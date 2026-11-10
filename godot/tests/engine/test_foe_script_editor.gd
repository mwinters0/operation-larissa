class_name TestFoeScriptEditor
extends GdUnitTestSuite
## Teaches: testing editor tooling without the editor. The highlighter works on a String, and
## the panel is an ordinary Control that can be added to a test's own tree. Files go to user://
## so the test never touches the project. What needs the real editor (the tab, the double
## click, Ctrl+S reaching the panel) is checked by hand in the editor.

const TEMP_A := "user://test_foe_editor_a.foe"
const TEMP_B := "user://test_foe_editor_b.foe"
const GOOD := "start:\n    Move_Foe_Relative_XY 2 0 1   ; step\n    Jump_To start\n"

var _panel: FoeEditorPanel


func before_test() -> void:
	_panel = FoeEditorPanel.new()
	add_child(_panel)


func after_test() -> void:
	_panel.free()
	DirAccess.remove_absolute(TEMP_A)
	DirAccess.remove_absolute(TEMP_B)


## Writes `text` to `path` and returns the FoeScript the loader gives back for it.
func _file(path: String, text: String) -> FoeScript:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as FoeScript


func _color_at(colors: Dictionary, column: int) -> Color:
	var best := 0
	for key in colors:
		if key <= column and key >= best:
			best = key
	return colors[best]["color"]


# --- highlighter -------------------------------------------------------------

func test_highlighter_colours_each_part_of_an_instruction_line() -> void:
	var hl := FoeSyntaxHighlighter.new()
	var line := "    Jump_To again 12 ; loop"
	var colors := hl.highlight_text(line)
	assert_that(_color_at(colors, line.find("Jump_To"))).is_equal(hl.mnemonic_color)
	assert_that(_color_at(colors, line.find("again"))).is_equal(hl.label_color)
	assert_that(_color_at(colors, line.find("12"))).is_equal(hl.number_color)
	assert_that(_color_at(colors, line.find(";"))).is_equal(hl.comment_color)
	assert_that(_color_at(colors, line.find("loop"))).is_equal(hl.comment_color)
	assert_that(_color_at(colors, 0)).is_equal(hl.text_color)


func test_highlighter_knows_labels_self_and_mistakes() -> void:
	var hl := FoeSyntaxHighlighter.new()
	assert_that(_color_at(hl.highlight_text("again:"), 2)).is_equal(hl.label_color)
	assert_that(_color_at(hl.highlight_text("    wake_foe self+2"), 4)).is_equal(hl.mnemonic_color)    # any case
	assert_that(_color_at(hl.highlight_text("    Wake_Foe self+2"), 13)).is_equal(hl.self_color)
	assert_that(_color_at(hl.highlight_text("    Wake_Foe -3"), 13)).is_equal(hl.number_color)
	assert_that(_color_at(hl.highlight_text("    Jmp again"), 4)).is_equal(hl.error_color)
	# Padding is coloured like an instruction (it is written like one), its count like a number
	assert_that(_color_at(hl.highlight_text("    Padding 9"), 4)).is_equal(hl.mnemonic_color)
	assert_that(_color_at(hl.highlight_text("    padding 9"), 4)).is_equal(hl.mnemonic_color)
	assert_that(_color_at(hl.highlight_text("    Padding 9"), 12)).is_equal(hl.number_color)
	assert_that(_color_at(hl.highlight_text("    Paddin 9"), 4)).is_equal(hl.error_color)
	assert_that(_color_at(hl.highlight_text("; only a comment"), 0)).is_equal(hl.comment_color)
	assert_that(_color_at(hl.highlight_text(""), 0)).is_equal(hl.text_color)


func test_every_mnemonic_is_coloured_as_an_instruction() -> void:
	var hl := FoeSyntaxHighlighter.new()
	for name in FoeOps.MNEMONIC:
		assert_that(_color_at(hl.highlight_text(name), 0)).override_failure_message(name).is_equal(hl.mnemonic_color)


