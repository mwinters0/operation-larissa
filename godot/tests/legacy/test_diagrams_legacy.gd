class_name TestDiagramsLegacy
extends GdUnitTestSuite
## The ORIGINAL's diagrams (legacy pack): every one of its 1276 stored problems drawn by the code of its family, with the numbers of its record (40 px per degree, 5 mph a segment, 100 ppm a slice ...).
## The generic vocabulary and the pack-independent checks are tests/engine/test_diagrams.gd.
## Teaches: testing a DRAWING by measuring it. A diagram builds a list of `DiagramItem`s from a
## stored record, so a test can count the pictures, read their positions and compare them with what the
## record says (the speed graph has one segment per 5 mph, the nav chart's markers are 40 px per degree
## of longitude apart ...). Every stored problem of the game (1276 records) goes through these checks.

const WINDOW := Rect2(0, 0, 640, 400)


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


## Builds the diagram of record `index` of `type_id` at `level` (the pie chart's legend rotation can be chosen).
func _diagram(type_id: int, level: int, index: int, rotation: int = 0) -> DiagramBase:
	var problem := ProblemInstance.build(Catalog.problem_type(type_id), level, index, rotation)
	return auto_free(DiagramFactory.plain(problem)) as DiagramBase


## Calls `check` with the diagram of every stored record of the type.
func _for_every_record(type_id: int, check: Callable) -> int:
	var type := Catalog.problem_type(type_id)
	var count := 0
	for level in 4:
		for index in type.record_count(level):
			check.call(_diagram(type_id, level, index), level)
			count += 1
	return count


# --- all types ---------------------------------------------------------------------------

func test_every_type_has_a_diagram_family_and_only_uses_pictures_it_has() -> void:
	for type_id in Catalog.PROBLEM_TYPE_COUNT:
		var type := Catalog.problem_type(type_id)
		assert_bool(type.diagram.has("family")).is_true()
		assert_bool(type.diagram.has("source")).override_failure_message("type %d: no source note" % type_id).is_true()
		# the importer's output is a Dictionary of plain values; the factory must know the family
		assert_object(auto_free(DiagramFactory._new_for(type.diagram["family"]))).is_not_null()


func test_all_1276_records_draw_something_inside_the_window() -> void:
	var drawn := 0
	for type_id in Catalog.PROBLEM_TYPE_COUNT:
		drawn += _for_every_record(type_id, func(diagram: DiagramBase, _level: int) -> void:
			assert_int(diagram.items.size()).is_greater(0)
			for item in diagram.items:
				if item.kind == DiagramItem.Kind.PICTURE:
					assert_object(diagram.texture_of(item)).is_not_null()
					assert_bool(WINDOW.encloses(Rect2(item.position, diagram.texture_of(item).get_size()))).override_failure_message(
							"type %d picture %d at %s leaves the window" % [type_id, item.pic, item.position]).is_true())
	assert_int(drawn).is_equal(1276)


func test_the_panel_picture_comes_first_where_the_original_draws_it_first() -> void:
	for type_id in range(1, Catalog.PROBLEM_TYPE_COUNT):
		var diagram := _diagram(type_id, Catalog.problem_type(type_id).levels_available.find(1), 0)
		assert_int(diagram.items[0].pic).is_equal(0)


func test_screen_layout_matches_the_originals_window() -> void:
	var layout := Catalog.screen_layout()
	assert_object(layout.background).is_not_null()
	assert_vector(Vector2(layout.background_position)).is_equal(Vector2(12, 30))
	assert_object(layout.message_box).is_equal(Rect2i(364, 48, 238, 202))
	assert_int(layout.palette.size()).is_equal(16)
	assert_int(layout.font_size()).is_equal(17)
	assert_object(layout.color(15)).is_equal(Color.WHITE)


# --- generic items -----------------------------------------------------------------------

