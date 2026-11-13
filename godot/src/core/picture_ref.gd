@tool
class_name PictureRef
extends Texture2D
## A picture HELD BY KEY: a texture that says `frame/sub_00` and is whatever picture the chain's tables give that key (`Pictures.resolve`). Data (a SpriteFrames, a tile set, a layout, a zone) holds these instead of
## files, so it names no file of any pack: the packs' tables choose the pictures, and a pack above that redraws a key redraws it everywhere the key is held, with nothing to rebuild.
##
## It is a PROXY. Every question the engine asks a texture is forwarded to the resolved picture: the size, whether it has alpha, the image, its RID (what a `NinePatchRect`, a `StyleBoxTexture` and a `TileSet` atlas hand to the
## renderer) and the three ways to draw (a `Sprite2D`, an `AnimatedSprite2D`, a `TextureRect`, a `TileMapLayer` and every `draw_texture*` call). Nothing is drawn, and the size is 0, for a key no pack holds (told once, `Pictures.unheld_line`). The answer is
## asked again when the chain changes (`Pictures.events`), and the holders hear of it as `changed`, as they hear of an `ImageTexture` that was updated.
##
## In a `.tres` it is a sub-resource with this script and its `key`; in the JSON data form it is `{"$picture": "frame/sub_00"}` (`ResourceJson`).
##
## Teaches: a `Texture2D` written in GDScript that stands for another one (compare `ScaledTexture`, which stands for the same picture at another scale): which virtuals a stand-in must forward so every consumer draws it, and why a
## texture's identity can be a name that is looked up when it is used.

## The picture's skin key (`<kind>/<name>`, `PictureTable.is_key`).
@export var key: String = "":
	set(value):
		key = value
		_forget()
		emit_changed()

var _texture: Texture2D
var _epoch := -1
var _image: Image


## The reference to the picture `picture_key`.
static func of(picture_key: String) -> PictureRef:
	var made := PictureRef.new()
	made.key = picture_key
	return made


func _init() -> void:
	Pictures.events.changed.connect(_chain_changed)


## The picture the chain gives the key now, or null.
func resolved() -> Texture2D:
	if _epoch != Pictures.epoch:
		_epoch = Pictures.epoch
		_image = null
		_texture = Pictures.resolve(key)
		if _texture == null and not key.is_empty():
			TroubleLog.session.tell(Pictures.unheld_line(key))
	return _texture


func _chain_changed() -> void:
	_forget()
	emit_changed()


func _forget() -> void:
	_epoch = -1
	_texture = null
	_image = null


func _get_width() -> int:
	var held := resolved()
	return held.get_width() if held != null else 0


func _get_height() -> int:
	var held := resolved()
	return held.get_height() if held != null else 0


func _has_alpha() -> bool:
	var held := resolved()
	return held != null and held.has_alpha()


func _has_mipmaps() -> bool:
	var held := resolved()
	return held != null and held.has_mipmaps()


func _get_format() -> Image.Format:
	var held := resolved()
	return held.get_format() if held != null else Image.FORMAT_MAX


func _get_image() -> Image:
	var held := resolved()
	return held.get_image() if held != null else null


## A pixel is opaque when the picture's is. (A script cannot ask a texture itself, so the image is read, once per answer.)
func _is_pixel_opaque(x: int, y: int) -> bool:
	var held := resolved()
	if held == null:
		return false
	if _image == null:
		_image = held.get_image()
	if _image == null:
		return true
	var scale := _image.get_width() / maxi(held.get_width(), 1)
	return _image.get_pixel(clampi(x * scale, 0, _image.get_width() - 1), clampi(y * scale, 0, _image.get_height() - 1)).a > 0.0


func _get_rid() -> RID:
	var held := resolved()
	return held.get_rid() if held != null else RID()


func _draw(to_canvas_item: RID, pos: Vector2, modulate: Color, transpose: bool) -> void:
	var held := resolved()
	if held != null:
		held.draw(to_canvas_item, pos, modulate, transpose)


func _draw_rect(to_canvas_item: RID, rect: Rect2, tile: bool, modulate: Color, transpose: bool) -> void:
	var held := resolved()
	if held != null:
		held.draw_rect(to_canvas_item, rect, tile, modulate, transpose)


func _draw_rect_region(to_canvas_item: RID, rect: Rect2, src_rect: Rect2, modulate: Color, transpose: bool, clip_uv: bool) -> void:
	var held := resolved()
	if held != null:
		held.draw_rect_region(to_canvas_item, rect, src_rect, modulate, transpose, clip_uv)
