class_name TestScreenPlaytest
extends GdUnitTestSuite
## Teaches: testing a tool by what it does to the rules. The playtest of a screen is a `PlaytestSetup`: plain data that turns
## into command-line words and back, and is applied to a fresh `SimWorld` before the first tick. The claims: the words round-trip;
## a preset gives the numbers it promises; applying a setup gives the state it says (air, pieces, flags, creatures, where the sub
## is); the tool scene does the same from the environment variable; the dialog and the launcher of the screen editor read and
## write the same setup; and, above all, that the DEFAULT setup of the start screen (and of the respawn screen) plays exactly the
## trace of the normal start of the sector, so a playtest changes no rule. Starting the game from the editor itself
## (`play_custom_scene`) is checked by hand.

const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"
const SCENE := "res://src/debug/screen_playtest.tscn"
const TICKS := 300


func after_test() -> void:
	OS.unset_environment(FoeSandbox.ARGS_ENV)
	GameClock.paused = false
	Engine.time_scale = 1.0
	GameState.reset()


## A player's game that is not in any tree (what `SimWorld` works on in the tests; the game has the autoload).
func _new_run() -> Node:
	var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
	run.reset()
	return run


## The first creature of `sector` that starts on `screen`, or -1.
func _foe_on(sector: int, screen: int) -> int:
	var data := Catalog.sector(sector)
	for i in data.foes.size():
		if data.foes[i].screen == screen:
			return i
	return -1


# --- the words -------------------------------------------------------------------------

func test_a_setup_round_trips_through_its_words() -> void:
	var setup := PlaytestSetup.new()
	setup.sector = 7
	setup.screen = 4
	setup.start = PlaytestSetup.START_AT
	setup.sub_pos = Vector2i(200, 150)
	setup.cell = 2
	setup.tanks = 5
	setup.oxygen = 1
	setup.ink = 9
	setup.pieces_mask = 0b1010011
	setup.flags = 0x8001
	setup.foe_states = {12: PlaytestSetup.FOE_DORMANT, 3: PlaytestSetup.FOE_DORMANT_HIDDEN, 40: PlaytestSetup.FOE_WOKEN}
	setup.paused = true
	var words := setup.to_arguments()
	assert_str(words).contains("--start=200,150").contains("--foes=3:dormant+hidden,12:dormant,40:woken").contains("--pause")
	assert_bool(words.contains("\n") or words.contains("\t")).is_false()
	var back := PlaytestSetup.from_arguments(words.split(" "))
	assert_bool(back.equals(setup)).is_true()
	assert_int(back.sector).is_equal(7)
	assert_int(back.screen).is_equal(4)
	assert_str(back.start).is_equal(PlaytestSetup.START_AT)
	assert_vector(back.sub_pos).is_equal(Vector2i(200, 150))
	assert_int(back.pieces_mask).is_equal(0b1010011)
	assert_int(back.flags).is_equal(0x8001)
	assert_dict(back.foe_states).is_equal(setup.foe_states)
	assert_bool(back.paused).is_true()
	# every named start survives, and the default says nothing
	for named in [PlaytestSetup.START_LAUNCH, PlaytestSetup.START_RESPAWN, PlaytestSetup.START_CENTRE]:
		setup.start = named
		assert_str(PlaytestSetup.from_arguments(setup.to_arguments().split(" ")).start).is_equal(named)
	setup.start = PlaytestSetup.START_DEFAULT
	assert_str(setup.to_arguments()).not_contains("--start")
	assert_str(PlaytestSetup.from_arguments(setup.to_arguments().split(" ")).start).is_equal(PlaytestSetup.START_DEFAULT)


func test_unknown_words_and_bad_values_are_ignored() -> void:
	var setup := PlaytestSetup.from_arguments(PackedStringArray([
			"--nonsense", "plain", "--start=sideways", "--foes=x:dormant,3:asleep,4:hidden,5", "--screen=3", "--fly"]))
	assert_str(setup.start).is_equal(PlaytestSetup.START_DEFAULT)
	assert_dict(setup.foe_states).is_equal({4: PlaytestSetup.FOE_HIDDEN})
	assert_int(setup.screen).is_equal(3)
	assert_bool(setup.paused).is_false()
	assert_bool(PlaytestSetup.from_arguments(PackedStringArray()).equals(PlaytestSetup.new())).is_true()


