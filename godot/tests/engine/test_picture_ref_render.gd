class_name TestPictureRefRender
extends GdUnitTestSuite
## Teaches: what really reaches the screen. A `PictureRef` is drawn by every consumer the game has, which ask a texture three different ways (`draw_rect_region` for sprites, tile maps and `draw_texture*`; the texture's own RID for nine-patches and style boxes), and
## this suite reads the pixels back, as `test_skin_creatures_render.gd` does, so it runs in a window (WINDOWED in `tools/run_tests.sh`; the dummy renderer of `--headless` draws nothing). Each consumer shows the same key in a cell of one viewport; the chain then changes and the SAME nodes
## are read again, with nothing rebuilt.
##   * `Sprite2D`, `AnimatedSprite2D`, `TextureRect` (stretched, and tiled, which draws the RID), `NinePatchRect`, `StyleBoxTexture` on a `Panel`, `TextureProgressBar`, a control that calls `draw_texture_rect` and `draw_texture`, a `TileMapLayer` over a `TileSetAtlasSource`,
##   * the picture is the table's, and after the chain changes it is the new chain's,
##   * a picture of a scaled pack (4x art) fills the same place as the plain one.

const CELL := 32
const COLUMNS := 4
const SKIP := "needs a real renderer (run it in a window)"

var _shelf: PicturesShelf
var _viewport: SubViewport
## cell name -> its column, row.
var _cells: Dictionary = {}
## cell name -> the node in it.
var _nodes: Dictionary = {}


func before_test() -> void:
	GameState.reset()
	_shelf = PicturesShelf.new()
	_shelf.mount_base()


func after_test() -> void:
	if _viewport != null:
		_viewport.free()                                                             # (before the chain changes back: nothing in it asks a picture of the pack that is gone)
		_viewport = null
	_shelf.remove()
	GameState.reset()


## A viewport with every consumer in a cell, all showing `key` (the tile map shows the tile sheet's second tile, GREEN).
func _stage(key: String) -> void:
	_cells = {}
	_nodes = {}
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(CELL * COLUMNS, CELL * 3)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	add_child(_viewport)
	var ref := PictureRef.of(key)
	var scale_up := Vector2.ONE * (CELL / 4.0)                                  # (the pictures are 4 x 4)

	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = ref
	sprite.scale = scale_up
	_place(sprite, "sprite")

	var frames := SpriteFrames.new()
	frames.add_frame(&"default", ref)
	var animated := AnimatedSprite2D.new()
	animated.centered = false
	animated.sprite_frames = frames
	animated.scale = scale_up
	_place(animated, "animated")

	var stretched := TextureRect.new()
	stretched.texture = ref
	stretched.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretched.stretch_mode = TextureRect.STRETCH_SCALE
	stretched.size = Vector2(CELL, CELL)
	_place(stretched, "texture_rect")

	var tiled := TextureRect.new()
	tiled.texture = ref
	tiled.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tiled.stretch_mode = TextureRect.STRETCH_TILE
	tiled.size = Vector2(CELL, CELL)
	_place(tiled, "tiled")

	var patch := NinePatchRect.new()
	patch.texture = ref
	patch.patch_margin_left = 1
	patch.patch_margin_right = 1
	patch.patch_margin_top = 1
	patch.patch_margin_bottom = 1
	patch.size = Vector2(CELL, CELL)
	_place(patch, "nine_patch")

	var panel := Panel.new()
	var box := StyleBoxTexture.new()
	box.texture = ref
	box.texture_margin_left = 1
	box.texture_margin_right = 1
	box.texture_margin_top = 1
	box.texture_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", box)
	panel.size = Vector2(CELL, CELL)
	_place(panel, "style_box")

	var bar := TextureProgressBar.new()
	bar.texture_progress = ref
	bar.nine_patch_stretch = true
	bar.max_value = 1
	bar.value = 1
	bar.size = Vector2(CELL, CELL)
	_place(bar, "progress")

	var painter := PicturePainter.new()
	painter.texture = ref
	painter.size = Vector2(CELL, CELL)
	_place(painter, "painter")

	var source := TileSetAtlasSource.new()
	source.texture = PictureRef.of("tile/wall_sheet")
	source.texture_region_size = Vector2i(16, 16)
	source.create_tile(Vector2i(0, 0))
	source.create_tile(Vector2i(1, 0))
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(16, 16)
	tile_set.add_source(source, 0)
	var layer := TileMapLayer.new()
	layer.tile_set = tile_set
	layer.set_cell(Vector2i(0, 0), 0, Vector2i(1, 0))
	layer.set_cell(Vector2i(1, 0), 0, Vector2i(1, 0))
	layer.set_cell(Vector2i(0, 1), 0, Vector2i(1, 0))
	layer.set_cell(Vector2i(1, 1), 0, Vector2i(1, 0))
	_place(layer, "tile_map")


