package general.backend.debug;

import flixel.FlxG;
import flixel.tweens.FlxTween;
import flixel.util.FlxTimer;
import general.backend.Cache;

#if (cpp && NF_LEAK_PROBE)
import cpp.vm.Gc;
#end

/**
 * hxcpp 原生弱引用包装（`hx::WeakRef`）：GC 回收目标后 `get()` 返回 null。
 * 这是探针能"直接问 GC 这个对象还在不在"的唯一手段 —— 释放版 hxcpp 关掉了
 * `__hxcpp_gc_trace`（需要 HXCPP_DEBUG），所以用弱引用代替按类型点数。
 */
private extern class HxGCWeak {
	@:native("__hxcpp_weak_ref_create") static function create(obj:Dynamic):Dynamic;
	@:native("__hxcpp_weak_ref_get") static function get(ref:Dynamic):Dynamic;
	/** 对象身份（比指针更安全）：用来判断某个全局引用是不是正好抓着同一个对象 */
	@:native("__hxcpp_obj_id") static function objId(obj:Dynamic):Int;
}

private class LeakProbeDummy {
	public function new() {}
}

/**
 * 内存泄漏探针（D.C.E. 调试设施）。
 *
 * 目标：把"内存好像涨了"变成"**哪个对象在哪个流程之后没有被回收**"。
 *
 * 用法：
 *   1) 构建时加 `-D NF_LEAK_PROBE`（默认构建不含本模块逻辑，全部调用退化为空操作）；
 *   2) 运行时设环境变量：
 *        NF_LEAK_PROBE=1                打开探针
 *        NF_LEAK_PROBE_FILE=<路径>      日志文件（默认 cwd/leakprobe.log）
 *   3) 交互：F9 = 立刻 checkPoint（强制全量 GC + 快照 + 弱引用点名），F10 = 只打快照。
 *
 * 输出内容：
 *   - heap：GC 堆 usage/reserved/current/large + 进程工作集（MEM_INFO_PROCESS）；
 *   - census：图形缓存/声音/补间/定时器/相机/插件/信号监听数/舞台子节点……的实时计数，
 *     这些计数跨状态切换若持续单调上涨，就是聚合证据；
 *   - aliveRefs：**被 watch() 过、且在本次全量 GC 后依然存活的对象**（tag 点名）。
 *
 * watch() 的调用点见 MusicBeatState/MusicBeatSubstate 的 destroy()：状态被销毁后
 * 若在切走 + 全量 GC 之后仍然存活，说明有别的对象（静态表、未摘除的监听、未取消的
 * 补间……）继续持有它 —— 即泄漏本体。
 */
class LeakProbe
{
	// hxcpp MEM_INFO_*（见 hxcpp/src/hx/gc/Immix.cpp:265）：0=usage 1=reserved 2=current 3=large 4=process
	public static inline var MEM_USAGE:Int = 0;
	public static inline var MEM_RESERVED:Int = 1;
	public static inline var MEM_CURRENT:Int = 2;
	public static inline var MEM_LARGE:Int = 3;
	public static inline var MEM_PROCESS:Int = 4;

	public static var enabled(default, null):Bool = false;

	#if (cpp && NF_LEAK_PROBE)
	/**
	 * 被观察对象。
	 *   pinned=true：watch 时调过 __hxcpp_gc_do_not_kill，GC 判定它不可达时会把它放进
	 *                zombie 列表交给我们收殓 —— 这是**权威判据**（不依赖弱引用语义）。
	 *   id        ：对象身份号，用来跟 zombie 列表比对。
	 *   ref       ：弱引用，作为 pinned 失败时的兜底判据。
	 */
	static var entries:Array<{id:Int, ref:Dynamic, tag:String, since:Int, pinned:Bool}> = [];
	static var knownGraphics:Map<String, Bool> = new Map<String, Bool>();
	/** 上一次 checkpoint 时缓存里的全部 key —— 用来算"净留存"（真正没被释放的图） */
	static var prevKeys:Map<String, Bool> = null;
	/** 上上次的 key —— 用来算 STALE：连续 3 次 checkpoint 都还在的图（= 跨了 2 轮界面，必是泄漏） */
	static var prev2Keys:Map<String, Bool> = null;
	/** 金丝雀：上次 checkpoint 生成的临时对象，用来验证弱引用到底是不是"弱"的 */
	static var canaryRef:Dynamic = null;
	static var canaryBorn:Int = 0;
	/** NF_LEAK_NOPIN=1：不 pin 被观察对象，只用弱引用判定（对照组） */
	static var noPin:Bool = false;
	/** 永远为 null 的"不透明空值"：让 clobberStack 的局部槽不会被编译器优化掉 */
	static var nullSlot:Dynamic = null;
	/** NF_LEAK_DROP=1：收尾做消去法诊断（见 dropSuspects） */
	static var dropMode:Bool = false;
	/** NF_LEAK_DROP_FOR：只在残留 tag 含该子串时触发消去法 */
	static var dropFor:String = '';
	/** NF_LEAK_DROP_AFTER=N：消去法只在第 N 次（含）之后的 checkpoint 触发 —— 配合静置复检，
	 *  这样定位的是"静置后仍在"的真泄漏，而不是退场动画期间的短暂持有。0=不限制。 */
	static var dropAfter:Int = 0;
	/** 清栈递归层数（每层约 300 字节）；NF_LEAK_CLOBBER=N 可调。
	 *  层数不够 → 栈上残影清不掉 → 会把"已经没人引用的对象"误报成泄漏（假阳性）。 */
	static var clobberFrames:Int = 40;
	static var started:Bool = false;
	static var logPath:String = 'leakprobe.log';
	static var points:Int = 0;
	#end

	/** 引导（幂等）：只在主状态 create 里调一次即可。 */
	public static function init():Void
	{
		#if (cpp && NF_LEAK_PROBE)
		if (started) return;
		started = true;

		var env:String = null;
		try env = Sys.getEnv('NF_LEAK_PROBE') catch (e:Dynamic) {}
		if (env == null || env.length == 0 || env == '0') return;
		enabled = true;

		try
		{
			var f:String = Sys.getEnv('NF_LEAK_PROBE_FILE');
			if (f != null && f.length > 0) logPath = f;
		}
		catch (e:Dynamic) {}
		try
		{
			noPin = Sys.getEnv('NF_LEAK_NOPIN') == '1';
			dropMode = Sys.getEnv('NF_LEAK_DROP') == '1';
			var da:String = Sys.getEnv('NF_LEAK_DROP_AFTER');
			if (da != null && da.length > 0)
			{
				var dai:Null<Int> = Std.parseInt(da);
				if (dai != null && dai > 0) dropAfter = dai;
			}
			var cl:String = Sys.getEnv('NF_LEAK_CLOBBER');
			if (cl != null && cl.length > 0)
			{
				var cli:Null<Int> = Std.parseInt(cl);
				if (cli != null && cli > 0) clobberFrames = cli;
			}
			var df:String = Sys.getEnv('NF_LEAK_DROP_FOR');
			if (df != null) dropFor = df;
		}
		catch (e:Dynamic) {}

		logLine('=== LeakProbe init | ' + heapLine() + (noPin ? ' | NOPIN(对照组)' : ''));
		weakRefSelfTest();
		logLine('    census ' + census());
		// 自动化运行时不希望窗口失焦把游戏暂停（FlxG.autoPause 默认 true）——只在探针模式下关闭
		try FlxG.autoPause = false catch (e:Dynamic) {}
		// F9/F10 全源码未占用（F7/F8/F12 被编辑器菜单用掉了）
		FlxG.signals.postUpdate.add(onPostUpdate);
		#end
	}

	public static function logLine(s:String):Void
	{
		#if (cpp && NF_LEAK_PROBE)
		if (!enabled) return;
		var line:String = '[' + Date.now().toString() + '] ' + s;
		trace('[LeakProbe] ' + s);
		try
		{
			var f = sys.io.File.append(logPath, false);
			f.writeString(line + '\n');
			f.close();
		}
		catch (e:Dynamic) {}
		#end
	}

	static function onPostUpdate():Void
	{
		#if (cpp && NF_LEAK_PROBE)
		if (!enabled || FlxG.keys == null) return;
		if (FlxG.keys.justPressed.F9) checkPoint('hotkey:F9');
		else if (FlxG.keys.justPressed.F10) logLine('    census(manual) ' + census() + ' | ' + heapLine());
		#end
	}

