class_name TestDiagrams
extends GdUnitTestSuite
## Teaches: testing a DRAWING by measuring it. A diagram builds a list of `DiagramItem`s from a stored record, so a test can count the pictures, read
## their positions and compare them with what the record says. The generic "items" vocabulary of `DiagramBase` (repeats, text boxes, lookups,
## conditions) is tested on specs the test writes (`ProblemKit.diagram_of`); the pack's own diagrams are tested for what any pack needs (every record
## draws inside the window; the ballast panel works). The original's per-type literals (40 px per degree, 5 mph per segment, 100 ppm slices ...)
## are tests/legacy/test_diagrams_legacy.gd.

const K = preload("res://tests/engine/problem_kit.gd")
const WINDOW := Rect2(0, 0, 640, 400)
const PANEL := {"pic": 0, "pos": [20, 60]}


## Builds the diagram of record `index` of the chain's type `type_id` at `level`.
func _diagram(type_id: int, level: int, index: int, rotation: int = 0) -> DiagramBase:
	var problem := ProblemInstance.build(Catalog.problem_type(type_id), level, index, rotation)
	return auto_free(DiagramFactory.create(problem)) as DiagramBase


## A diagram of a spec of the test's own with the record `numbers` (three decimals).
func _drawn(items: Array, numbers: Array = [0, 0, 0], level: int = 0, places: int = 0) -> DiagramBase:
	return auto_free(K.diagram_of({"family": "items", "items": items}, numbers, level, places)) as DiagramBase


# --- the pack's diagrams ------------------------------------------------------------------

func test_every_type_has_a_diagram_family_the_factory_knows() -> void:
	for type_id in Catalog.PROBLEM_TYPE_COUNT:
		var type := Catalog.problem_type(type_id)
		assert_bool(type.diagram.has("family")).override_failure_message("type %d" % type_id).is_true()
		assert_object(auto_free(DiagramFactory._new_for(type.diagram["family"]))).is_not_null()


func test_every_record_draws_something_inside_the_window() -> void:
	var drawn := 0
	var stored := 0
	for type_id in Catalog.PROBLEM_TYPE_COUNT:
		var type := Catalog.problem_type(type_id)
		stored += type.records.size()
		for level in 4:
			for index in type.record_count(level):
				var diagram := _diagram(type_id, level, index)
				assert_int(diagram.items.size()).is_greater(0)
				for item in diagram.items:
					if item.kind == DiagramItem.Kind.PICTURE:
						assert_object(item.texture).is_not_null()
						assert_bool(WINDOW.encloses(Rect2(item.position, item.texture.get_size()))).override_failure_message(
								"type %d picture %d at %s leaves the window" % [type_id, item.pic, item.position]).is_true()
				drawn += 1
	assert_int(drawn).is_equal(stored)
	assert_int(drawn).is_greater(0)


func test_the_screen_layout_is_data_the_screen_reads() -> void:
	var layout := Catalog.screen_layout()
	assert_object(layout.background).is_not_null()
	assert_bool(WINDOW.encloses(Rect2(layout.background_position, layout.background.get_size()))).is_true()
	assert_bool(Rect2(layout.background_position, layout.background.get_size()).encloses(Rect2(layout.message_box))).is_true()
	assert_int(layout.palette.size()).is_equal(16)
	assert_int(layout.font_size()).is_greater(0)
	assert_object(layout.color(15)).is_equal(Color.WHITE)


# --- the generic items ----------------------------------------------------------------------

func test_a_picture_is_drawn_at_its_place_and_mirrored_on_request() -> void:
	var diagram := _drawn([PANEL, {"pic": 3, "pos": [100, 120], "flip": true}, {"pic": 4, "pos": [140, 120]}])
	assert_int(diagram.items.size()).is_equal(3)
	assert_vector(diagram.pictures(3)[0].position).is_equal(Vector2(100, 120))
	assert_bool(diagram.pictures(3)[0].flip).is_true()
	assert_bool(diagram.pictures(4)[0].flip).is_false()
	assert_int(diagram.items[0].pic).is_equal(0)                              # drawing order is the spec's


func test_a_repeat_stacks_one_copy_per_divisor_of_the_field() -> void:
	# 25 units, one copy for every 5, each 26 pixels above the one before (a column of bars)
	var diagram := _drawn([PANEL, {"pic": 1, "pos": [92, 226], "repeat": {"count": {"field": 0, "divisor": 5}, "step": [0, -26]}}], [25, 0, 0])
	var copies := diagram.pictures(1)
	assert_int(copies.size()).is_equal(5)
	assert_float(copies[0].position.y).is_equal(226.0)
	assert_float(copies[4].position.y).is_equal(226.0 - 4 * 26.0)
	assert_float(copies[4].position.x).is_equal(92.0)
	assert_int(_drawn([PANEL, {"pic": 1, "pos": [92, 226], "repeat": {"count": {"field": 0, "divisor": 5}, "step": [0, -26]}}], [4, 0, 0]).pictures(1).size()).is_equal(0)


