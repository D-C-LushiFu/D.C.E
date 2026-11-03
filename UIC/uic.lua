--[[============================================================================
  UIC — U Idea Code 运行时库（Lua 版）
  ---------------------------------------------------------------------------
  面向 D.C.E. / Psych 引擎的轻量级 UI 声明语言运行时。

      声明结构归 UIC，逻辑归 Lua，渲染归 FNF 原生 API。

  用法（Lua 侧）：
      local uic = require('uic')            -- 或者库被引擎当作全局脚本加载后，
                                            -- 直接使用全局变量 uic
      uic.file['songs/bopeebo/ui/main.uic'] -- 加载并执行一个 .uic 文件
      local btn = uic.into('btn1')          -- 取用元素
      btn.scale = 1.2                       -- 改属性
      uic.getOut('btn1')                    -- 销毁元素
      local log = uic.dp()                  -- 接收 UIC 侧 dp() 的输出

  设计约束（重要）：
    本库刻意只使用「最小公共 Lua 子集」编写，以便：
      1. 在 LuaJIT（游戏内）与 Haxe/Lua 解释器（跑测试）上行为一致；
      2. 不依赖字符串元表，故不使用 s:method() 形式，一律 string.fn(s, ...)；
      3. 不使用 string.gmatch / string.match / 带捕获的 string.find /
         带函数的 string.gsub —— 全部手写扫描，避免不同实现的差异；
      4. 文件读取统一走 uic.vfs，方便测试注入与引擎侧替换；
      5. 不依赖 table.sort。
    因此本文件可以被整体复制进任何 mod 而无需拆分模块。

  版本：1.0.0
============================================================================]]

local UIC_VERSION = '1.0.0'

--==========================================================================
-- 0. 基础工具（最小公共 Lua 子集）
--==========================================================================

local uic = {}

uic.version = UIC_VERSION

--- 安全的 tostring：LuaJIT 下 nil 是 "nil"，部分实现是 "null"，统一成 "nil"
local function str(v)
	if v == nil then return 'nil' end
	if v == true then return 'true' end
	if v == false then return 'false' end
	return tostring(v)
end

