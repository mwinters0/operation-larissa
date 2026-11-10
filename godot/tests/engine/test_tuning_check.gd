class_name TestTuningCheck
extends GdUnitTestSuite
## Teaches: what a pack may say about the rule values is CHECKED before the game runs on it (`Tuning.check`, on `LayeredJson.walk`, as `Durations.check`
## is). A value the rules cannot run with is an ERROR: a key the project's file does not have, a section where a number belongs, a number that is not whole,
## a table with another length than the rules index (they would crash), a step or limit below its floor. A value that only strains the game is a WARNING:
## a sub faster than a wall is thick, an invulnerability shorter than the blink. Each class of finding is pinned here with a file of one mistake.


## The findings of a layer: `[errors, warnings]`.
func _found(layer: Variant) -> Array:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	Tuning.check(layer, errors, warnings)
	return [errors, warnings]


func _has(messages: Array, fragment: String) -> bool:
	return messages.any(func(m: String) -> bool: return m.contains(fragment))


func _assert_error(layer: Variant, fragment: String) -> void:
	var found := _found(layer)
	assert_bool(_has(found[0], fragment)).override_failure_message("no error about '%s' for %s:\nerrors: %s\nwarnings: %s" % [fragment, JSON.stringify(layer), found[0], found[1]]).is_true()


func _assert_warning(layer: Variant, fragment: String) -> void:
	var found := _found(layer)
	assert_bool(_has(found[1], fragment)).override_failure_message("no warning about '%s' for %s:\nerrors: %s\nwarnings: %s" % [fragment, JSON.stringify(layer), found[0], found[1]]).is_true()
	assert_array(found[0]).override_failure_message("errors for a warning case %s: %s" % [JSON.stringify(layer), found[0]]).is_empty()


func _assert_clean(layer: Variant) -> void:
	var found := _found(layer)
	assert_array(found[0]).override_failure_message("errors: %s" % [found[0]]).is_empty()
	assert_array(found[1]).override_failure_message("warnings: %s" % [found[1]]).is_empty()


# --- what passes -------------------------------------------------------------------------------------------

func test_the_projects_own_file_and_a_note_and_an_empty_layer_pass_clean() -> void:
	_assert_clean(JSON.parse_string(FileAccess.get_file_as_string(Tuning.BASE_PATH)))
	_assert_clean({})
	_assert_clean({"_about": "a note, skipped", "air": {"_why": "more air", "max_oxygen": 4}})


func test_a_layer_of_sensible_values_passes_clean() -> void:
	_assert_clean({
		"sub": {"max_speed_x_units": 160, "accel_units": 16, "decay_units": 3, "tick_hz": 12.5, "invulnerability_ticks": 40, "blink_ticks": 20,
				"wall_box": [8, 10, 70, 30], "light_cells": [0, 1], "ink_step_dx": [-8, 8, 0], "ink_step_dy": [0, 0, 0], "ink_direction": [0, 0, 1, 1, 2, 2, 2, 1, 0],
				"cell_pictures": [7, 6, 5, 4, 3, 2, 1, 1, 0, 0, 1, 1, 2, 3, 4, 5, 6, 7]},
		"air": {"max_oxygen": 4, "max_tanks": 3},
		"ink": {"max": 12, "in_flight_max": 4},
		"sector": {"midpoint_screen": 11, "pending_ticks": 60, "canister_pending_ticks": 1},
		"lock_wheel": {"ticks_per_position": 12, "key_window_ticks": 90, "max_passes": 3},
		"creatures": {"max_instructions_per_tick": 1000},
	})


# --- errors: the file is read wrongly --------------------------------------------------------------------------

func test_a_file_that_is_not_an_object_is_an_error() -> void:
	_assert_error([1, 2], "must be a JSON object")
	_assert_error("fast", "must be a JSON object")


func test_an_unknown_key_is_an_error_at_every_depth() -> void:
	_assert_error({"oxygen": {"max_oxygen": 5}}, "oxygen: no such rule value")
	_assert_error({"air": {"max_oxigen": 5}}, "air.max_oxigen: no such rule value")
	_assert_error({"sub": {"max_speed": 5}}, "sub.max_speed: no such rule value")
	_assert_error({"air": {"max_oxygen": {"x": 1}}}, "air.max_oxygen must be a whole number")


