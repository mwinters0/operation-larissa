class_name TestDiagramAnimationsLegacy
extends GdUnitTestSuite
## The ORIGINAL's build-up and replay animations, type by type (the numbers the decompiled `Prob*_Diagram` functions use). The mechanics of timelines are tests/engine/test_diagram_animations.gd.
## Teaches: testing an ANIMATION without waiting for it. A diagram describes its build-up (and the replay after a right
## answer) as a `DiagramTimeline`: steps with a tick, a sound and the picture that shows from then on. Most tests below read that
## list, for every stored problem of a type, against the numbers the decompiled `Prob*_Diagram` functions use (ticks are the
## original's 1/73 s). A few play a short timeline for real to check that the Tween keeps the schedule.

const TYPES_WITH_INTRO: Array[int] = [2, 4, 5, 7, 12, 13, 14, 17, 20, 21, 25, 30, 32, 33]
const TYPES_WITH_REPLAY: Array[int] = [6, 11, 12, 16, 22, 23, 26, 27]
const TYPES_WITHOUT_ANIMATION: Array[int] = [0, 1, 8, 9, 10, 15, 18, 19, 24, 28, 29, 31]


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func _diagram(type_id: int, level: int, index: int) -> DiagramBase:
	var problem := ProblemInstance.build(Catalog.problem_type(type_id), level, index, 0)
	return auto_free(DiagramFactory.create(problem)) as DiagramBase


## The diagram of the first stored record of the type (its lowest level that has one).
func _first(type_id: int) -> DiagramBase:
	var type := Catalog.problem_type(type_id)
	for level in 4:
		if type.record_count(level) > 0:
			return _diagram(type_id, level, 0)
	return null


## Calls `check` with the diagram of every stored record of the type; returns how many there are.
func _for_every_record(type_id: int, check: Callable) -> int:
	var type := Catalog.problem_type(type_id)
	var count := 0
	for level in 4:
		for index in type.record_count(level):
			check.call(_diagram(type_id, level, index), level)
			count += 1
	return count


## [[tick, sfx], ...] for a sound at every multiple of `every` ticks, `count` times.
static func _every(every: int, count: int, sfx: int) -> Array:
	var expected := []
	for i in count:
		expected.append([i * every, sfx])
	return expected


static func _ceil_div(value: int, divisor: int) -> int:
	@warning_ignore("integer_division")
	return maxi(0, (value + divisor - 1) / divisor)


## How many of the timeline's pictures show picture number `pic`.
static func _count_pictures(items: Array[DiagramItem], pic: int) -> int:
	var found := 0
	for item in items:
		if item.kind == DiagramItem.Kind.PICTURE and item.pic == pic:
			found += 1
	return found


# --- all types -----------------------------------------------------------------------------

func test_only_the_types_the_original_animates_have_a_timeline() -> void:
	for type_id in TYPES_WITHOUT_ANIMATION:
		var diagram := _first(type_id)
		assert_bool(diagram.intro.is_empty()).override_failure_message("type %d has an intro" % type_id).is_true()
		assert_bool(diagram.has_success_replay()).override_failure_message("type %d has a replay" % type_id).is_false()
	for type_id in TYPES_WITH_INTRO:
		var diagram := _first(type_id)
		assert_bool(diagram.has_intro()).override_failure_message("type %d has no intro" % type_id).is_true()
	for type_id in TYPES_WITH_REPLAY:
		assert_bool(_first(type_id).has_success_replay()).override_failure_message("type %d has no replay" % type_id).is_true()
	# `ShowSuccessMessage` (0x4272f1) calls the replay for exactly these types
	assert_array(TYPES_WITH_REPLAY).is_equal(ProblemScreen.SUCCESS_REPLAY_TYPES)
	# the radar (type 3) runs its own sweep, see test_sfx_events
	assert_bool(_first(3).has_intro()).is_true()


func test_the_sound_catalog_agrees_with_the_first_sound_of_each_intro() -> void:
	var catalog := Catalog.sfx_catalog()
	for type_id in Catalog.PROBLEM_TYPE_COUNT:
		var diagram := _first(type_id)
		if diagram == null or type_id == 3:                                    # (the radar has its own sweep, see test_sfx_events)
			continue
		var sounds := diagram.intro.sounds()
		var expected: int = sounds[0][1] if not sounds.is_empty() else -1
		assert_int(catalog.diagram_cue(type_id)).override_failure_message("type %d" % type_id).is_equal(expected)


