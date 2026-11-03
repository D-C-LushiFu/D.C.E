package developer.editors;

import general.backend.language.Language;
import general.backend.Paths;

#if sys
import sys.FileSystem;
#end

/**
 * 各编辑器输入框统一「灰底白字」外观。
 *
 * 结论（经 WeekEditor 验证 + 诊断）：
 *  引擎 tile 渲染下原生控件文本不可靠的根源是 set_color 的白色早退 + TextField
 *  反射不可用。可靠做法 = 【构建期】直接改 flixel 持有的 _defaultFormat
 *  （haxe 对象，反射可写）把文本颜色设为白，让后续每次文本渲染都用白色格式；
 *  运行时弹层只做同样的直改 + _regen 标记。
 *
 * 背景/边框/caret 走官方 setter（calcFrame 会重建对应 sprite）。
 */
class EditorInputStyle
{
	public static final BG:Int = 0xFF12141A;
	public static final BORDER:Int = 0x26FFFFFF;

	/** Add exactly one colon to localized labels, whether the translation already includes one or not. */
	public static function withLabelColon(label:String):String
	{
		var value:String = StringTools.trim(label == null ? '' : label);
		var colon:String = StringTools.endsWith(value, '：') ? '：' : ':';
		while (StringTools.endsWith(value, ':') || StringTools.endsWith(value, '：'))
			value = value.substr(0, value.length - 1);
		return value + colon;
	}

	// ==================== 字体选择（09-26 十轮：mods 的 vcr 优先，缺字回退语言字体）====================
	/** vcr.ttf 是否可用（mods 目录优先，其次 shared / assets） */
	static var _vcrOk:Null<Bool> = null;

	public static function hasVcrFont():Bool
	{
		if (_vcrOk != null) return _vcrOk;
		_vcrOk = false;
		try
		{
			#if MODS_ALLOWED
			var modPath:String = Paths.modFolders('fonts/vcr.ttf');
			if (modPath != null && modPath.indexOf('vcr') != -1 && FileSystem.exists(modPath))
				_vcrOk = true;
			#end
			#if sys
			if (!_vcrOk)
			{
				var shared:String = Paths.getSharedPath('fonts/vcr.ttf');
				if (shared != null && FileSystem.exists(shared)) _vcrOk = true;
			}
			if (!_vcrOk && FileSystem.exists('assets/fonts/vcr.ttf')) _vcrOk = true;
			#end
		}
		catch (e:Dynamic) {}
		return _vcrOk;
	}

	/** 文本是否只含 ASCII（vcr.ttf 只有 ASCII 字形，含中文/符号时必须换语言字体） */
	public static function isAsciiOnly(s:String):Bool
	{
		if (s == null) return false;
		for (i in 0...s.length)
		{
			if (s.charCodeAt(i) > 126) return false;
		}
		return true;
	}

	/** 当前语言对应的字体文件名（读 main 语言组 fontName，缺失时按语言兜底）。
	 *  ★ text 非空时按【这段文本】选字体：纯 ASCII 且有 vcr → vcr（mods 优先）；
	 *    含非 ASCII（中文等）→ 回退语言字体。
	 *  ★ text 为空时不冒险：只有当前语言本身不需要特殊字形（非中文）才用 vcr。 */
	public static function langFontFileName(?text:String = null):String
	{
		var n:String = 'chillax';
		try { n = Language.get('fontName', 'main'); } catch (e:Dynamic) {}
		if (n == null || n == '' || n.indexOf('fontName') != -1 || n.indexOf('404') != -1)
			n = (ClientPrefs.data.language == 'Chinese') ? 'Lang-ZH' : 'chillax';
		var langFile:String = n + '.ttf';

		if (hasVcrFont())
		{
			if (text != null)
			{
				if (text.length > 0 && isAsciiOnly(text)) return 'vcr.ttf';
				return langFile;
			}
			if (ClientPrefs.data.language != 'Chinese') return 'vcr.ttf';
		}
		return langFile;
	}

	// ==================== ★ 09-26 十二轮：编辑器高分辨率设计空间 ====================
	/**
	 * 为什么需要这个：
	 *   引擎主循环（FlxGame）固定以 **1280×720** 建画布，窗口是 1920×1080 时
	 *   OpenFL 只能把整幅画面放大 1.5 倍输出 ⇒ 所有文字都是"13px 光栅化后拉大"
	 *   = 发虚（截图实测：网格列距 60px = GRID_SIZE 40 × 1.5，坐实了 1.5 倍放大）。
	 *
	 * 解法：进编辑器时把"设计分辨率"临时改成设备分辨率（1080p → 1:1 无放大），
	 *   并让编辑器所有绝对尺寸（字号、栏高、格距…）乘以 `uiScale = 设计高/720`。
	 *   于是：文字按 1.5 倍字号光栅化后 1:1 输出 = 清晰，且**视觉大小与原来一致**。
	 *
	 * 只在编辑器状态内生效（进 create 时切入、destroy 时切回），游戏本体仍是
	 *   1280×720 设计，玩法/音符位置完全不受影响。
	 */
	public static var uiScale:Float = 1;
	public static var hiResActive:Bool = false;
	static var _savedInitW:Int = 1280;
	static var _savedInitH:Int = 720;
	/** 进入前的 OpenFL 逻辑尺寸（= 设置里的"分辨率"，游戏靠它决定渲染像素数） */
	static var _savedLogicalW:Int = 0;
	static var _savedLogicalH:Int = 0;
	static var _logicalSizeChanged:Bool = false;
	static var _hooked:Bool = false;

