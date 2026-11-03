package mobile.backend;

#if (android && cpp && DCE_FRAME_AUDIT)
import general.backend.ClientPrefs;
import general.backend.gc.GCManager;
import lime.app.Application;
import sys.io.File;
import sys.io.FileOutput;

/** Opt-in telemetry for device investigations; excluded from ordinary builds. */
class AndroidFrameAudit {
	static var output:FileOutput;
	static var started:Float;
	static var sampled:Float;
	static var lastUpdate:Float = 0;
	static var updates:Int = 0;
	static var renders:Int = 0;
	static var updateMaxMs:Float = 0;
	static var observedGcMaxMs:Float = 0;

	public static function start():Void {
		if (output != null) return;
		output = File.write(lime.system.System.applicationStorageDirectory + 'android-frame-audit.ndjson');
		started = sampled = haxe.Timer.stamp();
		Application.current.onUpdate.add(sampleUpdate);
		Application.current.window.onRender.add(sampleRender);
	}

	static function sampleRender(context:lime.graphics.RenderContext):Void {
		renders++;
	}

	static function sampleUpdate(deltaTime:Float):Void {
		var now = haxe.Timer.stamp();
		updates++;
		if (lastUpdate > 0) updateMaxMs = Math.max(updateMaxMs, (now - lastUpdate) * 1000);
		lastUpdate = now;
		// This getter holds the last completed pause, not total GC time.
		var gcLastMs = GCManager.lastPauseMs();
		observedGcMaxMs = Math.max(observedGcMaxMs, gcLastMs);
		if (now - sampled < 1) return;
		var window = Application.current.window;
		var record = haxe.Json.stringify({
			seconds: now - started, intervalSeconds: now - sampled,
			updates: updates, renderRequests: renders, updateMaxMs: updateMaxMs,
			gcLastMs: gcLastMs, gcObservedMaxMs: observedGcMaxMs,
			gcGameplay: GCManager.isGameplayMode(), gcGameplayMaxMs: GCManager.gameplayMaxPauseMs(),
			gcDeferred: GCManager.gameplayDeferredFullCount(), gcEmergency: GCManager.gameplayEmergencyFullCount(),
			heapUsedBytes: cpp.vm.Gc.memInfo64(0), heapReservedBytes: cpp.vm.Gc.memInfo64(1),
			updateCap: ClientPrefs.data.framerate, drawCap: ClientPrefs.data.drawFramerate,
			windowUpdateRate: window.frameRate, windowDrawRate: window.drawFrameRate,
			lockRender: window.lockRender, state: Type.getClassName(Type.getClass(flixel.FlxG.state))
		});
		output.writeString(record + '\n');
		output.flush();
		trace('[DCE-FrameAudit] ' + record);
		updates = renders = 0;
		updateMaxMs = 0;
		sampled = now;
		if (now - started >= 180) {
			Application.current.onUpdate.remove(sampleUpdate);
			window.onRender.remove(sampleRender);
			output.close();
			output = null;
		}
	}
}
#end
