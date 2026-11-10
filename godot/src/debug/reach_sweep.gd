class_name ReachSweep
extends RefCounted
## Runs `SectorReach` over every sector and answers the questions that matter for "can the player finish this level?":
## can the sub touch every piece (and the data canister), drive into the end station, and, in the finale sectors, touch the
## treasure and then reach the screen on which the closing sequence starts?
##
## Teaches: preparing plain data on the main thread (Resources are not for worker threads), then running one independent
## job per sector with `WorkerThreadPool`, and keeping the "what is true" (a result Dictionary) apart from the "what do we
## make of it" (the test, or `report_line`).
##
## Where the sub starts: the original calls `ExitSupplyStation` (SubX 0 -> 96, SubY 202, cell 6) whenever a sector begins on
## screen 0 - for the two finale sectors too (`DoAction` 0x417ffc has no sector test), and so does the port
## (`SimWorld.begin_sector`). The header-position start of the finales (the port's old behaviour) is still searched as a second seed.
## After a lost tank past the midpoint the sub appears on screen 6 at the header position (the "respawn" seed).

# The dock and the midpoint are the game's own constants (fixed in the original program, not in the data).
const DOCK_SCREEN := SimWorld.DOCK_SCREEN
const DOCK_MIN_X := SimWorld.DOCK_MIN_X       # DoAction: SubX >= 0x158, 0xaa <= SubY <= 0xea, SubCell >= 6
const DOCK_MIN_Y := SimWorld.DOCK_MIN_Y
const DOCK_MAX_Y := SimWorld.DOCK_MAX_Y
## Currents at least this strong cannot be out-thrust (a key adds 12 units per tick).
const STRONG_CURRENT := 12
const CELL_COUNT := 9
const MODE_NAMES: Array[String] = ["ortho", "diag", "fast"]


## Main thread only: everything a job needs, as plain data.
static func prepare(sector_index: int, rule_values: Tuning = null) -> Dictionary:
	return prepare_for(Catalog.sector(sector_index), rule_values)


## The same for a sector that is in memory (a copy being edited, a sector that is not one of the original's): `SectorChecks` uses it.
## The sector must be searchable (`SectorChecks.is_searchable`): 12 screens of 684 tiles, neighbour tables of 12, pieces on real screens.
## `rule_values` is the `Tuning` the search runs on (the sub's rectangles, the respawn screen, the creatures' limit): left out, the chain's,
## resolved here; a caller that prepares many sectors resolves once and passes it.
static func prepare_for(sector: SectorData, rule_values: Tuning = null) -> Dictionary:
	var sector_index := sector.index
	var tuning := rule_values if rule_values != null else Tuning.resolve()
	var job := {
		"index": sector_index,
		"reach": SectorReach.from_sector(sector, tuning.sub),
		"start": sector.start_pos,
		"pieces": [],
		"cell_rects": tuning.sub.frame_rects.duplicate(),
		"tuning": tuning,
		"midpoint_screen": tuning.midpoint_screen,
		"finale_screen": sector.finale_screen,
		"finale_object": [],
		"sector": sector,
		"meta": SpriteMeta.for_zone(sector.zone),
	}
	for i in sector.pieces.size():
		var piece := sector.pieces[i]
		job["pieces"].append({"index": i, "screen": piece.screen, "pos": piece.pos, "canister": piece.is_canister})
	if sector.finale_screen >= 0:
		job["finale_object"] = _finale_object_rects(sector, tuning)
	return job


## Window-pixel hit rectangles (with the screen) that creature 0 - the treasure - takes while its script runs. Sampled by running
## the creature's VM for a while; a treasure that sits still gives one entry.
static func _finale_object_rects(sector: SectorData, tuning: Tuning) -> Array:
	var meta := SpriteMeta.for_zone(sector.zone)
	var context := FoeVM.Context.new(tuning)
	for i in sector.foes.size():
		context.foes.append(FoeVM.from_data(sector.foes[i], i, sector))
	var treasure: FoeVM = context.foes[0]
	var seen := {}
	var rects: Array = []
	for t in 1200:
		context.current_screen = treasure.screen
		context.sub_x = 300
		context.sub_y = 150
		treasure.tick(context)
		if treasure.hidden:
			continue
		var r := meta.hit_rect(treasure.frame, treasure.flip)
		var key := Vector4i(treasure.screen, treasure.x, treasure.y, treasure.frame * 2 + int(treasure.flip))
		if not seen.has(key):
			seen[key] = true
			rects.append({"screen": treasure.screen, "rect": Rect2i(r.position + Vector2i(treasure.x, treasure.y), r.size)})
	return rects


