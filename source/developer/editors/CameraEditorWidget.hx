package developer.editors;

import flixel.FlxG;
import flixel.FlxBasic;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import general.backend.Paths;
import general.backend.language.Language;
import general.backend.cameraeditor.CameraEditorData;
import general.backend.ui.PsychUIButton;
import general.backend.ui.PsychUICheckBox;
import general.backend.ui.PsychUIInputText;
import general.backend.ui.PsychUINumericStepper;
import general.backend.ui.PsychUIDropDownMenu;

/** The Psych widgets supply values and text editing only; this layer owns all drawing and mouse input. */
class CameraEditorWidget extends FlxSpriteGroup
{
	public static var inputConsumed:Bool = false;
	static var expanded:CameraEditorWidget;
	public var source:FlxBasic;
	public var canInteract:Void->Bool;
	public var dialogTag:String = '';
	var body:FlxSprite;
	var border:FlxSprite;
	var label:FlxText;
	var trailing:FlxText;
	var popup:FlxSpriteGroup;
	var popupBg:FlxSprite;
	var popupLabels:Array<FlxText> = [];
	var firstOption:Int = 0;
	var w:Float = 100;
	var h:Float = 30;
	var sx:Float;
	var sy:Float;
	var popupY:Float;
	var popupRows:Int;

	public function new(model:FlxBasic)
	{
		super();
		source = model;
		model.active = false;
		(cast model:FlxSpriteGroup).alpha = 0;
		border = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		body = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		label = text();
		trailing = text();
		trailing.alignment = RIGHT;
		add(border); add(body); add(label); add(trailing);
		popup = new FlxSpriteGroup();
		popupBg = new FlxSprite().makeGraphic(1, 1, 0xFF232734);
		popup.add(popupBg);
		for(i in 0...10) { var t = text(); popup.add(t); popupLabels.push(t); }
		scrollFactor.set();
	}

	function text():FlxText
	{
		var t = new FlxText(0, 0, 100, '', 11);
		t.setFormat(Paths.font(Language.get('fontName', 'main') + '.ttf'), 11, 0xFFF2F3F5);
		t.textField.wordWrap = false;
		t.textField.multiline = false;
		t.scrollFactor.set();
		return t;
	}

	static function rect(s:FlxSprite, x:Float, y:Float, width:Float, height:Float, color:FlxColor):Void
	{
		s.setPosition(x, y);
		s.scale.set(Math.max(1, width), Math.max(1, height));
		s.origin.set(0, 0);
		s.offset.set(0, 0);
		s.color = color;
	}

	public static function display(value:String):String
	{
		return switch(value)
		{
			case 'boyfriend': '玩家'; case 'dad': '对手'; case 'girlfriend': '女友'; case 'pos': '指定坐标';
			case 'Stage': '相对舞台'; case 'Absolute': '绝对缩放';
			case 'linear': '线性'; case 'INSTANT': '瞬间'; case 'CLASSIC': '经典';
			case 'In': '缓入'; case 'Out': '缓出'; case 'InOut': '缓入缓出';
			case 'sine': '正弦'; case 'quad': '二次'; case 'cube': '三次'; case 'quart': '四次';
			case 'quint': '五次'; case 'expo': '指数'; case 'elastic': '弹性'; case 'back': '回弹';
			case 'bounce': '弹跳'; case 'circ': '圆形'; case 'smoothStep': '平滑'; case 'smootherStep': '更平滑';
			default: CameraEditorData.displayEventName(value);
		}
	}

	public static function beginFrame():Void
	{
		inputConsumed = false;
		if(expanded != null)
		{
			if(!expanded.source.exists || !expanded.source.visible || (expanded.canInteract != null && !expanded.canInteract())) expanded = null;
			else expanded.updatePopupInput();
		}
		var focused = PsychUIInputText.focusOn;
		if(focused != null && (!focused.visible || (EditorPointer.justPressedNow() && !inputConsumed)))
		{
			var mp = EditorPointer.position(focused.camera);
			if(!focused.visible || mp.x < focused.x || mp.x > focused.x + focused.fieldWidth || mp.y < focused.y || mp.y > focused.y + 30)
				PsychUIInputText.focusOn = null;
		}
	}

