class_name SectorScenario
extends RefCounted
## Test helper: one scripted visit to a sector, the same every time. The launch from the station, a flight with scripted hands (the
## creatures are awake and the ink flies), a math trigger that opens a problem, the data canister whose problem costs the tank, a
## creature that takes the last air of a tank so the sub dissolves, the dock and the balloon - or, in the finale sectors, the touch of
## the treasure and the closing. Everything the rules did is in `trace` (`SimTrace`): every event with its tick, the whole state after
## every tick, and how many ticks each trip and dissolve took.
##
## Teaches: one script for many shells. The scenario talks to a STAGE: `sim`, `tick(input)` and the stage methods of `GameFlow`. That
## is `HeadlessStage` (plain objects) or a `SectorWorld` with whichever presenter it has; both wait for the rules to end a trip, and
## this script runs the ticks. The trace is the same with all of them, because the presenter is the one thing that differs, and a
## presenter cannot change a rule.
##
## Harnesses take the game's paths (docs/engine/ARCHITECTURE.md, "Derived state is built from its owner"). Around the stage is the
## game's own `GameFlow`, in free play, with a view that writes down what it is asked (`ScenarioView`): the flow starts the sector,
## answers the problems (`open_problem`), respawns the sub after a lost tank (`respawn`: `GameState.respawn`, then the sector begins
## again on the station or on screen 6), starts the sector over at game over, opens the lock at the dock and completes the sector
## (`complete_sector`: the creatures start over, the dock, the balloon), and plays the closing. The creatures tick wherever they tick
## in the game, the trips included, with the dice seeded once (`SEED`) before the sector is loaded. What the script does that the
## player cannot: it moves the sub to a screen (`_enter_screen`, which enters it as a flight does), places it (`start_flight`) and
## takes a piece where it lies (`SimWorld.take_piece`, the debug key 3).

const SEED := 4242
const FLY_TICKS := 120
## The most ticks a trip, a trigger or the dock may take before the script gives up (a test then fails on what is missing).
const LIMIT := 300
const TRIP_NAMES := {StationSequence.Kind.LAUNCH: "launch", StationSequence.Kind.DOCK: "dock", StationSequence.Kind.BALLOON: "balloon"}


## The view of the flow for a scripted visit: `FakeFlowView`, whose problem screens stay up until the script answers them (`_answer`).
class ScenarioView:
	extends FakeFlowView
	## Problem screens that are up.
	var problems_open: int = 0

	func show_problem(problem: ProblemInstance, calculator_allowed: bool, after_prompt: Callable) -> ProblemSession:
		problems_open += 1
		var session: ProblemSession = await super.show_problem(problem, calculator_allowed, after_prompt)
		problems_open -= 1
		return session


var stage: Object
var sim: SimWorld
var run: Object
var trace: SimTrace
var flow: GameFlow
var view: ScenarioView
## Called after every tick of the flight (a test swaps the presenter here: not from inside a signal of the sim, whose handlers the old
## presenter would still be asked to answer).
var after_tick: Callable = Callable()
## What the flow put off "a little later" (the respawn, the restart), run between two ticks as the idle frame does.
var _later: Array[Callable] = []
## The next problem the script answers costs the tank (the canister's).
var _next_answer_costs_the_tank: bool = false
## How many problems the script has answered.
var _answered: int = 0
## The running trip: the ticks in which the rules advanced it.
var _trip_advanced: int = 0
var _trip_last_elapsed: int = 0
## Trips that ended, with their ticks, for the trace (`_note_trips`).
var _trips_done: Array[String] = []


func _init(game_stage: Object, game_run: Object) -> void:
	stage = game_stage
	sim = game_stage.sim
	run = game_run
	if stage is HeadlessStage:
		(stage as HeadlessStage).drives_trips = false                    # (this script ticks the trips, as it does a `SectorWorld`'s)
	trace = SimTrace.record(sim, run)
	sim.sequence_started.connect(_on_sequence_started)
	sim.sequence_finished.connect(_on_sequence_finished)
	sim.ticked.connect(_on_ticked)
	view = ScenarioView.new([], run)
	view.hold(&"problem")
	var store := FakeSaveStore.new()
	flow = GameFlow.new(run, store, MessageQueue.new(StubClock.new()))
	flow.world = stage
	flow.view = view
	flow.defer_call = func(action: Callable) -> void: _later.append(action)


