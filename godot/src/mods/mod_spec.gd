class_name ModSpec
extends RefCounted
## The `mod` entry of a pack's manifest: what makes a data pack a mod pack. It names the entry script (SafeGDScript, a `.sgd` file of the pack), the version of the game's mod
## API the script was written for, and the limits it asks to run within. The limits a manifest asks for are clamped to the game's ceilings (`MAX_*`): a manifest can lower a limit, never raise it.
##
##     "mod": {"entry": "orchard.sgd", "requires_api": 1, "limits": {"execution_timeout": 100, "memory_max": 16}}
##     "mod": {"entry": "reef.sgd", "requires_api": 2, "skin": {"shaders": ["skin/glow.gdshader"]}}
##     "mod": {"entry": "tides.sgd", "requires_api": 3, "problems": {"types": [40], "shaders": ["problems/wave.gdshader"]}}
##     "mod": {"entry": "rules.sgd", "requires_api": 4, "rules": {"answers": [41], "instructions": [0, 1], "sub": true}}
##
## `entry` is a plain file name (no folder) ending `.sgd`, in the pack's root. `requires_api` (default 1) is the lowest API version the script needs; a game that provides less
## refuses the pack. `limits` is optional, and so is every key in it. `skin` makes the mod a SKIN (`ModSkin`: the mod draws the sector, `docs/create/SKIN_API.md`); it needs API version 2,
## and lists the shaders the skin may use, text files `skin/<name>.gdshader` of the pack (`ModShader`), at most `MAX_SHADERS`. `problems` makes the mod DRAW the screens of the problem types it lists (`types`, whole numbers from
## `Catalog.PROBLEM_TYPE_COUNT` to `Catalog.LAST_PROBLEM_TYPE`, at most `MAX_PROBLEM_TYPES`; the pack holds each type as data); it needs API version 3 and lists its shaders like a skin, in the pack's `problems/` folder. `rules` makes the mod
## add GAMEPLAY inside the rules (`RuleHooks`), for a campaign that declares the mod: `answers` lists problem types it judges instead of their `compare_mode` (numbers as for `problems.types`, the pack holds each as data),
## `instructions` the numbers 0 to `RuleHooks.MAX_INSTRUCTIONS - 1` of the creature instruction `Mod_Instruction` it defines, `sub` (true) a sub ability; it needs API version 4, at least one of the three, and a mod with `rules`
## runs under an instruction limit of 1 to `MAX_RULE_EXECUTION_TIMEOUT` million per call. The instruction limit of every mod is at least 1: counting is never off. `Pack` reads this entry (`Pack.mod`), `PackCheck` judges what it names,
## `functions` lists what the script must define for it, and `ModLoader` runs the script.
##
## Teaches: validating an untrusted description by naming each rule in one place, and clamping a request to a ceiling instead of refusing it (a limit is a request; the host decides).

## The version of the API a mod is given (`ModApi.build`). A mod that requires a higher one is refused. The version goes up when the API gains something a mod can ask for (2: the skin API, 3: the problem
## screens), so that a mod written for it says so; a mod that requires an older version keeps running, because what it was given is never changed or taken away.
const API_VERSION := 4
## The first version with the skin API: a skin mod requires it.
const SKIN_API_VERSION := 2
## The first version with problem screens: a mod that draws problem types requires it.
const PROBLEM_API_VERSION := 3
## The first version with rule hooks: a mod with `rules` requires it.
const RULE_API_VERSION := 4
## The game's ceilings. A manifest can lower these, never raise them (the same numbers as the godot-sandbox example's loader).
const MAX_EXECUTION_TIMEOUT := 200       # millions of instructions per call into the mod
const MAX_MEMORY := 32                   # MiB of guest memory
const MAX_ALLOCATIONS := 8000            # guest heap allocations
const MAX_REFERENCES := 100              # Variants and Objects the mod holds on to
const MAX_COROUTINES := 32               # suspended coroutines
## A mod that draws (a skin, the screens of problem types) is called while the player waits for a frame, so its instruction limit is lower still (millions of instructions per call, 1 to this): a mod that never
## returns costs a frame this much and no more.
const MAX_DRAWING_EXECUTION_TIMEOUT := 10
## A mod with rule hooks is called inside the tick (up to `RuleHooks.MAX_CALLS_PER_TICK` times in one), so its limit is the lowest the Sandbox counts: 1 million instructions per call.
const MAX_RULE_EXECUTION_TIMEOUT := 1
## The keys of `limits` and their ceilings. Every limit of a manifest is clamped to 1..ceiling: the Sandbox counts instructions at 1 and does not count at 0, and a mod that is not counted can hang the game from any callback it defines.
const LIMITS: Dictionary[String, int] = {
	"execution_timeout": MAX_EXECUTION_TIMEOUT,
	"memory_max": MAX_MEMORY,
	"allocations_max": MAX_ALLOCATIONS,
	"references_max": MAX_REFERENCES,
	"coroutines_max": MAX_COROUTINES,
}
const KNOWN_KEYS: Array[String] = ["entry", "requires_api", "limits", "skin", "problems", "rules"]
## The keys of the `skin` entry.
const SKIN_KEYS: Array[String] = ["shaders"]
## The keys of the `problems` entry.
const PROBLEM_KEYS: Array[String] = ["types", "shaders"]
## The keys of the `rules` entry.
const RULE_KEYS: Array[String] = ["answers", "instructions", "sub"]
## The most problem types one mod draws.
const MAX_PROBLEM_TYPES := 16
## The most shaders a skin, or the problem screens of a mod, list.
const MAX_SHADERS := 8
const SHADER_EXTENSION := "gdshader"
## Where a skin keeps its pictures and shaders in its pack: `skin/`; the problem screens of a mod keep theirs in `problems/`.
const SKIN_FOLDER := "skin/"
const PROBLEM_FOLDER := "problems/"
## The most bytes an entry script may have.
const MAX_SOURCE_BYTES := 256 << 10
const SCRIPT_EXTENSION := "sgd"

