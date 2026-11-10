@tool
class_name SectorChecks
extends RefCounted
## The playability checks: is this sector one a player can start, finish and the game can store? They need NO original
## bytes, so they work on a sector made from scratch, such as a sector of a student's campaign.
##
## Teaches: turning "the fidelity tests, but for a sector nobody has a hash of" into a checklist. A sector made by a designer has no
## original to compare with, but it still has to obey what the original's FORMAT and RULES demand, and most of those demands are
## already methods of the data classes: `SectorData.header_problems()` (the values fit the header), `resource_problems()` (and the
## screens fit their records), `foe_problems()`, the screens' own `validate()`. This class adds what only a look at the whole sector
## sees (the creature script assembles and every creature's entry labels exist; the neighbour tables lead somewhere and back; the start
## position is a free spot; every piece, the canister, the end station and the math triggers can be reached by the sub) and asks
## the reachability search (`SectorReach`, `ReachSweep`: the real wall scan and the real screen changes) the last question.
## Each check returns `CheckFinding`s, data, so a tool, a test and an allow-list can all use them.
##
## THE CHECKS (the `check` id of a finding):
##   header, screen.record          the values fit the original's header / screen records (the problem methods named above)
##   sector.zone, sector.music      a zone and a song that exist
##   script.assemble                the creature script assembles ("line N: ...")
##   script.entry                   every creature's start / hit / ink label names a label of the script
##   script.dead_code, script.size, script.base   code nothing reaches; the script fits the 16-bit entry points and the original's size; it follows the records
##   creature.record, creature.count, creature.screen, creature.frame   the creature records fit; their number; on a real screen; a picture that exists
##   link.one_way, link.unreachable the neighbour tables lead back (or the one-way door is reported); every screen is on a chain of links from screen 0
##   start.frame, start.position, start.launch   the sub's start frame exists; the start is inside the screen and not inside a wall (also the launch spot)
##   piece.canister, piece.screen, piece.place, piece.buried   a canister first; pieces on real screens, inside the playfield, not buried in rock
##   trigger.problem                a math trigger's slot gives problems that exist
##   reach.screen, reach.piece, reach.dock, reach.trigger, reach.treasure, reach.closing, reach.respawn   the sub can get there
##
## THE ORIGINALS. All 32 pass, with the few findings that are simply how the original is listed in `ORIGINAL_ALLOWED`, each with its
## reason, like the DELIBERATE_* lists of the fidelity tests: the finding is still reported (marked allowed) but does not fail the sector.

## Findings of the original sectors that are how the original is: sector -> [{check, screen (optional), contains (a piece of "object message"), reason}].
const ORIGINAL_ALLOWED := {
	7: [
		{"check": "link.one_way", "screen": 4, "contains": "right link leads to screen 9", "reason": "the original's table: screen 4 right -> 9, but 9 left -> 5 (docs/data/sectors.json)"},
		{"check": "link.one_way", "screen": 9, "contains": "left link leads to screen 5", "reason": "the original's table: screen 9 left -> 5, but 5 right -> 6 (docs/data/sectors.json)"},
	],
	13: [
		{"check": "link.one_way", "screen": 3, "contains": "up link leads to screen 7", "reason": "the original's table: screen 3 up -> 7, but 7 down -> 8 (docs/data/sectors.json)"},
	],
	15: [
		{"check": "link.one_way", "screen": 7, "contains": "left link leads to screen 4", "reason": "the original's table: screen 7 left -> 4, but 4 right -> none (docs/data/sectors.json)"},
	],
	31: [
		{"check": "reach.piece", "screen": 0, "contains": "piece 0", "reason": "the data canister (16, 288) on screen 0 sits in the pocket of the start station, closed on every side except through the sub's own launch position; the finale never asks for pieces (test_sector_reachability.gd KNOWN_UNREACHABLE_PIECES)"},
	],
}

## The sub's frames: the cells `SubTuning.frame_rects` has.
const SUB_CELLS := 9
## How many of a piece's 480 pixels may lie in solid tiles before it counts as buried (the test of test_sector_reachability.gd).
const BURIED_PIXELS := 288
## The entry points of the creatures are 16-bit buffer offsets.
const BUFFER_END := 0x10000

const SOLID := 0x40
const SIDE_NAMES: Array[String] = ["left", "right", "up", "down"]


