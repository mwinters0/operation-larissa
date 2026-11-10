@tool
class_name SectorCheckDialog
extends AcceptDialog
## The "Check sector" window: pick a sector, press Check, read the report.
##
## Teaches: building a window out of code (an `AcceptDialog` with a few controls added to it) and showing a `RichTextLabel` with BBCode.
## The window only asks questions and shows answers; what is true about the sector is worked out by `SectorReport` (plain objects).
## The reachability search takes a few seconds, so it runs on a worker thread (`SectorCheckTask`): the window shows "Checking ..." with a
## counting-up time, keeps drawing and stays usable (the Close button works; a result that arrives for a window that was asked something
## else meanwhile is dropped), and the search can be switched off.

var _sector_box: OptionButton
var _reach_box: CheckBox
var _shared_box: CheckBox
var _check_button: Button
var _output: RichTextLabel
var _last_text := ""
var _chosen := 0
var _task: SectorCheckTask
var _serial := 0
var _started_msec := 0

## Emitted on the main thread when a check is over and its report is shown (also when it was a sector that could not be loaded).
signal check_finished(report: SectorReport)


func _init() -> void:
	title = "Check sector"
	ok_button_text = "Close"
	min_size = Vector2i(980, 640)
	exclusive = false
	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(column)
	var bar := HBoxContainer.new()
	column.add_child(bar)
	var label := Label.new()
	label.text = "Sector"
	bar.add_child(label)
	_sector_box = OptionButton.new()
	_sector_box.item_selected.connect(func(index: int) -> void: _chosen = _sector_box.get_item_id(index))
	bar.add_child(_sector_box)
	_reach_box = CheckBox.new()
	_reach_box.text = "Reachability search (a few seconds)"
	_reach_box.button_pressed = true
	bar.add_child(_reach_box)
	_shared_box = CheckBox.new()
	_shared_box.text = "Shared tables (trigger table, levels, problems)"
	bar.add_child(_shared_box)
	_check_button = Button.new()
	_check_button.text = "Check"
	_check_button.pressed.connect(_run)
	bar.add_child(_check_button)
	var copy := Button.new()
	copy.text = "Copy report"
	copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(_last_text))
	bar.add_child(copy)
	_output = RichTextLabel.new()
	_output.bbcode_enabled = true
	_output.selection_enabled = true
	_output.context_menu_enabled = true
	_output.scroll_following = false
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.custom_minimum_size = Vector2(940, 540)
	column.add_child(_output)


## Shows the window with `sector` selected (-1: the one chosen last) and runs the check at once.
func open(sector: int = -1) -> void:
	_fill_sectors()
	if sector >= 0:
		_chosen = sector
	var at := _sector_box.get_item_index(_chosen)
	_sector_box.select(maxi(at, 0))
	popup_centered()
	_run()


## The sectors that exist (`Catalog.sector_ids`), so a sector a designer added shows up too.
func _fill_sectors() -> void:
	_sector_box.clear()
	for number in Catalog.sector_ids():
		_sector_box.add_item("Sector %d" % number, number)


## The sector number of a file under a `sector_NN/` folder of the game (the sector, a screen, the script), or -1.
static func sector_of_path(path: String) -> int:
	return Catalog.sector_of_path(path)


## Starts the check of the chosen sector in the background; `check_finished` says when the report is shown.
func _run() -> void:
	if _sector_box.item_count == 0:
		_output.text = "No sector files under %s." % ", ".join(Catalog.own_sector_dirs())
		return
	var path := Catalog.sector_path(_chosen)
	var sector := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as SectorData
	if sector == null:
		_output.text = "Could not load %s." % path
		return
	_check_button.disabled = true
	_started_msec = Time.get_ticks_msec()
	_show_waiting()
	_serial += 1
	var serial := _serial
	await get_tree().process_frame             # draw "Checking ..." first: the comparison with the original takes a moment on this thread
	if serial != _serial:
		return                                 # another check was asked for meanwhile
	_task = SectorCheckTask.start(sector, true, true, _reach_box.button_pressed, _shared_box.button_pressed)
	_task.finished.connect(_on_finished.bind(_task), CONNECT_ONE_SHOT)
	set_process(true)


func _process(_delta: float) -> void:
	if _task != null and _task.running:
		_show_waiting()
	else:
		set_process(false)


func _show_waiting() -> void:
	_output.text = "Checking sector %d ... %.0f s" % [_chosen, (Time.get_ticks_msec() - _started_msec) / 1000.0]


func _on_finished(report: SectorReport, task: SectorCheckTask) -> void:
	if task != _task:
		return                                 # another check was started meanwhile
	_task = null
	_last_text = report.text()
	_output.text = report.bbcode()
	_check_button.disabled = false
	check_finished.emit(report)