var entry := ""
var requires_api := 1
## key -> the value the mod will run with (a ceiling for a key the manifest does not mention).
var limits: Dictionary[String, int] = {}
## Is the mod a skin? And the shaders it lists (paths in the pack, `skin/....gdshader`).
var is_skin := false
var shaders: Array[String] = []
## Does the mod draw problem screens (`problems`)? The problem types it draws, and the shaders those screens list (paths in the pack, `problems/....gdshader`).
var has_problems := false
var problem_types: Array[int] = []
var problem_shaders: Array[String] = []
## Does the mod add rule hooks (`rules`, which lists at least one of the three)? The problem types whose answers it judges, the creature instruction numbers it defines, and whether it has the sub ability.
var has_rules := false
var rule_answers: Array[int] = []
var rule_instructions: Array[int] = []
var rule_sub := false


## The spec `data` (the manifest's `mod` value) describes, or null when it is not one; every reason is appended to `errors`.
static func parse(data: Variant, errors: Array[String]) -> ModSpec:
	if not data is Dictionary:
		errors.append("\"mod\" must be an object {\"entry\": \"name.sgd\"}")
		return null
	var found: Array[String] = []
	var spec := ModSpec.new()
	for key: String in data:
		if not KNOWN_KEYS.has(key):
			found.append("\"mod\" has no \"%s\" (it has %s)" % [key, ", ".join(KNOWN_KEYS)])
	var entry_value: Variant = data.get("entry")
	if not entry_value is String or (entry_value as String).is_empty():
		found.append("\"mod\" needs an \"entry\": the name of a .%s file in the pack's root" % SCRIPT_EXTENSION)
	elif not is_entry_name(entry_value):
		found.append("the mod's entry \"%s\" must be a plain file name ending .%s (no folder, no \"..\")" % [entry_value, SCRIPT_EXTENSION])
	else:
		spec.entry = entry_value
	if data.has("requires_api"):
		var api: Variant = data["requires_api"]
		if not _is_whole(api) or int(api) < 1:
			found.append("\"requires_api\" must be a whole number of 1 or more")
		elif int(api) > API_VERSION:
			found.append("the mod needs API version %d, this game provides %d" % [int(api), API_VERSION])
		else:
			spec.requires_api = int(api)
	if data.has("skin"):
		_parse_skin(data["skin"], spec, found)
	if data.has("problems"):
		_parse_problems(data["problems"], spec, found)
	if data.has("rules"):
		_parse_rules(data["rules"], spec, found)
	for key in LIMITS:
		spec.limits[key] = spec.ceiling(key)
	if data.has("limits"):
		if not data["limits"] is Dictionary:
			found.append("\"limits\" must be an object")
		else:
			for key: String in data["limits"]:
				var value: Variant = data["limits"][key]
				if not LIMITS.has(key):
					found.append("\"limits\" has no \"%s\" (it has %s)" % [key, ", ".join(LIMITS.keys())])
				elif not _is_whole(value):
					found.append("limit \"%s\" must be a whole number" % key)
				else:
					spec.limits[key] = clampi(int(value), 1, spec.ceiling(key))
	errors.append_array(found)
	return null if not found.is_empty() else spec