	/**
	 * 观察一个对象：它一旦被 GC 判定不可达（zombie 收殓 / 弱引用失效）就从名单里消失。
	 * kind='created' 用于在 create() 时登记 —— 这样"**被换掉却没走 destroy()**"的状态
	 * 也会在 ALIVE 名单里现形（只在 destroy() 登记的话这种泄漏完全看不见）。
	 */
	public static function watch(obj:Dynamic, tag:String):Void
	{
		#if (cpp && NF_LEAK_PROBE)
		if (!enabled || obj == null) return;
		var pinned:Bool = false;
		var id:Int = 0;
		try
		{
			id = HxGCWeak.objId(obj);
			// 让 GC 在它不可达时把它交给我们（而不是直接释放），这样"还活着"就是权威结论
			// （NF_LEAK_NOPIN=1 时改用纯弱引用判定，用于交叉验证：如果关掉 pinning 后
			//   同一批对象就"死了"，说明结论是探针自身造成的假象）
			if (noPin) throw 'nopin';
			general.backend.gc.GCManager.doNotKill(obj);
			pinned = true;
		}
		catch (e:Dynamic) {}
		try
		{
			entries.push({id: id, ref: HxGCWeak.create(obj), tag: tag, since: points + 1, pinned: pinned});
		}
		catch (e:Dynamic) {}
		#end
	}

	/** 状态 create() 时登记（见 watch 的说明）。 */
	public static function watchCreated(obj:Dynamic, tag:String):Void
	{
		#if (cpp && NF_LEAK_PROBE)
		watch(obj, 'created:' + tag);
		#end
	}

	/** 强 GC + 快照 + 点名存活对象（自动化测试的每轮调用点）。 */
	public static function checkPoint(tag:String = ''):Void
	{
		#if (cpp && NF_LEAK_PROBE)
		if (!enabled) return;
		points++;
		var t0:Float = haxe.Timer.stamp();

		// 连收 3 轮：hxcpp 的标记阶段可能被栈/寄存器里的旧对象指针"钉"住一个周期，
		// 只收一次会把这种残影误判成泄漏。真正被引用的对象三轮都不会消失。
		var alivePerPass:Array<Int> = [];
		var lastAlive:Array<String> = [];
		for (pass in 0...3)
		{
			// ★ 顺序很重要：**先清栈、再 GC**。
			//   hxcpp 是保守式扫描 C++ 栈的：栈上残留的 hx::Object* 会被当成根。
			//   如果先 GC 后清栈，这一轮 GC 看到的还是"带残影的栈"，只有下一轮才受益。
			clobberStack();
			Gc.run(true);
			clobberStack();
			lastAlive = sweepPass(pass == 2);
			alivePerPass.push(lastAlive.length);
		}
		var ms:Int = Std.int((haxe.Timer.stamp() - t0) * 1000);

		logLine('--- checkpoint #' + points + ' [' + tag + '] gc=' + ms + 'ms state=' + stateName());		logLine('    ' + heapLine());
		logLine('    census ' + census());
		logLine('    ' + diffGraphics());
		logLine('    alive pass1=' + alivePerPass[0] + ' pass2=' + alivePerPass[1] + ' pass3=' + alivePerPass[2]);
		if (lastAlive.length > 0)
			logLine('    ALIVE: ' + groupTags(lastAlive));

		// NF_LEAK_DROP=1：消去法 —— 清空全局汇点后再收两轮，看谁死了（诊断用）
		// ★ 这一步会强拆游戏正在使用的对象（输入框/声音/键盘监听），之后**不能再继续跑流程**，
		//   否则 update/draw 访问已销毁对象必然访问违例崩溃（实测两次 native crash 都是这么来的）。
		//   所以：做完最后一次判定就立刻结束进程。
		if (dropMode && lastAlive.length > 0)
		{
			// 只在"确实存在非 LIVE 残留"时才做：否则正常的当前状态也会触发，
			// 导致还没进入目标场景就提前退出。
			// NF_LEAK_DROP_FOR=<子串>：只在残留 tag 里出现该子串时才触发（例如 ChartingState），
			// 这样启动链上的 InitState 之类小残留不会让诊断提前收场。
			var nonLive:Int = 0;
			var matched:Int = 0;
			for (a in lastAlive)
			{
				if (a.indexOf('(LIVE)') >= 0) continue;
				nonLive++;
				if (dropFor == null || dropFor.length == 0 || a.indexOf(dropFor) >= 0) matched++;
			}
			if (nonLive <= 0 || matched <= 0) return;
			if (dropAfter > 0 && points < dropAfter) return;

			logLine('    [drop] 发现 ' + nonLive + ' 个非 LIVE 残留（匹配 ' + matched + '），开始逐根定位');
			pinpointLeakRoots();
			logLine('[LeakProbe] DROP 诊断结束，立即退出（避免强拆后继续运行导致崩溃）');
			// 给日志一点时间落盘
			canaryCheck();
			try Sys.sleep(0.3) catch (e:Dynamic) {}
			Sys.exit(0);
		}

		canaryCheck();
		canaryRef = HxGCWeak.create(new LeakProbeDummy());
		canaryBorn = points;
		#end
	}

	/** 验证弱引用机制：上一轮造的临时对象（无任何强引用）本该被回收。 */
	static function canaryCheck():Void
	{
		#if (cpp && NF_LEAK_PROBE)
		if (canaryRef == null) return;
		var alive:Bool = false;
		try alive = HxGCWeak.get(canaryRef) != null catch (e:Dynamic) {}
		logLine('    [canary] dummy@#' + canaryBorn + ' survived full GC = ' + alive
			+ (alive ? '  <== 弱引用在本构建里是"强"的，aliveRefs 仅供参考' : '  (weakref ok)'));
		#end
	}

	/**
	 * NF_LEAK_DROP=1：收尾做一次"消去法"——把所有可能藏着闭包的全局汇点清空，
	 * 再收一轮。如果被点名的对象这时死了，说明保留者就在这批汇点里（闭包捕获）；
	 * 如果还活着，说明保留者在别处（原生引用 / 未扫描到的容器）。
	 * 注意：清空信号会连带干掉探针自己的钩子，所以这只在最后一次 checkpoint 之后有意义。
	 */
	public static function dropSuspects():String
	{
		var done:Array<String> = [];
		#if (cpp && NF_LEAK_PROBE)
		try
		{
			FlxG.signals.preStateSwitch.removeAll();
			done.push('preStateSwitch');
		}
		catch (e:Dynamic) {}
		try
		{
			FlxG.signals.postStateSwitch.removeAll();
			done.push('postStateSwitch');
		}
		catch (e:Dynamic) {}
		try
		{
			FlxG.signals.preStateCreate.removeAll();
			done.push('preStateCreate');
		}
		catch (e:Dynamic) {}
		try
		{
			FlxG.signals.gameResized.removeAll();
			done.push('gameResized');
		}
		catch (e:Dynamic) {}
		try
		{
			FlxG.signals.preGameReset.removeAll();
			FlxG.signals.postGameReset.removeAll();
			done.push('gameReset');
		}
		catch (e:Dynamic) {}
		try
		{
			FlxG.signals.focusGained.removeAll();
			FlxG.signals.focusLost.removeAll();
			done.push('focus');
		}
		catch (e:Dynamic) {}
		try
		{
			@:privateAccess FlxG.stage.__eventMap = null;
			done.push('stageEventMap');
		}
		catch (e:Dynamic) {}
		try
		{
			var wv = lime.app.Application.current.window;
			wv.onResize.removeAll();
			wv.onFullscreen.removeAll();
			// ★ 之前漏掉的一大类：lime window 的**输入**信号（键盘/鼠标/滚轮/文本/文件拖放…）。
			//   任何一处注册了实例方法闭包且没摘，就会把整个界面状态钉住。
			try wv.onKeyDown.removeAll() catch (e:Dynamic) {}
			try wv.onKeyUp.removeAll() catch (e:Dynamic) {}
			try wv.onMouseDown.removeAll() catch (e:Dynamic) {}
			try wv.onMouseUp.removeAll() catch (e:Dynamic) {}
			try wv.onMouseMove.removeAll() catch (e:Dynamic) {}
			try wv.onMouseWheel.removeAll() catch (e:Dynamic) {}
			try wv.onTextInput.removeAll() catch (e:Dynamic) {}
			try wv.onTextEdit.removeAll() catch (e:Dynamic) {}
			try wv.onDropFile.removeAll() catch (e:Dynamic) {}
			done.push('windowSignals(all)');
		}
		catch (e:Dynamic) {}
		// 全局插件表 / 游戏级滤镜 / 输入管理器
		try
		{
			FlxG.plugins.list.resize(0);
			done.push('plugins');
		}
		catch (e:Dynamic) {}
		try
		{
			@:privateAccess FlxG.game._filters = [];
			done.push('gameFilters');
		}
		catch (e:Dynamic) {}
		try
		{
			if (FlxG.cameras != null && FlxG.cameras.list != null)
				for (cam in FlxG.cameras.list)
					if (cam != null) cam.filters = [];
			done.push('cameraFilters');
		}
		catch (e:Dynamic) {}
		try
		{
			@:privateAccess scripts.stages.GlobalHandler.grp = null;
			done.push('globalScriptPack');
		}
		catch (e:Dynamic) {}
		// 输入框控件：它们的全局 stage / lime window 监听是"每开一个界面多一份"的头号嫌疑
		try
		{
			var n:Int = general.backend.ui.PsychUIInputText.releaseAll();
			done.push('inputs(' + n + ')');
		}
		catch (e:Dynamic) {}
		// 图形缓存：立刻清掉没人用的图（验证"图是否只是滞留在缓存里"）
		try
		{
			FlxG.bitmap.clearUnused();
			done.push('bitmapClear');
		}
		catch (e:Dynamic) {}
		// 音频：把当前声音列表里的死声音清空
		try
		{
			FlxG.sound.destroy(false);
			done.push('soundDestroy');
		}
		catch (e:Dynamic) {}
		#end
		return done.join(',');
	}

