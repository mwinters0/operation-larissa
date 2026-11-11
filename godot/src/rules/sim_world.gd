class_name SimWorld
extends RefCounted
## The rules of one sector, with no nodes: the sub, the creatures, the ink pellets, the pieces, the math triggers, the contacts
## between them, the waiting problem, the dock and the finale. It is the "simulation" of the three layers in docs/engine/ARCHITECTURE.md
## (rules / content / presentation): give it a sector and one `InputSnapshot` per tick and it runs the same game as the scene,
## and it tells whoever listens what happened through the signals below.
##
## Teaches: the difference between WHAT HAPPENS and HOW IT IS SHOWN. Nothing in this file (or in `src/rules/`) is a `Node`, a
## texture, a font, `Input` or a `TileMapLayer`; the scene (`SectorWorld` and the nodes under it) owns one of these, hands it the
## player's hands every tick, and draws what it says. Because the rules are plain objects, a test can fly a whole sector with no
## scene at all (tests/engine/test_sim_world.gd), and a different presentation (a skin) can listen to the same events.
##
## WHERE IT LIVES. A folder of its own, `src/rules/`, instead of `src/core/`: `core` also holds the loaders and lookups that touch
## resources (`Catalog`, `Assets`), and the point of this folder is that one rule can be written down for all of it - "no engine
## view class in here" - and checked by a test that scans the folder. The data the rules start from (`SectorData`, `FoeVM`,
## `TileGrid`, `SubTuning` ...) stays where it was.
##
## THE RUN (injection). The numbers of the player's game that the rules read and change - oxygen, ink, the collected pieces, the
## message lights, the midpoint - are not kept here but in the object handed to `_init` (`run`). In the game it is the `GameState`
## autoload, which the console (HUD) listens to; a headless test hands over a fresh instance of the same script that is not in
## any tree (see tests/engine/test_sim_world.gd), so no autoload has to exist. The methods the rules call on it are exactly these:
## `begin_life`, `set_sector`, `screen_entered`, `update_midpoint`, `has_piece`, `collect_piece`, `clear_piece`, `fire_ink`,
## `update_oxygen`, `hold_losses`, `release_losses`, `drop_losses`, `set_message_light` and `light_for_slot`; it reads one property,
## `tuning` (the run's `Tuning`, which `GameState.begin_run` resolved: the rule values, see `_hand_over_tuning`) and `hooks` (the run's `RuleHooks`: what the mods of
## the campaign add inside the tick, see "THE TICK"; empty for every original campaign). (Typed as `Object`: GDScript has no interfaces.)
##
## THE TICK. `tick(input)` is the original's `DoAction` loop, once per game tick, in the order of `TICK_ORDER`; nothing else
## decides a rule. A piece of the tick that needs the player's hands reads them from the `InputSnapshot`. Whoever runs the tick goes
## on with its own business between two ticks, never inside one (`after_tick`, `sequence_over`): a load, the reload of the creatures
## and a trip begin only there.
##
## RULE HOOKS. A campaign that declares a mod pack (`Campaign.mods`) has a `RuleHooks` table in its run, and the rules ask it at two places, neither of which moves a step of `TICK_ORDER`: a creature that runs
## `Mod_Instruction` in the `creatures` step (`FoeVM`, through `foe_context.hooks`), and the sub ability at the end of the `sub` step (`_use_sub_ability`). The third hook, the judging of an answer, is the problem's
## (`ProblemSession`). The table starts a tick with `begin_tick` and a load with `begin_load` (where the creatures are made), and answers every question of a run with no hooks without a call.
##
## THE EVENTS. Everything a presentation needs to stay in step is a signal here, named for what happened and not for how it looks:
## the creature signals say which creature (`FoeModel`) changed picture, mirror or visibility; the pellet signals carry the
## `PelletModel` (its `id` names it in a trace). Positions are not events: the view reads them (`sub.position`, `foe.vm.x` ...,
## with `previous_position` for smoothing) when `ticked` says the tick is over. `tests/engine/test_sim_world.gd` records the events of a
## flight and compares them. The whole list, and what a presenter does with it, is the header of `SectorPresenter`; a skin hears the same events as copies through
## `SimView` (docs/create/SKIN_API.md), which has no way back into this object.
##
## WHAT THE RULES DO NOT WAIT FOR, AND WHAT THEY COUNT. A step that shows something and holds up play - the sub dissolving after
## a lost tank, the door and the drive of the supply stations, the balloon - has its LENGTH here, in ticks, and the rules count it:
## the view is told "you have N ticks" (`dissolve_started`, `sequence_started`) and shows each tick of it, but it is never what
## decides when play goes on, so a presenter that shows nothing takes exactly as long. The sub's position and `controlled` change
## only in the rules (`StationSequence` in the tick, `begin_dissolve`). The loss of a tank is announced to the run when the
## dissolve is counted out (or at once, when the owner said it has no dissolve to wait for, see `damage_settled_by_owner`).
##
## LIFETIMES. Every member variable is in one of the `*_FIELDS` lists below: what `load_screen` clears, what `load_sector` clears
## (a sector start and every respawn: the entry of `DoAction`; it also ends a station trip or a dissolve that is still running),
## what each tick clears, and the ones that live as long as this object (`KEPT_FIELDS`, with the reason).
## tests/engine/test_state_lifetimes.gd fails for a variable in no list or in two, and checks that a load leaves each field of the
## first two lists as a fresh load does.

## Every rule of one `tick` has run: the state is complete and a view may read it (the sub, the creatures' places, the pellets).
## Positions are not events of their own - they change every tick - so this is the one signal that says "look now".
signal ticked
## The sector was loaded: its creatures exist (all of them, also those on other screens).
signal sector_loaded(sector_index: int)
## A screen has been (re)built: the grid, the pieces and the triggers of it. After `load_screen` the pellets are gone (each with
## `pellet_gone` first); after `reload_creatures` those in flight are kept (`pellets`).
signal screen_loaded(sector_index: int, screen_index: int)
## The sub flew into the neighbouring screen through `direction` (not for `load_screen` / `go` calls made by code).
signal screen_changed(screen_index: int, direction: SectorData.Direction)
## Something wants a sound effect played. `sfx` is the `sound` NAME of the effect (names/original.json).
signal sound_requested(sfx: StringName)

## A creature shows another picture (`picture` = its slot in the zone's creature pictures; also the first picture after a load).
signal creature_picture_changed(foe: FoeModel, picture: int)
## A creature is mirrored, or not any more.
signal creature_mirror_changed(foe: FoeModel, mirrored: bool)
## A creature is drawn / not drawn any more (it is on the shown screen and not hidden).
signal creature_visibility_changed(foe: FoeModel, shown: bool)
## The ink of a pellet reached a creature: it runs its ink script.
signal creature_hit_by_ink(foe: FoeModel)
## The sub touched a creature: it runs its contact script.
signal creature_hit_by_sub(foe: FoeModel)

## A creature hurt the sub for `damage` oxygen. `tank_lost`: that was the last of the tank (the sub is about to be put back).
## The sub is invulnerable afterwards unless the tank was lost. See `settle_damage`.
signal sub_damaged(damage: int, tank_lost: bool)
## The sub took a piece; `at` is where the piece lay (window pixels).
signal piece_collected(piece: PieceModel, at: Vector2i)
## The pieces of the shown screen were laid out again from the run's mask (the data canister has to be collected again).
signal pieces_reset
## A math trigger fired (and is disarmed now).
signal trigger_fired(trigger: TriggerModel)
## A pellet left the sub (it may already be splashing, when fired facing the viewer).
signal pellet_fired(pellet: PelletModel)
## A pellet started its splash, on rock or on a creature.
signal pellet_splashed(pellet: PelletModel)
## A pellet is over (splash done, left the playfield, or the screen changed) and is not in `pellets` any more.
signal pellet_gone(pellet: PelletModel)

