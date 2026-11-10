class_name ConsoleFrame
extends Control
## The black and grey frame the original paints around the playfield and the console
## (`DisplayBezelFrame` (0x41a3e8), the last step of `DisplayBezel`).
##
## Teaches: `_draw` with `draw_rect`. The frame is nothing but a list of filled rectangles in
## painting order (later ones cover earlier ones), stored in `HudLayout`. One node paints them all.
##
## The top 23 pixels are black on purpose: that is where the Godot `MenuBar` sits (the original
## used the Windows menu there, outside its 640 x 400 drawing).

@export var layout: HudLayout:
	set(value):
		layout = value
		queue_redraw()


func _draw() -> void:
	if layout == null:
		return
	for i in layout.frame_rects.size():
		draw_rect(Rect2(layout.frame_rects[i]), layout.frame_colors[i])
