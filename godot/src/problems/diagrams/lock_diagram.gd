class_name LockDiagram
extends DiagramBase
## Type 0, Combination Lock: the lock's face with its two wheels and their labels, turning.
##
## Teaches: drawing text on a circle by table, and animating by REBUILDING a list of items: each
## label has a fixed centre for each of the 4 quarter-turn phases, so a wheel position (0-31) is
## just "which spot, which phase". `CombinationLock` changes the positions; this class redraws.
##
## A wheel position counts quarter labels (4 per label, 32 per revolution). Position `p` puts the
## wheel picture `first_pic + p % 4` on screen and label `s` at the spot `(s + p / 4) % 8` of the
## phase `p % 4` (the spots are numbered clockwise from the arrow at the top). At rest (position 0)
## label `s` sits at spot `s`, as the resting diagram draws it.

## The two black boxes of the lock's face, measured from the picture (window pixels): the small one in the
## middle shows the operator that goes with the next number, the long one at the bottom the sum so far.
const OPERATOR_BOX := Rect2(158, 172, 32, 21)
const EXPRESSION_BOX := Rect2(70, 292, 210, 16)

## Where the wheels stand (0-31). Change them with `set_wheels`.
var operand_position: int = 0
var answer_position: int = 0
## What the two boxes show.
var operator_text: String = ""
var expression_text: String = ""
## True from the moment the operand wheel has stopped on a number until it moves again (or the answer wheel takes over): the dark window over
## the top of the wheel with the chosen label on it (`LockSpinOperandWheel` (0x421c6c) draws it after the spin; the next
## `LockDrawOperandWheel` (0x421a81) paints over it, as `LockRunStage` (0x421dc9) does before the answer wheel starts).
var operand_window_shown: bool = false


func _build() -> void:
	add_picture(spec["face"]["pic"], vector(spec["face"]["pos"]))
	add_picture(int(spec["answer_wheel"]["first_pic"]) + answer_position % 4, vector(spec["answer_wheel"]["pos"]))
	add_picture(int(spec["operand_wheel"]["first_pic"]) + operand_position % 4, vector(spec["operand_wheel"]["pos"]))
	var wheel_set := str(record.int_at(0))
	var operand_labels: PackedStringArray = type.extras["operand_labels"][wheel_set]
	_add_labels("operand", operand_labels, operand_position)
	_add_labels("answer", type.extras["answer_labels"][wheel_set], answer_position)
	if operand_window_shown and spec["operand_wheel"].has("window"):
		var window: Dictionary = spec["operand_wheel"]["window"]
		add_picture(int(window["pic"]), vector(window["pos"]))        # (it covers what of the neighbouring labels reaches under it)
		var chosen := posmod(LockWheel.LABELS - floori(operand_position / float(LockWheel.POSITIONS_PER_LABEL)), LockWheel.LABELS)
		add_centred_text(operand_labels[chosen], label_position("operand", chosen, operand_position))   # the label at the top, written on the window
	if not operator_text.is_empty():
		var operator_item := add_text(operator_text, OPERATOR_BOX.position, OPERATOR_BOX.size.x)
		operator_item.position.y += 2                      # centre the line in the box vertically
	if not expression_text.is_empty():
		var expression_item := add_text(expression_text, EXPRESSION_BOX.position, EXPRESSION_BOX.size.x)
		expression_item.position.y -= 2


## Moves the wheels (positions 0-31) and redraws.
func set_wheels(new_operand_position: int, new_answer_position: int) -> void:
	operand_position = posmod(new_operand_position, LockWheel.POSITIONS)
	answer_position = posmod(new_answer_position, LockWheel.POSITIONS)
	refresh()


func set_operand_window(shown: bool) -> void:
	operand_window_shown = shown
	refresh()


func set_boxes(new_operator: String, new_expression: String) -> void:
	operator_text = new_operator
	expression_text = new_expression
	refresh()


## Centre and radius of the answer wheel's picture (window pixels), for clicks on it.
## The size comes from the type's data (the importer wrote the picture's size there), not from the loaded texture.
func answer_wheel_centre() -> Vector2:
	return vector(spec["answer_wheel"]["pos"]) + vector(spec["answer_wheel"]["size"]) / 2.0


func answer_wheel_radius() -> float:
	return float(spec["answer_wheel"]["size"][0]) / 2.0


## Rebuilds the drawing list from the current positions.
func refresh() -> void:
	items.clear()
	_build()
	queue_redraw()


## Window position of label `slot` of a wheel ("operand" or "answer") when the wheel stands at position `at`.
func label_position(wheel: String, slot: int, at: int) -> Vector2:
	var spot := (slot + floori(at / float(LockWheel.POSITIONS_PER_LABEL))) % LockWheel.LABELS
	return vector(spec[wheel + "_labels"][at % LockWheel.POSITIONS_PER_LABEL][spot])


func _add_labels(wheel: String, labels: PackedStringArray, at: int) -> void:
	for slot in labels.size():
		var centre := label_position(wheel, slot, at)
		add_centred_text(labels[slot], centre)             # (the view centres it on the spot; the item holds the spot itself)
