class_name GameSkin
extends Resource
## A skin: what the game looks like, as DATA. It maps the NAMES of the registry (a picture, a layout, the presenter) to this skin's own
## resources, and everything it does not map is the original's. The rules and the content know nothing about skins
## (`tests/engine/test_rules_are_plain_objects.gd`); everything that draws asks `Assets` / `Catalog`, which ask the current skin
## (`SkinChoice.current()`), so one skin file is the whole difference between two looks.
##
## WHAT A SKIN MAPS
##  * `pictures`: a picture's KEY to a `Texture2D`. A key is `<kind>/<registry name>`: `ui_picture/title_sky`, `problem_art/log_scan_0`,
##    `frame/dolphin_swim_0` (a creature picture), `deco/coral_fan_cyan`, plus the pictures the registry does not name, which keep the
##    file's name: `tile/zone0_tiles`, `background/bg_s00_00`, and `frame/sub_00` (the sub, the pieces, the station, the bubbles). `key_of(path)` makes the key of a file under a pack's `assets/` (`Packs.relative`),
##    so every picture the data files hold by path (the SpriteFrames, the layouts, the tileset, the problems) is resolved through
##    the same table (`skinned`, `texture_at`).
##  * `art_folder` / `art_scale`: pictures as FILES instead of entries: `<art_folder>/<key>.png` is this skin's picture for `key`
##    (`<art_folder>/frame/sub_00.png`), drawn at `1 / art_scale` of its size (`ScaledTexture`), so a folder of 4x art needs no list, and a
##    picture that is not in the folder is simply the next skin's. `pictures` wins over the folder for a key both have.
##  * `resources`: a whole data resource instead of the original's, by its path under the data folder (a pack's `res://packs/<id>/data/`, or the project's `res://data/`) without `.tres`:
##    `ui/hud_layout`, `ui/story_layout`, `problems/screen_layout`, `sprite_frames/foes_zone2`, `neptune_tileset`. For a skin whose
##    pictures have other sizes or whose HUD is laid out differently (the layouts are data). ONLY presentation data can be
##    replaced (`REPLACEABLE`): a key that names rules or content (`zones`, `trigger_table`, `problems/problem_type_07` with
##    its records and answers, `sprite_meta/...` with the hit rectangles, a sector) is ignored, so a skin cannot change what the game
##    does by dressing up as a data file (`refused_resources` lists such keys for the author; `test_skins_dont_change_the_game.gd`).
##  * `presenter_scene`: the scene that shows a sector (`PresenterChoice.ORIGINAL_SCENE` is the original's); its root extends
##    `SectorPresenter`.
##  * `render`: filter and pixel snapping (`RenderSettings`); `hud_labels`: the HUD's zone / sector / game lettering as text.
##  * `layer_materials`: a shader (with its uniforms) on a layer of the original presenter, by the layer's name (`SkinLayers.NODES`). Presentation only: the presenter makes its own copy of the material each time it is built (`layer_material`) and
##    sets the `phase` uniform itself, so a skin holds no state of a run.
## An empty field means "not mine": the lookup goes on to `fallback` (another skin, for a skin that builds on a skin) and ends at the
## original, which maps nothing at all and keeps today's pictures, files and settings.
##
## Teaches: a Resource as a bundle of choices, edited in the Inspector like any other; a Dictionary exported with typed keys and
## values (`Dictionary[String, Texture2D]`); and an override table with a fallback chain, the same idea as CSS or a theme: the
## specific thing wins, the general thing answers the rest. Pack roots are one more link, at the FRONT: a mounted pack's picture
## for a key (`Packs.picture`) wins over every skin, because it is the CONTENT that says what that picture is (a pack that redraws a tile
## replaces the tile; a skin only dresses the pictures the content has). A skin's own art is for the pictures of the base game.

## The data resources a skin may replace by `resources`, as the start of their key: the layouts, the picture bundles and the tile set. The
## rest of the data is the rules and the content, which no skin can replace (pictures INSIDE them, such as a problem's art, still
## map through `pictures`).
const REPLACEABLE: Array[String] = ["ui/", "sprite_frames/", "neptune_tileset", "problems/screen_layout"]