func test_speed_graph_has_one_segment_per_5_mph_in_each_column() -> void:
	var count := _for_every_record(2, func(diagram: DiagramBase, _level: int) -> void:
		var segments := diagram.pictures(1)
		var total := 0
		for i in 6:
			var speed := diagram.record.int_at(i)
			total += speed / 5
			var column_x: int = diagram.spec["items"][1 + i]["pos"][0]
			var in_column := segments.filter(func(item: DiagramItem) -> bool: return int(item.position.x) == column_x)
			assert_int(in_column.size()).is_equal(speed / 5)
		assert_int(segments.size()).is_equal(total))
	assert_int(count).is_equal(27)


func test_speed_graph_segments_stack_upwards_from_the_axis() -> void:
	var diagram := _diagram(2, 1, 0)            # speeds 25 5 10 10 5 5
	var first_column := diagram.pictures(1).filter(func(item: DiagramItem) -> bool: return item.position.x == 92.0)
	assert_int(first_column.size()).is_equal(5)
	assert_float(first_column[0].position.y).is_equal(226.0)
	assert_float(first_column[4].position.y).is_equal(226.0 - 4 * 26.0)


func test_numbers_are_printed_into_the_panel_boxes() -> void:
	_for_every_record(1, func(diagram: DiagramBase, _level: int) -> void:      # access code: four numbers, then the "?" picture
		var shown := diagram.texts()
		assert_int(shown.size()).is_equal(4)
		for i in 4:
			assert_str(shown[i]).is_equal(diagram.record.number_at(i).to_text())
		assert_int(diagram.pictures(1).size()).is_equal(1))
	_for_every_record(7, func(diagram: DiagramBase, _level: int) -> void:      # five masses
		assert_int(diagram.texts().size()).is_equal(5))
	var scale_reading := _diagram(15, 0, 0)
	assert_array(scale_reading.texts()).contains_exactly([scale_reading.record.number_at(0).to_text()])
	var heat := _diagram(10, 1, 0)
	assert_str(heat.texts()[0]).ends_with("°C")


func test_numbers_are_centred_in_their_box() -> void:
	var diagram := _diagram(15, 0, 0)
	var item: DiagramItem = diagram.items.filter(func(i: DiagramItem) -> bool: return i.kind == DiagramItem.Kind.TEXT)[0]
	assert_int(item.align).is_equal(DiagramItem.Align.CENTER)
	assert_float(item.position.x).is_equal(float(0x76))
	assert_float(item.anchor_width).is_equal(float(0x6a))


func test_the_scale_picture_depends_on_the_level_for_the_capsule_inventory() -> void:
	assert_int(_diagram(7, 0, 0).pictures(1).size()).is_equal(1)    # grams
	assert_int(_diagram(7, 1, 0).pictures(2).size()).is_equal(1)    # kilograms


func test_depth_gauge_marks_are_the_depth_over_the_scale_division() -> void:
	var divisors := {0: 100, 1: 100, 2: 20, 3: 100, 4: 100}         # per conversion kind f0, from the original's table
	_for_every_record(8, func(diagram: DiagramBase, _level: int) -> void:
		var expected: int = diagram.record.int_at(1) / divisors[diagram.record.int_at(0)]
		assert_int(diagram.pictures(4).size()).is_equal(expected))


func test_toxicity_bars_have_one_slice_per_100_ppm() -> void:
	_for_every_record(20, func(diagram: DiagramBase, _level: int) -> void:
		assert_int(diagram.pictures(1).size()).is_equal(ceili(diagram.record.int_at(1) / 100.0))        # left bar: field f1
		assert_int(diagram.pictures(2).size()).is_equal(ceili(diagram.record.int_at(0) / 100.0)))       # right bar: field f0


func test_thermometers_fill_one_segment_per_5_degrees_above_minus_15() -> void:
	var fahrenheit := _for_every_record(12, func(diagram: DiagramBase, _level: int) -> void:
		assert_int(diagram.pictures(3).size()).is_equal((diagram.record.int_at(0) + 15) / 5 + 1))
	assert_int(fahrenheit).is_equal(20)
	_for_every_record(13, func(diagram: DiagramBase, _level: int) -> void:
		var celsius_given := diagram.record.int_at(2) != 0
		var expected := (diagram.record.int_at(0) + (35 if celsius_given else 15)) / 5 + 1
		assert_int(diagram.pictures(3).size()).is_equal(expected)
		assert_int(diagram.pictures(1).size()).is_equal(1 if celsius_given else 0))        # the Celsius scale picture


