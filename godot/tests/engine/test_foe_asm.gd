class_name TestFoeAsm
extends GdUnitTestSuite
## Teaches: testing a translator two ways. A ROUND TRIP proves the text format loses nothing (the text of a sector's bytes assembles to the
## same bytes); hand-written programs with their expected bytes show what a designer's text means; and every error message is checked for
## its line number. The sectors it runs over are the pack's (the dev pack: every sector of the chain); what only the ORIGINAL scripts can prove
## (the hashes of the original bytes, the sync with the Python disassembler and with the annotation store) is `legacy/test_foe_asm_legacy.gd`.

const Op := FoeOps.Op

# A designer-style script at buffer offset 100, with the byte offset of every line.
const HAND_WRITTEN := """
; a creature that walks, falls asleep next to it, and starts again
start:
    Set_Frame_Range 0 3            ; 100
again:
    Move_Foe_Relative_XY 2 -3 1    ; 103
    Loop_Counter0_Back_To again 4  ; 107
    Put_Foe_To_Sleep self+1        ; 112
    Jump_To done                   ; 114  forward jump
    Hide_Foe                       ; 117
done:
    Wait_Next_Tick                 ; 118
    Jump_To start                  ; 119  backward jump
"""


## The error messages of `source` as an array.
func _errors(source: String) -> Array[String]:
	return FoeAsm.assemble(source, 0).errors


# --- the sectors of the pack ---------------------------------------------------------------------------------

## The sectors of the chain that have creatures (the others have no script bytes).
func _sectors_with_creatures() -> Array[SectorData]:
	var found: Array[SectorData] = []
	for index in Catalog.sector_ids():
		var sector := Catalog.sector(index)
		if not sector.foes.is_empty():
			found.append(sector)
	return found


## The bytes, the base and the creatures' entry points of a sector, shaped like `FoeAnnotations.original`.
func _bytes_of(sector: SectorData) -> Dictionary:
	var offsets: Array = []
	for foe in sector.foes:
		offsets.append([foe.pc, foe.script_hit, foe.script_ink])
	return {"script": sector.foe_bytecode, "base": sector.foe_script_base, "offsets": offsets, "entries": FoeAsm.entry_names(offsets)}


func test_every_sector_compiles_without_errors() -> void:
	var checked := 0
	for sector in _sectors_with_creatures():
		assert_array(sector.compile_errors).override_failure_message("sector %d: %s" % [sector.index, sector.compile_errors.slice(0, 3)]).is_empty()
		assert_int(sector.foe_bytecode.size()).override_failure_message("sector %d compiled to no bytes" % sector.index).is_greater(0)
		checked += 1
	assert_int(checked).is_greater(0)


func test_disassembling_the_bytes_of_every_sector_round_trips() -> void:
	for sector in _sectors_with_creatures():
		var data := _bytes_of(sector)
		var script: PackedByteArray = data["script"]
		var base: int = data["base"]
		var entries: Dictionary = data["entries"]
		var result := FoeAsm.assemble(FoeAsm.disassemble(script, base, entries), base)
		assert_array(result.errors).override_failure_message("sector %d: %s" % [sector.index, result.errors.slice(0, 3)]).is_empty()
		assert_bool(result.bytes == script).override_failure_message("sector %d does not round-trip" % sector.index).is_true()
		# Only the first name at a shared place is printed, but every entry point has a label.
		var label_offsets := result.labels.values()
		for name in entries:
			assert_bool(label_offsets.has(entries[name])).override_failure_message("sector %d: nothing labels %s" % [sector.index, name]).is_true()


func test_the_stored_text_has_one_label_per_place() -> void:
	for index in Catalog.sector_ids():
		var lines := Catalog.sector(index).foe_script.source.split("\n")
		for n in range(1, lines.size()):
			assert_bool(lines[n].ends_with(":") and lines[n - 1].ends_with(":")).override_failure_message("sector %d line %d: two labels in a row" % [index, n + 1]).is_false()


func test_foes_that_share_a_place_name_the_same_label() -> void:
	var sector := Catalog.sector(DevCreatures.ARENA)
	# Every creature of the arena only returns when touched: they all point at the one label.
	var shared := 0
	for foe in sector.foes:
		if foe.hit_label == "quiet_hit":
			shared += 1
	assert_int(shared).is_greater(DevCreatures.CREATURES - 3)
	assert_int(sector.foes.map(func(foe: FoeData) -> int: return foe.script_hit).filter(func(at: int) -> bool: return at == sector.foes[0].script_hit).size()).is_equal(shared)


func test_every_dead_instruction_of_every_sector_is_padding_or_under_a_comment_and_no_live_one_is() -> void:
	for sector in _sectors_with_creatures():
		var original := _bytes_of(sector)
		var index := sector.index
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


func test_a_sector_text_has_one_line_for_every_instruction_and_as_many_bytes_as_the_script() -> void:
	for sector in _sectors_with_creatures():
		var data := _bytes_of(sector)
		var size := 0
		for line in FoeAsm.disassemble(data["script"], data["base"], data["entries"]).split("\n"):
			var words := line.split(";")[0].strip_edges().split(" ", false)
			if words.is_empty() or words[0].ends_with(":"):
				continue
			if words[0] == "Padding":
				size += int(words[1])
			else:
				size += 1 + FoeOps.OPERAND_COUNT[FoeOps.op_from_mnemonic(words[0])]
		assert_int(size).override_failure_message("sector %d" % sector.index).is_equal(data["script"].size())


func test_every_entry_label_in_every_sector_file_names_a_label_of_its_script() -> void:
	# All sector_NN/sector_NN.tres in the folder, the sectors made by the designers too (and not the screen_MM.tres beside them).
	var checked := 0
	for directory in Catalog.own_sector_dirs():
		for folder in DirAccess.get_directories_at(directory):
			if FoeAnnotations.sector_of_path(folder) < 0:
				continue
			var file_name := folder + ".tres"
			var sector := load(directory + "/" + folder + "/" + file_name) as SectorData
			var labels := sector.foe_labels
			for i in sector.foes.size():
				for field in ["start_label", "hit_label", "ink_label"]:
					var label: String = sector.foes[i].get(field)
					assert_bool(labels.has(label)).override_failure_message("%s foe %d %s '%s' is not a label of the script" % [file_name, i, field, label]).is_true()
			checked += 1
	assert_int(checked).is_greater(0)


