package general.backend;

import flixel.FlxG;
import flixel.input.keyboard.FlxKey;

/** Shared key capture for the settings screen and editor key binding panels. */
class KeyBindingCapture
{
	public static function firstKey():Int return FlxG.keys.firstJustPressed();

	public static function chord():String
	{
		var key:FlxKey = cast firstKey();
		if(key == NONE || key == CONTROL || key == SHIFT || key == ALT) return null;
		var result = '';
		if(FlxG.keys.pressed.CONTROL) result += 'CTRL+';
		if(FlxG.keys.pressed.SHIFT) result += 'SHIFT+';
		if(FlxG.keys.pressed.ALT) result += 'ALT+';
		return result + key.toString();
	}
}
