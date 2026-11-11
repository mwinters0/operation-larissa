class_name TestSfxEvents
extends GdUnitTestSuite
## The sound effects: the pool of players, and that each gameplay event asks `Audio` for the right one.
## The effects are asked for by their registry names (docs/create/NAMES.md), whatever numbers the pack gives them.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const SCREEN_SCENE := "res://src/problems/problem_screen.tscn"

var _probe: AudioProbe


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()
	Audio.stop_sfx()
	_probe = AudioProbe.new()


func after_test() -> void:
	_probe.stop()
	Audio.stop_sfx()
	Audio.stop_voice()
	GameClock.paused = false
	GameState.reset()


# --- the one wave device ----------------------------------------------------------------------------

func test_one_request_makes_exactly_one_player_busy() -> void:
	Audio.play_sfx(&"tank_fill")                                          # a long effect (3.2 s)
	assert_int(Audio.busy_sfx_players()).is_equal(1)
	assert_array(_probe.sfx).is_equal([&"tank_fill"])


func test_a_new_effect_cuts_the_previous_one_like_the_original() -> void:
	# `PlayWave` (0x4150c4) starts with `KillWave`: effects never overlap, however many are asked for.
	Audio.play_sfx(&"tank_fill")
	var first_stream := Audio._sfx_player.stream
	Audio.play_sfx(&"diagram_pop")
	assert_int(Audio.busy_sfx_players()).is_equal(1)
	assert_object(Audio._sfx_player.stream).is_not_same(first_stream)
	for i in 12:
		Audio.play_sfx(&"tank_fill")
	assert_int(Audio.busy_sfx_players()).is_equal(1)
	assert_int(_probe.sfx.size()).is_equal(14)                    # (every request is still announced)


func test_an_effect_cuts_a_speech_clip_and_a_speech_clip_cuts_an_effect() -> void:
	Audio.play_sfx(&"tank_fill")
	Audio.play_voice(&"sign_in_begin_1")                                        # speech goes through the same device
	assert_int(Audio.busy_sfx_players()).is_equal(0)
	assert_bool(Audio._voice_player.playing).is_true()
	Audio.play_sfx(&"tank_fill")
	assert_bool(Audio._voice_player.playing).is_false()
	assert_int(Audio.busy_sfx_players()).is_equal(1)


func test_the_speech_goes_on_with_its_next_clip_when_the_effect_that_cut_it_is_over() -> void:
	var started: Array[StringName] = []
	Audio.voice_started.connect(func(clip: StringName, _text: String) -> void: started.append(clip))
	Audio.play_voice_sequence([&"sign_in_begin_0", &"sign_in_begin_1"] as Array[StringName])
	assert_array(started).is_equal([&"sign_in_begin_0"])
	Audio.play_sfx(&"correct")                                          # a short effect cuts clip 4251
	assert_array(started).is_equal([&"sign_in_begin_0"])
	Audio.stop_sfx()                                              # (it ends) ... and the sequence goes on
	assert_array(started).is_equal([&"sign_in_begin_0", &"sign_in_begin_1"])


func test_a_speech_clip_with_the_voice_off_still_cuts_the_effect() -> void:
	Audio.set_bus_enabled(AudioService.VOICE, false)
	Audio.play_sfx(&"tank_fill")
	Audio.play_voice(&"sign_in_begin_1")                                        # (`KillWave` comes before `VoiceOn` is looked at)
	Audio.set_bus_enabled(AudioService.VOICE, true)
	assert_int(Audio.busy_sfx_players()).is_equal(0)


func test_a_muted_effect_bus_still_announces_but_starts_nothing() -> void:
	Audio.set_bus_enabled(AudioService.SFX, false)
	Audio.play_sfx(&"correct")
	Audio.set_bus_enabled(AudioService.SFX, true)
	assert_array(_probe.sfx).is_equal([&"correct"])
	assert_int(Audio.busy_sfx_players()).is_equal(0)


func test_an_unknown_effect_is_a_warning_not_a_crash() -> void:
	Audio.play_sfx(&"no_such_sound")
	assert_int(Audio.busy_sfx_players()).is_equal(0)


# --- the playfield -------------------------------------------------------------------------------

func _world() -> SectorWorld:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(0, 0)
	world.start_flight()
	world.foes_active = false
	world.tile_grid.clear()
	return world


func test_firing_plays_ink_fired_and_an_empty_supply_plays_no_pellets() -> void:
	var world := _world()
	world.request_fire()
	assert_array(_probe.sfx).is_equal([&"ink_fired"])
	_probe.clear()
	GameState.ink = 0
	world.request_fire()
	assert_array(_probe.sfx).is_equal([&"no_pellets"])


