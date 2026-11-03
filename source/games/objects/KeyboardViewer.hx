package games.objects;

import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Shape;
import openfl.utils.Assets;

import flixel.graphics.FlxGraphic;
import flixel.input.keyboard.FlxKey;
import flixel.util.FlxSave;

import general.backend.InputFormatter;

import games.backend.Song;

/**
 * 键盘反馈（游戏内屏幕键盘）。
 *
 * ★ 全部外观参数都从 `ClientPrefs.data.keyboard*` 读取，设置项划分照 KeyDisplay 那套模板：
 *   基本（大小/间距/透明度）、各键颜色（10K 逐键）、长条（尺寸/速度/间隔/颜色）、
 *   消失效果、统计（KPS/TOT 与配色）、布局（偏移/缩放）。
 *
 * ★ 编辑入口是 `options/base/KeyboardViewerSubState.hx`：它以 `preview = true` 建一个
 *   本类的实例当实时预览，并直接铺 10K，方便逐键/批量改色。
 *
 * 兼容性：`new KeyboardViewer(x, y)` 的老调用（PlayState / EditorPlayState / NoteOffsetState）
 * 行为不变；预览相关的新参数都是可选的。
 */
class KeyboardViewer extends FlxSpriteGroup
{
	public var noteArrays:Array<Array<TimeDis>> = []; // 存储所有键位的数组
	public var keyAlphas:Array<KeyButtonAlpha> = []; // 存储键位透明度对象
	public var keyTexts:Array<FlxText> = []; // 存储键位文本对象

	/** 每个按键的方块（预览界面用它做点击命中的选中） */
	public var keyButtons:Array<KeyButton> = [];
	/** 键位描边（单独一层，颜色可以跟常态色不同 —— 用户要的"描边颜色"） */
	public var keyBorders:Array<KeyBorder> = [];
	/** KPS / total 两个统计块 */
	public var statBlocks:Array<KeyButton> = [];
	/** KPS / total 两个标题文字 */
	public var statTitles:Array<FlxText> = [];

	public var _x:Float;
	public var _y:Float;
	public var _width:Float;
	public var _height:Float;
	public var kpsText:FlxText;
	public var totalText:FlxText;

	public var keys:Int = 4; // 默认键位数

	/** 预览模式（设置界面用）：强制键数、允许模拟按下；不参与成绩统计 */
	public var preview:Bool = false;

	var total:Int = 0;

	/** 本实例实际使用的按键大小/间距（供 TimeDis 等计算列位置） */
	public var colSize:Int = 50;
	public var colGap:Int = 4;
	var statH:Int = 50;

	public static var instance:KeyboardViewer;

	/**
	 * 长条/高亮用的"当前时间"（毫秒）。
	 *
	 * ★ 游戏内用 `Conductor.songPosition`（跟随歌曲、暂停会停）；
	 *   但设置界面的预览里 Conductor 没在跑（songPosition 恒为 0），长条会永远卡在 0 高度、
	 *   看起来像"设置项没生效"。预览模式改用真实时间戳，长条就会照常上漂。
	 */
	public static function now():Float
	{
		if (instance != null && instance.preview)
			return haxe.Timer.stamp() * 1000;
		return Conductor.songPosition;
	}

