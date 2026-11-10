class_name TestSectorChecksLegacy
extends GdUnitTestSuite
## The playability checks on the original's 32 sectors: they all pass, with the few findings that are simply how the original is (`SectorChecks.ORIGINAL_ALLOWED`,
## each with its reason); the one-way doors of sector 7; the finale 30 is not asked for pieces; the checks that compare with the original's records (the most
## creatures of any original sector, the longest original script). The checks on dev's sectors are in `tests/engine/test_sector_checks.gd`.
##
## The 32 originals are searched once, side by side on the worker threads, and the tests below read the result.

static var _original_findings: Array = []
static var _seconds: float = 0.0


func before() -> void:
	var sectors: Array[SectorData] = []
	for i in Catalog.ORIGINAL_SECTOR_COUNT:
		sectors.append(Catalog.sector(i))
	var started := Time.get_ticks_msec()
	_original_findings = SectorChecks.check_many(sectors)
	_seconds = (Time.get_ticks_msec() - started) / 1000.0
	prints("playability checks of %d sectors with the reachability search: %.1f s" % [sectors.size(), _seconds])


## A copy of an original sector that is safe to change: the loaded resources are shared and cached, and `duplicate_deep` copies only
## what the .tres holds inside itself (pieces, creatures), not the screen files or the .foe file, which are replaced when changed.
func _copy_of(index: int = 0) -> SectorData:
	return Catalog.sector(index).duplicate_deep() as SectorData


func _screen_copy(sector: SectorData, m: int) -> ScreenData:
	sector.screens[m] = sector.screens[m].duplicate_deep() as ScreenData
	return sector.screens[m]


func _options(reach: bool) -> SectorChecks.Options:
	var options := SectorChecks.Options.new()
	options.reach = reach
	return options


## The findings with this check id (an Array of CheckFinding).
func _of(found: Array[CheckFinding], check_id: String) -> Array[CheckFinding]:
	var out: Array[CheckFinding] = []
	for finding in found:
		if finding.check == check_id:
			out.append(finding)
	return out


func _texts(found: Array[CheckFinding]) -> String:
	return SectorChecks.text(found)


## One finding with this check id, severity and a message that contains `part`; fails the test with all findings listed otherwise.
func _expect(found: Array[CheckFinding], check_id: String, severity: CheckFinding.Severity, part: String) -> CheckFinding:
	for finding in found:
		if finding.check == check_id and finding.severity == severity and (finding.object + " " + finding.message).contains(part):
			return finding
	assert_bool(false).override_failure_message("expected a %s finding [%s] containing '%s', got:\n%s" % [CheckFinding.SEVERITY_NAMES[severity], check_id, part, _texts(found)]).is_true()
	return null


## A screen whose tiles are all solid rock, except the box of tiles columns 15-25, rows 6-11 (playfield (240, 96) to (416, 192)).
func _rock_with_pocket(sector: SectorData, m: int, pocket: bool) -> void:
	var screen := _screen_copy(sector, m)
	for i in ScreenData.TILE_BYTES:
		screen.tiles[i] = 0x41
	if pocket:
		for row in range(6, 12):
			for column in range(15, 26):
				screen.tiles[row * ScreenData.TILE_COLUMNS + column] = 0


# --- the originals ---------------------------------------------------------------------------------------------------

func test_all_32_original_sectors_pass_the_playability_checks() -> void:
	assert_int(_original_findings.size()).is_equal(Catalog.ORIGINAL_SECTOR_COUNT)
	var problems: Array[String] = []
	for i in _original_findings.size():
		for finding: CheckFinding in SectorChecks.failures(_original_findings[i]):
			problems.append(finding.text())
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()



func test_the_allow_list_holds_exactly_the_findings_the_originals_have() -> void:
	# Every entry must still match a finding (a reason that matches nothing is stale), and every allowed finding must be in the list.
	var in_list := 0
	for sector: int in SectorChecks.ORIGINAL_ALLOWED:
		in_list += SectorChecks.ORIGINAL_ALLOWED[sector].size()
		var matched := 0
		for finding: CheckFinding in _original_findings[sector]:
			if not finding.allowed.is_empty():
				matched += 1
		assert_int(matched).override_failure_message("sector %d: %d allow-list entries, %d allowed findings" % [sector, SectorChecks.ORIGINAL_ALLOWED[sector].size(), matched]).is_equal(SectorChecks.ORIGINAL_ALLOWED[sector].size())
		for entry: Dictionary in SectorChecks.ORIGINAL_ALLOWED[sector]:
			assert_str(str(entry["reason"])).is_not_empty()
	var allowed := 0
	for found: Array in _original_findings:
		for finding: CheckFinding in found:
			if not finding.allowed.is_empty():
				allowed += 1
	assert_int(allowed).is_equal(in_list)
	assert_int(allowed).is_equal(5)



func test_the_original_one_way_doors_are_reported_but_allowed() -> void:
	var seven: Array[CheckFinding] = []
	seven.assign(_original_findings[7])
	assert_int(_of(seven, "link.one_way").size()).is_equal(2)
	for finding in _of(seven, "link.one_way"):
		assert_int(finding.severity).is_equal(CheckFinding.Severity.WARNING)
		assert_str(finding.allowed).is_not_empty()
		assert_bool(finding.fails()).is_false()
	assert_str(SectorChecks.summary(seven)).is_equal("0 errors, 0 warnings, 2 allowed, 0 notes")
	var thirty_one: Array[CheckFinding] = []
	thirty_one.assign(_original_findings[31])
	var piece := _expect(thirty_one, "reach.piece", CheckFinding.Severity.ERROR, "piece 0")
	assert_str(piece.allowed).contains("pocket of the start station")



func test_a_finale_is_not_asked_for_pieces_or_for_all_its_screens() -> void:
	var thirty: Array[CheckFinding] = []
	thirty.assign(_original_findings[30])
	assert_bool(SectorChecks.passes(thirty)).is_true()
	for finding in _of(thirty, "link.unreachable"):
		assert_int(finding.severity).is_equal(CheckFinding.Severity.INFO)



func test_findings_are_data_with_a_severity_a_check_a_sector_and_a_place() -> void:
	var finding := _expect(_original_findings[7], "link.one_way", CheckFinding.Severity.WARNING, "right link")
	assert_int(finding.sector).is_equal(7)
	assert_int(finding.screen).is_equal(4)
	assert_str(finding.object).is_equal("right link")
	assert_str(finding.text()).starts_with("warning: sector 7 screen 4 right link:").contains("[link.one_way]").contains("allowed, the original is like this")



func test_more_creatures_than_any_original_sector_is_a_warning() -> void:
	var sector := _copy_of(3)
	var most := OriginalBytes.new().max_creatures()
	while sector.foes.size() <= most:
		sector.foes.append(sector.foes[0].duplicate_deep() as FoeData)
	var found := SectorChecks.check(sector, _options(false))
	_expect(found, "creature.count", CheckFinding.Severity.WARNING, "at most %d" % most)
	_expect(found, "script.base", CheckFinding.Severity.WARNING, "the script follows the %d creature records" % sector.foes.size())



func test_a_script_longer_than_any_original_script_is_a_warning() -> void:
	var sector := _copy_of(3)
	sector.foe_script = FoeScript.new()
	sector.foe_script.source = Catalog.sector(3).foe_script.source + "\nfiller:\n    Padding 65535\n"
	_expect(SectorChecks.check(sector, _options(false)), "script.size", CheckFinding.Severity.WARNING, "longer than any original script")
