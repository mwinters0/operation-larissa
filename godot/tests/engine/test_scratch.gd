class_name TestScratch
extends GdUnitTestSuite
## Teaches: a test double for the player's own folders. `Scratch.isolate_user_data` points the installed-packs folder (`Packs.installed_dir`) and the file that keeps the pack chosen for the next start
## (`PackChoice.memory_path`) at fresh scratch places and `release_user_data` puts them back, so that installing a pack, pressing Use on the pack screen or running the pack tool never touches what the
## person who runs the tests has installed or chosen. The scratch places are in one root in `user://`, a folder for each test process; a folder of a process that is gone is deleted, one of a process that runs is not.

const DEAD_PROCESS := "2147483646"


func after_test() -> void:
	Scratch.release_user_data()


func test_isolating_points_the_installed_folder_and_the_kept_choice_at_scratch_places_and_releasing_gives_them_back() -> void:
	var real_dir := Packs.installed_dir
	var real_memory := PackChoice.memory_path
	var real_folders := Packs.folders.duplicate()
	var user_data := Scratch.isolate_user_data()
	assert_str(Packs.installed_dir).starts_with(Scratch.ROOT).is_not_equal(real_dir)
	assert_str(PackChoice.memory_path).starts_with(Scratch.ROOT).is_not_equal(real_memory)
	assert_str(Packs.installed_dir.get_base_dir()).is_equal(user_data)
	assert_bool(Packs.folders.has(Packs.installed_dir) and not Packs.folders.has(real_dir)).override_failure_message("the installed entry of the find order moves with it").is_true()
	assert_array(Packs.available().filter(func(pack: Pack) -> bool: return pack.root.begins_with(Packs.installed_dir))).is_empty()
	assert_str(Scratch.isolate_user_data()).override_failure_message("isolating twice is isolating once").is_equal(user_data)
	var shelf := PackShelf.new(&"zz_scratch_probe")
	var installed := PackInstall.install(shelf.root)
	assert_bool(installed.ok).override_failure_message(installed.message).is_true()
	assert_str(installed.path).is_equal("%s/zz_scratch_probe" % Packs.installed_dir)
	PackChoice.remember(&"zz_scratch_probe")
	assert_str(PackChoice.remembered()).is_equal(&"zz_scratch_probe")
	shelf.remove()
	Scratch.release_user_data()
	assert_str(Packs.installed_dir).is_equal(real_dir)
	assert_str(PackChoice.memory_path).is_equal(real_memory)
	assert_array(Packs.folders).is_equal(real_folders)
	assert_bool(DirAccess.dir_exists_absolute(user_data)).is_false()


func test_a_folder_is_fresh_and_empty_each_time() -> void:
	var folder := Scratch.folder("probe")
	assert_str(folder).starts_with(Scratch.ROOT).ends_with("/probe")
	PackFiles.write_text(folder + "/x.txt", "x")
	assert_str(Scratch.folder("probe")).is_equal(folder)
	assert_array(PackFiles.files_under(folder)).is_empty()
	PackFiles.remove_tree(folder)


func test_the_folders_of_processes_that_are_gone_are_swept_and_those_of_running_ones_are_not() -> void:
	var own := Scratch.folder("probe")                                       # (makes this process's folder)
	var dead := "%s/%s" % [Scratch.ROOT, DEAD_PROCESS]
	var init := "%s/1" % Scratch.ROOT
	var elsewhere := "%s/not_a_process" % Scratch.ROOT
	for dir in [dead, init, elsewhere]:
		PackFiles.write_text(dir + "/" + Scratch.ALIVE, "0")
	Scratch.sweep()
	assert_bool(DirAccess.dir_exists_absolute(own)).override_failure_message("this process's own folder stays").is_true()
	assert_bool(DirAccess.dir_exists_absolute(init)).override_failure_message("a running process's folder stays").is_true()
	assert_bool(DirAccess.dir_exists_absolute(elsewhere)).is_true()
	assert_bool(DirAccess.dir_exists_absolute(dead)).override_failure_message("a process that is gone: where /proc lists the processes its folder goes").is_equal(not DirAccess.dir_exists_absolute("/proc/self"))
	for dir in [dead, init, elsewhere, own]:
		PackFiles.remove_tree(dir)
