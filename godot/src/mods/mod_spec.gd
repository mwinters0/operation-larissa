class_name ModSpec
extends RefCounted
## The `mod` entry of a pack's manifest: what makes a data pack a mod pack. It names the entry script (SafeGDScript, a `.sgd` file of the pack), the version of the game's mod
## API the script was written for, and the limits it asks to run within. The limits a manifest asks for are clamped to the game's ceilings (`MAX_*`): a manifest can lower a limit, never raise it.
##
##     "mod": {"entry": "orchard.sgd", "requires_api": 1, "limits": {"execution_timeout": 100, "memory_max": 16}}
##     "mod": {"entry": "reef.sgd", "requires_api": 2, "skin": {"shaders": ["skin/glow.gdshader"]}}
##     "mod": {"requires_api": 5, "skin": {"render": {"texture_filter": "linear"}, "pictures": {"ui_picture/title_sky": "skin/sky.png"}}}
##     "mod": {"requires_api": 5, "skin": {"hud_font": {"file": "skin/hud.ttf", "size": 14, "color": "#dcf7ff"}}}
##     "mod": {"requires_api": 5, "skin": {"shaders": ["skin/shimmer.gdshader"], "layers": {"background": {"shader": "skin/shimmer.gdshader", "uniforms": {"glint": 0.25, "tint": "#ff8800"}}}}}
##     "mod": {"entry": "reef.sgd", "requires_api": 7, "skin": {"script_layers": ["background", "bubbles"]}}
##     "mod": {"entry": "reef.sgd", "requires_api": 8, "skin": {"script_layers": ["background", "hud_oxygen", "hud_ship"]}}
##     "mod": {"entry": "tides.sgd", "requires_api": 3, "problems": {"types": [40], "shaders": ["problems/wave.gdshader"]}}
##     "mod": {"entry": "tides.sgd", "requires_api": 9, "problems": {"types": [5, 9, 40]}}
##     "mod": {"entry": "rules.sgd", "requires_api": 4, "rules": {"answers": [41], "instructions": [0, 1], "sub": true}}
##
## `entry` is a plain file name (no folder) ending `.sgd`, in the pack's root; only a skin whose script draws nothing may leave it out (a DATA skin: no script, so no Sandbox is needed to wear it). `requires_api` (default 1) is the lowest API version the script needs; a game that provides less
## refuses the pack. `limits` is optional, and so is every key in it. `skin` makes the mod a SKIN (`ModSkin`: the mod draws the sector, `docs/create/SKIN_API.md`); it needs API version 2,
## and lists the shaders the skin may use, text files `skin/<name>.gdshader` of the pack (`ModShader`), at most `MAX_SHADERS`; `render` (`texture_filter`, `snap_transforms`, `snap_vertices`: the `RenderSettings` the skin puts on the window)
## and `pictures` (skin key `ui_picture/<name>` to a PNG `skin/<name>.png` of the pack, at most `MAX_PICTURES`, worn only while the skin is) and `hud_font` (`file`: a `.ttf` of the pack's `skin/` folder, read from its bytes,
## at most `Pack.MAX_FONT_BYTES`; `size` from `MIN_HUD_FONT_SIZE` to `MAX_HUD_FONT_SIZE`; `color`: `#rrggbb` or `#rrggbbaa`: the lettering of the HUD's boxes, `HudLabels`) and `layers` (a layer of the original presenter by name, `SkinLayers.NODES`, to one of the listed `shaders` and the values of its uniforms: a number, `true` / `false`, a list of 2 to 4 numbers or a colour string, at most `MAX_LAYER_UNIFORMS`, each number within
## `MAX_UNIFORM_VALUE`; the game sets `phase`) are API version 5, which a skin without `entry` needs too. `script_layers` (API version 7; needs an `entry`) lists the layers of the original presenter (`SkinLayers.NODES`) and, from API version 8, the parts of the console (`SkinLayers.HUD_NODES`, or the whole console, `SkinLayers.HUD`)
## whose picture the script draws, one call of `skin_layer(name, state, fraction, events)` for each; the others stay the original's, and the layers of `layers` are dressed by their shader on those the script does not draw. A skin with an `entry` and no `script_layers` draws the whole
## screen with `skin_frame(state, fraction, events)`: every layer at once. `problems` makes the mod DRAW the screens of the problem types it lists (`types`, whole numbers from 0 to
## `Catalog.LAST_PROBLEM_TYPE`, at most `MAX_PROBLEM_TYPES`: a number below `Catalog.PROBLEM_TYPE_COUNT` is an ORIGINAL type, drawn by number in place of the original diagram (API version 9; the lock and the ballast panels are the engine's and cannot be listed), a number from it up
## is a type the pack adds and holds as data); it needs API version 3 and lists its shaders like a skin, in the pack's `problems/` folder. `rules` makes the mod
## add GAMEPLAY inside the rules (`RuleHooks`), for a campaign that declares the mod: `answers` lists problem types it judges instead of their `compare_mode` (numbers as for `problems.types`, the pack holds each as data),
## `instructions` the numbers 0 to `RuleHooks.MAX_INSTRUCTIONS - 1` of the creature instruction `Mod_Instruction` it defines, `sub` (true) a sub ability; it needs API version 4, at least one of the three, and a mod with `rules`
## runs under an instruction limit of 1 to `MAX_RULE_EXECUTION_TIMEOUT` million per call. The instruction limit of every mod is at least 1: counting is never off. `Pack` reads this entry (`Pack.mod`), `PackCheck` judges what it names,
## `functions` lists what the script must define for it, and `ModLoader` runs the script.
##
## Teaches: validating an untrusted description by naming each rule in one place, and clamping a request to a ceiling instead of refusing it (a limit is a request; the host decides).