func test_the_sounder_prints_the_speed_of_sound_and_the_echo_time() -> void:
	var diagram := _diagram(6, 1, 0)
	assert_array(diagram.texts()).contains_exactly(["5000", diagram.record.number_at(0).to_text()])


func test_oil_gauge_marks_and_maximum() -> void:
	_for_every_record(18, func(diagram: DiagramBase, _level: int) -> void:
		assert_int(diagram.pictures(1).size()).is_equal(diagram.record.int_at(0))
		assert_array(diagram.texts()).contains_exactly([str(diagram.record.int_at(1))])
		var text: DiagramItem = diagram.items.filter(func(i: DiagramItem) -> bool: return i.kind == DiagramItem.Kind.TEXT)[0]
		assert_int(text.align).is_equal(DiagramItem.Align.RIGHT))


func test_distance_chart_shows_a_second_leg_from_level_2_on() -> void:
	_for_every_record(16, func(diagram: DiagramBase, level: int) -> void:
		assert_int(diagram.texts().size()).is_equal(2 if level < 2 else 4))


func test_fixed_overlays_of_the_graphs_are_always_the_same() -> void:
	_for_every_record(4, func(diagram: DiagramBase, _level: int) -> void:
		assert_int(diagram.items.size()).is_equal(5))
	_for_every_record(5, func(diagram: DiagramBase, _level: int) -> void:
		assert_int(diagram.items.size()).is_equal(7))


# --- table lookups -----------------------------------------------------------------------

func test_heading_picture_follows_the_present_heading_and_mirrors_the_west_half() -> void:
	var by_heading := {0: [1, false], 45: [2, false], 90: [3, false], 135: [4, false], 180: [5, false],
			225: [4, true], 270: [3, true], 315: [2, true]}
	_for_every_record(22, func(diagram: DiagramBase, _level: int) -> void:
		var heading := diagram.record.int_at(1)
		var needle: DiagramItem = diagram.items[1]
		assert_array([needle.pic, needle.flip]).is_equal(by_heading[heading])
		assert_vector(needle.position).is_equal(Vector2(0x88, 0x98)))


func test_speed_needle_is_the_table_entry_of_the_speed() -> void:
	for type_id in [26, 27]:
		_for_every_record(type_id, func(diagram: DiagramBase, _level: int) -> void:
			var entries: Array = diagram.spec["items"][1]["lookup"]["entries"]
			var entry: Dictionary = entries[diagram.record.int_at(0)]
			var needle: DiagramItem = diagram.items[1]
			assert_int(needle.pic).is_equal(entry["pic"])
			assert_vector(needle.position).is_equal(Vector2(entry["pos"][0], entry["pos"][1]))
			assert_bool(needle.flip).is_equal(entry["flip"]))
	# the speeds 0-25: the needle sweeps from the lower left over the top to the lower right
	var entries: Array = Catalog.problem_type(26).diagram["items"][1]["lookup"]["entries"]
	assert_int(entries.size()).is_equal(26)
	assert_int(entries[0]["pic"]).is_equal(6)
	assert_int(entries[15]["pic"]).is_equal(11)
	assert_int(entries[25]["pic"]).is_equal(1)


func test_clock_shows_the_hour_hand_for_the_present_hour_and_ignores_minutes() -> void:
	assert_int(DiagramBase.hour_on_12_hour_clock(1800)).is_equal(6)
	assert_int(DiagramBase.hour_on_12_hour_clock(2400)).is_equal(12)
	assert_int(DiagramBase.hour_on_12_hour_clock(100)).is_equal(1)
	# 12:30 gives hour 0 like the original, and the hour-0 and hour-12 hands are the same picture
	assert_int(DiagramBase.hour_on_12_hour_clock(1230)).is_equal(0)
	var hands: Array = Catalog.problem_type(24).diagram["items"][2]["lookup"]["entries"]
	assert_dict(hands[0]).is_equal(hands[12])
	assert_int(DiagramBase.hour_on_12_hour_clock(1500)).is_equal(3)
	_for_every_record(24, func(diagram: DiagramBase, _level: int) -> void:
		assert_int(diagram.pictures(1).size()).is_equal(1)                       # the minute hand, always straight up
		var entries: Array = diagram.spec["items"][2]["lookup"]["entries"]
		var hand := entries[DiagramBase.hour_on_12_hour_clock(diagram.record.int_at(3))] as Dictionary
		assert_int(diagram.items[2].pic).is_equal(hand["pic"])
		assert_bool(diagram.items[2].flip).is_equal(hand["flip"]))


