package developer.display;

import cpp.vm.Gc;
import flixel.FlxG;
import flixel.input.keyboard.FlxKey;
import openfl.Lib;

/**
 * 调试监控（DebugMonitor）—— 采集引擎运行时数据，供"屏幕外面的面板"和 .erdb 导出使用。
 *
 * 采什么：
 *   - FPS（平滑值）
 *   - 内存：GC 使用/预留/当前/大对象池 + **进程工作集**（hxcpp 的 MEM_INFO_PROCESS，索引 4）
 *   - 当前界面：状态类名 **以及它对应的 .hx 文件路径**（自动在 source/ 与依赖目录里找）
 *   - 键盘：最近按下的按键（带时间戳的队列）
 *   - 鼠标：屏幕坐标/世界坐标 + 左中右按键的按下与释放
 *   - 引擎计数：图形缓存 / 声音列表 / 相机 / 插件 / 补间 / 定时器
 *
 * 怎么用：
 *   - 数据采集常驻（开销极小，只保留最近若干条按键）；
 *   - **F3** 开关"实时写文件"（默认不开，避免正常游玩时一直写盘）；
 *   - **F4** 一键导出 `DebugEditor.erdb`（当前详情 + 本次会话的快照历史）；
 *   - 环境变量 `NF_DEBUG_MONITOR=1` 可在启动时就打开实时写文件。
 *
 * 文件（都在游戏运行目录，即 exe 同级）：
 *   debug_live.json    —— 外部面板 `_dsh_tools/debug_monitor.ps1` 每 0.25s 读取并显示
 *   DebugEditor.erdb   —— 一键导出的调试快照库（文本格式，方便 grep/diff）
 */
class DebugMonitor
{
	public static var liveLogging(default, null):Bool = false;
	public static var livePath(default, null):String = 'debug_live.json';
	public static var exportPath(default, null):String = 'DebugEditor.erdb';

	static var inited:Bool = false;
	static var writeAccum:Float = 0;
	static var uiAccum:Float = 0;
	static var fpsSmooth:Float = 0;
	static var frames:Int = 0;
	static var startedAt:Float = 0;
	static var lastExport:String = '';
	/** 上次回收的结果（面板/F7 用） */
	static var lastReclaim:String = '';

	// ── 快捷键（**不硬编码**）：默认 F3 开关面板 / F4 导出 / F7 回收，
	//    可用环境变量 NF_DEBUG_KEYS 覆盖，例如：
	//      NF_DEBUG_KEYS=display:F5,export:F6,reclaim:F8
	//      NF_DEBUG_KEYS=off            （完全不用快捷键，只保留环境变量/外部触发）
	static var keyDisplay:FlxKey = FlxKey.F3;
	static var keyExport:FlxKey = FlxKey.F4;
	static var keyReclaim:FlxKey = FlxKey.F7;
	static var hotkeysEnabled:Bool = true;
	static var keysConfig:String = 'default(Ctrl+F3/F4/F7)';

	public static function hotkeyInfo():String
	{
		return hotkeysEnabled ? keysConfig : 'off';
	}

	static function applyKeyConfig():Void
	{
		#if sys
		try
		{
			var cfg:String = Sys.getEnv('NF_DEBUG_KEYS');
			if (cfg == null || cfg.length == 0) return;
			if (cfg == 'off' || cfg == '0')
			{
				hotkeysEnabled = false;
				keysConfig = 'off';
				return;
			}
			var names:Array<String> = [];
			for (part in cfg.split(','))
			{
				var kv:Array<String> = part.split(':');
				if (kv.length != 2) continue;
				var role:String = StringTools.trim(kv[0]).toLowerCase();
				var keyName:String = StringTools.trim(kv[1]);
				var k:FlxKey = FlxKey.fromString(keyName);
				if (k == FlxKey.NONE) continue;
				switch (role)
				{
					case 'display', 'panel', 'show':
						keyDisplay = k;
						names.push('display=' + keyName);
					case 'export', 'erdb':
						keyExport = k;
						names.push('export=' + keyName);
					case 'reclaim', 'gc':
						keyReclaim = k;
						names.push('reclaim=' + keyName);
				}
			}
			if (names.length > 0) keysConfig = names.join(' ');
		}
		catch (e:Dynamic) {}
		#end
	}

	/** 最近按下的按键（最多保留这么多个） */
	static var keyLog:Array<String> = [];
	static var keyLogMax:Int = 16;
	/** 快照历史（导出 .erdb 用；每秒最多一条，保留最近 600 条 ≈ 10 分钟） */
	static var history:Array<String> = [];
	static var historyAccum:Float = 0;
	static var historyMax:Int = 600;
	/** 最近的鼠标动作 */
	static var mouseLog:Array<String> = [];

