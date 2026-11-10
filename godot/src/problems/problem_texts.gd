class_name ProblemTexts
extends RefCounted
## Which text of a problem type is shown for a stored record, and what fills its `{k}` slots.
##
## Teaches: a rule table written as plain code. In the original, one small function per type
## ("PromptSubst", "HintSubst", "SolutionSubst") picks the text index from the record and the
## educational level and fills the variable slots with numbers or strings. DESIGN 5.4 and
## docs/data/problem_fields.json describe all 34; here they are 34 short `_type_NN` functions
## that fill a `Wording`. `ProblemInstance` then renders the wording with `TextTemplate`.
##
## Vocabulary: `L` is the educational level (0-3), `r` the stored record, `f(i)` its i-th field.
## `num(i)` prints a field the way the original does (decimals keep their digits, fractions are
## "1 3/4"), `int_at(i)` prints it as a whole number.
##
## Two conventions of the original that matter here:
##   * Texts that do not exist for a level are "" (see ProblemType.texts); the instance then
##     falls back to the plain answer.
##   * The hint inherits the prompt's slots, the solution inherits the prompt's slots too.
##
## The words of one problem.
class Wording:
	extends RefCounted
	var prompt_index: int = 0
	var hint_index: int = -1
	var solution_index: int = -1
	var success_index: int = -1
	var prompt_slots: Dictionary = {}
	var hint_slots: Dictionary = {}
	var solution_slots: Dictionary = {}
	## Replaces the solution when the original has no template for it or builds it with code.
	var solution_text: String = ""
	## [from, to]: a word to swap in the finished solution (see type 9).
	var solution_swap: PackedStringArray = PackedStringArray()

	func _init(prompt: int = 0, hint: int = -1, solution: int = -1, success: int = -1) -> void:
		prompt_index = prompt
		hint_index = hint
		solution_index = solution
		success_index = success


## Builds the wording of record `r` of `type` at educational level `level`.
## `pie_rotation` (0 or 1) is the random order of the foods in the pie chart's legend (type 17).
static func describe(type: ProblemType, level: int, r: ProblemRecord, pie_rotation: int = 0) -> Wording:
	var w: Wording
	match type.id:
		0: w = _type_00(type, level, r)
		1: w = _type_01(level, r)
		2: w = _type_02(r)
		3: w = _type_03(level, r)
		4: w = _type_04(r)
		5: w = _type_05(level, r)
		6: w = _type_06(r)
		7: w = _type_07(level, r)
		8: w = _type_08(r)
		9: w = _type_09(level, r)
		10: w = _type_10(r)
		11: w = _type_11(r)
		12: w = _type_12(r)
		13: w = _type_13(r)
		14: w = _type_14(level, r)
		15: w = _type_15(r)
		16: w = _type_16(level, r)
		17: w = _type_17(type, level, r, pie_rotation)
		18: w = _type_18(r)
		19: w = _type_19(level, r)
		20: w = _type_20(level, r)
		21: w = _type_21(level, r)
		22: w = _type_22(level, r)
		23: w = _type_23(r)
		24: w = _type_24(level, r)
		25: w = _type_25(level, r)
		26: w = _type_26(level, r)
		27: w = _type_27(level, r)
		28, 29: w = _type_ballast(type, level, r)
		30: w = _type_30(level, r)
		31: w = _type_31(r)
		32, 33: w = _type_32(r)
		_:
			if type.id >= Catalog.PROBLEM_TYPE_COUNT:
				w = _added(r)
			else:
				push_error("ProblemTexts: unknown type %d" % type.id)
				w = Wording.new()
	return w


## A problem type a pack adds (a number from `Catalog.PROBLEM_TYPE_COUNT` on) is worded by its data alone: text 0 of the type is the prompt, 1 the hint, 2 the worked solution and 3 the success text (an empty
## text is none), and the slot `{k}` of any of them is field k of the record, printed the way the original prints a field (`num`). The ones the original has are worded by the functions below.
static func _added(r: ProblemRecord) -> Wording:
	var w := Wording.new(0, 1, 2, 3)
	for i in r.kinds.length():
		w.prompt_slots[i] = _num(r, i)
	return w


# --- small helpers ------------------------------------------------------------

static func _num(r: ProblemRecord, i: int) -> String:
	return r.number_at(i).to_text()


static func _int(r: ProblemRecord, i: int) -> String:
	return str(r.int_at(i))


