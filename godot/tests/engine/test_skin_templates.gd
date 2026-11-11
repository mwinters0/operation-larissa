class_name TestSkinTemplates
extends GdUnitTestSuite
## Teaches: a tool whose answer is a list read off the engine's own data. The art templates (`SkinTemplates`, the command line `skin_templates_tool.tscn`) write one flat-colour PNG per picture of the
## HUD's layout, named by the skin key a skin's `pictures` uses, at the size of the picture in the layout, with the key and the size written on it, and one for each layer of the console a script may draw, at the size of the
## layer's rectangle in the layout: so these tests read the layout, ask for the same keys and sizes, and look at the files. Another phase's pictures are one more layout in `SkinTemplates.SOURCES`, and the same tests cover them.

const OUT := "user://test_skin_templates"

var _layout: HudLayout = Catalog.pack_resource("data/ui/hud_layout.tres") as HudLayout


func after_test() -> void:
	PackFiles.remove_tree(OUT)


## key -> size of the entries that are pictures a skin replaces (`ui_picture/...`).
func _sizes() -> Dictionary:
	var sizes := {}
	for entry in SkinTemplates.entries():
		if entry.key.begins_with("ui_picture/") and not entry.key.contains("prompt_sender"):       # (the console's: the sender's are the problem screen's)
			sizes[entry.key] = entry.size
	return sizes


## layer -> size of the entries that are layers of the console a script may draw.
func _layer_sizes() -> Dictionary:
	var sizes := {}
	for entry in SkinTemplates.entries():
		if entry.key.begins_with(SkinTemplates.LAYER_KIND + "/"):
			sizes[StringName(entry.key.get_slice("/", 1))] = entry.size
	return sizes


func _key_of(texture: Texture2D) -> String:
	return GameSkin.key_of(Packs.source_of(texture))


## The pixels of a PNG file, read the way a pack's picture is.
func _read(path: String) -> Image:
	var picture := Image.load_from_file(ProjectSettings.globalize_path(path))
	assert_object(picture).is_not_null()
	return picture


func _colors(picture: Image) -> Dictionary:
	var colors := {}
	for y in picture.get_height():
		for x in picture.get_width():
			colors[picture.get_pixel(x, y)] = true
	return colors


# --- the list ----------------------------------------------------------------------------------------------------------------

func test_every_picture_of_the_hud_layout_has_an_entry_at_its_size() -> void:
	var sizes := _sizes()
	var pictures: Array[Texture2D] = [_layout.bezel, _layout.tank_full, _layout.tank_empty, _layout.oxygen_full, _layout.oxygen_empty, _layout.oxygen_low,
			_layout.ink_full, _layout.ink_empty, _layout.custom_texture, _layout.sector_final_texture]
	pictures.append_array(_layout.game_textures)
	pictures.append_array(_layout.zone_textures)
	pictures.append_array(_layout.sector_textures)
	pictures.append_array(_layout.ship_textures)
	pictures.append_array(_layout.computer_textures)
	for texture in pictures:
		assert_bool(sizes.has(_key_of(texture))).is_true()
		assert_object(sizes[_key_of(texture)]).is_equal(Vector2i(texture.get_size()))
	assert_int(sizes.size()).is_equal(24)


func test_every_layer_of_the_console_has_an_entry_at_the_size_of_its_rectangle() -> void:
	var sizes := _layer_sizes()
	var rects := ConsoleState.rects(_layout)
	assert_array(sizes.keys()).is_equal(SkinLayers.hud_layers())
	for layer in SkinLayers.hud_layers():
		assert_object(sizes[layer]).override_failure_message(String(layer)).is_equal(Vector2i((rects[String(layer)] as Rect2).size))
	assert_object(sizes[&"hud_bezel"]).is_equal(_layout.bezel_size)
	assert_object(sizes[&"hud_ship"]).is_equal(_layout.ship_size)
	assert_object(sizes[&"hud_oxygen"]).is_equal(_layout.oxygen_rect.size)


