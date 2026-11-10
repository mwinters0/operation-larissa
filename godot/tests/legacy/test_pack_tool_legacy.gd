class_name TestPackToolLegacy
extends GdUnitTestSuite
## The pack tool's window and the original game: the campaigns it offers to export leave out the original's two (hard-coded, `Catalog.ORIGINAL_CAMPAIGNS`).
## (The tool itself, on any pack, is in tests/engine/test_pack_tool.gd.)


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_the_window_offers_the_designers_campaigns_but_not_the_originals() -> void:
	var campaigns := PackToolDialog.own_campaign_ids()
	assert_bool(campaigns.has("voyager") or campaigns.has("expert")).is_false()
	for id in campaigns:
		assert_bool(FileAccess.file_exists(Catalog.own_campaign_path(StringName(id)))).is_true()
