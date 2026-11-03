package developer.editors;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.math.FlxMath;
import flixel.util.FlxColor;
import general.backend.MusicBeatState;
import general.backend.Paths;
import general.backend.language.Language;
import general.backend.Mods;
import games.PlayState;
import games.backend.Song;
import games.backend.StageData;
import games.backend.WeekData;
import states.loadingState.LoadingState;
import sys.io.File;
import sys.FileSystem;

/** Opens an in-app browser of this mod's songs, then starts the selected chart for the camera preview. */
class CameraEditorLaunchState extends MusicBeatState
{
	static inline var MAX_CHART_BYTES:Int = 32 * 1024 * 1024;
	static inline var MAX_CHARTS_PER_SONG:Int = 256;
	static inline var MAX_CATALOG_SONGS:Int = 10000;
	static inline var MAX_VISIBLE_ROWS:Int = 12;
	static inline var ROW_HEIGHT:Int = 42;

	var menuBar:CameraEditorPickerMenuBar;
	var pageTitle:FlxText;
	var pageSubtitle:FlxText;
	var emptyMessage:FlxText;
	var songNames:Array<String> = [];
	var songFolders:Array<String> = [];
	var songChartCounts:Array<Int> = [];
	var chartPaths:Array<String> = [];
	var chartLabels:Array<String> = [];
	var rowBgs:Array<FlxSprite> = [];
	var rows:Array<FlxText> = [];
	var selectedIndex:Int = 0;
	var firstVisible:Int = 0;
	var visibleRows:Int = MAX_VISIBLE_ROWS;
	var listMode:String = 'songs';
	var selectedSongIndex:Int = -1;
	var listBg:FlxSprite;
	var detailBg:FlxSprite;
	var detailAccent:FlxSprite;
	var detailEyebrow:FlxText;
	var detailTitle:FlxText;
	var detailBody:FlxText;
	var detailMeta:FlxText;
	var openButtonBg:FlxSprite;
	var openButtonText:FlxText;
	var backButtonBg:FlxSprite;
	var backButtonText:FlxText;
	var selectedMod:String = '';
	var catalogError:String = null;
	var dragListActive:Bool = false;
	var dragListStartY:Float = 0;
	var dragListStartFirstVisible:Int = 0;
	var dragListMoved:Bool = false;
	var pressedRow:Int = -1;
	var pressedAction:String = '';

