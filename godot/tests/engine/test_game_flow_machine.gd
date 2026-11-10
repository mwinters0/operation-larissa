class_name TestGameFlowMachine
extends GdUnitTestSuite
## Teaches: testing the FLOW of a whole mission WITHOUT a scene. `GameFlow` decides what happens next - the sector
## starts, the dock, the lock, the supply message, the next sector, a lost tank, game over, the finale, the Hall of Fame - and asks
## its view to show things. Here the view is a fake that only writes down what it was asked, the playfield is a `SimWorld` and
## nothing else (`HeadlessStage`), the player's numbers are a fresh `GameState` that is in no tree, and the save store is a fake that
## counts the saves. The real view is tested with the real scene (`tests/engine/test_game_flow.gd`, `test_flow_fidelity.gd`).

const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"


var _run: Object
var _player: PlayerProfile
var _clock: StubClock
var _messages: MessageQueue
var _store: FakeSaveStore
var _stage: HeadlessStage
var _view: FakeFlowView
var _flow: GameFlow
var _log: Array
var _later: Array[Callable]


func before_test() -> void:
	_log = []
	_later = []
	_run = auto_free(load(GAME_STATE_SCRIPT).new())               # the script of the autoload, not in any tree
	_player = PlayerProfile.new_player("Tester", PlayerProfile.Game.VOYAGER)
	_player.hints_enabled = false                                  # (no hint boxes in the way unless a test asks for them)
	_run.profile = _player
	_clock = StubClock.new()
	_messages = MessageQueue.new(_clock)
	_store = FakeSaveStore.new()
	_store.watched = _player
	_stage = HeadlessStage.new(_run)
	_stage.log = _log
	_view = FakeFlowView.new(_log, _run)
	_flow = GameFlow.new(_run, _store, _messages)
	_flow.world = _stage
	_flow.view = _view
	_flow.defer_call = func(action: Callable) -> void: _later.append(action)     # (the test decides when "a little later" is)


func after_test() -> void:
	_flow.leave()


## Runs what the flow put off ("a little later, outside the signal"), the way the idle frame does in the game.
func _run_deferred() -> void:
	var batch := _later.duplicate()
	_later.clear()
	for action: Callable in batch:
		action.call()


func _enter(sector: int = 0) -> void:
	_player.progress = sector * 2
	_flow.enter(0, 1)


## Collects every piece of the sector that is loaded.
func _collect_all() -> void:
	for i in _stage.sector.pieces.size():
		_run.collect_piece(i)


# --- what the flow is made of ---------------------------------------------------------------

func test_it_is_a_plain_object_without_nodes_textures_fonts_input_or_autoloads() -> void:
	assert_bool(GameFlow.new(_run, _store, _messages) is RefCounted).is_true()
	# its source never names what a view is made of, nor an autoload (comments and strings do not count; the guard for all the
	# rules is tests/engine/test_rules_are_plain_objects.gd, this one pins the flow by itself)
	var found := SourceScan.find("res://src/rules/game_flow.gd", TestRulesArePlainObjects.FORBIDDEN)
	assert_array(found).override_failure_message("the flow names a view or an autoload:\n" + "\n".join(found)).is_empty()


func test_the_real_view_and_the_real_playfield_answer_what_the_flow_calls() -> void:
	var missing: Array[String] = []
	for pair: Array in [[Game, GameFlow.VIEW_METHODS], [FakeFlowView, GameFlow.VIEW_METHODS],
			[SectorWorld, GameFlow.STAGE_METHODS], [HeadlessStage, GameFlow.STAGE_METHODS]]:
		var names: Array = (pair[0] as Script).get_script_method_list().map(func(method: Dictionary) -> Variant: return method["name"])
		for method: StringName in pair[1]:
			if not names.has(method):
				missing.append("%s.%s" % [(pair[0] as Script).get_global_name(), method])
	for owner_script: Script in [SectorWorld, HeadlessStage]:
		var signals: Array = owner_script.get_script_signal_list().map(func(sig: Dictionary) -> Variant: return sig["name"])
		for signal_name: StringName in [&"problem_pending", &"problem_requested", &"dock_reached", &"finale_reached"]:
			if not signals.has(signal_name):
				missing.append("%s signal %s" % [owner_script.get_global_name(), signal_name])
	assert_array(missing).override_failure_message("missing:\n" + "\n".join(missing)).is_empty()


