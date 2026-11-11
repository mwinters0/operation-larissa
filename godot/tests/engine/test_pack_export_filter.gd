class_name TestPackExportFilter
extends GdUnitTestSuite
## Teaches: what an export carries of `res://packs/` (nothing) and of `res://skins/` (the original skin and no other): `PackExportFilter`, registered by the pack tools plugin. A pack reaches an exported game as a pack file (`<id>.larissa`) next to it.
## The filters in `export_presets.cfg` say the same for an export without the plugin, and the tool window's "New pack" job builds the command line of `pack_tool --new`.


func test_a_game_export_carries_no_pack() -> void:
	assert_bool(PackExportFilter.carries("res://packs/dev/pack.json")).is_false()
	assert_bool(PackExportFilter.carries("res://packs/dev/assets/ui/hud/ui_1195.png")).is_false()
	assert_bool(PackExportFilter.carries("res://packs/legacy/pack.json")).is_false()
	assert_bool(PackExportFilter.carries("res://packs/my_pack/data/zones.tres")).is_false()
	assert_bool(PackExportFilter.carries("res://packs/devious/pack.json")).is_false()           # (a pack whose id only starts with "dev")
	assert_bool(PackExportFilter.carries("res://packs/README.md")).is_false()
	assert_bool(PackExportFilter.carries("res://src/main.gd")).is_true()
	assert_bool(PackExportFilter.carries("res://data/rules/durations.json")).is_true()


func test_a_game_export_carries_the_original_skin_and_no_other() -> void:
	assert_bool(PackExportFilter.carries(SkinChoice.path_of(SkinChoice.ORIGINAL))).is_true()           # (the game cannot run without it: `SkinChoice.original`)
	assert_bool(PackExportFilter.carries("res://skins/original/anything.png")).is_true()
	assert_bool(PackExportFilter.carries(SkinChoice.path_of(&"creatures"))).is_false()
	assert_bool(PackExportFilter.carries("res://skins/creatures/creature_rig.gd")).is_false()
	assert_bool(PackExportFilter.carries("res://skins/a_skin_of_tomorrow/skin.tres")).is_false()
	assert_bool(PackExportFilter.carries("res://skins/originality/skin.tres")).is_false()              # (a skin whose id only starts with "original")
	assert_bool(PackExportFilter.carries("res://src/skins/game_skin.gd")).is_true()                    # (the code that wears a skin is the game's)


func test_the_presets_in_the_file_say_the_same() -> void:
	var presets := ConfigFile.new()
	assert_int(presets.load("res://export_presets.cfg")).is_equal(OK)
	var names: Array[String] = []
	for section in presets.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		names.append(presets.get_value(section, "name"))
		assert_str(presets.get_value(section, "include_filter")).not_contains("packs/")
		assert_str(presets.get_value(section, "exclude_filter")).contains("packs/dev/*").contains("packs/legacy/*").contains("skins/creatures/*")
	assert_array(names).is_equal(["Linux", "Windows Desktop", "Web"])


func test_the_web_preset_uses_the_project_shell() -> void:
	var presets := ConfigFile.new()
	assert_int(presets.load("res://export_presets.cfg")).is_equal(OK)
	for section in presets.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options") and presets.get_value(section, "name") == "Web":
			var shell: String = presets.get_value(section + ".options", "html/custom_html_shell")
			assert_str(shell).is_equal("res://export/web_shell.html")
			assert_bool(FileAccess.file_exists(shell)).is_true()
			var text := FileAccess.get_file_as_string(shell)
			assert_str(text).contains("$GODOT_URL")
			assert_str(text).contains("PACK_IDS")


func test_the_tool_window_builds_the_command_line_of_a_new_pack() -> void:
	assert_array(PackToolDialog.arguments(PackToolDialog.Job.NEW_PACK, "dev", " orchard ", "Orchard")).is_equal(["--new=orchard", "--from=dev", "--title=Orchard"])
	assert_array(PackToolDialog.arguments(PackToolDialog.Job.NEW_PACK, "dev", "orchard")).is_equal(["--new=orchard", "--from=dev"])
	assert_str(PackToolDialog.copyable_pack_ids()[0]).is_equal("dev")
