class_name ProblemInstance
extends RefCounted
## One concrete math problem: a stored record of a ProblemType, worded for a level.
##
## Teaches: a plain object that bundles everything the problem screen needs (texts, the
## expected answer, the rules to check a typed answer) so the screen itself stays dumb.
## It is built by `ProblemFactory.make`.

## What the player gives: a typed number, or (ballast panels) a selection of weights.
enum InputKind { NUMBER, DENOMINATIONS }

var type: ProblemType
var level: int = 0
var record: ProblemRecord
## Which stored record of the level was picked (0 .. N-1), for tests and debugging.
var record_index: int = 0
## The trigger slot of the map trigger that asked for this problem (`DoMathProblem(slot)` (0x423629)); -1 when the type was
## chosen directly (Math Practice, the debug menu). The prompt shows the sender picture only for a slot (`PromptSender`).
var trigger_slot: int = -1

var title: String = ""
var prompt: String = ""
var hint: String = ""
var solution: String = ""
var success: String = ""
## The data canister's newest log entry (its number - 1 in the campaign's log, 0-14 in the originals) whose text is `success`; -1 for every other problem. When the problem is
## over the log screen opens on it and reads it aloud (`LogScreen`).
var log_index: int = -1
## The sector whose log the canister opens (it decides which entries the log screen lists); -1 for every other problem.
var log_sector: int = -1
## Type 17 only: which food the legend names first, 0 or 1 (random in the original, see `PieDiagram`).
var pie_rotation: int = 0
var input_kind: InputKind = InputKind.NUMBER
## The stored answer (null for the water-pressure range and for ballast).
var expected: NumberValue


## Creates the instance for record number `index` of `level`.
static func build(problem_type: ProblemType, problem_level: int, index: int, rotation: int = 0) -> ProblemInstance:
	var instance := ProblemInstance.new()
	instance.type = problem_type
	instance.level = problem_level
	instance.record_index = index
	instance.pie_rotation = rotation
	instance.record = problem_type.record(problem_level, index)
	instance.title = problem_type.title
	instance.expected = AnswerChecker.expected(problem_type, problem_level, instance.record)
	if problem_type.compare_mode == "sum":
		instance.input_kind = InputKind.DENOMINATIONS
	instance._word()
	return instance


## Fills prompt, hint, solution and success from the wording rules.
func _word() -> void:
	var w := ProblemTexts.describe(type, level, record, pie_rotation)
	prompt = TextTemplate.render(type.text_at(w.prompt_index), w.prompt_slots)
	# Hint and solution may use the prompt's slots too.
	var hint_slots := w.prompt_slots.duplicate()
	hint_slots.merge(w.hint_slots, true)
	hint = TextTemplate.render(type.text_at(w.hint_index), hint_slots)
	if hint.is_empty():
		hint = prompt
	if not w.solution_text.is_empty():
		solution = w.solution_text
	else:
		var solution_slots := w.prompt_slots.duplicate()
		solution_slots.merge(w.solution_slots, true)
		solution = TextTemplate.render(type.text_at(w.solution_index), solution_slots)
		if w.solution_swap.size() == 2:
			solution = solution.replace(w.solution_swap[0], w.solution_swap[1])
	if solution.is_empty():
		solution = "The correct answer is %s." % answer_text()
	if w.success_index >= 0:
		success = TextTemplate.render(type.text_at(w.success_index), {})


## Is this answer right? `answer` is a NumberValue (NUMBER input) or the selection bitmask
## as an int (DENOMINATIONS input).
func check(answer: Variant) -> bool:
	if input_kind == InputKind.DENOMINATIONS:
		return AnswerChecker.check_selection(type, level, record, int(answer))
	return AnswerChecker.check(type, level, record, answer as NumberValue)


## The correct answer in words, for messages and tests.
func answer_text() -> String:
	if input_kind == InputKind.DENOMINATIONS:
		return "any weights that add up to %d" % record.int_at(0)
	if expected == null:
		var fields: PackedInt32Array = type.extras.get("range_fields", PackedInt32Array())
		return "a value between %s and %s" % [record.number_at(fields[0]).to_text(), record.number_at(fields[1]).to_text()]
	return expected.to_text()