# --- starting a mission ---------------------------------------------------------------------------

func test_a_mission_starts_with_the_song_and_the_launch_from_the_station() -> void:
	_enter(0)
	await _flow.begin_mission()
	assert_array(_log).is_equal(["music 0", &"launch"])
	assert_int(_stage.trip_ticks[0]).is_equal(28)                  # the rules counted the pack's 28 ticks, nothing else did
	assert_object(_flow.profile).is_same(_player)
	assert_bool(_flow.free_play).is_false()
	assert_int(_stage.sector_index).is_equal(0)
	assert_int(_stage.sim.screen_index).is_equal(0)
	assert_bool(_stage.sim.sub.controlled).is_true()
	assert_int(_store.saves.size()).is_equal(0)


func test_a_player_past_the_midpoint_starts_on_screen_6_without_a_launch() -> void:
	_player.progress = 4 * 2 + 1
	_flow.enter(0, 1)
	await _flow.begin_mission()
	assert_array(_log).is_equal(["music 4"])
	assert_int(_stage.sector_index).is_equal(4)
	assert_int(_stage.sim.screen_index).is_equal(Tuning.resolve().midpoint_screen)
	assert_bool(_stage.sim.sub.active).is_true()


func test_free_play_makes_a_player_that_is_never_saved_and_lets_go_of_it_at_the_end() -> void:
	_run.profile = null
	_flow.enter(3, 2)
	assert_bool(_flow.free_play).is_true()
	assert_int(_flow.profile.sector()).is_equal(3)
	assert_int(_run.edu_level).is_equal(2)
	_store.watched = _flow.profile
	assert_bool(_flow.save_progress()).is_false()
	assert_int(_store.saves.size()).is_equal(0)
	await _flow.finish_game()
	assert_str(_messages.current.body).is_equal("That was the end of the free play.")
	assert_array(_store.hall).is_empty()
	assert_array(_log).is_empty()                                  # no Hall of Fame, no sign-in
	_flow.leave()
	assert_object(_run.profile).is_null()


## The level chosen for free play is the throw-away player's, so every rebuild of the run's level (a sector start, a respawn, a
## restart) reads it again: it is not the zone's default after the first sector start.
func test_the_level_of_free_play_survives_the_start_a_respawn_and_a_restart() -> void:
	_run.profile = null
	var unchosen := PlayerProfile.new_player("Zone default", PlayerProfile.Game.VOYAGER)
	unchosen.progress = 2 * 2
	var chosen := (unchosen.effective_edu_level() + 1) % 4                # (not the level the zone would give)
	_flow.enter(2, chosen)
	await _flow.begin_mission()
	assert_int(_run.edu_level).override_failure_message("after begin_mission").is_equal(chosen)
	_run.update_oxygen(-4)                                         # a spare tank takes over: the respawn
	_run_deferred()
	assert_int(_run.edu_level).override_failure_message("after a respawn").is_equal(chosen)
	_run.oxygen_model.tanks = 0
	_run.update_oxygen(-4)                                         # no spare tank: the sector starts over
	_run_deferred()
	_messages.close_current()
	assert_int(_run.edu_level).override_failure_message("after a restart").is_equal(chosen)


func test_the_first_hint_is_how_to_steer_and_it_is_saved_with_the_player() -> void:
	_player.hints_enabled = true
	_enter(0)
	await _flow.begin_mission()
	assert_str(_messages.current.title).is_equal(Catalog.text(&"new_player_hint_title"))
	assert_int(_store.saves.size()).is_equal(1)                    # the mask of seen hints is part of the record
	_messages.close_current()
	_flow.show_hint(HintSystem.CONTROLS)                           # shown once
	assert_bool(_messages.is_open()).is_false()


func test_hints_come_from_the_numbers_of_the_run_a_low_tank_a_piece_a_blinking_light() -> void:
	_player.hints_enabled = true
	_enter(0)
	await _flow.begin_mission()
	_messages.close_current()
	_run.update_oxygen(-(_run.tuning.max_oxygen - 1))              # one point of air left
	assert_bool(_messages.is_open()).is_true()
	_messages.close_current()
	_run.collect_piece(0)                                          # the data canister
	assert_bool(_messages.is_open()).is_true()
	_messages.close_current()
	_stage.problem_pending.emit(2)
	assert_bool(_messages.is_open()).is_true()


# --- the dock ---------------------------------------------------------------------------------------