## The whole visit to `sector`, in free play (a player who is never saved), or as `player` (a player of a campaign, whose run has begun: `run.begin_run(player)`, so the rule hooks of the campaign are the run's). The campaign of the
## visit is the one sector, and its last: the dock ends the visit with the supply message, the balloon and the refill, and starts no other sector.
func play(sector: int, player: PlayerProfile = null) -> void:
	sim.foe_rng.seed = SEED
	run.profile = player
	flow.enter(sector, 0)
	flow.store.watched = flow.profile
	run.hints.enabled = false                                              # (the hints are the message line's, not the rules')
	var visit := Campaign.new()
	visit.sectors = PackedInt32Array([sector])
	visit.finales = PackedInt32Array([sector])
	flow.campaign = visit
	_run_flow(flow.begin_mission)
	_fly(FLY_TICKS, SimTrace.Hands.new(sector, 0))
	if SimWorld.finale_screen(sector) >= 0:
		_finale(sector)
	else:
		_screen_change()
		_problem()
		_canister_costs_the_tank()
		_tank_loss()
		_dock()
	flow.leave()


# --- the owner's part between two ticks ---------------------------------------------------------------

## One tick with `input`, and then what the owner of the sector does before the next one (`_settle`).
func _step(input: InputSnapshot) -> void:
	stage.tick(input)
	_note_trips()
	_settle()


## What happens between two ticks in the game: a problem that is up is answered (the clock is held while it is), a dissolve runs out
## (the clock is held for it too), a message that waits is closed, and what the flow put off runs.
func _settle() -> void:
	if view.problems_open > 0:
		_answer()
	if sim.is_dissolving():
		_dissolve()
	if flow.messages.is_open():
		flow.messages.close_current()
	while not _later.is_empty():
		_run_flow(_later.pop_front())


## Runs a step of the flow (a coroutine that may wait for the rules' ticks: a trip) and ticks, with nobody's hands, until it has
## returned.
func _run_flow(call: Callable) -> void:
	var done := [false]
	(func() -> void:
		await call.call()
		done[0] = true).call()
	var t := 0
	while not done[0] and t < LIMIT:
		_step(null)
		t += 1


## The player is done with the problem on the screen: the flow tells the rules (`problem_resolved`) and plays the song again. A problem
## that costs the tank is played the way `ProblemScreen` plays it: it holds the run's losses while it is up, the misses take the air,
## and the lost tank is let through when the screen has closed (the flow respawns the sub a little later).
func _answer() -> void:
	var costs := _next_answer_costs_the_tank
	_next_answer_costs_the_tank = false
	if costs:
		run.hold_losses()
		view.oxygen_code = run.update_oxygen(-run.oxygen())
	view.release(&"problem")
	view.hold(&"problem")
	view.oxygen_code = OxygenModel.OK
	if costs:
		run.release_losses()
	_answered += 1


## Counts a dissolve out in ticks of 1/73 s, as the owner does with the real time that goes by.
func _dissolve() -> void:
	var ticks := 0
	while sim.is_dissolving():
		sim.advance_dissolve(1)
		ticks += 1
	trace.flush("dissolve of %d ticks" % ticks)


func _on_sequence_started(_trip: StationSequence) -> void:
	_trip_advanced = 0
	_trip_last_elapsed = 0


## A tick in which the rules advanced the running trip counts for it.
func _on_ticked() -> void:
	var trip := sim.sequence
	if trip != null and trip.elapsed > _trip_last_elapsed:
		_trip_last_elapsed = trip.elapsed
		_trip_advanced += 1


## Its last tick ends it (`ticked` follows this signal; the dock's last tick may start the balloon).
func _on_sequence_finished(trip: StationSequence) -> void:
	_trips_done.append("%s took %d ticks" % [TRIP_NAMES[trip.kind], _trip_advanced + 1])


func _note_trips() -> void:
	for note in _trips_done:
		trace.flush(note)
	_trips_done.clear()


# --- the steps --------------------------------------------------------------------------------

## Flies `ticks` ticks with the scripted hands; the owner's part is done after each (a lost tank: the dissolve and the respawn).
func _fly(ticks: int, hands: SimTrace.Hands) -> void:
	for t in ticks:
		_step(hands.at(t))
		if after_tick.is_valid():
			after_tick.call()
	trace.flush("flight of %d ticks" % ticks)


## The sub is moved to `screen` of the sector (the script does not steer it there). The screen is entered as a flight enters it
## (`SimWorld._on_sub_crossed_edge`): the rules lay it out, and the run is told the screen was entered (the midpoint).
func _enter_screen(screen: int) -> void:
	sim.load_screen(screen)
	run.screen_entered(screen, sim.sector)


