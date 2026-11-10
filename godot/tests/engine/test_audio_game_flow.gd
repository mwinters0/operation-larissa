class_name TestAudioGameFlow
extends GdUnitTestSuite
## The audio side of a whole game: music per sector, silence during a problem, the player's switches, the
## sign-in speech and the mission-control message on the map.

const GAME_SCENE := "res://src/gameplay/game.tscn"
const ROSTER := "user://test_audio_roster.json"
const HALL := "user://test_audio_hall.json"

var _old_roster: String
var _old_hall: String
var _old_players: Array[PlayerProfile]
var _player: PlayerProfile
var _probe: AudioProbe
var _undo: Array[Callable] = []                 ## puts back what a test changed in the pack's data (resources are shared by every test)


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
	_player = SaveStore.add_player("Audio", 0)
	_player.hints_enabled = false
	GameState.profile = _player
	_probe = AudioProbe.new()


func after_test() -> void:
	for undo in _undo:
		undo.call()
	_undo.clear()
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


func test_a_game_starts_the_music_of_its_sector() -> void:
	var game := await _start()
	assert_str(Audio.song).is_equal(&"sector_song_1")
	assert_int(game.world.sector_index).is_equal(0)
	assert_array(_probe.music).contains(&"sector_song_1")
	assert_bool(_probe.sfx.has(&"begin")).is_true()                      # "begin": the sector's first screen is drawn


## Gives sector `index` of the campaign the tune (the stem of a MIDI file) `stem`, until the end of the test.
func _name_the_tune(index: int, stem: String) -> void:
	var data := Catalog.sector(index)
	var old := data.music_name
	_undo.append(func() -> void: data.music_name = old)
	data.music_name = stem


func test_sectors_that_name_the_same_tune_share_it_and_another_has_its_own() -> void:
	var game := await _start()
	var first_tune := Catalog.sector(0).music_name
	_name_the_tune(2, first_tune)
	await game.begin_sector(2, false)
	assert_str(Audio.song).is_equal(&"sector_song_1")
	assert_str(Audio.song).is_equal(AudioService.music_for_sector(0))
	await game.begin_sector(1, false)
	assert_str(Audio.song).is_equal(&"sector_song_2")
	_name_the_tune(DevPack.TOUR_FINALE, "eend")                       # the stem of the finale's MIDI file
	await game.begin_sector(DevPack.TOUR_FINALE, false)
	assert_str(Audio.song).is_equal(&"finale")


func test_the_music_plays_on_across_a_screen_change() -> void:
	# DoAction draws a new screen with DrawScreen(0) (0x433f1c) and PlaySectorMusic(0) (0x43204d): no sound, no music restart.
	var game := await _start()
	_probe.clear()
	game.world.sim._on_sub_crossed_edge(SectorData.Direction.RIGHT)
	assert_int(game.world.screen_index).is_equal(1)
	assert_array(_probe.music).is_empty()
	assert_str(Audio.song).is_equal(&"sector_song_1")


func test_the_begin_sound_plays_when_a_sector_starts_not_at_a_screen_change() -> void:
	# "begin" (0x16, the oxygen-level beeps) is DrawScreen(1): only at the start / respawn of a sector.
	var game := await _start()
	assert_bool(_probe.sfx.has(&"begin")).is_true()
	_probe.clear()
	for direction in [SectorData.Direction.RIGHT, SectorData.Direction.RIGHT, SectorData.Direction.LEFT]:
		game.world.sim._on_sub_crossed_edge(direction)
	assert_array(_probe.sfx).is_empty()
	await game.begin_sector(0, false)                                  # a respawn / new sector
	assert_bool(_probe.sfx.has(&"begin")).is_true()


func test_the_music_stops_during_a_problem_and_returns_after_it() -> void:
	var game := await _start()
	assert_str(Audio.song).is_equal(&"sector_song_1")
	game.world.problem_active = true
	game.flow.open_problem(2)                                      # a coroutine: runs until the problem is up
	assert_str(Audio.song).is_equal(AudioService.NO_MUSIC)
	var screen: ProblemScreen = game.problem_layer.get_child(game.problem_layer.get_child_count() - 1)
	screen.close()
	await await_idle_frame()
	assert_str(Audio.song).is_equal(&"sector_song_1")


