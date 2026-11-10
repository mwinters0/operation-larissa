class_name TestSubWalls
extends GdUnitTestSuite
## Teaches: the sub's wall box against rock at chosen heights. The ledge sector (`Ground.LEDGE`, screen 1) has rock A low on the floor, a ceiling over the floor,
## rock B behind the ceiling's end and rock C higher up with a piece behind it (`ledge_sector` in tools/dev_pack/test_sectors/batch_a.py); the sub flies right at
## each height and stops flush against the rock. The original's own measurements (Dragon Reef) are in `tests/legacy/test_sub_walls_dragon_reef.gd`.
##
## The box of the sub is the run's `wall_box` (80 x 32 in the original: x from SubX - 8 to SubX + 71, y from SubY - 22 to SubY + 9), so flush against a rock at
## tile column C the sub stands at SubX = 16 * C + 16 - the box's right edge (`_flush`; 16 * C - 72 in the original). The old physics-engine walls refused to slide sideways while the box touched the ceiling; a sub resting against a ceiling must still move.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const SCREEN := 1
const COLUMN_A := 30                      ## rock A: rows 15-16
const COLUMN_B := 32                      ## rock B: rows 13-14
const COLUMN_C := 34                      ## rock C: rows 9-11
const PIECE := 1                          ## behind rock C
## The heights: along the floor (the box's rows 14-15, the floor starts at row 16), under the ceiling (rows 13-14) and beside rock C (rows 9-10).
const Y_FLOOR := 246
const Y_CEILING := 230
const Y_ROCK_C := 166

## SubX of a sub whose box stands flush against a rock at tile column `column` (the box's right edge is at `wall_box.end.x` from the picture's corner,
## which lies 16 from the tile map).
func _flush(column: int) -> int:
	return 16 * column + 16 - Tuning.resolve().sub.wall_box.end.x


var _runner: GdUnitSceneRunner
var _world: SectorWorld


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()
	_runner = scene_runner(WORLD_SCENE)
	_world = _runner.scene() as SectorWorld
	_world.load_sector(Ground.LEDGE, SCREEN)


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()


func _drive(keys: Array[StringName], ticks: int) -> void:
	var held := KeyState.new()
	for key in keys:
		held.press(key)
	for i in ticks:
		_world.sim.sub.logic_tick(held.snapshot())


func _rightmost_from(start: Vector2i) -> Vector2i:
	_world.start_flight(start.x, start.y, 6)
	_drive([&"sub_right"], 40)
	return _world.sim.sub.original_position()


func test_the_sub_stops_flush_against_the_rock_at_every_height() -> void:
	assert_that(_rightmost_from(Vector2i(_flush(COLUMN_A) - 40, Y_FLOOR))).is_equal(Vector2i(_flush(COLUMN_A), Y_FLOOR))        # a: the floor and rock A
	assert_that(_rightmost_from(Vector2i(_flush(COLUMN_A) - 40, Y_CEILING))).is_equal(Vector2i(_flush(COLUMN_B), Y_CEILING))    # b: the box top rests on the ceiling, rock A is below
	assert_that(_rightmost_from(Vector2i(_flush(COLUMN_C) - 48, Y_ROCK_C))).is_equal(Vector2i(_flush(COLUMN_C), Y_ROCK_C))      # c: beside rock C


func test_resting_against_the_ceiling_does_not_block_sideways_moves() -> void:
	_world.start_flight(_flush(COLUMN_A), Y_FLOOR, 6)
	_drive([&"sub_up"], 8)
	assert_int(_world.sim.sub.original_position().y).is_equal(Y_CEILING)       # the box top is on the tile edge y = 208
	_drive([&"sub_right"], 30)
	assert_int(_world.sim.sub.original_position().x).is_equal(_flush(COLUMN_B))


func _solid_tiles_under(window_rect: Rect2i) -> int:
	var solid := 0
	for column in range((window_rect.position.x - 16) / 16, (window_rect.end.x - 1 - 16) / 16 + 1):
		for row in range((window_rect.position.y - 32) / 16, (window_rect.end.y - 1 - 32) / 16 + 1):
			solid += 1 if _world.tile_grid.is_solid(column, row) else 0
	return solid


func test_the_picture_may_hang_over_rock_the_wall_box_clears() -> void:
	# The wall box (80 x 32) is smaller than the picture (96 x 58): under the ceiling the box top rests on the tile edge while the top of the picture is 10 px
	# inside the ceiling's tiles. The sub can be put there, stays, and flies on (rock only stops the box).
	var spot := Vector2i(_flush(COLUMN_A) - 8, Y_CEILING)
	_world.start_flight(spot.x, spot.y, 6)
	var tuning := _world.sim.sub.tuning
	assert_int(_solid_tiles_under(Rect2i(tuning.wall_box.position + spot, tuning.wall_box.size))).is_equal(0)
	assert_int(_solid_tiles_under(Rect2i(spot, Vector2i(96, 58)))).is_greater(0)
	for i in 5:
		_world.sim.sub.logic_tick()
	assert_that(_world.sim.sub.original_position()).is_equal(spot)
	_drive([&"sub_right"], 40)
	assert_int(_world.sim.sub.original_position().x).is_equal(_flush(COLUMN_B))


