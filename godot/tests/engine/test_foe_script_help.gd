class_name TestFoeScriptHelp
extends GdUnitTestSuite
## Teaches: testing the helpers of a text editor without the editor. FoeLineInfo and FoeHelp
## work on Strings and column numbers, so every tooltip, hint and completion is checked by
## handing them a line and a column. FoeCodeEdit is the thin layer that connects them to a
## CodeEdit; a few tests call its functions directly. What needs a real mouse and keyboard
## (the tooltip popup appearing, the completion menu drawn) is checked by hand.

const MARK := FoeOps.HINT_MARK

const SCRIPT := """start:
    Move_Foe_To_XY 12 3 129   ; place it
    Wake_Foe self+2
    Loop_Counter0_Back_To start 4
    Jump_To again
again:
    Jump_To start
stop:
    Return
"""


func _lines(text := SCRIPT) -> PackedStringArray:
	return text.split("\n")


## The column of the nth (0-based) occurrence of `word` in `line`.
func _col(line: String, word: String, nth := 0) -> int:
	var at := -1
	for i in nth + 1:
		at = line.find(word, at + 1)
	return at


func _names(options: Array[Dictionary]) -> Array[String]:
	var names: Array[String] = []
	for option in options:
		names.append(option["name"])
	return names


# --- FoeLineInfo: words and positions ----------------------------------------

func test_tokens_split_at_spaces_and_tabs_and_stop_at_the_comment() -> void:
	var words := FoeLineInfo.tokens("\tMove_Foe_To_XY  12\t3 ;  129")
	assert_int(words.size()).is_equal(3)
	assert_str(words[0].text).is_equal("Move_Foe_To_XY")
	assert_int(words[0].start).is_equal(1)
	assert_int(words[0].end).is_equal(15)
	assert_str(words[2].text).is_equal("3")
	assert_array(FoeLineInfo.tokens("   ; only a comment")).is_empty()
	assert_array(FoeLineInfo.tokens("")).is_empty()


func test_locate_finds_the_word_under_the_mouse() -> void:
	var line := "    Move_Foe_To_XY 12 3 129   ; place it"
	var spot := FoeLineInfo.locate(line, _col(line, "Move"))
	assert_int(spot.part).is_equal(FoeLineInfo.Part.MNEMONIC)
	assert_int(spot.opcode).is_equal(FoeOps.Op.SET_POS)
	assert_int(spot.operand).is_equal(-1)
	for expected in [["12", 0], ["3", 1], ["129", 2]]:
		spot = FoeLineInfo.locate(line, _col(line, expected[0]))
		assert_int(spot.part).is_equal(FoeLineInfo.Part.OPERAND)
		assert_str(spot.token.text).is_equal(expected[0])
		assert_int(spot.operand).is_equal(expected[1])
		assert_str(spot.operand_info()["name"]).is_equal(["x", "y", "frame"][expected[1]])
	assert_int(FoeLineInfo.locate(line, _col(line, "place")).part).is_equal(FoeLineInfo.Part.COMMENT)
	assert_int(FoeLineInfo.locate(line, _col(line, ";")).part).is_equal(FoeLineInfo.Part.COMMENT)
	assert_int(FoeLineInfo.locate(line, 0).part).is_equal(FoeLineInfo.Part.NOTHING)             # the indentation
	assert_int(FoeLineInfo.locate(line, _col(line, "12") + 2).part).is_equal(FoeLineInfo.Part.NOTHING)   # the gap after 12
	assert_int(FoeLineInfo.locate("    Hide_Foe", 500).part).is_equal(FoeLineInfo.Part.NOTHING)       # past the end


func test_locate_knows_labels_unknown_words_and_extra_operands() -> void:
	assert_int(FoeLineInfo.locate("again:", 2).part).is_equal(FoeLineInfo.Part.LABEL_DEFINITION)
	assert_int(FoeLineInfo.locate("    Jmp again", 5).part).is_equal(FoeLineInfo.Part.UNKNOWN_WORD)
	assert_int(FoeLineInfo.locate("    hide_foe", 5).opcode).is_equal(FoeOps.Op.HIDE)           # any case
	var extra := FoeLineInfo.locate("    Hide_Foe 7", 13)
	assert_int(extra.operand).is_equal(0)
	assert_dict(extra.operand_info()).is_empty()                                                  # Hide_Foe has no operand 0


