package developer.editors;

import developer.editors.StageEditorMenuBar.StageItemType;
import developer.editors.StageEditorMenuBar.StageMenuDef;
import developer.editors.StageEditorMenuBar.StageMenuItemDef;

/** Camera Editor menus built on the Stage Editor's self-drawn menu system. */
class CameraEditorMenuBar extends StageEditorMenuBar
{
	public var shortcutProvider:String->String;
	public function new()
	{
		super();
		languageGroup = 'cameraEditor';
		applyLang();
		// CameraEditorState disables group updates and drives the menu bar
		// manually, so the status-bar child may not get its usual first update.
		// Place it below the menu immediately to keep its status text visible.
		if (statusBar != null) statusBar.y = StageEditorMenuBar.BAR_HEIGHT;
	}

	override public function createStatusBar():StageEditorStatusBar
	{
		return new CameraEditorStatusBar();
	}

	override public function buildMenus():Void
	{
		function command(action:String, key:String):StageMenuItemDef
		{
			return {
				type: StageItemType.Cmd,
				labelKey: key,
				descKey: 'desc_' + key,
				getChecked: null,
				onCheck: null,
				shortcut: shortcutProvider != null ? shortcutProvider(action) : defaultShortcut(action),
				onClick: function() if (onAction != null) onAction(action)
			};
		}

		var separator:StageMenuItemDef = {
			type: StageItemType.Sep,
			labelKey: null,
			descKey: null,
			getChecked: null,
			onCheck: null,
			onClick: null
		};

		menus = [
			{key: 'file', isTest: false, items: [
				command('save', 'save'),
				command('saveAs', 'save_as'),
				command('open', 'open_chart'),
				separator,
				command('exit', 'exit_editor')
			]},
			{key: 'edit', isTest: false, items: [
				command('undo', 'undo'), command('redo', 'redo'), separator,
				command('copy', 'copy'), command('cut', 'cut'), command('paste', 'paste'),
				command('duplicate', 'duplicate'), command('delete', 'delete'), command('selectAll', 'select_all'),
				separator, command('newEvent', 'new_event')
			]},
			{key: 'timeline', isTest: false, items: [
				command('playPause', 'play_pause'), command('goStart', 'go_start'),
				command('zoomIn', 'timeline_zoom_in'), command('zoomOut', 'timeline_zoom_out'),
				command('zoomReset', 'timeline_zoom_reset'), separator,
				command('addLayer', 'add_layer'), command('removeLayer', 'remove_layer'),
				command('moveLayerUp', 'move_layer_up'), command('moveLayerDown', 'move_layer_down')
			]},
			{key: 'camera', isTest: false, items: [
				command('focusDad', 'focus_opponent'), command('focusBf', 'focus_player'),
				command('focusGf', 'focus_girlfriend'), separator,
				command('resetCameraPosition', 'reset_camera_position'),
				command('resetCameraZoom', 'reset_camera_zoom'),
				command('toggleStrumPreview', 'toggle_strum_preview')
			]},
			{key: 'view', isTest: false, items: [
				command('togglePassepartout', 'toggle_passepartout'),
				command('toggleExtendedBounds', 'toggle_extended_bounds'),
				command('toggleShader', 'toggle_shader'),
				command('toggleHelp', 'show_help'),
				command('showKeybindings', 'show_keybindings')
			]},
			{key: 'help', isTest: false, items: [
				command('showHelp', 'show_help'),
				command('showKeybindings', 'show_keybindings')
			]}
		];
	}

	public static function defaultShortcut(action:String):String
	{
		return switch(action)
		{
			case 'save': 'Ctrl+S'; case 'saveAs': 'Ctrl+Shift+S'; case 'open': 'Ctrl+O'; case 'exit': 'Esc';
			case 'undo': 'Ctrl+Z'; case 'redo': 'Ctrl+Y'; case 'copy': 'Ctrl+C'; case 'cut': 'Ctrl+X';
			case 'paste': 'Ctrl+V'; case 'duplicate': 'Ctrl+D'; case 'delete': 'Delete'; case 'selectAll': 'Ctrl+A';
			case 'playPause': 'Space'; case 'goStart': 'Home'; case 'newEvent': 'N';
			case 'zoomIn': 'Ctrl+Shift+E'; case 'zoomOut': 'Ctrl+Shift+Q'; case 'addLayer': 'Ctrl+Shift+N';
			case 'focusDad': ','; case 'focusBf': '.';
			case 'resetCameraPosition': 'Ctrl+R'; case 'resetCameraZoom': 'Ctrl+G'; case 'toggleShader': 'G';
			case 'showHelp', 'toggleHelp': 'H'; default: '';
		}
	}
}