func test_a_message_box_holds_the_music_until_it_closes() -> void:
	var game := await _start()
	assert_int(Audio._music_pause_count).is_equal(0)
	game.messages.post("Test", "Hello")
	assert_int(Audio._music_pause_count).is_equal(1)
	game.messages.close_current(0)
	assert_int(Audio._music_pause_count).is_equal(0)


func test_the_options_menu_switches_the_buses_and_the_player_keeps_them() -> void:
	var game := await _start()
	# each item asks a Yes / No question (MenuMusic 0x42bd56 ...); button 0 is Yes, 1 is No
	game.menu_bar.options_menu.id_pressed.emit(2)                      # Music off
	game.messages.close_current(1)
	assert_bool(Audio.is_bus_enabled(AudioService.MUSIC)).is_false()
	assert_bool(_player.music_on).is_false()
	game.menu_bar.options_menu.id_pressed.emit(1)                      # Sound Effects off
	game.messages.close_current(1)
	assert_bool(Audio.is_bus_enabled(AudioService.SFX)).is_false()
	game.menu_bar.options_menu.id_pressed.emit(3)                      # Voice off
	game.messages.close_current(1)
	assert_bool(Audio.is_bus_enabled(AudioService.VOICE)).is_false()
	game.menu_bar.options_menu.id_pressed.emit(2)                      # Music on again
	game.messages.close_current(0)
	assert_bool(Audio.is_bus_enabled(AudioService.MUSIC)).is_true()
	assert_bool(_player.music_on).is_true()


func test_a_player_with_the_sound_off_starts_with_it_off() -> void:
	_player.sound_on = false
	_player.voice_on = false
	await _start()
	assert_bool(Audio.is_bus_enabled(AudioService.SFX)).is_false()
	assert_bool(Audio.is_bus_enabled(AudioService.VOICE)).is_false()
	assert_bool(Audio.is_bus_enabled(AudioService.MUSIC)).is_true()


func test_the_audio_settings_item_opens_the_dialog() -> void:
	var game := await _start()
	game.menu_bar.options_menu.id_pressed.emit(GameMenuBar.AUDIO_SETTINGS_ID)
	await await_idle_frame()
	var dialog: AudioSettingsDialog = null
	for child in game.dialog_layer.get_children():
		if child is AudioSettingsDialog:
			dialog = child
	assert_object(dialog).is_not_null()
	assert_int(Audio._music_pause_count).is_equal(1)                    # the song is held while the dialog is up
	dialog.close()
	await await_idle_frame()
	await await_idle_frame()
	assert_int(Audio._music_pause_count).is_equal(0)


func test_the_surface_ship_screen_speaks_the_supply_message_and_enter_cuts_it_off() -> void:
	var map := scene_runner("res://src/story/surface_ship_screen.tscn").scene() as SurfaceShipScreen
	assert_str(Catalog.campaign_of_sector(3).supply_voice_name(3)).is_equal(&"supply_3")      # (the tour speaks the pack's group supply_<k> for its sector k)
	map.show_supply_message(3)
	var cues := Catalog.voice_cues()
	var expected: Array[StringName] = [cues.jingle()]
	expected.append_array(cues.clips("supply_3"))
	assert_array(cues.clips("supply_3")).is_not_empty()
	assert_array(_probe.voice[0]).is_equal(Array(expected))
	assert_bool(Audio.is_voice_playing()).is_true()
	map.finish()
	assert_bool(Audio.is_voice_playing()).is_false()


func test_the_sign_in_screen_welcomes_and_start_speaks_the_clearance() -> void:
	SignIn.welcome_enabled = true
	SignIn.new_player_added = false                                             # no New in this run: Start says "Resume mission" (G26)
	var screen := scene_runner("res://src/ui/sign_in.tscn").scene() as SignIn
	await await_idle_frame()
	assert_array(_probe.voice[0]).is_equal(Array(Catalog.voice_cues().sign_in_first_visit()))
	Audio.stop_voice()                                                          # (the speech is synchronous: cut it, as a key would)
	await await_idle_frame()
	_probe.clear()
	screen.tree.get_root().get_first_child().select(0)
	_player.voice_on = false                                                    # Start would wait for the clearance speech to end
	await screen.request_start()
	assert_array(_probe.sfx).is_equal([&"scanner"])                                   # the scanner, then the speech
	assert_array(_probe.voice[0]).is_equal(Array(Catalog.voice_cues().sign_in_start(true)))
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.GAME)
	Audio.stop_voice()