func test_a_section_stays_a_section_and_a_value_a_value() -> void:
	_assert_error({"air": 5}, "air is a section")
	_assert_error({"sub": {"frame_rects": 5}}, "sub.frame_rects must be a list")
	_assert_error({"sub": {"cell_pictures": {"a": 1}}}, "sub.cell_pictures must be a list")
	_assert_error({"ink": {"max": [1, 2]}}, "ink.max must be a whole number")


func test_a_number_is_whole_and_fits_the_rules() -> void:
	_assert_error({"air": {"max_oxygen": 4.5}}, "air.max_oxygen must be a whole number")
	_assert_error({"air": {"max_oxygen": "four"}}, "air.max_oxygen must be a whole number")
	_assert_error({"air": {"max_oxygen": true}}, "air.max_oxygen must be a whole number")
	_assert_error({"sub": {"cell_after_left": [0, 1, 2, 2, 3, 4, 5, 5, 5.5]}}, "sub.cell_after_left must be a whole number")
	_assert_error({"air": {"max_oxygen": 1.0e12}}, "too large")
	_assert_clean({"air": {"max_oxygen": 4.0}})                          # (a JSON 4.0 is a whole number)


func test_tick_hz_is_any_number_above_zero() -> void:
	_assert_error({"sub": {"tick_hz": 0}}, "sub.tick_hz must be a number above 0")
	_assert_error({"sub": {"tick_hz": "fast"}}, "sub.tick_hz must be a number above 0")
	_assert_clean({"sub": {"tick_hz": 20.25}})


# --- errors: the rules index into a table -------------------------------------------------------------------------

func test_a_table_of_another_length_than_the_rules_index_is_an_error() -> void:
	_assert_error({"sub": {"cell_after_left": [0, 1, 2]}}, "sub.cell_after_left has 3 entries, the game's has 9")
	_assert_error({"sub": {"cell_pictures": [0, 1]}}, "sub.cell_pictures has 2 entries, the game's has 18")
	_assert_error({"sub": {"frame_rects": [[0, 0, 10, 10]]}}, "sub.frame_rects has 1 entries, the game's has 9")
	_assert_error({"sub": {"wall_box": [1, 2, 3]}}, "sub.wall_box has 3 entries")
	_assert_error({"sub": {"ink_splash_dx": [0, 1]}}, "sub.ink_splash_dx has 2 entries")
	_assert_error({"sub": {"light_dy_by_cell": []}}, "sub.light_dy_by_cell has 0 entries")


func test_the_lists_whose_length_the_file_decides_are_free() -> void:
	_assert_clean({"sub": {"light_cells": [], "ink_step_dx": [-8, 8], "ink_step_dy": [0, 0], "ink_direction": [0, 1, 1, 1, 1, 1, 1, 1, 0]}})
	_assert_clean({"sub": {"light_cells": [0, 1, 2, 3, 4, 5, 6, 7, 8, 0]}})


func test_every_entry_of_a_cell_table_is_a_cell() -> void:
	_assert_error({"sub": {"cell_after_up": [2, 1, 1, 3, 4, 5, 7, 7, 9]}}, "sub.cell_after_up has the entry 9: a cell is 0 to 8")
	_assert_error({"sub": {"cell_after_level": [-1, 2, 2, 3, 4, 5, 6, 6, 6]}}, "sub.cell_after_level has the entry -1")
	_assert_error({"sub": {"light_cells": [0, 9]}}, "sub.light_cells has the entry 9")


func test_a_picture_is_not_negative_and_a_picture_past_the_sub_is_odd() -> void:
	var pictures := [7, 6, 5, 4, 3, 2, 1, 1, 0, 0, 1, 1, 2, 3, 4, 5, 6, 7]
	pictures[3] = -2
	_assert_error({"sub": {"cell_pictures": pictures}}, "sub.cell_pictures has the entry -2")
	pictures[3] = 10
	_assert_warning({"sub": {"cell_pictures": pictures}}, "sub.cell_pictures has the entry 10")


