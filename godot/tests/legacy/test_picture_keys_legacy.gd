class_name TestPictureKeysLegacy
extends GdUnitTestSuite
## Teaches: the same rule as tests/engine/test_picture_keys.gd on the original's content: every key the legacy pack's data holds is answered by a row of its `pictures.json`, and every row is held by the data, asked for by
## name or by place, or an alias (`PictureUse`). The importer writes the table and the keys (tools/import/picture_table.py, `Tres.picture`); this checks what it wrote from the engine's side.


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_every_key_the_data_of_the_legacy_pack_holds_has_a_picture() -> void:
	var lacking := PictureUse.unanswered(Packs.chosen())
	assert_array(lacking).override_failure_message("keys the data holds that no picture answers:\n" + "\n".join(lacking)).is_empty()


func test_every_row_of_the_legacy_table_is_held_asked_for_or_an_alias() -> void:
	var loose := PictureUse.unjustified(Packs.chosen())
	assert_array(loose).override_failure_message("rows nothing holds or asks for:\n" + "\n".join(loose)).is_empty()


func test_every_row_that_names_a_file_names_a_picture_that_decodes() -> void:
	var table := Packs.chosen().picture_table()
	assert_int(table.files.size()).is_greater(1000)
	for key: String in table.files:
		assert_object(Pictures.resolve(key)).override_failure_message(key).is_not_null()


func test_the_table_has_a_row_for_every_name_the_registry_gives_a_picture() -> void:
	var table := Packs.chosen().picture_table()
	for kind: StringName in [&"ui_picture", &"problem_art"]:
		for picture_name: String in NameRegistry.original().entries(kind):
			assert_bool(table.has("%s/%s" % [kind, picture_name])).override_failure_message("%s/%s" % [kind, picture_name]).is_true()
