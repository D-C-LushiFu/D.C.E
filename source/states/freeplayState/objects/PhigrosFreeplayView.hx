package states.freeplayState.objects;

import openfl.display.BitmapData;
import sys.FileSystem;
import sys.io.File;
import general.backend.CoolUtil;
import openfl.display.Shape;
import openfl.display.GradientType;
import openfl.geom.Matrix;
import flixel.graphics.FlxGraphic;
import flixel.math.FlxRect;
import games.backend.Highscore;
import general.objects.AudioDisplay;
import general.backend.language.Language;
import games.objects.HealthIcon;
import states.modsMenuState.ModsMenuState;
import states.freeplayState.objects.PhiItalicText;

/** Presentation only; charts, preview playback and replay loading stay in FreeplayState. */
class PhigrosFreeplayView extends FlxSpriteGroup
{
    public static inline final DESIGN_WIDTH:Int = 1920;
    public static inline final DESIGN_HEIGHT:Int = 1080;
    static inline final DENSITY:Float = 1.5;
    public var cover:PhiPanel;
    var coverIncoming:PhiPanel;
    var activeCover:PhiPanel;
    public var coverTitle:PhiCoverTitle;
    public var bpmValue:FlxText;
    public var durationValue:FlxText;
    public var recordsEmpty:FlxText;
    public var recordsInfo:FlxText;
    public var spectrum:AudioDisplay;
    public var voicesSpectrum:AudioDisplay;
    public var opponentSpectrum:AudioDisplay;
    public var noteValue:FlxText;
    public var holdValue:FlxText;
    public var speedValue:FlxText;
    public var keyValue:FlxText;
    var state:FreeplayState;
    var mesh:FlxSprite;
    var spectrumBottom:FlxSprite;
    var voicesSpectrumBottom:FlxSprite;
    var opponentSpectrumBottom:FlxSprite;
    var songColorWash:FlxSprite;
    var currentBackdropColor:FlxColor = 0xFF657078;
    var targetBackdropColor:FlxColor = 0xFF657078;
    var rows:Array<PhiSongRow> = [];
    var selectionBand:PhiPanel;
    var selectionBadge:PhiPanel;
    var selectionRate:FlxText;
    var selectionName:FlxText;
    var selectionIcon:HealthIcon;
    var badgeNames:Array<FlxText> = [];
    var badgeValues:Array<FlxText> = [];
    var sortCaption:FlxText;
    var tools:Array<{panel:PhiPanel, label:FlxSprite, icon:FlxSprite, action:String}> = [];
    var difficulties:Array<PhiPanel> = [];
    var difficultyNames:Array<FlxText> = [];
    var difficultyValues:Array<FlxText> = [];
    var difficultyIds:Array<Int> = [];
    var difficultySlider:PhiPanel;
    var difficultyTrack:PhiPanel;
    var sortButtons:Array<PhiPanel> = [];
    var sortLabels:Array<FlxText> = [];
    var favoritePanel:PhiPanel;
    var favoriteIcon:FlxSprite;
    var bestScore:FlxText;
    var coverRate:FlxText;
    var counter:FlxText;
    var emptyList:FlxText;
    var listScrollTrack:FlxSprite;
    var listScrollThumb:FlxSprite;
    var sortValue:FlxText;
    var sortPanel:PhiPanel;
    var mirror:PhiPanel;
    var mirrorText:FlxText;
    var play:PhiPanel;
    var back:PhiPanel;
    var progress:FlxSprite;
    var progressTrack:FlxSprite;
    var progressThumb:FlxSprite;
    var pitchUp:PhiPanel;
    var speedButton:PhiPanel;
    var pitchDown:PhiPanel;
    var speedText:FlxText;
    var scrubbingProgress:Bool = false;
    var elapsedLabel:FlxText;
    var lengthLabel:FlxText;
    var elapsedTime:Float = 0;
    var lastSelected:Int = -1;
    var lastDifficulty:Int = -1;
    var lastFavorite:Bool = false;
    var dirtyRows:Bool = true;
    var displayedIndex:Int = -1;
    var scrollingThumb:Bool = false;
    var thumbGrabOffset:Float = 0;
    var dragging:Bool = false;
    var dragStartY:Float = 0;
    var dragMoved:Bool = false;
    var palette:Array<FlxColor> = [0xFF31C878, 0xFFFFC83D, 0xFFEF303D];
    var profilePanel:PhiPanel;
    var profileName:FlxText;
    var profileAvatar:FlxSprite;
    var profileInitial:FlxText;

