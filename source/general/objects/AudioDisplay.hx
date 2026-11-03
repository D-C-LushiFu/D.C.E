package general.objects;

import openfl.geom.Rectangle;
import funkin.vis.dsp.SpectralAnalyzer;
import funkin.vis.dsp.SpectralAnalyzer.Bar;
import lime.media.AudioBuffer;
import lime.media.AudioSource;
import flixel.FlxStrip;

/**
 * Main-menu spectrum rendered as one cached sprite texture.
 *
 * The previous implementation created and submitted one FlxSprite per bar.
 * The first batched implementation still rebuilt and copied hundreds of
 * triangle values on every game frame.  At uncapped frame rates that work was
 * considerably more expensive than the rest of the menu.  This version keeps
 * all 100 bars, but rasterizes them into a private, moderately sized texture at
 * a visual refresh rate.  Normal frames only submit one cached sprite quad.
 */
class AudioDisplay extends FlxSprite
{
	var analyzer:SpectralAnalyzer;
	var boundAudioSource:AudioSource;
	var externalAudioSource:AudioSource;
	var externalAudioBuffer:AudioBuffer;
	var useExternalAudioSource:Bool = false;

	var barXPositions:Array<Int> = [];
	var barWidths:Array<Int> = [];

	public var snd:FlxSound;
	public var symmetry:Bool = false;
	public var stopUpdate:Bool = false;
	public var amplitude:Float = 0;
    /** Per-view gain; the default preserves other menus' spectrum levels. */
    public var visualGain:Float = 1;
	public var attackSpeed:Float = 16;
	public var releaseSpeed:Float = 16;
    /** Freeplay's finite voice stems must not retain a stopped channel's last FFT. */
    public var resetWhenStopped:Bool = false;
	/** Negative keeps the global preference; views can request a faster local FFT cadence. */
	public var sampleIntervalMs:Float = -1;
	/** Optional per-view FFT resolution; zero follows the user's global preference. */
	public var fftQualityOverride:Int = 0;

	var line:Int;
	var displayWidth:Int;
	var displayHeight:Int;
	var bitmapWidth:Int;
	var bitmapHeight:Int;
	var barStep:Float;
	var bitmapGap:Int;
	var barHeights:Array<Float> = [];
	var barColor:FlxColor;
	var drawRect:Rectangle = new Rectangle();
	var saveTime:Float = 0;
	var motionTime:Float = 0;
	var getValues:Array<Bar>;
	var barMesh:FlxStrip;
	var reflectedMesh:FlxStrip;
	var geometryRate:Float = 60;

	static inline final MAX_VISUAL_RATE:Float = 120;
	static inline final MAX_BITMAP_WIDTH:Int = 640;

	public function new(snd:FlxSound = null, X:Float = 0, Y:Float = 0,
		Width:Int, Height:Int, line:Int, gap:Int, Color:FlxColor,
		symmetry:Bool = false)
	{
		super(X, Y);

		this.snd = snd;
		this.line = Std.int(Math.max(1, line));
		this.symmetry = symmetry;
		displayWidth = Width;
		displayHeight = Height;
		barColor = Color;

		// The texture is deliberately smaller than the display.  Spectrum bars
		// do not contain fine detail, and scaling this bitmap saves both CPU
		// raster work and GPU upload bandwidth when its shape changes.
		bitmapWidth = Std.int(Math.min(MAX_BITMAP_WIDTH, Math.max(1, Width)));
		bitmapHeight = Std.int(Math.max(1, Math.ceil(Height * bitmapWidth / Width)));
		bitmapGap = Std.int(Math.max(0, Math.round(gap * bitmapWidth / Width)));
		if (this.line > 1)
		{
			// Always leave at least one source pixel for every bar.
			final maxGap = Std.int(Math.max(0,
				Math.floor((bitmapWidth - this.line) / (this.line - 1))));
			bitmapGap = Std.int(Math.min(bitmapGap, maxGap));
		}
		else
			bitmapGap = 0;

		// Round only bar starts. Every non-final bar ends exactly bitmapGap
		// pixels before the next start, so cumulative fractional widths can no
		// longer turn nominally equal gaps into touching/widely separated pairs.
		barStep = (bitmapWidth + bitmapGap) / this.line;

		makeGraphic(bitmapWidth, bitmapHeight, FlxColor.TRANSPARENT, true);
		setGraphicSize(displayWidth, displayHeight);
		updateHitbox();
		x = X;
		y = Y - displayHeight;
		buildBars();
		rasterizeBars();

		refreshAnalyzerBinding();
	}

