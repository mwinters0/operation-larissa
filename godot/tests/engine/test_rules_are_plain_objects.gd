class_name TestRulesArePlainObjects
extends GdUnitTestSuite
## Teaches: a guard that keeps a design true. The rules of the game - the sector's `SimWorld` and its models, the flow
## of a mission, the problem models, the core data classes - are plain objects. They name no node, no picture, no font, no `Input`
## and no autoload, so they can run with no scene at all (`test_headless_sectors.gd` does), under any presenter
## (`test_plays_identically.gd`) and, one day, in a server or a level checker.
##
## The test READS THE SOURCE (`SourceScan`: comments and strings do not count, a word is a hit only when it stands alone) and fails
## with file:line and the word. Its other half is the sort of every file: a file in `src/rules/` or `src/core/` is guarded unless
## it is on the exclusion list WITH A REASON, and every file of `src/problems/` is a rule, a view or on the exclusion list, so a
## new file cannot slip in unclassified. An exclusion that is not needed any more fails, so the list can only shrink.

## What the rules may not name: the nodes (and the classes a scene is made of), the things a node draws with, the keyboard, the
## tree, the tweens and timers, the engine's machine, and the autoloads (which are nodes in the tree).
const FORBIDDEN: Array[String] = [
	"Node", "Node2D", "Node3D", "Control", "CanvasLayer", "CanvasItem", "Sprite2D", "AnimatedSprite2D", "Window", "Viewport", "SceneTree",
	"Texture2D", "Texture", "Font", "FontFile", "TileMapLayer", "TileMap", "Input", "InputEvent",
	"Tween", "Timer", "AnimationPlayer", "get_tree", "Engine", "OS",
	"GameState", "GameClock", "Audio", "AudioService", "SaveStore", "SceneRouter",
]

## The classes a rules file may extend. (Nothing after `class_name` means a `RefCounted`.)
const PLAIN_BASES: Array[String] = ["RefCounted", "Resource", "Object"]

## Whole folders of rules. `src/core/` is the data and rules every layer shares; its loaders are on `EXCLUDED`.
const RULE_FOLDERS: Array[String] = ["res://src/rules", "res://src/core"]

## Single rules files outside those folders: the message line (the flow posts to it; its clock is anything that ticks, see
## `MessageQueue._init`) and the problem models. `src/problems/` mixes models and views (the screens, the calculator, the diagrams are
## Controls), so the models are named one by one; `ProblemFlow` is the step machine of a problem screen.
const RULE_FILES: Array[String] = [
	"res://src/ui/message_queue.gd",
	"res://src/problems/problem_flow.gd",
	"res://src/problems/problem_factory.gd",
	"res://src/problems/problem_session.gd",
	"res://src/problems/problem_instance.gd",
	"res://src/problems/problem_record.gd",
	"res://src/problems/problem_texts.gd",
	"res://src/problems/text_template.gd",
	"res://src/problems/correct_phrase.gd",
	"res://src/problems/answer_checker.gd",
	"res://src/problems/calculator_model.gd",
	"res://src/problems/lock_program.gd",
	"res://src/problems/lock_wheel.gd",
	"res://src/problems/diagrams/diagram_step.gd",
	"res://src/problems/diagrams/diagram_timeline.gd",
]

## Files that sit in the folders above (or among the problem models) and still name what the rules may not, each with the reason.
## They are LOADERS or the draw lists of a view: they turn a name into a picture, which is the one job that needs a texture.
const EXCLUDED: Dictionary = {
	"res://src/core/assets.gd": "the loader that turns the NAME of a picture into a Texture2D; the rules only hold names, a presenter calls it",
	"res://src/core/pack.gd": "reads one pack's files; its `texture` turns a PNG of the pack into a Texture2D (a loader like `Assets`, called by the lookups)",
	"res://src/core/packs.gd": "the mounted packs and their lookups; `picture` answers a Texture2D to `Assets` / `GameSkin`, which are the views' side",
	"res://src/core/resource_json.gd": "reads a Resource from JSON; a `Texture2D` field (`Campaign.banner`) is a picture file of the pack",
	"res://src/core/window_focus.gd": "the test runner's switch for the window's focus, read by the audio and clock autoloads; it asks the engine's main loop which script runs",
	"res://src/problems/prompt_sender.gd": "the sender picture of a prompt: its rule is static, but `texture` loads the picture; only the problem screen calls that",
	"res://src/problems/problem_runner.gd": "puts a problem screen on a host NODE and waits for it: a helper of the views, not a rule",
	"res://src/problems/diagrams/diagram_item.gd": "one entry of a diagram's DRAW LIST: it holds the Texture2D the view paints (the problem models only hold picture numbers)",
	"res://src/problems/diagrams/diagram_factory.gd": "builds the diagram CONTROL of a problem type",
}

## Bases of the files in `src/problems/` that are views (the rest must be in `RULE_FILES` or `EXCLUDED`).
const VIEW_BASES: Array[String] = ["Control", "Node", "DiagramBase"]


