class_name StorageBoxesDiagram
extends DiagramBase
## Type 30, Food Storage: boxes stacked in the storage compartment, length x width x height (and extras).
##
## Teaches: nested loops that place sprites in an oblique (3D-looking) arrangement: each row back
## shifts a little left and down, each layer up shifts up. The compartment's front picture is drawn
## after every box so that boxes disappear behind its frame, exactly like the original.


func _build() -> void:
	add_spec_items(spec["items"])
	var boxes: Dictionary = spec["boxes"]
	var origin := vector(boxes["origin"])
	var rows := record.int_at(boxes["width_field"])
	for layer in record.int_at(boxes["height_field"]):
		var base := origin + Vector2(0, boxes["layer_dy"]) * layer
		for row in rows:
			_add_row(base + Vector2(boxes["row_dx"], boxes["row_dy"]) * row, record.int_at(boxes["length_field"]))
	# extra boxes (level 3) continue in one row in front of the stack
	var extra := record.int_at(boxes["extra_field"])
	if extra > 0:
		var front := origin + Vector2(boxes["row_dx"], boxes["row_dy"]) * rows
		front.y = origin.y + float(boxes["row_dy"]) * rows
		_add_row(front, extra)


## One row of `count` boxes starting at `at`: the two box pictures alternate and each step moves right by x_step[0], x_step[1], ...
func _add_row(at: Vector2, count: int) -> void:
	var boxes: Dictionary = spec["boxes"]
	var step: Array = boxes["x_step"]
	var x_offset := 0
	for i in count:
		var first := items.size()
		add_picture(boxes["pics"][i % 2], at + Vector2(x_offset, 0))
		add_picture(boxes["front_pic"], vector(boxes["front_pos"]))
		_end_group(first)                           # a box and the compartment front over it appear together (spec "intro")
		x_offset += step[(i + 1) % 2]


## How many boxes are drawn (the compartment pictures are not boxes).
func box_count() -> int:
	return pictures(spec["boxes"]["pics"][0]).size() + pictures(spec["boxes"]["pics"][1]).size()