	public static function init():Void
	{
		if (inited) return;
		inited = true;

		startedAt = haxe.Timer.stamp();
		#if mobile
		// Mobile has no Ctrl+F3 entry: keep this developer panel unavailable.
		overlayEnabled = false;
		hotkeysEnabled = false;
		keysConfig = 'off(mobile)';
		#else
		applyKeyConfig();
		#end
		try
		{
			if (Sys.getEnv('NF_DEBUG_MONITOR') == '1') liveLogging = true;
			// 默认就把游戏内面板显示出来（用户要求"看得见"）；NF_DEBUG_OVERLAY=0 可关
			#if !mobile
			var ov:String = Sys.getEnv('NF_DEBUG_OVERLAY');
			if (ov == '0') overlayEnabled = false;
			#end
		}
		catch (e:Dynamic) {}

		if (overlayEnabled) mountOverlay();
		FlxG.signals.postUpdate.add(onPostUpdate);

		// ★ 每次界面切换自动把内存现场落盘（gc_diag.log）——排查"退出后内存没回落"用，
		//   用户不需要按任何键、也不需要截图，开发侧直接读文件即可。
		try FlxG.signals.postStateSwitch.add(function():Void dumpDiag('stateSwitch')) catch (e:Dynamic) {}

		// ★ 周期性"工作集收缩"已**移除**（2026-10-01，用户反馈"APP MEM 像心电图"）：
		//   实测它只会造成 686MB → 1MB → 再涨回 686MB 的锯齿（压出去的页马上又被换回来），
		//   既误导判断又白费性能。工作集本来就会随访问波动，**它不是泄漏指标**：
		//   判断泄漏要看 GC used（存活对象）与 reserved。
		//   现在只在"界面切换"时压一次（见 MusicBeatState → ResourceLedger.compactIfBloated），
		//   以及用户按 F7 手动触发；不再周期性执行。
		// try FlxG.signals.postUpdate.add(autoTrimTick) catch (e:Dynamic) {}

		// ★ 启动时把"构建标识"写到 exe 同目录的 build_stamp.txt（2026-10-01 加）。
		//   动机：反复出现"我测的是哪个 exe"的混乱 —— 旧构建（保守扫描）在退出大场景后
		//   reserved 会停在 700~900MB，新构建（HXCPP_VISIT_ALLOCS，堆内精确遍历）会回落到
		//   100MB 级；两者的 DebugMonitor 面板长得一样，肉眼分不出来。
		//   现在不用开游戏、不用截图：看这个文件、或者 findstr 搜 exe 里的 NFGCMODE 即可。
		try
		{
			var exe:String = '';
			try exe = Sys.executablePath() catch (e:Dynamic) {}
			var dir:String = '';
			var slash:Int = exe.lastIndexOf('\\');
			if (slash < 0) slash = exe.lastIndexOf('/');
			if (slash > 0) dir = exe.substr(0, slash + 1);

			var mode:String = #if HXCPP_VISIT_ALLOCS 'VISIT_ALLOCS' #else 'CONSERVATIVE' #end;
			var human:String = #if HXCPP_VISIT_ALLOCS '堆内精确遍历(新)' #else '保守扫描(旧)' #end;
			var built:String = '?';
			try built = sys.FileSystem.stat(exe).mtime.toString() catch (e:Dynamic) {}

			var stamp:String = 'NFGCMODE=' + mode + '\n'
				+ 'GC说明=' + human + '\n'
				+ 'exe=' + exe + '\n'
				+ '构建时间=' + built + '\n'
				+ '（本文件由 DebugMonitor 启动时写入。若 GC说明 是"保守扫描(旧)"，说明跑的是旧构建，\n'
				+ '  退出大场景后 reserved 会停在 700~900MB，属于预期行为，请改用 VISIT_ALLOCS 构建。）\n';
			if (dir.length > 0) sys.io.File.saveContent(dir + 'build_stamp.txt', stamp);
		}
		catch (e:Dynamic) {}
	}

	public static var overlayEnabled:Bool = #if mobile false #else true #end;
	static var overlay:Dynamic = null;

	/** 把游戏内调试面板挂到 openfl stage 顶层（跨状态存活、不受相机/缩放影响） */
	static function mountOverlay():Void
	{
		#if (sys && !mobile)
		try
		{
			if (overlay != null) return;
			var stageOpenfl = openfl.Lib.current != null ? openfl.Lib.current.stage : null;
			if (stageOpenfl == null)
			{
				// 舞台还没就绪时延后一帧再挂
				FlxG.signals.postUpdate.addOnce(function() mountOverlay());
				return;
			}
			overlay = new DebugOverlay();
			stageOpenfl.addChild(cast overlay);
			trace('[DebugMonitor] overlay mounted (press Ctrl+' + Std.string(keyDisplay) + ' to toggle)');
		}
		catch (e:Dynamic)
		{
			trace('[DebugMonitor] overlay mount failed: ' + e);
		}
		#end
	}