func test_the_keys_are_keys_a_skin_may_name_and_the_game_asks_for() -> void:
	var seen := {}
	for entry in SkinTemplates.entries():
		if entry.key.begins_with(SkinTemplates.LAYER_KIND + "/"):
			assert_bool(SkinLayers.is_hud_layer(StringName(entry.key.get_slice("/", 1)))).is_true()
			continue
		if entry.key == "%s/%s" % [SkinTemplates.PROBLEM_LAYER_KIND, SkinTemplates.PROBLEM_WINDOW]:
			continue
		var kind := entry.key.get_slice("/", 0)
		assert_bool(ModSpec.is_picture_key(entry.key) if kind == "ui_picture" else ModSpec.is_drawable_key(entry.key)).is_true()
		assert_bool(kind == "ui_picture" or kind == "problem_art").override_failure_message(entry.key).is_true()
		assert_bool(NameRegistry.original().index_of(StringName(kind), entry.key.get_slice("/", 1)) >= 0).is_true()
		assert_bool(seen.has(entry.key)).is_false()
		seen[entry.key] = true
		assert_bool(entry.size.x > 0 and entry.size.y > 0).is_true()


func test_the_sizes_of_the_label_boxes_are_the_layouts() -> void:
	var sizes := _sizes()
	for texture in _layout.game_textures:
		assert_object(sizes[_key_of(texture)]).is_equal(_layout.game_size)
	for texture in _layout.zone_textures:
		assert_object(sizes[_key_of(texture)]).is_equal(_layout.zone_size)
	for texture in _layout.sector_textures:
		assert_object(sizes[_key_of(texture)]).is_equal(_layout.sector_size)
	assert_object(sizes[_key_of(_layout.custom_texture)]).is_equal(_layout.custom_size)


func test_the_frame_and_the_panels_of_the_problem_screen_have_entries_at_the_layouts_sizes() -> void:
	var screen := Catalog.pack_resource("data/problems/screen_layout.tres") as ProblemScreenLayout
	var calculator := Catalog.pack_resource("data/ui/calculator_layout.tres") as CalculatorLayout
	var sizes := {}
	for entry in SkinTemplates.entries():
		sizes[entry.key] = entry.size
	assert_object(sizes[_key_of(screen.background)]).is_equal(Vector2i(screen.background.get_size()))
	assert_object(sizes[_key_of(calculator.picture)]).is_equal(calculator.picture_size)
	assert_object(sizes[_key_of(calculator.answer_panel)]).is_equal(calculator.answer_size)
	assert_bool(_key_of(screen.background).begins_with("problem_art/")).is_true()
	assert_object(sizes["problem_layer/window"]).is_equal(ProblemState.WINDOW_SIZE)
	var written := SkinTemplates.write(OUT)
	assert_bool(written.has("%s/problem_layer/window.png" % OUT)).is_true()
	assert_bool(written.has("%s/%s.png" % [OUT, _key_of(screen.background)])).is_true()
	assert_object(_read("%s/problem_layer/window.png" % OUT).get_size()).is_equal(Vector2i(640, 400))


func test_the_senders_pictures_have_entries_at_the_size_the_screen_stretches_them_to() -> void:
	var sizes := {}
	for entry in SkinTemplates.entries():
		sizes[entry.key] = entry.size
	for sender in [PromptSender.PICTURE_SHIP, PromptSender.PICTURE_CONTROL_ROOM]:
		var key := "ui_picture/%s" % sender
		assert_bool(ModSpec.is_picture_key(key)).is_true()                                              # (a skin's `pictures` may name it)
		assert_object(sizes[key]).is_equal(PromptSender.PICTURE_SIZE)
	var icon := (load("res://src/problems/problem_screen.tscn") as PackedScene).instantiate() as ProblemScreen
	assert_object(Vector2i(icon.get_node("%SenderIcon").size)).is_equal(PromptSender.PICTURE_SIZE)   # (the scene's rectangle is the same number)
	icon.free()


# --- the pictures ------------------------------------------------------------------------------------------------------------