## The rows of the food pie chart's legend, by the colour of their box (the prompt of type 17 asks about a row by colour). The picture of
## the chart (`PieDiagram`) has the same constants, taken from here: the rules own the question, the view only draws the rows.
const PIE_GREEN := 0
const PIE_PURPLE := 1
const PIE_ORANGE := 2


## The words the wordings of the types fill in (ONWIN32 strings), as `text` names, in the order of the record's number.
const LENGTH_UNITS: Array[StringName] = [&"length_inches", &"length_yards", &"length_feet", &"length_kilometers",
		&"length_fathoms", &"length_miles"]
const PERIODS: Array[StringName] = [&"period_hour", &"period_day", &"period_week"]
const TIME_UNITS: Array[StringName] = [&"time_minutes", &"time_hours", &"time_seconds"]
const PERIODS_WITH_ARTICLE: Array[StringName] = [&"period_an_hour", &"period_a_day", &"period_a_week"]


## A string of the original's string table by name (ONWIN32: "inches", "hour", "port" ...).
static func _ui(text_name: StringName) -> String:
	return Catalog.text(text_name)


static func _b(condition: bool) -> int:
	return 1 if condition else 0


# --- the 34 types -------------------------------------------------------------

## Combination lock. Prompt, hint and success are templates; the worked solution depends on the stage (see `lock_solution`).
static func _type_00(type: ProblemType, _level: int, r: ProblemRecord) -> Wording:
	var w := Wording.new(0, 1, -1, 3)
	w.solution_text = lock_solution(type, r, 0)
	return w


## The worked solution of one of the lock's two combination numbers (`stage` 0 or 1), shown after a miss, as
## `LockShowSolution` (0x4223db) prints it: text f0 + 4 of the type's bundle, so the record's first byte (the label
## set, 0-11) picks one of 12 forms. With the program bytes `p` (operand slot, operator, operand slot, ..., then the
## "=" and the answer slot) and the intermediate results f10 / f11 (stage 1) or f21 / f22 (stage 2) it fills
##   f0 0, 1, 2   "({0} {1} {2}) {3} {4}\n= {5} {3} {4}\n= {6}"       {5} = f10
##   f0 3         "{0} {1} {2}\n= " and an underlined blank ("[u]  [/u]") (the template has no slot for the answer)
##   f0 4, 5, 8   "({0} {1} {2}) {3} {4} {5} {6}\n= ({7} {3} {4}) {5} {6}\n= {8} {5} {6}\n= {9}"   {7} = f10, {8} = f11
##   f0 6, 7, 11  "{0} {1} {2}\n= {3}\n= {4}" with {3} the answer slot's own table: "n/10" (6), "0.n" (7), "0.n0" (11)
##   f0 9, 10     the same with {3} = f10
## The labels are the strings `DoCombinationLock` loads ("0.5", "0.50"), as the type's tables hold them.
static func lock_solution(type: ProblemType, r: ProblemRecord, stage: int) -> String:
	var form := r.int_at(0)
	var set_key := str(form)
	var operands: PackedStringArray = type.extras["operand_labels"][set_key]
	var answers: PackedStringArray = type.extras["answer_labels"][set_key]
	var first_byte: int = LockProgram.STAGE_FIRST_FIELD[stage]
	var p := PackedInt32Array()
	for i in LockProgram.PROGRAM_BYTES:
		p.append(r.int_at(first_byte + i))
	var intermediate: int = 10 if stage == 0 else 21          # f10 / f11, or f21 / f22
	var slots := {0: operands[p[0]], 1: LockProgram.OPERATORS[p[1]], 2: operands[p[2]]}
	match form:
		0, 1, 2:
			slots[3] = LockProgram.OPERATORS[p[3]]
			slots[4] = operands[p[4]]
			slots[5] = _num(r, intermediate)
			slots[6] = answers[p[6]]
		3:
			pass
		4, 5, 8:
			slots[3] = LockProgram.OPERATORS[p[3]]
			slots[4] = operands[p[4]]
			slots[5] = LockProgram.OPERATORS[p[5]]
			slots[6] = operands[p[6]]
			slots[7] = _num(r, intermediate)
			slots[8] = _num(r, intermediate + 1)
			slots[9] = answers[p[8]]
		6:
			slots[3] = "%d/10" % (p[4] + 2)
			slots[4] = answers[p[4]]
		7:
			slots[3] = "0.%d" % (p[4] + 2)
			slots[4] = answers[p[4]]
		9, 10:
			slots[3] = _num(r, intermediate)
			slots[4] = answers[p[4]]
		11:
			# Deliberate deviation: for the answer slot 7 (90 %) the original's {3} buffer holds string 11245 ("1.9"), a wrong
			# "= 1.9" (`LockSolutionForm11Slot7` (0x442238)); the port shows "0.90", the pattern of the other slots.
			slots[3] = "0.%d0" % (p[4] + 2)
			slots[4] = answers[p[4]]
	# Form 3's text ends in a raw 0xFF: `ConvertTextMarkup` (0x415ebf) turns it into the underline toggle (FF 02 FF), so the two
	# spaces after it are drawn underlined, a short blank after "=" (the template has no slot for the answer).
	# `TextTemplate.render` writes that stretch as `[u]  [/u]`.
	var template := type.text_at(4 + form)
	return TextTemplate.render(template, slots)


