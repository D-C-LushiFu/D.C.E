package developer.editors;

/** Validation shared by editor controls; invalid intermediate input leaves existing data intact. */
class EditorInputValidation
{
	public static function parseJsonObject(text:String):Dynamic
	{
		if (text == null) return null;
		try
		{
			var value:Dynamic = haxe.Json.parse(text);
			return switch (Type.typeof(value)) { case TObject: value; default: null; };
		}
		catch (error:Dynamic) { return null; }
	}

	public static function parseNumber(text:String):Null<Float>
	{
		if (text == null) return null;
		text = StringTools.trim(text);
		if (!~/^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$/.match(text)) return null;
		var value:Float = Std.parseFloat(text);
		return Math.isFinite(value) ? value : null;
	}

	public static function rgbChannels(text:String):Null<Array<Int>>
	{
		if (text == null) return null;
		var parts = text.split(',');
		if (parts.length != 3) return null;
		var result:Array<Int> = [];
		for (part in parts)
		{
			var value = parseNumber(part);
			if (value == null || Math.floor(value) != value) return null;
			result.push(Std.int(Math.max(0, Math.min(255, value))));
		}
		return result;
	}

	public static function objectArray(value:Dynamic):Bool
	{
		if (!Std.isOfType(value, Array)) return false;
		var items:Array<Dynamic> = cast value;
		for (item in items) if (Type.typeof(item) != TObject) return false;
		return true;
	}

	public static function finiteNumber(value:Dynamic):Bool
	{
		return Std.isOfType(value, Float) && Math.isFinite(cast value);
	}

	public static function weekDocument(value:Dynamic):Bool
	{
		if (value == null || !Std.isOfType(value.weekName, String) || !Std.isOfType(value.weekCharacters, Array)
			|| value.weekCharacters.length < 3 || !Std.isOfType(value.songs, Array) || value.songs.length == 0) return false;
		for (field in ['storyName', 'weekBackground', 'weekBefore', 'difficulties'])
			if (Reflect.field(value, field) != null && !Std.isOfType(Reflect.field(value, field), String)) return false;
		for (field in ['startUnlocked', 'hiddenUntilUnlocked', 'hideStoryMode', 'hideFreeplay'])
			if (Reflect.field(value, field) != null && !Std.isOfType(Reflect.field(value, field), Bool)) return false;
		for (character in (cast value.weekCharacters:Array<Dynamic>))
			if (!Std.isOfType(character, String)) return false;
		for (entry in (cast value.songs:Array<Dynamic>))
		{
			if (!Std.isOfType(entry, Array)) return false;
			var song:Array<Dynamic> = cast entry;
			if (song.length < 2 || !Std.isOfType(song[0], String) || !Std.isOfType(song[1], String)) return false;
			if (song[2] == null) song[2] = [146, 113, 253];
			if (!Std.isOfType(song[2], Array) || song[2].length < 3) return false;
			for (channel in (cast song[2]:Array<Dynamic>))
				if (!finiteNumber(channel) || channel < 0 || channel > 255) return false;
			if (song.length > 3 && song[3] != null && !Std.isOfType(song[3], String)) return false;
			if (song.length > 4 && song[4] != null)
			{
				if (!Std.isOfType(song[4], Array) || song[4].length < 3) return false;
				for (author in (cast song[4]:Array<Dynamic>)) if (!Std.isOfType(author, String)) return false;
			}
		}
		return true;
	}

	public static function numberPair(value:Dynamic):Bool
	{
		if (!Std.isOfType(value, Array)) return false;
		var items:Array<Dynamic> = cast value;
		return items.length >= 2 && finiteNumber(items[0]) && finiteNumber(items[1]);
	}

	public static function splashPath(text:String):Null<String>
	{
		if (text == null) return null;
		text = StringTools.replace(StringTools.trim(text), '\\', '/');
		if (text.length == 0 || text.length > 1024 || StringTools.startsWith(text, '/') || ~/[<>:"|?*\x00-\x1F]/.match(text)) return null;
		for (part in text.split('/')) if (part == '..' || part == '.' || part.length == 0) return null;
		return text;
	}

	public static function frameIndices(text:String):Null<Array<Int>>
	{
		if (text == null) return null;
		if (StringTools.trim(text).length == 0) return [];
		var result:Array<Int> = [];
		for (part in text.split(','))
		{
			part = StringTools.trim(part);
			if (!~/^[0-9]+$/.match(part)) return null;
			var value:Float = Std.parseFloat(part);
			if (!Math.isFinite(value) || value > 2147483647) return null;
			result.push(Std.int(value));
		}
		return result;
	}
}