    public function new(state:FreeplayState)
    {
        super();
        this.state = state;
        var backdrop = new Shape();
        var matrix = new Matrix(); matrix.createGradientBox(1280, 720, Math.PI / 5);
        backdrop.graphics.beginGradientFill(GradientType.LINEAR, [0x35494B, 0x657078, 0x484755], [1, 1, 1], [0, 140, 255], matrix);
        backdrop.graphics.drawRect(0, 0, 1280, 720);
        add(bitmapSprite(backdrop, 1280, 720));
        #if VIDEOS_ALLOWED
        #if sys
        if (Sys.getEnv('DCE_FREEPLAY_CHECK_NO_VIDEO') != '1')
        #end
        add(new PhiVideoBackground());
        #end
        songColorWash = new FlxSprite(0, 0).makeGraphic(DESIGN_WIDTH, DESIGN_HEIGHT, FlxColor.WHITE);
        songColorWash.alpha = 0.24; add(songColorWash);
        mesh = makeMesh(); mesh.alpha = 0.22; add(mesh);
        var rail = new Shape(); rail.graphics.beginFill(0x101922, 0.32);
        rail.graphics.moveTo(69 + 720 * PhiPanel.SLOPE, 0); rail.graphics.lineTo(469 + 720 * PhiPanel.SLOPE, 0); rail.graphics.lineTo(469, 720); rail.graphics.lineTo(69, 720); rail.graphics.endFill();
        add(bitmapSprite(rail, 1280, 720));

        // Use the full set of frequency bands once across the width instead
        // of mirroring half of the spectrum. A longer FFT improves the low
        // end without changing the visual refresh cadence.
        spectrum = new AudioDisplay(FlxG.sound.music, 0, 1012, 1920, 160, 96, 3, FlxColor.WHITE, false);
        spectrum.visualGain = 1.0;
        spectrum.attackSpeed = 10; spectrum.releaseSpeed = 20; spectrum.sampleIntervalMs = 25; spectrum.resetWhenStopped = true; spectrum.fftQualityOverride = 8; spectrum.refreshFFTQuality(); spectrum.alpha = 0.15; add(spectrum);
        spectrumBottom = spectrum.enableBarGeometry();
        spectrumBottom.alpha = 0.045; add(spectrumBottom);
        voicesSpectrum = new AudioDisplay(null, 0, 1012, 960, 160, 48, 3, FlxColor.BLACK, false);
        voicesSpectrum.visualGain = 1.0;
        voicesSpectrum.attackSpeed = 10; voicesSpectrum.releaseSpeed = 20; voicesSpectrum.sampleIntervalMs = 25; voicesSpectrum.resetWhenStopped = true; voicesSpectrum.fftQualityOverride = 8; voicesSpectrum.refreshFFTQuality(); voicesSpectrum.alpha = 0.17; add(voicesSpectrum);
        voicesSpectrumBottom = voicesSpectrum.enableBarGeometry();
        voicesSpectrumBottom.alpha = 0.045; add(voicesSpectrumBottom);
        opponentSpectrum = new AudioDisplay(null, 960, 1012, 960, 160, 48, 3, 0xFFEF5364, false);
        opponentSpectrum.visualGain = 1.0;
        opponentSpectrum.attackSpeed = 10; opponentSpectrum.releaseSpeed = 20; opponentSpectrum.sampleIntervalMs = 25; opponentSpectrum.resetWhenStopped = true; opponentSpectrum.fftQualityOverride = 8; opponentSpectrum.refreshFFTQuality(); opponentSpectrum.alpha = 0.17; add(opponentSpectrum);
        opponentSpectrumBottom = opponentSpectrum.enableBarGeometry();
        opponentSpectrumBottom.alpha = 0.045; add(opponentSpectrumBottom);

        var toolbar = panelAt(224, 36, 720, 66, 0xFF101722); toolbar.alpha = 0.82; add(toolbar);
        sortCaption = label(253, 51, 133, textFor('sortBy', '排序方式', 'Sort by'), 11, false, false, 0xFFC1CDD2);
        sortValue = label(253, 70, 145, textFor('sortOrder', '曲目顺序', 'Song order'), 17);
        sortPanel = panelAt(247, 44, 142, 53); sortPanel.alpha = 0; add(sortPanel);
        var actions = ['search', 'favorites', 'random', 'options', 'mod', 'changer', 'editor', 'reset', 'audio'];
        var titleKeys = ['searchSong', 'favorite', 'random', 'option', 'mods', 'changers', 'chart', 'reset', 'previewMusic'];
        for (i in 0...actions.length)
        {
            var x = 400 + i * 60;
            var panel = PhigrosFreeplayView.panelAt(x, 42, 58, 55); panel.alpha = 0; add(panel);
            var icon = makeIcon(x + 19, 56, actions[i]); add(icon);
            var caption = textFor(titleKeys[i], ['搜索','收藏','随机','设置','模组','数据更改','谱面','重置','背景音乐'][i], ['Search','Favorite','Random','Options','Mods','Changers','Chart','Reset','Preview music'][i]);
            var text:FlxSprite;
            if (actions[i] == 'audio') {
                var marquee = new PhiMarqueeText(58);
                marquee.setText(caption, Paths.font(~/[^\x00-\x7F]/.match(caption) ? 'Lang-ZH.ttf' : 'montserrat.ttf'), 13, FlxColor.WHITE);
                marquee.setPosition((x + 1) * DENSITY, 78 * DENSITY);
                text = marquee; add(marquee);
            } else {
                var labelText = label(x + 1, 78, 58, caption, 9); labelText.alignment = CENTER;
                text = labelText;
            }
            tools.push({panel: panel, label: text, icon: icon, action: actions[i]});
        }
        profilePanel = panelAt(1013, 39, 246, 52, 0xFF10131D); profilePanel.alpha = 0.9; add(profilePanel);
        profileName = label(1036, 53, 70, 'Ruckus', 17, true);
        var hexagon = new Shape(); var g = hexagon.graphics; g.beginFill(0x91C85C);
        for (i in 0...6) { var a = (i * 60 - 90) * Math.PI / 180; var px = 20 + Math.cos(a) * 20; var py = 20 + Math.sin(a) * 20; if (i == 0) g.moveTo(px, py); else g.lineTo(px, py); }
        g.endFill(); var avatarFrame = bitmapSprite(hexagon, 40, 40); avatarFrame.x = 1657.5; avatarFrame.y = 67.5; add(avatarFrame);
        profileAvatar = new FlxSprite(); profileAvatar.setPosition(1662, 72); profileAvatar.setGraphicSize(32, 32); profileAvatar.antialiasing = true; add(profileAvatar);
        profileInitial = label(1116, 52, 22, 'R', 20, false, true, 0xFF152319);
        label(1152, 49, 99, textFor('userSummary', '已通关曲目 · 平均准度', 'Cleared charts · Avg. accuracy'), 8, false, false, 0xFFD0D9DF);
        label(1151, 62, 100, '97.44%', 17, true, true);
        refreshProfile();

        line(200, 125, 18, 1, 0xCCFFFFFF);
        label(227, 119, 225, textFor('collection', '自由游玩  /  D.C.E. 曲库', 'FREEPLAY  /  D.C.E. COLLECTION'), 9, false, false, 0xFFD5E0E5);
        // The selection band is stationary; only the song rows move.
        selectionBand = panelAt(145, 270, 425, 96, 0xFF111821); selectionBand.alpha = 0.94; add(selectionBand);
        var selectionEdge = new FlxSprite((145 + 96 * PhiPanel.SLOPE) * DENSITY, 270 * DENSITY).makeGraphic(3, 149, FlxColor.WHITE);
        selectionEdge.origin.set(0, 0); selectionEdge.angle = 15; add(selectionEdge);
        for (i in 0...9) { var row = new PhiSongRow(); rows.push(row); add(row); }
        selectionBadge = panelAt(482, 267, 90, 102); add(selectionBadge);
        selectionIcon = new HealthIcon('face', false, false); selectionIcon.setGraphicSize(112,112); selectionIcon.updateHitbox();
        selectionIcon.setPosition(1590, 956); add(selectionIcon);
        listScrollTrack = new FlxSprite((35 + 548 * PhiPanel.SLOPE) * DENSITY, 130 * DENSITY).makeGraphic(8, 851, 0x40FFFFFF);
        listScrollTrack.origin.set(0,0); listScrollTrack.angle = 15; add(listScrollTrack);
        listScrollThumb = new FlxSprite().makeGraphic(18, 1, 0xFFDBE5EA);
        listScrollThumb.origin.set(0, 0); listScrollThumb.angle = 15; listScrollThumb.alpha = 0.85; add(listScrollThumb);
        emptyList = label(248, 283, 330, textFor('noMatchingSongs', '没有符合条件的曲目', 'No matching songs'), 21);
        emptyList.visible = false;

        var detailStart = members.length;
        cover = panelAt(572, 147, 617, 329, 0xFF372C46); add(cover);
        activeCover = cover;
        coverIncoming = panelAt(572, 147, 617, 329, 0xFF372C46); coverIncoming.alpha = 0; add(coverIncoming);
        // A separate masked gradient keeps white jackets readable without tinting the artwork.
        var shadeShape = new Shape(); var shadeMatrix = new Matrix(); shadeMatrix.createGradientBox(617, 329, Math.PI / 2);
        shadeShape.graphics.beginGradientFill(GradientType.LINEAR, [0x0A101C, 0x0A101C, 0x0A101C], [0.10, 0.15, 0.9], [0, 110, 255], shadeMatrix);
        var dx = 329 * PhiPanel.SLOPE; shadeShape.graphics.moveTo(dx, 0); shadeShape.graphics.lineTo(617, 0); shadeShape.graphics.lineTo(617 - dx, 329); shadeShape.graphics.lineTo(0, 329); shadeShape.graphics.endFill();
        var shade = bitmapSprite(shadeShape, 617, 329); shade.x = 858; shade.y = 220.5; add(shade);
        line(660, 147, 529, 1, 0x70FFFFFF);
        var best = panelAt(669, 160, 129, 51, 0xFF0B1019); best.alpha = 0.87; add(best);
        label(684, 165, 95, textFor('bestScore', '最高分', 'Best score'), 11, true, false, 0xFFC7D2DA);
        bestScore = label(679, 181, 105, '—', 20, true, true);
        favoritePanel = panelAt(1133, 160, 42, 40, 0xFF0B1019); favoritePanel.alpha = 0.88; add(favoritePanel);
        favoriteIcon = makeIcon(1145, 170, 'favorites'); favoriteIcon.scale.set(1.2, 1.2); favoriteIcon.color = 0xFFBCC7D1; add(favoriteIcon);
        coverTitle = new PhiCoverTitle(700); coverTitle.setPosition(632 * DENSITY, 264 * DENSITY); add(coverTitle);
        coverRate = label(633, 419, 440, 'D.C.E.  /  FREEPLAY', 9, true, false, 0xFFC7CCD8);
        line(606, 459, 498, 2, 0x777E8996);
        progressTrack = new FlxSprite(909, 688.5).makeGraphic(540, 3, 0x887F8996); progressTrack.origin.set(0, 0); add(progressTrack);
        progress = new FlxSprite(909, 688.5).makeGraphic(540, 3, 0xFFFFCBDD); progress.origin.set(0, 0); add(progress);
        var thumbShape = new Shape(); thumbShape.graphics.beginFill(0xFFFFFFFF); thumbShape.graphics.drawCircle(7, 7, 6); thumbShape.graphics.endFill();
        progressThumb = bitmapSprite(thumbShape, 14, 14); add(progressThumb);
        elapsedLabel = label(608, 461, 80, '00:00', 9, true);
        lengthLabel = label(925, 461, 50, '00:00', 9, true); lengthLabel.alignment = RIGHT;
        pitchUp = panelAt(989, 447, 56, 24, 0xFF161B25); pitchUp.alpha = 0.92; add(pitchUp);
        label(992, 451, 50, textFor('pitchUp', '+1音阶', '+1 semitone'), 9, false, true).alignment = CENTER;
        speedButton = panelAt(1047, 447, 60, 24, 0xFF161B25); speedButton.alpha = 0.70; add(speedButton);
        speedText = label(1050, 451, 54, '[1.0X]', 9, false, true); speedText.alignment = CENTER;
        pitchDown = panelAt(1109, 447, 56, 24, 0xFF161B25); pitchDown.alpha = 0.92; add(pitchDown);
        label(1112, 451, 50, textFor('pitchDown', '-1音阶', '-1 semitone'), 9, false, true).alignment = CENTER;

        var stats = panelAt(558, 487, 541, 43, 0xFF181B27); stats.alpha = 0.6; add(stats);
        var statsNames = [textFor('bpm', 'BPM', 'BPM'), textFor('duration', '时长', 'Duration'), textFor('noteCount', '音符', 'Notes'), textFor('holdNotes', '长按', 'Holds'), textFor('speed', '滚速', 'Speed'), textFor('keyCount', '键数', 'Keys')];
        var values:Array<FlxText> = [];
        for (i in 0...6)
        {
            var x = 565 + i * 87;
            if (i > 0) line(x - 4, 493, 1, 31, 0x33FFFFFF);
            var statName = label(x, 492, 82, statsNames[i], 8, false, false, 0xFFD1D6DE); statName.alignment = CENTER;
            var statValue = label(x, 505, 82, '—', 14, false, true); statValue.alignment = CENTER;
            values.push(statValue);
        }
        bpmValue = values[0]; durationValue = values[1]; noteValue = values[2]; holdValue = values[3]; speedValue = values[4]; keyValue = values[5];
        mirror = panelAt(1085, 540, 100, 36, 0xFF1A202B); mirror.alpha = 0.7; add(mirror);
        mirrorText = label(1099, 550, 76, textFor('mirror', '镜像', 'Mirror'), 13); mirrorText.alignment = CENTER;

        var records = panelAt(521, 538, 500, 124, 0xFF11151F); records.alpha = 0.75; add(records);
        label(545, 543, 130, textFor('savedRecords', '已保存记录', 'Saved records'), 12, false, true);
        recordsInfo = label(680, 546, 65, '', 9, false, false, 0xFFB9C4CB);
        recordsEmpty = label(538, 574, 450, textFor('noSavedRecords', '暂无已保存记录', 'No saved records'), 12, false, false, 0xFFBBC7D1);
        var sorts = [textFor('date', '日期', 'Date'), textFor('score', '得分', 'Score'), textFor('accuracy', '准度', 'Accuracy'), textFor('combo', '连击', 'Combo')];
        for (i in 0...4)
        {
            var panel = PhigrosFreeplayView.panelAt(750 + i * 66, 553, 62, 21); panel.alpha = i == 0 ? 1 : 0; add(panel); sortButtons.push(panel);
            var text = label(750 + i * 66, 555, 62, sorts[i], 9); text.alignment = CENTER; sortLabels.push(text);
        }
        play = panelAt(1025, 668, 219, 64); add(play);
        var triangle = new Shape(); triangle.graphics.beginFill(0x252B33); triangle.graphics.moveTo(0, 0); triangle.graphics.lineTo(16, 10); triangle.graphics.lineTo(0, 20); triangle.graphics.endFill();
        var playIcon = bitmapSprite(triangle, 17, 21); playIcon.x = 1594.5; playIcon.y = 1035; add(playIcon);
        label(1091, 683, 84, textFor('start', '开始', 'Start'), 20, false, true, 0xFF252B33);
        label(1096, 707, 79, textFor('playHint', '游 玩', 'P L A Y'), 7, false, false, 0xFF737C84);
        for (i in detailStart...members.length) {
            var sprite:FlxSprite = cast members[i];
            sprite.y -= 24 * DENSITY;
        }
        back = panelAt(24, 36, 194, 66, 0xFF131C25); back.alpha = 0.82; add(back);
        label(44, 58, 173, 'D.C.E.  ‹  ' + textFor('backToMenu', '返回主菜单', 'Back to menu'), 14, true, true);
        counter = label(48, 687, 158, '', 15);
        label(225, 692, 353, textFor('freeplayControls', '↑ ↓ 选曲     ← → 难度     ENTER 开始     T 搜索', '↑ ↓ Select     ← → Difficulty     ENTER Start     T Search'), 9, false, false, 0xFFB0BEC7);
        // Draw the selected character last: immediately after the Start label,
        // inside the button, and above every UI layer.
        remove(selectionIcon, true);
        layoutSelectionIcon();
        add(selectionIcon);
        #if sys
        if (Sys.getEnv('DCE_FREEPLAY_CHECK_NO_SPECTRUM') == '1') {
            spectrum.exists = voicesSpectrum.exists = opponentSpectrum.exists = false;
            spectrumBottom.exists = voicesSpectrumBottom.exists = opponentSpectrumBottom.exists = false;
        }
        #end
    }

