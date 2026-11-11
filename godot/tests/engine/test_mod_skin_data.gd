class_name TestModSkinData
extends GdUnitTestSuite
## Teaches: a skin that is only data. A mod pack whose manifest says `skin` and has no `entry` is the same `ModSkin` in `SkinChoice` as a skin that runs a script, and it needs no godot-sandbox
## extension: its `render` (`RenderSettings`) goes on the window, its `pictures` (a skin key to a PNG of the pack's `skin/` folder) replace the base game's while this skin is worn, and only then, and its `hud_font` (a `.ttf` of the pack, with a
## size and a colour) is the lettering of the HUD's boxes, which keep their rectangles, and its `layers` put a shader (a compiled `ModShader`, with the values of its uniforms) on a layer of the original presenter, which sets the `phase` uniform to the game's time.
## The tests cover the manifest (every mistake is a sentence), the pack check, the skin the host makes (also in a build without the extension), and what wearing it changes and does not. That a skin of any
## kind changes no rule is `test_plays_identically.gd`, `test_skins_dont_change_the_game.gd` and `test_presenter_binds_late.gd`, which play this skin through `SkinRoster`.

const FIXTURE := "res://tests/mods/skin_data"
## The key the fixture maps (the first zone's name box of the console) and the file it maps it to.
const KEY := "ui_picture/ui_1195"
const FILE := "skin/sky.png"
## The font the fixture ships (`tools/make_test_font.py`: blocks for every printable ASCII letter), and the name inside it.
const FONT := "skin/hud.ttf"
const FONT_NAME := "Larissa Test Block"
## The shader the fixture lists and puts on two layers (`uniform float phase`, `glint`, `vec4 tint`, `vec2 size`).
const SHADER := "skin/glow.gdshader"
const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"

var _shelves: Array[PackShelf] = []


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	SkinChoice.select(SkinChoice.original())
	ModLoader.pretend_no_sandbox = false
	ModSkinShelf.release(_shelves)
	SkinChoice.select(SkinChoice.original())
	GameState.reset()


func _parse(data: Variant) -> Array:
	var errors: Array[String] = []
	var spec := ModSpec.parse(data, errors)
	return [spec, errors]


## The data skin fixture, mounted and running (with no Sandbox when `without_extension`).
func _mount(without_extension := false) -> PackShelf:
	ModLoader.pretend_no_sandbox = without_extension
	_shelves = ModSkinShelf.mount(["skin_data"] as Array[String])
	return _shelves[0]


func _report(shelf: PackShelf) -> PackReport:
	var options := PackCheck.Options.new()
	options.reach = false
	return PackCheck.run(Pack.open(shelf.root), options)


# --- the manifest ---------------------------------------------------------------------------------------------------------

func test_a_skin_without_an_entry_is_a_data_skin_with_render_and_pictures() -> void:
	var data := {"requires_api": 5, "skin": {"render": {"texture_filter": "linear", "snap_vertices": false}, "pictures": {KEY: FILE}}}
	var got := _parse(data)
	var spec: ModSpec = got[0]
	assert_array(got[1]).is_empty()
	assert_bool(spec.is_skin).is_true()
	assert_bool(spec.has_entry()).is_false()
	assert_str(spec.entry).is_empty()
	assert_int(spec.render.texture_filter).is_equal(Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR)
	assert_bool(spec.render.snap_transforms).is_true()                                      # (what it does not say stays the project's)
	assert_bool(spec.render.snap_vertices).is_false()
	assert_dict(spec.pictures).is_equal({KEY: FILE})
	assert_dict(spec.functions()).is_empty()                                                # (no script: no function to define)
	assert_dict(spec.to_dict()).is_equal(data)
	assert_dict((_parse(spec.to_dict())[0] as ModSpec).to_dict()).is_equal(data)


func test_a_scripted_skin_may_have_render_and_pictures_too() -> void:
	var spec: ModSpec = _parse({"entry": "reef.sgd", "requires_api": 5, "skin": {"render": {}, "pictures": {KEY: FILE}}})[0]
	assert_object(spec).is_not_null()
	assert_bool(spec.has_entry()).is_true()
	assert_array(spec.functions().keys()).is_equal([ModSkin.FRAME_FUNCTION])
	assert_dict(spec.to_dict()["skin"]).is_equal({"render": {}, "pictures": {KEY: FILE}})            # (a render that says nothing is still a render: the skin sets the project's own)
	assert_object((_parse({"entry": "reef.sgd", "requires_api": 2, "skin": {}})[0] as ModSpec).render).is_null()


func test_every_render_filter_has_its_name_and_the_names_round_trip() -> void:
	for filter_name: String in RenderSettings.FILTER_NAMES:
		var spec: ModSpec = _parse({"requires_api": 5, "skin": {"render": {"texture_filter": filter_name}}})[0]
		assert_int(spec.render.texture_filter).is_equal(RenderSettings.FILTER_NAMES[filter_name])
		assert_str(RenderSettings.filter_name(spec.render.texture_filter)).is_equal(filter_name)
	assert_dict((_parse({"requires_api": 5, "skin": {"render": {"texture_filter": "nearest"}}})[0] as ModSpec).to_dict()["skin"]).is_equal({"render": {}})   # (the project's own is not written)


