class_name TestFullRun
extends GdUnitTestSuite
## Teaches: an end-to-end test on the pack's first campaign (the dev tour). A scripted "player" completes every sector of it (collects every
## piece and opens the lock the way the flow does after a solved lock), docks in the finale, and the run must end in the Hall of Fame and back at sign-in.
## (The original's two games, with their closing sequences: tests/legacy/test_full_voyager_run.gd.)
## Animations are switched off (`SectorWorld.skip_animations`), the router only records where it would go,
## and the roster goes to scratch files.

const ROSTER := "user://test_full_roster.json"
const HALL := "user://test_full_hall.json"

var _old_roster: String
var _old_hall: String
var _old_players: Array[PlayerProfile]


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


func test_the_first_campaign_from_its_first_sector_to_the_hall_of_fame() -> void:
	var campaign := Catalog.default_campaign()
	var player := SaveStore.add_player_in("Runner", campaign)
	player.hints_enabled = false
	GameState.profile = player
	var game := scene_runner("res://src/gameplay/game.tscn").scene() as Game
	await await_idle_frame()
	var visited: Array[int] = []
	for step in campaign.sector_count():
		var sector := player.sector()
		assert_int(game.world.sector_index).is_equal(sector)
		visited.append(sector)
		for i in game.world.sector.pieces.size():
			GameState.collect_piece(i)
		game.complete_sector()                                       # (the lock is solved: not awaited, it waits for the map)
		await await_idle_frame()
		(game.problem_layer.get_child(0) as SurfaceShipScreen).finish()
		await await_idle_frame()
	assert_array(visited).is_equal(Array(campaign.sectors))
	var finale := campaign.finales[0]
	assert_int(player.sector()).is_equal(finale)
	assert_int(game.world.sector_index).is_equal(finale)
	assert_int(SaveStore.hall.entries.size()).is_equal(0)
	# docking in the finale ends the game: the supply station's screen first (if the campaign has words for it), then the Hall of Fame
	for i in game.world.sector.pieces.size():
		GameState.collect_piece(i)
	game.complete_sector()
	await await_idle_frame()
	var screen := game.problem_layer.get_child(0) as SurfaceShipScreen if game.problem_layer.get_child_count() > 0 else null
	if screen != null:
		screen.finish()
	await await_idle_frame()
	await await_idle_frame()
	assert_int(SaveStore.hall.entries.size()).is_equal(1)
	assert_str(SaveStore.hall.entries[0].campaign_id).is_equal(campaign.id)
	var view := game.dialog_layer.get_child(game.dialog_layer.get_child_count() - 1) as HallOfFameView
	assert_object(view).is_not_null()
	view.close()
	await await_idle_frame()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.SIGN_IN)
