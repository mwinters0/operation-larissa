class_name TestModProblemAnimation
extends GdUnitTestSuite
## Teaches: a stranger's code that animates on the game's clock and asks for sounds, and cannot change a length. A problem-screen mod of API version 5 is told where the build-up and the replay are (`state["clock"]`: the animation,
## its tick, its length and the tick it was last told, all read off the diagram that the step machine's count drives), so it draws frame N of a length the engine owns; it may return `{"draw": ..., "sounds": [names]}`, and the game
## plays the names of its sounds (`ModSounds`: a closed list, a few per answer, a bucket that refills) through the one `Audio` door. The tests count the ticks the flow takes with and without a mod (the exact number, the data's), read
## what the script was told from the worked example `tests/mods/tides` and flood the sounds with `tests/mods/tides_hostile`.
## These tests need the godot-sandbox extension (`uv run tools/fetch_sandbox.py`, docs/SETUP.md).

const ORIGINAL := ModProblemShelf.ORIGINAL
const REPLAY := ModProblemShelf.REPLAY

var _shelves: Array[PackShelf] = []
var _probe: AudioProbe


func before() -> void:
	assert_bool(ModLoader.sandbox_available()).override_failure_message("the godot-sandbox extension is not loaded: run `uv run tools/fetch_sandbox.py`, then `tools/godot.sh --headless --path godot --import` (docs/SETUP.md)").is_true()


func before_test() -> void:
	GameClock.paused = false
	GameState.reset()
	_probe = AudioProbe.new()


func after_test() -> void:
	_probe.stop()
	SkinChoice.select(SkinChoice.original())
	GameClock.paused = false
	ModProblemShelf.release(_shelves)
	GameState.reset()


## A screen with problem `type_id` (record 0) started.
func _screen(type_id: int) -> ProblemScreen:
	var screen: ProblemScreen = ProblemRunner.SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.start(ProblemFactory.make(type_id, 0, null, 0))
	return screen


func _mount(name: String, mod: Dictionary = {}, replay := false) -> PackShelf:
	var shelf := ModProblemShelf.mount_one(name, mod, replay)
	_shelves.append(shelf)
	return shelf


func _mod(shelf: PackShelf) -> Node:
	var node := ModHost.mod(String(shelf.id))
	assert_object(node).override_failure_message("the mod did not load: %s" % ModHost.failure(String(shelf.id))).is_not_null()
	return node


## The same fixture, with `own_sounds` in its manifest.
func _own_sounds(name: String) -> Dictionary:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/%s/pack.json" % [ModProblemShelf.FIXTURES, name]))
	var problems: Dictionary = (fixture["mod"]["problems"] as Dictionary).duplicate(true)
	problems["own_sounds"] = true
	return {"problems": problems, "requires_api": ModSpec.API_VERSION}


## The ticks the build-up of `screen` takes, counted one at a time until it asks for an answer.
func _intro_ticks(screen: ProblemScreen) -> int:
	var ticks := 0
	while not screen.is_answering() and ticks < 1000:
		screen.advance_ticks(1)
		ticks += 1
	return ticks


## The ticks the replay takes after a right answer, one at a time, until the step is another one (the replay is a step of its own).
func _replay_ticks(screen: ProblemScreen, answer: Variant) -> int:
	screen.submit_answer(answer)
	var ticks := 0
	while screen.step() == ProblemFlow.Step.REPLAY and ticks < 1000:
		screen.advance_ticks(1)
		ticks += 1
	return ticks


func _lines(screen: ProblemScreen) -> Array[String]:
	return (screen.diagram as ModDiagram).drawn_lines()


func _count(lines: Array[String], needle: String) -> int:
	return lines.filter(func(line: String) -> bool: return line.contains(needle)).size()


# --- the clock ----------------------------------------------------------------------------------------------------------------

