class_name TestTriggerLegacy
extends GdUnitTestSuite
## The ORIGINAL's first math trigger: sector 0, screen 5, at window (160, 70) with slot 29 (flags 0xA1: armed and re-armed whenever the screen is
## entered). The triggers' behaviour is tested on a dev test sector in tests/engine/test_trigger.gd.


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_the_original_data_has_the_trigger_the_old_tests_assumed() -> void:
	var trigger := Catalog.sector(0).screens[5].triggers[0]
	assert_vector(trigger.pos).is_equal(Vector2i(160, 70))
	assert_int(trigger.slot).is_equal(29)
	assert_bool(trigger.armed).is_true()
	assert_bool(trigger.rearm_on_enter).is_true()
	assert_int(trigger.flags & 15).is_equal(1)
	assert_int(trigger.flags).is_equal(0xA1)
