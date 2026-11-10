class_name TestProblemRecordsLegacy
extends GdUnitTestSuite
## The ORIGINAL's stored problems (legacy pack) against the rules that made them. Teaches: testing data against the rules that produced it. Every one of the 1276 stored
## problems is checked by recomputing its answer from the OTHER fields of the record with an
## independent formula (what a student would do with a calculator), and the stored answer must
## be accepted by `AnswerChecker`.

const LEVELS := 4


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


## The answer a student would compute from the record, or NAN where the answer is a choice
## (ballast, water-pressure range) and is verified separately.
func _computed(type_id: int, level: int, r: ProblemRecord) -> float:
	match type_id:
		1:      # sequence: last number from the pattern kind f4 and the step f5
			var last := r.value_at(3)
			var step := r.value_at(5)
			match r.int_at(4):
				0: return last + step
				1: return last - step
				2: return last * step
				3: return last / step
				4: return last + step + 3.0           # increments grow by 1: step, +1, +2, then +3
				_: return last + step + 6.0           # grow by 2
		2: return (r.value_at(0) + r.value_at(1) + r.value_at(2) + r.value_at(3) + r.value_at(4) + r.value_at(5)) / 6.0
		3: return r.value_at(0) / r.value_at(1) * (1.0 if level == 0 else 60.0)
		5: return r.value_at(1) * r.value_at(2)
		6: return 5000.0 * r.value_at(0) / 2.0
		7:
			var total := 0.0
			for i in 5:
				total += r.value_at(i)
			return total if level == 0 else total / (1000.0 if level == 2 else 16.0)
		8:
			var given := r.value_at(1)
			return [given * 12.0, given / 3.0, given * 6.0, given / 1000.0, given / 6.0][r.int_at(0)]
		9: return absf(r.value_at(3 if r.int_at(0) == 0 else 4) - r.value_at(1 if r.int_at(0) == 0 else 2))
		10: return (r.value_at(0) - r.value_at(1)) / r.value_at(2)
		11:
			var hours_in_period: float = [1.0, 24.0, 168.0][r.int_at(1)]
			var per_hour: float = [60.0, 1.0, 3600.0][r.int_at(2)]
			return hours_in_period * per_hour / r.int_at(0)
		12: return float(r.int_at(0) - r.int_at(1)) if r.int_at(2) < r.int_at(0) else float(r.int_at(0) + r.int_at(1))
		13: return (r.value_at(0) - 32.0) * 5.0 / 9.0 if r.int_at(2) == 0 else r.value_at(0) * 9.0 / 5.0 + 32.0
		14: return r.value_at(1) / r.value_at(0) if level == 1 else 100.0 * r.value_at(1) / r.value_at(0)
		15:
			var unit: float = [10.0, 100.0, 0.1, 0.01, 0.001][r.int_at(1) - 1]
			return floorf(r.value_at(0) / unit + 0.5 + 1e-9) * unit      # round half up
		16: return r.value_at(0) * r.value_at(6) + r.value_at(1) * r.value_at(7)
		18: return r.value_at(1) * r.value_at(2)
		19: return absf(r.value_at(1) - r.value_at(2))
		20:
			var change := absf(r.value_at(0) - r.value_at(1))
			return change if level == 0 else 100.0 * change / r.value_at(1)
		21:
			match level:
				0: return r.value_at(2) / 2.0 if r.int_at(2) != 0 else r.value_at(0) / 3.0
				1: return r.value_at(3) / 8.0 if r.int_at(3) != 0 else r.value_at(1) / 2000.0
				2: return r.value_at(4) / 16.0
				_: return r.value_at(5) / 48.0
		22: return float(posmod(r.int_at(1) - r.int_at(0) if r.int_at(2) == 0 else r.int_at(1) + r.int_at(0), 360))
		23: return r.value_at(1) * r.value_at(0) / 100.0
		24: return _clock(r)
		25: return r.value_at(7) - 1200.0 if level == 0 else r.value_at(7) * 10.0
		26: return r.value_at(0) * (1.0 - r.value_at(1) / (100.0 if level == 2 else 1.0))
		27: return r.value_at(0) * (1.0 + r.value_at(1) / (100.0 if level == 2 else 1.0))
		30:
			var boxes := r.value_at(0) * r.value_at(1) * r.value_at(2)
			match level:
				2: return 192.0 - r.value_at(3)
				3: return boxes + r.value_at(9)
				_: return boxes
		31: return _search_grid(r)
		32, 33: return r.value_at(0) / r.value_at(1)
	return NAN


## Clock arithmetic on hhmm numbers (f3 = present time, f2 = hours, f0 = distance, f1 = speed).
func _clock(r: ProblemRecord) -> float:
	var present := floori(r.int_at(3) / 100.0) * 60 + r.int_at(3) % 100
	var hours := r.value_at(2)
	var shifted := present + (hours * 60.0 if r.int_at(0) != 0 else -hours * 60.0)
	var minutes := posmod(roundi(shifted), 1440)
	return float(floori(minutes / 60.0) * 100 + minutes % 60)


func _search_grid(r: ProblemRecord) -> float:
	var a := r.value_at(1) * r.value_at(2)
	var b := r.value_at(4) * r.value_at(5)
	match r.int_at(9):
		0: return a
		1: return 100.0 - a
		2: return 2.0 * (r.value_at(1) + r.value_at(2))
		3: return a / 2.0
		4: return 100.0 - a / 2.0
		5: return a + b
		6: return 2.0 * (r.value_at(1) + r.value_at(2)) + 2.0 * (r.value_at(4) + r.value_at(5))
		7: return a / 2.0 + b / 2.0
		8: return a / 2.0 + b
		_: return 100.0 - (a / 2.0 + b)


func test_stored_answers_match_independent_formulas() -> void:
	var checked := 0
	var unsupported: Array[int] = [0, 4, 17, 28, 29]      # checked in their own tests below
	for type_id in Catalog.PROBLEM_TYPE_COUNT:
		var type := Catalog.problem_type(type_id)
		for level in LEVELS:
			for n in type.record_count(level):
				var r := type.record(level, n)
				var want := _computed(type_id, level, r)
				if is_nan(want):
					assert_bool(type_id in unsupported).override_failure_message("no formula for type %d" % type_id).is_true()
					continue
				var stored := r.value_at(type.answer_fields[level])
				var slack := 1e-6
				if type.tolerances.size() > level and type.tolerances[level] > 0.0:
					slack = type.tolerances[level] * (absf(stored) if type.compare_mode == "near" else 1.0)
				assert_float(absf(want - stored)).override_failure_message(
						"type %d level %d record %d: formula %s, stored %s" % [type_id, level, n, want, stored]
						).is_less_equal(slack + 1e-9)
				checked += 1
	assert_int(checked).is_greater(1000)


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
	assert_int(count).is_equal(116)


func test_water_pressure_accepts_anything_strictly_between_the_bounds() -> void:
	var type := Catalog.problem_type(4)
	for level in [1]:
		for n in type.record_count(level):
			var r := type.record(level, n)
			var low := r.value_at(2)
			var high := r.value_at(3)
			assert_float(r.value_at(0) / 2.0).is_between(low, high)           # pressure = depth / 2
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