func test_the_defaults_are_a_new_players_numbers() -> void:
	var setup := PlaytestSetup.new()
	assert_int(setup.tanks).is_equal(Tuning.resolve().refill_tanks)
	assert_int(setup.oxygen).is_equal(Tuning.resolve().max_oxygen)
	assert_int(setup.ink).is_equal(Tuning.resolve().ink_max)
	assert_int(setup.pieces_mask).is_equal(0)
	assert_int(setup.flags).is_equal(0)
	assert_array(setup.problems()).is_empty()


# --- the presets -------------------------------------------------------------------------

func test_the_presets_give_the_numbers_they_promise() -> void:
	var sector := Ground.main()
	var all := (1 << sector.pieces.size()) - 1
	var start := PlaytestSetup.from_preset(PlaytestSetup.PRESET_START, Ground.MAIN, 3)
	assert_int(start.tanks).is_equal(Tuning.resolve().refill_tanks)
	assert_int(start.pieces_mask).is_equal(0)
	var full := PlaytestSetup.from_preset(PlaytestSetup.PRESET_FULL, Ground.MAIN, 3)
	assert_int(full.tanks).is_equal(Tuning.resolve().max_tanks)
	assert_int(full.oxygen).is_equal(Tuning.resolve().max_oxygen)
	assert_int(full.ink).is_equal(Tuning.resolve().ink_max)
	var low := PlaytestSetup.from_preset(PlaytestSetup.PRESET_LOW_OXYGEN, Ground.MAIN, 3)
	assert_int(low.oxygen).is_equal(1)
	assert_int(low.tanks).is_equal(1)
	assert_int(PlaytestSetup.from_preset(PlaytestSetup.PRESET_NO_INK, Ground.MAIN, 3).ink).is_equal(0)
	# every piece but those of the screen: pick a screen that has one
	var screen := sector.pieces[0].screen
	var here := PlaytestSetup.pieces_mask_of_screen(Ground.MAIN, screen)
	assert_int(here).is_not_equal(0)
	var others := PlaytestSetup.from_preset(PlaytestSetup.PRESET_ALL_BUT_HERE, Ground.MAIN, screen)
	assert_int(others.pieces_mask).is_equal(all & ~here)
	assert_int(others.pieces_mask & here).is_equal(0)
	assert_int(others.tanks).is_equal(Tuning.resolve().max_tanks)
	for preset in PlaytestSetup.PRESETS:
		assert_array(PlaytestSetup.from_preset(preset, 0, screen).problems()).is_empty()
		assert_bool(PlaytestSetup.PRESET_TITLES.has(preset)).is_true()


func test_a_preset_leaves_the_place_of_the_sub_and_the_creatures() -> void:
	var setup := PlaytestSetup.new()
	setup.start = PlaytestSetup.START_CENTRE
	setup.foe_states = {1: PlaytestSetup.FOE_HIDDEN}
	setup.paused = true
	setup.flags = 5
	setup.apply_preset(PlaytestSetup.PRESET_LOW_OXYGEN)
	assert_str(setup.start).is_equal(PlaytestSetup.START_CENTRE)
	assert_dict(setup.foe_states).is_equal({1: PlaytestSetup.FOE_HIDDEN})
	assert_bool(setup.paused).is_true()
	assert_int(setup.flags).is_equal(0)                    # (the numbers are the preset's: flags too)


# --- applying a setup ---------------------------------------------------------------------

