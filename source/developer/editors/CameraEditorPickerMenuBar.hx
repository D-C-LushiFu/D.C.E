package developer.editors;

import developer.editors.StageEditorMenuBar.StageItemType;
import developer.editors.StageEditorMenuBar.StageMenuItemDef;

/** Small song-picker header using the Stage Editor menu and status-bar skin. */
class CameraEditorPickerMenuBar extends StageEditorMenuBar
{
	public function new()
	{
		super();
		languageGroup = 'cameraEditor';
		applyLang();
	}

	override public function createStatusBar():StageEditorStatusBar
	{
		return new CameraEditorStatusBar();
	}

	override public function buildMenus():Void
	{
		var back:StageMenuItemDef = {
			type: StageItemType.Cmd,
			labelKey: 'picker_back',
			descKey: 'desc_picker_back',
			getChecked: null,
			onCheck: null,
			onClick: function() if (onAction != null) onAction('back')
		};
		menus = [{key: 'file', isTest: false, items: [back]}];
	}
}
