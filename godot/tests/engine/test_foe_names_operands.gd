class_name TestFoeNamesOperands
extends GdUnitTestSuite
## B3, symbolic operands: a creature script may name its sounds, pictures, creatures, flags and screens, the assembler
## turns the names into the original numbers, and the disassembler writes a name when the number has one.
##
## Teaches: testing a SYMBOL TABLE feature without depending on its contents. The real registry
## (names/original.json) is still being filled in, so these tests use a small registry of their own: the probe of
## tests/fixtures/foe_names_probe.json (also read by tools/import/test_foe_names.py, which must produce the same
## text: that is how the Python disassembler of the importer and this one are kept equal), and, for the real
## scripts, a registry made up from the numbers each sector actually uses.

const PROBE := "res://tests/fixtures/foe_names_probe.json"


func _probe() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PROBE))


## The names of the probe, in the place the probe says it belongs to (sector 7, zone 2).
func _symbols(zone: int = -2, sector: int = -2) -> FoeNames:
	var probe := _probe()
	var registry := NameRegistry.parse(JSON.stringify(probe["registry"]))
	assert_array(registry.problems).is_empty()
	return FoeNames.new(registry, probe["sector"] if sector == -2 else sector, probe["zone"] if zone == -2 else zone)


func _probe_bytes() -> PackedByteArray:
	return String(_probe()["script_hex"]).hex_decode()


## The assembler's errors for one instruction line, with the probe's names.
func _errors(line: String, symbols: FoeNames = null) -> Array[String]:
	return FoeAsm.assemble(line, 0, symbols if symbols != null else _symbols()).errors


func _bytes(line: String) -> PackedByteArray:
	var result := FoeAsm.assemble(line, 0, _symbols())
	assert_array(result.errors).is_empty()
	return result.bytes


# --- the table -------------------------------------------------------------------------------------

func test_the_operand_table_says_which_operands_have_names() -> void:
	assert_int(FoeOps.operands(FoeOps.Op.SOUND)[0]["kind"]).is_equal(FoeOps.Kind.SOUND)
	assert_int(FoeOps.operands(FoeOps.Op.SET_FRAME)[0]["kind"]).is_equal(FoeOps.Kind.FRAME)
	assert_bool(FoeOps.operands(FoeOps.Op.SET_FRAME)[0].get("mirror", false)).is_true()
	for k in 2:
		assert_int(FoeOps.operands(FoeOps.Op.FRAME_RANGE)[k]["kind"]).is_equal(FoeOps.Kind.FRAME)
		assert_bool(FoeOps.operands(FoeOps.Op.FRAME_RANGE)[k].get("mirror", false)).is_false()   # a range limit is not mirrored
	assert_int(FoeOps.operands(FoeOps.Op.SET_POS)[2]["kind"]).is_equal(FoeOps.Kind.FRAME)
	assert_int(FoeOps.operands(FoeOps.Op.SET_POS_SCREEN)[2]["kind"]).is_equal(FoeOps.Kind.FRAME)
	assert_int(FoeOps.operands(FoeOps.Op.SET_POS_SCREEN)[3]["kind"]).is_equal(FoeOps.Kind.SCREEN)
	for opcode in [FoeOps.Op.SEM_SET, FoeOps.Op.SEM_CLR, FoeOps.Op.IF_SEM]:
		assert_int(FoeOps.operands(opcode)[0]["kind"]).is_equal(FoeOps.Kind.FLAG)
	# The third operand of Move_Foe_Relative_XY is a step, not a picture: it has no names (but it can be mirrored).
	assert_int(FoeOps.operands(FoeOps.Op.MOVE_REL)[2]["kind"]).is_equal(FoeOps.Kind.U8)
	assert_bool(FoeOps.operands(FoeOps.Op.MOVE_REL)[2].get("mirror", false)).is_true()
	assert_str(FoeOps.name_kind(FoeOps.Kind.U8)).is_empty()
	assert_str(FoeOps.name_kind(FoeOps.Kind.FRAME)).is_equal("frame")


