class_name TestScreenEditorFoesLegacy
extends GdUnitTestSuite
## The creature markers on the original's sector 0: the first creature is the committed record (position, start picture and the label its script names).
## The markers, on the ground sector of dev, are in `tests/engine/test_screen_editor_foes.gd`.


func test_the_markers_of_sector_0_screen_0_show_the_start_pictures() -> void:
	var editor := auto_free(ScreenEditor.new()) as ScreenEditor
	editor.data_dir = LegacyPack.SECTORS_DIR                 # (the authoring files of the project's legacy folder, whatever pack is played)
	editor.sector = 0
	editor.screen = 0
	add_child(editor)
	var first: ScreenEditorFoe = null
	for child in editor.get_node("Foes").get_children():
		if (child as ScreenEditorFoe).foe_index == 0:
			first = child as ScreenEditorFoe
	assert_object(first).is_not_null()
	assert_vector(first.pixel_position()).is_equal(Vector2i(360, 222))
	assert_int(first.start_frame).is_equal(3)
	assert_str(first.start_label).is_equal("foe0_start")


func test_the_picture_of_a_creature_is_resolved_by_its_original_name() -> void:
	var editor := auto_free(ScreenEditor.new()) as ScreenEditor
	editor.data_dir = LegacyPack.SECTORS_DIR                 # (the authoring files of the project's legacy folder, whatever pack is played)
	editor.sector = 0
	editor.screen = 0
	add_child(editor)
	for child in editor.get_node("Foes").get_children():
		var marker := child as ScreenEditorFoe
		assert_str(marker.picture_name(marker.start_frame)).is_equal(NameRegistry.original().name_of(&"frame", marker.start_frame, 0))
