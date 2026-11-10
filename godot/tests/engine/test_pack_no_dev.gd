class_name TestPackNoDev
extends GdUnitTestSuite
## Teaches: what the game does when the dev pack is absent, and where dev comes from when the project has no `res://packs/dev`. Dev is the folder of the project (the editor,
## these tests) or the installed `user://packs/dev` (the pack file `dev.larissa` extracted, `test_pack_bundled.gd`, or installed from the pack screen). With neither, `Packs.dev()` is null and nothing can fall back to it: a chain that needs a fallback is refused in a debug build too, with a sentence that says so, a
## pack laid over `dev` or `--pack=dev` is refused with the advice to get `dev.larissa`, and the pack tools say what is missing instead of failing. The suite makes dev absent with
## `PackShelf.without_dev`.

const PROBE_ID := &"zz_nodev_probe"

var _scratch: String
var _real_folders: Array[String]
var _real_mode: bool
var _shelves: Array[PackShelf] = []


func before_test() -> void:
	_scratch = "user://test_no_dev_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_scratch)
	_real_folders = Packs.folders.duplicate()
	_real_mode = Packs.dev_fallback


func after_test() -> void:
	for shelf in _shelves:
		shelf.remove()
	_shelves.clear()
	Packs.dev_fallback = _real_mode
	Packs.folders = _real_folders
	PackFiles.remove_tree(_scratch)
	Packs.installed_dev_root = "%s/%s" % [Packs.USER_PACKS_DIR, Packs.DEV]       # (a test of this suite points it at a scratch folder)
	Packs.forget_dev()
	PackShelf.with_dev_again()                               # (and `Packs.start`: the command-line choice again)


## The complete pack that is only a manifest, the only pack found; no dev.
func _incomplete_without_dev() -> void:
	Packs.folders = [PackShelf.empty_complete_pack_dir(PROBE_ID), _scratch]
	PackShelf.without_dev()


func _data_pack(id: String, base: String) -> void:
	PackFiles.write_text("%s/%s/pack.json" % [_scratch, id], JSON.stringify({"id": id, "title": "Test %s" % id, "version": "1", "base": base}))


# --- dev is absent ---------------------------------------------------------------------------------------------------------

func test_without_a_dev_folder_or_archive_dev_is_null() -> void:
	assert_bool(Packs.has_dev()).is_true()
	PackShelf.without_dev()
	assert_object(Packs.dev()).is_null()
	assert_bool(Packs.has_dev()).is_false()
	assert_array(Packs.available().map(func(each: Pack) -> StringName: return each.id)).not_contains([Packs.DEV])
	PackShelf.with_dev_again()
	assert_object(Packs.dev()).is_not_null()
	assert_str(Packs.dev().root).is_equal("res://packs/dev")


func test_debug_an_incomplete_pack_has_nothing_to_fall_back_to_and_is_refused() -> void:
	_incomplete_without_dev()
	Packs.dev_fallback = true
	assert_bool(Packs.choose(PROBE_ID)).is_false()
	assert_array(Packs.chain_ids()).is_equal([PROBE_ID])
	assert_bool(Packs.is_refused()).is_true()
	var reason := Packs.fallback_reason()
	assert_int(reason.why).is_equal(Packs.Fallback.Why.MISSING_ASSETS)
	assert_bool(reason.refused).is_true()
	assert_bool(reason.no_dev).is_true()
	assert_str(reason.text()).contains("is incomplete").contains("cannot play").ends_with(Packs.Fallback.NO_DEV_SENTENCE)
	assert_str(reason.text()).contains("no dev assets to fall back to")
	assert_str(reason.advice()).contains("dev.larissa").contains("creator download")
	assert_str(PackChoice.summary()).contains("no dev assets to fall back to")


func test_debug_no_pack_and_no_dev_is_a_refusal_with_an_empty_chain() -> void:
	Packs.folders = [_scratch]
	PackShelf.without_dev()
	Packs.dev_fallback = true
	assert_bool(Packs.choose()).is_false()
	assert_array(Packs.chain_ids()).is_empty()
	assert_object(Packs.chosen()).is_null()
	assert_bool(Packs.is_refused()).is_true()
	assert_int(Packs.fallback_reason().why).is_equal(Packs.Fallback.Why.NO_PACK)
	assert_str(Packs.fallback_reason().text()).is_equal("No pack was found, so the game cannot play. " + Packs.Fallback.NO_DEV_SENTENCE)
	assert_str(Packs.fallback_reason().advice()).starts_with(Packs.Fallback.ADVICE_NO_PACK).contains("dev.larissa")
	assert_str(Packs.path("data/zones.tres")).contains("zones.tres")                  # (a path to name in a message, though nothing holds it)
	assert_str(PackChoice.chain_text()).is_equal("(no pack)")
	assert_array(PackChoice.entries()).is_empty()


