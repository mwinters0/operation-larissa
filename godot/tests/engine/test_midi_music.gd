class_name TestMidiMusic
extends GdUnitTestSuite
## Music from MIDI at runtime: `MidiMusic`, and `Audio.set_soundfont`, which plays the songs from their MIDI files through
## a SoundFont instead of the rendered OGGs. Off by default; these tests turn it on.
##
## The MIDI files are the pack's own (`midi/` of the chain: the dev pack's tiny melodies) and the SoundFont is a fixture of a few KB, one looped sine wave
## for every program (`tests/fixtures/tiny_soundfont.sf2`, made by `tools/dev_pack/test_sectors/batch_e.py`), so nothing is skipped for want of files.

const SONG := &"sector_song_1"
const MIDI_FILE := "ESECT1.MID"
const SOUNDFONT := "res://tests/fixtures/tiny_soundfont.sf2"


func after_test() -> void:
	Audio.stop_music()
	while Audio._music_pause_count > 0:
		Audio.resume_music()
	Audio.set_soundfont("")                       # frees the player, the parsed SoundFont and the buses
	Audio.sound_set = MusicCatalog.SoundSet.GENERAL_MIDI


# --- names, fallbacks and file checks ----------------------------------------------------------------

func test_the_midi_file_of_a_song_follows_the_sound_set() -> void:
	var catalog := Catalog.music_catalog()
	assert_str(catalog.midi_file_of(SONG, MusicCatalog.SoundSet.GENERAL_MIDI)).is_equal("ESECT1.MID")
	assert_str(catalog.midi_file_of(SONG, MusicCatalog.SoundSet.ADLIB)).is_equal("BSECT1.MID")
	assert_str(catalog.midi_file_of(AudioService.SONG_TITLE)).is_equal("ENEPT2.MID")
	assert_str(catalog.midi_file_of(&"no_such_song")).is_equal("")


func test_only_a_soundfont_2_file_is_taken_for_one() -> void:
	var path := "user://test_midi_music_fake.sf2"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("RIFF\u0000\u0000\u0000\u0000WAVEfmt ")                 # a RIFF file, but a wave
	file.close()
	assert_bool(MidiMusic.is_soundfont(path)).is_false()
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer("RIFF".to_ascii_buffer() + PackedByteArray([0, 0, 0, 0]) + "sfbk".to_ascii_buffer())
	file.close()
	assert_bool(MidiMusic.is_soundfont(path)).is_true()                      # (the header is all that is checked)
	assert_bool(MidiMusic.is_soundfont("user://no_such_file.sf2")).is_false()
	assert_bool(MidiMusic.is_soundfont("res://project.godot")).is_false()
	assert_bool(MidiMusic.is_soundfont("")).is_false()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_without_a_soundfont_the_rendered_song_plays() -> void:
	assert_str(Audio.midi_soundfont).is_equal("")                             # the default
	Audio.play_music(SONG)
	assert_bool(Audio.is_music_playing()).is_true()
	assert_bool(Audio.is_midi_music()).is_false()


func test_a_file_that_is_not_a_soundfont_is_refused_and_the_rendered_song_plays() -> void:
	assert_bool(Audio.set_soundfont("res://project.godot")).is_false()
	assert_str(Audio.midi_soundfont).is_equal("")
	Audio.play_music(SONG)
	assert_bool(Audio.is_midi_music()).is_false()
	assert_bool(Audio.is_music_playing()).is_true()


func test_a_song_that_has_no_midi_file_is_not_found() -> void:
	var music := MidiMusic.new()
	assert_str(music.find_midi("NO_SUCH_SONG.MID")).is_equal("")
	assert_str(music.find_midi("")).is_equal("")
	music.add_midi_dir("user://campaign_midi")
	assert_str(music.find_midi("NO_SUCH_SONG.MID")).is_equal("")
	music.free()


## A song lasts as long as its last event, with the tempo changes on the way: a made-up file of four quarter notes at 120 beats a minute (2 s), then at
## 60 (2 s more).
func test_a_midi_song_lasts_until_its_last_event_at_its_tempo() -> void:
	var track := PackedByteArray([0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20])                    # 500000 microseconds a quarter note
	for beat in 4:
		track.append_array(PackedByteArray([0x00, 0x90, 60, 90, 0x60, 0x80, 60, 0]))             # a quarter note (96 ticks) per beat
	track.append_array(PackedByteArray([0x00, 0xFF, 0x51, 0x03, 0x0F, 0x42, 0x40]))            # now 1000000: 60 beats a minute
	for beat in 2:
		track.append_array(PackedByteArray([0x00, 0x90, 62, 90, 0x60, 0x80, 62, 0]))
	track.append_array(PackedByteArray([0x00, 0xFF, 0x2F, 0x00]))
	var bytes := "MThd".to_ascii_buffer() + PackedByteArray([0, 0, 0, 6, 0, 0, 0, 1, 0, 96]) + "MTrk".to_ascii_buffer()
	bytes.append_array(PackedByteArray([0, 0, 0, 0]))
	bytes.encode_u32(bytes.size() - 4, track.size())
	bytes.append_array(track)
	assert_float(MidiMusic.song_seconds(bytes)).is_equal_approx(4 * 0.5 + 2 * 1.0, 0.01)
	assert_float(MidiMusic.song_seconds(PackedByteArray())).is_equal(0.0)


