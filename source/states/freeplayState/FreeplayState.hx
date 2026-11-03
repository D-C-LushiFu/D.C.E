package states.freeplayState;

import haxe.Json;
import haxe.ds.ArraySort;

import sys.thread.Mutex;
import sys.io.File;

import openfl.system.System;
import openfl.display.BitmapData;
import openfl.display.BitmapDataChannel;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import flixel.graphics.FlxGraphic;

import developer.editors.ChartingState;

import options.OptionsState;

import states.mainMenuState.MainMenuState;
import states.storyMenuState.StoryMenuState;
import states.modsMenuState.ModsMenuState;
import states.freeplayState.backend.*;
import states.freeplayState.objects.detail.*;
import states.freeplayState.objects.down.*;
import states.freeplayState.objects.others.*;
import states.freeplayState.objects.select.*;
import states.freeplayState.objects.song.*;
import states.freeplayState.objects.replay.*;

import states.freeplayState.objects.replay.ReplayRect.ReplaySortMode;
import states.freeplayState.objects.replay.ReplayRect.ReplayData;

import substates.GameplayChangersSubstate;
import substates.ResetScoreSubState;

import games.backend.WeekData;
import games.backend.Highscore;
import games.backend.Song;
import games.backend.Song.SwagSong;
import games.backend.StageData;
import games.backend.Replay;
import games.backend.Replay.StateRecord;
import substates.ResultsScreen;
import games.backend.diffCalc.DiffRating;
import general.shapeEx.RoundRect;
import general.shapeEx.RoundRect.OriginType;
import general.objects.screen.MouseEffect;
import general.objects.AudioDisplay;
import general.backend.language.Language;
import states.freeplayState.objects.PhigrosFreeplayView;
import lime.media.AudioBuffer;
#if lime_vorbis
import lime.media.vorbis.VorbisFile;
#end
import openfl.media.Sound;
import states.freeplayState.objects.PhiPreviewBuffers;

class FreeplayState extends MusicBeatState
{
	static final DEFAULT_DIFFICULTY_COLORS:Map<String, FlxColor> = [
		'baby' => 0xFF54C9FF,
		'eazy' => 0xFF31C878,
		'easy' => 0xFF31C878,
		'normal' => 0xFFFFC83D,
		'hard' => 0xFFEF303D
	];
	static public var filePath:String = 'menuExtendHide/freeplay/';
	static public var instance:FreeplayState;

	static public var curSelected:Int = 0;
	static public var curDifficulty:Int = -1;
	public var curFunc:Int = -1;
	static public var curFuncBack:Int = 0;

	public var keyboardState:Int = 0;

	public var stopAll:Bool = false;

	///////////////////////////////////////////////////////////////////////////////////////////////

	var songsData:Array<SongMetadata> = [];

	public var songGroup:Array<SongRect> = [];
	public var songsMove:MouseMove;

	var camBG:FlxCamera;
	var camSongs:FlxCamera;
	var camReplay:FlxCamera;
	var camAfter:FlxCamera;

	public static var vocalsPlayer1:FlxSound;
	public static var vocalsPlayer2:FlxSound;

	public var mouseEvent:MouseEvent;

	///////////////////////////////////////////////////////////////////////////////////////////////

	var background:ChangeSprite;
	var intendedColor:Int;
	var backgroundRequestId:Int = 0;
	var backgroundLoadTimer:FlxTimer;
	var selectedBackgroundGraphic:FlxGraphic;
	var detailRequestId:Int = 0;
	var replayRequestId:Int = 0;
	var detailLoadTimer:FlxTimer;
	var stateDestroyed:Bool = false;

	var detailRect:DetailRect;
    var phiView:PhigrosFreeplayView;
    public var phiSongOrder:Array<Int> = [];
    public var phiFavoritesOnly:Bool = false;
    public var phiAudioVisible:Bool = true;
    public var phiSortLabel:String = '曲目顺序';
    var phiSort:Int = 0;
    var phiSearch:String = '';
    var phiRatings:Map<String, Float> = new Map();
    var phiAvailableDifficulties:Map<Int, Array<Int>> = new Map();
    var phiChartPaths:Map<String, String> = new Map();
    var phiResults:sys.thread.Deque<Void->Void> = new sys.thread.Deque<Void->Void>();
    var phiResultMutex:Mutex = new Mutex();

    function postPhiResult(callback:Void->Void, ?discard:Void->Void):Void {
        phiResultMutex.acquire();
        var accepted = !stateDestroyed;
        if (accepted) phiResults.add(function():Void {
            if (stateDestroyed) { if (discard != null) discard(); }
            else callback();
        });
        phiResultMutex.release();
        if (!accepted && discard != null) discard();
    }

    function drainPhiResults():Void {
        var deadline = haxe.Timer.stamp() + 0.003;
        for (_ in 0...32) {
            var callback = phiResults.pop(false);
            if (callback == null) break;
            var started = haxe.Timer.stamp();
            if (!stateDestroyed) callback();
            var durationMs = (haxe.Timer.stamp() - started) * 1000;
            if (durationMs > 16) trace('FREEPLAY MAIN CALLBACK: ' + Math.round(durationMs) + 'ms');
            if (haxe.Timer.stamp() >= deadline) break;
        }
    }
    var ratingWarmupId:Int = 0;
    static var sessionRatings:Map<String, Float> = new Map();
    var difficultyColorCache:Map<String, FlxColor> = new Map();
    public var previewSpeed:Float = 1.0;
    var previewPitchSemitones:Int = 0;
    public var previewPlaybackRate(get, never):Float;
    inline function get_previewPlaybackRate():Float return previewSpeed * Math.pow(2, previewPitchSemitones / 12);
    var heldBrowseDirection:Int = 0;
    var heldBrowseElapsed:Float = 0;
    var heldBrowseRepeat:Float = 0;
    var phiFavorites:Array<String> = [];
    var phiPointer:FlxPoint = new FlxPoint();
    public var phiMouseX(get, never):Float;
    public var phiMouseY(get, never):Float;
    inline function get_phiMouseX():Float return phiPointer.x;
    inline function get_phiMouseY():Float return phiPointer.y;
	var hybridCoverArt:FlxSprite;
	var hybridProgressBG:FlxSprite;
	var hybridProgressFill:FlxSprite;
	var hybridProgressElapsed:FlxText;
	var hybridProgressLength:FlxText;
	var hybridUserPanel:Rect;
	var hybridUserText:FlxText;
	var hybridHeader:FlxText;
	var hybridAverageText:FlxText;
	var hybridStartButton:Rect;
	var hybridStartLabel:FlxText;
	var hybridDifficultyRects:Array<RoundRect> = [];
	var hybridDifficultyLabels:Array<FlxText> = [];
	var previewSpectrum:AudioDisplay;
    var previewVoiceSpectrum:AudioDisplay;
    var previewOpponentSpectrum:AudioDisplay;
    var previewVoices:Array<FlxSound> = [];
    var previewAudioBuffers:Array<AudioBuffer> = [];
    var previewInstSound:Sound;
    #if sys
    var debugSession:states.freeplayState.objects.PhiDebugSession;
    var debugMode:Bool = false;
    #end
    var previewVoiceSyncCooldown:Float = 0;
    var pendingAudioPath:String = "";
    var previewDelayStarted:Bool = false;
    var previewDelayActive:Bool = false;
    var previewDelayRemaining:Float = 0;
    var deferredPreviewSong:SwagSong = null;
    var deferredPreviewDetailId:Int = -1;

	var detailMusican:FlxText;

	var detailPlaySign:FlxSprite;
	var detailPlayText:FlxText;

	var detailTimeSign:FlxSprite;
	var detailTimeText:FlxText;

	var detailBpmSign:FlxSprite;
	var detailBpmText:FlxText;

	var detailRate:StarRect;
	var detailMapper:FlxText;

	var noteData:DataDis;
	var holdNoteData:DataDis;
	var speedData:DataDis;
	var keyCountData:DataDis;

	///////////////////////////////////////////////////////////////////////////////////////////////

	var replayGroup:Array<ReplayRect> = [];
	var replayDataList:Array<ReplayData> = [];
	public var replayMove:MouseMove;
	public var replaySortMode:ReplaySortMode = DATE_DESC;
	public var replayPosiData:Float = 0;
	public var replayStartX:Float = 797;
	public var replayStartY:Float = 840;
	public var replaySlope:Float = 0.03;

	var replaySortBtn:Array<RoundRect> = [];
	var replaySortLabel:Array<FlxText> = [];
	var replaySortText:FlxText;
	var replayNoDataText:FlxText;
	var replayTitleText:FlxText;

	///////////////////////////////////////////////////////////////////////////////////////////////

	var funcData:Array<String> = ['options', 'mod', 'changer', 'editor', 'reset', 'random'];
	var funcColors:Array<FlxColor> = [0x63d6ff, 0xd1fc52, 0xff354e, 0xff617e, 0xfd6dff, 0x6dff6d];
	var downBG:Rect;
	var backRect:BackButton;
	var funcGroup:Array<FuncButton> = [];

