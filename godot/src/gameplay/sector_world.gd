class_name SectorWorld
extends Control
## The playfield: one screen of one sector. The RULES are not here: they are the `SimWorld` this node owns (`sim`,
## src/rules/sim_world.gd), a plain object that steps the sub, the creatures, the pellets, the pieces and the triggers once per game
## tick. The PICTURE is not here either: it is the `SectorPresenter` this node has as a child (`presenter`, by default the
## `OriginalPresenter`), which draws what `sim` says. This node sits between them: it hands the rules the player's hands, runs them
## once per tick, passes the tick fraction to the presenter every frame, tells the owner (`Game`, a debug scene, a test) what happened,
## and sequences the things that take time.
##
## Teaches:
##  * where to cut a game in two: the rules know nothing of the presenter, the presenter reads the rules and never changes them, and
##    this node is the only one that knows both. A different presentation (the debug rectangles, a skin) is one node
##    swapped in (`replace_presenter`); nothing else changes, and the game plays the same.
##  * `Control.clip_contents` to cut off anything that sticks out of the window
##
## The playfield is 608 x 288 pixels (38 x 18 tiles of 16 x 16). The viewer scene places this node at (16, 32) of the 640 x 400 screen.
##
## Why one owner and a child presenter, and not a presenter that owns the rules (or this node split in two scenes): the owner has
## things that belong to neither the rules nor the picture - the connection to the clock, the keyboard, the flow signals that `GameFlow`
## listens to - and keeping them in one small node means a presenter only has to implement `SectorPresenter` and never sees them.
##
## When the sub's centre leaves the playfield the sim switches screens (or clamps the sub at the edge when there is none) and tells
## this node with `screen_loaded` / `screen_changed`.
##
## THE TICK. Everything that decides a rule happens in `SimWorld.tick`, once per `GameClock` tick, in the order of the
## original's `DoAction` (`SimWorld.TICK_ORDER`); `tick` here takes the player's hands (`take_input`) and runs it. This node is the ONE
## connection of the rules to the clock. The presenter follows by the events of the sim, and by `show_between_ticks` once per frame.
##
## THE INPUTS OF THE RULES. The rules never ask `Input` or a `TileMapLayer`: the walls and the currents they use are a
## `TileGrid` built from the screen's tile bytes (`tile_grid`), and the player's hands arrive as an `InputSnapshot` taken once per tick
## by this node (`take_input`, filled by an `InputReader` that counts the presses that happen between two ticks).
##
## WHAT TAKES TIME IS THE RULES'. The sub dissolving after a lost tank, the door and the drive of the supply stations
## (`launch`, `dock`) and the balloon are counted in ticks by the `SimWorld`; the presenter is told "you have N ticks" and shows them,
## and this node waits for the RULES to say they are over (`SimWorld.sequence_over`, `dissolve_finished`), never for a picture.
## So a presenter that draws nothing holds play up for exactly as long as the original one. What this node adds is the real time:
## the supply trips run in the game clock's ticks, and the dissolve - for which the clock is held, the original being busy inside
## one call - is fed the real time that goes by (`TickMeter`), because no tick runs to count it.
##
## NOTHING ITS OWNER DOES RUNS INSIDE A TICK. The flow (`GameFlow`) goes on only between two ticks: a trip it waits for returns when
## the tick of its last step is over (`SimWorld.sequence_over`), and the dock reaches the flow through `SimWorld.after_tick`, so the
## lock, the reload of the creatures, the trips and the next sector all begin between ticks (docs/engine/ARCHITECTURE.md, "Nothing the
## owner does runs inside a tick"). The finale is said in its step: the original runs the closing inside the pass.
##
## It also does the start of a sector with the launch from the station (`begin_sector`) and the midpoint bookkeeping (the run's
## `screen_entered` after every screen change, `update_midpoint` after every pickup, both in the sim).

