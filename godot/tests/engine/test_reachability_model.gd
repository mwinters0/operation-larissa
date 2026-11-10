class_name TestReachabilityModel
extends GdUnitTestSuite
## Teaches: testing a TEST TOOL. The reachability sweep (`SectorReach`) is only worth something if its model of the sub
## is the game's. This suite plays the model against the real `Sub` and `SectorWorld`: the gap tables against `SubModel.wall_gap`,
## one tick of movement against `SubModel._move`, screen changes against the world's own, and finally it walks the sub along a
## path the search found, with real key presses, to show the one-step moves are possible for a player.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"

var _runner: GdUnitSceneRunner
var _world: SectorWorld


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()
	_runner = scene_runner(WORLD_SCENE)
	_world = _runner.scene() as SectorWorld


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()


# --- the search itself on tiny made-up sectors ----------------------------------------------------------------

## 12 screens of open water (nothing solid) with the usual chain of neighbours: screen k -> k + 1 on the right.
func _open_sector(solid_cells: Array[Vector3i] = [], right: Array[int] = []) -> SectorReach:
	var tile_screens: Array[PackedByteArray] = []
	for screen in 12:
		var tiles := PackedByteArray()
		tiles.resize(38 * 18)
		tile_screens.append(tiles)
	for cell in solid_cells:
		tile_screens[cell.x][cell.z * 38 + cell.y] = 0x40 | 1       # Vector3i(screen, column, row)
	var none := PackedInt32Array()
	none.resize(12)
	none.fill(-1)
	var right_side := none.duplicate()
	for k in right.size():
		right_side[k] = right[k]
	var sides: Array[PackedInt32Array] = [none.duplicate(), right_side, none.duplicate(), none.duplicate()]
	return SectorReach.from_tiles(tile_screens, sides, Tuning.original().sub)         # (hand-made geometry, made for the original's sub)


func test_open_water_is_reached_everywhere_and_the_edges_clamp() -> void:
	var reach := _open_sector()
	var visited := reach.explore([SectorReach.LAUNCH])
	# no neighbours at all: every grid state of screen 0 and nothing else
	assert_int(SectorReach.count(visited)).is_equal(SectorReach.PER_SCREEN)
	assert_bool(SectorReach.any_on_screen(visited, 1)).is_false()


func test_a_neighbour_table_carries_the_sub_over_and_wraps_the_position() -> void:
	var reach := _open_sector([], [1, 2])
	assert_that(reach.after_move(0, 576, 100)).is_equal(Vector3i(1, -32, 100))
	assert_that(reach.after_move(1, 600, 100)).is_equal(Vector3i(2, -32, 100))
	assert_that(reach.after_move(2, 600, 100)).is_equal(Vector3i(2, 572, 100))     # no neighbour: clamp
	assert_that(reach.after_move(0, -34, 100)).is_equal(Vector3i(0, -32, 100))
	assert_that(reach.after_move(0, 100, 2)).is_equal(Vector3i(0, 100, 3))
	assert_that(reach.after_move(0, 100, 291)).is_equal(Vector3i(0, 100, 290))
	var visited := reach.explore([SectorReach.LAUNCH])
	assert_bool(SectorReach.any_on_screen(visited, 2)).is_true()
	assert_bool(SectorReach.any_on_screen(visited, 3)).is_false()


## A room of tiles around columns 18-28 / rows 4-14 of screen 0 (interior: columns 19-27, rows 5-13 = tile pixels x 304..447, y 80..223).
func _room(door: bool) -> SectorReach:
	var cells: Array[Vector3i] = []
	for column in range(18, 29):
		cells.append(Vector3i(0, column, 4))
		cells.append(Vector3i(0, column, 14))
	for row in range(4, 15):
		if not (door and row >= 8 and row <= 11):          # a door four tiles high (rows 8-11) in the left wall
			cells.append(Vector3i(0, 18, row))
		cells.append(Vector3i(0, 28, row))
	return _open_sector(cells)


func test_a_sealed_room_is_not_reached() -> void:
	var reach := _room(false)
	var visited := reach.explore([SectorReach.LAUNCH])
	# The 80 x 32 wall box fits inside (SubX 312..376, SubY 102..214), but there is no way in.
	assert_int(SectorReach.first_state_in(visited, 0, 312, 376, 102, 214).x).is_equal(-1)
	assert_int(SectorReach.count(visited)).is_less(SectorReach.PER_SCREEN)


func test_an_opening_in_the_wall_lets_the_sub_in() -> void:
	var reach := _room(true)
	var visited := reach.explore([SectorReach.LAUNCH])
	assert_bool(SectorReach.first_state_in(visited, 0, 344, 344, 150, 150).x >= 0).is_true()


# --- the gap tables against the real scan -----------------------------------------------------------------------