## A math trigger was touched: the light on the sub blinks until the problem opens.
signal problem_pending(slot: int)
## The beacon on the sub (`SubModel.message_light`) went on (`lit`: a trigger was touched) or out (the problem opened, the canister
## took the countdown over, or a load put it out).
signal beacon_changed(lit: bool)
## Time to show a problem for this trigger slot (1 = data canister). The owner shows it and later calls `problem_resolved`.
signal problem_requested(slot: int)
## The owner reported the outcome of a problem.
signal problem_finished(slot: int, session: ProblemSession)
## The sub drove into the dock rectangle of the last screen (once per visit): time for the lock, or for the "ship's magnetometer"
## message when pieces are missing.
signal dock_reached
## The ending of the game begins: the sub is on the finale screen and a creature has set the semaphore bit (`finale_screen`).
## Emitted once per `load_sector`.
signal finale_reached

## A trip at a supply station begins (`StationSequence`: the launch, the dock or the balloon): "you have `sequence.ticks` ticks".
## The sub is already where the trip starts (a launch or dock). Show tick 0 now and each further tick when `ticked` says so.
signal sequence_started(sequence: StationSequence)
## The last tick of the trip has run (the sub is under control again after a launch, hidden after a dock). Play goes on.
## Said in the `sub` step, for whoever SHOWS the trip; whoever waits for the trip to go on with the game awaits `sequence_over`.
signal sequence_finished(sequence: StationSequence)
## The trip is over and so is the tick of its last step: said between two ticks (`after_tick`), so whatever its owner does next (the
## supply message, the balloon, the next sector) begins between two ticks, as the original's next call begins after the last pass of
## the trip's loop. `SectorWorld` and the test stages await this, never `sequence_finished`.
signal sequence_over(sequence: StationSequence)
## The sub dissolves away after losing its last air, and the rules hold everything else still: "you have `ticks` ticks" (of the
## original's 1/73 s, `TickMeter`: the rules count real time here because the game clock is held, see `begin_dissolve`).
signal dissolve_started(ticks: int)
## `elapsed` of the dissolve's ticks have gone by.
signal dissolve_advanced(elapsed: int)
## The dissolve is over; the loss of the tank is announced right after.
signal dissolve_finished

# The sound effects the rules ask for (names of names/original.json, DESIGN 7).
const SFX_STATION_DOOR := &"station_door"   # the door starts to close behind (or in front of) the sub
const SFX_INK_FIRED := &"ink_fired"
const SFX_CREATURE_HIT := &"creature_hit"
const SFX_NO_PELLETS := &"no_pellets"
const SFX_PIECE_PICKED_UP := &"piece_pickup"
const SFX_BEGIN := &"begin"           # the first screen of a sector is drawn (start or respawn), NOT every screen change
const SFX_INK_SPLASH := &"ink_splash" # a pellet starts its splash
## Trigger slot of the data canister problem.
const CANISTER_SLOT := 1
## The dock (DESIGN 3.6): on the last screen, sub picture at SubX >= 344 and 170 <= SubY <= 234, facing right (cell >= 6).
const DOCK_SCREEN := 11
const DOCK_MIN_X := 344
const DOCK_MIN_Y := 170
const DOCK_MAX_Y := 234
const DOCK_MIN_CELL := 6
## The finale sectors (30 Voyager, 31 Expert) have stations like every other sector: `DoAction` (0x417ffc) launches the
## sub from the start station whenever a sector starts on screen 0, `DrawScreen` (0x433f1c) draws the stations on screens
## 0 and 11 and the dock test has no sector test either.
## The finale: the creature that holds the "treasure" (Substance X in sector 30, the Alien Artifact in 31) sets
## semaphore bit 15 when the sub touches it (DESIGN 2 item 9). `DoAction` looks at the bit on every pass of its
## loop and starts the closing sequence when the sub is on screen 2 (sector 30) or screen 10 (sector 31): `SectorData.finale_screen`
## (the original hard-codes the two). In sector 30 the creature lives on screen 4, so the player must swim back up to
## screen 2 with the bit set.
const FINALE_SEMAPHORE_BIT := 15
## Where the sub's picture is (window y) while it drives out of the start station or into the end station (SubY 202). Where it is in x
## when the launch is over (SubX 96) is `launched_x()`.
const STATION_DRIVE_Y := StationSequence.DRIVE_Y

## How long the sub takes to dissolve after a lost tank, in ticks of 1/73 s (`TickMeter`): `dissolve.ticks` of `data/rules/durations.json`
## (`Durations`), 21 in the original's pack. The original never waits: `dissolve` (0x414f81) only copies and flushes, so its speed was
## the speed of the machine. The port gave each of the 16 passes and the closing copy one frame of a 60 Hz screen: 17 / 60 s = 20.68
## ticks of 1/73 s, which is counted as 21 whole ticks (0.288 s instead of 0.283 s: DESIGN, "Tank lost: the sub dissolves"). The clock is
## held for all of it (the original is busy inside one call).
static func dissolve_length() -> int:
	return maxi(Durations.at("dissolve.ticks"), 0)


## The sub's picture x (window pixels) once the launch is over: where the drive out of the start station ends (96).
static func launched_x() -> int:
	return StationSequence.launch().drive_to_x()

## The steps of one tick, in the order they run (`tick`). It is the order of `DoAction` (0x417ffc): the loop top (a waiting
## problem opens), the dock test, `CheckProbeCollision` (the pieces, with the sub where the last tick left it), the sub
## (keys, velocity, walls, screen edges), the finale test, `DetectMathTrigger` (the triggers, with the sub where it is now and
## the cell of this tick), `update_animals` (creature scripts, then their contacts with the sub and the pellets, then the damage)
## and `UpdateStunGun` (the pellets move). The one step that is not at its place in `DoAction` is `fire`, first of all: the original
## starts the pellet at the end of the tick, from the sub's NEW position, and moves it at once; the port has always started it
## where the sub was when the key went down (the end of the previous tick), and taking the presses first keeps exactly that.
## A tick in which the waiting problem opened stops after that step and goes on with the rest when the problem is resolved
## (`problem_resolved`, see `tick`), as `DoAction` goes on when `DoMathProblem` returns 0; `ticked` follows the last step. A problem
## that cost the tank ends the tick there, with no `ticked` (`DoAction` returns). `tests/engine/test_tick_order.gd` pins the order,
## `tests/engine/test_problem_ends_the_tick.gd` the early end.
const TICK_ORDER: Array[StringName] = [
	&"fire", &"pending_problem", &"dock", &"pieces", &"sub", &"finale", &"triggers", &"creatures", &"contacts", &"pellets"]