func test_code_edit_asks_the_highlighter_line_by_line() -> void:
	var edit := CodeEdit.new()
	add_child(edit)
	var hl := FoeSyntaxHighlighter.new()
	edit.syntax_highlighter = hl
	edit.text = "start:\n    Return\n"
	assert_that(_color_at(hl.get_line_syntax_highlighting(0), 0)).is_equal(hl.label_color)
	assert_that(_color_at(hl.get_line_syntax_highlighting(1), 4)).is_equal(hl.mnemonic_color)
	edit.free()


# --- panel: load, edit, save -------------------------------------------------

func test_opening_a_file_shows_its_text_and_is_clean() -> void:
	var doc := _panel.open_script(_file(TEMP_A, GOOD))
	assert_object(doc).is_not_null()
	assert_str(doc.edit.text).is_equal(GOOD)
	assert_bool(doc.is_dirty()).is_false()
	assert_bool(doc.edit.gutters_draw_line_numbers).is_true()
	assert_bool(_panel.has_unsaved()).is_false()
	assert_int(_panel.document_count()).is_equal(1)
	_panel.open_script(doc.resource)                      # again: no second tab
	assert_int(_panel.document_count()).is_equal(1)


func test_a_script_without_a_file_is_refused() -> void:
	assert_object(_panel.open_script(FoeScript.new())).is_null()
	assert_object(_panel.open_script(null)).is_null()


func test_edit_save_round_trip_is_byte_exact() -> void:
	var doc := _panel.open_script(_file(TEMP_A, GOOD))
	var edited := "start:\n    Hide_Foe\n    Jump_To start\n; caf\u00e9 \u2192 no final newline"
	doc.edit.text = edited
	doc.edit.text_changed.emit()
	assert_bool(doc.is_dirty()).is_true()
	assert_array(_panel.unsaved_paths()).contains_exactly([TEMP_A])
	assert_str(FileAccess.get_file_as_string(TEMP_A)).is_equal(GOOD)      # nothing written yet
	assert_int(_panel.save_document(doc)).is_equal(OK)
	assert_bool(FileAccess.get_file_as_bytes(TEMP_A) == edited.to_utf8_buffer()).is_true()
	assert_bool(doc.is_dirty()).is_false()
	assert_str(doc.resource.source).is_equal(edited)
	var loaded := ResourceLoader.load(TEMP_A, "", ResourceLoader.CACHE_MODE_IGNORE) as FoeScript
	assert_str(loaded.source).is_equal(edited)


func test_ctrl_s_in_the_editor_saves() -> void:
	var doc := _panel.open_script(_file(TEMP_A, GOOD))
	doc.edit.text = "start:\n    Return\n"
	var key := InputEventKey.new()
	key.keycode = KEY_S
	key.ctrl_pressed = true
	key.pressed = true
	doc.edit.gui_input.emit(key)
	assert_str(FileAccess.get_file_as_string(TEMP_A)).is_equal("start:\n    Return\n")


func test_save_all_writes_only_the_changed_files_and_apply_syncs_the_scripts() -> void:
	var a := _panel.open_script(_file(TEMP_A, GOOD))
	var b := _panel.open_script(_file(TEMP_B, GOOD))
	a.edit.text = "start:\n    Return\n"
	_panel.apply_to_scripts()
	assert_str(a.resource.source).is_equal("start:\n    Return\n")
	assert_str(FileAccess.get_file_as_string(TEMP_A)).is_equal(GOOD)
	assert_int(_panel.save_all()).is_equal(OK)
	assert_str(FileAccess.get_file_as_string(TEMP_A)).is_equal("start:\n    Return\n")
	assert_bool(b.is_dirty()).is_false()
	assert_bool(_panel.has_unsaved()).is_false()


func test_closing_drops_unsaved_edits_from_the_script_too() -> void:
	var doc := _panel.open_script(_file(TEMP_A, GOOD))
	var script := doc.resource
	doc.edit.text = "start:\n    Return\n"
	_panel.apply_to_scripts()
	_panel.close_document(doc)
	assert_int(_panel.document_count()).is_equal(0)
	assert_str(script.source).is_equal(GOOD)


