# UIC 测试

两套测试，都**不需要开游戏**：

| 文件 | 内容 | 数量 |
|---|---|---|
| `run_tests.lua` | 运行时测试：自己实现一套 FNF / Psych 假 API，断言 uic.lua 最终写进去的属性 | 84 项 |
| `run_examples.lua` | 端到端验证：真的加载 `../examples/ui/*.uic`，断言结果 | 20 项 |

---

## 跑法 A：Node（最省事）

在 `UIC/tests` 目录下：

```bash
npm i fengari          # 只需一次：纯 JS 的 Lua 5.3 虚拟机
node run_with_node.js
```

输出示例：

```
========================================
UIC 测试结果：通过 84 项，失败 0 项
========================================
...
示例验证：通过 20 项，失败 0 项
```

> 为什么用 fengari 而不是项目自带的 `luahscript`？
> `luahscript` 的 Lua 解释器有不少实现缺陷（字符串方法、`string.gmatch`、
> `string.find` 捕获、`table.sort`、`io`，以及闭包参数绑定都会出错），
> 跑不动这个库。fengari 是完整的 Lua 5.3 实现。

---

## 跑法 B：真实 Lua / LuaJIT

```bash
cd UIC/tests
lua run_tests.lua
lua run_examples.lua
```

需要 `uic.lua` 能被找到：脚本会依次尝试
「全局 `uic`」→「`require('uic')`」→「`uic.lua` / `../uic.lua` / `scripts/uic.lua`」。

---

## 跑法 C：游戏内（真实 LuaJIT，最接近实战）

1. 把 `uic.lua` 和 `run_tests.lua` 一起放进 `mods/<你的mod>/scripts/`
2. 启动随便一首歌

脚本会**临时覆盖**引擎函数（`makeLuaSprite` / `setProperty` ...），
跑完自动还原，所以不会污染正常运行。
结果同时打到控制台和 `debugPrint`（屏幕上）。

> 注意：引擎给每个 `.lua` 文件开独立 Lua state，
> 所以 `run_tests.lua` 必须能自己找到 `uic.lua` —— 放在同一个 `scripts/` 目录下最稳。

---

## 覆盖范围

**run_tests.lua**

* 词法：BOM、跨行/行尾/嵌套注释、`[...]` 字面名字（`btn1-`、`...`）
* 元素：声明、坐标、`auto`、无资源 50px、多元素一次声明、图集自动走动画精灵、重复声明不重建
* 属性：`scale` 展开、`camera` 走 `setObjectCamera`、组广播、广播后来者居上
* 样式：`*@` 组 / 常量、`*#` 跨文件超全局、标记叠标记覆盖、嵌套叠加（比例乘算 / 偏移加算 / 系统级跳过）
* 条件：`if`/`else`/`else if`、`&&`/`||`、嵌套、非数值比较
* 判断链：`why!` / `or!` / `and!` / `no` / `stopWhy`、多值集合 `值,值|属性`、`whynot` 反选
* `dp`：无参默认文本、字符串、元素、元素属性、取完即清空
* Lua 接口：`uic.into` 读写、`uic.getOut`、`uic.reset`
* 路径：相对路径走 mods、`uic.file[...]` / `uic.file(...)`、盘符规范化、找不到文件的报错
* 错误信息：三条规范文案逐条验证
* 降级：引擎缺 `debugPrint` / `getProperty` 时不炸

**run_examples.lua**

* 三个示例文件的加载与执行
* 跨文件超全局 → 文件内样式 → 元素 的三层叠加结果
* 组广播与条件语句的顺序敏感性
* 判断链在真实示例里的命中结果

---

## 加测试

在 `run_tests.lua` 里加一条就行：

```lua
test('用例名', function()
    load('hello.[x]("x.png", auto, auto) { alpha ? 0.5 }', 'tag')
    check(prop('x', 'alpha') == 0.5, '失败时显示的信息')
end)
```

`test` 会自动在跑之前调用 `uic.reset(true)` 并清空假精灵表，用例之间互不干扰。

常用工具函数：

| 函数 | 作用 |
|---|---|
| `load(源码, 标签)` | 加载并执行一段 UIC 源码（失败即抛错） |
| `prop(元素名, 属性)` | 读假引擎里的属性 |
| `dpOf(源码)` | 跑完取回 `dp()` 的输出数组 |
| `expectError(源码, 片段)` | 断言会报错，且错误信息包含指定片段 |
| `SPRITES[名字]` | 直接看假精灵记录（`__image` / `__animated` 等） |

---

## 不需要 fengari 的快速自检

库自带一个不依赖引擎的自检：

```lua
local uic = require('uic')
local cases, passed, failed = uic.selftest()
uic.printSelftest()   -- 直接打印
```
