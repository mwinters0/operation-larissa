class_name TestScreenEditorMarkers
extends GdUnitTestSuite
## Teaches: testing the screen editor's add and remove of creatures and pieces without the editor. The claims: duplicating, deleting
## and adding a marker changes the SECTOR through its own API (`SectorData.add_foe` / `remove_foe` / `add_piece` / `remove_piece`)
## and the sector's `changed` puts the markers right; a change the sector refuses (a creature a script names, the 12th piece, the
## data canister) leaves sector AND scene as they were and says why; undo and redo keep the two in step; and the saved files are
## the original's again after an add and a remove. The Scene dock's steps are played by hand on a plain `UndoRedo` (the names it gives
## them are the dock's: "Duplicate Node(s)", "Remove Node(s)"), because there is no dock here. What this can not show: that the real
## `EditorUndoRedoManager` accepts the calls (the code is the same, only the call syntax differs, see `SectorEdits._commit`).
## Everything is done on COPIES of the data under user://, never the committed files.

const SECTORS := DevPack.SECTORS_DIR
const TEMP := "user://screen_editor_markers_test"

var _dirs: Array[String] = []
var _history: UndoRedo


func before_test() -> void:
	_history = UndoRedo.new()


func after_test() -> void:
	_history = null
	for dir in _dirs:
		if DirAccess.dir_exists_absolute(dir):
			for s in Ground.clean_sectors():
				for m in Catalog.SCREENS_PER_SECTOR:
					DirAccess.remove_absolute(ScreenFile.screen_path(dir, s, m))
				DirAccess.remove_absolute(Catalog.sector_path(s, dir))
				DirAccess.remove_absolute(Catalog.sector_dir(s, dir))
			DirAccess.remove_absolute(dir)
	_dirs.clear()


## A copy of sector `s` (and its 12 screens) in a folder of its own; the folder is removed after the test.
func _temp_copy(s: int) -> String:
	var dir := "%s_%d" % [TEMP, Time.get_ticks_usec()]
	_dirs.append(dir)
	DirAccess.make_dir_recursive_absolute(Catalog.sector_dir(s, dir))
	DirAccess.copy_absolute(Catalog.sector_path(s, SECTORS), Catalog.sector_path(s, dir))
	for m in Catalog.SCREENS_PER_SECTOR:
		DirAccess.copy_absolute(ScreenFile.screen_path(SECTORS, s, m), ScreenFile.screen_path(dir, s, m))
	return dir


func _editor(dir: String, sector: int, screen: int, shared := false) -> ScreenEditor:
	var editor := auto_free(ScreenEditor.new()) as ScreenEditor
	editor.data_dir = dir
	editor.sector = sector
	editor.screen = screen
	editor.share_sector = shared
	editor.history = _history
	add_child(editor)
	return editor


func _markers(editor: ScreenEditor, layer: String) -> Array[Node]:
	var found: Array[Node] = []
	for child in editor.get_node(layer).get_children():
		found.append(child)
	return found


func _foe_marker(editor: ScreenEditor, index: int) -> ScreenEditorFoe:
	for child in _markers(editor, "Foes"):
		if (child as ScreenEditorFoe).foe_index == index:
			return child
	return null


func _piece_marker(editor: ScreenEditor, index: int) -> ScreenEditorPiece:
	for child in _markers(editor, "Pieces"):
		if (child as ScreenEditorPiece).piece_index == index:
			return child
	return null


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## The text of the sector file and its twelve screens, to compare after a round trip.
func _files(dir: String, s: int) -> Array[String]:
	var found: Array[String] = [_text(Catalog.sector_path(s, dir))]
	for m in Catalog.SCREENS_PER_SECTOR:
		found.append(_text(ScreenFile.screen_path(dir, s, m)))
	return found


## What the Scene dock does when a marker is duplicated: one step on the history, the undo of which takes the node out again.
func _dock_duplicate(editor: ScreenEditor, marker: Node) -> Node:
	var copy := marker.duplicate()
	var layer := marker.get_parent()
	_history.create_action("Duplicate Node(s)")
	_history.add_do_method(layer.add_child.bind(copy, true))
	_history.add_do_reference(copy)
	_history.add_undo_method(layer.remove_child.bind(copy))
	_history.commit_action()
	editor.sync_with_markers()                                  # the editor does this by itself, a frame later
	return copy


