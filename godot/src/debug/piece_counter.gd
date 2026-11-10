class_name PieceCounter
extends Control
## Row of little boxes, one per capsule piece of the sector: filled when collected.
##
## The original console has no piece read-out (the player counts on the "magnetometer" message at
## the end station), so the real HUD does not show one either: this is a debugging aid that lives
## in the F3 overlay (`GameDebug`). The first box is the data canister.
##
## Teaches: another tiny `_draw` gauge, fed by one method (`show_pieces`) instead of reading
## `GameState` itself, which keeps it trivially testable. Because it sits in `src/debug/`, nothing
## in the real game depends on it and a release build leaves it out with the rest of the overlay.

const BOX := 10
const GAP := 4
const COLLECTED_COLOR := Color("ffff55")
const CANISTER_COLOR := Color("55ffff")
const MISSING_COLOR := Color("555555")
const TITLE_GAP := 8

var total: int = 0
var mask: int = 0
var _title: Label


func _ready() -> void:
	_title = Label.new()
	_title.text = "Pieces"
	_title.theme_type_variation = &"DebugLabel"
	_title.position = Vector2(0, -2)
	add_child(_title)
	custom_minimum_size = Vector2(_title.get_minimum_size().x + TITLE_GAP + 11 * (BOX + GAP), 20)


## Shows `total` boxes; bit i of `collected_mask` set means piece i is taken.
func show_pieces(piece_total: int, collected_mask: int) -> void:
	total = piece_total
	mask = collected_mask
	queue_redraw()


## How many boxes are filled.
func collected_count() -> int:
	var count := 0
	for i in total:
		if mask & (1 << i):
			count += 1
	return count


func _draw() -> void:
	var x := (_title.get_minimum_size().x if _title != null else 40.0) + TITLE_GAP
	for i in total:
		var rect := Rect2(x + i * (BOX + GAP), 4, BOX, BOX)
		if mask & (1 << i):
			draw_rect(rect, CANISTER_COLOR if i == 0 else COLLECTED_COLOR)
		else:
			draw_rect(rect, MISSING_COLOR, false, 1.0)
