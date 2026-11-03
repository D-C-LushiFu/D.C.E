package states.freeplayState.objects;

import openfl.display.BitmapData;
import openfl.display.Shape;
import openfl.display.BitmapDataChannel;
import openfl.geom.Point;
import flixel.graphics.FlxGraphic;

/** All Freeplay edges use the same 15 degree shear, in logical game pixels. */
class PhiPanel extends FlxSprite
{
    public static inline final SLOPE:Float = 0.2679491924;
    /** Compatibility with option cards, which use this as inner padding. */
    public var mainRound:Float = 0;
    public var panelWidth(default, null):Int;
    public var panelHeight(default, null):Int;
    var mask:BitmapData;

    public function new(x:Float, y:Float, w:Int, h:Int, tint:FlxColor = FlxColor.WHITE)
    {
        super(x, y);
        panelWidth = w;
        panelHeight = h;
        var shape = new Shape();
        var g = shape.graphics;
        var inset = h * SLOPE;
        g.beginFill(0xFFFFFF);
        g.moveTo(inset, 0); g.lineTo(w, 0); g.lineTo(w - inset, h); g.lineTo(0, h); g.lineTo(inset, 0);
        g.endFill();
        mask = new BitmapData(w, h, true, 0);
        mask.draw(shape);
        loadGraphic(FlxGraphic.fromBitmapData(mask.clone(), false, null, false));
        color = tint;
        antialiasing = true;
    }

    public function contains(px:Float, py:Float):Bool
    {
        var dy = py - y;
        if (dy < 0 || dy > panelHeight) return false;
        var left = x + (panelHeight - dy) * SLOPE;
        return px >= left && px <= left + panelWidth - panelHeight * SLOPE;
    }

    public function installArtwork(source:BitmapData):Void
    {
        var bitmap = new BitmapData(panelWidth, panelHeight, true, 0);
        bitmap.copyPixels(source, source.rect, new Point());
        bitmap.copyChannel(mask, mask.rect, new Point(), BitmapDataChannel.ALPHA, BitmapDataChannel.ALPHA);
        loadGraphic(FlxGraphic.fromBitmapData(bitmap, false, null, false));
        color = FlxColor.WHITE;
    }

    override public function destroy():Void
    {
        super.destroy();
        if (mask != null) mask.dispose();
        mask = null;
    }
}
