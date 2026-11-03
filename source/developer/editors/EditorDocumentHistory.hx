package developer.editors;

import flixel.FlxG;
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import general.backend.Paths;
import general.backend.language.Language;
import substates.Prompt;

/** Plain document data; it can survive switching between the two Week views. */
class EditorDocumentTimeline
{
	public var snapshots:Array<String> = [];
	public var labels:Array<String> = [];
	public var index:Int = 0;
	public var saved:String;
	public var pendingSave:String;
	public function new() {}
}

/** Shared document history and save indicator for the smaller editors. */
class EditorDocumentHistory extends FlxSpriteGroup
{
	public var timeline:EditorDocumentTimeline;
	public var canCapture:Void->Bool = () -> true;
	public var onDirtyChanged:Bool->Void;
	public var onSave:Void->Void;
	public var panel:ChartEditorHistoryPanel;
	var read:Void->String;
	var restore:String->Void;
	var busy:Void->Bool;
	var status:FlxText;
	var header:EditorHistoryHeaderControls;
	var elapsedCapture:Float = 0;
	var lastCommit:Float = 0;
	var lastGrouping:Bool = false;
	var restoring:Bool = false;
	var lastDirty:Bool = false;
	static inline var LIMIT:Int = 100;

	public function new(read:Void->String, restore:String->Void, busy:Void->Bool, ?camera:FlxCamera, ?timeline:EditorDocumentTimeline)
	{
		super();
		this.read = read;
		this.restore = restore;
		this.busy = busy;
		this.timeline = timeline == null ? new EditorDocumentTimeline() : timeline;
		scrollFactor.set();
		status = makeText(EditorInputStyle.si(12), FlxG.height - EditorInputStyle.si(26), EditorInputStyle.si(132));
		panel = new ChartEditorHistoryPanel();
		panel.x = FlxG.width - EditorInputStyle.si(332);
		panel.y = EditorInputStyle.si(70);
		add(panel);
		panel.visible = false;
		panel.setCallbacks(jump, undo, redo, () -> panel.visible = false);
		header = new EditorHistoryHeaderControls([undo, redo, function() {
			capture(); panel.visible = !panel.visible; refresh();
		}], [() -> canCapture() && this.timeline.index > 0,
			() -> canCapture() && this.timeline.index < this.timeline.snapshots.length - 1, () -> canCapture()]);
		add(header);
		if (camera != null) cameras = [camera];
		if (this.timeline.snapshots.length == 0) resetTimeline();
		else refresh();
	}

	function makeText(x:Float, y:Float, width:Float):FlxText
	{
		var text = new EditorText(x, y + EditorInputStyle.si(5), width, '', 12);
		text.setFormat(Paths.font(EditorInputStyle.langFontFileName()), 12, 0xFFD5D9E2);
		text.scrollFactor.set();
		add(text);
		return text;
	}

	static function tr(key:String):String return Language.get(key, 'editors');

	/** Field order is not stable after JSON parsing on every target. */
	public static function jsonSnapshot(value:Dynamic):String
	{
		if (value == null || Std.isOfType(value, String) || Std.isOfType(value, Bool)
			|| Std.isOfType(value, Int) || Std.isOfType(value, Float)) return haxe.Json.stringify(value);
		if (Std.isOfType(value, Array))
			return '[' + [for (item in (cast value:Array<Dynamic>)) jsonSnapshot(item)].join(',') + ']';
		var fields = Reflect.fields(value);
		fields.sort(Reflect.compare);
		return '{' + [for (field in fields) haxe.Json.stringify(field) + ':' + jsonSnapshot(Reflect.field(value, field))].join(',') + '}';
	}

	public static function inputFocused(widgets:Array<Dynamic>, ?menu:Dynamic):Bool
	{
		if (menu != null && menu.isInputOverlayActive()) return true;
		for (w in widgets)
			if (w != null && Reflect.getProperty(w, 'hasFocus') == true) return true;
		return false;
	}

	public function resetTimeline():Void
	{
		var snapshot = read();
		timeline.snapshots = [snapshot];
		timeline.labels = [tr('history_opened')];
		timeline.index = 0;
		timeline.saved = snapshot;
		timeline.pendingSave = null;
		lastCommit = 0;
		lastGrouping = false;
		refresh();
	}