    public static function panelAt(x:Float, y:Float, w:Int, h:Int, tint:FlxColor = FlxColor.WHITE):PhiPanel {
        return new PhiPanel(x * DENSITY, y * DENSITY, Std.int(Math.round(w * DENSITY)), Std.int(Math.round(h * DENSITY)), tint);
    }
    public static function labelAt(x:Float, y:Float, w:Float, text:String, size:Int, italic:Bool = false, bold:Bool = false, color:FlxColor = FlxColor.WHITE):FlxText
    {
        var result:FlxText = italic
            ? new PhiItalicText(x * DENSITY, y * DENSITY, w * DENSITY, text, Std.int(Math.round(size * DENSITY)))
            : new FlxText(x * DENSITY, y * DENSITY, w * DENSITY, text, Std.int(Math.round(size * DENSITY)));
        result.setFormat(Paths.font(~/[^\x00-\x7F]/.match(text) ? 'Lang-ZH.ttf' : 'montserrat.ttf'), Std.int(Math.round(size * DENSITY)), color, LEFT);
        result.borderStyle = NONE; result.bold = bold; result.antialiasing = true;
        result.textField.wordWrap = false;
        return result;
    }
    function label(x:Float, y:Float, w:Float, text:String, size:Int, italic:Bool = false, bold:Bool = false, color:FlxColor = FlxColor.WHITE):FlxText
    { var result = labelAt(x, y, w, text, size, italic, bold, color); add(result); return result; }
    function line(x:Float, y:Float, w:Int, h:Int, color:FlxColor):Void { add(new FlxSprite(x * DENSITY, y * DENSITY).makeGraphic(Std.int(Math.round(w * DENSITY)), Std.int(Math.round(h * DENSITY)), color)); }
    static function bitmapSprite(shape:Shape, w:Int, h:Int):FlxSprite
    { var bitmap = new BitmapData(Std.int(Math.round(w * DENSITY)), Std.int(Math.round(h * DENSITY)), true, 0); var matrix = new Matrix(); matrix.scale(DENSITY, DENSITY); bitmap.draw(shape, matrix, null, null, null, true); return new FlxSprite().loadGraphic(FlxGraphic.fromBitmapData(bitmap, false, null, false)); }

