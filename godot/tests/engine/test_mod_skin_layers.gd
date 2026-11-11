class_name TestModSkinLayers
extends GdUnitTestSuite
## Teaches: a skin mod that draws CHOSEN layers of the original presenter. The manifest names them (`script_layers`), the script is called for one layer at a time (`skin_layer(name, state, fraction, events)`) and answers with a draw list, and
## the original presenter hosts the answer (`ModLayerHost`): a stack of `ModLayer` nodes right behind the layer's node, which is made transparent while the answer is on. Every other layer stays the original's, and so does a layer whose script faults.
## The tests cover the manifest, the functions the script must define, which layers are asked for and what they are told, where the stacks stand (through a supply trip too), the fault policy a layer at a time, a script that draws every layer, and a
## skin bound in the middle of anything. That a skin mod changes nothing of the game is `test_plays_identically.gd` and `test_skins_dont_change_the_game.gd` (they play the fixtures `skin_layers` and `skin_layers_faulty`), and the whole-screen form
## (`skin_frame`, the same host with one slot over every layer) is in `test_mod_skin.gd`.
## These tests need the godot-sandbox extension (`uv run tools/fetch_sandbox.py`, docs/SETUP.md).

const PRESENTER_SCENE := "res://src/gameplay/original_presenter.tscn"
const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const FIXTURE := "res://tests/mods/skin_layers"
const DRAWN: Array[StringName] = [&"background", &"walls", &"bubbles"]

var _shelves: Array[PackShelf] = []


func before() -> void:
	assert_bool(ModLoader.sandbox_available()).override_failure_message("the godot-sandbox extension is not loaded: run `uv run tools/fetch_sandbox.py`, then `tools/godot.sh --headless --path godot --import` (docs/SETUP.md)").is_true()


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	SkinChoice.select(SkinChoice.original())
	ModSkinShelf.release(_shelves)
	SkinChoice.select(SkinChoice.original())
	GameState.reset()


## The fixture `skin_layers` as a mounted skin, with `mod` laid over its manifest's `mod` (a different list of layers).
func _mount(mod: Dictionary = {}) -> ModSkin:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture(FIXTURE, mod)
	ModSkinShelf.add_files(shelf)
	shelf.mount()
	Mods.sync()
	return SkinChoice.load_skin(shelf.id) as ModSkin


func _sim() -> SimWorld:
	var sim := SimWorld.new(GameState)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.foe_context.rng.seed = 4242
	sim.start_flight(200, 150, 6)
	sim.tick()
	return sim


func _presenter(sim: SimWorld, skin: GameSkin) -> OriginalPresenter:
	var presenter := (load(PRESENTER_SCENE) as PackedScene).instantiate() as OriginalPresenter
	presenter.skin = skin
	auto_free(presenter)
	presenter.run_in_skin(func() -> void:
		add_child(presenter)
		presenter.bind(sim))
	return presenter


func _parse(data: Variant) -> Array:
	var errors: Array[String] = []
	var spec := ModSpec.parse(data, errors)
	return [spec, errors]


## Is the original's layer `layer` on show (not made transparent by the script's answer)?
func _original_shows(presenter: OriginalPresenter, layer: StringName) -> bool:
	return presenter.layer_node(layer).modulate.a > 0.0


# --- the manifest --------------------------------------------------------------------------------------------------------

