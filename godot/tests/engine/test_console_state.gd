class_name TestConsoleState
extends GdUnitTestSuite
## Teaches: one source for a view and for data. `ConsoleState` is the console's state as plain data and `Hud` is drawn from it, so after any change of the game every field of the state is looked for in the HUD's nodes (`_agrees`): the
## gauges, the low-air pulse, each label's picture, word and box, the lights and the two rectangles. The game is played (the rules tick with the ink being fired, the air drained, pieces taken, lights switched, the sector and the
## game's customising changed) with the original's pictures and with a skin that writes the words as text, and a HUD made in the middle of it shows what the first one shows.

const HUD_SCENE := "res://src/ui/hud.tscn"
const TINY := "res://tests/skins/tiny/skin.tres"
const TOP_KEYS := ["sector", "customized", "tanks", "oxygen", "ink", "pieces", "labels", "lights", "bezel", "playfield"]


func before_test() -> void:
	GameClock.paused = true
	SkinChoice.select(SkinChoice.original())
	GameState.reset()
	GameState.customized = false
	GameState.set_sector(0, 9)


func after_test() -> void:
	GameClock.paused = false
	SkinChoice.select(SkinChoice.original())
	GameState.reset()
	GameState.customized = false
	GameState.sector = -1
	GameState.piece_total = 0


func _hud() -> Hud:
	return scene_runner(HUD_SCENE).scene() as Hud


## Every step of a game that changes what the console shows: each is run, and the HUD is held to the state after it.
func _steps(sim: SimWorld) -> Array[Callable]:
	var full := GameState.tuning.max_oxygen
	return [
		func() -> void: sim.tick(),
		func() -> void: sim.tick(InputSnapshot.firing()),
		func() -> void: sim.tick(InputSnapshot.firing()),
		func() -> void: GameState.update_oxygen(-1),
		func() -> void: GameState.update_oxygen(-(full - 2)),                      # (one cell left: the warning)
		func() -> void: GameState.update_oxygen(1),
		func() -> void: GameState.collect_piece(0),
		func() -> void: GameState.collect_piece(3),
		func() -> void: GameState.set_message_light(true, false),
		func() -> void: GameState.set_message_light(false, true),
		func() -> void: GameState.set_message_light(true, true),
		func() -> void: GameState.set_message_light(false, false),
		func() -> void: GameState.customized = true,
		func() -> void: GameState.set_sector(2, 8),
		func() -> void: GameState.set_sector(DevPack.TOUR_FINALE, 8),
		func() -> void: GameState.refill_ink(),
		func() -> void: GameState.update_oxygen(-4),                               # (the last cell: a spare tank is used, then the air is full)
		func() -> void: GameState.update_oxygen(4),
		func() -> void: GameState.begin_sector(),
	]


# --- the state is plain data ------------------------------------------------------------------------------------------

func test_the_state_is_plain_read_only_data_of_a_known_shape() -> void:
	var hud := _hud()
	var state := ConsoleState.build(hud.layout, null)
	assert_array(state.keys()).contains_exactly_in_any_order(TOP_KEYS)
	_assert_plain(state, "state")
	assert_bool(state.is_read_only()).is_true()
	assert_bool((state["labels"] as Dictionary).is_read_only()).is_true()
	assert_array((state["ink"]["positions"] as Array)).has_size(hud.layout.ink_positions.size())
	assert_array(state["labels"].keys()).contains_exactly_in_any_order(["game", "custom", "zone", "sector"])
	assert_array(state["lights"].keys()).contains_exactly_in_any_order(["ship", "computer"])
	for gauge: String in ["tanks", "oxygen", "ink"]:
		assert_array((state[gauge]["positions"] as Array)).has_size(state[gauge]["slots"])


func _assert_plain(value: Variant, where: String) -> void:
	if value is Dictionary:
		for key: Variant in value:
			assert_bool(key is String).override_failure_message("%s: key %s is not a String" % [where, key]).is_true()
			_assert_plain(value[key], "%s.%s" % [where, key])
	elif value is Array:
		for element: Variant in value:
			_assert_plain(element, where + "[]")
	else:
		assert_bool(typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_VECTOR2, TYPE_RECT2]) \
				.override_failure_message("%s holds %s, which is not plain data" % [where, type_string(typeof(value))]).is_true()


func test_it_is_made_again_from_the_owner_each_time() -> void:
	var hud := _hud()
	var before := ConsoleState.build(hud.layout, null)
	assert_bool(before.is_read_only()).is_true()
	GameState.fire_ink()
	var after := ConsoleState.build(hud.layout, null)
	assert_int(after["ink"]["value"]).is_equal(before["ink"]["value"] - 1)
	assert_dict(ConsoleState.build(hud.layout, null)).is_equal(after)                 # (nothing is kept between calls)


