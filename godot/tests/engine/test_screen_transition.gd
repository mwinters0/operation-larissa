class_name TestScreenTransition
extends GdUnitTestSuite
## Teaches: signals in tests (`await_signal`-free: we collect the emissions in an
## array with a lambda) and flying the real sub through the real data.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const Direction := SectorData.Direction

var _world: SectorWorld
var _changes: Array


func before_test() -> void:
	GameClock.paused = true
	_world = scene_runner(WORLD_SCENE).scene() as SectorWorld
	_changes = []
	_world.screen_changed.connect(func(screen: int, direction: int) -> void: _changes.append([screen, direction]))


func after_test() -> void:
	GameClock.paused = false


## Empties the walls so that the test does not depend on the level's rock.
func _open_water() -> void:
	_world.tile_grid.clear()


func test_leaving_right_enters_the_right_neighbour_at_the_left_edge() -> void:
	_world.load_sector(Ground.MAP, 0)
	_world.start_flight()
	_open_water()
	_world.sim.sub.position = Vector2(608.5, 100)
	_world.sim.sub.logic_tick()
	var expected := _world.sector.neighbors_right[0]
	assert_int(expected).is_equal(1)             # (the map sector: screen = 4 * row + column)
	assert_int(_world.screen_index).is_equal(expected)
	assert_array(_changes).is_equal([[expected, Direction.RIGHT]])
	assert_float(_world.sim.sub.position.x).is_equal(0.0)          # SubX = -32 in the original


func test_leaving_left_enters_at_the_right_edge() -> void:
	_world.load_sector(Ground.MAP, 1)
	_world.start_flight()
	_open_water()
	_world.sim.sub.position = Vector2(-0.5, 100)
	_world.sim.sub.logic_tick()
	assert_int(_world.screen_index).is_equal(_world.sector.neighbors_left[1])
	assert_float(_world.sim.sub.position.x).is_equal(604.0)        # SubX = 572 in the original


func test_vertical_transitions_use_the_up_and_down_tables() -> void:
	# The map sector: screen 3 has screen 7 below it and 7 has 3 above; the numbers come from the table.
	_world.load_sector(Ground.MAP, 3)
	var below := _world.sector.neighbors_down[3]
	assert_int(below).is_greater_equal(0)
	_world.start_flight()
	_open_water()
	_world.sim.sub.position = Vector2(300, 286.5)
	_world.sim.sub.logic_tick()
	assert_int(_world.screen_index).is_equal(below)
	assert_float(_world.sim.sub.position.y).is_equal(-2.0)         # SubY = 3
	_world.sim.sub.position = Vector2(300, -2.5)
	_world.sim.sub.logic_tick()
	assert_int(_world.screen_index).is_equal(3)                # the way back
	assert_float(_world.sim.sub.position.y).is_equal(285.0)        # SubY = 290


func test_no_neighbour_clamps_the_sub() -> void:
	_world.load_sector(Ground.MAIN, 0)               # (screen 0 of the row has no neighbour on the left, above or below)
	_world.start_flight()
	_open_water()
	for case in [
		[Vector2(-5, 100), "x", 0.0], [Vector2(100, -9), "y", -2.0],
		[Vector2(100, 300), "y", 285.0]]:
		_world.sim.sub.position = case[0]
		_world.sim.sub.logic_tick()
		assert_int(_world.screen_index).is_equal(0)
		if case[1] == "x":
			assert_float(_world.sim.sub.position.x).is_equal(case[2])
		else:
			assert_float(_world.sim.sub.position.y).is_equal(case[2])
	assert_array(_changes).is_empty()


func test_flying_right_from_the_start_position_reaches_screen_1() -> void:
	# The real thing: real rock, real physics, the right arrow held down.
	_world.load_sector(Ground.MAIN, 0)
	_world.start_flight()
	var ticks := 0
	while _world.screen_index == 0 and ticks < 200:
		_world.sim.sub.logic_tick(InputSnapshot.steering(1))
		ticks += 1
	assert_int(_world.screen_index).is_equal(1)
	assert_int(_changes.size()).is_equal(1)
	assert_float(_world.sim.sub.position.x).is_less(60.0)          # just arrived at the left edge
	assert_int(ticks).is_less(200)


func test_respawn_point_is_free_water_in_every_sector() -> void:
	# `start_pos` is the header's respawn point on the midpoint screen: free water in every sector of the chain.
	for sector_index in Catalog.sector_ids():
		_world.load_sector(sector_index, Tuning.resolve().midpoint_screen)
		_world.start_flight()
		var sub := _world.sim.sub
		sub.velocity_units = Vector2i.ZERO
		var before := sub.position
		sub.logic_tick()
		# Not pushed out of a wall (the physics engine may nudge it by its 0.08 px safety margin).
		assert_float(sub.position.distance_to(before)).is_less(0.5)
		assert_int(_world.screen_index).is_equal(Tuning.resolve().midpoint_screen)
