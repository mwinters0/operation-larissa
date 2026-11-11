class_name TestSectorReachabilityLegacy
extends GdUnitTestSuite
## The original's sectors, 32 of them, searched (the engine half, on dev's sectors, is `tests/engine/test_sector_reachability.gd`).
##
## Teaches: an automatic "can the player finish every level?" test. `SectorReach` searches everywhere the sub can go in a sector
## (the real wall scan, the real screen changes, DESIGN 3.3) and `ReachSweep` asks the questions below of all 32 sectors, one
## worker thread per sector. See the headers of those two classes for the model and why it is sound (and
## `test_reachability_model.gd`, which checks the model against the real `Sub` and `SectorWorld`).
##
## What a failure means is spelled out in each test. Findings about the ORIGINAL game that are not port bugs are listed in the
## constants below, so that the suite stays green until something new shows up.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"

## Pieces that the original cannot collect either: sector 31 (Expert finale) keeps one piece (the data canister, window (16, 288) on screen 0)
## inside the pocket of the start station (tile columns 0-3, rows 10-16), which is closed on every side except through the sub's own launch
## position; the sub is only ever outside it. The finale never asks for pieces, so the game is not affected.
const KNOWN_UNREACHABLE_PIECES := {31: [0]}

## Neighbour tables of the original that do not lead back (checked against extracted/tables/sectors.json, i.e. they are in the game data).
const KNOWN_ONE_WAY_NEIGHBOURS := {
	7: ["screen 9 left -> 5, but 5 right -> 6", "screen 4 right -> 9, but 9 left -> 5"],
	13: ["screen 3 up -> 7, but 7 down -> 8"],
	15: ["screen 7 left -> 4, but 4 right -> -1"],
}

static var _results: Array = []
static var _jobs: Array = []
static var _seconds: float = 0.0

var _world: SectorWorld


func before() -> void:
	var started := Time.get_ticks_msec()
	_jobs.clear()
	for i in Catalog.ORIGINAL_SECTOR_COUNT:
		_jobs.append(ReachSweep.prepare(i))
	_results = ReachSweep.run_all(_jobs)
	_seconds = (Time.get_ticks_msec() - started) / 1000.0
	prints("reachability sweep of %d sectors: %.1f s" % [_results.size(), _seconds])
	for r: Dictionary in _results:
		prints(ReachSweep.report_line(r))


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()
	SectorWorld.skip_animations = false


# --- pieces, canister --------------------------------------------------------------------------------------------

func test_every_piece_and_canister_can_be_touched() -> void:
	var problems: Array[String] = []
	for r: Dictionary in _results:
		var known: Array = KNOWN_UNREACHABLE_PIECES.get(r["index"], [])
		for p: Dictionary in r["pieces"]:
			var reached: bool = p["orig_level"] >= 0
			if not reached and not (p["index"] in known):
				problems.append("sector %d piece %d (screen %d, window %s): no position the sub can reach touches it" % [r["index"], p["index"], p["screen"], p["pos"]])
			if reached and p["index"] in known:
				problems.append("sector %d piece %d is reachable now: remove it from KNOWN_UNREACHABLE_PIECES" % [r["index"], p["index"]])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_pieces_are_reached_by_plain_moves_not_by_corner_slips() -> void:
	# level 0 = only the sound orthogonal steps; a piece that needs diagonal / fast moves would deserve a manual look
	var problems: Array[String] = []
	for r: Dictionary in _results:
		for p: Dictionary in r["pieces"]:
			if p["orig_level"] > 0:
				problems.append("sector %d piece %d needs search level %s" % [r["index"], p["index"], ReachSweep.MODE_NAMES[p["orig_level"]]])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_the_ports_pickup_rule_can_also_be_satisfied_everywhere() -> void:
	# The port takes pieces with the original's rule (the whole picture box, see the test below), so the two searches must agree.
	var problems: Array[String] = []
	for r: Dictionary in _results:
		var known: Array = KNOWN_UNREACHABLE_PIECES.get(r["index"], [])
		for p: Dictionary in r["pieces"]:
			if p["orig_level"] >= 0 and p["port_level"] != p["orig_level"]:
				problems.append("sector %d piece %d: reachable in the original, but not with the port's contact rectangles (level %d)" % [r["index"], p["index"], p["port_level"]])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_piece_positions_and_screens_are_valid() -> void:
	var problems: Array[String] = []
	for i in Catalog.ORIGINAL_SECTOR_COUNT:
		var findings := ReachSweep.data_findings(Catalog.sector(i))
		for line: String in findings["pieces"]:
			problems.append("sector %d: %s" % [i, line])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_no_piece_is_buried_in_the_rock() -> void:
	# Pieces rest on the sea floor and overlap it by a few rows (96 of 480 pixels is normal); 'buried' means the centre is solid
	# or more than 60 percent of the picture is.
	var problems: Array[String] = []
	var notes: Array[String] = []
	for i in Catalog.ORIGINAL_SECTOR_COUNT:
		for line: String in ReachSweep.data_findings(Catalog.sector(i))["embedded"]:
			var pixels := int(line.split(": ")[1].split(" of")[0])
			if "centre is solid" in line or pixels > 288:
				problems.append("sector %d %s" % [i, line])
			elif pixels > 192:
				notes.append("sector %d %s" % [i, line])
	if not notes.is_empty():
		prints("half-buried pieces (fine, they are reached):\n" + "\n".join(notes))
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


