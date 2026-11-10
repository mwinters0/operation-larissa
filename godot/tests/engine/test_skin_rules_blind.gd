class_name TestSkinRulesBlind
extends GdUnitTestSuite
## Teaches: "skins never change rules or timing" as a guard on the source (the traces of real skins are compared in
## `test_plays_identically.gd` and `test_skins_dont_change_the_game.gd`, which also check what the loaders below may ask the skin for).
## The rules cannot be changed by a skin if they cannot see one: no file of `src/rules/`, no rule or data class of `src/core/` and no
## problem model may name a skin, its render settings or its HUD words. `test_rules_are_plain_objects.gd` keeps them free of nodes and
## pictures; this adds the skin classes to what they may not name. (`Assets` and `Catalog` are the loaders that ask the skin, so they
## are the two files of `src/core/` that do.)

const SKIN_WORDS: Array[String] = ["GameSkin", "SkinChoice", "SkinEvents", "RenderSettings", "HudLabels"]
## The loaders of `src/core/`: they turn a name into a resource, which is where the skin is asked.
const LOADERS: Array[String] = ["res://src/core/assets.gd", "res://src/core/catalog.gd"]
## The problem models (the rest of `src/problems/` are views, which may be skinned: see `test_rules_are_plain_objects.gd`).
const PROBLEM_MODELS: Array[String] = [
	"res://src/problems/problem_flow.gd", "res://src/problems/problem_factory.gd", "res://src/problems/problem_session.gd",
	"res://src/problems/problem_instance.gd", "res://src/problems/problem_record.gd", "res://src/problems/answer_checker.gd",
	"res://src/problems/calculator_model.gd", "res://src/problems/lock_program.gd",
]


func test_no_rule_names_a_skin() -> void:
	var files: Array[String] = []
	files.append_array(SourceScan.scripts_under("res://src/rules"))
	for path in SourceScan.scripts_under("res://src/core"):
		if not LOADERS.has(path):
			files.append(path)
	files.append_array(PROBLEM_MODELS)
	assert_int(files.size()).is_greater(30)
	var found := SourceScan.find_in(files, SKIN_WORDS)
	assert_array(found).override_failure_message("the rules name a skin:\n" + "\n".join(found)).is_empty()


func test_the_loaders_are_the_one_place_the_core_asks_the_skin() -> void:
	assert_array(SourceScan.find_in(LOADERS, ["SkinChoice"])).is_not_empty()