func test_every_mistake_in_a_data_skin_is_a_sentence() -> void:
	var many := {}
	for i in ModSpec.MAX_PICTURES + 1:
		many["ui_picture/ui_%d" % (1000 + i)] = FILE
	var bad := {
		"no entry and no skin": [{"requires_api": 5}, "needs an \"entry\""],
		"no entry for problem screens": [{"requires_api": 5, "skin": {}, "problems": {"types": [40]}}, "needs an \"entry\""],
		"no entry for rule hooks": [{"requires_api": 5, "skin": {}, "rules": {"sub": true}}, "needs an \"entry\""],
		"an empty entry": [{"entry": "", "requires_api": 5, "skin": {}}, "needs an \"entry\""],
		"a data skin of the skin API": [{"requires_api": 2, "skin": {}}, "requires_api"],
		"pictures of the skin API": [{"entry": "a.sgd", "requires_api": 2, "skin": {"pictures": {KEY: FILE}}}, "requires_api"],
		"render of the skin API": [{"entry": "a.sgd", "requires_api": 2, "skin": {"render": {}}}, "requires_api"],
		"render not an object": [{"requires_api": 5, "skin": {"render": "linear"}}, "\"render\" must be an object"],
		"a render key it does not know": [{"requires_api": 5, "skin": {"render": {"antialias": true}}}, "no \"antialias\""],
		"a filter it does not know": [{"requires_api": 5, "skin": {"render": {"texture_filter": "sharp"}}}, "texture_filter"],
		"a filter not a string": [{"requires_api": 5, "skin": {"render": {"texture_filter": 1}}}, "texture_filter"],
		"a snap not a boolean": [{"requires_api": 5, "skin": {"render": {"snap_transforms": "no"}}}, "true or false"],
		"pictures not an object": [{"requires_api": 5, "skin": {"pictures": [FILE]}}, "\"pictures\" must be an object"],
		"a key of another kind": [{"requires_api": 5, "skin": {"pictures": {"frame/sub_00": FILE}}}, "picture key"],
		"a key with no kind": [{"requires_api": 5, "skin": {"pictures": {"ui_1195": FILE}}}, "picture key"],
		"a key with a folder in its name": [{"requires_api": 5, "skin": {"pictures": {"ui_picture/a/b": FILE}}}, "picture key"],
		"a key that is not a name": [{"requires_api": 5, "skin": {"pictures": {"ui_picture/Sky": FILE}}}, "picture key"],
		"a picture outside skin/": [{"requires_api": 5, "skin": {"pictures": {KEY: "pictures/sky.png"}}}, "must be a file"],
		"a picture climbing out": [{"requires_api": 5, "skin": {"pictures": {KEY: "skin/../sky.png"}}}, "must be a file"],
		"a picture of the game": [{"requires_api": 5, "skin": {"pictures": {KEY: "res://skins/original/sky.png"}}}, "must be a file"],
		"a picture that is no png": [{"requires_api": 5, "skin": {"pictures": {KEY: "skin/sky.jpg"}}}, "must be a file"],
		"a picture not a string": [{"requires_api": 5, "skin": {"pictures": {KEY: 3}}}, "must be a file"],
		"too many pictures": [{"requires_api": 5, "skin": {"pictures": many}}, "at most"],
		"layers of the skin API": [{"requires_api": 2, "skin": {"shaders": [SHADER], "layers": {}}}, "requires_api"],
	}
	for what: String in bad:
		var got := _parse(bad[what][0])
		assert_object(got[0]).override_failure_message("%s was accepted" % what).is_null()
		assert_bool((got[1] as Array[String]).any(func(e: String) -> bool: return e.contains(bad[what][1]))) \
				.override_failure_message("%s: %s" % [what, got[1]]).is_true()


func test_hud_font_is_a_file_with_a_size_and_a_colour() -> void:
	var data := {"requires_api": 5, "skin": {"hud_font": {"file": FONT, "size": 20, "color": "#dcf7ff"}}}
	var got := _parse(data)
	var spec: ModSpec = got[0]
	assert_array(got[1]).is_empty()
	assert_str(spec.hud_font_spec.file).is_equal(FONT)
	assert_int(spec.hud_font.font_size).is_equal(20)
	assert_str(spec.hud_font.font_color.to_html(false)).is_equal("dcf7ff")
	assert_object(spec.hud_font.font).is_null()                                                     # (the file is read when the skin is made)
	assert_dict(spec.to_dict()).is_equal(data)
	var plain: ModSpec = _parse({"requires_api": 5, "skin": {"hud_font": {"file": FONT}}})[0]       # (size and colour left out are the original's lettering: `HudLabels`' own)
	assert_int(plain.hud_font.font_size).is_equal(HudLabels.new().font_size)
	assert_object(plain.hud_font.font_color).is_equal(HudLabels.new().font_color)
	assert_dict(plain.to_dict()["skin"]).is_equal({"hud_font": {"file": FONT}})
	var see_through: ModSpec = _parse({"requires_api": 5, "skin": {"hud_font": {"file": FONT, "color": "#10203040"}}})[0]
	assert_float(see_through.hud_font.font_color.a).is_equal_approx(0x40 / 255.0, 0.001)
	assert_str(see_through.to_dict()["skin"]["hud_font"]["color"]).is_equal("#10203040")
	assert_object((_parse({"requires_api": 5, "skin": {}})[0] as ModSpec).hud_font).is_null()


