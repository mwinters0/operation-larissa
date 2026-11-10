class_name Cutscene
extends RefCounted
## Turns a `CutsceneTimeline` (data) into an `Animation` (what an `AnimationPlayer` plays).
##
## Teaches: what an `Animation` resource is made of, and why we build one at run time instead of drawing it in the editor.
## An animation is a list of TRACKS; each track names a node property (a "value" track: `Stage/Ship:position`) or a
## method (a "method" track: `play_sfx`) and holds KEYS (a time and a value). The editor's animation panel shows exactly
## this, and so does the animation made here, because it lives in an ordinary `AnimationPlayer`: open the game, pause it
## and look in the Remote tree. What is NOT in the animation is the choreography itself: it is in the timeline, with
## picture names instead of textures and actor names instead of node paths, so the timing does not depend on how the scene
## is built. `CutsceneCast` says which node plays which actor.

## Seconds of the original's 73 Hz timer.
const TICK := 1.0 / CutsceneTimeline.TICKS_PER_SECOND

## What the view's methods are called: the `AnimationPlayer` calls them on the cast's root (the segment).
const SOUND_METHOD := &"play_sfx"
const EVENT_METHOD := &"cue"

## The Godot property that plays each word of a track, unless the cast renames it for an actor.
const PROPERTIES := {
	CutsceneTrack.PROP_PICTURE: "texture",
	CutsceneTrack.PROP_MIRROR: "flip_h",
	CutsceneTrack.PROP_POSITION: "position",
	CutsceneTrack.PROP_VISIBLE: "visible",
	CutsceneTrack.PROP_CLIP: "region_rect",
	CutsceneTrack.PROP_TEXT: "text",
	CutsceneTrack.PROP_REVEAL: "visible_ratio",
	CutsceneTrack.PROP_FRAME: "frame",
	CutsceneTrack.PROP_FADE: "modulate:a",
	CutsceneTrack.PROP_EXTENT: "extent",
}


## Original timer ticks as seconds.
static func ticks(count: float) -> float:
	return count * TICK


## The animation for `timeline`, played by the nodes `cast` knows.
static func animation(timeline: CutsceneTimeline, cast: CutsceneCast) -> Animation:
	var result := make(timeline.length_seconds(), timeline.loop)
	for track in timeline.tracks:
		_add_track(result, track, cast)
	_add_cues(result, timeline)
	for mark: StringName in timeline.marks:
		result.add_marker(mark, CutsceneTimeline.seconds(timeline.marks[mark]))
	return result


## Builds the animation of `timeline` and puts it into `player` under `name`.
static func install_timeline(player: AnimationPlayer, name: StringName, timeline: CutsceneTimeline, cast: CutsceneCast) -> void:
	install(player, name, animation(timeline, cast))


static func _add_track(result: Animation, track: CutsceneTrack, cast: CutsceneCast) -> void:
	if not cast.has_actor(track.actor):
		push_error("Cutscene: no node plays the actor '%s'" % track.actor)
		return
	var path := String(cast.path_to(track.actor))
	if track.property == CutsceneTrack.PROP_POSE:
		# One word of the data, two properties of the sprite: which drawing, and whether it faces left.
		var frames: Array = []
		var flips: Array = []
		for i in track.times.size():
			var t := CutsceneTimeline.seconds(track.times[i])
			frames.append([t, cast.pose_frame(track.values[i])])
			var flipped := SubTuning.is_flipped((track.values[i] as Vector2i).x)
			if flips.is_empty() or flips[-1][1] != flipped:           # (the facing changes rarely: a key only when it does)
				flips.append([t, flipped])
		values(result, "%s:%s" % [path, cast.godot_property(track.actor, CutsceneTrack.PROP_FRAME, "frame")], frames, track.smooth)
		values(result, "%s:%s" % [path, cast.godot_property(track.actor, CutsceneTrack.PROP_MIRROR, "flip_h")], flips, track.smooth)
		return
	var keys: Array = []
	for i in track.times.size():
		keys.append([CutsceneTimeline.seconds(track.times[i]), _node_value(track, track.values[i], cast)])
	var property := cast.godot_property(track.actor, track.property, PROPERTIES[track.property])
	values(result, "%s:%s" % [path, property], keys, track.smooth)


## A key's value of the timeline as the value Godot sets: names become textures, texts, frame numbers, and a window position
## becomes a position inside the actor's parent.
static func _node_value(track: CutsceneTrack, value: Variant, cast: CutsceneCast) -> Variant:
	match track.property:
		CutsceneTrack.PROP_POSITION:
			return (value as Vector2) - cast.origin_of(track.actor)
		CutsceneTrack.PROP_PICTURE:
			return cast.pictures.call(StringName(value))
		CutsceneTrack.PROP_TEXT:
			return cast.texts.call(StringName(value))
		CutsceneTrack.PROP_FRAME:
			return cast.frame_number(value)
	return value


## A sound is a call of `play_sfx(name)`, an event a call of `cue(name)`, both on the cast's root.
static func _add_cues(result: Animation, timeline: CutsceneTimeline) -> void:
	# One method track per kind: a method track holds one call per moment, and a sound and an event may share a moment
	# (the third title picture comes with its sound AND starts the prompt).
	for kind in [CutsceneCue.SOUND, CutsceneCue.EVENT]:
		var track := -1
		for cue_entry in timeline.cues:
			if cue_entry.kind != kind:
				continue
			if track < 0:
				track = result.add_track(Animation.TYPE_METHOD)
				result.track_set_path(track, NodePath("."))
			var method := SOUND_METHOD if kind == CutsceneCue.SOUND else EVENT_METHOD
			result.track_insert_key(track, CutsceneTimeline.seconds(cue_entry.tick), {"method": method, "args": [cue_entry.cue_name]})


## A new animation of `length` seconds.
static func make(length: float, loop: bool = false) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return animation


## Adds a property track. `keys` is a list of [time, value] pairs. `smooth` interpolates between the keys,
## otherwise the value jumps (what a picture swap or a visibility flag needs).
static func values(animation: Animation, path: String, keys: Array, smooth: bool = false) -> int:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(path))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR if smooth else Animation.INTERPOLATION_NEAREST)
	animation.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS if smooth else Animation.UPDATE_DISCRETE)
	for key: Array in keys:
		animation.track_insert_key(track, key[0], key[1])
	return track


## Puts `animation` into the player's default library under `name`.
static func install(player: AnimationPlayer, name: StringName, animation: Animation) -> void:
	var library: AnimationLibrary
	if player.has_animation_library(&""):
		library = player.get_animation_library(&"")
	else:
		library = AnimationLibrary.new()
		player.add_animation_library(&"", library)
	if library.has_animation(name):
		library.remove_animation(name)
	library.add_animation(name, animation)