static func _parse_skin(value: Variant, spec: ModSpec, found: Array[String]) -> void:
	if not value is Dictionary:
		found.append("\"skin\" must be an object ({} for a skin that uses no shader)")
		return
	spec.is_skin = true
	if spec.requires_api < SKIN_API_VERSION:
		found.append("a skin needs \"requires_api\": %d (the skin API came with that version)" % SKIN_API_VERSION)
	for key: String in value:
		if not SKIN_KEYS.has(key):
			found.append("\"skin\" has no \"%s\" (it has %s)" % [key, ", ".join(SKIN_KEYS)])
	spec.shaders = _parse_shaders(value, SKIN_FOLDER, found)


static func _parse_problems(value: Variant, spec: ModSpec, found: Array[String]) -> void:
	if not value is Dictionary:
		found.append("\"problems\" must be an object like {\"types\": [40]}")
		return
	spec.has_problems = true
	if spec.requires_api < PROBLEM_API_VERSION:
		found.append("a mod that draws problem screens needs \"requires_api\": %d (the problem screens came with that version)" % PROBLEM_API_VERSION)
	for key: String in value:
		if not PROBLEM_KEYS.has(key):
			found.append("\"problems\" has no \"%s\" (it has %s)" % [key, ", ".join(PROBLEM_KEYS)])
	var types: Variant = value.get("types")
	if not types is Array or (types as Array).is_empty():
		found.append("\"problems\" needs \"types\": the numbers of the problem types the mod draws, like [40]")
	elif (types as Array).size() > MAX_PROBLEM_TYPES:
		found.append("a mod draws at most %d problem types (it lists %d)" % [MAX_PROBLEM_TYPES, (types as Array).size()])
	else:
		for number: Variant in types:
			if not _is_whole(number) or int(number) < Catalog.PROBLEM_TYPE_COUNT or int(number) > Catalog.LAST_PROBLEM_TYPE:
				found.append("the problem type %s must be a whole number from %d (the first the original does not have) to %d" % [JSON.stringify(number), Catalog.PROBLEM_TYPE_COUNT, Catalog.LAST_PROBLEM_TYPE])
			elif spec.problem_types.has(int(number)):
				found.append("the problem type %d is listed twice" % int(number))
			else:
				spec.problem_types.append(int(number))
	spec.problem_shaders = _parse_shaders(value, PROBLEM_FOLDER, found)


static func _parse_rules(value: Variant, spec: ModSpec, found: Array[String]) -> void:
	if not value is Dictionary:
		found.append("\"rules\" must be an object like {\"sub\": true}")
		return
	spec.has_rules = true
	var mistakes_before := found.size()
	if spec.requires_api < RULE_API_VERSION:
		found.append("a mod with rule hooks needs \"requires_api\": %d (the rule hooks came with that version)" % RULE_API_VERSION)
	for key: String in value:
		if not RULE_KEYS.has(key):
			found.append("\"rules\" has no \"%s\" (it has %s)" % [key, ", ".join(RULE_KEYS)])
	if value.has("answers"):
		var answers: Variant = value["answers"]
		if not answers is Array or (answers as Array).size() > MAX_PROBLEM_TYPES:
			found.append("\"answers\" must be a list of at most %d problem types, like [41]" % MAX_PROBLEM_TYPES)
		else:
			for number: Variant in answers:
				if not _is_whole(number) or int(number) < Catalog.PROBLEM_TYPE_COUNT or int(number) > Catalog.LAST_PROBLEM_TYPE:
					found.append("the problem type %s in \"answers\" must be a whole number from %d (the first the original does not have) to %d" % [JSON.stringify(number), Catalog.PROBLEM_TYPE_COUNT, Catalog.LAST_PROBLEM_TYPE])
				elif spec.rule_answers.has(int(number)):
					found.append("the problem type %d is listed twice in \"answers\"" % int(number))
				else:
					spec.rule_answers.append(int(number))
	if value.has("instructions"):
		var numbers: Variant = value["instructions"]
		if not numbers is Array or (numbers as Array).size() > RuleHooks.MAX_INSTRUCTIONS:
			found.append("\"instructions\" must be a list of at most %d instruction numbers, like [0, 1]" % RuleHooks.MAX_INSTRUCTIONS)
		else:
			for number: Variant in numbers:
				if not _is_whole(number) or int(number) < 0 or int(number) >= RuleHooks.MAX_INSTRUCTIONS:
					found.append("the instruction number %s must be a whole number from 0 to %d" % [JSON.stringify(number), RuleHooks.MAX_INSTRUCTIONS - 1])
				elif spec.rule_instructions.has(int(number)):
					found.append("the instruction number %d is listed twice" % int(number))
				else:
					spec.rule_instructions.append(int(number))
	if value.has("sub"):
		if not value["sub"] is bool:
			found.append("\"sub\" must be true or false")
		else:
			spec.rule_sub = value["sub"]
	if found.size() == mistakes_before and spec.rule_answers.is_empty() and spec.rule_instructions.is_empty() and not spec.rule_sub:
		found.append("\"rules\" defines nothing: list problem types in \"answers\", instruction numbers in \"instructions\" or say \"sub\": true")


