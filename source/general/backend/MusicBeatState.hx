package general.backend;

import openfl.Lib;

import flixel.addons.ui.FlxUIState;

import general.backend.PsychCamera;
import mobile.objects.EditorMobileKeys;
import mobile.objects.EditorMobileKeyOverlay;

import general.shaders.ColorblindFilter;

#if hxvlc
import VideoHandler;
#end

class MusicBeatState extends FlxUIState
{
	public static var instance:MusicBeatState;

	private var curSection:Int = 0;
	private var stepsToDo:Int = 0;

	private var curStep:Int = 0;
	private var curBeat:Int = 0;

	private var curDecStep:Float = 0;
	private var curDecBeat:Float = 0;

	public var controls(get, never):Controls;

	private function get_controls()
	{
		return Controls.instance;
	}

	public var virtualPad:FlxVirtualPad;
	public var mobileControls:MobileControls;
	public var camControls:FlxCamera;
	public var vpadCam:FlxCamera;
	/** “调整移动端各Editor键位”开启时 Editor 里的自定义按键覆盖层 */
	public var editorMobileOverlay:EditorMobileKeyOverlay;

	public function editorMobileModalOpen():Bool
	{
		var history:developer.editors.EditorDocumentHistory = cast Reflect.field(this, 'documentHistory');
		return subState != null || (history != null && history.panel.visible);
	}
	public function editorMobilePointerBlocked(x:Float, y:Float):Bool
	{
		var history:developer.editors.EditorDocumentHistory = cast Reflect.field(this, 'documentHistory');
		return history != null && history.containsPoint(x, y);
	}

	public function addVirtualPad(DPad:FlxDPadMode, Action:FlxActionMode)
	{
		virtualPad = new FlxVirtualPad(DPad, Action);
		virtualPad.alpha = ClientPrefs.data.controlsAlpha + 0.000001;
		add(virtualPad);
		#if desktop
		if (!ClientPrefs.data.needMobileControl)
		{
			virtualPad.alpha = 0;
			virtualPad.active = virtualPad.visible = false;
		}
		#end
		EditorMobileKeys.onVirtualPadAdded(this);
	}

	public function removeVirtualPad()
	{
		if (virtualPad != null)
			remove(virtualPad);
	}

	public function addMobileControls(DefaultDrawTarget:Bool = true):Void
	{
		controls.isInSubstate = false;
		mobileControls = new MobileControls();

		var stage = Lib.current.stage;

		var scale:Float;
		var newWidth:Int;
		var newHeight:Int;

		if (ClientPrefs.data.useFlixelCoords)
		{
			newWidth = Std.int(FlxG.width);
			newHeight = Std.int(FlxG.height);
		}
		else
		{
			scale = Math.min((stage.stageWidth / FlxG.width), (stage.stageHeight / FlxG.height));
			newWidth = Std.int(stage.stageWidth / scale);
			newHeight = Std.int(stage.stageHeight / scale);
		}

		camControls = new FlxCamera(0, 0, newWidth, newHeight);

		camControls.x = (FlxG.width - newWidth) / 2;
		camControls.y = (FlxG.height - newHeight) / 2;
		camControls.bgColor.alpha = 0;
		FlxG.cameras.add(camControls, DefaultDrawTarget);

		mobileControls.cameras = [camControls];
		mobileControls.alpha = ClientPrefs.data.playControlsAlpha + 0.000001;
		add(mobileControls);
		#if desktop
		if (!ClientPrefs.data.needMobileControl)
		{
			mobileControls.alpha = 0;
			mobileControls.active = mobileControls.visible = false;
		}
		#end
	}

	public function removeMobileControls()
	{
		if (mobileControls != null)
			mobileControls = FlxDestroyUtil.destroy(mobileControls);
	}

	public function addVirtualPadCamera(DefaultDrawTarget:Bool = true):Void
	{
		if (virtualPad != null)
		{
			var stage = Lib.current.stage;

			var scale:Float;
			var newWidth:Int;
			var newHeight:Int;

			if (ClientPrefs.data.useFlixelCoords)
			{
				newWidth = Std.int(FlxG.width);
				newHeight = Std.int(FlxG.height);
			}
			else
			{
				scale = Math.min((stage.stageWidth / FlxG.width), (stage.stageHeight / FlxG.height));
				newWidth = Std.int(stage.stageWidth / scale);
				newHeight= Std.int(stage.stageHeight / scale);
			}
			vpadCam = new FlxCamera(0, 0, newWidth, newHeight);
			vpadCam.bgColor.alpha = 0;
			FlxG.cameras.add(vpadCam, DefaultDrawTarget);
			virtualPad.cameras = [vpadCam];
		}
	}

