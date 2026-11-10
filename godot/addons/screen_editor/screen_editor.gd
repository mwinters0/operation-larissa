@tool
class_name ScreenEditor
extends Node2D
## The screen editor's work scene: one screen of one sector, as nodes you can select, paint and drag.
##
## Teaches: a `@tool` scene root that BUILDS its own content from data files, and how that works with the editor's save:
##  * Everything under this node is made in code from `screen_MM.tres` (and the pieces / respawn point of `sector_NN.tres`)
##    when the scene opens. The nodes get `owner = self`, because only owned nodes show up in the Scene dock and can be
##    selected (the TileMap panel only works on a layer you selected).
##  * Ordinarily Ctrl+S would then write all those nodes into the `.tscn`. This scene does not: right before the editor
##    saves it (`NOTIFICATION_EDITOR_PRE_SAVE`) the owners are taken away, so the saved scene is just this root, and right
##    after (`NOTIFICATION_EDITOR_POST_SAVE`) they are given back. The `.tscn` is a throw-away holder for (sector, screen);
##    the SCREEN is saved by `save_screen()` into its own `.tres` (the plugin calls it on Ctrl+S, see
##    `ScreenEditorPlugin._save_external_data`; the Save button in the Inspector calls it too).
##  * Positions are WINDOW pixels, the numbers of the file: this node sits at (0, 0), the playfield (608 x 288) starts at
##    (16, 32), and `position` in the Inspector of a deco is exactly the `pos` stored in the screen file. Keep this
##    node at (0, 0).
##
## THE LAYERS, back to front, in the order the game draws a screen (`OriginalPresenter`):
##   Background picture, BackDecos, Walls (tiles), MidDecos, Pieces, Start (screen 6), the station (screens 0 and 11), Foes,
##   FrontDecos, AnimDecos, Currents (tiles; the game never draws them), Triggers.
## The ORDER of the children inside BackDecos / MidDecos / FrontDecos / AnimDecos / Triggers is the order of the list in
## the record: it decides the bytes, and later decos are drawn over earlier ones. Add with Ctrl+D (duplicate) or
## "Add Child Node", remove with Delete, reorder by dragging in the Scene dock.
##
## Creatures (`FoeData` records of the SECTOR file) that start on this screen are the markers of `Foes`, drawn where the game
## draws them (above the sub, below the front decorations); see `ScreenEditorFoe`.
##
## ADDING AND REMOVING creatures and pieces is adding and removing their markers, and the sector follows. The markers of `Foes` and
## `Pieces` each keep the record they stand for (`ScreenEditorFoe.record`); the sector's lists are only ever changed by
## `SectorData.add_foe` / `remove_foe` / `add_piece` / `remove_piece` (and their `insert_` forms), which refuse what would break the
## numbering the creature script and the saved games rely on and then change nothing. Two ways in, one history:
##  * "Add creature" / "Add piece" (the buttons below, or `add_creature()` / `add_piece()`) go through `SectorEdits`, whose undo
##    steps are put into the SCENE's history (`EditorUndoRedoManager`, with this node as the owner of the action);
##  * the Scene dock's Duplicate (Ctrl+D), Copy / Paste and Delete move marker nodes, and the dock's own undo step moves them back.
##    `sync_with_markers()` (run when a marker enters or leaves its layer) turns that into the sector change; a change the sector
##    refuses (the script names the creature, the data canister is not alone ...) is undone: the dock's step is taken back, the
##    marker is there again, and a toast says why.
## The other direction is the sector's `changed` signal (`_on_sector_changed`): when the Sector Inspector, or an undo, changes the
## lists, markers appear, go (parked, so that an undo brings back the same node with its unsaved edits) and get their numbers. In the
## editor the sector is the very object the Inspector shows (`share_sector`), so both always agree.
##
## Tiles are painted with Godot's own TileMap panel on `Walls` and `Currents`; see `build()` for how the cells become
## the original's one-byte-per-cell tiles and which cells can not.

## Where the playfield starts in the window; everything is positioned in window pixels.
const PLAYFIELD_ORIGIN := Vector2i(16, 32)
const WINDOW_SIZE := Vector2i(640, 400)
## The folder of sector folders the editor works in: "" is the game's own (each sector where `Catalog.sector_dir` says: a pack's `res://packs/<id>/data/sectors`,
## or the project's `res://data/sectors` for the designers' sectors); a test works in a copy.
const DATA_DIR := ""
## The files the editor draws with, in the pack that has them (`Packs.path`).
const TILESET_REL := "data/neptune_tileset.tres"
const ZONES_REL := "data/zones.tres"
const BACKGROUND_REL := Assets.BACKGROUND_REL
const DECO_FRAMES_REL := "data/sprite_frames/decos_zone%d.tres"
const FOE_FRAMES_REL := "data/sprite_frames/foes_zone%d.tres"
const PIECE_FRAMES_REL := "data/sprite_frames/pieces_frames.tres"
const SUB_FRAMES_REL := "data/sprite_frames/sub_frames.tres"
## Children shown in the status when there are many problems.
const MAX_PROBLEMS_SHOWN := 8

## The sector (0-31 are the original's; a sector made with `SectorFactory` has a higher number, up to `Catalog.MAX_SECTOR`, 255). Changing
## it (or `screen`) loads that screen; unsaved changes of the current one are dropped. A number no sector has shows "is not there".
@export_range(0, 255) var sector: int = 0:
	set(value):
		sector = clampi(value, 0, Catalog.MAX_SECTOR)
		_queue_reload()
## Screen 0-11 of the sector.
@export_range(0, 11) var screen: int = 0:
	set(value):
		screen = clampi(value, 0, 11)
		_queue_reload()
## Writes the screen (and the pieces / respawn point of the sector, if you moved them) to the .tres files. Ctrl+S does
## this too, as part of saving the scene. Not undoable: `git restore` or `reset_screens.py` bring the original back.
@export_tool_button("Save screen", "Save") var save_button: Callable = save_screen
## Loads the screen and the sector from their files again and drops every change not saved (not undoable).
@export_tool_button("Revert to saved", "Reload") var revert_button: Callable = revert
## Adds a creature to the sector and a marker for it: a copy of the selected creature (else of the first one that hurts), next to
## it. Undoable. A creature the sector can not have (it has 255) is refused with a toast.
@export_tool_button("Add creature", "Add") var add_creature_button: Callable = add_creature
## Adds a piece (a rock) to the sector and a marker for it in the middle of the playfield. Undoable.
@export_tool_button("Add piece", "Add") var add_piece_button: Callable = add_piece
## Saves the screen if needed, asks where the sub starts and what state it is in, and flies the screen in the game (`ScreenEditorPlaytest`).
@export_tool_button("Playtest screen", "Play") var playtest_button: Callable = playtest
## What the editor knows about this screen right now (read only).
@export_multiline var status: String = "":
	get:
		return _status
	set(_value):
		pass

