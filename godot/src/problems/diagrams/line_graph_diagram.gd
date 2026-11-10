class_name LineGraphDiagram
extends DiagramBase
## Type 25, Toxicity Level Graph: seven readings joined by line segments with a dot on each.
##
## Teaches: building a polyline out of sprites. Between two readings the original does not draw a
## line, it stamps one of three 24 pixel wide pictures (flat, rising, falling) and a 12 x 12 dot.


func _build() -> void:
	add_spec_items(spec["items"])
	var graph: Dictionary = spec["graph"]
	var last := reading_count() - 1
	var reading_level := level_of(0)
	var shift: Array = graph["dot_shift"]
	# the line starts flat at the first grid column, the first dot sits at the second
	var first := items.size()
	add_picture(graph["flat_pic"], Vector2(x_of_step(0), y_of_level(reading_level)))
	add_picture(graph["dot_pic"], Vector2(x_of_step(1) - shift[0], y_of_level(reading_level) - shift[0]))
	_end_group(first)                               # one group per reading: the original draws them one by one (spec "intro")
	for k in range(1, last + 1):
		first = items.size()
		var previous := reading_level
		reading_level = level_of(k)
		if reading_level > previous:
			add_picture(graph["rise_pic"], Vector2(x_of_step(k), y_of_level(reading_level)))
		elif reading_level < previous:
			add_picture(graph["fall_pic"], Vector2(x_of_step(k), y_of_level(reading_level + 1)))   # a falling segment hangs from the old reading_level
		else:
			add_picture(graph["flat_pic"], Vector2(x_of_step(k), y_of_level(reading_level)))
		add_picture(graph["dot_pic"], Vector2(x_of_step(k + 1) - shift[1], y_of_level(reading_level) - shift[1]))
		_end_group(first)


## The record stores seven readings f0 .. f6.
func reading_count() -> int:
	return spec["graph"]["x_by_step"].size() - 1


## Reading `k` in grid steps of 400 ppm (0 .. 5).
func level_of(k: int) -> int:
	@warning_ignore("integer_division")
	return record.int_at(k) / int(spec["graph"]["ppm_per_level"])


func y_of_level(grid_level: int) -> int:
	return spec["graph"]["y_by_level"][grid_level]


func x_of_step(step: int) -> int:
	return spec["graph"]["x_by_step"][step]