## Runs `analyze` for each prepared job on the worker threads and returns the results in the same order.
static func run_all(jobs: Array) -> Array:
	return parallel(jobs, analyze)


## Calls `work(job)` for every job on the `WorkerThreadPool` (a job is plain data and a `SectorReach` of its own, so the calls share nothing)
## and returns the results in the order of the jobs.
static func parallel(jobs: Array, work: Callable) -> Array:
	var results: Array = []
	results.resize(jobs.size())
	var mutex := Mutex.new()
	var one := func(i: int) -> void:
		var result: Variant = work.call(jobs[i])
		mutex.lock()
		results[i] = result
		mutex.unlock()
	var task := WorkerThreadPool.add_group_task(one, jobs.size(), -1, true, "reachability sweep")
	WorkerThreadPool.wait_for_group_task_completion(task)
	return results


# --- the analysis of one sector ------------------------------------------------------------------------------------

## Thread-safe. Result keys: index, pieces (array of per piece dictionaries), dock, finale, respawn, port_start, seconds, midpoint_screen
## (the screen of the respawn point, from the job's `Tuning`).
static func analyze(job: Dictionary) -> Dictionary:
	var started := Time.get_ticks_msec()
	var reach: SectorReach = job["reach"]
	var index: int = job["index"]
	reach.build()
	var result := {"index": index, "pieces": [], "seconds": 0.0, "midpoint_screen": job["midpoint_screen"]}

	# --- the main search, from the launch ---
	var midpoint_screen: int = job["midpoint_screen"]
	var search := _Search.new(reach, [SectorReach.LAUNCH])
	var states := search.visited(SectorReach.Mode.ORTHOGONAL)
	result["states"] = SectorReach.count(states)
	result["screens_visited"] = _screens_with_states(states)
	var cell_rects: Array = job["cell_rects"]
	for piece: Dictionary in job["pieces"]:
		result["pieces"].append(_check_piece(search, piece, cell_rects))
	if job["finale_screen"] < 0:                       # (a finale has no dock to reach: the treasure ends the game)
		result["dock"] = search.level_of(func(v: PackedByteArray) -> bool:
			return SectorReach.first_state_in(v, DOCK_SCREEN, DOCK_MIN_X, SectorReach.X_MAX, DOCK_MIN_Y, DOCK_MAX_Y).x >= 0)
	if job["finale_screen"] >= 0:
		result["finale"] = _check_finale(search, job, cell_rects)
		# the header position on screen 0 instead of the launch (the port used to start the finales there)
		var start: Vector2i = job["start"]
		var port_search := _Search.new(reach, [Vector3i(0, start.x & ~1, start.y)])
		result["finale_port_start"] = _check_finale(port_search, job, cell_rects)

	# --- after a death past the midpoint: screen 6, header position ---
	if job["finale_screen"] < 0:
		var start: Vector2i = job["start"]
		var respawn_search := _Search.new(reach, [Vector3i(midpoint_screen, start.x & ~1, start.y)])
		var missing: Array = []
		for piece: Dictionary in job["pieces"]:
			if piece["screen"] >= midpoint_screen:
				var checked := _check_piece(respawn_search, piece, cell_rects)
				if checked["orig_level"] < 0:
					missing.append(piece["index"])
		result["respawn_missing"] = missing
		result["respawn_dock"] = respawn_search.level_of(func(v: PackedByteArray) -> bool:
			return SectorReach.first_state_in(v, DOCK_SCREEN, DOCK_MIN_X, SectorReach.X_MAX, DOCK_MIN_Y, DOCK_MAX_Y).x >= 0)
		result["respawn_embedded"] = _embedded_start(reach, midpoint_screen, start.x & ~1, start.y)
	result["launch_embedded"] = _embedded_start(reach, 0, SectorReach.LAUNCH.y, SectorReach.LAUNCH.z)
	result["seconds"] = (Time.get_ticks_msec() - started) / 1000.0
	return result


