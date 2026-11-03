# D.C.GC（精确 GC）构建说明

> **D.C.GC** = D.C. Engine 的精确式低延迟 GC（单堆、可达即精确、真正把空闲页 decommit 还给系统）。
> 它由仓库里的 `hxcpp/` 运行时提供（原名字叫 NovaGC，2026-09-30 统一改名为 **D.C.GC**）。
> 它替换的是旧的 **legacy Immix GC**（`.haxelib/hxcpp/4,3,2`，非精确、堆只增不减）。

---

## 1. 为什么要换

旧 GC 的实测问题（2026-09-30 会话，构建 `-D legacy_gc_compare`）：

| 现象 | 原因 |
|---|---|
| 退出编谱器后 "APP MEM" 不回落 | Immix 的 `releaseEmptyGroups()` **只在整理式回收里**被调用（`Immix.cpp:4264/5433`），普通 GC 永不归还块；大场景退出后活对象散布各块 → 没有"完整空的 block group" → `reserved` 卡在 900MB 级 |
| 只有歌曲路径能回落（700→113MB） | 引擎的 `GameplayGC.abort() → __hxcpp_gc_leave_gameplay(false)` 里那次 `InternalCollect(true,false)` 恰好走了整理式回收；编谱器没有 gameplay 模式可退 |
| 元素"看起来没销毁" | 其实是状态壳被钉住 → 但 `hollowOut()` 已修好（对象确实回收，堆 644→152MB） |

D.C.GC 有真正的 decommit（`runtime/gc/runtime.cpp` 的 `free.region->decommitAll()`），所以空闲堆会真的还给系统。

---

## 2. 构建前置（三个都要满足，缺一个就构建不出精确 GC）

### ① hxcpp 指向仓库里的 D.C.GC 运行时

```powershell
haxelib dev hxcpp <仓库根>\hxcpp
```

验证：

```powershell
haxelib path hxcpp     # 应输出 <仓库根>\hxcpp\src\ 与 -D hxcpp=0.1.0
```

回滚到 legacy（Immix）：

```powershell
haxelib dev hxcpp       # 不带路径 = 清除 dev 指向，回到 .haxelib/hxcpp/4,3,2
```

### ② 用项目自带的定制 Haxe 编译器

精确 GC 的 C++ 代码生成需要能发出新 ABI 的编译器。**系统 Haxe（`C:\HaxeToolkit\haxe`）即使带上全部 define 也只会生成旧 ABI**（实测 `_hx_.mPtr->*(hx::interface_cast<...>)` → 编译期报 `base operand of '->' has non-pointer type 'hx::gc::RefSlot'`）。

用 `toolchains/haxe-novagc/haxe.exe`（项目自带，版本同为 4.3.7）：

```powershell
$env:PATH          = "<仓库根>\toolchains\haxe-novagc;" + $env:PATH
$env:HAXEPATH      = "C:\HaxeToolkit\haxe"        # 定制 haxe.exe 同目录没有 std，需要指向系统 std
$env:HAXE_STD_PATH = "C:\HaxeToolkit\haxe\std"    # 缺少这个会报 "Standard library not found"
```

### ③ ABI define（已写进 `Project.xml`，确认它在即可）

```xml
<haxedef name="hxcpp_zgc"        if="windows" unless="legacy_gc_compare" />
<haxedef name="novagc-precise"   if="windows" unless="legacy_gc_compare" />
<haxedef name="HXCPP_ZGC_ABI" value="1" if="windows" unless="legacy_gc_compare" />
```

- 前两个是 hxcpp 构建工具（`hxcpp/run.n`）校验的「codegen 契约」标记，**属于 ABI 层标识，不要改名**（改了会被 `run.n` 拒绝构建）。
- **第三个才是开关**：缺它时生成的是旧 ABI，构建会在接口头文件处炸掉（2026-09-30 实测过一次）。

---

## 3. 构建

```powershell
haxelib run lime build windows -release
```

- 不要带 `-D legacy_gc_compare`（那是旧 GC 的对照构建）。
- 产物：`export/release/windows/bin/D.C.E.exe`（`Project.xml` 的 `BUILD_DIR` 默认 `export/release`；带 `legacy_gc_compare` 时才是 `export/legacy-gc`）。
- 首次会全量重编约 5000+ 个翻译单元（8 并发，约 10~20 分钟）；之后是增量。

### 验证生成的是新 ABI

```powershell
Select-String -Path 'export\release\windows\obj\include\**\*.h' -Pattern 'managedPointer\(\)' | Select-Object -First 1
Select-String -Path 'export\release\windows\obj\include\**\*.h' -Pattern '_hx_\.mPtr->'      # 应为空
```

---

## 4. 切换 GC 时要注意

- 两个配置的中间产物目录不同（`export/release` vs `export/legacy-gc`），可以同时保留、互不破坏；但 **haxelib 的 dev 指向是全局的**，所以同一时刻只能构建其中一种。
- 切换前建议备份（本次改动已经做过）：
  - `_backup/2026-09-30-pre-dcgc/`（`source.zip` + `hxcpp-fork/` 整份 + haxelib 解析状态）
  - 两个仓库各有 git tag `backup-pre-dcgc-20260930`
- 代码里 `#if (cpp && !hxcpp_zgc)` 包着的是 **legacy 专用**的 gameplay GC 调用（`GCManager.GameplayGC`）；精确 GC 构建下这些调用会被编译掉，由 D.C.GC 自己的策略接管，这是预期行为。
