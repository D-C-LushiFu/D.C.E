package states.freeplayState.objects.replay;

import haxe.Json;
import haxe.ds.ArraySort;
import openfl.display.BitmapData;
import openfl.display.GradientType;
import openfl.display.Shape;
import openfl.geom.Matrix;
import flixel.graphics.FlxGraphic;
import sys.FileSystem;
import sys.io.File;
import sys.thread.Mutex;
import server.util.EncryptUtil;
import games.backend.Replay.StateRecord;

enum ReplaySortMode
{
	DATE_DESC;
	DATE_ASC;
	SCORE_DESC;
	SCORE_ASC;
	ACC_DESC;
	ACC_ASC;
	COMBO_DESC;
	COMBO_ASC;
}

typedef ReplayData = {
	var songName:String;
	var difficulty:String;
	var playDate:String;
	var songScore:Int;
	var ratingPercent:Float;
	var ratingFC:String;
	var songHits:Int;
	var highestCombo:Int;
	var songMisses:Int;
	var rsdPath:String;
	var replayVersion:Int;
	var sickCount:Int;
	var goodCount:Int;
	var badCount:Int;
	var shitCount:Int;
	var botPlay:Bool;
}

class ReplayRect extends FlxSpriteGroup
{
	static public final fixWidth:Int = 464;
	static public final fixHeight:Int = 42;
	static var replayDataCache:Map<String, Array<ReplayData>> = new Map();
	static var gradeBackgroundCache:Map<String, FlxGraphic> = new Map();
	static var replayDataCacheMutex:Mutex = new Mutex();
	public static function clearCache():Void { replayDataCacheMutex.acquire(); replayDataCache.clear(); replayDataCacheMutex.release(); }

	public var data(default, null):ReplayData;
	public var onClick:Void->Void;
	public var onClickSettings:Void->Void;
	public var isHovered(default, null):Bool = false;

	var bg:FlxSprite;
    var bg2:FlxSprite;
	var gradeShine:states.freeplayState.objects.PhiPanel;
	var grade:String;
	var gradePulse:Float = 0;

	var settingsIcon:FlxSprite;
	var gradeText:FlxText;
	var scoreText:FlxText;
	var dateText:FlxText;
	var entryWidth:Float;
	var entryHeight:Float;

	public var realY:Float = 0;
	public var targetY:Float = 0;

	public function new(x:Float, y:Float, w:Float, h:Float, data:ReplayData)
	{
		super(x, y);
		realY = y;
		targetY = y;
		this.data = data;
		entryWidth = w;
		entryHeight = h;

        bg = new states.freeplayState.objects.PhiPanel(0, 0, Std.int(w), Std.int(h), 0xFF263444); add(bg);
		grade = getGradeStr();
		bg2 = new states.freeplayState.objects.PhiPanel(0, 0, Std.int(w), Std.int(h), FlxColor.WHITE);
		applyGradeBackground();
		add(bg2);
		if (isDynamicGrade(grade)) ensureGradeShine();

		// Settings icon on the far left
		settingsIcon = new FlxSprite(5, h / 2 - 12);
		settingsIcon.loadGraphic(Paths.image(FreeplayState.filePath + "function/options"));
		settingsIcon.setGraphicSize(24, 24);
		settingsIcon.updateHitbox();
		settingsIcon.antialiasing = ClientPrefs.data.antialiasing;
		add(settingsIcon);

		// Score - keep original position
		scoreText = new FlxText(w - 153, h / 2 - 13, 107, Std.string(data.songScore), 19);
		scoreText.setFormat(Paths.font(Language.get('fontName', 'main') + '.ttf'), 19, 0xFFFFFFFF, LEFT);
		scoreText.borderStyle = NONE;
		scoreText.antialiasing = ClientPrefs.data.antialiasing;
		add(scoreText);

		// Rating grade - keep original position
		gradeText = new FlxText(w - 65, h / 2 - 12, 60, grade, 17);
		gradeText.setFormat(Paths.font(Language.get('fontName', 'main') + '.ttf'), 17, 0xFFFFFFFF, RIGHT);
		gradeText.borderStyle = NONE;
		gradeText.antialiasing = ClientPrefs.data.antialiasing;
		add(gradeText);

		// Time/Date - keep original position
		try
		{
			var date:Date = Date.fromString(data.playDate);
			var dateStr:String = DateTools.format(date, "%Y-%m-%d %H:%M");
			dateText = new FlxText(38, h / 2 - 10, w - 210, dateStr, 15);
			dateText.setFormat(Paths.font(Language.get('fontName', 'main') + '.ttf'), 15, 0xCCD1DEE6, RIGHT);
			dateText.borderStyle = NONE;
			dateText.antialiasing = ClientPrefs.data.antialiasing;
			add(dateText);
		}
		catch (e:Dynamic)
		{
			dateText = new FlxText(38, h / 2 - 10, w - 210, data.playDate, 15);
			dateText.setFormat(Paths.font(Language.get('fontName', 'main') + '.ttf'), 15, 0xCCD1DEE6, RIGHT);
			dateText.borderStyle = NONE;
			dateText.antialiasing = ClientPrefs.data.antialiasing;
			add(dateText);
		}
	}

