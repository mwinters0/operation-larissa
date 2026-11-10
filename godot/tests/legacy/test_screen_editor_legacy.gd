class_name TestScreenEditorLegacy
extends GdUnitTestSuite
## The screen editor on the original: all 384 screens encode back to the original's records (hash by hash), and the status line compares a screen with the original.
## The editor's rules, on a screen of dev's, are in `tests/engine/test_screen_editor.gd`.


func test_all_384_original_screens_encode_back_to_the_original_record() -> void:
	var problems: Array[String] = []
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		for m in Catalog.SCREENS_PER_SECTOR:
			var editor := auto_free(ScreenEditor.new()) as ScreenEditor
			editor.data_dir = LegacyPack.SECTORS_DIR                 # (the authoring files of the project's legacy folder, whatever pack is played)
			editor.sector = s
			editor.screen = m
			editor.reload()
			var built := editor.build()
			if not built.problems.is_empty():
				problems.append("sector %d screen %d: %s" % [s, m, built.problems[0]])
				continue
			var encoded := built.screen.encode()
			if FixtureHash.sha256_hex(encoded) != ScreenFile.original_sha256(s, m):
				var original := ScreenFile.original_record(s, m)
				problems.append("sector %d screen %d: does not encode to the original record%s" % [s, m, (": " + ScreenData.first_difference(original, encoded)) if not original.is_empty() else " (run tools/import/import_all.py on your copy of the game to see where)"])
			elif editor.is_dirty():
				problems.append("sector %d screen %d: dirty right after loading" % [s, m])
			editor.free()
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()



func test_an_original_screen_says_whether_it_is_the_same_as_the_original() -> void:
	var editor := auto_free(ScreenEditor.new()) as ScreenEditor
	editor.data_dir = LegacyPack.SECTORS_DIR                 # (the authoring files of the project's legacy folder, whatever pack is played)
	editor.sector = 3
	editor.screen = 2
	editor.reload()
	assert_str(editor.status).contains("same as the original")


func test_a_changed_original_screen_differs_from_the_original() -> void:
	var editor := auto_free(ScreenEditor.new()) as ScreenEditor
	editor.data_dir = LegacyPack.SECTORS_DIR                 # (the authoring files of the project's legacy folder, whatever pack is played)
	editor.sector = 0
	editor.screen = 5
	editor.reload()
	(editor.get_node("Walls") as TileMapLayer).set_cell(Vector2i(3, 9), Catalog.zone(Catalog.sector(0).zone).tile_source_id, Vector2i(2, 0))
	editor.refresh()
	assert_str(editor.status).contains("differs from the original")
