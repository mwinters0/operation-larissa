class_name TestFoeAsmLegacy
extends GdUnitTestSuite
## Teaches: testing a translator against ground truth. A FIXTURE of HASHES of the original scripts (committed with the tests,
## docs/port/FIDELITY.md "Fixtures commit hashes, not bytes") proves that the stored text assembles to exactly what the
## original game ran; the original bytes themselves are written by the importer from your copy of the game into the
## git-ignored tests/fixtures/original/, and the tests that need them (the first differing byte, the round trip bytes ->
## text -> bytes over the real scripts, the sync with the Python disassembler) skip with a message without them. This is the legacy half of
## `engine/test_foe_asm.gd` (the assembler's own rules, on hand-written scripts and on the dev pack): it runs on the legacy pack, where the
## sectors are the original's.

const FIXTURE := "res://tests/fixtures/foe_scripts.json"

## DELIBERATE CHANGES to the creature scripts of an original sector: sector index -> the reason (a String).
## The stored text in data/sectors/sector_NN/sector_NN.foe is what the game runs and what designers edit in the script editor,
## but the fixture holds the hashes of the ORIGINAL bytes, and the checks "matches the original" below protect that authentic
## data: they FAIL for an edited original sector. A designer who changes a sector on purpose and wants to keep the
## change lists it here, for example   2: "Deliberate deviation: the eel no longer ... (see DESIGN.md 7.4)".
## Listed sectors skip the checks that compare with the original (text equals the disassembly of the original,
## bytes hash to the fixture, entry offsets equal the original). They must still COMPILE without errors, and the
## structural checks keep running. The project's convention for this is the "Deliberate deviation" in
## docs/port/FIDELITY.md: mark the code/data change, a test and docs/port/DESIGN.md with that phrase.
## To go back to the original instead, run tools/import/reset_foe_scripts.py (docs/create/FOE_SCRIPTING.md).
## (`SectorChanges` reads this constant out of this file by its path.)
const DELIBERATE_SCRIPT_CHANGES := {}


func _is_deliberate(sector_index: int) -> bool:
	return DELIBERATE_SCRIPT_CHANGES.has(sector_index)


## The committed fixture written by tools/import/step_sectors.py from the ORIGINAL extracted data: per sector the
## provenance of its foe buffer, the offset and size of the script in it and the SHA-256 of the whole script.
func _fixture() -> Array:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return parsed["sectors"]


## True (after saying why) when the original script bytes cannot be used, for the tests that need them: the importer has
## not written them, which is a skip, or they are not the ones the committed hashes are of, which fails the test.
func _skip_without_original_bytes() -> bool:
	if not FoeAnnotations.has_original_bytes():
		prints("SKIPPED: %s" % FoeAnnotations.original_problem())
		return true
	assert_str(FoeAnnotations.original_problem()).is_empty()
	return not FoeAnnotations.original_problem().is_empty()


func test_fixture_covers_every_sector_with_its_provenance_and_holds_no_bytes() -> void:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_array(parsed.keys()).contains_exactly_in_any_order(["comment", "sectors"])
	assert_int(_fixture().size()).is_equal(Catalog.ORIGINAL_SECTOR_COUNT)
	for i in _fixture().size():
		var entry: Dictionary = _fixture()[i]
		assert_int(int(entry["index"])).is_equal(i)
		assert_str(entry["source"]["file"]).is_equal("NEP.DLL")
		assert_array(entry.keys()).contains_exactly_in_any_order(["index", "source", "offset", "size", "sha256"])
		assert_int(String(entry["sha256"]).length()).is_equal(64)
		assert_array(FoeAnnotations.original_sectors()).contains(i)


func test_every_original_sector_compiles_without_errors() -> void:
	# Also for the sectors listed in DELIBERATE_SCRIPT_CHANGES: a changed script must still be valid.
	for sector_index in Catalog.ORIGINAL_SECTOR_COUNT:
		var sector := Catalog.sector(sector_index)
		assert_array(sector.compile_errors).override_failure_message("sector %d: %s" % [sector_index, sector.compile_errors.slice(0, 3)]).is_empty()
		assert_int(sector.foe_bytecode.size()).override_failure_message("sector %d compiled to no bytes" % sector_index).is_greater(0)