	public function new(X:Float, Y:Float, ?forceKeys:Int = 0, ?previewMode:Bool = false)
	{
		super();
		instance = this;
		moves = false;

		preview = previewMode;

		colSize = Std.int(FlxMath.bound(ClientPrefs.data.keyboardKeySize, 8, 300));
		colGap = Std.int(FlxMath.bound(ClientPrefs.data.keyboardKeySpacing, 0, 100));
		KeyButton.size = colSize;
		KeyButton.gap = colGap;
		KeyButton.bgAlphaMul = ClientPrefs.data.keyboardAlpha;
		KeyButton.bgColor = ClientPrefs.keyboardBG();

		statH = ClientPrefs.data.keyboardStatHeight > 0 ? ClientPrefs.data.keyboardStatHeight : colSize;

		keys = resolveKeys(forceKeys);

		// 布局偏移/缩放（旧版为 0 / 1，默认观感不变）
		X = X + ClientPrefs.data.keyboardOffsetX;
		Y = Y + ClientPrefs.data.keyboardOffsetY;
		var sc:Float = ClientPrefs.data.keyboardScale;
		if (sc > 0 && sc != 1)
			scale.set(sc, sc);
		// ★ 不调 updateHitbox()：flixel 5.9 里它会把 offset/origin 设成居中偏移，
		//   带 scale 的组会因此整体平移（设置界面的预览就被推到了右半屏）。
		offset.set(0, 0);
		origin.set(0, 0);

		_x = X;
		_y = Y;

		for (i in 0...keys)
			noteArrays.push([]);

		_width = (colSize + colGap) * keys;
		_height = statH + colGap + colSize;

		buildKeys();
		buildStats();

		// 长条位图（宽度可单独配，高度默认键位大小 ×3 = 旧版）
		DisBitmap.cache(barWidthPx(), barHeightPx());

		if (FlxG.save != null && FlxG.save.data != null && FlxG.save.data.keyboardtotal != null)
			total = FlxG.save.data.keyboardtotal;
	}

	/** 键数：显式指定 > 预览配置 > 当前谱面 mania+1 > 4 */
	function resolveKeys(forceKeys:Int):Int
	{
		if (forceKeys > 0) return forceKeys;
		if (preview)
		{
			var p:Int = ClientPrefs.data.keyboardPreviewKeys;
			if (p > 0) return Std.int(FlxMath.bound(p, 1, 10));
		}
		if (PlayState.SONG != null) return PlayState.SONG.mania + 1;
		return 4;
	}

	inline function barWidthPx():Int
	{
		var w:Int = ClientPrefs.data.keyboardBarWidth;
		return (w > 0) ? Std.int(FlxMath.bound(w, 1, 400)) : colSize;
	}

	inline function barHeightPx():Int
	{
		var h:Int = ClientPrefs.data.keyboardBarHeight;
		return (h > 0) ? Std.int(FlxMath.bound(h, 1, 1200)) : colSize * 3;
	}

	// ===================== 建键位 / 统计 =====================

	function buildKeys():Void
	{
		var textArray:Array<String> = createArray();

		for (i in 0...keys)
		{
			var bx:Float = _x + (colSize + colGap) * i;

			// 常态色逐键独立（v2）：底色只画填充，描边单独一层
			var btn:KeyButton = new KeyButton(bx, _y, colSize, colSize, ClientPrefs.keyboardLaneColor(i), true);
			keyButtons.push(btn);
			add(btn);

			var bdr:KeyBorder = new KeyBorder(bx, _y, colSize, ClientPrefs.keyboardKeyBorder(i));
			keyBorders.push(bdr);
			add(bdr);

			// 按下时的高亮块：颜色按该键的「按下色」取（未设时回退常态色 = 旧版观感）
			var hi:KeyButtonAlpha = new KeyButtonAlpha(bx, _y, colSize, ClientPrefs.keyboardPress(i));
			keyAlphas.push(hi);
			add(hi);

			// 键位名
			var name:String = (i < textArray.length) ? textArray[i] : '';
			var t:FlxText = new FlxText(bx + colSize / 2, _y + colSize / 2, 50, name, 10, false);
			t.setFormat(Assets.getFont("assets/fonts/montserrat.ttf").fontName, Std.int(Math.max(8, colSize * 0.4)), FlxColor.WHITE, CENTER,
				FlxTextBorderStyle.OUTLINE, 0x00);
			t.x -= t.width / 2;
			t.y -= t.height / 2;
			t.color = ClientPrefs.keyboardKeyText(i); // 文本色也逐键独立
			t.alpha = ClientPrefs.data.keyboardAlpha;
			t.moves = false;
			keyTexts.push(t);
			add(t);
		}
	}