## Memoises the search per mode, and answers "in the weakest mode in which this holds".
class _Search extends RefCounted:
	var reach: SectorReach
	var seeds: Array
	var _cache := {}

	func _init(r: SectorReach, s: Array) -> void:
		reach = r
		seeds = s

	func visited(mode: SectorReach.Mode) -> PackedByteArray:
		if not _cache.has(mode):
			_cache[mode] = reach.explore(seeds, mode)
		return _cache[mode]

	## Index of the first mode (0 ortho, 1 diag, 2 fast) for which `test` is true, or -1.
	func level_of(test: Callable) -> int:
		for mode in 3:
			if test.call(visited(mode)):
				return mode
		return -1


static func _screens_with_states(states: PackedByteArray) -> Array:
	var screens: Array = []
	for s in SectorReach.SCREENS:
		if SectorReach.any_on_screen(states, s):
			screens.append(s)
	return screens


## Is the sub, standing at (`screen`, x, y), inside solid tiles? (Not a hard error: the scan ignores tiles it overlaps.) Counts the
## solid tiles the wall box overlaps.
static func _embedded_start(reach: SectorReach, screen: int, sub_x: int, sub_y: int) -> int:
	var overlapping := 0
	var scan := SubModel.wall_scan_box(Vector2i(sub_x, sub_y), reach.wall_box)
	for row in range(maxi(scan.position.y / 16, 0), mini((scan.end.y - 1) / 16, SectorReach.ROWS - 1) + 1):
		for column in range(maxi(scan.position.x / 16, 0), mini((scan.end.x - 1) / 16, SectorReach.COLUMNS - 1) + 1):
			overlapping += reach.solid[screen][row * SectorReach.COLUMNS + column]
	return overlapping


## orig_level / port_level: weakest search mode that reaches the piece under the original's / the port's contact rule (-1: none);
## the cells are those whose rectangle makes the port's contact work at that level.
static func _check_piece(search: _Search, piece: Dictionary, cell_rects: Array) -> Dictionary:
	var pos: Vector2i = piece["pos"]
	var screen: int = piece["screen"]
	var out := {"index": piece["index"], "screen": screen, "pos": pos, "orig_level": -1, "port_level": -1, "port_cells": [],
			"orig_count": 0, "port_count": 0}
	if screen < 0 or screen >= SectorReach.SCREENS:
		return out
	out["orig_level"] = search.level_of(func(v: PackedByteArray) -> bool:
		return SectorReach.first_pickup_original(v, screen, pos.x, pos.y).x >= 0)
	if out["orig_level"] >= 0:
		out["orig_count"] = SectorReach.count_states_in(search.visited(out["orig_level"]), screen, pos.x - 95, pos.x + 23, pos.y - 57, pos.y + 19)
	for mode in 3:
		var cells: Array = []
		var best := 0
		for c in CELL_COUNT:
			var r: Rect2i = cell_rects[c]
			var visited := search.visited(mode)
			if SectorReach.first_pickup_port(visited, screen, pos.x, pos.y, r).x >= 0:
				cells.append(c)
				best = maxi(best, SectorReach.count_states_in(visited, screen,
						pos.x - r.position.x - r.size.x, pos.x + 24 - r.position.x, pos.y - r.position.y - r.size.y, pos.y + 20 - r.position.y))
		if not cells.is_empty():
			out["port_level"] = mode
			out["port_cells"] = cells
			out["port_count"] = best
			break
	return out


