class_name TestSectorChangesLegacy
extends GdUnitTestSuite
## The report of what changed in a sector against the original, which needs the original's bytes and the hashes of its records: the legacy pack's sectors and a copy of
## one of them changed in memory. (What the report says of a sector of dev, which has no original, is in `tests/engine/test_sector_changes.gd`.)
##
## Teaches: testing a report by changing a sector in memory and reading what the report says. `SectorChanges` (the what-changed report) is
## built on the encoders and the original bytes the fidelity tests use, so these tests make a copy of an original sector, change one
## thing, and look for the sentence that names it; and they run the same report with the original bytes out of reach to see how it
## degrades: it still says WHICH record differs, by hash, and tells the reader to run the importer on their copy of the game.
##
## The tests that need the importer's original bytes skip with a message without them (like the fidelity tests); the others always run.

const NO_ORIGINAL_BYTES := "res://tests/fixtures/no_such_folder/"
const PATCHED_DIR := "user://sector_changes_patched/"
const NEED_THE_IMPORTER := "run tools/import/import_all.py on your copy of the game"

const SECTOR := 3


func after_test() -> void:
	if DirAccess.dir_exists_absolute(PATCHED_DIR):
		for file in DirAccess.get_files_at(PATCHED_DIR):
			DirAccess.remove_absolute(PATCHED_DIR + file)
		DirAccess.remove_absolute(PATCHED_DIR)


## A copy of an original sector that is safe to change: the loaded resources are shared and cached, and `duplicate_deep` only copies
## what the .tres holds inside itself (pieces, creatures), not the screen files or the .foe file.
func _copy_of(index: int = SECTOR) -> SectorData:
	return Catalog.sector(index).duplicate_deep() as SectorData


func _screen_copy(sector: SectorData, m: int) -> ScreenData:
	sector.screens[m] = sector.screens[m].duplicate_deep() as ScreenData
	return sector.screens[m]


func _with_script(sector: SectorData, text: String) -> void:
	sector.foe_script = FoeScript.new()
	sector.foe_script.source = text


func _options(original_dir: String = FixtureHash.ORIGINAL_DIR) -> SectorChanges.Options:
	var options := SectorChanges.Options.new()
	options.source = OriginalBytes.new(original_dir)
	return options


func _skip_without_original_bytes() -> bool:
	if FileAccess.file_exists(FixtureHash.ORIGINAL_DIR + "screens.json") and FileAccess.file_exists(FixtureHash.ORIGINAL_DIR + "sector_headers.json") \
			and FileAccess.file_exists(FixtureHash.ORIGINAL_DIR + "foe_records.json") and FileAccess.file_exists(FixtureHash.ORIGINAL_DIR + "foe_scripts.json"):
		return false
	prints("SKIPPED: %s is missing; %s" % [FixtureHash.ORIGINAL_DIR, NEED_THE_IMPORTER])
	return true


func _item(report: SectorChanges.Report, kind: String, subject: String = "") -> SectorChanges.Item:
	for item in report.items:
		if item.kind == kind and (subject.is_empty() or item.subject == subject):
			return item
	return null


func _details(item: SectorChanges.Item) -> String:
	return "\n".join(item.details)


# --- an unmodified sector is the same as the original ------------------------------------------------------------------

func test_an_unmodified_sector_is_the_same_as_the_original_with_and_without_the_original_bytes() -> void:
	for dir in [FixtureHash.ORIGINAL_DIR, NO_ORIGINAL_BYTES]:
		var report := SectorChanges.report(_copy_of(), _options(dir))
		assert_bool(report.is_same()).override_failure_message(report.text()).is_true()
		for item in report.items:
			assert_int(item.state).override_failure_message("%s:\n%s" % [item.label(), report.text()]).is_equal(SectorChanges.State.SAME)
		assert_str(report.text()).contains("header: same as the original").contains("script: same as the original").contains("screen: all 12 same as the original")
		assert_array(report.notes).is_empty()


func test_every_original_sector_is_the_same_as_the_original() -> void:
	for i in Catalog.ORIGINAL_SECTOR_COUNT:
		var report := SectorChanges.report(Catalog.sector(i), _options(NO_ORIGINAL_BYTES))
		assert_bool(report.is_same()).override_failure_message("sector %d:\n%s" % [i, report.text()]).is_true()


func test_the_shared_tables_are_the_same_as_the_original() -> void:
	for dir in [FixtureHash.ORIGINAL_DIR, NO_ORIGINAL_BYTES]:
		var report := SectorChanges.shared_report(_options(dir))
		assert_bool(report.is_same()).override_failure_message(report.text()).is_true()
		assert_int(report.items.size()).is_equal(2 + 34)


