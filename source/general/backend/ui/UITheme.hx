package general.backend.ui;

import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxTileFrames;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import general.backend.Cache;
import general.backend.Paths;

class UITheme
{
	public static inline var PANEL:FlxColor = 0xFF1D1D22;
	public static inline var BORDER:FlxColor = 0xFF3F3F46;
	public static inline var BTN:FlxColor = 0xFF2D2D34;
	public static inline var BTN_HOVER:FlxColor = 0xFF3E3E4A;
	public static inline var BTN_DOWN:FlxColor = 0xFF1B1B21;
	public static inline var ACCENT:FlxColor = 0xFF4F8DF9;
	public static inline var TEXT:FlxColor = 0xFFE8E4D8;
	public static inline var TEXT_DIM:FlxColor = 0xFF9A968C;
	public static inline var FIELD:FlxColor = 0xFF141419;

	public static function drawPanel(spr:FlxSprite, w:Int, h:Int, fill:FlxColor, ?glow:FlxColor = ACCENT, ?radius:Int = 10):Void
	{
		spr.makeGraphic(w, h, FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(spr, 0.5, 0.5, w - 1, h - 1, radius, radius, fill);
		FlxSpriteUtil.drawRoundRect(spr, 1.5, 1.5, w - 3, h - 3, Math.max(1, radius - 1), Math.max(1, radius - 1), FlxColor.TRANSPARENT, {thickness: 1, color: glow});
	}

	static var _checkbox:FlxGraphic;
	static var _plus:FlxGraphic;
	static var _minus:FlxGraphic;
	static var _ddBtn:FlxGraphic;
	static var _radio:FlxGraphic;
	static var _arrowUp:FlxGraphic;
	static var _arrowDown:FlxGraphic;

	public static function checkboxSheet():FlxGraphic
	{
		if(_checkbox != null && _checkbox.bitmap != null) return _checkbox;
		var s:FlxSprite = new FlxSprite().makeGraphic(32, 16, FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(s, 0.5, 0.5, 15, 15, 3, 3, FIELD, {thickness: 1, color: 0xFF5A5A64});
		FlxSpriteUtil.drawRoundRect(s, 16.5, 0.5, 15, 15, 3, 3, ACCENT, {thickness: 1, color: 0xFF7FB0FF});
		FlxSpriteUtil.drawLine(s, 20, 8.5, 23, 11.5, {thickness: 2, color: FlxColor.WHITE});
		FlxSpriteUtil.drawLine(s, 23, 11.5, 28, 4.5, {thickness: 2, color: FlxColor.WHITE});
		_checkbox = s.graphic;
		return _checkbox;
	}

	public static function stepperSheet(plus:Bool):FlxGraphic
	{
		var cached:FlxGraphic = plus ? _plus : _minus;
		if(cached != null && cached.bitmap != null) return cached;
		var s:FlxSprite = new FlxSprite().makeGraphic(32, 16, FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(s, 0.5, 0.5, 15, 15, 3, 3, BTN, {thickness: 1, color: BORDER});
		FlxSpriteUtil.drawRoundRect(s, 16.5, 0.5, 15, 15, 3, 3, BTN_DOWN, {thickness: 1, color: BORDER});
		FlxSpriteUtil.drawRect(s, 4, 7, 8, 2, TEXT);
		FlxSpriteUtil.drawRect(s, 20, 7, 8, 2, TEXT);
		if(plus)
		{
			FlxSpriteUtil.drawRect(s, 7, 4, 2, 8, TEXT);
			FlxSpriteUtil.drawRect(s, 23, 4, 2, 8, TEXT);
		}
		var g:FlxGraphic = s.graphic;
		if(plus) _plus = g; else _minus = g;
		return g;
	}

	public static function dropdownButtonSheet():FlxGraphic
	{
		if(_ddBtn != null && _ddBtn.bitmap != null) return _ddBtn;
		var s:FlxSprite = new FlxSprite().makeGraphic(40, 20, FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(s, 0.5, 0.5, 19, 19, 3, 3, BTN, {thickness: 1, color: BORDER});
		FlxSpriteUtil.drawRoundRect(s, 20.5, 0.5, 19, 19, 3, 3, BTN_DOWN, {thickness: 1, color: BORDER});
		arrowDown(s, 5.5, 7.5, 9);
		arrowDown(s, 25.5, 7.5, 9);
		_ddBtn = s.graphic;
		return _ddBtn;
	}

	public static function radioSheet():FlxGraphic
	{
		if(_radio != null && _radio.bitmap != null) return _radio;
		var s:FlxSprite = new FlxSprite().makeGraphic(32, 16, FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawCircle(s, 8, 8, 7, FIELD, {thickness: 1, color: 0xFF5A5A64});
		FlxSpriteUtil.drawCircle(s, 24, 8, 7, ACCENT, {thickness: 1, color: 0xFF7FB0FF});
		FlxSpriteUtil.drawCircle(s, 24, 8, 3, FlxColor.WHITE);
		_radio = s.graphic;
		return _radio;
	}

	public static function arrowSheet(up:Bool):FlxGraphic
	{
		var cached:FlxGraphic = up ? _arrowUp : _arrowDown;
		if(cached != null && cached.bitmap != null) return cached;
		var s:FlxSprite = new FlxSprite().makeGraphic(48, 18, FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(s, 0.5, 0.5, 23, 17, 3, 3, BTN, {thickness: 1, color: BORDER});
		FlxSpriteUtil.drawRoundRect(s, 24.5, 0.5, 23, 17, 3, 3, BTN_DOWN, {thickness: 1, color: BORDER});
		var cx:Float = up ? 12 : 36;
		var p1:FlxPoint = up ? FlxPoint.get(cx, 5) : FlxPoint.get(cx - 4, 9);
		var p2:FlxPoint = up ? FlxPoint.get(cx + 4, 5) : FlxPoint.get(cx + 4, 9);
		var p3:FlxPoint = up ? FlxPoint.get(cx - 4, 9) : FlxPoint.get(cx, 13);
		for (ox in [0, 24])
			FlxSpriteUtil.drawPolygon(s, [FlxPoint.get(p1.x + ox, p1.y), FlxPoint.get(p2.x + ox, p2.y), FlxPoint.get(p3.x + ox, p3.y)], TEXT, {thickness: 1, color: TEXT});
		var g:FlxGraphic = persistGraphic(s.graphic);
		if(up) _arrowUp = g; else _arrowDown = g;
		return g;
	}

	static function persistGraphic(g:FlxGraphic):FlxGraphic
	{
		if(g == null) return g;
		g.persist = true;
		g.destroyOnNoUse = false;
		if(g.key != null && g.key.length > 0) Cache.currentTrackedAssets.set(g.key, g);
		return g;
	}

	static function arrowDown(s:FlxSprite, x:Float, y:Float, w:Float)
	{
		FlxSpriteUtil.drawPolygon(s, [FlxPoint.get(x, y), FlxPoint.get(x + w, y), FlxPoint.get(x + w / 2, y + w * 0.6)], TEXT, {thickness: 1, color: TEXT});
	}

	public static function tiledFrames(g:FlxGraphic, fw:Int, fh:Int)
	{
		return FlxTileFrames.fromGraphic(g, FlxPoint.get(fw, fh));
	}
}
