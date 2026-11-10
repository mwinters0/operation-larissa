class_name TestClipLengths
extends GdUnitTestSuite
## Teaches: a clip's length belongs to the pack that holds the clip. A complete pack's lengths are numbers in its data (`VoiceIndex.durations`);
## a pack in the data form's are measured when it is mounted (`AudioStream.get_length()` of its file, rounded UP to ticks of 1/73 s) unless the pack
## states them (`audio/lengths.json`, which also allows a pause after a line). A clip comes back with its stream AND its length from the same
## pack, and the length is a number in the data, so the timing of a trace depends on the pack's files and never on playback: a longer
## narration lengthens a speech by exactly the measured ticks, and every skin plays the game the same. `ClipLengths.warnings` is what G4's
## validation shows. The streams are synthetic tones (tests/fixtures: 0.6 s and 2.5 s of sine, and the short blip of test_packs.gd), never a
## recording of the game.

const SHORT := "res://tests/fixtures/pack_tone_short.ogg.bin"
const LONG := "res://tests/fixtures/pack_tone_long.ogg.bin"
const BLIP := "res://tests/fixtures/pack_blip.ogg.bin"
const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"
const TICK_DELTA := 1.0 / 73.0 + 0.0001           # (a hair more than one tick, so that every call counts exactly one)
const CLIP := &"sign_in_begin_0"
const OTHER_CLIP := &"sign_in_begin_1"

var _shelves: Array[PackShelf] = []


func before_test() -> void:
	Audio.stop_voice()
	GameState.reset()


func after_test() -> void:
	Audio.stop_voice()
	for shelf in _shelves:
		shelf.remove()
	_shelves.clear()
	Packs.start()
	SkinChoice.select(SkinChoice.original())
	GameState.reset()


func _shelf(pack_id: StringName = &"", base: StringName = &"") -> PackShelf:
	var shelf := PackShelf.new(pack_id, base)
	_shelves.append(shelf)
	return shelf


func _bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)


## The length of a fixture as the engine says it, in ticks by the book (a float, rounded up).
func _expected(path: String) -> int:
	return ceili(AudioStreamOggVorbis.load_from_buffer(_bytes(path)).get_length() * 73.0 - 1.0e-6)


## A pack that replaces the base pack's clip `CLIP` with the fixture `path`.
func _narration(path: String, pack_id: StringName = &"narration") -> PackShelf:
	var shelf := _shelf(pack_id)
	shelf.write_bytes("audio/voice/%s.ogg" % CLIP, _bytes(path))
	return shelf


## Feeds `Audio` a tick at a time until the speech is over; returns the ticks it counted. `trace` gets a line for each clip that began.
func _speech(clips: Array[StringName], trace: Array[String] = []) -> int:
	var on_start := func(clip: StringName, _text: String) -> void: trace.append("%s began at tick %d" % [clip, Audio.speech_ticks])
	Audio.voice_started.connect(on_start)
	Audio.play_voice_sequence(clips)
	var calls := 0
	while Audio.is_voice_playing() and calls < 5000:
		Audio._process(TICK_DELTA)
		calls += 1
	Audio.voice_started.disconnect(on_start)
	return Audio.speech_ticks


# --- the arithmetic ---------------------------------------------------------------------------------------------

func test_a_length_is_rounded_up_to_whole_ticks_and_a_float_bit_does_not_add_one() -> void:
	assert_int(ClipLengths.ticks_of_seconds(2.0)).is_equal(146)
	assert_int(ClipLengths.ticks_of_seconds(2.0 + 1.0e-12)).is_equal(146)       # (a whole number of ticks that came out a hair over)
	assert_int(ClipLengths.ticks_of_seconds(0.5)).is_equal(37)                  # 36.5 ticks: the next whole one
	assert_int(ClipLengths.ticks_of_seconds(1.0 / 73.0 + 0.001)).is_equal(2)
	assert_int(ClipLengths.ticks_of_seconds(0.001)).is_equal(1)


func test_a_stream_with_no_length_has_no_measurable_length() -> void:
	assert_int(ClipLengths.measure(null)).is_equal(-1)
	assert_int(ClipLengths.measure(AudioStreamOggVorbis.new())).is_equal(-1)    # (nothing in it: 0 seconds)
	var tone := AudioStreamOggVorbis.load_from_buffer(_bytes(SHORT))
	assert_int(ClipLengths.measure(tone)).is_equal(_expected(SHORT))


