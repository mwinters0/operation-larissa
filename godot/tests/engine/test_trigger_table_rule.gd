class_name TestTriggerTableRule
extends GdUnitTestSuite
## The fire rule of a math trigger (`DetectMathTrigger` 0x427744): `MathTriggerTable` (0x442994) indexed by
## `SubCell * 16 + (flags & 15)` decides which axes of the sub's 96 x 58 box are tested (DESIGN 4.1). The rule is the engine's (`TriggerModel`); the
## world tests use the dev test sector 150 (tools/dev_pack/test_sectors/batch_c.py): screen 6 has a nibble-4 trigger at (300, 120), screen 7 two armed
## triggers (slots 22 and 23). That the table is the original's is tests/legacy/test_trigger_table_rule_legacy.gd.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const FAR := Vector2i(0, 0)


func test_nibble_15_tests_both_axes_in_every_cell() -> void:
	var sub := Vector2i(100, 100)
	for cell in 9:
		assert_bool(TriggerModel.fires(0x8F, cell, sub, Vector2i(150, 130))).is_true()
		assert_bool(TriggerModel.fires(0x8F, cell, sub, Vector2i(150, 158))).is_false()    # y = SubY + 58
		assert_bool(TriggerModel.fires(0x8F, cell, sub, Vector2i(196, 130))).is_false()    # x = SubX + 96
		assert_bool(TriggerModel.fires(0x8F, cell, sub, Vector2i(99, 130))).is_false()
		assert_bool(TriggerModel.fires(0x8F, cell, sub, Vector2i(150, 99))).is_false()


func test_the_box_edges_are_inclusive() -> void:
	var sub := Vector2i(100, 100)
	assert_bool(TriggerModel.fires(0x8F, 6, sub, Vector2i(100, 100))).is_true()
	assert_bool(TriggerModel.fires(0x8F, 6, sub, Vector2i(195, 157))).is_true()


func test_nibble_0_fires_wherever_the_sub_is() -> void:
	for cell in 9:
		assert_bool(TriggerModel.fires(0x80, cell, FAR, Vector2i(500, 250))).is_true()


func test_nibble_4_fires_at_once_in_cells_0_to_4_and_tests_x_only_in_5_to_8() -> void:
	var point := Vector2i(300, 200)
	for cell in 5:
		assert_bool(TriggerModel.fires(0x84, cell, FAR, point)).is_true()
	for cell in range(5, 9):
		assert_bool(TriggerModel.fires(0x84, cell, FAR, point)).is_false()
		assert_bool(TriggerModel.fires(0x84, cell, Vector2i(250, 0), point)).is_true()       # y is not tested
		assert_bool(TriggerModel.fires(0x84, cell, Vector2i(205, 0), point)).is_true()       # x = SubX + 95
		assert_bool(TriggerModel.fires(0x84, cell, Vector2i(204, 0), point)).is_false()      # x = SubX + 96


func test_nibble_1_tests_y_only_in_cells_0_and_8() -> void:
	var point := Vector2i(300, 200)
	for cell in 9:
		var in_row := TriggerModel.fires(0x81, cell, Vector2i(0, 150), point)
		var off_row := TriggerModel.fires(0x81, cell, Vector2i(0, 0), point)
		assert_bool(in_row).is_true()
		assert_bool(off_row).is_equal(cell != 0 and cell != 8)     # elsewhere it fires at once


func test_nibble_2_tests_y_only_in_cells_1_and_7() -> void:
	var point := Vector2i(300, 200)
	for cell in 9:
		assert_bool(TriggerModel.fires(0x82, cell, Vector2i(0, 0), point)).is_equal(cell != 1 and cell != 7)
		assert_bool(TriggerModel.fires(0x82, cell, Vector2i(0, 150), point)).is_true()


func test_nibble_8_tests_x_only_in_cells_0_to_3() -> void:
	var point := Vector2i(300, 200)
	for cell in 9:
		assert_bool(TriggerModel.fires(0x88, cell, Vector2i(0, 0), point)).is_equal(cell >= 4)
		assert_bool(TriggerModel.fires(0x88, cell, Vector2i(250, 0), point)).is_true()