## What to check and what to let pass.
class Options extends RefCounted:
	## Run the reachability search (a few seconds per sector). Everything else is instant.
	var reach := true
	## Findings that are allowed, in the form of `ORIGINAL_ALLOWED`. A tool that checks a sector of its own can pass {}.
	var allowances: Dictionary = ORIGINAL_ALLOWED
	## For the original's limits (most creatures, longest script).
	var source: OriginalBytes
	## The rule values the checks and the search run on (the sub's rectangles, the screen of the respawn point): the chain's, resolved when the options
	## are made, once per use of the tool.
	var tuning: Tuning = Tuning.resolve()


## The findings for `sector`, worst first. Does not change the sector. The sector's `index` says which one it is (the finales 30 and 31
## are checked as finales, an allow-list entry applies to the sector of its number).
static func check(sector: SectorData, options: Options = null) -> Array[CheckFinding]:
	var pending := begin(sector, options)
	pending.search()
	return pending.finish()


## A check in two halves, so that the slow one can run on another thread: `begin` does everything that needs the sector (all the
## checks but the search, and the preparation of the search) on the calling thread; `search()` is the reachability search, which
## touches nothing but its own copy of the data and may run on a `WorkerThreadPool` thread (see `SectorCheckTask`); `finish()` puts
## the findings together again on the calling thread.
class Pending extends RefCounted:
	var sector: SectorData
	var options: Options
	var found: Array[CheckFinding] = []
	## The prepared search (`ReachSweep.prepare_for`), or empty when none is asked for or the sector cannot be searched.
	var job: Dictionary = {}
	var work: Dictionary = {}

	## The reachability search. Thread-safe; does nothing when there is no job.
	func search() -> void:
		if not job.is_empty():
			work = SectorChecks.reach_work(job)

	## The findings, marked and sorted (`SectorChecks.finish`). Call after `search()`.
	func finish() -> Array[CheckFinding]:
		if not work.is_empty():
			found.append_array(SectorChecks.reach_findings(sector, work))
		return SectorChecks.finish(sector, found, options)


## The first half of `check`: see `Pending`.
static func begin(sector: SectorData, options: Options = null) -> Pending:
	var pending := Pending.new()
	pending.sector = sector
	pending.options = options if options != null else Options.new()
	pending.found = check_data(sector, pending.options)
	if pending.options.reach:
		var problem := searchable_problem(sector)
		if problem.is_empty():
			pending.job = _job(sector, pending.options)
		else:
			pending.found.append(CheckFinding.make(CheckFinding.Severity.INFO, "reach.skipped", sector.index, -1, "", "the reachability search was skipped: %s" % problem))
	return pending


## The same for several sectors, with the reachability searches running side by side on the worker threads. Returns one array per sector.
static func check_many(sectors: Array[SectorData], options: Options = null) -> Array:
	if options == null:
		options = Options.new()
	var results: Array = []
	var jobs: Array = []
	var job_of: Array[int] = []
	for k in sectors.size():
		results.append(check_data(sectors[k], options))
		if options.reach and searchable_problem(sectors[k]).is_empty():
			job_of.append(jobs.size())
			jobs.append(_job(sectors[k], options))
		else:
			job_of.append(-1)
	var work := ReachSweep.parallel(jobs, reach_work)
	for k in sectors.size():
		if job_of[k] >= 0:
			results[k].append_array(reach_findings(sectors[k], work[job_of[k]]))
		results[k] = finish(sectors[k], results[k], options)
	return results


## Checks the original sector `index` as the project has it now.
static func check_original(index: int, options: Options = null) -> Array[CheckFinding]:
	return check(Catalog.sector(index), options)


## Marks the allowed findings and sorts the list: errors first, then by screen.
static func finish(sector: SectorData, found: Array[CheckFinding], options: Options) -> Array[CheckFinding]:
	for finding in found:
		for entry: Dictionary in options.allowances.get(sector.index, []):
			if entry["check"] == finding.check and entry.get("screen", finding.screen) == finding.screen and (finding.object + " " + finding.message).contains(str(entry["contains"])):
				finding.allowed = str(entry["reason"])
	found.sort_custom(func(a: CheckFinding, b: CheckFinding) -> bool:
		if a.severity != b.severity:
			return a.severity > b.severity
		return a.screen < b.screen)
	return found