	override function destroy()
	{
		super.destroy();

		// ★ 清理孤儿按钮：flixel-ui 下拉/步进器等重建列表时会留下既不在 members 销毁链、
		//   也没被显式 destroy 的按钮，其 stage MOUSE_UP 监听器（闭包捕获 this）永久泄漏，
		//   经 stage.__iterators 的 stale DispatchIterator 钉住按钮→父组→整个状态。
		//   super.destroy 已销毁在册按钮，此刻登记表里剩下的全是孤儿，统一摘监听。
		try flixel.ui.FlxButton.releaseOrphaned() catch (e:Dynamic) {}

		#if NF_LEAK_PROBE
		// 状态被销毁后是否真的被回收：切走 + 全量 GC 之后仍在 aliveRefs 名单里 = 有人还拽着它
		general.backend.debug.LeakProbe.watch(this, 'state:' + Type.getClassName(Type.getClass(this)));
		#end

		// ★ 静态 self 引用收尾（见文件末尾 clearStaticSelfRefs）。
		//   注意：**这里绝不能清 MusicBeatState.instance**（踩过的坑，见函数注释）。
		//   它不需要在这里清 —— create() 里 `instance = this` 会被下一个状态直接覆盖；
		//   真的漏网的（不调 super.create 之类的奇葩状态）由 postStateSwitch 兜底重指。

		// 自定义按键覆盖层作为成员会被 super.destroy 一并销毁（含其相机与按键注入），
		// 先把引用清掉，避免 Manager 之后对已销毁对象做二次清理。
		editorMobileOverlay = null;

		// Script-created VideoHandlers live below the mouse in FlxG.game rather
		// than inside this state's member list. A number of hxcodec-era mods
		// call stop() from onDestroy(), but hxvlc's stop() only halts playback:
		// it does not release VLC, its buffers, or the display-tree reference.
		#if hxvlc
		if (variables != null)
		{
			for (value in variables)
			{
				if (Std.isOfType(value, VideoHandler))
				try
				{
					cast(value, VideoHandler).finishVideo();
				}
				catch (e:Dynamic)
				{
					FlxG.log.warn('Could not dispose script video: $e');
				}
			}
		}
		#end

		if (variables != null)
			variables.clear();

		if (virtualPad != null)
		{
			virtualPad = FlxDestroyUtil.destroy(virtualPad);
			virtualPad = null;
		}

		if (mobileControls != null)
		{
			mobileControls = FlxDestroyUtil.destroy(mobileControls);
			mobileControls = null;
		}

		// ★ 兜底：清掉"属于本状态、但没被 add 进成员表所以没被 super.destroy() 销毁"的
		//   PsychUIInputText。它们在构造时把实例方法挂到了全局 stage / lime window 信号上，
		//   漏一个就会用闭包把整个状态钉死（编谱器实测：每开一次多钉一个编辑器实例）。
		//   必须在 super.destroy() 之后调用 —— 那时正常成员已经销毁并从登记表里摘掉了。
		general.backend.ui.PsychUIInputText.releaseOwnedBy(this);

		// ★ 按"归属账本"清理本界面加载的图形/文本图形（引擎原本只认路径素材，
		//   makeGraphic 的唯一图与 FlxText 的 text<N> 图形没人记账 → 退出界面不释放）。
		//   只释放"本界面拥有、且没有别的存活界面共用"的键，所以不会误伤当前界面。
		try
		{
			developer.display.ResourceLedger.releaseOwned(this);
			// 预留远大于在用（进过大场景又退出来）时，让 hxcpp 把空闲堆归还操作系统，
			// 否则进程工作集会一直卡在峰值（实测 reserved 772MB / usage 90MB，WS 1GB 不降）。
			developer.display.ResourceLedger.compactIfBloated(256);
		}
		catch (e:Dynamic) {}

		// ★ 最后再清静态 self 引用（见上方注释：前面的清理可能还要靠 instance 解析 controls）
		clearStaticSelfRefs(this);
		// 指向"本状态或其子状态"的 Note 静态回引用一并兜底
		games.objects.Note.clearFollowStale(this);
		// ★ 兜底收尾：把"不在成员表里的大块内容"确定性地放掉（见 hollowOut 说明）。
		try hollowOut() catch (e:Dynamic) {}
	}

