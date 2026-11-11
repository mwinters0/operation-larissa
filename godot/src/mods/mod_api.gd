class_name ModApi
extends RefCounted
## What the game grants a mod: THE one place that decides it. `build` makes the API Dictionary a mod gets in `mod_init(api)` (read-only to the mod, `ModLoader.freeze`), and
## `property_allowed` / `method_allowed` are the policies for the objects the game hands over. To give mods a new ability, add its key to `build` and its function below;
## to let a mod touch an object, grant the object (`_grant`) and allow the property or method in the policy. Nothing else in the game is reachable from a mod.
##
## The API (`ModSpec.API_VERSION` 7; the first four keys are version 1, `skin` is version 2, `problems` is version 3, `rules` is version 4; version 5 adds to the manifest of a skin, version 6 to the draw list (`ModDraw`: a picture of the game by key) and version 7 the layers a skin's script draws (`skin_layer`), not to this table):
##
##     api_version  int       the version of this API
##     id           String    the mod's id (= its pack's id)
##     log          Callable  log(message): the game prints it with the mod's id and tells `logged` listeners; long text is cut, control characters become spaces
##     load         Callable  load("pictures/ui_picture/x.png") -> Texture2D, AudioStream or Resource of the mod's OWN pack, through the pack's door (`Pack.file`); null for a file
##                            the pack does not hold or a path that is not a plain relative path of the pack. The object is granted: the mod may hold it and hand it back to
##                            the game, and touches nothing of it (the policies allow no property and no method).
##     skin         Dictionary   only for a mod whose manifest says `skin`: the facts a skin needs, plain values (docs/create/SKIN_API.md): `columns`, `rows`, `tile`, `playfield` (the size
##                            in pixels), `max_commands`, `max_layers`, `max_uniforms`, `max_texts`, `max_text`, `min_font_size`, `max_font_size`, `shaders` (the paths its manifest lists). A skin gets nothing else: the state, the tick fraction and the
##                            events arrive as arguments of its own `skin_layer` (or `skin_frame`), and what it draws is a list it returns (`ModDraw`); no node, texture or material is granted.
##     problems     Dictionary   only for a mod whose manifest says `problems`: the facts a problem screen needs, plain values (docs/create/CONTENT.md, "Problem screens"): `types` (the problem types it draws),
##                            `window` (the size in pixels), `max_commands`, `max_layers`, `max_uniforms`, `max_texts`, `max_text`, `min_font_size`, `max_font_size`, `shaders` (the paths its manifest lists).
##                            A problem screen gets nothing else: the problem, the entry and the step arrive as the argument of its own `problem_frame`, and what it draws is a list it returns (`ModDraw`).
##     rules        Dictionary   only for a mod whose manifest says `rules`: the facts a rule hook needs, plain values (docs/create/CONTENT.md, "Rule hooks"): `answers`, `instructions` and `sub` (what its manifest lists),
##                            `max_calls_per_tick`, `max_faults`, and the bounds of what a hook may answer: `max_memory_keys`, `max_memory_key`, `max_memory_text`, `max_memory_items`, `max_move`. A hook gets nothing else:
##                            its snapshot arrives as the argument of its own function (`HookState`), and what it answers is plain data the game validates and cuts (`RuleHooks`).
##
## `Callable.bind()` appends: the mod's id arrives as the last argument of each function. A mod that passes more arguments than a function takes is refused by the call itself.
##
## Teaches: capability-based design (a mod holds nothing but what it was handed), a function table as the entire attack surface, `Callable.bind` to give each mod its own copy of the table, and that the
## narrowest grant is none: a skin draws by returning data, so no object of the game is ever handed to it, a skin, a problem screen or a rule hook.

## A mod's message is cut to this many characters.
const MAX_LOG_CHARS := 200

## A mod logged `text` (`log` of its API); the game also prints it.
signal logged(id: String, text: String)

var _loader: ModLoader


func _init(loader: ModLoader) -> void:
	_loader = loader


