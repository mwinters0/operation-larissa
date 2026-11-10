class_name TestSectorReachability
extends GdUnitTestSuite
## Teaches: an automatic "can the player finish every level?" test. `SectorReach` searches everywhere the sub can go in a sector
## (the real wall scan, the real screen changes, DESIGN 3.3) and `ReachSweep` asks the questions below of the sectors of the dev pack that are fine
## as they are (`Ground.clean_sectors()`), one worker thread per sector; the sectors that are broken on purpose are made in memory by the last tests. See the headers of those two classes for the model and why it is sound (and
## `test_reachability_model.gd`, which checks the model against the real `Sub` and `SectorWorld`).
##
## What a failure means is spelled out in each test. The original's 32 sectors are swept by `tests/legacy/test_sector_reachability_legacy.gd`.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"

static var _results: Array = []
static var _jobs: Array = []
static var _seconds: float = 0.0

var _world: SectorWorld


func before() -> void:
	var started := Time.get_ticks_msec()
	_jobs.clear()
	for i in Ground.clean_sectors():
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
		for p: Dictionary in r["pieces"]:
			if p["orig_level"] < 0:
				problems.append("sector %d piece %d (screen %d, window %s): no position the sub can reach touches it" % [r["index"], p["index"], p["screen"], p["pos"]])
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
		for p: Dictionary in r["pieces"]:
			if p["orig_level"] >= 0 and p["port_level"] != p["orig_level"]:
				problems.append("sector %d piece %d: reachable in the original, but not with the port's contact rectangles (level %d)" % [r["index"], p["index"], p["port_level"]])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_piece_positions_and_screens_are_valid() -> void:
	var problems: Array[String] = []
	for i in Ground.clean_sectors():
		var findings := ReachSweep.data_findings(Catalog.sector(i))
		for line: String in findings["pieces"]:
			problems.append("sector %d: %s" % [i, line])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_no_piece_is_buried_in_the_rock() -> void:
	# Pieces rest on the sea floor and overlap it by a few rows (96 of 480 pixels is normal); 'buried' means the centre is solid
	# or more than 60 percent of the picture is.
	var problems: Array[String] = []
	var notes: Array[String] = []
	for i in Ground.clean_sectors():
		for line: String in ReachSweep.data_findings(Catalog.sector(i))["embedded"]:
			var pixels := int(line.split(": ")[1].split(" of")[0])
			if "centre is solid" in line or pixels > 288:
				problems.append("sector %d %s" % [i, line])
			elif pixels > 192:
				notes.append("sector %d %s" % [i, line])
	if not notes.is_empty():
		prints("half-buried pieces (fine, they are reached):\n" + "\n".join(notes))
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


# --- a sector that is not fine: the sweep names what is wrong ------------------------------------------------------

## A copy of the ground sector with its last screen (`m`: it holds no piece, so closing it off hides none) all rock except a pocket (tile columns 15-25, rows 6-11) and piece 3 put inside it.
func _sector_with_a_sealed_piece(m: int) -> SectorData:
	var sector := Ground.copy_of()
	sector.screens[m] = sector.screens[m].duplicate_deep() as ScreenData
	for i in ScreenData.TILE_BYTES:
		sector.screens[m].tiles[i] = 0x41
	for row in range(6, 12):
		for column in range(15, 26):
			sector.screens[m].tiles[row * ScreenData.TILE_COLUMNS + column] = 0
	sector.pieces[3].screen = m
	sector.pieces[3].pos = Vector2i(300, 150)
	return sector


func test_a_piece_in_a_sealed_pocket_is_not_reached() -> void:
	var result := ReachSweep.analyze(ReachSweep.prepare_for(_sector_with_a_sealed_piece(11)))
	for p: Dictionary in result["pieces"]:
		assert_bool(p["orig_level"] >= 0).override_failure_message("piece %d" % p["index"]).is_equal(p["index"] != 3)


