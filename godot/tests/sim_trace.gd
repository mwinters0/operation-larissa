class_name SimTrace
extends RefCounted
## Test helper: writes down what the rules do, as text, so that two runs can be compared line by line. Two pieces:
##   `listen(sim, into)`      every event of the `SimWorld` as one line, in the order they happen
##   `state_line(sim, run, t)` everything the rules know at the end of tick `t`, as one line
## `record(sim, run)` joins them: it keeps one `SimTrace` that is told by `ticked` when a tick is over, whoever ran it (a test loop,
## a `SectorWorld`, the stage of a flow, a supply trip that ticks by itself), and counts the ticks.
##
## Teaches: why "the same game" can be a test. The rules are deterministic (the creature scripts roll the sim's own dice, the hands
## are scripted), so what they did is a list of lines. A presenter cannot change a line, because it cannot change a rule.

## The hands for tick `t` of a scripted flight: a random walk of the arrow keys that changes every 7 ticks, and Space now and then.
## The same `sector` and `screen` always give the same hands.
class Hands:
	extends RefCounted
	var _rng := RandomNumberGenerator.new()
	var _steer := Vector2i.ZERO

	func _init(sector: int, screen: int) -> void:
		_rng.seed = 99 + sector * 7 + screen

	func at(t: int) -> InputSnapshot:
		if t % 7 == 0:
			_steer = Vector2i(_rng.randi_range(-1, 1), _rng.randi_range(-1, 1))
		var input := InputSnapshot.steering(_steer.x, _steer.y)
		input.fire_presses = 1 if _rng.randf() < 0.3 else 0
		return input


## The events, one line each. `T<n>` is put in front of an event by `record`: the number of the tick it happened in.
var lines: Array[String] = []
## How many ticks have run since `record`.
var ticks: int = 0
var _sim: SimWorld
var _run: Object
## The events of the tick that is running (`listen` fills it, `_on_ticked` and `flush` empty it into `lines`).
var _events_feed: Array[String] = []


## Starts a trace that follows `sim` (and `run`, the player's numbers): every event and, after every tick, the state line.
static func record(sim: SimWorld, run: Object) -> SimTrace:
	var trace := SimTrace.new()
	trace._sim = sim
	trace._run = run
	listen(sim, trace._events_feed)
	sim.ticked.connect(trace._on_ticked)
	return trace


func _on_ticked() -> void:
	for event in _events_feed:
		lines.append("T%d %s" % [ticks, event])
	_events_feed.clear()
	lines.append(state_line(_sim, _run, ticks))
	ticks += 1


## The events that happened outside a tick (loading a sector, a hit by hand) are kept too: call this when a step of a scenario is
## over, so they are in the trace before the next tick's.
func flush(note: String = "") -> void:
	for event in _events_feed:
		lines.append("T%d %s" % [ticks, event])
	_events_feed.clear()
	if not note.is_empty():
		lines.append("-- " + note)


## The events so far whose text begins with `prefix` ("dock", "dissolve_finished", "requested "), as the lines of the trace.
func events_like(prefix: String) -> Array[String]:
	var found: Array[String] = []
	for line in lines:
		if line.begins_with("T") and line.substr(line.find(" ") + 1).begins_with(prefix):         # (the text after "T<tick> ")
			found.append(line)
	return found


## One line with everything the rules know at the end of a tick.
static func state_line(sim: SimWorld, run: Object, t: int) -> String:
	var s := sim.sub
	var parts: Array[String] = ["T%d scr=%d sub=%s cell=%d v=%s inv=%d act=%s ctl=%s light=%s pend=%d/%d pa=%s" % [
			t, sim.screen_index, s.original_position(), s.cell, s.velocity_units, s.invulnerability, s.active, s.controlled,
			s.message_light, sim.pending_slot, sim.pending_ticks, sim.problem_active]]
	parts.append("ink=%d ox=%d/%d mask=%d sem=%d" % [run.ink, run.tanks(), run.oxygen(), run.pieces_mask, sim.foe_context.semaphore])
	for foe in sim.foes:
		var v := foe.vm
		parts.append("f%d:%d,%d,%d,%s,%s,%s,%d,%s,%d,%s" % [
				v.index, v.x, v.y, v.frame, v.flip, v.hidden, v.dormant, v.screen, v.interrupted, v.pc, v.jumped])
	for pellet in sim.pellets:
		parts.append("p%s,%d,%d" % [Vector2i(pellet.position), pellet.state, pellet.splash_picture])
	var pieces: Array[int] = []
	for piece in sim.pieces:
		pieces.append(piece.index)
	parts.append("pieces=%s" % [pieces])
	var armed: Array[String] = []
	for trigger in sim.triggers_on_screen(sim.screen_index):
		armed.append("%d%s" % [trigger.index, "A" if trigger.armed else "-"])
	parts.append("trig=%s" % [armed])
	return " ".join(parts)


