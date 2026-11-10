class_name TestPackTool
extends GdUnitTestSuite
## Teaches: one tool, two front doors. `src/packs/pack_tool.tscn` is the command line (`--list`, `--check=`, `--export-campaign=`,
## `--install=`, `--uninstall=`; the exit code says whether it worked) and the editor's Project > Tools "Pack tools" window
## (`addons/pack_tools/`) does nothing but start that scene in a Godot of its own and show what it prints. So these tests run the REAL tool in a real
## process, the way the window and a terminal do, and read its output and exit code.

const ID := &"harvest_cli"
const EXPORTS := "user://test_pack_tool_exports"

var _shelves: Array[PackShelf] = []


func after_test() -> void:
	for shelf in _shelves:
		shelf.remove()
	_shelves.clear()
	PackFiles.remove_tree("%s/%s" % [PackInstall.DIR, ID])
	PackFiles.remove_tree(EXPORTS)


func _tool(args: PackedStringArray) -> Array:
	return PackToolDialog.run_tool(PackShelf.pin_args() + args)               # (a Godot of its own: it gets the pin too)


## A pack with a campaign of copies of dev's sectors 0, 1, 180 as 70, 71, 72, in a scratch folder (not installed).
func _pack(pack_id: StringName = ID) -> PackShelf:
	var shelf := PackShelf.new(pack_id)
	_shelves.append(shelf)
	shelf.add_sector_copy(0, 70)
	shelf.add_sector_copy(1, 71)
	shelf.add_sector_copy(DevPack.test_sector("e", 0), 72)
	shelf.write_json("campaigns/%s.json" % pack_id, {
		"class": "Campaign", "id": String(pack_id), "title": "Harvest CLI", "sectors": [70, 71], "finales": [72], "default_edu_levels": [0, 1],
		"log_unlock_order": [2, 1], "finale_log_counts": [2], "log_texts": ["Apples.", "Pears."], "log_voices": ["", ""],
		"supply_texts": ["Well picked.", "Well picked again."], "supply_voices": ["", ""], "finale_text": "The harvest is in."})
	return shelf


## Waits (a frame at a time, up to two minutes) until `done` has something in it: the window's thread reports through `call_deferred`.
func _wait_for(done: Array) -> void:
	var started := Time.get_ticks_msec()
	while done.is_empty() and Time.get_ticks_msec() - started < 120000:
		await get_tree().process_frame


# --- the arguments the window builds ---------------------------------------------------------------------------------------------------

func test_the_window_turns_its_fields_into_the_tools_command_line() -> void:
	assert_array(PackToolDialog.arguments(PackToolDialog.Job.EXPORT_CAMPAIGN, "orchard")).is_equal(
			["--export-campaign=orchard", "--out=user://pack_exports"])
	assert_array(PackToolDialog.arguments(PackToolDialog.Job.EXPORT_CAMPAIGN, "orchard", "orchard_pack", " Orchard ", "2.0", "Pip", "/tmp/out", true, false)).is_equal(
			["--export-campaign=orchard", "--out=/tmp/out", "--pack-id=orchard_pack", "--title=Orchard", "--version=2.0", "--author=Pip", "--archive", "--no-reach"])
	assert_array(PackToolDialog.arguments(PackToolDialog.Job.EXPORT_PACK, "dev", "dev_data", "", "", "", "/tmp/out", true, false)).is_equal(
			["--export-pack=dev", "--out=/tmp/out", "--pack-id=dev_data", "--archive", "--no-reach"])
	assert_array(PackToolDialog.arguments(PackToolDialog.Job.CHECK, "/some/pack", "", "", "", "", "", false, false)).is_equal(["--check=/some/pack", "--no-reach"])


func test_the_window_offers_the_campaigns_of_the_pack_and_the_project() -> void:
	var campaigns := PackToolDialog.own_campaign_ids()
	assert_array(campaigns).contains([String(DevPack.TOUR)])
	for id in campaigns:
		assert_bool(FileAccess.file_exists(Catalog.own_campaign_path(StringName(id)))).is_true()


