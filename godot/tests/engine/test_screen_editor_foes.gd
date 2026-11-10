class_name TestScreenEditorFoes
extends GdUnitTestSuite
## Teaches: testing the creature markers of the screen editor without the editor. The creatures (`FoeData`) live in the
## SECTOR file, so the claims are: every creature has exactly one marker, on the screen it starts on, with its start picture;
## the markers read back as the records they came from (an unchanged screen writes nothing); a moved marker changes the
## record's `pos` and only that line of `sector_NN.tres`; what the original record can not hold is refused like
## `FoeData.problems()`. Saving goes into a COPY of the data (user://), never the committed files.

const SECTORS := DevPack.SECTORS_DIR
const TEMP := "user://screen_editor_foes_test"


func _editor(sector: int, screen: int, dir: String = SECTORS, in_tree: bool = false) -> ScreenEditor:
	var editor := auto_free(ScreenEditor.new()) as ScreenEditor
	editor.data_dir = dir
	editor.sector = sector
	editor.screen = screen
	if in_tree:
		add_child(editor)
	else:
		editor.reload()
	return editor


func _temp_copy(s: int) -> String:
	DirAccess.make_dir_recursive_absolute(Catalog.sector_dir(s, TEMP))
	DirAccess.copy_absolute(Catalog.sector_path(s, SECTORS), Catalog.sector_path(s, TEMP))
	for m in Catalog.SCREENS_PER_SECTOR:
		DirAccess.copy_absolute(ScreenFile.screen_path(SECTORS, s, m), ScreenFile.screen_path(TEMP, s, m))
	return TEMP


func after_test() -> void:
	if DirAccess.dir_exists_absolute(TEMP):
		for s in Ground.clean_sectors():
			for m in Catalog.SCREENS_PER_SECTOR:
				DirAccess.remove_absolute(ScreenFile.screen_path(TEMP, s, m))
			DirAccess.remove_absolute(Catalog.sector_path(s, TEMP))
			DirAccess.remove_absolute(Catalog.sector_dir(s, TEMP))
		DirAccess.remove_absolute(TEMP)


func _markers(editor: ScreenEditor) -> Array[ScreenEditorFoe]:
	var found: Array[ScreenEditorFoe] = []
	for child in editor.get_node("Foes").get_children():
		found.append(child as ScreenEditorFoe)
	return found


func _marker(editor: ScreenEditor, index: int) -> ScreenEditorFoe:
	for marker in _markers(editor):
		if marker.foe_index == index:
			return marker
	return null


## The first (sector, screen) whose creature list has a creature for which `wanted` is true: [sector, screen, index].
func _find(wanted: Callable) -> Array[int]:
	for s in Ground.clean_sectors():
		var sector := Catalog.sector(s)
		for i in sector.foes.size():
			if wanted.call(sector.foes[i]):
				return [s, sector.foes[i].screen, i]
	return []


# --- the markers show the creatures -------------------------------------------------------------------------------------

func test_every_creature_of_every_sector_has_one_marker_on_its_start_screen() -> void:
	var problems: Array[String] = []
	for s in Ground.clean_sectors():
		var sector := Catalog.sector(s)
		var counted := 0
		for m in Catalog.SCREENS_PER_SECTOR:
			var editor := _editor(s, m)
			var markers := _markers(editor)
			var expected: Array[int] = []
			for i in sector.foes.size():
				if sector.foes[i].screen == m:
					expected.append(i)
			var indexes: Array[int] = []
			for marker in markers:
				indexes.append(marker.foe_index)
				var foe := sector.foes[marker.foe_index]
				if marker.pixel_position() != foe.pos or marker.start_frame != foe.frame or marker.flip_h != foe.flip:
					problems.append("sector %d creature %d: marker differs from the record" % [s, marker.foe_index])
			if indexes != expected:
				problems.append("sector %d screen %d: markers %s, creatures %s" % [s, m, indexes, expected])
			counted += markers.size()
			editor.free()
		if counted != sector.foes.size():
			problems.append("sector %d: %d markers for %d creatures" % [s, counted, sector.foes.size()])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_the_markers_of_the_first_creatures_screen_show_the_start_pictures() -> void:
	var editor := _editor(Ground.MAIN, 4, SECTORS, true)
	var sector := Ground.main()
	var markers := _markers(editor)
	assert_int(markers.size()).is_greater(0)
	for marker in markers:
		var foe := sector.foes[marker.foe_index]
		assert_object(marker.sprite_frames).is_same(editor.frames_for(marker))
		assert_str(marker.sprite_frames.resource_path).ends_with("foes_zone%d.tres" % sector.zone)
		assert_int(marker.frame).is_equal(foe.frame)
		assert_vector(marker.position).is_equal(Vector2(foe.pos))
		assert_vector(Vector2(marker.sprite_frames.get_frame_texture(&"all", marker.frame).get_size())).is_not_equal(Vector2.ZERO)
	# the first creature of the sector: a record of the committed file
	var first := _marker(editor, 0)
	assert_vector(first.pixel_position()).is_equal(sector.foes[0].pos)
	assert_int(first.start_frame).is_equal(sector.foes[0].frame)
	assert_str(first.start_label).is_equal("patrol_start")