func _script(text: String) -> FoeScript:
	var script := FoeScript.new()
	script.source = text
	return script


# --- compile errors ----------------------------------------------------------------------------

func _broken_sector() -> SectorData:
	var sector := SectorData.new()
	sector.index = 7
	sector.foe_script_base = 100
	sector.foe_script = _script("start:\n    Wait_Next_Tick\n    Jump_To nowhere\n    Bogus 3\n")
	var foe := FoeData.new()
	foe.start_label = "start"
	foe.hit_label = "start"
	foe.ink_label = "start"
	sector.foes = [foe]
	return sector


func test_a_compile_error_is_reported_with_the_line_and_gives_no_script() -> void:
	var sector := _broken_sector()
	var errors := sector.compile()
	assert_array(errors).is_equal(["line 3: unknown label 'nowhere'", "line 4: unknown instruction 'Bogus'"])
	assert_array(sector.compile_errors).is_equal(errors)
	assert_str(sector.describe()).contains("sector 7")
	assert_int(sector.foe_bytecode.size()).is_equal(0)
	assert_int(sector.foes[0].pc).is_equal(0)


func test_creatures_of_a_sector_that_does_not_compile_fault_instead_of_running() -> void:
	var sector := _broken_sector()
	var vm := FoeVM.from_data(sector.foes[0], 0, sector)
	assert_str(vm.fault).contains("sector 7").contains("line 3")
	vm.tick(FoeVM.Context.new())              # must not crash
	assert_int(vm.x).is_equal(0)
	assert_bool(vm.can_run(0)).is_false()


func test_an_unknown_entry_label_names_the_creature_and_the_field() -> void:
	var sector := SectorData.new()
	sector.foe_script = _script("a:\n    Return\n")
	var first := FoeData.new()
	first.start_label = "a"
	first.hit_label = "a"
	first.ink_label = "a"
	var second := FoeData.new()
	second.start_label = "a"
	second.hit_label = "a"
	second.ink_label = "ink_typo"
	var third := FoeData.new()                # all three labels left empty
	sector.foes = [first, second, third]
	assert_array(sector.compile()).is_equal([
		"foe 1 ink_label: unknown label 'ink_typo'",
		"foe 2 start_label is empty; name a label of the script",
		"foe 2 hit_label is empty; name a label of the script",
		"foe 2 ink_label is empty; name a label of the script",
	])


func test_editing_the_text_changes_the_compiled_script() -> void:
	var sector := SectorData.new()
	sector.foe_script_base = 40
	var foe := FoeData.new()
	foe.start_label = "b"
	foe.hit_label = "a"
	foe.ink_label = "a"
	sector.foes = [foe]
	sector.foe_script = _script("a:\n    Return\nb:\n    Hide_Foe\n")
	assert_array(sector.foe_bytecode).is_equal(PackedByteArray([Op.RET, Op.HIDE]))
	assert_int(foe.pc).is_equal(41)
	sector.foe_script.source = "a:\n    Return\n    Show_Foe\nb:\n    Hide_Foe\n"      # the FoeScript emits `changed`
	assert_array(sector.foe_bytecode).is_equal(PackedByteArray([Op.RET, Op.SHOW, Op.HIDE]))
	assert_int(foe.pc).is_equal(42)
	assert_int(foe.script_hit).is_equal(40)


## The compiled script is a cache keyed by everything it derives from, the creatures too: a label changed in place, a creature added
## to the list or the list replaced (a reload from disk) gives the entry points of the new records on next use, with no signal from
## whoever changed them.
func test_a_changed_label_or_a_new_creature_compiles_again() -> void:
	var sector := SectorData.new()
	sector.foe_script_base = 40
	var foe := FoeData.new()
	foe.start_label = "b"
	foe.hit_label = "a"
	foe.ink_label = "a"
	sector.foes = [foe]
	sector.foe_script = _script("a:\n    Return\nb:\n    Hide_Foe\n")
	sector.ensure_compiled()
	assert_int(foe.pc).is_equal(41)
	foe.start_label = "a"                                         # (the Inspector, the screen editor, a label rename)
	sector.ensure_compiled()
	assert_int(foe.pc).is_equal(40)
	var added := FoeData.new()
	added.start_label = "b"
	added.hit_label = "b"
	added.ink_label = "a"
	sector.foes.append(added)                                     # (the list changed in place)
	assert_int(sector.foe_source_map.line_of(41)).is_equal(4)
	assert_int(added.pc).is_equal(41)
	assert_int(added.script_hit).is_equal(41)
	var reloaded := FoeData.new()
	reloaded.start_label = "b"
	reloaded.hit_label = "a"
	reloaded.ink_label = "b"
	sector.foes = [reloaded]                                      # (a new list of new records: a reload from disk)
	sector.ensure_compiled()
	assert_int(reloaded.pc).is_equal(41)
	assert_int(reloaded.script_ink).is_equal(41)


func test_instruction_text_names_the_nearest_label_before() -> void:
	var result := FoeAsm.assemble("start:\n    Hide_Foe\nagain:\n    Wait_Next_Tick\n    Set_Frame 9\n    Jump_To again\n", 100)
	assert_str(FoeAsm.instruction_text(result.bytes, 100, result.labels, 100)).is_equal("start+0: Hide_Foe")
	assert_str(FoeAsm.instruction_text(result.bytes, 100, result.labels, 102)).is_equal("again+1: Set_Frame 9")
	assert_str(FoeAsm.instruction_text(result.bytes, 100, result.labels, 104)).is_equal("again+3: Jump_To again")
	assert_str(FoeAsm.instruction_text(result.bytes, 100, result.labels, 500)).is_equal("again+399: <outside the script>")
	assert_str(FoeAsm.instruction_text(result.bytes, 100, {}, 100)).is_equal("100: Hide_Foe")


