package states.storyMenuState;

import flixel.group.FlxGroup;
import flixel.graphics.FlxGraphic;
import flixel.util.FlxGradient;
import haxe.Json;
import haxe.io.Bytes;
import openfl.display.BitmapData;
#if mobile
import openfl.Lib;
import openfl.events.TouchEvent;
import openfl.geom.Point;
#end

import general.objects.MenuItem;
import general.objects.MenuCharacter;
import developer.editors.EditorInputStyle;

import substates.GameplayChangersSubstate;
import substates.ResetScoreSubState;

import games.backend.WeekData;
import games.backend.Highscore;
import games.backend.Song;

import states.mainMenuState.MainMenuState;
import states.freeplayState.FreeplayState;
import states.freeplayState.objects.PhiItalicText;
import states.freeplayState.objects.PhiPanel;

class StoryMenuState extends MusicBeatState
{
	public static var weekCompleted:Map<String, Bool> = new Map<String, Bool>();

	var scoreText:FlxText;

	private static var lastDifficultyName:String = '';

	var curDifficulty:Int = 1;

	var txtWeekTitle:FlxText;
	var bgYellow:FlxSprite;
	var bgSprite:FlxSprite;
	var weekSelectionPanel:PhiPanel;
	var trackPanel:PhiPanel;
	var backButton:PhiPanel;
	var backButtonLabel:FlxText;
	var gradientBackground:FlxSprite;
	var gradientIncoming:FlxSprite;
	var danceBackground:FlxSprite;
	var gradientTransitionTween:FlxTween;
	var weekChangeQueue:Array<Int> = [];
	var weekChangeBusy:Bool = false;
	var lastWeekSwitchTime:Float = -1;
	var weekAnimationRate:Float = 1;
	var storyPointerHeld:Bool = false;
	var storyPointerMoved:Bool = false;
	var storyPointerLastY:Float = 0;
	#if mobile
	var storyNativeTouchId:Int = -1;
	var storyNativeTouchMoved:Bool = false;
	#end
	var opponentColorCache:Map<String, FlxColor> = new Map<String, FlxColor>();
	var opponentGradientCache:Map<String, BitmapData> = new Map<String, BitmapData>();

	private static var curWeek:Int = 0;

	var grpWeekText:FlxTypedGroup<MenuItem>;
	var grpWeekCharacters:FlxTypedGroup<MenuCharacter>;
	var grpDifficultyList:FlxTypedGroup<FlxSprite>;

	var grpLocks:FlxTypedGroup<FlxSprite>;

	var difficultySelectors:FlxGroup;
	var sprDifficulty:FlxSprite;
	var leftArrow:FlxSprite;
	var rightArrow:FlxSprite;

	var loadedWeeks:Array<WeekData> = [];
	var selectingDifficulty:Bool = false;
	var weekListLeft:Float = 1500;
	var weekListOffset:Float = 0;
	var weekListOffsetTarget:Float = 0;
	var difficultyListOffset:Float = 360;
	var difficultyListOffsetTarget:Float = 360;
	var trackScoreValues:Array<Float> = [];
	var trackScoreTargets:Array<Int> = [];
	var trackScoreAnimating:Bool = false;
	var lastDisplayedWeekScore:Int = -1;
	var trackNameRows:Array<FlxText> = [];
	var trackScoreRows:Array<FlxText> = [];
	var trackGradeRows:Array<FlxText> = [];
	var weekPlaceholderLabels:Array<FlxText> = [];
	var weekHasArtwork:Array<Bool> = [];
	var trackRowY:Float = 928;
	static inline final STORY_SLOPE:Float = states.freeplayState.objects.PhiPanel.SLOPE;

