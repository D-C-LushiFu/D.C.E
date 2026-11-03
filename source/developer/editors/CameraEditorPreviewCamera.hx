package developer.editors;

import flixel.FlxCamera;
import flixel.FlxG;
import openfl.geom.Rectangle;

/** Preserve the gameplay projection/parallax while showing the scene around the output frame. */
@:access(flixel.FlxCamera)
class CameraEditorPreviewCamera extends FlxCamera
{
	var frameX:Float = 0;
	var frameY:Float = 0;
	var displayScale:Float = 0.55;
	var workspaceW:Float = 1280;
	var workspaceTop:Float = 60;
	var workspaceBottom:Float = 600;
	var expandedClip:Rectangle = new Rectangle();

	public function new(gameWidth:Int, gameHeight:Int)
	{
		super(0, 0, gameWidth, gameHeight, 1);
		bgColor = 0xFF12141A;
	}

	public function setWorkspace(fx:Float, fy:Float, scale:Float, right:Float, top:Float, bottom:Float):Void
	{
		frameX = fx; frameY = fy;
		displayScale = Math.max(0.05, scale);
		workspaceW = right; workspaceTop = top; workspaceBottom = bottom;
		applyWorkspace();
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		applyWorkspace();
	}

	function applyWorkspace():Void
	{
		if(flashSprite == null || _scrollRect == null) return;
		var screenX = FlxG.scaleMode.scale.x;
		var screenY = FlxG.scaleMode.scale.y;
		var padX = frameX / displayScale;
		var padY = (frameY - workspaceTop) / displayScale;
		flashSprite.scaleX = displayScale;
		flashSprite.scaleY = displayScale;
		flashSprite.x = (frameX + width * displayScale / 2) * screenX;
		flashSprite.y = (frameY + height * displayScale / 2) * screenY;
		expandedClip.setTo(-padX * screenX, -padY * screenY,
			workspaceW / displayScale * screenX, (workspaceBottom - workspaceTop) / displayScale * screenY);
		_scrollRect.scrollRect = expandedClip;
		_scrollRect.x = (-width / 2 - padX) * screenX;
		_scrollRect.y = (-height / 2 - padY) * screenY;
		// Culling must include the surrounding scene, too.
		viewMarginX = -Math.max(width, workspaceW / displayScale) / Math.max(0.05, zoom);
		viewMarginY = -Math.max(height, (workspaceBottom - workspaceTop) / displayScale) / Math.max(0.05, zoom);
	}
}
