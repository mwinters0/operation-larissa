class_name TestModSkinHud
extends GdUnitTestSuite
## Teaches: a skin mod that draws parts of the CONSOLE with the very host that draws the sector's layers. The manifest names a console layer in `script_layers` like any other (`hud_oxygen`, or `hud` for all of it), `Hud` makes a `ModLayerHost` for the skin
## it wears (`ModLayerHost.make_hud`: the same host the original presenter makes, standing on the HUD), the script is asked for it with the console's state (`ConsoleState.build`, built again every frame) and what it draws is cut to the part's rectangle. The tests
## cover the manifest, where the stacks stand, what the script is told (the rectangles, the blink), the original's nodes under a part the script draws, the clip, the fault policy a part at a time, a skin put on and taken off while the HUD runs, a console
## made in the middle of anything, and that drawing the console changes nothing of the game. The sector's layers are `test_mod_skin_layers.gd`; every skin of the roster (this one too) is held to the promises of skins in `test_plays_identically.gd`,
## `test_skins_dont_change_the_game.gd` and `test_presenter_binds_late.gd`.
## These tests need the godot-sandbox extension (`uv run tools/fetch_sandbox.py`, docs/SETUP.md).

const HUD_SCENE := "res://src/ui/hud.tscn"
const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const FIXTURE := "res://tests/mods/skin_hud"
const FAULTY := "res://tests/mods/skin_hud_faulty"
const DRAWN: Array[StringName] = [&"hud_bezel", &"hud_tanks", &"hud_oxygen", &"hud_ink", &"hud_zone", &"hud_ship"]

var _shelves: Array[PackShelf] = []


func before() -> void:
	assert_bool(ModLoader.sandbox_available()).override_failure_message("the godot-sandbox extension is not loaded: run `uv run tools/fetch_sandbox.py`, then `tools/godot.sh --headless --path godot --import` (docs/SETUP.md)").is_true()


func before_test() -> void:
	GameClock.paused = true
	SkinChoice.select(SkinChoice.original())
	GameState.reset()
	GameState.customized = false
	GameState.set_sector(0, 9)


func after_test() -> void:
	GameClock.paused = false
	SkinChoice.select(SkinChoice.original())
	ModSkinShelf.release(_shelves)
	SkinChoice.select(SkinChoice.original())
	GameState.reset()
	GameState.customized = false
	GameState.sector = -1
	GameState.piece_total = 0


## A fixture as a mounted skin, with `mod` laid over its manifest's `mod` (another list of layers).
func _mount(fixture: String = FIXTURE, mod: Dictionary = {}) -> ModSkin:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture(fixture, mod)
	ModSkinShelf.add_files(shelf)
	shelf.mount()
	Mods.sync()
	return SkinChoice.load_skin(shelf.id) as ModSkin


## The game's HUD wearing `skin` (the skin in use when it is made).
func _hud(skin: GameSkin = null) -> Hud:
	if skin != null:
		SkinChoice.select(skin)
	return scene_runner(HUD_SCENE).scene() as Hud


func _parse(data: Variant) -> Array:
	var errors: Array[String] = []
	var spec := ModSpec.parse(data, errors)
	return [spec, errors]


## Is the original's node `node_name` of the HUD on show (not made transparent by the script's answer)?
func _original_shows(hud: Hud, node_name: String) -> bool:
	return (hud.get_node("%" + node_name) as CanvasItem).modulate.a > 0.0


## The nodes of the HUD that are the original's, by layer: what the script's answer hides.
func _originals(layer: StringName) -> Array[String]:
	return SkinLayers.hud_node_names(layer)


func _stack_of(hud: Hud, layer: StringName) -> ModLayerStack:
	for clip: Node in hud.get_children():
		if clip.name == "Mod%sClip" % String(layer).capitalize().replace(" ", ""):
			return clip.get_child(0) as ModLayerStack
	return null


func _commands(stack: ModLayerStack) -> Array:
	return stack.layers().map(func(l: ModLayer) -> Array: return l.commands).reduce(func(a: Array, b: Array) -> Array: return a + b, [])


# --- the manifest --------------------------------------------------------------------------------------------------------

