class_name PufferRig3D
extends CreatureRig
## A puffer fish (sector 0, screens 0, 6 and 9) drawn as a lit 3D model, in the place of the original's flat picture: a `PufferModel` in
## a transparent `SubViewport`, whose picture is a `Sprite2D` in the playfield, exactly where the original picture would be.
##
##   rules say (skin API)                          the model does
##   -----------------------------------------------------------------------------------------------
##   picture swim / swell / puffed                -> how puffed up it is (0 / 0.5 / 1; it eases there)
##   `creature_mirror_changed`                    -> it turns round (the heading eases to the other side, through head-on)
##   how far it moved in the last tick            -> how fast the fins and the tail beat; a nose up or down for a climb or a dive
##   an ink picture (a pellet hit it)             -> the model is left out: the original's ink cloud is shown instead (`is_drawing`)
##
## Teaches: 3D in a 2D game (`SubViewport` + `SubViewportTexture` + `Sprite2D`). The viewport is
##   * `transparent_bg`, so only the fish is drawn and the sea behind it shows through,
##   * its own `World3D` (`own_world_3d`), so two puffer fish do not see each other's models (a `SubViewport` otherwise shares the world
##     of the window),
##   * four times the size of the picture (320 x 192 for 80 x 48), shown at a quarter scale with linear filtering: smooth edges, no
##     pixels, while the footprint stays the original picture's rectangle,
##   * put on the skin's render settings (`RenderSettings.apply_to`: a `SubViewport` does not inherit the window's), and
##   * only rendered while the creature is on the screen (`render_target_update_mode`).
## The camera is orthographic and sized so that one unit of the model is one pixel of the original picture (`Camera3D.size` is the
## height of the picture, 48). The project uses the Compatibility renderer: 3D in a `SubViewport`, lights and `transparent_bg` all work.

## How many times bigger the 3D picture is rendered than shown.
const RENDER_SCALE := 4
## The original's pictures of a puffer fish are all this big.
const PICTURE_SIZE := Vector2i(80, 48)
## How puffed up the model is for each picture (names of the registry).
const INFLATE_FOR := {"puffer_swim_0": 0.0, "puffer_swim_1": 0.0, "puffer_swell": 0.5, "puffer_puffed_0": 1.0, "puffer_puffed_1": 1.0}
## A little turned towards the viewer, so that the model shows its depth (radians).
const THREE_QUARTER := 0.32
## Pixels of a step per tick that count as "swimming hard" (the puffer's dives are 3).
const SPEED_FOR_FULL_SWIM := 3.0

var _viewport: SubViewport
var _picture: Sprite2D
var _model: PufferModel
var _inflate_for_slot := {}                    # slot -> how puffed up
var _inflate := 0.0                            # now (eases to the target of the picture)
var _inflate_target := 0.0
var _heading := THREE_QUARTER                  # now, in radians (eases to `_heading_target`)
var _heading_target := THREE_QUARTER
var _velocity := Vector2.ZERO                  # pixels per tick
var _swim := 0.0
var _time := 0.0
var _own_picture := false                      # is the current picture one of the puffer's (else the original's ink cloud is shown)


func _build() -> void:
	for picture_name: String in INFLATE_FOR:
		var slot := CreatureSpecies.slot_of(zone, picture_name)
		if slot >= 0:
			_inflate_for_slot[slot] = INFLATE_FOR[picture_name]
	_viewport = SubViewport.new()
	_viewport.name = "Viewport"
	_viewport.size = PICTURE_SIZE * RENDER_SCALE
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	SkinChoice.current().render_settings().apply_to(_viewport)
	add_child(_viewport)
	_viewport.add_child(_make_scene())
	_picture = Sprite2D.new()
	_picture.name = "Picture"
	_picture.centered = false
	_picture.texture = _viewport.get_texture()
	_picture.scale = Vector2.ONE / RENDER_SCALE
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR     # (the 3D picture is smooth, whatever the skin's filter for pixel art)
	add_child(_picture)


## The 3D world: the model, a camera that looks at it from the side, a key light from the upper left and a soft light all round.
func _make_scene() -> Node3D:
	var world := Node3D.new()
	world.name = "World"
	_model = PufferModel.new()
	_model.name = "Model"
	world.add_child(_model)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = PICTURE_SIZE.y                  # (the height of the picture in units: one unit is one pixel of the original)
	camera.position = Vector3(0.0, 0.0, 100.0)
	camera.near = 1.0
	camera.far = 300.0
	var environment := Environment.new()            # (no sky: the background is transparent; the light all round makes the shadow side readable)
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.65, 0.85)
	environment.ambient_light_energy = 0.7
	camera.environment = environment
	world.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, -30.0, 0.0)      # from the upper left, a little from the front
	light.light_energy = 1.1
	world.add_child(light)
	return world


# --- what the rules say -----------------------------------------------------------------------------

func _set_picture(new_picture: int) -> void:
	_own_picture = _inflate_for_slot.has(new_picture)
	if _own_picture:
		_inflate_target = _inflate_for_slot[new_picture]
	_update_rendering()


func _set_mirror(new_mirrored: bool, animate: bool) -> void:
	_heading_target = (PI - THREE_QUARTER) if new_mirrored else THREE_QUARTER
	if not animate:
		_heading = _heading_target


func _on_followed(creature: SimView.CreatureState) -> void:
	_velocity = creature.motion.current - creature.motion.previous


func _on_visibility_changed() -> void:
	_update_rendering()


func is_drawing() -> bool:
	return _own_picture


## The rectangle the model is drawn in: the original picture's, whatever the pose.
func drawn_rect() -> Rect2:
	return Rect2(position, Vector2(PICTURE_SIZE))


## The model is drawn (and the 3D picture renewed) only while the fish is a fish and on the screen.
func _update_rendering() -> void:
	var drawing := visible and _own_picture
	_picture.visible = drawing
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if drawing else SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
	_time += delta
	_inflate = move_toward(_inflate, _inflate_target, 2.5 * delta)
	_heading = move_toward(_heading, _heading_target, 9.0 * delta)
	_swim = move_toward(_swim, clampf(_velocity.length() / SPEED_FOR_FULL_SWIM, 0.0, 1.0), 4.0 * delta)
	if _picture.visible:
		_model.pose(_inflate, _time, _swim, _heading)
		# It bobs a little, and the nose goes up in a climb and down in a dive (a dive is +y on the screen).
		_model.position.y = sin(_time * 2.3) * 1.2
		_model.rotation.z = clampf(_velocity.y * 0.06, -0.2, 0.2) * (-1.0 if mirrored else 1.0)


# --- for the tests ------------------------------------------------------------------------------------

func viewport() -> SubViewport:
	return _viewport


func model() -> PufferModel:
	return _model


func picture_node() -> Sprite2D:
	return _picture


func heading_target() -> float:
	return _heading_target


func inflate_target() -> float:
	return _inflate_target
