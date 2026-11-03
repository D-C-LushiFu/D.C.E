package options.objects;

import openfl.display.BitmapData;
import openfl.display.Shape;
import flixel.graphics.FlxGraphic;
import states.freeplayState.objects.PhiPanel;

/**
 * A 15-degree Freeplay panel whose width and height can change without
 * stretching its diagonal edges. The two edge wedges scale from the current
 * panel height; the middle remains a plain quad.
 */
class ResizablePhiPanel extends FlxSpriteGroup
{
	static var leftGraphic:FlxGraphic;
	static var rightGraphic:FlxGraphic;

	final left:FlxSprite;
	final middle:FlxSprite;
	final right:FlxSprite;
	public var panelAlpha:Float = 0;

	public function new(color:FlxColor)
	{
		super();
		left = wedge(true);
		middle = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		right = wedge(false);
		for (part in [left, middle, right])
		{
			part.color = color;
			part.antialiasing = true;
			add(part);
		}
	}

	public function setRect(x:Float, y:Float, width:Float, height:Float):Void
	{
		var w:Float = Math.max(1, width);
		var h:Float = Math.max(1, height);
		var inset:Float = Math.min(h * PhiPanel.SLOPE, w * 0.5);
		place(left, x, y, inset, h);
		place(middle, x + inset, y, Math.max(1, w - inset * 2), h);
		place(right, x + w - inset, y, inset, h);
	}

	function wedge(isLeft:Bool):FlxSprite
	{
		var sprite = new FlxSprite();
		sprite.loadGraphic(isLeft ? getLeftGraphic() : getRightGraphic());
		return sprite;
	}

	static function getLeftGraphic():FlxGraphic
	{
		if (leftGraphic == null || leftGraphic.isDestroyed) leftGraphic = makeWedge(true);
		return leftGraphic;
	}

	static function getRightGraphic():FlxGraphic
	{
		if (rightGraphic == null || rightGraphic.isDestroyed) rightGraphic = makeWedge(false);
		return rightGraphic;
	}

	static function makeWedge(isLeft:Bool):FlxGraphic
	{
		// Keep the cached edge mask large enough for full-height panels. Freeplay's
		// PhiPanel rasterizes at the final dimensions; a 128px mask stretched to a
		// 1080px settings panel visibly softens its 15-degree edges.
		var size:Int = 1024;
		var shape = new Shape();
		var g = shape.graphics;
		g.beginFill(0xFFFFFF);
		if (isLeft)
		{
			g.moveTo(size, 0); g.lineTo(size, size); g.lineTo(0, size);
		}
		else
		{
			g.moveTo(0, 0); g.lineTo(size, 0); g.lineTo(0, size);
		}
		g.endFill();
		var bitmap = new BitmapData(size, size, true, 0);
		bitmap.draw(shape, null, null, null, null, true);
		var graphic = FlxGraphic.fromBitmapData(bitmap, true);
		graphic.persist = true;
		return graphic;
	}

	static inline function place(sprite:FlxSprite, x:Float, y:Float, w:Float, h:Float):Void
	{
		sprite.setPosition(x, y);
		sprite.origin.set(0, 0);
		sprite.scale.set(w / Math.max(1, sprite.frameWidth), h / Math.max(1, sprite.frameHeight));
		sprite.updateHitbox();
	}
}
