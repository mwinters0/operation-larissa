class_name Sub
extends Node2D
## The player's submarine as the playfield draws it: the sprites for the cell, the propeller, the blink, the bubbles and the
## beacon, and the dissolve when a tank is lost. It decides nothing: where the sub is, how fast it flies and whether it is hurt
## are the fields of its `SubModel` (`src/rules/sub_model.gd`), which the world's `SimWorld` steps once per game tick. It is a plain
## `Node2D`: the walls are a tile scan and the contacts are rectangle arithmetic in the rules, so there is no physics body here.
##
## Teaches: a node that only shows a model. `refresh()` copies the model's state to the nodes (position, which picture, blink,
## bubbles, the beacon) and runs after every tick and every frame; `show_between_ticks(fraction)` shifts the picture between two
## ticks so the sub glides although the rules move it 12.17 times a second (TickSmoothing). The node never moves the sub: when the
## supply station drives it in or out, or when a tank is lost, the RULES move it and stop it (`SimWorld`); the dissolve is told
## where it is (`show_dissolve`) and only draws that.
##
## Coordinates: the node's origin is the CENTRE of the 96 x 54 picture and its `position` is in playfield pixels (0..607, 0..287),
## so the parent must be the playfield; it follows `model.position`. The original game stores the picture's top-left corner in
## *window* pixels (SubX, SubY), see `SubModel.place_original` and `SubModel.original_position`.

## The playfield starts at (16, 32) in the original's window pixels.
const PLAYFIELD_ORIGIN := SubModel.PLAYFIELD_ORIGIN
## Offset from the picture's top-left corner (playfield pixels) to its centre.
const PICTURE_CENTER := SubModel.PICTURE_CENTER
const LIGHT_PICTURE := 8

## Draw the wall box (cyan) and the hurt rectangle (red) of the current frame, from the model's tuning (the rectangles the rules use).
@export var debug_draw: bool = false:
	set(value):
		debug_draw = value
		queue_redraw()

## What this node shows, handed over by its owner with `bind` (the world's `SimWorld.sub`, the sub sandbox's own); until then a
## stand-in on the run's sub numbers.
var model := SubModel.new(GameState.tuning.sub)

## True from the end of the dissolve until the sub is placed again: the pictures are hidden.
var _dissolved: bool = false

@onready var visual: Node2D = %Visual
@onready var sprite: AnimatedSprite2D = %Sprite
@onready var bubbles: AnimatedSprite2D = %Bubbles
@onready var light: AnimatedSprite2D = %Light


## Shows `new_model` from now on.
func bind(new_model: SubModel) -> void:
	if model.placed.is_connected(_on_placed):
		model.placed.disconnect(_on_placed)
	model = new_model
	model.placed.connect(_on_placed)
	_dissolved = false
	if is_node_ready():
		refresh()


func _ready() -> void:
	var frames := Catalog.sub_frames()
	sprite.sprite_frames = frames
	sprite.animation = &"all"
	sprite.pause()
	bubbles.sprite_frames = frames
	bubbles.animation = &"all"
	bubbles.pause()
	light.sprite_frames = frames
	light.animation = &"all"
	light.frame = LIGHT_PICTURE
	light.pause()
	if not model.placed.is_connected(_on_placed):
		model.placed.connect(_on_placed)
	refresh()


## Called once per drawn frame (`SectorPresenter.show_between_ticks`): shifts the picture between two ticks, `fraction` (0..1) of the
## way into the current one. The model only changes in the rules' ticks (also while the station drives the sub), and `refresh` has
## copied it after each of them, so there is nothing to read again here.
func show_between_ticks(fraction: float) -> void:
	visual.position = TickSmoothing.offset(model.previous_position, model.position, fraction)


func _on_placed() -> void:
	_dissolved = false


# --- the tank-loss dissolve -------------------------------------------------------

const DISSOLVE_SHADER := preload("res://src/gameplay/sub_dissolve.gdshader")

## The sub dissolves away where it floats (`RedrawFrameAfterTankLoss` 0x418bcb -> `dissolve` 0x414f81): the sprites are replaced by
## what is behind them, 2 x 2 pixel blocks at a time in the order of `DissolvePattern`, 16 passes and a closing copy. The rules
## count how long that takes (`SimWorld.dissolve_length()`) and stop the sub (`controlled`); this node is told where the dissolve IS
## (`show_dissolve`), not what happened to it: the owner passes the rules' state on every event of the dissolve, on a load and when it
## is bound, so a node made in the middle of a dissolve draws what one made before it draws. The pass mask is an `Image` that the
## shader (`sub_dissolve.gdshader`) reads. `place_original` brings the sub back.

