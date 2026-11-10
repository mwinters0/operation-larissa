class_name TestScreenSaversLegacy
extends GdUnitTestSuite
## The savers on the original's 384 screens (seven of them with stale bytes) and 32 sector files: a save without a change gives the committed bytes back. The same
## rules on dev's files, and what the savers refuse, are in `tests/engine/test_screen_savers.gd`.
##
## Teaches: why Ctrl+S in the Godot editor is safe for the generated data files. The editor re-saves every resource it believes was
## edited (and it believes that of every screen it has loaded); without help that rewrote `screen_MM.tres` in Godot's own text format.
## `ScreenDataSaver` and `SectorDataSaver` sit at the FRONT of `ResourceSaver`'s list (see their headers) and write the importer's
## text, or refuse. These tests register the savers exactly like `ScreenEditorPlugin._register_savers`, call `ResourceSaver.save`
## the way the editor does, and look at the bytes. Everything is written under user://, never into res://data.

const SECTORS := LegacyPack.SECTORS_DIR
const TEMP := "user://screen_savers_test"

var _savers: Array[ResourceFormatSaver] = []


func before_test() -> void:
	# The same call as the plugin's: the `true` puts the saver BEFORE Godot's own text saver, which would take every `.tres`.
	_savers = [ScreenDataSaver.new(), SectorDataSaver.new()]
	for saver in _savers:
		ResourceSaver.add_resource_format_saver(saver, true)
	ScreenFile.last_refusal = ""
	DirAccess.make_dir_recursive_absolute(TEMP)


func after_test() -> void:
	for saver in _savers:
		ResourceSaver.remove_resource_format_saver(saver)
	_savers.clear()
	_remove_tree(TEMP)


func _remove_tree(path: String) -> void:
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for dir in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(dir))
	DirAccess.remove_absolute(path)


func _load_screen(sector: int, screen: int, dir: String = SECTORS) -> ScreenData:
	return ResourceLoader.load(ScreenFile.screen_path(dir, sector, screen), "", ResourceLoader.CACHE_MODE_IGNORE) as ScreenData


## A copy of the sector file under user:// (its screens and script are still the res:// ones). Returns its path.
func _copy_sector(sector: int) -> String:
	var path := Catalog.sector_path(sector, TEMP)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert_int(DirAccess.copy_absolute(Catalog.sector_path(sector, SECTORS), path)).is_equal(OK)
	return path


func _load_sector(path: String) -> SectorData:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData


# --- the originals ---------------------------------------------------------------------------------------------------

func test_every_original_screen_is_saved_byte_for_byte_by_resource_saver() -> void:
	var path := TEMP + "/screen.tres"
	var problems: Array[String] = []
	var with_stale := 0
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		for m in Catalog.SCREENS_PER_SECTOR:
			var screen := _load_screen(s, m)
			with_stale += 0 if screen.stale_bytes.is_empty() else 1
			if ResourceSaver.save(screen, path) != OK or FileAccess.get_file_as_bytes(path) != FileAccess.get_file_as_bytes(ScreenFile.screen_path(SECTORS, s, m)):
				problems.append("sector %d screen %d" % [s, m])
			DirAccess.remove_absolute(path)
	assert_int(with_stale).override_failure_message("the seven original screens with stale bytes are part of this test").is_equal(7)
	assert_array(problems).override_failure_message("saved differently from the committed file: " + ", ".join(problems)).is_empty()



func test_every_original_sector_is_saved_byte_for_byte_by_resource_saver() -> void:
	var problems: Array[String] = []
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		var path := _copy_sector(s)
		var before := FileAccess.get_file_as_bytes(path)
		var result := ResourceSaver.save(_load_sector(path), path)
		if result != OK or FileAccess.get_file_as_bytes(path) != before:
			problems.append("sector %d" % s)
	assert_array(problems).override_failure_message("changed by a save without a change: " + ", ".join(problems)).is_empty()
