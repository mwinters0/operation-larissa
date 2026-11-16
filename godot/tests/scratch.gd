class_name Scratch
extends RefCounted
## Scratch places for a test, all under ONE root in `user://` (`ROOT`), so that a test never writes the player's own data and leaves nothing lying about. Each test process has a folder of
## its own in it (`<ROOT>/<process id>/`): `folder` makes a fresh empty one there for a test, `path` names a file in it, `isolate_user_data` points the game's own user folders (the installed packs, the pack remembered for the
## next start) at fresh ones and `release_user_data` gives them back and deletes what was made. The first use in a process also deletes the folders of processes that are gone (a run that crashed
## leaves its folder behind), and never one of a process that is still running (the editor's gdUnit and a command-line run at the same time).
##
## A test that installs, uninstalls or lists packs, presses Use on the pack screen or runs the pack tool calls `isolate_user_data` in `before_test` and `release_user_data` in `after_test` (after
## every other restore of its own that reads `Packs.folders`: the installed entry of that list follows `Packs.installed_dir`). A test names neither of those places itself
## (`test_tests_leave_user_data_alone.gd` scans for it): it reads `Packs.installed_dir` and `PackChoice.memory_path`.
##
## Teaches: a test double for a folder the player owns, like `PackShelf` is for a pack: the honest test of code that writes the disk points the code's one owner of the path at a scratch place and puts it
## back. And why a process is told to be gone by its folder (`/proc`), not by `OS.is_process_running`, which knows only the processes this one started.

## The one folder every scratch place is in.
const ROOT := "user://test_scratch"
## A file in a process's folder that says when the process used it last: the proof of life where there is no `/proc` (a folder not touched for `STALE_AFTER` seconds is left by a run that is gone).
const ALIVE := "alive.txt"
const STALE_AFTER := 24 * 3600
const USER_DATA := "user_data"
const PACKS := "packs"
const PACK_CHOICE := "pack_choice.cfg"

static var _swept := false
static var _saved: Dictionary = {}


## A path `name` (a file name, or `folder/file`) in this process's scratch folder, for a test's own file: its folder is made, the file is not touched. A suite that writes it deletes it in `after_test`
## (what it leaves is deleted with the process's folder by the next run).
static func path(name: String) -> String:
	var file := "%s/%s" % [_mine(), name]
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	return file


## A fresh, empty folder `name` (a name of one word) for the test in this process's scratch folder; its path. A second call with the same name empties it again.
static func folder(name: String) -> String:
	var dir := "%s/%s" % [_mine(), name]
	PackFiles.remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


## Points the game's user folders at fresh ones for the test: `Packs.installed_dir` at an empty `packs` folder that is not made (as on a machine with nothing installed) and `PackChoice.memory_path`
## at a file that is not there, both in one `user_data` folder here. The chain is chosen again (`Packs.start`, so the lookups see the new folders) and dev is looked for again. Does nothing when it is
## done already: `release_user_data` ends it. Returns the folder that stands for `user://`.
static func isolate_user_data() -> String:
	if not _saved.is_empty():
		return _saved["scratch"]
	var user_data := folder(USER_DATA)
	_saved = {"installed_dir": Packs.installed_dir, "memory_path": PackChoice.memory_path, "scratch": user_data}
	Packs.installed_dir = "%s/%s" % [user_data, PACKS]
	PackChoice.memory_path = "%s/%s" % [user_data, PACK_CHOICE]
	Packs.forget_dev()
	Packs.start()
	return user_data


## Gives the real folders back (`Packs.installed_dir`, `PackChoice.memory_path`), chooses again (`Packs.start`: the command-line choice) and deletes the scratch ones.
static func release_user_data() -> void:
	if _saved.is_empty():
		return
	Packs.installed_dir = _saved["installed_dir"]
	PackChoice.memory_path = _saved["memory_path"]
	var scratch: String = _saved["scratch"]
	_saved = {}
	PackFiles.remove_tree(scratch)
	Packs.forget_dev()
	Packs.start()


## This process's folder (made, its proof of life renewed). The first call deletes the folders of the processes that are gone.
static func _mine() -> String:
	var dir := "%s/%d" % [ROOT, OS.get_process_id()]
	if not _swept:
		_swept = true
		sweep()
		PackFiles.remove_tree(dir)                                # (an earlier process had this number)
	DirAccess.make_dir_recursive_absolute(dir)
	PackFiles.write_text("%s/%s" % [dir, ALIVE], str(Time.get_unix_time_from_system()))
	return dir


## Deletes the folders of the processes that are gone (the first use does it by itself).
static func sweep() -> void:
	for name in DirAccess.get_directories_at(ROOT):
		if not _in_use(name):
			PackFiles.remove_tree("%s/%s" % [ROOT, name])


## Is the folder of the process `name` (its id) in use by a process that is running? Where `/proc` lists the processes it is that; elsewhere the folder says so by being touched lately.
## (`OS.is_process_running` is no help: it knows only the processes this one started.)
static func _in_use(name: String) -> bool:
	if name.is_valid_int() and DirAccess.dir_exists_absolute("/proc/self"):
		return DirAccess.dir_exists_absolute("/proc/%s" % name)
	var touched := FileAccess.get_modified_time("%s/%s/%s" % [ROOT, name, ALIVE])
	return touched == 0 or Time.get_unix_time_from_system() - touched < STALE_AFTER
