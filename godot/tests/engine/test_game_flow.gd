class_name TestGameFlow
extends GdUnitTestSuite
## Teaches: an integration test of the whole game flow with a real player: the three result codes of the
## original (0 sector complete, 1 lost a tank, 2 game over), the midpoint, the deferral of losses while a problem
## is open, saving, and the end of the game. Door and driving animations are switched off
## (`SectorWorld.skip_animations`), the roster goes to a scratch file and the router only records where it
## would go.

const GAME_SCENE := "res://src/gameplay/game.tscn"
const ROSTER := "user://test_flow_roster.json"
const HALL := "user://test_flow_hall.json"

var _old_roster: String
var _old_hall: String
var _old_players: Array[PlayerProfile]
var _player: PlayerProfile


func before_test() -> void:
	_old_roster = SaveStore.roster_path
	_old_hall = SaveStore.hall_path
	_old_players = SaveStore.players.duplicate()
	SaveStore.roster_path = ROSTER
	SaveStore.hall_path = HALL
	SaveStore.players = []
	SaveStore.hall = HallOfFame.new()
	SectorWorld.skip_animations = true
	SceneRouter.dry_run = true
	SceneRouter.last_path = ""
	_player = SaveStore.add_player("Tester", 0)
	_player.hints_enabled = false                                  # no hint dialogs in the way
	GameState.profile = _player


func after_test() -> void:
	var space_up := InputEventKey.new()                              # (a failed test must not leave Space held for the next one)
	space_up.keycode = KEY_SPACE
	space_up.physical_keycode = KEY_SPACE
	Input.parse_input_event(space_up)
	SaveStore.roster_path = _old_roster
	SaveStore.hall_path = _old_hall
	SaveStore.players = _old_players
	SaveStore.hall = HallOfFame.new()
	SectorWorld.skip_animations = false
	SceneRouter.dry_run = false
	GameState.profile = null
	GameClock.paused = false
	GameState.hints.reset()
	GameState.reset()
	for path in [ROSTER, HALL]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _start() -> Game:
	var game := scene_runner(GAME_SCENE).scene() as Game
	await await_idle_frame()
	return game


## Collects every piece of the current sector (and the midpoint bookkeeping that goes with it).
func _collect_all(game: Game) -> void:
	for i in game.world.sector.pieces.size():
		GameState.collect_piece(i)
	GameState.update_midpoint(game.world.sector)


func test_a_new_player_starts_in_sector_zero_on_screen_zero() -> void:
	var game := await _start()
	assert_object(game.profile).is_same(_player)
	assert_bool(game.free_play).is_false()
	assert_int(game.world.sector_index).is_equal(0)
	assert_int(game.world.screen_index).is_equal(0)
	assert_bool(game.world.sim.sub.active).is_true()
	assert_int(GameState.tanks()).is_equal(GameState.tuning.refill_tanks)
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen)
	assert_int(GameState.ink).is_equal(GameState.tuning.ink_max)


func test_a_saved_game_resumes_where_it_was() -> void:
	_player.progress = Progression.with_midpoint(4, true)           # sector 2, past the midpoint
	_player.tanks = 3
	_player.oxygen = 2
	_player.ink = 5
	_player.pieces_mask = 0b11
	var game := await _start()
	assert_int(game.world.sector_index).is_equal(2)
	assert_int(game.world.screen_index).is_equal(Tuning.resolve().midpoint_screen)   # the respawn screen
	assert_int(GameState.tanks()).is_equal(3)
	assert_int(GameState.ink).is_equal(5)
	assert_int(GameState.pieces_mask).is_equal(0b11)
	assert_bool(GameState.past_midpoint).is_true()


func test_entering_the_midpoint_screen_alone_does_not_set_the_midpoint() -> void:
	var game := await _start()
	game.world.load_screen(Tuning.resolve().midpoint_screen)
	GameState.screen_entered(Tuning.resolve().midpoint_screen, game.world.sector)
	assert_bool(GameState.midpoint_reached).is_true()
	assert_bool(GameState.past_midpoint).is_false()                  # the pieces before the midpoint screen are still out there


