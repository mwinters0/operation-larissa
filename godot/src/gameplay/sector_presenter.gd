class_name SectorPresenter
extends Node2D
## The edge between the RULES of a sector and the thing that SHOWS it. A presenter is a node that is given a `SimWorld` and draws what
## it says; the rules (`src/rules/`) know nothing about it, so any presenter plays the same game. `OriginalPresenter` is the one with
## the original's pictures; a "debug rectangles" presenter or a skin is another node that does the same job with other
## means. This file is the contract: what a presenter RECEIVES, what it may be ASKED, and what it must NOT do.
##
## Teaches: an interface in a language without interfaces. A base class whose methods are all "do nothing" is the smallest honest way
## to write one in GDScript: an empty presenter is a valid (blank) presenter, and a real one overrides what it can show. Nothing here
## is magic: scenes, nodes and signals, the same as everywhere else in the project.
##
## WHAT A PRESENTER RECEIVES (the skin API; the full reference, with every event's arguments and its place in the tick, is
## `docs/create/SKIN_API.md`). Everything comes through `view`, a `SimView` made by `bind`, whose answers are COPIES: a presenter that holds only
## the view cannot change a rule (`tests/engine/test_skin_api.gd` plays a presenter that vandalises everything it is given).
##  1. THE STATE, on request. `view.sub()`, `view.creatures()`, `view.pellets()`, `view.pieces()`, `view.triggers()`, `view.sequence()`
##     (the supply trip), `view.is_dissolving()` / `dissolve_progress()`, `view.is_solid(column, row)`, `view.sector_index`,
##     `view.screen_index`, `view.zone`, `view.tick_number`. Ask on `ticked` and keep the answer: each call makes new copies.
##  2. THE PREVIOUS STATE, in the same form. Everything that moves is a `SimView.Motion`: `previous` (where it was at the start of
##     the last tick), `current`, and `at(fraction)` between them. Sub, creatures and pellets have one; a supply trip has
##     `progress(fraction)` and `balloon_position(fraction)`. Places are playfield pixels (`SimView` header).
##  3. THE TICK FRACTION. The rules move 12.17 times a second; the screen is drawn 60 times a second or more. `show_between_ticks(f)` is
##     called once per drawn frame with how far into the current tick we are (0.0 = a tick has just happened, 1.0 = the next is due).
##     A presenter shows each moving thing that far on its way from the previous to the current state (`Motion.at(f)`).
##  4. THE EVENTS, as the signals of `view` (`SimView.EVENTS`): they say WHAT happened, in the rules' words, and carry copies. Connect
##     them in `bind` with `_listen(view.creature_picture_changed, handler)`. In the order of a tick (details and arguments in the document):
##       sector_loaded, screen_loaded, screen_changed       a sector / screen was laid out; the sub crossed an edge
##       pellet_fired, problem_requested, dock_reached, piece_collected, finale_reached, trigger_fired, problem_pending,
##       beacon_changed (the sub's light on or out, also between ticks),
##       creature_picture_changed / _mirror_changed / _visibility_changed, creature_hit_by_ink / _by_sub, sub_damaged,
##       pellet_splashed, pellet_gone                         what the steps of the tick did, in the order of `SimWorld.TICK_ORDER`
##       sound_requested                                      a sound by its name (the owner plays it; a skin may react to it too)
##       sequence_started / sequence_finished                 a supply trip: `sequence.ticks` is the length the RULES gave it,
##                                                            `started_tick` the tick it began in, `elapsed` how far it is
##       dissolve_started(ticks) / _advanced(elapsed, ticks) / _finished     the sub dissolves; the clock is held meanwhile
##       sub_placed, pieces_reset                             the sub was put somewhere (do not glide); the pieces were laid out again
##       ticked                                               every rule of this tick has run: read the state now. Always the last.
##     The events of the game's flow (the rest of the problem, the news) are passed on to `Game` by the owner, not to the presenter.
##     Which events a presenter shows is up to it; none is required for the rules to go on.
##  The state of the rules itself, `sim`, is also kept here for the built-in presenters and the tools (`OriginalPresenter` and
##  `DebugRectPresenter` read the models directly, and are part of the game); a SKIN uses `view` only.
##
## WHAT A PRESENTER MAY BE ASKED (the methods below). `bind`, `refresh`, `show_between_ticks` and `show_debug` are all instant. Nothing
## a presenter is asked takes time that anyone waits for: the steps that hold up play (the dissolve, the supply trips) are lengths of
## the RULES, told to the presenter as events with "you have N ticks"; a presenter that draws nothing, or draws slowly, changes
## nothing about when play goes on.
##
## WHAT A PRESENTER MUST NOT DO
##  * Change a rule. It does not write `sim` state, call `sim.tick`, or hold the clock.
##  * Decide timing for the rules. A skin may draw anything but cannot change a hit rectangle, a duration that holds up input or the
##    outcome of a tick (`tests/engine/test_skins_dont_change_the_game.gd`).
##  * Read the keyboard. The player's hands go to the rules through `InputSnapshot`, taken by the owner.
##
## WHO OWNS WHAT. `SectorWorld` owns the `SimWorld`, the clock connection and the player's hands, and has one presenter as a child
## (`SectorWorld.presenter`; `replace_presenter` swaps it). It passes on the fraction every frame. It stays one node with the presenter
## beside the rules and not a presenter inside every node, because that gives a different presentation exactly one place to plug in.

