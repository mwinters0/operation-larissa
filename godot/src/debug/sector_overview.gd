@tool
class_name SectorOverview
extends Control
## The sector overview: all 12 screens of a sector on one map, laid out by the neighbour tables, with the pieces, creatures, triggers,
## currents, the start and the end station on top, and overlays for where the sub can get to and where the creatures go.
## A tool scene (`sector_overview.tscn`) and, through the `sector_overview` addon, a main
## screen of the Godot editor. The core is `SectorLayout` (where each screen goes), `CreaturePaths` (where the creatures go),
## `SectorOverviewModel` (the facts) and `SectorOverviewCanvas` (the picture); this node is the toolbar, the scroll area and the
## text beside the map.
##
## Teaches: building a tool's UI in code from a table (the check boxes of the overlays), `ScrollContainer` around a custom-drawn
## `Control`, `HSplitContainer`, and a control that is useful both as a scene of its own and as a panel of the editor: it does not
## know which, it only EMITS what the user asked for (`screen_open_requested`, `foe_script_requested`) and a host answers. Alone it
## answers a request to open a screen by zooming in on it.
##
## The "Checks" box runs the playability checks of the sector (`SectorChecks`, the same as the Project > Tools > Check sector window) and marks
## every finding on the map where it is (`SectorOverviewChecks`): red errors, amber warnings, grey-dashed findings that are how the ORIGINAL
## is (allowed, with the reason in the tooltip and the text), and a count on the corner of each screen. A list beside the map has every
## finding; choosing one selects its object and scrolls the map to it. The search runs on a worker thread (`SectorCheckTask`) and only
## with the "Reachable" box on, since the search takes seconds; without it the reach findings are missing, and the status line says so.
## ("Reachable" is the overview's own single search, the checks need several modes and the respawn search, so the two do not share a result.)
## The "Changed" box frames the screens that differ from the original (`SectorChanges`).
##
## In the map: click an object (a piece, a creature, a trigger, the start, the end station) to read about it; click a screen to
## select it, double-click it (or press "Open screen") to open it. Ctrl + wheel zooms.
##
## Keys (as a tool scene):  [ and ]  previous / next sector     F  fit the map into the window
## Command line (after `--`):  godot --path godot res://src/debug/sector_overview.tscn -- --sector=7 --reach --paths --snapshot=/where/shot.png
## Options: `--sector=N`  `--screen=N` (select it)  `--zoom=0.3`  `--reach`  `--paths`  `--currents`  `--checks`  `--changed`  `--ticks=N` (length of the traces)
## `--sub=0|1|2` (where the sub is for the traces), `--mode=0|1|2` (reachability: orthogonal, diagonal, fast).

## The host should open screen `screen` of sector `sector` (the screen editor, in the Godot editor).
signal screen_open_requested(sector: int, screen: int)
## The host should show the creature script of `sector` (creature number `foe_index`, whose labels are `labels`).
signal foe_script_requested(sector: int, foe_index: int, labels: PackedStringArray)
## The checks (and the comparison with the original) of the shown sector are in and on the map.
signal checks_finished(result: SectorOverviewChecks)

## The zoom `reveal` raises a too small map to.
const REVEAL_ZOOM := 0.35

var sector_index: int = 0
var model: SectorOverviewModel

var _canvas: SectorOverviewCanvas
var _scroll: ScrollContainer
var _info: RichTextLabel
var _status: Label
var _title: Label
var _sector_box: SpinBox
var _zoom_slider: HSlider
var _open_button: Button
var _script_button: Button
var _selected_screen := -1
var _selected_object: Dictionary = {}
var _fit_pending := true
## Somebody chose a zoom (the slider, the wheel, the command line): a new sector keeps it instead of fitting the map.
var _zoom_chosen := false
var _overlay_boxes: Dictionary = {}          # overlay -> its CheckBox
## The findings and differences placed on the map, or null; and the background task that makes the next ones.
var _checks: SectorOverviewChecks
var _checks_task: SectorCheckTask
var _findings_box: VBoxContainer
var _findings_label: Label
var _findings_list: ItemList
var _listed: Array[CheckFinding] = []           # the finding of each row of the list
## Settings read from the command line, applied once the map exists (`_save_snapshot_and_quit`).
var _pending_settings: Dictionary = {}
## The shown sector and its creature script: their `changed` builds the model again (`_watch`).
var _watched: Array[Resource] = []
var _rebuild_pending := false


