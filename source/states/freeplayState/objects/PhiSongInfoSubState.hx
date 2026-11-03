package states.freeplayState.objects;

class PhiSongInfoSubState extends MusicBeatSubstate
{
    public function new(song:String, artist:String, bpm:String, duration:String, difficulty:String)
    {
        super();
        add(new FlxSprite().makeGraphic(1280, 720, 0xC508101A));
        add(new FlxSprite(380, 165).makeGraphic(520, 390, 0xFF202B36));
        add(new FlxSprite(380, 165).makeGraphic(520, 2, FlxColor.WHITE));
        var lines = [song, '曲师  ' + artist, 'BPM  ' + bpm, '时长  ' + duration, '难度  ' + difficulty, '返回  /  ESC'];
        for (i in 0...lines.length) {
            var text = new FlxText(413, 190 + i * 51, 460, lines[i], i == 0 ? 25 : 17);
            text.setFormat(Paths.font('Lang-ZH.ttf'), i == 0 ? 25 : 17, i == 0 ? FlxColor.WHITE : 0xFFCAD6DE);
            text.borderStyle = NONE; text.antialiasing = true; add(text);
        }
    }
    override function update(elapsed:Float):Void {
        super.update(elapsed);
        if (controls.BACK || controls.ACCEPT || (FlxG.mouse.justReleased && FlxG.mouse.y > 437)) close();
    }
}
