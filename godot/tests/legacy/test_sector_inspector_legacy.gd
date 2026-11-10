class_name TestSectorInspectorLegacy
extends GdUnitTestSuite
## The sector panel on the original's sectors: the names the registry gives its screens and creatures, and the songs of its 32 sectors.
## The panel and its edits, on the sectors of dev, are in `tests/engine/test_sector_inspector.gd`.

const SECTORS := LegacyPack.SECTORS_DIR


func _load(sector: int) -> SectorData:
	return ResourceLoader.load(Catalog.sector_path(sector, SECTORS), "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData


func test_the_panel_names_the_screens_and_creatures_of_sector_0_from_the_registry() -> void:
	var panel := auto_free(SectorPanel.new()) as SectorPanel
	panel.setup(_load(0), UndoRedo.new())
	add_child(panel)
	assert_str(panel.label_of(&"screen", 0)).is_equal("0  start_station")
	assert_str(panel.label_of(&"screen", 11)).is_equal("11  end_station")
	assert_str(panel.label_of(&"screen", 3)).is_equal("3")                           # nobody named it: just the number
	assert_str(panel.label_of(&"foe", 0)).is_equal("0  " + NameRegistry.original().name_of(&"foe", 0, 0))


func test_the_song_the_panel_names_is_the_song_the_game_plays_in_every_original_sector() -> void:
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		assert_str(SectorPanel.game_song(_load(s).music_name)).is_equal(AudioService.music_for_sector(s))
		assert_bool(SectorPanel.songs().has(_load(s).music_name)).override_failure_message("sector %d: %s" % [s, _load(s).music_name]).is_true()