func test_the_picture_is_resolved_by_name_through_the_registry() -> void:
	var editor := _editor(Ground.MAIN, 4, SECTORS, true)
	var marker := _marker(editor, 0)
	var expected := NameRegistry.original().name_of(&"frame", marker.start_frame, Ground.main().zone)
	assert_str(expected).is_not_empty()
	assert_str(marker.picture_name(marker.start_frame)).is_equal(expected)
	# the Inspector offers the zone's pictures by name, the stored value stays the original's number
	var property := {"name": &"start_frame", "type": TYPE_INT, "usage": PROPERTY_USAGE_DEFAULT, "hint": 0, "hint_string": ""}
	marker._validate_property(property)
	assert_int(property.hint).is_equal(PROPERTY_HINT_ENUM)
	assert_str(property.hint_string).contains("%s:%d" % [expected, marker.start_frame])


func test_a_mirrored_creature_is_drawn_mirrored() -> void:
	var found := _find(func(foe: FoeData) -> bool: return foe.flip)
	assert_array(found).is_not_empty()
	var editor := _editor(found[0], found[1], SECTORS, true)
	var marker := _marker(editor, found[2])
	assert_bool(marker.flip).is_true()
	assert_bool(marker.flip_h).is_true()
	marker.flip = false
	assert_bool(marker.flip_h).is_false()


func test_hidden_and_dormant_creatures_look_different() -> void:
	# the ground sector has a creature that is hidden only (2) and one hidden AND dormant (5), none that is only dormant
	var hidden := _find(func(foe: FoeData) -> bool: return foe.hidden and not foe.dormant)
	var both := _find(func(foe: FoeData) -> bool: return foe.hidden and foe.dormant)
	var plain := _find(func(foe: FoeData) -> bool: return not foe.dormant and not foe.hidden)
	assert_array(hidden).is_not_empty()
	assert_array(both).is_not_empty()
	var hidden_marker := _marker(_editor(hidden[0], hidden[1], SECTORS, true), hidden[2])
	var both_marker := _marker(_editor(both[0], both[1], SECTORS, true), both[2])
	var plain_marker := _marker(_editor(plain[0], plain[1], SECTORS, true), plain[2])
	assert_bool(plain_marker.modulate == Color.WHITE).is_true()
	assert_float(hidden_marker.modulate.a).is_less(1.0)
	assert_float(hidden_marker.modulate.r).is_equal(1.0)                      # faint, not tinted
	assert_float(both_marker.modulate.a).is_less(1.0)
	assert_float(both_marker.modulate.r).is_less(1.0)                         # faint and tinted
	plain_marker.starts_dormant = true                                          # only dormant: tinted, not faint
	assert_float(plain_marker.modulate.a).is_equal(1.0)
	assert_float(plain_marker.modulate.r).is_less(1.0)
	plain_marker.move_to_screen = (plain[1] + 1) % 12                         # leaves the screen after saving: dimmed
	assert_float(plain_marker.modulate.a).is_less(1.0)


# --- reading the markers back ------------------------------------------------------------------------------------------