## Cleared by `load_screen` (`DoAction` (0x417ffc) on a screen change zeroes `LastHitFoe` (0x44868c) and `StunGunFlag` (0x44b048)
## and redraws the screen with its pieces; `RefreshMathTriggers` (0x427829) re-arms the triggers that ask for it). `screen_started_tick`: `DrawScreen`
## (0x433f1c) lays the screen out and `DrawAnimatedDecos` (0x41e943) steps the animated decorations from there, one entry per frame of `DoAction`.
const SCREEN_FIELDS: Array[StringName] = [&"screen_index", &"tile_grid", &"pellets", &"pieces", &"_last_culprit", &"screen_started_tick"]
## Cleared by `load_sector`, which is the entry of `DoAction` (a sector start or a respawn), see `_reset_triggers`. The station trip
## and the dissolve are here too: in the original each is one blocking call inside `DoAction`, so none is ever running when the next
## `DoAction` begins; a load in the middle of one (a debug key, a respawn during the launch) ends it (`abandon_damage`).
const LOAD_FIELDS: Array[StringName] = [
	&"sector", &"sector_index", &"foes", &"triggers", &"pending_slot", &"pending_ticks", &"problem_active",
	&"_in_dock", &"_finale_sent", &"_rest_of_tick_waits", &"_rest_of_tick_input", &"sequence", &"dissolve_elapsed", &"dissolve_ticks",
	&"_holding_losses"]
## One pass of `DoAction`'s loop (0x417ffc): set at the top of every `tick`, cleared when its steps are over (`_end_steps`).
const TICK_FIELDS: Array[StringName] = [&"tick_trace", &"_tick_ended", &"_ticking", &"_after_tick"]
## Member variables that no scope clears, and why.
const KEPT_FIELDS: Dictionary[StringName, String] = {
	&"run": "wiring: the player's game, handed to _init",
	&"sub": "wiring: one sub for the life of the sim; its own fields have their own scopes (SubModel), and its numbers are the run's (`_hand_over_tuning`)",
	&"foes_active": "configuration: the sector viewer's pause",
	&"ignore_currents": "configuration: debug and tests",
	&"steer_source": "wiring: where the owner's keys are read",
	&"damage_settled_by_owner": "configuration: the owner shows the dissolve",
	&"trace_ticks": "configuration: tests",
	&"tick_number": "a counter over the life of the sim, for whoever watches",
	&"_next_pellet_id": "a counter: pellet ids stay unique over the life of the sim",
	&"foe_context": "one creature context for the life of the sim, filled from the sim by `_build_foes`, `_show_creatures` and the creatures' step; its own fields have their own lifetimes (FoeVM.Context), and its limit and rule hooks are the run's (`_hand_over_tuning`)",
	&"foe_rng": "the dice of the creature scripts: the original's `rand` state is one global that no load resets, see `foe_rng`",
}

## The player's game that the rules read and change (see "THE RUN" above).
var run: Object

## Currently loaded sector and screen (null / -1 until `load_sector` is called).
var sector: SectorData
var sector_index: int = -1
var screen_index: int = -1
## The game tick (`tick_number`) in which the shown screen began to run: the animated decorations of a screen start from their start cursors there and step once per tick from then on
## (`DrawAnimatedDecos` (0x41e943) steps its cursors once per frame of `DoAction`). A screen laid out between two ticks begins with the next tick; one the sub flew into, in the middle of a tick, with the tick after it
## (the tick that loaded it has drawn nothing of it yet). `SimView.screen_ticks` is how many ticks it has run.
var screen_started_tick: int = 0

var sub: SubModel
## All creatures of the sector (also those on other screens) and what their scripts share.
var foes: Array[FoeModel] = []
var foe_context := FoeVM.Context.new()
## The dice of the creature scripts (`If_Random_Greater`), which every creature context of this sim rolls (`FoeVM.Context.rng`). One
## generator for the life of the sim, as the original's `rand` (0x4388c4) state is one global: rebuilding the creatures (a load, a
## respawn, the reload after the lock) does not start the dice over, so a seeded sim (a test, a tool) rolls one sequence through all of
## them. The original reseeds with `srand` (0x438894) from the tick count before every `DoAction`, an unpredictable seed; the port seeds
## once, at random (`RandomNumberGenerator.new()`), which the player cannot tell apart (G15 in docs/port/PORT_GAPS.md).
var foe_rng := RandomNumberGenerator.new()
## Set to false to freeze the creatures (the sector viewer's pause).
var foes_active: bool = true
## The ink pellets in flight or splashing. Their number is what limits the fire button.
var pellets: Array[PelletModel] = []
## The pieces of the shown screen that are not collected yet.
var pieces: Array[PieceModel] = []
## Every math trigger of the sector (all screens), screen after screen, in the order of each screen's list.
var triggers: Array[TriggerModel] = []
## The walls and currents of the screen that is shown, as the rules see it. Rebuilt by `load_screen`; a test may change cells of
## it (the sub and the pellets look at this very object).
var tile_grid := TileGrid.new():
	set(value):
		tile_grid = value
		sub.tile_grid = value
## Debug and tests: true = the water is still. Every screen loaded from now on gets a grid without its currents (the reachability
## search of `SectorReach` does not model them).
var ignore_currents: bool = false

## Slot of the trigger that was touched and waits for its countdown (-1: none).
var pending_slot: int = -1
## Optional: where the steering keys are read again when the rest of a tick that waited for a problem goes on (`problem_resolved`).
## The original reads the keys after `DoMathProblem` returns, so the sub steers by the keys held NOW and not by those of the
## moment the problem opened, seconds ago; the presses of the fire button were taken before and stay taken. Returns a `Vector2i`.
## Unset (rules with no hands of their own, tests): the tick's own snapshot is used.
var steer_source: Callable
## Ticks until the pending problem opens by itself.
var pending_ticks: int = 0
## True from `problem_requested` until `problem_resolved`: nothing new may start meanwhile.
var problem_active: bool = false

## True when the owner has said it will settle a lost tank itself: it calls `begin_dissolve` (the rules count the dissolve and settle
## at its end) or `settle_damage` (no dissolve). False: the rules settle at once, like a run with no view at all.
var damage_settled_by_owner: bool = false

## The station trip that is running, or the last one that ran in this load (`is_done()`); null before the first. Advanced by `tick`.
var sequence: StationSequence
## Ticks of the dissolve that have gone by, or -1 when the sub is not dissolving. Counted by `advance_dissolve`.
var dissolve_elapsed: int = -1
## How many ticks of 1/73 s the running (or the last) dissolve lasts: `dissolve_length()`, told to the presenters at its start
## (`dissolve_started`) and the number that every later step of it is measured against.
var dissolve_ticks: int = 0
## True while this sim holds the run's losses for a lost tank it has not settled yet (`_apply_creature_damage` .. `settle_damage`).
var _holding_losses: bool = false

## The number of the tick that is running, counted from 0 for this sim: during a tick, and in its `ticked`, it is that tick's number;
## between two ticks it is the next one's. Nothing in the rules reads it; it is for whoever watches (the `T<n>` of the test traces, the
## `started_tick` of a station trip, the skin API's `SimView.tick_number`).
var tick_number: int = 0

## Tests: when true, `tick` writes the name of every step it runs into `tick_trace` (cleared at the start of each tick).
var trace_ticks: bool = false
var tick_trace: Array[StringName] = []

## Index of the creature that was the first one touching the sub in the previous tick (-1: none).
var _last_culprit: int = -1
var _in_dock: bool = false
var _finale_sent: bool = false
## A problem opened at the loop top of the running tick and the rest of it is waiting for `problem_resolved`, with the hands of that tick.
var _rest_of_tick_waits: bool = false
var _rest_of_tick_input: InputSnapshot
## A problem that cost the tank was resolved: the running tick ends after the step it is in (`DoAction` returns the code).
var _tick_ended: bool = false
## True while the steps of a tick run (`tick`, and `_finish_tick` when a problem let the rest of its tick go on): see `is_ticking`.
var _ticking: bool = false
## What the owner asked to run when the running tick is over (`after_tick`), in the order asked.
var _after_tick: Array[Callable] = []
var _next_pellet_id: int = 1


