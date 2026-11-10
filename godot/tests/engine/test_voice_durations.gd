class_name TestVoiceDurations
extends GdUnitTestSuite
## Teaches: a step that waits for speech lasts as long as the ORIGINAL clip did (and "skins don't change the game"). The importer
## measures every clip (`VoiceIndex.durations`, whole ticks of 1/73 s); `Audio` counts those ticks while the clip sounds and ends the
## speech when they are over, whatever the stream does, so a re-recorded or translated clip changes what is heard and nothing else.
## The tests below feed `Audio` time by hand, a tick at a time, instead of waiting for a loudspeaker.

const TICK_DELTA := 1.0 / 73.0 + 0.0001           # (a hair more than one tick, so that every call counts exactly one)
const CLIP := &"sign_in_begin_0"
const OTHER_CLIP := &"sign_in_begin_1"

var _finished := 0


func before_test() -> void:
	_finished = 0
	Audio.stop_voice()
	Audio.voice_finished.connect(_on_finished)
	GameState.reset()


func after_test() -> void:
	Audio.voice_finished.disconnect(_on_finished)
	Audio.stop_voice()


func _on_finished() -> void:
	_finished += 1


## Feeds `Audio` a tick at a time until the speech is over; returns how many ticks of speech it counted (at most `limit` calls).
func _ticks_until_over(limit: int = 2000) -> int:
	var calls := 0
	while Audio.is_voice_playing() and calls < limit:
		Audio._process(TICK_DELTA)
		calls += 1
	return Audio.speech_ticks


func test_every_clip_has_the_length_its_wav_has_in_ticks() -> void:
	var index := Catalog.voice_index()
	assert_int(index.durations.size()).is_equal(index.ids.size())
	for i in index.ids.size():
		var stream := index.stream(index.ids[i])
		assert_int(index.durations[i]).is_greater(0)
		# (the importer's number is exact integer arithmetic on the WAV; Godot's `get_length` is a float, hence the one tick of room)
		assert_int(absi(index.durations[i] - ceili(stream.get_length() * TickMeter.TICKS_PER_SECOND))).override_failure_message("clip %d" % index.ids[i]).is_less_equal(1)


func test_the_length_of_a_run_of_clips_is_the_sum() -> void:
	var index := Catalog.voice_index()
	var clips: Array[StringName] = [CLIP, OTHER_CLIP]
	assert_int(index.ticks_of(clips)).is_equal(index.ticks_named(CLIP) + index.ticks_named(OTHER_CLIP))
	assert_int(index.ticks_named(&"no_such_clip")).is_equal(0)


func test_a_speech_ends_after_the_recorded_ticks_of_its_clips() -> void:
	var clips: Array[StringName] = [CLIP, OTHER_CLIP]
	Audio.play_voice_sequence(clips)
	assert_bool(Audio.is_voice_playing()).is_true()
	assert_int(_ticks_until_over()).is_equal(Catalog.voice_index().ticks_of(clips))
	assert_int(_finished).is_equal(1)


func test_a_replaced_clip_cannot_change_how_long_the_speech_lasts() -> void:
	var index := Catalog.voice_index()
	var clips: Array[StringName] = [CLIP]
	var expected := index.ticks_named(CLIP)
	var slot := index.ids.find(NameRegistry.original().index_of(&"voice", String(CLIP)))
	var original_path := index.paths[slot]
	var durations := Array(index.durations)
	var longest := durations.find(durations.max())
	var shortest := durations.find(durations.min())
	assert_int(index.durations[longest]).is_greater(expected)
	assert_int(index.durations[shortest]).is_less(expected)
	# A much longer recording, then a much shorter one, in the place of the clip: the speech lasts as long as the recorded one.
	for replacement in [longest, shortest]:
		index.paths[slot] = index.paths[replacement]
		Audio.play_voice_sequence(clips)
		assert_int(_ticks_until_over()).is_equal(expected)
	index.paths[slot] = original_path


func test_a_clip_that_is_held_by_a_dialog_is_not_counted() -> void:
	var clips: Array[StringName] = [CLIP]
	Audio.play_voice_sequence(clips)
	Audio._process(TICK_DELTA * 5)
	Audio.pause_sound()                                            # a dialog: the clip is cut, the speech waits for the resume
	var before := Audio.speech_ticks
	for t in 20:
		Audio._process(TICK_DELTA)
	assert_int(Audio.speech_ticks).is_equal(before)
	assert_bool(Audio.is_voice_playing()).is_true()
	Audio.resume_sound()
	Audio.stop_voice()


func test_with_the_voice_off_speak_waits_a_fixed_number_of_ticks() -> void:
	assert_int(Audio.silent_speech_ticks()).is_equal(146)          # 2 s, as the story pages always waited (data: speech.silent_ticks)
	assert_float(TickMeter.seconds(Audio.silent_speech_ticks())).is_equal(2.0)


func test_the_news_cartoon_pauses_are_the_ticks_of_the_packs_durations() -> void:
	# The pack's `rules/durations.json` lies over the base file key by key; the cartoon counts what it says (ticks of 1/73 s, never a clip's own length).
	var news: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Packs.path("rules/durations.json")))["news"]
	assert_int(NewsCartoon.speech_start_delay_ticks()).is_equal(int(news["speech_start_delay_ticks"]))
	var pauses: Array[int] = []
	for group in NewsCartoon.speech_groups():
		pauses.append(int(group[0]))
	var expected: Array[int] = []
	for pause: Variant in news["group_pauses"]:
		expected.append(int(pause))
	assert_array(pauses).is_equal(expected)