	static function ensureAutoExitHook():Void
	{
		if (_hooked) return;
		_hooked = true;
		// ★ 十四轮：必须用 preStateSwitch（在新 state 的 create 之前）。
		//   之前用 stateSwitched（切完才触发）→ 新主菜单按 1920 建好、画布却缩回 1280
		//   ⇒ "从开发工具返回主界面后整体缩小 + 位移"。
		FlxG.signals.preStateSwitch.add(function():Void
		{
			if (hiResActive)
				exitHiRes();
		});
	}

	/** 尺寸换算：把"720p 时代的数字"映射到当前设计分辨率 */
	public static inline function sv(v:Float):Float
		return v * uiScale;

	/** 尺寸换算（取整版本，给字号 / makeGraphic 用） */
	public static inline function si(v:Float):Int
		return Math.round(v * uiScale);

	/** 当前设备客户区尺寸（编辑器要按它设设计分辨率） */
	public static function deviceSize():{w:Int, h:Int}
	{
		var w:Int = 0;
		var h:Int = 0;
		#if (cpp && windows)
		try
		{
			w = general.backend.device.Native.clientWidth();
			h = general.backend.device.Native.clientHeight();
		}
		catch (e:Dynamic) {}
		#end
		if (w <= 0 || h <= 0)
		{
			try
			{
				var st:Dynamic = openfl.Lib.current.stage;
				if (st != null)
				{
					w = st.stageWidth;
					h = st.stageHeight;
				}
			}
			catch (e:Dynamic) {}
		}
		return {w: w, h: h};
	}

	/** 把"全屏尺寸"的相机同步到当前设计分辨率。
	 *  flixel 的 `FlxCamera` 逻辑尺寸只在**构造时**取 `FlxG.width/height`，
	 *  之后 `onResize()` 只更新 scrollRect/scale（这也是"1280 渲染后拉大"的来源之一）。
	 *  所以手动改设计分辨率后，必须把原本占满全屏的相机尺寸一起改掉。 */
	static function syncFullScreenCameras(oldW:Int, oldH:Int):Void
	{
		var list = FlxG.cameras.list;
		if (list == null) return;
		for (cam in list)
		{
			if (cam == null) continue;
			if (cam.width == oldW && cam.height == oldH)
			{
				cam.width = FlxG.width;
				cam.height = FlxG.height;
			}
			cam.onResize();
		}
	}

