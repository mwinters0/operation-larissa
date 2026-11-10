class_name TestSignInUiLegacy
extends GdUnitTestSuite
## Teaches: testing a screen with `scene_runner`: simulated keys, the scene's own signals and the autoloads it
## talks to. The roster files are redirected to scratch files, and `SceneRouter.dry_run` keeps the test runner's
## own scene in place (the router then only records where it would have gone).

const SCENE := "res://src/ui/sign_in.tscn"
const ROSTER := "user://test_signin_legacy_roster.json"
const HALL := "user://test_signin_legacy_hall.json"

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
	SceneRouter.dry_run = true
	SceneRouter.last_path = ""
	GameState.profile = null
	SignIn.welcome_enabled = false                  # (the welcome speech has its own tests; it would hold every other test back)
	SignIn.returning_from_practice = false
	SignIn.new_player_added = false                 # (`NewPlayerAdded` lives for the whole run of the program)
	SignIn.prompt_when_empty = false                # (most tests start from an empty list; the empty-roster loop has its own tests)


func after_test() -> void:
	SaveStore.roster_path = _old_roster
	SaveStore.hall_path = _old_hall
	SaveStore.players = _old_players
	SceneRouter.dry_run = false
	GameState.profile = null
	Audio.stop_voice()
	Audio.apply_profile(null)
	SignIn.new_player_added = false
	SignIn.prompt_when_empty = true
	SignIn.welcome_enabled = true
	SignIn.returning_from_practice = false
	for path in [ROSTER, HALL]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _open() -> SignIn:
	return scene_runner(SCENE).scene() as SignIn


## A player with the Voice option off: Start does not wait for the clearance speech (the original skips it, too).
func _add_quiet(screen: SignIn, player_name: String, game: int = 0) -> PlayerProfile:
	var profile := screen.add_player(player_name, game)
	profile.voice_on = false
	return profile


func test_an_empty_list_cannot_start() -> void:
	var screen := _open()
	assert_int(screen.tree.get_root().get_child_count()).is_equal(0)
	assert_bool(screen.start_button.disabled).is_true()


func test_a_new_player_is_added_listed_selected_and_saved() -> void:
	var screen := _open()
	var profile := screen.add_player("Ann", 0)
	assert_object(profile).is_not_null()
	assert_int(screen.tree.get_root().get_child_count()).is_equal(1)
	assert_object(screen.selected_profile()).is_same(profile)
	assert_bool(screen.start_button.disabled).is_false()
	assert_bool(FileAccess.file_exists(ROSTER)).is_true()


func test_the_list_is_sorted_and_shows_game_and_sector() -> void:
	var screen := _open()
	screen.add_player("Zed", 1)
	screen.add_player("Amy", 0)
	var first := screen.tree.get_root().get_first_child()
	assert_str(first.get_text(0)).is_equal("Amy")
	assert_str(first.get_text(1)).is_equal("Voyager")
	assert_str(first.get_text(3)).is_equal("1 of 15")
	assert_str(first.get_next().get_text(1)).is_equal("Expert")


func test_start_hands_the_player_to_the_game_through_the_router() -> void:
	var screen := _open()
	var profile := _add_quiet(screen, "Ann")
	await screen.request_start()
	assert_object(GameState.profile).is_same(profile)
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.GAME)


func test_remove_asks_with_the_original_strings_and_then_erases_the_name() -> void:
	var screen := _open()
	screen.add_player("Ann", 0)
	screen.add_player("Bea", 0)
	screen.select(SaveStore.find("Ann"))
	screen.request_remove()
	assert_bool(screen.messages.is_open()).is_true()
	var strings := Catalog.texts("ui_strings")
	assert_str(screen.messages.current.title).is_equal("Remove A Player's Name")           # string 11188
	assert_str(screen.messages.current.title).is_equal(strings.text(11188))
	assert_str(screen.messages.current.body).is_equal(
			"When you remove a name\nfrom the Sign-In list, that\nname is erased permanently.\n\nAre you sure you want to\nremove Ann  from the list?")
	assert_array(Array(screen.messages.current.buttons)).is_equal(["Yes", "No"])
	screen.messages.close_current(1)                                          # No
	assert_int(SaveStore.players.size()).is_equal(2)
	screen.request_remove()
	screen.messages.close_current(0)                                          # Yes
	await await_idle_frame()
	assert_int(SaveStore.players.size()).is_equal(1)
	assert_str(SaveStore.players[0].name).is_equal("Bea")


