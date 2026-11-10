class_name TestSectorDataIntegrity
extends GdUnitTestSuite
## Cross-checks all 32 sectors against the zone tables (the "slot arithmetic" of DESIGN section 9).


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_all_sectors() -> void:
	for i in Catalog.ORIGINAL_SECTOR_COUNT:
		var sector := Catalog.sector(i)
		var zone := Catalog.zone(sector.zone)
		assert_int(sector.index).is_equal(i)
		assert_int(sector.screens.size()).is_equal(Catalog.SCREENS_PER_SECTOR)
		for list in [sector.neighbors_left, sector.neighbors_right, sector.neighbors_up, sector.neighbors_down]:
			assert_int(list.size()).is_equal(12)
			for destination: int in list:
				assert_bool(destination >= -1 and destination <= 11).is_true()
		for screen in sector.screens:
			assert_int(screen.tiles.size()).is_equal(684)
			for deco_list in [screen.bg_decos, screen.mid_decos, screen.fg_decos]:
				for deco: DecoPlacement in deco_list:
					assert_bool(deco.slot < 70 + zone.deco_count).is_true()
			for anim: AnimDecoData in screen.anim_decos:
				for slot in anim.frames:
					# "<=": animation frame numbers may be 1-based, so allow one past the end.
					assert_bool(slot <= 70 + zone.deco_count).is_true()
		for foe in sector.foes:
			assert_bool(foe.frame < 35 + zone.foe_count).is_true()
			assert_bool(foe.screen >= 0 and foe.screen < 12).is_true()
		assert_int(sector.foe_bytecode.size()).is_greater(0)