    function makeMesh():FlxSprite
    {
        var shape = new Shape(); var g = shape.graphics; g.lineStyle(1.2, 0xD2E3E5, 0.43);
        var points:Array<Array<Float>> = [];
        for (r in 0...6) for (c in 0...8) points.push([c * 210 + (r % 2) * 100 + Math.sin(c * 8 + r) * 41, r * 167 + Math.cos(c + r * 2) * 31]);
        for (r in 0...6) for (c in 0...8)
        {
            var p = points[r * 8 + c];
            var links = [c < 7 ? r * 8 + c + 1 : -1, r < 5 ? (r + 1) * 8 + c : -1, r < 5 && c < 7 ? (r + 1) * 8 + c + 1 : -1];
            for (index in links) if (index >= 0) { var q = points[index]; g.moveTo(p[0], p[1]); g.lineTo(q[0], q[1]); }
        }
        var result = bitmapSprite(shape, 1480, 875); result.x = -40; result.y = -50; return result;
    }

    static function makeIcon(x:Float, y:Float, kind:String):FlxSprite
    {
        var shape = new Shape(); var g = shape.graphics; g.lineStyle(1.1, 0xFFFFFF, 1);
        switch (kind)
        {
            case 'search': g.drawCircle(8,8,6); g.moveTo(12,12); g.lineTo(19,19);
            case 'favorites':
                g.beginFill(0xFFFFFF); for (i in 0...10) { var a = (i * 36 - 90) * Math.PI / 180; var r = i % 2 == 0 ? 9 : 4; var px = 10 + Math.cos(a) * r; var py = 10 + Math.sin(a) * r; if (i == 0) g.moveTo(px, py); else g.lineTo(px, py); } g.endFill();
            case 'options':
                for (i in 0...3) { g.moveTo(1, 4 + i * 6); g.lineTo(19, 4 + i * 6); g.drawCircle(i == 1 ? 13 : 6, 4 + i * 6, 2.2); }
            case 'random':
                g.moveTo(1, 4); g.lineTo(5, 4); g.lineTo(14, 16); g.lineTo(19, 16); g.moveTo(1, 16); g.lineTo(5, 16); g.lineTo(14, 4); g.lineTo(19, 4); g.moveTo(16, 1); g.lineTo(19, 4); g.lineTo(16, 7); g.moveTo(16, 13); g.lineTo(19, 16); g.lineTo(16, 19);
            case 'reset': g.drawCircle(10, 10, 7); g.moveTo(1, 1); g.lineTo(1, 8); g.lineTo(7, 8);
            case 'editor': g.drawRect(3, 2, 14, 16); for (i in 0...4) { g.moveTo(5, 5 + i * 3); g.lineTo(15, 5 + i * 3); }
            case 'changer': g.moveTo(3, 16); g.lineTo(14, 3); g.lineTo(18, 7); g.lineTo(7, 19); g.lineTo(3, 19); g.lineTo(3, 16);
            case 'audio': g.moveTo(8, 15); g.lineTo(8, 3); g.lineTo(17, 1); g.lineTo(17, 13); g.beginFill(0xFFFFFF); g.drawEllipse(2, 13, 6, 4); g.drawEllipse(11, 11, 6, 4); g.endFill();
            default: g.moveTo(10, 1); g.lineTo(19, 10); g.lineTo(10, 19); g.lineTo(1, 10); g.lineTo(10, 1); g.moveTo(10, 5); g.lineTo(10, 15); g.moveTo(5, 10); g.lineTo(15, 10);
        }
        var result = bitmapSprite(shape, 21, 21); result.x = x * DENSITY; result.y = y * DENSITY; return result;
    }

    function layoutSelectionIcon():Void
    {
        selectionIcon.setGraphicSize(128, 128);
        selectionIcon.updateHitbox();
        // HealthIcon resets offsets for gameplay. Here align the scaled visual
        // bounds as well, including mod icons whose source frames are huge.
        selectionIcon.offset.set((selectionIcon.frameWidth - selectionIcon.width) * 0.5,
            (selectionIcon.frameHeight - selectionIcon.height) * 0.5);
        selectionIcon.setPosition(play.x + play.width - selectionIcon.width - 18,
            play.y + (play.height - selectionIcon.height) * 0.5);
    }

    public function refreshSong(animate:Bool = false):Void
    {
        lastSelected = FreeplayState.curSelected; lastDifficulty = FreeplayState.curDifficulty;
        var song = state.songGroup[lastSelected];
        var selectedColor = song.getSongColor();
        targetBackdropColor = selectedColor;
        coverTitle.setText(song.songNameSt, Paths.font(~/[^\x00-\x7F]/.match(song.songNameSt) ? 'Lang-ZH.ttf' : 'montserrat.ttf'));
        var score = lastDifficulty >= 0 ? Highscore.getScore(Paths.formatToSongPath(song.songNameSt), lastDifficulty) : 0;
        bestScore.text = score > 0 ? StringTools.lpad(Std.string(score), '0', 7) : '—';
        selectionIcon.changeIcon(state.phiIconCharacter(), false);
        layoutSelectionIcon();
        refreshSelectedBadge();
        refreshDifficulties(); dirtyRows = true; refreshRecords();
    }
    public static function textFor(key:String, zh:String, en:String):String {
        var value = Language.get(key, 'freeplay');
        if (value == key || StringTools.startsWith(value, key + ' ('))
            return ClientPrefs.data.language == 'Chinese' ? zh : en;
        return value;
    }