func test_the_gap_tables_are_wall_gap() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var box := Tuning.resolve().sub.wall_box
	for sector_index in [Ground.MAIN, Ground.LEDGE, Ground.MAP, Ground.FINALE, Ground.TANGLE]:
		var reach := SectorReach.from_sector(Catalog.sector(sector_index), Tuning.resolve().sub)
		for n in 600:
			var screen := rng.randi_range(0, 11)
			var x := rng.randi_range(SectorReach.X_MIN / 2, SectorReach.X_MAX / 2) * 2
			var y := rng.randi_range(SectorReach.Y_MIN, SectorReach.Y_MAX)
			var cells := reach.solid[screen]
			var is_solid := func(column: int, row: int) -> bool: return cells[row * 38 + column] != 0
			for side in [SubModel.WallSide.LEFT, SubModel.WallSide.RIGHT, SubModel.WallSide.UP, SubModel.WallSide.DOWN]:
				var expected := SubModel.wall_gap(side, Vector2i(x, y), is_solid, box)
				if reach.gap(side, screen, x, y) != expected:
					fail("sector %d screen %d at (%d, %d): side %d table says %d, wall_gap %d" % [sector_index, screen, x, y, side, reach.gap(side, screen, x, y), expected])
					return


# --- one tick against the real sub ---------------------------------------------------------------------------------

func test_one_move_is_what_sub_move_does() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for sector_index in [Ground.LEDGE, Ground.MAP, Ground.FINALE]:
		var reach := SectorReach.from_sector(Catalog.sector(sector_index), Tuning.resolve().sub)
		_world.ignore_currents = true
		_world.load_sector(sector_index, 0)
		_world.start_flight()
		for screen in [0, 4, 9]:
			_world.load_screen(screen)
			for n in 250:
				var x := rng.randi_range(SectorReach.X_MIN / 2, SectorReach.X_MAX / 2) * 2
				var y := rng.randi_range(SectorReach.Y_MIN, SectorReach.Y_MAX)
				var step := Vector2i(rng.randi_range(-16, 16), rng.randi_range(-12, 12))
				_world.original.sub.place_original(x, y, 6)
				_world.sim.sub._move(step)
				var expected := reach.move_only(screen, x, y, step.x, step.y)
				if _world.sim.sub.original_position() != expected:
					fail("sector %d screen %d (%d, %d) + %s: SubModel._move gives %s, the model %s" % [
							sector_index, screen, x, y, step, _world.sim.sub.original_position(), expected])
					return


func test_screen_changes_are_what_the_world_does() -> void:
	# the tangle sector has neighbour tables that do not lead back (screen 9 left -> 5, but 5 right -> 6) and a ring (11 right -> 0), a good test of the table handling
	var sector_index := Ground.TANGLE
	var reach := SectorReach.from_sector(Catalog.sector(sector_index), Tuning.resolve().sub)
	_world.ignore_currents = true
	_world.load_sector(sector_index, 0)
	_world.start_flight()
	var spots: Array[Vector2i] = [
			Vector2i(-40, 100), Vector2i(580, 100), Vector2i(100, 0), Vector2i(100, 295),      # one side
			Vector2i(-40, 0), Vector2i(580, 0), Vector2i(-40, 295), Vector2i(580, 295)]          # a corner: two changes
	for screen in 12:
		for spot in spots:
			_world.load_screen(screen)
			_world.original.sub.place_original(spot.x, spot.y, 6)
			_world.sim.sub._check_edges()
			var expected := reach.after_move(screen, spot.x & ~1, spot.y)
			var actual := Vector3i(_world.screen_index, _world.sim.sub.original_position().x, _world.sim.sub.original_position().y)
			if actual != expected:
				fail("screen %d, SubX/SubY %s: the world goes to %s, the model to %s" % [screen, spot, actual, expected])
				return


# --- walking a found path with real keys ---------------------------------------------------------------------------

func _tap(key: StringName) -> void:
	var held := KeyState.new()
	held.press(key)
	_world.sim.sub.logic_tick(held.snapshot())


func _arrived(to: Vector3i) -> bool:
	var at := _world.sim.sub.original_position()
	return _world.screen_index == to.x and at.x == to.y and at.y == to.z


## Stops the sub on one axis with the opposite key, like a player would.
func _settle(horizontal: bool) -> void:
	for guard in 8:
		var v := _world.sim.sub.velocity_units.x if horizontal else _world.sim.sub.velocity_units.y
		if v == 0:
			return
		if horizontal:
			_tap(&"sub_left" if v > 0 else &"sub_right")
		else:
			_tap(&"sub_up" if v > 0 else &"sub_down")


## One grid step with the keys, as described in the header of SectorReach: press the key until the sub has arrived, then use the
## opposite key until it is at rest again. (Up is the odd one: one tap moves 2 px; if that is too far, come back 1 px with two taps down.)
## Returns false if the sub does not end up in `to`.
func _walk_one(to: Vector3i, direction: Vector2i) -> bool:
	var key: StringName = &"sub_right" if direction.x > 0 else (&"sub_left" if direction.x < 0 else (&"sub_down" if direction.y > 0 else &"sub_up"))
	if direction == Vector2i(0, -1):
		_tap(key)
		if not _arrived(to):
			_tap(&"sub_down")
			_tap(&"sub_down")
	else:
		for guard in 4:
			if _arrived(to):
				break
			_tap(key)
	_settle(direction.x != 0)
	return _arrived(to) and _world.sim.sub.velocity_units == Vector2i.ZERO