	function buildBars():Void
	{
		final minimum = bitmapHeight / 40;
		for (i in 0...line)
			barHeights.push(minimum);

		barXPositions.resize(line);
		barWidths.resize(line);

		for (i in 0...line)
		{
			final x0 = Std.int(Math.round(barStep * i));
			final x1 = i == line - 1
				? bitmapWidth
				: Std.int(Math.round(barStep * (i + 1))) - bitmapGap;

			barXPositions[i] = x0;
			barWidths[i] = Std.int(Math.max(1, x1 - x0));
		}
	}

	override function update(elapsed:Float):Void
	{
		// FlxSound.loadStream() disposes the old SoundChannel before installing
		// the next one. Never let the analyzer retain that disposed AudioSource.
		refreshAnalyzerBinding();

		if (stopUpdate)
			return;

		saveTime += elapsed * 1000;
		motionTime += elapsed;
		final sampleInterval = Math.max(1000 / MAX_VISUAL_RATE,
			sampleIntervalMs < 0 ? ClientPrefs.data.audioDisplayUpdate : sampleIntervalMs);
        var stopped = resetWhenStopped && snd != null && !snd.playing;
        if (stopped && getValues != null) {
            for (value in getValues) { value.value = 0; value.peak = 0; }
            amplitude = 0;
        }
		if (!stopped && analyzer != null && boundAudioSource != null && saveTime >= sampleInterval)
		{
			saveTime %= sampleInterval;
			// Reuse both the level array and its Bar records. Passing null here
			// rebuilt roughly one hundred managed records on every FFT sample and
			// needlessly drove a Young collection every few seconds.
			try
			{
				getValues = analyzer.getLevels(getValues);
				updateAmplitude();
			}
			catch (e:Dynamic)
			{
				// A stream can be released between the channel check above and
				// the typed-array slice inside funkin.vis. Drop the stale source;
				// a later update will bind the replacement channel if it has one.
				invalidateAnalyzerBinding();
			}
		}

		// Visual data only needs display-rate interpolation.  The engine frame
		// loop remains uncapped, while intermediate frames reuse the texture.
		if (getValues != null && motionTime >= 1 / (barMesh == null ? MAX_VISUAL_RATE : geometryRate))
		{
			updateLine(motionTime);
			motionTime = 0;
		}
	}

	function updateAmplitude():Void
	{
		final count = Std.int(Math.min(5, getValues.length));
		if (count == 0)
		{
			amplitude = 0;
			return;
		}

		var total:Float = 0;
		for (i in 0...count)
			total += getValues[i].value;
		amplitude = total / count;
	}

	function getCurrentAudioSource():AudioSource
	{
		if (useExternalAudioSource)
			return externalAudioSource;

		var source:AudioSource = null;
		@:privateAccess
		if (snd != null && snd._channel != null && snd._channel.__audioSource != null)
		{
			var candidate:AudioSource = snd._channel.__audioSource;
			if (candidate.buffer != null && candidate.buffer.data != null
				&& candidate.buffer.data.length > 0)
				source = candidate;
		}
		return source;
	}

	function refreshAnalyzerBinding():Void
	{
		var source = getCurrentAudioSource();
		if (source == boundAudioSource)
			return;

		getValues = null;
		amplitude = 0;
		saveTime = 0;
		motionTime = 0;
		clearUpdate();

		if (source == null)
		{
			if (analyzer != null)
				analyzer.changeSnd(null);
			boundAudioSource = null;
			return;
		}

		if (analyzer == null)
		{
			var quality = fftQualityOverride > 0 ? fftQualityOverride : ClientPrefs.data.audioDisplayQuality;
			analyzer = new SpectralAnalyzer(source,
				Std.int(line + Math.abs(0.05 *
					(4 - quality))), 1, 5);
			analyzer.fftN = 256 * quality;
			// Freeplay opts into a short sample interval for responsive motion;
			// pass that through to the analyzer too, otherwise its 33 ms default
			// silently repeats stale FFT frames while the display updates faster.
			if (sampleIntervalMs > 0)
				analyzer.updateIntervalMs = Std.int(Math.max(8, sampleIntervalMs));
			// Analyze the full usable spectrum for this source without extending
			// past its Nyquist limit (which creates empty-looking high bands).
			if (source.buffer != null && source.buffer.sampleRate > 0)
				analyzer.maxFreq = Math.min(22000, source.buffer.sampleRate * 0.49);
		}
		else
			analyzer.changeSnd(source);
		boundAudioSource = source;
	}