func test_every_operand_kind_with_names_is_a_kind_of_the_registry() -> void:
	for kind in FoeOps.Kind.values():
		var registry_kind := FoeOps.name_kind(kind)
		if not registry_kind.is_empty():
			assert_bool(NameRegistry.KINDS.has(registry_kind)).override_failure_message(str(registry_kind)).is_true()


# --- names and the original numbers ------------------------------------------------------------------

func test_the_probe_written_only_with_names_assembles_to_its_bytes() -> void:
	var probe := _probe()
	var result := FoeAsm.assemble(probe["text"], 0, _symbols())
	assert_array(result.errors).is_empty()
	assert_bool(result.bytes == _probe_bytes()).is_true()


func test_the_probe_bytes_disassemble_to_the_names() -> void:
	var probe := _probe()
	assert_str(FoeAsm.disassemble(_probe_bytes(), 0, probe["entries"], {}, _symbols())).is_equal(probe["text"])


func test_without_names_every_operand_is_a_number() -> void:
	var text := FoeAsm.disassemble(_probe_bytes(), 0, _probe()["entries"])
	assert_bool(text.contains("probe_")).is_false()
	assert_bool(text.contains("    Set_Frame 40 mirrored\n")).is_true()
	assert_bool(text.contains("    Put_Foe_To_Sleep 3\n")).is_true()
	assert_bool(text.contains("    Move_Foe_To_Screen_XY 10 20 41 4\n")).is_true()


func test_a_number_without_a_real_name_is_printed_as_a_number_not_as_a_made_up_name() -> void:
	var text := FoeAsm.disassemble(_probe_bytes(), 0, _probe()["entries"], {}, _symbols())
	assert_bool(text.contains("    Play_Sound 6\n")).is_true()
	assert_bool(text.contains("sfx_")).is_false()
	assert_bool(text.contains("frame_0")).is_false()


func test_plain_numbers_and_made_up_names_still_assemble() -> void:
	assert_array(_bytes("Set_Frame 168")).is_equal(PackedByteArray([11, 168]))
	assert_array(_bytes("Set_Frame 40")).is_equal(_bytes("Set_Frame frame_040"))
	assert_array(_bytes("Play_Sound 5")).is_equal(_bytes("Play_Sound sfx_05"))
	assert_array(_bytes("Play_Sound sfx_05")).is_equal(_bytes("Play_Sound probe_sound"))       # a made-up name works even where a real one exists
	assert_array(_bytes("Wake_Foe foe_3")).is_equal(_bytes("Wake_Foe probe_boss"))
	assert_array(_bytes("Set_Flag flag_02")).is_equal(_bytes("Set_Flag probe_gate"))
	assert_array(_bytes("Move_Foe_To_Screen_XY 1 2 3 screen_04")).is_equal(_bytes("Move_Foe_To_Screen_XY 1 2 3 probe_cave"))


func test_self_and_numbers_for_creatures_are_unchanged() -> void:
	assert_array(_bytes("Wake_Foe self")).is_equal(PackedByteArray([9, 0x80]))
	assert_array(_bytes("Wake_Foe self-1")).is_equal(PackedByteArray([9, 0xFF]))
	assert_array(_bytes("Put_Foe_To_Sleep probe_helper")).is_equal(PackedByteArray([8, 4]))


# --- the mirror syntax ----------------------------------------------------------------------------------

func test_mirrored_after_a_picture_sets_bit_7() -> void:
	assert_array(_bytes("Set_Frame probe_zone_pic mirrored")).is_equal(PackedByteArray([11, 168]))
	assert_array(_bytes("Set_Frame 41 mirrored")).is_equal(PackedByteArray([11, 169]))
	assert_array(_bytes("Set_Frame 41 MIRRORED")).is_equal(PackedByteArray([11, 169]))
	assert_array(_bytes("Move_Foe_To_XY 1 2 probe_common mirrored")).is_equal(PackedByteArray([13, 1, 2, 131]))
	assert_array(_bytes("Move_Foe_Relative_XY 1 2 1 mirrored")).is_equal(PackedByteArray([12, 1, 2, 129]))
	# An operand after a mirrored picture is still the next operand.
	assert_array(_bytes("Move_Foe_To_Screen_XY 1 2 probe_common mirrored probe_cave")).is_equal(PackedByteArray([14, 1, 2, 131, 4]))