	function buildStats():Void
	{
		var statAlpha:Float = ClientPrefs.data.keyboardStatAlpha;
		// 统计块尺寸沿用**原有算法**（跟着按键大小自适应），不另外做宽高设置项：
		// 用户实测自己调宽高会把整块键盘反馈挤歪，所以这块只留颜色和透明度。
		var bigW:Int = Std.int((colSize * 2 + colGap) * (keys / 4));
		if (bigW < 20) bigW = colSize * 2 + colGap;
		var startX:Float = _x + (_width - bigW * 2 - colGap) / 2;
		var y:Float = _y + colSize + colGap;

		var titles:Array<String> = ['KPS', 'total'];

		for (i in 0...2)
		{
			var bx:Float = startX + (bigW + colGap) * i;
			var blk:KeyButton = new KeyButton(bx, y, bigW, statH, ClientPrefs.keyboardStatColor(i));
			blk.alpha = statAlpha;
			statBlocks.push(blk);
			add(blk);

			if (!ClientPrefs.data.keyboardStats)
				blk.visible = false;

			var t:FlxText = new FlxText(bx + bigW / 2, y + statH / 4, bigW, titles[i], 20, false);
			t.setFormat(Assets.getFont("assets/fonts/montserrat.ttf").fontName, Std.int(Math.max(9, colSize * 0.5)), FlxColor.WHITE, CENTER,
				FlxTextBorderStyle.OUTLINE, 0x00);
			t.x -= t.width / 2;
			t.y -= t.height / 2;
			t.color = ClientPrefs.keyboardStatText(i);
			t.alpha = statAlpha;
			t.antialiasing = ClientPrefs.data.antialiasing;
			t.moves = false;
			t.visible = ClientPrefs.data.keyboardStats;
			statTitles.push(t);
			add(t);
		}

		kpsText = new FlxText(startX + bigW / 2, y + statH / 5 * 3.5, bigW, '0', 15, false);
		kpsText.setFormat(Assets.getFont("assets/fonts/montserrat.ttf").fontName, Std.int(Math.max(8, colSize * 0.3)), FlxColor.WHITE, CENTER,
			FlxTextBorderStyle.OUTLINE, 0x00);
		kpsText.x -= kpsText.width / 2;
		kpsText.y -= kpsText.height / 2;
		kpsText.color = ClientPrefs.keyboardStatText(0);
		kpsText.alpha = statAlpha;
		kpsText.moves = false;
		kpsText.visible = ClientPrefs.data.keyboardStats;
		add(kpsText);

		totalText = new FlxText(startX + bigW + colGap + bigW / 2, y + statH / 5 * 3.5, bigW, Std.string(total), 15, false);
		totalText.setFormat(Assets.getFont("assets/fonts/montserrat.ttf").fontName, Std.int(Math.max(8, colSize * 0.3)), FlxColor.WHITE, CENTER,
			FlxTextBorderStyle.OUTLINE, 0x00);
		totalText.x -= totalText.width / 2;
		totalText.y -= totalText.height / 2;
		totalText.color = ClientPrefs.keyboardStatText(1);
		totalText.alpha = statAlpha;
		totalText.moves = false;
		totalText.visible = ClientPrefs.data.keyboardStats;
		add(totalText);
	}

	/**
	 * **只刷新颜色**，不重建任何 sprite。
	 * 切主题 / 改颜色走这条 —— 重建（refresh）容易在那一瞬间把界面搞花
	 * （用户反馈"设置主题时样式全崩了"）。
	 */
	public function applyColors():Void
	{
		for (i in 0...keyButtons.length)
		{
			keyButtons[i].color = ClientPrefs.keyboardLaneColor(i);
			if (i < keyBorders.length) keyBorders[i].color = ClientPrefs.keyboardKeyBorder(i);
			if (i < keyAlphas.length) keyAlphas[i].color = ClientPrefs.keyboardPress(i);
			if (i < keyTexts.length) keyTexts[i].color = ClientPrefs.keyboardKeyText(i);
		}
		for (i in 0...statBlocks.length)
		{
			statBlocks[i].color = ClientPrefs.keyboardStatColor(i);
			if (i < statTitles.length) statTitles[i].color = ClientPrefs.keyboardStatText(i);
		}
		if (kpsText != null) kpsText.color = ClientPrefs.keyboardStatText(0);
		if (totalText != null) totalText.color = ClientPrefs.keyboardStatText(1);
	}

