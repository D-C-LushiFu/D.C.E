# D.C.E. 编辑器功能差距审查与实机检查

审查对象：`E:\D.C.E` 的八个编辑器入口，以及 Week 的 Freeplay 子页面。
参考对象：`C:\Users\Admin1\Desktop\Funkin-0.8.6` 的本地官方源码。没有复制官方实现或替换 D.C.E. 的数据格式、渲染器和界面。

## 官方参考的适用范围

- Chart Editor 有命令式撤销/重做、选择与批量操作、试玩、备份和导入导出流程。证据：[ChartEditorState.hx](C:/Users/Admin1/Desktop/Funkin-0.8.6/source/funkin/ui/debug/charting/ChartEditorState.hx:992)、[commands](C:/Users/Admin1/Desktop/Funkin-0.8.6/source/funkin/ui/debug/charting/commands/ChartEditorCommand.hx)。
- Stage Editor 有对象与角色编辑、撤销/重做、复制/粘贴、查找对象、最近文件和自动备份。证据：[UndoRedoHandler.hx](C:/Users/Admin1/Desktop/Funkin-0.8.6/source/funkin/ui/debug/stageeditor/handlers/UndoRedoHandler.hx:10)、[StageEditorState.hx](C:/Users/Admin1/Desktop/Funkin-0.8.6/source/funkin/ui/debug/stageeditor/StageEditorState.hx:880)。
- 角色动画参考是 [DebugBoundingState.hx](C:/Users/Admin1/Desktop/Funkin-0.8.6/source/funkin/ui/debug/anim/DebugBoundingState.hx)，提供动画/偏移和图集观察，不能当作与 D.C.E. 角色编辑器完全对应的产品。
- 官方 [ConversationDebugState.hx](C:/Users/Admin1/Desktop/Funkin-0.8.6/source/funkin/ui/debug/dialogue/ConversationDebugState.hx:9) 是对白播放调试场景。Week、菜单角色、对话立绘、Note Splash 在这份源码中没有直接对应的完整作者工具；这些入口按 D.C.E. 自己的数据模型审查。

## 逐项结论与本轮改进

| 编辑器 | 当前已有的主要能力 | 本轮发现并处理的缺口 |
| --- | --- | --- |
| Chart | 放置/删除/移动音符与事件，持续音、小节属性、复制/镜像、试玩、自动保存 | 完整文档历史的恢复与控件同步，包含格式/引擎选择和新增小节；修复 Ctrl+Shift+Z 同时重做和撤销；不同字段的编辑不再误合并；退出提醒；保存回调与本地 OpenFL 一致；历史面板阻止缩略图误触 |
| Character | 动画添加/删除、帧索引、偏移、位置、缩放、图像、图标颜色、Ghost | 把单次偏移撤销扩展为完整角色数据历史，提供重做和历史窗口；退出和切换角色保护 |
| Stage | 舞台数据、角色/对象位置、对象创建/复制/删除/排序、相机、质量过滤、动画与资源输出 | 替换不完整的 JSON 撤销栈；记录实际对象数据并提供重做/历史；恢复时运行分步加载；修复一帧两次更新与浮层阻塞恢复；保存状态按文档内容判断 |
| Week | Story 字段、歌曲列表、角色、背景、解锁条件、难度、文件导入导出 | 添加历史与未保存退出保护；Story/Freeplay 共用同一时间线，跨页面仍可撤销；恢复时立即定位歌曲卡片并保持历史面板在上层；保存取消不清除修改状态 |
| Menu Character | 菜单角色预览、图片、动画名、翻转、缩放、偏移、导入导出 | 添加完整配置历史、重做与历史窗口，以及退出和导入前的修改保护 |
| Dialogue | 白文/速度/声音/角色/表情、增删行、预览、导入导出 | 添加完整对白文件历史；复制当前行的全部属性、上移/下移当前行；退出和载入保护依据实际内容 |
| Dialogue Portrait | 图片、位置、缩放、左右布局、循环/待机动画与偏移、Ghost | 添加完整立绘文件历史、重做与历史窗口；退出和载入保护依据实际内容 |
| Note Splash | 动画与帧索引、FPS、偏移、RGB/像素设置、复用预览、TXT 转换与导出 | 添加历史、退出保护和经过结构校验的 JSON 配置导入；保持当前图集；TXT 转换不会把正在编辑的配置误标为已保存 |

共享控件通常位于画面右下角，Week 两个页面位于右上方，避免遮挡表单。工具条提供修改状态、撤销、重做和历史入口。快捷键为 Ctrl+Z、Ctrl+Y / Ctrl+Shift+Z、Ctrl+H，其他编辑器另支持 Ctrl+S 保存。输入框具有焦点时，文档快捷键不抢占文本输入。鼠标命中使用控件自己的 HUD 相机坐标，适用于缩放的舞台预览。历史最多保留 100 个状态；连续输入/拖动适当合并。历史保存在内存中，重新启动后不恢复。JSON 文档使用排序后的字段生成快照，避免恢复后仅因字段顺序变化就误判修改、丢失重做；Note Splash 在 JSON 对象与动画 Map 之间转换。