func test_the_manifest_names_the_layers_the_script_draws() -> void:
	var got := _parse({"entry": "a.sgd", "requires_api": 7, "skin": {"script_layers": ["background", "bubbles"]}})
	assert_array(got[1]).is_empty()
	var spec: ModSpec = got[0]
	assert_array(spec.script_layers).is_equal([&"background", &"bubbles"])
	assert_bool(spec.draws_frame()).is_false()
	assert_dict(spec.to_dict()).is_equal({"entry": "a.sgd", "requires_api": 7, "skin": {"script_layers": ["background", "bubbles"]}})
	assert_array(spec.functions().keys()).is_equal([ModSkin.LAYER_FUNCTION])
	assert_array(spec.functions()[ModSkin.LAYER_FUNCTION]).is_equal(["name", "state", "fraction", "events"])
	var whole: ModSpec = _parse({"entry": "a.sgd", "requires_api": 2, "skin": {}})[0]
	assert_bool(whole.draws_frame()).is_true()                                                         # (no `script_layers`: the script draws the whole screen)
	assert_array(whole.functions().keys()).is_equal([ModSkin.FRAME_FUNCTION])
	assert_int(ModSpec.API_VERSION).is_greater_equal(ModSpec.LAYER_API_VERSION)


func test_a_layer_the_script_draws_may_not_also_have_a_shader_in_the_manifest_but_the_others_may() -> void:
	var shaders := ["skin/glow.gdshader"]
	var dressed := _parse({"entry": "a.sgd", "requires_api": 7, "skin": {"shaders": shaders, "script_layers": ["background"], "layers": {"sub": {"shader": shaders[0]}}}})
	assert_array(dressed[1]).is_empty()
	assert_array((dressed[0] as ModSpec).layers.keys()).is_equal(["sub"])
	var clash := _parse({"entry": "a.sgd", "requires_api": 7, "skin": {"shaders": shaders, "script_layers": ["background"], "layers": {"background": {"shader": shaders[0]}}}})
	assert_object(clash[0]).is_null()
	assert_bool((clash[1] as Array[String]).any(func(e: String) -> bool: return e.contains("drawn by the script"))).is_true()


func test_every_mistake_in_script_layers_is_a_sentence() -> void:
	var bad := {
		"no entry": [{"requires_api": 7, "skin": {"script_layers": ["background"]}}, "belong to a skin with an \"entry\""],
		"an older API": [{"entry": "a.sgd", "requires_api": 6, "skin": {"script_layers": ["background"]}}, "requires_api"],
		"not a list": [{"entry": "a.sgd", "requires_api": 7, "skin": {"script_layers": "background"}}, "must be a list"],
		"an empty list": [{"entry": "a.sgd", "requires_api": 7, "skin": {"script_layers": []}}, "must be a list"],
		"a layer that is not one": [{"entry": "a.sgd", "requires_api": 7, "skin": {"script_layers": ["sky"]}}, "no layer \"sky\""],
		"a name that is a number": [{"entry": "a.sgd", "requires_api": 7, "skin": {"script_layers": [3]}}, "no layer 3"],
		"a layer twice": [{"entry": "a.sgd", "requires_api": 7, "skin": {"script_layers": ["walls", "walls"]}}, "twice"],
		"the debug overlay": [{"entry": "a.sgd", "requires_api": 7, "skin": {"script_layers": ["currents"]}}, "no layer \"currents\""],
		"layers of a script that draws the whole screen": [{"entry": "a.sgd", "requires_api": 7, "skin": {"shaders": ["skin/a.gdshader"], "layers": {"sub": {"shader": "skin/a.gdshader"}}}}, "script_layers"],
	}
	for what: String in bad:
		var got := _parse(bad[what][0])
		assert_object(got[0]).override_failure_message("%s was accepted" % what).is_null()
		assert_bool((got[1] as Array[String]).any(func(e: String) -> bool: return e.contains(bad[what][1]))).override_failure_message("%s: %s" % [what, got[1]]).is_true()


