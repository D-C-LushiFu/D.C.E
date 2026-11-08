package mobile.backend;

import flixel.FlxG;

/** Requests Android's display mode separately from the engine's render cap. */
class MobileRefreshRate
{
	static var focusRestoreInstalled:Bool = false;

	/** Re-apply Android's uncapped window scheduling after Flixel handles focus. */
	public static function installFocusRestore():Void
	{
		#if android
		if (focusRestoreInstalled) return;
		focusRestoreInstalled = true;
		FlxG.signals.focusGained.add(function()
		{
			// FlxGame rewrites Lime's window rates during its focus handler. Run
			// after that handler so Android keeps the high-refresh scheduling policy.
			haxe.Timer.delay(function()
			{
				if (FlxG.stage == null || FlxG.stage.application == null || FlxG.stage.application.window == null) return;
				var rate:Int = maximumWindowRate(Std.int(FlxG.drawFramerate));
				FlxG.stage.application.window.frameRate = rate;
				FlxG.stage.application.window.drawFrameRate = rate;
				FlxG.stage.application.window.lockRender = true;
				requestMaximum();
			}, 250);
		});
		#end
	}

	public static function maximumWindowRate(fallback:Int):Int
	{
		#if android
		try
		{
			var rate:Int = android.jni.JNICache.createStaticMethod('org/dce/display/RefreshRateExtension', 'getMaximumRefreshRate', '()I')();
			if (rate > 0) return rate;
		}
		catch (error:Dynamic)
		{
			trace('[display] Could not read Android maximum refresh rate: $error');
		}
		#end
		return fallback;
	}

	public static function requestMaximum():Void
	{
		#if android
		try
		{
			android.jni.JNICache.createStaticMethod('org/dce/display/RefreshRateExtension', 'requestMaximumRefreshRate', '()V')();
		}
		catch (error:Dynamic)
		{
			trace('[display] Could not request Android refresh rate: $error');
		}
		#end
	}
}