func test_the_state_tells_where_the_build_up_is_and_the_mod_is_asked_as_each_tick_goes_by() -> void:
	var tides := _mount("tides")
	var mod := _mod(tides)
	var screen := _screen(ORIGINAL)
	var diagram := screen.diagram as ModDiagram
	var length := diagram.intro_length()
	assert_int(length).is_equal(60)
	assert_array(mod.call("clocks_seen")).override_failure_message("the first call, at the start of the build-up").is_equal([["intro", 0, length, -1]])
	for tick in range(1, 31):
		screen.advance_ticks(1)
	var seen: Array = mod.call("clocks_seen")
	assert_int(seen.size()).override_failure_message("one call for each tick: %s" % [seen]).is_equal(31)
	assert_array(seen[1]).is_equal(["intro", 1, length, 0])
	assert_array(seen[30]).is_equal(["intro", 30, length, 29])
	assert_int(_count(_lines(screen), "text intro 30/60")).is_equal(1)
	assert_int(_count(_lines(screen), "(100.0, 10.0)")).override_failure_message("the bar is half way at tick 30 of 60: %s" % [_lines(screen)]).is_equal(1)
	screen.advance_ticks(length - 30)
	seen = mod.call("clocks_seen")
	assert_array(seen.back()).override_failure_message("the last call of the animation carries its end").is_equal(["intro", length, length, 30])
	assert_bool(screen.is_answering()).is_true()
	assert_int(diagram.animation_tick()).is_equal(0)
	assert_str(String(diagram.animation_name())).is_equal("")
	var asked: int = mod.call("times_asked")
	assert_int(_count(_lines(screen), "intro")).override_failure_message("the idle clock was told last: no bar, no words").is_equal(0)
	assert_int(mod.call("times_asked")).is_equal(asked)
	screen.free()


func test_the_last_tick_of_a_build_up_is_told_before_the_step_that_ends_it() -> void:
	var tides := _mount("tides")
	var mod := _mod(tides)
	var screen := _screen(ORIGINAL)
	var length := (screen.diagram as ModDiagram).intro_length()
	screen.advance_ticks(length)
	var calls: Array = mod.call("calls_seen")
	var end_at := calls.find(["intro", length, "intro"])
	assert_int(end_at).override_failure_message("the end tick is told while the step is still the build-up: %s" % [calls]).is_greater(-1)
	assert_array(calls.slice(end_at)).override_failure_message("then the idle clock, then the step that follows: %s" % [calls]).is_equal([["intro", length, "intro"], ["", 0, "intro"], ["", 0, "answering"]])
	screen.free()


func test_the_calls_of_a_slow_frame_name_the_ticks_they_skipped() -> void:
	var tides := _mount("tides")
	var mod := _mod(tides)
	var screen := _screen(ORIGINAL)
	screen.advance_ticks(7)                                                                       # (seven ticks in one frame: one call, `since` says where it came from)
	screen.advance_ticks(40)
	var seen: Array = mod.call("clocks_seen")
	assert_array(seen).is_equal([["intro", 0, 60, -1], ["intro", 7, 60, 0], ["intro", 47, 60, 7]])
	screen.free()


func test_the_clock_is_the_flows_count_and_stands_still_when_it_does() -> void:
	var tides := _mount("tides")
	var mod := _mod(tides)
	var screen := _screen(ORIGINAL)
	var diagram := screen.diagram as ModDiagram
	screen.advance_ticks(25)
	var asked: int = mod.call("times_asked")
	assert_int(diagram.animation_tick()).is_equal(screen._flow.presentation_elapsed())
	assert_int(diagram.animation_tick()).is_equal(25)
	screen.process_mode = Node.PROCESS_MODE_DISABLED                                              # (the screen is paused: no time is fed to the step machine, so none goes by for the clock)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(diagram.animation_tick()).is_equal(25)
	assert_int(mod.call("times_asked")).is_equal(asked)
	screen.advance_ticks(0)
	assert_int(mod.call("times_asked")).is_equal(asked)
	assert_int(diagram.animation_length()).is_equal(diagram.plain().animation_length())
	screen.free()


