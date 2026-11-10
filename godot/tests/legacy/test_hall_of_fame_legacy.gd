class_name TestHallOfFameLegacy
extends GdUnitTestSuite
## Teaches: the Hall of Fame as the original shows it: Voyager and Expert rows and the original's headings (the list itself: tests/engine/test_hall_of_fame.gd).


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func _entry(name: String, tries: int = 1, customized: bool = false) -> HallEntry:
	var entry := HallEntry.new()
	entry.name = name
	entry.tries = tries
	entry.customized = customized
	return entry


func test_the_customized_flag_shows_as_c() -> void:
	assert_str(_entry("A", 1, true).level_text()).is_equal("Voyager (c)")
	var expert := _entry("B")
	expert.game = 1
	assert_str(expert.level_text()).is_equal("Expert")


func test_an_entry_comes_from_a_profile() -> void:
	var p := PlayerProfile.new_player("Zed", PlayerProfile.Game.EXPERT)
	p.tries = 3
	p.customized = true
	var entry := HallEntry.from_profile(p)
	assert_str(entry.name).is_equal("Zed")
	assert_int(entry.game).is_equal(1)
	assert_int(entry.tries).is_equal(3)
	assert_bool(entry.customized).is_true()


func test_the_view_takes_its_headings_from_string_11124() -> void:
	# `show_hall_of_fame` (0x42bafc) draws string 11124 ("   Name   Level   Tries   ..." plus blank lines) as its text
	var view: HallOfFameView = auto_free(preload("res://src/ui/hall_of_fame.tscn").instantiate())
	add_child(view)
	await await_idle_frame()
	var line: String = Catalog.texts("ui_strings").text(11124).replace("\r", "\n").get_slice("\n", 0)
	assert_str(line).contains("Name")
	assert_array(view._headings()).is_equal(["Name", "Level", "Tries"])
	for i in 3:
		assert_str((view.grid.get_child(i) as Label).text).is_equal(["Name", "Level", "Tries"][i])
