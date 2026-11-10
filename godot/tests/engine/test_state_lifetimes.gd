class_name TestStateLifetimes
extends GdUnitTestSuite
## Teaches: making "forgot to reset it" a test failure. `GameState`, `SimWorld`, `SubModel` and the objects a `SimWorld` fills from
## itself (`FoeVM.Context`, `FoeModel`) each declare which lifetime every member variable has (the `*_FIELDS` constants: a life, a sector, a run, a screen, a tick ... and `KEPT_FIELDS` with a reason),
## and each lifetime has one place that clears it. This suite reads the scripts' own variable lists
## (`Script.get_script_property_list`), so a new variable that is in no list fails here before anybody plays the bug. Then it dirties
## every field of a lifetime, runs that lifetime's reset, and compares the object with a fresh one that got the same reset: whatever
## the reset forgets shows up as a difference, named by field. The objects a sim fills from itself are also held against the sim after
## every path that fills them: a copy that drifts from its owner shows up the same way. See docs/engine/ARCHITECTURE.md, "Lifetimes of
## state".
##
## It also pins one reset of the original: `MidpointReached` (0x448680) starts over with every life before the midpoint, as on every
## entry of `DoAction` (0x417ffc). (The console of a new run is in test_message_light_death.gd and test_sign_in_ui.gd.)

const GAME_STATE_SCRIPT := preload("res://src/autoload/game_state.gd")
const GAME_CLOCK_SCRIPT := preload("res://src/autoload/game_clock.gd")
const ARCHITECTURE_DOC := "docs/engine/ARCHITECTURE.md, \"Lifetimes of state\""
## The first sector of the dev tour: it has pieces on screens 0-5 and a screen 6.
const SECTOR := 0
const SCREEN := 2
## A sector with creatures on several screens, and a screen of it that is not the first.
const CREATURE_SECTOR := DevCreatures.ARENA
const CREATURE_SCREEN := DevCreatures.RUNNER_SCREEN


# --- every field has exactly one lifetime -------------------------------------------------------

func test_every_game_state_field_has_one_lifetime() -> void:
	_assert_classified(GAME_STATE_SCRIPT, "src/autoload/game_state.gd")


func test_every_sim_world_field_has_one_lifetime() -> void:
	_assert_classified(SimWorld, "src/rules/sim_world.gd")


func test_every_sub_model_field_has_one_lifetime() -> void:
	_assert_classified(SubModel, "src/rules/sub_model.gd")


func test_every_creature_context_field_has_one_lifetime() -> void:
	_assert_classified(FoeVM.Context, "src/core/foe_vm.gd (Context)")


func test_every_creature_field_has_one_lifetime() -> void:
	_assert_classified(FoeModel, "src/rules/foe_model.gd")


## The autoloads that a scene change starts over (`SceneRouter.start_fresh`): the clock's holds and the sound's pauses.
func test_every_game_clock_field_has_one_lifetime() -> void:
	_assert_classified(GAME_CLOCK_SCRIPT, "src/autoload/game_clock.gd")


func test_every_audio_field_has_one_lifetime() -> void:
	_assert_classified(AudioService, "src/autoload/audio.gd")


## The rule hooks of a run (`RuleHooks`) are made once per run; what they keep starts over with every load of the creatures and every tick.
func test_every_rule_hooks_field_has_one_lifetime() -> void:
	_assert_classified(RuleHooks, "src/core/rule_hooks.gd")


func test_a_load_of_the_creatures_clears_what_the_hooks_keep_of_it_and_a_tick_clears_the_tick() -> void:
	var used := RuleHooks.none()
	used.begin_load()
	_dirty_all(used, RuleHooks.LOAD_FIELDS)
	used.begin_load()
	var fresh := RuleHooks.none()
	fresh.begin_load()
	_assert_same_fields(used, fresh, RuleHooks.LOAD_FIELDS, "RuleHooks.begin_load")
	_dirty_all(used, RuleHooks.TICK_FIELDS)
	used.begin_tick()
	fresh.begin_tick()
	_assert_same_fields(used, fresh, RuleHooks.TICK_FIELDS, "RuleHooks.begin_tick")


