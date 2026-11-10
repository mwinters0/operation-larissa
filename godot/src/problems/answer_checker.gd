class_name AnswerChecker
extends RefCounted
## Decides whether a typed answer is right, exactly as the original's `CheckAnswer` does.
##
## Teaches: data-driven rules. Which field holds the answer, how forgiving the comparison
## is and whether "fraction or decimal" matters are all stored in the ProblemType resource;
## this class only knows the four comparison primitives (DESIGN 5.2 item 7):
##   exact   equal when |a - b| < 1e-10, so 1/2 = .5 = 0.50 = 2/4
##   near    |expected - answer| <= |expected| * tolerance      (relative)
##   close   |expected - answer| <= tolerance                   (absolute)
##   range   strictly between two stored bounds (water pressure)
## plus `check_selection` for the ballast panels (a set of weights adding up to a target).
## Nothing is rounded and no units are parsed: the unit is fixed by the prompt.

## 2.2 - 2.0 is 0.20000000000000018 in floating point; without this a player who types exactly
## the edge of a tolerance (answer 2, tolerance 0.2, typed 2.2) would be marked wrong.
const BOUNDARY_SLACK := 1e-9


## The expected answer of a stored record, or null when the type has no single stored
## answer (water pressure above level 0, ballast).
## For the combination lock (type 0) it is the first answer-wheel label as printed ("13", "2/12",
## ".5", "20" for "20%").
static func expected(type: ProblemType, level: int, record: ProblemRecord) -> NumberValue:
	if type.compare_mode == "wheel":
		var label := LockProgram.from_record(type, record, 0).answer_label
		return NumberValue.parse(label.trim_suffix("%"))
	var field := type.answer_fields[level]
	if field < 0:
		return null
	return record.number_at(field)


## Is `answer` (a typed number) correct for this problem?
static func check(type: ProblemType, level: int, record: ProblemRecord, answer: NumberValue) -> bool:
	if answer == null:
		return false
	if type.compare_mode == "range" and level > 0:
		var fields: PackedInt32Array = type.extras["range_fields"]
		var low := record.value_at(fields[0])
		var high := record.value_at(fields[1])
		var typed := answer.to_double()
		return typed > low and typed < high
	var want := expected(type, level, record)
	if want == null:
		return false
	# Some types insist on the KIND: "type it as a fraction" / "give a percent, not a fraction".
	if level in type.kind_checked_levels and answer.kind != want.kind:
		return false
	var tolerance := type.tolerances[level] if level < type.tolerances.size() else 0.0
	var a := answer.to_double()
	var b := want.to_double()
	if tolerance > 0.0:
		match type.compare_mode:
			"near":
				return absf(b - a) <= absf(b) * tolerance + BOUNDARY_SLACK
			"close":
				return absf(b - a) <= tolerance + BOUNDARY_SLACK
	return absf(a - b) < NumberValue.EQUAL_EPSILON


## Ballast panels (types 28 and 29): `selected_mask` has bit i set when denomination i is
## chosen. Right if the chosen weights add up to the target (field f0), whichever ones.
static func check_selection(type: ProblemType, level: int, record: ProblemRecord, selected_mask: int) -> bool:
	return selection_sum(type, level, selected_mask) == record.int_at(0)


## Sum of the denominations chosen in `selected_mask` for this level's display mode.
static func selection_sum(type: ProblemType, level: int, selected_mask: int) -> int:
	var values := denominations(type, level)
	var total := 0
	for i in values.size():
		if selected_mask & (1 << i):
			total += values[i]
	return total


## The 10 weights offered on the ballast panel at `level`.
static func denominations(type: ProblemType, level: int) -> PackedInt32Array:
	var mode: int = type.extras["mode_by_level"][level]
	return type.extras["values"][str(mode)]


## The label printed on each of the 10 ballast weights (".25", "128" ...).
static func denomination_labels(type: ProblemType, level: int) -> PackedStringArray:
	var mode: int = type.extras["mode_by_level"][level]
	return type.extras["labels"][str(mode)]