func test_a_skin_whose_script_lacks_skin_layer_is_refused_and_the_check_says_so() -> void:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture(FIXTURE)
	ModSkinShelf.add_files(shelf)
	shelf.write_text("skin_layers.sgd", "var api = {}\nfunc mod_init(a):\n\tapi = a\nfunc skin_frame(state, fraction, events):\n\treturn []\n")      # (the other function: not what the manifest asks)
	var options := PackCheck.Options.new()
	options.reach = false
	assert_bool(PackCheck.run(Pack.open(shelf.root), options).errors().any(func(f: PackReport.Finding) -> bool: return f.message.contains("skin_layer(name, state, fraction, events)"))).is_true()
	shelf.mount()
	Mods.sync()
	assert_str(ModHost.failure(String(shelf.id))).contains("skin_layer")
	assert_array(Mods.loaded_ids()).not_contains([String(shelf.id)])


func test_the_skin_knows_what_its_script_draws() -> void:
	var skin := _mount()
	assert_array(skin.script_layers).is_equal(DRAWN)
	assert_bool(skin.draws_frame).is_false()
	assert_bool(skin.is_scripted()).is_true()
	assert_array(skin.layer_materials.keys()).is_equal([&"sub"])                                       # (the manifest's `layers`: a shader on a layer the script leaves alone)
	assert_object(skin.presenter_scene_or_null()).is_null()                                            # (its sector is the original presenter's)


# --- what the script is asked, what it draws ---------------------------------------------------------------------------

func test_the_script_is_asked_for_the_layers_it_names_and_for_no_other() -> void:
	var skin := _mount()
	var mod := ModHost.mod(String(skin.id))
	var sim := _sim()
	var presenter := _presenter(sim, skin)
	sim.tick()                                                                                          # (an event the presenter hears: the script is told of it)
	presenter.show_between_ticks(0.5)
	assert_array(mod.call("asked_layers")).is_equal(["background", "walls", "bubbles"])
	assert_array(presenter.mod_answered_layers()).is_equal(DRAWN)
	assert_array(mod.call("heard_events")).contains(["ticked"])


func test_each_layer_is_drawn_behind_its_own_node_and_the_original_of_that_layer_is_hidden() -> void:
	var skin := _mount()
	var presenter := _presenter(_sim(), skin)
	presenter.show_between_ticks(0.5)
	for layer in SkinLayers.NODES:
		assert_bool(_original_shows(presenter, layer)).override_failure_message("the layer %s" % layer).is_equal(not DRAWN.has(layer))
	for layer in DRAWN:
		var node := presenter.layer_node(layer)
		var behind := presenter.get_child(node.get_index() + 1)
		assert_object(behind).override_failure_message("what stands behind %s" % layer).is_instanceof(ModLayerStack)
		assert_str(behind.name).is_equal("Mod" + String(layer).capitalize().replace(" ", ""))
	var walls := presenter.layer_node(&"walls").get_index()
	assert_object(presenter.get_child(walls + 2)).override_failure_message("the next layer follows the stack").is_not_instanceof(ModLayerStack)
	assert_str(String(presenter.get_child(walls + 2).name)).is_equal("Currents")                  # (the debug overlay of the water currents)
	assert_array(presenter.mod_drawn()).is_not_empty()
	assert_int(presenter.mod_layers().size()).is_equal(3)