## The version of the API a mod is given (`ModApi.build`). A mod that requires a higher one is refused. The version goes up when the API gains something a mod can ask for (2: the skin API, 3: the problem
## screens, 4: the rule hooks, 5: the data skin, 6: a picture of the game by key in the draw list, 7: the skin's script draws chosen layers, 8: the console's parts are layers too, 9: a problem-screen mod draws the original's types by number), so that a mod written for it says so; a mod that requires an older version keeps running, because what it was given is never changed or taken away.
const API_VERSION := 9
## The first version with the skin API: a skin mod requires it.
const SKIN_API_VERSION := 2
## The first version with data skins: `render` and `pictures` in `skin`, and a skin with no `entry`.
const DATA_SKIN_API_VERSION := 5
## The first version with a script that draws chosen layers: a skin with `script_layers` requires it.
const LAYER_API_VERSION := 7
## The first version with the console's parts as layers: a skin whose `script_layers` names one requires it.
const HUD_API_VERSION := 8
## The first version with problem screens: a mod that draws problem types requires it.
const PROBLEM_API_VERSION := 3
## The first version with the original's problem types drawn by number: a mod whose `problems.types` lists one (below `Catalog.PROBLEM_TYPE_COUNT`) requires it.
const ORIGINAL_PROBLEM_API_VERSION := 9
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
const SKIN_KEYS: Array[String] = ["shaders", "render", "pictures", "hud_font", "layers", "script_layers"]
## The keys of a layer's entry in `layers`, the uniform the game sets itself (the game's time, `SectorPresenter.game_phase`: a manifest cannot give it a value), and the limits of a layer's uniforms.
const LAYER_KEYS: Array[String] = ["shader", "uniforms"]
const PHASE_UNIFORM := "phase"
const MAX_LAYER_UNIFORMS := 16
const MAX_UNIFORM_VALUE := 1000.0
## The keys of the `hud_font` entry of a skin, and the sizes (in pixels) its `size` may be: the boxes of the HUD keep their size, so what a larger font does not fit in a box is cut off.
const HUD_FONT_KEYS: Array[String] = ["file", "size", "color"]
const MIN_HUD_FONT_SIZE := 6
const MAX_HUD_FONT_SIZE := 32
## The keys of the `render` entry of a skin (`RenderSettings`).
const RENDER_KEYS: Array[String] = ["texture_filter", "snap_transforms", "snap_vertices"]
## The kinds of picture key (`<kind>/<name>`, as `GameSkin.pictures` has them) a skin's `pictures` may REPLACE. A draw list may NAME a picture of more kinds (`GameSkin.KEY_KINDS`, `is_drawable_key`): it only shows
## what the game would show, where a replaced picture changes what the game shows everywhere.
const PICTURE_KINDS: Array[String] = ["ui_picture"]
## The longest a picture key a draw list names may be (a file's name under a kind: the registry's names are shorter, `NameRegistry.MAX_NAME_LENGTH`, but a stem the importer keeps is not).
const MAX_KEY := 96
## The most pictures a skin lists.
const MAX_PICTURES := 128
## The keys of the `problems` entry.
const PROBLEM_KEYS: Array[String] = ["types", "shaders"]
## The keys of the `rules` entry.
const RULE_KEYS: Array[String] = ["answers", "instructions", "sub"]
## The most problem types one mod draws.
const MAX_PROBLEM_TYPES := 64
## The most shaders a skin, or the problem screens of a mod, list.
const MAX_SHADERS := 8
const SHADER_EXTENSION := "gdshader"
static var _uniform_name := RegEx.create_from_string("^[A-Za-z_][A-Za-z0-9_]{0,31}$")
static var _key_name := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
## Where a skin keeps its pictures and shaders in its pack: `skin/`; the problem screens of a mod keep theirs in `problems/`.
const SKIN_FOLDER := "skin/"
const PROBLEM_FOLDER := "problems/"
## The most bytes an entry script may have.
const MAX_SOURCE_BYTES := 256 << 10
const SCRIPT_EXTENSION := "sgd"