	///////////////////////////////////////////////////////////////////////////////////////////////

	var selectedBG:SkewRoundRect;
	public var searchButton:SearchButton;

	public var isSearchActive:Bool = false;
	public var searchJustUnfocused:Bool = false;
	var searchVolumeShortcutsSuppressed:Bool = false;
	var savedVolumeUpKeys:Dynamic = null;
	var savedVolumeDownKeys:Dynamic = null;

	var noMatchText:FlxText;
	var searchCountText:FlxText;

	override function create()
	{
		super.create();
		Language.refreshGroup('freeplay');
		phiSortLabel = [PhigrosFreeplayView.textFor('sortOrder', '曲目顺序', 'Song order'), PhigrosFreeplayView.textFor('sortName', '曲名', 'Song name'), PhigrosFreeplayView.textFor('sortScore', '最高分', 'Best score')][phiSort];

		Song.forceEngineVersion = null;

		instance = this;
        #if sys
        debugMode = Sys.getEnv('DCE_FREEPLAY_CHECK') != null;
        #end
		// The global star trail is implemented as a separate OpenFL display
		// list.  On this shader-heavy page it made a 1000 Hz mouse allocate
		// roughly 25 MB/s extra and reduced the measured frame rate to ~100.
		// Click feedback remains active and other states still use the trail.
		MouseEffect.trailEnabled = false;

		FlxG.mouse.visible = !ClientPrefs.data.needMobileControl;

		mouseEvent = new MouseEvent();
		add(mouseEvent);

		persistentUpdate = true;
		PlayState.isStoryMode = false;
		WeekData.reloadWeekFiles(false);

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence
		DiscordClient.changePresence("In the Menus", null);
		#end

		for (i in 0...WeekData.weeksList.length)
		{
			if (weekIsLocked(WeekData.weeksList[i]))
				continue;

			var leWeek:WeekData = WeekData.weeksLoaded.get(WeekData.weeksList[i]);

			WeekData.setDirectoryFromWeek(leWeek);

			for (song in leWeek.songs)
			{
				var colors:Array<Int> = song[2];
				if (colors == null || colors.length < 3)
				{
					colors = [146, 113, 253];
				}
				var muscan:String = song[3];
				if (song[3] == null)
					muscan = 'N/A';
				var charter:Array<String> = song[4];
				if (song[4] == null)
					charter = ['N/A', 'N/A', 'N/A'];
				songsData.push(new SongMetadata(song[0], i, song[1], muscan, charter, colors));
			}
		}

		Mods.loadTopMod();

		//////////////////////////////////////////////////////////////////////////////////////////

        // Build native 1920 x 1080 textures and type; scale the camera uniformly to the viewport.
        // Keep the engine's default camera first so FlxG.camera stays stable;
        // the design camera is appended above it for Freeplay content.
        camBG = FlxG.camera; camBG.bgColor = 0x00000000;
        camAfter = new FlxCamera(0, 0, 1920, 1080, Math.min(FlxG.width / 1920, FlxG.height / 1080));
        camAfter.bgColor = 0x00000000;
        FlxG.cameras.add(camAfter, false);
        camSongs = camReplay = camAfter;
        for (camera in [camBG, camAfter]) {
            camera.flashSprite.mouseEnabled = false; camera.flashSprite.mouseChildren = false;
        }
        for (i in 0...songsData.length) {
            var data = songsData[i]; Mods.currentModDirectory = data.folder;
            var model = new SongRect(data.songName, data.songCharacter, data.songMusican, data.songCharter, data.color, true);
            model.id = i; model.visible = model.active = false; add(model); songGroup.push(model);
        }
        if (FlxG.save.data.dceFreeplayFavorites != null) phiFavorites = cast FlxG.save.data.dceFreeplayFavorites;
        phiView = new PhigrosFreeplayView(this); phiView.cameras = [camAfter]; add(phiView);
        previewSpectrum = phiView.spectrum;
        previewVoiceSpectrum = phiView.voicesSpectrum;
        previewOpponentSpectrum = phiView.opponentSpectrum;
        detailBpmText = phiView.bpmValue; detailTimeText = phiView.durationValue;
        replayNoDataText = phiView.recordsEmpty; replaySortText = phiView.recordsInfo;
        // Retain asynchronous numeric animation without drawing the old two-line widgets.
        noteData = new DataDis(0, 0, 1, 1, '', 0, 100); holdNoteData = new DataDis(0, 0, 1, 1, '', 0, 100);
        speedData = new DataDis(0, 0, 1, 1, '', 0, 4); keyCountData = new DataDis(0, 0, 1, 1, '', 0, 9);
        for (data in [noteData, holdNoteData, speedData, keyCountData]) { data.visible = data.active = false; add(data); }
        searchButton = new SearchButton(600, 63, 816, 83); searchButton.cameras = [camAfter];
        searchButton.visible = searchButton.active = false; searchButton.onSearchChange = startSearch; add(searchButton);
        vocalsPlayer1 = FlxG.sound.music; vocalsPlayer2 = null;
        WeekData.setDirectoryFromWeek(); rebuildPhiOrder();
        if (songGroup.length > 0) selectPhiSong(Std.int(FlxMath.bound(curSelected, 0, songGroup.length - 1)), false);
        warmPhiRatings();

		#if windows
		var currentWindow = lime.app.Application.current.window;
		currentWindow.title = "D.C.E.";
		#end
	}

	function weekIsLocked(name:String):Bool
	{
		var leWeek:WeekData = WeekData.weeksLoaded.get(name);
		return (!leWeek.startUnlocked
			&& leWeek.weekBefore.length > 0
			&& (!StoryMenuState.weekCompleted.exists(leWeek.weekBefore) || !StoryMenuState.weekCompleted.get(leWeek.weekBefore)));
	}

	function outputEvent(name:String):() -> Void {
		switch (name) {
			case 'options':
				return function() {
				stopAll = true;
				OptionsState.stateType = 1;
				MusicBeatState.switchState(new OptionsState());
			};
			case 'mod':
				return function() {
				stopAll = true;
				ModsMenuState.isFreePlay = true;
				MusicBeatState.switchState(new ModsMenuState());
			};
			case 'changer':
				return function() {
				persistentUpdate = false;
				openSubState(new GameplayChangersSubstate());
			};
			case 'editor':
				return function() {
				stopAll = true;
				MusicBeatState.switchState(new ChartingState());
			};
			case 'reset':
				return function() {
				persistentUpdate = false;
				openSubState(new ResetScoreSubState(songsData[curSelected].songName, curDifficulty, songsData[curSelected].songCharacter, -1)); };
			case 'random':
				return function() {
				curSelected = FlxG.random.int(0, songGroup.length - 1);
				changeSelection();
				songGroup[curSelected].changeSelectAll();
			};
		}
		return null;
	}

	///////////////////////////////////////////////////////////////////////////////////

	public final songPosiStart:Float = 720 * 0.3;
	public static var songPosiData:Float = 720 * 0.3; //神人haxe不能用FlxG.height
	public var rectInter:Float = 0.97;
	public function songMoveEvent(){
		if (songGroup.length <= 0) return;
		var scrolling:Bool = songsMove != null && songsMove.state != 'stop';
		for (i in 0...songGroup.length) {
			songGroup[i].moveY(songPosiData + getEffectiveId(songGroup[i].id) * SongRect.fixHeight * rectInter);
			// Horizontal arc easing is only visible for rows in the viewport.
			// Avoid pow/lerp work for the other ~50 mod rows on every drag frame.
			if (updateSongVisibility(songGroup[i])) {
				songGroup[i].calcX();
				songGroup[i].setScrollRendering(scrolling);
			}
		}
	}

	public function getEffectiveId(id:Int):Int {
		if (!isSearchActive) return id;
		var count = 0;
		for (j in 0...id) {
			if (songGroup[j].searchMatch) count++;
		}
		return count;
	}

	var holdTime:Float = 0;
	var childUpdateElapsed:Float = 0;
    var lastChildUpdateTick:Int = -1;

