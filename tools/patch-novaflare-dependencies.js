#!/usr/bin/env node
// Apply the NovaFlare compatibility additions expected by this engine after
// hmm installs the public hxcpp and Flixel forks on a clean build runner.

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync, execSync } = require('node:child_process');

function libraryRoots(name, requiredFiles) {
  const output = process.platform === 'win32'
    ? execSync(`haxelib path ${name}`, { encoding: 'utf8' })
    : execFileSync('haxelib', ['path', name], { encoding: 'utf8' });
  return output
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .map((line) => path.resolve(line))
    .filter((root) => requiredFiles.every((file) => fs.existsSync(path.join(root, file))));
}

function patchFlxText(file) {
  let source = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
  let changed = false;

  if (!source.includes('uiSizeScale')) {
    const renderScale = 'public static var renderScale:Float = 1.0;';
    if (!source.includes(renderScale)) throw new Error(`Could not find renderScale in ${file}`);
    source = source.replace(
      renderScale,
      `${renderScale}\n\t/** Global UI font raster scale used by NovaFlare editor screens. */\n\tpublic static var uiSizeScale:Float = 1.0;`
    );
    changed = true;
  }

  const constructorFormat = '_defaultFormat = new TextFormat(null, Size, 0xffffff);';
  if (source.includes(constructorFormat)) {
    source = source.replace(constructorFormat, '_defaultFormat = new TextFormat(null, Std.int(Size * uiSizeScale), 0xffffff);');
    changed = true;
  }

  const unscaledSetter = '_defaultFormat.size = Std.int(Size * renderScale);';
  if (source.includes(unscaledSetter)) {
    source = source.replace(unscaledSetter, '_defaultFormat.size = Std.int(Size * renderScale * uiSizeScale);');
    changed = true;
  }

  const borderSetter = /(function set_borderSize\(Value:Float\):Float\s*\{)([\s\S]*?)(\n\t\})/;
  const borderMatch = source.match(borderSetter);
  if (borderMatch && !borderMatch[2].includes('Value *= uiSizeScale;')) {
    source = source.replace(borderSetter, `$1\n\t\tValue *= uiSizeScale;$2$3`);
    changed = true;
  }

  if (!source.includes('public static var uiSizeScale:Float = 1.0;') ||
      !source.includes('Std.int(Size * renderScale * uiSizeScale)')) {
    throw new Error(`FlxText UI scale compatibility patch did not apply completely: ${file}`);
  }

  if (changed) fs.writeFileSync(file, source, 'utf8');
  console.log(`${changed ? 'Patched' : 'Already patched'} FlxText at ${file}`);
}

function patchFlxButton(file) {
  let source = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
  let changed = false;
  const classHeader = 'class FlxButton extends FlxTypedButton<FlxText>\n{';
  const buttonStatics = `${classHeader}
	/** Live button registry used to release UI buttons that outlive their state. */
	public static var aliveCount:Int = 0;
	public static var instances:Array<FlxButton> = [];

	public static function releaseOrphaned():Void
	{
		while (instances.length > 0)
		{
			var button:FlxButton = instances.pop();
			if (button != null && button.exists)
			{
				try button.destroy() catch (e:Dynamic) {}
			}
		}
	}
`;

  if (!source.includes('public static function releaseOrphaned():Void')) {
    if (!source.includes(classHeader)) throw new Error(`Could not find FlxButton class header in ${file}`);
    source = source.replace(classHeader, buttonStatics);
    changed = true;
  }

  const lastStatus = 'var lastStatus = -1;';
  if (!source.includes('_boundOnUpListener')) {
    if (!source.includes(lastStatus)) throw new Error(`Could not find FlxTypedButton state anchor in ${file}`);
    source = source.replace(lastStatus, `${lastStatus}\n\tvar _boundOnUpListener:MouseEvent->Void;`);
    changed = true;
  }

  const constructorAnchor = 'super(X, Y);\n\n\t\tloadDefaultGraphic();';
  if (source.includes(constructorAnchor) && !source.includes('FlxButton.instances.push(cast this);')) {
    source = source.replace(
      constructorAnchor,
      'super(X, Y);\n\n\t\tFlxButton.aliveCount++;\n\t\tFlxButton.instances.push(cast this);\n\t\tloadDefaultGraphic();'
    );
    changed = true;
  }

  const addListener = 'FlxG.stage.addEventListener(MouseEvent.MOUSE_UP, onUpEventListener);';
  if (source.includes(addListener)) {
    source = source.replace(addListener, '_boundOnUpListener = onUpEventListener;\n\t\tFlxG.stage.addEventListener(MouseEvent.MOUSE_UP, _boundOnUpListener);');
    changed = true;
  }

  const destroyAnchor = 'override public function destroy():Void\n\t{\n\t\tlabel = FlxDestroyUtil.destroy(label);';
  if (source.includes(destroyAnchor)) {
    source = source.replace(
      destroyAnchor,
      'override public function destroy():Void\n\t{\n\t\tFlxButton.aliveCount--;\n\t\tFlxButton.instances.remove(cast this);\n\t\tlabel = FlxDestroyUtil.destroy(label);'
    );
    changed = true;
  }

  const removeListener = 'FlxG.stage.removeEventListener(MouseEvent.MOUSE_UP, onUpEventListener);';
  if (source.includes(removeListener)) {
    source = source.replace(removeListener, 'FlxG.stage.removeEventListener(MouseEvent.MOUSE_UP, _boundOnUpListener);');
    changed = true;
  }

  if (!source.includes('public static function releaseOrphaned():Void') ||
      !source.includes('FlxButton.instances.push(cast this);') ||
      !source.includes('FlxButton.instances.remove(cast this);') ||
      !source.includes('_boundOnUpListener = onUpEventListener;')) {
    throw new Error(`FlxButton orphan cleanup compatibility patch did not apply completely: ${file}`);
  }

  if (changed) fs.writeFileSync(file, source, 'utf8');
  console.log(`${changed ? 'Patched' : 'Already patched'} FlxButton at ${file}`);
}

