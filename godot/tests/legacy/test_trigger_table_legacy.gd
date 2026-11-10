class_name TestTriggerTableLegacy
extends GdUnitTestSuite
## The ORIGINAL's trigger table: which problem type its first slots ask for. The table's mechanics are tested on dev in tests/engine/test_trigger_table.gd.


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_fixed_slots() -> void:
	var table := Catalog.trigger_table()
	assert_int(table.table.size()).is_equal(63 * 4 * 2)
	for level in 4:
		for pick in 2:
			assert_int(table.type_for(0, level, pick)).is_equal(0)   # combination lock
			assert_int(table.type_for(1, level, pick)).is_equal(1)   # data canister