func test_the_replay_has_a_clock_too_and_its_length_is_the_originals() -> void:
	var tides := _mount("tides", {}, true)
	var mod := _mod(tides)
	var screen := _screen(REPLAY)
	var diagram := screen.diagram as ModDiagram
	assert_bool(screen.is_answering()).override_failure_message("type 6 has no build-up").is_true()
	assert_array(mod.call("clocks_seen")).is_empty()
	var problem := ProblemFactory.make(REPLAY, 0, null, 0)
	screen.submit_answer(problem.expected)
	assert_int(ProblemFlow.Step.keys().find("REPLAY")).is_equal(int(screen.step()))
	assert_int(diagram.success_replay_length()).is_equal(ModProblemShelf.REPLAY_TICKS)
	var seen: Array = mod.call("clocks_seen")
	assert_array(seen[0]).is_equal(["replay", 0, ModProblemShelf.REPLAY_TICKS, -1])
	var ticks := 0
	while screen.step() == ProblemFlow.Step.REPLAY:
		screen.advance_ticks(1)
		ticks += 1
	assert_int(ticks).override_failure_message("the replay lasts the data's 88 ticks").is_equal(ModProblemShelf.REPLAY_TICKS)
	seen = mod.call("clocks_seen")
	assert_array(seen.back()).is_equal(["replay", 88, 88, 87])
	assert_int(seen.size()).override_failure_message("%s" % [seen]).is_equal(ModProblemShelf.REPLAY_TICKS + 1)
	screen.free()


func test_the_flow_takes_the_same_ticks_whichever_mod_draws_or_none() -> void:
	_shelves.append(ModProblemShelf.plain_replay())
	var original := _screen(ORIGINAL)
	var intro := _intro_ticks(original)
	original.free()
	var replay_screen := _screen(REPLAY)
	var replay := _replay_ticks(replay_screen, ProblemFactory.make(REPLAY, 0, null, 0).expected)
	replay_screen.free()
	assert_int(intro).is_equal(60)
	assert_int(replay).is_equal(ModProblemShelf.REPLAY_TICKS)
	ModProblemShelf.release(_shelves)
	for name in ["tides", "tides_hostile", "tides_faulty", "tides_spinner"]:
		var shelf := _mount(name, {}, true)
		var node := _mod(shelf)
		if node.has_method("sound_on"):
			node.call("sound_on")
		if node.has_method("flood_on"):
			node.call("flood_on")
		var screen := _screen(ORIGINAL)
		assert_int(_intro_ticks(screen)).override_failure_message("%s changed the build-up" % name).is_equal(intro)
		screen.free()
		var replay_with := _screen(REPLAY)
		assert_int(_replay_ticks(replay_with, ProblemFactory.make(REPLAY, 0, null, 0).expected)).override_failure_message("%s changed the replay" % name).is_equal(replay)
		replay_with.free()
		Mods.loader().forgive(String(shelf.id))
		ModProblemShelf.release(_shelves)


# --- the sounds ---------------------------------------------------------------------------------------------------------------

func test_a_mod_asks_for_sounds_by_name_and_the_game_plays_them_with_the_originals() -> void:
	var baseline := _mount("tides")
	_mod(baseline)
	var screen := _screen(ORIGINAL)
	_intro_ticks(screen)
	var plain_pops := _probe.sfx.count(&"diagram_pop")
	assert_int(plain_pops).override_failure_message("the build-up's own sounds: %s" % [_probe.sfx]).is_greater(0)
	assert_int(_probe.sfx.count(&"diagram_bar")).is_equal(0)                                      # (the worked example is silent until a test asks)
	screen.free()
	_probe.clear()
	ModProblemShelf.release(_shelves)
	var tides := _mount("tides")
	var mod := _mod(tides)
	mod.call("sound_on")
	var heard: Array[StringName] = []
	screen = _screen(ORIGINAL)
	screen.sfx_requested.connect(func(sfx: StringName) -> void: heard.append(sfx))
	assert_int(_intro_ticks(screen)).is_equal(60)
	assert_array(mod.call("sounds_asked")).is_equal(["diagram_bar", "diagram_bar", "diagram_bar", "diagram_bar"])     # (the ticks 15, 30, 45, 60)
	assert_int(_probe.sfx.count(&"diagram_bar")).override_failure_message("played through Audio: %s" % [_probe.sfx]).is_equal(4)
	assert_int(heard.count(&"diagram_bar")).is_equal(4)
	assert_int(_probe.sfx.count(&"diagram_pop")).override_failure_message("the original's own sounds stay").is_equal(plain_pops)
	assert_int((screen.diagram as ModDiagram).sounds().accepted).is_equal(4)
	screen.free()


