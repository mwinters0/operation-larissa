class_name TestPackPictures
extends GdUnitTestSuite
## Teaches: authoring a table from a folder once, so the game never guesses a key from a file name. `PackPictures.write` (`pack_tool --pictures-table=<folder>`) turns a folder of `<kind>/<name>.png` files (what the art templates make) into the pack's `pictures.json`, keeps the
## rows the table has, adds a row only for a file no row names, and says what it left alone.

const ROOT := "user://test_pack_pictures"


func after_test() -> void:
	PackFiles.remove_tree(ROOT)


func _png(rel: String, color := Color.RED) -> void:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	PackFiles.write_bytes("%s/%s" % [ROOT, rel], image.save_png_to_buffer())


func _table() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [ROOT, PictureTable.FILE]))["pictures"]


func test_a_folder_of_kind_and_name_files_becomes_a_table() -> void:
	_png("ui_picture/title_sky.png")
	_png("frame/sub_00.png")
	_png("problem_art/pa_1780.png")
	_png("wallpaper/sea.png")                                         # (not a kind of picture)
	PackFiles.write_text("%s/notes.txt" % ROOT, "x")
	PackFiles.write_text("%s/ui_picture/notes.txt" % ROOT, "x")
	_png("ui_picture/deep/sky.png")                                   # (a folder below a kind: no key)
	var result := PackPictures.write(ROOT)
	assert_bool(result.ok()).is_true()
	assert_dict(_table()).is_equal({"ui_picture/title_sky": "ui_picture/title_sky.png", "frame/sub_00": "frame/sub_00.png", "problem_art/pa_1780": "problem_art/pa_1780.png"})
	assert_array(result.skipped).contains_exactly_in_any_order(["wallpaper/sea.png", "notes.txt", "ui_picture/notes.txt", "ui_picture/deep/sky.png"])
	assert_str(result.text()).contains("3 row(s) added").contains("wallpaper/sea.png is under no kind of picture")
	var table := PictureTable.read(Pack.open(ROOT))
	assert_array(table.problems).is_empty()
	assert_array(table.check(Pack.open(ROOT))).is_empty()


func test_a_table_the_folder_holds_keeps_its_rows_and_gains_only_the_files_no_row_names() -> void:
	_png("ui_picture/title_sky.png")
	_png("art/hi@4x.png")
	_png("frame/sub_00.png")
	PackFiles.write_text("%s/%s" % [ROOT, PictureTable.FILE], JSON.stringify({"format": 1, "pictures": {
		"ui_picture/title_sky": "art/hi@4x.png",                                                    # (a row for the key: the file of the same name is not another row)
		"ui_picture/coral_dawn": {"alias": "ui_picture/title_sky"},
		"frame/sub_01": "frame/sub_00.png"}}))                                                       # (a row names frame/sub_00.png)
	var result := PackPictures.write(ROOT)
	assert_dict(result.added).is_empty()
	assert_dict(_table()).is_equal({"ui_picture/title_sky": "art/hi@4x.png", "ui_picture/coral_dawn": {"alias": "ui_picture/title_sky"}, "frame/sub_01": "frame/sub_00.png"})
	_png("ui_picture/title_sea.png")
	result = PackPictures.write(ROOT)
	assert_dict(result.added).is_equal({"ui_picture/title_sea": "ui_picture/title_sea.png"})
	assert_int(_table().size()).is_equal(4)
	assert_str(_table()["frame/sub_01"]).is_equal("frame/sub_00.png")


func test_a_folder_that_is_not_there_is_an_error() -> void:
	var result := PackPictures.write("%s/nowhere" % ROOT)
	assert_bool(result.ok()).is_false()
	assert_str(result.text()).contains("there is no folder")


func test_the_command_line_option_writes_the_table_and_checks_it() -> void:
	_png("ui_picture/title_sky.png")
	PackFiles.write_text("%s/pack.json" % ROOT, JSON.stringify({"id": "zz_tabulated", "title": "Tabulated", "version": "1", "base": String(PackShelf.base_id())}))
	var arguments := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://src/packs/pack_tool.tscn", "--"])
	arguments.append_array(PackShelf.pin_args())
	arguments.append_array(["--pictures-table=" + ProjectSettings.globalize_path(ROOT), "--check=" + ProjectSettings.globalize_path(ROOT), "--no-reach"])
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), arguments, output, true)
	var text := "\n".join(PackedStringArray(output.map(func(chunk: Variant) -> String: return str(chunk))))
	assert_int(code).override_failure_message(text).is_equal(0)
	assert_str(text).contains("pictures.json: 1 row(s) added (ui_picture/title_sky)")
	assert_dict(_table()).is_equal({"ui_picture/title_sky": "ui_picture/title_sky.png"})
