class_name SimView
extends RefCounted
## The window a skin looks at the rules through: every event of the `SimWorld` and every thing that moves, as plain COPIES. Nothing
## this object hands out is a rule object, so a presenter that holds only a `SimView` cannot change a rule - not by a slip, and not
## by trying. The reference for skin authors is `docs/create/SKIN_API.md`; the header of `SectorPresenter` is its short form.
##
## Teaches: read-only in a language without `const` objects. GDScript cannot say "you may look at this `FoeModel` but not touch it", so
## the edge is drawn by COPYING: `creature(3)` returns a new `CreatureState` with the numbers of that moment, the events carry such
## copies instead of the models, and changing a copy changes nothing but the copy. (A copy is made for every call, so ask on `ticked`
## and keep the answer; the per-frame `show_between_ticks` should only do arithmetic on what it kept.) It also teaches the shape of
## smooth movement: every moving thing is a `Motion` with a `previous` and a `current` place and `at(fraction)` between them, the
## same arithmetic as `TickSmoothing`, so a skin interpolates a sub, a creature, a pellet and a balloon the same way.
##
## THE COORDINATES. All places are PLAYFIELD pixels: x 0..607, y 0..287, the playfield's top-left corner is (0, 0). (The rules store
## window pixels, the original's, whose playfield starts at (16, 32): `PLAYFIELD_ORIGIN`.) A place is the top-left corner of the
## thing's picture, except the sub's `position`, which is the centre of its picture (like the `Sub` node; `SubState.top_left()` is the
## corner). A picture is the thing the rules call a `picture`: a number in the zone's list of creature pictures, the sub's cells and so
## on; the view says WHICH, the skin decides how it looks.
##
## THE TICK. `tick_number` counts the rules' ticks from 0. During a tick, and in its `ticked`, it is that tick's number; between two
## ticks it is the number of the next one. It is the `T<n>` of the traces in the tests (`SimTrace`). A tick lasts 1/12.17 s; the skin is
## told how far into it a drawn frame is by `SectorPresenter.show_between_ticks(fraction)`, and the state copies are meant for that:
## `motion.at(fraction)` for places, `SequenceState.progress(fraction)` for the supply trips.
##
## WHAT THIS DOES NOT HAVE. The player's game (oxygen, ink, pieces) belongs to the console, which has its own events. The pictures
## (the background, the decorations' and the station's) are read from `Catalog` and `Assets`, which anyone may do; they are data and are not
## changed by playing. What is ON the shown screen is here: `decorations()`, `anim_decorations()` (at the entry `screen_ticks()` ticks have
## stepped them to) and `station()`. The creature scripts' internals (`pc`, registers) are not part of the API: a skin follows what a creature LOOKS like.

# --- the copies --------------------------------------------------------------------------------

## A thing that moves: where it was at the start of the last tick and where it is now. `at(fraction)` is where to draw it
## `fraction` (0..1) of the way into the current tick: 0.0 = a tick has just happened (the previous place), 1.0 = the next is due
## (the current place). A thing that jumped (placed by hand, a creature that was hidden before) has `previous == current` or is
## flagged by the state it belongs to (`CreatureState.jumped`), so the skin can choose a hop instead of a glide.
class Motion:
	extends RefCounted
	var previous := Vector2.ZERO
	var current := Vector2.ZERO

	func _init(from: Vector2 = Vector2.ZERO, to: Vector2 = Vector2.ZERO) -> void:
		previous = from
		current = to

	## The place `fraction` of the way from `previous` to `current`.
	func at(fraction: float) -> Vector2:
		return previous.lerp(current, fraction)

	## True if it moved in the last tick.
	func moved() -> bool:
		return previous != current