## The API of the mod `id` of `pack`. Called by `ModLoader.load_mod` (`ModLoader.api_provider`) before the mod's `mod_init`. Build a fresh Dictionary per mod; the loader freezes it.
func build(id: String, pack: Pack) -> Dictionary:
	var api := {
		"api_version": ModSpec.API_VERSION,
		"id": id,
		"log": _log.bind(id),
		"load": _load.bind(id),
	}
	if pack != null and pack.mod != null and pack.mod.is_skin:
		api["skin"] = _skin_facts(pack.mod)
	if pack != null and pack.mod != null and pack.mod.has_problems:
		api["problems"] = _problem_facts(pack.mod)
	if pack != null and pack.mod != null and pack.mod.has_rules:
		api["rules"] = _rule_facts(pack.mod)
	return api


## The properties of a granted object a mod may read or write. None: a mod holds the objects the game grants and cannot look inside them.
func property_allowed(_id: String, _object: Object, _property: String, _is_set: bool) -> bool:
	return false


## The methods of a granted object a mod may call. None.
func method_allowed(_id: String, _object: Object, _method: String) -> bool:
	return false


## The `skin` key: numbers and names, no object.
func _skin_facts(spec: ModSpec) -> Dictionary:
	return {
		"columns": SkinState.COLUMNS, "rows": SkinState.ROWS, "tile": TileGrid.TILE_SIZE, "playfield": Vector2(TileGrid.PLAYFIELD_SIZE),
		"max_commands": ModDraw.MAX_COMMANDS, "max_layers": ModDraw.MAX_LAYERS, "max_uniforms": ModDraw.MAX_UNIFORMS,
		"max_texts": ModDraw.MAX_TEXTS, "max_text": ModDraw.MAX_TEXT, "min_font_size": ModDraw.MIN_FONT_SIZE, "max_font_size": ModDraw.MAX_FONT_SIZE, "shaders": spec.shaders.duplicate(),
	}


## The `problems` key: numbers and names, no object.
func _problem_facts(spec: ModSpec) -> Dictionary:
	return {
		"types": spec.problem_types.duplicate(), "window": Vector2(ProblemState.WINDOW_SIZE),
		"max_commands": ModDraw.MAX_COMMANDS, "max_layers": ModDraw.MAX_LAYERS, "max_uniforms": ModDraw.MAX_UNIFORMS,
		"max_texts": ModDraw.MAX_TEXTS, "max_text": ModDraw.MAX_TEXT, "min_font_size": ModDraw.MIN_FONT_SIZE, "max_font_size": ModDraw.MAX_FONT_SIZE,
		"shaders": spec.problem_shaders.duplicate(),
	}


## The `rules` key: numbers and names, no object.
func _rule_facts(spec: ModSpec) -> Dictionary:
	return {
		"answers": spec.rule_answers.duplicate(), "instructions": spec.rule_instructions.duplicate(), "sub": spec.rule_sub,
		"max_calls_per_tick": RuleHooks.MAX_CALLS_PER_TICK, "max_faults": RuleHooks.MAX_FAULTS,
		"max_memory_keys": RuleHooks.MAX_MEMORY_KEYS, "max_memory_key": RuleHooks.MAX_MEMORY_KEY, "max_memory_text": RuleHooks.MAX_MEMORY_TEXT,
		"max_memory_items": RuleHooks.MAX_MEMORY_ITEMS, "max_move": RuleHooks.MAX_MOVE,
	}


# --- the functions of the API (each takes the mod's id last, bound by `build`) ---------------------------------------------------

func _log(message: Variant, id: String) -> void:
	var text := _clean(str(message))
	print("[mod %s] %s" % [id, text])
	logged.emit(id, text)


func _load(file: Variant, id: String) -> Resource:
	var mod := _loader.get_mod(id)
	var pack := Packs.pack(StringName(id))                   # (the chain's own pack of that id: the mod's)
	if mod == null or pack == null or not file is String or not Pack.is_safe(file):
		return null
	var made := pack.file(file)
	if made != null:
		_grant(mod, made)
	return made


## Gives the mod a handle to `object`. A grant allows nothing by itself: the properties and methods are the policy's.
func _grant(mod: Node, object: Object) -> void:
	mod.call("add_allowed_object", object)


## `text` cut to `MAX_LOG_CHARS` with control characters (a terminal's escape codes) replaced by spaces.
static func _clean(text: String) -> String:
	var out := ""
	for i in mini(text.length(), MAX_LOG_CHARS):
		out += " " if text.unicode_at(i) < 32 or text.unicode_at(i) == 127 else text[i]
	return out
