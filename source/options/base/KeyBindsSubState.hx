package options.base;

import flixel.text.FlxText;
import flixel.util.FlxColor;
import general.backend.ClientPrefs;
import general.backend.InputFormatter;
import general.backend.language.Language;
import flixel.input.keyboard.FlxKey;
import Std;

class KeyBindsSubState extends MusicBeatSubstate
{
	static final categories:Array<{name:String, first:Int, len:Int}> = [
		{name: '1K',       first: 0,  len: 1},
		{name: '2K',       first: 1,  len: 2},
		{name: '3K',       first: 3,  len: 3},
		{name: '4K',       first: 6,  len: 4},
		{name: '5K',       first: 10, len: 5},
		{name: '6k',       first: 15, len: 6},
		{name: '7k',       first: 21, len: 7},
		{name: '8k',       first: 28, len: 8},
		{name: '9k',       first: 36, len: 9},
		{name: '10k',      first: 45, len: 10},
		{name: 'UI',       first: 55, len: 4},
		{name: 'Misc',     first: 59, len: 5},
	];

	// Category-specific highlight colors for keyboard — each note mode gets its own color
	static final catHighlightColors:Array<FlxColor> = [
		0xFF88CC88,  // 1K      - muted green
		0xFF88AACC,  // 2K      - steel blue
		0xFFCCAA88,  // 3K      - tan/brown
		0xFF66CCFF,  // 4K      - sky blue
		0xFF99DDFF,  // 5K      - lighter sky blue (new)
		0xFFFFB366,  // 6k      - orange
		0xFFFF66CC,  // 7k      - pink
		0xFF66FF99,  // 8k      - lime green
		0xFFB366FF,  // 9k      - purple
		0xFFFFCC66,  // 10k     - gold
		0xFF66FFCC,  // UI      - teal
		0xFFFF6688,  // Misc    - coral
	];

	// Fallback category name translations (when Language.get fails)
	static final catNameFallbackZH:Map<String, String> = [
		'1K' => '1K', '2K' => '2K', '3K' => '3K',
		'4K' => '4K', '5K' => '5K', '6k' => '6K',
		'7k' => '7K', '8k' => '8K', '9k' => '9K',
		'10k' => '10K', 'UI' => '界面', 'Misc' => '其他',
	];

	static function isChinese():Bool
	{
		var lang:String = ClientPrefs.data.language;
		return lang.indexOf('中文') > -1 || lang.toLowerCase().indexOf('chinese') > -1;
	}

	// Translate with fallback. langKey is the translation key; fallbackZH/fallbackEN are hardcoded defaults.
	static function tr(langKey:String, group:String, fallbackZH:String, fallbackEN:String):String
	{
		var raw:String = Language.get(langKey, group);
		// If developerMode is on and translation is missing, Language.get returns 'key (404)'.
		// If developerMode is off and translation is missing, returns key unchanged.
		if (raw == langKey || raw == langKey + ' (404)')
			return isChinese() ? fallbackZH : fallbackEN;
		return raw;
	}

	static function getFontPath():String
	{
		return Paths.font(Language.get('fontName', 'main') + '.ttf');
	}