func test_the_layers_the_script_draws_are_the_scripts_and_the_others_are_the_originals() -> void:
	var skin := _mount()
	var sim := _sim()
	var presenter := _presenter(sim, skin)
	presenter.show_between_ticks(0.5)
	var by_layer := {}
	for layer in DRAWN:
		var stack := presenter.get_child(presenter.layer_node(layer).get_index() + 1) as ModLayerStack
		by_layer[layer] = stack.layers().map(func(l: ModLayer) -> Array: return l.commands).reduce(func(a: Array, b: Array) -> Array: return a + b, [])
	var rects := (by_layer[&"walls"] as Array).filter(func(c: Array) -> bool: return c[0] == "rect")
	var solid := 0
	for row in TileGrid.ROWS:
		for column in TileGrid.COLUMNS:
			solid += 1 if presenter.view.is_solid(column, row) else 0
	var covered := 0
	for rect in rects:
		covered += int((rect[1] as Rect2).get_area() / (TileGrid.TILE_SIZE * TileGrid.TILE_SIZE))
	assert_int(solid).is_greater(0)
	assert_int(covered).override_failure_message("the walls it drew are the tiles the rules treat as solid").is_equal(solid)
	assert_int((by_layer[&"bubbles"] as Array).size()).is_equal(8)
	assert_int((by_layer[&"background"] as Array).size()).is_greater_equal(1)
	var dots: Array = by_layer[&"bubbles"]
	var first := (dots[0][2] as Vector2).y
	sim.tick()
	sim.tick()
	presenter.show_between_ticks(0.5)
	var again := ((presenter.get_child(presenter.layer_node(&"bubbles").get_index() + 1) as ModLayerStack).layers()[0].commands[0][2] as Vector2).y
	assert_float(again).override_failure_message("the bubbles rise with the game's time").is_less(first)
	assert_object(presenter.sub).is_not_null()
	assert_bool(presenter.sub.visible).is_true()                                                       # (the original's sub and creatures are there)
	assert_int(presenter.foes_layer.get_child_count()).is_greater(0)


func test_a_layer_the_manifest_dresses_keeps_its_shader_next_to_a_layer_the_script_draws() -> void:
	var skin := _mount()
	var presenter := _presenter(_sim(), skin)
	presenter.show_between_ticks(0.5)
	var material := presenter.layer_node(&"sub").material as ShaderMaterial
	assert_object(material).is_not_null()
	assert_that(material.get_shader_parameter("tint")).is_equal(Color("#ff8800"))
	assert_object(presenter.layer_node(&"walls").material).is_null()


# --- where the stacks stand ---------------------------------------------------------------------------------------------

func test_the_stacks_keep_their_place_behind_their_layers_through_a_supply_trip() -> void:
	var skin := _mount({"skin": {"script_layers": ["station", "mid_decos", "collectibles", "sub"]}})
	var sim := SimWorld.new(GameState)
	var presenter := _presenter(sim, skin)
	sim.load_sector(DevCreatures.ARENA, SimWorld.DOCK_SCREEN)
	sim.start_flight(400, 200, 6)
	sim.tick()
	for moment in ["in play", "a dock", "a launch"]:
		if moment == "a dock":
			sim.start_dock()
			sim.tick()
		elif moment == "a launch":
			while not sim.sequence.is_done():
				sim.tick()
			sim.load_sector(DevCreatures.ARENA, 0)
			sim.start_launch()
			sim.tick()
		presenter.show_between_ticks(0.5)
		for layer: StringName in [&"station", &"mid_decos", &"collectibles", &"sub"]:
			var node := presenter.layer_node(layer)
			assert_object(presenter.get_child(node.get_index() + 1)).override_failure_message("%s: what is behind %s" % [moment, layer]).is_instanceof(ModLayerStack)
			assert_str(String(presenter.get_child(node.get_index() + 1).name)).override_failure_message("%s: the stack of %s" % [moment, layer]).is_equal("Mod" + String(layer).capitalize().replace(" ", ""))
		var order := presenter.get_children().filter(func(n: Node) -> bool: return not n is ModLayerStack).map(func(n: Node) -> String: return String(n.name))
		if moment == "in play":
			assert_bool(order.find("Station") < order.find("MidDecos") and order.find("MidDecos") < order.find("Collectibles") and order.find("Collectibles") < order.find("Sub")).is_true()
		else:
			assert_bool(order.find("MidDecos") < order.find("Sub") and order.find("Sub") < order.find("Station") and order.find("Station") < order.find("Collectibles")).override_failure_message(moment).is_true()