	public var allowUpdate:Bool = false;
    override function update(elapsed:Float)
    {
        suppressSearchVolumeShortcuts(searchButton != null && searchButton.hasFocus);
        drainPhiResults();
        states.freeplayState.objects.PhiWorker.collectIdlePressure();
        if (previewDelayActive && !stopAll && !stateDestroyed) {
            previewDelayRemaining -= elapsed;
            if (previewDelayRemaining <= 0) {
                previewDelayRemaining = 0;
                previewDelayActive = false;
                var delayedSong = deferredPreviewSong;
                var delayedDetailId = deferredPreviewDetailId;
                deferredPreviewSong = null;
                deferredPreviewDetailId = -1;
                if (delayedSong != null) updateAudio(delayedSong, delayedDetailId);
            }
        }
        FlxG.mouse.getWorldPosition(camAfter, phiPointer);
        if (FlxG.sound.music != null) Conductor.songPosition = FlxG.sound.music.time;
        updateHybridPlaybackProgress();
        childUpdateElapsed += elapsed;
        var now = FlxG.game.ticks;
        if (lastChildUpdateTick < 0 || now - lastChildUpdateTick >= 8 || FlxG.mouse.justPressed || FlxG.mouse.justReleased || FlxG.mouse.wheel != 0) {
            var dt = childUpdateElapsed; childUpdateElapsed = 0; lastChildUpdateTick = now; super.update(dt);
        }
        phiView.noteValue.text = groupedNumber(Math.round(noteData.value));
        phiView.holdValue.text = groupedNumber(Math.round(holdNoteData.value));
        phiView.speedValue.text = Std.string(Math.round(speedData.value * 100) / 100) + '×';
        phiView.keyValue.text = Math.round(keyCountData.value) + ' KEY';
        #if sys
        if (debugMode) {
            if (debugSession == null) debugSession = new states.freeplayState.objects.PhiDebugSession(this);
            debugSession.update();
            return;
        }
        #end
        if (stopAll || subState != null) return;
        if (searchButton.hasFocus) {
            if (FlxG.keys.justPressed.ESCAPE) { searchButton.unfocusSearch(); searchButton.visible = searchButton.active = false; suppressSearchVolumeShortcuts(false); }
            return;
        }
        if (searchJustUnfocused) {
            searchButton.visible = searchButton.active = false;
            searchJustUnfocused = false;
            if (controls.BACK || controls.ACCEPT || FlxG.mouse.justReleased) return;
        }
        if (controls.BACK) { returnPhiMenu(); return; }
        if (FlxG.keys.justPressed.T || FlxG.keys.justPressed.SLASH) { focusPhiSearch(); return; }
        updateHeldSongBrowse(elapsed);
        if (controls.UI_LEFT_P) stepPhiDifficulty(-1);
        if (controls.UI_RIGHT_P) stepPhiDifficulty(1);
        if (FlxG.keys.justPressed.HOME && phiSongOrder.length > 0) selectPhiSong(phiSongOrder[0]);
        if (FlxG.keys.justPressed.END && phiSongOrder.length > 0) selectPhiSong(phiSongOrder[phiSongOrder.length - 1]);
        if (controls.ACCEPT) { startGame(); return; }
        if (FlxG.mouse.wheel != 0) {
            if (phiMouseX < 885 && phiMouseY > 210 && phiMouseY < 958) stepPhiSong(FlxG.mouse.wheel > 0 ? -1 : 1);
            else if (phiMouseX > 785 && phiMouseX < 1206 && phiMouseY > 804 && phiMouseY < 908) {
				replayPosiData = FlxMath.bound(replayPosiData - FlxG.mouse.wheel * 48, 0, Math.max(0, replayDataList.length * 48 - (956 - replayStartY))); replayMoveEvent();
            }
        }
        if (FlxG.mouse.justReleased) phiView.click(phiMouseX, phiMouseY);
        for (r in replayGroup) if (r.visible) r.updateHover(phiMouseX, phiMouseY);
        searchJustUnfocused = false;
    }
    static function groupedNumber(value:Int):String {
        var str = Std.string(value); var out = '';
        for (i in 0...str.length) { if (i > 0 && (str.length - i) % 3 == 0) out += ','; out += str.charAt(i); } return out;
    }
    function updateHeldSongBrowse(elapsed:Float):Void {
        var upHeld = FlxG.keys.pressed.UP || FlxG.keys.pressed.W;
        var downHeld = FlxG.keys.pressed.DOWN || FlxG.keys.pressed.S;
        var direction = upHeld == downHeld ? 0 : (upHeld ? -1 : 1);
        var justUp = controls.UI_UP_P || FlxG.keys.justPressed.UP || FlxG.keys.justPressed.W;
        var justDown = controls.UI_DOWN_P || FlxG.keys.justPressed.DOWN || FlxG.keys.justPressed.S;
        if (justUp && !justDown) direction = -1;
        else if (justDown && !justUp) direction = 1;
        if (direction == 0) { heldBrowseDirection = 0; heldBrowseElapsed = heldBrowseRepeat = 0; return; }
        if (direction != heldBrowseDirection || justUp || justDown) {
            heldBrowseDirection = direction; heldBrowseElapsed = 0; heldBrowseRepeat = 0;
            stepPhiSong(direction); return;
        }
        heldBrowseElapsed += elapsed;
        if (heldBrowseElapsed < 0.30) return;
        heldBrowseRepeat += elapsed;
        var interval = Math.max(0.045, 0.14 - (heldBrowseElapsed - 0.30) * 0.08);
        while (heldBrowseRepeat >= interval) { heldBrowseRepeat -= interval; stepPhiSong(direction); }
    }
    public function buildHybridDifficultyButtons():Void { if (phiView != null) phiView.refreshDifficulties(); }
    public function setHybridDifficulty(index:Int):Void {
        if (index < 0 || index >= Difficulty.list.length || index == curDifficulty
            || availablePhiDifficulties(curSelected).indexOf(index) < 0) return;
        curDifficulty = index; phiView.refreshSong(); initSongsData(); FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
    }
    function updateHybridPlaybackProgress():Void {
        var music = FlxG.sound.music;
        if (previewVoiceSyncCooldown > 0) previewVoiceSyncCooldown = Math.max(0, previewVoiceSyncCooldown - FlxG.elapsed);
        if (music != null && music.playing && previewVoiceSyncCooldown <= 0) {
            var resynced = false;
            for (voice in previewVoices)
                if (voice.playing && Math.abs(voice.time - music.time) > 70) { voice.time = music.time; resynced = true; }
            if (resynced) previewVoiceSyncCooldown = 0.25;
        }
        phiView.setProgress(music == null ? 0 : music.time, music == null ? 0 : music.length);
    }
    function syncPreviewVoicesToMusic():Void {
        var music = FlxG.sound.music;
        if (music == null) return;
        for (voice in previewVoices) if (voice.playing && Math.abs(voice.time - music.time) > 8) voice.time = music.time;
        previewVoiceSyncCooldown = 0.25;
    }
    public function seekPreview(ratio:Float):Void {
        var music = FlxG.sound.music;
        if (music == null || music.length <= 0) return;
        var target = FlxMath.bound(ratio, 0, 1) * music.length;
        music.time = target;
        for (voice in previewVoices) voice.time = target;
        Conductor.songPosition = target;
    }
    public function adjustPreviewPitch(delta:Int):Void {
        previewPitchSemitones = Std.int(FlxMath.bound(previewPitchSemitones + delta, -12, 12));
        applyPreviewPlaybackRate();
    }
    public function cyclePreviewSpeed():Void {
        var speeds:Array<Float> = [0.75, 1.0, 1.25, 1.5, 2.0];
        var index = speeds.indexOf(previewSpeed);
        previewSpeed = speeds[(index + 1) % speeds.length];
        applyPreviewPlaybackRate();
    }
    function applyPreviewPlaybackRate():Void {
        var rate = previewPlaybackRate;
        #if FLX_PITCH
        if (FlxG.sound.music != null) FlxG.sound.music.pitch = rate;
        for (voice in previewVoices) voice.pitch = rate;
        #end
    }
    function stepPhiDifficulty(delta:Int):Void {
        var available = availablePhiDifficulties(curSelected);
        if (available.length == 0) return;
        var position = FlxMath.wrap(available.indexOf(curDifficulty) + delta, 0, available.length - 1);
        setHybridDifficulty(available[position]);
    }
    public static function formatPreviewTime(milliseconds:Float):String {
        var seconds = Std.int(Math.max(0, milliseconds) / 1000);
        return StringTools.lpad(Std.string(Std.int(seconds / 60)), '0', 2) + ':' + StringTools.lpad(Std.string(seconds % 60), '0', 2);
    }
    public function selectPhiSong(index:Int, sound:Bool = true):Void {
        if (index < 0 || index >= songGroup.length) return;
        if (index != curSelected || !previewDelayStarted) {
            ++audioSwitchId;
            pendingAudioPath = '';
            deferredPreviewSong = null;
            deferredPreviewDetailId = -1;
            previewDelayStarted = true;
            previewDelayActive = true;
            previewDelayRemaining = 1.0;
            // Stop the old preview immediately so rapid browsing does not keep
            // decoded PCM or OpenAL buffers alive while the next song is chosen.
            releasePreviewAudio();
        }
        curSelected = index; changeSelection(0, sound); Difficulty.loadFromWeek();
        var available = availablePhiDifficulties(index);
        if (available.indexOf(curDifficulty) < 0) curDifficulty = available.length > 0 ? available[available.length - 1] : -1;
        SongRect.openRect = songGroup[index]; SongRect.openRect.diffAdded = true;
        noteData.chanegData(0, 0); holdNoteData.chanegData(0, 0); speedData.chanegData(0, 0); keyCountData.chanegData(0, 0);
        detailBpmText.text = '—'; phiView.refreshSong(true); initSongsData();
        if (curDifficulty < 0) { PlayState.SONG = null; phiView.setRating(0); loadReplaysForCurrentSong(); }
    }
    public function stepPhiSong(delta:Int):Void {
        if (phiSongOrder.length == 0) return;
        var position = Std.int(FlxMath.bound(phiSongOrder.indexOf(curSelected) + delta, 0, phiSongOrder.length - 1));
        var id = phiSongOrder[position];
        if (id != curSelected) selectPhiSong(id);
    }
    public function phiRatingText(id:Int, diff:Int):String {
        if (id < 0 || id >= songsData.length) return '—';
        var value = phiRatings.get(phiKey(id) + '|' + diff); return value == null ? '—' : Std.string(value);
    }
    public function selectPhiScrollRatio(ratio:Float):Void {
        if (phiSongOrder.length == 0) return;
        var id = phiSongOrder[Math.round(ratio * (phiSongOrder.length - 1))];
        if (id != curSelected) selectPhiSong(id);
    }
    public function phiDifficultyNames(id:Int):Array<String> {
        var result:Array<String> = [];
        if (id < 0 || id >= songsData.length) return result;
        var data = songsData[id];
        if (data.week >= 0 && data.week < WeekData.weeksList.length) {
            var week = WeekData.weeksLoaded.get(WeekData.weeksList[data.week]);
            if (week != null && week.difficulties != null && StringTools.trim(week.difficulties) != '')
                for (name in week.difficulties.split(',')) if (StringTools.trim(name) != '') result.push(StringTools.trim(name));
        }
        if (result.length == 0) result = Difficulty.defaultList.copy();
        return result;
    }
    public function phiIconCharacter():String return songsData[curSelected].songCharacter;
    public function availablePhiDifficulties(id:Int):Array<Int> {
        var cached = phiAvailableDifficulties.get(id);
        if (cached != null) return cached;
        var result:Array<Int> = [];
        if (id < 0 || id >= songsData.length) return result;
        var originalFolder = Mods.currentModDirectory;
        Mods.currentModDirectory = songsData[id].folder;
        var song = Paths.formatToSongPath(songsData[id].songName);
        var names = phiDifficultyNames(id);
        for (i in 0...names.length) {
            var suffix = names[i].toLowerCase() == Difficulty.getDefault().toLowerCase() ? '' : '-' + Paths.formatToSongPath(names[i]);
            var path = Paths.json(song + '/' + song + suffix);
            if (!FileSystem.exists(path) && openfl.utils.Assets.exists(path)) path = openfl.utils.Assets.getPath(path);
            if (path != null && FileSystem.exists(path)) {
                result.push(i);
                phiChartPaths.set(id + '|' + i, path);
            }
        }
        Mods.currentModDirectory = originalFolder;
        phiAvailableDifficulties.set(id, result);
        return result;
    }
    public function difficultyColor(index:Int):FlxColor {
        var names = phiDifficultyNames(curSelected);
        var originalName = index >= 0 && index < names.length ? names[index] : '';
        var colorSong = curSelected >= 0 && curSelected < songsData.length ? songsData[curSelected] : null;
        var cacheKey = (colorSong == null ? '' : colorSong.folder + '|' + colorSong.week) + '|' + Paths.formatToSongPath(originalName);
        var customColor = difficultyColorCache.get(cacheKey);
        if (customColor != null) return customColor;
        var weekColor = configuredWeekDifficultyColor(colorSong, originalName);
        if (weekColor != null) { difficultyColorCache.set(cacheKey, weekColor); return weekColor; }
        var name = StringTools.trim(originalName).toLowerCase();
        var defaultColor = DEFAULT_DIFFICULTY_COLORS.get(name);
        if (defaultColor != null) return defaultColor;

        // Unmapped/custom chart names use the same rating-driven color ramp,
        // so a mod's "hell" chart is colored by its actual chart rate rather
        // than whichever slot it happened to occupy in the week file.
        var rating = phiRatings.get(phiKey(curSelected) + '|' + index);
        if (rating != null) return StarRect.getRatingColor(rating);
        var songColor = colorSong != null ? colorSong.color : [146, 113, 253];
        return FlxColor.fromRGB(songColor[0], songColor[1], songColor[2]);
    }