func test_the_rules_name_no_node_picture_font_input_or_autoload() -> void:
	var found := SourceScan.find_in(_rule_files(), FORBIDDEN)
	assert_array(found).override_failure_message("the rules name what a view is made of:\n" + "\n".join(found)).is_empty()


func test_the_rules_extend_a_plain_object_never_a_node() -> void:
	var found: Array[String] = []
	var rule_classes := _class_names(_rule_files())
	for path in _rule_files():
		var base := _base_of(path)
		if not (PLAIN_BASES.has(base) or rule_classes.has(base)):
			found.append("%s extends %s" % [path, base])
	assert_array(found).override_failure_message("a rules file is not a plain object:\n" + "\n".join(found)).is_empty()


func test_the_rules_use_no_class_that_is_a_node() -> void:
	# A rules file may not name a script class that is made of nodes either (a view hidden behind its class_name), even though the
	# word itself is not on `FORBIDDEN`. Found by walking the `extends` chain of every class_name of the project.
	var node_classes := _node_class_names()
	assert_bool(node_classes.has("SectorWorld") and node_classes.has("OriginalPresenter") and node_classes.has("Game")).is_true()
	var found := SourceScan.find_in(_rule_files(), node_classes, false)
	assert_array(found).override_failure_message("the rules name a class that is a node:\n" + "\n".join(found)).is_empty()


func test_every_file_of_the_problems_folder_is_a_rule_a_view_or_excluded_with_a_reason() -> void:
	var unclassified: Array[String] = []
	for path in SourceScan.scripts_under("res://src/problems"):
		if RULE_FILES.has(path) or EXCLUDED.has(path):
			continue
		if not VIEW_BASES.has(_base_of(path)):
			unclassified.append("%s extends %s" % [path, _base_of(path)])
	assert_array(unclassified).override_failure_message(
			"put these in RULE_FILES (plain models) or EXCLUDED (with a reason):\n" + "\n".join(unclassified)).is_empty()


func test_every_exclusion_is_still_needed_and_every_listed_file_exists() -> void:
	var problems: Array[String] = []
	for path: String in EXCLUDED:
		assert_str(str(EXCLUDED[path])).is_not_empty()
		if not FileAccess.file_exists(path):
			problems.append("%s is gone: remove the exclusion" % path)
		elif SourceScan.find(path, FORBIDDEN + _node_class_names(), false).is_empty():
			problems.append("%s names nothing forbidden any more: remove the exclusion" % path)
	for path in RULE_FILES:
		if not FileAccess.file_exists(path):
			problems.append("%s is listed as a rules file but is gone" % path)
	assert_array(problems).is_empty()


func test_the_guarded_set_holds_the_rules() -> void:
	# a few files that must be in it, so the folders cannot be emptied by a typo
	var files := _rule_files()
	for path in ["res://src/rules/sim_world.gd", "res://src/rules/game_flow.gd", "res://src/rules/station_sequence.gd", "res://src/core/foe_vm.gd",
			"res://src/core/tile_grid.gd", "res://src/ui/message_queue.gd", "res://src/problems/problem_flow.gd"]:
		assert_bool(files.has(path)).override_failure_message(path + " is not guarded").is_true()
	assert_bool(files.has("res://src/core/assets.gd")).is_false()
	assert_int(files.size()).is_greater(45)


# --- helpers ------------------------------------------------------------------------------------------

## Every guarded file, sorted: the folders without the exclusions, then the single files.
func _rule_files() -> Array[String]:
	var files: Array[String] = []
	for folder in RULE_FOLDERS:
		for path in SourceScan.scripts_under(folder):
			if not EXCLUDED.has(path):
				files.append(path)
	files.append_array(RULE_FILES)
	files.sort()
	return files


## The word after `extends` in the first line of code that has one ("RefCounted" when there is none).
func _base_of(path: String) -> String:
	for code in SourceScan.code_lines_of(path):
		if code.begins_with("extends "):
			return code.trim_prefix("extends ").strip_edges()
	return "RefCounted"


## The `class_name` of each file (those that have one).
func _class_names(paths: Array[String]) -> Array[String]:
	var names: Array[String] = []
	for entry in ProjectSettings.get_global_class_list():
		if paths.has(str(entry["path"])):
			names.append(str(entry["class"]))
	return names


## Every script class of the project whose chain of `extends` ends in a Node class (Control, Node2D, ...).
func _node_class_names() -> Array[String]:
	var base_of := {}
	for entry in ProjectSettings.get_global_class_list():
		base_of[str(entry["class"])] = str(entry["base"])
	var names: Array[String] = []
	for script_class: String in base_of:
		var base: String = base_of[script_class]
		while base_of.has(base):
			base = base_of[base]
		if ClassDB.class_exists(base) and ClassDB.is_parent_class(base, "Node"):
			names.append(script_class)
	names.sort()
	return names
