class_name TestCanisterLog
extends GdUnitTestSuite
## Teaches: testing a rule table. `CanisterLog` is pure data and arithmetic, so every claim about which entries a sector lists and how the menu moves
## is a one-line assertion. The campaign is dev's test campaign `test_c` (tools/dev_pack/test_sectors/batch_c.py): nine sectors 140-148 whose log is
## unlocked in the uneven order 3 1 4 9 2 6 5 8 7 (series 3), so the newest entry is neither the sector's number nor the largest of the list.
## The original's two games of 15 entries are tests/legacy/test_canister_log_legacy.gd.

const TEST_C := &"test_c"
const ORDER: Array[int] = [3, 1, 4, 9, 2, 6, 5, 8, 7]
const FIRST := 140


func _campaign() -> Campaign:
	return Catalog.campaign(TEST_C)


func test_every_campaign_unlocks_each_of_its_entries_exactly_once() -> void:
	for campaign in Catalog.campaigns():
		var order: Array = Array(campaign.log_unlock_order)
		order.sort()
		assert_array(order).override_failure_message(String(campaign.id)).is_equal(range(1, order.size() + 1))
	assert_array(Array(_campaign().log_unlock_order)).is_equal(ORDER)


func test_the_sector_at_position_i_lists_i_plus_one_entries() -> void:
	for i in ORDER.size():
		assert_int(CanisterLog.count(FIRST + i)).is_equal(i + 1)
	assert_int(CanisterLog.count(0)).is_equal(1)                          # dev_tour: its first sector lists one entry ...
	assert_int(CanisterLog.count(3)).is_equal(4)                          # ... and its fourth four
	assert_int(CanisterLog.count(99999)).is_equal(0)                      # a sector of no campaign has no log


func test_the_campaign_of_a_sector() -> void:
	for sector in range(FIRST, FIRST + ORDER.size()):
		assert_str(CanisterLog.campaign_of(sector).id).is_equal(TEST_C)
	assert_str(CanisterLog.campaign_of(0).id).is_equal(&"dev_tour")
	assert_object(CanisterLog.campaign_of(99999)).is_null()


func test_the_newest_entry_is_not_simply_the_sector_number() -> void:
	for i in ORDER.size():
		assert_int(CanisterLog.newest(FIRST + i)).is_equal(ORDER[i])           # the last number unlocked so far
	assert_int(CanisterLog.newest(99999)).is_equal(0)


func test_the_list_is_sorted_and_opens_on_the_newest_entry() -> void:
	assert_array(Array(CanisterLog.entries(FIRST))).is_equal([3])
	assert_array(Array(CanisterLog.entries(FIRST + 1))).is_equal([1, 3])
	assert_int(CanisterLog.initial_row(FIRST + 1)).is_equal(0)               # the newest, 1, sorts first
	assert_array(Array(CanisterLog.entries(FIRST + 2))).is_equal([1, 3, 4])
	assert_int(CanisterLog.initial_row(FIRST + 2)).is_equal(2)               # 4 is the newest and the last of the sorted three
	assert_array(Array(CanisterLog.entries(FIRST + 3))).is_equal([1, 3, 4, 9])
	assert_int(CanisterLog.initial_row(FIRST + 3)).is_equal(3)
	assert_array(Array(CanisterLog.entries(FIRST + 4))).is_equal([1, 2, 3, 4, 9])
	assert_int(CanisterLog.initial_row(FIRST + 4)).is_equal(1)               # 2 is the newest, second in the sorted list
	assert_array(Array(CanisterLog.entries(FIRST + 8))).is_equal(range(1, 10))
	assert_int(CanisterLog.initial_row(FIRST + 8)).is_equal(6)               # 7 is the 7th entry


func test_a_campaign_can_be_named_instead_of_found_from_the_sector() -> void:
	# a campaign made by the test, for the sector number it names (the functions take the campaign as their last argument)
	var campaign := Campaign.new()
	campaign.sectors = PackedInt32Array([7, 8])
	campaign.log_unlock_order = PackedInt32Array([2, 1])
	assert_array(Array(CanisterLog.entries(7, campaign))).is_equal([2])
	assert_array(Array(CanisterLog.entries(8, campaign))).is_equal([1, 2])
	assert_int(CanisterLog.newest(8, campaign)).is_equal(1)
	assert_int(CanisterLog.initial_row(8, campaign)).is_equal(0)


