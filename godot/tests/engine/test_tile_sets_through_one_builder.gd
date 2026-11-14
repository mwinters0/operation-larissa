class_name TestTileSetsThroughOneBuilder
extends GdUnitTestSuite
## Teaches: a rule kept by a test that reads the source. A `TileMapLayer` hands the renderer the RID of its tile set's atlas texture, which a picture of a scale above 1 (`ScaledTexture`) does not have, so a pack's tile set is put on a layer by ONE builder, `ScaledTileSet.dress`
## (the presenter, the screen editor and every debug scene use it). This suite reads the scripts and scenes of `src/`, `addons/` and `skins/` and fails on code that assigns a tile set to a layer another way. A tool that shows tiles calls `ScaledTileSet.dress`.

const ALLOWED := {
	"res://src/skins/scaled_tile_set.gd": "the builder itself",
}
## Not scanned: other people's code.
const SKIPPED := ["res://addons/gdUnit4/", "res://addons/godot_ai/", "res://addons/godot_sandbox/", "res://addons/midi/"]

## `layer.tile_set = x`, `tile_set = x` at the start of a line (a layer's own script), `set("tile_set", x)`, and a scene's `tile_set = ExtResource(...)`.
var _assignment := RegEx.create_from_string("\\.tile_set\\s*=(?!=)|^\\s*tile_set\\s*=(?!=)|\\bset(_deferred)?\\s*\\(\\s*[\"']tile_set[\"']")


func _files() -> Array[String]:
	var found: Array[String] = []
	for folder in ["res://src", "res://addons", "res://skins"]:
		for path in _files_under(folder):
			if not SKIPPED.any(func(skipped: String) -> bool: return path.begins_with(skipped)) and not ALLOWED.has(path):
				found.append(path)
	return found


func _files_under(folder: String) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(folder):
		if file.get_extension() in ["gd", "tscn"]:
			found.append(folder.path_join(file))
	for sub in DirAccess.get_directories_at(folder):
		found.append_array(_files_under(folder.path_join(sub)))
	return found


func _hits(path: String) -> Array[String]:
	var found: Array[String] = []
	var lines := SourceScan.code_lines_of(path) if path.ends_with(".gd") else FileAccess.get_file_as_string(path).split("\n")
	var raw := FileAccess.get_file_as_string(path).split("\n")
	for i in lines.size():
		var code := lines[i] if not lines[i].contains("\"\"") else raw[i]                  # (a string is blanked in `code_lines`, and `set("tile_set", ...)` is a string)
		if _assignment.search(code) != null and not raw[i].strip_edges().begins_with("#"):
			found.append("%s:%d  %s" % [path, i + 1, raw[i].strip_edges()])
	return found


func test_no_layer_is_given_a_tile_set_but_by_the_builder() -> void:
	var stray: Array[String] = []
	for path in _files():
		stray.append_array(_hits(path))
	assert_array(stray).override_failure_message("a tile set put on a layer outside `ScaledTileSet.dress`:\n" + "\n".join(stray)).is_empty()


func test_the_scan_sees_each_way_of_assigning_a_tile_set() -> void:
	for line in ["layer.tile_set = tile_set", "\ttile_set = made", "layer.set(\"tile_set\", made)", "tile_set = ExtResource(\"2_abc\")"]:
		assert_object(_assignment.search(line)).override_failure_message(line).is_not_null()
	for line in ["if layer.tile_set == made:", "var tile_set := Catalog.tileset()", "func of(tile_set: TileSet, scale: int) -> TileSet:", "var made := layer.tile_set"]:
		assert_object(_assignment.search(line)).override_failure_message(line).is_null()


func test_the_list_names_scripts_that_exist() -> void:
	for entry: String in ALLOWED:
		assert_bool(FileAccess.file_exists(entry)).override_failure_message(entry).is_true()
		assert_str(ALLOWED[entry]).is_not_empty()