## The rules this presenter shows (set by `bind`). For the built-in presenters and tools; a skin reads `view` instead.
var sim: SimWorld
## The read-only window onto `sim`: state copies and the events, the skin API (set by `bind`, closed by `unbind`).
var view: SimView
## The skin this presenter is dressed in, or null: whichever skin is in use (`SkinChoice.current()`) when it builds what it shows. The
## game never sets it. The tool that shows TWO skins at once (`src/debug/skin_compare.tscn`) does, before the presenter enters the
## tree: from then on everything the presenter fetches through `Assets` / `Catalog` - when it is built, when an event makes it build
## a creature or a piece, in a frame - comes from this skin, whichever one the rest of the game wears. See `run_in_skin`.
var skin: GameSkin

# The connections `_listen` made, to take them back in `unbind`.
var _listening: Array[Array] = []


## Starts showing `sim_world`: remember it, connect the events (with `_listen`), and show what it holds already (a sector may be
## loaded). The presenter must be in the scene tree. Call it once.
func bind(sim_world: SimWorld) -> void:
	sim = sim_world
	view = SimView.new(sim_world)


## Stops showing the rules: every event connected with `_listen` is disconnected, so a presenter that is replaced (and freed a moment
## later) does not go on answering the sim.
func unbind() -> void:
	for connection in _listening:
		var event: Signal = connection[0]
		var handler: Callable = connection[1]
		if event.is_connected(handler):
			event.disconnect(handler)
	_listening.clear()
	if view != null:
		view.close()
	view = null
	sim = null


## Connects `handler` to an event (of `view`, or of `sim` for the built-in presenters) and remembers it for `unbind`. A presenter with a
## `skin` hears the event inside that skin (`run_in_skin`): the handler is wrapped, so a skin's code needs to do nothing about it.
func _listen(event: Signal, handler: Callable) -> void:
	var connected := handler
	if skin != null:
		# (a lambda that takes any number of arguments, whatever the event carries, and hands them to the handler inside the skin)
		connected = func(...args: Array) -> void: SkinChoice.within(skin, handler.bindv(args))
	event.connect(connected)
	_listening.append([event, connected])


## Runs `action` as this presenter's skin (`SkinChoice.within`; just runs it when `skin` is null). The owner of a presenter that has a
## `skin` puts into it what it does to it from outside: adding it to the tree (its `_ready` fetches pictures), `bind`, `refresh` and
## `show_between_ticks`. The events need nothing: `_listen` does it.
func run_in_skin(action: Callable) -> Variant:
	return SkinChoice.within(skin, action)


## Shows the whole state of the rules NOW, as if every event had just happened. For the moments the state changed without a tick
## (a sector was placed by hand, a tool moved the sub).
func refresh() -> void:
	pass


## Called once per drawn frame, after the game clock had its say: `fraction` (0..1) is how far into the current tick we are.
## Shift each moving thing between its previous and its current state (`TickSmoothing`); never change the state.
func show_between_ticks(_fraction: float) -> void:
	pass


## The debug overlays of the sector viewer (keys T, C, H): the math triggers with their slot numbers, the water-current arrows, and the
## rectangles the rules test (walls, the sub's two boxes, the creatures' hit rectangles). A presenter shows those it can.
func show_debug(_triggers: bool, _currents: bool, _collisions: bool) -> void:
	pass
