package developer.editors;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;

import general.backend.language.Language;

/**
 * Chart 编辑器底部状态栏。
 * 显示：Zoom | 时间(s) | mm:ss | Section | Beat | Snap | Move Note Mode
 *
 * 由 ChartingState 每帧通过 setStatus() 更新各字段值。
 * 为避免播放时每帧重绘导致的"文字抽搐/闪烁"，只在拼接后的整串文本
 * 与上一帧不同时才刷新 rootLabel.text。
 */
class ChartEditorStatusBar extends FlxSpriteGroup
{
	// D.C.E. 规范：状态栏 = 卡片面板背景 + 主/提示文字
	static final BG_COLOR:FlxColor = 0xFF1C1F28;
	static final TEXT_DIM:FlxColor = 0xFF86909C;
	static final TEXT_VAL:FlxColor = 0xFFF2F3F5;
	static final SEP_COLOR:FlxColor = 0x14FFFFFF;

	// ★ 十二轮：随设计分辨率缩放（720 设计时 = 25）
	public static var HEIGHT(get, never):Int;

	static function get_HEIGHT():Int return EditorInputStyle.si(25);

	var bg:FlxSprite;
	var rootLabel:FlxText;
	var sepText:String = '  |  ';

	// ★ 09-26 三轮：BF / Opp 各自的 note 数量统计（放在「移动音符模式」右边），
	//   颜色 = 各自角色 healthBarColor（与谱面网格同色）+ 1px 白色描边。
	var bfLabel:FlxText;
	var oppLabel:FlxText;
	/** ★ BF/Opp 右侧：→ = 全曲 note 总数；▲ = 全曲事件总数 */
	var totalLabel:FlxText;
	var evtLabel:FlxText;
	var bfNotes:Int = -1;
	var oppNotes:Int = -1;
	var totalNotes:Int = -1;
	var totalEvents:Int = -1;
	var bfColor:FlxColor = 0xFF3CA7E0;
	var oppColor:FlxColor = 0xFFD8556A;

	// 当前状态字段
	public var zoomStr:String = '1 / 1';
	public var tempoStr:String = '0.00s / 0.00s';
	public var clockStr:String = '0:00 / 0:00';
	public var sectionStr:String = '0';
	public var beatStr:String = '0';
	public var snapStr:String = '16th';
	public var moveStr:String = 'False';

	// 缓存上一帧的完整文本，用于判定是否需要重绘
	var _lastFullText:String = '';

	public function new()
	{
		super();
		bg = new FlxSprite().makeGraphic(FlxG.width, HEIGHT, BG_COLOR);
		add(bg);
		var topLine:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, 1, 0x14FFFFFF);
		topLine.y = 0;
		add(topLine);

		rootLabel = new EditorText(EditorInputStyle.sv(10), EditorInputStyle.sv(4), FlxG.width - EditorInputStyle.sv(20), '', 13);
		rootLabel.setFormat(Paths.font(ChartEditorMenuBar.langFont()), 13, TEXT_VAL, LEFT);
		add(rootLabel);

		bfLabel = makeCountLabel(bfColor);
		oppLabel = makeCountLabel(oppColor);
		totalLabel = makeCountLabel(TEXT_VAL, false);
		evtLabel = makeCountLabel(0xFFFFD24A, false);
		add(bfLabel);
		add(oppLabel);
		add(totalLabel);
		add(evtLabel);

