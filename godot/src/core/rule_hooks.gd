class_name RuleHooks
extends RefCounted
## The rule hooks of ONE RUN: the named points where a mod pack adds gameplay inside the rules, and the table the rules consult to reach them. A campaign declares the mod packs it uses (`Campaign.mods`); when the run begins
## `GameState.begin_run` resolves them ONCE (`ModHooks.resolve`) into one of these, and the run keeps it (`GameState.hooks`). The rules ask THIS object, never the mods or the autoload that runs them
## (`test_rules_are_plain_objects`): they are handed a table whose only way out is the one `Callable` the resolver set (`set_caller`). A run of an original campaign, of free play or of a tool resolves the empty table
## (`none`): `is_empty`, no number claimed, and every question a rule asks it is answered at once with the original's behaviour and without a single call (`calls` stays 0; `test_rule_hooks`).
##
## THE THREE HOOK POINTS. Each is a function the mod's script defines, named here and in `ModSpec`, given ONE plain Dictionary (`HookState`) and returning plain data that this class validates, clamps and applies through the rules
## (a hook decides nothing by itself):
##   * `judge_answer(state) -> bool`: a problem type the mod ADDED (`ModSpec` `rules.answers`: a number from 34) is judged by the mod instead of its `compare_mode` (`ProblemSession.judge`).
##   * `creature_instruction(state) -> Dictionary`: the creature instruction `Mod_Instruction number value` (`FoeVM`, `ModSpec` `rules.instructions`) asks the mod what it does: skip the next instruction, raise or lower flags, show
##     a picture, move, end the turn.
##   * `sub_ability(state) -> Dictionary`: once per tick, in the `sub` step after the sub has moved (`SimWorld`, `SubModel.adjust`), the mod may set the sub's velocity (within the run's speed limits) and its invulnerability
##     (within the run's length of it), looking at the keys, the place and the speed.
## `validate_*` below says exactly what is accepted. Anything else, an unknown key included, is garbage.
##
## DETERMINISM. A hook is a function of its snapshot and of its MEMORY: a bounded plain-data Dictionary per mod and per hook of the tick that the game stores here and passes in (`state["memory"]`) and takes out (the `"memory"` key of the answer, validated).
## The game gives a hook no clock, no dice and no object; the mod is told the tick of the load it is in. The memory, the faults, a switched-off mod and the tick all start over with every load of the creatures (`begin_load`: a sector
## start, a respawn, the reload at the dock), as the creature flags do, so a load is a fresh start and a replay of the same inputs is the same play. A mod that keeps state in variables of its own instead is outside this
## promise (its answers then depend on how often it was called, which the game does not hand back); `verify_pure` asks every hook twice and calls a different answer a fault, for tests and the pack check.
##
## FAULTS. A hook that raises, runs past its instruction limit (`ModSpec.MAX_RULE_EXECUTION_TIMEOUT` million, never 0), is gone (its mod was unloaded) or answers garbage is a FAULT: the call has its default (an instruction does nothing, the
## sub is not changed, an answer is judged by the type's own `compare_mode`), the fault is recorded (`fault_log`, the `faulted` signal, one warning per mod and run), and a mod with `MAX_FAULTS` faults in a load is switched off for the rest of
## that load. At most `MAX_CALLS_PER_TICK` calls are made in a tick (the rest have their default), so a tick costs at most that many calls of the limit, whatever the scripts do.
##
## Teaches: a narrow interface instead of a global: the rules hold one object that can say nothing but plain data, the sandbox sits behind a single `Callable`, and every promise (bounded, deterministic, defaulted) is kept on the
## game's side of it. And a lifetime list for an object that is built once per run but holds state of three lifetimes.

## A hook was asked and the answer was a fault (`why` is a sentence); not for the calls the budget skipped.
signal faulted(mod_id: StringName, function: String, why: String)

const FUNCTION_JUDGE := "judge_answer"
const FUNCTION_INSTRUCTION := "creature_instruction"
const FUNCTION_SUB := "sub_ability"