## Emitted after a screen has been (re)built.
signal screen_loaded(sector_index: int, screen_index: int)
## Emitted when the sub flew into the neighbouring screen through `direction`
## (not for `load_screen` / `go` calls made by code).
signal screen_changed(screen_index: int, direction: SectorData.Direction)
## Something wants a sound effect played (a creature script, the sub's gun, a hit, the station's door).
## `sfx` is the `sound` NAME of the effect (names/original.json): the receiver looks it up (`Audio.play_sfx`). The world forwards
## its own requests to the `Audio` autoload (see `_ready`); the signal stays so that tests and tools can watch them too.
signal sfx_requested(sfx: StringName)
## A math trigger was touched: the light on the sub blinks until the problem opens.
signal problem_pending(slot: int)
## Time to show a problem for this trigger slot (1 = data canister). The owner builds the
## ProblemScreen (see `make_problem`) and later calls `problem_resolved`.
signal problem_requested(slot: int)
## The owner reported the outcome of a problem.
signal problem_finished(slot: int, session: ProblemSession)
## The sub drove into the dock rectangle of the last screen (once per visit): time for the lock, or
## for the "ship's magnetometer" message when pieces are missing. Said when the tick that reached it is over (`SimWorld.after_tick`).
signal dock_reached
## The ending of the game begins: the sub is on the finale screen and a creature has set the semaphore bit
## (`SimWorld.finale_screen`). Emitted once per `load_sector`; `GameFlow` starts the closing sequence.
signal finale_reached

## Tests and debug scenes set this to skip the door and driving animations (the sub just appears
## where the launch would have left it). A `static var` belongs to the class, not to one node.
static var skip_animations: bool = false

## The rules of the sector this node shows. Everything that decides what happens is in here.
var sim := SimWorld.new(GameState)
## Counts the key presses that happen between two ticks (see `take_input`).
var _input_reader := InputReader.new()
## Turns the real time of the dissolve into the ticks the rules count (`_process`).
var _dissolve_meter := TickMeter.new()
## True while this node holds the game clock for a dissolve (`_on_sub_damaged` .. `_release_dissolve_clock`).
var _dissolve_holds_clock: bool = false

# What the rules know, for the tests and tools that ask the world (the setters write through).
var sector: SectorData:
	get:
		return sim.sector
var sector_index: int:
	get:
		return sim.sector_index
var screen_index: int:
	get:
		return sim.screen_index
var foe_context: FoeVM.Context:
	get:
		return sim.foe_context
var tile_grid: TileGrid:
	get:
		return sim.tile_grid
## Set to false to freeze the creatures (the sector viewer's pause).
var foes_active: bool:
	get:
		return sim.foes_active
	set(value):
		sim.foes_active = value
## Debug and tests: true = the water is still. Every screen loaded from now on gets a grid without its currents.
var ignore_currents: bool:
	get:
		return sim.ignore_currents
	set(value):
		sim.ignore_currents = value
var pending_slot: int:
	get:
		return sim.pending_slot
var pending_ticks: int:
	get:
		return sim.pending_ticks
var problem_active: bool:
	get:
		return sim.problem_active
	set(value):
		sim.problem_active = value

## Debug: show the (normally invisible) math triggers with their slot numbers.
var show_triggers: bool = false:
	set(value):
		show_triggers = value
		_show_debug()

## Debug: draw the water-current arrows. (The real game never shows them.)
var show_currents: bool = false:
	set(value):
		show_currents = value
		_show_debug()

## Debug: outline the rectangles the rules test: the walls, the sub's wall box and hurt rectangle, the creatures' hit rectangles.
var show_collisions: bool = false:
	set(value):
		show_collisions = value
		_show_debug()

## What shows the rules. The original presenter, unless `replace_presenter` put another one in its place or the run asked for another
## (`PresenterChoice`: `-- --presenter=debug_rects`).
@onready var presenter: SectorPresenter = %Presenter

## The debug rectangles laid over the presenter (`set_overlay`), or null. Whatever skin is shown, it sees the rectangles the rules test.
var overlay: DebugRectPresenter

## The presenter as the original one, for the tests and tools that look at its nodes (the sub, the creatures, the layers). Null with
## another presenter.
var original: OriginalPresenter:
	get:
		return presenter as OriginalPresenter


