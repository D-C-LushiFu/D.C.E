package substates;

import openfl.display.BitmapData;
import openfl.display.Shape;
import openfl.Vector;

/** A single textured triangle batch. UVs encode tint and opacity in a tiny palette. */
class DCECreditsMesh extends Shape
{
	var palette:BitmapData;
	var vertices:Vector<Float> = new Vector<Float>();
	var indices:Vector<Int> = new Vector<Int>();
	var uv:Vector<Float> = new Vector<Float>();
	var penX:Float = 0;
	var penY:Float = 0;
	var thickness:Float = 0;
	var lineColor:Int = 0;
	var lineAlpha:Float = 0;
	var fillColor:Int = 0;
	var fillAlpha:Float = 0;

	public function new()
	{
		super();
		palette = new BitmapData(256, 4, true, 0);
		var colors = [0x69dcff, 0xffc56c, 0x149ac8, 0xe5f8ff];
		for (row in 0...4) for (alpha in 0...256) palette.setPixel32(alpha, row, (alpha << 24) | colors[row]);
	}

	public function clear():Void
	{
		vertices.length = indices.length = uv.length = 0;
	}

	public function lineStyle(width:Float = 0, color:Int = 0, alpha:Float = 0):Void
	{
		thickness = width;
		lineColor = color;
		lineAlpha = alpha;
	}

	public function moveTo(x:Float, y:Float):Void { penX = x; penY = y; }

	public function lineTo(x:Float, y:Float):Void
	{
		var dx = x - penX;
		var dy = y - penY;
		var length = Math.sqrt(dx * dx + dy * dy);
		if (length > .001 && thickness > 0 && lineAlpha > 0)
		{
			var nx = -dy / length;
			var ny = dx / length;
			var half = thickness / 2;
			var fringe = 2 / 3; // one physical pixel in the 1080p viewport
			var a = vertex(penX + nx * half, penY + ny * half, lineColor, lineAlpha);
			var b = vertex(x + nx * half, y + ny * half, lineColor, lineAlpha);
			var c = vertex(x - nx * half, y - ny * half, lineColor, lineAlpha);
			var d = vertex(penX - nx * half, penY - ny * half, lineColor, lineAlpha);
			quad(a, b, c, d);
			var e = vertex(penX + nx * (half + fringe), penY + ny * (half + fringe), lineColor, 0);
			var f = vertex(x + nx * (half + fringe), y + ny * (half + fringe), lineColor, 0);
			quad(e, f, b, a);
			var h = vertex(penX - nx * (half + fringe), penY - ny * (half + fringe), lineColor, 0);
			var j = vertex(x - nx * (half + fringe), y - ny * (half + fringe), lineColor, 0);
			quad(d, c, j, h);
		}
		penX = x; penY = y;
	}

	public function beginFill(color:Int, alpha:Float):Void { fillColor = color; fillAlpha = alpha; }
	public function endFill():Void {}

	public function drawCircle(x:Float, y:Float, radius:Float):Void
	{
		if (fillAlpha <= 0) return;
		var center = vertex(x, y, fillColor, fillAlpha);
		var segments = radius > 20 ? 32 : 12;
		var first = vertices.length >> 1;
		for (i in 0...segments)
		{
			var angle = i / segments * Math.PI * 2;
			vertex(x + Math.cos(angle) * radius, y + Math.sin(angle) * radius, fillColor, 0);
		}
		for (i in 0...segments) { indices.push(center); indices.push(first + i); indices.push(first + (i + 1) % segments); }
	}

	public function drawRect(x:Float, y:Float, width:Float, height:Float):Void
	{
		quad(vertex(x, y, fillColor, fillAlpha), vertex(x + width, y, fillColor, fillAlpha),
			vertex(x + width, y + height, fillColor, fillAlpha), vertex(x, y + height, fillColor, fillAlpha));
	}

	function vertex(x:Float, y:Float, color:Int, alpha:Float):Int
	{
		var index = vertices.length >> 1;
		vertices.push(x); vertices.push(y);
		var row = color == 0xffc56c ? 1 : (color == 0x149ac8 ? 2 : (color == 0xe5f8ff ? 3 : 0));
		uv.push((Math.max(0, Math.min(1, alpha)) * 255 + .5) / 256);
		uv.push((row + .5) / 4);
		return index;
	}

	function quad(a:Int, b:Int, c:Int, d:Int):Void
	{
		indices.push(a); indices.push(b); indices.push(c);
		indices.push(a); indices.push(c); indices.push(d);
	}

	public function commit():Void
	{
		// Bitmap fills + triangles stay on OpenFL's hardware path; lineStyle/circles do not.
		graphics.clear();
		graphics.beginBitmapFill(palette, null, false, true);
		graphics.drawTriangles(vertices, indices, uv);
		graphics.endFill();
	}

	public function release():Void
	{
		graphics.clear();
		palette.dispose();
		palette = null;
		vertices = null; indices = null; uv = null;
	}
}