func test_every_intro_ends_in_the_picture_the_static_diagram_shows() -> void:
	var checked := 0
	for type_id in TYPES_WITH_INTRO:
		checked += _for_every_record(type_id, func(diagram: DiagramBase, _level: int) -> void:
			var steps := diagram.intro.steps
			assert_array(steps).is_not_empty()
			assert_int(steps[0].tick).is_equal(0)
			assert_array(steps.back().items).is_equal(diagram.items)           # same items, same drawing order
			var previous_count := 0
			var previous_tick := 0
			for step in steps:
				assert_int(step.tick).is_greater_equal(previous_tick)         # in time order
				assert_int(step.items.size()).is_greater_equal(previous_count) # items only come, none go
				previous_tick = step.tick
				previous_count = step.items.size()
			assert_int(diagram.intro.end_tick).is_greater_equal(previous_tick))
	assert_int(checked).is_equal(381)


func test_a_diagram_is_not_drawn_in_part_until_an_animation_runs() -> void:
	var diagram := _diagram(17, 1, 0)
	assert_array(diagram._shown).is_equal(diagram.items)                # a fresh diagram shows the end state
	assert_bool(diagram.is_playing()).is_false()


# --- the build-up animations, type by type ---------------------------------------------------

func test_type_2_speed_bars_one_segment_per_6_ticks_and_30_ticks_between_bars() -> void:
	var count := _for_every_record(2, func(diagram: DiagramBase, _level: int) -> void:
		var expected := []
		var tick := 0
		for bar in 6:
			@warning_ignore("integer_division")
			var segments := diagram.record.int_at(bar) / 5
			for _s in segments:
				expected.append([tick, 0x22])
				tick += 6
			if bar < 5:
				tick += 30                                                # DelayTicks(30), also after an empty bar
		assert_array(diagram.intro.sounds()).is_equal(expected)
		assert_int(diagram.intro.end_tick).is_equal(tick)
		# each sound step adds exactly one segment (the panel is there from the start)
		var sound_steps := diagram.intro.steps.filter(func(step: DiagramStep) -> bool: return step.sfx >= 0)
		for i in sound_steps.size():
			assert_int(sound_steps[i].items.size()).is_equal(2 + i))
	assert_int(count).is_greater(0)


func test_type_4_and_5_four_and_six_pieces_every_15_ticks() -> void:
	for pair: Array in [[4, 4], [5, 6]]:
		var pieces: int = pair[1]
		_for_every_record(pair[0], func(diagram: DiagramBase, _level: int) -> void:
			assert_array(diagram.intro.sounds()).is_equal(_every(15, pieces, 0x23))
			assert_int(diagram.intro.end_tick).is_equal(15 * pieces)      # set_alarm(0, 15) ... wait_alarm(0) after the last piece too
			assert_int(diagram.intro.steps[0].items.size()).is_equal(2)   # the panel appears together with the first piece
			assert_int(diagram.intro.steps.size()).is_equal(pieces))


func test_type_7_four_values_one_by_one_30_ticks_apart() -> void:
	_for_every_record(7, func(diagram: DiagramBase, _level: int) -> void:
		assert_array(diagram.intro.sounds()).is_equal(_every(30, 5, 0x22))
		assert_int(diagram.intro.end_tick).is_equal(120)                  # nothing is waited for after the last value
		assert_int(diagram.intro.steps[0].items.size()).is_equal(3)       # panel, unit picture, first value
		assert_int(diagram.texts().size()).is_equal(5))
	# the first step shows only the first value
	var first := _first(7).intro.steps[0]
	var shown := PackedStringArray()
	for item in first.items:
		if item.kind == DiagramItem.Kind.TEXT:
			shown.append(item.text)
	assert_int(shown.size()).is_equal(1)