	override function create():Void
	{
		super.create();
		FlxG.camera.bgColor = 0xFF12141A;
		FlxG.mouse.visible = true;

		menuBar = new CameraEditorPickerMenuBar();
		menuBar.scrollFactor.set();
		menuBar.onAction = function(action:String)
		{
			if (action == 'back') returnToEditorMenu();
		};
		add(menuBar);

		var titleSize = EditorInputStyle.si(26);
		var subtitleSize = EditorInputStyle.si(14);
		pageTitle = new FlxText(EditorInputStyle.si(42), EditorInputStyle.si(62), FlxG.width - EditorInputStyle.si(84),
			Language.get('cameraEditorSongBrowserTitle', 'editors'), titleSize);
		pageTitle.setFormat(Paths.font(EditorInputStyle.langFontFileName()), titleSize, 0xFFF2F3F5, LEFT);
		pageTitle.scrollFactor.set();
		add(pageTitle);

		pageSubtitle = new FlxText(pageTitle.x, pageTitle.y + titleSize + EditorInputStyle.si(4), pageTitle.fieldWidth,
			'', subtitleSize);
		pageSubtitle.setFormat(Paths.font(EditorInputStyle.langFontFileName()), subtitleSize, 0xFF9CA3AF, LEFT);
		pageSubtitle.scrollFactor.set();
		add(pageSubtitle);

		// Freeplay-inspired split layout with a stable selected-item panel.
		detailBg = new FlxSprite();
		detailBg.scrollFactor.set();
		add(detailBg);
		detailAccent = new FlxSprite();
		detailAccent.scrollFactor.set();
		add(detailAccent);
		detailEyebrow = new FlxText(0, 0, 0, '', EditorInputStyle.si(11));
		detailEyebrow.setFormat(Paths.font(EditorInputStyle.langFontFileName()), EditorInputStyle.si(11), 0xFFC8C3E8, LEFT);
		detailEyebrow.scrollFactor.set();
		add(detailEyebrow);
		detailTitle = new FlxText(0, 0, 0, '', EditorInputStyle.si(25));
		detailTitle.setFormat(Paths.font(EditorInputStyle.langFontFileName()), EditorInputStyle.si(25), 0xFFF4F0FF, LEFT);
		detailTitle.scrollFactor.set();
		add(detailTitle);
		detailBody = new FlxText(0, 0, 0, '', EditorInputStyle.si(15));
		detailBody.setFormat(Paths.font(EditorInputStyle.langFontFileName()), EditorInputStyle.si(15), 0xFFB7BEC9, LEFT);
		detailBody.scrollFactor.set();
		add(detailBody);
		detailMeta = new FlxText(0, 0, 0, '', EditorInputStyle.si(13));
		detailMeta.setFormat(Paths.font(EditorInputStyle.langFontFileName()), EditorInputStyle.si(13), 0xFFD7D0FF, LEFT);
		detailMeta.scrollFactor.set();
		add(detailMeta);

		emptyMessage = new FlxText(pageTitle.x, pageSubtitle.y + EditorInputStyle.si(50), pageTitle.fieldWidth, '', EditorInputStyle.si(16));
		emptyMessage.setFormat(Paths.font(EditorInputStyle.langFontFileName()), EditorInputStyle.si(16), 0xFFC9CDD4, CENTER);
		emptyMessage.scrollFactor.set();
		emptyMessage.visible = false;
		add(emptyMessage);

		var status:CameraEditorStatusBar = cast menuBar.statusBar;
		status.setStage(selectedMod.length == 0 ? Language.get('cameraEditorNoMod', 'editors') : selectedMod);
		status.setDirectory(Language.get('cameraEditorSongList', 'cameraEditor'));
		status.setObject('0');
		status.setPos('—');
		status.setZoom('100%');
		loadModSongs();
		showSongList();
	}

	function loadModSongs():Void
	{
		try
		{
			selectedMod = Mods.currentModDirectory == null ? '' : Mods.currentModDirectory;
			WeekData.reloadWeekFiles(false);
			songNames = [];
			songFolders = [];
			songChartCounts = [];
			var seen:Map<String, Bool> = new Map();
			for (weekName in WeekData.weeksList)
			{
				var week = WeekData.weeksLoaded.get(weekName);
				if (week == null || week.songs == null) continue;
				var folder = week.folder == null ? '' : week.folder;
				if (folder != selectedMod) continue;
				for (entry in week.songs)
				{
					if (entry == null || !Std.isOfType(entry, Array) || entry.length < 1 || entry[0] == null) continue;
					var name = Std.string(entry[0]).trim();
					if (name.length == 0) continue;
					var songId = Paths.formatToSongPath(name);
					if (songId.length == 0) continue;
					var key = folder + '/' + songId.toLowerCase();
					if (seen.exists(key)) continue;
					var chartFolder = Paths.modCachePath(folder, 'data/' + songId);
					if (!FileSystem.exists(chartFolder) || !FileSystem.isDirectory(chartFolder)) continue;
					var chartCount = countCharts(chartFolder);
					if (chartCount == 0) continue;
					seen.set(key, true);
					songNames.push(name);
					songFolders.push(chartFolder);
					songChartCounts.push(chartCount);
					if (songNames.length >= MAX_CATALOG_SONGS) return;
				}
			}

			// Include chart folders that are present in the mod but are not referenced by a week file.
			var dataRoot = Paths.modCachePath(selectedMod, 'data');
			if (FileSystem.exists(dataRoot) && FileSystem.isDirectory(dataRoot))
			{
				var extraFolders = FileSystem.readDirectory(dataRoot);
				extraFolders.sort(compareNamesAscending);
				for (folderName in extraFolders)
				{
					var chartFolder = dataRoot + (StringTools.endsWith(dataRoot, '/') || StringTools.endsWith(dataRoot, '\\') ? '' : '/') + folderName;
					if (!FileSystem.isDirectory(chartFolder)) continue;
					var chartCount = countCharts(chartFolder);
					if (chartCount == 0) continue;
					var key = selectedMod + '/' + Paths.formatToSongPath(folderName).toLowerCase();
					if (seen.exists(key)) continue;
					seen.set(key, true);
					songNames.push(folderName);
					songFolders.push(chartFolder);
					songChartCounts.push(chartCount);
					if (songNames.length >= MAX_CATALOG_SONGS) break;
				}
			}
		}
		catch (e:Dynamic)
		{
			catalogError = Std.string(e);
		}

		// Week order is the mod's intentional song order. Keep it intact; unlisted
		// folders are appended A→Z so an alphabetical post-sort cannot invert weeks.
	}