	override public function update(elapsed:Float):Void
	{
		visible = source != null && source.exists && source.visible;
		if(!visible) return;
		var model:FlxSpriteGroup = cast source;
		sx = model.x; sy = model.y;
		var value = '';
		var suffix = '';
		var button:PsychUIButton = Std.isOfType(source, PsychUIButton) ? cast source : null;
		var check:PsychUICheckBox = Std.isOfType(source, PsychUICheckBox) ? cast source : null;
		var input:PsychUIInputText = Std.isOfType(source, PsychUIInputText) ? cast source : null;
		var stepper:PsychUINumericStepper = Std.isOfType(source, PsychUINumericStepper) ? cast source : null;
		var dropdown:PsychUIDropDownMenu = Std.isOfType(source, PsychUIDropDownMenu) ? cast source : null;
		var touchSized:Bool = #if android dialogTag == '' #else false #end;
		h = button != null ? Math.max(touchSized ? 44 : 24, button.bg.height) : (touchSized ? 44 : 30);
		if(button != null) { w = button.bg.width; value = button.label; }
		else if(check != null) { w = check.text.fieldWidth; value = (check.checked ? '[x]  ' : '[ ]  ') + check.label; }
		else if(input != null)
		{
			w = dropdown != null ? input.bg.width : input.fieldWidth + (stepper != null ? 32 : 2);
			value = dropdown != null ? display(input.text) : input.text;
			if(dropdown != null) suffix = 'v';
			if(stepper != null) suffix = '-     +';
			if(PsychUIInputText.focusOn == input && haxe.Timer.stamp() % 1 < 0.5) value += '|';
		}
		if(value == null) value = '';
		var mp = EditorPointer.position(camera);
		var hover = mp.x >= sx && mp.x <= sx + w && mp.y >= sy && mp.y <= sy + h;
		var focused = input != null && PsychUIInputText.focusOn == input;
		rect(border, sx, sy, w, h, focused ? 0xFF8B7AFF : 0xFF3C4354);
		rect(body, sx + 1, sy + 1, w - 2, h - 2, hover ? 0xFF33394B : (button != null ? 0xFF2A2E3A : 0xFF1B1F2B));
		var padding:Float = w < 60 ? 3 : 9;
		var textWidth = Math.max(1, w - (suffix == '' ? padding * 2 : (stepper != null ? 72 : 38)));
		if(label.fieldWidth != textWidth) label.fieldWidth = textWidth;
		label.textField.wordWrap = false;
		label.textField.multiline = false;
		label.text = value;
		label.setPosition(sx + padding, sy + (h - label.height) / 2);
		label.color = check != null && check.checked ? 0xFFB8ACFF : 0xFFF2F3F5;
		trailing.setPosition(sx + w - 62, sy + (h - trailing.height) / 2);
		if(trailing.fieldWidth != 54) trailing.fieldWidth = 54;
		trailing.textField.wordWrap = false;
		trailing.textField.multiline = false;
		trailing.text = suffix;
		var allowed = canInteract == null || canInteract();
		if(!inputConsumed && allowed && hover && EditorPointer.justPressedNow())
		{
			inputConsumed = true;
			if(button != null) { if(button.onClick != null) button.onClick(); }
			else if(check != null) { check.checked = !check.checked; if(check.onClick != null) check.onClick(); }
			else if(dropdown != null) { expanded = expanded == this ? null : this; firstOption = 0; }
			else if(stepper != null && mp.x >= sx + w - 62)
			{
				PsychUIInputText.focusOn = null;
				stepper.value += mp.x >= sx + w - 31 ? stepper.step : -stepper.step;
				if(stepper.onValueChange != null) stepper.onValueChange();
			}
			else if(input != null)
			{
				PsychUIInputText.focusOn = input;
				input.selectIndex = 0;
				input.caretIndex = input.text.length;
				input.updateCaret();
			}
		}
		if(!inputConsumed && allowed && hover && stepper != null && EditorPointer.wheel() != 0)
		{
			inputConsumed = true;
			stepper.value += stepper.step * EditorPointer.wheel();
			if(stepper.onValueChange != null) stepper.onValueChange();
		}
		if(expanded == this) layoutPopup();
	}

	function layoutPopup():Void
	{
		var dd:PsychUIDropDownMenu = cast source;
		var rowH:Float = #if android 44 #else 30 #end;
		popupRows = Std.int(Math.min(10, dd.list.length));
		popupY = Math.min(FlxG.height - popupRows * rowH - 8, sy + h + 3);
		rect(popupBg, sx, popupY, w, popupRows * rowH + 4, 0xFF232734);
		for(i in 0...popupLabels.length)
		{
			var t = popupLabels[i];
			t.visible = i < popupRows && firstOption + i < dd.list.length;
			if(!t.visible) continue;
			t.setPosition(sx + 10, popupY + i * rowH + 5);
			if(t.fieldWidth != w - 20) t.fieldWidth = w - 20;
			t.text = display(dd.list[firstOption + i]);
			t.color = dd.selectedIndex == firstOption + i ? 0xFFB8ACFF : FlxColor.WHITE;
		}
		popup.cameras = cameras;
	}

	function updatePopupInput():Void
	{
		var dd:PsychUIDropDownMenu = cast source;
		layoutPopup();
		var mp = EditorPointer.position(camera);
		if(EditorPointer.wheel() != 0)
		{
			firstOption = Std.int(Math.max(0, Math.min(Math.max(0, dd.list.length - popupRows), firstOption - EditorPointer.wheel())));
			inputConsumed = true;
		}
		if(FlxG.keys.justPressed.ESCAPE) { expanded = null; inputConsumed = true; }
		if(EditorPointer.justPressedNow())
		{
			inputConsumed = true;
			var rowH:Float = #if android 44 #else 30 #end;
			if(mp.x >= sx && mp.x <= sx + w && mp.y >= popupY && mp.y < popupY + popupRows * rowH)
			{
				var idx = firstOption + Std.int((mp.y - popupY) / rowH);
				if(idx >= 0 && idx < dd.list.length)
				{
					dd.selectedIndex = idx;
					if(dd.onSelect != null) dd.onSelect(idx, dd.list[idx]);
				}
			}
			expanded = null;
		}
	}

	public static function drawExpanded():Void
	{
		if(expanded != null && expanded.visible) expanded.popup.draw();
	}

	override public function destroy():Void
	{
		if(expanded == this) expanded = null;
		popup.destroy();
		source = null;
		super.destroy();
	}
}