func test_repeat_counts_follow_the_vocabulary() -> void:
	var diagram := _drawn([PANEL], [25, 300, 4])
	assert_int(diagram.count_of({"field": 0, "divisor": 5})).is_equal(5)
	assert_int(diagram.count_of({"field": 0, "divisor": 5, "extra": 1})).is_equal(6)
	assert_int(diagram.count_of({"field": 0, "divisor": 10, "round": "ceil"})).is_equal(3)
	assert_int(diagram.count_of({"field": 0, "divisor": 10})).is_equal(2)
	assert_int(diagram.count_of({"field": 0, "add": -30, "divisor": 5})).is_equal(0)           # never negative
	assert_int(diagram.count_of({"field": 0, "add": 5, "divisor": 5})).is_equal(6)
	# the divisor can come from a table, picked by another field
	assert_int(diagram.count_of({"field": 1, "divisor_table": {"field": 2, "table": [1, 1, 1, 1, 100]}})).is_equal(3)


func test_numbers_are_printed_into_a_box_and_centred_in_it() -> void:
	var diagram := _drawn([PANEL, {"text": {"field": 0}, "box": [118, 106], "y": 90}, {"text": {"field": 1}, "box": [300, 50], "y": 90}], [7.5, 12.5, 0], 0, 1)
	assert_array(diagram.texts()).contains_exactly(["7.5", "12.5"])
	var item: DiagramItem = diagram.items.filter(func(i: DiagramItem) -> bool: return i.kind == DiagramItem.Kind.TEXT)[0]
	assert_int(item.align).is_equal(DiagramItem.Align.CENTER)
	assert_float(item.position.x).is_equal(118.0)
	assert_float(item.anchor_width).is_equal(106.0)
	assert_float(item.position.y).is_equal(90.0)


func test_text_can_be_a_fixed_word_cut_to_a_whole_number_suffixed_or_right_aligned() -> void:
	var diagram := _drawn([PANEL,
			{"text": {"literal": "5000"}, "box": [10, 40], "y": 20},
			{"text": {"field": 0, "format": "int"}, "box": [10, 40], "y": 40},
			{"text": {"field": 0, "suffix": " degrees"}, "box": [10, 40], "y": 60},
			{"text": {"field": 1}, "right": 200, "y": 80}], [7.5, 3.5, 0], 0, 1)
	assert_array(diagram.texts()).contains_exactly(["5000", "8", "7.5 degrees", "3.5"])      # (a number is rounded to the nearest whole, a tie to the even)
	var right: DiagramItem = diagram.items[-1]
	assert_int(right.align).is_equal(DiagramItem.Align.RIGHT)
	assert_float(right.position.x).is_equal(200.0)


func test_a_lookup_picks_the_picture_of_the_field_and_a_divisor_scales_the_field() -> void:
	var needles := [{"pic": 1, "pos": [10, 10]}, {"pic": 2, "pos": [20, 10]}, {"pic": 3, "pos": [30, 10], "flip": true}]
	var spec := [PANEL, {"pos": [0, 0], "lookup": {"field": 0, "divisor": 45, "entries": needles}}]
	var diagram := _drawn(spec, [90, 0, 0])
	assert_int(diagram.items.size()).is_equal(2)
	assert_int(diagram.items[1].pic).is_equal(3)
	assert_vector(diagram.items[1].position).is_equal(Vector2(30, 10))
	assert_bool(diagram.items[1].flip).is_true()
	assert_int(_drawn(spec, [0, 0, 0]).items[1].pic).is_equal(1)
	assert_int(_drawn(spec, [900, 0, 0]).items[1].pic).is_equal(3)                          # beyond the table: its last entry
	var exact := [PANEL, {"pos": [0, 0], "lookup": {"field": 0, "divisor": 45, "exact": true, "entries": needles}}]
	assert_int(_drawn(exact, [90, 0, 0]).items.size()).is_equal(2)
	assert_int(_drawn(exact, [100, 0, 0]).items.size()).is_equal(1)                       # "exact": nothing is drawn unless the field divides evenly


func test_the_hour_of_a_clock_reading_ignores_the_minutes() -> void:
	assert_int(DiagramBase.hour_on_12_hour_clock(1800)).is_equal(6)
	assert_int(DiagramBase.hour_on_12_hour_clock(2400)).is_equal(12)
	assert_int(DiagramBase.hour_on_12_hour_clock(100)).is_equal(1)
	assert_int(DiagramBase.hour_on_12_hour_clock(1230)).is_equal(0)                       # 12:30 gives hour 0: the table's first and last hand are the same picture
	assert_int(DiagramBase.hour_on_12_hour_clock(1500)).is_equal(3)
	var hands := [{"pic": 1}, {"pic": 2}, {"pic": 3}, {"pic": 4}]
	var diagram := _drawn([PANEL, {"pos": [0, 0], "lookup": {"field": 0, "pre": "hour12", "entries": hands}}], [200, 0, 0])
	assert_int(diagram.items[1].pic).is_equal(3)                                           # 2 o'clock