## The sub. `motion.current` is the centre of its picture. `picture` is the number in the sub's bundle of pictures for the cell and
## the propeller phase; `mirrored` is true for the cells that face left.
class SubState:
	extends RefCounted
	var motion := Motion.new()
	var cell := 6
	var propeller_phase := 0
	var picture := 0
	var mirrored := false
	## False on the ticks of the blink when the picture is left out (the sub blinks after a hit).
	var picture_visible := true
	## The picture of the bubbles after a hit (9..12), or -1 when there are none now.
	var bubble_picture := -1
	## Ticks of invulnerability left after a hit (0: vulnerable); `blinking` is its last stretch.
	var invulnerability := 0
	var blinking := false
	## The beacon on the sub blinks: a math problem is waiting.
	var message_light := false
	## The sub is flying (false: not shown at all, e.g. the station swallowed it); and the player steers it (false while a trip at the
	## station or the dissolve moves it).
	var active := false
	var controlled := false
	## What the rules test for creatures' contacts, in playfield pixels (for an overlay).
	var hurt_rect := Rect2i()
	## The box the rules test against the walls (`SubTuning.wall_box` where the sub is), in playfield pixels (for an overlay). It is
	## smaller than the picture; the tiles it touches decide whether the sub can go on.
	var wall_rect := Rect2i()

	func top_left() -> Vector2:
		return motion.current - SubModel.PICTURE_CENTER

	static func of(sub: SubModel) -> SubState:
		var state := SubState.new()
		state.motion = Motion.new(sub.previous_position, sub.position)
		state.cell = sub.cell
		state.propeller_phase = sub.propeller_phase
		state.picture = sub.tuning.picture_for(sub.cell, sub.propeller_phase)
		state.mirrored = SubTuning.is_flipped(sub.cell)
		state.picture_visible = sub.is_picture_visible()
		state.bubble_picture = sub.bubble_picture()
		state.invulnerability = sub.invulnerability
		state.blinking = sub.is_blinking()
		state.message_light = sub.message_light
		state.active = sub.active
		state.controlled = sub.controlled
		state.hurt_rect = Rect2i(sub.hurt_rect_window().position - Vector2i(SubModel.PLAYFIELD_ORIGIN), sub.hurt_rect_window().size)
		state.wall_rect = Rect2i(sub.tuning.wall_box.position + sub.original_position() - Vector2i(SubModel.PLAYFIELD_ORIGIN), sub.tuning.wall_box.size)
		return state


## One creature (also those on other screens: `shown` says which are drawn). `motion` is the top-left corner of its picture. How a
## step is drawn is the skin's choice: the original look glides a step unless `jumped`, or `was_hidden != hidden`, or the step is
## longer than 24 px, or the picture is a loose tentacle tip (`Foe`).
class CreatureState:
	extends RefCounted
	var index := 0
	## The creature's picture: its slot in the zone's creature pictures (`frame` in the scripts).
	var picture := 0
	var mirrored := false
	var hidden := false
	var screen := 0
	## Drawn: on the shown screen and not hidden.
	var shown := false
	var motion := Motion.new()
	## The script put it somewhere (SET_POS, the end of an interrupt script): do not glide this step.
	var jumped := false
	## It was hidden before the last tick.
	var was_hidden := false
	## What hurts the sub when it touches (< 0: heals, 0: harmless).
	var damage := 0
	## The rectangle the rules test for contacts, in playfield pixels (empty for a picture with none).
	var hit_rect := Rect2i()

	static func of(foe: FoeModel) -> CreatureState:
		var vm := foe.vm
		var state := CreatureState.new()
		state.index = vm.index
		state.picture = vm.frame
		state.mirrored = vm.flip
		state.hidden = vm.hidden
		state.screen = vm.screen
		state.shown = foe.is_shown()
		state.motion = Motion.new(Vector2(foe.previous_pos) - SubModel.PLAYFIELD_ORIGIN, Vector2(vm.x, vm.y) - SubModel.PLAYFIELD_ORIGIN)
		state.jumped = vm.jumped
		state.was_hidden = foe.was_hidden
		state.damage = vm.damage
		if vm.frame < foe.meta.count():
			var rect := foe.hit_rect_window()
			state.hit_rect = Rect2i(rect.position - Vector2i(SubModel.PLAYFIELD_ORIGIN), rect.size)
		return state


