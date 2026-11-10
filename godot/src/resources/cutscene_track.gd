class_name CutsceneTrack
extends Resource
## One thing that changes during a cutscene: ONE property of ONE actor, as a list of keys (a moment and a value).
##
## Teaches: the same idea as an `Animation` track, but written in the game's own words. An `Animation` track says
## "set the `texture` of the node at `Stage/Ship/Radar`"; this says "the actor `radar` shows the picture `ship_radar_1`".
## The actor is a NAME (the view decides which node plays it), the property is one of a few words (`PICTURE`, `POSITION`,
## `MIRROR` ...) and a picture is a NAME of the registry (`docs/create/NAMES.md`), so the same timeline can be played by the
## original's sprites or by a skin's own nodes without a single path in the data. `Cutscene.animation()` turns it into
## a real `Animation` for an `AnimationPlayer`.
##
## Moments are in ticks of the original's 73 Hz timer (`CutsceneTimeline.TICKS_PER_SECOND`), as the original counted them.

## The words a track can use, and what the value of each key is:
const PROP_PICTURE := &"picture"      ## the NAME of a picture (`ui_picture` kind: `ship_radar_1`)
const PROP_MIRROR := &"mirror"        ## bool: drawn mirrored (flipped left to right)
const PROP_POSITION := &"position"    ## Vector2: window pixels of the picture's top-left corner (the screen is 640 x 400)
const PROP_VISIBLE := &"visible"      ## bool: drawn at all
const PROP_CLIP := &"clip"            ## Rect2: the part of the picture that is drawn (the mini-sub sinking behind the waves)
const PROP_TEXT := &"text"            ## the NAME of a text of the original (`text` kind), or "" for an empty box
const PROP_REVEAL := &"reveal"        ## float 0..1: how much of the text is typed so far
const PROP_FRAME := &"frame"          ## a picture of a set the view holds: a NAME (`alien_artifact_0`) or the number of the picture in the set
const PROP_POSE := &"pose"            ## Vector2i(cell, propeller phase): which of the sub's drawings (`SubTuning`)
const PROP_FADE := &"fade"            ## float 0..1: how opaque the actor is
const PROP_EXTENT := &"extent"        ## int: how far a stretched thing reaches (the y of the bottom of the crane's chain)

const ALL: Array[StringName] = [PROP_PICTURE, PROP_MIRROR, PROP_POSITION, PROP_VISIBLE, PROP_CLIP, PROP_TEXT, PROP_REVEAL, PROP_FRAME, PROP_POSE, PROP_FADE, PROP_EXTENT]

## The name the view knows the actor by (`hull`, `radar`, `crew_3`).
@export var actor: StringName = &""
## One of the words above.
@export var property: StringName = &""
## The moments of the keys, in ticks, in increasing order.
@export var times: PackedFloat64Array = PackedFloat64Array()
## One value per moment.
@export var values: Array = []
## false: the value jumps at each key (a picture swap, a step of the original's redraw). true: it moves smoothly
## from one key to the next (a fade, the typing of a text).
@export var smooth: bool = false


## Short constructor for tracks made in code (the importer writes them into `.tres` files instead).
static func from_keys(for_actor: StringName, for_property: StringName, keys: Array, is_smooth: bool = false) -> CutsceneTrack:
	var track := CutsceneTrack.new()
	track.actor = for_actor
	track.property = for_property
	track.smooth = is_smooth
	for key: Array in keys:
		track.times.append(key[0])
		track.values.append(key[1])
	return track


## What is wrong with this track, or "" when it is fine (the tests ask every timeline of the game).
func problem() -> String:
	if actor == &"":
		return "no actor"
	if not ALL.has(property):
		return "%s: unknown property '%s'" % [actor, property]
	if times.size() != values.size():
		return "%s %s: %d moments for %d values" % [actor, property, times.size(), values.size()]
	if times.is_empty():
		return "%s %s: no keys" % [actor, property]
	for i in range(1, times.size()):
		if times[i] < times[i - 1]:
			return "%s %s: moment %d is before the one before it" % [actor, property, i]
	return ""