func test_a_piece_in_the_rock_is_buried() -> void:
	var sector := _sector_with_a_sealed_piece(11)
	sector.pieces[3].pos = Vector2i(60, 60)                         # inside the rock around the pocket
	var buried: Array = ReachSweep.data_findings(sector)["embedded"]
	assert_array(buried).has_size(1)
	assert_str(buried[0]).contains("centre is solid")


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
	for index in [Ground.FINALE]:
		var r: Dictionary = _results[Ground.clean_sectors().find(index)]
		for key in ["finale", "finale_port_start"]:
			var f: Dictionary = r[key]
			var which := "launch" if key == "finale" else "port start"
			if f["touch_level"] < 0:
				problems.append("sector %d (%s): no reachable position touches the treasure (creature 0)" % [index, which])
			elif f["closing_level"] < 0:
				problems.append("sector %d (%s): after taking the treasure screen %d cannot be reached" % [index, which, f["trigger_screen"]])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_the_finale_sector_starts_with_the_station_launch() -> void:
	# `begin_sector` calls the station's launch whenever the sub starts on screen 0, with no exception for a finale: SubX 0 -> 96, SubY 202, cell 6, and the
	# station is drawn on screens 0 and 11 of every sector. (The original's finale sectors are in the legacy half.)
	SectorWorld.skip_animations = true
	var runner := scene_runner(WORLD_SCENE)
	_world = runner.scene() as SectorWorld
	var wrong: Array[String] = []
	for index in [Ground.FINALE]:
		await _world.begin_sector(index)
		var at := _world.sim.sub.original_position()
		if at != Vector2i(96, 202) or _world.screen_index != 0 or _world.sim.sub.cell != 6:
			wrong.append("sector %d: sub at %s cell %d on screen %d, the launch is at (96, 202), cell 6, screen 0" % [index, at, _world.sim.sub.cell, _world.screen_index])
	assert_array(wrong).override_failure_message("\n".join(wrong)).is_empty()


# --- how the port picks pieces up --------------------------------------------------------------------------------

func test_pieces_are_picked_up_with_the_whole_picture_box() -> void:
	# CheckProbeCollision (0x42dbb2): a piece is taken when SubX <= px + 23, px <= SubX + 95, SubY <= py + 19 and py <= SubY + 57, i.e. when the
	# whole 96 x 58 picture box of the sub touches the 24 x 20 piece, edges included; the sprite cell plays no part. The port tests the
	# same integers (`PieceModel.touched_by`, once per tick).
	var runner := scene_runner(WORLD_SCENE)
	_world = runner.scene() as SectorWorld
	var piece_index := 6                                          # the ground sector, screen 9: a rock at window (400, 150)
	_world.load_sector(Ground.MAIN, 9)
	var piece := _world.sector.pieces[piece_index]
	var cases := {
		"picture box touches with its bottom-right pixel": Vector2i(piece.pos.x - 95, piece.pos.y - 57),
		"picture box touches with its top-left pixel": Vector2i(piece.pos.x + 23, piece.pos.y + 19),
		"picture box covers only the piece's top row": Vector2i(piece.pos.x - 40, piece.pos.y - 57),
		"the sub's frame rectangle overlaps the piece (any rule picks it up)": Vector2i(piece.pos.x - 40, piece.pos.y - 25),
	}
	var missed: Array[String] = []
	for name: String in cases:
		GameState.reset()
		_world.load_sector(Ground.MAIN, 9)
		_world.start_flight()
		var at: Vector2i = cases[name]
		_world.original.sub.place_original(at.x, at.y, 6)
		_world.tick()
		if not GameState.has_piece(piece_index):
			missed.append("%s: sub at %s does not take the piece at %s" % [name, at, piece.pos])
	assert_array(missed).override_failure_message("A piece is taken in all these cases (the whole picture box touches it):\n" + "\n".join(missed)).is_empty()


# --- the data -----------------------------------------------------------------------------------------------------

