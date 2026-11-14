class_name ScaledStyleBox
extends StyleBox
## A nine-patch picture as a style box, for a picture of any scale (`ScaledTexture`): the corners are the number of game units the style says and the minimum size and content margins are in game units, because the stored file is drawn as a `StyleBoxTexture` under a transform of
## `1 / N` over a rectangle N times as large (`RenderingServer.canvas_item_add_set_transform`). `of` is the one way to make the box for a picture. The scale is read from the picture each time the box is drawn (`ScaledTexture.scale_of`, behind a `PictureRef` too), so a box that holds
## a `PictureRef` draws the pictures of whatever chain is in use. Why a `StyleBoxTexture` cannot do it, and where the other consumers are: `docs/engine/PACKS.md`, "Pictures".
##
## Teaches: a `StyleBox` written in GDScript (`_draw` gets the control's canvas item and its rectangle), why a transform on a canvas item is put back after it, and the inner object a script class keeps to reuse a native one's drawing.

## The picture, at the size it reports (a `ScaledTexture`, a `PictureRef`, or a plain texture).
var texture: Texture2D:
	set(value):
		if texture != null and texture.changed.is_connected(emit_changed):
			texture.changed.disconnect(emit_changed)
		texture = value
		if texture != null:
			texture.changed.connect(emit_changed)
		emit_changed()
## The widths of the picture's corners and edges in game units: left, top, right, bottom.
var texture_margin := Vector4i.ZERO:
	set(value):
		texture_margin = value
		emit_changed()

var _inner := StyleBoxTexture.new()
var _file: Texture2D
var _scale := 1
var _cut := Vector4i.ZERO


## The style box of `picture` cut at `slice` (left, top, right, bottom, in game units); the content margins are the slice until a caller says others.
static func of(picture: Texture2D, slice: Vector4i) -> ScaledStyleBox:
	var box := ScaledStyleBox.new()
	box.texture = picture
	box.texture_margin = slice
	box.set_content_margin(SIDE_LEFT, slice.x)                                            # (a `StyleBoxTexture` that says none uses its texture margins: a script class has no such fallback)
	box.set_content_margin(SIDE_TOP, slice.y)
	box.set_content_margin(SIDE_RIGHT, slice.z)
	box.set_content_margin(SIDE_BOTTOM, slice.w)
	return box


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var file := ScaledTexture.stored(texture)
	if file == null:
		return
	_dress(file, ScaledTexture.scale_of(texture))
	if _scale == 1:
		_inner.draw(to_canvas_item, rect)
		return
	RenderingServer.canvas_item_add_set_transform(to_canvas_item, Transform2D(0.0, Vector2.ONE / float(_scale), 0.0, Vector2.ZERO))
	_inner.draw(to_canvas_item, Rect2(rect.position * _scale, rect.size * _scale))
	RenderingServer.canvas_item_add_set_transform(to_canvas_item, Transform2D.IDENTITY)       # (the control draws its text and its children's frames after this: in its own units again)


## The inner style box of the stored `file` and the margins `scale` times as wide (set again only when one of them changed).
func _dress(file: Texture2D, scale: int) -> void:
	if file == _file and scale == _scale and texture_margin == _cut:
		return
	_file = file
	_scale = scale
	_cut = texture_margin
	_inner.texture = file
	_inner.texture_margin_left = texture_margin.x * scale
	_inner.texture_margin_top = texture_margin.y * scale
	_inner.texture_margin_right = texture_margin.z * scale
	_inner.texture_margin_bottom = texture_margin.w * scale