	/**
	 * 掏空（hollow out）：销毁时把**本状态持有、但不属于成员表**的大块内容确定性释放。
	 *
	 * 为什么需要：实测存在一个**反射看不见的根**，会把已经销毁的状态对象壳一直钉住
	 * （`LeakProbe` 静置复检 20s、深清栈、全量静态/汇点消去法都排除过，仍存活）。
	 * 壳本身只有几 MB，但它的字段会连带钉住真正的大头：
	 *   - `PlayState` 的 `unspawnNotes` 保存整张谱的 Note；`EditorPlayState` 现保存轻量谱面项，
	 *     只在生成窗口附近创建 Note，未入场的 sustain 音符由其试玩子状态显式清理；
	 *   - `ChartingState` 的波形浮点数组 / OGG 原始字节缓存 / 段落精灵缓存。
	 * 在这里显式 destroy + 清空，就不依赖 GC 也能把大头还回去。
	 * 子类按需 override（默认什么都不做）。
	 */
	public function hollowOut():Void {}

	/**
	 * 释放一串"不在成员表里"的对象：逐个 destroy（已销毁的跳过，避免二次销毁），
	 * 再把数组清空。用于 `unspawnNotes` 这类"从未 add() 过、super.destroy() 管不到"的容器。
	 *
	 * 判重方式说明：本版 flixel 的 `destroyed` 字段对外不可见，`FlxSprite.destroy()` 会把
	 * `graphic` 置空，所以用 "graphic == null" 当"已经销毁过"的判据（对没有 graphic 的
	 * FlxBasic 会直接跳过，正好也不会误伤）。
	 */
	public static function freeBunch(arr:Array<Dynamic>):Void
	{
		if (arr == null) return;
		for (o in arr)
		{
			if (o == null) continue;
			try
			{
				if (!Std.isOfType(o, flixel.FlxBasic)) continue;
				if (Reflect.field(o, 'graphic') == null) continue;
				cast(o, flixel.FlxBasic).destroy();
			}
			catch (e:Dynamic) {}
		}
		try arr.resize(0) catch (e:Dynamic) {}
	}

	var _psychCameraInitialized:Bool = false;

	public var variables:Map<String, Dynamic> = new Map<String, Dynamic>();

	public static function getVariables()
		return getState().variables;

	/**
	 * 统一的"离开界面就回收该界面资源"钩子。
	 *
	 * 背景（用户实测）：只有 MainMenu / Freeplay / Options / Mods / Loading / Title 等**部分**状态
	 * 在自己的 create() 里调 Paths.clearStoredMemory()+clearUnusedMemory()，其它界面（编辑器、
	 * 结算、成就、Credits、试玩、各种子界面…）根本不调 —— 于是"打开界面内存就涨、退出界面不回落"，
	 * 切来切去只涨不降。
	 *
	 * 时机选 preStateSwitch（**新状态 create 之前**，旧状态已经结束）：
	 *   - 此时重置"本界面资源清单"不会误伤任何界面 —— 新界面还没开始加载；
	 *   - （反面教材：放在基类 create() 里会误清 ModsMenuState / CreditsState 这类
	 *     "先加载资源、后调 super.create()" 的界面。）
	 * 处理完标记后由 Paths.clearStoredMemory() 里的 FlxG.bitmap.clearUnused() 真正把图摘掉，
	 * 所以退出界面时显存/内存会真的落下来，而不是只打个标记。
	 */
	public static function installPreSwitchCleanup():Void
	{
		if (preSwitchCleanupHooked) return;
		preSwitchCleanupHooked = true;
		FlxG.signals.preStateSwitch.add(function():Void
		{
			try
			{
				general.backend.Paths.clearStoredMemory();
				general.backend.Paths.clearUnusedMemory();
			}
			catch (e:Dynamic) {}
		});

		// ★ 切换**完成后**：按"归属账本"回收**本状态自己创建、且别的存活界面没在用**的图形。
		//   （注意：这里早期版本用的是"名单外一律强制销毁"，会把当前界面正在用的
		//     FlxText 文本图形也清掉 —— 表现为满屏文字变成色块，属于严重误伤，已改成
		//     由状态 destroy() 时按账本清理，见 MusicBeatState.destroy 里的 releaseOwnedGraphics）
		FlxG.signals.postStateSwitch.add(function():Void
		{
			try
			{
				developer.display.ResourceLedger.sweepDeadOwners();
				// 新界面已经建好：把"它这次新加载的图形"记进它的账本
				if (FlxG.state != null) developer.display.ResourceLedger.mark(FlxG.state);
			}
			catch (e:Dynamic) {}

			// ★ 兜底重指"当前状态"指针：此刻新状态已经 create（正常都在 create 里写过
			//   instance = this，这里是 no-op）；只有极少数不调 super.create() 的状态会漏。
			//   目的是不让一个已销毁的大状态被这个静态引用一直钉住。
			try
			{
				var st:Dynamic = FlxG.state;
				if (st != null && Std.isOfType(st, MusicBeatState) && instance != st)
					instance = cast st;
			}
			catch (e:Dynamic) {}
		});
	}