func test_the_piece_can_be_collected() -> void:
	_world.start_flight(_flush(COLUMN_C) - 16, Y_ROCK_C, 6)
	_drive([&"sub_right"], 40)
	assert_that(_world.sim.sub.original_position()).is_equal(Vector2i(_flush(COLUMN_C), Y_ROCK_C))
	_world.tick()
	await get_tree().process_frame
	assert_bool(GameState.has_piece(PIECE)).is_true()


func test_the_lower_stops_do_not_reach_the_piece() -> void:
	_world.start_flight(_flush(COLUMN_A) - 40, Y_CEILING, 6)
	_drive([&"sub_right"], 40)
	_world.tick()
	assert_bool(GameState.has_piece(PIECE)).is_false()


# --- the scan itself (pure function, the original's ScanSubWalls (0x418ea7)) --------------------------------------------------

func _solid_at(cells: Array[Vector2i]) -> Callable:
	return func(column: int, row: int) -> bool: return Vector2i(column, row) in cells


func test_scan_returns_the_free_distance_to_the_next_tile_column() -> void:
	# SubX 440: the box covers x 432..511; tile column 32 starts at 512, so nothing is left to move.
	var wall := _solid_at([Vector2i(32, 15)])
	assert_int(SubModel.wall_gap(SubModel.WallSide.RIGHT, Vector2i(440, 262), wall, Tuning.original().sub.wall_box)).is_equal(0)
	assert_int(SubModel.wall_gap(SubModel.WallSide.RIGHT, Vector2i(424, 262), wall, Tuning.original().sub.wall_box)).is_equal(16)
	assert_int(SubModel.wall_gap(SubModel.WallSide.RIGHT, Vector2i(408, 262), wall, Tuning.original().sub.wall_box)).is_equal(-1)      # farther than two tiles
	# Rows: the box covers y 240..271 = rows 15 and 16; row 14 (SubY 262 - 16) is not looked at.
	assert_int(SubModel.wall_gap(SubModel.WallSide.RIGHT, Vector2i(440, 262), _solid_at([Vector2i(32, 14)]), Tuning.original().sub.wall_box)).is_equal(-1)


func test_scan_ignores_tiles_the_box_already_overlaps() -> void:
	var inside := _solid_at([Vector2i(30, 15)])                     # in the box's own edge column
	assert_int(SubModel.wall_gap(SubModel.WallSide.RIGHT, Vector2i(440, 262), inside, Tuning.original().sub.wall_box)).is_equal(-1)


func test_scan_up_and_down_use_the_ceiling_and_floor_rows() -> void:
	# SubY 230: box y 208..239 (rows 13-14). Row 12 (y 192..207) is the ceiling, row 15 starts at y 240.
	var ceiling := _solid_at([Vector2i(28, 12)])
	assert_int(SubModel.wall_gap(SubModel.WallSide.UP, Vector2i(440, 230), ceiling, Tuning.original().sub.wall_box)).is_equal(0)
	assert_int(SubModel.wall_gap(SubModel.WallSide.UP, Vector2i(440, 238), ceiling, Tuning.original().sub.wall_box)).is_equal(-8)
	var floor_tile := _solid_at([Vector2i(28, 15)])
	assert_int(SubModel.wall_gap(SubModel.WallSide.DOWN, Vector2i(440, 230), floor_tile, Tuning.original().sub.wall_box)).is_equal(0)
	assert_int(SubModel.wall_gap(SubModel.WallSide.DOWN, Vector2i(440, 222), floor_tile, Tuning.original().sub.wall_box)).is_equal(8)
	assert_int(SubModel.wall_gap(SubModel.WallSide.DOWN, Vector2i(440, 230), _solid_at([]), Tuning.original().sub.wall_box)).is_equal(-1)


func test_scan_left_returns_a_negative_distance() -> void:
	# SubX 472: box left edge x = 464 (column 29); column 28 ends at 463.
	var wall := _solid_at([Vector2i(28, 13)])
	assert_int(SubModel.wall_gap(SubModel.WallSide.LEFT, Vector2i(472, 230), wall, Tuning.original().sub.wall_box)).is_equal(0)
	assert_int(SubModel.wall_gap(SubModel.WallSide.LEFT, Vector2i(488, 230), wall, Tuning.original().sub.wall_box)).is_equal(-16)
	assert_int(SubModel.wall_gap(SubModel.WallSide.LEFT, Vector2i(504, 230), wall, Tuning.original().sub.wall_box)).is_equal(1)