func test_type_12_and_13_thermometer_30_ticks_then_mercury_10_ticks_a_piece_then_60_ticks() -> void:
	for type_id in [12, 13]:
		_for_every_record(type_id, func(diagram: DiagramBase, _level: int) -> void:
			var pieces := _count_pictures(diagram.items, 3)
			assert_int(pieces).is_greater(0)
			assert_array(diagram.intro.sounds()).is_equal([[30, 0x25]])          # RepeatCommonSoundEffect(0x25) once
			assert_array(Array(diagram.intro.stops())).is_equal([30 + 10 * pieces])    # StopCommonSoundEffect when the column is up
			assert_int(diagram.intro.end_tick).is_equal(30 + 10 * pieces + 60)
			assert_int(_count_pictures(diagram.intro.steps[0].items, 3)).is_equal(0)  # the tube starts empty
			var last_piece := diagram.intro.steps[pieces]                        # step 0 = empty tube, then one step per piece
			assert_int(last_piece.tick).is_equal(30 + 10 * (pieces - 1))
			assert_int(_count_pictures(last_piece.items, 3)).is_equal(pieces))
	# type 12 level 0 record 0: 5 pieces = (f0 + 15) / 5 + 1
	var diagram := _first(12)
	@warning_ignore("integer_division")
	assert_int(_count_pictures(diagram.items, 3)).is_equal((diagram.record.int_at(0) + 15) / 5 + 1)


func test_type_14_barnacles_a_burst_of_sounds_at_the_start_of_each_of_three_rounds() -> void:
	var count := _for_every_record(14, func(diagram: DiagramBase, _level: int) -> void:
		var barnacles := diagram as BarnacleDiagram
		assert_array(diagram.intro.sounds()).is_equal(_every(70, 3, 0x24))
		assert_int(diagram.intro.end_tick).is_equal(3 * 70 + 20)         # + the 20 ticks of do_ccmonitor_opening before the prompt
		assert_int(diagram.intro.steps.size()).is_equal(6)
		assert_int(diagram.intro.steps[0].sfx_calls).is_equal(barnacles.healthy_count())   # one PlaySoundEffect per healthy barnacle ...
		assert_int(diagram.intro.steps[1].tick).is_equal(30)             # ... DelayTicks(30), swap, DelayTicks(40)
		# the two pictures swap between the 30 tick and the 40 tick half of a round
		assert_int(_count_pictures(diagram.intro.steps[0].items, 4)).is_equal(_count_pictures(diagram.intro.steps[1].items, 5))
		assert_int(_count_pictures(diagram.intro.steps[0].items, 5)).is_equal(_count_pictures(diagram.intro.steps[1].items, 4)))
	assert_int(count).is_equal(29)


func test_type_17_pie_the_slices_come_every_88_ticks() -> void:
	var count := _for_every_record(17, func(diagram: DiagramBase, level: int) -> void:
		assert_array(diagram.intro.sounds()).is_equal(_every(88, 3, 0x29))
		assert_int(diagram.intro.end_tick).is_equal(3 * 88)               # DelayTicks(88) after the last slice as well
		# the panel and the legend are there from the start, each step adds one slice
		assert_int(diagram.intro.steps[0].items.size()).is_equal(diagram.items.size() - 2)
		assert_int(diagram.intro.steps.size()).is_equal(3))
	assert_int(count).is_equal(10)


func test_type_20_a_slice_per_100_units_every_10_ticks() -> void:
	_for_every_record(20, func(diagram: DiagramBase, _level: int) -> void:
		var left := _ceil_div(diagram.record.int_at(1), 100)
		var right := _ceil_div(diagram.record.int_at(0), 100)
		var passes := maxi(left, right)
		assert_array(diagram.intro.sounds()).is_equal(_every(10, passes, 0x22))
		assert_int(diagram.intro.end_tick).is_equal(10 * passes)
		for i in passes:
			assert_int(diagram.intro.steps[i].items.size()).is_equal(1 + mini(i + 1, left) + mini(i + 1, right)))


func test_type_21_tank_the_sound_runs_while_the_level_rises_6_ticks_a_frame() -> void:
	var count := _for_every_record(21, func(diagram: DiagramBase, _level: int) -> void:
		var tank := diagram as TankDiagram
		var frames := tank.water_frames(tank.supply()["amount"])
		assert_array(diagram.intro.sounds()).is_equal([[0, 0x28]])
		assert_array(Array(diagram.intro.stops())).is_equal([6 * frames])           # StopCommonSoundEffect, then the label
		assert_int(diagram.intro.end_tick).is_equal(6 * frames)
		assert_array(diagram.intro.steps.back().items).is_equal(diagram.items)
		assert_int(diagram.intro.steps.back().items.size()).is_equal(diagram.intro.steps[diagram.intro.steps.size() - 2].items.size() + 1)  # only the label is new
		if frames > 0:
			assert_int(diagram.intro.steps[frames - 1].tick).is_equal(6 * (frames - 1)))
	assert_int(count).is_greater(0)