	static function compareNamesAscending(a:String, b:String):Int
	{
		var left = a == null ? '' : a.toLowerCase();
		var right = b == null ? '' : b.toLowerCase();
		if (left < right) return -1;
		if (left > right) return 1;
		if (a < b) return -1;
		if (a > b) return 1;
		return 0;
	}

	function countCharts(folder:String):Int
	{
		var count = 0;
		try
		{
			for (file in FileSystem.readDirectory(folder))
			{
				if (!isPlayableChartFile(file)) continue;
				var path = folder + (StringTools.endsWith(folder, '/') || StringTools.endsWith(folder, '\\') ? '' : '/') + file;
				if (!FileSystem.isDirectory(path) && ++count >= MAX_CHARTS_PER_SONG) break;
			}
		}
		catch (e:Dynamic) {}
		return count;
	}

	/** Camera event sidecar files share the song folder but are not chart difficulties. */
	static function isPlayableChartFile(fileName:String):Bool
	{
		var lower:String = fileName == null ? '' : fileName.toLowerCase();
		return StringTools.endsWith(lower, '.json')
			&& lower != 'cam.json'
			&& lower != 'events.json'
			&& lower != 'event.json'
			&& !StringTools.endsWith(lower, '-events.json')
			&& !StringTools.endsWith(lower, '-event.json')
			&& !StringTools.endsWith(lower, '-cam.json');
	}

	function showSongList():Void
	{
		clearList();
		listMode = 'songs';
		selectedIndex = 0;
		firstVisible = 0;
		pageTitle.text = Language.get('cameraEditorSongBrowserTitle', 'editors');
		pageSubtitle.text = Language.get('cameraEditorModSongCount', 'cameraEditor') + '  ' + selectedMod + '   •   '
			+ songNames.length + ' ' + Language.get('cameraEditorSongsCount', 'cameraEditor');
		var status:CameraEditorStatusBar = cast menuBar.statusBar;
		status.setStage(selectedMod.length == 0 ? Language.get('cameraEditorNoMod', 'cameraEditor') : selectedMod);
		status.setDirectory(Language.get('cameraEditorSongList', 'cameraEditor'));
		status.setObject(Std.string(songNames.length));
		if (songNames.length == 0)
		{
			if (detailBg != null) { detailBg.visible = false; detailAccent.visible = false; detailEyebrow.visible = false; detailTitle.visible = false; detailBody.visible = false; detailMeta.visible = false; }
			emptyMessage.text = Language.get('cameraEditorNoSongs', 'editors') + (catalogError == null ? '' : '\n' + catalogError);
			emptyMessage.visible = true;
			return;
		}
		emptyMessage.visible = false;
		buildList(songNames.length);
		buildActionButton(false, Language.get('cameraEditorOpenSong', 'editors'));
		layoutDetailPanel();
		refreshList();
	}

	function openSelectedSong():Void
	{
		if (selectedIndex < 0 || selectedIndex >= songNames.length) return;
		selectedSongIndex = selectedIndex;
		try
		{
			var folder = songFolders[selectedSongIndex];
			var names = FileSystem.readDirectory(folder);
			names.sort(compareNamesAscending);
			chartPaths = [];
			chartLabels = [];
			var baseName = Paths.formatToSongPath(songNames[selectedSongIndex]);
			for (name in names)
			{
				if (!isPlayableChartFile(name)) continue;
				var path = folder + (StringTools.endsWith(folder, '/') || StringTools.endsWith(folder, '\\') ? '' : '/') + name;
				if (FileSystem.isDirectory(path)) continue;
				chartPaths.push(path);
				chartLabels.push(difficultyLabel(name, baseName));
				if (chartPaths.length >= MAX_CHARTS_PER_SONG) break;
			}
			if (chartPaths.length == 0) throw 'No .json charts found for this song';
			showDifficultyList();
		}
		catch (e:Dynamic)
		{
			emptyMessage.text = Language.get('cameraEditorFolderReadFailed', 'editors') + '\n' + Std.string(e);
			emptyMessage.visible = true;
		}
	}

