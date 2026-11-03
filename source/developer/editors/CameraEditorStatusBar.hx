package developer.editors;

/** Camera Editor's status strip, using the Stage Editor's shared visual style. */
class CameraEditorStatusBar extends StageEditorStatusBar
{
	public function new()
	{
		super();
		languageGroup = 'cameraEditor';
		applyLang();
	}
}
