class_name TestTileGrid
extends GdUnitTestSuite
## Teaches: proving that a plain-data copy of a view answers like the view. The rules (the sub's wall scan and water current,
## the ink pellet's rock test) ask a `TileGrid` built from the screen's tile bytes; the `Walls` and `Currents` `TileMapLayer`s of
## the playfield are only their picture. This suite compares the two for every cell of every screen of the chain's sectors, and the
## questions the sub and the pellets really ask (`SubModel.wall_gap`, `SubModel.read_current`, the pellet's rock test) at many positions.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"


func before_test() -> void:
	GameClock.paused = true


func after_test() -> void:
	GameClock.paused = false


# --- the grid on its own --------------------------------------------------------------------------------------

func test_a_new_grid_is_open_water() -> void:
	var grid := TileGrid.new()
	for row in TileGrid.ROWS:
		for column in TileGrid.COLUMNS:
			assert_bool(grid.is_solid(column, row)).is_false()
			assert_that(grid.current_at(column, row)).is_equal(Vector2i.ZERO)


func test_bytes_decode_like_the_tile_codec() -> void:
	var grid := TileGrid.new()
	grid.set_byte(3, 4, 0x40)                                       # the invisible wall: solid
	grid.set_byte(4, 4, 0x45)                                       # a wall with picture 5
	grid.set_byte(5, 4, 0x80 | (7 << 3) | 4)                        # the strongest current, east
	grid.set_byte(6, 4, 0xC1)                                       # both flags: a wall (as `TileCodec.decode` says)
	assert_bool(grid.is_solid(3, 4)).is_true()
	assert_bool(grid.is_solid(4, 4)).is_true()
	assert_bool(grid.is_solid(5, 4)).is_false()
	assert_that(grid.current_at(5, 4)).is_equal(Vector2i(16, 0))
	assert_bool(grid.is_solid(6, 4)).is_true()
	assert_that(grid.current_at(6, 4)).is_equal(Vector2i.ZERO)
	assert_that(grid.current_at(4, 4)).is_equal(Vector2i.ZERO)


func test_the_edges_are_open_water() -> void:
	var grid := TileGrid.new()
	for cell in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(38, 0), Vector2i(0, 18), Vector2i(-5, 40)]:
		grid.set_byte(cell.x, cell.y, 0x41)                         # (ignored)
		assert_bool(grid.is_solid(cell.x, cell.y)).is_false()
		assert_int(grid.byte_at(cell.x, cell.y)).is_equal(0)
	grid.set_byte(37, 17, 0x41)
	assert_bool(grid.is_solid(37, 17)).is_true()


func test_a_point_belongs_to_the_tile_it_lies_in() -> void:
	var grid := TileGrid.new()
	grid.set_byte(2, 1, 0x41)
	assert_bool(grid.is_solid_at(Vector2(32, 16))).is_true()        # the tile's top-left pixel
	assert_bool(grid.is_solid_at(Vector2(47, 31))).is_true()        # its bottom-right pixel
	assert_bool(grid.is_solid_at(Vector2(48, 16))).is_false()
	assert_bool(grid.is_solid_at(Vector2(31, 16))).is_false()
	assert_bool(grid.is_solid_at(Vector2(32, 32))).is_false()
	grid.set_byte(0, 0, 0x41)
	assert_bool(grid.is_solid_at(Vector2(-0.5, 5))).is_false()      # left of the screen is not tile 0 (rounding towards zero would say so)
	assert_bool(grid.is_solid_at(Vector2(5, -0.5))).is_false()


func test_from_screen_copies_the_bytes() -> void:
	var screen := Ground.main().screens[Ground.CURRENT_SCREEN]
	var before := screen.tiles.duplicate()
	var grid := TileGrid.from_screen(screen)
	grid.clear()
	grid.set_byte(0, 0, 0x41)
	assert_array(screen.tiles).is_equal(before)                     # the shared resource is never touched


func test_without_currents_keeps_only_the_walls() -> void:
	var grid := TileGrid.new()
	grid.set_byte(1, 1, 0x41)
	grid.set_byte(2, 1, 0x80 | 5)
	var dry := grid.without_currents()
	assert_bool(dry.is_solid(1, 1)).is_true()
	assert_that(dry.current_at(2, 1)).is_equal(Vector2i.ZERO)
	assert_that(grid.current_at(2, 1)).is_not_equal(Vector2i.ZERO)  # (the original is unchanged)


func test_every_current_byte_has_the_vector_of_the_design_table() -> void:
	# DESIGN 3.3: direction in bits 0-2 (NW N NE W E SW S SE), magnitude ((byte & 0x38) >> 2) + 2.
	var directions: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
	for direction in 8:
		for strength in 8:
			var byte := 0x80 | (strength << 3) | direction
			assert_that(TileCodec.current_of(byte)).is_equal(directions[direction] * (2 * strength + 2))
			assert_that(TileCodec.decode(byte).current_vector()).is_equal(TileCodec.current_of(byte))
	assert_that(TileCodec.current_of(0)).is_equal(Vector2i.ZERO)
	assert_that(TileCodec.current_of(0x41)).is_equal(Vector2i.ZERO)


# --- the grid against the TileMapLayers, every cell of every screen -------------------------------------------