## Folder of the sector files; a test points it at a copy.
var data_dir: String = DATA_DIR
## Everything that stops the screen from being saved, from the last `refresh()`.
var problems: Array[String] = []
## Why the screen could not be loaded ("" when it could).
var load_error: String = ""
## Load `sector_NN.tres` through the resource cache, so that this editor and the Sector Inspector (which shows the cached
## `SectorData`) change the same object and see each other's changes at once. On in the editor; a test turns it on for a copy.
## Off: the sector is a private copy, nothing else sees the changes until they are saved.
var share_sector := false
## Why the last marker change was refused, in the words of the API (the script line that names the creature ...); empty after one
## that worked. The same text is the toast.
var refusal: Array[String] = []
## The undo history of marker changes made by `add_creature` / `add_piece`: a plain `UndoRedo` a test gives. Null: the editor's
## `EditorUndoRedoManager` in the editor (`undo_history()`), else the change is simply made and can not be undone.
var history: Object = null

## The actions of the Scene dock that move marker nodes; `_undo_node_action` takes one back when the sector refused it.
const NODE_ACTIONS: Array[String] = ["Remove Node(s)", "Cut Node(s)", "Duplicate Node(s)", "Paste Node(s)"]

var _status := ""
var _sector_data: SectorData
## The rule values of the chain in use, resolved each time the data is loaded (the editor is outside a run): the screen that carries the
## respawn point is `tuning.midpoint_screen`.
var tuning: Tuning = Tuning.original()
var _loaded_screen: ScreenData
var _zone_source: int = 0
var _deco_frames: SpriteFrames
var _foe_frames: SpriteFrames
var _piece_frames: SpriteFrames
var _sub_frames: SpriteFrames
var _loading := false
var _refresh_queued := false
var _reload_queued := false
var _saved_signature := ""
var _saved_sector_signature := ""
var _stripped: Array[Node] = []
## kind ("foes", "pieces") -> {record: marker}: the markers that stand for a record of the sector.
var _bound: Dictionary = {"foes": {}, "pieces": {}}
## record -> marker: markers whose record left the sector (removed, or undone) and may come back with the same edits.
var _parked: Dictionary = {}
var _nodes_queued := false
var _from_nodes := false
var _synced := false
var _saving := false


## The result of reading the nodes back: the screen, the sector's changed pieces, creatures and respawn point, and the
## problems.
class Built extends RefCounted:
	var screen: ScreenData
	var pieces: Array[PieceData] = []
	## ALL the creatures of the sector (file order), the ones with a marker as the marker says.
	var foes: Array[FoeData] = []
	var start_pos: Vector2i = Vector2i.ZERO
	var start_frame: int = 0
	var problems: Array[String] = []


## The `ScreenEditor` above `node`, or null.
static func find_for(node: Node) -> ScreenEditor:
	var parent := node.get_parent()
	while parent != null:
		if parent is ScreenEditor:
			return parent
		parent = parent.get_parent()
	return null


func _init() -> void:
	share_sector = Engine.is_editor_hint()


func _ready() -> void:
	reload()


## The scene root leaves the tree when its tab is hidden: stop listening to the sector then (it may be the Inspector's object, which
## outlives this scene), and catch up with what changed in the meantime when the tab comes back.
func _enter_tree() -> void:
	if _sector_data != null and not _sector_data.changed.is_connected(_on_sector_changed):
		_sector_data.changed.connect(_on_sector_changed)
		_on_sector_changed()


func _exit_tree() -> void:
	if _sector_data != null and _sector_data.changed.is_connected(_on_sector_changed):
		_sector_data.changed.disconnect(_on_sector_changed)


func _validate_property(property: Dictionary) -> void:
	if property.name == &"status":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY | PROPERTY_USAGE_NO_INSTANCE_STATE


# --- saving the scene -----------------------------------------------------------------------------------------------

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			_stripped.clear()
			_strip_owners(self)
		NOTIFICATION_EDITOR_POST_SAVE:
			for node in _stripped:
				if is_instance_valid(node):
					node.owner = self
			_stripped.clear()
		NOTIFICATION_PREDELETE:
			_free_parked()


func _strip_owners(node: Node) -> void:
	for child in node.get_children():
		if child.owner == self:
			_stripped.append(child)
			child.owner = null
		_strip_owners(child)


# --- loading ----------------------------------------------------------------------------------------------------------

func _queue_reload() -> void:
	if _reload_queued or _loading or not is_node_ready():
		return
	_reload_queued = true
	reload.call_deferred()


## "Revert to saved": `reload` and also read the (shared) sector again.
func revert() -> void:
	reload(true)


## Reads the screen and the sector from their files and builds all the layers again. Unsaved changes of the markers are dropped; the
## shared sector (`share_sector`) keeps what the Sector Inspector changed, unless `discard` is true (then it is read again too).
func reload(discard := false) -> void:
	_reload_queued = false
	_loading = true
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_free_parked()
	_bound = {"foes": {}, "pieces": {}}
	load_error = _load_data(discard)
	if load_error.is_empty():
		_build_layers()
	_loading = false
	_remember_saved()
	refresh()


## Opens the playtest dialog for this screen (the "Playtest screen" button; the files are written first).
func playtest() -> void:
	ScreenEditorPlaytestDialog.open(self)


