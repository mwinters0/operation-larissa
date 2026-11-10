class_name SubSandbox
extends Control
## Sandbox for the sub: one hand-made room, no sector data needed.
##
## Teaches: building a `TileMapLayer` (the picture) AND a `TileGrid` (what the sub's rules look at) from text (ASCII art ->
## tile bytes), owning the tick of a sub when there is no `SectorWorld` (an `InputReader` hands it its `InputSnapshot`), and
## keeping a debug read-out next to the thing you tune.
##
## Keys:  arrows / WASD  steer      R  back to the start      C  show currents
##        H  show collision boxes
## The room has no neighbours: the sub is held at the borders of the window,
## the same thing the real game does where a screen has no neighbour.

## The room, one string per tile row (38 x 18 tiles of 16 px).
##   #  solid rock           .  empty water       !  invisible wall (tile byte 0x40)
## Water currents (the letters are laid out like a keypad: Q = north-west, W = north,
## E = north-east, A = west, D = east, Z = south-west, X = south, C = south-east):
##   QWEADZXC  strong (strength 7, 16 units)      qweadzxc  gentle (strength 1, 4 units)
const ROOM: Array[String] = [
	"......................................",
	"..QWE.................................",
	"..A.D.........###.............qweadzxc",
	"..ZXC.........###.....................",
	"......................................",
	"......................................",
	"..........................XXXXXXXX....",
	"........................#.............",
	"........................#.............",
	"...........DDDDDDDD.....#.............",
	"........................#.............",
	"........................#.............",
	"..######................#.............",
	"......................................",
	"......................................",
	"......................................",
	"######################################",
	"######################################",
]
## Which picture of zone 0's floor atlas draws '#' (picture 0 would be invisible).
const ROCK_PICTURE := 1
const ZONE_SOURCE_ID := 0
const CURRENTS_SOURCE_ID := 5

@onready var walls: TileMapLayer = %Walls
@onready var currents: TileMapLayer = %Currents
@onready var sub: Sub = %Sub
@onready var info: Label = %InfoLabel

## The walls and currents of the room as the sub's rules see them (`build_room` fills it together with the two layers).
var tile_grid := TileGrid.new()
var _input := InputReader.new()

var _start := Vector2i(150, 200)    # window pixels of the picture's top-left (SubX, SubY)


func _ready() -> void:
	walls.tile_set = Catalog.pack_resource("data/neptune_tileset.tres") as TileSet
	currents.tile_set = walls.tile_set
	build_room(ROOM)
	GameState.reset()                                       # (a run of its own: the sub flies on the chain's rule values)
	sub.bind(SubModel.new(GameState.tuning.sub))            # (this scene owns the model, as `SimWorld` owns the game's)
	sub.model.tile_grid = tile_grid
	sub.model.crossed_edge.connect(sub.model.clamp_to_edge)
	# No `SectorWorld` here, so this scene owns the tick of its sub (in the game the world's `SimWorld` steps it) and takes its input.
	GameClock.tick.connect(func(_count: int) -> void:
		sub.model.logic_tick(_input.take())
		sub.refresh())
	sub.place_original(_start.x, _start.y)


func _process(_delta: float) -> void:
	sub.show_between_ticks(GameClock.tick_fraction())       # (no presenter here: this scene gives the sub its tick fraction itself)
	var model := sub.model
	var speed := model.velocity_px_per_s()
	info.text = "pos (%d, %d)  v %d, %d units (%d, %d px/s)  cell %d  current (%d, %d)" % [
		model.position.x, model.position.y, model.velocity_units.x, model.velocity_units.y,
		speed.x, speed.y, model.cell, model.current_units.x, model.current_units.y]


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_R:
			sub.place_original(_start.x, _start.y)
		KEY_C:
			currents.visible = not currents.visible
		KEY_H:
			sub.debug_draw = not sub.debug_draw
			walls.collision_visibility_mode = (TileMapLayer.DEBUG_VISIBILITY_MODE_FORCE_SHOW
					if sub.debug_draw else TileMapLayer.DEBUG_VISIBILITY_MODE_DEFAULT)


## Fills both tile layers (the picture) and the `tile_grid` (the rules) from `rows` (see ROOM). Public so tests can build their own
## rooms.
func build_room(rows: Array[String]) -> void:
	walls.clear()
	currents.clear()
	tile_grid.clear()
	for y in rows.size():
		for x in rows[y].length():
			var byte := _tile_byte(rows[y][x])
			if byte == 0:
				continue
			tile_grid.set_byte(x, y, byte)
			var tile := TileCodec.decode(byte)
			var cell := Vector2i(x, y)
			if tile.kind == TileCodec.Kind.SOLID:
				walls.set_cell(cell, ZONE_SOURCE_ID, tile.atlas_coords)
			else:
				currents.set_cell(cell, CURRENTS_SOURCE_ID, tile.atlas_coords)


## Letter -> tile byte (see TileCodec for the bit layout).
static func _tile_byte(letter: String) -> int:
	if letter == "#":
		return TileCodec.SOLID_BIT | ROCK_PICTURE
	if letter == "!":
		return TileCodec.SOLID_BIT
	var keypad := "QWEADZXC"                       # index = direction number 0-7
	var strong := keypad.find(letter)
	if strong >= 0:
		return TileCodec.CURRENT_BIT | (7 << 3) | strong
	var gentle := keypad.to_lower().find(letter)
	if gentle >= 0:
		return TileCodec.CURRENT_BIT | (1 << 3) | gentle
	return 0
