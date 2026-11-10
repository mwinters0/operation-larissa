class_name TestFoeAnnotations
extends GdUnitTestSuite
## Teaches: testing two implementations of one format against each other. The importer's
## Python (tools/import/foe_annotations.py) and FoeAnnotations/FoeAsm write and read the
## same store file and the same text; the example in tests/fixtures/foe_annotations_example
## is checked by BOTH test suites (this one and tools/import/test_foe_annotations.py), so
## neither can drift: the file must come out byte for byte, the hand-edited text must
## harvest to exactly the stored notes, and the notes must disassemble back to exactly the text.

const EXAMPLE := "res://tests/fixtures/foe_annotations_example/"

## A made-up creature script (one creature) that stands for "the original bytes" of a sector in the tests below: the harvest compares a text with
## bytes, and a test only needs bytes it knows. `_probe()` assembles it; the entry labels are the generated `foe0_start`, `foe0_hit` and `foe0_ink`.
const PROBE := "start:\n    Set_Frame 32\nagain:\n    Move_Foe_Relative_XY 2 0 1\n    Loop_Counter2_Back_To again 9\n    Jump_To start\nhit:\n    Return\n    Padding 3\nink:\n    Wait_Next_Tick\n    Return\n"
const PROBE_BASE := 35


## What `FoeAnnotations.original(index)` answers for a sector, from the made-up script of `PROBE`.
func _probe() -> Dictionary:
	var assembled := FoeAsm.assemble(PROBE, PROBE_BASE)
	assert_array(assembled.errors).is_empty()
	var labels: Dictionary = assembled.labels
	return _original_of(assembled.bytes, PROBE_BASE, [[labels["start"], labels["hit"], labels["ink"]]])


## The same for the compiled script of a sector of the chain (its creatures' entry points are the offsets).
func _of_sector(index: int) -> Dictionary:
	var sector := Catalog.sector(index)
	var offsets: Array = []
	for foe in sector.foes:
		offsets.append([foe.pc, foe.script_hit, foe.script_ink])
	return _original_of(sector.foe_bytecode, sector.foe_script_base, offsets)


func _original_of(script: PackedByteArray, base: int, offsets: Array) -> Dictionary:
	return {"script": script, "base": base, "offsets": offsets, "entries": FoeAsm.entry_names(offsets)}


func _example_json() -> String:
	return FileAccess.get_file_as_string(EXAMPLE + "foe_annotations.json")


func _example_text() -> String:
	return FileAccess.get_file_as_string(EXAMPLE + "sector_03_annotated.txt")


func _harvest(original: Dictionary, text: String) -> FoeAnnotations.Harvest:
	return FoeAnnotations.harvest(text, original["script"], original["base"], original["entries"])


func _plain(original: Dictionary) -> String:
	return FoeAsm.disassemble(original["script"], original["base"], original["entries"])


# --- the file ----------------------------------------------------------------

func test_the_example_is_in_the_standard_layout() -> void:
	var path := EXAMPLE + "foe_annotations.json"
	var text := FileAccess.get_file_as_string(path)
	var parsed := FoeAnnotations.parse(text)
	assert_str(parsed.error).is_empty()
	assert_bool(FoeAnnotations.stringify(parsed.store) == text).override_failure_message(path + " is not what stringify writes").is_true()


func test_offsets_are_sorted_as_numbers() -> void:
	var store := FoeAnnotations.parse(_example_json()).store
	assert_array(store[3]["labels"].keys()).contains_exactly([511, 529, 535])
	assert_int(store[3]["comments"].keys()[-1]).is_equal(1490)       # as text "1490" would come before "511"


func test_special_characters_survive_the_file() -> void:
	var note := {"above": ["    ; quote \" backslash \\ tab \t café → bell \u0007"], "inline": "; \"x\""}
	var store := {1: {"labels": {10: "a_b"}, "comments": {10: note}}}
	var text := FoeAnnotations.stringify(store)
	assert_str(text).contains("→")
	var back := FoeAnnotations.parse(text)
	assert_str(back.error).is_empty()
	assert_dict(back.store).is_equal(store)


func test_an_empty_store_has_no_sectors() -> void:
	assert_str(FoeAnnotations.stringify({})).contains('"sectors": {}')
	assert_dict(FoeAnnotations.parse(FoeAnnotations.stringify({})).store).is_empty()