## Loads the sector and screen resources: the screen is a fresh copy, not the editor's cached one; the sector is the cached one when
## `share_sector` is on (re-read with `discard`), else a fresh copy too. "" or what went wrong.
func _load_data(discard := false) -> String:
	var sector_path := ScreenFile.sector_path(data_dir, sector)
	var screen_path := ScreenFile.screen_path(data_dir, sector, screen)
	if not FileAccess.file_exists(sector_path) or not FileAccess.file_exists(screen_path):
		var held := Catalog.data_only_holder(sector) if data_dir.is_empty() else null
		if held != null:
			return "sector %d is held by the pack '%s' as data (%s), which the editor does not write: it edits the sector files of the packs in the project" % [sector, held.id, held.root]
		return "%s is not there" % (screen_path if not FileAccess.file_exists(screen_path) else sector_path)
	var mode := ResourceLoader.CACHE_MODE_IGNORE
	if share_sector:
		mode = ResourceLoader.CACHE_MODE_REPLACE if discard else ResourceLoader.CACHE_MODE_REUSE
	tuning = Tuning.resolve()
	var loaded := ResourceLoader.load(sector_path, "", mode) as SectorData
	if loaded != _sector_data:
		if _sector_data != null and _sector_data.changed.is_connected(_on_sector_changed):
			_sector_data.changed.disconnect(_on_sector_changed)
		_sector_data = loaded
	if _sector_data != null and not _sector_data.changed.is_connected(_on_sector_changed):
		_sector_data.changed.connect(_on_sector_changed)
	_loaded_screen = ResourceLoader.load(screen_path, "", ResourceLoader.CACHE_MODE_IGNORE) as ScreenData
	if _sector_data == null or _loaded_screen == null:
		return "%s or %s could not be loaded" % [sector_path, screen_path]
	var zones := Packs.resource(ZONES_REL) as ZoneTable
	var zone := zones.zones[_sector_data.zone]
	_zone_source = zone.tile_source_id
	_deco_frames = Packs.resource(DECO_FRAMES_REL % zone.tile_zone) as SpriteFrames
	_piece_frames = Packs.resource(PIECE_FRAMES_REL) as SpriteFrames
	_sub_frames = Packs.resource(SUB_FRAMES_REL) as SpriteFrames
	_foe_frames = Packs.resource(FOE_FRAMES_REL % _sector_data.zone) as SpriteFrames
	return ""


## The `SectorData` this editor changes (the Inspector's object when `share_sector` is on); null before anything is loaded.
func sector_data() -> SectorData:
	return _sector_data


## The zone of the sector (which creature pictures it uses); `NameRegistry.NO_SCOPE` while nothing is loaded.
func zone() -> int:
	return _sector_data.zone if _sector_data != null else NameRegistry.NO_SCOPE


## The labels of the sector's creature script (`foe_script`), in file order; empty when there is no script.
func script_labels() -> PackedStringArray:
	if _sector_data == null or _sector_data.foe_script == null:
		return PackedStringArray()
	return ScreenEditorFoeJump.labels_of(_sector_data.foe_script.source)


## Opens the sector's creature script at `label` in the Foe Script screen (a creature's "Go to ... label" button). A failure
## is shown as a toast.
func show_script_label(label: String) -> void:
	if _sector_data == null:
		return
	var why := ScreenEditorFoeJump.open_in_editor(_sector_data.foe_script, label)
	if not why.is_empty():
		_toast("Can not show the label: " + why, true)


## The pictures a picture node of this kind shows.
func frames_for(item: ScreenEditorItem) -> SpriteFrames:
	if item is ScreenEditorPiece:
		return _piece_frames
	if item is ScreenEditorStart:
		return _sub_frames
	if item is ScreenEditorFoe:
		return _foe_frames
	return _deco_frames


func _build_layers() -> void:
	var background := Sprite2D.new()
	background.name = "Background"
	background.centered = false
	background.position = Vector2(PLAYFIELD_ORIGIN)
	var picture := Packs.path(BACKGROUND_REL % [sector, screen])
	if Packs.exists_at(picture):
		background.texture = Packs.file_at(picture) as Texture2D
	add_child(background)                                                            # no owner: not editable, not saved

	var tile_set := Packs.resource(TILESET_REL) as TileSet
	_own(_layer("BackDecos", _loaded_screen.bg_decos))
	_own(_tiles("Walls", tile_set, 1.0))
	_own(_layer("MidDecos", _loaded_screen.mid_decos))
	var pieces := _container("Pieces")
	for i in _sector_data.pieces.size():
		if _sector_data.pieces[i].screen == screen:
			add_piece_marker(i, pieces)
	_own(pieces)
	pieces.child_entered_tree.connect(_on_marker_moved.unbind(1))
	pieces.child_exiting_tree.connect(_on_marker_moved.unbind(1))
	if screen == tuning.midpoint_screen:
		var start := ScreenEditorStart.new()
		start.name = "Start"
		start.start_frame = _sector_data.start_frame
		start.position = Vector2(_sector_data.start_pos)
		_add_item(self, start)
		start.owner = self
	var station := ScreenEditorStation.new()
	station.name = "Station"
	add_child(station)                                                               # no owner: read only
	station.show_for(screen)
	var foes_layer := _container("Foes")
	for i in _sector_data.foes.size():
		if _sector_data.foes[i].screen == screen:
			add_foe_marker(i, foes_layer)
	_own(foes_layer)
	foes_layer.child_entered_tree.connect(_on_marker_moved.unbind(1))
	foes_layer.child_exiting_tree.connect(_on_marker_moved.unbind(1))
	_own(_layer("FrontDecos", _loaded_screen.fg_decos))
	var anims := _container("AnimDecos")
	for i in _loaded_screen.anim_decos.size():
		var node := ScreenEditorAnimDeco.from_record(_loaded_screen.anim_decos[i])
		node.name = "Anim %d" % i
		_add_item(anims, node)
	_own(anims)
	_own(_tiles("Currents", tile_set, 0.85))
	var triggers := _container("Triggers")
	for i in _loaded_screen.triggers.size():
		var node := ScreenEditorTrigger.from_record(_loaded_screen.triggers[i])
		node.name = "Trigger %d" % i
		triggers.add_child(node)
	_own(triggers)
	_paint_tiles()


## Puts a marker for creature number `index` of the sector into `layer` (the `Foes` layer when null) and returns it. This is the one
## place a creature marker is made. The marker is bound to the creature's record (`ScreenEditorFoe.record`), which is how it is
## found again after the numbers move.
func add_foe_marker(index: int, layer: Node = null) -> ScreenEditorFoe:
	if layer == null:
		layer = get_node("Foes")
	var marker := ScreenEditorFoe.from_record(_sector_data.foes[index], index)
	_add_item(layer, marker)
	_bound["foes"][marker.record] = marker
	if layer.owner == self:
		_own(marker)
	return marker


## The same for piece number `index`: the one place a piece marker is made.
func add_piece_marker(index: int, layer: Node = null) -> ScreenEditorPiece:
	if layer == null:
		layer = get_node("Pieces")
	var marker := ScreenEditorPiece.from_record(_sector_data.pieces[index], index)
	_add_item(layer, marker)
	_bound["pieces"][marker.record] = marker
	if layer.owner == self:
		_own(marker)
	return marker


# --- adding and removing creatures and pieces -----------------------------------------------------------------------------