static func _type_01(level: int, r: ProblemRecord) -> Wording:
	var pattern := r.int_at(4)
	var w := Wording.new(0)
	w.hint_index = (pattern + 6) if level == 0 else (mini(pattern, 4) + 1)
	w.solution_index = mini(pattern, 4) + 9
	w.success_index = -1                                   # the sector's log entry (set by the caller)
	var grow := 1 if pattern == 4 else 2                  # how fast the added number grows
	w.hint_slots = {0: _num(r, 0), 1: _num(r, 1), 2: _num(r, 2), 3: _num(r, 3),
			4: _int(r, 5)}
	if pattern >= 4:
		w.hint_slots[5] = str(r.int_at(5) + grow)
		w.hint_slots[6] = str(r.int_at(5) + 2 * grow)
	w.solution_slots = {0: _num(r, 0), 1: _num(r, 1), 2: _num(r, 2), 3: _num(r, 3), 4: _num(r, 6),
			5: _int(r, 5) if pattern >= 4 else _num(r, 5)}
	w.solution_slots[6] = str(r.int_at(5) + grow)
	w.solution_slots[7] = str(r.int_at(5) + 2 * grow)
	w.solution_slots[8] = str(r.int_at(5) + 3 * grow)
	return w


static func _type_02(r: ProblemRecord) -> Wording:
	var w := Wording.new(0, 1, 2, 3)
	for i in 7:
		w.solution_slots[i] = _int(r, i)
	w.solution_slots[7] = _num(r, 7)
	return w


static func _type_03(level: int, r: ProblemRecord) -> Wording:
	var w := Wording.new(0, level + 1, level + 5, 9)
	w.prompt_slots = {0: _int(r, 0), 1: _int(r, 1), 2: _ui(&"lesson_hours") if level == 0 else _ui(&"lesson_minutes")}
	w.solution_slots = {0: _int(r, 0), 1: _int(r, 1), 2: _num(r, 2), 3: _num(r, 3)}
	return w


static func _type_04(r: ProblemRecord) -> Wording:
	var w := Wording.new(0, 1, 2, 3)
	w.prompt_slots = {0: _int(r, 0)}
	w.solution_slots = {0: _int(r, 0), 1: _int(r, 1)}
	return w


static func _type_05(level: int, r: ProblemRecord) -> Wording:
	var more := _b(level != 0)
	var w := Wording.new(more, more + 2, more + 4, 6)
	w.prompt_slots = {0: _num(r, 0), 1: _num(r, 1)}
	w.solution_slots = {0: _num(r, 0), 1: _num(r, 1), 4: _num(r, 2), 5: _num(r, 3)}
	return w


static func _type_06(r: ProblemRecord) -> Wording:
	var w := Wording.new(0, 1, 2, 3)
	w.solution_slots = {0: _num(r, 0), 1: _num(r, 1), 2: _num(r, 2)}
	return w


static func _type_07(level: int, r: ProblemRecord) -> Wording:
	var prompt := 0
	match level:
		1, 3:
			prompt = 2
		2:
			prompt = 1
	var w := Wording.new(prompt, prompt + 3, prompt + 6, 9 + _b(level == 1 or level == 3))
	w.solution_slots = {0: _num(r, 5), 1: _num(r, 6)}
	return w


static func _type_08(r: ProblemRecord) -> Wording:
	var kind := r.int_at(0)
	var w := Wording.new(0, kind + 1, kind + 6, 11)
	w.prompt_slots = {0: _ui(LENGTH_UNITS[kind])}
	w.solution_slots = {0: _num(r, 1), 1: _num(r, 2)}
	return w