func test_a_malformed_store_reports_an_error() -> void:
	for bad in ['{"sectors": {"1": {"labels": {"5": "no good"}}}}',
			'{"sectors": {"1": {"labels": {"5": "a", "6": "a"}}}}',
			'{"sectors": {"1": {"comments": {"5": {"bogus": ["x"]}}}}}',
			'{"sectors": {"1": {"comments": {"5": {"above": "no list"}}}}}',
			'{"sectors": {"1": {"comments": {"5": {}}}}}', "not json"]:
		assert_bool(FoeAnnotations.parse(bad).ok()).override_failure_message(bad).is_false()


# --- harvest: the same answers as the Python one -----------------------------

func test_a_generated_text_has_nothing_to_store() -> void:
	var originals: Array[Dictionary] = [_probe()]
	for index in Catalog.sector_ids():
		if not Catalog.sector(index).foes.is_empty():
			originals.append(_of_sector(index))
	for original in originals:
		var result := _harvest(original, _plain(original))
		assert_bool(result.ok).override_failure_message(result.problem).is_true()
		assert_bool(result.labels.is_empty() and result.comments.is_empty()).is_true()
		assert_bool(result.text == _plain(original)).is_true()


func test_the_generated_text_of_the_probe_is_the_text_one_expects() -> void:
	var offsets: Array = _probe()["offsets"][0]
	assert_str(_plain(_probe())).is_equal("foe0_start:\n    Set_Frame 32\n\nloc_%d:\n    Move_Foe_Relative_XY 2 0 1\n    Loop_Counter2_Back_To loc_%d 9\n    Jump_To foe0_start\n\nfoe0_hit:\n    Return\n    Padding 3\n\nfoe0_ink:\n    Wait_Next_Tick\n    Return\n" % [PROBE_BASE + 2, PROBE_BASE + 2])
	assert_int(offsets[0]).is_equal(PROBE_BASE)


func test_the_text_comes_back_in_the_standard_layout() -> void:
	var original := _probe()
	var plain := _plain(original)
	var messy := plain.replace("    Return\n", "    return  ;x\n").replace("foe0_ink:", "  foe0_ink:").trim_suffix("\n")
	var result := _harvest(original, messy)
	assert_bool(result.ok).is_true()
	assert_str(result.text).contains("    Return  ;x\n").contains("\nfoe0_ink:\n")
	assert_bool(result.text.ends_with("\n")).is_true()
	assert_bool(_harvest(original, result.text).text == result.text).is_true()


func test_comments_attach_to_the_following_line_and_blank_lines_are_exact() -> void:
	var original := _probe()
	var plain := _plain(original)
	var text := plain.replace("\nfoe0_ink:\n    Wait_Next_Tick\n", "\n; about the label\nfoe0_ink:\n; between\n    Wait_Next_Tick  ; same line\n")
	var result := _harvest(original, text)
	assert_bool(result.ok and result.text == text).is_true()
	var ink: int = original["offsets"][0][2]
	assert_dict(result.comments).is_equal({ink: {"label_above": ["", "; about the label"], "above": ["; between"], "inline": "; same line"}})
	var tight := _harvest(original, plain.replace("\n\nfoe0_ink:", "\nfoe0_ink:"))
	assert_bool(tight.ok).is_true()
	assert_array(tight.comments[ink]["label_above"]).is_empty()


func test_comments_at_the_end_of_the_file() -> void:
	var original := _probe()
	var end: int = original["base"] + original["script"].size()
	var result := _harvest(original, _plain(original) + "; the end\n\n; trailer\n")
	assert_bool(result.ok).is_true()
	assert_dict(result.comments).is_equal({end: {"above": ["; the end", "", "; trailer"]}})


func test_a_text_whose_instructions_differ_from_the_original_is_refused() -> void:
	var original := _probe()
	var plain := _plain(original)
	for bad in [plain.replace("    Set_Frame 32\n", "    Set_Frame 99\n"), plain.replace("    Return\n", ""), plain + "    Return\n",
			plain.replace("    Return\n", "    Frobnicate\n"), plain.replace("Loop_Counter2_Back_To loc_%d" % (PROBE_BASE + 2), "Loop_Counter2_Back_To foe0_ink")]:
		var result := _harvest(original, bad)
		assert_bool(result.ok).is_false()
		assert_str(result.problem).is_not_empty()