## The mods the game runs are derived from the chain (`ModHost`): its fields are the chain's lifetime or wiring.
func test_every_mod_host_field_has_one_lifetime() -> void:
	_assert_classified(ModHost, "src/autoload/mod_host.gd")


func _assert_classified(script: Script, file: String) -> void:
	var scopes := _scopes(script)
	var problems: Array[String] = []
	if not scopes.has("KEPT_FIELDS"):
		problems.append("%s declares no KEPT_FIELDS (an empty one says that every field is cleared somewhere)" % file)
	var variables := _variables(script)
	for field in variables:
		var owners: Array[String] = []
		for scope: String in scopes:
			if (scopes[scope] as Array).has(field):
				owners.append(scope)
		if owners.is_empty():
			problems.append(("%s: `%s` has no lifetime. Add it to the *_FIELDS list of the scope whose reset clears it (%s), and clear it "
					+ "there; or, if nothing ever clears it, to KEPT_FIELDS with the reason (%s).") % [
					file, field, ", ".join(scopes.keys().filter(func(s: String) -> bool: return s != "KEPT_FIELDS")), ARCHITECTURE_DOC])
		elif owners.size() > 1:
			problems.append("%s: `%s` is in %s. A field has one lifetime: keep it in the list of the widest scope that clears it." % [
					file, field, " and ".join(owners)])
	for scope: String in scopes:
		for field: StringName in scopes[scope]:
			if not variables.has(field):
				problems.append("%s: %s names `%s`, which is no member variable: take it out of the list." % [file, scope, field])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


# --- GameState ------------------------------------------------------------------------------------

## A run that begins on a dirty state is the run a fresh state begins: with a player and without one.
func test_begin_run_leaves_nothing_of_the_run_before() -> void:
	for player: PlayerProfile in [_player(false), _player(true), null]:
		var used := _new_state()
		used.begin_run(_player(false))
		used.collect_piece(1)
		used.update_oxygen(-1)
		used.hold_losses()
		_dirty_all(used, _fields(GAME_STATE_SCRIPT))
		used.begin_run(player)
		var fresh := _new_state()
		fresh.begin_run(player)
		_assert_same_fields(used, fresh, _fields(GAME_STATE_SCRIPT), "begin_run(%s)" % ("null" if player == null else player.name))


func test_begin_life_clears_the_life_and_keeps_the_rest() -> void:
	for past: bool in [false, true]:
		var used := _new_state()
		used.begin_run(_player(past))
		used.collect_piece(2)
		_dirty_all(used, GAME_STATE_SCRIPT.LIFE_FIELDS)
		used.begin_life()
		var fresh := _new_state()
		fresh.begin_run(_player(past))
		_assert_same_fields(used, fresh, GAME_STATE_SCRIPT.LIFE_FIELDS, "begin_life (past the midpoint: %s)" % past)
		assert_bool(used.has_piece(2)).is_true()


func test_begin_sector_clears_the_sector_and_the_life_and_keeps_the_run() -> void:
	var used := _new_state()
	used.begin_run(_player(true))
	used.fire_ink()
	_dirty_all(used, _join(GAME_STATE_SCRIPT.SECTOR_FIELDS, GAME_STATE_SCRIPT.LIFE_FIELDS))
	used.begin_sector()
	var fresh := _new_state()
	_assert_same_fields(used, fresh, _join(GAME_STATE_SCRIPT.SECTOR_FIELDS, GAME_STATE_SCRIPT.LIFE_FIELDS), "begin_sector")
	assert_int(used.ink).is_equal(_player(true).ink - 1)                # (the run keeps its numbers)