static func _type_09(level: int, r: ProblemRecord) -> Wording:
	var latitude := r.int_at(0) == 1
	var word := _ui(&"latitude") if latitude else _ui(&"longitude")
	var w := Wording.new(0, 1, 2, 3)
	w.prompt_slots = {0: "" if level == 0 else _ui(&"approximate_prefix"), 1: word}
	w.solution_slots = {0: _ui(&"distance_letter") if level == 0 else _ui(&"distance_letter_approximate"), 1: word,
			2: _num(r, 4 if latitude else 3), 3: _num(r, 2 if latitude else 1), 4: _num(r, 5)}
	# The stored solution text always says "longitude"; for a latitude question say so.
	if latitude:
		w.solution_swap = PackedStringArray(["longitude", "latitude"])
	return w


static func _type_10(r: ProblemRecord) -> Wording:
	var w := Wording.new(0, 1, 2, 3)
	w.solution_slots = {0: _num(r, 0), 1: _num(r, 1), 2: _num(r, 3), 3: _num(r, 2), 4: _num(r, 4)}
	return w


static func _type_11(r: ProblemRecord) -> Wording:
	var period := r.int_at(1)
	var unit := r.int_at(2)
	var solution := 5
	if period == 0:
		solution = 2 if unit == 0 else 4
	elif period == 1:
		solution = 3
	var w := Wording.new(0, 1, solution, 6)
	w.prompt_slots = {0: _int(r, 0), 1: _ui(PERIODS[period]), 2: _ui(TIME_UNITS[unit])}
	w.hint_slots = {3: _ui(PERIODS_WITH_ARTICLE[period])}
	w.solution_slots = {0: _int(r, 0), 1: _int(r, 3)}
	return w


static func _type_12(r: ProblemRecord) -> Wording:
	var decrease := r.int_at(2) < r.int_at(0)
	var prompt := _b(decrease)
	var w := Wording.new(prompt, prompt + 2, prompt + 4, 6)
	w.prompt_slots = {0: _int(r, 1)}
	w.solution_slots = {0: _int(r, 0), 1: _int(r, 1), 2: _int(r, 2)}
	# The original has no worked-solution text for this type; compose one.
	w.solution_text = "New temperature (in °F):\n%d %s %d = %d" % [r.int_at(0), "-" if decrease else "+", r.int_at(1), r.int_at(2)]
	return w


static func _type_13(r: ProblemRecord) -> Wording:
	var direction := r.int_at(2)
	var w := Wording.new(direction, direction + 2, direction + 4, 6)
	w.solution_slots = {0: _num(r, 0), 1: _num(r, 1)}
	return w


static func _type_14(level: int, r: ProblemRecord) -> Wording:
	var prompt := _b(level != 1)
	var w := Wording.new(prompt, prompt + 2, prompt + 4, 6)
	w.solution_slots = {0: _int(r, 1), 1: _int(r, 0), 2: _num(r, 2), 3: _num(r, 3)}
	return w


static func _type_15(r: ProblemRecord) -> Wording:
	var place := r.int_at(1)
	var w := Wording.new(place - 1, place + 4, place + 9, 15)
	w.solution_slots = {0: _num(r, 0), 1: _num(r, 2)}
	return w


static func _type_16(level: int, r: ProblemRecord) -> Wording:
	var more := _b(level > 1)
	var w := Wording.new(0, more + 1, more + 3, 5)
	w.solution_slots = {0: _int(r, 0), 3: _num(r, 6), 4: _num(r, 8), 5: _int(r, 1), 8: _num(r, 7),
			9: _num(r, 9), 10: _num(r, 10)}
	return w


## The food pie chart. The slices are fixed pictures; the legend names the foods in one of two rotations
## (drawn by `PieDiagram`), so the foods the question names depend on `rotation`: f0 = 0 asks about the purple slice,
## 1 about the orange one, 2 about the purple one; the second food (level 3) is always the green slice.
static func _type_17(type: ProblemType, level: int, r: ProblemRecord, rotation: int) -> Wording:
	var percent := not r.is_fraction_at(1)
	var prompt := _b(percent) + (2 if level == 3 else 0)
	var w := Wording.new(prompt, prompt + 4, prompt + 8, 12)
	var asked_row: int = [PIE_PURPLE, PIE_ORANGE, PIE_PURPLE][r.int_at(0)]
	w.prompt_slots = {0: type.text_at(13 + (rotation + asked_row) % 3), 1: type.text_at(13 + (rotation + PIE_GREEN) % 3)}
	w.hint_slots = {2: _simple_fraction(r.value_at(1) / (100.0 if percent else 1.0))}
	w.solution_slots = {2: _num(r, 1)}
	return w


