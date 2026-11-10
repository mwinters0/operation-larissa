class_name TestSectorChanges
extends GdUnitTestSuite
## `SectorChanges` (the what-changed report) names what differs between a sector and the ORIGINAL's records, so almost all of its tests need the original and are in
## `tests/legacy/test_sector_changes_legacy.gd`. What is left here is what does not depend on the original's bytes: the line diff the script comparison uses, which
## sprite sets a sector draws from, and what the report says of a sector that has no original (every sector of dev, and a designer's sector in any pack).


## A copy of a sector of the dev pack that is safe to change.
func _copy_of(index: int = Ground.MAIN) -> SectorData:
	return Catalog.sector(index).duplicate_deep() as SectorData


func _options() -> SectorChanges.Options:
	var options := SectorChanges.Options.new()
	options.source = OriginalBytes.new(FixtureHash.ORIGINAL_DIR)
	return options


func test_the_sprite_sets_of_a_sector_are_the_common_ones_the_ink_burst_and_its_zone() -> void:
	var sector := Ground.main()
	assert_array(SectorChanges.sprite_sets_of(sector)).is_equal(["common", "ink", "zone%d" % sector.zone])


func test_the_line_diff_names_changed_added_and_removed_lines() -> void:
	var hunks := LineDiff.diff("a\nb\nc\nd\ne\n", "a\nB\nc\nd\nx\ny\ne\n")
	assert_int(hunks.size()).is_equal(2)
	assert_str(hunks[0].kind()).is_equal("changed")
	assert_int(hunks[0].new_start).is_equal(2)
	assert_str(hunks[0].new_range_text()).is_equal("line 2")
	assert_str(hunks[1].kind()).is_equal("added")
	assert_str(hunks[1].new_range_text()).is_equal("lines 5-6")
	assert_array(hunks[1].new_lines).is_equal(["x", "y"])
	hunks = LineDiff.diff("a\nb\nc\n", "a\nc\n")
	assert_int(hunks.size()).is_equal(1)
	assert_str(hunks[0].kind()).is_equal("removed")
	assert_str(hunks[0].new_range_text()).is_equal("after line 1")
	assert_int(LineDiff.diff("same\ntext\n", "same\ntext\n").size()).is_equal(0)
	assert_int(LineDiff.diff("", "a\n").size()).is_equal(1)




func test_a_sector_of_dev_has_no_original_to_compare_with() -> void:
	var sector := _copy_of()               # sector 100: dev's own, the original has no such sector
	var report := SectorChanges.report(sector, _options())
	assert_bool(report.is_same()).is_true()
	for item in report.items:
		assert_int(item.state).is_equal(SectorChanges.State.NO_ORIGINAL)
	assert_str(report.text()).contains("has no original").contains("playability checks")
