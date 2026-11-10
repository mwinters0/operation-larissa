class_name TestTrigger
extends GdUnitTestSuite
## Teaches: testing a countdown that runs on the game clock by calling `tick()` by hand.
## The dev test sector 150 (tools/dev_pack/test_sectors/batch_c.py), screen 5, has one math trigger at window (200, 90) with slot 20 (nibble 1, armed and
## re-armed whenever the screen is entered); screen 6 has one that is not re-armed (slot 21, nibble 4).
## The original's own trigger (sector 0 screen 5, (160, 70), slot 29) is checked by tests/legacy/test_trigger_legacy.gd.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const SECTOR := 150
const AT := Vector2i(200, 90)
const SLOT := 20

var _world: SectorWorld
var _pending: Array
var _requested: Array


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()
	_world = scene_runner(WORLD_SCENE).scene() as SectorWorld
	_pending = []
	_requested = []
	_world.problem_pending.connect(func(slot: int) -> void: _pending.append(slot))
	_world.problem_requested.connect(func(slot: int) -> void: _requested.append(slot))
	_world.load_sector(SECTOR, 5)
	_world.start_flight()
	_world.foes_active = false


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()


func _touch_the_trigger() -> void:
	_world.sim.sub.position = Vector2(AT) - Sub.PLAYFIELD_ORIGIN         # the trigger point is in window pixels
	_world.tick()


func test_the_data_is_what_the_test_assumes() -> void:
	var trigger := _world.sector.screens[5].triggers[0]
	assert_vector(trigger.pos).is_equal(AT)
	assert_int(trigger.slot).is_equal(SLOT)
	assert_int(trigger.flags & 15).is_equal(1)
	assert_bool(trigger.armed).is_true()
	assert_bool(trigger.rearm_on_enter).is_true()


func test_touching_starts_the_blinking_light_and_the_countdown() -> void:
	await _touch_the_trigger()
	assert_array(_pending).is_equal([SLOT])
	assert_bool(_world.sim.sub.message_light).is_true()
	assert_int(_world.pending_ticks).is_equal(Tuning.resolve().pending_ticks)
	assert_array(_requested).is_empty()


func test_this_trigger_fires_wherever_the_sub_is_in_most_cells() -> void:
	# nibble 1 tests y only in cells 0 and 8 and fires at once in the others (`MathTriggerTable`, DESIGN 4.1; the full rule is pinned in
	# test_trigger_table_rule.gd).
	_world.original.sub.place_original(500, 250, 6)
	_world.sim._check_triggers()                              # (the trigger step alone: a whole tick would let the sub change its cell)
	assert_array(_pending).is_equal([SLOT])


func test_in_cell_0_the_same_trigger_wants_the_sub_on_its_row() -> void:
	_world.original.sub.place_original(500, 250, 0)
	_world.sim._check_triggers()
	assert_array(_pending).is_empty()
	_world.original.sub.place_original(500, 40, 0)                 # SubY 40 .. 97 contains the trigger's y = 90
	_world.sim._check_triggers()
	assert_array(_pending).is_equal([SLOT])


func test_the_light_blinks_on_every_other_tick() -> void:
	await _touch_the_trigger()
	var seen := []
	for i in 4:
		_world.sim.sub.logic_tick()
		_world.original.sub.refresh()
		seen.append(_world.original.sub.light.visible)
	assert_bool(seen[0] != seen[1]).is_true()
	assert_bool(seen[0] == seen[2]).is_true()


func test_the_problem_opens_by_itself_when_the_countdown_ends() -> void:
	await _touch_the_trigger()
	for i in Tuning.resolve().pending_ticks - 2:
		_world.tick()
	assert_array(_requested).is_empty()
	_world.tick()                                  # the tick where the counter reaches 1
	assert_array(_requested).is_equal([SLOT])
	assert_bool(_world.sim.sub.message_light).is_false()
	assert_bool(_world.problem_active).is_true()


