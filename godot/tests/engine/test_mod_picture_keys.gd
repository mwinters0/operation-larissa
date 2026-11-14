class_name TestModPictureKeys
extends GdUnitTestSuite
## Teaches: a mod names the pictures of the game it draws in its manifest. `picture_keys` (in `skin` and in `problems`) lists the picture keys, or a kind's wildcard (`deco/*`), that a draw list may ask for; a key it does not list is not looked up, draws nothing and
## is told once per run (`ModDraw.report`), and the declared keys count with what the chain needs (`PackNeeds`), so a set of packs at a higher picture scale must hold them to be chosen (`PictureScale`). The tests cover the manifest, the draw list, the needs and
## the run: a skin and a problem screen that draw with and without the declaration.
## These tests need the godot-sandbox extension (`uv run tools/fetch_sandbox.py`, docs/SETUP.md).

const SECTOR := 100
const SCREEN := 6
## A picture only a mod's pack holds and a mod declares.
const MOD_KEY := "ui_picture/mod_only_picture"

var _shelves: Array[PackShelf] = []
var _extra: Array[PackShelf] = []


func before() -> void:
	assert_bool(ModLoader.sandbox_available()).override_failure_message("the godot-sandbox extension is not loaded: run `uv run tools/fetch_sandbox.py`, then `tools/godot.sh --headless --path godot --import` (docs/SETUP.md)").is_true()


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	SkinChoice.select(SkinChoice.original())
	ModSkinShelf.release(_shelves)
	for i in range(_extra.size() - 1, -1, -1):
		_extra[i].remove()
	_extra.clear()
	SkinChoice.select(SkinChoice.original())
	GameState.reset()


func _parse(data: Variant) -> Array:
	var errors: Array[String] = []
	var spec := ModSpec.parse(data, errors)
	return [spec, errors]


func _told(text: String) -> Array[String]:
	var found: Array[String] = []
	for line in TroubleLog.session.told:
		if line.contains(text):
			found.append(line)
	return found


# --- the manifest ---------------------------------------------------------------------------------------------------------

func test_a_skin_and_a_problem_mod_declare_the_pictures_of_the_game_they_draw() -> void:
	var data := {"entry": "a.sgd", "requires_api": ModSpec.PICTURE_KEYS_API_VERSION,
			"skin": {"picture_keys": ["background/*", "frame/sub_00", "ui_picture/title_sky"]}, "problems": {"types": [5], "picture_keys": ["problem_art/*", "ui_picture/title_sky"]}}
	var got := _parse(data)
	var spec: ModSpec = got[0]
	assert_array(got[1]).is_empty()
	assert_array(spec.picture_keys).is_equal(["background/*", "frame/sub_00", "ui_picture/title_sky"])
	assert_array(spec.problem_picture_keys).is_equal(["problem_art/*", "ui_picture/title_sky"])
	assert_dict(spec.to_dict()).is_equal(data)
	var none: ModSpec = _parse({"entry": "a.sgd", "requires_api": 6, "skin": {}})[0]
	assert_array(none.picture_keys).is_empty()
	assert_dict(none.to_dict()).is_equal({"entry": "a.sgd", "requires_api": 6, "skin": {}})        # (nothing declared, nothing written)


