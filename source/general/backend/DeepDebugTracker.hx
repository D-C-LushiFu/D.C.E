package general.backend;

#if sys
import haxe.Timer;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.thread.Mutex;
#end

using StringTools;

/**
 * Collects the resources resolved and loaded during one PlayState session.
 *
 * The tracker stays completely idle unless a song session explicitly starts it.
 * LoadingState can call record methods from worker threads, so all mutations of
 * the resource map are protected by a mutex.
 */
class DeepDebugTracker
{
	public static var active(default, null):Bool = false;
	public static var lastReportPath(default, null):String = null;

	static var songName:String = '';
	static var modFolder:String = '';
	static var difficultyName:String = '';
	static var startedAt:Date = null;
	static var startedStamp:Float = 0;
	static var resources:Map<String, Array<String>> = [];

	#if sys
	static var resourceMutex:Mutex = new Mutex();
	#end

	public static function begin(song:String, mod:String, difficulty:String):Void
	{
		#if sys
		if (active)
			finish('replaced_by_new_song');

		resourceMutex.acquire();
		resources = [];
		songName = normalizeLabel(song, 'unknown-song');
		modFolder = normalizeLabel(mod, 'originFunkin');
		difficultyName = normalizeLabel(difficulty, 'Unknown');
		startedAt = Date.now();
		startedStamp = Timer.stamp();
		lastReportPath = null;
		active = true;
		resourceMutex.release();

		trace('[DeepDebug] Started resource tracking: song=$songName mod=$modFolder difficulty=$difficultyName');
		#end
	}

	public static function recordScript(kind:String, path:String):Void
	{
		record('Scripts - $kind', path);
	}