func test_it_writes_one_png_per_key_at_the_layout_size() -> void:
	var failures: Array[String] = []
	var written := SkinTemplates.write(OUT, failures)
	assert_array(failures).is_empty()
	var entries := SkinTemplates.entries()
	assert_int(written.size()).is_equal(entries.size())
	for entry in entries:
		var path := "%s/%s" % [OUT, entry.rel_path()]
		assert_bool(written.has(path)).is_true()
		assert_object(_read(path).get_size()).is_equal(entry.size)
	assert_bool(FileAccess.file_exists("%s/ui_picture/%s.png" % [OUT, _key_of(_layout.bezel).get_slice("/", 1)])).is_true()
	assert_bool(FileAccess.file_exists("%s/hud_layer/hud_oxygen.png" % OUT)).is_true()


func test_a_template_is_one_flat_colour_with_the_words_in_another() -> void:
	var entry := SkinTemplates.Entry.new("ui_picture/ui_1195", Vector2i(96, 16))
	var picture := SkinTemplates.image(entry)
	assert_object(picture.get_size()).is_equal(Vector2i(96, 16))
	var colors := _colors(picture)
	assert_int(colors.size()).is_equal(2)
	assert_bool(colors.has(SkinTemplates.color_of(entry.key))).is_true()
	assert_bool(colors.has(SkinTemplates.TEXT_COLOR)).is_true()
	assert_object(picture.get_pixel(0, 0)).is_equal(SkinTemplates.color_of(entry.key))


func test_the_words_are_the_key_and_the_size_then_less_as_the_picture_gets_smaller() -> void:
	assert_array(SkinTemplates._lines(SkinTemplates.Entry.new("ui_picture/ui_1195", Vector2i(96, 16)))).is_equal(["ui_picture/ui_1195", "96x16"])
	assert_array(SkinTemplates._lines(SkinTemplates.Entry.new("ui_picture/ui_1204", Vector2i(20, 24)))).is_equal(["ui_12", "04", "20x24"])
	assert_array(SkinTemplates._lines(SkinTemplates.Entry.new("ui_picture/ui_1193", Vector2i(24, 8)))).is_equal(["24x8"])
	assert_array(SkinTemplates._lines(SkinTemplates.Entry.new("ui_picture/ui_1193", Vector2i(8, 8)))).is_empty()
	assert_int(_colors(SkinTemplates.image(SkinTemplates.Entry.new("ui_picture/ui_1193", Vector2i(8, 8)))).size()).is_equal(1)


func test_a_template_is_the_same_every_time() -> void:
	var entry := SkinTemplates.Entry.new("ui_picture/ui_1189", Vector2i(616, 72))
	assert_array(SkinTemplates.image(entry).get_data()).is_equal(SkinTemplates.image(entry).get_data())


# --- the command line --------------------------------------------------------------------------------------------------------

func _tool(args: PackedStringArray) -> Array:
	var output: Array = []
	var full := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://src/skins/skin_templates_tool.tscn", "--"])
	full.append_array(PackShelf.pin_args())
	full.append_array(args)
	var code := OS.execute(OS.get_executable_path(), full, output, true)
	return [code, "\n".join(PackedStringArray(output.map(func(chunk: Variant) -> String: return str(chunk))))]


func test_the_tool_writes_the_templates_of_the_pack_in_use() -> void:
	var ran := _tool(PackedStringArray(["--out=" + ProjectSettings.globalize_path(OUT)]))
	assert_int(ran[0]).is_equal(0)
	assert_str(ran[1]).contains("wrote %d templates" % SkinTemplates.entries().size())
	for entry in SkinTemplates.entries():
		assert_object(_read("%s/%s" % [OUT, entry.rel_path()]).get_size()).is_equal(entry.size)


func test_the_tool_lists_the_keys_and_sizes_and_refuses_an_option_it_does_not_know() -> void:
	var listed := _tool(PackedStringArray(["--list"]))
	assert_int(listed[0]).is_equal(0)
	assert_str(listed[1]).contains("%s  %d x %d" % [_key_of(_layout.bezel), _layout.bezel.get_size().x, _layout.bezel.get_size().y])
	assert_int(_tool(PackedStringArray(["--nonsense"]))[0]).is_equal(2)