	public function capture(?label:String, ?grouping:Bool = false):Void
	{
		if (restoring || !canCapture()) return;
		var snapshot = read();
		if (snapshot == timeline.snapshots[timeline.index])
		{
			if (!grouping) lastGrouping = false;
			return;
		}
		var branched = timeline.index < timeline.snapshots.length - 1;
		if (branched)
		{
			timeline.snapshots = timeline.snapshots.slice(0, timeline.index + 1);
			timeline.labels = timeline.labels.slice(0, timeline.index + 1);
		}
		var now = haxe.Timer.stamp();
		if (!branched && grouping && lastGrouping && timeline.index > 0 && now - lastCommit < 0.6)
			timeline.snapshots[timeline.index] = snapshot;
		else
		{
			timeline.snapshots.push(snapshot);
			timeline.labels.push(label == null ? tr('history_changed') : label);
			timeline.index = timeline.snapshots.length - 1;
		}
		lastCommit = now;
		lastGrouping = grouping;
		while (timeline.snapshots.length > LIMIT)
		{
			timeline.snapshots.shift();
			timeline.labels.shift();
			timeline.index--;
		}
		refresh();
	}

	public function hasChanges():Bool
	{
		capture();
		return timeline.snapshots[timeline.index] != timeline.saved;
	}

	public function prepareSave():Void
	{
		capture();
		timeline.pendingSave = read();
	}

	public function markSaved():Void
	{
		timeline.saved = timeline.pendingSave == null ? read() : timeline.pendingSave;
		timeline.pendingSave = null;
		lastGrouping = false;
		lastCommit = 0;
		refresh();
	}

	public function confirmDiscard(action:Void->Void, ?cancel:Void->Void):Void
	{
		if (!hasChanges()) action();
		else FlxG.state.openSubState(new Prompt(tr('history_discard'), 0, action, cancel, false));
	}

	public function undo():Void
	{
		capture();
		if (timeline.index > 0) jump(timeline.index - 1);
	}

	public function redo():Void
	{
		capture();
		if (timeline.index < timeline.snapshots.length - 1) jump(timeline.index + 1);
	}

	public function jump(index:Int):Void
	{
		capture();
		if (!canCapture() || index < 0 || index >= timeline.snapshots.length) return;
		restoring = true;
		try restore(timeline.snapshots[index]) catch (error:Dynamic)
		{
			restoring = false;
			trace('[EditorHistory] restore failed: $error');
			return;
		}
		timeline.index = index;
		restoring = false;
		lastGrouping = false;
		lastCommit = 0;
		refresh();
		trace('[EditorHistory] ' + Type.getClassName(Type.getClass(FlxG.state)) + ' restored ' + index);
	}

	function refresh():Void
	{
		if (panel != null)
			panel.setEntries([for (i in 0...timeline.labels.length) (i + 1) + '. ' + timeline.labels[i]], timeline.index);
		var dirty = timeline.snapshots[timeline.index] != timeline.saved;
		status.text = dirty ? tr('history_unsaved') : tr('history_saved');
		status.color = dirty ? 0xFFFFC66D : 0xFF9ACDA3;
		if (onDirtyChanged != null) onDirtyChanged(dirty);
		lastDirty = dirty;
	}

	public function blocksInput():Bool
	{
		return panel.visible || EditorPointer.justPressed(cameras[0], containsPoint) != null || (FlxG.keys.pressed.CONTROL
			&& (FlxG.keys.justPressed.Z || FlxG.keys.justPressed.Y || FlxG.keys.justPressed.H || FlxG.keys.justPressed.S));
	}

	public function containsPoint(x:Float, y:Float):Bool
		return panel.containsScreenPoint(x, y) || header.containsPoint(x, y);

	override public function update(elapsed:Float):Void
	{
		elapsedCapture += elapsed;
		if (canCapture() && FlxG.state.subState == null)
		{
			if (elapsedCapture >= 0.12)
			{
				capture(null, busy() || FlxG.mouse.pressed || FlxG.keys.anyPressed([LEFT, RIGHT, UP, DOWN]));
				elapsedCapture = 0;
			}
			if (!busy())
			{
				if (panel.visible && FlxG.keys.justPressed.ESCAPE) panel.visible = false;
				else if (FlxG.keys.pressed.CONTROL)
				{
					if (FlxG.keys.justPressed.Z) { if (FlxG.keys.pressed.SHIFT) redo(); else undo(); }
					else if (FlxG.keys.justPressed.Y) redo();
					else if (FlxG.keys.justPressed.H) { capture(); panel.visible = !panel.visible; refresh(); }
					else if (FlxG.keys.justPressed.S && onSave != null) onSave();
				}
			}
		}
		super.update(elapsed);
	}

	override public function destroy():Void
	{
		read = null;
		restore = null;
		busy = null;
		onDirtyChanged = null;
		onSave = null;
		canCapture = null;
		super.destroy();
	}
}
