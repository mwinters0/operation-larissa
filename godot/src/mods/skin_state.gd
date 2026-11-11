class_name SkinState
extends RefCounted
## What a skin mod is told about the sector: PLAIN DATA made from a `SimView` (the skin API, `docs/create/SKIN_API.md`), never an object of the rules. `build` is the one builder of the state a
## script gets (`skin_layer(name, state, fraction, events)`, or `skin_frame(state, fraction, events)`): it reads every field from `view`, the owner's read-only window onto the rules, so a presenter bound in the middle of anything builds
## what one bound from the start builds. `event` makes one entry of the `events` list from what the view's signal carried. The Dictionaries, Arrays and values are made fresh per call and made
## read-only (`ModLoader.freeze`), so a script cannot change what the next frame is told, and none of them holds an object.
##
## The screen's own content (the background, the decorations, the station) is told by NAME, not as a picture: a `key` is the skin key of the picture as the pack in use holds it (`GameSkin.key_of`: `background/bg_s00_00`, `deco/coral_fan_cyan`,
## `frame/station_00`), with the `size` of that picture, and what the game draws for the key is the skin's business. It is built from the same `SimView` each time, like the rest: nothing about the screen is kept between builds (a screen is
## some forty small dictionaries, a cost the walls' 684 characters already exceed), so a skin bound on any screen is told the screen.
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
		"background": Assets.background_key(view.sector_index, view.screen_index),
		"decos": _decos(view),
		"anim_decos": _anim_decos(view),
		"station": _station(view),
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


## The still decorations of the screen (`SimView.decorations`), one entry for each of the layers `back_decos`, `mid_decos` and `front_decos` (each in the order of the screen's list, the order they are drawn), and in each COLUMNS: parallel Arrays
## `slot`, `key`, `position` (the top-left corner), `size` (the picture's) and `mirrored`, the picture at index i being the i-th of each. A screen has up to a hundred and fifty of them, and a script may hold only so many host objects at once
## (`references_max`): an Array of Dictionaries costs one for each decoration, a few Arrays of values cost nothing more (`tests/legacy/test_mod_skin_legacy.gd` walks the biggest screens there are).
static func _decos(view: SimView) -> Dictionary:
	var layers := {}
	for layer in [&"back_decos", &"mid_decos", &"front_decos"]:
		layers[String(layer)] = {"slot": [], "key": [], "position": [], "size": [], "mirrored": []}
	if view.zone < 0:
		return layers
	var frames := Catalog.pack_decos_frames(view.zone)
	for deco in view.decorations():
		var picture := _picture(frames, deco.slot)
		var columns: Dictionary = layers[String(deco.layer)]
		(columns["slot"] as Array).append(deco.slot)
		(columns["key"] as Array).append(picture["key"])
		(columns["position"] as Array).append(deco.position)
		(columns["size"] as Array).append(picture["size"])
		(columns["mirrored"] as Array).append(deco.mirrored)
	return layers


## The animated decorations (`SimView.anim_decorations`) in columns too: `position`, `size` and `key` of the picture it shows, `frame` (its slot, -1 when it has no frames) and `cursor` (the entry of its frame list it is at: one step a tick, looping).
static func _anim_decos(view: SimView) -> Dictionary:
	var columns := {"position": [], "size": [], "key": [], "frame": [], "cursor": []}
	if view.zone < 0:
		return columns
	var frames := Catalog.pack_decos_frames(view.zone)
	for deco in view.anim_decorations():
		var picture := _picture(frames, deco.frame)
		(columns["position"] as Array).append(deco.position)
		(columns["size"] as Array).append(picture["size"])
		(columns["key"] as Array).append(picture["key"])
		(columns["frame"] as Array).append(deco.frame)
		(columns["cursor"] as Array).append(deco.cursor)
	return columns


## The station of the screen, or null. `side` is "left" or "right"; `parts` are the pictures it is made of in the order they are drawn (`StationLayout.parts`): `name` (`balloon`, `body_a`, `body_b`, `body_c`, `door`), `picture` (its number in
## the station's pictures, -1 for an open door), `key`, `size`, `position`, `mirrored` and `shown` (the balloon only while a trip raises it, the door unless it is open). `previous` is where the part was a tick before: the same as `position`
## for all but the balloon, whose `position` and `previous` are those of the trip (`sequence.balloon_current` and `balloon_previous`).
static func _station(view: SimView) -> Variant:
	var station := view.station()
	if station == null:
		return null
	var trip := view.sequence()
	var frames := Catalog.pack_station_frames()
	var parts: Array = []
	for part in StationLayout.parts(station.left):
		var part_name := String(part["name"])
		var picture_number: int = station.door_picture if part_name == "door" else part["picture"]
		var picture := _picture(frames, picture_number)
		var shown := picture_number >= 0 and (station.balloon_shown if part_name == "balloon" else true)
		var entry := {"name": part_name, "picture": picture_number, "key": picture["key"], "size": picture["size"], "position": part["position"], "mirrored": part["mirrored"], "shown": shown}
		if part_name == "balloon" and trip != null and not trip.is_drive():
			entry["position"] = trip.balloon_position(1.0)
			entry["previous"] = trip.balloon_position(0.0)
		else:
			entry["previous"] = entry["position"]
		parts.append(entry)
	return {"side": "left" if station.left else "right", "parts": parts}


## The key and size of picture `slot` of `frames` as the pack holds it: "" and (0, 0) for a slot it has none of.
static func _picture(frames: SpriteFrames, slot: int) -> Dictionary:
	if frames == null or slot < 0 or slot >= frames.get_frame_count(&"all"):
		return {"key": "", "size": Vector2.ZERO}
	var texture := frames.get_frame_texture(&"all", slot)
	return {"key": GameSkin.key_of(Packs.source_of(texture)), "size": Vector2(texture.get_size())}


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
