# UIC — U Idea Code 运行时库

> **声明结构归 UIC，逻辑归 Lua，渲染归 FNF 原生 API。**
> 不改引擎源码，自己做库扫描加载，按曲目绑定调用。

本目录是 `D.C.LushiFuU.I.C.解决lua的重复性工作.md` 那份语法规范的**完整 Lua 实现**。

---

## 一、目录内容

```
UIC/
├── README.md               ← 本文件
├── uic.lua                 ← 运行时库本体（单文件，丢进 mod 就能用）
├── examples/
│   ├── README.md           ← 示例说明
│   ├── ui/主题.uic          ← 跨文件超全局 *# 示例
│   ├── ui/主菜单.uic        ← 界面声明示例
│   ├── ui/暂停界面.uic      ← 判断链 why! 示例
│   └── song_script.lua     ← 曲目脚本接入示例
└── tests/
    ├── README.md           ← 怎么跑测试
    ├── run_tests.lua       ← 84 项运行时测试（自带假引擎）
    ├── run_examples.lua    ← 20 项示例端到端验证
    └── run_with_node.js    ← Node 下跑测试（可选，用 fengari）
```

`uic.lua` 是**刻意做成单文件**的：Psych / D.C.E. 给每个 `.lua` 开独立 Lua state，
单文件没有模块解析问题，复制到任何 mod 都能直接跑。

---

## 二、快速开始（三步）

### 第 1 步：把库放进 mod

```
mods/<你的mod>/scripts/uic.lua
```

### 第 2 步：写 UIC 文件

`mods/<你的mod>/ui/主菜单.uic`：

```uic
/~ 文件内常量 ~/
*@ 标准缩放 ? 0.8

/~ 文件内样式组 ~/
*@ 按钮通用 {
    scale ? 0.8
    camera ? "hud"
    alpha ? 1
}

/~ 元素组 ~/
*! 主菜单按钮 {btn开始, btn设置, btn退出}

/~ 声明并应用样式 ~/
hello.[btn开始]("ui/btn.png", 100, 200) {
    @按钮通用
    scale ? @标准缩放
}
hello.[btn设置]("ui/btn.png", 100, 300) { @按钮通用 }
hello.[btn退出]("ui/btn.png", 100, 400) { @按钮通用 }

/~ 组广播：一次性，后来者居上 ~/
主菜单按钮.alpha ? 0.9
```

### 第 3 步：在曲目脚本里加载

`mods/<你的mod>/data/<歌曲名>/ui.lua`：

```lua
-- 每个 .lua 文件都有独立的 Lua state，所以要把 scripts/ 加进搜索路径
package.path = package.path .. ';mods/<你的mod>/scripts/?.lua'

local uic = require('uic')

function onCreatePost()
    uic.load('ui/主菜单.uic')
end

function onUpdatePost(elapsed)
    -- 读 UIC 侧 dp() 的输出
    for _, msg in ipairs(uic.dp()) do
        debugPrint(msg)
    end
end
```

> **为什么不是 `import uic`？**
> `import uic` 是规范里的书写形式，但 Lua 语法里没有 `import` 语句，写出来是语法错误。
> 等价的真实写法是 `local uic = require('uic')`。
> 另外，引擎给每个 lua 文件开**独立 state**，把 `uic.lua` 当全局脚本丢进 `scripts/`
> 并**不能**让别的脚本用上它 —— 必须 `require`（或 `dofile`）。

---

## 三、Lua 侧接口

| 规范写法 | Lua 实际写法 | 说明 |
|---|---|---|
| `import uic` | `local uic = require('uic')` | 加载库 |
| `uic.file.[路径]` | `local rt = uic.file['路径']` | 加载并执行 .uic |
| — | `uic.file('路径')` | 同上，调用形式 |
| — | `uic.load('路径', opts)` | 同上，可传选项 |
| `uic.into(名字)` | `local e = uic.into('btn1')` | 取元素句柄 |
| `uic.getOut(名字)` | `uic.getOut('btn1')` | 销毁元素 |
| `uic.dp()` | `local 消息表 = uic.dp()` | 接收 dp 输出（取完即清空） |

> `uic.file.[路径]` 里的 `.[]` 是 UIC 的声明记号，**不是合法 Lua**。
> Lua 里索引必须写成 `uic.file['路径']`，而且**单个索引表达式不能独立成句**
> （Lua 只允许函数调用和赋值作语句），所以要么赋值、要么用 `uic.file('路径')`。

### 元素句柄

