class_name RulerDiagram
extends DiagramBase
## Type 19, Window Crack: a crack drawn as a thick black line just above a ruler.
##
## Teaches: `Rect2` items and unit conversion. The ruler picture has 12 pixels per unit, where a unit
## is a quarter inch, a millimetre ... depending on the record's ruler kind (f0).


func _build() -> void:
	add_spec_items(spec["items"])
	var crack: Dictionary = spec["crack"]
	var ends := crack_ends()
	for y: int in crack["y"]:                       # two 1-pixel lines make the crack 2 pixels thick
		add_rect(Rect2(ends.x, y, ends.y - ends.x, 1), crack["color"])


## [x of the crack's left end, x of its right end] in window pixels.
func crack_ends() -> Vector2:
	var crack: Dictionary = spec["crack"]
	var factor: int = crack["units_per_value"][record.int_at(crack["unit_field"])]
	var from_units := roundi(record.value_at(crack["from_field"]) * factor)
	var to_units := roundi(record.value_at(crack["to_field"]) * factor)
	var x0: int = crack["x0"]
	var per_unit: int = crack["px_per_unit"]
	return Vector2(x0 + from_units * per_unit, x0 + to_units * per_unit)