func test_a_script_that_draws_every_layer_is_this_host_with_every_name() -> void:
	var skin := _mount({"skin": {"script_layers": SkinLayers.NODES.keys().map(func(k: StringName) -> String: return String(k))}})
	var mod := ModHost.mod(String(skin.id))
	var presenter := _presenter(_sim(), skin)
	presenter.show_between_ticks(0.5)
	assert_int(skin.script_layers.size()).is_equal(SkinLayers.NODES.size())
	assert_array(mod.call("asked_layers")).is_equal(SkinLayers.NODES.keys().map(func(k: StringName) -> String: return String(k)))
	for layer in SkinLayers.NODES:
		assert_bool(_original_shows(presenter, layer)).override_failure_message("the layer %s" % layer).is_false()           # (the script answered for each, with nothing for most)
	assert_array(presenter.mod_answered_layers()).is_equal(SkinLayers.NODES.keys())


# --- the fault policy -----------------------------------------------------------------------------------------------------

func test_a_layer_that_faults_is_the_originals_and_the_other_layers_of_the_script_go_on() -> void:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture("res://tests/mods/skin_layers_faulty")
	ModSkinShelf.add_files(shelf)
	shelf.mount()
	Mods.sync()
	var skin := SkinChoice.load_skin(shelf.id)
	var mod := ModHost.mod(String(shelf.id))
	var faults := int(mod.get("monitor_exceptions"))
	var presenter := _presenter(_sim(), skin)
	for i in 3:
		presenter.show_between_ticks(0.5)
	assert_int(int(mod.get("monitor_exceptions"))).is_greater(faults)
	assert_array(presenter.mod_answered_layers()).is_equal([&"background"])
	assert_bool(_original_shows(presenter, &"background")).is_false()                                   # (answered: the script's)
	assert_bool(_original_shows(presenter, &"walls")).override_failure_message("a layer that never answered shows the original").is_true()
	Mods.loader().forgive(String(shelf.id))


func test_a_quarantined_skin_leaves_every_layer_the_originals() -> void:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture("res://tests/mods/skin_layers_faulty")
	ModSkinShelf.add_files(shelf)
	shelf.mount()
	Mods.sync()
	var presenter := _presenter(_sim(), SkinChoice.load_skin(shelf.id))
	for i in ModLoader.MAX_FAULTS + 2:
		presenter.show_between_ticks(0.5)
	assert_array(presenter.mod_answered_layers()).is_equal([&"background"])
	Mods.loader().check_health()
	assert_bool(ModHost.is_quarantined(String(shelf.id))).is_true()
	presenter.show_between_ticks(0.5)
	assert_array(presenter.mod_answered_layers()).is_empty()
	for layer in SkinLayers.NODES:
		assert_bool(_original_shows(presenter, layer)).override_failure_message("the layer %s" % layer).is_true()
	assert_array(presenter.mod_layers().filter(func(l: ModLayer) -> bool: return not l.commands.is_empty())).is_empty()
	Mods.loader().resume(String(shelf.id))
	Mods.loader().forgive(String(shelf.id))
	presenter.show_between_ticks(0.5)                                                                   # (let run again: the script is asked again)
	assert_array(presenter.mod_answered_layers()).is_equal([&"background"])
	Mods.loader().forgive(String(shelf.id))


func test_a_mod_that_has_gone_leaves_every_layer_the_originals() -> void:
	var skin := _mount()
	var presenter := _presenter(_sim(), skin)
	presenter.show_between_ticks(0.5)
	assert_array(presenter.mod_answered_layers()).is_equal(DRAWN)
	ModSkinShelf.release(_shelves)
	presenter.show_between_ticks(0.5)
	assert_array(presenter.mod_answered_layers()).is_empty()
	for layer in SkinLayers.NODES:
		assert_bool(_original_shows(presenter, layer)).is_true()
	presenter.unbind()