	/** Use a fixed 1080p canvas and fit the complete canvas inside the actual window. */
	public static function enterHiRes(preserveRenderResolution:Bool = false):Void
	{
		#if sys
		if (hiResActive) return;
		// Editor documents and controls use a fixed 1080p design space.
		// Window resizing changes presentation, not the document's resolution.
		var d = {w: 1920, h: 1080};

		_savedInitW = FlxG.initialWidth;
		_savedInitH = FlxG.initialHeight;
		if (_savedInitW <= 0) _savedInitW = 1280;
		if (_savedInitH <= 0) _savedInitH = 720;

		// ★★ 十四轮：引擎的"分辨率"设置是 stage.setLogicalSize（窗口物理尺寸不变，
		//   舞台逻辑尺寸变小 → 游戏按小分辨率渲染再被放大）。编辑器要 1:1 就必须
		//   把【逻辑尺寸】也提到物理客户区，否则 stageWidth(逻辑) < FlxG.width(设计)
		//   → scaleMode 算出 scale<1 + 居中偏移 → 编辑器内容被放大且位置偏移。
		try
		{
			var st = openfl.Lib.current.stage;
			// Restore the requested size, not the aspect-fitted result. Feeding
			// the fitted result back into Android's cover calculation shrinks it.
			@:privateAccess _savedLogicalW = st.__desiredLogicalWidth;
			@:privateAccess _savedLogicalH = st.__desiredLogicalHeight;
			if (_savedLogicalW <= 0) _savedLogicalW = st.stageWidth;
			if (_savedLogicalH <= 0) _savedLogicalH = st.stageHeight;
			_logicalSizeChanged = false;
			if (!preserveRenderResolution && st.stageWidth > 0 && st.stageHeight > 0
				&& (st.stageWidth != d.w || st.stageHeight != d.h))
			{
				_logicalSizeChanged = true;
				st.setLogicalSize(d.w, d.h);
			}
		}
		catch (e:Dynamic) {}

		untyped
		{
			FlxG.initialWidth = d.w;
			FlxG.initialHeight = d.h;
		}
		// resizeGame measures the viewport; it does not set the design resolution.
		// Passing 1920 here in a 1280 window incorrectly gives the cameras scale=1.
		var stage = openfl.Lib.current.stage;
		FlxG.resizeGame(stage.stageWidth, stage.stageHeight);
		syncFullScreenCameras(_savedInitW, _savedInitH);

		uiScale = FlxG.height / 720;
		if (Math.isNaN(uiScale) || uiScale < 1) uiScale = 1;
		// ★ 15 轮：全局字号缩放 —— 包括 mods / hscript 直接 new 的 FlxText、
		//   FlxUI 输入框/复选框的文字，全部按同一倍率光栅化（只改文字，不动任何布局/贴图）。
		flixel.text.FlxText.uiSizeScale = uiScale;
		hiResActive = true;
		ensureAutoExitHook();
		var client = deviceSize();
		trace('[EditorResolution] design=' + FlxG.width + 'x' + FlxG.height + ' client=' + client.w + 'x' + client.h
			+ ' viewportScale=' + FlxG.scaleMode.scale.x + ',' + FlxG.scaleMode.scale.y
			+ ' preserveRenderResolution=' + preserveRenderResolution + ' previousRequested=' + _savedLogicalW + 'x' + _savedLogicalH);
		#end
	}

	/** 离开编辑器：恢复原本的设计分辨率（游戏本体保持 1280×720） */
	public static function exitHiRes():Void
	{
		#if sys
		if (!hiResActive) return;
		hiResActive = false;

		var oldW:Int = FlxG.initialWidth;
		var oldH:Int = FlxG.initialHeight;

		untyped
		{
			FlxG.initialWidth = _savedInitW;
			FlxG.initialHeight = _savedInitH;
		}
		// ★ 还原"分辨率"设置的逻辑尺寸（没有记录过就用当前物理客户区）
		var lw:Int = _savedLogicalW;
		var lh:Int = _savedLogicalH;
		if (lw <= 0 || lh <= 0)
		{
			var d = deviceSize();
			lw = d.w;
			lh = d.h;
		}
		try
		{
			var st = openfl.Lib.current.stage;
			if (_logicalSizeChanged && lw > 0 && lh > 0) st.setLogicalSize(lw, lh);
		}
		catch (e:Dynamic) {}
		var stage = openfl.Lib.current.stage;
		FlxG.resizeGame(stage.stageWidth, stage.stageHeight);
		syncFullScreenCameras(oldW, oldH);
		_savedLogicalW = 0;
		_savedLogicalH = 0;
		_logicalSizeChanged = false;
		uiScale = 1;
		flixel.text.FlxText.uiSizeScale = 1;
		#end
	}

	/**
	 * 把输入控件染成灰底白字（构建期与弹层期均可调用，幂等）：
	 *  - 字体 = 对应语言的字体（main 组 fontName，如中文 Lang-ZH）
	 *  - 直接写 _defaultFormat.color = 白（绕过 FlxText.set_color 的白色早退）
	 *  - 背景灰 / 边框浅灰 / 光标白 / 字号 12
	 */
	public static function apply(w:Dynamic, ?fieldW:Float):Void
	{
		if (w == null) return;
		if (Std.isOfType(w, flixel.addons.ui.FlxInputText))
		{
			var input:flixel.addons.ui.FlxInputText = cast w;
			input.setFormat(Paths.font(langFontFileName()), 12, 0xFFFFFFFF, LEFT);
			input.backgroundColor = BG;
			input.fieldBorderColor = BORDER;
			input.caretColor = 0xFFFFFFFF;
			if (fieldW != null) input.fieldWidth = fieldW;
			return;
		}

		// ★ 字体：对应语言的字体（与菜单文本同一来源）
		try { w.font = Paths.font(langFontFileName()); } catch (e:Dynamic) {}

		// ★ 文本颜色：直接改 flixel 持有的 TextFormat（haxe 对象，Dynamic 可靠）
		try
		{
			var df:Dynamic = Reflect.field(w, '_defaultFormat');
			if (df != null)
				df.color = 0xFFFFFF;
		}
		catch (e:Dynamic) {}
		// 同步 color 字段（FlxSprite tint 用；不依赖其 setter 是否早退）
		try { w.color = 0xFFFFFFFF; } catch (e:Dynamic) {}

		try { w.backgroundColor = BG; } catch (e:Dynamic) {}
		try { w.fieldBorderColor = BORDER; } catch (e:Dynamic) {}
		try { w.caretColor = 0xFFFFFFFF; } catch (e:Dynamic) {}
		try { w.size = 12; } catch (e:Dynamic) {} // ★ 字号由 FlxText.uiSizeScale 全局缩放，这里写逻辑值
		if (fieldW != null)
		{
			try { w.fieldWidth = fieldW; } catch (e:Dynamic) {}
		}
		// 标记文本重渲（由绘制/后续 set_text 触发 calcFrame）
		try { Reflect.setField(w, '_regen', true); } catch (e:Dynamic) {}
	}