Chart 使用自己的动作标签与历史入口，其他编辑器通过 [EditorDocumentHistory.hx](E:/D.C.E/source/developer/editors/EditorDocumentHistory.hx) 记录小型作者文档。Stage 的恢复采用原有的分步销毁/加载流程，避免另建舞台渲染器。

新增可选桌面启动参数：`--editor=menu|chart|character|stage|week|week-freeplay|menu-character|dialogue|portrait|splash`，以及 `--editor-mod=<目录>`。它在正常初始化之后选择落点，可用于日常直接打开指定工具；不传参数时保留正常启动流程。

## 保存规则的本地证据

本地 OpenFL 桌面实现先调用 `File.saveBytes`，然后发 `Event.SELECT`：[FileReference.hx](E:/D.C.E/dependencies/openfl-9.5.0-main/src/openfl/net/FileReference.hx:1484)。因此编辑器的桌面保存完成回调使用 SELECT，其他平台沿用 COMPLETE。保存快照在弹出保存对话框前取得，取消和错误不会把文档标为已保存。Stage 保留已有的文件与资源输出方式。

## 后续可评估的功能

这些是更大的工作流扩展，本轮没有宣称达到官方全部功能的对等程度。

- Chart：多项框选/批量属性编辑、难度概览、最近文件与独立恢复备份。官方 FNFC 包格式与 D.C.E. 当前谱面格式不同，需要先定义兼容范围。
- Stage：按名称筛选/查找对象、最近文件与恢复备份、更多图集格式的可视配置。D.C.E. 已有对象列表和资源导入，仍可进一步改善大型舞台的定位体验。
- Character/Portrait/Splash：图集帧网格与缺失帧检查。现有帧索引与预览保留，需要结合 D.C.E. 的多键数与动画资源格式设计。

## 构建与实机证据

构建命令：`cmd /c tools\build-credits-preview.cmd`。使用现有 Windows Release 验证目标和 `legacy_gc_compare` 参数；默认 NovaGC 路径没有在本轮进行性能/GC 回归。

实际进入八个入口，并检查 Week 的 Freeplay 页面。以下为对应代码版本的可见交互证据，v2 截图为修复稳定 JSON 比较后的版本；最终 HUD/Week 布局及 Chart 元数据恢复修正的复查另列。

| 页面 | 实机检查 | 证据 |
| --- | --- | --- |
| Chart | 放置两颗音符；Ctrl+Z 后数量 1；历史行切换恢复 0/2；回初始状态正常退出 | [v2-chart-undo.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-chart-undo.png)、[v2-chart-baseline.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-chart-baseline.png)、[v2-chart-jump.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-chart-jump.png)、[v2-chart-exit.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-chart-exit.png) |
| Character | idle 偏移 -5 → -6，撤销回 -5 且绿色状态，重做回 -6；历史行跳转 | [v2-character-undo.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-character-undo.png)、[v2-character-history.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-character-history.png) |
| Stage | 创建方块；Ctrl+Z 后方块消失且无待保存修改；Ctrl+Y 后方块重建；历史窗口打开时分步加载完成 | [v2-stage-square-undo.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-stage-square-undo.png)、[v2-stage-square-redo.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-stage-square-redo.png) |
| Week Story | 修改显示名称；撤销/重做；进入 Freeplay 后仍存在同一时间线 | [v2-week-undo.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-week-undo.png)、[v2-week-file-menu.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-week-file-menu.png) |
| Week Freeplay | 从 Story 带入历史；撤销回初始；修改 RGB 并保留历史；无歌曲的导入未替换当前三首歌曲 | [v2-week-freeplay-undo.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-week-freeplay-undo.png)、[v2-week-freeplay-history.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-week-freeplay-history.png)、[v2-week-invalid-retained.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-week-invalid-retained.png) |
| Menu Character | 位置 0 → -1，撤销回 0，历史重做按钮回 -1 | [v2-menu-character-baseline.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-menu-character-baseline.png)、[v2-menu-character-redo-button.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-menu-character-redo-button.png) |
| Dialogue | 复制当前行得到两行，撤销/重做；修改文本、下移后保持选择在第 2 行；实际保存并读取 JSON；取消/确认退出弹窗 | [v2-dialogue-duplicate-undo.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-dialogue-duplicate-undo.png)、[v2-dialogue-reordered.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-dialogue-reordered.png)、[v2-dialogue-saved.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-dialogue-saved.png)、[v2-dialogue-double-exit.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-dialogue-double-exit.png) |
| Dialogue Portrait | 待机偏移 -1 → -2，撤销回 -1 且绿色状态，重做回 -2 | [v2-portrait-undo.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-portrait-undo.png)、[v2-portrait-history.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-portrait-history.png) |
| Note Splash | 偏移 -58 → -59，撤销/重做；导入 auditBlue 配置后为 12/8、scale 1.2；拒绝无效动画配置并保留原文档；导入撤销/重做；实际保存；取消保存仍显示修改 | [v2-splash-history.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-splash-history.png)、[v2-splash-valid-config.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-splash-valid-config.png)、[v2-splash-rejected.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-splash-rejected.png)、[v2-splash-import-redo.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-splash-import-redo.png)、[v2-splash-save-cancel.png](E:/D.C.E/_build/editor-feature-audit/screenshots/v2-splash-save-cancel.png) |