func test_ctrl_r_asks_to_remove_the_selected_name() -> void:
	var runner := scene_runner(SCENE)
	var screen := runner.scene() as SignIn
	screen.add_player("Ann", 0)
	runner.simulate_key_pressed(KEY_R, false, true)                           # (shift, ctrl)
	await await_idle_frame()
	assert_bool(screen.messages.is_open()).is_true()
	assert_str(screen.messages.current.title).is_equal("Remove A Player's Name")
	assert_str(screen.messages.current.body).contains("remove Ann")
	screen.messages.close_current(0)                                          # Yes
	await await_idle_frame()
	assert_int(SaveStore.players.size()).is_equal(0)


## Deliberate deviation: the original ignores Delete (0x12e); the port also removes with it.
func test_the_delete_key_also_asks_to_remove_the_selected_name_deliberate_deviation() -> void:
	var runner := scene_runner(SCENE)
	var screen := runner.scene() as SignIn
	screen.add_player("Ann", 0)
	runner.simulate_key_pressed(KEY_DELETE)
	await await_idle_frame()
	assert_bool(screen.messages.is_open()).is_true()
	assert_str(screen.messages.current.title).is_equal("Remove A Player's Name")
	assert_str(screen.messages.current.body).contains("remove Ann")
	screen.messages.close_current(0)                                          # Yes
	await await_idle_frame()
	assert_int(SaveStore.players.size()).is_equal(0)


func test_a_plain_r_removes_nothing() -> void:
	var runner := scene_runner(SCENE)
	var screen := runner.scene() as SignIn
	screen.add_player("Ann", 0)
	runner.simulate_key_pressed(KEY_R)                                        # a letter R is no command either
	await await_idle_frame()
	assert_bool(screen.messages.is_open()).is_false()
	assert_int(SaveStore.players.size()).is_equal(1)


func test_a_full_list_must_lose_a_name_first() -> void:
	for i in SaveStore.MAX_PLAYERS:
		SaveStore.players.append(PlayerProfile.new_player("P%d" % i, 0))
	var screen := _open()
	await screen.request_new_player()
	assert_bool(screen.messages.is_open()).is_true()
	assert_str(screen.messages.current.body).contains("remove a name")
	assert_str(screen.messages.current.body).contains("press Ctrl+R.")                 # (the original's key glyph \x06)
	assert_int(screen.overlay.get_child_count()).is_equal(0)                  # no dialog opened


func test_the_new_player_dialog_limits_the_name_to_eight_characters() -> void:
	var screen := _open()
	await screen.request_new_player()
	var dialog := screen.overlay.get_child(0) as NewPlayerDialog
	assert_int(dialog.name_edit.max_length).is_equal(8)
	dialog.name_edit.text = "Christopher"
	assert_str(dialog.name_edit.text).is_equal("Christop")                      # the LineEdit itself cuts at eight
	dialog.name_edit.text_submitted.emit("Christopher")
	var chosen := []
	dialog.confirmed.connect(func(n: String, id: StringName) -> void: chosen.append([n, id]))
	dialog.expert_button.pressed.emit()
	assert_array(chosen).is_equal([["Christop", &"expert"]])


func test_the_new_player_dialog_makes_the_first_letter_upper_case_and_refuses_a_leading_blank() -> void:
	var screen := _open()
	await screen.request_new_player()
	var dialog := screen.overlay.get_child(0) as NewPlayerDialog
	dialog.name_edit.text = "  ann"
	dialog.name_edit.text_changed.emit(dialog.name_edit.text)                    # (typing emits it; setting `text` does not)
	assert_str(dialog.name_edit.text).is_equal("Ann")
	dialog.name_edit.text_submitted.emit("")                                     # Enter on an empty name does nothing
	assert_bool(dialog.name_panel.visible).is_true()
	dialog.name_edit.text_submitted.emit("Ann")
	assert_bool(dialog.game_panel.visible).is_true()


