class_name TestSectorInspector
extends GdUnitTestSuite
## Teaches: testing an editor panel without the editor. The Sector Inspector is built in layers so that this is possible:
## `SectorEdits` (every change, with its undo) has no controls in it and runs on a plain `UndoRedo` here, where the editor uses
## its `EditorUndoRedoManager`; `SectorPanel` is plain controls that need no editor, so a test makes one, presses its buttons by
## emitting their signals (headless mode transports no input events) and reads the data. What is NOT tested here is the editor
## itself: that the Inspector shows the panel, that `EditorUndoRedoManager` accepts the calls, and that Ctrl+S saves (the
## `SectorDataSaver` half of it is tested in test_sector_editing.gd and test_screen_savers.gd).

const SECTORS := DevPack.SECTORS_DIR

var _history: UndoRedo


func before_test() -> void:
	_history = UndoRedo.new()


func after_test() -> void:
	_history = null


func _load(sector: int) -> SectorData:
	return ResourceLoader.load(Catalog.sector_path(sector, SECTORS), "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData


func _panel(sector: SectorData) -> SectorPanel:
	var panel := auto_free(SectorPanel.new()) as SectorPanel
	panel.setup(sector, _history)
	add_child(panel)
	return panel


# --- SectorEdits ------------------------------------------------------------------------------------------------------

func test_a_neighbour_is_set_and_undone_and_redone() -> void:
	var sector := _load(Ground.EDIT)
	var edits := SectorEdits.new(sector, _history)
	var old := sector.neighbors_right[4]
	assert_bool(edits.set_neighbor(SectorEdits.Side.RIGHT, 4, 7)).is_true()
	assert_int(sector.neighbors_right[4]).is_equal(7)
	assert_bool(_history.undo()).is_true()
	assert_int(sector.neighbors_right[4]).is_equal(old)
	assert_bool(_history.redo()).is_true()
	assert_int(sector.neighbors_right[4]).is_equal(7)
	assert_array(Array(sector.header_problems())).is_empty()
	assert_bool(edits.set_neighbor(SectorEdits.Side.RIGHT, 4, 12)).is_false()
	assert_str(edits.refusal[0]).contains("not a screen")
	assert_int(sector.neighbors_right[4]).is_equal(7)


func test_the_start_must_be_on_the_grid_and_a_refusal_costs_no_undo_step() -> void:
	var sector := _load(Ground.EDIT)
	var edits := SectorEdits.new(sector, _history)
	var before := sector.start_pos
	var frame := sector.start_frame
	var music := sector.music_name
	assert_bool(edits.set_start_pos(Vector2i(101, 100))).is_false()
	assert_str(edits.refusal[0]).contains("even")
	assert_vector(sector.start_pos).is_equal(before)
	assert_bool(_history.has_undo()).is_false()
	assert_bool(edits.set_start_pos(Vector2i(100, 100))).is_true()
	assert_bool(edits.set_start_frame(2)).is_true()
	assert_bool(edits.set_music("esect5")).is_true()
	assert_bool(_history.undo()).is_true()
	assert_str(sector.music_name).is_equal(music)
	assert_bool(_history.undo()).is_true()
	assert_int(sector.start_frame).is_equal(frame)
	assert_bool(_history.undo()).is_true()
	assert_vector(sector.start_pos).is_equal(before)


func test_a_piece_is_moved_added_and_removed_with_undo() -> void:
	var sector := _load(Ground.EDIT)
	var edits := SectorEdits.new(sector, _history)
	var header := sector.encode()
	var count := sector.pieces.size()
	assert_bool(edits.set_piece(2, 5, Vector2i(200, 100))).is_true()
	assert_int(sector.pieces[2].screen).is_equal(5)
	assert_bool(edits.add_piece(1, Vector2i(64, 64))).is_true()
	assert_int(sector.pieces.size()).is_equal(count + 1)
	assert_bool(edits.remove_piece(3)).is_true()
	assert_int(sector.pieces.size()).is_equal(count)
	assert_bool(_history.undo()).is_true()                   # the removal: the same piece, at the same number
	assert_int(sector.pieces.size()).is_equal(count + 1)
	assert_bool(_history.undo()).is_true()
	assert_bool(_history.undo()).is_true()
	assert_int(sector.pieces.size()).is_equal(count)
	assert_array(Array(sector.encode())).is_equal(Array(header))
	assert_bool(_history.redo()).is_true()
	assert_bool(_history.redo()).is_true()
	assert_bool(_history.redo()).is_true()
	assert_int(sector.pieces.size()).is_equal(count)
	assert_int(sector.pieces[2].screen).is_equal(5)


func test_the_limits_are_refused_with_the_reason_and_leave_no_trace() -> void:
	var sector := _load(Ground.MAIN)                          # 11 pieces
	var edits := SectorEdits.new(sector, _history)
	assert_bool(edits.add_piece(1, Vector2i(64, 64))).is_false()
	assert_str(" ".join(edits.refusal)).contains("11 pieces")
	assert_bool(edits.remove_piece(0)).is_false()
	assert_str(" ".join(edits.refusal)).contains("data canister")
	assert_bool(edits.set_piece(1, 3, Vector2i(5, 8))).is_false()
	var named := _load(Ground.EDIT)                           # its script names creatures 3 and 1
	var named_edits := SectorEdits.new(named, _history)
	assert_bool(named_edits.remove_foe(0)).is_false()         # the script names a creature after it
	assert_str(" ".join(named_edits.refusal)).contains("line")
	assert_bool(_history.has_undo()).is_false()
	assert_int(sector.pieces.size()).is_equal(11)


func test_a_creature_is_added_and_removed_with_undo() -> void:
	var sector := _load(Ground.MAIN)
	var edits := SectorEdits.new(sector, _history)
	var count := sector.foes.size()
	var buffer := sector.encode_foe_buffer()
	assert_bool(edits.add_foe(2, Vector2i(100, 100), 1)).is_true()
	assert_int(sector.foes.size()).is_equal(count + 1)
	assert_int(sector.foes[count].screen).is_equal(2)
	assert_bool(edits.remove_foe(1)).is_true()                # nobody names a creature in this sector's script
	assert_int(sector.foes.size()).is_equal(count)
	assert_bool(_history.undo()).is_true()
	assert_int(sector.foes.size()).is_equal(count + 1)
	assert_bool(_history.undo()).is_true()
	assert_array(Array(sector.encode_foe_buffer())).is_equal(Array(buffer))
	assert_bool(_history.redo()).is_true()
	assert_int(sector.foes.size()).is_equal(count + 1)


func test_without_a_history_a_change_is_simply_made() -> void:
	var sector := _load(Ground.EDIT)
	var edits := SectorEdits.new(sector)
	assert_bool(edits.set_neighbor(SectorEdits.Side.UP, 1, 3)).is_true()
	assert_int(sector.neighbors_up[1]).is_equal(3)
	var count := sector.pieces.size()
	assert_bool(edits.add_piece(1, Vector2i(64, 64))).is_true()
	assert_int(sector.pieces.size()).is_equal(count + 1)


func test_the_live_problems_are_the_headers_and_the_creature_records() -> void:
	var sector := _load(Ground.EDIT)
	var edits := SectorEdits.new(sector)
	assert_array(edits.problems()).is_empty()
	sector.pieces[1].pos = Vector2i(33, 40)                   # off the grid: no original form
	sector.foes[0].damage = 300
	sector.neighbors_left[2] = 40
	var text := "\n".join(edits.problems())
	assert_str(text).contains("piece 1").contains("not on the grid")
	assert_str(text).contains("creature 0").contains("damage 300")
	assert_str(text).contains("neighbors_left of screen 2")
	assert_array(edits.notes()).is_empty()
	var finale := _load(Ground.FINALE)
	assert_array(SectorEdits.new(finale).notes()).is_empty()  # a finale has no pieces and needs none


# --- SectorPanel ------------------------------------------------------------------------------------------------------

func test_the_panel_shows_the_sector() -> void:
	var sector := _load(Ground.EDIT)
	var panel := _panel(sector)
	assert_int(panel._piece_rows.get_child_count()).is_equal(7)
	assert_int(panel._foe_rows.get_child_count()).is_equal(sector.foes.size())
	assert_str(panel._pieces_section.title).is_equal("Pieces: 7 of 11")
	assert_str(panel._foes_section.title).is_equal("Creatures: %d of 255" % sector.foes.size())
	assert_float(panel._start_x.value).is_equal(float(sector.start_pos.x))
	assert_int(int(panel._start_frame.value)).is_equal(sector.start_frame)
	for screen in 12:
		assert_int((panel._neighbors[0][screen] as OptionButton).selected).is_equal(sector.neighbors_left[screen] + 1)
		assert_int((panel._neighbors[3][screen] as OptionButton).selected).is_equal(sector.neighbors_down[screen] + 1)
	assert_str(panel._music.get_item_text(panel._music.selected)).starts_with(sector.music_name)
	assert_bool(panel._problems.visible).is_false()
	assert_str(panel._music_note.text).contains(SectorPanel.game_song(sector.music_name))
	# the piece rows show the data canister first, and its Remove button is off while other pieces are there
	assert_str((panel._piece_rows.get_child(0).get_child(0) as Label).text).contains("data canister")
	assert_bool((panel._piece_rows.get_child(0).get_child(4) as Button).disabled).is_true()
	assert_bool((panel._piece_rows.get_child(1).get_child(4) as Button).disabled).is_false()
	assert_bool(panel._add_piece.disabled).is_false()


func test_the_panel_names_screens_and_creatures_from_the_registry() -> void:
	var sector := _load(Ground.EDIT)
	var panel := _panel(sector)
	var registry := NameRegistry.original()
	var screen_scope := Ground.EDIT
	for screen in [0, 3, 11]:
		var name := registry.name_of(&"screen", screen, screen_scope) if registry.is_named(&"screen", screen, screen_scope) else ""
		assert_str(panel.label_of(&"screen", screen)).is_equal("%d  %s" % [screen, name] if not name.is_empty() else str(screen))   # a name, or just the number
	assert_str(panel.label_of(&"screen", 12)).is_equal("12")
	var foe_name := registry.name_of(&"foe", 0, Ground.EDIT) if registry.is_named(&"foe", 0, Ground.EDIT) else ""
	assert_str(panel.label_of(&"foe", 0)).is_equal("0  " + foe_name if not foe_name.is_empty() else "0")


func test_pressing_the_buttons_changes_the_data_and_undo_brings_the_rows_back() -> void:
	var sector := _load(Ground.EDIT)
	var panel := _panel(sector)
	var count := sector.pieces.size()
	(panel._piece_rows.get_child(4).get_child(4) as Button).pressed.emit()          # Remove piece 4
	assert_int(sector.pieces.size()).is_equal(count - 1)
	assert_int(panel._piece_rows.get_child_count()).is_equal(count - 1)
	assert_str(panel._pieces_section.title).is_equal("Pieces: %d of 11" % (count - 1))
	var added := 0
	while sector.pieces.size() < SectorData.MAX_PIECES:
		panel._add_piece.pressed.emit()
		added += 1
	assert_int(sector.pieces.size()).is_equal(SectorData.MAX_PIECES)
	assert_bool(panel._add_piece.disabled).is_true()                                # 11 of 11
	assert_bool(panel._refusal.visible).is_false()
	panel._add_piece.pressed.emit()                                                 # a button that was off, pressed anyway
	assert_int(sector.pieces.size()).is_equal(SectorData.MAX_PIECES)
	assert_bool(panel._refusal.visible).is_true()
	assert_str(panel._refusal.text).contains("Not changed").contains("11 pieces")
	for step in 1 + added:
		_history.undo()
	assert_int(sector.pieces.size()).is_equal(count)
	assert_int(panel._piece_rows.get_child_count()).is_equal(count)
	assert_bool(panel._add_piece.disabled).is_false()


func test_choosing_in_the_controls_edits_the_neighbours_the_start_the_pieces_and_the_music() -> void:
	var sector := _load(Ground.EDIT)
	var panel := _panel(sector)
	(panel._neighbors[1][4] as OptionButton).item_selected.emit(3)                  # right of screen 4: screen 2
	assert_int(sector.neighbors_right[4]).is_equal(2)
	(panel._neighbors[1][4] as OptionButton).item_selected.emit(0)                  # "-": none
	assert_int(sector.neighbors_right[4]).is_equal(-1)
	panel._start_x.value = 200
	assert_int(sector.start_pos.x).is_equal(200)
	panel._start_y.value = 91                                                       # the box steps by 2: it can not hold an odd number
	assert_int(sector.start_pos.y % 2).is_equal(0)
	assert_float(panel._start_y.value).is_equal(float(sector.start_pos.y))
	panel._start_frame.value = 3
	assert_int(sector.start_frame).is_equal(3)
	var row := panel._piece_rows.get_child(2)
	(row.get_child(1) as OptionButton).item_selected.emit(9)
	assert_int(sector.pieces[2].screen).is_equal(9)
	(row.get_child(2) as SpinBox).value = 120
	assert_int(sector.pieces[2].pos.x).is_equal(120)
	var songs: Array = SectorPanel.songs().keys()
	panel._music.item_selected.emit(5)
	assert_str(sector.music_name).is_equal(songs[5])
	assert_str(panel._music.get_item_text(panel._music.selected)).starts_with(songs[5])
	assert_str(panel._music_note.text).contains(SectorPanel.game_song(songs[5]))   # what the game plays follows the name (through the campaign)


func test_a_creature_the_script_depends_on_says_so_in_the_panel() -> void:
	var sector := _load(Ground.EDIT)
	var panel := _panel(sector)
	var count := sector.foes.size()
	(panel._foe_rows.get_child(0).get_child(3) as Button).pressed.emit()            # Remove creature 0
	assert_int(sector.foes.size()).is_equal(count)
	assert_bool(panel._refusal.visible).is_true()
	assert_str(panel._refusal.text).contains("line").contains("would become creature")
	(panel._foe_rows.get_child(1).get_child(2) as Button).pressed.emit()            # Copy creature 1
	assert_int(sector.foes.size()).is_equal(count + 1)
	assert_bool(panel._refusal.visible).is_false()
	assert_int(sector.foes[count].screen).is_equal(sector.foes[1].screen)
	assert_int(panel._foe_rows.get_child_count()).is_equal(count + 1)
	(panel._foe_rows.get_child(count).get_child(3) as Button).pressed.emit()        # the copy goes again: it is last and unnamed
	assert_int(sector.foes.size()).is_equal(count)


func test_the_panel_shows_what_cannot_be_stored_and_follows_a_change_from_elsewhere() -> void:
	var sector := _load(Ground.EDIT)
	var panel := _panel(sector)
	assert_bool(panel._problems.visible).is_false()
	sector.pieces[0].pos = Vector2i(11, 12)                                          # changed in the raw Inspector, say
	sector.emit_changed()
	assert_bool(panel._problems.visible).is_true()
	assert_str(panel._problems.text).contains("piece 0")
	sector.pieces[0].pos = Vector2i(14, 12)
	sector.emit_changed()
	assert_float(panel._piece_rows.get_child(0).get_child(2).value).is_equal(14.0)   # a box that steps by 2 can show only even numbers
	sector.pieces[0].pos = Vector2i(10, 12)
	sector.emit_changed()
	assert_bool(panel._problems.visible).is_false()


# --- the music names ----------------------------------------------------------------------------------------------------

func test_the_song_the_panel_names_is_the_song_the_game_plays() -> void:
	# (a sector in no campaign plays the default song whatever it is called; the sectors of the dev tour are in one)
	for s in DevPack.TOUR_SECTORS + [DevPack.TOUR_FINALE]:
		assert_str(SectorPanel.game_song(_load(s).music_name)).override_failure_message("sector %d" % s).is_equal(AudioService.music_for_sector(s))


func test_the_songs_of_the_panel_are_the_catalogs() -> void:
	var catalog := Catalog.music_catalog()
	var registry := NameRegistry.original()
	var stems: Array[String] = []
	for midi: String in catalog.midi_names:
		stems.append(("e" + midi.get_basename().substr(1)).to_lower())
	assert_array(SectorPanel.songs().keys()).contains_exactly_in_any_order(stems)
	for stem: String in SectorPanel.songs():
		assert_int(registry.index_of(&"music", String(SectorPanel.songs()[stem]))).is_equal(catalog.ids[stems.find(stem)])
	for s in Ground.clean_sectors():
		assert_bool(SectorPanel.songs().has(_load(s).music_name)).override_failure_message("sector %d: %s" % [s, _load(s).music_name]).is_true()


# --- the Inspector plugin -----------------------------------------------------------------------------------------------

func test_the_inspector_plugin_takes_sectors_and_hides_what_the_panel_replaces() -> void:
	assert_bool(SectorInspectorPlugin.handles(SectorData.new())).is_true()
	assert_bool(SectorInspectorPlugin.handles(ScreenData.new())).is_false()
	assert_bool(SectorInspectorPlugin.handles(PieceData.new())).is_false()
	for name in ["start_pos", "start_frame", "neighbors_left", "neighbors_right", "neighbors_up", "neighbors_down", "music_name", "pieces", "stale_pieces", "foe_script_base"]:
		assert_bool(SectorInspectorPlugin.hides(name)).override_failure_message(name).is_true()
	for name in ["foes", "index", "zone", "screens", "foe_script"]:
		assert_bool(SectorInspectorPlugin.hides(name)).override_failure_message(name).is_false()
	# what is hidden is a real stored property (a rename would otherwise leave the raw row showing)
	var stored: Array[String] = []
	for property in SectorData.new().get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
			stored.append(property.name)
	for name in SectorInspectorPlugin.HIDDEN:
		assert_array(stored).contains([name])
