class_name TestOxygenModel
extends GdUnitTestSuite
## Teaches: testing a rule table row by row (DESIGN 3.4, `UpdateOxygen`).


func _model(tanks: int, oxygen: int) -> OxygenModel:
	var model := OxygenModel.new(Tuning.original())
	model.tanks = tanks
	model.oxygen = oxygen
	return model


func test_new_player_has_two_tanks_and_four_oxygen() -> void:
	var model := OxygenModel.new(Tuning.original())
	assert_int(model.tanks).is_equal(2)
	assert_int(model.oxygen).is_equal(4)


func test_damage_lowers_oxygen_without_a_result() -> void:
	for d in [-1, -2, -3]:
		var model := _model(2, 4)
		assert_int(model.update(d)).is_equal(OxygenModel.OK)
		assert_int(model.oxygen).is_equal(4 + d)
		assert_int(model.tanks).is_equal(2)


func test_running_out_with_spare_tanks_returns_minus_1() -> void:
	for tanks in [2, 3, 6]:
		var model := _model(tanks, 1)
		assert_int(model.update(-1)).is_equal(-1)
		assert_int(model.oxygen).is_equal(0)
		assert_int(model.tanks).is_equal(tanks)        # the tank is spent by the respawn (+4), not here


func test_running_out_with_exactly_one_tank_returns_minus_3() -> void:
	var model := _model(1, 2)
	assert_int(model.update(-2)).is_equal(-3)
	assert_int(model.oxygen).is_equal(0)


func test_running_out_with_no_tank_is_game_over_minus_2() -> void:
	var model := _model(0, 1)
	assert_int(model.update(-4)).is_equal(-2)
	assert_int(model.oxygen).is_equal(0)               # never negative


func test_damage_larger_than_the_oxygen_left_runs_out_exactly_the_same() -> void:
	var model := _model(2, 3)
	assert_int(model.update(-4)).is_equal(-1)
	assert_int(model.oxygen).is_equal(0)


func test_plus_1_refills_oxygen_and_when_full_adds_a_tank() -> void:
	var low := _model(2, 2)
	assert_int(low.update(1)).is_equal(OxygenModel.OK)
	assert_int(low.oxygen).is_equal(4)
	assert_int(low.tanks).is_equal(2)
	var full := _model(2, 4)
	full.update(1)
	assert_int(full.tanks).is_equal(3)


func test_tank_count_is_capped_at_six() -> void:
	var model := _model(6, 4)
	model.update(1)
	assert_int(model.tanks).is_equal(6)


func test_plus_2_guarantees_two_tanks() -> void:
	var poor := _model(0, 2)
	poor.update(2)
	assert_int(poor.tanks).is_equal(2)
	assert_int(poor.oxygen).is_equal(2)                # oxygen untouched
	var rich := _model(5, 2)
	rich.update(2)
	assert_int(rich.tanks).is_equal(5)


func test_plus_3_is_the_supply_station_refill() -> void:
	var model := _model(0, 1)
	model.update(3)
	assert_int(model.tanks).is_equal(2)
	assert_int(model.oxygen).is_equal(4)
	var rich := _model(4, 1)
	rich.update(3)
	assert_int(rich.tanks).is_equal(4)


func test_plus_4_is_the_respawn_that_uses_up_a_tank() -> void:
	var model := _model(3, 0)
	model.update(4)
	assert_int(model.oxygen).is_equal(4)
	assert_int(model.tanks).is_equal(2)
	var last := _model(1, 0)
	last.update(4)
	assert_int(last.tanks).is_equal(0)


func test_which_codes_mean_a_lost_tank() -> void:
	assert_bool(OxygenModel.is_tank_lost(-1)).is_true()
	assert_bool(OxygenModel.is_tank_lost(-3)).is_true()
	assert_bool(OxygenModel.is_tank_lost(-2)).is_false()
	assert_bool(OxygenModel.is_tank_lost(0)).is_false()