func test_two_labels_at_one_place_a_duplicate_name_and_a_lost_entry_label_are_refused() -> void:
	var original := _probe()
	var plain := _plain(original)
	assert_str(_harvest(original, plain.replace("foe0_ink:\n", "foe0_ink:\nextra:\n")).problem).contains("label the same place")
	assert_str(_harvest(original, plain.replace("loc_%d:\n" % (PROBE_BASE + 2), "foe0_ink:\n")).problem).contains("duplicate label")
	assert_bool(_harvest(original, plain.replace("\nfoe0_ink:\n", "\n")).ok).is_false()


# --- the generated "not executed" comment and the store ---------------------------------

const DEAD_SCRIPT := [FoeOps.Op.RET, 0, 0, FoeOps.Op.JMP, 0xFD, 0xFF]     # 1, 2 zero bytes (Padding 2); 3 Jump_To 3, dead; a label splits the run
const DEAD_ENTRIES := {"start": 0}


func _dead_text() -> String:
	return "start:\n    Return\n    Padding 2\n\nloc_3:\n%s\n    Jump_To loc_3\n" % FoeAsm.UNEXECUTED_UNUSED


func _dead_harvest(text: String) -> FoeAnnotations.Harvest:
	return FoeAnnotations.harvest(text, PackedByteArray(DEAD_SCRIPT), 0, DEAD_ENTRIES)


func test_the_generated_comment_is_the_default_text_and_not_stored() -> void:
	assert_str(FoeAsm.disassemble(PackedByteArray(DEAD_SCRIPT), 0, DEAD_ENTRIES)).is_equal(_dead_text())
	var result := _dead_harvest(_dead_text())
	assert_str(result.problem).is_empty()
	assert_bool(result.ok).is_true()
	assert_dict(result.labels).is_empty()
	assert_dict(result.comments).is_empty()
	assert_bool(result.text == _dead_text()).is_true()


func test_a_stored_comment_above_replaces_the_generated_one() -> void:
	var mine := _dead_text().replace(FoeAsm.UNEXECUTED_UNUSED, "    ; my own words")
	var result := _dead_harvest(mine)
	assert_bool(result.ok).is_true()
	assert_dict(result.comments).is_equal({3: {"above": ["    ; my own words"]}})
	assert_bool(result.text == mine).is_true()
	assert_bool(mine.contains("not executed")).is_false()
	assert_bool(FoeAsm.disassemble(PackedByteArray(DEAD_SCRIPT), 0, DEAD_ENTRIES, result.annotations()) == mine).is_true()


func test_a_stored_empty_above_removes_the_generated_comment() -> void:
	var bare := _dead_text().replace(FoeAsm.UNEXECUTED_UNUSED + "\n", "")
	var result := _dead_harvest(bare)
	assert_bool(result.ok).is_true()
	assert_dict(result.comments).is_equal({3: {"above": []}})
	assert_bool(result.text == bare).is_true()
	assert_bool(FoeAsm.disassemble(PackedByteArray(DEAD_SCRIPT), 0, DEAD_ENTRIES, result.annotations()) == bare).is_true()
	var file := FoeAnnotations.stringify({7: result.annotations()})
	assert_str(file).contains('"above": []')
	assert_dict(FoeAnnotations.parse(file).store).is_equal({7: result.annotations()})


func test_lines_added_to_the_generated_comment_are_stored_with_it() -> void:
	var longer := _dead_text().replace(FoeAsm.UNEXECUTED_UNUSED + "\n", FoeAsm.UNEXECUTED_UNUSED + "\n    ; and more\n")
	var result := _dead_harvest(longer)
	assert_bool(result.ok).is_true()
	assert_dict(result.comments).is_equal({3: {"above": [FoeAsm.UNEXECUTED_UNUSED, "    ; and more"]}})
	assert_bool(FoeAsm.disassemble(PackedByteArray(DEAD_SCRIPT), 0, DEAD_ENTRIES, result.annotations()) == longer).is_true()


func test_other_notes_at_a_commented_position_leave_the_generated_comment_alone() -> void:
	var text := _dead_text().replace("    Padding 2\n", "    Padding 2  ; x\n")
	var result := _dead_harvest(text)
	assert_bool(result.ok).is_true()
	assert_dict(result.comments).is_equal({1: {"inline": "; x"}})
	assert_bool(FoeAsm.disassemble(PackedByteArray(DEAD_SCRIPT), 0, DEAD_ENTRIES, result.annotations()) == text).is_true()


