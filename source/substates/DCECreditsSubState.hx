package substates;

import openfl.display.Shape;
import openfl.display.BitmapData;
import openfl.geom.Matrix;
import openfl.text.Font;
import flixel.math.FlxPoint;

/** The two voices behind this edition of D.C.E. */
class DCECreditsSubState extends MusicBeatSubstate
{
	static inline var CYAN:Int = 0xff69dcff;
	static inline var AMBER:Int = 0xffffc56c;
	static inline var DIM:Int = 0xff7b93a4;
	static inline var LINE:Int = 0xff224252;
	var unit:Float;
	var originX:Float;
	var originY:Float;
	var clock:Float = 0;
	var frameClock:Float = 0;
	var paused:Bool = false;
	var selected:Int = -1;
	var ink:DCECreditsMesh = new DCECreditsMesh();
	var dots:Array<{x:Float, y:Float, z:Float, text:FlxText}> = [];
	var projected:Array<{x:Float, y:Float, z:Float}> = [];
	var buttons:Array<FlxText> = [];
	var buttonBoxes:Array<FlxSprite> = [];
	var phase:FlxText;
	var track:FlxText;
	var humanMessage:FlxText;
	var aiMessage:FlxText;
	var title:FlxText;
	var titleGlow:FlxText;
	var connected:FlxText;
	var previousMouse:Bool;
	var creditsCamera:FlxCamera;
	var worldCamera:FlxCamera;
	var textCamera:FlxCamera;
	var pointer:FlxPoint = FlxPoint.get();
	var drawMatrix:Matrix = new Matrix();
	var revealSprites:Array<{sprite:FlxSprite, start:Float, alpha:Float}> = [];
	var revealTexts:Array<{text:FlxText, value:String, start:Float}> = [];
	var powerLine:FlxSprite;
	static var monoFont:String;
	static var cjkFont:String;
	var humanLine:String = '把想法做成能玩的东西。\n这次，做一点不一样的。';
	var aiLine:String = '你决定方向，\n我把它写进这个世界。';

