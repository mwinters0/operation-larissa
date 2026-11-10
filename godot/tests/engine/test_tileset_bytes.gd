class_name TestTilesetBytes
extends GdUnitTestSuite
## Teaches: custom data layers on a TileSet (here "tile_byte", the byte the original stores for a tile) and
## testing a generated resource against the decoder that reads the same data (round trip over every cell).

const TILE_BYTE := "tile_byte"


func _source(id: int) -> TileSetAtlasSource:
	return Catalog.tileset().get_source(id) as TileSetAtlasSource


func test_every_zone_cell_decodes_to_its_own_cell() -> void:
	var problems: Array[String] = []
	for zone in 5:
		var source := _source(zone)
		for k in 64:
			var coords := Vector2i(k % TileCodec.ATLAS_COLUMNS, k / TileCodec.ATLAS_COLUMNS)
			var data := source.get_tile_data(coords, 0)
			if data == null:
				problems.append("zone %d cell %d: no tile" % [zone, k])
				continue
			var byte: int = data.get_custom_data(TILE_BYTE)
			var tile := TileCodec.decode(byte)
			if tile.kind != TileCodec.Kind.SOLID or tile.atlas_coords != coords or byte != (0x40 | k):
				problems.append("zone %d cell %d: tile_byte 0x%02x decodes to kind %d at %s" % [zone, k, byte, tile.kind, tile.atlas_coords])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_every_currents_cell_decodes_to_its_own_cell() -> void:
	var source := _source(OriginalPresenter.CURRENTS_SOURCE_ID)
	var problems: Array[String] = []
	for d in 8:
		for s in 8:
			var coords := Vector2i(d, s)
			var byte: int = source.get_tile_data(coords, 0).get_custom_data(TILE_BYTE)
			var tile := TileCodec.decode(byte)
			if tile.kind != TileCodec.Kind.CURRENT or tile.atlas_coords != coords or tile.direction != d or tile.strength != s:
				problems.append("currents (%d, %d): tile_byte 0x%02x decodes to kind %d at %s" % [d, s, byte, tile.kind, tile.atlas_coords])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_currents_keep_their_acceleration_in_custom_data_layer_0() -> void:
	# The sub reads "current"; adding tile_byte must not have moved it.
	var tile_set := Catalog.tileset()
	assert_str(tile_set.get_custom_data_layer_name(0)).is_equal("current")
	assert_int(tile_set.get_custom_data_layer_type(0)).is_equal(TYPE_VECTOR2)
	assert_str(tile_set.get_custom_data_layer_name(1)).is_equal(TILE_BYTE)
	assert_int(tile_set.get_custom_data_layer_type(1)).is_equal(TYPE_INT)
	var data := _source(OriginalPresenter.CURRENTS_SOURCE_ID).get_tile_data(Vector2i(4, 0), 0)  # direction E, strength 0
	assert_that(data.get_custom_data("current")).is_equal(Vector2(2, 0))


func test_invisible_wall_source_is_byte_0x40_with_collision() -> void:
	var source := _source(OriginalPresenter.INVISIBLE_WALL_SOURCE_ID)
	assert_int(source.get_tiles_count()).is_equal(1)
	var data := source.get_tile_data(Vector2i.ZERO, 0)
	var byte: int = data.get_custom_data(TILE_BYTE)
	var tile := TileCodec.decode(byte)
	assert_int(tile.kind).is_equal(TileCodec.Kind.SOLID)
	assert_int(tile.picture).is_equal(0)
	assert_int(data.get_collision_polygons_count(0)).is_equal(1)
	# Same wall square as a zone tile.
	var zone_data := _source(0).get_tile_data(Vector2i.ZERO, 0)
	assert_that(data.get_collision_polygon_points(0, 0)).is_equal(zone_data.get_collision_polygon_points(0, 0))


func test_the_game_does_not_use_the_invisible_wall_source() -> void:
	# SectorWorld draws a 0x40 tile from the zone atlas (cell 0), so a loaded screen never contains source 6.
	var world := scene_runner("res://src/gameplay/sector_world.tscn").scene() as SectorWorld
	world.load_sector(Ground.MAIN)
	var walls: TileMapLayer = world.original.walls
	var solid := 0
	for cell in walls.get_used_cells():
		solid += 1
		assert_int(walls.get_cell_source_id(cell)).is_not_equal(OriginalPresenter.INVISIBLE_WALL_SOURCE_ID)
	assert_int(solid).is_greater(0)
