class_name MusicCatalog
extends Resource
## The ten songs of the original and where their rendered OGG files are.
##
## The original numbers its songs 9500-9509 (extracted/tables/music_map.json: `LoadMidiFile` looks the id up in a
## table) and plays the `E*.MID` files on a General MIDI card, the `B*.MID` files on an AdLib card. Godot cannot
## play MIDI, so the import pipeline renders both sets to OGG with FluidSynth (see tools/import/step_audio.py).
##
## Teaches: a Resource that stores PATHS, not streams, so that opening the catalog does not load 30 MB of audio;
## `stream()` loads one song when it is needed, through the door of the pack the path is in (`Packs.file_at`).

## (`gm_paths` and `adlib_paths` are paths into a pack: how the data form of a pack writes them, `ResourceJson`.)
const JSON_PATH_FIELDS: Array[String] = ["gm_paths", "adlib_paths"]

## Which rendering of the music to use. The numbers are what the Options dialog saves.
enum SoundSet { GENERAL_MIDI = 0, ADLIB = 1 }

@export var ids: PackedInt32Array = PackedInt32Array()
@export var gm_paths: PackedStringArray = PackedStringArray()
@export var adlib_paths: PackedStringArray = PackedStringArray()
## The original file names ("BSECT1.MID"), for the sound test and the docs.
@export var midi_names: PackedStringArray = PackedStringArray()


## The songs of the original by the stem of their General MIDI file (what `SectorData.music_name` holds: "esect1" is played from "esect1.mid"),
## and the `music` name of each ("sector_song_1"): stem -> name, worked out from `midi_names` and the registry. The AdLib set has the same
## songs as "bsect1" ...; `midi_file_of` turns the name into either file.
func songs_by_stem() -> Dictionary:
	var registry := NameRegistry.original()
	var songs := {}
	for i in ids.size():
		songs[("e" + midi_names[i].get_basename().substr(1)).to_lower()] = StringName(registry.name_of(&"music", ids[i]))
	return songs


## The `music` name of the song whose MIDI file stem is `stem` ("esect4" gives `sector_song_4`), or empty for a stem that is none of the
## original's songs. This is how a sector's `music_name` becomes the name `Audio.play_music` takes (`Campaign.song_for`).
static func song_of_stem(stem: String) -> StringName:
	var song: StringName = Catalog.music_catalog().songs_by_stem().get(stem.to_lower(), &"")
	if song == &"" and Packs.clip(&"music", StringName(stem)) != null:
		return StringName(stem)                    # a song of a pack (`audio/music/<stem>.ogg`) is called by its file name
	return song


## The `music` name of a song (`names/original.json`) as the original's number, or -1.
static func id_of(song_name: StringName) -> int:
	return NameRegistry.original().index_of(&"music", String(song_name))


## The original's MIDI file name of the song called `song_name` ("ESECT1.MID"), or "(none)".
func midi_name_of(song_name: StringName) -> String:
	var i := ids.find(id_of(song_name))
	return midi_names[i] if i >= 0 else "(none)"


## The MIDI file of the song called `song_name` in a sound set: the General MIDI set is the `E*.MID` file, the AdLib set the `B*.MID`
## file of the same name ("ESECT1.MID" / "BSECT1.MID", the original's `LoadMidiFile`). "" for a name that means no song. `MidiMusic`
## plays it at runtime instead of the rendered OGG.
func midi_file_of(song_name: StringName, sound_set: int = SoundSet.GENERAL_MIDI) -> String:
	var i := ids.find(id_of(song_name))
	if i < 0:
		return ""
	return ("B" if sound_set == SoundSet.ADLIB else "E") + midi_names[i].substr(1)


func path_for(music_id: int, sound_set: int = SoundSet.GENERAL_MIDI) -> String:
	var i := ids.find(music_id)
	if i < 0:
		return ""
	return adlib_paths[i] if sound_set == SoundSet.ADLIB else gm_paths[i]


## The song called `song_name` (the resolver of the `music` kind): `stream` of its number. Null with a warning for a name that
## means no song.
func stream_named(song_name: StringName, sound_set: int = SoundSet.GENERAL_MIDI) -> AudioStream:
	var from_pack := Packs.clip(&"music", song_name)             # a mounted pack's song (it has one set only, whatever `sound_set` is)
	if from_pack != null:
		var own := from_pack.stream as AudioStreamOggVorbis
		own.loop = true
		return own
	var id := id_of(song_name)
	if id < 0:
		push_warning("MusicCatalog: no song called '%s'" % song_name)
		return null
	return stream(id, sound_set)


## The song as a looping stream, or null (with a warning, never a crash) when the file is missing.
## If the AdLib set was not rendered the General MIDI one is used instead.
func stream(music_id: int, sound_set: int = SoundSet.GENERAL_MIDI) -> AudioStream:
	var path := path_for(music_id, sound_set)
	if path.is_empty():
		push_warning("MusicCatalog: no song with id %d" % music_id)
		return null
	if not Packs.exists_at(path) and sound_set != SoundSet.GENERAL_MIDI:
		path = path_for(music_id, SoundSet.GENERAL_MIDI)
	if not Packs.exists_at(path):
		push_warning("MusicCatalog: missing music file " + path)
		return null
	var song := Packs.file_at(path) as AudioStreamOggVorbis
	if song != null:
		song.loop = true                       # the original restarts a song from its start when it ends
	return song