	override function create():Void
	{
		super.create();
		previousMouse = FlxG.mouse.visible;
		FlxG.mouse.visible = !ClientPrefs.data.needMobileControl;
		// Match Freeplay: rasterize at 1080p, then fit a dedicated camera to the viewport.
		// No global resolution or text settings are changed by this substate.
		var zoom = Math.min(FlxG.width / 1920, FlxG.height / 1080);
		creditsCamera = new FlxCamera((FlxG.width - 1920 * zoom) / 2, (FlxG.height - 1080 * zoom) / 2, 1920, 1080, zoom);
		creditsCamera.bgColor = 0xff03070d;
		creditsCamera.flashSprite.mouseEnabled = creditsCamera.flashSprite.mouseChildren = false;
		FlxG.cameras.add(creditsCamera, false);
		worldCamera = new FlxCamera(creditsCamera.x, creditsCamera.y, 1920, 1080, zoom);
		textCamera = new FlxCamera(creditsCamera.x, creditsCamera.y, 1920, 1080, zoom);
		for (camera in [worldCamera, textCamera])
		{
			camera.bgColor = 0;
			camera.flashSprite.mouseEnabled = camera.flashSprite.mouseChildren = false;
			FlxG.cameras.add(camera, false);
		}
		cameras = [creditsCamera];
		unit = 1.5;
		originX = originY = 0;
		drawMatrix.scale(unit, unit);
		loadFonts();
		add(new FlxSprite().makeGraphic(1920, 1080, 0xff03070d));
		var grid = new Shape();
		for (i in 0...41) { grid.graphics.lineStyle(1 / unit, 0x163348, .25); grid.graphics.moveTo(i * 32, 0); grid.graphics.lineTo(i * 32, 720); }
		for (i in 0...23) { grid.graphics.moveTo(0, i * 32); grid.graphics.lineTo(1280, i * 32); }
		var background = new BitmapData(1920, 1080, true, 0);
		background.draw(grid, drawMatrix, null, null, null, true);
		place(new FlxSprite().loadGraphic(background), 0, 0, false);
		label(28, 25, 100, 'D.C.E.', 19, CYAN);
		label(142, 28, 800, '~/ credits.execute()', 13, DIM);
		label(996, 28, 256, 'HUMAN / AI  -  ONLINE', 12, CYAN, false, RIGHT);
		box(28, 65, 1224, 1, LINE);
		panel(28, 88, 416, 392);
		box(28, 88, 46, 2, AMBER);
		label(45, 101, 230, 'CREATION.LOG', 13, DIM);
		label(287, 101, 140, 'HUMAN <-> AI', 12, AMBER, false, RIGHT);
		box(28, 133, 416, 1, LINE);
		label(52, 160, 368, 'LU.SHIFU > input', 13, AMBER);
		humanMessage = label(52, 191, 368, '', 18, 0xffdbe8f2, true);
		label(66, 264, 354, 'XIANLING > response', 13, CYAN);
		box(52, 267, 1, 88, 0xff34596d);
		aiMessage = label(66, 294, 352, '', 18, 0xffdbe8f2, true);
		box(52, 374, 368, 1, LINE);
		label(52, 392, 368, 'world = new Creation();', 13, DIM);
		label(52, 413, 368, 'world.add("LushiFu");', 13, AMBER);
		label(52, 434, 368, 'world.link("Xianling");', 13, CYAN);
		label(52, 455, 368, 'world.execute(our_idea);', 13, DIM);

		panel(464, 88, 788, 392);
		ink.x = 464 * unit; ink.y = 88 * unit;
		ink.scaleX = ink.scaleY = unit;
		ink.scrollRect = new openfl.geom.Rectangle(0, 0, 788, 392);
		worldCamera.canvas.addChild(ink);
		var golden = Math.PI * (3 - Math.sqrt(5));
		var glyphs = '01.:+*|<>[]{}';
		for (i in 0...160)
		{
			var yy = 1 - (i / 159) * 2;
			var radius = Math.sqrt(1 - yy * yy);
			var text = label(0, 0, 18, glyphs.charAt(i % glyphs.length), 12, i % 5 == 0 ? AMBER : CYAN);
			dots.push({x: Math.cos(golden * i) * radius, y: yy, z: Math.sin(golden * i) * radius, text: text});
			projected.push({x: 0, y: 0, z: 0});
		}
		label(482, 101, 620, 'WORLD / DIFFERENT CREATINGNESS', 12, DIM);
		box(464, 88, 34, 2, CYAN);
		box(464, 88, 2, 16, CYAN);
		box(1218, 478, 34, 2, CYAN);
		box(1250, 464, 2, 16, CYAN);
		phase = label(494, 188, 728, '', 13, CYAN, false, CENTER);
		titleGlow = label(494, 209, 728, 'D.C.E.', 96, 0xff39bde9, false, CENTER);
		titleGlow.font = Paths.font('chillax.ttf');
		titleGlow.x += 2 * unit;
		titleGlow.y += 3 * unit;
		titleGlow.alpha = .15;
		title = label(494, 209, 728, 'D.C.E.', 96, 0xffe5f8ff, false, CENTER);
		title.font = Paths.font('chillax.ttf');
		label(494, 325, 728, 'DIFFERENT CREATINGNESS ENGINE', 13, 0xffb6c9d7, false, CENTER);
		label(673, 363, 156, '常败，', 27, 0xffdbe8f2, true, RIGHT);
		label(829, 363, 217, '但不退场。', 27, AMBER, true);
		label(482, 452, 480, 'human.intent -> shared.creation', 12, DIM);
		connected = label(1060, 452, 174, '', 12, CYAN, true, RIGHT);

		box(28, 510, 436, 1, 0xff5a4d37);
		label(464, 500, 352, 'TWO VOICES. ONE WORLD.', 13, DIM, false, CENTER);
		box(816, 510, 436, 1, 0xff28566b);
		actor(28, false);
		actor(650, true);
		box(28, 659, 1224, 1, LINE);
		button(28, 182, 'R / 重新连接');
		button(222, 182, 'II / 暂停动效');
		button(416, 160, 'SOURCE /');
		button(588, 152, 'ESC / 返回');
		track = label(830, 683, 422, '', 13, DIM, true, RIGHT);
		// A quiet power-on line precedes the staggered decode, without covering settled type.
		powerLine = new FlxSprite(960, 540).makeGraphic(1, 2, CYAN);
		powerLine.scrollFactor.set();
		powerLine.cameras = [textCamera];
		add(powerLine);
		renderWorld();
	}