## What differs between the two kinds of marker, so that the code below is written once: the layer, the marker's class, the
## sector's list and the calls that change it (`SectorData.insert_foe` / `remove_foe` ... each returns its problems and, when there
## are some, changes nothing), how a record is made for a marker nobody added to the sector yet, and how the marker is made.
func _kinds() -> Array[Dictionary]:
	return [
		{"name": "foes", "layer": "Foes", "type": ScreenEditorFoe, "index": &"foe_index", "list": _sector_data.foes,
				"insert": _sector_data.insert_foe, "remove": _sector_data.remove_foe, "fresh": _fresh_foe, "make": add_foe_marker},
		{"name": "pieces", "layer": "Pieces", "type": ScreenEditorPiece, "index": &"piece_index", "list": _sector_data.pieces,
				"insert": _sector_data.insert_piece, "remove": _sector_data.remove_piece, "fresh": _fresh_piece, "make": add_piece_marker},
	]


## The record for a creature marker that is not in the sector (a duplicate): a copy of the creature it was duplicated from, on the
## marker's screen and place (`SectorData.new_foe`).
func _fresh_foe(marker: ScreenEditorFoe) -> FoeData:
	var like := marker.foe_index if marker.foe_index >= 0 and marker.foe_index < _sector_data.foes.size() else -1
	return _sector_data.new_foe(marker.move_to_screen, marker.pixel_position(), like)


func _fresh_piece(marker: ScreenEditorPiece) -> PieceData:
	var piece := PieceData.new()
	piece.screen = marker.move_to_screen
	piece.pos = marker.pixel_position()
	return piece


func _on_marker_moved() -> void:
	if _loading or _nodes_queued or not is_inside_tree():
		return
	_nodes_queued = true
	sync_with_markers.call_deferred()


## The markers of `Foes` and `Pieces` changed (one entered or left its layer: Ctrl+D, Paste, Delete, or the dock's undo of those):
## make the sector say the same. A marker that is gone removes its creature or piece, a marker nobody added is a new one (a copy of
## the creature it was duplicated from), a marker that comes back with its record (undo) puts the record back at its number.
## The sector refuses what breaks the numbering (`SectorData.remove_foe` names the script line that depends on the creature): then
## nothing in the sector changes and the dock's step is taken back (`_undo_node_action`), or the nodes are put right by hand, and a
## toast says why. Public so that a test can run it without waiting for the deferred call.
func sync_with_markers() -> void:
	_nodes_queued = false
	if _loading or not load_error.is_empty() or _sector_data == null:
		return
	var refused: Array[String] = []
	_synced = false
	_forget_freed()
	_from_nodes = true
	for kind in _kinds():
		_sync_kind_with_markers(kind, refused)
	_from_nodes = false
	_renumber()
	queue_refresh()
	if not refused.is_empty():
		refusal = refused
		_toast("Not changed: " + "; ".join(refused), true)
	elif _synced:
		refusal = []


func _sync_kind_with_markers(kind: Dictionary, refused: Array[String]) -> void:
	var layer := get_node_or_null(kind["layer"] as String)
	if layer == null:
		return
	var list: Array = kind["list"]
	var bound: Dictionary = _bound[kind["name"]]
	# markers that left the layer: remove their records, the last first (the numbers of the others do not move until they are done)
	var gone: Array[Dictionary] = []
	for record: Resource in bound.keys():
		var marker: Node = bound[record]
		if marker.get_parent() != null:
			continue
		if list.has(record):
			gone.append({"record": record, "marker": marker, "at": list.find(record)})
		else:
			bound.erase(record)                                          # the sector let go of it already
	gone.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["at"] > b["at"])
	var removed: Array[Dictionary] = []
	var blocked: Array[String] = []
	for item in gone:
		var at := list.find(item["record"])
		var bad: Array[String] = (kind["remove"] as Callable).call(at)
		if bad.is_empty():
			item["at"] = at
			removed.append(item)
		else:
			blocked.append_array(bad)
	if not blocked.is_empty():
		for k in range(removed.size() - 1, -1, -1):                      # all or nothing: put back the ones that did go
			(kind["insert"] as Callable).call(removed[k]["record"], removed[k]["at"])
		refused.append_array(blocked)
		var back: Array[Node] = []
		for item in gone:
			back.append(item["marker"])
		_take_back(layer, back, [])
		return
	for item in removed:
		bound.erase(item["record"])
		_synced = true
	# markers that entered the layer without being the record's marker: a duplicate or paste is a new creature or piece, a marker
	# that comes back with its record (an undo of a deletion) puts the record back
	var dropped: Array[Node] = []
	for child in layer.get_children():
		var marker: Node = child
		if not is_instance_of(marker, kind["type"]) or bound.get(marker.get(&"record")) == marker:
			continue
		var record: Resource = marker.get(&"record")
		var bad: Array[String]
		if record != null and not list.has(record):
			bad = (kind["insert"] as Callable).call(record, clampi(marker.get(kind["index"]) as int, 0, list.size()))
		else:
			record = (kind["fresh"] as Callable).call(marker)
			bad = (kind["insert"] as Callable).call(record, -1)
		if bad.is_empty():
			marker.set(&"record", record)
			bound[record] = marker
			_synced = true
		else:
			refused.append_array(bad)
			dropped.append(marker)
	if not dropped.is_empty():
		_take_back(layer, [], dropped)


## The sector refused what the Scene dock did to markers: take the dock's step back through the history (then its redo is still
## there and the marker nodes are the ones the history holds), or, with no history that knows it, put the nodes right by hand:
## `bring_back` re-enters the layer, `drop` leaves it.
func _take_back(layer: Node, bring_back: Array[Node], drop: Array[Node]) -> void:
	if _undo_node_action():
		return
	for marker in drop:
		layer.remove_child(marker)
		if undo_history() == null:
			marker.queue_free()
	for marker in bring_back:
		layer.add_child(marker, true)
		marker.owner = self


## Takes back the last step of the undo history if it is one the Scene dock made with marker nodes (`NODE_ACTIONS`). False when
## there is no history to ask or the last step is something else.
func _undo_node_action() -> bool:
	var plain: UndoRedo = null
	var manager := undo_history()
	if manager is UndoRedo:
		plain = manager
	elif manager != null:
		plain = manager.call("get_history_undo_redo", manager.call("get_object_history_id", self))
	if plain == null:
		return false
	var action := plain.get_current_action_name()
	for prefix in NODE_ACTIONS:
		if action.begins_with(prefix):
			return plain.undo()
	return false