func test_a_slow_frame_hears_the_sounds_of_the_ticks_it_skipped() -> void:
	var tides := _mount("tides")
	var mod := _mod(tides)
	mod.call("sound_on")
	var screen := _screen(ORIGINAL)
	screen.advance_ticks(60)                                                                      # (one frame for the whole build-up: ticks 15, 30, 45 and 60 are all behind the one call)
	assert_array(mod.call("sounds_asked")).is_equal(["diagram_bar", "diagram_bar", "diagram_bar", "diagram_bar"])
	assert_int(_probe.sfx.count(&"diagram_bar")).is_equal(4)
	screen.free()


func test_the_replay_hears_the_mods_sounds_and_the_originals() -> void:
	var tides := _mount("tides", {}, true)
	var mod := _mod(tides)
	mod.call("sound_on")
	var screen := _screen(REPLAY)
	assert_int(_replay_ticks(screen, ProblemFactory.make(REPLAY, 0, null, 0).expected)).is_equal(ModProblemShelf.REPLAY_TICKS)
	assert_int(_probe.sfx.count(&"diagram_bar")).override_failure_message("the ticks 15, 30, 45, 60 and 75 of 88: %s" % [_probe.sfx]).is_equal(5)
	assert_int(_probe.sfx.count(&"diagram_pop")).override_failure_message("the replay's own two sounds: %s" % [_probe.sfx]).is_equal(2)
	screen.free()


func test_a_mod_that_makes_its_own_sounds_silences_the_originals_and_changes_no_length() -> void:
	var tides := _mount("tides", _own_sounds("tides"), true)
	var mod := _mod(tides)
	assert_bool(ModHost.problem_screen(ORIGINAL).own_sounds).is_true()
	mod.call("sound_on")
	var screen := _screen(ORIGINAL)
	assert_int(_intro_ticks(screen)).is_equal(60)
	assert_int(_probe.sfx.count(&"diagram_pop")).override_failure_message("the build-up's own sounds are not played: %s" % [_probe.sfx]).is_equal(0)
	assert_int(_probe.sfx.count(&"diagram_bar")).is_equal(4)
	screen.submit_answer(NumberValue.parse("-1"))                                                  # (the flow's own cues are not the diagram's: `wrong` sounds)
	assert_int(_probe.sfx.count(&"wrong")).is_equal(1)
	screen.free()
	_probe.clear()
	var replay := _screen(REPLAY)
	assert_int(_replay_ticks(replay, ProblemFactory.make(REPLAY, 0, null, 0).expected)).is_equal(ModProblemShelf.REPLAY_TICKS)
	assert_int(_probe.sfx.count(&"diagram_pop")).is_equal(0)
	assert_int(_probe.sfx.count(&"correct")).is_equal(1)
	replay.free()


func test_a_mod_that_is_not_running_leaves_the_originals_sounds_whatever_its_manifest_says() -> void:
	var faulty := _mount("tides_faulty", _own_sounds("tides_faulty"))
	var mod := _mod(faulty)
	var screen := _screen(ORIGINAL)
	var diagram := screen.diagram as ModDiagram
	for i in ModLoader.MAX_FAULTS + 5:
		diagram.entry_changed(str(i))
	Mods.loader().check_health()
	assert_bool(ModHost.is_quarantined(String(faulty.id))).is_true()
	_probe.clear()
	assert_int(_intro_ticks(screen)).is_equal(60)
	assert_int(_probe.sfx.count(&"diagram_pop")).override_failure_message("a quarantined mod makes no sound of its own, so the original's play: %s" % [_probe.sfx]).is_greater(0)
	screen.free()
	Mods.loader().forgive(String(faulty.id))
	assert_object(mod).is_not_null()


