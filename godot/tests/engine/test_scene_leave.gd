class_name TestSceneLeave
extends GdUnitTestSuite
## Teaches: tearing a scene down in the right order. Godot runs the CHILDREN's `_exit_tree` before the parent's, so a scene that
## detaches itself from the autoloads in its own `_exit_tree` is still listening while its children let go of what they held: a
## problem screen that gives back a held lost tank, a message box that gives back the clock. These tests leave the game in the
## middle of those holds, both ways a game goes away: through `SceneRouter` (which tells the scene first, `leaving`) and by a plain
## `remove_child` (a test, a tool), and check that nothing of the departing game reaches the next one: no respawn, no try, no save
## with other numbers, no hold of the clock or the losses, no pause of the sound. See docs/engine/ARCHITECTURE.md, "Lifetimes of state".

const GAME_SCENE := "res://src/gameplay/game.tscn"
const ROSTER := "user://test_scene_leave_roster.json"
const HALL := "user://test_scene_leave_hall.json"
## A dev sector with a math trigger on this screen.
const SECTOR := 150
const SCREEN := 5

var _old_roster: String
var _old_hall: String
var _old_players: Array[PlayerProfile]
var _losses: Array[String] = []
var _on_tank_lost := func(code: int) -> void: _losses.append("tank_lost %d" % code)
var _on_game_over := func() -> void: _losses.append("game_over")


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
	_losses.clear()


func after_test() -> void:
	if GameState.tank_lost.is_connected(_on_tank_lost):
		GameState.tank_lost.disconnect(_on_tank_lost)
		GameState.game_over.disconnect(_on_game_over)
	Audio.stop_music()
	SaveStore.roster_path = _old_roster
	SaveStore.hall_path = _old_hall
	SaveStore.players = _old_players
	SaveStore.hall = HallOfFame.new()
	SectorWorld.skip_animations = false
	SceneRouter.dry_run = false
	GameState.profile = null
	GameClock.paused = false
	Audio.reset_pauses()
	GameState.hints.reset()
	GameState.reset()
	for path in [ROSTER, HALL]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _new_player() -> PlayerProfile:
	var player := SaveStore.add_player("Tester", 0)
	player.hints_enabled = false
	GameState.profile = player
	return player


func _make_game() -> Game:
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	get_tree().root.add_child(game)
	await await_idle_frame()
	return game


## A game in the middle of a math problem in which the air ran out: the lost tank (or the game over) is held until the problem closes.
func _game_with_a_held_loss(tanks: int) -> Game:
	var game := await _make_game()
	game.world.load_sector(SECTOR, SCREEN)
	game.world.start_flight()
	game.world.foes_active = false
	GameState.oxygen_model.tanks = tanks
	var sim := game.world.sim
	sim.touch_trigger(sim.triggers_on_screen(SCREEN)[0])
	sim.open_pending_problem()
	await await_idle_frame()
	assert_int(game.problem_layer.get_child_count()).is_greater(0)
	GameState.update_oxygen(-Tuning.resolve().max_oxygen)                    # wrong answers took the last air
	assert_bool(GameState.has_held_loss()).is_true()
	_listen_for_losses()
	return game


func _listen_for_losses() -> void:
	GameState.tank_lost.connect(_on_tank_lost)
	GameState.game_over.connect(_on_game_over)


## What `SceneRouter` does once the fade is black, in its order: the scene is told it leaves, it is taken out of the tree (its children
## exit first), the next scene starts with nothing held.
func _leave_through_the_router(game: Game) -> void:
	SceneRouter.leaving.emit(SceneRouter.SIGN_IN)
	get_tree().root.remove_child(game)
	SceneRouter.start_fresh()
	await await_idle_frame()
	await await_idle_frame()                                            # (a deferred respawn would run by now)


## The scene is only taken out (a test, a tool): no one tells it first.
func _leave_by_removing(game: Game) -> void:
	get_tree().root.remove_child(game)
	await await_idle_frame()
	await await_idle_frame()


func _assert_nothing_held() -> void:
	assert_int(GameClock.holds).override_failure_message("a clock hold outlived the scene").is_equal(0)
	assert_int(GameState._loss_holds).override_failure_message("a hold on the losses outlived the scene").is_equal(0)
	assert_bool(GameState.has_held_loss()).is_false()
	assert_int(Audio._sound_pause_level).override_failure_message("a sound pause outlived the scene").is_equal(0)
	assert_int(Audio._music_pause_count).override_failure_message("a music pause outlived the scene").is_equal(0)


# --- a lost tank held by a problem --------------------------------------------------------------

## Return to Sign In during a problem whose wrong answers took the last air: the save has the numbers of that moment (the tank is
## not taken, the empty tank is saved as the 1 every saved game starts with), and the departing game neither respawns nor saves again.
func test_return_to_sign_in_during_a_problem_drops_the_held_tank() -> void:
	var player := _new_player()
	var game := await _game_with_a_held_loss(2)
	var tries := player.tries
	game.leave_to_sign_in()                                             # saves, then asks the router (a dry run here)
	assert_int(player.tanks).is_equal(2)
	assert_int(player.oxygen).is_equal(1)
	await _leave_through_the_router(game)
	game.free()
	assert_array(_losses).override_failure_message("the leaving game announced a loss: %s" % [_losses]).is_empty()
	assert_int(GameState.tanks()).is_equal(2)
	assert_int(player.tanks).override_failure_message("the leaving game respawned and saved").is_equal(2)
	assert_int(player.oxygen).is_equal(1)
	assert_int(player.tries).is_equal(tries)
	assert_str(String(Audio.song)).override_failure_message("the leaving game started a song").is_equal(String(AudioService.NO_MUSIC))
	_assert_nothing_held()


