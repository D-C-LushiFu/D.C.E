package developer.editors;

import haxe.Json;
import haxe.format.JsonParser;
import haxe.io.Bytes;

import lime.media.AudioBuffer;

import openfl.utils.Assets;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.media.Sound;
import openfl.geom.Rectangle;
import openfl.display.BitmapData;
import openfl.net.FileReference;
import openfl.system.System;
import openfl.media.Sound;

import flixel.FlxObject;
import flixel.addons.display.FlxGridOverlay;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxImageFrame;
import flixel.addons.ui.FlxUI;
import flixel.addons.ui.FlxUICheckBox;
import flixel.addons.ui.FlxUIInputText;
import flixel.addons.ui.FlxUIDropDownMenu;
import flixel.addons.ui.FlxUINumericStepper;
import flixel.addons.ui.FlxUISlider;
import flixel.addons.ui.FlxUITabMenu;
import flixel.group.FlxGroup;
import flixel.ui.FlxButton;
import flixel.util.FlxSort;
import flixel.util.FlxStringUtil;

import general.objects.AttachedSprite;
import general.backend.language.Language;

import substates.Prompt;
import mobile.objects.EditorMobileKeys;

import games.backend.Song;
import games.backend.Section;
import games.backend.StageData;
import games.objects.Note;
import games.objects.StrumNote;
import games.objects.NoteSplash;
import games.objects.HealthIcon;
import games.objects.Character;

private typedef ChartHistoryFrame =
{
	var label:String;
	var snapshot:String;
}

@:access(flixel.sound.FlxSound._sound)
@:access(openfl.media.Sound.__buffer)
class ChartingState extends MusicBeatState
{
	public static var noteTypeList:Array<String> = // Used for backwards compatibility with 0.1 - 0.3.2 charts, though, you should add your hardcoded custom note types here too.
		['', 'Alt Animation', 'Hey!', 'Hurt Note', 'GF Sing', 'No Animation'];

	public var ignoreWarnings = false;

	var curNoteTypes:Array<String> = [];
	static inline var MAX_CHART_HISTORY:Int = 100;
	var historyFrames:Array<ChartHistoryFrame> = [];
	var historyIndex:Int = -1;
	var pendingHistorySnapshot:String;
	var pendingHistoryLabel:String = '';
	var pendingHistoryKey:String;
	var lastHistoryKey:String;
	var historyActionDepth:Int = 0;
	var lastHistoryCommitAt:Float = 0;
	var historyPanel:ChartEditorHistoryPanel;
	public var historyHeader:EditorHistoryHeaderControls;

	override public function editorMobileModalOpen():Bool
		return super.editorMobileModalOpen() || (historyPanel != null && historyPanel.visible) || (menuBar != null && menuBar.activeMenu >= 0);
	override public function editorMobilePointerBlocked(x:Float, y:Float):Bool
		return super.editorMobilePointerBlocked(x, y) || (historyHeader != null && historyHeader.containsPoint(x, y));
	var savedChartSnapshot:String;
	var pendingChartSave:String;
	var eventStuff:Array<Dynamic> = [
		['', "Nothing. Yep, that's right."],
		[
			'Dadbattle Spotlight',
			"Used in Dad Battle,\nValue 1: 0/1 = ON/OFF,\n2 = Target Dad\n3 = Target BF"
		],
		[
			'Hey!',
			"Plays the \"Hey!\" animation from Bopeebo,\nValue 1: BF = Only Boyfriend, GF = Only Girlfriend,\nSomething else = Both.\nValue 2: Custom animation duration,\nleave it blank for 0.6s"
		],
		[
			'Set GF Speed',
			"Sets GF head bopping speed,\nValue 1: 1 = Normal speed,\n2 = 1/2 speed, 4 = 1/4 speed etc.\nUsed on Fresh during the beatbox parts.\n\nWarning: Value must be integer!"
		],
		[
			'Philly Glow',
			"Exclusive to Week 3\nValue 1: 0/1/2 = OFF/ON/Reset Gradient\n \nNo, i won't add it to other weeks."
		],
		['Kill Henchmen', "For Mom's songs, don't use this please, i love them :("],
		[
			'Add Camera Zoom',
			"Used on MILF on that one \"hard\" part\nValue 1: Camera zoom add (Default: 0.015)\nValue 2: UI zoom add (Default: 0.03)\nLeave the values blank if you want to use Default."
		],
		['BG Freaks Expression', "Should be used only in \"school\" Stage!"],
		['Trigger BG Ghouls', "Should be used only in \"schoolEvil\" Stage!"],
		[
			'Play Animation',
			"Plays an animation on a Character,\nonce the animation is completed,\nthe animation changes to Idle\n\nValue 1: Animation to play.\nValue 2: Character (Dad, BF, GF)"
		],
		[
			'Camera Follow Pos',
			"Value 1: X\nValue 2: Y\n\nThe camera won't change the follow point\nafter using this, for getting it back\nto normal, leave both values blank."
		],
		[
			'Alt Idle Animation',
			"Sets a specified suffix after the idle animation name.\nYou can use this to trigger 'idle-alt' if you set\nValue 2 to -alt\n\nValue 1: Character to set (Dad, BF or GF)\nValue 2: New suffix (Leave it blank to disable)"
		],
		[
			'Screen Shake',
			"Value 1: Camera shake\nValue 2: HUD shake\n\nEvery value works as the following example: \"1, 0.05\".\nThe first number (1) is the duration.\nThe second number (0.05) is the intensity."
		],
		[
			'Change Character',
			"Value 1: Character to change (Dad, BF, GF)\nValue 2: New character's name"
		],
		[
			'Change Scroll Speed',
			"Value 1: Scroll Speed Multiplier (1 is default)\nValue 2: Time it takes to change fully in seconds."
		],
		['Set Property', "Value 1: Variable name\nValue 2: New value"],
		[
			'Play Sound',
			"Value 1: Sound file name\nValue 2: Volume (Default: 1), ranges from 0 to 1"
		],
		[
			'Key change(more key)',
			"Changes the visible key count during gameplay.\nValue 1: Number of keys to display (e.g., 10 for 10K)\nValue 2: Transition time in seconds (Default: 1s)"
		]
	];

	var _file:FileReference;

	var UI_box:FlxUITabMenu;

	public static var isFreePlay:Bool = false;
	public static var goToPlayState:Bool = false;

	/**
	 * Array of notes showing when each section STARTS in STEPS
	 * Usually rounded up??
	 */
	public static var curSec:Int = 0;

	/** ★ 把 static curSec 钳到当前谱面范围内（返回是否发生修正）。
	 *  curSec 是 static，跨实例残留：上一张谱编到第 25 小节退出后，再加载一张更短的非 Normal
	 *  难度谱，curSec 仍为 25 → 所有 `_song.notes[curSec].changeBPM` 式裸访问越界取到 null
	 *  → cpp 目标原生崩溃（crash dump 中的 "notes"+"changeBPM" 字符串即此）。 */
	function clampCurSec():Void
	{
		var n:Int = _song == null || _song.notes == null ? 0 : _song.notes.length;
		if (curSec >= n)
			curSec = n - 1;
		if (curSec < 0)
			curSec = 0;
	}

	/** ★ 安全取当前小节（curSec 越界时自动钳制） */
	function curSectionSafe():Dynamic
	{
		if (_song == null || _song.notes == null || _song.notes.length <= 0)
			return null;
		if (curSec < 0 || curSec >= _song.notes.length)
		{
			curSec = 0;
		}
		return _song.notes[curSec];
	}

	public static var lastSection:Int = 0;
	private static var lastSong:String = '';

	var bpmTxt:FlxText;

	// 提升为类变量的 UI 控件（用于注册到菜单系统）
	var songBpmStepper:FlxUINumericStepper;
	var stepperSpeed:FlxUINumericStepper;
	var stepperMania:FlxUINumericStepper;
	var player1DropDown:FlxUIDropDownMenu;
	var gfVersionDropDown:FlxUIDropDownMenu;
	var player2DropDown:FlxUIDropDownMenu;
	var selectedEventIdx:Int = -1;

	var camPos:FlxObject;
	var strumLine:FlxSprite;
	var quant:AttachedSprite;
	var strumLineNotes:FlxTypedGroup<StrumNote>;
	var curSong:String = 'Test';
	var amountSteps:Int = 0;
	var bullshitUI:FlxGroup;

	var highlight:FlxSprite;

	// ★ 十二轮：格距随编辑器设计分辨率缩放（720 设计时 = 40）
	public static var GRID_SIZE(get, never):Int;

	static function get_GRID_SIZE():Int return EditorInputStyle.si(40);

	var CAM_OFFSET:Int = 360;

	var eventIcon:FlxSprite;
	var dummyArrow:FlxSprite;

	var curRenderedSustains:FlxTypedGroup<FlxSprite>;
	var curRenderedNotes:FlxTypedGroup<Note>;
	var curRenderedNoteType:FlxTypedGroup<FlxText>;

	var nextRenderedSustains:FlxTypedGroup<FlxSprite>;
	var nextRenderedNotes:FlxTypedGroup<Note>;

	var gridBG:FlxSprite;
	var nextGridBG:FlxSprite;

	var daquantspot = 0;
	var curEventSelected:Int = 0;
	var curUndoIndex = 0;
	var curRedoIndex = 0;
	// 事件类型下拉：当前 hover 的选项索引（-1 = 未 hover），菜单里显示事件信息用
	var hoveringEventIdx:Int = -1;
	var _song:SwagSong;
	/*
	 * WILL BE THE CURRENT / LAST PLACED NOTE
	**/
	var curSelectedNote:Array<Dynamic> = null;

	var playbackSpeed:Float = 1;

	var vocals:FlxSound = null;
	var opponentVocals:FlxSound = null;

	var leftIcon:HealthIcon;
	var rightIcon:HealthIcon;
	/** ★ 摄像机图标（assets/shared/images/editors/camera.png）：标示摄像机跟随播放头，置于各 Icon 左侧 */
	var camIcon:FlxSprite;

	var value1InputText:FlxUIInputText;
	var value2InputText:FlxUIInputText;
	var currentSongName:String;

	var zoomTxt:FlxText;

	// Adobe 风格顶栏菜单（替代 zoomTxt 的零散显示）
	var menuBar:ChartEditorMenuBar;
	#if (cpp && windows)
	var windowChrome:EditorChromeUI;
	var modInfoPopup:general.objects.ModInfoPopup;
	var camHUD:flixel.FlxCamera;
	#end

	var zoomList:Array<Float> = [0.25, 0.5, 1, 2, 3, 4, 6, 8, 12, 16, 24];
	var curZoom:Int = 2;

	private var blockPressWhileTypingOn:Array<FlxUIInputText> = [];
	private var blockPressWhileTypingOnStepper:Array<FlxUINumericStepper> = [];
	private var blockPressWhileScrolling:Array<FlxUIDropDownMenu> = [];

	var waveformSprite:FlxSprite;
	var gridLayer:FlxTypedGroup<FlxSprite>;

	public static var quantization:Int = 16;
	public static var curQuant = 3;

	public var quantizations:Array<Int> = [4, 8, 12, 16, 20, 24, 32, 48, 64, 96, 192];

	var text:String = "";

	public static var vortex:Bool = false;

	var leftKeys:Int = 4;
	var rightKeys:Int = 4;
	var totalKeys:Int = 8;
	var gridOffsetX:Float = 0;

	public var mouseQuant:Bool = false;

	override function create()
	{
		// ★★ 09-26 十二轮：先把渲染设计分辨率切到设备分辨率（1080p → 1920×1080，1:1 无放大）
		//   必须在任何 UI / 相机 / 文字创建之前调用 —— 否则文字仍是 1280 光栅化后被拉大（发虚）。
		EditorInputStyle.enterHiRes();

		// 强制刷新语言数据，确保 charting 等新分组被正确加载
		general.backend.language.Language.resetData();

		if (PlayState.SONG != null)
		{
			_song = PlayState.SONG;
		}
		else
		{
			Difficulty.resetList();
			_song = {
				song: 'Test',
				notes: [],
				events: [],
				bpm: 150.0,
				needsVoices: true,
				player1: 'bf',
				player2: 'dad',
				gfVersion: 'gf',
				speed: 1,
				stage: 'stage',
				mania: 3,
				format: 'na'
			};
			addSection();
			PlayState.SONG = _song;
		}

		// Editor entry can reuse PlayState.SONG without parsing JSON again. Keep the
		// engine state in sync with that chart's own format, as reload JSON does.
		if (_song.format == 'psych_v1_convert' || _song.format == 'Pe-0.7.3')
			Song.applyFormatState('Pe-0.7.3');
		else if (_song.format == 'Pe-1.0.x' || (_song.format != null && StringTools.startsWith(_song.format, 'psych_v1')))
			Song.applyFormatState('Pe-1.0.x');

		// ★ 进入编辑器时数据与 mania 视为配套：先按数据自检 mania（防 json 缺 mania 字段默认 4K），
		//   再只重算键数——绝不平移数据（平移只用于用户主动改 mania，见 updateKeyAmounts）
		// ★ 必须在一切访问 _song.notes[curSec] 之前钳制 static curSec（跨实例残留 → 非 Normal
		//   难度短谱越界 → 原生崩溃，见 clampCurSec 注释）
		clampCurSec();
		autoFixManiaFromData();
		recalcKeyAmounts();

		// ★ 已移除：此处原有个 loops=0 的"无限" FlxTimer，闭包写实例字段 timeCheck 从而捕获 this，
		//   又没存引用、destroy 也不取消 → 整个 ChartingState 被钉死在 FlxTimer.globalManager 里，
		//   每开一次编谱器泄漏 ~17MB GC 堆 / ~57MB 进程。且 timeCheck 全程无人读取，纯死代码，删掉无副作用。

		// Paths.clearMemory();

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence
		DiscordClient.changePresence("Chart Editor", StringTools.replace(_song.song, '-', ' '));
		#end

		vortex = FlxG.save.data.chart_vortex;
		ignoreWarnings = FlxG.save.data.ignoreWarnings;
		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set();
		bg.color = 0xFF12141A; // ★ D.C.E. 规范：页面底层背景
		// ★ 十二轮：设计分辨率可能大于资源尺寸（1286×730）→ 拉伸铺满整屏（否则四周露黑边）
		bg.setGraphicSize(Std.int(FlxG.width), Std.int(FlxG.height));
		bg.updateHitbox();
		bg.origin.set(0, 0);
		bg.offset.set(0, 0);
		add(bg);

		gridLayer = new FlxTypedGroup<FlxSprite>();
		add(gridLayer);

		waveformSprite = new FlxSprite(GRID_SIZE, 0).makeGraphic(1, 1, 0x00FFFFFF, true);
		add(waveformSprite);

		eventIcon = new FlxSprite(-GRID_SIZE - 5, -90).loadGraphic(Paths.image('eventArrow'));
		eventIcon.antialiasing = ClientPrefs.data.antialiasing;
		leftIcon = new HealthIcon('bf');
		rightIcon = new HealthIcon('dad');
		eventIcon.scrollFactor.set(1, 1);
		leftIcon.scrollFactor.set(1, 1);
		rightIcon.scrollFactor.set(1, 1);

		eventIcon.setGraphicSize(EditorInputStyle.si(30), EditorInputStyle.si(30));
		leftIcon.setGraphicSize(0, EditorInputStyle.si(45));
		rightIcon.setGraphicSize(0, EditorInputStyle.si(45));
		// ★★ setGraphicSize 改的是 scale；必须再 updateHitbox 拿到正确 width/height，
		//   然后把 origin/offset 归零 —— 否则渲染顶点会被 -(origin*scale) 拉偏
		//   （icon 帧 150px、scale 0.3 时偏移可达 50px 以上，头像就会"位置不对"）
		for (_ic in [eventIcon, leftIcon, rightIcon])
		{
			if (_ic == null) continue;
			_ic.updateHitbox();
			_ic.origin.set(0, 0);
			_ic.offset.set(0, 0);
		}

		// ★ eventIcon 是旧版留下的装饰（贴图也是 eventArrow），不跟随任何位置 → 会与真正的事件箭头重叠，隐藏掉
		eventIcon.visible = false;
		add(eventIcon);
		add(leftIcon);
		add(rightIcon);

		// ★ 摄像机图标（camera.png）：播放跨小节不再切谱面、只切摄像机，
		//   用它标示摄像机位置 —— 位于各 Icon 左侧，并跟随播放白条（strumLine）上下移动。
		try
		{
			var camTex = Paths.image('editors/camera');
			if (camTex != null)
			{
				camIcon = new FlxSprite().loadGraphic(camTex);
				camIcon.scrollFactor.set(1, 1);
				camIcon.setGraphicSize(Std.int(GRID_SIZE * 0.8), 0);
				camIcon.updateHitbox();
				camIcon.origin.set(0, 0);
				camIcon.offset.set(0, 0);
				camIcon.antialiasing = ClientPrefs.data.antialiasing;
				add(camIcon);
			}
		}
		catch (e:Dynamic)
		{
			camIcon = null;
		}

		// ★ 头像初始位置统一由 positionSideIcons 负责（makeStrumNotes / reloadGridLayer / updateHeads 都会调用）
		positionSideIcons();

		curRenderedSustains = new FlxTypedGroup<FlxSprite>();
		curRenderedNotes = new FlxTypedGroup<Note>();
		curRenderedNoteType = new FlxTypedGroup<FlxText>();

		nextRenderedSustains = new FlxTypedGroup<FlxSprite>();
		nextRenderedNotes = new FlxTypedGroup<Note>();

		FlxG.mouse.visible = true;
		// FlxG.save.bind('funkin', CoolUtil.getSavePath());

		// addSection();

		// sections = _song.notes;

		updateJsonData();
		currentSongName = Paths.formatToSongPath(_song.song);
		loadSong();
		// ★ 先预热 Note 贴图/动画缓存：reloadGridLayer 内部的 updateGrid 会创建 Note，
		//   若此时 loadedNote 还是空的，reloadPath('') 会算出空 skin 并缓存空贴图 →
		//   启动后第一次打开编谱器时所有音符显示第一帧（全左箭头）。
		//   （原顺序：makeStrumNotes 里的 StrumNote 才会触发 Note.init，但它在 reloadGridLayer 之后）
		Note.init();
		reloadGridLayer();
		Conductor.bpm = _song.bpm;
		Conductor.mapBPMChanges(_song);
		if (curSec >= _song.notes.length)
			curSec = _song.notes.length - 1;

		// 原生谱面信息文本（时间/Section/Beat/Step/Beat Snap/Move）已由顶栏状态栏替代，直接隐藏
		bpmTxt = new EditorText(10, 75, 0, "", 16);
		bpmTxt.scrollFactor.set();
		bpmTxt.visible = false;
		add(bpmTxt);

		strumLine = new FlxSprite(0, 50).makeGraphic(Std.int(GRID_SIZE * (totalKeys + 1)), 4);
		add(strumLine);

		quant = new AttachedSprite('chart_quant', 'chart_quant');
		quant.animation.addByPrefix('q', 'chart_quant', 0, false);
		quant.animation.play('q', true, false, 0);
		quant.sprTracker = strumLine;
		quant.xAdd = EditorInputStyle.sv(-32);
		quant.yAdd = EditorInputStyle.sv(8);
		add(quant);

		strumLineNotes = new FlxTypedGroup<StrumNote>();
		makeStrumNotes();
		add(strumLineNotes);

		camPos = new FlxObject(0, 0, 1, 1);
		camPos.setPosition(strumLine.x + CAM_OFFSET, strumLine.y);

		dummyArrow = new FlxSprite().makeGraphic(GRID_SIZE, GRID_SIZE);
		dummyArrow.antialiasing = ClientPrefs.data.antialiasing;
		add(dummyArrow);

		// ★ Note 密度缩略图（minimap）：全曲 note 分布 + 可拖动视口块
		setupMinimap();
		resetMinimapForNewSong(); // ★ 每次进入编辑器都强制重新初始化一次

		var tabs = [
			{name: "Song", label: 'Song'},
			{name: "Section", label: 'Section'},
			{name: "Note", label: 'Note'},
			{name: "Events", label: 'Events'},
			{name: "Charting", label: 'Charting'},
			{name: "Data", label: 'Data'},
		];

		// ★ UI_box 仅存为逻辑引用（tab 管理），不加入场景，不渲染
		// widget 全部独立存在，不依赖 FlxGroup 容器
		UI_box = new FlxUITabMenu(null, tabs, true);
		UI_box.resize(300, 400);

		if (controls.mobileC)
		{
			text = "Up/Down - Change Conductor's strum time
		\nLeft/Right - Go to the previous/next section
		\nHold Y to move 4x faster
		\nZ/D - Zoom in/out
		\n
		\nC - Test your chart inside Chart Editor
		\nA - Play your chart
		\nUp/Down (right) - Decrease/Increase Note Sustain Length
		\nX - Stop/Resume song";
		}
		else
		{
			text = "W/S or Mouse Wheel - Change Conductor's strum time
		\nA/D - Go to the previous/next section
		\nLeft/Right - Change Snap
		\nUp/Down - Change Conductor's Strum Time with Snapping"
				+ #if FLX_PITCH "\nLeft Bracket / Right Bracket - Change Song Playback Rate (SHIFT to go Faster)
		\nALT + Left Bracket / Right Bracket - Reset Song Playback Rate"
				+ #end "\nHold Shift to move 4x faster
		\nZ/X - Zoom in/out
		\n
		\nEsc - Test your chart inside Chart Editor
		\nEnter - Play your chart
		\nQ/E - Decrease/Increase Note Sustain Length
		\nSpace - Stop/Resume song";
		}

		// 操作提示已移到【帮助】菜单，不再在屏幕上显示 tipText

		addSongUI();
		addSectionUI();
		addNoteUI();
		addEventsUI();
		addChartingUI();
		addDataUI();
		// ★★ 09-26 九轮：`curNoteTypes` 是在 addNoteUI() 里才填充的，而 create 前段的
		//   reloadGridLayer() 已经把窗口内音符建好了 —— 那批角标全是 '?'
		//   （用户反馈：特殊 note 不显示数字，调 mania 才出来）。这里重建一次。
		updateGrid();
		updateHeads();
		updateWaveform();

		// ===== 旧 FlxUITabMenu 不再加入场景，无需显式隐藏 =====

		add(curRenderedSustains);
		add(curRenderedNotes);
		add(curRenderedNoteType);
		add(nextRenderedSustains);
		add(nextRenderedNotes);

		if (lastSong != currentSongName)
		{
			changeSection();
		}
		lastSong = currentSongName;

		// 原版 zoomTxt（屏幕左上角单独一行）已废弃；改为整条顶栏 + 状态栏
		// zoomTxt 字段仍保留，updateZoom() 内会更新 menuBar.statusBar 的 zoom 显示
		zoomTxt = new EditorText(10, 10, 0, "Zoom: 1 / 1", 16);
		zoomTxt.scrollFactor.set();
		zoomTxt.visible = false;
		add(zoomTxt);

		// ===== 顶栏菜单栏（Adobe 风格）=====
		menuBar = new ChartEditorMenuBar();
		menuBar.scrollFactor.set();
		menuBar.uiCamera = FlxG.camera;
		menuBar.onSelectTab = function(idx:Int) {
			UI_box.selected_tab = idx;
		};
		menuBar.onPlaytest = function(testMode:Bool) {
			if (testMode) startPlaytest();
			else startNormalPlay();
		};
		menuBar.onAction = function(actionKey:String) {
			handleMenuAction(actionKey);
		};
		// ★ 事件下拉 hover：悬停在选项上时在菜单里显示该事件的名字+描述
		menuBar.onDropdownHoverOption = function(ctrl:Dynamic, optIdx:Int) {
			if (ctrl == null || ctrl.key != 'w_event_type') return;
			hoveringEventIdx = optIdx;
			menuBar.refreshDynTexts();
		};
		// ★ 事件信息动态文本行（菜单里事件类型下拉下方）
		menuBar.registerDynText('dyn_event_info', function():String {
			var idx:Int = hoveringEventIdx;
			if (idx < 0)
			{
				idx = 0;
				var parsed:Null<Int> = null;
				try { parsed = Std.parseInt(eventDropDown.selectedId); } catch (e:Dynamic) {}
				if (parsed != null) idx = parsed;
			}
			if (idx < 0 || idx >= eventStuff.length) return '';
			var name:String = eventStuff[idx][0];
			var desc:String = eventStuff[idx][1];
			if (desc == null) desc = '';
			// ★ 描述完整返回（右侧信息面板高度弹性自适应，不截断成 …）
			return (name != null && name != '') ? (name + '\n' + desc) : desc;
		});
		// ★ 菜单打开后刷新 widget 显示值
		//   widget 在 visible=false 时被赋值后显示不会刷新，需要在菜单打开时强制同步
		menuBar.onMenuOpened = function(menuKey:String) {
			refreshMenuWidgets(menuKey);
		};
		// 不再需要 onRequestUIBox —— menuBar 自己管理 widget 面板的显示/隐藏

		// 注册 widget 引用（仅用于下拉菜单显示状态文本）
		menuBar.registerWidget('w_metronome', metronome);
		menuBar.registerWidget('w_autoscroll', disableAutoScrolling);
		menuBar.registerWidget('w_waveform_inst', waveformUseInstrumental);
		menuBar.registerWidget('w_waveform_main', waveformUseVoices);
		menuBar.registerWidget('w_waveform_opp', waveformUseOppVoices);
		menuBar.registerWidget('w_mute_inst', check_mute_inst);
		menuBar.registerWidget('w_mute_main', check_mute_vocals);
		menuBar.registerWidget('w_mute_opp', check_mute_vocals_opponent);
		menuBar.registerWidget('w_vortex', check_vortex);
		menuBar.registerWidget('w_ignore_warnings', check_warnings);
		menuBar.registerWidget('w_sfx_bf', playSoundBf);
		menuBar.registerWidget('w_sfx_opp', playSoundDad);
		menuBar.registerWidget('w_no_rgb', check_disableNoteRGB);
		menuBar.registerWidget('w_must_hit', check_mustHitSection);
		menuBar.registerWidget('w_gf_section', check_gfSection);
		menuBar.registerWidget('w_alt_anim', check_altAnim);
		menuBar.registerWidget('w_change_bpm', check_changeBPM);
		menuBar.registerWidget('w_include_notes', check_notesSec);
		menuBar.registerWidget('w_include_events', check_eventsSec);
		menuBar.registerWidget('w_has_voice', check_voices);

		menuBar.registerWidget('w_bpm_stepper', metronomeStepper);
		menuBar.registerWidget('w_metronome_offset', metronomeOffsetStepper);
		menuBar.registerWidget('w_inst_volume', instVolume);
		menuBar.registerWidget('w_voices_volume', voicesVolume);
		menuBar.registerWidget('w_voices_opp_volume', voicesOppVolume);
		menuBar.registerWidget('w_beats_per_section', stepperBeats);
		menuBar.registerWidget('w_section_bpm', stepperSectionBPM);
		menuBar.registerWidget('w_copy_beat', copyBeatStepper);
		menuBar.registerWidget('w_sus_length', stepperSusLength);
		menuBar.registerWidget('w_strum_time', strumTimeInputText);
		menuBar.registerWidget('w_note_type', noteTypeDropDown);
		menuBar.registerWidget('w_event_type', eventDropDown);
		menuBar.registerWidget('w_value1', value1InputText);
		menuBar.registerWidget('w_value2', value2InputText);
		menuBar.registerWidget('w_song_title', UI_songTitle);
		menuBar.registerWidget('w_bpm', songBpmStepper);
		menuBar.registerWidget('w_speed', stepperSpeed);
		menuBar.registerWidget('w_mania', stepperMania);
		menuBar.registerWidget('w_stage', stageDropDown);
		menuBar.registerWidget('w_player1', player1DropDown);
		menuBar.registerWidget('w_gf', gfVersionDropDown);
		menuBar.registerWidget('w_player2', player2DropDown);
		menuBar.registerWidget('w_go_char', gameOverCharacterInputText);
		menuBar.registerWidget('w_go_sound', gameOverSoundInputText);
		menuBar.registerWidget('w_go_loop', gameOverLoopInputText);
		menuBar.registerWidget('w_go_end', gameOverEndInputText);
		menuBar.registerWidget('w_note_skin', noteSkinInputText);
		menuBar.registerWidget('w_note_splash', noteSplashesInputText);
		menuBar.registerWidget('w_difficulty', difficultyInputText);
		engineDropDown = new FlxUIDropDownMenu(0, 0, FlxUIDropDownMenu.makeStrIdLabelArray(['Pe-0.7.3', 'Pe-1.0.4'], true), function(value:String)
		{
			applyChartEngine(Std.parseInt(value) == 1 ? 'Pe-1.0.4' : 'Pe-0.7.3');
		});
		engineDropDown.selectedLabel = Song.chartEngineVersion;
		engineDropDown.visible = engineDropDown.active = false;
		menuBar.registerWidget('w_engine', engineDropDown);

		add(menuBar);

		// ===== 控件加入场景 =====
		addLegacyWidgetsToScene();
		// ===== 自绘菜单系统接管 UI：旧 6 列布局的原生控件全部隐藏（只作数据源）=====
		hideAllLegacyWidgets();

		updateGrid();

		addVirtualPad(ChartingStateC, ChartingStateC);

		super.create();

		#if (cpp && windows)
		// Charting 主相机跟随网格滚动，自绘窗口条必须挂独立的固定 HUD 相机。
		// 注意：必须在 super.create() 之后创建 —— MusicBeatState.create 里的
		// initPsychCamera() 会 FlxG.cameras.reset，提前创建会被清掉。
		camHUD = new flixel.FlxCamera();
		camHUD.bgColor.alpha = 0;
		flixel.FlxG.cameras.add(camHUD, false);

		// 引擎自绘窗口控制组（右上角：图标+标题 / - □ ×，可拖动窗口）
		windowChrome = new EditorChromeUI();
		windowChrome.scrollFactor.set();
		windowChrome.cameras = [camHUD];
		add(windowChrome);
		// 点击标题 → Mod 信息下拉面板
		modInfoPopup = new general.objects.ModInfoPopup();
		modInfoPopup.scrollFactor.set();
		modInfoPopup.cameras = [camHUD];
		add(modInfoPopup);
		windowChrome.onTitleClick = () -> modInfoPopup.openUnder(windowChrome);
		// 顶栏左侧「退出 编谱器」按钮
		windowChrome.setupExitButton('chartEditor', doExitEditor);
		#end

		historyPanel = new ChartEditorHistoryPanel();
		historyPanel.x = FlxG.width - EditorInputStyle.si(320) - EditorInputStyle.si(12);
		historyPanel.y = ChartEditorMenuBar.BAR_HEIGHT + EditorInputStyle.si(8);
		historyPanel.setCallbacks(jumpToHistory, undo, redo, function() historyPanel.visible = false);
		add(historyPanel);
		historyHeader = new EditorHistoryHeaderControls([undo, redo, function() {
			refreshHistoryPanel();
			historyPanel.visible = !historyPanel.visible;
		}], [() -> historyIndex > 0, () -> historyIndex < historyFrames.length - 1, () -> true]);
		add(historyHeader);
		resetChartHistory();
	}

	/** 6 列从左到右，每列控件纯纵向排列。不用容器，直接裸坐标。 */
	function layoutAllWidgetsVertical():Void
	{
		var colCount:Int = 6;
		var colW:Float = FlxG.width / colCount;
		var startY:Float = ChartEditorMenuBar.BAR_HEIGHT + ChartEditorMenuBar.STATUS_HEIGHT + EditorInputStyle.sv(8);
		var gapY:Float = 26;
		var cursors:Array<Float> = [startY, startY, startY, startY, startY, startY];

		function placeIn(col:Int, w:Dynamic):Void {
			if (w == null) return;
			try {
				try { w.scrollFactor.set(0, 0); } catch(e:Dynamic) {}
				try { w.setScrollFactor(0, 0); } catch(e:Dynamic) {}
				w.x = col * colW + 8;
				w.y = cursors[col];
				w.visible = true;
				cursors[col] += Math.max(w.height + 4, gapY);
			} catch(e:Dynamic) {}
		}

		// col 0 (最左): 歌曲
		placeIn(0, UI_songTitle);
		placeIn(0, check_voices);
		placeIn(0, songBpmStepper);
		placeIn(0, stepperSpeed);
		placeIn(0, stepperMania);
		placeIn(0, stageDropDown);
		placeIn(0, player1DropDown);
		placeIn(0, gfVersionDropDown);
		placeIn(0, player2DropDown);

		// col 1: 小节
		placeIn(1, check_mustHitSection);
		placeIn(1, check_gfSection);
		placeIn(1, check_altAnim);
		placeIn(1, stepperBeats);
		placeIn(1, check_changeBPM);
		placeIn(1, stepperSectionBPM);
		placeIn(1, check_notesSec);
		placeIn(1, check_eventsSec);

		// col 2: 音符
		placeIn(2, stepperSusLength);
		placeIn(2, strumTimeInputText);
		placeIn(2, noteTypeDropDown);

		// col 3: 事件
		placeIn(3, eventDropDown);
		placeIn(3, value1InputText);
		placeIn(3, value2InputText);

		// col 4: 谱面
		placeIn(4, metronome);
		placeIn(4, disableAutoScrolling);
		placeIn(4, metronomeStepper);
		placeIn(4, metronomeOffsetStepper);
		placeIn(4, waveformUseInstrumental);
		placeIn(4, waveformUseVoices);
		placeIn(4, waveformUseOppVoices);
		placeIn(4, check_mute_inst);
		placeIn(4, check_mute_vocals);
		placeIn(4, check_mute_vocals_opponent);
		placeIn(4, check_vortex);
		placeIn(4, check_warnings);
		placeIn(4, playSoundBf);
		placeIn(4, playSoundDad);
		placeIn(4, instVolume);
		placeIn(4, voicesVolume);
		placeIn(4, voicesOppVolume);

		// col 5 (最右): 数据
		placeIn(5, gameOverCharacterInputText);
		placeIn(5, gameOverSoundInputText);
		placeIn(5, gameOverLoopInputText);
		placeIn(5, gameOverEndInputText);
		placeIn(5, check_disableNoteRGB);
		placeIn(5, noteSkinInputText);
		placeIn(5, noteSplashesInputText);
	}
	function hideAllLegacyWidgets():Void
	{
		// ---- CheckBox ----
		var checks:Array<Dynamic> = [
			check_mute_inst, check_mute_vocals, check_mute_vocals_opponent,
			check_vortex, check_warnings, playSoundBf, playSoundDad,
			check_voices, check_eventsSec, check_notesSec, check_disableNoteRGB,
			waveformUseInstrumental, waveformUseVoices, waveformUseOppVoices,
			check_mustHitSection, check_gfSection, check_altAnim, check_changeBPM,
			metronome, disableAutoScrolling, mouseScrollingQuant
		];
		for (c in checks) if (c != null) EditorInputStyle.deepHide(c);

		// ---- InputText ----
		var inputs:Array<Dynamic> = [
			UI_songTitle, difficultyInputText, value1InputText, value2InputText, strumTimeInputText,
			gameOverCharacterInputText, gameOverSoundInputText, gameOverLoopInputText, gameOverEndInputText,
			noteSkinInputText, noteSplashesInputText
		];
		for (i in inputs) if (i != null) EditorInputStyle.deepHide(i);

		// ---- NumericStepper ----
		var steppers:Array<Dynamic> = [
			songBpmStepper, stepperSpeed, stepperMania,
			metronomeStepper, metronomeOffsetStepper,
			instVolume, voicesVolume, voicesOppVolume,
			stepperBeats, stepperSectionBPM, stepperSusLength
		];
		for (s in steppers) if (s != null) EditorInputStyle.deepHide(s);

		// ---- DropDown ----
		var drops:Array<Dynamic> = [
			player1DropDown, gfVersionDropDown, player2DropDown,
			stageDropDown, noteTypeDropDown, eventDropDown
		];
		for (d in drops) if (d != null) EditorInputStyle.deepHide(d);

		// ---- 零散 FlxText（事件描述等） ----
		if (descText != null) { descText.visible = false; descText.active = false; }
		if (selectedEventText != null) { selectedEventText.visible = false; selectedEventText.active = false; }
		// sliderRate（如果有）
		#if FLX_PITCH
		if (sliderRate != null) try { sliderRate.visible = false; sliderRate.active = false; } catch(e) {}
		#end
	}

	/**
	 * 与 BACKSPACE / B 键等价的退出动作（顶栏「退出 编谱器」按钮共用）：
	 *   - 自动 autosave 一份
	 *   - 还原 PlayState.chartingMode / isFreePlay 状态
	 *   - 回到 MasterEditorMenu 或 FreeplayState（取决于 isFreePlay）
	 *   - 播放 freakyMenu BGM
	 */
	function doExitEditor():Void
	{
		if (savedChartSnapshot != null && chartHistorySnapshot() != savedChartSnapshot)
		{
			openSubState(new Prompt(Language.get('history_discard', 'editors'), 0, exitChartAfterConfirmation, null, false));
			return;
		}
		exitChartAfterConfirmation();
	}

