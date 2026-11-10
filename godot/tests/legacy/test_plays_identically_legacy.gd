class_name TestPlaysIdenticallyLegacy
extends GdUnitTestSuite
## Teaches: the proof that the game plays the SAME with every presenter and skin, on a whole mission through the real `Game` scene of the original's
## game: sectors 0 and 1 of Voyager from the launch to the supply message (a problem opened by a trigger, the dock with a piece missing, the lock
## "solved") and the finale (sector 30) to the Hall of Fame. The visits to single sectors, with the dev pack's, are `engine/test_plays_identically.gd`.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const GAME_SCENE := "res://src/gameplay/game.tscn"
const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"
const ROSTER := "user://test_identical_roster.json"
const HALL := "user://test_identical_hall.json"

var _old_roster: String
var _old_hall: String
var _old_players: Array[PlayerProfile]


func before_test() -> void:
	GameClock.paused = true
	SectorWorld.skip_animations = false
	PresenterChoice.forced = &""
	SkinChoice.select(SkinChoice.original())
	GameState.reset()
	_old_roster = SaveStore.roster_path
	_old_hall = SaveStore.hall_path
	_old_players = SaveStore.players.duplicate()
	SkinRoster.mount_mod_skins()


func after_test() -> void:
	GameClock.paused = false
	SkinRoster.release_mod_skins()
	SectorWorld.skip_animations = false
	PresenterChoice.forced = &""
	SkinChoice.select(SkinChoice.original())
	SaveStore.roster_path = _old_roster
	SaveStore.hall_path = _old_hall
	SaveStore.players = _old_players
	SaveStore.hall = HallOfFame.new()
	SceneRouter.dry_run = false
	SceneRouter.last_path = ""
	GameState.profile = null
	GameState.hints.reset()
	GameState.reset()
	for path in [ROSTER, HALL]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## The player's key presses are the scripted hands; the clock is paused and the test is the clock. Plays sectors 0 and 1 from the