	/**
	 * NF_LEAK_DROP=1 的**精细化**版：不再一把清掉所有汇点，而是逐个根清除（累积），
	 * 每清一个就强 GC 三轮 + 冲栈，再测目标弱引用是否还在。
	 * 第一个让目标"死掉"的清除步骤，就是钉死它的那个持久根。
	 *
	 * 适用前提：必须配合 NF_LEAK_NOPIN=1 运行——pin 模式下对象被 GCManager 强留，
	 * 永远"活着"，无论怎么清根都测不出死亡。NOPIN 下清掉根 → 对象真的不可达 → 弱引用失效。
	 *
	 * 覆盖的根（比旧 dropSuspects 多了一个 cameras.reset，因为旧版只清相机 filters，
	 * 不清相机本体；若某相机 field 在 depth>2 处抓着目标，旧版会漏报成"在别处"）：
	 *   sound / signals / windowInputs / stageMap / inputs / cameras / plugins / filters / scriptPack / bitmap
	 */
	static function pinpointLeakRoots():Void
	{
		#if (cpp && NF_LEAK_PROBE)
		if (!noPin)
		{
			logLine('    [pinpoint] 未启用 NOPIN，pin 模式对象被强留，无法判定死亡——请加 NF_LEAK_NOPIN=1');
			return;
		}
		// 收集当前仍存活、且 tag 匹配 dropFor 的目标
		var targets:Array<{tag:String, ref:Dynamic}> = [];
		for (e in entries)
		{
			if (dropFor != null && dropFor.length > 0 && e.tag.indexOf(dropFor) < 0) continue;
			var obj:Dynamic = null;
			try obj = HxGCWeak.get(e.ref) catch (e2:Dynamic) {}
			if (obj == null) continue; // 已经回收，不算泄漏
			targets.push({tag: e.tag, ref: e.ref});
		}
		if (targets.length == 0)
		{
			logLine('    [pinpoint] 匹配 ' + dropFor + ' 的目标都已回收，无泄漏可定位');
			return;
		}
		logLine('    [pinpoint] 待定位目标 ' + targets.length + ' 个：' + [for (t in targets) t.tag].join(','));

		// 各根清除器（累积执行：每步在前一步已清的基础上再清一个）
		var steps:Array<{name:String, fn:Void->Void}> = [
			{name: 'sound', fn: function():Void { try FlxG.sound.destroy(false) catch (e:Dynamic) {} }},
			{name: 'signals', fn: function():Void { clearAllSignals(); }},
			{name: 'windowInputs', fn: function():Void { clearWindowSignals(); }},
			{name: 'stageMap', fn: function():Void { try @:privateAccess FlxG.stage.__eventMap = null catch (e:Dynamic) {} }},
			{name: 'inputs', fn: function():Void { try general.backend.ui.PsychUIInputText.releaseAll() catch (e:Dynamic) {} }},
			{name: 'cameras', fn: function():Void { try FlxG.cameras.reset() catch (e:Dynamic) {} }},
			{name: 'plugins', fn: function():Void { try FlxG.plugins.list.resize(0) catch (e:Dynamic) {} }},
			{name: 'filters', fn: function():Void {
				try @:privateAccess FlxG.game._filters = [] catch (e:Dynamic) {}
				try for (c in FlxG.cameras.list) if (c != null) c.filters = [] catch (e:Dynamic) {}
			}},
			{name: 'scriptPack', fn: function():Void { try @:privateAccess scripts.stages.GlobalHandler.grp = null catch (e:Dynamic) {} }},
			{name: 'bitmap', fn: function():Void { try FlxG.bitmap.clearUnused() catch (e:Dynamic) {} }},
			// 下面两步针对"反射看不见的持有者"：抓着 this 的闭包（函数对象）。
			// whoHolds/scanObjectFields 都看不到闭包内部捕获的 this，所以前面 10 步全清完仍活着。
			{name: 'stateFuncs', fn: function():Void {
				try
				{
					var st:Dynamic = FlxG.state;
					if (st != null)
					{
						var fs:Array<String> = Reflect.fields(st);
						for (f in fs) { var v:Dynamic = Reflect.field(st, f); if (Reflect.isFunction(v)) Reflect.setField(st, f, null); }
					}
				}
				catch (e:Dynamic) {}
			}},
			{name: 'staticFuncs', fn: function():Void {
				try
				{
					// 候选类：引擎自己的状态/编辑器/UI/设备类 + flixel 单例。持有 ChartingState 的闭包几乎一定
					// 注册在这些类上（ChartingState 自身或其直接子类的静态字段），不太可能是 flixel 内部。
					var suspects:Array<Dynamic> = [
						cast developer.editors.ChartingState,
						cast general.backend.MusicBeatState,
						cast mobile.objects.EditorMobileKeys,
						cast mobile.objects.EditorMobileKeyOverlay,
						cast general.backend.ui.PsychUIInputText,
						cast general.backend.device.WindowChromeManager,
						cast general.backend.debug.LeakProbe,
						cast general.backend.debug.LeakHarness,
						cast states.mainMenuState.MainMenuState,
						cast flixel.FlxG,
						cast flixel.FlxGame,
						cast flixel.FlxState,
						cast flixel.FlxSubState
					];
					for (c in suspects)
					{
						if (c == null) continue;
						var killed:Array<String> = [];
						try
						{
							var cf:Array<String> = Type.getClassFields(c);
							for (f in cf)
							{
								var v:Dynamic = Reflect.field(c, f);
								if (Reflect.isFunction(v)) { Reflect.setField(c, f, null); killed.push(f); }
							}
						}
						catch (e:Dynamic) {}
						if (killed.length > 0)
						{
							var anyAlive:Bool = false;
							for (t in targets) { try { if (HxGCWeak.get(t.ref) != null) anyAlive = true; } catch (e2:Dynamic) {} }
							if (!anyAlive)
							{
								logLine('    [staticFuncs] 钉死者在类 ' + Type.getClassName(c) + ' 的静态函数: ' + killed.join(','));
								break;
							}
						}
					}
				}
				catch (e:Dynamic) { logLine('    [staticFuncs] err ' + e); }
			}},
			// ★★ 全量静态函数字段（闭包）清除 —— 补掉最大的一个盲区：
			//   闭包捕获的 `this` 在 hxcpp 里是 CMemberFunction*/Closure_* 的 mThis 成员，
			//   **反射看不见**（Reflect.fields(closure) 是空的）→ 任何"静态闭包抓着状态"
			//   的泄漏，前面所有扫描都查不出来。这里挨个类清、每清一个就收一次 GC，
			//   谁清完目标就死了，谁就是钉死者。
			{name: 'staticFuncsAll', fn: function():Void {
				try
				{
					var names:Array<String> = general.backend.debug.LeakProbeClasses.NAMES;
					for (n in names)
					{
						var c:Dynamic = null;
						try c = Type.resolveClass(n) catch (e:Dynamic) {}
						if (c == null) continue;
						var killed:Array<String> = [];
						try
						{
							var cf:Array<String> = Type.getClassFields(c);
							for (f in cf)
							{
								var v:Dynamic = null;
								try v = Reflect.field(c, f) catch (e:Dynamic) { continue; }
								if (Reflect.isFunction(v))
								{
									try { Reflect.setField(c, f, null); killed.push(f); } catch (e:Dynamic) {}
								}
							}
						}
						catch (e:Dynamic) {}
						if (killed.length == 0) continue;

						Gc.run(true);
						clobberStack();
						var anyAlive:Bool = false;
						for (t in targets) { try { if (HxGCWeak.get(t.ref) != null) anyAlive = true; } catch (e2:Dynamic) {} }
						if (!anyAlive)
						{
							logLine('    [staticFuncsAll] ★钉死者在类 ' + n + ' 的静态函数: ' + killed.join(','));
							return;
						}
					}
					logLine('    [staticFuncsAll] 全量项目类静态函数清完仍存活 → 持有者不在"项目类静态闭包"里');
				}
				catch (e:Dynamic) { logLine('    [staticFuncsAll] err ' + e); }
			}},
			// 仍活着 -> 持有者在反射不可达处：活状态 / FlxGame 的深层对象引用链，或原生(C++)引用。
			// 下面几步暴力清空活状态与 FlxGame 的全部实例字段，断掉 depth>2 的引用链。
			{name: 'stateFields', fn: function():Void {
				try {
					var st:Dynamic = FlxG.state;
					if (st != null) { var fs:Array<String> = Reflect.fields(st); for (f in fs) { try Reflect.setField(st, f, null) catch (e:Dynamic) {} } }
				} catch (e:Dynamic) {}
			}},
			{name: 'gameFuncs', fn: function():Void {
				try {
					var g:Dynamic = FlxG.game;
					if (g != null) { var fs:Array<String> = Reflect.fields(g); for (f in fs) { var v:Dynamic = Reflect.field(g, f); if (Reflect.isFunction(v)) Reflect.setField(g, f, null); } }
				} catch (e:Dynamic) {}
			}},
			{name: 'gameFields', fn: function():Void {
				try {
					var g:Dynamic = FlxG.game;
					if (g != null) { var fs:Array<String> = Reflect.fields(g); for (f in fs) { try Reflect.setField(g, f, null) catch (e:Dynamic) {} } }
				} catch (e:Dynamic) {}
			}},
			{name: 'stageFind', fn: function():Void {
				try {
					var s:Dynamic = FlxG.stage;
					if (s == null) { logLine('    [stageFind] stage 为 null'); return; }
					var fs:Array<String> = Reflect.fields(s);
					for (f in fs)
					{
						var saved:Dynamic = null;
						try saved = Reflect.field(s, f) catch (e:Dynamic) {}
						try Reflect.setField(s, f, null) catch (e:Dynamic) {}
						for (p in 0...2) { Gc.run(true); clobberStack(); }
						var anyAlive:Bool = false;
						for (t in targets) { try { if (HxGCWeak.get(t.ref) != null) anyAlive = true; } catch (e2:Dynamic) {} }
						logLine('    [stageFind] 清字段 stage.' + f + ' -> ' + (anyAlive ? '仍活' : '★死亡★'));
						if (!anyAlive) { logLine('    [stageFind] ★钉死字段 = stage.' + f + ' (typeof=' + Type.typeof(saved) + ')'); break; }
					}
				} catch (e:Dynamic) { logLine('    [stageFind] err ' + e); }
			}},
		];

		for (s in steps)
		{
			try s.fn() catch (e:Dynamic) {}
			for (p in 0...3) { Gc.run(true); clobberStack(); }
			var still:Array<String> = [];
			var died:Array<String> = [];
			for (t in targets)
			{
				var alive:Bool = false;
				try alive = HxGCWeak.get(t.ref) != null catch (e2:Dynamic) {}
				if (alive) still.push(t.tag); else died.push(t.tag);
			}
			logLine('    [pinpoint] 清除 ' + s.name + ' 后 :: 仍活=' + still.length
				+ (still.length > 0 ? ' [' + still.join(',') + ']' : '')
				+ (died.length > 0 ? ' | 本次死亡=[' + died.join(',') + ']' : ''));
			if (still.length == 0) break; // 全清完了，没必要继续
		}
		#end
	}