func test_locate_for_the_caret_also_touches_the_end_of_a_word() -> void:
	var line := "    Move_Foe_To_XY 12 3"
	var end_of_name := _col(line, "Move_Foe_To_XY") + "Move_Foe_To_XY".length()
	var spot := FoeLineInfo.locate(line, end_of_name, true)                  # Move_Foe_To_XY|
	assert_int(spot.part).is_equal(FoeLineInfo.Part.MNEMONIC)
	assert_str(spot.typed).is_equal("Move_Foe_To_XY")
	assert_bool(spot.at_instruction()).is_true()
	assert_int(FoeLineInfo.locate(line, end_of_name).part).is_equal(FoeLineInfo.Part.NOTHING)  # a mouse is not at the gap
	spot = FoeLineInfo.locate(line, end_of_name + 1, true)                   # Move_Foe_To_XY |12
	assert_int(spot.operand).is_equal(0)
	spot = FoeLineInfo.locate(line, _col(line, "12") + 2, true)              # 12|
	assert_int(spot.operand).is_equal(0)
	assert_str(spot.typed).is_equal("12")
	spot = FoeLineInfo.locate(line + " ", line.length() + 1, true)           # 3 |
	assert_int(spot.operand).is_equal(2)
	assert_str(spot.typed).is_equal("")
	spot = FoeLineInfo.locate("    ", 2, true)                              # inside the indentation
	assert_bool(spot.at_instruction()).is_true()
	assert_bool(FoeLineInfo.locate("again: ", 7, true).at_instruction()).is_false()
	assert_int(FoeLineInfo.locate("Return ; x", 10, true).part).is_equal(FoeLineInfo.Part.COMMENT)
	assert_int(FoeLineInfo.locate("Return; x", 6, true).part).is_equal(FoeLineInfo.Part.MNEMONIC)  # just before the ;


func test_label_definitions_and_uses() -> void:
	var defined := FoeLineInfo.label_definitions(_lines())
	assert_array(defined.keys()).contains_exactly(["start", "again", "stop"])
	assert_array(defined["start"]).contains_exactly([0])
	assert_array(defined["again"]).contains_exactly([5])
	var uses := FoeLineInfo.label_uses(_lines())
	assert_array(uses["start"]).contains_exactly([3, 6])
	assert_array(uses["again"]).contains_exactly([4])
	assert_bool(uses.has("stop")).is_false()
	var twice := FoeLineInfo.label_definitions(_lines("a:\nReturn\na:\n"))
	assert_array(twice["a"]).contains_exactly([0, 2])
	# A number, or a label name in a place that takes a number, is not a use.
	assert_bool(FoeLineInfo.label_uses(_lines("Set_Frame start\nJump_To 5\n")).is_empty()).is_true()


# --- FoeHelp: tooltips -------------------------------------------------------

func test_tooltip_over_an_instruction_name() -> void:
	var line := _lines()[1]
	var tip := FoeHelp.tooltip(_lines(), 1, _col(line, "Move"))
	var parts := tip.split("\n")
	assert_str(parts[0]).is_equal("Move_Foe_To_XY x y frame")
	assert_str(parts[1]).is_equal(FoeOps.SUMMARY[FoeOps.Op.SET_POS])
	assert_str(tip).contains("x (unsigned byte, 0..255): horizontal position in 4-pixel steps")
	assert_str(tip).contains("frame (picture, 0..255)")
	assert_str(FoeHelp.tooltip(_lines("Return"), 0, 2)).contains("No operands.")
	assert_str(FoeHelp.tooltip(_lines("Wake_Foe self"), 0, 2)).contains("foe (creature, 0..127 or self, self+N, self-N with N from -64 to 63)")
	assert_str(FoeHelp.tooltip(_lines("    Jmp again"), 0, 5)).contains("'Jmp' is not an instruction")


func test_every_instruction_has_a_tooltip_with_its_signature() -> void:
	for opcode in FoeOps.MNEMONIC.size():
		var tip := FoeHelp.tooltip(_lines(FoeOps.MNEMONIC[opcode]), 0, 1)
		assert_str(tip.split("\n")[0]).override_failure_message(FoeOps.MNEMONIC[opcode]).is_equal(FoeOps.signature(opcode))


