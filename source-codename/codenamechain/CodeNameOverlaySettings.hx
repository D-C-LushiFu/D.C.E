package codenamechain;

import Main as DCEMain;
import general.backend.ClientPrefs;
import general.objects.screen.MouseEffect;
import openfl.Lib;

/** Keeps the CNE Extra Setting and D.C.E.-owned overlay in sync. */
class CodeNameOverlaySettings
{
	public static function applyWatermarkScale(value:Float, persist:Bool = true):Void
	{
		value = Math.max(0, Math.min(5, value));
		ClientPrefs.data.watermarkScale = value;

		if (DCEMain.watermark != null) {
			DCEMain.watermark.scaleX = DCEMain.watermark.scaleY = value;
			DCEMain.watermark.y = Lib.current.stage.stageHeight - 5
				- DCEMain.watermark.scaleY * DCEMain.watermark.bitmapData.height;
		}

		if (persist) ClientPrefs.saveSettings();
	}

	public static function applyMouseEffects(value:Bool):Void
	{
		MouseEffect.setUserEffectsEnabled(value);
	}
}
