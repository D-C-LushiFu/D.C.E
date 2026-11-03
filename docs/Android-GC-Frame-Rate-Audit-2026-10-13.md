# Android GC 与 60FPS 限制排查

日期：2026-10-13。设备：Redmi K70，23113RKC6C，Android 16。

## 结论与边界

本次测量支持：D.C.E. 持续无法超过 60 的主要约束在手机的显示策略上。尚未找到 MIUI 为 D.C.E. 选择 60Hz 上限的具体内部规则，尚未修复这个上限。

GC 有可测量的停顿，可能影响个别帧；数据不支持把持续锁 60 归因于 GC 每帧阻塞。不能据此宣称所有歌曲、Mod、长时间运行的 GC 性能都正常。

用户补充电脑上没有同样限制。本轮集中检查 Android；没有重新编译或测试 Windows。

## 实测：绘制上限与系统呈现

使用 SurfaceFlinger TimeStats 的同一 SurfaceView 帧数差值除以采样时长，不用游戏面板的绘制请求次数代替实际呈现。短窗口、两次 dumpsys 取样边界有少量误差，60.28 等读数代表约 60，而非解除了限制。

| 应用/条件 | 帧数增量 | 采样秒数 | 实际呈现 FPS |
| --- | ---: | ---: | ---: |
| 旧 NF：com.NovaFlareEngine | 485 | 8.078 | 约 60.04 |
| 新 NF：com.NovaFlareEngineNew | 485 | 8.078 | 约 60.04 |
| D.C.E.，独立渲染线程关闭，绘制上限 2000 | 485 | 8.063 | 约 60.15 |
| D.C.E.，重新开启独立渲染线程 | 421 | 8.063 | 约 52.21 |
| D.C.E.，绘制上限 24 | 193 | 8.047 | 约 23.98 |
| D.C.E.，绘制上限 120 | 486 | 8.063 | 约 60.28 |
| D.C.E.，恢复绘制上限 2000、独立渲染线程开启 | 484 | 8.063 | 约 60.03 |

线程开关期间低于 60 的样本不能用于断言渲染线程普遍降低性能；这是当前设置界面的短时样本。但两种模式都没有解除系统 60 上限。

24/120 的设置值由截图及 DCE-Display 日志确认。120 时日志明确记录：

```text
surfaceFrameRate=120.0
renderCap=120 requestedMode=2 refresh=120.00001 current=60.000004
```

24 的实测说明绘制上限可以降低实际呈现；120/2000 的样本说明提高引擎上限尚不能突破系统限制。

两次最初从滑条中部发起的拖动没有改变 2000 设置，已作废其“最低上限”解释。有效测试从滑块把手开始拖动，并再次核对设置值。`dce-cap-minimum*` 文件只保留调试过程；有效证据为 `dce-cap24-verified*` 与 `dce-cap120-verified*`。

## 实测：系统策略的区别

| 当前前台应用 | PRIORITY_MIUI_REFRESH_RATE 上限 | 本轮部分样本的额外温控上限 |
| --- | ---: | ---: |
| D.C.E. | 60 | 60 |
| 旧 NF | 120 | 60 |
| 新 NF | 120 | 60 |

本轮两个 NF 的实际呈现均约 60，不能用这轮有温控限制的样本否认用户观察到它们能跑 120+。测试按用户要求继续进行，没有等待降温，也没有关闭系统温控。

D.C.E. 的标题页样本还出现了 **没有当前温控 vote、只有 MIUI 最大 60** 的情况；因此不能把 D.C.E. 的全部问题归因于温度。

其他核实项：

