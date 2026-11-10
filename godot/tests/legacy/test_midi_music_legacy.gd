class_name TestMidiMusicLegacy
extends GdUnitTestSuite
## Music from MIDI at runtime as the original's songs have it: the MIDI files of the legacy pack (copied by the importer from your copy of the
## game) last as long as the OGGs rendered from them. (`MidiMusic` itself is tested on the dev pack in tests/engine/test_midi_music.gd.)

const MIDI_FILE := "ESECT1.MID"


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


## The MIDI song lasts as long as its rendered OGG (which also holds the release of the last notes): within three seconds, for
## all ten General MIDI songs.
func test_a_midi_song_is_as_long_as_its_render() -> void:
	var catalog := Catalog.music_catalog()
	assert_bool(FileAccess.file_exists(LegacyPack.ROOT + "midi/" + MIDI_FILE)).is_true()
	for i in catalog.ids.size():
		var midi := FileAccess.get_file_as_bytes(LegacyPack.ROOT + "midi/E" + catalog.midi_names[i].substr(1))
		var rendered := Packs.file_at(catalog.gm_paths[i]) as AudioStreamOggVorbis
		var seconds := MidiMusic.song_seconds(midi)
		assert_float(seconds).override_failure_message(catalog.midi_names[i]).is_between(rendered.get_length() - 3.0, rendered.get_length())
