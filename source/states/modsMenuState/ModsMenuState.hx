package states.modsMenuState;

import flixel.graphics.FlxGraphic;
import flixel.input.touch.FlxTouch;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.util.FlxSpriteUtil;

import general.shapeEx.Rect; // 设置界面 BoolButton 用的圆角矩形控件（详情右上角开关直接复用它）
import general.objects.WindowControlBar;
import general.objects.WindowBarMode;

import flixel.input.keyboard.FlxKey;
import flixel.math.FlxMatrix;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;
import openfl.geom.Point;

import states.mainMenuState.MainMenuState;
import states.titleState.TitleState;
import states.freeplayState.FreeplayState;

/**
 * Mods 菜单（新界面 · 2026-09-19 重写）
 *
 * 由 `NewModsMenuState.htm` 原型 1:1 移植：
 *  - 自绘窗口条（CONSTANT）承载 9 个工具按钮 + [打开 mods 文件夹] + 搜索框 + [退出 mod 列表]，
 *    右侧是引擎原有的 [恢复默认][−][□][×]（窗口条由本状态自建，见 WindowChromeManager.editorScreens）；
 *  - 左侧 30%（0..384）＝ 顶部【已启用】【已禁用】标签 + 列表（pack 图标 | 名称 / 文件夹名）
 *    + 底部 RELOAD / 全部启用 / 全部禁用；
 *  - 右侧 70%（384..1280）＝ 详情（pack 大图 / 名称 / 元信息 / 徽章 / 右上角【启用 禁用】/
 *    可滚动描述 / 重启提示）；
 *  - 所有元素贴屏幕边缘，无外边距；
 *  - 长按 1 秒拖动排序（不足 1 秒松开 = 选中；先移动 = 滚动列表）；
 *  - 超长名字走马灯：只往一个方向滑（32px/s、起点停 0.9s、无缝循环）。Flixel 实现方式是
 *    「文本拼接两份 + 裁剪窗横移（clipRect）」—— 与原型里"两份文本"等价且不会折行；
 *  - pack 显示逻辑与原版完全一致（pack.png → pack-pixel.png → unknownMod.png，150px 切帧）。
 *
 * 保留的旧语义：`isFreePlay`、`waitingToRestart`、`modsList.txt` 读写、`Mods.currentModDirectory`、
 * 空列表每秒轮询、退出时 FlxG.resetGame()。
 * 模组设置：点齿轮**不再弹出** ModSettingsSubState，而是整个菜单原地变形（2026-09-27）——
 * 右侧详情整体上滚、左列表横向滚出只剩当前模组的卡片、卡片上移到标签栏位置（标签淡出），
 * 然后设置项在卡片下方排开（可滚动），右侧显示所选设置项的详情 + 顶部的调整值控件。
 */
class ModsMenuState extends MusicBeatState
{
	// ═══════════════ 静态 ═══════════════
	/** 是否从选歌界面进入（退出时回选歌而不是主菜单） */
	public static var isFreePlay:Bool = false;

	/** 长名字走马灯总开关（false = 直接按列宽裁断） */
	public static var marqueeEnabled:Bool = true;

	/**
	 * 文件调试日志开关：仅在 NF_BOOT_MODS=1（调试引导）时写入 <cwd>/modsmenu_debug.log。
	 * 为什么不用 trace()：1145 trace 端口在本机环境下只能收到连接时那句问候，
	 * 之后的 trace 全部到不了客户端（见 _dsh_tools 里的调试记录），
	 * 而调试需要确定性的反馈通道，所以走文件。
	 */
	public static var debugLog:Bool = false;
	static var debugPath:String = 'modsmenu_debug.log';

	public static function dbg(msg:String):Void
	{
		if (!debugLog) return;
		try
		{
			var f = sys.io.File.append(debugPath, false);
			f.writeString('[' + Date.now().toString() + '] ' + msg + '\n');
			f.close();
		}
		catch (e:Dynamic) {}
	}

	// ═══════════════ 指针：鼠标 + 触点统一入口 ═══════════════
	/**
	 * 为什么需要这一层：
	 *  ① 引擎默认把鼠标光标藏起来（`ClientPrefs.needMobileControl` 默认就是 true，
	 *     而 MainMenuState 里写的是 `FlxG.mouse.visible = !needMobileControl`）。
	 *     老代码把 `FlxG.mouse.visible` 当命中开关（`var over = FlxG.mouse.visible && ...`），
	 *     于是手机上（以及桌面开了"虚拟按键"时）**整个自绘界面都点不动** ——
	 *     没有模组时最明显：满屏按钮一个都点不了（用户报的就是这个）。
	 *  ② 移动端引擎自己的按钮走的是 `FlxG.touches`（见 source/mobile/flixel/FlxButton.hx），
	 *     这里一并支持触点，不依赖 OpenFL 的 touch→mouse 合成。
	 * 坐标统一取 `FlxG.camera` 的世界坐标：手机宽屏的黑边由 lime 缩放处理，
	 * `gameX/gameY` 已经算进去了，和自绘界面用的 1280×720 舞台坐标一致。
	 */
	static var ptrP:FlxPoint = FlxPoint.get();
	static var scratchRect:Rectangle = new Rectangle();
	static var scratchPoint:Point = new Point();

	/** 当前活动触点（按下 / 刚按下 / 刚抬起）；桌面返回 null */
	static function activeTouch():FlxTouch
	{
		for (t in FlxG.touches.list)
			if (t.pressed || t.justPressed || t.justReleased) return t;
		return null;
	}

	public static function pointerPressed():Bool
	{
		var t = activeTouch();
		if (t != null) return t.pressed;
		return (FlxG.mouse != null) && FlxG.mouse.pressed;
	}

	public static function pointerJustPressed():Bool
	{
		var t = activeTouch();
		if (t != null) return t.justPressed;
		return (FlxG.mouse != null) && FlxG.mouse.justPressed;
	}

	public static function pointerJustReleased():Bool
	{
		var t = activeTouch();
		if (t != null) return t.justReleased;
		return (FlxG.mouse != null) && FlxG.mouse.justReleased;
	}

	public static function pointerX():Float
	{
		var t = activeTouch();
		if (t != null) return t.getWorldPosition(FlxG.camera, ptrP).x;
		return (FlxG.mouse != null) ? FlxG.mouse.viewX : 0;
	}

	public static function pointerY():Float
	{
		var t = activeTouch();
		if (t != null) return t.getWorldPosition(FlxG.camera, ptrP).y;
		return (FlxG.mouse != null) ? FlxG.mouse.viewY : 0;
	}

	/** 指针是否落在矩形内（所有悬停/命中判定统一走这里） */
	public static function pointerOver(px:Float, py:Float, pw:Float, ph:Float):Bool
	{
		var t = activeTouch();
		if (t != null)
		{
			var p = t.getWorldPosition(FlxG.camera, ptrP);
			return p.x >= px && p.x < px + pw && p.y >= py && p.y < py + ph;
		}
		if (FlxG.mouse == null) return false;
		// 没有光标时，"正在按 / 刚按下"也算命中（桌面关掉光标同样能用）
		if (!FlxG.mouse.visible && !FlxG.mouse.pressed && !FlxG.mouse.justPressed) return false;
		return FlxG.mouse.viewX >= px && FlxG.mouse.viewX < px + pw && FlxG.mouse.viewY >= py && FlxG.mouse.viewY < py + ph;
	}

	/** 滚轮（移动端没有滚轮 → 0） */
	public static function pointerWheel():Int
	{
		return (FlxG.mouse != null) ? FlxG.mouse.wheel : 0;
	}

	// ═══════════════ 布局常量（1280×720，全部贴边） ═══════════════
	public static inline var BAR_H:Int = 36;
	public static inline var LEFT_W:Int = 384; // 30%
	public static inline var TAB_H:Int = 40;
	public static inline var FOOT_H:Int = 40;
	public static inline var ROW_H:Int = 56;
	public static inline var LIST_TOP:Int = BAR_H + TAB_H; // 76
	public static inline var LIST_H:Int = 720 - LIST_TOP - FOOT_H; // 604
	public static inline var RIGHT_X:Int = LEFT_W;
	public static inline var RIGHT_W:Int = 1280 - LEFT_W; // 896
	public static inline var DESC_BASE_Y:Int = BAR_H + 170; // 描述正文的基准 y

	// ── 模组设置（内嵌视图）──
	public static inline var SET_CARD_H:Int = 56; // 左侧卡片高度（复用列表行的视觉比例）
	public static inline var OPT_H:Int = 34; // 设置项行高
	public static inline var OPT_HEAD_H:Int = 30; // 分组标题行高
	public static inline var OPT_TOP:Int = BAR_H + 64; // 100：卡片下方选项列表的起始 y
	public static inline var OPT_VIEW_H:Int = 720 - OPT_TOP - FOOT_H; // 选项列表可视高度
	public static inline var SET_WY:Int = BAR_H + 64; // 右侧"调整值"控件空间的 y
	public static inline var SET_DESC_Y:Int = BAR_H + 128; // 右侧描述正文的基准 y

	// 交互常量
	static inline var LONG_PRESS:Float = 1.0; // 长按判定（秒）
	static inline var SCROLL_TOL:Float = 18; // 先移动超过这个距离 = 拖动列表滚动（不再长按）
	public static inline var MARQ_SPEED:Float = 32; // 走马灯速度 px/s（对齐 CharacterEditorMenuBar）
	public static inline var MARQ_GAP:Int = 48; // 循环衔接处的透明间隔
	public static inline var MARQ_HOLD:Float = 0.9; // 走马灯起点停留秒数
	public static inline var MARQ_END_HOLD:Float = 0.9; // 滑到底后的停留秒数

	// 滚动条
	static inline var SB_W:Int = 6; // 滑块宽
	static inline var SB_PAD:Int = 3; // 距列表右边缘
	static inline var SB_MIN:Float = 36; // 滑块最小高度

	// 颜色（D.C.E. 深色规范）
	public static inline var C_TEXT:FlxColor = 0xFFEDEFF7;
	public static inline var C_DIM:FlxColor = 0xFF9BA1B8;
	public static inline var C_HINT:FlxColor = 0xFF6F7690;
	public static inline var C_ACCENT:FlxColor = 0xFF96B5FF;
	public static inline var C_OK:FlxColor = 0xFF22C55E;
	public static inline var C_WARN:FlxColor = 0xFFF59E0B;
	public static inline var C_DANGER:FlxColor = 0xFFEF4444;
	static inline var C_PANEL:FlxColor = 0x66090A0F;
	static inline var C_BAR:FlxColor = 0xF20E0F15;
	// 行底色：白底靠 alpha 控制深浅（选中 ~0.20 / 未选中 ~0.03）
	public static inline var ROW_BG_A:Float = 0.03;
	public static inline var ROW_SEL_A:Float = 0.20;

	// ═══════════════ 数据 ═══════════════
	var modsList:ModsList = null;
	var rows:Array<ModRow> = [];
	var sel:Int = 0;
	var zone:Int = 0; // 0 = 列表 / 1 = 工具条
	var toolSel:Int = 0;
	var filter:Int = 0; // 0 = 已启用 / 1 = 已禁用 / 2 = 全部（再点当前标签 = 切到全部）
	var query:String = '';
	var dirty:Int = 0;
	var waitingToRestart:Bool = false; // 原字段：有改动 → 退出时整局重启
	var startMod:String = null;

	// 滚动
	var scrollY:Float = 0;
	var holdTime:Float = 0;

	// 长按 / 拖拽
	var pressIdx:Int = -1;
	var pressTimer:Float = 0;
	var pressMouseX:Float = 0;
	var pressMouseY:Float = 0;
	var pressMoved:Bool = false;
	var dragging:Bool = false;
	var dragSlot:Int = -1;
	var dragOffsetY:Float = 0; // 被拖行相对光标的偏移（跟手）
	var scrollDrag:Bool = false; // 先移动 = 拖动列表滚动
	var scrollDragBase:Float = 0; // 进入拖动滚动时的 scrollY
	var scrollDragMouseY:Float = 0;
	var holdBar:FlxSprite; // 长按进度条（原型 .bl-row.pressing::after）
	var pressHintBg:FlxSprite; // 光标旁提示气泡
	var pressHintTxt:FlxText;

	// 滚动条
	var sbTrack:FlxSprite;
	var sbThumb:FlxSprite;
	var sbThumbH:Float = SB_MIN;
	var sbDrag:Bool = false;
	var sbDragOfs:Float = 0;
	var dbgSb:String = '';

	// 相机
	var camHUD:FlxCamera;
	var listCam:FlxCamera;
	var camTop:FlxCamera;

	// 背景
	var bg:FlxSprite;

	// 窗口条
	var chrome:WindowControlBar = null;
	var barBg:FlxSprite;
	var barLine:FlxSprite;
	var tools:Array<BarButton> = [];
	var btnFolder:FlatButton = null;
	var btnExit:FlatButton = null;
	var searchBox:PsychUIInputText = null;
	var searchBg:FlxSprite = null;
	var searchPlaceholder:FlxText = null;
	var hintTxt:FlxText;
	var hintDefault:String = '';
	var lastHintW:Float = 200;
	var lastBarW:Int = -1;

	// 左栏
	var tabOn:TabButton = null;
	var tabOff:TabButton = null;
	var tabLine:FlxSprite;
	var tabBottom:FlxSprite;
	var listBg:FlxSprite;
	var listDiv:FlxSprite;
	var footTop:FlxSprite;
	/** 空状态（没有任何模组）：常规界面整片收起，只留空状态卡片 */
	var emptyMode:Bool = false;
	var dropLine:FlxSprite;
	var filterEmptyTxt:FlxText;
	var footReload:FlatButton = null;
	var footEnableAll:FlatButton = null;
	var footDisableAll:FlatButton = null;

	// 右栏
	var detailBg:FlxSprite;
	var detailLine:FlxSprite;
	var dIcon:FlxSprite;
	var dName:FlxText; // 23px（对齐原型 #dName），原先误用 Alphabet → 字体过大
	var dMetaTxt:FlxText;
	var dBadgeTxt:FlxText;
	var dBadgeBg:FlxSprite;
	var dToggle:SwitchButton = null;
	var dDescLabel:FlxText;
	var dDesc:FlxSprite; // 固定窗口位图（内容由 dDescContent blit 进来）
	var dDescGen:SharpText; // 超采样光栅源
	var dDescContent:BitmapData; // 完整描述位图（1:1）
	var descScrollY:Float = 0;
	var descMaxScroll:Float = 0;
	var descDragging:Bool = false;
	var descDragY:Float = 0;
	var restartHint:FlxText;
	var footNote:FlxText;

	// 空状态 / 确认 / 提示
	var emptyGfx:Array<FlxSprite> = [];
	var emptyTitle:FlxText;
	var emptyBody:FlxText;
	var emptyScan:FlxText;
	var emptyEgg:FlxText;
	var emptyFolderBtn:FlatButton = null;
	var emptyExitBtn:FlatButton = null;
	var scanTimer:Float = 0;
	var noModsSine:Float = 0;

	var maskSpr:FlxSprite;
	var confirmBg:FlxSprite;
	var confirmTitle:FlxText;
	var confirmBody:FlxText;
	var confirmYes:FlatButton = null;
	var confirmStay:FlatButton = null;

	var toastBg:FlxSprite;
	var toastTxt:FlxText;
	var toastTimer:Float = 0;

	// 每帧统一驱动悬停/点击
	public var allButtons:Array<FlatButton> = [];
	var bgColorTween:FlxTween = null;

	// ═══════════════ 模组设置（内嵌视图） ═══════════════
	var settingsMode:Bool = false; // 当前处于模组设置视图
	var setAnim:Bool = false; // 进出场动画进行中（屏蔽交互）
	var setReady:Bool = false; // 进入动画完成，设置 UI 可交互
	var setMod:ModRow = null; // 正在设置的模组
	var setFolder:String = '';
	var saveMap:Map<String, Dynamic> = null; // FlxG.save.data.modSettings[folder] 的工作副本
	var setOpts:Array<SettOpt> = []; // 解析后的设置项
	var optSel:Int = -1; // 当前选中的设置项（setOpts 下标，标题行不可选）
	var optScrollY:Float = 0;
	var setContentH:Float = 0;
	var capturing:Bool = false; // keybind 抓键中
	var setQuery:String = ''; // 设置视图的搜索词（小写）
	// 左侧卡片（camHUD）
	var cardBg:FlxSprite;
	var cardIcon:FlxSprite;
	var cardName:FlxText;
	var cardFolder:FlxText;
	// 左侧选项列表（setCam）+ 滚动条（camTop）
	var setCam:FlxCamera;
	var sTrack:FlxSprite;
	var sThumb:FlxSprite;
	var sThumbH:Float = SB_MIN;
	var sDrag:Bool = false;
	var sDragOfs:Float = 0;
	var optDragging:Bool = false;
	var optDragBase:Float = 0;
	var optDragY:Float = 0;
	var optMoved:Bool = false;
	// 右侧设置详情（camHUD）
	var setTitleTxt:FlxText;
	var wVal:FlxText;
	var wPrev:FlatButton;
	var wNext:FlatButton;
	var wKey:FlatButton;
	var tog:SettToggle = null;
	var sDesc:FlxSprite; // 固定窗口位图
	var sDescGen:SharpText; // 超采样光栅源
	var sDescContent:BitmapData; // 完整描述位图（1:1）
	var setDescScrollY:Float = 0;
	var setDescMax:Float = 0;
	var setDescDragging:Bool = false;
	var setDescDragY:Float = 0;
	var backBtn:FlatButton = null;
	/** 进场时记录的右侧详情元素原始 y（退场时逐个落回） */
	var detailSavedY:Array<{o:Dynamic, base:Float}> = [];

	public function new(startMod:String = null)
	{
		this.startMod = startMod;
		super();
	}

	// ══════════════════════════════════════════════════════════════════════
	// create
	// ══════════════════════════════════════════════════════════════════════
	override function create()
	{
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();
		persistentUpdate = false;
		// 文字清晰化不再走 FlxText.renderScale（InitState A/B 与实测都有重影/错位），
		// 改为每个文字 fmtSharp()：1.5 倍光栅 + 精灵缩回，见 TXT_SS 注释。

		modsList = Mods.parseList();
		Mods.currentModDirectory = modsList.all[0] != null ? modsList.all[0] : '';

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("In the Menus", null);
		#end

		// 背景（原版：menuDesat + 当前 mod 的 pack.color 补间）
		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.color = 0xFF665AFF;
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.screenCenter();
		add(bg);

		super.create(); // ★ 必须先 super：initPsychCamera() 会重置相机列表

		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		FlxG.cameras.add(camHUD, false);

		// 列表专用相机：视口 = 列表矩形 → 天然完成"裁剪 + 滚动"
		listCam = new FlxCamera(0, LIST_TOP, LEFT_W, LIST_H);
		listCam.bgColor.alpha = 0;
		FlxG.cameras.add(listCam, false);

		// 模组设置选项列表专用相机：视口从卡片下方开始（列表行横向滚出时不会穿帮到设置行）
		setCam = new FlxCamera(0, OPT_TOP, LEFT_W, OPT_VIEW_H);
		setCam.bgColor.alpha = 0;
		FlxG.cameras.add(setCam, false);

		// 顶层相机（在 listCam 之后加入 → 永远画在列表之上）：
		// 滚动条、长按提示气泡、确认框、toast 都放这里，否则会被列表行盖住
		camTop = new FlxCamera();
		camTop.bgColor.alpha = 0;
		FlxG.cameras.add(camTop, false);

		buildChrome();
		buildLeftPanel();
		buildDetailPanel();
		buildRows();
		buildEmptyState();
		buildConfirmOverlay();
		buildToast();
		buildSettingsPanel();

		// 插入指示线要在列表行之上（同一相机内后加 = 后画）
		remove(dropLine, false);
		add(dropLine);

		sel = 0;
		if (startMod != null)
		{
			for (i in 0...modsList.all.length)
				if (modsList.all[i] == startMod) sel = i;
		}

		FlxG.autoPause = false; // 空列表时要能"边开着菜单边往 mods/ 丢文件"
		lastBarW = -1;
		relayoutBar();
		refreshAll();
		updateEmptyStateVisibility();

		if (Sys.getEnv('NF_BOOT_MODS') == '1') debugLog = true;
		dbg('=== ModsMenuState.create: mods=' + modsList.all.length + ' enabled=' + modsList.enabled.length
			+ ' disabled=' + modsList.disabled.length + ' rows=' + rows.length + ' sel=' + sel
			+ ' screen=' + FlxG.width + 'x' + FlxG.height
			+ ' list=(0,' + LIST_TOP + ',' + LEFT_W + ',' + LIST_H + ')'
			+ ' exitBtnX=' + (btnExit != null ? Std.int(btnExit.x) : -1)
			+ ' chrome=' + (chrome != null) + ' ===');
		dbg('  buttons=' + allButtons.length + ' tools=' + tools.length);
	}

