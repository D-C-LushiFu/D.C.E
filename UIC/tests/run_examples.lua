-- ============================================================================
--  示例端到端验证
--  ---------------------------------------------------------------------------
--  不只是「能解析」，而是真的把 examples/ui/*.uic 跑一遍，
--  断言最终写进假引擎里的属性值。
--
--  跑法（工作目录必须是 UIC/tests）：
--      node run_with_node.js
--      或任意真实 Lua：lua run_examples.lua
--
--  文件读取优先走 Node 宿主提供的全局 __readfile(path)，
--  没有就退回 io.open。
-- ============================================================================

local uic = rawget(_G, 'uic')
if type(uic) ~= 'table' or uic.version == nil then
	local ok, mod = pcall(require, 'uic')
	if ok and type(mod) == 'table' and mod.version ~= nil then uic = mod end
end
if type(uic) ~= 'table' or uic.version == nil then
	local g = rawget(_G, 'uic')
	if type(g) == 'table' and g.version ~= nil then uic = g end
end
if type(uic) ~= 'table' or uic.version == nil then
	print('[示例验证] 找不到 uic 模块，先加载 uic.lua')
	return
end

-- ---------------------------------------------------------------------------
-- 1. 假引擎
-- ---------------------------------------------------------------------------

local SPRITES = {}

local function splitFirst(s, sep)
	local a = string.find(s, sep, 1, true)
	if a == nil then return s, nil end
	return string.sub(s, 1, a - 1), string.sub(s, a + string.len(sep))
end

function makeLuaSprite(tag, image, x, y)
	SPRITES[tag] = {
		__image = image, __animated = false,
		x = x or 0, y = y or 0,
		scale = { x = 1, y = 1 }, offset = { x = 0, y = 0 },
		scrollFactor = { x = 1, y = 1 }, velocity = { x = 0, y = 0 },
		origin = { x = 0, y = 0 },
		alpha = 1, angle = 0, visible = true,
		width = 0, height = 0, color = 4294967295,
		camera = 'game', blend = 'normal', anim = nil,
	}
	return tag
end

function makeAnimatedLuaSprite(tag, image, x, y, t)
	makeLuaSprite(tag, image, x, y)
	SPRITES[tag].__animated = true
	return tag
end

function addLuaSprite(tag, front) end
function removeLuaSprite(tag) SPRITES[tag] = nil end
function luaSpriteExists(tag) return SPRITES[tag] ~= nil end
function setObjectCamera(tag, cam) if SPRITES[tag] then SPRITES[tag].camera = cam end end
function setBlendMode(tag, b) if SPRITES[tag] then SPRITES[tag].blend = b end end
function playAnim(tag, n) if SPRITES[tag] then SPRITES[tag].anim = n end end
function setSpriteShader(tag, s) end
function debugPrint(text) end

function setProperty(path, value)
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

function getProperty(path)
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

-- 引擎全局（Psych 会给这些）
screenWidth = 1920
screenHeight = 1080
curBeat = 0

-- ---------------------------------------------------------------------------
-- 2. 从磁盘读 .uic
-- ---------------------------------------------------------------------------

local function diskRead(path)
	local f = rawget(_G, '__readfile')
	if type(f) == 'function' then
		local ok, content = pcall(f, path)
		if ok then return content end
		return nil
	end
	local ioLib = rawget(_G, 'io')
	if type(ioLib) ~= 'table' or type(ioLib.open) ~= 'function' then return nil end
	local h = ioLib.open(path, 'r')
	if h == nil then return nil end
	local content = h:read('*a')
	h:close()
	return content
end

uic.vfs = {
	exists = function(p) return diskRead(p) ~= nil end,
	read = diskRead,
}
uic.roots = { '../examples/', 'examples/', '' }
uic.autoPrint = false

-- ---------------------------------------------------------------------------
-- 3. 断言
-- ---------------------------------------------------------------------------

local PASS, FAIL, FAILURES = 0, 0, {}

local function check(cond, msg)
	if not cond then error(msg or '断言失败', 0) end
end

local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		PASS = PASS + 1
		print('  [通过] ' .. name)
	else
		FAIL = FAIL + 1
		FAILURES[#FAILURES + 1] = name .. ' :: ' .. tostring(err)
		print('  [失败] ' .. name .. ' :: ' .. tostring(err))
	end
end

local function p(tag, path)
	return getProperty(tag .. '.' .. path)
end

print('=== UIC 示例端到端验证 ===')
print('')

uic.reset(true)
uic.clearDp()

test('加载 主题.uic（跨文件超全局）', function()
	local rt = uic.load('ui/主题.uic', { raise = true })
	check(rt ~= nil, '加载失败：' .. tostring(uic.lastError))
	check(uic.globals['标准缩放'] ~= nil, '标准缩放 未定义')
	check(uic.globals['按钮基底'] ~= nil, '按钮基底 未定义')
end)

test('加载 主菜单.uic', function()
	local rt = uic.load('ui/主菜单.uic', { raise = true })
	check(rt ~= nil, '加载失败：' .. tostring(uic.lastError))
end)

test('元素都创建出来了', function()
	check(SPRITES['btn开始'] ~= nil, 'btn开始 未创建')
	check(SPRITES['btn设置'] ~= nil, 'btn设置 未创建')
	check(SPRITES['btn退出'] ~= nil, 'btn退出 未创建')
	check(SPRITES['占位块'] ~= nil, '占位块 未创建')
	check(SPRITES['面板'] ~= nil, '面板 未创建')
end)

test('资源路径与坐标', function()
	check(SPRITES['btn开始'].__image == 'ui/btn.png', '资源路径不对：' .. tostring(SPRITES['btn开始'].__image))
	check(p('btn开始', 'x') == 640, 'x 应为 640，实际 ' .. tostring(p('btn开始', 'x')))
	check(p('btn设置', 'y') == 380, 'y 应为 380，实际 ' .. tostring(p('btn设置', 'y')))
end)

test('无资源元素按 50px 填充', function()
	check(p('占位块', 'width') == 50, '宽度应为 50，实际 ' .. tostring(p('占位块', 'width')))
	check(p('占位块', 'height') == 50, '高度应为 50')
	check(SPRITES['占位块'].__image == nil, '不该有资源')
end)

test('超全局 → 样式嵌套叠加（0.85 * 0.8 = 0.68）', function()
	local v = p('btn设置', 'scale.x')
	check(v ~= nil, 'scale.x 为空')
	check(math.abs(v - 0.68) < 0.0001, 'btn设置.scale.x 应为 0.68，实际 ' .. tostring(v))
end)

test('后面的直接赋值覆盖样式标记', function()
	local v = p('btn开始', 'scale.x')
	check(math.abs(v - 0.8) < 0.0001, 'btn开始.scale.x 应为 0.8（@按钮尺寸），实际 ' .. tostring(v))
end)

test('超全局里的 camera 传到了元素上', function()
	check(SPRITES['btn设置'].camera == 'hud',
		'camera 应为 hud，实际 ' .. tostring(SPRITES['btn设置'].camera))
end)

test('组广播后来者居上（0.95）', function()
	local a = p('btn开始', 'alpha')
	local b = p('btn设置', 'alpha')
	check(math.abs(a - 0.95) < 0.0001, 'btn开始.alpha 应为 0.95，实际 ' .. tostring(a))
	check(math.abs(b - 0.95) < 0.0001, 'btn设置.alpha 应为 0.95，实际 ' .. tostring(b))
end)

test('条件块改的是 angle，没盖掉组广播', function()
	check(p('btn开始', 'angle') == 5, 'btn开始.angle 应为 5，实际 ' .. tostring(p('btn开始', 'angle')))
end)

test('次级按钮样式叠加了 alpha 0.75', function()
	local v = p('btn退出', 'alpha')
	check(math.abs(v - 0.95) < 0.0001, '组广播应把 alpha 刷成 0.95，实际 ' .. tostring(v))
end)

test('条件：screenWidth 1920 → 面板 alpha 0.75', function()
	local v = p('面板', 'alpha')
	check(math.abs(v - 0.75) < 0.0001, '面板.alpha 应为 0.75，实际 ' .. tostring(v))
end)

test('dp 输出可被 Lua 侧取回', function()
	local msgs = uic.dp()
	check(#msgs >= 3, '至少应有 3 条 dp 输出，实际 ' .. tostring(#msgs))
	local joined = table.concat(msgs, ' | ')
	check(string.find(joined, '主菜单已构建', 1, true) ~= nil, '缺少 dp("主菜单已构建")：' .. joined)
	check(string.find(joined, 'btn开始', 1, true) ~= nil, '缺少 dp(btn开始)：' .. joined)
end)

test('加载 暂停界面.uic（判断链）', function()
	local rt = uic.load('ui/暂停界面.uic', { raise = true })
	check(rt ~= nil, '加载失败：' .. tostring(uic.lastError))
end)

test('why! 命中：scale 8 → alpha 1', function()
	check(p('按钮', 'scale.x') == 8, 'scale 应为 8')
	check(p('按钮', 'alpha') == 1, 'why! 分支应把 alpha 设为 1，实际 ' .. tostring(p('按钮', 'alpha')))
end)

test('多值集合命中：0.25,0.5,0.75|alpha → angle 10', function()
	check(p('图标', 'alpha') == 0.5, 'alpha 应为 0.5')
	check(p('图标', 'angle') == 10, 'angle 应为 10，实际 ' .. tostring(p('图标', 'angle')))
end)

test('whynot 反选命中：alpha 1 ≠ 0 → visible', function()
	check(p('提示', 'visible') == true, 'visible 应为 true')
end)

test('判断链里套 if：screenWidth 1920 → scale 1.2', function()
	local v = p('滑块', 'scale.x')
	check(math.abs(v - 1.2) < 0.0001, 'scale 应为 1.2，实际 ' .. tostring(v))
end)

test('Lua 侧能取用元素并改属性', function()
	local icon = uic.into('图标')
	check(icon ~= nil, 'into 返回 nil')
	check(icon.alpha == 0.5, '读 alpha 失败')
	icon.alpha = 0.9
	check(p('图标', 'alpha') == 0.9, '写 alpha 失败')
	check(uic.getOut('图标') == true, 'getOut 失败')
	check(SPRITES['图标'] == nil, '引擎对象未销毁')
end)

test('元素清单可用', function()
	check(#uic.elementOrder > 0, 'elementOrder 为空')
end)

-- ---------------------------------------------------------------------------
-- 4. 汇总
-- ---------------------------------------------------------------------------

uic.reset(true)

-- 给 Node 运行器看的失败计数
_G.__FAILED = FAIL

print('')
print('========================================')
print('示例验证：通过 ' .. tostring(PASS) .. ' 项，失败 ' .. tostring(FAIL) .. ' 项')
if FAIL > 0 then
	for i = 1, #FAILURES do
		print('  - ' .. FAILURES[i])
	end
end
print('========================================')

local realDp = rawget(_G, 'debugPrint')
if type(realDp) == 'function' and #FAILURES > 0 then
	pcall(realDp, 'UIC 示例验证失败 ' .. tostring(FAIL) .. ' 项，详见控制台')
end
