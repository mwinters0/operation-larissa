class_name TestFoeScriptFile
extends GdUnitTestSuite
## Teaches: testing a custom file format (ResourceFormatLoader / ResourceFormatSaver). The
## property that matters is the ROUND TRIP: what is saved is what loads, byte for byte.
## Files go to user:// so the test never touches the project.

const TEMP := "user://test_foe_script_file.foe"


func after_test() -> void:
	DirAccess.remove_absolute(TEMP)


## Saves `text` through ResourceSaver and returns the bytes now in the file.
func _saved_bytes(text: String) -> PackedByteArray:
	var script := FoeScript.new()
	script.source = text
	assert_int(ResourceSaver.save(script, TEMP)).is_equal(OK)
	return FileAccess.get_file_as_bytes(TEMP)


func test_the_file_holds_exactly_the_text() -> void:
	var text := "start:\n    Return\n"
	assert_bool(_saved_bytes(text) == text.to_utf8_buffer()).is_true()


func test_no_newline_is_added_or_dropped() -> void:
	assert_bool(_saved_bytes("a:\n    Return") == "a:\n    Return".to_utf8_buffer()).is_true()
	assert_int(_saved_bytes("").size()).is_equal(0)


func test_the_round_trip_is_byte_identical() -> void:
	for text in ["", "x", "a:\n    Return\n", "a:\n    Return\n\n\n", "; caf\u00e9 \u2192 \"quoted\" \\ back\n", "line\r\nwith CRLF\r\n"]:
		var bytes := _saved_bytes(text)
		var loaded := ResourceLoader.load(TEMP, "", ResourceLoader.CACHE_MODE_IGNORE) as FoeScript
		assert_object(loaded).is_not_null()
		assert_bool(loaded.source == text).override_failure_message("text changed: %s" % [text.c_escape()]).is_true()
		assert_bool(loaded.source.to_utf8_buffer() == bytes).is_true()


func test_every_sector_file_loads_as_a_foe_script() -> void:
	for i in Catalog.sector_ids():
		var path := Catalog.foe_path(i)
		var loaded := load(path) as FoeScript
		assert_object(loaded).override_failure_message("%s is not a FoeScript" % path).is_not_null()
		assert_bool(loaded.source == FileAccess.get_file_as_string(path)).is_true()
		assert_object(Catalog.sector(i).foe_script).is_same(loaded)


func test_replacing_the_script_recompiles_and_forgets_the_old_one() -> void:
	var first := FoeScript.new()
	first.source = "a:\n    Return\n"
	var second := FoeScript.new()
	second.source = "a:\n    Return\n    Return\n"
	var sector := SectorData.new()
	sector.foe_script = first
	assert_int(sector.foe_bytecode.size()).is_equal(1)
	sector.foe_script = second
	assert_int(sector.foe_bytecode.size()).is_equal(2)
	first.source = "a:\n    Return\n    Return\n    Return\n"      # no longer ours: must not matter
	assert_int(sector.foe_bytecode.size()).is_equal(2)
	second.source = "a:\n    Return\n"
	assert_int(sector.foe_bytecode.size()).is_equal(1)


func test_reload_reads_a_changed_file_into_the_same_object() -> void:
	_saved_bytes("a:\n    Return\n")
	var script := load(TEMP) as FoeScript
	assert_str(script.source).is_equal("a:\n    Return\n")
	var file := FileAccess.open(TEMP, FileAccess.WRITE)      # "another editor" saves the file
	file.store_string("a:\n    Hide_Foe\n")
	file.close()
	var monitor := monitor_signals(script)
	script.reload()
	assert_str(script.source).is_equal("a:\n    Hide_Foe\n")
	await assert_signal(monitor).is_emitted("changed")