	static function onPostUpdate():Void
	{
		var elapsed:Float = FlxG.elapsed;
		if (elapsed > 0 && elapsed < 1)
		{
			var fps:Float = 1 / elapsed;
			fpsSmooth = (fpsSmooth <= 0) ? fps : (fpsSmooth * 0.9 + fps * 0.1);
		}
		frames++;

		captureKeys();
		captureMouse();

		// 快捷键（可配置，见 applyKeyConfig）：用 firstJustPressed 拿到实际按键再比对，
		// 避免依赖 FlxKeyList 的私有 check()
		try
		{
			if (hotkeysEnabled && FlxG.keys != null)
			{
				var k:FlxKey = FlxG.keys.firstJustPressed();
				if (k != FlxKey.NONE)
				{
					if (FlxG.keys.anyJustPressed([keyDisplay]) && FlxG.keys.pressed.CONTROL)
					{
						overlayEnabled = !overlayEnabled;
						if (overlay != null)
						{
							var o:Dynamic = overlay;
							try o.setShown(overlayEnabled) catch (e:Dynamic) {}
						}
						trace('[DebugMonitor] overlay ' + (overlayEnabled ? 'ON' : 'OFF'));
					}
					else if (k == keyExport) exportErdb('hotkey:' + Std.string(keyExport));
					// 安全回收：清无人引用的图 + 让 GC 归还空闲堆（含修剪工作集）
					else if (k == keyReclaim) forceReclaim();
				}
			}
		}
		catch (e:Dynamic) {}

		// 外部面板点"导出"时写这个触发文件，引擎这边落实导出（保证导出内容来自引擎本身）
		try
		{
			if (sys.FileSystem.exists('debug_export.trigger'))
			{
				sys.FileSystem.deleteFile('debug_export.trigger');
				exportErdb('panel-button');
			}
		}
		catch (e:Dynamic) {}

		// 快照历史：每 1 秒一条
		historyAccum += elapsed;
		if (historyAccum >= 1.0)
		{
			historyAccum = 0;
			history.push(collect());
			while (history.length > historyMax) history.shift();
		}

		// 实时文件：默认 4 次/秒（面板/外部工具用）
		if (liveLogging)
		{
			writeAccum += elapsed;
			if (writeAccum >= 0.25)
			{
				writeAccum = 0;
				writeLive();
			}
		}

		// 游戏内面板：每 0.2s 刷新一次文本
		if (overlayEnabled && overlay != null)
		{
			uiAccum += elapsed;
			if (uiAccum >= 0.2)
			{
				uiAccum = 0;
				try
				{
					var o:Dynamic = overlay;
					var body:String = lines().join('\n');
					var title:String = overlayTitle();
					o.refresh(title, body);
					// 同时落盘一份，便于"面板到底有没有内容"自证（也能用文本工具核对）
					if (liveLogging)
					{
						try sys.io.File.saveContent('debug_overlay.txt', title + '\n' + body + '\n')
						catch (e:Dynamic) {}
					}
				}
				catch (e:Dynamic) {}
			}
		}
	}

	static function overlayTitle():String
	{
		return 'D.C.E. DebugMonitor  [Ctrl+' + Std.string(keyDisplay) + '] hide  [' + Std.string(keyExport)
			+ '] export erdb  [' + Std.string(keyReclaim) + '] reclaim';
	}