func test_applying_a_setup_makes_the_state_it_says() -> void:
	var run := _new_run()
	var sim := SimWorld.new(run)
	var sector := Ground.main()
	var screen := sector.pieces[1].screen if sector.pieces[1].screen != 0 else sector.pieces[2].screen
	var foe := _foe_on(Ground.MAIN, screen)
	assert_int(foe).is_greater(-1)
	var setup := PlaytestSetup.from_preset(PlaytestSetup.PRESET_ALL_BUT_HERE, Ground.MAIN, screen)
	setup.tanks = 4
	setup.oxygen = 2
	setup.ink = 7
	setup.flags = 0b101
	setup.foe_states = {foe: PlaytestSetup.FOE_DORMANT_HIDDEN}
	setup.start = PlaytestSetup.START_AT
	setup.sub_pos = Vector2i(300, 120)
	setup.cell = 3
	setup.apply(sim)
	# the numbers of the run
	assert_int(run.tanks()).is_equal(4)
	assert_int(run.oxygen()).is_equal(2)
	assert_int(run.ink).is_equal(7)
	assert_int(run.pieces_mask).is_equal(setup.pieces_mask)
	assert_int(run.sector).is_equal(Ground.MAIN)
	# the screen, its pieces (only the ones not collected lie there) and the flags
	assert_int(sim.sector_index).is_equal(Ground.MAIN)
	assert_int(sim.screen_index).is_equal(screen)
	var lying := PlaytestSetup.pieces_mask_of_screen(Ground.MAIN, screen)
	var lying_numbers: Array = sim.pieces.map(func(piece: PieceModel) -> int: return piece.index)
	assert_int(lying_numbers.size()).is_equal(PlaytestSetup._count_bits(lying))
	for number in lying_numbers:
		assert_int((setup.pieces_mask >> number) & 1).is_equal(0)
	assert_int(sim.foe_context.semaphore).is_equal(0b101)
	# the creature, and one nobody mentioned
	assert_bool(sim.foes[foe].vm.dormant).is_true()
	assert_bool(sim.foes[foe].vm.hidden).is_true()
	assert_bool(sim.foes[foe].is_touchable()).is_false()
	for other in sim.foes.size():
		if other != foe:
			assert_bool(sim.foes[other].vm.dormant).is_equal(sector.foes[other].dormant)
			assert_bool(sim.foes[other].vm.hidden).is_equal(sector.foes[other].hidden)
	# the sub
	assert_bool(sim.sub.active).is_true()
	assert_bool(sim.sub.controlled).is_true()
	assert_vector(sim.sub.original_position()).is_equal(Vector2i(300, 120))
	assert_int(sim.sub.cell).is_equal(3)
	assert_array(setup.problems()).is_empty()


func test_a_woken_creature_runs_and_a_dormant_one_does_not() -> void:
	var sector := Ground.MAIN                            # (it has a creature that starts asleep, beside an awake one)
	var data := Catalog.sector(sector)
	var sleeper := -1
	var awake := -1
	for i in data.foes.size():
		if data.foes[i].dormant and sleeper < 0:
			sleeper = i
	assert_int(sleeper).is_greater(-1)
	var screen := data.foes[sleeper].screen
	for i in data.foes.size():
		if not data.foes[i].dormant and data.foes[i].screen == screen and awake < 0:
			awake = i
	var setup := PlaytestSetup.new()
	setup.sector = sector
	setup.screen = screen
	setup.start = PlaytestSetup.START_CENTRE
	var sim := SimWorld.new(_new_run())
	setup.apply(sim)
	assert_bool(sim.foes[sleeper].vm.can_run(screen)).is_false()           # as the file says
	setup.foe_states = {sleeper: PlaytestSetup.FOE_WOKEN}
	setup.apply(sim)
	assert_bool(sim.foes[sleeper].vm.dormant).is_false()
	assert_bool(sim.foes[sleeper].vm.can_run(screen)).is_true()
	if awake >= 0:
		setup.foe_states = {awake: PlaytestSetup.FOE_DORMANT}
		setup.apply(sim)
		assert_bool(sim.foes[awake].vm.can_run(screen)).is_false()
		assert_bool(sim.foes[sleeper].vm.dormant).is_true()               # (a setup starts from the records again)


