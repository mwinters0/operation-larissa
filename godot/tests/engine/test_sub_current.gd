class_name TestSubCurrent
extends GdUnitTestSuite
## Teaches: filling a TileMapLayer from a test, and checking a physical effect on
## the original's own integer scale (units per tick), which makes exact assertions
## possible. The last four tests are the reason the sub runs on the game tick: they
## pin down how a weak current moves the sub in the original game.

const SANDBOX := "res://src/debug/sub_sandbox.tscn"
const CURRENTS_SOURCE := 5
## Directions in tile order (TileCodec): 0 NW, 1 N, 2 NE, 3 W, 4 E, 5 SW, 6 S, 7 SE.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
const START := Vector2(300, 140)

var _room: SubSandbox
var _sub: SubModel
var _node: Sub


func before_test() -> void:
	GameClock.paused = true
	_room = scene_runner("res://src/debug/sub_sandbox.tscn").scene() as SubSandbox
	_node = _room.sub
	_sub = _room.sub.model
	_room.build_room([])                      # an empty room: no rock, no current (the layers and the grid)
	_sub.position = START
	_sub.velocity_units = Vector2i.ZERO


func after_test() -> void:
	GameClock.paused = false


## Covers the whole room with one kind of current tile. Strength s (0-7) is a push of 2 * s + 2 units.
func _fill_currents(direction: int, strength: int) -> void:
	for y in 18:
		for x in 38:
			_room.tile_grid.set_byte(x, y, TileCodec.encode(TileCodec.Kind.CURRENT, direction, strength))


## Lets the sub drift for `ticks` game ticks with no key pressed, from the start position.
func _drift(ticks: int) -> void:
	_sub.position = START
	_sub.velocity_units = Vector2i.ZERO
	for i in ticks:
		_sub.logic_tick()


func test_current_pushes_in_the_table_direction() -> void:
	for direction in 8:
		_fill_currents(direction, 7)
		_drift(3)
		var expected := DIRECTIONS[direction]
		assert_int(signi(_sub.velocity_units.x)).is_equal(expected.x)
		assert_int(signi(_sub.velocity_units.y)).is_equal(expected.y)


func test_current_magnitude_follows_the_integer_rule() -> void:
	# Strength 7 = 16 units. Tick 1: 0 decays to 0, +16 = 16. After that each tick
	# decays `decay` and adds 16, so n ticks give decay + (16 - decay) * n units (until the limit).
	var tuning := Tuning.resolve().sub
	var decay := tuning.decay_units
	_fill_currents(4, 7)
	for ticks in [1, 4, 9]:
		_drift(ticks)
		var expected: int = decay + (16 - decay) * ticks if ticks > 1 else 16
		assert_int(_sub.velocity_units.x).is_equal(mini(expected, tuning.max_speed_x_units))


func test_stronger_currents_push_harder() -> void:
	var previous := -1
	for strength in 8:
		_fill_currents(4, strength)
		_drift(8)
		assert_int(_sub.velocity_units.x).is_greater(previous)
		previous = _sub.velocity_units.x
	# Strong ones carry the sub at the speed limit.
	_fill_currents(4, 7)
	_drift(20)
	assert_int(_sub.velocity_units.x).is_equal(Tuning.resolve().sub.max_speed_x_units)


func test_no_current_outside_current_tiles() -> void:
	_sub.position = START
	_sub.logic_tick()
	assert_that(_sub.current_units).is_equal(Vector2i.ZERO)


func test_current_is_read_from_the_tile_below_the_centre() -> void:
	# One single tile; the probe is the sub's centre + (0, 2).
	_room.tile_grid.set_byte(18, 8, TileCodec.encode(TileCodec.Kind.CURRENT, 4, 7))   # x 288-304, y 128-144
	_sub.position = Vector2(296, 140)
	_sub.logic_tick()
	assert_that(_sub.current_units).is_equal(Vector2i(16, 0))
	_sub.position = Vector2(296, 142)          # probe at y 144: next tile row, no current
	_sub.logic_tick()
	assert_that(_sub.current_units).is_equal(Vector2i.ZERO)


# --- weak currents: the reason for the tick -------------------------------------
# A "weak" current is one below the decay of 6 units (strengths 0-1: 2 and 4 units).
# With no key held the velocity settles at exactly the current's strength (decay,
# then add). The sub moves `velocity >> 3` whole pixels per tick, which rounds down:
#    +4 units -> 0 px per tick      -4 units -> -1 px per tick
# so weak currents push the sub left and up, and do nothing to the right and down.
# Run at 60 Hz in px/s the sub would drift much less; on the tick it matches.

func test_weak_current_pushes_up_one_pixel_per_tick() -> void:
	_fill_currents(1, 1)                     # north, 4 units
	_drift(61)                               # 61 ticks = 5.01 s
	assert_that(_sub.velocity_units).is_equal(Vector2i(0, -4))
	assert_float(START.y - _sub.position.y).is_equal(61.0)        # 12.17 px/s: the original's rate
	assert_float(_sub.position.x).is_equal(START.x)


func test_weak_current_pushes_left_two_pixels_per_tick_because_x_is_even() -> void:
	_fill_currents(3, 1)                     # west, 4 units: -1 px, and SubX is forced even
	_drift(61)
	assert_that(_sub.velocity_units).is_equal(Vector2i(-4, 0))
	assert_float(START.x - _sub.position.x).is_equal(122.0)       # 2 px per tick = 24.3 px/s


func test_weak_current_does_nothing_to_the_right_or_down() -> void:
	_fill_currents(4, 1)                     # east
	_drift(61)
	assert_that(_sub.velocity_units).is_equal(Vector2i(4, 0))
	assert_that(_sub.position).is_equal(START)
	_fill_currents(6, 1)                     # south
	_drift(61)
	assert_that(_sub.velocity_units).is_equal(Vector2i(0, 4))
	assert_that(_sub.position).is_equal(START)


func test_weak_current_drift_does_not_depend_on_the_frame_rate() -> void:
	# The drift is a function of game ticks only: the same 61 ticks give the same
	# distance whether the monitor ran at 30, 60 or 144 fps. Simulated here with the
	# real GameClock: feed it 5.01 s of frames at three frame rates.
	_fill_currents(1, 1)
	var distances: Array[float] = []
	for fps in [30.0, 60.0, 144.0]:
		_sub.position = START
		_sub.velocity_units = Vector2i.ZERO
		var clock: Node = auto_free(preload("res://src/autoload/game_clock.gd").new())
		clock.tick.connect(func(_count: int) -> void: _sub.logic_tick())
		for frame in roundi(5.0 * fps):
			clock.advance(1.0 / fps)
		distances.append(START.y - _sub.position.y)
	# 5 seconds: 60 or 61 ticks, i.e. 60-61 px at every frame rate.
	for distance in distances:
		assert_float(distance).is_between(60.0, 61.0)