	override function create()
	{
		// Story Mode uses the same fixed 1920x1080 canvas as Chart Editor.
		EditorInputStyle.enterHiRes();
		// Story Back was added after the menu language group is normally loaded.
		Language.refreshGroup('mainmenu');
		#if mobile
		// Handle touches directly from the stage. Story Mode used to poll touch
		// state in update(), which is not reliable after its camera/resolution
		// changes; editor screens already receive these stage events directly.
		Lib.current.stage.addEventListener(TouchEvent.TOUCH_BEGIN, onStoryTouchBegin);
		Lib.current.stage.addEventListener(TouchEvent.TOUCH_MOVE, onStoryTouchMove);
		Lib.current.stage.addEventListener(TouchEvent.TOUCH_END, onStoryTouchEnd);
		#end

		Song.forceEngineVersion = null;
		FlxG.camera.bgColor = FlxColor.BLACK;

		PlayState.isStoryMode = true;
		WeekData.reloadWeekFiles(true);
		if (curWeek >= WeekData.weeksList.length)
			curWeek = 0;
		persistentUpdate = persistentDraw = true;

		scoreText = new FlxText(0, 0, 480, "WEEK SCORE: 0", 24);
		scoreText.setFormat(Paths.font('vcr.ttf'), 20, FlxColor.WHITE, LEFT);
		scoreText.antialiasing = ClientPrefs.data.antialiasing;

		txtWeekTitle = new FlxText(24, 16, 1280, "", 26);
		txtWeekTitle.setFormat(Paths.font(Language.get('fontName', 'main') + '.ttf'), 26, FlxColor.WHITE, LEFT);
		txtWeekTitle.wordWrap = true;
		txtWeekTitle.autoSize = false;
		txtWeekTitle.fieldWidth = 1280;
		txtWeekTitle.fieldHeight = 100;
		txtWeekTitle.borderStyle = OUTLINE_FAST;
		txtWeekTitle.borderColor = 0x88000000;
		txtWeekTitle.borderSize = 2;
		txtWeekTitle.antialiasing = ClientPrefs.data.antialiasing;

		var ui_tex = Paths.getSparrowAtlas('campaign_menu_UI_assets');
		gradientBackground = makeOpponentGradient(WeekData.weeksLoaded.get(WeekData.weeksList[0]));
		insert(0, gradientBackground);
		danceBackground = new FlxSprite();
		danceBackground.frames = Paths.getSparrowAtlas('storymenu/caramen-dance');
		danceBackground.animation.addByPrefix('dance', 'caramel', 36, true);
		danceBackground.animation.play('dance');
		danceBackground.setGraphicSize(Std.int(FlxG.width * 0.41));
		danceBackground.updateHitbox();
		danceBackground.setPosition(FlxG.width - danceBackground.width, FlxG.height - danceBackground.height);
		danceBackground.alpha = 0.5;
		danceBackground.antialiasing = ClientPrefs.data.antialiasing;
		// Keep the legacy art intact through x=1280/y=720; only overflow fades out.
		var storyAreaWidth:Int = Std.int(Math.min(1280, FlxG.width));
		bgYellow = new FlxSprite(0, 56).makeGraphic(storyAreaWidth, 386, FlxColor.WHITE);
		bgYellow.color = 0xFFF9CF51;

		bgSprite = new FlxSprite(0, 56);
		add(bgYellow);
		add(bgSprite);
		// The atlas belongs over the per-week artwork and color wash, but below
		// the interactive Story Mode UI.
		insert(members.indexOf(gradientBackground) + 1, danceBackground);

		grpWeekText = new FlxTypedGroup<MenuItem>();

		grpWeekCharacters = new FlxTypedGroup<MenuCharacter>();

		grpLocks = new FlxTypedGroup<FlxSprite>();

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence
		DiscordClient.changePresence("In the Menus", null);
		#end

		var num:Int = 0;
		for (i in 0...WeekData.weeksList.length)
		{
			var weekFile:WeekData = WeekData.weeksLoaded.get(WeekData.weeksList[i]);
			var isLocked:Bool = weekIsLocked(WeekData.weeksList[i]);
			if (!isLocked || !weekFile.hiddenUntilUnlocked)
			{
				loadedWeeks.push(weekFile);
				WeekData.setDirectoryFromWeek(weekFile);
				var weekGraphic:FlxGraphic = Paths.image('storymenu/' + weekFile.fileName);
				var weekThing:MenuItem = new MenuItem(0, bgSprite.y + 396, weekFile.fileName);
				var hasArtwork:Bool = weekGraphic != null;
				weekHasArtwork.push(hasArtwork);
				if (!hasArtwork)
				{
					weekThing.makeGraphic(1, 56, FlxColor.TRANSPARENT, true);
					var placeholder:FlxText = new FlxText(0, 0, 560, "Where's Picture?", 30);
					placeholder.setFormat(Paths.font('vcr.ttf'), 30, FlxColor.WHITE, RIGHT);
					placeholder.antialiasing = ClientPrefs.data.antialiasing;
					weekPlaceholderLabels.push(placeholder);
				}
				else weekPlaceholderLabels.push(null);
				weekThing.y += ((weekThing.height + 20) * num);
				weekThing.targetY = num;
				weekThing.x = FlxG.width - weekThing.width - 24;
				grpWeekText.add(weekThing);

				// Needs an offset thingie
				if (isLocked)
				{
					var lock:FlxSprite = new FlxSprite(weekThing.width + 10 + weekThing.x);
					lock.antialiasing = ClientPrefs.data.antialiasing;
					lock.frames = ui_tex;
					lock.animation.addByPrefix('lock', 'lock');
					lock.animation.play('lock');
					lock.x = weekThing.x + weekThing.width - lock.width - 12;
					lock.ID = num;
					grpLocks.add(lock);
				}
				num++;
			}
		}
		// Keep each mod's week artwork at its authored size. Row positions and
		// cards adapt to each image's own dimensions instead of scaling it down.
		var initialY:Float = 480;
		for (i in 0...loadedWeeks.length)
		{
			var item:MenuItem = grpWeekText.members[i];
			item.targetY = i;
			item.y = initialY;
			initialY += Math.max(item.frameHeight, 56) + 28;
		}

		WeekData.setDirectoryFromWeek(loadedWeeks[0]);
		var charArray:Array<String> = loadedWeeks[0].weekCharacters;
		for (char in 0...3)
		{
			// Keep the legacy 1280x720 role anchors. Mod MenuCharacter JSON owns
			// the artwork scale and offset; Story Mode must not resize or recenter it.
			var weekCharacterThing:MenuCharacter = new MenuCharacter((1280 * 0.25) * (1 + char) - 150, charArray[char]);
			weekCharacterThing.y += 70;
			grpWeekCharacters.add(weekCharacterThing);
		}
		add(grpWeekCharacters);
		// Place black alpha ramps over the artwork only. Their first pixel starts
		// exactly at the 1280x720 boundary measured from the screen's top-left.
		var overflowFadeRight:FlxSprite = makeOverflowFade(true);
		add(overflowFadeRight);
		weekSelectionPanel = new PhiPanel(1280, 470, 640, 116, 0xFF27384A);
		weekSelectionPanel.alpha = 0.62;
		add(weekSelectionPanel);
		add(grpWeekText);
		for (placeholder in weekPlaceholderLabels) if (placeholder != null) add(placeholder);
		add(grpLocks);
		grpDifficultyList = new FlxTypedGroup<FlxSprite>();
		grpDifficultyList.visible = false;
		add(grpDifficultyList);

		difficultySelectors = new FlxGroup();

		weekListLeft = FlxG.width;
		for (weekItem in grpWeekText.members)
			weekListLeft = Math.min(weekListLeft, weekItem.x);
		leftArrow = new FlxSprite(Math.max(760, weekListLeft - 460), 730);
		leftArrow.antialiasing = ClientPrefs.data.antialiasing;
		leftArrow.frames = ui_tex;
		leftArrow.animation.addByPrefix('idle', "arrow left");
		leftArrow.animation.addByPrefix('press', "arrow push left");
		leftArrow.animation.play('idle');
		difficultySelectors.add(leftArrow);

		Difficulty.resetList();
		if (lastDifficultyName == '')
		{
			lastDifficultyName = Difficulty.getDefault();
		}
		curDifficulty = Math.round(Math.max(0, Difficulty.defaultList.indexOf(lastDifficultyName)));

		sprDifficulty = new FlxSprite(0, leftArrow.y);
		sprDifficulty.antialiasing = ClientPrefs.data.antialiasing;
		difficultySelectors.add(sprDifficulty);

		rightArrow = new FlxSprite(leftArrow.x + 376, leftArrow.y);
		rightArrow.antialiasing = ClientPrefs.data.antialiasing;
		rightArrow.frames = ui_tex;
		rightArrow.animation.addByPrefix('idle', 'arrow right');
		rightArrow.animation.addByPrefix('press', "arrow push right", 24, false);
		rightArrow.animation.play('idle');
		difficultySelectors.add(rightArrow);

		add(difficultySelectors);
		difficultySelectors.visible = false;

		trackPanel = new PhiPanel(32, 856, 970, 220, 0xFF131C25);
		trackPanel.alpha = 0.66;
		add(trackPanel);
		var tracksSprite:FlxSprite = new FlxSprite(72, 880).loadGraphic(Paths.image('Menu_Tracks'));
		tracksSprite.antialiasing = ClientPrefs.data.antialiasing;
		add(tracksSprite);
		trackRowY = tracksSprite.y + 48;

		add(scoreText);
		add(txtWeekTitle);
		var backW:Int = Std.int(Math.max(200, FlxG.width * 0.12));
		var backH:Int = Std.int(Math.max(56, FlxG.height * 0.055));
		var backX:Float = FlxG.width * 0.522;
		var backY:Float = FlxG.height * 0.89;
		backButton = new PhiPanel(backX, backY, backW, backH, 0xFF27384A);
		backButton.alpha = 0.9;
		add(backButton);
		backButtonLabel = new FlxText(backX, backY + 4, backW, Language.get('storyBack', 'mainmenu'), 22);
		backButtonLabel.setFormat(Paths.font(Language.get('fontName', 'main') + '.ttf'), 22, FlxColor.WHITE, CENTER);
		backButtonLabel.borderStyle = OUTLINE_FAST;
		backButtonLabel.borderColor = 0xAA000000;
		backButtonLabel.antialiasing = ClientPrefs.data.antialiasing;
		add(backButtonLabel);
		updateBackButtonLabel();

		changeWeek();
		changeDifficulty();

		super.create();
		// The camera stays black behind the full-canvas, per-week gradient.
	}

	override function closeSubState()
	{
		persistentUpdate = true;
		changeWeek();
		super.closeSubState();
	}