func _ready() -> void:
	if not Engine.is_editor_hint() and get_parent() == get_tree().root:
		# run as a scene of its own: use the window's real pixels instead of the game's 640 x 400 that is scaled up
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_build_ui()
	visibility_changed.connect(update_sector_range)
	var snapshot := _apply_command_line() if not Engine.is_editor_hint() else ""
	load_sector(sector_index)
	if not snapshot.is_empty():
		await _save_snapshot_and_quit(snapshot)


## The scroll area got its size (or a new one): fit the map into it, unless somebody chose a zoom.
func _on_scroll_resized() -> void:
	if _fit_pending:
		_fit()


func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_BRACKETLEFT:
			load_sector(Catalog.step_sector(sector_index, -1))
		KEY_BRACKETRIGHT:
			load_sector(Catalog.step_sector(sector_index, 1))
		KEY_F:
			_fit()


# --- the sector -----------------------------------------------------------------------------------------------------------

## The number box goes up to the last sector there is NOW, so a sector made after the panel was built (Project > Tools > "New sector...") can be
## typed in. Called when the panel is shown again, when the box is clicked and whenever a sector is chosen.
func update_sector_range() -> void:
	if _sector_box != null:
		_sector_box.max_value = maxi(Catalog.last_sector(), 0)


## Shows sector `index` (the closest one that exists, when there is none of that number) and forgets what was selected.
func load_sector(index: int) -> void:
	update_sector_range()
	if Catalog.sector_count() == 0:                    # nothing to show until a pack with sectors is in use (README, "Packs")
		return
	show_sector(Catalog.sector(Catalog.nearest_sector(index)))


## Shows `sector` (a sector of the catalog, or a copy in memory that a tool or a test made) and forgets what was selected.
func show_sector(sector: SectorData) -> void:
	_watch(sector)
	sector_index = sector.index
	var settings := model
	model = SectorOverviewModel.new(sector)
	if settings != null:                                          # the settings of the traces and of the search stay
		model.trace_ticks = settings.trace_ticks
		model.sub_preset = settings.sub_preset
		model.reach_mode = settings.reach_mode
	_canvas.model = model
	_sector_box.set_value_no_signal(sector_index)
	var zone := Catalog.zone(model.sector.zone)
	_title.text = "Sector %d (%s), zone: %s, %d pieces, %d creatures" % [
			sector_index, Catalog.campaign_name_of_sector(sector_index), zone.title, model.sector.pieces.size(), model.sector.foes.size()]
	_checks = null
	_checks_task = null
	_fill_findings()
	_select(-1, {})
	_fit_pending = not _zoom_chosen
	if _fit_pending:
		_fit.call_deferred()
	_refresh_checks()
	_update_status()


## The model is derived from the sector: a change of the sector or of its creature script (the screen editor's save, the Sector
## Inspector, the Foe Script editor; a file read again in place) builds it again, once per frame however many arrive, as choosing the
## sector does, and the screen that was selected stays selected.
func _watch(sector: SectorData) -> void:
	for source in _watched:
		if is_instance_valid(source) and source.changed.is_connected(_on_sector_changed):
			source.changed.disconnect(_on_sector_changed)
	_watched.clear()
	for source: Resource in [sector, sector.foe_script]:
		if source != null:
			source.changed.connect(_on_sector_changed)
			_watched.append(source)