## The findings that make a sector fail: errors and warnings that are not allowed.
static func failures(found: Array[CheckFinding]) -> Array[CheckFinding]:
	var out: Array[CheckFinding] = []
	for finding in found:
		if finding.fails():
			out.append(finding)
	return out


static func passes(found: Array[CheckFinding]) -> bool:
	return failures(found).is_empty()


## "1 error, 2 warnings, 1 allowed, 3 notes".
static func summary(found: Array[CheckFinding]) -> String:
	var counts := [0, 0, 0]
	var allowed := 0
	for finding in found:
		if not finding.allowed.is_empty():
			allowed += 1
		else:
			counts[finding.severity] += 1
	return "%d error%s, %d warning%s, %d allowed, %d note%s" % [counts[2], "" if counts[2] == 1 else "s", counts[1], "" if counts[1] == 1 else "s", allowed, counts[0], "" if counts[0] == 1 else "s"]


## The findings as text, one per line.
static func text(found: Array[CheckFinding]) -> String:
	var lines: Array[String] = []
	for finding in found:
		lines.append(finding.text())
	return "\n".join(lines)


## The two finales (sectors 30 and 31) are won by taking the treasure and have their own shape: few pieces, screens nobody visits.
static func _is_finale(sector: SectorData) -> bool:
	return sector.finale_screen >= 0


static func _add(found: Array[CheckFinding], severity: CheckFinding.Severity, check_id: String, sector: SectorData, screen: int, object: String, message: String) -> void:
	found.append(CheckFinding.make(severity, check_id, sector.index, screen, object, message))


# =====================================================================================================================
# The checks that need no search
# =====================================================================================================================

## Every check but the reachability search. Instant.
static func check_data(sector: SectorData, options: Options = null) -> Array[CheckFinding]:
	if options == null:
		options = Options.new()
	if options.source == null:
		options.source = OriginalBytes.new()
	var found: Array[CheckFinding] = []
	_fields(sector, found)
	_header(sector, found)
	_screens(sector, found)
	_links(sector, found)
	_pieces(sector, found)
	_start(sector, found, options.tuning.midpoint_screen, options.tuning.sub.wall_box)
	_script(sector, found, options)
	_creatures(sector, found, options)
	_triggers(sector, found)
	return found


static func _fields(sector: SectorData, found: Array[CheckFinding]) -> void:
	if sector.zone < 0 or sector.zone >= Catalog.ZONE_COUNT:
		_add(found, CheckFinding.Severity.ERROR, "sector.zone", sector, -1, "zone", "zone %d does not exist: there are %d zones (0 to %d)" % [sector.zone, Catalog.ZONE_COUNT, Catalog.ZONE_COUNT - 1])
	if sector.finale_screen < -1 or sector.finale_screen >= SectorData.SCREEN_COUNT:
		_add(found, CheckFinding.Severity.ERROR, "sector.zone", sector, -1, "finale_screen", "finale_screen %d is not a screen of the sector (0 to %d), or -1 for none" % [sector.finale_screen, SectorData.SCREEN_COUNT - 1])
	if sector.game < 0 or sector.game > 1:
		_add(found, CheckFinding.Severity.ERROR, "sector.zone", sector, -1, "game", "game %d is not 0 (Voyager) or 1 (Expert)" % sector.game)
	# `music_name` is the stem of the song's MIDI file ("esect4": the General MIDI "E" file; the AdLib set has the same song as "bsect4").
	# The game plays the song this names (`Campaign.song_for`); the original's own data gives sector `s` the song `s % 6 + 1`.
	if sector.music_name.is_empty():
		_add(found, CheckFinding.Severity.INFO, "sector.music", sector, -1, "music", "the sector names no background music")
	else:
		var known := false
		for midi: String in Catalog.music_catalog().midi_names:
			known = known or midi.get_basename().to_lower().substr(1) == sector.music_name.to_lower().substr(1)
		if not known:
			_add(found, CheckFinding.Severity.WARNING, "sector.music", sector, -1, "music", "'%s' is not the name of one of the original's MIDI songs" % sector.music_name)