func test_every_mistake_in_picture_keys_is_a_sentence() -> void:
	var skin := func(keys: Variant, api := ModSpec.PICTURE_KEYS_API_VERSION) -> Dictionary: return {"entry": "a.sgd", "requires_api": api, "skin": {"picture_keys": keys}}
	var bad := {
		"not a list": [skin.call("deco/x"), "must be a list of picture keys"],
		"the API before": [skin.call(["deco/x"], ModSpec.DRAWS_THE_GAME_API_VERSION), "\"requires_api\": %d" % ModSpec.PICTURE_KEYS_API_VERSION],
		"not a string": [skin.call([7]), "must be <kind>/<name>"],
		"no kind": [skin.call(["coral_fan"]), "must be <kind>/<name>"],
		"a kind that is none": [skin.call(["sound/whoosh"]), "must be <kind>/<name>"],
		"a wildcard of a kind that is none": [skin.call(["sound/*"]), "must be <kind>/<name>"],
		"a wildcard inside a name": [skin.call(["deco/coral_*"]), "must be <kind>/<name>"],
		"a wildcard for the kind": [skin.call(["*/coral"]), "must be <kind>/<name>"],
		"a name with capitals": [skin.call(["deco/Coral"]), "must be <kind>/<name>"],
		"a path": [skin.call(["skin/dot.png"]), "must be <kind>/<name>"],
		"too long": [skin.call(["deco/" + "x".repeat(ModSpec.MAX_KEY)]), "must be <kind>/<name>"],
		"twice": [skin.call(["deco/x", "deco/x"]), "listed twice"],
		"too many": [skin.call(range(ModSpec.MAX_PICTURE_KEYS + 1).map(func(i: int) -> String: return "deco/d%d" % i)), "at most %d" % ModSpec.MAX_PICTURE_KEYS],
		"problems: not a list": [{"entry": "a.sgd", "requires_api": 6, "problems": {"types": [40], "picture_keys": {}}}, "must be a list of picture keys"],
		"problems: the API before": [{"entry": "a.sgd", "requires_api": 5, "problems": {"types": [40], "picture_keys": ["problem_art/*"]}}, "\"requires_api\": %d" % ModSpec.PICTURE_KEYS_API_VERSION],
	}
	for what: String in bad:
		var got := _parse(bad[what][0])
		assert_object(got[0]).override_failure_message("%s was accepted" % what).is_null()
		assert_bool((got[1] as Array[String]).any(func(e: String) -> bool: return e.contains(bad[what][1]))).override_failure_message("%s: %s" % [what, got[1]]).is_true()


func test_a_key_is_declared_by_itself_or_by_the_wildcard_of_its_kind() -> void:
	var declared: Array[String] = ["deco/coral_fan_cyan", "frame/*"]
	assert_bool(ModSpec.declares(declared, "deco/coral_fan_cyan")).is_true()
	assert_bool(ModSpec.declares(declared, "deco/other")).is_false()
	assert_bool(ModSpec.declares(declared, "frame/sub_00")).is_true()
	assert_bool(ModSpec.declares(declared, "frame/station_00")).is_true()
	assert_bool(ModSpec.declares(declared, "background/bg_s00_00")).is_false()
	assert_bool(ModSpec.declares([] as Array[String], "deco/coral_fan_cyan")).is_false()


func test_the_pictures_a_mod_needs_are_its_keys_and_its_themes_and_a_wildcard_adds_none() -> void:
	var spec: ModSpec = _parse({"requires_api": 6, "skin": {"picture_keys": ["deco/*", "ui_picture/title_sky", "frame/sub_00"],
			"theme": {"button": {"normal": {"picture": "ui_picture/title_sky", "slice": [4, 4, 4, 4]}, "hover": {"picture": "ui_picture/other_sky", "slice": [4, 4, 4, 4]}}}}})[0]
	assert_array(spec.needed_pictures()).is_equal(["ui_picture/title_sky", "frame/sub_00", "ui_picture/other_sky"])


# --- the draw list ----------------------------------------------------------------------------------------------------------

func _assets(declared: Array[String], folder := ModSpec.SKIN_FOLDER) -> ModAssets:
	var assets := ModAssets.new()
	assets.folder = folder
	assets.pictures = declared
	return assets


func test_a_declared_key_is_drawn_and_an_undeclared_one_draws_nothing_and_is_named() -> void:
	var sub := Assets.picture_by_key("frame/sub_00")
	assert_object(sub).is_not_null()
	var list := [
		["picture", "frame/sub_00", Vector2(1, 2)],
		["picture", "deco/coral_fan_cyan", Vector2(3, 4)],
		["region", "tile/zone0_tiles", Rect2(0, 0, 16, 16), Rect2(0, 0, 16, 16)],
		["rect", Rect2(0, 0, 1, 1), Color.RED],
		["picture", "deco/coral_fan_cyan", Vector2(5, 6)],
	]
	var drawn := ModDraw.validate(list, null, _assets(["frame/sub_00", "tile/*"] as Array[String]))
	assert_array(drawn.layers[0].commands.map(func(c: Array) -> String: return c[0])).is_equal(["picture", "region", "rect"])
	assert_object(drawn.layers[0].commands[0][1]).is_same(sub)
	assert_array(drawn.undeclared).is_equal(["deco/coral_fan_cyan"])                         # (named once, however often the list asks)
	assert_int(drawn.dropped).override_failure_message("an undeclared key is told by name, not counted as a malformed command").is_equal(0)
	var everything := ModDraw.validate(list, null, _assets(["deco/*", "frame/*", "tile/*"] as Array[String]))
	assert_int(everything.layers[0].commands.size()).is_equal(5)
	assert_array(everything.undeclared).is_empty()
	var nothing := ModDraw.validate(list, null, null)                                         # (no assets, no declaration)
	assert_array(nothing.layers[0].commands.map(func(c: Array) -> String: return c[0])).is_equal(["rect"])
	assert_array(nothing.undeclared).is_equal(["frame/sub_00", "deco/coral_fan_cyan", "tile/zone0_tiles"])