	/**
	 * 设置界面改了配置之后，用它把整个预览按当前 ClientPrefs 重建。
	 * 预览与游戏内共用同一套取值入口，所以刷完看到的就是实机效果。
	 * ★ 调用方若想画「默认样式」那一排，先 `ClientPrefs.previewUseDefault = true` 再调它，
	 *   画完记得复位。
	 */
	public function refresh():Void
	{
		for (b in keyButtons) { remove(b, true); b.destroy(); }
		for (b in keyBorders) { remove(b, true); b.destroy(); }
		for (a in keyAlphas) { remove(a, true); a.destroy(); }
		for (t in keyTexts) { remove(t, true); t.destroy(); }
		keyButtons = []; keyBorders = []; keyAlphas = []; keyTexts = [];

		for (b in statBlocks) { remove(b, true); b.destroy(); }
		for (t in statTitles) { remove(t, true); t.destroy(); }
		if (kpsText != null) { remove(kpsText, true); kpsText.destroy(); kpsText = null; }
		if (totalText != null) { remove(totalText, true); totalText.destroy(); totalText = null; }
		statBlocks = []; statTitles = [];

		// KeyButton 的尺寸/间距/透明度是静态的，TimeDis 也依赖它们，这里一并同步
		colSize = Std.int(FlxMath.bound(ClientPrefs.data.keyboardKeySize, 8, 300));
		colGap = Std.int(FlxMath.bound(ClientPrefs.data.keyboardKeySpacing, 0, 100));
		KeyButton.size = colSize;
		KeyButton.gap = colGap;
		KeyButton.bgAlphaMul = ClientPrefs.data.keyboardAlpha;
		KeyButton.bgColor = ClientPrefs.keyboardBG();
		statH = ClientPrefs.data.keyboardStatHeight > 0 ? ClientPrefs.data.keyboardStatHeight : colSize;

		_width = (colSize + colGap) * keys;
		_height = statH + colGap + colSize;

		DisBitmap.cache(barWidthPx(), barHeightPx());

		buildKeys();
		buildStats();
	}

	// ===================== 运行时 =====================

	/** 上一次创建长条的时间（Conductor.songPosition，ms），用于 keyboardBarInterval */
	var lastBarTime:Float = -999999;

	public function pressed(key:Int)
	{
		if (key < keyAlphas.length)
		{
			keyAlphas[key].alpha = ClientPrefs.data.keyboardPressedAlpha;
			// 按下时的文字色：逐键的「按下文本色」，没设过才按亮度自动反色
			keyTexts[key].color = ClientPrefs.keyboardPressText(key);
		}

		if (!preview && PlayState.replayMode != true)
			total++;
		if (totalText != null) totalText.text = Std.string(total);
		hitArray.unshift(Date.now());

		if (!ClientPrefs.data.keyboardTimeDisplay)
			return;

		var now:Float = KeyboardViewer.now();
		var intervalMs:Float = ClientPrefs.data.keyboardBarInterval * 1000;
		if (intervalMs > 0 && now - lastBarTime < intervalMs)
			return;
		lastBarTime = now;

		var obj:TimeDis = new TimeDis(key, now, _x, _y, colSize, colGap);
		add(obj);

		if (key < noteArrays.length)
		{
			var arr = noteArrays[key];
			if (arr.length > 0 && arr[arr.length - 1].endTime == -999999)
				arr[arr.length - 1].endTime = now;
			arr.push(obj);
		}
	}

	public function released(key:Int)
	{
		if (key < keyAlphas.length)
		{
			keyAlphas[key].alpha = keyAlphas[key].idleAlpha;
			keyTexts[key].color = ClientPrefs.keyboardKeyText(key);
		}

		if (key < noteArrays.length)
		{
			var arr = noteArrays[key];
			if (arr.length > 0 && arr[arr.length - 1].endTime == -999999)
				arr[arr.length - 1].endTime = KeyboardViewer.now();
		}
	}

	/** 预览用：模拟按一下再松开（设置界面里点键位/长条时能看到真实反馈效果） */
	public function flash(key:Int):Void
	{
		if (key < 0 || key >= keys) return;
		pressed(key);
		released(key);
	}