# --- the header ----------------------------------------------------------------------------------------------------------

func test_a_moved_piece_a_changed_neighbour_and_a_new_start_are_named() -> void:
	if _skip_without_original_bytes():
		return
	var sector := _copy_of()
	sector.pieces[4].pos += Vector2i(4, 0)
	sector.neighbors_right[2] = 7
	sector.start_pos.y += 2
	sector.start_frame += 1
	var report := SectorChanges.report(sector, _options())
	var header := _item(report, "header")
	assert_int(header.state).is_equal(SectorChanges.State.CHANGED)
	var details := _details(header)
	var was: Vector2i = Catalog.sector(SECTOR).pieces[4].pos
	assert_str(details).contains("piece 4 moved from (%d, %d) to (%d, %d)" % [was.x, was.y, was.x + 4, was.y])
	assert_str(details).contains("right neighbour of screen 2: ")
	assert_str(details).contains("-> screen 7")
	assert_str(details).contains("start position (").contains("start frame ")
	assert_bool(report.is_same()).is_false()
	assert_str(report.text()).contains("header").contains("differs from the original")


func test_a_piece_on_another_screen_and_an_added_piece_are_named() -> void:
	if _skip_without_original_bytes():
		return
	var sector := _copy_of(0)                      # sector 3 has all 11 piece slots in use
	sector.pieces[2].screen = (sector.pieces[2].screen + 1) % 12
	var extra := PieceData.new()
	extra.screen = 1
	extra.pos = Vector2i(100, 100)
	sector.pieces.append(extra)
	var details := _details(_item(SectorChanges.report(sector, _options()), "header"))
	var count := Catalog.sector(0).pieces.size()
	assert_str(details).contains("piece 2 moved to another screen")
	assert_str(details).contains("piece count %d -> %d" % [count, count + 1])
	assert_str(details).contains("piece %d added: screen 1 at (100, 100)" % count)


func test_a_header_that_does_not_fit_is_reported_not_compared() -> void:
	var sector := _copy_of()
	sector.start_pos = Vector2i(5, 8)
	var header := _item(SectorChanges.report(sector, _options()), "header")
	assert_int(header.state).is_equal(SectorChanges.State.CHANGED)
	assert_str(_details(header)).contains("does not fit the original's header").contains("start x 5 is not on the grid")


func test_without_the_original_bytes_a_changed_header_is_named_by_hash_only() -> void:
	var sector := _copy_of()
	sector.neighbors_up[0] = 5
	var report := SectorChanges.report(sector, _options(NO_ORIGINAL_BYTES))
	var header := _item(report, "header")
	assert_int(header.state).is_equal(SectorChanges.State.CHANGED)
	assert_bool(header.hash_only).is_true()
	assert_str(_details(header)).contains("only the hash is compared").contains(NEED_THE_IMPORTER)
	assert_bool(report.uses_hash_only()).is_true()
	assert_str(report.text()).contains(NEED_THE_IMPORTER)
	assert_bool(_item(report, "creatures").hash_only).is_false()


# --- the creatures -------------------------------------------------------------------------------------------------------

func test_a_changed_creature_is_named_with_its_field() -> void:
	if _skip_without_original_bytes():
		return
	var sector := _copy_of()
	sector.foes[2].pos.x += 4
	sector.foes[2].damage += 1
	sector.foes[5].dormant = not sector.foes[5].dormant
	var report := SectorChanges.report(sector, _options())
	var creatures := _item(report, "creatures")
	var was: Vector2i = Catalog.sector(SECTOR).foes[2].pos
	assert_int(creatures.state).is_equal(SectorChanges.State.CHANGED)
	assert_str(_details(creatures)).contains("creature 2: ").contains("x %d -> %d" % [was.x, was.x + 4]).contains("damage ").contains("creature 5: dormant ")
	assert_str(_details(creatures)).not_contains("creature 3")
	assert_int(_item(report, "script").state).is_equal(SectorChanges.State.SAME)


func test_an_added_and_a_removed_creature_are_named() -> void:
	var sector := _copy_of()
	var count := sector.foes.size()
	var extra := sector.foes[0].duplicate_deep() as FoeData
	sector.foes.append(extra)
	var details := _details(_item(SectorChanges.report(sector, _options(NO_ORIGINAL_BYTES)), "creatures"))
	assert_str(details).contains("creature count %d -> %d" % [count, count + 1]).contains("creature %d added" % count)
	sector = _copy_of()
	sector.foes.pop_back()
	details = _details(_item(SectorChanges.report(sector, _options(NO_ORIGINAL_BYTES)), "creatures"))
	assert_str(details).contains("creature count %d -> %d" % [count, count - 1]).contains("creature %d removed" % (count - 1))


