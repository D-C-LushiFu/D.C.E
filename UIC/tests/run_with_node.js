// ============================================================================
//  UIC 测试套件 —— Node.js 运行器（可选）
//  ---------------------------------------------------------------------------
//  用 fengari（纯 JS 的 Lua 5.3 虚拟机）在本机跑测试，不需要开游戏、也不需要装 Lua。
//
//  准备：
//      npm i fengari
//  运行（在 UIC/tests 目录下）：
//      node run_with_node.js
//
//  它会依次跑两个独立 Lua state：
//      1) uic.lua + tests/run_tests.lua      —— 62 项运行时测试
//      2) uic.lua + tests/run_examples.lua   —— 三个示例文件端到端验证
//
//  宿主额外提供两个全局给 Lua 用：
//      print                 —— 保证有输出
//      __readfile(path)      —— 从磁盘读文本（示例验证用）
// ============================================================================

'use strict';

const fs = require('fs');
const path = require('path');

let fengari;
try {
	fengari = require('fengari');
} catch (e) {
	console.error('[运行器] 找不到 fengari。请先执行：npm i fengari');
	process.exit(2);
}

const { lua, lauxlib, lualib, to_luastring } = fengari;

const HERE = __dirname;
const LIB_PATH = path.join(HERE, '..', 'uic.lua');

/** 读文本并去掉 UTF-8 BOM */
function readText(file) {
	let text = fs.readFileSync(file, 'utf8');
	if (text.charCodeAt(0) === 0xFEFF) text = text.slice(1);
	return text;
}

/** 新建一个装好辅助函数的 Lua state */
function newState() {
	const L = lauxlib.luaL_newstate();
	lualib.luaL_openlibs(L);

	// fengari 在裸 Node 环境下 print 未必有输出，自己接管
	lua.lua_pushjsfunction(L, function (L) {
		const n = lua.lua_gettop(L);
		const parts = [];
		for (let i = 1; i <= n; i++) {
			const t = lua.lua_type(L, i);
			if (t === lua.LUA_TBOOLEAN) {
				parts.push(lua.lua_toboolean(L, i) ? 'true' : 'false');
			} else if (t === lua.LUA_TNIL) {
				parts.push('nil');
			} else {
				const s = lua.lua_tojsstring(L, i);
				parts.push(s === null || s === undefined ? 'nil' : s);
			}
		}
		console.log(parts.join('\t'));
		return 0;
	});
	lua.lua_setglobal(L, to_luastring('print'));

	// 给 Lua 一个读文件的口子（避开 fengari 的 io 支持不确定性）
	lua.lua_pushjsfunction(L, function (L) {
		const rel = lua.lua_tojsstring(L, 1);
		const full = path.isAbsolute(rel) ? rel : path.join(HERE, rel);
		if (fs.existsSync(full) && fs.statSync(full).isFile()) {
			lua.lua_pushstring(L, to_luastring(readText(full)));
		} else {
			lua.lua_pushnil(L);
		}
		return 1;
	});
	lua.lua_setglobal(L, to_luastring('__readfile'));

	return L;
}

/** 在给定 state 里执行一段 Lua 源码 */
function runChunk(L, label, source) {
	const status = lauxlib.luaL_dostring(L, to_luastring(source));
	if (status !== lua.LUA_OK) {
		const msg = lua.lua_tojsstring(L, -1);
		console.error('[' + label + '] 执行失败：' + msg);
		process.exitCode = 1;
		return false;
	}
	return true;
}

/** 跑一组：先加载库，再加载脚本 */
function runSuite(title, scriptFile) {
	console.log('');
	console.log('############################################################');
	console.log('# ' + title);
	console.log('############################################################');

	const scriptPath = path.join(HERE, scriptFile);
	if (!fs.existsSync(scriptPath)) {
		console.log('[运行器] 跳过：找不到 ' + scriptFile);
		return;
	}
	if (!fs.existsSync(LIB_PATH)) {
		console.error('[运行器] 找不到 uic.lua：' + LIB_PATH);
		process.exit(2);
	}

	const L = newState();
	if (runChunk(L, 'uic.lua', readText(LIB_PATH))) {
		if (runChunk(L, scriptFile, readText(scriptPath))) {
			// 脚本会把失败数写进全局 __FAILED
			lua.lua_getglobal(L, to_luastring('__FAILED'));
			const failed = lua.lua_tonumber(L, -1);
			lua.lua_pop(L, 1);
			if (failed && failed > 0) process.exitCode = 1;
		}
	}
}

runSuite('UIC 运行时测试', 'run_tests.lua');
runSuite('UIC 示例端到端验证', 'run_examples.lua');

console.log('');
if (process.exitCode) {
	console.log('>>> 有测试未通过，请看上面的 [失败] 行。');
} else {
	console.log('>>> 全部通过。');
}