	public function save()
	{
		if (preview) return; // 预览不写总击键数
		if (FlxG.save == null || FlxG.save.data == null) return;
		FlxG.save.data.keyboardtotal = total;
		FlxG.save.flush();
	}

	public function createArray():Array<String>
	{
		var array:Array<String> = [];
		var mania:Int = keys - 1;

		if (mania == 3)
		{
			array.push(InputFormatter.getKeyName(bindAt('note_left', 0)));
			array.push(InputFormatter.getKeyName(bindAt('note_down', 0)));
			array.push(InputFormatter.getKeyName(bindAt('note_up', 0)));
			array.push(InputFormatter.getKeyName(bindAt('note_right', 0)));
			return array;
		}

		for (i in 0...keys)
		{
			var keysArray:Array<FlxKey> = Controls.instance != null ? Controls.instance.keyboardBinds.get('${mania}_key_${i}') : null;
			if (keysArray != null && keysArray.length > 0)
				array.push(InputFormatter.getKeyName(keysArray[0]));
			else
				array.push('?');
		}
		return array;
	}

	function bindAt(name:String, idx:Int):FlxKey
	{
		if (Controls.instance == null || Controls.instance.keyboardBinds == null) return FlxKey.NONE;
		var arr:Array<FlxKey> = Controls.instance.keyboardBinds.get(name);
		if (arr == null || arr.length <= idx) return FlxKey.NONE;
		return arr[idx];
	}

	public function removeObj(obj:TimeDis)
	{
		if (obj.line < noteArrays.length)
			noteArrays[obj.line].remove(obj);
		remove(obj, true);
		obj.destroy();
	}

	public var kps:Int = 0;
	public var kpsCheck:Int = 0;
	public var hitArray:Array<Date> = [];

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		var i = hitArray.length - 1;
		while (i >= 0)
		{
			var time:Date = hitArray[i];
			if (time != null && time.getTime() + 1000 < Date.now().getTime())
				hitArray.remove(time);
			else
				i = -1; // 跳出循环
			i--;
		}
		kps = hitArray.length;

		if (kpsCheck != kps)
		{
			kpsCheck = kps;
			if (kpsText != null) kpsText.text = Std.string(kps);
		}
	}
}

/** 颜色解析小工具（HEX 与颜色名都吃；空串回退 fallback） */
class StatColor
{
	public static function of(raw:String, fallback:FlxColor = FlxColor.WHITE):FlxColor
	{
		if (raw == null || raw == '') return fallback;
		return CoolUtil.colorFromString(raw);
	}
}

/** 按键底色方块（也用于统计块底） */
class KeyButton extends FlxSprite
{
	/** 当前按键大小（KeyboardViewer 构造时同步；TimeDis / 高亮块共用） */
	public static var size:Int = 50;
	/** 当前按键间距 */
	public static var gap:Int = 4;
	/** 底色透明度系数（= ClientPrefs.data.keyboardAlpha，旧版行为） */
	public static var bgAlphaMul:Float = 0.8;
	/** 底色 */
	public static var bgColor:FlxColor = FlxColor.WHITE;

	public function new(X:Float, Y:Float, Width:Int, Height:Int, ?Color:FlxColor = null, ?FillOnly:Bool = false)
	{
		super(X, Y);

		var bgAlpha = 0.3 * bgAlphaMul;
		var lineAlpha = 0.8 * bgAlphaMul;

		var shape:Shape = new Shape();
		var radius:Int = Std.int(Math.min(Width, Height) / 3);
		if (radius < 1) radius = 1;
		if (!FillOnly)
		{
			// 统计块那种：填充 + 描边一张图（描边跟填充同色）
			shape.graphics.lineStyle(2, FlxColor.WHITE, lineAlpha);
			shape.graphics.drawRoundRect(0, 0, Width, Height, radius, radius);
			shape.graphics.lineStyle();
		}
		shape.graphics.beginFill(FlxColor.WHITE, bgAlpha);
		shape.graphics.drawRoundRect(0, 0, Width, Height, radius, radius);
		shape.graphics.endFill();

		var bd:BitmapData = new BitmapData(Width, Height, 0x00FFFFFF);
		bd.draw(shape);

		loadGraphic(bd);
		antialiasing = ClientPrefs.data.antialiasing;
		// ★ 底色按"这一个"键传进来（v2 里常态色是逐键独立的），不传才用静态默认值
		color = (Color == null) ? bgColor : Color;
		moves = false;
	}
}

