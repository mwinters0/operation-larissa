class_name TestPackBundled
extends GdUnitTestSuite
## Teaches: how a game gets the packs it carries. `legacy` and `dev` ship as pack files (`<id>.larissa`, `Pack.FILE_EXTENSION`) next to the executable (or preloaded by the Web page) and are READ WHERE THEY LIE
## (`PackArchive`): nothing is extracted into `user://packs`. A bundled pack file is one place among the others `Packs` looks in, last in the order (a pack of the project, an installed folder and an installed
## pack file are all used instead of it, and `ignored()` says so); a pack file whose `pack.json` names another id than its file is left out, and so is one that is not a zip.
## The packs are scratch ids of the test (`Packs.bundled`), so a pack installed on this machine is left alone.

const ID := &"zz_bundled_probe"
const PROJECT_ID := &"zz_bundled_project"
const DEV_ID := &"zz_dev_installed"

var _scratch: String
var _real_folders: Array[String]
var _real_bundled: Array[StringName]


func before_test() -> void:
	_scratch = "user://test_pack_bundled_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_scratch)
	_real_folders = Packs.folders.duplicate()
	_real_bundled = Packs.bundled.duplicate()
	Packs.bundled = [ID, PROJECT_ID]


func after_test() -> void:
	Packs.bundled = _real_bundled
	Packs.folders = _real_folders
	PackFiles.remove_tree("%s/%s" % [PackInstall.DIR, ID])
	PackFiles.remove_tree("%s/%s" % [PackInstall.DIR, DEV_ID])
	PackFiles.remove_tree("%s/%s" % [Packs.PROJECT_PACKS_DIR, PROJECT_ID])
	PackFiles.remove_tree(_scratch)
	Packs.installed_dev_root = "%s/%s" % [Packs.USER_PACKS_DIR, Packs.DEV]
	PackShelf.with_dev_again()
	Packs.archive_folders = Packs.default_archive_folders(OS.has_feature("web"), OS.has_feature("editor"), OS.get_executable_path())
	Packs.forget_dev()
	Packs.start()


## Zips a pack `id` at the version `version` (with a file of `text`) into `<scratch>/shipped/<id>.larissa`, as `PackExport.complete` with `archive` does.
func _pack_file(id: StringName, version: String, text := "hello", manifest_id := "") -> String:
	var folder := "%s/build_%s_%s" % [_scratch, id, version]
	PackFiles.write_text(folder + "/pack.json", JSON.stringify({"id": manifest_id if not manifest_id.is_empty() else String(id), "title": "Probe", "version": version}))
	PackFiles.write_text(folder + "/texts.json", JSON.stringify({"zz_bundled_text": text}))
	var file := "%s/shipped/%s.%s" % [_scratch, id, Pack.FILE_EXTENSION]
	assert_int(PackFiles.zip_folder(folder, file, String(id))).is_equal(OK)
	return file


func _look() -> void:
	Packs.archive_folders = [_scratch + "/shipped"]
	Packs.forget_dev()


func _listed(id: StringName) -> Array:
	return Packs.available().filter(func(pack: Pack) -> bool: return pack.id == id)


func _notes_about(text: String) -> Array:
	return Packs.ignored().filter(func(line: String) -> bool: return line.contains(text))


func test_a_bundled_pack_file_is_read_where_it_lies_as_data() -> void:
	var file := _pack_file(ID, "1")
	_look()
	var found := _listed(ID)
	assert_array(found).has_size(1)
	assert_str(found[0].root).is_equal(file)
	assert_bool(found[0].is_archive()).is_true()
	assert_bool(found[0].trusted).is_false()
	assert_str(found[0].read_json("texts.json")["zz_bundled_text"]).is_equal("hello")
	assert_bool(PackInstall.is_installed(ID)).override_failure_message("nothing is extracted into the installed packs").is_false()


func test_a_new_pack_file_next_to_the_game_is_the_pack_the_next_look_finds() -> void:
	_pack_file(ID, "1")
	_look()
	assert_str(_listed(ID)[0].version).is_equal("1")
	_pack_file(ID, "2", "newer")
	var found := _listed(ID)[0] as Pack
	assert_str(found.version).is_equal("2")
	assert_str(found.read_json("texts.json")["zz_bundled_text"]).is_equal("newer")


func test_a_pack_file_that_holds_another_pack_than_its_name_is_left_out_and_the_reason_is_kept() -> void:
	_pack_file(ID, "1", "x", "someone_else")
	_look()
	assert_array(_listed(ID)).is_empty()
	assert_array(_listed(&"someone_else")).is_empty()
	assert_array(_notes_about("its pack.json says 'someone_else', not '%s'" % ID)).has_size(1)