func test_every_mistake_in_a_hud_font_is_a_sentence() -> void:
	var bad := {
		"not an object": [{"requires_api": 5, "skin": {"hud_font": FONT}}, "\"hud_font\" must be an object"],
		"no file": [{"requires_api": 5, "skin": {"hud_font": {"size": 12}}}, "needs a \"file\""],
		"a key it does not know": [{"requires_api": 5, "skin": {"hud_font": {"file": FONT, "bold": true}}}, "no \"bold\""],
		"a file outside skin/": [{"requires_api": 5, "skin": {"hud_font": {"file": "fonts/hud.ttf"}}}, "must be a file"],
		"a file climbing out": [{"requires_api": 5, "skin": {"hud_font": {"file": "skin/../hud.ttf"}}}, "must be a file"],
		"a file that is no ttf": [{"requires_api": 5, "skin": {"hud_font": {"file": "skin/hud.otf"}}}, "must be a file"],
		"a file not a string": [{"requires_api": 5, "skin": {"hud_font": {"file": 3}}}, "must be a file"],
		"a size too small": [{"requires_api": 5, "skin": {"hud_font": {"file": FONT, "size": ModSpec.MIN_HUD_FONT_SIZE - 1}}}, "\"size\""],
		"a size too large": [{"requires_api": 5, "skin": {"hud_font": {"file": FONT, "size": ModSpec.MAX_HUD_FONT_SIZE + 1}}}, "\"size\""],
		"a size not whole": [{"requires_api": 5, "skin": {"hud_font": {"file": FONT, "size": 12.5}}}, "\"size\""],
		"a colour not a string": [{"requires_api": 5, "skin": {"hud_font": {"file": FONT, "color": [1, 1, 1]}}}, "\"color\""],
		"a colour that is no colour": [{"requires_api": 5, "skin": {"hud_font": {"file": FONT, "color": "#xyz"}}}, "\"color\""],
		"a colour name": [{"requires_api": 5, "skin": {"hud_font": {"file": FONT, "color": "red"}}}, "\"color\""],
		"a font of the skin API": [{"entry": "a.sgd", "requires_api": 2, "skin": {"hud_font": {"file": FONT}}}, "requires_api"],
	}
	for what: String in bad:
		var got := _parse(bad[what][0])
		assert_object(got[0]).override_failure_message("%s was accepted" % what).is_null()
		assert_bool((got[1] as Array[String]).any(func(e: String) -> bool: return e.contains(bad[what][1]))) \
				.override_failure_message("%s: %s" % [what, got[1]]).is_true()


# --- the pack -------------------------------------------------------------------------------------------------------------

func test_a_data_skin_pack_is_valid_without_the_extension_and_a_scripted_one_is_not() -> void:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture(FIXTURE)
	ModLoader.pretend_no_sandbox = true
	assert_array(Pack.open(shelf.root).errors).is_empty()
	assert_bool(Pack.open(shelf.root).mod.has_entry()).is_false()
	var scripted := PackShelf.new()
	_shelves.append(scripted)
	scripted.add_mod_fixture("res://tests/mods/skinny")
	assert_array(Pack.open(scripted.root).errors).is_equal([ModLoader.missing_extension_text()])


func test_the_check_passes_a_sound_data_skin_and_names_what_is_wrong() -> void:
	var sound := PackShelf.new()
	_shelves.append(sound)
	sound.add_mod_fixture(FIXTURE)
	ModSkinShelf.add_files(sound)
	var report := _report(sound)
	assert_bool(report.passes()).override_failure_message(report.text()).is_true()
	assert_array(report.warnings().filter(func(f: PackReport.Finding) -> bool: return f.area == "mod")).override_failure_message(report.text()).is_empty()
	var missing := PackShelf.new()                                                                       # (the manifest maps a file the pack does not hold)
	_shelves.append(missing)
	missing.add_mod_fixture(FIXTURE)
	var found := _report(missing)
	assert_bool(found.errors().any(func(f: PackReport.Finding) -> bool: return f.message.contains("skin/sky.png") and f.message.contains(KEY))).override_failure_message(found.text()).is_true()
	var broken := PackShelf.new()
	_shelves.append(broken)
	broken.add_mod_fixture(FIXTURE)
	ModSkinShelf.add_files(broken)
	broken.write_text(FILE, "not a picture")
	assert_bool(_report(broken).errors().any(func(f: PackReport.Finding) -> bool: return f.message.contains("skin/sky.png"))).is_true()
	var unnamed := PackShelf.new()
	_shelves.append(unnamed)
	unnamed.add_mod_fixture(FIXTURE, {"skin": {"pictures": {"ui_picture/no_such_picture": FILE}}})
	ModSkinShelf.add_files(unnamed)
	var warned := _report(unnamed)
	assert_bool(warned.passes()).is_true()
	assert_bool(warned.warnings().any(func(f: PackReport.Finding) -> bool: return f.message.contains("ui_picture/no_such_picture") and f.message.contains("never asked for"))).override_failure_message(warned.text()).is_true()


func test_the_check_says_what_is_wrong_with_a_font() -> void:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture(FIXTURE)
	ModSkinShelf.add_files(shelf)
	shelf.write_text(FONT, "this is not a font at all, but text")
	assert_bool(_report(shelf).errors().any(func(f: PackReport.Finding) -> bool: return f.message.contains("hud_font") and f.message.contains("not a TrueType font"))).is_true()
	shelf.write_bytes(FONT, FileAccess.get_file_as_bytes("%s/%s" % [FIXTURE, FONT]).slice(0, 200))     # (a TrueType font cut short: the header is right, the engine finds no face)
	assert_bool(_report(shelf).errors().any(func(f: PackReport.Finding) -> bool: return f.message.contains("hud_font") and f.message.contains("cannot read"))).is_true()
	var big := PackedByteArray()
	big.resize(Pack.MAX_FONT_BYTES + 1)
	shelf.write_bytes(FONT, big)
	assert_bool(_report(shelf).errors().any(func(f: PackReport.Finding) -> bool: return f.message.contains("hud_font") and f.message.contains("larger than"))).is_true()
	DirAccess.remove_absolute("%s/%s" % [shelf.root, FONT])
	assert_bool(_report(shelf).errors().any(func(f: PackReport.Finding) -> bool: return f.message.contains("hud_font") and f.message.contains("not in the pack"))).is_true()
	var unused := PackShelf.new()                                                                      # (a font that no manifest names is only a warning)
	_shelves.append(unused)
	unused.add_mod_fixture(FIXTURE, {"skin": {"pictures": {}}})
	ModSkinShelf.add_files(unused)
	unused.write_bytes("skin/other.ttf", FileAccess.get_file_as_bytes("%s/%s" % [FIXTURE, FONT]))
	var report := _report(unused)
	assert_bool(report.warnings().any(func(f: PackReport.Finding) -> bool: return f.message.contains("skin/other.ttf") and f.message.contains("never used"))).override_failure_message(report.text()).is_true()
	assert_bool(report.warnings().any(func(f: PackReport.Finding) -> bool: return f.message.contains("skin/hud.ttf") and f.message.contains("never used"))).is_true()   # (the fixture's own font, now unnamed)