## The entry script's file name, "" for a data skin (a skin with no script).
var entry := ""
var requires_api := 1
## key -> the value the mod will run with (a ceiling for a key the manifest does not mention).
var limits: Dictionary[String, int] = {}
## Is the mod a skin? And the shaders it lists (paths in the pack, `skin/....gdshader`).
var is_skin := false
var shaders: Array[String] = []
## What the skin asks of the renderer (`skin.render`), or null when it does not say. And its pictures: skin key -> path in the pack (`skin/....png`).
var render: RenderSettings = null
var pictures: Dictionary[String, String] = {}
## The lettering the skin asks for (`skin.hud_font`): the file in the pack (`skin/....ttf`, "" when the skin says none) and the `HudLabels` with the size and colour it set (null when it says none; its `font` is not set: `ModSkin.make` reads the file).
var hud_font_file := ""
var hud_font: HudLabels = null
## The shaders on the layers of the original presenter (`skin.layers`): layer name -> {"shader": the path of one of `shaders`, "uniforms": name -> a float, bool, `Vector2` / `Vector3` / `Vector4` or `Color`}. Which uniforms the shader has is judged by `ModSkin.make`.
var layers: Dictionary[String, Dictionary] = {}
## The layers the skin's script draws (`skin.script_layers`: names of `SkinLayers.NODES`, the original presenter's, and of `SkinLayers.HUD_NODES` or `SkinLayers.HUD`, the console's, in the manifest's order): empty for a skin with no script and for one whose script draws the whole screen (`draws_frame`).
var script_layers: Array[StringName] = []
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
	if data.has("entry"):
		var entry_value: Variant = data["entry"]
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
		_parse_skin(data["skin"], spec, data.has("entry"), found)
	if data.has("problems"):
		_parse_problems(data["problems"], spec, found)
	if data.has("rules"):
		_parse_rules(data["rules"], spec, found)
	if not data.has("entry") and (not spec.is_skin or spec.has_problems or spec.has_rules):
		found.append("\"mod\" needs an \"entry\": the name of a .%s file in the pack's root (only a skin may leave it out)" % SCRIPT_EXTENSION)
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


