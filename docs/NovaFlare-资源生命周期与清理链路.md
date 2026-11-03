# D.C.E. 资源生命周期与清理链路（2026-09-28 溯源）

> 目的：回答"**这些占用是从哪加载到哪的、GC/引擎怎么清、为什么从编谱器退回主菜单清不掉**"。
> 所有结论都带 `文件:行号`，行号按 UTF-8/LF 计数。

---

## 一、资源是怎么产生的（4 条路径，记账情况完全不同）

| # | 产生方式 | 键名形态 | 产生点 | **有没有人记账** |
|---|---|---|---|---|
| 1 | 文件素材：`Paths.image / getSparrowAtlas / inst / voices` | `assets/...png`、`mods/...ogg` | `source/general/backend/Paths.hx:559-564`（`FlxGraphic.fromBitmapData(bitmap,false,file)` + **`persist = true`** + `destroyOnNoUse = false` + `Cache.currentTrackedAssets.set(file, g)`） | ✅ 记进 `Cache.currentTrackedAssets` |
| 2 | `makeGraphic(w,h,color,true)` / `FlxG.bitmap.create(...,Unique=true)` | **`pixels<N>`** | `dependencies/flixel-5.9.0-main/flixel/system/frontEnds/BitmapFrontEnd.hx:135-138` → `getUniqueKey(null)`（`BitmapFrontEnd.hx:238-257`，baseKey 默认 `"pixels"`） | ❌ **完全没账本** |
| 3 | `FlxText` 渲染文本 | **`text<N>`** | `flixel/text/FlxText.hx:909-951`：`FlxG.bitmap.getUniqueKey("text")` + `makeGraphic(...)` —— 文本尺寸一变就换一个新键 | ❌ **完全没账本** |
| 4 | 引擎自建帧缓存 / 形状图 | `freeplay-card-placeholder:*`、`chart_white1px` 等 | `source/general/backend/Cache.hx:64-98`（`setFrame`）、`source/states/freeplayState/objects/song/SongRect.hx:136-169`、`source/developer/editors/ChartingState.hx:4529-4531` | ⚠️ 部分（`currentTrackedFrames` 只被 `clearStoredMemory` 遍历一次置 `persist=false`） |

**记账入口只有一个**：`source/general/backend/Cache.hx:15-24 trackLocalAsset(key)`，
而它**只被 `Paths.*` 调用**（路径 1）。路径 2/3 产生的图**任何人都不知道它们属于谁**。

---

## 二、释放是怎么走的（每条都有前置条件，条件不满足就永远不释放）

### 主通道：精灵销毁 → 引用计数归零 → 出缓存
```
FlxSprite.destroy()            dependencies/flixel-5.9.0-main/flixel/FlxSprite.hx:462-496   (graphic = null)
  └─ set_graphic(null)         flixel/FlxSprite.hx:1744-1760                                (旧图 decrementUseCount)
       └─ FlxGraphic.checkUseCount()   flixel/graphics/FlxGraphic.hx:616-620
            └─ useCount<=0 && destroyOnNoUse && !persist  →  FlxG.bitmap.remove(this)
```
**前置条件：该精灵必须真的被 `destroy()`**。

### 辅助通道：界面切换时的缓存清理
| 调用 | 实现 | 作用与**前置条件** |
|---|---|---|
| `Paths.clearStoredMemory()` | `source/general/backend/Paths.hx:49-108` | 遍历 `FlxG.bitmap._cache`，把**不在 `Cache.currentTrackedAssets`** 的图 `releaseGraphicWhenUnused()`（`Paths.hx:34-43`：只把 `persist=false; destroyOnNoUse=true`），然后 `Cache.resetLocalAssets()` 清空本界面清单。**只对"路径 1"的图有效**（路径 2/3 的 `pixels/text` 图虽然也会被置 `persist=false`，但没人会再去 decrement 它们的 useCount，所以仍留在缓存里） |
| `Paths.clearUnusedMemory()` | `Paths.hx:111-140` | 遍历 `currentTrackedAssets`，释放"非本地"的图。**只认路径 1 的账本** |
| `FlxG.bitmap.clearUnused()` | `BitmapFrontEnd.hx:382-392` | 清 `useCount<=0 && !persist && destroyOnNoUse` 的图。**引擎原本从未调用它**（本次修复才补上，见下） |

### 谁在什么时候调用这些清理
- `clearStoredMemory/clearUnusedMemory` 原本只在 **MainMenu / Freeplay / Options / Mods / Loading / Title / Achievements / 编辑器** 各自的 `create()` 里调用 —— **不是所有界面**，也没有统一的切换点。
- 本次修复新增：`source/general/backend/MusicBeatState.hx` 的 `installPreSwitchCleanup()`
  - `FlxG.signals.preStateSwitch` → `clearStoredMemory + clearUnusedMemory`
  - `FlxG.signals.postStateSwitch` → `ResourceLedger.sweepDeadOwners + mark(当前界面)`
  - 并在 `Paths.clearStoredMemory()` 末尾补了 **`FlxG.bitmap.clearUnused()`**（此前只有标记、没有回收动作）