    function configuredWeekDifficultyColor(song:SongMetadata, difficultyName:String):Null<FlxColor> {
        if (song == null || song.week < 0 || song.week >= WeekData.weeksList.length) return null;
        var week = WeekData.weeksLoaded.get(WeekData.weeksList[song.week]);
        if (week == null || week.difficultyColors == null || difficultyName == null) return null;
        var requested = StringTools.trim(difficultyName).toLowerCase();
        var configured:Dynamic = null;
        for (key in Reflect.fields(week.difficultyColors))
            if (StringTools.trim(key).toLowerCase() == requested) { configured = Reflect.field(week.difficultyColors, key); break; }
        if (configured == null) return null;
        if (Std.isOfType(configured, String)) {
            var hex:String = StringTools.trim(cast configured);
            if (StringTools.startsWith(hex, '#')) hex = hex.substr(1);
            else if (StringTools.startsWith(hex.toLowerCase(), '0x')) hex = hex.substr(2);
            var parsed = Std.parseInt('0x' + hex);
            if (parsed != null) return hex.length <= 6 ? FlxColor.fromRGB((parsed >> 16) & 255, (parsed >> 8) & 255, parsed & 255) : FlxColor.fromInt(parsed);
        }
        if (Std.isOfType(configured, Array)) {
            var channels:Array<Dynamic> = cast configured;
            if (channels.length >= 3) return FlxColor.fromRGB(Std.int(channels[0]), Std.int(channels[1]), Std.int(channels[2]));
        }
        return null;
    }

    function phiKey(id:Int):String return songsData[id].folder + '/' + Paths.formatToSongPath(songsData[id].songName);
    public function isPhiFavorite(id:Int):Bool return id >= 0 && id < songsData.length && phiFavorites.indexOf(phiKey(id)) >= 0;
    public function togglePhiFavorite():Void {
        var key = phiKey(curSelected); if (phiFavorites.indexOf(key) >= 0) phiFavorites.remove(key); else phiFavorites.push(key);
        FlxG.save.data.dceFreeplayFavorites = phiFavorites.copy(); FlxG.save.flush(); rebuildPhiOrder();
        if (phiFavoritesOnly && phiSongOrder.length > 0 && phiSongOrder.indexOf(curSelected) < 0) selectPhiSong(phiSongOrder[0]);
    }
    function rebuildPhiOrder():Void {
        phiSongOrder = [];
        for (i in 0...songGroup.length) {
            var song = songGroup[i]; var text = normalizePhiSearch(song.songNameSt + ' ' + song.songMusican + ' ' + song._songCharter.join(' '));
            song.searchMatch = text.indexOf(phiSearch) >= 0 && (!phiFavoritesOnly || isPhiFavorite(i));
            if (song.searchMatch) phiSongOrder.push(i);
        }
        if (phiSort == 1) phiSongOrder.sort((a, b) -> Reflect.compare(songGroup[a].songNameSt.toLowerCase(), songGroup[b].songNameSt.toLowerCase()));
        if (phiSort == 2 && curDifficulty >= 0) phiSongOrder.sort((a, b) -> Highscore.getScore(Paths.formatToSongPath(songGroup[b].songNameSt), curDifficulty) - Highscore.getScore(Paths.formatToSongPath(songGroup[a].songNameSt), curDifficulty));
        if (phiView != null) phiView.refreshOrder();
    }
    public function cyclePhiSort():Void {
        phiSort = (phiSort + 1) % 3;
        phiSortLabel = [PhigrosFreeplayView.textFor('sortOrder', '曲目顺序', 'Song order'), PhigrosFreeplayView.textFor('sortName', '曲名', 'Song name'), PhigrosFreeplayView.textFor('sortScore', '最高分', 'Best score')][phiSort];
        rebuildPhiOrder();
    }
    public function focusPhiSearch():Void { searchButton.visible = searchButton.active = true; searchButton.focusSearch(); suppressSearchVolumeShortcuts(true); }