	/**
	 * 给人看的多行快照（游戏内面板用）。
	 * 内存口径与引擎自带调试显示保持一致：D.C.GC 下 APP MEM = 进程私有字节(8)，
	 * legacy 下退化为工作集(4) —— 这样"APP MEM"这一栏和你在引擎里看到的永远同一个数。
	 */
	public static function lines():Array<String>
	{
		var out:Array<String> = [];

		var appMem:Float = Gc.memInfo64(8);
		var appLabel:String = 'APP MEM(private)';
		if (appMem <= 0)
		{
			appMem = Gc.memInfo64(4);
			appLabel = 'APP MEM(workingset)';
		}

		out.push('fps ' + (Math.round(fpsSmooth * 10) / 10) + '   uptime ' + Math.round((haxe.Timer.stamp() - startedAt)) + 's');
		// ★ 指标顺序（2026-10-01 按用户反馈调整）：
		//   **判断内存有没有泄漏请只看 GC used**（存活对象）—— 启动时 75MB，跑完大谱回到主菜单
		//   若仍是 230MB 左右，那多出来的才是真残留。
		//   APP MEM(工作集) 只是"最近访问过的物理页"，会随渲染波动、也会被 EmptyWorkingSet
		//   人为压低再换回（表现为心电图），**不能用来判断泄漏**，所以放到后面并标注。
		out.push('GC used ' + mb(Gc.memInfo64(0)) + ' MB   ← 看这个判断泄漏   (reserved ' + mb(Gc.memInfo64(1))
			+ ' / large ' + mb(Gc.memInfo64(3)) + ' MB)');
		out.push(appLabel + ' ' + mb(appMem) + ' MB  (仅供参考, 会波动)');
		// ★ 关键诊断行放前面（面板高度有限，放末尾会被裁掉 —— 2026-10-01 踩过）
		try out.push(resourceLine()) catch (e:Dynamic) {}
		if (lastReclaim.length > 0) out.push(lastReclaim);
		// ★ 构建标识（2026-10-01 加）：以前分不清"跑的是哪个构建"，导致拿旧 exe 测出旧结果。
		//   mtime = 当前 exe 的构建时间；后半句直接标出 GC 的关键开关是否生效。
		//   `HXCPP_VISIT_ALLOCS` 决定 GC 遍历堆内对象图时是"按真实字段精确走"还是"保守猜测"，
		//   两者在"退出场景后内存能否回收"上差别巨大（实测 App Mem 1018MB → 335MB）。
		try
		{
			var exeTime:String = '?';
			try exeTime = sys.FileSystem.stat(Sys.executablePath()).mtime.toString() catch (e:Dynamic) {}
			#if HXCPP_VISIT_ALLOCS
			out.push('NFGCMODE=VISIT_ALLOCS  build ' + exeTime + '  GC=堆内精确遍历(新)');
			#else
			out.push('NFGCMODE=CONSERVATIVE  build ' + exeTime + '  GC=保守扫描(旧)');
			#end
		}
		catch (e:Dynamic) {}
		var k5:Float = Gc.memInfo64(5), k6:Float = Gc.memInfo64(6), k7:Float = Gc.memInfo64(7);
		if (k5 > 0 || k6 > 0 || k7 > 0)
			out.push('D.C.GC reusable ' + mb(k5) + ' survivor ' + mb(k6) + ' old ' + mb(k7) + ' MB');

		var stateName:String = '(none)';
		try if (FlxG.state != null) stateName = Type.getClassName(Type.getClass(FlxG.state)) catch (e:Dynamic) {}
		out.push('screen: ' + stateName);
		out.push('file  : ' + hxFileOf(stateName));

		try
		{
			if (FlxG.mouse != null)
				out.push('mouse : ' + Std.int(FlxG.mouse.viewX) + ',' + Std.int(FlxG.mouse.viewY)
					+ (FlxG.mouse.pressed ? ' L' : '') + (FlxG.mouse.pressedRight ? ' R' : '') + (FlxG.mouse.pressedMiddle ? ' M' : ''));
		}
		catch (e:Dynamic) {}

		out.push('keys  : ' + (keyLog.length > 0 ? keyLog[keyLog.length - 1] : '(none)'));
		var n:Int = keyLog.length > 1 ? 1 : 0;
		for (i in 2...6)
		{
			var idx:Int = keyLog.length - i;
			if (idx >= 0) out.push('        ' + keyLog[idx]);
		}

		out.push('gfx ' + mapCount(@:privateAccess FlxG.bitmap._cache) + '  snd ' + arrCount(FlxG.sound.list.members)
			+ '  twn ' + arrCount(@:privateAccess flixel.tweens.FlxTween.globalManager._tweens));
		return out;
	}

	static function captureKeys():Void
	{
		try
		{
			var k:FlxKey = FlxG.keys.firstJustPressed();
			if (k != FlxKey.NONE) pushLog(keyLog, '[' + stamp() + '] DOWN ' + keyName(k));
			var r:FlxKey = FlxG.keys.firstJustReleased();
			if (r != FlxKey.NONE) pushLog(keyLog, '[' + stamp() + '] UP ' + keyName(r));
		}
		catch (e:Dynamic) {}
	}

	static function captureMouse():Void
	{
		try
		{
			var m = FlxG.mouse;
			if (m == null) return;
			if (m.justPressed) pushLog(mouseLog, '[' + stamp() + '] LEFT_DOWN @' + Std.int(m.viewX) + ',' + Std.int(m.viewY));
			if (m.justReleased) pushLog(mouseLog, '[' + stamp() + '] LEFT_UP @' + Std.int(m.viewX) + ',' + Std.int(m.viewY));
			if (m.justPressedRight) pushLog(mouseLog, '[' + stamp() + '] RIGHT_DOWN @' + Std.int(m.viewX) + ',' + Std.int(m.viewY));
			if (m.justPressedMiddle) pushLog(mouseLog, '[' + stamp() + '] MIDDLE_DOWN @' + Std.int(m.viewX) + ',' + Std.int(m.viewY));
			if (m.wheel != 0) pushLog(mouseLog, '[' + stamp() + '] WHEEL ' + m.wheel);
		}
		catch (e:Dynamic) {}
	}

	static function pushLog(log:Array<String>, line:String):Void
	{
		log.push(line);
		while (log.length > keyLogMax) log.shift();
	}

