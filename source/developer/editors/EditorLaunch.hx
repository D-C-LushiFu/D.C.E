package developer.editors;

import flixel.FlxG;
import flixel.FlxState;
import general.backend.Paths;
import general.backend.Mods;
import developer.editors.WeekEditorState.WeekEditorFreeplayState;

/** Optional desktop entry point: --editor=stage (or another editor name). */
class EditorLaunch
{
	public static function fromArguments():FlxState
	{
		#if sys
		var requested:String = null;
		var mod:String = null;
		for (arg in Sys.args())
		{
			if (StringTools.startsWith(arg, '--editor=')) requested = arg.substr(9).toLowerCase();
			if (StringTools.startsWith(arg, '--editor-mod=')) mod = arg.substr(13);
		}
		if (requested == null) return null;
		if (mod != null) Mods.currentModDirectory = mod;
		var state:FlxState = switch (requested)
		{
			case 'menu': new MasterEditorMenu();
			case 'chart': new ChartingState();
			case 'camera': new CameraEditorLaunchState();
			case 'character': new CharacterEditorState();
			case 'stage': new StageEditorState();
			case 'week': new WeekEditorState();
			case 'week-freeplay': new WeekEditorFreeplayState();
			case 'menu-character': new MenuCharacterEditorState();
			case 'dialogue': new DialogueEditorState();
			case 'portrait': new DialogueCharacterEditorState();
			case 'splash': new NoteSplashEditorState();
			default: null;
		};
		if (state != null)
		{
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
			trace('[EditorLaunch] ' + requested);
		}
		return state;
		#else
		return null;
		#end
	}
}