# --- the disassembler's format ------------------------------------------------------

func test_disassembly_uses_friendly_names_labels_and_signed_operands() -> void:
	var script := PackedByteArray([
		Op.MOVE_REL, 254, 3, 1,          # 50: dx = -2
		Op.LOOP1, 251, 255, 7, 0,        # 54: back 5 -> 54 + 5 - 5 = 54
		Op.SLEEP_FOE, 0xFF,              # 59: self-1
		Op.SLEEP_FOE, 0x80,              # 61: self
		Op.WAKE_FOE, 4,                  # 63
		Op.JMP, 238, 255,                # 65: next = 68, -18 -> 50
	])
	# "walker" and "walker_hit" share offset 50: only the first name is printed, and jumps use it.
	var text := FoeAsm.disassemble(script, 50, {"walker": 50, "walker_hit": 50, "late": 68})
	assert_str(text).is_equal("""walker:
    Move_Foe_Relative_XY -2 3 1

loc_54:
    Loop_Counter1_Back_To loc_54 7
    Put_Foe_To_Sleep self-1
    Put_Foe_To_Sleep self
    Wake_Foe 4
    Jump_To walker

late:
""")


# --- the generated "not executed" comment (reachability) -----------------------------
#
# Hand-assembled scripts at base 0, the same as in tools/import/test_foe_text.py. A jump's two
# operand bytes are (target - the offset after the instruction), signed 16-bit, little endian.

const UNUSED := [FoeAsm.UNEXECUTED_UNUSED]


## The Padding spans (offset -> N) the disassembler writes for `script`.
func _spans(script: Array, entries: Dictionary = {"start": 0}) -> Dictionary:
	return FoeAsm.padding_spans(PackedByteArray(script), 0, entries.values())


func _dead(script: Array, entries: Dictionary = {"start": 0}) -> Dictionary:
	return FoeAsm.unexecuted_notes(PackedByteArray(script), 0, entries)


func test_the_comment_text() -> void:
	assert_str(FoeAsm.UNEXECUTED_UNUSED).is_equal("    ; The following instructions are not executed -- nothing jumps to them")


func test_everything_reachable_has_no_comment() -> void:
	#   0 Set_Frame 1; 2 Jump_To 0
	assert_dict(_dead([Op.SET_FRAME, 1, Op.JMP, 0xFB, 0xFF])).is_empty()


func test_nothing_follows_a_jump() -> void:
	#   0 Set_Frame 1; 2 Jump_To 0; 5 Hide_Foe (dead); 6 Show_Foe (dead)
	assert_dict(_dead([Op.SET_FRAME, 1, Op.JMP, 0xFB, 0xFF, Op.HIDE, Op.SHOW])).is_equal({5: UNUSED})


func test_return_ends_the_path() -> void:
	assert_dict(_dead([Op.RET, Op.SHOW])).is_equal({1: UNUSED})


func test_a_subroutine_is_reached_by_the_call_and_its_return_comes_back_after_the_call() -> void:
	#   0 Call_Subroutine 7; 3 Show_Foe (only the Return of the subroutine gets here); 4 Jump_To 0; 7 Set_Frame 1; 9 Return
	assert_dict(_dead([Op.HANDLER, 4, 0, Op.SHOW, Op.JMP, 0xF9, 0xFF, Op.SET_FRAME, 1, Op.RET])).is_empty()
	#   the same without the call: the subroutine is dead
	assert_dict(_dead([Op.SET_FRAME, 1, Op.SHOW, Op.JMP, 0xF9, 0xFF, Op.SET_FRAME, 1, Op.RET])).is_equal({6: UNUSED})


func test_a_loop_goes_back_and_falls_through_when_it_is_over() -> void:
	#   0 Show_Foe; 1 Wait_Next_Tick; 2 Loop_Counter1 -> 1, 3 times; 7 Jump_To 7; 10 Hide_Foe (dead)
	var script := [Op.SHOW, Op.YIELD, Op.LOOP1, 0xFA, 0xFF, 3, 0, Op.JMP, 0xFD, 0xFF, Op.HIDE]
	assert_dict(_dead(script)).is_equal({10: UNUSED})
	#   entering at the loop: 0 is dead, but 1 is reached by the jump back and 7 by the fall-through
	assert_dict(_dead(script, {"start": 2})).is_equal({0: UNUSED, 10: UNUSED})
	for opcode in [Op.LOOP0, Op.LOOP2]:
		var other := [Op.SHOW, Op.YIELD, opcode, 0xFA, 0xFF, 3, 0, Op.JMP, 0xFD, 0xFF, Op.HIDE]
		assert_dict(_dead(other, {"start": 2})).is_equal({0: UNUSED, 10: UNUSED})


func test_a_condition_may_skip_the_next_instruction() -> void:
	#   0 If_Sub_X_Greater 5; 2 Jump_To 0; 5 Show_Foe (reached by the skip); 6 Jump_To 0; 9 Hide_Foe (dead)
	assert_dict(_dead([Op.IF_SUBX_GT, 5, Op.JMP, 0xFB, 0xFF, Op.SHOW, Op.JMP, 0xF7, 0xFF, Op.HIDE])).is_equal({9: UNUSED})
	#   without the condition the jump is always taken and Show_Foe is dead too
	assert_dict(_dead([Op.SET_FRAME, 5, Op.JMP, 0xFB, 0xFF, Op.SHOW, Op.JMP, 0xF7, 0xFF, Op.HIDE])).is_equal({5: UNUSED})


func test_every_conditional_instruction_skips() -> void:
	for opcode in [Op.IF_SUBX_GT, Op.IF_SUBX_LT, Op.IF_SUBY_GT, Op.IF_SUBY_LT, Op.IF_RAND_GT, Op.IF_SEM]:
		#   0 If_..., 2 Jump_To 0, 5 Show_Foe (reached only by the skip), 6 Return
		assert_dict(_dead([opcode, 1, Op.JMP, 0xFB, 0xFF, Op.SHOW, Op.RET])).override_failure_message(FoeOps.MNEMONIC[opcode]).is_empty()
	# and no other instruction does (Set_Flag, Clear_Flag, Play_Sound ... fall through only)
	for opcode in [Op.SOUND, Op.SEM_SET, Op.SEM_CLR, Op.SET_FRAME]:
		assert_dict(_dead([opcode, 1, Op.JMP, 0xFB, 0xFF, Op.SHOW, Op.RET])).override_failure_message(FoeOps.MNEMONIC[opcode]).is_equal({5: UNUSED})


