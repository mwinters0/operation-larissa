class_name TestFlowFidelity
extends GdUnitTestSuite
## Teaches: pinning small behaviours of the game flow that were read from the decompilation (ACTION.C `DoAction`,
## SUPPLY.C, OPTIONS.C, SIGNIN.C) and are easy to lose in a refactoring: WHEN the music changes around the dock,
## which light the dock message turns on, which words the menus use, and what a Yes / No question does with its
## answers. The music and sound events are watched with an `AudioProbe` (no loudspeaker needed).

const GAME_SCENE := "res://src/gameplay/game.tscn"
const SIGN_IN_SCENE := "res://src/ui/sign_in.tscn"
const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const ROSTER := "user://test_fidelity_roster.json"
const HALL := "user://test_fidelity_hall.json"

var _old_roster: String
var _old_hall: String
var _old_players: Array[PlayerProfile]
var _player: PlayerProfile
var _probe: AudioProbe


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
	SignIn.welcome_enabled = false                                       # (the welcome speech holds the list back; tested in test_sign_in_ui)
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


# --- the dock: music (DoAction 0x41822d, 0x418238, 0x41824c) --------------------------------------------

func test_the_lock_opening_plays_the_song_while_docking_is_silent_on_the_map_and_plays_for_the_balloon() -> void:
	var game := await _start()
	for i in game.world.sector.pieces.size():
		GameState.collect_piece(i)
	_probe.clear()
	game.complete_sector()                                             # waits for the surface ship screen
	await await_idle_frame()
	# PlaySectorMusic(1) before EnterSupplyStation, StopSectorMusic after it: the supply message is silent
	var first_song := AudioService.music_for_sector(0)
	var second_song := AudioService.music_for_sector(1)
	assert_array(_probe.music).is_equal([first_song, AudioService.NO_MUSIC])
	assert_str(Audio.song).is_equal(AudioService.NO_MUSIC)
	(game.problem_layer.get_child(0) as SurfaceShipScreen).finish()
	await await_idle_frame()
	# PlaySectorMusic(1) before LaunchBalloon (the finished sector's song), then sector 1 starts with its own
	assert_array(_probe.music).is_equal([first_song, AudioService.NO_MUSIC, first_song, second_song])
	assert_str(Audio.song).is_equal(second_song)


# --- the dock: the ship's message light (DisplayShipMathIcon 0x419ec3) -------------------------------------

func test_the_pieces_missing_message_turns_the_ship_light_on_with_its_sound_and_off_after() -> void:
	var game := await _start()
	GameState.collect_piece(0)
	_probe.clear()
	game.world.dock_reached.emit()
	assert_bool(game.messages.is_open()).is_false()                    # (the surface ship's screen, not a message box)
	assert_bool(GameState.ship_light).is_true()
	assert_bool(GameState.computer_light).is_false()
	assert_array(_probe.sfx).is_equal([&"message_light"])                          # the same sound as every message light
	assert_str(Audio.song).is_equal(AudioService.NO_MUSIC)         # silent while the ship talks
	(game.problem_layer.get_child(0) as SurfaceShipScreen).finish()     # Enter
	await await_idle_frame()
	assert_bool(GameState.ship_light).is_false()                       # DisplayShipMathIcon(0, 0)
	assert_str(Audio.song).is_equal(AudioService.music_for_sector(0))                  # PlaySectorMusic(1) 0x4181df


# --- the door sound (ExitSupplyStation 0x4329b2, EnterSupplyStation 0x432cdd) -------------------------------

func test_the_door_sound_comes_from_the_rules_one_tick_after_the_door_starts_to_close() -> void:
	for trip: StationSequence in [StationSequence.launch(), StationSequence.dock()]:             # launch (96 px) and dock (100 px)
		var close_start: int = trip.opening_ticks + trip.drive_ticks()
		# the door shows closing picture 4 at tick 3 + drive, then picture 3 (with the sound) one tick later
		assert_int(trip.door_sound_tick()).is_equal(close_start + 1)
		assert_int(trip.door_picture(trip.door_sound_tick())).is_equal(3)
		assert_int(trip.door_picture(close_start)).is_equal(4)


func test_the_launch_is_silent_until_the_door_closes() -> void:
	SectorWorld.skip_animations = false                                 # (after_test puts it back)
	GameClock.paused = true                                             # (the test counts the ticks itself)
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(0, 0)
	world.sim.foes_active = false
	var heard: Array[int] = []
	var ticks := [0]
	world.sfx_requested.connect(func(sfx: StringName) -> void:
		if sfx == SimWorld.SFX_STATION_DOOR:
			heard.append(ticks[0]))
	var done := [false]
	(func() -> void:
		await world.launch()
		done[0] = true).call()
	while not done[0]:
		ticks[0] += 1
		world.tick()
	assert_array(heard).is_equal([27])                                    # 2 + 24 + 1 ticks after the launch began; the launch is 28 long
	assert_int(ticks[0]).is_equal(28)
	GameClock.paused = false


