package states.freeplayState.objects;

import openfl.geom.Matrix;
import flixel.graphics.frames.FlxFrame.FlxFrameAngle;

/** Geometric italic works with regular TTFs on native OpenFL as well as web. */
class PhiItalicText extends FlxText
{
    var shearMatrix:Matrix = new Matrix();
    override public function isSimpleRender(?camera:FlxCamera):Bool return false;
    override function drawComplex(camera:FlxCamera):Void
    {
        _frame.prepareMatrix(_matrix, FlxFrameAngle.ANGLE_0, checkFlipX(), checkFlipY());
        shearMatrix.setTo(1, 0, -PhiPanel.SLOPE, 1, height * PhiPanel.SLOPE, 0);
        _matrix.concat(shearMatrix);
        _matrix.translate(-origin.x, -origin.y);
        _matrix.scale(scale.x, scale.y);
        getScreenPosition(_point, camera).subtractPoint(offset).subtractPoint(_graphicOffset);
        _point.add(origin.x, origin.y);
        _matrix.translate(_point.x, _point.y);
        camera.drawPixels(_frame, framePixels, _matrix, colorTransform, blend, true, shader);
    }
}