	public function refreshFFTQuality():Void
	{
		if (analyzer != null) analyzer.changeSnd(null);
		analyzer = null;
		boundAudioSource = null;
		getValues = null;
		refreshAnalyzerBinding();
	}

	function invalidateAnalyzerBinding():Void
	{
		if (analyzer != null)
			analyzer.changeSnd(null);
		boundAudioSource = null;
		getValues = null;
		amplitude = 0;
		clearUpdate();
	}

	function releaseExternalAudioBuffer():Void
	{
		if (externalAudioSource != null)
		{
			externalAudioSource.dispose();
			externalAudioSource = null;
		}
		if (externalAudioBuffer != null)
		{
			externalAudioBuffer.dispose();
			externalAudioBuffer = null;
		}
	}

	function updateLine(elapsed:Float):Void
	{
		if (getValues == null || getValues.length == 0)
			return;

		final minimum = bitmapHeight / 40;
		for (i in 0...line)
		{
			var valueIndex = symmetry && i >= line / 2 ? line - 1 - i : i;
			if (valueIndex >= getValues.length)
				valueIndex = getValues.length - 1;
			// Analyzer levels already represent normalized spectral energy. Do not
			// multiply by master volume: changing listening volume must not warp
			// the spectrum. A small noise gate and power curve retain peak shape;
			// the previous soft-knee compressed every band toward the same ceiling.
			var level = getValues[valueIndex].value * visualGain;
			if (!Math.isFinite(level)) level = 0;
			final normalized = FlxMath.bound(level, 0, 1);
			final aboveFloor = Math.max(0, (normalized - 0.055) / 0.945);
			final shapedLevel = Math.pow(aboveFloor, 1.75);
			// Cap transient peaks and ease attacks: malformed/very hot mod stems
			// must never turn a full-width white spectrum into a flash frame.
			final target = Math.round(shapedLevel * bitmapHeight * 0.52);
			final blend = Math.exp(-elapsed * (target > barHeights[i] ? attackSpeed : releaseSpeed));
			final height = Math.max(minimum,
				FlxMath.lerp(target, barHeights[i], blend));
			barHeights[i] = height;
		}
		rasterizeBars();
	}

	function rasterizeBars():Void
	{
		if (barMesh != null)
		{
			updateBarMesh();
			return;
		}
		final bitmap = pixels;
		if (bitmap == null)
			return;

		bitmap.lock();
		bitmap.fillRect(bitmap.rect, FlxColor.TRANSPARENT);

		for (i in 0...line)
		{
			final x0 = barXPositions[i];
			final width = barWidths[i];
			if (width <= 0) break;

			final height = Std.int(Math.min(bitmapHeight, Math.ceil(barHeights[i])));

			drawRect.setTo(x0, bitmapHeight - height, width, height);
			bitmap.fillRect(drawRect, barColor);
		}

		bitmap.unlock();
		dirty = true;
	}

	/** Freeplay uses a stable white texture and persistent triangle buffers.
	 * No live BitmapData uploads are shared with the reflected spectrum. */
	public function enableBarGeometry():FlxStrip
	{
		if (barMesh != null) return reflectedMesh;
		barMesh = createBarMesh();
		reflectedMesh = createBarMesh();
		reflectedMesh.setPosition(x, y + displayHeight);
		reflectedMesh.active = false;
		updateBarMesh();
		return reflectedMesh;
	}

	function createBarMesh():FlxStrip
	{
		var mesh = new FlxStrip();
		mesh.makeGraphic(1, 1, FlxColor.WHITE, true);
		mesh.color = barColor;
		mesh.antialiasing = false;
		mesh.width = displayWidth;
		mesh.height = displayHeight;
		for (i in 0...line)
		{
			var left = barXPositions[i] * displayWidth / bitmapWidth;
			var right = (barXPositions[i] + barWidths[i]) * displayWidth / bitmapWidth;
			for (value in [left, 0.0, right, 0.0, right, 0.0, left, 0.0]) mesh.vertices.push(value);
			var first = i * 4;
			for (index in [first, first + 1, first + 2, first, first + 2, first + 3]) mesh.indices.push(index);
			for (value in [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0]) mesh.uvtData.push(value);
		}
		return mesh;
	}