	#if NF_LEAK_PROBE
	/**
	 * 内存泄漏自动化测试入口（LeakHarness 的 mods 模式调用）。
	 * 复刻用户上报的完整流程：全部启用/禁用 → 等落定 → 🏠 确认弹窗 → "重启游戏"。
	 * 只在 `-D NF_LEAK_PROBE` 构建里存在。
	 */
	public function debugToggleAllAndRestart(enableAll:Bool):Void
	{
		dbg('[LeakTest] debugToggleAllAndRestart enableAll=' + enableAll);
		setAll(enableAll);
		new FlxTimer().start(4, function(_)
		{
			showConfirm();
			new FlxTimer().start(1, function(_) doRestartNow());
		});
	}
	#end

	// ══════════════════════════════════════════════════════════════════════
	// 构建：窗口条
	// ══════════════════════════════════════════════════════════════════════
	function buildChrome()
	{
		barBg = new FlxSprite(0, 0).makeGraphic(1280, BAR_H, C_BAR);
		addHud(barBg);

		barLine = new FlxSprite(0, BAR_H - 1).makeGraphic(1280, 1, 0x22FFFFFF);
		addHud(barLine);

		// 9 个工具按钮（原版 modsMenuButtons.png 帧：0=置顶 1=置底 4=上移 5=下移 2=上一个 3=下一个 6=设置 7=开关 8=退出）
		var frames:Array<Int> = [0, 1, 4, 5, 2, 3, 6, 7, 8];
		var keys:Array<String> = ['toolTop', 'toolBottom', 'toolUp', 'toolDown', 'toolPrev', 'toolNext', 'toolSettings', 'toolToggle', 'toolExit'];
		for (i in 0...frames.length)
		{
			var b = new BarButton(12 + i * 29, 5, frames[i], keys[i], function() toolAction(i));
			b.addTo(this, camHUD);
			tools.push(b);
		}

		// 顶栏右侧两颗按钮的语义随视图切换：
		//   常规视图：[打开外部mods]（退出按钮多余 —— 顶栏 🏠 本身就回主菜单）
		//   设置视图：[退出mods设置] [不保存设置退出mods界面]
		btnFolder = new FlatButton(0, 5, Language.get('openFolderShort', 'mods'), function()
		{
			if (settingsMode) exitSettings();
			else openModsFolder();
		});
		btnFolder.dbgName = 'bar:folder';
		btnFolder.addTo(this, camHUD);
		btnExit = new FlatButton(0, 5, Language.get('exitListShort', 'mods'), function()
		{
			if (settingsMode)
			{
				exitSettingsNoSave();
			}
			else exitMenu();
		});
		btnExit.dbgName = 'bar:exit';
		btnExit.addTo(this, camHUD);
		btnExit.setVisible(false); // 常规视图不需要它（🏠 可回主菜单）

		// 搜索框（引擎自绘 PsychUIInputText —— 与选歌界面同一个控件）
		searchBg = FlxSpriteUtil.drawRoundRect(new FlxSprite(0, 5).makeGraphic(196, 26, FlxColor.TRANSPARENT), 0, 0, 196, 26, 7, 7, 0xFF06070B);
		searchBg.alpha = 0.9;
		addHud(searchBg);

		searchBox = new PsychUIInputText(0, 10, 176, '', 12);
		searchBox.bg.visible = false;
		searchBox.behindText.alpha = 0;
		searchBox.textObj.font = Paths.font(Language.get('fontName', 'main') + '.ttf');
		searchBox.textObj.antialiasing = ClientPrefs.data.antialiasing;
		searchBox.textObj.color = C_TEXT;
		searchBox.caret.color = 0x727E7E7E;
		searchBox.onChange = function(old:String, cur:String)
		{
			query = (cur == null) ? '' : cur;
			if (searchPlaceholder != null) searchPlaceholder.visible = (query.length < 1);
			if (settingsMode)
			{
				// 设置视图：搜索框过滤的是设置项
				setQuery = query.toLowerCase();
				optScrollY = 0;
				setCam.scroll.y = 0;
				applyOptFilter();
				return;
			}
			scrollY = 0;
			var vis = visibleIndices();
			if (vis.length > 0 && vis.indexOf(sel) < 0) sel = vis[0];
			refreshList();
			refreshDetail();
		}
		searchBox.unfocus = function()
		{
			if (searchPlaceholder != null) searchPlaceholder.visible = (query.length < 1);
		}
		searchBox.cameras = [camHUD];
		searchBox.scrollFactor.set();
		add(searchBox);

		searchPlaceholder = new SharpText(0, 12, 0, Language.get('search', 'mods'), 12);
		fmtSharp(searchPlaceholder, 12, C_HINT);
		addHud(searchPlaceholder);

		hintDefault = Language.get('hintBar', 'mods');
		hintTxt = new SharpText(288, 11, 400, hintDefault, 11);
		fmtSharp(hintTxt, 11, C_HINT);
		addHud(hintTxt);

		// 引擎自绘窗口条（CONSTANT：分隔线 + 图标标题 + [恢复默认][−][□][×]）
		#if (cpp && windows)
		chrome = new WindowControlBar(WindowBarMode.CONSTANT);
		chrome.scrollFactor.set();
		chrome.cameras = [camHUD];
		add(chrome);
		#end
	}

	function toolAction(i:Int):Void
	{
		switch (i)
		{
			case 0: moveModToPosition(null, 0);
			case 1: moveModToPosition(null, modsList.all.length - 1);
			case 2: moveModToPosition(null, sel - 1);
			case 3: moveModToPosition(null, sel + 1);
			case 4: selectStep(-1);
			case 5: selectStep(1);
			case 6: openModSettings();
			case 7: toggleMod(sel);
			case 8: exitMenu();
		}
	}

	/** 按窗口宽度重排窗口条上的自定义控件（右边锚定 bar.titleAnchorX() - 11，避开拖窗区） */
	function relayoutBar()
	{
		lastBarW = FlxG.width;
		var w:Float = FlxG.width;

		barBg.makeGraphic(Std.int(w), BAR_H, C_BAR);
		barLine.makeGraphic(Std.int(w), 1, 0x22FFFFFF);
		barLine.x = 0;
		barLine.y = BAR_H - 1;

		var right:Float = w - 184 - 16 - titleWidth() - 22 - 11 - 12;
		if (right > w - 300) right = w - 300;
		if (right < 640) right = 640;

		if (settingsMode)
		{
			btnExit.setX(right - btnExit.w);
			btnFolder.setX(btnExit.x - 8 - btnFolder.w);
		}
		else
		{
			btnFolder.setX(right - btnFolder.w);
		}
		// 设置视图的【返回】按钮：跟着右上角按钮组走（搜索框左边；searchBg.x 在下一行才更新）
		if (backBtn != null) backBtn.setX(btnFolder.x - 8 - 196 - 8 - backBtn.w);
		searchBg.x = btnFolder.x - 8 - 196;
		searchBox.x = searchBg.x + 10;
		searchPlaceholder.x = searchBg.x + 10;
		// ★ 应用户要求：9 个工具按钮组与提示文案互换位置——提示文案贴左、按钮组靠右（紧挨搜索框左侧）
		var toolsStart:Float = searchBg.x - 16 - tools.length * 29;
		if (toolsStart < 150) toolsStart = 150;
		for (i in 0...tools.length)
			tools[i].setPosXY(toolsStart + i * 29, 5);
		hintTxt.x = 96; // too narrow on 1280 - hover tooltip covers it // 左上角是 FPS 显示的地盘，提示文案从它右侧起步
		hintTxt.y = 11;
		// ★ 提示栏宽度按实际可用空间给：太窄就换短文案，绝不让文字被裁断
		var avail:Float = Math.max(100, toolsStart - 12 - 16);
		sharpFieldW(hintTxt, avail);
		hintTxt.visible = avail >= 140; // 1280 宽下顶栏塞不下常驻提示，靠悬停浮动提示
		lastHintW = avail;
		hintTxt.text = hintFor(avail);
	}

	/** 按可用宽度挑提示文案（长版放不下就用短版） */
	function hintFor(avail:Float):String
	{
		if (dirty > 0) return fmt(Language.get('dirty', 'mods'), 'n', Std.string(dirty));
		var full:String = Language.get('hintBar', 'mods');
		if (full.length * 11 <= avail) return full;
		var short:String = Language.get('hintBarShort', 'mods');
		if (short.length * 11 <= avail) return short;
		return short;
	}

	function titleWidth():Float
	{
		#if (cpp && windows)
		if (chrome != null) return chrome.titleBlockWidth();
		#end
		return 150; // 非 windows 目标没有自绘条
	}

	// ══════════════════════════════════════════════════════════════════════
	// 构建：左栏
	// ══════════════════════════════════════════════════════════════════════
	function buildLeftPanel()
	{
		listBg = new FlxSprite(0, BAR_H).makeGraphic(LEFT_W, 720 - BAR_H - FOOT_H, 0x55101319);
		addHud(listBg);

		listDiv = new FlxSprite(LEFT_W - 1, BAR_H).makeGraphic(1, 720 - BAR_H, 0x22FFFFFF);
		addHud(listDiv);

		// 筛选/搜索后没有可见行时的占位文案
		filterEmptyTxt = new SharpText(0, LIST_TOP + 40, LEFT_W, Language.get('filterNone', 'mods'), 12);
		fmtSharp(filterEmptyTxt, 12, C_HINT, CENTER);
		addHud(filterEmptyTxt);
		filterEmptyTxt.visible = false;

		// 标签栏：整块扁平填充 + 状态圆点 + 数字胶囊 + 底部强调线（原型 .tab / .tab.on::after）
		tabOn = new TabButton(0, BAR_H, Std.int(LEFT_W / 2), TAB_H, 'tabEnabled', C_OK, function() setFilter(0));
		tabOn.dbgName = 'tab:enabled';
		tabOn.addTo(this, camHUD);

		tabOff = new TabButton(Std.int(LEFT_W / 2), BAR_H, Std.int(LEFT_W / 2), TAB_H, 'tabDisabled', C_DANGER, function() setFilter(1));
		tabOff.dbgName = 'tab:disabled';
		tabOff.addTo(this, camHUD);

		tabLine = new FlxSprite(0, BAR_H + TAB_H - 2).makeGraphic(Std.int(LEFT_W / 2), 2, C_ACCENT, true);
		addHud(tabLine);

		tabBottom = new FlxSprite(0, BAR_H + TAB_H - 1).makeGraphic(LEFT_W, 1, 0x22FFFFFF, true);
		addHud(tabBottom);

		// 拖拽插入指示线（挂在列表相机里 → 随滚动一起移动；不能设 scrollFactor(0,0)，否则不跟滚）
		dropLine = new FlxSprite(0, 0).makeGraphic(LEFT_W, 2, C_ACCENT, true);
		dropLine.cameras = [listCam];
		dropLine.visible = false;
		add(dropLine);

		// 长按进度条（按住时从行左侧长出来的下划线）
		holdBar = new FlxSprite(0, 0).makeGraphic(1, 2, C_ACCENT, true);
		addHud(holdBar);
		holdBar.visible = false;

		// 滚动条（原型 #listScroll 的 ::-webkit-scrollbar：轨道透明、滑块强调色）
		var trackH:Int = LIST_H - 8;
		sbTrack = new FlxSprite(LEFT_W - SB_W - SB_PAD, LIST_TOP + 4).makeGraphic(SB_W, trackH, 0x14FFFFFF, true);
		sbTrack.alpha = 0.9;
		addTop(sbTrack);
		sbThumb = new FlxSprite(sbTrack.x, sbTrack.y).makeGraphic(SB_W, Std.int(SB_MIN), 0x4296B5FF, true);
		// ★ origin 归零：Flixel 默认绕中心缩放，滑块会往上/下溢出到标签栏外面
		sbThumb.origin.set(0, 0);
		addTop(sbThumb);
		sbTrack.visible = sbThumb.visible = false;

		// 光标旁提示气泡（原型 #pressHint）
		pressHintBg = FlxSpriteUtil.drawRoundRect(new FlxSprite(0, 0).makeGraphic(1, 1, FlxColor.TRANSPARENT, true), 0, 0, 1, 1, 8, 8, 0xF208090D);
		pressHintTxt = new SharpText(0, 0, 0, '', 11);
		fmtSharp(pressHintTxt, 11, C_TEXT);
		addTop(pressHintBg);
		addTop(pressHintTxt);
		pressHintBg.visible = pressHintTxt.visible = false;

		// 底部三个原版按钮
		var bw = Std.int(LEFT_W / 3);
		footReload = new FlatButton(0, 720 - FOOT_H, Language.get('reload', 'mods'), function() reload());
		footReload.setSize(bw, FOOT_H);
		footReload.flat = true;
		footReload.dbgName = 'foot:reload';
		footReload.addTo(this, camHUD);

		footEnableAll = new FlatButton(bw, 720 - FOOT_H, Language.get('enableAll', 'mods'), function() setAll(true));
		footEnableAll.setSize(bw, FOOT_H);
		footEnableAll.flat = true;
		footEnableAll.dbgName = 'foot:enableAll';
		footEnableAll.addTo(this, camHUD);

		footDisableAll = new FlatButton(bw * 2, 720 - FOOT_H, Language.get('disableAll', 'mods'), function() setAll(false));
		footDisableAll.setSize(bw, FOOT_H);
		footDisableAll.flat = true;
		footDisableAll.dbgName = 'foot:disableAll';
		footDisableAll.addTo(this, camHUD);

		footTop = new FlxSprite(0, 720 - FOOT_H).makeGraphic(LEFT_W, 1, 0x22FFFFFF);
		addHud(footTop);
	}

	// ══════════════════════════════════════════════════════════════════════
	// 构建：右栏详情
	// ══════════════════════════════════════════════════════════════════════
	function buildDetailPanel()
	{
		detailBg = new FlxSprite(RIGHT_X, BAR_H).makeGraphic(RIGHT_W, 720 - BAR_H, C_PANEL);
		addHud(detailBg);

		dIcon = new FlxSprite(RIGHT_X + 20, BAR_H + 18);
		dIcon.antialiasing = ClientPrefs.data.antialiasing;
		addHud(dIcon);

		dName = new SharpText(RIGHT_X + 136, BAR_H + 30, 0, "", 23);
		fmtSharp(dName, 23, C_TEXT);
		dName.bold = true;
		dName.wordWrap = false;
		addHud(dName);

		dMetaTxt = new SharpText(RIGHT_X + 136, BAR_H + 70, RIGHT_W - 200, "", 12);
		fmtSharp(dMetaTxt, 12, C_DIM);
		addHud(dMetaTxt);

		dBadgeBg = new FlxSprite(RIGHT_X + 136, BAR_H + 92).makeGraphic(1, 24, 0x33FFFFFF);
		dBadgeBg.visible = false;
		addHud(dBadgeBg);

		dBadgeTxt = new SharpText(RIGHT_X + 146, BAR_H + 96, 0, "", 12);
		fmtSharp(dBadgeTxt, 12, C_TEXT);
		addHud(dBadgeTxt);

		// 右上角【启用 / 禁用】：宽度自适应内容，右对齐到面板内边距
		dToggle = new SwitchButton(RIGHT_X + RIGHT_W - 24 - 200, BAR_H + 16, function() toggleMod(sel));
		dToggle.addTo(this, camHUD);
		dToggle.setRight(RIGHT_X + RIGHT_W - 24);

		detailLine = new FlxSprite(RIGHT_X, BAR_H + 132).makeGraphic(RIGHT_W, 1, 0x22FFFFFF);
		addHud(detailLine);

		dDescLabel = new SharpText(RIGHT_X + 20, BAR_H + 148, 0, Language.get('descLabel', 'mods'), 11);
		fmtSharp(dDescLabel, 11, C_HINT);
		addHud(dDescLabel);

		dDescGen = new SharpText(RIGHT_X + 20, DESC_BASE_Y, RIGHT_W - 56, "", 13);
		fmtSharp(dDescGen, 13, 0xFFD7DBE6);
		dDescGen.wordWrap = true;
		dDesc = new FlxSprite(RIGHT_X + 20, DESC_BASE_Y).makeGraphic(Std.int((RIGHT_W - 56) * TXT_SS), Std.int((720 - DESC_BASE_Y - 60) * TXT_SS), FlxColor.TRANSPARENT, true);
		dDesc.scale.set(1 / TXT_SS, 1 / TXT_SS);
		dDesc.origin.set(0, 0);
		dDesc.offset.set(0, 0);
		addHud(dDesc);

		restartHint = new SharpText(RIGHT_X + 20, 720 - 32, 0, Language.get('restartHint', 'mods'), 11);
		fmtSharp(restartHint, 11, 0xFFF4C46B);
		addHud(restartHint);

		footNote = new SharpText(RIGHT_X + RIGHT_W - 24, 720 - 32, 0, "", 11);
		fmtSharp(footNote, 11, C_HINT);
		addHud(footNote);
	}

	// ══════════════════════════════════════════════════════════════════════
	// 构建：列表行
	// ══════════════════════════════════════════════════════════════════════
	function buildRows()
	{
		rows = [];
		for (i in 0...modsList.all.length)
		{
			var r = new ModRow(modsList.all[i], LEFT_W);
			r.addTo(this, listCam);
			rows.push(r);
		}
	}

	// ══════════════════════════════════════════════════════════════════════
	// 构建：空状态 / 确认层 / toast
	// ══════════════════════════════════════════════════════════════════════
	function buildEmptyState()
	{
		var bgS = new FlxSprite(0, BAR_H).makeGraphic(1280, 720 - BAR_H, 0x99090A0F);
		bgS.cameras = [camHUD];
		bgS.scrollFactor.set();
		add(bgS);
		emptyGfx.push(bgS);

		var box = FlxSpriteUtil.drawRoundRect(new FlxSprite(0, 0).makeGraphic(88, 88, FlxColor.TRANSPARENT), 0, 0, 88, 88, 24, 24, 0x1A96B5FF);
		box.x = 640 - 44;
		box.y = 250;
		addHud(box);
		emptyGfx.push(box);

		emptyTitle = new SharpText(0, 360, 1280, Language.get('emptyTitle', 'mods'), 24);
		fmtSharp(emptyTitle, 24, C_TEXT, CENTER);
		addHud(emptyTitle);
		emptyGfx.push(emptyTitle);

		emptyBody = new SharpText(320, 398, 640, Language.get('emptyBody1', 'mods') + '  mods/  ' + Language.get('emptyBody2', 'mods'), 13);
		fmtSharp(emptyBody, 13, C_DIM, CENTER);
		emptyBody.wordWrap = true;
		addHud(emptyBody);
		emptyGfx.push(emptyBody);

		emptyEgg = new SharpText(0, 428, 1280, '', 13);
		fmtSharp(emptyEgg, 13, 0xFFFF90DC, CENTER);
		addHud(emptyEgg);
		emptyGfx.push(emptyEgg);

		emptyFolderBtn = new FlatButton(0, 0, Language.get('openFolderShort', 'mods'), function() openModsFolder());
		emptyFolderBtn.setSize(180, 40);
		emptyFolderBtn.dbgName = 'empty:folder';
		emptyFolderBtn.addTo(this, camHUD);
		emptyExitBtn = new FlatButton(0, 0, Language.get('exitListShort', 'mods'), function() exitMenu());
		emptyExitBtn.setSize(160, 40);
		emptyExitBtn.dbgName = 'empty:exit';
		emptyExitBtn.addTo(this, camHUD);

		emptyScan = new SharpText(0, 496, 1280, Language.get('scanning', 'mods'), 12);
		fmtSharp(emptyScan, 12, C_HINT, CENTER);
		addHud(emptyScan);
		emptyGfx.push(emptyScan);

		if (FlxG.random.bool(0.1)) emptyEgg.text = 'BITCH.'; // 原版彩蛋保留
	}