	/** 清空 FlxG.signals 的全部 handler（逐个 removeAll，避免漏掉自定义信号）。 */
	static function clearAllSignals():Void
	{
		#if (cpp && NF_LEAK_PROBE)
		try
		{
			var sigs:Dynamic = FlxG.signals;
			var sfields:Array<String> = Reflect.fields(sigs);
			for (sf in sfields)
			{
				var sig:Dynamic = Reflect.field(sigs, sf);
				if (sig == null) continue;
				var ok:Bool = false;
				try { Reflect.callMethod(sig, Reflect.field(sig, 'removeAll'), []); ok = true; } catch (e:Dynamic) {}
				if (!ok)
				{
					try
					{
						var ls:Dynamic = Reflect.field(sig, 'listeners');
						if (ls != null && Std.isOfType(ls, Array))
					{
					var arr:Array<Dynamic> = cast ls;
					arr.splice(0, arr.length);
					}
					}
					catch (e:Dynamic) {}
				}
			}
		}
		catch (e:Dynamic) {}
		#end
	}

	/** 清空 lime window 的全部输入信号监听（键盘/鼠标/滚轮/文本/文件拖放）。 */
	static function clearWindowSignals():Void
	{
		#if (cpp && NF_LEAK_PROBE)
		try
		{
			var wv = lime.app.Application.current.window;
			var names:Array<String> = ['onResize', 'onFullscreen', 'onKeyDown', 'onKeyUp', 'onMouseDown',
				'onMouseUp', 'onMouseMove', 'onMouseWheel', 'onTextInput', 'onTextEdit', 'onDropFile',
				'onTouchStart', 'onTouchMove', 'onTouchEnd'];
			for (n in names)
			{
				var sig:Dynamic = Reflect.field(wv, n);
				if (sig == null) continue;
				var ok:Bool = false;
				try { Reflect.callMethod(sig, Reflect.field(sig, 'removeAll'), []); ok = true; } catch (e:Dynamic) {}
				if (!ok)
				{
					try
					{
						var ls:Dynamic = Reflect.field(sig, 'listeners');
						if (ls != null && Std.isOfType(ls, Array))
					{
					var arr:Array<Dynamic> = cast ls;
					arr.splice(0, arr.length);
					}
					}
					catch (e:Dynamic) {}
				}
			}
		}
		catch (e:Dynamic) {}
		#end
	}

	/**
	 * 用空白局部变量覆盖当前 C++ 栈的一段，冲掉早先深层调用留下的对象指针残影。
	 * hxcpp 会保守扫描 C++ 栈：状态切换那种深层调用链留在栈上的 hx::Object* 指针，
	 * 会把已经没人引用的对象"钉"住，直到那段栈被后来更深的调用覆盖 —— 表现为
	 * "销毁后还活着几轮、之后又自己死了"。所以判定前必须把栈刷深一点。
	 */
	static function clobberStack(depth:Int = 0):Void
	{
		var a:Dynamic = nullSlot, b:Dynamic = nullSlot, c:Dynamic = nullSlot, d:Dynamic = nullSlot;
		var e:Dynamic = nullSlot, f:Dynamic = nullSlot, g:Dynamic = nullSlot, h:Dynamic = nullSlot;
		var i:Dynamic = nullSlot, j:Dynamic = nullSlot, k:Dynamic = nullSlot, l:Dynamic = nullSlot;
		var m:Dynamic = nullSlot, n:Dynamic = nullSlot, o:Dynamic = nullSlot, p:Dynamic = nullSlot;
		var q:Dynamic = nullSlot, r:Dynamic = nullSlot, s:Dynamic = nullSlot, t:Dynamic = nullSlot;
		var u:Dynamic = nullSlot, v:Dynamic = nullSlot, w:Dynamic = nullSlot, x:Dynamic = nullSlot;
		var y:Dynamic = nullSlot, z:Dynamic = nullSlot, aa:Dynamic = nullSlot, ab:Dynamic = nullSlot;
		var ac:Dynamic = nullSlot, ad:Dynamic = nullSlot, ae:Dynamic = nullSlot, af:Dynamic = nullSlot;

		var buf:Array<Dynamic> = new Array<Dynamic>();
		for (k in 0...64) buf.push(null);

		if (depth < clobberFrames) clobberStack(depth + 1);

		// ★ 收尾时把这些槽**读一遍**：否则上面"写入 null"会被 C++ 编译器当死代码删掉，
		//   清栈就白做了（实测这层保险很关键 —— 没有它，栈上残影永远清不掉，
		//   会把早已没人引用的对象一直误报成泄漏）。
		if (a != null || b != null || c != null || d != null || e != null || f != null || g != null || h != null
			|| i != null || j != null || k != null || l != null || m != null || n != null || o != null || p != null
			|| q != null || r != null || s != null || t != null || u != null || v != null || w != null || x != null
			|| y != null || z != null || aa != null || ab != null || ac != null || ad != null || ae != null || af != null)
			nullSlot = a;

		buf = null;
		a = b = c = d = e = f = g = h = i = j = k = l = m = n = o = p = null;
		q = r = s = t = u = v = w = x = y = z = aa = ab = ac = ad = ae = af = null;
	}