# --- the skin the host makes ------------------------------------------------------------------------------------------------

func test_the_host_makes_the_skin_and_needs_no_extension_for_it() -> void:
	for without_extension in [false, true]:
		var shelf := _mount(without_extension)
		assert_str(ModHost.failure(String(shelf.id))).is_empty()
		assert_array(Mods.loaded_ids()).is_equal([String(shelf.id)])
		assert_array(Mods.loader().get_mod_ids()).override_failure_message("a data skin loads no script").is_empty()
		assert_object(ModHost.mod(shelf.id)).is_null()
		assert_array(SkinChoice.available()).contains([shelf.id])
		var skin := SkinChoice.load_skin(shelf.id)
		assert_bool(skin is ModSkin).is_true()
		assert_object(skin.presenter_scene_or_null()).override_failure_message("the presenter of a data skin is the original's").is_null()
		assert_bool(auto_free(PresenterChoice.make_presenter_for(skin)) is OriginalPresenter).is_true()
		assert_array(skin.pictures.keys()).contains_exactly_in_any_order([KEY, "ui_picture/title_sky"])
		assert_float(skin.pictures[KEY].get_size().x).is_equal(32.0)
		var labels := skin.labels()
		assert_object(labels).is_not_null()
		assert_str(labels.font.get_font_name()).is_equal(FONT_NAME)
		assert_int(labels.font_size).is_equal(12)
		assert_str(labels.font_color.to_html(false)).is_equal("dcf7ff")
		assert_str(labels.game_word(0)).is_equal(HudLabels.new().game_word(0))                           # (the words and the box colour stay the original lettering's)
		assert_object(skin.render).is_not_null()
		assert_int(skin.render.texture_filter).is_equal(Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR)
		ModSkinShelf.release(_shelves)
		assert_array(Mods.loaded_ids()).is_empty()


func test_a_skin_with_a_font_that_is_not_one_is_refused() -> void:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture(FIXTURE)
	ModSkinShelf.add_files(shelf)
	shelf.write_text(FONT, "not a font")
	shelf.mount()
	Mods.sync()
	assert_str(ModHost.failure(String(shelf.id))).contains("hud_font").contains("not a TrueType font")
	assert_array(SkinChoice.available()).not_contains([shelf.id])


func test_the_skin_ends_with_its_pack() -> void:
	var shelf := _mount()
	SkinChoice.select_id(shelf.id)
	assert_str(String(SkinChoice.current().id)).is_equal(String(shelf.id))
	ModSkinShelf.release(_shelves)
	assert_object(SkinChoice.current()).is_same(SkinChoice.original())                                  # (the pack left the chain: the original is put on)
	assert_array(SkinChoice.available()).not_contains([shelf.id])


func test_a_skin_that_maps_a_file_the_pack_lacks_is_refused() -> void:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture(FIXTURE)
	shelf.mount()
	Mods.sync()
	assert_str(ModHost.failure(String(shelf.id))).contains("skin/sky.png")
	assert_array(SkinChoice.available()).not_contains([shelf.id])
	assert_array(Mods.loaded_ids()).not_contains([String(shelf.id)])


func test_a_skin_with_the_id_of_a_skin_of_the_game_is_refused() -> void:
	var shelf := PackShelf.new(&"creatures")
	_shelves.append(shelf)
	shelf.add_mod_fixture(FIXTURE)
	ModSkinShelf.add_files(shelf)
	shelf.mount()
	Mods.sync()
	assert_str(ModHost.failure("creatures")).contains("id of a skin that comes with the game")


# --- what wearing it changes ------------------------------------------------------------------------------------------------

func test_the_pictures_are_worn_only_while_the_skin_is() -> void:
	var shelf := _mount()
	var mapped: Texture2D = (SkinChoice.load_skin(shelf.id) as ModSkin).pictures[KEY]
	var plain := Catalog.hud_layout().zone_textures[0]
	assert_object(plain).is_not_same(mapped)
	SkinChoice.select_id(shelf.id)
	assert_object(Catalog.hud_layout().zone_textures[0]).is_same(mapped)
	assert_object(Catalog.hud_layout().zone_textures[1]).is_same(Catalog.skinned(load(DevPack.ROOT + "data/ui/hud_layout.tres")).get("zone_textures")[1])   # (what it does not map is the original's)
	SkinChoice.select(SkinChoice.original())
	assert_object(Catalog.hud_layout().zone_textures[0]).is_same(plain)
	assert_object(SkinChoice.within(SkinChoice.load_skin(shelf.id), func() -> Texture2D: return Catalog.hud_layout().zone_textures[0])).is_same(mapped)
	assert_object(Catalog.hud_layout().zone_textures[0]).is_same(plain)                                 # (outside the call: the skin in use)


func test_the_font_is_the_hud_lettering_only_while_the_skin_is_worn() -> void:
	var shelf := _mount()
	var skin := SkinChoice.load_skin(shelf.id)
	assert_object(SkinChoice.original().labels()).is_null()
	assert_object(SkinChoice.current().labels()).is_null()
	SkinChoice.select_id(shelf.id)
	assert_object(SkinChoice.current().labels()).is_same(skin.hud_labels)
	var font := SkinChoice.current().labels().font as FontVariation                                     # (the fixture says a weight: the font is its file, varied)
	assert_object(font).is_not_null()
	assert_object(font.base_font).is_same(shelf.pack.font(FONT))                                        # (the pack's one door made it)
	assert_float(font.variation_opentype[FontSpec.WEIGHT_TAG]).is_equal(600.0)
	SkinChoice.select(SkinChoice.original())
	assert_object(SkinChoice.current().labels()).is_null()


