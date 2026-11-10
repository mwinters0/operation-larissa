class_name TestTriggerTableRuleLegacy
extends GdUnitTestSuite
## The fire rule of a math trigger (`DetectMathTrigger` 0x427744) checked against the ORIGINAL: `TriggerModel.TABLE` must be the 9 cells x 16 nibbles of
## `MathTriggerTable` (0x442994) dumped from ONWIN32.EXE, and the original's stored triggers use exactly the nibbles the dump shows. The rule itself
## (what each nibble tests, the inclusive box) is tests/engine/test_trigger_table_rule.gd, on made-up positions and a dev test sector.

## Rows = cells 0-8 of the table dumped from ONWIN32.EXE (columns = nibbles 0-15).
const EXE_TABLE_CHECKSUM_ROWS := {
	0: [0, 1, 0, 1, 0, 0, 0, 0, 2, 3, 0, 3, 2, 3, 0, 3],
	4: [0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 3],
	6: [0, 0, 0, 0, 2, 0, 0, 3, 0, 0, 0, 0, 2, 0, 0, 3],
	8: [0, 1, 0, 1, 2, 3, 0, 3, 0, 0, 0, 0, 2, 3, 0, 3],
}


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_the_table_has_9_cells_of_16_nibbles_and_matches_the_dump() -> void:
	assert_int(TriggerModel.TABLE.size()).is_equal(9 * 16)
	for cell: int in EXE_TABLE_CHECKSUM_ROWS:
		for nibble in 16:
			assert_int(TriggerModel.TABLE[cell * 16 + nibble]).is_equal(EXE_TABLE_CHECKSUM_ROWS[cell][nibble])


func test_the_stored_triggers_use_the_nibbles_of_the_dump() -> void:
	var counts := {}
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		for screen in Catalog.sector(s).screens:
			for trigger in screen.triggers:
				counts[trigger.flags & 15] = counts.get(trigger.flags & 15, 0) + 1
	assert_dict(counts).is_equal({15: 39, 1: 17, 4: 16, 8: 9, 2: 8, 12: 1})
