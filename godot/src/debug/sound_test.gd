class_name SoundTest
extends Control
## Sound test: lists every sound effect (52), every voice clip (371, with the machine-generated transcript) and
## every song (10, in the current music set) so that you can listen to them one by one.
##
## Enter or double click = play, Esc = stop everything, Tab / Shift+Tab = next list, S = switch the music set
## (General MIDI / AdLib), M = mute the music bus. Names for effects come from the decompilation
## (`SfxCatalog.named`); effects the game never plays are listed as "sfx_NN".
##
## Teaches: `TabContainer` with `ItemList`s filled from Resources, the `Audio` autoload used from a tool scene,
## and `Audio`'s signals as a log of what was requested.

@onready var tabs: TabContainer = %Tabs
@onready var effects: ItemList = %Effects
@onready var voices: ItemList = %Voices
@onready var songs: ItemList = %Songs
@onready var status: Label = %Status
@onready var log_label: RichTextLabel = %Log


func _ready() -> void:
	var catalog := Catalog.sfx_catalog()
	for i in catalog.streams.size():
		var stream := catalog.stream(i)
		effects.add_item("0x%02x  %-20s %4.2f s" % [i, catalog.name_of(i), stream.get_length() if stream != null else 0.0])
	var index := Catalog.voice_index()
	for clip in index.ids:
		voices.add_item("%-28s %s" % [NameRegistry.original().name_of(&"voice", clip), index.transcript(clip)])
	var music := Catalog.music_catalog()
	for i in music.ids.size():
		songs.add_item("%-16s %s" % [NameRegistry.original().name_of(&"music", music.ids[i]), music.midi_names[i]])
	for list in [effects, voices, songs]:
		(list as ItemList).item_activated.connect(_play_item.bind(list))
	Audio.sfx_played.connect(func(sfx: StringName) -> void: _log("effect %s" % sfx))
	Audio.voice_started.connect(func(clip: StringName, text: String) -> void: _log("voice %s: %s" % [clip, text]))
	Audio.music_changed.connect(func(song: StringName) -> void: _log("music %s" % song))
	_update_status()
	effects.grab_focus()


func _play_item(item: int, list: ItemList) -> void:
	if list == effects:
		Audio.play_sfx(Catalog.sfx_catalog().name_of(item))              # (the list is in the order of the numbers)
	elif list == voices:
		Audio.play_voice(StringName(NameRegistry.original().name_of(&"voice", Catalog.voice_index().ids[item])))
	else:
		Audio.play_music(StringName(NameRegistry.original().name_of(&"music", Catalog.music_catalog().ids[item])))


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ESCAPE:
			Audio.stop_music()
			Audio.stop_voice()
			Audio.stop_sfx()
		KEY_TAB:
			tabs.current_tab = posmod(tabs.current_tab + (-1 if key.shift_pressed else 1), tabs.get_tab_count())
			(tabs.get_current_tab_control() as ItemList).grab_focus()
		KEY_S:
			Audio.set_sound_set(1 - Audio.sound_set)
		KEY_M:
			Audio.set_bus_enabled(AudioService.MUSIC, not Audio.is_bus_enabled(AudioService.MUSIC))
	_update_status()


func _update_status() -> void:
	status.text = "Music set: %s    music bus: %s    (Enter play, Esc stop, Tab list, S set, M mute music)" % [
			"AdLib" if Audio.sound_set == MusicCatalog.SoundSet.ADLIB else "General MIDI",
			"on" if Audio.is_bus_enabled(AudioService.MUSIC) else "muted"]


func _log(line: String) -> void:
	log_label.text = (log_label.text + line + "\n").right(2000)
	log_label.scroll_to_line(log_label.get_line_count())