func test_the_midpoint_screen_plus_the_early_pieces_set_the_midpoint_and_it_is_saved() -> void:
	var game := await _start()
	var sector := game.world.sector
	for i in sector.pieces.size():
		if sector.pieces[i].screen < Tuning.resolve().midpoint_screen:
			GameState.collect_piece(i)
	GameState.screen_entered(Tuning.resolve().midpoint_screen, sector)
	assert_bool(GameState.past_midpoint).is_true()
	var fresh := PlayerProfile.from_dict(JSON.parse_string(FileAccess.get_file_as_string(ROSTER))["players"][0])
	assert_bool(fresh.past_midpoint()).is_true()                     # `midpoint_changed` saved it at once


func test_result_1_a_lost_tank_respawns_at_the_station_and_keeps_the_pieces() -> void:
	var game := await _start()
	GameState.collect_piece(1)
	game.world.load_screen(3)
	GameState.update_oxygen(-4)
	await await_idle_frame()
	assert_int(GameState.tanks()).is_equal(GameState.tuning.refill_tanks - 1)
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen)
	assert_int(game.world.screen_index).is_equal(0)
	assert_bool(GameState.has_piece(1)).is_true()
	assert_int(game.world.sim.sub.original_position().x).is_equal(SimWorld.launched_x())


func test_result_1_past_the_midpoint_the_respawn_is_on_the_midpoint_screen() -> void:
	var game := await _start()
	var sector := game.world.sector
	for i in sector.pieces.size():
		if sector.pieces[i].screen < Tuning.resolve().midpoint_screen:
			GameState.collect_piece(i)
	GameState.screen_entered(Tuning.resolve().midpoint_screen, sector)
	game.world.load_screen(9)
	GameState.update_oxygen(-4)
	await await_idle_frame()
	assert_int(game.world.screen_index).is_equal(Tuning.resolve().midpoint_screen)
	assert_vector(Vector2(game.world.sim.sub.original_position())).is_equal(Vector2(sector.start_pos))
	assert_int(GameState.tanks()).is_equal(GameState.tuning.refill_tanks - 1)


func test_result_2_game_over_restarts_the_sector_and_counts_a_try() -> void:
	var game := await _start()
	GameState.collect_piece(1)
	GameState.fire_ink()
	GameState.oxygen_model.tanks = 0
	game.world.load_screen(5)
	GameState.update_oxygen(-4)
	await await_idle_frame()
	assert_bool(game.messages.is_open()).is_true()                    # "You have run out of oxygen and spare tanks."
	game.messages.close_current()
	await await_idle_frame()
	assert_int(GameState.tanks()).is_equal(GameState.tuning.refill_tanks)
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen)
	assert_int(GameState.ink).is_equal(GameState.tuning.ink_max)
	assert_int(GameState.pieces_mask).is_equal(0)
	assert_int(_player.tries).is_equal(2)
	assert_int(game.world.screen_index).is_equal(0)
	assert_bool(GameState.past_midpoint).is_false()


func test_running_out_of_air_at_a_wrong_answer_costs_the_tank_only_when_the_problem_closes() -> void:
	var game := await _start()
	var lost := []
	GameState.tank_lost.connect(func(code: int) -> void: lost.append(code))
	GameState.oxygen_model.oxygen = 1
	game.world.problem_requested.emit(2)                              # a math problem opens
	var screen := game.problem_layer.get_child(0) as ProblemScreen
	if screen.step() == ProblemScreen.Step.INTRO:                     # the diagram builds up first (5.5)
		screen.diagram.skip_animation()
		await await_idle_frame()
	screen.submit_answer(NumberValue.decimal(-12345))                 # wrong: the last oxygen goes
	assert_int(GameState.oxygen()).is_equal(0)                        # the console shows it ...
	assert_array(lost).is_empty()                                     # ... but the sub still has its tank
	assert_int(game.world.sector_index).is_equal(0)
	assert_str(screen.text_label.text).is_equal(Catalog.text(&"error_title"))             # (no hint, no second try)
	screen.press_continue()                                           # "Error!" is over: with no air left the problem ends here
	assert_array(lost).has_size(1)                                    # now it happens, once
	await await_idle_frame()
	assert_int(GameState.tanks()).is_equal(GameState.tuning.refill_tanks - 1)


