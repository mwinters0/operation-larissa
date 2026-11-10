class_name TestProblemTexts
extends GdUnitTestSuite
## Teaches: a "smoke test over all the data". Every stored problem of every type and level
## must produce readable text: no `{k}` slot left unfilled, no leftover control characters,
## and a prompt, hint and solution that are not empty. The original's own wording (its sonar, its worked solutions of the lock and the ballast
## panels) is tests/legacy/test_problem_texts_legacy.gd.

const K = preload("res://tests/engine/problem_kit.gd")


func test_every_problem_has_complete_text() -> void:
	var count := 0
	for type_id in Catalog.PROBLEM_TYPE_COUNT:
		var type := Catalog.problem_type(type_id)
		for level in 4:
			for n in type.record_count(level):
				var p := ProblemFactory.make(type_id, level, null, n)
				var where := "type %d level %d record %d" % [type_id, level, n]
				for part in {"prompt": p.prompt, "hint": p.hint, "solution": p.solution}:
					var text: String = {"prompt": p.prompt, "hint": p.hint, "solution": p.solution}[part]
					assert_str(text).override_failure_message("%s: empty %s" % [where, part]).is_not_empty()
					assert_bool(TextTemplate.has_unfilled_slot(text)).override_failure_message(
							"%s: unfilled slot in %s: %s" % [where, part, text]).is_false()
					assert_bool(text.contains("ÿ")).override_failure_message("%s: answer marker left in %s" % [where, part]).is_false()
				count += 1
	var records := 0
	for type_id in Catalog.PROBLEM_TYPE_COUNT:
		records += Catalog.problem_type(type_id).records.size()
	assert_int(count).is_equal(records)
	assert_int(count).is_greater(0)


func test_levels_without_problems_return_null() -> void:
	# Dev's type 3 has no records at level 2 (dev_problems.NO_RECORDS), and says so in `levels_available` as well.
	assert_object(ProblemFactory.make(3, 2)).is_null()
	assert_int(Catalog.problem_type(3).record_count(2)).is_equal(0)
	assert_array(Array(Catalog.problem_type(3).levels_available)).is_equal([1, 1, 0, 1])
	assert_object(ProblemFactory.make(3, 1)).is_not_null()


func test_every_trigger_slot_has_a_usable_problem_at_every_level() -> void:
	# The table names two candidate types per (slot, level). A pack may name a type that has no problems at that
	# level (dev's type 3 has none at level 2); `ProblemFactory.for_trigger_slot` then falls back to the other
	# candidate. At least one of the two must exist, always.
	var table := Catalog.trigger_table()
	var unusable_picks := 0
	for slot in range(1, TriggerTable.SLOTS):          # slot 0 is the combination lock
		for level in 4:
			var usable := 0
			for pick in 2:
				var type_id := table.type_for(slot, level, pick)
				if Catalog.problem_type(type_id).record_count(level) > 0:
					usable += 1
				else:
					unusable_picks += 1
			assert_int(usable).override_failure_message("slot %d level %d has no usable type" % [slot, level]).is_greater(0)
			assert_object(ProblemFactory.for_trigger_slot(slot, level)).is_not_null()
	assert_int(unusable_picks).is_greater(0)             # (dev has a gap, so the fallback is walked)
	assert_int(unusable_picks).is_less(TriggerTable.SLOTS)   # a few, not a systematic gap


func test_temperature_signed_bytes_print_as_negative_numbers() -> void:
	# The thermometer type stores signed bytes: -10 F, +35 -> 25 (the test's own record in the pack's type 12)
	var type := K.with_records(12, [PackedInt64Array([-10, 35, 25])])
	var p := ProblemInstance.build(type, 0, 0)
	assert_int(p.record.int_at(0)).is_equal(-10)
	assert_str(p.solution).contains("-10 + 35 = 25")
	assert_str(ProblemTexts.describe(type, 0, p.record).prompt_slots[0]).is_equal("35")