	public function moveY(target:Float)
	{
		targetY = target;
		realY = targetY;
		y = realY;
	}

	public function updateHover(mouseX:Float, mouseY:Float):Bool
	{
		var hovering:Bool = (mouseX >= x && mouseX <= x + entryWidth
			&& mouseY >= y && mouseY <= y + entryHeight);

		// Left ~50px zone = settings/data view, right side = replay
		var inSettingsZone:Bool = hovering && (mouseX >= x && mouseX <= x + 50);

		if (hovering && !isHovered)
		{
			isHovered = true;
			bg.color = 0xFF415366;
		}
		else if (!hovering && isHovered)
		{
			isHovered = false;
			bg.color = 0xFF263444;
		}

		if (hovering && FlxG.mouse.justPressed)
		{
			if (inSettingsZone && onClickSettings != null)
			{
				onClickSettings();
				return true;
			}
			if (!inSettingsZone && onClick != null)
			{
				onClick();
				return true;
			}
		}
		return false;
	}

	function getGradeStr():String
	{
		return ReplayGrade.calculate(data.ratingFC, data.songMisses,
			data.replayVersion >= 2 && data.songHits > 0,
			data.goodCount, data.badCount, data.shitCount);
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		if (isDynamicGrade(grade))
		{
			gradePulse += elapsed;
			// Keep the hue palette spatially varied, like the web preview; move a
			// soft grade-colored highlight across it instead of tinting the whole row.
			var travel = Math.max(0, entryWidth - gradeShine.panelWidth);
			var sweep = 0.5 - 0.5 * Math.cos(gradePulse * 1.75);
			// Sprite-group children use world coordinates after insertion.
			// Keep the entire sweep inside this row, including after scrolling.
			gradeShine.x = x + travel * sweep;
			gradeShine.y = y;
			gradeShine.alpha = 0.72 + 0.22 * (0.5 + 0.5 * Math.sin(gradePulse * 2.1));
			bg2.alpha = 0.84 + 0.06 * (0.5 + 0.5 * Math.sin(gradePulse * 1.7));
		}
	}

	public function bindData(next:ReplayData):Void
	{
		data = next;
		grade = getGradeStr();
		gradePulse = 0;
		isHovered = false;
		bg.color = 0xFF263444;
		applyGradeBackground();
		if (isDynamicGrade(grade)) ensureGradeShine();
		if (gradeShine != null) gradeShine.visible = isDynamicGrade(grade);
		scoreText.text = Std.string(data.songScore);
		gradeText.text = grade;
		try
		{
			dateText.text = DateTools.format(Date.fromString(data.playDate), "%Y-%m-%d %H:%M");
		}
		catch (e:Dynamic)
		{
			dateText.text = data.playDate;
		}
	}

	function ensureGradeShine():Void
	{
		if (gradeShine == null)
		{
			var shineWidth = Std.int(Math.min(230, entryWidth));
			gradeShine = new states.freeplayState.objects.PhiPanel(0, 0, shineWidth, Std.int(entryHeight), FlxColor.WHITE);
			insert(2, gradeShine);
		}
		gradeShine.loadGraphic(getGradientGraphic(grade, gradeShine.panelWidth, Std.int(entryHeight), true));
		gradeShine.color = FlxColor.WHITE;
		gradeShine.alpha = 0.95;
	}

	function applyGradeBackground():Void
	{
		bg2.loadGraphic(getGradientGraphic(grade, Std.int(entryWidth), Std.int(entryHeight), false));
		bg2.color = FlxColor.WHITE;
		bg2.alpha = isDynamicGrade(grade) ? 0.84 : 0.82;
	}