func test_type_25_toxicity_graph_seven_readings_15_ticks_apart() -> void:
	var count := _for_every_record(25, func(diagram: DiagramBase, _level: int) -> void:
		assert_array(diagram.intro.sounds()).is_equal(_every(15, 7, 0x23))
		assert_int(diagram.intro.end_tick).is_equal(90)                    # the last reading has no delay after it
		assert_int(diagram.intro.steps[0].items.size()).is_equal(3)        # panel, flat line, first dot
		for i in 7:
			assert_int(diagram.intro.steps[i].items.size()).is_equal(3 + 2 * i))
	assert_int(count).is_greater(0)


func test_type_30_storage_boxes_one_box_every_15_ticks() -> void:
	var count := _for_every_record(30, func(diagram: DiagramBase, _level: int) -> void:
		var r := diagram.record
		var boxes := r.int_at(0) * r.int_at(1) * r.int_at(2) + r.int_at(9)
		assert_array(diagram.intro.sounds()).is_equal(_every(15, boxes, 0x29))
		assert_int(diagram.intro.end_tick).is_equal(15 * boxes)
		for i in boxes:
			assert_int(diagram.intro.steps[i].items.size()).is_equal(1 + 2 * (i + 1)))   # panel + (box, compartment front) per box
	assert_int(count).is_greater(0)


func test_type_32_and_33_search_grid_one_square_every_2_ticks() -> void:
	for type_id in [32, 33]:
		_for_every_record(type_id, func(diagram: DiagramBase, _level: int) -> void:
			var shaded := diagram.record.int_at(0)
			assert_array(diagram.intro.sounds()).is_equal(_every(2, shaded, 0x29))
			assert_int(diagram.intro.end_tick).is_equal(2 * shaded)
			assert_int(diagram.intro.steps.size()).is_equal(maxi(shaded, 1) if shaded > 0 else 1))


# --- the success replays ------------------------------------------------------------------------

func test_type_6_and_11_write_the_answer_onto_the_diagram_without_sound() -> void:
	for pair: Array in [[6, 2], [11, 3]]:
		var field: int = pair[1]
		_for_every_record(pair[0], func(diagram: DiagramBase, _level: int) -> void:
			var replay := diagram.success_replay
			assert_int(replay.steps.size()).is_equal(1)
			assert_array(replay.sounds()).is_empty()
			assert_int(replay.end_tick).is_equal(0)
			assert_int(replay.steps[0].items.size()).is_equal(diagram.items.size() + 2)       # picture 2 and the answer
			var answer: DiagramItem = replay.steps[0].items.back()
			assert_str(answer.text).is_equal(diagram.record.number_at(field).to_text() if pair[0] == 6 else str(diagram.record.int_at(field))))


func test_type_16_shows_the_distances_and_the_total_in_the_answer_box() -> void:
	_for_every_record(16, func(diagram: DiagramBase, level: int) -> void:
		var replay := diagram.success_replay
		assert_array(replay.sounds()).is_empty()
		var added: Array = replay.steps[0].items.slice(diagram.items.size())
		if level < 2:
			assert_int(added.size()).is_equal(2)                                       # picture 3 and the total f10
			assert_str((added[1] as DiagramItem).text).is_equal(diagram.record.number_at(10).to_text())
		else:
			assert_int(added.size()).is_equal(4)                                       # picture 3, f8, f9, f10
			assert_str((added[3] as DiagramItem).text).is_equal(diagram.record.number_at(10).to_text()))