# --- File > Return to Sign In (MenuReturnToSignInSave 0x42b914) ------------------------------------------

func test_the_in_game_return_to_sign_in_asks_with_string_11126_and_starts_on_no() -> void:
	var game := await _start()
	game.ask_to_return_to_sign_in()
	var strings := Catalog.texts("ui_strings")
	assert_str(game.messages.current.title).is_equal(strings.text(11127))
	assert_str(game.messages.current.body).is_equal(strings.text(11126).replace("\r", "\n"))
	assert_int(game.messages.current.default_button).is_equal(1)       # the dialog record's default button is No
	game.messages.close_current(1)
	assert_str(SceneRouter.last_path).is_equal("")


func test_yes_saves_and_goes_back_to_sign_in() -> void:
	var game := await _start()
	game.ask_to_return_to_sign_in()
	game.messages.close_current(0)
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.SIGN_IN)
	assert_bool(FileAccess.file_exists(ROSTER)).is_true()


# --- Options > Sound Effects / Music / Voice / New Player Hints (0x42bcdf ...) --------------------------

func test_each_option_asks_its_own_question() -> void:
	var game := await _start()
	var strings := Catalog.texts("ui_strings")
	for case: Array in [[&"sound", 11138, 11139], [&"music", 11140, 11141], [&"voice", 11136, 11137], [&"hints", 11143, 11142]]:
		game.menu_bar.option_dialog_requested.emit(case[0])
		assert_str(game.messages.current.title).is_equal(strings.text(case[1]))
		assert_str(game.messages.current.body).is_equal(strings.text(case[2]).replace("\r", "\n"))
		assert_array(Array(game.messages.current.buttons)).is_equal(["Yes", "No"])
		game.messages.close_current(-1)


func test_the_default_button_is_the_answer_that_changes_the_setting() -> void:
	var game := await _start()
	game.ask_option(&"sound")                                           # sound is on: the default is No
	assert_int(game.messages.current.default_button).is_equal(1)
	game.messages.close_current(-1)
	_player.sound_on = false
	game.ask_option(&"sound")                                           # sound is off: the default is Yes
	assert_int(game.messages.current.default_button).is_equal(0)
	game.messages.close_current(-1)


func test_escape_leaves_the_setting_alone_and_no_turns_it_off() -> void:
	var game := await _start()
	game.ask_option(&"voice")
	assert_int(game.messages.current.escape_choice).is_equal(-1)
	game.messages.close_current(-1)                                     # Escape
	assert_bool(_player.voice_on).is_true()
	assert_bool(Audio.is_bus_enabled(AudioService.VOICE)).is_true()
	game.ask_option(&"voice")
	game.messages.close_current(1)                                      # No
	assert_bool(_player.voice_on).is_false()
	assert_bool(Audio.is_bus_enabled(AudioService.VOICE)).is_false()
	assert_bool(game.menu_bar.options_menu.is_item_checked(3)).is_false()


func test_a_menu_choice_opens_the_question_instead_of_toggling() -> void:
	var game := await _start()
	game.menu_bar.options_menu.id_pressed.emit(2)                       # Music
	assert_bool(game.messages.is_open()).is_true()
	assert_bool(_player.music_on).is_true()                             # nothing changed yet
	game.messages.close_current(1)
	assert_bool(_player.music_on).is_false()


func test_yes_on_music_restarts_the_song_from_the_beginning() -> void:
	var game := await _start()
	game.ask_option(&"music")
	game.messages.close_current(1)                                      # off: the song is only silenced
	assert_str(Audio.song).is_equal(AudioService.music_for_sector(0))
	_probe.clear()
	game.ask_option(&"music")
	game.messages.close_current(0)                                      # on again: PlayBackgroundMusic(current id)
	assert_array(_probe.music).is_equal([AudioService.music_for_sector(0)])         # started again, not merely un-muted
	assert_bool(Audio.is_bus_enabled(AudioService.MUSIC)).is_true()
	assert_bool(_player.music_on).is_true()


func test_yes_on_hints_makes_every_hint_new_again() -> void:
	var game := await _start()
	GameState.hints.enabled = true                                      # (the test player starts with hints off)
	assert_bool(GameState.hints.take(HintSystem.CONTROLS)).is_true()
	GameState.hints.enabled = false
	game.ask_option(&"hints")
	game.messages.close_current(0)
	assert_bool(GameState.hints.enabled).is_true()
	assert_bool(GameState.hints.has_been_shown(HintSystem.CONTROLS)).is_false()