## What the Scene dock does for Delete: the node leaves, the undo puts it back where it was.
func _dock_remove(editor: ScreenEditor, marker: Node) -> void:
	var layer := marker.get_parent()
	var at := marker.get_index()
	_history.create_action("Remove Node(s)")
	_history.add_do_method(layer.remove_child.bind(marker))
	_history.add_undo_method(layer.add_child.bind(marker, true))
	_history.add_undo_method(layer.move_child.bind(marker, at))
	_history.add_undo_reference(marker)
	_history.commit_action()
	editor.sync_with_markers()


## The first creature of sector `s` that is not the last one on its screen, the screen, and a later creature of that screen.
func _screen_with_two_foes(s: int) -> Array[int]:
	var sector := Catalog.sector(s)
	for i in sector.foes.size():
		for j in range(i + 1, sector.foes.size()):
			if sector.foes[i].screen == sector.foes[j].screen:
				return [sector.foes[i].screen, i, j]
	return []


# --- creatures: duplicate, delete, undo, redo ----------------------------------------------------------------------------------

func test_duplicating_a_creature_marker_adds_a_copy_of_the_creature_to_the_sector() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var found := _screen_with_two_foes(Ground.MAIN)
	var editor := _editor(dir, Ground.MAIN, found[0])
	var sector := editor.sector_data()
	var count := sector.foes.size()
	var base := sector.foe_script_base
	var original := _foe_marker(editor, found[1])
	var copy := _dock_duplicate(editor, original) as ScreenEditorFoe
	assert_int(sector.foes.size()).is_equal(count + 1)
	assert_int(sector.foe_script_base).is_equal(base + FoeData.RECORD_SIZE)
	assert_int(copy.foe_index).is_equal(count)
	assert_str(String(copy.name)).is_equal("Foe %d" % count)
	assert_object(copy.record).is_same(sector.foes[count])
	assert_int(sector.foes[count].frame).is_equal(sector.foes[found[1]].frame)
	assert_str(sector.foes[count].start_label).is_equal(sector.foes[found[1]].start_label)
	assert_int(sector.foes[count].screen).is_equal(found[0])
	assert_array(editor.build().problems).is_empty()
	assert_bool(editor.is_dirty()).is_true()
	assert_array(editor.refusal).is_empty()
	# a second sync changes nothing
	editor.sync_with_markers()
	assert_int(sector.foes.size()).is_equal(count + 1)


func test_undo_and_redo_of_a_duplicated_creature_keep_the_markers_and_the_sector_in_step() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var found := _screen_with_two_foes(Ground.MAIN)
	var editor := _editor(dir, Ground.MAIN, found[0])
	var sector := editor.sector_data()
	var count := sector.foes.size()
	var copy := _dock_duplicate(editor, _foe_marker(editor, found[1])) as ScreenEditorFoe
	copy.position += Vector2(8, 0)                               # an edit on the marker, not yet in the sector
	var record := copy.record
	assert_bool(_history.undo()).is_true()
	editor.sync_with_markers()
	assert_int(sector.foes.size()).is_equal(count)
	assert_array(editor.build().problems).is_empty()
	assert_bool(editor.is_dirty()).is_false()
	assert_bool(_history.redo()).is_true()
	editor.sync_with_markers()
	assert_int(sector.foes.size()).is_equal(count + 1)
	assert_object(sector.foes[count]).is_same(record)           # the very same creature and node come back
	assert_object(_foe_marker(editor, count)).is_same(copy)
	assert_vector(copy.position).is_equal(Vector2(record.pos) + Vector2(8, 0))
	assert_array(editor.build().problems).is_empty()


func test_deleting_the_last_creature_marker_removes_the_creature_and_undo_brings_it_back() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var sector_index := Ground.MAIN
	var count := Catalog.sector(sector_index).foes.size()
	var screen: int = Catalog.sector(sector_index).foes[count - 1].screen
	var editor := _editor(dir, sector_index, screen)
	var sector := editor.sector_data()
	var marker := _foe_marker(editor, count - 1)
	var record := marker.record
	marker.position += Vector2(6, 0)
	_dock_remove(editor, marker)
	assert_int(sector.foes.size()).is_equal(count - 1)
	assert_int(sector.foe_script_base).is_equal(1 + FoeData.RECORD_SIZE * (count - 1))
	assert_array(editor.build().problems).is_empty()
	assert_array(editor.refusal).is_empty()
	assert_bool(_history.undo()).is_true()
	editor.sync_with_markers()
	assert_int(sector.foes.size()).is_equal(count)
	assert_object(sector.foes[count - 1]).is_same(record)
	assert_object(_foe_marker(editor, count - 1)).is_same(marker)
	assert_vector(marker.position).is_equal(Vector2(record.pos) + Vector2(6, 0))   # the unsaved move is still there
	assert_array(editor.build().problems).is_empty()