	static final entries:Array<{name:String, key:String}> = [
		// 1K+2K+3K (0-5)
		{name: '1K [key]',      key: '0_key_0'},
		{name: '2K Left',       key: '1_key_0'},
		{name: '2K Right',      key: '1_key_1'},
		{name: '3K Left',       key: '2_key_0'},
		{name: '3K Middle',     key: '2_key_1'},
		{name: '3K Right',      key: '2_key_2'},
		// 4K+5K (6-14)
		{name: '4K Left',       key: 'note_left'},
		{name: '4K Down',       key: 'note_down'},
		{name: '4K Up',         key: 'note_up'},
		{name: '4K Right',      key: 'note_right'},
		{name: '5K Left',       key: '4_key_0'},
		{name: '5K Down',       key: '4_key_1'},
		{name: '5K Middle',     key: '4_key_2'},
		{name: '5K Up',         key: '4_key_3'},
		{name: '5K Right',      key: '4_key_4'},
		// 6k (15-20)
		{name: '6K Left1',      key: '5_key_0'},
		{name: '6K Up',         key: '5_key_1'},
		{name: '6K Right1',     key: '5_key_2'},
		{name: '6K Left2',      key: '5_key_3'},
		{name: '6K Down',       key: '5_key_4'},
		{name: '6K Right2',     key: '5_key_5'},
		// 7k (21-27)
		{name: '7K Left1',      key: '6_key_0'},
		{name: '7K Up',         key: '6_key_1'},
		{name: '7K Right1',     key: '6_key_2'},
		{name: '7K Middle',     key: '6_key_3'},
		{name: '7K Left2',      key: '6_key_4'},
		{name: '7K Down',       key: '6_key_5'},
		{name: '7K Right2',     key: '6_key_6'},
		// 8k (28-35)
		{name: '8K Left1',      key: '7_key_0'},
		{name: '8K Down1',      key: '7_key_1'},
		{name: '8K Up1',        key: '7_key_2'},
		{name: '8K Right1',     key: '7_key_3'},
		{name: '8K Left2',      key: '7_key_4'},
		{name: '8K Down2',      key: '7_key_5'},
		{name: '8K Up2',        key: '7_key_6'},
		{name: '8K Right2',     key: '7_key_7'},
		// 9k (36-44)
		{name: '9K Left1',      key: '8_key_0'},
		{name: '9K Down1',      key: '8_key_1'},
		{name: '9K Up1',        key: '8_key_2'},
		{name: '9K Right1',     key: '8_key_3'},
		{name: '9K Middle',     key: '8_key_4'},
		{name: '9K Left2',      key: '8_key_5'},
		{name: '9K Down2',      key: '8_key_6'},
		{name: '9K Up2',        key: '8_key_7'},
		{name: '9K Right2',     key: '8_key_8'},
		// 10k (45-54)
		{name: '10K Left1',     key: '9_key_0'},
		{name: '10K Down1',     key: '9_key_1'},
		{name: '10K Up1',       key: '9_key_2'},
		{name: '10K Right1',    key: '9_key_3'},
		{name: '10K Middle1',   key: '9_key_4'},
		{name: '10K Middle2',   key: '9_key_5'},
		{name: '10K Left2',     key: '9_key_6'},
		{name: '10K Down2',     key: '9_key_7'},
		{name: '10K Up2',       key: '9_key_8'},
		{name: '10K Right2',    key: '9_key_9'},
		// UI (55-58)
		{name: 'UI Left',       key: 'ui_left'},
		{name: 'UI Down',       key: 'ui_down'},
		{name: 'UI Up',         key: 'ui_up'},
		{name: 'UI Right',      key: 'ui_right'},
		// Misc (59-63)
		{name: 'Reset',         key: 'reset'},
		{name: 'Accept',        key: 'accept'},
		{name: 'Back',          key: 'back'},
		{name: 'Pause',         key: 'pause'},
		{name: 'Fullscreen',    key: 'fullscreen'},
	];