func test_the_dock_with_pieces_missing_shows_the_surface_ship_screen() -> void:
	var game := await _start()
	var total := game.world.sector.pieces.size()
	GameState.collect_piece(0)
	game.world.dock_reached.emit()
	assert_bool(game.messages.is_open()).is_false()                    # a screen of its own, not a message box
	assert_int(game.problem_layer.get_child_count()).is_equal(1)       # (and no lock yet)
	var screen := game.problem_layer.get_child(0) as SurfaceShipScreen
	assert_object(screen).is_not_null()
	assert_str(screen.message_label.text).is_equal(SurfaceShipScreen.pieces_missing_text(total - 1))
	assert_str(screen.message_label.text).contains("%d piece" % (total - 1)).not_contains("\u0008")      # the number and the plural are filled in
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	screen._unhandled_input(key)                                        # Enter: back to the sector
	await await_idle_frame()
	assert_int(game.problem_layer.get_child_count()).is_equal(0)


func test_the_dock_is_found_by_position_and_only_once_per_visit() -> void:
	var game := await _start()
	var docks := []
	game.world.dock_reached.connect(func() -> void: docks.append(true))
	game.world.load_screen(SimWorld.DOCK_SCREEN)
	game.world.original.sub.place_original(300, 200, 6)                         # too far left
	game.world.tick()
	assert_array(docks).is_empty()
	game.world.original.sub.place_original(400, 200, 6)
	game.world.tick()
	game.world.tick()
	assert_array(docks).has_size(1)
	game.world.original.sub.place_original(400, 300, 6)                         # leaves the rectangle ...
	game.world.tick()
	game.world.original.sub.place_original(400, 200, 6)                         # ... and comes back
	game.world.tick()
	assert_array(docks).has_size(2)
	game.world.original.sub.place_original(400, 200, 2)                         # facing left: not docking
	game.world.tick()
	game.world.tick()
	assert_array(docks).has_size(2)


func test_result_0_the_lock_opens_the_next_sector() -> void:
	var game := await _start()
	_collect_all(game)
	GameState.update_oxygen(-(GameState.tuning.max_oxygen - 1))
	GameState.fire_ink()
	game.complete_sector()                                             # not awaited: it waits for the surface ship screen
	await await_idle_frame()
	assert_int(_player.progress).is_equal(2)                           # sector 1
	assert_int(GameState.pieces_mask).is_equal(0)                      # "transported to the surface ship"
	assert_int(GameState.oxygen()).is_equal(1)                         # not refilled yet: `Main` (0x427bb4) refills after the balloon
	assert_int(GameState.ink).is_equal(GameState.tuning.ink_max - 1)
	var map := game.problem_layer.get_child(0) as SurfaceShipScreen
	assert_object(map).is_not_null()
	assert_str(map.message_label.text).is_equal(_player.campaign().supply_message_text(0).strip_edges())      # the mission control text of sector 0
	map.finish()
	await await_idle_frame()
	assert_int(game.world.sector_index).is_equal(1)
	assert_int(game.world.screen_index).is_equal(0)
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen)
	assert_int(GameState.ink).is_equal(GameState.tuning.ink_max)
	assert_bool(FileAccess.file_exists(ROSTER)).is_true()
	assert_int(PlayerProfile.from_dict(JSON.parse_string(FileAccess.get_file_as_string(ROSTER))["players"][0]).progress).is_equal(2)