static func _header(sector: SectorData, found: Array[CheckFinding]) -> void:
	var piece_number := RegEx.create_from_string("^(?:stale )?piece (\\d+)")
	var screen_number := RegEx.create_from_string("of screen (\\d+)")
	for message in sector.header_problems():
		var object := ""
		var screen := -1
		var hit := piece_number.search(message)
		if hit != null:
			object = hit.get_string()
		elif message.begins_with("start"):
			object = "start"
		var on_screen := screen_number.search(message)
		if on_screen != null:
			screen = on_screen.get_string(1).to_int()
		_add(found, CheckFinding.Severity.ERROR, "header", sector, screen, object, message)


static func _screens(sector: SectorData, found: Array[CheckFinding]) -> void:
	if sector.screens.size() != SectorData.SCREEN_COUNT:
		_add(found, CheckFinding.Severity.ERROR, "screen.record", sector, -1, "screens", "%d screens, but a sector has %d" % [sector.screens.size(), SectorData.SCREEN_COUNT])
	for m in sector.screens.size():
		if sector.screens[m] == null:
			_add(found, CheckFinding.Severity.ERROR, "screen.record", sector, m, "", "the screen is empty")
			continue
		for message in sector.screens[m].validate():
			_add(found, CheckFinding.Severity.ERROR, "screen.record", sector, m, "", message)


static func _sides(sector: SectorData) -> Array:
	return [sector.neighbors_left, sector.neighbors_right, sector.neighbors_up, sector.neighbors_down]


## Neighbour tables: where each side leads, whether it leads back, and whether every screen is on some chain of links from screen 0.
static func _links(sector: SectorData, found: Array[CheckFinding]) -> void:
	var sides := _sides(sector)
	for side in 4:
		if (sides[side] as PackedInt32Array).size() != SectorData.SCREEN_COUNT:
			return                                    # `header` says so; the rest needs 12 entries
	var names := SIDE_NAMES
	for side in 4:
		var table: PackedInt32Array = sides[side]
		var opposite: PackedInt32Array = sides[side ^ 1]
		for screen in SectorData.SCREEN_COUNT:
			var target := table[screen]
			if target < 0 or target >= SectorData.SCREEN_COUNT:
				continue
			if opposite[target] != screen:
				var back: String = "screen %d" % opposite[target] if opposite[target] >= 0 else "nowhere"
				_add(found, CheckFinding.Severity.WARNING, "link.one_way", sector, screen, "%s link" % names[side],
						"leads to screen %d, but the %s link of screen %d leads to %s, so there is no way back (a one-way door)" % [target, names[side ^ 1], target, back])
	var unlinked_severity := CheckFinding.Severity.INFO if _is_finale(sector) else CheckFinding.Severity.ERROR
	var seen := {0: true}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var at: int = queue.pop_front()
		for side in 4:
			var target: int = (sides[side] as PackedInt32Array)[at]
			if target >= 0 and target < SectorData.SCREEN_COUNT and not seen.has(target):
				seen[target] = true
				queue.append(target)
	for m in SectorData.SCREEN_COUNT:
		if not seen.has(m):
			_add(found, unlinked_severity, "link.unreachable", sector, m, "", "no chain of neighbour links leads to this screen from screen 0, where the sub starts%s" % (" (a finale does not use all its screens)" if _is_finale(sector) else ""))


## How many pixels of `rect` (playfield pixels) lie on solid tiles of screen `m`.
static func _solid_pixels(sector: SectorData, m: int, rect: Rect2i) -> int:
	var tiles: PackedByteArray = sector.screens[m].tiles
	var total := 0
	for row in range(maxi(rect.position.y / 16, 0), mini((rect.end.y - 1) / 16, ScreenData.TILE_ROWS - 1) + 1):
		for column in range(maxi(rect.position.x / 16, 0), mini((rect.end.x - 1) / 16, ScreenData.TILE_COLUMNS - 1) + 1):
			if tiles[row * ScreenData.TILE_COLUMNS + column] & SOLID != 0:
				total += rect.intersection(Rect2i(column * 16, row * 16, 16, 16)).get_area()
	return total


static func _has_tiles(sector: SectorData, m: int) -> bool:
	return m >= 0 and m < sector.screens.size() and sector.screens[m] != null and sector.screens[m].tiles.size() == ScreenData.TILE_BYTES


## "piece 3", and "piece 0 (data canister)": the first piece of every sector is the canister.
static func _piece_name(index: int) -> String:
	return "piece 0 (data canister)" if index == 0 else "piece %d" % index


