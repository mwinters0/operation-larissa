class_name MathTrigger
extends Node2D
## An invisible spot on a screen that starts a math problem when the sub reaches it, as the debug view draws it.
##
## Teaches: data-driven nodes (one marker node per trigger of the screen) that show a model: whether the trigger is armed is the
## `TriggerModel`'s (the node is thrown away whenever the screen changes, the model lives as long as the sector), and the rule
## that decides when it fires is `TriggerModel.fires` (the lookup table of `DetectMathTrigger` 0x427744). The real game shows
## nothing; this marker exists for the sector viewer's "show triggers" toggle.

var model: TriggerModel
var data: MathTriggerData
## Position of the trigger in the sector's list for its screen (identifies it).
var index: int = 0
## Debug: draw a marker where the trigger is (the real game shows nothing).
var debug_draw: bool = false:
	set(value):
		debug_draw = value
		queue_redraw()


## Call before adding the node to the tree.
func setup(trigger: TriggerModel) -> void:
	model = trigger
	data = trigger.data
	index = trigger.index
	# Window pixels in the data, like the sub's SubX / SubY (see Collectible.setup).
	position = Vector2(data.pos) - Sub.PLAYFIELD_ORIGIN


func _draw() -> void:
	if not debug_draw:
		return
	var color := Color(1, 0.8, 0.2) if model.armed else Color(0.5, 0.5, 0.5)
	draw_circle(Vector2.ZERO, 5.0, color)
	draw_string(ThemeDB.fallback_font, Vector2(7, 4), str(data.slot), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