func test_switching_files_keeps_each_buffer() -> void:
	var a := _panel.open_script(_file(TEMP_A, GOOD))
	var b := _panel.open_script(_file(TEMP_B, "x:\n    Return\n"))
	assert_object(_panel.current_document()).is_same(b)
	assert_bool(b.edit.visible).is_true()
	assert_bool(a.edit.visible).is_false()
	_panel.open_script(a.resource)
	assert_object(_panel.current_document()).is_same(a)
	assert_bool(a.edit.visible).is_true()
	assert_bool(b.edit.visible).is_false()


# --- panel: errors -----------------------------------------------------------

func test_a_bad_script_lists_its_errors_and_marks_the_lines() -> void:
	var doc := _panel.open_script(_file(TEMP_A, "start:\n    Fly_Away 1\n    Jump_To nowhere\n"))
	assert_array(doc.errors).has_size(2)
	assert_str(doc.errors[0]).starts_with("line 2:")
	assert_str(doc.errors[1]).starts_with("line 3:")
	assert_array(doc.error_lines).contains_exactly([1, 2])
	assert_that(doc.edit.get_line_background_color(1)).is_equal(FoeEditorPanel.ERROR_LINE_COLOR)
	assert_that(doc.edit.get_line_background_color(0)).is_equal(FoeEditorPanel.NO_COLOR)


func test_fixing_the_text_clears_the_errors() -> void:
	var doc := _panel.open_script(_file(TEMP_A, "start:\n    Fly_Away 1\n"))
	assert_array(doc.errors).has_size(1)
	doc.edit.text = GOOD
	_panel.check(doc)
	assert_array(doc.errors).is_empty()
	assert_array(doc.error_lines).is_empty()
	assert_that(doc.edit.get_line_background_color(1)).is_equal(FoeEditorPanel.NO_COLOR)


func test_go_to_problem_moves_the_caret_to_the_line() -> void:
	var doc := _panel.open_script(_file(TEMP_A, "start:\n    Return\n    Fly_Away 1\n"))
	_panel.go_to_problem(0)
	assert_int(doc.edit.get_caret_line()).is_equal(2)
	_panel.go_to_problem(5)                          # no such problem: nothing happens
	assert_int(doc.edit.get_caret_line()).is_equal(2)


# --- panel: files changing on disk ------------------------------------------

func test_a_clean_buffer_follows_the_file_on_disk() -> void:
	var doc := _panel.open_script(_file(TEMP_A, GOOD))
	_file(TEMP_A, "start:\n    Return\n")             # another program saves
	_panel.check_disk_changes()
	assert_str(doc.edit.text).is_equal("start:\n    Return\n")
	assert_str(doc.resource.source).is_equal("start:\n    Return\n")
	assert_bool(doc.conflict).is_false()


func test_unsaved_edits_survive_a_change_on_disk_and_are_flagged() -> void:
	var doc := _panel.open_script(_file(TEMP_A, GOOD))
	doc.edit.text = "mine:\n    Return\n"
	_file(TEMP_A, "theirs:\n    Return\n")
	_panel.check_disk_changes()
	assert_str(doc.edit.text).is_equal("mine:\n    Return\n")
	assert_bool(doc.conflict).is_true()
	_panel.reload_document(doc)
	assert_str(doc.edit.text).is_equal("theirs:\n    Return\n")
	assert_bool(doc.conflict).is_false()
	assert_bool(doc.is_dirty()).is_false()


# --- a real sector -----------------------------------------------------------

func test_a_sector_file_opens_clean_and_assembles() -> void:
	var path := Catalog.foe_path(DevCreatures.ARENA)
	var doc := _panel.open_script(load(path) as FoeScript)
	assert_bool(doc.edit.text == FileAccess.get_file_as_string(path)).is_true()
	assert_bool(doc.is_dirty()).is_false()
	assert_array(doc.errors).is_empty()
	assert_int(doc.size).is_greater(0)