## The instruction numbers a mod may define: `Mod_Instruction 0` to `MAX_INSTRUCTIONS - 1`.
const MAX_INSTRUCTIONS := 8
## The most hook calls of one tick; the rest of the tick's questions have their default.
const MAX_CALLS_PER_TICK := 16
## The faults that switch a mod off for the rest of a load.
const MAX_FAULTS := 8
## The lines of `fault_log` kept.
const MAX_LOG := 32

## An answer with more keys than any hook has is garbage without a look at them.
const MAX_ANSWER_KEYS := 16
## Bounds of a mod's memory: keys, their length, a text's length, the elements of an Array.
const MAX_MEMORY_KEYS := 16
const MAX_MEMORY_KEY := 32
const MAX_MEMORY_TEXT := 64
const MAX_MEMORY_ITEMS := 16
## The longest move an instruction may ask for, in the 2-pixel steps of `Move_Foe_Relative_XY`, and the flags (16).
const MAX_MOVE := 16
const FLAG_MASK := 0xFFFF
const MAX_PICTURE := 255

## Starts over with every load of the creatures (`begin_load`): the memory of each mod, its faults in this load, the mods switched off, and the tick (-1 until `begin_tick`).
const LOAD_FIELDS: Array[StringName] = [&"_memory", &"_faults", &"_dead", &"_tick"]
## Starts over with every tick (`begin_tick`): the calls made.
const TICK_FIELDS: Array[StringName] = [&"_calls_this_tick"]
## Member variables that no load or tick clears, and why. The table is made for one run, so these are the run's.
const KEPT_FIELDS: Dictionary[StringName, String] = {
	&"campaign_id": "configuration: the campaign the table was resolved for, set by `ModHooks.resolve`",
	&"declared": "configuration: the mod packs the campaign declares (`Campaign.mods`), set by `ModHooks.resolve`",
	&"unresolved": "configuration: declared mods that do not run, with the reason, set by `ModHooks.resolve`",
	&"_instructions": "configuration: instruction number -> the mod that defines it, claimed by the resolver",
	&"_judges": "configuration: problem type -> the mod that judges its answers, claimed by the resolver",
	&"_sub_mod": "configuration: the mod with a sub ability, claimed by the resolver",
	&"_caller": "wiring: the one way to a mod, set by the resolver",
	&"verify_pure": "configuration: tests and the pack check",
	&"calls": "a counter over the life of the table, for whoever watches (a run of an original campaign: 0)",
	&"fault_log": "a bounded diary of the faults of the run, for whoever watches",
	&"_reported": "the mods already warned about in this run (one warning each)",
	&"trouble": "the warnings of the run about what a pack holds or lacks (a declared mod that does not resolve), each given once, by the resolver",
}

## The campaign and the mod packs it declares, and those of them that do not run (id -> why).
var campaign_id: StringName = &""
var declared: Array[StringName] = []
var unresolved: Dictionary = {}
## Ask the mod twice and call a different answer a fault.
var verify_pure := false
## How many calls were made into mods, and the faults that were recorded.
var calls := 0
var fault_log: Array[String] = []
## The warnings the resolver gave for this run (`ModHooks.resolve`: a declared mod that is not there, or lost a number) and `FoeVM` gives for its `Mod_Instruction` that no mod defines; `TroubleLog.told` is what a test reads.
var trouble := TroubleLog.new()

var _instructions: Dictionary = {}
var _judges: Dictionary = {}
var _sub_mod: StringName = &""
## `func(mod_id: StringName, function: String, state: Dictionary) -> Dictionary`: {"ok": true, "value": the plain answer} or {"ok": false, "why": a sentence}.
var _caller := Callable()
var _reported: Dictionary = {}

## mod id -> {hook function -> its memory (a validated Dictionary)}; mod id -> its faults in this load; the mods switched off; and the tick of this load.
var _memory: Dictionary = {}
var _faults: Dictionary = {}
var _dead: Dictionary = {}
var _tick := -1
var _calls_this_tick := 0