static func _type_18(r: ProblemRecord) -> Wording:
	var w := Wording.new(0, 1, 2, 3)
	w.solution_slots = {0: _num(r, 2), 1: _int(r, 1), 2: _num(r, 3)}
	return w


static func _type_19(level: int, r: ProblemRecord) -> Wording:
	var ruler := r.int_at(0)
	var index := 0
	match level:
		0:
			index = 0 if ruler == 0 else 1
		1:
			index = 2
		2:
			index = 3 if ruler == 3 else 4
		_:
			index = 5 if ruler == 3 else 6
	# The solution texts 9-15 are not simply "prompt + 9": the original keys them by what is
	# measured, so look at the unit of the prompt (inches, cm, mm, cm with tenths, quarter inches).
	var solution_for: Array[int] = [9, 10, 11, 10, 15, 12, 13]
	var w := Wording.new(index, index, solution_for[index], 16)
	w.prompt_slots = {0: "inch"}
	var units: Array[String] = ["inch", "quarter inch", "centimeter", "millimeter"]
	w.prompt_slots[0] = units[ruler]
	w.solution_slots = {0: _num(r, 1), 1: _num(r, 2), 5: _num(r, 6)}
	return w


static func _type_20(level: int, r: ProblemRecord) -> Wording:
	var prompt := _b(r.int_at(1) < r.int_at(0)) * 2 + _b(level != 0)
	var w := Wording.new(prompt, prompt + 4, prompt + 8, 12)
	w.solution_slots = {0: _int(r, 0), 1: _int(r, 1), 2: _int(r, 2), 3: _num(r, 3), 4: _num(r, 4)}
	# Field order in the data is (today, yesterday): the question says "increased" when f1 < f0.
	return w


static func _type_21(level: int, r: ProblemRecord) -> Wording:
	var gallons_given := r.int_at(2) != 0
	var prompt := 0
	match level:
		0:
			prompt = 0 if gallons_given else 1
		1:
			prompt = 2 if gallons_given else 3
		2:
			prompt = 4
		_:
			prompt = 5
	var w := Wording.new(prompt, prompt + 6, prompt + 12, 18)
	for i in 7:
		w.solution_slots[i] = _int(r, i)
	return w


static func _type_22(level: int, r: ProblemRecord) -> Wording:
	var side := r.int_at(2)
	# The original has no worked solution at level 1 (its slots 6 and 7 are empty); reuse the
	# "New heading" lines the other levels use.
	var solution := 8 + side if level == 1 else level * 2 + side + 4
	var w := Wording.new(side, level * 2 + side, solution, 10)
	w.prompt_slots = {0: _int(r, 0), 2: _int(r, 1)}
	w.solution_slots = {1: _int(r, 3)}
	return w


static func _type_23(r: ProblemRecord) -> Wording:
	var side := r.int_at(2)
	var w := Wording.new(side, side + 2, 4, 5)
	w.prompt_slots = {0: _int(r, 0), 1: _int(r, 1)}
	w.solution_slots = {0: _ui(&"side_starboard") if side == 0 else _ui(&"side_port"), 1: _int(r, 1), 2: _int(r, 0), 3: _num(r, 4)}
	return w


static func _type_24(level: int, r: ProblemRecord) -> Wording:
	var prompt := _b(level == 3 and r.int_at(0) != 0)
	var present := r.int_at(3)
	var w := Wording.new(prompt, prompt + 2, prompt + 4, 6)
	w.prompt_slots = {0: _num(r, 2), 1: "%04d" % present, 2: _int(r, 0), 3: _int(r, 1), 5: ""}
	w.solution_slots = {0: _num(r, 2), 1: "%04d" % present, 2: "%04d" % r.int_at(4),
			3: _int(r, 0), 4: _int(r, 1), 5: "", 6: ""}
	return w


static func _type_25(level: int, r: ProblemRecord) -> Wording:
	var prompt := r.int_at(9) + _b(level != 0) * 2
	var w := Wording.new(prompt, prompt + 3, prompt + 6, 9)
	w.solution_slots = {0: _int(r, 7), 1: _int(r, 8)}
	return w