func test_side_ballast_mirrors_for_the_other_side() -> void:
	_for_every_record(23, func(diagram: DiagramBase, _level: int) -> void:
		assert_bool(diagram.pictures(3)[0].flip).is_equal(diagram.record.int_at(2) != 0))


func test_radio_telephone_pictures_follow_period_and_unit() -> void:
	_for_every_record(11, func(diagram: DiagramBase, _level: int) -> void:
		assert_int(diagram.pictures(3 + diagram.record.int_at(1)).size()).is_equal(1)
		assert_int(diagram.pictures(6 + diagram.record.int_at(2)).size()).is_equal(1)
		assert_array(diagram.texts()).contains_exactly([str(diagram.record.int_at(0))]))


# --- families ---------------------------------------------------------------------------

func test_nav_chart_markers_are_40_px_per_degree_of_longitude_and_18_px_per_degree_of_latitude() -> void:
	var count := _for_every_record(9, func(diagram: DiagramBase, _level: int) -> void:
		var station := diagram.pictures(1).filter(func(i: DiagramItem) -> bool: return i.position.y < 250.0)[0] as DiagramItem
		var sub := diagram.pictures(2).filter(func(i: DiagramItem) -> bool: return i.position.y < 250.0)[0] as DiagramItem
		# the stored answer is the difference of longitudes (f0 = 0) or of latitudes (f0 = 1) of station and sub
		var answer := diagram.record.value_at(5)
		if diagram.record.int_at(0) == 0:
			assert_float(absf(station.position.x - sub.position.x) / 40.0).is_equal_approx(answer, 0.001)
		else:
			assert_float(absf(station.position.y - sub.position.y) / 18.0).is_equal_approx(answer, 0.001))
	assert_int(count).is_equal(40)
	# longitudes grow to the west: 180 is the left edge of the chart
	var map: Dictionary = Catalog.problem_type(9).diagram["map"]
	assert_vector(NavChartDiagram.marker_position(map, 180.0, 20.0)).is_equal(Vector2(86, 82))
	assert_float(NavChartDiagram.marker_position(map, 175.0, 20.0).x).is_greater(86.0)


func test_sonar_blip_is_one_row_per_5_miles_and_the_beam_ends_straight_up() -> void:
	_for_every_record(3, func(diagram: DiagramBase, _level: int) -> void:
		var sonar := diagram as SonarDiagram
		assert_int(sonar.blip_row()).is_equal(clampi(diagram.record.int_at(0) / 5, 0, 4))
		assert_int(diagram.pictures(2).size()).is_equal(1)                       # the beam, picture 2 = vertical
		assert_int(diagram.pictures(11).size()).is_equal(1))                     # the blip's last frame
	var far := _diagram(3, 0, 0)                                                 # 10 miles: row 2
	assert_float(far.pictures(11)[0].position.y).is_equal(130.0)


func test_barnacles_unhealthy_ones_use_their_own_picture() -> void:
	var count := _for_every_record(14, func(diagram: DiagramBase, _level: int) -> void:
		var total := diagram.record.int_at(0)
		var unhealthy := diagram.record.int_at(1)
		assert_int(diagram.pictures(3).size()).is_equal(unhealthy)
		assert_int(diagram.pictures(4).size() + diagram.pictures(5).size()).is_equal(total - unhealthy)
		assert_int((diagram as BarnacleDiagram).barnacle_count()).is_equal(total))
	assert_int(count).is_equal(29)