## The undo history marker actions go into: the one given (`history`), else the editor's `EditorUndoRedoManager`. Null outside the
## editor with none given.
func undo_history() -> Object:
	if history != null:
		return history
	if Engine.is_editor_hint():
		return EditorInterface.get_editor_undo_redo()
	return null


## The sector changed (an add or remove here, an undo, the Sector Inspector ...): give every creature and piece of this screen its
## marker, and let the markers of the ones that are gone go. A marker that goes is parked, not freed, so that an undo brings back
## the same node with what was edited on it. Nothing happens for a change this editor is making itself (`_from_nodes`) or while
## the files are written.
func _on_sector_changed() -> void:
	if _from_nodes or _saving or _loading or not load_error.is_empty() or _sector_data == null:
		return
	_forget_freed()
	for kind in _kinds():
		var layer := get_node_or_null(kind["layer"] as String)
		if layer == null:
			continue
		var list: Array = kind["list"]
		var bound: Dictionary = _bound[kind["name"]]
		for record: Resource in bound.keys():
			if not list.has(record):
				var marker: Node = bound[record]
				bound.erase(record)
				if marker.get_parent() != null:
					marker.get_parent().remove_child(marker)
				_parked[record] = marker
		for i in list.size():
			var record: Resource = list[i]
			if bound.has(record) or int(record.get(&"screen")) != screen:
				continue
			var parked: Node = _parked.get(record)
			if parked != null:
				_parked.erase(record)
				layer.add_child(parked, true)
				parked.owner = self
				bound[record] = parked
			else:
				(kind["make"] as Callable).call(i, layer)
	_renumber()
	queue_refresh()


## Every marker gets the number, the name and (a piece) the picture its record has now, and the layers list them in that order.
func _renumber() -> void:
	for kind in _kinds():
		var layer := get_node_or_null(kind["layer"] as String)
		if layer == null:
			continue
		var list: Array = kind["list"]
		var order: Array[Dictionary] = []
		for record: Resource in (_bound[kind["name"]] as Dictionary).keys():
			var marker: Node2D = _bound[kind["name"]][record]
			if marker.get_parent() == layer and list.has(record):
				order.append({"at": list.find(record), "marker": marker, "record": record})
		order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["at"] < b["at"])
		var renamed: Array[Dictionary] = []
		for item in order:
			var marker := item["marker"] as Node2D
			marker.set(kind["index"], item["at"])
			var wanted: String
			var piece := marker as ScreenEditorPiece
			if piece != null:
				piece.is_canister = (item["record"] as PieceData).is_canister
				piece.show_picture()
				wanted = ScreenEditorPiece.marker_name(piece.is_canister, item["at"])
			else:
				wanted = ScreenEditorFoe.marker_name(item["at"])
			marker.queue_redraw()
			if marker.name != wanted:
				renamed.append({"marker": marker, "name": wanted})
		for item in renamed:                                             # out of the way first: two markers may swap names
			(item["marker"] as Node).name = "Moving %d" % (item["marker"] as Node).get_instance_id()
		for item in renamed:
			(item["marker"] as Node).name = item["name"]
		for i in order.size():
			if layer.get_child(i) != order[i]["marker"]:
				layer.move_child(order[i]["marker"], i)


## A marker that was freed (not just removed from its layer) can not come back: forget it. Its creature or piece stays in the sector
## and has no marker then, which `build()` reports.
func _forget_freed() -> void:
	for bound: Dictionary in _bound.values():
		for record: Resource in bound.keys():
			if not is_instance_valid(bound[record]):
				bound.erase(record)


func _free_parked() -> void:
	for marker: Node in _parked.values():
		if is_instance_valid(marker) and marker.get_parent() == null:
			marker.free()
	_parked.clear()


## Adds a creature to the sector, on this screen at `pos` (window pixels; default: beside the selected creature, else the middle of
## the playfield) as a copy of creature `like` (default: the selected creature, else the first one that hurts), and shows its
## marker. One undo step. True when it was added; else a toast says why (`SectorData.add_foe` refuses a 128th creature ...).
func add_creature(pos := Vector2i(-1, -1), like := -1) -> bool:
	if _sector_data == null or not load_error.is_empty():
		return false
	refusal = []
	var chosen := _selected(ScreenEditorFoe) as ScreenEditorFoe
	if like < 0 and chosen != null:
		like = chosen.foe_index
	var edits := SectorEdits.new(_sector_data, undo_history(), self)
	if not edits.add_foe(screen, _new_marker_position(pos, chosen), like):
		refusal = edits.refusal
		_toast("Can not add a creature: " + "; ".join(edits.refusal), true)
		return false
	_select_last(&"foes")
	return true


## Adds a piece (a rock) to the sector, on this screen at `pos` (default: beside the selected piece, else the middle of the playfield),
## after the last piece, and shows its marker. One undo step. True when it was added; else a toast says why.
func add_piece(pos := Vector2i(-1, -1)) -> bool:
	if _sector_data == null or not load_error.is_empty():
		return false
	refusal = []
	var edits := SectorEdits.new(_sector_data, undo_history(), self)
	if not edits.add_piece(screen, _new_marker_position(pos, _selected(ScreenEditorPiece) as ScreenEditorItem)):
		refusal = edits.refusal
		_toast("Can not add a piece: " + "; ".join(edits.refusal), true)
		return false
	_select_last(&"pieces")
	return true


## `pos` if it is one (not negative), else a little beside `beside` if there is one, else the middle of the playfield; always on the
## grid the records need (even numbers).
func _new_marker_position(pos: Vector2i, beside: ScreenEditorItem) -> Vector2i:
	if pos.x < 0 or pos.y < 0:
		pos = beside.pixel_position() + Vector2i(16, 16) if beside != null else PLAYFIELD_ORIGIN + TileGrid.PLAYFIELD_SIZE / 2
	return Vector2i(pos.x / 2 * 2, pos.y / 2 * 2)


## The first selected node of the Scene dock that is a `kind` marker, or null.
func _selected(kind: Script) -> Node:
	if not Engine.is_editor_hint():
		return null
	for node in EditorInterface.get_selection().get_selected_nodes():
		if is_instance_of(node, kind) and is_ancestor_of(node):
			return node
	return null


## Selects the marker of the last record of the list `kind` (what was just added), so that it can be dragged at once.
func _select_last(kind: String) -> void:
	if not Engine.is_editor_hint():
		return
	var list: Array = _sector_data.get(kind)
	var marker: Node = (_bound[kind] as Dictionary).get(list.back()) if not list.is_empty() else null
	if marker != null:
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(marker)


func _container(layer_name: String) -> Node2D:
	var node := Node2D.new()
	node.name = layer_name
	add_child(node)
	return node


