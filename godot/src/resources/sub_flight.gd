class_name SubFlight
extends Resource
## The flight of the sub as numbers, and the rule that turns them into a `CutsceneTimeline` for the place where the sub happens to be: a kind of timeline FILE. A scene's one-shot `timelines` may name such a file as well as a timeline
## (`StoryScene.timeline_named` answers a timeline for either, given the `ScenePlace` the director hands in). The legacy pack's is `data/story/voyager_flight.tres`, written by the importer (`tools/import/step_story.py`; the numbers were read from
## the decompiled loops of `VoyagerClosingSequence`, CLOSING.C 0x41c5f2, DESIGN section 3).
##
## Teaches: why one cutscene cannot always be one fixed timeline. The Voyager finale starts wherever the sub is when the creature sets the last flag, facing whichever way it faces, so the length of the flight depends on three numbers that are
## only known then (x, y and the sub's cell). What IS fixed is how the original moves: this many steps up, this many pixels a step, until the helicopter has left the screen. `timeline()` runs those loops once and writes down what they did; the
## result is the same kind of data as every other cutscene and is played by the same `AnimationPlayer` machinery. The flight's last step is a MARK of the timeline (`END_MARK`) with the cue `end_cue` at it: Enter during the flight goes on to it
## (`TimelineSegment.advance`), whichever way the scene goes on after the flight.
##
## The original, in steps of 6 ticks (0.082 s): the sub rises 4 px a step for 18 steps; its drawing turns step by step
## (`turn_table`) until it shows cell 2; the flash sound and the helicopter appear in three pictures (12 ticks each); the
## surge sound, 15 steps of 8 px up with the rotor spinning; then 8 px to the left per step until the helicopter has left
## the playfield.

## The mark at the flight's last step (a hold Enter cuts short: the moment the flight is over).
const END_MARK := &"flight_over"

## One step of the original's loops, in ticks.
@export var step_ticks: float = 6.0
@export var rise_steps: int = 0
@export var rise_pixels: int = 0
## `VoyagerClosingTurnTable` (0x441579): the cell the sub shows next while it turns, indexed by the current cell.
@export var turn_table: PackedInt32Array = PackedInt32Array()
@export var turn_done_cell: int = 0
## The three pictures of the change into a helicopter, and how many steps each one stays.
@export var change_pictures: Array[StringName] = []
@export var change_picture_steps: int = 0
@export var flash_sound: StringName = &""
@export var surge_sound: StringName = &""
@export var surge_steps: int = 0
@export var surge_pixels: int = 0
@export var fly_pixels: int = 0
## The helicopter has left when its x is this far left (window pixels).
@export var fly_until_x: int = 0
@export var body_picture: StringName = &""
@export var rotor_pictures: Array[StringName] = []
## What happens at the last step: the event cue (a verb of `StoryVerbs`, as a scene's cues are) the flight ends with, at the mark `END_MARK`. The legacy pack's is `messages`: the surface ship's pages follow.
@export var end_cue: StringName = &"end"
## Ticks the animation goes on after the last step (our own: what follows begins at the last step, this is only a margin).
@export var margin_ticks: float = 0.0
@export_multiline var provenance: String = ""


