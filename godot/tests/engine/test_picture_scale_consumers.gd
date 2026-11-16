class_name TestPictureScaleConsumers
extends GdUnitTestSuite
## Teaches: what a run at picture scale 4 changes for each consumer of a picture, and what it must not. The game's unit stays 640 x 400: every picture of a pack of scale 4 reports the size of the picture of scale 1 it replaces (`ScaledTexture`), and what the renderer takes by RID
## instead of asking the texture to draw is made for the scale by one builder each: the tile set (`ScaledTileSet`: its cells, atlases and collision polygons N times as long under layers at 1/N) and the nine-patches of a theme (`ScaledStyleBox`). `UpscaledShelf` is the pack
## that is the scale-1 chain at four times the pixels; the pixels it puts on the screen are `test_picture_scale_render.gd`'s (windowed).

var _shelf: UpscaledShelf
var _scratch: Array[PackShelf] = []


func before() -> void:
	GameState.reset()
	_shelf = UpscaledShelf.new()


func after() -> void:
	_shelf.remove()
	GameState.reset()


func after_test() -> void:
	for shelf in _scratch:
		shelf.remove()
	_scratch.clear()
	_shelf.plain.mount()


## The size of each picture of the dev pack's table, as the chain in use draws it.
func _sizes() -> Dictionary[String, Vector2i]:
	var found: Dictionary[String, Vector2i] = {}
	for key in PackShelf.dev_picture_keys():
		var picture := Pictures.resolve(key)
		if picture != null:
			found[key] = Vector2i(picture.get_size())
	return found


func _frame_sizes(frames: SpriteFrames) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for animation in frames.get_animation_names():
		for index in frames.get_frame_count(animation):
			found.append(Vector2i(frames.get_frame_texture(animation, index).get_size()))
	return found


# --- the sizes the rules, the layouts and the sprites read ---------------------------------------------------------------

func test_every_picture_of_a_scale_4_pack_reports_the_size_of_the_picture_it_replaces() -> void:
	_shelf.mount_plain()
	assert_int(Packs.picture_decision().scale).is_equal(1)
	var plain := _sizes()
	var plain_frames := _frame_sizes(Catalog.foes_frames(0))
	var plain_decos := _frame_sizes(Catalog.decos_frames(0))
	var background_key := UpscaledShelf.BACKGROUNDS[0]
	var plain_background := Pictures.resolve(background_key).get_size()
	_shelf.mount_upscaled()
	assert_int(Packs.picture_decision().scale).is_equal(UpscaledShelf.SCALE)
	assert_dict(_sizes()).is_equal(plain)                                                         # (every key, so the layouts, the hit tests and the sprites' centres are the ones of scale 1)
	assert_array(_frame_sizes(Catalog.foes_frames(0))).is_equal(plain_frames)
	assert_array(_frame_sizes(Catalog.decos_frames(0))).is_equal(plain_decos)
	assert_that(Pictures.resolve(background_key).get_size()).is_equal(plain_background)
	assert_that(Assets.picture_by_key(background_key).get_size()).is_equal(plain_background)
	var frame := Pictures.resolve("ui_picture/ui_1195")
	assert_bool(frame is ScaledTexture).is_true()
	assert_int(ScaledTexture.stored(frame).get_width()).is_equal(frame.get_width() * UpscaledShelf.SCALE)       # (and the file has the pixels of the larger picture)


# --- the tile set ------------------------------------------------------------------------------------------------------------

func _zone_source(tile_set: TileSet) -> TileSetAtlasSource:
	return tile_set.get_source(Catalog.zone(0).tile_source_id) as TileSetAtlasSource


## A tile of the zone atlas that has a collision polygon.
func _tile_with_polygon(source: TileSetAtlasSource) -> Vector2i:
	for index in source.get_tiles_count():
		var coords := source.get_tile_id(index)
		if source.get_tile_data(coords, 0).get_collision_polygons_count(0) > 0:
			return coords
	return Vector2i(-1, -1)