func test_neighbour_tables_lead_back() -> void:
	var problems: Array[String] = []
	for i in Ground.clean_sectors():
		for line: String in ReachSweep.data_findings(Catalog.sector(i))["neighbours"]:
			problems.append("sector %d: %s" % [i, line])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_the_tangle_sector_has_exactly_its_three_one_way_connections() -> void:
	# (the tables of the tangle sector: 9 left -> 5 but 5 right -> 6; 4 up -> 8 but 8 has no way down; 8 right -> 9 but 9 left leads to 5)
	var found: Array = ReachSweep.data_findings(Catalog.sector(Ground.TANGLE))["neighbours"]
	assert_array(found).has_size(3)
	assert_str("\n".join(found)).contains("screen 9 left -> 5, but 5 right -> 6").contains("screen 4 up -> 8, but 8 down -> -1")


func test_no_tile_is_both_solid_and_a_current() -> void:
	var problems: Array[String] = []
	for i in Catalog.sector_ids():
		for line: String in ReachSweep.data_findings(Catalog.sector(i))["tiles"]:
			problems.append("sector %d: %s" % [i, line])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_the_wall_layer_has_exactly_the_solid_tiles() -> void:
	# What the OriginalPresenter puts into its TileMapLayer (the sub's wall source) against the tile bytes (flag 0x40) of every screen.
	var runner := scene_runner(WORLD_SCENE)
	_world = runner.scene() as SectorWorld
	var problems: Array[String] = []
	for i in Catalog.sector_ids():
		var sector := Catalog.sector(i)
		var zone := Catalog.zone(sector.zone)
		for screen in 12:
			var tiles: PackedByteArray = sector.screens[screen].tiles
			_world.original._build_tiles(sector.screens[screen], zone)
			var layer := _world.original.walls
			for t in tiles.size():
				var solid: bool = (tiles[t] & 0x40) != 0
				var cell := Vector2i(t % 38, t / 38)
				if (layer.get_cell_source_id(cell) != -1) != solid:
					problems.append("sector %d screen %d tile %s (0x%02x): the wall layer says %s" % [i, screen, cell, tiles[t], layer.get_cell_source_id(cell) != -1])
					break
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


# --- currents and creatures (information) ----------------------------------------------------------------------

func test_the_tileset_currents_are_the_designs_table() -> void:
	# DESIGN 3.3: direction d (bits 0-2) in the order NW N NE W E SW S SE, magnitude 2 * strength + 2 (strength = bits 3-5).
	var directions: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
	var source := Catalog.tileset().get_source(OriginalPresenter.CURRENTS_SOURCE_ID) as TileSetAtlasSource
	var problems: Array[String] = []
	for d in 8:
		for s in 8:
			var data := source.get_tile_data(Vector2i(d, s), 0)
			var expected := Vector2(directions[d] * (2 * s + 2))
			if data == null:
				problems.append("no tile for direction %d strength %d" % [d, s])
			elif (data.get_custom_data("current") as Vector2) != expected:
				problems.append("direction %d strength %d: %s, expected %s" % [d, s, data.get_custom_data("current"), expected])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_only_the_strongest_currents_of_the_ground_sector_could_stop_the_sub() -> void:
	# A key adds 12 units per tick; a current at least that strong could hold the sub back from going against it. The sectors made to be played have none; the
	# ground sector has eight tiles of the strongest strength (16 units), one for each direction, and none of them is in the way of a piece or the end station.
	var effects := ReachSweep.parallel(_jobs, ReachSweep.strong_current_effect)
	var sectors := Ground.clean_sectors()
	var problems: Array[String] = []
	for k in effects.size():
		var e: Dictionary = effects[k]
		var expected := 8 if sectors[k] == Ground.MAIN else 0
		if e["strong_tiles"] != expected:
			problems.append("sector %d: %d current tiles of strength >= %d, expected %d" % [sectors[k], e["strong_tiles"], ReachSweep.STRONG_CURRENT, expected])
		if not e["lost_pieces"].is_empty() or e["lost_dock"]:
			problems.append("sector %d: pieces behind strong currents if impassable: %s, end station lost: %s" % [sectors[k], e["lost_pieces"], e["lost_dock"]])
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
			prints("sector %d: %s sit%s in the only way to %d targets" % [Ground.clean_sectors()[k], ", ".join(names.keys()), "s" if names.size() == 1 else "", c["forced"].size()])
	assert_int(chokes.size()).is_equal(Ground.clean_sectors().size())
