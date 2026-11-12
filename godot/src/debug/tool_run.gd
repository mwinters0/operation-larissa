class_name ToolRun
extends RefCounted
## The game's run as a tool scene plays it. The sector viewer, the skin comparison, the creature sandbox and the screen playtest start
## a sector, show a math problem and answer a lost tank or a lost game here, through the entries the game uses and with the game's
## timing, so that no tool can leave out a step of a transition (docs/engine/ARCHITECTURE.md, "Derived state is built from its owner").
##
## Teaches: one helper instead of a copy in every tool. What the game does lives in `GameFlow`, which needs the whole `Game` view (its
## dialogs, the music, the saves); a tool has none of that, so this class makes the same calls of the run (`GameState`) and the rules
## (`SectorWorld`), and only those:
##  * a sector starts with the run's half (`GameState.begin_sector`: nothing collected, the midpoint forgotten, a new life), then the
##    rules' half (`SectorWorld.load_sector`), as `GameFlow.complete_sector` and `GameFlow.restart` start the next one;
##  * a problem the rules ask for is shown over the tool (`ProblemRunner`) and its outcome goes back to the rules
##    (`SectorWorld.problem_resolved`), as `GameFlow.open_problem` does;
##  * a lost tank and a game over are answered a little LATER (`defer_call`, as `GameFlow._on_tank_lost` and `_on_game_over`). A
##    problem that costs the tank announces the loss while it closes, before `problem_resolved` has run, and that call (which takes
##    the canister back when the canister's problem cost the tank) must still find the sector it belongs to, not the new one.
##
## The tool keeps the object (`var run := ToolRun.new(world, self)`); it listens for as long as it lives.

## The world the tool shows.
var world: SectorWorld
## The node a problem screen is put on.
var host: Node
## Runs a call "a little later, outside the signal that asked for it": `call_deferred`, as `GameFlow.defer_call`. A test may collect
## the calls and run them itself.
var defer_call: Callable = func(action: Callable) -> void: action.call_deferred()

## What a lost tank or a lost game does instead of the game's answer (the screen playtest starts its setup over); empty: the game's.
var _start_over: Callable


func _init(sector_world: SectorWorld, problem_host: Node, start_over: Callable = Callable()) -> void:
	world = sector_world
	host = problem_host
	_start_over = start_over
	GameState.tank_lost.connect(_on_tank_lost)
	GameState.game_over.connect(_on_game_over)
	world.problem_requested.connect(open_problem)


## Starts sector `index` on `screen` as the game starts a sector: the run's half, then the rules'. (The sub is not placed: a tool
## that flies calls `SectorWorld.start_flight` after it.)
func begin_sector(index: int, screen: int = 0) -> void:
	GameState.begin_sector()
	world.load_sector(index, screen)


## Shows the problem of trigger `slot` over the tool and tells the rules how it went (`GameFlow.open_problem`).
func open_problem(slot: int) -> void:
	var problem := world.make_problem(slot)
	if problem == null:                                   # (`ProblemFactory` told why)
		world.problem_resolved(slot, ProblemSession.not_made())
		return
	var session := await ProblemRunner.run(host, problem)
	world.problem_resolved(slot, session)


## A spare tank takes over (`GameFlow.respawn`): a fresh tank, and a flying sub starts the sector again (screen 6 past the midpoint).
func respawn() -> void:
	if _start_over.is_valid():
		_start_over.call()
		return
	GameState.respawn()
	if world.sim.sub.active:
		world.begin_sector(world.sector_index, GameState.past_midpoint)


## No tank left (`GameFlow.restart`): the sector starts over with nothing collected, and a flying sub launches again.
func restart() -> void:
	if _start_over.is_valid():
		_start_over.call()
		return
	GameState.restart_sector()
	if world.sim.sub.active:
		world.begin_sector(world.sector_index, false)


func _on_tank_lost(_code: int) -> void:
	defer_call.call(respawn)


func _on_game_over() -> void:
	defer_call.call(restart)
