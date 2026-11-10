class_name TestAudioAssets
extends GdUnitTestSuite
## The audio of the pack in use: every effect and every clip that anything refers to exists and is not silent, and the catalogs find them by name and
## by number. (The original's own numbers, lengths and counts are in tests/legacy/test_audio_assets_legacy.gd.)
## Loudness, clipping and loop seams of the music are measured by tools/import/test_import.py, which can decode the OGG files; GDScript cannot read their samples.


func test_the_effect_catalog_finds_an_effect_by_name_and_by_number() -> void:
	var catalog := Catalog.sfx_catalog()
	assert_int(catalog.streams.size()).is_greater(0)
	assert_object(catalog.stream_named(&"correct")).is_not_null()
	var number := catalog.id_of(&"correct")
	assert_int(number).is_greater_equal(0)
	assert_str(catalog.name_of(number)).is_equal("correct")
	assert_object(catalog.stream(number)).is_same(catalog.stream_named(&"correct"))
	assert_int(catalog.id_of(&"no_such_effect")).is_equal(-1)


## Every effect and every voice clip holds real sound, not silence: the loudest sample is well above the noise
## floor. (Godot imports WAV files with lossy QOA compression, so the samples are read from the source files.)
func test_every_effect_and_clip_is_audible() -> void:
	var catalog := Catalog.sfx_catalog()
	for i in catalog.streams.size():
		var path := catalog.streams[i].resource_path
		var peak := _peak_of_wav_file(path)
		assert_float(peak).override_failure_message("%s is silent (peak %f)" % [path, peak]).is_greater(0.2)
	for path in Catalog.voice_index().paths:
		var peak := _peak_of_wav_file(path)
		assert_float(peak).override_failure_message("%s is silent (peak %f)" % [path, peak]).is_greater(0.2)


## Loudest sample (0.0 - 1.0) of a mono WAV file of 8 bits (unsigned) or 16 bits (signed), found by walking its RIFF chunks.
func _peak_of_wav_file(path: String) -> float:
	var bytes := FileAccess.get_file_as_bytes(path)
	assert_int(bytes.size()).override_failure_message("cannot read " + path).is_greater(44)
	var bits := 8
	var at := 12                                                   # after "RIFF", size, "WAVE"
	while at + 8 <= bytes.size():
		var tag := bytes.slice(at, at + 4).get_string_from_ascii()
		var size := bytes.decode_u32(at + 4)
		if tag == "fmt ":
			bits = bytes.decode_u16(at + 8 + 14)
		elif tag == "data":
			var peak := 0.0
			var end := mini(at + 8 + size, bytes.size())
			if bits == 16:
				for i in range(at + 8, end - 1, 2):
					peak = maxf(peak, absf(bytes.decode_s16(i)) / 32768.0)
			else:
				for i in range(at + 8, end):
					peak = maxf(peak, absf(bytes[i] - 128) / 128.0)     # 8-bit WAV samples are unsigned, silence is 128
			return peak
		at += 8 + size + (size & 1)
	return 0.0


func test_the_voice_index_finds_every_clip() -> void:
	var index := Catalog.voice_index()
	assert_int(index.ids.size()).is_greater(0)
	assert_int(index.paths.size()).is_equal(index.ids.size())
	assert_int(index.durations.size()).is_equal(index.ids.size())
	for clip in index.ids:
		assert_object(index.stream(clip)).override_failure_message("clip %d" % clip).is_not_null()
	assert_object(index.stream(-1)).is_null()
