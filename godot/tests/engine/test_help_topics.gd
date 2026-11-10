class_name TestHelpTopics
extends GdUnitTestSuite
## Teaches: testing against the pack in use: every Help menu item must lead to readable text, and the viewer pages through it. (The original's page counts, key
## glyphs and About page: tests/legacy/test_help_topics_legacy.gd.)

















func test_the_menu_has_seven_topics_and_each_has_pages() -> void:
	var menu: PackedStringArray = Catalog.text(&"help_menu_items").split("\n")
	assert_int(menu.size()).is_equal(HelpTopics.count())
	for topic in HelpTopics.count():
		var pages := HelpTopics.pages(topic)
		assert_array(Array(pages)).is_not_empty()
		for page in pages:
			assert_str(page).is_not_empty()
			assert_bool("\u0001" in page or "ÿ" in page).is_false()          # no font control codes left


func test_every_topic_is_the_pages_the_table_lists_and_practice_has_its_own() -> void:
	for topic in 6:
		assert_int(HelpTopics.pages(topic).size()).is_equal(HelpTopics.TOPICS[topic].size())
		for i in HelpTopics.TOPICS[topic].size():
			assert_str(HelpTopics.pages(topic)[i]).is_equal(HelpTopics.clean(Catalog.text(HelpTopics.TOPICS[topic][i])))
	assert_int(HelpTopics.pages(0, true).size()).is_equal(HelpTopics.PRACTICE_TOPIC.size())
	assert_str(HelpTopics.pages(0, true)[1]).is_equal(HelpTopics.clean(Catalog.text(HelpTopics.PRACTICE_TOPIC[1])))


func test_key_glyphs_become_arrows_and_words_and_font_markers_go() -> void:
	var raw := "Press %cleft, %cright, %cup or %cdown, then %c and %c. \u00ff\u0002\u00ff Done\u00b0now." % [0x19, 0x1a, 0x1c, 0x1b, 0x11, 0x17]
	var cleaned := HelpTopics.clean(raw)
	assert_str(cleaned).contains("←left, →right, ↑up or ↓down").contains("Space and Enter.")
	assert_str(cleaned).not_contains("ÿ").not_contains("°")
	assert_str(cleaned).contains("Done now.")


## The calculator's key caps: `ConvertTextMarkup` (0x415ebf) turns the tab into glyph 0x13 (N) and copies 0x15 (S) and
## 0x0f (R), so the key table of "Using the Calculator" names its keys and "Press N, ... Press N again" reads.
func test_the_calculator_keys_are_written_out() -> void:
	var raw := "\t\u0001   Negates. Press \t, \rthen type. Press \t again.\r\r\u0015\u0001   Stores.\r\r\u000f\u0001   Recalls.\r"
	var cleaned := HelpTopics.clean(raw)
	assert_str(cleaned).is_equal("N   Negates. Press N, \nthen type. Press N again.\n\nS   Stores.\n\nR   Recalls.")


## Glyph 0x10 is the C key cap, written directly in text 10162 (and made from 0x0b by `ConvertTextMarkup`).
func test_the_clear_key_is_written_out_from_either_code() -> void:
	assert_str(HelpTopics.clean("Press \u0010 or \u000b to clear.")).is_equal("Press C or C to clear.")


func test_the_about_page_is_the_texts_then_the_version_then_the_copyright() -> void:
	var raw := HelpTopics.about_text()
	var texts := ""
	for text_name in HelpTopics.ABOUT_TEXTS:
		texts += Catalog.text(text_name)
	assert_str(raw).is_equal(texts + Catalog.text(&"version_line") + "\n" + Catalog.text(&"copyright_line") + "\n")
	var page := HelpTopics.pages(HelpTopics.TOPIC_COUNT - 1)[0]
	assert_str(page).is_equal(HelpTopics.clean(raw))
	assert_int(page.find(Catalog.text(&"version_line"))).is_greater(page.find(Catalog.text(&"about_0")))
	assert_int(page.find(Catalog.text(&"copyright_line"))).is_greater(page.find(Catalog.text(&"version_line")))


func _viewer(topic: int, practice: bool = false) -> HelpViewer:
	var viewer: HelpViewer = auto_free(load("res://src/ui/help_viewer.tscn").instantiate())
	add_child(viewer)
	viewer.show_topic(topic, practice)
	return viewer


func _focused(viewer: HelpViewer) -> Control:
	return viewer.get_viewport().gui_get_focus_owner()


func test_the_viewer_pages_forwards_and_back() -> void:
	var viewer := _viewer(5)                                                  # Educational Focus: four pages
	assert_int(viewer.page_count()).is_equal(4)
	assert_bool(viewer.back_button.visible).is_false()
	viewer.show_page(1, true)
	assert_int(viewer.page).is_equal(1)
	viewer.show_page(99, true)
	assert_int(viewer.page).is_equal(3)
	assert_bool(viewer.next_button.visible).is_false()
	assert_str(viewer.title_label.text).is_equal(Catalog.text(&"help_menu_items").split("\n")[5])


## G29: `RunPagedDialog` (0x417755) shows only the buttons that make sense on the page and highlights the first one on page 1,
## the right one on every other page; Enter presses the highlighted button.
func test_the_buttons_follow_run_paged_dialog() -> void:
	var viewer := _viewer(0)                                                  # Playing the Game: two pages
	assert_array([viewer.back_button.visible, viewer.next_button.visible, viewer.done_button.visible]).is_equal([false, true, false])
	assert_object(_focused(viewer)).is_same(viewer.next_button)
	viewer.show_page(1)
	assert_array([viewer.back_button.visible, viewer.next_button.visible, viewer.done_button.visible]).is_equal([true, false, true])
	assert_object(_focused(viewer)).is_same(viewer.done_button)
	var single := _viewer(1)                                                  # Using the Keyboard: one page, only Done
	assert_array([single.back_button.visible, single.next_button.visible, single.done_button.visible]).is_equal([false, false, true])
	var middle := _viewer(5)                                                  # Educational Focus
	middle.show_page(1)
	assert_array([middle.back_button.visible, middle.next_button.visible, middle.done_button.visible]).is_equal([true, true, false])
	assert_object(_focused(middle)).is_same(middle.next_button)


func _press_enter(viewer: HelpViewer) -> void:
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	viewer.get_viewport().push_input(enter)
	var release := InputEventKey.new()
	release.keycode = KEY_ENTER
	release.physical_keycode = KEY_ENTER
	release.pressed = false
	viewer.get_viewport().push_input(release)


func test_enter_on_a_multi_page_topic_goes_to_the_next_page_and_only_the_last_page_closes() -> void:
	var viewer := _viewer(4)                                                  # Using the Calculator: three pages
	var closed := [0]
	viewer.closed.connect(func() -> void: closed[0] += 1)
	_press_enter(viewer)
	assert_int(viewer.page).is_equal(1)
	assert_int(closed[0]).is_equal(0)
	_press_enter(viewer)
	assert_int(viewer.page).is_equal(2)
	assert_int(closed[0]).is_equal(0)
	_press_enter(viewer)                                                      # "Done" on the last page
	assert_int(closed[0]).is_equal(1)