## Finale: touch the treasure (creature 0, sub rectangle of some cell against its hit rectangle, inclusive), then reach the closing screen.
static func _check_finale(search: _Search, job: Dictionary, cell_rects: Array) -> Dictionary:
	var reach: SectorReach = search.reach
	var trigger_screen: int = job["finale_screen"]
	var out := {"touch_level": -1, "closing_level": -1, "cells": [], "trigger_screen": trigger_screen}
	for mode in 3:
		var visited := search.visited(mode)
		var touching: Array = []
		var cells := {}
		for entry: Dictionary in job["finale_object"]:
			for c in CELL_COUNT:
				var rect: Rect2i = cell_rects[c]
				var target: Rect2i = entry["rect"]
				var found := _states_touching(visited, entry["screen"], target, rect)
				if not found.is_empty():
					cells[c] = true
					touching.append_array(found)
		if touching.is_empty():
			continue
		if out["touch_level"] < 0:
			out["touch_level"] = mode
			out["cells"] = cells.keys()
		# from every state that touches the treasure, can the sub reach the closing screen?
		for after_mode in range(mode, 3):
			var after := reach.explore(touching, after_mode)
			if SectorReach.any_on_screen(after, trigger_screen):
				out["closing_level"] = after_mode
				return out
		return out
	return out


static func _states_touching(visited: PackedByteArray, screen: int, target: Rect2i, cell_rect: Rect2i) -> Array:
	var found: Array = []
	var x_from := target.position.x - cell_rect.position.x - cell_rect.size.x
	var x_to := target.end.x - cell_rect.position.x
	var y_from := target.position.y - cell_rect.position.y - cell_rect.size.y
	var y_to := target.end.y - cell_rect.position.y
	x_from = maxi(x_from + (x_from & 1), SectorReach.X_MIN)
	x_to = mini(x_to, SectorReach.X_MAX)
	for y in range(maxi(y_from, SectorReach.Y_MIN), mini(y_to, SectorReach.Y_MAX) + 1):
		var row := screen * SectorReach.PER_SCREEN + (y - SectorReach.Y_MIN) * SectorReach.X_COUNT
		for x in range(x_from, x_to + 1, 2):
			if visited[row + ((x - SectorReach.X_MIN) >> 1)] != 0:
				found.append(Vector3i(screen, x, y))
	return found


## Report-only: for every piece, how many of the states that touch it (original rule, reachable without currents) have the sub standing
## in a current tile, and in how many of those the current is at least 6 (the decay: weaker currents are cancelled by it when no key is held).
## Pieces whose every contact state is in a current are the ones where the "fine control" of SectorReach is the least certain.
static func pieces_in_currents(job: Dictionary) -> Array:
	var reach: SectorReach = job["reach"]
	var any_current := strong_current_mask(reach, 2)
	var visited := reach.explore([SectorReach.LAUNCH])
	var out: Array = []
	for piece: Dictionary in job["pieces"]:
		var screen: int = piece["screen"]
		var pos: Vector2i = piece["pos"]
		var total := SectorReach.count_states_in(visited, screen, pos.x - 95, pos.x + 23, pos.y - 57, pos.y + 19)
		var in_current := 0
		for y in range(maxi(pos.y - 57, SectorReach.Y_MIN), mini(pos.y + 19, SectorReach.Y_MAX) + 1):
			var row := screen * SectorReach.PER_SCREEN + (y - SectorReach.Y_MIN) * SectorReach.X_COUNT
			for x in range(maxi((pos.x - 95) + ((pos.x - 95) & 1), SectorReach.X_MIN), mini(pos.x + 23, SectorReach.X_MAX) + 1, 2):
				var i := row + ((x - SectorReach.X_MIN) >> 1)
				if visited[i] != 0 and any_current[i] != 0:
					in_current += 1
		if in_current > 0:
			out.append({"index": piece["index"], "screen": screen, "contact_states": total, "in_current": in_current})
	return out


# --- creatures that sit in the way (report only) ----------------------------------------------------------------------

