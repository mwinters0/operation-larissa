@tool
class_name SectorPanel
extends VBoxContainer
## The controls of the Sector Inspector: what a designer sees above a `SectorData`'s properties in the Inspector.
##
## Teaches: building an editor panel from plain controls in code (a `VBoxContainer` of `FoldableContainer` sections, `GridContainer`,
## `OptionButton`, `SpinBox`), and the one rule that keeps such a panel simple: the panel owns NO state. Every control shows a
## value of the `SectorData`; a change goes to `SectorEdits` (which refuses what the original's format cannot hold and does the undo),
## and `refresh()` sets every control from the data again. Undo, redo, a change made in the raw Inspector rows below or by another
## tool all end in `SectorData.changed`, and the panel just refreshes. `set_value_no_signal` and `select` do not emit the control's
## signal, so refreshing is not mistaken for an edit.
##
## The sections:
##   - problems: what stops the sector from being stored as the original's (`SectorEdits.problems`), live;
##   - start: where the sub starts and with which picture;
##   - neighbours: for each of the 12 screens, the screen you reach through each of the four sides (names from the registry);
##   - music: the song's name and the song the game plays now;
##   - pieces: the 11 slots of the header, the data canister first; add and remove;
##   - creatures: the records of the foe buffer, up to 255; add (a copy of one) and remove. A creature is edited in the screen
##     editor (its markers) and in the rows of the Inspector below this panel.
## Screens and decorations are in the Screen Editor, the creature script in the Foe Script editor.

## Where a new piece or creature appears, until it is moved: the middle of the playfield (window pixels).
const NEW_POSITION := Vector2i(320, 180)
const ERROR_COLOR := Color(1.0, 0.45, 0.4)
const NOTE_COLOR := Color(0.9, 0.8, 0.45)

var sector: SectorData
var edits: SectorEdits

var _problems: Label
var _notes: Label
var _refusal: Label
var _start_x: SpinBox
var _start_y: SpinBox
var _start_frame: SpinBox
## [side][screen] -> OptionButton; item 0 is "no neighbour", item k + 1 is screen k
var _neighbors: Array = []
var _music: OptionButton
var _music_note: Label
var _pieces_section: FoldableContainer
var _piece_rows: VBoxContainer
var _add_piece: Button
var _foes_section: FoldableContainer
var _foe_rows: VBoxContainer
var _add_foe: Button
var _built_pieces := -1
var _built_foes := -1


## Builds the panel for `p_sector`. `history` is the `EditorUndoRedoManager` (or null: no undo).
func setup(p_sector: SectorData, history: Object = null) -> void:
	sector = p_sector
	edits = SectorEdits.new(sector, history)
	name = "SectorPanel"
	add_theme_constant_override("separation", 6)
	_problems = _text_label(ERROR_COLOR)
	_notes = _text_label(NOTE_COLOR)
	_refusal = _text_label(ERROR_COLOR)
	add_child(_problems)
	add_child(_notes)
	add_child(_refusal)
	_build_start()
	_build_neighbors()
	_build_music()
	_build_pieces_section()
	_build_foes_section()
	sector.changed.connect(refresh)
	refresh()


func _exit_tree() -> void:
	if sector != null and sector.changed.is_connected(refresh):
		sector.changed.disconnect(refresh)