func test_nibble_12_tests_x_only() -> void:
	var point := Vector2i(300, 200)
	for cell in 9:
		assert_bool(TriggerModel.fires(0x8C, cell, Vector2i(250, 0), point)).is_true()
		assert_bool(TriggerModel.fires(0x8C, cell, Vector2i(0, 150), point)).is_false()


func test_only_the_low_nibble_matters() -> void:
	assert_bool(TriggerModel.fires(0xAF, 6, Vector2i(100, 100), Vector2i(150, 130))).is_true()
	assert_bool(TriggerModel.fires(0xAF, 6, FAR, Vector2i(150, 130))).is_false()


# --- in the world ---------------------------------------------------------

var _world: SectorWorld
var _pending: Array


const SECTOR := 150
const NIBBLE_4_SCREEN := 6
const TWO_TRIGGERS_SCREEN := 7


func _start_world(sector: int, screen: int) -> void:
	GameClock.paused = true
	GameState.reset()
	_world = scene_runner(WORLD_SCENE).scene() as SectorWorld
	_pending = []
	_world.problem_pending.connect(func(slot: int) -> void: _pending.append(slot))
	_world.load_sector(sector, screen)
	_world.start_flight()
	_world.foes_active = false


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()


func _park(pos: Vector2i, cell: int) -> void:
	_world.original.sub.place_original(pos.x, pos.y, cell)
	_world.tick()


func test_a_nibble_4_trigger_fires_in_the_world_by_the_cell_not_by_the_box() -> void:
	_start_world(SECTOR, NIBBLE_4_SCREEN)
	var trigger := _world.sector.screens[NIBBLE_4_SCREEN].triggers[0]
	assert_int(trigger.flags & 15).is_equal(4)
	# cell 6 (facing right): x is tested, the sub is far to the left of the point
	var far_x := 0 if trigger.pos.x > 200 else 500
	await _park(Vector2i(far_x, 100), 6)
	assert_array(_pending).is_empty()
	assert_bool(_world.is_trigger_armed(NIBBLE_4_SCREEN, 0)).is_true()
	# cell 2 (turned left): the same position fires at once
	await _park(Vector2i(far_x, 100), 2)
	assert_array(_pending).is_equal([trigger.slot])
	assert_bool(_world.is_trigger_armed(NIBBLE_4_SCREEN, 0)).is_false()


func test_a_second_trigger_during_the_countdown_replaces_the_pending_slot_and_restarts_it() -> void:
	# `DoAction` (0x417ffc) calls `DetectMathTrigger` every tick, also while MessageLightCountdown runs: a second hit
	# sets the countdown to 36 again and the problem slot to the new trigger's (the first one stays disarmed and
	# its problem is never shown).
	_start_world(SECTOR, TWO_TRIGGERS_SCREEN)
	var list := _world.sector.screens[TWO_TRIGGERS_SCREEN].triggers
	var requested := []
	_world.problem_requested.connect(func(slot: int) -> void: requested.append(slot))
	_world.sim.touch_trigger(_world.original.triggers_layer.get_child(0).model)
	assert_int(_world.pending_slot).is_equal(list[0].slot)
	for i in 10:
		_world.tick()
	assert_int(_world.pending_ticks).is_equal(Tuning.resolve().pending_ticks - 10)
	_world.sim._detect_math_trigger(list[1].pos)         # the sub box's corner is on trigger 1: it fires in any cell
	assert_array(_pending).is_equal([list[0].slot, list[1].slot])
	assert_int(_world.pending_slot).is_equal(list[1].slot)
	assert_int(_world.pending_ticks).is_equal(Tuning.resolve().pending_ticks)
	assert_bool(_world.is_trigger_armed(TWO_TRIGGERS_SCREEN, 0)).is_false()
	assert_bool(_world.is_trigger_armed(TWO_TRIGGERS_SCREEN, 1)).is_false()
	for i in 40:
		_world.tick()
	assert_array(requested).is_equal([list[1].slot])