func test_the_hud_is_lettered_in_the_font_and_its_boxes_keep_their_rectangles() -> void:
	var shelf := _mount()
	GameState.customized = true
	GameState.set_sector(0, 9)
	var hud := scene_runner("res://src/ui/hud.tscn").scene() as Hud
	var boxes: Array[TextureRect] = [hud.game_label, hud.zone_label, hud.sector_label, hud.custom_label]
	var texts: Array[Label] = [hud.game_text, hud.zone_text, hud.sector_text, hud.custom_text]
	var plain := boxes.map(func(box: TextureRect) -> Rect2: return box.get_rect())
	SkinChoice.select_id(shelf.id)
	for i in boxes.size():
		assert_bool(texts[i].visible).is_true()
		assert_str(texts[i].get_theme_font(&"font").get_font_name()).is_equal(FONT_NAME)
		assert_int(texts[i].get_theme_font_size(&"font_size")).is_equal(12)
		assert_str(texts[i].get_theme_color(&"font_color").to_html(false)).is_equal("dcf7ff")
		assert_object(boxes[i].get_rect()).override_failure_message("box %d" % i).is_equal(Rect2(plain[i].position, Vector2(Catalog.hud_layout().get(["game_size", "zone_size", "sector_size", "custom_size"][i]))))
	SkinChoice.select(SkinChoice.original())
	for i in boxes.size():
		assert_bool(texts[i].visible).is_false()
		assert_object(boxes[i].get_rect()).is_equal(plain[i])


func test_the_font_is_read_from_a_pack_file_and_goes_with_an_export() -> void:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture(FIXTURE)
	ModSkinShelf.add_files(shelf)
	var zip := "user://test_font_%d.%s" % [Time.get_ticks_usec(), Pack.FILE_EXTENSION]
	assert_int(PackFiles.zip_folder(shelf.root, zip, String(shelf.id))).is_equal(OK)
	var archived := Pack.open(zip)
	assert_bool(archived.is_archive()).is_true()
	assert_str(archived.font(FONT).get_font_name()).is_equal(FONT_NAME)
	assert_object(archived.file(FONT)).is_same(archived.font(FONT))                                       # (`Pack.file` answers a .ttf with the font, as it does a .png with the picture)
	assert_str(archived.font_problem(FONT)).is_empty()
	assert_array(ModParts.problems(archived)).is_empty()
	archived.close()
	DirAccess.remove_absolute(zip)
	var stage := "user://test_font_export_%d" % Time.get_ticks_usec()
	var source := Pack.open(shelf.root)
	assert_str(PackExport._write_complete_file(source, stage, FONT)).is_empty()                         # (the export copies the file as it is)
	assert_array(FileAccess.get_file_as_bytes("%s/%s" % [stage, FONT])).is_equal(source.read_bytes(FONT))
	PackFiles.remove_tree(stage)


func test_a_picture_of_a_pack_wins_over_the_skins() -> void:
	var shelf := _mount()
	var above := PackShelf.new(&"", shelf.id)                                                           # (a pack laid over the skin's: its `pictures/` is the content's say, under every skin)
	_shelves.append(above)
	above.add_picture("pictures/%s.png" % KEY, Color.MAGENTA, Vector2i(5, 5))
	above.mount()
	Mods.sync()
	SkinChoice.select_id(shelf.id)
	assert_float(Catalog.hud_layout().zone_textures[0].get_size().x).is_equal(5.0)


func test_the_render_settings_go_on_the_window_with_the_skin_and_leave_with_it() -> void:
	var shelf := _mount()
	var window := get_tree().root
	SkinChoice.select_id(shelf.id)
	assert_int(window.canvas_item_default_texture_filter).is_equal(Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR)
	assert_bool(window.snap_2d_transforms_to_pixel).is_false()
	assert_bool(window.snap_2d_vertices_to_pixel).is_false()
	SkinChoice.select(SkinChoice.original())
	assert_bool(SkinChoice.original().render_settings().is_applied_to(window)).is_true()


func test_a_changed_manifest_is_a_new_skin() -> void:
	var shelf := _mount()
	var first := SkinChoice.load_skin(shelf.id)
	assert_object(SkinChoice.load_skin(shelf.id)).is_same(first)                                        # (kept while the pack is as it was)
	var manifest: Dictionary = shelf.pack_json("pack.json")
	manifest["mod"]["skin"]["render"] = {"texture_filter": "nearest"}
	OS.delay_msec(1100)                                                                                 # (the key holds the file's time, in seconds)
	shelf.write_json("pack.json", manifest)
	shelf.mount()
	Mods.sync()
	var second := SkinChoice.load_skin(shelf.id)
	assert_object(second).is_not_same(first)
	assert_bool(first.alive).is_false()
	assert_int((second as ModSkin).render.texture_filter).is_equal(Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST)


# --- layers: shaders on the layers of the original presenter ------------------------------------------------------------------

func _layers(layers: Dictionary) -> Dictionary:
	return {"requires_api": 5, "skin": {"shaders": [SHADER], "layers": layers}}


func test_the_layers_are_the_original_presenters_and_each_is_a_node_of_its_scene() -> void:
	assert_array(SkinLayers.NODES.keys()).contains_exactly_in_any_order([&"background", &"back_decos", &"walls", &"station", &"mid_decos", &"collectibles", &"sub", &"foes", &"pellets", &"front_decos", &"anim_decos", &"bubbles"])
	var presenter := auto_free((load(PresenterChoice.ORIGINAL_SCENE) as PackedScene).instantiate()) as OriginalPresenter
	add_child(presenter)
	for layer: StringName in SkinLayers.NODES:
		assert_object(presenter.layer_node(layer)).override_failure_message(String(layer)).is_not_null()
		assert_bool(presenter.is_ancestor_of(presenter.layer_node(layer))).is_true()
		assert_str(String(presenter.layer_node(layer).name)).is_equal(SkinLayers.NODES[layer])
		var data := _layers({String(layer): {"shader": SHADER}})
		assert_array(_parse(data)[1]).override_failure_message(String(layer)).is_empty()