func test_type_12_the_mercury_moves_to_the_answer_after_73_ticks() -> void:
	var count := _for_every_record(12, func(diagram: DiagramBase, _level: int) -> void:
		var from := diagram.record.int_at(0)
		var to := diagram.record.int_at(2)
		@warning_ignore("integer_division")
		var moved := absi((to - from) / 5)
		var rising := from < to
		var pieces := moved + 1 if rising else moved
		var replay := diagram.success_replay
		assert_array(replay.sounds()).is_equal([[73, 0x25]])
		assert_array(Array(replay.stops())).is_equal([73 + 10 * pieces])
		assert_int(replay.end_tick).is_equal(73 + 10 * pieces + 30)
		var added: Array = replay.steps.back().items.slice(diagram.items.size())
		assert_int(added.size()).is_equal(pieces)
		for piece: DiagramItem in added:
			assert_int(piece.pic).is_equal(3 if rising else 4)                          # red mercury going up, dark tube going down
		if pieces > 0:
			@warning_ignore("integer_division")
			var top_y := 0x102 - 16 * ((from + 15) / 5)
			assert_float((added[0] as DiagramItem).position.y).is_equal(float(top_y))           # starts at the old top piece
			assert_float((added[pieces - 1] as DiagramItem).position.y).is_equal(float(top_y - 16 * (pieces - 1) if rising else top_y + 16 * (pieces - 1))))
	assert_int(count).is_greater(0)


func test_type_22_the_needle_turns_in_45_degree_steps_to_the_answer() -> void:
	var picture_by_step := [1, 2, 3, 4, 5, 4, 3, 2]
	var count := _for_every_record(22, func(diagram: DiagramBase, _level: int) -> void:
		var angle := diagram.record.int_at(1)
		var turn := 45 if diagram.record.int_at(2) != 0 else -45
		var angles := []
		for _guard in 9:
			angle += turn
			if angle > 359:
				angle = 0
			if angle < 0:
				angle = 315
			angles.append(angle)
			if angle == diagram.record.int_at(3):
				break
			assert_int(angles.size()).is_less(9)                                       # the answer is always reached
		var replay := diagram.success_replay
		assert_array(replay.sounds()).is_equal(_every(22, angles.size(), 0x29))
		assert_int(replay.end_tick).is_equal(22 * angles.size() + 22)
		for i in angles.size():
			@warning_ignore("integer_division")
			var needle: DiagramItem = replay.steps[i].items.back()
			@warning_ignore("integer_division")
			assert_int(needle.pic).is_equal(picture_by_step[angles[i] / 45])
			@warning_ignore("integer_division")
			assert_bool(needle.flip).is_equal(angles[i] / 45 >= 5)                        # mirrored for 225, 270 and 315 degrees
			assert_int(replay.steps[i].items.size()).is_equal(2))                         # the panel and the needle: a frame replaces the last
	assert_int(count).is_greater(0)


func test_type_23_two_pictures_22_and_44_ticks_apart() -> void:
	_for_every_record(23, func(diagram: DiagramBase, _level: int) -> void:
		var replay := diagram.success_replay
		assert_array(replay.sounds()).is_equal([[22, 0x29], [44, 0x29]])
		assert_int(replay.end_tick).is_equal(88)
		var mirrored := diagram.record.int_at(2) != 0
		assert_int((replay.steps[0].items.back() as DiagramItem).pic).is_equal(2)
		assert_int((replay.steps[1].items.back() as DiagramItem).pic).is_equal(1)
		assert_bool((replay.steps[0].items.back() as DiagramItem).flip).is_equal(mirrored)
		assert_bool((replay.steps[1].items.back() as DiagramItem).flip).is_equal(mirrored))


func test_type_26_and_27_the_needle_moves_one_step_every_20_ticks_and_ends_on_the_answer() -> void:
	for pair: Array in [[26, -1, 2, 3], [27, 1, 3, 4]]:
		var type_id: int = pair[0]
		var count := _for_every_record(type_id, func(diagram: DiagramBase, _level: int) -> void:
			var start := diagram.record.int_at(0)
			var steps: int = diagram.record.int_at(pair[2])
			var replay := diagram.success_replay
			assert_int(replay.steps.size()).is_equal(steps + 1)
			assert_int(replay.end_tick).is_equal(20 * (steps + 1))
			var sounds := []
			for k in range(1, steps + 1):
				sounds.append([20 * k, 0x22])                                            # every picture but the first
			assert_array(replay.sounds()).is_equal(sounds)
			# the first picture is the needle of the diagram, the last one the answer's
			var entries: Array = diagram.spec["items"][1]["lookup"]["entries"]
			var first_needle: DiagramItem = replay.steps[0].items.back()
			var last_needle: DiagramItem = replay.steps.back().items.back()
			assert_int(first_needle.pic).is_equal(entries[start]["pic"])
			assert_int(last_needle.pic).is_equal(entries[diagram.record.int_at(pair[3])]["pic"])
			assert_vector(last_needle.position).is_equal(DiagramBase.vector(entries[diagram.record.int_at(pair[3])]["pos"])))
		assert_int(count).is_greater(0)


