class_name TileGrid
extends RefCounted
## The walls and the water currents of one screen, as the rules see them: 38 x 18 tile bytes and nothing else.
##
## Teaches: the difference between what the rules need and what the player sees. The `Walls` and `Currents` layers of the
## playfield (`TileMapLayer`) are the VIEW of a screen: they hold pictures and collision shapes. The sub and the ink
## pellets never ask them anything; they ask this grid, which is built from the very bytes the layers are built from
## (`ScreenData.tiles`, decoded by `TileCodec`). That makes the rules plain objects that can run without a scene, and
## `tests/engine/test_tile_grid.gd` proves for all 384 screens that the grid and the layers say the same about every cell.
##
## A cell is addressed like the original addresses it: (column 0-37, row 0-17), tiles of 16 x 16 pixels, row after row in
## the byte array. Everything outside the screen is open water: no wall, no current (the original's scan stops at the
## edge, a `TileMapLayer` answers "empty" there too).

const COLUMNS := 38
const ROWS := 18
const TILE_SIZE := 16
const SIZE := COLUMNS * ROWS
## The playfield in pixels (608 x 288): the one home of the number, which the world, the skin API, the overview and the editors all read.
const PLAYFIELD_SIZE := Vector2i(COLUMNS * TILE_SIZE, ROWS * TILE_SIZE)

var _bytes := PackedByteArray()


func _init() -> void:
	_bytes.resize(SIZE)               # (resize fills with zeros: empty water)


## The grid of a screen of the game's data. The bytes are copied: editing the grid never edits the (shared) resource.
static func from_screen(screen: ScreenData) -> TileGrid:
	return from_bytes(screen.tiles)


## `bytes` must be a whole screen, `SIZE` bytes (the screen editor's validation guarantees it for stored screens).
static func from_bytes(bytes: PackedByteArray) -> TileGrid:
	assert(bytes.size() == SIZE, "a screen has %d tile bytes, got %d" % [SIZE, bytes.size()])
	var grid := TileGrid.new()
	grid._bytes = bytes.duplicate()
	return grid


## A copy of this grid without any current: only the walls stay (a reachability search that ignores the water).
func without_currents() -> TileGrid:
	var copy := TileGrid.new()
	for i in SIZE:
		if _bytes[i] & TileCodec.SOLID_BIT:
			copy._bytes[i] = _bytes[i]
	return copy


static func in_range(column: int, row: int) -> bool:
	return column >= 0 and column < COLUMNS and row >= 0 and row < ROWS


## The tile byte of a cell, 0 (empty water) outside the screen.
func byte_at(column: int, row: int) -> int:
	if not in_range(column, row):
		return 0
	return _bytes[row * COLUMNS + column]


## Sets a cell (tests and tools build their own rooms with it). Out-of-range cells are ignored.
func set_byte(column: int, row: int, byte: int) -> void:
	if in_range(column, row):
		_bytes[row * COLUMNS + column] = byte


## Every cell empty again.
func clear() -> void:
	_bytes.fill(0)


## Is the cell a wall (flag 0x40, the invisible walls with picture 0 included)? This is what `ScanSubWalls` (0x418ea7) and the
## pellet's rock test ask. Same rule as `TileCodec.decode`: a wall flag wins over a current flag.
func is_solid(column: int, row: int) -> bool:
	return byte_at(column, row) & TileCodec.SOLID_BIT != 0


## The water current in a cell, in the original's units (1/8 pixel per tick per tick); zero where there is none. See
## `TileCodec.current_vector`.
func current_at(column: int, row: int) -> Vector2i:
	return TileCodec.current_of(byte_at(column, row))


## The same two questions for a point in playfield pixels (0..607, 0..287; anything else is outside the screen). A point
## belongs to the tile it lies in, tiles being 16 x 16 starting at 0 (`floori`, as `TileMapLayer.local_to_map` does).
func is_solid_at(point: Vector2) -> bool:
	return is_solid(floori(point.x / TILE_SIZE), floori(point.y / TILE_SIZE))


func current_at_point(point: Vector2) -> Vector2i:
	return current_at(floori(point.x / TILE_SIZE), floori(point.y / TILE_SIZE))