## `show_dissolve`'s "no dissolve runs".
const NO_DISSOLVE := -1


## Shows the dissolve as the rules hold it: `passes_done` of the 16 passes and the closing copy (0..17) of a dissolve that runs, or
## `NO_DISSOLVE`, and then `gone`: the dissolve has run out and nothing of the sub is drawn until it is placed again.
func show_dissolve(passes_done: int, gone: bool = false) -> void:
	if passes_done == NO_DISSOLVE:
		_set_dissolve_material(null)
		_dissolved = gone
		refresh()
		return
	_dissolved = false
	if dissolve_material() == null:
		_set_dissolve_material(_make_dissolve_material())
	dissolve_material().set_shader_parameter("passes_done", float(passes_done))


## The material of a dissolve that runs, or null.
func dissolve_material() -> ShaderMaterial:
	return sprite.material as ShaderMaterial


## The shader set up for the place the sub stands (it does not move while it dissolves), with no pass drawn yet.
func _make_dissolve_material() -> ShaderMaterial:
	refresh()
	visual.position = Vector2.ZERO
	var at := model.original_position()
	var box := DissolvePattern.box_for(at.x, at.y)
	var material := ShaderMaterial.new()
	material.shader = DISSOLVE_SHADER
	material.set_shader_parameter("pass_mask", ImageTexture.create_from_image(DissolvePattern.make_mask(box.size.x, box.size.y)))
	material.set_shader_parameter("box_origin", global_position - PICTURE_CENTER + Vector2(box.position - at))
	material.set_shader_parameter("box_size", Vector2(box.size))
	material.set_shader_parameter("passes_done", 0.0)
	return material


## The dissolve's `material` on the pictures, or none: a picture with no material of its own wears its parent's (`use_parent_material`: the shader a data skin puts on the `sub` layer, `SkinLayers.NODES`), and one with the dissolve's wears that alone.
func _set_dissolve_material(material: ShaderMaterial) -> void:
	for picture: AnimatedSprite2D in [sprite, bubbles, light]:
		picture.material = material
		picture.use_parent_material = material == null


# --- placing ---------------------------------------------------------------------

## Puts the sub where the original would (`SubModel.place_original`) and shows it there at once.
func place_original(sub_x: int, sub_y: int, new_cell: int = 6) -> void:
	model.place_original(sub_x, sub_y, new_cell)
	snap_visual()
	refresh()


## Forget the previous position: after a jump the picture must not glide across the screen.
func snap_visual() -> void:
	model.snap()
	if is_node_ready():
		visual.position = Vector2.ZERO


# --- appearance ------------------------------------------------------------------

## Copies the model to the nodes: where the sub is, whether it is shown, the cell, propeller, blink, bubbles and the beacon. Cheap;
## called after every tick and every frame.
func refresh() -> void:
	if not is_node_ready():
		return
	position = model.position
	visible = model.active
	visual.visible = not _dissolved
	sprite.frame = model.tuning.picture_for(model.cell, model.propeller_phase)
	sprite.flip_h = SubTuning.is_flipped(model.cell)
	sprite.visible = model.is_picture_visible()
	var bubble := model.bubble_picture()
	bubbles.visible = bubble >= 0
	if bubble >= 0:
		bubbles.frame = bubble
		bubbles.flip_h = SubTuning.is_flipped(model.cell)
		# The bubble picture is 76 px wide; left-facing cells mirror its placement.
		bubbles.position = Vector2(model.tuning.hit_bubble_x_by_cell[model.cell], 0) - PICTURE_CENTER + Vector2(38, 27)
	# The beacon is only drawn while the sub is seen from the side (cells 0-2, 6-8), at a spot that depends on the
	# cell, not mirrored; it blinks on every other tick.
	light.visible = model.message_light and model.propeller_phase == 1 and model.tuning.light_cells.has(model.cell)
	light.position = Vector2(model.tuning.light_dx_by_cell[model.cell], model.tuning.light_dy_by_cell[model.cell]) - PICTURE_CENTER
	if debug_draw:
		queue_redraw()


func _draw() -> void:
	if not debug_draw:
		return
	draw_rect(model.tuning.wall_box_centered(), Color(0.2, 1.0, 1.0, 0.9), false)
	draw_rect(model.tuning.frame_rect_centered(model.cell), Color(1.0, 0.2, 0.2, 0.9), false)