func _ready() -> void:
	var asked := PresenterChoice.requested()          # (the command line, a test, or the original: `PresenterChoice`)
	# The scene's own presenter is the original's: another kind, or a skin with a presenter of its own, takes its place.
	if asked != PresenterChoice.kind_of(presenter) or (asked == PresenterChoice.ORIGINAL and SkinChoice.current().presenter_scene_or_null() != null):
		_swap_presenter(PresenterChoice.make_presenter(asked))
	_bind_presenter(presenter)
	if PresenterChoice.overlay_requested():                # (`-- --overlay`)
		set_overlay(true)
	SkinChoice.events.changed.connect(_on_skin_changed)
	_connect_sim()
	sim.steer_source = InputReader.steering        # (the keys are read again when the rest of a tick that waited for a problem goes on)
	GameClock.tick.connect(_on_game_tick)       # the ONE connection of the rules: `tick` steps the sub, the creatures and the pellets
	# A self-contained scene routes its own sounds: whoever owns the world (the game, a debug scene, a test)
	# hears them without any wiring.
	sfx_requested.connect(Audio.play_sfx)


## Draws the frame: the presenter shows every moving thing `GameClock.tick_fraction()` of the way into the current tick.
func _process(delta: float) -> void:
	if sim.is_dissolving():                      # (the clock is held: only real time can count the dissolve out)
		sim.advance_dissolve(_dissolve_meter.feed(delta))
	presenter.show_between_ticks(GameClock.tick_fraction())
	if overlay != null:
		overlay.show_between_ticks(GameClock.tick_fraction())


## Puts another presenter in the place of the current one (the debug rectangles, a skin): the old one is freed, the new one is
## bound to the rules and shows what they hold. Do it before the sector is loaded and before anyone listens to `screen_loaded`: a
## presenter bound later hears the sim's events after the owner of this node did.
## (Not from inside a handler of one of the sim's signals either: the old presenter would still be asked to answer the signal that is being emitted.)
func replace_presenter(new_presenter: SectorPresenter) -> void:
	_swap_presenter(new_presenter)
	_bind_presenter(new_presenter)


## The node swap of `replace_presenter`, without binding the new one (`_ready` binds it itself).
func _swap_presenter(new_presenter: SectorPresenter) -> void:
	var old := presenter
	old.unbind()                                # (it is freed a moment later: until then it must not answer the sim)
	remove_child(old)
	old.queue_free()
	new_presenter.name = old.name
	add_child(new_presenter)
	presenter = new_presenter
	if overlay != null:
		move_child(overlay, -1)                  # (the rectangles stay on top of whatever is shown)


## Another skin is in use (`SkinChoice.select`): the presenter of its kind is made again, from the new skin's scene and pictures, and
## builds what it shows from the rules' state, so the sector goes on exactly as it was and only its look is another.
func _on_skin_changed(_skin: GameSkin) -> void:
	replace_presenter(PresenterChoice.make_presenter(PresenterChoice.kind_of(presenter)))
	presenter.refresh()


## Swaps between the original look and the debug rectangles (the F3 debug keys and the sector viewer call this): the sector goes on
## as it was, the new presenter builds what it shows from the rules' state.
func toggle_presenter() -> void:
	replace_presenter(PresenterChoice.make_presenter(PresenterChoice.other_than(presenter)))


## Lays the debug rectangles (`DebugRectPresenter` with no backdrop) over the presenter, or takes them off: the walls, the sub's two boxes, the
## creatures' hit rectangles, the pellets, the pieces, the triggers, the dock, drawn from the rules on top of the skin's pictures
## (does the picture cover its rectangle?). It is bound to the same rules and survives a change of presenter or skin; the game
## plays the same with it on or off. A key in the sector viewer (O) and in the game (F3 then O), `-- --overlay` at the start.
func set_overlay(on: bool) -> void:
	if on == (overlay != null):
		return
	if on:
		overlay = DebugRectPresenter.overlay(self, sim)
	else:
		overlay.unbind()
		remove_child(overlay)
		overlay.queue_free()
		overlay = null


## `set_overlay` the other way round.
func toggle_overlay() -> void:
	set_overlay(overlay == null)


func _bind_presenter(new_presenter: SectorPresenter) -> void:
	SkinChoice.current().render_settings().apply_to_playfield(new_presenter)     # (the skin's filter for the playfield; "like the parent" by default)
	new_presenter.bind(sim)                     # (first: it has built the screen when the events below are passed on)
	_show_debug()


func _show_debug() -> void:
	if is_node_ready():
		presenter.show_debug(show_triggers, show_currents, show_collisions)