## The empty table: no mod, no hook; what every run that is not of a campaign with mods has.
static func none() -> RuleHooks:
	return RuleHooks.new()


# --- what the resolver sets ---------------------------------------------------------------------------------------------------

func set_caller(caller: Callable) -> void:
	_caller = caller


## The mod `mod_id` defines instruction `number`. False when another mod has it already (the first keeps it) or the number is out of range.
func claim_instruction(number: int, mod_id: StringName) -> bool:
	if number < 0 or number >= MAX_INSTRUCTIONS or _instructions.has(number):
		return false
	_instructions[number] = mod_id
	return true


## The mod `mod_id` judges the answers of problem type `type_id`. False when another mod does.
func claim_judge(type_id: int, mod_id: StringName) -> bool:
	if _judges.has(type_id):
		return false
	_judges[type_id] = mod_id
	return true


## The mod `mod_id` has the sub ability. False when another mod has it.
func claim_sub(mod_id: StringName) -> bool:
	if _sub_mod != &"":
		return false
	_sub_mod = mod_id
	return true


# --- what the rules ask -------------------------------------------------------------------------------------------------------

## True when no hook is defined at all: the originals, free play, the tools.
func is_empty() -> bool:
	return _instructions.is_empty() and _judges.is_empty() and _sub_mod == &""


func runs_instructions() -> bool:
	return not _instructions.is_empty()


func has_instruction(number: int) -> bool:
	return _instructions.has(number)


## Does a mod judge the answers of problem type `type_id`?
func judges(type_id: int) -> bool:
	return _judges.has(type_id)


func has_sub_ability() -> bool:
	return _sub_mod != &""


## The mods that define at least one hook, in the order of `declared`.
func mod_ids() -> Array[StringName]:
	var found: Array[StringName] = []
	for id in declared:
		if _instructions.values().has(id) or _judges.values().has(id) or _sub_mod == id:
			found.append(id)
	return found


## The creatures were made (a load, a respawn, the reload at the dock): the memory, the faults and the tick start over. Called by `SimWorld` where it builds the creatures.
func begin_load() -> void:
	_memory = {}
	_faults = {}
	_dead = {}
	_tick = -1
	_calls_this_tick = 0


## A tick of the rules begins: the tick of the load counts on and the calls of the tick start from none.
func begin_tick() -> void:
	_tick += 1
	_calls_this_tick = 0


## The tick of the load a hook is told (-1 before the first).
func tick() -> int:
	return _tick


## The memory the hook `function` of the mod `mod_id` has now (a copy): what it answered last in this load, `{}` before.
func memory_of(mod_id: StringName, function: String) -> Dictionary:
	return ((_memory.get(mod_id, {}) as Dictionary).get(function, {}) as Dictionary).duplicate(true)


## Has the mod been switched off for this load?
func is_switched_off(mod_id: StringName) -> bool:
	return _dead.has(mod_id)


## The verdict of the mod on `typed` for `problem`: true or false, or null when the mod has no say (no mod judges the type, the input is not a number) or its hook faulted: the game then judges as the type's data says.
func judge_answer(problem: ProblemInstance, typed: Variant) -> Variant:
	var mod_id: Variant = _judges.get(problem.type.id)
	if mod_id == null:
		return null
	if problem.input_kind != ProblemInstance.InputKind.NUMBER:
		trouble.tell("[rules] mod '%s' judges problem type %d, but that type is not answered with a number (it takes the player's own panel); the type's own data judges it" % [mod_id, problem.type.id])
		return null
	if not typed is NumberValue:
		return null
	var answer := _ask(mod_id, FUNCTION_JUDGE, HookState.answer(problem, typed), false)
	if not answer["ok"]:
		return null
	if typeof(answer["value"]) != TYPE_BOOL:
		_fault(mod_id, FUNCTION_JUDGE, "returned %s, not true or false" % type_string(typeof(answer["value"])), false)
		return null
	return answer["value"]