func test_an_unchanged_screen_builds_the_same_creatures_and_is_not_dirty() -> void:
	for pair: Array in [[Ground.MAIN, 4], [Ground.MAIN, 1], [Ground.EDIT, 7], [Ground.MAP, 9], [Ground.FINALE, 2], [Ground.LEDGE, 3]]:
		var editor := _editor(pair[0], pair[1])
		var built := editor.build()
		assert_array(built.problems).is_empty()
		var sector := Catalog.sector(pair[0])
		assert_int(built.foes.size()).is_equal(sector.foes.size())
		for i in sector.foes.size():
			assert_array(ScreenFile.FOE_FIELDS.map(func(n: String) -> Variant: return built.foes[i].get(n))) \
					.is_equal(ScreenFile.FOE_FIELDS.map(func(n: String) -> Variant: return sector.foes[i].get(n)))
			assert_array(Array(built.foes[i].runtime_state)).is_equal(Array(sector.foes[i].runtime_state))
		assert_bool(editor.is_dirty()).is_false()


func test_saving_an_unchanged_screen_writes_nothing_and_keeps_the_files_byte_identical() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var sector_before := FileAccess.get_file_as_bytes(ScreenFile.sector_path(dir, Ground.MAIN))
	var screen_before := FileAccess.get_file_as_bytes(ScreenFile.screen_path(dir, Ground.MAIN, 4))
	var editor := _editor(Ground.MAIN, 4, dir)
	assert_bool(editor.is_dirty()).is_false()
	assert_bool(editor.save_screen()).is_true()
	assert_array(Array(FileAccess.get_file_as_bytes(ScreenFile.sector_path(dir, Ground.MAIN)))).is_equal(Array(sector_before))
	assert_array(Array(FileAccess.get_file_as_bytes(ScreenFile.screen_path(dir, Ground.MAIN, 4)))).is_equal(Array(screen_before))


func test_the_creature_patch_of_equal_lists_is_the_text_unchanged() -> void:
	for s in [Ground.MAIN, Ground.EDIT, Ground.FINALE]:
		var text := FileAccess.get_file_as_string(Catalog.sector_path(s, SECTORS))
		var sector := Catalog.sector(s)
		var result := ScreenFile.foes_text(text, sector.foes, sector.foes)
		assert_str(result.error).is_empty()
		assert_bool(result.text == text).is_true()


# --- moving a marker --------------------------------------------------------------------------------------------------

