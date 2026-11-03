package developer.display;

import cpp.vm.Gc;
import flixel.FlxG;
import flixel.graphics.FlxGraphic;

/**
 * 资源归属账本（ResourceLedger）——「谁加载的，就由谁清」。
 *
 * ## 为什么需要它
 * 引擎原本的清理只认 `Paths.image/sound` 这类**文件素材**（靠 `Cache.trackLocalAsset` 记账），
 * 但界面里大量东西根本不是从文件来的：
 *   - `makeGraphic(w, h, color, true)` 造出来的**唯一图**（键名 `pixels<N>`）
 *   - `FlxText` 渲染用的**文本图形**（键名 `text<N>`）
 * 这些图**没有人记账**，于是退出界面时没人知道它们该由谁清 —— 表现就是
 * "打开界面内存涨、退出界面不回落"，而且每次进同一个界面都会再造一批新键名。
 *
 * ## 它怎么工作
 * 每个界面（MusicBeatState）在 create 时 `begin(this)` 记下"当时的图形键快照"作为基线；
 * 在切换完成后 / 销毁前 `mark(this)` 把**本界面期间新出现的键**记成"本界面拥有"；
 * 销毁时 `releaseOwned(this)` 只释放"本界面拥有、且**没有其它存活界面也拥有**"的键。
 *
 * 关键点：判定依据是**归属**（谁加载的）+ **存活界面是否共用**，而不是"引用计数/名单外一律清"。
 * 后者会把当前界面正在用的文本图形也清掉（实测表现为满屏文字变成色块），所以必须按归属来。
 */
