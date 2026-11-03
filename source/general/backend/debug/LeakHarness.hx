package general.backend.debug;

import flixel.FlxG;
import flixel.FlxState;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import general.backend.MusicBeatState;
import states.titleState.TitleState;

/**
 * 泄漏复现台（自动跑流程的司机）。
 *
 * 与 LeakProbe 配套：LeakProbe 负责"看"，本类负责"走" —— 反复执行真实用户路径
 * （软重启 / 主菜单⇄子界面 / Mods 全开关 + 重启），在**每轮的同一逻辑点**
 * 打一次 checkPoint，于是逐轮的 heap / census / aliveRefs 可以直接对比。
 *
 * 环境变量（一个都不设 = 完全惰性，只多一次 Bool 判断）：
 *   NF_LEAK_ROUNDS=<n>     跑 n 轮
 *   NF_LEAK_MODE=restart   每轮：主菜单 → FlxG.resetGame() 软重启（默认）
 *   NF_LEAK_MODE=cycle     每轮：主菜单 → 子界面 → 主菜单（NF_LEAK_TARGET 选子界面）
 *   NF_LEAK_MODE=mods      每轮：主菜单 → Mods 菜单 → 全部启用/禁用 → 🏠 → 重启游戏
 *   NF_LEAK_MODE=gameplay  每轮：主菜单 → Freeplay →（注入 ENTER）进歌 → 游玩 → 回主菜单
 *   NF_LEAK_DELAY=<秒>     每轮进入主菜单后的等待（默认 3.5s，等加载/音效落定）
 *   NF_LEAK_TARGET=<名字>  cycle 模式的子界面：freeplay|options|mods|achievements|credits|story
 *   NF_LEAK_GAMEPLAY_SEC=<秒>  gameplay 模式在 PlayState 里停留多久（默认 12）
 *   NF_LEAK_TAG=<文本>     写进日志的标记（区分不同实验批次）
 *
 * 日志：LeakProbe 的 leakprobe.log（同一条时间线）。
 */
class LeakHarness
{
	public static var rounds(default, null):Int = 0;
	public static var mode(default, null):String = '';
	public static var delay:Float = 3.5;
	public static var target(default, null):String = 'cycle';

	static var inited:Bool = false;
	static var active:Bool = false;
	static var visits:Int = 0;
	static var busy:Bool = false;
	static var done:Bool = false;
	/** cycle 模式：已切出去的子界面还等着回主菜单 */
	static var awaitingReturn:Bool = false;
	/** mods 模式：等 ModsMenuState 建好再下令开关+重启 */
	static var awaitingMods:Bool = false;
	/** 软重启后标题界面在等 ENTER —— 注入一次真实按键 */
	static var titlePending:Bool = false;
	/** gameplay 模式阶段：0=空闲 1=已进 Freeplay 2=已进 PlayState 3=已安排离开 */
	static var gamePhase:Int = 0;
	static var gameplaySeconds:Float = 12;
	/** editor 模式阶段：1=已下令进编谱器 2=编谱器里等着退出 */
	static var editPhase:Int = 0;
	/** fselect 模式阶段：1=已进 Freeplay 2=正在选歌 */
	static var selectPhase:Int = 0;
	static var selections:Int = 6;
	static var selectGap:Float = 1.6;
	static var staySeconds:Float = 8;
	/** 最后一轮结束后静置多少秒再收一次（NF_LEAK_SETTLE_SEC，0=关） */
	static var settleSeconds:Float = 12;
	/** editor 模式：是否额外做一次 ESC 试玩往返（VerifyPlaytest） */
	static var playtest:Bool = false;
	static var playtestSeconds:Float = 8;
	/** editor 模式：是否用真实退出链（BACKSPACE → 开发工具菜单 → BACKSPACE → 主菜单） */
	static var exitChain:Bool = false;
	/** NF_LEAK_CHART=模组目录|歌曲目录|谱面文件名（编谱器要打开的谱面） */
	static var chartSpec:String = '';
	static var traceStates:Bool = true;
	static var stateLogs:Int = 0;

