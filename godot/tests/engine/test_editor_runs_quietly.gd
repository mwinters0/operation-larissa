class_name TestEditorRunsQuietly
extends GdUnitTestSuite
## Teaches: what a plugin may and may not assume inside the editor, so that opening the project, importing it and exporting it print no error. Two facts of the
## editor shape the tests. (1) A script that is not `@tool` is a PLACEHOLDER there: a resource whose script is such a class (a `GameSkin`, a `VoiceCues`) holds its
## exported values, but calling a method on it is a script error. A plugin starts `Packs`, and `Packs` runs the start-up check (`PackNeeds`) on the chain, so that check
## may ask no skin and may call only methods of `@tool` scripts. (2) The editor throws away every saver that has a script right after it announces new script classes
## (`EditorFileSystem::_update_script_classes`), so a plugin that registered savers must know it holds none from the announcement on, or it removes savers that are not there
## when it leaves (`ResourceSaver::remove_resource_format_saver` complains). An `EditorPlugin` can not be made outside the editor, so the last test starts a real editor
## process on this project and reads what it printed.

const PROBE_DIR := "res://tests/engine/zz_quiet_probe"
const PROBE_SCRIPT := PROBE_DIR + "/zz_quiet_probe.gd"
const QUIET_LINES := ["SCRIPT ERROR", "ERROR:", "Parse Error", "Compile Error"]


func after_test() -> void:
	PackFiles.remove_tree(PROBE_DIR)


## The start-up check reads the problem types, the campaigns' finale pictures and the speech groups; none of that may go through the skin in use (it would be selected,
## its render settings put on the window, and in the editor it is a placeholder).
func test_the_pack_check_asks_no_skin() -> void:
	var real_skin := SkinChoice._current
	var asked: Array[int] = [0]
	var count := func(_skin: GameSkin) -> void: asked[0] += 1
	SkinChoice._current = null
	SkinChoice.events.changed.connect(count)
	var gaps := PackNeeds.gaps(Packs.chain())
	SkinChoice.events.changed.disconnect(count)
	var selected := SkinChoice._current
	SkinChoice._current = real_skin
	assert_int(gaps.size()).override_failure_message("the dev pack lacks something: %s" % PackNeeds.summary(gaps)).is_equal(0)
	assert_object(selected).override_failure_message("the pack check selected a skin").is_null()
	assert_int(asked[0]).is_equal(0)


func test_the_unskinned_problem_type_is_the_type_the_skin_starts_from() -> void:
	for index in [0, 3, Catalog.PROBLEM_TYPE_COUNT - 1]:
		var plain := Catalog.problem_type_unskinned(index)
		assert_object(plain).is_not_null()
		assert_str(Catalog.problem_type(index).title).is_equal(plain.title)
		assert_array(Catalog.problem_type(index).art_files).is_equal(plain.art_files)


## Every resource script whose methods the start-up check calls is a tool script (a placeholder in the editor refuses the call).
func test_the_data_scripts_the_pack_check_calls_are_tool_scripts() -> void:
	for path in ["res://src/resources/voice_cues.gd", "res://src/resources/campaign.gd", "res://src/resources/problem_type.gd"]:
		assert_bool((load(path) as GDScript).is_tool()).override_failure_message(path + " is not @tool").is_true()


## Exports the game in an editor process (`--export-pack` needs no templates): that runs every plugin's `_enter_tree` and `_exit_tree` and the first scan, and the
## process ends when the export does, with whatever the editor had not yet done. Nothing it prints is an error. A script with a new `class_name` is in the project while it
## runs, so the editor announces new script classes (and drops the screen editor's savers) in that process as it does whenever a script changes; the plugin then leaves with
## the savers already gone.
func test_an_export_runs_the_editor_and_prints_no_errors() -> void:
	DirAccess.make_dir_recursive_absolute(PROBE_DIR)
	var file := FileAccess.open(PROBE_SCRIPT, FileAccess.WRITE)
	file.store_string("class_name ZzQuietProbe\nextends RefCounted\n")
	file.close()
	var output: Array = []
	var archive := ProjectSettings.globalize_path(PROBE_DIR + "/game.pck")
	var arguments := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--export-pack", "Linux", archive])
	var code := OS.execute(OS.get_executable_path(), arguments, output, true)
	var text := "\n".join(PackedStringArray(output))
	var bad: Array[String] = []
	for line in text.split("\n"):
		if QUIET_LINES.any(func(marker: String) -> bool: return line.contains(marker)):
			bad.append(line)
	assert_int(code).is_equal(0)
	assert_array(bad).override_failure_message("the editor printed errors:\n" + "\n".join(bad)).is_empty()