## One ink pellet, named by its `id`. `motion` is the top-left corner of its 16 x 16 picture. `splash_picture` is 0 while it flies and
## 1..3 while it splashes; a splash picture is drawn at `splash_offset` from the place.
class PelletState:
	extends RefCounted
	var id := 0
	var splashing := false
	var splash_picture := 0
	var splash_offset := Vector2.ZERO
	var motion := Motion.new()

	static func of(pellet: PelletModel) -> PelletState:
		var state := PelletState.new()
		state.id = pellet.id
		state.splashing = pellet.state == PelletModel.State.SPLASHING
		state.splash_picture = pellet.splash_picture
		state.splash_offset = pellet.splash_offset
		state.motion = Motion.new(pellet.previous_position, pellet.position)
		return state


## A rock piece or the data canister lying on the sea floor (`index` 0 is the canister). `position` is the top-left corner of its
## 24 x 20 picture.
class PieceState:
	extends RefCounted
	var index := 0
	var is_canister := false
	var position := Vector2.ZERO

	static func of(piece: PieceModel) -> PieceState:
		var state := PieceState.new()
		state.index = piece.index
		state.is_canister = piece.is_canister()
		state.position = Vector2(piece.position()) - SubModel.PLAYFIELD_ORIGIN
		return state


## A math trigger of a screen: invisible in the game, so a skin normally only reacts to `trigger_fired`. `position` is its point.
class TriggerState:
	extends RefCounted
	var screen := 0
	var index := 0
	## The problem slot it starts (1 is the data canister's).
	var slot := 0
	var armed := false
	var position := Vector2.ZERO

	static func of(trigger: TriggerModel) -> TriggerState:
		var state := TriggerState.new()
		state.screen = trigger.screen
		state.index = trigger.index
		state.slot = trigger.data.slot
		state.armed = trigger.armed
		state.position = Vector2(trigger.data.pos) - SubModel.PLAYFIELD_ORIGIN
		return state


## One trip at a supply station (the launch, the dock or the balloon), as it stood when the copy was made. `ticks` is how long the
## RULES give it, in game ticks: the skin fits its drawing to it and never decides it. The trip began between ticks
## `started_tick - 1` and `started_tick` (`SimView.tick_number` then), and its first game tick is `started_tick`: tick
## `started_tick + k` takes `elapsed` to `k + 1`, and `sequence_finished` comes in tick `started_tick + ticks - 1`.
class SequenceState:
	extends RefCounted
	var kind := StationSequence.Kind.LAUNCH
	var ticks := 0
	var started_tick := 0
	## How many of the `ticks` have gone by (0 when it has just started).
	var elapsed := 0
	var done := false
	# A private copy of the trip (`StationSequence.copy`: the trip's own numbers, not the data's), to ask the questions of
	# `StationSequence` ("which picture does the door show after k ticks?").
	var _schedule: StationSequence

	## How far the trip is, 0..1, `fraction` of the way into the current tick: `(elapsed - 1 + fraction) / ticks`, because the drawing
	## lags the rules by a tick, as every `Motion` does. Done: 1.0 (the last step is not smoothed: play goes on at once).
	func progress(fraction: float) -> float:
		if done:
			return 1.0
		return clampf((elapsed - 1 + fraction) / ticks, 0.0, 1.0)

	## The door's picture after `elapsed` ticks: 2 closed, 3 and 4 moving, -1 open (a launch or a dock; the balloon has no door).
	func door_picture() -> int:
		return _schedule.door_picture()

	## True for the launch and the dock (a door and a sub that drives), false for the balloon.
	func is_drive() -> bool:
		return kind != StationSequence.Kind.BALLOON

	## The top-left corner of the balloon's picture (playfield pixels), `fraction` of the way into the current tick. The balloon is
	## gone (above the playfield) when the trip is done.
	func balloon_position(fraction: float) -> Vector2:
		var y := float(_schedule.balloon_y())
		if not done:
			y = lerpf(float(_schedule.balloon_y(maxi(elapsed - 1, 0))), y, fraction)
		return Vector2(_schedule.balloon_x, y) - SubModel.PLAYFIELD_ORIGIN

	static func of(trip: StationSequence) -> SequenceState:
		var state := SequenceState.new()
		state.kind = trip.kind
		state.ticks = trip.ticks
		state.started_tick = trip.started_tick
		state.elapsed = trip.elapsed
		state.done = trip.is_done()
		state._schedule = trip.copy()
		return state