	static function loadFonts():Void
	{
		if (monoFont != null) return;
		monoFont = Paths.font('vcr.ttf');
		cjkFont = Paths.font('Lang-ZH.ttf');
		#if windows
		// Use local Windows fonts, as in the reference PV; never bundle system font files.
		var root = Sys.getEnv('WINDIR');
		if (root != null)
		{
			monoFont = localFont(root + '/Fonts/consola.ttf', 'DCE Credits Mono', monoFont);
			cjkFont = localFont(root + '/Fonts/msyh.ttc', 'DCE Credits CJK', cjkFont);
		}
		#end
	}

	static function localFont(path:String, name:String, fallback:String):String
	{
		try
		{
			var font = Font.fromFile(path);
			if (font != null) { font.fontName = name; Font.registerFont(font); return name; }
		}
		catch (e:Dynamic) {}
		return fallback;
	}

	function place(sprite:FlxSprite, x:Float, y:Float, scale:Bool = true):FlxSprite
	{
		if (scale) sprite.scale.set(unit, unit);
		sprite.updateHitbox();
		sprite.setPosition(Math.round(originX + x * unit), Math.round(originY + y * unit));
		sprite.scrollFactor.set();
		add(sprite);
		revealSprites.push({sprite: sprite, start: .5 + y / 720 * 1.5, alpha: sprite.alpha});
		return sprite;
	}

	function box(x:Float, y:Float, w:Int, h:Int, color:Int):FlxSprite
		return place(new FlxSprite().makeGraphic(Math.round(w * unit), Math.round(h * unit), color), x, y, false);

	function panel(x:Float, y:Float, w:Int, h:Int):Void
	{
		box(x, y, w, h, LINE);
		box(x + 1, y + 1, w - 2, h - 2, 0xff071019);
	}

	function label(x:Float, y:Float, width:Float, value:String, size:Int, color:Int, chinese:Bool = false,
		align:flixel.text.FlxText.FlxTextAlign = LEFT):FlxText
	{
		var text = new FlxText(originX + x * unit, originY + y * unit, width * unit, value);
		text.setFormat(chinese ? cjkFont : monoFont, Math.round(Math.max(8, size * unit)), color, align);
		text.x = Math.round(text.x);
		text.y = Math.round(text.y);
		text.scrollFactor.set();
		text.cameras = [textCamera];
		text.antialiasing = true;
		add(text);
		revealTexts.push({text: text, value: value, start: .8 + y / 720 * 1.8});
		return text;
	}