## Creatures never block the sub (only the tile map does), but a hostile creature that never leaves its spot costs air whenever the
## sub passes it. Runs every creature's script for `ticks` ticks on each screen with the sub standing at two spots and collects the
## space each hostile, visible creature occupies; those that stay within 24 px of one place at least 60 % of the time are "fixed".
## Then asks which pieces / the dock cannot be reached without touching a fixed creature. Thread-safe.
## Returns {fixed: [{screen, index, rect, damage}], forced: [{target, creatures}]}.
static func creature_choke(job: Dictionary, ticks: int = 300) -> Dictionary:
	var sector: SectorData = job["sector"]
	var meta: SpriteMetaTable = job["meta"]
	var reach: SectorReach = job["reach"]
	var cell_rect: Rect2i = job["cell_rects"][6]
	var fixed: Array = []
	for screen in SectorReach.SCREENS:
		var seen := {}                       # foe index -> {rect, ticks}
		for sub_spot in [Vector2i(100, 150), Vector2i(480, 150)]:
			var context := FoeVM.Context.new(job["tuning"])
			for i in sector.foes.size():
				context.foes.append(FoeVM.from_data(sector.foes[i], i, sector))
			for t in ticks:
				context.current_screen = screen
				context.sub_x = sub_spot.x
				context.sub_y = sub_spot.y
				for vm: FoeVM in context.foes:
					vm.tick(context)
					if vm.screen != screen or vm.hidden or vm.damage <= 0 or vm.frame >= meta.count():
						continue
					var r := meta.hit_rect(vm.frame, vm.flip)
					var rect := Rect2i(r.position + Vector2i(vm.x, vm.y), r.size)
					if not seen.has(vm.index):
						seen[vm.index] = {"rect": rect, "ticks": 0, "damage": vm.damage}
					seen[vm.index]["rect"] = seen[vm.index]["rect"].merge(rect)
					seen[vm.index]["ticks"] += 1
		for index: int in seen:
			var entry: Dictionary = seen[index]
			var rect: Rect2i = entry["rect"]
			if entry["ticks"] >= 0.6 * ticks * 2 and rect.size.x <= 24 + 40 and rect.size.y <= 24 + 40:
				fixed.append({"screen": screen, "index": index, "rect": rect, "damage": entry["damage"]})
	var out := {"fixed": fixed, "forced": []}
	if fixed.is_empty():
		return out
	var open := reach.explore([SectorReach.LAUNCH])
	var all_blocked := _blocked_by(fixed, cell_rect)
	var closed := reach.explore([SectorReach.LAUNCH], SectorReach.Mode.ORTHOGONAL, all_blocked)
	var targets: Array = []
	for piece: Dictionary in job["pieces"]:
		targets.append({"name": "piece %d" % piece["index"], "screen": piece["screen"], "pos": piece["pos"]})
	if job["finale_screen"] < 0:
		targets.append({"name": "dock"})
	var without_creature := {}                  # creature -> what is reachable if only that one were passable
	for target: Dictionary in targets:
		if _target_reached(open, target) and not _target_reached(closed, target):
			var culprits: Array = []
			for creature: Dictionary in fixed:
				if not without_creature.has(creature):
					var others := fixed.duplicate()
					others.erase(creature)
					without_creature[creature] = reach.explore([SectorReach.LAUNCH], SectorReach.Mode.ORTHOGONAL, _blocked_by(others, cell_rect))
				if _target_reached(without_creature[creature], target):
					culprits.append("creature %d on screen %d" % [creature["index"], creature["screen"]])
			out["forced"].append({"target": target["name"], "creatures": culprits})
	return out


static func _target_reached(visited: PackedByteArray, target: Dictionary) -> bool:
	if target["name"] == "dock":
		return SectorReach.first_state_in(visited, DOCK_SCREEN, DOCK_MIN_X, SectorReach.X_MAX, DOCK_MIN_Y, DOCK_MAX_Y).x >= 0
	return SectorReach.first_pickup_original(visited, target["screen"], target["pos"].x, target["pos"].y).x >= 0


## A mask of the states in which the sub (cell `cell_rect`) touches one of the creature rectangles.
static func _blocked_by(creatures: Array, cell_rect: Rect2i) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(SectorReach.STATE_COUNT)
	for creature: Dictionary in creatures:
		var target: Rect2i = creature["rect"]
		var x_from := maxi(target.position.x - cell_rect.position.x - cell_rect.size.x, SectorReach.X_MIN)
		x_from += x_from & 1
		var x_to := mini(target.end.x - cell_rect.position.x, SectorReach.X_MAX)
		for y in range(maxi(target.position.y - cell_rect.position.y - cell_rect.size.y, SectorReach.Y_MIN),
				mini(target.end.y - cell_rect.position.y, SectorReach.Y_MAX) + 1):
			var row: int = creature["screen"] * SectorReach.PER_SCREEN + (y - SectorReach.Y_MIN) * SectorReach.X_COUNT
			for x in range(x_from, x_to + 1, 2):
				mask[row + ((x - SectorReach.X_MIN) >> 1)] = 1
	return mask


