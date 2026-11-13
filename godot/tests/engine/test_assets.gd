class_name TestAssets
extends GdUnitTestSuite
## Teaches: testing a resolver from the name side. Every NAME the registry holds for a picture or a string must turn into the
## thing (a texture, a text) in a complete pack. Also the Inspector's picture drop-down of `FoeData` (`picture_choices`).
## (The file side, the original's folders and numbers, is in tests/legacy/test_assets_legacy.gd.)


func test_every_named_ui_picture_loads() -> void:
	for picture_name: String in NameRegistry.original().entries(&"ui_picture"):
		assert_object(Assets.ui_picture(StringName(picture_name))).override_failure_message("ui_picture '%s'" % picture_name).is_not_null()


func test_every_named_problem_art_loads() -> void:
	for picture_name: String in NameRegistry.original().entries(&"problem_art"):
		assert_object(Assets.problem_art(StringName(picture_name))).override_failure_message("problem_art '%s'" % picture_name).is_not_null()


func test_a_name_is_the_name_of_a_key() -> void:
	assert_object(Assets.ui_picture(&"title_sky")).is_same(Assets.picture_by_key("ui_picture/title_sky"))
	assert_object(Assets.problem_art(&"log_scan_0")).is_same(Assets.picture_by_key("problem_art/log_scan_0"))
	assert_object(Assets.ui_picture(&"ui_2025")).override_failure_message("a picture nobody named is held by its made-up name").is_same(Assets.picture_by_key("ui_picture/ui_2025"))
	assert_object(Assets.ui_picture(&"ui_1039")).override_failure_message("the made-up name of a picture that has a name is no key").is_null()


# --- strings, songs, speech and sounds by name ---------------------------------------------------------------

func test_every_named_text_resolves_to_its_string() -> void:
	var registry := NameRegistry.original()
	for text_name: String in registry.entries(&"text"):
		var id := registry.index_of(&"text", text_name)
		var expected := ""
		for table_name in Catalog.TEXT_TABLES:
			if Catalog.texts(table_name).texts.has(id):
				expected = Catalog.texts(table_name).text(id)
		assert_str(Catalog.text(StringName(text_name))).override_failure_message("text '%s'" % text_name).is_equal(expected)


func test_a_text_the_data_does_not_have_is_known_by_has_text() -> void:
	assert_bool(Catalog.has_text(&"click_to_go_on")).is_true()
	assert_str(Catalog.text(&"click_to_go_on")).is_not_empty()
	assert_bool(Catalog.has_text(&"no_such_text")).is_false()


func test_a_song_a_clip_and_an_effect_are_found_by_name() -> void:
	assert_object(Catalog.music_catalog().stream_named(&"title")).is_not_null()
	assert_object(Catalog.voice_index().stream_named(&"sign_in_begin_1")).is_not_null()
	assert_object(Catalog.sfx_catalog().stream_named(&"lock_tick")).is_not_null()
	assert_str(Catalog.sfx_catalog().name_of(38)).is_equal("lock_tick")
	assert_str(Catalog.voice_cues().jingle()).is_equal("jingle")


# --- FoeData: pictures by name in the Inspector -------------------------------------------------------------------

func test_the_picture_drop_down_lists_the_zones_names_with_the_original_numbers() -> void:
	var hint := FoeData.picture_choices(1, 35)
	assert_str(hint).contains("eel_swim_0:35")
	assert_str(hint).contains("dolphin_swim_0:0")                            # the common pictures are in every zone
	assert_str(FoeData.picture_choices(0, 35)).not_contains("eel_swim_0")  # ... the zone's own only in it


func test_a_picture_the_list_does_not_offer_is_added_as_the_current_choice() -> void:
	assert_str(FoeData.picture_choices(1, 60)).ends_with("frame_060:60")             # nobody named it: its made-up name
	assert_str(FoeData.picture_choices(1, 35 + 128)).ends_with("eel_swim_0 mirrored:163")   # bit 7: mirrored
	assert_str(FoeData.picture_choices(1, 35)).not_contains("mirrored")


func test_a_creature_of_a_sector_file_shows_its_pictures_by_name_and_keeps_the_number() -> void:
	var foe := Catalog.sector(0).foes[0]
	var shown := {}
	for property in foe.get_property_list():
		if property["name"] in FoeData.PICTURE_PROPERTIES:
			shown[property["name"]] = property
	assert_int(shown.size()).is_equal(3)
	for property_name: String in shown:
		assert_int(shown[property_name]["hint"]).is_equal(PROPERTY_HINT_ENUM)
		assert_int(shown[property_name]["type"]).is_equal(TYPE_INT)
	var zone := Catalog.sector(0).zone
	assert_str(shown["frame"]["hint_string"]).is_equal(FoeData.picture_choices(zone, foe.frame))
	var before := foe.encode()
	assert_int(before.size()).is_equal(FoeData.RECORD_SIZE)                      # still the original's 34 bytes
	assert_int(before[7]).is_equal(foe.frame)                                    # ... with the picture as a number