## A still decoration of the shown screen (seaweed, rock, coral ...): the `layer` it is drawn in (`back_decos`, `mid_decos` or `front_decos`, the names of `SkinLayers.NODES`), its `slot` in the zone's decoration pictures, the
## top-left corner of the picture (playfield pixels) and whether it is mirrored.
class DecoState:
	extends RefCounted
	var layer: StringName = &"back_decos"
	var slot := 0
	var position := Vector2.ZERO
	var mirrored := false

	static func of(layer_name: StringName, placement: DecoPlacement) -> DecoState:
		var state := DecoState.new()
		state.layer = layer_name
		state.slot = placement.slot
		state.position = Vector2(placement.pos) - SubModel.PLAYFIELD_ORIGIN
		state.mirrored = placement.flag
		return state


## An animated decoration of the shown screen (the `anim_decos` layer): the list of decoration slots it shows one after another (`frames`, one entry per tick, looping), the entry it shows now (`cursor`, an index into `frames`) and
## so the slot (`frame`, `-1` for an empty list), and the top-left corner of its pictures (playfield pixels). `cursor` is where the screen's start cursor has got to after the ticks the screen has run (`screen_ticks`).
class AnimDecoState:
	extends RefCounted
	var position := Vector2.ZERO
	var frames := PackedInt32Array()
	var cursor := 0
	var frame := -1

	static func of(record: AnimDecoData, ticks: int) -> AnimDecoState:
		var state := AnimDecoState.new()
		state.position = Vector2(record.pos) - SubModel.PLAYFIELD_ORIGIN
		state.frames = record.frames.duplicate()
		if not record.frames.is_empty():
			state.cursor = (record.start_cursor + ticks) % record.frames.size()
			state.frame = record.frames[state.cursor]
		return state


## The supply station of the shown screen (screen 0 on the left, the dock on the right): which `left`, the picture of the door now (2 closed, 3 and 4 moving, -1 open) and whether the balloon is up. The door and the balloon are those
## of the supply trip the rules hold (`sequence()`: one that runs, or the last one's final picture); where the pictures go is `StationLayout`.
class StationState:
	extends RefCounted
	var left := true
	var door_picture := StationLayout.DOOR_CLOSED
	var balloon_shown := false


# --- the events --------------------------------------------------------------------------------
# The events of `SimWorld`, one for one, with copies instead of models. WHEN each one comes within a tick is in the table of
# `docs/create/SKIN_API.md`; `ticked` is always the last. `EVENTS` below lists them all (a test keeps the list, the signals and the
# document the same).