func test_a_key_that_is_declared_and_that_nothing_holds_is_a_dropped_command_as_before() -> void:
	var drawn := ModDraw.validate([["picture", "frame/no_such_picture_99", Vector2(0, 0)]], null, _assets(["frame/*"] as Array[String]))
	assert_int(drawn.layers[0].commands.size()).is_equal(0)
	assert_int(drawn.dropped).is_equal(1)
	assert_array(drawn.undeclared).is_empty()


func test_a_name_that_is_no_key_is_never_an_undeclared_key() -> void:
	var drawn := ModDraw.validate([["picture", "skin/missing.png", Vector2(0, 0)], ["picture", "frame/Sub", Vector2(0, 0)], ["picture", 7, Vector2(0, 0)], ["picture"]], null, _assets([] as Array[String]))
	assert_array(drawn.undeclared).is_empty()
	assert_int(drawn.dropped).is_equal(4)


func test_the_keys_named_in_one_list_are_cut_and_the_line_of_each_is_given_once_per_run() -> void:
	var list: Array = []
	for i in ModDraw.MAX_UNDECLARED + 5:
		list.append(["picture", "deco/d%d" % i, Vector2(0, 0)])
	var drawn := ModDraw.validate(list, null, _assets([] as Array[String]))
	assert_int(drawn.undeclared.size()).is_equal(ModDraw.MAX_UNDECLARED)
	ModDraw.report(drawn, &"reef", "skin")
	ModDraw.report(drawn, &"reef", "skin")
	assert_int(TroubleLog.session.told.size()).is_equal(ModDraw.MAX_UNDECLARED)


func test_an_undeclared_key_is_told_once_per_run_naming_the_pack_and_the_key() -> void:
	var drawn := ModDraw.validate([["picture", "frame/sub_00", Vector2(0, 0)]], null, _assets([] as Array[String]))
	for i in 3:
		ModDraw.report(drawn, &"reef", "skin")
	assert_array(TroubleLog.session.told).is_equal(["[mods] mod 'reef': its skin draw list names the picture 'frame/sub_00', which its manifest does not declare in \"picture_keys\"; that picture is not drawn"])
	ModDraw.report(drawn, &"reef", "problem screen")                                         # (another kind of screen of the same mod: its own line)
	ModDraw.report(drawn, &"other", "skin")                                                  # (another mod: its own line)
	assert_int(TroubleLog.session.told.size()).is_equal(3)
	assert_str(TroubleLog.session.told[1]).contains("mod 'reef': its problem screen draw list names the picture 'frame/sub_00'")
	GameState.reset()                                                                        # (a new run says it again)
	ModDraw.report(drawn, &"reef", "skin")
	assert_int(TroubleLog.session.told.size()).is_equal(1)


# --- the needs of the chain ------------------------------------------------------------------------------------------------------

## A scratch mod pack (a data skin) that holds a row for `MOD_KEY` and declares `declared` in its skin's `picture_keys`, laid over `base`.
func _mod_pack(base: StringName, declared: Array) -> PackShelf:
	var shelf := PackShelf.new(&"", base)
	_extra.append(shelf)
	var manifest: Dictionary = shelf.pack_json("pack.json")
	manifest["mod"] = {"requires_api": ModSpec.PICTURE_KEYS_API_VERSION, "skin": {"picture_keys": declared}}
	shelf.write_json("pack.json", manifest)
	shelf.add_picture_row(MOD_KEY, Color.GREEN, Vector2i(4, 4))
	return shelf