- `debug.graphics.game_default_frame_rate.disabled=true`，用户的“停止游戏默认帧率”已经开启。
- Android GameManager 对 D.C.E.、新 NF 均返回 `No intervention found`。
- D.C.E. 窗口请求的基本模式为 120，系统当前呈现仍为 60。
- 普通应用发出高刷请求不代表系统必须采用该模式。Android 官方说明见 [Optimize refresh rates](https://developer.android.com/games/optimize/display-refresh-rate-change) 和 [Frame rate](https://developer.android.com/media/optimize/performance/frame-rate)。本项目的请求及当前限制以设备日志为准。
- PowerKeeper 内部配置的受保护 provider 此前拒绝了 ADB shell 读取；具体命中规则未得到。没有通过清空系统服务数据、卸载正式应用等方式猜测修复。

## GC 排查

### 源码、编译配置

比较目录：`E:\D.C.E` 与用户提供的 `E:\FNF-NovaFlare-Engine-1.2.1`。

- 两边 Android 使用 Haxe 4.3.7、HXCPP 分代 GC。关键原生编译参数及 `HxcppConfig-64.h` 一致。
- HXCPP 的 `Immix.cpp`、`include/hx/GC.h` 对比一致；文本哈希规范化 CRLF/LF。
- `GCManager.hx` 的差异是 NovaGC/D.C.GC 注释名称，GC 调用及配置一致。
- PlayState、LoadingState、Paths 的 GC 生命周期调用行一致：加载期间临时关闭/重新开启、gameplay begin/pause/finish/abort、请求 full collection。
- 项目的 `hxcpp_zgc`/移动式 GC 开关在这份配置中只用于 Windows；Android 不使用该分支。
- `gcFreeZone` 保存项存在，但 Main 中对应调用为注释，没有用这个保存项每帧进入 GC free zone。
- 当前 Android gameplay GC 偏好关闭；本次实际游玩 getter 也返回 `gcGameplay=false`。

### 180 秒设备采样

诊断包直接读取 HXCPP 的 `__hxcpp_gc_last_pause_ms` 等原生 getter，数据为 Haxe GC，不是 Android Java/ART GC。

| 场景 | 每秒日志记录数 | 观测到的最近一次 GC 停顿范围 |
| --- | ---: | ---: |
| InitState | 8 | 1.94–4.17ms |
| TitleState | 45 | 1.55–7.47ms |
| MainMenuState | 36 | 2.93–5.85ms |
| StoryMenuState | 23 | 2.48–5.47ms |
| PlayState，Tutorial 实际游玩 | 64 | 2.17–10.47ms |

总计 176 条记录，180.253 秒。观测到的 GC 停顿最大约 **10.47ms**。该 getter 保留最近一次已完成停顿；这不是 GC 总耗时、次数或所有 collection 的完整 trace，不能把同一值重复出现当成多次 GC，也不能保证没有漏掉两次 update 之间的多次 collection。

稳定的约一秒采样窗口中，标题页约 426–614 次绘制请求/秒，游玩场景约 182–681 次/秒；窗口的 update/draw 配置仍分别为 288/2000，`lockRender=true`。SurfaceFlinger 的 D.C.E. 图层同时记录 `displayRefreshRate=60`、`renderRate=60`。这些请求次数不代表屏幕呈现了几百帧。

加载/状态切换也存在较长 update 间隔，最大单次观测间隔约 4.338 秒，不能将它归为 4.338 秒 GC 停顿。歌曲加载性能和偶发掉帧仍可独立优化。

未采用长期禁用 GC 的方法做“修复”。本轮没有更换 GC 后端或修改 GC 参数。

## 渲染链路与依赖

以下源码与参考目录一致：

- Flixel `FlxGame.hx`。
- OpenFL `Stage.hx`。
- Lime `NativeApplication.hx`、`SDLApplication.cpp`、`SDLWindow.cpp`。
- Lime `RenderThread.cpp`，包括上下文及 SwapInterval 路径。

D.C.E. 与手机新 NF、参考目录 1.2.2 APK 的以下 ARM64 库逐字节一致：

- `liblime.so`：SHA256 前缀 `8c46c853dafa6715`。
- `libc++_shared.so`：`ab4e6c71b96b851d`。
- `libvlc.so`：`b14d30636776164f`。

**更正旧对照边界：**“D.C.E. 额外包含 VLC”只适用于此前的旧 NF APK 对照；这次参考目录与手机的新 NF 也有相同 VLC。VLC 存在本身不解释新 NF 与 D.C.E. 的策略区别。

主程序 `libApplicationMain.so` 不同，D.C.E. 有额外的编辑器、兼容层等功能。手机新 NF 的 APK 与参考目录中的 APK 也不是完全相同的构建。因此源码一致不能当成手机上 NF 所有运行代码与参考目录完全一致的证明。

15 秒 simpleperf 原生 CPU 采样共 5296 samples、0 lost。较大的项目是时钟读取、SDL 原子操作和驱动调用。Haxe 主库占采样权重约 7.83%，但已移除的符号导致无法从该报告准确拆出 GC CPU 百分比。另行尝试 native gdb，旧工具链连接未完成，已解除进程暂停并清理调试转发；没有将它当成成功的原生 GC 调试。

游戏顶部数字在部分截图中空白，不能依靠这些截图读 FPS。本次结论使用原生 getter、配置值和 SurfaceFlinger 实测。数字显示问题未在本轮修复。

## 本次追加的诊断工具与交付状态

- `source/mobile/backend/AndroidFrameAudit.hx`：仅在 `android && cpp && DCE_FRAME_AUDIT` 构建中启用，每秒记录更新次数、绘制请求、GC 最近停顿、堆内存及窗口配置，180 秒后自动停止。
- `source/Main.hx`：在同一条件编译开关下启动采样。普通构建没有采样代码的运行开销。
- 原始日志位置：应用私有目录 `files/android-frame-audit.ndjson`；已复制到本地证据目录。
- 单独生成并更新安装 `E:\D.C.E\_release\D.C.E-Android-GC-Audit.apk`，包名、签名及已有设置保留，仍可被选为调试应用。手机暂留该诊断包。
- APK SHA256：`C34F08A8CE42F37D039B86E5CF44E6CF1E12C6EF7536838E28BD0C5F8DC7D15D`。
- 正式 `D.C.E-Android-Update.apk` 文件未替换，SHA256 仍为 `675181F2455674A8FCF732D1D25FA837130F710BE95BD32417CB413FBFF3D39B`。
- 生成的 Gradle/manifest 调试改动已经恢复。正常构建不传 `-DDCE_FRAME_AUDIT`。
- 设置恢复到本轮开始值：288 TPS、2000 绘制 FPS、独立渲染线程开启。
- 没有卸载正式 D.C.E. 或两个 NF，未清空游戏存档。

证据目录：`E:\D.C.E\_build\android-fps-full-audit`。

关键证据：`source-binary-comparison.json`、`presentation-summary.json`、`dce-telemetry-gameplay.ndjson`、`dce-cap-api-log.txt`、`dce-gameplay-timestats.txt`、各应用 display/SF dump 及截图。两次编译的日志为 `build-telemetry.txt`、`gradle-telemetry-debug.txt`。

后续未完成项：确定 MIUI 为 D.C.E. 选择 60 的内部规则，并验证解除该规则后能够按绘制上限在 60 以上实际呈现。目前不能宣布高刷修复完成。