    /** Put new jacket art over the previous art, then retire the old layer. */
    public function installArtwork(bitmap:BitmapData):Void
    {
        var next = activeCover == cover ? coverIncoming : cover;
        FlxTween.cancelTweensOf(next);
        next.installArtwork(bitmap);
        next.alpha = 0;
        FlxTween.tween(next, {alpha: 1}, 0.22, {ease: FlxEase.quadOut, onComplete: function(_) {
            activeCover.alpha = 0;
            activeCover = next;
        }});
    }
    function refreshSelectedBadge():Void {
        for (item in badgeNames) { remove(item, true); item.destroy(); }
        for (item in badgeValues) { remove(item, true); item.destroy(); }
        badgeNames = []; badgeValues = [];
        var text = label(490, 330, 66, '', 12, false, true, 0xFF20242A);
        var value = label(494, 297, 67, '', 27, false, true, 0xFF20242A);
        text.alignment = value.alignment = CENTER;
        badgeNames.push(text); badgeValues.push(value);
        updateSelectedBadge();
    }
    function updateSelectedBadge():Void {
        var names = state.phiDifficultyNames(FreeplayState.curSelected);
        var selected = FreeplayState.curDifficulty;
        for (i in 0...badgeValues.length) {
            badgeValues[i].text = state.phiRatingText(FreeplayState.curSelected, selected);
            badgeValues[i].color = 0xFF20242A;
            badgeNames[i].text = selected >= 0 && selected < names.length ? names[selected] : '';
            badgeNames[i].color = 0xFF20242A;
        }
    }
    public function refreshDifficulties():Void
    {
        var previousX = difficultySlider == null ? -1.0 : difficultySlider.x / DENSITY;
        for (item in difficulties) { remove(item, true); item.destroy(); }
        for (item in difficultyNames) { remove(item, true); item.destroy(); }
        for (item in difficultyValues) { remove(item, true); item.destroy(); }
        difficulties = []; difficultyNames = []; difficultyValues = [];
        if (difficultySlider != null) { FlxTween.cancelTweensOf(difficultySlider); remove(difficultySlider, true); difficultySlider.destroy(); difficultySlider = null; }
        if (difficultyTrack != null) { remove(difficultyTrack, true); difficultyTrack.destroy(); difficultyTrack = null; }
        difficultyIds = state.availablePhiDifficulties(FreeplayState.curSelected).copy();
        var count = difficultyIds.length; if (count == 0) return;
        var w = Std.int(Math.min(88, 225 / count));
        difficultyTrack = PhigrosFreeplayView.panelAt(1025, 582, count * (w - 3) + 3, 52, 0xFFF3F4F5);
        add(difficultyTrack);
        for (i in 0...count)
        {
            var panel = PhigrosFreeplayView.panelAt(1025 + i * (w - 3), 582, w, 52, 0xFFF3F4F5);
            panel.alpha = 0; add(panel); difficulties.push(panel);
        }
        var selected = Std.int(FlxMath.bound(difficultyIds.indexOf(FreeplayState.curDifficulty), 0, count - 1));
        difficultySlider = PhigrosFreeplayView.panelAt(1025 + selected * (w - 3), 582, w, 52, state.difficultyColor(difficultyIds[selected]));
        if (previousX >= 0) difficultySlider.x = previousX * DENSITY;
        add(difficultySlider);
        var names = state.phiDifficultyNames(FreeplayState.curSelected);
        for (i in 0...count)
        {
            var px = difficulties[i].x / DENSITY;
            var diffId = difficultyIds[i];
            var difficultyName = diffId >= 0 && diffId < names.length ? names[diffId] : '';
            var valueColor = i == selected && difficultyName.toLowerCase() != 'normal' ? FlxColor.WHITE : 0xFF161A20;
            var value = label(px + 5, 585, w - 10, state.phiRatingText(FreeplayState.curSelected, diffId), 17, false, true, valueColor);
            value.alignment = CENTER; difficultyValues.push(value);
            var name = label(px + 3, 607, w - 6, difficultyName, 10, false, true, valueColor);
            name.alignment = CENTER; difficultyNames.push(name);
        }
        if (previousX >= 0) FlxTween.tween(difficultySlider, {x: (1025 + selected * (w - 3)) * DENSITY}, 0.16, {ease: FlxEase.quadOut});
    }
    public function refreshOrder():Void { dirtyRows = true; }
    public function refreshRatingValues():Void {
        for (i in 0...difficultyValues.length) difficultyValues[i].text = state.phiRatingText(FreeplayState.curSelected, difficultyIds[i]);
        var selected = difficultyIds.indexOf(FreeplayState.curDifficulty);
        if (difficultySlider != null && selected >= 0) difficultySlider.color = state.difficultyColor(difficultyIds[selected]);
        updateSelectedBadge();
        dirtyRows = true;
    }
    public function setRating(rate:Float):Void { coverRate.text = 'CHART RATE  ' + rate + '  /  D.C.E. FREEPLAY'; refreshRatingValues(); }
    public function setProgress(time:Float, length:Float):Void
    {
        var fraction = length > 0 ? FlxMath.bound(time / length, 0, 1) : 0;
        progress.scale.x = fraction;
        progressThumb.x = progressTrack.x + progressTrack.width * fraction - progressThumb.width / 2;
        progressThumb.y = progress.y + (progress.height - progressThumb.height) / 2;
        elapsedLabel.text = FreeplayState.formatPreviewTime(time); lengthLabel.text = FreeplayState.formatPreviewTime(length);
        durationValue.text = length > 0 ? FreeplayState.formatPreviewTime(length) : '—';
        var rate = state.previewPlaybackRate;
        var speedLabel = Std.string(Math.round(rate * 100) / 100);
        if (rate == Math.floor(rate)) speedLabel += '.0';
        speedText.text = '[' + speedLabel + 'X]';
    }
    public function refreshRecords():Void
    {
        var mode = Std.string(state.replaySortMode);
        var selected = mode.indexOf('DATE') == 0 ? 0 : mode.indexOf('SCORE') == 0 ? 1 : mode.indexOf('ACC') == 0 ? 2 : 3;
        for (i in 0...sortButtons.length) { sortButtons[i].alpha = i == selected ? 1 : 0; sortLabels[i].color = i == selected ? 0xFF222831 : 0xFFC7D0DA; }
    }
    public function click(mx:Float, my:Float):Void
    {
        if (dragMoved) { dragMoved = false; return; }
        if (profilePanel.contains(mx, my)) { state.openPhiProfile(); return; }
        if (play.contains(mx, my)) { state.startGame(); return; }
        if (back.contains(mx, my)) { state.returnPhiMenu(); return; }
        if (pitchUp.contains(mx, my)) { state.adjustPreviewPitch(1); return; }
        if (pitchDown.contains(mx, my)) { state.adjustPreviewPitch(-1); return; }
        // The middle value is a readout of the two semitone controls.
        if (speedButton.contains(mx, my)) return;
        if (favoritePanel.contains(mx, my)) { state.togglePhiFavorite(); return; }
        if (mirror.contains(mx, my)) { ClientPrefs.data.flipChart = !ClientPrefs.data.flipChart; ClientPrefs.saveSettings(); return; }
        if (sortPanel.contains(mx, my)) { state.cyclePhiSort(); return; }

        for (tool in tools) if (tool.panel.contains(mx, my)) { state.runPhiTool(tool.action); return; }
        for (i in 0...difficulties.length) if (difficulties[i].contains(mx, my)) { state.setHybridDifficulty(difficultyIds[i]); return; }
        for (i in 0...sortButtons.length) if (sortButtons[i].contains(mx, my)) { state.sortPhiRecords(i); return; }
        for (row in rows) if (row.visible && row.hit(mx, my)) { state.selectPhiSong(row.songId); return; }
    }

