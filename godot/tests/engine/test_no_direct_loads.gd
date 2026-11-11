class_name TestNoDirectLoads
extends GdUnitTestSuite
## Teaches: a rule kept by a test that reads the source. A file of a pack becomes an object in ONE place, the door (`Pack.resource` / `texture` / `stream`, reached
## through `Packs.resource` / `texture` / `stream` / `file_at`): a trusted pack's `.tres` is loaded there and any other pack's data form is read there, so
## nothing a stranger's pack holds can reach `ResourceLoader`. This suite reads every script of `src/` and `addons/` and fails on a `load(` or
## `ResourceLoader.load(` that is not in the short list below, and on any `load(` of a pack path (`Packs.path`, `path_of`) anywhere.
## A new direct load is either routed through the door or added to the list with the reason it is not a pack's file.

## script (a path under res://, or a folder with a trailing slash) -> why a `load(` there is not a load of a pack's file.
const ALLOWED := {
	"res://src/core/pack.gd": "the door itself: a trusted pack's own files",
	"res://src/core/packs.gd": "`file_at`: a path of the project (`res://data/...`) outside every pack",
	"res://src/core/resource_json.gd": "the game's own class scripts, by `class_name`",
	"res://src/core/catalog.gd": "`_load`: the project's own data and the authoring `.tres` of sectors and campaigns that the editors write",
	"res://src/resources/foe_data.gd": "the authoring `.tres` of the sector a creature belongs to (the editors)",
	"res://src/checks/check_sector.gd": "a sector `.tres` the tool is given by path (authoring file)",
	"res://src/checks/sector_changes.gd": "the constants of the project's own test scripts",
	"res://src/gameplay/presenter_choice.gd": "the presenter scene, project code",
	"res://src/skins/": "skins are scenes and scripts of the project (`res://skins/`), code by design",
	"res://src/debug/skin_compare.gd": "a skin by path (`res://skins/`)",
	"res://addons/screen_editor/": "an editor of the project's authoring files: sectors and screens `.tres`, its own scene",
	"res://addons/sector_editor/": "an editor of the project's authoring files: sector `.tres`",
	"res://addons/foe_script_editor/": "an editor of the project's authoring files: sector `.tres` and creature scripts",
	"res://addons/sector_checks/": "a check of a sector `.tres` given by path (authoring file)",
	"res://addons/sector_overview/": "its own scene",
}
## Not scanned: other people's code, and the folders that hold no game code.
const SKIPPED := ["res://addons/gdUnit4/", "res://addons/godot_ai/", "res://addons/midi/"]

var _load_call := RegEx.create_from_string("(?<![\\w.])load\\s*\\(|ResourceLoader\\.load\\s*\\(")
var _pack_path := RegEx.create_from_string("Packs\\.path\\s*\\(|\\.path_of\\s*\\(|Assets\\.\\w*path\\w*\\s*\\(")


func _scripts() -> Array[String]:
	var found: Array[String] = []
	for folder in ["res://src", "res://addons"]:
		for path in SourceScan.scripts_under(folder):
			if not SKIPPED.any(func(skipped: String) -> bool: return path.begins_with(skipped)):
				found.append(path)
	return found


func _allowed(path: String) -> bool:
	return ALLOWED.keys().any(func(entry: String) -> bool: return path == entry or (entry.ends_with("/") and path.begins_with(entry)))


func test_every_load_is_in_the_door_or_is_not_a_packs_file() -> void:
	var stray: Array[String] = []
	for path in _scripts():
		if _allowed(path):
			continue
		var number := 0
		for code in SourceScan.code_lines_of(path):
			number += 1
			if _load_call.search(code) != null:
				stray.append("%s:%d  %s" % [path, number, code.strip_edges()])
	assert_array(stray).override_failure_message("a direct load outside the door (route it through Packs.resource / texture / stream / file_at, or list it with its reason):\n" + "\n".join(stray)).is_empty()


func test_no_load_takes_a_path_of_a_pack_anywhere() -> void:
	var stray: Array[String] = []
	for path in _scripts():
		if path == "res://src/core/pack.gd":
			continue                                                                   # (the door: it loads the trusted pack's own files, and says so)
		var number := 0
		for code in SourceScan.code_lines_of(path):
			number += 1
			if _load_call.search(code) != null and _pack_path.search(code) != null:
				stray.append("%s:%d  %s" % [path, number, code.strip_edges()])
	assert_array(stray).override_failure_message("\n".join(stray)).is_empty()


func test_the_list_names_scripts_that_exist() -> void:
	for entry: String in ALLOWED:
		assert_bool(FileAccess.file_exists(entry) or DirAccess.dir_exists_absolute(entry)).override_failure_message(entry).is_true()
		assert_str(ALLOWED[entry]).is_not_empty()
