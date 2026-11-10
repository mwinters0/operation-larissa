class_name TestGameFlowLegacy
extends GdUnitTestSuite
## Teaches: an integration test of the whole game flow with a real player: the three result codes of the
## original (0 sector complete, 1 lost a tank, 2 game over), the midpoint, the deferral of losses while a problem
## is open, saving, and the end of the game. Door and driving animations are switched off
## (`SectorWorld.skip_animations`), the roster goes to a scratch file and the router only records where it
## would go.

## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


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


func test_the_last_ordinary_sector_leads_into_the_finale_sector() -> void:
	_player.progress = 28                                              # sector 14, the last ordinary one
	var game := await _start()
	_collect_all(game)
	game.complete_sector()
	await await_idle_frame()
	(game.problem_layer.get_child(0) as SurfaceShipScreen).finish()
	await await_idle_frame()
	assert_int(_player.progress).is_equal(Progression.VOYAGER_FINALE)
	assert_int(game.world.sector_index).is_equal(30)                   # the finale is a sector you fly in
	assert_int(game.world.screen_index).is_equal(0)
	assert_bool(game.world.sim.sub.active).is_true()
	assert_int(SaveStore.hall.entries.size()).is_equal(0)              # not in the Hall of Fame yet


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


func test_the_voyager_finale_plays_the_closing_then_the_hall_of_fame_and_sign_in() -> void:
	_player.progress = Progression.VOYAGER_FINALE
	_player.tries = 3
	var game := await _start()
	assert_int(game.world.sector_index).is_equal(30)
	game.world.foe_context.semaphore |= 1 << SimWorld.FINALE_SEMAPHORE_BIT   # the creature was touched on screen 4 ...
	game.world.load_screen(Catalog.sector(30).finale_screen)                    # ... and the sub swims up to screen 2
	game.world.tick()
	assert_object(game.closing).is_instanceof(VoyagerClosing)
	assert_bool(game.world.sim.sub.active).is_false()
	var closing := game.closing as VoyagerClosing
	closing.advance()                                                  # Enter: skip the flight, show the three pages
	for page in VoyagerClosing.PAGES:
		await await_idle_frame()
		assert_bool(closing.messages.is_open()).is_true()
		closing.messages.close_current()
	await _finish_closing_and_check_hall(game, 3)


func test_the_expert_finale_plays_the_closing_then_the_hall_of_fame() -> void:
	SaveStore.players = []
	_player = SaveStore.add_player("Tester", 1)
	_player.progress = Progression.EXPERT_FINALE
	_player.tries = 2
	GameState.profile = _player
	var game := await _start()
	assert_int(game.world.sector_index).is_equal(31)
	game.world.foe_context.semaphore |= 1 << SimWorld.FINALE_SEMAPHORE_BIT
	game.world.load_screen(Catalog.sector(31).finale_screen)
	game.world.tick()
	assert_object(game.closing).is_instanceof(ExpertClosing)
	game.closing.advance()                                             # Enter is thrown away: the original reads every key until the last stage
	assert_object(game.closing).is_not_null()
	game.closing.finish()                                              # (the real thing ends with a key after about 50 s of film)
	await _finish_closing_and_check_hall(game, 2)