    public function refreshProfile():Void
    {
        var savedName:String = 'Ruckus';
        if (FlxG.save != null && FlxG.save.data != null)
        {
            var value:Dynamic = Reflect.field(FlxG.save.data, 'dceFreeplayProfileName');
            if (value != null && StringTools.trim(Std.string(value)) != '') savedName = StringTools.trim(Std.string(value));
        }
        profileName.text = savedName.length > 8 ? savedName.substr(0, 7) + '…' : savedName;
        profileInitial.text = savedName.length > 0 ? savedName.substr(0, 1).toUpperCase() : 'D';
        profileAvatar.visible = false;
        #if sys
        try
        {
            var avatarName:Dynamic = FlxG.save != null && FlxG.save.data != null
                ? Reflect.field(FlxG.save.data, 'dceFreeplayAvatarFile') : null;
            var avatarPath = CoolUtil.getSavePath() + '/freeplay-profile/'
                + (avatarName == null ? 'avatar.png' : Std.string(avatarName));
            if (FileSystem.exists(avatarPath))
            {
                var bitmap = BitmapData.fromFile(avatarPath);
                if (bitmap != null)
                {
                    profileAvatar.loadGraphic(FlxGraphic.fromBitmapData(bitmap, true));
                    profileAvatar.setGraphicSize(32, 32);
                    profileAvatar.updateHitbox();
                    profileAvatar.setPosition(1662, 72);
                    profileAvatar.visible = true;
                    profileInitial.visible = false;
                }
            }
        }
        catch (e:Dynamic) trace('[FreeplayProfile] Could not load local avatar: ' + e);
        #end
        if (!profileAvatar.visible) profileInitial.visible = true;
    }
    override public function update(elapsed:Float):Void
    {
        elapsedTime += elapsed;
        var showTools = !state.searchButton.visible;
        sortCaption.visible = sortValue.visible = sortPanel.visible = showTools;
        for (tool in tools) tool.panel.visible = tool.label.visible = tool.icon.visible = showTools;
        mesh.x = -60 + Math.sin(elapsedTime * 0.16) * 15; mesh.y = -75 + Math.cos(elapsedTime * 0.11) * 12;
        var backdropLerp = Math.min(1, elapsed * 12);
        currentBackdropColor = FlxColor.interpolate(currentBackdropColor, targetBackdropColor, backdropLerp);
        songColorWash.color = currentBackdropColor;
        // Keep the live texture updates visible without turning the whole menu
        // into a high-contrast flash when the preview toggle is enabled.
        var visualizerBlend = Math.min(1, elapsed * 9);
        spectrum.alpha = FlxMath.lerp(spectrum.alpha, state.phiAudioVisible ? 0.15 : 0, visualizerBlend);
        spectrumBottom.alpha = FlxMath.lerp(spectrumBottom.alpha, state.phiAudioVisible ? 0.045 : 0, visualizerBlend);
        voicesSpectrum.alpha = FlxMath.lerp(voicesSpectrum.alpha, state.phiAudioVisible ? 0.17 : 0, visualizerBlend);
        voicesSpectrumBottom.alpha = FlxMath.lerp(voicesSpectrumBottom.alpha, state.phiAudioVisible ? 0.045 : 0, visualizerBlend);
        opponentSpectrum.alpha = FlxMath.lerp(opponentSpectrum.alpha, state.phiAudioVisible ? 0.17 : 0, visualizerBlend);
        voicesSpectrumBottom.x = voicesSpectrum.x;
        opponentSpectrumBottom.alpha = FlxMath.lerp(opponentSpectrumBottom.alpha, state.phiAudioVisible ? 0.045 : 0, visualizerBlend);
        voicesSpectrumBottom.visible = voicesSpectrum.visible;
        opponentSpectrumBottom.visible = opponentSpectrum.visible;
        spectrum.stopUpdate = voicesSpectrum.stopUpdate = opponentSpectrum.stopUpdate = !state.phiAudioVisible;
        var progressLeft = progressTrack.x;
        var progressRight = progressTrack.x + progressTrack.width;
        if (!state.stopAll && !state.searchButton.hasFocus && FlxG.mouse.justPressed
            && state.phiMouseY >= progress.y - 18 && state.phiMouseY <= progress.y + 22
            && state.phiMouseX >= progressLeft - 10 && state.phiMouseX <= progressRight + 10)
        {
            scrubbingProgress = true;
            dragMoved = true;
        }
        if (scrubbingProgress && FlxG.mouse.pressed)
            state.seekPreview(FlxMath.bound((state.phiMouseX - progressLeft) / Math.max(1, progress.width), 0, 1));
        if (scrubbingProgress && FlxG.mouse.justReleased) { state.seekPreview(FlxMath.bound((state.phiMouseX - progressLeft) / Math.max(1, progress.width), 0, 1)); scrubbingProgress = false; }
        if (state.songGroup.length > 0 && (lastSelected != FreeplayState.curSelected || lastDifficulty != FreeplayState.curDifficulty)) refreshSong();
        if (dirtyRows)
        {
            dirtyRows = false;
            var order = state.phiSongOrder; var index = order.indexOf(FreeplayState.curSelected);
            emptyList.visible = order.length == 0;
            play.alpha = order.length == 0 ? 0.4 : 1;
            var visibleCount = Std.int(Math.min(rows.length, order.length));
            var anchor = Std.int(Math.min(2, Math.max(0, visibleCount - 1)));
            var direction = displayedIndex < 0 ? 0 : index == displayedIndex + 1 ? 1 : index == displayedIndex - 1 ? -1 : 0;
            var ids:Array<Int> = [];
            var slots:Array<Int> = [];
            for (slot in 0...rows.length) {
                var position = index + slot - anchor;
                if (position >= 0 && position < order.length) { ids.push(order[position]); slots.push(slot); }
            }
            // Preserve row identity so existing songs slide to their new slots.
            var available = rows.copy();
            for (j in 0...ids.length)
            {
                var id = ids[j];
                var slot = slots[j];
                var rowY:Float = 270 + (slot - anchor) * 52 + (slot > anchor ? 48 : 0);
                var row:PhiSongRow = null;
                for (candidate in available) if (candidate.songId == id) { row = candidate; break; }
                if (row == null) for (candidate in available) if (ids.indexOf(candidate.songId) < 0) { row = candidate; break; }
                available.remove(row);
                row.visible = true;
                row.setSong(state, id, id == FreeplayState.curSelected, 168 - (rowY - 270) * PhiPanel.SLOPE, rowY, direction);
            }
            for (row in available) row.visible = false;
            displayedIndex = index;
            selectionBand.visible = selectionIcon.visible = order.length > 0;
            selectionBadge.visible = order.length > 0 && FreeplayState.curDifficulty >= 0;
            for (item in badgeNames) item.visible = selectionBadge.visible;
            for (item in badgeValues) item.visible = selectionBadge.visible;
            updateSelectedBadge();

            var thumbHeight:Float = Math.max(92, 548 * Math.min(1, rows.length / Math.max(1, order.length)));
            var startRatio:Float = order.length <= 1 ? 0 : index / (order.length - 1);
            var thumbOffset = (548 - thumbHeight) * startRatio;
            listScrollThumb.setPosition((35 + (548 - thumbOffset) * PhiPanel.SLOPE) * DENSITY, (130 + thumbOffset) * DENSITY);
            listScrollThumb.scale.y = thumbHeight * DENSITY / Math.cos(Math.PI / 12);
            counter.text = StringTools.lpad(Std.string(index + 1), '0', 2) + '  /  ' + StringTools.lpad(Std.string(order.length), '0', 2) + ' ' + textFor('tracks', '首曲目', 'TRACKS');
            sortValue.text = state.phiSortLabel;
        }
        var favorite = state.isPhiFavorite(FreeplayState.curSelected);
        if (favorite != lastFavorite) { lastFavorite = favorite; favoriteIcon.color = favorite ? 0xFFFFD54F : 0xFFBCC7D1; }
        for (tool in tools)
        {
            tool.panel.alpha = tool.panel.contains(state.phiMouseX, state.phiMouseY) ? 0.09 : 0;
            if (tool.action == 'favorites') tool.icon.color = state.phiFavoritesOnly ? 0xFFFFD54F : 0xFFDBE2E8;
            if (tool.action == 'audio') tool.icon.color = state.phiAudioVisible ? 0xFF98FFC0 : 0xFFB3BFC9;
        }
        profilePanel.alpha = profilePanel.contains(state.phiMouseX, state.phiMouseY) ? 1 : 0.9;
        var interactionsEnabled = !state.stopAll && !state.searchButton.hasFocus;
        hoverPanel(play, 0xFFFFFFFF, 0xFFE1F3FF, elapsed, interactionsEnabled && state.phiSongOrder.length > 0);
        hoverPanel(back, 0xFF131C25, 0xFF293B4D, elapsed, interactionsEnabled);
        hoverPanel(pitchUp, 0xFF161B25, 0xFF354B63, elapsed, interactionsEnabled);
        hoverPanel(pitchDown, 0xFF161B25, 0xFF354B63, elapsed, interactionsEnabled);
        hoverPanel(favoritePanel, 0xFF0B1019, 0xFF354B63, elapsed, interactionsEnabled);
        hoverPanel(sortPanel, 0xFF131C25, 0xFF293B4D, elapsed, interactionsEnabled && showTools);
        hoverPanel(mirror, ClientPrefs.data.flipChart ? 0xFF9A2432 : 0xFF1A202B,
            ClientPrefs.data.flipChart ? 0xFFBA4250 : 0xFF354B63, elapsed, interactionsEnabled);
        var recordMode = Std.string(state.replaySortMode);
        var selectedTab = recordMode.indexOf('DATE') == 0 ? 0 : recordMode.indexOf('SCORE') == 0 ? 1 : recordMode.indexOf('ACC') == 0 ? 2 : 3;
        for (i in 0...sortButtons.length) {
            var selected = i == selectedTab;
            sortButtons[i].alpha = selected ? 1 : interactionsEnabled && sortButtons[i].contains(state.phiMouseX, state.phiMouseY) ? 0.18 : 0;
        }
        for (item in difficulties) {
            item.color = 0xFF465A71;
            item.alpha = interactionsEnabled && item.contains(state.phiMouseX, state.phiMouseY) ? 0.14 : 0;
        }
        for (row in rows) if (row.visible) row.setHovered(interactionsEnabled && row.hit(state.phiMouseX, state.phiMouseY));
        var overProgress = interactionsEnabled && state.phiMouseX >= progressLeft && state.phiMouseX <= progressRight
            && Math.abs(state.phiMouseY - progress.y) < 18;
        progressThumb.color = overProgress || scrubbingProgress ? 0xFF9ADFFF : FlxColor.WHITE;
        mirrorText.text = textFor('mirror', '镜像', 'Mirror');
        var scrollLineX = (35 + 548 * PhiPanel.SLOPE) * DENSITY - (state.phiMouseY - 195) * PhiPanel.SLOPE;
        if (!state.stopAll && !state.searchButton.hasFocus && FlxG.mouse.justPressed && Math.abs(state.phiMouseX - scrollLineX) < 20 && state.phiMouseY >= 195 && state.phiMouseY < 1017)
        {
            scrollingThumb = true; dragging = false; dragMoved = true;
            thumbGrabOffset = state.phiMouseY >= listScrollThumb.y && state.phiMouseY < listScrollThumb.y + listScrollThumb.scale.y * Math.cos(Math.PI / 12)
                ? state.phiMouseY - listScrollThumb.y : listScrollThumb.scale.y * Math.cos(Math.PI / 12) / 2;
        }
        if (scrollingThumb && FlxG.mouse.pressed) {
            var travel = 822 - listScrollThumb.scale.y * Math.cos(Math.PI / 12);
            state.selectPhiScrollRatio(travel <= 0 ? 0 : FlxMath.bound((state.phiMouseY - 195 - thumbGrabOffset) / travel, 0, 1));
        }
        if (!scrollingThumb && !state.stopAll && !state.searchButton.hasFocus && state.phiMouseX > 115 && state.phiMouseX < 835 && state.phiMouseY > 210 && state.phiMouseY < 948)
        {
            if (FlxG.mouse.justPressed) { dragging = true; dragStartY = state.phiMouseY; dragMoved = false; }
            if (dragging && FlxG.mouse.pressed && Math.abs(state.phiMouseY - dragStartY) > 38)
            { state.stepPhiSong(state.phiMouseY < dragStartY ? 1 : -1); dragStartY = state.phiMouseY; dragMoved = true; }
        }
        if (FlxG.mouse.justReleased) { dragging = false; scrollingThumb = false; }
        super.update(elapsed);
    }

