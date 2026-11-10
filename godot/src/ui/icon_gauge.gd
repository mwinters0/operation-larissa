class_name IconGauge
extends Control
## A gauge made of a row of icons: the first `value` show the "full" picture, the others the "empty" one.
##
## Teaches: a small custom-drawn Control. Instead of 21 TextureRect nodes for the ink pellets, one
## node draws all of them in `_draw`, and only redraws (`queue_redraw`) when its value changes,
## which is what the HUD's "no polling in `_process`" rule asks for. The slot positions are plain
## data (`slot_positions`), so the same class draws the tank row, the oxygen cells and the pellets.
##
## The oxygen gauge has one special case: with one cell left the first cell shows a warning
## picture (`low_texture`, shown when `value == low_value`).

@export var slot_positions: PackedVector2Array = PackedVector2Array():
	set(positions):
		slot_positions = positions
		queue_redraw()
@export var full_texture: Texture2D:
	set(texture):
		full_texture = texture
		queue_redraw()
@export var empty_texture: Texture2D:
	set(texture):
		empty_texture = texture
		queue_redraw()
## Shown in the first slot while `value == low_value` (optional).
@export var low_texture: Texture2D
@export var low_value: int = 1
## How many slots are "full". Changing it redraws the gauge, nothing else.
@export var value: int = 0:
	set(new_value):
		new_value = clampi(new_value, 0, slot_positions.size())
		if new_value == value:
			return
		value = new_value
		queue_redraw()
		value_changed.emit(value)

## The number of full slots changed.
signal value_changed(value: int)


## True while the warning picture replaces the first cell.
func is_low() -> bool:
	return low_texture != null and value == low_value


## The picture slot `index` shows now (also what the tests look at).
func texture_for_slot(index: int) -> Texture2D:
	if index < value:
		return low_texture if (index == 0 and is_low()) else full_texture
	return empty_texture


func _draw() -> void:
	for i in slot_positions.size():
		var texture := texture_for_slot(i)
		if texture != null:
			draw_texture(texture, slot_positions[i])