## `game_run`: the player's game the rules work on (the `GameState` autoload in the game), see "THE RUN".
func _init(game_run: Object) -> void:
	run = game_run
	sub = SubModel.new(game_run.tuning.sub)
	_hand_over_tuning()
	sub.active = false                        # (switched on by `start_flight`; a browsing viewer has no sub)
	sub.tile_grid = tile_grid
	sub.crossed_edge.connect(_on_sub_crossed_edge)
	foe_context.begin_load([] as Array[FoeVM], foe_rng, screen_index, sub.original_position())


## The rule values of the run (`run.tuning`, resolved when the run began) go to the parts that hold their own section: the sub (and
## through it the pellets) and the creatures' context. The ONE place that does, called by `_init` and by every `load_sector`, so a run
## that began after this sim was made is never left with the numbers of the one before. (The rest of the numbers, the waits and limits of the
## sector, are read from `run.tuning` where they are used.) The creatures' context gets the run's rule hooks (`run.hooks`) the same way.
func _hand_over_tuning() -> void:
	var tuning: Tuning = run.tuning
	sub.tuning = tuning.sub
	foe_context.max_instructions = tuning.max_instructions_per_tick
	foe_context.hooks = run.hooks


# --- loading ----------------------------------------------------------------------

## Loads a sector and shows one of its screens (default: the first). It is the entry of `DoAction` (0x417ffc), a sector start or a
## respawn: every field of `LOAD_FIELDS` and `SCREEN_FIELDS` starts over, and a new life of the run begins (`_reset_triggers`).
## `DoAction` zeroes `SubVX` / `SubVY` and `InvulnerabilityCounter` (0x448684) there too: `start_flight` / `start_launch` place the sub
## (`SubModel.place_original`).
func load_sector(index: int, screen: int = 0) -> void:
	_refuse_inside_a_tick(&"load_sector")
	abandon_damage()
	sequence = null
	dissolve_ticks = 0
	_hand_over_tuning()
	sector_index = index
	sector = Catalog.sector(index)
	_in_dock = false
	_finale_sent = false
	_reset_triggers()
	_load_creatures()
	run.set_sector(index, sector.pieces.size())
	load_screen(screen)


## The lock at the end station is open: `DoAction` (0x417ffc, 0x4181fb-0x41821e) frees and loads the sector's resources again
## (`FreeSectorResources` 0x433ec2, `LoadSectorResources` 0x433d13) before `DrawScreen(0)` and `EnterSupplyStation` (0x432b96).
## The creatures live in the records of `FoeTable`, which that load reads from the file again, so every creature of the sector starts
## over from its start record while the sub docks and the balloon rises. Nothing else changes: not the screen, the pieces, the triggers
## or the sub. Announced as a load of the same sector and screen (`sector_loaded`, the creatures' first pictures, `screen_loaded`), so a
## presenter builds its creatures again. (The flags of the creature scripts start at 0 too, as on every load: G40 in
## docs/port/PORT_GAPS.md.) It is made of the steps of `load_sector` and `load_screen` that concern the creatures, so the creatures
## and their context are those of a fresh load of the same screen (tests/engine/test_state_lifetimes.gd).
func reload_creatures() -> void:
	assert(sector != null, "call load_sector() first")
	_refuse_inside_a_tick(&"reload_creatures")
	_load_creatures()
	_show_creatures()
	_start_screen_clock()                                 # (the screen is announced again, and drawn from its start)
	screen_loaded.emit(sector_index, screen_index)


## The shown screen begins to run now (`screen_started_tick`).
func _start_screen_clock() -> void:
	screen_started_tick = tick_number + (1 if _ticking else 0)


## Lays out everything of screen `index` of the current sector: walls and currents, pieces, triggers, which creatures are on it.
func load_screen(index: int) -> void:
	assert(sector != null, "call load_sector() first")
	screen_index = index
	_start_screen_clock()
	var grid := TileGrid.from_screen(sector.screens[index])
	tile_grid = grid.without_currents() if ignore_currents else grid
	for pellet in pellets:                                # pellets do not follow you to the next screen
		pellet_gone.emit(pellet)
	pellets.clear()
	_rearm_triggers(index)
	_build_pieces()
	_last_culprit = -1
	_show_creatures()
	screen_loaded.emit(sector_index, screen_index)


## The screen you reach by leaving `from_screen` through a side, or -1.
func neighbor(from_screen: int, direction: SectorData.Direction) -> int:
	return sector.neighbor(from_screen, direction)


## Moves to the neighbouring screen in `direction`. Returns false (and changes nothing) when there is no neighbour: the sub is
## clamped at that edge.
func go(direction: SectorData.Direction) -> bool:
	var target := neighbor(screen_index, direction)
	if target < 0:
		return false
	load_screen(target)
	return true


## Starts playing sector `index`, the rules' half of it (`begin_sector_on`). Past the midpoint the sub appears on screen 6 at the
## sector's respawn point (`start_flight`). Otherwise it starts on screen 0 and the owner launches it from the station (the drive is
## an animation, so it is the view's: it calls `start_launch` and `end_launch`). This is both the start of a sector and the respawn
## after a lost tank.
func begin_sector(index: int, past_midpoint: bool = false) -> void:
	begin_sector_on(index, run.tuning.midpoint_screen if past_midpoint else 0)
	if past_midpoint:
		start_flight()


## Starts sector `index` on `screen` with the steps every start of a sector shares: loads the sector there (`load_sector`), tells the
## run which screen was entered (`GameState.screen_entered`), the "begin" sound. The sub is not placed: `begin_sector`
## places it as the game does, the screen playtest (`PlaytestSetup.apply`) where its setup says.
func begin_sector_on(index: int, screen: int) -> void:
	load_sector(index, screen)
	run.screen_entered(screen, sector)
	sound_requested.emit(SFX_BEGIN)


# --- the sub ------------------------------------------------------------------

## Switches the sub on at the given spot (SubX / SubY in the original's window pixels, see `SubModel.place_original`). Without
## arguments: the sector's respawn point.
func start_flight(sub_x: int = -1, sub_y: int = -1, cell: int = -1) -> void:
	assert(sector != null, "call load_sector() first")
	if sub_x < 0:
		sub_x = sector.start_pos.x
		sub_y = sector.start_pos.y
	sub.place_original(sub_x, sub_y, sector.start_frame if cell < 0 else cell)
	sub.controlled = true
	sub.active = true


## Hides and freezes the sub again (back to "browsing" mode).
func stop_flight() -> void:
	sub.active = false


## The sub is put at the start station's door and the launch begins (`StationSequence.launch`): the door opens, the sub drives 96 px,
## the door closes, 30 ticks in all. The sub does not steer itself until the last of them (`sequence_finished`).
func start_launch() -> void:
	var trip := StationSequence.launch()
	sub.place_original(trip.drive_from_x(), STATION_DRIVE_Y, 6)
	sub.controlled = false
	sub.active = true
	_start_sequence(trip)


## The launch is over at once (no animations: tests, tools): the sub is where the drive leaves it (SubX 96) and under the
## player's control.
func end_launch() -> void:
	sub.place_original(launched_x(), STATION_DRIVE_Y, 6)
	sub.controlled = true
	sub.active = true