## launch to the supply message (a problem opened by a trigger, the dock with a piece missing, the lock "solved") and the finale to
## the Hall of Fame. Returns the trace of the rules. With `skin`, the game is started wearing it (its presenter, its HUD, its render settings).
func _mission(kind: StringName, skin: GameSkin = null) -> Array[String]:
	SaveStore.roster_path = ROSTER
	SaveStore.hall_path = HALL
	SaveStore.players = []
	SaveStore.hall = HallOfFame.new()
	SectorWorld.skip_animations = true               # (the steps with real time in them are in the tests above; here the FLOW is looked at)
	SceneRouter.dry_run = true
	SceneRouter.last_path = ""
	GameState.reset()
	var player := SaveStore.add_player("Identical", PlayerProfile.Game.VOYAGER)
	player.hints_enabled = false
	GameState.profile = player
	PresenterChoice.forced = kind
	SkinChoice.select(skin if skin != null else SkinChoice.original())
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	var world := game.get_node("%SectorWorld") as SectorWorld
	var trace := SimTrace.record(world.sim, GameState)
	add_child(game)
	GameClock.paused = true                          # (`Game._ready` starts the clock: stop it before a frame goes by)
	await await_idle_frame()
	if skin == null:
		assert_object(world.presenter).is_instanceof(DebugRectPresenter if kind == PresenterChoice.DEBUG_RECTS else OriginalPresenter)
	else:                                           # (the skin's own presenter, if it brings one; and the HUD with the skin's layout)
		assert_bool(world.presenter is DebugRectPresenter).is_equal(kind == PresenterChoice.DEBUG_RECTS)
		var hud := game.get_node("Hud") as Hud
		assert_object(hud).is_not_null()
		assert_object(hud.layout).is_same(Catalog.hud_layout())
	var fraction := [0.0]
	world.sim.ticked.connect(func() -> void:
		fraction[0] = fmod(fraction[0] + 0.37, 1.0)
		world.presenter.show_between_ticks(fraction[0]))
	for sector in 2:
		world.sim.foe_context.rng.seed = 11 + sector
		var hands := SimTrace.Hands.new(sector, 0)
		for t in 60:
			world.tick(hands.at(t))
		await await_idle_frame()
		# a math trigger: the countdown runs, the game puts up the problem screen, the player gives up on it
		var trigger: TriggerModel = world.sim.triggers.filter(func(t: TriggerModel) -> bool: return t.data.slot != SimWorld.CANISTER_SLOT)[0]
		world.sim.load_screen(trigger.screen)
		world.sim.start_flight(trigger.data.pos.x - 40, trigger.data.pos.y - 25, 6)
		var waited := 0
		while game.problem_layer.get_child_count() == 0 and waited < 100:
			world.tick()
			waited += 1
		var screen := game.problem_layer.get_child(0) as ProblemScreen
		assert_object(screen).override_failure_message("sector %d: no problem screen" % sector).is_not_null()
		screen.close()
		await await_idle_frame()
		await await_idle_frame()
		# the dock with a piece missing: the ship says so
		GameState.collect_piece(0)
		world.sim.load_screen(SimWorld.DOCK_SCREEN)
		world.sim.start_flight(400, 200, 6)
		world.tick()
		world.tick()
		var ship := game.problem_layer.get_child(0) as SurfaceShipScreen
		assert_object(ship).override_failure_message("sector %d: no message about the missing pieces" % sector).is_not_null()
		ship.finish()
		await await_idle_frame()
		# every piece, the lock "solved", the supply message, the next sector
		for i in world.sector.pieces.size():
			GameState.collect_piece(i)
		game.complete_sector()
		await await_idle_frame()
		(game.problem_layer.get_child(0) as SurfaceShipScreen).finish()
		await await_idle_frame()
		assert_int(world.sector_index).is_equal(sector + 1)
	# the finale (sector 30): touch the treasure, swim to the closing screen, the closing, the Hall of Fame
	player.progress = Progression.VOYAGER_FINALE
	GameState.clear_midpoint()
	GameState.refresh_edu_level()
	game.begin_sector(player.sector(), false)
	await await_idle_frame()
	world.sim.foe_context.rng.seed = 99
	for t in 60:
		world.tick(SimTrace.Hands.new(30, 0).at(t))
	world.sim.sub.invulnerability = 100
	world.load_screen(world.sim.foes[0].vm.screen)
	world.sub_touches(world.sim.foes[0])
	for t in 4:
		world.tick()
	world.load_screen(SimWorld.finale_screen(30))
	world.tick()
	assert_object(game.closing).is_not_null()
	game.closing.skip()
	await await_idle_frame()
	await await_idle_frame()
	assert_int(SaveStore.hall.entries.size()).is_equal(1)
	var view := game.dialog_layer.get_child(game.dialog_layer.get_child_count() - 1) as HallOfFameView
	view.close()
	await await_idle_frame()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.SIGN_IN)
	var lines := trace.lines.duplicate()
	game.queue_free()
	await await_idle_frame()
	return lines


func test_a_whole_mission_through_the_game_plays_the_same_with_the_debug_rectangles() -> void:
	var original := await _mission(PresenterChoice.ORIGINAL)
	var debug := await _mission(PresenterChoice.DEBUG_RECTS)
	assert_int(original.size()).is_greater(500)
	assert_bool(original.any(func(line: String) -> bool: return line.contains("sector_loaded 1"))).is_true()
	assert_bool(original.any(func(line: String) -> bool: return line.contains(" finale"))).is_true()
	assert_int(debug.size()).override_failure_message("another number of lines").is_equal(original.size())
	for i in original.size():
		if debug[i] != original[i]:
			fail("the rules differ at line %d\n  original: %s\n  debug:    %s" % [i, original[i], debug[i]])
			break


func test_a_whole_mission_through_the_game_plays_the_same_with_every_skin() -> void:
	var original := await _mission(PresenterChoice.ORIGINAL)
	assert_int(original.size()).is_greater(500)
	for skin in SkinRoster.all():
		var lines := await _mission(PresenterChoice.ORIGINAL, skin)
		assert_int(lines.size()).override_failure_message("skin %s: another number of lines" % skin.id).is_equal(original.size())
		for i in original.size():
			if lines[i] != original[i]:
				fail("skin %s: the rules differ at line %d\n  original: %s\n  skin:     %s" % [skin.id, i, original[i], lines[i]])
				break
