package states.freeplayState.objects;

import hxvlc.flixel.FlxVideoSprite;
import flixel.system.FlxAssets.FlxShader;

/** Looping, silent wallpaper; its lifetime belongs to the Freeplay view. */
class PhiVideoBackground extends FlxVideoSprite
{
    public function new()
    {
        super();
        antialiasing = true;
        shader = new PhiMonochromeShader();
        alpha = 0.55;
        bitmap.volumeAdjust = 0;
        bitmap.onFormatSetup.add(fitBackground);
        bitmap.onEncounteredError.add(reportError);
        // LibVLC decodes and uploads every wallpaper frame on the render path.
        // Keep an environment switch for memory/performance comparisons.
        #if sys
        var enableVideo = Sys.getEnv('DCE_FREEPLAY_VIDEO_BACKGROUND') != '0';
        #else
        var enableVideo = true;
        #end
        if (enableVideo && load(Paths.video('freeplay-background'), ['input-repeat=65535', 'no-audio']))
            play();
    }

    function fitBackground():Void
    {
        if (bitmap == null || bitmap.bitmapData == null) return;
        var factor = Math.max(1920 / bitmap.bitmapData.width, 1080 / bitmap.bitmapData.height);
        setGraphicSize(Math.ceil(bitmap.bitmapData.width * factor), Math.ceil(bitmap.bitmapData.height * factor));
        updateHitbox();
        setPosition((1920 - width) / 2, (1080 - height) / 2);
    }

    function reportError(message:String):Void { trace('FREEPLAY BACKGROUND: ' + message); }

    override public function destroy():Void
    {
        if (bitmap != null) {
            bitmap.stop();
            bitmap.onFormatSetup.remove(fitBackground);
            bitmap.onEncounteredError.remove(reportError);
        }
        super.destroy();
    }
}

private class PhiMonochromeShader extends FlxShader
{
    @:glFragmentSource('
    #pragma header
    void main() {
        vec4 pixel = flixel_texture2D(bitmap, openfl_TextureCoordv);
        float luminance = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
        gl_FragColor = vec4(vec3(luminance), pixel.a);
    }')
    public function new() { super(); }
}