## What the creature instruction `number` with `value` does for the creature `vm`: a validated Dictionary of effects (`validate_instruction`), `{}` when nothing happens (no mod defines it, the call faulted or was skipped).
func creature_instruction(number: int, value: int, vm: FoeVM, ctx: FoeVM.Context) -> Dictionary:
	var mod_id: Variant = _instructions.get(number)
	if mod_id == null:
		return {}
	var answer := _ask(mod_id, FUNCTION_INSTRUCTION, HookState.creature(number, value, vm, ctx, _tick), true)
	return _effect(mod_id, FUNCTION_INSTRUCTION, answer, validate_instruction(answer.get("value")))


## What the sub ability does in this tick: a validated Dictionary (`validate_sub`), `{}` when nothing changes.
func sub_ability(model: SubModel, input: InputSnapshot, sector: int, screen: int) -> Dictionary:
	if _sub_mod == &"":
		return {}
	var state := HookState.sub(model, input, sector, screen, _tick)
	var answer := _ask(_sub_mod, FUNCTION_SUB, state, true)
	return _effect(_sub_mod, FUNCTION_SUB, answer, validate_sub(answer.get("value"), state["max_velocity"], state["max_invulnerability"]))


# --- validating what a mod answers --------------------------------------------------------------------------------------------

## The effect of a creature instruction in the form the game accepts, or null for garbage. Keys, all optional: `condition` (bool: false skips the next instruction), `end_turn` (bool), `set_flags` and `clear_flags` (whole
## numbers, the bits of the 16 flags), `frame` (whole number 0 to 255, bit 7 mirrors), `dx` and `dy` (whole numbers, 2-pixel steps; a move ends the turn), `memory`. A whole number out of its range is cut to it; any other kind of value,
## a key that is not one of these or an answer that is not a Dictionary is garbage.
static func validate_instruction(raw: Variant) -> Variant:
	if not raw is Dictionary or (raw as Dictionary).size() > MAX_ANSWER_KEYS:
		return null
	var out := {}
	for key: Variant in raw:
		var value: Variant = raw[key]
		match key:
			"condition", "end_turn":
				if typeof(value) != TYPE_BOOL:
					return null
				out[key] = value
			"set_flags", "clear_flags":
				if typeof(value) != TYPE_INT:
					return null
				out[key] = clampi(value, 0, FLAG_MASK)
			"frame":
				if typeof(value) != TYPE_INT:
					return null
				out[key] = clampi(value, 0, MAX_PICTURE)
			"dx", "dy":
				if typeof(value) != TYPE_INT:
					return null
				out[key] = clampi(value, -MAX_MOVE, MAX_MOVE)
			"memory":
				var memory: Variant = validate_memory(value)
				if memory == null:
					return null
				out[key] = memory
			_:
				return null
	return out


## The effect of the sub ability, or null for garbage. Keys, all optional: `vx` and `vy` (whole numbers, the sub's velocity in 1/8 pixel per tick, cut to `max_velocity`), `invulnerability` (whole number, ticks, cut to 0
## and `max_invulnerability`), `memory`.
static func validate_sub(raw: Variant, max_velocity: Vector2i, max_invulnerability: int) -> Variant:
	if not raw is Dictionary or (raw as Dictionary).size() > MAX_ANSWER_KEYS:
		return null
	var out := {}
	for key: Variant in raw:
		var value: Variant = raw[key]
		match key:
			"vx", "vy":
				if typeof(value) != TYPE_INT:
					return null
				var limit := max_velocity.x if key == "vx" else max_velocity.y
				out[key] = clampi(value, -limit, limit)
			"invulnerability":
				if typeof(value) != TYPE_INT:
					return null
				out[key] = clampi(value, 0, max_invulnerability)
			"memory":
				var memory: Variant = validate_memory(value)
				if memory == null:
					return null
				out[key] = memory
			_:
				return null
	return out