func test_far_is_more_than_a_second_or_a_quarter_of_the_clip() -> void:
	assert_bool(ClipLengths.is_far(100, 100)).is_false()
	assert_bool(ClipLengths.is_far(110, 100)).is_false()                         # 10 %
	assert_bool(ClipLengths.is_far(125, 100)).is_false()                         # 25 % exactly
	assert_bool(ClipLengths.is_far(126, 100)).is_true()
	assert_bool(ClipLengths.is_far(75, 100)).is_false()
	assert_bool(ClipLengths.is_far(74, 100)).is_true()
	assert_bool(ClipLengths.is_far(1073, 1000)).is_false()                       # 73 ticks over is exactly a second: not more
	assert_bool(ClipLengths.is_far(1074, 1000)).is_true()                        # (a long clip is held to the second, not to the quarter)
	assert_bool(ClipLengths.is_far(10, 1)).is_true()


# --- the base pack --------------------------------------------------------------------------------------------------------

func test_the_base_packs_clips_keep_the_numbers_of_its_data() -> void:
	var index := Catalog.voice_index()
	var names: Array[StringName] = []
	for id in index.ids:
		names.append(StringName(NameRegistry.original().name_of(&"voice", id)))
	for i in names.size():
		assert_int(index.ticks_named(names[i])).is_equal(index.durations[i])
	var shelf := _shelf(&"elsewhere")                                          # a pack that holds no clip of the base pack's
	shelf.write_bytes("audio/voice/my_own_line.ogg", _bytes(LONG))
	shelf.mount()
	for i in names.size():
		assert_int(index.ticks_named(names[i])).is_equal(index.durations[i])


# --- a pack's own clips -------------------------------------------------------------------------------------------

func test_a_packs_clip_is_measured_when_the_pack_is_mounted() -> void:
	var shelf := _shelf(&"tones")
	shelf.write_bytes("audio/voice/short_line.ogg", _bytes(SHORT))
	shelf.write_bytes("audio/voice/long_line.ogg", _bytes(LONG))
	shelf.write_bytes("audio/sound/chime.ogg", _bytes(SHORT))
	shelf.write_bytes("audio/music/theme.ogg", _bytes(LONG))
	var pack := shelf.mount()
	assert_int(pack.measured_clip_ticks(&"voice", &"short_line")).is_equal(_expected(SHORT))
	assert_int(pack.measured_clip_ticks(&"voice", &"long_line")).is_equal(_expected(LONG))
	assert_int(_expected(SHORT)).is_between(43, 45)                              # (0.6 s is 43.8 ticks)
	assert_int(_expected(LONG)).is_between(182, 184)                             # (2.5 s is 182.5)
	assert_int(Packs.clip(&"voice", &"short_line").ticks).is_equal(_expected(SHORT))
	assert_int(Packs.clip(&"sound", &"chime").ticks).is_equal(_expected(SHORT))  # (no sound or song is waited for, but all are measured)
	assert_int(Packs.clip(&"music", &"theme").ticks).is_equal(_expected(LONG))
	var voices := Catalog.voice_index()
	assert_int(voices.ticks_named(&"short_line")).is_equal(_expected(SHORT))     # a clip only the pack has: its own length, no longer 0
	assert_int(voices.ticks_named(&"long_line")).is_equal(_expected(LONG))
	assert_int(pack.measured_clip_ticks(&"voice", &"nothing")).is_equal(-1)
	assert_int(pack.clip_ticks(&"voice", &"nothing")).is_equal(-1)


func test_the_same_file_always_gives_the_same_number() -> void:
	var shelf := _shelf(&"again")
	shelf.write_bytes("audio/voice/line.ogg", _bytes(LONG))
	var first := shelf.mount().measured_clip_ticks(&"voice", &"line")
	Packs.start()
	assert_int(shelf.mount().measured_clip_ticks(&"voice", &"line")).is_equal(first)
	Packs.refresh()
	assert_int(Packs.clip(&"voice", &"line").ticks).is_equal(first)


func test_a_replaced_clip_lasts_what_the_packs_file_lasts_not_the_base_packs() -> void:
	var original := Catalog.voice_index().ticks_named(CLIP)
	_narration(LONG).mount()
	assert_int(Catalog.voice_index().ticks_named(CLIP)).is_equal(_expected(LONG))
	assert_int(_expected(LONG)).is_not_equal(original)
	Packs.start()
	assert_int(Catalog.voice_index().ticks_named(CLIP)).is_equal(original)       # unmounted: the base pack's again