	static function getGradientGraphic(grade:String, width:Int, height:Int, shine:Bool):FlxGraphic
	{
		var key = grade + '|' + width + '|' + height + '|' + shine;
		var cached = gradeBackgroundCache.get(key);
		if (cached != null) return cached;
		var colors = shine ? getShineColors(grade) : getGradeColors(grade);
		var ratios = shine ? [0, 64, 142, 255] : [0, 56, 110, 151, 202, 255];
		var alphas:Array<Float> = shine ? [0, 0.30, 0.58, 0] : [0.96, 0.98, 1, 1, 0.98, 0.96];
		var shape = new Shape();
		var matrix = new Matrix();
		matrix.createGradientBox(width, height, 0, 0, 0);
		shape.graphics.beginGradientFill(GradientType.LINEAR, colors, alphas, ratios, matrix);
		var inset = height * states.freeplayState.objects.PhiPanel.SLOPE;
		shape.graphics.moveTo(inset, 0);
		shape.graphics.lineTo(width, 0);
		shape.graphics.lineTo(width - inset, height);
		shape.graphics.lineTo(0, height);
		shape.graphics.lineTo(inset, 0);
		shape.graphics.endFill();
		var bitmap = new BitmapData(width, height, true, 0);
		bitmap.draw(shape);
		var graphic = FlxGraphic.fromBitmapData(bitmap, false, null, false);
		// Replay rows are pooled and destroyed as songs change. These generated
		// grade textures are shared from a static cache, so Flixel must not dispose
		// them when the last row releases its reference.
		graphic.persist = true;
		gradeBackgroundCache.set(key, graphic);
		return graphic;
	}

	static function getGradeColors(grade:String):Array<Int>
	{
		return switch (grade)
		{
			case 'D.C.P': [0xFF4E091F, 0xFF710D2B, 0xFF941333, 0xFFBD1B3B, 0xFF81102C, 0xFF4E091F];
			case 'V': [0xFF4B1B25, 0xFF6B202B, 0xFF8F2930, 0xFFB13A32, 0xFF76232C, 0xFF4B1B25];
			case 'S': [0xFF493511, 0xFF684812, 0xFF876019, 0xFFAD791E, 0xFF725017, 0xFF493511];
			case 'A': [0xFF104A36, 0xFF206B4C, 0xFF31C878, 0xFF31C878, 0xFF206B4C, 0xFF104A36];
			case 'B': [0xFF10484A, 0xFF1A777A, 0xFF22C7C9, 0xFF22C7C9, 0xFF1A777A, 0xFF10484A];
			case 'C': [0xFF1D345A, 0xFF2D5590, 0xFF4388F5, 0xFF4388F5, 0xFF2D5590, 0xFF1D345A];
			default: [0xFF343C45, 0xFF59626B, 0xFF929BA5, 0xFF929BA5, 0xFF59626B, 0xFF343C45];
		}
	}

	static function getShineColors(grade:String):Array<Int>
	{
		return switch (grade)
		{
			case 'D.C.P': [0xFF9D1235, 0xFFFF7186, 0xFFEF3455, 0xFF8D0B31];
			case 'V': [0xFF9D322F, 0xFFFF9A6A, 0xFFF04C40, 0xFF8D2633];
			default: [0xFF9B681B, 0xFFFFE477, 0xFFFFB52C, 0xFF966014];
		}
	}

	static inline function isDynamicGrade(grade:String):Bool
	{
		return grade == 'D.C.P' || grade == 'V' || grade == 'S';
	}

	////////////////////////////////////////////////////////////////////////////////

	public static function loadReplayData(songName:String, difficulty:String, modFolder:String):Array<ReplayData>
	{
		var data:Array<ReplayData> = [];

		#if sys
		var songPath:String = Paths.formatToSongPath(songName);
		var diffFolder:String = difficulty.toUpperCase();
		var cacheKey = (modFolder == null ? '' : modFolder) + '|' + songPath + '|' + diffFolder;
		replayDataCacheMutex.acquire();
		var cached = replayDataCache.get(cacheKey);
		replayDataCacheMutex.release();
		if (cached != null) return cached.copy();
		var seen:Map<String, Bool> = new Map<String, Bool>();

		if (!FileSystem.exists('replays/') || !FileSystem.isDirectory('replays/'))
		{
			replayDataCacheMutex.acquire(); replayDataCache.set(cacheKey, data.copy()); replayDataCacheMutex.release();
			return data;
		}

		var modDirs:Array<String> = [];
		for (mod in FileSystem.readDirectory('replays/'))
		{
			if (FileSystem.isDirectory('replays/$mod'))
				modDirs.push(mod);
		}

		// Try the current mod first, then all others
		var currentMod:String = (modFolder == '' || modFolder == null) ? 'originFunkin' : modFolder;
		var sortedMods:Array<String> = [];
		sortedMods.push(currentMod);
		for (mod in modDirs)
		{
			if (mod != currentMod && sortedMods.indexOf(mod) < 0)
				sortedMods.push(mod);
		}

		for (modDir in sortedMods)
		{
			var searchDir:String = 'replays/$modDir/$songPath/$diffFolder/';
			if (!FileSystem.exists(searchDir) || !FileSystem.isDirectory(searchDir))
				continue;

			for (file in FileSystem.readDirectory(searchDir))
			{
				if (!StringTools.endsWith(file, '.txt'))
					continue;

				var txtPath:String = searchDir + file;
				var rsdFile:String = StringTools.replace(file, '.txt', '.rsd');
				var rsdPath:String = searchDir + rsdFile;

				if (!FileSystem.exists(rsdPath))
					continue;

				// Avoid duplicate entries (same rsd file name)
				var key:String = file;
				if (seen.exists(key))
					continue;
				seen.set(key, true);

				var parsed:ReplayData = parseReplayTxt(txtPath, rsdPath);
				if (parsed != null)
					data.push(parsed);
			}
		}
		replayDataCacheMutex.acquire(); replayDataCache.set(cacheKey, data.copy()); replayDataCacheMutex.release();
		#end

		return data;
	}