static func _pieces(sector: SectorData, found: Array[CheckFinding]) -> void:
	if sector.pieces.is_empty():
		# the Voyager finale (sector 30) has none, the Expert finale (31) only the canister; the finale is won by taking the treasure
		_add(found, CheckFinding.Severity.INFO if _is_finale(sector) else CheckFinding.Severity.ERROR, "piece.canister", sector, -1, "pieces", "the sector has no pieces%s" % ("" if _is_finale(sector) else "; piece 0 must be the data canister"))
	for i in sector.pieces.size():
		var piece := sector.pieces[i]
		if piece == null:
			continue
		var object := _piece_name(i)
		if i == 0 and not piece.is_canister:
			_add(found, CheckFinding.Severity.ERROR, "piece.canister", sector, piece.screen, object, "piece 0 is the data canister but is not marked is_canister")
		elif i > 0 and piece.is_canister:
			_add(found, CheckFinding.Severity.WARNING, "piece.canister", sector, piece.screen, object, "only piece 0 is the data canister, but this one is marked is_canister")
		if piece.screen < 0 or piece.screen >= SectorData.SCREEN_COUNT:
			_add(found, CheckFinding.Severity.ERROR, "piece.screen", sector, -1, object, "on screen %d, but a sector has screens 0 to %d" % [piece.screen, SectorData.SCREEN_COUNT - 1])
			continue
		var playfield := Rect2i(piece.pos - Vector2i(16, 32), Vector2i(24, 20))
		if playfield.position.x < 0 or playfield.position.y < 0 or playfield.end.x > TileGrid.PLAYFIELD_SIZE.x or playfield.end.y > TileGrid.PLAYFIELD_SIZE.y:
			_add(found, CheckFinding.Severity.ERROR, "piece.place", sector, piece.screen, object, "at %s sticks out of the playfield" % piece.pos)
		if _has_tiles(sector, piece.screen):
			var buried := _solid_pixels(sector, piece.screen, playfield)
			var centre := _solid_pixels(sector, piece.screen, Rect2i(playfield.position + Vector2i(11, 9), Vector2i(2, 2))) > 0
			if centre or buried > BURIED_PIXELS:
				_add(found, CheckFinding.Severity.ERROR, "piece.buried", sector, piece.screen, object, "at %s: %d of its 480 pixels are in solid tiles%s" % [piece.pos, buried, " and its centre is" if centre else ""])


## Solid tiles under the sub's wall box (`box`, the run's `SubTuning.wall_box`) at (`x`, `y`) on screen `m`: the box `SubModel.wall_gap` scans.
static func _wall_overlap(sector: SectorData, m: int, x: int, y: int, box: Rect2i) -> int:
	var tiles: PackedByteArray = sector.screens[m].tiles
	var scan := SubModel.wall_scan_box(Vector2i(x, y), box)
	var overlapping := 0
	for row in range(maxi(scan.position.y / 16, 0), mini((scan.end.y - 1) / 16, ScreenData.TILE_ROWS - 1) + 1):
		for column in range(maxi(scan.position.x / 16, 0), mini((scan.end.x - 1) / 16, ScreenData.TILE_COLUMNS - 1) + 1):
			if tiles[row * ScreenData.TILE_COLUMNS + column] & SOLID != 0:
				overlapping += 1
	return overlapping


## The start data: the sub's frame, the spot it appears at after a lost tank (the header's start position, on the screen of the
## midpoint; a finale starts on screen 0) and the spot of the launch from the station, each inside the screen and clear of rock.
static func _start(sector: SectorData, found: Array[CheckFinding], midpoint: int, box: Rect2i) -> void:
	if sector.start_frame < 0 or sector.start_frame >= SUB_CELLS:
		_add(found, CheckFinding.Severity.ERROR, "start.frame", sector, -1, "start", "start frame %d is not one of the sub's %d frames (0 to %d)" % [sector.start_frame, SUB_CELLS, SUB_CELLS - 1])
	var at := sector.start_pos
	if at.x < SectorReach.X_MIN or at.x > SectorReach.X_MAX or at.y < SectorReach.Y_MIN or at.y > SectorReach.Y_MAX:
		_add(found, CheckFinding.Severity.ERROR, "start.position", sector, -1, "start", "the start position %s is outside the screen: the sub's x is %d to %d and y %d to %d" % [at, SectorReach.X_MIN, SectorReach.X_MAX, SectorReach.Y_MIN, SectorReach.Y_MAX])
		return
	var finale := sector.finale_screen >= 0
	var screen := 0 if finale else midpoint
	if _has_tiles(sector, screen):
		var overlap := _wall_overlap(sector, screen, at.x & ~1, at.y, box)
		if overlap > 0:
			_add(found, CheckFinding.Severity.ERROR, "start.position", sector, screen, "start", "the start position %s overlaps %d solid tiles of screen %d" % [at, overlap, screen])
	if _has_tiles(sector, 0):
		var launch := _wall_overlap(sector, 0, SectorReach.LAUNCH.y, SectorReach.LAUNCH.z, box)
		if launch > 0:
			_add(found, CheckFinding.Severity.ERROR, "start.launch", sector, 0, "launch", "the launch spot (%d, %d) in front of the start station overlaps %d solid tiles" % [SectorReach.LAUNCH.y, SectorReach.LAUNCH.z, launch])