func test_pieces_missing_at_the_dock_the_ship_says_so_with_its_light_and_the_song_goes_on_after() -> void:
	_enter(0)
	await _flow.begin_mission()
	_log.clear()
	_run.collect_piece(0)
	var missing := _stage.sector.pieces.size() - 1
	_view.hold(&"pieces_missing")
	_stage.dock_reached.emit()
	assert_array(_log).is_equal(["stop music", "pieces missing %d (ship light true)" % missing])
	assert_bool(_flow.busy).is_true()
	_stage.dock_reached.emit()                                     # (the sub is still in the rectangle: once per visit, but be safe)
	assert_int(_log.size()).is_equal(2)
	_view.release(&"pieces_missing")
	assert_array(_log).is_equal(["stop music", "pieces missing %d (ship light true)" % missing, "music 0"])
	assert_bool(_run.ship_light).is_false()
	assert_bool(_flow.busy).is_false()


func test_all_pieces_open_the_lock_then_the_supply_message_the_balloon_and_the_next_sector() -> void:
	_enter(0)
	await _flow.begin_mission()
	_collect_all()
	_log.clear()
	_run.update_oxygen(-1)                                         # (the supply station fills the tank up)
	_run.fire_ink()
	_view.hold(&"supply_message")
	_stage.dock_reached.emit()
	# the lock (type 0) is the problem on screen; then the sub drives in with the song, silence for the message
	assert_array(_log).is_equal(["stop music", "stop music", "problem 0 (calculator true)", "music 0", &"dock", "stop music", "supply message 0"])
	assert_int(_stage.sector_index).is_equal(0)                    # the next sector waits for the player to leave the message
	assert_int(_player.sector()).is_equal(1)                       # ... but the progress was counted and saved before it
	assert_int(_store.saves.back()["progress"]).is_equal(2)
	assert_int(_store.saves.back()["pieces"]).is_equal(0)          # the pieces went up to the ship
	assert_int(_run.oxygen()).is_equal(Tuning.resolve().max_oxygen - 1) # not refilled yet: `Main` does that after the balloon
	assert_int(_run.ink).is_equal(Tuning.resolve().ink_max - 1)
	assert_bool(_flow.busy).is_true()
	var refilled_at := []
	_run.oxygen_changed.connect(func(_t: int, _o: int) -> void: refilled_at.append(_log.back()), CONNECT_ONE_SHOT)
	_view.release(&"supply_message")
	assert_array(_log).is_equal(["stop music", "stop music", "problem 0 (calculator true)", "music 0", &"dock", "stop music",
			"supply message 0", "music 0", &"balloon", "music 1", &"launch"])
	assert_array(refilled_at).is_equal([&"balloon"])               # `UpdateOxygen(3)` after `LaunchBalloon`, before the next sector
	assert_int(_run.oxygen()).is_equal(Tuning.resolve().max_oxygen)
	assert_int(_run.ink).is_equal(Tuning.resolve().ink_max)
	assert_array(_stage.trip_ticks).is_equal([28, 26, StationSequence.balloon().ticks, 28])    # launch, dock, balloon, the next launch: counted by the rules
	assert_int(_stage.sector_index).is_equal(1)
	assert_int(_run.pieces_mask).is_equal(0)
	assert_bool(_flow.busy).is_false()


func test_the_open_lock_starts_every_creature_over_before_the_sub_docks() -> void:
	# `DoAction` (0x417ffc): after the lock, `FreeSectorResources` / `LoadSectorResources` read the creature records again before
	# `EnterSupplyStation`, so the creatures play the dock and the balloon from their start records.
	_enter(0)
	await _flow.begin_mission()
	_collect_all()
	var sim := _stage.sim
	assert_bool(sim.foes.is_empty()).is_false()
	var before := sim.foes[0]
	before.vm.x += 40
	before.vm.y += 20
	var loads := []
	var reloaded := []                                                        # (creature 0 where the reload put it: the creatures tick on through the dock)
	sim.sector_loaded.connect(func(index: int) -> void:
		loads.append([index, _log.back() if not _log.is_empty() else ""])
		reloaded.append(Vector2i(sim.foes[0].vm.x, sim.foes[0].vm.y)))
	_view.hold(&"supply_message")
	_stage.dock_reached.emit()
	assert_array(loads).is_equal([[0, "problem 0 (calculator true)"]])        # after the lock, before the dock
	assert_object(sim.foes[0]).is_not_same(before)
	var fresh := FoeVM.from_data(sim.sector.foes[0], 0, sim.sector)
	assert_array(reloaded).is_equal([Vector2i(fresh.x, fresh.y)])
	_view.release(&"supply_message")