func test_release_says_nothing_of_dev_whether_it_is_there_or_not() -> void:
	_incomplete_without_dev()
	Packs.dev_fallback = false
	Packs.choose(PROBE_ID)
	assert_bool(Packs.is_refused()).is_true()
	assert_bool(Packs.fallback_reason().no_dev).is_false()
	assert_str(Packs.fallback_reason().text()).not_contains("dev assets").not_contains("dev pack")
	assert_str(Packs.fallback_reason().advice()).not_contains("dev.larissa")


func test_a_pack_laid_over_dev_is_refused_in_both_modes_and_the_advice_says_where_dev_comes_from() -> void:
	_data_pack("zz_needs_dev", "dev")
	Packs.folders = [_scratch]
	PackShelf.without_dev()
	for mode in [true, false]:
		Packs.dev_fallback = mode
		assert_bool(Packs.choose(&"zz_needs_dev")).is_false()
		assert_array(Packs.chain_ids()).is_equal([&"zz_needs_dev"])
		var reason := Packs.fallback_reason()
		assert_int(reason.why).is_equal(Packs.Fallback.Why.MISSING_BASE)
		assert_bool(reason.refused).is_true()
		assert_bool(reason.needs_dev()).is_true()
		assert_bool(reason.no_dev).is_false()                  # (the trouble is dev itself: one sentence, not two)
		assert_str(reason.text()).contains("laid over 'dev'").not_contains("dev assets")
		assert_str(reason.advice()).is_equal(Packs.Fallback.ADVICE_NEEDS_DEV).contains("dev.larissa")


func test_pack_dev_with_no_dev_is_not_found_in_both_modes() -> void:
	PackShelf.without_dev()
	for mode in [true, false]:
		Packs.dev_fallback = mode
		assert_bool(Packs.choose(Packs.DEV)).is_false()
		assert_array(Packs.chain_ids()).is_empty()
		var reason := Packs.fallback_reason()
		assert_int(reason.why).is_equal(Packs.Fallback.Why.NOT_FOUND)
		assert_bool(reason.refused).is_true()
		assert_bool(reason.needs_dev()).is_true()
		assert_str(reason.advice()).is_equal(Packs.Fallback.ADVICE_NEEDS_DEV)
	Packs.start(PackedStringArray(["--pack=dev"]))
	assert_bool(Packs.is_refused()).is_true()


func test_the_dev_fallback_still_works_while_dev_is_there() -> void:
	Packs.folders = [PackShelf.empty_complete_pack_dir(PROBE_ID), _scratch]
	Packs.dev_fallback = true
	assert_bool(Packs.choose(PROBE_ID)).is_false()
	assert_array(Packs.chain_ids()).is_equal([PROBE_ID, Packs.DEV])
	assert_bool(Packs.fallback_reason().no_dev).is_false()
	assert_str(Packs.fallback_reason().text()).not_contains("dev assets")


# --- the tools cope --------------------------------------------------------------------------------------------------------

func test_the_check_of_a_pack_laid_over_a_missing_dev_says_what_to_get() -> void:
	_data_pack("zz_needs_dev", "dev")
	Packs.folders = [_scratch]
	PackShelf.without_dev()
	var report := PackCheck.run(Pack.open("%s/zz_needs_dev" % _scratch))
	assert_bool(report.passes()).is_false()
	assert_str(report.text()).contains("laid over the dev pack, which is not here").contains("dev.larissa")


func test_the_check_copes_with_an_empty_chain() -> void:
	_data_pack("zz_needs_dev", "dev")
	Packs.folders = [_scratch]
	PackShelf.without_dev()
	Packs.choose()
	assert_array(Packs.chain_ids()).is_equal([&"zz_needs_dev"])
	Packs.choose(Packs.DEV)
	assert_array(Packs.chain_ids()).is_empty()
	var report := PackCheck.run(Pack.open("%s/zz_needs_dev" % _scratch))
	assert_bool(report.passes()).is_false()
	assert_object(Packs.chosen()).is_null()                    # (the empty chain is put back as it was)


func test_a_new_pack_from_a_missing_dev_is_an_error_not_a_crash() -> void:
	PackShelf.without_dev()
	var result := PackCopy.make(&"zz_nodev_copy")
	assert_bool(result.ok).is_false()
	assert_str(result.message).contains("no dev pack to copy").contains("dev.larissa")
	assert_bool(DirAccess.dir_exists_absolute("res://packs/zz_nodev_copy")).is_false()
	assert_array(PackToolDialog.copyable_pack_ids()).not_contains(["dev"])
	PackShelf.with_dev_again()
	assert_array(PackToolDialog.copyable_pack_ids()).contains(["dev"])