func test_a_name_that_is_already_there_is_accepted_like_in_the_original() -> void:
	var screen := _open()
	var first := _add_quiet(screen, "Ann")
	await screen.request_new_player()
	var dialog := screen.overlay.get_child(0) as NewPlayerDialog
	dialog.name_edit.text_submitted.emit("Ann")
	dialog.voyager_button.pressed.emit()
	assert_int(SaveStore.players.size()).is_equal(2)
	assert_object(SaveStore.players[0]).is_same(first)
	assert_bool(screen.messages.is_open()).is_false()


func test_a_failed_save_shows_the_write_error_dialog_and_keeps_the_player() -> void:
	var screen := _open()
	SaveStore.roster_path = "user://no_such_folder/roster.json"                  # (`after_test` puts the real path back)
	var profile := screen.add_player("Ann", 0)
	assert_object(profile).is_not_null()
	assert_bool(screen.messages.is_open()).is_true()
	assert_str(screen.messages.current.title).is_equal("Write Error")             # string 11018
	assert_str(screen.messages.current.body).contains("Writing to the disk has failed")
	assert_array(screen.messages.current.buttons).is_equal(PackedStringArray(["OK"]))
	screen.messages.close_current(0)                                             # OK: nothing else happens
	assert_bool(screen.messages.is_open()).is_false()
	assert_array(SaveStore.players).contains_exactly([profile])


func test_a_player_at_the_finale_is_marked_final_and_can_start() -> void:
	var screen := _open()
	var profile := _add_quiet(screen, "Ann")
	profile.progress = Progression.VOYAGER_FINALE
	screen.refresh()
	var row := screen.tree.get_selected()
	assert_str(row.get_text(2)).is_equal("Final")
	assert_str(row.get_text(3)).is_equal("Final")
	await screen.request_start()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.GAME)         # the finale sector is played, not skipped


# --- the security scan (original AnimateSecurityScan (0x42fca0)) -----------------------------------------------

func test_the_scan_is_24_pictures_of_5_ticks_on_two_discrete_tracks() -> void:
	var screen := _open()
	var scan := screen.scan_animation.get_animation(&"scan")
	assert_int(scan.get_track_count()).is_equal(2)
	assert_float(scan.length).is_equal_approx(24 * 5 / 73.0, 0.0001)             # about 1.644 s
	for track in 2:
		assert_int(scan.value_track_get_update_mode(track)).is_equal(Animation.UPDATE_DISCRETE)
		assert_int(scan.track_get_key_count(track)).is_equal(25)                 # 24 pictures + the all-green one
	# the left strip runs 0 1 2 3, the right strip 3 2 1 0, six times; both end on picture 4 (all green)
	for step in 24:
		assert_object(scan.track_get_key_value(0, step)).is_same(SignIn.scan_pictures()[step % 4])
		assert_object(scan.track_get_key_value(1, step)).is_same(SignIn.scan_pictures()[3 - step % 4])
		assert_float(scan.track_get_key_time(0, step)).is_equal_approx(step * 5 / 73.0, 0.0001)
	assert_object(scan.track_get_key_value(0, 24)).is_same(SignIn.scan_pictures()[4])
	assert_object(scan.track_get_key_value(1, 24)).is_same(SignIn.scan_pictures()[4])