```lua
local btn = uic.into('btn开始')
btn.scale = 1.2                 -- 写属性（自动展开到 scale.x / scale.y）
local a = btn.alpha             -- 读属性
btn:set('camera', 'hud')        -- 方法形式
btn:destroy()                   -- 等价于 uic.getOut('btn开始')
btn.name, btn.tag, btn.exists   -- 元信息（不查引擎）
```

### 其它接口

```lua
uic.loadString(源码, '显示名', { raise = true })   -- 直接从字符串加载
uic.parse(源码, '显示名')                          -- 只解析，返回 AST
uic.parseFile('路径')                              -- 只解析文件
uic.setup({ mod = '模组目录名', files = { 'ui/a.uic' } })
uic.getOutAll()                                    -- 销毁所有元素
uic.reset(true)                                    -- 清空元素 + 超全局 + 缓存
uic.reload('路径')                                 -- 清缓存后重载（热重载）
uic.selftest() / uic.printSelftest()               -- 库自检
uic.normalizePath('C://a//b.uic')                  -- 路径规范化
uic.onDp   = function(text) end                    -- dp 回调
uic.onError = function(err, file) end              -- 错误回调
uic.autoPrint = false                              -- 关掉 dp 自动 debugPrint
uic.tagPrefix = 'uic_'                             -- 引擎 sprite tag 前缀
uic.cacheEnabled = false                           -- 关掉文件内容缓存
```

---

## 四、路径规则

| 写法 | 解析成 |
|---|---|
| `uic.file['C://mods/x.uic']` | `C:/mods/x.uic`（带盘符 → 走盘根） |
| `uic.file['ui/主菜单.uic']` | 依次尝试 `mods/<当前mod>/ui/主菜单.uic` → `mods/ui/主菜单.uic` → `ui/主菜单.uic` |

* 反斜杠会自动转成正斜杠；`C://` 里多余的斜杠会被折叠。
* 不带 `.uic` 后缀时会自动补一次。
* 当前 mod 的探测顺序：`uic.mod` → 引擎全局 `modFolder` / `currentModDirectory`
  → 库自身路径（`.../mods/<mod>/scripts/uic.lua`）→ 放弃。
* 找不到文件时报 `hello~你的[路径]中缺少了定义`。
* 搜索根可以用 `uic.roots` 查看、`uic.refreshRoots()` 刷新。

---

## 五、语法速查

### 符号总表

| 符号 | 作用域 | 含义 |
|---|---|---|
| `?` | — | 赋值 |
| `[名字]` | — | 声明标记（内容按**字面**处理，`-` 可以作名字一部分） |
| `*!` | 文件内 | 声明元素组 |
| `*@` | 文件内 | 声明样式 / 常量 |
| `*#` | 跨文件 | 声明超全局 |
| `@` | 文件内引用 | 引用 `*@` |
| `#` | 跨文件引用 | 引用 `*#` |
| `hello.[!组名]` | — | 批量导入组 |
| `/~ ~/` | — | 注释（可跨行，**支持嵌套**） |

### 元素声明

```uic
hello.[名字](路径, x, y)
hello.[名1][名2][名3](路径, x, y)
hello.[!组名]
hello.[名字]                       /~ 后续再补属性，无资源默认 50px ~/
```

* `hello` 裸用是普通标识符；只有 `hello.[名字]` 才触发声明。
* `auto`：按资源尺寸自动填充；**无资源默认 50px**；出现在坐标位时按 `0`。
* 资源以 `.xml` / `.txt` / `.json` 结尾时自动走 `makeAnimatedLuaSprite`。
* 重复声明同名元素**不会**重建，避免同一帧里覆盖已有的精灵。

### 属性赋值

```uic
元素.属性 ? 值
组名.属性 ? 值        /~ 一次性广播，后来者居上 ~/
```

### 样式 / 常量 / 超全局

```uic
*@ 样式名 {
    属性 ? 值
    @另一样式          /~ 必须前面已声明 ~/
}
*@ 常量名 ? 值

*# 超全局名 { 属性 ? 值 }
*# 超全局常量 ? 值
```

### 引用

```uic
hello.[btn1]("btn.png", auto, auto) {
    @文件内样式
    #跨文件超全局
    scale ? @常量名
}
```

### 条件

```uic
if 条件 {
    ...
} else {
    ...
}
```

运算符：`==` `!=` `>` `<` `>=` `<=` `&&` `||` `+` `-` `*` `/` `%`，支持 `( )` 与一元 `-` `!`。
**可比较非数值**（字符串按字典序）。支持嵌套与 `else if`。

条件里可以直接读引擎的 Lua 全局：