func test_a_layer_has_a_shader_and_the_values_of_its_uniforms() -> void:
	var data := _layers({
		"background": {"shader": SHADER, "uniforms": {"glint": 0.25, "tint": "#ff8800", "size": [608.0, 288.0], "on": true, "shade": [0.5, 0.25, 1.0], "plane": [1.0, 2.0, 3.0, 4.0], "see_through": "#ff880080"}},
		"sub": {"shader": SHADER},
	})
	var got := _parse(data)
	var spec: ModSpec = got[0]
	assert_array(got[1]).is_empty()
	var uniforms: Dictionary = spec.layers["background"]["uniforms"]
	assert_float(uniforms["glint"]).is_equal(0.25)
	assert_str((uniforms["tint"] as Color).to_html(false)).is_equal("ff8800")
	assert_object(uniforms["size"]).is_equal(Vector2(608, 288))
	assert_bool(uniforms["on"]).is_true()
	assert_object(uniforms["shade"]).is_equal(Vector3(0.5, 0.25, 1.0))
	assert_object(uniforms["plane"]).is_equal(Vector4(1, 2, 3, 4))
	assert_float((uniforms["see_through"] as Color).a).is_equal_approx(0x80 / 255.0, 0.001)
	assert_dict(spec.layers["sub"]).is_equal({"shader": SHADER, "uniforms": {}})
	assert_dict(spec.to_dict()).is_equal(data)
	assert_dict((_parse(spec.to_dict())[0] as ModSpec).to_dict()).is_equal(data)
	assert_dict((_parse({"requires_api": 5, "skin": {}})[0] as ModSpec).layers).is_empty()


func test_every_mistake_in_a_layer_is_a_sentence() -> void:
	var many := {}
	for i in ModSpec.MAX_LAYER_UNIFORMS + 1:
		many["u%d" % i] = 1.0
	var bad := {
		"layers not an object": [{"requires_api": 5, "skin": {"shaders": [SHADER], "layers": [SHADER]}}, "\"layers\" must be an object"],
		"a layer the presenter has not": [_layers({"currents": {"shader": SHADER}}), "no layer \"currents\""],
		"a layer with a capital": [_layers({"Background": {"shader": SHADER}}), "no layer \"Background\""],
		"a layer not an object": [_layers({"background": SHADER}), "must be an object"],
		"a key it does not know": [_layers({"background": {"shader": SHADER, "blend": "add"}}), "no \"blend\""],
		"no shader": [_layers({"background": {}}), "needs a \"shader\""],
		"a shader the skin does not list": [_layers({"background": {"shader": "skin/other.gdshader"}}), "needs a \"shader\""],
		"a shader not a string": [_layers({"background": {"shader": 3}}), "needs a \"shader\""],
		"uniforms not an object": [_layers({"background": {"shader": SHADER, "uniforms": [1.0]}}), "\"uniforms\""],
		"too many uniforms": [_layers({"background": {"shader": SHADER, "uniforms": many}}), "at most"],
		"a name with a space": [_layers({"background": {"shader": SHADER, "uniforms": {"two words": 1.0}}}), "uniform name"],
		"a name starting with a digit": [_layers({"background": {"shader": SHADER, "uniforms": {"2d": 1.0}}}), "uniform name"],
		"phase, which the game sets": [_layers({"background": {"shader": SHADER, "uniforms": {"phase": 1.0}}}), "the game sets it"],
		"a number too large": [_layers({"background": {"shader": SHADER, "uniforms": {"glint": ModSpec.MAX_UNIFORM_VALUE + 1.0}}}), "\"glint\""],
		"a number too small": [_layers({"background": {"shader": SHADER, "uniforms": {"glint": -ModSpec.MAX_UNIFORM_VALUE - 1.0}}}), "\"glint\""],
		"a vector with one number": [_layers({"background": {"shader": SHADER, "uniforms": {"size": [1.0]}}}), "\"size\""],
		"a vector with five": [_layers({"background": {"shader": SHADER, "uniforms": {"size": [1.0, 2.0, 3.0, 4.0, 5.0]}}}), "\"size\""],
		"a vector with a word": [_layers({"background": {"shader": SHADER, "uniforms": {"size": [1.0, "2"]}}}), "\"size\""],
		"a vector too large": [_layers({"background": {"shader": SHADER, "uniforms": {"size": [1.0, 1e9]}}}), "\"size\""],
		"a colour name": [_layers({"background": {"shader": SHADER, "uniforms": {"tint": "orange"}}}), "\"tint\""],
		"a colour that is no colour": [_layers({"background": {"shader": SHADER, "uniforms": {"tint": "#xyz"}}}), "\"tint\""],
		"an object": [_layers({"background": {"shader": SHADER, "uniforms": {"tint": {"r": 1.0}}}}), "\"tint\""],
		"a script that draws the whole screen": [{"entry": "a.sgd", "requires_api": 5, "skin": {"shaders": [SHADER], "layers": {"background": {"shader": SHADER}}}}, "script_layers"],
	}
	for what: String in bad:
		var got := _parse(bad[what][0])
		assert_object(got[0]).override_failure_message("%s was accepted" % what).is_null()
		assert_bool((got[1] as Array[String]).any(func(e: String) -> bool: return e.contains(bad[what][1]))) \
				.override_failure_message("%s: %s" % [what, got[1]]).is_true()


## A scratch data skin pack whose layers are `layers` (the fixture's own shader listed), running; its skin.
func _mount_layers(layers: Dictionary, shader_text := "") -> ModSkin:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture(FIXTURE, {"skin": {"shaders": [SHADER], "layers": layers}})
	ModSkinShelf.add_files(shelf)
	if not shader_text.is_empty():
		shelf.write_text(SHADER, shader_text)
	shelf.mount()
	Mods.sync()
	return SkinChoice.load_skin(shelf.id) as ModSkin