## The creatures go on through the trips (`EnterSupplyStation` 0x432b96 and `LaunchBalloon` 0x432eae call `update_animals`): from their
## start records, the creatures of the arena have moved by the time the supply message is up.
func test_the_creatures_play_the_dock_from_their_start_records() -> void:
	_enter(DevCreatures.ARENA)
	await _flow.begin_mission()
	_collect_all()
	var sim := _stage.sim
	var places := func() -> Array: return sim.foes.map(func(f: FoeModel) -> Array: return [f.vm.x, f.vm.y, f.vm.frame, f.vm.pc])
	var reloaded := []
	sim.sector_loaded.connect(func(_index: int) -> void: reloaded.append(places.call()))
	_view.hold(&"supply_message")
	_stage.dock_reached.emit()
	assert_int(reloaded.size()).is_equal(1)
	assert_array(places.call()).override_failure_message("no creature moved while the sub docked").is_not_equal(reloaded[0])
	_view.release(&"supply_message")


## The dock is reached in a step of a tick; the stage tells the flow when that tick is over (`SimWorld.after_tick`, as `SectorWorld`
## does), so the rest of that tick runs on the sector it began on, the lock, the reload and the trips come after it, each trip begins
## between two ticks and the next sector begins when the balloon's last tick is over.
func test_a_dock_reached_in_a_tick_lets_that_tick_end_before_the_trip_ticks() -> void:
	_enter(0)
	await _flow.begin_mission()
	_collect_all()
	var sim := _stage.sim
	var order: Array[String] = []
	sim.sequence_started.connect(func(trip: StationSequence) -> void: order.append("trip %d" % trip.kind))
	sim.ticked.connect(func() -> void: order.append("ticked %d" % sim.sector_index))
	sim.load_screen(SimWorld.DOCK_SCREEN)
	sim.start_flight(400, 200, 6)
	var ticks_before := sim.tick_number
	_stage.tick()
	assert_array(order.slice(0, 2)).is_equal(["ticked 0", "trip %d" % StationSequence.Kind.DOCK])     # (the dock trip begins after the tick that reached the dock)
	assert_int(order.count("ticked 0")).is_equal(1 + StationSequence.dock().ticks + StationSequence.balloon().ticks)
	assert_int(sim.tick_number - ticks_before).is_equal(1 + StationSequence.dock().ticks + StationSequence.balloon().ticks + StationSequence.launch().ticks)
	assert_array(_stage.trip_ticks.slice(-3)).is_equal([StationSequence.dock().ticks, StationSequence.balloon().ticks, StationSequence.launch().ticks])
	assert_int(_stage.sector_index).is_equal(1)
	assert_bool(sim.sub.controlled).is_true()


## No step of a tick runs on a sector that was loaded inside it. `SimWorld._advance_sequence` says `sequence_finished` in the sub step of the
## balloon's last tick; the stage's `send_balloon` (as `SectorWorld.send_balloon`) waits for `sequence_over`, which comes when that tick
## is over, so `GameFlow.complete_sector` loads the next sector between two ticks and its creatures take no step before the launch's
## first tick, as in the original (`LaunchBalloon` 0x432eae returns, `DoAction` returns 0, and the next `DoAction` loads the sector and
## runs `ExitSupplyStation` 0x4328b0).
func test_no_step_of_a_tick_runs_on_a_sector_that_was_loaded_inside_it() -> void:
	_enter(0)
	await _flow.begin_mission()
	_collect_all()
	var sim := _stage.sim
	sim.trace_ticks = true
	var tick_sector := [sim.sector_index]
	var changed_at := [-1]
	var ran_after: Array = []
	sim.sector_loaded.connect(func(index: int) -> void:
		if index != tick_sector[0] and not sim.tick_trace.is_empty():     # (a step of a tick has run: the load is inside it)
			changed_at[0] = sim.tick_trace.size())
	sim.ticked.connect(func() -> void:
		if changed_at[0] >= 0:
			ran_after.append(sim.tick_trace.slice(changed_at[0]))
		changed_at[0] = -1
		tick_sector[0] = sim.sector_index
		sim.tick_trace.clear())                                            # (between two ticks the list is empty)
	sim.load_screen(SimWorld.DOCK_SCREEN)
	sim.start_flight(400, 200, 6)
	_stage.tick()
	assert_int(_stage.sector_index).is_equal(1)
	assert_array(ran_after).override_failure_message("steps that ran on the sector loaded inside their tick: %s" % [ran_after]).is_empty()