func test_stored_text_assembles_to_bytes_with_the_hash_of_the_original() -> void:
	for entry in _fixture():
		if _is_deliberate(int(entry["index"])):
			continue
		var sector := Catalog.sector(int(entry["index"]))
		var where := "sector %d (edited on purpose? list it in DELIBERATE_SCRIPT_CHANGES, or reset it with tools/import/reset_foe_scripts.py)" % entry["index"]
		assert_array(sector.compile_errors).override_failure_message(where).is_empty()
		assert_int(sector.foe_script_base).override_failure_message(where + " base").is_equal(int(entry["offset"]))
		assert_int(sector.foe_bytecode.size()).override_failure_message(where + " size").is_equal(int(entry["size"]))
		if FixtureHash.sha256_hex(sector.foe_bytecode) == entry["sha256"]:
			continue
		var text := where + ": the assembled bytes differ from the original; run tools/import/import_all.py on your copy of the game to see where"
		if FoeAnnotations.has_original_bytes() and FoeAnnotations.original_problem().is_empty():
			var original := FoeAnnotations.original(int(entry["index"]))["script"] as PackedByteArray
			var at := 0
			while at < mini(original.size(), sector.foe_bytecode.size()) and original[at] == sector.foe_bytecode[at]:
				at += 1
			text = where + ": the assembled bytes differ from the original, first at script byte %d (buffer offset %d; the original has %d bytes, the text %d)" % [at, int(entry["offset"]) + at, original.size(), sector.foe_bytecode.size()]
		assert_bool(false).override_failure_message(text).is_true()


func test_the_entry_points_of_the_creatures_are_the_original_ones() -> void:
	# (The records, entry points included, are also hashed: tests/legacy/test_foe_record_fidelity.gd.)
	if _skip_without_original_bytes():
		return
	for index in FoeAnnotations.original_sectors():
		if _is_deliberate(index):
			continue
		var original := FoeAnnotations.original(index)
		var sector := Catalog.sector(index)
		var offsets: Array = original["offsets"]
		var where := "sector %d (edited on purpose? list it in DELIBERATE_SCRIPT_CHANGES, or reset it with tools/import/reset_foe_scripts.py)" % index
		assert_bool(sector.foe_bytecode == original["script"]).override_failure_message(where + ": the assembled bytes differ from the original").is_true()
		assert_int(sector.foes.size()).override_failure_message(where + " foe count").is_equal(offsets.size())
		for i in offsets.size():
			var foe := sector.foes[i]
			assert_int(foe.pc).override_failure_message("%s foe %d start" % [where, i]).is_equal(offsets[i][0])
			assert_int(foe.script_hit).override_failure_message("%s foe %d hit" % [where, i]).is_equal(offsets[i][1])
			assert_int(foe.script_ink).override_failure_message("%s foe %d ink" % [where, i]).is_equal(offsets[i][2])


func test_disassembling_the_original_bytes_round_trips() -> void:
	if _skip_without_original_bytes():
		return
	for index in FoeAnnotations.original_sectors():
		var original := FoeAnnotations.original(index)
		var script: PackedByteArray = original["script"]
		var base: int = original["base"]
		var entries: Dictionary = original["entries"]
		var result := FoeAsm.assemble(FoeAsm.disassemble(script, base, entries), base)
		assert_array(result.errors).override_failure_message("sector %d: %s" % [index, result.errors.slice(0, 3)]).is_empty()
		assert_bool(result.bytes == script).override_failure_message("sector %d does not round-trip" % index).is_true()
		# Only the first name at a shared place is printed, but every entry point has a label.
		var label_offsets := result.labels.values()
		for name in entries:
			assert_bool(label_offsets.has(entries[name])).override_failure_message("sector %d: nothing labels %s" % [index, name]).is_true()


