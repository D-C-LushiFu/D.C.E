package states.freeplayState.objects;

import lime.media.AudioBuffer;
import lime.media.openal.AL;

/** Buffers decoded exclusively for a preview, never shared with Paths' cache. */
class PhiPreviewBuffers
{
    /** Upload the owned PCM on the media worker, before publishing any channel. */
    public static function preparePlayback(buffer:AudioBuffer):Void
    {
        #if (lime_cffi && lime_openal && !macro)
        if (buffer == null || buffer.data == null) return;
        @:privateAccess if (buffer.__srcBuffer != null) return;
        var format = switch ([buffer.channels, buffer.bitsPerSample]) {
            case [1, 8]: AL.FORMAT_MONO8;
            case [1, 16]: AL.FORMAT_MONO16;
            case [2, 8]: AL.FORMAT_STEREO8;
            case [2, 16]: AL.FORMAT_STEREO16;
            default: return; // Leave other formats to Lime's playback backend.
        };
        var handle = AL.createBuffer();
        if (handle == null) throw 'Cannot allocate preview playback buffer';
        try {
            AL.bufferData(handle, format, buffer.data, buffer.data.length, buffer.sampleRate);
            @:privateAccess buffer.__srcBuffer = handle;
        } catch (error:Dynamic) {
            AL.deleteBuffer(handle);
            throw error;
        }
        #end
    }

    public static function release(buffer:AudioBuffer):Void
    {
        if (buffer == null) return;
        // The caller must detach all sound channels and FFT readers first.
        // Native AudioBuffer.dispose() does not release its uploaded AL buffer.
#if lime_vorbis
        @:privateAccess if (buffer.__srcVorbisFile != null) {
            buffer.__srcVorbisFile.clear();
            buffer.__srcVorbisFile = null;
        }
#end
        #if (lime_cffi && lime_openal && !macro)
        @:privateAccess {
            if (buffer.__srcBuffer != null) {
                AL.deleteBuffer(buffer.__srcBuffer);
                buffer.__srcBuffer = null;
            }
        }
        #end
        buffer.dispose();
        buffer.data = null;
    }

    public static function releaseAll(buffers:Array<AudioBuffer>):Void
    {
        for (buffer in buffers) release(buffer);
        buffers.resize(0);
    }

    public static function decodedBytes(buffers:Array<AudioBuffer>):Float
    {
        var total:Float = 0;
        for (buffer in buffers)
            if (buffer != null && buffer.data != null) total += buffer.data.length;
        return total;
    }

    public static function streamedCount(buffers:Array<AudioBuffer>):Int
    {
        var total = 0;
        for (buffer in buffers)
            if (buffer != null) {
                @:privateAccess if (buffer.__srcVorbisFile != null) total++;
            }
        return total;
    }
}