    function suppressSearchVolumeShortcuts(suppress:Bool):Void
    {
        if (FlxG.sound == null) return;
        if (suppress && !searchVolumeShortcutsSuppressed)
        {
            savedVolumeUpKeys = FlxG.sound.volumeUpKeys.copy();
            savedVolumeDownKeys = FlxG.sound.volumeDownKeys.copy();
            FlxG.sound.volumeUpKeys = [];
            FlxG.sound.volumeDownKeys = [];
            searchVolumeShortcutsSuppressed = true;
        }
        else if (!suppress && searchVolumeShortcutsSuppressed)
        {
            FlxG.sound.volumeUpKeys = savedVolumeUpKeys == null ? [] : savedVolumeUpKeys;
            FlxG.sound.volumeDownKeys = savedVolumeDownKeys == null ? [] : savedVolumeDownKeys;
            savedVolumeUpKeys = null;
            savedVolumeDownKeys = null;
            searchVolumeShortcutsSuppressed = false;
        }
    }
    public function runPhiTool(name:String):Void {
        switch (name) {
            case 'search': focusPhiSearch();
            case 'favorites': phiFavoritesOnly = !phiFavoritesOnly; rebuildPhiOrder(); if (phiSongOrder.length > 0 && phiSongOrder.indexOf(curSelected) < 0) selectPhiSong(phiSongOrder[0]);
            case 'random': if (phiSongOrder.length > 0) selectPhiSong(phiSongOrder[FlxG.random.int(0, phiSongOrder.length - 1)]);
            case 'audio':
                phiAudioVisible = !phiAudioVisible;
                var music = FlxG.sound.music;
                if (music != null) {
                    if (music.fadeTween != null) music.fadeTween.cancel();
                    if (phiAudioVisible) { music.volume = 1; music.resume(); }
                    else music.pause();
                    for (voice in previewVoices) { if (phiAudioVisible) voice.resume(); else voice.pause(); }
                    if (phiAudioVisible) syncPreviewVoicesToMusic();
                    trace('FREEPLAY PREVIEW ' + (phiAudioVisible ? 'resumed' : 'paused') + ' at ' + music.time);
                }
            default: var action = outputEvent(name); if (action != null) action();
        }
    }
    public function sortPhiRecords(index:Int):Void { var modes:Array<ReplaySortMode> = [DATE_DESC, SCORE_DESC, ACC_DESC, COMBO_DESC]; toggleReplaySort(modes[index]); }
    public function returnPhiMenu():Void {
        if (stopAll) return;
        stopAll = true;
        Mods.loadTopMod();
        destroyFreeplayVocals();
        FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);
        MusicBeatState.switchState(new MainMenuState());
    }
    public function showPhiSongInfo():Void {
        persistentUpdate = false;
        openSubState(new states.freeplayState.objects.PhiSongInfoSubState(songGroup[curSelected].songNameSt, songGroup[curSelected].songMusican, detailBpmText.text, formatPreviewTime(FlxG.sound.music == null ? 0 : FlxG.sound.music.length), curDifficulty >= 0 ? Difficulty.list[curDifficulty] : '—'));
    }

    public function warmPhiRatings():Void {
        // Restore small numeric results only. The list does not display ratings
        // for unselected songs, so parsing the entire mod library here wastes
        // CPU and can temporarily fill the managed heap with hundreds of charts.
        // initSongsData calculates the selected song's available difficulties.
        var originalFolder = Mods.currentModDirectory;
        var settings = Std.string(ClientPrefs.data.playOpponent) + '|' + Std.string(ClientPrefs.data.flipChart);
        for (offset in 0...songsData.length) {
            var id = (curSelected + offset) % songsData.length;
            var data = songsData[id];
            Mods.currentModDirectory = data.folder;
            var songName = Paths.formatToSongPath(data.songName);
            for (diff in availablePhiDifficulties(id)) {
                var path = phiChartPaths.get(id + '|' + diff);
                var key = phiKey(id) + '|' + diff;
                if (!FileSystem.exists(path)) continue;
                var stat = FileSystem.stat(path);
                var stamp = path + '|' + stat.size + '|' + stat.mtime.getTime() + '|' + settings;
                var cached = sessionRatings.get(stamp);
                if (cached != null) phiRatings.set(key, cached);
            }
        }
        Mods.currentModDirectory = originalFolder;
        phiView.refreshRatingValues();
    }

    function phiRatingStamp(path:String):String {
        var stat = FileSystem.stat(path);
        return path + '|' + stat.size + '|' + stat.mtime.getTime() + '|'
            + ClientPrefs.data.playOpponent + '|' + ClientPrefs.data.flipChart;
    }

	public function initSongsData():Void {
		var requestId:Int = ++detailRequestId;
		if (detailLoadTimer != null)
		{
			detailLoadTimer.cancel();
			detailLoadTimer = null;
		}
		if (stateDestroyed || curDifficulty < 0 || curSelected < 0
			|| curSelected >= songsData.length || curSelected >= songGroup.length)
			return;

		var selected:Int = curSelected;
		var difficulty:Int = curDifficulty;
		var songLowercase:String = Paths.formatToSongPath(songsData[selected].songName);
		var poop:String = Highscore.formatSong(songLowercase, difficulty);
		var formattedSong:String = Paths.formatToSongPath(poop);
        var chartPath:String = phiChartPaths.get(selected + '|' + difficulty);
        if (chartPath == null) return;
		var allDifficultyNames:Array<String> = Difficulty.list.copy();
		var allChartPaths:Array<String> = [];
		var allChartFormats:Array<String> = [];
		var needsRating:Array<Bool> = [];
		for (i in 0...allDifficultyNames.length)
		{
			var chartFormat = Highscore.formatSong(songLowercase, i);
			allChartFormats.push(chartFormat);
            allChartPaths.push(phiChartPaths.get(selected + '|' + i));
			needsRating.push(!phiRatings.exists(phiKey(selected) + '|' + i));
		}

		// The row and difficulty callbacks can request the same chart in one
		// frame. Coalesce them and keep blocking I/O away from the render thread.
		// Song's global parse state is touched only by the newest main callback.
		detailLoadTimer = new FlxTimer().start(0.025, function(_):Void
		{
			detailLoadTimer = null;
			if (!isDetailRequestCurrent(requestId, selected, difficulty)) return;
            states.freeplayState.objects.PhiWorker.run(function():Void
            {
                if (!isDetailRequestCurrent(requestId, selected, difficulty)) return;
				var rawData:String = null;
				var allRawData:Array<String> = [];
				var loadError:Dynamic = null;
				var extraRatings:Map<Int, Float> = new Map();
				var cachedResults:Map<String, Float> = new Map();
				var parsedChart:{song:SwagSong, detectedFormat:String} = null;
				var selectedRating:Float = 0;
				try
				{
                    if (FileSystem.exists(chartPath))
                        rawData = File.getContent(chartPath);
					if (rawData == null) throw 'Missing chart: $chartPath';
					parsedChart = Song.parseChart(rawData);
					if (!isDetailRequestCurrent(requestId, selected, difficulty)) return;
					selectedRating = DiffRating.calcForSong(parsedChart.song);
					cachedResults.set(phiRatingStamp(chartPath), Math.floor(selectedRating * 100) / 100);
					for (i in 0...allChartPaths.length)
					{
						if (!isDetailRequestCurrent(requestId, selected, difficulty)) return;
						var path = allChartPaths[i];
						var extra:String = null;
						try
						{
                            if (i != difficulty && needsRating[i] && path != null && FileSystem.exists(path)) extra = File.getContent(path);
						}
						catch (_:Dynamic) {}
						allRawData.push(extra);
					}
					// Calculate non-selected chart ratings on this worker. Parsing every
					// difficulty in the main-thread callback made fast song browsing hitch.
					for (i in 0...allRawData.length)
					{
						if (!isDetailRequestCurrent(requestId, selected, difficulty)) return;
						if (i == difficulty || allRawData[i] == null) continue;
						try
						{
							var raw:Dynamic = Json.parse(allRawData[i]);
							if (raw.song != null && Type.typeof(raw.song) == TObject) raw = raw.song;
							if (raw.notes == null) continue;
						if (raw.mania == null) raw.mania = 3;
						var sections:Array<Dynamic> = cast raw.notes;
						raw.notes = [for (section in sections) if (section != null && section.sectionNotes != null) section];
							var rating = Math.floor(DiffRating.calcForSong(cast raw) * 100) / 100;
							extraRatings.set(i, rating);
							cachedResults.set(phiRatingStamp(allChartPaths[i]), rating);
						}
						catch (extraError:Dynamic) trace('FREEPLAY CHART RATE $i: $extraError');
					}
				}
				catch (e:Dynamic)
				{
					loadError = e;
				}

				postPhiResult(function():Void
				{
					if (!isDetailRequestCurrent(requestId, selected, difficulty)) return;
					try
					{
						if (loadError != null) throw loadError;
						if (rawData == null) throw 'Missing chart: $chartPath';
						var loadedSong = parsedChart.song;
						if (loadedSong == null) throw 'Invalid chart: $chartPath';
						Song.applyFormatState(parsedChart.detectedFormat);
						for (stamp in cachedResults.keys()) sessionRatings.set(stamp, cachedResults.get(stamp));
						for (i in extraRatings.keys())
							phiRatings.set(phiKey(selected) + '|' + i, extraRatings.get(i));
						PlayState.SONG = loadedSong;
						Song.loadedSongName = songLowercase;
						Song.chartPath = chartPath;
						#if windows
						Song.chartPath = Song.chartPath.replace('/', '\\');
						#end
						Conductor.bpm = loadedSong.bpm;
						if (phiView != null) phiView.refreshRatingValues();
						updateDetail(loadedSong, selectedRating, requestId, selected, difficulty);
					}
					catch (e:Dynamic)
					{
						trace('FREEPLAY CHART: $e');
						seedError(e, requestId, selected, difficulty);
					}
				});
			});
		});
	}

	inline function isDetailRequestCurrent(requestId:Int, selected:Int, difficulty:Int):Bool
	{
		return !stateDestroyed && instance == this && requestId == detailRequestId
			&& selected == curSelected && difficulty == curDifficulty;
	}

	function updateDetail(song:SwagSong, diffCalc:Float, requestId:Int, selected:Int, difficulty:Int):Void {
		if (!isDetailRequestCurrent(requestId, selected, difficulty)
			|| phiView == null) return;
		diffCalc = Math.floor(diffCalc * 100) / 100;
		var selectedRect:SongRect = songGroup[selected];
		var charter:String = 'N/A';
		if (selectedRect._songCharter != null && difficulty >= 0
			&& difficulty < selectedRect._songCharter.length
			&& selectedRect._songCharter[difficulty] != null)
			charter = selectedRect._songCharter[difficulty];
		detailBpmText.text = Std.string(song.bpm);
        phiRatings.set(phiKey(selected) + '|' + difficulty, diffCalc);
        phiView.setRating(diffCalc);

		states.freeplayState.objects.PhiWorker.run(function():Void {
			var noteCount:Int = 0;
			var holdNoteCount:Int = 0;
			if (song != null && song.notes != null) {
				for (sec in song.notes) {
					if (sec == null || sec.sectionNotes == null) continue;
					for (n in sec.sectionNotes) {
						if (n == null || !Std.isOfType(n, Array)) continue;
						var arr:Array<Dynamic> = cast n;
						if (arr == null || arr.length < 2 || arr[1] == null) continue;
						var rawLane:Int = Std.int(arr[1]);
						if (rawLane < 0) continue;
						var gottaHitNote:Bool = sec.mustHitSection;
						if (rawLane > song.mania) gottaHitNote = !sec.mustHitSection;
						var isPlayerSide:Bool = ((gottaHitNote && !ClientPrefs.data.playOpponent)
							|| (!gottaHitNote && ClientPrefs.data.playOpponent));
						var isHold:Bool = (arr.length > 2 && arr[2] != null && arr[2] > 0);
						if (isPlayerSide) {
							noteCount++;
							if (isHold) holdNoteCount++;
						}
					}
				}
			}
			var speedValue:Float = (song != null) ? song.speed : 0;
			var keyCountValue:Float = (song != null) ? (song.mania + 1) : 0;

			postPhiResult(function():Void
			{
				if (!isDetailRequestCurrent(requestId, selected, difficulty)
					|| noteData == null || holdNoteData == null || speedData == null
					|| keyCountData == null) return;
				noteData.chanegData(noteCount);
				holdNoteData.chanegData(holdNoteCount);
				speedData.chanegData(speedValue);
				keyCountData.chanegData(keyCountValue);
			});
		});

		updateAudio(song, requestId);

		if (difficulty >= 0 && difficulty < Difficulty.list.length)
			loadReplaysForCurrentSong();
	}

	var allowPlayMusic:Bool = true;
	var alreadyLoadSongPath:String = '';
	var audioSwitchId:Int = 0;

	var audioFadeOutTime:Float = 0.12;
	var audioFadeInTime:Float = 0.18;

    public function updateAudio(?song:SwagSong, ?sourceDetailId:Int = -1):Void {
        if (stateDestroyed || song == null || (sourceDetailId >= 0 && sourceDetailId != detailRequestId)) return;
        if (previewDelayActive) {
            deferredPreviewSong = song;
            deferredPreviewDetailId = sourceDetailId;
            return;
        }
        var instPath = Paths.songPath(song.song + '/Inst');
        if (alreadyLoadSongPath == instPath || pendingAudioPath == instPath) return;
        var requestId = ++audioSwitchId;
        var selected = curSelected;
        pendingAudioPath = instPath;
        // Fade the outgoing preview as soon as selection changes, so it cannot
        // keep playing behind the new cover while its audio is decoded.
        if (FlxG.sound.music != null && FlxG.sound.music.playing) FlxG.sound.music.fadeOut(audioFadeOutTime, 0);
        for (voice in previewVoices) if (voice.playing) voice.fadeOut(audioFadeOutTime, 0);
        if (phiView != null) phiView.setProgress(0, 0);
        var voicePaths:Array<String> = [];
        var voiceRoles:Array<String> = [];
        if (song.needsVoices) {
            var combined = Paths.songPath(song.song + '/Voices');
            if (FileSystem.exists(combined)) { voicePaths.push(combined); voiceRoles.push('voices'); }
            else {
                var player = Paths.songPath(song.song + '/Voices' + getVocalFromCharacter(song.player1, 'Player'));
                var opponent = Paths.songPath(song.song + '/Voices' + getVocalFromCharacter(song.player2, 'Opponent'));
                if (FileSystem.exists(player)) { voicePaths.push(player); voiceRoles.push('player'); }
                if (FileSystem.exists(opponent) && opponent != player) { voicePaths.push(opponent); voiceRoles.push('opponent'); }
            }
        }
        trace('FREEPLAY PREVIEW decoding ' + instPath);
        states.freeplayState.objects.PhiWorker.run(function():Void {
            var inst:AudioBuffer = null;
            if (!isAudioRequestCurrent(requestId, sourceDetailId) || selected != curSelected) return;
            var voices:Array<AudioBuffer> = [];
            var decoded:Array<AudioBuffer> = [];
            var discard = function():Void { PhiPreviewBuffers.releaseAll(decoded); };
            var decodedRoles:Array<String> = [];
            var error:Dynamic = null;
            try {
                inst = loadPreviewAudioBuffer(instPath);
                if (inst == null) throw 'Cannot decode ' + instPath;
                decoded.push(inst);
                if (!isAudioRequestCurrent(requestId, sourceDetailId) || selected != curSelected) { discard(); return; }
                for (i in 0...voicePaths.length) {
                    if (!isAudioRequestCurrent(requestId, sourceDetailId) || selected != curSelected) { discard(); return; }
                    try {
                        var buffer = loadPreviewAudioBuffer(voicePaths[i]);
                        if (buffer != null) { decoded.push(buffer); voices.push(buffer); decodedRoles.push(voiceRoles[i]); }
                        else trace('FREEPLAY PREVIEW skipped undecodable Voice stem: ' + voicePaths[i]);
                    } catch (voiceError:Dynamic) {
                        // A bad optional vocal stem should not prevent Inst and
                        // any other valid stems from being previewed.
                        trace('FREEPLAY PREVIEW skipped Voice stem ' + voicePaths[i] + ': ' + voiceError);
                    }
                }
                // OpenAL's global context is shared across threads. Publish
                // fully uploaded immutable buffers; the UI only creates small
                // source handles rather than copying whole songs during a frame.
                for (buffer in decoded) {
                    if (!isAudioRequestCurrent(requestId, sourceDetailId) || selected != curSelected) { discard(); return; }
                    PhiPreviewBuffers.preparePlayback(buffer);
                }
            } catch (e:Dynamic) { error = e; }
            postPhiResult(function():Void {
                if (!isAudioRequestCurrent(requestId, sourceDetailId) || selected != curSelected) { discard(); return; }
                pendingAudioPath = '';
                if (error != null) { discard(); trace('FREEPLAY PREVIEW decode error: ' + error); return; }
                // Use the same OpenAL path as normal engine sounds. Preview switching
                // no longer synchronously tears down VLC audio threads on the UI thread.
                trace('FREEPLAY PREVIEW installing OpenAL tracks');
                releasePreviewAudio();
                previewAudioBuffers = decoded;
                previewInstSound = Sound.fromAudioBuffer(inst);
                FlxG.sound.playMusic(previewInstSound, phiAudioVisible ? 0 : 1, true);
                applyPreviewPlaybackRate();
                if (phiAudioVisible) FlxG.sound.music.fadeIn(audioFadeInTime, 0, 1);
                else FlxG.sound.music.pause();
                var playerVoice:FlxSound = null;
                var opponentVoice:FlxSound = null;
                var genericVoice:FlxSound = null;
                for (i in 0...voices.length) {
                    var buffer = voices[i];
                    // Stem files are finite tracks, not loops. Looping them makes
                    // mod voices drift or continue after Inst has ended.
                    var voice = new FlxSound().loadEmbedded(Sound.fromAudioBuffer(buffer), false, false);
                    voice.volume = 0;
                    FlxG.sound.list.add(voice); previewVoices.push(voice);
                    // Start directly at the master position. Setting `time`
                    // after play tears down and recreates the native channel,
                    // which adds a small but audible delay for vocal-only mods.
                    var startPosition = FlxG.sound.music == null ? 0 : FlxG.sound.music.time;
                    voice.play(false, startPosition);
                    switch (decodedRoles[i]) {
                        case 'player': if (playerVoice == null) playerVoice = voice;
                        case 'opponent': if (opponentVoice == null) opponentVoice = voice;
                        default: if (genericVoice == null) genericVoice = voice;
                    }
                    if (phiAudioVisible) voice.fadeIn(audioFadeInTime, 0, 0.8);
                    else voice.pause();
                }
                previewVoiceSyncCooldown = 0.25;
                applyPreviewPlaybackRate();
                alreadyLoadSongPath = instPath;
                phiView.setProgress(0, FlxG.sound.music == null ? 0 : FlxG.sound.music.length);
                previewSpectrum.changeAnalyzer(FlxG.sound.music);
                previewSpectrum.setBarColor(FlxColor.WHITE);
                if (genericVoice != null) {
                    previewVoiceSpectrum.x = 480;
                    previewVoiceSpectrum.visible = true;
                    previewVoiceSpectrum.changeAnalyzer(genericVoice);
                    previewVoiceSpectrum.setBarColor(FlxColor.BLACK);
                    previewOpponentSpectrum.changeAnalyzer(null);
                    previewOpponentSpectrum.visible = false;
                } else {
                    previewVoiceSpectrum.x = 0;
                    previewVoiceSpectrum.visible = playerVoice != null;
                    previewVoiceSpectrum.changeAnalyzer(playerVoice);
                    previewVoiceSpectrum.setBarColor(previewCharacterColor(song.player1, 0xFF31C878));
                    previewOpponentSpectrum.changeAnalyzer(opponentVoice);
                    previewOpponentSpectrum.setBarColor(previewCharacterColor(song.player2, 0xFFEF5364));
                    previewOpponentSpectrum.visible = opponentVoice != null;
                }
                trace('FREEPLAY PREVIEW ready: Inst + ' + previewVoices.length + ' Voices');
                trace('FREEPLAY PREVIEW owned buffers=' + previewAudioBuffers.length
                    + ', streamed OGG=' + PhiPreviewBuffers.streamedCount(previewAudioBuffers)
                    + ', decoded PCM MB=' + Math.round(PhiPreviewBuffers.decodedBytes(previewAudioBuffers) / 1048576));
            }, discard);
        }, false, true);
    }

    /** Stream OGG through Lime's bounded OpenAL queue instead of decoding the
     * complete track to PCM in memory. Fall back for other file formats. */
    function loadPreviewAudioBuffer(path:String):AudioBuffer {
        #if lime_vorbis
        if (path != null && StringTools.endsWith(path.toLowerCase(), '.ogg')) {
            var vorbis = VorbisFile.fromFile(path);
            if (vorbis != null) {
                var streamed = AudioBuffer.fromVorbisFile(vorbis);
                if (streamed != null) return streamed;
                vorbis.clear();
            }
        }
        #end
        return AudioBuffer.fromFile(path);
    }
    function destroyPreviewVoices():Void {
        if (previewVoiceSpectrum != null) previewVoiceSpectrum.changeAnalyzer(null);
        if (previewOpponentSpectrum != null) previewOpponentSpectrum.changeAnalyzer(null);
        for (voice in previewVoices) { FlxG.sound.list.remove(voice, true); voice.destroy(); }
        previewVoices = [];
    }

    function releasePreviewAudio():Void {
        if (previewSpectrum != null) previewSpectrum.changeAnalyzer(null);
        destroyPreviewVoices();
        // Other states may already have replaced the global music. Only stop
        // our own Sound; never destroy the newly installed menu/game track.
        @:privateAccess if (FlxG.sound.music != null && FlxG.sound.music._sound == previewInstSound && previewInstSound != null) {
            FlxG.sound.music.destroy();
            FlxG.sound.music = null;
        }
        if (previewInstSound != null) { previewInstSound.close(); previewInstSound = null; }
        var releasedCount = previewAudioBuffers.length;
        PhiPreviewBuffers.releaseAll(previewAudioBuffers);
        if (releasedCount > 0) trace('FREEPLAY PREVIEW released buffers=' + releasedCount + ', remaining=0');
        alreadyLoadSongPath = '';
    }

	inline function isAudioRequestCurrent(requestId:Int, sourceDetailId:Int = -1):Bool
	{
		return !stateDestroyed && instance == this && requestId == audioSwitchId
			&& (sourceDetailId < 0 || sourceDetailId == detailRequestId);
	}

	function seedError(e:Dynamic, requestId:Int, selected:Int, difficulty:Int):Void {
		if (!isDetailRequestCurrent(requestId, selected, difficulty)
			|| phiView == null) return;
        detailBpmText.text = '—'; phiView.setRating(0);
        noteData.chanegData(0); holdNoteData.chanegData(0); speedData.chanegData(0); keyCountData.chanegData(0);

		++audioSwitchId;
	}

	public function startGame() {
		if (phiSongOrder.indexOf(curSelected) < 0 || curSelected < 0 || curSelected >= songsData.length) return;
		if (curDifficulty >= 0 && curDifficulty < Difficulty.list.length) {
			var songLowercase:String = Paths.formatToSongPath(songsData[curSelected].songName);
			var poop:String = Highscore.formatSong(songLowercase, curDifficulty);

			try
			{
				ensureSelectedChartLoaded(poop, songLowercase);
				PlayState.isStoryMode = false;
				PlayState.storyDifficulty = curDifficulty;

				trace('CURRENT WEEK: ' + WeekData.getWeekFileName());
			}
			catch (e:Dynamic)
			{
				trace('ERROR! $e');

				var errorStr:String = e.toString();
				if (errorStr.startsWith('[lime.utils.Assets] ERROR:'))
					errorStr = 'Missing file: ' + errorStr.substring(errorStr.indexOf(songLowercase), errorStr.length - 1); // Missing chart

				trace(errorStr);
				FlxG.sound.play(Paths.sound('cancelMenu'));
				return;
			}

			Highscore.savePlayCount(songLowercase, curDifficulty);

			LoadingState.prepareToSong();
			if (ClientPrefs.data.loadingScreen)
			{
				FlxTransitionableState.skipNextTransIn = true;
				FlxTransitionableState.skipNextTransOut = true;
			}
			LoadingState.loadAndSwitchState(new PlayState());
		    stopAll = true;
			#if (MODS_ALLOWED && DISCORD_ALLOWED)
			DiscordClient.loadModRPC();
			#end
		}
	}

	public function watchReplay(rsdPath:String)
	{
		if (curDifficulty < 0 || curDifficulty >= Difficulty.list.length)
			return;

		var songLowercase:String = Paths.formatToSongPath(songsData[curSelected].songName);
		var poop:String = Highscore.formatSong(songLowercase, curDifficulty);

		try
		{
			ensureSelectedChartLoaded(poop, songLowercase);
			PlayState.isStoryMode = false;
			PlayState.storyDifficulty = curDifficulty;
			PlayState.replayMode = true;
			Replay.preparedPath = rsdPath;
		}
		catch (e:Dynamic)
		{
			trace('ERROR loading replay: $e');
			FlxG.sound.play(Paths.sound('cancelMenu'));
			return;
		}

		Highscore.savePlayCount(songLowercase, curDifficulty);

		LoadingState.prepareToSong();
		if (ClientPrefs.data.loadingScreen)
		{
			FlxTransitionableState.skipNextTransIn = true;
			FlxTransitionableState.skipNextTransOut = true;
		}
		LoadingState.loadAndSwitchState(new PlayState());
		stopAll = true;
		#if (MODS_ALLOWED && DISCORD_ALLOWED)
		DiscordClient.loadModRPC();
		#end
	}

	function ensureSelectedChartLoaded(jsonInput:String, songFolder:String):Void
	{
		var expectedPath:String = Paths.json(
			'${Paths.formatToSongPath(songFolder)}/${Paths.formatToSongPath(jsonInput)}');
		#if windows
		expectedPath = expectedPath.replace('/', '\\');
		#end
		if (PlayState.SONG != null && Song.loadedSongName == songFolder
			&& Song.chartPath == expectedPath)
		{
			// StageData.forceNextDirectory is consumed by LoadingState. Refresh
			// it even when the chart stays cached, otherwise replaying the same
			// song falls back to shared and loses its week-specific assets.
			StageData.loadDirectory(PlayState.SONG);
			return;
		}
		PlayState.SONG = Song.loadFromJson(jsonInput, songFolder);
		StageData.loadDirectory(PlayState.SONG);
	}

	public function openReplayResults(rsdPath:String)
	{
		#if sys
		states.freeplayState.objects.PhiWorker.run(() -> {
			var record:StateRecord = ReplayRect.loadStateRecord(rsdPath);
			postPhiResult(function():Void
			{
				if (record != null)
				{
					ResultsScreen.isFromFreeplay = true;
					ResultsScreen.freeplayRecord = record;
					persistentUpdate = false;
					openSubState(new ResultsScreen(0, 0));
				}
				else
				{
					FlxG.sound.play(Paths.sound('cancelMenu'));
				}
			});
		});
		#end
	}

	public function loadReplaysForCurrentSong()
	{
		var requestId = ++replayRequestId;
		var selected = curSelected;
		var difficulty = curDifficulty;
		for (r in replayGroup)
		{
			remove(r);
			r.destroy();
		}
		replayGroup = [];
		replayDataList = [];
		replayPosiData = 0;

		if (difficulty < 0 || difficulty >= Difficulty.list.length)
		{
			replayNoDataText.visible = true; replaySortText.text = '0 ' + PhigrosFreeplayView.textFor('recordCount', '条记录', 'records');
			if (replayMove != null)
				replayMove.moveLimit = [0, 0];
			return;
		}

		var songName = songsData[selected].songName;
		var modFolder = songsData[selected].folder;
		var diffName = Difficulty.list[difficulty];
		states.freeplayState.objects.PhiWorker.runBackground(function():Void {
			var data = ReplayRect.loadReplayData(songName, diffName, modFolder);
			postPhiResult(function():Void {
				if (stateDestroyed || requestId != replayRequestId || selected != curSelected || difficulty != curDifficulty) return;
				if (data.length == 0)
				{
					replayNoDataText.visible = true;
					replaySortText.text = '0 ' + PhigrosFreeplayView.textFor('recordCount', '条记录', 'records');
					if (replayMove != null) replayMove.moveLimit = [0, 0];
					return;
				}
				replayNoDataText.visible = false;
				ReplayRect.sortReplays(data, replaySortMode);
				replayDataList = data;
				// Keep only a few visible row sprites alive; record history remains unlimited.
				var visiblePoolSize = Std.int(Math.min(4, data.length));
				for (i in 0...visiblePoolSize)
				{
					var rect:ReplayRect = new ReplayRect(replayStartX + 12, replayStartY, 700, ReplayRect.fixHeight, data[i]);
					rect.cameras = [camReplay];
					add(rect);
					replayGroup.push(rect);
				}
				var maxScroll:Float = Math.max(0, data.length * 48 - (956 - replayStartY));
				if (replayMove != null) replayMove.moveLimit = [0, maxScroll];
				replayMoveEvent();
				updateReplaySortLabel();
			});
		});
	}

	public function replayMoveEvent()
	{
		for (i in 0...replayGroup.length)
		{
			var offset = replayPosiData % 48;
			var dataIndex = Std.int(replayPosiData / 48) + i;
			var baseY:Float = replayStartY + i * 48 - offset;
			var row = replayGroup[i];
			row.moveY(baseY);
			row.x = replayStartX + 12 - (baseY - replayStartY) * states.freeplayState.objects.PhiPanel.SLOPE;
			row.visible = dataIndex >= 0 && dataIndex < replayDataList.length
				&& baseY >= replayStartY && baseY + ReplayRect.fixHeight <= 956;
			if (dataIndex >= 0 && dataIndex < replayDataList.length)
			{
				var replayData = replayDataList[dataIndex];
				row.bindData(replayData);
				bindReplayActions(row, replayData);
			}
		}
	}

	function bindReplayActions(row:ReplayRect, replayData:ReplayData):Void
	{
		row.onClick = function() watchReplay(replayData.rsdPath);
		row.onClickSettings = function() openReplayResults(replayData.rsdPath);
	}

	function toggleReplaySort(mode:ReplaySortMode)
	{
		var nextMode:ReplaySortMode = mode;
		if (replaySortMode == mode)
		{
			nextMode = switch (mode)
			{
				case DATE_DESC: DATE_ASC;
				case DATE_ASC: DATE_DESC;
				case SCORE_DESC: SCORE_ASC;
				case SCORE_ASC: SCORE_DESC;
				case ACC_DESC: ACC_ASC;
				case ACC_ASC: ACC_DESC;
				case COMBO_DESC: COMBO_ASC;
				case COMBO_ASC: COMBO_DESC;
			}
		}
		replaySortMode = nextMode;
		updateSortBtnColors();
		loadReplaysForCurrentSong();
	}

    function updateSortBtnColors():Void { phiView.refreshRecords(); }
    function updateReplaySortLabel():Void { replaySortText.text = replayDataList.length + ' ' + PhigrosFreeplayView.textFor('recordCount', '条记录', 'records'); }

    public function changeSelection(change:Int = 0, playSound:Bool = true):Void {
        if (songGroup.length == 0) return;
        curSelected = Std.int(FlxMath.bound(curSelected + change, 0, songGroup.length - 1));
        Mods.currentModDirectory = songsData[curSelected].folder; PlayState.storyWeek = songsData[curSelected].week;
        if (playSound) FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
        requestSelectedBackground(songGroup[curSelected].bgPath);
    }
    function requestSelectedBackground(path:String):Void {
        var requestId = ++backgroundRequestId;
        if (backgroundLoadTimer != null) backgroundLoadTimer.cancel();
        backgroundLoadTimer = new FlxTimer().start(0.10, function(_) {
            backgroundLoadTimer = null;
            states.freeplayState.objects.PhiWorker.run(function() {
                if (stateDestroyed || requestId != backgroundRequestId) return;
                var prepared = SongRect.createCoverImage(path, 926, 494);
                postPhiResult(function() {
                    if (stateDestroyed || instance != this || requestId != backgroundRequestId || prepared == null) return;
                    var bitmap = BitmapData.fromImage(prepared); phiView.installArtwork(bitmap); bitmap.dispose();
                });
            });
        });
    }

	override function destroy():Void
	{
		suppressSearchVolumeShortcuts(false);
		MouseEffect.trailEnabled = true;
        phiResultMutex.acquire();
		stateDestroyed = true;
        phiResultMutex.release();
        // Run only the discard branch of queued results before losing the queue.
        while (true) {
            var discardedResult = phiResults.pop(false);
            if (discardedResult == null) break;
            discardedResult();
        }
        releasePreviewAudio();
		++detailRequestId;
		++audioSwitchId;
		++backgroundRequestId;
		if (detailLoadTimer != null)
		{
			detailLoadTimer.cancel();
			detailLoadTimer = null;
		}
		if (backgroundLoadTimer != null)
		{
			backgroundLoadTimer.cancel();
			backgroundLoadTimer = null;
		}
		if (instance == this) instance = null;
		super.destroy();
		selectedBackgroundGraphic = null;
	}

    public function updateSongLayerOrder():Void {}
    public function openPhiProfile():Void
    {
        if (subState == null)
        {
            persistentUpdate = false;
            openSubState(new FreeplayProfileSubState(this));
        }
    }

    public function onPhiProfileUpdated():Void
    {
        if (phiView != null) phiView.refreshProfile();
    }

    public function startSearch(text:String):Void {
        phiSearch = normalizePhiSearch(text); isSearchActive = phiSearch != ''; rebuildPhiOrder();
        if (phiSongOrder.length > 0 && phiSongOrder.indexOf(curSelected) < 0) selectPhiSong(phiSongOrder[0]);
    }

    function previewCharacterColor(character:String, fallback:FlxColor):FlxColor {
        #if sys
        if (character != null && character.length > 0) try {
            var path = Paths.getPath('characters/' + character + '.json', TEXT);
            if (FileSystem.exists(path)) {
                var data:Dynamic = Json.parse(File.getContent(path));
                var colors:Array<Int> = cast Reflect.field(data, 'healthbar_colors');
                if (colors != null && colors.length >= 3)
                    return FlxColor.fromRGB(colors[0], colors[1], colors[2]);
            }
        } catch (e:Dynamic) trace('FREEPLAY PREVIEW character color fallback for ' + character + ': ' + e);
        #end
        return fallback;
    }
    static function normalizePhiSearch(text:String):String return ~/\s+/g.replace(text == null ? '' : text.toLowerCase(), '');
    public function updateSongVisibility(r:SongRect):Bool return false;
    override function beatHit():Void { super.beatHit(); }

	override function closeSubState()
	{
		super.closeSubState();
		persistentUpdate = true;
	}

	public static function destroyFreeplayVocals() {
        if (instance != null) instance.releasePreviewAudio();
		if (FlxG.sound.music == null) return;
        FlxG.sound.music.releaseMedia(1);
		FlxG.sound.music.releaseMedia(2);
		FlxG.sound.music.releaseMedia(3);
		FlxG.sound.music.stop();
		vocalsPlayer1 = null;
		vocalsPlayer2 = null;
	}

	function getVocalFromCharacter(char:String, fixName:String)
	{
		try
		{
			var path:String = Paths.getPath('characters/$char.json', TEXT);

			var character:Dynamic = null;
			#if MODS_ALLOWED
			if (FileSystem.exists(path))
			character = Json.parse(File.getContent(path));
			#else
			character = Json.parse(Assets.getText(path));
			#end
			if (character != null && character.vocals_file != null && character.vocals_file != "" && character.vocals_file.length > 0)
			return '-'+ character.vocals_file;
		}
		return '-'+fixName;
	}
}

class SongMetadata
{
	public var songName:String = "";
	public var week:Int = 0;
	public var songCharacter:String = "";
	public var color:Array<Int> = [0, 0, 0];
	public var folder:String = "";
	public var bg:Dynamic;
	public var searchnum:Int = 0;
	public var songMusican:String = 'N/A';
	public var songCharter:Array<String> = ['N/A', 'N/A', 'N/A'];

	public function new(song:String, week:Int, songCharacter:String, musican:String, charter:Array<String>, color:Array<Int>)
	{
		this.songName = song;
		this.week = week;
		this.songCharacter = songCharacter;
		this.color = color;
		this.folder = Mods.currentModDirectory;
		this.bg = Paths.image('menuDesat', null, false);
		this.searchnum = 0;
		this.songMusican = musican;
		this.songCharter = charter;
		if (this.folder == null)
			this.folder = '';
	}
}
