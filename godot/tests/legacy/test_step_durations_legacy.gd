class_name TestStepDurationsLegacy
extends GdUnitTestSuite
## Teaches: the lengths of the steps that hold up play, as the original had them, in ticks of its 73 Hz timer (the rules and where they get them from:
## tests/engine/test_step_durations.gd).


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_the_original_steps_take_the_original_ticks() -> void:
	assert_int(CanisterLog.scan_ticks()).is_equal(240)
	assert_int(StationSequence.launch().ticks).is_equal(30)                       # game ticks of 6/73 s
	assert_int(StationSequence.dock().ticks).is_equal(31)
	assert_int(StationSequence.balloon().ticks).is_equal(44)
	assert_int(SimWorld.dissolve_length()).is_equal(21)
	assert_int(SceneRouter.fade_ticks()).is_equal(13)                             # the port's 0.18 s was 13.14 ticks
	assert_int(SurfaceShipScreen.wait_ticks()).is_equal(1460)
	assert_int(ProblemFlow.message_ticks()).is_equal(146)
	assert_int(CalculatorModel.key_flash_ticks()).is_equal(12)


func test_the_ballast_hold_is_73_ticks_in_the_panels_data() -> void:
	for type_id in [28, 29]:
		assert_int(int(Catalog.problem_type(type_id).diagram["total"]["hold_ticks"])).is_equal(73)
