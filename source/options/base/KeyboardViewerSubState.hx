package options.base;

import openfl.display.BitmapData;
import openfl.display.Shape;

import flixel.addons.display.shapes.FlxShapeCircle;
import flixel.addons.ui.FlxUIInputText;
import flixel.util.FlxGradient;

import general.backend.language.Language;

import games.objects.KeyboardViewer;

#if sys
import sys.io.File;
import sys.FileSystem;
#end

/**
 * 键盘反馈设置（KeyboardViewer 的编辑界面）—— v2 定稿版。
 *
 * 版面（**全屏铺满**，不做成"悬浮小面板"；所有可点目标都按移动端触摸尺寸放大）：
 *
 *   左 60%：默认样式 10K（只读对照）→ 自定样式 10K（点键位/统计块选中）→ 三态卡
 *   右 40%：颜色 / 长条 / 统计 / 主题 四个分区 + 取色浮层抽屉
 *   底部  ：正在编辑 · X                [恢复默认设置]  [保存并退出]
 *
 * ★ 三条硬规则（都是上一版被否掉的地方）：
 *   1. **只有颜色才逐目标独立**；透明度 / 长条 / 统计区 / 配色来源都是全局的。
 *      统计区的高・宽・透明度因此天然是"两个统计块一起变"。
 *   2. 预览里 **每个键各用各的配置** —— 绝不能把同一份配置喂给 10 个键，
 *      否则改一个键的颜色整排一起变（用户原话："直接被全局应用了"）。
 *   3. 选中 KPS / total 时不画三态卡（统计块没有被按下态和长条）。
 */
class KeyboardViewerSubState extends MusicBeatSubstate
{
	// ==================== 版面常量（触摸目标都 ≥44） ====================
	static inline var FOOT_H:Float = 78;
	static inline var TAB_H:Float = 44;
	static inline var ROW_H:Float = 44;
	static inline var CARD_H:Float = 30;
	static inline var PICK_H:Float = 216; // 左区取色盘的高度
	static inline var BTN_H:Float = 54;
	static inline var SW_W:Float = 56;
	static inline var SW_H:Float = 28;
	static inline var NAME_W:Float = 168;
	static inline var PREV_H:Float = 132;
	static inline var SLOTS:Int = 10; // 行槽位数量（切分区时复用）
	static inline var SEGMAX:Int = 5; // 单个 seg 行最多几个选项（主题有 5 个）

	static inline var C_BG:Int = 0xFF0D0D0F;
	static inline var C_CARD:Int = 0xFF1A1A1E;
	static inline var C_LINE:Int = 0xFF34343A;
	static inline var C_INK:Int = 0xFFEDF2FA;
	static inline var C_INK2:Int = 0xFFA7B3C6;
	static inline var C_INK3:Int = 0xFF7E8A9D;
	static inline var C_DIM:Int = 0xFF5A6376;
	static inline var C_ACC:Int = 0xFF7FB0FF;
	static inline var C_MARK:Int = 0xFF8EC1FF;
	static inline var C_WARN:Int = 0xFFFF9E5E;

	static var KEY_NAMES:Array<String> = ['A', 'S', 'D', 'F', 'V', 'N', 'J', 'K', 'L', ';'];

	// ==================== 版面 ====================
	var W:Float = 0;
	var H:Float = 0;
	var bodyH:Float = 0;
	var leftW:Float = 0;
	var rightX:Float = 0;
	var rightW:Float = 0;
	var contentX:Float = 0;
	var contentW:Float = 0;
	var ctlX:Float = 0;
	var ctlW:Float = 0;
	var listTop:Float = 68;

	// ==================== 预览 ====================
	var cusViewer:KeyboardViewer;
	var cusBox:KVBox;
	var cusScale:Float = 1;
	var cusHead:FlxText;
	var cusHeadTag:FlxText;
	/** 「默认样式」对照：和取色盘**共用左区底部**那块位置，没在调颜色的时候就显示它 */
	var defViewer:KeyboardViewer;
	var defBox:KVBox;
	var defScale:Float = 1;
	var defHead:FlxText;
	var defTag:FlxText;
	var arrowSpr:FlxSprite;

	// ==================== 当前编辑目标 ====================
	/** 0..9 = 键位，10 = KPS，11 = total */
	var target:Int = 3;

	inline function isStat():Bool return target >= 10;

	function shortName(i:Int):String
	{
		if (i == 10) return 'KPS';
		if (i == 11) return 'total';
		return KEY_NAMES[i];
	}

	// ==================== 三态卡 ====================
	/** 三态卡的全部元素（直接挂在 state 上，不走 FlxSpriteGroup —— 那一层下 sprite 不渲染，只有文字能画出来） */
	var triParts:Array<FlxSprite> = [];
	/** 三态卡整体是否显示（统计块时收起） */
	var triShown:Bool = true;
	/** 预览的结构是否已经建好（建好之后只刷颜色，不再重建） */
	var previewsBuilt:Bool = false;
	/** 三态卡顶边（layoutTriCard 算好存下来；基线用它，不要读 triBG.fill.y —— 取到过 0，长条被画到预览区去了） */
	var triTop:Float = 216;
	var triBG:KVBox;
	var triTitle:FlxText;
	var triCaps:Array<FlxText> = [];
	var triKeyBG:FlxSprite;
	var triKeyTxt:FlxText;
	var triPressBG:FlxSprite;
	var triPressTxt:FlxText;
	var triBar:FlxSprite;
	var triBarBase:FlxSprite;
	var triBarMeta:FlxText;

	// ==================== 分区 / 行 ====================
	static var TAB_ZH:Array<String> = ['颜色', '长条', '统计', '主题'];
	static var TAB_EN:Array<String> = ['Colors', 'Bars', 'Stats', 'Theme'];
	var tab:Int = 0;
	var tabBoxes:Array<KVBox> = [];
	var tabTxts:Array<FlxText> = [];
	var tabInd:FlxSprite;

	var rows:Array<KVRow> = [];
	var selected:Int = 0;
	var scrollFrom:Int = 0;
	var maxVisible:Int = 7;
	var rowY:Array<Float> = []; // 每行的 y（renderRows 时填好，命中检测直接查）

	var rBack:Array<FlxSprite> = [];
	var rName:Array<FlxText> = [];
	var rFill:Array<FlxSprite> = [];
	var rFillBG:Array<FlxSprite> = [];
	var rKnob:Array<FlxSprite> = [];
	var rSwBG:Array<FlxSprite> = [];
	var rChip:Array<FlxSprite> = []; // 颜色行的色块 / seg 行的选中底衬
	var rVal:Array<FlxText> = [];
	var rMinus:Array<FlxText> = [];
	var rPlus:Array<FlxText> = [];
	var rSegBG:Array<FlxSprite> = [];
	var rSegTxt:Array<FlxText> = [];
	var rReset:Array<FlxText> = [];
	var rGroupHead:Array<FlxText> = [];
	var rGroupLine:Array<FlxSprite> = [];

	var rPrevBox:FlxSprite;
	var rPrevBar:FlxSprite;
	var rPrevBase:FlxSprite;
	var rPrevMeta:FlxText;
	var prevRowY:Float = 0;
	var prevRowH:Float = 0;

	/**
	 * 长条的循环演示计时（秒）。
	 * ★ 「消隐」是**时间维度**的效果（升起来 → 停一会儿 → 淡出/直接没），
	 *   静止的预览根本看不出来 —— 所以预览里的长条必须自己动起来，
	 *   否则用户会以为"渐隐没做出来"。
	 */
	var barAnimT:Float = 0;
	static inline var BAR_CYCLE:Float = 2.4;
	static inline var BAR_GROW:Float = 0.3;
	/** 停留要够久：消隐段太长的话，静态看过去大部分时间都是"空的"，像没做出来 */
	static inline var BAR_HOLD:Float = 1.55;
	static inline var BAR_TEX_W:Int = 32;
	static inline var BAR_TEX_H:Int = 128;
	static var barTexFade:BitmapData;
	static var barTexSolid:BitmapData;
	/** 三态卡两个方块的贴图：和实机 KeyButton / KeyButtonAlpha 同款（描边 1.0 : 填充 0.375） */
	static var keyTex:BitmapData;
	static var pressTex:BitmapData;
	static inline var TRI_KEY_SIZE:Int = 68;

	var scrollUp:KVBox;
	var scrollDown:KVBox;
	var scrollUpTxt:FlxText;
	var scrollDownTxt:FlxText;
	var scrollBar:FlxSprite;
	var scrollBarBG:FlxSprite;

	// ==================== 取色抽屉 ====================
	var pickGroup:FlxSpriteGroup;
	var pickBG:KVBox;
	var pickTitle:FlxText;
	var colorGradient:FlxSprite;
	var colorGradSel:FlxSprite;
	var colorWheel:FlxSprite;
	var colorWheelSel:FlxShapeCircle;
	var colorPalette:FlxSprite;
	var palBitmap:BitmapData;
	var hexInput:FlxUIInputText;
	var curSwatch:FlxSprite;
	var rgbText:FlxText;
	var pickOpen:Bool = false;
	/** 左区底部那块面板的淡入进度（取色盘 ↔ 默认样式 切换时用，0→1） */
	var paneFade:Float = 0;
	var holding:FlxSprite;

	// ==================== 底部 ====================
	var resetAllBox:KVBox;
	var resetAllTxt:FlxText;
	var saveBox:KVBox;
	var saveTxt:FlxText;
	var whereTxt:FlxText;
	var toastTxt:FlxText;
	var toastTime:Float = 0;

	// ==================== 交互状态 ====================
	var dragRow:Int = -1;
	var lastMouseX:Float = 0;
	var closing:Bool = false;

	// ==================== 主题预设 ====================
	static var THEME_KEYS:Array<String> = ['default', 'black', 'fnf', 'fnfpixel', 'custom'];
	static var THEME_ZH:Array<String> = ['默认', '黑', 'FNF 标准', 'FNF 像素', '自定义'];
	static var THEME_EN:Array<String> = ['Default', 'Black', 'FNF', 'FNF Pixel', 'Custom'];
	static var THEMES:Map<String, {normal:String, normalText:String, press:String, pressText:String, bar:String}> = [
		'default' => {normal: '#FFFFFF', normalText: '#0A0A0A', press: '#FFFFFF', pressText: '#0A0A0A', bar: '#FFFFFF'},
		'black' => {normal: '#3A3A46', normalText: '#FFFFFF', press: '#E8ECF6', pressText: '#0A0A12', bar: '#9AA2B4'},
		'fnf' => {normal: '#C24B99', normalText: '#FFFFFF', press: '#00FFFF', pressText: '#04303A', bar: '#12FA05'},
		'fnfpixel' => {normal: '#E276FF', normalText: '#FFFFFF', press: '#3DCAFF', pressText: '#032B3A', bar: '#71E300'}
	];

	public function new()
	{
		super();

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Keyboard Feedback Menu", null);
		#end

		computeLayout();
		ensureBarTex();

		/* 旧版的 'BG'（长条跟按键底色）已经不在新界面里了，归一化成 'Custom'。
		   不归一化的话，界面高亮的是"用长条颜色"，实际却仍然取旧字段 keyboardBGColor
		   （用户存档里那是 #269AFF 蓝）—— 长条莫名其妙是蓝的就是这条。 */
		if (ClientPrefs.data.keyboardBarColorMode != 'Key') ClientPrefs.data.keyboardBarColorMode = 'Custom';

		/* 整块面板是**半透明**的：让游戏画面透出来（用户明确要求，上一版铺了个不透明的
		   黑蓝实底，等于把背景盖死了）。底色也一并去掉蓝味，改成中性深灰 ——
		   蓝色只留给强调色（选中/箭头/主按钮）。 */
		var dim:FlxSprite = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0xFF000000);
		dim.alpha = 0.55;
		dim.scrollFactor.set();
		add(dim);

		buildLeft();
		buildRight();
		buildPicker();
		buildFooter();

		updateWhere();
		switchTab(0, true);
		updateTriCard();
		layoutDefaultPane();

		addVirtualPad(NONE, B_C);
		if (virtualPad != null && virtualPad.buttonC != null)
			virtualPad.buttonC.onUp.callback = function() resetAll();