func test_enter_opens_the_problem_at_once() -> void:
	# (Not through a tick: a hint over the playfield stops the clock, and the Enter that closes it opens the problem too.)
	await _touch_the_trigger()
	_world.tick()
	var enter := InputEventAction.new()
	enter.action = &"show_problem"
	enter.pressed = true
	GameClock.hold()
	_world._unhandled_input(enter)
	GameClock.release()
	assert_array(_requested).is_equal([SLOT])


func test_enter_does_nothing_without_a_waiting_problem() -> void:
	var enter := InputEventAction.new()
	enter.action = &"show_problem"
	enter.pressed = true
	_world._unhandled_input(enter)
	assert_array(_requested).is_empty()


func test_a_used_trigger_is_disarmed() -> void:
	await _touch_the_trigger()
	assert_bool(_world.is_trigger_armed(5, 0)).is_false()
	for i in Tuning.resolve().pending_ticks - 1:
		_world.tick()
	_world.problem_resolved(SLOT, ProblemSession.new(_world.make_problem(SLOT)))
	# the sub is still on the trigger and nothing happens again
	_world.load_screen(5)                                # (this re-arms it, see the next test)
	assert_bool(_world.problem_active).is_false()


func test_a_trigger_with_the_rearm_flag_is_armed_again_on_entering_the_screen() -> void:
	await _touch_the_trigger()
	assert_bool(_world.is_trigger_armed(5, 0)).is_false()
	_world.load_screen(6)
	assert_bool(_world.is_trigger_armed(5, 0)).is_false()          # leaving does not re-arm
	_world.load_screen(5)
	assert_bool(_world.is_trigger_armed(5, 0)).is_true()


func test_a_trigger_without_the_rearm_flag_stays_disarmed() -> void:
	_world.load_screen(6)                                          # screen 6 has one armed trigger without the flag
	var trigger := _world.sector.screens[6].triggers[0]
	assert_bool(trigger.armed).is_true()
	assert_bool(trigger.rearm_on_enter).is_false()
	_world.sim.triggers_on_screen(6)[0].armed = false             # as if it had been used
	_world.load_screen(7)
	_world.load_screen(6)
	assert_bool(_world.is_trigger_armed(6, 0)).is_false()


func test_triggers_ask_for_the_problem_of_the_players_level() -> void:
	for level in 4:
		GameState.edu_level = level
		var problem := _world.make_problem(SLOT)
		assert_int(problem.level).is_equal(level)
		var expected_types := [Catalog.trigger_table().type_for(SLOT, level, 0), Catalog.trigger_table().type_for(SLOT, level, 1)]
		assert_bool(problem.type.id in expected_types).is_true()
	GameState.edu_level = 0


func test_nothing_new_starts_while_a_problem_is_open() -> void:
	await _touch_the_trigger()
	for i in Tuning.resolve().pending_ticks - 1:
		_world.tick()
	_world.load_screen(5)                                           # re-arms the trigger
	_world.tick()
	assert_array(_pending).is_equal([SLOT])                           # still only the first one


## `SimWorld.open_problem` is the entry a waiting problem opens through (`open_pending_problem`), for any slot: the waiting one is
## dropped (no countdown, no beacon, no console light) and the owner is asked for the slot given. While a problem is open it refuses.
func test_open_problem_takes_over_the_waiting_one_and_refuses_while_one_is_open() -> void:
	await _touch_the_trigger()
	assert_int(_world.pending_slot).is_equal(SLOT)
	assert_bool(_world.sim.open_problem(7)).is_true()
	assert_array(_requested).is_equal([7])
	assert_bool(_world.sim.problem_active).is_true()
	assert_int(_world.pending_slot).is_equal(-1)
	assert_int(_world.pending_ticks).is_equal(0)
	assert_bool(_world.sim.sub.message_light).is_false()
	assert_bool(GameState.ship_light or GameState.computer_light).is_false()
	assert_bool(_world.sim.open_problem(8)).is_false()                     # one is open: nothing
	assert_array(_requested).is_equal([7])
	_world.problem_resolved(7, ProblemSession.new(null))
	assert_bool(_world.sim.open_problem(8)).is_true()
	assert_array(_requested).is_equal([7, 8])
