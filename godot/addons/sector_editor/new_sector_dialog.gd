@tool
class_name NewSectorDialog
extends ConfirmationDialog
## The "New sector" window (Project > Tools > "New sector..."): pick what the sector starts as, give it a number, press Create.
##
## Teaches: the thin editor part of a tool again (like `SectorCheckDialog`). The window only asks, and shows why a number is refused while
## you type it; `SectorFactory` (a plain class, with tests) makes the files. The choices are the ones of `SectorFactory`: the EMPTY
## TEMPLATE (12 screens with a floor, a canister and a piece, no creatures; its zone and game are asked) or a COPY of any sector that
## exists, the originals included; the number is any free one from 32 up, the next free one to begin with.

## The id of the "Empty template" item (an OptionButton id of -1 means "the item's number", so the template needs one of its own).
const TEMPLATE_ITEM := 1000

## The sectors folder the new sector goes into; "" is the project's (`Catalog.sectors_dir`). A test sets its own.
var dir := ""

var _source_box: OptionButton
var _number_box: SpinBox
var _zone_box: SpinBox
var _game_box: OptionButton
var _message: Label

## Emitted when a sector was made, with what `SectorFactory` returned. The editor plugin then lets Godot find the files.
signal sector_made(made: SectorFactory.Made)


func _init() -> void:
	title = "New sector"
	ok_button_text = "Create"
	dialog_hide_on_ok = false                                    # stays open when the sector is refused
	var column := VBoxContainer.new()
	add_child(column)
	var grid := GridContainer.new()
	grid.columns = 2
	column.add_child(grid)
	_source_box = _row(grid, "Start from", OptionButton.new()) as OptionButton
	_source_box.item_selected.connect(func(_item: int) -> void: _refresh())
	_number_box = _row(grid, "Sector number", SpinBox.new()) as SpinBox
	_number_box.min_value = Catalog.ORIGINAL_SECTOR_COUNT
	_number_box.max_value = Catalog.MAX_SECTOR
	_number_box.value_changed.connect(func(_value: float) -> void: _refresh())
	_zone_box = _row(grid, "Zone (template)", SpinBox.new()) as SpinBox
	_zone_box.min_value = 0
	_zone_box.max_value = Catalog.ZONE_COUNT - 1
	_game_box = _row(grid, "Game (template)", OptionButton.new()) as OptionButton
	_game_box.add_item("Voyager", 0)
	_game_box.add_item("Expert", 1)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(420, 0)
	column.add_child(_message)
	confirmed.connect(create)


func _row(grid: GridContainer, text: String, control: Control) -> Control:
	var label := Label.new()
	label.text = text
	grid.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)
	return control


## Shows the window: "Empty template" and one "Copy of sector N" per sector that exists, the next free number chosen. `source`: the
## sector to copy at the start (-1: the template).
func open(source: int = -1) -> void:
	_source_box.clear()
	_source_box.add_item("Empty template", TEMPLATE_ITEM)
	for index in Catalog.sector_ids(dir):
		_source_box.add_item("Copy of sector %d" % index, index)
	_source_box.select(maxi(_source_box.get_item_index(source if source >= 0 else TEMPLATE_ITEM), 0))
	_number_box.value = maxi(Catalog.next_free_sector(dir), Catalog.ORIGINAL_SECTOR_COUNT)
	_refresh()
	popup_centered()


## What the window would make now: the sector number, -1 for the template or the sector to copy.
func chosen_number() -> int:
	return int(_number_box.value)


func chosen_source() -> int:
	var id := _source_box.get_selected_id()
	return -1 if id == TEMPLATE_ITEM or id < 0 else id


## Why the sector can not be made as it is set up now ("" when it can); also what the window shows under the fields.
func problem() -> String:
	var found := SectorFactory.refusal(chosen_number(), dir)
	if found.is_empty() and chosen_source() >= 0 and not Catalog.has_sector(chosen_source(), dir):
		found = "there is no sector %d to copy" % chosen_source()
	return found


func _refresh() -> void:
	var template := chosen_source() < 0
	_zone_box.editable = template
	_game_box.disabled = not template
	var found := problem()
	_message.text = found if not found.is_empty() else "Creates sector %d in %s." % [chosen_number(), Catalog.sector_dir(chosen_number(), dir)]
	get_ok_button().disabled = not found.is_empty()


## Makes the sector as the window is set up, and closes it; a refusal stays in the window.
func create() -> SectorFactory.Made:
	var made: SectorFactory.Made
	if chosen_source() < 0:
		made = SectorFactory.new_from_template(chosen_number(), int(_zone_box.value), _game_box.get_selected_id(), dir)
	else:
		made = SectorFactory.new_from_copy(chosen_source(), chosen_number(), dir)
	if made.ok():
		hide()
		sector_made.emit(made)
		_refresh()                                               # (the number is taken now)
	else:
		_message.text = made.error
	return made