	/**
	 * 图形缓存（FlxG.bitmap._cache）的两组指标：
	 *   churn  = 全部新出现过的 key（每次界面切换都会产生一批，正常）
	 *   stayed = **相对上次 checkpoint 净增加的 key** —— 这些图本轮没被释放，才是泄漏
	 */
	static function diffGraphics():String
	{
		#if (cpp && NF_LEAK_PROBE)
		var now:Map<String, Bool> = new Map<String, Bool>();
		var churn:Array<String> = [];
		var stayed:Array<String> = [];
		try
		{
			@:privateAccess
			for (key in FlxG.bitmap._cache.keys())
			{
				if (key == null) continue;
				now.set(key, true);
				if (!knownGraphics.exists(key))
				{
					knownGraphics.set(key, true);
					churn.push(key);
				}
				if (prevKeys != null && !prevKeys.exists(key))
					stayed.push(key);
			}
		}
		catch (e:Dynamic)
		{
			return 'graphicsDiff=error:' + e;
		}

		var total:Int = 0;
		for (_ in now.keys()) total++;

		// STALE：这三次 checkpoint 都在 = 跨了两轮界面还活着 —— 界面上"正在用"的图会随状态
		// 销毁而消失，所以这批就是真泄漏（配合 (persist/use) 标记看是策略还是有人抓着）。
		var stale:Array<String> = [];
		if (prevKeys != null && prev2Keys != null)
		{
			for (key in now.keys())
				if (prevKeys.exists(key) && prev2Keys.exists(key)) stale.push(key);
		}

		var out:String = 'graphics total=' + total + ' churn=' + churn.length;
		if (prevKeys == null)
			out += ' (baseline)';
		else
			out += ' STAYED=' + stayed.length + ' STALE=' + stale.length;

		if (stale.length > 0)
		{
			var sn:Int = stale.length > 12 ? 12 : stale.length;
			for (i in 0...sn)
				out += '\n        ## ' + stale[i] + graphicFlags(stale[i]);
			if (stale.length > sn)
				out += '\n        ## ...(' + (stale.length - sn) + ' more)';
		}
		else if (stayed.length > 0)
		{
			var n:Int = stayed.length > 16 ? 16 : stayed.length;
			for (i in 0...n)
				out += '\n        >> ' + stayed[i] + graphicFlags(stayed[i]);
			if (stayed.length > n)
				out += '\n        >> ...(' + (stayed.length - n) + ' more)';
		}
		prev2Keys = prevKeys;
		prevKeys = now;
		return out;
		#else
		return '';
		#end
	}

	/**
	 * 存活的图形为什么没被清掉：`persist=true`（缓存策略钉住）还是 `use>=1`（有 sprite 还拿着）。
	 * 前者是缓存策略问题，后者说明有对象活着 —— 两者的修法完全不同，必须区分。
	 */
	static function graphicFlags(key:String):String
	{
		#if (cpp && NF_LEAK_PROBE)
		try
		{
			@:privateAccess
			var g = FlxG.bitmap._cache.get(key);
			if (g == null) return '';
			var persist:Bool = false;
			var use:Int = -1;
			var don:Bool = false;
			try persist = g.persist catch (e:Dynamic) {}
			try don = g.destroyOnNoUse catch (e:Dynamic) {}
			try use = g.useCount catch (e:Dynamic) {}
			return ' (persist=' + persist + ' use=' + use + ' destroyOnNoUse=' + don + ')';
		}
		catch (e:Dynamic) {}
		#end
		return '';
	}

	public static function stateName():String
	{
		try
		{
			if (FlxG.state != null) return Type.getClassName(Type.getClass(FlxG.state));
			return '(no state)';
		}
		catch (e:Dynamic) {}
		return '(?)';
	}

	/**
	 * 一次收殓 + 判定：返回仍然存活（被 GC 判定可达）的 watch 对象标签。
	 * withHolders=true 时才去扫"谁抓着你"（较慢）。
	 */
	static function sweepPass(withHolders:Bool):Array<String>
	{
		var alive:Array<String> = [];
		#if (cpp && NF_LEAK_PROBE)
		if (entries.length == 0) return alive;

		// ① 收殓僵尸：GC 已经判定不可达的 watch 对象会被交到这里，弹出即释放
		var dead:Map<Int, Bool> = new Map<Int, Bool>();
		var guard:Int = 0;
		while (guard++ < 500000)
		{
			var z:Dynamic = null;
			try z = general.backend.gc.GCManager.getNextZombie() catch (e:Dynamic) { break; }
			if (z == null) break;
			try dead.set(HxGCWeak.objId(z), true) catch (e:Dynamic) {}
		}

		var keep:Array<{id:Int, ref:Dynamic, tag:String, since:Int, pinned:Bool}> = [];
		for (e in entries)
		{
			if (e.pinned)
			{
				if (dead.exists(e.id)) continue; // ★ 权威：GC 说它不可达
			}
			else
			{
				var target:Dynamic = null;
				try target = HxGCWeak.get(e.ref) catch (err:Dynamic) {}
				if (target == null) continue; // 弱引用兜底
			}

			var t2:Dynamic = null;
			try t2 = HxGCWeak.get(e.ref) catch (err:Dynamic) {}
			var mark:String = '';
			if (t2 != null && sameRef(t2, FlxG.state)) mark = '(LIVE)';
			alive.push(e.tag + '@#' + e.since + mark + (withHolders ? whoHolds(t2) : ''));
			keep.push(e);
		}
		entries = keep;
		#end
		return alive;
	}