## Every reset tells the console what to show: the signals `Hud._ready` reads the values of.
func test_every_reset_announces_what_the_console_shows() -> void:
	for reset: StringName in [&"begin_life", &"begin_sector", &"begin_run"]:
		var state := _new_state()
		var heard: Array[String] = []
		state.oxygen_changed.connect(func(_t: int, _o: int) -> void: heard.append("oxygen"))
		state.ink_changed.connect(func(_n: int) -> void: heard.append("ink"))
		state.sector_changed.connect(func(_s: int) -> void: heard.append("sector"))
		state.message_light_changed.connect(func(_s: bool, _c: bool) -> void: heard.append("lights"))
		state.call(reset)
		for signal_name: String in ["oxygen", "ink", "sector", "lights"]:
			assert_array(heard).override_failure_message("%s did not announce %s" % [reset, signal_name]).contains([signal_name])


## The repro of the midpoint that outlived a life: the sub sees screen 6 with a piece of screens 0-5 still missing, loses a tank and
## starts again on screen 0. `DoAction` set `MidpointReached` back to 0, so collecting the rest of the pieces is not the midpoint
## yet; the sub has to see screen 6 again.
func test_a_respawn_before_the_midpoint_forgets_that_screen_6_was_seen() -> void:
	var run := _new_state()
	run.begin_run(null)
	var sim := SimWorld.new(run)
	sim.begin_sector(SECTOR, false)
	var early := _pieces_before_the_midpoint(sim.sector)
	assert_array(early).is_not_empty()
	sim.load_screen(Tuning.resolve().midpoint_screen)
	run.screen_entered(Tuning.resolve().midpoint_screen, sim.sector)
	assert_bool(run.midpoint_reached).is_true()
	assert_bool(run.past_midpoint).is_false()
	run.respawn()                                                       # (a tank lost: `GameFlow.respawn`)
	sim.begin_sector(SECTOR, run.past_midpoint)
	assert_bool(run.midpoint_reached).override_failure_message("MidpointReached outlived the life").is_false()
	for index: int in early:
		run.collect_piece(index)
	run.update_midpoint(sim.sector)
	assert_bool(run.past_midpoint).is_false()
	sim.load_screen(Tuning.resolve().midpoint_screen)
	run.screen_entered(Tuning.resolve().midpoint_screen, sim.sector)
	assert_bool(run.past_midpoint).is_true()


## Past the midpoint a life starts on screen 6, and `MidpointReached` is set (`DoAction`: 1 when `IsPastSectorMidpoint`).
func test_a_respawn_past_the_midpoint_keeps_it() -> void:
	var run := _new_state()
	run.begin_run(_player(true))
	var sim := SimWorld.new(run)
	sim.begin_sector(SECTOR, run.past_midpoint)
	run.midpoint_reached = false
	sim.begin_sector(SECTOR, run.past_midpoint)
	assert_bool(run.midpoint_reached).is_true()
	assert_bool(run.past_midpoint).is_true()


# --- SimWorld and SubModel ------------------------------------------------------------------------

## A load on a dirty sim gives every field of the load and the screen what a fresh sim's load gives.
func test_a_sector_load_leaves_nothing_of_the_load_before() -> void:
	var fields := _join(SimWorld.LOAD_FIELDS, SimWorld.SCREEN_FIELDS)
	var used := SimWorld.new(_new_state())
	used.load_sector(SECTOR, SCREEN)
	used.start_flight()
	if _any_trigger(used) != null:
		used.touch_trigger(_any_trigger(used))
	_dirty_all(used, fields)
	used.load_sector(SECTOR, SCREEN)
	var fresh := SimWorld.new(_new_state())
	fresh.load_sector(SECTOR, SCREEN)
	_assert_same_fields(used, fresh, fields, "SimWorld.load_sector")