func _finish_closing_and_check_hall(game: Game, expected_tries: int) -> void:
	await await_idle_frame()
	assert_int(SaveStore.hall.entries.size()).is_equal(1)
	assert_str(SaveStore.hall.entries[0].name).is_equal("Tester")
	assert_int(SaveStore.hall.entries[0].tries).is_equal(expected_tries)
	# G27: `add_player_to_hall` (0x4315ac) -> `RemoveRosterSlot` (0x42f6eb) -> `SaveRosterData`: the winner leaves the roster, in memory and on disk
	assert_array(SaveStore.players).is_empty()
	assert_int(JSON.parse_string(FileAccess.get_file_as_string(ROSTER))["players"].size()).is_equal(0)
	var view := game.dialog_layer.get_child(game.dialog_layer.get_child_count() - 1) as HallOfFameView
	assert_object(view).is_not_null()
	view.close()
	await await_idle_frame()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.SIGN_IN)


func test_docking_in_the_finale_of_the_tour_ends_the_game_with_the_hall_of_fame() -> void:
	_player.progress = DevPack.TOUR_FINALE * 2
	_player.tries = 3
	var game := await _start()
	assert_int(game.world.sector_index).is_equal(DevPack.TOUR_FINALE)
	_collect_all(game)
	game.complete_sector()                                             # not awaited: it waits for the surface ship screen
	await await_idle_frame()
	var screen := game.problem_layer.get_child(0) as SurfaceShipScreen
	if screen != null:
		screen.finish()
	await _finish_closing_and_check_hall(game, 3)


func test_a_dead_sub_in_the_finale_starts_the_finale_again() -> void:
	_player.progress = DevPack.TOUR_FINALE * 2
	var game := await _start()
	GameState.update_oxygen(-4)                                        # last point of air, a spare tank takes over
	await await_idle_frame()
	await await_idle_frame()
	assert_int(game.world.sector_index).is_equal(DevPack.TOUR_FINALE)
	assert_int(game.world.screen_index).is_equal(0)


func test_leaving_saves_the_game() -> void:
	var game := await _start()
	GameState.collect_piece(1)
	GameState.fire_ink()
	game.leave_to_sign_in()
	var saved := PlayerProfile.from_dict(JSON.parse_string(FileAccess.get_file_as_string(ROSTER))["players"][0])
	assert_int(saved.pieces_mask).is_equal(0b10)
	assert_int(saved.ink).is_equal(GameState.tuning.ink_max - 1)
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.SIGN_IN)


func test_the_options_menu_is_saved_per_player() -> void:
	var game := await _start()
	game.menu_bar.options_menu.id_pressed.emit(2)                      # Music: the question "Do you want the Music on?"
	game.messages.close_current(1)                                     # No
	assert_bool(_player.music_on).is_false()
	game.menu_bar.options_menu.id_pressed.emit(0)                      # New Player Hints (it was off: now on)
	game.messages.close_current(0)                                     # Yes
	assert_bool(GameState.hints.enabled).is_true()


func test_customization_changes_the_level_and_marks_the_game_customized() -> void:
	var game := await _start()
	assert_int(GameState.edu_level).is_equal(0)
	game.show_customization()
	var dialog := game.dialog_layer.get_child(game.dialog_layer.get_child_count() - 1) as CustomizationDialog
	assert_int(dialog.chosen_level()).is_equal(0)
	dialog.accepted.emit(2, false)
	await await_idle_frame()
	assert_bool(_player.customized).is_true()
	assert_int(GameState.edu_level).is_equal(2)
	assert_bool(_player.calculator_on).is_false()
	assert_bool(GameState.customized).is_true()


func test_free_play_without_a_player_saves_nothing() -> void:
	GameState.profile = null
	var game := await _start()
	assert_bool(game.free_play).is_true()
	assert_bool(game.save_progress()).is_false()