# --- playing them ---------------------------------------------------------------------------------

## Adds `diagram` to the tree (a Tween needs it) and records every sound it asks for with the time in ms.
func _play_recorded(diagram: DiagramBase, replay: bool) -> Array:
	add_child(diagram)
	var heard := []
	var started := Time.get_ticks_msec()
	diagram.sfx_requested.connect(func(sfx_id: StringName) -> void: heard.append([Time.get_ticks_msec() - started, sfx_id]))
	diagram.sfx_stop_requested.connect(func() -> void: heard.append([Time.get_ticks_msec() - started, -1]))
	if replay:
		diagram.play_success_replay()
	else:
		diagram.play_intro()
	await assert_signal(diagram).wait_until(4000).is_emitted("animation_finished")
	heard.append([Time.get_ticks_msec() - started, -2])                       # the end
	return heard


func test_a_diagram_plays_its_sounds_on_schedule() -> void:
	var diagram := _first(4)                                                   # 4 pieces, 15 ticks (205 ms) apart, 60 ticks (822 ms) in all
	var heard: Array = await _play_recorded(diagram, false)
	assert_int(heard.size()).is_equal(5)
	for i in 4:
		assert_str(heard[i][1]).is_equal("diagram_bar")
	# (the first wait is not measured: the Tween's first frame may be late, which shortens it)
	for i in range(2, 4):
		assert_int(int(heard[i][0]) - int(heard[i - 1][0])).is_between(205 - 60, 205 + 60)
	assert_int(int(heard[4][0]) - int(heard[3][0])).is_between(205 - 60, 205 + 60)     # the wait after the last piece
	assert_bool(diagram.is_playing()).is_false()
	assert_array(diagram._shown).is_equal(diagram.items)


func test_the_first_sound_comes_with_the_first_frame() -> void:
	var diagram := _diagram(25, 1, 0)
	add_child(diagram)
	var heard := []
	diagram.sfx_requested.connect(func(sfx_id: StringName) -> void: heard.append(sfx_id))
	diagram.play_intro()
	assert_array(heard).is_equal([&"diagram_bar"])                                       # nothing waits for the Tween's first frame
	assert_bool(diagram.is_playing()).is_true()
	assert_int(diagram._shown.size()).is_equal(3)                              # the first reading only
	diagram.skip_animation()
	assert_bool(diagram.is_playing()).is_false()
	assert_array(diagram._shown).is_equal(diagram.items)


func test_a_success_replay_plays_its_sounds_on_schedule() -> void:
	var diagram := _first(23)                                                  # sounds at 22 and 44 ticks, over at 88: 301 ms apart, 603 ms to the end
	var heard: Array = await _play_recorded(diagram, true)
	assert_int(heard.size()).is_equal(3)
	assert_str(heard[0][1]).is_equal("diagram_pop")
	assert_str(heard[1][1]).is_equal("diagram_pop")
	assert_int(int(heard[1][0]) - int(heard[0][0])).is_between(301 - 60, 301 + 60)
	assert_int(int(heard[2][0]) - int(heard[1][0])).is_between(603 - 60, 603 + 60)
	assert_array(diagram._shown).is_equal(diagram.success_replay.steps.back().items)   # the replay's last picture stays


func test_the_thermometer_replay_cuts_its_sound_off() -> void:
	var diagram := _first(12)
	add_child(diagram)
	var events := []
	diagram.sfx_requested.connect(func(sfx_id: StringName) -> void: events.append("play %s" % sfx_id))
	diagram.sfx_stop_requested.connect(func() -> void: events.append("stop"))
	diagram.play_success_replay()
	assert_array(events).is_empty()                                            # DelayTicks(73) comes first
	diagram.skip_animation()
	assert_array(events).is_equal(["stop"])                                    # a skip silences it
	assert_bool(diagram.is_playing()).is_false()