func test_the_lights_rest_all_green_and_the_animation_moves_the_red_one() -> void:
	var screen := _open()
	assert_object(screen.left_lights.texture).is_same(SignIn.scan_pictures()[4])
	screen.scan_animation.play(&"scan")
	screen.scan_animation.seek(1.5 * 5 / 73.0, true)                             # during picture 1
	assert_object(screen.left_lights.texture).is_same(SignIn.scan_pictures()[1])
	assert_object(screen.right_lights.texture).is_same(SignIn.scan_pictures()[2])
	screen.scan_animation.seek(4.5 * 5 / 73.0, true)                             # the second sweep begins at picture 0
	assert_object(screen.left_lights.texture).is_same(SignIn.scan_pictures()[0])
	assert_object(screen.right_lights.texture).is_same(SignIn.scan_pictures()[3])
	screen.scan_animation.stop()


func test_start_scans_with_the_scanner_sound_before_the_clearance_speech() -> void:
	var probe := AudioProbe.new()
	var screen := _open()
	_add_quiet(screen, "Ann")
	var started := Time.get_ticks_msec()
	await screen.request_start()
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	probe.stop()
	assert_array(probe.sfx).is_equal([&"scanner"])                                     # "scanner"
	assert_int(Catalog.sfx_catalog().id_of(&"scanner")).is_equal(0x1d)
	assert_int(probe.voice.size()).is_equal(1)                                   # the speech follows the scan
	assert_float(seconds).is_between(18 / 73.0 + 24 * 5 / 73.0 - 0.1, 18 / 73.0 + 24 * 5 / 73.0 + 0.6)
	assert_object(screen.left_lights.texture).is_same(SignIn.scan_pictures()[4])   # back to all green
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.GAME)
	Audio.stop_voice()


func test_enter_shortens_the_scan() -> void:
	var runner := scene_runner(SCENE)
	var screen := runner.scene() as SignIn
	_add_quiet(screen, "Ann")
	var finished_at := [-1]
	screen.scan_finished.connect(func() -> void: finished_at[0] = Time.get_ticks_msec())
	screen.request_start()
	await await_millis(18 * 1000 / 73 + 200)                                     # the scan is running
	assert_bool(screen.scan_animation.is_playing()).is_true()
	var pressed_at := Time.get_ticks_msec()
	runner.simulate_key_pressed(KEY_ENTER)
	await await_millis(700)
	assert_int(finished_at[0]).is_greater(0)                                     # over long before its 1.6 s ...
	assert_int(finished_at[0] - pressed_at).is_between(150, 550)                 # ... but not at once: one picture per sweep is left
	assert_object(screen.left_lights.texture).is_same(SignIn.scan_pictures()[4])
	await await_millis(100)
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.GAME)
	Audio.stop_voice()


func test_practice_opens_the_practice_scene() -> void:
	var screen := _open()
	screen.request_practice()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.PRACTICE)


# --- the speech is synchronous (original SignInSpeech (0x42fe4d)) -----------------------------------------------

func test_the_welcome_speech_holds_the_list_until_a_key_cuts_it_and_the_key_goes_on() -> void:
	SignIn.welcome_enabled = true
	var runner := scene_runner(SCENE)
	var screen := runner.scene() as SignIn
	var profile := screen.add_player("Ann", 0)
	await await_idle_frame()
	assert_bool(Audio.is_voice_playing()).is_true()                              # "This is a highly classified mission ..."
	screen.request_start()                                                       # the list is not usable meanwhile
	assert_object(GameState.profile).is_null()
	assert_bool(screen.scan_animation.is_playing()).is_false()
	runner.simulate_key_pressed(KEY_INSERT)                                      # ANY key cuts both clips ...
	await await_millis(300)
	assert_bool(Audio.is_voice_playing()).is_false()
	assert_bool(screen.looks_pressed(screen.new_button)).is_true()               # ... and then does what it means: Insert = New
	assert_object(profile).is_not_null()
	Audio.stop_voice()


func test_the_welcome_speech_ends_by_itself_and_frees_the_list() -> void:
	SignIn.welcome_enabled = true
	var screen := _open()
	var finished := [false]
	Audio.voice_finished.connect(func() -> void: finished[0] = true, CONNECT_ONE_SHOT)
	var started := Time.get_ticks_msec()
	while not finished[0] and Time.get_ticks_msec() - started < 20000:
		await await_idle_frame()
	assert_bool(finished[0]).is_true()
	assert_int(Time.get_ticks_msec() - started).is_greater(1000)                 # two real clips, not a flash
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(screen._busy).is_false()


