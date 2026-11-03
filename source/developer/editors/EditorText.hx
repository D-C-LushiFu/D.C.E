package developer.editors;

/**
 * 编辑器用 FlxText —— 本类现在只是"编辑器文本"的标记子类，**不再自己缩放字号**。
 *
 * 字号/描边缩放统一由 flixel 的 `FlxText.uiSizeScale` 完成（15 轮起）：
 *   编辑器进入高分辨率设计时 EditorInputStyle 会把它设为 uiScale(=1.5)，
 *   于是 **所有** FlxText（引擎 UI、输入框、下拉、以及 mods / hscript 直接 new 出来的文本）
 *   都按 1.5 倍字号光栅化 = 清晰，且与放大后的编辑器 UI 同尺寸；
 *   游戏本体（720 设计）恒为 1，完全无副作用。
 */
class EditorText extends FlxText
{
}
