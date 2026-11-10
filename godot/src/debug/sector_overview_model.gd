@tool
class_name SectorOverviewModel
extends RefCounted
## Everything the sector overview shows, as plain data: the layout of the screens, the objects on each screen with the rectangle
## they occupy and the text that describes them, the reachability of the sub and the paths of the creatures.
##
## Teaches: keeping "what is true" apart from "how it is drawn". `SectorOverviewCanvas` only paints and clicks; this class holds
## the sector's facts, so it runs headless and `tests/engine/test_sector_overview.gd` can check them (every piece is listed, the
## canister is the first piece, a screen's creatures are those whose record puts them there, ...). The expensive parts (the
## reachability search, the creature traces) are made when first asked for and then kept.
##
## Positions are PLAYFIELD pixels (0..608 x 0..288, the screen drawn in the middle of the window, DESIGN 3.1): the data's window
## pixels minus `Sub.PLAYFIELD_ORIGIN`, so a view can scale one number and place it.
##
## @tool: the overview also runs inside the Godot editor (the `sector_overview` addon).

enum Kind { PIECE, CANISTER, CREATURE, TRIGGER, START, LAUNCH, DOCK, FINALE }

const ORIGIN := Vector2(16, 32)          # = SubModel.PLAYFIELD_ORIGIN (kept here so that a @tool script need not load the rules)

var sector: SectorData
var layout: SectorLayout
## The rule values the overview speaks of (the screen of the respawn point, the creatures' limit): the chain's, resolved when the model is made.
var tuning: Tuning
## Settings of the traces and of the search (set before asking).
var trace_ticks: int = CreaturePaths.DEFAULT_TICKS
var sub_preset: int = 1
var reach_mode: SectorReach.Mode = SectorReach.Mode.ORTHOGONAL

var _objects: Dictionary = {}              # screen -> Array[Dictionary]
var _paths: Dictionary = {}                # [screen, preset, ticks] -> Array[CreaturePaths.Path]
var _reach: Reach = null
var _reach_mode_made: int = -1


## The sector `index` of the catalog.
static func for_sector(index: int) -> SectorOverviewModel:
	return SectorOverviewModel.new(Catalog.sector(index))


func _init(source: SectorData = null) -> void:
	if source == null:
		return
	tuning = Tuning.resolve()
	sector = source
	layout = SectorLayout.from_sector(source)
	for screen in SectorData.SCREEN_COUNT:
		_objects[screen] = []
	_collect_objects()


# --- the objects ----------------------------------------------------------------------------------------------------

## The objects of `screen`, back to front: dictionaries {kind: Kind, screen, index, rect: Rect2 (playfield pixels), title, text}.
## `index` is the number in its list (the piece number, the creature number, the trigger's place in the screen's list; 0 for the
## rest). Creatures are listed on the screen their record starts them on.
func objects(screen: int) -> Array:
	return _objects.get(screen, [])


## Every object of the sector.
func all_objects() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for screen in SectorData.SCREEN_COUNT:
		for object: Dictionary in _objects[screen]:
			found.append(object)
	return found


## The objects of `kind` on `screen`.
func objects_of(screen: int, kind: Kind) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for object: Dictionary in objects(screen):
		if object["kind"] == kind:
			found.append(object)
	return found


## The topmost object of `screen` whose rectangle, grown by `slack` playfield pixels on every side (so that a small marker is
## easy to hit), contains `point` (playfield pixels); an empty dictionary when there is none. Later objects are drawn on top.
func object_at(screen: int, point: Vector2, slack: float = 0.0) -> Dictionary:
	var list := objects(screen)
	for i in range(list.size() - 1, -1, -1):
		var object: Dictionary = list[i]
		if (object["rect"] as Rect2).grow(slack).has_point(point):
			return object
	return {}