func test_the_pieces_are_told_by_index() -> void:
	GameState.set_sector(0, 9)
	GameState.collect_piece(0)
	GameState.collect_piece(4)
	var pieces := ConsoleState.pieces()
	assert_int(pieces["total"]).is_equal(9)
	assert_int(pieces["collected"]).is_equal(2)
	assert_array(pieces["taken"]).has_size(9)
	assert_bool(pieces["taken"][0]).is_true()
	assert_bool(pieces["taken"][1]).is_false()
	assert_bool(pieces["taken"][4]).is_true()
	var counter := auto_free(PieceCounter.new()) as PieceCounter                       # (the F3 overlay's own count agrees)
	counter.show_pieces(GameState.piece_total, GameState.pieces_mask)
	assert_int(counter.collected_count()).is_equal(pieces["collected"])


func test_a_sector_none_describes_nothing() -> void:
	GameState.sector = -1
	var labels := ConsoleState.labels(_hud().layout, null)
	for label: String in ["game", "custom", "zone", "sector"]:
		assert_bool(labels[label]["visible"]).is_false()
	for label: String in ["game", "zone", "sector"]:
		assert_str(labels[label]["word"]).is_empty()
		assert_int(labels[label]["picture"]).is_equal(-1)


func test_the_words_are_the_skins_or_the_originals() -> void:
	var layout := _hud().layout
	GameState.set_sector(2, 8)
	var original := ConsoleState.labels(layout, null)
	var words := HudLabels.new()
	assert_str(original["game"]["word"]).is_equal(words.game_word(Catalog.sector(2).game))
	assert_str(original["zone"]["word"]).is_equal(words.zone_word(Catalog.sector(2).zone))
	assert_str(original["sector"]["word"]).is_equal(words.sector_word(2, false))
	var own := HudLabels.new()
	own.zone_words = ["Zed"]
	own.sector_final_word = "Last"
	assert_str(ConsoleState.labels(layout, own)["zone"]["word"]).is_equal("Zed")
	GameState.set_sector(DevPack.TOUR_FINALE, 8)
	var finale: Dictionary = ConsoleState.labels(layout, own)["sector"]
	assert_bool(finale["final"]).is_true()
	assert_int(finale["picture"]).is_equal(-1)
	assert_str(finale["word"]).is_equal("Last")


# --- the HUD shows exactly the state -------------------------------------------------------------------------------

func test_the_hud_shows_the_state_after_every_step_of_a_played_game() -> void:
	var sim := SimWorld.new(GameState)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.foe_context.rng.seed = 4242
	sim.start_flight(200, 150, 6)
	var hud := _hud()
	_agrees(hud, "at the start")
	var number := 0
	for step in _steps(sim):
		step.call()
		number += 1
		_agrees(hud, "after step %d" % number)


func test_a_hud_made_in_the_middle_shows_what_the_first_one_shows() -> void:
	var sim := SimWorld.new(GameState)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.start_flight(200, 150, 6)
	var first := _hud()
	var number := 0
	for step in _steps(sim):
		step.call()
		number += 1
		var late := _hud()
		_agrees(late, "a HUD made after step %d" % number)
		assert_dict(_shown(late)).override_failure_message("after step %d the late HUD differs from the first" % number).is_equal(_shown(first))


func test_a_skin_with_text_shows_the_state_too() -> void:
	SkinChoice.select(load(TINY) as GameSkin)
	var sim := SimWorld.new(GameState)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.start_flight(200, 150, 6)
	var hud := _hud()
	_agrees(hud, "text skin at the start")
	var number := 0
	for step in _steps(sim):
		step.call()
		number += 1
		_agrees(hud, "text skin after step %d" % number)
	SkinChoice.select(SkinChoice.original())                                                   # (another skin: the words and the layout are put on again)
	_agrees(hud, "back to the original")


## What the HUD shows in the parts the state tells, as one value (for comparing two HUDs).
func _shown(hud: Hud) -> Dictionary:
	return {
		"gauges": [hud.tanks.value, hud.oxygen.value, hud.ink.value], "low": hud.air_animations.is_playing(),
		"labels": [hud.game_label.visible, hud.zone_label.visible, hud.sector_label.visible, hud.custom_label.visible],
		"textures": [hud.game_label.texture, hud.zone_label.texture, hud.sector_label.texture],
		"words": [hud.game_text.text, hud.zone_text.text, hud.sector_text.text, hud.custom_text.text],
		"lights": [hud.ship_glow.visible, hud.computer_glow.visible, hud.light_animations.is_playing()],
	}


