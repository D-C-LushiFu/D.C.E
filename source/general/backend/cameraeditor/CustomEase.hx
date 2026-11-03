package general.backend.cameraeditor;

import flixel.tweens.FlxEase;

class CustomEase
{
	public static var SAMPLES:Int = 16;

	public static function defaultCurve():Array<Float>
	{
		var a:Array<Float> = [];
		for(i in 0...SAMPLES) a.push(i / (SAMPLES - 1));
		return a;
	}

	public static function encode(samples:Array<Float>):String
	{
		var parts:Array<String> = [];
		for(s in samples) parts.push(Std.string(Math.round(s * 1000) / 1000));
		return parts.join(',');
	}

	public static function decode(token:String):Array<Float>
	{
		var body:String = token.indexOf(':') >= 0 ? token.substring(token.indexOf(':') + 1) : token;
		var arr:Array<String> = body.split(',');
		var out:Array<Float> = [];
		for(p in arr)
		{
			var v:Float = Std.parseFloat(p);
			if(Math.isNaN(v)) v = 0;
			out.push(Math.max(0, Math.min(1, v)));
		}
		while(out.length < SAMPLES) out.push(out.length > 0 ? out[out.length - 1] : 0);
		while(out.length > SAMPLES) out.pop();
		return out;
	}

	public static function eval(samples:Array<Float>, t:Float):Float
	{
		if(samples == null || samples.length == 0) return t;
		if(t <= 0) return samples[0];
		if(t >= 1) return samples[samples.length - 1];
		var x:Float = t * (samples.length - 1);
		var i:Int = Math.floor(x);
		if(i >= samples.length - 1) return samples[samples.length - 1];
		var f:Float = x - i;
		return samples[i] + (samples[i + 1] - samples[i]) * f;
	}

	public static function isClassicToken(token:String):Bool
	{
		if(token == null) return false;
		for(p in token.split(','))
			if(StringTools.trim(p).toUpperCase() == 'CLASSIC') return true;
		return false;
	}

	public static function isInstantToken(token:String):Bool
	{
		if(token == null) return false;
		for(p in token.split(','))
			if(StringTools.trim(p).toUpperCase() == 'INSTANT') return true;
		return false;
	}

	public static function isSnapToken(token:String):Bool
	{
		if(token == null) return false;
		for(p in token.split(','))
		{
			var v:String = StringTools.trim(p).toUpperCase();
			if(v == 'INSTANT' || v == 'CLASSIC') return true;
		}
		return false;
	}

	public static function getEaseFn(token:String):Float->Float
	{
		if(token != null && token.indexOf("custom:") == 0)
		{
			var samples:Array<Float> = decode(token);
			return function(t:Float):Float { return eval(samples, t); };
		}
		var fn:Float->Float = Reflect.field(FlxEase, token);
		if(fn == null) fn = FlxEase.linear;
		return fn;
	}
}