func test_a_diagram_without_a_replay_returns_at_once() -> void:
	var diagram := _first(9)
	add_child(diagram)
	await diagram.play_success_replay()                                        # would hang if it waited for a signal
	assert_bool(diagram.is_playing()).is_false()


# --- the ballast panel's Done button (GetBallastAnswer 0x4196e8) ----------------------------------

func test_ballast_done_clicks_shows_the_pressed_ok_and_tells_the_flow_to_hold_73_ticks() -> void:
	var panel := _first(28) as BallastPanelDiagram
	add_child(panel)
	var clicks := []
	var holds := []
	panel.sfx_requested.connect(func(sfx_id: StringName) -> void: clicks.append(sfx_id))
	panel.done_pressed.connect(func(mask: int, hold_ticks: int) -> void: holds.append([mask, hold_ticks]))
	panel.toggle(2)
	clicks.clear()
	panel._press(panel.slot_count())                                          # Done
	assert_array(clicks).is_equal([&"click"])                                      # Done clicks like every button
	assert_array(holds).is_equal([[1 << 2, 73]])                               # the length of the hold is the panel's DATA (73 ticks = 1 s) ...
	assert_bool(panel.is_done_pressed()).is_true()                             # ... and whoever owns the problem counts it (ProblemFlow)
	assert_int(panel.pictures(5).size()).is_equal(1)                           # the pressed OK instead of the idle button
	assert_int(panel.pictures(7).size()).is_equal(0)
	panel.toggle(0)                                                            # nothing can be changed meanwhile
	assert_int(panel.selected).is_equal(1 << 2)
	# asked again after a wrong answer: the panel is ready again
	panel.keyboard_enabled = true
	assert_bool(panel.is_done_pressed()).is_false()
	assert_int(panel.pictures(5).size()).is_equal(0)


# --- the clock belongs to the owner -----------------------------------------------------------------
# `ProblemFlow` counts the ticks of a build-up and tells the diagram where it is: the diagram only shows what is due.

func test_a_diagram_shows_only_what_is_due_at_the_tick_it_is_told() -> void:
	var diagram := _first(4)                                                   # 4 pieces, a sound every 15 ticks, over at tick 60
	var heard := []
	diagram.sfx_requested.connect(func(sfx_id: StringName) -> void: heard.append(sfx_id))
	assert_int(diagram.intro_length()).is_equal(60)
	diagram.begin_intro()
	assert_array(heard).has_size(1)                                            # tick 0 shows in the very first frame
	assert_bool(diagram.is_playing()).is_true()
	diagram.animate_to(14)
	assert_array(heard).has_size(1)
	diagram.animate_to(15)
	assert_array(heard).has_size(2)
	diagram.animate_to(45)                                                     # (ticks 30 and 45 come together when time jumps)
	assert_array(heard).has_size(4)
	diagram.animate_to(59)
	assert_bool(diagram.is_playing()).is_true()
	diagram.animate_to(60)
	assert_bool(diagram.is_playing()).is_false()
	assert_array(diagram._shown).is_equal(diagram.items)
	diagram.animate_to(1000)                                                   # an animation that is over ignores the clock
	assert_array(heard).has_size(4)


func test_a_jump_far_ahead_still_plays_every_sound_once() -> void:
	var diagram := _first(7)                                                   # five values, 30 ticks apart
	var heard := []
	diagram.sfx_requested.connect(func(sfx_id: StringName) -> void: heard.append(sfx_id))
	diagram.begin_intro()
	diagram.animate_to(100000)
	assert_array(heard).has_size(5)
	assert_bool(diagram.is_playing()).is_false()


func test_the_radar_sweep_is_144_ticks_long_and_pings_at_0_72_and_144() -> void:
	var sonar := _first(3) as SonarDiagram
	assert_int(sonar.intro_length()).is_equal(2 * 12 * 6)                      # two turns of 12 pictures, 6 ticks each (data)
	var pings := []
	var now := [0]
	sonar.sfx_requested.connect(func(_sfx_id: StringName) -> void: pings.append(now[0]))
	sonar.begin_intro()
	for tick in range(1, 145):
		now[0] = tick
		sonar.animate_to(tick)
		if tick < 144:
			assert_bool(sonar.is_playing()).is_true()
	assert_array(pings).is_equal([0, 72, 144])
	assert_bool(sonar.is_playing()).is_false()