func _layer(layer_name: String, records: Array) -> Node2D:
	var node := _container(layer_name)
	for i in records.size():
		var deco := ScreenEditorDeco.from_record(records[i])
		deco.name = "Deco %d" % i
		_add_item(node, deco)
	return node


func _tiles(layer_name: String, tile_set: TileSet, alpha: float) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tile_set
	layer.position = Vector2(PLAYFIELD_ORIGIN)
	layer.collision_enabled = false                       # the editor needs the pictures only, not the physics bodies
	layer.modulate = Color(1, 1, 1, alpha)
	add_child(layer)
	layer.changed.connect(queue_refresh)                  # every cell painted or erased
	return layer


func _add_item(parent: Node, item: ScreenEditorItem) -> void:
	parent.add_child(item)
	item.adopt(self)


## Makes `node` and everything below it selectable in the Scene dock (owner = this scene's root).
func _own(node: Node) -> void:
	node.owner = self
	for child in node.get_children():
		_own(child)


## Fills Walls and Currents from the tile bytes of the loaded screen. A `0x40` wall (picture 0, no art) is shown with the
## hatched editor-only tile (source 6), every other wall with the zone's own atlas, a current with source 5.
func _paint_tiles() -> void:
	var walls := get_node("Walls") as TileMapLayer
	var currents := get_node("Currents") as TileMapLayer
	for i in ScreenData.TILE_BYTES:
		var tile := TileCodec.decode(_loaded_screen.tiles[i])
		var cell := Vector2i(i % ScreenData.TILE_COLUMNS, i / ScreenData.TILE_COLUMNS)
		match tile.kind:
			TileCodec.Kind.SOLID:
				if tile.picture == 0:
					walls.set_cell(cell, TileCodec.INVISIBLE_WALL_SOURCE, Vector2i.ZERO)
				else:
					walls.set_cell(cell, _zone_source, tile.atlas_coords)
			TileCodec.Kind.CURRENT:
				currents.set_cell(cell, TileCodec.CURRENTS_SOURCE, tile.atlas_coords)


# --- reading the nodes back -------------------------------------------------------------------------------------------

## The screen, pieces and respawn point the nodes stand for now, with every problem that stops them being stored. The
## ScreenData is built even when there are problems (the cells that can not be stored stay empty), so look at
## `problems` before using it.
func build() -> Built:
	var built := Built.new()
	built.screen = ScreenData.new()
	if _loaded_screen == null or _sector_data == null:
		return built
	built.screen.original_sector = _loaded_screen.original_sector
	built.screen.original_screen = _loaded_screen.original_screen
	built.screen.stale_offset = _loaded_screen.stale_offset
	built.screen.stale_bytes = _loaded_screen.stale_bytes
	built.screen.tiles = _encode_tiles(built.problems)
	built.screen.bg_decos.assign(_collect(built.problems, "BackDecos", ScreenEditorDeco))
	built.screen.mid_decos.assign(_collect(built.problems, "MidDecos", ScreenEditorDeco))
	built.screen.fg_decos.assign(_collect(built.problems, "FrontDecos", ScreenEditorDeco))
	built.screen.anim_decos.assign(_collect(built.problems, "AnimDecos", ScreenEditorAnimDeco))
	built.screen.triggers.assign(_collect(built.problems, "Triggers", ScreenEditorTrigger))
	for message in built.screen.validate():
		built.problems.append(message)
	_collect_sector(built)
	_collect_foes(built)
	return built


## The records of the children of layer `layer_name`, in order. A child of another kind is a problem.
func _collect(found: Array[String], layer_name: String, kind: Script) -> Array:
	var records: Array = []
	var layer := get_node_or_null(layer_name)
	if layer == null:
		found.append("the layer %s is missing: use Revert to saved to build the screen again" % layer_name)
		return records
	for child in layer.get_children():
		if is_instance_of(child, kind):
			records.append(child.to_record())
		else:
			found.append("%s/%s is not a %s: only those are stored (move it out of this layer or delete it)" % [layer_name, child.name, kind.get_global_name()])
	return records


## The sector's pieces with the moved ones applied, and the respawn point.
func _collect_sector(built: Built) -> void:
	for piece in _sector_data.pieces:
		var copy := PieceData.new()
		copy.screen = piece.screen
		copy.pos = piece.pos
		copy.is_canister = piece.is_canister
		built.pieces.append(copy)
	built.start_pos = _sector_data.start_pos
	built.start_frame = _sector_data.start_frame
	var seen: Dictionary = {}
	var pieces_layer := get_node_or_null("Pieces")
	if pieces_layer == null:
		built.problems.append("the layer Pieces is missing: use Revert to saved to build the screen again")
	else:
		for child in pieces_layer.get_children():
			var piece := child as ScreenEditorPiece
			if piece == null:
				built.problems.append("Pieces/%s is not a piece marker: only those are stored" % child.name)
			elif piece.piece_index < 0 or piece.piece_index >= built.pieces.size():
				built.problems.append("Pieces/%s: the sector has no piece %d (it has %d)" % [child.name, piece.piece_index, built.pieces.size()])
			elif seen.has(piece.piece_index):
				built.problems.append("Pieces/%s: piece %d appears twice (a duplicate becomes a new piece as soon as the sector has accepted it)" % [child.name, piece.piece_index])
			else:
				seen[piece.piece_index] = true
				built.pieces[piece.piece_index].screen = piece.move_to_screen
				built.pieces[piece.piece_index].pos = piece.pixel_position()
				for message in ScreenEditorPiece.problems_of(piece.pixel_position(), "piece %d" % piece.piece_index):
					built.problems.append(message)
	for i in _sector_data.pieces.size():
		if _sector_data.pieces[i].screen == screen and not seen.has(i):
			built.problems.append("piece %d has no marker on this screen: delete a piece with its marker, or set 'Move To Screen' to move it away" % i)
	if screen == tuning.midpoint_screen:
		var start := get_node_or_null("Start") as ScreenEditorStart
		if start == null:
			built.problems.append("the respawn point (node Start) was removed; the sector needs it")
		else:
			built.start_pos = start.pixel_position()
			built.start_frame = start.start_frame
			for message in ScreenEditorPiece.problems_of(built.start_pos, "respawn point"):
				built.problems.append(message)