	/**
	 * 直接问"是不是这几个全局引用之一抓着你" —— 命中的名字就是保留者。
	 * 先查几个已知单例槽，再扫一遍候选类的**静态字段**（含数组/列表一层）。
	 */
	/**
	 * 扫 FlxG 实例根（之前 whoHolds 的盲区）：
	 *  - FlxG.cameras.list[i] 的字段（相机不随 state 销毁自动摘除 → 既累积又可能抓着对象）
	 *  - FlxG.game 自身字段
	 *  - FlxG.inputs 各项字段
	 *  - FlxG.signals.* 的监听器（闭包捕获 this → 直接比对类，或扫闭包内部字段找被捕获的 this）
	 *  - FlxTimer.globalManager / FlxTween.globalManager 的回调闭包（同上）
	 * 返回命中路径字符串，供 dead 对象打印真正的保留者。
	 */
	static function scanFlxGRoots(target:Dynamic):String
	{
		#if (cpp && NF_LEAK_PROBE)
		var tid:Int = 0;
		try tid = HxGCWeak.objId(target) catch (e:Dynamic) { return ''; }
		if (tid == 0) return '';
		var tname:String = '';
		try tname = Type.getClassName(Type.getClass(target)) catch (e:Dynamic) {}
		var hits:Array<String> = [];

		// 1) 相机列表（最常漏的持久根）
		try
		{
			if (FlxG.cameras != null && FlxG.cameras.list != null)
			{
				var cams:Array<Dynamic> = cast FlxG.cameras.list;
				for (i in 0...cams.length)
				{
					var hit:String = scanObjectFields(cams[i], tid, 'FlxG.cameras.list[' + i + ']');
					if (hit != null) hits.push(hit);
				}
			}
		}
		catch (e:Dynamic) {}

		// 2) FlxG.game 自身字段
		try
		{
			var hit:String = scanObjectFields(FlxG.game, tid, 'FlxG.game');
			if (hit != null) hits.push(hit);
		}
		catch (e:Dynamic) {}

		// 3) 输入管理器（键盘/鼠标/触摸）
		try
		{
			var ins:Dynamic = FlxG.inputs;
			if (ins != null && Std.isOfType(ins, Array))
			{
				var arr:Array<Dynamic> = cast ins;
				for (i in 0...arr.length)
					if (arr[i] != null)
					{
						var hit:String = scanObjectFields(arr[i], tid, 'FlxG.inputs[' + i + ']');
						if (hit != null) hits.push(hit);
					}
			}
			else if (ins != null)
			{
				var hit:String = scanObjectFields(ins, tid, 'FlxG.input');
				if (hit != null) hits.push(hit);
			}
		}
		catch (e:Dynamic) {}

		// 4) 信号监听器（闭包）
		try
		{
			var sigs:Dynamic = FlxG.signals;
			var sfields:Array<String> = Reflect.fields(sigs);
			for (sf in sfields)
			{
				var sig:Dynamic = Reflect.field(sigs, sf);
				if (sig == null) continue;
				var handlers:Dynamic = null;
				try handlers = Reflect.field(sig, 'handlers') catch (e:Dynamic) {}
				if (handlers == null || !Std.isOfType(handlers, Array)) continue;
				var arr:Array<Dynamic> = cast handlers;
				for (h in arr)
				{
					var listener:Dynamic = null;
					try listener = Reflect.field(h, 'listener') catch (e:Dynamic) {}
					if (listener == null) continue;
					if (sameRef(listener, target)) { hits.push('FlxG.signals.' + sf + '(fn)'); continue; }
					var sub:String = scanObjectFields(listener, tid, 'FlxG.signals.' + sf + '.listener');
					if (sub != null) hits.push(sub);
					try
					{
						if (tname.length > 0 && Type.getClassName(Type.getClass(listener)) == tname)
							hits.push('FlxG.signals.' + sf + '(' + tname + '*)');
					}
					catch (e:Dynamic) {}
				}
			}
		}
		catch (e:Dynamic) {}

		// 5) FlxTimer.globalManager（静态单例，跨 state 永不清空）
		try
		{
			var mgr:Dynamic = flixel.util.FlxTimer.globalManager;
			if (mgr != null)
			{
				var members:Dynamic = Reflect.field(mgr, 'members');
				if (members != null && Std.isOfType(members, Array))
				{
					var arr:Array<Dynamic> = cast members;
					for (i in 0...arr.length)
					{
						if (arr[i] == null) continue;
						for (cf in ['onComplete', 'onUpdate', 'onStart', '_onComplete', '_onUpdate', '_onStart', 'executer'])
						{
							var cb:Dynamic = null;
							try cb = Reflect.field(arr[i], cf) catch (e:Dynamic) {}
							if (cb == null) continue;
							if (sameRef(cb, target)) { hits.push('FlxTimer.members[' + i + '].' + cf); continue; }
							var sub:String = scanObjectFields(cb, tid, 'FlxTimer.members[' + i + '].' + cf);
							if (sub != null) hits.push(sub);
						}
						var sub2:String = scanObjectFields(arr[i], tid, 'FlxTimer.members[' + i + ']');
						if (sub2 != null) hits.push(sub2);
					}
				}
			}
		}
		catch (e:Dynamic) {}

		// 6) FlxTween.globalManager（同上）
		try
		{
			var mgr:Dynamic = flixel.tweens.FlxTween.globalManager;
			if (mgr != null)
			{
				var members:Dynamic = Reflect.field(mgr, 'members');
				if (members != null && Std.isOfType(members, Array))
				{
					var arr:Array<Dynamic> = cast members;
					for (i in 0...arr.length)
					{
						if (arr[i] == null) continue;
						for (cf in ['onComplete', 'onUpdate', 'onStart', '_onComplete', '_onUpdate', '_onStart', 'executer', '_tweenFunction'])
						{
							var cb:Dynamic = null;
							try cb = Reflect.field(arr[i], cf) catch (e:Dynamic) {}
							if (cb == null) continue;
							if (sameRef(cb, target)) { hits.push('FlxTween.members[' + i + '].' + cf); continue; }
							var sub:String = scanObjectFields(cb, tid, 'FlxTween.members[' + i + '].' + cf);
							if (sub != null) hits.push(sub);
						}
						var sub2:String = scanObjectFields(arr[i], tid, 'FlxTween.members[' + i + ']');
						if (sub2 != null) hits.push(sub2);
					}
				}
			}
		}
		catch (e:Dynamic) {}

		// 7) PsychUIInputText 静态存活表（private，用 Reflect 取）：没走到 destroy 的输入框，其 ownerState 字段仍指向创建它的状态
		try
		{
			var cls7:Dynamic = general.backend.ui.PsychUIInputText;
			var li:Dynamic = Reflect.field(cls7, 'liveInstances');
			if (li != null && Std.isOfType(li, Array))
			{
				var arr:Array<Dynamic> = cast li;
				for (i in 0...arr.length)
				{
					if (arr[i] == null) continue;
					if (sameRef(arr[i], target)) { hits.push('PsychUIInputText.liveInstances[' + i + '](self)'); continue; }
					var sub:String = scanObjectFields(arr[i], tid, 'PsychUIInputText.liveInstances[' + i + ']');
					if (sub != null) hits.push(sub);
				}
			}
		}
		catch (e:Dynamic) {}

		// 8) EditorMobileKeys.activeEditorState（private，用 Reflect 取）
		try
		{
			var cls8:Dynamic = mobile.objects.EditorMobileKeys;
			var ae:Dynamic = Reflect.field(cls8, 'activeEditorState');
			if (ae != null)
			{
				if (sameRef(ae, target)) hits.push('EditorMobileKeys.activeEditorState');
				else
				{
					var sub:String = scanObjectFields(ae, tid, 'EditorMobileKeys.activeEditorState');
					if (sub != null) hits.push(sub);
				}
			}
		}
		catch (e:Dynamic) {}

		return hits.length > 0 ? hits.join('+') : '';
		#else
		return '';
		#end
	}

	static function whoHolds(target:Dynamic):String
	{
		#if (cpp && NF_LEAK_PROBE)
		var hits:Array<String> = [];
		try
		{
			if (sameRef(target, FlxG.state)) hits.push('FlxG.state');
		}
		catch (e:Dynamic) {}
		try
		{
			if (sameRef(target, general.backend.MusicBeatState.instance)) hits.push('MusicBeatState.instance');
		}
		catch (e:Dynamic) {}
		try
		{
			@:privateAccess
			if (sameRef(target, general.backend.device.WindowChromeManager.lastState)) hits.push('WindowChromeManager.lastState');
		}
		catch (e:Dynamic) {}
		try
		{
			if (sameRef(target, games.PlayState.instance)) hits.push('PlayState.instance');
		}
		catch (e:Dynamic) {}
		try
		{
			if (FlxG.cameras != null && FlxG.cameras.list != null && FlxG.cameras.list.indexOf(cast target) >= 0) hits.push('FlxG.cameras.list');
		}
		catch (e:Dynamic) {}

		// ★ 补盲：之前 whoHolds 只查单例槽 + 静态字段，从不扫 FlxG 实例根，
		//   导致"被 FlxTimer/FlxTween 全局管理器里的闭包抓着 this"、"被某相机/输入管理器字段抓着"这类泄漏点不出。
		var flxg:String = scanFlxGRoots(target);
		if (flxg.length > 0) hits.push(flxg);

		var scanned:String = scanStatics(target);
		if (scanned.length > 0) hits.push(scanned);
		// 全量类扫描：候选表没命中时再铺开找一遍（LeakProbeClasses.NAMES）
		var all:String = scanAllStatics(target);
		if (all.length > 0 && all != scanned) hits.push('ALL:' + all);
		return hits.length > 0 ? '{' + hits.join('+') + '}' : '';
		#else
		return '';
		#end
	}

	/** 扫候选类的静态字段（含数组一层），找是谁直接抓着 target。 */
	static function scanStatics(target:Dynamic):String
	{
		#if (cpp && NF_LEAK_PROBE)
		var tid:Int = 0;
		try tid = HxGCWeak.objId(target) catch (e:Dynamic) { return ''; }
		if (tid == 0) return '';

		var hits:Array<String> = [];
		for (cls in candidateClasses())
		{
			var cname:String = null;
			var fields:Array<String> = null;
			try
			{
				cname = Type.getClassName(cls);
				fields = Type.getClassFields(cls);
			}
			catch (e:Dynamic) { continue; }
			if (fields == null) continue;

			for (f in fields)
			{
				var v:Dynamic = null;
				try v = Reflect.field(cls, f) catch (e:Dynamic) { continue; }
				if (v == null) continue;
				var hit:String = scanValue(v, tid, cname + '.' + f);
				if (hit != null) hits.push(hit);
			}
		}
		return hits.join(',');
		#else
		return '';
		#end
	}

	/**
	 * 全量静态扫描：把 source/ 下每个类都解析出来，扫它们的静态字段。
	 * 名字表见 LeakProbeClasses（生成文件）。这样不论保留者是哪个类的静态槽都能点名。
	 */
	static function scanAllStatics(target:Dynamic):String
	{
		#if (cpp && NF_LEAK_PROBE)
		var tid:Int = 0;
		try tid = HxGCWeak.objId(target) catch (e:Dynamic) { return ''; }
		if (tid == 0) return '';

		var hits:Array<String> = [];
		var names:Array<String> = LeakProbeClasses.NAMES;
		for (i in 0...names.length)
		{
			var cls:Class<Dynamic> = null;
			try cls = Type.resolveClass(names[i]) catch (e:Dynamic) { continue; }
			if (cls == null) continue;

			var fields:Array<String> = null;
			try fields = Type.getClassFields(cls) catch (e:Dynamic) { continue; }
			if (fields == null) continue;

			for (f in fields)
			{
				var v:Dynamic = null;
				try v = Reflect.field(cls, f) catch (e:Dynamic) { continue; }
				if (v == null) continue;
				var hit:String = scanValue(v, tid, names[i] + '.' + f);
				if (hit != null) hits.push(hit);
				// 第二层：静态对象自己的字段（含数组一项）—— 例如 Xxx.staticMap/staticObj.field 抓着目标
				else
				{
					var deep:String = scanObjectFields(v, tid, names[i] + '.' + f);
					if (deep != null) hits.push(deep);
				}
			}
		}
		return hits.join(',');
		#else
		return '';
		#end
	}