## Every rule of one tick has run: read the state now (`sub()`, `creatures()`, `pellets()`), then draw between ticks.
signal ticked
## The sector was loaded: its creatures exist (all of them, also those on other screens).
signal sector_loaded(sector_index: int)
## A screen has been (re)laid out: new walls, pieces and triggers, no pellets. Build it from `pieces()`, `triggers()`, `is_solid()`.
signal screen_loaded(sector_index: int, screen_index: int)
## The sub flew out of a screen into the neighbouring one through `direction` (`SectorData.Direction`); `screen_loaded` came first.
signal screen_changed(screen_index: int, direction: int)
## A sound effect is wanted, by its NAME (names/original.json). The owner plays it; a skin may also react to it.
signal sound_requested(sfx: StringName)
## A creature shows another picture (`picture`); also the first picture of every creature after a load.
signal creature_picture_changed(creature: CreatureState, picture: int)
## A creature is mirrored, or not any more.
signal creature_mirror_changed(creature: CreatureState, mirrored: bool)
## A creature is drawn / not drawn any more.
signal creature_visibility_changed(creature: CreatureState, shown: bool)
## An ink pellet reached a creature (it turns into an ink cloud).
signal creature_hit_by_ink(creature: CreatureState)
## The sub touched a creature (it runs its contact script; hurting is `sub_damaged`).
signal creature_hit_by_sub(creature: CreatureState)
## A creature hurt the sub for `damage` air; `tank_lost`: that was the last of the tank (the dissolve follows).
signal sub_damaged(damage: int, tank_lost: bool)
## The sub took a piece; `piece.position` is where it lay.
signal piece_collected(piece: PieceState)
## The pieces of the shown screen were laid out again (the canister problem failed): read `pieces()`.
signal pieces_reset
## A math trigger was touched and is disarmed.
signal trigger_fired(trigger: TriggerState)
## A pellet left the sub.
signal pellet_fired(pellet: PelletState)
## A pellet started its splash, on rock or on a creature.
signal pellet_splashed(pellet: PelletState)
## A pellet is over (it is not in `pellets()` any more).
signal pellet_gone(pellet: PelletState)
## The sub was put somewhere by hand (a launch, a respawn, a tool): do not glide from the old place; a dissolved sub is back.
signal sub_placed(sub: SubState)
## A math trigger was touched: the beacon blinks for about 3 s until the problem opens.
signal problem_pending(slot: int)
## The beacon on the sub went on (`lit`) or out; `sub().message_light` says the same.
signal beacon_changed(lit: bool)
## The problem of this trigger slot opens now (the owner shows it; the rules go on when it is resolved).
signal problem_requested(slot: int)
## The problem was resolved (`solved`: answered right).
signal problem_finished(slot: int, solved: bool)
## The sub drove into the dock rectangle.
signal dock_reached
## The ending of the game begins.
signal finale_reached
## A trip at a supply station begins: "you have `sequence.ticks` ticks" (see `SequenceState`).
signal sequence_started(sequence: SequenceState)
## The last tick of the trip has run; play goes on.
signal sequence_finished(sequence: SequenceState)
## The sub dissolves away after losing its last air: "you have `ticks` ticks" of 1/73 s, and the game clock is held meanwhile (no
## `ticked` comes). Progress is `elapsed / ticks`; there is no tick fraction here, the steps are fine enough (73 a second).
signal dissolve_started(ticks: int)
## `elapsed` of the `ticks` have gone by.
signal dissolve_advanced(elapsed: int, ticks: int)
## The dissolve is over; the sub is gone until `sub_placed`.
signal dissolve_finished

## The names of all the events above, in the order of the document. A presenter that wants every one connects each of these.
const EVENTS: Array[StringName] = [
	&"ticked", &"sector_loaded", &"screen_loaded", &"screen_changed", &"sound_requested",
	&"creature_picture_changed", &"creature_mirror_changed", &"creature_visibility_changed", &"creature_hit_by_ink", &"creature_hit_by_sub",
	&"sub_damaged", &"piece_collected", &"pieces_reset", &"trigger_fired",
	&"pellet_fired", &"pellet_splashed", &"pellet_gone", &"sub_placed",
	&"problem_pending", &"beacon_changed", &"problem_requested", &"problem_finished", &"dock_reached", &"finale_reached",
	&"sequence_started", &"sequence_finished", &"dissolve_started", &"dissolve_advanced", &"dissolve_finished",
]

# --- the state ---------------------------------------------------------------------------------

## Which tick the rules are in (see the header).
var tick_number: int:
	get:
		return _sim.tick_number
## The sector and the screen shown, and the sector's zone (which set of pictures it uses); -1 before a sector is loaded.
var sector_index: int:
	get:
		return _sim.sector_index
var screen_index: int:
	get:
		return _sim.screen_index
var zone: int:
	get:
		return _sim.sector.zone if _sim.sector != null else -1

var _sim: SimWorld
# The connections made in `_init`, to take them back in `close`.
var _connections: Array[Array] = []