	function buildConfirmOverlay()
	{
		maskSpr = new FlxSprite(0, 0).makeGraphic(1280, 720, 0xA6050509, true);
		addTop(maskSpr);

		confirmBg = FlxSpriteUtil.drawRoundRect(new FlxSprite(0, 0).makeGraphic(460, 210, FlxColor.TRANSPARENT, true), 0, 0, 460, 210, 14, 14, 0xFF14141B);
		confirmBg.x = 640 - 230;
		confirmBg.y = 360 - 105;
		addTop(confirmBg);

		confirmTitle = new SharpText(confirmBg.x, confirmBg.y + 26, 460, Language.get('exitTitle', 'mods'), 18);
		fmtSharp(confirmTitle, 18, C_TEXT, CENTER);
		addTop(confirmTitle);

		confirmBody = new SharpText(confirmBg.x + 24, confirmBg.y + 66, 412, Language.get('exitBody', 'mods'), 12);
		fmtSharp(confirmBody, 12, C_DIM, CENTER);
		confirmBody.wordWrap = true;
		addTop(confirmBody);

		confirmYes = new FlatButton(confirmBg.x + 24, confirmBg.y + 150, Language.get('restartNow', 'mods'), function() doRestartNow());
		confirmYes.setSize(200, 42);
		confirmYes.dbgName = 'confirm:restart';
		confirmYes.highlight = true;
		confirmYes.addTo(this, camTop);

		confirmStay = new FlatButton(confirmBg.x + 236, confirmBg.y + 150, Language.get('stayHere', 'mods'), function() hideConfirm());
		confirmStay.setSize(200, 42);
		confirmStay.dbgName = 'confirm:stay';
		confirmStay.addTo(this, camTop);

		hideConfirm();
	}

	function buildToast()
	{
		toastBg = new FlxSprite(0, 0).makeGraphic(360, 32, FlxColor.TRANSPARENT, true);
		addTop(toastBg);
		toastTxt = new SharpText(0, 0, 360, '', 12);
		fmtSharp(toastTxt, 12, C_TEXT, CENTER);
		addTop(toastTxt);
		toastBg.visible = false;
		toastTxt.visible = false;
	}

	inline function addHud(s:FlxSprite):Void
	{
		s.cameras = [camHUD];
		s.scrollFactor.set();
		add(s);
	}

	/** 画在列表之上的元素（滚动条 / 提示气泡 / 确认框 / toast） */
	inline function addTop(s:FlxSprite):Void
	{
		s.cameras = [camTop];
		s.scrollFactor.set();
		add(s);
	}

	// ══════════════════════════════════════════════════════════════════════
	// 刷新
	// ══════════════════════════════════════════════════════════════════════
	inline function isEnabled(m:ModRow):Bool
	{
		return !modsList.disabled.contains(m.folder);
	}

	function passFilter(m:ModRow):Bool
	{
		if (filter == 0 && !isEnabled(m)) return false;
		if (filter == 1 && isEnabled(m)) return false;
		if (query.length > 0)
		{
			var q = query.toLowerCase();
			if (m.name.toLowerCase().indexOf(q) < 0 && m.folder.toLowerCase().indexOf(q) < 0) return false;
		}
		return true;
	}

	function visibleIndices():Array<Int>
	{
		var vis:Array<Int> = [];
		for (i in 0...rows.length) if (passFilter(rows[i])) vis.push(i);
		return vis;
	}

	function listContentHeight():Float
	{
		return visibleIndices().length * ROW_H;
	}

	function refreshAll()
	{
		refreshTabs();
		refreshList();
		refreshDetail();
		refreshFooter();
		refreshDirty();
	}

	function refreshTabs()
	{
		if (settingsMode) return; // 设置视图：标签已淡出，别动它们
		var on = 0;
		for (m in modsList.all) if (!modsList.disabled.contains(m)) on++;
		var off = modsList.all.length - on;
		tabOn.setCount(on);
		tabOff.setCount(off);
		tabOn.setActive(filter == 0);
		tabOff.setActive(filter == 1);
		tabLine.visible = (filter != 2) && !emptyMode;
		tabLine.x = (filter == 1) ? LEFT_W / 2 : 0;
		dbg('tabs on=' + on + ' off=' + off + ' filter=' + filter + ' underline=' + (tabLine.visible ? Std.int(tabLine.x) + '..' + Std.int(tabLine.x + tabLine.width) : 'hidden')
			+ ' tabOn(count=' + on + ') tabOff(count=' + off + ')');
	}

	function refreshList()
	{
		if (settingsMode) return; // 设置视图：列表已滚出，行交给卡片接管
		var y = 0.0;
		for (i in 0...rows.length)
		{
			var r = rows[i];
			var vis = passFilter(r);
			r.setEnabledFlag(isEnabled(r));
			r.setVisible(vis);
			if (!vis) continue;
			r.index = i;
			r.setY(y);
			r.setSelected(i == sel && zone == 0);
			y += ROW_H;
		}

		// 筛选/搜索后一行都没有 → 显示占位文案（否则左栏会是一片空白）
		if (filterEmptyTxt != null)
		{
			var msg = (query.length > 0) ? Language.get('searchNone', 'mods') : Language.get('filterNone', 'mods');
			filterEmptyTxt.text = ModsMenuState.fmt(msg, 'q', query);
			filterEmptyTxt.visible = (modsList.all.length > 0 && y < 1);
		}

		var maxScroll = Math.max(0, listContentHeight() - LIST_H);
		if (scrollY > maxScroll) scrollY = maxScroll;
		if (scrollY < 0) scrollY = 0;
		listCam.scroll.y = scrollY;
		refreshScrollbar();
	}

	/** 滚动条：内容装得下就整条隐藏（原型 #listScroll 的滚动条同义） */
	function refreshScrollbar()
	{
		if (sbTrack == null || sbThumb == null) return;
		var content = listContentHeight();
		var need = content > LIST_H + 0.5;
		sbTrack.visible = need;
		sbThumb.visible = need;
		if (!need) return;

		var trackH = sbTrack.height;
		var maxScroll = Math.max(1, content - LIST_H);
		var th = Math.max(SB_MIN, trackH * (LIST_H / content));
		var ty = sbTrack.y + (trackH - th) * Math.max(0, Math.min(1, scrollY / maxScroll));
		sbThumbH = th; // ★ scale 不会更新 sprite.height，命中判定必须用这个值
		sbThumb.y = ty;
		sbThumb.scale.y = th / Math.max(1, sbThumb.frameHeight);
		if (dbgSb != (need + ':' + Std.int(ty) + ':' + Std.int(th)))
		{
			dbgSb = need + ':' + Std.int(ty) + ':' + Std.int(th);
			dbg('scrollbar track=(' + Std.int(sbTrack.x) + ',' + Std.int(sbTrack.y) + ',' + SB_W + ',' + Std.int(trackH)
				+ ') thumb=(' + Std.int(sbThumb.x) + ',' + Std.int(ty) + ',' + SB_W + ',' + Std.int(th)
				+ ') content=' + Std.int(content) + ' scrollY=' + Std.int(scrollY) + '/' + Std.int(maxScroll));
		}
		var px:Float = ModsMenuState.pointerX();
		var py:Float = ModsMenuState.pointerY();
		var hot = (px > sbTrack.x - 10 && px < sbTrack.x + SB_W + 10 && py >= sbTrack.y - 6 && py <= sbTrack.y + trackH + 6);
		sbThumb.alpha = (hot || sbDrag) ? 1 : 0.72;
		sbTrack.alpha = (hot || sbDrag) ? 1 : 0.75;
	}

	/**
	 * 描述区滚动：与走马灯同一个坑 —— clipRect 会把画面整体下移 clip.y，
	 * 所以滚动时必须把文本精灵上移同样的距离，窗口才固定。
	 */
	function applyDescScroll()
	{
		descScrollY = Math.max(0, Math.min(descScrollY, descMaxScroll));
		blitWindow(dDesc.pixels, dDescContent, Std.int(descScrollY * TXT_SS), Std.int((RIGHT_W - 56) * TXT_SS),
			Std.int((720 - DESC_BASE_Y - 60) * TXT_SS));
	}
	/** 光标旁的提示气泡（原型 #pressHint）：按住阶段 / 拖拽阶段两句文案 */
	function showPressHint(mx:Float, my:Float, holding:Bool)
	{
		var text = Language.get(holding ? 'pressHold' : 'pressDrag', 'mods');
		if (pressHintTxt.text != text)
		{
			pressHintTxt.text = text;
			var pw = Std.int(pressHintTxt.width) + 20;
			var ph = Std.int(pressHintTxt.height) + 10;
			pressHintBg.makeGraphic(pw, ph, FlxColor.TRANSPARENT, true);
			FlxSpriteUtil.drawRoundRect(pressHintBg, 0, 0, pw, ph, 8, 8, 0xF208090D);
			pressHintBg.visible = true;
			pressHintTxt.visible = true;
		}
		var px = Math.min(mx + 14, 1280 - pressHintBg.width - 6);
		var py = my + 18;
		if (py + pressHintBg.height > 716) py = my - pressHintBg.height - 10;
		pressHintBg.x = px - 6;
		pressHintBg.y = py - 4;
		pressHintTxt.x = px + 4;
		pressHintTxt.y = py + 1;
	}

	function hidePressHint()
	{
		if (pressHintTxt == null) return;
		pressHintTxt.visible = false;
		pressHintBg.visible = false;
	}

	/** floating tooltip for the 9 tool buttons (reuses the pressHint bubble) */
	function showToolTip(text:String)
	{
		if (pressHintTxt == null || pressIdx >= 0) return;
		if (pressHintTxt.text != text)
		{
			pressHintTxt.text = text;
			var pw = Std.int(pressHintTxt.width) + 20;
			var ph = Std.int(pressHintTxt.height) + 10;
			pressHintBg.makeGraphic(pw, ph, FlxColor.TRANSPARENT, true);
			FlxSpriteUtil.drawRoundRect(pressHintBg, 0, 0, pw, ph, 8, 8, 0xF208090D);
		}
		var mx:Float = pointerX();
		var my:Float = pointerY();
		var px = Math.min(mx + 14, 1280 - pressHintBg.width - 6);
		var py = my + 18;
		if (py + pressHintBg.height > 716) py = my - pressHintBg.height - 10;
		pressHintBg.x = px - 6;
		pressHintBg.y = py - 4;
		pressHintTxt.x = px + 4;
		pressHintTxt.y = py + 1;
		pressHintBg.visible = true;
		pressHintTxt.visible = true;
	}

	function refreshDetail()
	{
		if (settingsMode) return; // 设置视图：右侧详情已整体上滚
		if (rows.length < 1 || sel < 0 || sel >= rows.length)
		{
			dName.text = '';
			dDescGen.text = '';
			dDescContent = rasterizeBitmap(dDescGen);
		applyDescScroll();
			dMetaTxt.text = '';
			dBadgeTxt.text = '';
			dBadgeBg.visible = false;
			restartHint.visible = false;
			footNote.text = '';
			return;
		}
		var m:ModRow = rows[sel];

		// 背景染色（原版：FlxTween.color(bg, 1, bg.color, curMod.bgColor)）
		if (bgColorTween != null) bgColorTween.cancel();
		bgColorTween = FlxTween.color(bg, 0.7, bg.color, m.bgColor);

		if (m.iconGraphic != null)
		{
			dIcon.loadGraphic(m.iconGraphic, true, 150, 150);
			dIcon.antialiasing = m.iconAA && ClientPrefs.data.antialiasing;
			dIcon.scale.set(96 / 150, 96 / 150);
			dIcon.updateHitbox();
			if (m.frames > 1)
			{
				dIcon.animation.add('icon', [for (i in 0...m.frames) i], m.iconFps);
				dIcon.animation.play('icon');
			}
			else
			{
				dIcon.animation.stop();
			}
		}

		// 名称：23px（对齐原型 #dName），过长才缩字号，最小 15
		var fontName:String = Paths.font(Language.get('fontName', 'main') + '.ttf');
		fmtSharp(dName, 23, C_TEXT);
		dName.bold = true;
		dName.text = m.name;
		var maxNameW:Float = RIGHT_W - 320;
		if (dToggle != null) maxNameW = dToggle.left() - 16 - (RIGHT_X + 136); // 别撞上右上角的开关
		if (maxNameW < 120) maxNameW = 120;
		if (dName.width > maxNameW && dName.width > 0)
		{
			var s2:Int = Std.int(Math.max(15, 23 * (maxNameW / dName.width)));
			fmtSharp(dName, s2, C_TEXT);
			dName.bold = true;
		}
		dbg('detail sel=#' + pad2(sel + 1) + ' name="' + m.name + '" nameW=' + Std.int(dName.width) + ' nameH=' + Std.int(dName.height)
			+ ' fontSize=' + Std.int(dName.size) + ' text="' + dDescGen.text.substr(0, 24) + '"');

		dMetaTxt.text = Language.get('chipFolder', 'mods') + ': ' + m.folder
			+ '    #' + pad2(sel + 1)
			+ '    ' + Language.get('chipIcon', 'mods') + ': ' + m.frames + 'f @' + m.iconFps + 'fps'
			+ '    ' + Language.get('chipColor', 'mods') + ': ' + hex6(m.bgColor);

		var badges = '';
		if (m.runsGlobally) badges += '[' + Language.get('badgeGlobal', 'mods') + ']   ';
		if (m.mustRestart) badges += '[' + Language.get('badgeRestart', 'mods') + ']   ';
		if (m.hasSettings) badges += '[' + Language.get('badgeSettings', 'mods') + ']   ';
		if (!isEnabled(m)) badges += '[' + Language.get('badgeDisabled', 'mods') + ']';
		dBadgeTxt.text = badges;
		dBadgeBg.visible = badges.length > 0;
		if (dBadgeBg.visible)
		{
			var bw = Std.int(dBadgeTxt.width) + 20;
			dBadgeBg.makeGraphic(bw, 24, 0x33FFFFFF);
			dBadgeBg.x = RIGHT_X + 136;
			dBadgeBg.y = BAR_H + 92;
			dBadgeTxt.x = RIGHT_X + 146;
			dBadgeTxt.y = BAR_H + 96;
		}

		if (dToggle != null) dToggle.setState(isEnabled(m));

		dDescGen.text = (m.desc != null && m.desc.length > 0) ? m.desc : Language.get('noDesc', 'mods');
		dDescContent = rasterizeBitmap(dDescGen);
		// height 是视觉尺寸（帧 x scale），裁剪窗高度换算回视觉单位再相减
		descMaxScroll = Math.max(0, Std.int(dDescContent.height / TXT_SS) - (720 - DESC_BASE_Y - 60));
		applyDescScroll();

		restartHint.visible = m.mustRestart;
		footNote.text = 'mods/' + m.folder + '/pack.json';
		footNote.x = RIGHT_X + RIGHT_W - 24 - footNote.width;
	}

	function refreshFooter()
	{
		var anyOn = false, anyOff = false;
		for (m in modsList.all)
		{
			if (modsList.disabled.contains(m)) anyOff = true; else anyOn = true;
		}
		footEnableAll.setEnabled(anyOff);
		footDisableAll.setEnabled(anyOn);
		footReload.setEnabled(modsList.all.length > 0);
	}

	function refreshDirty()
	{
		hintTxt.color = (dirty > 0) ? 0xFFF4C46B : C_HINT;
		hintTxt.text = hintFor(lastHintW);
	}

	// ══════════════════════════════════════════════════════════════════════
	// 行为
	// ══════════════════════════════════════════════════════════════════════
	function selectMod(i:Int)
	{
		if (modsList.all.length < 1) return;
		sel = Std.int(Math.max(0, Math.min(modsList.all.length - 1, i)));
		zone = 0;
		dbg('select #' + pad2(sel + 1) + ' ' + rows[sel].folder + ' (enabled=' + isEnabled(rows[sel]) + ')');
		refreshList();
		refreshDetail();
	}

	function selectStep(step:Int)
	{
		var vis = visibleIndices();
		if (vis.length < 1) return;
		var at = vis.indexOf(sel);
		if (at < 0) at = 0;
		else at = ((at + step) % vis.length + vis.length) % vis.length;
		selectMod(vis[at]);
		ensureVisible();
	}

	function ensureVisible()
	{
		var vis = visibleIndices();
		var at = vis.indexOf(sel);
		if (at < 0) return;
		var rowTop = at * ROW_H;
		if (rowTop < scrollY) scrollY = rowTop;
		else if (rowTop + ROW_H > scrollY + LIST_H) scrollY = rowTop + ROW_H - LIST_H;
		scrollY = Math.max(0, Math.min(scrollY, Math.max(0, listContentHeight() - LIST_H)));
		listCam.scroll.y = scrollY;
	}

	function setFilter(f:Int)
	{
		filter = (filter == f) ? 2 : f; // 再点当前标签 = 取消筛选（显示全部）
		var vis = visibleIndices();
		if (vis.length > 0 && vis.indexOf(sel) < 0) sel = vis[0];
		scrollY = 0;
		refreshTabs();
		refreshList();
		refreshDetail();
		dbg('setFilter -> filter=' + filter + ' visible=' + vis.length + '/' + rows.length + ' sel=' + sel);
	}

	function toggleMod(i:Int)
	{
		if (i < 0 || i >= rows.length) return;
		var folder = rows[i].folder;
		if (!modsList.disabled.contains(folder))
		{
			modsList.enabled.remove(folder);
			modsList.disabled.push(folder);
		}
		else
		{
			modsList.disabled.remove(folder);
			modsList.enabled.push(folder);
		}
		dirty++;
		waitingToRestart = true; // 与原版一致：任何开关都置位
		saveTxt(); // ★ 立即落盘：顶栏 🏠 直接回主菜单也不会丢改动
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		var vis = visibleIndices();
		if (vis.length > 0 && vis.indexOf(sel) < 0) sel = vis[0];
		refreshTabs();
		refreshList();
		refreshDetail();
		refreshFooter();
		refreshDirty();
		dbg('toggle ' + folder + ' -> ' + (isEnabled(rows[i]) ? 'ON' : 'OFF') + ' dirty=' + dirty);
	}

	function setAll(enabled:Bool)
	{
		dbg('setAll enabled=' + enabled);
		var changed = 0;
		for (m in modsList.all)
		{
			var isOff = modsList.disabled.contains(m);
			if (enabled && isOff)
			{
				modsList.disabled.remove(m);
				modsList.enabled.push(m);
				changed++;
			}
			else if (!enabled && !isOff)
			{
				modsList.enabled.remove(m);
				modsList.disabled.push(m);
				changed++;
			}
		}
		if (changed > 0)
		{
			dirty += changed;
			waitingToRestart = true;
			saveTxt(); // ★ 立即落盘
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		}
		var vis = visibleIndices();
		if (vis.length > 0 && vis.indexOf(sel) < 0) sel = vis[0];
		refreshAll();
	}

	/** 对应原版 moveModToPosition：改的是 modsList.all 的顺序（= 加载优先级） */
	function moveModToPosition(?mod:String = null, position:Int = 0)
	{
		if (modsList.all.length < 2) return;
		if (mod == null)
		{
			if (sel < 0 || sel >= modsList.all.length) return;
			mod = modsList.all[sel];
		}
		var id = modsList.all.indexOf(mod);
		if (id < 0) return;
		moveOrder(id, position);
	}

	/** 把 from 号行移动到 to 号位置（绝对下标） */
	function moveOrder(from:Int, to:Int)
	{
		if (modsList.all.length < 2) return;
		var n = modsList.all.length;
		to = Std.int(Math.max(0, Math.min(n - 1, to)));
		if (from == to || from < 0 || from >= n) return;

		var mod = modsList.all[from];
		var row = rows[from];
		modsList.all.remove(mod);
		rows.remove(row);
		modsList.all.insert(to, mod);
		rows.insert(to, row);

		sel = to;
		dirty++;
		waitingToRestart = true; // 与原版一致：排序也置位
		saveTxt(); // ★ 立即落盘
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		refreshList();
		refreshDetail();
		refreshDirty();
		ensureVisible();
		showToast('#' + pad2(from + 1) + ' → #' + pad2(to + 1));
		dbg('moveOrder ' + mod + ' : #' + pad2(from + 1) + ' -> #' + pad2(to + 1) + ' dirty=' + dirty);
	}

	function reload()
	{
		dbg('reload() dirty=' + dirty);
		saveTxt();
		FlxG.autoPause = ClientPrefs.data.autoPause;
		FlxTransitionableState.skipNextTransIn = true;
		FlxTransitionableState.skipNextTransOut = true;
		MusicBeatState.switchState(new ModsMenuState(rows.length > 0 ? rows[sel].folder : null));
	}

	function openModSettings()
	{
		dbg('openModSettings sel=' + sel);
		if (rows.length < 1 || sel < 0 || sel >= rows.length) return;
		var m = rows[sel];
		if (m.settings == null || m.settings.length < 1)
		{
			showToast(Language.get('setNoneMod', 'mods'));
			return;
		}
		enterSettings(m);
	}