---

## 三、为什么"编谱器 → 开发工具菜单 → 主菜单"清不掉（缺口定位）

按实测（大谱 BPM-2021，1139 段 / 32787 note）：

| 时点 | GC 堆 usage | reserved | graphics |
|---|---|---|---|
| 主菜单（基线） | 73~79MB | 80MB | **42** |
| 编谱器开着 | 113~155MB | — | 582 |
| ESC 试玩（EditorPlayState） | 640MB | 751MB | 577 |
| 退出编辑器回主菜单（**修复前**） | 106MB | 731MB | **304** |
| 退出编辑器回主菜单（**账本修复后**） | 88.7~93.6MB | 717MB | **122** |

### 缺口 1：`pixels<N>` / `text<N>` 没有任何账本（最主要）
- 产生点见上表路径 2/3；**没有任何 tracker 记录它们属于哪个界面**。
- 唯一释放路径是"持有它的精灵被 destroy"。而编谱器里大量精灵**不在 `state.members` 里**
  （放在自己的数组/Map/局部容器，或挂到相机上），`super.destroy()` 遍历 `members` 时**碰不到它们**
  → 它们持有的 `pixels/text` 图 `useCount` 永远 ≥1 → `clearUnused()` 永远不会清它。
- **这就是用户看到的"退出界面后 graphics 从 42 涨到 122/304、越切越多"**。
- 修法（本次已实现）：`source/developer/display/ResourceLedger.hx`
  - `begin(owner)`：界面 create 时记下"当前缓存键快照"作为基线；
  - `mark(owner)`：把"本界面期间新出现的键" + "本界面成员精灵持有的键"记成本界面所有，并给全局 `liveKeys[key]++`；
  - `releaseOwned(owner)`：界面 destroy 时，只释放 **本界面拥有、且 `liveKeys[key]==1`（别的存活界面没共用）** 的键。
  - 这样既补上了路径 2/3 的账本，又**不会误伤当前界面正在使用的文本图形**。

### 缺口 2：`persist = true` 阻断主通道
- 路径 1 的图被 `Paths.hx:560-561` 显式设成 `persist=true; destroyOnNoUse=false`，
  `checkUseCount()` 因此**永远不会**移除它们（`FlxGraphic.hx:618`）。
- 只能靠 `clearStoredMemory()` 把它们降级（`releaseGraphicWhenUnused`）。**如果某界面没调用它、或调用时机不对，这些图就一直留着**。

### 缺口 3：界面实例本身可能被钉住（导致其图 useCount 长期 >0）
- 实测：`ChartingState` 退出后仍被某个引用持有（`LeakProbe` 的 ALIVE 名单里持续出现），
  用它自己的精灵继续撑着那批图。
- 已排除的持有者（用 `NF_LEAK_DROP=1` 消去法逐个清空后判定）：全部类静态字段（含 Map 值、二层字段）、
  `FlxG` 全部信号、`FlxG.stage.__eventMap`、**lime window 全部输入信号**、`FlxG.plugins`、
  game/camera filters、全局脚本包、`PsychUIInputText`、图形缓存本身。
- 已修复的同类问题：`MusicBeatSubstate.instance` / `EditorPlayState.instance` 等**静态 self 引用**
  在 destroy 时没置空 → 永久钉住最后一个子状态（试玩会为整谱建出 32787 个 Note 精灵，
  这一条引用就值 **600MB**）→ 修法 `MusicBeatState.clearStaticSelfRefs(this)`（按类链反射清 `instance`）。
  实测：退出试玩后 GC 堆 685MB → **171MB**。
- **仍待定位**的那一个持有者不在上述任何一类里，需要更底层的手段（见第五节）。

---

## 四、GC 侧：为什么 usage 掉回去了、`reserved`/进程内存却不降

- 引擎 GC 接口：`source/general/backend/gc/GCManager.hx`
  - legacy 构建：`__hxcpp_collect(major)`（`GCManager.hx:68`）、`__hxcpp_gc_compact()`（`GCManager.hx:94`）
  - 指标索引：`Immix.cpp:265-269` —— `0=usage 1=reserved 2=current 3=large 4=process`
- 实测现象：退出大场景后 `usage` 已从 640MB 回到 89MB，但 **`reserved` 卡在 720~750MB**，
  `process`（工作集）也就一直在 1GB —— **说明那 ~650MB 是 Immix 预留但没归还操作系统的空闲堆**，
  不是"活对象泄漏"。
