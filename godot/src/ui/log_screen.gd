class_name LogScreen
extends Control
## The data canister's log screen ("Star Log System", `DoDataBank` 0x41e18f): the access code is solved, the canister's
## computer scans, reads the new log entry aloud and lets the player browse the entries of this and the earlier sectors.
##
## Teaches: a screen built from plain nodes instead of drawing code (the original paints text and rectangles into a
## bitmap; here a `Label` per menu row, a `ColorRect` as the highlight and a `Label` for the entry), a menu with its own
## small model (`CanisterLog`), and an animation that is a function of TICKS the rules count (the scanner lights): the screen
## converts real time into ticks (`TickMeter`) and shows `CanisterLog.scan_picture(tick)`.
##
## What happens (DESIGN 7, "Canister log screen"):
##   1. The screen is drawn: the problem screen's picture with the title "Star Log System", the entry text on the left
##      monitor (the newest entry), the menu "LOG ENTRY MENU" on the right: "ENTRY 1.04" ... and DONE, two columns of 8 rows.
##   2. The scan: scanner sound 0x1d and eight lights, a red one running left to right, six times, 5 ticks a picture
##      (240 ticks = 3.3 s, `CanisterLog.scan_ticks()`). The keyboard is dead meanwhile (the original flushes whatever was typed).
##      The LENGTH is the rules' (`CanisterLog`); this screen is told it and shows the picture of each tick (`advance_scan`).
##   3. The entry is read aloud. While it plays only Esc, Enter, the arrow keys and a click on a menu row get through (they cut
##      the speech); every other key is thrown away.
##   4. Up / Down (or 8 / 2) move the highlight and wrap around, Left / Right (or 4 / 6) jump to the other column. Enter shows and
##      reads the highlighted entry (on DONE it leaves), a click on the highlighted row does the same and a click on another
##      row moves the highlight there. Esc leaves.
##
## Usage:  var screen := LOG_SCREEN.instantiate(); add_child(screen); screen.start(sector); await screen.finished

## The scan ran its `CanisterLog.scan_ticks()` ticks (private: `run_scan` waits for it).
signal scan_ticks_over
## The player is done with the log: DONE was chosen or Esc pressed.
signal finished
## The scanner animation is over: the keyboard works again and the first entry is being read.
signal scan_finished
## An entry (1-15) was put on the left monitor.
signal entry_shown(number: int)

## The bundle 476 pictures (228 x 26, eight lights, the problem art `log_scan_0` .. `log_scan_8`): 0-7 have the red light at
## position 0-7, 8 is all green (rests there).
const SCAN_PICTURE_COUNT := 9
## The scanner effect (`sound` name `scanner`, the original's common sound 0x1d).
const SFX_SCANNER := &"scanner"

## ONWIN32 strings: "ENTRY", "LOG ENTRY MENU", "DONE" and the problem title 11074 + 35.
const STRING_ENTRY := &"log_entry_word"
const STRING_MENU := &"log_menu_title"
const STRING_DONE := &"log_done_caption"
const STRING_TITLE := &"star_log_title"
## `SetColor` numbers: white text and highlight, the yellow menu title, the green entry text, black.
const COLOR_WHITE := 15
const COLOR_MENU_TITLE := 14
const COLOR_ENTRY := 2
const COLOR_BLACK := 0

## The sector whose log is shown (its number decides the campaign and how many entries are listed).
var sector: int = 0
## True from `start` until the scan is over: input is thrown away.
var scanning: bool = false

var _campaign: Campaign
var _numbers: PackedInt32Array = PackedInt32Array()
var _row: int = 0
var _shown: int = 0
var _closed: bool = false
var _row_labels: Array[Label] = []
var _scan_ticks := TickMeter.new()
var _scan_tick: int = 0
var _scan_running: bool = false

@onready var background: TextureRect = %Background
@onready var title_label: Label = %Title
@onready var menu_title: Label = %MenuTitle
@onready var cursor: ColorRect = %Cursor
@onready var rows: Control = %Rows
@onready var entry_text: Label = %EntryText
@onready var lights: TextureRect = %Lights


func _ready() -> void:
	_apply_layout(Catalog.screen_layout())
	title_label.text = Catalog.text(STRING_TITLE)
	menu_title.text = Catalog.text(STRING_MENU)