	/** 类名 → .hx 文件路径（找到才返回，找不到给类名本身） */
	public static function hxFileOf(className:String):String
	{
		if (className == null) return '?';
		var rel:String = className.split('.').join('/') + '.hx';

		// 先从游戏运行目录（export/.../bin）逐级往上找项目根的 source/
		if (sourceRoot == null) sourceRoot = resolveSourceRoot();
		if (sourceRoot != null)
		{
			var p1:String = sourceRoot + '/' + rel;
			try if (sys.FileSystem.exists(p1)) return p1 catch (e:Dynamic) {}
			var p2:String = sourceRoot + '/../source-codename/' + rel;
			try if (sys.FileSystem.exists(p2)) return p2 catch (e:Dynamic) {}
		}

		var candidates:Array<String> = [
			'source/' + rel,
			'../source/' + rel,
			'../../source/' + rel,
			'../../../source/' + rel,
			'../../../../source/' + rel,
			'../../../../../source/' + rel
		];
		for (c in candidates)
		{
			try
			{
				if (sys.FileSystem.exists(c)) return c;
			}
			catch (e:Dynamic) {}
		}
		// flixel / openfl / lime 等依赖：按包前缀猜目录
		if (StringTools.startsWith(className, 'flixel'))
		{
			var p:String = '../../dependencies/flixel-5.9.0-main/' + rel;
			try if (sys.FileSystem.exists(p)) return p catch (e:Dynamic) {}
		}
		return className;
	}

	/** 从当前目录逐级向上找含 source/ 的项目根 */
	static function resolveSourceRoot():String
	{
		try
		{
			var dir:String = Sys.getCwd();
			for (i in 0...8)
			{
				if (dir == null || dir.length == 0) break;
				var candidate:String = dir + (StringTools.endsWith(dir, '/') || StringTools.endsWith(dir, '\\') ? '' : '/') + 'source';
				try
				{
					if (sys.FileSystem.exists(candidate) && sys.FileSystem.isDirectory(candidate))
						return candidate;
				}
				catch (e:Dynamic) {}
				var up:String = haxe.io.Path.directory(dir);
				if (up == null || up == dir || up.length == 0) break;
				dir = up;
			}
		}
		catch (e:Dynamic) {}
		return null;
	}

	static var sourceRoot:String = null;

	static inline function stamp():String
	{
		return haxe.Timer.stamp() - startedAt < 0 ? '0.0' : '' + Math.round((haxe.Timer.stamp() - startedAt) * 10) / 10 + 's';
	}

	/** FlxKey 是抽象枚举，转成可读名字（用 Reflect 读枚举构造名） */
	static function keyName(k:FlxKey):String
	{
		try
		{
			var s:String = Std.string(k);
			return s != null ? s : '?';
		}
		catch (e:Dynamic) {}
		return '?';
	}

	static inline function mb(bytes:Float):Float
	{
		return Math.round(bytes / 1048576 * 10) / 10;
	}

	static function mapCount(m:Dynamic):Int
	{
		if (m == null) return -1;
		try
		{
			var n:Int = 0;
			for (_ in (cast m : Map<String, Dynamic>).keys()) n++;
			return n;
		}
		catch (e:Dynamic) {}
		return -1;
	}

	static function arrCount(a:Dynamic):Int
	{
		if (a == null) return -1;
		try return (cast a : Array<Dynamic>).length catch (e:Dynamic) {}
		return -1;
	}

