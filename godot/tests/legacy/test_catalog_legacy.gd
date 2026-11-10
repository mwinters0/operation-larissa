class_name TestCatalogLegacy
extends GdUnitTestSuite
## The original game's data as `Catalog` loads it: sector 0 and sector 31, its header, its zones, its text tables and its problem types.
## (How the catalog finds and shapes data in general is in tests/engine/test_catalog.gd.)


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_sector_0_contents() -> void:
	var sector := Catalog.sector(0)
	assert_object(sector).is_not_null()
	assert_int(sector.screens.size()).is_equal(12)
	assert_int(sector.pieces.size()).is_equal(10)
	assert_int(sector.foes.size()).is_equal(21)
	assert_bool(sector.pieces[0].is_canister).is_true()


func test_sector_31_has_one_piece() -> void:
	assert_int(Catalog.sector(31).pieces.size()).is_equal(1)


func test_sector_0_first_tile_byte() -> void:
	# Screen 0, column 0, row 0: 115 (0x73) = solid, picture 51 of the zone floor.
	assert_int(Catalog.sector(0).screens[0].tiles[0]).is_equal(115)


func test_sector_0_header() -> void:
	var sector := Catalog.sector(0)
	assert_that(sector.start_pos).is_equal(Vector2i(68, 66))
	assert_int(sector.game).is_equal(0)
	assert_str(sector.music_name).is_equal("esect1")
	# Screen 0 has screen 1 to its right (original value 2, minus 1) and nothing to its left.
	assert_int(sector.neighbor(0, SectorData.Direction.RIGHT)).is_equal(1)
	assert_int(sector.neighbor(3, SectorData.Direction.RIGHT)).is_equal(-1)
	assert_int(sector.neighbor(0, SectorData.Direction.LEFT)).is_equal(-1)


func test_zones() -> void:
	assert_int(Catalog.zones().zones.size()).is_equal(7)
	assert_str(Catalog.zone(0).title).is_equal("Dragon Reef")
	assert_object(Catalog.zone(0).banner_texture).is_not_null()
	assert_int(Catalog.zone(4).deco_count).is_equal(22)
	assert_int(Catalog.zone(5).tile_zone).is_equal(4)


func test_text_tables() -> void:
	assert_str(Catalog.texts("log_entries").text(10648)).starts_with("ENTRY 1.01:")
	assert_int(Catalog.texts("log_entries").texts.size()).is_equal(30)
	assert_int(Catalog.texts("supply_messages").texts.size()).is_equal(30)


func test_the_data_canister_problem_has_its_name() -> void:
	assert_str(Catalog.problem_type(1).title).is_equal("Data Canister")