	function updateBarMesh():Void
	{
		barMesh.color = reflectedMesh.color = barColor;
		for (i in 0...line)
		{
			var height = barHeights[i] * displayHeight / bitmapHeight;
			if (!Math.isFinite(height)) height = 0;
			height = FlxMath.bound(height, 0, displayHeight);
			var vertex = i * 8;
			barMesh.vertices[vertex + 1] = barMesh.vertices[vertex + 3] = displayHeight - height;
			barMesh.vertices[vertex + 5] = barMesh.vertices[vertex + 7] = displayHeight;
			reflectedMesh.vertices[vertex + 1] = reflectedMesh.vertices[vertex + 3] = 0;
			reflectedMesh.vertices[vertex + 5] = reflectedMesh.vertices[vertex + 7] = height;
		}
	}

	override public function draw():Void
	{
		if (barMesh == null) { super.draw(); return; }
		barMesh.cameras = cameras;
		barMesh.setPosition(x, y);
		barMesh.alpha = alpha;
		barMesh.draw();
	}

	public function changeAnalyzer(snd:FlxSound):Void
	{
		invalidateAnalyzerBinding();
		releaseExternalAudioBuffer();
		useExternalAudioSource = false;
		this.snd = snd;
		refreshAnalyzerBinding();

		stopUpdate = false;
	}

	/** Change the cached spectrum tint without replacing its analyzer or audio source. */
	public function setBarColor(color:FlxColor):Void
	{
		if (barColor == color) return;
		barColor = color;
		rasterizeBars();
	}

	/**
	 * Supplies decoded PCM for players such as hxvlc whose placeholder
	 * SoundChannel does not expose a Lime AudioSource. The buffer is used only
	 * for FFT sampling; playback time still comes from FlxG.sound.music.
	 */
	public function changeAudioBuffer(buffer:AudioBuffer):Void
	{
		invalidateAnalyzerBinding();
		releaseExternalAudioBuffer();
		useExternalAudioSource = true;

		if (buffer != null && buffer.data != null && buffer.data.length > 0)
		{
			externalAudioBuffer = buffer;
			// Construct the backend without a buffer so the analysis copy is not
			// uploaded to OpenAL or played a second time.
			externalAudioSource = new AudioSource();
			externalAudioSource.buffer = buffer;
		}

		refreshAnalyzerBinding();
		if (analyzer != null && externalAudioBuffer != null)
		{
			// A VLC preview has no OpenAL clock. Sample decoded PCM at the real
			// FlxSound playback position instead of the analysis-only source's 0ms.
			@:privateAccess analyzer.audioClip = new PreviewAnalysisClip(externalAudioBuffer, snd);
			analyzer.updateIntervalMs = 8;
		}
		stopUpdate = false;
	}

	public function clearUpdate():Void
	{
		final minimum = bitmapHeight / 40;
		for (i in 0...line)
			barHeights[i] = minimum;
		rasterizeBars();
	}

	override public function destroy():Void
	{
		if (barMesh != null) barMesh.destroy();
		barMesh = null;
		// The reflection is owned and destroyed by the view's sprite group.
		reflectedMesh = null;
		if (analyzer != null)
			analyzer.changeSnd(null);
		releaseExternalAudioBuffer();
		analyzer = null;
		boundAudioSource = null;
		getValues = null;
		snd = null;
		super.destroy();
	}
}

private class PreviewAnalysisClip implements funkin.vis.AudioClip
{
	public var audioBuffer(default, null):funkin.vis.AudioBuffer;
	public var source:Dynamic;
	public var currentFrame(get, never):Int;
	var player:FlxSound;
	var duration:Float;
	public function new(buffer:AudioBuffer, player:FlxSound)
	{
		this.player = player;
		audioBuffer = new funkin.vis.AudioBuffer(cast buffer.data, buffer.sampleRate);
		source = buffer.src;
		duration = buffer.data.length / (buffer.channels * buffer.bitsPerSample / 8) / buffer.sampleRate * 1000;
	}
	function get_currentFrame():Int
	{
		return player == null || duration <= 0 ? 0 : Std.int(audioBuffer.data.length * FlxMath.bound(player.time / duration, 0, 1));
	}
}