func test_a_screen_load_leaves_nothing_of_the_screen_before() -> void:
	var used := SimWorld.new(_new_state())
	used.load_sector(SECTOR, SCREEN)
	_dirty_all(used, SimWorld.SCREEN_FIELDS)
	used.load_screen(SCREEN)
	var fresh := SimWorld.new(_new_state())
	fresh.load_sector(SECTOR, SCREEN)
	_assert_same_fields(used, fresh, SimWorld.SCREEN_FIELDS, "SimWorld.load_screen")


func test_placing_the_sub_leaves_nothing_of_where_it_was() -> void:
	var used := SubModel.new(Tuning.resolve().sub)
	_dirty_all(used, SubModel.PLACE_FIELDS)
	used.place_original(120, 100, 3)
	var fresh := SubModel.new(Tuning.resolve().sub)
	fresh.place_original(120, 100, 3)
	_assert_same_fields(used, fresh, SubModel.PLACE_FIELDS, "SubModel.place_original")


# --- the creature context and the creatures ----------------------------------------------------------

## Each fill of the context gives what a fresh context given the same fill has.
func test_each_fill_of_the_creature_context_leaves_nothing_of_the_one_before() -> void:
	var vms: Array[FoeVM] = [FoeVM.new(), FoeVM.new()]
	var dice := RandomNumberGenerator.new()
	var fills := {
		"begin_load": [_join(_join(FoeVM.Context.LOAD_FIELDS, FoeVM.Context.SCREEN_FIELDS), FoeVM.Context.TICK_FIELDS),
				func(ctx: FoeVM.Context) -> void: ctx.begin_load(vms, dice, 3, Vector2i(120, 80))],
		"show_screen": [FoeVM.Context.SCREEN_FIELDS, func(ctx: FoeVM.Context) -> void: ctx.show_screen(3)],
		"begin_tick": [FoeVM.Context.TICK_FIELDS, func(ctx: FoeVM.Context) -> void: ctx.begin_tick(Vector2i(120, 80))],
	}
	for fill: String in fills:
		var fields: Array[StringName] = fills[fill][0]
		var used := FoeVM.Context.new()
		_dirty_all(used, fields)
		(fills[fill][1] as Callable).call(used)
		var fresh := FoeVM.Context.new()
		(fills[fill][1] as Callable).call(fresh)
		_assert_same_fields(used, fresh, fields, "FoeVM.Context." + fill)


## The context and the creatures are derived from the sim: after every path that fills them they say what the sim holds (the screen
## shown, the sub, the creatures, the dice).
func test_the_creature_context_follows_the_sim_through_every_path_that_fills_it() -> void:
	var sim := SimWorld.new(_new_state())
	sim.load_sector(CREATURE_SECTOR, CREATURE_SCREEN)
	assert_array(sim.foes).is_not_empty()
	_assert_follows_the_sim(sim, "load_sector")
	sim.load_screen(0)
	_assert_follows_the_sim(sim, "load_screen")
	sim.start_flight()
	sim.foes_active = true
	for t in 40:
		sim.tick()
	_assert_follows_the_sim(sim, "tick")
	sim.reload_creatures()
	_assert_follows_the_sim(sim, "reload_creatures")
	sim.begin_sector(CREATURE_SECTOR, false)
	_assert_follows_the_sim(sim, "begin_sector (a respawn)")


## The reload after the lock is the creatures' part of a load: the context and the creatures it leaves are, field by field, those of a
## fresh `load_sector` and `load_screen` of the same screen (the place of the sub, which a tick fills, is the sim's own in each).
func test_the_reloaded_creatures_and_context_are_those_of_a_fresh_load() -> void:
	var used := SimWorld.new(_new_state())
	used.load_sector(CREATURE_SECTOR, CREATURE_SCREEN)
	used.start_flight()
	used.foes_active = true
	for t in 40:
		used.tick()
	used.foe_context.semaphore = 0xFFFF
	used.reload_creatures()
	var fresh := SimWorld.new(_new_state())
	fresh.load_sector(CREATURE_SECTOR, 0)
	fresh.load_screen(CREATURE_SCREEN)
	_assert_same_fields(used.foe_context, fresh.foe_context, _join(FoeVM.Context.LOAD_FIELDS, FoeVM.Context.SCREEN_FIELDS),
			"reload_creatures (the context)")
	assert_int(used.foes.size()).is_equal(fresh.foes.size())
	var foe_fields := _fields(FoeModel)
	foe_fields.append_array(FoeModel.KEPT_FIELDS.keys())
	for i in used.foes.size():
		_assert_same_fields(used.foes[i], fresh.foes[i], foe_fields, "reload_creatures (creature %d)" % i)
	_assert_follows_the_sim(used, "reload_creatures")
	_assert_follows_the_sim(fresh, "load_sector + load_screen")


