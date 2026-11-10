@tool
class_name TileCodec
extends RefCounted
## Decodes and encodes one tile byte of a screen's 38 x 18 tile map (DESIGN 4.1).
##
## Teaches: bit masks and shifts, `enum`, a "factory" static function that
## returns an instance of its own class, and writing the inverse of a decoder
## (`encode`) so the pair can be tested as a round trip. Keeping this tiny piece of
## logic out of the scene code makes it trivial to unit test.
##
## Byte layout:
##   0x00        empty water
##   0x40 | p    solid wall, drawn with picture p (0-63) of the zone's floor tiles.
##               Picture 0 has no art: an invisible wall (docs/port/ASSET_FORMATS.md).
##   0x80 | s<<3 | d   water current: direction d (bits 0-2), strength s (bits 3-5).
##               Not drawn in the real game; we show arrows only in debug mode.
##
## The tileset (data/neptune_tileset.tres) stores this same byte on every tile as the custom data
## layer `tile_byte`, so selecting a tile in the TileSet panel shows what the original stores:
## 0x40 | k for cell k of a zone atlas, 0x80 | s<<3 | d for currents cell (d, s). Source 6 of
## the tileset is a hatched "invisible wall" with `tile_byte` 0x40; only the screen editor uses
## it (see OriginalPresenter.INVISIBLE_WALL_SOURCE_ID). `decode` of a tile's `tile_byte` gives back
## that tile's own atlas coordinates (tests/engine/test_tileset_bytes.gd).
##
## `encode` is the inverse of `decode` for the 129 canonical bytes (0, 0x40-0x7F, 0x80-0xBF); the original data
## uses nothing else. A byte such as 0xC0 (both flag bits) decodes as a solid wall and cannot be written back as
## it was, so `is_canonical` tells the validation of `ScreenData` to refuse it. `byte_from_cell` is the same
## step for the screen editor: a TileMapLayer cell (tileset source id and atlas coordinates) -> the byte to store.

enum Kind { EMPTY, SOLID, CURRENT }

const SOLID_BIT := 0x40
const CURRENT_BIT := 0x80
## The floor atlases are 8 cells wide (cell k is at column k % 8, row k / 8).
const ATLAS_COLUMNS := 8

var kind: Kind = Kind.EMPTY
## Cell of the atlas to draw: the floor picture for SOLID, (direction, strength)
## for CURRENT. (0, 0) for EMPTY.
var atlas_coords: Vector2i = Vector2i.ZERO
## SOLID only: picture index 0-63 (0 = invisible wall).
var picture: int = 0
## CURRENT only: 0 NW, 1 N, 2 NE, 3 W, 4 E, 5 SW, 6 S, 7 SE.
var direction: int = 0
## CURRENT only: 0-7.
var strength: int = 0


## The eight directions of a current tile, in the order of bits 0-2: NW, N, NE, W, E, SW, S, SE (DESIGN 3.3). Screen
## coordinates, so north is -y.
const CURRENT_DIRECTIONS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]


## Magnitude of a current in original units, 2 (weakest) to 16 (DESIGN 3.3).
## Only meaningful when `kind == Kind.CURRENT`.
func magnitude() -> int:
	return (strength << 1) + 2


## What this current tile adds to the sub's velocity each tick, in the original's units (1/8 pixel per tick per tick):
## the direction times the magnitude. Zero for any other kind. This is the number the tileset stores as the custom data
## `current` of every current tile (`tests/engine/test_tile_grid.gd` compares the two).
func current_vector() -> Vector2i:
	return current_of(to_byte()) if kind == Kind.CURRENT else Vector2i.ZERO


## The current of a tile BYTE, without making an object: zero unless it is a current tile (a wall flag wins over a current flag,
## as in `decode`).
static func current_of(byte: int) -> Vector2i:
	if byte & SOLID_BIT or not byte & CURRENT_BIT:
		return Vector2i.ZERO
	return CURRENT_DIRECTIONS[byte & 0x07] * (((byte & 0x38) >> 2) + 2)