# --- the way out --------------------------------------------------------------------------------------------------

func test_the_end_station_can_be_entered() -> void:
	var problems: Array[String] = []
	for r: Dictionary in _results:
		if Catalog.sector(r["index"]).finale_screen < 0 and r["dock"] < 0:
			problems.append("sector %d: no reachable position on screen 11 with SubX >= 344 and 170 <= SubY <= 234" % r["index"])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_every_screen_of_a_normal_sector_is_visited() -> void:
	var problems: Array[String] = []
	for r: Dictionary in _results:
		if Catalog.sector(r["index"]).finale_screen < 0 and r["screens_visited"].size() != 12:
			problems.append("sector %d: screens visited %s" % [r["index"], r["screens_visited"]])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_the_launch_and_the_respawn_position_are_not_inside_rock() -> void:
	var problems: Array[String] = []
	for r: Dictionary in _results:
		if r["launch_embedded"] > 0:
			problems.append("sector %d: the launch position (SubX 96, SubY 202) overlaps %d solid tiles" % [r["index"], r["launch_embedded"]])
		if r.get("respawn_embedded", 0) > 0:
			problems.append("sector %d: the respawn position (screen 6, header start) overlaps %d solid tiles" % [r["index"], r["respawn_embedded"]])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_after_a_respawn_past_the_midpoint_the_rest_of_the_sector_is_reachable() -> void:
	var problems: Array[String] = []
	for r: Dictionary in _results:
		if Catalog.sector(r["index"]).finale_screen >= 0:
			continue
		if not r["respawn_missing"].is_empty():
			problems.append("sector %d: from the respawn point on screen 6 pieces %s cannot be reached" % [r["index"], r["respawn_missing"]])
		if r["respawn_dock"] < 0:
			problems.append("sector %d: from the respawn point on screen 6 the end station cannot be reached" % r["index"])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


# --- the finale ---------------------------------------------------------------------------------------------------

func test_the_finale_treasure_can_be_taken_and_the_closing_screen_reached() -> void:
	var problems: Array[String] = []
	for index in [30, 31]:
		var r: Dictionary = _results[index]
		for key in ["finale", "finale_port_start"]:
			var f: Dictionary = r[key]
			var which := "launch" if key == "finale" else "port start"
			if f["touch_level"] < 0:
				problems.append("sector %d (%s): no reachable position touches the treasure (creature 0)" % [index, which])
			elif f["closing_level"] < 0:
				problems.append("sector %d (%s): after taking the treasure screen %d cannot be reached" % [index, which, f["trigger_screen"]])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


# --- how the port picks pieces up --------------------------------------------------------------------------------

# --- the data -----------------------------------------------------------------------------------------------------