func test_the_hit_and_the_ink_entry_are_starting_points_too() -> void:
	#   0 Jump_To 0; 3, 4 Wait_Next_Tick (dead); 5 Show_Foe, 6 Return (hit); 7 Hide_Foe, 8 Return (ink)
	var script := [Op.JMP, 0xFD, 0xFF, 0, 0, Op.SHOW, Op.RET, Op.HIDE, Op.RET]
	var entries := {"foe0_start": 0, "foe0_hit": 5, "foe0_ink": 7}
	assert_dict(_dead(script, entries)).is_empty()                 # only zero bytes: Padding 2, no comment
	assert_dict(_spans(script, entries)).is_equal({3: 2})
	assert_dict(_dead(script)).is_equal({5: UNUSED})              # without them the dead run has code too
	assert_dict(_spans(script)).is_equal({3: 2})


func test_a_run_of_only_zero_bytes_is_padding_and_a_run_with_code_is_unused_code() -> void:
	assert_dict(_dead([Op.RET, 0, 0, 0])).is_empty()
	assert_dict(_spans([Op.RET, 0, 0, 0])).is_equal({1: 3})
	assert_str(FoeAsm.disassemble(PackedByteArray([Op.RET, 0, 0, 0]), 0, {"start": 0})).is_equal("start:\n    Return\n    Padding 3\n")


func test_zero_bytes_inside_a_run_with_code_are_padding_only_when_nothing_falls_into_them() -> void:
	# The comment goes before the first instruction that is not padding.
	#   0 Return; 1, 2 zero (follow a Return); 3 Hide_Foe; 4 zero (falls through from Hide_Foe: a pause); 5 Show_Foe;
	#   6 Jump_To 0 (dead); 9, 10 zero (follow a Jump_To); 11 Show_Foe
	var script := [Op.RET, 0, 0, Op.HIDE, 0, Op.SHOW, Op.JMP, 0xF7, 0xFF, 0, 0, Op.SHOW]
	assert_dict(_dead(script)).is_equal({3: UNUSED})
	assert_dict(_spans(script)).is_equal({1: 2, 9: 2})
	assert_str(FoeAsm.disassemble(PackedByteArray(script), 0, {"start": 0})).is_equal(
			"start:\n    Return\n    Padding 2\n%s\n    Hide_Foe\n    Wait_Next_Tick\n    Show_Foe\n    Jump_To start\n    Padding 2\n    Show_Foe\n" % FoeAsm.UNEXECUTED_UNUSED)
	# zero bytes that start a run are padding even after an instruction that falls through (the run is a new one)
	#   0 Jump_To 0; 3 zero; 4 Hide_Foe
	assert_dict(_spans([Op.JMP, 0xFD, 0xFF, 0, Op.HIDE])).is_equal({3: 1})
	assert_dict(_dead([Op.JMP, 0xFD, 0xFF, 0, Op.HIDE])).is_equal({4: UNUSED})
	# trailing zero bytes after an instruction that falls through are code (the unused script runs on into them)
	assert_dict(_spans([Op.RET, Op.HIDE, 0, 0])).is_empty()
	assert_dict(_dead([Op.RET, Op.HIDE, 0, 0])).is_equal({1: UNUSED})
	assert_dict(_spans([Op.RET, Op.JMP, 0xFC, 0xFF, 0, 0])).is_equal({4: 2})


func test_a_reachable_zero_byte_stays_wait_next_tick_and_gets_no_padding() -> void:
	#   0 Wait_Next_Tick; 1 Wait_Next_Tick; 2 Jump_To 0; 5, 6 zero (dead)
	var script := [0, 0, Op.JMP, 0xFB, 0xFF, 0, 0]
	assert_dict(_spans(script)).is_equal({5: 2})
	assert_str(FoeAsm.disassemble(PackedByteArray(script), 0, {"start": 0})).is_equal(
			"start:\n    Wait_Next_Tick\n    Wait_Next_Tick\n    Jump_To start\n    Padding 2\n")


func test_a_label_in_a_run_of_zero_bytes_splits_the_padding_and_a_long_run_needs_more_than_one_line() -> void:
	#   0 Return; 1..4 zero; 5 Jump_To loc_3 (dead, makes loc_3 a label in the middle of the zero bytes)
	assert_dict(_spans([Op.RET, 0, 0, 0, 0, Op.JMP, 0xFB, 0xFF])).is_equal({1: 2, 3: 2})
	var big := PackedByteArray([Op.RET])
	big.resize(1 + FoeOps.PADDING_MAX + 5)
	assert_dict(FoeAsm.padding_spans(big, 0, [0])).is_equal({1: FoeOps.PADDING_MAX, 1 + FoeOps.PADDING_MAX: 5})


func test_a_stored_label_or_comment_inside_zero_bytes_cuts_the_padding_there() -> void:
	var script := PackedByteArray([Op.RET, 0, 0, 0, 0])
	assert_str(FoeAsm.disassemble(script, 0, {"start": 0})).is_equal("start:\n    Return\n    Padding 4\n")
	var annotations := {"labels": {3: "middle"}, "comments": {2: {"above": ["    ; here"]}}}
	var cut := FoeAsm.disassemble(script, 0, {"start": 0}, annotations)
	assert_str(cut).is_equal("start:\n    Return\n    Padding 1\n    ; here\n    Padding 1\n\nmiddle:\n    Padding 2\n")
	var result := FoeAnnotations.harvest(cut, script, 0, {"start": 0})
	assert_str(result.problem).is_empty()
	assert_dict(result.labels).is_equal({3: "middle"})
	assert_dict(result.comments).is_equal({2: {"above": ["    ; here"]}})
	assert_str(result.text).is_equal(cut)


