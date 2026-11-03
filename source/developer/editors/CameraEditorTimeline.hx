package developer.editors;

import games.backend.Song.SwagSong;

typedef CameraTimelineSection = {time:Float, beat:Float, beats:Float, bpm:Float, index:Int};

/** A document timeline whose coordinates do not change when playback changes Conductor.bpm. */
class CameraEditorTimeline
{
	public var sections:Array<CameraTimelineSection> = [];
	public var endTime:Float = 0;
	public var endBeat:Float = 0;

	public function new(song:SwagSong)
	{
		if(song == null) return;
		var bpm:Float = validBpm(song.bpm, 100);
		for(i in 0...song.notes.length)
		{
			var sec = song.notes[i];
			if(sec != null && sec.changeBPM) bpm = validBpm(sec.bpm, bpm);
			var beats:Float = sec != null && sec.sectionBeats > 0 ? sec.sectionBeats : 4;
			if(!Math.isFinite(beats)) beats = 4;
			sections.push({time: endTime, beat: endBeat, beats: beats, bpm: bpm, index: i});
			endTime += beats * 60000 / bpm;
			endBeat += beats;
		}
		if(sections.length == 0) sections.push({time: 0, beat: 0, beats: 4, bpm: bpm, index: 0});
	}

	static function validBpm(value:Float, fallback:Float):Float
		return Math.isFinite(value) && value > 0 ? value : fallback;

	public function sectionAt(ms:Float):CameraTimelineSection
	{
		var lo = 0; var hi = sections.length - 1;
		while(lo < hi)
		{
			var mid = (lo + hi + 1) >> 1;
			if(sections[mid].time <= ms) lo = mid; else hi = mid - 1;
		}
		return sections[lo];
	}

	public function beatAt(ms:Float):Float
	{
		var sec = sectionAt(ms);
		return sec.beat + (ms - sec.time) * sec.bpm / 60000;
	}

	public function timeAtBeat(beat:Float):Float
	{
		var lo = 0; var hi = sections.length - 1;
		while(lo < hi)
		{
			var mid = (lo + hi + 1) >> 1;
			if(sections[mid].beat <= beat) lo = mid; else hi = mid - 1;
		}
		var sec = sections[lo];
		return sec.time + (beat - sec.beat) * 60000 / sec.bpm;
	}

	public function snap(ms:Float, steps:Int):Float
	{
		// Match Chart Editor's quantization denominator: 16 means sixteenth notes,
		// or four snap points per beat.
		var interval = 4 / Math.max(1, steps);
		return Math.max(0, timeAtBeat(Math.round(beatAt(ms) / interval) * interval));
	}
}
