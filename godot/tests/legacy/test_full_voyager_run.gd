class_name TestFullVoyagerRun
extends GdUnitTestSuite
## Teaches: an end-to-end test. A scripted "player" completes all 15 sectors of the Voyager game (collects every
## piece and opens the lock the way the flow does after a solved lock), swims into the finale sector, touches the
## treasure, and watches the closing sequence; the run must end in the Hall of Fame and back at sign-in.
## Animations are switched off (`SectorWorld.skip_animations`), the router only records where it would go,
## and the roster goes to scratch files.

const ROSTER := "user://test_full_roster.json"
const HALL := "user://test_full_hall.json"

var _old_roster: String
var _old_hall: String
var _old_players: Array[PlayerProfile]


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


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


func after_test() -> void:
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


func _play_whole_game(game_kind: int) -> void:
	var player := SaveStore.add_player("Runner", game_kind)
	player.hints_enabled = false
	GameState.profile = player
	var game := scene_runner("res://src/gameplay/game.tscn").scene() as Game
	await await_idle_frame()
	var first := player.sector()
	assert_int(game.world.sector_index).is_equal(first)
	for step in player.campaign().sector_count():
		var sector := player.sector()
		assert_int(game.world.sector_index).is_equal(sector)
		assert_int(sector).is_equal(first + step)
		for i in game.world.sector.pieces.size():
			GameState.collect_piece(i)
		game.complete_sector()                                       # (the lock is solved: not awaited, it waits for the map)
		await await_idle_frame()
		(game.problem_layer.get_child(0) as SurfaceShipScreen).finish()
		await await_idle_frame()
	var finale := player.campaign().finales[0]
	assert_int(player.sector()).is_equal(finale)
	assert_int(game.world.sector_index).is_equal(finale)
	assert_int(SaveStore.hall.entries.size()).is_equal(0)
	# the treasure is touched on its own screen, then the sub arrives on the closing screen
	game.world.load_screen(game.world.original.foes[0].vm.screen)
	game.world.sub_touches(game.world.sim.foes[0])
	for tick in 4:
		game.world.tick()
	game.world.load_screen(SimWorld.finale_screen(finale))
	game.world.tick()
	assert_object(game.closing).is_not_null()
	game.closing.skip()
	if game_kind == PlayerProfile.Game.EXPERT:
		game.closing.finish()                                          # the Expert closing ignores keys until its last stage (a key ends it there)
	await await_idle_frame()
	await await_idle_frame()
	assert_int(SaveStore.hall.entries.size()).is_equal(1)
	assert_int(SaveStore.hall.entries[0].game).is_equal(game_kind)
	var view := game.dialog_layer.get_child(game.dialog_layer.get_child_count() - 1) as HallOfFameView
	assert_object(view).is_not_null()
	view.close()
	await await_idle_frame()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.SIGN_IN)


func test_a_voyager_game_from_the_first_sector_to_the_hall_of_fame() -> void:
	await _play_whole_game(PlayerProfile.Game.VOYAGER)


func test_an_expert_game_from_the_first_sector_to_the_hall_of_fame() -> void:
	await _play_whole_game(PlayerProfile.Game.EXPERT)