func _collect_objects() -> void:
	var meta := SpriteMeta.for_zone(sector.zone)
	var registry := NameRegistry.original()
	# the places of the sub: where a game starts it, and where a sector ends (the supply stations stand on screens 0 and 11)
	var launch := Vector2(CreaturePaths.SUB_LAUNCH) - ORIGIN
	_add(0, Kind.LAUNCH, 0, Rect2(launch, Vector2(96, 58)), "launch point",
			"Where the supply station lets the sub go at the start of a sector: SubX 96, SubY 202, cell 6 (`ExitSupplyStation`). The reachability search starts here.")
	var start := Vector2(sector.start_pos) - ORIGIN
	_add(0, Kind.START, 0, Rect2(start, Vector2(96, 58)), "start position",
			"Header start: x %d, y %d, picture %d. The sub shows here in the finale sectors' header and appears here on screen %d after a lost tank past the middle of the sector." % [
					sector.start_pos.x, sector.start_pos.y, sector.start_frame, tuning.midpoint_screen])
	var dock := Rect2(Vector2(ReachSweep.DOCK_MIN_X, ReachSweep.DOCK_MIN_Y) - ORIGIN,
			Vector2(SectorReach.X_MAX + 2 - ReachSweep.DOCK_MIN_X, ReachSweep.DOCK_MAX_Y - ReachSweep.DOCK_MIN_Y + 58))
	_add(ReachSweep.DOCK_SCREEN, Kind.DOCK, 0, dock, "end station",
			"The sub docks when it is at SubX >= %d and SubY %d..%d on screen %d (cell %d or more): the sector ends." % [
					ReachSweep.DOCK_MIN_X, ReachSweep.DOCK_MIN_Y, ReachSweep.DOCK_MAX_Y, ReachSweep.DOCK_SCREEN, SimWorld.DOCK_MIN_CELL])
	var finale := sector.finale_screen
	if finale >= 0:
		_add(finale, Kind.FINALE, 0, Rect2(Vector2.ZERO, Vector2(TileGrid.PLAYFIELD_SIZE)).grow(-3), "finale screen",
				"The closing sequence starts when the sub reaches this screen with the treasure (creature 0).")
	for screen in sector.screens.size():
		for k in sector.screens[screen].triggers.size():
			var trigger := sector.screens[screen].triggers[k]
			_add(screen, Kind.TRIGGER, k, Rect2(Vector2(trigger.pos) - ORIGIN - Vector2(4, 4), Vector2(8, 8)),
					"math trigger %d (slot %d)" % [k, trigger.slot],
					"Starts problem slot %d (the problem type depends on the educational level, `TriggerTable`). Flags 0x%02x: %s, %s, test nibble %d. At x %d, y %d." % [
							trigger.slot, trigger.flags, "armed" if trigger.armed else "not armed", "re-arms when the screen is entered" if trigger.rearm_on_enter else "stays used",
							trigger.test_nibble, trigger.pos.x, trigger.pos.y])
	for i in sector.pieces.size():
		var piece := sector.pieces[i]
		var canister := piece.is_canister
		_add(piece.screen, Kind.CANISTER if canister else Kind.PIECE, i, Rect2(Vector2(piece.pos) - ORIGIN, Vector2(PieceModel.PICTURE_SIZE)),
				"data canister (piece 0)" if canister else "piece %d" % i,
				"%s at x %d, y %d on screen %d." % ["The data canister" if canister else "A piece of the rock sample", piece.pos.x, piece.pos.y, piece.screen])
	for i in sector.foes.size():
		var foe := sector.foes[i]
		var size: Vector2i = meta.sizes[foe.frame & 0x7F] if (foe.frame & 0x7F) < meta.sizes.size() else Vector2i(16, 16)
		var picture := registry.name_of(&"frame", foe.frame & 0x7F, sector.zone)
		_add(foe.screen, Kind.CREATURE, i, Rect2(Vector2(foe.pos) - ORIGIN, Vector2(size)), "creature %d (%s)" % [i, picture],
				"%s%s. Starts at x %d, y %d on screen %d, picture %s%s. Damage %d%s.\nstart label `%s`, contact label `%s`, ink label `%s`." % [
						"Friendly" if foe.damage < 0 else ("Harmless" if foe.damage == 0 else "Hostile"),
						", dormant until a script wakes it" if foe.dormant else "", foe.pos.x, foe.pos.y, foe.screen, picture,
						" (mirrored)" if foe.flip else "", foe.damage, ", starts hidden" if foe.hidden else "",
						foe.start_label, foe.hit_label, foe.ink_label])