	// ══════════════════════════════════════════════════════════════════════
	// 模组设置（内嵌视图）：
	//   点齿轮 → 右侧详情整体上滚 / 左列表横向滚出只剩当前模组 / 标签淡出 /
	//   当前模组卡片上移到标签栏位置 → 设置项在卡片下方排开（可滚动），
	//   右侧 = 所选项详情 + 顶部调整值控件。Esc / 返回按钮退回（反向动画）。
	// ══════════════════════════════════════════════════════════════════════
	function buildSettingsPanel()
	{
		var fontName:String = Paths.font(Language.get('fontName', 'main') + '.ttf');

		// 返回按钮：设置模式下顶在右上角按钮组（左上角是 FPS 丈量地盘，不去凑热闹）
		backBtn = new FlatButton(0, 5, Language.get('setBack', 'mods'), function() exitSettings());
		backBtn.setSize(96, 26);
		backBtn.dbgName = 'set:back';
		backBtn.addTo(this, camHUD);
		backBtn.setVisible(false);

		// 左侧卡片（进场时从所选行的屏幕位置上移到标签栏位置）
		cardBg = new FlxSprite(0, 0).makeGraphic(LEFT_W, SET_CARD_H, 0xFFFFFFFF, true);
		cardBg.alpha = ROW_SEL_A;
		addHud(cardBg);

		cardIcon = new FlxSprite(12, 8);
		cardIcon.antialiasing = ClientPrefs.data.antialiasing;
		addHud(cardIcon);

		cardName = new SharpText(64, 11, LEFT_W - 76, '', 13);
		fmtSharp(cardName, 13, C_TEXT);
		cardName.wordWrap = false;
		addHud(cardName);

		cardFolder = new SharpText(64, 32, LEFT_W - 76, '', 11);
		fmtSharp(cardFolder, 11, C_HINT);
		cardFolder.wordWrap = false;
		addHud(cardFolder);
		setCardVisible(false);

		// 右侧：设置项名称 / 调整值空间 / 描述
		setTitleTxt = new SharpText(RIGHT_X + 24, BAR_H + 20, RIGHT_W - 48, '', 20);
		fmtSharp(setTitleTxt, 20, C_TEXT);
		setTitleTxt.bold = true;
		addHud(setTitleTxt);

		wVal = new SharpText(RIGHT_X + 24, SET_WY + 8, RIGHT_W - 48, '', 14);
		fmtSharp(wVal, 14, C_TEXT);
		addHud(wVal);

		sDescGen = new SharpText(RIGHT_X + 24, SET_DESC_Y, RIGHT_W - 48, '', 13);
		fmtSharp(sDescGen, 13, 0xFFD7DBE6);
		sDescGen.wordWrap = true;
		sDesc = new FlxSprite(RIGHT_X + 24, SET_DESC_Y).makeGraphic(Std.int((RIGHT_W - 48) * TXT_SS), Std.int((720 - SET_DESC_Y - 48) * TXT_SS), FlxColor.TRANSPARENT, true);
		sDesc.scale.set(1 / TXT_SS, 1 / TXT_SS);
		sDesc.origin.set(0, 0);
		sDesc.offset.set(0, 0);
		addHud(sDesc);

		// 调整值控件：◀ 值 ▶ / 开关 / 重设按键
		wPrev = new FlatButton(0, SET_WY, '<', function() adjustOpt(curOptSel(), -1));
		wPrev.setSize(44, 34);
		wPrev.dbgName = 'set:prev';
		wPrev.addTo(this, camHUD);
		wPrev.setVisible(false);

		wNext = new FlatButton(0, SET_WY, '>', function() adjustOpt(curOptSel(), 1));
		wNext.setSize(44, 34);
		wNext.dbgName = 'set:next';
		wNext.addTo(this, camHUD);
		wNext.setVisible(false);

		wKey = new FlatButton(0, SET_WY, Language.get('setBindReset', 'mods'), function() startCapture());
		wKey.setSize(110, 34);
		wKey.dbgName = 'set:rebind';
		wKey.addTo(this, camHUD);
		wKey.setVisible(false);

		tog = new SettToggle(RIGHT_X + 24, SET_WY + 2, function() adjustOpt(curOptSel(), 1));
		tog.addTo(this, camHUD);
		tog.setVisible(false);

		// 选项列表滚动条（同列表滚动条样式，挂在 camTop）
		sTrack = new FlxSprite(LEFT_W - SB_W - SB_PAD, OPT_TOP + 4).makeGraphic(SB_W, OPT_VIEW_H - 8, 0x14FFFFFF, true);
		sTrack.alpha = 0.9;
		addTop(sTrack);
		sThumb = new FlxSprite(sTrack.x, sTrack.y).makeGraphic(SB_W, Std.int(SB_MIN), 0x4296B5FF, true);
		sThumb.origin.set(0, 0); // ★ 归零 origin：绕中心缩放会让滑块溢出轨道
		addTop(sThumb);
		sTrack.visible = sThumb.visible = false;
	}

	function setCardVisible(v:Bool)
	{
		cardBg.visible = cardIcon.visible = cardName.visible = cardFolder.visible = v;
	}

	/** 卡片内容 = 当前模组（图标 / 名称 / 文件夹名，禁用态与列表行同色） */
	function setCardContent(m:ModRow)
	{
		if (m.iconGraphic != null)
		{
			cardIcon.loadGraphic(m.iconGraphic, true, 150, 150);
			cardIcon.antialiasing = m.iconAA && ClientPrefs.data.antialiasing;
			cardIcon.scale.set(40 / 150, 40 / 150);
			cardIcon.updateHitbox();
			if (m.frames > 1)
			{
				cardIcon.animation.add('icon', [for (i in 0...m.frames) i], m.iconFps);
				cardIcon.animation.play('icon');
			}
			else
				cardIcon.animation.stop();
		}
		cardName.text = m.name;
		cardFolder.text = m.folder;
		var en = isEnabled(m);
		cardName.color = en ? C_TEXT : 0xFF8A8F9E;
		cardFolder.color = en ? C_HINT : 0xFF6A6E7C;
		cardIcon.color = en ? FlxColor.WHITE : 0xFFFF6666;
	}

	/** 读取 FlxG.save.data.modSettings[folder] + 把 settings.json 解析成运行时选项 */
	function loadSettingsData(m:ModRow)
	{
		setFolder = m.folder;
		if (FlxG.save.data.modSettings == null) FlxG.save.data.modSettings = new Map<String, Dynamic>();
		saveMap = new Map<String, Dynamic>();
		var raw:Dynamic = cast(FlxG.save.data.modSettings, Map<String, Dynamic>)[setFolder];
		if (raw != null)
		{
			try
			{
				var cm:Map<String, Dynamic> = cast raw;
				for (k in cm.keys())
					saveMap.set(k, cm.get(k));
			}
			catch (e:Dynamic) {}
		}

		setOpts = [];
		for (option in m.settings)
		{
			var o = new SettOpt();
			o.saveKey = option.save;
			o.name = (option.name != null) ? Std.string(option.name) : Std.string(option.save);
			o.desc = (option.description != null) ? Std.string(option.description) : '';

			var t:String = (option.type != null ? Std.string(option.type) : 'bool').toLowerCase().trim();
			if (t == 'key' || t == 'keybind') t = 'keybind';
			else if (t == 'integer') t = 'int';
			else if (t == 'str') t = 'string';
			else if (t == 'fl') t = 'float';
			else if (t != 'bool' && t != 'int' && t != 'float' && t != 'percent' && t != 'string') t = 'bool';
			o.type = t;

			if (option.format != null) o.format = Std.string(option.format);
			if (option.scroll != null) o.scrollSpeed = option.scroll;

			switch (t)
			{
				case 'string':
					o.options = (option.options != null) ? (option.options : Array<String>) : [];
					// 单值 string 只在【没有描述】时才算分组标题；
					// Toolbox 的 Notice 项就是"单值 string + 长描述"，必须能选中查看描述
					o.isHeader = o.options.length < 2 && (o.desc == null || o.desc.length < 1);
					o.def = (option.value != null) ? option.value : (o.options.length > 0 ? o.options[0] : '');
					var v = saveMap.get(o.saveKey);
					o.value = (v != null) ? v : o.def;
					o.curIdx = o.options.indexOf(o.value);
					if (o.curIdx < 0) o.curIdx = 0;
					o.decimals = 0;
				case 'keybind':
					var v = saveMap.get(o.saveKey);
					if (v != null && v.keyboard != null)
						o.keys = {keyboard: v.keyboard, gamepad: (v.gamepad != null ? v.gamepad : 'NONE')};
					else
						o.keys = {keyboard: (option.keyboard != null ? Std.string(option.keyboard) : 'NONE'),
							gamepad: (option.gamepad != null ? Std.string(option.gamepad) : 'NONE')};
					o.value = o.keys.keyboard;
					saveMap.set(o.saveKey, o.keys);
					o.decimals = 0;
				case 'bool':
					o.def = (option.value != null) ? option.value : false;
					var v = saveMap.get(o.saveKey);
					o.value = (v != null) ? v : o.def;
					o.decimals = 0;
				case 'percent':
					if (option.format == null) o.format = '%v%';
					o.min = (option.min != null) ? option.min : 0;
					o.max = (option.max != null) ? option.max : 1;
					o.step = (option.step != null) ? option.step : 0.01;
					o.decimals = (option.decimals != null) ? Std.int(option.decimals) : 2;
					o.def = (option.value != null) ? option.value : 1;
					var v = saveMap.get(o.saveKey);
					o.value = (v != null) ? v : o.def;
				default: // int / float
					if (option.min != null) o.min = option.min;
					if (option.max != null) o.max = option.max;
					if (option.step != null) o.step = option.step;
					o.decimals = (option.decimals != null) ? Std.int(option.decimals) : (t == 'int' ? 0 : 1);
					o.def = (option.value != null) ? option.value : 0;
					var v = saveMap.get(o.saveKey);
					o.value = (v != null) ? v : o.def;
			}
			if (t != 'keybind') saveMap.set(o.saveKey, o.value);
			setOpts.push(o);
		}
	}

	/** 构建（重建）左侧选项行（setCam 世界坐标：y = uiY，相机滚动负责可视窗口） */
	function buildSettingsOptions()
	{
		// 上一模组的行先清掉（remove + kill，绝不 destroy —— 共享 FlxFrame 的教训）
		for (o in setOpts)
		{
			if (o.rowBg != null) remove(o.rowBg, true);
			if (o.nameTxt != null) remove(o.nameTxt, true);
			if (o.valTxt != null) remove(o.valTxt, true);
			o.rowBg = null;
			o.nameTxt = null;
			o.valTxt = null;
		}

		var fontName:String = Paths.font(Language.get('fontName', 'main') + '.ttf');
		var y:Float = 8;
		for (o in setOpts)
		{
			o.uiY = y;
			if (o.isHeader)
			{
				o.nameTxt = new SharpText(12, y + 6, LEFT_W - 24, flatName(o.name), 12);
				fmtSharp(o.nameTxt, 12, C_DIM);
				o.nameTxt.bold = true;
				o.nameTxt.cameras = [setCam];
				add(o.nameTxt);
				y += OPT_HEAD_H;
			}
			else
			{
				o.rowBg = new FlxSprite(0, y).makeGraphic(LEFT_W, OPT_H, 0xFFFFFFFF, true);
				o.rowBg.alpha = ROW_BG_A;
				o.rowBg.cameras = [setCam];
				add(o.rowBg);

				o.nameTxt = new SharpText(12, y + 8, LEFT_W - 150, flatName(o.name), 12);
				fmtSharp(o.nameTxt, 12, C_TEXT);
				o.nameTxt.wordWrap = false;
				o.nameTxt.cameras = [setCam];
				add(o.nameTxt);

				o.valTxt = new SharpText(12, y + 9, LEFT_W - 24, '', 11);
				fmtSharp(o.valTxt, 11, C_ACCENT, RIGHT);
				o.valTxt.cameras = [setCam];
				add(o.valTxt);
				y += OPT_H;
			}
		}
		setContentH = y + 8;
	}

	function flatName(s:String):String
	{
		return (s == null) ? '' : s.split('\n').join(' ');
	}

	// ── 进入 / 退出 ──
	function enterSettings(m:ModRow)
	{
		if (settingsMode || setAnim) return;
		settingsMode = true;
		setAnim = true;
		setReady = false;
		setMod = m;
		optSel = -1;
		optScrollY = 0;
		capturing = false;
		loadSettingsData(m);
		buildSettingsOptions();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		dbg('enterSettings folder=' + m.folder + ' opts=' + setOpts.length);

		// ① 左列表（含除当前行外的所有卡片）整体横向滚出视野
		FlxTween.tween(listCam.scroll, {x: -(LEFT_W + 60)}, 0.45, {ease: FlxEase.quadIn});
		rows[sel].setVisible(false); // 当前行由"卡片"接管

		// ② 卡片从行的屏幕位置上移到标签栏位置
		var visIdx = visibleIndices().indexOf(sel);
		var rowScreenY:Float = LIST_TOP + (visIdx < 0 ? 0 : visIdx) * ROW_H - scrollY;
		cardBg.setPosition(0, rowScreenY);
		cardIcon.x = 12;
		cardIcon.y = rowScreenY + 8;
		cardName.x = cardFolder.x = 64;
		cardName.y = rowScreenY + 11;
		cardFolder.y = rowScreenY + 32;
		setCardContent(m);
		setCardVisible(true);
		FlxTween.tween(cardBg, {y: BAR_H}, 0.45, {ease: FlxEase.quadOut});
		FlxTween.tween(cardIcon, {y: BAR_H + 8}, 0.45, {ease: FlxEase.quadOut});
		FlxTween.tween(cardName, {y: BAR_H + 11}, 0.45, {ease: FlxEase.quadOut});
		FlxTween.tween(cardFolder, {y: BAR_H + 32}, 0.45, {ease: FlxEase.quadOut});

		// ③ 已启用/已禁用 标签透明度归零
		fadeTabs(0, 0.35);
		sbTrack.visible = sbThumb.visible = false;

		// ④ 右侧详情页整体上滚（记录原始 y，退场时逐个落回）
		detailSavedY = [];
		var contents:Array<FlxSprite> = [dIcon, dName, dMetaTxt, dBadgeBg, dBadgeTxt, detailLine, dDescLabel, dDesc, restartHint, footNote];
		for (s in contents)
		{
			detailSavedY.push({o: s, base: s.y});
			FlxTween.tween(s, {y: s.y - 820}, 0.4, {ease: FlxEase.quadIn});
		}
		for (s in dToggle.contentSprites())
		{
			detailSavedY.push({o: s, base: s.y});
			FlxTween.tween(s, {y: s.y - 820}, 0.4, {ease: FlxEase.quadIn});
		}

		// ⑤ 常规控件让位
		for (t in tools)
			t.setVisible(false);
		footReload.setVisible(false);
		footEnableAll.setVisible(false);
		footDisableAll.setVisible(false);
		filterEmptyTxt.visible = false;
		backBtn.setVisible(true);
		hidePressHint(); // 悬浮的工具提示不能带进设置视图

		// 顶栏切换到设置语义：[退出mods设置] [不保存设置退出mods界面] [搜索设置项]
		btnFolder.setText(Language.get('setExitSettings', 'mods'));
		btnExit.setSize(190, 26);
		btnExit.setText(Language.get('setExitNoSave', 'mods'));
		btnExit.setVisible(true);
		searchPlaceholder.text = Language.get('searchSettings', 'mods');
		searchPlaceholder.visible = (query.length < 1);
		setQuery = '';
		applyOptFilter();
		lastBarW = -1; // 强制下一帧重排顶栏

		// ⑥ 动画完成后：设置项在卡片下方排开 + 右侧详情淡入
		new FlxTimer().start(0.5, function(_)
		{
			setAnim = false;
			setReady = true;
			optSel = firstSelectable();
			refreshOptRows();
			showSettingsUi(true);
			refreshSettingsDetail();
			ensureOptVisible();
			dbg('settings ready: sel=' + optSel);
		});
	}

	function exitSettings()
	{
		if (!settingsMode || setAnim) return;
		saveSettings();
		animateOutSettings();
	}

	/** 不保存设置，直接退出整个 mods 界面（设置改动丢弃 —— saveMap 只是工作副本） */
	function exitSettingsNoSave()
	{
		if (!settingsMode || setAnim) return;
		dbg('exitSettingsNoSave folder=' + setFolder);
		animateOutSettings();
		exitMenu();
	}

	function animateOutSettings()
	{
		capturing = false;
		setAnim = true;
		setReady = false;
		FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
		dbg('settings animateOut folder=' + setFolder);

		// 设置 UI 立即收起
		showSettingsUi(false);
		backBtn.setVisible(false);

		// 卡片滑回行的屏幕位置
		var visIdx = visibleIndices().indexOf(sel);
		var rowScreenY:Float = LIST_TOP + (visIdx < 0 ? 0 : visIdx) * ROW_H - scrollY;
		FlxTween.tween(cardBg, {y: rowScreenY}, 0.4, {ease: FlxEase.quadIn});
		FlxTween.tween(cardIcon, {y: rowScreenY + 8}, 0.4, {ease: FlxEase.quadIn});
		FlxTween.tween(cardName, {y: rowScreenY + 11}, 0.4, {ease: FlxEase.quadIn});
		FlxTween.tween(cardFolder, {y: rowScreenY + 32}, 0.4, {ease: FlxEase.quadIn});

		// 左列表滚回
		FlxTween.tween(listCam.scroll, {x: 0}, 0.4, {ease: FlxEase.quadOut});

		// 右侧详情落回原位
		for (r in detailSavedY)
			FlxTween.tween(r.o, {y: r.base}, 0.4, {ease: FlxEase.quadOut});

		// 标签恢复（直接按当前筛选态还原各元素的本征 alpha，避免和补间打架）
		tabOn.restoreVisual();
		tabOff.restoreVisual();
		tabLine.alpha = 1;
		tabBottom.alpha = 1;
		tabLine.visible = (filter != 2);

		// 常规控件回归
		for (t in tools)
			t.setVisible(true);
		footReload.setVisible(true);
		footEnableAll.setVisible(true);
		footDisableAll.setVisible(true);
		refreshFooter();

		// 顶栏还原常规语义
		btnFolder.setText(Language.get('openFolderShort', 'mods'));
		btnExit.setSize(120, 26);
		btnExit.setVisible(false); // 常规视图不需要（🏠 回主菜单）
		searchPlaceholder.text = Language.get('search', 'mods');
		setQuery = '';
		applyOptFilter();
		lastBarW = -1;

		new FlxTimer().start(0.45, function(_)
		{
			setAnim = false;
			settingsMode = false;
			setCardVisible(false);
			rows[sel].setVisible(true);
			refreshList();
			refreshDetail();
			refreshTabs();
			refreshScrollbar();
			dbg('settings closed');
		});
	}

	/** 保存到存档（与原 ModSettingsSubState.close() 同语义） */
	function saveSettings()
	{
		if (FlxG.save.data.modSettings == null) FlxG.save.data.modSettings = new Map<String, Dynamic>();
		cast(FlxG.save.data.modSettings, Map<String, Dynamic>).set(setFolder, saveMap);
		FlxG.save.flush();
		dbg('settings saved: ' + setFolder);
	}

	function fadeTabs(to:Float, dur:Float)
	{
		for (s in tabOn.contentSprites())
			FlxTween.tween(s, {alpha: to}, dur);
		for (s in tabOff.contentSprites())
			FlxTween.tween(s, {alpha: to}, dur);
		FlxTween.tween(tabLine, {alpha: to}, dur);
		FlxTween.tween(tabBottom, {alpha: to}, dur);
	}

	/** 显示/隐藏全部设置 UI（行 + 右侧面板 + 滚动条），显示时带 0.25s 淡入 */
	function showSettingsUi(v:Bool)
	{
		var fade:Float = v ? 0 : 0;
		for (i in 0...setOpts.length)
		{
			var o = setOpts[i];
			var rv:Bool = v && o.rowVisible;
			if (o.rowBg != null)
			{
				o.rowBg.visible = rv;
				o.rowBg.alpha = rv ? 0.01 : 0;
				if (rv) FlxTween.tween(o.rowBg, {alpha: (i == optSel) ? ROW_SEL_A : ROW_BG_A}, 0.25);
			}
			if (o.nameTxt != null)
			{
				o.nameTxt.visible = rv;
				o.nameTxt.alpha = fade;
				if (rv) FlxTween.tween(o.nameTxt, {alpha: 1}, 0.25);
			}
			if (o.valTxt != null)
			{
				o.valTxt.visible = rv;
				o.valTxt.alpha = fade;
				if (rv) FlxTween.tween(o.valTxt, {alpha: 1}, 0.25);
			}
		}
		setTitleTxt.visible = v;
		setTitleTxt.alpha = fade;
		if (v) FlxTween.tween(setTitleTxt, {alpha: 1}, 0.25);
		sDesc.visible = v;
		sDesc.alpha = fade;
		if (v) FlxTween.tween(sDesc, {alpha: 1}, 0.25);
		// ★ 类型相关控件（◀▶/开关/重设按键/wVal）的显隐由 refreshSettingsDetail 决定，
		//   这里只在收起时统一藏掉 —— 显示时越权全开会让 Notice 冒出红开关（实测教训）
		if (!v)
		{
			wVal.visible = false;
			wVal.alpha = 0;
			wPrev.setVisible(false);
			wNext.setVisible(false);
			wKey.setVisible(false);
			tog.setVisible(false);
			sTrack.visible = sThumb.visible = false;
		}
	}