	/** 每个 state.create() 都会调（见 MusicBeatState.create）。 */
	public static function onStateCreate(state:FlxState):Void
	{
		if (!inited) init();
		if (!active || state == null) return;

		var name:String = Type.getClassName(Type.getClass(state));
		// 完整状态时间线（诊断卡在哪一步用；上限 400 行避免刷爆日志）
		if (traceStates && stateLogs < 400)
		{
			stateLogs++;
			LeakProbe.logLine('[state] ' + name);
		}

		// 标题界面要按 ENTER 才进主菜单：自动化里注入**真实键盘事件**（走 openfl stage →
		// flixel 的 FlxKeyManager），和玩家按键是同一条路径，不做特殊后门。
		// 注意第一次 ENTER 只是跳过开场动画，所以必须重试到真的离开标题界面为止。
		if (titlePending && name == 'states.titleState.TitleState')
		{
			titlePending = false;
			LeakProbe.logLine('[harness] title screen -> inject ENTER (retry until left)');
			titleWatch(0);
			return;
		}

		// mods 模式：ModsMenuState 建好了，下令"全部启用/禁用 → 🏠 → 重启游戏"
		if (awaitingMods && name == 'states.modsMenuState.ModsMenuState')
		{
			awaitingMods = false;
			var enableAll:Bool = (visits % 2 == 1);
			LeakProbe.logLine('[harness] ModsMenuState ready -> toggleAll(' + enableAll + ') + restart');
			new FlxTimer().start(1.5, function(_)
			{
				try
				{
					var m:states.modsMenuState.ModsMenuState = cast state;
					m.debugToggleAllAndRestart(enableAll);
				}
				catch (e:Dynamic)
					LeakProbe.logLine('[harness] mods hook failed: ' + e);
			});
			return;
		}

		// cycle 模式：子界面停留结束 → 回主菜单
		if (awaitingReturn && name != 'states.mainMenuState.MainMenuState')
		{
			awaitingReturn = false;
			LeakProbe.logLine('[harness] entered ' + name + ' -> back to hub in ' + delay + 's');
			new FlxTimer().start(delay, function(_) MusicBeatState.switchState(new states.mainMenuState.MainMenuState()));
			return;
		}

		// gameplay 模式：主菜单 → Freeplay（注入 ENTER 进歌）→ PlayState 停留 → 回主菜单
		if (mode == 'gameplay')
		{
			if (name == 'states.freeplayState.FreeplayState' && gamePhase == 1)
			{
				gamePhase = 2;
				LeakProbe.logLine('[harness] freeplay -> inject ENTER (start first song)');
				new FlxTimer().start(delay, function(_) pressKey(13)); // ENTER = controls.ACCEPT
				return;
			}
			if (name == 'games.PlayState' && gamePhase == 2)
			{
				gamePhase = 3;
				LeakProbe.logLine('[harness] PlayState entered -> leave in ' + gameplaySeconds + 's');
				new FlxTimer().start(gameplaySeconds, function(_)
				{
					gamePhase = 0;
					LeakProbe.logLine('[harness] leaving PlayState -> hub');
					MusicBeatState.switchState(new states.mainMenuState.MainMenuState());
				});
				return;
			}
		}

		// editor 模式：主菜单 → 编谱器（可选指定谱面，建好后停留 staySeconds）→ 回主菜单
		if (mode == 'editor')
		{
			if (name == 'developer.editors.ChartingState' && editPhase == 1)
			{
				editPhase = 2;
				LeakProbe.logLine('[harness] ChartingState entered (stay ' + staySeconds + 's, chart=' + chartSpec + ')');
				// 编辑器"开着"时先打一枪：退出后再打一枪，两次之差就是"退出时到底释放了多少"
				new FlxTimer().start(staySeconds * 0.55, function(_)
				{
					if (LeakProbe.stateName() == 'developer.editors.ChartingState')
						LeakProbe.checkPoint('@ChartingState 仍开着 (round ' + visits + ')');
				});
				// 可选：复现"编谱器里按 ESC 进试玩再回来"（EditorPlayState 的音频/对象是否会释放）
				if (playtest)
				{
					new FlxTimer().start(delay, function(_)
					{
						LeakProbe.logLine('[harness] ChartingState: 按下 ESC -> 试玩');
						pressKey(0x1B);
					});
					new FlxTimer().start(delay + playtestSeconds, function(_)
					{
						LeakProbe.checkPoint('@试玩中 (EditorPlayState, round ' + visits + ')');
						LeakProbe.logLine('[harness] 试玩: 再按 ESC -> 回编谱器');
						pressKey(0x1B);
					});
					new FlxTimer().start(delay + playtestSeconds + 4, function(_)
					{
						LeakProbe.checkPoint('@试玩后回编谱器 (round ' + visits + ')');
					});
				}
				new FlxTimer().start(staySeconds, function(_)
				{
					if (exitChain)
					{
						// 复刻真实退出链：编辑器里按 BACKSPACE → doExitEditor() → 开发工具菜单
						editPhase = 3;
						LeakProbe.logLine('[harness] ChartingState: 注入 BACKSPACE -> 开发工具菜单');
						pressKey(0x08); // BACKSPACE
					}
					else
					{
						editPhase = 0;
						LeakProbe.logLine('[harness] leaving ChartingState -> hub');
						MusicBeatState.switchState(new states.mainMenuState.MainMenuState());
					}
				});
				return;
			}
		}

		// editor 模式 + 真实退出链：开发工具菜单里再按一次 BACKSPACE 回主菜单
		if (mode == 'editor' && exitChain && editPhase == 3 && name == 'developer.editors.MasterEditorMenu')
		{
			editPhase = 4;
			LeakProbe.logLine('[harness] MasterEditorMenu: 注入 BACKSPACE -> 主菜单');
			new FlxTimer().start(2.5, function(_) pressKey(0x08));
			return;
		}

		// fselect 模式：Freeplay 里只"选歌"不进入（注入 DOWN 键 N 次），每轮检查内存是否回落
		if (mode == 'fselect')
		{
			if (name == 'states.freeplayState.FreeplayState' && selectPhase == 1)
			{
				selectPhase = 2;
				LeakProbe.logLine('[harness] freeplay -> select ' + selections + ' songs (no enter)');
				selectWatch(0);
				new FlxTimer().start(delay + selections * selectGap + 2, function(_)
				{
					selectPhase = 0;
					LeakProbe.logLine('[harness] leaving freeplay -> hub');
					MusicBeatState.switchState(new states.mainMenuState.MainMenuState());
				});
				return;
			}
		}

		if (name != 'states.mainMenuState.MainMenuState' || busy) return;

		busy = true;
		LeakProbe.logLine('[harness] hub visit ' + (visits + 1) + '/' + rounds + ' (mode=' + mode + ')');
		new FlxTimer().start(delay, function(_)
		{
			busy = false;
			visits++;
			LeakProbe.checkPoint('round=' + visits + '/' + rounds + ' mode=' + mode + '@MainMenu');

			if (visits >= rounds)
			{
				if (!done)
				{
					if (settleSeconds > 0)
					{
						// ★ 静置复检：退出场景后 3 秒内"对象还活着"未必是泄漏 ——
						//   退场动画/淡出/延迟回调（FlxTimer、FlxTween、音乐 fadeOut）都可能
						//   用闭包多抓几秒。等它们全部跑完再收一次，才能区分
						//   「短暂持有（会自己消失）」和「真泄漏（一直在）」。
						LeakProbe.logLine('[harness] settle ' + settleSeconds + 's then re-check (区分短暂持有 vs 真泄漏)');
						new FlxTimer().start(settleSeconds, function(_)
						{
							LeakProbe.checkPoint('settle +' + settleSeconds + 's (after rounds) mode=' + mode);
							done = true;
							LeakProbe.logLine('[harness] DONE rounds=' + rounds + ' mode=' + mode);
						});
						return;
					}
					done = true;
					LeakProbe.logLine('[harness] DONE rounds=' + rounds + ' mode=' + mode);
				}
				return;
			}
			act();
		});
	}

