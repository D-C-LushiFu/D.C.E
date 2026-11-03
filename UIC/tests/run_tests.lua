-- ============================================================================
--  UIC 运行时测试套件
--  ---------------------------------------------------------------------------
--  这个脚本不依赖游戏引擎：它自己实现一套 FNF / Psych 的假 API
--  （makeLuaSprite / setProperty / getProperty ...），
--  然后驱动 uic.lua 跑完整流程，断言最终写进「假引擎」里的属性值。
--
--  三种跑法：
--    A) 命令行真实 Lua：
--         cd UIC/tests && lua run_tests.lua
--       （或者 luajit run_tests.lua）
--
--    B) 游戏内：把它放进 mods/<你的mod>/scripts/ 当全局脚本，
--       同时确保 uic.lua 也在 scripts/ 下。结果会打到控制台和 debugPrint。
--
--    C) 在任意 lua 脚本里 dofile('run_tests.lua') 也行。
--
--  注意：运行期间会**临时覆盖**引擎函数，跑完自动还原，
--        所以放在游戏里跑也不会污染正常运行。
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. 先把 uic 模块找出来
-- ---------------------------------------------------------------------------

local uic = rawget(_G, 'uic')
if type(uic) ~= 'table' or uic.version == nil then
	local ok, mod = pcall(require, 'uic')
	if ok and type(mod) == 'table' and mod.version ~= nil then uic = mod end
end

if type(uic) ~= 'table' or uic.version == nil then
	local candidates = { 'uic.lua', '../uic.lua', 'scripts/uic.lua', 'mods/uic.lua' }
	for i = 1, #candidates do
		pcall(dofile, candidates[i])
		local g = rawget(_G, 'uic')
		if type(g) == 'table' and g.version ~= nil then
			uic = g
			break
		end
	end
end

if type(uic) ~= 'table' or uic.version == nil then
	local msg = '[UIC 测试] 找不到 uic.lua。'
		.. '请把 uic.lua 放到 scripts/ 下，或先设置 package.path 再 require("uic")。'
	print(msg)
	local dp = rawget(_G, 'debugPrint')
	if type(dp) == 'function' then pcall(dp, msg) end
	return
end

-- ---------------------------------------------------------------------------
-- 1. 假引擎
-- ---------------------------------------------------------------------------

local SPRITES = {}
local LOGS = {}

local function splitFirst(s, sep)
	local a = string.find(s, sep, 1, true)
	if a == nil then return s, nil end
	return string.sub(s, 1, a - 1), string.sub(s, a + string.len(sep))
end

local function clearTable(t)
	for k in pairs(t) do t[k] = nil end
end

local MOCK = {}

function MOCK.makeLuaSprite(tag, image, x, y)
	SPRITES[tag] = {
		__image = image,
		__added = false,
		x = x or 0,
		y = y or 0,
		scale = { x = 1, y = 1 },
		offset = { x = 0, y = 0 },
		scrollFactor = { x = 1, y = 1 },
		velocity = { x = 0, y = 0 },
		origin = { x = 0, y = 0 },
		alpha = 1,
		angle = 0,
		visible = true,
		width = 0,
		height = 0,
		color = 4294967295,
		camera = 'game',
		blend = 'normal',
		anim = nil,
	}
	return tag
end

function MOCK.makeAnimatedLuaSprite(tag, image, x, y, spriteType)
	MOCK.makeLuaSprite(tag, image, x, y)
	local sp = SPRITES[tag]
	if sp ~= nil then sp.__animated = true end
	return tag
end

function MOCK.addLuaSprite(tag, front)
	local sp = SPRITES[tag]
	if sp ~= nil then
		sp.__added = true
		sp.__front = front
	end
end

function MOCK.removeLuaSprite(tag)
	SPRITES[tag] = nil
end

function MOCK.luaSpriteExists(tag)
	return SPRITES[tag] ~= nil
end

function MOCK.setProperty(path, value)
	local tag, rest = splitFirst(path, '.')
	local sp = SPRITES[tag]
	if sp == nil then return end
	local k1, k2 = splitFirst(rest, '.')
	if k2 ~= nil then
		if type(sp[k1]) ~= 'table' then sp[k1] = {} end
		sp[k1][k2] = value
	else
		sp[k1] = value
	end
end

function MOCK.getProperty(path)
	local tag, rest = splitFirst(path, '.')
	local sp = SPRITES[tag]
	if sp == nil then return nil end
	local k1, k2 = splitFirst(rest, '.')
	if k2 ~= nil then
		if type(sp[k1]) ~= 'table' then return nil end
		return sp[k1][k2]
	end
	return sp[k1]
end

function MOCK.setObjectCamera(tag, cam)
	local sp = SPRITES[tag]
	if sp ~= nil then sp.camera = cam end
end

function MOCK.setBlendMode(tag, mode)
	local sp = SPRITES[tag]
	if sp ~= nil then sp.blend = mode end
end

function MOCK.playAnim(tag, name, forced)
	local sp = SPRITES[tag]
	if sp ~= nil then sp.anim = name end
