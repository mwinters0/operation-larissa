class_name PicturePainter
extends Control
## A control that draws its texture with the two `draw_texture*` calls of `CanvasItem` (the way `LcdDisplay`, `IconGauge` and a diagram draw a picture), for `test_picture_ref_render.gd`: `draw_texture_rect` fills the left half of the control and `draw_texture`
## puts the picture at its own size at the top left of the right half.
##
## Teaches: what a custom `_draw` asks of a texture, and that it does not hear of a change by itself: whoever owns a drawing control calls `queue_redraw`.

var texture: Texture2D


func _draw() -> void:
	if texture == null:
		return
	draw_texture_rect(texture, Rect2(0, 0, size.x / 2, size.y), false)
	draw_texture(texture, Vector2(size.x / 2, 0))