		#if desktop
		FlxG.mouse.visible = false; // 自绘界面里系统指针很碍眼
		openfl.ui.Mouse.hide();
		#end
	}

	// =====================================================================
	// 版面
	// =====================================================================

	function computeLayout():Void
	{
		W = FlxG.width;
		H = FlxG.height;
		bodyH = H - FOOT_H;

		leftW = Math.round(W * 0.60);
		rightX = leftW + 4;
		rightW = W - rightX;
		contentX = rightX + 14;
		contentW = rightW - 28;
		ctlX = contentX + NAME_W;
		ctlW = contentW - NAME_W - 36;
	}

	inline function zh():Bool
	{
		var l:String = ClientPrefs.data.language;
		return l.indexOf('中文') > -1 || l.toLowerCase().indexOf('chinese') > -1 || l == 'I Dont Like Haxe';
	}

	inline function t(key:String, fbZH:String, fbEN:String):String
	{
		var raw:String = Language.get(key, 'options');
		if (raw == key || raw == key + ' (404)') return zh() ? fbZH : fbEN;
		return raw;
	}

	// =====================================================================
	// 左区：预览舞台
	// =====================================================================

	function buildLeft():Void
	{
		var bg:FlxSprite = new FlxSprite(0, 0).makeGraphic(Math.floor(leftW), Math.floor(H), C_BG);
		bg.alpha = 0.40;
		bg.scrollFactor.set();
		add(bg);

		var sky:FlxSprite = new FlxSprite(0, H - 200).makeGraphic(Math.floor(leftW), 200, 0xFF1C1C22);
		sky.alpha = 0.22;
		sky.scrollFactor.set();
		add(sky);

		var pill:KVBox = makeBox(92, 24, 0x1B2A44, 0x3D6BB5);
		boxPos(pill, 22, 16);
		var pillTxt:FlxText = mkTxt(22, 20, 92, zh() ? '实时预览' : 'LIVE', 12, 0xFFCFE0FF);
		pillTxt.alignment = CENTER;

		mkTxt(126, 21, leftW - 148,
			t('kv_preview_hint', '点按键或统计块切换编辑目标；选中颜色项时，左下角会出现取色盘',
				'Click a key or stat block to edit; the colour wheel appears bottom-left for colour rows'), 12, C_INK3);

		cusHead = mkTxt(22, 56, 300, t('kv_custom_style', '自定样式', 'Custom style'), 13, C_INK);
		cusHeadTag = mkTxt(110, 56, 200, t('kv_editable', '可编辑', 'editable'), 11.5, C_ACC);
		cusBox = makeBox(leftW - 44, 4, 0x111725, C_LINE);
		cusBox.fill.alpha = 1;

		cusViewer = new KeyboardViewer(0, 0, 10, true);
		add(cusViewer);

		// 默认样式（只读对照）—— 位置由 layoutDefaultPane() 摆在左区底部
		defHead = mkTxt(0, 0, 300, t('kv_default_style', '默认样式', 'Default style'), 13, C_INK2);
		defTag = mkTxt(0, 0, 240, t('kv_readonly', '（只读对照）', '(read-only)'), 11.5, C_INK3);
		defBox = makeBox(200, 160, 0x0E0E12, C_LINE);
		defBox.fill.alpha = 0.55;
		defViewer = new KeyboardViewer(0, 0, 10, true);
		add(defViewer);
		// 预览里键帽常显一点，玩家才能一眼看出 10K 每个键各自被设成了什么颜色
		for (k in cusViewer.keyAlphas) k.idleAlpha = 0.5;

		arrowSpr = makeDownArrow(20, C_MARK);
		arrowSpr.visible = false;
		add(arrowSpr);

		buildTriCard();

		refreshPreviews();
	}

	function layoutPreviews():Void
	{
		var boxW:Float = leftW - 44;
		var availW:Float = boxW - 32;

		cusScale = Math.min(1, availW / Math.max(1, cusViewer._width));
		cusViewer.scale.set(cusScale, cusScale);
		var ch:Float = cusViewer._height * cusScale;
		cusViewer.setPosition(22 + (boxW - cusViewer._width * cusScale) / 2, 84);
		resizeBox(cusBox, 22, 72, boxW, ch + 24);

		layoutTriCard();
		updateArrow();
	}

	/** 生成两张长条贴图：渐隐版（顶部柔边，与实机 DisBitmap 同款）与实心版 */
	static function ensureBarTex():Void
	{
		if (barTexSolid != null) return;

		var solid:Shape = new Shape();
		solid.graphics.beginFill(0xFFFFFFFF);
		solid.graphics.drawRect(0, 0, BAR_TEX_W, BAR_TEX_H);
		solid.graphics.endFill();
		barTexSolid = new BitmapData(BAR_TEX_W, BAR_TEX_H, true, 0);
		barTexSolid.draw(solid);

		var soft:Int = Std.int(BAR_TEX_H / 10);
		if (soft < 1) soft = 1;
		var fade:Shape = new Shape();
		for (i in 0...soft)
		{
			fade.graphics.beginFill(FlxColor.WHITE, i / soft);
			fade.graphics.drawRect(0, i, BAR_TEX_W, 1);
			fade.graphics.endFill();
		}
		fade.graphics.beginFill(FlxColor.WHITE);
		fade.graphics.drawRect(0, soft, BAR_TEX_W, BAR_TEX_H - soft);
		fade.graphics.endFill();
		barTexFade = new BitmapData(BAR_TEX_W, BAR_TEX_H, true, 0);
		barTexFade.draw(fade);

		/* 三态卡的两个方块必须用"实机同款贴图 + color 着色"，不能拿常态色跟 keyboardBGColor
		   插值糊弄 —— keyboardBGColor 是旧版遗留的「按键底色」字段（老存档里可能被设成任何
		   颜色，本机存档里就是 #269AFF 蓝），实机键帽压根不读它。用户看到的
		   "常态不是 FFF 吗，怎么是蓝的" 就是这条插值带偏的。 */
		var kr:Int = Std.int(TRI_KEY_SIZE / 3);
		var ksh:Shape = new Shape();
		ksh.graphics.lineStyle(2, 0xFFFFFFFF, 1);
		ksh.graphics.drawRoundRect(0, 0, TRI_KEY_SIZE, TRI_KEY_SIZE, kr, kr);
		ksh.graphics.lineStyle();
		ksh.graphics.beginFill(0xFFFFFFFF, 0.375); // 0.3 / 0.8，与 KeyButton 的填充:描边比例一致
		ksh.graphics.drawRoundRect(0, 0, TRI_KEY_SIZE, TRI_KEY_SIZE, kr, kr);
		ksh.graphics.endFill();
		keyTex = new BitmapData(TRI_KEY_SIZE, TRI_KEY_SIZE, true, 0);
		keyTex.draw(ksh);

		var psh:Shape = new Shape();
		psh.graphics.beginFill(0xFFFFFFFF, 1);
		psh.graphics.drawRoundRect(0, 0, TRI_KEY_SIZE, TRI_KEY_SIZE, kr, kr);
		psh.graphics.endFill();
		pressTex = new BitmapData(TRI_KEY_SIZE, TRI_KEY_SIZE, true, 0);
		pressTex.draw(psh);
	}

	/** 一个长条演示周期里"长满"用多久（= TimeDis 的 durationTime） */
	function barDemoGrow():Float
	{
		var spd:Float = ClientPrefs.data.keyboardBarSpeed;
		if (spd < 0.05) spd = 0.05;
		return Math.max(0.06, ClientPrefs.data.keyboardTime / spd / 1000);
	}

	static inline var BAR_DEMO_HOLD:Float = 0.06; // 只留一点点，避免

	function barDemoCycle():Float
	{
		return barDemoGrow() * 2 + BAR_DEMO_HOLD;
	}

	/**
	 * 长条演示状态 —— **照搬 KeyboardViewer.TimeDis 的时序**，不再自己发明一套：
	 *   ① 从键位底部往上长满，耗时 durationTime（= keyboardTime / speed）
	 *   ② 保持满高一小段
	 *   ③ 松手后整根向上滑走并消失：fade 是一路淡出，sudden 是滑到一半直接没
	 */
	function barDemoState():{r:Float, slide:Float, a:Float}
	{
		var dur:Float = barDemoGrow();
		var t:Float = barAnimT;
		if (t < dur) return {r: t / dur, slide: 0, a: 1};
		if (t < dur + BAR_DEMO_HOLD) return {r: 1, slide: 0, a: 1};
		var u:Float = FlxMath.bound((t - dur - BAR_DEMO_HOLD) / dur, 0, 1);
		if (isBarFade()) return {r: 1, slide: u, a: 1 - u};
		return {r: 1, slide: u, a: (u < 0.5 ? 1 : 0)};
	}

	function updateBarAnim(elapsed:Float):Void
	{
		barAnimT += elapsed;
		var cyc:Float = barDemoCycle();
		if (barAnimT >= cyc) barAnimT -= cyc;
	}

	/** 每帧把循环动画套到三态卡和「长条」分区预览的那两根条上 */
	function updateBarVisual():Void
	{
		var mul:Float = FlxMath.bound(ClientPrefs.data.keyboardBarAlpha, 0, 1);
		var on:Bool = ClientPrefs.data.keyboardTimeDisplay;

		if (triBar != null && triBG != null)
		{
			var boxW:Float = leftW - 44;
			var cellW:Float = (boxW - 24) / 3;
			var cx2:Float = 22 + 8 + cellW * 2 + cellW / 2;
			var top:Float = triTop;
			triBar.visible = on && triShown;
			if (on && triShown)
			{
				triBar.color = barLaneColor(target); // ★ 搬进 updateBarVisual 之后漏了，长条一直用着没着色的白图
				drawBarSprite(triBar, cx2, top + 154, 34, 96);
			}
		}

		// prevRowH > 0 只会在「长条」分区里成立；切走时 renderRows() 会把它清零，
		// 所以这里不会像上一版那样把长条留在别的分区里不走。
		if (rPrevBar != null && prevRowH > 0)
		{
			rPrevBar.color = barLaneColor(target);
			rPrevBar.visible = on;
			if (on) drawBarSprite(rPrevBar, contentX + 50, prevRowY + 8 + prevRowH - 44, 34, prevRowH - 50);
		}
	}

	/**
	 * 画一根长条 —— **复刻 KeyboardViewer.TimeDis 的渲染**：
	 * 把"顶部渐隐"的贴图按 ratio 从**底部**往上撑开（柱子是从键位向上长出来的），
	 * 松手后再整体上滑 slide 个身位。
	 * ★ 用 origin 贴底 + scale 缩放实现，不碰 offset —— 否则又会踩 updateHitbox 那个居中偏移的坑。
	 */
	function drawBarSprite(bar:FlxSprite, centerX:Float, baseY:Float, maxW:Float, maxH:Float):Void
	{
		var st = barDemoState();
		var mul:Float = FlxMath.bound(ClientPrefs.data.keyboardBarAlpha, 0, 1);
		var shown:Float = Math.max(3, st.r * maxH);

		// 老老实实 setSize + 定位：setSize 里已经清掉 updateHitbox 的居中偏移。
		// （试过 origin 贴底 + scale 那套，柱子会被画到别的地方去，不如这样直白可靠。）
		setSize(bar, maxW, shown);
		bar.setPosition(centerX - maxW / 2, baseY - shown - st.slide * shown);
		bar.alpha = mul * st.a;
	}

	/**
	 * 预览与游戏内共用同一套取值入口，刷完看到的就是实机效果。
	 *
	 * ★ 结构（键位/统计块的 sprite）只在**第一次**建；之后改颜色一律走 applyColors()，
	 *   绝不再重建 —— 切主题时重建会把界面搞花（用户反馈"设置样式全崩了"）。
	 */
	function refreshPreviews():Void
	{
		if (!previewsBuilt)
		{
			previewsBuilt = true;
			ClientPrefs.previewUseDefault = true;
			defViewer.refresh();
			defViewer.antialiasing = ClientPrefs.data.antialiasing;
			ClientPrefs.previewUseDefault = false;

			cusViewer.refresh();
			cusViewer.antialiasing = ClientPrefs.data.antialiasing;
			for (k in cusViewer.keyAlphas) k.idleAlpha = 0.5;

			layoutPreviews();
			layoutDefaultPane();
			return;
		}

		cusViewer.applyColors();
		ClientPrefs.previewUseDefault = true;
		defViewer.applyColors();
		ClientPrefs.previewUseDefault = false;
	}

	/** 「默认样式」面板：和取色盘同一块区域（左区底部），二选一显示 */
	function layoutDefaultPane():Void
	{
		var paneX:Float = 22;
		var paneW:Float = leftW - 44;
		var y:Float = bodyH - PICK_H - 8;

		resizeBox(defBox, paneX, y, paneW, PICK_H);
		defHead.setPosition(paneX + 18, y + 13);
		defTag.setPosition(paneX + 88, y + 14);

		var availW:Float = paneW - 64;
		defScale = Math.min(1, availW / Math.max(1, defViewer._width));
		defViewer.scale.set(defScale, defScale);
		var ch:Float = defViewer._height * defScale;
		defViewer.setPosition(paneX + (paneW - defViewer._width * defScale) / 2,
			y + 46 + Math.max(0, (PICK_H - 46 - ch) / 2));
	}

	function setDefPaneVisible(v:Bool):Void
	{
		defViewer.visible = v;
		defBox.border.visible = v;
		defBox.fill.visible = v;
		defHead.visible = v;
		defTag.visible = v;
	}

	/** 把淡入进度套到当前那块面板上（自己推，不用 FlxTween —— 省得销毁时留尾巴） */
	function applyPaneFade():Void
	{
		var f:Float = paneFade;
		if (pickOpen)
		{
			pickGroup.alpha = f;
			return;
		}
		defViewer.alpha = f;
		defBox.border.alpha = f;
		defBox.fill.alpha = 0.55 * f;
		defHead.alpha = f;
		defTag.alpha = f;
	}

	function buildTriCard():Void
	{
		triBG = makeBox(200, 160, C_CARD, C_LINE);
		triTitle = mkTxt(0, 0, 300, '', 12.5, C_INK3);

		var names:Array<String> = [
			t('kv_state_normal', '常态', 'Idle'),
			t('kv_state_press', '被按下', 'Pressed'),
			t('kv_state_bar', '长条', 'Bar')
		];
		triCaps = [];
		for (n in names) triCaps.push(mkTxt(0, 0, 180, n, 11, C_INK3));

		triKeyBG = new FlxSprite(0, 0).loadGraphic(keyTex);
		triKeyBG.offset.set(0, 0);
		triKeyBG.origin.set(0, 0);
		triKeyBG.scrollFactor.set();
		triParts.push(triKeyBG);
		add(triKeyBG);
		triKeyTxt = mkTxt(0, 0, 140, '', 18, C_INK);
		triPressBG = new FlxSprite(0, 0).loadGraphic(pressTex);
		triPressBG.offset.set(0, 0);
		triPressBG.origin.set(0, 0);
		triPressBG.scrollFactor.set();
		triParts.push(triPressBG);
		add(triPressBG);
		triPressTxt = mkTxt(0, 0, 140, '', 18, C_INK);
		triBarBase = newSprite();
		triBarBase.color = 0xFF3A4459;
		// 长条用真贴图（顶部柔边，跟实机 DisBitmap 同款），不能拿纯色块糊弄
		triBar = new FlxSprite(0, 0).loadGraphic(barTexFade);
		triBar.offset.set(0, 0);
		triBar.origin.set(0, 0);
		triBar.scrollFactor.set();
		triParts.push(triBar);
		add(triBar);
		triBarMeta = mkTxt(0, 0, 200, '', 11.5, C_INK3);
	}

	function layoutTriCard():Void
	{
		var boxW:Float = leftW - 44;
		var want:Float = 84 + cusViewer._height * cusScale + 28;
		var top:Float = Math.min(want, bodyH - PICK_H - 180);
		if (top > bodyH - PICK_H - 180) top = bodyH - PICK_H - 180;
		if (top < 210) top = 210;

		triTop = top;
		resizeBox(triBG, 22, top, boxW, 160);
		triTitle.setPosition(38, top + 12);
		triTitle.fieldWidth = boxW - 40;
		triTitle.text = (zh() ? '当前编辑目标: ' : 'Editing: ') + shortName(target)
			+ (zh() ? '  三种形态的实时效果' : '  - three live states');

		var cellW:Float = (boxW - 24) / 3;
		/* ★ FlxText 的 width 就是 fieldWidth（构造时传的那个值），默认还是左对齐 ——
		   所以"居中"必须靠 alignment + fieldWidth 自己做，不能拿 x = cx - width/2 硬算，
		   那样文字会跑到框的左边缘（上一版三态卡里的字全是歪的，就是这条）。 */
		for (i in 0...3)
		{
			triCaps[i].fieldWidth = cellW;
			triCaps[i].alignment = CENTER;
			triCaps[i].setPosition(22 + 8 + cellW * i, top + 42);
		}
	}

	function updateTriCard():Void
	{
		if (triBG == null) return;

		var boxW:Float = leftW - 44;
		var top:Float = triTop;
		var cellW:Float = (boxW - 24) / 3;
		var name:String = shortName(target);

		var cx0:Float = 22 + 8 + cellW / 2;
		var cx1:Float = 22 + 8 + cellW + cellW / 2;
		var maxH:Float = barMaxHeight();

		var size:Float = 68;
		var normal:FlxColor = laneColor(target);
		var textC:FlxColor = keyTextColor(target);
		var press:FlxColor = pressColor(target);
		var pressT:FlxColor = pressTextColor(target);
		var a:Float = ClientPrefs.data.keyboardAlpha;

		// ---- 常态：底色 = 键盘底色与常态色的混合，观感与实机 KeyButton 一致 ----
		triKeyBG.color = normal;
		triKeyBG.alpha = FlxMath.bound(0.8 * a, 0, 1);
		setSize(triKeyBG, size, size);
		triKeyBG.setPosition(cx0 - size / 2, top + 66);
		triKeyTxt.text = name;
		triKeyTxt.color = textC;
		triKeyTxt.fieldWidth = size;
		triKeyTxt.alignment = CENTER;
		triKeyTxt.setPosition(cx0 - size / 2, top + 66 + size / 2 - triKeyTxt.height / 2);

		// ---- 被按下 ----
		triPressBG.color = press;
		triPressBG.alpha = FlxMath.bound(ClientPrefs.data.keyboardPressedAlpha, 0, 1);
		setSize(triPressBG, size, size);
		triPressBG.setPosition(cx1 - size / 2, top + 66);
		triPressTxt.text = name;
		triPressTxt.color = pressT;
		triPressTxt.fieldWidth = size;
		triPressTxt.alignment = CENTER;
		triPressTxt.setPosition(cx1 - size / 2, top + 66 + size / 2 - triPressTxt.height / 2);

		// ---- 长条：位置/高度/透明由 updateBarVisual() 每帧推进（循环演示消隐） ----
		setSize(triBarBase, cellW - 40, 2);
		triBarBase.setPosition(22 + 8 + cellW * 2 + 20, top + 154);

		triBarMeta.visible = true;
		triBarMeta.text = ClientPrefs.data.keyboardTimeDisplay
			? (Std.int(maxH) + 'px   ' + Math.round(ClientPrefs.data.keyboardBarAlpha * 100) + '%')
			: t('kv_bar_off', '长条已关闭', 'bars off');
		triBarMeta.fieldWidth = cellW;
		triBarMeta.alignment = CENTER;
		triBarMeta.setPosition(22 + 8 + cellW * 2, top + 158);


	}

	/**
	 * 统一改尺寸。
	 *
	 * ★ 改完必须把 offset / origin 清回 0：flixel 5.9 的 `updateHitbox()` 会把它们设成
	 *   "居中偏移"（`-0.5 * (width - frameWidth)`）。我们的底衬都是 1×1 白图靠 scale 撑开的，
	 *   放大到几百像素后 offset 就是负几百 —— 绘制时会 `x - offset`，精灵直接被推出屏幕，
	 *   表现就是"文字都在、方块一个也看不见"。三态卡和取色盘集体消失就是这个原因。
	 */
	function setSize(s:FlxSprite, w:Float, h:Float):Void
	{
		s.setGraphicSize(Std.int(Math.max(1, w)), Std.int(Math.max(1, h)));
		s.updateHitbox();
		s.offset.set(0, 0);
		s.origin.set(0, 0);
	}

	/** 三态卡的可见性（统计块没有"被按下"和"长条"两种形态） */
	function setTriVisible(v:Bool):Void
	{
		triShown = v;
		for (s in triParts) s.visible = v;
		triBG.border.visible = v;
		triBG.fill.visible = v;
		triTitle.visible = v;
		for (c in triCaps) c.visible = v;
		triKeyTxt.visible = v;
		triPressTxt.visible = v;
		triBarBase.visible = v;
		triBarMeta.visible = v;
		if (!v) triBar.visible = false;
	}
	/** 指向当前编辑目标的自绘三角 */
	function updateArrow():Void
	{
		if (arrowSpr == null || cusViewer == null) return;
		arrowSpr.visible = false;

		if (isStat())
		{
			var i:Int = target - 10;
			if (i < 0 || i >= cusViewer.statBlocks.length) return;
			var blk:FlxSprite = cusViewer.statBlocks[i];
			if (blk == null || !blk.visible) return;
			arrowSpr.setPosition(blk.x + (blk.width * cusScale - arrowSpr.width) / 2, blk.y - 22);
			arrowSpr.visible = true;
			return;
		}

		if (target < 0 || target >= cusViewer.keyButtons.length) return;
		var btn:FlxSprite = cusViewer.keyButtons[target];
		if (btn == null) return;
		arrowSpr.setPosition(btn.x + (btn.width * cusScale - arrowSpr.width) / 2, btn.y - 22);
		arrowSpr.visible = true;
	}

	// =====================================================================
	// 右区：分区 + 行列表
	// =====================================================================

	function buildRight():Void
	{
		var bg:FlxSprite = new FlxSprite(rightX, 0).makeGraphic(Math.floor(rightW), Math.floor(H), 0xFF121214);
		bg.alpha = 0.62;
		bg.scrollFactor.set();
		add(bg);

		var div:FlxSprite = new FlxSprite(leftW, 0).makeGraphic(4, FlxG.height, 0xFF3A4A6B);
		div.scrollFactor.set();
		add(div);

		var tabW:Float = (contentW - 8) / 4;
		tabInd = newSprite();
		tabInd.color = C_ACC;
		tabInd.alpha = 0.30;

		for (i in 0...4)
		{
			var b:KVBox = makeBox(Std.int(tabW), TAB_H, 0x0D1119, C_LINE);
			boxPos(b, contentX + (tabW + 2.6) * i, 12);
			tabBoxes.push(b);
			var tx:FlxText = mkTxt(contentX + (tabW + 2.6) * i, 12 + (TAB_H - 18) / 2, tabW, zh() ? TAB_ZH[i] : TAB_EN[i], 14, C_INK3);
			tx.alignment = CENTER;
			tabTxts.push(tx);
		}

		for (i in 0...SLOTS)
		{
			rBack.push(newSprite());
			// 分组标题的底条要先于文字创建，否则会盖在字上面
			rGroupLine.push(newSprite());
			rGroupLine[i].color = 0x14141A;
			rGroupHead.push(mkTxt(0, 0, 400, '', 11.5, C_INK2));
			rName.push(mkTxt(0, 0, NAME_W - 10, '', 13, C_INK2));
			rFillBG.push(newSprite());
			rFillBG[i].color = 0xFF232B3A;
			rFill.push(newSprite());
			rFill[i].color = C_ACC;
			rKnob.push(newSprite());
			rKnob[i].color = 0xFFFFFFFF;
			rSwBG.push(newSprite());
			rSwBG[i].color = 0xFF2A3346;
			rChip.push(newSprite());
			rVal.push(mkTxt(0, 0, 200, '', 12.5, C_INK));
			rMinus.push(mkTxt(0, 0, 30, '−', 20, C_INK2));
			rPlus.push(mkTxt(0, 0, 30, '+', 18, C_INK2));
			rSegBG.push(newSprite());
			rSegBG[i].color = 0x0D1119;
			for (j in 0...SEGMAX)
			{
				var s:FlxText = mkTxt(0, 0, 60, '', 11.5, C_INK3);
				s.alignment = CENTER;
				rSegTxt.push(s);
			}
			rReset.push(mkTxt(0, 0, 30, '↺', 17, C_INK3));
		}

		rPrevBox = newSprite();
		rPrevBox.color = 0x14141A;
		rPrevBar = new FlxSprite(0, 0).loadGraphic(barTexFade);
		rPrevBar.offset.set(0, 0);
		rPrevBar.origin.set(0, 0);
		rPrevBar.scrollFactor.set();
		add(rPrevBar);
		rPrevBase = newSprite();
		rPrevBase.color = 0xFF3A4459;
		rPrevMeta = mkTxt(0, 0, 300, '', 12, C_INK3);

		// ★ 不再做滚动：取色盘搬去左区后，右区列表一屏能放得下全部设置项
		//   （用户明确要求去掉界面里的滚动）。控件留着但不显示，免得空引用。
		scrollUp = makeBox(0, 0, 0x0D1119, C_LINE);
		scrollUpTxt = mkTxt(0, 0, 0, '', 11, C_INK3);
		scrollDown = makeBox(0, 0, 0x0D1119, C_LINE);
		scrollDownTxt = mkTxt(0, 0, 0, '', 11, C_INK3);
		scrollBarBG = newSprite();
		scrollBar = newSprite();
		for (o in [scrollUp.border, scrollUp.fill, scrollUpTxt, scrollDown.border, scrollDown.fill, scrollDownTxt, scrollBarBG, scrollBar])
			o.visible = false;

		syncTabVisual();
	}

	function syncTabVisual():Void
	{
		var tabW:Float = (contentW - 8) / 4;
		setSize(tabInd, tabW - 4, TAB_H - 4);
		tabInd.setPosition(contentX + (tabW + 2.6) * tab + 2, 14);

		for (i in 0...4)
		{
			var on:Bool = (i == tab);
			tabTxts[i].color = on ? 0xFFFFFFFF : C_INK3;
			boxColors(tabBoxes[i], on ? 0x1B263C : 0x0D1119, on ? 0x5E86C8 : C_LINE);
		}
	}

	// ---------------------------------------------------------------------
	// 行定义（id 用来做稳定的重置匹配，别用会随语言变的 label）
	// ---------------------------------------------------------------------

	inline function num(id:String, label:String, get:Void->Dynamic, set:Dynamic->Void, min:Float, max:Float, step:Float, dec:Int, unit:String,
			?tip:String):KVRow
		return {id: id, label: label, kind: 'num', get: get, set: set, min: min, max: max, step: step, dec: dec, unit: unit, tip: tip};

	inline function bool(id:String, label:String, get:Void->Dynamic, set:Dynamic->Void, ?tip:String):KVRow
		return {id: id, label: label, kind: 'bool', get: get, set: set, tip: tip};

	inline function color(id:String, label:String, get:Void->Dynamic, set:Dynamic->Void, ?tip:String):KVRow
		return {id: id, label: label, kind: 'color', get: get, set: set, tip: tip};

	inline function seg(id:String, label:String, get:Void->Dynamic, set:Dynamic->Void, opts:Array<String>, labels:Array<String>,
			?tip:String):KVRow
		return {id: id, label: label, kind: 'seg', get: get, set: set, opts: opts, optLabels: labels, tip: tip};

	inline function act(id:String, label:String, fn:Void->Void):KVRow
		return {id: id, label: label, kind: 'act', get: function() return '', set: function(_) {}, onAct: fn};

	inline function grp(label:String):KVRow
		return {id: '', label: label, kind: 'group', get: function() return '', set: function(_) {}};

	inline function prev(id:String, label:String):KVRow
		return {id: id, label: label, kind: 'prev', get: function() return '', set: function(_) {}};

	function rowsForTab(which:Int):Array<KVRow>
	{
		var k:Int = target;

		if (which == 0) // 颜色
		{
			return [
				grp(t('kv_g_overall', '整体', 'Overall')),
				num('alpha', t('kv_alpha', '透明度', 'Opacity'),
					function() return ClientPrefs.data.keyboardAlpha,
					function(v) { ClientPrefs.data.keyboardAlpha = boundF(v, 0, 1); markCustom(); },
					0, 1, 0.01, 0, '%',
					t('kv_alpha_tip', '整块键盘反馈的透明度；填充与描边都按它缩放', 'Opacity of the whole overlay')),
				grp(t('kv_g_normal', '常态', 'Idle')),
				color('cNormal', t('kv_c_normal', '常态颜色', 'Idle color'),
					function() return getColorRaw(k, 'normal'),
					function(v) setColorRaw(k, 'normal', Std.string(v))),
				color('cBorder', t('kv_c_border', '描边颜色', 'Border color'),
					function() return getColorRaw(k, 'border'),
					function(v) setColorRaw(k, 'border', Std.string(v)),
					t('kv_c_border_tip', '空 = 跟随常态色（旧版观感）', 'Empty = follow idle color')),
				color('cNormalText', t('kv_c_normal_text', '常态文本颜色', 'Idle text color'),
					function() return getColorRaw(k, 'normalText'),
					function(v) setColorRaw(k, 'normalText', Std.string(v))),
				grp(t('kv_g_press', '按下', 'Pressed')),
				color('cPress', t('kv_c_press', '按下颜色', 'Pressed color'),
					function() return getColorRaw(k, 'press'),
					function(v) setColorRaw(k, 'press', Std.string(v)),
					isStat() ? t('kv_stat_only_normal', '统计块只使用「常态颜色」与「常态文本颜色」', 'Stats only use idle colors') : null),
				color('cPressText', t('kv_c_press_text', '按下文本颜色', 'Pressed text color'),
					function() return getColorRaw(k, 'pressText'),
					function(v) setColorRaw(k, 'pressText', Std.string(v)),
					isStat() ? t('kv_stat_only_normal', '统计块只使用「常态颜色」与「常态文本颜色」', 'Stats only use idle colors') : null),
				grp(t('kv_g_bar', '长条', 'Bar')),
				color('cBar', t('kv_c_bar', '长条颜色', 'Bar color'),
					function() return getColorRaw(k, 'bar'),
					function(v) setColorRaw(k, 'bar', Std.string(v)),
					isBarFollowNormal() ? t('kv_bar_color_off', '取色来源当前是「跟随常态色」，此项不生效', 'Ignored while source = idle color') : null),
				seg('barSrc', t('kv_c_bar_src', '取色来源', 'Bar source'),
					function() return ClientPrefs.data.keyboardBarColorMode,
					function(v) { ClientPrefs.data.keyboardBarColorMode = Std.string(v); markCustom(); },
					['Custom', 'Key'],
					[t('kv_src_custom', '用长条颜色', 'Custom'), t('kv_src_key', '跟随常态色', 'Follow idle')],
					t('kv_bar_src_tip', '选「跟随常态色」时上面的长条颜色不生效', 'The bar color above is ignored when following idle'))
			];
		}

		if (which == 1) // 长条
		{
			return [
				prev('barPrev', t('kv_live_bar', '长条预览', 'Live preview')),
				grp(t('kv_g_show', '显示', 'Show')),
				bool('barOn', t('kv_bar_on', '显示长条', 'Show bars'),
					function() return ClientPrefs.data.keyboardTimeDisplay,
					function(v) { ClientPrefs.data.keyboardTimeDisplay = (v == true); markCustom(); },
					t('kv_bar_on_tip', '长条参数是整块键盘反馈共用的，与当前编辑目标无关', 'Bar settings are global')),
				num('barAlpha', t('kv_bar_alpha', '长条透明度', 'Bar opacity'),
					function() return ClientPrefs.data.keyboardBarAlpha,
					function(v) { ClientPrefs.data.keyboardBarAlpha = boundF(v, 0, 1); markCustom(); },
					0, 1, 0.01, 0, '%'),
				grp(t('kv_g_shape', '形态与消失', 'Shape & vanish')),
				num('barMax', t('kv_bar_max', '最多显示高度', 'Max height'),
					function() return barMaxHeight(),
					function(v) { ClientPrefs.data.keyboardBarHeight = Std.int(boundF(v, 20, 400)); markCustom(); },
					20, 400, 5, 0, 'px'),
				num('barSpeed', t('kv_bar_speed', '速度', 'Speed'),
					function() return ClientPrefs.data.keyboardBarSpeed,
					function(v) { ClientPrefs.data.keyboardBarSpeed = boundF(v, 0.1, 5); markCustom(); },
					0.1, 5, 0.1, 1, '×'),
				num('barStay', t('kv_bar_stay', '滞留时间', 'Hold time'),
					function() return ClientPrefs.data.keyboardTime,
					function(v) { ClientPrefs.data.keyboardTime = boundF(v, 50, 2000); markCustom(); },
					50, 2000, 50, 0, 'ms')
			];
		}

		if (which == 2) // 统计
		{
			return [
				grp(t('kv_g_stats', '统计区（KPS 与 total 一起变）', 'Stats block (KPS & total change together)')),
				bool('showStats', t('kv_stats_on', '显示统计', 'Show stats'),
					function() return ClientPrefs.data.keyboardStats,
					function(v) { ClientPrefs.data.keyboardStats = (v == true); markCustom(); }),
				num('statAlpha', t('kv_stat_a', '统计区透明度', 'Stat opacity'),
					function() return ClientPrefs.data.keyboardStatAlpha,
					function(v) { ClientPrefs.data.keyboardStatAlpha = boundF(v, 0, 1); markCustom(); },
					0, 1, 0.01, 0, '%')
			];
		}

		// 主题
		return [
			grp(t('kv_g_color_src', '配色来源', 'Color source')),
			bool('followSong', t('kv_follow_song', '跟随谱面 RGB 音符配色', 'Follow song RGB note colors'),
				function() return ClientPrefs.data.keyboardFollowNoteColor,
				function(v) { ClientPrefs.data.keyboardFollowNoteColor = (v == true); markCustom(); },
				t('kv_follow_tip', '开启后每个按键取所在音符的颜色', 'Each key takes its note color')),
			seg('theme', t('kv_theme', '主题', 'Theme'),
				function() return ClientPrefs.data.keyboardTheme,
				function(v) applyTheme(Std.string(v)),
				THEME_KEYS, zh() ? THEME_ZH : THEME_EN,
				t('kv_theme_tip', '选主题会一次性套用整套配色；之后改动任何一项都会回到「自定义」', 'Picking a theme applies a full palette; any edit falls back to Custom')),
			grp(t('kv_g_transfer', '迁移', 'Transfer')),
			act('doExport', t('kv_export', '导出为 JSON 文件', 'Export to JSON'), function() exportJson()),
			act('doImport', t('kv_import', '从 JSON 文件导入', 'Import from JSON'), function() importJson())
		];
	}

	// ---------------------------------------------------------------------
	// 行渲染
	// ---------------------------------------------------------------------

	function switchTab(which:Int, ?force:Bool = false):Void
	{
		if (!force && which == tab) return;
		tab = which;
		rows = rowsForTab(tab);
		scrollFrom = 0;
		selected = firstSelectable();
		// 颜色分区要把取色抽屉让出来，可视行数因此少一些
		maxVisible = (tab == 0) ? 7 : 10;
		syncTabVisual();
		renderRows();
	}

	function firstSelectable():Int
	{
		for (i in 0...rows.length)
			if (rows[i].kind == 'color') return i;
		for (i in 0...rows.length)
			if (rows[i].kind != 'group' && rows[i].kind != 'prev') return i;
		return 0;
	}

	function renderRows():Void
	{
		for (i in 0...SLOTS) hideSlot(i);
		rPrevBox.visible = false;
		rPrevBar.visible = false;
		rPrevBase.visible = false;
		rPrevMeta.visible = false;
		rowY = [];
		prevRowH = 0; // 离开「长条」分区后别让那根预览条留在原地

		/* ★ 列表下边界按**像素**算，不能只按"最多几行"数：
		   分组标题也占高度，只数行的话最后两行会掉到屏幕外 / 被别的东西压住。 */
		var listBottom:Float = bodyH - 10;

		var slot:Int = 0;
		var y:Float = listTop;

		for (ri in 0...rows.length)
		{
			var r:KVRow = rows[ri];
			var h:Float = (r.kind == 'group') ? CARD_H : (r.kind == 'prev' ? PREV_H : ROW_H);
			var gap:Float = rowGapAfter(ri);

			if (ri < scrollFrom || y + h > listBottom)
			{
				rowY.push(-1);
				y += h + gap;
				continue;
			}

			rowY.push(y);

			if (r.kind == 'group')
			{
				if (slot < SLOTS)
				{
					// 分组标题画成一条暗色带 + 标题字，否则它在深色底上看起来就是"一片空白"
					rGroupLine[slot].visible = true;
					setSize(rGroupLine[slot], contentW, CARD_H - 6);
					rGroupLine[slot].setPosition(contentX, y + 3);
					rGroupLine[slot].alpha = 0.55;
					rGroupHead[slot].visible = true;
					rGroupHead[slot].text = r.label.toUpperCase();
					rGroupHead[slot].setPosition(contentX + 10, y + 8);
					slot++;
				}
			}
			else if (r.kind == 'prev')
			{
				drawPrevRow(y, h);
			}
			else if (slot < SLOTS)
			{
				drawRow(slot, ri, r, y, h);
				slot++;
			}

			y += h + gap;
		}

		syncScrollUI();
		refreshPicker();
	}

	/** 列表内容总高度（只用来判断会不会溢出；溢出也只是截断，不再滚动） */
	function contentHeight():Float
	{
		var h:Float = 0;
		for (ri in 0...rows.length)
		{
			h += (rows[ri].kind == 'group') ? CARD_H : (rows[ri].kind == 'prev' ? PREV_H : ROW_H);
			h += rowGapAfter(ri);
		}
		return h;
	}

	inline function rowGapAfter(ri:Int):Float
		return (ri + 1 < rows.length && rows[ri + 1].kind != 'group') ? 4 : 0;

	function hideSlot(i:Int):Void
	{
		rBack[i].visible = false;
		rGroupHead[i].visible = false;
		rGroupLine[i].visible = false;
		rName[i].visible = false;
		rFill[i].visible = false;
		rFillBG[i].visible = false;
		rKnob[i].visible = false;
		rSwBG[i].visible = false;
		rChip[i].visible = false;
		rVal[i].visible = false;
		rMinus[i].visible = false;
		rPlus[i].visible = false;
		rSegBG[i].visible = false;
		rReset[i].visible = false;
		for (j in 0...SEGMAX) rSegTxt[i * SEGMAX + j].visible = false;
	}

	function drawRow(slot:Int, ri:Int, r:KVRow, y:Float, h:Float):Void
	{
		var sel:Bool = (ri == selected);
		var dimmed:Bool = (r.tip != null && (r.kind == 'color' || r.kind == 'seg') && isBarFollowNormal()
			&& (r.id == 'cBar' || r.id == 'barSrc'));

		rBack[slot].visible = true;
		setSize(rBack[slot], contentW, h);
		rBack[slot].setPosition(contentX, y);
		rBack[slot].color = sel ? 0x2A3550 : 0x16161A;
		rBack[slot].alpha = sel ? 0.92 : 0.55;

		rName[slot].visible = true;
		rName[slot].text = r.label;
		rName[slot].color = sel ? 0xFFFFFFFF : (dimmed ? C_DIM : C_INK2);
		rName[slot].setPosition(contentX + 12, y + (h - 18) / 2);

		rReset[slot].visible = true;
		rReset[slot].setPosition(contentX + contentW - 30, y + (h - 20) / 2);
		rReset[slot].color = sel ? C_WARN : C_INK3;

		var midY:Float = y + h / 2;

		switch (r.kind)
		{
			case 'num':
				var f:Float = toFloat(r.get());
				var t01:Float = (r.max > r.min) ? FlxMath.bound((f - r.min) / (r.max - r.min), 0, 1) : 0;

				rMinus[slot].visible = true;
				rMinus[slot].setPosition(ctlX + 2, y + (h - 26) / 2);
				rPlus[slot].visible = true;
				rPlus[slot].setPosition(ctlX + ctlW - 26, y + (h - 24) / 2);

				var trackX:Float = ctlX + 30;
				var trackW:Float = ctlW - 60;

				rFillBG[slot].visible = true;
				setSize(rFillBG[slot], trackW, 6);
				rFillBG[slot].setPosition(trackX, midY + 9);

				rFill[slot].visible = true;
				setSize(rFill[slot], Math.max(2, trackW * t01), 6);
				rFill[slot].setPosition(trackX, midY + 9);
				rFill[slot].color = C_ACC;

				rKnob[slot].visible = true;
				setSize(rKnob[slot], 12, 12);
				rKnob[slot].setPosition(trackX + trackW * t01 - 6, midY + 6);
				rKnob[slot].color = 0xFFFFFFFF;

				rVal[slot].visible = true;
				/* ★ 0..1 的系数（透明度那三项）必须按百分比显示：
				   它们的 max 是 1、单位是 %，如果按整数格式化，0.8 会四舍五入成 "1%"。
				   约定：unit == '%' 且 max == 1 → 百分比模式；statWidth 那种"值本身就是百分比"的不受影响。 */
				var isPct:Bool = (r.unit == '%' && r.max == 1);
				rVal[slot].text = isPct
					? (Math.round(f * 100) + '%')
					: (fmtNum(f, r.dec) + ((r.unit != null) ? r.unit : ''));
				rVal[slot].color = C_INK;
				rVal[slot].fieldWidth = trackW;
				rVal[slot].alignment = CENTER;
				rVal[slot].x = trackX;
				rVal[slot].y = midY - rVal[slot].height - 3;

			case 'bool':
				var on:Bool = (r.get() == true);
				rSwBG[slot].visible = true;
				setSize(rSwBG[slot], SW_W, SW_H);
				rSwBG[slot].setPosition(ctlX + ctlW - SW_W, midY - SW_H / 2);
				rSwBG[slot].color = on ? 0x3E68B8 : 0x2A3346;

				rKnob[slot].visible = true;
				setSize(rKnob[slot], 22, 22);
				rKnob[slot].setPosition(ctlX + ctlW - SW_W + (on ? SW_W - 25 : 3), midY - 11);
				rKnob[slot].color = on ? 0xFFFFFFFF : 0xFF8E99AB;

			case 'color':
				var raw:String = Std.string(r.get());
				var c:FlxColor = (raw == null || raw == '') ? FlxColor.WHITE : CoolUtil.colorFromString(raw);

				rChip[slot].visible = true;
				setSize(rChip[slot], 24, 24);
				rChip[slot].setPosition(ctlX + ctlW - 26, midY - 12);
				rChip[slot].color = c;

				rVal[slot].visible = true;
				/* ★ 显示"实际生效的色号"，不要显示"默认"：
				   空串只代表"没单独设过"，它仍然会回退到一个真实颜色（通常是 #FFFFFF）。
				   显示成"默认"会让人以为这里没有颜色输出（用户就是这么理解的）。 */
				rVal[slot].text = '#' + c.toHexString(false, false).toUpperCase();
				rVal[slot].color = dimmed ? C_DIM : C_INK;
				rVal[slot].fieldWidth = ctlW - 36;
				rVal[slot].alignment = RIGHT;
				rVal[slot].x = ctlX;
				rVal[slot].y = midY - 10;

			case 'seg':
				var opts:Array<String> = r.opts;
				var labels:Array<String> = r.optLabels;
				var curS:String = Std.string(r.get());
				var n:Int = opts.length;
				var bw:Float = (ctlW - (n - 1) * 4) / n;
				var bh:Float = 32;

				rSegBG[slot].visible = true;
				setSize(rSegBG[slot], ctlW, bh);
				rSegBG[slot].setPosition(ctlX, midY - bh / 2);
				rSegBG[slot].color = 0x0D1119;

				var ci:Int = opts.indexOf(curS);
				if (ci < 0) ci = 0;

				// 选中格的底衬先画（用 rChip 复用），文字后画才不会被盖住
				rChip[slot].visible = true;
				setSize(rChip[slot], bw, bh);
				rChip[slot].setPosition(ctlX + (bw + 4) * ci, midY - bh / 2);
				rChip[slot].color = 0x1B263C;

				for (j in 0...n)
				{
					var st:FlxText = rSegTxt[slot * SEGMAX + j];
					var on:Bool = (opts[j] == curS);
					st.visible = true;
					st.text = (labels != null && j < labels.length) ? labels[j] : opts[j];
					st.fieldWidth = bw;
					st.alignment = CENTER;
					st.color = on ? 0xFFFFFFFF : (dimmed ? C_DIM : C_INK3);
					st.setPosition(ctlX + (bw + 4) * j, midY - 9);
				}

			case 'act':
				rVal[slot].visible = true;
				rVal[slot].text = t('kv_do', '执行 ›', 'Run ›');
				rVal[slot].color = C_MARK;
				rVal[slot].fieldWidth = ctlW;
				rVal[slot].alignment = RIGHT;
				rVal[slot].x = ctlX;
				rVal[slot].y = midY - 10;

			default:
		}
	}

	function drawPrevRow(y:Float, h:Float):Void
	{
		prevRowY = y;
		prevRowH = h;

		rPrevBox.visible = true;
		setSize(rPrevBox, contentW, h - 8);
		rPrevBox.setPosition(contentX, y + 4);
		rPrevBox.color = 0x14141A;

		var bx:Float = contentX + 50;

		rPrevBase.visible = true;
		setSize(rPrevBase, 100, 2);
		rPrevBase.setPosition(bx - 50, y + 8 + h - 44);

		// 条本身的位置/高度交给 updateBarVisual() 每帧推进（循环演示消隐）
		rPrevBar.color = barLaneColor(target);
		rPrevBar.visible = ClientPrefs.data.keyboardTimeDisplay;

		rPrevMeta.visible = true;
		rPrevMeta.text = ClientPrefs.data.keyboardTimeDisplay
			? (Std.int(barMaxHeight()) + 'px   ' + Math.round(ClientPrefs.data.keyboardBarAlpha * 100) + '%')
			: t('kv_bar_off', '长条已关闭', 'bars off');
		rPrevMeta.setPosition(bx + 60, y + 8 + (h - 8) / 2 - 10);
	}

	function syncScrollUI():Void
	{
		// 用户要求去掉滚动：所有滚动控件永久隐藏
		for (o in [scrollUp.border, scrollUp.fill, scrollUpTxt, scrollDown.border, scrollDown.fill, scrollDownTxt, scrollBarBG, scrollBar])
			o.visible = false;
		return;

		/* eslint-disable no-unreachable */
		var total:Int = rows.length;
		var overflow:Bool = total > maxVisible;

		for (o in [scrollUp.border, scrollUp.fill, scrollUpTxt, scrollDown.border, scrollDown.fill, scrollDownTxt, scrollBarBG, scrollBar])
			o.visible = overflow;
		if (!overflow) return;

		var bx:Float = contentX + contentW + 6;
		boxPos(scrollUp, bx, listTop);
		scrollUpTxt.setPosition(bx, listTop + 9);

		var downY:Float = listTop + maxVisible * ROW_H - 34;
		boxPos(scrollDown, bx, downY);
		scrollDownTxt.setPosition(bx, downY + 9);

		var trackY:Float = listTop + 36;
		var trackH:Float = Math.max(40, maxVisible * ROW_H - 76);
		scrollBarBG.setGraphicSize(4, Std.int(trackH));
		scrollBarBG.updateHitbox();
		scrollBarBG.setPosition(bx + 13, trackY);

		var barH:Float = Math.max(24, trackH * (maxVisible / total));
		var maxFrom:Int = Std.int(Math.max(1, total - maxVisible));
		var prog:Float = (maxFrom > 0) ? (scrollFrom / maxFrom) : 0;
		scrollBar.setGraphicSize(4, Std.int(barH));
		scrollBar.updateHitbox();
		scrollBar.setPosition(bx + 13, trackY + (trackH - barH) * prog);
	}

	// =====================================================================
	// 取色抽屉（浮层）
	// =====================================================================

	function buildPicker():Void
	{
		pickGroup = new FlxSpriteGroup();
		add(pickGroup);

		pickBG = makeBox(contentW, PICK_H, 0x121218, 0xFF4A4A58, pickGroup);
		pickBG.fill.alpha = 0.94;

		pickTitle = mkTxt(0, 0, 340, '', 12.5, C_INK2, false, pickGroup);

		var gradW:Float = 18;
		var wheel:Float = 132;

		colorGradient = FlxGradient.createGradientFlxSprite(Std.int(gradW), Std.int(wheel), [FlxColor.WHITE, FlxColor.BLACK]);
		colorGradient.scrollFactor.set();
		pickGroup.add(colorGradient);

		colorGradSel = newSprite(pickGroup);
		colorGradSel.color = 0xFFFFFFFF;

		colorWheel = new FlxSprite(0, 0).loadGraphic(Paths.image('noteColorMenu/colorWheel'));
		colorWheel.setGraphicSize(Std.int(wheel), Std.int(wheel));
		colorWheel.updateHitbox();
		colorWheel.offset.set(0, 0);   // 同 setSize：不清掉居中偏移，色轮会整个偏出去
		colorWheel.origin.set(0, 0);
		colorWheel.scrollFactor.set();
		pickGroup.add(colorWheel);

		colorWheelSel = new FlxShapeCircle(0, 0, 11, {thickness: 0}, FlxColor.WHITE);
		colorWheelSel.offset.set(11, 11);
		colorWheelSel.alpha = 0.9;
		pickGroup.add(colorWheelSel);

		var palGraphic = Paths.image('noteColorMenu/palette', false);
		palBitmap = palGraphic.bitmap;
		colorPalette = new FlxSprite(0, 0).loadGraphic(palGraphic);
		colorPalette.antialiasing = false;
		colorPalette.offset.set(0, 0);
		colorPalette.origin.set(0, 0);
		colorPalette.scrollFactor.set();
		pickGroup.add(colorPalette);

		curSwatch = newSprite(pickGroup);

		hexInput = new FlxUIInputText(0, 0, 120, '', 22);
		hexInput.customFilterPattern = ~/[^0-9a-fA-F]/g;
		hexInput.filterMode = 4;
		hexInput.forceCase = 2;
		hexInput.maxLength = 6;
		hexInput.backgroundColor = 0xFF0D1016;
		hexInput.fieldBorderColor = 0xFF4A5468;
		hexInput.fieldBorderThickness = 2;
		hexInput.color = 0xFFF2F6FC;
		hexInput.caretColor = 0xFFF2F6FC;
		hexInput.wordWrap = false;
		hexInput.font = Paths.font(Language.get('fontName', 'main') + '.ttf');
		pickGroup.add(hexInput);

		rgbText = mkTxt(0, 0, 300, '', 12, C_INK3, false, pickGroup);
	}

	function layoutPicker():Void
	{
		/* ★ 取色盘挂在**左区底部** —— 那里原本是"默认样式"预览的位置，已撤掉。
		   之前它作为浮层盖在右区设置列表上，把下面几行设置项全挡住了（用户反馈）。 */
		var paneX:Float = 22;
		var paneW:Float = leftW - 44;
		var y:Float = bodyH - PICK_H - 8;

		var gradW:Float = 18;
		var wheel:Float = 132;
		var gradX:Float = paneX + 18;
		var wheelX:Float = gradX + gradW + 14;
		var rx:Float = wheelX + wheel + 18;
		var rw:Float = paneX + paneW - rx - 18;
		var top:Float = y + 40;

		resizeBox(pickBG, paneX, y, paneW, PICK_H);
		pickTitle.setPosition(paneX + 18, y + 13);
		pickTitle.fieldWidth = paneW - 36;

		colorGradient.setPosition(gradX, top);
		setSize(colorGradSel, gradW + 12, 5);
		colorWheel.setPosition(wheelX, top);
		colorPalette.setPosition(rx, top);
		colorPalette.setGraphicSize(Std.int(rw), Std.int(wheel));
		colorPalette.updateHitbox();
		colorPalette.offset.set(0, 0);
		colorPalette.origin.set(0, 0);

		setSize(curSwatch, rw * 0.26, 30);
		curSwatch.setPosition(rx, top + wheel + 13);
		hexInput.setPosition(Std.int(rx + rw * 0.30), top + wheel + 13);
		hexInput.fieldWidth = Std.int(rw * 0.28);
		rgbText.setPosition(rx + rw * 0.30, top + wheel + 42);
		rgbText.fieldWidth = Std.int(rw * 0.6);
	}

	function refreshPicker():Void
	{
		var r:KVRow = currentRow();
		var wasOpen:Bool = pickOpen;
		pickOpen = (r != null && r.kind == 'color');
		pickGroup.visible = pickOpen;
		// 没在调颜色的时候，把「默认样式」对照拉回来占这块位置（两者共用左区底部）
		setDefPaneVisible(!pickOpen);
		if (wasOpen != pickOpen) paneFade = 0; // 换面板时重放一次淡入
		if (!pickOpen)
		{
			layoutDefaultPane();
			return;
		}
		layoutPicker();
		syncPicker();
	}

	function currentRow():KVRow
	{
		if (selected < 0 || selected >= rows.length) return null;
		return rows[selected];
	}

	function syncPicker():Void
	{
		var r:KVRow = currentRow();
		if (r == null || r.kind != 'color') return;

		var raw:String = Std.string(r.get());
		var c:FlxColor = (raw == null || raw == '') ? FlxColor.WHITE : CoolUtil.colorFromString(raw);

		pickTitle.text = shortName(target) + '  /  ' + r.label
			+ (isStat() && r.id != 'cNormal' && r.id != 'cNormalText'
				? t('kv_stat_hint', '   （统计块只吃常态颜色/文本色）', '  (stats use idle colors only)') : '');

		curSwatch.color = c;
		rgbText.text = 'R ' + c.red + '   G ' + c.green + '   B ' + c.blue;
		if (!hexInput.hasFocus) hexInput.text = c.toHexString(false, false).toUpperCase();

		/* ★ 选中圈按「色相角 + 饱和度」定位，角度换算必须与取色时互为逆运算：
		   取色用 hue = wrap(atan2(my-cy, mx-cx) + 90)，反算时用 (hue - 90) 才能对上；
		   写成 (hue + 90) 圈会跑到对角线上去（用户实测"小圆圈位置不对"就是这条）。 */
		var cx:Float = colorWheel.x + colorWheel.width / 2;
		var cy:Float = colorWheel.y + colorWheel.height / 2;
		var rad:Float = (colorWheel.width / 2) * FlxMath.bound(c.saturation, 0, 1);
		var deg:Float = (c.hue - 90) * Math.PI / 180;
		colorWheelSel.setPosition(cx + Math.cos(deg) * rad - 11, cy + Math.sin(deg) * rad - 11);

		colorGradSel.setPosition(colorGradient.x - 6,
			colorGradient.y + (1 - FlxMath.bound(c.brightness, 0, 1)) * colorGradient.height - 2);
	}

	function pushColor(c:FlxColor):Void
	{
		var r:KVRow = currentRow();
		if (r == null || r.kind != 'color') return;
		r.set('#' + c.toHexString(false, false).toUpperCase());
		syncPicker();
		afterEdit();
	}

	// =====================================================================
	// 底部
	// =====================================================================

	function buildFooter():Void
	{
		var fy:Float = bodyH;
		var bg:FlxSprite = new FlxSprite(0, fy).makeGraphic(FlxG.width, Math.floor(FOOT_H), 0xFF0C0C0E);
		bg.alpha = 0.74;
		bg.scrollFactor.set();
		add(bg);

		var line:FlxSprite = new FlxSprite(0, fy).makeGraphic(FlxG.width, 1, C_LINE);
		line.scrollFactor.set();
		add(line);

		whereTxt = mkTxt(22, fy + (FOOT_H - 18) / 2, 340, '', 13, C_INK3);

		var bw:Float = 236;
		var gap:Float = 24;
		var bx:Float = (W - (bw * 2 + gap)) / 2;
		var by:Float = fy + (FOOT_H - BTN_H) / 2;

		resetAllBox = makeBox(Std.int(bw), Std.int(BTN_H), 0x1A1F2B, C_LINE);
		boxPos(resetAllBox, bx, by);
		resetAllTxt = mkTxt(bx, by + (BTN_H - 18) / 2, bw, t('kv_reset_all', '恢复默认设置', 'Reset all'), 14, C_INK2);
		resetAllTxt.alignment = CENTER;

		saveBox = makeBox(Std.int(bw), Std.int(BTN_H), 0x3E68B8, 0x7FB0FF);
		boxPos(saveBox, bx + bw + gap, by);
		saveTxt = mkTxt(bx + bw + gap, by + (BTN_H - 18) / 2, bw, t('kv_save_exit', '保存并退出', 'Save & exit'), 14, 0xFFFFFFFF);
		saveTxt.alignment = CENTER;

		toastTxt = mkTxt(0, 0, W, '', 14, 0xFFFFFFFF);
		toastTxt.alignment = CENTER;
		toastTxt.visible = false;
	}

	function toast(msg:String):Void
	{
		toastTxt.text = msg;
		toastTxt.y = bodyH - 120;
		toastTxt.visible = true;
		toastTime = 1.8;
	}

	function updateWhere():Void
	{
		whereTxt.text = (zh() ? '正在编辑: ' : 'Editing: ') + shortName(target)
			+ (isStat() ? (zh() ? '（统计块）' : ' (stat)') : (zh() ? ' 键' : ' key'));
	}

	// =====================================================================
	// 主循环
	// =====================================================================

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (toastTime > 0)
		{
			toastTime -= elapsed;
			if (toastTime <= 0) toastTxt.visible = false;
		}

		handleHexInput();
		handleTabs();
		handlePreviews();
		handleList();
		handleDrag();
		handlePicker();
		handleFooter();

		updateBarAnim(elapsed);
		updateBarVisual();

		if (paneFade < 1)
		{
			paneFade = Math.min(1, paneFade + elapsed * 7);
			applyPaneFade();
		}

		lastMouseX = FlxG.mouse.x;

		// 输入框有焦点时不要抢键：否则退格会被当成"返回"，直接把界面关掉。
		var typing:Bool = (hexInput != null && hexInput.hasFocus);
		if (typing)
		{
			if (FlxG.keys.justPressed.ESCAPE) hexInput.hasFocus = false;
			return;
		}

		if (controls.BACK)
		{
			exitMenu();
			return;
		}
		if (FlxG.keys.justPressed.LEFT) changeValue(-1);
		if (FlxG.keys.justPressed.RIGHT) changeValue(1);
		if (FlxG.keys.justPressed.UP) stepRow(-1);
		if (FlxG.keys.justPressed.DOWN) stepRow(1);
		if (FlxG.keys.justPressed.ENTER) activateRow();
	}

	// ---------------------------------------------------------------------
	// 鼠标 / 触摸
	// ---------------------------------------------------------------------

	inline function over(x:Float, y:Float, w:Float, h:Float):Bool
		return FlxG.mouse.x >= x && FlxG.mouse.x <= x + w && FlxG.mouse.y >= y && FlxG.mouse.y <= y + h;

	function overSprite(s:FlxSprite):Bool
		return s != null && s.visible && over(s.x, s.y, s.width * Math.abs(s.scale.x), s.height * Math.abs(s.scale.y));

	function handleTabs():Void
	{
		if (!FlxG.mouse.justPressed) return;
		var tabW:Float = (contentW - 8) / 4;
		for (i in 0...4)
		{
			if (over(contentX + (tabW + 2.6) * i, 12, tabW, TAB_H))
			{
				switchTab(i);
				return;
			}
		}
	}

	function handlePreviews():Void
	{
		if (!FlxG.mouse.justPressed) return;

		for (i in 0...cusViewer.keyButtons.length)
		{
			var b:FlxSprite = cusViewer.keyButtons[i];
			if (b == null) continue;
			if (over(b.x, b.y, b.width * cusScale, b.height * cusScale))
			{
				selectTarget(i);
				return;
			}
		}
		for (i in 0...cusViewer.statBlocks.length)
		{
			var b:FlxSprite = cusViewer.statBlocks[i];
			if (b == null || !b.visible) continue;
			if (over(b.x, b.y, b.width * cusScale, b.height * cusScale))
			{
				selectTarget(10 + i);
				return;
			}
		}
	}

	function handleList():Void
	{
		if (!FlxG.mouse.justPressed) return;

		for (ri in 0...rows.length)
		{
			if (ri >= rowY.length || rowY[ri] < 0) continue;
			var r:KVRow = rows[ri];
			var h:Float = (r.kind == 'group') ? CARD_H : (r.kind == 'prev' ? PREV_H : ROW_H);
			var y:Float = rowY[ri];

			if (!over(contentX, y, contentW, h)) continue;

			if (r.kind == 'group' || r.kind == 'prev') return;

			selected = ri;

			// ↺ 单项重置
			if (over(contentX + contentW - 34, y, 34, h))
			{
				resetRow(ri);
				return;
			}

			if (r.kind == 'num')
			{
				if (over(ctlX, y, 30, h)) { changeValue(-1); return; }
				if (over(ctlX + ctlW - 30, y, 30, h)) { changeValue(1); return; }
				if (over(ctlX + 30, y, ctlW - 60, h))
				{
					renderRows();
					dragRow = ri; // 按住左右拖 = 滑块手感（鼠标与触摸都能用）
					return;
				}
			}

			if (r.kind == 'bool' && over(ctlX + ctlW - SW_W - 12, y, SW_W + 24, h))
			{
				r.set(!(r.get() == true));
				afterEdit(true);
				return;
			}

			if (r.kind == 'seg')
			{
				var opts:Array<String> = r.opts;
				var n:Int = opts.length;
				var bw:Float = (ctlW - (n - 1) * 4) / n;
				for (j in 0...n)
				{
					if (over(ctlX + (bw + 4) * j, y + (h - 32) / 2, bw, 32))
					{
						r.set(opts[j]);
						afterEdit(true);
						return;
					}
				}
			}

			if (r.kind == 'act')
			{
				activateRow();
				return;
			}

			renderRows();
			return;
		}
	}

	/** 数值行：按住值区左右拖动（每帧推进，鼠标和触摸通用） */
	function handleDrag():Void
	{
		if (dragRow < 0) return;
		if (!FlxG.mouse.pressed)
		{
			dragRow = -1;
			return;
		}
		if (dragRow >= rows.length)
		{
			dragRow = -1;
			return;
		}
		var r:KVRow = rows[dragRow];
		if (r.kind != 'num')
		{
			dragRow = -1;
			return;
		}

		var dx:Float = FlxG.mouse.x - lastMouseX;
		if (dx == 0) return;

		var trackW:Float = Math.max(60, ctlW - 60);
		var span:Float = r.max - r.min;
		var nv:Float = toFloat(r.get()) + (dx / trackW) * span;
		nv = FlxMath.bound(nv, r.min, r.max);
		nv = (r.step >= 1) ? Math.round(nv / r.step) * r.step : Math.round(nv * 100) / 100;
		r.set(nv);
		afterEdit();
	}

	function handlePicker():Void
	{
		if (!pickOpen) return;

		var cx:Float = colorWheel.x + colorWheel.width / 2;
		var cy:Float = colorWheel.y + colorWheel.height / 2;

		if (FlxG.mouse.justPressed)
		{
			if (overSprite(colorWheel)) holding = colorWheel;
			else if (overSprite(colorGradient)) holding = colorGradient;
			else if (overSprite(colorPalette) && palBitmap != null)
			{
				pickFromPalette();
				holding = null;
			}
			else holding = null;
		}
		if (FlxG.mouse.justReleased) holding = null;

		if (holding == colorWheel && FlxG.mouse.pressed)
		{
			var dx:Float = FlxG.mouse.x - cx;
			var dy:Float = FlxG.mouse.y - cy;
			var hue:Float = Math.atan2(dy, dx) * 180 / Math.PI + 90;
			if (hue < 0) hue += 360;
			var sat:Float = FlxMath.bound(Math.sqrt(dx * dx + dy * dy) / (colorWheel.width / 2 - 8), 0, 1);
			var cur:FlxColor = curPickColor();
			pushColor(FlxColor.fromHSB(hue, sat, FlxMath.bound(cur.brightness, 0.03, 1)));
		}
		else if (holding == colorGradient && FlxG.mouse.pressed)
		{
			var b:Float = 1 - FlxMath.bound((FlxG.mouse.y - colorGradient.y) / colorGradient.height, 0, 1);
			var cur:FlxColor = curPickColor();
			pushColor(FlxColor.fromHSB(cur.hue, cur.saturation, b));
		}
	}

	function pickFromPalette():Void
	{
		if (palBitmap == null) return;
		var u:Float = FlxMath.bound((FlxG.mouse.x - colorPalette.x) / Math.max(1, colorPalette.width), 0, 0.999);
		var v:Float = FlxMath.bound((FlxG.mouse.y - colorPalette.y) / Math.max(1, colorPalette.height), 0, 0.999);
		pushColor(palBitmap.getPixel32(Std.int(u * palBitmap.width), Std.int(v * palBitmap.height)));
	}

	function curPickColor():FlxColor
	{
		var r:KVRow = currentRow();
		if (r == null) return FlxColor.WHITE;
		var raw:String = Std.string(r.get());
		return (raw == null || raw == '') ? FlxColor.WHITE : CoolUtil.colorFromString(raw);
	}

	function handleHexInput():Void
	{
		if (hexInput == null || !hexInput.hasFocus) return;
		var v:String = hexInput.text;
		if (v == null || v.length != 6) return;

		var r:KVRow = currentRow();
		if (r == null || r.kind != 'color') return;

		var want:String = '#' + v.toUpperCase();
		if (Std.string(r.get()).toUpperCase() == want) return;
		r.set(want);
		syncPicker();
		afterEdit();
	}

	function handleFooter():Void
	{
		if (!FlxG.mouse.justPressed) return;

		if (over(resetAllBox.fill.x, resetAllBox.fill.y, resetAllBox.fill.width, resetAllBox.fill.height))
		{
			resetAll();
			return;
		}
		if (over(saveBox.fill.x, saveBox.fill.y, saveBox.fill.width, saveBox.fill.height)) saveAndExit();
	}

	// ---------------------------------------------------------------------
	// 键盘 / 手柄
	// ---------------------------------------------------------------------

	function stepRow(dir:Int):Void
	{
		if (rows.length == 0) return;
		var i:Int = selected;
		for (_ in 0...rows.length)
		{
			i += dir;
			if (i < 0) i = rows.length - 1;
			if (i >= rows.length) i = 0;
			if (rows[i].kind != 'group') break;
		}
		selected = i;
		if (selected < scrollFrom) scrollFrom = selected;
		if (selected >= scrollFrom + maxVisible) scrollFrom = selected - maxVisible + 1;
		renderRows();
	}

	function changeValue(dir:Int):Void
	{
		var r:KVRow = currentRow();
		if (r == null) return;

		switch (r.kind)
		{
			case 'num':
				r.set(FlxMath.bound(toFloat(r.get()) + r.step * dir, r.min, r.max));
				afterEdit();
			case 'bool':
				r.set(!(r.get() == true));
				afterEdit(true);
			case 'seg':
				var opts:Array<String> = r.opts;
				var i:Int = opts.indexOf(Std.string(r.get()));
				if (i < 0) i = 0;
				r.set(opts[(i + dir + opts.length) % opts.length]);
				afterEdit(true);
			case 'act':
				activateRow();
			default:
		}
	}

	function activateRow():Void
	{
		var r:KVRow = currentRow();
		if (r == null) return;
		if (r.kind == 'act' && r.onAct != null) r.onAct();
		else if (r.kind == 'bool')
		{
			r.set(!(r.get() == true));
			afterEdit(true);
		}
	}

	function scrollBy(d:Int):Void
	{
		var maxFrom:Int = Std.int(Math.max(0, rows.length - maxVisible));
		var nv:Int = Std.int(FlxMath.bound(scrollFrom + d, 0, maxFrom));
		if (nv == scrollFrom) return;
		scrollFrom = nv;
		renderRows();
	}

	// ---------------------------------------------------------------------
	// 变更动作
	// ---------------------------------------------------------------------

	function selectTarget(idx:Int):Void
	{
		if (idx < 0 || idx > 11 || idx == target) return;
		target = idx;
		ClientPrefs.data.keyboardTheme = 'custom';
		setTriVisible(!isStat()); // 统计块没有被按下态和长条
		refreshPreviews();
		rows = rowsForTab(tab); // 颜色是按目标读的，必须重算行
		renderRows();
		updateTriCard();
		updateWhere();
	}

	function markCustom():Void
		ClientPrefs.data.keyboardTheme = 'custom';

	/** 一次改动的收尾：刷预览 + 刷三态卡 + 刷行 + 刷底栏文字 */
	function afterEdit(?rebuild:Bool = true):Void
	{
		refreshPreviews();
		updateTriCard();
		if (rebuild) renderRows();
		updateWhere();
	}

	function resetRow(ri:Int):Void
	{
		var r:KVRow = rows[ri];
		if (r == null) return;

		switch (r.kind)
		{
			case 'color':
				setSlotRaw(colorSlotOf(r.id), '');
			case 'num', 'bool', 'seg':
				resetGlobal(r.id);
			default:
				return;
		}
		markCustom();
		afterEdit(true);
	}

	/** 全局项的单项重置（按 id 匹配，不受界面语言影响） */
	function resetGlobal(id:String):Void
	{
		var d = ClientPrefs.defaultData;
		switch (id)
		{
			case 'alpha': ClientPrefs.data.keyboardAlpha = d.keyboardAlpha;
			case 'barOn': ClientPrefs.data.keyboardTimeDisplay = d.keyboardTimeDisplay;
			case 'barAlpha': ClientPrefs.data.keyboardBarAlpha = d.keyboardBarAlpha;
			case 'barMax': ClientPrefs.data.keyboardBarHeight = d.keyboardBarHeight;
			case 'barSpeed': ClientPrefs.data.keyboardBarSpeed = d.keyboardBarSpeed;
			case 'barStay': ClientPrefs.data.keyboardTime = d.keyboardTime;
			case 'barDis': ClientPrefs.data.keyboardBarDisappearMode = d.keyboardBarDisappearMode;
			case 'barSrc': ClientPrefs.data.keyboardBarColorMode = 'Custom';
			case 'showStats': ClientPrefs.data.keyboardStats = d.keyboardStats;
			case 'statHeight': ClientPrefs.data.keyboardStatHeight = d.keyboardStatHeight;
			case 'statWidth': ClientPrefs.data.keyboardStatWidth = d.keyboardStatWidth;
			case 'statAlpha': ClientPrefs.data.keyboardStatAlpha = d.keyboardStatAlpha;
			case 'followSong': ClientPrefs.data.keyboardFollowNoteColor = d.keyboardFollowNoteColor;
			case 'theme': applyTheme('default');
			default:
		}
	}

	function resetAll():Void
	{
		var d = ClientPrefs.defaultData;
		ClientPrefs.data.keyboardAlpha = d.keyboardAlpha;
		ClientPrefs.data.keyboardPressedAlpha = d.keyboardPressedAlpha;
		ClientPrefs.data.keyboardTimeDisplay = d.keyboardTimeDisplay;
		ClientPrefs.data.keyboardTime = d.keyboardTime;
		ClientPrefs.data.keyboardBarAlpha = d.keyboardBarAlpha;
		ClientPrefs.data.keyboardBarHeight = d.keyboardBarHeight;
		ClientPrefs.data.keyboardBarSpeed = d.keyboardBarSpeed;
		ClientPrefs.data.keyboardBarDisappearMode = d.keyboardBarDisappearMode;
		ClientPrefs.data.keyboardBarColorMode = 'Custom';
		ClientPrefs.data.keyboardStats = d.keyboardStats;
		ClientPrefs.data.keyboardStatHeight = d.keyboardStatHeight;
		ClientPrefs.data.keyboardStatWidth = d.keyboardStatWidth;
		ClientPrefs.data.keyboardStatAlpha = d.keyboardStatAlpha;
		ClientPrefs.data.keyboardFollowNoteColor = d.keyboardFollowNoteColor;
		ClientPrefs.data.keyboardTheme = 'default';

		for (i in 0...10)
		{
			ClientPrefs.setKeyboardKeyColorRaw(i, '');
			ClientPrefs.setKeyboardKeyTextColorRaw(i, '');
			ClientPrefs.setKeyboardPressedColorRaw(i, '');
			ClientPrefs.setKeyboardPressedTextColorRaw(i, '');
			ClientPrefs.setKeyboardBarColorRaw(i, '');
		}
		ClientPrefs.data.keyboardStatKpsColor = d.keyboardStatKpsColor;
		ClientPrefs.data.keyboardStatTotColor = d.keyboardStatTotColor;
		ClientPrefs.data.keyboardStatKpsTextColor = '';
		ClientPrefs.data.keyboardStatTotTextColor = '';

		target = 3;
		refreshPreviews();
		rows = rowsForTab(tab);
		renderRows();
		updateTriCard();
		updateWhere();
		toast(t('kv_toast_reset', '已恢复默认设置', 'Reset to defaults'));
	}

	function applyTheme(name:String):Void
	{
		ClientPrefs.data.keyboardTheme = name;
		var th = THEMES.get(name);

		if (th != null)
		{
			for (i in 0...10)
			{
				ClientPrefs.setKeyboardKeyColorRaw(i, th.normal);
				ClientPrefs.setKeyboardKeyTextColorRaw(i, th.normalText);
				ClientPrefs.setKeyboardPressedColorRaw(i, th.press);
				ClientPrefs.setKeyboardPressedTextColorRaw(i, th.pressText);
				ClientPrefs.setKeyboardBarColorRaw(i, th.bar);
			}
			ClientPrefs.data.keyboardStatKpsColor = th.normal;
			ClientPrefs.data.keyboardStatTotColor = th.normal;
			ClientPrefs.data.keyboardStatKpsTextColor = th.normalText;
			ClientPrefs.data.keyboardStatTotTextColor = th.normalText;
			ClientPrefs.data.keyboardBarColorMode = 'Custom';
		}
		afterEdit(true);
	}

	// ---------------------------------------------------------------------
	// 颜色读写：把「当前目标 + 槽位」映射到具体字段
	// ---------------------------------------------------------------------

	function getColorRaw(idx:Int, slot:String):String
	{
		if (idx >= 10)
		{
			var s:Int = idx - 10;
			return switch (slot)
			{
				case 'normal': (s == 0) ? ClientPrefs.data.keyboardStatKpsColor : ClientPrefs.data.keyboardStatTotColor;
				case 'normalText': (s == 0) ? ClientPrefs.data.keyboardStatKpsTextColor : ClientPrefs.data.keyboardStatTotTextColor;
				default: '';
			}
		}
		return switch (slot)
		{
			case 'normal': ClientPrefs.getKeyboardKeyColorRaw(idx);
			case 'border': ClientPrefs.getKeyboardKeyBorderColorRaw(idx);
			case 'normalText': ClientPrefs.getKeyboardKeyTextColorRaw(idx);
			case 'press': ClientPrefs.getKeyboardPressedColorRaw(idx);
			case 'pressText': ClientPrefs.getKeyboardPressedTextColorRaw(idx);
			case 'bar': ClientPrefs.getKeyboardBarColorRaw(idx);
			default: '';
		}
	}

	function setColorRaw(idx:Int, slot:String, value:String):Void
	{
		if (idx >= 10)
		{
			var s:Int = idx - 10;
			switch (slot)
			{
				case 'normal':
					if (s == 0) ClientPrefs.data.keyboardStatKpsColor = value else ClientPrefs.data.keyboardStatTotColor = value;
				case 'normalText':
					if (s == 0) ClientPrefs.data.keyboardStatKpsTextColor = value else ClientPrefs.data.keyboardStatTotTextColor = value;
				default:
			}
		}
		else
		{
			switch (slot)
			{
				case 'normal': ClientPrefs.setKeyboardKeyColorRaw(idx, value);
				case 'border': ClientPrefs.setKeyboardKeyBorderColorRaw(idx, value);
				case 'normalText': ClientPrefs.setKeyboardKeyTextColorRaw(idx, value);
				case 'press': ClientPrefs.setKeyboardPressedColorRaw(idx, value);
				case 'pressText': ClientPrefs.setKeyboardPressedTextColorRaw(idx, value);
				case 'bar': ClientPrefs.setKeyboardBarColorRaw(idx, value);
				default:
			}
		}
		markCustom();
		afterEdit();
	}

	/** 行 id → 颜色槽位（-1 = 不是颜色行） */
	function colorSlotOf(id:String):Int
	{
		return switch (id)
		{
			case 'cNormal': 0;
			case 'cNormalText': 1;
			case 'cBorder': 5;
			case 'cPress': 2;
			case 'cPressText': 3;
			case 'cBar': 4;
			default: -1;
		}
	}

	function setSlotRaw(slot:Int, value:String):Void
	{
		var names:Array<String> = ['normal', 'normalText', 'press', 'pressText', 'bar', 'border'];
		if (slot >= 0 && slot < names.length) setColorRaw(target, names[slot], value);
	}

	// ---------------------------------------------------------------------
	// 配色取值（与 ClientPrefs 的规则保持一致）
	// ---------------------------------------------------------------------

	inline function laneColor(idx:Int):FlxColor
		return (idx >= 10) ? ClientPrefs.keyboardStatColor(idx - 10) : ClientPrefs.keyboardLaneColor(idx);

	inline function keyTextColor(idx:Int):FlxColor
		return (idx >= 10) ? ClientPrefs.keyboardStatText(idx - 10) : ClientPrefs.keyboardKeyText(idx);

	inline function pressColor(idx:Int):FlxColor
		return (idx >= 10) ? laneColor(idx) : ClientPrefs.keyboardPress(idx);

	inline function pressTextColor(idx:Int):FlxColor
		return (idx >= 10) ? keyTextColor(idx) : ClientPrefs.keyboardPressText(idx);

	inline function barLaneColor(idx:Int):FlxColor
		return ClientPrefs.keyboardBarLaneColor(idx >= 10 ? 0 : idx);

	inline function isBarFade():Bool
		return ClientPrefs.data.keyboardBarDisappearMode == 'fade';

	inline function isBarFollowNormal():Bool
		return ClientPrefs.data.keyboardBarColorMode == 'Key';

	function barMaxHeight():Float
	{
		var h:Int = ClientPrefs.data.keyboardBarHeight;
		return (h > 0) ? h : ClientPrefs.data.keyboardKeySize * 3;
	}

	function statHeight():Float
	{
		var h:Int = ClientPrefs.data.keyboardStatHeight;
		return (h > 0) ? h : ClientPrefs.data.keyboardKeySize;
	}

	// ---------------------------------------------------------------------
	// 导入导出
	// ---------------------------------------------------------------------

	function exportJson():Void
	{
		#if sys
		var targets:Dynamic = {};
		for (i in 0...10)
		{
			Reflect.setField(targets, 'k' + i, {
				normalColor: ClientPrefs.getKeyboardKeyColorRaw(i),
				normalText: ClientPrefs.getKeyboardKeyTextColorRaw(i),
				pressColor: ClientPrefs.getKeyboardPressedColorRaw(i),
				pressText: ClientPrefs.getKeyboardPressedTextColorRaw(i),
				barColor: ClientPrefs.getKeyboardBarColorRaw(i)
			});
		}
		Reflect.setField(targets, 'kps', {
			normalColor: ClientPrefs.data.keyboardStatKpsColor,
			normalText: ClientPrefs.data.keyboardStatKpsTextColor
		});
		Reflect.setField(targets, 'total', {
			normalColor: ClientPrefs.data.keyboardStatTotColor,
			normalText: ClientPrefs.data.keyboardStatTotTextColor
		});

		var obj:Dynamic = {
			version: 2,
			theme: ClientPrefs.data.keyboardTheme,
			options: {
				alpha: ClientPrefs.data.keyboardAlpha,
				barOn: ClientPrefs.data.keyboardTimeDisplay,
				barAlpha: ClientPrefs.data.keyboardBarAlpha,
				barMax: barMaxHeight(),
				barSpeed: ClientPrefs.data.keyboardBarSpeed,
				barStay: ClientPrefs.data.keyboardTime,
				barDis: isBarFade(),
				barMode: ClientPrefs.data.keyboardBarColorMode,
				showStats: ClientPrefs.data.keyboardStats,
				statHeight: statHeight(),
				statWidth: ClientPrefs.data.keyboardStatWidth,
				statAlpha: ClientPrefs.data.keyboardStatAlpha,
				followSong: ClientPrefs.data.keyboardFollowNoteColor
			},
			targets: targets
		};

		File.saveContent('keyboard-feedback.json', haxe.Json.stringify(obj, '    '));
		toast(t('kv_toast_export', '已导出 keyboard-feedback.json', 'Exported keyboard-feedback.json'));
		#end
	}

	function importJson():Void
	{
		#if sys
		var path:String = 'keyboard-feedback.json';
		if (!FileSystem.exists(path))
		{
			toast(t('kv_toast_import_missing', '没找到 keyboard-feedback.json（放在游戏目录下）', 'keyboard-feedback.json not found'));
			return;
		}

		var obj:Dynamic = null;
		try
		{
			obj = haxe.Json.parse(File.getContent(path));
		}
		catch (e:Dynamic)
		{
			toast(t('kv_toast_bad_json', 'JSON 解析失败', 'Bad JSON'));
			return;
		}
		if (obj == null)
		{
			toast(t('kv_toast_bad_json', 'JSON 解析失败', 'Bad JSON'));
			return;
		}

		var opts:Dynamic = Reflect.field(obj, 'options');
		if (opts != null)
		{
			readFloat(opts, 'alpha', function(v) ClientPrefs.data.keyboardAlpha = FlxMath.bound(v, 0, 1));
			readBool(opts, 'barOn', function(v) ClientPrefs.data.keyboardTimeDisplay = v);
			readFloat(opts, 'barAlpha', function(v) ClientPrefs.data.keyboardBarAlpha = FlxMath.bound(v, 0, 1));
			readFloat(opts, 'barMax', function(v) ClientPrefs.data.keyboardBarHeight = Std.int(v));
			readFloat(opts, 'barSpeed', function(v) ClientPrefs.data.keyboardBarSpeed = v);
			readFloat(opts, 'barStay', function(v) ClientPrefs.data.keyboardTime = v);
			readBool(opts, 'barDis', function(v) ClientPrefs.data.keyboardBarDisappearMode = v ? 'fade' : 'sudden');
			readStr(opts, 'barMode', function(v) ClientPrefs.data.keyboardBarColorMode = v);
			readBool(opts, 'showStats', function(v) ClientPrefs.data.keyboardStats = v);
			readFloat(opts, 'statHeight', function(v) ClientPrefs.data.keyboardStatHeight = Std.int(v));
			readFloat(opts, 'statWidth', function(v) ClientPrefs.data.keyboardStatWidth = v);
			readFloat(opts, 'statAlpha', function(v) ClientPrefs.data.keyboardStatAlpha = v);
			readBool(opts, 'followSong', function(v) ClientPrefs.data.keyboardFollowNoteColor = v);
		}

		var targets:Dynamic = Reflect.field(obj, 'targets');
		if (targets != null)
		{
			for (i in 0...10)
			{
				var e:Dynamic = Reflect.field(targets, 'k' + i);
				if (e == null) continue;
				readStr(e, 'normalColor', function(v) ClientPrefs.setKeyboardKeyColorRaw(i, v));
				readStr(e, 'normalText', function(v) ClientPrefs.setKeyboardKeyTextColorRaw(i, v));
				readStr(e, 'pressColor', function(v) ClientPrefs.setKeyboardPressedColorRaw(i, v));
				readStr(e, 'pressText', function(v) ClientPrefs.setKeyboardPressedTextColorRaw(i, v));
				readStr(e, 'barColor', function(v) ClientPrefs.setKeyboardBarColorRaw(i, v));
			}

			var e:Dynamic = Reflect.field(targets, 'kps');
			if (e != null)
			{
				readStr(e, 'normalColor', function(v) ClientPrefs.data.keyboardStatKpsColor = v);
				readStr(e, 'normalText', function(v) ClientPrefs.data.keyboardStatKpsTextColor = v);
				// v1 老存档把长条/统计参数塞在每个 target 里，顺手收上来一份
				if (opts == null)
				{
					readFloat(e, 'barMax', function(v) ClientPrefs.data.keyboardBarHeight = Std.int(v));
					readFloat(e, 'statHeight', function(v) ClientPrefs.data.keyboardStatHeight = Std.int(v));
					readFloat(e, 'statWidth', function(v) ClientPrefs.data.keyboardStatWidth = v);
				}
			}
			e = Reflect.field(targets, 'total');
			if (e != null)
			{
				readStr(e, 'normalColor', function(v) ClientPrefs.data.keyboardStatTotColor = v);
				readStr(e, 'normalText', function(v) ClientPrefs.data.keyboardStatTotTextColor = v);
			}
		}

		var th:Dynamic = Reflect.field(obj, 'theme');
		ClientPrefs.data.keyboardTheme = (th == null) ? 'custom' : Std.string(th);

		target = 3;
		refreshPreviews();
		rows = rowsForTab(tab);
		renderRows();
		updateTriCard();
		updateWhere();
		toast(t('kv_toast_import', '已导入 keyboard-feedback.json', 'Imported keyboard-feedback.json'));
		#end
	}

	inline function readStr(o:Dynamic, key:String, fn:String->Void):Void
	{
		var v:Dynamic = Reflect.field(o, key);
		if (v != null && Std.string(v) != 'null') fn(Std.string(v));
	}

	inline function readFloat(o:Dynamic, key:String, fn:Float->Void):Void
	{
		var v:Dynamic = Reflect.field(o, key);
		if (v == null) return;
		var f:Float = Std.parseFloat(Std.string(v));
		if (!Math.isNaN(f)) fn(f);
	}

	inline function readBool(o:Dynamic, key:String, fn:Bool->Void):Void
	{
		var v:Dynamic = Reflect.field(o, key);
		if (v == null) return;
		fn(v == true || Std.string(v) == 'true');
	}

	// ---------------------------------------------------------------------
	// 退出 / 销毁
	// ---------------------------------------------------------------------

	function saveAndExit():Void
	{
		toast(t('kv_toast_saved', '已保存', 'Saved'));
		exitMenu();
	}

	function exitMenu():Void
	{
		// ★ 重入保护：destroy() 里的二次销毁曾经让界面直接崩（rva 0x168ecee）
		if (closing) return;
		closing = true;
		ClientPrefs.saveSettings();
		#if desktop
		FlxG.mouse.visible = true;
		openfl.ui.Mouse.show();
		#end
		close();
	}

	override function destroy():Void
	{
		#if desktop
		FlxG.mouse.visible = true;
		openfl.ui.Mouse.show();
		#end
		// 万一没走 exitMenu 就直接销毁，也得把取值来源复位，否则会污染全局
		ClientPrefs.previewUseDefault = false;
		super.destroy();
	}

	// ---------------------------------------------------------------------
	// 小工具
	// ---------------------------------------------------------------------

	inline function toFloat(v:Dynamic):Float
	{
		if (v == null) return 0;
		var f:Float = Std.parseFloat(Std.string(v));
		return Math.isNaN(f) ? 0 : f;
	}

	inline function boundF(v:Dynamic, lo:Float, hi:Float):Float
		return FlxMath.bound(toFloat(v), lo, hi);

	function fmtNum(v:Float, dec:Int):String
	{
		if (dec <= 0) return Std.string(Std.int(Math.round(v)));
		var p:Float = Math.pow(10, dec);
		var s:String = Std.string(Math.round(v * p) / p);
		var dot:Int = s.indexOf('.');
		if (dot < 0) s += '.';
		var have:Int = s.length - s.indexOf('.') - 1;
		while (have < dec)
		{
			s += '0';
			have++;
		}
		return s;
	}

	function mkTxt(x:Float, y:Float, w:Float, text:String, size:Float, color:Int, ?outline:Bool = false, ?parent:FlxSpriteGroup):FlxText
	{
		var t:FlxText = new FlxText(x, y, w, text, Std.int(size));
		t.setFormat(Paths.font(Language.get('fontName', 'main') + '.ttf'), Std.int(size), color);
		if (outline) t.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF000000, 2);
		t.scrollFactor.set();
		if (parent != null) parent.add(t) else add(t);
		return t;
	}

	function newSprite(?parent:FlxSpriteGroup):FlxSprite
	{
		var s:FlxSprite = new FlxSprite(0, 0).makeGraphic(1, 1, 0xFFFFFFFF);
		s.offset.set(0, 0);
		s.origin.set(0, 0);
		s.scrollFactor.set();
		if (parent != null) parent.add(s) else add(s);
		return s;
	}

	function makeBox(w:Float, h:Float, fill:Int, border:Int, ?parent:FlxSpriteGroup):KVBox
	{
		var b:KVBox = new KVBox();
		b.border = new FlxSprite(0, 0).makeGraphic(Math.floor(w) + 2, Math.floor(h) + 2, 0xFFFFFFFF);
		b.border.color = border;
		b.border.scrollFactor.set();
		b.fill = new FlxSprite(0, 0).makeGraphic(Math.floor(w), Math.floor(h), 0xFFFFFFFF);
		b.fill.color = fill;
		b.fill.alpha = 0.75;
		b.fill.scrollFactor.set();
		if (parent != null)
		{
			parent.add(b.border);
			parent.add(b.fill);
		}
		else
		{
			add(b.border);
			add(b.fill);
		}
		return b;
	}

	function resizeBox(b:KVBox, x:Float, y:Float, w:Float, h:Float):Void
	{
		b.border.setGraphicSize(Math.floor(w) + 2, Math.floor(h) + 2);
		b.border.updateHitbox();
		b.border.offset.set(0, 0);   // 同上：updateHitbox 的居中偏移必须清掉
		b.border.origin.set(0, 0);
		b.fill.setGraphicSize(Math.floor(w), Math.floor(h));
		b.fill.updateHitbox();
		b.fill.offset.set(0, 0);
		b.fill.origin.set(0, 0);
		boxPos(b, x, y);
	}

	function boxPos(b:KVBox, x:Float, y:Float):Void
	{
		b.border.setPosition(x - 1, y - 1);
		b.fill.setPosition(x, y);
	}

	function boxColors(b:KVBox, fill:Int, border:Int):Void
	{
		b.fill.color = fill;
		b.border.color = border;
	}

	/** 自绘向下的三角（montserrat 没有 ▼ 字形，用文字画出来是空白） */
	function makeDownArrow(size:Float, color:Int):FlxSprite
	{
		var sh:Shape = new Shape();
		sh.graphics.beginFill(0xFFFFFF);
		sh.graphics.moveTo(0, 0);
		sh.graphics.lineTo(size, 0);
		sh.graphics.lineTo(size / 2, size);
		sh.graphics.lineTo(0, 0);
		sh.graphics.endFill();

		var bd:BitmapData = new BitmapData(Std.int(size), Std.int(size), true, 0);
		bd.draw(sh);

		var s:FlxSprite = new FlxSprite(0, 0);
		s.loadGraphic(bd);
		s.offset.set(0, 0);
		s.origin.set(0, 0);
		s.color = color;
		s.scrollFactor.set();
		return s;
	}
}

/** 设置项定义：kind = group / num / bool / color / seg / act / prev */
typedef KVRow = {
	id:String,
	label:String,
	kind:String,
	get:Void->Dynamic,
	set:Dynamic->Void,
	?min:Float,
	?max:Float,
	?step:Float,
	?dec:Int,
	?unit:String,
	?opts:Array<String>,
	?optLabels:Array<String>,
	?tip:String,
	?onAct:Void->Void
}

/** 两个矩形拼出来的"卡片"（描边 + 填充） */
class KVBox
{
	public var border:FlxSprite;
	public var fill:FlxSprite;

	public function new() {}
}