# --- the creature script and records ---------------------------------------------------------------------------------

static func _script(sector: SectorData, found: Array[CheckFinding], options: Options) -> void:
	var source_text := sector.foe_script.source if sector.foe_script != null else ""
	var result := FoeAsm.assemble(source_text, sector.foe_script_base, FoeNames.for_sector(sector))
	var line_number := RegEx.create_from_string("^line (\\d+)")
	for error in result.errors:
		var hit := line_number.search(error)
		_add(found, CheckFinding.Severity.ERROR, "script.assemble", sector, -1, "script line %s" % hit.get_string(1) if hit != null else "script", error)
	if not result.ok():
		return
	for k in sector.foes.size():
		var foe := sector.foes[k]
		if foe == null:
			continue
		for pair: Array in [["start_label", foe.start_label], ["hit_label", foe.hit_label], ["ink_label", foe.ink_label]]:
			var label: String = pair[1]
			if label.is_empty():
				_add(found, CheckFinding.Severity.ERROR, "script.entry", sector, foe.screen, "creature %d %s" % [k, pair[0]], "is empty; name a label of the script")
			elif not result.labels.has(label):
				_add(found, CheckFinding.Severity.ERROR, "script.entry", sector, foe.screen, "creature %d %s" % [k, pair[0]], "names '%s', but the script has no such label" % label)
	for warning in FoeAsm.dead_code_warnings(source_text, result, FoeAsm.sector_entry_labels(sector)):
		_add(found, CheckFinding.Severity.WARNING, "script.dead_code", sector, -1, "script", warning)
	var end := sector.foe_script_base + result.bytes.size()
	if end > BUFFER_END:
		_add(found, CheckFinding.Severity.ERROR, "script.size", sector, -1, "script", "ends at buffer offset %d, but the creatures' entry points are 16-bit numbers (at most %d)" % [end, BUFFER_END - 1])
	var longest := options.source.max_script_size()
	if longest > 0 and result.bytes.size() > longest:
		_add(found, CheckFinding.Severity.WARNING, "script.size", sector, -1, "script", "%d bytes is longer than any original script (%d bytes)" % [result.bytes.size(), longest])
	var expected_base := 1 + FoeData.RECORD_SIZE * sector.foes.size()
	if sector.foe_script_base != expected_base:
		_add(found, CheckFinding.Severity.WARNING, "script.base", sector, -1, "script", "starts at buffer offset %d, but in the original's layout the script follows the %d creature records, at %d" % [sector.foe_script_base, sector.foes.size(), expected_base])