## Puts the shared parts where the original has them (`ProblemScreenLayout`): the screen picture, the title and the colours.
func _apply_layout(layout: ProblemScreenLayout) -> void:
	background.texture = layout.background
	background.position = Vector2(layout.background_position)
	title_label.position = Vector2(layout.title_box_x, layout.title_y)
	title_label.size = Vector2(layout.title_box_width, layout.line_height)
	title_label.add_theme_color_override("font_color", layout.color(COLOR_WHITE))
	menu_title.add_theme_color_override("font_color", layout.color(COLOR_MENU_TITLE))
	cursor.color = layout.color(COLOR_WHITE)
	entry_text.add_theme_color_override("font_color", layout.color(COLOR_ENTRY))
	entry_text.add_theme_constant_override("line_spacing", layout.line_separation)        # (data, not the font's height)


## Builds the menu for `sector_index` and runs the whole sequence: the newest entry's text, the scan, its speech, then the
## menu answers the keyboard and the mouse until `finished`. A coroutine: callers just ignore the return.
func start(sector_index: int) -> void:
	sector = sector_index
	_campaign = CanisterLog.campaign_of(sector)
	_numbers = CanisterLog.entries(sector)
	_row = CanisterLog.initial_row(sector)
	_closed = false
	_build_rows()
	_show_entry(_numbers[_row])
	scanning = true
	await run_scan()
	scanning = false
	_speak(_numbers[_row])
	scan_finished.emit()


## One label per entry (text "ENTRY 1.04") and the DONE label last, at the positions of `CanisterLog.row_position`. The
## original registers a mouse hot spot (id 3000 + row) for each; here the labels catch the clicks themselves.
func _build_rows() -> void:
	for old in rows.get_children():
		old.queue_free()
	_row_labels.clear()
	var captions: Array[String] = []
	for number in _numbers:
		captions.append(CanisterLog.label(Catalog.text(STRING_ENTRY), _campaign, number))
	captions.append(Catalog.text(STRING_DONE))
	for i in captions.size():
		var label := Label.new()
		label.text = captions[i]
		label.position = Vector2(CanisterLog.row_position(i))
		label.size = Vector2(CanisterLog.ROW_SIZE)
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.gui_input.connect(_on_row_gui_input.bind(i))
		rows.add_child(label)
		_row_labels.append(label)
	# The original's box is 16 px high; our font sits about 3 px lower in its line than the GDI font, so the box is a line
	# high to keep the black text inside the white.
	cursor.size = Vector2(CanisterLog.ROW_SIZE.x, Catalog.screen_layout().line_height)
	_update_highlight()


## The highlighted row is a white box (2 px left of the text) with black text; the others are white text on black.
func _update_highlight() -> void:
	var layout := Catalog.screen_layout()
	for i in _row_labels.size():
		var selected := i == _row
		_row_labels[i].add_theme_color_override("font_color", layout.color(COLOR_BLACK if selected else COLOR_WHITE))
	cursor.position = Vector2(CanisterLog.row_position(_row)) - Vector2(2, 0)


## Entry `number` (1-15) goes on the left monitor (the original restores the clean monitor first, then draws the text).
func _show_entry(number: int) -> void:
	_shown = number
	entry_text.text = _campaign.log_entry_text(number)
	entry_shown.emit(number)


func _speak(number: int) -> void:
	Audio.play_voice_sequence(Catalog.voice_cues().clips(String(_campaign.log_voice_name(number))))


## The number (1-15) of the entry on the left monitor.
func shown_entry() -> int:
	return _shown


## The highlighted row (0 .. entry count; the last row is DONE).
func selected_row() -> int:
	return _row


func row_count() -> int:
	return _row_labels.size()


# --- the scan -------------------------------------------------------------------------------

## The scanner sound and the lights (`AnimateLogScan`). Returns when the scan's ticks are over (`CanisterLog.scan_ticks()`); the sound is
## cut at that moment (`StopCommonSoundEffect` 0x431ef2), but the 3.15 s effect is shorter than the 3.3 s scan anyway.
func run_scan() -> void:
	Audio.play_sfx(SFX_SCANNER)
	_scan_tick = 0
	_scan_ticks.reset()
	_scan_running = true
	_show_scan_picture()
	await scan_ticks_over
	Audio.stop_sfx()