func test_a_presenter_that_lets_the_mod_go_shows_the_originals_and_keeps_no_stack() -> void:
	var skin := _mount()
	var presenter := _presenter(_sim(), skin)
	presenter.show_between_ticks(0.5)
	assert_array(presenter.get_children().filter(func(n: Node) -> bool: return n is ModLayerStack)).has_size(3)
	presenter.unbind()
	assert_bool(presenter.hosts_mod_layers()).is_false()
	await await_idle_frame()
	assert_array(presenter.get_children().filter(func(n: Node) -> bool: return n is ModLayerStack)).is_empty()
	for layer in SkinLayers.NODES:
		assert_bool(_original_shows(presenter, layer)).is_true()


# --- bound in the middle of anything ---------------------------------------------------------------------------------------

func test_a_skin_bound_late_shows_what_one_bound_from_the_start_shows() -> void:
	var skin := _mount()
	var sim := SimWorld.new(GameState)
	var early := _presenter(sim, skin)
	sim.load_sector(100, 6)                                                                             # (the dev pack's sector with decorations in every layer)
	sim.foe_context.rng.seed = 4242
	sim.start_flight(200, 150, 6)
	for i in 7:
		sim.tick()
	sim.tick(InputSnapshot.firing())
	var late := _presenter(sim, skin)
	for presenter: OriginalPresenter in [early, late]:
		presenter.show_between_ticks(0.5)
	assert_array(late.mod_drawn()).is_not_empty()
	assert_array(late.mod_drawn()).is_equal(early.mod_drawn())
	assert_array(late.mod_answered_layers()).is_equal(early.mod_answered_layers())
	for layer in SkinLayers.NODES:
		assert_bool(_original_shows(late, layer)).is_equal(_original_shows(early, layer))


func test_the_skin_is_worn_by_the_world_through_the_original_presenter() -> void:
	var skin := _mount()
	SkinChoice.select(skin)
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	assert_str(String(PresenterChoice.kind_of(world.presenter))).is_equal(String(PresenterChoice.ORIGINAL))
	assert_bool(world.original.hosts_mod_layers()).is_true()
	SkinChoice.select(SkinChoice.original())
	assert_bool(world.original.hosts_mod_layers()).is_false()
	for layer in SkinLayers.NODES:
		assert_bool(_original_shows(world.original, layer)).is_true()


func test_the_rules_run_the_same_whatever_the_script_draws() -> void:
	var skin := _mount()
	var traces: Array = []
	for worn: GameSkin in [null, skin]:
		GameState.reset()
		var sim := SimWorld.new(GameState)
		var presenter: OriginalPresenter = null
		if worn != null:
			presenter = _presenter(sim, worn)
		sim.load_sector(DevCreatures.ARENA, 0)
		sim.foe_context.rng.seed = 4242
		sim.start_flight(200, 150, 6)
		var lines: Array[String] = []
		for t in 120:
			sim.tick(InputSnapshot.firing() if t % 7 == 0 else InputSnapshot.new())
			if presenter != null:
				presenter.show_between_ticks(0.5)
			lines.append("%s %s %s" % [sim.sub.position, sim.foes.map(func(f: FoeModel) -> Vector2i: return Vector2i(f.vm.x, f.vm.y)), sim.pellets.size()])
		traces.append(lines)
		if presenter != null:
			presenter.unbind()
	assert_array(traces[1]).is_equal(traces[0])


# --- the document ---------------------------------------------------------------------------------------------------------

func test_the_document_names_the_layers_the_function_and_the_version() -> void:
	var doc := FileAccess.get_file_as_string("res://../docs/create/SKIN_API.md")
	doc = doc.substr(doc.find("## Writing a skin mod"))
	assert_str(doc).is_not_empty()
	for layer in SkinLayers.NODES:
		assert_bool(doc.contains("`%s`" % layer)).override_failure_message("SKIN_API.md does not name the layer `%s`" % layer).is_true()
	for part in ["script_layers", "skin_layer(name, state, fraction, events)", "skin_frame", "\"requires_api\": %d" % ModSpec.LAYER_API_VERSION]:
		assert_bool(doc.contains(part)).override_failure_message("SKIN_API.md does not mention %s" % part).is_true()