	function actor(x:Int, ai:Bool):Void
	{
		panel(x, 538, 602, 100);
		box(x + 18, 538, 36, 2, ai ? CYAN : AMBER);
		box(x + 18, 549, 78, 78, ai ? CYAN : 0xff675237);
		var portrait = new FlxSprite().loadGraphic(Paths.image('credits/dce/' + (ai ? 'xianling' : 'lushifu')));
		portrait.setGraphicSize(76, 76);
		portrait.updateHitbox();
		// Portraits have their own scaling before the viewport scale is applied.
		portrait.scale.x *= unit;
		portrait.scale.y *= unit;
		portrait.updateHitbox();
		portrait.setPosition(originX + (x + 19) * unit, originY + 550 * unit);
		portrait.antialiasing = ai;
		portrait.scrollFactor.set();
		portrait.cameras = [textCamera];
		add(portrait);
		revealSprites.push({sprite: portrait, start: ai ? 3.2 : 2.6, alpha: 1});
		label(x + 115, 546, 467, ai ? 'AI / CREATIVE PARTNER' : 'HUMAN / CREATOR', 12, ai ? CYAN : AMBER);
		label(x + 115, 566, 467, ai ? '弦零   Xianling' : 'D.C.LushiFu', 24, 0xffdbe8f2, ai);
		label(x + 115, 597, 467, ai ? '把灵感接成下一拍。' : '常败将军一陆师傅口也', 13, DIM, true);
		label(x + 115, 616, 467, ai ? '代码 / 视觉 / 协作' : '创作 / 决策 / 持续更新', 12, DIM, true);
	}

