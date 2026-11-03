package developer.display;

/* author: D.C.LushiFu */

import openfl.events.Event;

class FPSViewer extends Sprite
{
	public function new(x:Float = 10, y:Float = 10)
	{
		super();

		this.x = x;
		this.y = y;

		create();

		scaleX = scaleY = ClientPrefs.data.fpsScale;
		visible = ClientPrefs.data.showFPS;
	}

	public static var fpsShow:FPSCounter;
	public static var extraShow:ExtraCounter;

	public var isHiding = false;

	function create()
	{
		fpsShow = new FPSCounter(10, 10);
		addChild(fpsShow);
		fpsShow.update();

		extraShow = new ExtraCounter(10, 10);
		addChild(extraShow);
		extraShow.update();

		addEventListener(Event.ENTER_UPDATE, update);
		addEventListener(Event.ENTER_FRAME, draw);

		// 默认显示「新版」展开态（Update/Draw/Memory 详情 + 图形监视），
		// 点击左上角可折叠回「旧版」轻量数字。由 hide() 按 isHiding 统一
		// 初始化两个计数器的 alpha 与 graphMonitor 渲染/输入开关。
		hide();
	}

	public var canPress:Bool = true;
	private var lastToggleStamp:Float = -1;
	
	private function update(e:Event):Void
	{
		// Count the event that actually advances Flixel. Native scheduler wakeups
		// which never reach Stage are deliberately excluded.
		DataCalc.update();

		// Hit-testing allocates a transformed Point and walks the display matrix.
		// Only do it for the single update that actually contains a click instead
		// of doing that work at the full (up to 2000 Hz) update rate.
		if (canPress && FlxG.mouse.justPressed && isPointInFPSCounter())
		{
			var now:Float = haxe.Timer.stamp();
			// ENTER_UPDATE can be dispatched more than once while Flixel still
			// exposes the same justPressed edge at very high scheduler rates. One
			// physical click must create/dispose the graph surface exactly once.
			if (lastToggleStamp < 0 || now - lastToggleStamp >= 0.25)
			{
				lastToggleStamp = now;
				isHiding = !isHiding;
				hide();
			}
		}

		// Restore the original lightweight counter cadence. Updating a TextField
		// on every 2000 Hz update event invalidates the whole Stage and turns the
		// counter itself into the dominant render workload.
		if (DataCalc.updateMember != 0)
			return;

		if (isHiding)
			fpsShow.update();
		else
			extraShow.update();

		this.x = 10 - FlxG.game.x;
		this.y = 10 - FlxG.game.y;
	}

	private function draw(e:Event)
	{
		// ENTER_FRAME is emitted only for a real OpenFL render pass.
		DataCalc.draw();
	}

	function hide():Void
	{
		if (isHiding)
		{
			extraShow.alpha = 0;
			extraShow.graphMonitor.setInputEnabled(false);
			extraShow.graphMonitor.setRenderingEnabled(false);
			fpsShow.alpha = 1;
		}
		else
		{
			extraShow.alpha = 1;
			extraShow.graphMonitor.setRenderingEnabled(true);
			extraShow.graphMonitor.setInputEnabled(true);
			extraShow.update();
			fpsShow.alpha = 0;
		}
	}

	private function isPointInFPSCounter():Bool
	{
		var target = isHiding ? fpsShow.bgSprite : extraShow.bgSprite;
		final stage = Lib.current.stage;
		// width/height are local to the bitmap and do not include FPSViewer's
		// fpsScale. Stage-space bounds include the complete parent transform.
		final bounds = target.getBounds(stage);
		return bounds.contains(stage.mouseX, stage.mouseY);
	}
}
