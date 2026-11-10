class_name TestFoeSourceMap
extends GdUnitTestSuite
## Teaches: testing a debugger's map from both ends. Hand-written scripts show what the map answers; then the data of every sector of the chain
## proves it: every instruction the VM can run maps to a line, and THAT LINE'S TEXT, assembled on its own,
## gives back the very bytes of the instruction (a label operand needs its label, so the check builds a tiny script around the
## line that puts the label where the sector has it). A live creature's program counter is checked too: it never points
## anywhere the map does not know.

const SCRIPT := """
; two creatures
walker:
    Move_Foe_Relative_XY 2 0 1     ; step
    Loop_Counter0_Back_To walker 3

    Jump_To hurt
; unused
sleeper:
    Wait_Next_Tick
    Jump_To sleeper
hurt:
    Hide_Foe
    Return
"""


func _foe(start: String, hit: String, ink: String) -> FoeData:
	var data := FoeData.new()
	data.start_label = start
	data.hit_label = hit
	data.ink_label = ink
	return data


# --- hand-written scripts ----------------------------------------------------

func test_a_pc_maps_to_its_line_and_text() -> void:
	var map := FoeSourceMap.from_source(SCRIPT, 100)
	assert_int(map.line_of(100)).is_equal(4)                       # the first instruction is on line 4 of the text
	assert_str(map.line_text(4)).is_equal("    Move_Foe_Relative_XY 2 0 1     ; step")
	assert_int(map.line_of(104)).is_equal(5)                       # Move_Foe_Relative_XY is 4 bytes
	assert_int(map.line_of(101)).is_equal(0)                       # inside an instruction
	assert_int(map.line_of(50)).is_equal(0)                        # before the script
	assert_int(map.line_of(9999)).is_equal(0)
	assert_int(map.offset_of(5)).is_equal(104)
	assert_int(map.offset_of(1)).is_equal(-1)                      # a blank line
	assert_int(map.offset_of(3)).is_equal(-1)                      # a label line


func test_a_line_knows_the_label_it_is_under() -> void:
	var map := FoeSourceMap.from_source(SCRIPT, 100)
	assert_str(map.label_above(1)).is_empty()                      # before the first label
	assert_str(map.label_above(3)).is_equal("walker")              # the label line itself
	assert_str(map.label_above(7)).is_equal("walker")              # a comment line and a blank line do not end it
	assert_str(map.label_above(10)).is_equal("sleeper")
	assert_str(map.label_above(13)).is_equal("hurt")
	assert_str(map.label_above(99)).is_empty()
	assert_str(map.describe(100)).is_equal("line 4 under 'walker': Move_Foe_Relative_XY 2 0 1     ; step")
	assert_str(map.describe(101)).contains("no source line")


func test_a_text_with_errors_has_no_bytes_but_still_lines() -> void:
	var map := FoeSourceMap.from_source("a:\n    Jump_To nowhere\n", 0)
	assert_bool(map.bytes.is_empty()).is_true()
	assert_int(map.line_of(0)).is_equal(2)
	assert_array(map.creatures_at_line([_foe("a", "a", "a")], 2)).is_empty()


func test_creatures_are_found_by_entry_label_first_then_by_reach() -> void:
	var map := FoeSourceMap.from_source(SCRIPT, 0)
	var foes: Array[FoeData] = [
		_foe("walker", "hurt", "hurt"),                            # 0: runs walker, hurt
		_foe("sleeper", "hurt", "sleeper"),                        # 1: runs sleeper, hurt
		_foe("hurt", "hurt", "hurt"),                              # 2: only the hurt block
		_foe("walker", "walker", "no_such_label"),                 # 3: broken labels: ignored
	]
	assert_array(map.creatures_at_line(foes, 4)).is_equal([0] as Array[int])           # Move_Foe_Relative_XY, under walker
	assert_array(map.creatures_at_line(foes, 7)).is_equal([0] as Array[int])           # Jump_To hurt, still under walker
	assert_array(map.creatures_at_line(foes, 10)).is_equal([1] as Array[int])          # Wait_Next_Tick, under sleeper
	assert_array(map.creatures_at_line(foes, 13)).is_equal([0, 1, 2] as Array[int])    # Hide_Foe, under hurt: all three enter there
	# a creature that does not enter at the line's label but runs through it comes after those that do
	var fall_through := FoeSourceMap.from_source("a:\n    Wait_Next_Tick\nb:\n    Hide_Foe\n    Return\n", 0)
	var pair: Array[FoeData] = [_foe("a", "a", "a"), _foe("b", "b", "b")]
	assert_array(fall_through.creatures_at_line(pair, 4)).is_equal([1, 0] as Array[int])
	assert_array(fall_through.creatures_at_line(pair, 2)).is_equal([0] as Array[int])   # only creature 0 starts at a


func test_a_comment_or_blank_line_stands_for_the_next_instruction() -> void:
	var map := FoeSourceMap.from_source(SCRIPT, 0)
	var foes: Array[FoeData] = [_foe("sleeper", "sleeper", "sleeper")]
	assert_array(map.creatures_at_line(foes, 8)).is_equal([0] as Array[int])           # `; unused`: the next instruction is under sleeper
	assert_array(map.creatures_at_line(foes, 9)).is_equal([0] as Array[int])           # the label line
	assert_array(map.creatures_at_line(foes, 6)).is_empty()                            # a blank line before Jump_To hurt (under walker)
	assert_array(map.creatures_at_line(foes, 40)).is_empty()                           # past the end


