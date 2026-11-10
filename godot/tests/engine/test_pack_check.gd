class_name TestPackCheck
extends GdUnitTestSuite
## Teaches: validating a pack is ONE function (`PackCheck.run`) that answers with a report, and that function looks at the pack the way the game will:
## the pack is made the chosen pack for the check, so the sectors are judged by the playability checks as the game reads them, the campaign by `Campaign.problems`, the
## names by the real lookups. Errors stop a pack, warnings do not. Every pack here is a scratch DATA pack in `user://` (`PackShelf`) made of copies of
## the dev pack's sectors 0, 1 and 180 (test data built at run time, never committed), with one thing wrong at a time.

const ID := &"orchard_pack"
const BOX := &"orchard_box"
const TONE_SHORT := "res://tests/fixtures/pack_tone_short.ogg.bin"

var _shelves: Array[PackShelf] = []


func after_test() -> void:
	for shelf in _shelves:
		shelf.remove()
	_shelves.clear()
	Packs.start()
	Durations.use_base()


## A pack called `pack_id` with a campaign `campaign_id` of the sectors `first`, `first + 1` and the finale `first + 2` (copies of dev's 0, 1 and 180).
func _orchard(pack_id: StringName = BOX, first := 40, campaign_id: StringName = ID, base: StringName = &"") -> PackShelf:
	var shelf := PackShelf.new(pack_id, base)
	_shelves.append(shelf)
	shelf.add_sector_copy(0, first)
	shelf.add_sector_copy(1, first + 1)
	shelf.add_sector_copy(DevPack.test_sector("e", 0), first + 2)
	shelf.write_json("campaigns/%s.json" % campaign_id, {
		"class": "Campaign", "id": String(campaign_id), "title": "Orchard of Packs", "sectors": [first, first + 1], "finales": [first + 2],
		"default_edu_levels": [0, 1], "log_unlock_order": [2, 1], "finale_log_counts": [2], "log_texts": ["Apples.", "Pears."], "log_voices": ["", ""],
		"supply_texts": ["Well picked.", "Well picked again."], "supply_voices": ["", ""], "finale_text": "The orchard is yours.",
	})
	return shelf


func _quick() -> PackCheck.Options:
	var options := PackCheck.Options.new()
	options.reach = false
	return options


func _check(shelf: PackShelf, options: PackCheck.Options = null) -> PackReport:
	return PackCheck.run(Pack.open(shelf.root), options if options != null else _quick())


func _errors(report: PackReport) -> String:
	return "\n".join(report.findings.map(func(f: PackReport.Finding) -> String: return f.text()))


## True when some finding of the given severity mentions `fragment`.
func _has(report: PackReport, severity: PackReport.Severity, fragment: String) -> bool:
	for finding in report.findings:
		if finding.severity == severity and (finding.message.contains(fragment) or finding.area.contains(fragment)):
			return true
	return false


# --- a sound pack -----------------------------------------------------------------------------------------------------------------

func test_a_sound_pack_passes_and_the_report_says_what_it_holds() -> void:
	var report := _check(_orchard())
	assert_bool(report.passes()).override_failure_message(_errors(report)).is_true()
	assert_array(report.errors()).is_empty()
	assert_array(report.campaigns).is_equal([ID])
	assert_array(report.sectors).is_equal([40, 41, 42])
	assert_str(report.summary()).starts_with("orchard_box:")
	assert_str(report.text()).contains("campaigns orchard_pack").contains("sectors 40, 41, 42")


func test_checking_a_pack_leaves_the_chain_in_use_as_it_was() -> void:
	var other := _orchard(&"other_box", 50, &"other_pack")
	other.mount()
	var shelf := _orchard()
	_check(shelf)
	assert_bool(Packs.in_chain(BOX)).is_false()                                         # it was not in use before
	assert_array(Packs.chain_ids()).is_equal([&"other_box", PackShelf.base_id()])
	# the chosen pack is checked where it is and stays
	var chosen := shelf.mount()
	var report := PackCheck.run(chosen, _quick())
	assert_bool(report.passes()).override_failure_message(_errors(report)).is_true()
	assert_array(Packs.chain_ids()).is_equal([BOX, PackShelf.base_id()])