func test_barnacle_pictures_swap_between_the_two_phases() -> void:
	var diagram := _diagram(14, 1, 1) as BarnacleDiagram          # 11 barnacles, 4 unhealthy: 7 healthy, split 3 + 4
	assert_int(diagram.pictures(5).size()).is_equal(3)            # phase 1: the first 3 healthy ones show picture 5, the other 4 picture 4
	assert_int(diagram.pictures(4).size()).is_equal(4)
	diagram.phase = 0
	diagram.items.clear()
	diagram._build()
	assert_int(diagram.pictures(4).size()).is_equal(3)
	assert_int(diagram.pictures(5).size()).is_equal(4)


func test_pie_chart_slices_are_fixed_pictures_and_shares_match_the_stored_answers() -> void:
	var checked := 0
	for rotation in 2:
		for level in [1, 2, 3]:
			for index in Catalog.problem_type(17).record_count(level):
				var diagram := _diagram(17, level, index, rotation) as PieDiagram
				var problem := diagram.problem
				var f0 := problem.record.int_at(0)
				assert_int(diagram.pictures(4 if f0 == 0 else 1).size()).is_equal(1)
				# the foods the prompt names: asked slice (purple, orange or purple) and, at level 3, also the green one
				var asked_row: int = [PieDiagram.PURPLE, PieDiagram.ORANGE, PieDiagram.PURPLE][f0]
				var share := diagram.share_of_row(asked_row)
				if level == 3:
					share += diagram.share_of_row(PieDiagram.GREEN)
				var stored := problem.record.value_at(1) / (1.0 if problem.record.is_fraction_at(1) else 100.0)
				assert_float(share).is_equal_approx(stored, 0.007)
				# and the prompt names exactly those foods, whatever the legend's order
				assert_str(problem.prompt.to_lower()).contains(diagram.type.text_at(13 + diagram.food_in_row(asked_row)))
				checked += 1
	assert_int(checked).is_equal(2 * 10)


func test_pie_chart_legend_rotates_the_foods() -> void:
	var a := _diagram(17, 1, 0, 0) as PieDiagram
	var b := _diagram(17, 1, 0, 1) as PieDiagram
	assert_array(a.texts()).contains_exactly(["Canned", "Frozen", "Freeze-Dried"])
	assert_array(b.texts()).contains_exactly(["Frozen", "Freeze-Dried", "Canned"])


func test_window_crack_length_is_the_stored_answer_in_ruler_units() -> void:
	_for_every_record(19, func(diagram: DiagramBase, _level: int) -> void:
		var ruler := diagram as RulerDiagram
		var ends := ruler.crack_ends()
		var factor: int = ruler.spec["crack"]["units_per_value"][diagram.record.int_at(0)]
		assert_float((ends.y - ends.x) / 12.0 / factor).is_equal_approx(diagram.record.value_at(6), 0.0001)
		assert_int(diagram.items.filter(func(i: DiagramItem) -> bool: return i.kind == DiagramItem.Kind.RECT).size()).is_equal(2))


func test_water_tank_fills_three_frames_per_unit_and_labels_the_amount() -> void:
	_for_every_record(21, func(diagram: DiagramBase, _level: int) -> void:
		var tank := diagram as TankDiagram
		var supply := tank.supply()
		var frames := tank.water_frames(supply["amount"])
		assert_int(frames).is_equal(maxi(0, supply["amount"] * 3 - 7))
		assert_int(diagram.pictures(3).size()).is_equal(maxi(1, frames))
		assert_int(diagram.pictures(5).size()).is_equal(frames)
		assert_str(diagram.texts()[0]).is_equal("%d%s" % [supply["amount"], " liters" if supply["liters"] else " gallons"]))
	var tank := _diagram(21, 0, 0) as TankDiagram                     # 18 gallons: 47 frames
	assert_int(tank.water_frames(18)).is_equal(47)
	assert_int(tank.water_top(46)).is_equal(0xd0 - 92)


