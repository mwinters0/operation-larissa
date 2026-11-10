class_name TestSectorWorldNavigation
extends GdUnitTestSuite
## Teaches: testing against data tables, and a small graph walk (breadth-first search).

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const Direction := SectorData.Direction


func test_screen_0_of_the_map_sector_has_neighbours_right_and_below() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(Ground.MAP)
	# The map sector is four screens wide and three high (screen = 4 * row + column): screen 0 is its top left corner.
	assert_int(world.neighbor(0, Direction.RIGHT)).is_equal(1)
	assert_int(world.neighbor(0, Direction.DOWN)).is_equal(4)
	assert_int(world.neighbor(0, Direction.LEFT)).is_equal(-1)
	assert_int(world.neighbor(0, Direction.UP)).is_equal(-1)


func test_neighbours_follow_the_tables() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	for sector_index in Catalog.sector_ids():
		world.load_sector(sector_index)
		for screen in 12:
			assert_int(world.neighbor(screen, Direction.LEFT)).is_equal(world.sector.neighbors_left[screen])
			assert_int(world.neighbor(screen, Direction.RIGHT)).is_equal(world.sector.neighbors_right[screen])
			assert_int(world.neighbor(screen, Direction.UP)).is_equal(world.sector.neighbors_up[screen])
			assert_int(world.neighbor(screen, Direction.DOWN)).is_equal(world.sector.neighbors_down[screen])


func test_go_moves_and_clamps() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(Ground.MAP, 0)
	assert_bool(world.go(Direction.LEFT)).is_false()   # no neighbour: clamped
	assert_int(world.screen_index).is_equal(0)
	assert_bool(world.go(Direction.RIGHT)).is_true()
	assert_int(world.screen_index).is_equal(1)
	assert_bool(world.go(Direction.LEFT)).is_true()    # and back
	assert_int(world.screen_index).is_equal(0)


func test_walking_through_the_map_sector_reaches_screen_11() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(Ground.MAP, 0)
	# Breadth-first search over "screen -> neighbouring screens".
	var seen := {0: true}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for direction in [Direction.LEFT, Direction.RIGHT, Direction.UP, Direction.DOWN]:
			var next := world.neighbor(current, direction)
			if next >= 0 and not seen.has(next):
				seen[next] = true
				queue.append(next)
	assert_int(seen.size()).is_equal(12)
	assert_bool(seen.has(11)).is_true()


func test_moves_are_reversible_in_the_map_sector() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(Ground.MAP)
	var opposite := {
		Direction.LEFT: Direction.RIGHT, Direction.RIGHT: Direction.LEFT,
		Direction.UP: Direction.DOWN, Direction.DOWN: Direction.UP}
	for screen in 12:
		for direction: Direction in opposite:
			var next := world.neighbor(screen, direction)
			if next >= 0:
				assert_int(world.neighbor(next, opposite[direction])).is_equal(screen)