func test_the_manifest_names_parts_of_the_console_among_the_layers_the_script_draws() -> void:
	var got := _parse({"entry": "a.sgd", "requires_api": 8, "skin": {"script_layers": ["background", "hud_oxygen", "hud_ship"]}})
	assert_array(got[1]).is_empty()
	var spec: ModSpec = got[0]
	assert_array(spec.script_layers).is_equal([&"background", &"hud_oxygen", &"hud_ship"])
	assert_bool(spec.draws_frame()).is_false()
	assert_dict(spec.to_dict()).is_equal({"entry": "a.sgd", "requires_api": 8, "skin": {"script_layers": ["background", "hud_oxygen", "hud_ship"]}})
	assert_array(spec.functions().keys()).is_equal([ModSkin.LAYER_FUNCTION])
	var whole: ModSpec = _parse({"entry": "a.sgd", "requires_api": 8, "skin": {"script_layers": ["hud"]}})[0]
	assert_array(whole.script_layers).is_equal([&"hud"])
	assert_int(ModSpec.API_VERSION).is_greater_equal(ModSpec.HUD_API_VERSION)
	assert_array(SkinLayers.hud_layers()).is_equal([&"hud", &"hud_bezel", &"hud_tanks", &"hud_oxygen", &"hud_ink", &"hud_game", &"hud_custom", &"hud_zone", &"hud_sector", &"hud_ship", &"hud_computer"])


func test_every_mistake_about_the_consoles_layers_is_a_sentence() -> void:
	var bad := {
		"an API without the console": [{"entry": "a.sgd", "requires_api": 7, "skin": {"script_layers": ["hud_oxygen"]}}, "needs \"requires_api\": 8"],
		"the whole and a part": [{"entry": "a.sgd", "requires_api": 8, "skin": {"script_layers": ["hud", "hud_ink"]}}, "the whole console"],
		"a part twice": [{"entry": "a.sgd", "requires_api": 8, "skin": {"script_layers": ["hud_ink", "hud_ink"]}}, "twice"],
		"a part that is not one": [{"entry": "a.sgd", "requires_api": 8, "skin": {"script_layers": ["hud_frame"]}}, "no layer \"hud_frame\""],
		"a shader on a part": [{"entry": "a.sgd", "requires_api": 8, "skin": {"shaders": ["skin/a.gdshader"], "script_layers": ["hud_ink"], "layers": {"hud_ink": {"shader": "skin/a.gdshader"}}}}, "no layer \"hud_ink\""],
	}
	for what: String in bad:
		var got := _parse(bad[what][0])
		assert_object(got[0]).override_failure_message("%s was accepted" % what).is_null()
		assert_bool((got[1] as Array[String]).any(func(e: String) -> bool: return e.contains(bad[what][1]))).override_failure_message("%s: %s" % [what, got[1]]).is_true()


func test_the_skin_splits_its_layers_between_the_two_screens() -> void:
	var skin := _mount()
	assert_array(skin.script_layers).is_equal([&"bubbles", &"hud_bezel", &"hud_tanks", &"hud_oxygen", &"hud_ink", &"hud_zone", &"hud_ship"])
	assert_array(skin.presenter_layers()).is_equal([&"bubbles"])
	assert_array(skin.hud_layers()).is_equal(DRAWN)
	assert_bool(skin.draws_frame).is_false()
	var only := _mount(FIXTURE, {"skin": {"script_layers": ["hud_ink"]}})
	assert_array(only.presenter_layers()).is_empty()
	assert_array(only.hud_layers()).is_equal([&"hud_ink"])


# --- where the stacks stand, what the script is asked and told ----------------------------------------------------------------

