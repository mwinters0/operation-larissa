class_name TestMessageLightDeath
extends GdUnitTestSuite
## Teaches: state that two layers show must be reset by the layer that owns it. The blinking message light has three parts: the
## countdown in the rules (`SimWorld.pending_slot`), the beacon on the sub (`SubModel.message_light`) and the console's light
## (`GameState.ship_light` / `computer_light`, which the HUD only mirrors). A sector load, which is also how the sub respawns after
## a lost tank, starts a `DoAction` (0x417ffc): it zeroes `MessageLightCountdown` (0x448688) and `DisplayBezel` (0x419eec) draws
## the console with both lights out. This test dies in the middle of the blinking and checks all three parts after the respawn.
## The dev test sector 150, screen 5, has the math trigger (slot 20, a computer alert) used by `test_trigger.gd`.

const GAME_SCENE := "res://src/gameplay/game.tscn"
const HUD_SCENE := "res://src/ui/hud.tscn"
const ROSTER := "user://test_light_roster.json"
const HALL := "user://test_light_hall.json"
const SECTOR := 150
const SCREEN := 5

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
	var player := SaveStore.add_player("Tester", 0)
	player.hints_enabled = false
	GameState.profile = player


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


## A running game on the test sector with the sub on the screen of the trigger, and a HUD beside it.
func _start() -> Array:
	var game := scene_runner(GAME_SCENE).scene() as Game
	await await_idle_frame()
	var hud := scene_runner(HUD_SCENE).scene() as Hud
	game.world.load_sector(SECTOR, SCREEN)
	game.world.start_flight()
	game.world.foes_active = false
	return [game, hud]


func _touch_the_trigger(game: Game) -> void:
	var sim := game.world.sim
	sim.touch_trigger(sim.triggers_on_screen(SCREEN)[0])


func test_touching_the_trigger_lights_the_console_and_the_beacon() -> void:
	var started := await _start()
	var game := started[0] as Game
	var hud := started[1] as Hud
	_touch_the_trigger(game)
	assert_int(game.world.sim.pending_slot).is_equal(20)
	assert_bool(game.world.sim.sub.message_light).is_true()
	assert_bool(GameState.computer_light).is_true()
	assert_bool(hud.computer_glow.visible).is_true()


func test_a_lost_tank_in_the_middle_of_the_blinking_puts_every_light_out() -> void:
	var started := await _start()
	var game := started[0] as Game
	var hud := started[1] as Hud
	_touch_the_trigger(game)
	GameState.update_oxygen(-4)                                   # the tank is lost: `GameFlow.respawn`
	await await_idle_frame()
	assert_int(GameState.tanks()).is_equal(GameState.tuning.refill_tanks - 1)
	assert_int(game.world.sim.pending_slot).is_equal(-1)
	assert_int(game.world.sim.pending_ticks).is_equal(0)
	assert_bool(game.world.sim.sub.message_light).is_false()
	assert_bool(GameState.ship_light).is_false()
	assert_bool(GameState.computer_light).is_false()
	assert_bool(hud.ship_glow.visible).is_false()
	assert_bool(hud.computer_glow.visible).is_false()
	assert_bool(hud.light_animations.is_playing()).is_false()


func test_a_ship_message_light_does_not_survive_the_respawn_either() -> void:
	var started := await _start()
	var game := started[0] as Game
	var hud := started[1] as Hud
	GameState.set_message_light(true, false)                      # (what a trigger with a surface ship slot lights)
	GameState.update_oxygen(-4)
	await await_idle_frame()
	assert_bool(GameState.ship_light).is_false()
	assert_bool(hud.ship_glow.visible).is_false()
	assert_int(game.world.sim.pending_slot).is_equal(-1)


## Leaving the game with a light on, then signing in again: the run begins at the sign-in (`GameState.begin_run`), before the next
## game scene exists, so the new console reads a dark light and plays no `message_light` sound when it starts.
func test_a_light_left_on_does_not_sound_when_the_next_game_starts() -> void:
	var player := GameState.profile
	var first := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	get_tree().root.add_child(first)
	await await_idle_frame()
	first.world.load_sector(SECTOR, SCREEN)
	first.world.start_flight()
	first.world.foes_active = false
	_touch_the_trigger(first)
	assert_bool(GameState.computer_light).is_true()
	first.leave_to_sign_in()                                      # (a dry run: the router only records it)
	get_tree().root.remove_child(first)
	first.free()
	GameState.begin_run(player)                                   # what the sign-in screen does when the player starts again
	var sounds: Array[StringName] = []
	var record := func(sfx: StringName) -> void: sounds.append(sfx)
	Audio.sfx_played.connect(record)
	var second := scene_runner(GAME_SCENE).scene() as Game
	await await_idle_frame()
	Audio.sfx_played.disconnect(record)
	assert_object(second).is_not_null()
	assert_array(sounds).not_contains([&"message_light"])
	assert_bool(GameState.computer_light).is_false()
	assert_bool(GameState.ship_light).is_false()