func _assert_follows_the_sim(sim: SimWorld, path: String) -> void:
	var ctx := sim.foe_context
	var different: Array[String] = []
	if ctx.current_screen != sim.screen_index:
		different.append("  current_screen: %d, the sim shows %d" % [ctx.current_screen, sim.screen_index])
	if Vector2i(ctx.sub_x, ctx.sub_y) != sim.sub.original_position():
		different.append("  sub_x / sub_y: %s, the sub is at %s" % [Vector2i(ctx.sub_x, ctx.sub_y), sim.sub.original_position()])
	if ctx.rng != sim.foe_rng:
		different.append("  rng: not the sim's foe_rng")
	if not ctx.sounds.is_empty():
		different.append("  sounds: %s between two ticks" % [ctx.sounds])
	if ctx.foes.size() != sim.foes.size():
		different.append("  foes: %d, the sim has %d creatures" % [ctx.foes.size(), sim.foes.size()])
	else:
		for i in sim.foes.size():
			if ctx.foes[i] != sim.foes[i].vm:
				different.append("  foes[%d]: not the VM of the sim's creature %d" % [i, i])
	for foe in sim.foes:
		if foe.on_screen != (foe.vm.screen == sim.screen_index):
			different.append("  creature %d: on_screen %s, it lives on screen %d and %d is shown" % [
					foe.vm.index, foe.on_screen, foe.vm.screen, sim.screen_index])
	assert_array(different).override_failure_message("after %s the creatures do not follow the sim:\n%s" % [path, "\n".join(different)]) \
			.is_empty()


# --- helpers --------------------------------------------------------------------------------------

func _new_state() -> Node:
	return auto_free(GAME_STATE_SCRIPT.new()) as Node


func _player(past_midpoint: bool) -> PlayerProfile:
	var player := PlayerProfile.new_player("Past" if past_midpoint else "Early", PlayerProfile.Game.VOYAGER)
	player.tanks = 3
	player.oxygen = 2
	player.ink = 12
	player.pieces_mask = 0b10
	player.hints_enabled = false
	player.customized = true
	player.progress = Progression.with_midpoint(player.progress, past_midpoint)
	return player


func _pieces_before_the_midpoint(sector: SectorData) -> Array[int]:
	var found: Array[int] = []
	for i in sector.pieces.size():
		if sector.pieces[i].screen < Tuning.resolve().midpoint_screen:
			found.append(i)
	return found


func _any_trigger(sim: SimWorld) -> TriggerModel:
	var on_screen := sim.triggers_on_screen(sim.screen_index)
	return on_screen[0] if not on_screen.is_empty() else null


static func _join(a: Array[StringName], b: Array[StringName]) -> Array[StringName]:
	var all: Array[StringName] = a.duplicate()
	all.append_array(b)
	return all


## The script's own member variables.
static func _variables(script: Script) -> Array[StringName]:
	var names: Array[StringName] = []
	for property in script.get_script_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(StringName(property["name"]))
	return names


