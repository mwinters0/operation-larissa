class_name TestProblemTextsLegacy
extends GdUnitTestSuite
## The ORIGINAL's problem wording: the texts of its types filled with its records (sonar, the ballast and lock worked solutions, the canister's
## underlined hint). The rules that fill any pack's texts are tested on dev in tests/engine/test_problem_texts.gd.


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_sonar_wording_matches_the_record() -> void:
	# Sonar level 0 record 0: 10 miles at 2 MPH, answer 5 hours.
	var p := ProblemFactory.make(3, 0, null, 0)
	assert_str(p.prompt).contains("10 miles ahead").contains("2 MPH").contains("hours")
	assert_str(p.solution).contains("10 / 2 = 5")
	assert_str(p.hint).contains("Divide the distance by the speed")


# --- G20: the ballast worked solution (Prob28_SolutionSubst 0x41937f) --------------------------------

## Slots {2} .. {11} take the weights from bit 9 down to bit 0, so the largest comes first; the first one has two
## leading spaces instead of "+ ", every weight ends with a space, and {1} is "= " and the amount.
func test_the_ballast_solution_lists_the_weights_largest_first() -> void:
	var p := ProblemFactory.make(28, 1, null, 0)                  # 62 = 2 + 4 + 8 + 16 + 32
	assert_str(p.solution).ends_with("\n  32 + 16 + 8 + 4 + 2 = 62")
	p = ProblemFactory.make(28, 0, null, 0)                        # 15 = 5 + 10 (stored mask 96)
	assert_str(p.solution).ends_with("\n  10 + 5 = 15")
	p = ProblemFactory.make(29, 1, null, 0)                        # the decrease panel has its own wording
	assert_str(p.solution).ends_with("\n  32 + 16 + 8 + 4 = 60")


# --- G22: the lock's worked solution (LockShowSolution 0x4223db) -------------------------------------

func _lock_solution(level: int, index: int, stage: int) -> String:
	var type := Catalog.problem_type(0)
	return ProblemTexts.lock_solution(type, type.record(level, index), stage)


## Text f0 + 4 with parentheses and the intermediate results f10 / f11 (stage 1) or f21 / f22 (stage 2).
func test_the_lock_solution_has_the_form_of_its_label_set() -> void:
	# f0 0-2 (whole numbers, quarters 25/50/75 and tens): "(a op b) op c" and f10
	assert_str(_lock_solution(0, 0, 0)).is_equal("Combination number:\n(7 + 9) - 5\n= 16 - 5\n= 11")
	assert_str(_lock_solution(0, 0, 1)).is_equal("Combination number:\n(6 - 2) + 8\n= 4 + 8\n= 12")
	assert_str(_lock_solution(0, 5, 0)).is_equal("Combination number:\n(40 + 20) - 30\n= 60 - 30\n= 30")
	assert_str(_lock_solution(0, 10, 1)).is_equal("Combination number:\n(50 + 75) + 25\n= 125 + 25\n= 150")
	# f0 4, 5, 8: four operands, f10 and f11
	assert_str(_lock_solution(1, 0, 0)).is_equal("Combination number:\n(75 + 75) + 25 + 50\n= (150 + 25) + 50\n= 175 + 50\n= 225")
	assert_str(_lock_solution(1, 5, 1)).is_equal("Combination number:\n(20 + 60) - 50 + 30\n= (80 - 50) + 30\n= 30 + 30\n= 60")
	assert_str(_lock_solution(2, 0, 0)).is_equal("Combination number:\n(0.5 + 0.7) + 0.6 - 0.2\n= (1.2 + 0.6) - 0.2\n= 1.8 - 0.2\n= 1.6")
	# f0 6: tenths as fractions, the answer slot's own "n/10" and the decimal answer label
	assert_str(_lock_solution(2, 5, 0)).is_equal("Combination number:\n4/10 + 5/10\n= 9/10\n= 0.9")
	# f0 7: decimals, the answer slot's own "0.n" and the fraction label
	assert_str(_lock_solution(2, 8, 0)).is_equal("Combination number:\n0.3 + 0.2\n= 0.5\n= 5/10")
	# f0 11: hundredths and percent
	assert_str(_lock_solution(3, 0, 0)).is_equal("Combination number:\n0.10 + 0.20\n= 0.30\n= 30%")
	# f0 10 and 9: the stored intermediate (an unreduced fraction) and the reduced answer
	assert_str(_lock_solution(3, 5, 0)).is_equal("Combination number:\n5/12 - 2/12\n= 3/12\n= 1/4")
	assert_str(_lock_solution(3, 10, 0)).is_equal("Combination number:\n2 x 1/4\n= 2/4\n= 1/2")
	assert_str(_lock_solution(3, 11, 1)).is_equal("Combination number:\n1/2 x 2/3\n= 2/6\n= 1/3")


## Form 3 (twelfths): the template has no slot for the result, only the underline toggle (a raw 0xFF) and two spaces.
func test_the_twelfths_form_ends_in_an_underlined_blank() -> void:
	assert_str(_lock_solution(1, 10, 0)).is_equal("Combination number:\n5/12 - 2/12\n= [u]  [/u]")


## G35: the data canister's hint ends in `N + ` and the underlined characters `= `, `t `, `c `, `s ` (texts 10198-10201 =
## type 1 positions 5-8): the byte after the raw 0xFF is text, there is no width byte and no `_____`.
func test_the_canister_hints_underline_the_characters_after_the_0xff() -> void:
	var type := Catalog.problem_type(1)
	var tails := ["+ [u]= [/u]", "+ [u]t [/u]", "- [u]c [/u]", "x [u]s [/u]"]
	for i in 4:
		var text := TextTemplate.render(type.text_at(5 + i), {0: "7", 4: "2"})
		assert_str(text).ends_with("\n7 " + tails[i])
		assert_bool(text.contains("_")).is_false()
	# the generated hints of real records: level 3 uses text 5, level 0 the texts 6-8 (by pattern)
	assert_str(ProblemFactory.make(1, 3, null, 0).hint).ends_with(" + [u]= [/u]")
	assert_str(ProblemFactory.make(1, 0, null, 0).hint).ends_with(" + [u]t [/u]")


## Form 3 of the lock's worked solution keeps its underlined blank (two underlined spaces after "= ", G22 / G35).
func test_the_lock_form_3_blank_is_two_underlined_spaces() -> void:
	assert_str(_lock_solution(1, 10, 0)).ends_with("\n= [u]  [/u]")


func test_every_lock_record_has_a_complete_solution_for_both_numbers() -> void:
	var type := Catalog.problem_type(0)
	var forms := {}
	for level in 4:
		for n in type.record_count(level):
			var r := type.record(level, n)
			forms[r.int_at(0)] = true
			for stage in 2:
				var text := ProblemTexts.lock_solution(type, r, stage)
				assert_bool(TextTemplate.has_unfilled_slot(text)).is_false()
				assert_str(text).starts_with("Combination number:\n")
	assert_int(forms.size()).is_equal(12)                          # all twelve forms occur in the stored records