func test_neighbour_tables_lead_back_except_where_the_original_does_not() -> void:
	var problems: Array[String] = []
	for i in Catalog.ORIGINAL_SECTOR_COUNT:
		var found: Array = ReachSweep.data_findings(Catalog.sector(i))["neighbours"]
		var known: Array = KNOWN_ONE_WAY_NEIGHBOURS.get(i, [])
		for line: String in found:
			if not (line in known):
				problems.append("sector %d: %s" % [i, line])
		for line: String in known:
			if not (line in found):
				problems.append("sector %d: expected the one-way connection '%s'" % [i, line])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_no_tile_is_both_solid_and_a_current() -> void:
	var problems: Array[String] = []
	for i in Catalog.ORIGINAL_SECTOR_COUNT:
		for line: String in ReachSweep.data_findings(Catalog.sector(i))["tiles"]:
			problems.append("sector %d: %s" % [i, line])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_sector_data_equals_the_extracted_original_data() -> void:
	# extracted/tables/sectors.json comes straight from the original's data (tools/analysis); the port's .tres files must hold the same
	# tiles, neighbour tables, pieces and start positions.
	var path := ProjectSettings.globalize_path("res://").path_join("../extracted/tables/sectors.json").simplify_path()
	if not FileAccess.file_exists(path):
		prints("extracted/tables/sectors.json not found, skipped")
		return
	var original: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_int(original.size()).is_equal(Catalog.ORIGINAL_SECTOR_COUNT)
	var problems: Array[String] = []
	for i in Catalog.ORIGINAL_SECTOR_COUNT:
		var sector := Catalog.sector(i)
		var o: Dictionary = original[i]
		if sector.start_pos != Vector2i(int(o["start_x"]), int(o["start_y"])) or sector.start_frame != int(o["start_cell"]):
			problems.append("sector %d: start %s cell %d, original (%d, %d) cell %d" % [i, sector.start_pos, sector.start_frame, o["start_x"], o["start_y"], o["start_cell"]])
		if sector.pieces.size() != int(o["n_pieces"]):
			problems.append("sector %d: %d pieces, original %d" % [i, sector.pieces.size(), o["n_pieces"]])
		else:
			for k in sector.pieces.size():
				var piece := sector.pieces[k]
				if piece.screen != int(o["piece_screen"][k]) or piece.pos != Vector2i(int(o["piece_x"][k]), int(o["piece_y"][k])):
					problems.append("sector %d piece %d: screen %d at %s, original screen %d at (%d, %d)" % [i, k, piece.screen, piece.pos, o["piece_screen"][k], o["piece_x"][k], o["piece_y"][k]])
		var sides := [sector.neighbors_left, sector.neighbors_right, sector.neighbors_up, sector.neighbors_down]
		var names := ["left", "right", "up", "down"]
		for side in 4:
			for screen in 12:
				if sides[side][screen] != int(o["nbr"][names[side]][screen]) - 1:
					problems.append("sector %d screen %d %s: %d, original %d" % [i, screen, names[side], sides[side][screen], int(o["nbr"][names[side]][screen]) - 1])
		for screen in 12:
			var tiles: PackedByteArray = sector.screens[screen].tiles
			var expected: Array = o["screens"][screen]["tiles"]
			for t in tiles.size():
				if tiles[t] != int(expected[t]):
					problems.append("sector %d screen %d tile %d: 0x%02x, original 0x%02x" % [i, screen, t, tiles[t], int(expected[t])])
					break
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


# --- currents and creatures (information) ----------------------------------------------------------------------

func test_no_current_is_strong_enough_to_stop_the_sub() -> void:
	# A key adds 12 units per tick; a current at least that strong could hold the sub back from going against it. The strongest in the game is 8.
	var effects := ReachSweep.parallel(_jobs, ReachSweep.strong_current_effect)
	var problems: Array[String] = []
	for k in effects.size():
		var e: Dictionary = effects[k]
		if e["strong_tiles"] > 0:
			problems.append("sector %d: %d current tiles of strength >= %d; pieces behind them if impassable: %s, end station lost: %s" % [k, e["strong_tiles"], ReachSweep.STRONG_CURRENT, e["lost_pieces"], e["lost_dock"]])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_report_creatures_that_sit_in_the_only_way() -> void:
	# Report only. Creatures never block the sub (only the tile map does), but a hostile creature that stays put and sits in the only passage
	# makes contact (1 air) unavoidable; ink or the 30 ticks of invulnerability get the sub past it.
	var chokes := ReachSweep.parallel(_jobs, ReachSweep.creature_choke)
	for k in chokes.size():
		var c: Dictionary = chokes[k]
		if not c["forced"].is_empty():
			var names: Dictionary = {}
			for f: Dictionary in c["forced"]:
				for who: String in f["creatures"]:
					names[who] = true
			prints("sector %d: %s sit%s in the only way to %d targets" % [k, ", ".join(names.keys()), "s" if names.size() == 1 else "", c["forced"].size()])
	assert_int(chokes.size()).is_equal(Catalog.ORIGINAL_SECTOR_COUNT)