## Sets every control from the data again (and builds the piece and creature rows again when their number changed).
func refresh() -> void:
	if sector == null:
		return
	var problems := edits.problems()
	_problems.text = "Cannot be stored as the original's:\n- " + "\n- ".join(problems) if not problems.is_empty() else ""
	_problems.visible = not problems.is_empty()
	var notes := edits.notes()
	_notes.text = "\n".join(notes)
	_notes.visible = not notes.is_empty()
	_start_x.set_value_no_signal(sector.start_pos.x)
	_start_y.set_value_no_signal(sector.start_pos.y)
	_start_frame.max_value = maxi(8, sector.start_frame)
	_start_frame.set_value_no_signal(sector.start_frame)
	for side in 4:
		var table := sector.get(SectorEdits.SIDE_PROPERTIES[side]) as PackedInt32Array
		for screen in mini(table.size(), SectorData.SCREEN_COUNT):
			(_neighbors[side][screen] as OptionButton).select(table[screen] + 1)
	_refresh_music()
	if _built_pieces != sector.pieces.size():
		_build_piece_rows()
	else:
		_sync_piece_rows()
	if _built_foes != sector.foes.size():
		_build_foe_rows()
	else:
		_sync_foe_rows()
	_pieces_section.title = "Pieces: %d of %d" % [sector.pieces.size(), SectorData.MAX_PIECES]
	_foes_section.title = "Creatures: %d of %d" % [sector.foes.size(), SectorData.MAX_FOES]
	_add_piece.disabled = sector.pieces.size() >= SectorData.MAX_PIECES
	_add_foe.disabled = sector.foes.size() >= SectorData.MAX_FOES


## The song the game plays for a sector whose `music_name` is `stem`: what `AudioService.music_for_sector` finds through the campaign
## (`Campaign.song_for`), so the panel shows an edit before it is saved. A stem that is none of the original's songs plays the campaign's
## fallback song, `Campaign.DEFAULT_SONG` for the originals. tests/engine/test_sector_inspector.gd compares the two for all 32 sectors.
static func game_song(stem: String, fallback: StringName = Campaign.DEFAULT_SONG) -> StringName:
	var song := MusicCatalog.song_of_stem(stem)
	return song if song != &"" else fallback


## "3 (sea_urchin)" for a named screen or creature, else "3".
func label_of(kind: StringName, number: int) -> String:
	var registry := NameRegistry.original()
	var scope := sector.index if NameRegistry.is_scoped(kind) and sector.index < NameRegistry.scope_count(kind) else NameRegistry.NO_SCOPE
	if registry.is_named(kind, number, scope):
		return "%d  %s" % [number, registry.name_of(kind, number, scope)]
	return str(number)


# --- start --------------------------------------------------------------------------------------------------------------------

func _build_start() -> void:
	var section := _section("Start")
	var row := HBoxContainer.new()
	row.add_child(_label("x"))
	_start_x = _spin(0, 640, 2)
	row.add_child(_start_x)
	row.add_child(_label("y"))
	_start_y = _spin(0, 400, 2)
	row.add_child(_start_y)
	row.add_child(_label("sub picture"))
	_start_frame = _spin(0, 8, 1)
	_start_frame.tooltip_text = "Which picture of the sub shows at the start (0-8, the same numbers as the sub's sprite cells)."
	row.add_child(_start_frame)
	_start_x.tooltip_text = "Window pixels, even numbers: the file keeps half of them."
	_start_y.tooltip_text = _start_x.tooltip_text
	section.add_child(row)
	_start_x.value_changed.connect(func(_v: float) -> void: _apply(edits.set_start_pos(Vector2i(int(_start_x.value), int(_start_y.value)))))
	_start_y.value_changed.connect(func(_v: float) -> void: _apply(edits.set_start_pos(Vector2i(int(_start_x.value), int(_start_y.value)))))
	_start_frame.value_changed.connect(func(v: float) -> void: _apply(edits.set_start_frame(int(v))))


# --- neighbours ---------------------------------------------------------------------------------------------------------------

