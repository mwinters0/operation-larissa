class_name TestSaveStoreLegacy
extends GdUnitTestSuite
## Teaches: the original's words for the write error (the store: tests/engine/test_save_store.gd).

## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


const SaveStoreScript := preload("res://src/autoload/save_store.gd")
const ROSTER := "user://test_roster.json"
const HALL := "user://test_hall.json"

var _store: Node


func before_test() -> void:
	_cleanup()
	_store = auto_free(SaveStoreScript.new())
	_store.roster_path = ROSTER
	_store.hall_path = HALL


func after_test() -> void:
	_cleanup()


func _cleanup() -> void:
	for path in [ROSTER, HALL, ROSTER + ".tmp", HALL + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func test_the_write_error_dialog_has_the_originals_title_and_text() -> void:
	var queue := MessageQueue.new(GameClock)
	var message: MessageQueue.Message = _store.post_write_error(queue)
	assert_str(message.title).is_equal("Write Error")                                      # string 11018
	assert_str(message.body).is_equal("Writing to the disk has failed.  Your \n game cannot be saved.")   # 11017
	assert_array(message.buttons).is_equal(PackedStringArray(["OK"]))
	queue.close_current(0)