func test_each_part_is_drawn_behind_its_own_nodes_and_cut_to_its_rectangle() -> void:
	var hud := _hud(_mount())
	hud.show_mod_layers(0.5)
	assert_bool(hud.hosts_mod_layers()).is_true()
	var rects := ConsoleState.rects(hud.layout)
	for layer in DRAWN:
		var last := hud.layer_nodes(layer).back() as Node
		var clip := hud.get_child(last.get_index() + 1) as Control
		assert_object(clip).override_failure_message("what stands behind %s" % layer).is_not_null()
		assert_str(String(clip.name)).is_equal("Mod%sClip" % String(layer).capitalize().replace(" ", ""))
		assert_bool(clip.clip_contents).is_true()
		assert_object(Rect2(clip.position, clip.size)).override_failure_message("the clip of %s" % layer).is_equal(rects[String(layer)])
		assert_object(clip.get_child(0)).is_instanceof(ModLayerStack)
		assert_object((clip.get_child(0) as Node2D).position).override_failure_message("the script draws in window pixels").is_equal(-rects[String(layer)].position)
		assert_int(clip.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	var order := hud.get_children().map(func(n: Node) -> String: return String(n.name))
	assert_bool(order.find("ModHudShipClip") < order.find("Frame")).override_failure_message("the frame of the console is painted last: %s" % [order]).is_true()
	assert_str(order[order.find("ShipGlow") + 1]).is_equal("ModHudShipClip")


func test_the_script_is_asked_for_each_layer_of_its_screen_and_told_the_state_of_the_console() -> void:
	var skin := _mount()
	var mod := ModHost.mod(String(skin.id))
	var hud := _hud(skin)
	hud.show_mod_layers(0.5)
	assert_array(mod.call("asked_layers")).is_equal(["hud_bezel", "hud_tanks", "hud_oxygen", "hud_ink", "hud_zone", "hud_ship"])      # (the sector's `bubbles` is the presenter's to ask for)
	var keys: Array = mod.call("console_keys")
	assert_array(keys).contains_exactly_in_any_order(ConsoleState.build(hud.layout, null).keys())
	assert_array(hud.mod_host().answered_layers()).is_equal(DRAWN)


func test_the_original_of_a_part_is_hidden_while_the_script_draws_it_and_the_rest_is_shown() -> void:
	var hud := _hud(_mount())
	hud.show_mod_layers(0.5)
	for layer in SkinLayers.HUD_NODES:
		for node_name in _originals(layer):
			assert_bool(_original_shows(hud, node_name)).override_failure_message("%s of %s" % [node_name, layer]).is_equal(not DRAWN.has(layer))
	assert_bool(hud.frame.modulate.a > 0.0).is_true()
	assert_bool(hud.ship_light.visible).is_true()                                       # (the HUD's own state goes on under the script's picture)
	assert_int(hud.oxygen.value).is_equal(GameState.oxygen())


func test_the_script_draws_from_the_console_state_and_what_it_draws_follows_the_game() -> void:
	var hud := _hud(_mount())
	hud.show_mod_layers(0.5)
	var tanks: Array = _commands(_stack_of(hud, &"hud_tanks")).filter(func(c: Array) -> bool: return c[0] == "rect")
	assert_int(tanks.size()).is_equal(hud.layout.tank_positions.size())
	var full := tanks.filter(func(c: Array) -> bool: return (c[2] as Color).g > 0.5).size()
	assert_int(full).is_equal(GameState.tanks())
	GameState.fire_ink()
	hud.show_mod_layers(0.5)
	var ink: Array = _commands(_stack_of(hud, &"hud_ink"))
	assert_int(ink.filter(func(c: Array) -> bool: return c[2] == Color.BLACK).size()).is_equal(GameState.ink)
	var zone: Array = _commands(_stack_of(hud, &"hud_zone"))
	assert_str(zone.filter(func(c: Array) -> bool: return c[0] == "text")[0][1]).is_equal(ConsoleState.labels(hud.layout, null)["zone"]["word"])
	GameState.sector = -1                                                                 # (no sector: the zone label has nothing to say, and the script draws nothing for it)
	hud.show_mod_layers(0.5)
	assert_array(_commands(_stack_of(hud, &"hud_zone"))).is_empty()


func test_the_blink_is_the_huds_own_and_the_script_is_told_where_it_is() -> void:
	var skin := _mount()
	var mod := ModHost.mod(String(skin.id))
	var hud := _hud(skin)
	hud.show_mod_layers(0.5)
	var light := func() -> Color: return _commands(_stack_of(hud, &"hud_ship")).filter(func(c: Array) -> bool: return c[0] == "rect")[1][2]
	assert_float(light.call().a).override_failure_message("a light that is off").is_equal(1.0)
	GameState.set_message_light(true, false)
	hud.show_mod_layers(0.5)
	assert_float(light.call().a).is_equal_approx(0.4, 0.001)                              # (phase 0: the glow starts at its brightest in the original's own animation, the script's alpha is `0.4 + 0.6 * phase`)
	hud.light_animations.advance(0.125)                                                   # (a quarter of the 0.5 s blink)
	hud.show_mod_layers(0.5)
	assert_float(light.call().a).is_equal_approx(0.4 + 0.6 * 0.25, 0.001)
	assert_float(hud.console_state()["lights"]["ship"]["phase"]).is_equal_approx(0.25, 0.001)
	GameState.update_oxygen(-(GameState.oxygen() - ConsoleState.LOW_OXYGEN))              # (one cell left: the warning cell pulses, 0.8 s a cycle)
	hud.air_animations.advance(0.4)
	hud.show_mod_layers(0.5)
	assert_float(float(mod.call("oxygen_phase"))).is_equal_approx(0.5, 0.001)
	GameState.update_oxygen(1)
	hud.show_mod_layers(0.5)
	assert_float(float(mod.call("oxygen_phase"))).is_equal(0.0)


func test_the_whole_console_is_one_layer_over_every_part() -> void:
	var skin := _mount(FIXTURE, {"skin": {"script_layers": ["hud"]}})
	var hud := _hud(skin)
	hud.show_mod_layers(0.5)
	assert_array(hud.mod_host().answered_layers()).is_equal([&"hud"])
	for node_name in _originals(SkinLayers.HUD):
		assert_bool(_original_shows(hud, node_name)).override_failure_message(node_name).is_false()
	assert_bool(_original_shows(hud, "ShipGlow")).is_false()
	var clip := hud.get_child(hud.computer_glow.get_index() + 1) as Control
	assert_object(Rect2(clip.position, clip.size)).is_equal(ConsoleState.rects(hud.layout)["hud"])
	assert_array(ModHost.mod(String(skin.id)).call("asked_layers")).is_equal(["hud"])


func test_the_hud_does_no_work_in_process_without_a_script_that_draws_it() -> void:
	var hud := _hud()
	assert_bool(hud.hosts_mod_layers()).is_false()
	assert_bool(hud.is_processing()).is_false()
	var worn := _hud(_mount())
	assert_bool(worn.is_processing()).is_true()
	var data_only := _hud(_mount(FIXTURE, {"skin": {"script_layers": ["bubbles"]}}))          # (a script that draws only the sector: nothing of the console)
	assert_bool(data_only.hosts_mod_layers()).is_false()


# --- two screens, one skin -------------------------------------------------------------------------------------------------

func test_a_skin_that_draws_both_screens_has_a_host_on_each() -> void:
	var skin := _mount()
	SkinChoice.select(skin)
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	var hud := _hud()
	assert_bool(world.original.hosts_mod_layers()).is_true()
	assert_bool(hud.hosts_mod_layers()).is_true()
	assert_array(world.original.mod_drawn()).is_not_empty()
	assert_bool(world.original.mod_drawn().any(func(line: String) -> bool: return line.contains("hud"))).override_failure_message("the presenter asked for a layer of the console").is_false()
	var only := _mount(FIXTURE, {"skin": {"script_layers": ["hud_ink"]}})
	SkinChoice.select(only)
	assert_bool(world.original.hosts_mod_layers()).override_failure_message("a skin with only console layers has no host on the presenter").is_false()
	assert_bool(hud.hosts_mod_layers()).is_true()
	hud.show_mod_layers(0.5)
	assert_bool(_original_shows(hud, "Ink")).is_false()
	assert_bool(_original_shows(hud, "Tanks")).is_true()


func test_another_skin_takes_the_script_away_and_the_originals_are_back() -> void:
	var skin := _mount()
	var hud := _hud()
	assert_bool(hud.hosts_mod_layers()).is_false()
	SkinChoice.select(skin)
	hud.show_mod_layers(0.5)
	assert_bool(hud.hosts_mod_layers()).is_true()
	assert_array(hud.mod_host().answered_layers()).is_equal(DRAWN)
	SkinChoice.select(SkinChoice.original())
	assert_bool(hud.hosts_mod_layers()).is_false()
	for layer in SkinLayers.HUD_NODES:
		for node_name in _originals(layer):
			assert_bool(_original_shows(hud, node_name)).override_failure_message(node_name).is_true()
	await await_idle_frame()
	assert_array(hud.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with("Mod"))).is_empty()
	assert_bool(hud.is_processing()).is_false()


