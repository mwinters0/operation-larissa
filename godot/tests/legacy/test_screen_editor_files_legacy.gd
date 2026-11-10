class_name TestScreenEditorFilesLegacy
extends GdUnitTestSuite
## The original's screen records as the screen editor reads them back: the importer's bytes of every screen of sectors 0-31 (git-ignored, from the user's own copy of
## the game) and the committed hashes of them. The files the editor writes, on dev's sectors, are in `tests/engine/test_screen_editor_files.gd`.


func test_the_original_records_are_readable_when_the_importer_wrote_them() -> void:
	if not ScreenFile.has_original_bytes():
		prints("SKIPPED: %s is missing; run tools/import/import_all.py on your copy of the game" % ScreenFile.ORIGINAL_BYTES_PATH)
		assert_bool(ScreenFile.original_record(0, 0).is_empty()).is_true()
		return
	assert_int(ScreenFile.original_record(0, 0).size()).is_equal(ScreenData.RECORD_SIZE)
	assert_int(ScreenFile.original_record(31, 11).size()).is_equal(ScreenData.RECORD_SIZE)
	assert_bool(ScreenFile.original_record(32, 0).is_empty()).is_true()
	assert_str(FixtureHash.sha256_hex(ScreenFile.original_record(31, 11))).is_equal(ScreenFile.original_sha256(31, 11))


func test_the_hashes_of_the_original_records_are_readable_without_the_bytes() -> void:
	assert_int(ScreenFile.original_sha256(0, 0).length()).is_equal(64)
	assert_int(ScreenFile.original_sha256(31, 11).length()).is_equal(64)
	assert_str(ScreenFile.original_sha256(32, 0)).is_empty()
	assert_str(ScreenFile.original_sha256(0, 12)).is_empty()