	public static function sortReplays(data:Array<ReplayData>, mode:ReplaySortMode):Array<ReplayData>
	{
		ArraySort.sort(data, function(a:ReplayData, b:ReplayData):Int
		{
			return switch (mode)
			{
				case DATE_DESC:
					try { Reflect.compare(Date.fromString(b.playDate).getTime(), Date.fromString(a.playDate).getTime()); }
					catch (e:Dynamic) { 0; }
				case DATE_ASC:
					try { Reflect.compare(Date.fromString(a.playDate).getTime(), Date.fromString(b.playDate).getTime()); }
					catch (e:Dynamic) { 0; }
				case SCORE_DESC:
					Reflect.compare(b.songScore, a.songScore);
				case SCORE_ASC:
					Reflect.compare(a.songScore, b.songScore);
				case ACC_DESC:
					Reflect.compare(b.ratingPercent, a.ratingPercent);
				case ACC_ASC:
					Reflect.compare(a.ratingPercent, b.ratingPercent);
				case COMBO_DESC:
					Reflect.compare(b.highestCombo, a.highestCombo);
				case COMBO_ASC:
					Reflect.compare(a.highestCombo, b.highestCombo);
			}
		});
		return data;
	}

	static function parseReplayTxt(txtPath:String, rsdPath:String):ReplayData
	{
		#if sys
		try
		{
			var content:String = File.getContent(txtPath);
			var lines:Array<String> = content.split('\n');
			var map:Map<String, String> = new Map<String, String>();

			for (line in lines)
			{
				var idx:Int = line.indexOf(': ');
				if (idx > 0)
				{
					map.set(line.substring(0, idx), line.substring(idx + 2));
				}
			}

			var ratingStr:String = map.get('Rating');
			var ratingPercent:Float = 0;
			var ratingFC:String = 'N/A';
			if (ratingStr != null)
			{
				var parts:Array<String> = ratingStr.split(' (');
				ratingPercent = Std.parseFloat(parts[0]);
				if (parts.length > 1)
					ratingFC = StringTools.replace(parts[1], ')', '');
			}

		var version:Int = Std.parseInt(map.get('Replay Version'));
			if (Math.isNaN(version)) version = 1; // old replays default to v1

			return {
				songName: map.get('Song Name'),
				difficulty: map.get('Difficulty'),
				playDate: map.get('Date'),
				songScore: Std.parseInt(map.get('Score')),
				ratingPercent: ratingPercent,
				ratingFC: ratingFC,
				songHits: Std.parseInt(map.get('Hits')),
				highestCombo: Std.parseInt(map.get('Highest Combo')),
				songMisses: Std.parseInt(map.get('Misses')),
				rsdPath: rsdPath,
				replayVersion: version,
				sickCount: version >= 2 ? Std.parseInt(map.get('Sick Count')) : 0,
				goodCount: version >= 2 ? Std.parseInt(map.get('Good Count')) : 0,
				badCount: version >= 2 ? Std.parseInt(map.get('Bad Count')) : 0,
				shitCount: version >= 2 ? Std.parseInt(map.get('Shit Count')) : 0,
				botPlay: version >= 2 ? (map.get('Bot Play') == 'true') : false
			};
		}
		catch (e:Dynamic) {}
		#end
		return null;
	}

	public static function loadStateRecord(rsdPath:String):StateRecord
	{
		#if sys
		try
		{
			var content:String = File.getContent(rsdPath);
			content = EncryptUtil.aesDecrypt(content);
			var json:Dynamic = Json.parse(content);
			return json.stateRecord;
		}
		catch (e:Dynamic)
		{
			trace('Failed to load StateRecord from: $rsdPath, error: $e');
		}
		#end
		return null;
	}
}
