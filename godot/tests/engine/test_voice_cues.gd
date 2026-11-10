class_name TestVoiceCues
extends GdUnitTestSuite
## Which speech clips go with which event: every cue names clips the pack has, and a run of clips plays one after the other. (The transcripts and texts of
## the original game are checked in tests/legacy/test_voice_cues_legacy.gd.)

var _cues: VoiceCues
var _index: VoiceIndex


func before_test() -> void:
	_cues = Catalog.voice_cues()
	_index = Catalog.voice_index()


func after_test() -> void:
	Audio.stop_voice()
	Audio.set_bus_enabled(AudioService.VOICE, true)


func test_every_cue_names_clips_that_exist() -> void:
	for group: String in _cues.groups:
		for clip in _cues.clips(group):
			assert_object(_index.stream_named(clip)).override_failure_message("%s names clip %s" % [group, clip]).is_not_null()


func test_sequences_play_clip_after_clip() -> void:
	var started: Array[StringName] = []
	var finished := [false]
	Audio.voice_started.connect(func(clip: StringName, _text: String) -> void: started.append(clip))
	Audio.voice_finished.connect(func() -> void: finished[0] = true)
	Audio.play_voice_sequence(_cues.sign_in_start(false))          # `sign_in_begin_0` then `sign_in_begin_1`
	assert_array(started).is_equal([&"sign_in_begin_0"])
	# Wait for the events, not for a fixed time: how fast the clips play out depends on the audio driver (the dummy
	# driver of a --headless run paces itself with a sleep) and on how busy the machine is.
	var deadline := Time.get_ticks_msec() + 10000
	while started.size() < 2 and Time.get_ticks_msec() < deadline:
		await await_idle_frame()
	assert_array(started).is_equal([&"sign_in_begin_0", &"sign_in_begin_1"])                   # the second clip comes after the first ...
	assert_bool(finished[0]).is_false()                              # ... and the sequence is not over yet
	while not finished[0] and Time.get_ticks_msec() < deadline:
		await await_idle_frame()
	assert_bool(finished[0]).is_true()
	assert_bool(Audio.is_voice_playing()).is_false()


func test_stop_voice_cuts_the_speech_off() -> void:
	var finished := [0]
	Audio.voice_finished.connect(func() -> void: finished[0] += 1)
	Audio.play_voice_sequence(_cues.clips("supply_3"))
	assert_bool(Audio.is_voice_playing()).is_true()
	Audio.stop_voice()
	assert_bool(Audio.is_voice_playing()).is_false()
	assert_int(finished[0]).is_equal(1)
	Audio.stop_voice()                                              # a second stop says nothing more
	assert_int(finished[0]).is_equal(1)


func test_a_missing_clip_is_skipped_with_a_warning() -> void:
	var started: Array[StringName] = []
	Audio.voice_started.connect(func(clip: StringName, _text: String) -> void: started.append(clip))
	Audio.play_voice_sequence([&"no_such_clip", &"sign_in_begin_1"] as Array[StringName])
	assert_array(started).is_equal([&"sign_in_begin_1"])