func test_a_crlf_file_opens_clean_and_is_saved_with_lf() -> void:
	var doc := _panel.open_script(_file(TEMP_A, "start:\r\n    Return\r\n"))
	assert_str(doc.edit.text).is_equal("start:\n    Return\n")      # CodeEdit keeps only "\n"
	assert_bool(doc.is_dirty()).is_false()
	_panel.check_disk_changes()                                     # no phantom change either
	assert_bool(doc.conflict).is_false()
	doc.edit.text = "start:\n    Return\n    Return\n"
	assert_int(_panel.save_document(doc)).is_equal(OK)
	assert_str(FileAccess.get_file_as_string(TEMP_A)).is_equal("start:\n    Return\n    Return\n")


# --- names and comments: rename a label, store them -----------------------------------------

const TEMP_DIR := "user://foe_names_test"
const WALK := "start:\n    Move_Foe_Relative_XY 2 0 1  ; step\nagain:\n    Wait_Next_Tick\n    Jump_To again ; again2\n    Jump_To start\n"


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## A scratch copy of sector `index` (its .foe and .tres) in user://, named like sector `as_index`.
func _sector_copy(index: int, as_index: int) -> FoeScript:
	DirAccess.make_dir_recursive_absolute(Catalog.sector_dir(as_index, TEMP_DIR))
	_write(Catalog.sector_path(as_index, TEMP_DIR), FileAccess.get_file_as_string(Catalog.sector_path(index)))
	_write(Catalog.foe_path(as_index, TEMP_DIR), FileAccess.get_file_as_string(Catalog.foe_path(index)))
	return ResourceLoader.load(Catalog.foe_path(as_index, TEMP_DIR), "", ResourceLoader.CACHE_MODE_REPLACE) as FoeScript


func _clear_temp_dir() -> void:
	for folder in DirAccess.get_directories_at(TEMP_DIR):
		for file_name in DirAccess.get_files_at(TEMP_DIR + "/" + folder):
			DirAccess.remove_absolute(TEMP_DIR + "/" + folder + "/" + file_name)
		DirAccess.remove_absolute(TEMP_DIR + "/" + folder)
	for file_name in DirAccess.get_files_at(TEMP_DIR):
		DirAccess.remove_absolute(TEMP_DIR + "/" + file_name)
	DirAccess.remove_absolute(TEMP_DIR)


func test_dead_code_is_a_warning_in_the_problems_area_not_an_error() -> void:
	# the arena's text and entry labels, as a sector number of its own (the .tres beside the .foe names the entry labels)
	var doc := _panel.open_script(_sector_copy(DevCreatures.ARENA, 41))
	assert_array(doc.warnings).is_empty()
	assert_array(doc.errors).is_empty()
	# instructions after the last jump that nothing reaches: a warning, and the generated comment says it is meant
	var meant := doc.edit.text + "%s\n    Show_Foe\n    Hide_Foe\n" % FoeAsm.UNEXECUTED_UNUSED
	doc.edit.text = meant
	_panel.check(doc)
	assert_array(doc.warnings).is_empty()
	var bare := doc.edit.text.replace(FoeAsm.UNEXECUTED_UNUSED + "\n", "")
	doc.edit.text = bare
	_panel.check(doc)
	assert_array(doc.errors).is_empty()                                    # still assembles: nothing blocks saving
	assert_array(doc.warnings).is_not_empty()
	assert_str(doc.warnings[0]).starts_with("line ").contains("never executed")
	assert_array(doc.error_lines).is_empty()                               # no red line tint, a yellow one
	var warned := int(doc.warnings[0].get_slice(":", 0).trim_prefix("line ")) - 1
	assert_that(doc.edit.get_line_background_color(warned)).is_equal(FoeEditorPanel.WARNING_LINE_COLOR)
	doc.edit.text = doc.edit.text                                          # unchanged text: still warned
	_panel.check(doc)
	assert_int(doc.warning_lines.size()).is_equal(doc.warnings.size())     # every warned run is tinted
	assert_bool(doc.warning_lines.has(warned)).is_true()
	# clicking the warning goes to its line
	_panel.go_to_problem(0)
	assert_int(doc.edit.get_caret_line() + 1).is_equal(int(doc.warnings[0].get_slice(":", 0).trim_prefix("line ")))
	_clear_temp_dir()