```uic
if screenWidth >= 1280 && screenHeight >= 720 { ... }
if curBeat > 16 { ... }
```

单段名字的解析顺序是：**UIC 元素 → 引擎全局 → 当前作用域元素的属性**。
所以 `why![scale]` 里的 `scale` 会落到「当前元素的属性」，而 `curBeat` 会读到引擎全局。

### 判断链

```uic
hello.[btn]("e.x.p.png", auto, auto) {
    why![scale] ? 8 OK
        dp("FuckYou")
    or![scale] ? 1 OK
        dp("Fuckme")
    and![scale] ? 0.1 OK
        dp(btn)
    no
        dp("nothing beat some Jeet 2 hologay")
    stopWhy
}
```

| 记号 | 含义 |
|---|---|
| `why![属性]` | 判断入口 |
| `or!` / `and!` | 后续分支（等价 else if 链，按书写顺序求值） |
| `? 值,值,...` | 候选值集合（命中任一即成立） |
| `值,值\|属性` | 也可以把值集合写在方括号里 |
| `whynot` | 反选（写在方括号里或 `?` 之后都行） |
| `OK` | 条件为真时执行（显式标记） |
| `no` | 前面所有分支都没命中时执行 |
| `stopWhy` | 结束判断链（可省略） |

**求值语义**

* 作用域里有多个元素时**逐个元素判定**，命中的元素执行该分支体，
  且执行时作用域收窄为命中者。
* 每个元素**最多命中一个分支** —— 读起来就是 `if` / `else if` / `else`。
* `no` 只作用于「一个分支都没命中」的元素；全命中时 `no` 不执行。
* 分支体里可以继续写 `dp()` / 属性赋值 / 嵌套 `if` / 嵌套判断链。

**嵌套判断链**

分支体「开头」就是另一个 `why!` 时，按**嵌套链**解析（内层用 `stopWhy` 收尾）：

```uic
why![scale] ? 1 OK
    why![alpha] ? 0.5 OK
        dp("内层命中")
    stopWhy
stopWhy
```

区分规则很简单：`why!` 紧跟着 `why!` → 嵌套；正文写在前面 → 平级分支。
`or!` / `and!` / `no` 永远只属于当前这一层。

### 跨语言通信

```uic
dp()                /~ 无参 → "D.C.LushiFu--U.I.C." ~/
dp("字符串")
dp(元素)
dp(元素.属性)
```

Lua 侧用 `uic.dp()` 取回（返回数组并清空缓冲）；也支持 `uic.onDp` 回调。

---

## 六、属性与合并规则

### 属性名怎么变成引擎调用

* 认识的别名会自动展开：

  | UIC 属性 | 实际写入 |
  |---|---|
  | `scale` | `scale.x` + `scale.y` |
  | `scroll` / `scrollFactor` | `scrollFactor.x` + `scrollFactor.y` |
  | `offset` | `offset.x` + `offset.y` |
  | `origin` | `origin.x` + `origin.y` |
  | `velocity` | `velocity.x` + `velocity.y` |

* 需要专用函数的：

  | UIC 属性 | 调用 |
  |---|---|
  | `camera` | `setObjectCamera` |
  | `anim` / `animation` | `playAnim` |
  | `blend` | `setBlendMode` |
  | `add` | `addLuaSprite` / `removeLuaSprite` |
  | `shader` | `setSpriteShader` |

* 其它一切属性直接走 `setProperty(tag..'.'..属性名, 值)`，
  所以 Psych 的 `x` `y` `angle` `alpha` `visible` `flipX` `color` `antialiasing`
  以及任意自定义字段都能用。
* 颜色可以写 `0xFFFF00`、`#FFFF00`、`"#FFFF00"`、`"0xFFFF00"`。

### 合并规则

规范里两条看似矛盾的话，实现上这样落地：

| 情形 | 规则 |
|---|---|
| **同一元素上，多个 `@` 标记 / `#` 超全局互相叠** | **后来者居上**（覆盖） |
| **元素先有直接赋值（`scale ? 2`），再来 `@` 标记** | **嵌套叠加** |
| 组广播 `组名.属性 ? 值` | 一律按直接赋值处理，覆盖 |
| `*@` 样式内部再 `@别的样式` | 样式内部按嵌套叠加合并 |

嵌套叠加按属性类别处理：

