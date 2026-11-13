class_name GameSkin
extends Resource
## A skin: what the game looks like, as DATA. It maps the NAMES of the registry (a layout, the presenter) to this skin's own
## resources, and everything it does not map is the original's. The rules and the content know nothing about skins
## (`tests/engine/test_rules_are_plain_objects.gd`); everything that draws asks `Assets` / `Catalog`, which ask the current skin
## (`SkinChoice.current()`), so one skin file is the whole difference between two looks.
##
## A SKIN MAPS NO PICTURE. Which picture a key (`ui_picture/title_sky`, `frame/sub_00`) shows is the PACK layer's choice (`pictures.json` of each pack of the chain, `Pictures`): a skin dresses the game with shaders, fonts, themes, layouts
## and a presenter, never with another picture, so a change of skin changes no picture and a pack that redraws one changes it under every skin.
##
## WHAT A SKIN MAPS
##  * `resources`: a whole LAYOUT instead of the original's, by its path under the data folder (a pack's `res://packs/<id>/data/`, or the project's `res://data/`) without `.tres`:
##    `ui/hud_layout`, `ui/story_layout`, `problems/screen_layout`. For a skin whose HUD or screens are laid out differently (the layouts are data). ONLY layouts can be
##    replaced (`REPLACEABLE`): a key that names rules or content (`zones`, `trigger_table`, `problems/problem_type_07` with
##    its records and answers, `sprite_meta/...` with the hit rectangles, a sector) is ignored, and so is one that names a picture bundle (`sprite_frames/...`, `neptune_tileset`: the pictures are the packs'), so a skin cannot change what the game
##    does by dressing up as a data file; and a layout that holds a picture of its own, a `Texture2D` that is not a `PictureRef`, is ignored too (`refused_resources` lists such keys for the author; `test_skins_dont_change_the_game.gd`, `test_skin.gd`).
##  * `presenter_scene`: the scene that shows a sector (`PresenterChoice.ORIGINAL_SCENE` is the original's); its root extends
##    `SectorPresenter`.
##  * `render`: filter and pixel snapping (`RenderSettings`); `hud_labels`: the HUD's zone / sector / game lettering as text; `menu_theme`: the look of the menus (`SkinTheme`, put on by `ThemeBuilder`).
##  * `layer_materials`: a shader (with its uniforms) on a layer of the original presenter, by the layer's name (`SkinLayers.NODES`). Presentation only: the presenter makes its own copy of the material each time it is built (`layer_material`) and
##    sets the `phase` uniform itself, so a skin holds no state of a run.
## An empty field means "not mine": the lookup goes on to `fallback` (another skin, for a skin that builds on a skin) and ends at the
## original, which maps nothing at all and keeps today's resources and settings.
##
## Teaches: a Resource as a bundle of choices, edited in the Inspector like any other; a Dictionary exported with typed keys and
## values (`Dictionary[String, Resource]`); and an override table with a fallback chain, the same idea as CSS or a theme: the
## specific thing wins, the general thing answers the rest. What a picture IS belongs to the content (the packs' tables), not to the skin.

## The data resources a skin may replace by `resources`, as the start of their key: the layouts. The rest of the data is the rules, the content and the picture bundles
## (the sprite sets and the tile set hold keys, and a pack's picture table says what each key shows), which no skin can replace.
const REPLACEABLE: Array[String] = ["ui/", "problems/screen_layout"]

## The skin's id: the folder name under `res://skins/` and the word of `--skin=<id>`.
@export var id: StringName = &""
## What a menu would show.
@export var display_name: String = ""
## The skin that answers what this one does not map. Empty means the original (the original itself has none).
@export var fallback: GameSkin

@export var resources: Dictionary[String, Resource] = {}
@export var presenter_scene: PackedScene
@export var render: RenderSettings
@export var hud_labels: HudLabels
## The look of the menus (`SkinTheme`: font, colours, panel and button styles), or null: the engine's own theme. `ThemeBuilder` lays it on that theme when the skin is selected (`SkinChoice.select`); no control, rectangle or rule is named in it.
@export var menu_theme: SkinTheme
## A material for a layer of the original presenter: layer name (`SkinLayers.NODES`) -> a `ShaderMaterial` with the shader and the values of its uniforms. Never put on a node as it is: `layer_material` hands out copies.
@export var layer_materials: Dictionary[StringName, ShaderMaterial] = {}

