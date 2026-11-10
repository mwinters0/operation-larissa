class_name TestFoeOpsTable
extends GdUnitTestSuite
## Teaches: one table as the single source of truth. FoeOps.OPERANDS says what each
## instruction's operands are; the assembler, the disassembler, the editor's hints and the
## manual all have to agree with it, and these tests are what keeps them honest. The
## byte counts of the original game (OPERAND_COUNT) are the cross-check: the table is a
## second description of the same fact and must add up to it.

const MANUAL := "res://../docs/create/FOE_SCRIPTING.md"


func test_the_parallel_tables_have_one_entry_per_opcode() -> void:
	var count := FoeOps.Op.size()
	assert_int(FoeOps.OPERAND_COUNT.size()).is_equal(count)
	assert_int(FoeOps.MNEMONIC.size()).is_equal(count)
	assert_int(FoeOps.SUMMARY.size()).is_equal(count)
	assert_int(FoeOps.OPERANDS.size()).is_equal(count)


func test_operand_widths_add_up_to_the_operand_count_of_every_opcode() -> void:
	for opcode in FoeOps.OPERAND_COUNT.size():
		assert_int(FoeOps.operand_bytes(opcode)).override_failure_message(FoeOps.op_name(opcode)).is_equal(FoeOps.OPERAND_COUNT[opcode])


func test_every_operand_is_described() -> void:
	for opcode in FoeOps.OPERANDS.size():
		var names: Array[String] = []
		for operand in FoeOps.operands(opcode):
			var where := "%s %s" % [FoeOps.op_name(opcode), operand.get("name", "?")]
			assert_bool(FoeAsm.is_identifier(operand["name"])).override_failure_message(where).is_true()
			assert_bool(names.has(operand["name"])).override_failure_message(where + " is named twice").is_false()
			names.append(operand["name"])
			assert_int(operand["kind"]).override_failure_message(where).is_between(0, FoeOps.Kind.size() - 1)
			assert_str(operand["meaning"]).override_failure_message(where).is_not_empty()
		assert_str(FoeOps.SUMMARY[opcode]).override_failure_message(FoeOps.op_name(opcode)).is_not_empty()


func test_only_a_first_operand_is_a_label() -> void:
	var with_label := 0
	for opcode in FoeOps.OPERANDS.size():
		var list := FoeOps.operands(opcode)
		for k in list.size():
			if list[k]["kind"] == FoeOps.Kind.LABEL:
				assert_int(k).override_failure_message(FoeOps.op_name(opcode)).is_equal(0)
				with_label += 1
	assert_int(with_label).is_equal(5)                    # Jump_To, Call_Subroutine, three loops
	assert_int(FoeOps.operands(999).size()).is_equal(0)


func test_ranges_and_their_text() -> void:
	assert_that(FoeOps.kind_range(FoeOps.Kind.U8)).is_equal(Vector2i(0, 255))
	assert_that(FoeOps.kind_range(FoeOps.Kind.I8)).is_equal(Vector2i(-128, 127))
	assert_that(FoeOps.kind_range(FoeOps.Kind.U16)).is_equal(Vector2i(0, 65535))
	assert_that(FoeOps.kind_range(FoeOps.Kind.FOE)).is_equal(Vector2i(0, 127))
	assert_str(FoeOps.range_text(FoeOps.Kind.I8)).is_equal("-128..127")
	assert_str(FoeOps.range_text(FoeOps.Kind.LABEL)).is_equal("a label")
	assert_str(FoeOps.range_text(FoeOps.Kind.FOE)).is_equal("0..127 or self, self+N, self-N with N from -64 to 63")
	assert_int(FoeOps.kind_width(FoeOps.Kind.LABEL)).is_equal(2)
	assert_int(FoeOps.kind_width(FoeOps.Kind.U16)).is_equal(2)
	assert_int(FoeOps.kind_width(FoeOps.Kind.U8)).is_equal(1)


func test_signature_lists_the_operand_names_and_can_mark_one() -> void:
	assert_str(FoeOps.signature(FoeOps.Op.SET_POS)).is_equal("Move_Foe_To_XY x y frame")
	assert_str(FoeOps.signature(FoeOps.Op.RET)).is_equal("Return")
	assert_str(FoeOps.signature(FoeOps.Op.LOOP1)).is_equal("Loop_Counter1_Back_To label count")
	var mark := FoeOps.HINT_MARK
	assert_str(FoeOps.signature(FoeOps.Op.SET_POS, 1)).is_equal("Move_Foe_To_XY x %sy%s frame" % [mark, mark])
	assert_int(mark.unicode_at(0)).is_equal(0xFFFF)


