class_name TestCombinationLockLegacy
extends GdUnitTestSuite
## The ORIGINAL's first combination lock (type 0, level 0, record 0: 7 + 9 - 5 = 11, the answer wheel's label 0) and its words. The controller's
## behaviour is tested on dev's lock in tests/engine/test_combination_lock.gd.


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_the_first_lock_of_the_original_is_7_plus_9_minus_5() -> void:
	var problem := ProblemFactory.make(0, 0, null, 0)
	var program := LockProgram.from_record(problem.type, problem.record, 0)
	assert_str(program.expression()).is_equal("7 + 9 - 5")
	assert_str(program.answer_label).is_equal("11")
	assert_int(program.answer_slot).is_equal(0)


func test_the_originals_lock_words() -> void:
	var type := Catalog.problem_type(0)
	assert_str(type.text_at(0)).contains("To enter the supply station")
	assert_str(type.text_at(1)).contains("directed to ship")
	assert_str(type.text_at(2)).contains("First number accepted")
	assert_str(type.text_at(3)).is_equal("Lock opened.")
	var solution := ProblemTexts.lock_solution(type, type.record(0, 0), 0)
	assert_str(solution).contains("Combination number:").contains("= 11")


## `DoCombinationLock` (0x421780) loads strings 11219-11245 over the decimal label buffers, so the wheels show "0.5", "0.50", not the
## EXE's static " .5" (label sets: operands 7 and 8 tenths, 11 hundredths; answers 6 "0.2" .. "0.9", 8 "1.1" .. "1.8").
func test_the_decimal_wheels_show_the_loaded_labels() -> void:
	var extras := Catalog.problem_type(0).extras
	var tenths := PackedStringArray(["0.1", "0.2", "0.3", "0.4", "0.5", "0.6", "0.7", "0.8"])
	assert_array(Array(extras["operand_labels"]["7"])).is_equal(Array(tenths))
	assert_array(Array(extras["operand_labels"]["8"])).is_equal(Array(tenths))
	assert_array(Array(extras["operand_labels"]["11"])).is_equal(["0.10", "0.20", "0.30", "0.40", "0.50", "0.60", "0.70", "0.80"])
	assert_array(Array(extras["answer_labels"]["6"])).is_equal(["0.2", "0.3", "0.4", "0.5", "0.6", "0.7", "0.8", "0.9"])
	assert_array(Array(extras["answer_labels"]["8"])).is_equal(["1.1", "1.2", "1.3", "1.4", "1.5", "1.6", "1.7", "1.8"])


## No label of any wheel set starts with the EXE's padding.
func test_no_wheel_label_has_the_exes_padding() -> void:
	var extras := Catalog.problem_type(0).extras
	for table: String in ["operand_labels", "answer_labels"]:
		for wheel_set: String in extras[table]:
			for label in extras[table][wheel_set]:
				assert_str(label).is_equal(label.strip_edges())
