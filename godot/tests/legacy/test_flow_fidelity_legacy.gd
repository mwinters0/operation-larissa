class_name TestFlowFidelityLegacy
extends GdUnitTestSuite
## Teaches: small behaviours of the original's flow that depend on its songs and words: the Expert closing's song ends with the sequence, the return-to-sign-in question
## and the notice of a customized game say what the original said, and the songs around the dock are the original's. (The flow on any pack: tests/engine/test_flow_fidelity.gd.)

const GAME_SCENE := "res://src/gameplay/game.tscn"
const SIGN_IN_SCENE := "res://src/ui/sign_in.tscn"
const EXPERT_SCENE := "res://src/story/expert_closing.tscn"
const ROSTER := "user://test_fidelity_legacy_roster.json"
const HALL := "user://test_fidelity_legacy_hall.json"

var _old_roster: String
var _old_hall: String
var _old_players: Array[PlayerProfile]
var _player: PlayerProfile
var _probe: AudioProbe


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
	SignIn.welcome_enabled = false
	_player = SaveStore.add_player("Flow", 0)
	_player.hints_enabled = false
	GameState.profile = _player
	_probe = AudioProbe.new()


func after_test() -> void:
	_probe.stop()
	Audio.stop_music()
	Audio.stop_voice()
	Audio.apply_profile(null)
	SaveStore.roster_path = _old_roster
	SaveStore.hall_path = _old_hall
	SaveStore.players = _old_players
	SaveStore.hall = HallOfFame.new()
	SectorWorld.skip_animations = false
	SceneRouter.dry_run = false
	SignIn.welcome_enabled = true
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


func test_the_songs_around_the_dock_are_the_originals() -> void:
	var game := await _start()
	for i in game.world.sector.pieces.size():
		GameState.collect_piece(i)
	_probe.clear()
	game.complete_sector()
	await await_idle_frame()
	assert_array(_probe.music).is_equal([&"sector_song_1", AudioService.NO_MUSIC])
	(game.problem_layer.get_child(0) as SurfaceShipScreen).finish()
	await await_idle_frame()
	assert_array(_probe.music).is_equal([&"sector_song_1", AudioService.NO_MUSIC, &"sector_song_1", &"sector_song_2"])
	assert_str(Audio.song).is_equal(&"sector_song_2")


func test_the_expert_closing_song_ends_with_the_sequence() -> void:
	var closing: ExpertClosing = auto_free(load(EXPERT_SCENE).instantiate())
	add_child(closing)
	assert_str(Audio.song).is_equal(AudioService.SONG_CLOSING)
	closing.finish()
	assert_str(Audio.song).is_equal(AudioService.NO_MUSIC)         # not carried into the Hall of Fame


func test_the_return_to_sign_in_question_has_the_originals_words() -> void:
	var game := await _start()
	game.ask_to_return_to_sign_in()
	assert_str(game.messages.current.body).contains("Only those sectors you have completed")
	game.messages.close_current(1)


func test_the_notice_of_a_customized_game_has_the_originals_words() -> void:
	var screen := scene_runner(SIGN_IN_SCENE).scene() as SignIn
	var profile := screen.add_player("Cust", 0)
	profile.voice_on = false
	profile.customized = true
	profile.edu_level = 2
	profile.calculator_on = false
	assert_str(GameFlow.customized_notice_text(profile)).contains("has been customized")
