package originfunkin;

import mobile.backend.SUtil;

#if android
import android.Tools;
#end

/**
 * Native notices used by the Origin frontend.
 *
 * Android keeps the engine's native AlertDialog implementation. Desktop uses
 * D.C.E.'s standard SUtil popup so Origin notices match the rest of the game.
 */
class OriginFunkinDialog
{
	static inline final ORIGIN_TITLE:String = "D.C.E. x Friday Night Funkin' 0.8.4";
	static final ORIGIN_NOTICE:String =
		"You are playing the original FNF through D.C.E.\n\n"
		+ "This build is based on FNF 0.8.4, but it differs from the official game. "
		+ "If something breaks here, please do not report it to the Funkin' Crew.";

	static inline final MOD_TITLE:String = "Mod compatibility warning";

	public static function showOriginNotice(onContinue:Void->Void):Void
	{
		#if android
		Tools.showAlertDialog(ORIGIN_TITLE, ORIGIN_NOTICE, {
			name: "CONTINUE",
			func: onContinue
		});
		#else
		SUtil.showPopUp(ORIGIN_NOTICE, ORIGIN_TITLE);
		onContinue();
		#end
	}

	public static function showModWarning(modRoot:String, onEnable:Void->Void, onCancel:Void->Void):Void
	{
		var message:String =
			"This build uses D.C.E.'s haxelib set, which differs from the official FNF build. "
			+ "Compatible mods are not guaranteed to run perfectly.\n\n"
			+ "Mod folder:\n"
			+ modRoot;

		#if android
		Tools.showAlertDialog(MOD_TITLE, message, {
			name: "ENABLE",
			func: onEnable
		}, {
			name: "CANCEL",
			func: onCancel
		});
		#else
		SUtil.showPopUp(message, MOD_TITLE);
		onEnable();
		#end
	}
}