func test_the_welcome_speech_is_not_waited_for_with_the_voice_off() -> void:
	SignIn.welcome_enabled = true
	var screen := _open()
	# the screen starts with every sound on (nobody is signed in), so the voice IS on here: the clips play
	assert_bool(Audio.is_voice_playing()).is_true()
	Audio.set_bus_enabled(AudioService.VOICE, false)                             # switching the voice off silences it at once
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(screen._busy).is_false()


func test_the_welcome_speech_is_spoken_on_every_entry_to_the_screen() -> void:
	SignIn.welcome_enabled = true
	var first := scene_runner(SCENE)                                             # the first sign-in of the run
	await await_idle_frame()
	assert_bool(Audio.is_voice_playing()).is_true()
	Audio.stop_voice()
	first = null
	var second := scene_runner(SCENE)                                            # a Return to Sign-In / a finished game: `sign_in` again
	await await_idle_frame()
	assert_bool(Audio.is_voice_playing()).is_true()                              # G36: `SignInWelcomePending` is set on every call
	Audio.stop_voice()
	assert_bool(second.scene() is SignIn).is_true()


func test_the_welcome_speech_is_not_repeated_when_math_practice_returns() -> void:
	SignIn.welcome_enabled = true
	var first := scene_runner(SCENE)
	await await_idle_frame()
	var screen := first.scene() as SignIn
	Audio.stop_voice()
	screen._listening = SignIn.Listening.NOTHING
	screen._busy = false
	screen.request_practice()                                                    # (dry run: the scene is not left)
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.PRACTICE)
	assert_bool(SignIn.returning_from_practice).is_true()
	var back := scene_runner(SCENE)                                              # the practice screen goes back to sign-in
	await await_idle_frame()
	assert_bool(Audio.is_voice_playing()).is_false()                             # the original returns into the same loop iteration
	assert_bool(SignIn.returning_from_practice).is_false()                       # the flag is for ONE entry
	assert_bool((back.scene() as SignIn)._busy).is_false()
	var later := scene_runner(SCENE)                                             # the next entry speaks again
	await await_idle_frame()
	assert_bool(Audio.is_voice_playing()).is_true()
	Audio.stop_voice()
	assert_bool(later.scene() is SignIn).is_true()


func test_start_waits_for_the_clearance_speech_and_escape_cuts_it() -> void:
	var runner := scene_runner(SCENE)
	var screen := runner.scene() as SignIn
	screen.add_player("Ann", 0)                                                  # (Voice option on)
	screen.request_start()
	await await_millis(int((18 + 24 * 5) * 1000.0 / 73.0) + 500)                 # the scan is over
	assert_bool(Audio.is_voice_playing()).is_true()                              # the clearance clip
	assert_str(SceneRouter.last_path).is_empty()                                 # the game does not start yet
	runner.simulate_key_pressed(KEY_A)                                           # any other key is swallowed
	await await_millis(100)
	assert_bool(Audio.is_voice_playing()).is_true()
	assert_str(SceneRouter.last_path).is_empty()
	runner.simulate_key_pressed(KEY_ESCAPE)
	await await_millis(200)
	assert_bool(Audio.is_voice_playing()).is_false()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.GAME)


func test_start_enters_the_game_only_after_begin_mission_has_ended() -> void:
	var screen := _open()
	screen.add_player("Ann", 0)
	var started := Time.get_ticks_msec()
	screen.request_start()
	var scan_seconds := (18 + 24 * 5) / 73.0
	while SceneRouter.last_path.is_empty() and Time.get_ticks_msec() - started < 30000:
		await await_idle_frame()
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.GAME)
	assert_float(seconds).is_greater(scan_seconds + 1.0)                         # the two clips took a while