	function exitChartAfterConfirmation():Void
	{
		autosaveSong();
		PlayState.chartingMode = false;
		if (!isFreePlay)
			MusicBeatState.switchState(new developer.editors.MasterEditorMenu());
		else
			MusicBeatState.switchState(new states.freeplayState.FreeplayState());
		isFreePlay = false;
		FlxG.sound.playMusic(Paths.music('freakyMenu'));
		FlxG.mouse.visible = false;
	}

	/**
	 * 把所有原生 widget add 到场景，保证它们进入 FlxG.update() 循环。
	 * 之前只 new 不 add → widget 的 update() 从没被调 → 点了没反应，纯贴图。
	 * 用 try/catch 防御性处理重复 add 的情况。
	 */
	function addLegacyWidgetsToScene():Void
	{
		function addOne(w:Dynamic):Void {
			if (w == null) return;
			try { add(w); } catch (e:Dynamic) {}
			// ★ 创建时就设 scrollFactor=0，之后 positionWidget 只需设坐标
			try { w.scrollFactor.set(0, 0); } catch (e:Dynamic) {}
			try { w.setScrollFactor(0, 0); } catch (e:Dynamic) {}
		}
		// CheckBox
		addOne(check_mute_inst); addOne(check_mute_vocals); addOne(check_mute_vocals_opponent);
		addOne(check_vortex); addOne(check_warnings); addOne(playSoundBf); addOne(playSoundDad);
		addOne(check_voices); addOne(check_eventsSec); addOne(check_notesSec); addOne(check_disableNoteRGB);
		addOne(waveformUseInstrumental); addOne(waveformUseVoices); addOne(waveformUseOppVoices);
		addOne(check_mustHitSection); addOne(check_gfSection); addOne(check_altAnim); addOne(check_changeBPM);
		addOne(metronome); addOne(disableAutoScrolling); addOne(mouseScrollingQuant);
		// InputText
		addOne(UI_songTitle); addOne(difficultyInputText); addOne(value1InputText); addOne(value2InputText); addOne(strumTimeInputText);
		addOne(gameOverCharacterInputText); addOne(gameOverSoundInputText);
		addOne(gameOverLoopInputText); addOne(gameOverEndInputText);
		addOne(noteSkinInputText); addOne(noteSplashesInputText);
		// NumericStepper
		addOne(songBpmStepper); addOne(stepperSpeed); addOne(stepperMania);
		addOne(metronomeStepper); addOne(metronomeOffsetStepper);
		addOne(instVolume); addOne(voicesVolume); addOne(voicesOppVolume);
		addOne(stepperBeats); addOne(stepperSectionBPM); addOne(stepperSusLength);
		// DropDown
		addOne(player1DropDown); addOne(gfVersionDropDown); addOne(player2DropDown);
		addOne(stageDropDown); addOne(noteTypeDropDown); addOne(eventDropDown);
		// sliderRate
		#if FLX_PITCH
		addOne(sliderRate);
		#end
	}

	var check_mute_inst:FlxUICheckBox = null;
	var check_mute_vocals:FlxUICheckBox = null;
	var check_mute_vocals_opponent:FlxUICheckBox = null;
	var check_vortex:FlxUICheckBox = null;
	var check_warnings:FlxUICheckBox = null;
	var playSoundBf:FlxUICheckBox = null;
	var playSoundDad:FlxUICheckBox = null;
	// 以下 4 个原本是 add*UI 内的局部变量，为接通新顶栏菜单的 check 项提升为成员
	var check_voices:FlxUICheckBox = null;
	var check_eventsSec:FlxUICheckBox = null;
	var check_notesSec:FlxUICheckBox = null;
	var check_disableNoteRGB:FlxUICheckBox = null;
	// 波形图 3 个 checkbox，原是 addChartingUI 内的局部变量
	var waveformUseInstrumental:FlxUICheckBox = null;
	var waveformUseVoices:FlxUICheckBox = null;
	var waveformUseOppVoices:FlxUICheckBox = null;
	var UI_songTitle:FlxUIInputText;
	/** ★ 难度输入框（【歌曲】菜单）：留空 = 无难度后缀；填了如 Fuck →
	 *  保存为 song-Fuck.json，重载/打开也按 song-Fuck 加载 */
	var difficultyInputText:FlxUIInputText;
	var engineDropDown:FlxUIDropDownMenu;
	var stageDropDown:FlxUIDropDownMenu;
	#if FLX_PITCH
	var sliderRate:FlxUISlider;
	#end

	function addSongUI():Void
	{
		UI_songTitle = new FlxUIInputText(10, 10, 70, _song.song, 8);
		// ★ 加入 blockPressWhileTypingOn，防止输入框内按 Backspace 触发全局退出快捷键
		blockPressWhileTypingOn.push(UI_songTitle);

		// ★ 难度输入框：初始取当前全局难度（非默认难度时带入，方便继续编辑该难度）
		var initDiff:String = '';
		try
		{
			var curDiff:String = Difficulty.getString();
			if (curDiff != null && curDiff != Difficulty.getDefault()) initDiff = curDiff;
		}
		catch (e:Dynamic) {}
		difficultyInputText = new FlxUIInputText(10, 55, 70, initDiff, 8);
		// A custom difficulty loaded through this editor may not be in the global difficulty list.
		if (Song.chartPath != null && Song.loadedSongName != null && Paths.formatToSongPath(Song.loadedSongName) == Paths.formatToSongPath(_song.song))
		{
			var chartFile = haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(Song.chartPath.replace('\\', '/')));
			var prefix = Paths.formatToSongPath(_song.song) + '-';
			if (chartFile.startsWith(prefix)) difficultyInputText.text = chartFile.substr(prefix.length);
		}
		blockPressWhileTypingOn.push(difficultyInputText);

		check_voices = new FlxUICheckBox(10, 25, null, null, "Has voice track", 100);
		check_voices.checked = _song.needsVoices;
		// _song.needsVoices = check_voices.checked;
		check_voices.callback = function()
		{
			beginHistoryAction('history_edit_chart');
			_song.needsVoices = check_voices.checked;
			commitHistoryAction();
			// trace('CHECKED!');
		};

		var saveButton:FlxButton = new FlxButton(110, 8, "Save", function()
		{
			saveLevel();
		});

		var reloadSong:FlxButton = new FlxButton(saveButton.x + 90, saveButton.y, "Reload Audio", function()
		{
			currentSongName = Paths.formatToSongPath(UI_songTitle.text);
			updateJsonData();
			withHistoryAction('history_edit_chart', loadSong);
			updateWaveform();
		});

		var reloadSongJson:FlxButton = new FlxButton(reloadSong.x, saveButton.y + 30, "Reload JSON", function()
		{
			openSubState(new Prompt('This action will clear current progress.\n\nProceed?', 0, function()
			{
				loadJson(_song.song.toLowerCase());
			}, null, ignoreWarnings));
		});

		var engineBtn:FlxButton = new FlxButton(reloadSongJson.x, reloadSongJson.y + 30, 'Engine', function()
		{
			handleMenuAction('engine');
		});
		engineBtn.label.setFormat(Paths.font(Language.get('fontName', 'main') + '.ttf'), 8, CENTER);

		var loadAutosaveBtn:FlxButton = new FlxButton(reloadSongJson.x, engineBtn.y + 30, 'Load Autosave', function()
		{
			PlayState.SONG = Song.parseJSON(FlxG.save.data.autosave);
			MusicBeatState.resetState();
		});

		var loadEventJson:FlxButton = new FlxButton(loadAutosaveBtn.x, loadAutosaveBtn.y + 30, 'Load Events', function()
		{
			var songName:String = Paths.formatToSongPath(_song.song);
			var file:String = Paths.json(songName + '/events');
			#if sys
			if (#if MODS_ALLOWED FileSystem.exists(Paths.modsJson(songName + '/events')) || #end FileSystem.exists(file))
			#else
			if (Assets.exists(file))
			#end
			{
				beginHistoryAction('history_load_events');
				_song.events = [];
				var savedFmt = Song.detectedFormat;
				var savedCE = Song.chartEngineVersion;
				var events:SwagSong = Song.loadFromJson('events', songName);
				Song.detectedFormat = savedFmt;
				Song.chartEngineVersion = savedCE;
				_song.events = events.events;
				changeSection(curSec);
				commitHistoryAction();
			}
		});

		var saveEvents:FlxButton = new FlxButton(110, reloadSongJson.y, 'Save Events', function()
		{
			saveEvents();
		});

		var clear_events:FlxButton = new FlxButton(320, 310, 'Clear events', function()
		{
			openSubState(new Prompt('This action will clear current progress.\n\nProceed?', 0, clearEvents, null, ignoreWarnings));
		});
		clear_events.color = FlxColor.RED;
		clear_events.label.color = FlxColor.WHITE;

		var clear_notes:FlxButton = new FlxButton(320, clear_events.y + 30, 'Clear notes', function()
		{
			openSubState(new Prompt('This action will clear current progress.\n\nProceed?', 0, function()
			{
				beginHistoryAction('history_clear_notes');
				for (sec in 0..._song.notes.length)
				{
					_song.notes[sec].sectionNotes = [];
				}
				updateGrid();
				commitHistoryAction();
			}, null, ignoreWarnings));
		});
		clear_notes.color = FlxColor.RED;
		clear_notes.label.color = FlxColor.WHITE;

		songBpmStepper = new FlxUINumericStepper(10, 70, 1, 1, 1, 400, 3, FlxUINumericStepper.STACK_VERTICAL);
		songBpmStepper.value = Conductor.bpm;
		songBpmStepper.name = 'song_bpm';
		blockPressWhileTypingOnStepper.push(songBpmStepper);

		stepperSpeed = new FlxUINumericStepper(10, songBpmStepper.y + 35, 0.1, 1, 0.1, 10, 2, FlxUINumericStepper.STACK_VERTICAL);
		stepperSpeed.value = _song.speed;
		stepperSpeed.name = 'song_speed';
		blockPressWhileTypingOnStepper.push(stepperSpeed);

		// ★ mania 在 UI 上显示「键数」（4K=4），内部仍是「每边键数-1」（4K=mania 3）。
		//   stepper 范围也整体 +1，从「键数 1..10」而不是「mania 0..9」。
		// ★ Mania 步进器阈值：extrakeys.json 缺失时兜底 1~10，避免 ± 越界崩溃
		var maniaMinK:Int = 1;
		var maniaMaxK:Int = extraMaxKeys();
		stepperMania = new FlxUINumericStepper(100, stepperSpeed.y, 1, _song.mania + 1, maniaMinK + 1, maniaMaxK + 1, 1, FlxUINumericStepper.STACK_VERTICAL);
		stepperMania.value = _song.mania + 1;
		stepperMania.name = 'song_mania';
		blockPressWhileTypingOnStepper.push(stepperMania);

		#if MODS_ALLOWED
		var directories:Array<String> = [
			Paths.mods('characters/'),
			Paths.mods(Mods.currentModDirectory + '/characters/'),
			Paths.getSharedPath('characters/')
		];
		for (mod in Mods.getGlobalMods())
			directories.push(Paths.mods(mod + '/characters/'));
		#else
		var directories:Array<String> = [Paths.getSharedPath('characters/')];
		#end

		var tempArray:Array<String> = [];
		var characters:Array<String> = Mods.mergeAllTextsNamed('data/characterList.txt', Paths.getSharedPath());
		for (character in characters)
		{
			if (character.trim().length > 0)
				tempArray.push(character);
		}

		#if MODS_ALLOWED
		for (i in 0...directories.length)
		{
			var directory:String = directories[i];
			if (FileSystem.exists(directory))
			{
				for (file in FileSystem.readDirectory(directory))
				{
					var path = haxe.io.Path.join([directory, file]);
					if (!FileSystem.isDirectory(path) && file.endsWith('.json'))
					{
						var charToCheck:String = file.substr(0, file.length - 5);
						if (charToCheck.trim().length > 0 && !charToCheck.endsWith('-dead') && !tempArray.contains(charToCheck))
						{
							tempArray.push(charToCheck);
							characters.push(charToCheck);
						}
					}
				}
			}
		}
		#end
		tempArray = [];

		player1DropDown = new FlxUIDropDownMenu(10, stepperSpeed.y + 45, FlxUIDropDownMenu.makeStrIdLabelArray(characters, true),
			function(character:String)
			{
				beginHistoryAction('history_edit_chart');
				_song.player1 = characters[Std.parseInt(character)];
				commitHistoryAction();
				updateJsonData();
				updateHeads();
				reloadGridLayer(); // ★ 换角色后背景/波形颜色立即跟随
			});
		player1DropDown.selectedLabel = _song.player1;
		blockPressWhileScrolling.push(player1DropDown);

		gfVersionDropDown = new FlxUIDropDownMenu(player1DropDown.x, player1DropDown.y + 40, FlxUIDropDownMenu.makeStrIdLabelArray(characters, true),
			function(character:String)
			{
				beginHistoryAction('history_edit_chart');
				_song.gfVersion = characters[Std.parseInt(character)];
				commitHistoryAction();
				updateJsonData();
				updateHeads();
			});
		gfVersionDropDown.selectedLabel = _song.gfVersion;
		blockPressWhileScrolling.push(gfVersionDropDown);

		player2DropDown = new FlxUIDropDownMenu(player1DropDown.x, gfVersionDropDown.y + 40, FlxUIDropDownMenu.makeStrIdLabelArray(characters, true),
			function(character:String)
			{
				beginHistoryAction('history_edit_chart');
				_song.player2 = characters[Std.parseInt(character)];
				commitHistoryAction();
				updateJsonData();
				updateHeads();
				reloadGridLayer(); // ★ 换角色后背景/波形颜色立即跟随
			});
		player2DropDown.selectedLabel = _song.player2;
		blockPressWhileScrolling.push(player2DropDown);

		#if MODS_ALLOWED
		var directories:Array<String> = [
			Paths.mods('stages/'),
			Paths.mods(Mods.currentModDirectory + '/stages/'),
			Paths.getSharedPath('stages/')
		];
		for (mod in Mods.getGlobalMods())
			directories.push(Paths.mods(mod + '/stages/'));
		#else
		var directories:Array<String> = [Paths.getSharedPath('stages/')];
		#end

		var stageFile:Array<String> = Mods.mergeAllTextsNamed('data/stageList.txt', Paths.getSharedPath());
		var stages:Array<String> = [];
		for (stage in stageFile)
		{
			if (stage.trim().length > 0)
			{
				stages.push(stage);
			}
			tempArray.push(stage);
		}
		#if MODS_ALLOWED
		for (i in 0...directories.length)
		{
			var directory:String = directories[i];
			if (FileSystem.exists(directory))
			{
				for (file in FileSystem.readDirectory(directory))
				{
					var path = haxe.io.Path.join([directory, file]);
					if (!FileSystem.isDirectory(path) && file.endsWith('.json'))
					{
						var stageToCheck:String = file.substr(0, file.length - 5);
						if (stageToCheck.trim().length > 0 && !tempArray.contains(stageToCheck))
						{
							tempArray.push(stageToCheck);
							stages.push(stageToCheck);
						}
					}
				}
			}
		}
		#end

		if (stages.length < 1)
			stages.push('stage');

		stageDropDown = new FlxUIDropDownMenu(player1DropDown.x + 140, player1DropDown.y, FlxUIDropDownMenu.makeStrIdLabelArray(stages, true),
			function(character:String)
			{
				beginHistoryAction('history_edit_chart');
				_song.stage = stages[Std.parseInt(character)];
				commitHistoryAction();
			});
		stageDropDown.selectedLabel = _song.stage;
		blockPressWhileScrolling.push(stageDropDown);

		// 隐藏所有局部 FlxButton（只保留回调功能，不在旧 UI 上显示）
		var songButtons:Array<FlxButton> = [saveButton, reloadSong, reloadSongJson, engineBtn, loadAutosaveBtn, loadEventJson, saveEvents, clear_events, clear_notes];
		for (b in songButtons) if (b != null) try { b.visible = false; } catch(e) {}

		// ★ 09-26 三轮（用户要求「播放条固定不动」）：不再用 follow(camPos, LOCKON, 999)。
		//   follow 的 lerp 会让播放中的白条/角色头像持续漂移；改成 update() 里把
		//   camera.scroll 硬同步到「白条 - 半屏」，白条屏幕位置恒为屏幕中心。
		initPsychCamera();
	}

	var stepperBeats:FlxUINumericStepper;
	var check_mustHitSection:FlxUICheckBox;
	var check_gfSection:FlxUICheckBox;
	var check_changeBPM:FlxUICheckBox;
	var stepperSectionBPM:FlxUINumericStepper;
	var check_altAnim:FlxUICheckBox;

	var sectionToCopy:Int = 0;
	var notesCopied:Array<Dynamic>;

	function addSectionUI():Void
	{
		check_mustHitSection = new FlxUICheckBox(10, 15, null, null, "Must hit section", 100);
		check_mustHitSection.name = 'check_mustHit';
		check_mustHitSection.checked = _song.notes[curSec].mustHitSection;
		// ★ 新菜单系统不经过 UI_box 事件广播，必须在这里补 callback（原逻辑在 getEvent）
		check_mustHitSection.callback = function()
		{
			beginHistoryAction('history_edit_chart');
			_song.notes[curSec].mustHitSection = check_mustHitSection.checked;
			updateHeads();
			reloadGridLayer(); // ★ 背景/网格/波形归属整体跟随 mustHit
			commitHistoryAction();
		};

		check_gfSection = new FlxUICheckBox(10, check_mustHitSection.y + 22, null, null, "GF section", 100);
		check_gfSection.name = 'check_gf';
		check_gfSection.checked = _song.notes[curSec].gfSection;
		// _song.needsVoices = check_mustHit.checked;
		check_gfSection.callback = function()
		{
			beginHistoryAction('history_edit_chart');
			_song.notes[curSec].gfSection = check_gfSection.checked;
			updateGrid();
			updateHeads();
			commitHistoryAction();
		};

		check_altAnim = new FlxUICheckBox(check_gfSection.x + 120, check_gfSection.y, null, null, "Alt Animation", 100);
		check_altAnim.checked = _song.notes[curSec].altAnim;
		check_altAnim.callback = function()
		{
			beginHistoryAction('history_edit_chart');
			_song.notes[curSec].altAnim = check_altAnim.checked;
			commitHistoryAction();
		};

		stepperBeats = new FlxUINumericStepper(10, 100, 1, 4, 1, 7, 2, FlxUINumericStepper.STACK_VERTICAL);
		stepperBeats.value = getSectionBeats();
		stepperBeats.name = 'section_beats';
		blockPressWhileTypingOnStepper.push(stepperBeats);
		check_altAnim.name = 'check_altAnim';

		check_changeBPM = new FlxUICheckBox(10, stepperBeats.y + 30, null, null, 'Change BPM', 100);
		check_changeBPM.checked = _song.notes[curSec].changeBPM;
		check_changeBPM.name = 'check_changeBPM';
		// ★ 新菜单系统不经过 UI_box 事件广播，必须在这里补 callback（原逻辑在 getEvent）
		check_changeBPM.callback = function()
		{
			beginHistoryAction('history_edit_chart');
			_song.notes[curSec].changeBPM = check_changeBPM.checked;
			if (check_changeBPM.checked)
				stepperSectionBPM.value = _song.notes[curSec].bpm;
			else
				stepperSectionBPM.value = Conductor.bpm;
			commitHistoryAction();
		};

		stepperSectionBPM = new FlxUINumericStepper(10, check_changeBPM.y + 20, 1, Conductor.bpm, 0, 999, 1, FlxUINumericStepper.STACK_VERTICAL);
		if (check_changeBPM.checked)
		{
			stepperSectionBPM.value = _song.notes[curSec].bpm;
		}
		else
		{
			stepperSectionBPM.value = Conductor.bpm;
		}
		stepperSectionBPM.name = 'section_bpm';
		blockPressWhileTypingOnStepper.push(stepperSectionBPM);

		check_eventsSec = null;
		check_notesSec = null;
		var copyButton:FlxButton = new FlxButton(10, 190, "Copy Section", function()
		{
			notesCopied = [];
			sectionToCopy = curSec;
			for (i in 0..._song.notes[curSec].sectionNotes.length)
			{
				var note:Array<Dynamic> = _song.notes[curSec].sectionNotes[i];
				notesCopied.push(note);
			}

			var startThing:Float = sectionStartTime();
			var endThing:Float = sectionStartTime(1);
			for (event in _song.events)
			{
				var strumTime:Float = event[0];
				if (endThing > event[0] && event[0] >= startThing)
				{
					var copiedEventArray:Array<Dynamic> = [];
					for (i in 0...event[1].length)
					{
						var eventToPush:Array<Dynamic> = event[1][i];
						copiedEventArray.push([eventToPush[0], eventToPush[1], eventToPush[2]]);
					}
					notesCopied.push([strumTime, -1, copiedEventArray]);
				}
			}
		});

		var pasteButton:FlxButton = new FlxButton(copyButton.x + 100, copyButton.y, "Paste Section", function()
		{
			if (notesCopied == null || notesCopied.length < 1)
			{
				return;
			}

			beginHistoryAction('history_paste_section');
			var addToTime:Float = Conductor.stepCrochet * (getSectionBeats() * 4 * (curSec - sectionToCopy));
			// trace('Time to add: ' + addToTime);

			for (note in notesCopied)
			{
				var copiedNote:Array<Dynamic> = [];
				var newStrumTime:Float = note[0] + addToTime;
				if (note[1] < 0)
				{
					if (check_eventsSec.checked)
					{
						var copiedEventArray:Array<Dynamic> = [];
						for (i in 0...note[2].length)
						{
							var eventToPush:Array<Dynamic> = note[2][i];
							copiedEventArray.push([eventToPush[0], eventToPush[1], eventToPush[2]]);
						}
						_song.events.push([newStrumTime, copiedEventArray]);
					}
				}
				else
				{
					if (check_notesSec.checked)
					{
						if (note[4] != null)
							copiedNote = [newStrumTime, note[1], note[2], note[3], note[4]];
						else
							copiedNote = [newStrumTime, note[1], note[2], note[3]];

						_song.notes[curSec].sectionNotes.push(copiedNote);
					}
				}
			}
			updateGrid();
			commitHistoryAction();
		});

		var clearSectionButton:FlxButton = new FlxButton(pasteButton.x + 100, pasteButton.y, "Clear", function()
		{
			beginHistoryAction('history_clear_section');
			if (check_notesSec.checked)
			{
				_song.notes[curSec].sectionNotes = [];
			}

			if (check_eventsSec.checked)
			{
				var i:Int = _song.events.length - 1;
				var startThing:Float = sectionStartTime();
				var endThing:Float = sectionStartTime(1);
				while (i > -1)
				{
					var event:Array<Dynamic> = _song.events[i];
					if (event != null && endThing > event[0] && event[0] >= startThing)
					{
						_song.events.remove(event);
					}
					--i;
				}
			}
			updateGrid();
			updateNoteUI();
			commitHistoryAction();
		});
		clearSectionButton.color = FlxColor.RED;
		clearSectionButton.label.color = FlxColor.WHITE;

		check_notesSec = new FlxUICheckBox(10, clearSectionButton.y + 25, null, null, "Notes", 100);
		check_notesSec.checked = true;
		check_eventsSec = new FlxUICheckBox(check_notesSec.x + 100, check_notesSec.y, null, null, "Events", 100);
		check_eventsSec.checked = true;

		var swapSection:FlxButton = new FlxButton(10, check_notesSec.y + 40, "Swap section", function()
		{
			beginHistoryAction('history_swap_sides');
			for (i in 0..._song.notes[curSec].sectionNotes.length)
			{
				var note:Array<Dynamic> = _song.notes[curSec].sectionNotes[i];
				note[1] = (note[1] + leftKeys) % totalKeys;
				_song.notes[curSec].sectionNotes[i] = note;
			}
			updateGrid();
			commitHistoryAction();
		});

		var copyLastButton:FlxButton = new FlxButton(10, swapSection.y + 30, "Copy last section", function()
		{
			var value:Int = Std.int(copyBeatStepper.value);
			if (value == 0)
				return;

			beginHistoryAction('history_copy_section');
			var daSec = FlxMath.maxInt(curSec, value);

			for (note in _song.notes[daSec - value].sectionNotes)
			{
				var strum = note[0] + Conductor.stepCrochet * (getSectionBeats(daSec) * 4 * value);

				var copiedNote:Array<Dynamic> = [strum, note[1], note[2], note[3]];
				_song.notes[daSec].sectionNotes.push(copiedNote);
			}

			var startThing:Float = sectionStartTime(-value);
			var endThing:Float = sectionStartTime(-value + 1);
			for (event in _song.events)
			{
				var strumTime:Float = event[0];
				if (endThing > event[0] && event[0] >= startThing)
				{
					strumTime += Conductor.stepCrochet * (getSectionBeats(daSec) * 4 * value);
					var copiedEventArray:Array<Dynamic> = [];
					for (i in 0...event[1].length)
					{
						var eventToPush:Array<Dynamic> = event[1][i];
						copiedEventArray.push([eventToPush[0], eventToPush[1], eventToPush[2]]);
					}
					_song.events.push([strumTime, copiedEventArray]);
				}
			}
			updateGrid();
			commitHistoryAction();
		});
		copyLastButton.setGraphicSize(80, 30);
		copyLastButton.updateHitbox();

		copyBeatStepper = new FlxUINumericStepper(copyLastButton.x + 100, copyLastButton.y, 1, 1, -99, 99, 0, FlxUINumericStepper.STACK_VERTICAL);
		blockPressWhileTypingOnStepper.push(copyBeatStepper);

		var duetButton:FlxButton = new FlxButton(10, copyLastButton.y + 45, "Duet Notes", function()
		{
			beginHistoryAction('history_duet');
			var duetNotes:Array<Array<Dynamic>> = [];
			for (note in _song.notes[curSec].sectionNotes)
			{
				var boob = note[1];
				if (boob >= leftKeys)
				{
					boob -= leftKeys;
				}
				else
				{
					boob += leftKeys;
				}

				var copiedNote:Array<Dynamic> = [note[0], boob, note[2], note[3]];
				duetNotes.push(copiedNote);
			}

			for (i in duetNotes)
			{
				_song.notes[curSec].sectionNotes.push(i);
			}

			updateGrid();
			commitHistoryAction();
		});
		var mirrorButton:FlxButton = new FlxButton(duetButton.x + 100, duetButton.y, "Mirror Notes", function()
		{
			beginHistoryAction('history_mirror');
			var duetNotes:Array<Array<Dynamic>> = [];
			for (note in _song.notes[curSec].sectionNotes)
			{
				var boob = note[1] % leftKeys;
				boob = (leftKeys - 1) - boob;
				if (note[1] >= leftKeys)
					boob += leftKeys;

				note[1] = boob;
				var copiedNote:Array<Dynamic> = [note[0], boob, note[2], note[3]];
				// duetNotes.push(copiedNote);
			}

			for (i in duetNotes)
			{
				// _song.notes[curSec].sectionNotes.push(i);
			}

			updateGrid();
			commitHistoryAction();
		});

		// 隐藏所有局部 button/stepper（只保留回调功能，不在旧 UI 上显示）
		var sectionWidgets:Array<Dynamic> = [copyButton, pasteButton, clearSectionButton, swapSection, copyLastButton, duetButton, mirrorButton, copyBeatStepper];
		for (w in sectionWidgets) if (w != null) try { w.visible = false; } catch(e) {}
	}

	var stepperSusLength:FlxUINumericStepper;
	var copyBeatStepper:FlxUINumericStepper; // 复制节拍：相对当前小节的偏移（正数=从[N-数]拍复制过来，负数反之）
	var strumTimeInputText:FlxUIInputText; // I wanted to use a stepper but we can't scale these as far as i know :(
	var noteTypeDropDown:FlxUIDropDownMenu;
	var currentType:Int = 0;