	/** 采一行数据（JSON，便于外部解析，也便于 .erdb 里按行读） */
	public static function collect():String
	{
		var stateName:String = '(none)';
		var hxFile:String = '?';
		try
		{
			if (FlxG.state != null)
			{
				stateName = Type.getClassName(Type.getClass(FlxG.state));
				hxFile = hxFileOf(stateName);
			}
		}
		catch (e:Dynamic) {}

		var mx:Float = -1, my:Float = -1, mvx:Float = -1, mvy:Float = -1;
		var mDown:Bool = false, mRight:Bool = false, mMid:Bool = false;
		try
		{
			if (FlxG.mouse != null)
			{
				mx = Math.round(FlxG.mouse.x * 10) / 10;
				my = Math.round(FlxG.mouse.y * 10) / 10;
				mvx = Math.round(FlxG.mouse.viewX * 10) / 10;
				mvy = Math.round(FlxG.mouse.viewY * 10) / 10;
				mDown = FlxG.mouse.pressed;
				mRight = FlxG.mouse.pressedRight;
				mMid = FlxG.mouse.pressedMiddle;
			}
		}
		catch (e:Dynamic) {}

		var line:String = '{';
		line += '"t":"' + Date.now().toString() + '"';
		line += ',"uptime":' + Math.round((haxe.Timer.stamp() - startedAt) * 10) / 10;
		line += ',"fps":' + Math.round(fpsSmooth * 10) / 10;
		line += ',"frames":' + frames;
		line += ',"heapUsedMB":' + mb(Gc.memInfo64(0));
		line += ',"heapReservedMB":' + mb(Gc.memInfo64(1));
		line += ',"heapCurrentMB":' + mb(Gc.memInfo64(2));
		line += ',"heapLargeMB":' + mb(Gc.memInfo64(3));
		// kind 4 在两套 GC 下语义不同：
		//   D.C.GC（默认配置 / hxcpp_zgc）→ committedBytes（已提交物理页）
		//   legacy（-D legacy_gc_compare）  → process（进程工作集）
		line += ',"memKind4MB":' + mb(Gc.memInfo64(4));
		line += ',"memKind5MB":' + mb(Gc.memInfo64(5)); // D.C.GC: reusable 虚拟预留
		line += ',"memKind6MB":' + mb(Gc.memInfo64(6)); // D.C.GC: survivor 占用
		line += ',"memKind7MB":' + mb(Gc.memInfo64(7)); // D.C.GC: old 代占用
		// kind 8 = 进程私有字节（PrivateUsage）—— 就是引擎调试显示里的 “APP MEM”
		line += ',"appMemMB":' + mb(Gc.memInfo64(8));
		line += ',"gcKind":"' + (Gc.memInfo64(8) > 0 ? 'dcgc' : 'legacy') + '"';
		line += ',"state":"' + stateName + '"';
		line += ',"stateFile":"' + hxFile.split('\\').join('/') + '"';
		line += ',"graphics":' + mapCount(@:privateAccess FlxG.bitmap._cache);
		line += ',"sounds":' + arrCount(FlxG.sound.list.members);
		line += ',"cameras":' + arrCount(FlxG.cameras.list);
		line += ',"plugins":' + arrCount(FlxG.plugins.list);
		line += ',"tweens":' + arrCount(@:privateAccess flixel.tweens.FlxTween.globalManager._tweens);
		line += ',"timers":' + arrCount(@:privateAccess flixel.util.FlxTimer.globalManager._timers);
		line += ',"mouseX":' + mvx + ',"mouseY":' + mvy + ',"worldX":' + mx + ',"worldY":' + my;
		line += ',"mouseLeft":' + mDown + ',"mouseRight":' + mRight + ',"mouseMiddle":' + mMid;
		line += ',"recentKeys":[' + joinQuoted(keyLog, 8) + ']';
		line += ',"recentMouse":[' + joinQuoted(mouseLog, 6) + ']';
		line += '}';
		return line;
	}

	static function joinQuoted(arr:Array<String>, max:Int):String	{
		var out:Array<String> = [];
		var from:Int = arr.length - max;
		if (from < 0) from = 0;
		for (i in from...arr.length)
			out.push('"' + StringTools.replace(arr[i], '"', "'") + '"');
		return out.join(',');
	}

	static function writeLive():Void
	{
		try
		{
			sys.io.File.saveContent(livePath, collect() + '\n');
		}
		catch (e:Dynamic) {}
	}

	/**
	 * 手动回收（F7）。
	 *
	 * ⚠ 早期版本这里是"按保护名单强制销毁名单外的所有图形"，结果把**当前界面正在用的
	 *   FlxText 文本图形**也一起销毁了 —— 表现为满屏文字变成色块（实测踩过）。
	 *   现在只做两件安全的事：
	 *     1) `FlxG.bitmap.clearUnused()`：只清 useCount<=0 且非 persist 的图（正被使用的图不受影响）；
	 *     2) `ResourceLedger.compactIfBloated()`：让 hxcpp 把空闲堆归还操作系统
	 *        （退出大场景后 reserved 卡在 772MB / usage 90MB、进程 1GB 不降，就是这一步能治的）。
	 *   真正的"按场景清理"由 ResourceLedger.releaseOwned() 在界面 destroy 时自动完成。
	 */
	public static function reclaimUnusedGraphics(reason:String = ''):Void
	{
		var before:Float = Gc.memInfo64(4);
		var reservedBefore:Float = Gc.memInfo64(1);
		try
		{
			FlxG.bitmap.clearUnused();
			ResourceLedger.compactIfBloated(64);
			// ★ 手动回收时**才**收缩工作集（自动路径已移除，避免"心电图"式锯齿）。
			//   这是用户主动按 F7 / 点导出时的动作，压出去的页之后再被访问会换回来，属预期。
			ResourceLedger.trimWorkingSet();
		}
		catch (e:Dynamic) {}
		try Gc.run(true) catch (e:Dynamic) {}

		lastReclaim = '回收(' + reason + '): 进程 ' + mb(before) + '->' + mb(Gc.memInfo64(4)) + 'MB；预留堆 '
			+ mb(reservedBefore) + '->' + mb(Gc.memInfo64(1)) + 'MB；工作集回收 ' + ResourceLedger.lastTrimInfo
			+ '；' + ResourceLedger.lastInfo();
		trace('[DebugMonitor] ' + lastReclaim);
	}

