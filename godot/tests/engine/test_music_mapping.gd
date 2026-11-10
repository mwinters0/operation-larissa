class_name TestMusicMapping
extends GdUnitTestSuite
## Which song plays where (a sector's `music_name` through its campaign), and how the songs are cross-faded, looped and paused.
## (The original game's own map of sectors to songs is checked in tests/legacy/test_music_mapping_legacy.gd.)

var _probe: AudioProbe
var _undo: Array[Callable] = []                 ## puts back what a test changed in the pack's data (resources are shared by every test)


func before_test() -> void:
	_probe = AudioProbe.new()


func after_test() -> void:
	for undo in _undo:
		undo.call()
	_undo.clear()
	_probe.stop()
	Audio.stop_music()
	while Audio._music_pause_count > 0:
		Audio.resume_music()
	Audio.sound_set = MusicCatalog.SoundSet.GENERAL_MIDI


func test_a_sector_plays_the_song_its_music_name_names() -> void:
	var tour := Catalog.campaign(DevPack.TOUR)
	assert_str(Catalog.sector(0).music_name).is_not_empty()
	assert_str(AudioService.music_for_sector(0)).is_equal(tour.song_for(0))
	assert_str(AudioService.music_for_sector(0)).is_equal(MusicCatalog.song_of_stem(Catalog.sector(0).music_name))
	assert_str(AudioService.music_for_sector(0)).is_not_equal(AudioService.music_for_sector(1))      # (the tour's sectors have a tune each)
	assert_object(Catalog.music_catalog().stream_named(AudioService.music_for_sector(0))).is_not_null()


func test_the_stem_of_a_midi_file_names_the_song_and_an_unknown_stem_names_none() -> void:
	assert_str(MusicCatalog.song_of_stem("esect1")).is_equal(&"sector_song_1")
	assert_str(MusicCatalog.song_of_stem("ESECT3")).is_equal(&"sector_song_3")             # (case does not matter)
	assert_str(MusicCatalog.song_of_stem("eend")).is_equal(&"finale")
	assert_str(MusicCatalog.song_of_stem("no_such_tune")).is_equal(&"")


func test_a_sector_that_names_no_known_tune_plays_its_campaigns_fallback() -> void:
	var tour := Catalog.campaign(DevPack.TOUR)
	var data := Catalog.sector(1)
	var old := data.music_name
	_undo.append(func() -> void: data.music_name = old)
	data.music_name = "no_such_tune"
	assert_str(tour.song_for(1)).is_equal(tour.fallback_song)
	assert_str(AudioService.music_for_sector(1)).is_equal(tour.fallback_song)


func test_a_sector_that_is_in_no_campaign_plays_the_default_song() -> void:
	assert_object(Catalog.campaign_of_sector(DevPack.test_sector("e", 19))).is_null()
	assert_str(AudioService.music_for_sector(DevPack.test_sector("e", 19))).is_equal(Campaign.DEFAULT_SONG)


func test_the_songs_the_game_names_itself_are_in_the_catalog() -> void:
	var catalog := Catalog.music_catalog()
	for song in [AudioService.SONG_TITLE, AudioService.SONG_OPENING, AudioService.SONG_CLOSING, &"finale"]:
		assert_object(catalog.stream_named(song)).override_failure_message(String(song)).is_not_null()
		assert_int(MusicCatalog.id_of(song)).override_failure_message(String(song)).is_greater_equal(0)


func test_every_song_loads_in_both_sets_and_loops() -> void:
	var catalog := Catalog.music_catalog()
	for song_id in catalog.ids:
		for sound_set in [MusicCatalog.SoundSet.GENERAL_MIDI, MusicCatalog.SoundSet.ADLIB]:
			var stream := catalog.stream(song_id, sound_set) as AudioStreamOggVorbis
			assert_object(stream).is_not_null()
			assert_bool(stream.loop).is_true()


func test_a_missing_song_is_a_warning_not_a_crash() -> void:
	var catalog := Catalog.music_catalog()
	assert_object(catalog.stream(1234)).is_null()
	Audio.play_music(&"no_such_song")                                              # unknown id: silence
	assert_str(Audio.song).is_equal(AudioService.NO_MUSIC)
	assert_bool(Audio.is_music_playing()).is_false()


func test_play_music_starts_the_song_and_announces_it() -> void:
	Audio.play_music(&"sector_song_2")
	assert_str(Audio.song).is_equal(&"sector_song_2")
	assert_bool(Audio.is_music_playing()).is_true()
	assert_array(_probe.music).is_equal([&"sector_song_2"])


func test_the_same_song_is_kept_when_restart_is_off() -> void:
	Audio.play_music(&"sector_song_1")
	Audio.play_music(&"sector_song_1", false)
	assert_array(_probe.music).is_equal([&"sector_song_1"])
	Audio.play_music(&"sector_song_1")                                              # the default: start over (like a screen change)
	assert_array(_probe.music).is_equal([&"sector_song_1", &"sector_song_1"])