func test_an_answer_with_sounds_and_no_draw_leaves_what_is_on_screen() -> void:
	var tides := _mount("tides")
	var mod := _mod(tides)
	var screen := _screen(ORIGINAL)
	screen.advance_ticks(10)
	var before := _lines(screen)
	mod.call("sound_on")
	mod.call("sound_only_on")
	screen.advance_ticks(10)                                                                      # (ticks 11 to 20: the sound of 15, and no list)
	assert_array(mod.call("sounds_asked")).is_equal(["diagram_bar"])
	assert_array(_lines(screen)).override_failure_message("the picture of the last list stays").is_equal(before)
	assert_int(_probe.sfx.count(&"diagram_bar")).is_equal(1)
	screen.free()


func test_the_call_that_builds_the_screen_has_nobody_to_hear_a_sound() -> void:
	var tides := _mount("tides")
	var mod := _mod(tides)
	mod.call("sound_on")
	var screen := _screen(3)
	assert_int(_probe.sfx.count(&"diagram_bar")).is_equal(0)
	assert_int((screen.diagram as ModDiagram).sounds().accepted).override_failure_message("the screen is not up when it is built").is_equal(0)
	screen.free()


# --- the bounds ---------------------------------------------------------------------------------------------------------------

func test_a_hostile_mod_that_floods_the_sounds_is_heard_for_a_handful_and_changes_no_play() -> void:
	var hostile := _mount("tides_hostile")
	var mod := _mod(hostile)
	mod.call("flood_on")
	var screen := _screen(ORIGINAL)
	var diagram := screen.diagram as ModDiagram
	diagram.sounds().now = func() -> int: return 0                                                  # (time stands still: the bucket gives nothing back)
	var finished: Array = []
	screen.finished.connect(func(session: ProblemSession) -> void: finished.append(session))
	_probe.clear()
	assert_int(_intro_ticks(screen)).is_equal(60)
	for i in 40:
		diagram.entry_changed(str(i))
	var asked: int = mod.call("calls_made")
	assert_int(asked).override_failure_message("the flood was made again and again").is_greater(60)
	var played := _probe.sfx.count(&"click") + _probe.sfx.count(&"correct")
	assert_int(played).override_failure_message("a hundred calls, each with %d names, are heard for the bucket's few: %s" % [mod.call("the_flood").size(), _probe.sfx]).is_less_equal(ModSounds.BURST)
	assert_int(diagram.sounds().accepted).is_less_equal(ModSounds.BURST)
	assert_int(diagram.sounds().dropped).is_greater(asked)
	assert_int(_probe.sfx.size()).override_failure_message("nothing but the sounds of a flood and the original's own is heard: %s" % [_probe.sfx]).is_less(ModSounds.BURST + 40)
	assert_bool(screen.is_answering()).is_true()
	var oxygen := GameState.oxygen()
	screen.submit_answer(NumberValue.parse("12345"))                                               # (the claims and the flood do not make an answer right: the game judges it)
	assert_int(GameState.oxygen()).is_equal(oxygen - 1)
	assert_int(int(screen.step())).is_equal(int(ProblemFlow.Step.MESSAGE))
	screen.free()
	Mods.loader().forgive(String(hostile.id))


func test_the_bucket_gives_sounds_back_with_time_and_a_made_up_name_costs_one() -> void:
	var sounds := ModSounds.new()
	var time := [0]
	sounds.now = func() -> int: return time[0]
	var heard := sounds.accept(["click", "correct", "wrong", "begin", "click"])
	assert_array(heard).override_failure_message("at most %d names of one answer" % ModSounds.MAX_PER_CALL).is_equal([&"click", &"correct", &"wrong", &"begin"])
	assert_int(sounds.dropped).is_equal(1)
	assert_int(sounds.accept(["click", "correct", "wrong", "begin"]).size()).is_equal(4)            # (the burst is 8: this empties it)
	assert_array(sounds.accept(["click"])).override_failure_message("empty: dropped").is_empty()
	time[0] = 500
	assert_int(sounds.accept(["click", "click", "click", "click", "click"]).size()).override_failure_message("half a second gives four back").is_equal(4)
	time[0] = 600
	var made_up: Array = []
	for i in 100:
		made_up.append("not_a_sound_%d" % i)
	assert_array(sounds.accept(made_up.slice(0, 4))).is_empty()
	time[0] = 10000
	assert_array(sounds.accept(made_up)).is_empty()
	assert_int(sounds.accept(["click", "click", "click", "click"]).size()).override_failure_message("a made-up name cost its token: %d are left of the burst" % ModSounds.BURST).is_less(5)
	time[0] = 60000
	assert_int(sounds.accept(["click"]).size()).is_equal(1)