## The sub is put at the end station and drives in (`StationSequence.dock`, 31 ticks); then it is hidden behind it.
func start_dock() -> void:
	var trip := StationSequence.dock()
	sub.place_original(trip.drive_from_x(), STATION_DRIVE_Y, 6)
	sub.controlled = false
	sub.active = true
	_start_sequence(trip)


## The sub drove into the end station and is hidden behind it (also the whole dock at once, when there is no animation).
func end_dock() -> void:
	sub.active = false
	sub.controlled = true


## The balloon takes the pieces up to the surface ship (`StationSequence.balloon`, 44 ticks). The sub is not involved.
func start_balloon() -> void:
	_start_sequence(StationSequence.balloon())


func _start_sequence(trip: StationSequence) -> void:
	_refuse_inside_a_tick(&"a station trip")
	trip.started_tick = tick_number
	sequence = trip
	sequence_started.emit(trip)


## One tick of the running trip: the sub drives 4 px, the door sound plays, and at the last tick the trip is over. A trip that
## is done is left in `sequence` (the view shows its last tick) but no longer advances.
func _advance_sequence() -> void:
	if sequence == null or sequence.is_done():
		return
	var trip := sequence
	var finished := trip.advance()
	if trip.is_drive():
		sub.position.x = trip.sub_x() - SubModel.PLAYFIELD_ORIGIN.x + SubModel.PICTURE_CENTER.x       # (window x of the picture -> the centre in the playfield)
		if trip.elapsed == trip.door_sound_tick():
			sound_requested.emit(SFX_STATION_DOOR)
	if not finished:
		return
	match trip.kind:
		StationSequence.Kind.LAUNCH:
			sub.controlled = true
		StationSequence.Kind.DOCK:
			end_dock()
	sequence_finished.emit(trip)
	after_tick(func() -> void: sequence_over.emit(trip))


## The sub stops and dissolves away where it floats (`RedrawFrameAfterTankLoss` 0x418bcb -> `dissolve` 0x414f81). The OWNER holds the
## clock for as long as this lasts (`dissolve_started` .. `dissolve_finished`: the original is busy inside one call, nothing else
## moves), so no tick runs and nobody else can count it: the owner feeds the real time that goes by to `advance_dissolve`, in whole
## ticks of 1/73 s (`TickMeter`), and the rules end it after `dissolve_length()` ticks.
func begin_dissolve() -> void:
	sub.controlled = false
	dissolve_elapsed = 0
	dissolve_ticks = dissolve_length()
	dissolve_started.emit(dissolve_ticks)


func is_dissolving() -> bool:
	return dissolve_elapsed >= 0


## True when the sub has dissolved away in this load and nothing of it is drawn: its dissolve ran out (`dissolve_ticks` is kept until
## the next `load_sector`, which places the sub anew). A dissolve ended by a load (`abandon_damage`) leaves none.
func is_dissolved() -> bool:
	return not is_dissolving() and dissolve_ticks > 0


## `timer_ticks` ticks of 1/73 s went by during the dissolve. At the end of it the sub is gone and the lost tank is announced to the run.
func advance_dissolve(timer_ticks: int) -> void:
	if not is_dissolving() or timer_ticks <= 0:
		return
	dissolve_elapsed = mini(dissolve_elapsed + timer_ticks, dissolve_ticks)
	dissolve_advanced.emit(dissolve_elapsed)
	if dissolve_elapsed < dissolve_ticks:
		return
	dissolve_elapsed = -1
	dissolve_finished.emit()
	settle_damage()


# --- the tick -----------------------------------------------------------------------

## One game tick: every rule of the playfield, in the order of `TICK_ORDER` (the original's `DoAction`), with `input` as what the
## player's hands did (null: nothing pressed). Each step is a function of its own so that the order is the only thing this one says.
func tick(input: InputSnapshot = null) -> void:
	if input == null:
		input = InputSnapshot.new()
	if trace_ticks:
		tick_trace.clear()
	_rest_of_tick_waits = false                      # (a tick whose problem was never resolved is abandoned, not run late)
	_tick_ended = false
	_ticking = true
	run.hooks.begin_tick()
	var problem_was_active := problem_active
	_run_step(&"fire", _take_fire_presses.bind(input))
	_run_step(&"pending_problem", _tick_pending_problem)
	if _tick_ended:                                  # (the owner answered inside `problem_requested`, and it cost the tank)
		_end_steps()
		return
	if problem_active and not problem_was_active:
		# The problem opened at the loop top. In the original `DoAction` is inside `DoMathProblem` (0x423629) and goes on with the
		# rest of the pass when it RETURNS. The owner's problem screen outlives this call, so the rest of the tick waits here and
		# `problem_resolved` runs it (`_finish_tick`); `ticked` is said once, when it has. A problem that cost the tank ends the tick
		# instead (`DoAction` returns the code). (An owner that answers inside `problem_requested` has nothing open any more: the
		# tick goes straight on, or, when that answer cost the tank, ended just above.)
		_rest_of_tick_waits = true
		_rest_of_tick_input = input
		_end_steps()                                 # (no step runs until it is resolved)
		return
	_finish_tick(input)


## The steps of the tick after the loop top, and `ticked`. Runs at once, or (a problem opened in this tick) when it is resolved.
func _finish_tick(input: InputSnapshot) -> void:
	_ticking = true
	_run_step(&"dock", _check_dock)
	_run_step(&"pieces", _check_pieces)
	_run_step(&"sub", _tick_sub.bind(input))
	_run_step(&"finale", _check_finale)
	_run_step(&"triggers", _check_triggers)
	_run_step(&"creatures", _tick_creatures)
	_run_step(&"contacts", _tick_contacts)
	_run_step(&"pellets", _tick_pellets)
	ticked.emit()
	tick_number += 1
	_end_steps()


## True while the steps of a tick run (and its `ticked` is said): the state may be half way through a tick. False between two ticks,
## and while a tick waits for its problem.
func is_ticking() -> bool:
	return _ticking


## Runs `action` between two ticks: now when no step of a tick is running, otherwise as soon as the running tick is over (after its
## `ticked` and the count of `tick_number`, or where it ended early), in the order asked. It is the one door from the rules' tick back
## to whoever runs it: the owner hears there what it goes on with (the end of a trip, `sequence_over`; the dock, which `SectorWorld`
## passes on to the flow through here), so nothing the owner does - a load, the reload of the creatures, a trip - begins in the middle
## of a tick, and no step of a tick runs on a sector that was loaded inside it. In the original those come after the pass that led
## to them: `Main` (0x427bb4) starts the next sector only after `DoAction` (0x417ffc) has returned, and `LaunchBalloon` (0x432eae)
## begins after the last pass of the loop of `EnterSupplyStation` (0x432b96) (docs/engine/ARCHITECTURE.md, "Nothing the owner does
## runs inside a tick").
func after_tick(action: Callable) -> void:
	if _ticking:
		_after_tick.append(action)
	else:
		action.call()


## The steps of the running tick are over (it ended, ended early, or waits for its problem): what the owner asked for runs now. An
## action may run a tick of its own (a stage that plays a trip): that tick runs what is left of the list when it is over.
func _end_steps() -> void:
	_ticking = false
	while not _ticking and not _after_tick.is_empty():
		var action: Callable = _after_tick.pop_front()
		action.call()