func test_a_reached_padding_is_a_warning_and_padding_nobody_reaches_is_not() -> void:
	var doc := _panel.open_script(_sector_copy(DevCreatures.ARENA, 42))
	var plain := "quiet_hit:\n    Return\n"
	assert_str(doc.edit.text).contains(plain)
	var label_line := doc.edit.text.split("\n").find("quiet_hit:") + 1            # (1-based, as the problems say)
	doc.edit.text = doc.edit.text.replace(plain, plain + "    Padding 9\n")
	_panel.check(doc)
	assert_array(doc.warnings).is_empty()                                  # Padding after a Return: nobody reaches it
	doc.edit.text = doc.edit.text.replace(plain + "    Padding 9\n", "quiet_hit:\n    Padding 9\n    Return\n")
	_panel.check(doc)
	assert_array(doc.errors).is_empty()
	assert_array(doc.warnings).has_size(1)
	assert_str(doc.warnings[0]).starts_with("line %d: Padding is reached and would run as Wait_Next_Tick (9 ticks of doing nothing)" % (label_line + 1))
	assert_array(doc.warning_lines).contains_exactly([label_line])
	assert_that(doc.edit.get_line_background_color(label_line)).is_equal(FoeEditorPanel.WARNING_LINE_COLOR)
	# dead Wait_Next_Tick lines get the hint to write Padding
	doc.edit.text = doc.edit.text.replace("quiet_hit:\n    Padding 9\n    Return\n", plain + "    Wait_Next_Tick\n    Wait_Next_Tick\n")
	_panel.check(doc)
	assert_array(doc.warnings).has_size(1)
	assert_str(doc.warnings[0]).is_equal("line %d: never executed (no creature start/hit/ink entry or jump reaches it); if it is only filler, write Padding 2 instead" % (label_line + 2))
	_clear_temp_dir()


func test_a_text_without_a_sector_gets_no_dead_code_warnings() -> void:
	var doc := _panel.open_script(_file(TEMP_A, "start:\n    Jump_To start\n    Hide_Foe\n"))
	assert_array(doc.errors).is_empty()
	assert_array(doc.warnings).is_empty()


func test_label_at_finds_definitions_and_uses_under_the_caret() -> void:
	assert_str(FoeLineInfo.label_at("again:", 2)).is_equal("again")
	assert_str(FoeLineInfo.label_at("again:", 5)).is_equal("again")
	assert_str(FoeLineInfo.label_at("    Jump_To again ; x", 14)).is_equal("again")
	assert_str(FoeLineInfo.label_at("    Jump_To again ; x", 6)).is_equal("")           # on the instruction name
	assert_str(FoeLineInfo.label_at("    Loop_Counter0_Back_To again 4", 33)).is_equal("")   # on the count
	assert_str(FoeLineInfo.label_at("    Jump_To again ; again", 22)).is_equal("")       # in the comment
	assert_str(FoeLineInfo.label_at("    Set_Frame 3", 13)).is_equal("")


func test_rename_label_changes_whole_words_outside_comments_only() -> void:
	var lines := "start:\n    Jump_To start ; start again\nstart2:\n    Loop_Counter1_Back_To start 3\n".split("\n")
	var renamed := FoeLineInfo.rename_label(lines, "start", "begin")
	assert_array(renamed).contains_exactly(["begin:", "    Jump_To begin ; start again", "start2:", "    Loop_Counter1_Back_To begin 3", ""])


