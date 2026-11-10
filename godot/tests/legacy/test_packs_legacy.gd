class_name TestPacksLegacy
extends GdUnitTestSuite
## The legacy pack among the packs: it is a folder of the project like any other, so the pack list offers it. (The lookups through a pack on any base are
## in tests/engine/test_packs.gd.)


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_the_legacy_pack_is_offered_like_any_pack() -> void:
	var ids: Array = Packs.available().map(func(p: Pack) -> StringName: return p.id)
	assert_array(ids).contains([LegacyPack.ID])
	assert_str(PackShelf.base_id()).is_equal(LegacyPack.ID)              # (the legacy suite runs on it)
	assert_array(Packs.chain_ids()).is_equal([LegacyPack.ID])
