class_name SearchGridDiagram
extends DiagramBase
## Types 32 and 33, Search Grid (fraction / decimal of the grid): a grid of squares, some of them shaded.
##
## Teaches: one drawing routine serving two problem types (the original shares all the code), and
## a table-driven grid whose cell size depends on the number of squares (100, 16 or 4).


func _build() -> void:
	add_spec_items(spec["items"])
	var grid := grid_for(record.int_at(spec["total_field"]))
	var origin := vector(spec["origin"])
	if grid["overlay"] != null:
		add_picture(grid["overlay"], origin)
	var step := vector(grid["step"])
	var columns: int = grid["columns"]
	for i in record.int_at(spec["shaded_field"]):
		@warning_ignore("integer_division")
		var first := items.size()
		add_picture(grid["pic"], origin + Vector2(i % columns, i / columns) * step)
		_end_group(first)                           # one shaded square after the other (spec "intro")


## The grid description for `total` squares (anything but 4 and 16 is the 10 x 10 grid).
func grid_for(total: int) -> Dictionary:
	return spec["grids"].get(str(total), spec["grids"]["100"])


## Number of shaded squares drawn.
func shaded_count() -> int:
	return pictures(grid_for(record.int_at(spec["total_field"]))["pic"]).size()
