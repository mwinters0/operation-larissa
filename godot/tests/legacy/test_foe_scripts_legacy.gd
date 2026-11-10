class_name TestFoeScriptsLegacy
extends GdUnitTestSuite
## Teaches: the legacy half of the creature-script tests: what only the original's scripts can prove. The annotation store and its example are
## the harvest of the ORIGINAL sector 3 (the engine half, `engine/test_foe_annotations.gd`, runs the same code on made-up bytes), the names the
## importer wrote into the stored texts are the registry's, "Store names & comments" works on an original sector and refuses a text whose
## instructions differ from the original's, every original sector written only with names assembles to the original bytes, and the one creature
## of sector 14 whose hit script ends its own interrupt (G42).

const EXAMPLE := "res://tests/fixtures/foe_annotations_example/"
const TEMP_DIR := "user://foe_names_test"
const TEMP_A := "user://foe_script_editor_a.foe"

var _panel: FoeEditorPanel


func before_test() -> void:
	_panel = FoeEditorPanel.new()
	add_child(_panel)


func after_test() -> void:
	_panel.free()
	_clear_temp_dir()


func _clear_temp_dir() -> void:
	if not DirAccess.dir_exists_absolute(TEMP_DIR):
		return
	for file_name in DirAccess.get_files_at(TEMP_DIR):
		DirAccess.remove_absolute(TEMP_DIR + "/" + file_name)
	DirAccess.remove_absolute(TEMP_DIR)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## A scratch copy of sector `index` (its .foe and .tres) in user://, named like sector `as_index`.
func _sector_copy(index: int, as_index: int) -> FoeScript:
	DirAccess.make_dir_recursive_absolute(Catalog.sector_dir(as_index, TEMP_DIR))
	_write(Catalog.sector_path(as_index, TEMP_DIR), FileAccess.get_file_as_string(Catalog.sector_path(index, LegacyPack.SECTORS_DIR)))       # (the authoring files of the project's legacy folder)
	_write(Catalog.foe_path(as_index, TEMP_DIR), FileAccess.get_file_as_string(Catalog.foe_path(index, LegacyPack.SECTORS_DIR)))
	return ResourceLoader.load(Catalog.foe_path(as_index, TEMP_DIR), "", ResourceLoader.CACHE_MODE_REPLACE) as FoeScript


func _example_json() -> String:
	return FileAccess.get_file_as_string(EXAMPLE + "foe_annotations.json")


func _example_text() -> String:
	return FileAccess.get_file_as_string(EXAMPLE + "sector_03_annotated.txt")


func _harvest(index: int, text: String) -> FoeAnnotations.Harvest:
	var original := FoeAnnotations.original(index)
	return FoeAnnotations.harvest(text, original["script"], original["base"], original["entries"])


func _plain(index: int) -> String:
	var original := FoeAnnotations.original(index)
	return FoeAsm.disassemble(original["script"], original["base"], original["entries"])


## True (after saying why) when the original script bytes cannot be used, for the tests that need them: the importer has
## not written them, which is a skip, or they are not the ones the committed hashes are of, which fails the test.
func _skip_without_original_bytes() -> bool:
	if not FoeAnnotations.has_original_bytes():
		prints("SKIPPED: %s" % FoeAnnotations.original_problem())
		return true
	assert_str(FoeAnnotations.original_problem()).is_empty()
	return not FoeAnnotations.original_problem().is_empty()


func test_the_committed_store_and_the_example_are_in_the_standard_layout() -> void:
	for path in [FoeAnnotations.STORE_PATH, EXAMPLE + "foe_annotations.json"]:
		var text := FileAccess.get_file_as_string(path)
		var parsed := FoeAnnotations.parse(text)
		assert_str(parsed.error).is_empty()
		assert_bool(FoeAnnotations.stringify(parsed.store) == text).override_failure_message(path + " is not what stringify writes").is_true()


