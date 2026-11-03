package options.objects.others;

/**
 * 顶部工具栏右侧的重置按钮。深色实底和白字保证它从背景中分离，
 * 鼠标悬停时切换成浅色强调态，避免按钮与工具栏或主面板叠在一起时变暗。
 */
class ResetButton extends FlxSpriteGroup
{
	/** 常态底色（深色顶栏上保持低调但清晰可见） */
	inline static var IDLE_BG:Float = 0.94;
	/** 悬停底色（原型 .pclose:hover） */
	inline static var HOVER_BG:Float = 0.16;
	/** 二次确认时的底色（同族强调色） */
	inline static var CONFIRM_BG:Float = 0.22;
	inline static var IDLE_TEXT:Int = 0xFFFFFF;
	inline static var HOVER_TEXT:Int = 0xFFFFFF;
	inline static var CONFIRM_TINT:Int = 0xFF90DC;

	var rect:Rect;
	var text:FlxText;

	/** 当前的底色 alpha（由悬停/确认状态决定，再乘上淡入淡出系数） */
	var bgAlpha:Float = IDLE_BG;
	/** 内容整体淡入淡出系数 */
	var fade:Float = 1;

	var waitingForConfirm:Bool = false;
	var confirmTimer:Float = 0;

	public function new(x:Float, y:Float, width:Float, height:Float)
	{
		super(x, y);

		rect = new Rect(0, 0, width, height, height / 3, height / 3, 0x111821, IDLE_BG);
		add(rect);

		text = new FlxText(0, 0, 0, Language.get('Reset'), Std.int(height * 0.48));
		text.font = Paths.font(Language.get('fontName', 'main') + '.ttf');
		text.antialiasing = ClientPrefs.data.antialiasing;
		text.color = IDLE_TEXT;
		text.x += rect.width / 2 - text.width / 2;
		text.y += rect.height / 2 - text.height / 2;
		add(text);
	}

	public var onFocus:Bool = false;

	/**
	 * 内容淡入淡出。
	 * ★ 不要用 `FlxTween.tween(this, {alpha: v})` —— FlxSpriteGroup 的 alpha 会把
	 *   变化比例乘到子元素上，还会把 alpha==0 的子元素写成 1/比例，一块 0.045 的
	 *   底板会被放大成不透明的白块（详见 Option.setFade 的长注释）。
	 */
	public function setFade(v:Float):Void
	{
		fade = v;
		rect.alpha = bgAlpha * v;
		text.alpha = v;
	}

	function getConfirmText():String
	{
		var t = Language.get('ResetConfirm', 'options');
		// Fallback if translation key doesn't exist
		if (t == 'ResetConfirm' || t == 'ResetConfirm (404)')
			t = 'Sure?';
		return t;
	}

	function getResetText():String
	{
		return Language.get('Reset');
	}

	function updateTextDisplay(newText:String)
	{
		text.text = newText;
		text.x = rect.x + rect.width / 2 - text.width / 2;
		text.y = rect.y + rect.height / 2 - text.height / 2;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		var mouse = OptionsState.instance.mouseEvent;

		onFocus = mouse.overlaps(this);

		if (waitingForConfirm)
		{
			confirmTimer += elapsed;
			if (confirmTimer > 2.0)
			{
				waitingForConfirm = false;
				confirmTimer = 0;
				updateTextDisplay(getResetText());
			}
		}

		if (onFocus)
		{
			rect.color = waitingForConfirm ? CONFIRM_TINT : 0xFFFFFF;
			bgAlpha = waitingForConfirm ? CONFIRM_BG : HOVER_BG;
			text.color = HOVER_TEXT;
			if (mouse.justReleased)
			{
				if (!waitingForConfirm)
				{
					waitingForConfirm = true;
					confirmTimer = 0;
					updateTextDisplay(getConfirmText());
				}
				else
				{
					waitingForConfirm = false;
					confirmTimer = 0;
					updateTextDisplay(getResetText());
					OptionsState.instance.resetData();
				}
			}
		}
		else
		{
			rect.color = 0x111821;
			bgAlpha = IDLE_BG;
			text.color = IDLE_TEXT;
			if (waitingForConfirm)
			{
				waitingForConfirm = false;
				confirmTimer = 0;
				updateTextDisplay(getResetText());
			}
		}

		rect.alpha = bgAlpha * fade;
	}

	public function changeLanguage()
	{
		waitingForConfirm = false;
		confirmTimer = 0;
		text.text = Language.get('Reset');
		text.setFormat(Paths.font(Language.get('fontName', 'main') + '.ttf'), Std.int(rect.height * 0.48), IDLE_TEXT);
		text.borderStyle = NONE;
		text.antialiasing = ClientPrefs.data.antialiasing;
		text.x = rect.x + rect.width / 2 - text.width / 2;
		text.y = rect.y + rect.height / 2 - text.height / 2;
	}
}