func test_where_the_sub_starts_by_default() -> void:
	var data := Ground.main()
	# screen 0: the launch from the station, as in the game
	var launch := PlaytestSetup.new()
	launch.sector = Ground.MAIN
	var sim := SimWorld.new(_new_run())
	launch.apply(sim)
	assert_str(launch.resolved_start()).is_equal(PlaytestSetup.START_LAUNCH)
	assert_bool(sim.sub.controlled).is_false()
	assert_bool(sim.sequence != null and not sim.sequence.is_done()).is_true()
	# screen 6: the respawn point of the sector, with its picture (the start marker of the screen editor)
	var respawn := PlaytestSetup.new()
	respawn.sector = Ground.MAIN
	respawn.screen = Tuning.resolve().midpoint_screen
	respawn.apply(sim)
	assert_str(respawn.resolved_start()).is_equal(PlaytestSetup.START_RESPAWN)
	assert_vector(sim.sub.original_position()).is_equal(data.start_pos)
	assert_int(sim.sub.cell).is_equal(data.start_frame)
	assert_bool(sim.sub.controlled).is_true()
	assert_bool(sim.run.midpoint_reached).is_true()          # (the game says so when screen 6 is entered)
	# any other screen: the middle of the playfield
	var middle := PlaytestSetup.new()
	middle.sector = Ground.MAIN
	middle.screen = 3
	middle.apply(sim)
	assert_str(middle.resolved_start()).is_equal(PlaytestSetup.START_CENTRE)
	assert_vector(sim.sub.original_position()).is_equal(PlaytestSetup.centre_position())
	var playfield := Rect2i(Vector2i(SubModel.PLAYFIELD_ORIGIN), TileGrid.PLAYFIELD_SIZE)
	assert_bool(playfield.encloses(Rect2i(sim.sub.original_position(), PieceModel.SUB_PICTURE_SIZE))).is_true()
	assert_int(sim.screen_index).is_equal(3)


func test_what_the_game_cannot_give_is_reported_and_brought_into_range() -> void:
	var setup := PlaytestSetup.new()
	setup.screen = 3
	setup.start = PlaytestSetup.START_LAUNCH                 # the station is on screen 0
	setup.tanks = 9
	setup.oxygen = 0
	setup.ink = 99
	setup.pieces_mask = 1 << 20
	setup.flags = 0x1FFFF
	setup.foe_states = {999: PlaytestSetup.FOE_HIDDEN}
	var found := setup.problems()
	assert_int(found.size()).is_equal(7)
	var sim := SimWorld.new(_new_run())
	setup.apply(sim)
	assert_int(sim.run.tanks()).is_equal(Tuning.resolve().max_tanks)
	assert_int(sim.run.oxygen()).is_equal(1)
	assert_int(sim.run.ink).is_equal(Tuning.resolve().ink_max)
	assert_int(sim.run.pieces_mask).is_equal(0)
	assert_int(sim.foe_context.semaphore).is_equal(0xFFFF)
	assert_vector(sim.sub.original_position()).is_equal(PlaytestSetup.centre_position())
	assert_bool(sim.sub.controlled).is_true()
	var outside := PlaytestSetup.new()
	outside.start = PlaytestSetup.START_AT
	outside.sub_pos = Vector2i(2000, -5)
	assert_array(outside.problems()).has_size(1)
	outside.apply(sim)
	var playfield := Rect2i(Vector2i(SubModel.PLAYFIELD_ORIGIN), TileGrid.PLAYFIELD_SIZE)
	assert_bool(playfield.encloses(Rect2i(sim.sub.original_position(), PieceModel.SUB_PICTURE_SIZE))).is_true()


# --- no rule changes ----------------------------------------------------------------------

## The trace of `ticks` ticks of the scripted flight of `SimTrace.Hands`, after `start` has set the sim up.
func _trace_of(start: Callable, sector: int, screen: int, ticks: int) -> Array[String]:
	var run := _new_run()
	var sim := SimWorld.new(run)
	start.call(sim)
	sim.foe_context.rng.seed = 4242                          # (the creature scripts roll dice)
	var trace := SimTrace.record(sim, run)
	trace.flush("started")
	var hands := SimTrace.Hands.new(sector, screen)
	for t in ticks:
		sim.tick(hands.at(t))
		if sim.problem_active:
			sim.problem_resolved(1, ProblemSession.new(null))
	trace.flush("end")
	return trace.lines


