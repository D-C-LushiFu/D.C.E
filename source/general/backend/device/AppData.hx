package general.backend.device;

// make Sscript can check those data
#if android
import android.os.AppDetails;
import lime.system.JNI;

class AppData
{
	public static function getVersionName():String
	{
		return AppDetails.getVersionName();
	}

	public static function getVersionCode():Int
	{
		return AppDetails.getVersionCode();
	}

	public static function getPackageName():String
	{
		return AppDetails.getPackageName();
	}

	public static function getAppName():String
	{
		return AppDetails.getAppName();
	}
	
	public static function verifySignature():Bool
	{
		return AppDetails.verifySignature() || DceSignatureVerifier.verifySignature();
	}
}

private class DceSignatureVerifier
{
	private static final verifyMethod = JNI.createStaticMethod(
		"org/novaflare/security/DceSignatureVerifier",
		"verifySignature",
		"()Z"
	);

	public static function verifySignature():Bool
	{
		return verifyMethod();
	}
}
#end