static func _parse_skin(value: Variant, spec: ModSpec, scripted: bool, found: Array[String]) -> void:
	if not value is Dictionary:
		found.append("\"skin\" must be an object ({} for a skin that uses no shader)")
		return
	spec.is_skin = true
	if spec.requires_api < SKIN_API_VERSION:
		found.append("a skin needs \"requires_api\": %d (the skin API came with that version)" % SKIN_API_VERSION)
	elif spec.requires_api < DATA_SKIN_API_VERSION and (not scripted or value.has("render") or value.has("pictures") or value.has("hud_font") or value.has("layers")):
		found.append("a skin with \"render\", \"pictures\", \"hud_font\" or \"layers\", or with no \"entry\", needs \"requires_api\": %d (data skins came with that version)" % DATA_SKIN_API_VERSION)
	for key: String in value:
		if not SKIN_KEYS.has(key):
			found.append("\"skin\" has no \"%s\" (it has %s)" % [key, ", ".join(SKIN_KEYS)])
	spec.shaders = _parse_shaders(value, SKIN_FOLDER, found)
	if value.has("render"):
		spec.render = _parse_render(value["render"], found)
	if value.has("pictures"):
		_parse_pictures(value["pictures"], spec, found)
	if value.has("hud_font"):
		_parse_hud_font(value["hud_font"], spec, found)
	if value.has("script_layers"):
		_parse_script_layers(value["script_layers"], spec, scripted, found)
	if value.has("layers"):
		if scripted and spec.script_layers.is_empty():
			found.append("\"layers\" cannot dress a skin whose script draws the whole screen (no \"script_layers\"): list the layers the script draws in \"script_layers\", and \"layers\" dresses the others")
		else:
			_parse_layers(value["layers"], spec, found)


## The `script_layers` of a skin: the layers its script draws (of the original presenter, and, from `HUD_API_VERSION`, of the console), into `spec.script_layers`. The whole console and its parts are not both listed: the whole is every part.
static func _parse_script_layers(value: Variant, spec: ModSpec, scripted: bool, found: Array[String]) -> void:
	if not scripted:
		found.append("\"script_layers\" belong to a skin with an \"entry\": the script that draws them")
		return
	if spec.requires_api < LAYER_API_VERSION:
		found.append("a skin with \"script_layers\" needs \"requires_api\": %d (the layers a script draws came with that version)" % LAYER_API_VERSION)
	var names := ", ".join(PackedStringArray(SkinLayers.NODES.keys() + SkinLayers.hud_layers()))
	if not value is Array or (value as Array).is_empty():
		found.append("\"script_layers\" must be a list of the layers the script draws, like [\"background\", \"bubbles\"] (the layers are %s); leave it out for a script that draws the whole screen" % names)
		return
	var console := false
	for layer: Variant in value:
		var named := StringName(layer) if layer is String else &""
		if not SkinLayers.is_presenter_layer(named) and not SkinLayers.is_hud_layer(named):
			found.append("\"script_layers\" has no layer %s (the layers are %s)" % [JSON.stringify(layer), names])
		elif spec.script_layers.has(named):
			found.append("the layer \"%s\" is listed twice in \"script_layers\"" % layer)
		else:
			if SkinLayers.is_hud_layer(named):
				console = true
				if spec.requires_api < HUD_API_VERSION:
					found.append("a skin whose \"script_layers\" has the console's layer \"%s\" needs \"requires_api\": %d (the console's layers came with that version)" % [layer, HUD_API_VERSION])
			spec.script_layers.append(named)
	if console and spec.script_layers.has(SkinLayers.HUD) and spec.script_layers.any(func(layer: StringName) -> bool: return SkinLayers.HUD_NODES.has(layer)):
		found.append("\"script_layers\" has the whole console (\"%s\") and a part of it: the whole console is every part, list one or the other" % SkinLayers.HUD)


