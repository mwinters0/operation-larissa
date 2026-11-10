class_name CutsceneTimeline
extends Resource
## A cutscene's choreography as DATA: how long it lasts, which pictures are where at which moment, which sounds play
## when. No node, no path, no `Animation` in it.
##
## Teaches: separating WHAT happens from HOW it is shown. The original game timed its cartoon in ticks of a 73 Hz timer
## and drew every picture by number; this resource keeps exactly that (ticks, picture NAMES, window pixels) and a view
## decides how to show it. The original look is one view (`Cutscene.animation()` builds an `AnimationPlayer` animation from
## the timeline, and the scene's own nodes play the actors); a skin can redraw the same cutscene with other nodes and
## other art and still takes exactly as long, because the time lives here and not in the art.
##
## The timelines that come from the original are written by the importer (`tools/import/step_story.py`, into
## `data/story/`); a few small ones that are our own (the fade of a story page, the flicker of the console lights)
## are made in code with `track()` and `cue()` below. `provenance` says which is which.

## The original's timer: 73 ticks a second. Every moment of a timeline is in ticks.
const TICKS_PER_SECOND := 73.0

## How long the timeline lasts, in ticks. A cue may sit exactly at the end.
@export var length: float = 0.0
## true: starts again when it reaches the end (the lights of the console).
@export var loop: bool = false
## What changes, one property of one actor per track.
@export var tracks: Array[CutsceneTrack] = []
## What happens: sounds and events.
@export var cues: Array[CutsceneCue] = []
## Named moments (`presents`, `operation`, `neptune`): where a skip may jump to. Name -> ticks.
@export var marks: Dictionary = {}
## Where the numbers come from: the original function and file, and which numbers are our own (ground rule "provenance").
@export_multiline var provenance: String = ""


## Ticks as seconds.
static func seconds(ticks: float) -> float:
	return ticks / TICKS_PER_SECOND


## The length in seconds.
func length_seconds() -> float:
	return seconds(length)


## The track of `actor`'s `property`, or null.
func find_track(actor: StringName, property: StringName) -> CutsceneTrack:
	for track in tracks:
		if track.actor == actor and track.property == property:
			return track
	return null


## Every moment at which anything changes or happens (a key of a track, a cue), in ticks, increasing, each once.
## The tests pin these against the numbers of the original; the view needs nothing like it.
func key_times() -> PackedFloat64Array:
	var seen := {}
	for track in tracks:
		for t in track.times:
			seen[snappedf(t, 1e-6)] = true
	for cue_entry in cues:
		seen[snappedf(cue_entry.tick, 1e-6)] = true
	var list := seen.keys()
	list.sort()
	return PackedFloat64Array(list)


## What is wrong with this timeline, or an empty list when it is fine.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if length <= 0.0:
		found.append("no length")
	for track in tracks:
		var problem := track.problem()
		if problem != "":
			found.append(problem)
		elif track.times[track.times.size() - 1] > length + 1e-6:
			found.append("%s %s: a key after the end" % [track.actor, track.property])
	for cue_entry in cues:
		if cue_entry.tick > length + 1e-6:
			found.append("cue %s after the end" % cue_entry.cue_name)
	return found


# --- making a timeline in code -------------------------------------------------------------------------------

## Adds a track from a list of [tick, value] pairs and returns the timeline (so calls can be chained).
func track(actor: StringName, property: StringName, keys: Array, smooth: bool = false) -> CutsceneTimeline:
	tracks.append(CutsceneTrack.from_keys(actor, property, keys, smooth))
	return self


## Adds a cue at `tick`.
func cue(tick: float, kind: StringName, cue_name: StringName) -> CutsceneTimeline:
	cues.append(CutsceneCue.happening(tick, kind, cue_name))
	return self


## A new timeline of `ticks` that is made in code (`provenance` says so).
static func made_in_code(ticks: float, why: String, loops: bool = false) -> CutsceneTimeline:
	var timeline := CutsceneTimeline.new()
	timeline.length = ticks
	timeline.loop = loops
	timeline.provenance = why
	return timeline


## This timeline's tracks and cues together with `other`'s, as a new timeline (they must agree on length and looping).
## For a cutscene whose original part comes from a file and whose own part is made in code.
func merged_with(other: CutsceneTimeline) -> CutsceneTimeline:
	assert(is_equal_approx(length, other.length) and loop == other.loop, "timelines to merge must have the same length")
	var merged := CutsceneTimeline.new()
	merged.length = length
	merged.loop = loop
	merged.tracks = tracks + other.tracks
	merged.cues = cues + other.cues
	merged.marks = marks.merged(other.marks)
	merged.provenance = provenance + "\n" + other.provenance
	return merged