static func decode(byte: int) -> TileCodec:
	var tile := TileCodec.new()
	if byte & SOLID_BIT:
		tile.kind = Kind.SOLID
		tile.picture = byte & 0x3F
		tile.atlas_coords = Vector2i(tile.picture % ATLAS_COLUMNS, floori(tile.picture / float(ATLAS_COLUMNS)))
	elif byte & CURRENT_BIT:
		tile.kind = Kind.CURRENT
		tile.direction = byte & 0x07
		tile.strength = (byte & 0x38) >> 3
		tile.atlas_coords = Vector2i(tile.direction, tile.strength)
	return tile


## True when `byte` is one of the encodings the original uses, i.e. `encode(decode(byte)) == byte`.
static func is_canonical(byte: int) -> bool:
	if byte < 0 or byte > 0xFF:
		return false
	return byte == 0 or (byte & 0xC0) == SOLID_BIT or (byte & 0xC0) == CURRENT_BIT


## The inverse of `decode`. For SOLID `first` is the picture (0-63), for CURRENT it is the direction (0-7) and
## `second` the strength (0-7); EMPTY ignores both. Values outside their range are cut to the bits the byte has
## room for (the same bits `decode` would read back), so the result is always a canonical byte.
static func encode(tile_kind: Kind, first: int = 0, second: int = 0) -> int:
	match tile_kind:
		Kind.SOLID:
			return SOLID_BIT | (first & 0x3F)
		Kind.CURRENT:
			return CURRENT_BIT | ((second & 0x07) << 3) | (first & 0x07)
		_:
			return 0


## This decoded tile as a byte again.
func to_byte() -> int:
	return TileCodec.encode(kind, picture if kind == Kind.SOLID else direction, strength)


## Zone atlas sources 0-4 of the tileset are the floor pictures (see `OriginalPresenter`); source 5 the current arrows;
## source 6 the editor-only hatched invisible wall. These mirror OriginalPresenter's constants, which cannot be used
## from here without making this tiny class depend on a scene script.
const ZONE_SOURCE_COUNT := 5
const CURRENTS_SOURCE := 5
const INVISIBLE_WALL_SOURCE := 6


## Why a TileMapLayer cell cannot be stored as a tile byte, or "" when it can. `source_id` -1 is an empty cell.
## Zone sources 0-4 hold wall pictures (cell k = picture k), source 5 the currents (column = direction, row =
## strength), source 6 the invisible wall. The sector's own zone decides which of 0-4 the editor offers; here
## any of them is encodable, because the byte only stores the picture number.
static func cell_problem(source_id: int, atlas_coords: Vector2i) -> String:
	if source_id == -1:
		return ""
	if source_id >= 0 and source_id < ZONE_SOURCE_COUNT:
		var picture := atlas_coords.y * ATLAS_COLUMNS + atlas_coords.x
		if atlas_coords.x < 0 or atlas_coords.x >= ATLAS_COLUMNS or atlas_coords.y < 0 or picture > 63:
			return "cell %s is outside the 8 x 8 picture atlas of zone source %d" % [atlas_coords, source_id]
		return ""
	if source_id == CURRENTS_SOURCE:
		if atlas_coords.x < 0 or atlas_coords.x > 7 or atlas_coords.y < 0 or atlas_coords.y > 7:
			return "cell %s is not a current arrow (columns 0-7 are the direction, rows 0-7 the strength)" % atlas_coords
		return ""
	if source_id == INVISIBLE_WALL_SOURCE:
		return "" if atlas_coords == Vector2i.ZERO else "cell %s is not the invisible wall tile (0, 0)" % atlas_coords
	return "tileset source %d is not one of the tile atlases the original data can store (0-4 zone pictures, 5 currents, 6 invisible wall)" % source_id


## The tile byte for a TileMapLayer cell, or -1 when `cell_problem` says it cannot be stored.
## Empty cell -> 0; zone source k -> 0x40 | picture; currents -> 0x80 | strength << 3 | direction;
## invisible wall -> 0x40.
static func byte_from_cell(source_id: int, atlas_coords: Vector2i) -> int:
	if not cell_problem(source_id, atlas_coords).is_empty():
		return -1
	if source_id == -1:
		return 0
	if source_id == CURRENTS_SOURCE:
		return encode(Kind.CURRENT, atlas_coords.x, atlas_coords.y)
	if source_id == INVISIBLE_WALL_SOURCE:
		return SOLID_BIT
	return encode(Kind.SOLID, atlas_coords.y * ATLAS_COLUMNS + atlas_coords.x)