	function difficultyLabel(fileName:String, baseName:String):String
	{
		var label = fileName.substr(0, fileName.length - 5);
		if (label.toLowerCase() == baseName.toLowerCase()) return 'Normal';
		var prefix = baseName.toLowerCase() + '-';
		if (label.toLowerCase().indexOf(prefix) == 0) label = label.substr(baseName.length + 1);
		else
		{
			var dash = label.lastIndexOf('-');
			if (dash >= 0 && dash < label.length - 1) label = label.substr(dash + 1);
		}
		return label;
	}

	function showDifficultyList():Void
	{
		clearList();
		listMode = 'difficulties';
		selectedIndex = 0;
		firstVisible = 0;
		pageTitle.text = songNames[selectedSongIndex];
		pageSubtitle.text = Language.get('cameraEditorSelectDifficulty', 'editors') + '   •   '
			+ chartLabels.length + ' ' + Language.get('cameraEditorDifficultiesCount', 'cameraEditor');
		var status:CameraEditorStatusBar = cast menuBar.statusBar;
		status.setObject(Std.string(chartLabels.length));
		status.setDirectory(songNames[selectedSongIndex]);
		emptyMessage.visible = false;
		buildList(chartLabels.length);
		buildActionButton(true, Language.get('cameraEditorOpenDifficulty', 'editors'));
		layoutDetailPanel();
		refreshList();
	}

	function buildList(count:Int):Void
	{
		var gap = EditorInputStyle.si(24);
		var margin = EditorInputStyle.si(42);
		var usableWidth = FlxG.width - margin * 2;
		var width = Std.int(Math.min(EditorInputStyle.si(1120), usableWidth * 0.48));
		var detailWidth = Std.int(usableWidth - width - gap);
		var rowHeight = EditorInputStyle.si(ROW_HEIGHT + 12);
		var y = pageSubtitle.y + EditorInputStyle.si(42);
		var availableHeight = FlxG.height - y - EditorInputStyle.si(94);
		visibleRows = Std.int(FlxMath.bound(Math.floor(availableHeight / rowHeight), 1, MAX_VISIBLE_ROWS));
		var rowCount = Std.int(Math.min(visibleRows, Math.max(1, count)));
		var height = Std.int(Math.max(rowCount * rowHeight + EditorInputStyle.si(20), Math.min(availableHeight, EditorInputStyle.si(520))));
		var x = margin;
		listBg = new FlxSprite(x, y).makeGraphic(width, height, 0xFF171B24);
		listBg.scrollFactor.set();
		add(listBg);
		detailBg.setPosition(x + width + gap, y);
		detailBg.makeGraphic(detailWidth, height, 0xFF1A1E29);
		detailAccent.setPosition(detailBg.x, y);
		detailAccent.makeGraphic(EditorInputStyle.si(4), height, 0xFFB28AFF);
		detailEyebrow.setPosition(detailBg.x + EditorInputStyle.si(26), y + EditorInputStyle.si(32));
		detailEyebrow.fieldWidth = detailWidth - EditorInputStyle.si(52);
		detailTitle.setPosition(detailEyebrow.x, y + EditorInputStyle.si(68));
		detailTitle.fieldWidth = detailWidth - EditorInputStyle.si(48);
		detailBody.setPosition(detailEyebrow.x, y + EditorInputStyle.si(132));
		detailBody.fieldWidth = detailWidth - EditorInputStyle.si(54);
		detailBody.fieldHeight = Std.int(Math.max(EditorInputStyle.si(72), height - EditorInputStyle.si(270)));
		detailMeta.setPosition(detailEyebrow.x, y + height - EditorInputStyle.si(78));
		detailMeta.fieldWidth = detailWidth - EditorInputStyle.si(52);
		for (row in 0...visibleRows)
		{
			var rowY = y + EditorInputStyle.si(10) + row * rowHeight;
			var rowBg = new FlxSprite(x + EditorInputStyle.si(10), rowY).makeGraphic(width - EditorInputStyle.si(20), rowHeight - EditorInputStyle.si(5), 0xFF222733);
			rowBg.scrollFactor.set();
			rowBg.ID = row;
			rowBgs.push(rowBg);
			add(rowBg);
			var textSize = EditorInputStyle.si(15);
			var text = new FlxText(x + EditorInputStyle.si(24), rowY + EditorInputStyle.si(6), width - EditorInputStyle.si(170), '', textSize);
			text.setFormat(Paths.font(EditorInputStyle.langFontFileName()), textSize, 0xFFE5E7EB, LEFT);
			text.scrollFactor.set();
			text.ID = row;
			add(text);
			rows.push(text);

			var detail = new FlxText(x + width - EditorInputStyle.si(146), rowY + EditorInputStyle.si(7), EditorInputStyle.si(120), '', EditorInputStyle.si(12));
			detail.setFormat(Paths.font(EditorInputStyle.langFontFileName()), EditorInputStyle.si(12), 0xFF9CA3AF, RIGHT);
			detail.scrollFactor.set();
			detail.ID = row;
			rowDetails.push(detail);
			add(detail);
		}
	}