	override function update(elapsed:Float)
	{
		// scoreText.setFormat('VCR OSD Mono', 32);
		lerpScore = Math.floor(FlxMath.lerp(intendedScore, lerpScore, Math.exp(-elapsed * 30)));
		if (Math.abs(intendedScore - lerpScore) < 10)
			lerpScore = intendedScore;

		if (lastDisplayedWeekScore != lerpScore)
		{
			lastDisplayedWeekScore = lerpScore;
			scoreText.text = "WEEK SCORE: " + lerpScore;
		}
		var handledBack:Bool = false;
		#if !mobile
		handledBack = processStoryPointer();
		#end

		// FlxG.watch.addQuick('font', scoreText.font);

		if (!movedBack && !selectedWeek)
		{
			var upP = controls.UI_UP_P;
			var downP = controls.UI_DOWN_P;
			if (selectingDifficulty)
			{
				if (FlxG.keys.justPressed.ESCAPE || controls.BACK #if android || FlxG.android.justReleased.BACK #end)
				{
					setDifficultyMode(false);
					handledBack = true;
					FlxG.sound.play(Paths.sound('cancelMenu'));
				}
				else
				{
					if (upP || downP)
					{
						changeDifficulty(upP ? -1 : 1);
						FlxG.sound.play(Paths.sound('scrollMenu'));
					}
					if (FlxG.mouse.wheel != 0)
					{
						changeDifficulty(-FlxG.mouse.wheel);
						FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
					}
				if (controls.ACCEPT)
						startSelectedWeek();
				}
			}
			else
			{
				if (upP || downP)
				{
					changeWeek(upP ? -1 : 1);
					FlxG.sound.play(Paths.sound('scrollMenu'));
				}
				if (FlxG.mouse.wheel != 0)
				{
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
					changeWeek(-FlxG.mouse.wheel);
				}
				if (!weekChangeBusy && weekChangeQueue.length == 0 && FlxG.keys.justPressed.CONTROL)
				{
					persistentUpdate = false;
					openSubState(new GameplayChangersSubstate());
				}
				else if (!weekChangeBusy && weekChangeQueue.length == 0 && controls.RESET)
				{
					persistentUpdate = false;
					openSubState(new ResetScoreSubState('', curDifficulty, '', curWeek));
				}
				else if (controls.ACCEPT && !weekChangeBusy && weekChangeQueue.length == 0)
					selectWeek();
			}
		}

		if ((controls.BACK || FlxG.keys.justPressed.ESCAPE #if android || FlxG.android.justReleased.BACK #end)
			&& !weekChangeBusy && weekChangeQueue.length == 0 && !movedBack && !selectedWeek && !selectingDifficulty && !handledBack)
		{
			handleStoryBack();
		}

		super.update(elapsed);

		grpLocks.forEach(function(lock:FlxSprite)
		{
			if (lock.ID < 0 || lock.ID >= grpWeekText.members.length) return;
			var linkedItem:MenuItem = grpWeekText.members[lock.ID];
			lock.y = linkedItem.y;
			lock.x = linkedItem.x + linkedItem.frameWidth * linkedItem.scale.x - lock.width - 12;
			lock.alpha = FlxMath.bound(1 - Math.abs(weekListOffset) / 480, 0, 1);
			lock.visible = (lock.y > FlxG.height / 2);
		});

		var listMoving:Bool = Math.abs(weekListOffset - weekListOffsetTarget) > 0.05;
		for (i in 0...grpWeekText.members.length)
		{
			var item = grpWeekText.members[i];
			if (item == null) continue;
			var weekOpacity:Float = weekIsLocked(loadedWeeks[i].fullName) ? 0.6 : 1;
			var focusOpacity:Float = i == curWeek ? 1 : 0.38;
			var panelOpacity:Float = FlxMath.bound(1 - Math.abs(weekListOffset) / 480, 0, 1);
			var desiredScale:Float = i == curWeek ? 1.1 : 1.0;
			var desiredAlpha:Float = weekOpacity * focusOpacity * panelOpacity;
			if (!item.active && !listMoving && Math.abs(item.alpha - desiredAlpha) < 0.005
				&& Math.abs(item.scale.x - desiredScale) < 0.005 && Math.abs(item.scale.y - desiredScale) < 0.005)
				continue;
			item.animationSpeed = weekAnimationRate;
			item.alpha = FlxMath.lerp(item.alpha, desiredAlpha, 1 - Math.exp(-elapsed * 10 * weekAnimationRate));
			item.scale.set(FlxMath.lerp(item.scale.x, desiredScale, 1 - Math.exp(-elapsed * 14 * weekAnimationRate)), FlxMath.lerp(item.scale.y, desiredScale, 1 - Math.exp(-elapsed * 14 * weekAnimationRate)));
			var itemWidth:Float = weekHasArtwork[i] ? item.frameWidth * item.scale.x : 560 * item.scale.x;
			item.x = FlxG.width - 24 - itemWidth - (item.y - 565) * STORY_SLOPE + weekListOffset;
			var placeholder:FlxText = weekPlaceholderLabels[i];
			if (placeholder != null)
			{
				placeholder.visible = item.visible;
				placeholder.alpha = item.alpha;
				placeholder.scale.set(item.scale.x, item.scale.y);
				placeholder.x = FlxG.width - 24 - 560 * item.scale.x - (item.y - 565) * STORY_SLOPE + weekListOffset;
				placeholder.y = item.y + (item.frameHeight - placeholder.height) * 0.5;
			}
		}

		advancePanelTransitions(elapsed);
		updateDifficultyList(elapsed);
		updateWeekSelectionPanel(elapsed);
		updateTrackScoreAnimation(elapsed);
	}

	/** Mobile Story Mode uses touch swipes for navigation and taps for confirm. */
	function processStoryPointer():Bool
	{
		var pointerX:Float = 0;
		var pointerY:Float = 0;
		var pressed:Bool = false;
		var justPressed:Bool = false;
		var justReleased:Bool = false;
		var activeTouch:Dynamic = null;
		for (touchPoint in FlxG.touches.list)
		{
			if (touchPoint == null) continue;
			if (touchPoint.pressed || touchPoint.justPressed || touchPoint.justReleased)
			{
				activeTouch = touchPoint;
				break;
			}
		}
		if (activeTouch != null)
		{
			// Raw gameX/gameY ignore the active camera's view margins. Story Mode
			// changes the design canvas to 1920x1080, so use Flixel's world mapping
			// to keep touch coordinates aligned with the rendered UI on phones.
			var touchPosition = activeTouch.getWorldPosition(FlxG.camera);
			pointerX = touchPosition.x;
			pointerY = touchPosition.y;
			touchPosition.put();
			pressed = activeTouch.pressed;
			justPressed = activeTouch.justPressed;
			justReleased = activeTouch.justReleased;
		}
		else
		{
			if (FlxG.mouse == null) return false;
			pointerX = FlxG.mouse.viewX;
			pointerY = FlxG.mouse.viewY;
			pressed = FlxG.mouse.pressed;
			justPressed = FlxG.mouse.justPressed;
			justReleased = FlxG.mouse.justReleased;
		}

		if (justPressed)
		{
			storyPointerHeld = true;
			storyPointerMoved = false;
			storyPointerLastY = pointerY;
		}
		if (storyPointerHeld && pressed)
		{
			var swipeStep:Float = Math.max(28, FlxG.height * 0.075);
			var deltaY:Float = pointerY - storyPointerLastY;
			if (Math.abs(deltaY) >= swipeStep)
			{
				var steps:Int = Std.int(Math.floor(Math.abs(deltaY) / swipeStep));
				var change:Int = deltaY < 0 ? 1 : -1;
				for (_ in 0...steps)
				{
					if (selectingDifficulty) changeDifficulty(change);
					else changeWeek(change);
				}
				storyPointerLastY += (deltaY < 0 ? -1 : 1) * steps * swipeStep;
				storyPointerMoved = true;
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
			}
		}
		if (!justReleased) return false;

		var didHandle:Bool = false;
		if (!storyPointerMoved && !weekChangeBusy && weekChangeQueue.length == 0 && !movedBack && !selectedWeek)
		{
			didHandle = handleStoryTap(pointerX, pointerY);
		}
		storyPointerHeld = false;
		storyPointerMoved = false;
		return didHandle;
	}

	#if mobile
	function storyTouchGamePoint(stageX:Float, stageY:Float):Point
	{
		var point:Point = new Point(stageX, stageY);
		FlxG.game.globalToLocal(point);
		// FlxTouch.setXY() already converts stage coordinates to game-local
		// coordinates with globalToLocal(). Dividing by scaleMode a second time
		// shifts taps on scaled mobile windows, making the Back button miss.
		return point;
	}

	function storyTouchWorldPoint(stageX:Float, stageY:Float):Point
	{
		var point:Point = storyTouchGamePoint(stageX, stageY);
		var camera = FlxG.camera;
		point.x = (point.x - camera.x) / camera.zoom + camera.viewMarginX + camera.scroll.x;
		point.y = (point.y - camera.y) / camera.zoom + camera.viewMarginY + camera.scroll.y;
		return point;
	}

	function onStoryTouchBegin(event:TouchEvent):Void
	{
		if (storyNativeTouchId >= 0 || movedBack || selectedWeek) return;
		storyNativeTouchId = event.touchPointID;
		storyNativeTouchMoved = false;
		storyPointerHeld = true;
		storyPointerMoved = false;
		var point = storyTouchGamePoint(event.stageX, event.stageY);
		storyPointerLastY = point.y;
		point = null;
	}

	function onStoryTouchMove(event:TouchEvent):Void
	{
		if (event.touchPointID != storyNativeTouchId || !storyPointerHeld) return;
		var point = storyTouchGamePoint(event.stageX, event.stageY);
		var deltaY:Float = point.y - storyPointerLastY;
		point = null;
		var swipeStep:Float = Math.max(28, FlxG.height * 0.075);
		if (Math.abs(deltaY) < swipeStep) return;
		var steps:Int = Std.int(Math.floor(Math.abs(deltaY) / swipeStep));
		var change:Int = deltaY < 0 ? 1 : -1;
		for (_ in 0...steps)
		{
			if (selectingDifficulty) changeDifficulty(change);
			else changeWeek(change);
		}
		storyPointerLastY += (deltaY < 0 ? -1 : 1) * steps * swipeStep;
		storyNativeTouchMoved = storyPointerMoved = true;
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
	}

	function onStoryTouchEnd(event:TouchEvent):Void
	{
		if (event.touchPointID != storyNativeTouchId) return;
		if (!storyNativeTouchMoved)
		{
			var point = storyTouchWorldPoint(event.stageX, event.stageY);
			handleStoryTap(point.x, point.y);
			point = null;
		}
		storyNativeTouchId = -1;
		storyNativeTouchMoved = false;
		storyPointerHeld = false;
		storyPointerMoved = false;
	}
	#end

	function handleStoryTap(pointerX:Float, pointerY:Float):Bool
	{
		if (weekChangeBusy || weekChangeQueue.length > 0 || movedBack || selectedWeek) return false;
		if (backButton != null && pointerX >= backButton.x && pointerX <= backButton.x + backButton.panelWidth
			&& pointerY >= backButton.y && pointerY <= backButton.y + backButton.height)
		{
			handleStoryBack();
			return true;
		}
		if (selectingDifficulty)
		{
			if (isSelectedDifficultyAt(pointerX, pointerY))
				startSelectedWeek();
			return isSelectedDifficultyAt(pointerX, pointerY);
		}
		if (isSelectedWeekAt(pointerX, pointerY))
			selectWeek();
		return isSelectedWeekAt(pointerX, pointerY);
	}
	function isSelectedWeekAt(x:Float, y:Float):Bool
	{
		if (curWeek < 0 || curWeek >= grpWeekText.members.length) return false;
		var item:MenuItem = grpWeekText.members[curWeek];
		if (item == null || !item.visible) return false;
		var left:Float = item.x;
		var top:Float = item.y;
		var width:Float = weekHasArtwork[curWeek] ? item.frameWidth * item.scale.x : 560 * item.scale.x;
		var height:Float = item.frameHeight * item.scale.y;
		var placeholder:FlxText = weekPlaceholderLabels[curWeek];
		if (placeholder != null)
		{
			left = placeholder.x;
			width = placeholder.width * placeholder.scale.x;
			height = placeholder.height * placeholder.scale.y;
			top = placeholder.y;
		}
		return x >= left && x <= left + width && y >= top && y <= top + height;
	}

	function isSelectedDifficultyAt(x:Float, y:Float):Bool
	{
		if (grpDifficultyList == null) return false;
		for (item in grpDifficultyList.members)
		{
			if (item == null || item.ID != curDifficulty || !item.visible) continue;
			return x >= item.x && x <= item.x + item.frameWidth * item.scale.x
				&& y >= item.y && y <= item.y + item.frameHeight * item.scale.y;
		}
		return false;
	}

	function updateBackButtonLabel():Void
	{
		if (backButtonLabel == null) return;
		var key:String = selectingDifficulty ? 'storyBackToWeeks' : 'storyBack';
		var label:String = Language.get(key, 'mainmenu');
		if (label == key)
			label = selectingDifficulty ? 'BACK TO WEEKS' : 'BACK';
		backButtonLabel.text = label;
		backButtonLabel.size = selectingDifficulty ? 18 : 22;
		backButtonLabel.y = backButton.y + (backButton.height - backButtonLabel.height) * 0.5;
	}

	override function destroy():Void
	{
		#if mobile
		if (Lib.current != null && Lib.current.stage != null)
		{
			Lib.current.stage.removeEventListener(TouchEvent.TOUCH_BEGIN, onStoryTouchBegin);
			Lib.current.stage.removeEventListener(TouchEvent.TOUCH_MOVE, onStoryTouchMove);
			Lib.current.stage.removeEventListener(TouchEvent.TOUCH_END, onStoryTouchEnd);
		}
		#end
		super.destroy();
	}

	function handleStoryBack():Void
	{
		if (weekChangeBusy || weekChangeQueue.length > 0 || movedBack || selectedWeek) return;
		FlxG.sound.play(Paths.sound('cancelMenu'));
		if (selectingDifficulty)
			setDifficultyMode(false);
		else
		{
			movedBack = true;
			MusicBeatState.switchState(new MainMenuState());
		}
	}

	var movedBack:Bool = false;
	var selectedWeek:Bool = false;
	var stopspamming:Bool = false;

	function selectWeek()
	{
		if (!weekIsLocked(loadedWeeks[curWeek].fullName))
		{
			setDifficultyMode(true);
			FlxG.sound.play(Paths.sound('scrollMenu'));
		}
		else
			FlxG.sound.play(Paths.sound('cancelMenu'));
	}

	function setDifficultyMode(value:Bool):Void
	{
		selectingDifficulty = value;
		updateBackButtonLabel();
		difficultySelectors.visible = false;
		if (value)
		{
			grpWeekText.visible = true;
			grpLocks.visible = true;
			weekListOffsetTarget = -480;
			difficultyListOffset = 360;
			difficultyListOffsetTarget = 0;
			grpDifficultyList.visible = true;
			rebuildDifficultyList();
		}
		else
		{
			grpWeekText.visible = true;
			grpLocks.visible = true;
			weekListOffsetTarget = 0;
			difficultyListOffsetTarget = 360;
		}
	}

	function advancePanelTransitions(elapsed:Float):Void
	{
		var amount:Float = 1 - Math.exp(-elapsed * 8 * weekAnimationRate);
		weekListOffset = FlxMath.lerp(weekListOffset, weekListOffsetTarget, amount);
		difficultyListOffset = FlxMath.lerp(difficultyListOffset, difficultyListOffsetTarget, amount);
		if (selectingDifficulty && Math.abs(weekListOffset - weekListOffsetTarget) < 1)
		{
			grpWeekText.visible = false;
			grpLocks.visible = false;
		}
		if (!selectingDifficulty && Math.abs(difficultyListOffset - difficultyListOffsetTarget) < 1)
			grpDifficultyList.visible = false;
	}

	function rebuildDifficultyList():Void
	{
		// FlxTypedGroup.clear() only drops references; it does not destroy members.
		// Re-entering difficulty selection otherwise leaks every old icon and its
		// frame/animation objects.
		for (item in grpDifficultyList.members)
			if (item != null) item.destroy();
		grpDifficultyList.clear();
		for (i in 0...Difficulty.list.length)
		{
			var diffName:String = Difficulty.list[i];
			var icon:FlxSprite = new FlxSprite();
			icon.antialiasing = ClientPrefs.data.antialiasing;
			icon.loadGraphic(Paths.image('menudifficulties/' + Paths.formatToSongPath(diffName)));
			icon.ID = i;
			grpDifficultyList.add(icon);
		}
		updateDifficultyList(1);
	}

	function updateDifficultyList(elapsed:Float):Void
	{
		if (grpDifficultyList == null || !grpDifficultyList.visible) return;
		for (item in grpDifficultyList.members)
		{
			if (item == null) continue;
			var selected:Bool = item.ID == curDifficulty;
			var targetScale:Float = selected ? 1.08 : 1;
			var scale:Float = FlxMath.lerp(item.scale.x, targetScale, 1 - Math.exp(-elapsed * 10 * weekAnimationRate));
			item.scale.set(scale, scale);
			var panelOpacity:Float = FlxMath.bound(1 - difficultyListOffset / 360, 0, 1);
			item.alpha = FlxMath.lerp(item.alpha, (selected ? 1 : 0.55) * panelOpacity, 1 - Math.exp(-elapsed * 10 * weekAnimationRate));
			var targetY:Float = 500 + (item.ID - curDifficulty) * 112;
			item.y = FlxMath.lerp(item.y, targetY, 1 - Math.exp(-elapsed * 10 * weekAnimationRate));
			item.x = FlxG.width - 24 - item.frameWidth * scale - (item.y - 500) * STORY_SLOPE + difficultyListOffset;
		}
	}

	function updateWeekSelectionPanel(elapsed:Float):Void
	{
		if (weekSelectionPanel == null) return;
		if (selectingDifficulty)
		{
			var selectedDifficulty:FlxSprite = null;
			if (grpDifficultyList != null)
				for (item in grpDifficultyList.members) if (item != null && item.ID == curDifficulty) selectedDifficulty = item;
			if (selectedDifficulty != null)
			{
				weekSelectionPanel.visible = true;
			weekSelectionPanel.setPosition(FlxG.width - 24 - 640 - (selectedDifficulty.y - 500) * STORY_SLOPE + difficultyListOffset, selectedDifficulty.y - 28);
				weekSelectionPanel.alpha = FlxMath.lerp(weekSelectionPanel.alpha, 0.62, 1 - Math.exp(-elapsed * 10 * weekAnimationRate));
			}
			return;
		}
		weekSelectionPanel.visible = false;
	}

	function updateTrackScoreAnimation(elapsed:Float):Void
	{
		if (!trackScoreAnimating || trackScoreValues.length == 0 || trackScoreValues.length != trackScoreTargets.length) return;
		var amount:Float = 1 - Math.exp(-elapsed * 7 * weekAnimationRate);
		var stillAnimating:Bool = false;
		for (i in 0...trackScoreValues.length)
		{
			trackScoreValues[i] = FlxMath.lerp(trackScoreValues[i], trackScoreTargets[i], amount);
			if (Math.abs(trackScoreValues[i] - trackScoreTargets[i]) < 1)
				trackScoreValues[i] = trackScoreTargets[i];
			else
				stillAnimating = true;
			var scoreValue:String = Std.string(Math.round(trackScoreValues[i]));
			if (i < trackScoreRows.length && trackScoreRows[i].text != scoreValue)
				trackScoreRows[i].text = scoreValue;
		}
		trackScoreAnimating = stillAnimating;
	}

	function startSelectedWeek():Void
	{
		if (!weekIsLocked(loadedWeeks[curWeek].fullName))
		{
			// We can't use Dynamic Array .copy() because that crashes HTML5, here's a workaround.
			var songArray:Array<String> = [];
			var leWeek:Array<Dynamic> = loadedWeeks[curWeek].songs;
			for (i in 0...leWeek.length)
			{
				songArray.push(leWeek[i][0]);
			}

			// Nevermind that's stupid lmao
			try
			{
				PlayState.storyPlaylist = songArray;
				PlayState.isStoryMode = true;
				selectedWeek = true;

				var diffic = Difficulty.getFilePath(curDifficulty);
				if (diffic == null)
					diffic = '';

				PlayState.storyDifficulty = curDifficulty;

				PlayState.SONG = Song.loadFromJson(PlayState.storyPlaylist[0].toLowerCase() + diffic, PlayState.storyPlaylist[0].toLowerCase());
				PlayState.campaignScore = 0;
				PlayState.campaignMisses = 0;
			}
			catch (e:Dynamic)
			{
				trace('ERROR! $e');
				selectedWeek = false;
				FlxG.sound.play(Paths.sound('cancelMenu'));
				return;
			}

			if (stopspamming == false)
			{
				FlxG.sound.play(Paths.sound('confirmMenu'));

				grpWeekText.members[curWeek].isFlashing = true;
				for (char in grpWeekCharacters.members)
				{
					if (char.character != '' && char.hasConfirmAnimation)
					{
						char.animation.play('confirm');
					}
				}
				stopspamming = true;
			}

			LoadingState.prepareToSong();
			new FlxTimer().start(1, function(tmr:FlxTimer)
			{
				LoadingState.prepareToSong();
				if (ClientPrefs.data.loadingScreen)
				{
					FlxTransitionableState.skipNextTransIn = true;
					FlxTransitionableState.skipNextTransOut = true;
				}
				LoadingState.loadAndSwitchState(new PlayState(), true);
				FreeplayState.destroyFreeplayVocals();
			});

			#if (MODS_ALLOWED && DISCORD_ALLOWED)
			DiscordClient.loadModRPC();
			#end
		}
		else
			FlxG.sound.play(Paths.sound('cancelMenu'));
	}

	var tweenDifficulty:FlxTween;

	function changeDifficulty(change:Int = 0):Void
	{
		if (Difficulty.list.length == 0) return;
		curDifficulty += change;

		if (curDifficulty < 0)
			curDifficulty = Difficulty.list.length - 1;
		if (curDifficulty >= Difficulty.list.length)
			curDifficulty = 0;

		WeekData.setDirectoryFromWeek(loadedWeeks[curWeek]);

		var diff:String = Difficulty.getString(curDifficulty);
		var newImage:FlxGraphic = Paths.image('menudifficulties/' + Paths.formatToSongPath(diff));
		// trace(Mods.currentModDirectory + ', menudifficulties/' + Paths.formatToSongPath(diff));

		if (sprDifficulty.graphic != newImage)
		{
			sprDifficulty.loadGraphic(newImage);
			sprDifficulty.x = leftArrow.x + 60;
			sprDifficulty.x += (308 - sprDifficulty.width) / 3;
			sprDifficulty.alpha = 0;
			sprDifficulty.y = leftArrow.y - 15;

			if (tweenDifficulty != null)
				tweenDifficulty.cancel();
			tweenDifficulty = FlxTween.tween(sprDifficulty, {y: leftArrow.y + 15, alpha: 1}, 0.07, {
				onComplete: function(twn:FlxTween)
				{
					tweenDifficulty = null;
				}
			});
		}
		lastDifficultyName = diff;
		if (change != 0)
			transitionGradient(loadedWeeks[curWeek], change, weekAnimationRate, 0.5);

		#if !switch
		intendedScore = Highscore.getWeekScore(loadedWeeks[curWeek].fullName, curDifficulty);
		#end
		updateTrackScores(change != 0);
	}

	var lerpScore:Int = 0;
	var intendedScore:Int = 0;

	function changeWeek(change:Int = 0):Void
	{
		if (change == 0)
		{
			applyWeekChange(0);
			return;
		}
		var now:Float = haxe.Timer.stamp();
		weekAnimationRate = (lastWeekSwitchTime >= 0 && now - lastWeekSwitchTime < 0.125) ? 3 : 1;
		lastWeekSwitchTime = now;
		// Keep only one pending destination delta. Repeated keys/wheel events
		// should never make the player wait through a long chain of stale tweens.
		if (weekChangeQueue.length == 0) weekChangeQueue.push(change);
		else weekChangeQueue[0] += change;
		startQueuedWeekChange();
	}

	function startQueuedWeekChange():Void
	{
		if (weekChangeBusy || weekChangeQueue.length == 0) return;
		weekChangeBusy = true;
		var change:Int = weekChangeQueue.shift();
		if (change == 0)
		{
			weekChangeBusy = false;
			if (weekChangeQueue.length == 0) weekAnimationRate = 1;
			return;
		}
		var direction:Int = change < 0 ? -1 : 1;
		animateWeekVisuals(direction, true, function()
		{
			applyWeekChange(change);
			animateWeekVisuals(direction, false, function()
			{
				weekChangeBusy = false;
				if (weekChangeQueue.length > 0) startQueuedWeekChange();
				else weekAnimationRate = 1;
			});
		});
	}

	function weekTransitionSprites():Array<FlxSprite>
	{
		var sprites:Array<FlxSprite> = [bgYellow, bgSprite, txtWeekTitle, scoreText];
		for (character in grpWeekCharacters.members) if (character != null) sprites.push(character);
		for (row in trackNameRows) if (row != null) sprites.push(row);
		for (row in trackScoreRows) if (row != null) sprites.push(row);
		for (row in trackGradeRows) if (row != null) sprites.push(row);
		return sprites;
	}

	function animateWeekVisuals(direction:Int, leaving:Bool, done:Void->Void):Void
	{
		var sprites:Array<FlxSprite> = weekTransitionSprites();
		if (sprites.length == 0) { done(); return; }
		var remaining:Int = sprites.length;
		var slideX:Float = direction * 96;
		var slideY:Float = -direction * 64;
		for (sprite in sprites)
		{
			var shouldSlide:Bool = sprite == bgYellow || sprite == bgSprite;
			if (leaving)
			{
				if (!sprite.visible) { remaining--; continue; }
				if (shouldSlide)
				{
					var originX:Float = sprite.x;
					var originY:Float = sprite.y;
				FlxTween.tween(sprite, {x: sprite.x + slideX, y: sprite.y + slideY, alpha: 0}, 0.0625 / weekAnimationRate,
						{ease: FlxEase.quadIn, onComplete: function(_) { sprite.setPosition(originX, originY); remaining--; if (remaining <= 0) done(); }});
				}
				else
					FlxTween.tween(sprite, {alpha: 0}, 0.0625 / weekAnimationRate,
						{ease: FlxEase.quadIn, onComplete: function(_) { remaining--; if (remaining <= 0) done(); }});
			}
			else
			{
				if (!sprite.visible) { remaining--; continue; }
				var targetX:Float = sprite.x;
				var targetY:Float = sprite.y;
				if (shouldSlide) { sprite.x = targetX - slideX; sprite.y = targetY - slideY; }
				sprite.alpha = 0;
				sprite.visible = true;
				if (shouldSlide)
					FlxTween.tween(sprite, {x: targetX, y: targetY, alpha: 1}, 0.0625 / weekAnimationRate,
						{ease: FlxEase.quadOut, onComplete: function(_) { remaining--; if (remaining <= 0) done(); }});
				else
					FlxTween.tween(sprite, {alpha: 1}, 0.0625 / weekAnimationRate,
						{ease: FlxEase.quadOut, onComplete: function(_) { remaining--; if (remaining <= 0) done(); }});
			}
		}
		if (remaining <= 0) done();
	}

	function applyWeekChange(change:Int):Void
	{
		if (loadedWeeks.length == 0) return;
		curWeek = ((curWeek + change) % loadedWeeks.length + loadedWeeks.length) % loadedWeeks.length;

		var leWeek:WeekData = loadedWeeks[curWeek];
		WeekData.setDirectoryFromWeek(leWeek);
		scoreText.font = Paths.font('vcr.ttf');
		scoreText.size = 20;

		var leName:String = leWeek.storyName;
		var description:String = leWeek.description;
		if (description == null || StringTools.trim(description).length == 0)
			description = leName;
		txtWeekTitle.text = (description == null || description.length == 0) ? leWeek.weekName : description;
		txtWeekTitle.setFormat(Paths.font(Language.get('fontName', 'main') + '.ttf'), 26, FlxColor.WHITE, LEFT);
		txtWeekTitle.wordWrap = true;
		txtWeekTitle.autoSize = false;
		txtWeekTitle.fieldWidth = 1280;
		txtWeekTitle.fieldHeight = 240;
		txtWeekTitle.borderStyle = OUTLINE_FAST;
		txtWeekTitle.borderColor = 0x88000000;
		txtWeekTitle.borderSize = 2;

		var unlocked:Bool = !weekIsLocked(leWeek.fullName);
		for (i in 0...grpWeekText.members.length)
		{
			var item:MenuItem = grpWeekText.members[i];
				// Keep the selected image centered and stack neighbors using their
				// actual source heights rather than a fixed 120px row.
			if (i == curWeek && unlocked)
				item.alpha = 1;
			else
				item.alpha = 0.6;
		}
		var rowOffset:Float = 0;
		for (i in curWeek...grpWeekText.members.length)
		{
			var item:MenuItem = grpWeekText.members[i];
			item.active = true;
			item.targetY = rowOffset / 120;
			rowOffset += item.frameHeight + 28;
		}
		rowOffset = 0;
		var index:Int = curWeek - 1;
		while (index >= 0)
		{
			var item:MenuItem = grpWeekText.members[index];
			item.active = true;
			rowOffset -= item.frameHeight + 28;
			item.targetY = rowOffset / 120;
			index--;
		}

		bgSprite.visible = true;
		var assetName:String = leWeek.weekBackground;
		if (assetName == null || assetName.length < 1)
		{
			bgSprite.visible = false;
		}
		else
		{
			// Resolve the graphic while this mod's directory is active. Deferring
			// Paths.image until a tween callback breaks mod-to-mod week changes.
			bgSprite.loadGraphic(Paths.image('menubackgrounds/menu_' + assetName));
		}
		if (bgYellow != null && leWeek.freeplayColor != null && leWeek.freeplayColor.length >= 3)
			bgYellow.color = FlxColor.fromRGB(leWeek.freeplayColor[0], leWeek.freeplayColor[1], leWeek.freeplayColor[2]);
		if (change != 0) transitionGradient(leWeek, 1, weekAnimationRate, 0.125);
		PlayState.storyWeek = curWeek;

		Difficulty.loadFromWeek();
		difficultySelectors.visible = false;

		if (Difficulty.list.contains(Difficulty.getDefault()))
			curDifficulty = Difficulty.list.indexOf(Difficulty.getDefault());
		else
			curDifficulty = 0;

		var newPos:Int = Difficulty.list.indexOf(lastDifficultyName);
		// trace('Pos of ' + lastDifficultyName + ' is ' + newPos);
		if (newPos > -1)
		{
			curDifficulty = newPos;
		}
		if (curDifficulty >= Difficulty.list.length)
			curDifficulty = 0;
		updateText(change != 0);
		if (selectingDifficulty)
			rebuildDifficultyList();
	}

	function weekIsLocked(name:String):Bool
	{
		var leWeek:WeekData = WeekData.weeksLoaded.get(name);
		return (!leWeek.startUnlocked
			&& leWeek.weekBefore.length > 0
			&& (!weekCompleted.exists(leWeek.weekBefore) || !weekCompleted.get(leWeek.weekBefore)));
	}

	function updateText(animateTrackScores:Bool = false)
	{
		var weekArray:Array<String> = loadedWeeks[curWeek].weekCharacters;
		for (i in 0...grpWeekCharacters.length)
		{
			grpWeekCharacters.members[i].changeCharacter(weekArray[i]);
		}
		positionWeekDescription();

		var leWeek:WeekData = loadedWeeks[curWeek];
		var stringThing:Array<String> = [];
		for (i in 0...leWeek.songs.length)
		{
			stringThing.push(leWeek.songs[i][0]);
		}

		while (trackNameRows.length > stringThing.length) remove(trackNameRows.pop(), true);
		while (trackScoreRows.length > stringThing.length) remove(trackScoreRows.pop(), true);
		while (trackGradeRows.length > stringThing.length) remove(trackGradeRows.pop(), true);
		while (trackNameRows.length < stringThing.length)
		{
			var nameRow:FlxText = new PhiItalicText(0, 0, 650, '', 20);
			nameRow.setFormat(Paths.font('vcr.ttf'), 20, 0xFFe55777, LEFT);
			nameRow.antialiasing = ClientPrefs.data.antialiasing;
			trackNameRows.push(nameRow); add(nameRow);
			var scoreRow:FlxText = new PhiItalicText(0, 0, 180, '', 18);
			scoreRow.setFormat(Paths.font('vcr.ttf'), 18, FlxColor.WHITE, RIGHT);
			scoreRow.antialiasing = ClientPrefs.data.antialiasing;
			trackScoreRows.push(scoreRow); add(scoreRow);
			var gradeRow:FlxText = new PhiItalicText(0, 0, 70, '', 18);
			gradeRow.setFormat(Paths.font('vcr.ttf'), 18, FlxColor.WHITE, LEFT);
			gradeRow.antialiasing = ClientPrefs.data.antialiasing;
			trackGradeRows.push(gradeRow); add(gradeRow);
		}
		// Paths.font resolves mod-local fonts. Refresh every pooled row after the
		// selected week directory is set so reused rows cannot retain another
		// mod's VCR face.
		var weekVcr:String = Paths.font('vcr.ttf');
		scoreText.setFormat(weekVcr, 20, FlxColor.WHITE, LEFT);
		for (i in 0...stringThing.length)
		{
			var rowY:Float = trackRowY + i * 34;
			var shearX:Float = -(rowY - trackRowY) * STORY_SLOPE;
			trackNameRows[i].text = stringThing[i].toUpperCase();
			var weekSong:Array<Dynamic> = leWeek.songs != null && i < leWeek.songs.length ? cast leWeek.songs[i] : null;
			var opponentHint:String = weekSong != null && weekSong.length > 1 && weekSong[1] != null ? Std.string(weekSong[1]) : null;
			var opponentColor:FlxColor = opponentHealthColor(stringThing[i], leWeek, opponentHint);
			trackNameRows[i].setFormat(weekVcr, 20, opponentColor, LEFT);
			// Keep the per-song tint explicit after rebuilding the text format;
			// this avoids mobile renderers retaining a stale pooled-row color.
			trackNameRows[i].color = opponentColor;
			trackNameRows[i].setPosition(72 + shearX, rowY);
			trackScoreRows[i].setFormat(weekVcr, 18, FlxColor.WHITE, RIGHT);
			trackScoreRows[i].setPosition(760 + shearX, rowY);
			trackGradeRows[i].setFormat(Paths.font(Language.get('fontName', 'main') + '.ttf'), 16, FlxColor.WHITE, LEFT);
			trackGradeRows[i].setPosition(950 + shearX, rowY);
		}
		updateTrackScores(animateTrackScores);

		#if !switch
		intendedScore = Highscore.getWeekScore(loadedWeeks[curWeek].fullName, curDifficulty);
		#end
	}

	function updateTrackScores(animate:Bool = false):Void
	{
		if (loadedWeeks.length == 0 || curWeek >= loadedWeeks.length) return;
		var scores:Array<Int> = [];
		for (song in loadedWeeks[curWeek].songs)
			scores.push(Highscore.getScore(Std.string(song[0]), curDifficulty));
		trackScoreTargets = scores;
		if (!animate)
		{
			trackScoreValues = [];
			for (score in scores) trackScoreValues.push(score);
			trackScoreAnimating = false;
		}
		else
		{
			while (trackScoreValues.length < scores.length) trackScoreValues.push(0);
			while (trackScoreValues.length > scores.length) trackScoreValues.pop();
			trackScoreAnimating = false;
			for (i in 0...scores.length)
				if (Math.abs(trackScoreValues[i] - scores[i]) >= 1)
				{
					trackScoreAnimating = true;
					break;
				}
		}
		for (i in 0...trackScoreRows.length)
		{
			trackScoreRows[i].text = i < trackScoreValues.length ? Std.string(Math.round(trackScoreValues[i])) : '';
			var grade:String = '';
			if (i < loadedWeeks[curWeek].songs.length)
			{
				var details:Dynamic = Highscore.getDetails(Std.string(loadedWeeks[curWeek].songs[i][0]), curDifficulty);
				if (details != null && details.length > 2 && details[2] != null && details[2].length > 5)
					grade = states.freeplayState.objects.replay.ReplayGrade.calculate(Std.string(details[2][2]), Std.int(details[2][5]));
			}
			trackGradeRows[i].text = grade;
			trackGradeRows[i].color = gradeColor(grade);
		}
		// Keep the aggregate score beside the TRACKS heading, separate from the
		// per-song score and grade columns.
		scoreText.x = 330;
		scoreText.y = 878;
	}

	function gradeColor(grade:String):FlxColor
	{
		return switch (grade)
		{
			case 'D.C.P': 0xFFFF7186;
			case 'V': 0xFFFF9A6A;
			case 'S': 0xFFFFE477;
			case 'A': 0xFF31C878;
			case 'B': 0xFF22C7C9;
			case 'C': 0xFF4388F5;
			case 'D': 0xFF929BA5;
			default: FlxColor.WHITE;
		};
	}

	function transitionGradient(week:WeekData, direction:Int, speed:Float = 1, baseDuration:Float = 0.125):Void
	{
		var next:FlxSprite = makeOpponentGradient(week);
		if (gradientTransitionTween != null)
		{
			gradientTransitionTween.cancel();
			gradientTransitionTween = null;
		}
		if (gradientIncoming != null)
		{
			remove(gradientIncoming, true);
			gradientIncoming = null;
		}
		if (gradientBackground != null) gradientBackground.alpha = 1;
		if (gradientBackground == null || direction == 0)
		{
			if (gradientBackground != null) remove(gradientBackground, true);
			gradientBackground = next;
			insert(0, gradientBackground);
			return;
		}
		var old:FlxSprite = gradientBackground;
		insert(members.indexOf(danceBackground), next);
		gradientIncoming = next;
		next.alpha = 0;
		var duration:Float = baseDuration / Math.max(1, speed);
		gradientTransitionTween = FlxTween.tween(next, {alpha: 1}, duration, {
			ease: FlxEase.quadOut,
			onComplete: function(_)
			{
				remove(old, true);
				gradientBackground = next;
				gradientIncoming = null;
				gradientTransitionTween = null;
			}
		});
	}

	function makeOpponentGradient(week:WeekData):FlxSprite
	{
		var gradientKey:String = (week == null ? 'default' : week.folder + '|' + week.fullName + '|' + week.fileName) + '|' + curDifficulty;
		var bitmap:BitmapData = opponentGradientCache.get(gradientKey);
		if (bitmap != null)
		{
			var cachedGradient:FlxSprite = new FlxSprite();
			cachedGradient.pixels = bitmap;
			cachedGradient.setGraphicSize(FlxG.width, FlxG.height);
			cachedGradient.updateHitbox();
			cachedGradient.antialiasing = true;
			cachedGradient.alpha = 1;
			cachedGradient.scrollFactor.set();
			return cachedGradient;
		}

		var colors:Array<FlxColor> = [];
		if (week != null && week.songs != null)
		{
			WeekData.setDirectoryFromWeek(week);
			for (songEntry in week.songs)
			{
				var songName:String = Std.string(songEntry[0]);
				var opponentHint:String = songEntry.length > 1 && songEntry[1] != null ? Std.string(songEntry[1]) : null;
				var songColor:FlxColor = opponentHealthColor(songName, week, opponentHint);
				colors.push(songColor);
			}
		}
		if (colors.length == 0)
		{
			var fallback:Array<Int> = week != null && week.freeplayColor != null ? week.freeplayColor : [40, 40, 80];
			colors.push(FlxColor.fromRGB(fallback[0], fallback[1], fallback[2]));
		}
		if (colors.length == 1) colors.push(FlxColor.BLACK);
		bitmap = FlxGradient.createGradientBitmapData(Std.int(Math.min(FlxG.width, 640)), Std.int(Math.min(FlxG.height, 360)), colors, 1, 45);
		opponentGradientCache.set(gradientKey, bitmap);
		var gradient:FlxSprite = new FlxSprite();
		gradient.pixels = bitmap;
		gradient.setGraphicSize(FlxG.width, FlxG.height);
		gradient.updateHitbox();
		gradient.antialiasing = true;
		gradient.alpha = 1;
		gradient.scrollFactor.set();
		return gradient;
	}

	function opponentHealthColor(songName:String, week:WeekData, ?opponentHint:String):FlxColor
	{
		var songId:String = Paths.formatToSongPath(songName);
		var colorKey:String = week.folder + '|' + week.fullName + '|' + songId + '|' + curDifficulty + '|' + (opponentHint == null ? '' : opponentHint);
		if (opponentColorCache.exists(colorKey)) return opponentColorCache.get(colorKey);
		var opponent:String = opponentHint == null ? null : StringTools.trim(opponentHint);
		// The chart's player2 is the actual opponent; week song entries can name
		// the player character (for example bf) or an icon alias instead.
		var suffix:String = Difficulty.getFilePath(curDifficulty);
		var chartOpponent:String = readChartOpponent(songId, songId + (suffix == null ? '' : suffix));
		if (chartOpponent == null) chartOpponent = readChartOpponent(songId, songId);
		if (chartOpponent != null && chartOpponent.length > 0)
		{
			var chartColor:Null<FlxColor> = readOpponentHealthColor(chartOpponent);
			if (chartColor != null)
			{
				opponentColorCache.set(colorKey, chartColor);
				return chartColor;
			}
			var hintColor:Null<FlxColor> = readOpponentHealthColor(opponent);
			if (hintColor != null)
			{
				opponentColorCache.set(colorKey, hintColor);
				return hintColor;
			}
			opponent = chartOpponent;
		}
		else
		{
			// If no chart opponent can be loaded, retain the week JSON's opponent hint.
			var hintColor:Null<FlxColor> = readOpponentHealthColor(opponent);
			if (hintColor != null)
			{
				opponentColorCache.set(colorKey, hintColor);
				return hintColor;
			}
		}
		if (opponent == null || opponent.length == 0) opponent = 'dad';
		var fallbackColor:FlxColor = switch (opponent.toLowerCase())
		{
			case 'bf' | 'bf-pixel' | 'bf-car' | 'bf-christmas': 0xFF31B0D1;
			case 'gf' | 'gf-pixel' | 'gf-christmas': 0xFFA6E22E;
			case 'mom' | 'mom-pixel': 0xFFFF78BF;
			case 'monster' | 'monster-pixel': 0xFF8F6BFF;
			case 'pico' | 'pico-pixel': 0xFF00E9FF;
			default: 0xFFA32E4B;
		};
		opponentColorCache.set(colorKey, fallbackColor);
		return fallbackColor;
	}

	function readOpponentHealthColor(opponent:String):Null<FlxColor>
	{
		if (opponent == null || opponent.length == 0) return null;
		try
		{
			var rawCharacter:String = Paths.getTextFromFile('characters/' + opponent + '.json');
			if (rawCharacter != null && rawCharacter.length > 0)
			{
				var data:Dynamic = Json.parse(rawCharacter);
				var health:Array<Dynamic> = cast Reflect.field(data, 'healthbar_colors');
				if (health != null && health.length >= 3)
					return FlxColor.fromRGB(Std.int(health[0]), Std.int(health[1]), Std.int(health[2]));
			}
		}
		catch (_:Dynamic) {}
		return null;
	}

	/** Read only the chart header for player2; parsing full note arrays froze week changes. */
	function readChartOpponent(folder:String, chartName:String):String
	{
		var path:String = Paths.json(Paths.formatToSongPath(folder) + '/' + Paths.formatToSongPath(chartName));
		var header:String = null;
		#if sys
		try
		{
			if (sys.FileSystem.exists(path))
			{
				var input:sys.io.FileInput = sys.io.File.read(path, false);
				var fileLength:Int = Std.int(sys.FileSystem.stat(path).size);
				var first:Bytes = input.read(Std.int(Math.min(65536, fileLength)));
				var headerText:String = first.toString();
				if (fileLength > 65536)
				{
					input.seek(Std.int(Math.max(0, fileLength - 65536)), sys.io.FileSeek.SeekBegin);
					headerText += input.read(65536).toString();
				}
				input.close();
				header = headerText;
			}
		}
		catch (_:Dynamic) {}
		#end
		if (header == null)
		{
			try header = openfl.utils.Assets.getText(path) catch (_:Dynamic) {}
		}
		if (header == null) return null;
		var player2:EReg = new EReg('"player2"\\s*:\\s*"([^"]+)"', '');
		return player2.match(header) ? player2.matched(1) : null;
	}

	function positionWeekDescription():Void
	{
		txtWeekTitle.x = 0;
		txtWeekTitle.y = 720;
		txtWeekTitle.fieldWidth = 1280;
		txtWeekTitle.fieldHeight = 240;
	}

	function makeOverflowFade(horizontal:Bool):FlxSprite
	{
		var width:Int = horizontal ? Std.int(Math.max(1, FlxG.width - 1280)) : 1280;
		var height:Int = horizontal ? FlxG.height : Std.int(Math.max(1, FlxG.height - 720));
		var fade:FlxSprite = new FlxSprite(horizontal ? 1280 : 0, horizontal ? 0 : 720);
		var rampLength:Int = horizontal ? width : height;
		fade.makeGraphic(horizontal ? rampLength : 1, horizontal ? 1 : rampLength, FlxColor.TRANSPARENT, true);
		var maxAlpha:Int = 190;
		for (distance in 0...rampLength)
		{
			var amount:Float = rampLength <= 1 ? 1 : distance / (rampLength - 1);
			amount = amount * amount * (3 - 2 * amount);
			var alpha:Int = Math.round(amount * maxAlpha);
			fade.pixels.setPixel32(horizontal ? distance : 0, horizontal ? 0 : distance, FlxColor.fromRGB(0, 0, 0, alpha));
		}
		fade.setGraphicSize(width, height);
		fade.updateHitbox();
		fade.antialiasing = true;
		fade.scrollFactor.set();
		return fade;
	}
}