func _on_sector_changed() -> void:
	if not _rebuild_pending:
		_rebuild_pending = true
		_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_pending = false
	if model == null:
		return
	var screen := _selected_screen
	show_sector(model.sector)
	if screen >= 0:
		select_screen(screen)


## Selects `screen` (and shows the text about it).
func select_screen(screen: int) -> void:
	_select(screen, {})
	_canvas.selected_screen = screen


## Asks the host to open the selected (or the given) screen. Without a host that listens, the map zooms in on it instead.
func open_screen(screen: int = -1) -> void:
	if screen < 0:
		screen = _selected_screen
	if screen < 0:
		return
	if not screen_open_requested.get_connections().is_empty():
		screen_open_requested.emit(sector_index, screen)
		return
	zoom_to_screen(screen)


## The map as big as the scroll area allows the screen to be, and scrolled to it. (What the tool scene does to "open" a screen.)
func zoom_to_screen(screen: int) -> void:
	_fit_pending = false
	_set_zoom(minf(SectorOverviewCanvas.MAX_ZOOM, maxf(0.3, (_scroll.size.x - 2.0 * SectorOverviewCanvas.MARGIN) / float(TileGrid.PLAYFIELD_SIZE.x))))
	await get_tree().process_frame
	var rect := _canvas.screen_rect(screen)
	_scroll.scroll_horizontal = int(rect.position.x - SectorOverviewCanvas.MARGIN)
	_scroll.scroll_vertical = int(rect.position.y - SectorOverviewCanvas.MARGIN - SectorOverviewCanvas.TITLE_HEIGHT)


func canvas() -> SectorOverviewCanvas:
	return _canvas


## What the checks found for the shown sector, or null (the overlays are off, or the task is still running: `checking()`).
func checks_result() -> SectorOverviewChecks:
	return _checks


## Is the background check still running?
func checking() -> bool:
	return _checks_task != null and _checks_task.running


## Fits the whole map into the scroll area.
func _fit() -> void:
	if _scroll == null or model == null:
		return
	var available := _scroll.size - Vector2(4, 4)
	if available.x < 50.0 or available.y < 50.0:
		return
	_set_zoom(_canvas.fit_zoom(available))


func _set_zoom(value: float) -> void:
	_canvas.zoom = value
	_zoom_slider.set_value_no_signal(_canvas.zoom)


# --- what the clicks mean -----------------------------------------------------------------------------------------------------

func _on_screen_selected(screen: int) -> void:
	_select(screen, {})


func _on_object_picked(object: Dictionary) -> void:
	if object.is_empty():
		return
	_select(object["screen"], object)


func _select(screen: int, object: Dictionary) -> void:
	_selected_screen = screen
	_selected_object = object
	_open_button.disabled = screen < 0
	_open_button.text = "Open screen %d" % screen if screen >= 0 else "Open screen"
	_script_button.visible = not object.is_empty() and object["kind"] == SectorOverviewModel.Kind.CREATURE
	if screen < 0 or model == null:
		_info.text = "Click an object to read about it, a screen to select it; double-click a screen to open it."
		return
	var text := ""
	if object.is_empty():
		text = "[b]Screen %d[/b]\n%s" % [screen, model.screen_text(screen)]
	else:
		text = "[b]%s[/b]  (screen %d)\n%s" % [object["title"], screen, object["text"]]
		if object["kind"] == SectorOverviewModel.Kind.PIECE or object["kind"] == SectorOverviewModel.Kind.CANISTER:
			if _canvas.is_overlay_shown(SectorOverviewCanvas.Overlay.REACHABILITY):
				text += "\nThe sub %s this one (%s search)." % [
						"can touch" if model.reach().piece_reachable[object["index"]] else "can NOT touch", ReachSweep.MODE_NAMES[model.reach_mode]]
		if object["kind"] == SectorOverviewModel.Kind.CREATURE and _canvas.is_overlay_shown(SectorOverviewCanvas.Overlay.PATHS):
			var path := model.path_of(object["index"], screen)
			if path != null:
				text += "\n" + path.describe() + " (%s, %d ticks)." % [CreaturePaths.SUB_PRESET_NAMES[model.sub_preset], model.trace_ticks]
	text += _checks_text(screen, object)
	_info.text = text


