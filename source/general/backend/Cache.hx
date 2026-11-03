package general.backend;

import sys.thread.Mutex;

import openfl.media.Sound;

import flixel.graphics.frames.FlxFramesCollection;
import flixel.graphics.frames.FlxFrame;
import flixel.graphics.FlxGraphic;
import flixel.animation.FlxAnimationController;

class Cache {
	static var localAssetsMutex:Mutex = new Mutex();

	public static function trackLocalAsset(key:String):Void
	{
		if (key == null)
			return;

		localAssetsMutex.acquire();
		if (!localTrackedAssets.contains(key))
			localTrackedAssets.push(key);
		localAssetsMutex.release();
	}

	public static function isLocalAsset(key:String):Bool
	{
		localAssetsMutex.acquire();
		var result:Bool = localTrackedAssets.contains(key);
		localAssetsMutex.release();
		return result;
	}

	public static function resetLocalAssets():Void
	{
		localAssetsMutex.acquire();
		localTrackedAssets = [];
		localAssetsMutex.release();
	}

    // define the locally tracked assets
	public static var localTrackedAssets:Array<String> = [];  //用于列举当前状态的所有资源（包括图形，声音）

    public static var currentTrackedAssets:Map<String, FlxGraphic> = []; //用于列举当前状态的所有图形资源

    public static var currentTrackedSounds:Map<String, Sound> = []; //用于列举当前状态的所有声音资源

	public static var currentTrackedFrames:Map<String, {graphic:FlxGraphic, frame:FlxFramesCollection}> = []; //用于列举当前状态的所有图形资源

	public static var currentTrackedAnims:Map<String, FlxAnimationController> = []; //用于列举当前状态的所有动画资源

    public static function excludeAsset(key:String)
	{
		if (!dumpExclusions.contains(key))
			dumpExclusions.push(key);
	}

	public static var dumpExclusions:Array<String> = [
		'assets/shared/music/freakyMenu.$Paths.SOUND_EXT',
		'assets/shared/music/breakfast.$Paths.SOUND_EXT',
		'assets/shared/music/tea-time.$Paths.SOUND_EXT',
	];

	public static function setFrame(key:String, data:{graphic:FlxGraphic, frame:FlxFramesCollection})
	{
		Cache.currentTrackedFrames.set(key, data);
	}

	public static function checkFrame(key:String):Bool
	{
		if (key == null) return false;

		var data = currentTrackedFrames.get(key);
		if (data == null) return false;

		if (data.graphic != null
			&& data.graphic.imageFrame != null 
			&& data.graphic.imageFrame.frames != null 
			&& data.graphic.imageFrame.frames.length > 0) {
			return true;
		}

		if (data.frame != null 
			&& data.frame.frames != null 
			&& data.frame.frames.length > 0) {
			return true;
		}

		currentTrackedFrames.remove(key);
		return false;
	}

	/**
	 * 取缓存帧。
	 *
	 * ★★ 这里必须判空 —— 这是踩过的真崩溃（2026-10-01）。★★
	 *
	 * 原实现是：
	 *     if (currentTrackedFrames.get(key).frame != null) { … }
	 * `Map.get(key)` 在 **key 尚未缓存**时返回 null，紧接着的 `.frame` 就是解引用空指针。
	 * 在 hxcpp 上表现为 `EXCEPTION_ACCESS_VIOLATION / access_address=0x0`，
	 * 崩溃报告的 `fault_module_rva` 正好落在本函数内部（实测 0x96c3d9），
	 * 而调用栈是关着的 —— 也就是说：**任何一次"取一个还没缓存过的 key"都会直接把进程干掉**，
	 * 而且完全看不出是谁调用的。
	 *
	 * 语义澄清：调用方本来就该处理"没有缓存"这种情况（所有 shapeEx / Note / HealthIcon 的
	 * 调用点都是 `if (!checkFrame(key)) addCache(…)` 再 getFrame），所以这里返回 null
	 * 才是正确行为，而不是需要防御的异常。
	 */
	public static function getFrame(key:String):FlxFramesCollection
	{
		if (key == null) return null;

		var data = currentTrackedFrames.get(key);
		if (data == null) return null;

		if (data.frame != null) {
			return data.frame;
		} else if (data.graphic != null) {
			return data.graphic.imageFrame;
		}
		return null;
	}
}
