package mobile.objects;

import flixel.FlxBasic;
import flixel.FlxG;
import general.backend.MusicBeatState;

/** Plugins run after input sampling and before the editor reads keyboard shortcuts. */
class EditorMobileInputPlugin extends FlxBasic
{
	override public function update(elapsed:Float):Void
	{
		if (!Std.isOfType(FlxG.state, MusicBeatState)) return;
		var state:MusicBeatState = cast FlxG.state;
		EditorMobileKeys.frameUpdate(state);
		var overlay = state.editorMobileOverlay;
		if (overlay != null && overlay.visible && overlay.active) overlay.updateInput(elapsed);
	}
}