	function buildActionButton(showBack:Bool, label:String):Void
	{
		var width = EditorInputStyle.si(174);
		var height = EditorInputStyle.si(40);
		var y = listBg.y + listBg.height - height - EditorInputStyle.si(8);
		var right = detailBg.x + detailBg.width - EditorInputStyle.si(20);
		if (showBack)
		{
			var backWidth = EditorInputStyle.si(156);
			backButtonBg = new FlxSprite(detailBg.x + EditorInputStyle.si(20), y).makeGraphic(backWidth, height, 0xFF2A2E39);
			backButtonBg.scrollFactor.set();
			add(backButtonBg);
			backButtonText = buttonLabel(backButtonBg, Language.get('cameraEditorBackToSongs', 'editors'));
			add(backButtonText);
		}
		openButtonBg = new FlxSprite(right - width, y).makeGraphic(width, height, 0xFF6857E8);
		openButtonBg.scrollFactor.set();
		add(openButtonBg);
		openButtonText = buttonLabel(openButtonBg, label);
		add(openButtonText);
	}

	function layoutDetailPanel():Void
	{
		if (detailBg == null) return;
		var isSong = listMode == 'songs';
		var labels = isSong ? songNames : chartLabels;
		if (labels.length == 0) return;
		if (detailBg != null) { detailBg.visible = true; detailAccent.visible = true; detailEyebrow.visible = true; detailTitle.visible = true; detailBody.visible = true; detailMeta.visible = true; }
		var idx = Std.int(FlxMath.bound(selectedIndex, 0, labels.length - 1));
		detailEyebrow.text = isSong ? 'D.C.E.  /  FREEPLAY COLLECTION' : 'CAMERA EDITOR  /  DIFFICULTY';
		detailTitle.text = labels[idx];
		detailBody.text = isSong
			? '选择曲目文件夹后，再从该曲目的难度列表进入相机编辑器。\n\n当前模组：' + selectedMod
			: '选择要预览和编辑的谱面难度。\n\n曲目：' + songNames[selectedSongIndex];
		detailMeta.text = isSong
			? songChartCounts[idx] + '  ' + Language.get('cameraEditorDifficultiesCount', 'cameraEditor')
			: (idx + 1) + ' / ' + chartLabels.length + '    •    ' + Language.get('cameraEditorOpenDifficulty', 'editors');
	}

	function buttonLabel(bg:FlxSprite, label:String):FlxText
	{
		var size = EditorInputStyle.si(13);
		var text = new FlxText(bg.x + EditorInputStyle.si(6), bg.y + EditorInputStyle.si(8), bg.width - EditorInputStyle.si(12), label, size);
		text.setFormat(Paths.font(EditorInputStyle.langFontFileName()), size, FlxColor.WHITE, CENTER);
		text.scrollFactor.set();
		return text;
	}