func test_a_label_inside_a_dead_run_starts_a_new_run() -> void:
	#   0 Jump_To 0; 3 Show_Foe, 4 Hide_Foe (both dead); 5 Jump_To loc_4 (dead, makes loc_4); 8 Show_Foe (dead)
	var script := PackedByteArray([Op.JMP, 0xFD, 0xFF, Op.SHOW, Op.HIDE, Op.JMP, 0xFC, 0xFF, Op.SHOW])
	assert_dict(FoeAsm.unexecuted_notes(script, 0, {"start": 0})).is_equal({3: UNUSED, 4: UNUSED})
	var note := FoeAsm.UNEXECUTED_UNUSED
	assert_str(FoeAsm.disassemble(script, 0, {"start": 0})).is_equal(
			"start:\n    Jump_To start\n%s\n    Show_Foe\n\nloc_4:\n%s\n    Hide_Foe\n    Jump_To loc_4\n    Show_Foe\n" % [note, note])


func test_the_parts_of_a_split_run_are_judged_separately() -> void:
	#   0 Jump_To 0; 3 Wait_Next_Tick (dead); 4 Wait_Next_Tick (dead, target of the next); 5 Jump_To loc_4 (dead)
	var script := [Op.JMP, 0xFD, 0xFF, 0, 0, Op.JMP, 0xFC, 0xFF]
	assert_dict(_spans(script)).is_equal({3: 1, 4: 1})
	assert_dict(_dead(script)).is_equal({5: UNUSED})


func test_the_comment_comes_after_the_label_line_and_before_the_instruction() -> void:
	#   0 Return; 1 Hide_Foe (dead, labelled by a dead jump); 2 Jump_To loc_1
	var script := PackedByteArray([Op.RET, Op.HIDE, Op.JMP, 0xFC, 0xFF])
	assert_str(FoeAsm.disassemble(script, 0, {"start": 0})).is_equal(
			"start:\n    Return\n\nloc_1:\n%s\n    Hide_Foe\n    Jump_To loc_1\n" % FoeAsm.UNEXECUTED_UNUSED)
	# a Padding line at the start of the run comes first, the comment goes before the code after it
	var padded := PackedByteArray([Op.RET, 0, Op.HIDE, Op.JMP, 0xFA, 0xFF])
	assert_str(FoeAsm.disassemble(padded, 0, {"start": 0})).is_equal(
			"start:\n    Return\n    Padding 1\n%s\n    Hide_Foe\n    Jump_To start\n" % FoeAsm.UNEXECUTED_UNUSED)


func test_a_stored_above_replaces_the_comment_and_an_empty_one_removes_it() -> void:
	var script := PackedByteArray([Op.RET, Op.HIDE, 0, Op.SHOW])
	var plain := "start:\n    Return\n%s\n    Hide_Foe\n    Wait_Next_Tick\n    Show_Foe\n" % FoeAsm.UNEXECUTED_UNUSED
	assert_str(FoeAsm.disassemble(script, 0, {"start": 0})).is_equal(plain)
	var replaced := FoeAsm.disassemble(script, 0, {"start": 0}, {"comments": {1: {"above": ["    ; mine"]}}})
	assert_str(replaced).is_equal("start:\n    Return\n    ; mine\n    Hide_Foe\n    Wait_Next_Tick\n    Show_Foe\n")
	var removed := FoeAsm.disassemble(script, 0, {"start": 0}, {"comments": {1: {"above": []}}})
	assert_str(removed).is_equal("start:\n    Return\n    Hide_Foe\n    Wait_Next_Tick\n    Show_Foe\n")
	# other notes at the position leave the generated comment alone
	var inline := FoeAsm.disassemble(script, 0, {"start": 0}, {"comments": {1: {"inline": "; x"}}})
	assert_str(inline).is_equal(plain.replace("Hide_Foe\n", "Hide_Foe  ; x\n"))


# --- dead-code warnings for hand-written text ---------------------------------------------

const STUDENT := """start:
    Move_Foe_Relative_XY 2 0 1
    Jump_To start
    Hide_Foe
    Show_Foe

touch:
    Return

spare:
    Jump_To spare
"""


func _warnings(source: String, entry_labels: Array) -> Array[String]:
	return FoeAsm.dead_code_warnings(source, FoeAsm.assemble(source, 100), entry_labels)


func test_assemble_remembers_the_line_of_every_instruction() -> void:
	var result := FoeAsm.assemble(STUDENT, 100)
	assert_int(result.base).is_equal(100)
	assert_dict(result.instruction_lines).is_equal({100: 2, 104: 3, 107: 4, 108: 5, 109: 8, 110: 11})
	assert_array(FoeAsm.unreachable_offsets(result.bytes, 100, [result.labels["start"], result.labels["touch"]])).is_equal([107, 108, 110])


func test_a_student_script_gets_one_warning_per_dead_run_with_its_first_line() -> void:
	var warnings := _warnings(STUDENT, ["start", "touch", "touch"])
	assert_array(warnings).is_equal([
		"line 4: never executed (no creature start/hit/ink entry or jump reaches it)",
		"line 11: never executed (no creature start/hit/ink entry or jump reaches it)"])    # `spare` jumps to itself only
	# a creature that starts at spare makes it live
	assert_array(_warnings(STUDENT, ["start", "touch", "spare"])).has_size(1)