func test_a_different_pack_of_the_same_id_is_checked_in_its_own_chain_and_the_chain_in_use_comes_back() -> void:
	var first := _orchard(BOX, 40)
	first.mount()
	var second := _orchard(BOX, 60, &"orchard_two")                                     # another folder, same id as the chosen one
	var report := _check(second)
	assert_bool(report.passes()).override_failure_message(_errors(report)).is_true()
	assert_str(Packs.chosen().root).is_equal(first.root)


func test_a_base_that_is_missing_or_absent_is_an_error() -> void:
	var lost := _orchard(&"lost_box", 40, ID, &"ghost")
	var report := _check(lost)
	assert_bool(report.passes()).is_false()
	assert_bool(_has(report, PackReport.Severity.ERROR, "'ghost', which is not installed")).is_true()
	var bare := _orchard(&"bare_box", 40, ID)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(bare.root + "/pack.json"))
	manifest.erase("base")
	bare.write_json("pack.json", manifest)
	var alone := _check(bare)                                                           # (no base: it is complete, so it is asked for everything, and nothing crashes on the trigger table it lacks)
	assert_bool(alone.passes()).is_false()
	assert_bool(_has(alone, PackReport.Severity.ERROR, "that neither this pack nor the packs under it hold")).is_true()
	assert_bool(_has(alone, PackReport.Severity.ERROR, "data/trigger_table.tres")).is_true()


# --- the manifest and the layout --------------------------------------------------------------------------------------------------

func test_manifest_errors_are_errors_and_stop_the_check() -> void:
	var shelf := _orchard()
	shelf.write_json("pack.json", {"id": "Not An Id", "title": ""})
	var report := _check(shelf)
	assert_bool(report.passes()).is_false()
	assert_bool(_has(report, PackReport.Severity.ERROR, "manifest")).is_true()
	assert_bool(report.errors().all(func(f: PackReport.Finding) -> bool: return f.area == "manifest")).is_true()      # (nothing else is read)
	var missing := PackReport.new()
	missing = PackCheck.run(Pack.open("user://no_such_pack_folder"))
	assert_bool(missing.passes()).is_false()


func test_the_layout_rules_of_pack_problems_are_errors() -> void:
	var shelf := _orchard()
	shelf.write_text("scripts/evil.gd", "extends Node")                                 # code in an untrusted pack
	shelf.write_text("data/zones.tres", "x")                                            # a data file a pack may not replace
	var report := _check(shelf)
	assert_bool(_has(report, PackReport.Severity.ERROR, "evil.gd")).is_true()
	assert_bool(_has(report, PackReport.Severity.ERROR, "data/zones.tres")).is_true()


func test_a_pack_that_holds_nothing_is_a_warning_not_an_error() -> void:
	var shelf := PackShelf.new(&"empty_box")
	_shelves.append(shelf)
	var report := _check(shelf)
	assert_bool(report.passes()).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "holds nothing")).is_true()


# --- other packs ----------------------------------------------------------------------------------------------------------------

func test_a_pack_laid_over_another_may_hold_the_same_sector_numbers_and_campaign_id() -> void:
	var first := _orchard(BOX, 40)
	var over := _orchard(&"over_box", 41, ID, BOX)                                       # sectors 41-43 overlap 41, 42; the same campaign id: it replaces them
	var report := _check(over)
	assert_bool(report.passes()).override_failure_message(_errors(report)).is_true()


func test_a_pack_may_remake_a_sector_and_a_campaign_of_the_pack_under_it() -> void:
	var shelf := _orchard()
	shelf.add_sector_copy(1, 2)                                                          # sector 2 of the dev pack, remade
	shelf.write_json("campaigns/%s.json" % DevPack.TOUR, {"class": "Campaign", "id": String(DevPack.TOUR), "title": "x", "sectors": [40], "default_edu_levels": [0]})
	var report := _check(shelf)
	assert_bool(_has(report, PackReport.Severity.ERROR, "would hide it")).is_false()
	assert_bool(_has(report, PackReport.Severity.ERROR, "conflict")).is_false()


# --- the sectors and the campaign -------------------------------------------------------------------------------------------------