--- 数字 → 字符串：整数不带小数点，浮点最多保留 6 位并去掉尾随 0
--- 刻意不用 string.format('%.6f')，因为部分 Lua 实现不支持浮点格式符
local function numToStr(n)
	if n == nil then return 'nil' end
	if type(n) ~= 'number' then return str(n) end
	if n ~= n then return 'nan' end
	if n == math.huge then return 'inf' end
	if n == -math.huge then return '-inf' end

	local neg = (n < 0)
	local a = neg and -n or n
	local intPart = math.floor(a)
	local frac = a - intPart
	local sign = neg and '-' or ''
	local intStr = string.format('%d', intPart)

	if frac < 1e-9 then return sign .. intStr end

	local digits = {}
	local f = frac
	for _ = 1, 6 do
		f = f * 10
		local d = math.floor(f + 1e-9)
		if d > 9 then d = 9 end
		if d < 0 then d = 0 end
		digits[#digits + 1] = string.char(48 + d)
		f = f - d
	end
	local fs = table.concat(digits, '')
	local cut = 6
	while cut > 0 and string.sub(fs, cut, cut) == '0' do cut = cut - 1 end
	fs = string.sub(fs, 1, cut)
	if fs == '' then return sign .. intStr end
	return sign .. intStr .. '.' .. fs
end

--- 判断字符是否为空白（不含换行）
local function isSpaceByte(b)
	return b == 32 or b == 9 or b == 13 or b == 11 or b == 12
end

--- 手写 trim
local function trim(s)
	if s == nil then return '' end
	s = str(s)
	local n = string.len(s)
	local i = 1
	while i <= n do
		local b = string.byte(s, i)
		if not isSpaceByte(b) and b ~= 10 then break end
		i = i + 1
	end
	local j = n
	while j >= i do
		local b = string.byte(s, j)
		if not isSpaceByte(b) and b ~= 10 then break end
		j = j - 1
	end
	return string.sub(s, i, j)
end

--- 手写 startsWith / endsWith
local function startsWith(s, prefix)
	if s == nil or prefix == nil then return false end
	return string.sub(s, 1, string.len(prefix)) == prefix
end

--- 手写 endsWith
local function endsWith(s, suffix)
	if s == nil or suffix == nil then return false end
	local ls, lf = string.len(s), string.len(suffix)
	if lf > ls then return false end
	return string.sub(s, ls - lf + 1) == suffix
end

--- 手写「纯文本」查找（不用模式），返回起始下标或 nil
local function findPlain(s, sub, init)
	if s == nil or sub == nil or sub == '' then return nil end
	init = init or 1
	local ok, a = pcall(string.find, s, sub, init, true)
	if ok and a ~= nil then return a end
	return nil
end

--- 手写「纯文本」替换（不用 string.gsub 的回调/模式特性）
local function replacePlain(s, from, to)
	if s == nil or from == nil or from == '' then return s end
	local out = {}
	local pos = 1
	local n = string.len(s)
	local fl = string.len(from)
	while pos <= n do
		local a = findPlain(s, from, pos)
		if a == nil then
			out[#out + 1] = string.sub(s, pos)
			break
		end
		if a > pos then out[#out + 1] = string.sub(s, pos, a - 1) end
		out[#out + 1] = to
		pos = a + fl
	end
	if n == 0 then return s end
	return table.concat(out, '')
end

--- 手写按分隔符切分（纯文本，不解释模式）
local function splitPlain(s, sep)
	local out = {}
	if s == nil then return out end
	s = str(s)
	if sep == nil or sep == '' then
		out[1] = s
		return out
	end
	local pos = 1
	local n = string.len(s)
	local sl = string.len(sep)
	while true do
		local a = findPlain(s, sep, pos)
		if a == nil then
			out[#out + 1] = string.sub(s, pos)
			break
		end
		out[#out + 1] = string.sub(s, pos, a - 1)
		pos = a + sl
		if pos > n + 1 then break end
	end
	return out
end

--- 手写重复
local function repeatStr(s, n)
	if n == nil or n < 1 then return '' end
	local out = {}
	for _ = 1, n do out[#out + 1] = s end
	return table.concat(out, '')
end

--- 是否是「看起来像数字」的字符串（用于 *@ 常量 ? 值 的判断）
local function isNumericString(s)
	if s == nil or s == '' then return false end
	local n = string.len(s)
	local i = 1
	if string.byte(s, 1) == 45 then i = 2 end -- '-'
	local seenDigit, seenDot = false, false
	while i <= n do
		local b = string.byte(s, i)
		if b >= 48 and b <= 57 then
			seenDigit = true
		elseif b == 46 and not seenDot then
			seenDot = true
		else
			return false
		end
		i = i + 1
	end
	return seenDigit
end

--- 是否是十六进制颜色字面量，如 FFFF00 / FF00FF80
local function isHexColor(s)
	if s == nil then return false end
	local n = string.len(s)
	if n ~= 3 and n ~= 4 and n ~= 6 and n ~= 8 then return false end
	for i = 1, n do
		local b = string.byte(s, i)
		local isDigit = (b >= 48 and b <= 57)
		local isUpper = (b >= 65 and b <= 70)
		local isLower = (b >= 97 and b <= 102)
		if not (isDigit or isUpper or isLower) then return false end
	end
	return true
end

--- 十六进制颜色字符串 → 数字
local function hexToNumber(s)
	local n = 0
	local len = string.len(s)
	for i = 1, len do
		local b = string.byte(s, i)
		local d
		if b >= 48 and b <= 57 then d = b - 48
		elseif b >= 65 and b <= 70 then d = b - 55
		elseif b >= 97 and b <= 102 then d = b - 87
		else return nil end
		n = n * 16 + d
	end
	return n
end

--- 取字符串的「逻辑长度」：UTF-8 连续字节按 1 个字符算（错误信息用）
local function utf8Len(s)
	if s == nil then return 0 end
	local n, count = string.len(s), 0
	local i = 1
	while i <= n do
		local b = string.byte(s, i)
		if b < 128 then i = i + 1
		elseif b < 224 then i = i + 2
		elseif b < 240 then i = i + 3
		else i = i + 4 end
		count = count + 1
	end
	return count
end

--- 安全调用引擎函数（引擎里不存在时降级，不炸）
local engineWarnings = {}

local function engineFn(name)
	local f = rawget(_G, name)
	if type(f) == 'function' then return f end
	return nil
end

local function callEngine(name, ...)
	local f = engineFn(name)
	if f == nil then
		if not engineWarnings[name] then
			engineWarnings[name] = true
			-- 用最朴素的方式吐一次警告，避免刷屏
			local dp = rawget(_G, 'debugPrint')
			if type(dp) == 'function' then
				pcall(dp, '[UIC] 引擎缺少函数 ' .. name .. '()，该调用被跳过')
			end
		end
		return nil
	end
	return f(...)
end

local function hasEngine(name)
	return engineFn(name) ~= nil
end

--==========================================================================
-- 1. 错误信息（严格遵循 UIC 语法规范第九节）
--==========================================================================

local Err = {}

--- 错误对象统一用字符串承载，带 UIC 前缀，便于区分引擎自身抛的错
local UIC_ERR_TAG = '[UIC]'

local function makeError(text)
	return UIC_ERR_TAG .. ' ' .. text
end

--- 缺少定义：hello~你的[line]中缺少了定义
function Err.missingDef(line)
	return makeError('hello~你的[' .. str(line) .. ']中缺少了定义')
end

--- 越界：你想死啊。[line]
function Err.outOfRange(line)
	return makeError('你想死啊。' .. str(line))
end

--- 未定义引用：你貌似没有定义[报错的@]，检查下声明位置
function Err.undefinedRef(name)
	return makeError('你貌似没有定义' .. str(name) .. '，检查下声明位置')
end

--- 其余通用错误
function Err.generic(fileName, line, text)
	local where = ''
	if fileName then where = ' (' .. str(fileName) .. ':' .. str(line) .. ')' end
	return makeError(str(text) .. where)
end

Err.TAG = UIC_ERR_TAG

--- 抛错
local function fail(text)
	error(text, 0)
end

--- 判断某个错误字符串是不是 UIC 自己的
local function isUicError(e)
	if type(e) ~= 'string' then return false end
	return startsWith(e, UIC_ERR_TAG)
end

--==========================================================================
-- 2. 词法分析器
--==========================================================================

--- Token 结构：
---   { t = 'name'|'number'|'string'|'punct'|'newline'|'eof',
---     v = 值, line = 行号, col = 列号 }
---
--- 说明：UIC 不把 hello/if/why 等当作硬关键字 —— 词法层统一产出 'name'，
---       由语法层按上下文判定，这样 [...] 里的字面名字永远不会被误伤。

local Lexer = {}

local PUNCT2 = {
	['=='] = true, ['!='] = true, ['>='] = true, ['<='] = true,
	['&&'] = true, ['||'] = true, ['..'] = true, ['~='] = true,
}

local PUNCT1 = {
	['['] = true, [']'] = true, ['('] = true, [')'] = true,
	['{'] = true, ['}'] = true, ['?'] = true, ['.'] = true,
	[','] = true, ['@'] = true, ['#'] = true, ['!'] = true,
	['*'] = true, ['~'] = true, ['|'] = true, [';'] = true,
	['='] = true, ['<'] = true, ['>'] = true, ['&'] = true,
	['+'] = true, ['-'] = true, ['/'] = true, ['%'] = true,
	[':'] = true,
}

--- 创建词法分析器
--- @param src string 源码
--- @param fileName string 文件名（错误信息用）
function Lexer.new(src, fileName)
	local self = {}
	self.src = src or ''
	self.file = fileName or '<uic>'
	self.pos = 1
	self.line = 1
	self.col = 1
	self.len = string.len(self.src)

	-- 去掉 UTF-8 BOM（记事本另存为 UTF-8 会加）
	if self.len >= 3 then
		if string.byte(self.src, 1) == 239
			and string.byte(self.src, 2) == 187
			and string.byte(self.src, 3) == 191 then
			self.pos = 4
			self.col = 4
		end
	end
	return self
end

--- 当前字节（越界返回 nil）
local function peekByte(self, offset)
	offset = offset or 0
	local p = self.pos + offset
	if p > self.len then return nil end
	return string.byte(self.src, p)
end

--- 当前字符（1 字节，UIC 语法全是 ASCII 结构符号）
local function peekChar(self, offset)
	offset = offset or 0
	local p = self.pos + offset
	if p > self.len then return nil end
	return string.sub(self.src, p, p)
end

--- 前进 n 个字节，维护行列号
local function advance(self, n)
	n = n or 1
	for _ = 1, n do
		if self.pos > self.len then return end
		local b = string.byte(self.src, self.pos)
		if b == 10 then
			self.line = self.line + 1
			self.col = 1
		else
			self.col = self.col + 1
		end
		self.pos = self.pos + 1
	end
end

--- 跳过 `/~ ... ~/` 注释，返回 true 表示吃掉了一段注释
--- 支持嵌套：`/~ 外层 /~ 内层 ~/ 还是外层 ~/`
--- 这样可以把一整段带注释的代码直接注掉。
local function skipComment(self)
	if peekChar(self, 0) ~= '/' then return false end
	if peekChar(self, 1) ~= '~' then return false end
	advance(self, 2)
	local depth = 1
	while self.pos <= self.len do
		local c = peekChar(self)
		local n = peekChar(self, 1)
		if c == '/' and n == '~' then
			advance(self, 2)
			depth = depth + 1
		elseif c == '~' and n == '/' then
			advance(self, 2)
			depth = depth - 1
			if depth == 0 then return true end
		else
			advance(self, 1)
		end
	end
	-- 注释没闭合：宽容处理，吃到文件尾
	return true
end

--- 跳过空白与注释，返回是否吃掉了换行
local function skipTrivia(self)
	local sawNewline = false
	while self.pos <= self.len do
		local c = peekChar(self)
		if c == '/' and peekChar(self, 1) == '~' then
			skipComment(self)
		elseif c == '\n' then
			advance(self, 1)
			sawNewline = true
		elseif isSpaceByte(string.byte(self.src, self.pos)) then
			advance(self, 1)
		else
			break
		end
	end
	return sawNewline
end

--- 扫描一个标识符/名字（允许 UTF-8 字节，允许 '-' 与 '_'，允许数字）
--- 注意：UIC 里 '-' 可以作为名字的一部分（如 btn1-），所以这里放开
local function scanName(self)
	local startPos = self.pos
	local startCol = self.col
	while self.pos <= self.len do
		local b = string.byte(self.src, self.pos)
		local isWord = (b >= 48 and b <= 57)          -- 0-9
			or (b >= 65 and b <= 90)                  -- A-Z
			or (b >= 97 and b <= 122)                 -- a-z
			or b == 95                                -- _
			or b == 45                                -- -
			or b >= 128                               -- UTF-8 中文等
		if not isWord then break end
		advance(self, 1)
	end
	return {
		t = 'name',
		v = string.sub(self.src, startPos, self.pos - 1),
		line = self.line,
		col = startCol,
	}
end

--- 扫描数字：十进制 / 浮点 / 0x 十六进制
local function scanNumber(self)
	local startPos = self.pos
	local startCol = self.col

	-- 0x / 0X 十六进制
	if peekChar(self) == '0' then
		local c1 = peekChar(self, 1)
		if c1 == 'x' or c1 == 'X' then
			advance(self, 2)
			while self.pos <= self.len do
				local b = string.byte(self.src, self.pos)
				local isHex = (b >= 48 and b <= 57) or (b >= 65 and b <= 70) or (b >= 97 and b <= 102)
				if not isHex then break end
				advance(self, 1)
			end
			local raw = string.sub(self.src, startPos, self.pos - 1)
			local digits = string.sub(raw, 3)
			local value = hexToNumber(digits)
			return { t = 'number', v = value or 0, raw = raw, line = self.line, col = startCol }
		end
	end

	while self.pos <= self.len do
		local b = string.byte(self.src, self.pos)
		local isDigit = (b >= 48 and b <= 57)
		local isDot = (b == 46) and (peekByte(self, 1) ~= nil) and (peekByte(self, 1) >= 48) and (peekByte(self, 1) <= 57)
		if not (isDigit or isDot) then break end
		advance(self, 1)
	end
	-- 指数部分
	local e = peekChar(self)
	if e == 'e' or e == 'E' then
		local save = self.pos
		advance(self, 1)
		local sign = peekChar(self)
		if sign == '+' or sign == '-' then advance(self, 1) end
		local b = peekByte(self)
		if b ~= nil and b >= 48 and b <= 57 then
			while self.pos <= self.len do
				local d = string.byte(self.src, self.pos)
				if not (d >= 48 and d <= 57) then break end
				advance(self, 1)
			end
		else
			self.pos = save -- 回退，e 不是指数
		end
	end

	local raw = string.sub(self.src, startPos, self.pos - 1)
	return { t = 'number', v = tonumber(raw) or 0, raw = raw, line = self.line, col = startCol }
end

--- 扫描字符串（单双引号都可以，支持 \n \t \" \\ \r 转义）
local function scanString(self)
	local quote = peekChar(self)
	local startLine = self.line
	local startCol = self.col
	advance(self, 1)
	local out = {}
	while self.pos <= self.len do
		local c = peekChar(self)
		if c == '\\' then
			local nxt = peekChar(self, 1)
			if nxt == 'n' then out[#out + 1] = '\n'; advance(self, 2)
			elseif nxt == 't' then out[#out + 1] = '\t'; advance(self, 2)
			elseif nxt == 'r' then out[#out + 1] = '\r'; advance(self, 2)
			elseif nxt == '0' then out[#out + 1] = '\0'; advance(self, 2)
			elseif nxt == '\\' then out[#out + 1] = '\\'; advance(self, 2)
			elseif nxt == '"' then out[#out + 1] = '"'; advance(self, 2)
			elseif nxt == "'" then out[#out + 1] = "'"; advance(self, 2)
			else
				-- 未知转义：原样保留
				out[#out + 1] = nxt or ''
				advance(self, 2)
			end
		elseif c == quote then
			advance(self, 1)
			return {
				t = 'string',
				v = table.concat(out, ''),
				line = startLine,
				col = startCol,
			}
		elseif c == '\n' then
			-- 字符串里不允许裸换行，宽容地允许跨行
			out[#out + 1] = c
			advance(self, 1)
		else
			out[#out + 1] = c
			advance(self, 1)
		end
	end
	-- 没闭合：报错
	fail(Err.generic(self.file, startLine, '你想死啊。' .. str(startLine) .. ' 行有一个没闭合的字符串'))
end

--- 扫描下一个 token
--- 每个 token 都带 p / ep：在源码中的起始与结束字节偏移，
--- 供语法层原样取出 `[...]` / `{...}` 里的字面文本。
local function lexNext(self)
	-- 跳过空白与注释（其中可能跨行，所以行号必须在跳完之后再取）
	while self.pos <= self.len do
		local c = peekChar(self)
		if c == '/' and peekChar(self, 1) == '~' then
			skipComment(self)
		elseif isSpaceByte(string.byte(self.src, self.pos)) then
			advance(self, 1)
		else
			break
		end
	end

	local tokStart = self.pos
	local tokLine = self.line
	local tokCol = self.col

	--- 给 token 补上偏移信息
	local function emit(tok)
		tok.p = tokStart
		tok.ep = self.pos - 1
		if tok.line == nil then tok.line = tokLine end
		if tok.col == nil then tok.col = tokCol end
		return tok
	end

	if self.pos > self.len then
		return emit({ t = 'eof', v = '<eof>' })
	end

	local c = peekChar(self)

	-- 换行（连续空行折叠成一个 newline token）
	if c == '\n' then
		while self.pos <= self.len do
			local c2 = peekChar(self)
			if c2 == '\n' then
				advance(self, 1)
			elseif isSpaceByte(string.byte(self.src, self.pos)) then
				advance(self, 1)
			elseif c2 == '/' and peekChar(self, 1) == '~' then
				skipComment(self)
			else
				break
			end
		end
		return emit({ t = 'newline', v = '\n' })
	end

	-- 字符串
	if c == '"' or c == "'" then
		return emit(scanString(self))
	end

	-- 数字（'-' 只作为名字的一部分，负号交给语法层的一元运算符）
	local b = string.byte(self.src, self.pos)
	if b >= 48 and b <= 57 then
		return emit(scanNumber(self))
	end

	-- 双字符符号
	local two = string.sub(self.src, self.pos, self.pos + 1)
	if PUNCT2[two] then
		advance(self, 2)
		return emit({ t = 'punct', v = two })
	end

	-- 单字符符号
	if PUNCT1[c] then
		advance(self, 1)
		return emit({ t = 'punct', v = c })
	end

	-- 名字（含中文等 UTF-8）
	if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95 or b >= 128 then
		return emit(scanName(self))
	end

	-- 认不出来的字符
	fail(Err.generic(self.file, tokLine, '你想死啊。' .. str(tokLine) .. ' 行有个不认识的字符 ' .. str(c)))
end

--- 一次性产出全部 token
function Lexer.tokenize(src, fileName)
	local self = Lexer.new(src, fileName)
	local tokens = {}
	local guard = 0
	while true do
		guard = guard + 1
		if guard > 2000000 then
			fail(Err.generic(fileName, self.line, '文件太大或词法分析进入死循环'))
		end
		local tok = lexNext(self)
		tokens[#tokens + 1] = tok
		if tok.t == 'eof' then break end
	end
	return tokens
end

--==========================================================================
-- 3. 语法分析器（Parser → AST）
--==========================================================================
--
--  AST 节点一览
--    program       { body = {stmt...} }
--    group_decl    *! 组名 {a, b, c}          → { name, members }
--    style_decl    *@ / *# 名字 { ... } / ? 值 → { scope, name, body|value }
--    elem_decl     hello.[名][名](路径, 参数) { } → { names, path, args, block }
--    group_import  hello.[!组名] { }           → { name, block }
--    assign        目标.属性 ? 值              → { target, value }
--    apply_style   @名字 / #名字（块内语句）    → { scope, name }
--    if            if 条件 { } else { }        → { cond, thenBody, elseBody }
--    why           判断链                      → { branches = { {op, spec, body} } }
--    dp            dp(...)                     → { args }
--
--  表达式节点
--    num / str / bool / nil_ / auto / color
--    ref          元素.属性 路径
--    style_ref    @常量名（文件内）
--    super_ref    #常量名（跨文件）
--    bin / un     二元 / 一元运算
--    dp           dp(...) 作为表达式

local Parser = {}
Parser.__index = Parser

function Parser.new(tokens, src, fileName)
	local self = setmetatable({}, Parser)
	self.toks = tokens
	self.i = 1
	self.src = src or ''
	self.file = fileName or '<uic>'
	return self
end

-- ---- 基础读取 ----------------------------------------------------------

function Parser:cur() return self.toks[self.i] end
function Parser:peek(n) return self.toks[self.i + (n or 0)] end
function Parser:adv()
	local t = self.toks[self.i]
	self.i = self.i + 1
	return t
end

local function isPunct(tok, v)
	return tok ~= nil and tok.t == 'punct' and tok.v == v
end

local function isName(tok, v)
	return tok ~= nil and tok.t == 'name' and tok.v == v
end

local function isLineEnd(tok)
	if tok == nil then return true end
	if tok.t == 'newline' or tok.t == 'eof' then return true end
	if isPunct(tok, '}') or isPunct(tok, ';') then return true end
	return false
end

function Parser:skipNewlines()
	while self:cur().t == 'newline' do self:adv() end
end

function Parser:skipSeps()
	while true do
		local t = self:cur()
		if t.t == 'newline' or isPunct(t, ';') then
			self:adv()
		else
			break
		end
	end
end

function Parser:expectPunct(v, line)
	if not isPunct(self:cur(), v) then
		fail(Err.generic(self.file, line or self:cur().line,
			'你想死啊。' .. str(line or self:cur().line) .. ' 行缺少了 ' .. v))
	end
	return self:adv()
end

--- 原样取出 `[` 到配对 `]` 之间的文本（按字面处理，不解释成表达式）
function Parser:readBracketRaw()
	local open = self:cur()
	if not isPunct(open, '[') then
		fail(Err.generic(self.file, open.line, '你想死啊。' .. str(open.line) .. ' 行期待 [ 却遇到 ' .. str(open.v)))
	end
	self:adv()
	local startP = self:cur().p
	local depth = 1
	local guard = 0
	while true do
		guard = guard + 1
		if guard > 500000 then fail(Err.outOfRange(open.line)) end
		local t = self:cur()
		if t.t == 'eof' then fail(Err.outOfRange(open.line)) end
		if isPunct(t, '[') then
			depth = depth + 1
		elseif isPunct(t, ']') then
			depth = depth - 1
			if depth == 0 then
				local raw = string.sub(self.src, startP, t.p - 1)
				self:adv()
				return trim(raw), open.line
			end
		end
		self:adv()
	end
end

--- 原样取出 `{` 到配对 `}` 之间的文本（*! 组成员列表用）
function Parser:readBraceRaw()
	local open = self:cur()
	if not isPunct(open, '{') then
		fail(Err.generic(self.file, open.line, '你想死啊。' .. str(open.line) .. ' 行期待 { 却遇到 ' .. str(open.v)))
	end
	self:adv()
	local startP = self:cur().p
	local depth = 1
	local guard = 0
	while true do
		guard = guard + 1
		if guard > 500000 then fail(Err.outOfRange(open.line)) end
		local t = self:cur()
		if t.t == 'eof' then fail(Err.outOfRange(open.line)) end
		if isPunct(t, '{') then
			depth = depth + 1
		elseif isPunct(t, '}') then
			depth = depth - 1
			if depth == 0 then
				local raw = string.sub(self.src, startP, t.p - 1)
				self:adv()
				return raw
			end
		end
		self:adv()
	end
end

--- 把 `a, b, c` 这种字面列表切分成数组（自动去掉两侧空白与空项）
local function parseNameList(raw)
	local out = {}
	local parts = splitPlain(raw, ',')
	for i = 1, #parts do
		local name = trim(parts[i])
		name = replacePlain(name, '\n', '')
		name = trim(name)
		if name ~= '' then out[#out + 1] = name end
	end
	return out
end

-- ---- 块 ---------------------------------------------------------------

--- 判断某个位置是不是「判断链」的分支开头
local function isWhyBranchStart(cur, nxt)
	if nxt ~= nil and isPunct(nxt, '!') then
		if isName(cur, 'why') or isName(cur, 'or') or isName(cur, 'and') then
			return true
		end
	end
	return false
end

--- 收集语句，直到 `}` / eof /（stopAtWhy 时）判断链的下一个分支
function Parser:parseStatements(stopAtWhy)
	local stmts = {}
	self:skipSeps()
	local guard = 0
	while true do
		guard = guard + 1
		if guard > 1000000 then fail(Err.outOfRange(self:cur().line)) end
		local t = self:cur()
		if t.t == 'eof' then break end
		if isPunct(t, '}') then break end
		if stopAtWhy then
			if isWhyBranchStart(t, self:peek(1)) then break end
			if isName(t, 'stopWhy') then break end
			if isName(t, 'no') and isLineEnd(self:peek(1)) then break end
		end
		local s = self:parseStatement(false)
		if s ~= nil then stmts[#stmts + 1] = s end
		self:skipSeps()
	end
	return stmts
end

--- 尝试解析 `{ ... }`；没有就返回 nil
function Parser:tryBlock()
	self:skipNewlines()
	if not isPunct(self:cur(), '{') then return nil end
	local open = self:adv()
	local stmts = self:parseStatements(false)
	if not isPunct(self:cur(), '}') then fail(Err.outOfRange(open.line)) end
	self:adv()
	return stmts
end

--- 必须解析 `{ ... }`
function Parser:requireBlock()
	self:skipNewlines()
	if not isPunct(self:cur(), '{') then
		fail(Err.outOfRange(self:cur().line))
	end
	local open = self:adv()
	local stmts = self:parseStatements(false)
	if not isPunct(self:cur(), '}') then fail(Err.outOfRange(open.line)) end
	self:adv()
	return stmts
end

-- ---- 各种语句 ----------------------------------------------------------

--- hello.[名字](路径, 参数...) { ... }
--- hello.[名1][名2]...
--- hello.[!组名] { ... }
function Parser:parseHello()
	local at = self:cur()
	self:adv() -- hello
	self:adv() -- .

	local first = self:readBracketRaw()

	-- 批量导入组
	if string.len(first) > 0 and string.byte(first, 1) == 33 then -- '!'
		local gname = trim(string.sub(first, 2))
		if gname == '' then fail(Err.missingDef(at.line)) end
		local block = self:tryBlock()
		return { kind = 'group_import', name = gname, block = block, line = at.line }
	end

	local names = { first }
	while isPunct(self:cur(), '[') do
		local more, ml = self:readBracketRaw()
		if string.len(more) > 0 and string.byte(more, 1) == 33 then
			fail(Err.generic(self.file, ml,
				'批量导入 hello.[!组名] 不能和普通元素写在同一个声明里'))
		end
		names[#names + 1] = more
	end

	-- 空名字（hello.[] / hello.[a][]）直接当成缺少定义
	for i = 1, #names do
		if trim(names[i]) == '' then fail(Err.missingDef(at.line)) end
	end

	-- 参数表（可选）
	local path, args = nil, {}
	if isPunct(self:cur(), '(') then
		path, args = self:parseArgList()
	end

	local block = self:tryBlock()
	return {
		kind = 'elem_decl',
		names = names,
		path = path,
		args = args,
		block = block,
		line = at.line,
	}
end

--- `(路径, 参数...)`
function Parser:parseArgList()
	local open = self:adv() -- (
	local items = {}
	self:skipNewlines()
	if not isPunct(self:cur(), ')') then
		local guard = 0
		while true do
			guard = guard + 1
			if guard > 100000 then fail(Err.outOfRange(open.line)) end
			items[#items + 1] = self:parseExpr()
			self:skipNewlines()
			if isPunct(self:cur(), ',') then
				self:adv()
				self:skipNewlines()
			else
				break
			end
		end
	end
	self:skipNewlines()
	if not isPunct(self:cur(), ')') then fail(Err.outOfRange(open.line)) end
	self:adv()

	-- 第一个参数是资源路径
	local path = nil
	local args = {}
	if #items >= 1 then
		local p0 = items[1]
		if p0.k == 'str' then
			path = p0.v
		elseif p0.k == 'num' then
			path = numToStr(p0.v)
		else
			path = nil -- auto / nil / 其它一律视为「无资源」
		end
	end
	for i = 2, #items do args[#args + 1] = items[i] end
	return path, args
end

--- *! 组名 {a, b, c}
function Parser:parseGroupDecl()
	local at = self:cur()
	self:adv() -- *
	self:adv() -- !
	self:skipNewlines()
	local nameTok = self:cur()
	if nameTok.t ~= 'name' then fail(Err.missingDef(at.line)) end
	local name = nameTok.v
	self:adv()
	self:skipNewlines()

	local members = {}
	if isPunct(self:cur(), '{') then
		local raw = self:readBraceRaw()
		members = parseNameList(raw)
	else
		-- 宽容：也接受 *! 组名 ? a, b, c 之外什么都不写
		fail(Err.missingDef(at.line))
	end

	return { kind = 'group_decl', name = name, members = members, line = at.line }
end

--- *@ 名字 { ... }  /  *@ 名字 ? 值
--- *# 名字 { ... }  /  *# 名字 ? 值
function Parser:parseStyleDecl(scope)
	local at = self:cur()
	self:adv() -- *
	self:adv() -- @ 或 #
	self:skipNewlines()
	local nameTok = self:cur()
	if nameTok.t ~= 'name' then fail(Err.missingDef(at.line)) end
	local name = nameTok.v
	self:adv()
	self:skipNewlines()

	if isPunct(self:cur(), '{') then
		local open = self:adv()
		local body = self:parseStatements(false)
		if not isPunct(self:cur(), '}') then fail(Err.outOfRange(open.line)) end
		self:adv()
		return {
			kind = 'style_decl',
			scope = scope,
			name = name,
			body = body,
			line = at.line,
		}
	elseif isPunct(self:cur(), '?') then
		self:adv()
		local value = self:parseExpr()
		return {
			kind = 'style_decl',
			scope = scope,
			name = name,
			value = value,
			line = at.line,
		}
	end

	fail(Err.missingDef(at.line))
end

--- 块内的 `@名字` / `#名字`
function Parser:parseApplyStyle(scope)
	local at = self:adv() -- @ 或 #
	local nameTok = self:cur()
	if nameTok.t ~= 'name' then
		fail(Err.undefinedRef(str(at.v) .. str(nameTok.v)))
	end
	self:adv()
	return { kind = 'apply_style', scope = scope, name = nameTok.v, line = at.line }
end

--- 目标.属性 ? 值
function Parser:parseAssign()
	local at = self:cur()
	local parts = {}

	local tok = self:cur()
	if tok.t == 'name' or tok.t == 'number' then
		parts[#parts + 1] = tok.raw or tok.v
		self:adv()
	else
		fail(Err.missingDef(at.line))
	end

	while isPunct(self:cur(), '.') do
		self:adv()
		local nt = self:cur()
		if nt.t == 'name' or nt.t == 'number' then
			parts[#parts + 1] = nt.raw or nt.v
			self:adv()
		else
			fail(Err.missingDef(at.line))
		end
	end

	if not isPunct(self:cur(), '?') then
		-- 光秃秃一个名字，既不是声明也没有赋值 → 缺少定义
		fail(Err.missingDef(at.line))
	end
	self:adv()

	local value
	if isLineEnd(self:cur()) then
		-- `属性 ?` 后面空着：视为 nil，宽容处理
		value = { k = 'nil_', line = at.line }
	else
		value = self:parseExpr()
	end

	return { kind = 'assign', target = parts, value = value, line = at.line }
end

--- if 条件 { ... } else { ... }
function Parser:parseIf()
	local at = self:adv() -- if
	local cond = self:parseExpr()
	local thenBody = self:requireBlock()
	local elseBody = nil

	self:skipNewlines()
	if isName(self:cur(), 'else') then
		self:adv()
		self:skipNewlines()
		if isName(self:cur(), 'if') then
			elseBody = { self:parseIf() }
		else
			elseBody = self:requireBlock()
		end
	end

	return {
		kind = 'if',
		cond = cond,
		thenBody = thenBody,
		elseBody = elseBody,
		line = at.line,
	}
end

--- 判断链的分支体
--- 歧义消解：如果分支体「开头」就是另一个 why!，那它是**嵌套判断链**，
--- 而不是本链的下一个分支。内层链用 stopWhy 收尾，然后回到外层。
--- 换句话说：`why!` 紧跟着 `why!` → 嵌套；正文写在前面 → 平级分支。
function Parser:parseWhyBody()
	self:skipSeps()
	if isName(self:cur(), 'why') and isPunct(self:peek(1), '!') then
		return { self:parseWhyChain() }
	end
	return self:parseStatements(true)
end

--- 判断链：why! / or! / and! / no / stopWhy
function Parser:parseWhyChain()
	local at = self:cur()
	local branches = {}
	local guard = 0

	while true do
		guard = guard + 1
		if guard > 100000 then break end

		local t = self:cur()
		local op = nil
		if isWhyBranchStart(t, self:peek(1)) then
			op = t.v
		elseif isName(t, 'no') and isLineEnd(self:peek(1)) then
			op = 'no'
		else
			break
		end

		local branch = { op = op, line = t.line, spec = nil, body = {} }

		if op == 'no' then
			self:adv()
		else
			self:adv() -- why / or / and
			self:adv() -- !
			self:skipNewlines()

			local raw, bracketLine = self:readBracketRaw()
			branch.line = bracketLine
			branch.spec = self:parseWhySpec(raw, bracketLine)

			self:skipNewlines()
			if isPunct(self:cur(), '?') then
				self:adv()
				self:parseWhyValues(branch.spec, branch.line)
			end
		end

		branch.body = self:parseWhyBody()
		branches[#branches + 1] = branch

		if op == 'no' then
			-- `no` 之后只可能是 stopWhy 或链结束
			break
		end
	end

	-- 吃掉可选的 stopWhy
	self:skipSeps()
	if isName(self:cur(), 'stopWhy') then self:adv() end

	return { kind = 'why', branches = branches, line = at.line }
end

--- 解析 `[...]` 里的判断目标
---   `scale`                 → 属性名
---   `0,1,2,3|scale`         → 候选值集合 + 属性名
---   `whynot|scale`          → 反选
function Parser:parseWhySpec(raw, line)
	local spec = {
		prop = nil,
		values = {},
		negate = false,
		assertTrue = true,
		line = line,
	}
	local text = trim(raw)
	if text == '' then return spec end

	-- 竖线把「值集合」和「属性名」切开
	local barPos = findPlain(text, '|')
	local valuesPart, propPart = nil, text
	if barPos ~= nil then
		valuesPart = trim(string.sub(text, 1, barPos - 1))
		propPart = trim(string.sub(text, barPos + 1))
	end

	if propPart == 'whynot' and valuesPart ~= nil then
		spec.negate = true
		propPart = valuesPart
		valuesPart = nil
	end

	if valuesPart ~= nil and valuesPart ~= '' then
		local parts = splitPlain(valuesPart, ',')
		for i = 1, #parts do
			local v = trim(parts[i])
			if v == 'whynot' then
				spec.negate = true
			elseif v ~= '' then
				if isNumericString(v) then
					spec.values[#spec.values + 1] = tonumber(v) or 0
				else
					spec.values[#spec.values + 1] = v
				end
			end
		end
	end

	spec.prop = propPart
	return spec
end

--- 解析 `? 值,值... [whynot] [OK]`，就地填进 spec
function Parser:parseWhyValues(spec, line)
	spec.values = spec.values or {}
	local guard = 0
	while true do
		guard = guard + 1
		if guard > 100000 then break end
		local t = self:cur()
		if t.t == 'newline' or t.t == 'eof' then break end
		if isPunct(t, '}') then break end

		if t.t == 'number' then
			spec.values[#spec.values + 1] = t.v
			self:adv()
		elseif t.t == 'string' then
			spec.values[#spec.values + 1] = t.v
			self:adv()
		elseif t.t == 'name' then
			if t.v == 'whynot' then
				spec.negate = true
				self:adv()
			elseif t.v == 'OK' then
				spec.assertTrue = true
				self:adv()
			elseif t.v == 'NOT' or t.v == 'notOK' then
				spec.assertTrue = false
				self:adv()
			elseif t.v == 'stopWhy' then
				break
			else
				-- 裸名字：视为引用（属性或元素名）
				spec.values[#spec.values + 1] = { ref = t.v }
				self:adv()
			end
		elseif isPunct(t, ',') then
			self:adv()
		else
			break
		end
	end
end

--- dp(...)
function Parser:parseDp()
	local at = self:adv() -- dp
	self:expectPunct('(', at.line)
	local args = {}
	self:skipNewlines()
	if not isPunct(self:cur(), ')') then
		local guard = 0
		while true do
			guard = guard + 1
			if guard > 100000 then fail(Err.outOfRange(at.line)) end
			args[#args + 1] = self:parseExpr()
			self:skipNewlines()
			if isPunct(self:cur(), ',') then
				self:adv()
				self:skipNewlines()
			else
				break
			end
		end
	end
	self:skipNewlines()
	self:expectPunct(')', at.line)
	return { kind = 'dp', args = args, line = at.line }
end

--- 单条语句
function Parser:parseStatement(top)
	local t = self:cur()

	if t.t == 'eof' then return nil end

	-- *!  *@  *#
	if isPunct(t, '*') then
		local nxt = self:peek(1)
		if isPunct(nxt, '!') then return self:parseGroupDecl() end
		if isPunct(nxt, '@') then return self:parseStyleDecl('file') end
		if isPunct(nxt, '#') then return self:parseStyleDecl('global') end
		fail(Err.generic(self.file, t.line,
			'你想死啊。' .. str(t.line) .. ' 行的 * 后面只能是 ! @ # 之一'))
	end

	-- hello.[...]
	if isName(t, 'hello') and isPunct(self:peek(1), '.') and isPunct(self:peek(2), '[') then
		return self:parseHello()
	end

	if isName(t, 'if') then return self:parseIf() end

	-- 判断链
	if isWhyBranchStart(t, self:peek(1)) then return self:parseWhyChain() end
	if isName(t, 'no') and isLineEnd(self:peek(1)) then return self:parseWhyChain() end

	-- stopWhy 单飞（没有前置链）时直接吃掉
	if isName(t, 'stopWhy') then
		self:adv()
		return nil
	end

	-- dp(...)
	if isName(t, 'dp') and isPunct(self:peek(1), '(') then
		return self:parseDp()
	end

	-- 块内的 @ / # 引用
	if isPunct(t, '@') then return self:parseApplyStyle('file') end
	if isPunct(t, '#') then return self:parseApplyStyle('global') end

	-- 其余一律按「目标.属性 ? 值」处理
	return self:parseAssign()
end

-- ---- 表达式 ------------------------------------------------------------

function Parser:parseExpr() return self:parseOr() end

function Parser:parseOr()
	local l = self:parseAnd()
	while isPunct(self:cur(), '||') do
		local at = self:adv()
		local r = self:parseAnd()
		l = { k = 'bin', op = '||', l = l, r = r, line = at.line }
	end
	return l
end

function Parser:parseAnd()
	local l = self:parseCmp()
	while isPunct(self:cur(), '&&') do
		local at = self:adv()
		local r = self:parseCmp()
		l = { k = 'bin', op = '&&', l = l, r = r, line = at.line }
	end
	return l
end

local CMP_OPS = { ['=='] = true, ['!='] = true, ['>'] = true, ['<'] = true, ['>='] = true, ['<='] = true, ['~='] = true }

function Parser:parseCmp()
	local l = self:parseAdd()
	local t = self:cur()
	if t.t == 'punct' and CMP_OPS[t.v] then
		self:adv()
		local r = self:parseAdd()
		return { k = 'bin', op = t.v, l = l, r = r, line = t.line }
	end
	return l
end

function Parser:parseAdd()
	local l = self:parseMul()
	while true do
		local t = self:cur()
		if isPunct(t, '+') or isPunct(t, '-') then
			self:adv()
			local r = self:parseMul()
			l = { k = 'bin', op = t.v, l = l, r = r, line = t.line }
		else
			break
		end
	end
	return l
end

function Parser:parseMul()
	local l = self:parseUnary()
	while true do
		local t = self:cur()
		if isPunct(t, '*') or isPunct(t, '/') or isPunct(t, '%') then
			self:adv()
			local r = self:parseUnary()
			l = { k = 'bin', op = t.v, l = l, r = r, line = t.line }
		else
			break
		end
	end
	return l
end

function Parser:parseUnary()
	local t = self:cur()
	if isPunct(t, '-') then
		self:adv()
		return { k = 'un', op = '-', e = self:parseUnary(), line = t.line }
	end
	if isPunct(t, '!') then
		self:adv()
		return { k = 'un', op = '!', e = self:parseUnary(), line = t.line }
	end
	return self:parsePrimary()
end

function Parser:parsePrimary()
	local t = self:cur()

	if t.t == 'number' then
		self:adv()
		return { k = 'num', v = t.v, line = t.line }
	end
	if t.t == 'string' then
		self:adv()
		return { k = 'str', v = t.v, line = t.line }
	end

	-- 括号
	if isPunct(t, '(') then
		self:adv()
		self:skipNewlines()
		local e = self:parseExpr()
		self:skipNewlines()
		if not isPunct(self:cur(), ')') then fail(Err.outOfRange(t.line)) end
		self:adv()
		return e
	end

	-- @常量名
	if isPunct(t, '@') then
		self:adv()
		local n = self:cur()
		if n.t ~= 'name' then fail(Err.undefinedRef('@')) end
		self:adv()
		return { k = 'style_ref', scope = 'file', name = n.v, line = t.line }
	end

	-- #超全局常量 / #十六进制颜色
	if isPunct(t, '#') then
		self:adv()
		local n = self:cur()
		if n.t ~= 'name' then fail(Err.undefinedRef('#')) end
		self:adv()
		if isHexColor(n.v) then
			return { k = 'num', v = hexToNumber(n.v), color = true, line = t.line }
		end
		return { k = 'super_ref', scope = 'global', name = n.v, line = t.line }
	end

	if t.t == 'name' then
		if t.v == 'true' then self:adv(); return { k = 'bool', v = true, line = t.line } end
		if t.v == 'false' then self:adv(); return { k = 'bool', v = false, line = t.line } end
		if t.v == 'nil' then self:adv(); return { k = 'nil_', line = t.line } end
		if t.v == 'auto' then self:adv(); return { k = 'auto', line = t.line } end

		-- dp(...) 作为表达式
		if t.v == 'dp' and isPunct(self:peek(1), '(') then
			local node = self:parseDp()
			return { k = 'dp', args = node.args, line = t.line }
		end

		-- 引用路径：元素.属性.子属性
		local parts = { t.v }
		self:adv()
		while isPunct(self:cur(), '.') do
			self:adv()
			local nt = self:cur()
			if nt.t == 'name' or nt.t == 'number' then
				parts[#parts + 1] = nt.raw or nt.v
				self:adv()
			else
				break
			end
		end
		return { k = 'ref', path = parts, line = t.line }
	end

	fail(Err.generic(self.file, t.line,
		'你想死啊。' .. str(t.line) .. ' 行的表达式不完整（遇到 ' .. str(t.v) .. '）'))
end

-- ---- 入口 --------------------------------------------------------------

function Parser:parseProgram()
	local body = {}
	self:skipSeps()
	local guard = 0
	while self:cur().t ~= 'eof' do
		guard = guard + 1
		if guard > 1000000 then fail(Err.outOfRange(self:cur().line)) end
		local s = self:parseStatement(true)
		if s ~= nil then body[#body + 1] = s end
		self:skipSeps()
	end
	return { kind = 'program', body = body, file = self.file }
end

--- 对外：源码 → AST
function uic.parse(source, fileName)
	fileName = fileName or '<uic>'
	local tokens = Lexer.tokenize(source, fileName)
	local p = Parser.new(tokens, source, fileName)
	local ast = p:parseProgram()
	return ast
end

--==========================================================================
-- 4. 属性分类表
--==========================================================================
--
--  「嵌套叠加」的三种类别（对应规范第四节）：
--    ratio  比例型 → 乘算        （scale / alpha / graphicSize ...）
--    offset 偏移型 → 加算        （x / y / angle / offset / scrollFactor ...）
--    system 系统级 → 跳过        （camera / add / anim / blend / color ... 只认先到者）
--
--  未登记的属性一律按 system 处理，保证「不认识的东西不瞎叠」。

local PROP_RATIO = {
	['scale'] = true, ['scale.x'] = true, ['scale.y'] = true,
	['alpha'] = true,
	['graphicSize'] = true, ['graphicSize.x'] = true, ['graphicSize.y'] = true,
}

local PROP_OFFSET = {
	['x'] = true, ['y'] = true,
	['angle'] = true, ['degrees'] = true,
	['offset.x'] = true, ['offset.y'] = true,
	['scrollFactor.x'] = true, ['scrollFactor.y'] = true,
	['velocity.x'] = true, ['velocity.y'] = true,
	['origin.x'] = true, ['origin.y'] = true,
}

--- 取得属性类别
local function propKind(key)
	if PROP_RATIO[key] then return 'ratio' end
	if PROP_OFFSET[key] then return 'offset' end
	return 'system'
end

--- 按类别合并两个值
local function mergeValue(key, old, new)
	local kind = propKind(key)
	if kind == 'ratio' then
		return (tonumber(old) or 0) * (tonumber(new) or 0)
	elseif kind == 'offset' then
		return (tonumber(old) or 0) + (tonumber(new) or 0)
	end
	return old -- 系统级：跳过，保留先到者
end

--==========================================================================
-- 5. 引擎桥接层（UIC 属性 → FNF / Psych 原生 API）
--==========================================================================

local Bridge = {}

--- 一个 UIC 属性名展开成多个引擎属性路径
local PROP_EXPAND = {
	['scale'] = { 'scale.x', 'scale.y' },
	['scroll'] = { 'scrollFactor.x', 'scrollFactor.y' },
	['scrollFactor'] = { 'scrollFactor.x', 'scrollFactor.y' },
	['offset'] = { 'offset.x', 'offset.y' },
	['velocity'] = { 'velocity.x', 'velocity.y' },
}

--- 需要调用专用函数的属性
local PROP_SPECIAL = {}

PROP_SPECIAL['camera'] = function(tag, v)
	callEngine('setObjectCamera', tag, str(v))
end

PROP_SPECIAL['add'] = function(tag, v)
	if v == nil or v == false then
		callEngine('removeLuaSprite', tag, false)
	else
		callEngine('addLuaSprite', tag, true)
	end
end

PROP_SPECIAL['anim'] = function(tag, v)
	callEngine('playAnim', tag, str(v), true)
end
PROP_SPECIAL['animation'] = PROP_SPECIAL['anim']

PROP_SPECIAL['blend'] = function(tag, v)
	callEngine('setBlendMode', tag, str(v))
end

PROP_SPECIAL['shader'] = function(tag, v)
	callEngine('setSpriteShader', tag, str(v))
end

--- 数值化：颜色可以写成 0xFFFF00 / #FFFF00 / "0xFFFF00"
local function toEngineValue(value)
	if type(value) == 'string' then
		local s = trim(value)
		if startsWith(s, '0x') or startsWith(s, '0X') then
			local n = hexToNumber(string.sub(s, 3))
			if n ~= nil then return n end
		end
		if string.len(s) > 0 and string.byte(s, 1) == 35 then -- '#'
			local n = hexToNumber(string.sub(s, 2))
			if n ~= nil then return n end
		end
		if isNumericString(s) then return tonumber(s) end
		return value
	end
	return value
end

--- 写一个具体属性路径
local function writeRaw(tag, path, value)
	callEngine('setProperty', tag .. '.' .. path, toEngineValue(value))
end

--- 对外：写属性（自动处理展开与专用函数）
function Bridge.setProp(tag, key, value)
	local special = PROP_SPECIAL[key]
	if special ~= nil then
		special(tag, value)
		return
	end
	local ex = PROP_EXPAND[key]
	if ex ~= nil then
		for i = 1, #ex do writeRaw(tag, ex[i], value) end
		return
	end
	writeRaw(tag, key, value)
end

--- 读属性
function Bridge.getProp(tag, key)
	local f = engineFn('getProperty')
	if f == nil then return nil end
	local ex = PROP_EXPAND[key]
	local realKey = (ex ~= nil) and ex[1] or key
	-- 引擎对象不存在时 getProperty 会抛错，这里吞掉
	local ok, v = pcall(f, tag .. '.' .. realKey)
	if not ok then return nil end
	return v
end

--- 判断资源路径是不是「图集 / 动画」
local function looksAnimated(path)
	if path == nil then return false end
	local lower = ''
	local n = string.len(path)
	for i = 1, n do
		local b = string.byte(path, i)
		if b >= 65 and b <= 90 then b = b + 32 end
		lower = lower .. string.char(b)
	end
	return endsWith(lower, '.xml') or endsWith(lower, '.txt') or endsWith(lower, '.json')
end

--- 创建元素（真正落到引擎里）
--- @return boolean 是否成功
function Bridge.createElement(name, path, x, y)
	local tag = name
	local hasPath = (path ~= nil and path ~= '')

	if hasPath and looksAnimated(path) then
		callEngine('makeAnimatedLuaSprite', tag, path, x, y, 'sparrow')
	else
		callEngine('makeLuaSprite', tag, hasPath and path or nil, x, y)
	end

	if not hasPath then
		-- 「auto：按资源尺寸自动填充，无资源默认 50px」
		callEngine('setProperty', tag .. '.width', 50)
		callEngine('setProperty', tag .. '.height', 50)
	end

	callEngine('addLuaSprite', tag, false)
	return true
end

--- 销毁元素
function Bridge.destroyElement(name)
	callEngine('removeLuaSprite', name, true)
end

--- 元素是否存在
function Bridge.exists(name)
	if hasEngine('luaSpriteExists') then
		local ok, v = pcall(callEngine, 'luaSpriteExists', name)
		if ok then return v == true end
	end
	return true -- 引擎没有这个 API 时不做额外判断
end

--==========================================================================
-- 6. dp —— 跨语言通信
--==========================================================================

uic.dpBuffer = {}
uic.dpMax = 512
uic.autoPrint = true
uic.onDp = nil

local function dpPush(text)
	text = str(text)
	local buf = uic.dpBuffer
	buf[#buf + 1] = text
	if #buf > uic.dpMax then table.remove(buf, 1) end

	if uic.onDp then
		local ok = pcall(uic.onDp, text)
		if not ok then uic.onDp = nil end
	end
	if uic.autoPrint then
		local f = engineFn('debugPrint')
		if f ~= nil then pcall(f, text) end
	end
end

--- Lua 侧：uic.dp()          → 取出并清空 UIC 侧 dp 的输出
---          uic.dp("文本")    → 主动输出一条
function uic.dp(...)
	local n = select('#', ...)
	if n == 0 then
		local buf = uic.dpBuffer
		uic.dpBuffer = {}
		return buf
	end
	local parts = {}
	for i = 1, n do parts[#parts + 1] = str((select(i, ...))) end
	dpPush(table.concat(parts, ' '))
	return nil
end

--- 清空 dp 缓冲
function uic.clearDp()
	uic.dpBuffer = {}
end

--==========================================================================
-- 7. 运行时（AST 求值 → 引擎调用）
--==========================================================================

local AUTO = {} -- `auto` 的哨兵值

--- 前向声明：下面几个是纯函数，先声明成局部变量。
--- 否则 Runtime 的方法会在定义之前引用到同名的**全局**变量（nil），
--- 这是 Lua 里最经典的作用域坑。
local truthy
local applyBinOp
local compareLoose

local Runtime = {}
Runtime.__index = Runtime

function Runtime.new(fileName)
	local self = setmetatable({}, Runtime)
	self.file = fileName or '<uic>'
	self.styles = {} -- *@ 文件内样式 / 常量
	self.groups = {} -- *! 文件内元素组
	self.targets = {} -- 当前正在配置的元素名列表
	return self
end

--- 元素在引擎里的 tag（默认与 UIC 名字相同）
local function tagOf(name)
	return uic.tagPrefix .. name
end

--- 取元素记录
local function elemOf(name)
	return uic.elements[name]
end

-- ---- 值求值 ------------------------------------------------------------

function Runtime:resolveConst(scope, name, line)
	local def
	if scope == 'global' then
		def = uic.globals[name]
	else
		def = self.styles[name]
	end
	if def == nil then
		fail(Err.undefinedRef((scope == 'global' and '#' or '@') .. name))
	end
	if def.kind ~= 'const' then
		fail(Err.generic(self.file, line or def.line,
			(scope == 'global' and '#' or '@') .. name .. ' 是一个样式组，不能当值用'))
	end
	return def.value
end

--- 读取 `元素.属性` 引用
--- 单段名字的解析顺序：
---   1) 已声明的 UIC 元素
---   2) 引擎全局（screenWidth / curBeat / score / songName 之类）
---   3) 当前作用域只锁了一个元素时，当作它的属性（why![scale] 就靠这条）
---   4) 都不是 → 未定义引用
--- 三段及以上的路径一律按「元素.属性路径」处理。
function Runtime:readRef(path, line)
	if #path == 1 then
		local name = path[1]

		local e = elemOf(name)
		if e ~= nil then return e end

		local g = rawget(_G, name)
		if g ~= nil and type(g) ~= 'function' then return g end

		if #self.targets == 1 then
			local t = elemOf(self.targets[1])
			if t ~= nil then return Bridge.getProp(tagOf(t.name), name) end
		end

		fail(Err.undefinedRef(name))
	end

	local name = path[1]
	local key = table.concat(path, '.', 2)

	-- 组名出现在表达式里：语义不明确（取哪个成员？），给出明确提示而不是含糊的「未定义」
	if self.groups[name] ~= nil then
		fail(Err.generic(self.file, line,
			'你想死啊。' .. str(line) .. ' 行：' .. name ..
			' 是一个元素组，组广播只能用在赋值左边（' .. name .. '.' .. key .. ' ? 值）'))
	end

	local e = elemOf(name)
	if e == nil then fail(Err.undefinedRef(name)) end
	return Bridge.getProp(tagOf(e.name), key)
end

function Runtime:value(expr, line)
	if expr == nil then return nil end
	local k = expr.k

	if k == 'num' then return expr.v end
	if k == 'str' then return expr.v end
	if k == 'bool' then return expr.v end
	if k == 'nil_' then return nil end
	if k == 'auto' then return AUTO end
	if k == 'style_ref' then return self:resolveConst('file', expr.name, expr.line) end
	if k == 'super_ref' then return self:resolveConst('global', expr.name, expr.line) end
	if k == 'ref' then return self:readRef(expr.path, expr.line) end
	if k == 'dp' then return self:evalDp(expr) end

	if k == 'un' then
		local v = self:value(expr.e, expr.line)
		if expr.op == '-' then return -(tonumber(v) or 0) end
		if expr.op == '!' then return not truthy(v) end
		return nil
	end

	if k == 'bin' then
		local op = expr.op
		-- 短路
		if op == '&&' then
			local l = self:value(expr.l, expr.line)
			if not truthy(l) then return false end
			return truthy(self:value(expr.r, expr.line))
		end
		if op == '||' then
			local l = self:value(expr.l, expr.line)
			if truthy(l) then return true end
			return truthy(self:value(expr.r, expr.line))
		end

		local l = self:value(expr.l, expr.line)
		local r = self:value(expr.r, expr.line)
		return applyBinOp(op, l, r)
	end

	fail(Err.generic(self.file, line, '你想死啊。' .. str(line) .. ' 行有个无法求值的表达式'))
end

--- 二元运算（数值优先，非数值回退到字符串比较 —— 规范允许比较非数值）
function applyBinOp(op, l, r)
	if op == '==' or op == '~=' then
		local eq
		local ln, rn = tonumber(l), tonumber(r)
		if ln ~= nil and rn ~= nil then
			eq = (ln == rn)
		elseif type(l) == 'boolean' or type(r) == 'boolean' then
			eq = (l == r)
		else
			eq = (str(l) == str(r))
		end
		if op == '~=' then return not eq end
		return eq
	end
	if op == '!=' then
		return not applyBinOp('==', l, r)
	end

	local ln, rn = tonumber(l), tonumber(r)
	if ln == nil or rn == nil then
		-- 非数值：按字符串比较（字典序）
		local ls, rs = str(l), str(r)
		if op == '>' then return ls > rs end
		if op == '<' then return ls < rs end
		if op == '>=' then return ls >= rs end
		if op == '<=' then return ls <= rs end
		return nil
	end

	if op == '+' then return ln + rn end
	if op == '-' then return ln - rn end
	if op == '*' then return ln * rn end
	if op == '/' then
		if rn == 0 then return 0 end
		return ln / rn
	end
	if op == '%' then
		if rn == 0 then return 0 end
		return ln % rn
	end
	if op == '>' then return ln > rn end
	if op == '<' then return ln < rn end
	if op == '>=' then return ln >= rn end
	if op == '<=' then return ln <= rn end
	return nil
end

function truthy(v)
	if v == nil or v == false then return false end
	if v == AUTO then return true end
	if type(v) == 'number' then return v ~= 0 end
	if type(v) == 'string' then return v ~= '' end
	return true
end

uic.truthy = truthy

-- ---- 样式解析 ----------------------------------------------------------

--- 把一个样式 / 超全局展开成有序属性列表
--- 样式内部按「嵌套叠加」规则合并：比例乘算、偏移加算、系统级跳过
function Runtime:resolveStyle(scope, name, seen)
	local key = (scope == 'global' and '#' or '@') .. name
	if seen[key] then
		fail(Err.generic(self.file, nil, '样式 ' .. key .. ' 出现了循环引用（嵌套太深）'))
	end
	seen[key] = true

	local def = (scope == 'global') and uic.globals[name] or self.styles[name]
	if def == nil then fail(Err.undefinedRef(key)) end
	if def.kind ~= 'group' then
		fail(Err.generic(self.file, def.line, key .. ' 是一个常量，不能当样式块用'))
	end

	local acc = {}
	local order = {}

	local function put(propKey, value)
		if acc[propKey] == nil then
			acc[propKey] = value
			order[#order + 1] = propKey
		else
			acc[propKey] = mergeValue(propKey, acc[propKey], value)
		end
	end

	for i = 1, #def.body do
		local st = def.body[i]
		if st.kind == 'apply_style' then
			local sub = self:resolveStyle(st.scope, st.name, seen)
			for j = 1, #sub do put(sub[j].key, sub[j].value) end
		elseif st.kind == 'assign' then
			-- 样式体内只允许 `属性 ? 值`
			if #st.target ~= 1 then
				fail(Err.generic(self.file, st.line,
					'你想死啊。' .. str(st.line) .. ' 行：样式组内只能写「属性 ? 值」'))
			end
			local pk = st.target[1]
			local v = self:value(st.value, st.line)
			put(pk, v)
		else
			-- 「样式组内不写逻辑」
			fail(Err.generic(self.file, st.line,
				'你想死啊。' .. str(st.line) .. ' 行：样式组内不写逻辑'))
		end
	end

	seen[key] = nil

	local out = {}
	for i = 1, #order do
		out[#out + 1] = { key = order[i], value = acc[order[i]] }
	end
	return out
end

-- ---- 属性写入元素 ------------------------------------------------------

--- 把有序属性列表写进一个元素
--- 同一元素上：标记叠标记 → 覆盖；直接赋值叠标记 → 按类别嵌套叠加
---
--- 注意：累积状态必须挂在元素记录上（e.props / e.propOrigin），
--- 因为每条 `属性 ? 值` 语句都是单独一次 applyToProps，
--- 只有跨语句保存，`scale ? 2` 之后再 `@样式` 才能叠加成 2*0.5。
function Runtime:applyToProps(name, propList)
	local e = elemOf(name)
	if e == nil then fail(Err.missingDef(propList[1] and propList[1].line or '?')) end

	if e.props == nil then e.props = {} end
	if e.propOrigin == nil then e.propOrigin = {} end

	local vals = e.props
	local origins = e.propOrigin
	local seen = {}
	local order = {}

	for i = 1, #propList do
		local p = propList[i]
		local curOrigin = origins[p.key]

		if curOrigin == nil then
			vals[p.key] = p.value
			origins[p.key] = p.origin
		elseif p.origin == 'mark' and curOrigin == 'assign' then
			-- 嵌套叠加：比例型乘算、偏移型加算、系统级跳过
			vals[p.key] = mergeValue(p.key, vals[p.key], p.value)
			origins[p.key] = 'assign'
		else
			-- 后来者居上
			vals[p.key] = p.value
			origins[p.key] = p.origin
		end

		if not seen[p.key] then
			seen[p.key] = true
			order[#order + 1] = p.key
		end
	end

	local tag = tagOf(name)
	for i = 1, #order do
		local key = order[i]
		local v = vals[key]
		if v == AUTO then v = nil end
		if v ~= nil then
			Bridge.setProp(tag, key, v)
		end
	end
end

--- 把一条属性写入若干元素
function Runtime:writeProp(targetNames, key, value, origin, line)
	local list = { { key = key, value = value, origin = origin, line = line } }
	for i = 1, #targetNames do
		self:applyToProps(targetNames[i], list)
	end
end

-- ---- 元素创建 ----------------------------------------------------------

--- 求一个参数表达式的数值（auto → 0）
function Runtime:evalCoord(expr)
	if expr == nil then return 0 end
	if expr.k == 'auto' then return 0 end
	local v = self:value(expr)
	if v == nil or v == AUTO then return 0 end
	local n = tonumber(v)
	if n == nil then return 0 end
	return n
end

function Runtime:createElement(name, path, args, line)
	local e = elemOf(name)
	if e ~= nil and e.exists then
		-- 已存在：重新声明视为「重新绑定」，不重复创建
		return e
	end

	local x = self:evalCoord(args and args[1])
	local y = self:evalCoord(args and args[2])

	local tag = tagOf(name)
	Bridge.createElement(tag, path, x, y)

	local rec = {
		name = name,
		tag = tag,
		path = path,
		line = line,
		exists = true,
		props = {},
	}
	uic.elements[name] = rec
	uic.elementOrder[#uic.elementOrder + 1] = name
	return rec
end

-- ---- 语句执行 ----------------------------------------------------------

function Runtime:execStatements(stmts)
	if stmts == nil then return end
	for i = 1, #stmts do
		self:execStmt(stmts[i])
	end
end

--- 在收窄的作用域里执行一段语句
function Runtime:withTargets(list, stmts)
	local saved = self.targets
	self.targets = list
	self:execStatements(stmts)
	self.targets = saved
end

function Runtime:execStmt(node)
	local k = node.kind

	-- *! 组声明
	if k == 'group_decl' then
		self.groups[node.name] = { members = node.members, line = node.line }
		return
	end

	-- *@ / *#
	if k == 'style_decl' then
		local def
		if node.value ~= nil then
			def = { kind = 'const', value = self:value(node.value, node.line), line = node.line }
		else
			def = { kind = 'group', body = node.body, line = node.line }
		end
		if node.scope == 'global' then
			uic.globals[node.name] = def
		else
			self.styles[node.name] = def
		end
		return
	end

	-- hello.[名字](...) { }
	if k == 'elem_decl' then
		for i = 1, #node.names do
			self:createElement(node.names[i], node.path, node.args, node.line)
		end
		if node.block ~= nil then
			self:withTargets(node.names, node.block)
		end
		return
	end

	-- hello.[!组名] { }
	if k == 'group_import' then
		local g = self.groups[node.name]
		if g == nil then
			fail(Err.undefinedRef('!' .. node.name))
		end
		local members = g.members
		if #members == 0 then
			fail(Err.generic(self.file, node.line,
				'hello~你的[' .. str(node.line) .. ']中缺少了定义'))
		end
		-- 没声明过的成员按默认模板自动创建（批量创建）
		for i = 1, #members do
			local m = members[i]
			if elemOf(m) == nil then
				self:createElement(m, nil, nil, node.line)
			end
		end
		if node.block ~= nil then
			self:withTargets(members, node.block)
		end
		return
	end

	-- @样式 / #超全局（块内引用）
	if k == 'apply_style' then
		if #self.targets == 0 then
			fail(Err.generic(self.file, node.line,
				( node.scope == 'global' and '#' or '@' ) .. node.name ..
				' 只能出现在元素或组的属性块里'))
		end
		local list = self:resolveStyle(node.scope, node.name, {})
		local propList = {}
		for i = 1, #list do
			propList[#propList + 1] = {
				key = list[i].key,
				value = list[i].value,
				origin = 'mark',
				line = node.line,
			}
		end
		for i = 1, #self.targets do
			self:applyToProps(self.targets[i], propList)
		end
		return
	end

	-- 属性赋值
	if k == 'assign' then
		self:execAssign(node)
		return
	end

	-- if
	if k == 'if' then
		local cond = truthy(self:value(node.cond, node.line))
		if cond then
			self:execStatements(node.thenBody)
		elseif node.elseBody ~= nil then
			self:execStatements(node.elseBody)
		end
		return
	end

	-- 判断链
	if k == 'why' then
		self:execWhy(node)
		return
	end

	-- dp(...)
	if k == 'dp' then
		dpPush(self:formatDp(node.args, node.line))
		return
	end

	fail(Err.generic(self.file, node.line or 0, '你想死啊。' .. str(node.line or 0) .. ' 行有未知语句'))
end

--- 属性赋值
function Runtime:execAssign(node)
	local target = node.target

	-- 单段目标：当前作用域里元素的属性
	if #target == 1 then
		local key = target[1]
		if #self.targets == 0 then
			fail(Err.missingDef(node.line))
		end
		local v = self:value(node.value, node.line)
		self:writeProp(self.targets, key, v, 'assign', node.line)
		return
	end

	local head = target[1]
	local key = table.concat(target, '.', 2)

	-- 组广播
	local g = self.groups[head]
	if g ~= nil then
		if #g.members == 0 then
			-- 空组广播一律视为缺少定义，避免静默什么都不做
			fail(Err.missingDef(node.line))
		end
		local v = self:value(node.value, node.line)
		self:writeProp(g.members, key, v, 'assign', node.line)
		return
	end

	-- 单元素
	if elemOf(head) ~= nil then
		local v = self:value(node.value, node.line)
		self:writeProp({ head }, key, v, 'assign', node.line)
		return
	end

	-- 既不是组也不是已声明元素
	fail(Err.missingDef(node.line))
end

--- 判断链：why! / or! / and! / no
---
--- 语义（每个元素最多命中一个分支，读起来就是 if / else if / else）：
---   * 对作用域内的每个元素逐个求值；
---   * 命中的元素执行该分支体，作用域收窄为命中者；
---   * 已经命中过的元素**不再**参与后面的分支，避免重复执行；
---   * `no` 兜住「一个分支都没命中」的那些元素；全命中时 no 不执行。
function Runtime:execWhy(node)
	local frontier = self.targets
	local matched = {}

	for i = 1, #node.branches do
		local br = node.branches[i]

		if br.op == 'no' then
			local rest = {}
			for j = 1, #frontier do
				if not matched[frontier[j]] then rest[#rest + 1] = frontier[j] end
			end
			if #rest > 0 then
				self:withTargets(rest, br.body)
			end
			return
		end

		local hits = {}
		for j = 1, #frontier do
			local name = frontier[j]
			if not matched[name] and self:whyMatch(name, br.spec) then
				hits[#hits + 1] = name
				matched[name] = true
			end
		end

		if #hits > 0 then
			self:withTargets(hits, br.body)
		end
	end
end

--- 单个元素是否命中判断条件
function Runtime:whyMatch(name, spec)
	local e = elemOf(name)
	if e == nil then return false end

	local prop = spec.prop
	local cur
	if prop == nil or prop == '' then
		cur = nil
	else
		cur = Bridge.getProp(tagOf(name), prop)
	end

	local result
	if spec.values == nil or #spec.values == 0 then
		-- 只写属性名 → 真值判定
		result = truthy(cur)
	else
		result = false
		for i = 1, #spec.values do
			local v = spec.values[i]
			if type(v) == 'table' and v.ref ~= nil then
				-- 裸名字：再取一次属性
				v = Bridge.getProp(tagOf(name), v.ref)
			end
			if compareLoose(cur, v) then
				result = true
				break
			end
		end
	end

	if spec.negate then result = not result end
	if spec.assertTrue == false then result = not result end
	return result
end

--- 宽松比较：数值优先，其次字符串
function compareLoose(a, b)
	local an, bn = tonumber(a), tonumber(b)
	if an ~= nil and bn ~= nil then return an == bn end
	if a == nil and b == nil then return true end
	if a == nil or b == nil then return false end
	return str(a) == str(b)
end

-- ---- dp 格式化 ---------------------------------------------------------

function Runtime:describeElement(name)
	local e = elemOf(name)
	if e == nil then
		-- 组名也能 dp，直接把成员列出来，调试时很有用
		local g = self.groups[name]
		if g ~= nil then
			return '元素组 ' .. name .. ' = {' .. table.concat(g.members, ', ') .. '}'
		end
		return '<未定义元素 ' .. name .. '>'
	end
	local parts = { '元素 ' .. name }
	if e.path ~= nil then parts[#parts + 1] = '资源=' .. e.path end
	parts[#parts + 1] = 'x=' .. numToStr(Bridge.getProp(tagOf(name), 'x'))
	parts[#parts + 1] = 'y=' .. numToStr(Bridge.getProp(tagOf(name), 'y'))
	return table.concat(parts, ' ')
end

function Runtime:formatDp(args, line)
	if args == nil or #args == 0 then
		return 'D.C.LushiFu--U.I.C.'
	end
	local out = {}
	for i = 1, #args do
		local a = args[i]
		if a.k == 'ref' and #a.path == 1 then
			-- dp(元素)
			out[#out + 1] = self:describeElement(a.path[1])
		elseif a.k == 'ref' and #a.path >= 2 then
			-- dp(元素.属性)；走 readRef 以便组名等情况给出明确错误
			local name = a.path[1]
			local key = table.concat(a.path, '.', 2)
			local v = self:readRef(a.path, a.line or line)
			out[#out + 1] = name .. '.' .. key .. ' = ' .. str(v)
		else
			local v = self:value(a, a.line or line)
			if type(v) == 'table' and v ~= AUTO then
				out[#out + 1] = self:describeElement(v.name or '?')
			elseif v == AUTO then
				out[#out + 1] = 'auto'
			else
				out[#out + 1] = str(v)
			end
		end
	end
	return table.concat(out, ' ')
end

function Runtime:evalDp(expr)
	return self:formatDp(expr.args, expr.line)
end

--- 执行整棵 AST
function Runtime:run(ast)
	self:execStatements(ast.body)
end

--==========================================================================
-- 8. 文件系统 / 路径解析
--==========================================================================

uic.mod = nil -- 当前 mod 目录名，可手动指定
uic.tagPrefix = '' -- 引擎 sprite tag 前缀，默认与元素同名

--- 默认 vfs：走引擎沙箱里保留的 io.open
--- （strict 沙箱会移除 io，此时务必自行替换 uic.vfs）
local function defaultIo()
	local ioLib = rawget(_G, 'io')
	if type(ioLib) ~= 'table' then return nil, nil end
	local openFn = ioLib.open
	if type(openFn) ~= 'function' then return nil, nil end
	return ioLib, openFn
end

uic.vfs = {
	exists = function(path)
		local _, openFn = defaultIo()
		if openFn == nil then return false end
		local ok, f = pcall(openFn, path, 'r')
		if not ok or f == nil then return false end
		pcall(function() f:close() end)
		return true
	end,
	read = function(path)
		local _, openFn = defaultIo()
		if openFn == nil then return nil end
		local ok, f = pcall(openFn, path, 'r')
		if not ok or f == nil then return nil end
		local ok2, content = pcall(function() return f:read('*a') end)
		pcall(function() f:close() end)
		if not ok2 then return nil end
		return content
	end,
}

--- 尝试从库自身位置推断当前 mod（库放在 mods/<mod>/scripts/ 下时最准）
local function detectSelfMod()
	-- 注意：这里一律用 type() 判断，不用 `x == nil`。
	-- 某些 Lua 实现里「未定义的全局」与 nil 的比较并不可靠，直接取字段会炸。
	local dbg = rawget(_G, 'debug')
	if type(dbg) ~= 'table' then return nil end
	local getinfo = dbg.getinfo
	if type(getinfo) ~= 'function' then return nil end

	local ok, info = pcall(getinfo, 1, 'S')
	if not ok or type(info) ~= 'table' then return nil end
	local src = info.source
	if type(src) ~= 'string' then return nil end
	if string.sub(src, 1, 1) == '@' then src = string.sub(src, 2) end
	src = replacePlain(src, '\\', '/')

	-- 形如 .../mods/<mod>/scripts/uic.lua
	local marker = '/mods/'
	local a = findPlain(src, marker, 1)
	if a == nil then
		if startsWith(src, 'mods/') then a = 0 else return nil end
	end
	local rest = string.sub(src, a + string.len(marker))
	local parts = splitPlain(rest, '/')
	if #parts >= 2 then return parts[1] end
	return nil
end

--- 搜索根：相对路径一律优先走 mods（规范第八节）
local function buildRoots()
	local roots = {}
	local mod = uic.mod
	if mod == nil then
		-- 引擎可能暴露的全局
		if type(rawget(_G, 'modFolder')) == 'string' then mod = rawget(_G, 'modFolder') end
		if mod == nil and type(rawget(_G, 'currentModDirectory')) == 'string' then
			mod = rawget(_G, 'currentModDirectory')
		end
	end
	if mod == nil then mod = detectSelfMod() end
	if mod ~= nil and mod ~= '' then
		uic.detectedMod = mod
		roots[#roots + 1] = 'mods/' .. mod .. '/'
	end
	roots[#roots + 1] = 'mods/'
	roots[#roots + 1] = ''
	return roots
end

uic.roots = nil
function uic.refreshRoots()
	uic.roots = buildRoots()
	return uic.roots
end
uic.refreshRoots()

--- 规范化路径：反斜杠转正斜杠，折叠盘符后的多余斜杠
function uic.normalizePath(p)
	p = trim(p)
	p = replacePlain(p, '\\', '/')
	if string.len(p) >= 2 and string.sub(p, 2, 2) == ':' then
		local rest = string.sub(p, 3)
		while string.len(rest) > 0 and string.byte(rest, 1) == 47 do
			rest = string.sub(rest, 2)
		end
		p = string.sub(p, 1, 2) .. '/' .. rest
	end
	return p
end

--- 是否绝对路径（带盘符 或 以 / 开头）
local function isAbsolutePath(p)
	if string.len(p) >= 2 and string.sub(p, 2, 2) == ':' then return true end
	if string.len(p) >= 1 and string.byte(p, 1) == 47 then return true end
	return false
end

--- 解析成真实可读的路径；找不到返回 nil
function uic.resolve(path)
	local p = uic.normalizePath(path)
	if p == '' then return nil end
	if isAbsolutePath(p) then
		if uic.vfs.exists(p) then return p end
		return nil
	end
	local roots = uic.roots or uic.refreshRoots()
	for i = 1, #roots do
		local cand = roots[i] .. p
		if uic.vfs.exists(cand) then return cand end
	end
	-- 再兜底试一次 .uic 后缀
	if not endsWith(p, '.uic') then
		return uic.resolve(p .. '.uic')
	end
	return nil
end

--==========================================================================
-- 9. 对外状态
--==========================================================================

uic.elements = {} -- 名字 → 元素记录
uic.elementOrder = {} -- 声明顺序
uic.globals = {} -- *# 跨文件超全局（所有文件共享）
uic.astCache = {} -- 路径 → AST
uic.cacheEnabled = true

--- 当前上下文（供 Lua 侧查询）
function uic.into(name)
	local e = uic.elements[name]
	if e == nil then return nil end
	return uic.proxy(name)
end

--- 销毁元素
function uic.getOut(name)
	local e = uic.elements[name]
	if e == nil then return false end
	Bridge.destroyElement(tagOf(name))
	uic.elements[name] = nil
	for i = #uic.elementOrder, 1, -1 do
		if uic.elementOrder[i] == name then table.remove(uic.elementOrder, i) end
	end
	return true
end

--- 销毁全部元素
function uic.getOutAll()
	for i = #uic.elementOrder, 1, -1 do
		local name = uic.elementOrder[i]
		Bridge.destroyElement(tagOf(name))
	end
	uic.elements = {}
	uic.elementOrder = {}
end

--- 清空一切（含 *# 超全局）
function uic.reset(destroySprites)
	if destroySprites ~= false then uic.getOutAll() end
	uic.elements = {}
	uic.elementOrder = {}
	uic.globals = {}
	uic.astCache = {}
	uic.clearDp()
end

--==========================================================================
-- 10. 元素句柄（uic.into 的返回值）
--==========================================================================

local proxyMt = {}
local proxyMethods = {}

proxyMt.__index = function(t, k)
	local name = rawget(t, '__name')
	if k == 'name' then return name end
	if k == 'tag' then return tagOf(name) end
	if k == 'exists' then return uic.elements[name] ~= nil end
	-- 方法优先，避免把 set/get/destroy 当成属性去问引擎要
	local m = proxyMethods[k]
	if m ~= nil then return m end
	if type(k) == 'string' then
		return Bridge.getProp(tagOf(name), k)
	end
	return nil
end

proxyMt.__newindex = function(t, k, v)
	local name = rawget(t, '__name')
	if type(k) == 'string' then
		Bridge.setProp(tagOf(name), k, v)
		local e = uic.elements[name]
		if e ~= nil then
			if e.props == nil then e.props = {} end
			if e.propOrigin == nil then e.propOrigin = {} end
			e.props[k] = v
			e.propOrigin[k] = 'assign'
		end
	end
end

proxyMt.__tostring = function(t)
	return 'UICElement(' .. str(rawget(t, '__name')) .. ')'
end

proxyMt.__call = function(t, key, value)
	if value ~= nil then
		t[key] = value
		return t
	end
	return t[key]
end

proxyMethods = {
	set = function(self, key, value)
		self[key] = value
		return self
	end,
	get = function(self, key)
		return Bridge.getProp(self.tag, key)
	end,
	destroy = function(self)
		return uic.getOut(self.name)
	end,
}

function uic.proxy(name)
	local t = setmetatable({}, proxyMt)
	rawset(t, '__name', name)
	return t
end

--==========================================================================
-- 11. 加载并执行 .uic 文件
--==========================================================================

uic.onError = nil -- function(errText, filePath) —— 自定义错误处理
uic.lastError = nil

--- 读取源码（带缓存）
function uic.readSource(path, resolved)
	if uic.cacheEnabled and resolved ~= nil then
		local cached = uic.sourceCache and uic.sourceCache[resolved]
		if cached ~= nil then return cached end
	end
	local content = uic.vfs.read(resolved or path)
	if content ~= nil and uic.cacheEnabled and resolved ~= nil then
		uic.sourceCache = uic.sourceCache or {}
		uic.sourceCache[resolved] = content
	end
	return content
end

uic.sourceCache = {}

--- 从字符串加载
--- @param source string UIC 源码
--- @param fileName string 显示用的文件名
--- @param opts table|nil { raise = true 时抛错，否则只记日志 }
function uic.loadString(source, fileName, opts)
	opts = opts or {}
	fileName = fileName or '<string>'

	local ok, result = pcall(function()
		local ast = uic.parse(source, fileName)
		local rt = Runtime.new(fileName)
		rt:run(ast)
		return rt
	end)

	if ok then return result end

	uic.lastError = result
	if uic.onError ~= nil then
		pcall(uic.onError, result, fileName)
	end
	if opts.raise == true then
		error(result, 0)
	end
	local dp = engineFn('debugPrint')
	if dp ~= nil then pcall(dp, str(result)) end
	return nil
end

--- 加载并执行一个 .uic 文件
--- @param path string 路径。带盘符走盘根；相对路径走 mods
function uic.load(path, opts)
	opts = opts or {}
	local resolved = uic.resolve(path)

	if resolved == nil then
		local msg = Err.generic(path, 0, 'hello~你的[' .. str(path) .. ']中缺少了定义')
		uic.lastError = msg
		if uic.onError ~= nil then pcall(uic.onError, msg, path) end
		if opts.raise == true then error(msg, 0) end
		local dp = engineFn('debugPrint')
		if dp ~= nil then pcall(dp, msg) end
		return nil
	end

	local source = uic.readSource(path, resolved)
	if source == nil then
		local msg = Err.generic(resolved, 0, '你想死啊。' .. str(resolved) .. ' 打不开')
		uic.lastError = msg
		if uic.onError ~= nil then pcall(uic.onError, msg, resolved) end
		if opts.raise == true then error(msg, 0) end
		return nil
	end

	return uic.loadString(source, resolved, opts)
end

--- 解析但不执行（调试用）
function uic.parseFile(path)
	local resolved = uic.resolve(path)
	if resolved == nil then return nil end
	local source = uic.readSource(path, resolved)
	if source == nil then return nil end
	return uic.parse(source, resolved)
end

--- 语法糖：uic.file['路径'] / uic.file('路径')
uic.file = setmetatable({}, {
	__index = function(_, path)
		return uic.load(path)
	end,
	__call = function(_, path, opts)
		return uic.load(path, opts)
	end,
})

--- 语法糖：uic.fileRaw['路径'] 只解析不执行
uic.fileRaw = setmetatable({}, {
	__index = function(_, path)
		return uic.parseFile(path)
	end,
	__call = function(_, path)
		return uic.parseFile(path)
	end,
})

--- 引擎桥接表。测试或特殊宿主可以替换其中任意函数。
uic.bridge = Bridge

--- 词法 / 语法分析器（供工具链复用）
uic.lexer = Lexer
uic.parser = Parser
uic.runtime = Runtime

--==========================================================================
-- 12. 引擎接入辅助
--==========================================================================

--- 一次性挂到引擎上（在曲目脚本的 onCreate 里调用最省事）
--- @param opts table { mod = '模组目录名', files = { 'a.uic', ... } }
function uic.setup(opts)
	opts = opts or {}
	if opts.mod ~= nil then
		uic.mod = opts.mod
		uic.refreshRoots()
	end
	if opts.tagPrefix ~= nil then uic.tagPrefix = opts.tagPrefix end
	if opts.files ~= nil then
		local loaded = {}
		for i = 1, #opts.files do
			loaded[#loaded + 1] = uic.load(opts.files[i], opts)
		end
		return loaded
	end
	return nil
end

--- 重新执行已加载过的最后一个文件（热重载用）
function uic.reload(path, opts)
	if path == nil then return nil end
	uic.sourceCache = {}
	uic.astCache = {}
	return uic.load(path, opts)
end

--==========================================================================
-- 13. 自检（uic.selftest()）—— 不依赖引擎，纯逻辑验证
--==========================================================================

function uic.selftest()
	local cases = {}
	local function check(name, fn)
		local ok, err = pcall(fn)
		cases[#cases + 1] = { name = name, ok = ok, err = ok and nil or err }
	end

	check('lexer 基本切分', function()
		local toks = Lexer.tokenize('hello.[a](x, auto, auto)', 't')
		assert(toks[1].t == 'name' and toks[1].v == 'hello', 'first token')
	end)

	check('括号内字面名', function()
		local src = 'hello.[btn1-][...]("x.png", auto, auto)'
		local ast = uic.parse(src, 't')
		local names = ast.body[1].names
		assert(names[1] == 'btn1-', 'name1=' .. str(names[1]))
		assert(names[2] == '...', 'name2=' .. str(names[2]))
	end)

	--- 装一套假桥接，跑完自动还原（自检不需要引擎）
	local function withFakeBridge(fn)
		local realCreate = Bridge.createElement
		local realDestroy = Bridge.destroyElement
		local realSet = Bridge.setProp
		local realGet = Bridge.getProp
		local fake = {}

		Bridge.createElement = function(name, path, x, y)
			uic.elements[name] = { name = name, tag = name, path = path, exists = true, props = {} }
			uic.elementOrder[#uic.elementOrder + 1] = name
			fake[name .. '.__create'] = true
			fake[name .. '.x'] = x
			fake[name .. '.y'] = y
			return true
		end
		Bridge.destroyElement = function(name) uic.elements[name] = nil end
		Bridge.setProp = function(tag, key, v) fake[tag .. '.' .. key] = v end
		Bridge.getProp = function(tag, key) return fake[tag .. '.' .. key] end

		local ok, err = pcall(fn, fake)

		Bridge.createElement = realCreate
		Bridge.destroyElement = realDestroy
		Bridge.setProp = realSet
		Bridge.getProp = realGet

		if not ok then error(err, 0) end
		return fake
	end

	check('注释与换行', function()
		local toks = Lexer.tokenize('/~ 注释 ~/\nabc ? 1', 't')
		assert(toks[1].t == 'newline', 'first=' .. toks[1].t)
	end)

	check('*@ 常量 + @引用', function()
		local src = '*@ 值1 ? 0.8\nhello.[b]("x.png", auto, auto) {\n scale ? @值1 \n}'
		local ast = uic.parse(src, 't')
		assert(#ast.body == 2, 'body=' .. str(#ast.body))

		uic.elements = {}
		uic.elementOrder = {}
		local fake = withFakeBridge(function()
			local rt = Runtime.new('t')
			rt:run(ast)
		end)
		-- 假桥接收到的是 UIC 层的属性名（scale），
		-- 展开成 scale.x / scale.y 是真桥接的事，由 tests/run_tests.lua 覆盖。
		assert(fake['b.scale'] == 0.8, 'scale=' .. str(fake['b.scale']))
	end)

	check('*! 组 + hello.[!组] 批量创建 + 广播', function()
		local src = '*! G {a, b}\nhello.[!G]\nG.alpha ? 0.5'
		local ast = uic.parse(src, 't')
		uic.elements = {}
		uic.elementOrder = {}
		local fake = withFakeBridge(function()
			local rt = Runtime.new('t')
			rt:run(ast)
		end)
		assert(fake['a.__create'] == true, 'a 未创建')
		assert(fake['b.__create'] == true, 'b 未创建')
		assert(fake['a.alpha'] == 0.5, 'a.alpha=' .. str(fake['a.alpha']))
		assert(fake['b.alpha'] == 0.5, 'b.alpha=' .. str(fake['b.alpha']))
	end)

	check('嵌套叠加：比例型乘算', function()
		local src = '*@ 通用 { scale ? 0.5 }\nhello.[c]("x.png", auto, auto) {\n scale ? 2\n @通用\n}'
		local ast = uic.parse(src, 't')
		uic.elements = {}
		uic.elementOrder = {}
		local fake = withFakeBridge(function()
			local rt = Runtime.new('t')
			rt:run(ast)
		end)
		assert(fake['c.scale'] == 1, '2 * 0.5 应为 1，实际 ' .. str(fake['c.scale']))
	end)

	check('错误信息：缺少定义', function()
		local ok, err = pcall(uic.parse, 'ghost.alpha ? 1', 't')
		-- 解析不会报错，执行才报，这里只验证解析能过
		assert(ok, '解析不该报错')

		uic.elements = {}
		uic.elementOrder = {}
		local ok2, err2 = pcall(function()
			local rt = Runtime.new('t')
			rt:run(uic.parse('ghost.alpha ? 1', 't'))
		end)
		assert(not ok2, '应该报错')
		assert(string.find(str(err2), '缺少了定义', 1, true) ~= nil, '错误信息不对：' .. str(err2))
	end)

	check('错误信息：未定义引用', function()
		uic.elements = {}
		uic.elementOrder = {}
		local ok, err = pcall(function()
			local rt = Runtime.new('t')
			rt:run(uic.parse('*! G {a}\nhello.[!G] {\n @不存在的样式\n}', 't'))
		end)
		assert(not ok, '应该报错')
		assert(string.find(str(err), '你貌似没有定义', 1, true) ~= nil, '错误信息不对：' .. str(err))
	end)

	check('dp() 默认文本', function()
		local saved = uic.autoPrint
		uic.autoPrint = false
		uic.clearDp()
		uic.elements = {}
		uic.elementOrder = {}
		withFakeBridge(function()
			local rt = Runtime.new('t')
			rt:run(uic.parse('hello.[d]("x.png", auto, auto) { dp() }', 't'))
		end)
		local out = uic.dp()
		uic.autoPrint = saved
		assert(out[1] == 'D.C.LushiFu--U.I.C.', '实际 ' .. str(out[1]))
	end)

	local passed, failed = 0, 0
	for i = 1, #cases do
		if cases[i].ok then passed = passed + 1 else failed = failed + 1 end
	end
	return cases, passed, failed
end

--- 把自检结果打印出来（游戏里会走 debugPrint，纯 Lua 环境下退回 print）
function uic.printSelftest()
	local cases, passed, failed = uic.selftest()
	local lines = {}
	lines[#lines + 1] = '=== UIC 自检 ==='
	for i = 1, #cases do
		local c = cases[i]
		lines[#lines + 1] = (c.ok and '  [通过] ' or '  [失败] ') .. c.name .. (c.ok and '' or (' :: ' .. str(c.err)))
	end
	lines[#lines + 1] = '通过 ' .. str(passed) .. ' / 失败 ' .. str(failed)

	local dp = engineFn('debugPrint')
	if dp ~= nil then
		pcall(dp, table.concat(lines, '\n'))
	end
	-- 控制台也来一份，方便命令行里直接看
	local pr = engineFn('print')
	if pr ~= nil then
		for i = 1, #lines do pcall(pr, lines[i]) end
	end
	return passed, failed, cases
end

--==========================================================================
-- 14. 收尾
--==========================================================================
--
--  重要：D.C.E. / Psych 给**每个 .lua 文件**都开一个独立的 Lua state
--  （见 source/scripts/lua/FunkinLua.hx 里的 LuaL.newstate）。
--  所以「把 uic.lua 丢进 scripts/ 当全局脚本」并不能让曲目脚本用上它。
--  跨脚本的正确姿势是在曲目脚本里：
--
--      package.path = package.path .. ';mods/<你的mod>/scripts/?.lua'
--      local uic = require('uic')
--
--  下面的全局赋值只对「同一个 state 内 dofile / 内联」的场景有用
--  （例如 tests/run_tests.lua），不会影响引擎。
if type(rawget(_G, 'uic')) ~= 'table' then
	_G.uic = uic
end

return uic