func test_a_tile_set_at_scale_4_has_cells_atlases_and_polygons_four_times_as_long_and_the_pack_s_own_is_untouched() -> void:
	_shelf.mount_upscaled()
	var held := Catalog.tileset()
	var one := _zone_source(held)
	var coords := _tile_with_polygon(one)
	assert_bool(coords.x >= 0).override_failure_message("dev's zone atlas has a tile with a collision").is_true()
	var points := one.get_tile_data(coords, 0).get_collision_polygon_points(0, 0)
	var made := ScaledTileSet.of(held, UpscaledShelf.SCALE)
	var big := _zone_source(made)
	assert_that(made.tile_size).is_equal(held.tile_size * 4)
	assert_that(big.texture_region_size).is_equal(one.texture_region_size * 4)
	assert_that(big.texture.get_size()).is_equal(one.texture.get_size() * 4.0)                      # (the stored file: its own RID and pixels)
	assert_bool(big.texture is PictureRef or big.texture is ScaledTexture).override_failure_message("the atlas holds the file, not a picture that reports less of it").is_false()
	assert_that(big.get_atlas_grid_size()).is_equal(one.get_atlas_grid_size())                      # (the same grid of tiles: the atlas coordinates a cell names are the same)
	assert_int(big.get_tiles_count()).is_equal(one.get_tiles_count())
	for index in one.get_tiles_count():
		assert_that(big.get_tile_id(index)).is_equal(one.get_tile_id(index))
	var scaled_points := big.get_tile_data(coords, 0).get_collision_polygon_points(0, 0)
	assert_int(scaled_points.size()).is_equal(points.size())
	for i in points.size():
		assert_that(scaled_points[i]).is_equal(points[i] * 4.0)
	assert_that(big.get_tile_data(coords, 0).get_custom_data_by_layer_id(0)).is_equal(one.get_tile_data(coords, 0).get_custom_data_by_layer_id(0))     # (what `TileCodec` reads)
	assert_that(held.tile_size).is_equal(Vector2i(16, 16))                                           # (the owner's tile set is as it was)
	assert_that(one.texture_region_size).is_equal(Vector2i(16, 16))
	assert_bool(one.texture is PictureRef).is_true()
	assert_that(one.get_tile_data(coords, 0).get_collision_polygon_points(0, 0)).is_equal(points)
	assert_object(ScaledTileSet.of(held, 1)).override_failure_message("scale 1 changes nothing").is_same(held)


func test_the_layers_at_scale_4_put_a_cell_where_the_layers_at_scale_1_put_it() -> void:
	_shelf.mount_plain()
	var plain := TileMapLayer.new()
	auto_free(plain)
	ScaledTileSet.dress([plain], Catalog.tileset())
	assert_that(plain.scale).is_equal(Vector2.ONE)
	assert_object(plain.tile_set).is_same(Catalog.tileset())
	_shelf.mount_upscaled()
	var walls := TileMapLayer.new()
	var currents := TileMapLayer.new()
	auto_free(walls)
	auto_free(currents)
	ScaledTileSet.dress([walls, currents], Catalog.tileset())
	assert_that(walls.scale).is_equal(Vector2.ONE / 4.0)
	assert_object(currents.tile_set).override_failure_message("the layers share one tile set").is_same(walls.tile_set)
	for cell in [Vector2i(0, 0), Vector2i(3, 2), Vector2i(39, 24)]:
		assert_that(walls.map_to_local(cell) * walls.scale).is_equal(plain.map_to_local(cell))
		assert_that(walls.local_to_map(plain.map_to_local(cell) / walls.scale)).is_equal(cell)


func test_a_presenter_dresses_its_layers_for_the_scale_of_the_chain_each_time_the_chain_changes() -> void:
	_shelf.mount_upscaled()
	var presenter := auto_free((load("res://src/gameplay/original_presenter.tscn") as PackedScene).instantiate()) as OriginalPresenter
	add_child(presenter)
	assert_that(presenter.walls.tile_set.tile_size).is_equal(Vector2i(64, 64))                        # (made in the middle of a run at scale 4)
	assert_that(presenter.walls.scale).is_equal(Vector2.ONE / 4.0)
	assert_object(presenter.currents.tile_set).is_same(presenter.walls.tile_set)
	_shelf.mount_plain()                                                                              # (the chain changes under it)
	assert_that(presenter.walls.tile_set.tile_size).is_equal(Vector2i(16, 16))
	assert_that(presenter.walls.scale).is_equal(Vector2.ONE)
	_shelf.mount_upscaled()
	assert_that(presenter.currents.tile_set.tile_size).is_equal(Vector2i(64, 64))
	assert_that(presenter.currents.scale).is_equal(Vector2.ONE / 4.0)


func test_the_screen_editor_dresses_its_layers_like_the_presenter() -> void:
	_shelf.mount_upscaled()
	var editor := auto_free(ScreenEditor.new()) as ScreenEditor
	editor.data_dir = DevPack.SECTORS_DIR
	editor.sector = Ground.MAIN
	editor.screen = 6
	editor.reload()
	for layer_name in ["Walls", "Currents"]:
		var layer := editor.get_node(layer_name) as TileMapLayer
		assert_that(layer.tile_set.tile_size).override_failure_message("the editor's %s layer holds the tile set of the scale the run draws at" % layer_name).is_equal(Vector2i(64, 64))
		assert_that(layer.scale).is_equal(Vector2.ONE / 4.0)
	_shelf.mount_plain()
	editor.reload()
	assert_that((editor.get_node("Walls") as TileMapLayer).tile_set.tile_size).is_equal(Vector2i(16, 16))