/** 只有描边的键位外框 —— 描边颜色可以跟常态色不同（"描边颜色"这一项靠它） */
class KeyBorder extends FlxSprite
{
	public function new(X:Float, Y:Float, Size:Int, ?Color:FlxColor = null)
	{
		super(X, Y);

		var radius:Int = Std.int(Size / 3);
		if (radius < 1) radius = 1;

		var shape:Shape = new Shape();
		shape.graphics.lineStyle(2, FlxColor.WHITE, 0.8 * KeyButton.bgAlphaMul);
		shape.graphics.drawRoundRect(0, 0, Size, Size, radius, radius);

		var bd:BitmapData = new BitmapData(Size, Size, true, 0);
		bd.draw(shape);

		loadGraphic(bd);
		antialiasing = ClientPrefs.data.antialiasing;
		color = (Color == null) ? FlxColor.WHITE : Color;
		moves = false;
	}
}

/** 按下时的高亮块（颜色由调用方按该键的配置传入） */
class KeyButtonAlpha extends FlxSprite
{
	public var tween = FlxTween;

	/**
	 * 未按下时停留的透明度。
	 * 游戏内为 0（完全看不见，旧版行为）；设置界面的预览里会设成 0.7，
	 * 这样玩家能一眼看到 10K 每个键各自被设成了什么颜色。
	 */
	public var idleAlpha:Float = 0;

	public function new(X:Float, Y:Float, ?Size:Int = 0, ?Color:FlxColor = 0xFFFFFFFF)
	{
		super(X, Y);

		var size:Int = (Size > 0) ? Size : KeyButton.size;
		var radius:Int = Std.int(size / 3);
		if (radius < 1) radius = 1;

		var shape:Shape = new Shape();
		shape.graphics.beginFill(FlxColor.WHITE, 1);
		shape.graphics.drawRoundRect(0, 0, size, size, radius, radius);
		shape.graphics.endFill();

		var bd:BitmapData = new BitmapData(size, size, 0x00FFFFFF);
		bd.draw(shape);

		loadGraphic(bd);
		antialiasing = ClientPrefs.data.antialiasing;
		color = Color;
		alpha = idleAlpha;
		moves = false;
	}
}

/** 按下后向上漂的长条 */
class TimeDis extends FlxSprite
{
	public var startTime:Float;
	public var endTime:Float = -999999;
	public var line:Int;

	var durationTime:Float = 500;
	var maxH:Float = 150;
	var removing:Bool = false;
	/** 创建它的 KeyboardViewer（退出时用 instance 会串到别的实例上，所以自己记住） */
	var owner:KeyboardViewer;

	public function new(Line:Int, Time:Float, X:Float, Y:Float, ?colSize:Int = 0, ?colGap:Int = 0)
	{
		this.line = Line;
		owner = KeyboardViewer.instance;

		var size:Int = (colSize > 0) ? colSize : KeyButton.size;
		var gap:Int = (colGap > 0) ? colGap : KeyButton.gap;

		// 用户可把长条单独调宽/调高；默认（0）等于旧版：宽 = 键位宽，高 = 键位大小 ×3
		var bw:Int = ClientPrefs.data.keyboardBarWidth > 0 ? ClientPrefs.data.keyboardBarWidth : size;
		var bh:Int = ClientPrefs.data.keyboardBarHeight > 0 ? ClientPrefs.data.keyboardBarHeight : size * 3;

		maxH = DisBitmap.Height;
		if (maxH <= 0) maxH = bh;

		// 长条比键位窄时居中在键位上
		var colX:Float = X + Line * (size + gap) + (size - bw) / 2;
		super(colX, Y - 4 - maxH);

		this.startTime = Time;

		// 速度倍率：duration = 滞留时长 / 速度（默认 1 = 旧版）
		var speed:Float = ClientPrefs.data.keyboardBarSpeed;
		if (speed < 0.05) speed = 0.05;
		durationTime = Math.max(30, ClientPrefs.data.keyboardTime / speed);

		frames = Cache.getFrame('keyboardViewer');
		_frame.frame.height = 1;
		color = ClientPrefs.keyboardBarLaneColor(Line);
		alpha = ClientPrefs.data.keyboardBarAlpha;
		moves = false;
	}