	/**
	 * 遍历一个 Map 的**值**找目标。
	 *
	 * 为什么单独写：之前的扫描只覆盖"静态字段本身"和"数组项"，而引擎里大量东西是塞在 Map 里的
	 * （HScript.instances、Cache.currentTrackedXxx、Mods 的各种缓存、EditorMobileKeys 的表…），
	 * 这正是"扫遍所有类静态字段却点不出保留者"的原因。
	 * 做法：用反射嗅探 keys()/get() 两个方法（Haxe 的 Map 抽象在运行时是具体容器类）。
	 */
	static function scanMapValues(v:Dynamic, tid:Int, path:String):String
	{
		#if (cpp && NF_LEAK_PROBE)
		if (v == null) return null;
		var keysFn:Dynamic = null;
		var getFn:Dynamic = null;
		try
		{
			keysFn = Reflect.field(v, 'keys');
			getFn = Reflect.field(v, 'get');
		}
		catch (e:Dynamic) { return null; }
		if (keysFn == null || getFn == null) return null;

		try
		{
			var it:Dynamic = Reflect.callMethod(v, keysFn, []);
			if (it == null) return null;
			var hasNext:Dynamic = Reflect.field(it, 'hasNext');
			var nextFn:Dynamic = Reflect.field(it, 'next');
			if (hasNext == null || nextFn == null) return null;

			var guard:Int = 0;
			while (guard++ < 50000)
			{
				var more:Bool = false;
				try more = cast Reflect.callMethod(it, hasNext, []) catch (e:Dynamic) { break; }
				if (!more) break;

				var key:Dynamic = null;
				try key = Reflect.callMethod(it, nextFn, []) catch (e:Dynamic) { break; }

				var val:Dynamic = null;
				try val = Reflect.callMethod(v, getFn, [key]) catch (e:Dynamic) { continue; }
				if (val == null) continue;

				try
				{
					if (HxGCWeak.objId(val) == tid) return path + '[' + Std.string(key) + ']';
				}
				catch (e:Dynamic) {}
				// 值自身的一层字段（例如 map[key] = 某对象，该对象又抓着状态）
				try
				{
					if (Std.isOfType(val, Array))
					{
						var arr:Array<Dynamic> = cast val;
						var n:Int = arr.length > 2000 ? 2000 : arr.length;
						for (i in 0...n)
						{
							var e2:Dynamic = arr[i];
							if (e2 == null) continue;
							if (HxGCWeak.objId(e2) == tid) return path + '[' + Std.string(key) + '][' + i + ']';
						}
					}
				}
				catch (e:Dynamic) {}
			}
		}
		catch (e:Dynamic) {}
		#end
		return null;
	}

	/** 第二层：静态对象自己的字段（含数组一项）—— 例如 Xxx.staticObj.field 或 Xxx.staticArr[i] 抓着目标。 */
	static function scanObjectFields(v:Dynamic, tid:Int, path:String):String
	{
		#if (cpp && NF_LEAK_PROBE)
		if (v == null) return null;
		try
		{
			if (Std.isOfType(v, Class)) return null; // 类对象本身没有实例字段可扫
		}
		catch (e:Dynamic) {}

		// 数组：逐项比
		try
		{
			if (Std.isOfType(v, Array))
			{
				var arr:Array<Dynamic> = cast v;
				var n:Int = arr.length > 3000 ? 3000 : arr.length;
				for (i in 0...n)
				{
					var e:Dynamic = arr[i];
					if (e == null) continue;
					try
					{
						if (HxGCWeak.objId(e) == tid) return path + '[' + i + ']';
					}
					catch (err:Dynamic) {}
				}
				return null;
			}
		}
		catch (e:Dynamic) {}

		// 普通对象：先试 Map（Haxe 的 Map 在运行时是 keys/get 容器，值里塞对象是最常见的漏网形式）
		try
		{
			var mapHit:String = scanMapValues(v, tid, path);
			if (mapHit != null) return mapHit;
		}
		catch (e:Dynamic) {}

		// 普通对象：读它的字段（Reflect.field 对 hxcpp 的私有/公有声明字段都有效）
		try
		{
			var fields:Array<String> = Reflect.fields(v);
			if (fields == null) return null;
			for (f in fields)
			{
				if (f == null) continue;
				var w:Dynamic = null;
				try w = Reflect.field(v, f) catch (e:Dynamic) { continue; }
				if (w == null) continue;
				try
				{
					if (HxGCWeak.objId(w) == tid) return path + '.' + f;
				}
				catch (e:Dynamic) {}
				// 再深一层数组项（例如 Xxx.obj.someArray[i]）
				try
				{
					if (Std.isOfType(w, Array))
					{
						var arr2:Array<Dynamic> = cast w;
						var n2:Int = arr2.length > 2000 ? 2000 : arr2.length;
						for (i in 0...n2)
						{
							var e2:Dynamic = arr2[i];
							if (e2 == null) continue;
							if (HxGCWeak.objId(e2) == tid) return path + '.' + f + '[' + i + ']';
						}
					}
				}
				catch (e:Dynamic) {}
			}
		}
		catch (e:Dynamic) {}
		#end
		return null;
	}

	/** 值和 target 是同一个对象 → 返回路径；是一层容器且装得下 → 返回带下标的路径。 */
	static function scanValue(v:Dynamic, tid:Int, path:String):String
	{		#if (cpp && NF_LEAK_PROBE)
		try
		{
			if (HxGCWeak.objId(v) == tid) return path;
		}
		catch (e:Dynamic) { return null; }

		if (Std.isOfType(v, Array))
		{
			var arr:Array<Dynamic> = cast v;
			var n:Int = arr.length > 3000 ? 3000 : arr.length;
			for (i in 0...n)
			{
				var e:Dynamic = arr[i];
				if (e == null) continue;
				try
				{
					if (HxGCWeak.objId(e) == tid) return path + '[' + i + ']';
				}
				catch (err:Dynamic) {}
			}
		}
		#end
		return null;
	}

	static function candidateClasses():Array<Class<Dynamic>>
	{
		return [
			general.backend.MusicBeatState,
			general.backend.MusicBeatSubstate,
			general.backend.Paths,
			general.backend.Cache,
			general.backend.Mods,
			general.backend.ClientPrefs,
			general.backend.Conductor,
			general.backend.Achievements,
			general.backend.CustomFadeTransition,
			general.backend.device.WindowChromeManager,
			general.objects.WindowControlBar,
			general.objects.screen.MouseEffect,
			games.PlayState,
			scripts.hscript.HScript,
			scripts.hscript.HScriptBase,
			scripts.lua.FunkinLua,
			scripts.lua.CallbackHandler,
			scripts.lua.ShaderFunctions,
			scripts.stages.GlobalHandler,
			scripts.stages.modules.ModuleHandler,
			states.mainMenuState.MainMenuState,
			states.titleState.TitleState,
			states.backend.initState.InitState,
			states.freeplayState.FreeplayState,
			states.loadingState.LoadingState,
			states.modsMenuState.ModsMenuState,
			substates.ResultsScreen,
			substates.PauseSubState,
			games.objects.Note,
			games.objects.NoteSplash,
			games.backend.Replay,
			games.backend.Highscore,
			games.backend.Song,
			Main,
			flixel.FlxG,
			flixel.tweens.FlxTween,
			flixel.util.FlxTimer,
			flixel.sound.FlxSound,
			flixel.FlxState,
		];
	}

	static function sameRef(a:Dynamic, b:Dynamic):Bool
	{
		#if (cpp && NF_LEAK_PROBE)
		if (a == null || b == null) return false;
		try return HxGCWeak.objId(a) == HxGCWeak.objId(b) catch (e:Dynamic) {}
		#end
		return false;
	}

	static function groupTags(list:Array<String>):String
	{		var counts:Map<String, Int> = new Map<String, Int>();
		var order:Array<String> = [];
		for (t in list)
		{
			if (!counts.exists(t)) order.push(t);
			counts.set(t, (counts.exists(t) ? counts.get(t) : 0) + 1);
		}
		var out:Array<String> = [];
		for (t in order)
			out.push(t + ' x' + counts.get(t));
		return out.join(' | ');
	}