end

function MOCK.debugPrint(text)
	LOGS[#LOGS + 1] = tostring(text)
end

--- 需要伪造的引擎函数名单
local ENGINE_FNS = {
	'makeLuaSprite', 'makeAnimatedLuaSprite', 'addLuaSprite', 'removeLuaSprite',
	'luaSpriteExists', 'setProperty', 'getProperty', 'setObjectCamera',
	'setBlendMode', 'playAnim', 'debugPrint',
}

local SAVED = {}
for i = 1, #ENGINE_FNS do
	local n = ENGINE_FNS[i]
	SAVED[n] = rawget(_G, n)
end

local function installMocks()
	for i = 1, #ENGINE_FNS do
		local n = ENGINE_FNS[i]
		_G[n] = MOCK[n]
	end
end

local function restoreEngine()
	for i = 1, #ENGINE_FNS do
		local n = ENGINE_FNS[i]
		_G[n] = SAVED[n]
	end
end

installMocks()

-- ---------------------------------------------------------------------------
-- 2. 测试框架
-- ---------------------------------------------------------------------------

local REPORT = {}
local PASS, FAIL = 0, 0
local FAILURES = {}

local function out(line)
	REPORT[#REPORT + 1] = line
	print(line)
end

local function check(cond, msg)
	if not cond then error(msg or '断言失败', 0) end
end

local function test(name, fn)
	-- 每个用例前把全局状态复位，避免用例之间互相污染
	uic.tagPrefix = ''
	uic.autoPrint = false
	uic.cacheEnabled = true
	uic.onError = nil
	uic.reset(true)
	clearTable(SPRITES)
	local ok, err = pcall(fn)
	if ok then
		PASS = PASS + 1
		out('  [通过] ' .. name)
	else
		FAIL = FAIL + 1
		FAILURES[#FAILURES + 1] = name .. ' :: ' .. tostring(err)
		out('  [失败] ' .. name)
		out('         ' .. tostring(err))
	end
end

--- 期待报错，并检查错误信息里包含指定片段
local function expectError(src, fragment, tag)
	local ok, err = pcall(uic.loadString, src, tag or 'errcase', { raise = true })
	if ok then error('期待报错，但成功执行了', 0) end
	local text = tostring(err)
	if string.find(text, fragment, 1, true) == nil then
		error('错误信息里没有 [' .. fragment .. ']，实际是：' .. text, 0)
	end
end

local function load(src, tag)
	local rt = uic.loadString(src, tag or 'case', { raise = true })
	check(rt ~= nil, 'loadString 返回了 nil')
	return rt
end

local function prop(tag, path)
	return MOCK.getProperty(tag .. '.' .. path)
end

local function dpOf(src)
	uic.clearDp()
	load(src, 'dpcase')
	return uic.dp()
end

-- ---------------------------------------------------------------------------
-- 3. vfs：让 uic.file / uic.load 走内存文件表
-- ---------------------------------------------------------------------------

local FILES = {}

uic.vfs = {
	exists = function(p) return FILES[p] ~= nil end,
	read = function(p) return FILES[p] end,
}
uic.roots = { 'mods/', '' }
uic.autoPrint = false -- 免得 dp 刷屏，测试里手动取

-- ---------------------------------------------------------------------------
-- 4. 用例
-- ---------------------------------------------------------------------------

out('=== UIC 运行时测试（库版本 ' .. tostring(uic.version) .. '）===')
out('')
out('-- 词法层 --')

test('BOM 容错', function()
	local bom = string.char(239, 187, 191) .. 'hello.[bom1]("b.png", 1, 2)'
	load(bom, 'bom')
	check(prop('bom1', 'x') == 1, 'x 应为 1')
end)

test('跨行注释 /~ ~/', function()
	load('/~ 第一行\n   第二行 ~/\nhello.[cm1]("c.png", 3, 4)', 'cm')
	check(prop('cm1', 'x') == 3, 'x 应为 3')
	check(prop('cm1', 'y') == 4, 'y 应为 4')
end)

test('行尾注释', function()
	load('hello.[cm2]("c.png", 5, 6) /~ 尾巴 ~/', 'cm2')
	check(prop('cm2', 'x') == 5, 'x 应为 5')
end)

test('注释可以嵌套（便于整段注掉带注释的代码）', function()
	local src = '/~ 外层 /~ 内层 ~/ 还是外层 ~/\nhello.[cm3]("c.png", 7, 8)'
	load(src, 'cm3')
	check(prop('cm3', 'x') == 7, 'x 应为 7')

	-- 整段注掉一段本来就有注释的代码
	local src2 = '/~\nhello.[cm4]("c.png", 9, 9) /~ 行尾 ~/\n~/\nhello.[cm5]("c.png", 1, 1)'
	load(src2, 'cm5')
	check(SPRITES['cm4'] == nil, 'cm4 应该被注释掉')
	check(SPRITES['cm5'] ~= nil, 'cm5 应该存在')
end)

test('括号里按字面名字处理（含 - 与 ...）', function()
	local ast = uic.parse('hello.[btn1-][...]("x.png", auto, auto)', 'lit')
	check(ast.body[1].names[1] == 'btn1-', '第一个名字应为 btn1-')
	check(ast.body[1].names[2] == '...', '第二个名字应为 ...')
end)

out('')
out('-- 元素声明 --')

test('基础声明 + 坐标', function()
	load('hello.[e1]("img/e1.png", 100, 200)', 'e1')
	check(prop('e1', 'x') == 100, 'x')
	check(prop('e1', 'y') == 200, 'y')
	check(SPRITES['e1'].__image == 'img/e1.png', '资源路径')
	check(SPRITES['e1'].__added == true, '应该被 addLuaSprite')
end)

test('auto 参数 + 无资源默认 50px', function()
	load('hello.[e2](auto, auto, auto)', 'e2')
	check(prop('e2', 'x') == 0, 'auto 坐标按 0')
	check(prop('e2', 'width') == 50, '无资源宽度应为 50')
	check(prop('e2', 'height') == 50, '无资源高度应为 50')
	check(SPRITES['e2'].__image == nil, '不应有资源')
end)

test('多元素一次声明 + 共享属性块', function()
	load('hello.[m1][m2][m3]("m.png", 10, 20) { alpha ? 0.5 }', 'multi')
	check(prop('m1', 'alpha') == 0.5, 'm1 alpha')
	check(prop('m2', 'alpha') == 0.5, 'm2 alpha')
	check(prop('m3', 'alpha') == 0.5, 'm3 alpha')
	check(prop('m3', 'x') == 10, 'm3 x')
end)

test('图集资源自动走 makeAnimatedLuaSprite', function()
	load('hello.[an1]("sheet.xml", 0, 0)', 'anim')
	check(SPRITES['an1'].__animated == true, '应使用动画精灵')
end)

test('再次声明同名元素不重复创建', function()
	load('hello.[dup]("d1.png", 1, 1)', 'dup')
	load('hello.[dup]("d2.png", 2, 2)', 'dup')
	check(SPRITES['dup'].__image == 'd1.png', '资源不应被覆盖')
end)

out('')
out('-- 属性展开与群组广播 --')

test('scale 展开成 scale.x / scale.y', function()
	load('hello.[s1]("s.png", auto, auto) { scale ? 0.8 }', 'scale')
	check(prop('s1', 'scale.x') == 0.8, 'scale.x')
	check(prop('s1', 'scale.y') == 0.8, 'scale.y')
end)

test('camera 走 setObjectCamera', function()
	load('hello.[cam]("c.png", auto, auto) { camera ? "hud" }', 'camera')
	check(SPRITES['cam'].camera == 'hud', 'camera 应为 hud')
end)

test('*! 组 + hello.[!组] 批量创建', function()
	load('*! 菜单 {g1, g2, g3}\nhello.[!菜单]', 'group')
	check(SPRITES['g1'] ~= nil, 'g1 应被创建')
	check(SPRITES['g2'] ~= nil, 'g2 应被创建')
	check(SPRITES['g3'] ~= nil, 'g3 应被创建')
	check(prop('g1', 'width') == 50, '无资源应为 50px')
end)

test('组广播：组名.属性 ? 值', function()
	load('*! 菜单 {g1, g2}\nhello.[!菜单]\n菜单.alpha ? 0.5', 'cast')
	check(prop('g1', 'alpha') == 0.5, 'g1 alpha')
	check(prop('g2', 'alpha') == 0.5, 'g2 alpha')
end)

test('组广播后来者居上', function()
	load('*! G {a, b}\nhello.[!G]\nG.alpha ? 0.5\nG.alpha ? 0.9', 'cast2')
	check(prop('a', 'alpha') == 0.9, '后一次广播应覆盖')
end)

test('组内已声明成员不会被重建', function()
	load('*! G {p1, p2}\nhello.[p1]("real.png", 7, 8)\nhello.[!G]', 'group3')
	check(SPRITES['p1'].__image == 'real.png', 'p1 资源应保留')
	check(prop('p1', 'x') == 7, 'p1 x 应保留')
	check(SPRITES['p2'] ~= nil, 'p2 应被补建')
end)

test('组导入也能带属性块', function()
	load('*! G2 {q1, q2}\nhello.[!G2] { alpha ? 0.25 }', 'group4')
	check(prop('q1', 'alpha') == 0.25, 'q1')
	check(prop('q2', 'alpha') == 0.25, 'q2')
end)

out('')
out('-- 样式 / 常量 / 超全局 --')

test('*@ 样式组 + @引用', function()
	local src = '*@ 通用 {\n scale ? 0.5\n alpha ? 0.4\n}\n'
		.. 'hello.[st1]("s.png", auto, auto) {\n @通用\n}'
	load(src, 'style')
	check(prop('st1', 'scale.x') == 0.5, 'scale')
	check(prop('st1', 'alpha') == 0.4, 'alpha')
end)

test('*@ 常量 ? 值 与 @常量引用', function()
	local src = '*@ 值1 ? 0.8\nhello.[k1]("k.png", auto, auto) { scale ? @值1 }'
	load(src, 'const')
	check(prop('k1', 'scale.x') == 0.8, 'scale 应取常量值')
end)

test('标记叠标记 → 后来者居上', function()
	local src = '*@ A { alpha ? 0.2 }\n*@ B { alpha ? 0.7 }\n'
		.. 'hello.[mk]("m.png", auto, auto) {\n @A\n @B\n}'
	load(src, 'mark')
	check(prop('mk', 'alpha') == 0.7, '后一个标记应覆盖')
end)

test('嵌套叠加：比例型乘算', function()
	local src = '*@ 通用 { scale ? 0.5 }\n'
		.. 'hello.[ns]("n.png", auto, auto) {\n scale ? 2\n @通用\n}'
	load(src, 'nest')
	check(prop('ns', 'scale.x') == 1, '2 * 0.5 应为 1')
end)

test('嵌套叠加：偏移型加算', function()
	local src = '*@ 位移 { x ? 10 }\n'
		.. 'hello.[no1]("n.png", 5, 5) {\n x ? 100\n @位移\n}'
	load(src, 'nest2')
	check(prop('no1', 'x') == 110, '100 + 10 应为 110')
	check(prop('no1', 'y') == 5, 'y 不受影响')
end)

test('嵌套叠加：系统级跳过（camera 只认先到者）', function()
	local src = '*@ 摄像 { camera ? "hud" }\n'
		.. 'hello.[sy]("s.png", auto, auto) {\n camera ? "game"\n @摄像\n}'
	load(src, 'nest3')
	check(SPRITES['sy'].camera == 'game', 'camera 应保持 game')
end)

test('样式内嵌套样式 → 按类别叠加', function()
	local src = '*@ A { scale ? 0.5 }\n*@ B {\n @A\n scale ? 2\n}\n'
		.. 'hello.[nn]("n.png", auto, auto) { @B }'
	load(src, 'nest4')
	check(prop('nn', 'scale.x') == 1, '0.5 * 2 应为 1')
end)

test('*# 超全局跨文件共享', function()
	FILES['mods/lib/theme.uic'] = '*# 主题 {\n scale ? 0.25\n}'
	FILES['mods/song/ui.uic'] = 'hello.[sh]("s.png", auto, auto) {\n #主题\n}'
	uic.load('lib/theme.uic', { raise = true })
	uic.load('song/ui.uic', { raise = true })
	check(prop('sh', 'scale.x') == 0.25, '跨文件超全局应生效')
	FILES['mods/lib/theme.uic'] = nil
	FILES['mods/song/ui.uic'] = nil
end)

test('*# 超全局常量', function()
	load('*# 全局值 ? 0.33\nhello.[sg]("s.png", auto, auto) { alpha ? #全局值 }', 'super2')
	check(prop('sg', 'alpha') == 0.33, 'alpha 应取超全局常量')
end)

out('')
out('-- 条件 --')

test('if / else', function()
	local src = 'hello.[c1]("c.png", auto, auto) { scale ? 1 }\n'
		.. 'if c1.scale.x == 1 {\n c1.alpha ? 0.25\n} else {\n c1.alpha ? 0.75\n}'
	load(src, 'if1')
	check(prop('c1', 'alpha') == 0.25, '应走 if 分支')
end)

test('if / else 走 else', function()
	local src = 'hello.[c2]("c.png", auto, auto) { scale ? 1 }\n'
		.. 'if c2.scale.x > 5 {\n c2.alpha ? 0.25\n} else {\n c2.alpha ? 0.75\n}'
	load(src, 'if2')
	check(prop('c2', 'alpha') == 0.75, '应走 else 分支')
end)

test('逻辑组合 && ||', function()
	local src = 'hello.[c3]("c.png", auto, auto) { scale ? 2 }\n'
		.. 'if c3.scale.x >= 1 && c3.scale.x <= 3 {\n c3.alpha ? 0.11\n}'
	load(src, 'if3')
	check(prop('c3', 'alpha') == 0.11, '&& 组合')
end)

test('嵌套 if', function()
	local src = 'hello.[c4]("c.png", auto, auto) { scale ? 2 }\n'
		.. 'if c4.scale.x == 2 {\n if c4.alpha == 1 {\n c4.angle ? 45\n }\n}'
	load(src, 'if4')
	check(prop('c4', 'angle') == 45, '嵌套 if 应生效')
end)

test('块内 if 使用当前作用域', function()
	local src = 'hello.[c5]("c.png", auto, auto) {\n scale ? 1\n'
		.. ' if 1 < 2 {\n alpha ? 0.6\n }\n}'
	load(src, 'if5')
	check(prop('c5', 'alpha') == 0.6, '块内 if 应作用于该元素')
end)

test('非数值比较', function()
	local src = '*@ 名字 ? "abc"\nhello.[c6]("c.png", auto, auto) { }\n'
		.. 'if @名字 == "abc" {\n c6.alpha ? 0.9\n}'
	load(src, 'if6')
	check(prop('c6', 'alpha') == 0.9, '字符串比较')
end)

out('')
out('-- 判断链 why! / or! / and! / no / stopWhy --')

test('why! 命中第一支', function()
	local src = 'hello.[w1]("w.png", auto, auto) {\n scale ? 8\n'
		.. ' why![scale] ? 8 OK\n  dp("hit-8")\n'
		.. ' or![scale] ? 1 OK\n  dp("hit-1")\n'
		.. ' no\n  dp("none")\n stopWhy\n}'
	local out1 = dpOf(src)
	check(out1[1] == 'hit-8', '应命中第一支，实际 ' .. tostring(out1[1]))
	check(#out1 == 1, '只应产生一条输出，实际 ' .. tostring(#out1))
end)

test('or! 命中第二支', function()
	local src = 'hello.[w2]("w.png", auto, auto) {\n scale ? 1\n'
		.. ' why![scale] ? 8 OK\n  dp("hit-8")\n'
		.. ' or![scale] ? 1 OK\n  dp("hit-1")\n'
		.. ' no\n  dp("none")\n stopWhy\n}'
	local out1 = dpOf(src)
	check(out1[1] == 'hit-1', '应命中第二支，实际 ' .. tostring(out1[1]))
end)

test('no 兜底', function()
	local src = 'hello.[w3]("w.png", auto, auto) {\n scale ? 3\n'
		.. ' why![scale] ? 8 OK\n  dp("hit-8")\n'
		.. ' no\n  dp("none")\n stopWhy\n}'
	local out1 = dpOf(src)
	check(out1[1] == 'none', '应走 no 分支，实际 ' .. tostring(out1[1]))
end)

test('多值集合 值,值|属性', function()
	local src = 'hello.[w4]("w.png", auto, auto) {\n alpha ? 0.5\n'
		.. ' why![0.25,0.5|alpha] ? OK\n  dp("in-set")\n'
		.. ' no\n  dp("out-set")\n stopWhy\n}'
	local out1 = dpOf(src)
	check(out1[1] == 'in-set', '应命中集合，实际 ' .. tostring(out1[1]))
end)

test('whynot 反选', function()
	local src = 'hello.[w5]("w.png", auto, auto) {\n alpha ? 0.5\n'
		.. ' why![alpha] ? 0.9 whynot OK\n  dp("neg-hit")\n'
		.. ' no\n  dp("neg-miss")\n stopWhy\n}'
	local out1 = dpOf(src)
	check(out1[1] == 'neg-hit', '反选应命中，实际 ' .. tostring(out1[1]))
end)

test('判断链分支体也能改属性', function()
	local src = 'hello.[w6]("w.png", auto, auto) {\n scale ? 1\n'
		.. ' why![scale] ? 1 OK\n  alpha ? 0.42\n stopWhy\n}'
	load(src, 'why6')
	check(prop('w6', 'alpha') == 0.42, '分支体应改到 alpha')
end)

out('')
out('-- dp 跨语言通信 --')

test('dp() 无参默认文本', function()
	local o = dpOf('hello.[d1]("d.png", auto, auto) { dp() }')
	check(o[1] == 'D.C.LushiFu--U.I.C.', '实际 ' .. tostring(o[1]))
end)

test('dp("字符串")', function()
	local o = dpOf('hello.[d2]("d.png", auto, auto) { dp("FuckYou") }')
	check(o[1] == 'FuckYou', '实际 ' .. tostring(o[1]))
end)

test('dp(元素.属性)', function()
	local o = dpOf('hello.[d3]("d.png", 11, 22) { dp(d3.x) }')
	check(string.find(o[1], '11', 1, true) ~= nil, '应含 11，实际 ' .. tostring(o[1]))
end)

test('dp(元素)', function()
	local o = dpOf('hello.[d4]("d.png", 11, 22) { dp(d4) }')
	check(string.find(o[1], 'd4', 1, true) ~= nil, '应含元素名，实际 ' .. tostring(o[1]))
end)

test('uic.dp() 取完即清空', function()
	load('hello.[d5]("d.png", auto, auto) { dp("x") }', 'dp5')
	uic.dp()
	local b = uic.dp()
	check(#b == 0, '第二次取应为空，实际 ' .. tostring(#b))
end)

out('')
out('-- Lua 侧接口 --')

test('uic.into 读属性', function()
	load('hello.[k1]("k.png", 10, 20)', 'into')
	local k = uic.into('k1')
	check(k ~= nil, 'into 不应返回 nil')
	check(k.x == 10, 'x 应为 10')
	check(k.y == 20, 'y 应为 20')
end)

test('uic.into 写属性', function()
	load('hello.[k2]("k.png", 1, 1)', 'into2')
	local k = uic.into('k2')
	k.alpha = 0.3
	check(MOCK.getProperty('k2.alpha') == 0.3, 'alpha 应被写入')
end)

test('uic.into 未知元素返回 nil', function()
	check(uic.into('压根不存在') == nil, '应返回 nil')
end)

test('uic.getOut 销毁元素', function()
	load('hello.[k3]("k.png", 1, 1)', 'out')
	check(SPRITES['k3'] ~= nil, '创建后应存在')
	check(uic.getOut('k3') == true, 'getOut 应返回 true')
	check(SPRITES['k3'] == nil, '销毁后应消失')
	check(uic.into('k3') == nil, 'into 应返回 nil')
end)

test('uic.reset 清空超全局与元素', function()
	load('*# 主题2 { scale ? 0.5 }\nhello.[r1]("r.png", 1, 1)', 'reset')
	uic.reset(true)
	check(uic.globals['主题2'] == nil, '超全局应被清空')
	check(uic.into('r1') == nil, '元素应被清空')
	check(SPRITES['r1'] == nil, '引擎对象应被销毁')
end)

out('')
out('-- 路径解析 --')

test('相对路径走 mods', function()
	FILES['mods/songs/demo/ui.uic'] = 'hello.[pa]("p.png", 1, 1)'
	uic.load('songs/demo/ui.uic', { raise = true })
	check(SPRITES['pa'] ~= nil, '应加载成功')
	FILES['mods/songs/demo/ui.uic'] = nil
end)

test('uic.file[...] 语法糖', function()
	FILES['mods/a.uic'] = 'hello.[pb]("p.png", 2, 2)'
	-- 注意：Lua 里「单个索引表达式」不能独立成句，必须赋值或调用
	local rt = uic.file['a.uic']
	check(rt ~= nil, 'uic.file[key] 应返回运行时对象')
	check(SPRITES['pb'] ~= nil, 'uic.file 应加载成功')
	FILES['mods/a.uic'] = nil
end)

test('uic.file(...) 调用形式', function()
	FILES['mods/b.uic'] = 'hello.[pc]("p.png", 3, 3)'
	uic.file('b.uic')
	check(SPRITES['pc'] ~= nil, 'uic.file() 应加载成功')
	FILES['mods/b.uic'] = nil
end)

test('盘符路径规范化', function()
	check(uic.normalizePath('C://mods/x.uic') == 'C:/mods/x.uic',
		'实际 ' .. uic.normalizePath('C://mods/x.uic'))
	check(uic.normalizePath('D:\\a\\b.uic') == 'D:/a/b.uic', '反斜杠应转正斜杠')
end)

test('找不到文件时的错误信息', function()
	local ok, err = pcall(uic.load, '不存在的文件.uic', { raise = true })
	check(not ok, '应报错')
	check(string.find(tostring(err), '缺少了定义', 1, true) ~= nil, '错误信息：' .. tostring(err))
end)

out('')
out('-- 错误信息（规范第九节）--')

test('缺少定义：hello~你的[line]中缺少了定义', function()
	expectError('ghost.alpha ? 1', '缺少了定义')
	expectError('*! 空组 {}\nhello.[!空组]', '缺少了定义')
end)

test('未定义引用：你貌似没有定义[@]，检查下声明位置', function()
	expectError('hello.[x1]("x.png", auto, auto) {\n @不存在的样式\n}', '你貌似没有定义@不存在的样式')
	expectError('hello.[x2]("x.png", auto, auto) {\n #不存在的超全局\n}', '你貌似没有定义#不存在的超全局')
	expectError('hello.[!不存在的组]', '你貌似没有定义!不存在的组')
end)

test('越界：你想死啊。[line]', function()
	expectError('hello.[y1]("y.png", auto, auto) {', '你想死啊。')
	expectError('if 1 > 0 {\n y1.alpha ? 1', '你想死啊。')
end)

test('样式组内不写逻辑', function()
	expectError('*@ S { if 1 > 0 { x ? 1 } }\nhello.[z1]("z.png", auto, auto) { @S }', '样式组内不写逻辑')
end)

test('常量不能当样式块用', function()
	expectError('*@ C ? 1\nhello.[z2]("z.png", auto, auto) { @C }', '是一个常量')
end)

test('@ 引用必须前面已声明', function()
	expectError('hello.[z3]("z.png", auto, auto) { @后面才定义 }\n*@ 后面才定义 { alpha ? 1 }', '你貌似没有定义')
end)

test('*! 必须先声明后使用', function()
	expectError('hello.[!先用了]\n*! 先用了 { a, b }', '你貌似没有定义')
end)

test('空元素名当作缺少定义', function()
	expectError('hello.[]("x.png", auto, auto)', '缺少了定义')
	expectError('hello.[a][]("x.png", auto, auto)', '缺少了定义')
end)

test('属性块里出现未知单段目标 → 缺少定义', function()
	expectError('光杆司令', '缺少了定义')
end)

out('')
out('-- 引擎缺失时的降级 --')

test('引擎没有 debugPrint 也不炸', function()
	local saved = _G.debugPrint
	_G.debugPrint = nil
	local ok = pcall(function()
		load('hello.[nd]("n.png", auto, auto) { dp("x") }', 'nodebug')
	end)
	_G.debugPrint = saved
	check(ok, '不应因缺少 debugPrint 而报错')
end)

test('引擎没有 getProperty 也不炸', function()
	local saved = _G.getProperty
	_G.getProperty = nil
	local ok = pcall(function()
		load('hello.[ng]("n.png", auto, auto) { scale ? 1 }', 'noget')
	end)
	_G.getProperty = saved
	check(ok, '不应因缺少 getProperty 而报错')
end)

out('')
out('-- 边界与健壮性 --')

test('else if 链', function()
	local src = 'hello.[ei]("e.png", auto, auto) { scale ? 3 }\n'
		.. 'if ei.scale.x == 1 {\n ei.alpha ? 0.1\n} else if ei.scale.x == 3 {\n ei.alpha ? 0.3\n} else {\n ei.alpha ? 0.9\n}'
	load(src, 'elif')
	check(prop('ei', 'alpha') == 0.3, '应命中 else if 分支，实际 ' .. tostring(prop('ei', 'alpha')))
end)

test('判断链里套判断链', function()
	local src = 'hello.[wn]("w.png", auto, auto) {\n scale ? 1\n alpha ? 0.5\n'
		.. ' why![scale] ? 1 OK\n'
		.. '  why![alpha] ? 0.5 OK\n    dp("inner-hit")\n  stopWhy\n'
		.. ' stopWhy\n}'
	local o = dpOf(src)
	check(o[1] == 'inner-hit', '嵌套判断链应命中，实际 ' .. tostring(o[1]))
end)

test('多元素作用域里判断链逐个判定', function()
	local src = 'hello.[wa][wb]("w.png", auto, auto) { }\n'
		.. 'wa.scale ? 1\nwb.scale ? 2\n'
		.. 'hello.[wa][wb]("w.png", auto, auto) {\n'
		.. ' why![scale] ? 1 OK\n  alpha ? 0.1\n'
		.. ' no\n  alpha ? 0.2\n stopWhy\n}'
	load(src, 'why-multi')
	check(prop('wa', 'alpha') == 0.1, 'wa 应命中 why!，实际 ' .. tostring(prop('wa', 'alpha')))
	check(prop('wb', 'alpha') == 0.2, 'wb 应走 no，实际 ' .. tostring(prop('wb', 'alpha')))
end)

test('样式循环引用会报错', function()
	expectError('*@ A { @B }\n*@ B { @A }\nhello.[cy]("c.png", auto, auto) { @A }', '循环引用')
end)

test('超全局循环引用会报错', function()
	expectError('*# X { #Y }\n*# Y { #X }\nhello.[cx]("c.png", auto, auto) { #X }', '循环引用')
end)

test('负数 / 十六进制颜色 / 算术表达式', function()
	local src = '*@ 负值 ? -1.5\n'
		.. 'hello.[num]("n.png", auto, auto) {\n'
		.. ' angle ? @负值\n alpha ? 0.5 + 0.25\n color ? 0x66CCFF\n}'
	load(src, 'nums')
	check(prop('num', 'angle') == -1.5, '负数，实际 ' .. tostring(prop('num', 'angle')))
	check(prop('num', 'alpha') == 0.75, '算术，实际 ' .. tostring(prop('num', 'alpha')))
	check(prop('num', 'color') == 0x66CCFF, '0x 颜色，实际 ' .. tostring(prop('num', 'color')))
end)

test('#十六进制颜色写法', function()
	load('hello.[hc]("h.png", auto, auto) { color ? #FF00FF }', 'hex')
	check(prop('hc', 'color') == 0xFF00FF, '实际 ' .. tostring(prop('hc', 'color')))
end)

test('别的元素的属性可以参与运算', function()
	local src = 'hello.[a1x]("a.png", 100, 50)\n'
		.. 'hello.[b1x]("b.png", auto, auto) { x ? a1x.x + 20 }'
	load(src, 'refarith')
	check(prop('b1x', 'x') == 120, '实际 ' .. tostring(prop('b1x', 'x')))
end)

test('条件里能读引擎全局', function()
	_G.screenWidth = 1920
	_G.curBeat = 7
	local src = 'hello.[gl]("g.png", auto, auto) { }\n'
		.. 'if screenWidth > 1000 && curBeat == 7 {\n gl.alpha ? 0.77\n}'
	load(src, 'global')
	check(prop('gl', 'alpha') == 0.77, '实际 ' .. tostring(prop('gl', 'alpha')))
	_G.screenWidth = nil
	_G.curBeat = nil
end)

test('未知全局变量 → 未定义引用', function()
	expectError('if 这个全局压根不存在 > 1 {\n dp("x")\n}', '你貌似没有定义')
end)

test('getOutAll 销毁全部元素', function()
	load('hello.[ga]("a.png", 1, 1)\nhello.[gb]("b.png", 2, 2)', 'all')
	uic.getOutAll()
	check(SPRITES['ga'] == nil and SPRITES['gb'] == nil, '应全部销毁')
	check(#uic.elementOrder == 0, 'elementOrder 应清空')
end)

test('文件内容缓存 + reload', function()
	FILES['mods/cache.uic'] = 'hello.[c1x]("c.png", 1, 1)'
	uic.cacheEnabled = true
	uic.load('cache.uic', { raise = true })
	check(uic.sourceCache['mods/cache.uic'] ~= nil, '应写入缓存')
	uic.reload('cache.uic')
	check(uic.sourceCache['mods/cache.uic'] ~= nil, 'reload 后应重新缓存')
	FILES['mods/cache.uic'] = nil
end)

test('uic.setup 批量加载', function()
	FILES['mods/s1.uic'] = 'hello.[su1]("s.png", 1, 1)'
	FILES['mods/s2.uic'] = 'hello.[su2]("s.png", 2, 2)'
	uic.setup({ files = { 's1.uic', 's2.uic' } })
	check(SPRITES['su1'] ~= nil and SPRITES['su2'] ~= nil, '两个文件都应加载')
	FILES['mods/s1.uic'] = nil
	FILES['mods/s2.uic'] = nil
end)

test('uic.tagPrefix 生效', function()
	uic.tagPrefix = 'uic_'
	load('hello.[pf]("p.png", 1, 1)', 'prefix')
	check(SPRITES['uic_pf'] ~= nil, '引擎里应带前缀')
	check(uic.into('pf') ~= nil, 'UIC 侧仍用原名')
	check(uic.into('pf').x == 1, '读属性应走前缀')
	uic.getOut('pf')
	check(SPRITES['uic_pf'] == nil, '销毁应走前缀')
	uic.tagPrefix = ''
end)

test('uic.parse 只解析不执行', function()
	local ast = uic.parse('hello.[nx]("n.png", 1, 1)', 'parseonly')
	check(ast ~= nil and #ast.body == 1, '应返回 AST')
	check(SPRITES['nx'] == nil, '不该创建任何东西')
end)

test('空元素名当作缺少定义', function()
	expectError('hello.[]("x.png", auto, auto)', '缺少了定义')
	expectError('hello.[a][]("x.png", auto, auto)', '缺少了定义')
end)

test('嵌套注释', function()
	local src = '/~\nhello.[nc1]("c.png", 1, 1) /~ 行尾 ~/\n~/\n'
		.. '/~ 外层 /~ 内层 ~/ 还是外层 ~/\nhello.[nc2]("c.png", 2, 2)'
	load(src, 'nestcomment')
	check(SPRITES['nc1'] == nil, 'nc1 应被注释掉')
	check(SPRITES['nc2'] ~= nil, 'nc2 应该存在')
end)

test('空组广播会报缺少定义（不静默）', function()
	expectError('*! 空广播组 {}\n空广播组.alpha ? 1', '缺少了定义')
end)

test('组名出现在表达式里 → 明确提示', function()
	expectError('*! GG {g1}\nhello.[!GG]\ndp(GG.alpha)', '组广播只能用在赋值左边')
end)

test('dp(组名) 会列出成员', function()
	local o = dpOf('*! GD {gd1, gd2}\nhello.[!GD]\ndp(GD)')
	check(string.find(o[1], 'gd1', 1, true) ~= nil, '应列出成员，实际 ' .. tostring(o[1]))
	check(string.find(o[1], 'gd2', 1, true) ~= nil, '应列出成员，实际 ' .. tostring(o[1]))
end)

-- ---------------------------------------------------------------------------
-- 5. 收尾：还原引擎、汇报
-- ---------------------------------------------------------------------------

uic.autoPrint = true
uic.vfs = nil
uic.vfs = {
	exists = function(path)
		local ioLib = rawget(_G, 'io')
		if type(ioLib) ~= 'table' or type(ioLib.open) ~= 'function' then return false end
		local ok, f = pcall(ioLib.open, path, 'r')
		if not ok or f == nil then return false end
		pcall(function() f:close() end)
		return true
	end,
	read = function(path)
		local ioLib = rawget(_G, 'io')
		if type(ioLib) ~= 'table' or type(ioLib.open) ~= 'function' then return nil end
		local ok, f = pcall(ioLib.open, path, 'r')
		if not ok or f == nil then return nil end
		local ok2, content = pcall(function() return f:read('*a') end)
		pcall(function() f:close() end)
		if not ok2 then return nil end
		return content
	end,
}
uic.refreshRoots()

restoreEngine()

-- 给 Node 运行器看的失败计数
_G.__FAILED = FAIL

local summary = {}
summary[#summary + 1] = ''
summary[#summary + 1] = '========================================'
summary[#summary + 1] = 'UIC 测试结果：通过 ' .. tostring(PASS) .. ' 项，失败 ' .. tostring(FAIL) .. ' 项'
if FAIL > 0 then
	summary[#summary + 1] = '失败清单：'
	for i = 1, #FAILURES do
		summary[#summary + 1] = '  - ' .. FAILURES[i]
	end
end
summary[#summary + 1] = '========================================'

for i = 1, #summary do
	print(summary[i])
end

-- 游戏里把结果打到屏幕上
local realDp = rawget(_G, 'debugPrint')
if type(realDp) == 'function' then
	for i = 1, #summary do
		pcall(realDp, summary[i])
	end
end
