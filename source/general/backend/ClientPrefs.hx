package general.backend;

import haxe.Exception;

import flixel.util.FlxSave;
import flixel.input.keyboard.FlxKey;
import flixel.input.gamepad.FlxGamepadInputID;

import states.titleState.TitleState;

import games.backend.ExtraKeysHandler.EKNoteColor;

import lime.system.Display;

#if mobile
import general.objects.screen.MouseEffect;
import general.shaders.MobileShaderConverter;
#end

// Add a variable here and it will get automatically saved
@:structInit class SaveVariables
{
	//更新这个直接原地爆破所有人设置
	public var prefsVersion:Int = 120;
	//更新这个能让性能相关的强制更新
	public var performanceDefaultsVersion:Int = 8;

	// General
	public var framerate:Int = 1000;
	public var drawFramerate:Int = 1000;
	public var lockRender:Bool = true;
	public var renderThread:Bool = true;
	public var resolution:String = 'Native';
	public var colorblindMode:String = 'None';
	public var lowQuality:Bool = false;
	public var gameQuality:Int = #if mobile 0 #else 1 #end;
	public var antialiasing:Bool = true;
	public var flashing:Bool = true;
	public var shaders:Bool = true;
	public var cacheOnGPU:Bool = false;
	public var autoPause:Bool = true;
	public var gcFreeZone:Bool = true;
	#if mobile
	public var autoOrientation:Bool = false;
	public var autoShaderConversion:Bool = true;
	public var mouseTrailEffect:Bool = true;
	#end

	// Gameplay
	public var downScroll:Bool = false;
	public var middleScroll:Bool = false;
	public var flipChart:Bool = false;
	public var ghostTapping:Bool = true;
	public var guitarHeroSustains:Bool = true;
	public var noReset:Bool = false;
	// Opponent s
	public var playOpponent:Bool = false;
	public var opponentCodeFix:Bool = false;
	public var botOpponentFix:Bool = true;
	public var healthDrainOPPOMult:Float = 0.5;
	public var healthDrainOPPO:Bool = false;

	// Backend
	// Gameplay backend s
	public var gameplayGC:Bool = false;
	public var fixLNL:Int = 0; // fix long note length
	public var saveScoreBase:String = 'Score';
	public var mainMusic:String = 'None';
	public var optionMusic:String = 'None';
	public var pauseMusic:String = 'Tea Time';
	public var hitsoundType:String = 'Default';
	public var hitsoundVolume:Float = 0;
	public var oldHscriptVersion:Bool = false;
	public var pauseButton:Bool = #if mobile true #else false #end;
	public var compulsionPause:Bool = false;
	public var compulsionPauseNumber:Int = 3;
	public var gameOverVibration:Bool = false;
	public var ratingOffset:Int = 0;
	public var noteOffset:Int = 0;
	public var replayQuality:Bool = true;
	public var showReplayWatermark:Bool = true;
	public var marvelousWindow:Int = 15;
	public var sickWindow:Int = 45;
	public var goodWindow:Int = 90;
	public var badWindow:Int = 135;
	public var safeFrames:Float = 10;
	public var marvelousRating:Bool = true;
	public var marvelousSprite:Bool = true;

	// App backend s
	public var discordRPC:Bool = true;
	public var checkForUpdates:Bool = true;
	public var screensaver:Bool = false;
	public var githubCheck:Bool = false;
	public var filesCheck:Bool = true;
	public var quotaGCIncreace:Float = 1;

	// Game UI
	// Visble s
	public var hideHud:Bool = false;
	public var showComboNum:Bool = true;
	public var showRating:Bool = true;
	public var opponentStrums:Bool = true;
	public var judgementCounter:Bool = false;
	public var keyboardViewer:Bool = true;
	// TimeBar s
	public var timeBarType:String = 'Time Left';
	// HealthBar s
	public var healthBarAlpha:Float = 1;
	public var oldHealthBarVersion:Bool = false;
	// Combe s
	public var comboStacking:Bool = true;
	public var comboColor:Bool = true;
	public var comboOffsetFix:Bool = true;
	// ================= KeyBoard（键盘反馈 / KeyboardViewer）=================
	//
	// ★ 这一组是「键盘反馈设置」界面的数据源（options/base/KeyboardViewerSubState.hx）。
	//   设置项的划分照 KeyDisplay 那套模板（基本 / 各键颜色 / 长条 / 长条颜色 / 消失效果 /
	//   统计 / 统计颜色 / 布局），只是这里全部由自绘界面读写，不再走 Option 列表。

	// ---- 基本 ----
	// ★ 总开关沿用上面 Gameplay 区已有的 `keyboardViewer`（游戏界面设置那条），不重复声明。
	/** 按键底色方块透明度（旧名 keyboardAlpha，保持存档兼容） */
	public var keyboardAlpha:Float = 0.8;
	/** 按下时的高亮透明度 */
	public var keyboardPressedAlpha:Float = 1;
	/** 按键方块基础大小（px，键与长条共用基准） */
	public var keyboardKeySize:Int = 50;
	/** 按键方块基础间距（px） */
	public var keyboardKeySpacing:Int = 4;
	/** 显示摁压的时间细节（长条） */
	public var keyboardTimeDisplay:Bool = true;
	/** 长条滞留时长（ms） */
	public var keyboardTime:Float = 500;
	/** 按键底色 */
	public var keyboardBGColor:String = 'WHITE';
	/** 按键文字色 */
	public var keyboardTextColor:String = 'BLACK';
	/**
	 * 当前套用的主题名：'default' / 'black' / 'fnf' / 'fnfpixel' / 'custom'。
	 * ★ 只要用户改动任何一项（包括逐键颜色），就自动回到 'custom' ——
	 *   选主题本身不算"改动"，它会一次性把整套配色铺到全部目标上。
	 */
	public var keyboardTheme:String = 'default';

	// ---- 各键颜色（10K 逐键，最多 10 组；空串 = 用默认纯白，与旧版观感一致）----
	public var keyboardKeyColor1:String = '';
	public var keyboardKeyColor2:String = '';
	public var keyboardKeyColor3:String = '';
	public var keyboardKeyColor4:String = '';
	public var keyboardKeyColor5:String = '';
	public var keyboardKeyColor6:String = '';
	public var keyboardKeyColor7:String = '';
	public var keyboardKeyColor8:String = '';
	public var keyboardKeyColor9:String = '';
	public var keyboardKeyColor10:String = '';

	// ---- 逐键颜色 · v2 补充 ----
	// ★ 键面这一版的规则是「只有颜色才逐键独立，其它（透明度/长条/统计区/配色来源）都是全局」。
	//   下面四组都遵守同一个约定：**空串 = 回退到旧版的全局值**，
	//   于是老存档不需要任何迁移，没设过的键观感与旧版完全一致。
	/** 第 n 键的常态文本颜色（空 = keyboardTextColor） */
	public var keyboardKeyTextColor1:String = '';
	public var keyboardKeyTextColor2:String = '';
	public var keyboardKeyTextColor3:String = '';
	public var keyboardKeyTextColor4:String = '';
	public var keyboardKeyTextColor5:String = '';
	public var keyboardKeyTextColor6:String = '';
	public var keyboardKeyTextColor7:String = '';
	public var keyboardKeyTextColor8:String = '';
	public var keyboardKeyTextColor9:String = '';
	public var keyboardKeyTextColor10:String = '';
	/** 第 n 键的按下颜色（空 = 用该键常态色，即旧版观感） */
	public var keyboardPressedColor1:String = '';
	public var keyboardPressedColor2:String = '';
	public var keyboardPressedColor3:String = '';
	public var keyboardPressedColor4:String = '';
	public var keyboardPressedColor5:String = '';
	public var keyboardPressedColor6:String = '';
	public var keyboardPressedColor7:String = '';
	public var keyboardPressedColor8:String = '';
	public var keyboardPressedColor9:String = '';
	public var keyboardPressedColor10:String = '';
	/** 第 n 键的按下文本颜色（空 = 按高亮色亮度自动挑黑/白，即旧版的 keyboardPressedTextColor） */
	public var keyboardPressedTextColor1:String = '';
	public var keyboardPressedTextColor2:String = '';
	public var keyboardPressedTextColor3:String = '';
	public var keyboardPressedTextColor4:String = '';
	public var keyboardPressedTextColor5:String = '';
	public var keyboardPressedTextColor6:String = '';
	public var keyboardPressedTextColor7:String = '';
	public var keyboardPressedTextColor8:String = '';
	public var keyboardPressedTextColor9:String = '';
	public var keyboardPressedTextColor10:String = '';
	/** 第 n 键的长条颜色（空 = 按 keyboardBarColorMode 决定，即旧版观感） */
	public var keyboardBarColor1:String = '';
	public var keyboardBarColor2:String = '';
	public var keyboardBarColor3:String = '';
	public var keyboardBarColor4:String = '';
	public var keyboardBarColor5:String = '';
	public var keyboardBarColor6:String = '';
	public var keyboardBarColor7:String = '';
	public var keyboardBarColor8:String = '';
	public var keyboardBarColor9:String = '';
	public var keyboardBarColor10:String = '';

	/** 第 n 键的**描边颜色**（空 = 跟随该键的常态色，即原来的观感） */
	public var keyboardKeyBorderColor1:String = '';
	public var keyboardKeyBorderColor2:String = '';
	public var keyboardKeyBorderColor3:String = '';
	public var keyboardKeyBorderColor4:String = '';
	public var keyboardKeyBorderColor5:String = '';
	public var keyboardKeyBorderColor6:String = '';
	public var keyboardKeyBorderColor7:String = '';
	public var keyboardKeyBorderColor8:String = '';
	public var keyboardKeyBorderColor9:String = '';
	public var keyboardKeyBorderColor10:String = '';

	/**
	 * 颜色跟随曲目音符配色。
	 * 开启后「各键颜色」不再用上面的逐键值，而是按当前曲目的箭头配色循环取色
	 * （第 i 个键取 `arrowRGB[i % 4]` 的 inner 色；跟随像素配色时取 arrowRGBPixel），
	 * 于是键盘反馈会和画面上的箭头/音符同色。
	 */
	public var keyboardFollowNoteColor:Bool = false;
	/** 跟随哪一套配色：'Normal' = arrowRGB，'Pixel' = arrowRGBPixel */
	public var keyboardFollowNotePalette:String = 'Normal';

	// ---- 长条（按下后向上漂的那根；总开关沿用上面的 keyboardTimeDisplay）----
	/** 长条透明度 */
	public var keyboardBarAlpha:Float = 1;
	/** 长条宽度（px；<=0 表示跟随按键宽度） */
	public var keyboardBarWidth:Int = 0;
	/** 长条最大高度（px；<=0 表示用按键大小 ×3，即旧版行为） */
	public var keyboardBarHeight:Int = 0;
	/** 长条上漂速度倍率（1 = 原版速度；duration = keyboardTime / speed） */
	public var keyboardBarSpeed:Float = 1;
	/** 连续按下时的长条创建间隔（秒；0 = 每次按下都创建） */
	public var keyboardBarInterval:Float = 0;
	/**
	 * 长条颜色模式：'Key' = 跟随该键的常态色，'Custom' = 用下面的自定义色。
	 * ★ 旧版的 'BG'（跟随按键底色 keyboardBGColor）已从设置界面移除，
	 *   默认改成 'Custom'，界面读到旧值时也会归一化 —— 否则长条会莫名跟着一个
	 *   用户早就忘了的旧字段走（本机存档里那字段是 #269AFF 蓝）。
	 */
	public var keyboardBarColorMode:String = 'Custom';
	/** 'Custom' 模式下的长条颜色 */
	public var keyboardBarColor:String = 'WHITE';
	/** 长条颜色跟随哪一套按键色：'Key' = 各键颜色，'Note' = 曲目配色（与 keyboardFollowNoteColor 无关，独立生效） */
	public var keyboardBarUseNoteColor:Bool = false;

	// ---- 消失效果 ----
	/** 消失模式：'sudden' 到时长即回收（旧版行为）/ 'fade' 先渐隐再回收 */
	public var keyboardBarDisappearMode:String = 'sudden';
	/** 渐隐速度（越大越快） */
	public var keyboardBarFadeSpeed:Float = 10;

	// ---- 统计（KPS / TOT）----
	public var keyboardStats:Bool = true;
	/** 统计区高度（px；<=0 表示跟随按键大小） */
	public var keyboardStatHeight:Int = 0;
	/** 统计区方块透明度（默认与按键透明度一致 = 旧版观感） */
	public var keyboardStatAlpha:Float = 0.8;
	/** TOT 数值更新间隔（秒） */
	public var keyboardTotInterval:Float = 0.05;
	/** KPS 底色 */
	public var keyboardStatKpsColor:String = 'WHITE';
	/** TOT 底色 */
	public var keyboardStatTotColor:String = 'WHITE';
	/** 统计标题颜色（KPS / total 两个字） */
	public var keyboardStatTitleColor:String = 'WHITE';
	/** 统计数值颜色（KPS / total 的数字；逐块重写用下面两个 Text 字段） */
	public var keyboardStatValueColor:String = 'WHITE';
	/** KPS 块的文本颜色（空 = 用 keyboardStatValueColor） */
	public var keyboardStatKpsTextColor:String = '';
	/** total 块的文本颜色（空 = 用 keyboardStatValueColor） */
	public var keyboardStatTotTextColor:String = '';
	/**
	 * 统计块宽度（占键盘反馈总宽度的百分比）。两个统计块共用同一个值 ——
	 * ★ 定稿规则：统计区的高度 / 宽度 / 透明度都是全局的，两个块一起变；
	 *   只有「颜色」才 KPS / total 各自独立。
	 */
	public var keyboardStatWidth:Float = 26;

	// ---- 布局 ----
	/** 整体纵向偏移（px） */
	public var keyboardOffsetY:Float = 0;
	/** 整体横向偏移（px） */
	public var keyboardOffsetX:Float = 0;
	/** 整体缩放 */
	public var keyboardScale:Float = 1;
	/** 在其它界面（如本设置界面）预览时使用的键数；0 = 自动（跟随当前曲目的 mania） */
	public var keyboardPreviewKeys:Int = 10;
	// Camera s
	public var camZooms:Bool = true;
	public var scoreZoom:Bool = true;

	// Skin
	public var noteSkin:String = 'Default';
	public var noteRGB:Bool = true;
	public var noteColorSwap:Bool = false;
	// splash s
	public var splashSkin:String = 'Psych';
	public var splashRGB:Bool = true;
	public var showSplash:Bool = true;
	public var splashAlpha:Float = 0.6;

	// Input
	// Moblie Input Backend s
	public var dynamicColors:Bool = true;
	public var needMobileControl:Bool = true; // work for desktop
	public var hitboxLocation:String = 'Bottom';
	public var controlsAlpha:Float = 0.6;
	public var playControlsAlpha:Float = 0.2;
	public var hideHitboxHints:Bool = false;

	public var extraKey:Int = 4;
	public var extraKeyReturn1:String = 'Space';
	public var extraKeyReturn2:String = 'Space';
	public var extraKeyReturn3:String = 'Shift';
	public var extraKeyReturn4:String = 'Shift';

	// User Interface
	public var uiScale:Float = 1;

	public var customFade:String = 'Move';
	public var customFadeSound:Float = 0.5;
	public var customFadeText:Bool = true;
	public var skipTitleVideo:Bool = false;
	public var audioDisplayQuality:Int = 1;
	public var audioDisplayUpdate:Int = 50;
	public var resultsScreen:Bool = true;
	public var loadingScreen:Bool = false;
	public var loadThreads:Int = #if mobile 2 #else 4 #end;
	public var useFlixelCoords:Bool = true;

	// Watermark
	public var showFPS:Bool = true;
	public var rainbowFPS:Bool = true;
	public var fpsDisplayMode:String = 'TPS';
	public var memoryType:String = 'Usage';
	public var fpsScale:Float = 1;
	public var watermarkScale:Float = 1;
	public var showWatermark:Bool = true;

	public var comboOffset:Array<Int> = [0, 0, 0, 0, 530, 470];

	public var language:String = 'English';

	public var storageFolder:String = 'Different Creatingness Engine';

	public var developerMode:Bool = false;
	public var devConScale:Float = #if mobile 1.8 #else 1.5 #end;
	public var deepDebug:Bool = false;

	// 维护设置 - Lua 语法错误提示。
	// ★ 只管"脚本报错"这一条通道（PlayState.addScriptErrorToDebug）：开启后 Lua 报错会像以前那样
	//   一条条铺在屏幕左上角，关闭（默认）则只写进日志。
	//   debugPrint / luaTrace / 引擎自身的缺 shader、缺视频等报错走的是 addTextToDebug，
	//   不受这个开关影响，始终照常显示。
	public var luaErrorOverlay:Bool = false;

	// 维护设置 - HScript 语法错误提示（与上面那条各自独立，互不影响）。
	// ★ 先澄清一件事：HScript 脚本自身的报错（Iris.error / Iris.warn）**本来就不上屏** ——
	//   链路是 Iris.logLevel → Sys.println + 开发者控制台 + 1145 trace 客户端，里面没有
	//   addTextToDebug。真正会铺到屏幕上的 HScript 红字只有 HScriptBase 里那几处脚本报错，
	//   这个开关管的就是它们（PlayState.addHScriptErrorToDebug）。
	public var hscriptErrorOverlay:Bool = false;

	// Trace Console / LOG 悬浮按钮的位置与尺寸记忆（-1 = 未自定义，用默认位置）
	public var consoleButtonX:Float = -1;
	public var consoleButtonY:Float = -1;
	public var consoleX:Float = -1;
	public var consoleY:Float = -1;
	public var consoleW:Float = -1;
	public var consoleH:Float = -1;

	// 维护设置 - 调整移动端各Editor键位（开启后隐藏默认Editor虚拟按键并启用外部按键编辑器）
	public var adjustMobileEditorKeys:Bool = false;

	// 一次性迁移标记：移动端首次运行（或从旧版升级）自动开启上面这项，
	// 让 APK 内置的 Editor 键位开箱即用；只生效一次，之后尊重用户手动开关。
	public var emkDefaultsVersion:Int = 0;

	//For Extra Keys (maybe)
	public var showKeybinds:Bool = false;
	
	public var enableRecordRotation:Bool = true;
	public var enableBpmZoom:Bool = true;
	
	//public var theme:Array<String> = ["Circle", "Straight", "None"];
	//public var songInfo:Array<String> = ["None", "Middle", "topLeft", "downLeft", "topRight", "downRight"];
	public var theme:String = "Circle";
	public var songInfo:String = "None";
	
	//////////////////////////////////////////////////////////////////////////////////////

	//Psych引擎的箭头RGB可以扔了，已经几乎被PsychEK代替了————卡昔233
	public var arrowRGB:Array<Array<FlxColor>> = [
		[0xFFC24B99, 0xFFFFFFFF, 0xFF3C1F56],
		[0xFF00FFFF, 0xFFFFFFFF, 0xFF1542B7],
		[0xFF12FA05, 0xFFFFFFFF, 0xFF0A4447],
		[0xFFF9393F, 0xFFFFFFFF, 0xFF651038]
	];

	public var arrowRGBPixel:Array<Array<FlxColor>> = [
		[0xFFE276FF, 0xFFFFF9FF, 0xFF60008D],
		[0xFF3DCAFF, 0xFFF4FFFF, 0xFF003060],
		[0xFF71E300, 0xFFF6FFE6, 0xFF003100],
		[0xFFFF884E, 0xFFFFFAF5, 0xFF6C0000]
	];

	//其实这个也可以扔了,我们有多k，，，，，
	public var arrowHSV:Array<Array<Float>> = [[0, 0, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0]];

	public var gameplaySettings:Map<String, Dynamic> = [
		'scrollspeed' => 1.0,
		'scrolltype' => 'multiplicative',
		'songspeed' => 1.0,
		'healthgain' => 1.0,
		'healthloss' => 1.0,
		'instakill' => false,
		'practice' => false,
		'botplay' => false,
		'opponentplay' => false
	];
}