## A pack of picture scale 4 laid over `base` that holds a row for every key of `keys`.
func _hires_pack(base: StringName, keys: Array[String]) -> PackShelf:
	var shelf := PackShelf.new(&"", base)
	_extra.append(shelf)
	shelf.set_picture_scale(4)
	shelf.add_picture("art/big.png", Color.RED, Vector2i(16, 16))
	var rows := {}
	for key in keys:
		rows[key] = "art/big.png"
	shelf.write_json(PictureTable.FILE, {"format": PictureTable.FORMAT, "pictures": rows})
	return shelf


func test_the_chain_needs_the_pictures_its_mods_declare() -> void:
	var plain := _mod_pack(PackShelf.base_id(), [])
	plain.mount()
	assert_bool(PackNeeds.picture_keys(Packs.chain()).has(MOD_KEY)).is_false()
	var declaring := _mod_pack(PackShelf.base_id(), [MOD_KEY, "deco/*"])
	declaring.mount()
	var keys := PackNeeds.picture_keys(Packs.chain())
	assert_bool(keys.has(MOD_KEY)).is_true()
	assert_bool(keys.has("deco/*")).override_failure_message("a wildcard is no key").is_false()
	assert_bool(PackNeeds.required(Packs.chain()).has(MOD_KEY)).is_true()
	assert_bool(PictureScale.needed(Packs.chain(), PackNeeds.picture_keys(Packs.chain())).has(MOD_KEY)).is_true()                   # (some pack holds a row for it)


func test_a_declared_key_that_no_pack_holds_is_no_gap_and_counts_against_no_set_but_the_check_warns() -> void:
	var shelf := _mod_pack(PackShelf.base_id(), ["ui_picture/nobody_holds_this"])
	shelf.mount()
	assert_bool(PackNeeds.picture_keys(Packs.chain()).has("ui_picture/nobody_holds_this")).is_true()
	assert_bool(PackNeeds.missing(Packs.chain()).has("ui_picture/nobody_holds_this")).is_false()
	assert_array(PackNeeds.gaps(Packs.chain())).is_empty()
	assert_bool(PictureScale.needed(Packs.chain(), PackNeeds.picture_keys(Packs.chain())).has("ui_picture/nobody_holds_this")).override_failure_message("a key no pack holds counts against no set").is_false()
	var options := PackCheck.Options.new()
	options.reach = false
	var report := PackCheck.run(Pack.open(shelf.root), options)
	assert_bool(report.passes()).override_failure_message(report.text()).is_true()
	assert_bool(report.warnings().any(func(f: PackReport.Finding) -> bool: return f.area == "mod" and f.message.contains("ui_picture/nobody_holds_this") and f.message.contains("picture_keys"))).override_failure_message(report.text()).is_true()


func test_a_set_of_packs_at_scale_4_that_lacks_a_key_only_a_mod_declares_does_not_cover() -> void:
	var needed := PictureScale.needed(Packs.chain(), PackNeeds.picture_keys(Packs.chain()))
	var mod := _mod_pack(PackShelf.base_id(), [MOD_KEY])
	var four := _hires_pack(mod.id, needed)
	four.mount()
	assert_int(Packs.picture_decision().scale).override_failure_message("the key the mod declares has no row at scale 4").is_equal(1)
	var shortfall := Packs.picture_decision().shortfalls
	assert_array(shortfall).has_size(1)
	assert_array(shortfall[0].missing).is_equal([MOD_KEY])
	assert_str(shortfall[0].text()).contains(MOD_KEY).contains("pack '%s' (picture scale 4)" % four.id)
	var with_key: Array[String] = needed.duplicate()
	with_key.append(MOD_KEY)
	var covering := _hires_pack(mod.id, with_key)
	covering.mount()
	assert_int(Packs.picture_decision().scale).is_equal(4)
	assert_array(Packs.picture_decision().shortfalls).is_empty()