func test_tooltip_over_a_number_names_the_operand_and_its_range() -> void:
	var line := _lines()[1]
	var tip := FoeHelp.tooltip(_lines(), 1, _col(line, "12"))
	assert_str(tip).contains("x: operand 1 of Move_Foe_To_XY x y frame")
	assert_str(tip).contains("horizontal position in 4-pixel steps")
	assert_str(tip).contains("unsigned byte (0..255)")
	assert_str(tip).contains("12 is valid: 48 pixels.")
	tip = FoeHelp.tooltip(_lines(), 1, _col(line, "3"))
	assert_str(tip).contains("y: operand 2 of")
	assert_str(tip).contains("3 is valid: 6 pixels.")
	tip = FoeHelp.tooltip(_lines(), 1, _col(line, "129"))
	assert_str(tip).contains("frame: operand 3 of")
	assert_str(tip).contains("Picture bits 1, mirrored")


func test_tooltip_says_when_a_number_is_out_of_range() -> void:
	var tip := FoeHelp.tooltip(_lines("Play_Sound 300"), 0, 12)
	assert_str(tip).contains("sound: operand 1 of Play_Sound sound")
	assert_str(tip).contains("Out of range: 300 is not 0..255.")
	tip = FoeHelp.tooltip(_lines("Move_Foe_Relative_XY -129 0 0"), 0, 22)
	assert_str(tip).contains("Out of range: -129 is not -128..127.")
	assert_str(FoeHelp.tooltip(_lines("Play_Sound 1.5"), 0, 12)).contains("'1.5' is not a whole number")
	assert_str(FoeHelp.tooltip(_lines("Play_Sound loud"), 0, 12)).contains("unknown sound 'loud'")      # a word that could be a name
	assert_str(FoeHelp.tooltip(_lines("Move_Foe_Relative_XY 1 loud 0"), 0, 24)).contains("'loud' is not a whole number")
	assert_str(FoeHelp.tooltip(_lines("Hide_Foe 7"), 0, 9)).contains("takes no operands, so this word is one too many")
	assert_str(FoeHelp.tooltip(_lines("Set_Frame 1 2"), 0, 12)).contains("takes 1 operand, so this word is one too many")


func test_tooltip_over_a_signed_byte_and_a_frame_without_mirror() -> void:
	var tip := FoeHelp.tooltip(_lines("Move_Foe_Relative_XY -3 0 1"), 0, 22)
	assert_str(tip).contains("dx: operand 1 of")
	assert_str(tip).contains("-3 is valid: -6 pixels.")
	assert_str(FoeHelp.tooltip(_lines("Set_Frame 5"), 0, 10)).contains("not mirrored")


func test_tooltip_over_self_explains_the_relative_creature() -> void:
	var line := _lines()[2]
	var tip := FoeHelp.tooltip(_lines(), 2, _col(line, "self"))
	assert_str(tip).contains("foe: operand 1 of Wake_Foe foe")
	assert_str(tip).contains("self+2: the creature 2 places after the one that runs this instruction")
	assert_str(FoeHelp.tooltip(_lines("Wake_Foe self"), 0, 10)).contains("self: the creature that runs this instruction.")
	assert_str(FoeHelp.tooltip(_lines("Wake_Foe self-1"), 0, 10)).contains("self-1: the creature 1 place before")
	assert_str(FoeHelp.tooltip(_lines("Wake_Foe 7"), 0, 9)).contains("Creature number 7")
	assert_str(FoeHelp.tooltip(_lines("Wake_Foe self+99"), 0, 10)).contains("'self+99' is not valid")
	assert_str(FoeHelp.tooltip(_lines("Wake_Foe 200"), 0, 10)).contains("'200' is not valid")


func test_tooltip_over_a_label_definition_counts_its_uses() -> void:
	var tip := FoeHelp.tooltip(_lines(), 0, 2)                       # start:
	assert_str(tip).contains("Label 'start': defined here (line 1).")
	assert_str(tip).contains("Used 2 times.")
	tip = FoeHelp.tooltip(_lines(), 5, 2)                             # again:
	assert_str(tip).contains("defined here (line 6)")
	assert_str(tip).contains("Used once, on line 5.")
	tip = FoeHelp.tooltip(_lines(), 7, 2)                             # stop:
	assert_str(tip).contains("Nothing jumps to it")


