class_name HallOfFameView
extends Control
## The Hall of Fame window: nine rows of Name / Level / Tries (DESIGN 6); the headings are the words of string 11124.
##
## Teaches: filling a `GridContainer` from data in code, and a window scene that reports with one signal.
## The rows come from `SaveStore.hall`; an unused row stays empty. Level shows "Voyager" / "Expert" and
## the original's "(c)" after customised games.

signal closed

@onready var grid: GridContainer = %Rows
@onready var title_label: Label = %Title
@onready var done_button: Button = %Done


func _ready() -> void:
	title_label.text = Catalog.text(&"hall_of_fame_title")
	done_button.text = Catalog.text(&"help_done_button")
	done_button.pressed.connect(close)
	_fill(SaveStore.hall)
	done_button.grab_focus()


## Shows the entries of `hall`: three header cells, then nine rows.
func _fill(hall: HallOfFame) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for heading in _headings():
		grid.add_child(_cell(heading, &"ConsoleTitle"))
	for row in HallOfFame.ROWS:
		var entry: HallEntry = hall.entries[row] if row < hall.entries.size() else null
		grid.add_child(_cell(entry.name if entry else ""))
		grid.add_child(_cell(entry.level_text() if entry else ""))
		grid.add_child(_cell(str(entry.tries) if entry else ""))


## The three column headings. The original draws string 11124 as the text of its dialog (`show_hall_of_fame` 0x42bafc: "   Name
## <spaces> Level <spaces> Tries" on the first line, then blank lines that leave room for the nine rows), so the words come
## from that first line; the spaces only lined them up over the columns of the original's font.
func _headings() -> PackedStringArray:
	var line := Catalog.text(&"hall_of_fame_header").replace("\r", "\n").get_slice("\n", 0)
	return line.split(" ", false)


func _cell(text: String, variation: StringName = &"") -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(130, 0)
	if variation != &"":
		label.theme_type_variation = variation
	return label


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
