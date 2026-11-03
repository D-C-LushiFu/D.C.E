import developer.editors.EditorInputValidation;

class EditorInputValidationTest
{
	static var assertions:Int = 0;
	static function check(ok:Bool, message:String):Void
	{
		assertions++;
		if (!ok) throw message;
	}
	static function main():Void
	{
		for (input in ['', '{', '{"field":}', 'null', '[]', '"text"', 'false', '12'])
			check(EditorInputValidation.parseJsonObject(input) == null, 'Accepted invalid JSON document: ' + input);
		check(EditorInputValidation.parseJsonObject('{"text":"中文\\n<>&"}').text == '中文\n<>&', 'Preserve JSON text');
		check(!EditorInputValidation.objectArray([null]), 'Reject null array entries');
		check(!EditorInputValidation.objectArray(["animation"]), 'Reject string array entries');
		check(EditorInputValidation.objectArray([{name: "idle"}]), 'Accept object entries');
		check(!EditorInputValidation.numberPair([0]), 'Reject short positions');
		check(!EditorInputValidation.numberPair(["0", 2]), 'Reject string positions');
		check(!EditorInputValidation.numberPair([Math.POSITIVE_INFINITY, 2]), 'Reject infinite positions');
		check(EditorInputValidation.numberPair([0, -2.5]), 'Accept numeric positions');
		for (input in ['', ' ', '12abc', '1.2.3', '--2', 'NaN', 'Infinity', '-Infinity', '1e309', '0xFF', '1\n2'])
			check(EditorInputValidation.parseNumber(input) == null, 'Accepted invalid number: ' + input);
		var hugeDigits = StringTools.lpad('', '9', 10000);
		check(EditorInputValidation.parseNumber(hugeDigits) == null, 'Reject ten thousand digit overflow');
		check(EditorInputValidation.frameIndices(hugeDigits) == null, 'Reject huge frame index');
		check(EditorInputValidation.splashPath(StringTools.lpad('', 'a', 10000)) == null, 'Reject oversized resource path');
		for (character in ['<', '>', ':', '"', '|', '?', '*', '\t'])
			check(EditorInputValidation.splashPath('folder/bad' + character + 'name') == null, 'Accepted illegal path character');
		for (pair in [{input: '12', value: 12.0}, {input: ' -2.5 ', value: -2.5}, {input: '.05', value: 0.05},
			{input: '+1e2', value: 100.0}, {input: '0', value: 0.0}])
			check(EditorInputValidation.parseNumber(pair.input) == pair.value, 'Rejected valid number: ' + pair.input);
		for (input in ['', '../bad', 'folder/../bad', '/bad', 'C:/bad', 'bad:?', 'bad' + String.fromCharCode(0) + 'name', 'bad\nname', 'folder//bad'])
			check(EditorInputValidation.splashPath(input) == null, 'Accepted invalid path: ' + input);
		check(EditorInputValidation.splashPath(' noteSplashes/noteSplashes ') == 'noteSplashes/noteSplashes', 'Trim path');
		check(EditorInputValidation.splashPath('立绘/测试') == '立绘/测试', 'Preserve Unicode path');
		for (input in ['-1', '1abc', '0x10', '1,,2', '1.5', '2147483648', '999999999999999999999999'])
			check(EditorInputValidation.frameIndices(input) == null, 'Accepted invalid frame indices: ' + input);
		check(EditorInputValidation.frameIndices('').length == 0, 'Empty indices use animation prefix');
		check(EditorInputValidation.frameIndices('2').join(',') == '2', 'Single frame index must be preserved');
		check(EditorInputValidation.frameIndices('0, 2, 004').join(',') == '0,2,4', 'Multiple indices');
		for (input in ['12abc,0,0', '1,2', 'NaN,0,0', '1.5,2,3'])
			check(EditorInputValidation.rgbChannels(input) == null, 'Reject invalid RGB clipboard: ' + input);
		check(EditorInputValidation.rgbChannels('-999,260,0').join(',') == '0,255,0', 'Clamp RGB clipboard channels');
		check(EditorInputValidation.rgbChannels('1,2,3').join(',') == '1,2,3', 'Accept RGB clipboard channels');
		Sys.println('PASS ' + assertions + ' editor validation assertions');
	}
}
