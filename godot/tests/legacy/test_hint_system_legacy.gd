class_name TestHintSystemLegacy
extends GdUnitTestSuite
## The original's wording of the hints (strings 10167-10173). The hint set itself is tested on dev in tests/engine/test_hint_system.gd.


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_the_controls_hint_names_the_space_bar() -> void:
	assert_str(HintSystem.text_for(HintSystem.CONTROLS)).contains("Space")