func test_the_mirror_flag_round_trips_for_every_picture() -> void:
	for picture in 128:
		for mirrored in [false, true]:
			var bytes := PackedByteArray([11, picture | (128 if mirrored else 0)])
			var text := FoeAsm.disassemble(bytes, 0, {"s": 0})
			assert_bool(text.contains("mirrored")).is_equal(mirrored)
			assert_bool(FoeAsm.assemble(text, 0).bytes == bytes).override_failure_message(text).is_true()


func test_mirrored_is_refused_where_it_means_nothing() -> void:
	assert_array(_errors("Set_Frame 168 mirrored")).has_size(1)
	assert_str(_errors("Set_Frame 168 mirrored")[0]).contains("already has bit 7")
	assert_str(_errors("Set_Frame_Range 1 2 mirrored")[0]).contains("Set_Frame_Range max takes no 'mirrored'")      # a limit of the range is not shown
	assert_str(_errors("Play_Sound 5 mirrored")[0]).contains("takes no 'mirrored'")
	assert_str(_errors("Wake_Foe 3 mirrored")[0]).contains("takes no 'mirrored'")
	assert_str(_errors("Set_Frame mirrored")[0]).contains("reserved word")
	assert_str(_errors("Set_Frame 3 mirrored mirrored")[0]).contains("needs 1 operand")
	assert_str(_errors("Set_Frame 3 mirror")[0]).contains("needs 1 operand")


func test_mirror_typo_points_to_the_right_word() -> void:
	assert_str(_errors("Set_Frame mirror")[0]).contains("write mirrored after the picture")


# --- unknown names ----------------------------------------------------------------------------------------

func test_an_unknown_name_says_what_kind_it_is_and_what_was_meant() -> void:
	assert_array(_errors("Play_Sound probe_sond")).is_equal(["line 1: Play_Sound operand: unknown sound 'probe_sond' (did you mean 'probe_sound'?)"])
	assert_array(_errors("Put_Foe_To_Sleep probe_bos")).is_equal(["line 1: Put_Foe_To_Sleep foe: unknown foe 'probe_bos' (did you mean 'probe_boss'?)"])
	assert_array(_errors("Set_Flag probe_gat")).is_equal(["line 1: Set_Flag operand: unknown flag 'probe_gat' (did you mean 'probe_gate'?)"])
	assert_str(_errors("Move_Foe_To_Screen_XY 1 2 3 nowhere")[0]).contains("unknown screen 'nowhere'")
	assert_str(_errors("Set_Frame_Range probe_common nobody")[0]).contains("Set_Frame_Range max: unknown frame 'nobody'")


func test_a_name_of_another_scope_is_explained() -> void:
	# other_zone_pic is picture 40 of zone 4; the probe is in zone 2.
	assert_str(_errors("Set_Frame other_zone_pic")[0]).contains("zone 4 (names of that scope work only there)")
	assert_array(FoeAsm.assemble("Set_Frame other_zone_pic", 0, _symbols(4)).errors).is_empty()
	assert_array(FoeAsm.assemble("Set_Frame probe_zone_pic", 0, _symbols(4)).errors).has_size(1)
	# probe_boss is a creature of sector 7 only.
	assert_array(FoeAsm.assemble("Wake_Foe probe_boss", 0, _symbols(-2, 8)).errors).has_size(1)
	assert_array(FoeAsm.assemble("Wake_Foe foe_3", 0, _symbols(-2, 8)).errors).is_empty()