func test_moving_a_marker_changes_that_record_and_only_that_line_of_the_sector() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var editor := _editor(Ground.MAIN, 4, dir)
	var marker := _marker(editor, 0)
	var old: Vector2i = marker.pixel_position()
	marker.position = Vector2(old) + Vector2(20, -10)
	assert_bool(editor.is_dirty()).is_true()
	var built := editor.build()
	assert_array(built.problems).is_empty()
	assert_vector(built.foes[0].pos).is_equal(old + Vector2i(20, -10))
	assert_vector(built.foes[1].pos).is_equal(Ground.main().foes[1].pos)

	var before := FileAccess.get_file_as_string(ScreenFile.sector_path(dir, Ground.MAIN)).split("\n")
	assert_bool(editor.save_screen()).is_true()
	var after := FileAccess.get_file_as_string(ScreenFile.sector_path(dir, Ground.MAIN)).split("\n")
	assert_int(after.size()).is_equal(before.size())
	var changed: Array[String] = []
	for i in before.size():
		if before[i] != after[i]:
			changed.append("%s -> %s" % [before[i], after[i]])
	assert_array(changed).is_equal(["pos = Vector2i(%d, %d) -> pos = Vector2i(%d, %d)" % [old.x, old.y, old.x + 20, old.y - 10]])
	var saved := ResourceLoader.load(ScreenFile.sector_path(dir, Ground.MAIN), "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData
	assert_vector(saved.foes[0].pos).is_equal(old + Vector2i(20, -10))
	assert_bool(editor.is_dirty()).is_false()
	# the screen file did not change (a creature is not part of the screen record)
	assert_bool(FileAccess.get_file_as_string(ScreenFile.screen_path(dir, Ground.MAIN, 4)) == FileAccess.get_file_as_string(ScreenFile.screen_path(SECTORS, Ground.MAIN, 4))).is_true()
	# the committed sector is untouched
	assert_vector(Ground.main().foes[0].pos).is_equal(old)


func test_a_marker_snaps_to_the_originals_grid_so_dragging_never_makes_an_odd_position() -> void:
	var editor := _editor(Ground.MAIN, 4, SECTORS, true)
	var marker := _marker(editor, 0)
	marker.position = Vector2(101, 59)
	assert_vector(marker.position).is_equal(Vector2(102, 60))
	assert_array(editor.build().problems).is_empty()


func test_a_position_the_record_can_not_hold_is_refused_and_nothing_is_written() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var before := FileAccess.get_file_as_string(ScreenFile.sector_path(dir, Ground.MAIN))
	var editor := _editor(Ground.MAIN, 4, dir)
	var marker := _marker(editor, 0)
	marker.position = Vector2(-20, 100)                       # x below 0: the record keeps x / 2 unsigned
	assert_str("\n".join(editor.build().problems)).contains("creature 0: x -20 does not fit")
	assert_bool(editor.save_screen()).is_false()
	marker.position = Vector2(100, 100)
	marker.damage = 300
	assert_str("\n".join(editor.build().problems)).contains("creature 0: damage 300 does not fit")
	assert_bool(editor.save_screen()).is_false()
	assert_bool(FileAccess.get_file_as_string(ScreenFile.sector_path(dir, Ground.MAIN)) == before).is_true()


func test_a_label_the_script_does_not_have_is_refused() -> void:
	var editor := _editor(Ground.MAIN, 4)
	var marker := _marker(editor, 0)
	marker.hit_label = "no_such_label"
	assert_str("\n".join(editor.build().problems)).contains("hit_label 'no_such_label' is not a label of the sector's script")
	assert_array(Array(editor.script_labels())).contains(["patrol_start"])


func test_the_record_fields_are_saved_through_the_markers() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var editor := _editor(Ground.MAIN, 4, dir)
	var marker := _marker(editor, 0)
	marker.starts_dormant = true
	marker.starts_hidden = true
	marker.flip = true
	marker.damage = -3
	marker.frame_min = 4
	marker.frame_max = 9
	marker.start_frame = 5
	marker.ink_label = editor.script_labels()[1]
	marker.move_to_screen = 2
	assert_bool(editor.save_screen()).is_true()
	var saved := ResourceLoader.load(ScreenFile.sector_path(dir, Ground.MAIN), "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData
	var foe := saved.foes[0]
	assert_bool(foe.dormant).is_true()
	assert_bool(foe.hidden).is_true()
	assert_bool(foe.flip).is_true()
	assert_int(foe.damage).is_equal(-3)
	assert_int(foe.frame_min).is_equal(4)
	assert_int(foe.frame_max).is_equal(9)
	assert_int(foe.frame).is_equal(5)
	assert_str(foe.ink_label).is_equal(marker.ink_label)
	assert_int(foe.screen).is_equal(2)
	# the creature now starts on screen 2
	var other := _editor(Ground.MAIN, 2, dir)
	assert_bool(_marker(other, 0) != null).is_true()
	assert_bool(_marker(_editor(Ground.MAIN, 4, dir), 0) == null).is_true()


## The sector that was loaded before the save (the one the Catalog, the Sector Overview and the sandbox hold) is read again in place
## (`CACHE_MODE_REPLACE`), and its compiled script follows: the creature's new ink label is its entry point on next use.
func test_a_saved_label_is_the_entry_point_of_the_loaded_sector() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var path := ScreenFile.sector_path(dir, Ground.MAIN)
	var loaded := ResourceLoader.load(path) as SectorData                    # (cached, as the game's sector is)
	loaded.ensure_compiled()
	var editor := _editor(Ground.MAIN, 4, dir)
	var marker := _marker(editor, 0)
	var labels := editor.script_labels()
	var label: String = labels[1] if labels[1] != loaded.foes[0].ink_label else labels[2]
	marker.ink_label = label
	assert_bool(editor.save_screen()).is_true()
	assert_str(loaded.foes[0].ink_label).is_equal(label)
	loaded.ensure_compiled()
	assert_int(loaded.foes[0].script_ink).is_equal(loaded.foe_labels[label])


func test_the_edited_record_encodes_as_the_original_record_with_that_field_changed() -> void:
	var editor := _editor(Ground.MAIN, 4)
	var marker := _marker(editor, 0)
	var sector := Ground.main()
	sector.ensure_compiled()
	var original := sector.foes[0].encode()
	marker.position = Vector2(marker.pixel_position()) + Vector2(4, 0)
	var record := editor.build().foes[0]
	record.pc = sector.foes[0].pc
	record.script_hit = sector.foes[0].script_hit
	record.script_ink = sector.foes[0].script_ink
	assert_str(FoeData.first_difference(original, record.encode())).starts_with("first difference at byte 0x03 (x)")


func test_a_marker_the_sector_does_not_know_yet_is_a_problem_until_the_sector_has_taken_it() -> void:
	# deleting and duplicating markers changes the sector (test_screen_editor_markers.gd); until the editor has run
	# `sync_with_markers` the nodes and the sector disagree, and that is reported, not saved
	var editor := _editor(Ground.MAIN, 4, SECTORS, true)
	var layer := editor.get_node("Foes")
	var marker := _marker(editor, 0)
	layer.remove_child(marker)
	assert_str("\n".join(editor.build().problems)).contains("creature 0 has no marker on this screen")
	layer.add_child(marker)
	layer.add_child(marker.duplicate())
	assert_str("\n".join(editor.build().problems)).contains("creature 0 appears twice")
	marker.foe_index = 999
	assert_str("\n".join(editor.build().problems)).contains("the sector has no creature 999")
	marker.free()


func test_add_foe_marker_makes_the_marker_of_a_record() -> void:
	var editor := _editor(Ground.MAIN, 4, SECTORS, true)
	var other := editor.add_foe_marker(Ground.main().foes.size() - 1)
	assert_int(other.foe_index).is_equal(Ground.main().foes.size() - 1)
	assert_object(other.get_parent()).is_same(editor.get_node("Foes"))
	assert_object(other.sprite_frames).is_not_null()


# --- the script labels --------------------------------------------------------------------------------------------------

func test_the_line_of_a_label_in_the_creature_script() -> void:
	var text := FileAccess.get_file_as_string(Catalog.foe_path(Ground.MAIN))
	var line := ScreenEditorFoeJump.line_of_label(text, "patrol_start")
	assert_int(line).is_greater_equal(0)
	assert_str(text.split("\n")[line].strip_edges()).is_equal("patrol_start:")
	assert_int(ScreenEditorFoeJump.line_of_label(text, "no_such_label")).is_equal(-1)
	assert_array(Array(ScreenEditorFoeJump.labels_of(text))).contains(["patrol_start", "patrol_hit", "patrol_ink"])
	assert_int(ScreenEditorFoeJump.labels_of("").size()).is_equal(0)


func test_every_entry_label_of_every_creature_is_in_its_script() -> void:
	var missing: Array[String] = []
	for s in Ground.clean_sectors():
		var sector := Catalog.sector(s)
		var labels := ScreenEditorFoeJump.labels_of(sector.foe_script.source)
		for i in sector.foes.size():
			for label in [sector.foes[i].start_label, sector.foes[i].hit_label, sector.foes[i].ink_label]:
				if not labels.has(label):
					missing.append("sector %d creature %d: %s" % [s, i, label])
	assert_array(missing).is_empty()


func test_the_jump_opens_the_script_in_the_foe_panel_at_the_label() -> void:
	var panel := auto_free(FoeEditorPanel.new()) as FoeEditorPanel
	add_child(panel)
	var script := Ground.main().foe_script
	var marker := ScreenEditorFoe.from_record(Ground.main().foes[1], 1)
	auto_free(marker)
	assert_str(ScreenEditorFoeJump.show_label(panel, script, marker.hit_label)).is_empty()
	var doc := panel.current_document()
	assert_str(doc.path()).is_equal(script.resource_path)
	var line := ScreenEditorFoeJump.line_of_label(script.source, marker.hit_label)
	assert_int(doc.edit.get_caret_line()).is_equal(line)
	assert_str(ScreenEditorFoeJump.show_label(panel, script, "no_such_label")).contains("is not a label")
	assert_str(ScreenEditorFoeJump.show_label(panel, script, "")).contains("no label")
	assert_str(ScreenEditorFoeJump.show_label(panel, null, "patrol_start")).contains("no creature script")