func test_toxicity_graph_has_a_segment_and_a_dot_for_each_of_the_seven_readings() -> void:
	_for_every_record(25, func(diagram: DiagramBase, _level: int) -> void:
		var graph := diagram as LineGraphDiagram
		assert_int(diagram.pictures(1).size()).is_equal(7)                       # dots
		assert_int(diagram.pictures(2).size() + diagram.pictures(3).size() + diagram.pictures(4).size()).is_equal(7)
		var rises := 0
		var falls := 0
		for k in range(1, 7):
			rises += 1 if graph.level_of(k) > graph.level_of(k - 1) else 0
			falls += 1 if graph.level_of(k) < graph.level_of(k - 1) else 0
		assert_int(diagram.pictures(3).size()).is_equal(rises)
		assert_int(diagram.pictures(4).size()).is_equal(falls)
		# every dot sits on the grid line of its reading
		for k in 7:
			var dot := diagram.pictures(1)[k]
			var shift := 2.0 if k == 0 else 4.0
			assert_float(dot.position.y).is_equal(graph.y_of_level(graph.level_of(k)) - shift))


func test_food_storage_boxes_are_length_times_width_times_height_plus_extras() -> void:
	var count := _for_every_record(30, func(diagram: DiagramBase, _level: int) -> void:
		var r := diagram.record
		var boxes := (diagram as StorageBoxesDiagram).box_count()
		assert_int(boxes).is_equal(r.int_at(0) * r.int_at(1) * r.int_at(2) + r.int_at(9)))
	assert_int(count).is_equal(40)


func test_search_grid_with_area_has_exactly_the_stored_area() -> void:
	var seen := {}
	_for_every_record(31, func(diagram: DiagramBase, _level: int) -> void:
		var r := diagram.record
		var shape := r.int_at(0)
		seen[shape] = true
		var rows := r.int_at(1)
		var columns := r.int_at(2)
		var expected: float
		match shape:
			1: expected = rows * columns
			2: expected = rows * columns / 2.0
			3: expected = rows * columns + r.int_at(4) * r.int_at(5)
			6: expected = rows * columns / 2.0 + r.int_at(4) * r.int_at(5)
		assert_float((diagram as SearchAreaDiagram).area()).is_equal(expected)
		# the stored areas of the parts agree with the drawing too
		if shape == 3 or shape == 6:
			assert_float(expected).is_equal(float(r.int_at(3) + r.int_at(6))))
	assert_array(seen.keys()).contains_exactly_in_any_order([1, 2, 3, 6])


func test_search_grid_triangles_start_at_the_bottom_left_and_stay_in_the_grid() -> void:
	var diagram := _diagram(31, 2, 0) as SearchAreaDiagram           # a 6 x 6 right triangle
	var cells := diagram.items.filter(func(i: DiagramItem) -> bool: return i.kind == DiagramItem.Kind.PICTURE and i.pic in [2, 3])
	var lowest := 0.0
	for cell: DiagramItem in cells:
		lowest = maxf(lowest, cell.position.y)
		assert_float(cell.position.x).is_greater_equal(80.0)
	assert_float(lowest).is_equal(82.0 + 5 * 16.0)                   # the longest row is the sixth, at the bottom
	assert_int(cells.filter(func(i: DiagramItem) -> bool: return i.position.y == lowest).size()).is_equal(6)


func test_search_grid_fraction_shades_the_stored_number_of_squares() -> void:
	for type_id in [32, 33]:
		_for_every_record(type_id, func(diagram: DiagramBase, _level: int) -> void:
			assert_int((diagram as SearchGridDiagram).shaded_count()).is_equal(diagram.record.int_at(0))
			# the number of squares picks the grid: 4, 16 or 100
			assert_bool(diagram.record.int_at(1) in [4, 16, 100]).is_true())


func test_search_grid_cells_go_row_by_row() -> void:
	var grid := _diagram(32, 3, 1) as SearchGridDiagram              # 45 of 100 squares
	var cells := grid.pictures(2)
	assert_int(cells.size()).is_equal(45)
	assert_vector(cells[0].position).is_equal(Vector2(80, 82))
	assert_vector(cells[10].position).is_equal(Vector2(80, 98))
	assert_vector(cells[44].position).is_equal(Vector2(80 + 4 * 20, 82 + 4 * 16))