## A load, the reload of the creatures and a trip begin between two ticks (`after_tick`): one asked for in the middle of a tick is an
## owner going on inside the tick, which leaves the rest of that tick to run on the new state. Said loudly; the call still happens.
func _refuse_inside_a_tick(what: StringName) -> void:
	if _ticking:
		push_error("SimWorld: %s inside a tick (step '%s'): the owner goes on between ticks (SimWorld.after_tick)" % [
			what, tick_trace.back() if not tick_trace.is_empty() else "?"])


func _run_step(step: StringName, action: Callable) -> void:
	if trace_ticks:
		tick_trace.append(step)
	action.call()


## The sub's tick: keys, velocity, walls, screen edges (which may switch the screen). Only a flying sub moves.
func _tick_sub(input: InputSnapshot) -> void:
	if sub.active:
		sub.logic_tick(input)
		_use_sub_ability(input)
	_advance_sequence()                       # (the station trips run beside the sub: it is not steered while one drives it)


## The sub ability of the campaign's mod (`RuleHooks.sub_ability`), after the sub has moved: what it asks for, validated and cut to the run's limits, is applied by the sub (`SubModel.adjust`). Only a sub under control
## has one, and a run with no such mod asks nothing.
func _use_sub_ability(input: InputSnapshot) -> void:
	if sub.controlled and run.hooks.has_sub_ability():
		sub.adjust(run.hooks.sub_ability(sub, input, sector_index, screen_index))


## The sub left the playfield: switch screens, or hold it at the border.
func _on_sub_crossed_edge(direction: SectorData.Direction) -> void:
	if go(direction):
		sub.enter_from(direction)
		run.screen_entered(screen_index, sector)
		# No sound and no music restart here: the original draws a new screen with `DrawScreen(0)` and
		# `PlaySectorMusic(0)`, both silent (DESIGN 7). Only the START of a sector (`begin_sector`) plays "begin".
		screen_changed.emit(screen_index, direction)
	else:
		sub.clamp_to_edge(direction)


# --- the dock and the finale ------------------------------------------------------------

## Raises `dock_reached` the moment the sub enters the dock rectangle.
func _check_dock() -> void:
	var inside := false
	if sub.active and sub.controlled and screen_index == DOCK_SCREEN:
		var at := sub.original_position()
		inside = sub.cell >= DOCK_MIN_CELL and at.x >= DOCK_MIN_X and at.y >= DOCK_MIN_Y and at.y <= DOCK_MAX_Y
	if not inside:
		_in_dock = false
	elif not _in_dock and pending_slot < 0 and not problem_active:     # (a waiting math problem goes first)
		_in_dock = true
		dock_reached.emit()


## The screen on which the closing sequence starts in sector `sector_number` (the sector's `finale_screen`), else -1.
static func finale_screen(sector_number: int) -> int:
	if not Catalog.has_sector(sector_number):
		return -1
	return Catalog.sector(sector_number).finale_screen


## Has the sub won? True when the finale creature has set bit 15 and the sub is on the finale screen of the sector.
func is_finale_triggered() -> bool:
	return sector != null and sector.finale_screen == screen_index and (foe_context.semaphore >> FINALE_SEMAPHORE_BIT) & 1 == 1


## Raises `finale_reached` once. (The sub must be flying: this keeps a browsing viewer quiet.)
func _check_finale() -> void:
	if _finale_sent or not sub.active or not sub.controlled or not is_finale_triggered():
		return
	_finale_sent = true
	finale_reached.emit()


# --- creatures ------------------------------------------------------------------

## What a contact does. Hostile creatures (damage > 0) cost oxygen once and make the sub invulnerable for 30 ticks (and the hit
## sound 0x1a plays); Zoom the dolphin (damage < 0) refills the air silently (only its own contact script makes a sound); a
## creature with damage 0 only runs its contact script. A creature that is busy with an interrupt script (for example an ink
## cloud) is harmless, and so is one with damage 0.
func sub_touches(foe: FoeModel) -> void:
	if not sub.active or not sub.controlled or not foe.is_touchable() or foe.vm.interrupted:
		return
	var damage := foe.vm.damage
	if damage > 0 and not sub.is_invulnerable():
		_hit_by_sub(foe)
		sound_requested.emit(SFX_CREATURE_HIT)
		_apply_creature_damage(damage)
	elif damage < 0:
		# Zoom's tank: `ApplyCreatureDamage` (0x418d23) with a negative damage is just `UpdateOxygen(1)` + `DisplayOxygen`, NO
		# sound (0x1a is only for a hurting contact). What you hear is the creature's own contact script
		# (`SOUND 15` in sector 0), which `hit_by_sub` starts.
		_hit_by_sub(foe)
		run.update_oxygen(1)
	elif damage == 0:
		_hit_by_sub(foe)                                   # harmless, but its contact script still runs (the finale object sets its semaphore bit)


## `ApplyCreatureDamage` (0x418d23): the hit costs `damage` oxygen. If that was the last of the tank, the original runs
## `RedrawFrameAfterTankLoss` (0x418bcb) before it goes on: the sub dissolves away where it floats, everything else stands still,
## and only then does the game respawn the sub (`tank_lost` / `game_over` of the run, which `hold_losses` keeps back until the
## dissolve is over). The owner hears `sub_damaged` and starts the dissolve (`begin_dissolve`), which the rules count out and then settle. A hit that
## leaves some air makes the sub invulnerable instead; a lost tank does not (the sub is about to be put back). The math problems
## lose tanks too, but those do not dissolve anything.
func _apply_creature_damage(damage: int) -> void:
	if not _holding_losses:
		_holding_losses = true
		run.hold_losses()
	var code: int = run.update_oxygen(-damage)
	var tank_lost := code != OxygenModel.OK
	if not tank_lost:
		sub.start_invulnerability()
	sub_damaged.emit(damage, tank_lost)
	if not tank_lost or not damage_settled_by_owner:
		settle_damage()


## The dissolve is over (or there is none): the run may announce the lost tank or the game over now.
func settle_damage() -> void:
	if _holding_losses:
		_holding_losses = false
		run.release_losses()


## The sim is thrown away (its scene leaves: `SectorWorld._exit_tree`), or loads a sector, before a lost tank was settled: a dissolve
## that is running ends where it is, and the loss it held back is DROPPED (`run.drop_losses`), not announced: the sub it belonged to
## is gone, and nothing is left to respawn it. (The original never gets here: its dissolve is one blocking call inside `DoAction`.)
func abandon_damage() -> void:
	dissolve_elapsed = -1
	if _holding_losses:
		_holding_losses = false
		run.drop_losses()


func _hit_by_sub(foe: FoeModel) -> void:
	if foe.hit_by_sub():
		creature_hit_by_sub.emit(foe)


## The creature scripts, one step each, and the sounds they asked for.
func _tick_creatures() -> void:
	if foes.is_empty() or not foes_active:
		return
	foe_context.begin_tick(sub.original_position())
	for foe in foes:
		foe.tick(foe_context)
	for foe in foes:
		foe.announce_changes()                        # (a script may have changed ANOTHER creature after that one's turn)
	var sounds := Catalog.sfx_catalog()
	for sound in foe_context.sounds:                  # the VM runs the original's bytes: the world gives the number its name
		sound_requested.emit(sounds.name_of(sound))
	foe_context.sounds.clear()


func _tick_contacts() -> void:
	if not foes.is_empty():
		check_contacts()