func test_exporting_a_campaign_over_a_missing_dev_or_with_no_chain_is_an_error() -> void:
	var shelf := PackShelf.new(&"zz_nodev_box")
	_shelves.append(shelf)
	shelf.add_sector_copy(0, 40)
	shelf.add_sector_copy(1, 41)
	shelf.write_json("campaigns/zz_nodev_camp.json", {"class": "Campaign", "id": "zz_nodev_camp", "title": "No dev", "sectors": [40, 41], "finales": [],
			"default_edu_levels": [0, 1], "log_unlock_order": [2, 1], "finale_log_counts": [], "log_texts": ["a", "b"], "log_voices": ["", ""]})
	assert_object(shelf.mount()).is_not_null()
	PackShelf.without_dev()
	var options := PackExport.Options.new()
	options.base = Packs.DEV
	options.reach = false
	var result := PackExport.campaign(&"zz_nodev_camp", _scratch + "/out", options)
	assert_bool(result.ok()).is_false()
	assert_str(result.error).contains("dev pack, which is not here").contains("dev.larissa")
	assert_bool(DirAccess.dir_exists_absolute(_scratch + "/out/zz_nodev_camp")).is_false()
	Packs.lend([], func() -> void: assert_str(PackExport._base_of(PackExport.Options.new())).is_empty())


func test_the_pack_screen_shows_an_empty_chain() -> void:
	Packs.folders = [_scratch]
	PackShelf.without_dev()
	Packs.dev_fallback = true
	Packs.choose()
	var dialog := auto_free(load("res://src/ui/pack_dialog.tscn").instantiate()) as PackDialog
	add_child(dialog)
	assert_int(dialog.entry_count()).is_equal(0)
	assert_str(dialog.intro.text).contains("In use: (no pack)").contains("no dev assets to fall back to")
	assert_str(dialog.details.text).contains("No packs yet")


# --- where dev and the pack files are looked for ------------------------------------------------------------------------------

func test_the_folders_pack_files_are_looked_for_in_by_kind_of_build() -> void:
	assert_array(Packs.default_archive_folders(false, false, "/opt/neptune/neptune.x86_64")).is_equal(["/opt/neptune"])
	assert_array(Packs.default_archive_folders(false, true, "/usr/bin/godot")).is_empty()             # (the editor's executable is Godot's own)
	assert_array(Packs.default_archive_folders(false, false, "")).is_empty()
	assert_array(Packs.default_archive_folders(true, false, "")).is_equal([Packs.WEB_ARCHIVES_DIR])
	assert_str(Packs.WEB_ARCHIVES_DIR).is_equal("/packs")


## A dev pack in the data form (a manifest) as the folder `<_scratch>/<name>`; "" is the folder's own id.
func _installed_dev(manifest_id := "dev") -> String:
	var folder := _scratch + "/installed_dev"
	PackFiles.write_text(folder + "/pack.json", JSON.stringify({"id": manifest_id, "title": "Installed dev", "version": "1"}))
	return folder


func test_an_installed_dev_is_dev_when_the_project_has_none() -> void:
	var folder := _installed_dev()
	PackShelf.without_dev()
	Packs.installed_dev_root = folder
	Packs.forget_dev()
	Packs.folders = [_scratch]
	assert_str(Packs.dev().root).is_equal(folder)
	assert_bool(Packs.dev().trusted).is_false()
	assert_array(Packs.available().map(func(each: Pack) -> StringName: return each.id)).not_contains([Packs.DEV])


func test_the_projects_dev_wins_over_an_installed_one_and_the_reason_is_kept() -> void:
	var folder := _installed_dev()
	Packs.installed_dev_root = folder
	Packs.forget_dev()
	assert_str(Packs.dev().root).is_equal("res://packs/dev")
	Packs.available()
	var notes := Packs.ignored().filter(func(line: String) -> bool: return line.contains(folder))
	assert_array(notes).has_size(1)
	assert_str(notes[0]).contains("dev is res://packs/dev").contains("left out")


func test_an_installed_dev_that_says_it_is_another_pack_is_left_out() -> void:
	var folder := _installed_dev("elsewhere")
	PackShelf.without_dev()
	Packs.installed_dev_root = folder
	Packs.forget_dev()
	assert_object(Packs.dev()).is_null()
	Packs.available()
	assert_array(Packs.ignored().filter(func(line: String) -> bool: return line.contains("not 'dev'"))).has_size(1)


func test_a_user_packs_dev_folder_that_is_not_the_installed_place_is_left_out() -> void:
	_data_pack("dev", "ghost")
	Packs.folders = [_scratch]
	PackShelf.without_dev()
	var ids: Array = Packs.available().map(func(each: Pack) -> StringName: return each.id)
	assert_array(ids).not_contains([Packs.DEV])
	assert_array(Packs.ignored()).has_size(1)
	assert_str(Packs.ignored()[0]).contains("reserved for the dev pack")
	assert_object(Packs.dev()).is_null()