func test_a_set_of_packs_at_scale_4_that_lacks_the_rows_of_a_wildcard_kind_does_not_cover() -> void:
	var needed := PictureScale.needed(Packs.chain(), PackNeeds.picture_keys(Packs.chain()))
	var outside: Array[String] = []                                                                  # (the problem pictures scale 1 draws that no data of the chain names: only a mod's script asks for them by a key it builds)
	for key in Packs.dev().picture_table().keys():
		if key.begins_with("problem_art/") and not needed.has(key):
			outside.append(key)
	outside.sort()
	assert_array(outside).is_not_empty()
	var mod := _mod_pack(PackShelf.base_id(), ["problem_art/*"])
	var four := _hires_pack(mod.id, needed)
	four.mount()
	assert_array(PackNeeds.picture_keys(Packs.chain())).contains(outside)
	assert_int(Packs.picture_decision().scale).override_failure_message("the pictures scale 1 would draw have no picture at scale 4").is_equal(1)
	assert_array(Packs.picture_decision().shortfalls[0].missing).is_equal(outside)
	assert_array(PackNeeds.gaps(Packs.chain())).override_failure_message("a picture of a wildcard is no gap").is_empty()
	var covering := _hires_pack(mod.id, needed + outside)
	covering.mount()
	assert_int(Packs.picture_decision().scale).is_equal(4)


## A scratch pack whose mod is a script that does not compile, so the host refuses it, and whose skin declares `MOD_KEY`.
func _refused_mod_pack(base: StringName) -> PackShelf:
	var shelf := PackShelf.new(&"", base)
	_extra.append(shelf)
	var manifest: Dictionary = shelf.pack_json("pack.json")
	manifest["mod"] = {"entry": "broken.sgd", "requires_api": ModSpec.PICTURE_KEYS_API_VERSION, "skin": {"picture_keys": [MOD_KEY]}}
	shelf.write_json("pack.json", manifest)
	shelf.write_text("broken.sgd", "func mod_init(a):\n\tthis is not code\n")
	shelf.add_picture_row(MOD_KEY, Color.GREEN, Vector2i(4, 4))
	return shelf


func test_a_mod_the_host_refused_declares_no_picture_the_scale_must_hold() -> void:
	var needed := PictureScale.needed(Packs.chain(), PackNeeds.picture_keys(Packs.chain()))
	var broken := _refused_mod_pack(PackShelf.base_id())
	_hires_pack(broken.id, needed).mount()
	assert_int(Packs.picture_decision().scale).override_failure_message("until the host has refused it, the mod's declared picture counts").is_equal(1)
	Mods.sync()
	assert_bool(ModHost.is_refused(broken.id)).is_true()
	assert_array(PackNeeds.picture_keys(Packs.chain())).not_contains([MOD_KEY])
	assert_int(Packs.picture_decision().scale).override_failure_message("a refused mod draws nothing: the set covers without its picture").is_equal(4)
	assert_array(Packs.picture_decision().shortfalls).is_empty()


func test_the_same_set_covers_when_no_mod_declares_the_key() -> void:
	var needed := PictureScale.needed(Packs.chain(), PackNeeds.picture_keys(Packs.chain()))
	var mod := _mod_pack(PackShelf.base_id(), [])
	var four := _hires_pack(mod.id, needed)
	four.mount()
	assert_int(Packs.picture_decision().scale).is_equal(4)


# --- the run -----------------------------------------------------------------------------------------------------------------------

func _sim() -> SimWorld:
	var sim := SimWorld.new(GameState)
	sim.load_sector(SECTOR, SCREEN)
	sim.foe_context.rng.seed = 4242
	sim.start_flight(200, 150, 6)
	sim.tick()
	return sim


## The skin fixture `skinny` with its skin's `picture_keys` set to `keys` (the rest of its manifest is the fixture's), laid over the suite's pack, chosen and synced.
func _skinny(keys: Array) -> PackShelf:
	var shelf := PackShelf.new()
	shelf.add_mod_fixture("%s/skinny" % ModSkinShelf.FIXTURES, {"skin": {"shaders": [ModSkinShelf.GLOW], "picture_keys": keys}})
	ModSkinShelf.add_files(shelf)
	shelf.mount()
	Mods.sync()
	_shelves.append(shelf)
	return shelf


