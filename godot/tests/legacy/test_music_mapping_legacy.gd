class_name TestMusicMappingLegacy
extends GdUnitTestSuite
## Which song plays where in the original game (extracted/tables/music_map.json, from the decompiled `SelectSectorMusic`) and where its songs' files are.
## (How songs are cross-faded, looped and paused is in tests/engine/test_music_mapping.gd.)


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_one_tune_per_sector_in_six() -> void:
	assert_str(AudioService.music_for_sector(0)).is_equal(&"sector_song_1")
	assert_str(AudioService.music_for_sector(5)).is_equal(&"sector_song_6")
	assert_str(AudioService.music_for_sector(6)).is_equal(&"sector_song_1")        # sectors 0 and 6 share a tune
	assert_str(AudioService.music_for_sector(1)).is_equal(&"sector_song_2")        # ... and sector 1 differs
	assert_str(AudioService.music_for_sector(29)).is_equal(&"sector_song_6")       # 29 % 6 = 5
	assert_str(AudioService.music_for_sector(15)).is_equal(&"sector_song_4")       # the Expert game's first sector


func test_the_finale_sectors_play_the_finale_song() -> void:
	assert_str(AudioService.music_for_sector(30)).is_equal(&"finale")
	assert_str(AudioService.music_for_sector(31)).is_equal(&"finale")


func test_the_named_songs_match_the_map() -> void:
	assert_int(MusicCatalog.id_of(AudioService.SONG_CLOSING)).is_equal(9501)
	assert_int(MusicCatalog.id_of(AudioService.SONG_OPENING)).is_equal(9502)
	assert_int(MusicCatalog.id_of(AudioService.SONG_TITLE)).is_equal(9503)


func test_the_catalog_is_the_verified_map() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../extracted/tables/music_map.json"))
	var catalog := Catalog.music_catalog()
	assert_int(catalog.ids.size()).is_equal(10)
	for entry: Dictionary in map["music"]:
		var i := catalog.ids.find(int(entry["id"]))
		assert_int(i).is_greater_equal(0)
		assert_str(catalog.midi_names[i]).is_equal(entry["file"])
		# The General MIDI set is the E*.MID file, the AdLib set the B*.MID file of the same name. The OGG of a named song is
		# <name>_<id>.ogg in both folders; one nobody named keeps the MIDI file's stem (tools/import/asset_names.py).
		var stem: String = String(entry["file"]).trim_suffix(".MID").substr(1).to_lower()
		var registry := NameRegistry.original()
		var id := int(entry["id"])
		var gm_file := "e" + stem
		var adlib_file := "b" + stem
		if registry.is_named(&"music", id):
			gm_file = "%s_%d" % [registry.name_of(&"music", id), id]
			adlib_file = gm_file
		assert_str(Packs.relative(catalog.gm_paths[i])).is_equal("assets/audio/music/%s.ogg" % gm_file)
		assert_str(Packs.relative(catalog.adlib_paths[i])).is_equal("assets/audio/music/adlib/%s.ogg" % adlib_file)
