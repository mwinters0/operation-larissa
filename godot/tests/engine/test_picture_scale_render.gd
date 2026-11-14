class_name TestPictureScaleRender
extends GdUnitTestSuite
## Teaches: that a run at picture scale 4 puts the same picture on the screen as a run at scale 1, from four times the pixels. The window draws the 2D scene at its own resolution (`stretch/mode="canvas_items"`), which a viewport with a `canvas_transform` of 4 does
## too: the same nodes, the same game units, the same pictures at four times the size (`HiresShelf`: every picture of the second pack is the first's, every pixel a 4 x 4 block). Each consumer that reaches the renderer another way than asking the texture to draw
## is on the stage (the presenter's two tile layers, a panel with the style box of a theme, a tiled `TextureRect`), beside the sprites; where the pictures are flat blocks (a stretched nine-patch) probes say what the corners and the middle are. It reads pixels back, so it
## runs in a window (WINDOWED in `tools/run_tests.sh`; the dummy renderer of `--headless` draws nothing).

const SKIP := "needs a real renderer (run it in a window)"
const UNITS := Vector2i(192, 128)
## Where each consumer is, in game units.
const BACKGROUND_AT := Vector2i(0, 0)
const BACKGROUND_SIZE := Vector2i(64, 48)
const FRAME_AT := Vector2i(72, 0)
const TILED_AT := Vector2i(112, 0)
const TILED_SIZE := Vector2i(60, 30)
const TILES_AT := Vector2i(0, 56)
const PANEL_AT := Vector2i(104, 40)
const PANEL_SIZE := Vector2i(80, 48)

var _shelf: HiresShelf
var _viewport: SubViewport


func before() -> void:
	GameState.reset()
	_shelf = HiresShelf.new()


func after() -> void:
	_shelf.remove()
	GameState.reset()


func after_test() -> void:
	if _viewport != null:
		_viewport.free()
		_viewport = null
	_shelf.plain.mount()


## The stage: every consumer on a viewport of `UNITS` game units drawn at `factor` pixels to the unit.
func _stage(factor: int) -> void:
	_viewport = SubViewport.new()
	_viewport.size = UNITS * factor
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	add_child(_viewport)
	_viewport.canvas_transform = Transform2D(0.0, Vector2.ONE * factor, 0.0, Vector2.ZERO)               # (what the window's stretch does to a 2D scene; the viewport has its canvas once it is in the tree)

	var background := Sprite2D.new()
	background.texture = Assets.picture_by_key(HiresShelf.BACKGROUNDS[0])
	background.centered = false
	background.region_enabled = true
	background.region_rect = Rect2(Vector2(BACKGROUND_SIZE), Vector2(BACKGROUND_SIZE))                       # (a piece in the middle of it: the source rectangle is in game units)
	background.position = Vector2(BACKGROUND_AT)
	_viewport.add_child(background)

	var frames := Catalog.foes_frames(0)
	var frame := AnimatedSprite2D.new()
	frame.sprite_frames = frames
	frame.animation = &"all"
	frame.frame = 3
	frame.centered = false
	frame.position = Vector2(FRAME_AT)
	_viewport.add_child(frame)

	var tiled := TextureRect.new()
	tiled.texture = Assets.picture_by_key(HiresShelf.NINE_KEY)
	tiled.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tiled.stretch_mode = TextureRect.STRETCH_TILE
	tiled.size = Vector2(TILED_SIZE)
	tiled.position = Vector2(TILED_AT)
	_viewport.add_child(tiled)

	var presenter := (load("res://src/gameplay/original_presenter.tscn") as PackedScene).instantiate() as OriginalPresenter
	presenter.position = Vector2(TILES_AT)
	_viewport.add_child(presenter)                                                                        # (the game's own layers, dressed by the game's own builder)
	var atlas := Catalog.tileset().get_source(Catalog.zone(0).tile_source_id) as TileSetAtlasSource
	for column in 6:
		presenter.walls.set_cell(Vector2i(column, 0), Catalog.zone(0).tile_source_id, Vector2i(column, 1))
		presenter.walls.set_cell(Vector2i(column, 1), Catalog.zone(0).tile_source_id, Vector2i(column, 2))
	assert_bool(atlas.has_tile(Vector2i(5, 2))).override_failure_message("dev's zone atlas has the tiles the stage shows").is_true()
	for column in 3:
		presenter.currents.set_cell(Vector2i(column, 2), OriginalPresenter.CURRENTS_SOURCE_ID, Vector2i(column, 1))
	presenter.currents.visible = true

	var data := SkinTheme.new()
	data.styles["panel"] = {"picture": HiresShelf.NINE_KEY, "slice": Vector4i(4, 4, 4, 4)}
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", ThemeBuilder.derive(data, &"zz_skin").get_stylebox("panel", "Panel"))
	panel.position = Vector2(PANEL_AT)
	panel.size = Vector2(PANEL_SIZE)
	_viewport.add_child(panel)