func test_a_pack_of_the_project_is_used_instead_of_a_pack_file_of_its_id_and_the_note_says_which() -> void:
	PackFiles.write_text("%s/%s/pack.json" % [Packs.PROJECT_PACKS_DIR, PROJECT_ID], JSON.stringify({"id": String(PROJECT_ID), "title": "Project", "version": "1"}))
	_pack_file(PROJECT_ID, "9")
	_look()
	var found := _listed(PROJECT_ID)
	assert_array(found).has_size(1)
	assert_str(found[0].root).is_equal("%s/%s" % [Packs.PROJECT_PACKS_DIR, PROJECT_ID])
	assert_array(_notes_about("is %s/%s, so this one is left out" % [Packs.PROJECT_PACKS_DIR, PROJECT_ID])).has_size(1)
	assert_str(PackInstall.refusal(Packs.DEV)).contains("the project itself has a pack called 'dev'")


func test_only_the_bundled_ids_are_looked_for_and_a_pack_file_that_is_not_a_pack_is_left_out() -> void:
	_pack_file(&"zz_not_bundled", "1")
	PackFiles.write_text(_scratch + "/shipped/%s.%s" % [ID, Pack.FILE_EXTENSION], "not a zip")
	_look()
	assert_array(_listed(&"zz_not_bundled")).is_empty()
	assert_array(_listed(ID)).is_empty()
	assert_array(_notes_about("%s.%s" % [ID, Pack.FILE_EXTENSION])).has_size(1)


func test_the_bundled_dev_is_dev_in_place_and_an_installed_dev_comes_before_it() -> void:
	Packs.bundled = [Packs.DEV]
	PackShelf.without_dev([_scratch + "/shipped"])
	var file := _pack_file(Packs.DEV, "1")
	assert_str(Packs.dev().root).is_equal(file)
	assert_bool(Packs.dev().is_archive()).is_true()
	assert_array(Packs.available().filter(func(pack: Pack) -> bool: return pack.id == Packs.DEV)).is_empty()
	PackFiles.write_text("%s/%s/pack.json" % [PackInstall.DIR, DEV_ID], JSON.stringify({"id": "dev", "title": "Installed dev", "version": "1"}))
	Packs.installed_dev_root = "%s/%s" % [PackInstall.DIR, DEV_ID]
	Packs.forget_dev()
	assert_str(Packs.dev().root).is_equal(Packs.installed_dev_root)
	Packs.available()
	assert_array(_notes_about("%s: dev is %s, so this copy is left out" % [file, Packs.installed_dev_root])).has_size(1)


func test_an_installed_dev_is_listed_by_the_pack_screen_and_is_the_fallback() -> void:
	PackFiles.write_text("%s/%s/pack.json" % [PackInstall.DIR, DEV_ID], JSON.stringify({"id": "dev", "title": "Installed dev", "version": "1"}))
	PackShelf.without_dev()
	Packs.installed_dev_root = "%s/%s" % [PackInstall.DIR, DEV_ID]
	Packs.forget_dev()
	assert_bool(Packs.has_dev()).is_true()
	assert_bool(Packs.dev().trusted).is_false()
	var listed := PackChoice.entries().filter(func(entry: PackChoice.Entry) -> bool: return entry.id() == Packs.DEV)
	assert_array(listed).has_size(1)
	assert_array(Packs.available().map(func(pack: Pack) -> StringName: return pack.id)).not_contains([Packs.DEV])


## The start-up report (stdout of an exported game): where it looked, the bundled pack file it found (by its path), and why that pack was chosen.
func test_the_start_report_says_where_it_looked_and_what_it_chose() -> void:
	var file := _pack_file(ID, "1.0")
	_look()
	Packs.folders = [_scratch + "/none"]
	var search := "\n".join(Packs.search_report())
	assert_str(search).contains(_scratch + "/shipped").contains("%s.%s" % [ID, Pack.FILE_EXTENSION]).contains(_scratch + "/none")
	assert_str(search).contains(ProjectSettings.globalize_path(_scratch))
	var found := Packs.available()
	assert_str("\n".join(Packs.found_report(found))).contains("found '%s' at %s" % [ID, file])
	Packs.choose(ID)
	assert_str("\n".join(Packs.choice_report(ID, found))).contains("--pack=%s asked for" % ID).contains("chain: %s (%s (" % [ID, file]).contains("dev stands in for what is missing")
	Packs.choose()
	var chose := "\n".join(Packs.choice_report(&"", found))
	assert_str(chose).contains("no --pack= given: chose '%s'" % found.filter(func(pack: Pack) -> bool: return pack.is_valid())[0].id)
