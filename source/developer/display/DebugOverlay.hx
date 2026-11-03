package developer.display;

import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldAutoSize;
import openfl.Lib;

/**
 * 游戏内调试面板（DebugOverlay）——**看得见**的那一份。
 *
 * 为什么放在 openfl 层而不是 flixel 层：
 *   - 它要**跨状态存活**（切界面、软重启都在），挂到状态上会随状态销毁；
 *   - 挂在 `Lib.current.stage` 顶层，不受相机滚动/缩放/滤镜影响，也不会被游戏画面重绘覆盖；
 *   - 引擎里已有同类先例：`source/general/objects/ReplayOverlay.hx`（openfl Sprite + TextField）。
 *
 * 显示位置：**贴屏幕右缘的一条竖栏**（不挡中间画面），可用 `setSide()` 换边、
 *          用 `NF_DEBUG_OVERLAY_SIDE=right|left` 在启动时选择。
 *
 * 内容：FPS / APP MEM（与引擎自带调试显示同一口径）/ GC 各代占用 /
 *       当前界面的类名与 .hx 文件 / 鼠标坐标与按键 / 最近按键 / 图形·声音·补间计数。
 *
 * 数据来源：`DebugMonitor.lines()`（每 0.2s 刷新一次）。
 */
class DebugOverlay extends Sprite
{
	static inline var MARGIN:Int = 8;
	static inline var PAD:Int = 8;

	var titleField:TextField;
	var bodyField:TextField;
	var bg:Shape;
	var panelW:Int = 430;
	/** 0=贴右缘 1=贴左缘 */
	public var side:Int = 0;

	var shown:Bool = true;
	var lastW:Int = 0;
	var lastH:Int = 0;

	public function new()
	{
		super();

		// 只做显示，不吃输入
		this.mouseEnabled = false;
		this.mouseChildren = false;

		try
		{
			var s:String = Sys.getEnv('NF_DEBUG_OVERLAY_SIDE');
			if (s != null && s.toLowerCase() == 'left') side = 1;
		}
		catch (e:Dynamic) {}
		// 面板宽度可配（窄屏/大分辨率都用得上）
		try
		{
			var w:String = Sys.getEnv('NF_DEBUG_OVERLAY_W');
			if (w != null && w.length > 0)
			{
				var v:Int = Std.parseInt(w);
				if (v >= 220 && v <= 1200) panelW = v;
			}
		}
		catch (e:Dynamic) {}

		bg = new Shape();
		addChild(bg);

		titleField = makeField(0x9ADCFF, true);
		addChild(titleField);

		bodyField = makeField(0xD2E1F0, false);
		addChild(bodyField);

		refresh('D.C.E. DebugMonitor', '(waiting for data...)');
	}

	function makeField(color:Int, bold:Bool):TextField
	{
		var t = new TextField();
		t.selectable = false;
		t.mouseEnabled = false;
		t.multiline = true;
		t.wordWrap = false;
		t.autoSize = TextFieldAutoSize.NONE;
		var f = new TextFormat('Consolas', 13, color);
		f.bold = bold;
		t.defaultTextFormat = f;
		t.setTextFormat(f);
		return t;
	}

	public function setShown(v:Bool):Void
	{
		shown = v;
		this.visible = v;
	}

	public function isShown():Bool return shown;

	/** 数据刷新（由 DebugMonitor 每 0.2s 调用一次） */
	public function refresh(title:String, body:String):Void
	{
		if (!shown) return;

		var stageW:Int = 0;
		var stageH:Int = 0;
		try
		{
			stageW = Lib.current.stage.stageWidth;
			stageH = Lib.current.stage.stageHeight;
		}
		catch (e:Dynamic) {}

		titleField.text = title;
		titleField.width = panelW - PAD * 2;
		titleField.x = PAD;
		titleField.y = PAD;

		bodyField.text = body;
		bodyField.width = panelW - PAD * 2;
		bodyField.x = PAD;
		bodyField.y = PAD + titleField.height + 4;

		var contentH:Int = Std.int(bodyField.y + bodyField.height + PAD);
		if (contentH < 120) contentH = 120;

		// 背景
		bg.graphics.clear();
		bg.graphics.beginFill(0x0A0C12, 0.82);
		bg.graphics.drawRect(0, 0, panelW, contentH);
		bg.graphics.endFill();
		bg.graphics.lineStyle(1, 0x2A3A52, 0.9);
		bg.graphics.drawRect(0, 0, panelW, contentH);

		this.x = (side == 0) ? (stageW - panelW - MARGIN) : MARGIN;
		this.y = MARGIN;

		lastW = stageW;
		lastH = stageH;
	}

	/** 分辨率变化时重新贴边 + **每帧把自己提到 stage 最顶层**（否则会被游戏画面盖住） */
	private override function __enterFrame(deltaTime:Float):Void
	{
		if (!shown) return;
		try
		{
			var st = Lib.current.stage;
			// flixel 的 FlxGame 也是挂在 stage 上的；addChild 顺序决定谁在上层。
			// 这里每帧确认自己在最后一个（最上），切状态/重建显示树后都不会被压下去。
			if (st != null && st.getChildIndex(this) != st.numChildren - 1)
				st.setChildIndex(this, st.numChildren - 1);
		}
		catch (e:Dynamic) {}

		try
		{
			var stageW:Int = Lib.current.stage.stageWidth;
			var stageH:Int = Lib.current.stage.stageHeight;
			if (stageW != lastW || stageH != lastH)
			{
				this.x = (side == 0) ? (stageW - panelW - MARGIN) : MARGIN;
				this.y = MARGIN;
				lastW = stageW;
				lastH = stageH;
			}
		}
		catch (e:Dynamic) {}
	}
}