func test_tooltip_over_a_label_use_says_where_it_is_defined() -> void:
	var line := _lines()[3]
	var tip := FoeHelp.tooltip(_lines(), 3, _col(line, "start"))
	assert_str(tip).contains("label: operand 1 of Loop_Counter0_Back_To label count")
	assert_str(tip).contains("Label 'start': defined on line 1 (above).")
	assert_str(tip).contains("Used 2 times.")
	tip = FoeHelp.tooltip(_lines(), 4, _col(_lines()[4], "again"))   # a jump forward
	assert_str(tip).contains("defined on line 6 (below).")
	assert_str(FoeHelp.tooltip(_lines("Jump_To nowhere"), 0, 9)).contains("'nowhere' is not defined in this file")
	assert_str(FoeHelp.tooltip(_lines("Jump_To 40"), 0, 9)).contains("'40' is not a label name")
	assert_str(FoeHelp.tooltip(_lines("a:\nReturn\na:\nJump_To a"), 3, 8)).contains("defined 2 times")
	assert_str(FoeHelp.tooltip(_lines("a:\nReturn\na:\n"), 2, 0)).contains("again on line 1")


func test_no_tooltip_over_blank_space_comments_or_outside_the_text() -> void:
	var line := _lines()[1]
	assert_str(FoeHelp.tooltip(_lines(), 1, 0)).is_empty()
	assert_str(FoeHelp.tooltip(_lines(), 1, _col(line, "place"))).is_empty()
	assert_str(FoeHelp.tooltip(_lines(), 1, 400)).is_empty()
	assert_str(FoeHelp.tooltip(_lines(), 99, 0)).is_empty()
	assert_str(FoeHelp.tooltip(_lines(), -1, 0)).is_empty()


# --- FoeHelp: the signature hint ---------------------------------------------

func test_hint_marks_the_operand_being_typed() -> void:
	var line := "    Move_Foe_To_XY "
	var hint := FoeHelp.code_hint(line, line.length())
	assert_str(hint.split("\n")[0]).is_equal("Move_Foe_To_XY %sx%s y frame" % [MARK, MARK])
	assert_str(hint.split("\n")[1]).is_equal("x (0..255): " + FoeOps.operands(FoeOps.Op.SET_POS)[0]["meaning"])
	line = "    Move_Foe_To_XY 12 "
	assert_str(FoeHelp.code_hint(line, line.length()).split("\n")[0]).is_equal("Move_Foe_To_XY x %sy%s frame" % [MARK, MARK])
	line = "    Move_Foe_To_XY 12 3 12"
	assert_str(FoeHelp.code_hint(line, line.length()).split("\n")[0]).is_equal("Move_Foe_To_XY x y %sframe%s" % [MARK, MARK])
	# The caret inside or touching a number marks that number's operand.
	line = "    Move_Foe_To_XY 12 3"
	assert_str(FoeHelp.code_hint(line, line.length()).split("\n")[0]).is_equal("Move_Foe_To_XY x %sy%s frame" % [MARK, MARK])
	assert_str(FoeHelp.code_hint(line, line.find("12") + 1).split("\n")[0]).is_equal("Move_Foe_To_XY %sx%s y frame" % [MARK, MARK])


func test_hint_knows_label_and_creature_operands() -> void:
	var hint := FoeHelp.code_hint("Loop_Counter2_Back_To ", 22)
	assert_str(hint.split("\n")[0]).is_equal("Loop_Counter2_Back_To %slabel%s count" % [MARK, MARK])
	assert_str(hint.split("\n")[1]).starts_with("label (a label): ")
	hint = FoeHelp.code_hint("Loop_Counter2_Back_To start 5", 29)
	assert_str(hint.split("\n")[0]).is_equal("Loop_Counter2_Back_To label %scount%s" % [MARK, MARK])
	assert_str(FoeHelp.code_hint("Wake_Foe ", 9).split("\n")[1]).starts_with("foe (0..127 or self, self+N")


func test_hint_is_cleared_where_it_does_not_apply() -> void:
	assert_str(FoeHelp.code_hint("    Move_Foe_To_XY", 18)).is_empty()                 # still typing the name
	assert_str(FoeHelp.code_hint("    Move_Foe_To_XY 1 2 3 ", 25)).is_empty()          # after the last operand
	assert_str(FoeHelp.code_hint("    Return ", 11)).is_empty()                        # nothing to type
	assert_str(FoeHelp.code_hint("    Jmp ", 8)).is_empty()                            # not an instruction
	assert_str(FoeHelp.code_hint("    Jump_To x ; Wake_Foe ", 24)).is_empty()          # in a comment
	assert_str(FoeHelp.code_hint("    Set_Frame ; ", 15)).is_empty()
	assert_str(FoeHelp.code_hint("again:", 6)).is_empty()
	assert_str(FoeHelp.code_hint("again: ", 7)).is_empty()
	assert_str(FoeHelp.code_hint("", 0)).is_empty()
	assert_str(FoeHelp.code_hint("    ", 4)).is_empty()


