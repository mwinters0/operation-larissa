class_name TestVoiceCuesLegacy
extends GdUnitTestSuite
## Which speech clips go with which event, checked against the machine transcripts and the game's own texts.

var _cues: VoiceCues
var _index: VoiceIndex


## Without the legacy pack (the original game, made by the importer from your own copy), or without the voice transcripts (an importer run
## with --no-transcripts), this suite skips.
func before(do_skip := not LegacyPack.has_transcripts(), skip_reason := "run the importer with its transcripts step (uv run tools/import/import_all.py --only transcripts,audio)") -> void:
	pass


func before_test() -> void:
	_cues = Catalog.voice_cues()
	_index = Catalog.voice_index()


func after_test() -> void:
	Audio.stop_voice()
	Audio.set_bus_enabled(AudioService.VOICE, true)


func _said(clips: Array[StringName]) -> String:
	var words: PackedStringArray = []
	for clip in clips:
		words.append(_index.transcript_named(clip))
	return " ".join(words)


func test_each_of_the_30_log_entries_has_a_spoken_clip_run() -> void:
	var texts := Catalog.texts("log_entries")
	for n in 30:
		var clips := _cues.clips("log_%d" % n)
		assert_int(clips.size()).is_greater_equal(3)                # "entry", "1.01", then the sentences
		var header: String = texts.text(10648 + n).get_slice(":", 0)         # "ENTRY 1.01"
		var number := header.get_slice(" ", 1)
		assert_str(_index.transcript_named(clips[1])).override_failure_message("log %d says '%s'" % [n, _index.transcript_named(clips[1])]).is_equal(number)


func test_each_of_the_30_supply_messages_has_a_clip_run_in_the_text() -> void:
	var texts := Catalog.texts("supply_messages")
	for sector in 30:
		var text: String = texts.text(10678 + sector % 15 + (15 if sector >= 15 else 0))
		var last_words := _said(_cues.clips("supply_%d" % sector)).to_lower()
		assert_str(last_words).override_failure_message("sector %d: %s" % [sector, last_words]).contains("out")
		assert_bool(text.to_lower().contains("out")).is_true()


func test_spot_checks_against_the_transcripts() -> void:
	assert_str(_said(_cues.clips("supply_0"))).contains("Great progress")
	assert_str(_said(_cues.clips("supply_14"))).contains("final sector")
	assert_str(_said(_cues.clips("log_0"))).contains("landing on asteroid Argos")
	assert_str(_said(_cues.clips("log_29"))).contains("last entry")
	assert_str(_said(_cues.sign_in_first_visit())).contains("classified mission")
	assert_str(_said(_cues.sign_in_start(false))).contains("Begin mission")
	assert_str(_said(_cues.sign_in_start(true))).contains("Resume mission")
	assert_str(_said(_cues.closing_page(0)).to_lower()).contains("congratulations")
	assert_str(_said(_cues.story_page(0))).contains("astronauts")
	assert_str(_said(_cues.story_page(8))).contains("hands")


func test_the_opening_story_covers_clips_4011_to_4029_once() -> void:
	var all: Array = []
	for page in 9:
		all.append_array(Array(_cues.story_page(page)))
	var expected: Array = []
	for id in range(4011, 4030):
		expected.append(StringName(NameRegistry.original().name_of(&"voice", id)))
	assert_array(all).is_equal(expected)
