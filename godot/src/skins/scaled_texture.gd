class_name ScaledTexture
extends Texture2D
## A picture drawn at a FRACTION of its size: a texture whose file is `scale` times larger than the size it reports. This is how 4x art
## goes into a game whose coordinates are 640 x 400: the file is 384 x 216 pixels, the texture says it is 96 x 54, and so everything that
## asks the size (a sprite's centre, a layout's rectangle, a hit test) gets the original's number and nothing moves. The window draws the
## 2D scene at its own resolution (`stretch/mode="canvas_items"`), so the extra pixels of the file reach the screen: the picture is
## sharp at any window size instead of enlarged pixels.
##
## Teaches: a `Texture2D` is an interface, not a file. The engine asks it for a size, whether it has transparency, and to draw itself;
## a script that answers those questions (the `_get_width` ... `_draw_rect_region` methods below) is a texture as far as every
## `Sprite2D`, `AnimatedSprite2D`, `TextureRect` and `TextureProgressBar` is concerned. Compare `AtlasTexture`, which answers with a
## piece of another texture; this one answers with the same picture at another scale.
##
## What it does not do: nodes that hand the texture's own RID to the renderer instead of asking it to draw (a `TileSet`'s atlas, a
## `Sprite3D`, a shader's `sampler2D` uniform) see the large file as it is. A skin that wants a sharper tile set gives it a
## `TileSetAtlasSource` with the larger texture and `texture_region_size` and the same tile coordinates, as a whole resource instead.

## The picture as it is stored: `scale` times larger than it is drawn.
@export var source: Texture2D
## How many times larger in each direction the stored picture is than the size this texture reports (4 for 4x art).
@export_range(1, 16) var scale: int = 4


## The texture of `file` shown at `1 / factor` of its size.
static func of(file: Texture2D, factor: int) -> ScaledTexture:
	var made := ScaledTexture.new()
	made.source = file
	made.scale = factor
	return made


func _get_width() -> int:
	return ceili(float(source.get_width()) / scale) if source != null else 0


func _get_height() -> int:
	return ceili(float(source.get_height()) / scale) if source != null else 0


func _has_alpha() -> bool:
	return source != null and source.has_alpha()


## A pixel of the reported size is opaque if the pixel in the middle of its `scale` x `scale` block of the stored picture is. (The engine
## asks for `Sprite2D.is_pixel_opaque`, a click test; a script cannot ask a texture itself, so this reads the picture's image.)
func _is_pixel_opaque(x: int, y: int) -> bool:
	var image := source.get_image() if source != null else null
	if image == null:
		return true
	var half := scale >> 1
	return image.get_pixel(clampi(x * scale + half, 0, image.get_width() - 1), clampi(y * scale + half, 0, image.get_height() - 1)).a > 0.0


func _draw(to_canvas_item: RID, pos: Vector2, modulate: Color, transpose: bool) -> void:
	if source != null:
		source.draw_rect(to_canvas_item, Rect2(pos, get_size()), false, modulate, transpose)


## A rectangle on the screen is the same for either size: the large file is simply sampled more finely.
func _draw_rect(to_canvas_item: RID, rect: Rect2, tile: bool, modulate: Color, transpose: bool) -> void:
	if source != null:
		source.draw_rect(to_canvas_item, rect, tile, modulate, transpose)


## `src_rect` is in the REPORTED size's pixels (a sprite sheet cell, a progress bar's fill); the file has `scale` times as many.
func _draw_rect_region(to_canvas_item: RID, rect: Rect2, src_rect: Rect2, modulate: Color, transpose: bool, clip_uv: bool) -> void:
	if source != null:
		source.draw_rect_region(to_canvas_item, rect, Rect2(src_rect.position * scale, src_rect.size * scale), modulate, transpose, clip_uv)