## The `RenderSettings` the `render` entry of a skin describes (what it does not say stays the project's), or null with every mistake appended to `found`.
static func _parse_render(value: Variant, found: Array[String]) -> RenderSettings:
	if not value is Dictionary:
		found.append("\"render\" must be an object like {\"texture_filter\": \"linear\"}")
		return null
	var settings := RenderSettings.new()
	var before := found.size()
	for key: String in value:
		if not RENDER_KEYS.has(key):
			found.append("\"render\" has no \"%s\" (it has %s)" % [key, ", ".join(RENDER_KEYS)])
	if value.has("texture_filter"):
		if not value["texture_filter"] is String or not RenderSettings.FILTER_NAMES.has(value["texture_filter"]):
			found.append("\"texture_filter\" must be one of %s" % ", ".join(RenderSettings.FILTER_NAMES.keys()))
		else:
			settings.texture_filter = RenderSettings.FILTER_NAMES[value["texture_filter"]] as Viewport.DefaultCanvasItemTextureFilter
	for key in ["snap_transforms", "snap_vertices"]:
		if value.has(key):
			if not value[key] is bool:
				found.append("\"%s\" must be true or false" % key)
			else:
				settings.set(key, value[key])
	return settings if found.size() == before else null


## The `pictures` of a skin: skin key -> path of a PNG of the pack's `skin/` folder, into `spec.pictures`.
static func _parse_pictures(value: Variant, spec: ModSpec, found: Array[String]) -> void:
	if not value is Dictionary:
		found.append("\"pictures\" must be an object like {\"ui_picture/title_sky\": \"skin/sky.png\"}")
		return
	if (value as Dictionary).size() > MAX_PICTURES:
		found.append("a skin lists at most %d pictures (it lists %d)" % [MAX_PICTURES, (value as Dictionary).size()])
		return
	for key: String in value:
		var path: Variant = value[key]
		if not is_picture_key(key):
			found.append("the picture key \"%s\" must be <kind>/<name> with a kind of %s and a name of lowercase letters, digits and underscores" % [key, ", ".join(PICTURE_KINDS)])
		elif not path is String or not is_picture_path(path):
			found.append("the picture of \"%s\", %s, must be a file of the pack's %s folder ending .png" % [key, JSON.stringify(path), SKIN_FOLDER])
		else:
			spec.pictures[key] = path


## The `hud_font` of a skin: the file of its `skin/` folder, and the size and colour of the letters, into `spec.hud_font_file` and `spec.hud_font`.
static func _parse_hud_font(value: Variant, spec: ModSpec, found: Array[String]) -> void:
	if not value is Dictionary:
		found.append("\"hud_font\" must be an object like {\"file\": \"%shud.%s\", \"size\": 14, \"color\": \"#dcf7ff\"}" % [SKIN_FOLDER, Pack.FONT_EXTENSION])
		return
	var before := found.size()
	var labels := HudLabels.new()
	for key: String in value:
		if not HUD_FONT_KEYS.has(key):
			found.append("\"hud_font\" has no \"%s\" (it has %s)" % [key, ", ".join(HUD_FONT_KEYS)])
	if not value.has("file"):
		found.append("\"hud_font\" needs a \"file\": a .%s file of the pack's %s folder" % [Pack.FONT_EXTENSION, SKIN_FOLDER])
	elif not value["file"] is String or not is_font_path(value["file"]):
		found.append("the font %s must be a file of the pack's %s folder ending .%s" % [JSON.stringify(value["file"]), SKIN_FOLDER, Pack.FONT_EXTENSION])
	else:
		spec.hud_font_file = value["file"]
	if value.has("size"):
		if not _is_whole(value["size"]) or int(value["size"]) < MIN_HUD_FONT_SIZE or int(value["size"]) > MAX_HUD_FONT_SIZE:
			found.append("the font's \"size\" must be a whole number from %d to %d" % [MIN_HUD_FONT_SIZE, MAX_HUD_FONT_SIZE])
		else:
			labels.font_size = int(value["size"])
	if value.has("color"):
		if not value["color"] is String or not (value["color"] as String).begins_with("#") or not Color.html_is_valid(value["color"]):
			found.append("the font's \"color\" must be a string like \"#dcf7ff\" (#rrggbb, or #rrggbbaa)")
		else:
			labels.font_color = Color.html(value["color"])
	if found.size() == before:
		spec.hud_font = labels