func test_only_names_of_the_chains_sounds_are_kept() -> void:
	var sounds := ModSounds.new()
	assert_array(sounds.accept(null)).is_empty()
	assert_array(sounds.accept("click")).is_empty()
	assert_array(sounds.accept({"click": 1})).is_empty()
	assert_array(sounds.accept([12, null, ["click"], Vector2(1, 1), "", "Click", "../x", "res://icon.svg", "a b", "click"])).override_failure_message("what is not a name, and a name that is not a sound").is_empty()
	var fresh := ModSounds.new()
	assert_array(fresh.accept([&"click"])).is_equal([&"click"])                                      # (a StringName is a name)
	var long_name := "x".repeat(300)
	assert_array(ModSounds.new().accept([long_name])).is_empty()
	assert_bool(Catalog.sfx_catalog().can_play(&"diagram_bar")).is_true()
	assert_bool(Catalog.sfx_catalog().can_play(&"no_such_sound_at_all")).is_false()


func test_a_sound_the_mods_own_pack_ships_is_a_sound_of_the_chain() -> void:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture("%s/tides" % ModProblemShelf.FIXTURES)
	ModProblemShelf.add_files(shelf)
	shelf.write_bytes("audio/sound/tide_bell.ogg", FileAccess.get_file_as_bytes("res://tests/fixtures/pack_blip.ogg.bin"))
	shelf.write_text("audio/sound/tide_junk.ogg", "not an ogg")
	assert_array(ModSounds.new().accept(["tide_bell"])).override_failure_message("before the pack is in the chain").is_empty()
	shelf.mount()
	Mods.sync()
	assert_array(ModSounds.new().accept(["tide_bell", "tide_junk"])).override_failure_message("the pack's own file is a sound by its name; a file that is no sound is not").is_equal([&"tide_bell"])
	assert_object(Catalog.sfx_catalog().stream_named(&"tide_bell")).is_not_null()


# --- the manifest -------------------------------------------------------------------------------------------------------------

func test_own_sounds_is_a_manifest_key_of_api_five() -> void:
	var errors: Array[String] = []
	var spec := ModSpec.parse({"entry": "a.sgd", "requires_api": 5, "problems": {"types": [40], "own_sounds": true}}, errors)
	assert_array(errors).is_empty()
	assert_bool(spec.problem_own_sounds).is_true()
	assert_bool(spec.tells_problem_state()).is_true()
	assert_dict(spec.to_dict()["problems"]).is_equal({"types": [40], "own_sounds": true})
	var off := ModSpec.parse({"entry": "a.sgd", "requires_api": 3, "problems": {"types": [40], "own_sounds": false}}, [] as Array[String])
	assert_bool(off == null or not off.problem_own_sounds).is_true()
	errors = []
	ModSpec.parse({"entry": "a.sgd", "requires_api": 4, "problems": {"types": [40], "own_sounds": true}}, errors)
	assert_array(errors).is_not_empty()
	assert_str(errors[0]).contains("own_sounds").contains("5")
	errors = []
	ModSpec.parse({"entry": "a.sgd", "requires_api": 5, "problems": {"types": [40], "own_sounds": "yes"}}, errors)
	assert_str(errors[0]).contains("own_sounds").contains("true or false")
	assert_int(ModSpec.DRAWS_THE_GAME_API_VERSION).is_less_equal(ModSpec.API_VERSION)
	assert_bool(ModSpec.parse({"entry": "a.sgd", "requires_api": 4, "problems": {"types": [40]}}, [] as Array[String]).tells_problem_state()).is_false()