	function firstSelectable():Int
	{
		for (i in 0...setOpts.length)
			if (!setOpts[i].isHeader && setOpts[i].rowVisible) return i;
		return -1;
	}

	/** 设置视图搜索：按名称过滤选项行（搜索框在设置视图里就是"搜索设置项"） */
	function applyOptFilter()
	{
		for (o in setOpts)
		{
			o.rowVisible = (setQuery.length < 1) || (o.name.toLowerCase().indexOf(setQuery) >= 0);
			var v:Bool = o.rowVisible && setReady && settingsMode;
			if (o.rowBg != null) o.rowBg.visible = v;
			if (o.nameTxt != null) o.nameTxt.visible = v;
			if (o.valTxt != null) o.valTxt.visible = v;
		}
		var cur = curOptSel();
		if (cur == null || !cur.rowVisible)
		{
			optSel = firstSelectable();
			refreshOptRows();
			refreshSettingsDetail();
		}
	}

	function curOptSel():SettOpt
	{
		return (optSel >= 0 && optSel < setOpts.length) ? setOpts[optSel] : null;
	}

	// ── 设置视图的刷新 ──
	function refreshOptRows()
	{
		for (i in 0...setOpts.length)
		{
			var o = setOpts[i];
			if (o.rowBg == null) continue;
			o.rowBg.alpha = (i == optSel) ? ROW_SEL_A : ROW_BG_A;
			o.valTxt.text = optValueText(o);
		}
	}

	/** 值的显示文案（与 BaseOptionsMenu.updateTextFrom 同一套 %v / %d 规则） */
	function optValueText(o:SettOpt):String
	{
		switch (o.type)
		{
			case 'bool':
				return (o.value == true) ? 'ON' : 'OFF';
			case 'string':
				return Std.string(o.value);
			case 'keybind':
				return o.keys != null ? o.keys.keyboard : 'NONE';
			default:
				var val:Float = o.value;
				if (o.type == 'percent') val *= 100;
				val = FlxMath.roundDecimal(val, o.decimals);
				return o.format.split('%v').join(Std.string(val)).split('%d').join(Std.string(o.def));
		}
	}

	/** 右侧详情 = 所选项名称 + 调整值控件 + 描述（instant=false 时开关用动画过渡） */
	function refreshSettingsDetail(instant:Bool = true)
	{
		var o = curOptSel();
		if (o == null)
		{
			setTitleTxt.text = '';
			sDescGen.text = '';
			sDescContent = rasterizeBitmap(sDescGen);
		applySetDescScroll();
			wVal.visible = false;
			wPrev.setVisible(false);
			wNext.setVisible(false);
			wKey.setVisible(false);
			tog.setVisible(false);
			return;
		}
		setTitleTxt.text = flatName(o.name); // 单行化，避免两行标题压到调整值控件
		sDescGen.text = (o.desc != null && o.desc.length > 0) ? o.desc : Language.get('noDesc', 'mods');
		sDescContent = rasterizeBitmap(sDescGen);
		setDescMax = Math.max(0, Std.int(sDescContent.height / TXT_SS) - (720 - SET_DESC_Y - 48));
		setDescScrollY = 0;
		applySetDescScroll();

		var isStr = (o.type == 'string');
		var isBool = (o.type == 'bool');
		var isKey = (o.type == 'keybind');
		var isNum = (!isStr && !isBool && !isKey);

		var canCycle = (isStr && o.options != null && o.options.length >= 2); // 单值 string 没得切，藏掉箭头
		wPrev.setVisible(canCycle || isNum);
		wNext.setVisible(canCycle || isNum);
		wKey.setVisible(isKey);
		tog.setVisible(isBool);
		wVal.visible = (canCycle || isNum || isKey);

		if (canCycle || isNum)
		{
			wPrev.setX(RIGHT_X + 24);
			wNext.setX(RIGHT_X + RIGHT_W - 24 - wNext.w);
			wVal.x = wPrev.x + wPrev.w + 14;
			sharpFieldW(wVal, wNext.x - 14 - wVal.x);
			wVal.alignment = CENTER;
			wVal.y = SET_WY + (34 - wVal.height) / 2;
			wVal.text = optValueText(o);
		}
		else if (isKey)
		{
			wVal.alignment = LEFT;
			sharpFieldW(wVal, RIGHT_W - 48);
			wVal.x = RIGHT_X + 24;
			wVal.y = SET_WY + 8;
			wKey.setX(RIGHT_X + 24);
			wKey.setPos(RIGHT_X + 24, SET_WY + 44);
			updateKeyText();
		}
		else
		{
			wVal.visible = false;
		}
		if (isBool) tog.setState(o.value == true, instant);
	}

	/** 调整值后只更新值区（不动描述、不让描述滚动归零） */
	function refreshSettingsValue()
	{
		var o = curOptSel();
		if (o == null) return;
		if (o.type == 'bool') tog.setState(o.value == true, false);
		else if (o.type == 'keybind') updateKeyText();
		else if (wVal.visible) wVal.text = optValueText(o);
	}

	function updateKeyText()
	{
		var o = curOptSel();
		if (o == null || o.type != 'keybind') return;
		wVal.text = capturing ? Language.get('setBindPrompt', 'mods') :
			ModsMenuState.fmt(ModsMenuState.fmt(Language.get('setBindTip', 'mods'), 'kb', o.keys.keyboard), 'gp', o.keys.gamepad);
	}

	function startCapture()
	{
		var o = curOptSel();
		if (o == null || o.type != 'keybind') return;
		capturing = true;
		updateKeyText();
	}

	/** 调整一项设置（dir：-1 / 1；bool 视 dir 为"切换"） */
	function adjustOpt(o:SettOpt, dir:Int)
	{
		if (o == null || o.isHeader || !setReady) return;
		switch (o.type)
		{
			case 'bool':
				o.value = !(o.value == true);
			case 'string':
				if (o.options.length < 2) return;
				var n = o.curIdx + dir;
				if (n < 0) n = o.options.length - 1;
				else if (n >= o.options.length) n = 0;
				o.curIdx = n;
				o.value = o.options[n];
			case 'int':
				var v = Std.int(o.value) + Std.int(o.step) * dir;
				if (o.min != null && v < o.min) v = Std.int(o.min);
				if (o.max != null && v > o.max) v = Std.int(o.max);
				o.value = v;
			case 'keybind':
				return; // 按键走抓键流程
			default: // float / percent
				var v:Float = o.value + o.step * dir;
				if (o.min != null && v < o.min) v = o.min;
				if (o.max != null && v > o.max) v = o.max;
				o.value = FlxMath.roundDecimal(v, o.decimals);
		}
		saveMap.set(o.saveKey, o.value);
		refreshOptRows();
		refreshSettingsValue();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
	}

	function selectOpt(i:Int)
	{
		if (i < 0 || i >= setOpts.length || setOpts[i].isHeader) return;
		if (i == optSel) return;
		optSel = i;
		refreshOptRows();
		refreshSettingsDetail();
		ensureOptVisible();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
	}

	function stepOptSel(step:Int)
	{
		if (setOpts.length < 1) return;
		var i = optSel;
		while (true)
		{
			i += step;
			if (i < 0 || i >= setOpts.length) return; // 到头就停（不绕圈，标题多时不乱跳）
			if (!setOpts[i].isHeader && setOpts[i].rowVisible)
			{
				selectOpt(i);
				return;
			}
		}
	}

	function maxOptScroll():Float
	{
		return Math.max(0, setContentH - OPT_VIEW_H);
	}

	function ensureOptVisible()
	{
		var o = curOptSel();
		if (o == null) return;
		var top = o.uiY;
		var bottom = o.uiY + ((o.isHeader) ? OPT_HEAD_H : OPT_H);
		if (top < optScrollY + 8) optScrollY = top - 8;
		else if (bottom > optScrollY + OPT_VIEW_H - 8) optScrollY = bottom - OPT_VIEW_H + 8;
		optScrollY = Math.max(0, Math.min(optScrollY, maxOptScroll()));
		setCam.scroll.y = optScrollY;
	}

	function applySetDescScroll()
	{
		setDescScrollY = Math.max(0, Math.min(setDescScrollY, setDescMax));
		blitWindow(sDesc.pixels, sDescContent, Std.int(setDescScrollY * TXT_SS), Std.int((RIGHT_W - 48) * TXT_SS),
			Std.int((720 - SET_DESC_Y - 48) * TXT_SS));
	}

	/** 选项行命中（返回 setOpts 下标；标题行也返回，交由 selectOpt 拒绝） */
	function optRowAt(sy:Float):Int
	{
		var local = sy - OPT_TOP + optScrollY;
		for (i in 0...setOpts.length)
		{
			var o = setOpts[i];
			if (!o.rowVisible) continue;
			var h:Float = o.isHeader ? OPT_HEAD_H : OPT_H;
			if (local >= o.uiY && local < o.uiY + h) return i;
		}
		return -1;
	}

	function updateSetScrollbar()
	{
		if (sTrack == null || sThumb == null || !setReady) return;
		var need = setContentH > OPT_VIEW_H + 0.5;
		sTrack.visible = sThumb.visible = need;
		if (!need) return;

		var trackH = sTrack.height;
		var maxScroll = Math.max(1, maxOptScroll());
		var th = Math.max(SB_MIN, trackH * (OPT_VIEW_H / setContentH));
		var ty = sTrack.y + (trackH - th) * Math.max(0, Math.min(1, optScrollY / maxScroll));
		sThumbH = th;
		sThumb.y = ty;
		sThumb.scale.y = th / Math.max(1, sThumb.frameHeight);
		var px:Float = pointerX();
		var py:Float = pointerY();
		var hot = (px > sTrack.x - 10 && px < sTrack.x + SB_W + 10 && py >= sTrack.y - 6 && py <= sTrack.y + trackH + 6);
		sThumb.alpha = (hot || sDrag) ? 1 : 0.72;
		sTrack.alpha = (hot || sDrag) ? 1 : 0.75;
	}

	// ── 设置视图的鼠标 / 键盘 ──
	function settingsMouse(elapsed:Float)
	{
		var mx:Float = pointerX();
		var my:Float = pointerY();
		var wheel:Int = pointerWheel();
		var justPressed:Bool = pointerJustPressed();
		var pressedNow:Bool = pointerPressed();
		var justReleased:Bool = pointerJustReleased();

		// 滚轮：左 = 滚设置项；右控件带 = 调整值；右下描述区 = 滚描述
		if (wheel != 0)
		{
			if (mx < LEFT_W && my >= OPT_TOP && my < 720 - FOOT_H)
			{
				optScrollY = Math.max(0, Math.min(optScrollY - wheel * 34, maxOptScroll()));
				setCam.scroll.y = optScrollY;
			}
			else if (mx >= RIGHT_X && my >= SET_WY - 6 && my < SET_WY + 46 && curOptSel() != null && !capturing)
			{
				adjustOpt(curOptSel(), wheel > 0 ? 1 : -1);
			}
			else if (mx >= RIGHT_X && my > SET_DESC_Y && my < 720 - 40 && setDescMax > 0)
			{
				setDescScrollY -= wheel * 40;
				applySetDescScroll();
			}
		}

		// 左侧选项行：按下 → 拖动滚动 / 松开 = 选中
		if (justPressed && mx < LEFT_W && my >= OPT_TOP && my < 720 - FOOT_H)
		{
			optDragging = true;
			optDragBase = optScrollY;
			optDragY = my;
			optMoved = false;
		}
		if (optDragging && pressedNow)
		{
			if (Math.abs(my - optDragY) > 8) optMoved = true;
			if (optMoved)
			{
				optScrollY = Math.max(0, Math.min(optDragBase - (my - optDragY), maxOptScroll()));
				setCam.scroll.y = optScrollY;
			}
		}
		if (optDragging && justReleased)
		{
			if (!optMoved)
			{
				var hit = optRowAt(my);
				if (hit >= 0) selectOpt(hit);
			}
			optDragging = false;
		}

		// 滚动条：拖动滑块 / 点轨道跳转
		if (sThumb != null && sThumb.visible)
		{
			var trackTop = sTrack.y;
			var trackH = sTrack.height;
			var maxScroll = Math.max(1, maxOptScroll());
			var overThumb = (mx >= sThumb.x - 4 && mx <= sThumb.x + SB_W + 4 && my >= sThumb.y && my <= sThumb.y + sThumbH);
			if (justPressed && overThumb)
			{
				sDrag = true;
				sDragOfs = my - sThumb.y;
			}
			else if (justPressed && mx >= sTrack.x - 6 && mx <= sTrack.x + SB_W + 6 && my >= trackTop && my <= trackTop + trackH)
			{
				optScrollY = ((my - trackTop - sThumbH / 2) / Math.max(1, trackH - sThumbH)) * maxScroll;
				optScrollY = Math.max(0, Math.min(optScrollY, maxScroll));
				setCam.scroll.y = optScrollY;
			}
			if (sDrag)
			{
				if (!pressedNow) sDrag = false;
				else
				{
					var frac = (my - sDragOfs - trackTop) / Math.max(1, trackH - sThumbH);
					optScrollY = Math.max(0, Math.min(1, frac)) * maxScroll;
					setCam.scroll.y = optScrollY;
				}
			}
		}

		// 描述区：按住拖动滚动
		if (setDescDragging)
		{
			if (!pressedNow) setDescDragging = false;
			else
			{
				setDescScrollY += (setDescDragY - my);
				setDescDragY = my;
				applySetDescScroll();
			}
		}
		else if (justPressed && mx >= RIGHT_X + 20 && my > SET_DESC_Y && my < 720 - 40 && setDescMax > 0)
		{
			setDescDragging = true;
			setDescDragY = my;
		}
	}

	function settingsKeys(elapsed:Float)
	{
		// keybind 抓键：按任意键写入，Esc 取消
		if (capturing)
		{
			var k:FlxKey = FlxG.keys.firstJustPressed();
			if (k != FlxKey.NONE)
			{
				capturing = false;
				var o = curOptSel();
				if (o != null && o.type == 'keybind' && k != FlxKey.ESCAPE)
				{
					o.keys.keyboard = Std.string(k);
					o.value = o.keys.keyboard;
					saveMap.set(o.saveKey, o.keys);
					refreshOptRows();
				}
				updateKeyText();
			}
			return;
		}

		if (controls.BACK)
		{
			exitSettings();
			return;
		}
		if (controls.UI_UP_P) stepOptSel(-1);
		else if (controls.UI_DOWN_P) stepOptSel(1);
		else if (controls.UI_LEFT_P)
		{
			if (curOptSel() != null) adjustOpt(curOptSel(), -1);
		}
		else if (controls.UI_RIGHT_P)
		{
			if (curOptSel() != null) adjustOpt(curOptSel(), 1);
		}
		else if (controls.ACCEPT)
		{
			var o = curOptSel();
			if (o != null)
			{
				if (o.type == 'keybind') startCapture();
				else adjustOpt(o, 1);
			}
		}
	}

	function openModsFolder()
	{
		var modFolder = Paths.mods();
		if (!FileSystem.exists(modFolder))
		{
			try FileSystem.createDirectory(modFolder) catch (e:Dynamic) { trace('create mods dir failed: $e'); }
		}
		#if mobile
		// ★ Android 上没有 explorer.exe / xdg-open：CoolUtil.openFolder 只在 Windows/Linux 生效，
		//   在手机上调用是个**静默空操作**（logcat 里只会留下 `explorer.exe \storage\...` 一行），
		//   用户点了"打开 mods 文件夹"就会觉得按钮坏了。这里改成把路径提示出来。
		showToast(ModsMenuState.fmt(Language.get('toastFolder', 'mods'), 'path', modFolder));
		#else
		CoolUtil.openFolder(modFolder);
		showToast(modFolder);
		#end
	}

	/** 退出：有改动 → 弹确认并整局重启；否则回主菜单 / 选歌（原版语义） */
	function exitMenu()
	{
		dbg('exitMenu dirty=' + dirty);
		if (dirty > 0)
		{
			showConfirm();
			return;
		}
		doExitToMenu();
	}

	function doExitToMenu()
	{
		dbg('doExitToMenu -> freeplay=' + isFreePlay);
		saveTxt();
		FlxG.sound.play(Paths.sound('cancelMenu'));
		if (!isFreePlay)
			MusicBeatState.switchState(new MainMenuState());
		else
			MusicBeatState.switchState(new FreeplayState());
		isFreePlay = false; // 原版在退出分支里复位
		persistentUpdate = false;
		FlxG.autoPause = ClientPrefs.data.autoPause;
	}

	function doRestartNow()
	{
		hideConfirm();
		saveTxt();
		dbg('doRestartNow: waitingToRestart=' + waitingToRestart + ' dirty=' + dirty);
		TitleState.initialized = false;
		TitleState.closedState = false;
		if (FlxG.sound.music != null) FlxG.sound.music.fadeOut(0.3);
		FlxG.camera.fade(FlxColor.BLACK, 0.5, false, FlxG.resetGame, false);
		isFreePlay = false;
	}

	function showConfirm()
	{
		dbg('showConfirm');
		maskSpr.visible = true;
		confirmBg.visible = true;
		confirmTitle.visible = true;
		confirmBody.visible = true;
		confirmYes.setVisible(true);
		confirmStay.setVisible(true);
	}

	function hideConfirm()
	{
		dbg('hideConfirm');
		maskSpr.visible = false;
		confirmBg.visible = false;
		confirmTitle.visible = false;
		confirmBody.visible = false;
		confirmYes.setVisible(false);
		confirmStay.setVisible(false);
	}