    function hoverPanel(panel:PhiPanel, base:FlxColor, hover:FlxColor, elapsed:Float, enabled:Bool):Void
    {
        var hovered = enabled && panel.contains(state.phiMouseX, state.phiMouseY);
        var target = hovered ? hover : base;
        if (hovered && FlxG.mouse.pressed) target = FlxColor.interpolate(target, 0xFF243647, 0.16);
        panel.color = FlxColor.interpolate(panel.color, target, 1 - Math.exp(-elapsed * 18));
    }
}

private class PhiSongRow extends FlxSpriteGroup
{
    public var songId:Int = -1;
    var title:PhiMarqueeText;
    var artist:PhiMarqueeText;
    var difficultySummary:FlxText;
    var scoreCaption:FlxText;
    var score:FlxText;
    var selected:Bool = false;
    var targetX:Float = 0;
    var targetY:Float = 0;
    var initialized:Bool = false;
    public function new()
    {
        super();
        title = new PhiMarqueeText(300); add(title);
        artist = new PhiMarqueeText(300); add(artist);
        difficultySummary = PhigrosFreeplayView.labelAt(20, 48, 300, '', 10, false, false, 0xFFCFD7DE); add(difficultySummary);
        scoreCaption = PhigrosFreeplayView.labelAt(232, 0, 90, PhigrosFreeplayView.textFor('bestScore', '最高分', 'Best score'), 11, false, true, 0xFFD6E0E5); add(scoreCaption);
        score = PhigrosFreeplayView.labelAt(232, 18, 90, '—', 15, false, true); add(score);
    }
    public function setHovered(hovered:Bool):Void { title.color = hovered && !selected ? 0xFFB9E7FF : FlxColor.WHITE; }
    public function setSong(state:FreeplayState, id:Int, active:Bool, px:Float, py:Float, direction:Int):Void
    {
        var replaced = songId != id;
        songId = id; selected = active; targetX = (px - (active ? 5 : 0)) * 1.5; targetY = py * 1.5;
        if (!initialized || replaced) {
            x = targetX - direction * 52 * PhiPanel.SLOPE * 1.5;
            y = targetY + direction * 52 * 1.5;
            initialized = true;
        }
        var song = state.songGroup[id];
        var names = state.phiDifficultyNames(id);
        var diff = Std.int(FlxMath.bound(FreeplayState.curDifficulty, 0, names.length - 1));
        var mapper = song._songCharter != null && diff < song._songCharter.length ? song._songCharter[diff] : 'N/A';
        title.setText(song.songNameSt, Paths.font(~/[^\x00-\x7F]/.match(song.songNameSt) ? 'Lang-ZH.ttf' : 'montserrat.ttf'), 33, FlxColor.WHITE, active);
        artist.setText(PhigrosFreeplayView.textFor('composer', '曲师', 'Composer') + ' ' + song.songMusican + '   ' + PhigrosFreeplayView.textFor('charter', '谱师', 'Charter') + ' ' + mapper, Paths.font('Lang-ZH.ttf'), 18, 0xFFCFD7DE);
        var best = Highscore.getScore(Paths.formatToSongPath(song.songNameSt), diff);
        score.text = best > 0 ? StringTools.lpad(Std.string(best), '0', 7) : '—';
        difficultySummary.text = ''; difficultySummary.visible = false;
        fitText(difficultySummary, 16, 13);
        title.setPosition(x + 20 * 1.5, y + (active ? 20 : 0) * 1.5);
        artist.setPosition(x + 20 * 1.5, y + (active ? 52 : 28) * 1.5);
        difficultySummary.setPosition(x + 20 * 1.5, y + (active ? 77 : 48) * 1.5);
        scoreCaption.setPosition(x + 232 * 1.5, y + (active ? 13 : 0) * 1.5);
        score.setPosition(x + 232 * 1.5, y + (active ? 32 : 18) * 1.5);
        alpha = 1;
    }
    static function fitText(text:FlxText, preferred:Int, minimum:Int):Void {
        text.size = preferred;
        while (text.size > minimum && text.textField.textWidth > text.fieldWidth - 8) text.size--;
    }
    public function hit(mx:Float, my:Float):Bool {
        return mx > x + 12 && mx < x + 615 && my >= y && my < y + (selected ? 144 : 96);
    }
    override public function update(elapsed:Float):Void
    {
        var blend = 1 - Math.exp(-elapsed * 30);
        x += (targetX - x) * blend; y += (targetY - y) * blend;
        super.update(elapsed);
        clipRect = new FlxRect(0, 0, 372 * 1.5, (selected ? 95 : 49) * 1.5);
    }
}