## What the checks and the comparison say about the selected object (or screen), in BBCode.
func _checks_text(screen: int, object: Dictionary) -> String:
	var text := ""
	if _checks == null:
		return text
	if _canvas.is_overlay_shown(SectorOverviewCanvas.Overlay.CHECKS):
		var marks := _checks.marks_of(object) if not object.is_empty() else _checks.marks_on(screen)
		for mark in marks:
			text += "\n[color=#%s]%s[/color]" % [SectorOverviewCanvas.finding_color(mark.finding).to_html(false), _bb(SectorOverviewChecks.describe(mark.finding))]
	if object.is_empty() and _canvas.is_overlay_shown(SectorOverviewCanvas.Overlay.CHANGES) and _checks.is_changed(screen):
		text += "\n[color=#%s]%s[/color]" % [SectorOverviewCanvas.COLOR_CHANGED.to_html(false), _bb("\n".join(_checks.changed_screens[screen]))]
	return text


## BBCode treats "[" as the start of a tag; the findings are full of "[reach.piece]".
static func _bb(text: String) -> String:
	return text.replace("[", "[lb]")


func _on_open_pressed() -> void:
	open_screen()


func _on_script_pressed() -> void:
	if _selected_object.is_empty() or _selected_object["kind"] != SectorOverviewModel.Kind.CREATURE:
		return
	var foe := model.sector.foes[_selected_object["index"]]
	if foe_script_requested.get_connections().is_empty():
		# no editor to show it in (the tool scene): say where the creature's script starts
		_info.text += "\n\nThe creature script opens in the Godot editor (the Sector Overview main screen): its entry point is the label `%s` of the sector's .foe file." % foe.start_label
		return
	foe_script_requested.emit(sector_index, _selected_object["index"], PackedStringArray([foe.start_label, foe.hit_label, foe.ink_label]))


func _update_status() -> void:
	if model == null:
		return
	var lines := model.layout.report()
	var text := "Layout: " + ("a clean map: every link joins neighbouring screens and leads back" if lines.is_empty() else "; ".join(lines))
	if _canvas.is_overlay_shown(SectorOverviewCanvas.Overlay.REACHABILITY):
		text += "\n" + model.reach_summary()
	if checking():
		text += "\nChecking ... (the reachability search runs in the background)"
	elif _checks != null:
		text += "\n" + _checks.summary()
	_status.text = text


# --- the checks ---------------------------------------------------------------------------------------------------------------

## Makes the checks and the comparison that the boxes ask for (nothing when neither is on, nothing again when what is shown already has
## what is asked for). The reachability search is part of it only with the "Reachable" box on. Runs in the background; `checks_finished`.
func _refresh_checks() -> void:
	var checks_on := _canvas.is_overlay_shown(SectorOverviewCanvas.Overlay.CHECKS)
	var changes_on := _canvas.is_overlay_shown(SectorOverviewCanvas.Overlay.CHANGES)
	_findings_box.visible = checks_on
	if model == null:
		return
	if not checks_on and not changes_on:
		_checks_task = null                                  # a result still on its way is dropped
		return
	var reach := checks_on and _canvas.is_overlay_shown(SectorOverviewCanvas.Overlay.REACHABILITY)
	if _checks != null and (not checks_on or (_checks.checked and (_checks.with_reach or not reach))) and (not changes_on or _checks.compared):
		_fill_findings()
		return                                               # what is there is enough
	var task := SectorCheckTask.start(model.sector, true, true, reach, false)
	_checks_task = task
	_findings_label.text = "Checking ..."
	task.finished.connect(_on_checks_finished.bind(task, reach), CONNECT_ONE_SHOT)


