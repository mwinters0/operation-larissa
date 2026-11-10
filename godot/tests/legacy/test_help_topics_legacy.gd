class_name TestHelpTopicsLegacy
extends GdUnitTestSuite
## Teaches: testing against the real extracted data: every Help menu item of the original must lead to readable text, with the original's page counts, key
## glyphs and About page. (The viewer and the topics table on any pack: tests/engine/test_help_topics.gd.)


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_the_menu_has_seven_topics_and_each_has_pages() -> void:
	var menu: PackedStringArray = Catalog.texts("ui_strings").text(11053).split("\n")
	assert_int(menu.size()).is_equal(HelpTopics.count())
	for topic in HelpTopics.count():
		var pages := HelpTopics.pages(topic)
		assert_bool(pages.size() > 0).is_true()
		for page in pages:
			assert_bool(page.length() > 40).is_true()
			assert_bool("\u0001" in page or "ÿ" in page).is_false()          # no font control codes left


func test_key_glyphs_become_arrows_and_words() -> void:
	var keyboard := HelpTopics.pages(1)[0]
	assert_str(keyboard).contains("Moves sub down, up, left, or right")
	assert_str(keyboard).contains("←")


## `ConvertTextMarkup` (0x415ebf) turns the tab of text 12016 into the key glyph N and passes 0x15 (S) and 0x0f (R);
## the font's glyphs 0x13, 0x15, 0x0f are those key caps.
func test_using_the_calculator_names_its_keys() -> void:
	var page := HelpTopics.pages(4)[2]
	assert_str(page).contains("Press N, \n")
	assert_str(page).contains("Press N again")
	assert_str(page).contains("\nS ").contains("\nR ")
	assert_str(page).not_contains("Press  ").not_contains("Press ,")


func test_the_about_page_has_the_version() -> void:
	assert_str(HelpTopics.pages(6)[0]).contains("Version 1.23")


## G29: `RunHelpTopic` (0x428d70) always shows the long texts 12000-12018; the page counts are the first characters of strings
## 11116-11122 (`do_help_*_message` 0x428ed9 ...).
func test_every_topic_uses_the_long_texts_with_the_page_counts_of_strings_11116_to_11122() -> void:
	var strings := Catalog.texts("ui_strings")
	var table := Catalog.texts("help")
	var expected_ids := [[12007, 12008], [12009], [12018], [12000, 12001], [12014, 12015, 12016], [12002, 12003, 12004, 12005]]
	var registry := NameRegistry.original()
	for topic in 6:
		var announced := strings.text(11116 + topic)
		assert_int(HelpTopics.pages(topic).size()).is_equal(int(announced.substr(0, 1)))
		var numbers: Array = []
		for page: StringName in HelpTopics.TOPICS[topic]:
			numbers.append(registry.index_of(&"text", page))
		assert_array(numbers).is_equal(expected_ids[topic])
		for i in HelpTopics.TOPICS[topic].size():
			assert_str(HelpTopics.pages(topic)[i]).is_equal(HelpTopics.clean(table.texts[expected_ids[topic][i]]))
	# Math Practice (11122: 3 pages 12011-12013, including 12012 the port used to skip)
	assert_int(int(strings.text(11122).substr(0, 1))).is_equal(3)
	assert_int(HelpTopics.pages(0, true).size()).is_equal(3)
	assert_str(HelpTopics.pages(0, true)[1]).is_equal(HelpTopics.clean(table.texts[12012]))
	assert_str(HelpTopics.pages(0, true)[1]).contains("Use the following symbols on your keyboard")


## G32: `MenuAboutBox` (0x42b74c) joins 11144-11146, three newlines (11147-11149), Version (11002), Copyright (11001).
func test_the_about_text_is_built_like_menu_about_box() -> void:
	var strings := Catalog.texts("ui_strings")
	assert_str(strings.text(11147) + strings.text(11148) + strings.text(11149)).is_equal("\n\n\n")
	var raw := HelpTopics.about_text()
	assert_str(raw).is_equal(strings.text(11144) + strings.text(11145) + strings.text(11146) + "\n\n\n" \
			+ strings.text(11002) + "\n" + strings.text(11001) + "\n")
	var page := HelpTopics.pages(6)[0]
	assert_str(page).is_equal(HelpTopics.clean(raw))
	assert_bool(page.begins_with("In Operation Neptune, players solve")).is_true()          # the text first ...
	assert_int(page.find("Version 1.23")).is_greater(page.find("an easy-to-use word processor"))   # ... then the version ...
	assert_int(page.find("Copyright")).is_greater(page.find("Version 1.23"))                 # ... then the copyright
	assert_str(page).contains("pre-algebra math and problem-solving skills.")      # no hard break between 11144 and 11145
	assert_str(page).contains("Version 1.23\nCopyright")
	assert_str(page).contains("grammar and writing tips.\n\n\nVersion 1.23")
	assert_str(strings.text(11150)).is_equal("About Operation Neptune")
