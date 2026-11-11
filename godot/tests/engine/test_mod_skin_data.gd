class_name TestModSkinData
extends GdUnitTestSuite
## Teaches: a skin that is only data. A mod pack whose manifest says `skin` and has no `entry` is the same `ModSkin` in `SkinChoice` as a skin that runs a script, and it needs no godot-sandbox
## extension: its `render` (`RenderSettings`) goes on the window, its `pictures` (a skin key to a PNG of the pack's `skin/` folder) replace the base game's while this skin is worn, and only then, and its `hud_font` (a `.ttf` of the pack, with a
## size and a colour) is the lettering of the HUD's boxes, which keep their rectangles.
## The tests cover the manifest (every mistake is a sentence), the pack check, the skin the host makes (also in a build without the extension), and what wearing it changes and does not. That a skin of any
## kind changes no rule is `test_plays_identically.gd`, `test_skins_dont_change_the_game.gd` and `test_presenter_binds_late.gd`, which play this skin through `SkinRoster`.

const FIXTURE := "res://tests/mods/skin_data"
## The key the fixture maps (the first zone's name box of the console) and the file it maps it to.
const KEY := "ui_picture/ui_1195"
const FILE := "skin/sky.png"
## The font the fixture ships (`tools/make_test_font.py`: blocks for every printable ASCII letter), and the name inside it.
const FONT := "skin/hud.ttf"
const FONT_NAME := "Larissa Test Block"

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
	assert_array(spec.functions().keys()).is_equal([ModSkin.FUNCTION])
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
	assert_str(spec.hud_font_file).is_equal(FONT)
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
	var shelf := PackShelf.new(&"modern")
	_shelves.append(shelf)
	shelf.add_mod_fixture(FIXTURE)
	ModSkinShelf.add_files(shelf)
	shelf.mount()
	Mods.sync()
	assert_str(ModHost.failure("modern")).contains("id of a skin that comes with the game")


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
	assert_object(SkinChoice.current().labels().font).is_same(shelf.pack.font(FONT))                    # (the pack's one door made it)
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