func _place(node: CanvasItem, cell_name: String) -> void:
	var at := Vector2i(_cells.size() % COLUMNS, _cells.size() / COLUMNS)
	_cells[cell_name] = at
	_nodes[cell_name] = node
	node.position = Vector2(at * CELL)
	_viewport.add_child(node)


func _draw_frames(count := 4) -> Image:
	for i in count:
		await get_tree().process_frame
	RenderingServer.force_draw()
	await get_tree().process_frame
	return _viewport.get_texture().get_image()


## The color in the middle of the cell `cell_name`.
func _color_at(image: Image, cell_name: String, inner := Vector2i(CELL / 2, CELL / 2)) -> Color:
	var at: Vector2i = _cells[cell_name]
	return image.get_pixelv(at * CELL + inner)


func test_every_consumer_draws_the_picture_of_the_key(do_skip := DisplayServer.get_name() == "headless", skip_reason := SKIP) -> void:
	_stage("ui_picture/title_sky")
	var image := await _draw_frames()
	for cell_name in ["sprite", "animated", "texture_rect", "tiled", "nine_patch", "style_box", "progress"]:
		assert_that(_color_at(image, cell_name)).override_failure_message("%s does not show the picture" % cell_name).is_equal(PicturesShelf.RED)
	assert_that(_color_at(image, "painter", Vector2i(CELL / 4, CELL / 2))).override_failure_message("draw_texture_rect").is_equal(PicturesShelf.RED)       # (the left half, stretched)
	assert_that(_color_at(image, "painter", Vector2i(CELL / 2 + 2, 2))).override_failure_message("draw_texture").is_equal(PicturesShelf.RED)            # (the picture's own 4 x 4, top left of the right half)
	assert_that(_color_at(image, "tile_map", Vector2i(CELL - 2, CELL - 2))).override_failure_message("the tile map").is_equal(PicturesShelf.GREEN)       # (the sheet's second tile, from the atlas the ref gives)
	assert_that(_color_at(image, "tile_map", Vector2i(CELL / 2, CELL / 2))).is_equal(PicturesShelf.GREEN)


func test_a_picture_of_a_scaled_pack_fills_the_same_place_as_a_plain_one(do_skip := DisplayServer.get_name() == "headless", skip_reason := SKIP) -> void:
	_shelf.mount_hires()
	_stage("frame/sub_00")                                                           # (a 16 x 16 file of a pack of picture scale 4, drawn at 4 x 4)
	var image := await _draw_frames()
	for cell_name in ["sprite", "animated", "texture_rect"]:
		assert_that(_color_at(image, cell_name)).override_failure_message("%s does not show the scaled picture" % cell_name).is_equal(PicturesShelf.YELLOW)
	assert_that(_color_at(image, "sprite", Vector2i(CELL - 1, CELL - 1))).is_equal(PicturesShelf.YELLOW)          # (as big as a plain 4 x 4 picture: the cell is filled)


func test_the_same_nodes_show_the_new_chains_picture_when_the_chain_changes(do_skip := DisplayServer.get_name() == "headless", skip_reason := SKIP) -> void:
	_stage("ui_picture/title_sky")
	await _draw_frames()
	_shelf.mount_over()                                                              # (the pack over `base` redraws the key white)
	var image := await _draw_frames()
	for cell_name in ["sprite", "texture_rect", "tiled", "nine_patch", "progress"]:
		assert_that(_color_at(image, cell_name)).override_failure_message("%s did not follow the chain" % cell_name).is_equal(PicturesShelf.WHITE)
	# a node that draws from a frame list, a style box or by hand does not listen to the texture's `changed`: its owner redraws it (as the game's presenters redraw on a change of the chain)
	for cell_name in ["animated", "style_box", "painter"]:
		(_nodes[cell_name] as CanvasItem).queue_redraw()
	image = await _draw_frames()
	assert_that(_color_at(image, "animated")).override_failure_message("animated").is_equal(PicturesShelf.WHITE)
	assert_that(_color_at(image, "style_box")).override_failure_message("style_box").is_equal(PicturesShelf.WHITE)
	assert_that(_color_at(image, "painter", Vector2i(CELL / 4, CELL / 2))).override_failure_message("painter").is_equal(PicturesShelf.WHITE)
	assert_that(_color_at(image, "tile_map", Vector2i(CELL / 2, CELL / 2))).is_equal(PicturesShelf.GREEN)         # (the tile sheet is the same picture in both packs)