## The sector's creatures with the markers' values applied. A marker stands for the creature of its number; a creature of this
## screen without a marker, a number the sector does not have, or two markers for one creature are problems. They exist only until
## `sync_with_markers` has made the sector say the same as the markers (a deleted marker removes its creature, a duplicate adds one),
## or put the markers right.
func _collect_foes(built: Built) -> void:
	for foe in _sector_data.foes:
		built.foes.append(foe.duplicate() as FoeData)
	var labels := script_labels()
	var seen: Dictionary = {}
	var layer := get_node_or_null("Foes")
	if layer == null:
		built.problems.append("the layer Foes is missing: use Revert to saved to build the screen again")
		return
	for child in layer.get_children():
		var marker := child as ScreenEditorFoe
		if marker == null:
			built.problems.append("Foes/%s is not a creature marker: only those are stored" % child.name)
		elif marker.foe_index < 0 or marker.foe_index >= built.foes.size():
			built.problems.append("Foes/%s: the sector has no creature %d (it has %d)" % [child.name, marker.foe_index, built.foes.size()])
		elif seen.has(marker.foe_index):
			built.problems.append("Foes/%s: creature %d appears twice (a duplicate becomes a new creature as soon as the sector has accepted it)" % [child.name, marker.foe_index])
		else:
			seen[marker.foe_index] = true
			built.foes[marker.foe_index] = marker.to_record()
			for message in marker.problems(labels):
				built.problems.append(message)
	for i in _sector_data.foes.size():
		if _sector_data.foes[i].screen == screen and not seen.has(i):
			built.problems.append("creature %d has no marker on this screen: delete a creature with its marker, or set 'Move To Screen' to send it away" % i)


## The 684 tile bytes from the Walls and Currents layers. One byte holds a wall OR a current, so the layers must not
## both have the same cell; only the sector's own zone atlas (and the invisible-wall tile) can be a wall. Anything else
## is reported in `found` and left empty, never converted behind your back.
func _encode_tiles(found: Array[String]) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(ScreenData.TILE_BYTES)
	var filled: Dictionary = {}
	var tile_problems: Array[String] = []
	var walls := get_node_or_null("Walls") as TileMapLayer
	var currents := get_node_or_null("Currents") as TileMapLayer
	if walls == null or currents == null:
		found.append("the layer Walls or Currents is missing: use Revert to saved to build the screen again")
		return bytes
	for layer: TileMapLayer in [walls, currents]:
		var is_walls := layer == walls
		for cell in layer.get_used_cells():
			var where := "%s cell (%d, %d)" % [layer.name, cell.x, cell.y]
			var source := layer.get_cell_source_id(cell)
			var coords := layer.get_cell_atlas_coords(cell)
			if cell.x < 0 or cell.x >= ScreenData.TILE_COLUMNS or cell.y < 0 or cell.y >= ScreenData.TILE_ROWS:
				tile_problems.append("%s is outside the %d x %d screen: erase it" % [where, ScreenData.TILE_COLUMNS, ScreenData.TILE_ROWS])
			elif layer.get_cell_alternative_tile(cell) != 0:
				tile_problems.append("%s uses an alternative tile (flipped or rotated): the original has none" % where)
			elif is_walls and source == TileCodec.CURRENTS_SOURCE:
				tile_problems.append("%s is a current arrow: put currents on the Currents layer" % where)
			elif not is_walls and source != TileCodec.CURRENTS_SOURCE:
				tile_problems.append("%s is a wall tile (tileset source %d): put walls on the Walls layer" % [where, source])
			elif is_walls and source >= 0 and source < TileCodec.ZONE_SOURCE_COUNT and source != _zone_source:
				tile_problems.append("%s is from the atlas of another zone (source %d): this sector uses source %d. Paint it again with that atlas" % [where, source, _zone_source])
			else:
				var byte := TileCodec.byte_from_cell(source, coords)
				var index := cell.y * ScreenData.TILE_COLUMNS + cell.x
				if byte < 0:
					tile_problems.append("%s: %s" % [where, TileCodec.cell_problem(source, coords)])
				elif filled.has(index):
					tile_problems.append("cell (%d, %d) has a wall AND a current: the original stores one byte per cell, so only one fits. Erase one of them" % [cell.x, cell.y])
				else:
					bytes[index] = byte
					filled[index] = true
	for i in mini(tile_problems.size(), MAX_PROBLEMS_SHOWN):
		found.append(tile_problems[i])
	if tile_problems.size() > MAX_PROBLEMS_SHOWN:
		found.append("... and %d more tile problems like these" % (tile_problems.size() - MAX_PROBLEMS_SHOWN))
	return bytes


## Text that changes when anything the files would store changes: the screen file text, the pieces and the respawn point.
func _signature(built: Built) -> String:
	return ScreenFile.screen_text(built.screen) + "\n" + _sector_signature(built)


## The same for the sector file's part: the pieces (their number too), the respawn point and the creatures.
func _sector_signature(built: Built) -> String:
	var parts: Array[String] = []
	for piece in built.pieces:
		parts.append("%d %s %s" % [piece.screen, piece.pos, piece.is_canister])
	parts.append("%s %d" % [built.start_pos, built.start_frame])
	for foe in built.foes:
		parts.append(str(ScreenFile.FOE_FIELDS.map(func(name: String) -> Variant: return foe.get(name))))
	return "\n".join(parts)


## What the nodes say now is what the files hold: the point later changes are measured from.
func _remember_saved() -> void:
	if load_error.is_empty():
		var built := build()
		_saved_signature = _signature(built)
		_saved_sector_signature = _sector_signature(built)
	else:
		_saved_signature = ""
		_saved_sector_signature = ""


## Do the nodes differ from what was last loaded or saved? A screen that has not been loaded yet is never dirty: a scene in a
## background tab of the editor (restored with the session) is not in the tree, so `_ready` and `reload()` have not run, and
## `build()` of that is an EMPTY screen, which would otherwise look like a change and be written over the real file.
func is_dirty() -> bool:
	return load_error.is_empty() and _loaded_screen != null and _signature(build()) != _saved_signature


# --- status ---------------------------------------------------------------------------------------------------------------

func queue_refresh() -> void:
	if _loading or _refresh_queued or not is_inside_tree():
		return
	_refresh_queued = true
	refresh.call_deferred()


## Recomputes the problems and the status text and tells the editor (warnings in the Scene dock, the Inspector, the view).
func refresh() -> void:
	_refresh_queued = false
	if not load_error.is_empty():
		problems = [load_error]
		_status = "Sector %d, screen %d: %s" % [sector, screen, load_error]
	else:
		var built := build()
		problems = built.problems
		_status = _status_text(built)
	update_configuration_warnings()
	queue_redraw()
	notify_property_list_changed()


