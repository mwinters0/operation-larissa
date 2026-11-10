class_name CutsceneCue
extends Resource
## Something that HAPPENS at one moment of a cutscene, as opposed to a property that changes: a sound is played, or the
## view is told that a step has been reached ("show the prompt", "the animation is over").
##
## Teaches: an `Animation` "method track" in the game's own words. A sound is a NAME of the registry (`sound` kind), so a
## timeline never says which file or number plays; an event is a NAME the view answers in `StorySegment.cue()`.
## `Cutscene.animation()` turns cues into calls of `play_sfx` and `cue` on the segment.

const SOUND := &"sound"
const EVENT := &"event"

## When, in ticks of the 73 Hz timer.
@export var tick: float = 0.0
## `SOUND` or `EVENT`.
@export var kind: StringName = SOUND
## The sound's name, or the event's.
@export var cue_name: StringName = &""


static func happening(when: float, cue_kind: StringName, name_of_cue: StringName) -> CutsceneCue:
	var cue := CutsceneCue.new()
	cue.tick = when
	cue.kind = cue_kind
	cue.cue_name = name_of_cue
	return cue