func test_the_default_setup_of_the_start_screen_plays_the_trace_of_the_normal_start() -> void:
	for sector in [Ground.MAIN, Ground.LEDGE, Ground.MAP, Ground.FINALE]:
		var normal := _trace_of(func(sim: SimWorld) -> void:
			sim.begin_sector(sector, false)
			sim.start_launch(), sector, 0, TICKS)
		var playtest := _trace_of(func(sim: SimWorld) -> void:
			var setup := PlaytestSetup.new()
			setup.sector = sector
			setup.apply(sim), sector, 0, TICKS)
		assert_int(normal.size()).is_greater(TICKS)
		assert_array(playtest).override_failure_message("sector %d: the default setup of screen 0 plays differently from the start of the sector" % sector).is_equal(normal)


func test_the_default_setup_of_the_respawn_screen_plays_the_trace_of_the_respawn() -> void:
	for sector in [Ground.MAIN, Ground.EDIT, Ground.MAP]:
		var normal := _trace_of(func(sim: SimWorld) -> void: sim.begin_sector(sector, true), sector, Tuning.resolve().midpoint_screen, TICKS)
		var playtest := _trace_of(func(sim: SimWorld) -> void:
			var setup := PlaytestSetup.new()
			setup.sector = sector
			setup.screen = Tuning.resolve().midpoint_screen
			setup.apply(sim), sector, Tuning.resolve().midpoint_screen, TICKS)
		assert_array(playtest).override_failure_message("sector %d: the default setup of screen 6 plays differently from the respawn" % sector).is_equal(normal)


## A playtest starts its sector through the rules' entry the game's own start is built from (`SimWorld.begin_sector_on`), on any
## screen: the "begin" sound once, the screen entered (on screen 6 the midpoint is reached), and the creatures it sets keep their
## state after it. It makes no step of that entry itself (docs/engine/ARCHITECTURE.md, "Derived state is built from its owner").
func test_a_playtest_on_any_screen_starts_the_sector_through_the_rules_entry() -> void:
	for screen in [0, 3, Tuning.resolve().midpoint_screen]:
		var sim := SimWorld.new(_new_run())
		var sounds: Array[StringName] = []
		sim.sound_requested.connect(func(id: StringName) -> void: sounds.append(id))
		var setup := PlaytestSetup.new()
		setup.sector = Ground.MAIN
		setup.screen = screen
		var foe := _foe_on(Ground.MAIN, screen)
		if foe >= 0:
			setup.foe_states = {foe: PlaytestSetup.FOE_HIDDEN}
		setup.apply(sim)
		assert_array(sounds.filter(func(id: StringName) -> bool: return id == SimWorld.SFX_BEGIN)) \
				.override_failure_message("screen %d: one \"begin\" sound" % screen).has_size(1)
		assert_int(sim.screen_index).is_equal(screen)
		assert_bool(sim.run.midpoint_reached).is_equal(screen == Tuning.resolve().midpoint_screen)
		if foe >= 0:
			assert_bool(sim.foes[foe].vm.hidden).is_true()
	assert_array(SourceScan.find("res://src/debug/playtest_setup.gd", ["load_sector", "screen_entered", "SFX_BEGIN", "sound_requested"])) \
			.is_empty()


## `SimWorld.begin_sector` is `begin_sector_on` with the sub placed: both make the same sector, screen, run and sounds.
func test_begin_sector_is_built_from_begin_sector_on() -> void:
	for past_midpoint in [false, true]:
		var screen := Tuning.resolve().midpoint_screen if past_midpoint else 0
		var lines: Array = []
		for use_entry in [true, false]:
			var run := _new_run()
			var sim := SimWorld.new(run)
			var events: Array[String] = []
			sim.sound_requested.connect(func(id: StringName) -> void: events.append("sound %s" % id))
			sim.screen_loaded.connect(func(sector: int, at: int) -> void: events.append("screen %d %d" % [sector, at]))
			if use_entry:
				sim.begin_sector(Ground.MAIN, past_midpoint)
			else:
				sim.begin_sector_on(Ground.MAIN, screen)
				if past_midpoint:
					sim.start_flight()
			events.append("%d %d %s %s %s" % [sim.sector_index, sim.screen_index, run.midpoint_reached, sim.sub.active,
					sim.sub.original_position()])
			lines.append(events)
		assert_array(lines[1]).is_equal(lines[0])


