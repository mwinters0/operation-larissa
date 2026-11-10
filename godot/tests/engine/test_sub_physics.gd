class_name TestSubPhysics
extends GdUnitTestSuite
## Teaches: testing a fixed-tick simulation deterministically. The GameClock is
## paused and the test calls `SubModel.logic_tick()` itself, once per simulated game
## tick (82 ms), so the result does not depend on the machine's frame rate.
## `KeyState.press` holds an arrow key like the keyboard would; the keys reach the sub as the `InputSnapshot` of each tick.

const SANDBOX := "res://src/debug/sub_sandbox.tscn"
const EMPTY_ROOM: Array[String] = [
	"......................................", "......................................",
	"......................................", "......................................",
	"......................................", "......................................",
	"......................................", "......................................",
	"......................................", "......................................",
	"......................................", "......................................",
	"......................................", "......................................",
	"......................................", "......................................",
	"......................................", "......................................",
]

var _runner: GdUnitSceneRunner
var _room: SubSandbox
var _sub: SubModel
var _node: Sub
var _keys := KeyState.new()


func before_test() -> void:
	GameClock.paused = true            # no sprite ticks while we step by hand
	_runner = scene_runner(SANDBOX)
	_room = _runner.scene() as SubSandbox
	_node = _room.sub
	_sub = _room.sub.model
	_room.build_room(EMPTY_ROOM)
	_sub.velocity_units = Vector2i.ZERO


func after_test() -> void:
	GameClock.paused = false


## Runs `ticks` game ticks.
func _run(ticks: int) -> void:
	for i in ticks:
		_sub.logic_tick(_keys.snapshot())


func _place(center: Vector2) -> void:
	_sub.position = center
	_sub.velocity_units = Vector2i.ZERO


func test_holding_right_reaches_max_speed_in_the_ticks_the_acceleration_needs_and_holds_it() -> void:
	_place(Vector2(100, 144))
	var tuning := Tuning.resolve().sub
	_keys.press("sub_right")
	var ticks := 0
	while _sub.velocity_units.x < tuning.max_speed_x_units and ticks < 100:
		_sub.logic_tick(_keys.snapshot())
		ticks += 1
	# +accel units per tick: the tick that reaches the limit is the first to hold at least that much (11 ticks of 12 for 128 in the original).
	assert_int(ticks).is_equal(ceili(tuning.max_speed_x_units / float(tuning.accel_units)))
	_run(30)
	assert_int(_sub.velocity_units.x).is_equal(tuning.max_speed_x_units)          # holds the limit, never above
	assert_float(_sub.velocity_px_per_s().x).is_equal_approx(tuning.max_speed_x(), tuning.max_speed_x() * 0.01)
	assert_int(_sub.velocity_units.y).is_equal(0)
	_keys.release("sub_right")


func test_releasing_stops_in_the_ticks_the_decay_needs_without_reversing() -> void:
	var tuning := Tuning.resolve().sub
	_place(Vector2(100, 144))
	_keys.press("sub_right")
	_run(ceili(tuning.max_speed_x_units / float(tuning.accel_units)))
	_keys.release("sub_right")
	var ticks := 0
	while _sub.velocity_units.x > 0 and ticks < 100:
		_sub.logic_tick(_keys.snapshot())
		assert_int(_sub.velocity_units.x).is_greater_equal(0)          # decay never overshoots
		ticks += 1
	assert_int(ticks).is_equal(ceili(tuning.max_speed_x_units / float(tuning.decay_units)))              # the limit, minus decay per tick
	assert_int(_sub.velocity_units.x).is_equal(0)


func test_vertical_limit_is_lower_than_horizontal() -> void:
	_place(Vector2(300, 60))
	var tuning := Tuning.resolve().sub
	_keys.press("sub_down")
	_run(12)
	assert_int(_sub.velocity_units.y).is_equal(tuning.max_speed_y_units)
	assert_float(_sub.velocity_px_per_s().y).is_equal_approx(tuning.max_speed_y(), tuning.max_speed_y() * 0.01)
	_keys.release("sub_down")


func test_diagonal_is_clamped_per_axis() -> void:
	# Like the original, each axis has its own limit (no vector normalising).
	_place(Vector2(200, 60))
	_keys.press("sub_right")
	_keys.press("sub_down")
	_run(12)
	var tuning := Tuning.resolve().sub
	assert_that(_sub.velocity_units).is_equal(Vector2i(tuning.max_speed_x_units, tuning.max_speed_y_units))
	_keys.release("sub_right")
	_keys.release("sub_down")


func test_left_beats_right_when_both_are_held() -> void:
	_place(Vector2(300, 144))
	_keys.press("sub_left")
	_keys.press("sub_right")
	_run(3)
	assert_int(_sub.velocity_units.x).is_less(0)
	_keys.release("sub_left")
	_keys.release("sub_right")