	function refreshList():Void
	{
		var labels = listMode == 'songs' ? songNames : chartLabels;
		if (labels.length == 0) return;
		layoutDetailPanel();
		firstVisible = Std.int(FlxMath.bound(firstVisible, 0, Std.int(Math.max(0, labels.length - visibleRows))));
		for (row in 0...rows.length)
		{
			var idx = firstVisible + row;
			rows[row].visible = idx < labels.length;
			rowDetails[row].visible = idx < labels.length;
			rowBgs[row].visible = idx < labels.length;
			if (idx < labels.length)
			{
				rows[row].text = labels[idx];
				var detail = '';
				if (listMode == 'songs') detail = songChartCounts[idx] + ' ' + Language.get('cameraEditorDifficultiesCount', 'cameraEditor');
				else detail = Language.get('cameraEditorDifficultyIndex', 'cameraEditor') + ' ' + (idx + 1);
				rowDetails[row].text = detail;
				rowBgs[row].color = idx == selectedIndex ? 0xFF41405B : 0xFF222733;
				rows[row].color = idx == selectedIndex ? 0xFFF4F0FF : 0xFFE5E7EB;
				rowDetails[row].color = idx == selectedIndex ? 0xFFC4B5FD : 0xFF9CA3AF;
			}
		}
	}

	function keepSelectionVisible(labelsLength:Int):Void
	{
		if (selectedIndex < firstVisible) firstVisible = selectedIndex;
		else if (selectedIndex >= firstVisible + visibleRows) firstVisible = selectedIndex - visibleRows + 1;
		firstVisible = Std.int(FlxMath.bound(firstVisible, 0, Std.int(Math.max(0, labelsLength - visibleRows))));
	}

	function containsPoint(sprite:FlxSprite, x:Float, y:Float):Bool
	{
		return sprite != null && sprite.visible && x >= sprite.x && x <= sprite.x + sprite.width && y >= sprite.y && y <= sprite.y + sprite.height;
	}

	var rowDetails:Array<FlxText> = [];

	function clearList():Void
	{
		for (row in rows) { remove(row, true); row.destroy(); }
		rows = [];
		for (detail in rowDetails) { remove(detail, true); detail.destroy(); }
		rowDetails = [];
		for (rowBg in rowBgs) { remove(rowBg, true); rowBg.destroy(); }
		rowBgs = [];
		if (listBg != null) { remove(listBg, true); listBg.destroy(); listBg = null; }
		if (openButtonBg != null) { remove(openButtonBg, true); openButtonBg.destroy(); openButtonBg = null; }
		if (openButtonText != null) { remove(openButtonText, true); openButtonText.destroy(); openButtonText = null; }
		if (backButtonBg != null) { remove(backButtonBg, true); backButtonBg.destroy(); backButtonBg = null; }
		if (backButtonText != null) { remove(backButtonText, true); backButtonText.destroy(); backButtonText = null; }
	}