func test_the_check_says_what_is_wrong_with_a_layer() -> void:
	var cases := {
		"a uniform the shader does not declare": [{"background": {"shader": SHADER, "uniforms": {"glow": 0.5}}}, "does not declare"],
		"a number for a colour": [{"background": {"shader": SHADER, "uniforms": {"tint": 0.5}}}, "a vec4"],
		"a colour for a float": [{"background": {"shader": SHADER, "uniforms": {"glint": "#ff8800"}}}, "a number is needed"],
		"a list of three for a vec2": [{"background": {"shader": SHADER, "uniforms": {"size": [1.0, 2.0, 3.0]}}}, "a list of 2 numbers"],
	}
	for what: String in cases:
		var shelf := PackShelf.new()
		_shelves.append(shelf)
		shelf.add_mod_fixture(FIXTURE, {"skin": {"shaders": [SHADER], "layers": cases[what][0]}})
		ModSkinShelf.add_files(shelf)
		var report := _report(shelf)
		assert_bool(report.errors().any(func(f: PackReport.Finding) -> bool: return f.message.contains(cases[what][1]) and f.message.contains("\"background\""))).override_failure_message("%s: %s" % [what, report.text()]).is_true()
	var odd := PackShelf.new()                                                                           # (a shader that fails ModShader: a loop)
	_shelves.append(odd)
	odd.add_mod_fixture(FIXTURE, {"skin": {"shaders": [SHADER], "layers": {"background": {"shader": SHADER}}}})
	ModSkinShelf.add_files(odd)
	odd.write_text(SHADER, "shader_type canvas_item;\nvoid fragment() { for (int i = 0; i < 3; i++) { COLOR = vec4(1.0); } }")
	assert_bool(_report(odd).errors().any(func(f: PackReport.Finding) -> bool: return f.message.contains(SHADER) and f.message.contains("no loops"))).is_true()
	var no_shader := PackShelf.new()                                                                     # (a layer's shader the pack lacks)
	_shelves.append(no_shader)
	no_shader.add_mod_fixture(FIXTURE)
	DirAccess.remove_absolute("%s/%s" % [no_shader.root, SHADER])
	assert_bool(_report(no_shader).errors().any(func(f: PackReport.Finding) -> bool: return f.message.contains(SHADER) and f.message.contains("not in the pack"))).is_true()


func test_a_shader_declares_its_uniforms_in_its_text() -> void:
	var source := "shader_type canvas_item;\n// uniform float hidden;\nuniform float phase = 0.0;\ninstance uniform vec4 tint : source_color;\nuniform lowp int bands = 3;\nuniform sampler2D noise;\nuniform float list[3];\nvoid fragment() {}"
	assert_dict(ModShader.uniform_types(source)).is_equal({"phase": "float", "tint": "vec4", "bands": "int", "noise": "sampler2D", "list": "array"})
	assert_str(ModShader.uniform_problem("sampler2D", 1.0)).contains("cannot set")
	assert_str(ModShader.uniform_problem("int", 2.5)).contains("whole number")
	assert_str(ModShader.uniform_problem("int", 2.0)).is_empty()
	assert_int(ModShader.uniform_value("int", 2.0)).is_equal(2)
	assert_str(ModShader.uniform_problem("bool", 1.0)).contains("true or false")
	assert_str(ModShader.uniform_problem("vec3", Color.RED)).is_empty()
	assert_str(ModShader.uniform_problem("vec2", Color.RED)).contains("2 numbers")


func test_the_skin_holds_a_material_for_each_layer_and_hands_out_copies() -> void:
	var shelf := _mount()
	var skin := SkinChoice.load_skin(shelf.id)
	assert_array(skin.layer_materials.keys()).contains_exactly_in_any_order([&"background", &"foes"])
	var material := skin.layer_materials[&"background"]
	assert_str(material.shader.code).is_equal((skin as ModSkin).assets.shaders[SHADER].code)
	assert_float(material.get_shader_parameter(&"glint")).is_equal(0.25)
	assert_str((material.get_shader_parameter(&"tint") as Color).to_html(false)).is_equal("ff8800")
	assert_object(material.get_shader_parameter(&"size")).is_equal(Vector2(608, 288))
	assert_object(skin.layer_materials[&"foes"].get_shader_parameter(&"glint")).is_null()               # (what the manifest does not say is the shader's own default)
	var copy := skin.layer_material(&"background")
	assert_object(copy).is_not_same(material)
	assert_object(copy.shader).is_same(material.shader)
	assert_float(copy.get_shader_parameter(&"glint")).is_equal(0.25)
	assert_object(skin.layer_material(&"walls")).is_null()
	assert_object(SkinChoice.original().layer_material(&"background")).is_null()
	var int_skin := _mount_layers({"background": {"shader": SHADER, "uniforms": {"bands": 3.0, "soft": true}}}, "shader_type canvas_item;\nuniform int bands = 1;\nuniform bool soft = false;\nvoid fragment() { COLOR = vec4(float(bands)); }")
	assert_int(int_skin.layer_materials[&"background"].get_shader_parameter(&"bands")).is_equal(3)
	assert_bool(int_skin.layer_materials[&"background"].get_shader_parameter(&"soft")).is_true()


# --- what a layer's shader does and does not touch (that no rule changes is `test_plays_identically`, which plays this skin) ---------------------------------------------------------------------------

## A presenter of the original kind dressed in `skin`, in the tree and bound to `sim` (what `SectorWorld` does with the skin in use).
func _presenter(skin: GameSkin, sim: SimWorld) -> OriginalPresenter:
	var presenter := auto_free(PresenterChoice.make_presenter_for(skin)) as OriginalPresenter
	presenter.run_in_skin(func() -> void:
		add_child(presenter)
		presenter.bind(sim))
	return presenter


## A sim with the arena loaded, the sub flying and `ticks` ticks run.
func _sim(ticks: int) -> SimWorld:
	var sim := SimWorld.new(GameState)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.foe_context.rng.seed = 4242
	sim.start_flight(200, 150, 6)
	for i in ticks:
		sim.tick()
	return sim


