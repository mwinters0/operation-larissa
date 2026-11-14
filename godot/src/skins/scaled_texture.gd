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
## What the renderer takes by RID instead of asking the texture to draw (a `TileSet`'s atlas, a nine-patch, a `StyleBoxTexture`) never sees this class: its RID is empty, so those consumers are given the stored picture and the scale by one builder each:
## `ScaledTileSet` (a tile set at `scale` times its cell size under a layer at `1 / scale`) and `ScaledStyleBox` (a nine-patch drawn under a transform of `1 / scale`). `stored` and `scale_of` are how they read a picture. A `Sprite3D` and a
## `NinePatchRect` are not used by the game; a shader's `sampler2D` uniform is a picture of its own and `TEXTURE` is the stored picture, whose own pixel size `TEXTURE_PIXEL_SIZE` reports.

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


## The picture as it is stored (a file `scale_of(texture)` times as large as `texture` says it is): the picture `texture` stands for with every `ScaledTexture` and `PictureRef` taken off, or `texture` itself when it is a plain picture. Null for a `PictureRef`
## that holds no picture. What a consumer that hands the renderer a texture's RID is given (`ScaledTileSet`, `ScaledStyleBox`).
static func stored(texture: Texture2D) -> Texture2D:
	var held := texture
	if held is PictureRef:
		held = (held as PictureRef).resolved()
	return (held as ScaledTexture).source if held is ScaledTexture else held


## How many times larger than the size `texture` reports its stored picture is: the `scale` of a `ScaledTexture` (also behind a `PictureRef`), 1 for any other picture.
static func scale_of(texture: Texture2D) -> int:
	var held := texture
	if held is PictureRef:
		held = (held as PictureRef).resolved()
	return (held as ScaledTexture).scale if held is ScaledTexture else 1


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


## A rectangle on the screen is the same for either size: the large file is simply sampled more finely. A tiled rectangle repeats the picture at the size it reports, so the repeat is made here from the whole picture, one cell at a time (`rect` is a few cells in the game's use).
func _draw_rect(to_canvas_item: RID, rect: Rect2, tile: bool, modulate: Color, transpose: bool) -> void:
	if source == null:
		return
	if not tile:
		source.draw_rect(to_canvas_item, rect, false, modulate, transpose)
		return
	var cell := get_size()
	if cell.x <= 0.0 or cell.y <= 0.0:
		return
	var y := 0.0
	while y < rect.size.y:
		var x := 0.0
		while x < rect.size.x:
			var piece := Vector2(minf(cell.x, rect.size.x - x), minf(cell.y, rect.size.y - y))
			source.draw_rect_region(to_canvas_item, Rect2(rect.position + Vector2(x, y), piece), Rect2(Vector2.ZERO, (piece * float(scale)).min(source.get_size())), modulate, transpose, true)
			x += cell.x
		y += cell.y


## `src_rect` is in the REPORTED size's pixels (a sprite sheet cell, a progress bar's fill); the file has `scale` times as many.
func _draw_rect_region(to_canvas_item: RID, rect: Rect2, src_rect: Rect2, modulate: Color, transpose: bool, clip_uv: bool) -> void:
	if source != null:
		source.draw_rect_region(to_canvas_item, rect, Rect2(src_rect.position * scale, src_rect.size * scale), modulate, transpose, clip_uv)