| 类别 | 行为 | 属性 |
|---|---|---|
| **比例型** | **乘算** | `scale` `scale.x` `scale.y` `alpha` `graphicSize` … |
| **偏移型** | **加算** | `x` `y` `angle` `offset.*` `scrollFactor.*` `origin.*` `velocity.*` |
| **系统级** | **跳过**（保留先到者） | `camera` `add` `anim` `blend` `shader` `color`、以及**所有未登记属性** |

举例：

```uic
*@ 通用 { scale ? 0.5 }

hello.[a]("a.png", auto, auto) { scale ? 2  @通用 }   /~ a.scale = 2 * 0.5 = 1 ~/
hello.[b]("b.png", auto, auto) { @通用  @通用 }        /~ b.scale = 0.5（后者覆盖） ~/
hello.[c]("c.png", 5, 5)       { x ? 100  @位移10 }   /~ c.x = 100 + 10 = 110 ~/
hello.[d]("d.png", auto, auto) { camera ? "game"  @摄像hud }  /~ 仍是 game ~/
```

---

## 七、错误信息（规范第九节）

| 触发 | 信息 |
|---|---|
| `hello.[名字]` 引用不到任何元素 / 组，或光杆名字 | `hello~你的[行号]中缺少了定义` |
| 花括号、方括号、圆括号没闭合；样式组里写逻辑 | `你想死啊。行号` |
| `@` `#` `!` 引用了一个没声明过的名字 | `你貌似没有定义@某某，检查下声明位置` |

* 错误的行号除了报错文本，还会在括号里附上 `(文件名:行号)`，方便定位。
* `uic.load` 默认**不抛错**（把信息打给 `debugPrint`，返回 `nil`），
  避免一首歌直接崩掉；要抛错就传 `{ raise = true }`。
* 可以用 `uic.onError = function(err, file) ... end` 接管；`uic.lastError` 保存最后一次的错误。

---

## 八、常见坑

**1. 每个 lua 文件是独立 state。**
把 `uic.lua` 丢进 `scripts/` 当全局脚本**不会**让曲目脚本用上它。
必须 `package.path = package.path .. ';mods/<mod>/scripts/?.lua'` 再 `require('uic')`。

**2. `uic.file['x']` 不能独立成句。**
Lua 只允许函数调用 / 赋值作语句。写 `uic.file('x')`，或 `local rt = uic.file['x']`。

**3. 严格沙箱下会失效。**
引擎的 `sandboxStrict` 会移除 `io` / `require`，那时 UIC 读不了 `.uic` 文件。
默认沙箱（`sandboxEnabled = true`、`sandboxStrict = false`）是保留 `io.open` 和 `require` 的，
正常情况没问题。

**4. 中文路径是安全的。**
`uic.lua` 自己用 `io.open` 读文件，不走引擎的 `dofile`，所以中文目录名不会有编码问题
（引擎侧对 `luaL_dofile` 的中文路径有专门的兜底处理）。

**5. 元素生命周期归 Lua 端。**
UIC 只负责「声明 + 赋值」，什么时候销毁由你在 Lua 里决定（`uic.getOut` / `uic.reset`）。
切换歌曲前记得清理，否则上一首的元素会留在舞台上。

**6. `*@` / `*!` 必须先声明后使用。**
这是规范硬性要求，也是「顺序敏感」语义的一部分。`*#` 可以跨文件，但仍然要先加载定义它的文件。

---

## 九、跑测试

```bash
cd UIC/tests
node run_with_node.js      # 需要先 npm i fengari
```

或者按 `tests/README.md` 里的方式，把 `run_tests.lua` 丢进游戏跑真实 LuaJIT。

当前状态：**运行时测试 84 项 + 示例端到端验证 20 项，全部通过**。

---

## 十、实现说明（给要改库的人）

* `uic.lua` 只用**最小公共 Lua 子集**：
  不用字符串方法语法（`s:sub()`）、不用 `string.gmatch` / `string.match` /
  带捕获的 `string.find` / 带函数的 `string.gsub`、不用 `table.sort`、
  不用 `%.Nf` 格式符。全部手写扫描，这样在任何 Lua 实现上行为一致。
* 文件读取统一走 `uic.vfs`，测试时替换成内存表即可完全脱离磁盘。
* 引擎调用统一走 `uic.bridge`，引擎缺函数时只警告一次然后跳过，不会炸。
* 局部变量一律遵守先声明后使用；需要互相引用的纯函数用「前向声明」占位
  （`local truthy` 之类），否则会掉进 Lua 的全局变量坑。
* 词法分析器给每个 token 带 `p` / `ep` 字节偏移，
  `[...]` 和 `{...}` 的内容是**原样取文本**再处理的，所以 `-`、`...` 这类字面名字不会被误伤。