func test_a_rectangle_is_four_numbers_with_a_size() -> void:
	var rects: Array = Tuning.original().sub.frame_rects.map(func(r: Rect2i) -> Array: return [r.position.x, r.position.y, r.size.x, r.size.y])
	rects[2] = [1, 2, 3]
	_assert_error({"sub": {"frame_rects": rects}}, "sub.frame_rects must hold rectangles")
	rects[2] = [1, 2, 3, 4.5]
	_assert_error({"sub": {"frame_rects": rects}}, "sub.frame_rects must be a whole number")
	rects[2] = [1, 2, 0, 4]
	_assert_error({"sub": {"frame_rects": rects}}, "the rectangle of cell 2 has no size")
	_assert_error({"sub": {"wall_box": [0, 0, 80, 0]}}, "sub.wall_box has no size")
	_assert_error({"sub": {"sprite_size": [0, 54]}}, "sub.sprite_size has no size")


func test_the_ink_tables_agree_with_each_other() -> void:
	_assert_error({"sub": {"ink_step_dx": [-8, 8]}}, "sub.ink_step_dx has 2 entries and sub.ink_step_dy 7")
	_assert_error({"sub": {"ink_step_dx": [-8, 8], "ink_step_dy": [0, 0]}}, "sub.ink_direction names the direction code")   # (codes up to 6 are in the base's table)
	_assert_error({"sub": {"ink_direction": [0, 1, 2, 2, 3, 4, 4, 5, 7]}}, "direction code 7")
	_assert_error({"sub": {"ink_direction": [0, 1, 2, 2, 3, 4, 4, 5, -1]}}, "sub.ink_direction has the entry -1")


# --- errors: a step, a limit, a countdown --------------------------------------------------------------------------

func test_a_value_the_rules_cannot_run_with_is_below_its_floor() -> void:
	for case: Array in [
			[{"sub": {"max_speed_x_units": 0}}, "sub.max_speed_x_units is 0: it must be 1 or more"],
			[{"sub": {"max_speed_y_units": -3}}, "sub.max_speed_y_units is -3"],
			[{"sub": {"accel_units": 0}}, "sub.accel_units is 0: it must be 1 or more"],
			[{"sub": {"decay_units": -1}}, "sub.decay_units is -1: it must be 0 or more"],
			[{"sub": {"invulnerability_ticks": -1}}, "sub.invulnerability_ticks is -1"],
			[{"sub": {"blink_ticks": -1}}, "sub.blink_ticks is -1"],
			[{"sub": {"bubble_ticks": -1}}, "sub.bubble_ticks is -1"],
			[{"sub": {"ink_steps_per_tick": 0}}, "sub.ink_steps_per_tick is 0: it must be 1 or more"],
			[{"air": {"max_oxygen": 0}}, "air.max_oxygen is 0: it must be 1 or more"],
			[{"air": {"max_tanks": -1}}, "air.max_tanks is -1: it must be 0 or more"],
			[{"ink": {"max": -1}}, "ink.max is -1: it must be 0 or more"],
			[{"ink": {"in_flight_max": 0}}, "ink.in_flight_max is 0: it must be 1 or more"],
			[{"sector": {"pending_ticks": 0}}, "sector.pending_ticks is 0: it must be 1 or more"],
			[{"sector": {"canister_pending_ticks": 0}}, "sector.canister_pending_ticks is 0: it must be 1 or more"],
			[{"lock_wheel": {"ticks_per_position": 0}}, "lock_wheel.ticks_per_position is 0: it must be 1 or more"],
			[{"lock_wheel": {"key_window_ticks": 0}}, "lock_wheel.key_window_ticks is 0: it must be 1 or more"],
			[{"lock_wheel": {"max_passes": 0}}, "lock_wheel.max_passes is 0: it must be 1 or more"],
			[{"creatures": {"max_instructions_per_tick": 0}}, "creatures.max_instructions_per_tick is 0: it must be 1 or more"],
	]:
		_assert_error(case[0], case[1])