func _shader_of(node: CanvasItem) -> String:
	var material := node.material as ShaderMaterial
	return "" if material == null else material.shader.code


func test_the_layers_the_manifest_names_wear_the_shader_and_no_other() -> void:
	var skin := SkinChoice.load_skin(_mount().id)
	var presenter := _presenter(skin, _sim(2))
	var shader := (skin as ModSkin).assets.shaders[SHADER].code
	for layer: StringName in SkinLayers.NODES:
		assert_str(_shader_of(presenter.layer_node(layer))).override_failure_message(String(layer)).is_equal(shader if [&"background", &"foes"].has(layer) else "")
	assert_float((presenter.background.material as ShaderMaterial).get_shader_parameter(&"glint")).is_equal(0.25)
	assert_object(presenter.background.material).is_not_same(presenter.foes_layer.material)             # (a material to a layer)
	var plain := _presenter(SkinChoice.original(), _sim(0))
	for layer: StringName in SkinLayers.NODES:
		assert_object(plain.layer_node(layer).material).override_failure_message(String(layer)).is_null()


func test_every_picture_inside_a_layer_wears_the_layers_material() -> void:
	var skin := SkinChoice.load_skin(_mount().id)
	var sim := _sim(2)
	sim.tick(InputSnapshot.firing())                                                                      # (a pellet in flight: a node made after the presenter was bound)
	var presenter := _presenter(skin, sim)
	sim.tick()
	var checked := 0
	for layer: StringName in SkinLayers.NODES:
		var found: Array[Node] = presenter.layer_node(layer).find_children("*", "CanvasItem", true, false)
		for node: Node in found:
			var item := node as CanvasItem
			assert_bool(item.use_parent_material).override_failure_message("%s of %s" % [item.get_path(), layer]).is_true()
			assert_object(item.material).override_failure_message("%s of %s has a material of its own" % [item.get_path(), layer]).is_null()
			checked += 1
	assert_int(checked).is_greater(10)                                                                    # (decorations, creatures with their sprites, the sub's pictures, the pellet, the bubbles, the station)
	assert_int(presenter.foes_layer.get_child_count()).is_greater(0)


func test_the_sub_dissolve_is_its_own_material_and_the_layers_comes_back() -> void:
	var skin := SkinChoice.load_skin(_mount_layers({"sub": {"shader": SHADER}}).id)
	var sim := _sim(2)
	var presenter := _presenter(skin, sim)
	assert_bool(presenter.sub.sprite.use_parent_material).is_true()
	sim.begin_dissolve()
	sim.advance_dissolve(SimWorld.dissolve_length() / 3)
	assert_bool(presenter.sub.dissolve_material() != null).is_true()
	assert_bool(presenter.sub.sprite.use_parent_material).is_false()
	sim.abandon_damage()
	presenter.sub.show_dissolve(Sub.NO_DISSOLVE)
	assert_object(presenter.sub.dissolve_material()).is_null()
	assert_bool(presenter.sub.sprite.use_parent_material).is_true()
	assert_str(_shader_of(presenter.sub)).is_equal((skin as ModSkin).assets.shaders[SHADER].code)


func _phase(presenter: OriginalPresenter, layer := &"background") -> float:
	return (presenter.layer_node(layer).material as ShaderMaterial).get_shader_parameter(&"phase")


func test_phase_is_the_games_time_from_the_start_and_when_bound_late() -> void:
	var skin := SkinChoice.load_skin(_mount().id)
	var sim := SimWorld.new(GameState)
	var first := _presenter(skin, sim)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.start_flight(200, 150, 6)
	for i in 3:
		sim.tick()
	var late := _presenter(skin, sim)
	for presenter in [first, late]:
		presenter.show_between_ticks(0.5)
		assert_float(_phase(presenter)).is_equal_approx(presenter.view.tick_number + 0.5, 0.0001)
		assert_float(_phase(presenter, &"foes")).is_equal(_phase(presenter))                              # (every layer has the one time)
	assert_float(_phase(late)).is_equal(_phase(first))
	assert_float(_phase(late)).is_greater(3.0)
	late.show_between_ticks(0.0)                                                                           # (a frame without a tick: the same time; the clock held: it stands still)
	var held := _phase(late)
	for i in 5:
		late.show_between_ticks(0.0)
	assert_float(_phase(late)).is_equal(held)
	assert_float(_phase(first)).is_not_equal(held)                                                         # (a presenter's phase is its own: the other one was not moved)
	assert_float(late.game_phase(0.25)).is_equal(late.view.tick_number + 0.25)
	late.unbind()
	assert_float(late.game_phase(0.25)).is_equal(0.0)


func test_the_skin_goes_and_the_material_goes_with_it() -> void:
	var shelf := _mount()
	SkinChoice.select_id(shelf.id)
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(DevCreatures.ARENA, 0)
	var worn := world.original.background.material
	assert_object(worn).is_instanceof(ShaderMaterial)
	assert_object(world.original.foes_layer.material).is_instanceof(ShaderMaterial)
	world.presenter.show_between_ticks(0.5)
	assert_float(_phase(world.original)).is_equal_approx(world.presenter.view.tick_number + 0.5, 0.0001)
	SkinChoice.select(SkinChoice.original())
	for layer: StringName in SkinLayers.NODES:
		assert_object(world.original.layer_node(layer).material).override_failure_message(String(layer)).is_null()
	SkinChoice.select_id(shelf.id)
	assert_object(world.original.background.material).is_instanceof(ShaderMaterial)
	assert_object(world.original.background.material).is_not_same(worn)                                    # (made again from the skin and the clock, not kept)
	world.presenter.show_between_ticks(0.5)
	assert_float(_phase(world.original)).is_equal_approx(world.presenter.view.tick_number + 0.5, 0.0001)
