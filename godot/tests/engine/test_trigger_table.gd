class_name TestTriggerTable
extends GdUnitTestSuite
## Teaches: a flat table with an index function (`TriggerTable.type_for`), tested on a table the test fills itself and on the chain's. The original's
## table (which slots ask for the lock and the canister) is tests/legacy/test_trigger_table_legacy.gd and its hash tests/legacy/test_trigger_table_fidelity.gd.


func _copy() -> TriggerTable:
	return Catalog.trigger_table().duplicate_deep() as TriggerTable


func test_the_table_has_a_byte_for_every_slot_level_and_pick() -> void:
	var table := Catalog.trigger_table()
	assert_int(table.table.size()).is_equal(TriggerTable.SLOTS * TriggerTable.LEVELS * TriggerTable.PICKS)
	assert_array(table.problems()).is_empty()


func test_types_in_range() -> void:
	var table := Catalog.trigger_table()
	for slot in TriggerTable.SLOTS:
		for level in TriggerTable.LEVELS:
			for pick in TriggerTable.PICKS:
				assert_bool(table.type_for(slot, level, pick) < Catalog.PROBLEM_TYPE_COUNT).is_true()


func test_the_index_runs_slot_then_level_then_pick() -> void:
	var table := TriggerTable.new()
	table.table.resize(TriggerTable.SIZE)
	for i in TriggerTable.SIZE:
		table.table[i] = i % 34
	assert_int(table.type_for(0, 0, 0)).is_equal(0)
	assert_int(table.type_for(0, 0, 1)).is_equal(1)
	assert_int(table.type_for(0, 1, 0)).is_equal(2)                    # a level is two bytes ...
	assert_int(table.type_for(1, 0, 0)).is_equal(8 % 34)               # ... a slot is LEVELS x PICKS = 8
	assert_int(table.type_for(5, 3, 1)).is_equal((5 * 8 + 3 * 2 + 1) % 34)
	assert_str(TriggerTable.field_at(5 * 8 + 3 * 2 + 1)).is_equal("slot 5, educational level 3, pick 1")


func test_an_edited_entry_is_named() -> void:
	var original := Catalog.trigger_table().encode()
	var table := _copy()
	table.table[(12 * TriggerTable.LEVELS + 2) * TriggerTable.PICKS + 1] += 1
	assert_str(TriggerTable.first_difference(original, table.encode())).starts_with("first difference at byte 0x").contains("(slot 12, educational level 2, pick 1)")
	assert_str(TriggerTable.first_difference(original, original)).is_empty()
	assert_str(TriggerTable.first_difference(original, PackedByteArray())).contains("0 bytes")
	assert_str(TriggerTable.field_at(TriggerTable.SIZE - 1)).is_equal("slot 62, educational level 3, pick 1")
	assert_str(TriggerTable.field_at(TriggerTable.SIZE)).is_equal("outside the table")


func test_a_table_of_the_wrong_size_is_refused() -> void:
	var table := _copy()
	table.table.resize(TriggerTable.SIZE - 2)
	assert_str("\n".join(table.problems())).contains("table: %d bytes" % (TriggerTable.SIZE - 2)).contains("(63 slots x 4 levels x 2 picks)")
	assert_int(table.encode().size()).is_equal(0)
