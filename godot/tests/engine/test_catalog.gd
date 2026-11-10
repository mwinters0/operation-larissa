class_name TestCatalog
extends GdUnitTestSuite
## Teaches: loading generated Resources through the static Catalog class. The shape of what it loads (a sector, the zones, the text tables, the problem
## types) is the same in every pack; the original game's own sectors, texts and numbers are in tests/legacy/test_catalog_legacy.gd.


func test_a_sector_has_screens_pieces_and_creatures() -> void:
	var sector := Catalog.sector(0)
	assert_object(sector).is_not_null()
	assert_int(sector.index).is_equal(0)
	assert_int(sector.screens.size()).is_equal(DevPack.SCREENS)
	assert_int(sector.foes.size()).is_equal(DevPack.TOUR_CREATURES[0])
	assert_bool(sector.pieces[0].is_canister).is_true()                       # (piece 0 is the data canister)
	assert_int(sector.screens[0].tiles.size()).is_greater(0)


func test_a_sector_that_is_not_there_is_not_found() -> void:
	assert_bool(Catalog.has_sector(DevPack.test_sector("e", 19))).is_false()


func test_a_sector_knows_its_neighbours_and_its_music() -> void:
	var sector := Catalog.sector(0)
	assert_str(sector.music_name).is_not_empty()
	assert_int(sector.neighbor(0, SectorData.Direction.RIGHT)).is_equal(1)         # (a row of screens: nothing to the left of the first or right of the last)
	assert_int(sector.neighbor(DevPack.SCREENS - 1, SectorData.Direction.RIGHT)).is_equal(-1)
	assert_int(sector.neighbor(0, SectorData.Direction.LEFT)).is_equal(-1)


func test_the_zones_have_names_and_banners() -> void:
	assert_int(Catalog.zones().zones.size()).is_greater(0)
	for index in Catalog.zones().zones.size():
		assert_str(Catalog.zone(index).title).override_failure_message("zone %d" % index).is_not_empty()
	for sector_index in DevPack.TOUR_SECTORS:                                         # (a finale's zone may have no banner)
		var zone := Catalog.sector(sector_index).zone
		assert_int(zone).is_less(Catalog.zones().zones.size())
		assert_object(Catalog.zone(zone).banner_texture).override_failure_message("zone %d" % zone).is_not_null()


func test_every_text_table_loads() -> void:
	for table_name in Catalog.TEXT_TABLES:
		assert_int(Catalog.texts(table_name).texts.size()).override_failure_message(table_name).is_greater(0)


func test_problem_types() -> void:
	for i in Catalog.PROBLEM_TYPE_COUNT:
		var problem := Catalog.problem_type(i)
		assert_object(problem).is_not_null()
		assert_int(problem.id).is_equal(i)
		assert_str(problem.title).is_not_empty()
		assert_str(problem.texts[0]).is_not_empty()
		assert_int(problem.records.size()).is_greater(0)
		assert_int(problem.levels_available.size()).is_equal(4)
		assert_int(problem.art_files.size()).is_greater(0)
		# Every art file must really exist.
		for path in problem.art_files:
			assert_bool(ResourceLoader.exists(path)).is_true()


func test_the_game_data_comes_from_the_first_pack_of_the_chain_that_has_it() -> void:
	assert_str(Packs.holder("data/zones.tres").id).is_equal(PackShelf.base_id())
	assert_str(Packs.path("data/zones.tres")).is_equal(DevPack.path("data/zones.tres"))
	assert_str(Catalog.zones().resource_path).is_equal(DevPack.path("data/zones.tres"))
	assert_str(Catalog.pack_resource("data/ui/hud_layout.tres").resource_path).is_equal(DevPack.path("data/ui/hud_layout.tres"))
	assert_str(Assets.background_path(3, 7)).is_equal(DevPack.path("assets/backgrounds/bg_s03_07.png"))
	assert_str(Catalog.sector_dir(3)).is_equal(DevPack.SECTORS_DIR + "/sector_03")
	assert_array(Catalog.own_sector_dirs()).is_equal([DevPack.SECTORS_DIR, Catalog.SECTORS_DIR])
	assert_array(Catalog.own_campaign_dirs()).is_equal([DevPack.CAMPAIGNS_DIR, Catalog.CAMPAIGNS_DIR])
