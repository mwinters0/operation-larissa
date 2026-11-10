class_name LockProgram
extends RefCounted
## The little "program" of one combination-lock number (problem type 0).
##
## Teaches: decoding a tiny bytecode into something readable. A lock record holds TWO
## programs (one per combination number), each a list of (operand wheel slot, operator)
## pairs ending with the operator "=" (code 0), followed by the slot of the ANSWER wheel
## where the player must stop. Operators: 1 +, 2 -, 3 x, 4 /; they are applied left to right.
##
## Record layout (DESIGN 3.7 / 5.4): f0 = wheel set (which label tables), stage 1 program =
## f1..f9, stage 2 program = f12..f20. The wheel UI is `CombinationLock`; this class is the logic
## that the wheel and the problem texts share.

## Where each stage's program starts and how many bytes it has.
const STAGE_FIRST_FIELD: Array[int] = [1, 12]
const PROGRAM_BYTES := 9
const OPERATORS: Array[String] = ["=", "+", "-", "x", "/"]

## Labels of the operands in the order they are used ("7", "9", "5"), the operators between
## them ("+", "-"), the final label of the answer wheel and the value it stands for.
var operands: PackedStringArray = PackedStringArray()
## The slot (0-7) of each operand on the operand wheel (labels may repeat, slots do not).
var operand_slots: PackedInt32Array = PackedInt32Array()
var operand_values: PackedFloat64Array = PackedFloat64Array()
var operators: PackedStringArray = PackedStringArray()
var answer_label: String = ""
var answer_value: float = 0.0
var answer_slot: int = 0


## Decodes stage 0 or 1 of a type-0 record.
static func from_record(type: ProblemType, record: ProblemRecord, stage: int) -> LockProgram:
	var program := LockProgram.new()
	var wheel_set := str(record.int_at(0))
	var operand_table: PackedStringArray = type.extras["operand_labels"][wheel_set]
	var answer_table: PackedStringArray = type.extras["answer_labels"][wheel_set]
	var at: int = STAGE_FIRST_FIELD[stage]
	var end := at + PROGRAM_BYTES
	var running := 0.0
	var pending_operator := 0
	while at + 1 < end:
		var slot := record.int_at(at)
		var op_code := record.int_at(at + 1)
		at += 2
		var label := operand_table[slot].strip_edges()
		var value := label_to_value(label)
		program.operands.append(label)
		program.operand_slots.append(slot)
		program.operand_values.append(value)
		if program.operands.size() == 1:
			running = value
		else:
			running = apply_operator(pending_operator, running, value)
		if op_code == 0:
			break
		program.operators.append(OPERATORS[op_code])
		pending_operator = op_code
	program.answer_slot = record.int_at(at)
	program.answer_label = answer_table[program.answer_slot].strip_edges()
	program.answer_value = label_to_value(program.answer_label)
	return program


## What the player must end up with, computed from the operands (not read from the label).
func evaluate() -> float:
	var running := operand_values[0]
	for i in operators.size():
		var code := OPERATORS.find(operators[i])
		running = apply_operator(code, running, operand_values[i + 1])
	return running


## "7 + 9 - 5"
func expression() -> String:
	var text := operands[0]
	for i in operators.size():
		text += " %s %s" % [operators[i], operands[i + 1]]
	return text


## A wheel label as a number: "2", "0.10", "1/12", "20%".
static func label_to_value(label: String) -> float:
	var s := label.strip_edges()
	if s.ends_with("%"):
		return s.trim_suffix("%").to_float() / 100.0
	if "/" in s:
		var parts := s.split("/")
		return parts[0].to_float() / parts[1].to_float()
	return s.to_float()


## One step of the program: `left <op> right`.
static func apply_operator(op_code: int, left: float, right: float) -> float:
	match op_code:
		1: return left + right
		2: return left - right
		3: return left * right
		_: return left / right