	var saveTime:Float;

	override function update(elapsed:Float)
	{
		if (removing)
		{
			// 'fade' 模式：先渐隐再回收
			var spd:Float = ClientPrefs.data.keyboardBarFadeSpeed;
			if (spd < 0.01) spd = 0.01;
			alpha -= (spd * 0.15 + 1.2) * elapsed * 3;
			if (alpha <= 0.02)
			{
				alpha = 0;
				if (owner != null) owner.removeObj(this);
			}
			return;
		}

		var pos:Float = KeyboardViewer.now();

		if (endTime == -999999)
		{
			_frame.frame.y = (1 - ((pos - startTime) / durationTime)) * maxH;
			_frame.frame.height = ((pos - startTime) / durationTime) * maxH;
			offset.y = -(1 - ((pos - startTime) / durationTime)) * maxH;
			if (_frame.frame.y < 0)
				_frame.frame.y = 0;
			if (pos - startTime > durationTime)
				offset.y = 0;
			saveTime = pos;
		}
		else
		{
			if (endTime - startTime < durationTime)
				_frame.frame.y = (1 - ((pos - startTime) / durationTime)) * maxH;
			else
				_frame.frame.y = (1 - ((pos - (endTime - durationTime)) / durationTime)) * maxH;
			offset.y -= -((pos - saveTime) / durationTime) * maxH;
			saveTime = pos;
		}
		if (_frame.frame.height > maxH)
			_frame.frame.height = maxH;
		if (_frame.frame.height <= 0)
			_frame.frame.height = 1; // fix bug

		if (endTime != -999999 && pos - endTime > durationTime)
		{
			if (ClientPrefs.data.keyboardBarDisappearMode == 'fade')
				removing = true; // 下一帧起渐隐
			else if (owner != null)
				owner.removeObj(this);
		}
	}
}

/** 长条的渐变位图（每个键共用一张；尺寸随配置重建） */
class DisBitmap extends Bitmap
{
	static public var Width:Int = 50;
	static public var Height:Int = 150;

	/** 按当前配置重建位图与缓存帧 */
	static public function cache(width:Int, height:Int):Void
	{
		if (width < 1) width = 1;
		if (height < 1) height = 1;

		// ★ 判断"缓存里有没有"必须用 exists，**不能**用 `Cache.getFrame(...) != null`：
		//   第一次进设置界面时这个 key 还没被缓存过，而历史上 getFrame 对未命中的 key
		//   直接解引用 null 崩溃（现已修好，但 exists 才是这里该用的语义）。
		if (Width == width && Height == height && Cache.currentTrackedFrames.exists('keyboardViewer'))
			return;

		Width = width;
		Height = height;

		var bd:BitmapData = new BitmapData(Width, Height, true, 0);
		var shape:Shape = new Shape();

		var soft:Int = Std.int(Height / 10);
		if (soft < 1) soft = 1;
		for (i in 0...soft)
		{
			shape.graphics.beginFill(FlxColor.WHITE, i / soft);
			shape.graphics.drawRect(0, i, Width, 1);
			shape.graphics.endFill();
		}
		shape.graphics.beginFill(FlxColor.WHITE);
		shape.graphics.drawRect(0, soft, Width, Height - soft);
		shape.graphics.endFill();
		bd.draw(shape);

		var spr:FlxSprite = new FlxSprite();
		var g:FlxGraphic = FlxGraphic.fromBitmapData(bd);
		spr.loadGraphic(g);

		Cache.setFrame('keyboardViewer', {graphic: null, frame: spr.frames});
	}
}
