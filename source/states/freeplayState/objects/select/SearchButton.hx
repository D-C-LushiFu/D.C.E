package states.freeplayState.objects.select;

class SearchButton extends FlxSpriteGroup {
	var bg:FlxSprite;
	public var search:PsychUIInputText;
	var tapText:FlxText;

	public var onSearchChange:String->Void;
	public var searchDelay:Float = 0.2;
	var timer:FlxTimer = null;
    var revealWidth:Int;
    var revealHeight:Int;
    public var reveal:Float = 1;

	public var hasFocus(get, never):Bool;

	public function new(x:Float, y:Float, width:Int = 490, height:Int = 45) {
		super(x, y);

        revealWidth = width; revealHeight = height;
        bg = new states.freeplayState.objects.PhiPanel(0, 0, width, height, 0xFF111B28);
        add(bg);
        search = new PsychUIInputText(24, (height - 32) / 2, width - 54, '', 28);
        search.bg.visible = false; search.behindText.alpha = 0;
        search.textObj.font = Paths.font('Lang-ZH.ttf'); search.textObj.antialiasing = true;
        search.textObj.color = FlxColor.WHITE; search.caret.color = FlxColor.WHITE;
		search.onChange = function(old:String, cur:String) {
			if (cur == '')
				tapText.visible = true;
			else
				tapText.visible = false;
			startSearch(cur);
		}
		search.unfocus = function() {
            if (FreeplayState.instance != null) FreeplayState.instance.searchJustUnfocused = true;
			if (search.text == '' || search.text == null) {
				tapText.visible = true;
				startSearch('');
			}
		}
		add(search);

		tapText = new FlxText(24, (height - 32) / 2, width - 54, Language.get('tapToSearch', 'freeplay'), 28);
		tapText.font = Paths.font(Language.get('fontName', 'main') + '.ttf');
		tapText.antialiasing = ClientPrefs.data.antialiasing;
		tapText.alpha = 0.6;
		tapText.color = FlxColor.WHITE;
		add(tapText);
	}

	function get_hasFocus():Bool {
		return PsychUIInputText.focusOn == search;
	}

	public function focusSearch() {
        FlxTween.cancelTweensOf(this);
        reveal = 0;
        FlxTween.tween(this, {reveal: 1}, 0.22, {ease:FlxEase.quadOut});
		PsychUIInputText.focusOn = search;
	}

	public function unfocusSearch() {
		if (PsychUIInputText.focusOn == search) {
			PsychUIInputText.focusOn = null;
            if (FreeplayState.instance != null) FreeplayState.instance.searchJustUnfocused = true;
		}
	}

	public function startSearch(text:String) {
		if (timer != null) timer.cancel();
		timer = new FlxTimer().start(searchDelay, function(tmr:FlxTimer) {
			if (onSearchChange != null)
				onSearchChange(text);
		});
	}

	public function changeLanguage() {
		tapText.text = Language.get('tapToSearch', 'freeplay');
		tapText.font = Paths.font(Language.get('fontName', 'main') + '.ttf');
		search.textObj.font = Paths.font(Language.get('fontName', 'main') + '.ttf');
	}
    override public function update(elapsed:Float):Void {
        clipRect = new flixel.math.FlxRect(0, 0, Math.max(1, revealWidth * reveal), revealHeight);
        super.update(elapsed);
    }
    override public function destroy():Void {
        if (timer != null) timer.cancel();
        FlxTween.cancelTweensOf(this);
        onSearchChange = null;
        super.destroy();
    }
}