## The `layers` of a skin: layer name -> its shader (one of the skin's `shaders`) and the values of its uniforms, into `spec.layers`.
static func _parse_layers(value: Variant, spec: ModSpec, found: Array[String]) -> void:
	if not value is Dictionary:
		found.append("\"layers\" must be an object like {\"background\": {\"shader\": \"%sshimmer.%s\", \"uniforms\": {\"glint\": 0.25}}}" % [SKIN_FOLDER, SHADER_EXTENSION])
		return
	for layer: String in value:
		var entry: Variant = value[layer]
		if not SkinLayers.NODES.has(StringName(layer)):
			found.append("\"layers\" has no layer \"%s\" (the layers are %s)" % [layer, ", ".join(PackedStringArray(SkinLayers.NODES.keys()))])
			continue
		if spec.script_layers.has(StringName(layer)):
			found.append("the layer \"%s\" is drawn by the script (\"script_layers\"): the script names a shader of its own in a \"layer\" command, and \"layers\" dresses the layers it does not draw" % layer)
			continue
		if not entry is Dictionary:
			found.append("the layer \"%s\" must be an object like {\"shader\": \"%sshimmer.%s\", \"uniforms\": {}}" % [layer, SKIN_FOLDER, SHADER_EXTENSION])
			continue
		var before := found.size()
		for key: String in entry:
			if not LAYER_KEYS.has(key):
				found.append("the layer \"%s\" has no \"%s\" (it has %s)" % [layer, key, ", ".join(LAYER_KEYS)])
		if not entry.has("shader") or not entry["shader"] is String or not spec.shaders.has(entry["shader"]):
			found.append("the layer \"%s\" needs a \"shader\": one of the skin's \"shaders\" (%s)" % [layer, ", ".join(spec.shaders) if not spec.shaders.is_empty() else "it lists none"])
		var uniforms := {}
		if entry.has("uniforms"):
			uniforms = _parse_uniforms(layer, entry["uniforms"], found)
		if found.size() == before:
			spec.layers[layer] = {"shader": entry["shader"], "uniforms": uniforms}


## The values of the uniforms of the layer `layer` (name -> float, bool, vector or colour), or {} with every mistake appended to `found`.
static func _parse_uniforms(layer: String, value: Variant, found: Array[String]) -> Dictionary:
	var uniforms := {}
	if not value is Dictionary:
		found.append("the \"uniforms\" of the layer \"%s\" must be an object like {\"glint\": 0.25}" % layer)
		return uniforms
	if (value as Dictionary).size() > MAX_LAYER_UNIFORMS:
		found.append("a layer sets at most %d uniforms (\"%s\" sets %d)" % [MAX_LAYER_UNIFORMS, layer, (value as Dictionary).size()])
		return uniforms
	for uniform: String in value:
		if not is_uniform_name(uniform):
			found.append("the uniform name \"%s\" of the layer \"%s\" must be letters, digits and underscores, not starting with a digit" % [uniform, layer])
		elif uniform == PHASE_UNIFORM:
			found.append("the layer \"%s\" sets \"%s\": the game sets it (its time), a manifest cannot" % [layer, PHASE_UNIFORM])
		else:
			var parsed: Variant = _uniform_value(value[uniform])
			if parsed == null:
				found.append("the uniform \"%s\" of the layer \"%s\" must be a number, true or false, a list of 2 to 4 numbers or a colour string like \"#ff8800\" (numbers from %d to %d)" % [uniform, layer, -MAX_UNIFORM_VALUE, MAX_UNIFORM_VALUE])
			else:
				uniforms[uniform] = parsed
	return uniforms