func test_the_not_executed_comment_silences_the_warning_for_its_run() -> void:
	var commented := STUDENT.replace("    Hide_Foe\n", "    ; The following instructions are not executed -- I left them for later\n    Hide_Foe\n")
	assert_array(_warnings(commented, ["start", "touch", "touch"])).is_equal(["line 12: never executed (no creature start/hit/ink entry or jump reaches it)"])
	# either generated wording counts, with blank lines and label lines between the comment and the instruction
	var generated := STUDENT.replace("    Hide_Foe\n", FoeAsm.UNEXECUTED_UNUSED + "\n    Hide_Foe\n").replace("spare:\n", FoeAsm.UNEXECUTED_UNUSED + "\n\nspare:\n")
	assert_array(_warnings(generated, ["start", "touch", "touch"])).is_empty()
	# any other comment does not
	var other := STUDENT.replace("    Hide_Foe\n", "    ; remove this\n    Hide_Foe\n")
	assert_array(_warnings(other, ["start", "touch", "touch"])).has_size(2)
	# and a comment further up does not reach a later run
	var far := STUDENT.replace("    Hide_Foe\n", "    ; The following instructions are not executed -- x\n    Hide_Foe\n").replace("touch:\n    Return\n", "touch:\n    Return\n    Show_Foe\n    Jump_To touch\n    Hide_Foe\n")
	assert_array(_warnings(far, ["start", "touch", "touch"])).has_size(2)


func test_no_warnings_without_known_entry_points_or_with_errors() -> void:
	assert_array(_warnings(STUDENT, [])).is_empty()                                  # sector not found
	assert_array(_warnings(STUDENT, ["start", "nowhere"])).is_empty()                # the .tres names a label the text lacks
	assert_array(_warnings(STUDENT.replace("Show_Foe", "Frobnicate"), ["start", "touch"])).is_empty()    # an error: the errors come first


const FILLER := "never executed (no creature start/hit/ink entry or jump reaches it)"


func test_a_reached_padding_is_a_warning_found_by_reachability_not_by_position() -> void:
	var reached := "start:\n    Set_Frame 1\n    Padding 2\n    Jump_To start\n"
	var warnings := _warnings(reached, ["start"])
	assert_array(warnings).has_size(1)
	assert_str(warnings[0]).starts_with("line 3: Padding is reached and would run as Wait_Next_Tick (2 ticks of doing nothing)")
	assert_str(_warnings(reached.replace("Padding 2", "Padding"), ["start"])[0]).contains("(1 tick of doing nothing)")
	# no comment silences it
	var commented := reached.replace("    Padding 2", "    ; The following instructions are not executed -- on purpose\n    Padding 2")
	assert_array(_warnings(commented, ["start"])).has_size(1)
	# it is reached by a jump, a call and a creature's entry too, and by a skip over a conditional
	assert_array(_warnings("start:\n    Jump_To pad\npad:\n    Padding 3\n    Jump_To start\n", ["start"])).has_size(1)
	assert_array(_warnings("start:\n    Call_Subroutine pad\n    Return\npad:\n    Padding 3\n    Return\n", ["start"])).has_size(1)
	assert_array(_warnings("start:\n    Return\npad:\n    Padding 3\n    Return\n", ["start", "pad"])).has_size(1)
	assert_array(_warnings("start:\n    If_Flag 1\n    Jump_To start\n    Padding 1\n    Jump_To start\n", ["start"])).has_size(1)


func test_a_padding_nobody_reaches_is_no_warning() -> void:
	assert_array(_warnings("start:\n    Jump_To start\n    Padding 4\n", ["start"])).is_empty()
	assert_array(_warnings("start:\n    Jump_To start\ntouch:\n    Return\n    Padding 9\n", ["start", "touch"])).is_empty()
	# several Padding lines in a row, with a label between them
	assert_array(_warnings("start:\n    Jump_To start\n    Padding 4\nloc:\n    Padding\n    Padding 2\n", ["start"])).is_empty()


func test_dead_wait_next_tick_lines_get_a_hint_to_write_padding() -> void:
	assert_array(_warnings("start:\n    Jump_To start\n    Wait_Next_Tick\n    Wait_Next_Tick\n", ["start"])).is_equal(
			["line 3: %s; if it is only filler, write Padding 2 instead" % FILLER])
	# mixed with other code: no hint
	assert_array(_warnings("start:\n    Jump_To start\n    Wait_Next_Tick\n    Hide_Foe\n", ["start"])).is_equal(["line 3: " + FILLER])
	# Padding lines in the run are not counted as code or as filler to convert
	assert_array(_warnings("start:\n    Jump_To start\n    Padding 3\n    Hide_Foe\n", ["start"])).is_equal(["line 4: " + FILLER])
	assert_array(_warnings("start:\n    Jump_To start\n    Padding 3\n    Wait_Next_Tick\n", ["start"])).is_equal(
			["line 4: %s; if it is only filler, write Padding 1 instead" % FILLER])
	assert_array(_warnings("start:\n    Jump_To start\n    Hide_Foe\n    Padding 3\n    Show_Foe\n", ["start"])).is_equal(["line 3: " + FILLER])


func test_the_not_executed_comment_silences_the_dead_code_warning_but_not_a_reached_padding() -> void:
	var dead := "start:\n    Jump_To start\n    ; The following instructions are not executed -- spare\n    Wait_Next_Tick\n"
	assert_array(_warnings(dead, ["start"])).is_empty()
	assert_array(_warnings(dead.replace("    Wait_Next_Tick", "    Padding\n    Hide_Foe"), ["start"])).is_empty()
	# the warnings come in line order
	var both := "start:\n    Wait_Next_Tick\n    Padding 2\n    Jump_To start\n    Hide_Foe\n"
	var warnings := _warnings(both, ["start"])
	assert_array(warnings).has_size(2)
	assert_str(warnings[0]).starts_with("line 3: Padding is reached")
	assert_str(warnings[1]).is_equal("line 5: " + FILLER)


# --- hand-written scripts --------------------------------------------------------------

func test_hand_written_script_assembles_to_the_expected_bytes() -> void:
	var result := FoeAsm.assemble(HAND_WRITTEN, 100)
	assert_array(result.errors).is_empty()
	assert_array(result.bytes).is_equal(PackedByteArray([
		Op.FRAME_RANGE, 0, 3,                      # 100
		Op.MOVE_REL, 2, 253, 1,                    # 103  dy = -3
		Op.LOOP0, 0xF7, 0xFF, 4, 0,                # 107  next = 112, 103 - 112 = -9
		Op.SLEEP_FOE, 0x81,                        # 112  self+1
		Op.JMP, 1, 0,                              # 114  next = 117, 118 - 117 = +1
		Op.HIDE,                                   # 117
		Op.YIELD,                                  # 118
		Op.JMP, 0xEA, 0xFF,                        # 119  next = 122, 100 - 122 = -22
	]))
	assert_dict(result.labels).is_equal({"start": 100, "again": 103, "done": 118})


