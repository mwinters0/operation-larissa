class_name HeadlessStage
extends RefCounted
## Test helper: the playfield a `GameFlow` needs (`GameFlow.STAGE_METHODS`), made of nothing but a `SimWorld`. There is no node, no
## presenter and no clock: the trips at the supply stations are played by calling `sim.tick()` until the RULES say they are over,
## which is exactly what `SectorWorld` waits for in the game (`sequence_over`), only without the real time in between.
##
## What runs in the game runs here: the creatures tick in every tick, the trips included (the original's `ExitSupplyStation`,
## `EnterSupplyStation` and `LaunchBalloon` call `update_animals` too; only the sector viewer's pause freezes them). A test that wants
## the same creatures every time seeds `sim.foe_rng`. As `SectorWorld` does, the stage passes the dock on to the flow when the tick
## that reached it is over (`SimWorld.after_tick`), and a trip waits for `SimWorld.sequence_over`, which comes when the tick of the
## trip's last step is over: the flow goes on between two ticks only. A trip asked for while this stage runs a tick (the flow goes on
## at its end) is played by that `tick` after it.
##
## It plays the owner's part for the things the sim leaves to its owner: a lost tank is followed by the dissolve (`SimWorld.begin_dissolve`,
## the ticks of 1/73 s are fed by `finish_dissolve`), and the trips are ticked out. So a creature that takes the last air costs a tank
## here exactly as in `SectorWorld`, with no clock to hold.
##
## Teaches: what a "stage" is for the flow. `SectorWorld` is a node that owns a `SimWorld` and a presenter; the flow uses only the
## methods and signals listed here, so this much is all it takes to play a whole mission with plain objects (and
## "a whole sector runs headless with no presenter" starts from it).

signal problem_pending(slot: int)
signal problem_requested(slot: int)
signal dock_reached
signal finale_reached

var sim: SimWorld
var run: Object
## Every trip that was played, in order: &"launch", &"dock", &"balloon" (a test may point this at a shared log).
var log: Array = []
## The ticks the trips took, in the same order: the ticks of the stage in which the rules advanced the trip.
var trip_ticks: Array[int] = []
## True: the stage plays a trip's ticks itself, at once (a flow test calls `begin_sector`, `dock` ... and finds the trip over when the
## call returns). False: a trip only waits for the rules to end it, and whoever drives the stage ticks it (`SectorScenario`, which
## drives a `SectorWorld` the same way, so the two give the same trace).
var drives_trips: bool = true

var sector_index: int:
	get:
		return sim.sector_index
var sector: SectorData:
	get:
		return sim.sector

## True while `sim.tick` runs (a trip asked for now waits for the end of the tick, see the header).
var _ticking: bool = false
## Ticks in which the running trip advanced, counted by `_on_ticked`.
var _trip_advanced: int = 0
var _trip_last_elapsed: int = 0


func _init(game_run: Object) -> void:
	run = game_run
	sim = SimWorld.new(game_run)
	sim.problem_pending.connect(func(slot: int) -> void: problem_pending.emit(slot))
	sim.problem_requested.connect(func(slot: int) -> void: problem_requested.emit(slot))
	sim.dock_reached.connect(func() -> void: sim.after_tick(dock_reached.emit))     # (as `SectorWorld`: the flow goes on between ticks)
	sim.finale_reached.connect(func() -> void: finale_reached.emit())
	sim.damage_settled_by_owner = true
	sim.sub_damaged.connect(_on_sub_damaged)
	sim.sequence_started.connect(_on_sequence_started)
	sim.sequence_finished.connect(_on_sequence_finished)
	sim.ticked.connect(_on_ticked)


## `SectorWorld.begin_sector`: past the midpoint the sub is on screen 6; otherwise it drives out of the station (30 ticks).
func begin_sector(index: int, past_midpoint: bool = false) -> void:
	sim.begin_sector(index, past_midpoint)
	if not past_midpoint:
		await launch()


## The sub drives out of the start station (30 ticks).
func launch() -> void:
	sim.start_launch()
	await _play_trip(&"launch")


## One game tick of the rules (what `SectorWorld.tick` is in the game). A trip that a step of this tick asked for is played after it.
func tick(input: InputSnapshot = null) -> void:
	_tick(input)
	if drives_trips:
		_play_running_trips()


func dock() -> void:
	sim.start_dock()
	await _play_trip(&"dock")


func send_balloon() -> void:
	sim.start_balloon()
	await _play_trip(&"balloon")


func stop_flight() -> void:
	sim.stop_flight()


func make_problem(slot: int, rng: RandomNumberGenerator = null) -> ProblemInstance:
	if slot == SimWorld.CANISTER_SLOT:
		return ProblemFactory.for_canister(sector, run.edu_level, rng)
	return ProblemFactory.for_trigger_slot(slot, run.edu_level, rng)


func problem_resolved(slot: int, session: ProblemSession) -> void:
	sim.problem_resolved(slot, session)


func _tick(input: InputSnapshot) -> void:
	_ticking = true
	sim.tick(input)
	_ticking = false


## Waits for the rules to end the trip that was just started. Asked for outside a tick and driving the trips itself, the stage plays
## its ticks now; otherwise the tick that asked for it, or whoever drives the stage, plays them (`tick`).
func _play_trip(kind: StringName) -> void:
	log.append(kind)
	if drives_trips and not _ticking:
		var trip := sim.sequence
		while not trip.is_done():
			_tick(null)
		return
	await sim.sequence_over


## Plays the ticks of the trips that are running, one after the other (the dock's last tick starts the balloon).
func _play_running_trips() -> void:
	while sim.sequence != null and not sim.sequence.is_done():
		_tick(null)


func _on_sequence_started(_trip: StationSequence) -> void:
	_trip_advanced = 0
	_trip_last_elapsed = 0


## A tick of the stage in which the rules advanced the trip counts for it (a trip asked for in a tick before the sub's step runs its
## first tick there; one asked for after it, in the next).
func _on_ticked() -> void:
	if sim.sequence != null and sim.sequence.elapsed > _trip_last_elapsed:
		_trip_last_elapsed = sim.sequence.elapsed
		_trip_advanced += 1


func _on_sequence_finished(_trip: StationSequence) -> void:
	trip_ticks.append(_trip_advanced + 1)                    # (its last tick: `ticked` follows this signal)


## `SectorWorld._on_sub_damaged`: the last air of a tank starts the dissolve, any other hit is settled at once.
func _on_sub_damaged(_damage: int, tank_lost: bool) -> void:
	if tank_lost:
		sim.begin_dissolve()
	else:
		sim.settle_damage()


## Counts a dissolve out, one tick of 1/73 s at a time (the real time that `SectorWorld` feeds it); returns how many that took.
func finish_dissolve() -> int:
	var ticks := 0
	while sim.is_dissolving():
		sim.advance_dissolve(1)
		ticks += 1
	return ticks