func test_a_picture_number_can_come_from_the_record() -> void:
	var by_add := _drawn([PANEL, {"pic": {"field": 0, "add": 2}, "pos": [50, 50]}], [3, 0, 0])
	assert_int(by_add.items[1].pic).is_equal(5)
	var by_table := _drawn([PANEL, {"pic": {"field": 0, "table": [7, 8, 9, 10]}, "pos": [50, 50]}], [2, 0, 0])
	assert_int(by_table.items[1].pic).is_equal(9)


func test_a_picture_can_be_mirrored_by_a_field_of_the_record() -> void:
	assert_bool(_drawn([PANEL, {"pic": 3, "pos": [5, 5], "flip_field": 0}], [1, 0, 0]).items[1].flip).is_true()
	assert_bool(_drawn([PANEL, {"pic": 3, "pos": [5, 5], "flip_field": 0}], [0, 0, 0]).items[1].flip).is_false()


func test_an_entry_can_be_drawn_for_some_levels_or_some_values_of_a_field_only() -> void:
	var spec := [PANEL, {"pic": 3, "pos": [5, 5], "when": {"levels": [1, 3]}}, {"pic": 4, "pos": [5, 5], "when": {"field": 0, "ge": 10}},
			{"pic": 5, "pos": [5, 5], "when": {"field": 0, "eq": 4}}, {"pic": 6, "pos": [5, 5], "when": {"field": 0, "lt": 5}}, {"pic": 7, "pos": [5, 5], "when": {"field": 0, "ne": 4}}]
	var shown := func(diagram: DiagramBase) -> Array:
		return diagram.items.map(func(i: DiagramItem) -> int: return i.pic)
	assert_array(shown.call(_drawn(spec, [4, 0, 0], 0))).is_equal([0, 5, 6])
	assert_array(shown.call(_drawn(spec, [4, 0, 0], 1))).is_equal([0, 3, 5, 6])
	assert_array(shown.call(_drawn(spec, [12, 0, 0], 3))).is_equal([0, 3, 4, 7])


# --- the ballast panel (dev's types 28 and 29) ----------------------------------------------

func test_ballast_panel_toggles_weights_and_sums_them() -> void:
	var panel := _diagram(28, 0, 0) as BallastPanelDiagram                  # dev: the weights 1, 2, 3 ... 10, target 4
	assert_int(panel.slot_count()).is_equal(10)
	assert_int(panel.pictures(3).size()).is_equal(0)
	panel.toggle(1)
	panel.toggle(6)
	assert_int(panel.pictures(3).size()).is_equal(2)                         # two weights switched on (the data's "selected" picture)
	assert_int(panel.sum()).is_equal(2 + 7)
	assert_int(panel.selected).is_equal((1 << 1) | (1 << 6))
	panel.toggle(1)
	assert_int(panel.sum()).is_equal(7)
	assert_int(panel.button_at(panel.slot_position(7) + Vector2(5, 5))).is_equal(7)
	var done_at := Vector2(panel.spec["total"]["pos"][0], panel.spec["total"]["pos"][1])
	assert_int(panel.button_at(done_at + Vector2(5, 5))).is_equal(panel.slot_count())    # the Done button follows the weights
	assert_int(panel.button_at(Vector2(2, 2))).is_equal(-1)


func test_ballast_panel_reports_the_selection_and_the_hold_when_done_is_pressed() -> void:
	var panel := _diagram(29, 0, 0) as BallastPanelDiagram
	var reported := []
	panel.done_pressed.connect(func(mask: int, hold_ticks: int) -> void: reported.append([mask, hold_ticks]))
	panel.toggle(0)
	panel._press(panel.slot_count())
	assert_array(reported).contains_exactly([[1, int(panel.spec["total"]["hold_ticks"])]])    # the weights, and how long the pressed button stays (data)
	assert_str(panel.texts()[0]).is_equal(str(panel.values()[0]))


func test_ballast_labels_follow_the_level() -> void:
	# dev's panel modes by level are 0, 1, 2, 1: the weights 1 .. 10, the powers of two, the tens
	assert_array(Array(_diagram(28, 0, 0).texts().slice(0, 4))).contains_exactly(["1", "2", "3", "4"])
	assert_array(Array(_diagram(28, 1, 0).texts().slice(0, 4))).contains_exactly(["1", "2", "4", "8"])
	assert_array(Array(_diagram(28, 2, 0).texts().slice(0, 4))).contains_exactly(["10", "20", "30", "40"])