func _add(screen: int, kind: Kind, index: int, rect: Rect2, title: String, text: String) -> void:
	if screen < 0 or screen >= SectorData.SCREEN_COUNT:
		return
	_objects[screen].append({"kind": kind, "screen": screen, "index": index, "rect": rect, "title": title, "text": text})


# --- the screens --------------------------------------------------------------------------------------------------------

## A few lines about one screen: where it sits, what it leads to, how many of each thing it holds.
func screen_text(screen: int) -> String:
	var data := sector.screens[screen]
	var walls := 0
	var currents := 0
	for byte in data.tiles:
		if byte & TileCodec.SOLID_BIT:
			walls += 1
		elif byte & TileCodec.CURRENT_BIT:
			currents += 1
	var lines: Array[String] = ["Screen %d of sector %d, at cell %s%s." % [
			screen, sector.index, layout.cell_of[screen], "" if layout.group_of[screen] == 0 else " (not connected to the start screen: group %d)" % layout.group_of[screen]]]
	var leads: Array[String] = []
	for side in 4:
		var target := layout.neighbours[side][screen]
		leads.append("%s %s" % [SectorLayout.SIDE_NAMES[side], "-" if target < 0 else str(target)])
	lines.append("Leads to: " + ", ".join(leads) + ".")
	lines.append("%d wall tiles, %d current tiles, %d decorations, %d animated, %d math triggers." % [
			walls, currents, data.bg_decos.size() + data.mid_decos.size() + data.fg_decos.size(), data.anim_decos.size(), data.triggers.size()])
	lines.append("%d pieces (%d canister), %d creatures start here." % [
			objects_of(screen, Kind.PIECE).size() + objects_of(screen, Kind.CANISTER).size(), objects_of(screen, Kind.CANISTER).size(),
			objects_of(screen, Kind.CREATURE).size()])
	for link in layout.links:
		if link["screen"] == screen and link["kind"] != SectorLayout.Kind.OK:
			lines.append(("Problem: " if link["kind"] != SectorLayout.Kind.ONE_WAY else "One-way: ") + link["text"])
	return "\n".join(lines)


# --- the reachability overlay (SectorReach) -------------------------------------------------------------------------------

## What the search found: `visited` is `SectorReach`'s one-byte-per-state array; the rest is derived from it.
class Reach extends RefCounted:
	var mode: SectorReach.Mode = SectorReach.Mode.ORTHOGONAL
	var visited: PackedByteArray = PackedByteArray()
	var states: int = 0
	## Per piece (like `SectorData.pieces`): can the sub touch it (the original's pick-up rule)?
	var piece_reachable: Array[bool] = []
	## Per screen: does the sub get there at all?
	var screen_reached: Array[bool] = []
	## Can the sub drive into the end station?
	var dock_reachable: bool = false
	var seconds: float = 0.0
	var _masks: Dictionary = {}

	## The picture of where the CENTRE of the sub can be on `screen`, as a 304 x 288 RGBA image (translucent `color` where it can,
	## clear elsewhere). The search's states are SubX (even, -32..574) and SubY (3..290) of the picture's top-left corner; the centre
	## lies (48, 27) further, and the playfield starts at (16, 32) of the window. So column i is exactly playfield x = 2 i
	## (2 i - 32 + 48 - 16) and row j is playfield y = j - 2 (j + 3 + 27 - 32): draw the image 608 pixels wide and one pixel per row,
	## from y = -2.
	func mask(screen: int, color: Color = Color(0.2, 1.0, 0.35, 0.42)) -> Image:
		if _masks.has(screen):
			return _masks[screen]
		var bytes := PackedByteArray()
		bytes.resize(SectorReach.PER_SCREEN * 4)
		var base := screen * SectorReach.PER_SCREEN
		for i in SectorReach.PER_SCREEN:
			if visited[base + i] != 0:
				bytes[i * 4] = color.r8
				bytes[i * 4 + 1] = color.g8
				bytes[i * 4 + 2] = color.b8
				bytes[i * 4 + 3] = color.a8
		var image := Image.create_from_data(SectorReach.X_COUNT, SectorReach.Y_COUNT, false, Image.FORMAT_RGBA8, bytes)
		_masks[screen] = image
		return image


