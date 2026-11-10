class_name TestSectorOverviewLegacy
extends GdUnitTestSuite
## The overview of the original's 32 sectors: which of them have one-way links, links that cannot be drawn between neighbouring cells, and screens nothing leads to.
## The layout and the other parts of the overview, on dev's sectors, are in `tests/engine/test_sector_overview.gd`.
##
## The findings about the ORIGINAL data that are not bugs are named in the constants below, so that the suite stays green until something new
## turns up (the same way `test_sector_reachability_legacy.gd` keeps its `KNOWN_ONE_WAY_NEIGHBOURS`).

## Links of the original's neighbour tables that are not a plain two-way link between neighbouring screens, per sector: the number of one-way
## links (adjacent, but the other side does not lead back) and of links that cannot be drawn between neighbouring cells. Sector 7: screen 4 leads
## right to 9, which leads left to 5 (not back to 4). Sector 13: screen 3 leads up to 7, but 7 leads down to 8. Sector 15: screen 7 leads left to
## 4, which has no right neighbour. (All three are the `KNOWN_ONE_WAY_NEIGHBOURS` of `test_sector_reachability.gd`.)
const KNOWN_ONE_WAY := {7: 1, 15: 1}
const KNOWN_MISPLACED := {7: 1, 13: 1}
## Screens no link leads to or from, per sector: the finales have screens that are empty and never visited (30: 5-11, 31: 11).
const KNOWN_DETACHED := {30: [5, 6, 7, 8, 9, 10, 11], 31: [11]}



func test_the_original_sectors_have_the_known_problems_and_no_others() -> void:
	for index in Catalog.ORIGINAL_SECTOR_COUNT:
		var layout := SectorLayout.from_sector(Catalog.sector(index))
		assert_int(layout.one_way_links().size()).override_failure_message("sector %d: one-way links %s" % [index, layout.report()]).is_equal(KNOWN_ONE_WAY.get(index, 0))
		var misplaced := layout.conflicts().size()
		assert_int(misplaced).override_failure_message("sector %d: conflicting links %s" % [index, layout.report()]).is_equal(KNOWN_MISPLACED.get(index, 0))
		assert_array(layout.detached()).override_failure_message("sector %d: detached screens" % index).is_equal(KNOWN_DETACHED.get(index, []))
		# what is wrong is always in the report: a view that prints it hides nothing
		assert_int(layout.report().size()).is_equal(layout.detached().size() + misplaced + layout.one_way_links().size())



func test_most_original_sectors_are_clean_maps() -> void:
	var clean := 0
	for index in Catalog.ORIGINAL_SECTOR_COUNT:
		if SectorLayout.from_sector(Catalog.sector(index)).report().is_empty():
			clean += 1
	assert_int(clean).is_equal(Catalog.ORIGINAL_SECTOR_COUNT - 5)        # all but 7, 13, 15 (links) and 30, 31 (unused screens): the known tables above



func test_the_report_says_which_screen_is_in_the_way() -> void:
	# sector 7: screen 9 leads left to 5, but the cell left of 9 is the one screen 4 sits in
	var report := "\n".join(SectorLayout.from_sector(Catalog.sector(7)).report())
	assert_str(report).contains("screen 9, left -> screen 5").contains("where screen 4 sits")