func test_enter_during_the_scan_ends_it_and_skips_the_speech() -> void:
	var probe := AudioProbe.new()
	var runner := scene_runner(SCENE)
	var screen := runner.scene() as SignIn
	screen.add_player("Ann", 0)
	screen.request_start()
	await await_millis(int(18 * 1000.0 / 73.0) + 200)
	assert_bool(screen.scan_animation.is_playing()).is_true()
	runner.simulate_key_pressed(KEY_ENTER)                                       # the key stays pending: the clips are cut at once
	await await_millis(800)
	probe.stop()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.GAME)
	assert_bool(Audio.is_voice_playing()).is_false()
	assert_array(probe.voice).is_empty()


func test_escape_during_the_scan_does_not_end_it_but_skips_the_speech() -> void:
	var runner := scene_runner(SCENE)
	var screen := runner.scene() as SignIn
	screen.add_player("Ann", 0)
	screen.request_start()
	await await_millis(int(18 * 1000.0 / 73.0) + 200)
	runner.simulate_key_pressed(KEY_ESCAPE)
	await await_millis(300)
	assert_bool(screen.scan_animation.is_playing()).is_true()                    # only Enter (or a click) ends the scan
	assert_str(SceneRouter.last_path).is_empty()
	while screen.scan_animation.is_playing():
		await await_idle_frame()
	await await_millis(200)
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.GAME)                 # no speech to wait for
	assert_bool(Audio.is_voice_playing()).is_false()


func test_start_applies_the_players_voice_option_before_the_speech() -> void:
	var screen := _open()
	var profile := _add_quiet(screen, "Ann")                                     # Voice: off
	await screen.request_start()
	assert_bool(Audio.is_bus_enabled(AudioService.VOICE)).is_false()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.GAME)
	assert_object(profile).is_not_null()


func test_a_skipped_scan_shows_one_picture_for_each_sweep_that_is_left() -> void:
	# AnimateSecurityScan: with Enter pending the inner loop (4 pictures) ends after the picture that shows, the outer loop
	# still runs the other sweeps, each with picture 0 only (5 ticks)
	var picture := 5 / 73.0
	assert_float(SignIn.seconds_left_after_skip(0.0)).is_equal_approx(picture + 5 * picture, 0.0001)      # sweep 0, picture 0
	assert_float(SignIn.seconds_left_after_skip(3.5 * picture)).is_equal_approx(0.5 * picture + 5 * picture, 0.0001)
	assert_float(SignIn.seconds_left_after_skip(4.2 * picture)).is_equal_approx(0.8 * picture + 4 * picture, 0.0001)   # sweep 1
	assert_float(SignIn.seconds_left_after_skip(23.5 * picture)).is_equal_approx(0.5 * picture, 0.0001)   # the last picture: nothing else
	var screen := _open()
	screen.scan_animation.play(&"scan")
	screen.scan_animation.seek(4.2 * picture, true)                              # picture 0 of sweep 1
	screen.skip_scan()
	var cut := screen.scan_animation.get_animation(&"scan_cut")
	assert_str(screen.scan_animation.current_animation).is_equal("scan_cut")
	assert_float(cut.length).is_equal_approx(0.8 * picture + 4 * picture, 0.0001)
	assert_int(cut.track_get_key_count(0)).is_equal(1 + 4 + 1)                   # the showing picture, 4 sweeps, all green
	assert_object(cut.track_get_key_value(0, 0)).is_same(SignIn.scan_pictures()[0])
	assert_object(cut.track_get_key_value(1, 0)).is_same(SignIn.scan_pictures()[3])
	for i in range(1, 5):
		assert_object(cut.track_get_key_value(0, i)).is_same(SignIn.scan_pictures()[0])
		assert_object(cut.track_get_key_value(1, i)).is_same(SignIn.scan_pictures()[3])
	assert_object(cut.track_get_key_value(0, 5)).is_same(SignIn.scan_pictures()[4])
	screen.scan_animation.stop()


# --- G24: the letter keys of SignInScreenLoop (0x430c33) --------------------------------------------------------