func _on_checks_finished(report: SectorReport, task: SectorCheckTask, reach: bool) -> void:
	if task != _checks_task:
		return                                               # the sector was changed, or the boxes turned off, meanwhile
	_checks_task = null
	_checks = SectorOverviewChecks.build(model, report, reach)
	_canvas.checks = _checks
	_fill_findings()
	_update_status()
	_select(_selected_screen, _selected_object)
	checks_finished.emit(_checks)


## The list beside the map: one row per finding, worst first.
func _fill_findings() -> void:
	_findings_list.clear()
	_listed.clear()
	if _checks == null or not _checks.checked:
		_findings_label.text = "Checking ..." if checking() else ""
		return
	for finding in _checks.findings:
		var allowed := not finding.allowed.is_empty()
		var where := ("screen %d " % finding.screen if finding.screen >= 0 else "") + finding.object
		var row := _findings_list.add_item("%s%s %s: %s" % ["(allowed) " if allowed else "", CheckFinding.SEVERITY_NAMES[finding.severity], where.strip_edges(), finding.message])
		_findings_list.set_item_custom_fg_color(row, SectorOverviewCanvas.finding_color(finding))
		_findings_list.set_item_tooltip(row, SectorOverviewChecks.describe(finding))
		_listed.append(finding)
	_findings_label.text = "%s (%d on the map, %d about the sector)" % [SectorChecks.summary(_checks.findings), _checks.marks.size(), _checks.unplaced.size()]


func _on_finding_picked(row: int) -> void:
	if row >= 0 and row < _listed.size():
		focus_finding(_listed[row])


## Selects the object (or screen) that `finding` is about and scrolls the map to it. A finding about the whole sector is only read.
func focus_finding(finding: CheckFinding) -> void:
	var mark := _checks.mark_of(finding) if _checks != null else null
	_canvas.selected_finding = finding
	if mark == null:
		_select(-1, {})
		_canvas.selected_screen = -1
		_info.text = "[color=#%s]%s[/color]\n\nThis one is about the sector as a whole, not about a place on the map." % [
				SectorOverviewCanvas.finding_color(finding).to_html(false), _bb(SectorOverviewChecks.describe(finding))]
		return
	_select(mark.screen, mark.object)
	_canvas.selected_screen = mark.screen
	_canvas.selected_object = mark.object
	reveal(mark.screen, mark.rect)


## Scrolls the map so that `rect` (playfield pixels) of `screen` is in the middle, zooming in first if the map is too small to see it.
func reveal(screen: int, rect: Rect2) -> void:
	_fit_pending = false
	_zoom_chosen = true
	if _canvas.zoom < REVEAL_ZOOM:
		_set_zoom(REVEAL_ZOOM)
	await get_tree().process_frame
	var at := _canvas.origin_of(screen) + rect.get_center() * _canvas.zoom
	_scroll.scroll_horizontal = int(at.x - _scroll.size.x / 2.0)
	_scroll.scroll_vertical = int(at.y - _scroll.size.y / 2.0)