func test_without_the_original_bytes_a_changed_creature_is_named_by_hash_only() -> void:
	var sector := _copy_of()
	sector.foes[4].pos.y += 2
	var creatures := _item(SectorChanges.report(sector, _options(NO_ORIGINAL_BYTES)), "creatures")
	assert_int(creatures.state).is_equal(SectorChanges.State.CHANGED)
	assert_bool(creatures.hash_only).is_true()
	assert_str(_details(creatures)).contains("creature 4 differs").contains(NEED_THE_IMPORTER)
	assert_str(_details(creatures)).not_contains("creature 3")


# --- the script ----------------------------------------------------------------------------------------------------------

func test_a_changed_script_line_is_named_with_its_line_number_and_label() -> void:
	if _skip_without_original_bytes():
		return
	var sector := _copy_of()
	var old_line := "    Move_Foe_Relative_XY -4 -5 0"
	var text := sector.foe_script.source
	var at := text.find(old_line)
	assert_int(at).is_greater(0)
	var line_number := text.substr(0, at).count("\n") + 1
	_with_script(sector, text.replace(old_line, "    Move_Foe_Relative_XY -4 -6 0"))
	var item := _item(SectorChanges.report(sector, _options()), "script")
	assert_int(item.state).is_equal(SectorChanges.State.CHANGED)
	assert_str(_details(item)).contains("line %d" % line_number).contains("Move_Foe_Relative_XY -4 -6 0").contains("was `Move_Foe_Relative_XY -4 -5 0`")
	assert_str(_details(item)).contains("`foe0_ink`")
	assert_str(_details(item)).contains("creature 0's ink")


func test_comments_and_names_do_not_make_a_script_differ() -> void:
	var sector := _copy_of()
	_with_script(sector, sector.foe_script.source + "\n; a comment at the end\n")
	var item := _item(SectorChanges.report(sector, _options(NO_ORIGINAL_BYTES)), "script")
	assert_int(item.state).is_equal(SectorChanges.State.SAME)


func test_a_script_that_does_not_assemble_is_reported_with_its_error() -> void:
	var sector := _copy_of()
	_with_script(sector, sector.foe_script.source + "\n    Bogus_Instruction 3\n")
	var item := _item(SectorChanges.report(sector, _options()), "script")
	assert_int(item.state).is_equal(SectorChanges.State.CHANGED)
	assert_str(_details(item)).contains("does not assemble").contains("Bogus_Instruction")


func test_without_the_original_bytes_a_changed_script_says_that_the_hash_differs_and_how_long_it_is() -> void:
	var sector := _copy_of()
	_with_script(sector, sector.foe_script.source.replace("    Move_Foe_Relative_XY -4 -5 0", "    Move_Foe_Relative_XY -4 -6 0"))
	var item := _item(SectorChanges.report(sector, _options(NO_ORIGINAL_BYTES)), "script")
	assert_int(item.state).is_equal(SectorChanges.State.CHANGED)
	assert_bool(item.hash_only).is_true()
	assert_str(_details(item)).contains("only the hash is compared").contains(NEED_THE_IMPORTER)
	# a script of another length also says how long it is, and how long the original's is
	_with_script(sector, sector.foe_script.source.replace("    Move_Foe_Relative_XY -4 -6 0", "    Move_Foe_Relative_XY -4 -6 0\n    Wait_Next_Tick"))
	item = _item(SectorChanges.report(sector, _options(NO_ORIGINAL_BYTES)), "script")
	assert_str(_details(item)).contains("assembles to 980 bytes").contains("the original has 979 at 511")


# --- the screens ---------------------------------------------------------------------------------------------------------

func test_changed_tiles_and_decos_are_named() -> void:
	if _skip_without_original_bytes():
		return
	var sector := _copy_of()
	var screen := _screen_copy(sector, 5)
	var was_tile := screen.tiles[7 * ScreenData.TILE_COLUMNS + 12]
	screen.tiles[7 * ScreenData.TILE_COLUMNS + 12] = 0x41 if was_tile != 0x41 else 0
	screen.tiles[8 * ScreenData.TILE_COLUMNS + 12] = 0x42 if screen.tiles[8 * ScreenData.TILE_COLUMNS + 12] != 0x42 else 0
	screen.mid_decos[0].pos.x += 4
	var report := SectorChanges.report(sector, _options())
	var item := _item(report, "screen", "screen 5")
	assert_int(item.state).is_equal(SectorChanges.State.CHANGED)
	assert_str(_details(item)).contains("2 tiles changed (columns 12-12, rows 7-8)").contains("(12, 7) ").contains("mid decos entry 0: x ")
	assert_int(_item(report, "screen", "screen 4").state).is_equal(SectorChanges.State.SAME)
	assert_str(report.text()).contains("1 of 12 differ").contains("same as the original: screen 0, screen 1")