func test_the_example_text_harvests_to_the_example_store_and_back() -> void:
	if _skip_without_original_bytes():
		return
	var text := _example_text()
	var expected: Dictionary = FoeAnnotations.parse(_example_json()).store[3]
	var result := _harvest(3, text)
	assert_str(result.problem).is_empty()
	assert_bool(result.ok).is_true()
	assert_str(FoeAnnotations.stringify({3: result.annotations()})).is_equal(_example_json())
	assert_bool(result.text == text).override_failure_message("the example is not in the standard layout").is_true()
	var original := FoeAnnotations.original(3)
	assert_bool(FoeAsm.disassemble(original["script"], original["base"], original["entries"], expected) == text).is_true()


## The committed store reads without error and holds only original sectors (0-31): sectors made from scratch have
## no original bytes and therefore no annotations. (Whether each entry matches its `.foe` is test_foe_asm.gd's job.)
func test_the_committed_store_is_valid() -> void:
	var parsed := FoeAnnotations.load_store()
	assert_str(parsed.error).is_empty()
	for sector_index in parsed.store:
		assert_int(sector_index).is_between(0, 31)


func test_sector_numbers_come_from_the_file_name() -> void:
	assert_int(FoeAnnotations.sector_of_path(Catalog.foe_path(7))).is_equal(7)
	assert_int(FoeAnnotations.sector_of_path("user://sector_40.tres")).is_equal(40)
	assert_int(FoeAnnotations.sector_of_path("user://notes.foe")).is_equal(-1)
	assert_bool(FoeAnnotations.has_original(31)).is_true()
	assert_bool(FoeAnnotations.has_original(40)).is_false()


func test_the_stored_scripts_use_the_real_names_of_the_registry() -> void:
	# What the importer wrote must be what the registry says now: a number with a real name is never written as the number.
	# (test_foe_asm.gd compares the whole text with the Python disassembler's; this checks the names directly.)
	var registry := NameRegistry.original()
	for index in FoeAnnotations.original_sectors():
		for line in Catalog.sector(index).foe_script.source.split("\n"):
			var words := line.split(";")[0].strip_edges().split(" ", false)
			if words.size() == 2 and words[0] == "Play_Sound":
				assert_bool(words[1].is_valid_int() and registry.is_named(&"sound", words[1].to_int())).override_failure_message("sector %d: %s" % [index, line]).is_false()


## A registry that names every number the script of `sector` uses as a sound, picture, creature, flag or screen:
## `t_sound_<n>`, `t_pic_<n>` (in the sector's zone), `t_foe_<n>`, `t_flag_<n>`, `t_screen_<n>`.
func _registry_of(sector: SectorData) -> NameRegistry:
	var used := {&"sound": {}, &"frame": {}, &"foe": {}, &"flag": {}, &"screen": {}}
	var prefix := {&"sound": "t_sound_", &"frame": "t_pic_", &"foe": "t_foe_", &"flag": "t_flag_", &"screen": "t_screen_"}
	for item in FoeAsm.decode(sector.foe_bytecode, sector.foe_script_base):
		if item["op"] < 0:
			continue
		var position := 0
		for part in FoeOps.operands(item["op"]):
			var kind := FoeOps.name_kind(part["kind"])
			var value: int = item["operands"][position]
			position += FoeOps.kind_width(part["kind"])
			if kind.is_empty():
				continue
			if part.get("mirror", false) and value >= 128:
				value -= 128
			if value & 0x80 == 0 and value <= NameRegistry.KINDS[kind]["last"]:
				used[kind][value] = true
	var tables := {}
	for kind: StringName in used:
		var table := {}
		var numbers: Array = used[kind].keys()
		numbers.sort()
		for number: int in numbers:
			table["%s%d" % [prefix[kind], number]] = number
		tables[String(kind)] = table if kind == &"sound" else {str(sector.zone if kind == &"frame" else sector.index): table}
	var registry := NameRegistry.parse(JSON.stringify({"format": 1, "content_set": "test", "names": tables}))
	assert_array(registry.problems).override_failure_message("sector %d: %s" % [sector.index, registry.problems]).is_empty()
	return registry


