package states.freeplayState.objects.detail;

class DetailRect extends FlxSpriteGroup{
    public var bg1:SkewSegmentGradientRoundRect;
    public var bg2:SkewSegmentGradientRoundRect;
    public var bg3:SkewSegmentGradientRoundRect;

    public function new(x, y){
        super(x, y);
        bg1 = new SkewSegmentGradientRoundRect(-55, -7, 690, 285, 15, 15, -10, 0, FlxColor.BLACK, [[0, 0.5, 0.8], [1, 0.5, 0.4]]);
		bg1.antialiasing = ClientPrefs.data.antialiasing;
		add(bg1);

        bg2 = new SkewSegmentGradientRoundRect(-80, 0, bg1.width, 92, 15, 15, -10, 0, FlxColor.BLACK, [[0, 0.5, 0.4], [1, 0.5, 0.2]]);
        bg2.y += bg1.y + bg1.height - bg2.height;
		bg2.antialiasing = ClientPrefs.data.antialiasing;
		add(bg2);

        bg3 = new SkewSegmentGradientRoundRect(-80, 0, bg1.width, 55, 15, 15, -10, 0, FlxColor.BLACK, [[0, 0.5, 0.4], [1, 0.5, 0.2]]);
        bg3.y += bg1.y + bg1.height - bg3.height;
		bg3.antialiasing = ClientPrefs.data.antialiasing;
		add(bg3);
    }
}