func test_an_added_trigger_and_a_removed_deco_are_named() -> void:
	if _skip_without_original_bytes():
		return
	var sector := _copy_of()
	var screen := _screen_copy(sector, 2)
	var trigger := MathTriggerData.new()
	trigger.pos = Vector2i(200, 100)
	trigger.slot = 4
	screen.triggers.append(trigger)
	screen.bg_decos.pop_back()
	var details := _details(_item(SectorChanges.report(sector, _options()), "screen", "screen 2"))
	assert_str(details).contains("math triggers: ").contains("entries; added (x 200, y 100, slot 4")
	assert_str(details).contains("bg decos: ").contains("removed (")


func test_without_the_original_bytes_a_changed_screen_is_named_by_hash_only() -> void:
	var sector := _copy_of()
	var screen := _screen_copy(sector, 9)
	screen.tiles[0] = 0x44 if screen.tiles[0] != 0x44 else 0
	var report := SectorChanges.report(sector, _options(NO_ORIGINAL_BYTES))
	var item := _item(report, "screen", "screen 9")
	assert_int(item.state).is_equal(SectorChanges.State.CHANGED)
	assert_bool(item.hash_only).is_true()
	assert_int(_item(report, "screen", "screen 8").state).is_equal(SectorChanges.State.SAME)
	assert_str(report.text()).contains("screen 9: differs from the original").contains(NEED_THE_IMPORTER)


# --- sprite sizes, the trigger table, levels, problems -------------------------------------------------------------------

func test_a_changed_sprite_size_is_named_by_sprite_and_field() -> void:
	if not FileAccess.file_exists(FixtureHash.ORIGINAL_DIR + "sprite_meta.json"):
		prints("SKIPPED: %ssprite_meta.json is missing; %s" % [FixtureHash.ORIGINAL_DIR, NEED_THE_IMPORTER])
		return
	var options := _options()
	var table := (load(LegacyPack.ROOT + "data/sprite_meta/sprite_meta_common.tres") as SpriteMetaTable).duplicate_deep() as SpriteMetaTable
	var width := table.sizes[3].x
	table.sizes[3].x += 2
	options.overrides["sprite:common"] = table
	var report := SectorChanges.report(Catalog.sector(SECTOR), options)
	var item := _item(report, "sprite meta", "set common")
	assert_int(item.state).is_equal(SectorChanges.State.CHANGED)
	assert_str(_details(item)).contains("sprite 3 width: %d -> %d" % [width, width + 2])
	assert_int(_item(report, "sprite meta", "set ink").state).is_equal(SectorChanges.State.SAME)


func test_a_changed_trigger_table_default_level_and_problem_table_are_named() -> void:
	var options := _options()
	var triggers := Catalog.trigger_table().duplicate_deep() as TriggerTable
	triggers.table[19] = (triggers.table[19] + 1) % 34
	options.overrides["trigger_table"] = triggers
	var zones := Catalog.zones().duplicate_deep() as ZoneTable
	zones.zones[2].default_edu_level_expert = (zones.zones[2].default_edu_level_expert + 1) % 4
	options.overrides["zones"] = zones
	var problem := Catalog.problem_type(3).duplicate_deep() as ProblemType
	assert_int(problem.records.size()).is_greater(0)
	problem.records[0][0] += 1
	options.overrides["problem:3"] = problem
	var report := SectorChanges.shared_report(options)
	var have_bytes := FileAccess.file_exists(FixtureHash.ORIGINAL_DIR + "trigger_table.json")
	assert_int(_item(report, "trigger table").state).is_equal(SectorChanges.State.CHANGED)
	assert_int(_item(report, "default levels").state).is_equal(SectorChanges.State.CHANGED)
	assert_int(_problem_item(report, 3).state).is_equal(SectorChanges.State.CHANGED)
	if have_bytes:
		assert_str(_details(_item(report, "trigger table"))).contains("slot 2, educational level 1, pick 1: problem type ")
		assert_str(_details(_item(report, "default levels"))).contains("Expert zone 2: educational level ")


func _problem_item(report: SectorChanges.Report, type_id: int) -> SectorChanges.Item:
	for item in report.items:
		if item.kind == "problem table" and (item.subject == "type %d" % type_id or item.subject.begins_with("type %d (" % type_id)):
			return item
	return null