func test_parse_foe() -> void:
	assert_int(FoeOps.parse_foe("0")).is_equal(0)
	assert_int(FoeOps.parse_foe("127")).is_equal(127)
	assert_int(FoeOps.parse_foe("128")).is_equal(-1)
	assert_int(FoeOps.parse_foe("-1")).is_equal(-1)
	assert_int(FoeOps.parse_foe("self")).is_equal(0x80)
	assert_int(FoeOps.parse_foe("SELF+2")).is_equal(0x82)
	assert_int(FoeOps.parse_foe("self-1")).is_equal(0xFF)
	assert_int(FoeOps.parse_foe("self+63")).is_equal(0xBF)
	assert_int(FoeOps.parse_foe("self-64")).is_equal(0xC0)
	assert_int(FoeOps.parse_foe("self+64")).is_equal(-1)
	assert_int(FoeOps.parse_foe("self+")).is_equal(-1)
	assert_int(FoeOps.parse_foe("selfie")).is_equal(-1)


## The assembler takes its limits from the table: the largest valid value of every operand
## assembles, one more is refused, and so is one less than the smallest (when the kind has
## a smaller refusal; a creature's self+N form has its own limits, tested above).
func test_the_assembler_accepts_exactly_the_range_of_the_table() -> void:
	for opcode in FoeOps.OPERANDS.size():
		var list := FoeOps.operands(opcode)
		for k in list.size():
			var kind: int = list[k]["kind"]
			if kind == FoeOps.Kind.LABEL:
				continue
			var limits := FoeOps.kind_range(kind)
			for edge in [[limits.x, true], [limits.y, true], [limits.x - 1, false], [limits.y + 1, false]]:
				var words: Array[String] = []
				for j in list.size():
					words.append("x" if list[j]["kind"] == FoeOps.Kind.LABEL else str(edge[0] if j == k else FoeOps.kind_range(list[j]["kind"]).x))
				var result := FoeAsm.assemble("x:\n%s %s\n" % [FoeOps.op_name(opcode), " ".join(words)], 0)
				var message := "%s with %s" % [FoeOps.op_name(opcode), " ".join(words)]
				assert_bool(result.ok()).override_failure_message(message + ": " + str(result.errors)).is_equal(edge[1])
				assert_bool(result.bytes.size() == 1 + FoeOps.OPERAND_COUNT[opcode]).override_failure_message(message).is_equal(edge[1])


## The manual and the table must say the same: the section of each instruction (the "###"
## heading that names it, down to the next heading) mentions each operand name in backticks.
func test_the_manual_names_every_operand_of_every_instruction() -> void:
	var lines := FileAccess.get_file_as_string(MANUAL).split("\n")
	assert_int(lines.size()).is_greater(100)
	for opcode in FoeOps.MNEMONIC.size():
		var name := FoeOps.MNEMONIC[opcode]
		var start := -1
		for n in lines.size():
			if lines[n].begins_with("### ") and (lines[n].contains("`%s " % name) or lines[n].contains("`%s`" % name)):
				start = n
				break
		assert_int(start).override_failure_message("no section for " + name).is_greater_equal(0)
		var section: Array[String] = [lines[start]]
		for n in range(start + 1, lines.size()):
			if lines[n].begins_with("#"):
				break
			section.append(lines[n])
		var body := "\n".join(section)
		for operand in FoeOps.operands(opcode):
			assert_bool(body.contains("`%s`" % operand["name"])).override_failure_message("%s: the manual never mentions `%s`" % [name, operand["name"]]).is_true()
		# The heading also shows the real signature for the first instruction of a shared section.
		if lines[start].contains("`%s " % name):
			assert_bool(lines[start].contains("`%s`" % FoeOps.signature(opcode))).override_failure_message("heading of " + name).is_true()


# --- the Padding pseudo-instruction: modelled apart from the opcodes ---------------------