	/**
	 * 往 openfl stage 注入一次真实键盘事件（按下 → 下一帧抬起）。
	 * flixel 的 FlxKeyManager 就挂在 stage 的 KEY_DOWN/KEY_UP 上，所以这与玩家按键盘等效；
	 * 分开两帧是为了让 justPressed 至少被采样到一次。
	 */
	public static function pressKey(keyCode:Int):Void
	{
		if (FlxG.stage == null) return;
		try
		{
			var down = new openfl.events.KeyboardEvent(openfl.events.KeyboardEvent.KEY_DOWN, true, true, keyCode, keyCode);
			FlxG.stage.dispatchEvent(down);
			new FlxTimer().start(0.05, function(_)
			{
				var up = new openfl.events.KeyboardEvent(openfl.events.KeyboardEvent.KEY_UP, true, true, keyCode, keyCode);
				FlxG.stage.dispatchEvent(up);
			});
		}
		catch (e:Dynamic)
			LeakProbe.logLine('[harness] pressKey(' + keyCode + ') failed: ' + e);
	}

	/** 还停在标题界面就继续按 ENTER（最多 15 次，约 20 秒），离开后停止。 */
	static function titleWatch(tries:Int):Void
	{
		if (tries > 15)
		{
			LeakProbe.logLine('[harness] title screen still there after ' + tries + ' ENTERs - giving up');
			return;
		}
		new FlxTimer().start(1.3, function(_)
		{
			var cn:String = LeakProbe.stateName();
			if (cn == 'states.titleState.TitleState')
			{
				pressKey(13); // ENTER
				titleWatch(tries + 1);
			}
			else
				LeakProbe.logLine('[harness] left title screen -> ' + cn + ' (after ' + tries + ' extra ENTERs)');
		});
	}

