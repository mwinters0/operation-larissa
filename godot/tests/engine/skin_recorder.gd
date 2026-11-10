class_name SkinRecorder
extends SectorPresenter
## Test helper: a presenter written the way a SKIN is written - against `view` only. It sets `sim` to null right after `bind`, so
## everything it knows comes through the skin API (`SimView`), and it listens to EVERY event in `SimView.EVENTS`.
##
## For each event it keeps
##   `lines`   the event as the line `SimTrace.listen` writes for the same event of the rules (built from the event's copies only),
##             so a test can compare what the skin heard with what the rules said;
##   `calls`   [event name, the arguments, `view.tick_number`, the step of the tick (see `step_of`)], to check the data and the timing.
## and `fractions`, every tick fraction `show_between_ticks` was given.
##
## Teaches: what "enough data" means. If the recorder can write the rules' own trace line from the copies, a skin has what it needs.

## Asks the test which step of the tick is running ("" between ticks). Set before the sim runs; optional.
var step_of: Callable = Callable()
var lines: Array[String] = []
var calls: Array = []
var fractions: Array[float] = []


func bind(sim_world: SimWorld) -> void:
	super.bind(sim_world)
	sim = null                                             # (a skin has no handle on the rules: only `view`)
	_listen(view.ticked, func() -> void: _rec(&"ticked", "", []))
	_listen(view.sector_loaded, func(index: int) -> void: _rec(&"sector_loaded", "sector_loaded %d" % index, [index]))
	_listen(view.screen_loaded, func(index: int, screen: int) -> void: _rec(&"screen_loaded", "screen_loaded %d %d" % [index, screen], [index, screen]))
	_listen(view.screen_changed, func(screen: int, direction: int) -> void: _rec(&"screen_changed", "screen %d %d" % [screen, direction], [screen, direction]))
	_listen(view.sound_requested, func(sfx: StringName) -> void: _rec(&"sound_requested", "sfx %s" % sfx, [sfx]))
	_listen(view.creature_picture_changed, func(c: SimView.CreatureState, picture: int) -> void: _rec(&"creature_picture_changed", "picture %d %d" % [c.index, picture], [c, picture]))
	_listen(view.creature_mirror_changed, func(c: SimView.CreatureState, mirrored: bool) -> void: _rec(&"creature_mirror_changed", "mirror %d %s" % [c.index, mirrored], [c, mirrored]))
	_listen(view.creature_visibility_changed, func(c: SimView.CreatureState, shown: bool) -> void: _rec(&"creature_visibility_changed", "shown %d %s" % [c.index, shown], [c, shown]))
	_listen(view.creature_hit_by_ink, func(c: SimView.CreatureState) -> void: _rec(&"creature_hit_by_ink", "ink_hit %d" % c.index, [c]))
	_listen(view.creature_hit_by_sub, func(c: SimView.CreatureState) -> void: _rec(&"creature_hit_by_sub", "sub_hit %d" % c.index, [c]))
	_listen(view.sub_damaged, func(damage: int, tank_lost: bool) -> void: _rec(&"sub_damaged", "damaged %d %s" % [damage, tank_lost], [damage, tank_lost]))
	_listen(view.piece_collected, func(p: SimView.PieceState) -> void: _rec(&"piece_collected", "piece %d %s" % [p.index, Vector2i(p.position + SubModel.PLAYFIELD_ORIGIN)], [p]))
	_listen(view.pieces_reset, func() -> void: _rec(&"pieces_reset", "pieces_reset", []))
	_listen(view.trigger_fired, func(t: SimView.TriggerState) -> void: _rec(&"trigger_fired", "trigger %d %d" % [t.screen, t.index], [t]))
	_listen(view.pellet_fired, func(p: SimView.PelletState) -> void: _rec(&"pellet_fired", "pellet_fired %d" % p.id, [p]))
	_listen(view.pellet_splashed, func(p: SimView.PelletState) -> void: _rec(&"pellet_splashed", "pellet_splashed %d" % p.id, [p]))
	_listen(view.pellet_gone, func(p: SimView.PelletState) -> void: _rec(&"pellet_gone", "pellet_gone %d" % p.id, [p]))
	_listen(view.sub_placed, func(s: SimView.SubState) -> void: _rec(&"sub_placed", "", [s]))
	_listen(view.problem_pending, func(slot: int) -> void: _rec(&"problem_pending", "pending %d" % slot, [slot]))
	_listen(view.beacon_changed, func(lit: bool) -> void: _rec(&"beacon_changed", "beacon %s" % lit, [lit]))
	_listen(view.problem_requested, func(slot: int) -> void: _rec(&"problem_requested", "requested %d" % slot, [slot]))
	_listen(view.problem_finished, func(slot: int, solved: bool) -> void: _rec(&"problem_finished", "problem_finished %d solved=%s" % [slot, solved], [slot, solved]))
	_listen(view.dock_reached, func() -> void: _rec(&"dock_reached", "dock", []))
	_listen(view.finale_reached, func() -> void: _rec(&"finale_reached", "finale", []))
	_listen(view.sequence_started, func(s: SimView.SequenceState) -> void: _rec(&"sequence_started", "trip_started %d ticks=%d" % [s.kind, s.ticks], [s]))
	_listen(view.sequence_finished, func(s: SimView.SequenceState) -> void: _rec(&"sequence_finished", "trip_finished %d" % s.kind, [s]))
	_listen(view.dissolve_started, func(ticks: int) -> void: _rec(&"dissolve_started", "dissolve_started %d" % ticks, [ticks]))
	_listen(view.dissolve_advanced, func(elapsed: int, ticks: int) -> void: _rec(&"dissolve_advanced", "dissolve_advanced %d" % elapsed, [elapsed, ticks]))
	_listen(view.dissolve_finished, func() -> void: _rec(&"dissolve_finished", "dissolve_finished", []))


func show_between_ticks(fraction: float) -> void:
	fractions.append(fraction)


func _rec(event: StringName, line: String, args: Array) -> void:
	if not line.is_empty():
		lines.append(line)
	var step := ""
	if step_of.is_valid():
		step = step_of.call()
	calls.append([event, args, view.tick_number, step])


## The calls of one event.
func calls_of(event: StringName) -> Array:
	return calls.filter(func(call: Array) -> bool: return call[0] == event)