func test_without_a_sector_only_the_global_and_common_names_work() -> void:
	var anywhere := FoeNames.new(_symbols().registry)
	assert_array(FoeAsm.assemble("Play_Sound probe_sound\nSet_Frame probe_common\nSet_Flag probe_finale", 0, anywhere).errors).is_empty()
	assert_array(FoeAsm.assemble("Set_Frame probe_zone_pic", 0, anywhere).errors).has_size(1)
	assert_array(FoeAsm.assemble("Wake_Foe probe_boss", 0, anywhere).errors).has_size(1)


func test_a_wrong_name_or_number_that_is_no_name_keeps_the_range_message() -> void:
	assert_array(_errors("Set_Frame 999")).is_equal(["line 1: Set_Frame operand must be 0..255, got 999"])
	assert_array(_errors("Play_Sound 1.5")).is_equal(["line 1: Play_Sound operand must be 0..255, got '1.5'"])
	assert_array(_errors("Wake_Foe self+64")).is_equal(["line 1: Wake_Foe foe must be 0..127 or self, self+N, self-N with N from -64 to 63, got 'self+64'"])
	assert_str(_errors("Set_Frame Probe_Zone")[0]).contains("is not a valid name")


func test_the_default_symbols_are_the_registry_of_the_project() -> void:
	var begin := NameRegistry.original().index_of(&"sound", "begin")
	assert_int(begin).is_greater(-1)
	assert_array(FoeAsm.assemble("Play_Sound begin", 0).bytes).is_equal(PackedByteArray([7, begin]))


# --- editing a text with names: the harvest compares values, not spellings --------------------------------

func test_a_stored_text_may_spell_an_operand_any_way() -> void:
	var probe := _probe()
	var script := _probe_bytes()
	var text: String = probe["text"]
	var other := text.replace("Play_Sound probe_sound", "Play_Sound 5").replace("Set_Frame probe_zone_pic mirrored", "Set_Frame 168") \
			.replace("Put_Foe_To_Sleep probe_boss", "Put_Foe_To_Sleep foe_3").replace("Set_Flag probe_gate", "Set_Flag flag_02")
	assert_str(other).is_not_equal(text)
	var result := FoeAnnotations.harvest(other, script, 0, probe["entries"], _symbols())
	assert_str(result.problem).is_empty()
	assert_bool(result.ok).is_true()
	assert_str(result.text).is_equal(text)                    # written back in the standard spelling, with the names
	var wrong := FoeAnnotations.harvest(text.replace("Set_Frame 41 mirrored", "Set_Frame 42 mirrored"), script, 0, probe["entries"], _symbols())
	assert_bool(wrong.ok).is_false()
	assert_str(wrong.problem).contains("the original has 'Set_Frame 41 mirrored' here")


# --- the whole game: every sector, written only with names -------------------------------------------------

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
	for index in Catalog.sector_ids():
		var sector := Catalog.sector(index)
		if sector.foes.is_empty():
			continue
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
	assert_int(named_operands).is_greater(20)


# --- the editor: names with their numbers ---------------------------------------------------------------------

func _completions(line: String, force := true) -> Array[Dictionary]:
	return FoeHelp.completions(PackedStringArray([line]), 0, line.length(), force, _symbols())


func test_completion_offers_the_names_of_the_operand_with_their_numbers() -> void:
	var options := _completions("    Set_Frame ")
	var found := {}
	for option in options:
		found[option["name"]] = option
	assert_bool(found.has("probe_common") and found.has("probe_zone_pic")).is_true()
	assert_bool(found.has("other_zone_pic")).is_false()                     # another zone's picture
	assert_str(found["probe_zone_pic"]["display"]).is_equal("probe_zone_pic (40)")
	assert_str(found["probe_zone_pic"]["insert"]).is_equal("probe_zone_pic")     # the script text has no number
	assert_int(found["probe_zone_pic"]["type"]).is_equal(FoeHelp.Candidate.NAME)
	assert_str(_completions("    Play_Sound ")[0]["display"]).is_equal("probe_sound (5)")
	assert_array(_completions("    Wake_Foe ").map(func(o): return o["name"])).contains(["self", "probe_boss", "probe_helper"])
	assert_array(_completions("    Wake_Foe pro").map(func(o): return o["display"])).is_equal(["probe_boss (3)", "probe_helper (4)"])
	assert_array(_completions("    Jump_To ").map(func(o): return o["name"])).is_empty()            # a label operand: labels only