func test_the_words_make_the_same_game_as_the_object() -> void:
	var setup := PlaytestSetup.from_preset(PlaytestSetup.PRESET_ALL_BUT_HERE, Ground.EDIT, 4)
	setup.flags = 3
	setup.foe_states = {0: PlaytestSetup.FOE_HIDDEN}
	var direct := _trace_of(func(sim: SimWorld) -> void: setup.apply(sim), Ground.EDIT, 4, 120)
	var from_words := _trace_of(func(sim: SimWorld) -> void: PlaytestSetup.from_arguments(setup.to_arguments().split(" ")).apply(sim), Ground.EDIT, 4, 120)
	assert_array(from_words).is_equal(direct)


# --- the tool scene ---------------------------------------------------------------------------

func test_the_tool_scene_applies_the_setup_from_the_environment_and_runs() -> void:
	var setup := PlaytestSetup.from_preset(PlaytestSetup.PRESET_LOW_OXYGEN, Ground.MAIN, 4)
	setup.ink = 5
	setup.flags = 0b11
	setup.paused = true
	var foe := _foe_on(Ground.MAIN, 4)
	if foe >= 0:
		setup.foe_states = {foe: PlaytestSetup.FOE_HIDDEN}
	OS.set_environment(FoeSandbox.ARGS_ENV, setup.to_arguments())
	var playtest := scene_runner(SCENE).scene() as ScreenPlaytest
	assert_bool(playtest.setup.equals(setup)).is_true()
	assert_int(playtest.world.sector_index).is_equal(Ground.MAIN)
	assert_int(playtest.world.screen_index).is_equal(4)
	assert_int(GameState.oxygen()).is_equal(1)
	assert_int(GameState.tanks()).is_equal(1)
	assert_int(GameState.ink).is_equal(5)
	assert_bool(GameClock.paused).is_true()
	assert_bool(playtest.world.sim.sub.active).is_true()
	assert_vector(playtest.world.sim.sub.original_position()).is_equal(PlaytestSetup.centre_position())
	if foe >= 0:
		assert_bool(playtest.world.sim.foes[foe].vm.hidden).is_true()
	assert_str(playtest.title_label.text).contains("sector %d" % Ground.MAIN).contains("screen 4").contains("[paused]")
	var creatures := playtest.world.sim.foes.map(func(f: FoeModel) -> Array: return [f.vm.x, f.vm.y, f.vm.pc])
	for i in 6:
		GameClock.step()
	assert_int(playtest.world.sim.tick_number).is_equal(6)
	assert_int(playtest.world.screen_index).is_equal(4)
	# the same ticks in a bare sim give the same creatures
	var bare := SimWorld.new(_new_run())
	PlaytestSetup.from_arguments(setup.to_arguments().split(" ")).apply(bare)
	bare.foe_context.rng.seed = playtest.world.sim.foe_context.rng.seed
	assert_array(creatures).is_equal(bare.foes.map(func(f: FoeModel) -> Array: return [f.vm.x, f.vm.y, f.vm.pc]))


func test_the_tool_scene_starts_over_when_a_tank_is_lost() -> void:
	var setup := PlaytestSetup.from_preset(PlaytestSetup.PRESET_LOW_OXYGEN, Ground.MAIN, 2)
	setup.paused = true
	OS.set_environment(FoeSandbox.ARGS_ENV, setup.to_arguments())
	var playtest := scene_runner(SCENE).scene() as ScreenPlaytest
	playtest.world.sim.sub.place_original(100, 100, 2)
	GameState.update_oxygen(-1)                         # the only oxygen of the only spare tank: the tank is lost
	assert_str(playtest.title_label.text).not_contains("started over")     # (not inside the signal: a little later, as the game)
	await await_idle_frame()
	assert_int(playtest.world.screen_index).is_equal(2)         # (not the start of the sector)
	assert_int(GameState.oxygen()).is_equal(1)
	assert_int(GameState.tanks()).is_equal(1)
	assert_vector(playtest.world.sim.sub.original_position()).is_equal(PlaytestSetup.centre_position())
	assert_str(playtest.title_label.text).contains("started over 1")