	/** 各类全局计数器的实时快照。跨轮次单调上涨即为聚合证据。 */
	public static function census():String
	{
		#if (cpp && NF_LEAK_PROBE)
		var sb:StringBuf = new StringBuf();
		try
		{
			sb.add('graphics=' + mapCount(@:privateAccess FlxG.bitmap._cache));
			sb.add(' sounds=' + arrCount(FlxG.sound.list.members));
			sb.add(' soundsLive=' + groupCount(FlxG.sound.list, 'countLiving') + '/' + groupCount(FlxG.sound.list, 'countDead'));
			sb.add(' tweens=' + arrCount(@:privateAccess FlxTween.globalManager._tweens));
			sb.add(' timers=' + arrCount(@:privateAccess FlxTimer.globalManager._timers));
			sb.add(' cameras=' + (FlxG.cameras.list != null ? FlxG.cameras.list.length : -1));
			sb.add(' plugins=' + (FlxG.plugins.list != null ? FlxG.plugins.list.length : -1));
			sb.add(' members=' + (FlxG.state != null && FlxG.state.members != null ? FlxG.state.members.length : -1));
			sb.add(' cacheA=' + mapCount(Cache.currentTrackedAssets));
			sb.add(' cacheS=' + mapCount(Cache.currentTrackedSounds));
			sb.add(' cacheF=' + mapCount(Cache.currentTrackedFrames));
			sb.add(' cacheN=' + mapCount(Cache.currentTrackedAnims));
			sb.add(' localA=' + arrCount(Cache.localTrackedAssets));
			sb.add(' sigUpdate=' + sigCount(FlxG.signals.postUpdate));
			sb.add(' sigPreUpdate=' + sigCount(FlxG.signals.preUpdate));
			sb.add(' sigPreState=' + sigCount(FlxG.signals.preStateSwitch));
			sb.add(' sigResized=' + sigCount(FlxG.signals.gameResized));
			sb.add(' sigPostState=' + sigCount(FlxG.signals.postStateSwitch));
			sb.add(' stageKeyUp=' + stageListeners('keyUp'));
			sb.add(' stageKeyDown=' + stageListeners('keyDown'));
			sb.add(' stageResize=' + stageListeners('resize'));
			sb.add(' stageMouseMove=' + stageListeners('mouseMove'));
			sb.add(' stageMouseDown=' + stageListeners('mouseDown'));
			sb.add(' stageMouseUp=' + stageListeners('mouseUp'));
			sb.add(' stageEnterFrame=' + stageListeners('enterFrame'));
			sb.add(' stageTextInput=' + stageListeners('textInput'));
			sb.add(' btnAlive=' + (try flixel.ui.FlxButton.aliveCount catch (e:Dynamic) -1));
			sb.add(' stageKids=' + (FlxG.stage != null ? FlxG.stage.numChildren : -1));
			sb.add(' gameKids=' + (FlxG.game != null ? FlxG.game.numChildren : -1));
		}
		catch (e:Dynamic)
		{
			sb.add('census-error:' + e);
		}
		return sb.toString();
		#else
		return '';
		#end
	}

	/** 打印 OpenFL stage 的事件监听器表与 dispatch 迭代器快照（定位 stage 泄漏的关键证据）。 */
	public static function logStageDispatch():String
	{
		#if (cpp && NF_LEAK_PROBE)
		var sb:StringBuf = new StringBuf();
		try
		{
			if (FlxG.stage == null) { sb.add('stageDispatch: stage=null'); return sb.toString(); }
			var em:Dynamic = Reflect.field(FlxG.stage, '__eventMap');
			var it:Dynamic = Reflect.field(FlxG.stage, '__iterators');

			sb.add('stageMap{');
			if (em != null) sb.add(mapKeysToCounts(em));
			sb.add('} stageIter{');
			if (it != null) sb.add(mapKeysToCounts(it));
			sb.add('}');

			var focus:Dynamic = null;
			try focus = Reflect.field(FlxG.stage, 'focus') catch (e:Dynamic) {}
			if (focus != null) sb.add(' focus=' + Type.getClassName(Type.getClass(focus)));
			var td:Dynamic = null;
			try td = Reflect.field(FlxG.stage, '__targetDispatcher') catch (e:Dynamic) {}
			if (td != null) sb.add(' targetDispatcher=' + Type.getClassName(Type.getClass(td)));
		}
		catch (e:Dynamic) { sb.add('stageDispatch-error:' + e); }
		return sb.toString();
		#else
		return '';
		#end
	}

	/** 把一个 Map<String,Array> 的每个 key -> 数组长度 拼成 "k=n,k2=n2" 字符串（用 iterator 迭代）。 */
	static function mapKeysToCounts(m:Dynamic):String
	{
		var parts:Array<String> = [];
		try
		{
			var it:Dynamic = Reflect.callMethod(m, Reflect.field(m, 'iterator'), []);
			var hasNext:Dynamic = Reflect.field(it, 'hasNext');
			var next:Dynamic = Reflect.field(it, 'next');
			while (Reflect.callMethod(it, hasNext, []) == true)
			{
				var kv:Dynamic = Reflect.callMethod(it, next, []);
				var k:Dynamic = Reflect.field(kv, 'key');
				var v:Dynamic = Reflect.field(kv, 'value');
				var n:Int = -1;
				try n = (cast v : Array<Dynamic>).length catch (e:Dynamic) {}
				parts.push(Std.string(k) + '=' + n);
			}
		}
		catch (e:Dynamic) { parts.push('iter-err:' + e); }
		return parts.join(',');
	}

	public static function heapLine():String
	{
		#if (cpp && NF_LEAK_PROBE)
		return 'heap usage=' + mb(mem(MEM_USAGE)) + 'MB reserved=' + mb(mem(MEM_RESERVED)) + 'MB current=' + mb(mem(MEM_CURRENT)) + 'MB large='
			+ mb(mem(MEM_LARGE)) + 'MB | process=' + mb(mem(MEM_PROCESS)) + 'MB';
		#else
		return '';
		#end
	}

	#if (cpp && NF_LEAK_PROBE)
	static inline function mem(which:Int):Float
		return Gc.memInfo64(which);

	static inline function mb(bytes:Float):Float
		return Math.round(bytes / 1048576 * 10) / 10;

	static function mapCount<K, V>(m:Map<K, V>):Int
	{
		if (m == null) return -1;
		var n:Int = 0;
		for (_ in m.keys()) n++;
		return n;
	}

	static function arrCount<T>(a:Array<T>):Int
		return a == null ? -1 : a.length;

	static function groupLength(g:Dynamic):Int
	{
		if (g == null) return -1;
		try return cast Reflect.field(g, 'length') catch (e:Dynamic) {}
		return -1;
	}

	/** 调 FlxTypedGroup 上的一个统计方法（countLiving/countDead）。 */
	static function groupCount(g:Dynamic, fn:String):Int
	{
		if (g == null) return -1;
		try
		{
			var f:Dynamic = Reflect.field(g, fn);
			if (f == null) return -1;
			return cast Reflect.callMethod(g, f, []);
		}
		catch (e:Dynamic) {}
		return -1;
	}

	/** 舞台上的 openfl 事件监听数（__eventMap 私有，反射读）——按重启累计的监听会在这里现形。 */
	static function stageListeners(type:String):Int
	{
		if (FlxG.stage == null) return -1;
		try
		{
			var map:Dynamic = Reflect.field(FlxG.stage, '__eventMap');
			if (map == null) return 0;
			var list:Dynamic = Reflect.callMethod(map, Reflect.field(map, 'get'), [type]);
			if (list == null) return 0;
			var arr:Array<Dynamic> = cast list;
			return arr.length;
		}
		catch (e:Dynamic) {}
		return -1;
	}

	/** FlxSignal 的监听者数量（handlers 是私有字段，用反射读）。 */
	static function sigCount(sig:Dynamic):Int
	{
		if (sig == null) return -1;
		try
		{
			var h:Dynamic = Reflect.field(sig, 'handlers');
			if (h != null)
			{
				var arr:Array<Dynamic> = cast h;
				return arr.length;
			}
		}
		catch (e:Dynamic) {}
		return -1;
	}

	/** 先验证弱引用在这个 hxcpp 构建里真的是"弱"的，否则后面的点名毫无意义。 */
	static function weakRefSelfTest():Void
	{
		try
		{
			var ref:Dynamic = makeDummyRef();
			Gc.run(true);
			var alive:Bool = HxGCWeak.get(ref) != null;
			// 注意：同一帧刚创建的临时对象可能被栈上的残留引用留住，报 true 不代表机制坏掉；
			// 真正的判据是后面 checkpoint 里 state:/substate: 是否被判为 collected。
			logLine('[selftest] weakref alive-after-full-GC=' + alive + (alive ? ' (same-frame leftover ref, expected)' : ' (collected)'));
		}
		catch (e:Dynamic)
		{
			logLine('[selftest] failed: ' + e);
		}
	}

	/** 单独一帧创建，返回值里不保留强引用。 */
	static function makeDummyRef():Dynamic
	{
		var d = new LeakProbeDummy();
		return HxGCWeak.create(d);
	}
	#end
}