	private static var preSwitchCleanupHooked:Bool = false;

	/**
	 * 清掉"静态 self 引用"：本类及其每个父类/子类链上名为 `instance` 的静态字段，
	 * 只要还指向 obj 就置空。
	 *
	 * 为什么需要：引擎里大量状态/子状态都在构造函数里写 `instance = this`
	 * （MusicBeatState / MusicBeatSubstate / PlayState / FreeplayState / EditorPlayState /
	 * GameOverSubstate / NewControlsSubState / CustomSubstate …），但 destroy() 里从不置空。
	 * 于是**最后一个状态/子状态会被静态字段永久钉住**——对被切走的那个实例来说，
	 * 这条引用等于它的整块内存（编谱器 ESC 试玩会为整首谱建出全部 Note 精灵，
	 * 32787 note 的谱一次 600MB+，退出后 GC 堆仍停在 685MB 就是这个原因）。
	 */
	public static function clearStaticSelfRefs(obj:Dynamic):Void
	{
		if (obj == null) return;
		var cls:Class<Dynamic> = Type.getClass(obj);
		var guard:Int = 0;
		while (cls != null && guard++ < 64)
		{
			// ★★ 绝不动 MusicBeatState.instance（进歌崩溃的真凶，记下来）：
			//   `Controls.get_requested()`（source/general/backend/Controls.hx:169-175）在
			//   "非子状态"时就读它，而 `controls` 被 update 循环、LoadingState 的收尾、
			//   各种脚本回调随时取用。旧状态 destroy() 到新状态 create() 之间正好有一个窗口，
			//   把这里清成 null 后，窗口里任何一次 `controls.xxx` 都会解引用 null →
			//   实测就是"从 Freeplay 进歌直接崩"（EXCEPTION_ACCESS_VIOLATION / read 0x148）。
			//   它本来也不需要清：create() 里 `instance = this` 会被下一个状态覆盖，
			//   真的没人覆盖时由 postStateSwitch 兜底重指（见 installPreSwitchCleanup）。
			//
			//   而 MusicBeatSubstate.instance（子状态那份）**要清**：它是"最后一个子状态"
			//   的永久钉子（试玩 600MB 就是这么留住的），且子状态 destroy 时 isInSubstate
			//   已经复位，此后 controls 走 MusicBeatState.instance，清掉不会悬空。
			if (cls != MusicBeatState)
			{
				try
				{
					var cur:Dynamic = Reflect.field(cls, 'instance');
					if (cur != null && cur == obj)
					{
						try Reflect.setField(cls, 'instance', null)
						catch (e:Dynamic) {}
					}
				}
				catch (e:Dynamic) {}
			}
			try cls = Type.getSuperClass(cls) catch (e:Dynamic) { break; }
		}
	}

