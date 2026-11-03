package developer.editors;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import general.backend.Paths;
import general.backend.language.Language;

/** Floating history window shared by the editors. Drag its header to move it. */
class ChartEditorHistoryPanel extends FlxSpriteGroup
{
	static inline var MAX_VISIBLE_ROWS:Int = 12;
	static inline var BASE_WIDTH:Int = 320;
	static inline var BASE_ROW_HEIGHT:Int = 25;

	var panelWidth:Int;
	var rowHeight:Int;
	var headerHeight:Int;
	var footerHeight:Int;
	var background:FlxSprite;
	var header:FlxSprite;
	var title:FlxText;
	var closeText:FlxText;
	var undoText:FlxText;
	var redoText:FlxText;
	var rowBgs:Array<FlxSprite> = [];
	var rowTexts:Array<FlxText> = [];
	var entries:Array<String> = [];
	var selectedIndex:Int = 0;
	var scrollOffset:Int = 0;
	var onSelect:Int->Void;
	var onUndo:Void->Void;
	var onRedo:Void->Void;
	var onClose:Void->Void;
	var dragPointer:Int = -2;
	var dragX:Float;
	var dragY:Float;
	var listPointer:Int = -2;
	var listStartY:Float;
	var listStartOffset:Int;
	var listRow:Int;
	var listScrolled:Bool = false;
	var wasShown:Bool = false;

	public function new()
	{
		super();
		panelWidth = EditorInputStyle.si(BASE_WIDTH);
		rowHeight = EditorInputStyle.si(BASE_ROW_HEIGHT);
		headerHeight = EditorInputStyle.si(38);
		footerHeight = EditorInputStyle.si(38);
		scrollFactor.set();
		visible = false;

		var panelHeight:Int = headerHeight + MAX_VISIBLE_ROWS * rowHeight + footerHeight;
		background = new FlxSprite().makeGraphic(panelWidth, panelHeight, 0xFF171A22);
		background.scrollFactor.set();
		add(background);

		header = new FlxSprite().makeGraphic(panelWidth, headerHeight, 0xFF252A36);
		header.scrollFactor.set();
		add(header);

		title = makeText(10, 0, panelWidth - 70, 16, 0xFFF1F3F8);
		title.text = Language.get('history_title', 'charting');
		title.y = (headerHeight - title.height) / 2;
		add(title);

		closeText = makeText(panelWidth - 28, 0, 20, 16, 0xFFB8C0CF);
		closeText.text = '×';
		closeText.y = (headerHeight - closeText.height) / 2;
		add(closeText);

		for (i in 0...MAX_VISIBLE_ROWS)
		{
			var rowBg = new FlxSprite(0, headerHeight + i * rowHeight).makeGraphic(panelWidth, rowHeight, 0xFFFFFFFF);
			rowBg.scrollFactor.set();
			add(rowBg);
			rowBgs.push(rowBg);

			var rowText = makeText(10, headerHeight + i * rowHeight + EditorInputStyle.si(4), panelWidth - 20, 14, 0xFFD5D9E2);
			add(rowText);
			rowTexts.push(rowText);
		}

		var footerY:Int = headerHeight + MAX_VISIBLE_ROWS * rowHeight;
		var footerBg = new FlxSprite(0, footerY).makeGraphic(panelWidth, footerHeight, 0xFF20242E);
		footerBg.scrollFactor.set();
		add(footerBg);

		undoText = makeText(12, footerY + EditorInputStyle.si(10), panelWidth / 2 - 16, 14, 0xFFB9D7F3);
		undoText.text = Language.get('history_undo', 'charting');
		add(undoText);
		redoText = makeText(panelWidth / 2, footerY + EditorInputStyle.si(10), panelWidth / 2 - 12, 14, 0xFFB9D7F3);
		redoText.text = Language.get('history_redo', 'charting');
		add(redoText);
	}

	function makeText(x:Float, y:Float, width:Float, size:Int, color:FlxColor):FlxText
	{
		var text = new EditorText(x, y, width, '', size);
		text.setFormat(Paths.font(ChartEditorMenuBar.langFont()), size, color, LEFT);
		text.scrollFactor.set();
		text.borderStyle = NONE;
		return text;
	}

	public function setCallbacks(select:Int->Void, undo:Void->Void, redo:Void->Void, close:Void->Void):Void
	{
		onSelect = select;
		onUndo = undo;
		onRedo = redo;
		onClose = close;
	}

