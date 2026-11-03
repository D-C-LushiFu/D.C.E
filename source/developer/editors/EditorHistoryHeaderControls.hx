package developer.editors;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import general.backend.language.Language;
import general.backend.Paths;

/** History actions occupy the free area of the existing top menu bar. */
class EditorHistoryHeaderControls extends FlxSpriteGroup
{
	var actions:Array<Void->Void>;
	var enabled:Array<Void->Bool>;
	var labels:Array<EditorText> = [];
	var hits:Array<FlxSprite> = [];
	var barWidth:Int;
	var barHeight:Int;

	public function new(actions:Array<Void->Void>, enabled:Array<Void->Bool>)
	{
		super();
		this.actions = actions;
		this.enabled = enabled;
		barWidth = EditorInputStyle.si(224);
		barHeight = EditorInputStyle.si(36);
		var menu:Dynamic = Reflect.field(FlxG.state, 'menuBar');
		var items:Array<Dynamic> = menu == null ? null : cast Reflect.field(menu, 'menus');
		x = items == null ? EditorInputStyle.si(12) : EditorInputStyle.si(items.length * 88);
		y = 0;
		var keys = ['history_undo', 'history_redo', 'history_open'];
		var widths = [64, 64, 96];
		var left:Float = 0;
		for (i in 0...keys.length)
		{
			var width = EditorInputStyle.si(widths[i]);
			var hit = new FlxSprite(left, 0).makeGraphic(width, barHeight, 0xFFFFFFFF);
			hit.color = 0xFF1C1F28;
			add(hit);
			hits.push(hit);
			var label = new EditorText(left, 0, width, Language.get(keys[i], 'editors'), 14);
			label.setFormat(Paths.font(EditorInputStyle.langFontFileName()), 14, 0xFFC9CDD4, CENTER);
			label.y = (barHeight - label.height) / 2;
			add(label);
			labels.push(label);
			left += width;
		}
		scrollFactor.set();
	}

	public function containsPoint(px:Float, py:Float):Bool
		return visible && px >= x && px < x + barWidth && py >= y && py < y + barHeight;

	override public function update(elapsed:Float):Void
	{
		var mouse = FlxG.mouse.getViewPosition(cameras[0]);
		for (i in 0...labels.length)
		{
			var available = enabled[i]();
			labels[i].alpha = available ? 1 : 0.4;
			hits[i].color = available && mouse.x >= hits[i].x && mouse.x < hits[i].x + hits[i].width
				&& mouse.y >= y && mouse.y < y + barHeight ? 0xFF303448 : 0xFF1C1F28;
		}
		mouse.put();
		var point = EditorPointer.justPressed(cameras[0], containsPoint);
		if (point != null)
			for (i in 0...hits.length)
				if (point.x >= hits[i].x && point.x < hits[i].x + hits[i].width && enabled[i]())
				{
					actions[i]();
					break;
				}
		super.update(elapsed);
	}
}