func test_changing_the_song_cross_fades_the_two_players() -> void:
	Audio.play_music(&"sector_song_1")
	var first: AudioStreamPlayer = Audio._music_players[Audio._active_music_player]
	Audio.play_music(&"sector_song_2")
	var second: AudioStreamPlayer = Audio._music_players[Audio._active_music_player]
	assert_object(second).is_not_same(first)
	assert_bool(first.playing and second.playing).is_true()             # both sound during the fade
	await await_millis(int(AudioService.FADE_SECONDS * 1000) + 300)
	assert_bool(first.playing).is_false()
	assert_float(second.volume_db).is_equal_approx(0.0, 0.5)


func test_stop_music_fades_out_and_forgets_the_song() -> void:
	Audio.play_music(&"sector_song_3")
	Audio.stop_music()
	assert_str(Audio.song).is_equal(AudioService.NO_MUSIC)
	assert_array(_probe.music).is_equal([&"sector_song_3", AudioService.NO_MUSIC])
	await await_millis(int(AudioService.FADE_SECONDS * 1000) + 300)
	assert_bool(Audio.is_music_playing()).is_false()


func _playing_music_players() -> int:
	var count := 0
	for player: AudioStreamPlayer in Audio._music_players:
		count += 1 if player.playing else 0
	return count


## A request in the middle of a fade kills the tween and with it the `stop` queued for the first song's player: it must not play on.
func test_stopping_the_music_in_the_middle_of_a_cross_fade_leaves_no_player_sounding_after_the_fade() -> void:
	for player: AudioStreamPlayer in Audio._music_players:
		player.stop()
	Audio.play_music(&"sector_song_1")
	var first: AudioStreamPlayer = Audio._music_players[Audio._active_music_player]
	Audio.play_music(&"sector_song_2")
	Audio.stop_music()
	assert_bool(first.playing).is_false()                                # (the older song is not the one that fades: it is simply gone)
	await await_millis(int(AudioService.FADE_SECONDS * 1000) + 300)
	assert_int(_playing_music_players()).is_equal(0)
	assert_bool(Audio.is_music_playing()).is_false()


func test_a_song_asked_for_twice_within_the_fade_leaves_only_the_last_one_sounding() -> void:
	for player: AudioStreamPlayer in Audio._music_players:
		player.stop()
	Audio.play_music(&"sector_song_1")
	Audio.play_music(&"sector_song_2")
	Audio.pause_music()                                                  # (a dialog in the middle of the fades changes nothing)
	Audio.play_music(&"sector_song_3")
	Audio.resume_music()
	assert_int(_playing_music_players()).is_less_equal(2)
	await await_millis(int(AudioService.FADE_SECONDS * 1000) + 300)
	assert_int(_playing_music_players()).is_equal(1)
	assert_bool(Audio._music_players[Audio._active_music_player].playing).is_true()
	assert_str((Audio._music_players[Audio._active_music_player] as AudioStreamPlayer).stream.resource_path) \
			.is_equal(Catalog.music_catalog().stream_named(&"sector_song_3", Audio.sound_set).resource_path)


## A song held by a dialog reports `playing == false`, so a stop (or a new song) behind the dialog must still count it as sounding.
func test_stopping_the_music_behind_a_dialog_silences_it_for_good() -> void:
	for player: AudioStreamPlayer in Audio._music_players:
		player.stop()
	Audio.play_music(&"sector_song_1")
	Audio.pause_music()
	assert_bool(Audio.is_music_playing()).is_true()                      # (held, not stopped)
	Audio.stop_music()
	Audio.resume_music()
	await await_millis(int(AudioService.FADE_SECONDS * 1000) + 300)
	assert_int(_playing_music_players()).is_equal(0)


func test_pauses_nest() -> void:
	Audio.play_music(&"sector_song_1")
	var player: AudioStreamPlayer = Audio._music_players[Audio._active_music_player]
	Audio.pause_music()
	Audio.pause_music()
	assert_bool(player.stream_paused).is_true()
	Audio.resume_music()
	assert_bool(player.stream_paused).is_true()                         # one dialog is still open
	Audio.resume_music()
	assert_bool(player.stream_paused).is_false()


func test_switching_the_sound_set_replays_the_song_in_the_new_set() -> void:
	Audio.play_music(&"sector_song_1")
	var general: AudioStream = (Audio._music_players[Audio._active_music_player] as AudioStreamPlayer).stream
	Audio.set_sound_set(MusicCatalog.SoundSet.ADLIB)
	var adlib: AudioStream = (Audio._music_players[Audio._active_music_player] as AudioStreamPlayer).stream
	assert_object(adlib).is_not_same(general)
	assert_str(adlib.resource_path).contains("/adlib/")