func test_the_window_runs_the_tool_in_the_background_and_shows_what_it_printed() -> void:
	var shelf := _pack()
	var dialog: PackToolDialog = auto_free(PackToolDialog.new())
	add_child(dialog)
	dialog.open(PackToolDialog.Job.CHECK)
	dialog._target_edit.text = shelf.root
	dialog._reach_box.button_pressed = false
	var done: Array = []
	dialog.finished.connect(func(code: int, text: String) -> void: done.assign([code, text]))
	dialog.run()
	assert_bool(dialog._run_button.disabled).is_true()                       # (busy: a second Run does nothing)
	await _wait_for(done)
	assert_int(done[0]).is_equal(0)
	assert_str(dialog._output.text).contains("Pack harvest_cli").contains("harvest_cli: no problems")
	assert_bool(dialog._run_button.disabled).is_false()
	# a pack with an error: the exit code is the tool's and the text says what
	FileAccess.open("%s/%s" % [shelf.root, SectorJson.foe_rel(71)], FileAccess.WRITE).store_string("not a creature script\n")
	done.clear()
	dialog.run()
	await _wait_for(done)
	assert_int(done[0]).is_equal(1)
	assert_str(dialog._output.text).contains("error: sector 71")


# --- the command line ----------------------------------------------------------------------------------------------------------------

func test_check_says_what_is_wrong_and_the_exit_code_follows() -> void:
	var shelf := _pack()
	shelf.write_json("rules/durations.json", {"fade": {"tiks": 3}})
	shelf.write_json("rules/tuning.json", {"air": {"max_oxygen": 0}})
	var bad := _tool(PackedStringArray(["--check=" + shelf.root, "--check=user://no_such_pack_folder", "--no-reach"]))      # (one process, two packs)
	assert_int(bad[0]).is_equal(1)
	assert_str(bad[1]).contains("campaigns harvest_cli").contains("sectors 70, 71, 72")
	assert_str(bad[1]).contains("error: durations: fade.tiks: no such duration")
	assert_str(bad[1]).contains("error: tuning: air.max_oxygen is 0: it must be 1 or more")
	assert_str(bad[1]).contains("no pack.json")


func test_install_list_check_by_id_and_uninstall_work_from_the_command_line() -> void:
	var shelf := _pack()
	# the options run in the order install, check, export, list: one process installs the pack, finds it by its id and lists it
	var first := _tool(PackedStringArray(["--install=" + shelf.root, "--check=harvest_cli", "--no-reach", "--list"]))
	assert_int(first[0]).is_equal(0)
	assert_str(first[1]).contains("installed 'harvest_cli'").contains("harvest_cli: no problems")
	assert_bool(FileAccess.file_exists("user://packs/%s/pack.json" % ID)).is_true()
	assert_str(first[1]).contains("In use:").contains("harvest_cli").contains("user://packs/harvest_cli")
	var gone := _tool(PackedStringArray(["--uninstall=harvest_cli", "--install=user://no_such_pack"]))
	assert_int(gone[0]).is_equal(1)                                                         # (the second fails: the exit code says so; the first still happened)
	assert_str(gone[1]).contains("uninstalled harvest_cli").contains("is not a folder")
	assert_bool(DirAccess.dir_exists_absolute("user://packs/%s" % ID)).is_false()


func test_a_complete_pack_is_exported_checked_and_listed_from_the_command_line() -> void:
	var done := _tool(PackedStringArray(["--export-pack=dev", "--pack-id=dev_cli_data", "--out=" + EXPORTS, "--no-reach"]))
	assert_int(done[0]).override_failure_message(done[1]).is_equal(0)
	assert_str(done[1]).contains("exported").contains("%s/dev_cli_data" % EXPORTS)
	assert_bool(FileAccess.file_exists("%s/dev_cli_data/data/zones.json" % EXPORTS)).is_true()
	assert_bool(FileAccess.file_exists("%s/dev_cli_data/data/zones.tres" % EXPORTS)).is_false()
	var checked := _tool(PackedStringArray(["--check=%s/dev_cli_data" % EXPORTS, "--no-reach"]))
	assert_int(checked[0]).override_failure_message(checked[1]).is_equal(0)
	assert_str(checked[1]).contains("Pack dev_cli_data").not_contains("error:")
	var refused := _tool(PackedStringArray(["--export-pack=no_such_pack", "--out=" + EXPORTS]))
	assert_int(refused[0]).is_equal(1)
	assert_str(refused[1]).contains("there is no pack 'no_such_pack'")


func test_export_from_the_command_line_refuses_what_cannot_be_exported_with_a_nonzero_exit_code() -> void:
	var refused := _tool(PackedStringArray(["--export-campaign=no_such_campaign", "--out=" + EXPORTS, "--no-reach"]))
	assert_int(refused[0]).is_equal(1)
	assert_str(refused[1]).contains("there is no campaign 'no_such_campaign'")
	assert_bool(DirAccess.dir_exists_absolute(EXPORTS)).is_false()
	var bad_option := _tool(PackedStringArray(["--frobnicate"]))
	assert_int(bad_option[0]).is_equal(2)