func test_s_starts_n_adds_m_practises_e_exits_in_both_cases() -> void:
	var runner := scene_runner(SCENE)
	var screen := runner.scene() as SignIn
	screen.quits_program = false
	_add_quiet(screen, "Ann")
	await await_idle_frame()
	runner.simulate_key_pressed(KEY_M)                                           # M / m = Practice
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.PRACTICE)
	SceneRouter.last_path = ""
	runner.simulate_key_pressed(KEY_N)                                           # N / n = New (the button looks pressed 36 ticks first)
	assert_bool(screen.looks_pressed(screen.new_button)).is_true()
	await await_millis(int(36 * 1000.0 / 73.0) + 300)
	assert_int(screen.overlay.get_child_count()).is_equal(1)                     # the name dialog
	(screen.overlay.get_child(0) as NewPlayerDialog).cancelled.emit()
	await await_idle_frame()
	runner.simulate_key_pressed(KEY_E)                                           # E / e = Exit: the question (strings 11191 / 11192)
	await await_idle_frame()
	assert_bool(screen.messages.is_open()).is_true()
	assert_str(screen.messages.current.title).is_equal(Catalog.texts("ui_strings").text(11191))
	screen.messages.close_current(1)
	await await_idle_frame()
	var shift := InputEventKey.new()                                             # a capital "S" is Shift + S: the same key
	shift.keycode = KEY_S
	shift.shift_pressed = true
	shift.pressed = true
	screen.get_viewport().push_input(shift)
	await await_idle_frame()
	assert_object(GameState.profile).is_not_null()                               # S / s = Start
	screen._leaving = true


func test_ctrl_s_is_not_the_letter_s() -> void:
	var runner := scene_runner(SCENE)
	var screen := runner.scene() as SignIn
	_add_quiet(screen, "Ann")
	var event := InputEventKey.new()
	event.keycode = KEY_S
	event.ctrl_pressed = true
	event.pressed = true
	screen.get_viewport().push_input(event)
	await await_idle_frame()
	assert_object(GameState.profile).is_null()


func test_yes_to_the_exit_question_quits_the_program() -> void:
	var screen := _open()
	screen.quits_program = false
	var quit_seen := [0]
	screen.quit_requested.connect(func() -> void: quit_seen[0] += 1)
	screen.ask_to_exit()
	screen.messages.close_current(1)                                             # No
	await await_idle_frame()
	assert_int(quit_seen[0]).is_equal(0)
	screen.ask_to_exit()
	screen.messages.close_current(0)                                             # Yes
	await await_idle_frame()
	assert_int(quit_seen[0]).is_equal(1)


# --- G25: the New player flow (AddNewPlayer 0x430851, SignInRun 0x43136f) -------------------------------------

func test_a_successful_new_starts_the_game_at_once_and_copies_the_current_switches() -> void:
	var screen := _open()                                                        # (the screen switches everything on when it opens)
	Audio.set_bus_enabled(AudioService.VOICE, false)                              # (no speech to wait for) ...
	Audio.set_bus_enabled(AudioService.MUSIC, false)                              # ... and the record copies what is on now
	await screen.request_new_player()
	var dialog := screen.overlay.get_child(0) as NewPlayerDialog
	dialog.name_edit.text_submitted.emit("Ann")
	dialog.voyager_button.pressed.emit()                                         # no Start needed
	assert_int(SaveStore.players.size()).is_equal(1)
	var profile := SaveStore.players[0]
	assert_bool(profile.sound_on).is_true()
	assert_bool(profile.music_on).is_false()
	assert_bool(profile.voice_on).is_false()
	assert_object(GameState.profile).is_same(profile)
	assert_bool(screen.scan_animation.is_playing() or screen._listening != SignIn.Listening.NOTHING or screen._busy).is_true()
	var started := Time.get_ticks_msec()
	while SceneRouter.last_path.is_empty() and Time.get_ticks_msec() - started < 10000:
		await await_idle_frame()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.GAME)
	assert_bool(SignIn.new_player_added).is_true()