func test_a_pellet_hitting_rock_splashes_with_sound_0x19() -> void:
	var world := _world()
	world.request_fire()
	var pellet := world.sim.pellets[0]
	# A rock tile (zone 0 picture 1) a few tiles in front of the pellet's centre, three rows tall: it flies straight on.
	var centre := pellet.position + Vector2(8, 8)
	var column := int(centre.x / 16) + 4
	var row := int(centre.y / 16)
	for each in range(row - 1, row + 2):
		world.tile_grid.set_byte(column, each, TileCodec.SOLID_BIT | 1)
	_probe.clear()
	for tick in 12:
		pellet.logic_tick()
	assert_array(_probe.sfx).is_equal([&"ink_splash"])                     # once, not once per splash picture


func test_touching_a_creature_plays_the_hit_sound() -> void:
	var world := _world()
	world.foes_active = true
	world.load_screen(world.sector.foes[0].screen)                           # (the screen the creature is on)
	_probe.clear()
	world.sub_touches(world.sim.foes[0])
	assert_array(_probe.sfx).is_equal([&"creature_hit"])


func test_a_creature_script_can_ask_for_a_sound() -> void:
	var world := _world()
	world.sfx_requested.emit(&"clam_chomp")                                  # what creature 0 of sector 0 does (SOUND 13)
	assert_array(_probe.sfx).is_equal([&"clam_chomp"])


func test_taking_a_piece_plays_the_pickup_sound() -> void:
	var world := _world()
	world.load_screen(9)
	world.sim.take_piece(6)
	assert_array(_probe.sfx).is_equal([&"piece_pickup"])


func test_entering_a_screen_plays_nothing() -> void:
	# The original's DrawScreen(0) at a screen edge is silent; only DrawScreen(1) at the start of a sector
	# plays "begin" (0x16, the oxygen level).
	var world := _world()
	world.sim._on_sub_crossed_edge(SectorData.Direction.RIGHT)
	assert_array(_probe.sfx).is_empty()


func test_starting_a_sector_plays_the_begin_sound() -> void:
	var world := _world()
	await world.begin_sector(0, true)
	assert_array(_probe.sfx).contains(&"begin")


func test_the_station_door_plays_0x17() -> void:
	var world := _world()
	world.sim.sound_requested.emit(SimWorld.SFX_STATION_DOOR)
	assert_array(_probe.sfx).is_equal([&"station_door"])


func test_a_message_light_plays_0x2f() -> void:
	var hud := scene_runner("res://src/ui/hud.tscn").scene() as Hud
	_probe.clear()
	GameState.set_message_light(true, false)
	assert_array(_probe.sfx).is_equal([&"message_light"])
	GameState.set_message_light(false, false)                     # going out is silent
	assert_array(_probe.sfx).is_equal([&"message_light"])
	assert_object(hud).is_not_null()


# --- math problems --------------------------------------------------------------------------------

func _screen(type_id: int, level: int, record: int = 0) -> ProblemScreen:
	var screen := scene_runner(SCREEN_SCENE).scene() as ProblemScreen
	screen.start(ProblemFactory.make(type_id, level, null, record))
	if screen.step() == ProblemScreen.Step.INTRO:
		screen.diagram.skip_animation()
	return screen


func test_a_right_answer_plays_0x20_and_a_wrong_one_0x21() -> void:
	var screen := _screen(6, 2)                                   # a plain number problem
	var right := screen.session.instance.expected.to_text()
	assert_str(right).is_not_equal("7")
	for key in "7":
		screen.calculator.press(key)
	_probe.clear()                                                # (the key clicks are tested below)
	screen.calculator.press("Enter")
	assert_array(_probe.sfx).is_equal([&"calc_backspace", &"wrong"])               # the Enter key clicks, then "wrong"
	screen.press_continue()                                       # ("Error!" over: the second try)
	_probe.clear()
	for key in right:
		screen.calculator.press(key)
	_probe.clear()
	screen.calculator.press("Enter")
	assert_array(_probe.sfx).is_equal([&"calc_backspace", &"correct"])


func test_the_lock_ticks_and_settles_and_judges() -> void:
	var screen := _screen(0, 0)
	assert_object(screen.lock).is_not_null()
	_probe.clear()
	screen.lock.sfx_requested.emit(&"lock_tick")
	screen.lock.sfx_requested.emit(&"lock_settle")
	assert_array(_probe.sfx).is_equal([&"lock_tick", &"lock_settle"])
	_probe.clear()
	screen.lock.stage_right.emit()
	assert_array(_probe.sfx).is_equal([&"correct"])
	_probe.clear()
	screen.lock.stage_missed.emit("OUT OF TIME")
	assert_array(_probe.sfx).is_equal([&"wrong"])