func test_the_stream_and_the_length_come_from_the_same_pack() -> void:
	var older := _shelf(&"older")
	older.write_bytes("audio/voice/line_a.ogg", _bytes(LONG))
	older.write_bytes("audio/voice/line_b.ogg", _bytes(LONG))
	var newer := _shelf(&"newer", &"older")                                       # laid over the older pack
	newer.write_bytes("audio/voice/line_a.ogg", _bytes(SHORT))
	newer.write_json("audio/lengths.json", {"voice": {"line_a": 100}})
	newer.mount()
	var a := Packs.clip(&"voice", &"line_a")
	assert_str(a.pack_id).is_equal(&"newer")
	assert_int(a.ticks).is_equal(100)                                            # the newer pack's stated number, not the older file's
	assert_float(a.stream.get_length()).is_equal_approx(0.6, 0.1)                # and the newer pack's stream
	var b := Packs.clip(&"voice", &"line_b")
	assert_str(b.pack_id).is_equal(&"older")                                     # (the newer pack says nothing about it)
	assert_int(b.ticks).is_equal(_expected(LONG))


func test_a_pack_may_state_a_length_and_that_wins_over_the_files() -> void:
	var shelf := _narration(SHORT)
	shelf.write_json("audio/lengths.json", {"voice": {String(CLIP): 300}})        # a long pause after a short line
	var pack := shelf.mount()
	assert_int(pack.measured_clip_ticks(&"voice", CLIP)).is_equal(_expected(SHORT))
	assert_int(pack.stated_clip_ticks(&"voice", CLIP)).is_equal(300)
	assert_int(Packs.clip(&"voice", CLIP).ticks).is_equal(300)
	assert_int(Catalog.voice_index().ticks_named(CLIP)).is_equal(300)


# --- the timing of a trace ----------------------------------------------------------------------------------------

func test_a_longer_or_shorter_narration_changes_a_speech_by_exactly_the_measured_ticks() -> void:
	var clips: Array[StringName] = [CLIP, OTHER_CLIP]
	var index := Catalog.voice_index()
	var plain: Array[String] = []
	var base_total := _speech(clips, plain)
	var original := index.ticks_named(CLIP)
	var other := index.ticks_named(OTHER_CLIP)
	assert_int(base_total).is_equal(original + other)
	assert_array(plain).is_equal(["%s began at tick 0" % CLIP, "%s began at tick %d" % [OTHER_CLIP, original]])
	for fixture in [LONG, SHORT]:
		var shelf := _narration(fixture)
		shelf.mount()
		var trace: Array[String] = []
		var total := _speech(clips, trace)
		assert_int(total).is_equal(_expected(fixture) + other)                    # the new clip's measured ticks, the second one untouched
		assert_int(total - base_total).is_equal(_expected(fixture) - original)
		assert_array(trace).is_equal(["%s began at tick 0" % CLIP, "%s began at tick %d" % [OTHER_CLIP, _expected(fixture)]])
		shelf.remove()
	assert_int(_speech(clips)).is_equal(base_total)                               # no pack: the base pack's again


func test_a_stated_pause_after_a_line_is_waited_out_after_the_file_has_ended() -> void:
	var shelf := _narration(SHORT)
	shelf.write_json("audio/lengths.json", {"voice": {String(CLIP): 200}})
	shelf.mount()
	var clips: Array[StringName] = [CLIP]
	assert_int(_speech(clips)).is_equal(200)


func test_a_pack_that_states_a_shorter_length_cuts_the_clip_off() -> void:
	var shelf := _narration(LONG)
	shelf.write_json("audio/lengths.json", {"voice": {String(CLIP): 40}})
	shelf.mount()
	var clips: Array[StringName] = [CLIP]
	assert_int(_speech(clips)).is_equal(40)


func test_a_clip_nothing_can_read_is_not_the_packs_and_the_original_stays() -> void:
	var original := Catalog.voice_index().ticks_named(CLIP)
	var shelf := _shelf(&"broken")
	shelf.write_text("audio/voice/%s.ogg" % CLIP, "not an ogg")
	shelf.mount()
	assert_object(Packs.clip(&"voice", CLIP)).is_null()
	assert_int(Catalog.voice_index().ticks_named(CLIP)).is_equal(original)