	function showToast(msg:String)
	{
		toastTxt.text = msg;
		var w = Std.int(Math.max(120, toastTxt.width + 32));
		toastBg.makeGraphic(w, 32, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(toastBg, 0, 0, w, 32, 16, 16, 0xF208090D);
		toastBg.x = 640 - w / 2;
		toastBg.y = 720 - 60;
		toastTxt.x = toastBg.x;
		toastTxt.y = toastBg.y + 9;
		toastBg.visible = true;
		toastTxt.visible = true;
		toastBg.alpha = 1;
		toastTxt.alpha = 1;
		toastTimer = 1.9;
	}

	function updateEmptyStateVisibility()
	{
		var empty = (modsList.all.length < 1);
		emptyMode = empty;
		// ★ 空状态把常规界面（标签栏 / 底部三按钮 / 右栏详情 / 工具条）整片收起来，
		//   只留空状态卡片 + 顶部窗口条 —— 否则 60% 透明的遮罩下面会透出"一堆多余按钮"，
		//   而且那些按钮点了也没意义（它们都需要先选中某个模组）。
		setNormalUiVisible(!empty);
		for (s in emptyGfx) s.visible = empty;
		if (emptyEgg != null && emptyEgg.text.length < 1) emptyEgg.visible = false;
		emptyTitle.visible = emptyBody.visible = emptyScan.visible = empty;
		emptyFolderBtn.setVisible(empty);
		emptyExitBtn.setVisible(empty);
		layoutEmptyButtons();
	}

	/** 空状态两个按钮：正文下方居中排成一行（原型 #empty .row，间距 10）
	 *  ★ 老代码建完按钮后从没定位过，一直停在 (0,0) 互相重叠 —— 点一下会同时触发两个。 */
	function layoutEmptyButtons()
	{
		if (emptyFolderBtn == null || emptyExitBtn == null) return;
		var gap:Float = 10;
		var total:Float = emptyFolderBtn.w + gap + emptyExitBtn.w;
		var x0:Float = 640 - total / 2;
		emptyFolderBtn.setPos(x0, 470);
		emptyExitBtn.setPos(x0 + emptyFolderBtn.w + gap, 470);
	}

	/** 常规界面（无模组时整体隐藏） */
	function setNormalUiVisible(v:Bool)
	{
		// 结构性元素：空状态收起、有模组时展开
		var arr:Array<FlxSprite> = [listBg, listDiv, tabLine, tabBottom, footTop, detailBg, detailLine, dIcon, dName, dMetaTxt, dDescLabel,
			dDesc, footNote];
		for (s in arr)
			if (s != null) s.visible = v;
		// 这几个的显隐是按内容算的（refreshDetail / refreshList 负责）：只在收起时强制隐藏
		if (!v)
		{
			for (s in [dBadgeBg, dBadgeTxt, restartHint, filterEmptyTxt])
				if (s != null) s.visible = false;
		}
		if (tabOn != null) tabOn.setVisible(v);
		if (tabOff != null) tabOff.setVisible(v);
		if (dToggle != null) dToggle.setVisible(v);
		if (footReload != null) footReload.setVisible(v);
		if (footEnableAll != null) footEnableAll.setVisible(v);
		if (footDisableAll != null) footDisableAll.setVisible(v);
		for (b in tools)
			b.setVisible(v);
	}

	/** 写 modsList.txt（与原版 saveTxt 完全一致） */
	function saveTxt()
	{
		var fileStr:String = '';
		for (mod in modsList.all)
		{
			if (mod.trim().length < 1) continue;
			if (fileStr.length > 0) fileStr += '\n';
			var on = '1';
			if (modsList.disabled.contains(mod)) on = '0';
			fileStr += '$mod|$on';
		}
		File.saveContent('modsList.txt', fileStr);
	}

	// ══════════════════════════════════════════════════════════════════════
	// update
	// ══════════════════════════════════════════════════════════════════════
	override function update(elapsed:Float)
	{
		if (FlxG.width != lastBarW) relayoutBar();

		if (modsList.all.length < 1)
		{
			// 空列表：每秒轮询（原版行为）；同时让提示呼吸
			noModsSine += 180 * elapsed;
			emptyTitle.alpha = 0.55 + 0.45 * (1 - Math.sin((Math.PI * noModsSine) / 180));
			scanTimer -= elapsed;
			if (scanTimer < 0)
			{
				scanTimer = 1;
				@:privateAccess
				Mods.updateModList();
				modsList = Mods.parseList();
				if (modsList.all.length > 0)
				{
					trace('[ModsMenu] mod(s) found -> reloading menu');
					reload();
					return;
				}
			}
		}
		else if (settingsMode)
		{
			// 模组设置视图：输入全部让给设置 UI
			if (setReady)
			{
				settingsMouse(elapsed);
				settingsKeys(elapsed);
				if (tog != null) tog.updateHover();
			}
		}
		else
		{
			handleMouse(elapsed);
			handleKeys(elapsed);
		}

		if (!settingsMode)
		{
			// 列表行：走马灯 + 选中态
			for (r in rows) if (r.anyVisible()) r.updateVisual(elapsed);
			refreshScrollbar();
		}
		else
		{
			hidePressHint(); // 设置视图里工具提示绝不允许残留
			updateSetScrollbar();
		}

		// 自绘控件的悬停/点击（统一走 viewX/viewY 判定）
		for (b in allButtons) b.updateHover();
		if (!settingsMode)
		{
			if (tabOn != null) tabOn.updateHover();
			if (tabOff != null) tabOff.updateHover();
			for (i in 0...tools.length)
			{
				tools[i].setFocus(zone == 1 && i == toolSel); // 工具条焦点指示（键盘/手柄用）
				tools[i].updateHover();
			}
			if (dToggle != null) dToggle.updateHover();

			// 悬停工具按钮 → 提示栏显示它的名字
			if (modsList.all.length > 0)
			{
				var tip:String = '';
				for (i in 0...tools.length)
				{
					if (tools[i].hovered)
					{
						tip = Language.get(tools[i].labelKey, 'mods');
						break;
					}
				}
				if (tip.length > 0) showToolTip(tip);
				else if (pressIdx < 0) hidePressHint();
			}
		}

		// toast 淡出
		if (toastTimer > 0)
		{
			toastTimer -= elapsed;
			if (toastTimer < 0.4)
			{
				var a = Math.max(0, toastTimer / 0.4);
				toastBg.alpha = a;
				toastTxt.alpha = a;
			}
			if (toastTimer <= 0)
			{
				toastBg.visible = false;
				toastTxt.visible = false;
			}
		}

		// 鼠标一动就退出控制器模式（原版行为）
		// ★ 桌面端不再用 needMobileControl 卡住光标：本界面本来就是鼠标/触摸驱动的，
		//   而引擎默认把光标藏起来（needMobileControl 默认 true），否则桌面上连悬停高亮都没有。
		var mouseMoved:Bool = (FlxG.mouse != null) && (Math.abs(FlxG.mouse.deltaX) > 4 || Math.abs(FlxG.mouse.deltaY) > 4);
		if (mouseMoved) controls.controllerMode = false;
		#if !mobile
		if (mouseMoved && FlxG.mouse != null && !FlxG.mouse.visible) FlxG.mouse.visible = true;
		#end

		super.update(elapsed);
	}

	// ── 鼠标 ──
	function handleMouse(elapsed:Float)
	{
		// ★ 统一走指针层：手机用触点、桌面用鼠标，且不再要求 mouse.visible
		var mx:Float = ModsMenuState.pointerX();
		var my:Float = ModsMenuState.pointerY();
		var wheel:Int = ModsMenuState.pointerWheel();
		var justPressed:Bool = ModsMenuState.pointerJustPressed();
		var pressedNow:Bool = ModsMenuState.pointerPressed();
		var justReleased:Bool = ModsMenuState.pointerJustReleased();

		if (wheel != 0)
			dbg('wheel=' + wheel + ' at(' + Std.int(mx) + ',' + Std.int(my) + ') overList=' + (mx < LEFT_W && my >= LIST_TOP && my < LIST_TOP + LIST_H));
		if (justPressed)
			dbg('press at(' + Std.int(mx) + ',' + Std.int(my) + ') listHit=' + (mx < LEFT_W && my >= LIST_TOP && my < LIST_TOP + LIST_H ? rowAtScreen(my) : -1));

		// 滚轮：列表 / 描述区（移动端没有滚轮，wheel 恒为 0）
		if (wheel != 0)
		{
			if (mx < LEFT_W && my >= LIST_TOP && my < LIST_TOP + LIST_H)
			{
				scrollY -= wheel * 34;
				scrollY = Math.max(0, Math.min(scrollY, Math.max(0, listContentHeight() - LIST_H)));
				listCam.scroll.y = scrollY;
			}
			else if (mx >= RIGHT_X && my > BAR_H + 170 && my < 720 - 50 && descMaxScroll > 0)
			{
				descScrollY -= wheel * 40;
				applyDescScroll();
			}
		}

		// 搜索框：点框内聚焦、点外面失焦
		if (justPressed)
		{
			var insideSearch = (mx >= searchBg.x - 6 && mx <= searchBg.x + 196 + 6 && my >= 2 && my <= 34);
			if (insideSearch) PsychUIInputText.focusOn = searchBox;
			else if (PsychUIInputText.focusOn == searchBox) PsychUIInputText.focusOn = null;
		}

		// ── 列表行：按下 → 1 秒长按 → 拖拽；不足 1 秒松开 = 选中；先移动 = 滚动列表 ──
		// ── 列表行：按下 → 1 秒长按 → 拖拽排序；不足 1 秒先移动 = 拖动列表滚动 ──
		var overSb = (sbThumb != null && sbThumb.visible && mx >= sbTrack.x - 6);
		var inList = (!overSb && mx < LEFT_W && my >= LIST_TOP && my < LIST_TOP + LIST_H);
		var hit = inList ? rowAtScreen(my) : -1;

		if (justPressed && hit >= 0)
		{
			pressIdx = hit;
			pressTimer = 0;
			pressMoved = false;
			dragging = false;
			scrollDrag = false;
			dragSlot = -1;
			dragOffsetY = 0;
			pressMouseX = mx;
			pressMouseY = my;
			scrollDragBase = scrollY;
			scrollDragMouseY = my;
		}

		if (pressIdx >= 0 && pressedNow)
		{
			var dx = Math.abs(mx - pressMouseX);
			var dy = Math.abs(my - pressMouseY);

			// ① 不到 1 秒就先移动 = 拖动列表滚动（并彻底取消长按）
			if (!dragging && !scrollDrag && (dx > SCROLL_TOL || dy > SCROLL_TOL))
			{
				scrollDrag = true;
				pressMoved = true;
				if (pressIdx < rows.length) rows[pressIdx].setHoldProgress(0);
				hidePressHint();
				dbg('scrollDrag start row=#' + pad2(pressIdx + 1) + ' d=(' + Std.int(dx) + ',' + Std.int(dy) + ') scrollY=' + Std.int(scrollY));
			}
			// ② 按住不动满 1 秒 = 进入排序拖拽
			else if (!dragging && !scrollDrag && pressTimer < LONG_PRESS)
			{
				pressTimer += elapsed;
				if (pressTimer >= LONG_PRESS)
				{
					dragging = true;
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
					if (pressIdx < rows.length) rows[pressIdx].setHoldProgress(0);
					dbg('longPress OK row=#' + pad2(pressIdx + 1) + ' ' + rows[pressIdx].folder);
				}
				else if (pressIdx < rows.length)
				{
					rows[pressIdx].setHoldProgress(pressTimer / LONG_PRESS);
					if (pressTimer > 0.22) showPressHint(mx, my, true);
				}
			}

			if (scrollDrag)
			{
				// 跟手滚动：光标往上 = 列表往下
				scrollY = scrollDragBase - (my - scrollDragMouseY);
				scrollY = Math.max(0, Math.min(scrollY, Math.max(0, listContentHeight() - LIST_H)));
				listCam.scroll.y = scrollY;
				refreshScrollbar();
			}
			else if (dragging)
			{
				if (my < LIST_TOP + 24) scrollY -= 7;
				else if (my > LIST_TOP + LIST_H - 24) scrollY += 7;
				scrollY = Math.max(0, Math.min(scrollY, Math.max(0, listContentHeight() - LIST_H)));
				listCam.scroll.y = scrollY;
				refreshScrollbar();

				var vis0 = visibleIndices();
				if (pressIdx < rows.length && vis0.indexOf(pressIdx) >= 0)
				{
					// 被拖行跟手（限制在列表可视区内，不会跑到面板外面）
					var base = vis0.indexOf(pressIdx) * ROW_H;
					var want = my - pressMouseY;
					want = Math.max(-base, Math.min(want, LIST_H - ROW_H - base));
					rows[pressIdx].setDragOffset(want);
				}

				dragSlot = dropSlotAt(my);
				var vis = visibleIndices();
				if (vis.length > 0)
				{
					var slot = Std.int(Math.max(0, Math.min(vis.length, dragSlot)));
					dropLine.y = slot * ROW_H - 1;
					dropLine.visible = true;
				}
				showPressHint(mx, my, false);
			}
		}

		if (justReleased && pressIdx >= 0)
		{
			dropLine.visible = false;
			hidePressHint();
			if (pressIdx < rows.length) rows[pressIdx].setHoldProgress(0);
			if (dragging)
			{
				var vis = visibleIndices();
				var from = pressIdx;
				var target = from;
				if (vis.length > 0)
				{
					var slot = Std.int(Math.max(0, Math.min(vis.length, dragSlot)));
					target = (slot >= vis.length) ? vis[vis.length - 1] : vis[slot];
					if (target > from) target -= 1; // 前插后行会前移一位（moveOrder 内部先删后插）
					if (target < 0) target = 0;
				}
				if (pressIdx < rows.length) rows[pressIdx].setDragOffset(0);
				if (target != from) moveOrder(from, target);
			}
			else if (!pressMoved)
			{
				selectMod(pressIdx);
			}
			if (scrollDrag) dbg('scrollDrag end scrollY=' + Std.int(scrollY));
			pressIdx = -1;
			dragging = false;
			scrollDrag = false;
			pressMoved = false;
		}

		// 滚动条：拖动滑块 / 点轨道跳转
		if (sbThumb != null && sbThumb.visible)
		{
			var trackTop = sbTrack.y;
			var trackH = sbTrack.height;
			var maxScroll = Math.max(1, listContentHeight() - LIST_H);
			var overThumb = (mx >= sbThumb.x - 4 && mx <= sbThumb.x + SB_W + 4 && my >= sbThumb.y && my <= sbThumb.y + sbThumbH);
			if (justPressed && overThumb)
			{
				sbDrag = true;
				sbDragOfs = my - sbThumb.y;
				dbg('sbDrag start y=' + Std.int(my) + ' thumbY=' + Std.int(sbThumb.y) + ' thumbH=' + Std.int(sbThumbH));
			}
			else if (justPressed && mx >= sbTrack.x - 6 && mx <= sbTrack.x + SB_W + 6 && my >= trackTop && my <= trackTop + trackH)
			{
				scrollY = ((my - trackTop - sbThumbH / 2) / Math.max(1, trackH - sbThumbH)) * maxScroll;
				scrollY = Math.max(0, Math.min(scrollY, maxScroll));
				listCam.scroll.y = scrollY;
				refreshScrollbar();
				dbg('sbJump y=' + Std.int(my) + ' -> scrollY=' + Std.int(scrollY));
			}
			if (sbDrag)
			{
				if (!pressedNow)
				{
					sbDrag = false;
					dbg('sbDrag end scrollY=' + Std.int(scrollY));
				}
				else
				{
					var frac = (my - sbDragOfs - trackTop) / Math.max(1, trackH - sbThumbH);
					scrollY = Math.max(0, Math.min(1, frac)) * maxScroll;
					listCam.scroll.y = scrollY;
					refreshScrollbar();
				}
			}
		}

		// 描述区：按住拖动滚动
		if (descDragging)
		{
			if (!pressedNow) descDragging = false;
			else
			{
				descScrollY += (descDragY - my);
				descDragY = my;
				applyDescScroll();
			}
		}
		else if (justPressed && mx >= RIGHT_X + 20 && my > BAR_H + 170 && my < 720 - 50 && descMaxScroll > 0)
		{
			descDragging = true;
			descDragY = my;
		}
	}

	function rowAtScreen(sy:Float):Int
	{
		var vis = visibleIndices();
		if (vis.length < 1) return -1;
		var local = sy - LIST_TOP + scrollY;
		var k = Std.int(local / ROW_H);
		if (k < 0 || k >= vis.length) return -1;
		return vis[k];
	}

	/** 返回插入槽位（0..可见行数） */
	function dropSlotAt(sy:Float):Int
	{
		var vis = visibleIndices();
		var local = sy - LIST_TOP + scrollY;
		var k = Std.int(local / ROW_H);
		if (local - k * ROW_H > ROW_H / 2) k++;
		return Std.int(Math.max(0, Math.min(vis.length, k)));
	}

	// ── 键盘（原版 controls 语义）──
	function handleKeys(elapsed:Float)
	{
		if (controls.ACCEPT || controls.BACK || controls.UI_UP_P || controls.UI_DOWN_P || controls.UI_LEFT_P || controls.UI_RIGHT_P)
			dbg('key ACCEPT=' + controls.ACCEPT + ' BACK=' + controls.BACK + ' U=' + controls.UI_UP_P + ' D=' + controls.UI_DOWN_P + ' L=' + controls.UI_LEFT_P + ' R=' + controls.UI_RIGHT_P);
		// 搜索框聚焦时把按键让给输入框（Esc 除外）
		if (PsychUIInputText.focusOn != null && !controls.BACK) return;

		if (maskSpr.visible)
		{
			if (controls.ACCEPT) doRestartNow();
			else if (controls.BACK) hideConfirm();
			return;
		}

		if (controls.BACK)
		{
			if (searchBox != null && PsychUIInputText.focusOn == searchBox) PsychUIInputText.focusOn = null;
			else if (zone == 1) zone = 0; // 工具条区按 BACK 只回列表（原版行为）
			else exitMenu();
			return;
		}

		if (controls.UI_DOWN_P || controls.UI_UP_P)
		{
			var down = controls.UI_DOWN_P;
			if (zone == 0) selectStep(Std.int((FlxG.keys.pressed.SHIFT ? 5 : 1) * (down ? 1 : -1)));
			else
			{
				var t = toolSel + (down ? 1 : -1);
				if (t < 0 || t >= tools.length) zone = 0;
				else toolSel = t;
			}
		}
		else if (controls.UI_LEFT_P || controls.UI_RIGHT_P)
		{
			if (zone == 0)
			{
				zone = 1;
				toolSel = 0;
			}
			else
			{
				var t = toolSel + (controls.UI_RIGHT_P ? 1 : -1);
				if (t < 0 || t >= tools.length) zone = 0;
				else toolSel = t;
			}
		}
		else if (controls.ACCEPT)
		{
			if (zone == 1) toolAction(toolSel);
		}
		else if (FlxG.keys.justPressed.TAB)
		{
			// Tab 键在【已启用】/【已禁用】之间切换（鼠标点标签的键盘等价物）
			setFilter(filter == 0 ? 1 : 0);
		}
		else if (FlxG.keys.justPressed.SPACE)
		{
			toggleMod(sel);
		}
		else if (FlxG.keys.justPressed.HOME)
		{
			var vis = visibleIndices();
			if (vis.length > 0) selectMod(vis[0]);
			scrollY = 0;
			listCam.scroll.y = 0;
		}
		else if (FlxG.keys.justPressed.END)
		{
			var vis = visibleIndices();
			if (vis.length > 0) selectMod(vis[vis.length - 1]);
			scrollY = Math.max(0, listContentHeight() - LIST_H);
			listCam.scroll.y = scrollY;
		}
		else if (FlxG.keys.pressed.SHIFT && (controls.UI_UP || controls.UI_DOWN))
		{
			holdTime += elapsed;
			if (holdTime > 0.5)
			{
				holdTime = 0;
				moveOrder(sel, controls.UI_UP ? sel - 1 : sel + 1);
			}
		}
		if (controls.UI_DOWN_R || controls.UI_UP_R) holdTime = 0;
	}

	override function destroy()
	{
		FlxG.autoPause = ClientPrefs.data.autoPause;
		super.destroy();
	}

	// ══════════════════════════════════════════════════════════════════════
	// 小工具
	// ══════════════════════════════════════════════════════════════════════
	public static inline function pad2(v:Int):String
	{
		return (v < 10) ? '0' + v : '' + v;
	}

	// 文字超采样倍率：字号与 fieldWidth 同乘 1.5 光栅化，精灵整体缩回 1/1.5
	// （参照编辑器 hi-res"1920 光栅再等比缩小"的思路，但只作用于单个文字精灵，
	//  不碰 frame.sourceSize/tileMatrix —— 那条路（FlxText.renderScale）实测有重影 bug）
	public static inline var TXT_SS:Float = 1.5;

	/**
	 * 代替 setFormat：光栅 1.5 倍再由精灵缩回，视觉布局完全不变、文字清晰。
	 * ★ 会把 fieldWidth(>0) 也乘 TXT_SS —— 因此只允许对每个文字调用一次；
	 *   fieldWidth=0（自适应宽）的文字重复调用是安全的（dName 缩字号那两处）。
	 */
	public static function fmtSharp(t:FlxText, size:Int, color:FlxColor, ?align:FlxTextAlign = null):FlxText
	{
		FlxText.uiSizeScale = TXT_SS; // 让 set_size 内部按 1.5x 光栅
		t.setFormat(Paths.font(Language.get('fontName', 'main') + '.ttf'), size, color, align);
		FlxText.uiSizeScale = 1.0;
		// ★ 只有"固定宽"文字才乘倍率。autoSize（fieldWidth=0）的文字千万不能碰：
		//   它的 fieldWidth getter 返回实测内容宽，一乘倍率就会把自适应锁死成小固定宽，
		//   之后一换长文本就逐字竖排（dName/footNote 竖排血案）。
		if (!t.autoSize && t.fieldWidth > 0) t.fieldWidth = Std.int(t.fieldWidth * TXT_SS);
		t.scale.set(1 / TXT_SS, 1 / TXT_SS);
		t.origin.set(0, 0); // ★ 缩放锚点回到左上角（默认中心锚会把文字推偏）
		t.offset.set(0, 0);
		return t;
	}

	/**
	 * 把超采样文字的光栅位图取出来（1.5x 分辨率，不做降采样）。
	 * 用途：凡是要裁剪/滚动的文字（走马灯/描述区），CPU blit 在 1.5x 位图上摘窗口，
	 * 显示精灵以 scale=1/TXT_SS 缩回 —— GPU 采样 1:1 物理像素，保持锐利。
	 */
	public static function rasterizeBitmap(t:FlxText):BitmapData
	{
		var w:Int = Std.int(Math.max(1, t.width)); // 先读宽高强制 regen（get_pixels 不触发 regen！）
		var h:Int = Std.int(Math.max(1, t.height));
		return t.pixels;
	}

	/** 把 content 的可见段摘进固定窗口位图（走马灯/描述滚动 = 纯 CPU blit，零渲染歧义） */
	public static function blitWindow(bd:BitmapData, content:BitmapData, sx:Int, winW:Int, winH:Int):Void
	{
		bd.fillRect(bd.rect, 0);
		if (content == null || sx < 0 || sx >= content.width) return;
		var w:Int = Std.int(Math.min(winW, content.width - sx));
		var h:Int = Std.int(Math.min(winH, content.height));
		if (w <= 0 || h <= 0) return;
		scratchRect.setTo(sx, 0, w, h);
		scratchPoint.setTo(0, 0);
		bd.copyPixels(content, scratchRect, scratchPoint);
	}

	/** 无缝循环版：uv 窗口越过内容尾部时从头部续接（内容位图尾部已留 48px 间隔） */
	public static function blitWindowLoop(bd:BitmapData, content:BitmapData, sx:Int, winW:Int, winH:Int):Void
	{
		bd.fillRect(bd.rect, 0);
		if (content == null || content.width <= 0) return;
		var loopW:Int = content.width;
		sx = ((sx % loopW) + loopW) % loopW;
		var h:Int = Std.int(Math.min(winH, content.height));
		if (h <= 0) return;
		var dstX:Int = 0;
		var remaining:Int = winW;
		while (remaining > 0)
		{
			var w:Int = Std.int(Math.min(remaining, loopW - sx));
			scratchRect.setTo(sx, 0, w, h);
			scratchPoint.setTo(dstX, 0);
			bd.copyPixels(content, scratchRect, scratchPoint);
			dstX += w;
			remaining -= w;
			sx = 0;
		}
	}

	/** 内容位图尾部补 48px 透明间隔（循环衔接处的视觉分隔） */
	public static function padMarqueeBitmap(src:BitmapData):BitmapData
	{
		var bd:BitmapData = new BitmapData(src.width + Std.int(MARQ_GAP * TXT_SS), src.height, true, 0);
		scratchPoint.setTo(0, 0);
		bd.copyPixels(src, src.rect, scratchPoint);
		return bd;
	}

	/** 给已 fmtSharp 的文字设置"逻辑"fieldWidth（内部自动乘倍率） */
	public static function sharpFieldW(t:FlxText, logicalW:Float):Void
	{
		t.fieldWidth = Std.int(logicalW * TXT_SS);
	}

	public static function fmt(s:String, key:String, value:String):String
	{
		return s.split('{' + key + '}').join(value);
	}

	public static function hex6(c:FlxColor):String
	{
		var digits = '0123456789ABCDEF';
		var r = (c >> 16) & 0xFF;
		var g = (c >> 8) & 0xFF;
		var b = c & 0xFF;
		return '#' + digits.charAt(r >> 4) + digits.charAt(r & 0xF)
			+ digits.charAt(g >> 4) + digits.charAt(g & 0xF)
			+ digits.charAt(b >> 4) + digits.charAt(b & 0xF);
	}
}

// ══════════════════════════════════════════════════════════════════════
// 列表行：pack 图标 | 名称 / 文件夹名（长名字走马灯）
// ══════════════════════════════════════════════════════════════════════
class ModRow
{
	public var folder:String;
	public var name:String = 'Unknown Mod';
	public var desc:String = 'No description provided.';
	public var mustRestart:Bool = false;
	public var runsGlobally:Bool = false;
	public var hasSettings:Bool = false;
	public var settings:Array<Dynamic> = null;
	public var iconFps:Int = 10;
	public var frames:Int = 0;
	public var bgColor:FlxColor = 0xFF665AFF;
	public var iconGraphic:FlxGraphic = null;
	public var iconAA:Bool = true;
	public var index:Int = 0;