func test_the_python_and_gdscript_disassemblers_agree() -> void:
	# tools/import/foe_text.py wrote the stored text (with the designers' names and comments from the
	# annotation store); this disassembler must print the same.
	if _skip_without_original_bytes():
		return
	var store := _store()
	for index in FoeAnnotations.original_sectors():
		if _is_deliberate(index):
			continue
		var sector := Catalog.sector(index)
		var original := FoeAnnotations.original(index)
		var text := FoeAsm.disassemble(original["script"], original["base"], original["entries"], FoeAnnotations.for_sector(store, index), FoeNames.for_sector(sector))
		assert_bool(text == sector.foe_script.source).override_failure_message(_out_of_sync(index)).is_true()


func _out_of_sync(sector_index: int) -> String:
	return ("sector %d: the text in sector_%02d.foe is not what the disassembler writes from the original bytes plus data/sectors/foe_annotations.json. "
			+ "If you renamed labels or wrote comments, store them: press \"Store names & comments\" in the Foe Script screen, or run  uv run tools/import/harvest_foe_annotations.py %d  "
			+ "(a deliberate change of the instructions belongs in DELIBERATE_SCRIPT_CHANGES; to go back to the original run tools/import/reset_foe_scripts.py %d)") % [sector_index, sector_index, sector_index, sector_index]


func _store() -> Dictionary:
	var parsed := FoeAnnotations.load_store()
	assert_str(parsed.error).override_failure_message("data/sectors/foe_annotations.json: " + parsed.error).is_empty()
	return parsed.store


func test_every_original_sector_text_equals_the_disassembly_of_the_original_bytes_and_the_store() -> void:
	if _skip_without_original_bytes():
		return
	# The sync test: nothing in a .foe file that the store does not hold (and the other way round).
	var store := _store()
	for index in FoeAnnotations.original_sectors():
		if _is_deliberate(index):
			continue
		var original := FoeAnnotations.original(index)
		var expected := FoeAsm.disassemble(original["script"], original["base"], original["entries"], FoeAnnotations.for_sector(store, index), FoeNames.for_sector(Catalog.sector(index)))
		var stored := LegacyPack.played_foe_text(index)
		assert_bool(stored == expected).override_failure_message(_out_of_sync(index)).is_true()


func test_the_store_only_holds_original_sectors() -> void:
	for index in _store():
		assert_bool(FoeAnnotations.has_original(index)).override_failure_message("foe_annotations.json holds sector %d, which has no original script" % index).is_true()


func test_the_stored_text_has_one_label_per_place() -> void:
	for sector_index in Catalog.ORIGINAL_SECTOR_COUNT:
		var lines := Catalog.sector(sector_index).foe_script.source.split("\n")
		for n in range(1, lines.size()):
			assert_bool(lines[n].ends_with(":") and lines[n - 1].ends_with(":")).override_failure_message("sector %d line %d: two labels in a row" % [sector_index, n + 1]).is_false()


func test_foes_that_share_a_place_name_the_same_label() -> void:
	if _skip_without_original_bytes():
		return
	var sector := Catalog.sector(0)
	# Most creatures of sector 0 only Return when touched: they all point at the one label.
	var shared := 0
	for foe in sector.foes:
		if foe.hit_label == sector.foes[0].hit_label:
			shared += 1
	assert_int(shared).is_greater(10)
	# The label is "foe0_hit" unless the designers renamed it (data/sectors/foe_annotations.json).
	var original := FoeAnnotations.original(0)
	var expected: String = FoeAsm.entry_labels(original["offsets"], FoeAnnotations.for_sector(_store(), 0))[0][1]
	assert_str(sector.foes[0].hit_label).is_equal(expected)


func test_sector_zero_names_entries_and_jump_targets() -> void:
	var text := FoeAsm.disassemble_sector(Catalog.sector(0))
	assert_str(text).starts_with("foe0_hit:")   # a hit script comes first in the buffer
	assert_str(text).contains("\n    ")
	assert_str(text).contains("loc_")