func test_every_entry_of_a_sector_comes_from_the_same_campaign() -> void:
	for sector in range(FIRST, FIRST + ORDER.size()):
		var campaign := CanisterLog.campaign_of(sector)
		assert_int(CanisterLog.entries(sector).size()).is_equal(CanisterLog.count(sector))
		assert_bool(CanisterLog.entries(sector).has(CanisterLog.newest(sector))).is_true()
		assert_str(campaign.log_entry_text(CanisterLog.newest(sector))).starts_with("Test log entry")
		assert_str(campaign.log_voice_name(CanisterLog.newest(sector))).starts_with("log_")


func test_the_caption_patches_series_and_number_into_the_template() -> void:
	assert_str(CanisterLog.label("ENTRY", _campaign(), 7)).is_equal("ENTRY 3.07")
	assert_str(CanisterLog.label("ENTRY", _campaign(), 9)).is_equal("ENTRY 3.09")
	assert_str(CanisterLog.label("ENTRY", Catalog.campaign(&"dev_tour"), 1)).is_equal("ENTRY 1.01")


func test_the_entry_text_and_speech_index_match_the_number() -> void:
	assert_str(_campaign().log_entry_text(7)).starts_with("Test log entry 7")
	assert_str(_campaign().log_voice_name(7)).is_equal(&"log_6")
	assert_str(_campaign().log_entry_text(0)).is_empty()                      # there is no entry 0


func test_rows_are_two_columns_of_eight() -> void:
	assert_object(CanisterLog.row_position(0)).is_equal(Vector2i(362, 88))
	assert_object(CanisterLog.row_position(7)).is_equal(Vector2i(362, 228))
	assert_object(CanisterLog.row_position(8)).is_equal(Vector2i(485, 88))
	assert_object(CanisterLog.row_position(15)).is_equal(Vector2i(485, 228))      # DONE after 15 entries


func test_up_and_down_wrap_over_the_entries_and_done() -> void:
	assert_int(CanisterLog.next_row(0, 5, CanisterLog.Move.UP)).is_equal(5)       # row 5 = DONE
	assert_int(CanisterLog.next_row(5, 5, CanisterLog.Move.DOWN)).is_equal(0)
	assert_int(CanisterLog.next_row(2, 5, CanisterLog.Move.DOWN)).is_equal(3)
	assert_int(CanisterLog.next_row(2, 5, CanisterLog.Move.UP)).is_equal(1)


func test_sideways_jumps_to_the_other_column_and_stops_at_done() -> void:
	assert_int(CanisterLog.next_row(2, 15, CanisterLog.Move.SIDEWAYS)).is_equal(10)
	assert_int(CanisterLog.next_row(10, 15, CanisterLog.Move.SIDEWAYS)).is_equal(2)
	assert_int(CanisterLog.next_row(7, 15, CanisterLog.Move.SIDEWAYS)).is_equal(15)   # DONE
	assert_int(CanisterLog.next_row(3, 5, CanisterLog.Move.SIDEWAYS)).is_equal(5)     # the right column does not exist: DONE


func test_the_canister_problem_carries_the_sectors_entry() -> void:
	var problem := ProblemFactory.for_canister(Catalog.sector(FIRST + 3), 0)
	assert_int(problem.log_index).is_equal(8)                # entry 9: its number - 1
	assert_int(problem.log_sector).is_equal(FIRST + 3)
	assert_str(problem.success).starts_with("Test log entry 9")
	var first := ProblemFactory.for_canister(Catalog.sector(FIRST), 0)
	assert_int(first.log_index).is_equal(2)                  # the first sector delivers entry 3
	assert_str(first.success).starts_with("Test log entry 3")
	var tour := ProblemFactory.for_canister(Catalog.sector(0), 0)     # dev_tour's own entries (in its own words too)
	assert_int(tour.log_index).is_equal(0)