func test_a_sector_that_fails_the_playability_checks_is_an_error_of_that_sector() -> void:
	var shelf := _orchard()
	var sector := SectorJson.read(shelf.pack if shelf.pack != null else Pack.open(shelf.root), 41)
	sector.start_pos = Vector2i(-50, 3000)                                              # the start is outside the screen
	shelf.add_sector(sector)
	var report := _check(shelf)
	assert_bool(report.passes()).is_false()
	var found := report.errors().filter(func(f: PackReport.Finding) -> bool: return f.area == "sector 41")
	assert_array(found).is_not_empty()
	assert_bool(report.errors().any(func(f: PackReport.Finding) -> bool: return f.area == "sector 40")).is_false()     # the others are fine
	assert_bool(_check(shelf, _no_sectors()).passes()).override_failure_message("without the sector checks the pack is not judged on its sectors").is_true()


func _no_sectors() -> PackCheck.Options:
	var options := PackCheck.Options.new()
	options.sectors = false
	return options


func test_a_creature_script_that_does_not_assemble_is_an_error() -> void:
	var shelf := _orchard()
	shelf.write_text(SectorJson.foe_rel(40), "this is not a creature script\n")
	var report := _check(shelf)
	assert_bool(report.errors().any(func(f: PackReport.Finding) -> bool: return f.area == "sector 40")).is_true()


func test_a_missing_creature_script_and_a_misnumbered_sector_file_are_errors() -> void:
	var shelf := _orchard()
	DirAccess.remove_absolute("%s/%s" % [shelf.root, SectorJson.foe_rel(41)])
	var misnumbered: Dictionary = shelf_json(shelf, 42)
	misnumbered["index"] = 7
	shelf.write_json(SectorJson.json_rel(42), misnumbered)
	var report := _check(shelf)
	assert_bool(_has(report, PackReport.Severity.ERROR, "no creature script")).is_true()
	assert_bool(_has(report, PackReport.Severity.ERROR, "says it is sector 7")).is_true()


func shelf_json(shelf: PackShelf, index: int) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [shelf.root, SectorJson.json_rel(index)]))


func test_json_the_game_cannot_read_is_an_error_with_the_field_named() -> void:
	var shelf := _orchard()
	var broken: Dictionary = shelf_json(shelf, 40)
	broken["no_such_field"] = 1
	shelf.write_json(SectorJson.json_rel(40), broken)
	shelf.write_json("campaigns/%s.json" % ID, {"class": "Campaign", "id": String(ID), "title": 4, "sektors": [40]})
	var report := _check(shelf)
	assert_bool(_has(report, PackReport.Severity.ERROR, "no field 'no_such_field'")).is_true()
	assert_bool(_has(report, PackReport.Severity.ERROR, "no field 'sektors'")).is_true()
	assert_bool(_has(report, PackReport.Severity.ERROR, "title should be text")).is_true()
	shelf.write_text("texts.json", "{not json")
	assert_bool(_has(_check(shelf), PackReport.Severity.ERROR, "texts.json line")).is_true()


func test_a_campaign_that_is_not_playable_or_not_self_contained_is_an_error() -> void:
	var shelf := _orchard()
	shelf.write_json("campaigns/%s.json" % ID, {"class": "Campaign", "id": String(ID), "title": "Orchard", "sectors": [40, 41, 77, 3], "finales": [42],
			"default_edu_levels": [0], "log_unlock_order": [1], "log_texts": ["x"], "log_voices": [""], "supply_texts": ["a", "b", "c", "d"], "supply_voices": ["", "", "", ""],
			"finale_log_counts": [1]})
	var report := _check(shelf)
	assert_bool(_has(report, PackReport.Severity.ERROR, "sector 77 is not in this pack, nor in the packs it is laid over")).is_true()
	assert_bool(_has(report, PackReport.Severity.ERROR, "also in the campaign 'dev_tour'")).is_true()


func test_warnings_do_not_stop_a_pack() -> void:
	var shelf := _orchard()
	shelf.add_sector_copy(0, 45)                                                        # in no campaign
	var cued: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/campaigns/%s.json" % [shelf.root, ID]))
	cued["log_voices"] = ["no_such_group", ""]
	cued["closing_scene"] = "pirate"
	cued["fallback_song"] = "no_such_song"
	shelf.write_json("campaigns/%s.json" % ID, cued)
	var report := _check(shelf)
	assert_bool(report.passes()).override_failure_message(_errors(report)).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "no campaign of this pack lists it")).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "voice group 'no_such_group' has no clips")).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "closing_scene 'pirate'")).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "fallback_song 'no_such_song'")).is_true()


# --- names, pictures, clips ---------------------------------------------------------------------------------------------------------