	static function act():Void
	{
		switch (mode)
		{
			case 'mods':
				awaitingMods = true;
				titlePending = true; // ModsMenuState 里的 doRestartNow() 之后同样要过标题界面
				MusicBeatState.switchState(new states.modsMenuState.ModsMenuState());

			case 'editor':
				editPhase = 1;
				prepareChart();
				MusicBeatState.switchState(new developer.editors.ChartingState());

			case 'fselect':
				selectPhase = 1;
				LeakProbe.logLine('[harness] -> FreeplayState (select-only)');
				MusicBeatState.switchState(new states.freeplayState.FreeplayState());

			case 'cycle':
				awaitingReturn = true;
				var t:FlxState = makeTarget(visits);
				MusicBeatState.switchState(t);

			case 'gameplay':
				gamePhase = 1;
				MusicBeatState.switchState(new states.freeplayState.FreeplayState());

			default: // restart
				LeakProbe.logLine('[harness] soft restart (FlxG.resetGame)');
				titlePending = true;
				TitleState.initialized = false;
				TitleState.closedState = false;
				FlxG.camera.fade(FlxColor.BLACK, 0.3, false, FlxG.resetGame, false);
		}
	}

	/**
	 * 让编谱器打开指定谱面（`NF_LEAK_CHART=模组目录|歌曲目录|谱面文件名`）。
	 * 不设置就用引擎默认的空 test 谱 —— 空谱量不出东西，压测要用大谱（例如
	 * `BPM-2021|BPM-2021|bpm-2021-camellia`，3 万多条 note + 7.8MB Inst）。
	 */
	static function prepareChart():Void
	{
		if (chartSpec == null || chartSpec.length == 0)
		{
			LeakProbe.logLine('[harness] -> ChartingState (默认空谱 test)');
			return;
		}

		var parts:Array<String> = chartSpec.split('|');
		var modFolder:String = parts[0];
		var songFolder:String = (parts.length > 1 && parts[1].length > 0) ? parts[1] : parts[0];
		var chartBase:String = (parts.length > 2 && parts[2].length > 0) ? parts[2] : songFolder;

		try
		{
			if (modFolder.length > 0) general.backend.Mods.currentModDirectory = modFolder;
			var s:Dynamic = games.backend.Song.loadFromJson(chartBase, songFolder);
			if (s != null && (s.song == null || (s.song : String).length == 0)) s.song = songFolder;
			LeakProbe.logLine('[harness] -> ChartingState, chart=' + chartBase + ' @ ' + songFolder + ' mod=' + modFolder
				+ (s == null ? ' (LOAD FAILED)' : ' (sections=' + (cast s.notes : Array<Dynamic>).length + ', notes≈' + countNotes(s) + ')'));
		}
		catch (e:Dynamic)
			LeakProbe.logLine('[harness] chart load failed: ' + e);
	}

	/** 数一下谱面里到底有多少 note（用来看"内存涨"是否与音符量成正比）。 */
	static function countNotes(s:Dynamic):Int
	{
		var n:Int = 0;
		try
		{
			var secs:Array<Dynamic> = cast s.notes;
			for (sec in secs)
			{
				if (sec == null || sec.sectionNotes == null) continue;
				n += (cast sec.sectionNotes : Array<Dynamic>).length;
			}
		}
		catch (e:Dynamic) {}
		return n;
	}

	/** Freeplay 里每隔 selectGap 秒按一次 DOWN（只换选中项，不进入歌曲），每次选完打一个 checkpoint。 */	static function selectWatch(n:Int):Void
	{
		if (n >= selections) return;
		new FlxTimer().start(selectGap, function(_)
		{
			if (LeakProbe.stateName() != 'states.freeplayState.FreeplayState') return;
			pressKey(0x28); // DOWN = UI_DOWN_P
			new FlxTimer().start(0.8, function(_)
			{
				LeakProbe.checkPoint('fselect ' + (n + 1) + '/' + selections + ' (只选歌不进歌)');
				selectWatch(n + 1);
			});
		});
	}

	static function makeTarget(n:Int):FlxState
	{
		var t:String = target;
		if (t == 'cycle' || t == null || t.length == 0)
		{
			var all:Array<String> = ['freeplay', 'options', 'mods'];
			t = all[(n - 1) % all.length];
		}
		LeakProbe.logLine('[harness] -> ' + t);
		return switch (t)
		{
			case 'freeplay': new states.freeplayState.FreeplayState();
			case 'options': new options.OptionsState();
			case 'mods': new states.modsMenuState.ModsMenuState();
			case 'achievements': new states.achievementsMenuState.AchievementsMenuState();
			case 'credits': new states.creditsState.CreditsState();
			case 'story': new states.storyMenuState.StoryMenuState();
			default: new states.freeplayState.FreeplayState();
		};
	}