/** Artwork titles get the full safe width and two lines before falling back to a marquee. */
class PhiCoverTitle extends FlxSpriteGroup
{
    var wrapped:FlxText;
    var marquee:PhiMarqueeText;
    var lastValue:String;
    var lastFont:String;

    public function new(width:Int)
    {
        super();
        wrapped = new FlxText(0, 0, width, '', 48);
        wrapped.wordWrap = true;
        wrapped.antialiasing = ClientPrefs.data.antialiasing;
        add(wrapped);
        marquee = new PhiMarqueeText(width);
        marquee.visible = marquee.active = false;
        add(marquee);
    }

    public function setText(value:String, fontPath:String):Void
    {
        if (value == lastValue && fontPath == lastFont) return;
        lastValue = value; lastFont = fontPath;
        wrapped.setFormat(fontPath, 48, FlxColor.WHITE, LEFT);
        wrapped.bold = true;
        wrapped.text = value;
        // Use a modest size adjustment only when the two-line area really fills.
        while (wrapped.textField.numLines > 2 && wrapped.size > 36) wrapped.size -= 4;
        var fits = wrapped.textField.numLines <= 2;
        wrapped.visible = fits;
        marquee.visible = marquee.active = !fits;
        if (!fits) marquee.setText(value, fontPath, 36, FlxColor.WHITE, true);
    }
}

/** Fixed-size supersampled text window with the same continuous marquee as Mods rows. */
class PhiMarqueeText extends FlxSprite
{
    static inline final SS:Float = ModsMenuState.TXT_SS;
    static inline final GAP:Float = ModsMenuState.MARQ_GAP;
    var windowWidth:Int;
    var content:BitmapData;
    var loopWidth:Int = 0;
    var phase:Float = 0;
    var startDelay:Float = 0;
    var lastText:String;
    var lastFont:String;
    var lastSize:Int = -1;
    var lastColor:FlxColor;
    var lastBold:Bool;
    var lastItalic:Bool;

    public function new(logicalWidth:Float)
    {
        super();
        windowWidth = Std.int(Math.ceil(logicalWidth * SS));
        makeGraphic(windowWidth, 120, FlxColor.TRANSPARENT, true);
        scale.set(1 / SS, 1 / SS);
        origin.set(0, 0);
        offset.set(0, 0);
        antialiasing = ClientPrefs.data.antialiasing;
    }

    public function setText(value:String, fontPath:String, size:Int, color:FlxColor, bold:Bool = false, italic:Bool = false):Void
    {
        if (content != null && lastText == value && lastFont == fontPath && lastSize == size
            && lastColor == color && lastBold == bold && lastItalic == italic) return;
        lastText = value; lastFont = fontPath; lastSize = size;
        lastColor = color; lastBold = bold; lastItalic = italic;
        phase = 0;
        startDelay = 0.65;
        loopWidth = 0;
        if (content != null) { content.dispose(); content = null; }

        var pxSize = Std.int(Math.round(size * SS));
        var source:FlxText = italic
            ? new PhiItalicText(0, 0, 0, value, pxSize)
            : new FlxText(0, 0, 0, value, pxSize);
        source.setFormat(fontPath, pxSize, color, LEFT);
        source.bold = bold;
        source.antialiasing = ClientPrefs.data.antialiasing;
        source.textField.wordWrap = false;
        var raw = ModsMenuState.rasterizeBitmap(source);
        // Slight overflow is resolved with a small size adjustment; marquee
        // movement is reserved for labels that genuinely need extra width.
        if (raw.width > windowWidth && raw.width <= windowWidth * 1.35)
        {
            pxSize = Std.int(Math.max(1, Math.floor(pxSize * windowWidth / raw.width)));
            source.destroy();
            source = italic
                ? new PhiItalicText(0, 0, 0, value, pxSize)
                : new FlxText(0, 0, 0, value, pxSize);
            source.setFormat(fontPath, pxSize, color, LEFT);
            source.bold = bold;
            source.antialiasing = ClientPrefs.data.antialiasing;
            source.textField.wordWrap = false;
            raw = ModsMenuState.rasterizeBitmap(source);
        }
        if (italic && raw.width > 0 && raw.height > 0)
        {
            var skew = PhiPanel.SLOPE;
            var sheared = new BitmapData(raw.width + Std.int(Math.ceil(raw.height * skew)), raw.height, true, 0);
            var matrix = new Matrix();
            matrix.setTo(1, 0, -skew, 1, raw.height * skew, 0);
            sheared.draw(raw, matrix, null, null, null, true);
            content = ModsMenuState.padMarqueeBitmap(sheared);
            sheared.dispose();
        }
        else content = ModsMenuState.padMarqueeBitmap(raw);
        source.destroy();

        pixels.fillRect(pixels.rect, 0);
        var textWidth = content.width - Std.int(GAP * SS);
        if (textWidth > windowWidth)
        {
            loopWidth = content.width;
            ModsMenuState.blitWindowLoop(pixels, content, 0, windowWidth, Std.int(Math.min(pixels.height, content.height)));
        }
        else ModsMenuState.blitWindow(pixels, content, 0, windowWidth, Std.int(Math.min(pixels.height, content.height)));
    }

    override public function update(elapsed:Float):Void
    {
        if (loopWidth > 0 && content != null)
        {
            if (startDelay > 0) startDelay = Math.max(0, startDelay - elapsed);
            else {
                phase = (phase + elapsed * ModsMenuState.MARQ_SPEED * SS) % loopWidth;
                ModsMenuState.blitWindowLoop(pixels, content, Std.int(phase), windowWidth, Std.int(Math.min(pixels.height, content.height)));
            }
        }
        super.update(elapsed);
    }

    override public function destroy():Void
    {
        if (content != null) { content.dispose(); content = null; }
        super.destroy();
    }
}
