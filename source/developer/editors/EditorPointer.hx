package developer.editors;

import flixel.FlxG;
import flixel.FlxCamera;
import flixel.math.FlxPoint;

/** One press in the UI camera; a real touch takes priority over its emulated mouse. */
class EditorPointer
{
	static var activeTouchId:Int = -1;
	static var lastTouchX:Float = 0;
	static var lastTouchY:Float = 0;

	public static function position(camera:FlxCamera):{x:Float, y:Float}
	{
		var touch = findTouch();
		if (touch != null)
		{
			var point = touch.getViewPosition(camera);
			lastTouchX = point.x;
			lastTouchY = point.y;
			activeTouchId = touch.touchPointID;
			var result = {x: point.x, y: point.y};
			point.put();
			return result;
		}
		var mouse = FlxG.mouse.getViewPosition(camera);
		var result = {x: mouse.x, y: mouse.y};
		mouse.put();
		return result;
	}

	public static function pressed():Bool
	{
		if (FlxG.mouse.pressed) return true;
		for (touch in FlxG.touches.list) if (touch != null && touch.pressed) { activeTouchId = touch.touchPointID; return true; }
		return false;
	}

	public static function justPressedNow():Bool
	{
		if (FlxG.mouse.justPressed) return true;
		for (touch in FlxG.touches.list) if (touch != null && touch.justPressed) { activeTouchId = touch.touchPointID; return true; }
		return false;
	}

	public static function justReleased():Bool
	{
		if (FlxG.mouse.justReleased) return true;
		for (touch in FlxG.touches.list) if (touch != null && touch.justReleased) { activeTouchId = touch.touchPointID; return true; }
		return false;
	}

	public static function wheel():Int return FlxG.mouse.wheel;

	static function findTouch():Dynamic
	{
		for (touch in FlxG.touches.list)
			if (touch != null && (touch.pressed || touch.justPressed || touch.justReleased)) return touch;
		return null;
	}

	public static function justPressed(camera:FlxCamera, ?hit:Float->Float->Bool):Null<{x:Float, y:Float, id:Int}>
	{
		for (touch in FlxG.touches.list)
			if (touch != null && touch.justPressed)
			{
				var point = touch.getViewPosition(camera);
				var result = {x: point.x, y: point.y, id: touch.touchPointID};
				point.put();
				if (hit == null || hit(result.x, result.y)) return result;
			}
		if (FlxG.mouse.justPressed)
		{
			var point = FlxG.mouse.getViewPosition(camera);
			var result = {x: point.x, y: point.y, id: -1};
			point.put();
			if (hit == null || hit(result.x, result.y)) return result;
		}
		return null;
	}

	public static function held(camera:FlxCamera, id:Int):Null<{x:Float, y:Float}>
	{
		if (id == -1 && FlxG.mouse.pressed)
		{
			var point = FlxG.mouse.getViewPosition(camera);
			var result = {x: point.x, y: point.y};
			point.put();
			return result;
		}
		for (touch in FlxG.touches.list)
			if (touch.touchPointID == id && touch.pressed)
			{
				var point = touch.getViewPosition(camera);
				var result = {x: point.x, y: point.y};
				point.put();
				return result;
			}
		return null;
	}
}