## Appends a line to `into` for every event `sim` emits from now on.
static func listen(sim: SimWorld, into: Array[String]) -> void:
	sim.sector_loaded.connect(func(index: int) -> void: into.append("sector_loaded %d" % index))
	sim.screen_loaded.connect(func(index: int, screen: int) -> void: into.append("screen_loaded %d %d" % [index, screen]))
	sim.screen_changed.connect(func(screen: int, direction: int) -> void: into.append("screen %d %d" % [screen, direction]))
	sim.sound_requested.connect(func(sfx: StringName) -> void: into.append("sfx %s" % sfx))
	sim.creature_picture_changed.connect(func(foe: FoeModel, picture: int) -> void: into.append("picture %d %d" % [foe.vm.index, picture]))
	sim.creature_mirror_changed.connect(func(foe: FoeModel, mirrored: bool) -> void: into.append("mirror %d %s" % [foe.vm.index, mirrored]))
	sim.creature_visibility_changed.connect(func(foe: FoeModel, shown: bool) -> void: into.append("shown %d %s" % [foe.vm.index, shown]))
	sim.creature_hit_by_ink.connect(func(foe: FoeModel) -> void: into.append("ink_hit %d" % foe.vm.index))
	sim.creature_hit_by_sub.connect(func(foe: FoeModel) -> void: into.append("sub_hit %d" % foe.vm.index))
	sim.sub_damaged.connect(func(damage: int, tank_lost: bool) -> void: into.append("damaged %d %s" % [damage, tank_lost]))
	sim.piece_collected.connect(func(piece: PieceModel, at: Vector2i) -> void: into.append("piece %d %s" % [piece.index, at]))
	sim.pieces_reset.connect(func() -> void: into.append("pieces_reset"))
	sim.trigger_fired.connect(func(trigger: TriggerModel) -> void: into.append("trigger %d %d" % [trigger.screen, trigger.index]))
	sim.pellet_fired.connect(func(pellet: PelletModel) -> void: into.append("pellet_fired %d" % pellet.id))
	sim.pellet_splashed.connect(func(pellet: PelletModel) -> void: into.append("pellet_splashed %d" % pellet.id))
	sim.pellet_gone.connect(func(pellet: PelletModel) -> void: into.append("pellet_gone %d" % pellet.id))
	sim.problem_pending.connect(func(slot: int) -> void: into.append("pending %d" % slot))
	sim.beacon_changed.connect(func(lit: bool) -> void: into.append("beacon %s" % lit))
	sim.problem_requested.connect(func(slot: int) -> void: into.append("requested %d" % slot))
	sim.problem_finished.connect(func(slot: int, session: ProblemSession) -> void: into.append("problem_finished %d solved=%s" % [slot, session.solved]))
	sim.dock_reached.connect(func() -> void: into.append("dock"))
	sim.finale_reached.connect(func() -> void: into.append("finale"))
	sim.sequence_started.connect(func(trip: StationSequence) -> void: into.append("trip_started %d ticks=%d" % [trip.kind, trip.ticks]))
	sim.sequence_finished.connect(func(trip: StationSequence) -> void: into.append("trip_finished %d" % trip.kind))
	sim.dissolve_started.connect(func(count: int) -> void: into.append("dissolve_started %d" % count))
	sim.dissolve_advanced.connect(func(elapsed: int) -> void: into.append("dissolve_advanced %d" % elapsed))
	sim.dissolve_finished.connect(func() -> void: into.append("dissolve_finished"))