## A view of `world`. The events of the rules are passed on from now on; call `close()` when the view is not needed any more.
func _init(world: SimWorld) -> void:
	_sim = world
	_forward(world.ticked, func() -> void: ticked.emit())
	_forward(world.sector_loaded, func(index: int) -> void: sector_loaded.emit(index))
	_forward(world.screen_loaded, func(index: int, screen: int) -> void: screen_loaded.emit(index, screen))
	_forward(world.screen_changed, func(screen: int, direction: int) -> void: screen_changed.emit(screen, direction))
	_forward(world.sound_requested, func(sfx: StringName) -> void: sound_requested.emit(sfx))
	_forward(world.creature_picture_changed, func(foe: FoeModel, picture: int) -> void: creature_picture_changed.emit(CreatureState.of(foe), picture))
	_forward(world.creature_mirror_changed, func(foe: FoeModel, mirrored: bool) -> void: creature_mirror_changed.emit(CreatureState.of(foe), mirrored))
	_forward(world.creature_visibility_changed, func(foe: FoeModel, shown: bool) -> void: creature_visibility_changed.emit(CreatureState.of(foe), shown))
	_forward(world.creature_hit_by_ink, func(foe: FoeModel) -> void: creature_hit_by_ink.emit(CreatureState.of(foe)))
	_forward(world.creature_hit_by_sub, func(foe: FoeModel) -> void: creature_hit_by_sub.emit(CreatureState.of(foe)))
	_forward(world.sub_damaged, func(damage: int, tank_lost: bool) -> void: sub_damaged.emit(damage, tank_lost))
	_forward(world.piece_collected, func(piece: PieceModel, _at: Vector2i) -> void: piece_collected.emit(PieceState.of(piece)))
	_forward(world.pieces_reset, func() -> void: pieces_reset.emit())
	_forward(world.trigger_fired, func(trigger: TriggerModel) -> void: trigger_fired.emit(TriggerState.of(trigger)))
	_forward(world.pellet_fired, func(pellet: PelletModel) -> void: pellet_fired.emit(PelletState.of(pellet)))
	_forward(world.pellet_splashed, func(pellet: PelletModel) -> void: pellet_splashed.emit(PelletState.of(pellet)))
	_forward(world.pellet_gone, func(pellet: PelletModel) -> void: pellet_gone.emit(PelletState.of(pellet)))
	_forward(world.sub.placed, func() -> void: sub_placed.emit(SubState.of(world.sub)))
	_forward(world.problem_pending, func(slot: int) -> void: problem_pending.emit(slot))
	_forward(world.beacon_changed, func(lit: bool) -> void: beacon_changed.emit(lit))
	_forward(world.problem_requested, func(slot: int) -> void: problem_requested.emit(slot))
	_forward(world.problem_finished, func(slot: int, session: ProblemSession) -> void: problem_finished.emit(slot, session.solved))
	_forward(world.dock_reached, func() -> void: dock_reached.emit())
	_forward(world.finale_reached, func() -> void: finale_reached.emit())
	_forward(world.sequence_started, func(trip: StationSequence) -> void: sequence_started.emit(SequenceState.of(trip)))
	_forward(world.sequence_finished, func(trip: StationSequence) -> void: sequence_finished.emit(SequenceState.of(trip)))
	_forward(world.dissolve_started, func(count: int) -> void: dissolve_started.emit(count))
	_forward(world.dissolve_advanced, func(elapsed: int) -> void: dissolve_advanced.emit(elapsed, world.dissolve_ticks))
	_forward(world.dissolve_finished, func() -> void: dissolve_finished.emit())


## Stops passing the events on (a presenter does this in `unbind`).
func close() -> void:
	for connection in _connections:
		var event: Signal = connection[0]
		var handler: Callable = connection[1]
		if event.is_connected(handler):
			event.disconnect(handler)
	_connections.clear()


func _forward(event: Signal, handler: Callable) -> void:
	event.connect(handler)
	_connections.append([event, handler])


## The sub, now.
func sub() -> SubState:
	return SubState.of(_sim.sub)


## Every creature of the sector in the order of the sector's list (`index`), also those on other screens.
func creatures() -> Array[CreatureState]:
	var found: Array[CreatureState] = []
	for foe in _sim.foes:
		found.append(CreatureState.of(foe))
	return found