func _build_neighbors() -> void:
	var section := _section("Neighbours", true)
	var hint := _label("The screen you reach by leaving through a side. The original keeps one entry per screen and side.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(hint)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	section.add_child(grid)
	grid.add_child(_label("Screen"))
	for side in 4:
		grid.add_child(_label(SectorEdits.SIDE_NAMES[side].capitalize()))
	_neighbors = [[], [], [], []]
	for screen in SectorData.SCREEN_COUNT:
		grid.add_child(_label(label_of(&"screen", screen)))
		for side in 4:
			var choice := OptionButton.new()
			choice.add_item("-")
			for destination in SectorData.SCREEN_COUNT:
				choice.add_item(label_of(&"screen", destination))
			choice.tooltip_text = "%s of screen %d" % [SectorEdits.SIDE_NAMES[side], screen]
			choice.item_selected.connect(func(item: int) -> void: _apply(edits.set_neighbor(side, screen, item - 1)))
			grid.add_child(choice)
			(_neighbors[side] as Array).append(choice)


# --- music --------------------------------------------------------------------------------------------------------------------

func _build_music() -> void:
	var section := _section("Music")
	_music = OptionButton.new()
	_music.item_selected.connect(func(item: int) -> void: _apply(edits.set_music(String(_music.get_item_metadata(item)))))
	section.add_child(_music)
	_music_note = _label("")
	_music_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(_music_note)


## The songs the original has, by the stem of their MIDI file (what `SectorData.music_name` holds), and the registry's `music` name.
static func songs() -> Dictionary:
	return Catalog.music_catalog().songs_by_stem()


## The song for a sector whose `music_name` is none of the original's: its campaign's `fallback_song`.
func _fallback_song() -> StringName:
	var campaign := Catalog.campaign_of_sector(sector.index)
	return campaign.fallback_song if campaign != null else Campaign.DEFAULT_SONG


func _refresh_music() -> void:
	_music.clear()
	var selected := -1
	var songs := songs()
	for stem: String in songs:
		_music.add_item("%s  (%s)" % [stem, songs[stem]])
		_music.set_item_metadata(_music.item_count - 1, stem)
		if stem == sector.music_name:
			selected = _music.item_count - 1
	if selected < 0:                                    # a name that is none of the original's songs: keep it as it is
		_music.add_item("%s  (not an original song)" % sector.music_name)
		_music.set_item_metadata(_music.item_count - 1, sector.music_name)
		selected = _music.item_count - 1
	_music.select(selected)
	_music_note.text = "The game plays '%s' in this sector: the song named above, through the campaign that lists the sector (the original's own sectors name the songs SelectSectorMusic would choose by number)." % game_song(sector.music_name, _fallback_song())


# --- pieces -------------------------------------------------------------------------------------------------------------------

func _build_pieces_section() -> void:
	var body := _section("Pieces")
	_pieces_section = body.get_parent() as FoldableContainer
	_piece_rows = VBoxContainer.new()
	body.add_child(_piece_rows)
	_add_piece = Button.new()
	_add_piece.text = "Add a piece"
	_add_piece.tooltip_text = "Puts a new piece in the middle of the last piece's screen. The header has room for 11."
	_add_piece.pressed.connect(func() -> void:
		var screen := sector.pieces[sector.pieces.size() - 1].screen if not sector.pieces.is_empty() else 0
		_apply(edits.add_piece(screen, NEW_POSITION)))
	body.add_child(_add_piece)


func _build_piece_rows() -> void:
	_clear(_piece_rows)
	_built_pieces = sector.pieces.size()
	for k in sector.pieces.size():
		var row := HBoxContainer.new()
		row.name = "Piece%d" % k
		var title := _label("%d  %s" % [k, "data canister" if k == 0 else "piece"])
		title.custom_minimum_size.x = 110
		row.add_child(title)
		var screen := _screen_choice()
		screen.item_selected.connect(func(item: int) -> void: _move_piece(k, item, null, null))
		row.add_child(screen)
		var x := _spin(0, 640, 2)
		x.value_changed.connect(func(v: float) -> void: _move_piece(k, -1, int(v), null))
		row.add_child(x)
		var y := _spin(0, 400, 2)
		y.value_changed.connect(func(v: float) -> void: _move_piece(k, -1, null, int(v)))
		row.add_child(y)
		var remove := Button.new()
		remove.text = "Remove"
		remove.pressed.connect(func() -> void: _apply(edits.remove_piece(k)))
		row.add_child(remove)
		_piece_rows.add_child(row)
	_sync_piece_rows()


func _sync_piece_rows() -> void:
	for k in sector.pieces.size():
		var row := _piece_rows.get_child(k)
		(row.get_child(1) as OptionButton).select(sector.pieces[k].screen)
		(row.get_child(2) as SpinBox).set_value_no_signal(sector.pieces[k].pos.x)
		(row.get_child(3) as SpinBox).set_value_no_signal(sector.pieces[k].pos.y)
		# the canister goes only when it is alone (SectorData.remove_piece); the button says so by being off
		(row.get_child(4) as Button).disabled = k == 0 and sector.pieces.size() > 1


## A move of piece `k` to screen `screen` (when not -1), x (when not null) or y (when not null): the other parts stay.
func _move_piece(k: int, screen: int, x: Variant, y: Variant) -> void:
	var piece := sector.pieces[k]
	var pos := Vector2i(int(x) if x != null else piece.pos.x, int(y) if y != null else piece.pos.y)
	_apply(edits.set_piece(k, screen if screen >= 0 else piece.screen, pos))


# --- creatures ----------------------------------------------------------------------------------------------------------------

func _build_foes_section() -> void:
	var body := _section("Creatures", true)
	_foes_section = body.get_parent() as FoldableContainer
	var hint := _label("Position and picture of a creature: the markers of the Screen Editor, or its rows in the list below. A new creature is a copy and behaves like it; edit the script to make it different.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint)
	_foe_rows = VBoxContainer.new()
	body.add_child(_foe_rows)
	_add_foe = Button.new()
	_add_foe.text = "Add a creature"
	_add_foe.tooltip_text = "A copy of the first creature that hurts, in the middle of screen 0, at the end of the list."
	_add_foe.pressed.connect(func() -> void: _apply(edits.add_foe(0, NEW_POSITION)))
	body.add_child(_add_foe)


func _build_foe_rows() -> void:
	_clear(_foe_rows)
	_built_foes = sector.foes.size()
	for k in sector.foes.size():
		var row := HBoxContainer.new()
		row.name = "Foe%d" % k
		var title := _label(label_of(&"foe", k))
		title.custom_minimum_size.x = 190
		row.add_child(title)
		var where := _label("")
		where.custom_minimum_size.x = 150
		row.add_child(where)
		var copy := Button.new()
		copy.text = "Copy"
		copy.tooltip_text = "Adds a creature at the end that is a copy of this one (same picture, damage and script)."
		copy.pressed.connect(func() -> void:
			var foe := sector.foes[k]
			_apply(edits.add_foe(foe.screen, foe.pos + Vector2i(16, 0), k)))
		row.add_child(copy)
		var remove := Button.new()
		remove.text = "Remove"
		remove.tooltip_text = "Removes this creature, unless the script depends on its number (the message says which line)."
		remove.pressed.connect(func() -> void: _apply(edits.remove_foe(k)))
		row.add_child(remove)
		_foe_rows.add_child(row)
	_sync_foe_rows()


func _sync_foe_rows() -> void:
	for k in sector.foes.size():
		var foe := sector.foes[k]
		var row := _foe_rows.get_child(k)
		(row.get_child(1) as Label).text = "screen %d  %d, %d" % [foe.screen, foe.pos.x, foe.pos.y]
		(row.get_child(2) as Button).disabled = sector.foes.size() >= SectorData.MAX_FOES


# --- helpers ------------------------------------------------------------------------------------------------------------------

## Shows the outcome of a change: nothing after a change that worked, the reasons after a refusal (and the controls go back to
## the data, which did not change).
func _apply(worked: bool) -> void:
	_refusal.text = "" if worked else "Not changed: " + " ".join(edits.refusal)
	_refusal.visible = not worked
	refresh()


## A foldable section with a title; returns its body, the box to put the rows in (`body.get_parent()` is the section).
func _section(title: String, folded := false) -> VBoxContainer:
	var section := FoldableContainer.new()
	section.title = title
	section.folded = folded
	var body := VBoxContainer.new()
	section.add_child(body)
	add_child(section)
	return body


func _screen_choice() -> OptionButton:
	var choice := OptionButton.new()
	for screen in SectorData.SCREEN_COUNT:
		choice.add_item(label_of(&"screen", screen))
	return choice


func _spin(minimum: float, maximum: float, step: float) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = minimum
	box.max_value = maximum
	box.step = step
	box.allow_greater = true
	return box


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _text_label(color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	label.visible = false
	return label


func _clear(box: Control) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
