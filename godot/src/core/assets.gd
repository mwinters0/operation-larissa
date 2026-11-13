class_name Assets
extends RefCounted
## Turns the NAME of a picture into the picture: the one place that knows where the pictures of a complete pack live.
##
## The rest of the game says what it means (`Assets.ui_picture(&"title_sky")`), never which number or file that is. A name
## is looked up in the NameRegistry (names/original.json) to find the original's number, and the number is turned into a
## path by ONE function per kind (`ui_picture_path`, `problem_art_path`). That is the whole contract: a later renaming of the
## files changes these two functions and the importer, not the scenes. The file of a NAMED picture is
## `<name>_<number>.png` (`radar_map_1000.png`), one nobody named keeps `ui_1000.png` / `pa_1780.png` (`file_stem`; the importer's twin
## is tools/import/asset_names.py).
##
## THE PACKS. A picture is found by its KEY, through the chain's picture tables (`Pictures`: `pictures.json` of each pack, the top first); the number-to-path functions below are what a pack with no table is still read by
## (BRIDGE: they go when every pack has a table). A `ui_picture` name that only a pack has is found by `ui_picture` itself.
##
## NO SKIN. A skin maps no picture: the pictures are the packs' (`Pictures`). A picture a data file still holds by its file (BRIDGE) is fetched with `texture_at(path)`, which asks the packs laid over another whether they redraw that file's key and loads the file only
## if none does.
##
## Teaches: a resolver as a seam. Code that needs a picture holds a name, a small static class owns "name -> number -> file ->
## the skin's texture", and a name that means nothing is a loud error with a suggestion instead of a missing texture.
##
## Kinds of this class and who resolves the others: `ui_picture` and `problem_art` here; `sound` is `SfxCatalog.stream_named`,
## `music` is `MusicCatalog.stream_named`, `voice` is `VoiceIndex.stream_named`, `text` is `Catalog.text`, and the creature
## and decoration pictures are slots of the SpriteFrames sets (`NameRegistry.index_of(&"frame", name, zone)`).
##
## A few pictures are chosen by DATA that holds the original's numbers (the closing crew's programs, `ClosingCrewScripts`; the
## cutscene timelines hold NAMES instead). For those `ui_picture_by_number` exists; code never writes a number itself (tests/engine/test_no_asset_numbers.gd checks that).

## The folders of `assets/ui/`, for the ids that are not in the default one ("story"). The rule is the importer's
## (tools/import/pictures.py: `UI_FOLDERS`); tests/engine/test_assets.gd checks that every picture file is found where it is.
const UI_FOLDER_RANGES := {
	"map": [[1000, 1000]],
	"title": [[1039, 1057], [2041, 2045]],
	"hud": [[1189, 1213]],
	"prompt": [[2412, 2413]],
}
const DEFAULT_UI_FOLDER := "story"
## Where the pictures are in a pack (`Packs.path` turns these into the file of the first pack of the chain that has it).
const UI_REL := "assets/ui/%s/%s.png"
const PROBLEM_ART_REL := "assets/problem_art/%s/%s.png"
## The picture behind one screen of a sector (`bg_s03_07`: sector 3, screen 7), made by the importer; not a registry kind.
const BACKGROUND_REL := "assets/backgrounds/bg_s%02d_%02d.png"
## Which folder (`b116`, `single` ...) of `assets/problem_art/` holds each picture: written by the importer.
const PROBLEM_ART_INDEX_REL := "data/problems/problem_art_index.json"

## picture number -> folder of the problem art; read from `PROBLEM_ART_INDEX_REL` the first time it is needed.
static var _problem_art_folders: Dictionary = {}
## key -> file of the chain's pictures, built by `key_files`.
static var _key_files: Dictionary = {}
static var _key_files_made := false
## BRIDGE: pack id -> the same for one pack (`pack_key_files`).
static var _pack_key_files: Dictionary = {}


# --- the interface, story and console pictures (`ui_picture`) ------------------------------------------------

## The texture of the picture `picture_name` (a `ui_picture` name), or null when there is no such name or file.
static func ui_picture(picture_name: StringName) -> Texture2D:
	var held := picture_by_key("ui_picture/" + picture_name)
	if held != null:
		return held
	return _texture(ui_picture_path(number_of(&"ui_picture", picture_name)))       # BRIDGE: a made-up name (`ui_1039`) and the pack with no table


## The texture of picture `number`, for numbers a data file holds (`ClosingCrewScripts`).
static func ui_picture_by_number(number: int) -> Texture2D:
	return _texture(ui_picture_path(number))


## "res://packs/legacy/assets/ui/title/title_sky_1039.png": where the picture with the original's number `number` is.
static func ui_picture_path(number: int) -> String:
	return Packs.path(ui_picture_rel(number)) if number >= 0 else ""


## "assets/ui/title/title_sky_1039.png": the file of the picture with the original's number `number` as a pack keeps it (the `rel` of `Packs.path`), or "".
static func ui_picture_rel(number: int) -> String:
	if number < 0:
		return ""
	return UI_REL % [_ui_folder(number), file_stem(&"ui_picture", number)]


static func _ui_folder(number: int) -> String:
	for folder: String in UI_FOLDER_RANGES:
		for span: Array in UI_FOLDER_RANGES[folder]:
			if number >= span[0] and number <= span[1]:
				return folder
	return DEFAULT_UI_FOLDER


# --- the pictures of the math problems (`problem_art`) -----------------------------------------------------------

