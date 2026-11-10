class_name CreatureRig
extends Node2D
## The base of the two "rigs" of the creatures skin: a node that draws ONE creature in its own way, in place of the original's flat
## picture, from nothing but the skin API (`SimView.CreatureState`, `SimView.Motion`, the events). `RainbowFishRig` draws its fish with an
## `AnimationTree`, `PufferRig3D` draws its puffer fish as a 3D model in a `SubViewport`; what they have in common is here: where the
## creature is, when it is drawn, and how big its picture is.
##
## Teaches:
##  * a small base class that the skin's presenter talks to, so it needs no `if species == ...` anywhere (a rig is something with
##    `show_picture`, `show_mirror`, `hit_by_ink`, `follow`, `show_between_ticks` - the skin API's events, one method each)
##  * the footprint rule of a skin: the rules test the creature's HIT RECTANGLE, which lies inside its original picture (`Rect2(place,
##    picture size)`), so a rig draws inside that rectangle (`drawn_rect`) and the picture matches what the rules test, however it is made
##  * drawing between two ticks with `SimView.Motion.at(fraction)`, and choosing to hop instead of glide (`GLIDE_LIMIT`)
##
## The node's `position` is the top-left corner of the creature's picture in playfield pixels, as everywhere in the skin API; the rig's
## children are drawn relative to that corner (`picture_size` / 2 is the centre of the picture).

## A step longer than this is drawn as a hop (the original look does the same, `Foe.JUMP_LIMIT`; here it is the skin's own choice).
const GLIDE_LIMIT := 24.0

## The creature's number in its sector (`CreatureState.index`).
var index := 0
## The creature pictures of the zone, which say how big each picture is (and give the original texture of it, if a rig wants it).
var frames: SpriteFrames
## The zone of the sector (the slots of the pictures are the zone's: `CreatureSpecies`).
var zone := -1
## The creature's picture now (a slot in `frames`), and whether it is mirrored.
var picture := -1
var mirrored := false

var _motion := SimView.Motion.new()
var _glides := true


## Builds the rig for `creature` (the node must be in the tree already) and shows it as it is now.
func setup(creature: SimView.CreatureState, zone_frames: SpriteFrames, zone_index: int) -> void:
	index = creature.index
	frames = zone_frames
	zone = zone_index
	_build()
	follow(creature)
	_motion = SimView.Motion.new(creature.motion.current, creature.motion.current)    # (the first sight of it: no glide from nowhere)
	mirrored = creature.mirrored
	_set_mirror(mirrored, false)
	show_picture(creature.picture)
	show_between_ticks(1.0)


# --- what the presenter tells the rig (the skin API's events) ---------------------------------------

## `creature_picture_changed`.
func show_picture(new_picture: int) -> void:
	picture = new_picture
	_set_picture(new_picture)


## `creature_mirror_changed`: it turned round.
func show_mirror(new_mirrored: bool) -> void:
	if new_mirrored != mirrored:
		mirrored = new_mirrored
		_set_mirror(mirrored, true)


## `creature_visibility_changed`: drawn (on the shown screen, not hidden), or not any more.
func show_visible(shown: bool) -> void:
	visible = shown
	_on_visibility_changed()


## `creature_hit_by_ink`: a pellet reached it.
func hit_by_ink() -> void:
	pass


## Called after every tick with the creature's state: where it is going, and whether it is drawn (on the shown screen, not hidden).
func follow(creature: SimView.CreatureState) -> void:
	_motion = creature.motion
	var step := creature.motion.previous.distance_to(creature.motion.current)
	_glides = not creature.jumped and creature.was_hidden == creature.hidden and step <= GLIDE_LIMIT
	show_visible(creature.shown)
	_on_followed(creature)


## Called once per drawn frame: the creature is `fraction` (0..1) of the way into the tick, from where it was to where it is.
func show_between_ticks(fraction: float) -> void:
	position = _motion.at(fraction) if _glides else _motion.current


## Does this rig draw the creature NOW? False for a picture it leaves to the original (the ink cloud, say); the presenter then shows the
## original's picture instead.
func is_drawing() -> bool:
	return true


## The rectangle of the creature's picture where it is drawn now (playfield pixels): the footprint the rig stays in.
func drawn_rect() -> Rect2:
	return Rect2(position, picture_size(picture))


## How big the picture `slot` is.
func picture_size(slot: int) -> Vector2:
	if frames == null or slot < 0 or slot >= frames.get_frame_count(&"all"):
		return Vector2.ZERO
	return frames.get_frame_texture(&"all", slot).get_size()


# --- for the kinds of rig to fill in ----------------------------------------------------------------

## Makes the nodes (the rig is in the tree).
func _build() -> void:
	pass


func _set_picture(_new_picture: int) -> void:
	pass


## `animate` is false for the first look at the creature (no turn to show).
func _set_mirror(_new_mirrored: bool, _animate: bool) -> void:
	pass


func _on_visibility_changed() -> void:
	pass


func _on_followed(_creature: SimView.CreatureState) -> void:
	pass