## The shaders `value["shaders"]` lists (paths of `folder`), or [] with every mistake appended to `found`.
static func _parse_shaders(value: Dictionary, folder: String, found: Array[String]) -> Array[String]:
	var paths: Array[String] = []
	if not value.has("shaders"):
		return paths
	var listed: Variant = value["shaders"]
	if not listed is Array:
		found.append("\"shaders\" must be a list of file names like %sglow.gdshader" % folder)
		return paths
	if listed.size() > MAX_SHADERS:
		found.append("at most %d shaders can be listed (%d are)" % [MAX_SHADERS, listed.size()])
		return paths
	for path: Variant in listed:
		if not path is String or not is_shader_path(path, folder):
			found.append("the shader %s must be a file of the pack's %s folder ending .%s" % [JSON.stringify(path), folder, SHADER_EXTENSION])
		elif paths.has(path):
			found.append("the shader %s is listed twice" % path)
		else:
			paths.append(path)
	return paths


## Is `path` a place a shader may be: `folder` (`skin/` or `problems/`) and then a plain relative path ending `.gdshader`?
static func is_shader_path(path: String, folder: String = SKIN_FOLDER) -> bool:
	return path.begins_with(folder) and path.get_extension() == SHADER_EXTENSION and path.length() <= 96 and not path.get_basename().get_file().is_empty() and Pack.is_safe(path)


## Is `name` a file name an entry may have: no folder, no `..`, no drive, the extension `.sgd`, and something before it?
static func is_entry_name(name: String) -> bool:
	return name.get_extension() == SCRIPT_EXTENSION and not name.get_basename().is_empty() and name.get_file() == name \
			and not name.begins_with(".") and Pack.is_safe(name)


## Does the mod draw anything (a skin, or the screens of problem types)?
func draws() -> bool:
	return is_skin or has_problems


## The functions the script must define for what the manifest lists: function name -> the names of its arguments (their count is what the Sandbox is asked for). The ONE list of them: `ModLoader.missing_functions` checks it
## when the mod loads and `PackCheck` when the author asks. A mod that lists nothing needs only `mod_init(api)`.
func functions() -> Dictionary[String, PackedStringArray]:
	var found: Dictionary[String, PackedStringArray] = {}
	if is_skin:
		found[ModSkin.FUNCTION] = PackedStringArray(["state", "fraction", "events"])
	if has_problems:
		found[ModProblems.FUNCTION] = PackedStringArray(["state"])
	if not rule_answers.is_empty():
		found[RuleHooks.FUNCTION_JUDGE] = PackedStringArray(["state"])
	if not rule_instructions.is_empty():
		found[RuleHooks.FUNCTION_INSTRUCTION] = PackedStringArray(["state"])
	if rule_sub:
		found[RuleHooks.FUNCTION_SUB] = PackedStringArray(["state"])
	return found


## `function(argument, ...)`, the way an author reads it.
static func signature(function: String, arguments: PackedStringArray) -> String:
	return "%s(%s)" % [function, ", ".join(arguments)]


## The most `key` may be for this mod: the game's ceiling, lower for the instruction limit of a mod that draws and lowest for one with rule hooks.
func ceiling(key: String) -> int:
	if key == "execution_timeout":
		if has_rules:
			return MAX_RULE_EXECUTION_TIMEOUT
		if draws():
			return MAX_DRAWING_EXECUTION_TIMEOUT
	return LIMITS[key]


## The manifest form of the spec: only what differs from the defaults is written.
func to_dict() -> Dictionary:
	var data := {"entry": entry}
	if requires_api != 1:
		data["requires_api"] = requires_api
	var asked := {}
	for key in limits:
		if limits[key] != ceiling(key):
			asked[key] = limits[key]
	if not asked.is_empty():
		data["limits"] = asked
	if is_skin:
		data["skin"] = {"shaders": shaders.duplicate()} if not shaders.is_empty() else {}
	if has_problems:
		data["problems"] = {"types": problem_types.duplicate()}
		if not problem_shaders.is_empty():
			data["problems"]["shaders"] = problem_shaders.duplicate()
	if has_rules:
		data["rules"] = {}
		if not rule_answers.is_empty():
			data["rules"]["answers"] = rule_answers.duplicate()
		if not rule_instructions.is_empty():
			data["rules"]["instructions"] = rule_instructions.duplicate()
		if rule_sub:
			data["rules"]["sub"] = true
	return data


static func _is_whole(value: Variant) -> bool:
	return value is int or (value is float and is_equal_approx(value, roundf(value)))
