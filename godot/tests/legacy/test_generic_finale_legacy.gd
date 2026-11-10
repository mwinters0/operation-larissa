class_name TestGenericFinaleLegacy
extends GdUnitTestSuite
## (The legacy half: the original's campaigns keep their closing scenes and their text names. The generic finale: tests/engine/test_generic_finale.gd.)
## Teaches: the original's two campaigns have closing scenes of their own and keep their text names; every other campaign gets the generic finale.

## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass

func test_the_originals_still_get_their_own_scenes() -> void:
	assert_str(Catalog.campaign(&"voyager").closing_scene).is_equal(&"voyager")
	assert_str(Catalog.campaign(&"expert").closing_scene).is_equal(&"expert")
	assert_str(Catalog.campaign(&"voyager").finale_text).is_equal("")


func test_the_originals_keep_their_text_names() -> void:
	var voyager := Catalog.campaign(&"voyager")
	assert_str(voyager.display_title()).is_equal(Catalog.text(&"game_voyager"))
	assert_str(voyager.supply_message_text(0)).is_equal(Catalog.text(&"supply_message_0"))
	assert_str(voyager.log_entry_text(3)).is_equal(Catalog.text(&"log_entry_2"))