# --- the real data -------------------------------------------------------------

## The instruction (or Padding) bytes `bytes`, written at buffer offset `at` of `sector`, as text `line_text`: assembled on its
## own. A jump needs its label, so the script is built with a Padding line to put the label at the same distance. Returns "" when
## the line gives back exactly `bytes`, else what differed. `skipped` counts the lines where the label lies inside the
## instruction itself (no script can be built for it).
func _line_gives_back(sector: SectorData, symbols: FoeNames, at: int, line_text: String, bytes: PackedByteArray) -> String:
	var words := line_text.split(";")[0].strip_edges().split(" ", false)
	var opcode := FoeOps.op_from_mnemonic(words[0])
	var source := line_text
	var base := at
	if opcode >= 0 and not FoeOps.is_pseudo(opcode) and FoeOps.operands(opcode).any(func(spec: Dictionary) -> bool: return spec["kind"] == FoeOps.Kind.LABEL):
		var label := words[1]
		assert_bool(sector.foe_labels.has(label)).is_true()
		var target: int = sector.foe_labels[label]
		var next := at + bytes.size()
		if target > at and target < next:
			return ""                                              # cannot be built; nothing to compare
		if target <= at:
			base = target
			source = "%s:\n%s%s\n" % [label, "" if at == target else "Padding %d\n" % (at - target), line_text]
		else:
			source = "%s\n%s%s:\n" % [line_text, "" if next == target else "Padding %d\n" % (target - next), label]
	var result := FoeAsm.assemble(source, base, symbols)
	if not result.errors.is_empty():
		return "does not assemble: %s" % result.errors[0]
	var written := result.bytes.slice(at - base, at - base + bytes.size())
	return "" if written == bytes else "assembles to %s, not %s" % [written, bytes]


func test_every_instruction_of_every_sector_maps_to_a_line_that_assembles_to_it() -> void:
	var checked := 0
	for index in Catalog.sector_ids():
		var sector := Catalog.sector(index)
		var map := sector.foe_source_map
		var symbols := FoeNames.for_sector(sector)
		var script := sector.foe_bytecode
		if script.is_empty():
			assert_int(sector.foes.size()).is_equal(0)                  # (a sector without creatures has no instructions to map)
			continue
		var offsets: Array = map.instruction_lines.keys()
		offsets.sort()
		var padding := {}                                          # byte offsets that a Padding line writes
		for k in offsets.size():
			var at: int = offsets[k]
			var stop: int = offsets[k + 1] if k + 1 < offsets.size() else sector.foe_script_base + script.size()
			var line: int = map.line_of(at)
			var text := map.line_text(line)
			var problem := _line_gives_back(sector, symbols, at, text, script.slice(at - sector.foe_script_base, stop - sector.foe_script_base))
			assert_str(problem).override_failure_message("sector %d offset %d line %d '%s': %s" % [index, at, line, text.strip_edges(), problem]).is_empty()
			assert_int(map.offset_of(line)).is_equal(at)
			if text.strip_edges().to_lower().begins_with("padding"):
				for b in range(at, stop):
					padding[b] = true
			checked += 1
		# every instruction the VM could decode is on a line, unless a Padding line wrote it
		for item in FoeAsm.decode(script, sector.foe_script_base):
			if map.line_of(item["at"]) == 0:
				assert_bool(padding.has(item["at"])).override_failure_message("sector %d: the instruction at %d has no line" % [index, item["at"]]).is_true()
		# the creatures' entry points are instructions with lines
		for foe in sector.foes:
			for entry in [foe.pc, foe.script_hit, foe.script_ink]:
				assert_int(sector.foe_line_of(entry)).override_failure_message("sector %d entry %d has no line" % [index, entry]).is_greater(0)
	assert_int(checked).is_greater(100)


func test_a_live_creatures_pc_is_always_on_a_line() -> void:
	for index in Catalog.sector_ids():
		var sector := Catalog.sector(index)
		var ctx := FoeVM.Context.new()
		ctx.rng.seed = index + 1
		var vms: Array[FoeVM] = []
		for i in sector.foes.size():
			var vm := FoeVM.from_data(sector.foes[i], i, sector)
			vms.append(vm)
			ctx.foes.append(vm)
		for t in 400:
			ctx.current_screen = (t / 20) % 12
			ctx.sub_x = ctx.rng.randi_range(-32, 576)
			ctx.sub_y = ctx.rng.randi_range(3, 290)
			for vm in vms:
				vm.tick(ctx)
				assert_int(sector.foe_line_of(vm.pc)).override_failure_message("sector %d creature %d tick %d: pc %d has no line" % [index, vm.index, t, vm.pc]).is_greater(0)
			ctx.sounds.clear()
			if t % 37 == 0:
				for vm in vms:
					if vm.screen == ctx.current_screen and vm.can_be_interrupted():
						vm.interrupt(vm.script_ink if (t / 37) % 2 == 0 else vm.script_hit)
						break
