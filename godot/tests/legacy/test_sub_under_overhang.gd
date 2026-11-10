class_name TestSubUnderOverhang
extends GdUnitTestSuite
## Teaches: checking a screenshot of the original against the port. A screenshot of the original
## (sector 0, screen 5) shows the sub facing left at SubX / SubY = (332, 246) with the tail fin overlapping the
## floor art: the fixed wall box (x SubX-8 .. SubX+71, y SubY-22 .. SubY+9) is shorter than the ~48 px sprite, so the
## rest of the picture may hang over solid tiles. The port must be able to be in that spot too.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const SPOT := Vector2i(332, 246)

var _runner: GdUnitSceneRunner
var _world: SectorWorld


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()
	_runner = scene_runner(WORLD_SCENE)
	_world = _runner.scene() as SectorWorld
	_world.load_sector(0, 5)


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()


func _is_solid(column: int, row: int) -> bool:
	return _world.tile_grid.is_solid(column, row)


func test_the_wall_box_at_the_screenshot_position_touches_no_solid_tile() -> void:
	var box := Rect2i(SPOT.x - 8, SPOT.y - 22, 80, 32)
	for column in range(box.position.x / 16, (box.end.x - 1) / 16 + 1):
		for row in range(box.position.y / 16, (box.end.y - 1) / 16 + 1):
			assert_bool(_is_solid(column, row)).is_false()


func test_the_sub_can_be_placed_and_sits_there_facing_left() -> void:
	_world.start_flight(SPOT.x, SPOT.y, 0)
	assert_that(_world.sim.sub.original_position()).is_equal(SPOT)
	for i in 5:
		_world.sim.sub.logic_tick()                      # no key, no current: it stays (or drifts only with a current)
	assert_int(_world.sim.sub.original_position().y).is_between(SPOT.y - 2, SPOT.y + 2)


func test_flying_left_along_that_height_passes_the_spot() -> void:
	_world.start_flight(400, SPOT.y, 6)
	var visited: Array[int] = []
	for i in 30:
		_world.sim.sub.logic_tick(InputSnapshot.steering(-1))
		visited.append(_world.sim.sub.original_position().x)
	# It keeps going left through x = 332 (it is not stopped by the box of the floor tiles).
	assert_int(visited.min()).is_less(SPOT.x)
	assert_int(visited.min()).is_less_equal(visited[0])
