package general.objects;

class MenuItem extends FlxSprite
{
	public var targetY:Float = 0;
	public var animationSpeed:Float = 1;

	public function new(x:Float, y:Float, weekName:String = '')
	{
		super(x, y);
		loadGraphic(Paths.image('storymenu/' + weekName));
		antialiasing = ClientPrefs.data.antialiasing;
		// trace('Test added: ' + WeekData.getWeekNumber(weekNum) + ' (' + weekNum + ')');
	}

	public var isFlashing(default, set):Bool = false;

	private var _flashingElapsed:Float = 0;
	final _flashColor = 0xFF33FFFF;
	final flashes_ps:Int = 6;

	public function set_isFlashing(value:Bool = true):Bool
	{
		isFlashing = value;
		_flashingElapsed = 0;
		color = (isFlashing) ? _flashColor : FlxColor.WHITE;
		return isFlashing;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		var target:Float = (targetY * 120) + 480;
		if (Math.abs(target - y) < 0.05)
		{
			y = target;
			// StoryMode can contain many mod weeks. Static menu art has no per-frame
			// animation work once its vertical easing finishes; wake it when layout
			// assigns a new target or when the confirm flash is active.
			if (!isFlashing) active = false;
		}
		else
			y = FlxMath.lerp(target, y, Math.exp(-elapsed * 10.2 * Math.max(1, animationSpeed)));
		if (isFlashing)
		{
			_flashingElapsed += elapsed;
			color = (Math.floor(_flashingElapsed * FlxG.updateFramerate * flashes_ps) % 2 == 0) ? _flashColor : FlxColor.WHITE;
		}
	}
}
