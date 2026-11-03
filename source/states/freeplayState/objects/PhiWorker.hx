package states.freeplayState.objects;

import sys.thread.Deque;
import sys.thread.Thread;

/** Haxe-managed threads keep Freeplay callbacks registered with hxcpp's GC. */
class PhiWorker
{
    static var interactive:Deque<Void->Void>;
    static var ratings:Deque<Void->Void>;
    static var media:Deque<Void->Void>;
    static var background:Deque<Void->Void>;
    #if cpp
    static var pressureMutex = new sys.thread.Mutex();
    static var lastPressureRequest:Float = 0;
    static var lastIdleCheck:Float = 0;
    #end

    /** Released full-song PCM can otherwise wait through several more decodes.
     * Collect only under pressure, after dropping the completed job.
     * The native collector still has a safepoint pause; this is not a promise
     * of pause-free GC and must never be called once per UI frame.
     */
    static function collectReleasedData(minimumInterval:Float = 1.5):Void
    {
        #if cpp
        if (Sys.getEnv('DCE_FREEPLAY_CHECK_NO_PRESSURE') == '1') return;
        if (cpp.vm.Gc.memInfo64(0) < 256 * 1048576) return;
        var now = haxe.Timer.stamp();
        pressureMutex.acquire();
        var request = now - lastPressureRequest >= minimumInterval;
        if (request) lastPressureRequest = now;
        pressureMutex.release();
        // __hxcpp_gc_request_full in the bundled runtime only sets its pause
        // flag; it does not start a collector and can leave every thread waiting.
        // Gc.run starts collection and coordinates the native safepoints.
        if (request) cpp.vm.Gc.run(true);
        #end
    }

    /** Freeplay can sit idle after its one-time load, so no worker completion
     * would otherwise trigger pressure collection. Check at most once a second
     * and collect at most every five seconds while the managed heap is large. */
    public static function collectIdlePressure():Void
    {
        #if cpp
        var now = haxe.Timer.stamp();
        if (now - lastIdleCheck < 1) return;
        lastIdleCheck = now;
        collectReleasedData(5);
        #end
    }

    public static function runBackground(job:Void->Void):Void
    {
        if (background == null)
        {
            background = new Deque<Void->Void>();
            var workerQueue = background;
            Thread.create(function():Void
            {
                while (true)
                {
                    var task = workerQueue.pop(true);
                    try task() catch (error:Dynamic) trace('FREEPLAY BACKGROUND WORKER: ' + error);
                    task = null;
                    collectReleasedData();
                }
            });
        }
        background.push(job);
    }

    public static function run(job:Void->Void, warmup:Bool = false, audio:Bool = false):Void
    {
        var queue = audio ? media : warmup ? ratings : interactive;
        if (queue == null)
        {
            queue = new Deque<Void->Void>();
            if (audio) media = queue; else if (warmup) ratings = queue; else interactive = queue;
            var workerQueue = queue;
            Thread.create(function():Void
            {
                while (true)
                {
                    var task = workerQueue.pop(true);
                    try task() catch (error:Dynamic) trace('FREEPLAY WORKER: ' + error);
                    task = null;
                    collectReleasedData();
                }
            });
        }
        queue.push(job);
    }
}
