class_name LcdDisplay
extends Control
## The green seven-segment-style number display of the original's calculator and "Ans:" panel.
##
## Teaches: custom drawing from a picture font. The original has no text font for the display:
## each character is a small picture (digits 8 x 14, point 4 x 6 ...), drawn right to left from a
## fixed x. `_draw` does exactly what the decompiled `DrawCalcDisplay` (0x420b73) does, using the numbers in
## `CalculatorLayout`. Changing `text` only queues a redraw.
##
## Coordinates: the layout numbers are window pixels. This node sits inside a parent (the
## calculator picture or the "Ans:" panel) whose top-left corner is `frame_origin` in window pixels,
## so everything is shifted by that to land in local coordinates.

@export var layout: CalculatorLayout:
	set(value):
		layout = value
		queue_redraw()
## Window position of the parent's top-left corner (where its picture is drawn).
@export var frame_origin: Vector2i = Vector2i.ZERO
## Window position (x0, y0) of the display, from `CalculatorLayout`.
@export var origin: Vector2i = Vector2i.ZERO

## What the display shows: digits, "." "-" "/" and spaces (a mixed number is "3 1/4").
var text: String = "0":
	set(value):
		text = value
		queue_redraw()
## The "F" mark: the player is typing a fraction.
var fraction_flag: bool = false:
	set(value):
		fraction_flag = value
		queue_redraw()
## The pending operator "+", "-", "*" or "/" (or ""), and the memory marker (calculator only).
var operator: String = "":
	set(value):
		operator = value
		queue_redraw()
var memory_flag: bool = false:
	set(value):
		memory_flag = value
		queue_redraw()
## Whether the operator and memory markers exist (the "Ans:" panel has none).
var show_markers: bool = true


## The screen rectangles of every picture drawn for `text`, as [Rect2, Texture2D] pairs in local
## coordinates, right to left. Separate from `_draw` so tests can check the arrangement.
func glyph_placements() -> Array:
	var placements: Array = []
	if layout == null:
		return placements
	var x := origin.x - frame_origin.x + layout.digits_right
	var y := origin.y - frame_origin.y
	for i in range(text.length() - 1, -1, -1):
		var c := text[i]
		var texture: Texture2D = null
		var glyph_size := Vector2i.ZERO                  # the picture's size from the layout's data (never read from the texture)
		var at := Vector2(x, y + layout.digit_y)
		match c:
			".", ",":
				# the point is drawn next to the digit on its left and does not use up a cell
				texture = layout.point_texture
				glyph_size = layout.point_size
				at = Vector2(x + layout.point_offset.x, y + layout.point_offset.y)
			"-":
				texture = layout.minus_texture
				glyph_size = layout.minus_size
				x -= layout.advance
			"/":
				texture = layout.slash_texture
				glyph_size = layout.slash_size
				x -= layout.advance
			" ":
				x -= layout.advance
			_:
				if c >= "0" and c <= "9":
					texture = layout.digit_textures[c.unicode_at(0) - 48]
					glyph_size = layout.digit_sizes[c.unicode_at(0) - 48]
					x -= layout.advance
		if texture != null:
			placements.append([Rect2(at, Vector2(glyph_size)), texture])
	return placements


func _draw() -> void:
	if layout == null:
		return
	var local_origin := Vector2(origin - frame_origin)
	# the black field is wiped first, as the original does
	var field := Rect2(local_origin + Vector2(layout.display_clear_rect.position), Vector2(layout.display_clear_rect.size))
	draw_rect(field, Color.BLACK)
	for placement in glyph_placements():
		draw_texture((placement[1] as Texture2D), (placement[0] as Rect2).position)
	if fraction_flag:
		draw_texture(layout.fraction_flag_texture, local_origin + Vector2(layout.fraction_flag_offset))
	if show_markers:
		var left := Vector2(frame_origin)
		if layout.operator_textures.has(operator):
			draw_texture(layout.operator_textures[operator], Vector2(layout.operator_position) - left)
		if memory_flag:
			draw_texture(layout.memory_texture, Vector2(layout.memory_position) - left)