	override function create()
	{
		EditorMobileKeys.ensureInputPlugin();
		instance = this;

		// 统一的"换界面就回收上一个界面资源"钩子（幂等，只装一次）
		installPreSwitchCleanup();

		// 调试监控（幂等）：采集 FPS/内存/当前界面对应 .hx/按键/鼠标，供屏幕外面的面板与 .erdb 导出
		developer.display.DebugMonitor.init();
		// 资源归属账本：记下"本界面开始时的图形键快照"，退出时只清**本界面加载的**图
		developer.display.ResourceLedger.begin(this);

		#if NF_LEAK_PROBE
		// 内存泄漏探针/复现台（-D NF_LEAK_PROBE 构建 + NF_LEAK_PROBE=1 时才真正工作）
		general.backend.debug.LeakProbe.init();
		general.backend.debug.LeakHarness.onStateCreate(this);
		// create 时登记：能抓到"被换掉却没走 destroy()"的状态（只在 destroy 登记会漏掉这种）
		general.backend.debug.LeakProbe.watchCreated(this, Type.getClassName(Type.getClass(this)));
		#end

		#if (cpp && windows)
		// 沉浸式标题栏管理：StoryMode/游玩/编辑器隐藏系统栏并扩展视口，
		// 游玩类界面支持鼠标靠近顶部时唤出标题栏。
		general.backend.device.WindowChromeManager.onStateChanged(this);
		#end

		var skip:Bool = FlxTransitionableState.skipNextTransOut;
		#if MODS_ALLOWED Mods.updatedOnState = false; #end

		if (!_psychCameraInitialized)
			initPsychCamera();

		ColorblindFilter.UpdateColors();

		super.create();

		if (!skip)
		{
			openSubState(new CustomFadeTransition(0.6, true));
		}
		FlxTransitionableState.skipNextTransOut = false;
		timePassedOnState = 0;
	}

	public function initPsychCamera():PsychCamera
	{
		var camera = new PsychCamera();
		FlxG.cameras.reset(camera);
		FlxG.cameras.setDefaultDrawTarget(camera, true);
		_psychCameraInitialized = true;
		// trace('initialized psych camera ' + Sys.cpuTime());
		return camera;
	}

	public static var timePassedOnState:Float = 0;
	public var allowMinorGc:Bool = true;
	private var lastSavedFullscreen:Null<Bool> = null;
	#if (cpp && windows)
	private var lastChromeFullscreen:Null<Bool> = null;
	#end

	override function update(elapsed:Float)
	{
		// 注意：此处曾有每 60 帧一次 `sys.io.File.append('ui_mark.log', ...)` 的诊断写盘，
		// 在所有状态（含 PlayState）的 update 热路径上做同步 open/write/close，
		// 240TPS 下每秒 4 次 IO 往返，是周期性长帧的来源，已移除。
		// everyStep();
		// Mobile editor input is injected by the plugin before derived-state update.
		var oldStep:Int = curStep;
		timePassedOnState += elapsed;
		updateCurStep();
		updateBeat();

		if (oldStep != curStep)
		{
			if (curStep > 0)
				stepHit();

			if (PlayState.SONG != null)
			{
				if (oldStep < curStep)
					updateSection();
				else
					rollbackSection();
			}
		}

		// 不再把全屏状态写进存档（窗口一律默认窗口化启动，F11 全屏为临时状态）
		if (FlxG.save.data != null && FlxG.save.data.fullscreen)
		{
			// 顺手清掉旧存档里残留的全屏标记，避免旧数据再次生效
			FlxG.save.data.fullscreen = false;
		}

		// This is the hottest stage dispatch in the engine.  Avoid allocating a
		// closure on every update; event/beat dispatches remain on the generic
		// helper because they are infrequent.
		for (stage in stages)
			if (stage != null && stage.exists && stage.active)
				stage.update(elapsed);

		super.update(elapsed);
	}

	override function draw()
	{
		super.draw();
		
		#if TRACY_ALLOWED
			cpp.vm.tracy.TracyProfiler.frameMark();
		#end
	}

	private function updateSection():Void
	{
		if (stepsToDo < 1)
			stepsToDo = Math.round(getBeatsOnSection() * 4);
		while (curStep >= stepsToDo)
		{
			curSection++;
			var beats:Float = getBeatsOnSection();
			stepsToDo += Math.round(beats * 4);
			sectionHit();
		}
	}

