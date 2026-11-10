class_name AudioSettingsDialog
extends Control
## Options > Audio Settings: four volume sliders (one per audio bus) and the choice of music set.
##
## Teaches: `HSlider` driving an audio bus through the `Audio` autoload (the dialog never touches
## `AudioServer` itself), `OptionButton`, a short preview sound when a slider is let go so the player can hear the
## new level, and a dialog that saves its result when it closes (`Audio.save_settings`, a `ConfigFile`).
## The on/off switches for effects, music and voice are NOT here: they are per player, in the Options menu.

## The player closed the dialog (Done or Esc). The settings are already saved.
signal closed

## Sound used as the preview when a slider is released: right-answer chime, and the "Begin mission" clip.
const PREVIEW_SFX := &"correct"
const PREVIEW_VOICE := &"sign_in_begin_1"

@onready var rows: VBoxContainer = %Rows
@onready var set_picker: OptionButton = %SetPicker
@onready var done_button: Button = %Done

var _sliders: Dictionary = {}                       # bus name -> HSlider


func _ready() -> void:
	for bus in AudioService.BUSES:
		_add_slider_row(bus)
	set_picker.add_item("General MIDI (richer)", MusicCatalog.SoundSet.GENERAL_MIDI)
	set_picker.add_item("AdLib (the original's base set)", MusicCatalog.SoundSet.ADLIB)
	set_picker.select(Audio.sound_set)
	set_picker.item_selected.connect(func(index: int) -> void: Audio.set_sound_set(set_picker.get_item_id(index)))
	done_button.pressed.connect(close)
	_sliders[AudioService.MASTER].grab_focus()


func _add_slider_row(bus: StringName) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = {AudioService.MASTER: "Master", AudioService.MUSIC: "Music", AudioService.SFX: "Sound effects",
			AudioService.VOICE: "Voice"}[bus]
	label.custom_minimum_size.x = 120
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Audio.get_bus_volume(bus)
	slider.custom_minimum_size.x = 220
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(value: float) -> void: Audio.set_bus_volume(bus, value))
	slider.drag_ended.connect(func(_changed: bool) -> void: _preview(bus))
	_sliders[bus] = slider
	row.add_child(label)
	row.add_child(slider)
	rows.add_child(row)
	rows.move_child(row, rows.get_child_count() - 1 - 2)      # above the music-set row and the buttons


## Plays a sample on the bus whose slider was let go (the music is already audible).
func _preview(bus: StringName) -> void:
	if bus == AudioService.SFX or bus == AudioService.MASTER:
		Audio.play_sfx(PREVIEW_SFX)
	elif bus == AudioService.VOICE:
		Audio.play_voice(PREVIEW_VOICE)


func close() -> void:
	Audio.save_settings()
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