func test_a_voice_group_names_clips_the_game_or_the_pack_has() -> void:
	var shelf := _orchard()
	shelf.write_json("voice_cues.json", {"groups": {"apples": ["sign_in_begin_0", "my_line", "ghost_line"]}})
	shelf.write_bytes("audio/voice/my_line.ogg", FileAccess.get_file_as_bytes(TONE_SHORT))
	var report := _check(shelf)
	assert_bool(_has(report, PackReport.Severity.ERROR, "the voice 'ghost_line'")).is_true()
	assert_bool(_has(report, PackReport.Severity.ERROR, "'my_line'")).is_false()
	assert_bool(_has(report, PackReport.Severity.ERROR, "'sign_in_begin_0'")).is_false()
	shelf.write_json("voice_cues.json", {"groups": {"apples": "not a list"}})
	assert_bool(_has(_check(shelf), PackReport.Severity.ERROR, "must be a list of voice names")).is_true()


func test_a_picture_that_is_not_a_png_is_an_error_and_odd_files_are_warnings() -> void:
	var shelf := _orchard()
	shelf.add_picture("pictures/ui_picture/fine_one.png", Color.RED)
	shelf.write_text("pictures/ui_picture/liar.png", "not a picture")
	shelf.write_text("pictures/ui_picture/notes.txt", "x")
	shelf.add_picture("pictures/wallpaper/sea.png", Color.BLUE)
	var report := _check(shelf)
	assert_bool(_has(report, PackReport.Severity.ERROR, "liar.png is not a PNG")).is_true()
	assert_bool(_has(report, PackReport.Severity.ERROR, "fine_one")).is_false()
	assert_bool(_has(report, PackReport.Severity.WARNING, "notes.txt: only .png")).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "pictures/wallpaper")).is_true()


func test_clip_warnings_of_g2a_are_warnings() -> void:
	var shelf := _orchard()
	shelf.write_bytes("audio/voice/my_line.ogg", FileAccess.get_file_as_bytes(TONE_SHORT))
	shelf.write_json("audio/lengths.json", {"voice": {"my_line": 700, "ghost": 5}})        # 0.6 s of tone stated as 9.6 s; a clip the pack lacks
	shelf.write_bytes("audio/voice/Loud Line.ogg", FileAccess.get_file_as_bytes(TONE_SHORT))
	shelf.write_text("audio/voice/sound.mp3", "x")
	shelf.write_text("audio/jingles/x.ogg", "x")
	var report := _check(shelf)
	assert_bool(report.passes()).override_failure_message(_errors(report)).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "states 700 ticks")).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "'ghost' states a length but the pack has no")).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "Loud Line")).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "only .ogg")).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "audio/jingles")).is_true()


func test_a_picture_file_that_the_campaign_names_must_exist() -> void:
	var shelf := _orchard()
	var named: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/campaigns/%s.json" % [shelf.root, ID]))
	named["finale_picture"] = "orchard_sunset"
	shelf.write_json("campaigns/%s.json" % ID, named)
	assert_bool(_has(_check(shelf), PackReport.Severity.ERROR, "finale_picture 'orchard_sunset'")).is_true()
	shelf.add_picture("pictures/ui_picture/orchard_sunset.png", Color.ORANGE)
	assert_bool(_check(shelf).passes()).is_true()


# --- durations ----------------------------------------------------------------------------------------------------------------------