func test_completion_offers_mirrored_after_a_picture_once() -> void:
	assert_array(_completions("    Set_Frame probe_common m", false).map(func(o): return o["name"])).contains_exactly(["mirrored"])
	assert_str(_completions("    Set_Frame probe_common m", false)[0]["display"]).is_equal("mirrored (+ 128)")
	assert_array(_completions("    Set_Frame probe_common mirrored ", true).map(func(o): return o["name"])).is_empty()
	assert_array(_completions("    Play_Sound probe_sound m", false)).is_empty()
	assert_array(_completions("    Move_Foe_To_Screen_XY 1 2 probe_common mirrored p", false).map(func(o): return o["name"])).contains_exactly(["probe_cave"])


func test_operand_tooltips_show_the_name_and_the_number() -> void:
	var line := "    Set_Frame probe_zone_pic mirrored"
	var lines := PackedStringArray([line])
	var symbols := _symbols()
	var over_name := FoeHelp.tooltip(lines, 0, line.find("probe_zone_pic") + 2, symbols)
	assert_str(over_name).contains("probe_zone_pic (40)")
	var over_number := FoeHelp.tooltip(PackedStringArray(["    Set_Frame 168"]), 0, 14, symbols)
	assert_str(over_number).contains("Its name: probe_zone_pic (40 + 128)")
	assert_str(FoeHelp.tooltip(lines, 0, line.find("mirrored") + 2, symbols)).contains("adding 128")
	assert_str(FoeHelp.tooltip(PackedStringArray(["    Play_Sound probe_sound"]), 0, 16, symbols)).contains("probe_sound (5)")
	assert_str(FoeHelp.tooltip(PackedStringArray(["    Play_Sound sfx_28"]), 0, 16, symbols)).contains("made-up name of sound effect number 28")
	assert_str(FoeHelp.tooltip(PackedStringArray(["    Play_Sound nope"]), 0, 16, symbols)).contains("unknown sound 'nope'")
	assert_str(FoeHelp.tooltip(PackedStringArray(["    Wake_Foe probe_boss"]), 0, 14, symbols)).contains("probe_boss (3)")


func test_the_operand_index_skips_the_mirrored_word() -> void:
	var line := "    Move_Foe_To_Screen_XY 1 2 probe_common mirrored probe_cave"
	assert_int(FoeLineInfo.locate(line, line.find("probe_common")).operand).is_equal(2)
	var on_mirror := FoeLineInfo.locate(line, line.find("mirrored"))
	assert_int(on_mirror.operand).is_equal(2)
	assert_bool(on_mirror.on_mirror_word).is_true()
	assert_int(FoeLineInfo.locate(line, line.find("probe_cave")).operand).is_equal(3)
	assert_int(FoeLineInfo.locate(line + " ", line.length() + 1).operand).is_equal(4)
	assert_bool(FoeLineInfo.locate("    Set_Frame 3 ", 17, true).mirror_may_follow).is_true()
	assert_bool(FoeLineInfo.locate("    Set_Frame 3 mirrored ", 26, true).mirror_may_follow).is_false()


func test_the_highlighter_colours_names_apart_from_labels_and_numbers() -> void:
	var hl := FoeSyntaxHighlighter.new()
	var colors := hl.highlight_text("    Set_Frame probe_zone_pic mirrored")
	assert_that(colors[14]["color"]).is_equal(hl.name_color)
	assert_that(colors[29]["color"]).is_equal(hl.name_color)                 # mirrored
	assert_that(hl.highlight_text("    Jump_To again")[12]["color"]).is_equal(hl.label_color)
	assert_that(hl.highlight_text("    Set_Frame 3")[14]["color"]).is_equal(hl.number_color)
	assert_that(hl.highlight_text("    Wake_Foe self+1")[13]["color"]).is_equal(hl.self_color)