# --- the Yes / No box itself ---------------------------------------------------------------------------------

func test_a_message_can_choose_its_default_button_and_what_escape_answers() -> void:
	var queue := MessageQueue.new(GameClock)
	var message := queue.post("Q", "?", PackedStringArray(["Yes", "No"]), true, 0, 1, -1)
	assert_int(message.default_button).is_equal(1)
	assert_int(message.escape_choice).is_equal(-1)
	var plain := MessageQueue.new(GameClock).post("Q", "?", PackedStringArray(["Yes", "No"]))
	assert_int(plain.default_button).is_equal(0)
	assert_int(plain.escape_choice).is_equal(MessageQueue.LAST_BUTTON)
	GameClock.release()
	queue.close_current(0)
	GameClock.paused = false


func test_the_box_focuses_the_default_button_and_y_n_answer() -> void:
	var runner := scene_runner(GAME_SCENE)
	var game := runner.scene() as Game
	await await_idle_frame()
	var message := game.messages.post("Q", "?", PackedStringArray(["Yes", "No"]), true, 0, 1, -1)
	var buttons := game.message_view.button_row
	assert_bool((buttons.get_child(1) as Button).has_focus()).is_true()
	runner.simulate_key_pressed(KEY_Y)
	assert_int(message.choice).is_equal(0)
	var again := game.messages.post("Q", "?", PackedStringArray(["Yes", "No"]), true, 0, 1, -1)
	runner.simulate_key_pressed(KEY_ESCAPE)
	assert_int(again.choice).is_equal(-1)


# --- the sign-in screen (SignInScreenLoop 0x430c33) ----------------------------------------------------------

func test_new_wears_its_pressed_look_for_36_ticks_before_the_dialog_opens() -> void:
	var screen := scene_runner(SIGN_IN_SCENE).scene() as SignIn
	var started := Time.get_ticks_msec()
	var opened := [-1.0]
	(func() -> void:
		await screen.request_new_player()
		opened[0] = (Time.get_ticks_msec() - started) / 1000.0).call()
	assert_bool(screen.looks_pressed(screen.new_button)).is_true()
	assert_int(screen.overlay.get_child_count()).is_equal(0)            # no dialog yet
	while opened[0] < 0.0:
		await await_idle_frame()
	assert_float(opened[0]).is_between(SignIn.pressed_ticks() / 73.0 - 0.05, SignIn.pressed_ticks() / 73.0 + 0.4)
	assert_bool(screen.looks_pressed(screen.new_button)).is_false()
	assert_int(screen.overlay.get_child_count()).is_equal(1)            # the name dialog


func test_practice_and_exit_look_pressed_at_once() -> void:
	var screen := scene_runner(SIGN_IN_SCENE).scene() as SignIn
	screen.request_practice()
	assert_bool(screen.looks_pressed(screen.practice_button)).is_true()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.PRACTICE)
	var other := scene_runner(SIGN_IN_SCENE).scene() as SignIn
	other.ask_to_exit()
	assert_bool(other.looks_pressed(other.exit_button)).is_true()
	other.messages.close_current(1)                                     # No: the button is released
	assert_bool(other.looks_pressed(other.exit_button)).is_false()


func test_start_of_a_customized_game_shows_the_notice_after_36_ticks_before_the_scan() -> void:
	var screen := scene_runner(SIGN_IN_SCENE).scene() as SignIn
	var profile := screen.add_player("Cust", 0)
	profile.voice_on = false                                            # (no clearance speech to wait for)
	profile.customized = true
	profile.edu_level = 2
	profile.calculator_on = false
	screen.refresh()
	screen.select(profile)
	var done := [false]
	(func() -> void:
		await screen.request_start()
		done[0] = true).call()
	assert_bool(screen.looks_pressed(screen.start_button)).is_true()
	assert_bool(screen.messages.is_open()).is_false()                   # the pause comes first
	await await_millis(int(SignIn.pressed_ticks() * 1000.0 / 73.0) + 250)
	assert_bool(screen.messages.is_open()).is_true()
	assert_str(screen.messages.current.body).contains(Catalog.text(&"customized_intro"))
	assert_str(screen.messages.current.body).is_equal(GameFlow.customized_notice_text(profile))
	assert_bool(screen.scan_animation.is_playing()).is_false()          # the scan starts only after the notice
	screen.messages.close_current()
	while not done[0]:
		await await_idle_frame()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.GAME)
	Audio.stop_voice()


func test_start_of_an_ordinary_game_has_no_notice() -> void:
	var screen := scene_runner(SIGN_IN_SCENE).scene() as SignIn
	screen.add_player("Plain", 0).voice_on = false
	await screen.request_start()
	assert_bool(screen.messages.is_open()).is_false()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.GAME)
	Audio.stop_voice()