func test_deleting_a_creature_in_the_middle_renumbers_the_markers_after_it() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var found := _screen_with_two_foes(Ground.MAIN)
	var first: int = found[1]
	var later: int = found[2]
	var editor := _editor(dir, Ground.MAIN, found[0])
	var sector := editor.sector_data()
	var count := sector.foes.size()
	var last_marker := _foe_marker(editor, later)
	_dock_remove(editor, _foe_marker(editor, first))
	assert_int(sector.foes.size()).is_equal(count - 1)
	assert_int(last_marker.foe_index).is_equal(later - 1)
	assert_str(String(last_marker.name)).is_equal("Foe %d" % (later - 1))
	assert_object(last_marker.record).is_same(sector.foes[later - 1])
	assert_array(editor.build().problems).is_empty()
	# undo puts the creature back at its number, and the others move up again
	assert_bool(_history.undo()).is_true()
	editor.sync_with_markers()
	assert_int(sector.foes.size()).is_equal(count)
	assert_int(last_marker.foe_index).is_equal(later)
	assert_str(String(last_marker.name)).is_equal("Foe %d" % later)
	assert_int(_foe_marker(editor, first).foe_index).is_equal(first)
	assert_array(editor.build().problems).is_empty()


func test_a_creature_the_script_names_is_not_removed_and_the_marker_comes_back() -> void:
	var dir := _temp_copy(Ground.EDIT)
	var sector_index := Ground.EDIT
	var tank := FoeNames.for_sector(Catalog.sector(sector_index)).index_for(FoeOps.Kind.FOE, "foe_3")
	var screen: int = Catalog.sector(sector_index).foes[tank].screen
	var editor := _editor(dir, sector_index, screen)
	var sector := editor.sector_data()
	var count := sector.foes.size()
	var marker := _foe_marker(editor, tank)
	var parent := marker.get_parent()
	_dock_remove(editor, marker)
	assert_int(sector.foes.size()).is_equal(count)               # nothing changed in the sector ...
	assert_object(marker.get_parent()).is_same(parent)           # ... the same marker is back in its layer ...
	assert_object(_foe_marker(editor, tank)).is_same(marker)
	assert_str(" ".join(editor.refusal)).contains("line").contains("names creature %d" % tank)    # ... and we are told why
	assert_array(editor.build().problems).is_empty()
	assert_bool(editor.is_dirty()).is_false()
	# the dock's step was taken back, not left behind: its redo is there, and the history has no step for the refusal
	assert_bool(_history.has_redo()).is_true()
	assert_bool(_history.has_undo()).is_false()


func test_a_refused_deletion_without_a_history_puts_the_nodes_right_by_hand() -> void:
	var dir := _temp_copy(Ground.EDIT)
	var tank := FoeNames.for_sector(Catalog.sector(Ground.EDIT)).index_for(FoeOps.Kind.FOE, "foe_3")
	var editor := _editor(dir, Ground.EDIT, Catalog.sector(Ground.EDIT).foes[tank].screen)
	editor.history = null
	var marker := _foe_marker(editor, tank)
	var layer := marker.get_parent()
	layer.remove_child(marker)
	editor.sync_with_markers()
	assert_object(marker.get_parent()).is_same(layer)
	assert_object(_foe_marker(editor, tank)).is_same(marker)
	assert_int(editor.sector_data().foes.size()).is_equal(Catalog.sector(Ground.EDIT).foes.size())
	assert_str(" ".join(editor.refusal)).contains("names creature")
	assert_array(editor.build().problems).is_empty()