## A uniform's value as the shader gets it: a number (a float), a bool, a list of 2 to 4 numbers (a `Vector2` .. `Vector4`) or a `#rrggbb` / `#rrggbbaa` string (a `Color`). Null for anything else, and for a number out of bounds.
static func _uniform_value(value: Variant) -> Variant:
	if value is bool:
		return value
	if _is_bounded_number(value):
		return float(value)
	if value is String:
		return Color.html(value) if (value as String).begins_with("#") and Color.html_is_valid(value) else null
	if value is Array and (value as Array).size() >= 2 and (value as Array).size() <= 4 and (value as Array).all(_is_bounded_number):
		var numbers: Array = value
		match numbers.size():
			2:
				return Vector2(numbers[0], numbers[1])
			3:
				return Vector3(numbers[0], numbers[1], numbers[2])
		return Vector4(numbers[0], numbers[1], numbers[2], numbers[3])
	return null


static func _is_bounded_number(value: Variant) -> bool:
	return (value is int or value is float) and absf(float(value)) <= MAX_UNIFORM_VALUE


## Is `name` a name a shader's uniform may have: letters, digits and underscores, not starting with a digit, at most 32 long?
static func is_uniform_name(uniform: String) -> bool:
	return _uniform_name.search(uniform) != null


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
			if not _is_whole(number) or int(number) < 0 or int(number) > Catalog.LAST_PROBLEM_TYPE:
				found.append("the problem type %s must be a whole number from 0 to %d (0 to %d are the original's, the rest are types the pack adds)" % [JSON.stringify(number), Catalog.LAST_PROBLEM_TYPE, Catalog.PROBLEM_TYPE_COUNT - 1])
			elif spec.problem_types.has(int(number)):
				found.append("the problem type %d is listed twice" % int(number))
			else:
				spec.problem_types.append(int(number))
				if int(number) < Catalog.PROBLEM_TYPE_COUNT and spec.requires_api < ORIGINAL_PROBLEM_API_VERSION:
					found.append("a mod that draws the original's problem type %d needs \"requires_api\": %d (the original's types came with that version)" % [int(number), ORIGINAL_PROBLEM_API_VERSION])
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


## Is `key` a picture key a skin may map (`PICTURE_KINDS`, then a name)?
static func is_picture_key(key: String) -> bool:
	var parts := key.split("/")
	return parts.size() == 2 and PICTURE_KINDS.has(parts[0]) and NameRegistry.is_valid_name(parts[1])


## Is `key` a picture key a draw list may name (`GameSkin.KEY_KINDS`, then a name of lowercase letters, digits and underscores starting with a letter)? A shape only: whether the chain holds a picture for it is `Assets.picture_by_key`'s answer.
static func is_drawable_key(key: String) -> bool:
	if key.length() > MAX_KEY:
		return false
	var parts := key.split("/")
	return parts.size() == 2 and GameSkin.KEY_KINDS.has(parts[0]) and _key_name.search(parts[1]) != null


## Is `path` a place a skin's picture may be: `skin/` and then a plain relative path ending `.png`?
static func is_picture_path(path: String) -> bool:
	return path.begins_with(SKIN_FOLDER) and path.get_extension() == "png" and path.length() <= 96 and not path.get_basename().get_file().is_empty() and Pack.is_safe(path)


## Is `path` a place a skin's font may be: `skin/` and then a plain relative path ending `.ttf`?
static func is_font_path(path: String) -> bool:
	return path.begins_with(SKIN_FOLDER) and path.get_extension() == Pack.FONT_EXTENSION and path.length() <= 96 and not path.get_basename().get_file().is_empty() and Pack.is_safe(path)


## Does the mod have a script (`entry`)? A data skin has none: it is worn with no Sandbox.
func has_entry() -> bool:
	return not entry.is_empty()


## Is `name` a file name an entry may have: no folder, no `..`, no drive, the extension `.sgd`, and something before it?
static func is_entry_name(name: String) -> bool:
	return name.get_extension() == SCRIPT_EXTENSION and not name.get_basename().is_empty() and name.get_file() == name \
			and not name.begins_with(".") and Pack.is_safe(name)


