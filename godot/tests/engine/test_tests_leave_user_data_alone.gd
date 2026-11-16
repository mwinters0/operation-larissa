class_name TestTestsLeaveUserDataAlone
extends GdUnitTestSuite
## Teaches: a rule kept by a test that reads the source. A test never writes the player's own data: the installed packs and the pack remembered for the next start are the player's, and a
## machine with a pack installed must pass the suite without losing it. The code reaches them through one owner each (`Packs.installed_dir`, `PackChoice.memory_path`) and a test points
## the owner at a scratch place (`Scratch.isolate_user_data`), so no script under `tests/` names either place itself. This suite reads every script under `tests/` and fails on a line that does.
## It looks at the text of the line, comments included, so the words of a header cannot name them either; it cannot see a path built from pieces.
## And a test leaves nothing in `user://` (rules of an engine test, `docs/engine/DEVELOPING.md`): every path of its own is a `Scratch` place, so a script that has a `user://` path in a string of
## its code is told, unless the path is one of `MAY_NAME` (a place that is only asked about, never made, or that the game or a human keeps). It reads strings of code, not comments, and a path built from pieces escapes it.

## The two places a test must not name, split here so that this file does not name them itself.
const PLACES: Array[String] = ["user://" + "packs", "user://" + "pack_choice"]
## The `user://` paths a test may have in a string (a path begins with one of these): what is never made (a path to fail on, a name to parse, an argument built and compared), the root of `Scratch` itself, the pictures the render tests leave for a human to look at, and the cache of `NEPTUNE_LEGACY_AS_DATA` that `LegacyPack` keeps.
const MAY_NAME: Array[String] = [
	"user://test_scratch", "user://legacy_as_data", "user://snapshots/",
	"user://no_such", "user://nowhere",
	"user://sector_40.tres", "user://notes.foe", "user://a.tres", "user://a.res", "user://roster.json", "user://pack_exports",
]
## Not scanned: this file.
const SKIPPED := ["res://tests/engine/test_tests_leave_user_data_alone.gd"]


func _strays() -> Array[String]:
	var stray: Array[String] = []
	for path in SourceScan.scripts_under("res://tests"):
		if SKIPPED.has(path):
			continue
		var number := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			number += 1
			if PLACES.any(func(place: String) -> bool: return line.contains(place)):
				stray.append("%s:%d  %s" % [path, number, line.strip_edges()])
	return stray


## The `user://` paths in the strings of the code of a script: `file:line  path` of each that is not one of `MAY_NAME`.
func _paths_outside_scratch() -> Array[String]:
	var found: Array[String] = []
	var path_in_text := RegEx.create_from_string("user://[A-Za-z0-9_./%-]*")
	for path in SourceScan.scripts_under("res://tests"):
		if SKIPPED.has(path):
			continue
		var number := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			number += 1
			if line.strip_edges().begins_with("#"):
				continue
			for hit in path_in_text.search_all(line):
				var inside_a_string := line.substr(0, hit.get_start()).count("\"") % 2 == 1
				var text := hit.get_string()
				if inside_a_string and not MAY_NAME.any(func(allowed: String) -> bool: return text.begins_with(allowed)):
					found.append("%s:%d  %s" % [path, number, text])
	return found


func test_no_test_names_the_installed_packs_folder_or_the_remembered_choice() -> void:
	var stray := _strays()
	assert_array(stray).override_failure_message("a test names a place of the player's own data (read Packs.installed_dir / PackChoice.memory_path and isolate them with Scratch.isolate_user_data):\n" + "\n".join(stray)).is_empty()


func test_the_scan_sees_the_tests_and_the_places_are_where_the_code_owns_them() -> void:
	assert_int(SourceScan.scripts_under("res://tests").size()).is_greater(100)
	assert_str(Packs.DEFAULT_INSTALLED_DIR).is_equal(PLACES[0])
	assert_str(PackChoice.memory_path).starts_with(PLACES[1])


func test_no_test_makes_a_place_of_its_own_in_user() -> void:
	var found := _paths_outside_scratch()
	assert_array(found).override_failure_message("a test has a path in `user://` of its own (make it with Scratch.folder / Scratch.path, and delete it in after_test):\n" + "\n".join(found)).is_empty()


func test_the_paths_a_test_may_name_are_still_named_by_some_test() -> void:
	var named := {}
	for path in SourceScan.scripts_under("res://tests"):
		if not SKIPPED.has(path):
			for allowed in MAY_NAME:
				if FileAccess.get_file_as_string(path).contains(allowed):
					named[allowed] = true
	var unused: Array = MAY_NAME.filter(func(allowed: String) -> bool: return not named.has(allowed))
	assert_array(unused).override_failure_message("these are in MAY_NAME and no test names them any more (delete them from the list): %s" % [unused]).is_empty()