# --- the fire key (Space) while anything covers the playfield ---------------------------------------------
#
# Original: the fire key is read only at the top of `DoAction`'s (0x417ffc) tick loop (`PeekInput` 0x4180d6, `WaitForInput`
# 0x4180df -> `StartStunGun` 0x432330 at 0x41894f). A problem (and its lock), the surface ship screen, a message or hint, a
# dialog are all calls made from inside that loop, which does not go on until they return, so a Space typed meanwhile fires
# nothing and plays neither 0x18 (`ink_fired`) nor 0x1e (`no_pellets`). In the port every cover holds the `GameClock`, and
# `Sub` does not fire while it is held.

var _sounds: Array[StringName]


## Parses a Space press and release the way the window does, so it travels the viewport's whole input path.
func _press_space() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	await await_idle_frame()
	var release := key.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	await await_idle_frame()


## Starts a game and records the world's sounds.
func _start_listening() -> Game:
	var game := await _start()
	_sounds = []
	game.world.sfx_requested.connect(func(sfx_id: StringName) -> void: _sounds.append(sfx_id))
	return game


## A Space now: no pellet, no ink spent, not even the empty-supply sound.
func _assert_space_is_dead(game: Game) -> void:
	var ink_before := GameState.ink
	await _press_space()
	game.world.tick(game.world.take_input())                           # (a press that was counted would be a shot in this tick)
	assert_int(GameState.ink).is_equal(ink_before)
	assert_int(game.world.sim.pellets.size()).is_equal(0)
	assert_bool(_sounds.has(SimWorld.SFX_INK_FIRED) or _sounds.has(SimWorld.SFX_NO_PELLETS)).is_false()


## The control: with the cover gone, the same Space fires (so the zeros above are not a dead key).
func _assert_space_fires(game: Game) -> void:
	assert_int(GameClock.holds).is_equal(0)
	await _press_space()
	game.world.tick(game.world.take_input())                           # the shot happens in the tick that takes the press
	assert_int(game.world.sim.pellets.size()).is_equal(1)
	assert_bool(_sounds.has(SimWorld.SFX_INK_FIRED)).is_true()


## Opens the supply station's lock on a game whose sub is flying (it still is, behind the lock screen: `dock()` runs after).
func _open_lock(game: Game) -> CombinationLock:
	_collect_all(game)
	game.flow.on_dock_reached()                                            # not awaited: it waits for the lock
	await await_idle_frame()
	var screen := game.problem_layer.get_child(0) as ProblemScreen
	assert_object(screen).is_not_null()
	assert_object(screen.lock).is_not_null()
	return screen.lock


func test_space_in_every_phase_of_the_lock_fires_nothing() -> void:
	var game := await _start_listening()
	var lock := await _open_lock(game)
	lock.set_process(false)                                            # only the test moves time
	await _assert_space_is_dead(game)                                  # the intro, "Press Enter to begin."
	lock.press_key()
	lock.advance_ticks(1)
	assert_int(lock.phase).is_equal(CombinationLock.Phase.OPERANDS)
	await _assert_space_is_dead(game)                                  # the operand wheel turns
	while lock.phase != CombinationLock.Phase.REVEAL:
		lock.advance_ticks(1)
	await _assert_space_is_dead(game)                                  # the operator is held back
	while lock.phase != CombinationLock.Phase.ANSWER:
		lock.advance_ticks(1)
	lock.set_process_unhandled_input(false)                            # control: no lock to take the Space, no hold on the clock ...
	GameClock.paused = false                                           # ... and the same key fires
	await _assert_space_fires(game)