static func _creatures(sector: SectorData, found: Array[CheckFinding], options: Options) -> void:
	if sector.foes.size() > 255:
		_add(found, CheckFinding.Severity.ERROR, "creature.count", sector, -1, "creatures", "%d creatures, but the original keeps the count in one byte (at most 255)" % sector.foes.size())
	var most := options.source.max_creatures()
	if most > 0 and sector.foes.size() > most and sector.foes.size() <= 255:
		_add(found, CheckFinding.Severity.WARNING, "creature.count", sector, -1, "creatures", "%d creatures; the original's sectors have at most %d" % [sector.foes.size(), most])
	var meta: SpriteMetaTable = null
	if sector.zone >= 0 and sector.zone < Catalog.ZONE_COUNT:
		meta = SpriteMeta.for_zone(sector.zone)
	for k in sector.foes.size():
		var foe := sector.foes[k]
		if foe == null:
			_add(found, CheckFinding.Severity.ERROR, "creature.record", sector, -1, "creature %d" % k, "the creature is empty")
			continue
		for message in foe.problems():
			_add(found, CheckFinding.Severity.ERROR, "creature.record", sector, foe.screen, "creature %d" % k, message)
		if foe.screen < 0 or foe.screen >= SectorData.SCREEN_COUNT:
			_add(found, CheckFinding.Severity.ERROR, "creature.screen", sector, -1, "creature %d" % k, "starts on screen %d, but a sector has screens 0 to %d" % [foe.screen, SectorData.SCREEN_COUNT - 1])
		if meta != null:
			for pair: Array in [["frame", foe.frame], ["frame_min", foe.frame_min], ["frame_max", foe.frame_max]]:
				if pair[1] >= meta.count():
					_add(found, CheckFinding.Severity.ERROR, "creature.frame", sector, foe.screen, "creature %d" % k, "%s %d is not a picture of the zone's creature set (it has %d: 0 to %d)" % [pair[0], pair[1], meta.count(), meta.count() - 1])


## Each math trigger's problem slot must give problem types that exist at every educational level.
static func _triggers(sector: SectorData, found: Array[CheckFinding]) -> void:
	var table := Catalog.trigger_table()
	for m in sector.screens.size():
		if sector.screens[m] == null:
			continue
		for t in sector.screens[m].triggers.size():
			var trigger := sector.screens[m].triggers[t]
			if trigger == null or trigger.slot < 0 or trigger.slot >= TriggerTable.SLOTS:
				continue                                  # `screen.record` says so
			for level in TriggerTable.LEVELS:
				for pick in TriggerTable.PICKS:
					var type_id := table.type_for(trigger.slot, level, pick)
					if type_id >= Catalog.PROBLEM_TYPE_COUNT:
						_add(found, CheckFinding.Severity.ERROR, "trigger.problem", sector, m, "trigger %d" % t, "slot %d gives problem type %d at level %d (pick %d), but there are only %d types" % [trigger.slot, type_id, level, pick, Catalog.PROBLEM_TYPE_COUNT])


# =====================================================================================================================
# The reachability search
# =====================================================================================================================

## Why the reachability search cannot run on `sector` (it needs 12 screens of 684 tiles, neighbour tables of 12 entries between -1
## and 11, pieces on real screens, a real zone), or "" when it can.
static func searchable_problem(sector: SectorData) -> String:
	if sector.screens.size() != SectorData.SCREEN_COUNT:
		return "the sector has %d screens, not %d" % [sector.screens.size(), SectorData.SCREEN_COUNT]
	for m in SectorData.SCREEN_COUNT:
		if not _has_tiles(sector, m):
			return "screen %d has no complete tile map" % m
	for side in 4:
		var table: PackedInt32Array = _sides(sector)[side]
		if table.size() != SectorData.SCREEN_COUNT:
			return "a neighbour table does not have %d entries" % SectorData.SCREEN_COUNT
		for target in table:
			if target < -1 or target >= SectorData.SCREEN_COUNT:
				return "a neighbour table leads to screen %d" % target
	for piece in sector.pieces:
		if piece == null or piece.screen < 0 or piece.screen >= SectorData.SCREEN_COUNT:
			return "a piece is not on a screen of the sector"
	if sector.zone < 0 or sector.zone >= Catalog.ZONE_COUNT:
		return "the zone does not exist"
	if sector.finale_screen >= 0:
		if sector.foes.is_empty() or sector.foes[0] == null:
			return "a finale needs creature 0, the treasure"
		var result := FoeAsm.assemble(sector.foe_script.source if sector.foe_script != null else "", sector.foe_script_base, FoeNames.for_sector(sector))
		if not result.ok():
			return "the creature script does not assemble"
	return ""


static func _job(sector: SectorData, options: Options) -> Dictionary:
	return ReachSweep.prepare_for(sector, options.tuning)