func test_a_creature_can_be_added_with_a_history_and_undone() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var found := _screen_with_two_foes(Ground.MAIN)
	var editor := _editor(dir, Ground.MAIN, found[0])
	var sector := editor.sector_data()
	var count := sector.foes.size()
	assert_bool(editor.add_creature(Vector2i(100, 100), found[1])).is_true()
	assert_int(sector.foes.size()).is_equal(count + 1)
	var marker := _foe_marker(editor, count)
	assert_object(marker).is_not_null()
	assert_vector(marker.pixel_position()).is_equal(Vector2i(100, 100))
	assert_int(marker.start_frame).is_equal(sector.foes[found[1]].frame)
	assert_bool(_history.undo()).is_true()
	assert_int(sector.foes.size()).is_equal(count)
	assert_object(_foe_marker(editor, count)).is_null()
	assert_bool(_history.redo()).is_true()
	assert_int(sector.foes.size()).is_equal(count + 1)
	assert_object(_foe_marker(editor, count)).is_same(marker)   # the parked node is reused, with its edits
	assert_array(editor.build().problems).is_empty()


func test_adding_a_creature_beyond_the_limit_is_refused_with_the_reason() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var editor := _editor(dir, Ground.MAIN, 0)
	var sector := editor.sector_data()
	while sector.foes.size() < SectorData.MAX_FOES:
		assert_array(sector.add_foe(0, Vector2i(64, 64))).is_empty()
	assert_bool(editor.add_creature()).is_false()
	assert_str(" ".join(editor.refusal)).contains("255")
	assert_bool(_history.has_undo()).is_false()


# --- pieces ------------------------------------------------------------------------------------------------------------------------

func test_duplicating_a_piece_marker_adds_a_piece_and_deleting_it_removes_it_again() -> void:
	var dir := _temp_copy(Ground.EDIT)
	var sector_index := Ground.EDIT
	var screen: int = Catalog.sector(sector_index).pieces[1].screen
	var editor := _editor(dir, sector_index, screen)
	var sector := editor.sector_data()
	var count := sector.pieces.size()
	var copy := _dock_duplicate(editor, _piece_marker(editor, 1)) as ScreenEditorPiece
	assert_int(sector.pieces.size()).is_equal(count + 1)
	assert_int(copy.piece_index).is_equal(count)
	assert_str(String(copy.name)).is_equal("Piece %d" % count)
	assert_bool(copy.is_canister).is_false()
	assert_object(copy.record).is_same(sector.pieces[count])
	assert_array(editor.build().problems).is_empty()
	_dock_remove(editor, copy)
	assert_int(sector.pieces.size()).is_equal(count)
	assert_array(editor.build().problems).is_empty()
	assert_bool(_history.undo()).is_true()                       # the removal
	editor.sync_with_markers()
	assert_int(sector.pieces.size()).is_equal(count + 1)
	assert_object(_piece_marker(editor, count)).is_same(copy)
	assert_bool(_history.undo()).is_true()                       # the duplication
	editor.sync_with_markers()
	assert_int(sector.pieces.size()).is_equal(count)
	assert_bool(editor.is_dirty()).is_false()
	copy.free()                                                  # the history let go of it


func test_the_data_canister_marker_stays_while_other_pieces_are_left() -> void:
	var dir := _temp_copy(Ground.EDIT)
	var editor := _editor(dir, Ground.EDIT, Catalog.sector(Ground.EDIT).pieces[0].screen)
	var sector := editor.sector_data()
	var count := sector.pieces.size()
	var canister := _piece_marker(editor, 0)
	assert_bool(canister.is_canister).is_true()
	_dock_remove(editor, canister)
	assert_int(sector.pieces.size()).is_equal(count)
	assert_object(_piece_marker(editor, 0)).is_same(canister)
	assert_str(" ".join(editor.refusal)).contains("piece 0 is the data canister")
	assert_array(editor.build().problems).is_empty()


func test_a_twelfth_piece_is_refused_and_the_duplicate_goes_away_again() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var sector_index := Ground.MAIN
	assert_int(Catalog.sector(sector_index).pieces.size()).is_equal(SectorData.MAX_PIECES)
	var editor := _editor(dir, sector_index, Catalog.sector(sector_index).pieces[1].screen)
	var layer := editor.get_node("Pieces")
	var before := layer.get_child_count()
	var copy := _dock_duplicate(editor, _piece_marker(editor, 1))
	assert_int(editor.sector_data().pieces.size()).is_equal(SectorData.MAX_PIECES)
	assert_int(layer.get_child_count()).is_equal(before)
	assert_object(copy.get_parent()).is_null()
	assert_str(" ".join(editor.refusal)).contains("11 pieces")
	assert_array(editor.build().problems).is_empty()
	assert_bool(_history.has_undo()).is_false()                  # the dock's step was undone
	assert_bool(editor.add_piece()).is_false()
	assert_str(" ".join(editor.refusal)).contains("11 pieces")
	copy.free()