## The kinds of picture key there are (the part of a key before the `/`, `key_of`). A pack's `pictures/` folder holds these kinds (`PackCheck`), and a mod's draw list may name a picture of any of them (`ModSpec.is_drawable_key`);
## a skin mod's `pictures` may replace only `ModSpec.PICTURE_KINDS` of them.
const KEY_KINDS: Array[String] = ["ui_picture", "background", "problem_art", "frame", "deco", "tile"]

## The skin's id: the folder name under `res://skins/` and the word of `--skin=<id>`.
@export var id: StringName = &""
## What a menu would show.
@export var display_name: String = ""
## The skin that answers what this one does not map. Empty means the original (the original itself has none).
@export var fallback: GameSkin

@export var pictures: Dictionary[String, Texture2D] = {}
## A folder of picture files named by key (`res://skins/<id>/art`, holding `frame/sub_00.png`, `ui_picture/ui_1189.png` ...), or "".
@export_dir var art_folder: String = ""
## How many times larger the files of `art_folder` are than the size they are drawn at: 4 for 4x art, 1 for pictures of the right size.
@export_range(1, 16) var art_scale: int = 1
@export var resources: Dictionary[String, Resource] = {}
@export var presenter_scene: PackedScene
@export var render: RenderSettings
@export var hud_labels: HudLabels
## A material for a layer of the original presenter: layer name (`SkinLayers.NODES`) -> a `ShaderMaterial` with the shader and the values of its uniforms. Never put on a node as it is: `layer_material` hands out copies.
@export var layer_materials: Dictionary[StringName, ShaderMaterial] = {}

## A made-up name of the registry (`ui_1189`, `pa_1780`) already holds its number; a real one is followed by it in the file name.
static var _trailing_number := RegEx.create_from_string("^(.+)_(\\d+)$")
## path -> key, so a picture asked for a hundred times is parsed once.
static var _keys: Dictionary = {}

## key -> the texture of the file `art_folder/key.png` (a `ScaledTexture` for `art_scale` > 1), or null for a key with no file. A lookup
## that found nothing is kept too, so the folder is asked about a key once.
var _art: Dictionary = {}

## original resource (its instance id) -> the same resource with this skin's pictures put in. Filled by `skinned`.
var _retextured: Dictionary = {}


# --- the lookups (each one: this skin, else the next, else the original's) ------------------------------------

## The skin that answers what this one does not: `fallback`, or the original for every skin but the original.
func next_skin() -> GameSkin:
	if fallback != null:
		return fallback
	if id == SkinChoice.ORIGINAL:
		return null
	return SkinChoice.original()


## The picture for `key` (see the class comment): a mounted pack's, else this skin's, else the next skin's. Null when none maps it.
func picture(key: String) -> Texture2D:
	var from_pack := Packs.picture(key)
	return from_pack if from_pack != null else _skin_picture(key)


## This skin's picture for `key`, or the skins behind it, or null: the chain without the packs.
func _skin_picture(key: String) -> Texture2D:
	if pictures.has(key):
		return pictures[key]
	var from_folder := _art_picture(key)
	if from_folder != null:
		return from_folder
	var next := next_skin()
	return next._skin_picture(key) if next != null else null


## This skin's data resource for `data_key` (a path under the data folder without `.tres`), or null. Only the keys of `REPLACEABLE` count.
func resource_for(data_key: String) -> Resource:
	if resources.has(data_key) and is_replaceable(data_key):
		return resources[data_key]
	var next := next_skin()
	return next.resource_for(data_key) if next != null else null


## May a skin replace the data resource `data_key`? (`REPLACEABLE`)
static func is_replaceable(data_key: String) -> bool:
	for start in REPLACEABLE:
		if data_key.begins_with(start):
			return true
	return false


