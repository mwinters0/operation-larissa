class_name CutsceneTimingRecord
extends RefCounted
## The timing of one cutscene as the text the fixture hashes, and the hash.
##
## Teaches: pinning behaviour without committing the original's numbers. `tests/fixtures/cutscene_timing.json` holds one SHA-256 per
## cutscene of this record (its length, whether it loops, every moment at which anything changes, every sound and event), so the
## repository states that a timeline is exactly the original's and none of its ticks. The record is the same text from a
## `CutsceneTimeline` (the data) and from an `Animation` (what a scene builds from it): every number is in whole thousandths of a
## tick, the moments are sorted and each once, the cues are in time order with a sound before an event at the same moment.
##
## tools/import/step_story.py `timing_record` writes the same text in Python; the two must agree
## (`tools/import/test_story.py`). tools/import/godot/write_cutscene_timing.gd writes the fixture.

const TICKS := CutsceneTimeline.TICKS_PER_SECOND
const SOUND := "sound"
const EVENT := "event"


## `ticks` in whole thousandths.
static func milli(ticks: float) -> int:
	return roundi(ticks * 1000.0)


## The record text of a cutscene of `length` ticks. `moments` are ticks, `cues` are [tick, kind, name].
static func record(length: float, loop: bool, moments: Array, cues: Array) -> String:
	var seen := {}
	for tick: float in moments:
		seen[milli(tick)] = true
	var sorted_moments := seen.keys()
	sorted_moments.sort()
	var calls: Array = []
	for entry: Array in cues:
		calls.append([milli(entry[0]), String(entry[1]), String(entry[2])])
	calls.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] > b[1]))
	var cue_text := PackedStringArray()
	for call in calls:
		cue_text.append("%d:%s:%s" % call)
	var moment_text := PackedStringArray()
	for moment in sorted_moments:
		moment_text.append(str(moment))
	return "length=%d;loop=%d;moments=%s;cues=%s" % [milli(length), 1 if loop else 0, ",".join(moment_text), ",".join(cue_text)]


## The record of a timeline of the data.
static func of_timeline(timeline: CutsceneTimeline) -> String:
	var cues: Array = []
	for cue_entry in timeline.cues:
		cues.append([cue_entry.tick, String(cue_entry.kind), String(cue_entry.cue_name)])
	return record(timeline.length, timeline.loop, Array(timeline.key_times()), cues)


## The record of an animation: its length and its keys in ticks, and its method calls (`play_sfx` is a sound, any other an event).
static func of_animation(animation: Animation) -> String:
	var moments: Array = []
	var cues: Array = []
	for track in animation.get_track_count():
		for key in animation.track_get_key_count(track):
			var tick := animation.track_get_key_time(track, key) * TICKS
			moments.append(tick)
			if animation.track_get_type(track) == Animation.TYPE_METHOD:
				var method := animation.method_track_get_name(track, key)
				cues.append([tick, SOUND if method == &"play_sfx" else EVENT, String(animation.method_track_get_params(track, key)[0])])
	return record(animation.length * TICKS, animation.loop_mode == Animation.LOOP_LINEAR, moments, cues)


## Lower-case hex SHA-256 of a record text.
static func digest(text: String) -> String:
	return FixtureHash.sha256_hex(text.to_utf8_buffer())