func test_a_piece_can_be_added_with_a_history_and_undone() -> void:
	var dir := _temp_copy(Ground.EDIT)
	var editor := _editor(dir, Ground.EDIT, 2)
	var sector := editor.sector_data()
	var count := sector.pieces.size()
	assert_bool(editor.add_piece(Vector2i(200, 150))).is_true()
	assert_int(sector.pieces.size()).is_equal(count + 1)
	assert_vector(_piece_marker(editor, count).pixel_position()).is_equal(Vector2i(200, 150))
	assert_bool(_history.undo()).is_true()
	assert_int(sector.pieces.size()).is_equal(count)
	assert_object(_piece_marker(editor, count)).is_null()
	assert_bool(_history.redo()).is_true()
	assert_object(_piece_marker(editor, count)).is_not_null()
	assert_array(editor.build().problems).is_empty()


# --- the Sector Inspector and the screen editor on one sector -------------------------------------------------------------------

func test_the_sector_inspector_and_the_screen_editor_share_the_sector_and_follow_each_other() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var found := _screen_with_two_foes(Ground.MAIN)
	var editor := _editor(dir, Ground.MAIN, found[0], true)
	var sector := editor.sector_data()
	assert_object(ResourceLoader.load(Catalog.sector_path(Ground.MAIN, dir))).is_same(sector)       # the object the Inspector shows
	var panel := auto_free(SectorPanel.new()) as SectorPanel
	panel.setup(sector, _history)
	add_child(panel)
	var count := sector.foes.size()
	# the screen editor adds: the panel's numbers change at once
	assert_bool(editor.add_creature(Vector2i(100, 100), found[1])).is_true()
	assert_str(panel._foes_section.title).contains(str(count + 1))
	# the panel removes it: the marker goes
	var edits := SectorEdits.new(sector, _history)
	assert_bool(edits.remove_foe(count)).is_true()
	assert_object(_foe_marker(editor, count)).is_null()
	assert_str(panel._foes_section.title).contains(str(count))
	# the panel adds one on this screen: the marker appears
	assert_bool(edits.add_foe(found[0], Vector2i(120, 100), found[1])).is_true()
	assert_object(_foe_marker(editor, count)).is_not_null()
	assert_array(editor.build().problems).is_empty()
	# undo steps of both are on one history and undo in order
	assert_bool(_history.undo()).is_true()
	assert_object(_foe_marker(editor, count)).is_null()
	assert_bool(_history.undo()).is_true()
	assert_int(sector.foes.size()).is_equal(count + 1)
	assert_object(_foe_marker(editor, count)).is_not_null()


func test_revert_reads_the_shared_sector_again() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var editor := _editor(dir, Ground.MAIN, 0, true)
	var sector := editor.sector_data()
	var count := sector.foes.size()
	assert_bool(editor.add_creature(Vector2i(100, 100))).is_true()
	assert_int(sector.foes.size()).is_equal(count + 1)
	editor.revert()
	assert_object(editor.sector_data()).is_same(sector)
	assert_int(sector.foes.size()).is_equal(count)
	assert_bool(editor.is_dirty()).is_false()
	assert_array(editor.build().problems).is_empty()


# --- the saved files -------------------------------------------------------------------------------------------------------------------

func test_an_unchanged_save_keeps_every_file_byte_identical() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var before := _files(dir, 5)
	var editor := _editor(dir, Ground.MAIN, 0)
	assert_bool(editor.save_screen()).is_true()
	assert_array(_files(dir, 5)).is_equal(before)