	public static function recordResolved(path:String):Void
	{
		if (!active || path == null || path.length == 0)
			return;

		var lower:String = path.toLowerCase();
		var category:String;
		if (hasExtension(lower, ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp']))
			category = 'Images';
		else if (hasExtension(lower, ['.ogg', '.mp3', '.wav', '.flac', '.aac']))
			category = 'Audio';
		else if (hasExtension(lower, ['.mp4', '.webm', '.mkv', '.avi', '.mov']))
			category = 'Videos';
		else if (hasExtension(lower, ['.frag', '.vert', '.glsl']))
			category = 'Shaders';
		else if (hasExtension(lower, ['.ttf', '.otf', '.woff', '.woff2']))
			category = 'Fonts';
		else if (StringTools.endsWith(lower, '.lua'))
			category = 'Scripts - Lua';
		else if (StringTools.endsWith(lower, '.hx'))
			category = 'Scripts - HScript';
		else if (hasExtension(lower, ['.xml', '.json', '.txt', '.csv', '.ini', '.atlas']))
			category = 'Data and atlases';
		else
			category = 'Other resources';

		record(category, path);
	}

	public static function record(category:String, value:String):Void
	{
		#if sys
		if (!active || category == null || value == null)
			return;

		var normalized:String = normalizePath(value);
		if (normalized.length == 0)
			return;

		resourceMutex.acquire();
		if (active)
		{
			var entries:Array<String> = resources.get(category);
			if (entries == null)
			{
				entries = [];
				resources.set(category, entries);
			}
			if (!entries.contains(normalized))
				entries.push(normalized);
		}
		resourceMutex.release();
		#end
	}

	public static function finish(reason:String):Void
	{
		#if sys
		if (!active)
			return;

		captureRuntimeCache();

		var snapshot:Map<String, Array<String>> = [];
		var finishedAt:Date = Date.now();
		var elapsedMs:Int = Std.int(Math.max(0, (Timer.stamp() - startedStamp) * 1000));
		var reportSong:String;
		var reportMod:String;
		var reportDifficulty:String;
		var reportStartedAt:Date;

		resourceMutex.acquire();
		if (!active)
		{
			resourceMutex.release();
			return;
		}
		for (category => entries in resources)
			snapshot.set(category, entries.copy());
		reportSong = songName;
		reportMod = modFolder;
		reportDifficulty = difficultyName;
		reportStartedAt = startedAt;
		active = false;
		resourceMutex.release();

		try
		{
			var programDirectory:String = Path.directory(Sys.programPath());
			if (programDirectory == null || programDirectory.length == 0)
				programDirectory = Sys.getCwd();

			var outputDirectory:String = Path.join([
				programDirectory,
				'debug',
				sanitizeFileName(reportMod, 'originFunkin'),
				sanitizeFileName(reportDifficulty, 'Unknown')
			]);
			FileSystem.createDirectory(outputDirectory);

			var outputFile:String = Path.join([
				outputDirectory,
				sanitizeFileName(reportSong, 'unknown-song') + '.txt'
			]);
			File.saveContent(outputFile, buildReport(
				snapshot,
				reportSong,
				reportMod,
				reportDifficulty,
				reportStartedAt,
				finishedAt,
				elapsedMs,
				reason
			));
			lastReportPath = outputFile;
			trace('[DeepDebug] Resource report saved: $outputFile');
		}
		catch (error:Dynamic)
		{
			trace('[DeepDebug] Failed to save resource report: $error');
		}
		#end
	}

	#if sys
	static function captureRuntimeCache():Void
	{
		for (key in Cache.localTrackedAssets)
			recordResolved(key);
		for (key in Cache.currentTrackedFrames.keys())
			record('Runtime frame cache keys', key);
		for (key in Cache.currentTrackedAnims.keys())
			record('Runtime animation cache keys', key);
	}

	static function buildReport(snapshot:Map<String, Array<String>>, reportSong:String, reportMod:String,
			reportDifficulty:String, reportStartedAt:Date, finishedAt:Date, elapsedMs:Int, reason:String):String
	{
		var lineBreak:String = '\r\n';
		var output:StringBuf = new StringBuf();
		var totalResources:Int = 0;
		for (entries in snapshot)
			totalResources += entries.length;

		output.add('D.C.E. Deep Debug Resource Report$lineBreak');
		output.add('================================================$lineBreak');
		output.add('Song: $reportSong$lineBreak');
		output.add('Mod folder: $reportMod$lineBreak');
		output.add('Difficulty: $reportDifficulty$lineBreak');
		output.add('Started: ${reportStartedAt == null ? "Unknown" : reportStartedAt.toString()}$lineBreak');
		output.add('Finished: ${finishedAt.toString()}$lineBreak');
		output.add('Elapsed: ${elapsedMs} ms$lineBreak');
		output.add('Finish reason: ${normalizeLabel(reason, "unknown")}$lineBreak');
		output.add('Unique recorded resources: $totalResources$lineBreak');
		output.add(lineBreak);
		output.add('The report contains paths resolved or loaded while this song session was active.$lineBreak');
		output.add('Entries are de-duplicated and sorted inside each category.$lineBreak');
        output.add('对于写入源码的歌曲，路径可能会显示为相对路径或内联资源。$lineBreak');
		output.add('For songs embedded in the source code, the path may appear as a relative path or an inline resource.$lineBreak');

		var categories:Array<String> = [
			'Scripts - Lua',
			'Scripts - HScript',
			'Images',
			'Audio',
			'Videos',
			'Shaders',
			'Fonts',
			'Data and atlases',
			'Runtime frame cache keys',
			'Runtime animation cache keys',
			'Other resources'
		];
		for (category in snapshot.keys())
			if (!categories.contains(category))
				categories.push(category);

		for (category in categories)
		{
			var entries:Array<String> = snapshot.get(category);
			if (entries == null || entries.length == 0)
				continue;

			entries.sort(comparePaths);
			output.add(lineBreak);
			output.add('[$category] (${entries.length})$lineBreak');
			for (entry in entries)
				output.add('- $entry$lineBreak');
		}
		return output.toString();
	}

	static function comparePaths(a:String, b:String):Int
	{
		var lowerA:String = a.toLowerCase();
		var lowerB:String = b.toLowerCase();
		return lowerA < lowerB ? -1 : (lowerA > lowerB ? 1 : 0);
	}

	static function hasExtension(path:String, extensions:Array<String>):Bool
	{
		for (extension in extensions)
			if (StringTools.endsWith(path, extension))
				return true;
		return false;
	}

	static function normalizePath(value:String):String
	{
		var normalized:String = StringTools.trim(value).replace('\\', '/');
		if (normalized.indexOf('\n') != -1 || normalized.indexOf('\r') != -1)
			return '[inline or generated resource]';
		return normalized;
	}

	static function normalizeLabel(value:String, fallback:String):String
	{
		if (value == null || StringTools.trim(value).length == 0)
			return fallback;
		return StringTools.trim(value);
	}

	static function sanitizeFileName(value:String, fallback:String):String
	{
		var source:String = normalizeLabel(value, fallback);
		var invalid:String = '<>:"/\\|?*';
		var buffer:StringBuf = new StringBuf();
		for (index in 0...source.length)
		{
			var character:String = source.charAt(index);
			var code:Null<Int> = source.charCodeAt(index);
			buffer.add(code == null || code < 32 || invalid.indexOf(character) != -1 ? '_' : character);
		}

		var result:String = StringTools.trim(buffer.toString());
		while (result.length > 0 && (StringTools.endsWith(result, '.') || StringTools.endsWith(result, ' ')))
			result = result.substr(0, result.length - 1);
		if (result.length == 0)
			result = fallback;

		var upper:String = result.toUpperCase();
		var reserved:Array<String> = ['CON', 'PRN', 'AUX', 'NUL',
			'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
			'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'];
		if (reserved.contains(upper))
			result = '_$result';
		return result;
	}
	#end
}