@:headerCode('
#if defined(_WIN32)
// ★ 只声明用到的两个 Win32 API，**绝不 include <windows.h>**（2026-10-01 踩坑）：
//   windows.h 会把 min/max 定义成宏，直接污染 flixel/openfl 的生成代码，
//   实测导致 LogStyle.h(58) / FlxKey_Impl_.h(108) 报 C2059「语法错误: 常数」，
//   整个构建失败。手写原型等价于 HANDLE=void*、BOOL=int、WINAPI=__stdcall。
extern "C" {
  __declspec(dllimport) void* __stdcall GetCurrentProcess(void);
  __declspec(dllimport) int __stdcall K32EmptyWorkingSet(void* hProcess);
}
#endif
')
class ResourceLedger
{
	/** 状态实例 id → 账本 */
	static var owners:Map<Int, OwnerEntry> = new Map<Int, OwnerEntry>();
	/** 每个图形键当前被多少个"存活界面"拥有（>0 表示别的界面也在用，不能动） */
	static var liveKeys:Map<String, Int> = new Map<String, Int>();

	static var lastReport:String = '';

	public static function lastInfo():String return lastReport;

	@:native("__hxcpp_obj_id") extern static function objId(obj:Dynamic):Int;
	@:native("__hxcpp_gc_compact") extern static function nativeCompact():Void;

	/** 界面 create 时调用：记下基线快照 */
	public static function begin(owner:Dynamic):Void
	{
		if (owner == null) return;
		try
		{
			var id:Int = objId(owner);
			var base:Map<String, Bool> = new Map<String, Bool>();
			@:privateAccess
			for (k in FlxG.bitmap._cache.keys())
				if (k != null) base.set(k, true);
			owners.set(id, {baseline: base, owned: new Map<String, Bool>()});
		}
		catch (e:Dynamic) {}
	}

	/** 把"本界面期间新出现的图形键"记进本界面账本（可在切换后/销毁前多次调用） */
	public static function mark(owner:Dynamic):Void
	{
		if (owner == null) return;
		try
		{
			var id:Int = objId(owner);
			var entry:OwnerEntry = owners.get(id);
			if (entry == null)
			{
				begin(owner);
				entry = owners.get(id);
				if (entry == null) return;
			}

			@:privateAccess
			for (k in FlxG.bitmap._cache.keys())
			{
				if (k == null) continue;
				if (entry.baseline.exists(k)) continue;
				if (entry.owned.exists(k)) continue;
				entry.owned.set(k, true);
				liveKeys.set(k, (liveKeys.exists(k) ? liveKeys.get(k) : 0) + 1);
			}

			// 本界面成员精灵实际持有的键也算它的（例如文本框重建、素材在 create 之后才加载）
			var keep:Map<String, Bool> = new Map<String, Bool>();
			collectGraphics(owner, keep, 0);
			for (k in keep.keys())
			{
				if (k == null || entry.owned.exists(k)) continue;
				entry.owned.set(k, true);
				liveKeys.set(k, (liveKeys.exists(k) ? liveKeys.get(k) : 0) + 1);
			}
		}
		catch (e:Dynamic) {}
	}

	/**
	 * 界面销毁时调用：释放"本界面拥有、别的存活界面没有共用"的图形。
	 * @return 释放的图形数量
	 */
	public static function releaseOwned(owner:Dynamic):Int
	{
		if (owner == null) return 0;
		var freed:Int = 0;
		try
		{
			mark(owner); // 先把 destroy 之前新建的图补进账本
			var id:Int = objId(owner);
			var entry:OwnerEntry = owners.get(id);
			if (entry == null) return 0;
			owners.remove(id);

			var cache:Map<String, Dynamic> = cast @:privateAccess FlxG.bitmap._cache;
			for (k in entry.owned.keys())
			{
				if (k == null) continue;
				var refs:Int = liveKeys.exists(k) ? liveKeys.get(k) : 0;
				if (refs > 1)
				{
					// 还有别的存活界面在用它 —— 只减计数，不释放
					liveKeys.set(k, refs - 1);
					continue;
				}
				liveKeys.remove(k);

				var g:Dynamic = cache.get(k);
				if (g == null) continue;

				// ★★ 安全线（踩过坑）：绝不销毁"还在被精灵使用"的图。
				//
				//   之前这里是"账本里的一律 destroy()"，结果从 Freeplay 进歌时直接崩
				//   （EXCEPTION_ACCESS_VIOLATION / read 0x148）：某张图还被角色/音符/图标
				//   精灵持有（useCount>0），或者是 persist 的素材，被我们摘掉销毁后，
				//   精灵渲染时访问已释放的 BitmapData 就崩了。
				//   现在的规则：
				//     1) 只处理**匿名图**（makeGraphic 的唯一图 / FlxText 文本图，不带路径）；
				//        带路径或素材扩展名的键一律交给 Paths/Cache 自己那套账本处理；
				//     2) useCount>0（有人用）或 persist=true（素材常驻）→ **只降级不销毁**，
				//        交给 flixel 的引用计数在最后一位持有者死亡时自动释放。
				var isAsset:Bool = k.indexOf('/') >= 0 || k.indexOf('\\') >= 0
					|| k.indexOf('.png') >= 0 || k.indexOf('.ogg') >= 0 || k.indexOf('.jpg') >= 0;
				var use:Int = 0;
				var persist:Bool = false;
				try use = g.useCount catch (e:Dynamic) {}
				try persist = g.persist catch (e:Dynamic) {}

				if (isAsset || use > 0 || persist)
				{
					try
					{
						if (persist && !isAsset) g.persist = false;
						g.destroyOnNoUse = true;
					}
					catch (e:Dynamic) {}
					continue;
				}

				try
				{
					cache.remove(k);
					freed++;
					cast(g, FlxGraphic).destroy();
				}
				catch (e:Dynamic) {}
			}
			try FlxG.bitmap.clearUnused() catch (e:Dynamic) {}
		}
		catch (e:Dynamic) {}

		lastReport = '账本回收: 释放图形 ' + freed + ' 张';
		return freed;
	}

	/** 清理已死界面留下的账本计数（防止 liveKeys 因异常路径只增不减） */
	public static function sweepDeadOwners():Void
	{
		// 账本条目本身很轻（只有字符串键），真正的清理发生在 releaseOwned。
		// 这里只做一次 count 校正：把计数归零且已无主的键去掉，避免 map 无限增长。
		try
		{
			if (owners == null) return;
			if (owners.keys().hasNext() == false)
			{
				liveKeys = new Map<String, Int>();
			}
		}
		catch (e:Dynamic) {}
	}

	/**
	 * 离开场景时把"已经用不到的空闲内存"还给系统。
	 *
	 * 实测结论（2026-09-30）：
	 *   - `nativeCompact()`（`__hxcpp_gc_compact`）是"反复全量回收直到不再释放"，**没有上界**。
	 *     在 900MB 级碎片堆上它跑完也只归还约 20MB（实测 reserved 751MB → 731MB），
	 *     因为 legacy Immix 只归还"完整空的 block group"，而大场景退出后活对象散布各块。
	 *     收益≈0、代价=一次不可预期的长全量回收 → **默认不再调用**
	 *     （`NF_FORCE_COMPACT=1` 可开回来做实验/对比）。
	 *   - 真正有效且即时的是 `EmptyWorkingSet`：把空闲页移出进程工作集，任务管理器/引擎
	 *     显示的 "APP MEM（工作集）" 立刻回落（实测 686MB → 330MB）。
	 *     这一步开销是微秒级，所以**每次离开场景都做**（不再挂阈值条件）。
	 */
	public static function compactIfBloated(thresholdMB:Float = 256):Void
	{
		try
		{
			if (!forceCompactConfigured)
			{
				forceCompactConfigured = true;
				try forceCompact = Sys.getEnv('NF_FORCE_COMPACT') == '1' catch (e:Dynamic) {}
			}

			// ① 让 Immix 的保留策略变"抠门"（一次性）：目标空闲比例 / 最小空闲调小，
			//    否则它每次都给自己留一大片空闲，reserved 永远贴着峰值。
			if (!tuned)
			{
				tuned = true;
				try general.backend.gc.GCManager.setTargetFreeSpacePercentage(20) catch (e:Dynamic) {}
				try general.backend.gc.GCManager.setMinimumFreeSpace(8 * 1024 * 1024) catch (e:Dynamic) {}
			}

			// ② 借 gameplay 模式的退出路径，强制走一次"整理式回收" —— 这是 legacy Immix
			//    唯一会把空闲块还给系统的地方（见 forceHeapReturn 的说明）。
			forceHeapReturn();

			// ③ 可选：强制整理（默认关，见上面的踩坑说明）
			if (forceCompact)
			{
				var usage:Float = Gc.memInfo64(0);
				var reserved:Float = Gc.memInfo64(1);
				if ((reserved - usage) / 1048576 >= thresholdMB)
				{
					var t0:Float = haxe.Timer.stamp();
					nativeCompact();
					var ms:Int = Std.int((haxe.Timer.stamp() - t0) * 1000);
					lastReport += ' | compact(' + ms + 'ms): reserved ' + Math.round(reserved / 1048576) + 'MB -> '
						+ Math.round(Gc.memInfo64(1) / 1048576) + 'MB';
					#if NF_LEAK_PROBE
					// 实测：compact 的耗时与释放量差异极大（歌曲路径 700→113MB，编谱器路径只降 44MB），
					// 所以必须把每一次的"耗时 + 释放量"记下来，才能决定默认开还是关。
					general.backend.debug.LeakProbe.logLine('    [ledger] compact ' + ms + 'ms: reserved '
						+ Math.round(reserved / 1048576) + 'MB -> ' + Math.round(Gc.memInfo64(1) / 1048576)
						+ 'MB (usage ' + Math.round(Gc.memInfo64(0) / 1048576) + 'MB)');
					#end
				}
			}

			// ③ 工作集收缩：**不再在界面切换时自动执行**（2026-10-01，用户反馈"APP MEM 像心电图"）。
			//   `EmptyWorkingSet` 只是把页移出工作集 —— 游戏马上又会访问它们并换回来，
			//   实测表现为 686MB → 1MB → 686MB 的锯齿（每隔几十秒一次），既不真实又白费性能。
			//   工作集本来就随访问波动，**它不是泄漏指标**：判断泄漏看 GC used / reserved。
			//   需要"把空闲页压出去"时由用户按 F7 手动触发（见 DebugMonitor.reclaimUnusedGraphics）。
			// trimWorkingSet();
			#if NF_LEAK_PROBE
			try general.backend.debug.LeakProbe.logLine('    [ledger] trimWS -> 工作集 '
				+ Math.round(Gc.memInfo64(4) / 1048576) + 'MB (reserved ' + Math.round(Gc.memInfo64(1) / 1048576)
				+ 'MB, usage ' + Math.round(Gc.memInfo64(0) / 1048576) + 'MB)') catch (e:Dynamic) {}
			#end
		}
		catch (e:Dynamic) {}
	}

	static var trimEnabled:Bool = true;
	static var trimConfigured:Bool = false;
	static var emptyWorkingSetFn:Dynamic = null;

	/** 是否调用 __hxcpp_gc_compact()（默认关，见 compactIfBloated 里的踩坑说明）。 */
	static var forceCompact:Bool = false;
	static var forceCompactConfigured:Bool = false;

	/** 把进程的空闲页移出工作集（Windows）—— 让 "APP MEM（工作集）" 瞬间回落的那一下。 */
	public static function trimWorkingSet():Void
	{
		#if (cpp && windows)
		if (!trimConfigured)
		{
			trimConfigured = true;
			try
			{
				var env:String = Sys.getEnv('NF_TRIM_WORKINGSET');
				if (env == '0') trimEnabled = false;
			}
			catch (e:Dynamic) {}
		}
		if (!trimEnabled) return;

		try
		{
			var wsBefore:Float = Gc.memInfo64(4);
			var ok:Bool = winEmptyWorkingSet(winGetCurrentProcess());
			var wsAfter:Float = Gc.memInfo64(4);
			lastTrimInfo = 'ok=' + (ok ? '1' : '0') + ' 工作集 ' + Math.round(wsBefore / 1048576) + '->'
				+ Math.round(wsAfter / 1048576) + 'MB';
			lastReport += ' | trimWS ' + lastTrimInfo;
			#if NF_LEAK_PROBE
			try general.backend.debug.LeakProbe.logLine('    [ledger] trimWS ' + lastTrimInfo + ' (reserved '
				+ Math.round(Gc.memInfo64(1) / 1048576) + 'MB, usage ' + Math.round(Gc.memInfo64(0) / 1048576) + 'MB)')
			catch (e:Dynamic) {}
			#end
		}
		catch (e:Dynamic) {}
		#end
	}

	#if (cpp && windows)
	/**
	 * Windows：当前进程的伪句柄（(HANDLE)-1）。
	 * 走**编译期**调用（`@:native` extern），所以 C++ 侧拿到的就是正确的 64 位值。
	 */
	@:native("GetCurrentProcess")
	extern static function winGetCurrentProcess():cpp.Pointer<cpp.Void>;

	/** Windows：把空闲页移出工作集。`K32EmptyWorkingSet` 由 kernel32 导出（psapi.h 里声明）。 */
	@:native("K32EmptyWorkingSet")
	extern static function winEmptyWorkingSet(h:cpp.Pointer<cpp.Void>):Bool;
	#end

	/**
	 * 最近一次"工作集回收"的结果（成败 + 返回值 + 前后工作集）。
	 * 只有探针构建才写日志，而用户跑的往往是发布版 —— 所以把结果做成**面板可见的字符串**，
	 * 这样一截图就知道 `EmptyWorkingSet` 到底成功没有（之前它静默失败过：调用后工作集纹丝不动）。
	 */
	public static var lastTrimInfo:String = '(未执行)';

	static var tuned:Bool = false;

	/**
	 * 强制让 GC 把空闲堆还给系统 —— legacy Immix 里**唯一**的归还路径。
	 *
	 * 机制（读 hxcpp 源码得出的结论）：
	 *   - `releaseEmptyGroups()` 只在**整理式回收**里被调用（`Immix.cpp:4264` 定义、
	 *     `:5433` 调用），普通 GC 永远不会把块还给 OS；
	 *   - 整理式回收有两条触发路径：
	 *       ① `__hxcpp_gc_compact()`（`inForceCompact`）—— 无上界，实测在 900MB 碎片堆上
	 *          只释放几 MB（`releaseEmptyGroups` 只能还"完整空的 block group"）。已默认关闭。
	 *       ② GC 自己判断碎片率够高时（`MoveBlocks(job,stats)` 返回 true）。
	 *   - 实测歌曲路径能归还 ~590MB（reserved 700 → 113MB），靠的正是引擎
	 *     `PlayState.destroy → GameplayGC.abort() → __hxcpp_gc_leave_gameplay(false)`
	 *     里那次 `InternalCollect(true, false)`。
	 *   - 而**编谱器这条路径没有 gameplay 模式可退** → 900MB 预留永不归还 →
	 *     用户看到"退出编谱器 APP MEM 不降"。
	 *
	 * 所以这里主动做一次 "进入极小的 gameplay 预留 + 立刻带回收退出"，
	 * 借那条路径触发一次整理式回收。仅在**当前不在** gameplay 模式时做，
	 * 免得把正在游玩中的 GC 保护参数（96MB/384MB 预留）冲掉。
	 */
	public static function forceHeapReturn():Void
	{
		#if (cpp && !hxcpp_zgc)
		try
		{
			if (general.backend.gc.GCManager.isGameplayMode()) return;

			var before:Float = Gc.memInfo64(1);
			general.backend.gc.GCManager.enterGameplay(1024 * 1024, 2 * 1024 * 1024);
			general.backend.gc.GCManager.leaveGameplay(true);
			var after:Float = Gc.memInfo64(1);
			if (after < before)
				lastReport += ' | heapReturn: reserved ' + Math.round(before / 1048576) + 'MB -> ' + Math.round(after / 1048576) + 'MB';
			#if NF_LEAK_PROBE
			try general.backend.debug.LeakProbe.logLine('    [ledger] heapReturn: reserved ' + Math.round(before / 1048576)
				+ 'MB -> ' + Math.round(after / 1048576) + 'MB (usage ' + Math.round(Gc.memInfo64(0) / 1048576) + 'MB)')
			catch (e:Dynamic) {}
			#end
		}
		catch (e:Dynamic) {}
		#end
	}

	/** 递归收集一个对象（状态/容器/精灵）持有的图形键 */
	static function collectGraphics(b:Dynamic, keep:Map<String, Bool>, depth:Int):Void
	{
		if (b == null || depth > 5) return;
		try
		{
			var g:Dynamic = Reflect.field(b, 'graphic');
			if (g != null)
			{
				var key:Dynamic = Reflect.field(g, 'key');
				if (key != null) keep.set(cast key, true);
			}
		}
		catch (e:Dynamic) {}
		try
		{
			var members:Dynamic = Reflect.field(b, 'members');
			if (members != null)
			{
				var arr:Array<Dynamic> = cast members;
				var n:Int = arr.length > 40000 ? 40000 : arr.length;
				for (i in 0...n)
					collectGraphics(arr[i], keep, depth + 1);
			}
		}
		catch (e:Dynamic) {}
		// FlxText 的文本图形在 textObj/textField 链上也要覆盖
		try
		{
			var t:Dynamic = Reflect.field(b, 'textObj');
			if (t != null && t != b) collectGraphics(t, keep, depth + 1);
		}
		catch (e:Dynamic) {}
	}
}

private typedef OwnerEntry =
{
	var baseline:Map<String, Bool>;
	var owned:Map<String, Bool>;
}