- `__hxcpp_gc_compact()` 实现见 `.haxelib/hxcpp/4,3,2/src/hx/gc/GcCommon.cpp:86-96`：
  反复 `InternalCollect(major, forceCompact)`；归还逻辑在 `Immix.cpp:5413-5438`，
  **只归还"完全空的 block group"**（`releaseEmptyGroups`）。
  3 万 Note 的分配尖峰把堆撑大后，活对象散布在各 block 里 → 没有足够完整空组可还 → reserved 只降了 ~20MB。
- 本次据此做了：`ResourceLedger.compactIfBloated()`（`reserved - usage > 阈值` 时才 compact），
  并把 Immix 保留策略调"抠门"（`setTargetFreeSpacePercentage(20)`、`setMinimumFreeSpace(8MB)`）。
  **注意**：这是治标；治本是**别让堆出现那种尖峰**（见第六节建议 1）。

---

## 五、仍然没解决的 / 下一步怎么查

1. **编谱器实例退出后仍被持有**（缺口 3 的残留那一个）。已排除的类别见上；建议的下一步：
   - 构建一个 `-debug`（HXCPP_DEBUG 打开 `__hxcpp_gc_trace`）版本，用它按类型点数 + 打印实例，
     能直接看出"谁还活着"；
   - 或给 hxcpp 加一个"反向引用查询"接口（`hx::Class` 注册表已经存在，
     `hxcpp/…/src/hx/Class.cpp:12-53` 的 `sClassMap` 就是全类表，可加 `__hxcpp_who_refs(obj)` 做堆扫描）。
2. **`reserved` 不归还**：需要 GC 层手段（更激进的 compact 策略 / 或换回 NovaGC 配置验证），
   以及减少分配尖峰（下一条）。
3. **分配尖峰本身**：`EditorPlayState`（ESC 试玩）会为**整首谱**一次性 `new Note(...)`，
   32787 note ≈ 600MB Haxe 对象。编谱器主界面有"渲染窗口虚拟化"（`secBgCache/secNoteCache` + `refreshRenderWindow`），
   但**试玩没有**。建议试玩也走同一套窗口虚拟化 / 音符对象池 —— 这能从根上把 1GB 峰值压到几百 MB。
4. **`pixels<N>` / `text<N>` 的账本**已由 `ResourceLedger` 补上；若后续还有残留，
   优先看"是不是又出现了新的匿名图产生点"（任何 `FlxG.bitmap.create(...,true)` / `getUniqueKey(...)` 调用点都得纳入账本）。

---

## 六、本次改动索引（与本主题相关）

| 文件 | 改动 |
|---|---|
| `source/developer/display/ResourceLedger.hx` | **新增**：按界面归属的图形账本（begin/mark/releaseOwned）+ `compactIfBloated`（让 GC 归还空闲堆） |
| `source/general/backend/MusicBeatState.hx` | 统一清理钩子（preStateSwitch 清缓存 / postStateSwitch mark 账本）、destroy 时 `releaseOwned` + `compactIfBloated`、`clearStaticSelfRefs`、`PsychUIInputText.releaseOwnedBy` |
| `source/general/backend/MusicBeatSubstate.hx` | destroy 末尾清静态 self 引用 + 账本回收 + 输入框兜底 |
| `source/general/backend/Paths.hx` | `clearStoredMemory()` 末尾补 `FlxG.bitmap.clearUnused()`（此前只标记不回收） |
| `source/developer/editors/ChartingState.hx` | 释放自有音轨/全局音轨回菜单曲、waveform/minimap 降级可回收、缓存放引用 |
| `source/developer/editors/EditorPlayState.hx` | 清静态 self 引用、`Note.clearFollow`、释放三条音轨 |
| `source/games/PlayState.hx` | 释放 vocals/opponentVocals/inst、清 `FlxG.sound.music.onComplete` 闭包、`Note.clearFollow` |
| `source/games/objects/Note.hx` | `clearFollow/clearFollowStale`（静态回引用收口） |
| `source/general/backend/ui/PsychUIInputText.hx` | 存活实例登记表 + `releaseOwnedBy/releaseAll`（它往全局 stage/window 挂实例方法监听） |
| `source/developer/display/DebugMonitor.hx` | **新增**：FPS/内存/当前界面 .hx/按键/鼠标采集；F3 开关写盘、F4 导出 `DebugEditor.erdb`、F7 安全回收 |
| `_dsh_tools/debug_monitor.ps1` | **新增**：屏幕外面的监控面板（贴游戏窗口右侧，读 `debug_live.json`，一键请求导出 .erdb） |
| `_dsh_tools/leakrun.ps1` | 支持 `-Mode editor|fselect|cycle|restart|gameplay`、`-Chart 模组\|歌曲\|谱面`、`-Selects`、`-StaySeconds` |