# --- deliberate changes, sectors without an original, patched originals ---------------------------------------------------

func test_a_change_on_a_deliberate_list_is_reported_as_deliberate_with_its_reason() -> void:
	var sector := _copy_of()
	sector.neighbors_up[0] = 5
	sector.foes[1].pos.x += 2
	var screen := _screen_copy(sector, 3)
	screen.tiles[0] = 0x44 if screen.tiles[0] != 0x44 else 0
	var options := _options(NO_ORIGINAL_BYTES)
	options.deliberate = SectorChanges.Deliberate.new()
	options.deliberate.header = {SECTOR: "the door to the cave is moved"}
	options.deliberate.foe = {"%d:1" % SECTOR: "the eel starts further right"}
	options.deliberate.screen = {"%d:3" % SECTOR: "a new rock"}
	var report := SectorChanges.report(sector, options)
	assert_bool(report.is_same()).override_failure_message(report.text()).is_true()
	assert_int(_item(report, "header").state).is_equal(SectorChanges.State.DELIBERATE)
	assert_str(_details(_item(report, "header"))).contains("deliberate: the door to the cave is moved")
	assert_int(_item(report, "creatures").state).is_equal(SectorChanges.State.DELIBERATE)
	assert_str(_details(_item(report, "creatures"))).contains("deliberate: the eel starts further right")
	assert_int(_item(report, "screen", "screen 3").state).is_equal(SectorChanges.State.DELIBERATE)
	assert_str(report.text()).contains("differs from the original on purpose")
	# one creature on the list does not excuse another
	sector.foes[2].pos.x += 2
	assert_int(_item(SectorChanges.report(sector, options), "creatures").state).is_equal(SectorChanges.State.CHANGED)


func test_the_deliberate_lists_of_the_fidelity_tests_are_read_from_the_tests() -> void:
	var deliberate := SectorChanges.Deliberate.from_tests()
	assert_dict(deliberate.header).is_equal(TestSectorHeaderFidelity.DELIBERATE_SECTOR_CHANGES)
	assert_dict(deliberate.foe).is_equal(TestFoeRecordFidelity.DELIBERATE_FOE_CHANGES)
	assert_dict(deliberate.foe_script).is_equal(TestFoeAsmLegacy.DELIBERATE_SCRIPT_CHANGES)
	assert_dict(deliberate.screen).is_equal(TestScreenFidelity.DELIBERATE_SCREEN_CHANGES)
	assert_dict(deliberate.sprite).is_equal(TestSpriteMetaFidelity.DELIBERATE_SET_CHANGES)
	assert_str(deliberate.trigger).is_equal(TestTriggerTableFidelity.DELIBERATE_TABLE_CHANGE)
	assert_str(deliberate.zones).is_equal(TestZoneFidelity.DELIBERATE_LEVEL_CHANGE)
	assert_dict(deliberate.problem).is_equal(TestProblemTableFidelity.DELIBERATE_TYPE_CHANGES)


func test_original_bytes_that_are_not_the_ones_the_fixture_hashes_are_not_trusted() -> void:
	# A different release or a patched copy: the importer's file does not match the committed SHA-256, so the report must not compare
	# the sector with it (it would be comparing the sector with itself) and says so.
	var source := FileAccess.get_file_as_string(FixtureHash.ORIGINAL_DIR + "sector_headers.json")
	if source.is_empty():
		prints("SKIPPED: %ssector_headers.json is missing; %s" % [FixtureHash.ORIGINAL_DIR, NEED_THE_IMPORTER])
		return
	DirAccess.make_dir_recursive_absolute(PATCHED_DIR)
	var parsed: Dictionary = JSON.parse_string(source)
	var entry: Dictionary = parsed["sectors"][SECTOR]
	var hex: String = entry["header_hex"]
	entry["header_hex"] = ("ff" if not hex.begins_with("ff") else "00") + hex.substr(2)
	var file := FileAccess.open(PATCHED_DIR + "sector_headers.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(parsed))
	file.close()
	var options := _options(PATCHED_DIR)
	var report := SectorChanges.report(_copy_of(), options)
	assert_bool(report.is_same()).override_failure_message(report.text()).is_true()
	assert_bool(_item(report, "header").hash_only).is_false()           # unchanged header: the hash agrees, no bytes needed
	var changed := _copy_of()
	changed.neighbors_left[1] = 4
	report = SectorChanges.report(changed, _options(PATCHED_DIR))
	assert_bool(_item(report, "header").hash_only).is_true()
	assert_str(report.text()).contains("does not match the SHA-256 committed")