func test_a_lock_that_cost_the_last_air_does_not_finish_the_sector() -> void:
	_enter(0)
	await _flow.begin_mission()
	_collect_all()
	_log.clear()
	_view.oxygen_code = OxygenModel.OUT_WITH_SPARE_TANKS           # (the lost tank is the respawn's business)
	_stage.dock_reached.emit()
	assert_array(_log).is_equal(["stop music", "stop music", "problem 0 (calculator true)"])
	assert_int(_player.sector()).is_equal(0)
	assert_bool(_flow.busy).is_false()


func test_docking_in_a_finale_ends_the_game_with_no_closing() -> void:
	_enter(DevPack.TOUR_FINALE)
	await _flow.begin_mission()
	_log.clear()
	await _flow.complete_sector()
	var song := DevPack.TOUR_FINALE
	assert_array(_log).is_equal(["music %d" % song, &"dock", "stop music", "supply message %d" % song, "music %d" % song, &"balloon", "hall of fame", "sign in"])
	assert_array(_store.hall).is_equal([_player])


# --- the finale -------------------------------------------------------------------------------------

func test_the_closing_of_a_campaign_gets_the_sub_and_ends_in_the_hall_of_fame() -> void:
	_enter(DevPack.TOUR_FINALE)
	await _flow.begin_mission()
	_log.clear()
	var sub_at: Vector2i = _stage.sim.sub.original_position()
	var cell: int = _stage.sim.sub.cell
	_view.hold(&"closing")
	_stage.finale_reached.emit()
	assert_array(_log).is_equal(["stop music", "closing %s at %s cell %d" % [_flow.campaign.closing_scene, sub_at, cell]])     # (no closing scene of its own: the generic finale)
	assert_bool(_stage.sim.sub.active).is_false()                  # the closing draws its own sub
	assert_bool(_flow.busy).is_true()
	_view.release(&"closing")
	assert_array(_log.slice(2)).is_equal(["hall of fame", "sign in"])
	assert_array(_store.hall).is_equal([_player])
	assert_bool(_flow.busy).is_false()


func test_the_hall_of_fame_entry_is_saved_before_the_hall_is_shown() -> void:
	_enter(DevPack.TOUR_FINALE)
	await _flow.begin_mission()
	_view.hold(&"hall_of_fame")
	var saves_before := _store.saves.size()
	_stage.finale_reached.emit()
	assert_array(_store.hall).is_equal([_player])
	assert_int(_store.saves.size()).is_equal(saves_before + 1)
	_view.release(&"hall_of_fame")
	assert_str(_log.back()).is_equal("sign in")


# --- math problems --------------------------------------------------------------------------------

func test_a_problem_request_shows_the_problem_without_the_song_and_tells_the_world_how_it_went() -> void:
	_enter(0)
	await _flow.begin_mission()
	_log.clear()
	var finished: Array = []
	_stage.sim.problem_finished.connect(func(slot: int, session: ProblemSession) -> void: finished.append([slot, session]))
	_stage.sim.problem_active = true
	_stage.problem_requested.emit(2)
	assert_str(_log[0]).is_equal("stop music")
	assert_str(_log[1]).starts_with("problem ")
	assert_str(_log[2]).is_equal("music 0")                        # the song comes back
	assert_int(finished.size()).is_equal(1)
	assert_int(finished[0][0]).is_equal(2)
	assert_bool(_stage.sim.problem_active).is_false()


func test_the_problem_screen_is_told_whether_the_player_wants_the_calculator() -> void:
	_player.calculator_on = false
	_enter(0)
	await _flow.begin_mission()
	_log.clear()
	_stage.sim.problem_active = true
	_stage.problem_requested.emit(2)
	assert_str(_log[1]).ends_with("(calculator false)")