# --- FoeHelp: completion -----------------------------------------------------

func test_completion_offers_instruction_names_by_prefix_in_any_case() -> void:
	var lines := _lines("start:\n    Wa")
	assert_array(_names(FoeHelp.completions(lines, 1, 6))).contains_exactly(["Wait_Next_Tick", "Wake_Foe"])
	lines = _lines("    wa")
	assert_array(_names(FoeHelp.completions(lines, 0, 6))).contains_exactly(["Wait_Next_Tick", "Wake_Foe"])
	lines = _lines("    Loop_Counter")
	assert_array(_names(FoeHelp.completions(lines, 0, 16))).contains_exactly(["Loop_Counter0_Back_To", "Loop_Counter1_Back_To", "Loop_Counter2_Back_To"])
	assert_array(_names(FoeHelp.completions(_lines("    Xyz"), 0, 7))).is_empty()
	assert_array(_names(FoeHelp.completions(_lines("    If_"), 0, 7))).has_size(6)      # If_Sub_X/Y x2, If_Random, If_Flag


func test_completion_options_carry_the_summary_and_a_space_after_names_with_operands() -> void:
	var options := FoeHelp.completions(_lines("    Wak"), 0, 7)
	assert_int(options.size()).is_equal(1)
	assert_int(options[0]["type"]).is_equal(FoeHelp.Candidate.MNEMONIC)
	assert_str(options[0]["insert"]).is_equal("Wake_Foe ")
	assert_str(options[0]["summary"]).is_equal(FoeOps.SUMMARY[FoeOps.Op.WAKE_FOE])
	options = FoeHelp.completions(_lines("    Retu"), 0, 8)
	assert_str(options[0]["insert"]).is_equal("Return")                            # no operands: no space


func test_completion_uses_only_what_is_in_front_of_the_caret() -> void:
	# Caret after "Wa" in "Wait_Next_Tick": the rest of the word does not matter.
	assert_array(_names(FoeHelp.completions(_lines("    Wait_Next_Tick"), 0, 6))).contains_exactly(["Wait_Next_Tick", "Wake_Foe"])


func test_completion_offers_labels_where_the_operand_is_a_label() -> void:
	var text := SCRIPT + "    Jump_To st"
	var lines := _lines(text)
	var last := lines.size() - 1
	var options := FoeHelp.completions(lines, last, lines[last].length())
	assert_array(_names(options)).contains_exactly(["start", "stop"])
	assert_int(options[0]["type"]).is_equal(FoeHelp.Candidate.LABEL)
	assert_str(options[0]["summary"]).is_equal("label on line 1")
	# The second operand of a loop is a count, not a label.
	lines = _lines(SCRIPT + "    Loop_Counter1_Back_To start st")
	assert_array(FoeHelp.completions(lines, lines.size() - 1, lines[lines.size() - 1].length())).is_empty()
	# A label is also found in any case, and the one that is exactly typed alone is not offered.
	lines = _lines(SCRIPT + "    Call_Subroutine AG")
	assert_array(_names(FoeHelp.completions(lines, lines.size() - 1, lines[lines.size() - 1].length()))).contains_exactly(["again"])
	lines = _lines(SCRIPT + "    Call_Subroutine again")
	assert_array(FoeHelp.completions(lines, lines.size() - 1, lines[lines.size() - 1].length())).is_empty()


func test_completion_offers_self_where_the_operand_is_a_creature() -> void:
	var options := FoeHelp.completions(_lines("    Wake_Foe s"), 0, 14)
	assert_array(_names(options)).contains_exactly(["self"])
	assert_int(options[0]["type"]).is_equal(FoeHelp.Candidate.SELF)
	assert_array(_names(FoeHelp.completions(_lines("    Put_Foe_To_Sleep Se"), 0, 22))).contains_exactly(["self"])
	assert_array(FoeHelp.completions(_lines("    Wake_Foe x"), 0, 14)).is_empty()
	assert_array(FoeHelp.completions(_lines("    Wake_Foe self+"), 0, 18)).is_empty()
	assert_array(FoeHelp.completions(_lines("    Wake_Foe 12"), 0, 15)).is_empty()
	assert_array(FoeHelp.completions(_lines("    Wake_Foe self"), 0, 17)).is_empty()        # complete already