	/** F7 手动触发同一个回收 */
	public static function forceReclaim():Void
	{
		reclaimUnusedGraphics('hotkey:F7');
		dumpDiag('hotkey:F7');
	}

	/** 诊断落盘目录（= exe 同目录）。用户机器就是开发机，直接读文件比反复截图可靠。 */
	static var diagDir:String = '';

	/** 上次自动收缩的时间（节流用） */
	static var lastAutoTrim:Float = -100;

	/**
	 * 条件式工作集回收（每帧调用，内部节流）。
	 *
	 * ★ 2026-10-01 修正：早期版本每 3 秒就可能压一次，实测造成工作集在 **1MB ↔ 540MB 之间反复跳**
	 *   （压出去 → 游戏马上又要用 → 缺页换回），既让面板数字看起来"很不稳定"，也白费性能。
	 *   现在改成**保守得多**的策略：距离上次至少 25 秒，且必须"工作集明显高于真实占用"才压一次；
	 *   正常游玩/主菜单闲置时都不会触发。真正让内存数字长期偏高的原因不是"没收缩"，
	 *   而是**真实存活对象**（实测跑完大谱后 used 比基线多 152MB），那个要靠释放对象解决。
	 */
	static function autoTrimTick():Void
	{
		#if (cpp && windows)
		try
		{
			var now:Float = haxe.Timer.stamp();
			if (now - lastAutoTrim < 25.0) return;
			var ws:Float = Gc.memInfo64(4);
			var used:Float = Gc.memInfo64(0);
			var reserved:Float = Gc.memInfo64(1);
			// 工作集要比"真实占用(used+large 之外的活跃部分)"高出至少 350MB 才值得压
			var realUse:Float = used + (reserved - used) * 0.15; // 保守估计真实需要的工作集
			if (ws > realUse + 350 * 1048576)
			{
				lastAutoTrim = now;
				developer.display.ResourceLedger.compactIfBloated(384);
				logDiag('autoTrim: 工作集 ' + mb(ws) + 'MB → ' + mb(Gc.memInfo64(4)) + 'MB (used=' + mb(used) + ' reserved=' + mb(reserved) + ')');
			}
		}
		catch (e:Dynamic) {}
		#end
	}

	/** 只写 gc_diag.log（时间线），不覆盖 gc_diag.txt */
	static function logDiag(line:String):Void
	{
		try
		{
			ensureDiagDir();
			if (diagDir.length == 0) return;
			var f = sys.io.File.append(diagDir + 'gc_diag.log', false);
			f.writeString(Date.now().toString() + ' | ' + line + '\n');
			f.close();
		}
		catch (e:Dynamic) {}
	}

	static function ensureDiagDir():Void
	{
		if (diagDir.length > 0) return;
		var exe:String = '';
		try exe = Sys.executablePath() catch (e:Dynamic) {}
		var slash:Int = exe.lastIndexOf('\\');
		if (slash < 0) slash = exe.lastIndexOf('/');
		if (slash > 0) diagDir = exe.substr(0, slash + 1);
	}

	static function currentStateName():String
	{
		var n:String = '(none)';
		try if (FlxG.state != null) n = Type.getClassName(Type.getClass(FlxG.state)) catch (e:Dynamic) {}
		return n;
	}

	/**
	 * 把"内存现场"落盘：exe 同目录 `gc_diag.txt`（覆盖=最新）+ `gc_diag.log`（追加=时间线）。
	 *
	 * 为什么这么做（2026-10-01）：排查"退出大场景后内存没回落"时，靠用户截图 + OCR 既慢又不可靠
	 * （面板底部的行还会被裁掉、中文识别成乱码）。既然用户就在同一台机器上跑，
	 * 就让程序把关键数值直接写成文件，开发侧读文件即可对齐时间线。
	 *
	 * 触发点：每次状态切换（自动，用户什么都不用做）+ 按 F7。
	 */
	public static function dumpDiag(reason:String):Void
	{
		try
		{
			ensureDiagDir();
			if (diagDir.length == 0) return;
			var line:String = Date.now().toString() + ' | ' + reason
				+ ' | uptime=' + Math.round(haxe.Timer.stamp() - startedAt) + 's'
				+ ' | state=' + currentStateName()
				+ ' | appMem=' + mb(Gc.memInfo64(4)) + 'MB'
				+ ' | used=' + mb(Gc.memInfo64(0)) + ' reserved=' + mb(Gc.memInfo64(1)) + ' large=' + mb(Gc.memInfo64(3)) + 'MB'
				+ ' | ' + resourceLine()
				+ ' | trim=' + developer.display.ResourceLedger.lastTrimInfo;
			sys.io.File.saveContent(diagDir + 'gc_diag.txt', line + '\n');
			var f = sys.io.File.append(diagDir + 'gc_diag.log', false);
			f.writeString(line + '\n');
			f.close();
		}
		catch (e:Dynamic) {}
	}