# --- the toolbar ---------------------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bar := HFlowContainer.new()
	root.add_child(bar)
	_sector_box = SpinBox.new()
	_sector_box.min_value = 0
	_sector_box.max_value = maxi(Catalog.last_sector(), 0)
	_sector_box.prefix = "Sector"
	_sector_box.value_changed.connect(func(value: float) -> void: load_sector(int(value)))
	_sector_box.get_line_edit().focus_entered.connect(update_sector_range)
	bar.add_child(_sector_box)
	for entry: Array in [
			["Pieces", SectorOverviewCanvas.Overlay.PIECES, true, "The data canister (C) and the pieces. With the reachability overlay on, a red ring marks one the sub cannot touch."],
			["Creatures", SectorOverviewCanvas.Overlay.CREATURES, true, "Each creature where its record starts it, with its picture (faded: dormant or hidden)."],
			["Triggers", SectorOverviewCanvas.Overlay.TRIGGERS, true, "The (invisible) math triggers, with their problem slot."],
			["Currents", SectorOverviewCanvas.Overlay.CURRENTS, false, "The water currents: direction and strength of every current tile."],
			["Start/end", SectorOverviewCanvas.Overlay.PLACES, true, "The launch point, the header's start position, the end station and, in the finales, the finale screen."]]:
		bar.add_child(_overlay_box(entry))
	var reach_box := _overlay_box(["Reachable", SectorOverviewCanvas.Overlay.REACHABILITY, false,
			"Where the middle of the sub can be, found with the same search as the reachability tests (SectorReach). Takes a moment. Screens the sub never enters are tinted red."])
	bar.add_child(reach_box)
	var mode_box := OptionButton.new()
	for mode_name in ReachSweep.MODE_NAMES:
		mode_box.add_item(mode_name)
	mode_box.tooltip_text = "orthogonal: a safe lower bound; diagonal: slips past corners; fast: an upper bound (see the header of SectorReach)"
	mode_box.item_selected.connect(func(mode: int) -> void:
		model.reach_mode = mode as SectorReach.Mode
		_canvas.settings_changed()
		_update_status())
	bar.add_child(mode_box)
	bar.add_child(_overlay_box(["Checks", SectorOverviewCanvas.Overlay.CHECKS, false,
			"Runs the playability checks (Project > Tools > Check sector) and marks every finding where it is: red errors, amber warnings, grey dashed what is how the original is. The list on the right has them all. The reachability findings need the Reachable box on as well."]))
	bar.add_child(_overlay_box(["Changed", SectorOverviewCanvas.Overlay.CHANGES, false,
			"Frames the screens that differ from the original (the what-changed report)."]))
	bar.add_child(_overlay_box(["Creature paths", SectorOverviewCanvas.Overlay.PATHS, false,
			"Where each creature goes: its script is run for N ticks (CreaturePaths) with the sub standing still where the next box says. White dot: where it starts."]))
	var sub_box := OptionButton.new()
	for sub_name in CreaturePaths.SUB_PRESET_NAMES:
		sub_box.add_item(sub_name)
	sub_box.select(1)
	sub_box.item_selected.connect(func(preset: int) -> void:
		model.sub_preset = preset
		_canvas.settings_changed())
	bar.add_child(sub_box)
	var ticks_box := SpinBox.new()
	ticks_box.min_value = 10
	ticks_box.max_value = 999
	ticks_box.step = 10
	ticks_box.value = CreaturePaths.DEFAULT_TICKS
	ticks_box.suffix = "ticks"
	ticks_box.value_changed.connect(func(value: float) -> void:
		model.trace_ticks = int(value)
		_canvas.settings_changed())
	bar.add_child(ticks_box)
	_zoom_slider = HSlider.new()
	_zoom_slider.min_value = SectorOverviewCanvas.MIN_ZOOM
	_zoom_slider.max_value = SectorOverviewCanvas.MAX_ZOOM
	_zoom_slider.step = 0.01
	_zoom_slider.custom_minimum_size = Vector2(110, 0)
	_zoom_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_zoom_slider.tooltip_text = "Zoom (Ctrl + wheel on the map)"
	_zoom_slider.value_changed.connect(func(value: float) -> void:
		_fit_pending = false
		_zoom_chosen = true
		_canvas.zoom = value)
	bar.add_child(_zoom_slider)
	var fit := Button.new()
	fit.text = "Fit"
	fit.pressed.connect(func() -> void:
		_fit_pending = true
		_zoom_chosen = false
		_fit())
	bar.add_child(fit)

	_title = Label.new()
	root.add_child(_title)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.resized.connect(_on_scroll_resized)
	split.add_child(_scroll)
	_canvas = SectorOverviewCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.screen_selected.connect(_on_screen_selected)
	_canvas.object_picked.connect(_on_object_picked)
	_canvas.screen_open_requested.connect(open_screen)
	_canvas.zoom_changed.connect(func(value: float) -> void:
		_fit_pending = false
		_zoom_chosen = true
		_zoom_slider.set_value_no_signal(value))
	_scroll.add_child(_canvas)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(200, 0)
	split.add_child(side)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_info)
	_open_button = Button.new()
	_open_button.pressed.connect(_on_open_pressed)
	side.add_child(_open_button)
	_script_button = Button.new()
	_script_button.text = "Show the creature script"
	_script_button.pressed.connect(_on_script_pressed)
	side.add_child(_script_button)
	_findings_box = VBoxContainer.new()
	_findings_box.visible = false
	_findings_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_findings_box)
	_findings_label = Label.new()
	_findings_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_findings_box.add_child(_findings_label)
	_findings_list = ItemList.new()
	_findings_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_findings_list.custom_minimum_size = Vector2(0, 120)
	_findings_list.max_text_lines = 3
	_findings_list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_findings_list.item_selected.connect(_on_finding_picked)
	_findings_box.add_child(_findings_list)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)


