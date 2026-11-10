class_name AudioProbe
extends RefCounted
## Test helper: records everything the `Audio` autoload is asked to do, so a test can say "this event plays
## the sound effect `correct`" without a loudspeaker. Call `stop()` when done (the autoload outlives every test).

var sfx: Array[StringName] = []
var voice: Array[Array] = []
var music: Array[StringName] = []


func _init() -> void:
	Audio.sfx_played.connect(_on_sfx)
	Audio.voice_played.connect(_on_voice)
	Audio.music_changed.connect(_on_music)


func stop() -> void:
	Audio.sfx_played.disconnect(_on_sfx)
	Audio.voice_played.disconnect(_on_voice)
	Audio.music_changed.disconnect(_on_music)


func clear() -> void:
	sfx.clear()
	voice.clear()
	music.clear()


func _on_sfx(sfx_name: StringName) -> void:
	sfx.append(sfx_name)


func _on_voice(clips: Array[StringName]) -> void:
	voice.append(clips)


func _on_music(song: StringName) -> void:
	music.append(song)