func test_a_name_given_to_a_label_does_not_change_where_the_comments_go() -> void:
	var result := _dead_harvest(_dead_text().replace("loc_3", "again"))
	assert_bool(result.ok).is_true()
	assert_dict(result.comments).is_empty()
	assert_dict(result.labels).is_equal({3: "again"})


# --- Padding in the harvest --------------------------------------------------


const PAD_SCRIPT := [FoeOps.Op.RET, 0, 0, 0, 0, FoeOps.Op.JMP, 0xFD, 0xFF]     # 1..4 zero bytes, 5 Jump_To 5 (dead)


func _pad_harvest(text: String, script: Array = PAD_SCRIPT) -> FoeAnnotations.Harvest:
	return FoeAnnotations.harvest(text, PackedByteArray(script), 0, {"start": 0})


func test_a_padding_line_covers_its_bytes_and_labels_and_comments_attach_to_its_first_offset() -> void:
	var text := "start:\n    Return\n    ; about the padding\n    Padding 4  ; filler\n\nloc_5:\n%s\n    Jump_To loc_5\n" % FoeAsm.UNEXECUTED_UNUSED
	var result := _pad_harvest(text)
	assert_str(result.problem).is_empty()
	assert_dict(result.comments).is_equal({1: {"above": ["    ; about the padding"], "inline": "; filler"}})
	assert_dict(result.names).is_equal({0: "start", 5: "loc_5"})              # loc_5 is at offset 5: 1 + 4 bytes of padding
	assert_bool(result.text == text).is_true()


func test_padding_counts_as_that_many_zero_bytes_in_the_instructions_match_check() -> void:
	for middle in ["    Padding 4", "    Padding 1\n    Padding 3", "    Wait_Next_Tick\n    Padding 3", "    padding\n    PADDING 3",
			"    Wait_Next_Tick\n    Wait_Next_Tick\n    Wait_Next_Tick\n    Wait_Next_Tick"]:
		var text := "start:\n    Return\n%s\n\nloc_5:\n%s\n    Jump_To loc_5\n" % [middle, FoeAsm.UNEXECUTED_UNUSED]
		var result := _pad_harvest(text)
		assert_str(result.problem).override_failure_message(middle).is_empty()
		assert_dict(result.labels).is_empty()
		assert_dict(result.comments).is_empty()
		assert_bool(result.text.contains("    Padding 4\n") and not result.text.contains("Wait_Next_Tick")).is_true()    # the standard layout


func test_padding_that_does_not_match_the_original_bytes_is_refused() -> void:
	var head := "start:\n    Return\n"
	var tail := "\nloc_5:\n    Jump_To loc_5\n"
	assert_bool(_pad_harvest(head + "    Padding 3" + tail).ok).is_false()                # one byte short: the label is no longer at 5
	assert_str(_pad_harvest(head + "    Padding 5" + tail).problem).contains("Padding 5")
	assert_str(_pad_harvest("start:\n    Return\n    Hide_Foe\n    Padding 3" + tail).problem).contains("the original has 'Wait_Next_Tick' here, the text has 'Hide_Foe'")
	assert_str(_pad_harvest("start:\n    Padding 2\n", [FoeOps.Op.RET, FoeOps.Op.SHOW]).problem).contains("the original has 'Return' here, the text has 'Padding 2'")
	assert_str(_pad_harvest("start:\n    Return\n    Padding 2\n", [FoeOps.Op.RET, 0]).problem).contains("the end of the script")


func test_a_bad_padding_count_is_refused() -> void:
	for operands in ["0", "65536", "-1", "x", "3 4", "2.5", "+2"]:
		var result := _pad_harvest("start:\n    Return\n    Padding %s\n" % operands, [FoeOps.Op.RET, 0, 0])
		assert_bool(result.ok).override_failure_message(operands).is_false()
		assert_str(result.problem).override_failure_message(operands).starts_with("line 3: Padding takes one count")


func test_a_stored_label_or_comment_inside_zero_bytes_cuts_the_padding_there() -> void:
	var script := PackedByteArray([FoeOps.Op.RET, 0, 0, 0, 0])
	var annotations := {"labels": {3: "middle"}, "comments": {2: {"above": ["    ; here"]}}}
	var cut := FoeAsm.disassemble(script, 0, {"start": 0}, annotations)
	var result := FoeAnnotations.harvest(cut, script, 0, {"start": 0})
	assert_str(result.problem).is_empty()
	assert_dict(result.annotations()).is_equal(annotations)
	assert_bool(result.text == cut).is_true()