	/**
	 * 资源构成一行（2026-10-01 加）：退出大场景后，内存到底是被"图 / 音 / 素材缓存"占着，
	 * 还是对象本身还活着。配合 F7 的回收结果一起看就能判断该修哪一头：
	 *   图多 → 图形缓存没清；音多 → 音频缓存没清；都不多而 GC used 高 → 是活对象，需按类型定位。
	 */
	public static function resourceLine():String
	{
		var g:Int = 0, snd:Int = 0, cA:Int = 0, cS:Int = 0, cF:Int = 0, cL:Int = 0, mem:Int = 0;
		try
		{
			@:privateAccess
			for (k in FlxG.bitmap._cache.keys())
				if (k != null) g++;
		}
		catch (e:Dynamic) {}
		try
		{
			if (FlxG.sound != null && FlxG.sound.list != null) snd = FlxG.sound.list.length;
		}
		catch (e:Dynamic) {}
		try
		{
			for (k in general.backend.Cache.currentTrackedAssets.keys())
				if (k != null) cA++;
		}
		catch (e:Dynamic) {}
		try
		{
			for (k in general.backend.Cache.currentTrackedSounds.keys())
				if (k != null) cS++;
		}
		catch (e:Dynamic) {}
		try
		{
			for (k in general.backend.Cache.currentTrackedFrames.keys())
				if (k != null) cF++;
		}
		catch (e:Dynamic) {}
		try
		{
			cL = general.backend.Cache.localTrackedAssets.length;
		}
		catch (e:Dynamic) {}
		try
		{
			if (FlxG.state != null) mem = FlxG.state.members.length;
		}
		catch (e:Dynamic) {}
		return '资源: 图=' + g + ' 音轨=' + snd + ' 素材缓存(图/音/帧)=' + cA + '/' + cS + '/' + cF + ' 本状态资源=' + cL + ' 成员=' + mem;
	}
	/** 递归收集一个 FlxBasic（含容器）实际持有的图形 key，放进保护名单 */
	static function collectSprites(b:Dynamic, keep:Map<String, Bool>, depth:Int):Void
	{
		if (b == null || depth > 4) return;
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
				var n:Int = arr.length > 20000 ? 20000 : arr.length;
				for (i in 0...n)
					collectSprites(arr[i], keep, depth + 1);
			}
		}
		catch (e:Dynamic) {}
	}

	/** 一键导出 DebugEditor.erdb：当前详情 + 本次会话快照历史 + 采集说明 */	public static function exportErdb(reason:String = 'manual'):Void
	{
		try
		{
			var sb:StringBuf = new StringBuf();
			sb.add('ERDB/1\n');
			sb.add('# D.C.E. DebugEditor dump\n');
			sb.add('# 用途：把"当时的引擎状态"整包带出来（面板/日志/复现报告都靠它对齐时间线）\n');
			sb.add('# 字段说明：stateFile = 当前界面对应的 .hx 源文件；processMB = 进程工作集；\n');
			sb.add('#           recentKeys/recentMouse = 最近按键与鼠标动作（含时间偏移）；\n');
			sb.add('#           history = 每秒一条的快照序列（同一格式的 JSON 行）。\n');
			sb.add('reason=' + reason + '\n');
			sb.add('exported_at=' + Date.now().toString() + '\n');
			sb.add('uptime=' + Math.round((haxe.Timer.stamp() - startedAt) * 10) / 10 + '\n');
			sb.add('frames=' + frames + '\n');
			sb.add('build=' + '#if NF_LEAK_PROBE probe #end' + '' + '\n');
			sb.add('\n--- CURRENT ---\n');
			sb.add(collect() + '\n');
			sb.add('\n--- HISTORY (' + history.length + ' 条，最新在最后) ---\n');
			for (h in history) sb.add(h + '\n');
			sb.add('\n--- KEYS (最近 ' + keyLog.length + ' 条) ---\n');
			for (k in keyLog) sb.add(k + '\n');
			sb.add('\n--- MOUSE (最近 ' + mouseLog.length + ' 条) ---\n');
			for (m in mouseLog) sb.add(m + '\n');
			sb.add('\n--- END ---\n');

			sys.io.File.saveContent(exportPath, sb.toString());
			lastExport = exportPath + ' @ ' + Date.now().toString();
			trace('[DebugMonitor] exported ' + exportPath);
		}
		catch (e:Dynamic)
		{
			trace('[DebugMonitor] export failed: ' + e);
		}
	}

	public static function lastExportInfo():String
	{
		return lastExport;
	}

	public static function lastReclaimInfo():String
	{
		return lastReclaim;
	}
}