static func _type_26(level: int, r: ProblemRecord) -> Wording:
	var percent := _b(level == 2)
	var w := Wording.new(percent, percent + 2, percent + 4, 6)
	w.prompt_slots = {0: _num(r, 1)}
	w.solution_slots = {0: _int(r, 0), 1: _num(r, 1), 2: _int(r, 2), 3: _int(r, 3)}
	return w


static func _type_27(level: int, r: ProblemRecord) -> Wording:
	var prompt := _b(level == 3 and r.is_fraction_at(1)) + _b(level > 1)
	var w := Wording.new(prompt, prompt + 3, prompt + 6, 9)
	w.prompt_slots = {0: _num(r, 1)}
	w.solution_slots = {0: _int(r, 0), 1: _num(r, 1), 3: _int(r, 3), 4: _int(r, 4)}
	return w


## Ballast increase (28) and decrease (29). The player picks weights on a panel instead of
## typing a number; the solution lists one valid selection (the stored bitmask).
static func _type_ballast(type: ProblemType, level: int, r: ProblemRecord) -> Wording:
	var target := r.int_at(0)
	var money_display := level == 2                          # decimals: "0.16" instead of "16" (NumberToString adds the leading 0)
	var shown := "%.2f" % (target / 100.0) if money_display else str(target)
	var w := Wording.new(0, 1 if level == 0 else 2, 3, 4)
	w.prompt_slots = {0: shown}
	w.hint_slots = {0: str(target), 1: shown}
	w.solution_slots = ballast_solution_slots(AnswerChecker.denomination_labels(type, level), r.int_at(1), shown)
	return w


## The slots {1} .. {11} of the ballast worked solution, as `Prob28_SolutionSubst` (0x41937f) fills them: {1} is "= " and
## the amount; slots {2} .. {11} take the weights from bit 9 DOWN to bit 0 (largest first), each as "+ " and its label;
## the first weight that is there loses its "+" (it becomes a space, so the line starts with two spaces) and every
## weight ends with a space. A weight that is not in the mask leaves its slot empty.
static func ballast_solution_slots(labels: PackedStringArray, mask: int, shown: String) -> Dictionary:
	var slots := {1: "= %s" % shown}
	var first := true
	for i in range(labels.size() - 1, -1, -1):
		var slot := 2 + (labels.size() - 1 - i)
		if not mask & (1 << i):
			slots[slot] = ""
			continue
		slots[slot] = ("  " if first else "+ ") + labels[i] + " "
		first = false
	return slots


static func _type_30(level: int, r: ProblemRecord) -> Wording:
	var extras := r.int_at(10)
	var step := (0 if level == 0 else level - 1) + extras
	var w := Wording.new(_b(level == 2), step + 2, step + 6, 10)
	w.solution_slots = {0: _int(r, 0), 1: _int(r, 1), 2: _int(r, 2), 3: _int(r, 3), 8: _int(r, 8), 9: _int(r, 9)}
	return w


static func _type_31(r: ProblemRecord) -> Wording:
	var variant := r.int_at(9)
	var w := Wording.new(variant, variant + 10, variant + 20, 30)
	w.solution_slots = {0: _int(r, 0), 1: _int(r, 2), 2: _int(r, 1), 3: _int(r, 3), 4: _int(r, 5),
			5: _int(r, 4), 6: _int(r, 6), 7: _int(r, 7), 8: _int(r, 8)}
	return w


## Search grid, fraction or decimal of the grid (types 32 and 33 share everything).
static func _type_32(r: ProblemRecord) -> Wording:
	var fraction_form := r.is_fraction_at(3)
	var prompt := _b(fraction_form)
	var unreduced := r.is_fraction_at(2) and _num(r, 2) != _num(r, 3)
	var w := Wording.new(prompt, prompt + 2, 6 if (fraction_form and unreduced) else prompt + 4, 7)
	w.solution_slots = {0: _int(r, 0), 1: _int(r, 1), 2: _num(r, 2), 3: _num(r, 3)}
	return w


## The simplest fraction a/b (b <= 12) near `value`, as text: 0.333 -> "1/3".
static func _simple_fraction(value: float) -> String:
	var best_a := 0
	var best_b := 1
	var best_error := INF
	for b in range(1, 13):
		var a := roundi(value * b)
		var error := absf(value - float(a) / b)
		if a > 0 and error < best_error - 1e-9:
			best_a = a
			best_b = b
			best_error = error
	return "%d/%d" % [best_a, best_b]