func test_the_catalog_names_the_effect_a_diagram_plays_while_it_builds() -> void:
	var catalog := SfxCatalog.new()
	catalog.diagram_cues = {5: 3}
	assert_int(catalog.diagram_cue(5)).is_equal(3)
	assert_int(catalog.diagram_cue(6)).is_equal(-1)                # a type that is not listed has a silent diagram


func test_a_diagram_that_builds_with_a_sound_plays_it() -> void:
	# A type of the pack that draws plain items, with its second item made to appear by itself with a sound.
	var problem := ProblemFactory.make(21, 1)
	var type := problem.type.duplicate() as ProblemType
	var spec := type.diagram.duplicate(true)
	spec["items"][1]["animate"] = true
	spec["intro"] = {"mode": "sequence", "interval": 10, "sfx": Catalog.sfx_catalog().id_of(&"diagram_bar")}
	type.diagram = spec
	problem.type = type
	var screen := scene_runner(SCREEN_SCENE).scene() as ProblemScreen
	screen.start(problem)
	assert_array(_probe.sfx).is_equal([&"diagram_bar"])


func test_a_weight_button_clicks() -> void:
	var level := 0
	while ProblemFactory.make(28, level) == null:
		level += 1
	var screen := _screen(28, level)
	assert_object(screen.ballast).is_not_null()
	_probe.clear()
	screen.ballast.toggle(0)
	assert_array(_probe.sfx).is_equal([&"click"])


func test_backspace_in_the_answer_box_erases_with_a_sound() -> void:
	var screen := scene_runner(SCREEN_SCENE).scene() as ProblemScreen
	screen.calculator_allowed = false                              # the plain "Ans:" box
	screen.start(ProblemFactory.make(6, 2, null, 0))
	assert_bool(screen.answer_box.visible).is_true()
	screen.answer_box.text = "12"
	_probe.clear()
	var key := InputEventKey.new()
	key.keycode = KEY_BACKSPACE
	key.pressed = true
	screen.answer_box._unhandled_key_input(key)
	assert_array(_probe.sfx).is_equal([&"calc_backspace"])
	assert_str(screen.answer_box.text).is_equal("1")


func test_backspace_in_the_answer_box_clicks_even_on_an_empty_entry() -> void:
	# GetNumber 0x41fefd / 0x42031a / 0x420546: PlaySoundEffect(0x1f) comes before anything is looked at
	var screen := scene_runner(SCREEN_SCENE).scene() as ProblemScreen
	screen.calculator_allowed = false
	screen.start(ProblemFactory.make(6, 2, null, 0))
	assert_str(screen.answer_box.text).is_empty()
	_probe.clear()
	var key := InputEventKey.new()
	key.keycode = KEY_BACKSPACE
	key.pressed = true
	screen.answer_box._unhandled_key_input(key)
	assert_array(_probe.sfx).is_equal([&"calc_backspace"])
	assert_str(screen.answer_box.text).is_empty()


func test_every_calculator_key_clicks_with_sound_0x1f() -> void:
	# HighlightCalcKey (0x41b4f1) (called by GetNumber for every key in calculator mode) plays PlaySoundEffect(0x1f) on the press of
	# each of the 22 keys, digits and operators and F S N R C and Enter alike; there is no second sound.
	var screen := _screen(6, 2)
	assert_bool(screen.calculator.visible).is_true()
	assert_int(screen.calculator.layout.key_names.size()).is_equal(22)
	for key: String in screen.calculator.layout.key_names:
		screen.calculator.reset()
		_probe.clear()
		screen.calculator.press(key)
		# (Enter on the empty display clicks and then does nothing: GetNumber needs a digit first, no wrong answer)
		assert_str(String(_probe.sfx[0])).override_failure_message("key %s" % key).is_equal("calc_backspace")
		assert_int(_probe.sfx.size()).override_failure_message("key %s" % key).is_equal(1)


func test_a_calculator_key_clicks_even_when_it_does_nothing() -> void:
	# the sound comes before the state machine: an operator inside a fraction is refused (a notice), still clicking
	var screen := _screen(6, 2)
	for key in "F3":
		screen.calculator.press(key)
	_probe.clear()
	screen.calculator.press("+")
	assert_array(_probe.sfx).is_equal([&"calc_backspace"])
	assert_str(screen.calculator.model.display_text()).is_equal("3")