## The original's contact rule, once per tick, after the sub and every creature have moved (DESIGN 3.5). It is plain rectangle
## arithmetic in window pixels, not `Area2D` physics: the rule is inclusive at the edges and only looks at the state at the end of
## the tick.
##  * Only creatures on this screen, not hidden and not busy with an interrupt script are looked at
##    (`update_animals` 0x41ed0c: `rec[2] != 1` and `rec[0x13] == 0`); dormant ones count, damage does not matter.
##  * Every touching creature runs its contact script (usually just `RET`).
##  * Only the FIRST touching creature with damage != 0 can hurt (`update_animals` 0x41ed0c sets `HitFoeIndex` only
##    while the `Collision` option is on, see `MachineSettings`; with it off every touching creature just runs its
##    contact script), and only if the sub is
##    not invulnerable and that creature was not the first one in the previous tick
##    as well: staying inside a creature costs air once, not again every 2.5 seconds.
##  * A creature that does NOT touch the sub is tested against the flying pellets instead (the ELSE branch of
##    the sub test): see `_pellet_hits`. A creature that touches the sub is not, that tick.
func check_contacts() -> void:
	var sub_live := sub.active and sub.controlled
	var sub_rect := sub.hurt_rect_window()
	var culprit: FoeModel = null
	for foe in foes:
		if not foe.is_touchable() or foe.vm.interrupted:
			continue
		var foe_rect := foe.hit_rect_window()
		if sub_live and FoeModel.rects_touch(sub_rect, foe_rect):
			if culprit == null and foe.vm.damage != 0 and MachineSettings.collision_enabled:
				culprit = foe
			else:
				_hit_by_sub(foe)
		else:
			_pellet_hits(foe, foe_rect)
	if not sub_live:
		return
	var culprit_index := culprit.vm.index if culprit != null else -1
	if culprit != null:
		if culprit_index != _last_culprit and not sub.is_invulnerable():
			sub_touches(culprit)
		else:
			_hit_by_sub(culprit)
	_last_culprit = culprit_index


## The pellet half of `update_animals`: the first flying pellet (a 16 x 16 box at its position, inclusive edges) that overlaps
## `foe_rect` sends the creature to its ink script and starts its own splash; the creature is then busy, so a second pellet flies
## through it. The creature's damage is not looked at (harmless and friendly creatures are inked too).
func _pellet_hits(foe: FoeModel, foe_rect: Rect2i) -> void:
	for pellet in pellets:
		if not pellet.is_flying() or not pellet.alive:
			continue
		if FoeModel.rects_touch(pellet.window_rect(), foe_rect):
			if foe.hit_by_ink():
				creature_hit_by_ink.emit(foe)
			pellet.hit_creature()
			return


# --- the ink pellets ----------------------------------------------------------------

## Every fire press since the last tick is one shot, in order (two presses inside one tick are two tries).
func _take_fire_presses(input: InputSnapshot) -> void:
	for press in input.fire_presses:
		request_fire()


## One press of the fire button. At most `ink_in_flight_max` pellets may be flying; beyond that the press is ignored (and costs
## nothing). With no ink left only a sound plays. A sub that is not flying under control does not shoot. Public so that tests
## can press the button without a tick.
func request_fire() -> void:
	if not sub.active or not sub.controlled:
		return
	if pellets.size() >= run.tuning.ink_in_flight_max:
		return
	if not run.fire_ink():
		sound_requested.emit(SFX_NO_PELLETS)
		return
	fire_pellet()


## Creates a pellet in front of the sub. (No ink is used here; `request_fire` does that.)
func fire_pellet() -> PelletModel:
	var pellet := PelletModel.new()
	pellet.id = _next_pellet_id
	_next_pellet_id += 1
	var top_left := sub.position - SubModel.PICTURE_CENTER + Vector2(sub.tuning.pellet_spawn_offset(sub.cell))
	pellet.launch(top_left, sub.cell, sub.tuning, tile_grid)
	pellet.splashed.connect(_on_pellet_splashed.bind(pellet))
	pellets.append(pellet)
	pellet_fired.emit(pellet)
	pellet.begin()                                        # (facing the viewer it splashes at once: that sound comes first)
	sound_requested.emit(SFX_INK_FIRED)
	return pellet


func _on_pellet_splashed(pellet: PelletModel) -> void:
	pellet_splashed.emit(pellet)
	sound_requested.emit(SFX_INK_SPLASH)


## The ink pellets move (`UpdateStunGun`), after the contacts looked at them where they were. A pellet that is over is dropped
## from the list at once (a deliberate deviation, `tests/engine/test_ink_pellets.gd`).
func _tick_pellets() -> void:
	for pellet in pellets:
		pellet.logic_tick()
	var i := 0
	while i < pellets.size():
		if pellets[i].alive:
			i += 1
		else:
			pellet_gone.emit(pellets[i])
			pellets.remove_at(i)


# --- pieces and math problems -----------------------------------------------------

## `CheckProbeCollision` (0x42dbb2), once per tick, BEFORE the sub moves: the pieces are taken by plain rectangle arithmetic
## (`PieceModel.touched_by`), with the sub where the previous tick left it. A piece on the screen that the sub just entered is seen
## on the next tick.
func _check_pieces() -> void:
	if not sub.active or not sub.controlled or problem_active:
		return
	var at := sub.original_position()
	for piece in pieces.duplicate():
		if piece.is_touched_by(at):
			take_piece(piece.index)


## `DetectMathTrigger` (0x427744), once per tick, AFTER the sub has moved (and maybe changed the screen), so it sees this tick's
## position and cell.
func _check_triggers() -> void:
	if not sub.active or not sub.controlled or problem_active:
		return
	_detect_math_trigger(sub.original_position())


## The rule of `DetectMathTrigger`: the first armed trigger of this screen (list order) whose table entry for the sub's current
## cell and the trigger's flag nibble passes fires and is disarmed; at most one per call. It is NOT gated by a running countdown:
## `DoAction` (0x417ffc) calls `DetectMathTrigger` every tick, and a second trigger that fires meanwhile replaces the pending slot
## and restarts the 36 ticks (the first problem is lost). The math triggers decide by `TriggerModel.fires`
## (the `MathTriggerTable` rule).
func _detect_math_trigger(at: Vector2i) -> void:
	for trigger in triggers_on_screen(screen_index):
		if trigger.armed and trigger.fires_for(at, sub.cell):
			touch_trigger(trigger)
			return


## The sub touched piece `index`. Each piece can be taken once; the data canister (0) also starts its math problem. Public so that
## tests can take a piece without flying to it.
func take_piece(index: int) -> void:
	if not sub.active or not sub.controlled or problem_active:
		return
	if not run.collect_piece(index):
		return
	run.update_midpoint(sector)
	sound_requested.emit(SFX_PIECE_PICKED_UP)
	var at := Vector2i.ZERO
	for piece in pieces.duplicate():
		if piece.index == index:
			at = piece.position()
			pieces.erase(piece)                           # (gone from the list at once: the pieces that are left are the list)
			piece_collected.emit(piece, at)
	if index == 0:
		# `DoAction` (0x417ffc, asm 0x4182ca-0x4182e8): taking piece 1 stores `MessageLightCountdown` (0x448688) = 2 and the
		# problem id = 1 UNCONDITIONALLY. That is the same countdown a math trigger uses, so a trigger whose countdown is
		# still running is overwritten (its problem is never shown; its armed bit is already cleared), and the canister's
		# problem opens one tick later (countdown 1) through `_tick_pending_problem`, not at once. `CheckProbeCollision` runs
		# before `DetectMathTrigger`, so a trigger that fires in this same tick overwrites the canister in turn: the canister
		# is taken for good and gets no problem. (Why this is no `problem_active = true` here: that would refuse the trigger.)
		pending_slot = CANISTER_SLOT
		pending_ticks = run.tuning.canister_pending_ticks
		_set_beacon(false)                              # (the countdown is even: `DrawSub` shows no dome)
		run.set_message_light(false, true)              # the computer has a message: the canister's code


