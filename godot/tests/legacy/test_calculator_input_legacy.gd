class_name TestCalculatorInputLegacy
extends GdUnitTestSuite
## The original's words in the calculator's notice dialog (`ShowCalcNoticeDialog` 0x420d8f): title 11042 "Calculator Error" + message 10174-10176, or
## title 11044 "Fraction Mode" + text 11043. Checks the legacy pack's texts; the dialog's mechanics are tested on dev (tests/engine/test_calculator_input.gd).

const NOTICE := CalculatorModel.Notice


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_the_dialog_has_the_originals_words() -> void:
	var divide := CalcNoticeDialog.texts_for(NOTICE.DIVIDE_BY_ZERO)
	assert_str(divide[0]).is_equal("Calculator Error")
	assert_str(divide[1]).contains("cannot").contains("zero")
	assert_str(CalcNoticeDialog.texts_for(NOTICE.TOO_LARGE)[1]).contains("too large")
	var operator := CalcNoticeDialog.texts_for(NOTICE.FRACTION_OPERATOR)
	assert_str(operator[1]).contains("operator").contains("press / and")        # the fraction-bar key picture is written out
	var help := CalcNoticeDialog.texts_for(NOTICE.FRACTION_HELP)
	assert_str(help[0]).is_equal("Fraction Mode")
	assert_str(help[1]).contains("fraction mode").contains("press /").contains("Enter").contains("C to exit")