## One creature by its `index`.
func creature(index: int) -> CreatureState:
	return CreatureState.of(_sim.foes[index])


## The ink pellets in flight or splashing.
func pellets() -> Array[PelletState]:
	var found: Array[PelletState] = []
	for pellet in _sim.pellets:
		found.append(PelletState.of(pellet))
	return found


## The pieces of the shown screen that are not collected yet.
func pieces() -> Array[PieceState]:
	var found: Array[PieceState] = []
	for piece in _sim.pieces:
		found.append(PieceState.of(piece))
	return found


## The math triggers of the shown screen.
func triggers() -> Array[TriggerState]:
	var found: Array[TriggerState] = []
	for trigger in _sim.triggers_on_screen(_sim.screen_index):
		found.append(TriggerState.of(trigger))
	return found


## The decorations of the shown screen that stand still, back layer first, then the middle and the front ones, each in the order of the screen's list.
func decorations() -> Array[DecoState]:
	var found: Array[DecoState] = []
	if _sim.sector == null or _sim.screen_index < 0:
		return found
	var screen := _sim.sector.screens[_sim.screen_index]
	for placement in screen.bg_decos:
		found.append(DecoState.of(&"back_decos", placement))
	for placement in screen.mid_decos:
		found.append(DecoState.of(&"mid_decos", placement))
	for placement in screen.fg_decos:
		found.append(DecoState.of(&"front_decos", placement))
	return found


## The animated decorations of the shown screen, as they are after `screen_ticks()` ticks.
func anim_decorations() -> Array[AnimDecoState]:
	var found: Array[AnimDecoState] = []
	if _sim.sector == null or _sim.screen_index < 0:
		return found
	for record in _sim.sector.screens[_sim.screen_index].anim_decos:
		found.append(AnimDecoState.of(record, screen_ticks()))
	return found


## How many ticks the shown screen has run: what its animated decorations have stepped (0 when the screen was laid out in this tick or between ticks, and no tick has finished since).
func screen_ticks() -> int:
	return maxi(_sim.tick_number - _sim.screen_started_tick, 0)


## The station of the shown screen, or null when it has none.
func station() -> StationState:
	if _sim.screen_index != 0 and _sim.screen_index != SimWorld.DOCK_SCREEN:
		return null
	var state := StationState.new()
	state.left = _sim.screen_index == 0
	var trip := _sim.sequence
	if trip != null:
		if trip.is_drive():
			state.door_picture = trip.door_picture()
		else:
			state.balloon_shown = not trip.is_done()
	return state


## The trip at a supply station that is running, or the last one that ran (`done`); null before the first.
func sequence() -> SequenceState:
	return SequenceState.of(_sim.sequence) if _sim.sequence != null else null


## Is the sub dissolving now? And how far: `dissolve_elapsed()` of `dissolve_ticks()` ticks of 1/73 s (0 / 0 when it is not).
func is_dissolving() -> bool:
	return _sim.is_dissolving()


## The sub dissolved away in this sector load and nothing of it is drawn until it is placed again (`SimWorld.is_dissolved`).
func is_dissolved() -> bool:
	return _sim.is_dissolved()


func dissolve_elapsed() -> int:
	return maxi(_sim.dissolve_elapsed, 0)


func dissolve_ticks() -> int:
	return _sim.dissolve_ticks if _sim.is_dissolving() else 0


## The dissolve's progress, 0..1 (0 when it is not running).
func dissolve_progress() -> float:
	return float(dissolve_elapsed()) / dissolve_ticks() if is_dissolving() else 0.0


## Is the tile at (`column`, `row`) of the shown screen a wall? (38 x 18 tiles of 16 px.)
func is_solid(column: int, row: int) -> bool:
	return _sim.tile_grid.is_solid(column, row)


## The water current at the tile (`column`, `row`) as a direction, in steps of -1..1; zero where the water is still.
func current_at(column: int, row: int) -> Vector2i:
	return _sim.tile_grid.current_at(column, row)