## Does the skin's script draw the whole screen (`skin_frame`)? A skin with an `entry` and no `script_layers` does.
func draws_frame() -> bool:
	return is_skin and has_entry() and script_layers.is_empty()


## Does the mod draw anything (a skin, or the screens of problem types)?
func draws() -> bool:
	return is_skin or has_problems


## The functions the script must define for what the manifest lists: function name -> the names of its arguments (their count is what the Sandbox is asked for). The ONE list of them: `ModLoader.missing_functions` checks it
## when the mod loads and `PackCheck` when the author asks. A mod that lists nothing needs only `mod_init(api)`.
func functions() -> Dictionary[String, PackedStringArray]:
	var found: Dictionary[String, PackedStringArray] = {}
	if is_skin and has_entry():
		if script_layers.is_empty():
			found[ModSkin.FRAME_FUNCTION] = PackedStringArray(["state", "fraction", "events"])
		else:
			found[ModSkin.LAYER_FUNCTION] = PackedStringArray(["name", "state", "fraction", "events"])
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
	var data := {}
	if has_entry():
		data["entry"] = entry
	if requires_api != 1:
		data["requires_api"] = requires_api
	var asked := {}
	for key in limits:
		if limits[key] != ceiling(key):
			asked[key] = limits[key]
	if not asked.is_empty():
		data["limits"] = asked
	if is_skin:
		data["skin"] = {}
		if not shaders.is_empty():
			data["skin"]["shaders"] = shaders.duplicate()
		if render != null:
			data["skin"]["render"] = _render_dict()
		if not pictures.is_empty():
			data["skin"]["pictures"] = pictures.duplicate()
		if hud_font != null:
			data["skin"]["hud_font"] = _hud_font_dict()
		if not layers.is_empty():
			data["skin"]["layers"] = _layers_dict()
		if not script_layers.is_empty():
			data["skin"]["script_layers"] = script_layers.map(func(layer: StringName) -> String: return String(layer))
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


## The `render` entry as the manifest writes it: the keys that differ from the project's settings.
func _render_dict() -> Dictionary:
	var plain := RenderSettings.new()
	var written := {}
	if render.texture_filter != plain.texture_filter:
		written["texture_filter"] = RenderSettings.filter_name(render.texture_filter)
	for key in ["snap_transforms", "snap_vertices"]:
		if render.get(key) != plain.get(key):
			written[key] = render.get(key)
	return written


## The `hud_font` entry as the manifest writes it: the file, and the size and colour when they differ from `HudLabels`'.
func _hud_font_dict() -> Dictionary:
	var plain := HudLabels.new()
	var written := {"file": hud_font_file}
	if hud_font.font_size != plain.font_size:
		written["size"] = hud_font.font_size
	if hud_font.font_color != plain.font_color:
		written["color"] = "#" + hud_font.font_color.to_html(not is_equal_approx(hud_font.font_color.a, 1.0))
	return written


## The `layers` entry as the manifest writes it (a vector as a list, a colour as a string).
func _layers_dict() -> Dictionary:
	var written := {}
	for layer in layers:
		var entry := {"shader": layers[layer]["shader"]}
		var uniforms: Dictionary = layers[layer]["uniforms"]
		if not uniforms.is_empty():
			entry["uniforms"] = {}
			for uniform: String in uniforms:
				entry["uniforms"][uniform] = _written_uniform(uniforms[uniform])
		written[layer] = entry
	return written


static func _written_uniform(value: Variant) -> Variant:
	if value is Vector2:
		return [value.x, value.y]
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Vector4:
		return [value.x, value.y, value.z, value.w]
	if value is Color:
		return "#" + (value as Color).to_html(not is_equal_approx((value as Color).a, 1.0))
	return value


static func _is_whole(value: Variant) -> bool:
	return value is int or (value is float and is_equal_approx(value, roundf(value)))
