class_name TestSubTuning
extends GdUnitTestSuite
## Unit conversion from the original 1/8 px per tick units (docs/port/DESIGN.md section 3).


func test_derived_constants() -> void:
	var tuning := Tuning.original().sub
	assert_float(tuning.max_speed_x()).is_equal_approx(194.7, 194.7 * 0.005)
	assert_float(tuning.max_speed_y()).is_equal_approx(146.0, 146.0 * 0.005)
	assert_float(tuning.accel()).is_equal_approx(222.0, 222.0 * 0.005)
	assert_float(tuning.decay()).is_equal_approx(111.0, 111.0 * 0.005)
	assert_int(tuning.frame_rects.size()).is_equal(9)
	assert_that(tuning.frame_rects[0]).is_equal(Rect2i(10, 14, 80, 28))