	function addNoteUI():Void
	{
		stepperSusLength = new FlxUINumericStepper(10, 25, Conductor.stepCrochet / 2, 0, 0, Conductor.stepCrochet * 64, 1, FlxUINumericStepper.STACK_VERTICAL);
		stepperSusLength.value = 0;
		stepperSusLength.name = 'note_susLength';
		blockPressWhileTypingOnStepper.push(stepperSusLength);

		strumTimeInputText = new FlxUIInputText(10, 65, 180, "0");
		blockPressWhileTypingOn.push(strumTimeInputText);

		var key:Int = 0;
		while (key < noteTypeList.length)
		{
			curNoteTypes.push(noteTypeList[key]);
			key++;
		}

		#if sys
		var foldersToCheck:Array<String> = Mods.directoriesWithFile(Paths.getSharedPath(), 'custom_notetypes/');
		for (folder in foldersToCheck)
			for (file in FileSystem.readDirectory(folder))
			{
				var fileName:String = file.toLowerCase().trim();
				var wordLen:Int = 4; // length of word ".lua" and ".txt";
				if ((#if LUA_ALLOWED fileName.endsWith('.lua') || #end#if HSCRIPT_ALLOWED (fileName.endsWith('.hx') && (wordLen = 3) == 3)
					|| #end fileName.endsWith('.txt')) && fileName != 'readme.txt')
				{
					var fileToCheck:String = file.substr(0, file.length - wordLen);
					if (!curNoteTypes.contains(fileToCheck))
					{
						curNoteTypes.push(fileToCheck);
						key++;
					}
				}
			}
		#end

		var displayNameList:Array<String> = curNoteTypes.copy();
		for (i in 1...displayNameList.length)
		{
			displayNameList[i] = i + '. ' + displayNameList[i];
		}

		noteTypeDropDown = new FlxUIDropDownMenu(10, 105, FlxUIDropDownMenu.makeStrIdLabelArray(displayNameList, true), function(character:String)
		{
			currentType = Std.parseInt(character);
			if (curSelectedNote != null && curSelectedNote[1] > -1)
			{
				beginHistoryAction('history_edit_chart');
				curSelectedNote[3] = curNoteTypes[currentType];
				commitHistoryAction();
				updateGrid();
			}
		});
		blockPressWhileScrolling.push(noteTypeDropDown);

	}

	var eventDropDown:FlxUIDropDownMenu;
	var descText:FlxText;
	var selectedEventText:FlxText;

	function addEventsUI():Void
	{
		#if LUA_ALLOWED
		var eventPushedMap:Map<String, Bool> = new Map<String, Bool>();
		var directories:Array<String> = [];

		#if MODS_ALLOWED
		directories.push(Paths.mods('custom_events/'));
		directories.push(Paths.mods(Mods.currentModDirectory + '/custom_events/'));
		for (mod in Mods.getGlobalMods())
			directories.push(Paths.mods(mod + '/custom_events/'));
		#end

		for (i in 0...directories.length)
		{
			var directory:String = directories[i];
			if (FileSystem.exists(directory))
			{
				for (file in FileSystem.readDirectory(directory))
				{
					var path = haxe.io.Path.join([directory, file]);
					if (!FileSystem.isDirectory(path) && file != 'readme.txt' && file.endsWith('.txt'))
					{
						var fileToCheck:String = file.substr(0, file.length - 4);
						if (!eventPushedMap.exists(fileToCheck))
						{
							eventPushedMap.set(fileToCheck, true);
							eventStuff.push([fileToCheck, File.getContent(path)]);
						}
					}
				}
			}
		}
		eventPushedMap.clear();
		eventPushedMap = null;
		#end

		descText = new EditorText(20, 200, 0, eventStuff[0][0]);

		var leEvents:Array<String> = [];
		for (i in 0...eventStuff.length)
		{
			leEvents.push(eventStuff[i][0]);
		}

		var text:FlxText = new EditorText(20, 30, 0, "Event:");
		text.visible = false;
		eventDropDown = new FlxUIDropDownMenu(20, 50, FlxUIDropDownMenu.makeStrIdLabelArray(leEvents, true), function(pressed:String)
		{
			// ★ 防御：pressed 可能非数字 → Std.parseInt 返回 null → eventStuff[null] 空指针崩溃
			var selectedEvent:Null<Int> = null;
			try { selectedEvent = Std.parseInt(pressed); } catch(e:Dynamic) { selectedEvent = null; }
			if (selectedEvent == null || selectedEvent < 0 || selectedEvent >= eventStuff.length) return;
			descText.text = eventStuff[selectedEvent][1];
			if (curSelectedNote != null && eventStuff != null)
			{
				// ★ 事件音符判定用 [1] 是否为数组（[2]==null 对旧谱面普通音符不可靠 → 空指针崩溃）
				if (Std.is(curSelectedNote[1], Array))
				{
					var evGroup:Array<Dynamic> = cast curSelectedNote[1];
					if (evGroup != null && evGroup.length > 0
						&& curEventSelected >= 0 && curEventSelected < evGroup.length
						&& Std.is(evGroup[curEventSelected], Array))
					{
						beginHistoryAction('history_edit_chart');
						evGroup[curEventSelected][0] = eventStuff[selectedEvent][0];
						commitHistoryAction();
					}
				}
				updateGrid();
			}
		});
		blockPressWhileScrolling.push(eventDropDown);

		var text:FlxText = new EditorText(20, 90, 0, "Value 1:");
		text.visible = false;
		value1InputText = new FlxUIInputText(20, 110, 100, "");
		blockPressWhileTypingOn.push(value1InputText);

		var text:FlxText = new EditorText(20, 130, 0, "Value 2:");
		text.visible = false;
		value2InputText = new FlxUIInputText(20, 150, 100, "");
		blockPressWhileTypingOn.push(value2InputText);

		// New event buttons
		var removeButton:FlxButton = new FlxButton(eventDropDown.x + eventDropDown.width + 10, eventDropDown.y, '-', function()
		{
			// ★ 事件音符判定用 [1] 是否为数组（[2]==null 对旧谱面普通音符不可靠 → 空指针崩溃）
			if (curSelectedNote != null && Std.is(curSelectedNote[1], Array))
			{
				var eventsGroup:Array<Dynamic> = cast curSelectedNote[1];
				if (eventsGroup == null) return;
				beginHistoryAction('history_delete_item');
				if (eventsGroup.length < 2)
				{
					_song.events.remove(curSelectedNote);
					curSelectedNote = null;
				}
				else
				{
					eventsGroup.remove(eventsGroup[curEventSelected]);
				}

				--curEventSelected;
				if (curEventSelected < 0)
					curEventSelected = 0;
				else if (curSelectedNote != null && curEventSelected >= eventsGroup.length)
					curEventSelected = eventsGroup.length - 1;

				changeEventSelected();
				updateGrid();
				commitHistoryAction();
			}
		});
		removeButton.setGraphicSize(Std.int(removeButton.height), Std.int(removeButton.height));
		removeButton.updateHitbox();
		removeButton.color = FlxColor.RED;
		removeButton.label.color = FlxColor.WHITE;
		removeButton.label.size = 12;
		setAllLabelsOffset(removeButton, -30, 0);

		var addButton:FlxButton = new FlxButton(removeButton.x + removeButton.width + 10, removeButton.y, '+', function()
		{
			// ★ 事件音符判定用 [1] 是否为数组（[2]==null 对旧谱面普通音符不可靠 → 空指针崩溃）
			if (curSelectedNote != null && Std.is(curSelectedNote[1], Array))
			{
				var eventsGroup:Array<Dynamic> = cast curSelectedNote[1];
				if (eventsGroup == null) return;
				beginHistoryAction('history_add_item');
				eventsGroup.push(['', '', '']);

				changeEventSelected(1);
				updateGrid();
				commitHistoryAction();
			}
		});
		addButton.setGraphicSize(Std.int(removeButton.width), Std.int(removeButton.height));
		addButton.updateHitbox();
		addButton.color = FlxColor.GREEN;
		addButton.label.color = FlxColor.WHITE;
		addButton.label.size = 12;
		setAllLabelsOffset(addButton, -30, 0);

		var moveLeftButton:FlxButton = new FlxButton(addButton.x + addButton.width + 20, addButton.y, '<', function()
		{
			changeEventSelected(-1);
		});
		moveLeftButton.setGraphicSize(Std.int(addButton.width), Std.int(addButton.height));
		moveLeftButton.updateHitbox();
		moveLeftButton.label.size = 12;
		setAllLabelsOffset(moveLeftButton, -30, 0);

		var moveRightButton:FlxButton = new FlxButton(moveLeftButton.x + moveLeftButton.width + 10, moveLeftButton.y, '>', function()
		{
			changeEventSelected(1);
		});
		moveRightButton.setGraphicSize(Std.int(moveLeftButton.width), Std.int(moveLeftButton.height));
		moveRightButton.updateHitbox();
		moveRightButton.label.size = 12;
		setAllLabelsOffset(moveRightButton, -30, 0);

		selectedEventText = new EditorText(addButton.x - 100, addButton.y + addButton.height + 6, (moveRightButton.x - addButton.x) + 186, 'Selected Event: None');
		selectedEventText.alignment = CENTER;

		// 隐藏所有局部 button（只保留回调功能，不在旧 UI 上显示）
		var eventButtons:Array<FlxButton> = [removeButton, addButton, moveLeftButton, moveRightButton];
		for (b in eventButtons) if (b != null) try { b.visible = false; } catch(e) {}
	}

	function changeEventSelected(change:Int = 0)
	{
		// ★ 事件音符判定用 [1] 是否为数组（[2]==null 不可靠，旧谱面普通音符 susLength 可能缺失）
		if (curSelectedNote != null && Std.is(curSelectedNote[1], Array))
		{
			var eventsGroup:Array<Dynamic> = cast curSelectedNote[1];
			if (eventsGroup == null || eventsGroup.length < 1)
			{
				curEventSelected = 0;
				selectedEventText.text = 'Selected Event: None';
			}
			else
			{
				curEventSelected += change;
				if (curEventSelected < 0)
					curEventSelected = eventsGroup.length - 1;
				else if (curEventSelected >= eventsGroup.length)
					curEventSelected = 0;
				selectedEventText.text = 'Selected Event: ' + (curEventSelected + 1) + ' / ' + eventsGroup.length;
			}
		}
		else
		{
			curEventSelected = 0;
			selectedEventText.text = 'Selected Event: None';
		}
		updateNoteUI();
	}

	function setAllLabelsOffset(button:FlxButton, x:Float, y:Float)
	{
		for (point in button.labelOffsets)
		{
			point.set(x, y);
		}
	}

	var metronome:FlxUICheckBox;
	var mouseScrollingQuant:FlxUICheckBox;
	var metronomeStepper:FlxUINumericStepper;
	var metronomeOffsetStepper:FlxUINumericStepper;
	var disableAutoScrolling:FlxUICheckBox;
	var instVolume:FlxUINumericStepper;
	var voicesVolume:FlxUINumericStepper;
	var voicesOppVolume:FlxUINumericStepper;

	function addChartingUI()
	{

		#if (desktop || mobile)
		if (FlxG.save.data.chart_waveformInst == null)
			FlxG.save.data.chart_waveformInst = false;
		if (FlxG.save.data.chart_waveformVoices == null)
			FlxG.save.data.chart_waveformVoices = false;
		if (FlxG.save.data.chart_waveformOppVoices == null)
			FlxG.save.data.chart_waveformOppVoices = false;

		// 这三个原是局部变量，提升到类成员以便顶栏菜单 registerCheck / toggle
		waveformUseInstrumental = null;
		waveformUseVoices = null;
		waveformUseOppVoices = null;

		waveformUseInstrumental = new FlxUICheckBox(10, 90, null, null, "Waveform\n(Instrumental)", 85);
		waveformUseInstrumental.checked = FlxG.save.data.chart_waveformInst;
		// ★ 互斥已取消：BF / Inst / Opp 波形可同时开启（BF 画左侧、Opp 画右侧、Inst 全宽）
		waveformUseInstrumental.callback = function()
		{
			FlxG.save.data.chart_waveformInst = waveformUseInstrumental.checked;
			updateWaveform();
		};

		waveformUseVoices = new FlxUICheckBox(waveformUseInstrumental.x + 100, waveformUseInstrumental.y, null, null, "Waveform\n(Main Vocals)", 85);
		waveformUseVoices.checked = FlxG.save.data.chart_waveformVoices;
		waveformUseVoices.callback = function()
		{
			FlxG.save.data.chart_waveformVoices = waveformUseVoices.checked;
			updateWaveform();
		};

		waveformUseOppVoices = new FlxUICheckBox(waveformUseInstrumental.x + 200, waveformUseInstrumental.y, null, null, "Waveform\n(Opp. Vocals)", 85);
		waveformUseOppVoices.checked = FlxG.save.data.chart_waveformOppVoices;
		waveformUseOppVoices.callback = function()
		{
			FlxG.save.data.chart_waveformOppVoices = waveformUseOppVoices.checked;
			updateWaveform();
		};
		#end

		check_mute_inst = new FlxUICheckBox(10, 280, null, null, "Mute Instrumental (in editor)", 100);
		check_mute_inst.checked = false;
		check_mute_inst.callback = function()
		{
			var vol:Float = instVolume.value;
			if (check_mute_inst.checked)
				vol = 0;

			FlxG.sound.music.volume = vol;
		};
		mouseScrollingQuant = new FlxUICheckBox(10, 190, null, null, "Mouse Scrolling Quantization", 100);
		if (FlxG.save.data.mouseScrollingQuant == null)
			FlxG.save.data.mouseScrollingQuant = false;
		mouseScrollingQuant.checked = FlxG.save.data.mouseScrollingQuant;

		mouseScrollingQuant.callback = function()
		{
			FlxG.save.data.mouseScrollingQuant = mouseScrollingQuant.checked;
			mouseQuant = FlxG.save.data.mouseScrollingQuant;
		};

		check_vortex = new FlxUICheckBox(10, 160, null, null, "Vortex Editor (BETA)", 100);
		if (FlxG.save.data.chart_vortex == null)
			FlxG.save.data.chart_vortex = false;
		check_vortex.checked = FlxG.save.data.chart_vortex;

		check_vortex.callback = function()
		{
			FlxG.save.data.chart_vortex = check_vortex.checked;
			vortex = FlxG.save.data.chart_vortex;
			reloadGridLayer();
		};

		check_warnings = new FlxUICheckBox(10, 120, null, null, "Ignore Progress Warnings", 100);
		if (FlxG.save.data.ignoreWarnings == null)
			FlxG.save.data.ignoreWarnings = false;
		check_warnings.checked = FlxG.save.data.ignoreWarnings;

		check_warnings.callback = function()
		{
			FlxG.save.data.ignoreWarnings = check_warnings.checked;
			ignoreWarnings = FlxG.save.data.ignoreWarnings;
		};

		check_mute_vocals = new FlxUICheckBox(check_mute_inst.x, check_mute_inst.y + 30, null, null, "Mute Main Vocals (in editor)", 100);
		check_mute_vocals.checked = false;
		check_mute_vocals.callback = function()
		{
			var vol:Float = voicesVolume.value;
			if (check_mute_vocals.checked)
				vol = 0;

			if (vocals != null)
				vocals.volume = vol;
		};
		check_mute_vocals_opponent = new FlxUICheckBox(check_mute_vocals.x + 120, check_mute_vocals.y, null, null, "Mute Opp. Vocals (in editor)", 100);
		check_mute_vocals_opponent.checked = false;
		check_mute_vocals_opponent.callback = function()
		{
			var vol:Float = voicesOppVolume.value;
			if (check_mute_vocals_opponent.checked)
				vol = 0;

			if (opponentVocals != null)
				opponentVocals.volume = vol;
		};

		playSoundBf = new FlxUICheckBox(check_mute_inst.x, check_mute_vocals.y + 30, null, null, 'Play Sound (Boyfriend notes)', 100, function()
		{
			FlxG.save.data.chart_playSoundBf = playSoundBf.checked;
		});
		if (FlxG.save.data.chart_playSoundBf == null)
			FlxG.save.data.chart_playSoundBf = false;
		playSoundBf.checked = FlxG.save.data.chart_playSoundBf;

		playSoundDad = new FlxUICheckBox(check_mute_inst.x + 120, playSoundBf.y, null, null, 'Play Sound (Opponent notes)', 100, function()
		{
			FlxG.save.data.chart_playSoundDad = playSoundDad.checked;
		});
		if (FlxG.save.data.chart_playSoundDad == null)
			FlxG.save.data.chart_playSoundDad = false;
		playSoundDad.checked = FlxG.save.data.chart_playSoundDad;

		metronome = new FlxUICheckBox(10, 15, null, null, "Metronome Enabled", 100, function()
		{
			FlxG.save.data.chart_metronome = metronome.checked;
		});
		if (FlxG.save.data.chart_metronome == null)
			FlxG.save.data.chart_metronome = false;
		metronome.checked = FlxG.save.data.chart_metronome;

		// ★ 节拍器 BPM：默认步长 1（Shift+点击 ±5 由菜单栏 stepperStep 处理），不再固定 ±5
		metronomeStepper = new FlxUINumericStepper(15, 55, 1, _song.bpm, 1, 1500, 1, FlxUINumericStepper.STACK_VERTICAL);
		metronomeOffsetStepper = new FlxUINumericStepper(metronomeStepper.x + 100, metronomeStepper.y, 25, 0, 0, 1000, 1, FlxUINumericStepper.STACK_VERTICAL);
		blockPressWhileTypingOnStepper.push(metronomeStepper);
		blockPressWhileTypingOnStepper.push(metronomeOffsetStepper);

		disableAutoScrolling = new FlxUICheckBox(metronome.x + 120, metronome.y, null, null, "Disable Autoscroll (Not Recommended)", 120, function()
		{
			FlxG.save.data.chart_noAutoScroll = disableAutoScrolling.checked;
		});
		if (FlxG.save.data.chart_noAutoScroll == null)
			FlxG.save.data.chart_noAutoScroll = false;
		disableAutoScrolling.checked = FlxG.save.data.chart_noAutoScroll;

		instVolume = new FlxUINumericStepper(metronomeStepper.x, 250, 0.1, 1, 0, 1, 1, FlxUINumericStepper.STACK_VERTICAL);
		instVolume.value = FlxG.sound.music.volume;
		instVolume.name = 'inst_volume';
		blockPressWhileTypingOnStepper.push(instVolume);

		voicesVolume = new FlxUINumericStepper(instVolume.x + 100, instVolume.y, 0.1, 1, 0, 1, 1, FlxUINumericStepper.STACK_VERTICAL);
		voicesVolume.value = vocals.volume;
		voicesVolume.name = 'voices_volume';
		blockPressWhileTypingOnStepper.push(voicesVolume);

		voicesOppVolume = new FlxUINumericStepper(instVolume.x + 200, instVolume.y, 0.1, 1, 0, 1, 1, FlxUINumericStepper.STACK_VERTICAL);
		voicesOppVolume.value = vocals.volume;
		voicesOppVolume.name = 'voices_opp_volume';
		blockPressWhileTypingOnStepper.push(voicesOppVolume);

		#if FLX_PITCH
		sliderRate = new FlxUISlider(this, 'playbackSpeed', 120, 120, 0.5, 3, 150, #if !hl null #else 0 #end, 5, FlxColor.WHITE, FlxColor.BLACK);
		sliderRate.nameLabel.text = 'Playback Rate';
		#end

	}

	var gameOverCharacterInputText:FlxUIInputText;
	var gameOverSoundInputText:FlxUIInputText;
	var gameOverLoopInputText:FlxUIInputText;
	var gameOverEndInputText:FlxUIInputText;

	var noteSkinInputText:FlxUIInputText;
	var noteSplashesInputText:FlxUIInputText;

	function addDataUI()
	{
		//
		gameOverCharacterInputText = new FlxUIInputText(10, 25, 150, _song.gameOverChar != null ? _song.gameOverChar : '', 8);
		blockPressWhileTypingOn.push(gameOverCharacterInputText);

		gameOverSoundInputText = new FlxUIInputText(10, gameOverCharacterInputText.y + 35, 150, _song.gameOverSound != null ? _song.gameOverSound : '', 8);
		blockPressWhileTypingOn.push(gameOverSoundInputText);

		gameOverLoopInputText = new FlxUIInputText(10, gameOverSoundInputText.y + 35, 150, _song.gameOverLoop != null ? _song.gameOverLoop : '', 8);
		blockPressWhileTypingOn.push(gameOverLoopInputText);

		gameOverEndInputText = new FlxUIInputText(10, gameOverLoopInputText.y + 35, 150, _song.gameOverEnd != null ? _song.gameOverEnd : '', 8);
		blockPressWhileTypingOn.push(gameOverEndInputText);
		//

		check_disableNoteRGB = new FlxUICheckBox(10, 170, null, null, "Disable Note RGB", 100);
		check_disableNoteRGB.checked = (_song.disableNoteRGB == true);
		check_disableNoteRGB.callback = function()
		{
			beginHistoryAction('history_edit_chart');
			_song.disableNoteRGB = check_disableNoteRGB.checked;
			commitHistoryAction();
			// ★ 必须同时重建网格音符与顶部受体箭头：只 updateGrid() 的话
			//   strumline 仍是勾选前的着色状态，勾上「禁用 RGB」看起来毫无效果。
			updateGrid();
			makeStrumNotes();
			// trace('CHECKED!');
		};

		//
		noteSkinInputText = new FlxUIInputText(10, 280, 150, _song.arrowSkin != null ? _song.arrowSkin : '', 8);
		blockPressWhileTypingOn.push(noteSkinInputText);

		noteSplashesInputText = new FlxUIInputText(noteSkinInputText.x, noteSkinInputText.y + 35, 150, _song.splashSkin != null ? _song.splashSkin : '', 8);
		blockPressWhileTypingOn.push(noteSplashesInputText);

		var reloadNotesButton:FlxButton = new FlxButton(noteSplashesInputText.x + 5, noteSplashesInputText.y + 20, 'Change Notes', function()
		{
			beginHistoryAction('history_edit_chart');
			_song.arrowSkin = noteSkinInputText.text;
			commitHistoryAction();
			updateGrid();
		});
		//
	}

	function disableAllOldUI():Void
	{
		// 不再需要 —— 旧 UI 体系已完全移除
	}

	function loadSong():Void
	{
		// ★ 重载音频 = 强制绕过声音缓存重新解码磁盘文件（否则改了 Inst/Voices 后点重载还是旧音频）
		Paths.forceReloadSounds = true;
		waveBytesCache.clear(); // ★ 音频换了，波形字节缓存全部作废
		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();

		if (vocals != null)
		{
			vocals.stop();
			vocals.destroy();
		}
		if (opponentVocals != null)
		{
			opponentVocals.stop();
			opponentVocals.destroy();
		}

		vocals = new FlxSound();
		opponentVocals = new FlxSound();
		try
		{
			var playerVocals = Paths.voices(currentSongName,
				(characterData.vocalsP1 == null || characterData.vocalsP1.length < 1) ? 'Player' : characterData.vocalsP1);
			if (playerVocals == null) playerVocals = Paths.voices(currentSongName);
			if (playerVocals != null)
			{
				vocals.loadEmbedded(playerVocals);
				FlxG.sound.list.add(vocals);
			}
		}
		vocals.autoDestroy = false;

		opponentVocals = new FlxSound();
		try
		{
			var oppVocals = Paths.voices(currentSongName,
				(characterData.vocalsP2 == null || characterData.vocalsP2.length < 1) ? 'Opponent' : characterData.vocalsP2);
			if (oppVocals != null)
			{
				opponentVocals.loadEmbedded(oppVocals);
				FlxG.sound.list.add(opponentVocals);
			}
		}
		opponentVocals.autoDestroy = false;

		generateSong();
		FlxG.sound.music.pause();
		Conductor.songPosition = sectionStartTime();
		FlxG.sound.music.time = Conductor.songPosition;

		var curTime:Float = 0;
		if (_song.notes.length <= 1) // First load ever
		{
			while (curTime < FlxG.sound.music.length)
			{
				addSection();
				curTime += (60 / _song.bpm) * 4000;
			}
		}
		Paths.forceReloadSounds = false;

		// ★ 换曲目 → minimap 强制重新初始化
		resetMinimapForNewSong();
	}

	var playtesting:Bool = false;
	var playtestingTime:Float = 0;
	var playtestingOnComplete:Void->Void = null;
	/** 我们挂在全局 persist 音轨 FlxG.sound.music 上的完成回调（闭包捕获 this，销毁时必须摘掉） */
	var musicOnComplete:Void->Void = null;

	/** 统一入口：挂到全局音乐上的回调必须留个引用，否则离开编辑器时闭包会把整个编辑器钉在内存里。 */
	inline function setMusicOnComplete(cb:Void->Void):Void
	{
		musicOnComplete = cb;
		FlxG.sound.music.onComplete = cb;
	}

	/** 只在"当前挂的还是我们那个回调"时摘除，避免误清其它状态的回调。 */
	function clearMusicOnComplete():Void
	{
		if (FlxG.sound != null && FlxG.sound.music != null && musicOnComplete != null
			&& FlxG.sound.music.onComplete == musicOnComplete)
			FlxG.sound.music.onComplete = null;
		musicOnComplete = null;
	}

	override function closeSubState()
	{
		if (playtesting)
		{
			// ★ 一次性恢复：ESC 试玩结束只恢复这一次，随后必须复位标志——
			//   否则之后任何 substate 关闭（粘贴/清除等确认 Prompt）都会再次把
			//   播放位置跳回 ESC 试玩前的时刻（表现为"粘贴完回到测试那个小节"）
			playtesting = false;
			FlxG.sound.music.pause();
			FlxG.sound.music.time = playtestingTime;
		setMusicOnComplete(playtestingOnComplete);
			if (instVolume != null)
				FlxG.sound.music.volume = instVolume.value;
			if (check_mute_inst != null && check_mute_inst.checked)
				FlxG.sound.music.volume = 0;

			if (vocals != null)
			{
				vocals.pause();
				vocals.time = playtestingTime;
				if (voicesVolume != null)
					vocals.volume = voicesVolume.value;
				if (check_mute_vocals != null && check_mute_vocals.checked)
					vocals.volume = 0;
			}

			if (opponentVocals != null)
			{
				opponentVocals.pause();
				opponentVocals.time = playtestingTime;
				if (voicesOppVolume != null)
					opponentVocals.volume = voicesOppVolume.value;
				if (check_mute_vocals_opponent != null && check_mute_vocals_opponent.checked)
					opponentVocals.volume = 0;
			}

			#if DISCORD_ALLOWED
			// Updating Discord Rich Presence
			DiscordClient.changePresence("Chart Editor", StringTools.replace(_song.song, '-', ' '));
			#end
		}
		removeVirtualPad();
		addVirtualPad(ChartingStateC, ChartingStateC);
		super.closeSubState();
	}

	function generateSong()
	{
		var instrumental = Paths.inst(currentSongName);
		if (instrumental != null)
			FlxG.sound.playMusic(instrumental, 0.6 /*, false*/);
		else if (FlxG.sound.music != null)
		{
			// A chart can still be edited when its Inst file is missing. Keep the
			// stopped menu track out of the chart timeline instead of loading null.
			FlxG.sound.music.stop();
			FlxG.sound.music.time = 0;
		}
		FlxG.sound.music.autoDestroy = false;
		if (instVolume != null)
			FlxG.sound.music.volume = instVolume.value;
		if (check_mute_inst != null && check_mute_inst.checked)
			FlxG.sound.music.volume = 0;

		setMusicOnComplete(function()
		{
			FlxG.sound.music.pause();
			Conductor.songPosition = 0;
			if (vocals != null)
			{
				vocals.pause();
				vocals.time = 0;
			}
			if (opponentVocals != null)
			{
				opponentVocals.pause();
				opponentVocals.time = 0;
			}
			changeSection();
			curSec = 0;
			updateGrid();
			updateSectionUI();
			if (vocals != null)
				vocals.play();
			if (opponentVocals != null)
				opponentVocals.play();
		});
	}

	function generateUI():Void
	{
		while (bullshitUI.members.length > 0)
		{
			bullshitUI.remove(bullshitUI.members[0], true);
		}

		// general shit
		var title:FlxText = new EditorText(UI_box.x + 20, UI_box.y + 20, 0);
		bullshitUI.add(title);
	}

	override function getEvent(id:String, sender:Dynamic, data:Dynamic, ?params:Array<Dynamic>)
	{
		var fieldKey:String = null;
		if (id == FlxUIInputText.CHANGE_EVENT)
		{
			var fields:Array<Dynamic> = [UI_songTitle, noteSplashesInputText, noteSkinInputText, gameOverCharacterInputText,
				gameOverSoundInputText, gameOverLoopInputText, gameOverEndInputText, value1InputText, value2InputText, strumTimeInputText];
			var fieldIndex = fields.indexOf(sender);
			if (fieldIndex >= 0) fieldKey = 'input_' + fieldIndex;
		}
		else if (id == FlxUINumericStepper.CHANGE_EVENT && (sender is FlxUINumericStepper))
			fieldKey = 'stepper_' + (cast sender:FlxUINumericStepper).name;
		beginHistoryAction('history_edit_chart', fieldKey);
		if (id == FlxUICheckBox.CLICK_EVENT)
		{
			var check:FlxUICheckBox = cast sender;
			var label = check.getLabel().text;
			switch (label)
			{
				case 'Must hit section':
					_song.notes[curSec].mustHitSection = check.checked;

					updateGrid();
					updateHeads();

				case 'GF section':
					_song.notes[curSec].gfSection = check.checked;

					updateGrid();
					updateHeads();

				case 'Change BPM':
					_song.notes[curSec].changeBPM = check.checked;
					FlxG.log.add('changed bpm shit');
				case "Alt Animation":
					_song.notes[curSec].altAnim = check.checked;
			}
		}
		else if (id == FlxUINumericStepper.CHANGE_EVENT && (sender is FlxUINumericStepper))
		{
			var nums:FlxUINumericStepper = cast sender;
			var wname = nums.name;
			// FlxG.log.add(wname);
			switch (wname)
			{
				case 'section_beats':
					_song.notes[curSec].sectionBeats = nums.value;
					reloadGridLayer();

				case 'song_speed':
					_song.speed = nums.value;

				case 'song_mania':
					// ★ UI 显示键数（4K=4），存内部 mania 要减一（4K=3）；阈值兜底防越界
					var maniaMinK:Int = 1;
					var maniaMaxK:Int = extraMaxKeys();
					nums.value = FlxMath.bound(nums.value, maniaMinK + 1, maniaMaxK + 1);
					_song.mania = Std.int(nums.value) - 1;
					updateKeyAmounts();
					reloadGridLayer();
					makeStrumNotes();

				case 'song_bpm':
					_song.bpm = nums.value;
					Conductor.mapBPMChanges(_song);
					Conductor.bpm = nums.value;
					stepperSusLength.stepSize = Math.ceil(Conductor.stepCrochet / 2);
					updateGrid();

				case 'note_susLength':
					if (curSelectedNote != null && curSelectedNote[2] != null)
					{
						curSelectedNote[2] = nums.value;
						updateGrid();
					}

				case 'section_bpm':
					_song.notes[curSec].bpm = nums.value;
					updateGrid();

				case 'inst_volume':
					FlxG.sound.music.volume = nums.value;
					if (check_mute_inst.checked)
						FlxG.sound.music.volume = 0;

				case 'voices_volume':
					vocals.volume = nums.value;
					if (check_mute_vocals.checked)
						vocals.volume = 0;

				case 'voices_opp_volume':
					opponentVocals.volume = nums.value;
					if (check_mute_vocals_opponent.checked)
						opponentVocals.volume = 0;
			}
		}
		else if (id == FlxUIInputText.CHANGE_EVENT && (sender is FlxUIInputText))
		{
			if (sender == UI_songTitle)
			{
				_song.song = UI_songTitle.text;
			}
			else if (sender == noteSplashesInputText)
			{
				_song.splashSkin = noteSplashesInputText.text;
			}
			else if (sender == noteSkinInputText)
			{
				_song.arrowSkin = noteSkinInputText.text;
			}
			else if (sender == gameOverCharacterInputText)
			{
				_song.gameOverChar = gameOverCharacterInputText.text;
			}
			else if (sender == gameOverSoundInputText)
			{
				_song.gameOverSound = gameOverSoundInputText.text;
			}
			else if (sender == gameOverLoopInputText)
			{
				_song.gameOverLoop = gameOverLoopInputText.text;
			}
			else if (sender == gameOverEndInputText)
			{
				_song.gameOverEnd = gameOverEndInputText.text;
			}
			else if (curSelectedNote != null)
			{
				// ★ 防御：只有事件 note（[1] 为数组）才能编辑 value1/value2；
				//   普通 note 的 [1] 是轨道号 Int，直接索引会空指针崩溃（事件菜单编辑值时触发）
				var evGroupX:Array<Dynamic> = Std.is(curSelectedNote[1], Array) ? cast curSelectedNote[1] : null;
				if (sender == value1InputText)
				{
					if (evGroupX != null && curEventSelected >= 0 && curEventSelected < evGroupX.length
						&& evGroupX[curEventSelected] != null && Std.is(evGroupX[curEventSelected], Array))
					{
						evGroupX[curEventSelected][1] = value1InputText.text;
						updateGrid();
					}
				}
				else if (sender == value2InputText)
				{
					if (evGroupX != null && curEventSelected >= 0 && curEventSelected < evGroupX.length
						&& evGroupX[curEventSelected] != null && Std.is(evGroupX[curEventSelected], Array))
					{
						evGroupX[curEventSelected][2] = value2InputText.text;
						updateGrid();
					}
				}
				else if (sender == strumTimeInputText)
				{
					var value:Null<Float> = EditorInputValidation.parseNumber(strumTimeInputText.text);
					if (value == null)
					{
						commitHistoryAction();
						return;
					}
					curSelectedNote[0] = value;
					updateGrid();
				}
			}
		}
		else if (id == FlxUISlider.CHANGE_EVENT && (sender is FlxUISlider))
		{
			switch (sender)
			{
				case 'playbackSpeed':
					playbackSpeed = #if FLX_PITCH Std.int(sliderRate.value) #else 1.0 #end;
			}
		}

		// FlxG.log.add(id + " WEED " + sender + " WEED " + data + " WEED " + params);
		commitHistoryAction();
	}

	var updatedSection:Bool = false;

	function sectionStartTime(add:Int = 0):Float
	{
		return sectionStartTimeAt(curSec + add);
	}

	// ==================== 全谱加载（09-26）====================
	// 网格/音符改成「整首歌一次渲染」的绝对坐标系：
	//   绝对 y = 前面所有小节的行数 × GRID_SIZE + 小节内局部 y。
	// 每个小节的行高 = beats*4*zoom（与旧 gridBG.height 同源），拍线/底色都按小节自身算。

	// ==================== 小节度量缓存（09-26 二轮 / 性能）====================
	// ★ 32787 音符的谱面有数千小节；原先 secRowStartPx/sectionStartTimeAt/secRowsAt 全部是
	//   O(n) 前缀累加，而它们每帧被调用多次（update / minimap / findSection…）→ O(n²) 掉帧。
	//   这里统一做成「一次重算 + O(1) 查表」，谱面结构/zoom 变化时置 metricsDirty 即可。
	var metricsDirty:Bool = true;
	var secRowsCache:Array<Int> = [];
	var secTopCache:Array<Float> = [];
	var secMsCache:Array<Float> = [];
	var secBpmCache:Array<Float> = [];
	var secStepMsCache:Array<Float> = [];
	var secLenCache:Array<Float> = [];
	var secNoteCountCache:Array<Int> = [];
	var eventsBySec:Array<Array<Dynamic>> = [];
	var totalRowsCache:Float = 0;
	var totalMsCache:Float = 0;
	/** ★ BF / Opp 各自的 note 总数（状态栏统计；按 mustHitSection 归属，事件音符不计） */
	var bfNoteTotal:Int = 0;
	var oppNoteTotal:Int = 0;

	function rebuildMetrics():Void
	{
		metricsDirty = false;
		secRowsCache = [];
		secTopCache = [];
		secMsCache = [];
		secBpmCache = [];
		secStepMsCache = [];
		secLenCache = [];
		secNoteCountCache = [];
		eventsBySec = [];
		totalRowsCache = 0;
		totalMsCache = 0;
		bfNoteTotal = 0;
		oppNoteTotal = 0;

		var n:Int = (_song == null || _song.notes == null) ? 0 : _song.notes.length;
		var daBPM:Float = (_song == null) ? 150 : _song.bpm;
		if (daBPM <= 0 || Math.isNaN(daBPM)) daBPM = 150;

		var top:Float = 0;
		var ms:Float = 0;
		for (i in 0...n)
		{
			var o:Dynamic = _song.notes[i];
			if (o != null && o.changeBPM && o.bpm != null && o.bpm > 0)
				daBPM = o.bpm;
			var beats:Float = getSectionBeats(i);
			if (beats <= 0 || Math.isNaN(beats)) beats = 4;
			var stepMs:Float = 1000 * 60 / daBPM / 4;
			var rows:Int = Std.int(Math.max(1, beats * 4 * zoomList[curZoom]));
			var len:Float = beats * 4 * stepMs;

			secRowsCache.push(rows);
			secTopCache.push(top);
			secMsCache.push(ms);
			secBpmCache.push(daBPM);
			secStepMsCache.push(stepMs);
			secLenCache.push(len);
			secNoteCountCache.push((o != null && o.sectionNotes != null) ? o.sectionNotes.length : 0);
			eventsBySec.push([]);

			// ★ BF / Opp note 计数（事件音符的 [1] 是数组，跳过）
			var sn:Array<Dynamic> = (o != null) ? o.sectionNotes : null;
			if (sn != null)
			{
				var mh:Bool = (o != null && o.mustHitSection != null) ? o.mustHitSection : true;
				for (k in sn)
				{
					if (k == null) continue;
					var laneDyn:Dynamic = k[1];
					if (!(Std.isOfType(laneDyn, Int) || Std.isOfType(laneDyn, Float))) continue;
					var ln:Int = Std.int(cast laneDyn);
					var isPlayer:Bool = dataLaneIsPlayer(ln, mh);
					if (isPlayer) bfNoteTotal++ else oppNoteTotal++;
				}
			}

			top += rows * GRID_SIZE;
			ms += len;
		}
		totalRowsCache = top;
		totalMsCache = ms;

		// ★ 事件按小节预分组（旧代码对每个小节全扫 _song.events = O(小节×事件)）
		if (_song != null && _song.events != null && n > 0)
		{
			for (e in _song.events)
			{
				if (e == null) continue;
				var s:Int = findSectionAtTime(e[0]);
				if (s >= 0 && s < n)
					eventsBySec[s].push(e);
			}
		}
	}

	inline function ensureMetrics():Void
	{
		if (metricsDirty)
			rebuildMetrics();
	}

	inline function secClamp(sec:Int):Int
	{
		var n:Int = secTopCache.length;
		if (n <= 0) return -1;
		if (sec < 0) return 0;
		if (sec >= n) return n - 1;
		return sec;
	}

	/** ★ 绝对小节起始时间（ms）：查缓存版（旧 O(n) 累加） */
	function sectionStartTimeAt(sec:Int):Float
	{
		ensureMetrics();
		var n:Int = secMsCache.length;
		if (n <= 0) return 0;
		if (sec <= 0) return 0;
		if (sec >= n) return totalMsCache;
		return secMsCache[sec];
	}

	/** ★ 第 sec 小节自己的 step 时长（ms）——按该小节生效的 BPM（查缓存版） */
	function sectionStepMsAt(sec:Int):Float
	{
		ensureMetrics();
		var i:Int = secClamp(sec);
		if (i < 0) return 1000 * 60 / 150 / 4;
		return secStepMsCache[i];
	}

	/** ★ 第 sec 小节的时长（ms） */
	function sectionLenMsAt(sec:Int):Float
	{
		ensureMetrics();
		var i:Int = secClamp(sec);
		if (i < 0) return 0;
		return secLenCache[i];
	}

	/** 第 sec 小节的行数（旧 gridBG.height / GRID_SIZE 的按小节版） */
	function secRowsAt(sec:Int):Int
	{
		ensureMetrics();
		if (sec < 0 || sec >= secRowsCache.length) return 1;
		return secRowsCache[sec];
	}

	/** 第 sec 小节顶部的绝对 y（px） */
	function secRowStartPx(sec:Int):Float
	{
		ensureMetrics();
		if (secTopCache.length <= 0) return 0;
		if (sec <= 0) return 0;
		if (sec >= secTopCache.length) return totalRowsCache;
		return secTopCache[sec];
	}

	/** 当前小节的像素高度（= 旧单小节 gridBG.height） */
	function curSecHeightPx():Float
	{
		return GRID_SIZE * secRowsAt(curSec);
	}

	/** 整首歌的总像素高度（minimap / 视口换算用） */
	function totalRowsPx():Float
	{
		ensureMetrics();
		return totalRowsCache;
	}

	/** Every note visible at the current zoom can be edited, regardless of section. */
	inline function noteEditableInViewport(spr:FlxSprite):Bool
	{
		return spr.y + spr.height >= FlxG.camera.scroll.y && spr.y <= FlxG.camera.scroll.y + FlxG.camera.height;
	}

	/** ★ 音符在网格里的「显示轨号」（0..totalKeys-1）：玩家(BF)侧恒在左半、对手恒在右半。
	 *  与 setupNoteData 的 dispLane 互逆，供点击/拖放/按键落点换算使用。 */
	inline function noteDisplayLane(note:Note):Int
	{
		var col:Int = note.noteData;
		if (col < 0) return -1;
		return note.mustPress ? (col % leftKeys) : (col % leftKeys) + leftKeys;
	}

	/** ★ 显示轨号 → 数据 lane（对手小节左右互换）。secMustHit = 该小节 mustHitSection */
	inline function displayLaneToData(dispLane:Int, secMustHit:Bool):Int
	{
		if (totalKeys <= 0) return 0;
		var v:Int = dispLane;
		if (v < 0) return -1;
		if (Song.chartEngineVersion != 'Pe-1.0.4' && !secMustHit) v = (v + leftKeys) % totalKeys;
		return v;
	}

	/** Match both gameplay readers: 1.0.4 lanes are absolute, older lanes are section-relative. */
	inline function dataLaneIsPlayer(lane:Int, secMustHit:Bool):Bool
	{
		return Song.chartEngineVersion == 'Pe-1.0.4' ? lane < leftKeys : (lane < leftKeys ? secMustHit : !secMustHit);
	}

	/** ★ 数据 lane → 网格显示轨号（与 setupNoteData 的 dispLane 同一算法） */
	inline function dataLaneToDisplay(lane:Int, secMustHit:Bool):Int
	{
		var col:Int = (leftKeys > 0) ? (lane % leftKeys) : 0;
		if (col < 0) col += leftKeys;
		var isPlayer:Bool = dataLaneIsPlayer(lane, secMustHit);
		return isPlayer ? col : col + leftKeys;
	}

	/** ★ 全曲绝对 y（px）→ 所在小节索引（二分，越出末尾返回最后一小节） */
	function findSectionAtY(worldY:Float):Int
	{
		ensureMetrics();
		var n:Int = secTopCache.length;
		if (n <= 0) return 0;
		if (worldY <= 0) return 0;
		var lo:Int = 0;
		var hi:Int = n - 1;
		while (lo < hi)
		{
			var mid:Int = (lo + hi + 1) >> 1;
			if (secTopCache[mid] <= worldY)
				lo = mid;
			else
				hi = mid - 1;
		}
		return lo;
	}

	/** ★ 全局时间（ms）→ 所在小节索引（二分，越出末尾返回最后一小节） */
	function findSectionAtTime(msTime:Float):Int
	{
		ensureMetrics();
		var n:Int = secMsCache.length;
		if (n <= 0) return 0;
		if (msTime <= 0) return 0;
		var lo:Int = 0;
		var hi:Int = n - 1;
		while (lo < hi)
		{
			var mid:Int = (lo + hi + 1) >> 1;
			if (secMsCache[mid] <= msTime)
				lo = mid;
			else
				hi = mid - 1;
		}
		return lo;
	}

	/** ★ 同步 Conductor.bpm 到「curSec 生效的 BPM」（全部 null 安全；static curSec 可能越界） */
	function syncConductorBPM():Void
	{
		var secObj:Dynamic = curSectionSafe();
		if (secObj != null && secObj.changeBPM && secObj.bpm > 0)
		{
			Conductor.bpm = secObj.bpm;
			return;
		}
		var daBPM:Float = _song.bpm;
		for (i in 0...curSec)
			if (_song.notes[i] != null && _song.notes[i].changeBPM)
				daBPM = _song.notes[i].bpm;
		Conductor.bpm = daBPM;
	}

	var lastConductorPos:Float;
	var colorSine:Float = 0;

	var noteMove:Bool = false;
	var nowMoveNote = null;

	override function update(elapsed:Float)
	{
		if (historyPanel != null && historyPanel.visible && FlxG.keys.justPressed.ESCAPE)
		{
			historyPanel.visible = false;
			super.update(elapsed);
			return;
		}
		// ★ 菜单打开时，跳过所有鼠标相关的 grid 操作（addNote/deleteNote/noteMove 等）
		var menuBarOpen:Bool = (menuBar != null && menuBar.activeMenu >= 0) || (historyPanel != null && historyPanel.visible);
		if (menuBarOpen)
		{
			// 不调任何 grid 鼠标逻辑，但其他业务（音乐时间、节拍）照常跑
		}

		// ★ 保险：curSec 是 static（跨实例残留）→ 每帧先钳制，避免任何裸访问越界
		clampCurSec();

		curStep = recalculateSteps();

		if (FlxG.sound.music.time < 0)
		{
			FlxG.sound.music.pause();
			FlxG.sound.music.time = 0;
		}
		else if (FlxG.sound.music.time > FlxG.sound.music.length)
		{
			FlxG.sound.music.pause();
			FlxG.sound.music.time = 0;
			changeSection();
		}
		Conductor.songPosition = FlxG.sound.music.time;
		_song.song = UI_songTitle.text;

		strumLineUpdateY();

		// ★ 播放条固定不动：先把相机硬同步到「白条 - 半屏」，再做窗口/图标/交互计算，
		//   否则它们会用到上一帧的 scroll（滞后一帧，滚动时会出现空白带）
		FlxG.mouse.visible = true; // cause reasons. trust me
		camPos.y = strumLine.y;
		// ★ 相机目标 = 网格中心：让整张网格在屏幕上水平居中（原来用 CAM_OFFSET=360 固定偏移会偏左）
		camPos.x = strumLine.x + GRID_SIZE * (totalKeys + 1) / 2;
		FlxG.camera.scroll.x = camPos.x - FlxG.width * 0.5;
		FlxG.camera.scroll.y = camPos.y - FlxG.height * 0.5;

		for (i in 0...totalKeys)
		{
			if (i >= strumLineNotes.length) break;
			strumLineNotes.members[i].y = strumLine.y;
		}
		// ★ Icon 跟随播放白条（用户要求）：BF/Opp 头像 + 摄像机图标贴着 strumLine 移动
		updateSideIconsFollow();

		// ★ 虚拟化渲染窗口：相机滚动后增量补建 / 回收小节的 sprite（每帧一次，边界没变则几乎零成本）
		refreshRenderWindow();

		if (!disableAutoScrolling.checked)
		{
			// ★ 播放跨小节（含 BF↔Opp 换边）不再 changeSection——旧流程会触发
			//   reloadGridLayer 整谱重建（几千个 sprite）+ 波形重画 = 雷霆大卡顿。
			//   全谱渲染后网格与 curSec 无关，这里只做「静默推进」：
			//   更新 curSec → 同步 BPM → 刷高亮/状态栏 → 波形重锚定。摄像机本来就跟随 strumLine。
			var totalEnd:Float = totalRowsPx();
			if (Math.ceil(strumLine.y) >= totalEnd)
			{
				// 播到曲末：照旧追加新小节（一次性成本，罕见）
				addSection();
				reloadGridLayer();
			}

			var targetSec:Int = findSectionAtY(strumLine.y);
			if (targetSec != curSec)
			{
				var prevSec:Int = curSec;
				curSec = targetSec;
				syncConductorBPM();
				refreshNoteHighlight();
				updateSectionUI();
				if (secRowStartPx(prevSec) != secRowStartPx(curSec))
					updateWaveform(); // 波形窗口跟随播放头（仅换小节时重画，位图很小）
			}
		}
		FlxG.watch.addQuick('daBeat', curBeat);
		FlxG.watch.addQuick('daStep', curStep);

		// ★ minimap：锚定/重绘/视口块/拖动跳转（要在 grid 交互之前跑，按住时优先吃掉指针）
		minimapUpdate();

		if (virtualPad.buttonS.justPressed || FlxG.keys.justPressed.L)
		{
			if (noteMove)
			{
				noteMove = false;
			}
			else
			{
				noteMove = true;
			}
		}

		if (controls.mobileC || FlxG.touches.list.length > 0)
		{
			for (touch in FlxG.touches.list)
			{
				// ★ 指针落在自定义移动按键 / minimap 上 → 该次触摸交给虚拟键，不处理网格
				var tPt = touch.getViewPosition(FlxG.camera, FlxPoint.get());
				var tOnMap:Bool = pointerOnMinimap(tPt.x, tPt.y);
				var tx = tPt.x;
				var ty = tPt.y;
				tPt.put();
				if (menuBarOpen || editorMobilePointerBlocked(tx, ty) || pointerOnOverlay(tx, ty) || tOnMap) continue;
				// ★ 视图坐标：相机随 strumLine 纵向滚动，屏幕坐标须加 camera.scroll 才是网格坐标
				//  （否则 y → 时间的换算会整体偏移 → 音符放到错误的时间）
				var wx:Float = tx + FlxG.camera.scroll.x;
				var wy:Float = ty + FlxG.camera.scroll.y;
				if (touch.pressed
					&& noteMove
					&& wx > gridBG.x
					&& wx < gridBG.x + gridBG.width
					&& wy > gridBG.y
					&& wy < gridBG.y + gridBG.height)
				{
					if (touch.overlaps(curRenderedNotes))
					{
						curRenderedNotes.forEachAlive(function(note:Note)
						{
							// ★ 全谱渲染：其它小节的音符不可拖动（只允许当前小节）
							if (touch.overlaps(note) && noteEditableInViewport(note))
							{
								if (nowMoveNote == null)
								{
									nowMoveNote = note;
									selectNote(note);
								}
							}
						});
						if (nowMoveNote != null) nowMoveNote.y = wy;
					}
				}
				if (touch.justReleased && noteMove)
				{
					if (nowMoveNote != null
						&& wx > gridBG.x
						&& wx < gridBG.x + gridBG.width
						&& wy > gridBG.y
						&& wy < gridBG.y + gridBG.height)
					{
						beginHistoryAction('history_edit_chart');
						// ★ 拖动落点：时间取 note 当前 y（绝对坐标）；
						//   轨号传「网格显示列号」（addNote 会换算回数据 lane）
						addNote(getStrumTime(nowMoveNote.y, false), noteDisplayLane(nowMoveNote));
						deleteNote(nowMoveNote);
						nowMoveNote = null;
						commitHistoryAction();
					}
				}
				if (touch.justReleased && !noteMove)
				{
					if (touch.overlaps(curRenderedNotes))
					{
						curRenderedNotes.forEachAlive(function(note:Note)
						{
							// ★ 全谱渲染：点击删除只作用于当前小节（其它小节原样保留）
							if (touch.overlaps(note) && noteEditableInViewport(note))
							{
								deleteNote(note);
							}
						});
					}
					else
					{
						if (wx > gridBG.x
							&& wx < gridBG.x + gridBG.width
							&& wy > gridBG.y
							&& wy < gridBG.y + gridBG.height)
						{
							FlxG.log.add('added note');
							var noteY = (FlxG.keys.pressed.SHIFT || virtualPad.buttonY.pressed) ? wy : Math.floor(wy / GRID_SIZE) * GRID_SIZE;
							addNote(getStrumTime(noteY, false), Math.floor((wx - getGridX() - GRID_SIZE) / GRID_SIZE));
						}
					}
				}

				if (wx > gridBG.x
					&& wx < gridBG.x + gridBG.width
					&& wy > gridBG.y
					&& wy < gridBG.y + gridBG.height)
				{
					dummyArrow.visible = true;
					dummyArrow.x = getGridX() + Math.floor((wx - getGridX()) / GRID_SIZE) * GRID_SIZE;
					if (FlxG.keys.pressed.SHIFT || virtualPad.buttonY.pressed)
						dummyArrow.y = wy;
					else
						dummyArrow.y = Math.floor(wy / GRID_SIZE) * GRID_SIZE;
				}
				else
				{
					dummyArrow.visible = false;
				}
			}
		}
		else
		{
			// ★ 菜单打开 / 指针落在自定义移动按键上时，整段 grid 鼠标操作跳过
			//   （noteMove / addNote / deleteNote / dummyArrow）
			if (!menuBarOpen && !editorMobilePointerBlocked(FlxG.mouse.viewX, FlxG.mouse.viewY) && !pointerOnOverlay(FlxG.mouse.viewX, FlxG.mouse.viewY)
				&& !pointerOnMinimap(FlxG.mouse.viewX, FlxG.mouse.viewY))
			{
			// ★ 鼠标用世界坐标（flixel 5.9.0 里 `FlxG.mouse.x/y` 已经 = getWorldPosition(cam)，
			//   含 camera.scroll；`viewX/Y` 只是屏幕坐标，跟 gridBG/getGridX 这些世界坐标混用
			//   会让高光方格相对鼠标固定偏移 camPos.x，滚轮改变 scroll.y 时偏移跟着变 → 视觉/交互错位）
			//   grid 网格坐标 = world 坐标；下面所有 mvx/mvy 都按世界坐标参与列号/行号换算。
			var mvx:Float = FlxG.mouse.x;
			var mvy:Float = FlxG.mouse.y;
			if (FlxG.mouse.pressedRight
				&& mvx > gridBG.x
				&& mvx < gridBG.x + gridBG.width
				&& mvy > gridBG.y
				&& mvy < gridBG.y + gridBG.height)
			{
				noteMove = true;
				if (FlxG.mouse.overlaps(curRenderedNotes))
				{
					curRenderedNotes.forEachAlive(function(note:Note)
					{
						// ★ 全谱渲染：右键拖动只对当前小节音符生效
						if (FlxG.mouse.overlaps(note) && noteEditableInViewport(note))
						{
							if (nowMoveNote == null)
							{
								nowMoveNote = note;
								selectNote(note);
							}
						}
					});
					if (nowMoveNote != null) nowMoveNote.y = mvy;
				}
			}
			if (FlxG.mouse.justReleasedRight)
			{
				noteMove = false;
				if (nowMoveNote != null
					&& mvx > gridBG.x
					&& mvx < gridBG.x + gridBG.width
					&& mvy > gridBG.y
					&& mvy < gridBG.y + gridBG.height)
				{
					beginHistoryAction('history_edit_chart');
					// ★ 拖动落点：时间取 note 当前 y（绝对坐标）；
					//   轨号传「网格显示列号」（addNote 会换算回数据 lane）
					addNote(getStrumTime(nowMoveNote.y, false), noteDisplayLane(nowMoveNote));
					deleteNote(nowMoveNote);
					nowMoveNote = null;
					commitHistoryAction();
				}
			}

			// ★ 菜单栏下拉打开时已在外层 if (!menuBarOpen) 跳过整段
			if (FlxG.mouse.justPressed && !noteMove)
			{
				if (FlxG.mouse.overlaps(curRenderedNotes))
				{
					curRenderedNotes.forEachAlive(function(note:Note)
					{
						// ★ 全谱渲染：其它小节的音符不可选中/删除（避免跨小节误删）
						if (!noteEditableInViewport(note)) return;
						if (FlxG.mouse.overlaps(note))
						{
							// ★ 自定义移动键位模式（EditorMobileKeys）下忽略 Ctrl/Alt 点击修饰：
							//   虚拟修饰键可能残留/组合触发，会让"点击删除"变成选择 → 点击事件像被消除
							var useMods:Bool = FlxG.keys.pressed.CONTROL || FlxG.keys.pressed.ALT;
							if (useMods && FlxG.keys.pressed.CONTROL)
							{
								selectNote(note);
							}
							else if (useMods && FlxG.keys.pressed.ALT)
							{
								beginHistoryAction('history_edit_chart');
								selectNote(note);
								curSelectedNote[3] = curNoteTypes[currentType];
								updateGrid();
								commitHistoryAction();
							}
							else
							{
								// trace('tryin to delete note...');
								deleteNote(note);
							}
						}
					});
				}
				else
				{
					if (mvx > gridBG.x
						&& mvx < gridBG.x + gridBG.width
						&& mvy > gridBG.y
						&& mvy < gridBG.y + gridBG.height)
					{
						FlxG.log.add('added note');
						var noteY = FlxG.keys.pressed.SHIFT ? mvy : Math.floor(mvy / GRID_SIZE) * GRID_SIZE;
						addNote(getStrumTime(noteY, false), Math.floor((mvx - getGridX() - GRID_SIZE) / GRID_SIZE));
					}
				}
			}

			if (mvx > gridBG.x
				&& mvx < gridBG.x + gridBG.width
				&& mvy > gridBG.y
				&& mvy < gridBG.y + gridBG.height)
			{
				dummyArrow.visible = true;
				dummyArrow.x = getGridX() + Math.floor((mvx - getGridX()) / GRID_SIZE) * GRID_SIZE;
				if (FlxG.keys.pressed.SHIFT)
					dummyArrow.y = mvy;
				else
					dummyArrow.y = Math.floor(mvy / GRID_SIZE) * GRID_SIZE;
			}
			else
			{
				dummyArrow.visible = false;
			}
			} // end if (!menuBarOpen)
		}

		var blockInput:Bool = false;
		for (inputText in blockPressWhileTypingOn)
		{
			if (inputText.hasFocus)
			{
				ClientPrefs.toggleVolumeKeys(false);
				blockInput = true;
				break;
			}
		}

		if (!blockInput)
		{
			for (stepper in blockPressWhileTypingOnStepper)
			{
				@:privateAccess
				var leText:FlxUIInputText = cast(stepper.text_field, FlxUIInputText);
				if (leText.hasFocus)
				{
					ClientPrefs.toggleVolumeKeys(false);
					blockInput = true;
					break;
				}
			}
		}

		if (!blockInput)
		{
			ClientPrefs.toggleVolumeKeys(true);
			for (dropDownMenu in blockPressWhileScrolling)
			{
				if (dropDownMenu.dropPanel.visible)
				{
					blockInput = true;
					break;
				}
			}
		}

		if (!blockInput)
		{
			// ================= 全局快捷键（F1~F8 开菜单；其余在菜单打开时禁用） =================
			var menuOpen:Bool = (menuBar != null && menuBar.activeMenu >= 0);
			if (FlxG.keys.justPressed.F1) menuBar.openMenu(0);
			else if (FlxG.keys.justPressed.F2) menuBar.openMenu(1);
			else if (FlxG.keys.justPressed.F3 && !FlxG.keys.pressed.CONTROL) menuBar.openMenu(2);
			else if (FlxG.keys.justPressed.F4) menuBar.openMenu(3);
			else if (FlxG.keys.justPressed.F5) menuBar.openMenu(4);
			else if (FlxG.keys.justPressed.F6) menuBar.openMenu(5);
			else if (FlxG.keys.justPressed.F7) menuBar.openMenu(6);
			else if (FlxG.keys.justPressed.F8) menuBar.openMenu(7);
			else if (!menuOpen)
			{
				var ctrlHeld:Bool = FlxG.keys.pressed.CONTROL;
				var shiftHeld:Bool = FlxG.keys.pressed.SHIFT;
				var altHeld:Bool = FlxG.keys.pressed.ALT;

				// Shift+Del = 清空事件 / Ctrl+Del = 清空 Note（FlxKey 不区分左右，任意侧修饰键均可）
				if (FlxG.keys.justPressed.DELETE)
				{
					if (shiftHeld) { handleMenuAction('clear_events'); }
					else if (ctrlHeld) { handleMenuAction('clear_notes'); }
				}

				// Ctrl+Shift 组合：重载/载入/保存事件系列 + Vortex + 打击音
				if (ctrlHeld && shiftHeld && !altHeld)
				{
					if (FlxG.keys.justPressed.Z) redo();
					else if (FlxG.keys.justPressed.Q) handleMenuAction('reload_audio');
					else if (FlxG.keys.justPressed.W) handleMenuAction('reload_json');
					else if (FlxG.keys.justPressed.E) handleMenuAction('load_autosave');
					else if (FlxG.keys.justPressed.R) handleMenuAction('load_events');
					else if (FlxG.keys.justPressed.S) handleMenuAction('save_events');
					else if (FlxG.keys.justPressed.TAB) toggleVortexShortcut();
					else if (FlxG.keys.justPressed.U) toggleSfxShortcut('bf');
					else if (FlxG.keys.justPressed.O) toggleSfxShortcut('opp');
				}

				// Alt+Ctrl+U/I/O = 静音 BF / Inst / Opp；Alt+U/I/O = 波形图 BF / Inst / Opp
				if (altHeld && ctrlHeld && !shiftHeld)
				{
					if (FlxG.keys.justPressed.U) toggleMuteShortcut('bf');
					else if (FlxG.keys.justPressed.I) toggleMuteShortcut('inst');
					else if (FlxG.keys.justPressed.O) toggleMuteShortcut('opp');
				}
				if (altHeld && !ctrlHeld && !shiftHeld)
				{
					if (FlxG.keys.justPressed.U) toggleWaveformShortcut('bf');
					else if (FlxG.keys.justPressed.I) toggleWaveformShortcut('inst');
					else if (FlxG.keys.justPressed.O) toggleWaveformShortcut('opp');
				}

				// Ctrl 组合：U/I/O = 交换/二重奏/镜像；C/V = 复制/粘贴小节；S = 保存；Z = 撤销（下方原有）
				if (ctrlHeld && !shiftHeld && !altHeld)
				{
					if (FlxG.keys.justPressed.Y) redo();
					else if (FlxG.keys.justPressed.U) swapSectionSides();
					else if (FlxG.keys.justPressed.I) duetCurrentSection();
					else if (FlxG.keys.justPressed.O) mirrorCurrentSection();
					else if (FlxG.keys.justPressed.C) copyCurrentSection();
					else if (FlxG.keys.justPressed.V) pasteToCurrentSection();
					else if (FlxG.keys.justPressed.S) handleMenuAction('save');
				}

				// 单键：U = 玩家小节 / I = GF 小节 / O = Opponents 小节（★ 切换后立即刷新背景/波形归属）
				if (!ctrlHeld && !shiftHeld && !altHeld)
				{
					if (FlxG.keys.justPressed.U)
					{
						beginHistoryAction('history_edit_chart');
						_song.notes[curSec].mustHitSection = true;
						check_mustHitSection.checked = true;
						updateHeads();
						reloadGridLayer();
						commitHistoryAction();
					}
					else if (FlxG.keys.justPressed.I)
					{
						beginHistoryAction('history_edit_chart');
						_song.notes[curSec].gfSection = !_song.notes[curSec].gfSection;
						check_gfSection.checked = _song.notes[curSec].gfSection;
						updateGrid();
						updateHeads();
						commitHistoryAction();
					}
					else if (FlxG.keys.justPressed.O)
					{
						beginHistoryAction('history_edit_chart');
						_song.notes[curSec].mustHitSection = false;
						check_mustHitSection.checked = false;
						updateHeads();
						reloadGridLayer();
						commitHistoryAction();
					}
				}

				// 按住 K + 数字键 = 设置 Mania（`=1K、1=2K … 9=10K）
				if (FlxG.keys.pressed.K && !ctrlHeld && !shiftHeld && !altHeld)
				{
					if (FlxG.keys.justPressed.GRAVEACCENT) setManiaByKey(1);
					else if (FlxG.keys.justPressed.ONE) setManiaByKey(2);
					else if (FlxG.keys.justPressed.TWO) setManiaByKey(3);
					else if (FlxG.keys.justPressed.THREE) setManiaByKey(4);
					else if (FlxG.keys.justPressed.FOUR) setManiaByKey(5);
					else if (FlxG.keys.justPressed.FIVE) setManiaByKey(6);
					else if (FlxG.keys.justPressed.SIX) setManiaByKey(7);
					else if (FlxG.keys.justPressed.SEVEN) setManiaByKey(8);
					else if (FlxG.keys.justPressed.EIGHT) setManiaByKey(9);
					else if (FlxG.keys.justPressed.NINE) setManiaByKey(10);
				}
			}
			// ================= 快捷键结束 =================

			if (FlxG.keys.justPressed.ESCAPE || virtualPad.buttonC.justPressed)
			{
				startPlaytest();
			}
			else if (FlxG.keys.justPressed.ENTER || virtualPad.buttonA.justPressed)
			{
				startNormalPlay();
			}

			if (curSelectedNote != null && curSelectedNote[1] > -1)
			{
				if (FlxG.keys.justPressed.E || virtualPad.buttonE.justPressed)
				{
					changeNoteSustain(Conductor.stepCrochet);
				}
				if (FlxG.keys.justPressed.Q || virtualPad.buttonP.justPressed)
				{
					changeNoteSustain(-Conductor.stepCrochet);
				}
			}

			if (FlxG.keys.justPressed.BACKSPACE || virtualPad.buttonB.justPressed)
			{
				doExitEditor();
				return;
			}

			if (virtualPad.buttonV.justPressed || FlxG.keys.justPressed.Z && FlxG.keys.pressed.CONTROL && !FlxG.keys.pressed.SHIFT)
			{
				undo();
			}

			// ★ Z/X 缩放：桌面与虚拟按键统一带边界守卫（原来桌面分支无守卫，
			//   在最小档再按 Z 会把 curZoom 减成 -1 → zoomList[-1] 越界 → 崩溃）
			if ((FlxG.keys.justPressed.Z || virtualPad.buttonZ.justPressed) && curZoom > 0 && !FlxG.keys.pressed.CONTROL)
			{
				--curZoom;
				updateZoom();
			}
			if ((FlxG.keys.justPressed.X || virtualPad.buttonD.justPressed) && curZoom < zoomList.length - 1)
			{
				curZoom++;
				updateZoom();
			}

			if (FlxG.keys.justPressed.TAB || virtualPad.buttonG.justPressed)
			{
				// 如果新菜单系统正在显示下拉菜单，拦截 TAB 键（防止切换旧 tab）
				if (menuBar != null && menuBar.activeMenu >= 0)
				{
					// 不做任何事，让 TAB 给下拉菜单里的 widget 使用
				}
				else
				{
					if (FlxG.keys.pressed.SHIFT)
					{
						UI_box.selected_tab -= 1;
						if (UI_box.selected_tab < 0)
							UI_box.selected_tab = 5;
					}
					else
					{
						UI_box.selected_tab += 1;
						if (UI_box.selected_tab > 5)
							UI_box.selected_tab = 0;
					}
				}
			}

			if (FlxG.keys.justPressed.SPACE || virtualPad.buttonX.justPressed)
			{
				if (vocals != null)
					vocals.play();
				if (opponentVocals != null)
					opponentVocals.play();
				pauseAndSetVocalsTime();
				if (!FlxG.sound.music.playing)
				{
					FlxG.sound.music.play();
					if (vocals != null)
						vocals.play();
					if (opponentVocals != null)
						opponentVocals.play();
				}
				else
					FlxG.sound.music.pause();
			}

			if (!FlxG.keys.pressed.ALT && FlxG.keys.justPressed.R)
			{
				if (FlxG.keys.pressed.SHIFT)
					resetSection(true);
				else
					resetSection();
			}

			// ★ 菜单（含下拉列表）打开时滚轮归菜单用，不再滚动谱面时间
			if (!controls.mobileC && !(menuBar != null && menuBar.activeMenu >= 0) && !(historyPanel != null && historyPanel.visible))
			{
				if (FlxG.mouse.wheel != 0)
				{
					FlxG.sound.music.pause();
					if (!mouseQuant)
						FlxG.sound.music.time -= (FlxG.mouse.wheel * Conductor.stepCrochet * 0.8);
					else
					{
						var time:Float = FlxG.sound.music.time;
						var beat:Float = curDecBeat;
						var snap:Float = quantization / 4;
						var increase:Float = 1 / snap;
						if (FlxG.mouse.wheel > 0)
						{
							var fuck:Float = CoolUtil.quantize(beat, snap) - increase;
							FlxG.sound.music.time = Conductor.beatToSeconds(fuck);
						}
						else
						{
							var fuck:Float = CoolUtil.quantize(beat, snap) + increase;
							FlxG.sound.music.time = Conductor.beatToSeconds(fuck);
						}
					}
					pauseAndSetVocalsTime();
				}
			}

			// ARROW VORTEX SHIT NO DEADASS

			// Vertical time scroll: W/S (desktop) or pad up/down (mobile)
			var vertUp = controls.mobileC ? virtualPad.buttonUp.pressed : FlxG.keys.pressed.W;
			var vertDown = controls.mobileC ? virtualPad.buttonDown.pressed : FlxG.keys.pressed.S;
			if (vertUp || vertDown)
			{
				FlxG.sound.music.pause();

				var holdingShift:Float = 1;
				if (FlxG.keys.pressed.CONTROL && !controls.mobileC)
					holdingShift = 0.25;
				else if (FlxG.keys.pressed.SHIFT || virtualPad.buttonY.pressed)
					holdingShift = 4;

				var daTime:Float = 700 * FlxG.elapsed * holdingShift;

				FlxG.sound.music.time += daTime * (vertUp ? -1 : 1);

				pauseAndSetVocalsTime();
			}

			if (!vortex)
			{
				if (FlxG.keys.justPressed.UP || FlxG.keys.justPressed.DOWN)
				{
					FlxG.sound.music.pause();
					updateCurStep();
					var time:Float = FlxG.sound.music.time;
					var beat:Float = curDecBeat;
					var snap:Float = quantization / 4;
					var increase:Float = 1 / snap;
					if (FlxG.keys.pressed.UP)
					{
						var fuck:Float = CoolUtil.quantize(beat, snap) - increase; // (Math.floor((beat+snap) / snap) * snap);
						FlxG.sound.music.time = Conductor.beatToSeconds(fuck);
					}
					else
					{
						var fuck:Float = CoolUtil.quantize(beat, snap) + increase; // (Math.floor((beat+snap) / snap) * snap);
						FlxG.sound.music.time = Conductor.beatToSeconds(fuck);
					}
				}
			}

			var style = currentType;

			if (FlxG.keys.pressed.SHIFT || virtualPad.buttonY.pressed)
			{
				style = 3;
			}

			var conductorTime = Conductor.songPosition; // + sectionStartTime();Conductor.songPosition / Conductor.stepCrochet;

			// AWW YOU MADE IT SEXY <3333 THX SHADMAR

			if (!blockInput)
			{
				if (FlxG.keys.justPressed.RIGHT && !FlxG.keys.pressed.CONTROL)
				{
					curQuant++;
					if (curQuant > quantizations.length - 1)
						curQuant = 0;

					quantization = quantizations[curQuant];
				}

				if (FlxG.keys.justPressed.LEFT && !FlxG.keys.pressed.CONTROL)
				{
					curQuant--;
					if (curQuant < 0)
						curQuant = quantizations.length - 1;

					quantization = quantizations[curQuant];
				}
				quant.animation.play('q', true, false, curQuant);
			}
			if (vortex && !blockInput)
			{
				var controlArray:Array<Bool> = [
					 FlxG.keys.justPressed.ONE, FlxG.keys.justPressed.TWO, FlxG.keys.justPressed.THREE, FlxG.keys.justPressed.FOUR,
					FlxG.keys.justPressed.FIVE, FlxG.keys.justPressed.SIX, FlxG.keys.justPressed.SEVEN, FlxG.keys.justPressed.EIGHT
				];

				if (controlArray.contains(true))
				{
					for (i in 0...controlArray.length)
					{
						if (controlArray[i])
							doANoteThing(conductorTime, i, style);
					}
				}

				var feces:Float;
				if (FlxG.keys.justPressed.UP || FlxG.keys.justPressed.DOWN)
				{
					FlxG.sound.music.pause();

					updateCurStep();
					// FlxG.sound.music.time = (Math.round(curStep/quants[curQuant])*quants[curQuant]) * Conductor.stepCrochet;

					// (Math.floor((curStep+quants[curQuant]*1.5/(quants[curQuant]/2))/quants[curQuant])*quants[curQuant]) * Conductor.stepCrochet;//snap into quantization
					var time:Float = FlxG.sound.music.time;
					var beat:Float = curDecBeat;
					var snap:Float = quantization / 4;
					var increase:Float = 1 / snap;
					if (FlxG.keys.pressed.UP)
					{
						var fuck:Float = CoolUtil.quantize(beat, snap) - increase;
						feces = Conductor.beatToSeconds(fuck);
					}
					else
					{
						var fuck:Float = CoolUtil.quantize(beat, snap) + increase; // (Math.floor((beat+snap) / snap) * snap);
						feces = Conductor.beatToSeconds(fuck);
					}
					FlxTween.tween(FlxG.sound.music, {time: feces}, 0.1, {ease: FlxEase.circOut});
					pauseAndSetVocalsTime();

					var dastrum = 0;

					if (curSelectedNote != null)
					{
						dastrum = curSelectedNote[0];
					}

					var secStart:Float = sectionStartTime();
					var datime = (feces - secStart) - (dastrum - secStart); // idk math find out why it doesn't work on any other section other than 0
					if (curSelectedNote != null)
					{
						var controlArray:Array<Bool> = [
							 FlxG.keys.pressed.ONE, FlxG.keys.pressed.TWO, FlxG.keys.pressed.THREE, FlxG.keys.pressed.FOUR,
							FlxG.keys.pressed.FIVE, FlxG.keys.pressed.SIX, FlxG.keys.pressed.SEVEN, FlxG.keys.pressed.EIGHT
						];

						if (controlArray.contains(true))
						{
							beginHistoryAction('history_change_sustain');
							for (i in 0...controlArray.length)
							{
								if (controlArray[i])
									if (curSelectedNote[1] == i)
										curSelectedNote[2] += datime - curSelectedNote[2] - Conductor.stepCrochet;
							}
							updateGrid();
							updateNoteUI();
							commitHistoryAction();
						}
					}
				}
			}
			var shiftThing:Int = 1;
			// ★ Alt = ×10 小节、Shift = ×4、默认 ×1
			if (FlxG.keys.pressed.ALT)
				shiftThing = 10;
			else if (FlxG.keys.pressed.SHIFT || virtualPad.buttonY.pressed)
				shiftThing = 4;

			if (FlxG.keys.justPressed.D || virtualPad.buttonRight.justPressed)
				changeSection(curSec + shiftThing);
			if (FlxG.keys.justPressed.A || virtualPad.buttonLeft.justPressed)
			{
				if (curSec <= 0)
				{
					changeSection(_song.notes.length - 1);
				}
				else
				{
					changeSection(curSec - shiftThing);
				}
			}
		}
		else if (FlxG.keys.justPressed.ENTER)
		{
			for (i in 0...blockPressWhileTypingOn.length)
			{
				if (blockPressWhileTypingOn[i].hasFocus)
				{
					blockPressWhileTypingOn[i].hasFocus = false;
				}
			}
		}

		strumLineNotes.visible = quant.visible = vortex;

		if (FlxG.sound.music.time < 0)
		{
			FlxG.sound.music.pause();
			FlxG.sound.music.time = 0;
		}
		else if (FlxG.sound.music.time > FlxG.sound.music.length)
		{
			FlxG.sound.music.pause();
			FlxG.sound.music.time = 0;
			changeSection();
		}
		Conductor.songPosition = FlxG.sound.music.time;
		strumLineUpdateY();
		camPos.y = strumLine.y;
		// ★ 相机目标 = 网格中心（保持屏幕水平居中）
		camPos.x = strumLine.x + GRID_SIZE * (totalKeys + 1) / 2;
		// ★ 播放条固定不动：相机硬同步（同 update 前半段）
		FlxG.camera.scroll.x = camPos.x - FlxG.width * 0.5;
		FlxG.camera.scroll.y = camPos.y - FlxG.height * 0.5;
		for (i in 0...totalKeys)
		{
			strumLineNotes.members[i].y = strumLine.y;
			strumLineNotes.members[i].alpha = FlxG.sound.music.playing ? 1 : 0.35;
		}
		updateWaveform(false);

		#if FLX_PITCH
		// PLAYBACK SPEED CONTROLS //
		var holdingShift = FlxG.keys.pressed.SHIFT;
		var holdingLB = FlxG.keys.pressed.LBRACKET;
		var holdingRB = FlxG.keys.pressed.RBRACKET;
		var pressedLB = FlxG.keys.justPressed.LBRACKET;
		var pressedRB = FlxG.keys.justPressed.RBRACKET;

		if (!holdingShift && pressedLB || holdingShift && holdingLB)
			playbackSpeed -= 0.01;
		if (!holdingShift && pressedRB || holdingShift && holdingRB)
			playbackSpeed += 0.01;
		if (FlxG.keys.pressed.ALT && (pressedLB || pressedRB || holdingLB || holdingRB) || virtualPad.buttonV.pressed)
			playbackSpeed = 1;
		//

		if (playbackSpeed <= 0.5)
			playbackSpeed = 0.5;
		if (playbackSpeed >= 3)
			playbackSpeed = 3;

		FlxG.sound.music.pitch = playbackSpeed;
		vocals.pitch = playbackSpeed;
		opponentVocals.pitch = playbackSpeed;
		#end

		var curTimeSec:Float = FlxMath.roundDecimal(Conductor.songPosition / 1000, 2);
		var totalTimeSec:Float = FlxMath.roundDecimal(FlxG.sound.music.length / 1000, 2);

		// 同步到新顶栏状态栏（原生 bpmTxt 已隐藏，不再逐帧拼字符串）
		if (menuBar != null && menuBar.statusBar != null)
		{
			// ★ 秒数恒保留两位小数（尾数 0 也保留）：0 → "0.00"、1.5 → "1.50"
			menuBar.statusBar.setTempo(fmt2(curTimeSec) + 's / ' + fmt2(totalTimeSec) + 's');
			menuBar.statusBar.setClock(FlxStringUtil.formatTime(curTimeSec) + ' / ' + FlxStringUtil.formatTime(totalTimeSec));
			menuBar.statusBar.setSection(Std.string(curSec));
			menuBar.statusBar.setBeat(Std.string(curDecBeat).substring(0, 4));
			var snapSuffix = if ((quantization - 2) % 10 == 0 && quantization != 12) "nd"; else "th";
			menuBar.statusBar.setSnap(Std.string(quantization) + snapSuffix);
			menuBar.statusBar.setMove(Std.string(noteMove));
		}

		var playedSound:Array<Bool> = []; // Prevents ouchy GF sex sounds
		for (i in 0...totalKeys)
			playedSound.push(false);

		// ★ 安全取「当前小节 mustHitSection」（curSec 是 static，绝不裸访问）
		var curMustHit:Bool = true;
		var csObj:Dynamic = curSectionSafe();
		if (csObj != null && csObj.mustHitSection != null)
			curMustHit = csObj.mustHitSection;

		curRenderedNotes.forEachAlive(function(note:Note)
		{
			// ★ 半透明预览：其它小节 0.6、当前小节 1（窗口化后渲染量小，这里每帧重设无害）
			note.alpha = noteEditableInViewport(note) ? 1 : 0.6;
			if (curSelectedNote != null)
			{
				var noteDataToCheck:Int = note.noteData;
				var owner = noteSourceSection(note);
				var sourceMustHit = owner >= 0 && owner < _song.notes.length ? _song.notes[owner].mustHitSection : curMustHit;
				if (noteDataToCheck > -1)
					noteDataToCheck = displayLaneToData(noteDisplayLane(note), sourceMustHit);

				if (curSelectedNote[0] == note.strumTime
					&& ((curSelectedNote[2] == null && noteDataToCheck < 0)
						|| (curSelectedNote[2] != null && curSelectedNote[1] == noteDataToCheck)))
				{
					colorSine += elapsed;
					var colorVal:Float = 0.7 + Math.sin(Math.PI * colorSine) * 0.3;
					note.color = FlxColor.fromRGBFloat(colorVal, colorVal, colorVal,
						0.999); // Alpha can't be 100% or the color won't be updated for some reason, guess i will die
				}
			}

			if (note.strumTime <= Conductor.songPosition)
			{
				note.alpha = 0.4;
				if (note.strumTime > lastConductorPos && FlxG.sound.music.playing && note.noteData > -1)
				{
					var data:Int = note.noteData % leftKeys;
					// ★ strumLineNotes 的成员顺序 = 网格显示顺序 → 用「显示轨号」（对手小节与数据 lane 互换）
					var noteDataToCheck:Int = noteDisplayLane(note);
					// ★ 索引守护：mania 切换 / 损坏谱面下 noteData 可能越界（cpp 下直接崩）
					if (noteDataToCheck >= 0 && noteDataToCheck < strumLineNotes.length)
					{
						strumLineNotes.members[noteDataToCheck].playAnim('confirm', true);
						strumLineNotes.members[noteDataToCheck].resetAnim = ((note.sustainLength / 1000) + 0.15) / playbackSpeed;
					}
					if (!playedSound[data])
					{
						if (note.hitsoundChartEditor
							&& ((playSoundBf.checked && note.mustPress) || (playSoundDad.checked && !note.mustPress)))
						{
							var soundToPlay = note.hitsound;
							if (_song.player1 == 'gf') // Easter egg
								soundToPlay = 'GF_' + Std.string(data + 1);

							FlxG.sound.play(Paths.sound(soundToPlay)).pan = note.noteData < leftKeys ? -0.3 : 0.3; // would be coolio
							playedSound[data] = true;
						}

						data = note.noteData;
						if (note.mustPress != curMustHit)
						{
							data += leftKeys;
						}
					}
				}
			}
		});

		if (metronome.checked && lastConductorPos != Conductor.songPosition)
		{
			var metroInterval:Float = 60 / metronomeStepper.value;
			var metroStep:Int = Math.floor(((Conductor.songPosition + metronomeOffsetStepper.value) / metroInterval) / 1000);
			var lastMetroStep:Int = Math.floor(((lastConductorPos + metronomeOffsetStepper.value) / metroInterval) / 1000);
			if (metroStep != lastMetroStep)
			{
				FlxG.sound.play(Paths.sound('Metronome_Tick'));
				// trace('Ticked');
			}
		}
		lastConductorPos = Conductor.songPosition;
		super.update(elapsed);
	}

	function pauseAndSetVocalsTime()
	{
		if (vocals != null)
		{
			vocals.pause();
			vocals.time = FlxG.sound.music.time;
		}

		if (opponentVocals != null)
		{
			opponentVocals.pause();
			opponentVocals.time = FlxG.sound.music.time;
		}
	}

	/** 秒数格式化：恒保留两位小数（0 → "0.00"、1.5 → "1.50"） */
	function fmt2(v:Float):String
	{
		var neg:Bool = v < 0;
		if (neg) v = -v;
		var whole:Int = Math.floor(v);
		var frac:Int = Math.round((v - whole) * 100);
		if (frac >= 100) { frac -= 100; whole++; }
		var s:String = Std.string(whole) + '.' + (frac < 10 ? '0' : '') + Std.string(frac);
		return neg ? '-' + s : s;
	}

	/** ★ 自定义移动按键 overlay 是否命中了 (mx,my)（逻辑屏幕坐标）——
	 *  命中 = 该指针是点在虚拟键上，网格点击应跳过（避免放/删音符与虚拟键操作互相干扰） */
	function pointerOnOverlay(mx:Float, my:Float):Bool
	{
		var ov:Dynamic = editorMobileOverlay;
		if (ov == null) return false;
		try
		{
			if (ov.visible != true || ov.active != true) return false;
			return ov.hitTest(mx, my) == true;
		}
		catch (e:Dynamic) {}
		return false;
	}

	// ==================== Note 密度缩略图（minimap，09-26）====================
	// 仿 Grafex charter：竖条缩略图统计全曲 note 分布；视口块可拖动 → 快速跳转到对应位置。
	// 位置锚定在移动工具「LEFT」按钮上方（找不到该按钮时放屏幕左下角）。

	// ==================== Note 密度缩略图（minimap）====================
	// ★ 09-26 二轮（用户要求）：
	//   1) 位置固定：顶栏状态栏（「缩放 1/1 | …」那一行）正下方，高度延伸到距屏幕底部 220px；
	//   2) 二级菜单展开时 minimap 不参与交互（菜单独享指针）；
	//   3) 换曲目 / 换难度后强制重建画布并重画（否则残留上一首的分布图 → note 看着"只占一点点"）；
	//   4) 重画节流 —— 32787 note 的谱面不能每次编辑都全量重绘。
	var minimapBG:FlxSprite;
	var minimapCanvas:FlxSprite;
	var minimapViewport:FlxSprite;
	var minimapTitle:FlxText;
	/** ★ 事件列图例（◆ n）：事件单独一列，不再与 note 混在一起 */
	var minimapEvtTitle:FlxText;
	var minimapX:Float = 10;
	var minimapY:Float = 0;
	var minimapW:Float = 190;
	var minimapH:Float = 300;
	var minimapDirty:Bool = true;
	var minimapCooldown:Float = 0;
	var minimapCanvasW:Int = 0;
	var minimapCanvasH:Int = 0;
	var minimapSongKey:String = '';
	/** ★ 上一帧的屏幕尺寸（全屏切换/窗口缩放后重算 minimap 布局） */
	var minimapScreenW:Float = -1;
	var minimapScreenH:Float = -1;

	/** minimap 下边缘与屏幕底部的距离（用户指定 220px） */
	static inline var MINIMAP_BOTTOM_GAP:Float = 220;
	/** minimap 与状态栏的间隔（用户要求“完全贴着”） */
	static inline var MINIMAP_TOP_PAD:Float = 0;

	function setupMinimap():Void
	{
		minimapW = EditorInputStyle.sv(190);
		layoutMinimapMetrics();

		minimapBG = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		minimapBG.color = 0xFF14161D;
		minimapBG.alpha = 0.85;
		minimapBG.scrollFactor.set(0, 0);
		add(minimapBG);

		rebuildMinimapCanvas();

		minimapViewport = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		minimapViewport.color = 0xFFFFD24A;
		minimapViewport.alpha = 0.28;
		minimapViewport.scrollFactor.set(0, 0);
		// ★ 拉伸前必须归零 origin/offset：否则渲染顶点会被 -(origin*scale) 左移
		//   整整半个宽度 → 黄色视口块看起来只有 50% 宽（左半被裁掉）。
		minimapViewport.origin.set(0, 0);
		minimapViewport.offset.set(0, 0);
		add(minimapViewport);

		minimapTitle = new EditorText(minimapX + EditorInputStyle.sv(5), minimapY + EditorInputStyle.sv(3), minimapW - EditorInputStyle.sv(10), '♪ 0', 14);
		minimapTitle.visible = false; // ★ 数字已移到状态栏，不再占 minimap 的空间
		minimapTitle.setFormat(Paths.font(Language.get('fontName', 'main') + '.ttf'), 14, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE_FAST, FlxColor.BLACK);
		minimapTitle.scrollFactor.set(0, 0);
		minimapTitle.borderSize = 1;
		add(minimapTitle);

		// 事件列图例（黄）
		minimapEvtTitle = new EditorText(minimapX + minimapW - EditorInputStyle.sv(42), minimapY + EditorInputStyle.sv(3), EditorInputStyle.sv(40), '▶', 14);
		minimapEvtTitle.visible = false;
		minimapEvtTitle.setFormat(Paths.font(Language.get('fontName', 'main') + '.ttf'), 14, 0xFFFFD24A, RIGHT, FlxTextBorderStyle.OUTLINE_FAST,
			FlxColor.BLACK);
		minimapEvtTitle.scrollFactor.set(0, 0);
		minimapEvtTitle.borderSize = 1;
		add(minimapEvtTitle);

		applyMinimapLayout();
	}

	/** ★ 位置/尺寸：状态栏下方 → 屏幕底部 220px 处（窗口尺寸变化时会被重新计算） */
	function layoutMinimapMetrics():Void
	{
		minimapX = 10;
		var top:Float = ChartEditorMenuBar.BAR_HEIGHT + ChartEditorMenuBar.STATUS_HEIGHT + MINIMAP_TOP_PAD;
		var bottom:Float = FlxG.height - EditorInputStyle.sv(MINIMAP_BOTTOM_GAP);
		var h:Float = bottom - top;
		if (h < EditorInputStyle.sv(120)) h = EditorInputStyle.sv(120);
		if (top + h > FlxG.height - EditorInputStyle.sv(40)) h = FlxG.height - EditorInputStyle.sv(40) - top;
		minimapY = top;
		minimapH = h;
	}

	/** 画布尺寸变化时重建（同尺寸则跳过） */
	function rebuildMinimapCanvas():Void
	{
		var w:Int = Std.int(minimapW) - EditorInputStyle.si(4);
		var h:Int = Std.int(minimapH) - EditorInputStyle.si(4); // ★ 不再预留标题条（数字已移到状态栏），画布直接占满，高度自然变高
		if (w < 8) w = 8;
		if (h < EditorInputStyle.si(32)) h = EditorInputStyle.si(32);
		if (minimapCanvas == null)
		{
			minimapCanvas = new FlxSprite().makeGraphic(w, h, 0x00000000, true);
			minimapCanvas.scrollFactor.set(0, 0);
			if (minimapCanvas.graphic != null) minimapCanvas.graphic.persist = true; // ★ 防自动清理
			add(minimapCanvas);
		}
		else if (minimapCanvasW != w || minimapCanvasH != h)
		{
			// ★ 用 makeGraphic 就地换纹理：不能 remove/add（会打乱与标题的层级顺序）
			var oldG:FlxGraphic = minimapCanvas.graphic;
			minimapCanvas.makeGraphic(w, h, 0x00000000, true);
			minimapCanvas.scrollFactor.set(0, 0);
			if (minimapCanvas.graphic != null) minimapCanvas.graphic.persist = true;
			if (oldG != null && oldG != minimapCanvas.graphic) oldG.destroy();
		}
		minimapCanvasW = w;
		minimapCanvasH = h;
		minimapDirty = true;
	}

	function applyMinimapLayout():Void
	{
		if (minimapBG == null) return;
		layoutMinimapMetrics();
		rebuildMinimapCanvas();
		minimapBG.setPosition(minimapX, minimapY);
		minimapBG.scale.set(minimapW, minimapH);
		minimapBG.updateHitbox();
// ★★ 关键：updateHitbox() 会 centerOrigin()（origin = 帧半尺寸），
		//   而渲染顶点 = -(origin*scale) + (x - offset + origin)；1×1 贴图拉扯后
		//   origin*scale 会变成巨大偏移（360 宽 → 左移 179.5px；39 宽 → 19px）。
		//   所以拉伸后必须把 origin 与 offset 一起归零。
		minimapBG.origin.set(0, 0);
		minimapBG.offset.set(0, 0);
		if (minimapCanvas != null)
			minimapCanvas.setPosition(minimapX + EditorInputStyle.sv(2), minimapY + EditorInputStyle.sv(2));
		if (minimapTitle != null)
			minimapTitle.setPosition(minimapX + EditorInputStyle.sv(5), minimapY + EditorInputStyle.sv(3));
		if (minimapEvtTitle != null)
			minimapEvtTitle.setPosition(minimapX + minimapW - EditorInputStyle.sv(46), minimapY + EditorInputStyle.sv(3));
		minimapDirty = true;
	}

	/** ★ 换曲目 / 换难度后强制重新初始化 minimap（位置 + 画布尺寸 + 内容 + 视口）。
	 *  用户反馈「不是每次打开曲目都初始化」——因为同一首歌的不同难度可能 song/mania/小节数全相同，
	 *  靠 minimapSongKey 指纹检测会漏掉；所以载入流程里直接调这个，不依赖指纹。 */
	function resetMinimapForNewSong():Void
	{
		if (minimapBG == null) return;
		minimapSongKey = '';
		minimapCooldown = 0;
		minimapDirty = true;
		applyMinimapLayout(); // 内部会重算尺寸、必要时重建画布，并置 minimapDirty
		refreshMinimapNow();  // ★ 不等节流，立刻把当前谱面的分布画出来
	}

	/** ★ 立即重画（绕过节流）：进入编辑器 / 换曲目等时机调用，保证一进去就是当前谱面的分布图。 */
	function refreshMinimapNow():Void
	{
		if (minimapCanvas == null) return;
		ensureMetrics();
		refreshMinimap();
		minimapCooldown = 0.25; // 画完再启用节流，避免紧接着又重画一次
	}

	/** 屏幕坐标（view 坐标）是否落在 minimap 上。
	 *  ★ 菜单（含二级下拉）展开期间一律返回 false —— 此时指针归菜单，minimap 不参与交互。 */
	function pointerOnMinimap(sx:Float, sy:Float):Bool
	{
		if (minimapBG == null) return false;
		if (menuBar != null && menuBar.activeMenu >= 0) return false;
		if (historyPanel != null && historyPanel.visible) return false;
		return sx >= minimapX && sx <= minimapX + minimapW && sy >= minimapY && sy <= minimapY + minimapH;
	}

	/** 重画缩略图内容：全曲 note 分布 + 小节分隔（note 总数统计进标题） */
	function refreshMinimap():Void
	{
		if (minimapCanvas == null) return;
		rebuildMinimapCanvas(); // ★ 先校验画布尺寸（不符则重建），避免画布比实际绘制区大而留下大片空白
		var w:Int = minimapCanvasW;
		var h:Int = minimapCanvasH;
		if (w < 1 || h < 1) return;
		ensureMetrics();
		var totalPx:Float = totalRowsPx();
		if (totalPx <= 0) return;

		// ★★ 09-26 七轮：每次重画都换一张全新纹理（而不是原地改旧位图）。
		//   原地修改 BitmapData 在部分情况下不会重新上传到 GPU → minimap 永远停在第一次画的内容
		//   （用户反馈：“显示旧曲目内容、换曲目也恢复不了”）。
		var bmd:BitmapData = new BitmapData(w, h, true, 0x00000000);
		bmd.fillRect(new Rectangle(0, 0, w, h), 0x00000000);

		// ★ 09-26 三轮（用户要求）：事件不再和 note 挤在同一条里 —— 最右侧留 8px 作为
		//   「事件专用列」，note 只用左边的 noteAreaW，两列之间画一条分隔线。
		var evColW:Int = EditorInputStyle.si(8);
		var noteAreaW:Int = w - evColW - 3;
		if (noteAreaW < 8) noteAreaW = 8;
		var evColX:Int = w - evColW;

		var laneW:Float = noteAreaW / Math.max(1, totalKeys);
		var noteCount:Int = 0;
		var evCount:Int = 0;
		var colL:Int = resolveCharColor(_song.player1, 0xFF9AA0AA);
		var colR:Int = resolveCharColor(_song.player2, 0xFF9AA0AA);

		// ★ 09-26 八轮（用户要求）：minimap 也做背景颜色区分 ——
		//   与谱面网格同一语义：左半 = player1(BF) 色、右半 = player2(Opp) 色（低透明底色），
		//   note 仍然按它属于哪一方用对应的亮色标记。
		var bfBgW:Int = Std.int(noteAreaW * (leftKeys / Math.max(1, totalKeys)));
		if (bfBgW < 1) bfBgW = 1;
		if (bfBgW > noteAreaW - 1) bfBgW = noteAreaW - 1;
		bmd.fillRect(new Rectangle(0, 0, bfBgW, h), (colL & 0x00FFFFFF) | 0x33000000);
		bmd.fillRect(new Rectangle(bfBgW, 0, noteAreaW - bfBgW, h), (colR & 0x00FFFFFF) | 0x33000000);
		bmd.fillRect(new Rectangle(bfBgW, 0, 1, h), 0x66FFFFFF); // 左右分界线
		// 事件列背景稍暗（与 note 区分）
		bmd.fillRect(new Rectangle(evColX, 0, w - evColX, h), 0x1AFFFFFF);
		var markH:Int = EditorInputStyle.si(3); // ★ note 标记高度（原来 2px 太细，缩略图上几乎看不见）
		var n:Int = _song.notes.length;

		// 两列之间的分隔线
		bmd.fillRect(new Rectangle(evColX - 1, 0, 1, h), 0x30FFFFFF);

		for (s in 0...n)
		{
			var sec:Dynamic = _song.notes[s];
			if (sec == null) continue;

			var startPx:Float = secTopCache[s];
			var lenMs:Float = secLenCache[s];
			var startMs:Float = secMsCache[s];
			var secPx:Float = secRowsCache[s] * GRID_SIZE;

			// 小节分隔线（只画在 note 列内）
			var sepY:Int = Std.int((startPx / totalPx) * h);
			if (sepY >= 0 && sepY < h)
				bmd.fillRect(new Rectangle(0, sepY, noteAreaW, 1), 0x48FFFFFF);

			if (lenMs <= 0) continue;

			var notes:Array<Dynamic> = sec.sectionNotes;
			if (notes != null && notes.length > 0)
			{
				noteCount += notes.length;
				// ★ 颜色按「属于谁」：mustHitSection 小节的 lane<leftKeys 是 BF，否则反过来
				var mh:Bool = (sec.mustHitSection != null) ? sec.mustHitSection : true;
				for (i in notes)
				{
					if (i == null) continue;
					if (!(Std.isOfType(i[1], Int) || Std.isOfType(i[1], Float))) continue;
					var lane:Int = Std.int(cast i[1]);
					if (lane < 0 || lane >= totalKeys) continue;
					var frac:Float = ((cast i[0]:Float) - startMs) / lenMs;
					if (frac < 0) frac = 0;
					if (frac > 1) frac = 1;
					var ny:Int = Std.int(((startPx + frac * secPx) / totalPx) * h);
					if (ny < 0) ny = 0;
					if (ny >= h) ny = h - 1;
					var isPlayer:Bool = dataLaneIsPlayer(lane, mh);
					var col:Int = ((isPlayer ? colL : colR) & 0x00FFFFFF) | 0xE8000000;
					// 显示列：玩家侧在左半、对手在右半（与网格一致）
					var colIdx:Int = isPlayer ? (lane % leftKeys) : (lane % leftKeys) + leftKeys;
					var nx:Int = 1 + Std.int(colIdx * laneW);
					var nw:Int = Std.int(laneW);
					if (nw < 1) nw = 1;
					if (nx + nw > noteAreaW) nw = noteAreaW - nx;
					if (nw < 1) continue;
					bmd.fillRect(new Rectangle(nx, ny, nw, markH), col);
				}
			}

			// ★ 事件画在【独立的事件列】里（黄色，不再压住 note 条）
			var evs:Array<Dynamic> = (s < eventsBySec.length) ? eventsBySec[s] : null;
			if (evs != null)
			{
				for (i in evs)
				{
					if (i == null) continue;
					var frac:Float = ((cast i[0]:Float) - startMs) / lenMs;
					if (frac < 0) frac = 0;
					if (frac > 1) frac = 1;
					var ny:Int = Std.int(((startPx + frac * secPx) / totalPx) * h);
					if (ny < 0 || ny >= h) continue;
					evCount++;
					bmd.fillRect(new Rectangle(evColX, ny, evColW - 1, 3), 0xE8FFD24A);
				}
			}
		}

		// ★ 把新纹理换上去（旧纹理及时释放，避免每次重画泄漏显存）
		var newG:FlxGraphic = FlxGraphic.fromBitmapData(bmd, true, null, false);
		newG.persist = true;
		var oldG:FlxGraphic = minimapCanvas.graphic;
		minimapCanvas.frames = FlxImageFrame.fromGraphic(newG);
		minimapCanvas.dirty = true;
		if (oldG != null && oldG != newG)
			oldG.destroy();

		// note 总数已移到顶栏状态栏（BF/Opp 分开统计），这里只留图例
		// ★ note 总数 / 事件总数已在顶栏状态栏显示；图例不再占画布空间
		if (minimapTitle != null)
			minimapTitle.visible = false;
		if (minimapEvtTitle != null)
			minimapEvtTitle.visible = false;
		minimapDirty = false;
	}

	/** 拖动/点击缩略图 → 跳到对应位置。
	 *  ★ 用户要求：拖动高亮期间【绝不播放】——音乐/vocals 保持暂停（不然抹音时噪音很吵）。 */
	function minimapSeek(screenY:Float):Void
	{
		if (minimapCanvas == null) return;
		ensureMetrics();
		var totalPx:Float = totalRowsPx();
		if (totalPx <= 0) return;

		var frac:Float = FlxMath.bound((screenY - minimapCanvas.y) / minimapCanvas.height, 0, 1);
		var targetPx:Float = frac * totalPx;

		// 目标小节（二分）
		var targetSec:Int = findSectionAtY(targetPx);
		var localFrac:Float = 0;
		if (secRowsCache.length > 0)
		{
			var secH:Float = secRowsCache[targetSec] * GRID_SIZE;
			if (secH > 0)
				localFrac = FlxMath.bound((targetPx - secTopCache[targetSec]) / secH, 0, 0.999);
		}

		changeSection(targetSec, false);
		var t:Float = sectionStartTime() + localFrac * sectionLenMsAt(curSec);
		if (t > FlxG.sound.music.length) t = FlxG.sound.music.length;
		if (t < 0) t = 0;
		// 拖动 = 静音抹音：先确保全部暂停，再定位（不 resume，恢复播放交给用户按播放键）
		FlxG.sound.music.pause();
		FlxG.sound.music.time = t;
		pauseAndSetVocalsTime();
		Conductor.songPosition = t;
		strumLineUpdateY();
	}

	/** 每帧：布局校验 → 节流重绘 → 视口块位置 → 拖动跳转 */
	function minimapUpdate():Void
	{
		if (minimapBG == null) return;
		ensureMetrics();

		// ★ 换曲目 / 换难度（歌名或小节数变化）→ 立即重建布局 + 重画，避免残留上一首的分布图
		var key:String = '' + currentSongName + '|' + (_song == null ? '' : (_song.mania + '|' + _song.notes.length));
		if (key != minimapSongKey)
		{
			minimapSongKey = key;
			minimapCooldown = 0;
			applyMinimapLayout();
			refreshMinimapNow(); // ★ 换曲目/难度后立刻重画，不再等 update 的节流
		}

		if (minimapCooldown > 0)
			minimapCooldown -= FlxG.elapsed;

		// ★ 屏幕尺寸变了（全屏切换、窗口拉伸）→ 重算位置/尺寸并重画
		if (FlxG.width != minimapScreenW || FlxG.height != minimapScreenH)
		{
			minimapScreenW = FlxG.width;
			minimapScreenH = FlxG.height;
			applyMinimapLayout();
		}

		// ★ 顶栏状态栏：「移动音符模式」右边的 BF / Opp note 数量统计
		//   （颜色 = 各自角色 healthColor，与谱面网格同色；值不变时 setNoteCounts 内部直接返回）
		if (menuBar != null && menuBar.statusBar != null && _song != null)
		{
			menuBar.statusBar.setNoteCounts(bfNoteTotal, oppNoteTotal,
				resolveCharColor(_song.player1, 0xFF3CA7E0),
				resolveCharColor(_song.player2, 0xFFD8556A),
				bfNoteTotal + oppNoteTotal,
				(_song.events != null) ? _song.events.length : 0);
		}
		if (minimapDirty && minimapCooldown <= 0)
		{
			refreshMinimap();
			minimapCooldown = 0.2; // 重画节流：最多每 0.2s 一次（32787 note 的全量重画不便宜）
		}

		var totalPx:Float = totalRowsPx();
		if (totalPx > 0 && minimapCanvas != null)
		{
			var canvasTop:Float = minimapCanvas.y;
			var canvasH:Float = minimapCanvas.height;
			var vy:Float = canvasTop + (FlxG.camera.scroll.y / totalPx) * canvasH;
			var vh:Float = (FlxG.height / totalPx) * canvasH;
			if (vy < canvasTop)
			{
				vh += (vy - canvasTop);
				vy = canvasTop;
			}
			if (vy + vh > canvasTop + canvasH)
				vh = canvasTop + canvasH - vy;
			if (vh < 4) vh = 4;
			minimapViewport.setPosition(minimapCanvas.x, vy);
			minimapViewport.scale.set(minimapCanvasW, vh); // ★ 用画布字段，与绘制尺寸同源
			minimapViewport.origin.set(0, 0);
			minimapViewport.offset.set(0, 0);
		}

		// ---- 按住 = 跳转（鼠标 / 触摸都支持）----
		var px:Float = -9999;
		var py:Float = -9999;
		var held:Bool = false;
		#if desktop
		if (FlxG.mouse != null && FlxG.mouse.pressed)
		{
			px = FlxG.mouse.viewX;
			py = FlxG.mouse.viewY;
			held = true;
		}
		#end
		var touches = FlxG.touches.list;
		if (touches != null)
		{
			for (touch in touches)
			{
				if (touch != null && touch.pressed)
				{
					var pt = touch.getViewPosition(FlxG.camera, FlxPoint.get());
					px = pt.x;
					py = pt.y;
					pt.put();
					held = true;
				}
			}
		}
		// ★ 菜单展开时 pointerOnMinimap 直接返回 false（不 seek、不静音、不抢指针）
		if (held && pointerOnMinimap(px, py))
		{
			// ★ 按住缩略图期间强制静音（即使音乐刚被快捷键/自动续播拉起来也立刻压住）
			if (FlxG.sound.music != null && FlxG.sound.music.playing)
				FlxG.sound.music.pause();
			if (vocals != null && vocals.playing)
				vocals.pause();
			if (opponentVocals != null && opponentVocals.playing)
				opponentVocals.pause();
			minimapSeek(py);
		}
	}

	function updateZoom()
	{
		// ★ 双保险：curZoom 越界直接 clamp（防任何路径把索引改出界）
		curZoom = Std.int(FlxMath.bound(curZoom, 0, zoomList.length - 1));
		var daZoom:Float = zoomList[curZoom];
		var zoomThing:String = '1 / ' + daZoom;
		if (daZoom < 1)
			zoomThing = Math.round(1 / daZoom) + ' / 1';
		zoomTxt.text = 'Zoom: ' + zoomThing;
		// 同步到新顶栏菜单的状态栏
		if (menuBar != null && menuBar.statusBar != null)
			menuBar.statusBar.setZoom(zoomThing);
		reloadGridLayer();
	}

	override function destroy()
	{
		// ★ 离开编谱器必须摘掉挂在全局 persist 音轨上的完成回调：闭包捕获 this，
		//   留着会把整个 ChartingState（谱面缓存/波形/小地图位图…）一直钉在内存里。
		clearMusicOnComplete();
		// Engine overrides apply to this chart only; do not let them force the next
		// gameplay chart or editor session to use the same parser/ownership rules.
		Song.forceEngineVersion = null;
		// ★ 编谱器把整首歌的 Inst 载进了**全局** persist 音轨、把 player/opponent vocals
		//   加进了**全局** FlxG.sound.list，却从不释放：一首 7.8MB 的 ogg 解码出来是几十 MB，
		//   退出编辑器后这些 PCM 一直挂着（实测每次进出编谱器残留 +17MB GC 堆 / +57MB 进程内存）。
		releaseEditorAudio();
		releaseEditorGraphics();
		// ★ 防止错误提示的 5s 计时器在退出时仍抓着 this（闭包捕获 this）
		if (missingTextTimer != null) { missingTextTimer.cancel(); missingTextTimer = null; }
		// ★ 十二轮：离开编辑器 → 还原游戏本体设计分辨率（1280×720），玩法不受影响
		EditorInputStyle.exitHiRes();
		Note.globalRgbShaders = [];
		games.backend.NoteTypesConfig.clearNoteTypesData();
		super.destroy();
	}

	/**
	 * 掏空（见 MusicBeatState.hollowOut）：编谱器最占内存的东西**都不在成员表里** ——
	 * 波形浮点数组、解码音频的原始字节缓存、段落精灵缓存、小地图/小节行缓存。
	 * 它们由本实例的字段持有，而本实例的壳会被一个反射看不见的根钉住
	 * （实测退出编谱器后 created/state:ChartingState 仍存活），于是这些几十 MB 的
	 * 内容也跟着常驻。这里在销毁最后把它们确定性放掉。
	 */
	override function hollowOut():Void
	{
		// 波形（2 声道 × 整首歌的采样点，浮点数组）与原始音频字节
		wavData = [[[0], [0]], [[0], [0]]];
		try waveBytesCache.clear() catch (e:Dynamic) {}

		// 段落精灵缓存里的精灵不是成员表成员 → 显式销毁（已销毁的会被 freeBunch 跳过）
		try
		{
			for (arr in secBgCache) if (arr != null) MusicBeatState.freeBunch(cast arr);
			secBgCache.clear();
		}
		catch (e:Dynamic) {}
		try
		{
			for (arr in secNoteCache) if (arr != null) MusicBeatState.freeBunch(cast arr);
			secNoteCache.clear();
		}
		catch (e:Dynamic) {}

		// 各种按段落/事件的索引缓存
		secRowsCache = [];
		secTopCache = [];
		secMsCache = [];
		secBpmCache = [];
		secStepMsCache = [];
		secLenCache = [];
		secNoteCountCache = [];
		eventsBySec = [];
		try charColorCache.clear() catch (e:Dynamic) {}

		// 成员表里的组已经由 super.destroy() 销毁，这里只断开引用
		curRenderedNotes = null;
		curRenderedSustains = null;
		curRenderedNoteType = null;
		nextRenderedNotes = null;
		nextRenderedSustains = null;
		strumLineNotes = null;
		gridLayer = null;
		blockPressWhileTypingOn = [];
		blockPressWhileTypingOnStepper = [];
		blockPressWhileScrolling = [];
	}

	/**
	 * 释放编谱器的音频资源：
	 *   - player / opponent vocals：从全局声音表摘除并销毁；
	 *   - 全局 persist 音轨：换回菜单 BGM（和 doExitEditor() 里那句 playMusic 同语义），
	 *     这样整首 Inst 的解码数据不再被 FlxG.sound.music 抓着（同时保证主菜单仍有一首可放的曲子）。
	 */
	function releaseEditorAudio():Void
	{
		if (vocals != null)
		{
			if (FlxG.sound != null && FlxG.sound.list != null) FlxG.sound.list.remove(vocals);
			vocals.destroy();
			vocals = null;
		}
		if (opponentVocals != null)
		{
			if (FlxG.sound != null && FlxG.sound.list != null) FlxG.sound.list.remove(opponentVocals);
			opponentVocals.destroy();
			opponentVocals = null;
		}

		// 把全局音轨换回菜单曲：丢掉对本曲 Inst 的引用（音频由 clearStoredMemory 的
		// Assets 缓存清理 + GC 真正回收）。
		try
		{
			if (FlxG.sound != null && FlxG.sound.music != null)
			{
				FlxG.sound.music.stop();
				FlxG.sound.playMusic(Paths.music('freakyMenu'), 0.7);
			}
		}
		catch (e:Dynamic) {}
	}

	/**
	 * 释放编谱器自己造的 persist 位图。
	 *
	 * 网格底色/小地图画布/波形图都显式 `persist = true`（防止被 FlxG.bitmap 的自动清理
	 * 当成垃圾销毁）。编辑器退出后它们没人用了却还留在位图缓存里，逐轮累积（实测
	 * graphics 68 → 567，退出后仍残留 266/448）。这里主动降级为可回收，交给
	 * clearStoredMemory / clearUnused 收掉。
	 */
	function releaseEditorGraphics():Void
	{
		// 小地图画布 / 波形图是**本会话专属**的大位图，退出时降级为可回收
		// （注意：网格的 chart_white1px 是跨会话共享的缓存图，故意 persist，不能动！）
		unpersistGraphic(minimapCanvas);
		unpersistGraphic(waveformSprite);
		// 渲染窗口缓存：只丢引用（这些 sprite 可能共享 chartWhiteFrame，按引擎既有约定
		// 不在这里 destroy，免得把共享帧还回对象池导致下次进编辑器渲染空白）
		try
		{
			if (secBgCache != null) secBgCache.clear();
			if (secNoteCache != null) secNoteCache.clear();
		}
		catch (e:Dynamic) {}
		// 编辑器里所有 makeGraphic(..., true) 出来的唯一图：立刻清一遍没人用的
		try
		{
			if (FlxG.bitmap != null) FlxG.bitmap.clearUnused();
		}
		catch (e:Dynamic) {}
	}

	function unpersistGraphic(spr:FlxSprite):Void
	{
		if (spr == null) return;
		try
		{
			if (spr.graphic != null)
			{
				spr.graphic.persist = false;
				spr.graphic.destroyOnNoUse = true;
			}
		}
		catch (e:Dynamic) {}
	}

	var lastSecBeats:Float = 0;
	var lastSecBeatsNext:Float = 0;

	/** 网格左缘 x：整张网格（含节拍列）相对屏幕水平居中 */
	function getGridX():Float
	{
		return (FlxG.width - GRID_SIZE * (totalKeys + 1)) / 2;
	}

	/** 角色 healthBarColor（Psych 标准角色名映射：bf=蓝、dad=紫红、gf=绿、monster=紫、pico=青、mom=粉…）。
	 *  ★ 未知角色返回 -1，由调用方用角色图标主色（dominantColor）兜底——不固定颜色，
	 *    换任何角色当 BF/Opp 时背景/波形颜色都会跟着变。 */
	public static function getCharHealthColor(char:String):Int
	{
		switch (char)
		{
			case 'bf' | 'bf-pixel' | 'bf-car' | 'bf-christmas' | 'bf-holding-gf': return 0xFF31B0D1;
			case 'dad' | 'dad-pixel' | 'dad-car' | 'dad-christmas' | 'dad-week1' | 'dad-week2' | 'dad-week3' | 'bf-pixel-opponent': return 0xFFA32E4B;
			case 'gf' | 'gf-pixel' | 'gf-christmas' | 'gf-car': return 0xFFA6E22E;
			case 'monster' | 'monster-pixel': return 0xFF8F6BFF;
			case 'pico' | 'pico-pixel': return 0xFF00E9FF;
			case 'mom' | 'mom-pixel': return 0xFFFF78BF;
			case 'spooky' | 'spooky-pixel': return 0xFF7C7C7C;
			case 'tankman' | 'tankman-pixel': return 0xFF4B4B4B;
			case 'face': return 0xFFFFE172;
			default: return -1;
		}
	}

	/** ★ 角色颜色 = 纯歌曲数据驱动，与屏幕上的头像状态完全无关（顺序无关、换曲即正确）：
	 *  1) 内置角色名映射 getCharHealthColor
	 *  2) 角色 JSON 的 healthbar_colors（updateJsonData 时缓存进 characterData）
	 *  3) 独立加载该角色图标提取主色（带缓存）——不再读 leftIcon/rightIcon 的显示状态，
	 *     否则小节换边/换曲时图标滞后会导致左右颜色错位或永远不更新
	 *  4) 兜底色 */
	function resolveCharColor(char:String, fallback:Int):Int
	{
		var mapped:Int = getCharHealthColor(char);
		if (mapped >= 0) return mapped;

		var slot:Int = 0;
		var iconName:String = null;
		var hb:Array<Int> = null;
		if (_song != null && characterData != null)
		{
			for (i in 1...3)
			{
				if (Reflect.field(_song, 'player$i') == char)
				{
					slot = i;
					break;
				}
			}
			if (slot > 0)
			{
				hb = Reflect.field(characterData, 'healthP$slot');
				iconName = Reflect.field(characterData, 'iconP$slot');
			}
		}
		if (hb != null && hb.length > 2)
			return 0xFF000000 | (Std.int(hb[0]) << 16) | (Std.int(hb[1]) << 8) | Std.int(hb[2]);
		if (iconName == null) iconName = char;
		if (charColorCache.exists(iconName)) return charColorCache.get(iconName);
		var col:Int = -1;
		try
		{
			var tmp:HealthIcon = new HealthIcon(iconName);
			if (tmp.graphic != null && tmp.graphic.bitmap != null)
				col = CoolUtil.dominantColor(tmp);
			// ★ 绝不能 tmp.destroy()：HealthIcon 的帧是全局共享的 Atlas 帧，
			//   destroy 会把 FlxFrame 归还对象池 → 场上所有同角色头像一起变空白。
			tmp.kill();
			tmp.exists = false;
		}
		catch (e:Dynamic) {}
		charColorCache.set(iconName, col);
		return col >= 0 ? col : fallback;
	}

	/** 全谱网格共用的 1×1 白贴图 frames（reloadGridLayer 里初始化） */
	var chartWhiteFrame:FlxImageFrame;

	/** 全谱网格横线：共享 1×1 白贴图 + alpha/厚度（避免每行生成独立贴图）。
	 *  ★ into 非空时 sprite 同时登记进该小节的缓存数组（供窗口回收），否则裸挂在 gridLayer 上。 */
	function addHLine(x:Float, y:Float, w:Int, alpha:Float, thick:Int, ?into:Array<FlxSprite>):Void
	{
		var hLine:FlxSprite = new FlxSprite(x, y);
		if (chartWhiteFrame != null)
		{
			hLine.frames = chartWhiteFrame; // 共享 1×1 白贴图
			hLine.color = 0xFFFFFFFF;
			hLine.alpha = alpha;
			hLine.scale.set(w, thick);
		}
		else
		{
			var a:Int = Std.int(Math.max(1, Math.min(255, alpha * 255)));
			hLine.makeGraphic(w, thick, (a << 24) | 0xFFFFFF);
		}
		hLine.updateHitbox();
		hLine.origin.set(0, 0);
		hLine.offset.set(0, 0); // ★ 左上角对齐（updateHitbox 会同时改 origin 与 offset）
		hLine.antialiasing = false;
		gridLayer.add(hLine);
		if (into != null)
			into.push(hLine);
	}

	// ==================== 虚拟化渲染窗口（09-26 二轮 / 性能）====================
	// 只渲染「相机附近」的小节；离开窗口即销毁，进入窗口才创建。
	var secBgCache:Map<Int, Array<FlxSprite>> = new Map();
	var secNoteCache:Map<Int, Array<FlxSprite>> = new Map();
	var noteOwners:haxe.ds.ObjectMap<Note, Int> = new haxe.ds.ObjectMap();
	function noteSourceSection(note:Note):Int
	{
		var owner = noteOwners.get(note);
		return owner == null ? findSectionAtTime(note.strumTime) : owner;
	}
	var winFrom:Int = -1;
	var winTo:Int = -1;
	var winAxis:Int = -1;

	/** ★★ 释放渲染缓存 sprite：只从分组移除 + 停用，**绝不 destroy()**。
	 *  flixel 5.9 的 `FlxSprite.destroy()` 内部会 `FlxDestroyUtil.destroy(_frame)` → `FlxFrame.destroy()`
	 *  把 `parent=null` 并把 sourceSize/uv/frame **归还到对象池**；而这些 sprite 共享同一个
	 *  FlxFrame 实例（chartWhiteFrame、note/icon 的 Atlas 帧）→ destroy 一个 = 之后所有复用该帧的
	 *  sprite 全部渲染不出来（网格底色消失、音符消失、头像空白）。对象交给 GC 回收即可。 */
	inline function releaseSprite(spr:FlxSprite):Void
	{
		if (spr == null) return;
		spr.kill();
		spr.exists = false;
		spr.visible = false;
		spr.alpha = 0;
	}

	function destroySecBg(s:Int):Void
	{
		var old:Array<FlxSprite> = secBgCache.get(s);
		if (old == null) return;
		for (spr in old)
		{
			if (spr == null) continue;
			gridLayer.remove(spr, true);
			releaseSprite(spr);
		}
		secBgCache.remove(s);
	}

	function destroySecNotes(s:Int):Void
	{
		var old:Array<FlxSprite> = secNoteCache.get(s);
		if (old == null) return;
		for (spr in old)
		{
			if (spr == null) continue;
			if (Std.isOfType(spr, Note)) noteOwners.remove(cast spr);
			curRenderedNotes.remove(cast spr);
			curRenderedSustains.remove(spr);
			curRenderedNoteType.remove(cast spr);
			releaseSprite(spr);
		}
		secNoteCache.remove(s);
	}

	function destroyAllSecBg():Void
	{
		for (k in [for (k in secBgCache.keys()) k])
			destroySecBg(k);
	}

	function destroyAllSecNotes():Void
	{
		for (k in [for (k in secNoteCache.keys()) k])
			destroySecNotes(k);
	}

	/** ★ 增量维护渲染窗口：回收窗口外的小节，创建窗口内尚未渲染的小节。
	 *  09-26 三轮（防爆）：窗口 = 【相机可视范围 ± 0.6 屏】 ∪ 【curSec ± 1】。
	 *  旧版把 curSec 也「拉进」区间（from=min(from,curSec)）——当相机还没跟到大编号的 curSec 时
	 *  会一次性从 0 建到 curSec（几千个小节）→ 直接卡死。 */
	function refreshRenderWindow(force:Bool = false):Void
	{
		if (_song == null || _song.notes == null) return;
		ensureMetrics();
		var n:Int = _song.notes.length;
		if (n <= 0) return;

		// 窗口 = 相机可视范围 ± 1.2 屏（缓冲开大，避免播放/BPM 高的谱面里反复跨越窗口边界
		// 导致背景块与音符被频繁销毁重建 —— 那会在画面上表现为网格闪烁）
		var pad:Float = FlxG.height * 1.2;
		var camFrom:Int = findSectionAtY(FlxG.camera.scroll.y - pad);
		var camTo:Int = findSectionAtY(FlxG.camera.scroll.y + FlxG.height + pad);
		if (camFrom < 0) camFrom = 0;
		if (camTo > n - 1) camTo = n - 1;

		var cs:Int = curSec;
		if (cs < 0) cs = 0;
		if (cs >= n) cs = n - 1;

		if (!force && camFrom == winFrom && camTo == winTo && cs == winAxis) return;

		// 需要保留的集合 = 相机窗口 ∪ 编辑区邻域
		var keep:Map<Int, Bool> = new Map();
		for (s in camFrom...camTo + 1)
			keep.set(s, true);
		for (s in (cs - 1)...(cs + 2))
			if (s >= 0 && s <= n - 1)
				keep.set(s, true);

		// ★★ 09-26 九轮：类型角标（note 上的数字）只在【当前小节】画，而 sprite 只在进窗口时创建一次 ——
		//   换小节时不重建就永远没有角标（用户反馈“特殊 note 不显示数字，调 mania 才出来”）。
		//   所以 curSec 变化时把新/旧两个小节都重建一次。
		if (winAxis >= 0 && winAxis != cs)
		{
			destroySecNotes(winAxis);
			destroySecNotes(cs);
		}

		for (k in [for (k in secBgCache.keys()) k])
			if (!keep.exists(k))
				destroySecBg(k);
		for (k in [for (k in secNoteCache.keys()) k])
			if (!keep.exists(k))
				destroySecNotes(k);

		for (s in keep.keys())
		{
			if (!secBgCache.exists(s))
				buildSecBg(s);
			if (!secNoteCache.exists(s))
				buildSecNotes(s);
		}
		winFrom = camFrom;
		winTo = camTo;
		winAxis = cs;
	}

	/** ★ 第 s 小节的背景（轨道底色 + 横线 + 竖线 + 分割线） */
	function buildSecBg(s:Int):Void
	{
		if (_song.notes[s] == null) return;
		var gx:Float = getGridX();
		var gridW:Float = GRID_SIZE * (totalKeys + 1);
		var gridWi:Int = Std.int(gridW);
		var secY:Float = secRowStartPx(s);
		var rows:Int = secRowsAt(s);
		var secH:Float = rows * GRID_SIZE;

		var list:Array<FlxSprite> = [];

		// 1) 轨道底色 ★ 09-26 二轮：谱面固定 —— 左半恒 player1、右半恒 player2。
		//    切换 BF/Opp 小节只移动摄像机图标（camIcon），不再整片换色。
		var leftC:Int = resolveCharColor(_song.player1, 0xFF666666);
		var rightC:Int = resolveCharColor(_song.player2, 0xFF666666);
		for (i in 0...totalKeys)
		{
			var laneBg:FlxSprite = new FlxSprite(gx + GRID_SIZE * (i + 1), secY);
			laneBg.frames = chartWhiteFrame; // 共享 1×1 白贴图
			laneBg.color = (i < leftKeys ? leftC : rightC);
			laneBg.scale.set(GRID_SIZE - 1, secH);
			laneBg.updateHitbox();
			laneBg.origin.set(0, 0);
			laneBg.offset.set(0, 0);
			laneBg.alpha = 0.35;
			laneBg.antialiasing = false;
			gridLayer.add(laneBg);
			list.push(laneBg);
		}

		// 2) 横线：拍线更亮；行数过多（超大 zoom）时只保留拍线 + 小节边界
		var beatStep:Int = Std.int(Math.max(1, rows / 4));
		var drawRowLines:Bool = (rows <= 200);
		for (r in 0...rows)
		{
			if (r % beatStep == 0)
				addHLine(gx, secY + GRID_SIZE * r, gridWi, 0.6, 2, list);
			else if (drawRowLines)
				addHLine(gx, secY + GRID_SIZE * r, gridWi, 0.4, 1, list);
		}
		addHLine(gx, secY, gridWi, 0.7, 2, list); // 小节边界

		// 3) 竖线（按小节分段，避免单个 sprite 纵向 scale 到几十万像素）
		for (i in 0...(totalKeys + 1))
		{
			var vLine:FlxSprite = new FlxSprite(gx + GRID_SIZE * (i + 1) - 1, secY);
			vLine.frames = chartWhiteFrame;
			vLine.color = 0xFFFFFFFF;
			vLine.alpha = 0.33;
			vLine.scale.set(1, secH);
			vLine.updateHitbox();
			vLine.origin.set(0, 0);
			vLine.offset.set(0, 0);
			vLine.antialiasing = false;
			gridLayer.add(vLine);
			list.push(vLine);
		}

		// 4) 两条黑色分割线：BF/Opp 分界 + 左侧节拍列
		var sepXs:Array<Float> = [gx + gridW - (GRID_SIZE * leftKeys), gx + GRID_SIZE];
		for (sx in sepXs)
		{
			var sep:FlxSprite = new FlxSprite(sx, secY);
			sep.frames = chartWhiteFrame;
			sep.color = 0xFF000000;
			sep.alpha = 1;
			sep.scale.set(2, secH);
			sep.updateHitbox();
			sep.origin.set(0, 0);
			sep.offset.set(0, 0);
			sep.antialiasing = false;
			gridLayer.add(sep);
			list.push(sep);
		}

		// 5) vortex 红色拍分隔（按该小节自己的 beats）
		if (vortex)
		{
			var beats:Int = Std.int(getSectionBeats(s));
			for (i in 1...beats)
			{
				var beatsep:FlxSprite = new FlxSprite(gx, secY + (GRID_SIZE * 4 * zoomList[curZoom]) * i);
				beatsep.frames = chartWhiteFrame;
				beatsep.color = 0xFF0000;
				beatsep.alpha = 0.27;
				beatsep.scale.set(gridW, 1);
				beatsep.updateHitbox();
			beatsep.origin.set(0, 0);
			beatsep.offset.set(0, 0);
				beatsep.antialiasing = false;
				gridLayer.add(beatsep);
				list.push(beatsep);
			}
		}

		secBgCache.set(s, list);
	}

	/** ★ 第 s 小节的音符 / sustain / 类型标签 */
	function buildSecNotes(s:Int):Void
	{
		if (s < 0 || s >= _song.notes.length || _song.notes[s] == null) return;
		var secObj:Dynamic = _song.notes[s];
		var list:Array<FlxSprite> = [];
		secNoteCache.set(s, list);

		var inCur:Bool = (s == curSec);
		var secStepMs:Float = sectionStepMsAt(s);

		var secNotes:Array<Dynamic> = secObj.sectionNotes;
		if (secNotes != null)
		{
			for (i in secNotes)
			{
				var note:Note = setupNoteData(i, s);
				note.alpha = inCur ? 1 : 0.6;
				// mustPress / 显示轨号 已由 setupNoteData 按 mustHitSection 与 lane 一并算好
				curRenderedNotes.add(note);
				list.push(note);
				if (note.sustainLength > 0)
				{
					var sus:FlxSprite = setupSusNote(note, secStepMs);
					sus.alpha = note.alpha;
					curRenderedSustains.add(sus);
					list.push(sus);
				}

				// 类型角标只在当前小节画（全谱都画的话文本量爆炸）
				if (inCur && i[3] != null && note.noteType != null && note.noteType.length > 0)
				{
					var typeInt:Int = curNoteTypes.indexOf(i[3]);
					var theType:String = '' + typeInt;
					if (typeInt < 0)
						theType = '?';

					var daText:AttachedFlxText = new AttachedFlxText(0, 0, 100, theType, 24);
					// ★ 角标内容恒为 ASCII（数字或 '?'）→ 可安全用 vcr（mods 优先）
					daText.setFormat(Paths.font(ChartEditorMenuBar.langFont(theType)), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE_FAST, FlxColor.BLACK);
					daText.xAdd = EditorInputStyle.sv(-32);
					daText.yAdd = EditorInputStyle.sv(6);
					daText.borderSize = 1;
					curRenderedNoteType.add(daText);
					daText.sprTracker = note;
					list.push(daText);
				}
			}
		}

		// 该小节范围内的事件（★ 预分组，避免每小节全扫 _song.events = O(小节×事件)）
		var evList:Array<Dynamic> = (s >= 0 && s < eventsBySec.length) ? eventsBySec[s] : null;
		if (evList != null)
		{
			for (i in evList)
			{
				var note:Note = setupNoteData(i, s);
				note.alpha = inCur ? 1 : 0.6;
				curRenderedNotes.add(note);
				list.push(note);

				if (inCur)
				{
					var text:String = 'Event: ' + note.eventName + ' (' + Math.floor(note.strumTime) + ' ms)' + '\nValue 1: ' + note.eventVal1
						+ '\nValue 2: ' + note.eventVal2;
					if (note.eventLength > 1)
						text = note.eventLength + ' Events:\n' + note.eventName;

					// ★ 十二轮：面板收窄到 190（720 设计）→ 不再压住左侧 minimap；右对齐贴住事件箭头
					var daText:AttachedFlxText = new AttachedFlxText(0, 0, EditorInputStyle.si(190), text, 12);
					// ★ 事件文本含英文+数字（ASCII）：按文本选字体
					daText.setFormat(Paths.font(ChartEditorMenuBar.langFont(text)), 12, FlxColor.WHITE, RIGHT, FlxTextBorderStyle.OUTLINE_FAST,
						FlxColor.BLACK);
					daText.xAdd = EditorInputStyle.sv(-198);
					daText.borderSize = 1;
					if (note.eventLength > 1)
						daText.yAdd += EditorInputStyle.sv(8);
					curRenderedNoteType.add(daText);
					daText.sprTracker = note;
					list.push(daText);
				}
			}
		}
	}

	function reloadGridLayer()
	{

		if (PlayState.SONG == null) {
			PlayState.SONG = {
				song: 'DUMMY',
				notes: [],
				events: [],
				bpm: 1,
				mania: _song.mania,
				needsVoices: true,
				player1: 'bf',
				player2: 'bf',
				gfVersion: 'bf',
				speed: 1,
				format: 'na',
				stage: 'stage'
			};
		} else {
			PlayState.SONG.mania = _song.mania;
		}

		// ★ 09-26 二轮（性能）：虚拟化渲染 —— 只保留相机附近若干小节的 sprite。
		//   32787 音符的谱面旧实现一次性建出十几万个 laneBg / 横线 sprite → 20 TPS。
		//   现在的分工：
		//     reloadGridLayer → 静态部分（gridBG 占位 + 上下留白横线）+ 触发窗口重建；
		//     buildSecBg(s)   → 第 s 小节的轨道底色 / 横线 / 竖线 / 分割线（进窗口时创建，离开即销毁）；
		//     buildSecNotes(s)→ 第 s 小节的音符 / sustain / 类型标签。
		metricsDirty = true;
		ensureMetrics();

		destroyAllSecBg();
		destroyAllSecNotes();
		winFrom = -1;
		winTo = -1;
		winAxis = -1;

		gridLayer.clear();

		// 全谱共享的 1×1 白贴图（所有线/底色都用它 + scale 拉伸，避免生成成千上万张贴图）
		var whitePx:FlxGraphic = FlxG.bitmap.create(1, 1, 0xFFFFFFFF, false, 'chart_white1px');
		whitePx.persist = true; // ★ 防止被 FlxG.bitmap 的自动清理销毁（销毁后所有网格线/底色一起变空白）
		chartWhiteFrame = FlxImageFrame.fromGraphic(whitePx);

		var gridW:Float = GRID_SIZE * (totalKeys + 1);
		var gridWi:Int = Std.int(gridW);
		var totalPx:Float = totalRowsPx();
		if (totalPx < 1) totalPx = 1;

		// ★ gridBG 只作为「范围 / 宽度参考」：绝不能直接生成整曲行数的位图
		//   （OpenFL 纹理边长上限 16384px，几千小节 × 每行 1px 会超限或直接造出巨图卡死）。
		//   改成 1×1 透明贴图 scale 到整曲尺寸 —— hitbox 依旧给出正确的 width/height。
		gridBG = new FlxSprite(getGridX(), 0).makeGraphic(1, 1, FlxColor.TRANSPARENT);
		gridBG.alpha = 0;
		gridBG.antialiasing = false;
		gridBG.scale.set(gridW, totalPx);
		gridBG.updateHitbox();
		gridBG.origin.set(0, 0);
		gridBG.offset.set(0, 0);
		gridLayer.add(gridBG);

		// ★ 全谱加载后不再有「下一小节」独立网格：nextGridBG 仅保留透明占位，防引用空指针
		nextGridBG = new FlxSprite().makeGraphic(1, 1, FlxColor.TRANSPARENT);
		nextGridBG.y = gridBG.height;
		gridLayer.add(nextGridBG);

		// ★ 全曲上 / 下留白（相机以播放头为中心，两端会露出谱面之外）：只补最暗的横线
		var padRows:Int = Std.int(Math.ceil((FlxG.height * 0.5 + 80) / GRID_SIZE));
		for (r in -padRows...0)
			addHLine(gridBG.x, GRID_SIZE * r, gridWi, 0.27, 1);
		for (r in 0...padRows)
			addHLine(gridBG.x, totalPx + GRID_SIZE * r, gridWi, 0.27, 1);

		// 波形 sprite 跟随当前小节顶部（只画当前小节时间窗，位图很小）
		waveformSprite.x = gridBG.x;
		waveformSprite.y = secRowStartPx(curSec);

		// 网格几何（键数 / 居中）变化后，头像重新居中
		positionSideIcons();

		#if (desktop || mobile)
		if (FlxG.save.data.chart_waveformInst || FlxG.save.data.chart_waveformVoices || FlxG.save.data.chart_waveformOppVoices)
		{
			updateWaveform();
		}
		#end

		// ★ 按相机窗口构建可见小节
		refreshRenderWindow(true);

		lastSecBeats = getSectionBeats();
		if (sectionStartTime(1) > FlxG.sound.music.length)
			lastSecBeatsNext = 0;
		else
			lastSecBeatsNext = getSectionBeats(curSec + 1);
	}

	function strumLineUpdateY()
	{
		// ★ 09-26 二轮：播放白条「抽搐」的修复。
		//   旧公式 `getTime % (Conductor.stepCrochet * 16)` 把小节内时间取模到 16 step：
		//   只要 (songPosition - 小节起点的换算) 略微越界，白条就从小节底部瞬移回顶部 → 逐帧抖动。
		//   新公式 = 纯线性映射（全局时间 → 绝对 y），单调连续，绝不 wrap：
		//     y = 所在小节顶部 + (t - 小节起点 ms) / 小节时长 ms × 小节像素高
		if (strumLine == null) return;
		ensureMetrics();
		if (secTopCache.length <= 0)
		{
			strumLine.y = 0;
			return;
		}
		var t:Float = Conductor.songPosition;
		if (Math.isNaN(t))
			t = 0;
		if (t < 0)
			t = 0;
		var sec:Int = findSectionAtTime(t);
		var len:Float = secLenCache[sec];
		var frac:Float = (len > 0) ? ((t - secMsCache[sec]) / len) : 0;
		if (frac < 0)
			frac = 0;
		else if (frac > 1)
			frac = 1; // 曲末最后一点：夹在小节底边，不要绕回顶部
		strumLine.y = secTopCache[sec] + frac * secRowsCache[sec] * GRID_SIZE;
	}

	var waveformPrinted:Bool = true;
	var wavData:Array<Array<Array<Float>>> = [[[0], [0]], [[0], [0]]];

	var lastWaveformHeight:Int = 0;
	var lastWaveformWidth:Int = 0;

	// ★ 波形字节缓存：__buffer.data.toBytes() 每次都整段拷贝解码后的音频（几十 MB 级），
	//   播放跨小节时反复拷贝 = 大卡顿的另一半来源。按源缓存，loadSong/重载音频时失效。
	var waveBytesCache:Map<String, Bytes> = new Map();

	function getWaveBytes(key:String, buf:AudioBuffer):Bytes
	{
		if (buf == null || buf.data == null) return null;
		if (!waveBytesCache.exists(key))
		{
			try
			{
				waveBytesCache.set(key, buf.data.toBytes());
			}
			catch (e:Dynamic)
			{
				return null;
			}
		}
		return waveBytesCache.get(key);
	}

	var waveViewFrom:Float = -1;
	var waveViewTo:Float = -1;
	var waveViewZoom:Int = -1;
	var waveViewModes:Int = -1;

	/** Cache only the visible time range. More beats fit as the chart is zoomed out. */
	function updateWaveform(force:Bool = true)
	{
		#if (desktop || mobile)
		if (_song == null || _song.notes == null || _song.notes.length == 0 || waveformSprite == null) return;
		ensureMetrics();
		var instOn = FlxG.save.data.chart_waveformInst == true;
		var bfOn = FlxG.save.data.chart_waveformVoices == true;
		var oppOn = FlxG.save.data.chart_waveformOppVoices == true;
		var modes = (instOn ? 1 : 0) | (bfOn ? 2 : 0) | (oppOn ? 4 : 0);
		if (modes == 0)
		{
			waveformSprite.visible = false;
			waveViewModes = 0;
			return;
		}
		var fromY:Float = Math.max(0, Math.floor(FlxG.camera.scroll.y / GRID_SIZE) * GRID_SIZE - GRID_SIZE);
		var toY:Float = Math.min(totalRowsPx(), Math.ceil((FlxG.camera.scroll.y + FlxG.camera.height) / GRID_SIZE) * GRID_SIZE + GRID_SIZE);
		if (toY <= fromY) { waveformSprite.visible = false; return; }
		var width:Int = GRID_SIZE * (totalKeys + 1);
		var height:Int = Std.int(Math.ceil(toY - fromY));
		if (!force && fromY == waveViewFrom && toY == waveViewTo && curZoom == waveViewZoom
			&& modes == waveViewModes && width == lastWaveformWidth) return;
		waveformSprite.visible = true;
		waveformSprite.x = getGridX();
		waveformSprite.y = fromY;
		if (lastWaveformHeight != height || lastWaveformWidth != width)
		{
			// The old bitmap is still referenced by the sprite and its GPU texture.
			// Detach it normally; disposing its image before replacement creates black blocks.
			unpersistGraphic(waveformSprite);
			waveformSprite.makeGraphic(width, height, 0x00000000, true);
			waveformSprite.graphic.persist = true;
			lastWaveformHeight = height;
			lastWaveformWidth = width;
		}
		waveformSprite.pixels.fillRect(new Rectangle(0, 0, width, height), 0x00000000);
		var bfX:Int = GRID_SIZE;
		var oppX:Int = GRID_SIZE * (leftKeys + 1);
		var bfW:Int = GRID_SIZE * leftKeys;
		var oppW:Int = GRID_SIZE * rightKeys;
		var bfColor:Int = (resolveCharColor(_song.player1, 0xFF666666) & 0x00FFFFFF) | 0x80000000;
		var oppColor:Int = (resolveCharColor(_song.player2, 0xFF666666) & 0x00FFFFFF) | 0x80000000;
		var first = findSectionAtY(fromY);
		var last = findSectionAtY(toY - 0.01);
		// Split sampling at BPM/section boundaries so each pixel keeps the correct time.
		for (section in first...last + 1)
		{
			var sectionY = secRowStartPx(section);
			var sectionHeight = secRowsAt(section) * GRID_SIZE;
			var clipY = Math.max(fromY, sectionY);
			var clipEnd = Math.min(toY, sectionY + sectionHeight);
			if (clipEnd <= clipY || sectionHeight <= 0) continue;
			var rows = Std.int(Math.ceil(clipEnd - clipY));
			var st = sectionStartTimeAt(section) + (clipY - sectionY) / sectionHeight * sectionLenMsAt(section);
			var et = sectionStartTimeAt(section) + (clipEnd - sectionY) / sectionHeight * sectionLenMsAt(section);
			var yOffset = clipY - fromY;
			if (bfOn && vocals != null && vocals._sound != null && vocals._sound.__buffer != null)
			{
				var buffer = vocals._sound.__buffer;
				var bytes = getWaveBytes('bf', buffer);
				if (bytes != null) drawWaveformBand(waveformData(buffer, bytes, st, et, 1, null, rows), bfX, bfX + bfW, bfColor, 1, yOffset);
			}
			if (oppOn && opponentVocals != null && opponentVocals._sound != null && opponentVocals._sound.__buffer != null)
			{
				var buffer = opponentVocals._sound.__buffer;
				var bytes = getWaveBytes('opp', buffer);
				if (bytes != null) drawWaveformBand(waveformData(buffer, bytes, st, et, 1, null, rows), oppX, oppX + oppW, oppColor, 1, yOffset);
			}
			if (instOn && FlxG.sound.music != null && FlxG.sound.music._sound != null && FlxG.sound.music._sound.__buffer != null)
			{
				var buffer = FlxG.sound.music._sound.__buffer;
				var bytes = getWaveBytes('inst', buffer);
				var instW = Std.int(width / 2);
				var instX = Std.int((width - instW) / 2);
				if (bytes != null) drawWaveformBand(waveformData(buffer, bytes, st, et, 1, null, rows), instX, instX + instW, 0x806FCF6F, 1, yOffset);
			}
		}
		waveViewFrom = fromY; waveViewTo = toY;
		waveViewZoom = curZoom; waveViewModes = modes;
		waveformPrinted = true;
		if (force) trace('[ChartWaveform] zoom=' + curZoom + ' visibleSections=' + first + '..' + last + ' bitmap=' + width + 'x' + height);
		#end
	}

	/** 在 waveformSprite 上绘制一段波形带（xStart ~ xEnd，以带中心为轴）。 */
	function drawWaveformBand(wav:Array<Array<Array<Float>>>, xStart:Int, xEnd:Int, color:Int, size:Float, yOffset:Float = 0):Void
	{
		var bandW:Int = xEnd - xStart;
		if (bandW < 1) return;
		var hSize:Int = Std.int(bandW / 2);

		var leftLength:Int = (wav[0][0].length > wav[0][1].length ? wav[0][0].length : wav[0][1].length);
		var rightLength:Int = (wav[1][0].length > wav[1][1].length ? wav[1][0].length : wav[1][1].length);
		var length:Int = leftLength > rightLength ? leftLength : rightLength;

		for (index in 0...length)
		{
			var lmin:Float = FlxMath.bound(((index < wav[0][0].length && index >= 0) ? wav[0][0][index] : 0) * (bandW / 1.12), -hSize, hSize) / 2;
			var lmax:Float = FlxMath.bound(((index < wav[0][1].length && index >= 0) ? wav[0][1][index] : 0) * (bandW / 1.12), -hSize, hSize) / 2;

			var rmin:Float = FlxMath.bound(((index < wav[1][0].length && index >= 0) ? wav[1][0][index] : 0) * (bandW / 1.12), -hSize, hSize) / 2;
			var rmax:Float = FlxMath.bound(((index < wav[1][1].length && index >= 0) ? wav[1][1][index] : 0) * (bandW / 1.12), -hSize, hSize) / 2;

			waveformSprite.pixels.fillRect(new Rectangle(xStart + hSize - (lmin + rmin), yOffset + index * size, (lmin + rmin) + (lmax + rmax), size), color);
		}
	}

	function waveformData(buffer:AudioBuffer, bytes:Bytes, time:Float, endTime:Float, multiply:Float = 1, ?array:Array<Array<Array<Float>>>,
			?steps:Float):Array<Array<Array<Float>>>
	{
		#if (lime_cffi && !macro)
		if (buffer == null || buffer.data == null)
			return [[[0], [0]], [[0], [0]]];

		var khz:Float = (buffer.sampleRate / 1000);
		var channels:Int = buffer.channels;

		var index:Int = Std.int(time * khz);

		var samples:Float = ((endTime - time) * khz);

		if (steps == null)
			steps = 1280;

		var samplesPerRow:Float = samples / steps;
		var samplesPerRowI:Int = Std.int(samplesPerRow);

		var gotIndex:Int = 0;

		var lmin:Float = 0;
		var lmax:Float = 0;

		var rmin:Float = 0;
		var rmax:Float = 0;

		var rows:Float = 0;

		var simpleSample:Bool = true; // samples > 17200;
		var v1:Bool = false;

		if (array == null)
			array = [[[0], [0]], [[0], [0]]];

		while (index < (bytes.length - 1))
		{
			if (index >= 0)
			{
				var byte:Int = bytes.getUInt16(index * channels * 2);

				if (byte > 65535 / 2)
					byte -= 65535;

				var sample:Float = (byte / 65535);

				if (sample > 0)
					if (sample > lmax)
						lmax = sample;
					else if (sample < 0)
						if (sample < lmin)
							lmin = sample;

				if (channels >= 2)
				{
					byte = bytes.getUInt16((index * channels * 2) + 2);

					if (byte > 65535 / 2)
						byte -= 65535;

					sample = (byte / 65535);

					if (sample > 0)
					{
						if (sample > rmax)
							rmax = sample;
					}
					else if (sample < 0)
					{
						if (sample < rmin)
							rmin = sample;
					}
				}
			}

			v1 = samplesPerRowI > 0 ? (index % samplesPerRowI == 0) : false;
			while (simpleSample ? v1 : rows >= samplesPerRow)
			{
				v1 = false;
				rows -= samplesPerRow;

				gotIndex++;

				var lRMin:Float = Math.abs(lmin) * multiply;
				var lRMax:Float = lmax * multiply;

				var rRMin:Float = Math.abs(rmin) * multiply;
				var rRMax:Float = rmax * multiply;

				if (gotIndex > array[0][0].length)
					array[0][0].push(lRMin);
				else
					array[0][0][gotIndex - 1] = array[0][0][gotIndex - 1] + lRMin;

				if (gotIndex > array[0][1].length)
					array[0][1].push(lRMax);
				else
					array[0][1][gotIndex - 1] = array[0][1][gotIndex - 1] + lRMax;

				if (channels >= 2)
				{
					if (gotIndex > array[1][0].length)
						array[1][0].push(rRMin);
					else
						array[1][0][gotIndex - 1] = array[1][0][gotIndex - 1] + rRMin;

					if (gotIndex > array[1][1].length)
						array[1][1].push(rRMax);
					else
						array[1][1][gotIndex - 1] = array[1][1][gotIndex - 1] + rRMax;
				}
				else
				{
					if (gotIndex > array[1][0].length)
						array[1][0].push(lRMin);
					else
						array[1][0][gotIndex - 1] = array[1][0][gotIndex - 1] + lRMin;

					if (gotIndex > array[1][1].length)
						array[1][1].push(lRMax);
					else
						array[1][1][gotIndex - 1] = array[1][1][gotIndex - 1] + lRMax;
				}

				lmin = 0;
				lmax = 0;

				rmin = 0;
				rmax = 0;
			}

			index++;
			rows++;
			if (gotIndex > steps)
				break;
		}

		return array;
		#else
		return [[[0], [0]], [[0], [0]]];
		#end
	}

	function changeNoteSustain(value:Float):Void
	{
		beginHistoryAction('history_change_sustain');
		if (curSelectedNote != null)
		{
			if (curSelectedNote[2] != null)
			{
				curSelectedNote[2] += Math.ceil(value);
				curSelectedNote[2] = Math.max(curSelectedNote[2], 0);
			}
		}

		updateNoteUI();
		updateGrid();
		commitHistoryAction();
	}

	function recalculateSteps(add:Float = 0):Int
	{
		var lastChange:BPMChangeEvent = {
			stepTime: 0,
			songTime: 0,
			bpm: 0
		}
		for (i in 0...Conductor.bpmChangeMap.length)
		{
			if (FlxG.sound.music.time > Conductor.bpmChangeMap[i].songTime)
				lastChange = Conductor.bpmChangeMap[i];
		}

		curStep = lastChange.stepTime + Math.floor((FlxG.sound.music.time - lastChange.songTime + add) / Conductor.stepCrochet);
		updateBeat();

		return curStep;
	}

	function resetSection(songBeginning:Bool = false):Void
	{
		updateGrid();

		FlxG.sound.music.pause();
		// Basically old shit from changeSection???
		FlxG.sound.music.time = sectionStartTime();

		if (songBeginning)
		{
			FlxG.sound.music.time = 0;
			curSec = 0;
		}

		pauseAndSetVocalsTime();
		updateCurStep();

		updateGrid();
		updateSectionUI();
		updateWaveform();
	}

	function changeSection(sec:Int = 0, ?updateMusic:Bool = true):Void
	{
		if (_song.notes[sec] != null)
		{
			curSec = sec;
			if (updateMusic)
			{
				FlxG.sound.music.pause();

				FlxG.sound.music.time = sectionStartTime();
				pauseAndSetVocalsTime();
				updateCurStep();
			}

			// ★ 全谱渲染后网格/底色与 curSec 无关（换边小节的 laneBg 本来就各自着色），
			//   换小节绝不需要重建 —— 只同步 BPM + 刷高亮 + 更新 UI。
			//   （旧 blah1/blah2/sideChanged 触发的 reloadGridLayer 整谱重建 =
			//   「换 BF/Opp 小节雷霆大卡顿」的元凶，已移除）
			syncConductorBPM();
			refreshNoteHighlight();
			updateSectionUI();

			// ★ 跳到新小节 → 让渲染窗口把「curSec ± 1」纳入（最小化重建量，见 refreshRenderWindow）
			refreshRenderWindow();
		}
		else
		{
			// sec 越界（static curSec 残留 / 换短谱）：钳到 0 重试一次，避免无限递归
			if (sec != 0 && _song.notes.length > 0)
				changeSection(0, updateMusic);
			return;
		}
		Conductor.songPosition = FlxG.sound.music.time;
		updateWaveform();
	}

	function updateSectionUI():Void
	{
		// ★ static curSec 可能越界（换难度/短谱）→ 安全钳制后再取，防原生崩溃
		var sec = curSectionSafe();
		if (sec == null) return;

		stepperBeats.value = getSectionBeats();
		check_mustHitSection.checked = sec.mustHitSection;
		check_gfSection.checked = sec.gfSection;
		check_altAnim.checked = sec.altAnim;
		check_changeBPM.checked = sec.changeBPM;
		stepperSectionBPM.value = sec.bpm;

		updateHeads();
	}

	var characterData:Dynamic = {
		iconP1: null,
		iconP2: null,
		vocalsP1: null,
		vocalsP2: null,
		healthP1: null,
		healthP2: null
	};

	/** 角色颜色缓存：icon 名 → 主色（-1 = 未算出）。仅用于兜底，与屏幕头像状态无关 */
	var charColorCache:Map<String, Int> = new Map<String, Int>();

	function updateJsonData():Void
	{
		for (i in 1...3)
		{
			var data:CharacterFile = loadCharacterFile(Reflect.field(_song, 'player$i'));
			Reflect.setField(characterData, 'iconP$i', !characterFailed ? data.healthicon : 'face');
			Reflect.setField(characterData, 'vocalsP$i', data.vocals_file != null ? data.vocals_file : '');
			// ★ 缓存角色 JSON 的 healthbar_colors（Psych 标准），供背景/波形取色
			var hb:Array<Int> = null;
			if (!characterFailed && data.healthbar_colors != null && data.healthbar_colors.length > 2)
				hb = data.healthbar_colors;
			Reflect.setField(characterData, 'healthP$i', hb);
		}
	}

	var curLeftIconName:String = '';
	var curRightIconName:String = '';

	/** ★ 09-26 二轮（用户要求）：BF/Opp 头像位置固定 —— 左 = player1(BF)，右 = player2(Opp)。
	 *  切换 BF/Opp 小节时不再交换头像、也不换整片底色：只移动「摄像机图标」camIcon
	 *  （见 updateSideIconsFollow）。gfSection 仍让左头像临时显示 GF。 */
	function updateHeads():Void
	{
		if (leftIcon == null || rightIcon == null) return;
		var secObj:Dynamic = curSectionSafe();
		var gf:Bool = (secObj != null && secObj.gfSection == true);
		var lName:String = gf ? 'gf' : characterData.iconP1;
		var rName:String = characterData.iconP2;
		if (lName == null) lName = 'face';
		if (rName == null) rName = 'face';

		// ★ 同名不重复 changeIcon（播放跨小节时每小节都会调用，重载贴图会明显掉帧/抖动）
		if (lName != curLeftIconName)
		{
			leftIcon.changeIcon(lName);
			curLeftIconName = lName;
		}
		if (rName != curRightIconName)
		{
			rightIcon.changeIcon(rName);
			curRightIconName = rName;
		}
		positionSideIcons(); // ★ 换图后图标宽度可能变化，重新居中到各自轨道组
	}

	var characterFailed:Bool = false;

	function loadCharacterFile(char:String):CharacterFile
	{
		characterFailed = false;
		var characterPath:String = 'characters/' + char + '.json';
		#if MODS_ALLOWED
		var path:String = Paths.modFolders(characterPath);
		if (!FileSystem.exists(path))
		{
			path = Paths.getSharedPath(characterPath);
		}

		if (!FileSystem.exists(path))
		#else
		var path:String = Paths.getSharedPath(characterPath);
		if (!Assets.exists(path))
		#end
		{
			path = Paths.getSharedPath('characters/' + Character.DEFAULT_CHARACTER +
				'.json'); // If a character couldn't be found, change him to BF just to prevent a crash
			characterFailed = true;
		}

		#if MODS_ALLOWED
		var rawJson = File.getContent(path);
		#else
		var rawJson = Assets.getText(path);
		#end
		return cast Json.parse(rawJson);
	}

	function updateNoteUI():Void
	{
		if (curSelectedNote != null)
		{
			if (curSelectedNote[2] != null)
			{
				stepperSusLength.value = curSelectedNote[2];
				if (curSelectedNote[3] != null)
				{
					currentType = curNoteTypes.indexOf(curSelectedNote[3]);
					if (currentType <= 0)
					{
						noteTypeDropDown.selectedLabel = '';
					}
					else
					{
						noteTypeDropDown.selectedLabel = currentType + '. ' + curSelectedNote[3];
					}
				}
			}
			else if (Std.is(curSelectedNote[1], Array))
			{
				// ★ 崩溃防御：只有事件 note（[1] 为数组）才走事件读取，普通 note 的 [1] 是数字轨道号
				var evArr4:Array<Dynamic> = cast curSelectedNote[1];
				if (curEventSelected >= 0 && curEventSelected < evArr4.length && Std.is(evArr4[curEventSelected], Array))
				{
					var evD4:Array<Dynamic> = cast evArr4[curEventSelected];
					if (evD4.length > 0) eventDropDown.selectedLabel = evD4[0];
					var selected:Null<Int> = null;
					try { selected = Std.parseInt(eventDropDown.selectedId); } catch(e:Dynamic) { selected = null; }
					if (selected != null && selected >= 0 && selected < eventStuff.length)
					{
						descText.text = eventStuff[selected][1];
					}
					if (evD4.length > 1) value1InputText.text = evD4[1];
					if (evD4.length > 2) value2InputText.text = evD4[2];
				}
			}
			strumTimeInputText.text = '' + curSelectedNote[0];
		}
	}


	// ★ 全谱渲染缓存：小节索引 → 该小节的音符/受体/类型文本 sprite
	//   （09-26 二轮：改成「相机窗口虚拟化」，见 refreshRenderWindow / buildSecNotes）

	function updateGrid(?withNext:Bool = true):Void
	{
		// ★ 语义（09-26 二轮 / 虚拟化）：
		//   withNext=true  → 所有小节的数据都视为失效（销毁当前已渲染的，新的在进窗口时再建）；
		//   withNext=false → 只有当前小节失效。
		//   32787 音符的谱面下「整个重建」是不可能的，因此这里只做「失效 + 重画窗口」。
		if (_song == null || _song.notes == null || _song.notes.length <= 0) return;

		metricsDirty = true;
		ensureMetrics();

		// ★ curSec 是 static，可能越界（换难度/短谱）→ 一律走安全访问，绝不能裸取 notes[curSec]
		clampCurSec();
		var curSecObj:Dynamic = _song.notes[curSec];
		if (curSecObj != null && curSecObj.changeBPM && curSecObj.bpm > 0)
		{
			Conductor.bpm = curSecObj.bpm;
		}
		else
		{
			Conductor.bpm = secBpmCache.length > 0 ? secBpmCache[secClamp(curSec)] : _song.bpm;
		}

		if (withNext)
			destroyAllSecNotes();
		else
			destroySecNotes(curSec);

		refreshRenderWindow(true);

		minimapDirty = true; // 音符变了 → 缩略图重画（节流，见 minimapUpdate）
		minimapCooldown = 0.3;
	}

	function refreshNoteHighlight():Void
	{
		var curTop:Float = secRowStartPx(curSec);
		var curBottom:Float = curTop + curSecHeightPx();
		curRenderedNotes.forEachAlive(function(note:Note)
		{
			note.alpha = (note.y >= curTop && note.y < curBottom) ? 1 : 0.6;
		});
		curRenderedSustains.forEachAlive(function(sus:FlxSprite)
		{
			sus.alpha = (sus.y >= curTop && sus.y < curBottom) ? 1 : 0.6;
		});
	}

	function setupNoteData(i:Array<Dynamic>, secIdx:Int):Note
	{
		var daNoteInfo = i[1];
		var daStrumTime = i[0];
		var daSus:Dynamic = i[2];

		// ★ 事件音符的 i[1] 是数组（[事件名, 值1, 值2 …]），旧代码直接 `daNoteInfo % leftKeys`
		//   对 Dynamic 取模，得到的轨号是垃圾值；它决定了构造期取哪条轨道的配色/缩放，
		//   随后虽然会被改回 -1，但构造期已经用错误轨号建过 RGB palette 与动画了。
		//   这里先归一成安全轨号（非数字一律 0）。
		var laneForNote:Int = 0;
		var hasLane:Bool = (Std.isOfType(daNoteInfo, Int) || Std.isOfType(daNoteInfo, Float));
		// ★ 09-26 十一轮：事件音符的判定以「实际走了哪个分支」为准。
		//   只靠 hasLane（i[1] 是不是数字）在某些事件格式下会误判 → 箭头被当成普通音符打到 lane 0，
		//   于是「事件图标压在音符上」。
		var isEventNote:Bool = false;
		if (hasLane)
		{
			var laneNum:Int = Std.int(cast daNoteInfo);
			laneForNote = (leftKeys > 0) ? (laneNum % leftKeys) : 0;
			if (laneForNote < 0) laneForNote += leftKeys;
		}

		// ★ 09-26 三轮：与 PlayState.generateSong 完全一致的「侧」判定 ——
		//   mustPress(= 该音符属于玩家/BF)：经典格式 mustHitSection，且 lane >= leftKeys 时取反；
		//   编辑器固定「玩家侧在左、对手侧在右」，所以显示轨号 = (mustPress ? 0 : leftKeys) + lane % leftKeys。
		//   旧版直接拿原始 lane 当列号，在 mustHitSection=false 的小节会把两侧写反
		//   （用户反馈「BF 小节的东西跑到 Opp 一侧」）。
		var secMustHit:Bool = true;
		if (secIdx >= 0 && secIdx < _song.notes.length && _song.notes[secIdx] != null)
			secMustHit = _song.notes[secIdx].mustHitSection;
		var laneNumRaw:Int = hasLane ? Std.int(cast daNoteInfo) : 0;
		var noteMustPress:Bool = dataLaneIsPlayer(laneNumRaw, secMustHit);
		var dispLane:Int = noteMustPress ? laneForNote : (laneForNote + leftKeys);
		if (dispLane < 0) dispLane = 0;
		if (totalKeys > 0 && dispLane >= totalKeys) dispLane = totalKeys - 1;

		var note:Note = new Note(daStrumTime, laneForNote, null, null, true);
		if (daSus != null)
		{ // Common note
			if (!Std.isOfType(i[3], String)) // Convert old note type to new note type format
			{
				// ★ 防御：i[3] 可能是 null（旧谱面无类型字段）→ 不能直接索引 curNoteTypes
				var oldTypeIdx:Int = Std.is(i[3], Int) || Std.is(i[3], Float) ? Std.int(i[3]) : 0;
				if (oldTypeIdx >= 0 && oldTypeIdx < curNoteTypes.length)
					i[3] = curNoteTypes[oldTypeIdx];
				else
					i[3] = null;
			}
			if (i.length > 3 && (i[3] == null || i[3].length < 1))
			{
				i.remove(i[3]);
			}
			note.sustainLength = daSus;
			note.noteType = i[3];
		}
		else if (Std.is(i[1], Array))
		{ // Event note（★ 判定必须用 [1] 是否为数组：普通音符的 [1] 是轨道号 Int，
			//   [2]==null 不可靠——旧谱面普通音符 susLength 缺失时会把 Int 当数组 → 空指针崩溃）
			var evArr:Array<Dynamic> = cast i[1];
			if (evArr == null) evArr = [];
			note.loadGraphic(Paths.image('eventArrow'));
			note.rgbShader.enabled = false;
			note.eventName = getEventName(evArr);
			note.eventLength = evArr.length;
			if (evArr.length < 2 && evArr.length > 0 && Std.is(evArr[0], Array))
			{
				var ev0:Array<Dynamic> = cast evArr[0];
				if (ev0.length > 1) note.eventVal1 = ev0[1];
				if (ev0.length > 2) note.eventVal2 = ev0[2];
			}
			note.noteData = -1;
			daNoteInfo = -1;
			isEventNote = true;
		}
		else
		{ // 普通音符但 susLength 缺失（旧谱面）——按普通音符兜底，避免误入事件分支
			note.sustainLength = 0;
			note.noteData = daNoteInfo;
		}

		note.setGraphicSize(GRID_SIZE, GRID_SIZE);
		note.updateHitbox();
		note.origin.set(0, 0);
		note.offset.set(0, 0);
		// ★ x 用「显示轨号」（玩家侧恒在左半），不再用原始 lane 直接当列号
		if (isEventNote)
			// ★ 十二轮：紧贴网格左外侧一格 + 6px（原来 -2格-10 离得太远，用户反馈"事件的 UI 与点击位置太远"）
			note.x = getGridX() - GRID_SIZE - EditorInputStyle.sv(6);
		else
			note.x = getGridX() + dispLane * GRID_SIZE + GRID_SIZE;
		note.mustPress = noteMustPress;

		// ★ 绝对坐标：y = 该小节顶部偏移 + (小节内局部时间 / 该小节时长) × 该小节像素高
		var secLen:Float = sectionLenMsAt(secIdx);
		if (secLen <= 0) secLen = 1;
		var localT:Float = daStrumTime - sectionStartTimeAt(secIdx);
		var secPx:Float = secRowsAt(secIdx) * GRID_SIZE;
		note.y = secRowStartPx(secIdx) + (localT / secLen) * secPx;
		// 兼容负 offset 音符（第一小节开头往前一点的音），别飞出网格太远
		if (note.y < -150)
			note.y = -150;
		noteOwners.set(note, secIdx);
		return note;
	}

	function getEventName(names:Array<Dynamic>):String
	{
		var retStr:String = '';
		var addedOne:Bool = false;
		for (i in 0...names.length)
		{
			if (addedOne)
				retStr += ', ';
			retStr += names[i][0];
			addedOne = true;
		}
		return retStr;
	}

	function setupSusNote(note:Note, stepMs:Float):FlxSprite
	{
		// ★ 全谱渲染：受体高度按「该小节自己的 step 时长」换算（换 BPM 的小节受体不再错位）。
		//   旧实现等价于 stepMs = Conductor.stepCrochet 且单小节网格，now 传入 sectionStepMsAt(s)。
		if (stepMs <= 0) stepMs = Conductor.stepCrochet > 0 ? Conductor.stepCrochet : 1;
		var height:Int = Math.floor((note.sustainLength / stepMs) * GRID_SIZE * zoomList[curZoom]
			+ (GRID_SIZE * zoomList[curZoom])
			- GRID_SIZE / 2);
		var minHeight:Int = Std.int((GRID_SIZE * zoomList[curZoom] / 2) + GRID_SIZE / 2);
		if (height < minHeight)
			height = minHeight;
		if (height < 1)
			height = 1; // Prevents error of invalid height

		var spr:FlxSprite = new FlxSprite(note.x + (GRID_SIZE * 0.5) - 4, note.y + GRID_SIZE / 2).makeGraphic(8, height);
		return spr;
	}

	private function addSection(sectionBeats:Float = 4):Void
	{
		var recordHistory = historyIndex >= 0;
		if (recordHistory) beginHistoryAction('history_edit_chart');
		var sec:SwagSection = {
			sectionBeats: sectionBeats,
			bpm: _song.bpm,
			changeBPM: false,
			mustHitSection: true,
			gfSection: false,
			sectionNotes: [],
			altAnim: false
		};

		_song.notes.push(sec);
		if (recordHistory) commitHistoryAction();
	}

	function selectNote(note:Note):Void
	{
		lastHistoryKey = null;
		var sourceSection = noteSourceSection(note);
		if (sourceSection < 0 || sourceSection >= _song.notes.length || _song.notes[sourceSection] == null) return;
		var noteDataToCheck:Int = note.noteData;

		if (noteDataToCheck > -1)
		{
			noteDataToCheck = displayLaneToData(noteDisplayLane(note), _song.notes[sourceSection].mustHitSection);
			for (i in _song.notes[sourceSection].sectionNotes)
			{
				if (i != curSelectedNote && i.length > 2 && i[0] == note.strumTime && i[1] == noteDataToCheck)
				{
					curSelectedNote = i;
					break;
				}
			}
		}
		else
		{
			for (i in _song.events)
			{
				if (i != curSelectedNote && i[0] == note.strumTime)
				{
					curSelectedNote = i;
					// ★ 防御：事件音符 [1] 应为数组（谱面数据损坏时避免对 Int 取 length）
					if (Std.is(curSelectedNote[1], Array))
						curEventSelected = Std.int((cast curSelectedNote[1]:Array<Dynamic>).length) - 1;
					else
						curEventSelected = 0;
					break;
				}
			}
		}
		changeEventSelected();

		updateGrid();
		updateNoteUI();
	}

	function deleteNote(note:Note):Void
	{
		var sourceSection = noteSourceSection(note);
		if (sourceSection < 0 || sourceSection >= _song.notes.length || _song.notes[sourceSection] == null) return;
		beginHistoryAction('history_delete_item');
		var noteDataToCheck:Int = note.noteData;
		if (noteDataToCheck > -1)
			noteDataToCheck = displayLaneToData(noteDisplayLane(note), _song.notes[sourceSection].mustHitSection);

		if (note.noteData > -1) // Normal Notes
		{
			for (i in _song.notes[sourceSection].sectionNotes)
			{
				if (i[0] == note.strumTime && i[1] == noteDataToCheck)
				{
					if (i == curSelectedNote)
						curSelectedNote = null;
					// FlxG.log.add('FOUND EVIL NOTE');
					_song.notes[sourceSection].sectionNotes.remove(i);
					break;
				}
			}
		}
		else // Events
		{
			for (i in _song.events)
			{
				if (i[0] == note.strumTime)
				{
					if (i == curSelectedNote)
					{
						curSelectedNote = null;
						changeEventSelected();
					}
					// FlxG.log.add('FOUND EVIL EVENT');
					_song.events.remove(i);
					break;
				}
			}
		}

		updateGrid();
		commitHistoryAction();
	}

	public function doANoteThing(cs, d, style)
	{
		// ★ 索引守护：mania 键数 < 8 时 strumLineNotes.members[d] 会越界（cpp 下直接崩）
		if (strumLineNotes == null || d == null || d < 0 || d >= strumLineNotes.length) return;
		var delnote = false;
		if (strumLineNotes.members[d].overlaps(curRenderedNotes))
		{
			curRenderedNotes.forEachAlive(function(note:Note)
			{
				// ★ 比较「显示轨号」（网格列），而不是数据 lane —— 对手小节两者是互换的
				if (note.overlapsPoint(FlxPoint.weak(strumLineNotes.members[d].x + 1, strumLine.y + 1)) && noteDisplayLane(note) == d)
				{
					// trace('tryin to delete note...');
					if (!delnote)
						deleteNote(note);
					delnote = true;
				}
			});
		}

		if (!delnote)
		{
			addNote(cs, d, style);
		}
	}

	function clearSong():Void
	{
		for (daSection in 0..._song.notes.length)
		{
			_song.notes[daSection].sectionNotes = [];
		}

		updateGrid();
	}

	private function addNote(strum:Null<Float> = null, data:Null<Int> = null, type:Null<Int> = null):Void
	{
		// curUndoIndex++;
		// var newsong = _song.notes;
		//	undos.push(newsong);
		// ★ 全谱坐标（09-26 二轮）：dummyArrow.y / strum 都是【整曲绝对】坐标。
		//   音符必须加进「它自己所属的小节」——旧版一律 push 给 curSec，
		//   在别的小节点击/拖动会写出时间与所属小节不匹配的坏数据。
		var noteStrum = getStrumTime(dummyArrow.y, false);
		var noteData = 0;
		// if (ClientPrefs.data.needMobileControl) {
		// for (touch in FlxG.touches.list){noteData = Math.floor((touch.x - GRID_SIZE) / GRID_SIZE);}
		// } else {
		noteData = Math.floor((FlxG.mouse.getWorldPosition(FlxG.camera).x - getGridX() - GRID_SIZE) / GRID_SIZE);
		// }
		var noteSus = 0;
		var daAlt = false;
		var daType = currentType;

		if (strum != null)
			noteStrum = strum;
		if (data != null)
			noteData = data;
		if (type != null)
			daType = type;

		// ★ 目标小节 = 绝对时间所属的小节（跨小节点击/拖动时不会写坏数据）
		if (_song.notes.length > 0)
		{
			var targetSec:Int = findSectionAtTime(noteStrum);
			if (targetSec < 0) targetSec = 0;
			if (targetSec >= _song.notes.length) targetSec = _song.notes.length - 1;
			if (targetSec != curSec)
				changeSection(targetSec, false);
		}
		if (_song.notes[curSec] == null) return;
		beginHistoryAction('history_add_item');

		// ★ 显示轨号 → 数据 lane（对手小节左右互换）：点击/按键给出的都是「网格上的列号」，
		//   而 sectionNotes 里存的是「数据 lane」（0..3 = 本小节 mustHitSection 那一方）。
		if (noteData > -1)
		{
			var targetMustHit:Bool = (_song.notes[curSec].mustHitSection != false);
			noteData = displayLaneToData(noteData, targetMustHit);
		}

		if (noteData > -1)
		{
			_song.notes[curSec].sectionNotes.push([noteStrum, noteData, noteSus, curNoteTypes[daType]]);
			curSelectedNote = _song.notes[curSec].sectionNotes[_song.notes[curSec].sectionNotes.length - 1];
		}
		else
		{
			// ★ 防御：eventDropDown.selectedId 可能是空/非数字 → Std.parseInt 返回 null →
			//   eventStuff[null] 取 [0] 会空指针崩溃，先解析并校验索引
			var eventId:Null<Int> = null;
			try { eventId = Std.parseInt(eventDropDown.selectedId); } catch(e:Dynamic) { eventId = null; }
			var evName:String = '';
			if (eventId != null && eventId >= 0 && eventId < eventStuff.length)
				evName = eventStuff[eventId][0];
			var text1 = value1InputText.text;
			var text2 = value2InputText.text;
			_song.events.push([noteStrum, [[evName, text1, text2]]]);
			curSelectedNote = _song.events[_song.events.length - 1];
			curEventSelected = 0;
		}
		changeEventSelected();

		// ★ 自定义移动键位模式下不自动双放（Ctrl 来自虚拟组合键，同帧可能误触发对侧复制）
		//   对侧复制 = 在同一显示位置镜像到另一半轨道组（对手小节再换算回数据 lane）
		if (FlxG.keys.pressed.CONTROL && noteData > -1)
		{
			var curMustHit:Bool = (_song.notes[curSec].mustHitSection != false);
			var dispLane:Int = dataLaneToDisplay(noteData, curMustHit);
			var mirrorDisp:Int = totalKeys > 0 ? (dispLane + leftKeys) % totalKeys : dispLane;
			var mirrorData:Int = displayLaneToData(mirrorDisp, curMustHit);
			_song.notes[curSec].sectionNotes.push([noteStrum, mirrorData, noteSus, curNoteTypes[daType]]);
		}

		// trace(noteData + ', ' + noteStrum + ', ' + curSec);
		strumTimeInputText.text = '' + curSelectedNote[0];

		updateGrid();
		updateNoteUI();
		commitHistoryAction();
	}

	/** JSON is the chart's canonical model, so history snapshots include metadata, sections, notes and events. */
	function chartHistorySnapshot():String
	{
		return _song == null ? '' : EditorDocumentHistory.jsonSnapshot({song: _song,
			format: Song.detectedFormat, engine: Song.chartEngineVersion, forceEngine: Song.forceEngineVersion});
	}

	function resetChartHistory(?label:String = 'history_opened_chart'):Void
	{
		pendingHistorySnapshot = null;
		pendingHistoryLabel = '';
		historyFrames = [];
		historyIndex = -1;
		if (_song != null)
		{
			historyFrames.push({label: label, snapshot: chartHistorySnapshot()});
			historyIndex = 0;
			savedChartSnapshot = historyFrames[0].snapshot;
		}
		historyActionDepth = 0;
		lastHistoryCommitAt = 0;
		refreshHistoryPanel();
	}

	function beginHistoryAction(label:String, ?key:String):Void
	{
		if (_song == null) return;
		if (historyFrames == null || historyFrames.length == 0) resetChartHistory();
		if (pendingHistorySnapshot == null)
		{
			pendingHistorySnapshot = chartHistorySnapshot();
			pendingHistoryLabel = label;
			pendingHistoryKey = key;
		}
		historyActionDepth++;
	}

	function commitHistoryAction():Void
	{
		if (pendingHistorySnapshot == null) return;
		if (historyActionDepth > 0) historyActionDepth--;
		if (historyActionDepth > 0) return;
		var before = pendingHistorySnapshot;
		var label = pendingHistoryLabel;
		var key = pendingHistoryKey;
		pendingHistorySnapshot = null;
		pendingHistoryLabel = '';
		pendingHistoryKey = null;
		historyActionDepth = 0;
		var after = chartHistorySnapshot();
		if (before == after) return;

		if (historyIndex < historyFrames.length - 1)
			historyFrames = historyFrames.slice(0, historyIndex + 1);
		var now:Float = haxe.Timer.stamp();
		var coalesce:Bool = key != null && key == lastHistoryKey && historyIndex > 0 && historyFrames[historyIndex].label == label
			&& now - lastHistoryCommitAt < 0.65;
		if (coalesce)
			historyFrames[historyIndex].snapshot = after;
		else
		{
			historyFrames.push({label: label, snapshot: after});
			historyIndex = historyFrames.length - 1;
		}
		lastHistoryCommitAt = now;
		lastHistoryKey = key;
		while (historyFrames.length > MAX_CHART_HISTORY)
		{
			historyFrames.shift();
			historyIndex--;
		}
		refreshHistoryPanel();
	}

	function withHistoryAction(label:String, action:Void->Void):Void
	{
		beginHistoryAction(label);
		try action() catch (e:Dynamic)
		{
			commitHistoryAction();
			throw e;
		}
		commitHistoryAction();
	}

	function refreshHistoryPanel():Void
	{
		if (historyPanel == null) return;
		var labels:Array<String> = [];
		for (frame in historyFrames)
		{
			var label:String = Language.get(frame.label, 'charting');
			if (label == frame.label || label.indexOf('(404)') != -1)
				label = frame.label;
			labels.push(label);
		}
		historyPanel.setEntries(labels, historyIndex);
	}

	function restoreHistoryFrame(index:Int):Void
	{
		if (index < 0 || index >= historyFrames.length) return;
		var position:Float = FlxG.sound.music != null ? FlxG.sound.music.time : 0;
		var selectedSection:Int = -1;
		var selectedRow:Int = -1;
		var selectedEventRow:Int = -1;
		if (curSelectedNote != null)
		{
			if (Std.is(curSelectedNote[1], Array))
			{
				if (_song.events != null) selectedEventRow = _song.events.indexOf(curSelectedNote);
			}
			else if (_song.notes != null)
			{
				for (i in 0..._song.notes.length)
				{
					var rows:Array<Dynamic> = _song.notes[i] != null ? _song.notes[i].sectionNotes : null;
					if (rows != null)
					{
						var row:Int = rows.indexOf(curSelectedNote);
						if (row >= 0)
						{
							selectedSection = i;
							selectedRow = row;
							break;
						}
					}
				}
			}
		}
		var savedFormat:String = Song.detectedFormat;
		var savedEngine:String = Song.chartEngineVersion;
		var restored:SwagSong = null;
		var restoredDocument:Dynamic = null;
		try
		{
			restoredDocument = haxe.Json.parse(historyFrames[index].snapshot);
			restored = cast restoredDocument.song;
		}
		catch (e:Dynamic) {}
		Song.detectedFormat = savedFormat;
		Song.chartEngineVersion = savedEngine;
		if (restored == null) return;
		Song.detectedFormat = restoredDocument.format;
		Song.chartEngineVersion = restoredDocument.engine;
		Song.forceEngineVersion = restoredDocument.forceEngine;
		var wasPlaying = FlxG.sound.music != null && FlxG.sound.music.playing;
		if (FlxG.sound.music != null) FlxG.sound.music.pause();

		_song = restored;
		PlayState.SONG = _song;
		Conductor.mapBPMChanges(_song);
		historyActionDepth = 0;
		lastHistoryCommitAt = 0;
		lastHistoryKey = null;
		curSelectedNote = null;
		if (selectedEventRow >= 0 && _song.events != null && selectedEventRow < _song.events.length)
			curSelectedNote = _song.events[selectedEventRow];
		else if (selectedSection >= 0 && selectedSection < _song.notes.length && selectedRow >= 0
			&& _song.notes[selectedSection].sectionNotes != null && selectedRow < _song.notes[selectedSection].sectionNotes.length)
			curSelectedNote = _song.notes[selectedSection].sectionNotes[selectedRow];
		historyIndex = index;
		pendingHistorySnapshot = null;
		pendingHistoryLabel = '';
		clampCurSec();
		updateJsonData();
		recalcKeyAmounts();
		reloadGridLayer();
		makeStrumNotes();
		updateHeads();
		changeSection(curSec, false);
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.time = FlxMath.bound(position, 0, FlxG.sound.music.length);
			pauseAndSetVocalsTime();
			if (wasPlaying)
			{
				FlxG.sound.music.resume();
				if (vocals != null) vocals.play();
				if (opponentVocals != null) opponentVocals.play();
			}
		}
		refreshMenuWidgets('song');
		refreshMenuWidgets('section');
		refreshMenuWidgets('note');
		refreshMenuWidgets('event');
		refreshMenuWidgets('data');
		changeEventSelected();
		updateNoteUI();
		refreshHistoryPanel();
	}

	function jumpToHistory(index:Int):Void
	{
		commitHistoryAction();
		restoreHistoryFrame(index);
	}

	function pushUndo(?label:String = 'Edit chart'):Void
	{
		beginHistoryAction(label);
	}

	function redo():Void
	{
		if (historyIndex < 0 || historyIndex >= historyFrames.length - 1) return;
		restoreHistoryFrame(historyIndex + 1);
	}

	function undo():Void
	{
		commitHistoryAction();
		if (historyIndex <= 0) return;
		restoreHistoryFrame(historyIndex - 1);
	}

	/** ★ 整曲绝对 y → 整曲绝对时间（ms）。
	 *  09-26 二轮：按「yPos 自己所属的小节」换算 —— 旧版固定用 curSec 的顶部/高度，
	 *  鼠标点在别的小节上会算出完全错误的时间。与 strumLineUpdateY / setupNoteData 同一映射。 */
	function getStrumTime(yPos:Float, doZoomCalc:Bool = true):Float
	{
		ensureMetrics();
		if (secTopCache.length <= 0) return 0;
		var sec:Int = findSectionAtY(yPos);
		var top:Float = secTopCache[sec];
		var secPx:Float = secRowsCache[sec] * GRID_SIZE;
		if (secPx <= 0) secPx = 1;
		return secMsCache[sec] + ((yPos - top) / secPx) * secLenCache[sec];
	}

	/** ★ 整曲绝对时间（ms）→ 整曲绝对 y（与上面互逆） */
	function getYfromStrum(strumTime:Float, doZoomCalc:Bool = true):Float
	{
		ensureMetrics();
		if (secTopCache.length <= 0) return 0;
		var sec:Int = findSectionAtTime(strumTime);
		var len:Float = secLenCache[sec];
		if (len <= 0) return secTopCache[sec];
		var frac:Float = (strumTime - secMsCache[sec]) / len;
		return secTopCache[sec] + frac * secRowsCache[sec] * GRID_SIZE;
	}

	function getNotes():Array<Dynamic>
	{
		var noteData:Array<Dynamic> = [];

		for (i in _song.notes)
		{
			noteData.push(i.sectionNotes);
		}

		return noteData;
	}

	var missingText:FlxText;
	var missingTextTimer:FlxTimer;

	function loadJson(song:String):Void
	{
		// ★ 难度后缀取自【歌曲】→「难度」输入框：填了 Fuck 就加载 song-Fuck.json（制作多难度用）；
		//   留空则加载无后缀文件（不再受全局 Difficulty 影响——之前会莫名拼难度后缀导致"重载无效"）
		try
		{
			var diff:String = (difficultyInputText != null && difficultyInputText.text != null) ? StringTools.trim(difficultyInputText.text) : '';
			if (diff.length > 0)
				PlayState.SONG = Song.loadFromJson(song.toLowerCase() + '-' + Paths.formatToSongPath(diff), song.toLowerCase());
			else
				PlayState.SONG = Song.loadFromJson(song.toLowerCase(), song.toLowerCase());
			MusicBeatState.resetState();
		}
		catch (e)
		{
			trace('ERROR! $e');

			var errorStr:String = e.toString();
			if (errorStr.startsWith('[file_contents,assets/data/'))
				errorStr = 'Missing file: ' + errorStr.substring(27, errorStr.length - 1); // Missing chart

			if (missingText == null)
			{
				missingText = new EditorText(50, 0, FlxG.width - 100, '', 24);
				missingText.setFormat(Paths.font(Language.get('fontName', 'main') + '.ttf'), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				missingText.scrollFactor.set();
				add(missingText);
			}
			else
				missingTextTimer.cancel();

			missingText.text = 'ERROR WHILE LOADING CHART:\n$errorStr';
			missingText.screenCenter(Y);

			missingTextTimer = new FlxTimer().start(5, function(tmr:FlxTimer)
			{
				remove(missingText);
				missingText.destroy();
			});
			FlxG.sound.play(Paths.sound('cancelMenu'));
		}
	}

	function autosaveSong():Void
	{
		FlxG.save.data.autosave = haxe.Json.stringify({
			"song": _song
		});
		FlxG.save.flush();
	}

	/**
	 * 以「测试模式」进入 EditorPlayState。
	 * 对应原版的 ESC，也对应新顶栏菜单 [测试] → 「以测试模式进行」。
	 */

	// ================= 快捷键辅助函数 =================
	/** Ctrl+Shift+Tab：打开/关闭 Vortex */
	function toggleVortexShortcut():Void
	{
		vortex = !vortex;
		FlxG.save.data.chart_vortex = vortex;
		if (check_vortex != null) check_vortex.checked = vortex;
		reloadGridLayer();
	}

	/** Ctrl+Shift+U / Ctrl+Shift+O：BF / Opp 打击音开关 */
	function toggleSfxShortcut(side:String):Void
	{
		if (side == 'bf')
		{
			if (playSoundBf == null) return;
			playSoundBf.checked = !playSoundBf.checked;
			if (playSoundBf.callback != null) playSoundBf.callback();
		}
		else
		{
			if (playSoundDad == null) return;
			playSoundDad.checked = !playSoundDad.checked;
			if (playSoundDad.callback != null) playSoundDad.callback();
		}
	}

	/** Alt+Ctrl+U/I/O：静音 BF / Inst / Opp（走各自 callback 同步音量） */
	function toggleMuteShortcut(side:String):Void
	{
		var cb:Dynamic = null;
		switch (side)
		{
			case 'bf': if (check_mute_vocals != null) { check_mute_vocals.checked = !check_mute_vocals.checked; cb = check_mute_vocals.callback; }
			case 'inst': if (check_mute_inst != null) { check_mute_inst.checked = !check_mute_inst.checked; cb = check_mute_inst.callback; }
			case 'opp': if (check_mute_vocals_opponent != null) { check_mute_vocals_opponent.checked = !check_mute_vocals_opponent.checked; cb = check_mute_vocals_opponent.callback; }
		}
		if (cb != null) try { cb(); } catch (e:Dynamic) {}
	}

	/** Alt+U/I/O：BF / Inst / Opp 波形图开关（互斥已取消，可同时开启） */
	function toggleWaveformShortcut(side:String):Void
	{
		switch (side)
		{
			case 'bf':
				if (waveformUseVoices == null) return;
				waveformUseVoices.checked = !waveformUseVoices.checked;
				FlxG.save.data.chart_waveformVoices = waveformUseVoices.checked;
				updateWaveform();
			case 'inst':
				if (waveformUseInstrumental == null) return;
				waveformUseInstrumental.checked = !waveformUseInstrumental.checked;
				FlxG.save.data.chart_waveformInst = waveformUseInstrumental.checked;
				updateWaveform();
			case 'opp':
				if (waveformUseOppVoices == null) return;
				waveformUseOppVoices.checked = !waveformUseOppVoices.checked;
				FlxG.save.data.chart_waveformOppVoices = waveformUseOppVoices.checked;
				updateWaveform();
		}
	}

	/** K+数字（`=1K ~ 9=10K）：设置 Mania 键数（带阈值 clamp，并同步到【歌曲】→【键数】步进器） */
	function setManiaByKey(displayKeys:Int):Void
	{
		beginHistoryAction('history_edit_chart');
		var minK:Int = 1;
		var maxK:Int = extraMaxKeys();
		displayKeys = Std.int(FlxMath.bound(displayKeys, minK, maxK));
		_song.mania = displayKeys - 1;
		if (stepperMania != null) stepperMania.value = displayKeys; // ★ 同步回【键数】步进器
		updateKeyAmounts();
		reloadGridLayer();
		makeStrumNotes();
		commitHistoryAction();
	}
	// ================= 快捷键辅助函数结束 =================

	// 处理菜单 action 项的回调
	function handleMenuAction(actionKey:String):Void
	{
		switch (actionKey)
		{
			case 'history':
				if (historyPanel != null)
				{
					historyPanel.visible = !historyPanel.visible;
					refreshHistoryPanel();
				}
			case 'save':
				saveLevel();
			case 'reload_audio':
				// ★ 与 reload_json 一致：优先用【歌曲】标题输入框的内容（改了歌名后重载音频才生效），
				//   loadSong 内部会强制绕过声音缓存重新解码磁盘文件
				var wantedAudio:String = (UI_songTitle != null && UI_songTitle.text != null) ? StringTools.trim(UI_songTitle.text) : '';
				if (wantedAudio.length < 1) wantedAudio = _song.song;
				currentSongName = Paths.formatToSongPath(wantedAudio);
				withHistoryAction('history_edit_chart', loadSong);
			case 'reload_json':
				// ★ 用【歌曲】标题输入框的内容作为要加载的曲目（可输入新歌名如 "dad battle" 直接换曲），
				//   为空则保持当前曲目。之前写死 currentSongName → 输入什么都是重载当前曲
				var wantedSong:String = (UI_songTitle != null && UI_songTitle.text != null) ? StringTools.trim(UI_songTitle.text) : '';
				if (wantedSong.length < 1) wantedSong = _song.song;
				loadJson(Paths.formatToSongPath(wantedSong));
			case 'engine':
				menuBar.openMenu(5);
			case 'load_autosave':
				loadFromAutosave();
			case 'load_events':
				loadEventsFromFile();
			case 'save_events':
				saveEvents();
			case 'clear_events':
				openSubState(new Prompt('This action will clear current progress.\n\nProceed?', 0, clearEvents, null, ignoreWarnings));
			case 'clear_notes':
				openSubState(new Prompt('This action will clear current progress.\n\nProceed?', 0, function()
				{
					beginHistoryAction('history_clear_notes');
					for (sec in 0..._song.notes.length)
					{
						_song.notes[sec].sectionNotes = [];
					}
					updateGrid();
					commitHistoryAction();
				}, null, ignoreWarnings));
			case 'apply_notes':
				applyNoteSkinSelection();
			case 'copy_section':
				copyCurrentSection();
			case 'paste_section':
				openSubState(new Prompt(Language.get('prompt_paste_section', 'charting'), 0, function()
				{
					pasteToCurrentSection();
				}, null, ignoreWarnings));
			case 'clear_section':
				openSubState(new Prompt(Language.get('prompt_clear_section', 'charting'), 0, function()
				{
					clearCurrentSection();
				}, null, ignoreWarnings));
			case 'swap_section':
				openSubState(new Prompt(Language.get('prompt_swap_section', 'charting'), 0, function()
				{
					swapSectionSides();
				}, null, ignoreWarnings));
			case 'do_copy_beat':
				openSubState(new Prompt(Language.get('prompt_copy_beat', 'charting'), 0, function()
				{
					copyBeat();
				}, null, ignoreWarnings));
			case 'copy_last_section':
				copyLastSectionToCurrent();
			case 'duet_notes':
				openSubState(new Prompt(Language.get('prompt_duet_notes', 'charting'), 0, function()
				{
					duetCurrentSection();
				}, null, ignoreWarnings));
			case 'mirror_notes':
				openSubState(new Prompt(Language.get('prompt_mirror_notes', 'charting'), 0, function()
				{
					mirrorCurrentSection();
				}, null, ignoreWarnings));
			case 'undo':
				undo();
			case 'redo':
				redo();
			case 'add_event':
				addNewEventToCurrentSection();
			case 'del_event':
				deleteSelectedEvent();
			case 'prev_event':
				selectPrevEvent();
			case 'next_event':
				selectNextEvent();
		}
	}

	/**
	 * 菜单打开后刷新 widget 显示值。
	 * widget 在 visible=false 时被 setter 赋值后，内部 text_field 可能不会立即刷新。
	 * 这里在 widget 已可见的状态下重新触发 setter，确保显示与数据同步。
	 */
	function refreshMenuWidgets(menuKey:String):Void
	{
		switch (menuKey)
		{
			case 'song':
				if (engineDropDown != null) engineDropDown.selectedLabel = Song.chartEngineVersion;
				try { if (UI_songTitle != null) UI_songTitle.text = _song.song; } catch(e:Dynamic) {}
				try { if (songBpmStepper != null) songBpmStepper.value = _song.bpm; } catch(e:Dynamic) {}
				try { if (stepperSpeed != null) stepperSpeed.value = _song.speed; } catch(e:Dynamic) {}
				try { if (check_voices != null) check_voices.checked = _song.needsVoices; } catch(e:Dynamic) {}
				if (stepperMania != null) stepperMania.value = _song.mania + 1;
				if (player1DropDown != null) player1DropDown.selectedLabel = _song.player1;
				if (player2DropDown != null) player2DropDown.selectedLabel = _song.player2;
				if (gfVersionDropDown != null) gfVersionDropDown.selectedLabel = _song.gfVersion;
				if (stageDropDown != null) stageDropDown.selectedLabel = _song.stage;

			case 'section':
				try { if (stepperSectionBPM != null && _song.notes.length > curSec) stepperSectionBPM.value = _song.notes[curSec].bpm; } catch(e:Dynamic) {}
				// ★ 先读取：所有小节 checkbox 从谱面数据刷新（openMenu 先调这里再 rebuildDropdown 渲染）
				try { if (check_mustHitSection != null && _song.notes.length > curSec) check_mustHitSection.checked = _song.notes[curSec].mustHitSection; } catch(e:Dynamic) {}
				try { if (check_gfSection != null && _song.notes.length > curSec) check_gfSection.checked = _song.notes[curSec].gfSection; } catch(e:Dynamic) {}
				try { if (check_altAnim != null && _song.notes.length > curSec) check_altAnim.checked = _song.notes[curSec].altAnim; } catch(e:Dynamic) {}
				try { if (check_changeBPM != null && _song.notes.length > curSec) check_changeBPM.checked = _song.notes[curSec].changeBPM; } catch(e:Dynamic) {}
				// check_notesSec / check_eventsSec 是用户的复制设置，保持 toggle 状态，不刷新

			case 'note':
				if (curSelectedNote != null)
				{
					try { if (stepperSusLength != null && curSelectedNote.length > 2 && curSelectedNote[2] != null)
					{
						var curVal:Float = stepperSusLength.value;
						var targetVal:Float = curSelectedNote[2];
						if (curVal == targetVal) stepperSusLength.value = targetVal + 0.001;
						stepperSusLength.value = targetVal;
					}} catch(e:Dynamic) {}
					try { if (strumTimeInputText != null) strumTimeInputText.text = '' + curSelectedNote[0]; } catch(e:Dynamic) {}
				}

			case 'event':
				// ★ 崩溃修复：普通 note 的 curSelectedNote[1] 是轨道号数字（非数组），
				//   直接 [1][curEventSelected][1] 索引会对 Int 做动态访问 → 原生空指针 AV（try/catch 拦不住）
				if (curSelectedNote != null && curSelectedNote.length > 1 && Std.is(curSelectedNote[1], Array))
				{
					var evArr3:Array<Dynamic> = cast curSelectedNote[1];
					if (curEventSelected >= 0 && curEventSelected < evArr3.length)
					{
						var ev3:Dynamic = evArr3[curEventSelected];
						if (Std.is(ev3, Array))
						{
							var evD3:Array<Dynamic> = cast ev3;
							try { if (value1InputText != null && evD3.length > 1) value1InputText.text = evD3[1]; } catch(e:Dynamic) {}
							try { if (value2InputText != null && evD3.length > 2) value2InputText.text = evD3[2]; } catch(e:Dynamic) {}
						}
					}
				}

			case 'charting':
				// ★ 先读取：谱面菜单 checkbox 从存档刷新（openMenu 先调这里再 rebuildDropdown 渲染）
				try { if (metronome != null) metronome.checked = (FlxG.save.data.chart_metronome == true); } catch(e:Dynamic) {}
				try { if (disableAutoScrolling != null) disableAutoScrolling.checked = (FlxG.save.data.chart_noAutoScroll == true); } catch(e:Dynamic) {}
				try { if (waveformUseInstrumental != null) waveformUseInstrumental.checked = (FlxG.save.data.chart_waveformInst == true); } catch(e:Dynamic) {}
				try { if (waveformUseVoices != null) waveformUseVoices.checked = (FlxG.save.data.chart_waveformVoices == true); } catch(e:Dynamic) {}
				try { if (waveformUseOppVoices != null) waveformUseOppVoices.checked = (FlxG.save.data.chart_waveformOppVoices == true); } catch(e:Dynamic) {}
				try { if (check_vortex != null) check_vortex.checked = (FlxG.save.data.chart_vortex == true); } catch(e:Dynamic) {}
				try { if (check_warnings != null) check_warnings.checked = (FlxG.save.data.ignoreWarnings == true); } catch(e:Dynamic) {}
				try { if (playSoundBf != null) playSoundBf.checked = (FlxG.save.data.chart_playSoundBf == true); } catch(e:Dynamic) {}
				try { if (playSoundDad != null) playSoundDad.checked = (FlxG.save.data.chart_playSoundDad == true); } catch(e:Dynamic) {}
				// 静音类（mute_inst/main/opp）是运行时状态，由用户 toggle 实时生效，不在此刷新

			case 'data':
				if (noteSkinInputText != null) noteSkinInputText.text = _song.arrowSkin == null ? '' : _song.arrowSkin;
				if (noteSplashesInputText != null) noteSplashesInputText.text = _song.splashSkin == null ? '' : _song.splashSkin;
				try { if (gameOverCharacterInputText != null) gameOverCharacterInputText.text = _song.gameOverChar != null ? _song.gameOverChar : ''; } catch(e:Dynamic) {}
				try { if (gameOverSoundInputText != null) gameOverSoundInputText.text = _song.gameOverSound != null ? _song.gameOverSound : ''; } catch(e:Dynamic) {}
				try { if (gameOverLoopInputText != null) gameOverLoopInputText.text = _song.gameOverLoop != null ? _song.gameOverLoop : ''; } catch(e:Dynamic) {}
				try { if (gameOverEndInputText != null) gameOverEndInputText.text = _song.gameOverEnd != null ? _song.gameOverEnd : ''; } catch(e:Dynamic) {}
				// ★ 先读取：数据菜单 checkbox 从谱面数据刷新
				try { if (check_disableNoteRGB != null) check_disableNoteRGB.checked = (_song.disableNoteRGB == true); } catch(e:Dynamic) {}
		}
	}

	function loadEventsFromFile():Void
	{
		var songName = currentSongName;
		var file:String = Paths.json(songName + '/events');
		#if sys
		if (#if MODS_ALLOWED FileSystem.exists(Paths.modsJson(songName + '/events')) || #end FileSystem.exists(file))
		#else
		if (Assets.exists(file))
		#end
		{
			beginHistoryAction('history_load_events');
			_song.events = [];
			var savedFmt = Song.detectedFormat;
			var savedCE = Song.chartEngineVersion;
			var events:SwagSong = Song.loadFromJson('events', songName);
			Song.detectedFormat = savedFmt;
			Song.chartEngineVersion = savedCE;
			_song.events = events.events;
			changeSection(curSec);
			commitHistoryAction();
		}
	}

	function loadFromAutosave():Void
	{
		beginHistoryAction('history_load_autosave');
		PlayState.SONG = Song.parseJSON(FlxG.save.data.autosave);
		if (PlayState.SONG == null)
		{
			commitHistoryAction();
			return;
		}
		_song = PlayState.SONG; // ★ 同步引用（autosave 是全新对象）
		if (curSec >= _song.notes.length) curSec = _song.notes.length - 1;
		if (curSec < 0) curSec = 0;
		// ★ 全套刷新：角色/mania 可能都变了 → 颜色、头像、轨道数全部按新曲目数据重建
		updateJsonData();
		autoFixManiaFromData(); // autosave 若缺 mania 字段 → 按数据恢复
		recalcKeyAmounts();
		reloadGridLayer();
		makeStrumNotes();
		updateHeads();
		changeSection(curSec);
		commitHistoryAction();
	}

	function applyNoteSkinSelection():Void
	{
		// 把当前下拉选中的音符类型应用到谱面所有音符（原 apply_notes 是空壳）
		if (_song.notes == null || curNoteTypes == null) return;
		if (currentType < 0 || currentType >= curNoteTypes.length) return;
		var typeStr:String = curNoteTypes[currentType];
		pushUndo('history_apply_note_skin');
		for (sec in 0..._song.notes.length)
		{
			for (note in _song.notes[sec].sectionNotes)
			{
				note[3] = typeStr;
			}
		}
		updateGrid();
		commitHistoryAction();
	}

	function copyCurrentSection():Void
	{
		if (curSec >= 0 && curSec < _song.notes.length)
		{
			// ★ 按「包含音符 / 包含事件」勾选状态过滤后再保存（作用于所有复制/粘贴）
			var secCopy:Dynamic = haxe.Json.parse(haxe.Json.stringify(_song.notes[curSec]));
			filterSectionByChecks(secCopy);
			FlxG.save.data.copiedSection = haxe.Json.stringify(secCopy);
			// ★ 记录复制时刻所在小节的时间起点，粘贴时用它计算偏移，
			//   否则粘到别的小节时 note 时间不挪，全部堆在源小节的位置（谱面外）
			FlxG.save.data.copiedSectionTime = sectionStartTime();
		}
	}

	/** 按「包含音符 / 包含事件」勾选状态过滤小节数据（Psych 格式：事件行 [1] == -1）。
	 *  就地修改传入的小节对象，返回同一对象。 */
	function filterSectionByChecks(sec:Dynamic):Void
	{
		if (sec == null || sec.sectionNotes == null) return;
		var includeNotes:Bool = (check_notesSec != null) ? check_notesSec.checked : true;
		var includeEvents:Bool = (check_eventsSec != null) ? check_eventsSec.checked : true;
		if (includeNotes && includeEvents) return; // 全选，无需过滤

		var filtered:Array<Dynamic> = [];
		for (note in (sec.sectionNotes:Array<Dynamic>))
		{
			if (note == null || !Std.is(note, Array)) continue;
			var arrNote:Array<Dynamic> = cast note;
			var isEventRow:Bool = (arrNote.length > 1 && arrNote[1] == -1);
			if (isEventRow)
			{
				if (includeEvents) filtered.push(note);
			}
			else
			{
				if (includeNotes) filtered.push(note);
			}
		}
		sec.sectionNotes = filtered;
	}

	/** ★ 把 parsed 小节的音符内容【追加】到当前小节（纯粘贴：不清除目标小节原有内容，
	 *  也不改动小节属性 mustHitSection/gfSection）。复制/粘贴 = 叠加内容。 */
	function appendSectionNotes(parsed:Dynamic):Void
	{
		if (parsed == null || _song.notes == null || curSec < 0 || curSec >= _song.notes.length) return;
		if (parsed.sectionNotes == null) return;
		var target:Array<Dynamic> = _song.notes[curSec].sectionNotes;
		if (target == null) target = [];
		for (n in (parsed.sectionNotes:Array<Dynamic>))
		{
			if (n != null && Std.is(n, Array)) target.push(n);
		}
		// 追加后按时间排序，保持渲染/选择稳定
		target.sort(function(a:Array<Dynamic>, b:Array<Dynamic>):Int
		{
			var ta:Float = (a != null && a.length > 0 && a[0] != null) ? Std.parseFloat(Std.string(a[0])) : 0;
			var tb:Float = (b != null && b.length > 0 && b[0] != null) ? Std.parseFloat(Std.string(b[0])) : 0;
			return ta < tb ? -1 : (ta > tb ? 1 : 0);
		});
		_song.notes[curSec].sectionNotes = target;
	}

	/** ★ 重活（粘贴/撤销等全量重建）期间若音乐在播放先暂停，结束后恢复——
	 *   大谱面重建会卡顿数百 ms，若不暂停，卡顿期间音乐时间照常前进，
	 *   恢复后 strumline/视图会瞬间跳变（表现为"网格疯狂滚动"）。
	 *   ★ 同时记录并强制恢复 music.time：防任何路径（如大谱面下耗时操作
	 *   触发的 onComplete 等）把播放位置归零，粘贴到 100+ 小节后视图倒退到 0:00。 */
	function withMusicPaused(fn:Void->Void):Void
	{
		var wasPlaying:Bool = (FlxG.sound.music != null && FlxG.sound.music.playing);
		var savedTime:Float = (FlxG.sound.music != null) ? FlxG.sound.music.time : -1;
		if (wasPlaying) FlxG.sound.music.pause();
		try { fn(); } catch (e:Dynamic) {}
		if (FlxG.sound.music != null)
		{
			if (savedTime >= 0) FlxG.sound.music.time = savedTime; // 兜底恢复播放位置
			if (wasPlaying) FlxG.sound.music.resume();
		}
	}

	function pasteToCurrentSection():Void
	{
		withMusicPaused(function()
		{
			var json:String = FlxG.save.data.copiedSection;
			if (json != null && json.length > 0 && curSec >= 0 && curSec < _song.notes.length)
			{
				var parsed:Dynamic = haxe.Json.parse(json);
				if (parsed != null)
				{
					pushUndo('history_paste_section');
					// ★ 粘贴时也按勾选状态过滤（覆盖旧存档里未过滤的复制数据）
					filterSectionByChecks(parsed);
					// ★ 把每个 note 的 strumTime 从「复制小节的时间原点」平移到「当前小节的时间原点」
					var copiedTime:Float = FlxG.save.data.copiedSectionTime;
					var offset:Float = sectionStartTime() - copiedTime;
					if (parsed.sectionNotes != null)
					{
						for (note in (parsed.sectionNotes:Array<Dynamic>))
						{
							if (note != null && Std.is(note, Array) && note.length > 0 && note[0] != null)
								note[0] = note[0] + offset;
						}
					}
					appendSectionNotes(parsed); // ★ 纯粘贴：不清除目标原有内容、不改 mustHit/gf
					updateGrid(false); // 只重绘当前小节（下一小节预览未变，跳过省一半重建开销）
					commitHistoryAction();
				}
			}
		});
	}

	function clearCurrentSection():Void
	{
		if (curSec >= 0 && curSec < _song.notes.length)
		{
			pushUndo('history_clear_section');
			var sec = _song.notes[curSec];
			// ★ 清除语义（与旧版 Clear 按钮一致）：「包含音符/包含事件」勾选 = 该部分被清除；
			//   注意与 filterSectionByChecks（复制/粘贴用，勾选 = 保留）语义相反，不能混用！
			var includeNotes:Bool = (check_notesSec != null) ? check_notesSec.checked : true;
			var includeEvents:Bool = (check_eventsSec != null) ? check_eventsSec.checked : true;

			// 小节内 sectionNotes：清除勾选的部分（事件行 [1] == -1）
			if (sec.sectionNotes != null)
			{
				var kept:Array<Dynamic> = [];
				for (note in (sec.sectionNotes:Array<Dynamic>))
				{
					if (note == null || !Std.is(note, Array)) continue;
					var arrNote:Array<Dynamic> = cast note;
					var isEventRow:Bool = (arrNote.length > 1 && arrNote[1] == -1);
					if (isEventRow)
					{
						if (!includeEvents) kept.push(note); // 未勾选「包含事件」→ 保留事件行
					}
					else
					{
						if (!includeNotes) kept.push(note); // 未勾选「包含音符」→ 保留音符
					}
				}
				sec.sectionNotes = kept;
			}

			// 全局事件 _song.events：勾选「包含事件」时清除当前小节时间段内的事件（与旧版 Clear 一致）
			if (includeEvents && _song.events != null)
			{
				var i:Int = _song.events.length - 1;
				var startThing:Float = sectionStartTime();
				var endThing:Float = sectionStartTime(1);
				while (i > -1)
				{
					var event:Array<Dynamic> = _song.events[i];
					if (event != null && endThing > event[0] && event[0] >= startThing)
						_song.events.remove(event);
					--i;
				}
			}
			updateGrid();
			commitHistoryAction();
		}
	}

	/** 交换当前小节内玩家（BF）与对手（opp）的 NOTE：键位在两侧对调。
	    ★ 注意：不翻转 mustHitSection——键位对调本身已让 BF 改接原 opp 的 note、
	      opp 改接原 BF 的 note；再翻转 mustHit 会把归属又换回去，还误改了「玩家小节」设置。
	      （角色头像位置由 mustHitSection 驱动，翻转会导致 bf/dad 位置互换） */
	function swapSectionSides():Void
	{
		if (curSec >= 0 && curSec < _song.notes.length)
		{
			pushUndo('history_swap_sides');
			var perSide:Int = _song.mania + 1;
			var notes = _song.notes[curSec].sectionNotes;
			for (note in notes)
			{
				if (note == null || !Std.is(note, Array)) continue;
				var arrNote:Array<Dynamic> = cast note;
				if (arrNote.length < 2 || arrNote[1] == null || !Std.is(arrNote[1], Int) && !Std.is(arrNote[1], Float)) continue;
				// 玩家侧 0..mania ⇄ 对手侧 (mania+1)..(mania*2+1)
				if (arrNote[1] < perSide) arrNote[1] += perSide;
				else arrNote[1] -= perSide;
			}
			updateGrid();
			commitHistoryAction();
		}
	}

	function copyLastSectionToCurrent():Void
	{
		if (curSec > 0 && curSec < _song.notes.length)
		{
			withMusicPaused(function()
			{
				pushUndo('history_copy_section');
				var parsed:Dynamic = haxe.Json.parse(haxe.Json.stringify(_song.notes[curSec - 1]));
				// ★ 按「包含音符 / 包含事件」勾选状态过滤
				filterSectionByChecks(parsed);
				// ★ 时间偏移：源小节(curSec-1)的 note 时间平移到当前小节，否则全部堆在源小节位置（谱面外）
				applySectionTimeOffset(parsed, sectionStartTime() - sectionStartTime(-1));
				appendSectionNotes(parsed); // ★ 纯粘贴：不清除目标原有内容、不改 mustHit/gf
				updateGrid(false); // 只重绘当前小节
				commitHistoryAction();
			});
		}
	}

	/** 复制节拍：以当前小节 curSec 为基准，偏移 offset（stepper 值，可正可负），
	    把源小节 [curSec - offset] 复制覆盖到当前小节。offset=1 即原"复制上一小节"。 */
	function copyBeat():Void
	{
		if (copyBeatStepper == null || _song.notes == null) return;
		var offset:Int = Std.int(copyBeatStepper.value);
		if (offset == 0)
		{
			trace('[charting] 复制节拍失败：偏移量为 0（复制自己没意义），请在 stepper 里输入非零值');
			return;
		}
		var src:Int = curSec - offset;
		if (src >= 0 && src < _song.notes.length && curSec >= 0 && curSec < _song.notes.length)
		{
			withMusicPaused(function()
			{
				pushUndo('history_copy_beat');
				var parsed:Dynamic = haxe.Json.parse(haxe.Json.stringify(_song.notes[src]));
				// ★ 按「包含音符 / 包含事件」勾选状态过滤
				filterSectionByChecks(parsed);
				// ★ 时间偏移：把源小节 src 的 note 时间平移到当前小节（sectionStartTime 的 add 是相对 curSec 的偏移）
				applySectionTimeOffset(parsed, sectionStartTime() - sectionStartTime(src - curSec));
				appendSectionNotes(parsed); // ★ 纯粘贴：不清除目标原有内容、不改 mustHit/gf
				updateGrid(false); // 只重绘当前小节
				commitHistoryAction();
			});
		}
		else
			trace('[charting] 复制节拍失败：源小节越界 src=$src（当前小节 curSec=$curSec）');
	}

	/** 把复制来的小节里每个 note 的 strumTime 整体平移 offset 毫秒。 */
	function applySectionTimeOffset(sec:Dynamic, offset:Float):Void
	{
		if (sec == null || sec.sectionNotes == null || offset == 0) return;
		for (note in (sec.sectionNotes:Array<Dynamic>))
		{
			if (note != null && Std.is(note, Array) && note.length > 0 && note[0] != null)
				note[0] = note[0] + offset;
		}
	}

	function duetCurrentSection():Void
	{
		if (curSec >= 0 && curSec < _song.notes.length)
		{
			pushUndo('history_duet');
			var perSide:Int = _song.mania + 1;
			// ★ 二重奏 = 平衡两侧：谁多，就把多的那侧的每个音符复制一份给少的一侧，
			//   让两边数量相等（BF 16 个 + opp 8 个 → 二重奏后两边各 16 个）。
			//   只复制「多的一方」，少的一方保持不动。
			var playerNotes:Array<Array<Dynamic>> = [];
			var oppNotes:Array<Array<Dynamic>> = [];
			for (note in _song.notes[curSec].sectionNotes)
			{
				// 防御：可能混入 null / 非数组 / 事件 note（[1] 是数组）
				if (note == null || !Std.is(note, Array)) continue;
				var arrNote:Array<Dynamic> = cast note;
				if (arrNote.length < 2 || arrNote[1] == null || !Std.is(arrNote[1], Int) && !Std.is(arrNote[1], Float)) continue;
				// 先收集到快照再处理，避免遍历的同时 push 导致重复处理
				if (arrNote[1] < perSide) playerNotes.push(arrNote);
				else oppNotes.push(arrNote);
			}
			if (playerNotes.length > oppNotes.length)
			{
				// 玩家侧多 → 把玩家侧的复制到对手侧（键位平移 perSide，恰好落在对手键位区间）
				for (pn in playerNotes)
				{
					var newNote:Array<Dynamic> = pn.copy();
					newNote[1] = newNote[1] + perSide;
					_song.notes[curSec].sectionNotes.push(newNote);
				}
			}
			else if (oppNotes.length > playerNotes.length)
			{
				// 对手侧多 → 把对手侧的复制到玩家侧
				for (on in oppNotes)
				{
					var newNote:Array<Dynamic> = on.copy();
					newNote[1] = newNote[1] - perSide;
					_song.notes[curSec].sectionNotes.push(newNote);
				}
			}
			// 两侧数量相等时无需操作（本来就已经平衡）
			updateGrid();
			commitHistoryAction();
		}
	}

	function mirrorCurrentSection():Void
	{
		if (curSec >= 0 && curSec < _song.notes.length)
		{
			pushUndo('history_mirror');
			var notes = _song.notes[curSec].sectionNotes;
			var keysPerPlayer = _song.mania;
			for (note in notes)
			{
				// ★ 同 duet：镜像操作的是键位 note[1]，跳过 null / 非数组 / 事件 note
				if (note == null || !Std.is(note, Array)) continue;
				var arrNote:Array<Dynamic> = cast note;
				if (arrNote.length < 2 || arrNote[1] == null || !Std.is(arrNote[1], Int) && !Std.is(arrNote[1], Float)) continue;
				arrNote[1] = (keysPerPlayer * 2 + 1) - arrNote[1];
			}
			updateGrid();
			commitHistoryAction();
		}
	}

	function addNewEventToCurrentSection():Void
	{
		// 在当前选中的音符上添加事件
		// ★ 事件音符判定必须用 [1] 是否为数组：普通音符的 [1] 是轨道号（Int），
		//   旧谱面普通音符的 [2]（susLength）也可能为 null，用 [2]==null 判断会把普通音符
		//   误判成事件音符 → 对 Int 调 push → 空指针崩溃（ACCESS_VIOLATION read 0x0）。
		if (curSelectedNote != null && Std.is(curSelectedNote[1], Array))
		{
			var eventsGroup:Array<Dynamic> = cast curSelectedNote[1];
			if (eventsGroup == null) return;
			beginHistoryAction('history_add_item');
			eventsGroup.push(['', '', '']);
			changeEventSelected(1);
			updateGrid();
			commitHistoryAction();
		}
	}

	function deleteSelectedEvent():Void
	{
		// 删除当前选中的事件
		if (curSelectedNote != null && Std.is(curSelectedNote[1], Array))
		{
			var eventsGroup:Array<Dynamic> = cast curSelectedNote[1];
			if (eventsGroup == null || eventsGroup.length < 1) return;
			if (curEventSelected >= 0 && curEventSelected < eventsGroup.length)
			{
				beginHistoryAction('history_delete_item');
				eventsGroup.remove(eventsGroup[curEventSelected]);
				if (eventsGroup.length < 1)
				{
					// ★ 事件删空 → 顺带移除整个事件音符（与旧版「-」按钮行为一致，
					//   否则网格里会留下一个空事件箭头，看起来像没删掉）
					_song.events.remove(curSelectedNote);
					curSelectedNote = null;
					curEventSelected = 0;
				}
				else
				{
					if (curEventSelected >= eventsGroup.length)
						curEventSelected = eventsGroup.length - 1;
					if (curEventSelected < 0) curEventSelected = 0;
				}
				updateGrid();
				commitHistoryAction();
			}
		}
	}

	function selectPrevEvent():Void
	{
		changeEventSelected(-1);
	}

	function selectNextEvent():Void
	{
		changeEventSelected(1);
	}

	function applyChartEngine(engine:String):Void
	{
		if (engine == Song.chartEngineVersion)
		{
			var selectedFormat:String = engine == 'Pe-1.0.4' ? 'psych_v1' : 'Pe-0.7.3';
			if (_song.format != selectedFormat)
			{
				beginHistoryAction('history_edit_chart');
				_song.format = selectedFormat;
				commitHistoryAction();
			}
			// 用户明确选择当前版本时，也同步强制版本，避免后续重载被旧值覆盖。
			Song.forceEngineVersion = engine;
			return;
		}
		beginHistoryAction('history_edit_chart');
		Song.forceEngineVersion = engine;
		Song.chartEngineVersion = engine;
		_song.format = engine == 'Pe-1.0.4' ? 'psych_v1' : 'Pe-0.7.3';
		metricsDirty = true;
		reloadGridLayer();
		updateGrid();
		updateHeads();
		commitHistoryAction();
		trace('[ChartEngine] selected=' + engine);
	}

	function startPlaytest():Void
	{
		ensureMetrics();
		PlayState.SONG = _song;
		trace('[ChartOwnership] engine=' + Song.chartEngineVersion + ' BF=' + bfNoteTotal + ' Opp=' + oppNoteTotal);
		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();

		if (vocals != null)
		{
			vocals.pause();
			vocals.volume = 0;
		}
		if (opponentVocals != null)
		{
			opponentVocals.pause();
			opponentVocals.volume = 0;
		}

		autosaveSong();
		playtesting = true;
		playtestingTime = Conductor.songPosition; // 试玩前位置（返回编辑器时恢复用）
		playtestingOnComplete = FlxG.sound.music.onComplete;
		// ★ 试玩从当前位置开始，但 EditorPlayState 内会先播放 3,2,1,GO 倒计时再开播
		removeVirtualPad();
		// ★ 十二轮：试玩画面要与真实游玩完全一致 → 先退回 1280×720 设计；
		//   EditorPlayState.destroy() 会再切回编辑器的高分辨率设计。
		EditorInputStyle.exitHiRes();
		openSubState(new developer.editors.EditorPlayState(playbackSpeed));
	}

	/**
	 * 以「正常游玩模式」进入 PlayState。
	 * 对应原版的 ENTER，也对应新顶栏菜单 [测试] → 「以正常模式进行」。
	 */
	function startNormalPlay():Void
	{
		autosaveSong();
		FlxG.mouse.visible = false;
		PlayState.SONG = _song;
		FlxG.sound.music.stop();
		if (vocals != null)
			vocals.stop();
		if (opponentVocals != null)
			opponentVocals.stop();

		// if(_song.stage == null) _song.stage = stageDropDown.selectedLabel;
		StageData.loadDirectory(_song);
		LoadingState.loadAndSwitchState(new PlayState());
	}

	function clearEvents()
	{
		beginHistoryAction('history_clear_events');
		_song.events = [];
		updateGrid();
		commitHistoryAction();
	}

	private function saveLevel()
	{
		if (_file != null) return;
		if (_song.events != null && _song.events.length > 1)
			_song.events.sort(sortByTime);
		pendingChartSave = chartHistorySnapshot();
		if (historyIndex >= 0) historyFrames[historyIndex].snapshot = pendingChartSave;
		var json = {
			"song": _song
		};

		var data:String = haxe.Json.stringify(json, "\t");

		if ((data != null) && (data.length > 0))
		{
			// ★ 保存文件名自动带难度后缀：难度输入框填了 Fuck → 「歌曲名-Fuck.json」
			var saveName:String = Paths.formatToSongPath(_song.song);
			var diff:String = (difficultyInputText != null && difficultyInputText.text != null) ? StringTools.trim(difficultyInputText.text) : '';
			if (diff.length > 0)
				saveName += '-' + Paths.formatToSongPath(diff);
			#if mobile
			SUtil.saveContent(saveName, ".json", data.trim());
			#else
			_file = new FileReference();
			_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data.trim(), saveName + ".json");
			#end
		}
	}

	function sortByTime(Obj1:Array<Dynamic>, Obj2:Array<Dynamic>):Int
	{
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1[0], Obj2[0]);
	}

	private function saveEvents()
	{
		if (_file != null) return;
		pendingChartSave = null;
		if (_song.events != null && _song.events.length > 1)
			_song.events.sort(sortByTime);
		var eventsSong:Dynamic = {
			events: _song.events,
			format: 'psych_v1'
		};
		var json = {
			"song": eventsSong
		}

		var data:String = haxe.Json.stringify(json, "\t");

		if ((data != null) && (data.length > 0))
		{
			#if mobile
			SUtil.saveContent("events", ".json", data.trim());
			#else
			_file = new FileReference();
			_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data.trim(), "events.json");
			#end
		}
	}

	function onSaveComplete(_):Void
	{
		if (pendingChartSave != null) savedChartSnapshot = pendingChartSave;
		pendingChartSave = null;
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.notice("Successfully saved LEVEL DATA.");
	}

	/**
	 * Called when the save file dialog is cancelled.
	 */
	function onSaveCancel(_):Void
	{
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
	}

	/**
	 * Called if there is an error while saving the gameplay recording.
	 */
	function onSaveError(_):Void
	{
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.error("Problem saving Level data");
	}

	function getSectionBeats(?section:Null<Int> = null)
	{
		if (section == null)
			section = curSec;
		var val:Null<Float> = null;

		if (_song.notes[section] != null)
			val = _song.notes[section].sectionBeats;
		return val != null ? val : 4;
	}

	// ★ 网格左右平移（shiftGridX）已移除：谱面固定居中，gridOffsetX 恒为 0。

	/** ★ 只按 _song.mania 重算键数，不移动任何音符数据。
	 *   用于创建/载入/autosave/引擎切换等「数据与 mania 配套」的场景——
	 *   绝不能走 updateKeyAmounts 的平移逻辑：它以旧 totalKeys 为基准平移数据，
	 *   若字段默认 totalKeys=8 而谱面是非 4K，每次重建都会把已排好的数据二次平移错乱
	 *   （典型症状：前 4K 正常、其余键全部跑到对方/越界）。 */
	function recalcKeyAmounts():Void
	{
		leftKeys = _song.mania + 1;
		rightKeys = _song.mania + 1;
		totalKeys = leftKeys + rightKeys;
		gridOffsetX = 0; // re-anchor to left edge when key count changes
	}

	/** 用户主动改变 mania 时：重算键数并把音符数据从旧布局平移到新布局（缩小会裁剪越界音符） */
	function updateKeyAmounts():Void
	{
		var oldTotalKeys:Int = totalKeys;
		recalcKeyAmounts();
		
		if (totalKeys < oldTotalKeys)
		{
			var oldLeftKeys:Int = oldTotalKeys >> 1;
			var diff:Int = oldLeftKeys - leftKeys;
			for (section in _song.notes)
			{
				var i:Int = section.sectionNotes.length - 1;
				while (i >= 0)
				{
					var row:Dynamic = section.sectionNotes[i];
					// 防御：事件行 [1] 是数组、或 lane 非 Int → 不参与平移
					if (row == null || !Std.is(row, Array)) { i--; continue; }
					var rowArr:Array<Dynamic> = cast row;
					if (rowArr.length < 2 || rowArr[1] == null || Std.is(rowArr[1], Array)
						|| (!Std.is(rowArr[1], Int) && !Std.is(rowArr[1], Float))) { i--; continue; }
					var nd:Int = Std.int(rowArr[1]);
					// Remove rightmost diff lanes from each side
					if ((nd >= oldLeftKeys - diff && nd < oldLeftKeys) || nd >= oldTotalKeys - diff)
						section.sectionNotes.remove(section.sectionNotes[i]);
					// Shift remaining opponent notes left to fill the gap
					else if (nd >= oldLeftKeys)
						rowArr[1] = nd - diff;
					i--;
				}
			}
		}
		else if (totalKeys > oldTotalKeys)
		{
			var oldLeftKeys:Int = oldTotalKeys >> 1;
			var diff:Int = leftKeys - oldLeftKeys;
			// Shift opponent notes right by diff to make room for new player lanes
			for (section in _song.notes)
			{
				for (note in section.sectionNotes)
				{
					if (note == null || !Std.is(note, Array)) continue;
					var rowArr:Array<Dynamic> = cast note;
					if (rowArr.length < 2 || rowArr[1] == null || Std.is(rowArr[1], Array)
						|| (!Std.is(rowArr[1], Int) && !Std.is(rowArr[1], Float))) continue;
					if (Std.int(rowArr[1]) >= oldLeftKeys)
						rowArr[1] = Std.int(rowArr[1]) + diff;
				}
			}
		}
	}

	/** ★ 数据驱动的键数自检：谱面 json 缺 mania 字段时解析会默认 3（4K），
	 *   若音符数据实际占了更高的 lane（非 4K 谱），按数据提升 mania（只升不降），
	 *   避免"前 4K 正常、其余 key 全部判定到对方"的错位。数据本身按 lane 排布，无需平移。 */
	function autoFixManiaFromData():Void
	{
		if (_song == null || _song.notes == null) return;
		var maxLane:Int = -1;
		for (sec in _song.notes)
		{
			if (sec == null || sec.sectionNotes == null) continue;
			for (n in (sec.sectionNotes:Array<Dynamic>))
			{
				if (n == null || !Std.is(n, Array)) continue;
				var arr:Array<Dynamic> = cast n;
				if (arr.length < 2 || arr[1] == null) continue;
				// 事件行 [1] 是数组；普通音符 lane 是非负 Int
				if (Std.is(arr[1], Array)) continue;
				if (!Std.is(arr[1], Int) && !Std.is(arr[1], Float)) continue;
				var lane:Int = Std.int(arr[1]);
				if (lane >= 0 && lane > maxLane) maxLane = lane;
			}
		}
		if (maxLane < 0) return;
		// 需要每侧 needKeys 键才装得下 maxLane（lane 0..needKeys-1 玩家侧、needKeys.. 对手侧）
		var needKeys:Int = Std.int(maxLane / 2) + 1;
		var needMania:Int = needKeys - 1;
		if (needMania > _song.mania)
		{
			trace('[charting] mania 自检：数据最大 lane=$maxLane，当前 ${_song.mania + 1}K 装不下 → 提升为 ${needMania + 1}K');
			_song.mania = needMania;
		}
	}

	/** ExtraKeys 实际支持的键数上限：优先 keys 配置表长度（extrakeys.json 的 maxKeys=9
	 *  是过期值——keys 表有 10 项、实际支持 10K），其次 maxKeys 字段，最后兜底 10 */
	function extraMaxKeys():Int
	{
		var ek = ExtraKeysHandler.instance;
		if (ek != null && ek.data != null)
		{
			if (ek.data.keys != null && ek.data.keys.length > 0) return ek.data.keys.length;
			if (ek.data.maxKeys > 0) return ek.data.maxKeys;
		}
		return 10;
	}

	function makeStrumNotes():Void
	{
		strumLineNotes.clear();
		var gx:Float = getGridX();
		
		for (i in 0...totalKeys)
		{
			var note:StrumNote;
			var player:Int = i < leftKeys ? 1 : 0;
			var noteData:Int = i < leftKeys ? i : i - leftKeys;
			
			note = new StrumNote(gx + GRID_SIZE * (i + 1), strumLine.y, noteData, player);
			note.setGraphicSize(GRID_SIZE, GRID_SIZE);
			note.updateHitbox();
			note.origin.set(0, 0);
			note.offset.set(0, 0);
			note.playAnim('static', true);
			strumLineNotes.add(note);
			note.scrollFactor.set(1, 1);
		}
		
		if (strumLine != null)
		{
			strumLine.makeGraphic(Std.int(GRID_SIZE * (totalKeys + 1)), 4);
			strumLine.x = gx;
		}

		if (eventIcon != null)
		{
			eventIcon.x = gx - GRID_SIZE - 5;
		}
		
		positionSideIcons();
	}

	/** ★ 两个角色头像重新水平居中到各自一侧的 note 轨道组正上方（y 固定 -100 锚点）。
	 *  网格几何变化（mania 键数 / 水平居中偏移）或头像换图（宽度变化）后都必须调用，
	 *  否则头像停在旧位置，与轨道列错位。 */
	function positionSideIcons():Void
	{
		if (leftIcon == null || rightIcon == null) return;
		var gx:Float = getGridX();
		// ★ 09-26 四轮：这里【只负责水平位置】。旧的 `setPosition(..., -100)` 会把 Icon 的 y 写死成
		//   -100（曲首方向），而 updateHeads() → positionSideIcons() 会在**每次换小节**时被调用
		//   （播放中 BPM 高的谱面每秒换好几次小节）→ Icon 被甩出屏幕一帧再被下一帧修回，
		//   表现为「Icon / 摄像机图标位置乱跳、只有超长超快谱面才明显」。y 现在一律由
		//   updateSideIconsFollow() 统一决定。
		leftIcon.x = gx + GRID_SIZE * (leftKeys + 2) / 2 - leftIcon.width / 2;
		rightIcon.x = gx + GRID_SIZE * (leftKeys + totalKeys + 2) / 2 - rightIcon.width / 2;
		// x 变了要立刻同步 y/camIcon，避免出现「横向已对、纵向还是旧值」的一帧
		updateSideIconsFollow();
	}

	/** ★ Icon（BF/Opp 头像 + 摄像机图标）跟随播放条定位。
	 *  09-26 三轮（用户要求）：播放条固定不动 → 头像与摄像机图标都放在【播放条上方】，
	 *  并水平居中于各自的 note 轨道组；切换 BF/Opp 小节只把 camIcon 换到对应那一组。 */
	function updateSideIconsFollow():Void
	{
		if (strumLine == null) return;
		var yF:Float = strumLine.y;
		// ★ HealthIcon.changeIcon()/setGraphicSize() 会重新设 origin（=帧半尺寸），
		//   不归零的话渲染顶点会被 -(origin*scale) 拉偏 → 头像「位置不对」。
		//   这里每帧强制归零（开销极小），任何路径换图都不会偏。
		if (leftIcon != null)
		{
			leftIcon.origin.set(0, 0);
			leftIcon.offset.set(0, 0);
			leftIcon.y = yF - leftIcon.height - 6;
		}
		if (rightIcon != null)
		{
			rightIcon.origin.set(0, 0);
			rightIcon.offset.set(0, 0);
			rightIcon.y = yF - rightIcon.height - 6;
		}

		if (camIcon != null)
		{
			var secObj:Dynamic = curSectionSafe();
			var camOnBf:Bool = (secObj == null || secObj.mustHitSection != false);
			var target:FlxSprite = camOnBf ? leftIcon : rightIcon;
			if (target != null)
			{
				// ★ 用户要求：摄像机图标放在【对应那个头像的左侧】，
				//   且与头像【同一 Y】
				camIcon.x = target.x - camIcon.width - 8;
				camIcon.y = target.y;
				camIcon.origin.set(0, 0);
				camIcon.offset.set(0, 0);
			}
		}
	}

}

class AttachedFlxText extends EditorText
{
	public var sprTracker:FlxSprite;
	public var xAdd:Float = 0;
	public var yAdd:Float = 0;

	public function new(X:Float = 0, Y:Float = 0, FieldWidth:Float = 0, ?Text:String, Size:Int = 8, EmbeddedFont:Bool = true)
	{
		super(X, Y, FieldWidth, Text, Size, EmbeddedFont);
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (sprTracker != null)
		{
			setPosition(sprTracker.x + xAdd, sprTracker.y + yAdd);
			angle = sprTracker.angle;
			alpha = sprTracker.alpha;
		}
	}
}