	// Visual keyboard layout (non-interactive, just for reference)
	var returnArray:Array<Array<String>> = [
		['Esc', '', 'F1', 'F2', 'F3', 'F4', '', 'F5', 'F6', 'F7', 'F8', '', 'F9', 'F10', 'F11', 'F12', '', 'PrtScrn', 'ScrLk', 'Break'],
		['`', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '+', 'BckSpc', '', 'Ins', 'Home', 'PgUp', '', 'NumLk', '#/', '#*', '#-'],
		['Tab', 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '[', ']', '\\', '', 'Del', 'End', 'PgDown', '', '#7', '#8', '#9', '#+'],
		['Caps', 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ';', "'", 'Enter', '', '', '', '', '', '#4', '#5', '#6', ''],
		['Shift', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', ',', '.', '/', 'Shift', '', '', 'Up', '', '', '#1', '#2', '#3', ''],
		['Ctrl', 'Win', 'Alt', 'Space', 'Alt', 'Win', 'Menu', 'Ctrl', '', 'Left', 'Down', 'Right', '', '#0', '#.', ''],
	];

	var displayArray:Array<Array<String>> = [
		['Esc', '', 'F1', 'F2', 'F3', 'F4', '', 'F5', 'F6', 'F7', 'F8', '', 'F9', 'F10', 'F11', 'F12', '', 'Prt\nScrn', 'Scr\nLk', 'Break'],
		['`', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '+', 'Back\nSpace', '', 'Ins', 'Home', 'Pg\nUp', '', 'Num\nLk', '#/', '#*', '#-'],
		['Tab', 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '[', ']', '\\', '', 'Del', 'End', 'Pg\nDown', '', '#7', '#8', '#9', '#+'],
		['Caps', 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ';', "'", 'Enter', '', '', '', '', '', '#4', '#5', '#6', ''],
		['Shift', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', ',', '.', '/', 'Shift', '', '', 'Up', '', '', '#1', '#2', '#3', ''],
		['Ctrl', 'Win', 'Alt', 'Space', 'Alt', 'Win', 'Menu', 'Ctrl', '', 'Left', 'Down', 'Right', '', '#0', '#.', ''],
	];

	var widthUnits:Array<Array<Float>> = [
		[1, 1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.5, 1.25, 1.25, 1.25],
		[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1.5, 1, 1, 1, 1.5, 1, 1, 1, 1],
		[1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.5, 1.5, 1, 1, 1, 1.5, 1, 1, 1, 1],
		[1.75, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.37, 1.5, 1, 1, 1, 1.5, 1, 1, 1, 1],
		[2.25, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.96, 1.5, 1, 1, 1, 1.5, 1, 1, 1, 1],
		[1.25, 1.25, 1.25, 6.25, 1.25, 1.25, 1.25, 2, 1.5, 1, 1, 1, 1.5, 2.2, 1, 1],
	];

	var keySprites:Array<FlxSpriteGroup>;
	var keyBgList:Array<{key:String, bg:FlxSprite}>;

	// UI
	var catTexts:Array<FlxText>;
	var entryTexts:Array<FlxText>;
	var slotText:FlxText;
	var hintText:FlxText;
	var resetText:FlxText;
	var bindingText:FlxText;

	// State
	var curCat:Int = 0;
	var curEntry:Int = 0;
	var curSlot:Int = 0;
	var isBinding:Bool = false;
	var holdingTime:Float = 0;

	/**
	 * ★ 重置所有键位必须"按住"多久才生效（秒）。
	 *
	 * 以前这里是一按 RESET（默认 R）就 `ClientPrefs.resetKeys(false)`，把**全部**键盘键位
	 * 恢复成编译默认值（4K 的 DFJK → ASKL 就是这么来的），而且离开本界面时会
	 * `saveSettings()` 写进存档 —— 玩家在键位界面随手按一下 R 就再也回不去了。
	 * 用户反馈的"键位莫名其妙被重置成默认"就是这条路径。
	 *
	 * 现在跟同界面的其它破坏性操作保持一致（长按 Backspace 0.5s 删键、长按 ESC 2s 撤回）：
	 * 长按 RESET（移动端为 C 键）1.2 秒才重置，中途松手即取消，提示行会显示进度。
	 */
	static inline var RESET_HOLD_TIME:Float = 1.2;
	var resetHoldTime:Float = 0;
	/** 一次长按只重置一次；松手后才重新武装（防止一直按着反复清） */
	var resetArmed:Bool = true;

	/**
	 * ★ 刚进入界面后的"宽限期"（秒）：这段时间内完全不累计重置长按。
	 *
	 * 为什么必须有它（用户反馈"没点 R 也被重置"的另一条路径）：
	 * `controls.pressed('reset')` 读的是 **FlxG.keys 的全局状态**，而这个全局状态会被
	 * 移动端虚拟按键**直接改写** —— `mobile.flixel.FlxTypedButton.handleInput()` 在按钮
	 * 按下时会把 `IDs` 里对应的键写成 PRESSED，键位界面本身的虚拟摇杆（A/B = accept/back）
	 * 就在改写同一份状态。因此"刚打开界面时 reset 键恰好已经是按下"完全可能发生，
	 * 此时长按计数器从第一帧就开始跑，玩家一根手指都没碰 R，1.2 秒后键位就被清空了。
	 *
	 * 给一个短宽限期 + "必须松手才重新武装"，这条路径就彻底断掉：
	 * 宽限期内按住不算数，要么松手重按，要么从一开始就别按。
	 */
	static inline var RESET_INPUT_GRACE:Float = 0.35;
	var resetGrace:Float = RESET_INPUT_GRACE;

	override function create()
	{
		// ★ 关键：子状态的 cameras 必须是主相机（FlxG.camera），不能是最后一个相机
		//   `FlxG.cameras.list[length-1]` 在沉浸界面下 = chromeCam（AUTO_HIDE 自绘窗口条），
		//   跟 chromeCam 共用相机 → 渲染顺序：父状态 chrome 条先画 → 子状态键盘 UI 后画 → 顶栏自绘按钮
		//   被键盘设置等子状态 UI 盖住。改成主相机后：主相机先画（背景/UI/键盘），chromeCam 最后画 → 自绘按钮始终在最上层。
		cameras = [FlxG.camera];

		var bg:FlxSprite = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.scrollFactor.set();
		bg.alpha = 0.65;
		add(bg);

		// ===== Category tabs =====
		catTexts = [];
		var catStartY:Float = 15;
		for (cat in categories)
		{
			// Translate category name: use controls.lang if present, else use hardcoded fallback
			var catLangKey:String = 'key_' + cat.name.toLowerCase().replace('+', '').replace('k', 'k').replace('misc', 'misc');
			// Construct a lang key like 'key_1k', 'key_2k', 'key_4k', 'key_5k', 'key_ui', 'key_misc'
			var displayCatName:String = cat.name;
			switch (cat.name)
			{
				case '1K': displayCatName = tr('key_1k', 'controls', '1K', '1K');
				case '2K': displayCatName = tr('key_2k', 'controls', '2K', '2K');
				case '3K': displayCatName = tr('key_3k', 'controls', '3K', '3K');
				case '4K': displayCatName = tr('key_4k', 'controls', '4K', '4K');
				case '5K': displayCatName = tr('key_5k', 'controls', '5K', '5K');
				case '6k': displayCatName = tr('key_6k', 'controls', '6K', '6K');
				case '7k': displayCatName = tr('key_7k', 'controls', '7K', '7K');
				case '8k': displayCatName = tr('key_8k', 'controls', '8K', '8K');
				case '9k': displayCatName = tr('key_9k', 'controls', '9K', '9K');
				case '10k': displayCatName = tr('key_10k', 'controls', '10K', '10K');
				case 'UI': displayCatName = tr('ui', 'controls', '界面', 'UI');
				case 'Misc': displayCatName = tr('misc', 'controls', '其他', 'Misc');
				default: displayCatName = cat.name;
			}
			var t = new FlxText(0, catStartY, 0, '[' + displayCatName + ']', 18);
			t.setFormat(getFontPath(), 18, FlxColor.GRAY, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			t.borderSize = 1.5;
			t.scrollFactor.set();
			catTexts.push(t);
		}
		var catGap:Float = 6;
		var catX:Float = (FlxG.width - getTotalCatWidth(catGap)) / 2;
		for (t in catTexts)
		{
			t.x = catX;
			catX += t.width + catGap;
			add(t);
		}

		// ===== Hint (between category tabs and entry list) =====
		hintText = new FlxText(0, 0, FlxG.width, '', 20);
		hintText.setFormat(getFontPath(), 20, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hintText.borderSize = 1.5;
		hintText.scrollFactor.set();
		hintText.y = catStartY + 24;
		add(hintText);

		// ===== Slot indicator (below hint) =====
		slotText = new FlxText(0, 0, FlxG.width, '', 18);
		slotText.setFormat(getFontPath(), 18, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		slotText.borderSize = 1.5;
		slotText.scrollFactor.set();
		slotText.y = catStartY + 48;
		add(slotText);

		// ===== Entry list =====
		entryTexts = [];
		var entryStartY:Float = catStartY + 74;
		// Entry list x offset: avoid OptionsState's 20% width left navigation panel
		var entryStartX:Float = Std.int(FlxG.width * 0.2) + 20;
		for (i in 0...entries.length)
		{
			var t = new FlxText(entryStartX, entryStartY + 26 * i, 0, '', 20);
			t.setFormat(getFontPath(), 20, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			t.borderSize = 1.5;
			t.scrollFactor.set();
			t.visible = false;
			add(t);
			entryTexts.push(t);
		}

		// ===== Visual keyboard (non-interactive, shows key positions) =====
		buildKeyboard();

		// ===== Reset text =====
		// ★ 文案跟着行为走：现在是"长按"才重置（见 update 里的 RESET_HOLD_TIME）。
		var resetLabel:String = tr('reset_to_default', 'controls', '长按 R 重置为默认按键', 'Hold R to Reset to Default Keys');
		resetText = new FlxText(0, 0, FlxG.width, resetLabel, 14);
		resetText.setFormat(getFontPath(), 14, FlxColor.GRAY, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		resetText.borderSize = 1.5;
		resetText.scrollFactor.set();
		resetText.y = FlxG.height - 150;
		add(resetText);

		// ===== Binding overlay text =====
		bindingText = new FlxText(0, 0, FlxG.width, '', 24);
		bindingText.setFormat(getFontPath(), 24, FlxColor.CYAN, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		bindingText.borderSize = 2;
		bindingText.scrollFactor.set();
		bindingText.y = FlxG.height / 2 - 60;
		bindingText.visible = false;
		add(bindingText);

		updateView();

		addVirtualPad(OptionStateC, OptionStateC);
		addVirtualPadCamera(false);

		super.create();
	}

	function getTotalCatWidth(gap:Float):Float
	{
		var w:Float = 0;
		for (t in catTexts)
			w += t.width + gap;
		return w - gap;
	}

	function buildKeyboard()
	{
		var gap:Float = 4;
		var margin:Float = 30;
		var unit:Float = 99999;

		for (row in 0...widthUnits.length)
		{
			var totalUnits:Float = 0;
			for (u in widthUnits[row])
				totalUnits += u;
			var available:Float = FlxG.width - margin * 2 - gap * (widthUnits[row].length - 1);
			unit = Math.min(unit, available / totalUnits);
		}
		unit = Math.max(16, Math.min(50, unit));

		var maxRowWidth:Float = 0;
		for (row in 0...widthUnits.length)
		{
			var totalUnits:Float = 0;
			for (u in widthUnits[row])
				totalUnits += u;
			var rowWidth:Float = totalUnits * unit + gap * (widthUnits[row].length - 1);
			maxRowWidth = Math.max(maxRowWidth, rowWidth);
		}

		var keyHeight:Int = Std.int(Math.max(20, Math.min(38, unit * 0.8)));
		var rowGap:Float = 5;

		// Calculate total keyboard height to position it at bottom-100px
		// 6 rows, last row has #+ key at 2x height
		var totalHeight:Float = 5 * (keyHeight + rowGap) + keyHeight; // normal rows
		totalHeight += keyHeight + rowGap; // extra for #+ at row 5
		var startY:Float = FlxG.height - 100 - totalHeight;
		if (startY < 90) startY = 90; // don't overlap with entries

		var startX:Float = (FlxG.width - maxRowWidth) / 2;

		keySprites = [];
		keyBgList = [];

		for (row in 0...returnArray.length)
		{
			var x:Float = startX;
			var y:Float = startY + (keyHeight + rowGap) * row;
			for (col in 0...returnArray[row].length)
			{
				var w:Int = Std.int(unit * widthUnits[row][col]);
				var label:String = returnArray[row][col];
				if (label != null && label != '')
				{
					var h:Int = keyHeight;
					if (label == '#+')
						h = keyHeight * 2 + Std.int(rowGap);

					var sprGroup = new FlxSpriteGroup(x, y);
					var bg:FlxSprite = new FlxSprite(0, 0).makeGraphic(w, h, FlxColor.WHITE);
					bg.color = FlxColor.BLACK;
					bg.alpha = 0.35;
					bg.scrollFactor.set();
					sprGroup.add(bg);
					keyBgList.push({key: label, bg: bg});

					var display = displayArray[row][col];
					var txt = new FlxText(0, 0, w, display);
					txt.setFormat(getFontPath(), Std.int(Math.max(9, Math.min(16, h - 8))), FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
					txt.antialiasing = ClientPrefs.data.antialiasing;
					txt.borderSize = 1;
					txt.x = w / 2 - txt.width / 2;
					txt.y = h / 2 - txt.height / 2;
					sprGroup.add(txt);

					add(sprGroup);
					keySprites.push(sprGroup);
				}
				x += w + gap;
			}
		}
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		var accept = controls.ACCEPT;
		var right = controls.UI_RIGHT_P;
		var left = controls.UI_LEFT_P;
		var up = controls.UI_UP_P;
		var down = controls.UI_DOWN_P;
		var back = controls.BACK;
		// ★ 按住检测（不是 justPressed）：长按 RESET / 移动端 C 才重置全部键位，
		//   避免"随手按一下 R"就把用户所有键位清成默认值。
		// ★ 再加两道防误触：
		//   1) 虚拟摇杆只有在**真的显示且激活**时，它上面的 C 才算数 ——
		//      桌面端 needMobileControl=false 时整个 pad 是 visible/active = false，
		//      以前仍然读 buttonC.pressed（而且 buttonC 在别的 DPad/Action 组合下可能是 null），
		//      属于"看不见的按钮也能清空键位"；
		//   2) 进界面头 RESET_INPUT_GRACE 秒内不累计（见上面的字段注释）。
		var padResetHeld:Bool = virtualPad != null
			&& virtualPad.exists
			&& virtualPad.active
			&& virtualPad.visible
			&& virtualPad.buttonC != null
			&& virtualPad.buttonC.pressed;
		var resetBinds:Array<FlxKey> = ClientPrefs.keyBinds.get('reset');
		var resetBindingMissing:Bool = resetBinds == null || resetBinds.length == 0
			|| (resetBinds[0] == FlxKey.NONE && (resetBinds.length < 2 || resetBinds[1] == FlxKey.NONE));
		// Keep a physical recovery key when an empty/corrupt profile has erased RESET itself.
		// Holding R still goes through the normal 1.2s confirmation below.
		var keyResetHeld:Bool = !controls.controllerMode
			&& (controls.pressed('reset') || (resetBindingMissing && FlxG.keys.pressed.R));
		var resetHeld:Bool = padResetHeld || keyResetHeld;

		if (isBinding)
		{
			updateBinding(elapsed);
			return;
		}

		if (resetGrace > 0)
		{
			resetGrace -= elapsed;
			resetHeld = false;
			resetHoldTime = 0;
		}

		// ===== Browsing mode =====
		if (resetHeld && resetArmed)
		{
			resetHoldTime += elapsed;
			if (resetHoldTime >= RESET_HOLD_TIME)
			{
				resetHoldTime = 0;
				// 一直按着不放不要反复清：必须松手再按才重新武装
				resetArmed = false;
				FlxG.sound.play(Paths.sound('cancelMenu'));
				ClientPrefs.resetKeys(false);
				ClientPrefs.reloadVolumeKeys();
				// 重置后再给一次宽限期：避免"刚好还按着"在同一帧里重新开始计数
				resetGrace = RESET_INPUT_GRACE;
				updateView();
			}
			else
			{
				// 长按进度：写在这一行的提示上（松手会由下面的分支恢复成常规提示）
				var percent:Int = Std.int(Math.min(100, Math.max(0, resetHoldTime / RESET_HOLD_TIME * 100)));
				hintText.text = tr('keybinds_reset_holding', 'controls',
					'继续按住 RESET 重置为默认按键… ' + percent + '%',
					'Hold RESET to reset to default keys… ' + percent + '%');
			}
		}
		else if (!resetHeld)
		{
			resetArmed = true;
			if (resetHoldTime > 0)
			{
				// 松手（没按满）：什么都不做，恢复常规提示
				resetHoldTime = 0;
				updateView();
			}
		}

		if (left || right)
		{
			FlxG.sound.play(Paths.sound('scrollMenu'));
			curCat += right ? 1 : -1;
			if (curCat >= categories.length) curCat = 0;
			if (curCat < 0) curCat = categories.length - 1;
			curEntry = 0;
			updateView();
		}

		if (up || down)
		{
			var cat = categories[curCat];
			FlxG.sound.play(Paths.sound('scrollMenu'));
			curEntry += down ? 1 : -1;
			if (curEntry >= cat.len) curEntry = 0;
			if (curEntry < 0) curEntry = cat.len - 1;
			updateView();
		}

		if (FlxG.keys.justPressed.TAB)
		{
			FlxG.sound.play(Paths.sound('scrollMenu'));
			curSlot = (curSlot == 0) ? 1 : 0;
			updateView();
		}

		if (accept)
		{
			startBinding();
		}

		if (back)
		{
			// 关闭前先隐藏自身，防止销毁过程中黑色键盘背景闪烁残留
			visible = false;
			ClientPrefs.saveSettings();
			close();
		}
	}

	function startBinding()
	{
		isBinding = true;
		holdingTime = 0;
		bindingText.visible = true;
		var overlay:String = Language.get('keybinds_binding_overlay', 'controls');
		var escCancel:String = Language.get('keybinds_esc_cancel', 'controls');
		var bkspDelete:String = Language.get('keybinds_bksp_delete', 'controls');
		// 中文兜底：当翻译缺失（返回原key或带404）时用预设中文
		var isZH:Bool = ClientPrefs.data.language.indexOf('中文') > -1 || ClientPrefs.data.language.toLowerCase().indexOf('chinese') > -1;
		if (overlay == 'keybinds_binding_overlay' || overlay == 'keybinds_binding_overlay (404)')
			overlay = isZH ? '[ 请在这里键入你的按键 ]' : '[ Press any key to bind ]';
		if (escCancel == 'keybinds_esc_cancel' || escCancel == 'keybinds_esc_cancel (404)')
			escCancel = isZH ? '（长按ESC 2秒撤回修改）' : '(Hold ESC for 2s to cancel)';
		if (bkspDelete == 'keybinds_bksp_delete' || bkspDelete == 'keybinds_bksp_delete (404)')
			bkspDelete = isZH ? '（长按Backspace删除按键）' : '(Hold Backspace to delete)';
		bindingText.text = overlay + '\n' + escCancel + '\n' + bkspDelete;
		updateView();
	}

	function updateBinding(elapsed:Float)
	{
		// Hold ESC to cancel
		if (FlxG.keys.pressed.ESCAPE)
		{
			holdingTime += elapsed;
			if (holdingTime > 2.0)
			{
				FlxG.sound.play(Paths.sound('cancelMenu'));
				isBinding = false;
				bindingText.visible = false;
				updateView();
			}
			return;
		}
		// Hold Backspace to delete
		if (FlxG.keys.pressed.BACKSPACE)
		{
			holdingTime += elapsed;
			if (holdingTime > 0.5)
			{
				var entry = entries[categories[curCat].first + curEntry];
				var binds:Array<FlxKey> = ClientPrefs.keyBinds.get(entry.key);
				if (binds != null)
				{
					binds[curSlot] = FlxKey.NONE;
					ClientPrefs.clearInvalidKeys(entry.key);
				}
				isBinding = false;
				bindingText.visible = false;
				FlxG.sound.play(Paths.sound('cancelMenu'));
				updateView();
			}
			return;
		}

		holdingTime = 0;

		if (FlxG.keys.justPressed.ANY || FlxG.keys.justReleased.ANY)
		{
			var keyPressed:Int = FlxG.keys.firstJustPressed();
			var keyReleased:Int = FlxG.keys.firstJustReleased();

			if (keyPressed > -1 && keyPressed != FlxKey.ESCAPE && keyPressed != FlxKey.BACKSPACE)
			{
				var entry = entries[categories[curCat].first + curEntry];
				var binds:Array<FlxKey> = ClientPrefs.keyBinds.get(entry.key);
				if (binds != null)
				{
					binds[curSlot] = keyPressed;
					if (binds[0] == binds[1])
						binds[1 - curSlot] = FlxKey.NONE;
					ClientPrefs.clearInvalidKeys(entry.key);
				}
				FlxG.sound.play(Paths.sound('confirmMenu'));
				isBinding = false;
				bindingText.visible = false;
				updateView();
			}
			else if (keyReleased > -1 && (keyReleased == FlxKey.ESCAPE || keyReleased == FlxKey.BACKSPACE))
			{
				var entry = entries[categories[curCat].first + curEntry];
				var binds:Array<FlxKey> = ClientPrefs.keyBinds.get(entry.key);
				if (binds != null)
				{
					binds[curSlot] = keyReleased;
					if (binds[0] == binds[1])
						binds[1 - curSlot] = FlxKey.NONE;
					ClientPrefs.clearInvalidKeys(entry.key);
				}
				FlxG.sound.play(Paths.sound('confirmMenu'));
				isBinding = false;
				bindingText.visible = false;
				updateView();
			}
		}
	}

	function updateView()
	{
		for (i in 0...catTexts.length)
			catTexts[i].color = (i == curCat) ? FlxColor.WHITE : FlxColor.GRAY;

		var cat = categories[curCat];
		for (i in 0...entryTexts.length)
			entryTexts[i].visible = false;

		var catColor:FlxColor = catHighlightColors[curCat];

		for (i in 0...cat.len)
		{
			var idx = cat.first + i;
			var entry = entries[idx];
			var binds:Array<FlxKey> = ClientPrefs.keyBinds.get(entry.key);
			var s1:String = (binds != null) ? InputFormatter.getKeyName(binds[0]) : '---';
			var s2:String = (binds != null) ? InputFormatter.getKeyName(binds[1]) : '---';
			var displayName:String = Language.get('kb_' + entry.key, 'controls');
			if (displayName == 'kb_' + entry.key || displayName == 'kb_' + entry.key + ' (404)') displayName = entry.name;
			var t = entryTexts[i];
			t.text = (i == curEntry ? '> ' : '  ') + displayName + '  [' + s1 + ' / ' + s2 + ']';
			t.visible = true;
			t.color = (i == curEntry) ? FlxColor.CYAN : FlxColor.WHITE;
		}

		var curEntryIdx = cat.first + curEntry;
		var curEntryData = entries[curEntryIdx];
		var curBinds:Array<FlxKey> = ClientPrefs.keyBinds.get(curEntryData.key);
		var curS1:String = (curBinds != null) ? InputFormatter.getKeyName(curBinds[0]) : '---';
		var curS2:String = (curBinds != null) ? InputFormatter.getKeyName(curBinds[1]) : '---';
		slotText.text = 'Slot 1: ' + curS1 + (curSlot == 0 ? ' <' : '  ') + '    |    Slot 2: ' + curS2 + (curSlot == 1 ? ' <' : '  ');

		// ===== Keyboard highlighting:
		// 1) Reset all keys to default dark background
		// 2) Highlight ALL keys bound in the current category with category color
		// 3) Override current entry's keys with WHITE background for emphasis
		for (pair in keyBgList)
		{
			pair.bg.color = FlxColor.BLACK;
			pair.bg.alpha = 0.35;
		}

		// Step 2: highlight all bound keys in the current category using category color
		for (i in 0...cat.len)
		{
			var eIdx = cat.first + i;
			var eEntry = entries[eIdx];
			var eBinds:Array<FlxKey> = ClientPrefs.keyBinds.get(eEntry.key);
			if (eBinds == null) continue;
			for (slot in 0...2)
			{
				var fk:FlxKey = eBinds[slot];
				if (fk != FlxKey.NONE)
				{
					var kn:String = InputFormatter.getKeyName(fk);
					for (pair in keyBgList)
					{
						if (pair.key == kn)
						{
							pair.bg.color = catColor;
							pair.bg.alpha = 0.7;
						}
					}
				}
			}
		}

		// Step 3: highlight current entry's bound keys with WHITE background for emphasis
		if (curBinds != null)
		{
			for (slot in 0...2)
			{
				var fk:FlxKey = curBinds[slot];
				if (fk != FlxKey.NONE)
				{
					var kn:String = InputFormatter.getKeyName(fk);
					for (pair in keyBgList)
					{
						if (pair.key == kn)
						{
							pair.bg.color = FlxColor.WHITE;
							pair.bg.alpha = 0.95;
						}
					}
				}
			}
			// Also highlight the currently active slot key with slightly brighter white
			var curSlotKeyName:String = (curSlot == 0) ? curS1 : curS2;
			if (curSlotKeyName != '---')
			{
				for (pair in keyBgList)
				{
					if (pair.key == curSlotKeyName)
					{
						pair.bg.color = FlxColor.WHITE;
						pair.bg.alpha = 1.0;
					}
				}
			}
		}

		if (isBinding)
			hintText.text = '';
		else
			hintText.text = tr('keybinds_browse_hint', 'controls',
				'← → 分类 | ↑ ↓ 条目 | Tab 插槽 | Enter 绑定 | ESC 返回',
				'LEFT/RIGHT Category | UP/DOWN Entry | TAB Slot | ENTER Bind | ESC Back');
	}

}
