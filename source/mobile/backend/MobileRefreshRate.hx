package mobile.backend;

/** Requests Android's display mode separately from the engine's render cap. */
class MobileRefreshRate
{
	public static function apply(framesPerSecond:Int):Void
	{
		#if android
		try
		{
			android.jni.JNICache.createStaticMethod('org/dce/display/RefreshRateExtension', 'setTargetFrameRate', '(I)V')(framesPerSecond);
		}
		catch (error:Dynamic)
		{
			trace('[display] Could not request Android refresh rate: $error');
		}
		#end
	}
}