class ClientPrefs
{
	public static var data:SaveVariables = {};
	public static var defaultData:SaveVariables = {};
	public static var modsData:Map<String, Map<String, Dynamic>>= [];

	// Every key has two binds, add your key bind down here and then add your control on options/ControlsSubState.hx and Controls.hx
	public static var keyBinds:Map<String, Array<FlxKey>> = [
		// Key Bind, Name for ControlsSubState
		'note_left' => [A, LEFT],
		'note_down' => [S, DOWN],
		'note_up' => [K, UP],
		'note_right' => [L, RIGHT],

		'0_key_0' => [SPACE],

		'1_key_0' => [D, LEFT],
		'1_key_1' => [K, RIGHT],

		'2_key_0' => [D],
		'2_key_1' => [SPACE],
		'2_key_2' => [K],

		'4_key_0' => [D],
		'4_key_1' => [F],
		'4_key_2' => [SPACE],
		'4_key_3' => [J],
		'4_key_4' => [K],

		'5_key_0' => [S],
		'5_key_1' => [D],
		'5_key_2' => [F],
		'5_key_3' => [J],
		'5_key_4' => [K],
		'5_key_5' => [L],

		'6_key_0' => [S],
		'6_key_1' => [D],
		'6_key_2' => [F],
		'6_key_3' => [SPACE],
		'6_key_4' => [J],
		'6_key_5' => [K],
		'6_key_6' => [L],

		'7_key_0' => [A],
		'7_key_1' => [S],
		'7_key_2' => [D],
		'7_key_3' => [F],
		'7_key_4' => [J],
		'7_key_5' => [K],
		'7_key_6' => [L],
		'7_key_7' => [SEMICOLON],

		'8_key_0' => [A],
		'8_key_1' => [S],
		'8_key_2' => [D],
		'8_key_3' => [F],
		'8_key_4' => [SPACE],
		'8_key_5' => [J],
		'8_key_6' => [K],
		'8_key_7' => [L],
		'8_key_8' => [SEMICOLON],

		'9_key_0' => [A],
		'9_key_1' => [S],
		'9_key_2' => [D],
		'9_key_3' => [F],
		'9_key_4' => [V],
		'9_key_5' => [N],
		'9_key_6' => [J],
		'9_key_7' => [K],
		'9_key_8' => [L],
		'9_key_9' => [SEMICOLON],

		'ui_up' => [W, UP],
		'ui_left' => [A, LEFT],
		'ui_down' => [S, DOWN],
		'ui_right' => [D, RIGHT],
		'accept' => [SPACE, ENTER],
		'back' => [BACKSPACE, ESCAPE],
		'pause' => [ENTER, ESCAPE],
		'reset' => [R],
		'volume_mute' => [#if mobile F10 #else ZERO #end],
		'volume_up' => [NUMPADPLUS, PLUS],
		'volume_down' => [NUMPADMINUS, MINUS],
		'debug_1' => [SEVEN],
		'debug_2' => [EIGHT],
		'fullscreen' => [F11]
	];

	/**
	 * "没有就会让玩家连菜单都操作不了"的基础键位。
	 *
	 * 与 `MusicBeatState.switchState()` 原本用来判断"要不要重置键位"的那组完全一致。
	 * 只有这几条被清空时 `repairMissingKeyBinds()` 才会兜底补回默认值 ——
	 * 其它键位空了代表玩家**故意删掉**（键位界面长按 Backspace），必须尊重。
	 */
	static final BASIC_KEYS:Array<String> = ['ui_up', 'ui_down', 'ui_left', 'ui_right', 'accept', 'back'];

	/**
	 * Detect a controls file that contains only the essential menu bindings.
	 * An empty new profile can otherwise load successfully and silently replace every
	 * gameplay/default binding with NONE. Keep individual user-cleared bindings intact;
	 * only treat the whole map as zeroed when every non-essential action is empty.
	 */
	static function isEffectivelyZeroedKeyBindMap(saved:Map<String, Array<FlxKey>>):Bool
	{
		if (saved == null) return false;
		if (defaultKeys == null) loadDefaultKeys();
		if (defaultKeys == null) return false;

		for (name in defaultKeys.keys())
		{
			if (BASIC_KEYS.contains(name)) continue;
			var binds:Array<FlxKey> = saved.get(name);
			if (binds == null) continue;
			for (key in binds)
				if (key != NONE)
					return false;
		}
		return true;
	}

	static function restoreCompiledKeyBinds():Void
	{
		if (defaultKeys == null) loadDefaultKeys();
		if (defaultKeys == null) return;
		keyBinds.clear();
		for (name => binds in defaultKeys)
			if (binds != null)
				keyBinds.set(name, binds.copy());
		repairMissingKeyBinds();
		reloadVolumeKeys();
	}

	public static var defaultMobileBinds:Map<String, Array<FlxKey>> = null;
	public static var defaultKeys:Map<String, Array<FlxKey>> = null;
	public static var defaultButtons:Map<String, Array<FlxGamepadInputID>> = null;

	public static function resetKeys(controller:Null<Bool> = null) // Null = both, False = Keyboard, True = Controller
	{
		if (controller == true) return;

		// Rebuild from the complete compiled defaults. Iterating the current map misses
		// actions that were removed from it, leaving those bindings empty after reset.
		if (defaultKeys == null) loadDefaultKeys();
		if (defaultKeys == null) return;

		for (key => defaults in defaultKeys)
			if (defaults != null)
				keyBinds.set(key, defaults.copy());

		repairMissingKeyBinds();
		reloadVolumeKeys();
		saveSettings();
	}

	public static function clearInvalidKeys(key:String)
	{
		var keyBind:Array<FlxKey> = keyBinds.get(key);
		while (keyBind != null && keyBind.contains(NONE))
			keyBind.remove(NONE);
	}

	/**
	 * 只补回"丢了 / 空了的键位"，**绝不整表清空**。
	 *
	 * ★ 修的是一条真实的"键位偶尔自己变回默认"路径（用户反馈：没碰过 R / Reset，
	 *   键盘设置也会莫名其妙被重置）。
	 *
	 * 起因在 `MusicBeatState.switchState()`：它原本只要发现
	 * `ui_up / ui_down / ui_left / ui_right / accept / back` 里**任何一条**是空的，
	 * 就 `keyBinds.clear()` 再用编译默认值把**整张表**重填一遍。而"一条变空"很容易
	 * 在正常使用中发生 —— 在键位界面里用【长按 Backspace 删除按键】删掉某条绑定后，
	 * `clearInvalidKeys()` 会把 NONE 直接 `remove`，数组长度就变成 0。
	 * 于是：
	 *   · 玩家自己改过的**所有**键位被无声丢弃（效果和"点了 R 重置"一模一样）；
	 *   · 紧接着任何一次 `saveSettings()`（离开设置界面、退出对局……）都会把这份
	 *     默认表写进 `controls_v4.sol` —— 从此不可恢复。
	 * 而这一切发生在**任意一次状态切换**里，玩家完全没碰过 R / Reset，
	 * 所以体感就是"偶尔被重置"。
	 *
	 * 现在的语义严格收敛为：
	 *   1) 整条**不在表里**的键位（旧存档 / 被别的代码 clear 过）→ 补回默认值；
	 *   2) 空了的基础操作键位（`BASIC_KEYS`：ui 方向 + accept + back）→ 补回默认值，
	 *      否则玩家连"退出这个界面"都按不出来，属于卡死级问题；
	 *   3) **其它键位一个字都不动** —— 尤其是"玩家自己在键位界面长按 Backspace 删掉"的
	 *      那一条，那是明确的用户意图，替他填回来就又变成"设置被重置"了。
	 *
	 * @return 实际补回的键位数量（0 = 什么都没改）
	 */
	public static function repairMissingKeyBinds():Int
	{
		if (keyBinds == null) return 0;

		// `defaultKeys` 由 Main.hx 在启动时用编译默认值填充；万一是空的自救一次。
		if (defaultKeys == null) loadDefaultKeys();
		if (defaultKeys == null) return 0;

		var repaired:Int = 0;

		// 1) 整条丢失：补回默认（只补"表里根本没有"的键，不覆盖玩家改过的值）
		var missing:Array<String> = [];
		for (name in defaultKeys.keys())
			if (!keyBinds.exists(name))
				missing.push(name);
		for (name in missing)
		{
			var def:Array<FlxKey> = defaultKeys.get(name);
			if (def == null || def.length == 0) continue;
			keyBinds.set(name, def.copy());
			repaired++;
		}

		// 2) 空了的基础操作键位：兜底（只救这几条，见函数注释）
		for (name in BASIC_KEYS)
		{
			var def:Array<FlxKey> = defaultKeys.get(name);
			if (def == null || def.length == 0) continue;

			var arr:Array<FlxKey> = keyBinds.get(name);
			if (arr == null)
			{
				keyBinds.set(name, def.copy());
				repaired++;
				continue;
			}

			// 只剩 NONE（理论上 clearInvalidKeys 会摘掉，这里再兜一层）也算空
			var isEmpty:Bool = (arr.length == 0);
			if (!isEmpty)
			{
				isEmpty = true;
				for (v in arr)
					if (v != NONE)
					{
						isEmpty = false;
						break;
					}
			}
			if (!isEmpty) continue;

			arr.resize(0);
			for (v in def)
				arr.push(v);
			repaired++;
		}

		if (repaired > 0)
		{
			FlxG.log.warn('[ClientPrefs] repaired $repaired missing/empty key bind(s); all other binds were left untouched.');
			reloadVolumeKeys();
		}
		return repaired;
	}

	public static function loadDefaultKeys()
	{
		defaultKeys = [for (key => value in keyBinds) key => value.copy()];
	}

	// ==================== 键盘反馈（KeyboardViewer）取值入口 ====================
	//
	// 说明：逐键颜色存成 keyboardKeyColor1..keyboardKeyColor10 这类独立字段（方便脚本按名读写），
	// 这里用 Reflect 按 0 起的序号访问，避免在界面代码里写 10 个 switch 分支。
	// v2 补的 keyboardKeyTextColorN / keyboardPressedColorN / keyboardPressedTextColorN /
	// keyboardBarColorN 走同一套读写；**空串一律表示"回退到旧版的全局值"**。

	/**
	 * 取值来源开关。
	 * 设置界面的「默认样式」那一排需要用 defaultData 来画，但下面这些入口都是静态的、
	 * 默认读 data —— 打开这个开关即可把整组取值整体切到 defaultData。
	 * ★ 只在画那一排期间打开，画完立刻复位；写入永远落回 data（见 perKeySet）。
	 */
	public static var previewUseDefault:Bool = false;

	inline static function kbSrc():SaveVariables
		return previewUseDefault ? defaultData : data;

	/** 按「前缀 + 1 起序号」读一个逐键颜色字段 */
	static function perKeyGet(prefix:String, idx:Int):String
	{
		if (idx < 0 || idx > 9) return '';
		var v:Dynamic = Reflect.field(kbSrc(), prefix + (idx + 1));
		return (v == null) ? '' : Std.string(v);
	}

	static function perKeySet(prefix:String, idx:Int, value:String):Void
	{
		if (idx < 0 || idx > 9) return;
		Reflect.setField(data, prefix + (idx + 1), (value == null) ? '' : value);
	}

	inline static function colOr(raw:String, fallback:FlxColor):FlxColor
		return (raw == null || raw == '') ? fallback : CoolUtil.colorFromString(raw);

	/** 第 idx 个键位（0 起）的常态色原始串；'' = 未设置（用默认纯白） */
	public static inline function getKeyboardKeyColorRaw(idx:Int):String return perKeyGet('keyboardKeyColor', idx);
	public static inline function setKeyboardKeyColorRaw(idx:Int, v:String):Void perKeySet('keyboardKeyColor', idx, v);
	/** 常态文本色 */
	public static inline function getKeyboardKeyTextColorRaw(idx:Int):String return perKeyGet('keyboardKeyTextColor', idx);
	public static inline function setKeyboardKeyTextColorRaw(idx:Int, v:String):Void perKeySet('keyboardKeyTextColor', idx, v);
	/** 按下色 */
	public static inline function getKeyboardPressedColorRaw(idx:Int):String return perKeyGet('keyboardPressedColor', idx);
	public static inline function setKeyboardPressedColorRaw(idx:Int, v:String):Void perKeySet('keyboardPressedColor', idx, v);
	/** 按下文本色 */
	public static inline function getKeyboardPressedTextColorRaw(idx:Int):String return perKeyGet('keyboardPressedTextColor', idx);
	public static inline function setKeyboardPressedTextColorRaw(idx:Int, v:String):Void perKeySet('keyboardPressedTextColor', idx, v);
	/** 长条颜色 */
	public static inline function getKeyboardBarColorRaw(idx:Int):String return perKeyGet('keyboardBarColor', idx);
	public static inline function setKeyboardBarColorRaw(idx:Int, v:String):Void perKeySet('keyboardBarColor', idx, v);
	/** 描边颜色 */
	public static inline function getKeyboardKeyBorderColorRaw(idx:Int):String return perKeyGet('keyboardKeyBorderColor', idx);
	public static inline function setKeyboardKeyBorderColorRaw(idx:Int, v:String):Void perKeySet('keyboardKeyBorderColor', idx, v);

	/** 跟随曲目配色时，第 idx 个键位取到的颜色（箭头配色表的 inner 色，按表长循环） */
	public static function keyboardNotePaletteColor(idx:Int):FlxColor
	{
		var d:SaveVariables = kbSrc();
		var table:Array<Array<FlxColor>> = (d.keyboardFollowNotePalette == 'Pixel') ? d.arrowRGBPixel : d.arrowRGB;
		if (table == null || table.length == 0) table = d.arrowRGB;
		if (table == null || table.length == 0) return FlxColor.WHITE;

		var n:Int = table.length;
		var row:Array<FlxColor> = table[((idx % n) + n) % n];
		if (row == null || row.length == 0) return FlxColor.WHITE;
		return row[0];
	}

	/** 键盘反馈第 idx 个键位最终使用的常态色（已处理「跟随曲目配色」） */
	public static function keyboardLaneColor(idx:Int):FlxColor
	{
		if (kbSrc().keyboardFollowNoteColor) return keyboardNotePaletteColor(idx);
		return colOr(getKeyboardKeyColorRaw(idx), FlxColor.WHITE);
	}

	/** 描边色：逐键优先，空则跟随该键常态色（= 旧版观感） */
	public static function keyboardKeyBorder(idx:Int):FlxColor
		return colOr(getKeyboardKeyBorderColorRaw(idx), keyboardLaneColor(idx));

	/** 常态文本色：逐键优先，空则回退全局 keyboardTextColor */
	public static function keyboardKeyText(idx:Int):FlxColor
		return colOr(getKeyboardKeyTextColorRaw(idx), keyboardText());

	/** 按下色：逐键优先，空则用该键常态色（旧版观感） */
	public static function keyboardPress(idx:Int):FlxColor
		return colOr(getKeyboardPressedColorRaw(idx), keyboardLaneColor(idx));

	/** 按下文本色：逐键优先，空则按高亮亮度自动反色 */
	public static function keyboardPressText(idx:Int):FlxColor
		return colOr(getKeyboardPressedTextColorRaw(idx), autoContrast(keyboardPress(idx)));

	/** 键盘反馈第 idx 个键位长条的颜色：逐键优先，其次看 keyboardBarColorMode */
	public static function keyboardBarLaneColor(idx:Int):FlxColor
	{
		var d:SaveVariables = kbSrc();
		if (d.keyboardBarUseNoteColor) return keyboardNotePaletteColor(idx);

		var per:String = getKeyboardBarColorRaw(idx);
		if (per != null && per != '') return CoolUtil.colorFromString(per);

		return switch (d.keyboardBarColorMode)
		{
			case 'Key': keyboardLaneColor(idx);
			case 'Custom': colOr(d.keyboardBarColor, FlxColor.WHITE);
			default: colOr(d.keyboardBGColor, FlxColor.WHITE); // 'BG'：旧版行为
		}
	}

	/** 键盘反馈按键底色 */
	public static function keyboardBG():FlxColor
		return colOr(kbSrc().keyboardBGColor, FlxColor.WHITE);

	/** 键盘反馈按键文字色（逐键未设时的全局回退值） */
	public static function keyboardText():FlxColor
		return colOr(kbSrc().keyboardTextColor, FlxColor.BLACK);

	/** 统计块（0 = KPS，1 = total）的常态底色 */
	public static function keyboardStatColor(idx:Int):FlxColor
	{
		var d:SaveVariables = kbSrc();
		var raw:String = (idx == 0) ? d.keyboardStatKpsColor : d.keyboardStatTotColor;
		return colOr(raw, FlxColor.WHITE);
	}

	/** 统计块文本色：逐块优先，空则回退 keyboardStatValueColor */
	public static function keyboardStatText(idx:Int):FlxColor
	{
		var d:SaveVariables = kbSrc();
		var raw:String = (idx == 0) ? d.keyboardStatKpsTextColor : d.keyboardStatTotTextColor;
		if (raw == null || raw == '') raw = d.keyboardStatValueColor;
		return colOr(raw, FlxColor.WHITE);
	}

	/** 按一个颜色的亮度挑黑/白文字，避免深色高亮上黑字看不见 */
	public static function autoContrast(c:FlxColor):FlxColor
	{
		var luminance:Float = (0.299 * c.red + 0.587 * c.green + 0.114 * c.blue) / 255;
		return luminance > 0.55 ? FlxColor.BLACK : FlxColor.WHITE;
	}

	/** 旧接口：按下时键位文字用什么颜色（= 常态色的自动反色） */
	public static function keyboardPressedTextColor(idx:Int):FlxColor
		return autoContrast(keyboardLaneColor(idx));

	public static function saveSettings()
	{
		for (key in Reflect.fields(data))
			if (key != 'arrowRGB' && key != 'arrowRGBPixel')
			{
				Reflect.setField(FlxG.save.data, key, Reflect.field(data, key));
			} //遍历data输入到flxsave里
		#if sys
		else if (key == 'arrowRGB')
			saveArrowRGBData('arrowRGB.json', data.arrowRGB);
		else if (key == 'arrowRGBPixel')
			saveArrowRGBData('arrowRGBPixel.json', data.arrowRGBPixel);
		#end

		FlxG.save.data.modsData = modsData;

		#if ACHIEVEMENTS_ALLOWED Achievements.save(); #end
		FlxG.save.flush();

		// Placing this in a separate save so that it can be manually deleted without removing your Score and stuff
		var save:FlxSave = new FlxSave();
		// ★ 必须看 bind 的返回值并且自己兜底 data：
		//   `FlxSave.bind()` 会先 destroy()（把 data 置 null），只有读取成功才会重新填上。
		//   键位文件一旦读不出来（写到一半被杀进程 / 旧版本写进了无法反序列化的类型），
		//   `save.data` 就还是 null，于是 `save.data.keyboard = keyBinds` 在 hxcpp 上是
		//   空指针写入（EXCEPTION_ACCESS_VIOLATION），而且这里还只是"保存设置"这一步。
		var bound:Bool = save.bind('controls_v4', CoolUtil.getSavePath(), recoverUnreadableControlsSave);
		if (bound && save.data != null)
		{
			save.data.keyboard = keyBinds;
			save.flush();
		}
		else
			FlxG.log.warn('[ClientPrefs] controls_v4 could not be bound; key binds were NOT written to disk.');
		FlxG.log.add("Settings saved!");
	}

	#if sys
	public static function saveArrowRGBData(path:String, rgbArray:Array<Array<FlxColor>>)
	{
		var saveArrowRGB:ArrowRGBSavedData;
		var colors:Array<EKNoteColor> = [];
		for (color in rgbArray)
		{
			var inner = color[0];
			var border = color[1];
			var outline = color[2];

			var resultColor = new EKNoteColor();
			resultColor.inner = inner.toHexString(false, false);
			resultColor.border = border.toHexString(false, false);
			resultColor.outline = outline.toHexString(false, false);

			colors.push(resultColor);

			// trace('Saved color ${resultColor.inner} ${resultColor.border} ${resultColor.outline}');
		}

		saveArrowRGB = new ArrowRGBSavedData(colors);
		var writer = new json2object.JsonWriter<ArrowRGBSavedData>();
		var content = writer.write(saveArrowRGB, '    ');
		File.saveContent(path, content);

		trace('Wrote to $path');
	}
	#end

	public static function loadArrowRGBData(path:String, pixel:Bool = false, defaultColors:Array<EKNoteColor>)
	{
		var savedColors:CoolUtil.ArrowRGBSavedData = CoolUtil.getArrowRGB(path, defaultColors);

		if (pixel)
			ClientPrefs.defaultData.arrowRGBPixel = [];
		else
			ClientPrefs.defaultData.arrowRGB = [];

		for (defaultColor in defaultColors)
		{
			var thisNote = [
				CoolUtil.colorFromString(defaultColor.inner),
				CoolUtil.colorFromString(defaultColor.border),
				CoolUtil.colorFromString(defaultColor.outline)
			];
			if (pixel)
				ClientPrefs.defaultData.arrowRGBPixel.push(thisNote);
			else
				ClientPrefs.defaultData.arrowRGB.push(thisNote);
		}

		if (pixel)
			ClientPrefs.data.arrowRGBPixel = [];
		else
			ClientPrefs.data.arrowRGB = [];

		for (color in savedColors.colors)
		{
			var thisNote = [
				CoolUtil.colorFromString(color.inner),
				CoolUtil.colorFromString(color.border),
				CoolUtil.colorFromString(color.outline)
			];

			// trace('Loaded color into save: $thisNote, pixel? $pixel');

			if (pixel)
				ClientPrefs.data.arrowRGBPixel.push(thisNote);
			else
				ClientPrefs.data.arrowRGB.push(thisNote);
		}
	}

	/**
	 * Guarantees that `FlxG.save.data` is a usable container.
	 *
	 * `FlxSave.bind()` calls `destroy()` first (which sets `data = null`) and only
	 * assigns a fresh value when the shared object loads successfully. So any save
	 * file that fails to load (parsing error, IO error, invalid path) leaves
	 * `FlxG.save.data` null, and reading a field off a null `Dynamic` is a hard
	 * access violation on hxcpp (`EXCEPTION_ACCESS_VIOLATION`, 0xC0000005) that
	 * kills the process before the first frame is drawn.
	 *
	 * Never let that happen: install an empty container and let the
	 * `prefsVersion` migration in `loadPrefs()` repopulate every default.
	 */
	public static function ensureSaveData():Dynamic
	{
		if (FlxG.save == null)
			return null;

		var current:Dynamic = FlxG.save.data;
		if (current == null)
		{
			current = {};
			@:privateAccess FlxG.save.data = current;
			FlxG.log.warn('[ClientPrefs] FlxG.save.data was null (save could not be loaded), starting from defaults.');
		}
		return current;
	}

	/**
	 * Recovery parser handed to `FlxSave.bind()` as its `backupParser` argument.
	 *
	 * flixel only calls this when the save file exists but cannot be unserialized
	 * (for example a save holding a class instance the runtime cannot rebuild, such
	 * as the `FlxPoint` values older builds wrote into the mobile control settings).
	 * Without a recovery parser `bind()` simply returns false and leaves `data`
	 * null, which is what used to crash the engine during boot; returning a fresh
	 * container keeps the game running, and the previous file is preserved on disk
	 * as `funkin.sol.unreadable` so nothing is lost silently.
	 */
	public static function recoverUnreadableSave(raw:String, error:Exception):Null<Dynamic>
	{
		FlxG.log.warn('[ClientPrefs] Save data could not be read ($error) - keeping a backup and starting from defaults.');

		#if sys
		try
		{
			if (raw != null && raw.length > 0)
				sys.io.File.saveContent('funkin.sol.unreadable', raw);
		}
		catch (e:Dynamic) {}
		#end

		return {};
	}

	/**
	 * 键位存档（`controls_v4.sol`）读取失败的恢复解析器。
	 *
	 * 为什么单独有一份：`funkin.sol` 早就带了 `recoverUnreadableSave`，但键位是存在
	 * 另一个文件里的，之前这里既没看 `bind()` 的返回值、也没处理 `data == null`：
	 *   · 读失败 → `save.data` 保持 null → 键位**静默**用回编译默认值
	 *     （用户看到的"键位莫名其妙被重置成 ASKL"）；
	 *   · 随后任意一次 `saveSettings()` 里 `save.data.keyboard = …` 又是对着 null 写入，
	 *     在 hxcpp 上直接 EXCEPTION_ACCESS_VIOLATION。
	 * 现在：留一份 `controls_v4.sol.unreadable` 备份、日志里说清楚、返回空容器让流程继续。
	 */
	public static function recoverUnreadableControlsSave(raw:String, error:Exception):Null<Dynamic>
	{
		FlxG.log.warn('[ClientPrefs] Key bind save (controls_v4) could not be read ($error) - keeping a backup; this run keeps the compiled default binds.');

		#if sys
		try
		{
			if (raw != null && raw.length > 0)
				sys.io.File.saveContent('controls_v4.sol.unreadable', raw);
		}
		catch (e:Dynamic) {}
		#end

		return {};
	}

	public static function loadPrefs()
	{
		// A failed `FlxG.save.bind()` leaves `data` null; repair it before touching it.
		ensureSaveData();

		#if ACHIEVEMENTS_ALLOWED Achievements.load(); #end

		if (FlxG.save.data.prefsVersion != data.prefsVersion)
		{
			data = {};
			modsData = [];
			for (key in Reflect.fields(defaultData))
			{
				if (key == 'arrowRGB' || key == 'arrowRGBPixel' || key == 'modsData')
					continue;
				if (key == 'gameplaySettings')
				{
					data.gameplaySettings.clear();
					for (k => v in defaultData.gameplaySettings)
						data.gameplaySettings.set(k, v);
					FlxG.save.data.gameplaySettings = data.gameplaySettings;
					continue;
				}
				Reflect.setField(data, key, Reflect.field(defaultData, key));
				Reflect.setField(FlxG.save.data, key, Reflect.field(defaultData, key));
			}
			FlxG.save.data.modsData = modsData;

			#if desktop
			data.framerate = 240;
			data.drawFramerate = 1200;
			Reflect.setField(FlxG.save.data, 'framerate', data.framerate);
			Reflect.setField(FlxG.save.data, 'drawFramerate', data.drawFramerate);
			#elseif (!html5 && !switch)
			final refreshRate:Int = FlxG.stage.application.window.displayMode.refreshRate;
			data.framerate = Std.int(FlxMath.bound(refreshRate * 2, 60, 1000));
			data.drawFramerate = Std.int(FlxMath.bound(refreshRate, 60, 1000));
			Reflect.setField(FlxG.save.data, 'framerate', data.framerate);
			Reflect.setField(FlxG.save.data, 'drawFramerate', data.drawFramerate);
			#end

			FlxG.save.flush();

			#if sys
			if (FileSystem.exists('arrowRGB.json')) FileSystem.deleteFile('arrowRGB.json');
			if (FileSystem.exists('arrowRGBPixel.json')) FileSystem.deleteFile('arrowRGBPixel.json');
			#end
			loadArrowRGBData('arrowRGB.json', false, ExtraKeysHandler.instance.data.colors);
			loadArrowRGBData('arrowRGBPixel.json', true, ExtraKeysHandler.instance.data.pixelNoteColors);

			if (defaultKeys == null)
				loadDefaultKeys();

			// Preference-version migrations reset general settings, but key binds live in
			// their own save and must survive unrelated preference changes.
			keyBinds.clear();
			for (name => keys in defaultKeys)
				keyBinds.set(name, keys.copy());

			var controlSave:FlxSave = new FlxSave();
			var controlsBound:Bool = controlSave.bind('controls_v4', CoolUtil.getSavePath(), recoverUnreadableControlsSave);
			if (controlsBound && controlSave.data != null)
			{
				// A profile can be migrated with a valid-looking map whose every gameplay
				// binding is NONE (for example, a newly-created app save directory). Do not
				// preserve that mass-clear as if it were an intentional per-key edit.
				if (isEffectivelyZeroedKeyBindMap(controlSave.data.keyboard))
				{
					restoreCompiledKeyBinds();
					FlxG.log.warn('[ClientPrefs] controls_v4 contained only essential menu binds; restored compiled defaults.');
				}
				else if (controlSave.data.keyboard != null)
				{
					// Merge saved controls over compiled defaults. This keeps newly added actions
					// available while preserving every known binding the player already changed.
					var savedControls:Map<String, Array<FlxKey>> = controlSave.data.keyboard;
					for (control => keys in savedControls)
						if (keyBinds.exists(control) && keys != null)
						{
							var arr:Array<FlxKey> = keyBinds.get(control);
							arr.resize(0);
							for (key in keys)
								arr.push(key);
						}
				}
				repairMissingKeyBinds();
				controlSave.data.keyboard = keyBinds;
				controlSave.flush();
			}
			else
				FlxG.log.warn('[ClientPrefs] controls_v4 could not be bound during preference migration; existing key bind data was not overwritten.');
			reloadVolumeKeys();
		}
		else
		{
			for (key in Reflect.fields(data))
				if (key != 'gameplaySettings' && 
					key != 'arrowRGB' &&
					key != 'arrowRGBPixel' &&
					// Keep the compiled migration target. Loading the saved marker
					// here makes the later comparison oldVersion < targetVersion
					// compare the old value with itself and silently skip migration.
					key != 'performanceDefaultsVersion' && Reflect.hasField(FlxG.save.data, key))
					Reflect.setField(data, key, Reflect.field(FlxG.save.data, key));
				else if (key == 'arrowRGB') 
				{
					loadArrowRGBData('arrowRGB.json', false, ExtraKeysHandler.instance.data.colors);
				} 
				else if (key == 'arrowRGBPixel') 
				{
					loadArrowRGBData('arrowRGBPixel.json', true, ExtraKeysHandler.instance.data.pixelNoteColors);
				}

			if (FlxG.save.data.modsData != null)
				modsData = FlxG.save.data.modsData;
			else modsData = [];

			var save:FlxSave = new FlxSave();
			// ★ 和 funkin.sol 一样带上恢复解析器：键位文件损坏时不要"静默回退到默认键位"，
			//   否则用户会遇到"键位莫名其妙变回 ASKL"，而且下一次保存就把默认值写死回去。
			//   这里至少留下一份 controls_v4.sol.unreadable 备份并在日志里说明原因。
			var bound:Bool = save.bind('controls_v4', CoolUtil.getSavePath(), recoverUnreadableControlsSave);
			if (bound && save.data != null)
			{
				if (save.data.keyboard != null)
				{
					var loadedControls:Map<String, Array<FlxKey>> = save.data.keyboard;
					if (isEffectivelyZeroedKeyBindMap(loadedControls))
					{
						restoreCompiledKeyBinds();
						save.data.keyboard = keyBinds;
						save.flush();
						FlxG.log.warn('[ClientPrefs] controls_v4 contained only essential menu binds; restored compiled defaults.');
					}
					else
						for (control => keys in loadedControls)
							if (keyBinds.exists(control) && keys != null)
							{
								var arr = keyBinds.get(control);
								arr.resize(0);
								for (i in keys)
									arr.push(i);
							}
				}
				reloadVolumeKeys();
			}
			else
				FlxG.log.warn('[ClientPrefs] controls_v4 could not be read; key binds keep their compiled defaults for this run.');
		}

		#if mobile
		// 移动端一次性迁移：首次运行（或旧版升级）自动启用“调整移动端各Editor键位”，
		// 让 APK 内置的 Editor 键位配置开箱即用；标记写入后不再强制，尊重用户手动开关。
		var savedEmkVersion:Dynamic = Reflect.field(FlxG.save.data, 'emkDefaultsVersion');
		if (savedEmkVersion == null || savedEmkVersion < data.emkDefaultsVersion)
		{
			data.adjustMobileEditorKeys = true;
			Reflect.setField(FlxG.save.data, 'adjustMobileEditorKeys', true);
			Reflect.setField(FlxG.save.data, 'emkDefaultsVersion', data.emkDefaultsVersion);
			FlxG.save.flush();
		}
		#end

		#if desktop
		// Migrate only the measured desktop scheduling defaults. Keep every other
		// preference and key binding intact.
		var savedPerformanceDefaultsVersion:Dynamic = Reflect.field(FlxG.save.data, 'performanceDefaultsVersion');
		if (savedPerformanceDefaultsVersion == null || savedPerformanceDefaultsVersion < data.performanceDefaultsVersion)
		{
			data.framerate = 240;
			data.drawFramerate = 1200;
			data.lockRender = true;
			// Lime's GL worker keeps a bounded two-frame pipeline. Keep driver
			// submission off the update thread; direct submission serializes UI
			// traversal with GL commands and causes a high-FPS regression.
			data.renderThread = true;
			// Keep desktop high-FPS mode at the engine's authored resolution.
			// Higher resolutions remain selectable, but should be an explicit
			// image-quality choice rather than a hidden cost on every interface.
			data.resolution = '720P';
			Reflect.setField(FlxG.save.data, 'framerate', data.framerate);
			Reflect.setField(FlxG.save.data, 'drawFramerate', data.drawFramerate);
			Reflect.setField(FlxG.save.data, 'lockRender', data.lockRender);
			Reflect.setField(FlxG.save.data, 'renderThread', data.renderThread);
			Reflect.setField(FlxG.save.data, 'resolution', data.resolution);
			Reflect.setField(FlxG.save.data, 'performanceDefaultsVersion', data.performanceDefaultsVersion);
			FlxG.save.flush();
		}
		#end

		if (Main.fpsVar != null)
			Main.fpsVar.visible = data.showFPS;

		#if (!html5 && !switch)
		FlxG.autoPause = data.autoPause;

		if (FlxG.save.data.framerate == null)
		{
			#if desktop
			data.framerate = 240;
			#else
			final refreshRate:Int = FlxG.stage.application.window.displayMode.refreshRate * 2;
			data.framerate = Std.int(FlxMath.bound(refreshRate, 60, 1000));
			#end
		}

		if (FlxG.save.data.drawFramerate == null)
		{
			#if desktop
			data.drawFramerate = 1200;
			#else
			final refreshRate:Int = FlxG.stage.application.window.displayMode.refreshRate;
			data.drawFramerate = Std.int(FlxMath.bound(refreshRate, 60, 1000));
			#end
		}
		#end

		var useRenderThread:Bool = data.renderThread;
		#if sys
		// Keep the saved preference as the default, while allowing repeatable
		// render-path A/B tests without rewriting the user's save file.
		final renderThreadOverride:String = Sys.getEnv('DCE_RENDER_THREAD');
		if (renderThreadOverride == '0')
			useRenderThread = false;
		else if (renderThreadOverride == '1')
			useRenderThread = true;
		#end
		lime.graphics.opengl.GL.setMultiThreaded(useRenderThread);

		#if mobile
		MobileShaderConverter.setEnabled(data.autoShaderConversion);
		MouseEffect.setUserEffectsEnabled(data.mouseTrailEffect);
		#end

		FlxG.updateFramerate = data.framerate;
		FlxG.drawFramerate = data.drawFramerate;
		mobile.backend.MobileRefreshRate.apply(data.drawFramerate);
		FlxG.stage.application.window.lockRender = #if android true #else data.lockRender #end;

		var output:Array<Float> = [];
		switch(data.resolution) {
			case '360P':
				output = [640, 360];
			case '480P':
				output = [854, 480];
			case '540P':
				output = [960, 540];
			case '720P':
				output = [1280, 720];
			case '768P':
				output = [1366, 768];
			case '900P':
				output = [1600, 900];
			case '1080P':
				output = [1920, 1080];
			case '1440P (2K)':
				output = [2560, 1440];
			case '1600P':	
				output = [2560, 1600];
			case '1800P':
				output = [3200, 1800];
			case '2160P (4K)':	
				output = [3840, 2160];
			default:
				var display:Display = lime.system.System.getDisplay(0);
				output = [display.bounds.width, display.bounds.height];
				data.resolution = "Native: " + display.bounds.width + "x" + display.bounds.height;
		}
		openfl.Lib.current.stage.setLogicalSize(Std.int(output[0]), Std.int(output[1]));

		if (FlxG.save.data.gameplaySettings != null)
		{
			var savedMap:Map<String, Dynamic> = FlxG.save.data.gameplaySettings;
			for (name => value in savedMap)
				data.gameplaySettings.set(name, value);
		}

		// flixel automatically saves your volume!
		if (FlxG.save.data.volume != null)
			FlxG.sound.volume = FlxG.save.data.volume;
		if (FlxG.save.data.mute != null)
			FlxG.sound.muted = FlxG.save.data.mute;

		#if DISCORD_ALLOWED
		DiscordClient.check();
		#end
	}

	inline public static function getGameplaySetting(name:String, defaultValue:Dynamic = null, ?customDefaultValue:Bool = false):Dynamic
	{
		if (!customDefaultValue)
			defaultValue = defaultData.gameplaySettings.get(name);
		return /*PlayState.isStoryMode ? defaultValue : */ (data.gameplaySettings.exists(name) ? data.gameplaySettings.get(name) : defaultValue);
	}

	public static function reloadVolumeKeys()
	{
		var _mk:Array<FlxKey> = keyBinds != null ? keyBinds.get('volume_mute') : null;
		TitleState.muteKeys = _mk != null ? _mk.copy() : [];
		var _dk:Array<FlxKey> = keyBinds != null ? keyBinds.get('volume_down') : null;
		TitleState.volumeDownKeys = _dk != null ? _dk.copy() : [];
		var _uk:Array<FlxKey> = keyBinds != null ? keyBinds.get('volume_up') : null;
		TitleState.volumeUpKeys = _uk != null ? _uk.copy() : [];
		toggleVolumeKeys(true);
	}

	public static function toggleVolumeKeys(?turnOn:Bool = true)
	{
		if (FlxG.sound != null) FlxG.sound.muteKeys = turnOn ? TitleState.muteKeys : [];
		if (FlxG.sound != null) FlxG.sound.volumeDownKeys = turnOn ? TitleState.volumeDownKeys : [];
		if (FlxG.sound != null) FlxG.sound.volumeUpKeys = turnOn ? TitleState.volumeUpKeys : [];
	}

	public static function get(variable:String, supportMods:Bool = true):Dynamic {
		if (supportMods) {
			if (modsData.get(Mods.currentModDirectory).get(variable) != null)
					return modsData.get(Mods.currentModDirectory).get(variable);

			if (modsData.get('Global mod').get(variable) != null)
					return modsData.get('Global mod').get(variable);

			for (mod in Mods.getGlobalMods())
			{
				if (modsData.get(mod).get(variable) != null)
					return modsData.get(mod).get(variable);
			}
		}

		if (Reflect.getProperty(ClientPrefs.data, variable) != null)
			return Reflect.getProperty(ClientPrefs.data, variable);

		return null;
	}

	public static function set(variable:String, data:Bool = true, path:String = '') {
		switch (path) {
			case '':
				if (Mods.currentModDirectory != '') {
					if (modsData.get(Mods.currentModDirectory) == null)
						modsData.set(Mods.currentModDirectory, []);
					modsData.get(Mods.currentModDirectory).set(variable, data);
				} else {
					if (modsData.get('Global mod') == null)
						modsData.set('Global mod', []);
					modsData.get('Global mod').set(variable, data);
				}
			case 'data':
				try{ Reflect.setProperty(ClientPrefs.data, variable, data); }
			case _:
				if (modsData.get(path) == null)
						modsData.set(path, []);
				modsData.get(path).set(variable, data);
		}
	}
}