func test_combination_lock_draws_its_wheels_and_all_sixteen_labels() -> void:
	_for_every_record(0, func(diagram: DiagramBase, _level: int) -> void:
		assert_int(diagram.texts().size()).is_equal(16)
		assert_int(diagram.pictures(11).size()).is_equal(1)                      # the lock's face
		assert_int(diagram.pictures(12).size()).is_equal(1)                      # the answer wheel at rest
		assert_int(diagram.pictures(6).size()).is_equal(1))                      # the operand wheel at rest


func test_ballast_panel_toggles_weights_and_sums_them() -> void:
	var panel := _diagram(28, 0, 0) as BallastPanelDiagram                # weights 1 1 1 1 5 5 10 25 25 25, target 15
	assert_int(panel.slot_count()).is_equal(10)
	assert_int(panel.pictures(3).size()).is_equal(0)
	panel.toggle(4)
	panel.toggle(6)
	assert_int(panel.pictures(3).size()).is_equal(2)                         # two weights switched on
	assert_int(panel.sum()).is_equal(15)
	assert_int(panel.selected).is_equal((1 << 4) | (1 << 6))
	assert_int(panel.button_at(panel.slot_position(7) + Vector2(5, 5))).is_equal(7)
	assert_int(panel.button_at(Vector2(0x34 + 5, 0xee + 5))).is_equal(10)    # the Done button
	assert_int(panel.button_at(Vector2(2, 2))).is_equal(-1)


func test_ballast_panel_reports_the_selection_and_the_hold_when_done_is_pressed() -> void:
	var panel := _diagram(29, 0, 0) as BallastPanelDiagram
	var reported := []
	panel.done_pressed.connect(func(mask: int, hold_ticks: int) -> void: reported.append([mask, hold_ticks]))
	panel.toggle(0)
	panel._press(10)
	assert_array(reported).contains_exactly([[1, 73]])                       # the weights, and how long the pressed button stays (data)
	assert_str(panel.texts()[0]).is_equal("1")
	assert_array(panel.pictures(1).map(func(i: DiagramItem) -> Vector2: return i.position)).contains_exactly([Vector2(0xb4, 0x11c)])   # the "Drain" marker


## `LoadBallastLabels` (0x419d96) loads strings 11215-11218 over the level-3 labels: "0.01" (weights 0-3), "0.05" (4-5), "0.10" (6), "0.25" (7-9).
func test_ballast_level_3_labels_are_the_loaded_strings() -> void:
	assert_array(Array(_diagram(28, 2, 0).texts().slice(0, 10))).contains_exactly(
			["0.01", "0.01", "0.01", "0.01", "0.05", "0.05", "0.10", "0.25", "0.25", "0.25"])


func test_ballast_labels_follow_the_level() -> void:
	assert_array(Array(_diagram(28, 2, 0).texts().slice(0, 4))).contains_exactly(["0.01", "0.01", "0.01", "0.01"])
	assert_array(Array(_diagram(28, 1, 0).texts().slice(0, 4))).contains_exactly(["1", "2", "4", "8"])


# --- helpers of the base class -------------------------------------------------------------

func test_repeat_counts_follow_the_vocabulary() -> void:
	var diagram := _diagram(2, 1, 0)
	assert_int(diagram.count_of({"field": 0, "divisor": 5})).is_equal(5)                       # 25 mph
	assert_int(diagram.count_of({"field": 0, "divisor": 5, "extra": 1})).is_equal(6)
	assert_int(diagram.count_of({"field": 0, "divisor": 10, "round": "ceil"})).is_equal(3)
	assert_int(diagram.count_of({"field": 0, "add": -30, "divisor": 5})).is_equal(0)           # never negative
	var gauge := _diagram(8, 1, 0)            # conversion kind f0 = 4, depth 300: divisor table picks by f0
	assert_int(gauge.count_of({"field": 1, "divisor_table": {"field": 0, "table": [1, 1, 1, 1, 100]}})).is_equal(3)