func test_the_pack_has_the_midi_file_of_its_song() -> void:
	var music := MidiMusic.new()
	var path := music.find_midi(Catalog.music_catalog().midi_file_of(SONG))
	assert_str(path).is_not_empty()
	assert_float(MidiMusic.song_seconds(Packs.bytes_at(path))).is_greater(1.0)
	music.free()


# --- with a SoundFont ----------------------------------------------------------------------------------

func test_a_midi_song_makes_sound_that_stays_under_the_ceiling() -> void:
	var music := MidiMusic.new()
	add_child(music)
	assert_bool(music.set_soundfont(SOUNDFONT)).is_true()
	assert_bool(music.play_file(music.find_midi(MIDI_FILE))).is_true()
	assert_bool(music.is_playing()).is_true()
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index(MidiMusic.BUS), capture)     # after the limiter
	var peak := 0.0
	for step in 20:
		await await_millis(100)
		var frames := capture.get_buffer(capture.get_frames_available())
		for frame in frames:
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	assert_float(linear_to_db(peak)).override_failure_message("silent").is_greater(-50.0)
	assert_float(linear_to_db(peak)).override_failure_message("over the ceiling").is_less_equal(MidiMusic.CEILING_DB + 0.1)
	assert_int(music.voices()).is_greater(0)
	music.free()
	MidiMusic.remove_buses()


func test_a_midi_song_loops_to_its_start_and_pausing_holds_it() -> void:
	var music := MidiMusic.new()
	add_child(music)
	music.set_soundfont(SOUNDFONT)
	assert_bool(music.play_file(music.find_midi("ENEPT2.MID"))).is_true()
	var player: MidiPlayer = music._player
	assert_bool(player.loop).is_true()
	assert_float(player.loop_start).is_equal(0.0)                             # no loop-point controller: back to the first event
	player.seek(player.last_position - 20.0)                                 # just before the end (a fifth of a quarter note) ...
	var looped := [false]
	player.looped.connect(func() -> void: looped[0] = true)
	await await_millis(600)
	assert_bool(looped[0]).is_true()                                         # ... it comes round again
	assert_bool(player.playing).is_true()
	music.set_paused(true)
	var held := player.position
	await await_millis(200)
	assert_float(player.position).is_equal(held)
	assert_int(music.voices()).is_equal(0)
	music.set_paused(false)
	await await_millis(200)
	assert_float(player.position).is_greater(held)
	music.free()
	MidiMusic.remove_buses()


func test_the_audio_service_plays_the_song_from_midi_and_goes_back() -> void:
	var heard: Array[StringName] = []
	Audio.music_changed.connect(func(new_song: StringName) -> void: heard.append(new_song))
	assert_bool(Audio.set_soundfont(SOUNDFONT)).is_true()
	Audio.play_music(SONG)
	assert_array(heard).is_equal([SONG])
	assert_bool(Audio.is_midi_music()).is_true()
	assert_bool(Audio.is_music_playing()).is_true()
	assert_str(Audio._midi.playing_file.get_file()).is_equal(MIDI_FILE)
	# the AdLib set is the B*.MID file, through the same SoundFont
	Audio.set_sound_set(MusicCatalog.SoundSet.ADLIB)
	assert_str(Audio._midi.playing_file.get_file()).is_equal("BSECT1.MID")
	# a dialog holds the song and lets it go on
	Audio.pause_music()
	assert_bool(Audio.is_music_playing()).is_true()
	assert_bool(Audio._midi.is_playing()).is_false()
	Audio.resume_music()
	assert_bool(Audio._midi.is_playing()).is_true()
	# switching the SoundFont off: the rendered song takes over, the player and its buses are gone
	Audio.set_soundfont("")
	assert_bool(Audio.is_midi_music()).is_false()
	assert_bool(Audio.is_music_playing()).is_true()
	assert_int(AudioServer.get_bus_index(MidiMusic.BUS)).is_equal(-1)
	assert_int(AudioServer.bus_count).is_equal(AudioService.BUSES.size())
	Audio.stop_music()
	assert_array(heard).contains([SONG, AudioService.NO_MUSIC])