	var rowW:Float;
	var bg:FlxSprite;
	var bar:FlxSprite;
	var icon:FlxSprite;
	// 名称/文件夹：固定窗口位图精灵 + 完整内容位图（走马灯 = CPU blit，零渲染歧义）
	var nameTxt:FlxSprite;
	var folderTxt:FlxSprite;
	var nameContent:BitmapData;
	var folderContent:BitmapData;
	var badgeTxt:FlxText;

	var nameLoopW:Float = 0; // 循环周长 = 内容位图宽（含尾部间隔）；0 = 不滚动
	var folderLoopW:Float = 0;
	var nameTime:Float = 0;
	var folderTime:Float = 0;
	var colW:Float = 0;
	var nameBaseX:Float = 64;
	var folderBaseX:Float = 64;
	var nameOne:String = '';
	var folderOne:String = '';
	var holdProg:Float = 0;
	var holdSpr:FlxSprite;
	var dragOfs:Float = 0;
	var rowY:Float = 0;
	var sprites:Array<FlxSprite> = [];

	public function new(folder:String, rowW:Float)
	{
		this.folder = folder;
		this.rowW = rowW;

		// ── pack.json（与原版 ModItem 一致的读取顺序与兜底）──
		var pack:Dynamic = Mods.getPack(folder);

		// data/settings.json（与原版一致，TJSON）
		var setPath:String = Paths.mods('$folder/data/settings.json');
		if (FileSystem.exists(setPath))
		{
			try
			{
				settings = tjson.TJSON.parse(File.getContent(setPath));
			}
			catch (e:Dynamic)
			{
				trace('Mod settings parse failed: $folder - $e');
			}
		}
		hasSettings = (settings != null && settings.length > 0);

		// ★ pack 图标显示逻辑：pack.png → pack-pixel.png（关抗锯齿）→ unknownMod.png
		var isPixel = false;
		var bmp = Paths.cacheBitmap(Paths.mods('$folder/pack.png'));
		if (bmp == null)
		{
			bmp = Paths.cacheBitmap(Paths.mods('$folder/pack-pixel.png'));
			isPixel = true;
		}
		if (bmp != null)
		{
			iconGraphic = bmp;
			iconAA = !isPixel;
			frames = Std.int(Math.floor(bmp.width / 150) * Math.floor(bmp.height / 150));
		}
		else
		{
			iconGraphic = Paths.image('unknownMod');
			iconAA = true;
			frames = 1;
		}

		this.name = folder;
		if (pack != null)
		{
			if (pack.name != null) this.name = Std.string(pack.name);
			if (pack.description != null) this.desc = Std.string(pack.description);
			if (pack.iconFramerate != null) this.iconFps = Std.int(pack.iconFramerate);
			if (pack.restart == true) this.mustRestart = true;
			if (pack.runsGlobally == true) this.runsGlobally = true;
			if (pack.color != null)
			{
				this.bgColor = FlxColor.fromRGB(pack.color[0] != null ? pack.color[0] : 170, pack.color[1] != null ? pack.color[1] : 0,
					pack.color[2] != null ? pack.color[2] : 255);
			}
		}

		// ── 精灵 ──
		bg = new FlxSprite(0, 0).makeGraphic(Std.int(rowW), ModsMenuState.ROW_H, 0xFFFFFFFF);
		bg.alpha = ModsMenuState.ROW_BG_A;

		icon = new FlxSprite(12, 8);
		if (iconGraphic != null) icon.loadGraphic(iconGraphic, true, 150, 150);
		icon.antialiasing = iconAA && ClientPrefs.data.antialiasing;
		icon.scale.set(40 / 150, 40 / 150);
		icon.updateHitbox();
		if (frames > 1)
		{
			icon.animation.add('icon', [for (i in 0...frames) i], iconFps);
			icon.animation.play('icon');
		}

		// 文字列宽：原型里名字块是 flex:1（占满图标与徽章之外的全部宽度）。
		// 有徽章的行给右侧徽章区（rowW-160 起、右对齐）留 8px 空隙；没有徽章的行把整行都给文字。
		var badgeZone:Float = (runsGlobally || mustRestart || hasSettings) ? 168 : 22;
		colW = rowW - 64 - badgeZone;
		nameBaseX = 64;
		folderBaseX = 64;
		nameOne = this.name;
		folderOne = folder;
		// 先用 SharpText 光栅化（1.5x），再降采样成 1:1 位图精灵：
		// 走马灯的 clipRect 数学回到久经考验的原版语义，文字清晰度不变
		var nameGen = new SharpText(0, 0, 0, this.name, 13);
		ModsMenuState.fmtSharp(nameGen, 13, ModsMenuState.C_TEXT);
		nameContent = ModsMenuState.padMarqueeBitmap(ModsMenuState.rasterizeBitmap(nameGen));
		// 窗口位图也是 1.5x：CPU blit 无重采样，精灵 2/3 缩回 → GPU 采样 1:1 物理像素
		// ★ 高度 = 内容光栅全高（写死 18*1.5=27 会裁掉字形下半 → "文字只显示一半"）
		nameTxt = new FlxSprite(nameBaseX, 11).makeGraphic(Std.int(colW * ModsMenuState.TXT_SS), nameContent.height, FlxColor.TRANSPARENT, true);
		nameTxt.scale.set(1 / ModsMenuState.TXT_SS, 1 / ModsMenuState.TXT_SS);
		nameTxt.origin.set(0, 0);
		nameTxt.offset.set(0, 0);
		nameGen.destroy();

		var folderGen = new SharpText(0, 0, 0, folder, 11);
		ModsMenuState.fmtSharp(folderGen, 11, ModsMenuState.C_HINT);
		folderContent = ModsMenuState.padMarqueeBitmap(ModsMenuState.rasterizeBitmap(folderGen));
		folderTxt = new FlxSprite(folderBaseX, 32).makeGraphic(Std.int(colW * ModsMenuState.TXT_SS), folderContent.height, FlxColor.TRANSPARENT, true);
		folderTxt.scale.set(1 / ModsMenuState.TXT_SS, 1 / ModsMenuState.TXT_SS);
		folderTxt.origin.set(0, 0);
		folderTxt.offset.set(0, 0);
		folderGen.destroy();
		refreshMarqueeViews();

		badgeTxt = new SharpText(rowW - 160, 20, 148, '', 10);
		ModsMenuState.fmtSharp(badgeTxt, 10, ModsMenuState.C_DIM, RIGHT);

		bar = new FlxSprite(rowW - 3, 10).makeGraphic(3, ModsMenuState.ROW_H - 20, ModsMenuState.C_DANGER, true);

		// 长按进度条：按住时从行左侧长出来（2px 强调线）
		holdSpr = new FlxSprite(0, ModsMenuState.ROW_H - 2).makeGraphic(1, 2, ModsMenuState.C_ACCENT, true);
		holdSpr.origin.set(0, 0); // ★ 归零 origin，否则 scale.x 会绕中心把进度条推到左边去
		holdSpr.visible = false;

		buildMarquee(nameContent, nameTxt, true);
		buildMarquee(folderContent, folderTxt, false);

		sprites = [bg, bar, icon, nameTxt, folderTxt, badgeTxt, holdSpr];
		setEnabledFlag(true);
	}

	/**
	 * 走马灯（无缝循环版）：内容位图尾部带 48px 透明间隔，恒速左移、越尾从头续接。
	 * 单位约定：content / 窗口位图全部是光栅分辨率（×TXT_SS），colW / textW 是逻辑值；
	 * blit 的 sx/winW/winH 一律光栅单位，速度乘 TXT_SS 抵消倍率。
	 */
	function buildMarquee(content:BitmapData, spr:FlxSprite, isName:Bool)
	{
		// ★ 单位铁律：content.width 是光栅（×TXT_SS），colW 是逻辑。
		//   判定"放不放得下"必须先换算回逻辑，否则比实际宽 1.5 倍 →
		//   大量放得下的名字被误判成放不下、强制走马灯。
		var textW:Float = (content.width - ModsMenuState.MARQ_GAP * ModsMenuState.TXT_SS) / ModsMenuState.TXT_SS;

		if (!ModsMenuState.marqueeEnabled || textW <= colW)
		{
			// 放得下（或关了走马灯）：窗口里铺左端即可，不滚动
			if (isName) nameLoopW = 0; else folderLoopW = 0;
			ModsMenuState.blitWindow(spr.pixels, content, 0, Std.int(colW * ModsMenuState.TXT_SS), content.height);
			return;
		}

		var loopW:Float = content.width; // 无缝循环周长（光栅单位）
		if (isName)
		{
			nameLoopW = loopW;
			nameTime = 0;
		}
		else
		{
			folderLoopW = loopW;
			folderTime = 0;
		}
		ModsMenuState.blitWindowLoop(spr.pixels, content, 0, Std.int(colW * ModsMenuState.TXT_SS), content.height);
		ModsMenuState.dbg('marquee[' + folder + '] ' + (isName ? 'name' : 'folder') + ' textW=' + Std.int(textW)
			+ ' colW=' + Std.int(colW) + ' loopW=' + Std.int(loopW) + ' -> 无缝循环');
	}

	/** 把内容位图的左端铺进两个窗口（构造后/走马灯未激活时） */
	public function refreshMarqueeViews()
	{
		ModsMenuState.blitWindow(nameTxt.pixels, nameContent, 0, Std.int(colW * ModsMenuState.TXT_SS), nameContent.height);
		ModsMenuState.blitWindow(folderTxt.pixels, folderContent, 0, Std.int(colW * ModsMenuState.TXT_SS), folderContent.height);
	}

	/** 被拖拽时整行跟手（dy = 光标相对按下点的位移） */
	public function setDragOffset(dy:Float)
	{
		dragOfs = dy;
		applyY();
	}

	/** 长按进度 0..1（按住时行底部从左往右长的强调线） */
	public function setHoldProgress(p:Float)
	{
		holdProg = p;
		if (p <= 0)
		{
			holdSpr.visible = false;
			return;
		}
		holdSpr.visible = bg.visible;
		holdSpr.y = rowY + ModsMenuState.ROW_H - 2;
		// 底图是 1x2 → 直接用 scale.x 当宽度（不做 updateHitbox，否则会把缩放烘进尺寸）
		holdSpr.scale.x = Math.max(0.001, rowW * Math.min(1, p));
	}

	function applyY()
	{
		var y = rowY + dragOfs;
		bg.y = y;
		bar.y = y + 10;
		icon.y = y + 8;
		nameTxt.y = y + 11;
		folderTxt.y = y + 32;
		badgeTxt.y = y + 20;
		if (holdSpr.visible) holdSpr.y = y + ModsMenuState.ROW_H - 2;
	}

	public function addTo(state:FlxState, cam:FlxCamera)
	{
		for (s in sprites)
		{
			s.cameras = [cam];
			// ★ 不要 scrollFactor.set()：列表行必须跟随 listCam.scroll 才会真的滚动
			//   （scrollFactor(0,0) = 忽略相机滚动，列表看起来就是"冻住"的）
			state.add(s);
		}
	}

	public inline function anyVisible():Bool
	{
		return bg.visible;
	}

	public function setVisible(v:Bool)
	{
		for (s in sprites) s.visible = v;
		if (holdSpr != null) holdSpr.visible = v && holdProg > 0;
		if (!v) return;
		bar.visible = !enabled;
		badgeTxt.visible = (badgeTxt.text.length > 0);
	}

	public var enabled:Bool = true;

	public function setY(y:Float)
	{
		rowY = y;
		applyY();
	}

	public function setSelected(v:Bool)
	{
		// ★ 必须改 alpha 而不是 color：底图是 0x08FFFFFF（位图自带 alpha 0x08），
		//   而 FlxSprite.color 只乘 RGB、改不了位图 alpha —— 老写法选中态根本看不出来。
		bg.color = FlxColor.WHITE;
		bg.alpha = v ? ModsMenuState.ROW_SEL_A : ModsMenuState.ROW_BG_A;
	}

	/** 启用/禁用态的全部视觉（原版：图标染红 + 名称变灰；新版另加右侧红条与徽章） */
	public function setEnabledFlag(v:Bool)
	{
		enabled = v;
		nameTxt.color = v ? ModsMenuState.C_TEXT : 0xFF8A8F9E;
		folderTxt.color = v ? ModsMenuState.C_HINT : 0xFF6A6E7C;
		icon.color = v ? FlxColor.WHITE : 0xFFFF6666;
		bar.visible = bg.visible && !v;
		var b = '';
		if (runsGlobally) b += Language.get('badgeGlobal', 'mods') + '  ';
		if (mustRestart) b += Language.get('badgeRestart', 'mods') + '  ';
		if (hasSettings) b += Language.get('badgeSettings', 'mods');
		badgeTxt.text = b;
		badgeTxt.visible = bg.visible && b.length > 0;
	}

	/** 每帧：走马灯相位（单向；到尾停一下瞬间回到起点，中途永远是连续文字） */
	public function updateVisual(elapsed:Float)
	{
		if (nameLoopW > 0)
		{
			nameTime += elapsed;
			// 全程光栅单位：x 与 loopW 同单位；速度 ×TXT_SS 抵消光栅倍率（视觉仍 = MARQ_SPEED 逻辑px/s）
			var x:Int = Std.int((nameTime * ModsMenuState.MARQ_SPEED * ModsMenuState.TXT_SS) % nameLoopW);
			ModsMenuState.blitWindowLoop(nameTxt.pixels, nameContent, x, Std.int(colW * ModsMenuState.TXT_SS), nameContent.height);
		}
		if (folderLoopW > 0)
		{
			folderTime += elapsed;
			var x2:Int = Std.int((folderTime * ModsMenuState.MARQ_SPEED * ModsMenuState.TXT_SS) % folderLoopW);
			ModsMenuState.blitWindowLoop(folderTxt.pixels, folderContent, x2, Std.int(colW * ModsMenuState.TXT_SS), folderContent.height);
		}
	}
}

// ══════════════════════════════════════════════════════════════════════
// 窗口条图标按钮（使用原版 modsMenuButtons.png 的帧）
// ══════════════════════════════════════════════════════════════════════
class BarButton
{
	public var labelKey:String;
	public var hovered:Bool = false;
	public var x:Float;
	public var y:Float;
	var bg:FlxSprite;
	var icon:FlxSprite;
	var onClick:Void->Void;

	public function new(x:Float, y:Float, frame:Int, labelKey:String, onClick:Void->Void)
	{
		this.x = x;
		this.y = y;
		this.labelKey = labelKey;
		this.onClick = onClick;

		bg = FlxSpriteUtil.drawRoundRect(new FlxSprite(x, y).makeGraphic(26, 26, FlxColor.TRANSPARENT), 0, 0, 26, 26, 7, 7, 0xFFFFFFFF);
		bg.alpha = 0;

		icon = new FlxSprite(x + 2, y + 2);
		var img = Paths.image('modsMenuButtons');
		if (img != null)
		{
			icon.loadGraphic(img, true, 54, 54);
			icon.animation.add('icon', [frame]);
			icon.animation.play('icon');
			icon.scale.set(22 / 54, 22 / 54);
			icon.updateHitbox();
		}
		else
		{
			icon.makeGraphic(22, 22, ModsMenuState.C_DIM);
		}
		icon.color = ModsMenuState.C_DIM;
	}

	public function addTo(state:FlxState, cam:FlxCamera)
	{
		for (s in [bg, icon])
		{
			s.cameras = [cam];
			s.scrollFactor.set();
			state.add(s);
		}
	}

	/** 顶栏重排用：整体挪到新位置（提示文案与按钮组互换后按钮组靠右） */
	public function setPosXY(nx:Float, ny:Float)
	{
		x = nx;
		y = ny;
		bg.x = nx;
		bg.y = ny;
		icon.x = nx + 2;
		icon.y = ny + 2;
	}

	/** 工具条区域焦点（键盘/手柄选中）*/
	public function setFocus(v:Bool):Void
	{
		if (v == focused) return;
		focused = v;
		bg.alpha = v ? 0.26 : (hovered ? 0.16 : 0);
		icon.color = (v || hovered) ? FlxColor.WHITE : ModsMenuState.C_DIM;
	}

	/** 无模组时整条工具条一起隐藏 */
	public function setVisible(v:Bool):Void
	{
		bg.visible = v;
		icon.visible = v;
	}

	public var focused:Bool = false;

