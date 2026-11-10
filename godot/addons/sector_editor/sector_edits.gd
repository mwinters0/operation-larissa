@tool
class_name SectorEdits
extends RefCounted
## Every change the Sector Inspector can make to a `SectorData`, as a function with an undo, and the live list of what is wrong.
##
## Teaches: keeping the LOGIC of an editor panel out of its controls. The panel (`SectorPanel`) only turns clicks into calls on
## this class, and this class has no controls in it: a test (tests/engine/test_sector_inspector.gd) can run the same calls headless.
## It also shows how an editor plugin does undo. In the editor the `history` is the plugin's `EditorUndoRedoManager`
## (`EditorPlugin.get_undo_redo()`): one `create_action`, a list of "do" and "undo" calls on the edited resource, `commit_action`
## (which runs the "do" calls straight away). The Edit menu's Undo and Redo, and Ctrl+Z in the Inspector, then work on the sector
## without us handling a key. Outside the editor (the test, a script) the same code runs on a plain `UndoRedo`, or with `null`
## it simply does the change. `EditorUndoRedoManager` and `UndoRedo` differ in how a call is named (an object and a method's
## name, or a `Callable`), which is all `_commit` has to know.
##
## The undo calls are the opposite operations of the same `SectorData` functions (`insert_piece` / `remove_piece`, ...), or the
## old value of a property. A call changes the resource (and `emit_changed` tells the panel); the Inspector's own rows rebuild
## after a call that changed a list (`notify_property_list_changed`). The editor marks a resource it changed through its undo
## history as edited, so Ctrl+S saves it: `SectorDataSaver` writes the file (it refuses what it cannot write, with a message).

enum Side { LEFT, RIGHT, UP, DOWN }

const SIDE_NAMES: Array[String] = ["left", "right", "up", "down"]
const SIDE_PROPERTIES: Array[String] = ["neighbors_left", "neighbors_right", "neighbors_up", "neighbors_down"]

var sector: SectorData
## `EditorUndoRedoManager`, `UndoRedo`, or null.
var history: Object
## The object whose undo history the actions belong to when `history` is the editor's `EditorUndoRedoManager` (it keeps one history per
## scene, and one for resources outside any scene). Null: the sector, which is the Inspector's case. The screen editor passes its own
## root, so that Ctrl+Z in the scene undoes a creature added from the screen editor.
var history_owner: Object = null
## Why the last change was refused, in words; empty after a change that worked.
var refusal: Array[String] = []


func _init(p_sector: SectorData, p_history: Object = null, p_history_owner: Object = null) -> void:
	sector = p_sector
	history = p_history
	history_owner = p_history_owner


# --- what is wrong, live ------------------------------------------------------------------------------------------------------

## Everything that stops the sector from being stored as the original's (`SectorData.header_problems()` and the creature
## records' problems), in plain words. The screens have their own editor; their messages are not repeated here.
func problems() -> Array[String]:
	var found := sector.header_problems()
	found.append_array(sector.foe_problems())
	return found


## What is allowed but worth knowing.
func notes() -> Array[String]:
	var found := sector.foe_notes()
	if sector.pieces.is_empty() and sector.finale_screen < 0:
		found.append("no pieces: the sector has no data canister, so the combination lock opens at once")
	return found


# --- the header --------------------------------------------------------------------------------------------------------------

## Screen `destination` (-1: none) is where you go from `screen` through `side`.
func set_neighbor(side: int, screen: int, destination: int) -> bool:
	var table := (sector.get(SIDE_PROPERTIES[side]) as PackedInt32Array).duplicate()
	if screen < 0 or screen >= table.size() or destination < -1 or destination >= SectorData.SCREEN_COUNT:
		return _refuse("screen %d, %s: %d is not a screen of the sector (0 to %d, or -1 for none)" % [screen, SIDE_NAMES[side], destination, SectorData.SCREEN_COUNT - 1])
	if table[screen] == destination:
		return _ok()
	var old := (sector.get(SIDE_PROPERTIES[side]) as PackedInt32Array).duplicate()
	table[screen] = destination
	_commit("Set neighbour (%s of screen %d)" % [SIDE_NAMES[side], screen],
			[[sector, "set", SIDE_PROPERTIES[side], table]], [[sector, "set", SIDE_PROPERTIES[side], old]])
	return _ok()