func test_random_annotations_survive_disassemble_then_harvest() -> void:
	var rng := RandomNumberGenerator.new()
	for index in [DevCreatures.ARENA, DevCreatures.FISH, -1]:                    # (-1: the made-up probe)
		rng.seed = index + 2
		var original := _probe() if index < 0 else _of_sector(index)
		var base: int = original["base"]
		var positions: Array = []
		for item in FoeAsm.decode(original["script"], base):
			positions.append(item["at"])
		positions.append(base + original["script"].size())
		var generated := FoeAsm.generated_names(original["script"], base, original["entries"])
		var labels: Dictionary = {}
		for at in positions:
			if (generated.has(at) and rng.randf() < 0.3) or (not generated.has(at) and rng.randf() < 0.02):
				labels[at] = "named_%d" % at
		var shown: Array = generated.keys() + labels.keys()
		var first: int = shown.min()
		var comments: Dictionary = {}
		for at in positions:
			var note: Dictionary = {}
			if rng.randf() < 0.15:
				note["above"] = [["    ; c"], ["", "; two"], [""]][rng.randi() % 3]
			if at != positions[-1] and rng.randf() < 0.15:
				note["inline"] = ["; x", " ; one space", "    ; wide"][rng.randi() % 3]
			if shown.has(at) and at != first and rng.randf() < 0.2:
				note["label_above"] = [[], ["", "; head"], ["; tight"]][rng.randi() % 3]
			if shown.has(at) and rng.randf() < 0.2:
				note["label_inline"] = "; lbl"
			if not note.is_empty():
				var ordered: Dictionary = {}
				for key in FoeAnnotations.NOTE_KEYS:
					if note.has(key):
						ordered[key] = note[key]
				comments[at] = ordered
		var annotations := {"labels": labels, "comments": comments}
		var text := FoeAsm.disassemble(original["script"], base, original["entries"], annotations)
		var result := _harvest(original, text)
		assert_bool(result.ok).override_failure_message("sector %d: %s" % [index, result.problem]).is_true()
		assert_bool(result.text == text).is_true()
		var labels_back: Dictionary = result.labels
		assert_array(labels_back.keys()).is_equal(_sorted_keys(labels))
		assert_int(result.comments.size()).is_equal(comments.size())
		for at in comments:
			assert_dict(result.comments[at]).is_equal(comments[at])


func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys


# --- the names reach the creatures' entry labels -----------------------------

func test_entry_labels_follow_renamed_labels() -> void:
	var original := _probe()
	var plain: Array = FoeAsm.entry_labels(original["offsets"])
	assert_str(plain[0][1]).is_equal("foe0_hit")
	var annotations := {"labels": {original["offsets"][0][1]: "touch_return"}, "comments": {}}
	var renamed: Array = FoeAsm.entry_labels(original["offsets"], annotations)
	assert_str(renamed[0][0]).is_equal("foe0_start")
	assert_str(renamed[0][1]).is_equal("touch_return")
	assert_str(renamed[0][2]).is_equal("foe0_ink")


func test_the_tres_label_fields_can_be_renamed_or_set() -> void:
	var tres := FileAccess.get_file_as_string(Catalog.sector_path(DevCreatures.ARENA))
	var renamed := FoeAnnotations.rename_entry_label(tres, "quiet_hit", "touch_return")
	assert_str(renamed).contains('hit_label = "touch_return"')
	assert_bool(renamed.contains('hit_label = "quiet_hit"')).is_false()
	assert_bool(renamed.replace("touch_return", "quiet_hit") == tres).is_true()           # nothing else changed
	var labels: Array = FoeAnnotations.read_entry_labels(tres)
	assert_int(labels.size()).is_equal(DevCreatures.CREATURES)
	assert_bool(FoeAnnotations.set_entry_labels(tres, labels) == tres).is_true()
	assert_str(FoeAnnotations.set_entry_labels(tres, labels.slice(1))).is_empty()        # wrong creature count


func test_sector_numbers_come_from_the_file_name() -> void:
	assert_int(FoeAnnotations.sector_of_path(Catalog.foe_path(7))).is_equal(7)
	assert_int(FoeAnnotations.sector_of_path("user://sector_40.tres")).is_equal(40)
	assert_int(FoeAnnotations.sector_of_path("user://notes.foe")).is_equal(-1)
	assert_bool(FoeAnnotations.has_original(40)).is_false()