# --- plain data checks ---------------------------------------------------------------------------------------------

## Checks that need no search. Keys (each an Array of strings, empty when fine): `neighbours` (a side whose destination does not lead
## back), `pieces` (bad screen index / outside the window), `embedded` (a piece buried in solid tiles), `tiles` (a tile byte with
## both the solid and the current flag).
static func data_findings(sector: SectorData) -> Dictionary:
	var out := {"neighbours": [], "pieces": [], "embedded": [], "tiles": []}
	var sides := [sector.neighbors_left, sector.neighbors_right, sector.neighbors_up, sector.neighbors_down]
	var names := ["left", "right", "up", "down"]
	for side in 4:
		var opposite: PackedInt32Array = sides[side ^ 1]
		for screen in SectorReach.SCREENS:
			var target: int = sides[side][screen]
			if target < 0:
				continue
			if target >= SectorReach.SCREENS:
				out["neighbours"].append("screen %d %s -> %d does not exist" % [screen, names[side], target])
			elif opposite[target] != screen:
				out["neighbours"].append("screen %d %s -> %d, but %d %s -> %d" % [screen, names[side], target, target, names[side ^ 1], opposite[target]])
	var reach := SectorReach.from_sector(sector)
	for screen in sector.screens.size():
		for i in sector.screens[screen].tiles.size():
			var byte: int = sector.screens[screen].tiles[i]
			if (byte & TileCodec.SOLID_BIT) != 0 and (byte & TileCodec.CURRENT_BIT) != 0:
				out["tiles"].append("screen %d tile %d,%d = 0x%02x" % [screen, i % 38, i / 38, byte])
	for i in sector.pieces.size():
		var piece := sector.pieces[i]
		if piece.screen < 0 or piece.screen >= SectorReach.SCREENS:
			out["pieces"].append("piece %d: screen %d" % [i, piece.screen])
			continue
		var playfield := Rect2i(piece.pos - Vector2i(16, 32), Vector2i(24, 20))
		if playfield.position.x < 0 or playfield.position.y < 0 or playfield.end.x > TileGrid.PLAYFIELD_SIZE.x or playfield.end.y > TileGrid.PLAYFIELD_SIZE.y:
			out["pieces"].append("piece %d at %s sticks out of the playfield" % [i, piece.pos])
		var buried := _solid_pixels(reach, piece.screen, playfield)
		if buried > 0:
			out["embedded"].append("piece %d screen %d at %s: %d of 480 pixels in solid tiles%s" % [
					i, piece.screen, piece.pos, buried, "  (centre is solid)" if _solid_pixels(reach, piece.screen, Rect2i(playfield.position + Vector2i(11, 9), Vector2i(2, 2))) > 0 else ""])
	return out


## How many pixels of `rect` (playfield pixels) lie on solid tiles.
static func _solid_pixels(reach: SectorReach, screen: int, rect: Rect2i) -> int:
	var total := 0
	for row in range(maxi(rect.position.y / 16, 0), mini((rect.end.y - 1) / 16, SectorReach.ROWS - 1) + 1):
		for column in range(maxi(rect.position.x / 16, 0), mini((rect.end.x - 1) / 16, SectorReach.COLUMNS - 1) + 1):
			if reach.solid[screen][row * SectorReach.COLUMNS + column] != 0:
				total += rect.intersection(Rect2i(column * 16, row * 16, 16, 16)).get_area()
	return total


# --- currents (report only) ----------------------------------------------------------------------------------------