func test_the_keyboard_clicks_like_the_mouse_and_other_keys_are_silent() -> void:
	var screen := _screen(6, 2)
	_probe.clear()
	var key := InputEventKey.new()
	key.keycode = KEY_7
	key.unicode = "7".unicode_at(0)
	key.pressed = true
	screen.calculator._unhandled_key_input(key)
	assert_array(_probe.sfx).is_equal([&"calc_backspace"])
	_probe.clear()
	key.keycode = KEY_Q                                            # not a calculator key
	key.unicode = "q".unicode_at(0)
	screen.calculator._unhandled_key_input(key)
	assert_array(_probe.sfx).is_empty()


func test_no_calculator_no_key_click() -> void:
	# without the calculator (plain "Ans:" box) only Backspace makes the sound (GetNumber's param_2 == 0)
	var screen := scene_runner(SCREEN_SCENE).scene() as ProblemScreen
	screen.calculator_allowed = false
	screen.start(ProblemFactory.make(6, 2, null, 0))
	_probe.clear()
	screen.answer_box.type_character("5")
	assert_array(_probe.sfx).is_empty()


func test_the_radar_sweep_pings_when_the_beam_reaches_the_blip() -> void:
	# A sonar picture of the test's own: four beam steps a turn, two turns, the blip under the beam at step 0.
	var problem := ProblemFactory.make(3, 0)
	var type := problem.type.duplicate() as ProblemType
	var ping := Catalog.sfx_catalog().id_of(&"diagram_pop")
	type.diagram = {
		"family": "sonar", "items": [type.diagram["items"][0]],
		"sweep": {"pics": [0, 0, 0, 0], "pos": [[0, 0], [0, 0], [0, 0], [0, 0]], "mirror_from": 2, "revolutions": 2, "ticks_per_step": 1},
		"blip": {"field": 0, "divisor": 5, "clamp": [0, 2], "step": [0, 0, 0], "sfx": ping, "pic_frames": [0, 0], "pos": [[10, 10], [20, 20], [30, 30]]},
	}
	problem.type = type
	var screen := scene_runner(SCREEN_SCENE).scene() as ProblemScreen
	screen.start(problem)
	var sonar := (screen.diagram as ModDiagram).plain() as SonarDiagram
	assert_object(sonar).is_not_null()
	assert_int(sonar.blip_sfx()).is_equal(ping)
	assert_int(sonar.blip_step()).is_equal(0)
	_probe.clear()                                                # (the first picture of the sweep rang its ping in the very first frame)
	# play the sweep's steps by hand: the steps of each of two turns, then the final state (step 0 again)
	var steps: int = sonar.spec["sweep"]["pics"].size()
	for turn in 2:
		for step in steps:
			sonar._show_beam(step)
	sonar._show_beam(0)
	assert_array(_probe.sfx).is_equal([&"diagram_pop", &"diagram_pop", &"diagram_pop"])        # step 0 of both turns and the end; the other steps are silent


func test_the_data_canister_reads_its_log_entry_when_solved() -> void:
	var sector := Catalog.sector(0)
	var campaign := CanisterLog.campaign_of(0)
	var rng := RandomNumberGenerator.new()
	var instance: ProblemInstance
	for seed_value in range(1, 60):                                     # (the canister's problem is drawn at random: take the first draw with one plain answer)
		rng.seed = seed_value
		instance = ProblemFactory.for_canister(sector, 1, rng)
		if instance.expected != null:
			break
	assert_object(instance.expected).is_not_null()
	assert_int(instance.log_index).is_greater_equal(0)                  # the canister delivers a log entry
	var screen := scene_runner(SCREEN_SCENE).scene() as ProblemScreen
	screen.start(instance)
	if screen.step() == ProblemScreen.Step.INTRO:
		screen.diagram.skip_animation()
	_probe.clear()
	screen.submit_answer(instance.expected)
	# the log screen scans first (the scanner sound), then the newest entry is read aloud
	assert_array(_probe.sfx).is_equal([&"correct", &"scanner"])
	assert_int(_probe.voice.size()).is_equal(0)
	screen.log_screen.advance_scan(CanisterLog.scan_ticks())              # (the rules own the length of the scan: hand it the ticks)
	assert_int(_probe.voice.size()).is_equal(1)
	var number := CanisterLog.entries(0)[CanisterLog.initial_row(0)]
	var clips := Catalog.voice_cues().clips(String(campaign.log_voice_name(number)))
	assert_array(clips).is_not_empty()
	assert_array(_probe.voice[0]).is_equal(Array(clips))
	Audio.stop_voice()
