class_name PathPictures
extends RefCounted
## BRIDGE (goes when the data holds picture keys, `PictureRef`, instead of picture files): the data resources that still hold a picture FILE by path (a SpriteFrames, the tile set, a layout), shown with the pictures the chain's tables choose.
##
## A data file of the base game names the picture it shows by the file (`assets/sprites/sub/sub_00.png`). The packs laid over another choose pictures by key (`Pictures`); `dress` is the copy of a resource whose textures are those the packs laid over the base game
## say for the key of each file (`GameSkin.key_of`, `Pictures.overlaid`), and the resource itself when no such pack says anything. A skin has no part in it: it changes no picture. Nothing is written to the original resource: the copy is made once per resource
## and kept until the chain changes (`forget`, from `Assets.forget_folders`); a shallow copy, so what no picture changed in is shared with the original.
##
## Teaches: copy-on-write over a resource graph (an array, a dictionary or an inner resource is copied only when something under it changed, otherwise the very same value comes back).

## original resource (its instance id) -> the same resource with the chain's pictures put in.
static var _dressed: Dictionary = {}
## Does a pack laid over another hold a picture table? Asked once per chain (-1 not asked, 0 no, 1 yes).
static var _any_overlay := -1


## `original` as the chain's pictures show it: a changed copy, or `original` itself when no pack laid over another has a picture table.
static func dress(original: Resource) -> Resource:
	if original == null or not _overlaid_anywhere():
		return original
	var held := original.get_instance_id()
	if not _dressed.has(held):
		_dressed[held] = _with_pictures(original)
	return _dressed[held]


## Forget the copies and the answer about the chain (it changed).
static func forget() -> void:
	_dressed = {}
	_any_overlay = -1


static func _overlaid_anywhere() -> bool:
	if _any_overlay < 0:
		_any_overlay = 0
		for each in Packs.chain():
			if each.base != &"" and each.picture_table().present:
				_any_overlay = 1
	return _any_overlay == 1


## A copy of `original` whose textures are the chain's, or `original` when none of them is redrawn.
static func _with_pictures(original: Resource) -> Resource:
	if original is SpriteFrames:
		return _frames_with_pictures(original)
	if original is TileSet:
		return _tile_set_with_pictures(original)
	var copy: Resource = null
	for info in original.get_property_list():
		if not (info.usage & PROPERTY_USAGE_STORAGE):
			continue
		var value: Variant = original.get(info.name)
		var mapped: Variant = _mapped(value)
		if not is_same(mapped, value):
			if copy == null:
				copy = original.duplicate()
			copy.set(info.name, mapped)
	return copy if copy != null else original


## `value` with the chain's pictures put in: a texture of a file a pack redraws becomes the pack's, an array, a dictionary or an inner resource (one that lives inside the file, as the data files' sub-resources do) is copied if something in it
## changed. Anything else, and everything that did not change, comes back as the very same value.
static func _mapped(value: Variant) -> Variant:
	if value is PictureRef:
		return value                             # (a key: the chain's tables choose the picture, `Pictures`)
	if value is Texture2D:
		var texture: Texture2D = value
		var mapped := Pictures.overlaid(GameSkin.key_of(Packs.source_of(texture)))
		return mapped if mapped != null else texture
	if value is Array:
		var array: Array = value
		var copy: Array = array.duplicate()      # (typed arrays stay typed)
		var changed := false
		for i in array.size():
			var mapped: Variant = _mapped(array[i])
			if not is_same(mapped, array[i]):
				copy[i] = mapped
				changed = true
		return copy if changed else array
	if value is Dictionary:
		var dictionary: Dictionary = value
		var copy: Dictionary = dictionary.duplicate()
		var changed := false
		for key in dictionary:
			var mapped: Variant = _mapped(dictionary[key])
			if not is_same(mapped, dictionary[key]):
				copy[key] = mapped
				changed = true
		return copy if changed else dictionary
	if value is Resource and _is_inner(value):
		return _with_pictures(value)
	return value


## Does `resource` live inside the file that holds it ("zones.tres::ZoneData_x") or is it not saved at all, rather than in a file of its own (a script, a font, a picture)? Only those are copied; the others are shared.
static func _is_inner(resource: Resource) -> bool:
	var source := Packs.source_of(resource)
	return source.is_empty() or source.contains("::")


static func _frames_with_pictures(original: SpriteFrames) -> SpriteFrames:
	var copy: SpriteFrames = null
	for animation in original.get_animation_names():
		for i in original.get_frame_count(animation):
			var texture := original.get_frame_texture(animation, i)
			var mapped := _mapped(texture) as Texture2D
			if mapped != texture:
				if copy == null:
					copy = original.duplicate() as SpriteFrames
				copy.set_frame(animation, i, mapped, original.get_frame_duration(animation, i))
	return copy if copy != null else original


static func _tile_set_with_pictures(original: TileSet) -> TileSet:
	var copy: TileSet = null
	for i in original.get_source_count():
		var source := original.get_source(original.get_source_id(i)) as TileSetAtlasSource
		var mapped := _mapped(source.texture) as Texture2D if source != null else null
		if mapped != null and mapped != source.texture:
			if copy == null:
				copy = original.duplicate(true) as TileSet     # (deep: the sources are part of the set, and must not be shared)
			(copy.get_source(copy.get_source_id(i)) as TileSetAtlasSource).texture = mapped
	return copy if copy != null else original