func test_names_are_case_insensitive_and_several_labels_can_share_a_place() -> void:
	var result := FoeAsm.assemble("a:\nb:\n  HIDE_FOE\n  wait_next_tick\n  SET_FRAME 130", 10)
	assert_array(result.errors).is_empty()
	assert_array(result.bytes).is_equal(PackedByteArray([Op.HIDE, Op.YIELD, Op.SET_FRAME, 130]))
	assert_int(result.labels["a"]).is_equal(10)
	assert_int(result.labels["b"]).is_equal(10)


func test_self_offsets_cover_the_whole_signed_range() -> void:
	var result := FoeAsm.assemble("Wake_Foe self-64\nWake_Foe self+63\nWake_Foe SELF+0\nWake_Foe 127", 0)
	assert_array(result.errors).is_empty()
	assert_array(result.bytes).is_equal(PackedByteArray([Op.WAKE_FOE, 0xC0, Op.WAKE_FOE, 0xBF, Op.WAKE_FOE, 0x80, Op.WAKE_FOE, 127]))


func test_a_label_at_the_very_end_is_allowed() -> void:
	var result := FoeAsm.assemble("Jump_To end\nend:", 0)
	assert_array(result.errors).is_empty()
	assert_array(result.bytes).is_equal(PackedByteArray([Op.JMP, 0, 0]))
	assert_int(result.labels["end"]).is_equal(3)


# --- the Padding pseudo-instruction ------------------------------------------------------

func test_padding_assembles_to_that_many_zero_bytes() -> void:
	var result := FoeAsm.assemble("start:\n    Hide_Foe\n    Padding 3\n    Jump_To end\n    PADDING\n    padding 2\nend:\n", 10)
	assert_array(result.errors).is_empty()
	assert_array(result.bytes).is_equal(PackedByteArray([Op.HIDE, 0, 0, 0, Op.JMP, 3, 0, 0, 0, 0]))
	assert_dict(result.labels).is_equal({"start": 10, "end": 20})            # a jump measures across the padding: 3 bytes
	assert_dict(result.paddings).is_equal({11: {"line": 3, "count": 3}, 17: {"line": 5, "count": 1}, 18: {"line": 6, "count": 2}})
	assert_dict(result.instruction_lines).is_equal({10: 2, 11: 3, 14: 4, 17: 5, 18: 6})


func test_padding_is_a_directive_not_an_opcode() -> void:
	# the instruction tables and the VM are untouched: zero is Wait_Next_Tick, and no byte decodes as Padding
	assert_bool(FoeOps.MNEMONIC.has("Padding")).is_false()
	assert_int(FoeOps.OPERAND_COUNT.size()).is_equal(FoeOps.Op.size())
	assert_bool(FoeOps.is_valid(FoeOps.PADDING)).is_false()
	assert_bool(FoeOps.is_pseudo(FoeOps.PADDING)).is_true()
	var vm := _vm_from("Padding 2\nHide_Foe")
	var ctx := FoeVM.Context.new()
	vm.tick(ctx)
	vm.tick(ctx)
	assert_bool(vm.hidden).is_false()               # two Wait_Next_Tick
	vm.tick(ctx)
	assert_bool(vm.hidden).is_true()


func test_padding_limits() -> void:
	var biggest := FoeAsm.assemble("Padding 65535\nend:", 0)
	assert_array(biggest.errors).is_empty()
	assert_int(biggest.bytes.size()).is_equal(65535)
	assert_int(biggest.labels["end"]).is_equal(65535)
	assert_array(_errors("Padding 65536")).is_equal(["line 1: Padding count must be 1..65535, got 65536"])
	assert_array(_errors("Padding 0")).is_equal(["line 1: Padding count must be 1..65535, got 0"])
	assert_array(_errors("x:\nPadding -3")).is_equal(["line 2: Padding count must be 1..65535, got -3"])
	assert_array(_errors("Padding many")).is_equal(["line 1: Padding count must be 1..65535, got 'many'"])
	assert_array(_errors("Padding 2.5")).is_equal(["line 1: Padding count must be 1..65535, got '2.5'"])
	assert_array(_errors("Padding 2 3")).is_equal(["line 1: Padding takes at most 1 operand (count), got 2"])


func test_a_bad_padding_does_not_hide_other_errors_or_cause_jump_range_errors() -> void:
	assert_array(_errors("Padding 0\nJump_To nowhere\nPadding 1\nBogus")).is_equal([
		"line 1: Padding count must be 1..65535, got 0",
		"line 2: unknown label 'nowhere'",
		"line 4: unknown instruction 'Bogus'"])
	# the size of the bad line is unknown, so a far jump is not reported as out of range
	assert_array(_errors("Jump_To far\nPadding 40000\nPadding 0\nfar:")).has_size(1)


# --- error reporting ---------------------------------------------------------------------

func test_error_jump_needs_a_label() -> void:
	assert_array(_errors("Wait_Next_Tick\nJump_To 40")).is_equal(["line 2: Jump_To needs a label, got '40'"])


func test_error_unknown_label() -> void:
	assert_array(_errors("\n\nJump_To loop2")).is_equal(["line 3: unknown label 'loop2'"])


func test_error_operand_out_of_range() -> void:
	assert_array(_errors("; x\nMove_Foe_Relative_XY 200 0 1")).is_equal(["line 2: Move_Foe_Relative_XY dx must be -128..127, got 200"])
	assert_array(_errors("Play_Sound 256")).is_equal(["line 1: Play_Sound operand must be 0..255, got 256"])
	assert_array(_errors("Loop_Counter2_Back_To x 70000\nx:")).is_equal(["line 1: Loop_Counter2_Back_To count must be 0..65535, got 70000"])
	assert_array(_errors("Set_Frame 1,")).is_equal(["line 1: Set_Frame operand must be 0..255, got '1,'"])


