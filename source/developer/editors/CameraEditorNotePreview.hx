package developer.editors;

import games.PlayState;
import games.backend.Song;
import games.backend.KeyChange;
import games.backend.NoteTypesConfig;
import games.backend.NoteTypesConfig.NoteTypeProperty;
import games.backend.ExtraKeysHandler;
import games.objects.Note;
import games.objects.Character;
import general.backend.ClientPrefs;
import general.backend.Paths;

typedef CameraPreviewNote = {
	var time:Float;
	var duration:Float;
	var dir:Int;
	var mania:Int;
	var mustHit:Bool;
	var gfNote:Bool;
	var anim:String;
	var type:String;
	var noAnimation:Bool;
};

typedef CameraPreviewMarker = {
	var time:Float;
	var duration:Float;
	var mustHit:Bool;
	var special:Bool;
};

/** Read the same note metadata as gameplay while keeping seeks independent of consumed gameplay notes. */
@:access(games.PlayState)
class CameraEditorNotePreview
{
	public var notes:Array<CameraPreviewNote> = [];
	public var holds:Array<CameraPreviewNote> = [];
	public var onHit:CameraPreviewNote->Void;
	public var lastHit:CameraPreviewNote;
	var ps:PlayState;
	var timeline:CameraEditorTimeline;
	var pointer:Int = 0;
	var lastBeat:Int = -1;
	var lastTime:Float = 0;
	var latest:Array<CameraPreviewNote> = [null, null, null];
	var baseMania:Int;
	var longestDuration:Float = 0;
	var markerFrom:Float = Math.NaN;
	var markerTo:Float = Math.NaN;
	var markerCapacity:Int = 0;
	var markerCache:Array<CameraPreviewMarker> = [];
	public var markerBuilds(default,null):Int = 0;

