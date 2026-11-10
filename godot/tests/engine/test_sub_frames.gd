class_name TestSubFrames
extends GdUnitTestSuite
## Teaches: testing a state machine that is just lookup tables, and that the tables
## taken from the original binary have the symmetry the sprites need.

var tuning: SubTuning


func before_test() -> void:
	tuning = Tuning.original().sub


func test_tables_have_one_entry_per_cell_and_stay_in_range() -> void:
	assert_int(tuning.cell_pictures.size()).is_equal(18)
	for table in [tuning.cell_after_left, tuning.cell_after_right, tuning.cell_after_down,
			tuning.cell_after_up, tuning.cell_after_level]:
		assert_int(table.size()).is_equal(9)
		for target in table:
			assert_int(target).is_between(0, 8)
	for cell in 9:
		for phase in 2:
			# bundle 15 holds 8 sub pictures (0-7); 8 is the little light, 9-12 are bubbles.
			assert_int(tuning.picture_for(cell, phase)).is_between(0, 7)


func test_pictures_are_mirror_symmetric() -> void:
	# Cell k and cell 8 - k show the same two pictures (propeller phases swapped),
	# one of them mirrored. The front view (cell 4) is its own mirror image.
	for cell in 4:
		var mirror := 8 - cell
		var left := [tuning.picture_for(cell, 0), tuning.picture_for(cell, 1)]
		var right := [tuning.picture_for(mirror, 1), tuning.picture_for(mirror, 0)]
		assert_array(left).is_equal(right)
		assert_bool(SubTuning.is_flipped(cell)).is_true()
		assert_bool(SubTuning.is_flipped(mirror)).is_false()
	assert_int(tuning.picture_for(4, 0)).is_equal(0)
	assert_bool(SubTuning.is_flipped(4)).is_false()


func test_steering_left_turns_the_sub_through_the_front_view() -> void:
	var cell := 6                       # start of a sector: facing right
	var seen: Array[int] = [cell]
	for i in 5:
		cell = tuning.next_cell(cell, -1, 0)
		seen.append(cell)
	assert_array(seen).is_equal([6, 5, 4, 3, 2, 2])
	assert_bool(SubTuning.is_flipped(cell)).is_true()        # now facing left
	# ... and back to the right again.
	for i in 5:
		cell = tuning.next_cell(cell, 1, 0)
	assert_int(cell).is_equal(6)


func test_vertical_steering_tilts_the_nose() -> void:
	assert_int(tuning.next_cell(6, 0, -1)).is_equal(7)       # right, up: nose up
	assert_int(tuning.next_cell(6, 0, 1)).is_equal(8)        # right, down: nose down
	assert_int(tuning.next_cell(7, 0, 0)).is_equal(6)        # no vertical movement: level again
	assert_int(tuning.next_cell(8, 0, 0)).is_equal(6)
	# Left-facing mirror image: cell 1 nose up, cell 0 nose down, both return to level cell 2.
	assert_int(tuning.next_cell(2, 0, -1)).is_equal(1)
	assert_int(tuning.next_cell(2, 0, 1)).is_equal(0)
	assert_int(tuning.next_cell(0, 0, 0)).is_equal(2)
	# The front view never tilts.
	assert_int(tuning.next_cell(4, 0, -1)).is_equal(4)


func test_sub_follows_the_keys_and_the_propeller_turns() -> void:
	GameClock.paused = true
	var runner := scene_runner("res://src/gameplay/sub.tscn")
	var sub := runner.scene() as Sub
	assert_int(sub.model.cell).is_equal(6)
	var pictures: Array[int] = []
	for i in 4:
		sub.model.logic_tick()
		sub.refresh()
		pictures.append(sub.sprite.frame)
	assert_array(pictures).is_equal([3, 2, 3, 2])          # cell 6: pictures 2 / 3 alternate
	for i in 5:
		sub.model.logic_tick(InputSnapshot.steering(-1))            # the left arrow held for 5 ticks
	sub.refresh()
	assert_int(sub.model.cell).is_equal(2)
	assert_bool(sub.sprite.flip_h).is_true()
	GameClock.paused = false


func test_hurt_rectangle_follows_the_frame() -> void:
	GameClock.paused = true
	var sub := scene_runner("res://src/gameplay/sub.tscn").scene() as Sub
	var widths := {}
	for cell in 9:
		sub.model.cell = cell
		sub.model.logic_tick()                # the cell stays: no key, no velocity, level tables keep 4 and 6
		sub.refresh()
		var rect := tuning.frame_rects[sub.model.cell]
		var hurt := sub.model.hurt_rect_window()           # (what the creatures are tested against; the node draws it for the debug view)
		assert_that(hurt.size).is_equal(rect.size)
		widths[sub.model.cell] = hurt.size.x
	assert_int(widths.size()).is_greater(3)                 # the rectangle really changes
	GameClock.paused = false
