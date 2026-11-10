class_name TestAudioBuses
extends GdUnitTestSuite
## The audio buses (Master > Music, SFX, Voice): names, switches, volumes and the saved settings.

const SCRATCH := "user://test_audio_settings.cfg"

var _old_path: String
var _old_set: int


func before_test() -> void:
	_old_path = Audio.settings_path
	_old_set = Audio.sound_set
	Audio.settings_path = SCRATCH


func after_test() -> void:
	Audio.settings_path = _old_path
	Audio.sound_set = _old_set
	for bus in AudioService.BUSES:
		Audio.set_bus_enabled(bus, true)
		Audio.set_bus_volume(bus, AudioService.DEFAULT_VOLUMES[bus])
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(SCRATCH)


func test_the_bus_layout_has_music_sfx_and_voice_under_master() -> void:
	for bus in [AudioService.MUSIC, AudioService.SFX, AudioService.VOICE]:
		var index := AudioServer.get_bus_index(bus)
		assert_int(index).is_greater(0)
		assert_str(String(AudioServer.get_bus_send(index))).is_equal("Master")
	assert_int(AudioServer.get_bus_index(&"Master")).is_equal(0)


func test_every_player_of_the_service_uses_one_of_the_buses() -> void:
	var seen := {}
	for child in Audio.get_children():
		if child is AudioStreamPlayer:
			seen[String((child as AudioStreamPlayer).bus)] = true
	assert_array(seen.keys()).contains_exactly_in_any_order(["Music", "SFX", "Voice"])


func test_set_bus_enabled_mutes_the_bus() -> void:
	for bus in [AudioService.MUSIC, AudioService.SFX, AudioService.VOICE]:
		assert_bool(Audio.is_bus_enabled(bus)).is_true()
		Audio.set_bus_enabled(bus, false)
		assert_bool(AudioServer.is_bus_mute(AudioServer.get_bus_index(bus))).is_true()
		assert_bool(Audio.is_bus_enabled(bus)).is_false()
		Audio.set_bus_enabled(bus, true)
		assert_bool(Audio.is_bus_enabled(bus)).is_true()


func test_switching_the_voice_bus_off_silences_the_speech() -> void:
	Audio.play_voice_sequence([&"sign_in_begin_1", &"sign_in_resume_1"] as Array[StringName])
	assert_bool(Audio.is_voice_playing()).is_true()
	Audio.set_bus_enabled(AudioService.VOICE, false)
	assert_bool(Audio.is_voice_playing()).is_false()
	Audio.play_voice(&"sign_in_begin_1")                                       # asked again while off: nothing starts
	assert_bool(Audio.is_voice_playing()).is_false()


## `speak` with the Voice on and a list whose clips have no stream: nothing starts and `voice_finished` comes before `speak` can await it,
## so it has to wait like the silent path (a story page paced by it must not hang).
func test_speak_with_no_clip_that_can_be_played_waits_like_the_silent_path() -> void:
	var result := [-1]
	var run := func() -> void: result[0] = await Audio.speak([&"no_such_clip_a", &"no_such_clip_b"] as Array[StringName], 3)
	run.call()
	assert_int(result[0]).is_equal(-1)                                          # (not at once: the silent wait)
	await await_millis(400)
	assert_int(result[0]).is_equal(3)
	assert_bool(Audio.is_voice_playing()).is_false()


func test_volumes_are_linear_and_clamped() -> void:
	Audio.set_bus_volume(AudioService.MUSIC, 0.5)
	assert_float(Audio.get_bus_volume(AudioService.MUSIC)).is_equal_approx(0.5, 0.001)
	assert_float(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music"))).is_equal_approx(-6.02, 0.05)
	Audio.set_bus_volume(AudioService.MUSIC, 7.0)
	assert_float(Audio.get_bus_volume(AudioService.MUSIC)).is_equal_approx(1.0, 0.001)


func test_apply_profile_sets_the_three_switches_from_the_player() -> void:
	var profile := PlayerProfile.new_player("Audio", 0)
	profile.sound_on = false
	profile.music_on = true
	profile.voice_on = false
	Audio.apply_profile(profile)
	assert_bool(Audio.is_bus_enabled(AudioService.SFX)).is_false()
	assert_bool(Audio.is_bus_enabled(AudioService.MUSIC)).is_true()
	assert_bool(Audio.is_bus_enabled(AudioService.VOICE)).is_false()
	Audio.apply_profile(null)                                   # nobody signed in: everything on
	for bus in [AudioService.MUSIC, AudioService.SFX, AudioService.VOICE]:
		assert_bool(Audio.is_bus_enabled(bus)).is_true()


func test_settings_survive_a_save_and_a_load() -> void:
	Audio.set_bus_volume(AudioService.MUSIC, 0.25)
	Audio.set_bus_volume(AudioService.VOICE, 0.75)
	Audio.sound_set = MusicCatalog.SoundSet.ADLIB
	assert_int(Audio.save_settings()).is_equal(OK)
	Audio.set_bus_volume(AudioService.MUSIC, 1.0)
	Audio.set_bus_volume(AudioService.VOICE, 1.0)
	Audio.sound_set = MusicCatalog.SoundSet.GENERAL_MIDI
	Audio.load_settings()
	assert_float(Audio.get_bus_volume(AudioService.MUSIC)).is_equal_approx(0.25, 0.001)
	assert_float(Audio.get_bus_volume(AudioService.VOICE)).is_equal_approx(0.75, 0.001)
	assert_int(Audio.sound_set).is_equal(MusicCatalog.SoundSet.ADLIB)


func test_a_missing_or_damaged_settings_file_gives_the_defaults() -> void:
	Audio.set_bus_volume(AudioService.MUSIC, 0.1)
	Audio.load_settings()                                       # no file at the scratch path
	assert_float(Audio.get_bus_volume(AudioService.MUSIC)).is_equal_approx(AudioService.DEFAULT_VOLUMES[AudioService.MUSIC], 0.001)
	var file := FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_string("[volume]\nMusic = \"loud\"\n[music]\nsound_set = 99\n(garbage")
	file.close()
	Audio.load_settings()
	assert_float(Audio.get_bus_volume(AudioService.MUSIC)).is_equal_approx(AudioService.DEFAULT_VOLUMES[AudioService.MUSIC], 0.001)
	assert_int(Audio.sound_set).is_equal(MusicCatalog.SoundSet.GENERAL_MIDI)