	private function rollbackSection():Void
	{
		if (curStep < 0)
			return;

		var lastSection:Int = curSection;
		curSection = 0;
		stepsToDo = 0;
		for (i in 0...PlayState.SONG.notes.length)
		{
			if (PlayState.SONG.notes[i] != null)
			{
				stepsToDo += Math.round(getBeatsOnSection() * 4);
				if (stepsToDo > curStep)
					break;

				curSection++;
			}
		}

		if (curSection > lastSection)
			sectionHit();
	}

	private function updateBeat():Void
	{
		curBeat = Math.floor(curStep / 4);
		curDecBeat = curDecStep / 4;
	}

	private function updateCurStep():Void
	{
		var lastChange = Conductor.getBPMFromSeconds(Conductor.songPosition);

		var shit = ((Conductor.songPosition - ClientPrefs.data.noteOffset) - lastChange.songTime) / lastChange.stepCrochet;
		curDecStep = lastChange.stepTime + shit;
		curStep = lastChange.stepTime + Math.floor(shit);
	}

	public static function switchState(nextState:FlxState = null)
	{
		// ★ 这里以前是"发现任何一个基础键位为空就 keyBinds.clear() + 用默认值重填整张表"。
		//   后果：玩家在键位界面长按 Backspace 删掉任意一条绑定（`clearInvalidKeys` 会把
		//   NONE 直接 remove，数组长度变 0）之后，**下一次状态切换**就会把玩家自定义的
		//   全部键位无声恢复成编译默认值，再被随后的 saveSettings() 写进存档 ——
		//   玩家没碰过 R / Reset，看起来就是"键位偶尔被重置"。
		//   现在改成"谁空了补谁"，其它键位一个字都不动（详见 ClientPrefs.repairMissingKeyBinds）。
		ClientPrefs.repairMissingKeyBinds();

		if (nextState == null)
			nextState = FlxG.state;
		if (nextState == FlxG.state)
		{
			resetState();
			return;
		}

		if (FlxTransitionableState.skipNextTransIn)
			FlxG.switchState(nextState);
		else
			startTransition(nextState);
		FlxTransitionableState.skipNextTransIn = false;
	}

	public static function resetState()
	{
		if (FlxTransitionableState.skipNextTransIn)
			FlxG.resetState();
		else
			startTransition();
		FlxTransitionableState.skipNextTransIn = false;
	}

	// Custom made Trans in
	public static function startTransition(nextState:FlxState = null)
	{
		if (nextState == null)
			nextState = FlxG.state;

		FlxG.state.openSubState(new CustomFadeTransition(0.6, false));
		if (nextState == FlxG.state)
			CustomFadeTransition.finishCallback = function() FlxG.resetState();
		else
			CustomFadeTransition.finishCallback = function() FlxG.switchState(nextState);
	}

	public static function getState():MusicBeatState
	{
		return cast(FlxG.state, MusicBeatState);
	}

	public function stepHit():Void
	{
		stagesFunc(function(stage:BaseStage)
		{
			stage.curStep = curStep;
			stage.curDecStep = curDecStep;
			stage.stepHit();
		});

		if (curStep % 4 == 0)
			beatHit();
	}

	public var stages:Array<BaseStage> = [];

	public function beatHit():Void
	{
		stagesFunc(function(stage:BaseStage)
		{
			stage.curBeat = curBeat;
			stage.curDecBeat = curDecBeat;
			stage.beatHit();
		});
	}

	public function sectionHit():Void
	{
		// trace('Section: ' + curSection + ', Beat: ' + curBeat + ', Step: ' + curStep);
		stagesFunc(function(stage:BaseStage)
		{
			stage.curSection = curSection;
			stage.sectionHit();
		});
	}

	function stagesFunc(func:BaseStage->Void)
	{
		for (stage in stages)
			if (stage != null && stage.exists && stage.active)
				func(stage);
	}

	function getBeatsOnSection()
	{
		var val:Null<Float> = 4;
		if (PlayState.SONG != null && PlayState.SONG.notes[curSection] != null)
			val = PlayState.SONG.notes[curSection].sectionBeats;
		return val == null ? 4 : val;
	}
}