## The reachability of the sub from the launch point (`SectorReach`, the model of `docs/port/DESIGN.md` 3.3 that the sweep tests use).
## Made on first use for the current `reach_mode`, then kept.
func reach() -> Reach:
	if _reach == null or _reach_mode_made != reach_mode:
		var started := Time.get_ticks_msec()
		var search := SectorReach.from_sector(sector, tuning.sub)
		search.build()
		var result := Reach.new()
		result.mode = reach_mode
		result.visited = search.explore([SectorReach.LAUNCH], reach_mode)
		result.states = SectorReach.count(result.visited)
		for piece in sector.pieces:
			result.piece_reachable.append(SectorReach.first_pickup_original(result.visited, piece.screen, piece.pos.x, piece.pos.y).x >= 0)
		for screen in SectorData.SCREEN_COUNT:
			result.screen_reached.append(SectorReach.any_on_screen(result.visited, screen))
		result.dock_reachable = SectorReach.first_state_in(result.visited, ReachSweep.DOCK_SCREEN, ReachSweep.DOCK_MIN_X,
				SectorReach.X_MAX, ReachSweep.DOCK_MIN_Y, ReachSweep.DOCK_MAX_Y).x >= 0
		result.seconds = (Time.get_ticks_msec() - started) / 1000.0
		_reach = result
		_reach_mode_made = reach_mode
	return _reach


## One line about the search, for the status bar.
func reach_summary() -> String:
	var result := reach()
	var lost: Array[int] = []
	for i in result.piece_reachable.size():
		if not result.piece_reachable[i]:
			lost.append(i)
	var dark: Array[int] = []
	for screen in result.screen_reached.size():
		if not result.screen_reached[screen]:
			dark.append(screen)
	return "reachable (%s): %d states in %.1f s; pieces out of reach: %s; screens never entered: %s; end station: %s" % [
			ReachSweep.MODE_NAMES[result.mode], result.states, result.seconds, str(lost) if not lost.is_empty() else "none",
			str(dark) if not dark.is_empty() else "none", "reachable" if result.dock_reachable else "NOT reachable"]


# --- the creature paths (CreaturePaths) ---------------------------------------------------------------------------------

## The paths of the creatures on `screen` for the current settings (`trace_ticks`, `sub_preset`), made on first use.
func paths(screen: int) -> Array[CreaturePaths.Path]:
	var key := [screen, sub_preset, trace_ticks]
	if not _paths.has(key):
		_paths[key] = CreaturePaths.trace_screen(sector, screen, trace_ticks, CreaturePaths.SUB_PRESETS[sub_preset], CreaturePaths.DEFAULT_SEED, tuning)
	return _paths[key]


## The path of creature `foe_index` on `screen`, or null (it never was there).
func path_of(foe_index: int, screen: int) -> CreaturePaths.Path:
	for path in paths(screen):
		if path.foe_index == foe_index:
			return path
	return null