## The events of the rules that are about the flow of the game, passed on to the owner. (What the picture does with the others is the
## presenter's business.)
func _connect_sim() -> void:
	sim.damage_settled_by_owner = true
	sim.dissolve_started.connect(_on_dissolve_started)
	sim.dissolve_finished.connect(_on_dissolve_finished)
	sim.sector_loaded.connect(func(_index: int) -> void: _release_dissolve_clock())     # (a load ends a dissolve that ran: `abandon_damage`)
	sim.screen_loaded.connect(func(sector_number: int, screen_number: int) -> void: screen_loaded.emit(sector_number, screen_number))
	sim.screen_changed.connect(func(screen: int, direction: SectorData.Direction) -> void: screen_changed.emit(screen, direction))
	sim.sound_requested.connect(func(sfx: StringName) -> void: sfx_requested.emit(sfx))
	sim.sub_damaged.connect(_on_sub_damaged)
	sim.problem_pending.connect(func(slot: int) -> void: problem_pending.emit(slot))
	sim.problem_requested.connect(func(slot: int) -> void: problem_requested.emit(slot))
	sim.problem_finished.connect(func(slot: int, session: ProblemSession) -> void: problem_finished.emit(slot, session))
	sim.dock_reached.connect(func() -> void: sim.after_tick(dock_reached.emit))     # (the flow goes on between ticks)
	sim.finale_reached.connect(func() -> void: finale_reached.emit())


## Two key events reach the playfield:
##  * Enter (the `show_problem` action) while a problem waits: open it at once. This is a request to the flow of the game, not an
##    input of a tick: a hint over the playfield has stopped the clock, and the Enter that closes the hint opens the problem too.
##    Not while the sub dissolves after a lost tank: the original is busy inside that one call (`_on_sub_damaged`) and reads no key,
##    and a problem opened over it would hold the losses and the lost tank would never be announced (nothing to respawn the sub).
##  * Space (`fire_ink`): one shot, COUNTED here as it arrives and taken by the next tick (`take_input`). The sub must be flying and
##    under control, and no cover (a problem, a message, a dialog) may hold the clock: `DoAction` is the only caller of
##    `StartStunGun`, so while something else runs the key reaches no one (DESIGN 3.7, "Space outside the key window, and the
##    sub's fire key"). Echo events (key repeat) are ignored.
func _unhandled_input(event: InputEvent) -> void:
	if sim.pending_slot >= 0 and event.is_action_pressed(&"show_problem"):
		get_viewport().set_input_as_handled()                 # (also while dissolving: the key is taken and dropped, as in the original)
		if not sim.is_dissolving():
			sim.open_pending_problem()
	elif event.is_action_pressed(&"fire_ink") and GameClock.holds == 0 and sim.sub.active and sim.sub.controlled:
		_input_reader.press_fire()


## The player's hands for the tick that is about to run: the held keys now, and the presses since the last call (which are
## forgotten). `_on_game_tick` is the only caller in the game; tests may call it after sending an event to `_unhandled_input`.
func take_input() -> InputSnapshot:
	return _input_reader.take()


## Loads a sector and shows one of its screens (default: the first).
func load_sector(index: int, screen: int = 0) -> void:
	_input_reader.forget()
	sim.load_sector(index, screen)


## Rebuilds everything on the playfield for screen `index` of the current sector.
func load_screen(index: int) -> void:
	sim.load_screen(index)


## The screen you reach by leaving `from_screen` through a side, or -1.
func neighbor(from_screen: int, direction: SectorData.Direction) -> int:
	return sim.neighbor(from_screen, direction)


## Moves to the neighbouring screen in `direction`. Returns false (and changes
## nothing) when there is no neighbour: the sub is clamped at that edge.
func go(direction: SectorData.Direction) -> bool:
	return sim.go(direction)


# --- the sub ------------------------------------------------------------------

## Switches the sub on at the given spot (SubX / SubY in the original's window
## pixels, see `SubModel.place_original`). Without arguments: the sector's respawn point.
func start_flight(sub_x: int = -1, sub_y: int = -1, cell: int = -1) -> void:
	sim.start_flight(sub_x, sub_y, cell)
	presenter.refresh()


## Hides and freezes the sub again (back to "browsing" mode).
func stop_flight() -> void:
	sim.stop_flight()
	presenter.refresh()


## Starts playing sector `index`. Past the midpoint the sub appears on screen 6 at the sector's respawn
## point; otherwise it starts on screen 0 and drives out of the supply station (`launch`). Returns when
## the player has control. This is both the start of a sector and the respawn after a lost tank.
func begin_sector(index: int, past_midpoint: bool = false) -> void:
	sim.begin_sector(index, past_midpoint)
	presenter.refresh()
	if not past_midpoint:
		await launch()