func _walk_path(reach: SectorReach, path: PackedInt32Array) -> String:
	var steps: Array[Vector2i] = [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for k in range(1, path.size()):
		var from := Vector3i(SectorReach.state_screen(path[k - 1]), SectorReach.state_x(path[k - 1]), SectorReach.state_y(path[k - 1]))
		var to := Vector3i(SectorReach.state_screen(path[k]), SectorReach.state_x(path[k]), SectorReach.state_y(path[k]))
		var direction := Vector2i.ZERO
		for step in steps:
			if reach.step(from.x, from.y, from.z, step.x, step.y) == to:
				direction = step
				break
		if direction == Vector2i.ZERO:
			return "step %d: %s -> %s is not a model step" % [k, from, to]
		if not _walk_one(to, direction):
			return "step %d: from %s with %s the sub is at screen %d %s (model: %s), velocity %s" % [
					k, from, direction, _world.screen_index, _world.sim.sub.original_position(), to, _world.sim.sub.velocity_units]
	return ""


func _walk_to_piece(sector_index: int, piece_index: int) -> String:
	var sector := Catalog.sector(sector_index)
	var reach := SectorReach.from_sector(sector, Tuning.resolve().sub)
	reach.record_parents = true
	var visited := reach.explore([SectorReach.LAUNCH])
	var piece := sector.pieces[piece_index]
	var goal := SectorReach.first_pickup_original(visited, piece.screen, piece.pos.x, piece.pos.y)
	if goal.x < 0:
		return "the search does not reach the piece"
	var path := reach.path_to(SectorReach.state_index(goal.x, goal.y, goal.z))
	if path.size() < 100:
		return "the path is only %d steps long: not a real test" % path.size()
	_world.ignore_currents = true                                                    # the search ignores currents
	_world.load_sector(sector_index, 0)
	_world.start_flight(SectorReach.LAUNCH.y, SectorReach.LAUNCH.z, 6)
	var message := _walk_path(reach, path)
	if message != "":
		return message
	# the real pick-up happens in the physics step; the model's test is the original's rectangle: compare with that
	var at := _world.sim.sub.original_position()
	if not (at.x <= piece.pos.x + 23 and piece.pos.x <= at.x + 95 and at.y <= piece.pos.y + 19 and piece.pos.y <= at.y + 57):
		return "the sub ended at %s, which does not touch the piece at %s" % [at, piece.pos]
	return ""


func test_a_player_can_walk_the_found_path_to_the_capsule_behind_a_rock() -> void:
	# the ledge sector, piece 1: behind a rock that the old physics-engine walls made unreachable
	assert_str(_walk_to_piece(Ground.LEDGE, 1)).is_empty()


func test_a_player_can_walk_the_found_path_to_far_pieces() -> void:
	assert_str(_walk_to_piece(Ground.MAIN, 0)).is_empty()          # the data canister, several screens away
	assert_str(_walk_to_piece(Ground.MAIN, 6)).is_empty()          # the same screen, across the screens with water currents (the walk switches them off)


func test_a_player_can_walk_the_found_path_to_the_piece_at_the_end_of_a_tunnel() -> void:
	# a piece whose contact positions are the fewest (one row of 16 positions in a tunnel as high as the sub's wall box): the hardest test of fine control
	assert_str(_walk_to_piece(Ground.LEDGE, 2)).is_empty()


func test_a_player_can_walk_the_found_path_to_every_piece_of_the_ledge_sector() -> void:
	for piece in Catalog.sector(Ground.LEDGE).pieces.size():
		var message := _walk_to_piece(Ground.LEDGE, piece)
		if message != "":
			fail("ledge sector piece %d: %s" % [piece, message])
			return


# --- the big steps follow the sub's top speeds ----------------------------------------------------------------------

func test_the_fast_steps_are_the_top_speed_and_half_of_it() -> void:
	var original := SectorReach.from_tiles([] as Array[PackedByteArray], [] as Array[PackedInt32Array], Tuning.original().sub)
	assert_vector(Vector2(original.max_step)).is_equal(Vector2(16, 12))       # (128 >> 3, 96 >> 3)
	var steps := original._fast_steps()
	for move in [[16, 12], [-16, 0], [0, -12], [8, 6], [-8, -6]]:
		assert_bool(_has_step(steps, move[0], move[1])).override_failure_message("no step %s" % str(move)).is_true()
	var sub := Tuning.resolve().sub                                          # (the dev pack's speeds differ from the original's)
	var chain := SectorReach.from_tiles([] as Array[PackedByteArray], [] as Array[PackedInt32Array], sub)
	assert_vector(Vector2(chain.max_step)).is_equal(Vector2(sub.max_speed_x_units >> 3, sub.max_speed_y_units >> 3))
	assert_bool(_has_step(chain._fast_steps(), sub.max_speed_x_units >> 3, sub.max_speed_y_units >> 3)).is_true()


func _has_step(steps: Array[int], dx: int, dy: int) -> bool:
	for i in range(0, steps.size(), 2):
		if steps[i] == dx and steps[i + 1] == dy:
			return true
	return false