func test_every_sector_written_only_with_names_assembles_to_the_same_bytes() -> void:
	var named_operands := 0
	for index in FoeAnnotations.original_sectors():
		var sector := Catalog.sector(index)
		var symbols := FoeNames.for_sector(sector, _registry_of(sector))
		var offsets: Array = []
		for foe in sector.foes:
			offsets.append([foe.pc, foe.script_hit, foe.script_ink])
		var text := FoeAsm.disassemble(sector.foe_bytecode, sector.foe_script_base, FoeAsm.entry_names(offsets), {}, symbols)
		# the named operands are names: no instruction that takes one has a plain number there
		for line in text.split("\n"):
			var words := line.strip_edges().split(" ", false)
			if words.is_empty() or words[0].ends_with(":") or words[0].begins_with(";") or FoeOps.op_from_mnemonic(words[0]) < 0:
				continue
			var list := FoeOps.operands(FoeOps.op_from_mnemonic(words[0]))
			var at := 1
			for part in list:
				if not FoeOps.name_kind(part["kind"]).is_empty() and at < words.size():
					assert_bool(words[at].is_valid_int()).override_failure_message("sector %d: %s" % [index, line]).is_false()
					named_operands += 1
				at += 1
				if at < words.size() and words[at] == FoeOps.MIRROR_WORD:
					at += 1
		var result := FoeAsm.assemble(text, sector.foe_script_base, symbols)
		assert_array(result.errors).override_failure_message("sector %d: %s" % [index, result.errors.slice(0, 3)]).is_empty()
		assert_bool(result.bytes == sector.foe_bytecode).override_failure_message("sector %d: the named text assembles to other bytes" % index).is_true()
		if FoeAnnotations.has_original_bytes():                 # and those are the original game's
			assert_bool(result.bytes == FoeAnnotations.original(index)["script"]).override_failure_message("sector %d" % index).is_true()
	assert_int(named_operands).is_greater(2000)


func test_storing_names_and_comments_needs_a_saved_original_sector() -> void:
	if _skip_without_original_bytes():
		return
	var doc := _panel.open_script(_sector_copy(3, 3))
	_panel.rename_label(doc, "loc_529", "swim_back")
	assert_str(_panel.store_problem(doc)).contains("unsaved")
	assert_bool(_panel.store_annotations(doc)).is_false()
	assert_bool(FileAccess.file_exists(TEMP_DIR + "/foe_annotations.json")).is_false()
	assert_int(_panel.save_document(doc)).is_equal(OK)
	assert_bool(FileAccess.file_exists(TEMP_DIR + "/foe_annotations.json")).override_failure_message("saving must not store").is_false()
	assert_bool(_panel.store_annotations(doc)).is_true()
	var store := FoeAnnotations.load_store(TEMP_DIR + "/foe_annotations.json").store
	assert_array(store[3]["labels"].values()).contains_exactly(["swim_back"])
	_clear_temp_dir()


func test_store_then_reset_style_round_trip_for_an_entry_rename_and_comments() -> void:
	if _skip_without_original_bytes():
		return
	var doc := _panel.open_script(_sector_copy(3, 3))
	_panel.rename_label(doc, "foe0_hit", "touch_return")
	doc.edit.text = "; header\n\n" + doc.edit.text.replace("    Return\n", "    Return  ; bounce\n")
	assert_int(_panel.save_document(doc)).is_equal(OK)
	assert_bool(_panel.store_annotations(doc)).is_true()
	var parsed := FoeAnnotations.load_store(TEMP_DIR + "/foe_annotations.json")
	assert_str(parsed.error).is_empty()
	var original := FoeAnnotations.original(3)
	var regenerated := FoeAsm.disassemble(original["script"], original["base"], original["entries"], parsed.store[3], FoeNames.for_sector(Catalog.sector(3)))
	assert_bool(regenerated == FileAccess.get_file_as_string(Catalog.foe_path(3, TEMP_DIR))).is_true()
	assert_str(FileAccess.get_file_as_string(Catalog.foe_path(3, TEMP_DIR))).starts_with("; header\n\ntouch_return:\n    Return  ; bounce\n")
	_clear_temp_dir()