## A canister problem that costs the tank announces the loss while it closes, BEFORE the rules hear how it went
## (`SimWorld.problem_resolved`, which takes the canister back). The playtest starts over after that call, as the game respawns after
## it, so the setup's collected canister is the one the new start has.
func test_a_problem_that_costs_the_tank_starts_over_after_the_rules_heard_of_it() -> void:
	var setup := PlaytestSetup.from_preset(PlaytestSetup.PRESET_LOW_OXYGEN, Ground.MAIN, 2)
	setup.pieces_mask = 1                               # the canister is collected
	setup.paused = true
	OS.set_environment(FoeSandbox.ARGS_ENV, setup.to_arguments())
	var playtest := scene_runner(SCENE).scene() as ScreenPlaytest
	var sim := playtest.world.sim
	sim.problem_active = true                            # the canister's problem is open (`open_pending_problem`)
	GameState.hold_losses()                              # (what the problem screen does while it is up)
	var session := ProblemSession.new(null)
	session.oxygen_code = GameState.update_oxygen(-1)    # a wrong answer takes the last air
	GameState.release_losses()                           # the screen closes: the run announces the lost tank
	sim.problem_resolved(SimWorld.CANISTER_SLOT, session) # and then the rules hear how it went
	await await_idle_frame()
	assert_str(playtest.title_label.text).contains("started over 1")
	assert_bool(GameState.has_piece(0)).is_true()        # the setup's canister, not the one the old problem took back
	assert_bool(sim.problem_active).is_false()
	assert_int(GameState.oxygen()).is_equal(1)
	assert_int(GameState.tanks()).is_equal(1)


# --- the screen editor's side --------------------------------------------------------------

func _editor(sector: int, screen: int, dir: String = ScreenEditor.DATA_DIR) -> ScreenEditor:
	var editor := auto_free(ScreenEditor.new()) as ScreenEditor
	editor.data_dir = dir
	editor.sector = sector
	editor.screen = screen
	add_child(editor)                                    # (its _ready loads the screen)
	return editor


func _dialog(editor: ScreenEditor) -> ScreenEditorPlaytestDialog:
	var dialog := auto_free(ScreenEditorPlaytestDialog.new()) as ScreenEditorPlaytestDialog
	dialog.editor = editor
	add_child(dialog)
	dialog.build()
	return dialog


func test_the_dialog_reads_back_the_setup_it_was_given() -> void:
	var editor := _editor(Ground.MAIN, 2)
	var dialog := _dialog(editor)
	var foe := _foe_on(Ground.MAIN, 2)
	var setup := PlaytestSetup.from_preset(PlaytestSetup.PRESET_ALL_BUT_HERE, Ground.MAIN, 2)
	setup.ink = 3
	setup.flags = 0x0104
	setup.start = PlaytestSetup.START_AT
	setup.sub_pos = Vector2i(120, 100)
	setup.cell = 1
	setup.foe_states = {40: PlaytestSetup.FOE_DORMANT}
	if foe >= 0:
		setup.foe_states[foe] = PlaytestSetup.FOE_HIDDEN
	setup.paused = true
	dialog.fill(setup)
	assert_bool(dialog.read().equals(setup)).override_failure_message(dialog.read().to_arguments() + " != " + setup.to_arguments()).is_true()
	# the start options that the screen does not have are greyed out
	assert_bool(dialog._start.is_item_disabled(1)).is_true()
	assert_bool(dialog._start.is_item_disabled(2)).is_true()
	# a preset changes the numbers and nothing else
	dialog._preset.select(dialog._preset.get_item_index(PlaytestSetup.PRESETS.find(PlaytestSetup.PRESET_NO_INK)))
	dialog._on_preset_selected(dialog._preset.selected)
	var after := dialog.read()
	assert_int(after.ink).is_equal(0)
	assert_int(after.tanks).is_equal(Tuning.resolve().refill_tanks)
	assert_int(after.pieces_mask).is_equal(0)
	assert_dict(after.foe_states).is_equal(setup.foe_states)
	assert_vector(after.sub_pos).is_equal(Vector2i(120, 100))


