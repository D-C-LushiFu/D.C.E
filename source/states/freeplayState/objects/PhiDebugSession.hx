package states.freeplayState.objects;

import states.freeplayState.FreeplayState;
import sys.io.File;
import flixel.FlxG;

/** Opt-in runtime stress check. Normal launches never construct this object. */
@:access(states.freeplayState.FreeplayState)
#if (cpp && windows)
@:cppFileCode('#include <windows.h>\n#include <psapi.h>\n#ifdef ERROR\n#undef ERROR\n#endif')
#end
class PhiDebugSession
{
    #if (cpp && windows)
    @:functionCode('PROCESS_MEMORY_COUNTERS_EX counters = {};
        counters.cb = sizeof(counters);
        if (K32GetProcessMemoryInfo(GetCurrentProcess(),
            reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&counters), sizeof(counters)))
            return static_cast<double>(counters.PrivateUsage);
        return 0;')
    static function privateMemoryBytes():Float { return 0; }
    #end
    var state:FreeplayState;
    static var started:Float = 0;
    static var nextStep:Float = 15;
    static var steps:Int = 0;
    static var lastReport:Int = -1;
    static var didReenter:Bool = false;
    var output:String;
    var idleOnly:Bool;
    var maxSteps:Int;
    var stepInterval:Float;
    var duration:Float;
    static var audioToggles:Int = 0;
    var lastFrame:Float = 0;
    var maxFrameMs:Float = 0;

    public function new(state:FreeplayState)
    {
        this.state = state;
        var firstEntry = started == 0;
        if (firstEntry) started = haxe.Timer.stamp();
        idleOnly = Sys.getEnv('DCE_FREEPLAY_CHECK') == 'idle';
        var stepSetting = Std.parseInt(Sys.getEnv('DCE_FREEPLAY_CHECK_STEPS'));
        maxSteps = stepSetting == null ? 30 : Std.int(Math.max(0, stepSetting));
        stepInterval = Std.parseFloat(Sys.getEnv('DCE_FREEPLAY_CHECK_INTERVAL'));
        if (!Math.isFinite(stepInterval) || stepInterval < 0.1) stepInterval = 2;
        duration = Std.parseFloat(Sys.getEnv('DCE_FREEPLAY_CHECK_SECONDS'));
        if (!Math.isFinite(duration) || duration < 20) duration = 95;
        output = Sys.getEnv('DCE_FREEPLAY_CHECK_OUTPUT');
        if (output != null && firstEntry) File.saveContent(output, 'seconds,steps,workingSetMB,privateMB,gcUsedMB,ownedBuffers,pcmMB,maxFrameMs\n');
        FlxG.autoPause = false;
        trace('FREEPLAY CHECK started: ' + (idleOnly ? 'idle' : maxSteps + ' switches') + ', no gameplay input');
    }

    public function update():Void
    {
        var now = haxe.Timer.stamp();
        var age = now - started;
        if (lastFrame != 0) maxFrameMs = Math.max(maxFrameMs, (now - lastFrame) * 1000);
        lastFrame = now;
        if (Sys.getEnv('DCE_FREEPLAY_CHECK') == 'reentry' && !didReenter && age >= duration - 50) {
            didReenter = true;
            trace('FREEPLAY CHECK reentering the same process');
            FlxG.resetState();
            return;
        }
        // Long stress runs also exercise the exact off/on action that was
        // reported to trigger flashes. Four toggles restore the initial state.
        if (maxSteps >= 120 && audioToggles < 4 && steps >= maxSteps
            && age >= 25 + maxSteps * stepInterval + audioToggles * 5) {
            state.runPhiTool('audio');
            audioToggles++;
        }
        if (!idleOnly && age >= nextStep && steps < maxSteps && state.phiSongOrder.length > 1)
        {
            var span = state.phiSongOrder.length - 1;
            state.stepPhiSong(Std.int(steps / span) % 2 == 0 ? 1 : -1);
            steps++;
            nextStep = age + stepInterval;
        }
        var second = Std.int(age);
        if (second != lastReport)
        {
            lastReport = second;
            var working:Float = 0, privateBytes:Float = 0, gc:Float = 0;
            #if cpp
            working = cpp.vm.Gc.memInfo64(4) / 1048576;
            #if windows
            privateBytes = privateMemoryBytes() / 1048576;
            #end
            gc = cpp.vm.Gc.memInfo64(0) / 1048576;
            #end
            var pcm = PhiPreviewBuffers.decodedBytes(state.previewAudioBuffers) / 1048576;
            var row = second + ',' + steps + ',' + working + ',' + privateBytes + ',' + gc
                + ',' + state.previewAudioBuffers.length + ',' + pcm + ',' + maxFrameMs + '\n';
            if (output != null) { var file = File.append(output); file.writeString(row); file.close(); }
            if (second % 10 == 0) trace('FREEPLAY CHECK ' + StringTools.trim(row));
            maxFrameMs = 0;
        }
        if (age >= duration) { trace('FREEPLAY CHECK completed'); Sys.exit(0); }
    }
}