	/** Resize through typed setters; Dynamic writes do not reliably update native text geometry. */
	public static function fitInputOverlay(w:Dynamic, boxW:Float):Void
	{
		if (!Std.isOfType(w, flixel.addons.ui.FlxInputText)) return;
		var input:flixel.addons.ui.FlxInputText = cast w;
		var targetW:Float = Math.max(1, boxW - 4);
		input.scale.set(1, 1);
		if (input.fieldWidth != targetW) input.fieldWidth = targetW;
		input.wordWrap = false;
		input.drawFrame();
		input.offset.set();
		input.setPosition(input.x, input.y);
	}

	/**
	 * 类型化设置 FlxInputText 的 hasFocus（必须走 setter）。
	 *
	 * set_hasFocus 内 `#if mobile` 会执行 window.textInputEnabled = true/false
	 * （SDL 弹/收安卓软键盘）。若用 Dynamic 赋值 `w.hasFocus = true` 会绕过
	 * setter 直接写字段 → 桌面一切正常（字符走 stage KEY_DOWN），安卓却永远
	 * 弹不出软键盘。
	 */
	public static function setInputFocus(w:Dynamic, focus:Bool):Void
	{
		if (w == null)
			return;
		if (Std.isOfType(w, flixel.addons.ui.FlxInputText))
		{
			var fi:flixel.addons.ui.FlxInputText = cast w;
			@:privateAccess fi.hasFocus = focus;
			return;
		}
		// 兜底：非 FlxInputText 的控件直接写字段
		try
		{
			Reflect.setProperty(w, 'hasFocus', focus);
		}
		catch (e:Dynamic) {}
	}

	/**
	 * 深递归把一个原生 FlxUI 控件整棵子树隐藏（visible=false + active=false）。
	 *
	 *  为什么要深递归：
	 *   - FlxUICheckBox.set_visible 是 `// don't cascade to my members` 的特制版，
	 *     设父 visible=false 不会带动 button 子对象隐藏；
	 *   - FlxUIDropDownMenu.set_visible 会保留子按钮原本的可见状态再恢复 →
	 *     visible=false 同样不会隐藏 list 子按钮 / dropPanel；
	 *   - FlxUIGroup / FlxSpriteGroup 子对象 `active=true` 时还会持续抢鼠标
	 *     事件，即使父对象 visible=false 也不行。
	 *
	 *  调用方在编辑器 create() 里统一调一次，把所有原生 widget 子树
	 * 彻底隐藏、改由自绘控件承担交互。
	 */
	public static function deepHide(w:Dynamic):Void
	{
		if (w == null) return;
		try { w.visible = false; } catch (e:Dynamic) {}
		try { w.active = false; } catch (e:Dynamic) {}
		// 1) FlxUICheckBox / FlxUIButton 等持有 `button` / `box` / `mark` 子对象
		try
		{
			for (fieldName in ['button', 'box', 'mark'])
			{
				var sub:Dynamic = Reflect.field(w, fieldName);
				if (sub != null) deepHide(sub);
			}
		}
		catch (e:Dynamic) {}
		// 2) FlxUIDropDownMenu 持有 `header` / `dropPanel` / `list` 子对象
		try
		{
			var header:Dynamic = Reflect.field(w, 'header');
			if (header != null) deepHide(header);
			var dropPanel:Dynamic = Reflect.field(w, 'dropPanel');
			if (dropPanel != null) deepHide(dropPanel);
			var list:Dynamic = Reflect.field(w, 'list');
			if (list != null)
			{
				try
				{
					for (item in (list:Array<Dynamic>))
						if (item != null) deepHide(item);
				}
				catch (e:Dynamic) {}
			}
		}
		catch (e:Dynamic) {}
		// 3) FlxSpriteGroup / FlxUIGroup 持有 `members` 列表
		try
		{
			var members:Dynamic = Reflect.field(w, 'members');
			if (members != null)
			{
				try
				{
					for (m in (members:Array<Dynamic>))
						if (m != null) deepHide(m);
				}
				catch (e:Dynamic) {}
			}
		}
		catch (e:Dynamic) {}
	}
}