func test_padding_is_in_the_pseudo_table_and_not_in_the_opcode_tables() -> void:
	assert_int(FoeOps.PSEUDO.size()).is_equal(1)
	assert_bool(FoeOps.MNEMONIC.has("Padding")).is_false()
	assert_int(FoeOps.PADDING).is_greater_equal(256)                       # above every byte: it cannot be an opcode
	assert_bool(FoeOps.is_pseudo(FoeOps.PADDING)).is_true()
	assert_bool(FoeOps.is_pseudo(FoeOps.Op.SHOW)).is_false()
	assert_bool(FoeOps.is_valid(FoeOps.PADDING)).is_false()
	assert_int(FoeOps.PSEUDO_FIRST + FoeOps.PSEUDO.size()).is_equal(FoeOps.PADDING + 1)
	assert_int(FoeOps.op_from_mnemonic("padding")).is_equal(FoeOps.PADDING)
	assert_int(FoeOps.op_from_mnemonic("PADDING")).is_equal(FoeOps.PADDING)
	assert_int(FoeOps.op_from_mnemonic("Pad")).is_equal(-1)
	assert_str(FoeOps.op_name(FoeOps.PADDING)).is_equal("Padding")
	assert_array(FoeOps.listed()).has_size(FoeOps.MNEMONIC.size() + 1)
	assert_int(FoeOps.listed()[-1]).is_equal(FoeOps.PADDING)


func test_padding_is_described_like_an_instruction() -> void:
	var entry := FoeOps.PSEUDO[0]
	assert_bool(FoeAsm.is_identifier(entry["name"])).is_true()
	assert_str(FoeOps.summary(FoeOps.PADDING)).is_not_empty()
	assert_str(FoeOps.summary(FoeOps.Op.RET)).is_equal(FoeOps.SUMMARY[FoeOps.Op.RET])
	assert_str(FoeOps.summary(999)).is_empty()
	var list := FoeOps.operands(FoeOps.PADDING)
	assert_int(list.size()).is_equal(1)
	assert_str(list[0]["name"]).is_equal("count")
	assert_int(list[0]["kind"]).is_equal(FoeOps.Kind.COUNT)
	assert_bool(list[0]["optional"]).is_true()
	assert_str(list[0]["meaning"]).is_not_empty()
	assert_that(FoeOps.kind_range(FoeOps.Kind.COUNT)).is_equal(Vector2i(1, 65535))
	assert_int(FoeOps.PADDING_MAX).is_equal(65535)
	assert_str(FoeOps.range_text(FoeOps.Kind.COUNT)).is_equal("1..65535")
	assert_str(FoeOps.kind_name(FoeOps.Kind.COUNT)).is_equal("number of bytes")
	assert_int(FoeOps.kind_width(FoeOps.Kind.COUNT)).is_equal(0)               # the count is not stored in any byte
	assert_str(FoeOps.signature(FoeOps.PADDING)).is_equal("Padding [count]")
	assert_str(FoeOps.signature(FoeOps.PADDING, 0)).is_equal("Padding %s[count]%s" % [FoeOps.HINT_MARK, FoeOps.HINT_MARK])


func test_the_assembler_accepts_exactly_the_range_of_padding() -> void:
	var limits := FoeOps.kind_range(FoeOps.Kind.COUNT)
	for edge in [[limits.x, true], [limits.y, true], [limits.x - 1, false], [limits.y + 1, false]]:
		var result := FoeAsm.assemble("Padding %d" % edge[0], 0)
		assert_bool(result.ok()).override_failure_message("Padding %d: %s" % [edge[0], result.errors]).is_equal(edge[1])
		if edge[1]:
			assert_int(result.bytes.size()).is_equal(edge[0])
	assert_int(FoeAsm.assemble("Padding", 0).bytes.size()).is_equal(1)          # the count may be left out: 1


func test_the_manual_documents_padding_as_a_pseudo_instruction() -> void:
	var lines := FileAccess.get_file_as_string(MANUAL).split("\n")
	var start := -1
	for n in lines.size():
		if lines[n].begins_with("### ") and lines[n].contains("`Padding [count]`"):
			start = n
			break
	assert_int(start).override_failure_message("no section for Padding").is_greater_equal(0)
	assert_bool(lines[start].to_lower().contains("pseudo")).is_true()
	var section: Array[String] = []
	for n in range(start + 1, lines.size()):
		if lines[n].begins_with("#"):
			break
		section.append(lines[n])
	var body := "\n".join(section)
	for operand in FoeOps.operands(FoeOps.PADDING):
		assert_bool(body.contains("`%s`" % operand["name"])).is_true()
	assert_bool(body.contains("65535")).is_true()