func _overlay_box(entry: Array) -> CheckBox:
	var box := CheckBox.new()
	box.text = entry[0]
	box.button_pressed = entry[2]
	box.tooltip_text = entry[3]
	_overlay_boxes[entry[1]] = box
	box.toggled.connect(func(on: bool) -> void:
		_canvas.show_overlay(entry[1], on)
		if entry[1] in [SectorOverviewCanvas.Overlay.CHECKS, SectorOverviewCanvas.Overlay.CHANGES, SectorOverviewCanvas.Overlay.REACHABILITY]:
			_refresh_checks()
		_update_status()
		_select(_selected_screen, _selected_object))
	return box


## For tests and tools: switches an overlay as the check box does.
func set_overlay(overlay: SectorOverviewCanvas.Overlay, on: bool) -> void:
	_overlay_boxes[overlay].button_pressed = on


# --- command line and snapshots (tool scene only) --------------------------------------------------------------------------------------

## Reads `--key=value` / `--flag` user arguments; returns the snapshot path ("" if none).
func _apply_command_line() -> String:
	var snapshot_path := ""
	var preselect := -1
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"sector":
				sector_index = value.to_int()
			"screen":
				preselect = value.to_int()
			"zoom":
				_zoom_chosen = true
				_set_zoom(value.to_float())
			"reach":
				set_overlay(SectorOverviewCanvas.Overlay.REACHABILITY, true)
			"paths":
				set_overlay(SectorOverviewCanvas.Overlay.PATHS, true)
			"currents":
				set_overlay(SectorOverviewCanvas.Overlay.CURRENTS, true)
			"checks":
				set_overlay(SectorOverviewCanvas.Overlay.CHECKS, true)
			"changed":
				set_overlay(SectorOverviewCanvas.Overlay.CHANGES, true)
			"ticks":
				_pending_settings["ticks"] = value.to_int()
			"sub":
				_pending_settings["sub"] = value.to_int()
			"mode":
				_pending_settings["mode"] = value.to_int()
			"snapshot":
				snapshot_path = value
	if preselect >= 0:
		_pending_settings["screen"] = preselect
	return snapshot_path


func _save_snapshot_and_quit(path: String) -> void:
	if _pending_settings.has("ticks"):
		model.trace_ticks = _pending_settings["ticks"]
	if _pending_settings.has("sub"):
		model.sub_preset = clampi(_pending_settings["sub"], 0, CreaturePaths.SUB_PRESETS.size() - 1)
	if _pending_settings.has("mode"):
		model.reach_mode = clampi(_pending_settings["mode"], 0, 2) as SectorReach.Mode
	_canvas.settings_changed()
	_update_status()
	if _pending_settings.has("screen"):
		select_screen(_pending_settings["screen"])
	if checking():
		await checks_finished
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Could not save snapshot %s (error %d)" % [path, error])
	get_tree().quit(0 if error == OK else 1)