## What the `Currents` layer says: its custom data `current`, zero where the cell is empty.
static func _layer_current(layer: TileMapLayer, cell: Vector2i) -> Vector2i:
	var data := layer.get_cell_tile_data(cell)
	return Vector2i.ZERO if data == null else Vector2i(data.get_custom_data("current") as Vector2)


func test_the_grid_answers_like_the_layers_for_every_cell_of_every_screen() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	var problems: Array[String] = []
	var solid_cells := 0
	var current_cells := 0
	for sector_index in Catalog.sector_ids():
		world.load_sector(sector_index, 0)
		for screen_index in Catalog.SCREENS_PER_SECTOR:
			world.load_screen(screen_index)
			var grid := world.tile_grid
			for row in TileGrid.ROWS:
				for column in TileGrid.COLUMNS:
					var cell := Vector2i(column, row)
					var wall_in_layer := world.original.walls.get_cell_source_id(cell) != -1
					var current_in_layer := _layer_current(world.original.currents, cell)
					solid_cells += 1 if wall_in_layer else 0
					current_cells += 1 if current_in_layer != Vector2i.ZERO else 0
					if grid.is_solid(column, row) != wall_in_layer:
						problems.append("sector %d screen %d cell %s: the wall layer says %s, the grid %s" % [sector_index, screen_index, cell, wall_in_layer, grid.is_solid(column, row)])
					elif grid.current_at(column, row) != current_in_layer:
						problems.append("sector %d screen %d cell %s: the current layer says %s, the grid %s" % [sector_index, screen_index, cell, current_in_layer, grid.current_at(column, row)])
			if problems.size() > 20:
				break
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()
	assert_int(solid_cells).is_greater(1000)                       # (the comparison looked at real rock and real water currents)
	assert_int(current_cells).is_greater(10)


func test_the_wall_scan_gives_the_same_gaps_with_the_grid_and_with_the_layer() -> void:
	# `SubModel.wall_gap` is the question the sub asks; here it gets both kinds of answer to "is this cell solid".
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	var problems: Array[String] = []
	for sector_index in Catalog.sector_ids():
		world.load_sector(sector_index, 0)
		for screen_index in Catalog.SCREENS_PER_SECTOR:
			world.load_screen(screen_index)
			var grid := world.tile_grid
			var box := Tuning.resolve().sub.wall_box
			var from_grid := func(column: int, row: int) -> bool: return grid.is_solid(column, row)
			var from_layer := func(column: int, row: int) -> bool: return world.original.walls.get_cell_source_id(Vector2i(column, row)) != -1
			for x in range(-30, 640, 38):
				for y in range(0, 340, 27):
					var at := Vector2i(x, y)
					for side in 4:
						var a := SubModel.wall_gap(side, at, from_grid, box)
						var b := SubModel.wall_gap(side, at, from_layer, box)
						if a != b:
							problems.append("sector %d screen %d at %s side %d: grid %d, layer %d" % [sector_index, screen_index, at, side, a, b])
			if problems.size() > 20:
				break
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_the_sub_reads_the_same_current_as_it_did_from_the_layer() -> void:
	# The old `SubModel.read_current`: the `Currents` layer's tile under the point (0, 2) below the sub's centre.
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	var problems: Array[String] = []
	var seen := 0
	for sector_index in Catalog.sector_ids():
		world.load_sector(sector_index, 0)
		world.start_flight()
		for screen_index in Catalog.SCREENS_PER_SECTOR:
			world.load_screen(screen_index)
			if world.original.currents.get_used_cells().is_empty():
				continue
			for x in range(-20, 640, 13):
				for y in range(-10, 310, 11):
					world.sim.sub.position = Vector2(x, y)
					world.original.sub.refresh()                 # (the node follows the model)
					var probe := world.original.sub.global_position + Vector2(world.sim.sub.tuning.current_probe)
					var expected := _layer_current(world.original.currents, world.original.currents.local_to_map(world.original.currents.to_local(probe)))
					seen += 1 if expected != Vector2i.ZERO else 0
					if world.sim.sub.read_current() != expected:
						problems.append("sector %d screen %d sub at %s: layer %s, sub %s" % [sector_index, screen_index, Vector2(x, y), expected, world.sim.sub.read_current()])
		if problems.size() > 20:
			break
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()
	assert_int(seen).is_greater(100)


func test_the_pellet_finds_rock_where_the_layer_did() -> void:
	# The old `InkPellet._touches_rock`: the `Walls` layer's cell under the pellet's centre.
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	var problems: Array[String] = []
	for sector_index in Catalog.sector_ids():
		world.load_sector(sector_index, 0)
		for screen_index in Catalog.SCREENS_PER_SECTOR:
			world.load_screen(screen_index)
			for x in range(-20, 620, 9):
				for y in range(-20, 300, 7):
					var centre := Vector2(x, y) + PelletModel.PICTURE_CENTER
					var expected := world.original.walls.get_cell_source_id(world.original.walls.local_to_map(centre)) != -1
					if world.tile_grid.is_solid_at(centre) != expected:
						problems.append("sector %d screen %d pellet centre %s: layer %s" % [sector_index, screen_index, centre, expected])
		if problems.size() > 20:
			break
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()
