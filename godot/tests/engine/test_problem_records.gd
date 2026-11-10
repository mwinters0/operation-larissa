class_name TestProblemRecords
extends GdUnitTestSuite
## Teaches: testing a pack's data against the rules of the engine that reads it. Every stored problem of the chain's pack must be answerable: the
## stored answer, written out and typed back, is accepted by `AnswerChecker`; a lock program evaluates to its answer label; a ballast record's selection
## sums to its target. (That the original's answers are the right arithmetic is tests/legacy/test_problem_records_legacy.gd.)

const LEVELS := 4


func test_every_stored_answer_is_accepted_when_typed_back() -> void:
	for type_id in Catalog.PROBLEM_TYPE_COUNT:
		var type := Catalog.problem_type(type_id)
		for level in LEVELS:
			for n in type.record_count(level):
				var r := type.record(level, n)
				var instance := ProblemFactory.make(type_id, level, null, n)
				if instance.expected == null:
					continue
				var typed := NumberValue.parse(instance.expected.to_text().trim_suffix("%"))
				assert_object(typed).override_failure_message("type %d: cannot type %s" % [type_id, instance.expected.to_text()]).is_not_null()
				assert_bool(instance.check(typed)).override_failure_message(
						"type %d level %d record %d answer %s" % [type_id, level, n, instance.expected.to_text()]).is_true()
				assert_bool(r != null).is_true()


func test_lock_programs_evaluate_to_their_answer_label() -> void:
	var type := Catalog.problem_type(0)
	var count := 0
	for level in LEVELS:
		for n in type.record_count(level):
			for stage in 2:
				var program := LockProgram.from_record(type, type.record(level, n), stage)
				assert_float(program.evaluate()).override_failure_message(
						"lock level %d record %d stage %d: %s" % [level, n, stage, program.expression()]
						).is_equal_approx(program.answer_value, 1e-9)
				count += 1
	assert_int(count).is_equal(type.records.size() * 2)          # (two numbers a record)
	assert_int(count).is_greater(0)


func test_water_pressure_accepts_anything_strictly_between_the_bounds() -> void:
	var type := Catalog.problem_type(4)
	for level in [1, 2, 3]:
		for n in type.record_count(level):
			var r := type.record(level, n)
			var low := r.value_at(2)
			var high := r.value_at(3)
			assert_float(low).is_less(high)
			assert_float(r.value_at(1)).is_between(low, high)                 # (level 0's exact answer sits inside the bounds)
			var mid := NumberValue.from_double((low + high) / 2.0)
			assert_bool(AnswerChecker.check(type, level, r, mid)).is_true()
			assert_bool(AnswerChecker.check(type, level, r, NumberValue.from_double(low))).is_false()
			assert_bool(AnswerChecker.check(type, level, r, NumberValue.from_double(high))).is_false()
	# level 0 is exact
	var r0 := type.record(0, 0)
	assert_bool(AnswerChecker.check(type, 0, r0, r0.number_at(1))).is_true()
	assert_bool(AnswerChecker.check(type, 0, r0, NumberValue.from_double(r0.value_at(1) + 1.0))).is_false()


func test_ballast_stored_selection_sums_to_the_target() -> void:
	for type_id in [28, 29]:
		var type := Catalog.problem_type(type_id)
		for level in LEVELS:
			for n in type.record_count(level):
				var r := type.record(level, n)
				assert_bool(AnswerChecker.check_selection(type, level, r, r.int_at(1))).override_failure_message(
						"type %d level %d record %d" % [type_id, level, n]).is_true()
				assert_bool(AnswerChecker.check_selection(type, level, r, 0)).is_false()