## Where the sub starts (window pixels, even numbers: the file keeps the halves).
func set_start_pos(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.y < 0 or pos.x % 2 != 0 or pos.y % 2 != 0:
		return _refuse("the start position %s must be even numbers, from 0 up (the original keeps x / 2 and y / 2)" % pos)
	if pos == sector.start_pos:
		return _ok()
	_commit("Set start position", [[sector, "set", "start_pos", pos]], [[sector, "set", "start_pos", sector.start_pos]])
	return _ok()


## The picture of the sub at the start.
func set_start_frame(frame: int) -> bool:
	if frame < 0 or frame > 0xFFFF:
		return _refuse("the start frame %d must be 0 to 65535" % frame)
	if frame == sector.start_frame:
		return _ok()
	_commit("Set start frame", [[sector, "set", "start_frame", frame]], [[sector, "set", "start_frame", sector.start_frame]])
	return _ok()


## The song's name (the stem of its MIDI file, `MusicCatalog.midi_names`). The game still picks the sector's song by its number
## (`SelectSectorMusic`), so this is data for the future: see `SectorPanel`.
func set_music(song: String) -> bool:
	if song == sector.music_name:
		return _ok()
	_commit("Set music", [[sector, "set", "music_name", song]], [[sector, "set", "music_name", sector.music_name]])
	return _ok()


# --- pieces ------------------------------------------------------------------------------------------------------------------

## Moves piece `index` to `screen` and `pos` (window pixels, even numbers).
func set_piece(index: int, screen: int, pos: Vector2i) -> bool:
	if index < 0 or index >= sector.pieces.size():
		return _refuse("piece %d does not exist" % index)
	var piece := sector.pieces[index]
	if screen < 0 or screen >= SectorData.SCREEN_COUNT:
		return _refuse("screen %d: a sector has the screens 0 to %d" % [screen, SectorData.SCREEN_COUNT - 1])
	var bad := SectorData._position_problems(pos, "piece %d" % index)
	if not bad.is_empty():
		return _refuse_all(bad)
	if piece.screen == screen and piece.pos == pos:
		return _ok()
	_commit("Move piece %d" % index,
			[[piece, "set", "screen", screen], [piece, "set", "pos", pos]],
			[[piece, "set", "screen", piece.screen], [piece, "set", "pos", piece.pos]])
	return _ok()


## Adds a piece at the end of the list (`SectorData.add_piece`).
func add_piece(screen: int, pos: Vector2i) -> bool:
	var piece := PieceData.new()
	piece.screen = screen
	piece.pos = pos
	var bad := piece_insert_problems(piece)
	if not bad.is_empty():
		return _refuse_all(bad)
	var at := sector.pieces.size()
	_commit("Add piece %d" % at, [[sector, "insert_piece", piece, at]], [[sector, "remove_piece", at]], true)
	return _ok()


## Removes piece `index`; the undo puts the same piece back at the same number.
func remove_piece(index: int) -> bool:
	var probe := piece_remove_problems(index)
	if not probe.is_empty():
		return _refuse_all(probe)
	var piece := sector.pieces[index]
	_commit("Remove piece %d" % index, [[sector, "remove_piece", index]], [[sector, "insert_piece", piece, index]], true)
	return _ok()


# --- creatures ---------------------------------------------------------------------------------------------------------------

## Adds a creature on `screen` at `pos`, a copy of creature `like` (-1: the first one that hurts) at the end of the list.
func add_foe(screen: int, pos: Vector2i, like := -1) -> bool:
	# the creature is made here (not inside `SectorData.add_foe`), so that the redo puts exactly the same one back
	var foe := sector.new_foe(screen, pos, like)
	var bad := foe_insert_problems(foe)
	if not bad.is_empty():
		return _refuse_all(bad)
	var at := sector.foes.size()
	_commit("Add creature %d" % at, [[sector, "insert_foe", foe, at]], [[sector, "remove_foe", at]], true)
	return _ok()


## Removes creature `index` unless the script depends on its number (`SectorData.remove_foe` says why).
func remove_foe(index: int) -> bool:
	if index < 0 or index >= sector.foes.size():
		return _refuse("creature %d does not exist" % index)
	var bad := foe_remove_problems(index)
	if not bad.is_empty():
		return _refuse_all(bad)
	var foe := sector.foes[index]
	_commit("Remove creature %d" % index, [[sector, "remove_foe", index]], [[sector, "insert_foe", foe, index]], true)
	return _ok()


# --- the checks before a change ---------------------------------------------------------------------------------------------
# The change itself is a `SectorData` call inside the undo action, so the checks use the same function on a stand-in: a copy of the
# lists, not of the screens, so a refusal changes nothing and costs no undo step.

## Why `piece` could not be inserted at the end now (empty: it can). Changes nothing.
func piece_insert_problems(piece: PieceData) -> Array[String]:
	var stand_in := _stand_in()
	return stand_in.insert_piece(piece.duplicate() as PieceData)


## Why piece `index` could not be removed now (empty: it can). Changes nothing.
func piece_remove_problems(index: int) -> Array[String]:
	return _stand_in().remove_piece(index)


## Why `foe` could not be inserted at the end now (empty: it can). Changes nothing.
func foe_insert_problems(foe: FoeData) -> Array[String]:
	return _stand_in().insert_foe(foe.duplicate() as FoeData)


## Why creature `index` could not be removed now (the script names it, ...; empty: it can). Changes nothing.
func foe_remove_problems(index: int) -> Array[String]:
	return _stand_in().remove_foe(index)


## A `SectorData` with the same pieces, creatures and script as `sector` (the objects are shared, the lists are not), for asking
## "would this be allowed?" without doing it.
func _stand_in() -> SectorData:
	var other := SectorData.new()
	other.index = sector.index
	other.zone = sector.zone
	other.pieces = sector.pieces.duplicate()
	other.foes = sector.foes.duplicate()
	other.foe_script = sector.foe_script
	other.foe_script_base = sector.foe_script_base
	return other


# --- undo ---------------------------------------------------------------------------------------------------------------------

## Does `do_calls` as one undoable action and remembers how to take it back with `undo_calls`. A call is [object, method, args...].
## `lists`: pieces or creatures were added or removed, so the Inspector's own rows (the raw `foes` list) must be built again.
func _commit(label: String, do_calls: Array, undo_calls: Array, lists := false) -> void:
	do_calls.append([sector, "emit_changed"])
	undo_calls.append([sector, "emit_changed"])
	if lists:
		do_calls.append([sector, "notify_property_list_changed"])
		undo_calls.append([sector, "notify_property_list_changed"])
	if history == null:
		for call: Array in do_calls:
			(call[0] as Object).callv(call[1], call.slice(2))
	elif history is UndoRedo:
		var plain := history as UndoRedo
		plain.create_action(label)
		for call: Array in do_calls:
			plain.add_do_method(Callable(call[0], call[1]).bindv(call.slice(2)))
		for call: Array in undo_calls:
			plain.add_undo_method(Callable(call[0], call[1]).bindv(call.slice(2)))
		plain.commit_action()
	else:
		# EditorUndoRedoManager: the third argument says whose history the action belongs to (a resource that is no part of a scene).
		history.call("create_action", label, UndoRedo.MERGE_DISABLE, history_owner if history_owner != null else sector)
		for call: Array in do_calls:
			history.callv("add_do_method", [call[0], call[1]] + call.slice(2))
		for call: Array in undo_calls:
			history.callv("add_undo_method", [call[0], call[1]] + call.slice(2))
		history.call("commit_action")


func _ok() -> bool:
	refusal = []
	return true


func _refuse(why: String) -> bool:
	refusal = [why]
	return false


func _refuse_all(why: Array[String]) -> bool:
	refusal = why
	return false
