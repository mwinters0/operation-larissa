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


## The ten AdLib songs use the base-level layout (melodic channels 13-15, percussion on 16, never channel 10): `MidiMusic` moves every
## channel-16 event to channel 10, loses no event, and leaves the ten General MIDI songs (channel 10 already) as they are.
func test_the_adlib_songs_play_their_percussion_on_channel_10() -> void:
	var catalog := Catalog.music_catalog()
	for name in catalog.midi_names:
		var adlib := FileAccess.get_file_as_bytes(LegacyPack.ROOT + "midi/B" + name.substr(1))
		var before := _channel_counts(adlib)
		assert_bool(before.has(15) and not before.has(9)).override_failure_message(name).is_true()
		var after := _channel_counts(MidiMusic.percussion_to_channel_10(adlib))
		var expected := before.duplicate()
		expected.erase(15)
		expected[9] = before[15]
		assert_dict(after).override_failure_message(name).is_equal(expected)         # the same events, channel 16's now on channel 10
		var general := FileAccess.get_file_as_bytes(LegacyPack.ROOT + "midi/E" + name.substr(1))
		assert_array(MidiMusic.percussion_to_channel_10(general)).override_failure_message(name).is_equal(general)


## How many channel-voiced events each channel (from 0) has in a MIDI file.
func _channel_counts(bytes: PackedByteArray) -> Dictionary:
	var counts := {}
	for track in SMF.new().read_data(bytes).data.tracks:
		for chunk: SMF.MIDIEventChunk in track.events:
			if chunk.event.type != SMF.MIDIEventType.system_event:
				counts[chunk.channel_number] = counts.get(chunk.channel_number, 0) + 1
	return counts
