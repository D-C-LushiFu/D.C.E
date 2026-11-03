# Chart Editor 调试记录（2026-10-13）

## 本轮修改

- 编辑器采用 1920×1080 逻辑画布，按实际窗口大小缩放。1280×720 窗口完整显示画布。
- 编辑器移动按键独立于游戏内移动控制开关，在状态更新前注入按键；菜单及历史面板打开时暂停网格按键输入。
- 调试面板快捷键改为 Ctrl+F3；Chart Editor 的 F3 保留事件菜单功能。
- 撤销、重做、历史记录合并进顶部栏，移除独立操作条及额外保存按钮。
- 历史面板默认关闭，支持点击、关闭、拖动，关闭再打开保留当前位置。
- 音符及波形覆盖当前缩放下的可见时间范围；点击编辑按音符所属小节查找数据。
- 波形重建使用独立透明位图，修复 Z 再 X 后的黑色矩形。
- 【歌曲 → 引擎】改为显示当前版本的下拉选择：Pe-0.7.3 / Pe-1.0.4。选择纳入撤销历史，取消原先点击按钮就重载原谱的行为。
- 编谱器的显示、计数、选中及删除统一遵循当前引擎的 lane 语义，与 ESC 试玩一致。1.0.4 的归属不随 mustHitSection 翻转；旧格式随小节归属翻转。
- psych_v1_convert 明确按旧格式读取，避免保存后重载误判为 1.0。
- 重载自定义难度后，从实际谱面文件名回填【难度】，避免下一次保存丢失难度后缀。

## 编译

- 成功退出码：0。
- 构建命令：`tools/build-credits-preview.cmd`。
- 构建日志：`_build/editor-mobile-audit/build-final.log`。
- 可执行文件：`export/credits-preview/windows/bin/DCE.exe`。
- 构建时间：2026-10-13 00:37:10，大小 64,487,936 字节。
- SHA256：E634E7C31D64D76F08E369907AE303AB6F231BF0A165BB9B4DBC9A5906B50E95。
- 使用现有预览构建的 legacy_gc_compare 配置；本次未交付 Android 构建，也未替换默认发布目录的可执行文件。

## 游戏内验证

证据目录：`_build/editor-mobile-audit/screenshots/`。

| 检查 | 实测结果 | 证据 |
| --- | --- | --- |
| 初次打开的完整视口 | 1280×720 客户区完整显示 1920×1080 逻辑界面 | final-difficulty-focus.png、运行日志 EditorResolution |
| 难度 hard 保存 | 原生对话框默认 test-hard.json；实际桌面文件含 484 音符 | hard-entered.png、hard-save-default.png |
| 难度 expert 保存 | 原生对话框默认 test-expert.json；实际桌面文件含 484 音符 | expert-entered.png、expert-save-default.png |
| hard / expert 重载 | 原样副本从测试版资源目录载入；484 音符，难度文本分别保留 | final-hard-reload.png、final-expert-reload.png |
| 桌面 test.json 可用性 | 原样副本载入，485 音符，BF 224 / Opp 261 | final-desktop-test-reload.png |
| 4/1 可见范围及 Z→X | 26.07 秒处有跨小节音符和波形；切换后无黑块 | final-zoom-4to1.png、final-ZX.png |
| Pe-0.7.3 的 ESC 归属 | 编辑器与试玩均 BF 223 / Opp 261 | final-preview-073.png、runtime-final-evidence.log |
| Pe-1.0.4 的 ESC 归属 | 编辑器与试玩均 BF 421 / Opp 63 | final-engine-selected.png、final-preview-104.png、runtime-final-evidence.log |
| 引擎设置撤销 / 重做 | 恢复旧版本与新版本对应计数 | final-engine-undo.png、final-engine-redo.png |
| 顶部历史入口、面板移动 | 点击打开；拖动到左侧；关闭再打开保留位置 | final-chart-history.png、final-history-moved.png、final-history-position-kept.png |
| 可见的其他小节点击删除 | 484→483；移动撤销回 484；顶部重做回 483（较早构建） | chart-cross-section-before/after/undo/redo.png |

## 临时文件与设置

- 桌面 test.json、test-hard.json、test-expert.json 在校验哈希且成功重载后删除。
- 测试版资源目录内新增的 test-hard.json、test-expert.json、test-desktop.json 已删除。
- 测试证据副本保留在 `_build/editor-mobile-audit/exports/`，原始 test.json 未覆盖。
- 测试后恢复 prefs-final-baseline 中保留的 funkin.sol / controls_v4.sol，恢复后哈希一致。
- 原始资源 test/test.json 与测试版对应原始文件哈希一致：B69900DE9A97BE18B2F0D347C427175B0C96433E1D720E06C65B15B463778D36。

## 验证边界

- 上述为 Windows 可见窗口操作。Android 真机、多指触控、不同键数及 KeyChange 段未完成实机验证。
- 网格缩放仅改变时间轴，轨道宽度固定，因此某些比例下格子呈长方形；本轮未改为随时间缩放轨道宽度。
- 跨小节拖拽的自动化结果不稳定，尚不能记为通过；已验证的跨小节编辑路径是点击删除、撤销和重做。
- 其他编辑器本轮只做过 Character / Stage / Week 共享界面回归；未把它们记作全部完成移动端验证。