## The sub leaves the start station: the door opens, the sub drives 96 px right, the door closes (`StationSequence.launch`: 30 ticks of
## the game clock, counted by the rules). Returns when the rules say the sub is under control.
func launch() -> void:
	if skip_animations:
		sim.end_launch()
		presenter.refresh()
		return
	sim.start_launch()
	presenter.refresh()
	await sim.sequence_over


## The sub drives into the end station and is hidden behind it (`StationSequence.dock`: 31 ticks).
func dock() -> void:
	if skip_animations:
		sim.end_dock()
		presenter.refresh()
		return
	sim.start_dock()
	presenter.refresh()
	await sim.sequence_over
	presenter.refresh()


## The balloon takes the collected pieces up to the surface ship (`StationSequence.balloon`: 44 ticks).
func send_balloon() -> void:
	if skip_animations:
		return
	sim.start_balloon()
	await sim.sequence_over


## The clock ticked: take the player's hands once and run the rules.
func _on_game_tick(_count: int) -> void:
	tick(take_input())


## One game tick: the rules (`SimWorld.tick`, in the order of its `TICK_ORDER`) with `input` as what the player's hands did (null:
## nothing pressed). The presenter hears `SimWorld.ticked` and reads the result. Public so tests can run it without the clock.
func tick(input: InputSnapshot = null) -> void:
	sim.tick(input)


## Shows the whole state of the rules now (`SectorPresenter.refresh`), for tests and tools that changed it without a tick.
func refresh_views() -> void:
	presenter.refresh()


## `SimWorld.sub_touches` (tests and tools).
func sub_touches(foe: FoeModel) -> void:
	sim.sub_touches(foe)
	refresh_views()


## `SimWorld.check_contacts` (tests and tools).
func check_contacts() -> void:
	sim.check_contacts()
	refresh_views()


## One press of the fire button (tests and tools): `SimWorld.request_fire`.
func request_fire() -> void:
	sim.request_fire()


func is_trigger_armed(screen: int, index: int) -> bool:
	return sim.is_trigger_armed(screen, index)


## The problem for a trigger slot at the player's educational level (`GameState.edu_level`).
## The data canister gets its sector's log entry as the success message.
func make_problem(slot: int, rng: RandomNumberGenerator = null) -> ProblemInstance:
	if slot == SimWorld.CANISTER_SLOT:
		return ProblemFactory.for_canister(sector, GameState.edu_level, rng)
	return ProblemFactory.for_trigger_slot(slot, GameState.edu_level, rng)


## The owner tells the world how the problem went (`SimWorld.problem_resolved`).
func problem_resolved(slot: int, session: ProblemSession) -> void:
	sim.problem_resolved(slot, session)


## The sub lost air to a creature. If that was the last of the tank, the original runs `RedrawFrameAfterTankLoss` (0x418bcb) before it
## goes on: the sub dissolves away where it floats, everything else stands still (the clock is held, until `_on_dissolve_finished`),
## and only then does the game respawn the sub: the rules count the dissolve out (`SimWorld.begin_dissolve`, `dissolve.ticks` of the durations data) and then
## settle the damage, which lets the run announce the lost tank. Without animations (`skip_animations`, tests) the loss is announced at once.
func _on_sub_damaged(_damage: int, tank_lost: bool) -> void:
	if not tank_lost or skip_animations:
		sim.settle_damage()
		return
	if not _dissolve_holds_clock:
		_dissolve_holds_clock = true
		GameClock.hold()                                   # (the original is busy inside one call: nothing else moves)
	sim.begin_dissolve()


func _on_dissolve_started(_ticks: int) -> void:
	_dissolve_meter.reset()


func _on_dissolve_finished() -> void:
	_release_dissolve_clock()


func _release_dissolve_clock() -> void:
	if _dissolve_holds_clock:
		_dissolve_holds_clock = false
		GameClock.release()


## The world is going away (its scene leaves, a test or a tool frees it): a dissolve that is running ends here. Its hold on the clock is
## given back, and the lost tank it held back is dropped with the sub (`SimWorld.abandon_damage`): nothing is left to respawn it.
func _exit_tree() -> void:
	sim.abandon_damage()
	_release_dissolve_clock()