	public function updateHover()
	{
		if (!bg.visible) return; // 空状态工具条整条隐藏时不许再响应点击
		var over = ModsMenuState.pointerOver(x, y, 26, 26);
		if (over != hovered)
		{
			hovered = over;
			bg.alpha = over ? 0.16 : 0;
			icon.color = over ? FlxColor.WHITE : ModsMenuState.C_DIM;
		}
		if (hovered && ModsMenuState.pointerJustPressed())
		{
			ModsMenuState.dbg('  -> click [tool:' + labelKey + '] at(' + Std.int(ModsMenuState.pointerX()) + ',' + Std.int(ModsMenuState.pointerY()) + ')');
			onClick();
		}
	}
}

// ══════════════════════════════════════════════════════════════════════
// 左栏顶部标签按钮（原型 .tab：圆点 + 文字 + 数字胶囊 + 扁平选中填充）
// ══════════════════════════════════════════════════════════════════════
class TabButton
{
	public var x:Float;
	public var y:Float;
	public var w:Int;
	public var h:Int;
	public var hovered:Bool = false;
	public var dbgName:String = '';

	var bg:FlxSprite;
	var dot:FlxSprite;
	var label:FlxText;
	var countBg:FlxSprite;
	var countTxt:FlxText;
	var onClick:Void->Void;
	var active:Bool = false;
	var count:Int = 0;
	var labelKey:String;
	var sprites:Array<FlxSprite> = [];

	public function new(x:Float, y:Float, w:Int, h:Int, labelKey:String, dotColor:FlxColor, onClick:Void->Void)
	{
		this.x = x;
		this.y = y;
		this.w = w;
		this.h = h;
		this.labelKey = labelKey;
		this.onClick = onClick;

		// 扁平填充（选中 12% / 悬停 5%），直角贴边 —— 不是圆角药丸
		bg = new FlxSprite(x, y).makeGraphic(w, h, 0xFFFFFFFF, true);
		bg.alpha = 0;

		// 状态圆点：8x8 圆角 = 圆形
		dot = FlxSpriteUtil.drawRoundRect(new FlxSprite(x, y).makeGraphic(8, 8, FlxColor.TRANSPARENT, true), 0, 0, 8, 8, 4, 4, dotColor);

		label = new SharpText(x, y, 0, Language.get(labelKey, 'mods'), 13);
		ModsMenuState.fmtSharp(label, 13, ModsMenuState.C_TEXT);

		// 数字胶囊（原型 .tab .n）
		countBg = FlxSpriteUtil.drawRoundRect(new FlxSprite(x, y).makeGraphic(26, 17, FlxColor.TRANSPARENT, true), 0, 0, 26, 17, 8, 8, 0x1AFFFFFF);
		countTxt = new SharpText(x, y, 26, '0', 11);
		ModsMenuState.fmtSharp(countTxt, 11, ModsMenuState.C_DIM, CENTER);

		sprites = [bg, dot, label, countBg, countTxt];
		layout();
		applyVisual();
	}

	/** 内容整体居中：[圆点] 7 [文字] 7 [胶囊] */
	function layout()
	{
		var total = 8 + 7 + label.width + 7 + 26;
		var cx = x + (w - total) / 2;
		dot.x = cx;
		dot.y = y + (h - 8) / 2;
		label.x = cx + 8 + 7;
		label.y = y + (h - label.height) / 2;
		countBg.x = cx + 8 + 7 + label.width + 7;
		countBg.y = y + (h - 17) / 2;
		countTxt.x = countBg.x;
		countTxt.y = countBg.y + 1;
	}

	public function setCount(v:Int)
	{
		if (count == v) return;
		count = v;
		countTxt.text = Std.string(v);
		layout();
	}

	public function setActive(v:Bool)
	{
		active = v;
		applyVisual();
	}

	function applyVisual()
	{
		bg.alpha = active ? 0.12 : (hovered ? 0.05 : 0);
		label.alpha = active ? 1 : 0.72;
		countBg.alpha = active ? 1 : 0.7;
		countTxt.alpha = active ? 1 : 0.8;
		countTxt.color = active ? ModsMenuState.C_TEXT : ModsMenuState.C_DIM;
	}

	public function addTo(state:ModsMenuState, cam:FlxCamera)
	{
		for (s in sprites)
		{
			s.cameras = [cam];
			s.scrollFactor.set();
			state.add(s);
		}
	}

	public function setVisible(v:Bool)
	{
		for (s in sprites) s.visible = v;
	}

	/** 供设置视图淡出/淡入标签用（含全部内部元素） */
	public function contentSprites():Array<FlxSprite>
	{
		return sprites;
	}

	/** 按当前 active/hovered 状态还原本征 alpha（设置视图退场时用，避免和补间打架） */
	public function restoreVisual()
	{
		applyVisual();
	}

	public function updateHover()
	{
		if (!bg.visible) return;
		var over = ModsMenuState.pointerOver(x, y, w, h);
		if (over != hovered)
		{
			hovered = over;
			label.color = over ? ModsMenuState.C_ACCENT : ModsMenuState.C_TEXT;
			applyVisual();
		}
		if (over && ModsMenuState.pointerJustPressed())
		{
			ModsMenuState.dbg('  -> click [' + dbgName + '] rect=(' + Std.int(x) + ',' + Std.int(y) + ',' + w + ',' + h + ')');
			onClick();
		}
	}
}

// ══════════════════════════════════════════════════════════════════════
// 通用文字按钮（底部三按钮 / 窗口条文字按钮 / 确认框按钮）
// ══════════════════════════════════════════════════════════════════════
class FlatButton
{
	public var x:Float;
	public var y:Float;
	public var w:Float = 120;
	public var h:Float = 26;
	public var highlight:Bool = false;
	public var hovered:Bool = false;
	public var active:Bool = false;
	/** 调试用名字（点击时写进 modsmenu_debug.log） */
	public var dbgName:String = '';

	/**
	 * true = 无底色（底部三按钮）。
	 * ★ 注意：必须是属性 —— 老代码里先 setSize() 再 `flat = true`，
	 *   而 setSize 时 flat 还是 false，于是把白色圆角矩形画进了底图（标签曾被画成药丸）。
	 */
	public var flat(default, set):Bool = false;

	function set_flat(v:Bool):Bool
	{
		if (flat == v) return v;
		flat = v;
		redrawBg();
		applyBg();
		return v;
	}

	var bg:FlxSprite;
	var txt:FlxText;
	var onClick:Void->Void;
	var enabled:Bool = true;

	public function new(x:Float, y:Float, text:String, onClick:Void->Void)
	{
		this.x = x;
		this.y = y;
		this.onClick = onClick;
		bg = new FlxSprite(x, y);
		txt = new SharpText(x, y + 6, 120, text, 12);
		ModsMenuState.fmtSharp(txt, 12, ModsMenuState.C_TEXT, CENTER);
		redrawBg();
		applyBg();
	}

	/** ★ unique = true：FlxSprite.makeGraphic 会按「宽x高:颜色」缓存并共享同一张位图，
	 *  往共享位图上 drawRoundRect 会污染所有同尺寸精灵（老代码就是踩了这个坑）。 */
	function redrawBg()
	{
		var iw:Int = Std.int(Math.max(1, w));
		var ih:Int = Std.int(Math.max(1, h));
		bg.makeGraphic(iw, ih, FlxColor.TRANSPARENT, true);
		if (!flat && iw > 4) FlxSpriteUtil.drawRoundRect(bg, 0, 0, iw, ih, 7, 7, 0xFFFFFFFF);
	}

	public function setSize(w:Int, h:Int)
	{
		this.w = w;
		this.h = h;
		redrawBg();
		txt.x = x;
		txt.y = y + (h - txt.height) / 2;
		// txt 是 fmtSharp 过的（fieldWidth 已乘倍率），这里也要按逻辑宽换算
		txt.fieldWidth = Std.int(w * ModsMenuState.TXT_SS);
		applyBg();
	}

	function applyBg()
	{
		if (!enabled) bg.alpha = 0.02;
		else if (flat) bg.alpha = hovered ? 0.10 : (active ? 0.14 : 0);
		else bg.alpha = hovered ? 0.16 : (active ? 0.14 : 0.06);
	}

	public function setText(s:String)
	{
		txt.text = s;
		txt.y = y + (h - txt.height) / 2;
	}

	/** 同时挪 x/y（空状态两个按钮要摆到正文下方居中） */
	public function setPos(nx:Float, ny:Float)
	{
		x = nx;
		y = ny;
		bg.setPosition(nx, ny);
		txt.x = nx;
		txt.y = ny + (h - txt.height) / 2;
	}

	public function setActive(v:Bool)
	{
		active = v;
		txt.alpha = v ? 1 : 0.75;
		applyBg();
	}

	public function setX(nx:Float)
	{
		x = nx;
		bg.x = nx;
		txt.x = nx;
	}

	public function setEnabled(v:Bool)
	{
		enabled = v;
		txt.alpha = v ? (active ? 1 : 0.95) : 0.35;
		applyBg();
	}

	public function setVisible(v:Bool)
	{
		bg.visible = v;
		txt.visible = v;
	}

	public function addTo(state:ModsMenuState, cam:FlxCamera)
	{
		for (s in [bg, txt])
		{
			s.cameras = [cam];
			s.scrollFactor.set();
			state.add(s);
		}
		state.allButtons.push(this);
	}

	public function updateHover()
	{
		if (!bg.visible) return;
		var over = ModsMenuState.pointerOver(x, y, w, h);
		if (over != hovered)
		{
			hovered = over;
			txt.color = over ? ModsMenuState.C_ACCENT : ModsMenuState.C_TEXT;
			applyBg();
		}
		if (over && enabled && ModsMenuState.pointerJustPressed())
		{
			ModsMenuState.dbg('  -> click [' + dbgName + '] rect=(' + Std.int(x) + ',' + Std.int(y) + ',' + Std.int(w) + ',' + Std.int(h) + ')');
			onClick();
		}
	}
}

// ══════════════════════════════════════════════════════════════════════
// 详情右上角【启用 / 禁用】开关
//   ★ 直接复用设置界面那个开关（source/options/objects/backend/BoolButton.hx）的
//     控件与参数：同一个 general.shapeEx.Rect 圆角矩形，同一个尺寸比例
//     （轨道宽:高 ≈ 4:1、滑块 = 轨道宽的一半）、同一组颜色
//     （关 = 0xFF6363 / 开 = 0x63FF75、滑块白 0.8、整体 alpha 0.8），
//     连滑块 0.2 秒 quadOut 的位移动画和每帧朝目标色插值的做法都照搬，
//     所以它看起来和设置里的一模一样。
//   右侧补一个状态文字 + 一句"点击切换启用状态"（模组菜单没有设置项那样的标题行）。
// ══════════════════════════════════════════════════════════════════════
class SwitchButton
{
	// 与 BoolButton 完全一致的两个目标色
	static inline var COL_OFF:FlxColor = 0xFF6363;
	static inline var COL_ON:FlxColor = 0x63FF75;
	// 轨道尺寸（≈4:1，和设置里一致）；滑块 = W/2-4 x H-6，位置 2 / W/2+1
	static inline var TRACK_W:Float = 112;
	static inline var TRACK_H:Float = 30;
	static inline var KNOB_PAD:Float = 2; // 滑块离轨道边 2px（BoolButton: x=2）
	static inline var KNOB_PAD_Y:Float = 3; // BoolButton: y=3

	var x:Float;
	var y:Float;
	var w:Int = 200;
	var h:Int = 30;
	var track:Rect;
	var knob:Rect;
	var txt:FlxText;
	var hint:FlxText;
	var onClick:Void->Void;
	var state:Bool = true;
	var hovered:Bool = false;
	var curCol:FlxColor = COL_ON; // 每帧朝目标色插值（同 BoolButton.updateBgColor）
	var knobTween:FlxTween = null;

	public function new(x:Float, y:Float, onClick:Void->Void)
	{
		this.x = x;
		this.y = y;
		this.onClick = onClick;

		var round:Float = TRACK_W / 20; // BoolButton: 圆角 = 宽/20
		track = new Rect(x, y, TRACK_W, TRACK_H, round, round, COL_ON, 0.8);
		knob = new Rect(x + KNOB_PAD, y + KNOB_PAD_Y, TRACK_W / 2 - KNOB_PAD * 2, TRACK_H - KNOB_PAD_Y * 2, round, round, FlxColor.WHITE, 0.8);

		txt = new SharpText(x, y, 0, Language.get('enabledLabel', 'mods'), 14);
		ModsMenuState.fmtSharp(txt, 14, 0xFF7DE3A6);
		hint = new SharpText(x, y, 0, Language.get('toggleHint', 'mods'), 11);
		ModsMenuState.fmtSharp(hint, 11, ModsMenuState.C_HINT);

		layout();
		setState(true, true);
	}

	/** 总宽 = [轨道][12][状态文字][10][提示] */
	function layout()
	{
		w = Std.int(TRACK_W + 12 + txt.width + 10 + hint.width);
		h = Std.int(TRACK_H);
		track.x = x;
		track.y = y;
		knob.y = y + KNOB_PAD_Y;
		txt.x = x + TRACK_W + 12;
		txt.y = y + (h - txt.height) / 2;
		hint.x = txt.x + txt.width + 10;
		hint.y = y + (h - hint.height) / 2;
	}

	public function addTo(state0:ModsMenuState, cam:FlxCamera)
	{
		for (s in [track, knob, txt, hint])
		{
			s.cameras = [cam];
			s.scrollFactor.set();
			state0.add(s);
		}
	}

	/** 供设置视图把整个详情页"整体上滚"用（记录 y / 落回都走 ModsMenuState.detailSavedY） */
	public function contentSprites():Array<FlxSprite>
	{
		return cast [track, knob, txt, hint];
	}

	/** 右对齐用：左边界（详情标题据此决定可用宽度） */
	public function left():Float
	{
		return x;
	}

	/** 无模组时一起隐藏 */
	public function setVisible(v:Bool):Void
	{
		track.visible = v;
		knob.visible = v;
		txt.visible = v;
		hint.visible = v;
	}

	public function setRight(rx:Float)
	{
		setX(rx - w);
	}

	public function setX(nx:Float)
	{
		x = nx;
		layout();
	}

	/** 换状态：滑块 0.2 秒 quadOut 滑过去（BoolButton.updateDisplay 同款） */
	public function setState(v:Bool, instant:Bool = false)
	{
		state = v;
		txt.text = v ? Language.get('enabledLabel', 'mods') : Language.get('disabledLabel', 'mods');
		txt.color = v ? 0xFF7DE3A6 : 0xFFF79A9A;
		layout();

		var targetX:Float = v ? (x + TRACK_W / 2 + 1) : (x + KNOB_PAD);
		if (instant)
		{
			knob.x = targetX;
		}
		else
		{
			if (knobTween != null) knobTween.cancel();
			knobTween = FlxTween.tween(knob, {x: targetX}, 0.2, {ease: FlxEase.quadOut});
		}
		if (instant) curCol = v ? COL_ON : COL_OFF;
	}

	public function updateHover()
	{
		if (!track.visible) return; // 空状态整块隐藏时不许再响应点击
		var over = ModsMenuState.pointerOver(x, y, w, h);
		if (over != hovered)
		{
			hovered = over;
			txt.color = over ? ModsMenuState.C_ACCENT : (state ? 0xFF7DE3A6 : 0xFFF79A9A);
		}
		if (over && ModsMenuState.pointerJustPressed())
		{
			ModsMenuState.dbg('  -> click [detail:toggle] at(' + Std.int(ModsMenuState.pointerX()) + ',' + Std.int(ModsMenuState.pointerY()) + ')');
			onClick();
		}
		// 每帧朝目标色插值（复刻 BoolButton.updateBgColor；悬停时整体亮一点）
		var target:FlxColor = state ? COL_ON : COL_OFF;
		if (hovered) target = FlxColor.interpolate(target, FlxColor.WHITE, 0.18);
		curCol = FlxColor.interpolate(curCol, target, 0.2);
		track.color = curCol;
	}
}

// ══════════════════════════════════════════════════════════════════════
// 超采样文字：每次位图重建（makeGraphic → resetHelpers → centerOrigin）都会把
// origin 拽回中心，缩放锚点随之漂移（文字/按钮文字整体右下偏移）。
// 这里在每次 regen 后强制归零，保证 fmtSharp 的"1.5x 光栅 + 缩回"锚定左上角。
// ══════════════════════════════════════════════════════════════════════
class SharpText extends FlxText
{
	override function regenGraphic():Void
	{
		super.regenGraphic();
		origin.set(0, 0);
		offset.set(0, 0);
	}

	public function new(X:Float = 0, Y:Float = 0, FieldWidth:Float = 0, ?Text:String, Size:Int = 8, EmbeddedFont:Bool = true)
	{
		super(X, Y, FieldWidth, Text, Size, EmbeddedFont);
	}
}

// ══════════════════════════════════════════════════════════════════════
// 模组设置项（内嵌视图的运行时记录）
//   不复用 options.base.OptionBase：那套 getValue/setValue 绑死 ClientPrefs.data，
//   模组设置要读写的是 FlxG.save.data.modSettings[folder]，值语义自己管。
// ══════════════════════════════════════════════════════════════════════
class SettOpt
{
	public var saveKey:String;
	public var name:String = '';
	public var desc:String = '';
	public var type:String = 'bool'; // bool / int / float / percent / string / keybind
	public var options:Array<String> = null; // string 型的候选值
	public var value:Dynamic = null; // 当前值
	public var def:Dynamic = null; // 默认值（settings.json 的 value 字段）
	public var format:String = '%v'; // 显示格式（%v = 当前值，%d = 默认值）
	public var min:Dynamic = null;
	public var max:Dynamic = null;
	public var step:Float = 1;
	public var scrollSpeed:Float = 1;
	public var decimals:Int = 0;
	public var curIdx:Int = 0; // string 型当前候选下标
	public var keys:{keyboard:String, gamepad:String} = null; // keybind 型
	public var isHeader:Bool = false; // 分组标题行（Toolbox 的单值 string 项）
	public var rowVisible:Bool = true; // 设置视图搜索过滤
	public var uiY:Float = 0; // 在选项列表中的世界 y（setCam）
	// UI（懒建，随 buildSettingsOptions 重建）
	public var rowBg:FlxSprite = null;
	public var nameTxt:FlxText = null;
	public var valTxt:FlxText = null;

	public function new() {}
}

// ══════════════════════════════════════════════════════════════════════
// 设置视图的 bool 开关：SwitchButton 的紧凑版（无状态文字/提示，纯轨道+滑块），
// 尺寸/颜色/动画节奏与其一致，避免"详情开关和设置开关长得不一样"。
// ══════════════════════════════════════════════════════════════════════
class SettToggle
{
	static inline var COL_OFF:FlxColor = 0xFF6363;
	static inline var COL_ON:FlxColor = 0x63FF75;
	static inline var TRACK_W:Float = 88;
	static inline var TRACK_H:Float = 30;

	var x:Float;
	var y:Float;
	var track:Rect;
	var knob:Rect;
	var onClick:Void->Void;
	var state:Bool = false;
	var hovered:Bool = false;
	var curCol:FlxColor = COL_OFF;
	var knobTween:FlxTween = null;

	public function new(x:Float, y:Float, onClick:Void->Void)
	{
		this.x = x;
		this.y = y;
		this.onClick = onClick;

		var round:Float = TRACK_W / 20;
		track = new Rect(x, y, TRACK_W, TRACK_H, round, round, COL_ON, 0.8);
		knob = new Rect(x + 2, y + 3, TRACK_W / 2 - 4, TRACK_H - 6, round, round, FlxColor.WHITE, 0.8);
		setState(false, true);
	}

	public function addTo(state0:ModsMenuState, cam:FlxCamera)
	{
		for (s in [track, knob])
		{
			s.cameras = [cam];
			s.scrollFactor.set();
			state0.add(s);
		}
	}

	public function setVisible(v:Bool)
	{
		track.visible = v;
		knob.visible = v;
	}

	public function setState(v:Bool, instant:Bool = false)
	{
		state = v;
		var targetX:Float = v ? (x + TRACK_W / 2 + 1) : (x + 2);
		if (instant)
		{
			knob.x = targetX;
			curCol = v ? COL_ON : COL_OFF;
		}
		else
		{
			if (knobTween != null) knobTween.cancel();
			knobTween = FlxTween.tween(knob, {x: targetX}, 0.2, {ease: FlxEase.quadOut});
		}
	}

	public function updateHover()
	{
		if (!track.visible) return;
		var over = ModsMenuState.pointerOver(x, y, TRACK_W, TRACK_H);
		if (over && ModsMenuState.pointerJustPressed()) onClick();
		var target:FlxColor = state ? COL_ON : COL_OFF;
		if (over) target = FlxColor.interpolate(target, FlxColor.WHITE, 0.18);
		curCol = FlxColor.interpolate(curCol, target, 0.2);
		track.color = curCol;
	}
}
