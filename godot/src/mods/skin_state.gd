class_name SkinState
extends RefCounted
## What a skin mod is told about the sector: PLAIN DATA made from a `SimView` (the skin API, `docs/create/SKIN_API.md`), never an object of the rules. `build` is the one builder of the state a
## script gets (`skin_frame(state, fraction, events)`): it reads every field from `view`, the owner's read-only window onto the rules, so a presenter bound in the middle of anything builds
## what one bound from the start builds. `event` makes one entry of the `events` list from what the view's signal carried. The Dictionaries, Arrays and values are made fresh per call and made
## read-only (`ModLoader.freeze`), so a script cannot change what the next frame is told, and none of them holds an object.
##
## The keys are listed in `docs/create/SKIN_API.md`, "The state of a skin mod". Places are playfield pixels (x 0..607, y 0..287) as in `SimView`; a thing that moves has `previous` and `current`,
## and the script puts it `fraction` of the way from one to the other (`previous.lerp(current, fraction)`), as `SimView.Motion.at` does.
##
## Teaches: a read-only edge drawn by copying into the plainest form there is: values. What crosses into a sandbox needs no class, no method and no grant when it is a Dictionary of numbers.

const COLUMNS := TileGrid.COLUMNS
const ROWS := TileGrid.ROWS
## The most events one call carries (the newest): a presenter that is not drawn for a while does not build a list as long as the game.
const MAX_EVENTS := 256


## The state of the sector `view` looks at.
static func build(view: SimView) -> Dictionary:
	var creatures: Array = []
	for creature in view.creatures():
		if creature.shown:
			creatures.append(_creature(creature))
	var pellets: Array = []
	for pellet in view.pellets():
		pellets.append({
			"id": pellet.id, "splashing": pellet.splashing, "splash_picture": pellet.splash_picture, "splash_offset": pellet.splash_offset,
			"previous": pellet.motion.previous, "current": pellet.motion.current,
		})
	var pieces: Array = []
	for piece in view.pieces():
		pieces.append({"index": piece.index, "canister": piece.is_canister, "position": piece.position})
	var state := {
		"sector": view.sector_index,
		"screen": view.screen_index,
		"zone": view.zone,
		"tick": view.tick_number,
		"sub": _sub(view.sub()),
		"creatures": creatures,
		"pellets": pellets,
		"pieces": pieces,
		"sequence": _sequence(view.sequence()),
		"dissolve": {"running": view.is_dissolving(), "elapsed": view.dissolve_elapsed(), "ticks": view.dissolve_ticks(), "progress": view.dissolve_progress(), "done": view.is_dissolved()},
		"walls": walls(view),
	}
	ModLoader.freeze(state)
	return state


## One entry of the `events` list: `[name, arguments...]`, the name a String and each argument a number, a bool, a place or a name (a creature, a pellet, a piece or a trigger is its index or
## id, a supply trip its kind). `args` is what the view's signal carried.
static func event(name: StringName, args: Array) -> Array:
	var entry: Array = [String(name)]
	for arg: Variant in args:
		entry.append(_plain(arg))
	return entry


## The walls of the shown screen as one String, `COLUMNS` characters a row, `ROWS` rows: "1" for a wall tile, "0" for water. The tile at (column, row) is the character at `row * COLUMNS + column`.
static func walls(view: SimView) -> String:
	var bytes := PackedByteArray()
	bytes.resize(COLUMNS * ROWS)
	for row in ROWS:
		for column in COLUMNS:
			bytes[row * COLUMNS + column] = 49 if view.is_solid(column, row) else 48
	return bytes.get_string_from_ascii()


static func _sub(sub: SimView.SubState) -> Dictionary:
	return {
		"previous": sub.motion.previous, "current": sub.motion.current, "cell": sub.cell, "propeller_phase": sub.propeller_phase, "picture": sub.picture, "mirrored": sub.mirrored,
		"visible": sub.picture_visible, "bubble": sub.bubble_picture, "invulnerability": sub.invulnerability, "blinking": sub.blinking, "beacon": sub.message_light,
		"active": sub.active, "controlled": sub.controlled, "hurt_rect": Rect2(sub.hurt_rect), "wall_rect": Rect2(sub.wall_rect),
	}


static func _creature(creature: SimView.CreatureState) -> Dictionary:
	return {
		"index": creature.index, "picture": creature.picture, "mirrored": creature.mirrored, "previous": creature.motion.previous, "current": creature.motion.current,
		"jumped": creature.jumped, "was_hidden": creature.was_hidden, "damage": creature.damage, "hit_rect": Rect2(creature.hit_rect),
	}


## The supply trip as plain values, or null before the first. `balloon_previous` and `balloon_current` are the balloon's corner at the start and the end of the tick (it is `balloon_position(fraction)`
## in between); `door` is the door's picture (2 closed, 3 and 4 moving, -1 open).
static func _sequence(trip: SimView.SequenceState) -> Variant:
	if trip == null:
		return null
	return {
		"kind": trip.kind, "ticks": trip.ticks, "started_tick": trip.started_tick, "elapsed": trip.elapsed, "done": trip.done, "drive": trip.is_drive(), "door": trip.door_picture(),
		"balloon_previous": trip.balloon_position(0.0), "balloon_current": trip.balloon_position(1.0),
	}


static func _plain(value: Variant) -> Variant:
	if value is SimView.CreatureState:
		return value.index
	if value is SimView.PieceState:
		return value.index
	if value is SimView.TriggerState:
		return value.index
	if value is SimView.PelletState:
		return value.id
	if value is SimView.SequenceState:
		return value.kind
	if value is SimView.SubState:
		return null
	if value is StringName:
		return String(value)
	return value
