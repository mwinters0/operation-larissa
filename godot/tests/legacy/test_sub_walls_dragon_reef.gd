class_name TestSubWallsDragonReef
extends GdUnitTestSuite
## Teaches: regression-testing against measurements of the original. Dragon Reef (zone 1), sector index 1
## ("Second"), screen 1: the sub could not reach the rock piece (piece 7, window (560, 208)) on the right. The
## original lets it stop at SubX = 440 / 472 / 504 at SubY = 262 / 230 / 171 (three screenshots of the original,
## measured with tools/analysis/register_screenshot.py). The old physics-engine walls refused to slide sideways
## while the wall box touched the ceiling (SubY = 230: the box top rests on the tile row 12), so the sub never
## got past x = 440. (The engine's rules for the sub's walls, on a sector of dev's, are in `tests/engine/test_sub_walls.gd`.)

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const PIECE := 7

var _runner: GdUnitSceneRunner
var _world: SectorWorld


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()
	_runner = scene_runner(WORLD_SCENE)
	_world = _runner.scene() as SectorWorld
	_world.load_sector(1, 1)


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


func test_rightmost_positions_match_the_original() -> void:
	assert_that(_rightmost_from(Vector2i(400, 262))).is_equal(Vector2i(440, 262))   # a: floor and the rock at x = 512
	assert_that(_rightmost_from(Vector2i(400, 230))).is_equal(Vector2i(472, 230))   # b: the box top rests on a ceiling tile
	assert_that(_rightmost_from(Vector2i(456, 171))).is_equal(Vector2i(504, 171))   # c: rock at x = 576, rows 9-11


func test_resting_against_the_ceiling_does_not_block_sideways_moves() -> void:
	_world.start_flight(440, 262, 6)
	_drive([&"sub_up"], 8)
	assert_int(_world.sim.sub.original_position().y).is_equal(230)       # the box top is on the tile edge y = 208
	_drive([&"sub_right"], 30)
	assert_int(_world.sim.sub.original_position().x).is_equal(472)


func test_the_piece_can_be_collected() -> void:
	_world.start_flight(456, 171, 6)
	_drive([&"sub_right"], 40)
	assert_that(_world.sim.sub.original_position()).is_equal(Vector2i(504, 171))
	_world.tick()
	await get_tree().process_frame
	assert_bool(GameState.has_piece(PIECE)).is_true()


func test_the_lower_stops_do_not_reach_the_piece() -> void:
	_world.start_flight(400, 230, 6)
	_drive([&"sub_right"], 40)
	_world.tick()
	assert_bool(GameState.has_piece(PIECE)).is_false()