func test_a_durations_file_is_checked_for_known_keys_and_sensible_values() -> void:
	var shelf := _orchard()
	shelf.write_json(Durations.PACK_PATH, {"dissolve": {"ticks": 30}, "fade": {"ticks": 7}, "station": {"dock": {"opening_ticks": 6}}})
	assert_bool(_check(shelf).passes()).is_true()
	shelf.write_json(Durations.PACK_PATH, {"dissolv": {"ticks": 30}, "fade": {"tiks": 7}, "problem": 5, "sign_in": {"pre_scan_ticks": 2.5},
			"station": {"dock": {"pixels_per_tick": 0, "opening_ticks": -1, "from_x": 500, "to_x": 400}, "balloon": {"from_y": -50, "to_y": 100}}, "news": {"group_pauses": [0, -3, "x"]}})
	var report := _check(shelf)
	for fragment in ["dissolv: no such duration", "fade.tiks: no such duration", "problem is a section", "sign_in.pre_scan_ticks must be a whole number", "pixels_per_tick is 0: it must be 1 or more",
			"opening_ticks is -1: it must be 0 or more", "from_x (500) is right of to_x (400)", "balloon: from_y (-50) is above to_y (100)", "group_pauses must be a whole number"]:
		assert_bool(_has(report, PackReport.Severity.ERROR, fragment)).override_failure_message("no error about '%s':\n%s" % [fragment, _errors(report)]).is_true()
	shelf.write_json(Durations.PACK_PATH, {"fade": {"ticks": 0}, "dissolve": {"ticks": 99999}, "station": {"launch": {"from_x": 10, "to_x": 10}, "balloon": {"x": 9000}}, "news": {"group_pauses": [0, 1]}})
	report = _check(shelf)
	assert_bool(_has(report, PackReport.Severity.ERROR, "fade.ticks is 0: it must be 1 or more")).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "longer than ten minutes")).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "the sub does not drive")).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "more than a window away")).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "has 2 entries, the game's has 5")).is_true()
	shelf.write_text(Durations.PACK_PATH, "[1, 2]")
	assert_bool(_has(_check(shelf), PackReport.Severity.ERROR, "must be a JSON object")).is_true()


func test_durations_check_on_its_own_accepts_the_base_file_and_a_note() -> void:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	Durations.check(JSON.parse_string(FileAccess.get_file_as_string(Durations.BASE_PATH)), errors, warnings)
	assert_array(errors).is_empty()
	assert_array(warnings).is_empty()
	Durations.check({"_about": "a note", "fade": {"ticks": 20}}, errors, warnings)
	assert_array(errors).is_empty()


# --- rule values --------------------------------------------------------------------------------------------------------------------

func test_a_tuning_file_is_checked_for_known_keys_and_values_the_rules_can_run_with() -> void:
	var shelf := _orchard()
	shelf.write_json(Tuning.PACK_PATH, {"air": {"max_oxygen": 4, "max_tanks": 3}, "ink": {"max": 12}, "sub": {"max_speed_x_units": 160}})
	var report := _check(shelf)
	assert_bool(report.passes()).override_failure_message(_errors(report)).is_true()
	assert_array(report.warnings()).override_failure_message(_errors(report)).is_empty()
	shelf.write_json(Tuning.PACK_PATH, {"air": {"max_oxigen": 5, "max_tanks": 2.5}, "ink": 3, "lock_wheel": {"ticks_per_position": 0},
			"sub": {"cell_after_left": [0, 1], "cell_after_up": [2, 1, 1, 3, 4, 5, 7, 7, 9]}, "sector": {"midpoint_screen": 12}})
	report = _check(shelf)
	for fragment in ["air.max_oxigen: no such rule value", "air.max_tanks must be a whole number", "ink is a section", "lock_wheel.ticks_per_position is 0: it must be 1 or more",
			"sub.cell_after_left has 2 entries, the game's has 9", "sub.cell_after_up has the entry 9", "sector.midpoint_screen is 12: it must be 11 or less"]:
		assert_bool(_has(report, PackReport.Severity.ERROR, fragment)).override_failure_message("no error about '%s':\n%s" % [fragment, _errors(report)]).is_true()
	assert_bool(report.passes()).is_false()
	shelf.write_json(Tuning.PACK_PATH, {"sub": {"max_speed_x_units": 900}, "air": {"max_tanks": 1}})
	report = _check(shelf)
	assert_bool(report.passes()).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "sub.max_speed_x_units is 900")).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "air.refill_tanks (2) is above air.max_tanks (1)")).is_true()
	shelf.write_text(Tuning.PACK_PATH, "{\"air\": ")
	assert_bool(_has(_check(shelf), PackReport.Severity.ERROR, "rules/tuning.json line")).is_true()
	shelf.write_text(Tuning.PACK_PATH, "[1, 2]")
	assert_bool(_has(_check(shelf), PackReport.Severity.ERROR, "must be a JSON object")).is_true()


func test_a_pack_that_holds_only_rule_values_holds_something() -> void:
	var shelf := PackShelf.new(&"only_values")
	_shelves.append(shelf)
	shelf.write_json(Tuning.PACK_PATH, {"air": {"max_oxygen": 5}})
	var report := _check(shelf)
	assert_bool(report.passes()).override_failure_message(_errors(report)).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "holds nothing")).is_false()