func _draw_frames() -> Image:
	for i in 5:
		await get_tree().process_frame
	RenderingServer.force_draw()
	await get_tree().process_frame
	return _viewport.get_texture().get_image()


## The pixels of the game-unit rectangle `at`, `size` of `image`, which is drawn at `factor` pixels to the unit.
static func _region(image: Image, at: Vector2i, size: Vector2i, factor: int) -> PackedByteArray:
	return image.get_region(Rect2i(at * factor, size * factor)).get_data()


## The same region of the image drawn at scale 1, every pixel made `factor` x `factor` (what a picture four times larger is, drawn as it is).
static func _enlarged(image: Image, at: Vector2i, size: Vector2i, factor: int) -> PackedByteArray:
	var piece := image.get_region(Rect2i(at, size))
	piece.resize(size.x * factor, size.y * factor, Image.INTERPOLATE_NEAREST)
	return piece.get_data()


func _distinct_colors(image: Image, at: Vector2i, size: Vector2i, factor: int) -> int:
	var seen := {}
	var piece := image.get_region(Rect2i(at * factor, size * factor))
	for y in piece.get_height():
		for x in piece.get_width():
			seen[piece.get_pixel(x, y)] = true
	return seen.size()


func test_a_run_at_scale_4_draws_the_pictures_of_a_run_at_scale_1_from_four_times_the_pixels(do_skip := DisplayServer.get_name() == "headless", skip_reason := SKIP) -> void:
	_shelf.mount_plain()
	assert_int(Packs.picture_scale()).is_equal(1)
	_stage(1)
	var one := await _draw_frames()
	_viewport.free()
	_shelf.mount_hires()
	assert_int(Packs.picture_scale()).is_equal(HiresShelf.SCALE)
	_stage(HiresShelf.SCALE)
	var four := await _draw_frames()
	assert_that(four.get_size()).is_equal(one.get_size() * HiresShelf.SCALE)
	var f := HiresShelf.SCALE
	var consumers := {
		"a sprite's region of a background": [BACKGROUND_AT, BACKGROUND_SIZE],
		"an animated sprite's frame": [FRAME_AT, Vector2i(24, 24)],
		"a tiled texture rect": [TILED_AT, TILED_SIZE],
		"the presenter's tile layers (the walls and the currents)": [TILES_AT, Vector2i(6 * 16, 3 * 16)],
	}
	for what: String in consumers:
		var at: Vector2i = consumers[what][0]
		var size: Vector2i = consumers[what][1]
		assert_array(_region(four, at, size, f)).override_failure_message("%s is not the picture of scale 1 at four times the pixels" % what).is_equal(_enlarged(one, at, size, f))
		assert_int(_distinct_colors(one, at, size, 1)).override_failure_message("%s draws something" % what).is_greater(1)


func test_a_nine_patch_of_scale_4_has_the_corners_and_the_middle_of_the_one_of_scale_1(do_skip := DisplayServer.get_name() == "headless", skip_reason := SKIP) -> void:
	_shelf.mount_hires()
	_stage(HiresShelf.SCALE)
	var four := await _draw_frames()
	_viewport.free()
	_shelf.mount_plain()
	_stage(1)
	var one := await _draw_frames()
	var slice := HiresShelf.NINE_SLICE
	for image_and_factor: Array in [[one, 1], [four, HiresShelf.SCALE]]:
		var image: Image = image_and_factor[0]
		var factor: int = image_and_factor[1]
		# a point of the panel, in game units from its top left, and the block of the picture it must show (the corners 4 units wide, the rest stretched)
		var width := PANEL_SIZE.x
		var height := PANEL_SIZE.y
		var probes := {
			Vector2i(1, 1): Vector2i(0, 0), Vector2i(slice - 1, slice - 1): Vector2i(0, 0),
			Vector2i(width - 2, 1): Vector2i(2, 0), Vector2i(width - slice, slice - 1): Vector2i(2, 0),
			Vector2i(1, height - 2): Vector2i(0, 2), Vector2i(slice - 1, height - slice): Vector2i(0, 2),
			Vector2i(width - 2, height - 2): Vector2i(2, 2), Vector2i(width - slice, height - slice): Vector2i(2, 2),
			Vector2i(width / 2, 1): Vector2i(1, 0), Vector2i(width / 2, height - 2): Vector2i(1, 2),
			Vector2i(1, height / 2): Vector2i(0, 1), Vector2i(width - 2, height / 2): Vector2i(2, 1),
			Vector2i(width / 2, height / 2): Vector2i(1, 1), Vector2i(slice + 10, slice + 10): Vector2i(1, 1),
		}
		for probe: Vector2i in probes:
			var block: Vector2i = probes[probe]
			var seen := image.get_pixelv((PANEL_AT + probe) * factor + Vector2i(factor / 2, factor / 2))
			assert_that(seen).override_failure_message("the panel at factor %d, %s units in: the block (%d, %d) of the picture" % [factor, probe, block.x, block.y]).is_equal(HiresShelf.nine_color(block.x, block.y))
