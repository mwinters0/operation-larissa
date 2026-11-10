class_name PieDiagram
extends DiagramBase
## Type 17, Food Supply Pie Chart: a pie made of three fixed slice pictures and a legend of food names.
##
## Teaches: why the old "random slices" idea was wrong. Decompiling `Prob17_Diagram` shows that the slices
## are PRE-DRAWN pictures (the record's f0 picks one of two pies: thirds, or half/quarter/quarter) and
## the only random part is which food the legend names first (`rotation`, 0 or 1).
##
## The legend has three rows (green, purple, orange boxes); row r names food (rotation + r) % 3
## (canned, frozen, freeze-dried). The prompt asks about rows by colour, see `ProblemTexts`.

const GREEN := ProblemTexts.PIE_GREEN
const PURPLE := ProblemTexts.PIE_PURPLE
const ORANGE := ProblemTexts.PIE_ORANGE


func _build() -> void:
	add_spec_items(spec["items"])
	var legend: Dictionary = spec["legend"]
	for row in 3:
		add_text(type.text_at(int(legend["text_base"]) + food_in_row(row)), vector(legend["pos"][row]))
	for slice: Dictionary in spec["layouts"].get(_layout_key(), spec["layouts"]["default"]):
		var first := items.size()
		add_picture(slice["pic"], vector(slice["pos"]))
		_end_group(first)                           # the slices appear one after the other (spec "intro")


## The food (0 canned, 1 frozen, 2 freeze-dried) named in legend row `row`.
func food_in_row(row: int) -> int:
	return (problem.pie_rotation + row) % 3


## Share of the pie, as a fraction 0..1, of the slice with the colour of legend row `row`.
func share_of_row(row: int) -> float:
	var shares: Array = spec["shares"].get(_layout_key(), spec["shares"]["default"])
	return float(shares[row][0]) / float(shares[row][1])


func _layout_key() -> String:
	return str(record.int_at(0)) if spec["layouts"].has(str(record.int_at(0))) else "default"