# --- nine-patches and style boxes ----------------------------------------------------------------------------------------------

func _theme_with_a_picture() -> Theme:
	var data := SkinTheme.new()
	data.styles["button/pressed"] = {"picture": UpscaledShelf.NINE_KEY, "slice": Vector4i(4, 4, 4, 4)}
	data.styles["panel"] = {"picture": UpscaledShelf.NINE_KEY, "slice": Vector4i(4, 3, 2, 1), "margin": Vector2i(5, 6)}
	return ThemeBuilder.derive(data, &"zz_skin")


func test_a_style_box_of_a_scaled_picture_has_the_margins_and_the_minimum_size_of_any_style_box() -> void:
	var engine_pressed := ThemeBuilder.engine().get_stylebox("pressed", "Button")                  # (a picture keeps the engine's content margins when the style says none)
	_shelf.mount_upscaled()
	var scaled := _theme_with_a_picture()
	var pressed := scaled.get_stylebox("pressed", "Button") as ScaledStyleBox
	assert_object(pressed).is_not_null()
	assert_that(pressed.texture_margin).is_equal(Vector4i(4, 4, 4, 4))                                 # (the style's numbers, in game units)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		assert_float(pressed.get_margin(side)).is_equal(engine_pressed.get_margin(side))
	assert_that(pressed.get_minimum_size()).is_equal(engine_pressed.get_minimum_size())
	var panel := scaled.get_stylebox("panel", "Panel") as ScaledStyleBox
	assert_that(panel.get_minimum_size()).is_equal(Vector2(10, 12))                                    # (the margin the style says wins over the picture's slice, 5 + 5 and 6 + 6)
	var again := ScaledStyleBox.of(Pictures.resolve(UpscaledShelf.NINE_KEY), Vector4i(2, 3, 4, 5))
	assert_that(again.get_minimum_size()).is_equal(Vector2(6, 8))                                      # (with no style's margin: the picture's own slice)


## A style box is made once (a theme holds it) and the chain changes under it: it is the one class at any scale, and what it reports and draws follows the picture of the chain in use, in game units. (The pixels it draws: `test_picture_scale_render.gd`.)
func test_a_style_box_follows_the_picture_it_holds_when_the_chain_changes() -> void:
	_shelf.mount_plain()
	var data := SkinTheme.new()
	data.styles["panel"] = {"picture": UpscaledShelf.NINE_KEY, "slice": Vector4i(4, 3, 2, 1), "margin": Vector2i(5, 6)}
	var made_at_one := ThemeBuilder.derive(data, &"zz_skin").get_stylebox("panel", "Panel")
	var held := PictureRef.of(UpscaledShelf.NINE_KEY)
	var box := ScaledStyleBox.of(held, Vector4i(4, 4, 4, 4))
	assert_object(made_at_one).override_failure_message("a theme made at scale 1 holds the style box that follows the chain").is_instanceof(ScaledStyleBox)
	assert_int(ScaledTexture.scale_of(box.texture)).is_equal(1)
	assert_that(made_at_one.get_minimum_size()).is_equal(Vector2(10, 12))
	_shelf.mount_upscaled()
	assert_int(ScaledTexture.scale_of(box.texture)).override_failure_message("the box the theme made at scale 1 holds the picture of the chain now in use").is_equal(UpscaledShelf.SCALE)
	assert_int(ScaledTexture.stored(box.texture).get_width()).is_equal(UpscaledShelf.NINE_SLICE * 3 * UpscaledShelf.SCALE)
	assert_that(made_at_one.get_minimum_size()).override_failure_message("the minimum size and the margins are game units at any scale").is_equal(Vector2(10, 12))
	assert_that(box.get_minimum_size()).is_equal(Vector2(8, 8))


# --- a texture the renderer is not asked to draw: a stored picture --------------------------------------------------------------

func test_stored_and_scale_of_see_through_a_reference_and_a_scaled_texture() -> void:
	_shelf.mount_upscaled()
	var held := PictureRef.of(UpscaledShelf.NINE_KEY)
	var file := ScaledTexture.stored(held)
	assert_int(file.get_width()).is_equal(UpscaledShelf.NINE_SLICE * 3 * UpscaledShelf.SCALE)
	assert_int(ScaledTexture.scale_of(held)).is_equal(UpscaledShelf.SCALE)
	assert_object(ScaledTexture.stored(file)).is_same(file)                                            # (a plain picture is its own file)
	assert_int(ScaledTexture.scale_of(file)).is_equal(1)
	assert_object(ScaledTexture.stored(PictureRef.of("ui_picture/nothing_here_at_all"))).is_null()
	assert_object(ScaledTexture.stored(null)).is_null()