## The keys of `resources` that are ignored because they name rules or content, not presentation. An authoring check: it should be empty.
func refused_resources() -> Array[String]:
	var refused: Array[String] = []
	for data_key in resources:
		if not is_replaceable(data_key):
			refused.append(data_key)
	return refused


## The scene of this skin's sector presenter, or null: the original's.
func presenter_scene_or_null() -> PackedScene:
	if presenter_scene != null:
		return presenter_scene
	var next := next_skin()
	return next.presenter_scene_or_null() if next != null else null


## The render settings of this skin, else of the skin behind it; the project's own if nobody sets any (the original look).
func render_settings() -> RenderSettings:
	if render != null:
		return render
	var next := next_skin()
	return next.render_settings() if next != null else RenderSettings.new()


## A new copy of the material this skin, else the skin behind it, puts on the layer `layer` of the original presenter (`SkinLayers.NODES`), or null for a layer no skin dresses. A copy, so that two presenters on screen have a `phase` each.
func layer_material(layer: StringName) -> ShaderMaterial:
	if layer_materials.has(layer):
		return layer_materials[layer].duplicate() as ShaderMaterial
	var next := next_skin()
	return next.layer_material(layer) if next != null else null


## The HUD's text lettering, or null while the skin shows the original's pictures of the words.
func labels() -> HudLabels:
	if hud_labels != null:
		return hud_labels
	var next := next_skin()
	return next.labels() if next != null else null


## Does this skin or one behind it map any picture, or does a mounted pack hold some? (If none does, the original's resources are used as
## they are.)
func has_pictures() -> bool:
	if not pictures.is_empty() or not art_folder.is_empty() or Packs.has_pictures():
		return true
	var next := next_skin()
	return next != null and next.has_pictures()


## The picture of `key` in `art_folder`, or null. The file is loaded the first time it is asked for, and the same texture answers
## every time after that.
func _art_picture(key: String) -> Texture2D:
	if art_folder.is_empty() or key.is_empty():
		return null
	if not _art.has(key):
		var path := "%s/%s.png" % [art_folder, key]
		var file := load(path) as Texture2D if ResourceLoader.exists(path) else null
		_art[key] = ScaledTexture.of(file, art_scale) if file != null and art_scale > 1 else file
	return _art[key]


# --- pictures by file ------------------------------------------------------------------------------------