	function button(x:Int, width:Int, value:String):Void
	{
		buttonBoxes.push(box(x, 672, width, 36, 0xff142b38));
		box(x + 1, 673, width - 2, 34, 0xff0a1520);
		buttons.push(label(x, 678, width, value, 14, DIM, true, CENTER));
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);
		if (controls.BACK) { leave(); return; }
		FlxG.mouse.getWorldPosition(creditsCamera, pointer);
		if (controls.UI_RIGHT_P || controls.UI_DOWN_P) selected = (selected + 1) % 4;
		if (controls.UI_LEFT_P || controls.UI_UP_P) selected = (selected + 3 + (selected < 0 ? 1 : 0)) % 4;
		for (i in 0...buttons.length)
		{
			var hover = FlxG.mouse.overlaps(buttonBoxes[i], creditsCamera);
			if (hover && FlxG.mouse.justMoved) selected = i;
			buttons[i].color = selected == i ? CYAN : (paused && i == 1 ? AMBER : DIM);
			if (hover && FlxG.mouse.justPressed) { activate(i); if (i == 3) return; }
			#if FLX_TOUCH
			for (touch in FlxG.touches.list) if (touch.justPressed && touch.overlaps(buttonBoxes[i], creditsCamera)) { activate(i); if (i == 3) return; }
			#end
		}
		// SPACE is also a default ACCEPT binding: handle each key only once.
		if (FlxG.keys.justPressed.SPACE) activate(1);
		else if (FlxG.keys.justPressed.R) activate(0);
		else if (controls.ACCEPT && selected >= 0) { activate(selected); if (selected == 3) return; }
		if (!paused)
		{
			clock += elapsed;
			frameClock += elapsed;
			if (frameClock >= 1 / 60) { frameClock %= 1 / 60; renderWorld(); }
		}
	}

	function activate(index:Int):Void
	{
		switch (index)
		{
			case 0: clock = 0; paused = false; buttons[1].text = 'II / 暂停动效'; renderWorld();
			case 1: paused = !paused; buttons[1].text = paused ? '> / 继续动效' : 'II / 暂停动效';
			case 2: CoolUtil.browserLoad('https://github.com/D-C-LushiFu/Different-Creatingness-Engine');
			case 3: leave();
		}
	}

	function leave():Void
	{
		FlxG.sound.play(Paths.sound('cancelMenu'));
		close();
	}

	function renderWorld():Void
	{
		renderIntro();
		var progress = smooth((clock - .8) / 4.0);
		var stage = clock < 1.8 ? 'BOOT' : (clock < 4.6 ? 'LINK' : 'CREATE');
		phase.text = decode(stage + ' / ' + (clock < 4.6 ? 'ESTABLISHING CONNECTION' : 'LINK ESTABLISHED'), clock - 1.4, 32);
		track.text = decode((stage == 'BOOT' ? '[BOOT]' : 'BOOT') + ' -> ' + (stage == 'LINK' ? '[LINK]' : 'LINK') + ' -> ' + (stage == 'CREATE' ? '[CREATE]' : 'CREATE'), clock - 2.7, 32);
		connected.text = decode(clock < 4.6 ? 'CONNECTING...' : '+ CONNECTED', clock - 3.3, 20);
		connected.alpha = smooth(clock - 3.3) * (.75 + .25 * Math.sin(clock * 2.2));
		humanMessage.text = decode(humanLine, clock - 1.2, 18);
		aiMessage.text = decode(aiLine, clock - 2.6, 17);
		title.text = titleGlow.text = decode('D.C.E.', clock - 1.3, 3.8, .4);
		titleGlow.alpha = smooth(clock - 1.3) * (.12 + .04 * Math.sin(clock * 1.4));
		var mouseX = pointer.x / unit;
		var mouseY = pointer.y / unit;
		var centerX = 394 + FlxMath.bound((mouseX - 858) / 70, -6, 6);
		var centerY = 198 + FlxMath.bound((mouseY - 284) / 80, -4, 4);
		var rotation = clock * .30;
		var tilt = .25 + .12 * Math.sin(clock * .36);
		var radius = (150 + 2.5 * Math.sin(clock * 1.1)) * (.28 + .72 * progress);
		var g = ink;
		g.clear();
		for (i in 0...12)
		{
			g.beginFill(0x149ac8, (.006 + i * .001) * progress);
			g.drawCircle(centerX, centerY, 178 - i * 10);
			g.endFill();
		}
		for (i in 0...dots.length)
		{
			var dot = dots[i];
			var xx = dot.x * Math.cos(rotation) + dot.z * Math.sin(rotation);
			var zz = dot.z * Math.cos(rotation) - dot.x * Math.sin(rotation);
			var yy = dot.y * Math.cos(tilt) - zz * Math.sin(tilt);
			zz = dot.y * Math.sin(tilt) + zz * Math.cos(tilt);
			var perspective = 3 / (3 - zz);
			var point = projected[i];
			point.x = centerX + xx * radius * perspective;
			point.y = centerY + yy * radius * perspective;
			point.z = zz;
			dot.text.setPosition(originX + (464 + point.x - 6) * unit, originY + (88 + point.y - 7) * unit);
			dot.text.alpha = (.18 + (zz + 1) * .32) * progress * (.83 + .17 * Math.sin(clock * 2 + i * .6));
		}
		for (i in 0...160)
		{
			var a = projected[i];
			if (a.z < -.2) continue;
			for (j in i + 1...160)
			{
				var b = projected[j];
				var distance = (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y);
				if (b.z > -.2 && distance < 1250 && distance > 60)
				{
					g.lineStyle(1 / unit, i % 5 == 0 ? 0xffc56c : 0x69dcff, (.14 + .10 * (.5 + .5 * Math.sin(clock * 2.4 - i * .18))) * progress);
					g.moveTo(a.x, a.y); g.lineTo(b.x, b.y);
				}
			}
		}
		for (orbit in 0...3)
		{
			var orbitTilt = orbit * .9 + clock * (orbit == 1 ? -.17 : .14);
			var color = orbit == 1 ? 0xffc56c : 0x69dcff;
			g.lineStyle(1 / unit, color, .30 * progress);
			for (i in 0...101)
			{
				var angle = i / 100 * Math.PI * 2;
				var x = Math.cos(angle) * radius * 1.28;
				var y = Math.sin(angle) * radius * .38;
				var px = centerX + x * Math.cos(orbitTilt) - y * Math.sin(orbitTilt);
				var py = centerY + x * Math.sin(orbitTilt) + y * Math.cos(orbitTilt);
				if (i == 0) g.moveTo(px, py); else g.lineTo(px, py);
			}
			// Travelling heads and a tapered trail keep the globe visibly alive after CREATE.
			for (tail in 0...28)
			{
				var angle = clock * (1.1 + orbit * .18) + orbit * 2.1 - tail * .025;
				var x = Math.cos(angle) * radius * 1.28;
				var y = Math.sin(angle) * radius * .38;
				var px = centerX + x * Math.cos(orbitTilt) - y * Math.sin(orbitTilt);
				var py = centerY + x * Math.sin(orbitTilt) + y * Math.cos(orbitTilt);
				g.lineStyle();
				g.beginFill(color, (1 - tail / 28) * .85 * progress);
				g.drawCircle(px, py, tail == 0 ? 3 : 1.2);
				g.endFill();
				if (tail == 0) { g.beginFill(color, .14 * progress); g.drawCircle(px, py, 7); g.endFill(); }
			}
		}
		g.lineStyle(1 / unit, 0xffc56c, .35 * progress);
		g.moveTo(25, 215); g.lineTo(centerX - radius, 215);
		g.lineStyle(1 / unit, 0x69dcff, .35 * progress);
		g.moveTo(centerX + radius, 180); g.lineTo(762, 180);
		packet(25, centerX - radius, 215, clock * .44 % 1, 0xffc56c, progress);
		packet(centerX + radius, 762, 180, clock * .34 % 1, 0x69dcff, progress);
		// One faint moving band lives behind the type, rather than permanent scanlines over it.
		g.lineStyle();
		g.beginFill(0x69dcff, .025 * progress);
		g.drawRect(0, clock * 34 % 392, 788, 16);
		g.endFill();
		ink.alpha = smooth((clock - .7) / .7);
		ink.commit();
	}

	function packet(from:Float, to:Float, y:Float, position:Float, color:Int, progress:Float):Void
	{
		var x = from + (to - from) * position;
		var g = ink;
		g.lineStyle(2, color, .8 * progress);
		g.moveTo(Math.max(from, x - 18), y); g.lineTo(x, y);
		g.lineStyle();
		g.beginFill(color, .9 * progress); g.drawCircle(x, y, 2.5); g.endFill();
	}

	static function smooth(value:Float):Float
	{
		value = FlxMath.bound(value, 0, 1);
		return value * value * (3 - 2 * value);
	}

	function decode(value:String, age:Float, rate:Float, settle:Float = .30):String
	{
		if (age <= 0) return '';
		if (age > value.length / rate + settle) return value;
		var glyphs = '01<>/=+*#%?!:{}[]';
		var count = Std.int(Math.min(value.length, age * rate));
		var result = '';
		for (i in 0...count)
		{
			var ch = value.charAt(i);
			result += ch == ' ' || ch == '\n' || age - i / rate >= settle ? ch : glyphs.charAt((Std.int(clock * 24) * 7 + i * 13) % glyphs.length);
		}
		return result;
	}

	function renderIntro():Void
	{
		for (entry in revealSprites) entry.sprite.alpha = entry.alpha * smooth((clock - entry.start) / .7);
		for (entry in revealTexts)
		{
			entry.text.alpha = smooth((clock - entry.start) / .4);
			if (entry.text == buttons[1] && paused) continue;
			entry.text.text = decode(entry.value, clock - entry.start, Math.max(16, entry.value.length / .9));
		}
		powerLine.visible = clock > .15 && clock < .9;
		powerLine.scale.x = 800 * smooth((clock - .15) / .55);
		powerLine.updateHitbox();
		powerLine.x = (1920 - powerLine.width) / 2;
		powerLine.alpha = 1 - smooth((clock - .55) / .35);
	}

	override function destroy():Void
	{
		FlxG.mouse.visible = previousMouse;
		if (ink.parent != null) ink.parent.removeChild(ink);
		ink.release();
		for (camera in [textCamera, worldCamera, creditsCamera]) if (camera != null) FlxG.cameras.remove(camera);
		textCamera = worldCamera = creditsCamera = null;
		pointer.put();
		revealSprites = [];
		revealTexts = [];
		ink = null;
		dots = [];
		projected = [];
		super.destroy();
	}
}