func test_the_same_speech_counts_the_same_ticks_whatever_the_device_does() -> void:
	# the ticks are the data's, not the device's: a player that stops at once (no device, a lost focus) changes nothing
	_narration(LONG).mount()
	var clips: Array[StringName] = [CLIP]
	var heard := _speech(clips)
	Audio.play_voice_sequence(clips)
	var calls := 0
	while Audio.is_voice_playing() and calls < 5000:
		Audio._voice_player.stop()
		Audio._process(TICK_DELTA)
		calls += 1
	assert_int(heard).is_equal(_expected(LONG))
	assert_int(Audio.speech_ticks).is_equal(heard)


## The trace of a scripted visit of sector 0 (`SectorScenario`) in plain objects, or in a `SectorWorld` wearing `skin`.
func _play(skin: GameSkin = null) -> SectorScenario:
	GameState.reset()
	if skin == null:
		var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
		run.reset()
		var scenario := SectorScenario.new(HeadlessStage.new(run), run)
		scenario.play(0)
		return scenario
	SkinChoice.select(skin)
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	var scenario := SectorScenario.new(world, GameState)
	scenario.play(0)
	SkinChoice.select(SkinChoice.original())
	return scenario


func test_every_skin_plays_the_same_with_a_pack_that_brings_its_own_narration() -> void:
	var without := _play().trace.lines
	var shelf := _narration(LONG)
	shelf.write_bytes("audio/voice/my_own_line.ogg", _bytes(SHORT))
	shelf.mount()
	var plain := _play().trace.lines
	assert_array(plain).is_equal(without)                                          # a narration is heard, never a rule
	for skin in SkinRoster.all():
		var lines := _play(skin).trace.lines
		assert_int(lines.size()).override_failure_message("skin %s: another number of lines" % skin.id).is_equal(plain.size())
		for i in mini(lines.size(), plain.size()):
			if lines[i] != plain[i]:
				fail("skin %s: the rules differ at line %d\n  plain: %s\n  skin:  %s" % [skin.id, i, plain[i], lines[i]])
				break


# --- validation (G4 calls this) -----------------------------------------------------------------------------------

func test_a_sound_pack_has_no_warnings() -> void:
	var shelf := _narration(SHORT)
	shelf.write_bytes("audio/sound/chime.ogg", _bytes(BLIP))
	shelf.write_json("audio/lengths.json", {"voice": {String(CLIP): _expected(SHORT) + 10}})      # (a small pause)
	var pack := shelf.mount()
	assert_array(pack.clip_warnings()).is_empty()
	assert_array(ClipLengths.warnings(pack)).is_empty()


func test_a_stated_length_far_from_the_file_is_warned_about() -> void:
	var shelf := _narration(LONG)
	shelf.write_bytes("audio/voice/pause_line.ogg", _bytes(SHORT))
	shelf.write_json("audio/lengths.json", {"voice": {String(CLIP): 20, "pause_line": 400}})
	var warnings := shelf.mount().clip_warnings()
	assert_int(warnings.size()).is_equal(2)
	var text := "\n".join(warnings)
	assert_str(text).contains("states 20 ticks").contains("cut off")
	assert_str(text).contains("'pause_line'").contains("silence follows")


func test_a_clip_with_no_measurable_length_is_warned_about() -> void:
	var shelf := _shelf(&"junk")
	shelf.write_text("audio/voice/noise.ogg", "not an ogg")
	shelf.write_bytes("audio/voice/fine.ogg", _bytes(SHORT))
	var warnings := shelf.mount().clip_warnings()
	assert_int(warnings.size()).is_equal(1)
	assert_str(warnings[0]).contains("noise.ogg").contains("no measurable length")


func test_a_lengths_file_that_makes_no_sense_is_warned_about() -> void:
	var shelf := _shelf(&"muddled")
	shelf.write_bytes("audio/voice/fine.ogg", _bytes(SHORT))
	shelf.write_json("audio/lengths.json", {"voice": {"fine": 0, "ghost": 50, "bad": "long"}, "speech": {}, "music": [1]})
	var warnings := shelf.mount().clip_warnings()
	var text := "\n".join(warnings)
	assert_str(text).contains("'fine' must be a whole number")
	assert_str(text).contains("'bad' must be a whole number")
	assert_str(text).contains("'speech' is not a kind of clip")
	assert_str(text).contains("'music' must be an object")
	assert_str(text).contains("'ghost' states a length but the pack has no")
	assert_int(Packs.clip(&"voice", &"fine").ticks).is_equal(_expected(SHORT))    # the bad number is ignored: the measured one stands
	var whole := _shelf(&"not_an_object")
	whole.write_text("audio/lengths.json", "[1, 2]")
	assert_str("\n".join(whole.mount().clip_warnings())).contains("must be a JSON object")