	public function new(host:PlayState, document:CameraEditorTimeline)
	{
		ps = host; timeline = document;
		baseMania = ps.baseMania;
		var generated:Map<String, Note> = [];
		var typeConfigs:Map<String,Array<NoteTypeProperty>> = [];
		for(n in ps.unspawnNotes) if(n != null && !n.isSustainNote) generated.set(noteKey(n.strumTime, n.noteData, n.mustPress), n);
		if(ps.notes != null) for(n in ps.notes.members) if(n != null && !n.isSustainNote) generated.set(noteKey(n.strumTime, n.noteData, n.mustPress), n);
		for(sec in PlayState.SONG.notes)
		{
			if(sec == null || sec.sectionNotes == null) continue;
			for(raw in sec.sectionNotes)
			{
				if(raw == null || raw.length < 2) continue;
				var time:Float = Std.parseFloat(Std.string(raw[0])) + ClientPrefs.data.noteOffset;
				if(!Math.isFinite(time)) continue;
				var mania = maniaAt(time);
				var keys = mania + 1;
				var lane:Int = Std.int(raw[1]);
				if(lane < 0 || keys <= 0) continue;
				var pe104 = Song.chartEngineVersion == 'Pe-1.0.4';
				var mustHit = pe104 ? lane < keys : (lane >= keys ? !sec.mustHitSection : sec.mustHitSection);
				var dir = lane % keys;
				if(ClientPrefs.data.flipChart && mania == 3) dir = 3 - dir;
				var type:String = raw.length > 3 && raw[3] != null ? Std.string(raw[3]) : '';
				if(raw.length > 3 && raw[3] != null && !Std.isOfType(raw[3], String))
				{
					var idx = Std.int(raw[3]);
					type = idx >= 0 && idx < Note.defaultNoteTypes.length ? Note.defaultNoteTypes[idx] : '';
				}
				var gf = type == 'GF Sing' || (sec.gfSection && (pe104 ? mustHit == sec.mustHitSection : lane < keys));
				var suffix = type == 'Alt Animation' || (sec.altAnim && !sec.gfSection) ? '-alt' : '';
				var noAnim = type == 'No Animation' || (type == 'Hurt Note' && mustHit);
				var model = generated.get(noteKey(time, dir, mustHit));
				if(model != null)
				{
					gf = model.gfNote; suffix = model.animSuffix;
					if(sec.altAnim && !sec.gfSection && !mustHit) suffix = '-alt';
					noAnim = model.noAnimation || (mustHit && (model.ignoreNote || model.hitCausesMiss));
				}
				else if(type.length > 0)
				{
					if(!typeConfigs.exists(type)) typeConfigs.set(type,Paths.getTextFromFile('custom_notetypes/' + type + '.txt') != null ? NoteTypesConfig.loadNoteTypeData(type) : null);
					var config = typeConfigs.get(type);
					if(config != null) for(item in config) if(item.property.length == 1)
						switch(item.property[0]) { case 'animSuffix': suffix = Std.string(item.value); case 'gfNote': gf = item.value == true; case 'noAnimation': noAnim = item.value == true; default: }
				}
				var visual = Note.visualLane(mania, dir);
				var data = ExtraKeysHandler.instance.data;
				var anim = 'sing' + (visual >= 0 && visual < data.animations.length ? data.animations[visual].sing : 'LEFT') + suffix;
				var duration:Float = raw.length > 2 ? Std.parseFloat(Std.string(raw[2])) : 0;
				if(!Math.isFinite(duration) || duration < 0) duration = 0;
				longestDuration = Math.max(longestDuration,duration);
				notes.push({time: time, duration: duration, dir: dir, mania: mania, mustHit: mustHit, gfNote: gf, anim: anim, type: type, noAnimation: noAnim});
			}
		}
		notes.sort(function(a,b) return a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
	}

	static function noteKey(time:Float, lane:Int, side:Bool):String return Math.round(time * 100) + ':' + lane + ':' + side;

	/** Keep sparse holds exact and aggregate dense overviews across the entire visible range. */
	public function markers(from:Float, to:Float, capacity:Int):Array<CameraPreviewMarker>
	{
		if(from == markerFrom && to == markerTo && capacity == markerCapacity) return markerCache;
		markerFrom = from; markerTo = to; markerCapacity = capacity;
		markerCache = []; markerBuilds++;
		if(capacity < 2 || to <= from) return markerCache;
		var low = 0; var high = notes.length;
		while(low < high) { var mid = (low + high) >> 1; if(notes[mid].time < from - longestDuration) low = mid + 1; else high = mid; }
		var overflow = false;
		for(index in low...notes.length)
		{
			var n = notes[index];
			if(n.time > to) break;
			if(n.time + n.duration < from) continue;
			if(markerCache.length == capacity) { overflow = true; break; }
			var start = Math.max(from,n.time);
			markerCache.push({time:start,duration:Math.max(0,Math.min(to,n.time + n.duration) - start),mustHit:n.mustHit,special:n.type.length > 0});
		}
		if(!overflow) return markerCache;
		markerCache = [];
		var perSide = Std.int(capacity / 2);
		var binWidth = (to - from) / perSide;
		var bins:Array<CameraPreviewMarker> = [for(i in 0...perSide * 2) null];
		for(index in low...notes.length)
		{
			var n = notes[index];
			if(n.time > to) break;
			if(n.time + n.duration < from) continue;
			var first = Std.int(Math.max(0,Math.min(perSide - 1,Math.floor((n.time - from) / binWidth))));
			var last = Std.int(Math.max(first,Math.min(perSide - 1,Math.floor((n.time + n.duration - from) / binWidth))));
			for(bin in first...last + 1)
			{
				var slot = (n.mustHit ? perSide : 0) + bin;
				if(bins[slot] == null) bins[slot] = {time:from + bin * binWidth,duration:binWidth,mustHit:n.mustHit,special:n.type.length > 0};
				else if(n.type.length > 0) bins[slot].special = true;
			}
		}
		for(marker in bins) if(marker != null) markerCache.push(marker);
		return markerCache;
	}

	public function maniaAt(ms:Float):Int return KeyChange.maniaAt(ms, ps.keyChangePoints, baseMania);
	function role(n:CameraPreviewNote):Int return n.gfNote ? 2 : (n.mustHit ? 0 : 1);
	function character(index:Int):Character return index == 2 ? ps.gf : (index == 0 ? ps.boyfriend : ps.dad);
	function releaseTime(n:CameraPreviewNote, ch:Character):Float return n.time + n.duration + 60000 / timeline.sectionAt(n.time + n.duration).bpm / 4 * 1.1 * ch.singDuration;

	function play(n:CameraPreviewNote):Void
	{
		if(n.noAnimation) return;
		var ch = character(role(n));
		if(ch == null) return;
		var anim = n.type == 'Hey!' ? (n.gfNote ? 'cheer' : 'hey') : n.anim;
		if(!ch.hasAnimation(anim)) anim = n.anim;
		ch.playAnim(anim, true); ch.holdTimer = 0;
		if(n.type == 'Hey!' && (anim == 'hey' || anim == 'cheer')) { ch.specialAnim = true; ch.heyTimer = 0.6; }
		latest[role(n)] = n;
	}

	public function seek(ms:Float):Void
	{
		pointer = 0; holds = []; latest = [null,null,null];
		lastTime = ms; lastBeat = Math.floor(timeline.beatAt(ms));
		for(i in 0...3)
		{
			var ch = character(i);
			if(ch != null) { ch.specialAnim = false; ch.heyTimer = 0; ch.holdTimer = 0; ch.danced = lastBeat % 2 == 0; ch.dance(); }
		}
		while(pointer < notes.length && notes[pointer].time <= ms)
		{
			var n = notes[pointer++];
			if(!n.noAnimation) latest[role(n)] = n;
			if(n.duration > 0 && n.time + n.duration >= ms) holds.push(n);
		}
		for(n in latest) if(n != null)
		{
			var ch = character(role(n));
			if(ch != null && ms <= (n.type == 'Hey!' ? n.time + 600 : releaseTime(n,ch))) play(n);
		}
	}

	public function update(ms:Float):Void
	{
		if(ms < lastTime - 1) seek(ms);
		lastTime = ms;
		var holdIndex = holds.length;
		while(holdIndex > 0) { holdIndex--; var n = holds[holdIndex]; if(n.time + n.duration < ms) holds.splice(holdIndex,1); }
		for(i in 0...3)
		{
			var ch = character(i); var n = latest[i];
			if(ch == null) continue;
			var held = false;
			for(h in holds) if(!h.noAnimation && role(h) == i) { held = true; ch.holdTimer = 0; if(!ch.getAnimationName().startsWith('sing') && !ch.specialAnim) play(h); }
			if(!held && n != null && ms > releaseTime(n,ch) && ch.getAnimationName().startsWith('sing')) { ch.dance(); latest[i] = null; }
		}
		var beat = Math.floor(timeline.beatAt(ms));
		if(beat != lastBeat) { ps.characterBopper(beat); lastBeat = beat; }
		while(pointer < notes.length && notes[pointer].time <= ms)
		{
			var n = notes[pointer++];
			play(n);
			lastHit = n;
			if(n.duration > 0 && n.time + n.duration >= ms) holds.push(n);
			if(onHit != null) onHit(n);
		}
	}
}