## The searches for one prepared job (`ReachSweep.prepare_for`): the sweep's own analysis, and the math triggers the sub cannot touch.
## Thread-safe: it touches nothing but the job.
static func reach_work(job: Dictionary) -> Dictionary:
	var sector: SectorData = job["sector"]
	var reach: SectorReach = job["reach"]
	var visited := reach.explore([SectorReach.LAUNCH])
	var unreachable: Array = []
	for m in sector.screens.size():
		for t in sector.screens[m].triggers.size():
			if not _trigger_reachable(visited, m, sector.screens[m].triggers[t]):
				unreachable.append([m, t])
	return {"analysis": ReachSweep.analyze(job), "triggers": unreachable}


## Can the sub, somewhere it can get to, be at a spot where `DetectMathTrigger` fires this trigger (in some sprite cell)?
static func _trigger_reachable(visited: PackedByteArray, screen: int, trigger: MathTriggerData) -> bool:
	for cell in SUB_CELLS:
		var mode := TriggerModel.TABLE[cell * 16 + (trigger.flags & 15)]
		var x_from := SectorReach.X_MIN
		var x_to := SectorReach.X_MAX
		var y_from := SectorReach.Y_MIN
		var y_to := SectorReach.Y_MAX
		if mode & 2 != 0:
			x_from = trigger.pos.x - TriggerModel.SUB_BOX_LAST.x
			x_to = trigger.pos.x
		if mode & 1 != 0:
			y_from = trigger.pos.y - TriggerModel.SUB_BOX_LAST.y
			y_to = trigger.pos.y
		if SectorReach.first_state_in(visited, screen, x_from, x_to, y_from, y_to).x >= 0:
			return true
	return false


## The findings from `reach_work`'s result.
static func reach_findings(sector: SectorData, work: Dictionary) -> Array[CheckFinding]:
	var found: Array[CheckFinding] = []
	var r: Dictionary = work["analysis"]
	var midpoint: int = r["midpoint_screen"]
	var finale := sector.finale_screen >= 0
	if not finale:
		for m in SectorData.SCREEN_COUNT:
			if not (m in r["screens_visited"]):
				_add(found, CheckFinding.Severity.ERROR, "reach.screen", sector, m, "", "the sub cannot enter this screen: the links lead here, but the walls or the neighbour tables stop it")
	for p: Dictionary in r["pieces"]:
		var object := _piece_name(p["index"])
		if p["orig_level"] < 0:
			_add(found, CheckFinding.Severity.ERROR, "reach.piece", sector, p["screen"], object, "no position the sub can reach touches it (window %s)" % p["pos"])
		elif p["orig_level"] > 0:
			_add(found, CheckFinding.Severity.WARNING, "reach.piece", sector, p["screen"], object, "can only be reached with %s moves (corner slips), not by plain steps" % ReachSweep.MODE_NAMES[p["orig_level"]])
	if r.has("dock"):
		if r["dock"] < 0:
			_add(found, CheckFinding.Severity.ERROR, "reach.dock", sector, SimWorld.DOCK_SCREEN, "end station", "the sub cannot get into the end station")
		elif r["dock"] > 0:
			_add(found, CheckFinding.Severity.WARNING, "reach.dock", sector, SimWorld.DOCK_SCREEN, "end station", "can only be entered with %s moves (corner slips)" % ReachSweep.MODE_NAMES[r["dock"]])
	if r.has("finale"):
		var f: Dictionary = r["finale"]
		if f["touch_level"] < 0:
			_add(found, CheckFinding.Severity.ERROR, "reach.treasure", sector, -1, "creature 0", "no position the sub can reach touches the treasure")
		elif f["closing_level"] < 0:
			_add(found, CheckFinding.Severity.ERROR, "reach.closing", sector, f["trigger_screen"], "closing screen", "after taking the treasure the sub cannot reach screen %d" % f["trigger_screen"])
	if r.has("respawn_missing"):
		for index in r["respawn_missing"]:
			_add(found, CheckFinding.Severity.ERROR, "reach.respawn", sector, midpoint, _piece_name(index), "cannot be reached from the respawn point on screen %d, where the sub reappears after a lost tank" % midpoint)
		if r["respawn_dock"] < 0:
			_add(found, CheckFinding.Severity.ERROR, "reach.respawn", sector, midpoint, "end station", "cannot be reached from the respawn point on screen %d" % midpoint)
	for pair: Array in work["triggers"]:
		_add(found, CheckFinding.Severity.WARNING, "reach.trigger", sector, pair[0], "trigger %d" % pair[1], "no position the sub can reach fires this math trigger")
	return found