	public function setEntries(labels:Array<String>, currentIndex:Int):Void
	{
		entries = labels == null ? [] : labels.copy();
		scrollOffset = Std.int(FlxMath.bound(scrollOffset, 0, Math.max(0, entries.length - MAX_VISIBLE_ROWS)));
		selectedIndex = entries.length == 0 ? 0 : Std.int(FlxMath.bound(currentIndex, 0, entries.length - 1));
		if (selectedIndex < scrollOffset)
			scrollOffset = selectedIndex;
		else if (selectedIndex >= scrollOffset + MAX_VISIBLE_ROWS)
			scrollOffset = selectedIndex - MAX_VISIBLE_ROWS + 1;
		refreshRows();
	}

	function refreshRows():Void
	{
		for (i in 0...MAX_VISIBLE_ROWS)
		{
			var entryIndex = scrollOffset + i;
			var visibleRow = entryIndex < entries.length;
			rowBgs[i].visible = visibleRow;
			rowTexts[i].visible = visibleRow;
			if (!visibleRow) continue;
			rowBgs[i].color = entryIndex == selectedIndex ? 0xFF315477 : 0xFF171A22;
			rowTexts[i].text = entries[entryIndex];
			rowTexts[i].alpha = entryIndex == selectedIndex ? 1 : 0.78;
		}
		undoText.alpha = selectedIndex > 0 ? 1 : 0.4;
		redoText.alpha = selectedIndex < entries.length - 1 ? 1 : 0.4;
	}

	public function containsScreenPoint(px:Float, py:Float):Bool
	{
		return visible && px >= x && px <= x + panelWidth && py >= y && py <= y + background.height;
	}

	override function update(elapsed:Float):Void
	{
		if (!visible)
		{
			wasShown = false;
			dragPointer = -2;
			listPointer = -2;
			super.update(elapsed);
			return;
		}
		if (!wasShown)
		{
			refreshRows();
			wasShown = true;
		}
		if (listPointer != -2)
		{
			var point = EditorPointer.held(cameras[0], listPointer);
			if (point == null)
			{
				listPointer = -2;
				if (!listScrolled && listRow >= 0 && listRow < entries.length && onSelect != null) onSelect(listRow);
			}
			else if (Math.abs(point.y - listStartY) > EditorInputStyle.si(6))
			{
				listScrolled = true;
				scrollOffset = Std.int(FlxMath.bound(listStartOffset + Math.round((listStartY - point.y) / rowHeight), 0,
					Math.max(0, entries.length - MAX_VISIBLE_ROWS)));
				refreshRows();
			}
		}
		if (dragPointer != -2)
		{
			var point = EditorPointer.held(cameras[0], dragPointer);
			if (point == null)
			{
				dragPointer = -2;
				trace('[EditorHistoryPanel] moved to ' + x + ',' + y);
			}
			else
			{
				x = FlxMath.bound(point.x - dragX, 0, Math.max(0, FlxG.width - panelWidth));
				y = FlxMath.bound(point.y - dragY, EditorInputStyle.si(40), Math.max(EditorInputStyle.si(40), FlxG.height - background.height));
			}
		}

		var pointer = FlxG.mouse.getViewPosition(cameras[0]);
		var px = pointer.x;
		var py = pointer.y;
		pointer.put();
		if (containsScreenPoint(px, py) && FlxG.mouse.wheel != 0)
		{
			scrollOffset = Std.int(FlxMath.bound(scrollOffset - FlxG.mouse.wheel, 0, Math.max(0, entries.length - MAX_VISIBLE_ROWS)));
			refreshRows();
		}

		var pressed = EditorPointer.justPressed(cameras[0], containsScreenPoint);
		if (pressed != null)
		{
			px = pressed.x;
			py = pressed.y;
			if (px >= x && px <= x + panelWidth && py >= y && py <= y + headerHeight)
			{
				if (px >= x + panelWidth - EditorInputStyle.si(34))
				{
					if (onClose != null) onClose();
				}
				else
				{
					dragPointer = pressed.id;
					dragX = px - x;
					dragY = py - y;
				}
			}
			else
			{
				var footerY = y + headerHeight + MAX_VISIBLE_ROWS * rowHeight;
				if (py >= footerY && py <= footerY + footerHeight)
				{
					if (px < x + panelWidth / 2 && selectedIndex > 0 && onUndo != null) onUndo();
					else if (px >= x + panelWidth / 2 && selectedIndex < entries.length - 1 && onRedo != null) onRedo();
				}
				else if (py >= y + headerHeight && py < footerY)
				{
					var row = Std.int((py - y - headerHeight) / rowHeight);
					var entryIndex = scrollOffset + row;
					if (pressed.id != -1)
					{
						listPointer = pressed.id;
						listStartY = py;
						listStartOffset = scrollOffset;
						listRow = entryIndex;
						listScrolled = false;
					}
					else if (entryIndex >= 0 && entryIndex < entries.length && onSelect != null) onSelect(entryIndex);
				}
			}
		}

		super.update(elapsed);
	}
}