func test_the_hints_of_a_problem_depend_on_its_type_and_the_calculator() -> void:
	_player.hints_enabled = true
	_enter(0)
	_run.hints.load_mask(0xffff)
	_player.calculator_on = true
	var lock := ProblemFactory.make(0, 0)
	_flow.show_problem_hints(lock)                                 # not for the lock
	assert_bool(_messages.is_open()).is_false()
	var ordinary: ProblemInstance = null
	for type_id in range(2, 28):
		ordinary = ProblemFactory.make(type_id, 0)
		if ordinary != null:
			break
	_flow.show_problem_hints(ordinary)
	assert_bool(_messages.is_open()).is_true()                     # hint 4: the calculator
	assert_str(_messages.current.body).is_equal(HintSystem.text_for(HintSystem.CALCULATOR))
	assert_int(_messages.waiting_count()).is_equal(0)              # level 0: no fractions hint


# --- losing air ---------------------------------------------------------------------------------------

func test_a_lost_tank_respawns_at_the_station_and_keeps_the_pieces() -> void:
	_enter(2)
	await _flow.begin_mission()
	_run.collect_piece(1)
	_log.clear()
	var tanks_before: int = _run.tanks()
	_run.update_oxygen(-4)                                         # the last point of air, a spare tank takes over
	assert_array(_later).has_size(1)                               # (put off: the signal may come from inside a physics step)
	assert_array(_log).is_empty()
	_run_deferred()
	assert_array(_log).is_equal(["music 2", &"launch"])
	assert_int(_run.tanks()).is_equal(tanks_before - 1)
	assert_int(_run.oxygen()).is_equal(Tuning.resolve().max_oxygen)
	assert_int(_run.pieces_mask).is_equal(1 << 1)
	assert_int(_store.saves.size()).is_equal(1)
	assert_bool(_flow.busy).is_false()


func test_a_lost_tank_past_the_midpoint_respawns_on_screen_6() -> void:
	_enter(2)
	await _flow.begin_mission()
	_run.past_midpoint = true
	_log.clear()
	_run.update_oxygen(-4)
	_run_deferred()
	assert_array(_log).is_equal(["music 2"])
	assert_int(_stage.sim.screen_index).is_equal(Tuning.resolve().midpoint_screen)


## A save past the midpoint of a sector whose number of pieces changed since (the designer added one): the collecting of the sector
## starts over as a whole, midpoint included, before the start screen is chosen. The game resumes at the station, and a lost tank
## brings the sub back there, not to screen 6.
func test_a_save_past_the_midpoint_of_a_sector_with_another_piece_count_resumes_and_respawns_at_the_station() -> void:
	_player.progress = Progression.with_midpoint(2 * 2, true)
	_player.pieces_mask = 0b11
	_player.pieces_total = Catalog.sector(2).pieces.size() + 1
	_flow.enter(0, 1)
	assert_bool(_run.past_midpoint).is_true()                      # (what the save says)
	await _flow.begin_mission()
	assert_int(_stage.sim.screen_index).is_equal(0)
	assert_bool(_run.past_midpoint).is_false()
	assert_bool(_run.midpoint_reached).is_false()
	assert_int(_run.pieces_mask).is_equal(0)
	assert_bool(Progression.past_midpoint(_player.progress)).override_failure_message("the record keeps the midpoint").is_false()
	_run.collect_piece(1)
	_run.update_oxygen(-4)                                         # a spare tank takes over
	_run_deferred()
	assert_int(_stage.sim.screen_index).is_equal(0)
	assert_bool(_run.past_midpoint).is_false()
	assert_int(_run.pieces_mask).override_failure_message("the respawn threw the new collecting away").is_equal(1 << 1)


func test_game_over_starts_the_sector_over_after_the_message_and_counts_a_try() -> void:
	_enter(2)
	await _flow.begin_mission()
	_run.collect_piece(1)
	_run.fire_ink()
	_run.oxygen_model.tanks = 0
	_log.clear()
	var tries_before := _player.tries
	_run.update_oxygen(-4)                                         # no spare tank left
	_run_deferred()
	assert_str(_messages.current.body).is_equal("You have run out of oxygen and spare tanks.\nThe sector starts over.")
	assert_array(_log).is_empty()                                  # the sector waits for the player to read the message
	assert_int(_run.pieces_mask).is_equal(0)
	assert_int(_run.ink).is_equal(Tuning.resolve().ink_max)
	assert_int(_player.tries).is_equal(tries_before + 1)
	assert_int(_store.saves.back()["tries"]).is_equal(tries_before + 1)
	assert_bool(_flow.busy).is_true()
	_messages.close_current()
	assert_array(_log).is_equal(["music 2", &"launch"])
	assert_bool(_flow.busy).is_false()