		applyLang();
	}

	function makeCountLabel(col:FlxColor, outline:Bool = true):FlxText
	{
		var t:FlxText = new EditorText(0, EditorInputStyle.sv(4), 0, '', 13);
		// ★ 用户：BF/Opp 保留 1px 白描边；→/▶（note/事件总数）不要描边
		// ★ 这四个标签内容恒为 ASCII（BF/Opp/→/▶ + 数字）→ 按“纯 ASCII 文本”选字体（有 vcr 就用 vcr，mods 优先）
		var fnt:String = Paths.font(ChartEditorMenuBar.langFont('0'));
		if (outline)
		{
			t.setFormat(fnt, 13, col, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.WHITE);
			t.borderSize = 1;
		}
		else
		{
			t.setFormat(fnt, 13, col, LEFT);
		}
		return t;
	}

	public function applyLang():Void
	{
		rootLabel.font = Paths.font(ChartEditorMenuBar.langFont(''));
		bfLabel.font = Paths.font(ChartEditorMenuBar.langFont('0'));
		oppLabel.font = Paths.font(ChartEditorMenuBar.langFont('0'));
		// 语言切换强制刷新
		_lastFullText = '';
		refreshText();
	}

	public function setZoom(v:String) { zoomStr = v; refreshText(); }
	public function setTempo(v:String) { tempoStr = v; refreshText(); }
	public function setClock(v:String) { clockStr = v; refreshText(); }
	public function setSection(v:String) { sectionStr = v; refreshText(); }
	public function setBeat(v:String) { beatStr = v; refreshText(); }
	public function setSnap(v:String) { snapStr = v; refreshText(); }
	public function setMove(v:String) { moveStr = v; refreshText(); }

	/** ★ BF / Opp note 数量统计（颜色取各自角色 healthColor） */
	public function setNoteCounts(bf:Int, opp:Int, colBf:FlxColor, colOpp:FlxColor, totalN:Int = -1, totalE:Int = -1):Void
	{
		if (bf == bfNotes && opp == oppNotes && totalN == totalNotes && totalE == totalEvents
			&& colBf == bfColor && colOpp == oppColor) return;
		bfNotes = bf;
		oppNotes = opp;
		totalNotes = totalN;
		totalEvents = totalE;
		bfColor = colBf;
		oppColor = colOpp;
		layoutCountLabels();
	}

	function layoutCountLabels():Void
	{
		if (bfLabel == null || oppLabel == null) return;
		var sBf:String = 'BF ' + bfNotes;
		var sOpp:String = 'Opp ' + oppNotes;
		if (bfLabel.text != sBf) bfLabel.text = sBf;
		if (oppLabel.text != sOpp) oppLabel.text = sOpp;
		bfLabel.color = bfColor;
		oppLabel.color = oppColor;
		// 位置：主文本右边（即「移动音符模式：…」之后），主文本变化后需要重排
		// ★ → note 总数 / ▲ 事件总数（放在 BF/Opp 右侧）
		var sTotal:String = '→ ' + totalNotes;
		var sEvt:String = '▶ ' + totalEvents;
		if (totalLabel.text != sTotal) totalLabel.text = sTotal;
		if (evtLabel.text != sEvt) evtLabel.text = sEvt;
		totalLabel.color = TEXT_VAL;
		evtLabel.color = 0xFFFFD24A;

		var mainW:Float = (rootLabel != null && rootLabel.textField != null) ? rootLabel.textField.textWidth : 0;
		var x:Float = EditorInputStyle.sv(10) + mainW + EditorInputStyle.sv(22);
		bfLabel.x = x;
		oppLabel.x = x + bfLabel.width + EditorInputStyle.sv(16);
		totalLabel.x = oppLabel.x + oppLabel.width + EditorInputStyle.sv(18);
		evtLabel.x = totalLabel.x + totalLabel.width + EditorInputStyle.sv(18);
	}

	function refreshText():Void
	{
		var parts:Array<String> = [
			Language.get('status_zoom', 'charting') + ' ' + zoomStr,
			'',
			tempoStr,
			clockStr,
			Language.get('status_section', 'charting') + ' ' + sectionStr,
			Language.get('status_beat', 'charting') + ' ' + beatStr,
			Language.get('status_snap', 'charting') + ' ' + snapStr,
			Language.get('status_move', 'charting') + ' ' + moveStr,
		];
		var full = parts.join('  |  ');
		// 只有文本真的变了才改 text 字段，否则 FlxText 每帧都会重建纹理，看起来就像在抽搐
		if (full != _lastFullText)
		{
			_lastFullText = full;
			// ★ 按这段文本选字体：纯 ASCII → vcr（mods 优先）；含中文等 → 回退语言字体
			var fPath:String = Paths.font(ChartEditorMenuBar.langFont(full));
			if (rootLabel.font != fPath)
				rootLabel.setFormat(fPath, 13, TEXT_VAL, LEFT);
			rootLabel.text = full;
			layoutCountLabels();
		}
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);
		this.y = ChartEditorMenuBar.BAR_HEIGHT;
	}
}