## Lets `ticks` ticks of the scan pass (the real-time `_process` calls this; a test can finish the scan at once).
func advance_scan(ticks: int) -> void:
	if not _scan_running:
		return
	_scan_tick = mini(_scan_tick + ticks, CanisterLog.scan_ticks())
	_show_scan_picture()
	if _scan_tick >= CanisterLog.scan_ticks():
		_scan_running = false
		scan_ticks_over.emit()


func _process(delta: float) -> void:
	if _scan_running:
		advance_scan(_scan_ticks.feed(delta))


func _show_scan_picture() -> void:
	lights.texture = scan_picture(CanisterLog.scan_picture(_scan_tick))


## Scanner picture `index` (0..8), asked of `Assets` each time: it depends on the pack chain and the skin in use, so nothing keeps it
## (the texture itself is cached where it is loaded).
static func scan_picture(index: int) -> Texture2D:
	return Assets.problem_art(StringName("log_scan_%d" % index))


## The nine scanner pictures (`scan_picture`).
static func scan_pictures() -> Array[Texture2D]:
	var pictures: Array[Texture2D] = []
	for i in SCAN_PICTURE_COUNT:
		pictures.append(scan_picture(i))
	return pictures


# --- input ------------------------------------------------------------------------------------

## Every plain key belongs to this screen while it is up. During the scan they are thrown away; while the speech plays only
## Esc, Enter and the arrow keys get through (and cut the speech: `PlayLogEntrySpeech` 0x41dfc8 peeks for exactly these and
## discards anything else); the digits 8 2 4 6 work as arrows only when no speech is playing.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.alt_pressed or key.ctrl_pressed or key.meta_pressed:
		return
	get_viewport().set_input_as_handled()                 # (also after `finished`, until the owner frees the screen)
	if scanning or _closed:
		return
	var command := _arrow_command(key.keycode)
	if command != &"":
		Audio.stop_voice()
	elif not Audio.is_voice_playing():
		command = _digit_command(key.keycode)
	if command != &"":
		press(command)


## Esc, Enter and the four arrow keys (the keys that cut the speech).
func _arrow_command(keycode: Key) -> StringName:
	match keycode:
		KEY_ESCAPE:
			return &"escape"
		KEY_ENTER, KEY_KP_ENTER:
			return &"enter"
		KEY_UP:
			return &"up"
		KEY_DOWN:
			return &"down"
		KEY_LEFT, KEY_RIGHT:
			return &"sideways"
	return &""


## The digits 8 / 2 / 4 / 6 (main row or keypad).
func _digit_command(keycode: Key) -> StringName:
	match keycode:
		KEY_8, KEY_KP_8:
			return &"up"
		KEY_2, KEY_KP_2:
			return &"down"
		KEY_4, KEY_KP_4, KEY_6, KEY_KP_6:
			return &"sideways"
	return &""


## Runs one menu command: &"up", &"down", &"sideways" (move the highlight), &"enter" (show the highlighted entry, or leave
## on DONE) or &"escape" (leave). Public so tests and the debug menu can drive the screen without key events.
func press(command: StringName) -> void:
	if _closed:
		return
	match command:
		&"escape":
			_leave()
		&"enter":
			_activate(_row)
		&"up":
			_select(CanisterLog.next_row(_row, _numbers.size(), CanisterLog.Move.UP))
		&"down":
			_select(CanisterLog.next_row(_row, _numbers.size(), CanisterLog.Move.DOWN))
		&"sideways":
			_select(CanisterLog.next_row(_row, _numbers.size(), CanisterLog.Move.SIDEWAYS))


## A click on menu row `row`. Cuts the speech. On the highlighted row it acts like Enter, on another row it only moves the
## highlight there (`DoDataBank`: hot spot ids 3000 + row).
func click_row(row: int) -> void:
	if _closed or scanning or row < 0 or row >= _row_labels.size():
		return
	Audio.stop_voice()
	if row == _row:
		_activate(row)
	else:
		_select(row)


func _on_row_gui_input(event: InputEvent, row: int) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		click_row(row)


func _select(new_row: int) -> void:
	if new_row == _row:
		return
	_row = new_row
	_update_highlight()


func _activate(row: int) -> void:
	if row >= _numbers.size():
		_leave()
		return
	_show_entry(_numbers[row])
	_speak(_numbers[row])


func _leave() -> void:
	_closed = true
	Audio.stop_voice()
	finished.emit()
