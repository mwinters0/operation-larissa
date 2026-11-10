class_name TestSoundPause
extends GdUnitTestSuite
## `pause_sound` (0x414145) and the focus: a modal dialog and a window that loses the focus both call `KillWave` and
## pause the song; the game itself stands still while the window is not active (DoAction's input poll does not return).
## The focus is simulated by sending the notification Godot sends to every node. Only the tests that send it switch
## `WindowFocus` on, and they do not wait: while a test waits, the real desktop may move the test window's focus, and
## with the switch on that pauses the sound like a dialog (a speech clip that never comes back after `resume_sound`).

const CLIP_A := &"sign_in_first_visit_0"
const CLIP_B := &"sign_in_first_visit_1"

var _probe: AudioProbe
var _old_enabled: bool


func before_test() -> void:
	_probe = AudioProbe.new()
	_old_enabled = WindowFocus.enabled
	WindowFocus.enabled = false                                         # (see _hear_focus_notifications)
	Audio.apply_profile(null)
	Audio.stop_voice()
	Audio.stop_sfx()
	Audio.resume_sound_on_activate()
	GameClock.window_active = true
	GameClock.paused = false


func after_test() -> void:
	_probe.stop()
	Audio.stop_voice()
	Audio.stop_sfx()
	Audio.stop_music()
	Audio.resume_sound_on_activate()
	while Audio._sound_pause_level > 0:
		Audio.resume_sound()
	while Audio._music_pause_count > 0:
		Audio.resume_music()
	GameClock.window_active = true
	GameClock.paused = false
	WindowFocus.enabled = _old_enabled


## The focus notifications count from here to the end of the test (off in a script-driven run, see WindowFocus).
func _hear_focus_notifications() -> void:
	WindowFocus.enabled = true


func _song_player() -> AudioStreamPlayer:
	return Audio._music_players[Audio._active_music_player]


func test_pause_sound_cuts_the_effect_and_the_song_stops_moving() -> void:
	Audio.play_music(&"sector_song_1")
	Audio.play_sfx(&"correct")
	assert_bool(Audio.is_wave_playing()).is_true()
	Audio.pause_sound()
	assert_bool(Audio.is_wave_playing()).is_false()                     # KillWave: the effect is gone, not held
	assert_bool(_song_player().stream_paused).is_true()
	Audio.resume_sound()
	assert_bool(Audio.is_wave_playing()).is_false()                     # ... and it does not come back
	assert_bool(_song_player().stream_paused).is_false()


func test_pause_sound_cuts_a_speech_clip_and_the_sequence_goes_on_after_the_resume() -> void:
	Audio.play_voice_sequence([CLIP_A, CLIP_B] as Array[StringName])
	assert_bool(Audio.is_wave_playing()).is_true()
	Audio.pause_sound()
	assert_bool(Audio.is_wave_playing()).is_false()
	assert_bool(Audio.is_voice_playing()).is_true()                     # the sequence is not over: its next clip is due
	await await_millis(200)
	assert_bool(Audio.is_wave_playing()).is_false()                     # ... but nothing sounds while the dialog is open
	Audio.resume_sound()
	assert_bool(Audio.is_wave_playing()).is_true()                      # clip B (clip A was killed, as in the original)


func test_a_sequence_started_during_a_pause_plays() -> void:
	Audio.pause_sound()
	Audio.play_voice_sequence([CLIP_A] as Array[StringName])               # (the audio settings dialog previews a clip)
	assert_bool(Audio.is_wave_playing()).is_true()
	Audio.resume_sound()


func test_pause_levels_nest_and_only_the_first_pauses_the_song() -> void:
	Audio.play_music(&"sector_song_1")
	Audio.pause_sound()
	Audio.pause_sound()
	Audio.resume_sound()
	assert_bool(_song_player().stream_paused).is_true()                 # one level is still open
	Audio.resume_sound()
	assert_bool(_song_player().stream_paused).is_false()


func test_losing_the_focus_pauses_like_a_dialog_and_regaining_it_resumes() -> void:
	_hear_focus_notifications()
	Audio.play_music(&"sector_song_1")
	Audio.play_voice_sequence([CLIP_A] as Array[StringName])
	assert_bool(Audio.is_window_active()).is_true()
	Audio.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_bool(Audio.is_window_active()).is_false()
	assert_bool(Audio.is_wave_playing()).is_false()
	assert_bool(_song_player().stream_paused).is_true()
	Audio.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)              # (the flag 0x440d80: asking twice pauses once)
	Audio.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_bool(Audio.is_window_active()).is_true()
	assert_bool(_song_player().stream_paused).is_false()


func test_a_dialog_inside_a_lost_focus_keeps_the_song_paused_until_both_are_over() -> void:
	_hear_focus_notifications()
	Audio.play_music(&"sector_song_1")
	Audio.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	Audio.pause_sound()                                                 # a dialog opens
	Audio.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_bool(_song_player().stream_paused).is_true()
	Audio.resume_sound()
	assert_bool(_song_player().stream_paused).is_false()


func test_the_game_clock_stands_still_while_the_window_is_not_active() -> void:
	_hear_focus_notifications()
	assert_int(GameClock.advance(1.0)).is_greater(0)
	GameClock.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_bool(GameClock.window_active).is_false()
	assert_bool(GameClock.paused).is_true()
	var before := GameClock.tick_count
	assert_int(GameClock.advance(1.0)).is_equal(0)
	assert_int(GameClock.tick_count).is_equal(before)
	GameClock.paused = false                                            # a new scene starts: the focus is still lost
	assert_bool(GameClock.paused).is_true()
	GameClock.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_bool(GameClock.paused).is_false()
	assert_int(GameClock.advance(1.0)).is_greater(0)                    # no catching up: at most MAX_TICKS_PER_ADVANCE


func test_an_open_menu_is_the_same_as_a_lost_focus() -> void:
	# MainWindowProc: WM_ENTERMENULOOP -> PauseSoundOnDeactivate, WM_EXITMENULOOP -> ResumeSoundOnActivate
	var bar: GameMenuBar = auto_free(preload("res://src/ui/game_menu_bar.tscn").instantiate())
	add_child(bar)
	await await_idle_frame()
	Audio.play_music(&"sector_song_1")
	bar.open_menu(0)
	assert_bool(Audio.is_window_active()).is_false()
	assert_bool(GameClock.paused).is_true()
	assert_bool(_song_player().stream_paused).is_true()
	bar.get_menu_popup(0).hide()
	assert_bool(Audio.is_window_active()).is_true()
	assert_bool(GameClock.paused).is_false()
	assert_bool(_song_player().stream_paused).is_false()


func test_focus_notifications_are_ignored_when_the_switch_is_off() -> void:
	WindowFocus.enabled = false                                         # the default under the test runner
	Audio.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	GameClock.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_bool(Audio.is_window_active()).is_true()
	assert_bool(GameClock.window_active).is_true()


func test_the_switch_is_off_under_the_test_runner_and_on_in_a_normal_run() -> void:
	assert_bool(WindowFocus._default()).is_false()                      # (the main loop here has the runner's script)