func test_completion_stays_quiet_when_nothing_is_typed() -> void:
	assert_array(FoeHelp.completions(_lines("    "), 0, 4)).is_empty()
	assert_array(FoeHelp.completions(_lines(SCRIPT + "    Jump_To "), 9, 12)).is_empty()
	assert_array(FoeHelp.completions(_lines("    Wake_Foe "), 0, 13)).is_empty()
	assert_array(FoeHelp.completions(_lines("    Return"), 0, 10)).is_empty()                # the one exact match is not offered
	assert_array(FoeHelp.completions(_lines("again:"), 0, 6)).is_empty()                    # a label line
	assert_array(FoeHelp.completions(_lines("again: Wa"), 0, 9)).is_empty()
	assert_array(FoeHelp.completions(_lines("    Return ; Wa"), 0, 15)).is_empty()          # a comment
	assert_array(FoeHelp.completions(_lines("    Set_Frame 1"), 0, 15)).is_empty()          # a number
	assert_array(FoeHelp.completions(_lines("    Set_Frame 1 Wa"), 0, 18)).is_empty()       # one operand too many
	assert_array(FoeHelp.completions(_lines("x"), 5, 0)).is_empty()


func test_forced_completion_lists_everything_that_fits() -> void:
	assert_int(FoeHelp.completions(_lines("    "), 0, 4, true).size()).is_equal(FoeOps.MNEMONIC.size() + FoeOps.PSEUDO.size())     # the opcodes and Padding
	var lines := _lines(SCRIPT + "    Jump_To ")
	assert_array(_names(FoeHelp.completions(lines, 9, 12, true))).contains_exactly(["start", "again", "stop"])
	var nothing_named := FoeNames.new(NameRegistry.parse('{"format": 1, "names": {}}'))      # a registry without names: only self, and no picture
	assert_array(_names(FoeHelp.completions(_lines("    Wake_Foe "), 0, 13, true, nothing_named))).contains_exactly(["self"])
	assert_array(FoeHelp.completions(_lines("    Set_Frame "), 0, 14, true, nothing_named)).is_empty()
	assert_array(FoeHelp.completions(_lines("    ; "), 0, 6, true)).is_empty()


# --- Padding, the pseudo-instruction -----------------------------------------

func test_the_tooltip_over_padding_describes_the_directive_and_its_optional_count() -> void:
	var tip := FoeHelp.tooltip(_lines("    Padding 4"), 0, 6)
	var parts := tip.split("\n")
	assert_str(parts[0]).is_equal("Padding [count]")
	assert_str(parts[1]).is_equal(FoeOps.summary(FoeOps.PADDING))
	assert_str(parts[1]).starts_with("Not an instruction")
	assert_str(tip).contains("count (number of bytes, 1..65535, optional): how many zero bytes to write")
	assert_str(FoeHelp.tooltip(_lines("    padding"), 0, 6).split("\n")[0]).is_equal("Padding [count]")       # any case, no operand


func test_the_tooltip_over_the_count_says_how_many_bytes_and_whether_it_is_valid() -> void:
	var tip := FoeHelp.tooltip(_lines("    Padding 9"), 0, 12)
	assert_str(tip).contains("count: operand 1 of Padding [count]")
	assert_str(tip).contains("number of bytes (1..65535)")
	assert_str(tip).contains("9 is valid: 9 zero bytes.")
	assert_str(FoeHelp.tooltip(_lines("    Padding 1"), 0, 12)).contains("1 is valid: 1 zero byte.")
	assert_str(FoeHelp.tooltip(_lines("    Padding 0"), 0, 12)).contains("Out of range: 0 is not 1..65535.")
	assert_str(FoeHelp.tooltip(_lines("    Padding 65536"), 0, 12)).contains("Out of range: 65536 is not 1..65535.")
	assert_str(FoeHelp.tooltip(_lines("    Padding 2 3"), 0, 14)).contains("Padding takes 1 operand, so this word is one too many.")


func test_the_hint_for_padding_marks_the_optional_count() -> void:
	var line := "    Padding "
	var hint := FoeHelp.code_hint(line, line.length())
	assert_str(hint.split("\n")[0]).is_equal("Padding %s[count]%s" % [MARK, MARK])
	assert_str(hint.split("\n")[1]).starts_with("count (1..65535): how many zero bytes")
	assert_str(FoeHelp.code_hint("    Padding 3 ", 14)).is_empty()                         # after the count
	assert_str(FoeHelp.code_hint("    Padding", 11)).is_empty()                            # still typing the name