func test_adding_a_creature_and_saving_writes_it_and_removing_it_again_gives_the_files_back() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var before := _files(dir, 5)
	var found := _screen_with_two_foes(Ground.MAIN)
	var editor := _editor(dir, Ground.MAIN, found[0])
	var count := editor.sector_data().foes.size()
	var copy := _dock_duplicate(editor, _foe_marker(editor, found[1])) as ScreenEditorFoe
	copy.position += Vector2(10, 0)
	assert_bool(editor.save_screen()).is_true()
	assert_bool(editor.is_dirty()).is_false()
	var written := ResourceLoader.load(Catalog.sector_path(Ground.MAIN, dir), "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData
	assert_int(written.foes.size()).is_equal(count + 1)
	assert_vector(written.foes[count].pos).is_equal(written.foes[found[1]].pos + Vector2i(10, 0))
	assert_int(written.foe_script_base).is_equal(1 + FoeData.RECORD_SIZE * (count + 1))
	assert_array(Array(written.encode_foe_buffer().slice(0, 1))).is_equal([count + 1])
	assert_str(_text(Catalog.sector_path(Ground.MAIN, dir))).is_not_equal(before[0])
	# a second save of the same state writes nothing
	var saved := _files(dir, 5)
	assert_bool(editor.save_screen()).is_true()
	assert_array(_files(dir, 5)).is_equal(saved)
	# the new creature goes again; the files are the original's byte for byte
	_dock_remove(editor, copy)
	assert_bool(editor.is_dirty()).is_true()
	assert_bool(editor.save_screen()).is_true()
	assert_array(_files(dir, 5)).is_equal(before)
	copy.free()


func test_adding_a_piece_and_saving_writes_it_and_removing_it_again_gives_the_files_back() -> void:
	var dir := _temp_copy(Ground.EDIT)
	var before := _files(dir, 6)
	var screen: int = Catalog.sector(Ground.EDIT).pieces[1].screen
	var editor := _editor(dir, Ground.EDIT, screen)
	var count := editor.sector_data().pieces.size()
	var copy := _dock_duplicate(editor, _piece_marker(editor, 1)) as ScreenEditorPiece
	copy.position += Vector2(10, 4)
	assert_bool(editor.save_screen()).is_true()
	var written := ResourceLoader.load(Catalog.sector_path(Ground.EDIT, dir), "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData
	assert_int(written.pieces.size()).is_equal(count + 1)
	assert_vector(written.pieces[count].pos).is_equal(written.pieces[1].pos + Vector2i(10, 4))
	assert_array(written.header_problems()).is_empty()
	_dock_remove(editor, copy)
	assert_bool(editor.save_screen()).is_true()
	assert_array(_files(dir, 6)).is_equal(before)
	copy.free()


func test_a_save_with_marker_edits_and_a_count_change_together() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var found := _screen_with_two_foes(Ground.MAIN)
	var editor := _editor(dir, Ground.MAIN, found[0], true)
	var count := editor.sector_data().foes.size()
	var moved := _foe_marker(editor, found[1])
	var old_pos := moved.pixel_position()
	moved.position += Vector2(4, 0)
	assert_bool(editor.add_creature(Vector2i(100, 100), found[2])).is_true()
	assert_bool(editor.save_screen()).is_true()
	var written := ResourceLoader.load(Catalog.sector_path(Ground.MAIN, dir), "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData
	assert_int(written.foes.size()).is_equal(count + 1)
	assert_vector(written.foes[found[1]].pos).is_equal(old_pos + Vector2i(4, 0))
	assert_vector(written.foes[count].pos).is_equal(Vector2i(100, 100))
	assert_bool(editor.is_dirty()).is_false()
	# the history still works after the save: the creature goes, the markers follow, and the screen is dirty again
	assert_bool(_history.undo()).is_true()
	assert_object(_foe_marker(editor, count)).is_null()
	assert_int(editor.sector_data().foes.size()).is_equal(count)
	assert_bool(editor.is_dirty()).is_true()
	assert_bool(editor.save_screen()).is_true()
	var back := ResourceLoader.load(Catalog.sector_path(Ground.MAIN, dir), "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData
	assert_int(back.foes.size()).is_equal(count)
	assert_vector(back.foes[found[1]].pos).is_equal(old_pos + Vector2i(4, 0))


func test_the_status_says_that_the_sector_file_changes_when_a_creature_is_added() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var editor := _editor(dir, Ground.MAIN, 0)
	assert_str(editor.status).not_contains("also changes sector")
	assert_bool(editor.add_creature(Vector2i(100, 100))).is_true()
	editor.refresh()
	assert_str(editor.status).contains("also changes sector_%02d.tres" % Ground.MAIN)