func test_the_dialog_for_screen_six_offers_the_respawn_point_and_the_marker_is_not_saved() -> void:
	var editor := _editor(0, Tuning.resolve().midpoint_screen)
	var saved := editor.build()
	var signature_clean := editor.is_dirty()
	var dialog := _dialog(editor)
	assert_bool(dialog._start.is_item_disabled(2)).is_false()
	assert_bool(dialog._start.is_item_disabled(1)).is_true()
	assert_str(dialog.read().resolved_start()).is_equal(PlaytestSetup.START_RESPAWN)
	assert_vector(Vector2i(dialog._x.value, dialog._y.value)).is_equal(Ground.main().start_pos)
	# the marker: made once, found again, snapped to the sub's grid, read by the dialog, and the screen has not changed
	assert_object(ScreenEditorPlaytestStart.find_in(editor)).is_null()
	var marker := ScreenEditorPlaytestStart.ensure_in(editor, Vector2i(200, 120), 4)
	assert_object(ScreenEditorPlaytestStart.ensure_in(editor, Vector2i(10, 10))).is_same(marker)
	marker.position = Vector2(203, 121)
	assert_vector(marker.position).is_equal(Vector2(204, 122))
	dialog._start.select(ScreenEditorPlaytestDialog.START_MARKER)
	var setup := dialog.read()
	assert_str(setup.start).is_equal(PlaytestSetup.START_AT)
	assert_vector(setup.sub_pos).is_equal(Vector2i(204, 122))
	assert_int(setup.cell).is_equal(4)
	assert_bool(editor.is_dirty()).is_equal(signature_clean)
	assert_str(ScreenFile.screen_text(editor.build().screen)).is_equal(ScreenFile.screen_text(saved.screen))
	assert_array(editor.build().problems).is_equal(saved.problems)
	assert_int(editor.build().start_pos.x).is_equal(Ground.main().start_pos.x)            # the respawn point is not the marker


func test_playing_hands_the_game_the_words_and_refuses_what_it_cannot_play() -> void:
	var editor := _editor(Ground.MAIN, 5)
	var started: Array[String] = []
	var setup := PlaytestSetup.from_preset(PlaytestSetup.PRESET_FULL, 9, 9)           # (sector and screen are the editor's)
	assert_str(ScreenEditorPlaytest.run(editor, setup, func(words: String) -> void: started.append(words))).is_empty()
	assert_array(started).has_size(1)
	var played := PlaytestSetup.from_arguments(started[0].split(" "))
	assert_int(played.sector).is_equal(Ground.MAIN)
	assert_int(played.screen).is_equal(5)
	assert_int(played.tanks).is_equal(Tuning.resolve().max_tanks)
	# an editor on a copy of the data is not the game's data
	var copy := _editor(Ground.MAIN, 5, "user://not_the_game")
	assert_str(ScreenEditorPlaytest.run(copy, setup, func(words: String) -> void: started.append(words))).starts_with("Not played")    # (no files there)
	copy.load_error = ""
	assert_str(ScreenEditorPlaytest.why_not(copy)).contains("copy")
	# a screen with a problem the files do not show is not played as if it were saved
	var broken := _editor(Ground.MAIN, 5)
	broken.get_node("BackDecos").add_child(Node2D.new())
	var refusal := ScreenEditorPlaytest.run(broken, setup, func(words: String) -> void: started.append(words))
	assert_str(refusal).starts_with("Not played").contains("can not be saved")
	assert_array(started).has_size(1)
	broken.get_node("BackDecos").get_child(-1).free()