# --- the lookups (each one: this skin, else the next, else the original's) ------------------------------------

## The skin that answers what this one does not: `fallback`, or the original for every skin but the original.
func next_skin() -> GameSkin:
	if fallback != null:
		return fallback
	if id == SkinChoice.ORIGINAL:
		return null
	return SkinChoice.original()


## This skin's data resource for `data_key` (a path under the data folder without `.tres`), or null. Only the keys of `REPLACEABLE` count, and not a resource that holds a picture of its own.
func resource_for(data_key: String) -> Resource:
	if resources.has(data_key) and is_replaceable(data_key) and not holds_a_picture(resources[data_key]):
		return resources[data_key]
	var next := next_skin()
	return next.resource_for(data_key) if next != null else null


## May a skin replace the data resource `data_key`? (`REPLACEABLE`)
static func is_replaceable(data_key: String) -> bool:
	for start in REPLACEABLE:
		if data_key.begins_with(start):
			return true
	return false


## The keys of `resources` that are ignored because they name rules, content or a picture bundle, not a layout, or because the layout holds a picture of its own. An authoring check: it should be empty.
func refused_resources() -> Array[String]:
	var refused: Array[String] = []
	for data_key in resources:
		if not is_replaceable(data_key) or holds_a_picture(resources[data_key]):
			refused.append(data_key)
	return refused


## Does `value` hold a picture of its own: a `Texture2D` that is not a `PictureRef` (a key), itself or in a resource, array or dictionary it holds? A skin maps no picture: the pictures are the packs'
## (`Pictures`), so a layout that carries one is not shown. (A resource is looked into by the properties it stores; each is looked into once.)
static func holds_a_picture(value: Variant, seen: Dictionary = {}) -> bool:
	if value is PictureRef:
		return false
	if value is Texture2D:
		return true
	if value is Resource:
		var resource := value as Resource
		if seen.has(resource):
			return false
		seen[resource] = true
		for property: Dictionary in resource.get_property_list():
			if (int(property["usage"]) & PROPERTY_USAGE_STORAGE) != 0 and property["name"] != "script" and holds_a_picture(resource.get(property["name"]), seen):
				return true
	elif value is Array:
		return (value as Array).any(func(each: Variant) -> bool: return holds_a_picture(each, seen))
	elif value is Dictionary:
		for key: Variant in value:
			if holds_a_picture(key, seen) or holds_a_picture(value[key], seen):
				return true
	return false


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


## The look of the menus this skin asks for, else the skin behind it, or null while every skin leaves the engine's theme (an empty `SkinTheme` says nothing, so it is none too).
func menu_theme_in_use() -> SkinTheme:
	if menu_theme != null and not menu_theme.is_empty():
		return menu_theme
	var next := next_skin()
	return next.menu_theme_in_use() if next != null else null


# --- data resources --------------------------------------------------------------------------------------

## `original` (a resource of the data folders, as `Catalog` loads it) as THIS skin shows it: the skin's own resource for it if it has
## one (`resources`), else `original` itself. A skin changes no picture (the packs' tables do, `Pictures`).
func skinned(original: Resource) -> Resource:
	if original == null:
		return null
	var own := resource_for(_data_key(Packs.source_of(original)))
	return own if own != null else original


## "res://packs/legacy/data/ui/hud_layout.tres" -> "ui/hud_layout" (and "res://data/ui/menu_layout.tres" -> "ui/menu_layout"); "" for a resource that is not a file of
## a pack's `data/` or the project's `res://data/`.
static func _data_key(path: String) -> String:
	var in_a_pack := Packs.relative(path)
	if in_a_pack.begins_with("data/"):
		return in_a_pack.trim_prefix("data/").get_basename()
	if path.begins_with("res://data/"):
		return path.trim_prefix("res://data/").get_basename()
	return ""
