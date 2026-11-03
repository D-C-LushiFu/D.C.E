-- ===========================================================================
--  曲目脚本接入示例
--  ---------------------------------------------------------------------------
--  放到：mods/<你的mod>/data/<歌曲名>/ui.lua
--
--  ★ 关键点：D.C.E. / Psych 给**每个 .lua 文件**开一个独立的 Lua state，
--    所以「把 uic.lua 丢进 scripts/ 当全局脚本」并不能让本脚本用上它。
--    必须先把 scripts/ 加进 package.path，再 require。
-- ===========================================================================

-- 把 <你的mod> 换成你 mod 文件夹的真实名字
local MOD_NAME = 'Shit Night Fucking Vs LushiFu Demo'

package.path = package.path .. ';mods/' .. MOD_NAME .. '/scripts/?.lua;mods/' .. MOD_NAME .. '/scripts/?/init.lua'

local uic = require('uic')

-- 告诉 uic 当前 mod（不写也行，库会自己从自身路径推断）
uic.setup({ mod = MOD_NAME })

-- 这次要加载的 UIC 文件（相对路径 → 走 mods/<当前mod>/）
local UIC_FILES = {
	'ui/主题.uic',      -- 先加载超全局定义
	'ui/主菜单.uic',
}

-- dp 的输出也可以挂回调，实时看
uic.onDp = function(text)
	debugPrint(text)
end


-- ---------------------------------------------------------------------------
-- 时机一：曲目创建时（规范里说的「打开对应曲目时调用」）
-- ---------------------------------------------------------------------------
function onCreatePost()
	-- 上一首可能留下了元素，先清干净
	uic.reset(true)

	for _, file in ipairs(UIC_FILES) do
		uic.load(file)
	end

	debugPrint('[UIC] 界面已加载，元素数 = ' .. tostring(#uic.elementOrder))
end


-- ---------------------------------------------------------------------------
-- 时机二：运行中取用 / 改属性 / 销毁
-- ---------------------------------------------------------------------------
function onUpdatePost(elapsed)
	-- 取 dp 的积压消息（取完即清空）
	local messages = uic.dp()
	for _, msg in ipairs(messages) do
		debugPrint('[UIC] ' .. msg)
	end

	-- 直接读元素
	local btn = uic.into('btn开始')
	if btn ~= nil then
		btn.angle = btn.angle + elapsed * 10
	end
end


-- 跟随节拍做点事
function onBeatHit()
	if curBeat == 8 then
		-- 组广播等价物：Lua 侧也可以手动批量改
		uic.into('btn设置').alpha = 0.5
	end
end


-- ---------------------------------------------------------------------------
-- 时机三：离开曲目时清理（元素生命周期归 Lua 端）
-- ---------------------------------------------------------------------------
function onDestroy()
	uic.reset(true)
end