	static function init():Void
	{
		if (inited) return;
		inited = true;

		#if sys
		var n:Int = 0;
		try
		{
			var s:String = Sys.getEnv('NF_LEAK_ROUNDS');
			if (s != null && s.length > 0) n = Std.parseInt(s);
		}
		catch (e:Dynamic) {}

		if (n <= 0) return;

		rounds = n;
		active = true;
		try
		{
			var m:String = Sys.getEnv('NF_LEAK_MODE');
			if (m != null && m.length > 0) mode = m;
		}
		catch (e:Dynamic) {}
		if (mode == null || mode.length == 0) mode = 'restart';
		try
		{
			var d:String = Sys.getEnv('NF_LEAK_DELAY');
			if (d != null && d.length > 0)
			{
				var f:Float = Std.parseFloat(d);
				if (!Math.isNaN(f) && f > 0) delay = f;
			}
		}
		catch (e:Dynamic) {}
		try
		{
			var t:String = Sys.getEnv('NF_LEAK_TARGET');
			if (t != null && t.length > 0) target = t;
		}
		catch (e:Dynamic) {}
		try
		{
			var g:String = Sys.getEnv('NF_LEAK_GAMEPLAY_SEC');
			if (g != null && g.length > 0)
			{
				var f:Float = Std.parseFloat(g);
				if (!Math.isNaN(f) && f > 0) gameplaySeconds = f;
			}
		}
		catch (e:Dynamic) {}
		try
		{
			var s:String = Sys.getEnv('NF_LEAK_SELECTS');
			if (s != null && s.length > 0)
			{
				var n:Int = Std.parseInt(s);
				if (n > 0) selections = n;
			}
		}
		catch (e:Dynamic) {}
		try
		{
			var s2:String = Sys.getEnv('NF_LEAK_STAY_SEC');
			if (s2 != null && s2.length > 0)
			{
				var f2:Float = Std.parseFloat(s2);
				if (!Math.isNaN(f2) && f2 > 0) staySeconds = f2;
			}
		}
		catch (e:Dynamic) {}
		try
		{
			var c:String = Sys.getEnv('NF_LEAK_CHART');
			if (c != null) chartSpec = c;
		}
		catch (e:Dynamic) {}
		try
		{
			// NF_LEAK_SETTLE_SEC=秒：最后一轮结束后静置这么久再收一次（区分短暂持有 / 真泄漏）。
			// 0 = 关掉（回到"跑完立刻收尾"的旧行为）。
			var st:String = Sys.getEnv('NF_LEAK_SETTLE_SEC');
			if (st != null && st.length > 0)
			{
				var f4:Float = Std.parseFloat(st);
				if (!Math.isNaN(f4) && f4 >= 0) settleSeconds = f4;
			}
		}
		catch (e:Dynamic) {}
		try
		{
			playtest = Sys.getEnv('NF_LEAK_PLAYTEST') == '1';
			exitChain = Sys.getEnv('NF_LEAK_EXIT_CHAIN') == '1';
			var ps:String = Sys.getEnv('NF_LEAK_PLAYTEST_SEC');
			if (ps != null && ps.length > 0)
			{
				var f3:Float = Std.parseFloat(ps);
				if (!Math.isNaN(f3) && f3 > 0) playtestSeconds = f3;
			}
		}
		catch (e:Dynamic) {}
		try
		{
			// A/B 实验用：跳过启动视频（用来验证"InitState 每次重启残留"是否来自视频路径）
			if (Sys.getEnv('NF_LEAK_SKIP_VIDEO') == '1')
				general.backend.ClientPrefs.data.skipTitleVideo = true;
		}
		catch (e:Dynamic) {}

		var tag:String = '';
		try tag = Sys.getEnv('NF_LEAK_TAG') catch (e:Dynamic) {}
		try
		{
			var t2:String = Sys.getEnv('NF_LEAK_TRACE_STATES');
			if (t2 == '0') traceStates = false;
		}
		catch (e:Dynamic) {}
		// 首次启动也要过标题界面（等 ENTER）——自动化统一注入按键，别让整轮卡死
		titlePending = true;
		LeakProbe.logLine('=== LeakHarness start rounds=' + rounds + ' mode=' + mode + ' delay=' + delay + ' target=' + target + ' tag=' + tag);
		#end
	}
}
