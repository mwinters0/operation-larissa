class_name TestTileset
extends GdUnitTestSuite
## The shared TileSet: five zone atlases, the currents atlas, the editor-only invisible wall, physics and custom data.
## (The tile_byte layer and the source names are in test_tileset_bytes.gd.)


func test_sources() -> void:
	var tile_set := Catalog.tileset()
	assert_int(tile_set.get_source_count()).is_equal(7)
	assert_vector(Vector2(tile_set.tile_size)).is_equal(Vector2(16, 16))
	for source_id in 7:
		assert_bool(tile_set.get_source(source_id) is TileSetAtlasSource).is_true()


func test_zone_tile_has_collision() -> void:
	var tile_set := Catalog.tileset()
	assert_int(tile_set.get_physics_layers_count()).is_equal(1)
	for source_id in 5:
		var source := tile_set.get_source(source_id) as TileSetAtlasSource
		assert_int(source.get_tiles_count()).is_equal(64)
		# Even the empty cell 0 collides: tile byte 0x40 + index 0 is an invisible wall.
		var data := source.get_tile_data(Vector2i(0, 0), 0)
		assert_int(data.get_collision_polygons_count(0)).is_equal(1)
		assert_int(data.get_collision_polygon_points(0, 0).size()).is_equal(4)


func test_current_custom_data() -> void:
	var tile_set := Catalog.tileset()
	assert_int(tile_set.get_custom_data_layer_by_name("current")).is_greater_equal(0)
	var currents := tile_set.get_source(5) as TileSetAtlasSource
	assert_int(currents.get_tiles_count()).is_equal(64)
	# Direction 4 = east, strength 3: magnitude (3 * 2) + 2 = 8, pushing right.
	var east: Vector2 = currents.get_tile_data(Vector2i(4, 3), 0).get_custom_data("current")
	assert_vector(east).is_equal(Vector2(8, 0))
	# Direction 0 = north-west, weakest: (-2, -2).
	var north_west: Vector2 = currents.get_tile_data(Vector2i(0, 0), 0).get_custom_data("current")
	assert_vector(north_west).is_equal(Vector2(-2, -2))
	# Current tiles have no collision.
	assert_int(currents.get_tile_data(Vector2i(4, 3), 0).get_collision_polygons_count(0)).is_equal(0)