# --- the pack check -------------------------------------------------------------------------------------------------------------

func _check(shelf: PackShelf) -> Array[String]:
	var options := PackCheck.Options.new()
	options.reach = false
	var found: Array[String] = []
	for finding in PackCheck.run(Pack.open(shelf.root), options).findings:
		if finding.area == "pictures":
			found.append(finding.message)
	return found


func _first_with(messages: Array[String], fragment: String) -> String:
	for message in messages:
		if message.contains(fragment):
			return message
	return ""


func test_a_picture_of_a_scale_4_pack_that_is_not_4_times_the_one_it_replaces_is_a_warning() -> void:
	Packs.start()                                                                                      # (the chain is the game's again, dev)
	var base: Pack = Packs.chain().back()
	var layout_keys: Array[String] = []
	for key in SkinTemplates.sizes():
		if key.begins_with("ui_picture/") and base.picture_table().files.has(key):
			layout_keys.append(key)
	var frame_key := ""
	for key: String in base.picture_table().files:
		if key.begins_with("frame/"):
			frame_key = key
			break
	var right_key := layout_keys[0]
	var odd_key := layout_keys[1]
	var right_size := base.png_size(base.picture_table().files[right_key])
	var odd_size := base.png_size(base.picture_table().files[odd_key])
	var frame_size := base.png_size(base.picture_table().files[frame_key])
	var shelf := PackShelf.new()
	_scratch.append(shelf)
	shelf.set_picture_scale(4)
	shelf.add_picture("art/right.png", Color.RED, right_size * 4)
	shelf.add_picture("art/odd.png", Color.RED, odd_size * 4 + Vector2i(1, 0))
	shelf.add_picture("art/small.png", Color.RED, frame_size)                                            # (a frame is judged too, though no layout names it)
	shelf.add_picture("art/new.png", Color.RED, Vector2i(5, 7))
	shelf.write_json(PictureTable.FILE, {"format": PictureTable.FORMAT, "pictures": {
		right_key: "art/right.png", odd_key: "art/odd.png", frame_key: "art/small.png", "ui_picture/zz_a_picture_of_its_own": "art/new.png"}})
	var told := _check(shelf)
	var odd := _first_with(told, "'%s'" % odd_key)
	assert_str(odd).override_failure_message("\n".join(told)).contains("is %dx%d pixels, and the picture of scale 1 it replaces is %dx%d, so a picture of scale 4 should be %dx%d pixels" % [
			odd_size.x * 4 + 1, odd_size.y * 4, odd_size.x, odd_size.y, odd_size.x * 4, odd_size.y * 4])
	assert_str(odd).contains("drawn at 1/4 of its size it is %dx%d" % [ceili((odd_size.x * 4 + 1) / 4.0), odd_size.y])
	assert_str(_first_with(told, "'%s'" % frame_key)).contains("should be %dx%d pixels" % [frame_size.x * 4, frame_size.y * 4])      # (the file is as large as the picture it replaces: 1 times, not 4 times)
	assert_str(_first_with(told, "'%s'" % right_key)).is_empty()                                        # (right)
	assert_str(_first_with(told, "'ui_picture/zz_a_picture_of_its_own'")).is_empty()                    # (nothing of scale 1 to compare with)
	assert_array(told.filter(func(message: String) -> bool: return message.contains("pixels, and the picture of scale 1"))).has_size(2)


func test_a_png_has_its_size_in_its_header_for_a_folder_and_for_a_pack_file_alike() -> void:
	var shelf := PackShelf.new()
	_scratch.append(shelf)
	shelf.add_picture("art/a.png", Color.RED, Vector2i(300, 7))
	shelf.write_text("art/b.png", "not a picture, but long enough to hold a header of 24 bytes")
	shelf.write_bytes("art/c.png", PackedByteArray([137, 80, 78, 71]))
	var pack := Pack.open(shelf.root)
	assert_that(pack.png_size("art/a.png")).is_equal(Vector2i(300, 7))
	assert_that(pack.png_size("art/b.png")).is_equal(Vector2i.ZERO)
	assert_that(pack.png_size("art/c.png")).is_equal(Vector2i.ZERO)
	assert_that(pack.png_size("art/missing.png")).is_equal(Vector2i.ZERO)
	var file := Scratch.path("test_png_size.larissa")
	assert_int(PackFiles.zip_folder(shelf.root, file, String(shelf.id))).is_equal(OK)
	var archived := Pack.open(file)
	assert_that(archived.png_size("art/a.png")).is_equal(Vector2i(300, 7))
	archived.close()
	DirAccess.remove_absolute(file)
