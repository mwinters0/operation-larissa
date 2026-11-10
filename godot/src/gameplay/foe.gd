class_name Foe
extends Node2D
## One creature on the playfield as it is drawn: a picture, and a `FoeModel` that decides what it does. It is a plain `Node2D`: the
## contacts with the sub and with the ink are rectangle arithmetic in `SimWorld.check_contacts`, so there is no physics area here.
##
## Teaches: a node that only shows a model (`FoeModel` holds the script, the pictures' hit rectangles and who touches whom). The
## presenter tells this node what changed: a new picture, a mirror flip or a change of visibility arrive as the events of the rules
## (`show_picture`, `show_mirror`, `show_visible`), the place is read after each tick (`follow`), and `show_between_ticks` slides the
## picture between two places every frame. And a presentation CHOICE that is not a rule: whether a step is drawn gliding or as a hop
## (below).
##
## All creatures of a sector exist from the moment the sector is loaded (so that a script can wake a creature on a screen you are
## not looking at), but only those whose screen is shown are visible.

## A MOVE_REL step is drawn gliding (TickSmoothing); these are drawn at the new place at once instead:
## a SET_POS or the end of an interrupt (`FoeVM.jumped`), showing or hiding, a step longer than JUMP_LIMIT, and
## a picture listed in HOPPING_PICTURES. This is how the ORIGINAL look draws them, so it lives here and not in `FoeModel`: the
## rules only say where the creature is now and where it was; a skin may animate a step as it likes.
const JUMP_LIMIT := 24.0
## Zone -> pictures (`frame` names of that zone) that are never drawn gliding. Zone 0's `jellyfish_tentacle` (picture 44,
## `foe_z0_044`) is the jellyfish's loose tentacle tip: a creature of its own (`foe4_start` in sectors 0, 2 and 16) that hops from tentacle to tentacle in
## time with the bell's pictures, with MOVE_REL steps of -28, +8, +32 and -12 px. Gliding, it visibly slid along the
## 8 px step. A survey of every creature of every sector (moves of an unchanged picture, with no move on the
## tick before or after) found no other such creature, so this is a list, not a rule.
const HOPPING_PICTURES := {0: [&"jellyfish_tentacle"]}

var model: FoeModel
## The creature's script machine (the model's), for the tests and tools that look at the creature.
var vm: FoeVM
## Draw the hit rectangle (the sector viewer's collision toggle), from the model's table of rectangles.
var debug_draw: bool = false:
	set(value):
		debug_draw = value
		queue_redraw()

var _frames: SpriteFrames
var _previous_position: Vector2 = Vector2.ZERO
var _hopping_pictures: Array = []
var _seen_ticks: int = 0

@onready var sprite: AnimatedSprite2D = %Sprite


## Connects this node to its model. Call before adding the node to the tree. `zone`: whose pictures `frames` are.
func setup(foe_model: FoeModel, frames: SpriteFrames, zone: int = -1) -> void:
	model = foe_model
	vm = foe_model.vm
	_frames = frames
	_hopping_pictures = []
	for picture_name: StringName in HOPPING_PICTURES.get(zone, []):
		_hopping_pictures.append(NameRegistry.original().index_of(&"frame", picture_name, zone))
	position = _playfield_position()
	_previous_position = position
	_seen_ticks = -1                                   # (the first `follow` decides "glide or hop" from the model, as after any tick)
	visible = false                                    # (the rules announce the first sight of it, see `show_visible`)
	if is_node_ready():
		_adopt_frames()


func _ready() -> void:
	if model != null:
		_adopt_frames()


func _adopt_frames() -> void:
	sprite.sprite_frames = _frames
	sprite.animation = &"all"
	sprite.pause()
	sync()


# --- what the presenter tells this node -------------------------------------------------------------

## Another picture (`SimWorld.creature_picture_changed`): slot `picture` of the zone's creature pictures.
func show_picture(picture: int) -> void:
	if sprite != null and picture < _frames.get_frame_count(&"all"):
		sprite.frame = picture
	if debug_draw:
		queue_redraw()


## Mirrored, or not any more (`SimWorld.creature_mirror_changed`).
func show_mirror(mirrored: bool) -> void:
	if sprite != null:
		sprite.flip_h = mirrored
	if debug_draw:
		queue_redraw()


## Drawn, or not drawn any more (`SimWorld.creature_visibility_changed`): on the shown screen and not hidden.
func show_visible(shown: bool) -> void:
	visible = shown
	if debug_draw:
		queue_redraw()


## Takes the creature's place from its script and, if the script ran since the last time, decides whether the picture glides to its
## new place or jumps. Called after every tick (`SimWorld.ticked`).
func follow() -> void:
	if model == null:
		return
	position = _playfield_position()
	if model.ticks_run != _seen_ticks:
		_seen_ticks = model.ticks_run
		var came_from := Vector2(model.previous_pos) - Sub.PLAYFIELD_ORIGIN
		var glides := not vm.jumped and model.was_hidden == vm.hidden and not _hopping_pictures.has(vm.frame) \
				and came_from.distance_squared_to(position) <= JUMP_LIMIT * JUMP_LIMIT
		_previous_position = came_from if glides else position
	if debug_draw:
		queue_redraw()


## Called once per drawn frame (`SectorPresenter.show_between_ticks`): `fraction` (0..1) of the way into the tick, the picture is
## that far from its previous place to its current one.
func show_between_ticks(fraction: float) -> void:
	if sprite != null:
		sprite.position = TickSmoothing.offset(_previous_position, position, fraction)


## Shows everything the model says now: picture, mirror, visibility and place. The first sight of a creature, and for tests and
## tools that changed it by hand.
func sync() -> void:
	if model == null or sprite == null:
		return
	show_picture(vm.frame)
	show_mirror(vm.flip)
	show_visible(model.is_shown())
	follow()


## Tells the model which screen is shown and draws it. (The world does this for all creatures; tests do it for one.)
func refresh(on_screen: bool) -> void:
	model.refresh(on_screen)
	sync()


## True if the picture is being drawn between its previous and its current place this tick (TickSmoothing).
func is_gliding() -> bool:
	return _previous_position != position


## The script keeps the picture's top-left corner in WINDOW pixels (the original draws
## everything in one window coordinate system, the sub's SubX / SubY too). Our node lives
## in the playfield, which starts at window (16, 32).
func _playfield_position() -> Vector2:
	return Vector2(vm.x, vm.y) - Sub.PLAYFIELD_ORIGIN


## The hit rectangle in playfield coordinates (what the debug drawing uses): the model's rectangle in window pixels, moved to the
## playfield.
func hit_rect_world() -> Rect2:
	var rect := Rect2(model.hit_rect_window())
	rect.position -= Sub.PLAYFIELD_ORIGIN
	return rect


func _draw() -> void:
	if debug_draw and model.is_touchable() and vm.frame < model.meta.count():
		draw_rect(Rect2(model.meta.hit_rect(vm.frame, vm.flip)), Color(1.0, 0.2, 0.2, 0.9), false)