# --- the fault policy ---------------------------------------------------------------------------------------------------------

func test_a_part_that_faults_is_the_originals_and_the_other_parts_of_the_script_go_on() -> void:
	var skin := _mount(FAULTY)
	var mod := ModHost.mod(String(skin.id))
	var faults := int(mod.get("monitor_exceptions"))
	var hud := _hud(skin)
	for i in 3:
		hud.show_mod_layers(0.5)
	assert_int(int(mod.get("monitor_exceptions"))).is_greater(faults)
	assert_array(hud.mod_host().answered_layers()).is_equal([&"hud_bezel"])
	assert_bool(_original_shows(hud, "Bezel")).is_false()
	assert_bool(_original_shows(hud, "Oxygen")).override_failure_message("a part that never answered shows the original").is_true()
	Mods.loader().forgive(String(skin.id))


func test_a_quarantined_skin_leaves_every_part_the_originals_and_the_original_skin_is_put_on() -> void:
	var skin := _mount(FAULTY)
	var hud := _hud(skin)
	for i in ModLoader.MAX_FAULTS + 2:
		hud.show_mod_layers(0.5)
	assert_array(hud.mod_host().answered_layers()).is_equal([&"hud_bezel"])
	Mods.loader().check_health()
	assert_bool(ModHost.is_quarantined(String(skin.id))).is_true()
	assert_bool(SkinChoice.current().id == SkinChoice.ORIGINAL).override_failure_message("`SkinChoice` puts the original skin on").is_true()
	assert_bool(hud.hosts_mod_layers()).is_false()                                        # (the HUD heard the change)
	for node_name in _originals(SkinLayers.HUD):
		assert_bool(_original_shows(hud, node_name)).override_failure_message(node_name).is_true()
	Mods.loader().resume(String(skin.id))
	Mods.loader().forgive(String(skin.id))
	SkinChoice.select(skin)                                                               # (let run again: chosen again, the script is asked again)
	hud.show_mod_layers(0.5)
	assert_array(hud.mod_host().answered_layers()).is_equal([&"hud_bezel"])
	Mods.loader().forgive(String(skin.id))