func test_storing_is_refused_when_the_instructions_differ_from_the_original() -> void:
	if _skip_without_original_bytes():
		return
	var doc := _panel.open_script(_sector_copy(3, 3))
	doc.edit.text = doc.edit.text.replace("    Set_Frame ink_burst_4\n", "    Set_Frame 99\n")
	assert_int(_panel.save_document(doc)).is_equal(OK)
	assert_bool(_panel.store_annotations(doc)).is_false()
	assert_str(doc.notes[0]).contains("not stored").contains("original has")
	assert_bool(FileAccess.file_exists(TEMP_DIR + "/foe_annotations.json")).is_false()
	_clear_temp_dir()


## G42, sector 14 foe 18. Its hit entry starts with a LOOP0 back to foe 17's hit entry (a slip in the original data),
## so a hit on foe 18 runs foe 17's tail: SET_FRAME 51 ; MOVE_REL ; SOUND ; SET_FRAME 52 ; YIELD ;
## SLEEP_FOE 17 ; HIDE ; JMP loc_1961. The original's SLEEP_FOE zeroes the saved pc of the creature RUNNING it
## (foe 18), so its interrupt ends there and nothing is restored. The JMP then sends it into foe 17's cycle
## (loc_1961, which also shows it again, moves it to x 42 and calls loc_1774) instead of back to the pre-hit
## position and picture.
func test_sector_14_foe_18_hit_ends_its_interrupt_at_the_sleep_of_foe_17() -> void:
	var sector := Catalog.sector(14)
	var ctx := FoeVM.Context.new()
	ctx.rng.seed = 1
	var vms: Array[FoeVM] = []
	for i in sector.foes.size():
		var vm := FoeVM.from_data(sector.foes[i], i, sector)
		vms.append(vm)
		ctx.foes.append(vm)
	var foe := vms[18]
	var foe17 := vms[17]
	ctx.current_screen = foe.screen
	# Let the foe get going and into the middle of its jet cycle (it starts in loc_1774's climb).
	var ticks := 0
	while ticks < 400 and foe.hidden:
		for vm in vms:
			vm.tick(ctx)
		ticks += 1
	for i in 5:
		for vm in vms:
			vm.tick(ctx)
	assert_bool(foe.hidden).is_false()
	assert_bool(foe.can_be_interrupted()).is_true()
	var x_before := foe.x
	var y_before := foe.y
	var pc_before := foe.pc
	foe.interrupt(foe.script_hit)
	var steps := 0
	while foe.interrupted and steps < 20:
		foe.tick(ctx)
		steps += 1
	# It takes three ticks (MOVE_REL, YIELD and HIDE each end a turn); the last one runs SLEEP_FOE 17 ; HIDE.
	assert_int(steps).is_less(20)
	assert_bool(foe.interrupted).is_false()
	assert_bool(foe17.dormant).is_true()
	assert_bool(foe.dormant).is_false()
	assert_bool(foe.hidden).is_true()
	assert_int(foe.frame).is_equal(52)                     # not the pre-hit picture
	assert_int(foe.x).is_equal(x_before - 8)               # the hit script's step to the left, not undone
	assert_int(foe.y).is_equal(y_before)
	assert_str(foe.fault).is_empty()
	# The next tick is the JMP to loc_1961: the foe re-appears at the bottom of its screen (x 42 * 4, y 158 * 2),
	# in the picture range of foe 18 (SET_POS clamps 50 into its range), instead of resuming its climb at (x_before, y_before).
	foe.tick(ctx)
	assert_bool(foe.hidden).is_false()
	assert_int(foe.x).is_equal(168)
	assert_int(foe.y).is_equal(316)
	assert_bool(foe.x != x_before - 8 or foe.y != y_before).is_true()
	assert_bool(foe.pc != pc_before).is_true()
	assert_bool(foe.interrupted).is_false()