## Every `*_FIELDS` constant of the script: its name -> the field names (the keys, for `KEPT_FIELDS`).
static func _scopes(script: Script) -> Dictionary:
	var scopes := {}
	var constants := script.get_script_constant_map()
	for constant_name in constants:
		if String(constant_name).ends_with("_FIELDS"):
			var value: Variant = constants[constant_name]
			var names: Array[StringName] = []
			for field in (value.keys() if value is Dictionary else value):
				names.append(StringName(field))
			scopes[String(constant_name)] = names
	return scopes


## Every field of every scope of the script except `KEPT_FIELDS`.
static func _fields(script: Script) -> Array[StringName]:
	var all: Array[StringName] = []
	var scopes := _scopes(script)
	for scope: String in scopes:
		if scope != "KEPT_FIELDS":
			all.append_array(scopes[scope])
	return all


## Gives each field a value that no reset leaves behind. Fails for a type it cannot change: teach it that type.
func _dirty_all(object: Object, fields: Array[StringName]) -> void:
	var classes := {}
	for property in object.get_script().get_script_property_list():
		classes[StringName(property["name"])] = property["class_name"]
	for field in fields:
		var value: Variant = object.get(field)
		match typeof(value):
			TYPE_BOOL:
				object.set(field, not value)
			TYPE_INT:
				object.set(field, value + 7)
			TYPE_FLOAT:
				object.set(field, value + 7.5)
			TYPE_VECTOR2:
				object.set(field, value + Vector2(7, 7))
			TYPE_VECTOR2I:
				object.set(field, value + Vector2i(7, 7))
			TYPE_DICTIONARY:
				if not (value as Dictionary).is_empty():
					(value as Dictionary).clear()
				else:
					(value as Dictionary)[&"dirty"] = 7
			TYPE_ARRAY:
				if not (value as Array).is_empty():
					(value as Array).clear()
				elif (value as Array).get_typed_builtin() == TYPE_INT:
					(value as Array).append(7)
				else:
					(value as Array).append(null)                       # (a typed array of objects takes null)
			TYPE_OBJECT:
				object.set(field, null)
			TYPE_NIL:
				var instance := _instance_of(classes.get(field, &""))
				assert_object(instance).override_failure_message("cannot dirty `%s` (null, class '%s')" % [field, classes.get(field)]).is_not_null()
				object.set(field, instance)
			_:
				fail("cannot dirty `%s` of type %s: teach `_dirty_all` that type" % [field, type_string(typeof(value))])


## A value of the class `global_class`: `new()`, or for a class whose `new` takes arguments, one of its own factories.
static func _instance_of(global_class: StringName) -> Object:
	if global_class == &"StationSequence":
		return StationSequence.balloon()
	for entry in ProjectSettings.get_global_class_list():
		if entry["class"] == global_class:
			return load(entry["path"]).new()
	return null


func _assert_same_fields(used: Object, fresh: Object, fields: Array[StringName], what: String) -> void:
	var different: Array[String] = []
	for field in fields:
		var got: Variant = _shape(used.get(field))
		var want: Variant = _shape(fresh.get(field))
		if got != want:
			different.append("  %s: %s, a fresh one has %s" % [field, str(got).left(200), str(want).left(200)])
	assert_array(different).override_failure_message("%s does not clear every field of its lifetime:\n%s" % [what, "\n".join(different)]) \
			.is_empty()


## A value as plain data that two objects can be compared by: an object by its script's variables (a few levels deep), a resource by
## its file (or itself).
static func _shape(value: Variant, depth: int = 3) -> Variant:
	if value is Resource:
		var resource := value as Resource
		return "resource " + (resource.resource_path if not resource.resource_path.is_empty() else str(resource.get_instance_id()))
	if value is Object:
		var object := value as Object
		if depth <= 0 or object.get_script() == null:
			return "object " + object.get_class()
		var fields := {}
		for field in _variables(object.get_script()):
			fields[field] = _shape(object.get(field), depth - 1)
		return fields
	if value is Array:
		var items := []
		for item: Variant in value:
			items.append(_shape(item, depth))
		return items
	if value is Callable or value is Signal:
		return "callable"
	return value