func test_completion_offers_padding_with_its_summary() -> void:
	var options := FoeHelp.completions(_lines("    Pad"), 0, 7)
	assert_array(_names(options)).contains_exactly(["Padding"])
	assert_int(options[0]["type"]).is_equal(FoeHelp.Candidate.MNEMONIC)
	assert_str(options[0]["insert"]).is_equal("Padding ")                                 # the count may follow
	assert_str(options[0]["summary"]).is_equal(FoeOps.summary(FoeOps.PADDING))
	assert_array(_names(FoeHelp.completions(_lines("    pa"), 0, 6))).contains_exactly(["Padding"])
	assert_array(FoeHelp.completions(_lines("    Padding"), 0, 11)).is_empty()            # complete already
	assert_array(FoeHelp.completions(_lines("    Padding 1"), 0, 13)).is_empty()          # a number
	assert_array(_names(FoeHelp.completions(_lines("    P"), 0, 5))).contains_exactly(["Play_Sound", "Put_Foe_To_Sleep", "Padding"])
	# Ctrl+Space on an empty line lists it among the instructions, after the opcodes
	var all := _names(FoeHelp.completions(_lines("    "), 0, 4, true))
	assert_str(all[-1]).is_equal("Padding")
	assert_int(all.find("If_Flag")).is_less(all.find("Padding"))


func test_every_listed_instruction_has_a_tooltip_with_its_signature() -> void:
	for opcode in FoeOps.listed():
		var tip := FoeHelp.tooltip(_lines(FoeOps.op_name(opcode)), 0, 1)
		assert_str(tip.split("\n")[0]).override_failure_message(FoeOps.op_name(opcode)).is_equal(FoeOps.signature(opcode))
		assert_str(tip.split("\n")[1]).is_equal(FoeOps.summary(opcode))


# --- FoeCodeEdit: the CodeEdit that shows them ------------------------------

func _edit(text: String, line: int, column: int) -> FoeCodeEdit:
	var edit := FoeCodeEdit.new()
	edit.size = Vector2(700, 300)
	add_child(edit)
	edit.text = text
	edit.set_caret_line(line)
	edit.set_caret_column(column)
	return edit


func test_the_code_edit_is_set_up_for_help() -> void:
	var edit := FoeCodeEdit.new()
	assert_bool(edit.code_completion_enabled).is_true()
	edit.free()


func test_the_code_edit_shows_the_hint_for_the_caret() -> void:
	var edit := _edit("    Wake_Foe \n    Move_Foe_To_XY 1 ", 0, 13)
	edit.update_hint()
	assert_str(edit.hint).is_equal(FoeHelp.code_hint("    Wake_Foe ", 13))
	assert_str(edit.hint).contains("%sfoe%s" % [MARK, MARK])
	edit.set_caret_line(1)
	edit.set_caret_column(21)
	edit.update_hint()
	assert_str(edit.hint.split("\n")[0]).is_equal("Move_Foe_To_XY x %sy%s frame" % [MARK, MARK])
	edit.set_caret_column(5)                                  # back in the name: no hint
	edit.update_hint()
	assert_str(edit.hint).is_empty()
	edit.free()


func test_the_code_edit_answers_the_tooltip_for_a_cell() -> void:
	var edit := _edit(SCRIPT, 0, 0)
	assert_str(edit.tooltip_at(1, 6)).starts_with("Move_Foe_To_XY x y frame")
	assert_str(edit.tooltip_at(1, 0)).is_empty()
	assert_str(edit.tooltip_at(-1, -1)).is_empty()
	assert_str(edit.tooltip_at(3, edit.get_line(3).find("start"))).contains("defined on line 1")
	edit.free()


func test_the_code_edit_builds_its_tooltip_from_the_mouse_position() -> void:
	var edit := _edit(SCRIPT, 0, 0)
	await get_tree().process_frame
	var cell := edit.get_pos_at_line_column(1, 6)
	if cell.x < 0:
		edit.free()
		return                                                 # no layout without a window: nothing to check
	var tip := edit._get_tooltip(Vector2(cell.x + 2, cell.y - edit.get_line_height() / 2.0))     # y is the bottom of the line
	assert_str(tip).starts_with("Move_Foe_To_XY x y frame")
	edit.free()