func test_error_bad_creature_reference() -> void:
	assert_array(_errors("Wake_Foe 128")).has_size(1)
	assert_str(_errors("Wake_Foe 128")[0]).starts_with("line 1: Wake_Foe foe must be 0..127 or self")
	assert_array(_errors("Wake_Foe self+64")).has_size(1)
	assert_array(_errors("Wake_Foe self+-3")).has_size(1)
	assert_array(_errors("Wake_Foe selfish")).has_size(1)


func test_error_duplicate_label() -> void:
	assert_array(_errors("a:\nHide_Foe\nb:\na:")).is_equal(["line 4: duplicate label 'a' (first defined on line 1)"])


func test_error_wrong_operand_count() -> void:
	assert_array(_errors("Move_Foe_Relative_XY 1 2")).is_equal(["line 1: Move_Foe_Relative_XY needs 3 operands (dx dy frame), got 2"])
	assert_array(_errors("Hide_Foe 1")).is_equal(["line 1: Hide_Foe takes no operands, got 1"])
	assert_array(_errors("Play_Sound")).is_equal(["line 1: Play_Sound needs 1 operand (operand), got 0"])


func test_error_unknown_instruction() -> void:
	assert_array(_errors("Hide_Foe\nDance 3")).is_equal(["line 2: unknown instruction 'Dance'"])
	# The short names of the original are not accepted, but the message points the way.
	assert_array(_errors("MOVE_REL 1 1 1")).is_equal(["line 1: unknown instruction 'MOVE_REL' (did you mean Move_Foe_Relative_XY?)"])
	assert_str(_errors("start: Hide_Foe")[0]).contains("a label goes on a line of its own")


func test_error_jump_out_of_range() -> void:
	var source := "Jump_To far\n" + "Set_Frame 1\n".repeat(17000) + "far:"     # 34000 bytes away
	var errors := _errors(source)
	assert_array(errors).has_size(1)
	assert_str(errors[0]).starts_with("line 1: Jump_To to 'far' is 34000 bytes away")
	# Just inside the limit is fine: 3 + 2 * 16382 = 32767 bytes after the Jump_To's end.
	assert_array(_errors("Jump_To far\n" + "Set_Frame 1\n".repeat(16383) + "far:")).is_empty()


func test_all_errors_are_reported_in_line_order_and_no_bytes_come_out() -> void:
	var result := FoeAsm.assemble("Jump_To nowhere\nBogus\nSet_Frame 999\nJump_To 5\nx:\nx:", 0)
	assert_array(result.errors).is_equal([
		"line 1: unknown label 'nowhere'",
		"line 2: unknown instruction 'Bogus'",
		"line 3: Set_Frame operand must be 0..255, got 999",
		"line 4: Jump_To needs a label, got '5'",
		"line 6: duplicate label 'x' (first defined on line 5)",
	])
	assert_int(result.bytes.size()).is_equal(0)


# --- the assembled bytes run in the VM -----------------------------------------------------

func _vm_from(source: String, foe_index: int = 0) -> FoeVM:
	var result := FoeAsm.assemble(source, 0)
	assert_array(result.errors).is_empty()
	var data := FoeData.new()
	data.pos = Vector2i(100, 50)
	data.frame_max = 255
	var vm := FoeVM.new()
	vm.index = foe_index
	vm.setup(data, result.bytes, 0)
	return vm


func test_assembled_move_loop_moves_the_foe_then_falls_through() -> void:
	var vm := _vm_from("""
top:
    Move_Foe_Relative_XY 3 -1 0     ; right 6 pixels, up 2
    Loop_Counter0_Back_To top 2     ; the body runs count + 1 = 3 times
    Hide_Foe
""")
	var ctx := FoeVM.Context.new()
	for i in 3:
		vm.tick(ctx)
	assert_vector(Vector2(vm.x, vm.y)).is_equal(Vector2(118, 44))
	assert_bool(vm.hidden).is_false()
	vm.tick(ctx)                          # the loop is over: Hide_Foe runs
	assert_bool(vm.hidden).is_true()
	assert_vector(Vector2(vm.x, vm.y)).is_equal(Vector2(118, 44))
	assert_str(vm.fault).is_empty()


func test_assembled_self_plus_one_puts_the_next_creature_to_sleep() -> void:
	var first := _vm_from("Put_Foe_To_Sleep self+1\nWait_Next_Tick\nWake_Foe 1\nWait_Next_Tick", 0)
	var second := _vm_from("Wait_Next_Tick", 1)
	var ctx := FoeVM.Context.new()
	ctx.foes = [first, second]
	first.tick(ctx)
	assert_bool(second.dormant).is_true()
	assert_bool(first.dormant).is_false()
	first.tick(ctx)
	assert_bool(second.dormant).is_false()


## The port's own instruction is known to the assembler and the disassembler in every sector (the editor offers it); whether a creature runs it depends on the campaign (`test_rule_hooks.gd`).
func test_the_mod_instruction_assembles_and_disassembles_like_any_other() -> void:
	var result := FoeAsm.assemble("start:\n    Mod_Instruction 3 200\n    Wait_Next_Tick\n    Jump_To start\n", 0)
	assert_bool(result.ok()).override_failure_message(str(result.errors)).is_true()
	assert_array(Array(result.bytes)).is_equal([FoeOps.Op.MOD_INSTRUCTION, 3, 200, FoeOps.Op.YIELD, FoeOps.Op.JMP, 249, 255])
	var text := FoeAsm.disassemble(result.bytes, 0, {"start": 0})
	assert_str(text).contains("Mod_Instruction 3 200")
	assert_array(Array(FoeAsm.assemble(text, 0).bytes)).is_equal(Array(result.bytes))
	assert_bool(FoeAsm.assemble("Mod_Instruction 256 0\n", 0).ok()).is_false()
	assert_bool(FoeAsm.assemble("Mod_Instruction 1\n", 0).ok()).is_false()
	assert_str(FoeOps.disassemble_one(result.bytes, 0, 0)).is_equal("0000: Mod_Instruction 3 200")