## The flight of a sub that is at window position (`start_x`, `start_y`) showing cell `start_cell` when the finale begins.
## Cues: the two sounds, and the event `end_cue` at the last step, which is the mark `END_MARK`.
func timeline(start_x: int, start_y: int, start_cell: int) -> CutsceneTimeline:
	var at := Vector2(start_x, start_y)
	var cell := clampi(start_cell, 0, maxi(turn_table.size() - 1, 0))
	var phase := 0
	var t := 0.0
	var sub_position: Array = []
	var sub_pose: Array = []
	var body_position: Array = []
	var body_picture_keys: Array = []
	var rotor_position: Array = []
	var rotor_picture_keys: Array = []
	var sub_visible: Array = [[0.0, true]]
	var body_visible: Array = [[0.0, false]]
	var rotor_visible: Array = [[0.0, false]]

	# 1. the sub rises, the propeller turns on every step
	for i in rise_steps:
		at.y -= rise_pixels
		_sub_key(t, at, cell, phase, sub_position, sub_pose)
		phase ^= 1
		t += step_ticks
	# 2. it turns until it shows the cell it ends in
	while cell != turn_done_cell:
		cell = turn_table[cell]
		_sub_key(t, at, cell, phase, sub_position, sub_pose)
		phase ^= 1
		t += step_ticks
	# 3. the change into a helicopter: three pictures, with the flash sound
	var flash_at := t
	sub_visible.append([t, false])
	body_visible.append([t, true])
	for picture in change_pictures:
		body_position.append([t, at])
		body_picture_keys.append([t, picture])
		t += change_picture_steps * step_ticks
	# 4. the surge: the second sound, straight up with the rotor turning, then off to the left
	var surge_at := t
	body_picture_keys.append([t, body_picture])
	rotor_visible.append([t, true])
	var fly_steps := 0
	var x := at.x
	while x > fly_until_x:
		x -= fly_pixels
		fly_steps += 1
	for i in surge_steps + fly_steps:
		if i < surge_steps:
			at.y -= surge_pixels
		else:
			at.x -= fly_pixels
		body_position.append([t, at])
		rotor_position.append([t, at])
		rotor_picture_keys.append([t, rotor_pictures[i % rotor_pictures.size()]])
		t += step_ticks

	var result := CutsceneTimeline.made_in_code(t + margin_ticks,
			"Run from a SubFlight (the original's loop counts, tools/import/step_story.py) for one starting place.")
	result.track(&"sub", CutsceneTrack.PROP_POSITION, sub_position)
	result.track(&"sub", CutsceneTrack.PROP_POSE, sub_pose)
	result.track(&"sub", CutsceneTrack.PROP_VISIBLE, sub_visible)
	result.track(&"helicopter", CutsceneTrack.PROP_POSITION, body_position)
	result.track(&"helicopter", CutsceneTrack.PROP_PICTURE, body_picture_keys)
	result.track(&"helicopter", CutsceneTrack.PROP_VISIBLE, body_visible)
	result.track(&"rotor", CutsceneTrack.PROP_POSITION, rotor_position)
	result.track(&"rotor", CutsceneTrack.PROP_PICTURE, rotor_picture_keys)
	result.track(&"rotor", CutsceneTrack.PROP_VISIBLE, rotor_visible)
	result.cue(flash_at, CutsceneCue.SOUND, flash_sound)
	result.cue(surge_at, CutsceneCue.SOUND, surge_sound)
	result.cue(t, CutsceneCue.EVENT, end_cue)
	result.marks[END_MARK] = t
	return result


## What is wrong with the flight, one sentence each that goes on after "the flight 'x'" and says what the player gets instead; empty when it is fine. A flight that would never end (a turn table that does not lead every cell to `turn_done_cell`,
## a helicopter that does not move left) or has nothing to draw (no rotor pictures, a step of no time) is not made: `StoryScene.timeline_named` answers null for it.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if step_ticks <= 0.0:
		found.append("has steps of %s ticks: it is not played" % step_ticks)
	if fly_pixels <= 0:
		found.append("moves the helicopter %d pixels a step to the left, so it never leaves: it is not played" % fly_pixels)
	if rotor_pictures.is_empty():
		found.append("has no rotor pictures: it is not played")
	if change_pictures.is_empty():
		found.append("has no pictures of the change into a helicopter: it is not played")
	if turn_table.is_empty():
		found.append("has no turn table: it is not played")
	for start in turn_table.size():
		if _turn_steps(start) < 0:
			found.append("has a turn table that does not lead cell %d to cell %d: it is not played" % [start, turn_done_cell])
			break
	return found


## Records the sub's position and drawing (cell and propeller phase) at tick `t`.
func _sub_key(t: float, at: Vector2, cell: int, phase: int, positions: Array, poses: Array) -> void:
	positions.append([t, at])
	poses.append([t, Vector2i(cell, phase)])


## How many steps the turn takes from cell `start`, -1 when the table never leads it to `turn_done_cell`.
func _turn_steps(start: int) -> int:
	var cell := start
	var steps := 0
	while cell != turn_done_cell:
		if cell < 0 or cell >= turn_table.size() or steps > turn_table.size():
			return -1
		cell = turn_table[cell]
		steps += 1
	return steps