function patchFlixel() {
  const roots = libraryRoots('flixel', ['flixel/text/FlxText.hx', 'flixel/ui/FlxButton.hx']);
  if (roots.length === 0) throw new Error('haxelib path flixel did not resolve to a Flixel source checkout');
  for (const root of roots) {
    patchFlxText(path.join(root, 'flixel', 'text', 'FlxText.hx'));
    patchFlxButton(path.join(root, 'flixel', 'ui', 'FlxButton.hx'));
  }
}

function patchHxcpp() {
  const roots = libraryRoots('hxcpp', ['include/hx/GC.h', 'src/hx/gc/Immix.cpp']);
  if (roots.length === 0) throw new Error('haxelib path hxcpp did not resolve to an hxcpp source checkout');

  for (const root of roots) {
    const headerPath = path.join(root, 'include', 'hx', 'GC.h');
    const immixPath = path.join(root, 'src', 'hx', 'gc', 'Immix.cpp');
    let header = fs.readFileSync(headerPath, 'utf8').replace(/\r\n/g, '\n');
    let immix = fs.readFileSync(immixPath, 'utf8').replace(/\r\n/g, '\n');
    let changed = false;

    if (!header.includes('__hxcpp_gc_request_full')) {
      const declaration = /^\s*HXCPP_EXTERN_CLASS_ATTRIBUTES\s+void\s+__hxcpp_gc_safe_point\(\);\s*$/m;
      if (!declaration.test(header)) throw new Error(`Could not find safe-point declaration in ${headerPath}`);
      header = header.replace(
        declaration,
        (match) => `${match}\n// Non-blocking full-collection request used by GCManager.requestFull().\nHXCPP_EXTERN_CLASS_ATTRIBUTES void  __hxcpp_gc_request_full();`
      );
      fs.writeFileSync(headerPath, header, 'utf8');
      changed = true;
    }

    if (!/\bvoid\s+__hxcpp_gc_request_full\s*\(/.test(immix)) {
      const safePoint = /void\s+__hxcpp_gc_safe_point\s*\(\s*\)\s*\{\s*if\s*\(\s*hx::gPauseForCollect\s*\)\s*hx::PauseForCollect\s*\(\s*\)\s*;\s*\}/m;
      if (!safePoint.test(immix)) throw new Error(`Could not find safe-point implementation in ${immixPath}`);
      immix = immix.replace(
        safePoint,
        (match) => `${match}\n\n// Queue a collection without blocking the calling thread.\nvoid __hxcpp_gc_request_full()\n{\n   hx::gPauseForCollect = 0xffffffff;\n}`
      );
      fs.writeFileSync(immixPath, immix, 'utf8');
      changed = true;
    }

    console.log(`${changed ? 'Patched' : 'Already patched'} hxcpp at ${root}`);
  }
}

patchFlixel();
patchHxcpp();