## The same with no spare tank: no game over, no try counted, no message (and so no clock hold and no sound pause) left behind.
func test_leaving_during_a_problem_with_a_held_game_over_counts_no_try() -> void:
	var player := _new_player()
	var game := await _game_with_a_held_loss(0)
	var tries := player.tries
	game.leave_to_sign_in()
	await _leave_through_the_router(game)
	game.free()
	assert_array(_losses).is_empty()
	assert_int(player.tries).override_failure_message("the leaving game restarted the sector").is_equal(tries)
	_assert_nothing_held()


## A game that is only taken out of the tree (nobody tells it first) is as safe: the problem screen drops its loss itself.
func test_a_game_removed_during_a_problem_announces_no_loss_and_holds_nothing() -> void:
	var player := _new_player()
	var game := await _game_with_a_held_loss(0)
	var tries := player.tries
	await _leave_by_removing(game)
	game.free()
	assert_array(_losses).is_empty()
	assert_int(player.tries).is_equal(tries)
	_assert_nothing_held()


## The window is closed (the red cross, Alt+F4) during that problem: the game saves the numbers of the moment, then the program tears
## the tree down; the lost tank is not taken and saved afterwards.
func test_closing_the_window_during_a_problem_saves_the_numbers_of_that_moment() -> void:
	var player := _new_player()
	var game := await _game_with_a_held_loss(3)
	var tries := player.tries
	game.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_int(player.tanks).is_equal(3)
	assert_int(player.oxygen).is_equal(1)
	await _leave_by_removing(game)                                    # (what quitting does to the tree)
	game.free()
	assert_array(_losses).is_empty()
	assert_int(player.tanks).is_equal(3)
	assert_int(player.tries).is_equal(tries)
	_assert_nothing_held()


# --- a lost tank held by the dissolve -----------------------------------------------------------

## The scene goes away while the sub dissolves after a creature took its last air: the clock hold of `SectorWorld` and the sim's hold
## on the losses go with it, and the lost tank is never announced.
func test_leaving_during_the_dissolve_releases_its_holds_and_announces_nothing() -> void:
	SectorWorld.skip_animations = false
	_new_player()
	var game := await _make_game()
	game.world.load_sector(DevCreatures.ARENA, 0)
	game.world.start_flight(200, 150, 6)
	GameState.oxygen_model.oxygen = 1
	_listen_for_losses()
	game.world.sub_touches(game.world.sim.foes[DevCreatures.POST])    # a hostile creature, damage 1: the last air
	assert_bool(game.world.sim.is_dissolving()).is_true()
	assert_int(GameClock.holds).is_equal(1)
	assert_int(GameState._loss_holds).is_equal(1)
	await _leave_by_removing(game)
	game.free()
	assert_array(_losses).is_empty()
	_assert_nothing_held()


## A sector loaded while the sub dissolves (a debug key) ends that dissolve: the trip and the dissolve belong to the sector that was
## loaded, and the lost tank they held is dropped with them.
func test_a_sector_load_ends_a_running_dissolve_and_drops_its_loss() -> void:
	var run := auto_free(preload("res://src/autoload/game_state.gd").new()) as Node
	var sim := SimWorld.new(run)
	sim.damage_settled_by_owner = true
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.start_flight(200, 150, 6)
	run.oxygen_model.oxygen = 1
	var lost := [0]
	run.tank_lost.connect(func(_code: int) -> void: lost[0] += 1)
	sim.sub_touches(sim.foes[DevCreatures.POST])
	sim.begin_dissolve()                                               # (what the owner does on `sub_damaged`)
	assert_bool(sim.is_dissolving()).is_true()
	sim.load_sector(DevCreatures.ARENA, 0)
	assert_bool(sim.is_dissolving()).is_false()
	assert_int(run._loss_holds).is_equal(0)
	assert_int(lost[0]).is_equal(0)
	assert_object(sim.sequence).is_null()


# --- what a scene change starts over ---------------------------------------------------------------

## A new scene starts with no pause of the sound and no hold of the clock left by the scene before, however deep its dialogs nested.
func test_a_new_scene_starts_with_no_pause_and_no_hold_of_the_scene_before() -> void:
	Audio.pause_sound()
	Audio.pause_sound()
	Audio.pause_music()
	GameClock.hold()
	GameClock.hold()
	SceneRouter.start_fresh()
	assert_int(Audio._sound_pause_level).is_equal(0)
	assert_int(Audio._music_pause_count).is_equal(0)
	assert_int(GameClock.holds).is_equal(0)
	assert_bool(GameClock.paused).is_false()


## The pause of a window without the focus is the window's, not a scene's: it stays across the change and goes when the focus comes back.
func test_a_window_without_the_focus_keeps_its_pause_across_a_scene_change() -> void:
	Audio.pause_sound_on_deactivate()
	Audio.pause_sound()                                                 # (a dialog of the scene that leaves)
	SceneRouter.start_fresh()
	assert_int(Audio._sound_pause_level).is_equal(1)
	assert_int(Audio._music_pause_count).is_equal(1)
	Audio.resume_sound_on_activate()
	assert_int(Audio._sound_pause_level).is_equal(0)
	assert_int(Audio._music_pause_count).is_equal(0)