## A copy of the memory a mod answers, or null for garbage: a Dictionary of at most `MAX_MEMORY_KEYS` entries, the keys texts of at most `MAX_MEMORY_KEY` characters, the values whole numbers, finite numbers, booleans, texts of at most
## `MAX_MEMORY_TEXT` characters or Arrays of at most `MAX_MEMORY_ITEMS` of those.
static func validate_memory(raw: Variant) -> Variant:
	if not raw is Dictionary or (raw as Dictionary).size() > MAX_MEMORY_KEYS:
		return null
	var out := {}
	for key: Variant in raw:
		if not key is String or (key as String).length() > MAX_MEMORY_KEY:
			return null
		var value: Variant = raw[key]
		if value is Array:
			if (value as Array).size() > MAX_MEMORY_ITEMS:
				return null
			var items := []
			for item: Variant in value:
				if not _is_memory_value(item):
					return null
				items.append(item)
			out[key] = items
		elif _is_memory_value(value):
			out[key] = value
		else:
			return null
	return out


static func _is_memory_value(value: Variant) -> bool:
	match typeof(value):
		TYPE_INT, TYPE_BOOL:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_STRING:
			return (value as String).length() <= MAX_MEMORY_TEXT
	return false


# --- the one way to a mod -------------------------------------------------------------------------------------------------------

## Asks `function` of the mod `mod_id` with `state` (plain data; the memory of the mod is added for a hook of the tick) and returns {"ok": true, "value": ...} or {"ok": false}. A hook of the tick (`counted`) is not asked once
## the mod is switched off or the tick's calls are used up.
func _ask(mod_id: StringName, function: String, state: Dictionary, counted: bool) -> Dictionary:
	if not _caller.is_valid():
		return {"ok": false}
	if counted:
		if _dead.has(mod_id) or _calls_this_tick >= MAX_CALLS_PER_TICK:
			return {"ok": false}
		_calls_this_tick += 1
		state["memory"] = memory_of(mod_id, function)
	calls += 1
	var answer: Dictionary = _caller.call(mod_id, function, state)
	if not answer.get("ok", false):
		_fault(mod_id, function, String(answer.get("why", "it failed")), counted)
		return {"ok": false}
	if verify_pure:
		var again: Dictionary = _caller.call(mod_id, function, state)
		if not again.get("ok", false) or again["value"] != answer["value"]:
			_fault(mod_id, function, "it answered differently to the same state", counted)
			return {"ok": false}
	return answer


## The validated `effect` of a hook of the tick: null (garbage) is a fault; its memory, if it sent one, replaces the mod's.
func _effect(mod_id: StringName, function: String, answer: Dictionary, effect: Variant) -> Dictionary:
	if not answer["ok"]:
		return {}
	if effect == null:
		_fault(mod_id, function, "it answered something the game does not accept", true)
		return {}
	if effect.has("memory"):
		if not _memory.has(mod_id):
			_memory[mod_id] = {}
		_memory[mod_id][function] = effect["memory"]
		effect.erase("memory")
	return effect


## Records a fault. One that counted (a hook of the tick) is one more of the mod's in this load; at `MAX_FAULTS` the mod is switched off until the next load.
func _fault(mod_id: StringName, function: String, why: String, counted: bool) -> void:
	var line := "mod '%s' %s: %s" % [mod_id, function, why]
	if fault_log.size() < MAX_LOG:
		fault_log.append(line)
	if not _reported.has(mod_id):
		_reported[mod_id] = true
		push_warning("[rules] %s (further faults of this mod are not reported; see RuleHooks.fault_log)" % line)
	faulted.emit(mod_id, function, why)
	if not counted:
		return
	_faults[mod_id] = int(_faults.get(mod_id, 0)) + 1
	if _faults[mod_id] >= MAX_FAULTS:
		_dead[mod_id] = true