## The messages after a number: the Space is thrown away, and no pellet waits for after the lock.
func test_space_during_the_lock_notices_leaves_no_pellet_for_after_the_lock() -> void:
	var game := await _start_listening()
	var lock := await _open_lock(game)
	lock.set_process(false)
	lock.press_key()                                                   # Enter: begin
	for number in 2:
		while lock.phase != CombinationLock.Phase.ANSWER:
			lock.advance_ticks(1)
		var target := LockWheel.target_position(lock.answer_wheel.target_slot)
		while not (lock.answer_wheel.is_waiting_for_key() and lock.answer_wheel.position == target):
			lock.advance_ticks(1)
		lock.press_key()                                               # stop on the right label
		assert_int(lock.phase).is_equal(CombinationLock.Phase.NOTICE)
		await _assert_space_is_dead(game)
		assert_int(lock.phase).is_equal(CombinationLock.Phase.NOTICE)  # (Space does not end a message)
		lock.press_key()
	assert_int(lock.phase).is_equal(CombinationLock.Phase.DONE)
	assert_int(game.world.sim.pellets.size()).is_equal(0)


## With no ink left the stray Space used to be the "no pellets" sound (0x1e, `StartStunGun`'s empty-supply branch).
func test_space_in_the_lock_plays_no_no_pellets_sound_with_an_empty_supply() -> void:
	var game := await _start_listening()
	while GameState.fire_ink():
		pass
	var lock := await _open_lock(game)
	lock.set_process(false)
	await _assert_space_is_dead(game)
	lock.press_key()
	lock.advance_ticks(5)
	await _assert_space_is_dead(game)
	GameClock.paused = false
	await _press_space()
	game.world.tick(game.world.take_input())
	assert_bool(_sounds.has(SimWorld.SFX_NO_PELLETS)).is_true()     # control: with the clock running the key is live


func test_space_during_a_normal_problem_fires_nothing_until_it_is_over() -> void:
	var game := await _start_listening()
	var problem: ProblemInstance = null
	for type_id in range(2, 28):                                       # the first ordinary problem (typed answer or calculator)
		problem = ProblemFactory.make(type_id, GameState.edu_level)
		if problem != null:
			break
	assert_object(problem).is_not_null()
	game.flow.run_problem.call(problem)                                    # not awaited: it waits for the screen to finish
	await await_idle_frame()
	var screen := game.problem_layer.get_child(0) as ProblemScreen
	assert_object(screen).is_not_null()
	await _assert_space_is_dead(game)                                  # a typed number may be in the answer box, but never a shot
	screen.close()
	await await_idle_frame()
	await await_idle_frame()
	await _assert_space_fires(game)


func test_space_during_the_ballast_panel_fires_nothing_until_it_is_over() -> void:
	var game := await _start_listening()
	var problem: ProblemInstance = null
	for level in 4:
		problem = ProblemFactory.make(28, level)
		if problem != null:
			break
	assert_object(problem).is_not_null()
	game.flow.run_problem.call(problem)
	await await_idle_frame()
	var screen := game.problem_layer.get_child(0) as ProblemScreen
	assert_object(screen.ballast).is_not_null()
	await _assert_space_is_dead(game)
	screen.close()
	await await_idle_frame()
	await await_idle_frame()
	await _assert_space_fires(game)


func test_space_on_the_surface_ship_screen_fires_nothing_until_it_is_closed() -> void:
	var game := await _start_listening()
	GameState.collect_piece(0)
	game.world.dock_reached.emit()                                     # pieces missing: the surface ship screen (it ignores Space)
	await await_idle_frame()
	var screen := game.problem_layer.get_child(0) as SurfaceShipScreen
	assert_object(screen).is_not_null()
	await _assert_space_is_dead(game)
	assert_object(game.problem_layer.get_child(0)).is_same(screen)     # (Space did not close it)
	screen.finish()
	await await_idle_frame()
	await await_idle_frame()
	await _assert_space_fires(game)


func test_space_during_a_message_or_hint_box_fires_nothing_until_it_is_closed() -> void:
	var game := await _start_listening()
	game.messages.post("Operation Neptune", "A hint box (or any other message).")
	await await_idle_frame()
	assert_bool(game.messages.is_open()).is_true()
	await _assert_space_is_dead(game)
	if game.messages.is_open():                                        # (the box may have taken the Space for its default button)
		game.messages.close_current()
	await await_idle_frame()
	await _assert_space_fires(game)