## Every field of the state, found in the nodes of `hud`.
func _agrees(hud: Hud, when: String) -> void:
	var state := ConsoleState.build(hud.layout, hud._labels)
	var layout := hud.layout
	var say := func(what: String) -> String: return "%s: %s" % [when, what]
	assert_int(state["sector"]).override_failure_message(say.call("sector")).is_equal(GameState.sector)
	assert_bool(state["customized"]).is_equal(GameState.customized)
	for part: Array in [["tanks", hud.tanks], ["oxygen", hud.oxygen], ["ink", hud.ink]]:
		var gauge: IconGauge = part[1]
		var told: Dictionary = state[part[0]]
		assert_int(gauge.value).override_failure_message(say.call(part[0] + " value")).is_equal(told["value"])
		assert_int(gauge.slot_positions.size()).is_equal(told["slots"])
		assert_array(told["positions"]).is_equal(Array(gauge.slot_positions))
		var low_here: bool = part[0] == "oxygen" and state["oxygen"]["low"] and gauge.low_texture != null
		for slot in told["slots"]:                                                             # (the first `value` slots are full, the others empty)
			var wanted := gauge.empty_texture
			if slot < told["value"]:
				wanted = gauge.low_texture if slot == 0 and low_here else gauge.full_texture
			assert_object(gauge.texture_for_slot(slot)).override_failure_message(say.call("%s slot %d" % [part[0], slot])).is_same(wanted)
	var low: bool = state["oxygen"]["low"]
	assert_bool(hud.air_animations.is_playing()).override_failure_message(say.call("low oxygen pulse")).is_equal(low)
	assert_bool(hud.oxygen.is_low()).is_equal(low)
	var labels: Dictionary = state["labels"]
	var boxes := {"game": hud.game_label, "custom": hud.custom_label, "zone": hud.zone_label, "sector": hud.sector_label}
	var texts := {"game": hud.game_text, "custom": hud.custom_text, "zone": hud.zone_text, "sector": hud.sector_text}
	for name: String in boxes:
		var box: TextureRect = boxes[name]
		var told: Dictionary = labels[name]
		assert_bool(box.visible).override_failure_message(say.call(name + " visible")).is_equal(told["visible"])
		assert_object(box.position).is_equal(told["rect"].position)
		if not told["visible"]:
			continue
		if hud._labels == null:
			assert_object(box.get_rect()).override_failure_message(say.call(name + " box")).is_equal(told["rect"])
		else:
			assert_object(box.size).is_equal(told["rect"].size)
			assert_str((texts[name] as Label).text).override_failure_message(say.call(name + " word")).is_equal(told["word"])
	if hud._labels == null:
		if labels["game"]["visible"]:
			var banner: Texture2D = layout.game_textures[labels["game"]["picture"]] if labels["game"]["picture"] >= 0 else ConsoleState.campaign_of(GameState.sector).banner
			assert_object(hud.game_label.texture).override_failure_message(say.call("game picture")).is_same(banner)
			assert_object(hud.zone_label.texture).override_failure_message(say.call("zone picture")).is_same(layout.zone_textures[labels["zone"]["picture"]])
			var sector_picture: Texture2D = layout.sector_final_texture if labels["sector"]["final"] else layout.sector_textures[labels["sector"]["picture"]]
			assert_object(hud.sector_label.texture).override_failure_message(say.call("sector picture")).is_same(sector_picture)
		if labels["custom"]["visible"]:
			assert_object(hud.custom_label.texture).is_same(layout.custom_texture)
	var lights: Dictionary = state["lights"]
	assert_bool(hud.ship_glow.visible).override_failure_message(say.call("ship light")).is_equal(lights["ship"]["on"])
	assert_bool(hud.computer_glow.visible).override_failure_message(say.call("computer light")).is_equal(lights["computer"]["on"])
	assert_bool(hud.light_animations.is_playing()).is_equal(lights["ship"]["on"] or lights["computer"]["on"])
	assert_object(hud.ship_light.position).is_equal(lights["ship"]["position"])
	assert_object(hud.computer_light.position).is_equal(lights["computer"]["position"])
	assert_object(hud.bezel.position).is_equal(state["bezel"])
	assert_object(state["playfield"]).is_equal(Rect2(layout.playfield))


# --- the document ----------------------------------------------------------------------------------------------------

func test_the_document_names_every_key_of_the_state() -> void:
	var doc := FileAccess.get_file_as_string("res://../docs/create/SKIN_API.md")
	doc = doc.substr(doc.find("### The console's state"))
	doc = doc.substr(0, doc.find("### The events"))
	assert_str(doc).is_not_empty()
	GameState.customized = true
	var state := ConsoleState.build(_hud().layout, null)
	var named: Array = state.keys()
	for group: String in ["tanks", "oxygen", "ink", "pieces", "labels", "lights"]:
		named.append_array((state[group] as Dictionary).keys())
	for label: String in state["labels"]:
		named.append_array((state["labels"][label] as Dictionary).keys())
	for light: String in state["lights"]:
		named.append_array((state["lights"][light] as Dictionary).keys())
	for key: String in named:
		assert_bool(doc.contains("`%s`" % key)).override_failure_message("SKIN_API.md does not mention the key `%s` of the console's state" % key).is_true()
	assert_bool(doc.contains("`ConsoleState.LOW_OXYGEN`")).is_true()