## The texture of the picture file `path` (under a pack's `assets/`): this skin's picture for it, else the file itself. The ONE
## place a path becomes a texture, so `Assets` and everything that holds a path in data ask here. "" gives null.
func texture_at(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var mapped := picture(key_of(path))
	return mapped if mapped != null else Packs.file_at(path) as Texture2D


## The key a picture file has in `pictures`: "ui_picture/title_sky" for "res://packs/legacy/assets/ui/title/title_sky_1039.png". The kind comes
## from the folder and the name from the file's, without the number the importer appends to a registry name (a made-up name, which
## holds its number already, stays as it is: "ui_picture/ui_1189"). "" for a file that is not a picture of the game.
static func key_of(path: String) -> String:
	if _keys.has(path):
		return _keys[path]
	var key := _make_key(path)
	if not key.is_empty():
		_keys[path] = key                    # (an empty answer is not kept: the same path can be a picture of a pack chosen later)
	return key


static func _make_key(path: String) -> String:
	return key_of_rel(Packs.relative(path))


## The key of the picture file `assets` as a pack keeps it (`assets/ui/title/title_sky_1039.png`, what `Packs.relative` makes of a path), "" for a file that is not a picture of the game.
static func key_of_rel(assets: String) -> String:
	if not assets.begins_with("assets/"):
		return ""
	var parts := assets.trim_prefix("assets/").split("/")
	if parts.size() < 2:
		return ""
	var stem := parts[parts.size() - 1].get_basename()
	match parts[0]:
		"ui":
			return "ui_picture/" + _registry_name(&"ui_picture", stem)
		"problem_art":
			return "problem_art/" + _registry_name(&"problem_art", stem)
		"sprites":
			if parts[1] != "foes" and parts[1] != "decos":
				return "frame/" + stem      # the sub, pieces, station and bubbles: no registry names, so "sub_00" must not become "sub"
			var kind := &"deco" if parts[1] == "decos" else &"frame"
			return "%s/%s" % [kind, _registry_name(kind, stem)]
		"tiles":
			return "tile/" + stem
		"backgrounds":
			return "background/" + stem
	return ""


static func _registry_name(kind: StringName, stem: String) -> String:
	var found := _trailing_number.search(stem)
	if found == null or NameRegistry.fallback_index(kind, stem) >= 0:
		return stem
	return found.get_string(1)


# --- data resources --------------------------------------------------------------------------------------

## `original` (a resource of the data folders, as `Catalog` loads it) as THIS skin shows it: the skin's own resource for it if it has
## one (`resources`), else the original with this skin's pictures put in place of its textures, else `original` itself. Nothing is
## written to `original`: the changed copy is made once per skin and kept.
func skinned(original: Resource) -> Resource:
	if original == null:
		return null
	var own := resource_for(_data_key(Packs.source_of(original)))
	if own != null:
		return own
	if not has_pictures():
		return original                          # (the original skin: the very same object, so nothing about it can differ)
	var original_id := original.get_instance_id()
	if not _retextured.has(original_id):
		_retextured[original_id] = _with_pictures(original)
	return _retextured[original_id]


## Forget the copies `skinned` made: call it after changing `pictures`, `resources` or the files of `art_folder` while the game runs
## (a tool, a test).
func forget() -> void:
	_retextured.clear()
	_art.clear()
	var next := next_skin()
	if next != null:
		next.forget()


## "res://packs/legacy/data/ui/hud_layout.tres" -> "ui/hud_layout" (and "res://data/ui/menu_layout.tres" -> "ui/menu_layout"); "" for a resource that is not a file of
## a pack's `data/` or the project's `res://data/`.
static func _data_key(path: String) -> String:
	var in_a_pack := Packs.relative(path)
	if in_a_pack.begins_with("data/"):
		return in_a_pack.trim_prefix("data/").get_basename()
	if path.begins_with("res://data/"):
		return path.trim_prefix("res://data/").get_basename()
	return ""


## A copy of `original` whose textures are this skin's, or `original` when none of them is mapped.
func _with_pictures(original: Resource) -> Resource:
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
				copy = original.duplicate()      # (a shallow copy: what no picture changed in is shared with the original)
			copy.set(info.name, mapped)
	return copy if copy != null else original


## `value` with this skin's pictures put in: a texture of a mapped file becomes the skin's, an array, a dictionary or an inner
## resource (one that lives inside the file, as the data files' sub-resources do) is copied if something in it changed. Anything
## else, and everything that did not change, comes back as the very same value.
func _mapped(value: Variant) -> Variant:
	if value is Texture2D:
		var texture: Texture2D = value
		var mapped := picture(key_of(Packs.source_of(texture)))
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


## Does `resource` live inside the file that holds it ("zones.tres::ZoneData_x") or is it not saved at all, rather than in a file of
## its own (a script, a font, a picture)? Only those are copied; the others are shared.
static func _is_inner(resource: Resource) -> bool:
	var source := Packs.source_of(resource)
	return source.is_empty() or source.contains("::")


func _frames_with_pictures(original: SpriteFrames) -> SpriteFrames:
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


func _tile_set_with_pictures(original: TileSet) -> TileSet:
	var copy: TileSet = null
	for i in original.get_source_count():
		var source := original.get_source(original.get_source_id(i)) as TileSetAtlasSource
		var mapped := _mapped(source.texture) as Texture2D if source != null else null
		if mapped != null and mapped != source.texture:
			if copy == null:
				copy = original.duplicate(true) as TileSet     # (deep: the sources are part of the set, and must not be shared)
			(copy.get_source(copy.get_source_id(i)) as TileSetAtlasSource).texture = mapped
	return copy if copy != null else original