func test_the_midpoint_screen_is_a_screen_of_the_sector() -> void:
	_assert_error({"sector": {"midpoint_screen": -1}}, "sector.midpoint_screen is -1: it must be 0 or more")
	_assert_error({"sector": {"midpoint_screen": SectorData.SCREEN_COUNT}}, "sector.midpoint_screen is %d: it must be %d or less" % [SectorData.SCREEN_COUNT, SectorData.SCREEN_COUNT - 1])
	_assert_clean({"sector": {"midpoint_screen": 0}})
	_assert_clean({"sector": {"midpoint_screen": SectorData.SCREEN_COUNT - 1}})


# --- warnings: odd, but it plays ---------------------------------------------------------------------------

func test_a_value_that_strains_the_game_is_a_warning() -> void:
	for case: Array in [
			[{"sub": {"max_speed_x_units": 400}}, "sub.max_speed_x_units is 400: more than twice"],
			[{"sub": {"max_speed_y_units": 400}}, "sub.max_speed_y_units is 400: more than twice"],
			[{"sub": {"ink_steps_per_tick": 9}}, "sub.ink_steps_per_tick is 9: more than twice"],
			[{"sub": {"invulnerability_ticks": 5000}}, "sub.invulnerability_ticks is 5000: longer than a minute"],
			[{"air": {"max_oxygen": 6}}, "air.max_oxygen is 6: above the original's"],
			[{"air": {"max_tanks": 9}}, "air.max_tanks is 9: above the original's"],
			[{"ink": {"max": 30}}, "ink.max is 30: above the original's"],
			[{"sector": {"pending_ticks": 5000}}, "sector.pending_ticks is 5000: longer than a minute"],
			[{"sector": {"canister_pending_ticks": 5000}}, "sector.canister_pending_ticks is 5000"],
			[{"lock_wheel": {"ticks_per_position": 100}}, "lock_wheel.ticks_per_position is 100: longer than a second"],
			[{"lock_wheel": {"key_window_ticks": 2000}}, "lock_wheel.key_window_ticks is 2000: longer than ten seconds"],
			[{"lock_wheel": {"max_passes": 11}}, "lock_wheel.max_passes is 11"],
			[{"creatures": {"max_instructions_per_tick": 1000000}}, "creatures.max_instructions_per_tick is 1000000"],
			[{"creatures": {"max_instructions_per_tick": 10}}, "creatures.max_instructions_per_tick is 10: a creature script of ordinary length"],
	]:
		_assert_warning(case[0], case[1])


func test_facts_that_span_several_keys_are_warnings() -> void:
	_assert_warning({"sub": {"invulnerability_ticks": 10}}, "sub.blink_ticks (22) is longer than sub.invulnerability_ticks (10)")
	_assert_warning({"sub": {"invulnerability_ticks": 4, "blink_ticks": 2}}, "sub.bubble_ticks (8) is longer than sub.invulnerability_ticks (4)")
	_assert_warning({"sub": {"invulnerability_ticks": 0, "blink_ticks": 0, "bubble_ticks": 0}}, "sub.invulnerability_ticks is 0")
	_assert_warning({"sub": {"bubble_ticks": 12, "invulnerability_ticks": 40}}, "sub.bubble_ticks is 12: the bubbles have 4 pictures of 2 ticks")
	_assert_warning({"sub": {"accel_units": 200}}, "sub.accel_units (200) is above sub.max_speed_x_units (128)")
	_assert_warning({"sub": {"decay_units": 0}}, "sub.decay_units is 0")
	_assert_warning({"air": {"max_tanks": 1}}, "air.refill_tanks (2) is above air.max_tanks (1)")
	_assert_warning({"ink": {"max": 1}}, "ink.in_flight_max (2) is above ink.max (1)")
	_assert_warning({"ink": {"max": 0}}, "ink.in_flight_max (2) is above ink.max (0)")


func test_a_layer_is_judged_with_the_values_it_lies_over() -> void:
	_assert_clean({"sub": {"invulnerability_ticks": 40, "blink_ticks": 30}})
	_assert_clean({"ink": {"in_flight_max": 3}})
	_assert_warning({"ink": {"in_flight_max": 30}}, "ink.in_flight_max (30) is above ink.max (21)")
