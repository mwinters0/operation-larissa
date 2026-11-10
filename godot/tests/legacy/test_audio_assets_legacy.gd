class_name TestAudioAssetsLegacy
extends GdUnitTestSuite
## The original game's audio as the importer made it: how many effects, clips and songs there are, how long they are, and which effect has which
## number. (What every pack must keep, whatever it sounds like, is in tests/engine/test_audio_assets.gd.)


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_music_tracks_are_long_enough_in_both_sets() -> void:
	var catalog := Catalog.music_catalog()
	assert_int(catalog.ids.size()).is_equal(10)
	for paths: PackedStringArray in [catalog.gm_paths, catalog.adlib_paths]:
		for path in paths:
			var stream := Packs.file_at(path) as AudioStreamOggVorbis
			assert_object(stream).override_failure_message("cannot load " + path).is_not_null()
			assert_float(stream.get_length()).override_failure_message(path).is_greater(20.0)


func test_sfx_catalog() -> void:
	var catalog := Catalog.sfx_catalog()
	assert_int(catalog.streams.size()).is_equal(52)
	assert_object(catalog.stream_named(&"correct")).is_not_null()
	assert_object(catalog.stream(0x21)).is_not_null()


func test_the_named_effects_are_the_decompiled_ones() -> void:
	var catalog := Catalog.sfx_catalog()
	var expected := {"begin": 0x16, "ink_fired": 0x18, "creature_hit": 0x1A, "piece_pickup": 0x1B, "no_pellets": 0x1E,
			"correct": 0x20, "wrong": 0x21, "lock_tick": 0x26, "lock_settle": 0x27, "message_light": 0x2F, "station_door": 0x17}
	for effect_name: String in expected:
		assert_int(catalog.id_of(StringName(effect_name))).override_failure_message(effect_name).is_equal(expected[effect_name])
	assert_str(catalog.name_of(0x20)).is_equal("correct")
	assert_str(catalog.name_of(0x00)).is_equal("eel_lash")
	assert_str(catalog.name_of(0x1C)).is_equal("sfx_28")                  # nobody named this one yet


func test_voice_index() -> void:
	var index := Catalog.voice_index()
	assert_int(index.ids.size()).is_equal(371)
	assert_object(index.stream(4000)).is_not_null()


func test_clips_have_plausible_lengths() -> void:
	var index := Catalog.voice_index()
	for clip in index.ids:
		var length := index.stream(clip).get_length()
		assert_float(length).override_failure_message("clip %d" % clip).is_between(0.2, 12.0)