func _status_text(built: Built) -> String:
	var lines: Array[String] = []
	var head := "Sector %d, screen %d (zone atlas %d)" % [sector, screen, _zone_source]
	lines.append(head + (" - unsaved changes" if _signature(built) != _saved_signature else " - nothing to save"))
	if not built.problems.is_empty():
		lines.append("CAN NOT BE SAVED: %d problem(s). First: %s" % [built.problems.size(), built.problems[0]])
	else:
		var original := ScreenFile.original_record(sector, screen)
		var wanted := ScreenFile.original_sha256(sector, screen)
		if not original.is_empty():
			var difference := ScreenData.first_difference(original, built.screen.encode())
			lines.append("same as the original" if difference.is_empty() else "differs from the original: " + difference)
		elif not Catalog.is_original_sector(sector):
			lines.append("sector %d is your own: there is no original to compare with" % sector)
		elif wanted.is_empty():
			lines.append("no original to compare with (tests/fixtures/screens.json is missing)")
		elif FixtureHash.sha256_hex(built.screen.encode()) == wanted:
			lines.append("same as the original")
		else:
			lines.append("differs from the original (run tools/import/import_all.py on your copy of the game to see where)")
	lines.append("record: %d / %d bytes" % [built.screen.used_bytes(), ScreenData.RECORD_SIZE])
	if _sector_changed(built):
		lines.append("also changes sector_%02d.tres (pieces, creatures or the respawn point)" % sector)
	return "\n".join(lines)


## Would the sector file change? The pieces (their number too), the respawn point or the creatures differ from when the files were
## last loaded or written.
func _sector_changed(built: Built) -> bool:
	return _sector_signature(built) != _saved_sector_signature


## A `SectorData` that is the sector as it is now with the markers' values applied, for `ScreenFile.sector_patch` to compare with the
## file: the same lists as the sector (so a creature or piece added or removed is in or out), the markers' positions and fields.
func _wanted_sector(built: Built) -> SectorData:
	var wanted := _sector_data.duplicate() as SectorData
	wanted.pieces = built.pieces
	wanted.foes = built.foes
	wanted.start_pos = built.start_pos
	wanted.start_frame = built.start_frame
	return wanted


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(WINDOW_SIZE)), Color(1, 1, 1, 0.25), false)
	draw_rect(Rect2(Vector2(PLAYFIELD_ORIGIN), Vector2(TileGrid.PLAYFIELD_SIZE)), Color(0.3, 0.8, 1.0, 0.8), false)
	var lines := _status.split("\n")
	var color := Color(1, 0.45, 0.45) if not problems.is_empty() else Color(0.85, 0.95, 0.85)
	for i in lines.size():
		draw_string(ThemeDB.fallback_font, Vector2(0, -8 - (lines.size() - 1 - i) * 15), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)


func _get_configuration_warnings() -> PackedStringArray:
	var found := PackedStringArray()
	for message in problems:
		found.append(message)
	if position != Vector2.ZERO:
		found.append("Keep this node at (0, 0): positions in the screen file are window pixels counted from there.")
	return found


# --- saving the screen -----------------------------------------------------------------------------------------------------

## Writes `screen_MM.tres` and, when you moved or added or removed a piece or a creature, or moved the respawn point, those lines of
## `sector_NN.tres`. Nothing is written while there are problems (the status says which), and a file whose text would not change is
## not touched (so adding a creature and removing it again leaves both files byte for byte as they were).
## Returns true when the files on disk match the nodes afterwards.
func save_screen() -> bool:
	if not load_error.is_empty() or _loaded_screen == null or _sector_data == null:
		return false
	var built := build()
	if not built.problems.is_empty():
		refresh()
		_toast("Screen %d of sector %d was NOT saved: %s" % [screen, sector, built.problems[0]], true)
		return false
	var written: Array[String] = []
	var screen_path := ScreenFile.screen_path(data_dir, sector, screen)
	var error := _write_if_changed(screen_path, ScreenFile.screen_text(built.screen), written)
	if error.is_empty() and _sector_changed(built):
		# the file as it is on disk against the sector with the markers applied: `sector_patch` changes the lines that differ and
		# writes a list whole when its length differs (a creature or piece was added or removed)
		var sector_path := ScreenFile.sector_path(data_dir, sector)
		var disk := ResourceLoader.load(sector_path, "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData
		if disk == null:
			error = "%s could not be loaded" % sector_path
		else:
			var patched := ScreenFile.sector_patch(FileAccess.get_file_as_string(sector_path), disk, _wanted_sector(built))
			error = patched.error
			if error.is_empty():
				error = _write_if_changed(sector_path, patched.text, written)
	if not error.is_empty():
		_toast("Screen %d of sector %d was NOT saved: %s" % [screen, sector, error], true)
		return false
	_saving = true                                 # the sector is read again below; its `changed` is no news for the markers
	_after_write(written)
	load_error = _load_data()                      # the files are the truth again
	_bind_markers()
	_saving = false
	_remember_saved()
	if _sector_data != null:
		_sector_data.emit_changed()                # tells the Sector Inspector, which shows the same object
	refresh()
	if not written.is_empty():
		_toast("Saved %s" % ", ".join(written.map(func(p: String) -> String: return p.get_file())), false)
	return true


## After the files were read again: the markers stand for the new record objects (the lists were loaded anew, with the same count
## and order as what was written), and the markers that were parked belong to a sector that no longer exists.
func _bind_markers() -> void:
	_free_parked()
	if _sector_data == null:
		return
	for kind in _kinds():
		var list: Array = kind["list"]
		var bound: Dictionary = _bound[kind["name"]]
		var markers: Array = bound.values()
		bound.clear()
		for marker: Node in markers:
			var at: int = marker.get(kind["index"])
			if at >= 0 and at < list.size():
				marker.set(&"record", list[at])
				bound[list[at]] = marker


func _write_if_changed(path: String, text: String, written: Array[String]) -> String:
	if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == text:
		return ""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "%s can not be written (error %d)" % [path, FileAccess.get_open_error()]
	file.store_string(text)
	file.close()
	written.append(path)
	return ""


## Tells the editor that files changed (its file system dock) and refreshes copies of them it already holds.
func _after_write(paths: Array[String]) -> void:
	for path in paths:
		if ResourceLoader.has_cached(path):
			ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().update_file(path)


func _toast(message: String, is_problem: bool) -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_editor_toaster().push_toast(message, EditorToaster.SEVERITY_WARNING if is_problem else EditorToaster.SEVERITY_INFO)
	elif is_problem:
		push_warning(message)