func test_escape_in_the_game_level_dialog_cancels_the_whole_new() -> void:
	var runner := scene_runner(SCENE)
	var screen := runner.scene() as SignIn
	await screen.request_new_player()
	var dialog := screen.overlay.get_child(0) as NewPlayerDialog
	dialog.name_edit.text_submitted.emit("Ann")
	assert_bool(dialog.game_panel.visible).is_true()
	runner.simulate_key_pressed(KEY_ESCAPE)
	await await_idle_frame()
	assert_int(screen.overlay.get_child_count()).is_equal(0)                     # not back at the name box
	assert_int(SaveStore.players.size()).is_equal(0)
	assert_bool(SignIn.new_player_added).is_false()
	assert_str(SceneRouter.last_path).is_empty()


func test_with_no_players_the_list_is_never_shown_the_new_dialog_comes_instead() -> void:
	SignIn.prompt_when_empty = true
	var screen := _open()
	screen.quits_program = false
	var quit_seen := [0]
	screen.quit_requested.connect(func() -> void: quit_seen[0] += 1)
	await await_idle_frame()
	assert_int(screen.overlay.get_child_count()).is_equal(1)                     # the name dialog, at once
	assert_bool(screen.start_button.disabled).is_true()
	(screen.overlay.get_child(0) as NewPlayerDialog).cancelled.emit()            # Esc: the exit question (0x2bb7 / 0x2bb8) ...
	await await_idle_frame()
	assert_bool(screen.messages.is_open()).is_true()
	assert_str(screen.messages.current.title).is_equal(Catalog.texts("ui_strings").text(11191))
	screen.messages.close_current(1)                                             # ... No: the New dialogs again
	await await_idle_frame()
	await await_idle_frame()
	assert_int(screen.overlay.get_child_count()).is_equal(1)
	assert_int(quit_seen[0]).is_equal(0)
	(screen.overlay.get_child(0) as NewPlayerDialog).cancelled.emit()
	await await_idle_frame()
	screen.messages.close_current(0)                                             # Yes: quit
	await await_idle_frame()
	assert_int(quit_seen[0]).is_equal(1)
	screen._leaving = true


func test_removing_the_last_player_asks_for_a_new_one() -> void:
	var screen := _open()
	screen.add_player("Ann", 0)
	SignIn.prompt_when_empty = true
	screen.request_remove()
	screen.messages.close_current(0)                                             # Yes
	await await_idle_frame()
	await await_idle_frame()
	assert_int(SaveStore.players.size()).is_equal(0)
	assert_int(screen.overlay.get_child_count()).is_equal(1)                     # `SignInRun`: AddNewPlayer
	screen._leaving = true


# --- G26: Begin / Resume by NewPlayerAdded (sign_in 0x431420) ---------------------------------------------------

func test_begin_or_resume_follows_new_player_added_which_is_never_cleared() -> void:
	var probe := AudioProbe.new()
	var screen := _open()
	var ann := screen.add_player("Ann", 0)                                       # (sets the flag) ...
	SignIn.new_player_added = false                                              # ... an older player, signed in before any New
	ann.progress = Progression.start_progress(0) + 4                            # (progress does not matter either way)
	screen.request_start()
	await await_millis(int((18 + 24 * 5) * 1000.0 / 73.0) + 400)
	assert_array(probe.voice).is_equal([Catalog.voice_cues().sign_in_start(true)])   # "Resume mission"
	Audio.stop_voice()
	screen.queue_free()
	await await_idle_frame()
	# after a New of the run every later Start says "Begin", even for a player who is far into the game
	SignIn.new_player_added = true
	probe.clear()
	SceneRouter.last_path = ""
	var again := _open()
	again.select(SaveStore.find("Ann"))
	again.request_start()
	await await_millis(int((18 + 24 * 5) * 1000.0 / 73.0) + 400)
	assert_array(probe.voice).is_equal([Catalog.voice_cues().sign_in_start(false)])  # "Begin mission"
	probe.stop()
	Audio.stop_voice()
	assert_bool(SignIn.new_player_added).is_true()                               # not cleared by the Start