func test_the_code_edit_fills_the_completion_menu() -> void:
	var edit := _edit("start:\n    Wa", 1, 6)
	edit.request_code_completion()
	var options := edit.get_code_completion_options()
	assert_int(options.size()).is_equal(2)
	var shown: Array[String] = []
	for option in options:
		shown.append(option["display_text"])
	assert_array(shown.filter(func(d): return d.begins_with("Wait_Next_Tick  "))).has_size(1)
	assert_array(shown.filter(func(d): return d.begins_with("Wake_Foe  ") and d.contains(FoeOps.SUMMARY[FoeOps.Op.WAKE_FOE]))).has_size(1)
	# Taking the entry replaces what was typed and leaves the caret ready for the operand.
	for i in options.size():
		if options[i]["display_text"].begins_with("Wake_Foe"):
			edit.set_code_completion_selected_index(i)
	edit.confirm_code_completion()
	assert_str(edit.get_line(1)).is_equal("    Wake_Foe ")
	assert_int(edit.get_caret_column()).is_equal(13)
	edit.free()


func test_the_code_edit_completes_labels_and_closes_the_menu_when_nothing_fits() -> void:
	var edit := _edit("start:\nstop:\n    Jump_To st", 2, 14)
	edit.request_code_completion()
	assert_int(edit.get_code_completion_options().size()).is_equal(2)
	edit.set_caret_column(0)                                  # nothing in front of the caret: no options
	edit.set_caret_line(1)
	edit.request_code_completion()
	assert_int(edit.get_code_completion_options().size()).is_equal(0)
	edit.free()


func test_ctrl_space_forces_the_full_list() -> void:
	var edit := _edit("start:\n    ", 1, 4)
	edit.request_code_completion(true)
	assert_int(edit.get_code_completion_options().size()).is_equal(FoeOps.listed().size())      # the opcodes and Padding
	edit.free()


func test_ctrl_space_after_an_instruction_lists_the_labels_and_a_typed_space_stays_quiet() -> void:
	var edit := _edit("start:\nstop:\n    Jump_To ", 2, 12)
	edit.request_code_completion(true)
	assert_int(edit.get_code_completion_options().size()).is_equal(2)
	edit.request_code_completion()                            # what typing a space asks for
	assert_int(edit.get_code_completion_options().size()).is_equal(0)
	edit.free()


func test_typing_a_word_opens_the_menu_only_while_the_editor_has_the_focus() -> void:
	var edit := _edit("    Wa", 0, 6)
	edit.release_focus()
	edit._on_text_changed()                                   # text set by a load or a reload
	assert_int(edit.get_code_completion_options().size()).is_equal(0)
	edit.grab_focus()
	if edit.has_focus():                                      # a window with the keyboard focus is needed
		edit._on_text_changed()                               # text typed by the user
		assert_int(edit.get_code_completion_options().size()).is_equal(2)
	edit.free()


func test_the_panel_uses_the_foe_code_edit() -> void:
	var panel := FoeEditorPanel.new()
	add_child(panel)
	var path := "user://test_foe_help.foe"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("start:\n    Return\n")
	file.close()
	var doc := panel.open_script(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as FoeScript)
	assert_object(doc.edit).is_instanceof(FoeCodeEdit)
	panel.free()
	DirAccess.remove_absolute(path)


func test_ctrl_k_comments_the_selected_lines_in_and_out_in_one_undo_step() -> void:
	var edit: FoeCodeEdit = auto_free(FoeCodeEdit.new())
	edit.text = "a:\n    Return\n\n    Show_Foe\nb:"
	edit.select(1, 2, 3, 4)                  # lines 1-3 (the blank line 2 stays blank)
	edit.toggle_comment()
	assert_str(edit.text).is_equal("a:\n;    Return\n\n;    Show_Foe\nb:")
	edit.toggle_comment()                    # all touched lines are comments: uncomment
	assert_str(edit.text).is_equal("a:\n    Return\n\n    Show_Foe\nb:")
	edit.toggle_comment()
	edit.undo()                              # one step undoes the whole toggle
	assert_str(edit.text).is_equal("a:\n    Return\n\n    Show_Foe\nb:")


func test_ctrl_k_without_a_selection_toggles_the_caret_line_and_mixed_lines_get_commented() -> void:
	var edit: FoeCodeEdit = auto_free(FoeCodeEdit.new())
	edit.text = "    ; note\n    Return"
	edit.set_caret_line(1)
	edit.toggle_comment()
	assert_str(edit.text).is_equal("    ; note\n;    Return")
	edit.select(0, 0, 1, 3)                  # one comment, one already commented: uncomment both
	edit.toggle_comment()
	assert_str(edit.text).is_equal("     note\n    Return")