	function loadSelectedChart():Void
	{
		if (selectedIndex < 0 || selectedIndex >= chartPaths.length) return;
		PlayState.cameraEditorLoadStartedAt = haxe.Timer.stamp();
		var path = chartPaths[selectedIndex];
		try
		{
			if (!FileSystem.exists(path)) throw 'Selected chart no longer exists';
			var stat = FileSystem.stat(path);
			if (stat.size < 0 || stat.size > MAX_CHART_BYTES) throw 'Chart file exceeds the 32 MB safety limit';
			var song = Song.parseJSON(File.getContent(path), path);
			if (song == null || song.song == null || song.notes == null) throw 'Selected file is not a supported chart';

			clearList();
			Mods.currentModDirectory = selectedMod;
			Song.chartPath = path;
			Song.loadedSongName = song.song;
			PlayState.SONG = song;
			PlayState.isStoryMode = false;
			StageData.loadDirectory(song);
			PlayState.openCameraEditorOnCreate = true;
			PlayState.cameraEditorReturnToMenu = true;
			FlxG.mouse.visible = false;
			LoadingState.loadAndSwitchState(new PlayState(), true);
		}
		catch (e:Dynamic)
		{
			emptyMessage.text = Language.get('cameraEditorLoadFailed', 'editors') + '\n' + Std.string(e);
			emptyMessage.visible = true;
		}
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);
		var labels = listMode == 'songs' ? songNames : chartLabels;
		if (labels.length > 0)
		{
			if (FlxG.keys.justPressed.UP)
			{
				selectedIndex = Std.int(Math.max(0, selectedIndex - 1));
				keepSelectionVisible(labels.length);
			}
			if (FlxG.keys.justPressed.DOWN)
			{
				selectedIndex = Std.int(Math.min(labels.length - 1, selectedIndex + 1));
				keepSelectionVisible(labels.length);
			}
			var uiCamera = menuBar.uiCamera == null ? FlxG.camera : menuBar.uiCamera;
			var mousePoint = EditorPointer.position(uiCamera);
			var mouseX = mousePoint.x;
			var mouseY = mousePoint.y;
			var inList = containsPoint(listBg, mouseX, mouseY);
			if (EditorPointer.wheel() != 0 && inList)
				firstVisible = Std.int(FlxMath.bound(firstVisible - EditorPointer.wheel(), 0, Math.max(0, labels.length - visibleRows)));
			if (EditorPointer.justPressedNow())
			{
				dragListActive = inList;
				dragListMoved = false;
				dragListStartY = mouseY;
				dragListStartFirstVisible = firstVisible;
				pressedRow = -1;
				pressedAction = '';
				if (backButtonBg != null && containsPoint(backButtonBg, mouseX, mouseY)) pressedAction = 'back';
				else if (openButtonBg != null && containsPoint(openButtonBg, mouseX, mouseY)) pressedAction = 'open';
				else
					for (rowBg in rowBgs)
						if (rowBg.visible && containsPoint(rowBg, mouseX, mouseY))
						{
							pressedRow = firstVisible + rowBg.ID;
							break;
						}
			}
			if (dragListActive && EditorPointer.pressed())
			{
				var dragPoint = EditorPointer.position(uiCamera);
				var rowStep = Math.max(1, EditorInputStyle.si(ROW_HEIGHT + 12));
				var dy = dragPoint.y - dragListStartY;
				if (Math.abs(dy) > EditorInputStyle.si(8)) dragListMoved = true;
				firstVisible = Std.int(FlxMath.bound(dragListStartFirstVisible - Math.round(dy / rowStep), 0, Math.max(0, labels.length - visibleRows)));
			}
			if (EditorPointer.justReleased())
			{
				if (dragListMoved) pressedRow = -1;
				if (pressedRow >= 0) selectedIndex = Std.int(FlxMath.bound(pressedRow, 0, labels.length - 1));
				if (!dragListMoved && pressedAction == 'back' && backButtonBg != null && containsPoint(backButtonBg, mouseX, mouseY)) showSongList();
				else if (!dragListMoved && pressedAction == 'open' && openButtonBg != null && containsPoint(openButtonBg, mouseX, mouseY))
				{
					if (listMode == 'songs') openSelectedSong(); else loadSelectedChart();
				}
				dragListActive = false;
				pressedAction = '';
			}
			if (FlxG.keys.justPressed.ENTER)
			{
				if (listMode == 'songs') openSelectedSong(); else loadSelectedChart();
			}
			refreshList();
			var status:CameraEditorStatusBar = cast menuBar.statusBar;
			status.setPos((selectedIndex + 1) + ' / ' + labels.length);
		}
		if (FlxG.keys.justPressed.ESCAPE)
		{
			if (listMode == 'difficulties') showSongList();
			else returnToEditorMenu();
		}
	}

	function returnToEditorMenu():Void
	{
		PlayState.openCameraEditorOnCreate = false;
		PlayState.cameraEditorReturnToMenu = false;
		FlxG.mouse.visible = false;
		MusicBeatState.switchState(new MasterEditorMenu());
	}

	override function destroy():Void
	{
		clearList();
		super.destroy();
	}
}