## The sub touched an armed math trigger: disarm it and (re)start the countdown (`Tuning.pending_ticks`, 36 ticks) for its slot.
func touch_trigger(trigger: TriggerModel) -> void:
	if not sub.active or not sub.controlled or problem_active:
		return
	trigger.armed = false                 # the original clears the trigger's bit when it fires
	pending_slot = trigger.data.slot
	pending_ticks = run.tuning.pending_ticks
	_set_beacon(true)
	var light: Vector2i = run.light_for_slot(pending_slot)
	run.set_message_light(light.x == 1, light.y == 1)
	trigger_fired.emit(trigger)
	problem_pending.emit(pending_slot)


## One tick of the countdown. At 1 the problem opens.
func _tick_pending_problem() -> void:
	if pending_slot < 0:
		return
	pending_ticks -= 1
	if pending_ticks <= 1:
		open_pending_problem()


## Opens the waiting problem now (the countdown ran out, or the player pressed Enter): `open_problem` of its slot.
func open_pending_problem() -> void:
	open_problem(pending_slot)


## Opens the problem of trigger slot `slot` now, as a waiting problem opens: a problem that was waiting is dropped (the countdown
## stops, the beacon on the sub and the console's lights go out) and the owner is asked for the problem (`problem_requested`).
## Nothing while a problem is open; returns whether it opened. The F3 key 6 opens any slot through here.
func open_problem(slot: int) -> bool:
	if problem_active:
		return false
	pending_slot = -1
	pending_ticks = 0
	_set_beacon(false)
	problem_active = true
	run.set_message_light(false, false)
	problem_requested.emit(slot)
	return true


## The owner tells the world how the problem went. If the air ran out during the canister's problem, the canister must be
## collected again (DESIGN 5.2 item 4).
##
## A problem that cost the tank (`session.oxygen_code` not OK) ENDS the tick that opened it: `DoAction` (0x417ffc) does
## `PlaySectorMusic(1)` (0x43204d) and returns the code of `DoMathProblem` (0x423629) at once, and `Main` (0x427bb4) respawns the
## sub or starts the sector over. So none of the steps after `pending_problem` runs for it (the sub, now dead, would take the
## canister it sits on again, move, enter screen 6, fire a trigger or be hit), and no `ticked` comes: the tick is abandoned as a
## load abandons it. The owner plays the song again (`GameFlow.open_problem`) and respawns the sub when the run announces the loss.
## Only a problem that returns 0 lets the pass go on.
func problem_resolved(slot: int, session: ProblemSession) -> void:
	problem_active = false
	run.set_message_light(false, false)
	var tank_lost := session.oxygen_code != OxygenModel.OK
	_tick_ended = tank_lost
	if slot == CANISTER_SLOT and tank_lost:
		run.clear_piece(0)
		_build_pieces()
		pieces_reset.emit()
	problem_finished.emit(slot, session)
	if _rest_of_tick_waits:                       # `DoMathProblem` has returned: the rest of the pass that opened it
		var input := _rest_of_tick_input
		_rest_of_tick_waits = false
		_rest_of_tick_input = null
		if tank_lost:
			return                                # (`DoAction` returns the code: the rest of the pass never runs)
		if steer_source.is_valid():
			var fresh := InputSnapshot.new()
			fresh.steer = steer_source.call()
			input = fresh
		_finish_tick(input)


## Forget which triggers were used: all start as the data says, and the blinking message light goes out. A sector load is the start
## of `DoAction` (0x417ffc), which zeroes `MessageLightCountdown` (0x448688) and has `DisplayBezel` (0x419eec) draw the console
## with both lights out, so a countdown that was running when the sub died does not outlive the respawn. The console's lights and
## `MidpointReached` belong to the run, which clears them in `begin_life`; the HUD only mirrors the lights.
func _reset_triggers() -> void:
	_rest_of_tick_waits = false                   # (a sector change or a game over: the tick that waited belongs to a sector that is gone)
	_rest_of_tick_input = null
	pending_slot = -1
	pending_ticks = 0
	problem_active = false
	_set_beacon(false)
	run.begin_life()
	triggers.clear()
	for s in sector.screens.size():
		var list := sector.screens[s].triggers
		for i in list.size():
			triggers.append(TriggerModel.new(list[i], s, i))


## Switches the beacon on the sub and says so when that changed it (`beacon_changed`). Every change of `SubModel.message_light` goes
## through here.
func _set_beacon(lit: bool) -> void:
	if sub.message_light == lit:
		return
	sub.message_light = lit
	beacon_changed.emit(lit)


## Entering a screen re-arms its triggers that have the "re-arm on enter" flag.
func _rearm_triggers(screen: int) -> void:
	for trigger in triggers_on_screen(screen):
		if trigger.data.rearm_on_enter:
			trigger.armed = true


## The triggers of one screen, in the order of its list.
func triggers_on_screen(screen: int) -> Array[TriggerModel]:
	var result: Array[TriggerModel] = []
	for trigger in triggers:
		if trigger.screen == screen:
			result.append(trigger)
	return result


func is_trigger_armed(screen: int, index: int) -> bool:
	for trigger in triggers:
		if trigger.screen == screen and trigger.index == index:
			return trigger.armed
	return false


# --- builders -------------------------------------------------------------

## Pieces of this screen that are not collected yet.
func _build_pieces() -> void:
	pieces.clear()
	for i in sector.pieces.size():
		var data := sector.pieces[i]
		if data.screen != screen_index or run.has_piece(i):
			continue
		pieces.append(PieceModel.new(data, i))


## A step of `load_sector` and `reload_creatures`: the creatures of the sector are made from their start records and announced
## (`sector_loaded`). Which of them are shown follows with `_show_creatures`.
func _load_creatures() -> void:
	_build_foes()
	sector_loaded.emit(sector_index)


## A step of `load_screen` and `reload_creatures`: the creatures see the screen that is shown, and each one on it is shown.
func _show_creatures() -> void:
	foe_context.show_screen(screen_index)
	for foe in foes:
		foe.refresh(foe.vm.screen == screen_index)


## Creates all creatures of the sector. Each gets a VM; the VMs share the creature context, which is filled from the sim
## (`FoeVM.Context.begin_load`: the new VMs, the sim's dice, the screen that is shown, the sub; the flags at 0, a deliberate deviation,
## G40).
func _build_foes() -> void:
	foes.clear()
	_last_culprit = -1
	var meta := SpriteMeta.for_zone(sector.zone)
	var vms: Array[FoeVM] = []
	for i in sector.foes.size():
		var vm := FoeVM.from_data(sector.foes[i], i, sector)
		var foe := FoeModel.new(vm, meta)
		foe.picture_changed.connect(func(picture: int) -> void: creature_picture_changed.emit(foe, picture))
		foe.mirror_changed.connect(func(mirrored: bool) -> void: creature_mirror_changed.emit(foe, mirrored))
		foe.visibility_changed.connect(func(shown: bool) -> void: creature_visibility_changed.emit(foe, shown))
		foes.append(foe)
		vms.append(vm)
	foe_context.begin_load(vms, foe_rng, screen_index, sub.original_position())
	run.hooks.begin_load()                                # (what the mods' hooks keep starts over with the creatures' flags)