func _presenter(sim: SimWorld, skin: GameSkin) -> OriginalPresenter:
	var presenter := (load("res://src/gameplay/original_presenter.tscn") as PackedScene).instantiate() as OriginalPresenter
	presenter.skin = skin
	auto_free(presenter)
	presenter.run_in_skin(func() -> void:
		add_child(presenter)
		presenter.bind(sim))
	return presenter


## The textures of the `picture` and `region` commands the presenter's mod layers hold.
func _textures(presenter: OriginalPresenter) -> Array[Texture2D]:
	var found: Array[Texture2D] = []
	for layer in presenter.mod_layers():
		for command: Array in layer.commands:
			if command[0] == "picture" or command[0] == "region":
				found.append(command[1])
	return found


func test_a_skin_that_draws_the_screen_by_the_keys_of_its_state_draws_them_when_it_declares_them() -> void:
	var skinny := _skinny(["background/*", "deco/*", "frame/*"])
	var skin := SkinChoice.load_skin(skinny.id) as ModSkin
	var state := SkinState.build(SimView.new(_sim()))
	var key := ""
	for layer: String in ["back_decos", "mid_decos", "front_decos"]:
		for each: String in state["decos"][layer]["key"]:
			if not each.is_empty() and key.is_empty():
				key = each
	assert_str(key).override_failure_message("the screen has a decoration to draw").is_not_empty()
	var presenter := _presenter(_sim(), skin)
	assert_bool(_textures(presenter).any(func(texture: Texture2D) -> bool: return texture == Assets.picture_by_key(key))).is_true()
	assert_array(_told("which its manifest does not declare")).is_empty()


func test_a_skin_that_names_a_picture_it_did_not_declare_draws_nothing_of_it_and_is_told_once() -> void:
	var skinny := _skinny(["background/*", "frame/*"])                                         # (the decorations are not declared)
	var skin := SkinChoice.load_skin(skinny.id) as ModSkin
	var state := SkinState.build(SimView.new(_sim()))
	var key := ""
	for layer: String in ["back_decos", "mid_decos", "front_decos"]:
		for each: String in state["decos"][layer]["key"]:
			if not each.is_empty() and key.is_empty():
				key = each
	assert_str(key).is_not_empty()
	var presenter := _presenter(_sim(), skin)
	assert_bool(_textures(presenter).any(func(texture: Texture2D) -> bool: return texture == Assets.picture_by_key(key))).override_failure_message("the undeclared decoration was drawn").is_false()
	var told := _told("its skin draw list names the picture 'deco/")
	assert_array(told).is_not_empty()
	assert_str(told[0]).contains("mod '%s'" % skinny.id).contains("does not declare in \"picture_keys\"").contains("that picture is not drawn")
	var count := TroubleLog.session.told.size()
	presenter.bind(_sim())                                                                    # (frames and binds again: the same causes are not told again)
	assert_int(TroubleLog.session.told.size()).is_equal(count)


func test_a_problem_screen_that_names_the_art_of_a_type_draws_it_only_when_it_declares_it() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/tides/pack.json" % ModProblemShelf.FIXTURES))
	var problems: Dictionary = (fixture["mod"]["problems"] as Dictionary).duplicate(true)
	problems.erase("picture_keys")
	var shelf := ModProblemShelf.mount_one("tides", {"problems": problems})
	_shelves.append(shelf)
	var screen: ProblemScreen = ProblemRunner.SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.start(ProblemFactory.make(ModProblemShelf.ORIGINAL, 0, null, 0))
	var diagram := screen.diagram as ModDiagram
	screen.advance_ticks(diagram.intro_length())
	var art := ProblemState.art_keys(Catalog.problem_type(ModProblemShelf.ORIGINAL))
	assert_array(art).is_not_empty()
	var drawn: Array[Texture2D] = []
	for layer in diagram.layers():
		for command: Array in layer.commands:
			if command[0] == "picture":
				drawn.append(command[1])
	assert_bool(drawn.any(func(texture: Texture2D) -> bool: return texture == Assets.picture_by_key(art[0]))).override_failure_message("an undeclared picture of the game was drawn").is_false()
	var told := _told("its problem screen draw list names the picture '%s'" % art[0])
	assert_array(told).has_size(1)
	assert_str(told[0]).contains("mod '%s'" % shelf.id).contains("that picture is not drawn")
	screen.free()
