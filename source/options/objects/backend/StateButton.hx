package options.objects.backend;

import states.freeplayState.objects.PhiPanel;

class StateButton extends FlxSpriteGroup{
	public var bg:PhiPanel;
	public var stateName:FlxText;

    var follow:Option;

	public function new(width:Float, height:Float, follow:Option)
	{
        super(); //直接跟随option的x和y
        this.follow = follow;

		bg = new PhiPanel(0, 0, Std.int(width), Std.int(height), EngineSet.mainColor);
		bg.alpha = 0.5;
		add(bg);

		stateName = new FlxText(0, 0, bg.width, follow.description, Std.int(bg.width / 30));
		stateName.setFormat(Paths.font(Language.get('fontName', 'main') + '.ttf'), Std.int(bg.width / 30), 0xffffff, CENTER, FlxTextBorderStyle.OUTLINE, 0xFFFFFFFF);
        stateName.antialiasing = ClientPrefs.data.antialiasing;
		stateName.borderStyle = NONE;
		stateName.x = 0;
		stateName.y = (bg.height - stateName.height) / 2;
		stateName.alpha = 0.8;
		add(stateName);
	}

    var colorChange:Bool = false;
    var timeCalc:Float;
    override function update(elapsed:Float) {
        super.update(elapsed);

        timeCalc += elapsed;
        
        if (!follow.allowUpdate) {
            timeCalc = 0;
            return;
        }

        if (timeCalc < 0.6) return;

        if (OptionsState.instance.mouseEvent.overlaps(OptionsState.instance.specBG) || OptionsState.instance.mouseEvent.overlaps(OptionsState.instance.downBG)) return;

        var mouse = OptionsState.instance.mouseEvent;

		if (mouse.overlaps(bg)) {
            if (!colorChange) {
                colorChange = true;
                bg.color = 0xffffff;
                bg.alpha = 1;
                stateName.color = EngineSet.mainColor;
                stateName.alpha = 0.8;
            }

            if (mouse.justReleased) {
                follow.change();
            }
        } else {
            if (colorChange) {
                    colorChange = false;
                    bg.color = EngineSet.mainColor;
				bg.alpha = 0.5;
                    stateName.color = 0xFFFFFF;
                    stateName.alpha = 0.8;
                }
        }
    }

	public function refreshLabelLayout():Void
	{
		if (stateName == null || bg == null) return;
		stateName.fieldWidth = bg.width;
		stateName.x = 0;
		stateName.y = (bg.height - stateName.height) / 2;
	}

}