func test_a_mod_that_has_gone_leaves_every_part_the_originals() -> void:
	var skin := _mount()
	var hud := _hud(skin)
	hud.show_mod_layers(0.5)
	assert_array(hud.mod_host().answered_layers()).is_equal(DRAWN)
	ModSkinShelf.release(_shelves)
	hud.show_mod_layers(0.5)
	for layer in SkinLayers.HUD_NODES:
		for node_name in _originals(layer):
			assert_bool(_original_shows(hud, node_name)).override_failure_message(node_name).is_true()


# --- bound in the middle of anything ---------------------------------------------------------------------------------------

## What the script draws on a HUD and what is hidden under it, as lines: the layers it answered and the commands, and the original's parts that show.
func _shown(hud: Hud) -> Array:
	var shows := {}
	for layer in SkinLayers.HUD_NODES:
		shows[layer] = _originals(layer).all(func(node_name: String) -> bool: return _original_shows(hud, node_name))
	return [hud.mod_host().lines(), hud.mod_host().answered_layers(), shows, [hud.tanks.value, hud.oxygen.value, hud.ink.value]]


func test_a_console_made_in_the_middle_draws_what_the_first_one_draws() -> void:
	var skin := _mount()
	SkinChoice.select(skin)
	var sim := SimWorld.new(GameState)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.foe_context.rng.seed = 4242
	sim.start_flight(200, 150, 6)
	var first := _hud()
	var steps: Array[Callable] = [
		func() -> void: sim.tick(InputSnapshot.firing()),
		func() -> void: GameState.update_oxygen(-3),
		func() -> void: GameState.set_message_light(true, false),
		func() -> void: GameState.collect_piece(2),
		func() -> void: GameState.set_sector(2, 8),
		func() -> void: GameState.customized = true,
		func() -> void: GameState.update_oxygen(-1),
		func() -> void: GameState.set_message_light(false, false),
		func() -> void: GameState.begin_sector(),
	]
	var number := 0
	for step in steps:
		step.call()
		number += 1
		var late := _hud()
		first.show_mod_layers(0.5)
		late.show_mod_layers(0.5)
		assert_array(late.mod_host().lines()).override_failure_message("after step %d the late console draws nothing" % number).is_not_empty()
		assert_array(_shown(late)[0]).override_failure_message("after step %d" % number).is_equal(_shown(first)[0])
		assert_array(_shown(late)[1]).is_equal(_shown(first)[1])
		assert_dict(_shown(late)[2]).is_equal(_shown(first)[2])