实机导出 JSON：

- [dialogue-audit.json](E:/D.C.E/_build/editor-feature-audit/exports/dialogue-audit.json)：两行对白，第一行文本修改，第二行保留复制时的字段。
- [splash-audit.json](E:/D.C.E/_build/editor-feature-audit/exports/splash-audit.json)：auditBlue 的 FPS 22/26、偏移 12/8、noteData 1、scale 1.2，动画 Map 正常输出 JSON 对象。

Haxe 小型回归检查：稳定 JSON 的字段顺序/往返一致、实际改动可检测、数组顺序保留；Week 空歌曲列表、最小字段默认值、越界 RGB、损坏 JSON 和非法帧索引。均通过。验证类位于 `_build/editor-feature-audit/fixtures`，不参与游戏产品构建。

### 最终版本复查

最终 Windows Release 构建通过，时间 2026-10-12 14:03:06；[DCE.exe](E:/D.C.E/export/credits-preview/windows/bin/DCE.exe) 大小 64,436,736 字节，SHA-256：`149A86195384F52C657D4F3F67A49D001C0A4257FAED0C8F8DB28A6ACD878D4A`。

- Stage：直接点击右下角历史按钮可打开面板；点击初始/编辑行后方块消失/重建，状态绿色/黄色相应变化。[final-stage-undo.png](E:/D.C.E/_build/editor-feature-audit/screenshots/final-stage-undo.png)、[final-stage-redo.png](E:/D.C.E/_build/editor-feature-audit/screenshots/final-stage-redo.png)。
- Week：工具条移动到右上方，字段和保存入口完整可见。Story 的开始锁定修改进入 Freeplay 后仍可撤销；恢复后的三首歌曲卡片立即定位，历史窗口在卡片上方。[final-week-fields.png](E:/D.C.E/_build/editor-feature-audit/screenshots/final-week-fields.png)、[final-week-file.png](E:/D.C.E/_build/editor-feature-audit/screenshots/final-week-file.png)、[final-week-freeplay-history.png](E:/D.C.E/_build/editor-feature-audit/screenshots/final-week-freeplay-history.png)。
- Chart：两颗测试音符的历史窗口正常显示，打开历史面板没有误跳缩略图时间。切换引擎重新载入现有 Test 谱面后为 484 颗音符，撤销恢复两颗测试音符，重做再次恢复 484 颗；引擎/格式设置包含在快照中。[final-chart-history.png](E:/D.C.E/_build/editor-feature-audit/screenshots/final-chart-history.png)、[final-chart-engine-history.png](E:/D.C.E/_build/editor-feature-audit/screenshots/final-chart-engine-history.png)、[final-chart-engine-undo.png](E:/D.C.E/_build/editor-feature-audit/screenshots/final-chart-engine-undo.png)。
- Chart 实际保存：[chart-audit.json](E:/D.C.E/_build/editor-feature-audit/exports/chart-audit.json) 为 Test、484 音符、64 小节；保存后 Backspace 正常返回编辑器菜单。[final-chart-saved-exit.png](E:/D.C.E/_build/editor-feature-audit/screenshots/final-chart-saved-exit.png)。
- Ctrl+Z、Ctrl+Y 和鼠标历史操作已有实机证据。Ctrl+Shift+Z 的自动键盘注入未取得有效验证，列为未确认；该快捷键重复进入撤销分支的问题已在源码修复。
- 测试游戏已关闭。`funkin.sol` 与 `controls_v4.sol` 已恢复检查前备份，退出后再次核对 SHA-256 均一致。检查时段没有新增崩溃转储。


验证边界：没有穷举每个 mod、所有字段组合、TXT 转换、舞台资源打包输出、100 次历史上限和大谱面性能。历史只保存内存；本报告不宣称与官方所有编辑器工作流完全对等。启动更新检查的 SSL 错误不影响编辑器进入，本轮记录为非致命的既有网络路径现象。

构建日志：[build-final.log](E:/D.C.E/_build/editor-feature-audit/build-final.log)。
运行日志：`_build/editor-feature-audit/runtime-*.log`。
截图目录：`E:\D.C.E\_build\editor-feature-audit\screenshots`。
改动前的编辑器源码备份：`E:\D.C.E\_build\editor-feature-audit\baseline`。