func test_sector_zero_starts_like_the_designers_model() -> void:
	if _skip_without_original_bytes():
		return
	var original := FoeAnnotations.original(0)
	var text := FoeAsm.disassemble(original["script"], original["base"], original["entries"])
	assert_str(text).starts_with("foe0_hit:\n    Return\n    Padding 9\n\nfoe0_ink:")
	assert_int(text.count("    Padding ")).is_equal(14)
	assert_int(text.count(FoeAsm.UNEXECUTED_UNUSED)).is_equal(1)
	assert_bool(text.contains("they are padding")).is_false()


func test_every_dead_instruction_of_every_sector_is_padding_or_under_a_comment_and_no_live_one_is() -> void:
	if _skip_without_original_bytes():
		return
	for index in FoeAnnotations.original_sectors():
		var original := FoeAnnotations.original(index)
		var base: int = original["base"]
		var decoded := FoeAsm.decode(original["script"], base)
		var alive := FoeAsm.reachable(decoded, original["entries"].values())
		var notes := FoeAsm.unexecuted_notes(original["script"], base, original["entries"])
		var spans := FoeAsm.padding_spans(original["script"], base, original["entries"].values())
		var padded: Dictionary = {}
		for start in spans:
			for at in range(start, start + int(spans[start])):
				padded[at] = true
				assert_int(original["script"][at - base]).override_failure_message("sector %d: padding at %d is not a zero byte" % [index, at]).is_equal(0)
				assert_bool(alive.has(at)).override_failure_message("sector %d: padding at %d is reachable" % [index, at]).is_false()
		var names := FoeAsm.generated_names(original["script"], base, original["entries"])
		var covered := false
		for item in decoded:
			var at: int = item["at"]
			if alive.has(at):
				assert_bool(notes.has(at)).override_failure_message("sector %d offset %d: a comment on a live instruction" % [index, at]).is_false()
				covered = false
			elif not padded.has(at):
				covered = (covered and not names.has(at)) or notes.has(at)
				assert_bool(covered).override_failure_message("sector %d offset %d is dead and has no comment" % [index, at]).is_true()


func test_every_sector_text_has_as_many_bytes_as_the_script() -> void:
	if _skip_without_original_bytes():
		return
	for index in FoeAnnotations.original_sectors():
		var original := FoeAnnotations.original(index)
		var size := 0
		for line in FoeAsm.disassemble(original["script"], original["base"], original["entries"]).split("\n"):
			var words := line.split(";")[0].strip_edges().split(" ", false)
			if words.is_empty() or words[0].ends_with(":"):
				continue
			if words[0] == "Padding":
				size += int(words[1])
			else:
				size += 1 + FoeOps.OPERAND_COUNT[FoeOps.op_from_mnemonic(words[0])]
		assert_int(size).override_failure_message("sector %d" % index).is_equal(original["script"].size())


func test_the_original_sectors_have_no_unsuppressed_dead_code_warnings() -> void:
	if _skip_without_original_bytes():
		return
	# The generated comments say the dead code is meant; remove them and every run warns.
	for index in FoeAnnotations.original_sectors():
		var sector := Catalog.sector(index)
		var source := sector.foe_script.source
		var labels := FoeAsm.sector_entry_labels(sector)
		var result := FoeAsm.assemble(source, sector.foe_script_base, FoeNames.for_sector(sector))
		assert_array(result.errors).is_empty()
		assert_array(FoeAsm.dead_code_warnings(source, result, labels)).override_failure_message("sector %d" % index).is_empty()
		var original := FoeAnnotations.original(index)
		var runs := FoeAsm.unexecuted_notes(original["script"], original["base"], original["entries"]).size()
		var bare_lines: PackedStringArray = []
		for line in source.split("\n"):
			if not line.strip_edges().begins_with(FoeAsm.UNEXECUTED_COMMENT_PREFIX):
				bare_lines.append(line)
		var bare := "\n".join(bare_lines)
		var bare_result := FoeAsm.assemble(bare, sector.foe_script_base, FoeNames.for_sector(sector))
		assert_int(FoeAsm.dead_code_warnings(bare, bare_result, labels).size()).override_failure_message("sector %d" % index).is_equal(runs)
