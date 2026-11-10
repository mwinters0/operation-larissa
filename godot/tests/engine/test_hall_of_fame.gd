class_name TestHallOfFame
extends GdUnitTestSuite
## Teaches: the shift-out rule of a fixed-size list (DESIGN 6).


func _entry(name: String, tries: int = 1, customized: bool = false) -> HallEntry:
	var entry := HallEntry.new()
	entry.name = name
	entry.tries = tries
	entry.customized = customized
	return entry


func test_new_entries_fill_the_first_free_row() -> void:
	var hall := HallOfFame.new()
	hall.add(_entry("A"))
	hall.add(_entry("B"))
	assert_int(hall.entries.size()).is_equal(2)
	assert_str(hall.entries[1].name).is_equal("B")


func test_when_full_the_oldest_drops_out_and_the_newcomer_takes_the_last_row() -> void:
	var hall := HallOfFame.new()
	for i in 9:
		hall.add(_entry("P%d" % i))
	hall.add(_entry("New"))
	assert_int(hall.entries.size()).is_equal(9)
	assert_str(hall.entries[0].name).is_equal("P1")
	assert_str(hall.entries[8].name).is_equal("New")


func test_the_customized_flag_shows_as_the_marker_after_the_campaigns_name() -> void:
	var first := Catalog.default_campaign()
	assert_str(_entry("A").level_text()).is_equal(first.display_title())
	assert_str(_entry("A", 1, true).level_text()).is_equal(first.display_title() + " " + Catalog.text(&"customized_marker"))


func test_an_entry_comes_from_a_profile() -> void:
	var p := PlayerProfile.new_player_in("Zed", Catalog.campaign(DevPack.TOUR))
	p.tries = 3
	p.customized = true
	var entry := HallEntry.from_profile(p)
	assert_str(entry.name).is_equal("Zed")
	assert_str(entry.campaign_id).is_equal(DevPack.TOUR)
	assert_int(entry.game).is_equal(-1)
	assert_int(entry.tries).is_equal(3)
	assert_bool(entry.customized).is_true()


func test_rows_round_trip_and_bad_rows_are_skipped() -> void:
	var hall := HallOfFame.new()
	hall.add(_entry("A", 2))
	var other := HallOfFame.new()
	other.from_array(hall.to_array() + ["junk", {"name": ""}, {"name": "B", "tries": "x"}])
	assert_int(other.entries.size()).is_equal(2)
	assert_int(other.entries[0].tries).is_equal(2)
	assert_str(other.entries[1].name).is_equal("B")




func test_the_view_takes_its_headings_from_the_first_line_of_the_header_string() -> void:
	var view: HallOfFameView = auto_free(preload("res://src/ui/hall_of_fame.tscn").instantiate())
	add_child(view)
	await await_idle_frame()
	var line: String = Catalog.texts("ui_strings").text(11124).replace("\r", "\n").get_slice("\n", 0)     # string 11124 is the header (the file's own number)
	var words := Array(line.split(" ", false))
	assert_int(words.size()).is_equal(3)                                  # name, level, tries
	assert_array(Array(view._headings())).is_equal(words)
	for i in 3:
		assert_str((view.grid.get_child(i) as Label).text).is_equal(words[i])