# --- the menu ---------------------------------------------------------------------------------------

func test_the_exit_question_starts_on_no_and_yes_saves_and_quits() -> void:
	_enter(0)
	_flow.ask_to_exit()
	assert_str(_messages.current.title).is_equal(Catalog.text(&"exit_title"))
	assert_int(_messages.current.default_button).is_equal(1)
	_flow.ask_to_exit()                                            # (one question at a time)
	assert_int(_messages.waiting_count()).is_equal(0)
	_messages.close_current(1)                                     # No
	assert_array(_log).is_empty()
	_flow.ask_to_exit()
	_messages.close_current(0)                                     # Yes
	assert_array(_log).is_equal(["quit"])
	assert_int(_store.saves.size()).is_equal(1)


func test_return_to_sign_in_asks_first_and_then_saves_and_goes() -> void:
	_enter(0)
	_flow.ask_to_return_to_sign_in()
	assert_str(_messages.current.body).is_equal(Catalog.text(&"return_to_sign_in_text").replace("\r", "\n"))
	_messages.close_current(1)
	assert_array(_log).is_empty()
	_flow.ask_to_return_to_sign_in()
	_messages.close_current(0)
	assert_array(_log).is_equal(["sign in"])
	assert_int(_store.saves.size()).is_equal(1)


func test_an_options_question_changes_the_setting_and_tells_the_view() -> void:
	_player.sound_on = false
	_enter(0)
	var heard: Array = []
	_flow.option_changed.connect(func(option: StringName, enabled: bool) -> void: heard.append([option, enabled]))
	_flow.ask_option(&"sound")
	assert_int(_messages.current.default_button).is_equal(0)       # the button that would change it is the default one
	assert_int(_messages.current.escape_choice).is_equal(-1)
	_messages.close_current(-1)                                    # Escape: leave it alone
	assert_bool(_player.sound_on).is_false()
	assert_array(heard).is_empty()
	_flow.ask_option(&"sound")
	_messages.close_current(0)                                     # Yes
	assert_bool(_player.sound_on).is_true()
	assert_array(heard).is_equal([[&"sound", true]])
	assert_int(_store.saves.size()).is_equal(1)
	_flow.ask_option(&"music")
	assert_int(_messages.current.default_button).is_equal(1)       # it is on: the default is No
	_messages.close_current(1)
	assert_bool(_player.music_on).is_false()
	assert_array(heard.back()).is_equal([&"music", false])


func test_yes_on_hints_makes_every_hint_new_again() -> void:
	_player.hints_enabled = true
	_enter(0)
	assert_bool(_run.hints.take(HintSystem.CONTROLS)).is_true()
	assert_bool(_run.hints.take(HintSystem.CONTROLS)).is_false()      # shown once
	_flow.ask_option(&"hints")
	_messages.close_current(0)
	assert_bool(_run.hints.enabled).is_true()
	assert_bool(_run.hints.take(HintSystem.CONTROLS)).is_true()


func test_customizing_marks_the_game_only_when_something_changed() -> void:
	_enter(0)
	var level: int = _player.effective_edu_level()
	_flow.customize(level, _player.calculator_on)
	assert_bool(_player.customized).is_false()
	_flow.customize((level + 1) % 4, false)
	assert_bool(_player.customized).is_true()
	assert_bool(_run.customized).is_true()
	assert_int(_run.edu_level).is_equal((level + 1) % 4)
	assert_bool(_player.calculator_on).is_false()
	assert_int(_store.saves.size()).is_equal(2)


func test_a_failed_save_posts_the_write_error_and_the_game_goes_on() -> void:
	_enter(0)
	_store.write_failed.emit("user://roster.json")
	assert_str(_messages.current.title).is_equal("Write Error")             # (the fake store posts it)


func test_the_midpoint_is_saved_with_the_progress() -> void:
	_enter(0)
	_run.midpoint_changed.emit(true)
	assert_int(_store.saves.size()).is_equal(1)


# --- going away ---------------------------------------------------------------------------------------

func test_after_leaving_the_flow_no_longer_hears_the_run() -> void:
	_enter(0)
	_flow.leave()
	_run.update_oxygen(-4)
	_stage.dock_reached.emit()
	_store.write_failed.emit("x")
	assert_array(_later).is_empty()
	assert_array(_log).is_empty()
	assert_bool(_messages.is_open()).is_false()