## The sub swims out of the right edge of screen 0 along a row of open water, into the next screen (the rules switch screens).
func _screen_change() -> void:
	_enter_screen(0)
	if sim.neighbor(0, SectorData.Direction.RIGHT) < 0:
		return
	var grid := sim.tile_grid
	for row in range(1, TileGrid.ROWS - 3):                      # the sub's wall box is 32 px high: three rows of open water
		var free := true
		for dy in 3:
			for column in range(TileGrid.COLUMNS - 8, TileGrid.COLUMNS):
				free = free and not grid.is_solid(column, row + dy)
		if free:
			sim.start_flight(520, row * TileGrid.TILE_SIZE + 32 - 8, 6)
			var t := 0
			while sim.screen_index == 0 and t < LIMIT:
				_step(InputSnapshot.steering(1, 0))
				t += 1
			trace.flush("screen change after %d ticks" % t)
			return


## The sub swims into the first math trigger of the sector; the problem opens after the rules' countdown and the flow shows it.
func _problem() -> void:
	var found := sim.triggers.filter(func(t: TriggerModel) -> bool: return t.data.slot != SimWorld.CANISTER_SLOT)
	if found.is_empty():
		return
	var trigger: TriggerModel = found[0]
	_enter_screen(trigger.screen)
	sim.start_flight(trigger.data.pos.x - 40, trigger.data.pos.y - 25, 6)
	var before := _answered
	var t := 0
	while _answered == before and t < LIMIT:
		_step(null)
		t += 1
	trace.flush("problem of slot %d after %d ticks" % [trigger.data.slot, t])


## The sub takes the data canister where it lies; its problem opens and the air runs out in it. The tank is lost when the problem
## closes, the canister is to be collected again (`SimWorld.problem_resolved`), and the flow respawns the sub.
func _canister_costs_the_tank() -> void:
	if sim.sector.pieces.is_empty() or run.has_piece(0):
		return
	_enter_screen(sim.sector.pieces[0].screen)
	sim.start_flight()
	sim.take_piece(0)
	_next_answer_costs_the_tank = true
	var before := _answered
	var t := 0
	while _answered == before and t < LIMIT:
		_step(null)
		t += 1
	_next_answer_costs_the_tank = false
	trace.flush("canister problem after %d ticks" % t)


## A creature that hurts takes the last of the air: the sub dissolves (21 ticks of 1/73 s), the tank is lost and the flow respawns
## the sub.
func _tank_loss() -> void:
	var hurts := sim.foes.filter(func(f: FoeModel) -> bool: return f.vm.damage > 0 and not f.vm.hidden and not f.vm.interrupted)
	if hurts.is_empty():
		return
	var foe: FoeModel = hurts[0]
	_enter_screen(foe.vm.screen)
	sim.start_flight()                                              # (not invulnerable from an earlier hit)
	if run.oxygen() > foe.vm.damage:
		run.update_oxygen(foe.vm.damage - run.oxygen())            # (the air that is left is what the creature takes)
	sim.sub_touches(foe)
	_settle()
	trace.flush("tank lost to creature %d" % foe.vm.index)


## Every piece the sub has not got is taken where it lies; the sub enters the dock rectangle, the flow opens the lock (answered), the
## creatures start over, the sub docks, the supply message, the balloon.
func _dock() -> void:
	for i in sim.sector.pieces.size():
		if run.has_piece(i):
			continue
		_enter_screen(sim.sector.pieces[i].screen)
		sim.start_flight()
		sim.take_piece(i)
		_step(null)
	var t := 0
	while sim.pending_slot >= 0 and t < LIMIT:                       # (the canister's problem opens and is answered)
		_step(null)
		t += 1
	_enter_screen(SimWorld.DOCK_SCREEN)
	sim.start_flight(400, 200, 6)
	t = 0
	while trace.events_like("dock").is_empty() and t < LIMIT:
		_step(null)
		t += 1
	trace.flush("dock rectangle after %d ticks" % t)
	t = 0
	while flow.busy and t < LIMIT:
		_step(null)
		t += 1
	trace.flush("the sector is done")


## The finale sector: the sub touches the treasure (a creature sets the semaphore bit), then it swims onto the closing screen and the
## flow plays the closing.
func _finale(sector: int) -> void:
	var treasure := sim.foes[0]
	_enter_screen(treasure.vm.screen)
	sim.sub.invulnerability = 100                    # (no creature takes the tank while the treasure is touched)
	sim.sub_touches(treasure)
	for t in 4:
		_step(null)
	_enter_screen(SimWorld.finale_screen(sector))
	_step(null)
	trace.flush("finale")