# --- drawing the console changes nothing of the game -------------------------------------------------------------------------

## The rules' trace of `ticks` ticks of the arena with a firing sub (what the rules say after each).
func _trace(world: SectorWorld, console: Hud, ticks: int) -> Array[String]:
	var lines: Array[String] = []
	var sim := world.sim
	for t in ticks:
		sim.tick(InputSnapshot.firing() if t % 7 == 0 else InputSnapshot.new())
		world.presenter.show_between_ticks(0.5)
		if console != null:
			console.show_mod_layers(0.5)
		lines.append("%s %s %s %d %d %d" % [sim.sub.position, sim.foes.map(func(f: FoeModel) -> Vector2i: return Vector2i(f.vm.x, f.vm.y)), sim.pellets.size(), GameState.oxygen(), GameState.ink, GameState.tanks()])
	return lines


func test_the_rules_run_the_same_whatever_the_script_draws_of_the_console() -> void:
	var traces: Array = []
	for fixture in ["", FIXTURE, FAULTY]:
		SkinChoice.select(SkinChoice.original())
		GameState.reset()
		GameState.set_sector(DevCreatures.ARENA, 9)
		var console: Hud = null
		if fixture != "":
			SkinChoice.select(_mount(fixture))
		var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
		if fixture != "":
			console = auto_free((load(HUD_SCENE) as PackedScene).instantiate()) as Hud
			world.add_child(console)
		world.sim.load_sector(DevCreatures.ARENA, 0)
		world.sim.foe_context.rng.seed = 4242
		world.sim.start_flight(200, 150, 6)
		traces.append(_trace(world, console, 120))
		if console != null:
			assert_bool(console.hosts_mod_layers()).is_true()
		if fixture != "":
			Mods.loader().forgive(String(_shelves[-1].id))
		ModSkinShelf.release(_shelves)
	assert_array(traces[1]).is_equal(traces[0])
	assert_array(traces[2]).is_equal(traces[0])


# --- the clip -----------------------------------------------------------------------------------------------------------------

func test_what_the_script_draws_outside_its_rectangle_is_cut_off_and_a_rectangle_cannot_move_a_hit_area() -> void:
	var hud := _hud(_mount())
	hud.show_mod_layers(0.5)
	var drawn := _commands(_stack_of(hud, &"hud_ship"))
	assert_bool(drawn.any(func(c: Array) -> bool: return c[0] == "rect" and (c[1] as Rect2) == Rect2(0, 0, 640, 400))).override_failure_message("the script drew over the whole window").is_true()
	var clip := _stack_of(hud, &"hud_ship").get_parent() as Control
	var area: Rect2 = ConsoleState.rects(hud.layout)["hud_ship"]
	assert_object(Rect2(clip.position, clip.size)).is_equal(area)
	assert_bool(clip.clip_contents).is_true()
	assert_bool(Rect2(0, 0, 640, 400).encloses(area)).is_true()
	assert_bool(area.size.x < 640.0).is_true()
	for node: Node in hud.get_children():                                                 # (nothing the script made takes the mouse: the console ignores it)
		if node is Control:
			assert_int((node as Control).mouse_filter).override_failure_message(String(node.name)).is_equal(Control.MOUSE_FILTER_IGNORE)


# --- the document ----------------------------------------------------------------------------------------------------------

func test_the_document_names_the_layers_the_rectangles_and_the_version() -> void:
	var doc := FileAccess.get_file_as_string("res://../docs/create/SKIN_API.md")
	doc = doc.substr(doc.find("## Writing a skin mod"))
	assert_str(doc).is_not_empty()
	for layer in SkinLayers.hud_layers():
		assert_bool(doc.contains("`%s`" % layer)).override_failure_message("SKIN_API.md does not name the layer `%s`" % layer).is_true()
	for part in ["\"requires_api\": %d" % ModSpec.HUD_API_VERSION, "`rects`", "`phase`", "`size`", "`ConsoleState.rects`", "hud_layer/"]:
		assert_bool(doc.contains(part)).override_failure_message("SKIN_API.md does not mention %s" % part).is_true()