func test_the_rename_checks_the_new_name() -> void:
	var doc := _panel.open_script(_file(TEMP_A, WALK))
	assert_str(_panel.rename_problem(doc, "again", "2bad")).is_not_empty()
	assert_str(_panel.rename_problem(doc, "again", "has space")).is_not_empty()
	assert_str(_panel.rename_problem(doc, "again", "start")).contains("already")
	assert_str(_panel.rename_problem(doc, "again", "again")).is_not_empty()
	assert_str(_panel.rename_problem(doc, "missing", "fine")).contains("not a label")
	assert_str(_panel.rename_problem(doc, "again", "loop_a")).is_empty()


func test_renaming_a_label_changes_the_buffer_in_one_undoable_step() -> void:
	var doc := _panel.open_script(_file(TEMP_A, WALK))
	assert_str(_panel.rename_label(doc, "again", "loop_a")).is_empty()
	assert_str(doc.edit.text).is_equal(WALK.replace("again:", "loop_a:").replace("Jump_To again", "Jump_To loop_a"))
	assert_bool(doc.is_dirty()).is_true()
	assert_str(FileAccess.get_file_as_string(TEMP_A)).is_equal(WALK)         # a plain label only changes the buffer
	doc.edit.undo()
	assert_str(doc.edit.text).is_equal(WALK)
	assert_str(_panel.rename_label(doc, "again", "start")).is_not_empty()      # refused: nothing changed
	assert_str(doc.edit.text).is_equal(WALK)


func test_renaming_an_entry_label_changes_the_tres_and_saves_both_files() -> void:
	var script := _sector_copy(DevCreatures.ARENA, DevCreatures.ARENA)
	var doc := _panel.open_script(script)
	var tres_before := FileAccess.get_file_as_string(Catalog.sector_path(DevCreatures.ARENA, TEMP_DIR))
	assert_str(_panel.rename_label(doc, "quiet_hit", "touch_return")).is_empty()
	assert_bool(doc.is_dirty()).is_false()                                    # saved together with the .tres
	assert_str(FileAccess.get_file_as_string(Catalog.foe_path(DevCreatures.ARENA, TEMP_DIR))).contains("touch_return:").not_contains("quiet_hit")
	var tres := FileAccess.get_file_as_string(Catalog.sector_path(DevCreatures.ARENA, TEMP_DIR))
	assert_str(tres).contains('hit_label = "touch_return"').not_contains('hit_label = "quiet_hit"')
	assert_bool(tres.replace("touch_return", "quiet_hit") == tres_before).is_true()      # nothing else changed
	assert_bool(_panel.current_document().notes.is_empty()).is_false()
	_clear_temp_dir()


func test_a_jump_target_label_rename_leaves_the_tres_alone() -> void:
	var doc := _panel.open_script(_sector_copy(DevCreatures.ARENA, DevCreatures.ARENA))
	var tres_before := FileAccess.get_file_as_string(Catalog.sector_path(DevCreatures.ARENA, TEMP_DIR))
	assert_str(_panel.rename_label(doc, "swim_right", "paddle_right")).is_empty()
	assert_bool(doc.is_dirty()).is_true()
	assert_str(FileAccess.get_file_as_string(Catalog.sector_path(DevCreatures.ARENA, TEMP_DIR))).is_equal(tres_before)
	_clear_temp_dir()


func test_a_sector_without_an_original_is_never_stored_but_renames_like_any_other() -> void:
	# sector_40: a scratch sector of the designers, in user://, not in the project
	var doc := _panel.open_script(_sector_copy(DevCreatures.ARENA, 40))
	assert_str(_panel.store_problem(doc)).contains("not one of the original sectors")
	assert_bool(_panel.store_annotations(doc)).is_false()
	assert_bool(FileAccess.file_exists(TEMP_DIR + "/foe_annotations.json")).is_false()
	assert_bool(FoeAnnotations.has_original(40)).is_false()
	assert_str(_panel.rename_label(doc, "quiet_hit", "touch_return")).is_empty()      # rename works the same
	assert_str(FileAccess.get_file_as_string(Catalog.sector_path(40, TEMP_DIR))).contains('hit_label = "touch_return"')
	_clear_temp_dir()