func test_velocity_rule_is_pure_integer_arithmetic() -> void:
	# The rule as a table, straight from DESIGN 3.3 (no key = decay by 6, key = +-12).
	var t := Tuning.resolve().sub
	var top := Vector2i(t.max_speed_x_units, t.max_speed_y_units)
	var a := t.accel_units
	var d := t.decay_units
	assert_that(t.step_velocity(Vector2i(0, 0), Vector2i(1, 0), Vector2i.ZERO)).is_equal(Vector2i(a, 0))
	assert_that(t.step_velocity(Vector2i(top.x - 2, 0), Vector2i(1, 0), Vector2i.ZERO)).is_equal(Vector2i(top.x, 0))
	assert_that(t.step_velocity(Vector2i(d - 2, -(d - 1)), Vector2i.ZERO, Vector2i.ZERO)).is_equal(Vector2i(0, 0))
	assert_that(t.step_velocity(Vector2i(-(d + 4), d + 4), Vector2i.ZERO, Vector2i.ZERO)).is_equal(Vector2i(-4, 4))
	assert_that(t.step_velocity(Vector2i(0, 0), Vector2i.ZERO, Vector2i(2, -2))).is_equal(Vector2i(2, -2))
	# The current is added after the decay, then the limit applies again.
	assert_that(t.step_velocity(Vector2i(top.x, -top.y), Vector2i(1, -1), Vector2i(16, -16))).is_equal(Vector2i(top.x, -top.y))


func test_displacement_is_an_arithmetic_shift() -> void:
	# `>> 3` divides by 8 and rounds DOWN, so small negative velocities still move the sub.
	assert_that(SubTuning.displacement(Vector2i(7, 7))).is_equal(Vector2i(0, 0))
	assert_that(SubTuning.displacement(Vector2i(8, 15))).is_equal(Vector2i(1, 1))
	assert_that(SubTuning.displacement(Vector2i(-1, -8))).is_equal(Vector2i(-1, -1))
	assert_that(SubTuning.displacement(Vector2i(-9, -128))).is_equal(Vector2i(-2, -16))
	assert_that(SubTuning.displacement(Vector2i(128, 96))).is_equal(Vector2i(16, 12))


func test_sub_x_is_always_even() -> void:
	_place(Vector2(100, 144))
	_keys.press("sub_right")
	for i in 20:
		_sub.logic_tick(_keys.snapshot())
		assert_int(int(_sub.position.x) % 2).is_equal(0)
	_keys.release("sub_right")


func test_cannot_enter_a_solid_tile_and_velocity_is_zeroed() -> void:
	var rows := EMPTY_ROOM.duplicate()
	rows[8] = "...............................#......"
	rows[9] = "...............................#......"
	rows[10] = "...............................#......"
	_room.build_room(rows)
	_place(Vector2(300, 144))
	_keys.press("sub_right")
	_run(40)
	# The wall box has the run's width and lies about the sub (80 wide, centred, in the original), the wall starts at x = 31 * 16 = 496.
	var right := Tuning.resolve().sub.wall_box_centered().end.x
	assert_float(_sub.position.x + right).is_less_equal(496.01)
	assert_float(_sub.position.x + right).is_greater(494.0)
	assert_int(_sub.velocity_units.x).is_equal(0)
	_keys.release("sub_right")


func test_invisible_wall_tiles_block_too() -> void:
	var rows := EMPTY_ROOM.duplicate()
	rows[8] = "...............................!......"
	rows[9] = "...............................!......"
	rows[10] = "...............................!......"
	_room.build_room(rows)
	assert_that(_room.walls.get_cell_atlas_coords(Vector2i(31, 9))).is_equal(Vector2i(0, 0))
	_place(Vector2(300, 144))
	_keys.press("sub_right")
	_run(40)
	assert_float(_sub.position.x + Tuning.resolve().sub.wall_box_centered().end.x).is_less_equal(496.01)
	_keys.release("sub_right")


func test_slides_along_a_wall() -> void:
	var rows := EMPTY_ROOM.duplicate()
	for y in range(0, 18):
		rows[y] = "...............................#......"
	_room.build_room(rows)
	_place(Vector2(300, 20))
	_keys.press("sub_right")
	_keys.press("sub_down")
	_run(30)
	# Blocked sideways, but still gliding down along the rock.
	assert_int(_sub.velocity_units.x).is_equal(0)
	assert_int(_sub.velocity_units.y).is_greater(50)
	assert_float(_sub.position.y).is_greater(120.0)
	_keys.release("sub_right")
	_keys.release("sub_down")


func test_floor_stops_the_sub_from_above() -> void:
	var rows := EMPTY_ROOM.duplicate()
	rows[16] = "######################################"
	rows[17] = "######################################"
	_room.build_room(rows)
	_place(Vector2(300, 100))
	_keys.press("sub_down")
	_run(40)
	# Wall box: 32 high, centre of the box is 1 px above the sub's centre.
	var box_bottom := _sub.position.y - 1.0 + 16.0
	assert_float(box_bottom).is_less_equal(256.01)
	assert_float(box_bottom).is_greater(254.0)
	assert_int(_sub.velocity_units.y).is_equal(0)
	_keys.release("sub_down")


func test_wall_box_does_not_change_with_the_frame() -> void:
	# The original tests walls with one fixed box (80 x 32 there); frames only change the hurt rectangle.
	var tuning := Tuning.resolve().sub
	for cell in 9:
		_sub.cell = cell
		_sub.logic_tick(_keys.snapshot())
		_node.refresh()
		assert_that(tuning.wall_box_centered().size).is_equal(Vector2(tuning.wall_box.size))
		assert_that(_sub.hurt_rect_window().size).is_equal(tuning.frame_rects[_sub.cell].size)