func test_the_data_canister_problem_carries_the_sectors_log_entry() -> void:
	var p := ProblemFactory.for_canister(Catalog.sector(0), 0)
	var campaign := Catalog.campaign_of_sector(0)
	assert_str(p.success).is_equal(campaign.log_entry_text(campaign.log_newest(0)))
	assert_str(p.success).is_not_empty()
	assert_int(p.trigger_slot).is_equal(1)
	assert_str(p.title).is_equal(p.type.title)


# --- G20: the ballast worked solution (Prob28_SolutionSubst 0x41937f) --------------------------------

func test_ballast_solution_slots_have_the_original_spacing() -> void:
	var slots := ProblemTexts.ballast_solution_slots(PackedStringArray(["1", "2", "4", "8", "16", "32", "64", "128", "256", "512"]), 0b1000000101, "517")
	assert_str(slots[1]).is_equal("= 517")
	assert_str(slots[2]).is_equal("  512 ")                       # bit 9
	assert_str(slots[3]).is_equal("")
	assert_str(slots[9]).is_equal("+ 4 ")                         # bit 2
	assert_str(slots[11]).is_equal("+ 1 ")                        # bit 0


## The `[u]` markup is the only BBCode: no stored problem text has a `[`, so the problem screen can parse every text.
func test_no_stored_problem_text_contains_a_bracket() -> void:
	for type_id in Catalog.PROBLEM_TYPE_COUNT:
		for text in Catalog.problem_type(type_id).texts:
			assert_bool(text.contains("[")).is_false()


## The problem screen draws it: the label parses BBCode, so the underline markup is not shown as characters.
func test_the_problem_screen_does_not_show_the_underline_markup() -> void:
	var screen := scene_runner("res://src/problems/problem_screen.tscn").scene() as ProblemScreen
	screen._write_message("1 + [u]= [/u]")
	assert_bool(screen.text_label.bbcode_enabled).is_true()
	assert_str(screen.text_label.get_parsed_text()).is_equal("1 + = ")


# --- the lock's decimal labels (DoCombinationLock 0x421780 loads "0.5", "0.50", not the EXE's " .5") -------------

## A copy of the pack's lock type whose texts for the forms 7 and 11 are just their {3} slot, and whose first record has label set `form`
## and answer slot `answer_slot` (the records' field 5, the stage's fifth program byte).
func _lock_solution_of(form: int, answer_slot: int) -> String:
	var type := Catalog.problem_type(0).duplicate() as ProblemType
	type.texts = type.texts.duplicate()
	type.texts[4 + form] = "{3}"
	var flat := PackedInt64Array(type.records[0])
	flat[0] = form
	flat[5] = answer_slot
	type.records = [flat]
	type.record_levels = PackedInt32Array([0])
	return ProblemTexts.lock_solution(type, type.record(0, 0), 0)


func test_the_tenths_solution_shows_the_loaded_label() -> void:
	for slot in 8:
		assert_str(_lock_solution_of(7, slot)).is_equal("0.%d" % (slot + 2))                 # slot 7 is the string 11227, "0.9"


func test_the_hundredths_solution_shows_the_loaded_label() -> void:
	for slot in 7:
		assert_str(_lock_solution_of(11, slot)).is_equal("0.%d0" % (slot + 2))


## Deliberate deviation: the original's buffer for form 11's answer slot 7 holds string 11245 ("1.9"), a worked solution that ends
## "= 1.9" for 90 %; the port shows "0.90" there like the other slots (docs/port/DESIGN.md).
func test_the_hundredths_solution_of_90_percent_is_0_90_deliberate_deviation() -> void:
	assert_str(_lock_solution_of(11, 7)).is_equal("0.90")


func test_a_decimal_wheel_label_is_read_as_its_number() -> void:
	assert_float(LockProgram.label_to_value("0.5")).is_equal(0.5)
	assert_float(LockProgram.label_to_value("0.50")).is_equal(0.5)
	assert_float(LockProgram.label_to_value("1.9")).is_equal(1.9)
