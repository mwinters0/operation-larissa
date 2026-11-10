class_name TestTileCodec
extends GdUnitTestSuite
## Teaches: unit-testing a tiny pure function with a table of (input, expected) cases.


func test_empty() -> void:
	var tile := TileCodec.decode(0)
	assert_int(tile.kind).is_equal(TileCodec.Kind.EMPTY)


func test_invisible_solid_wall() -> void:
	# 0x40 with picture 0: solid, but there is nothing to draw.
	var tile := TileCodec.decode(64)
	assert_int(tile.kind).is_equal(TileCodec.Kind.SOLID)
	assert_int(tile.picture).is_equal(0)
	assert_that(tile.atlas_coords).is_equal(Vector2i(0, 0))


func test_solid_picture() -> void:
	# 113 = 0x40 + 49. Picture 49 sits in the 8-wide atlas at column 1, row 6.
	var tile := TileCodec.decode(113)
	assert_int(tile.kind).is_equal(TileCodec.Kind.SOLID)
	assert_int(tile.picture).is_equal(49)
	assert_that(tile.atlas_coords).is_equal(Vector2i(1, 6))


func test_current() -> void:
	# 129 = 0x80 + direction 1 (north), strength 0.
	var tile := TileCodec.decode(129)
	assert_int(tile.kind).is_equal(TileCodec.Kind.CURRENT)
	assert_int(tile.direction).is_equal(1)
	assert_int(tile.strength).is_equal(0)
	assert_that(tile.atlas_coords).is_equal(Vector2i(1, 0))
	assert_int(tile.magnitude()).is_equal(2)


func test_strongest_current() -> void:
	# 0x80 | (7 << 3) | 7 = south-east, full strength: 16 original units.
	var tile := TileCodec.decode(0x80 | 0x38 | 7)
	assert_int(tile.direction).is_equal(7)
	assert_int(tile.strength).is_equal(7)
	assert_int(tile.magnitude()).is_equal(16)


# --- encode: the inverse of decode, and the TileMapLayer cell helper (screen editor, step 3) ------------------

func test_encode_gives_back_every_canonical_byte() -> void:
	# 129 bytes are what the original uses: 0, 0x40-0x7f (wall, picture 0-63), 0x80-0xbf (current).
	var canonical := 0
	for byte in 256:
		if not TileCodec.is_canonical(byte):
			continue
		canonical += 1
		var tile := TileCodec.decode(byte)
		assert_int(tile.to_byte()).override_failure_message("decode/to_byte of 0x%02x" % byte).is_equal(byte)
		var again := TileCodec.encode(tile.kind, tile.picture if tile.kind == TileCodec.Kind.SOLID else tile.direction, tile.strength)
		assert_int(again).override_failure_message("decode/encode of 0x%02x" % byte).is_equal(byte)
	assert_int(canonical).is_equal(129)


func test_the_other_bytes_are_not_canonical_and_do_not_survive_decoding() -> void:
	# 0x01-0x3f decode as empty (0), 0xc0-0xff as a wall (0x40 | low 6 bits): writing them back changes them.
	for byte in 256:
		if TileCodec.is_canonical(byte):
			continue
		assert_bool(byte != 0 and (byte < 0x40 or byte >= 0xC0)).is_true()
		assert_int(TileCodec.decode(byte).to_byte()).override_failure_message("0x%02x" % byte).is_not_equal(byte)


func test_encode_by_kind() -> void:
	assert_int(TileCodec.encode(TileCodec.Kind.EMPTY)).is_equal(0)
	assert_int(TileCodec.encode(TileCodec.Kind.SOLID, 49)).is_equal(113)
	assert_int(TileCodec.encode(TileCodec.Kind.CURRENT, 1, 0)).is_equal(129)
	assert_int(TileCodec.encode(TileCodec.Kind.CURRENT, 7, 7)).is_equal(0xBF)


func test_a_cell_of_a_zone_atlas_is_wall_plus_picture() -> void:
	for zone_source in 5:
		assert_int(TileCodec.byte_from_cell(zone_source, Vector2i(1, 6))).is_equal(0x40 | 49)
	assert_int(TileCodec.byte_from_cell(0, Vector2i(0, 0))).is_equal(0x40)
	assert_int(TileCodec.byte_from_cell(4, Vector2i(5, 7))).is_equal(0x40 | 61)


func test_a_currents_cell_is_direction_and_strength() -> void:
	assert_int(TileCodec.byte_from_cell(OriginalPresenter.CURRENTS_SOURCE_ID, Vector2i(1, 0))).is_equal(129)
	assert_int(TileCodec.byte_from_cell(OriginalPresenter.CURRENTS_SOURCE_ID, Vector2i(7, 3))).is_equal(0x80 | 3 << 3 | 7)


func test_the_invisible_wall_and_an_empty_cell() -> void:
	assert_int(TileCodec.byte_from_cell(OriginalPresenter.INVISIBLE_WALL_SOURCE_ID, Vector2i.ZERO)).is_equal(0x40)
	assert_int(TileCodec.byte_from_cell(-1, Vector2i(-1, -1))).is_equal(0)


func test_a_cell_that_cannot_be_stored_is_refused_with_a_reason() -> void:
	assert_int(TileCodec.byte_from_cell(9, Vector2i.ZERO)).is_equal(-1)
	assert_str(TileCodec.cell_problem(9, Vector2i.ZERO)).contains("source 9")
	assert_int(TileCodec.byte_from_cell(0, Vector2i(8, 0))).is_equal(-1)
	assert_int(TileCodec.byte_from_cell(OriginalPresenter.CURRENTS_SOURCE_ID, Vector2i(0, 8))).is_equal(-1)
	assert_int(TileCodec.byte_from_cell(OriginalPresenter.INVISIBLE_WALL_SOURCE_ID, Vector2i(1, 0))).is_equal(-1)
	assert_str(TileCodec.cell_problem(0, Vector2i(2, 2))).is_empty()


func test_every_tileset_tile_gives_its_own_tile_byte() -> void:
	# The cell helper and the tile_byte custom data of the tileset (step 1) say the same for every tile.
	var tile_set := Catalog.tileset()
	for source_id in [0, 1, 2, 3, 4, 5, 6]:
		var source := tile_set.get_source(source_id) as TileSetAtlasSource
		for t in source.get_tiles_count():
			var coords := source.get_tile_id(t)
			var stored: int = source.get_tile_data(coords, 0).get_custom_data("tile_byte")
			assert_int(TileCodec.byte_from_cell(source_id, coords)).override_failure_message("source %d cell %s" % [source_id, coords]).is_equal(stored)


func test_the_codec_constants_match_the_sector_world() -> void:
	assert_int(TileCodec.CURRENTS_SOURCE).is_equal(OriginalPresenter.CURRENTS_SOURCE_ID)
	assert_int(TileCodec.INVISIBLE_WALL_SOURCE).is_equal(OriginalPresenter.INVISIBLE_WALL_SOURCE_ID)