## Strength of the current under the sub's centre tile for every state: (SubX + 32) >> 4, (SubY - 3) >> 4 (DESIGN 3.3), in original
## units (2..16), 0 where there is no current. Returns a mask with 1 where the current is at least `threshold`.
static func strong_current_mask(reach: SectorReach, threshold: int) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(SectorReach.STATE_COUNT)
	for screen in reach.tiles.size():
		var t := reach.tiles[screen]
		for yi in SectorReach.Y_COUNT:
			var row := (yi + SectorReach.Y_MIN - 3) >> 4
			for xi in SectorReach.X_COUNT:
				var column := (xi * 2 + SectorReach.X_MIN + 32) >> 4
				var byte := t[row * SectorReach.COLUMNS + column]
				if (byte & TileCodec.CURRENT_BIT) != 0 and (byte & TileCodec.SOLID_BIT) == 0:
					if (((byte & 0x38) >> 2) + 2) >= threshold:
						mask[screen * SectorReach.PER_SCREEN + yi * SectorReach.X_COUNT + xi] = 1
	return mask


## Report-only: how many states have a strong current, and which pieces / the dock would be out of reach if every such
## state were impassable (a deliberately pessimistic model: momentum can carry the sub through a short current).
static func strong_current_effect(job: Dictionary, threshold: int = STRONG_CURRENT) -> Dictionary:
	var reach: SectorReach = job["reach"]
	var mask := strong_current_mask(reach, threshold)
	var out := {"strong_states": SectorReach.count(mask), "strong_tiles": 0, "lost_pieces": [], "lost_dock": false}
	for screen in reach.tiles.size():
		for byte in reach.tiles[screen]:
			if (byte & TileCodec.CURRENT_BIT) != 0 and (byte & TileCodec.SOLID_BIT) == 0 and (((byte & 0x38) >> 2) + 2) >= threshold:
				out["strong_tiles"] += 1
	if out["strong_tiles"] == 0:
		return out
	var open := reach.explore([SectorReach.LAUNCH], SectorReach.Mode.ORTHOGONAL)
	var blocked_search := reach.explore([SectorReach.LAUNCH], SectorReach.Mode.ORTHOGONAL, mask)
	for piece: Dictionary in job["pieces"]:
		var open_ok := SectorReach.first_pickup_original(open, piece["screen"], piece["pos"].x, piece["pos"].y).x >= 0
		var blocked_ok := SectorReach.first_pickup_original(blocked_search, piece["screen"], piece["pos"].x, piece["pos"].y).x >= 0
		if open_ok and not blocked_ok:
			out["lost_pieces"].append(piece["index"])
	if job["finale_screen"] < 0:
		var dock_open := SectorReach.first_state_in(open, DOCK_SCREEN, DOCK_MIN_X, SectorReach.X_MAX, DOCK_MIN_Y, DOCK_MAX_Y).x >= 0
		var dock_blocked := SectorReach.first_state_in(blocked_search, DOCK_SCREEN, DOCK_MIN_X, SectorReach.X_MAX, DOCK_MIN_Y, DOCK_MAX_Y).x >= 0
		out["lost_dock"] = dock_open and not dock_blocked
	return out


# --- text ------------------------------------------------------------------------------------------------------------

static func _level_text(level: int) -> String:
	return "NO" if level < 0 else MODE_NAMES[level]


## One line per sector for the console / the report.
static func report_line(result: Dictionary) -> String:
	var pieces: Array = result["pieces"]
	var orig_ok := 0
	var port_ok := 0
	var weak := 0
	for p: Dictionary in pieces:
		orig_ok += int(p["orig_level"] >= 0)
		port_ok += int(p["port_level"] >= 0)
		weak += int(p["orig_level"] > 0)
	var line := "sector %2d  pieces orig %d/%d (diag-or-fast %d)  port %d/%d" % [result["index"], orig_ok, pieces.size(), weak, port_ok, pieces.size()]
	if result.has("dock"):
		line += "  dock %s" % _level_text(result["dock"])
	if result.has("finale"):
		var f: Dictionary = result["finale"]
		line += "  treasure %s  closing %s" % [_level_text(f["touch_level"]), _level_text(f["closing_level"])]
		var g: Dictionary = result["finale_port_start"]
		line += "  (port start: treasure %s closing %s)" % [_level_text(g["touch_level"]), _level_text(g["closing_level"])]
	line += "  screens %d/12  states %d  %.1fs" % [result["screens_visited"].size(), result["states"], result["seconds"]]
	return line