## The texture of the problem-art picture `picture_name`, or null.
static func problem_art(picture_name: StringName) -> Texture2D:
	var held := picture_by_key("problem_art/" + picture_name)
	if held != null:
		return held
	return _texture(problem_art_path(number_of(&"problem_art", picture_name)))     # BRIDGE: a made-up name (`pa_1780`) and the pack with no table


## "res://packs/legacy/assets/problem_art/b116/log_scan_0_2046.png", or "" when no folder holds the number.
static func problem_art_path(number: int) -> String:
	var rel := problem_art_rel(number)
	return Packs.path(rel) if not rel.is_empty() else ""


## "assets/problem_art/b116/log_scan_0_2046.png": the file of the problem-art picture `number` as a pack keeps it, or "" when no folder holds the number.
static func problem_art_rel(number: int) -> String:
	if _problem_art_folders.is_empty():
		var held := Packs.holder(PROBLEM_ART_INDEX_REL)
		var index: Variant = held.read_json(PROBLEM_ART_INDEX_REL) if held != null else null
		if index is Dictionary:
			for folder: String in index:
				for id: float in index[folder]:                       # (a JSON file holds its numbers as floats)
					_problem_art_folders[int(id)] = folder
	if not _problem_art_folders.has(number):
		return ""
	return PROBLEM_ART_REL % [_problem_art_folders[number], file_stem(&"problem_art", number)]


# --- the backgrounds of the screens ------------------------------------------------------------------------

## The picture behind screen `screen` of sector `sector`, or null when the screen has none (two of the finale's are plain black).
static func background(sector: int, screen: int) -> Texture2D:
	return picture_by_key(_background_key(sector, screen))


## Has screen `screen` of sector `sector` a picture behind it (a picture of the chain for its key)?
static func has_background(sector: int, screen: int) -> bool:
	return picture_by_key(_background_key(sector, screen)) != null


## The key of that picture (`background/bg_s03_07`), or "" when the screen has none.
static func background_key(sector: int, screen: int) -> String:
	return _background_key(sector, screen) if has_background(sector, screen) else ""


static func _background_key(sector: int, screen: int) -> String:
	return "background/bg_s%02d_%02d" % [sector, screen]


## "res://packs/legacy/assets/backgrounds/bg_s03_07.png": where the picture behind screen `screen` of sector `sector` is (or would be).
static func background_path(sector: int, screen: int) -> String:
	return Packs.path(BACKGROUND_REL % [sector, screen])


## Forget what was read from the chain's files (`Catalog.packs_changed`: another pack is in use).
static func forget_folders() -> void:
	Pictures.forget()
	PathPictures.forget()
	_problem_art_folders = {}
	_key_files = {}
	_key_files_made = false
	_pack_key_files = {}


# --- a picture by its skin key ------------------------------------------------------------------------------------

## The picture of the skin key `key` (`frame/sub_00`, `background/bg_s03_07`, `deco/coral_fan_cyan`): what the chain's picture tables say (`Pictures.resolve`); null for a key no pack holds. What a mod's draw list names is
## resolved here (`ModDraw`), so a mod sees what `OriginalPresenter` would show, and holds no picture itself.
static func picture_by_key(key: String) -> Texture2D:
	return Pictures.resolve(key)


## BRIDGE: the picture files of the packs with no table by their skin key: key -> the file as a pack keeps it (`assets/sprites/sub/sub_00.png`), the first pack of the chain having the last word. Made once for the chain in use (`forget_folders`).
static func key_files() -> Dictionary:
	if not _key_files_made:
		var made := {}
		for each in Packs.chain():                        # (the top of the chain first: the file of a key the first pack has is the one `Packs.path` finds)
			var own := pack_key_files(each)
			for key: String in own:
				if not made.has(key):
					made[key] = own[key]
		_key_files = made
		_key_files_made = true
	return _key_files


## BRIDGE: the same for one pack (`{}` for a pack with a table: it names its pictures there, not by its files' names).
static func pack_key_files(pack: Pack) -> Dictionary:
	if pack.picture_table().present:
		return {}
	if not _pack_key_files.has(pack.id):
		var made := {}
		for rel in pack.all_files():
			if rel.get_extension() == "png" and rel.begins_with("assets/"):
				var key := GameSkin.key_of_rel(rel)
				if not key.is_empty() and not made.has(key):
					made[key] = rel
		_pack_key_files[pack.id] = made
	return _pack_key_files[pack.id]


# --- shared -------------------------------------------------------------------------------------------------------

## BRIDGE: the texture of the picture file `path`: what the packs laid over another say for its key (`Pictures.overlaid`), or the file. For the pictures that DATA names by path
## (`ProblemType.art_files`); the rest of the game says a picture's key instead. "" gives null.
static func texture_at(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var mapped := Pictures.overlaid(GameSkin.key_of(path))
	return mapped if mapped != null else Packs.file_at(path) as Texture2D


## The file name (without extension) of picture `number` of `kind`: `<name>_<number>` when somebody named it, else the made-up
## name, which already holds the number (`ui_1039`, `pa_1780`). The rule of tools/import/asset_names.py `stem`.
static func file_stem(kind: StringName, number: int) -> String:
	var registry := NameRegistry.original()
	if registry.is_named(kind, number):
		return "%s_%d" % [registry.name_of(kind, number), number]
	return registry.name_of(kind, number)


## The original's number of the name `picture_name` of `kind`, or -1 (and an error that says what was meant).
static func number_of(kind: StringName, picture_name: StringName) -> int:
	var registry := NameRegistry.original()
	var number := registry.index_of(kind, String(picture_name))
	if number < 0:
		push_error("Assets: " + registry.explain_unknown(kind, String(picture_name)))
	return number


static func _texture(path: String) -> Texture2D:
	return texture_at(path)
