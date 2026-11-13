class_name TestPictureKeys
extends GdUnitTestSuite
## Teaches: the data holds KEYS and the pack's table answers them, checked both ways over a whole pack. Every key a resource of the dev pack holds (a `PictureRef` of a `.tres`, a problem type's `art_keys`, the closing
## crew's `pictures`, a campaign's `finale_picture`) is a key some row of the dev pack's `pictures.json` answers with a picture, and every row of that table is held by the data, asked for by name or by place, or an alias
## (`PictureUse` says what each of those is). The same rule is held on the legacy pack (tests/legacy/test_picture_keys_legacy.gd).


func test_every_key_the_data_of_dev_holds_has_a_picture() -> void:
	var lacking := PictureUse.unanswered(Packs.dev())
	assert_array(lacking).override_failure_message("keys the data holds that no picture answers:\n" + "\n".join(lacking)).is_empty()


func test_every_row_of_the_table_of_dev_is_held_asked_for_or_an_alias() -> void:
	var loose := PictureUse.unjustified(Packs.dev())
	assert_array(loose).override_failure_message("rows nothing holds or asks for:\n" + "\n".join(loose)).is_empty()


func test_the_data_holds_pictures_by_key_and_by_nothing_else() -> void:
	var held := PictureUse.held(Packs.dev())
	assert_int(held.size()).is_greater(200)
	for key: String in held:
		assert_bool(PictureTable.is_key(key)).override_failure_message(key).is_true()
	for rel in Packs.dev().all_files():
		if rel.begins_with("data/") and rel.get_extension() == "tres":
			assert_str(Packs.dev().read_text(rel)).override_failure_message("%s names a picture file" % rel).not_contains('type="Texture2D" uid=').not_contains('.png"')


func test_the_table_of_dev_is_a_row_for_every_name_the_registry_gives_a_picture() -> void:
	var table := Packs.dev().picture_table()
	for kind: StringName in [&"ui_picture", &"problem_art"]:
		for picture_name: String in NameRegistry.original().entries(kind):
			assert_bool(table.has("%s/%s" % [kind, picture_name])).override_failure_message("%s/%s" % [kind, picture_name]).is_true()
