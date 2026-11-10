class_name SfxCatalog
extends Resource
## The 52 sound effects, plus friendly names for the ones we understand.
##
## The names are not stored here: they are the `sound` names of the NameRegistry (names/original.json), the one place
## where the project keeps what it calls things. This class only asks it.

## streams[i] is original effect index i (NE0SOUND 8000 + i).
@export var streams: Array[AudioStream] = []
## Name -> effect index, for the effects that have a name of their own (identified in DESIGN section 7), by number.
var named: Dictionary:
	get:
		return NameRegistry.original().entries(&"sound")
## Problem type -> the effect its diagram plays while it is built (docs/data/audio_map.json "diagram_cues").
@export var diagram_cues: Dictionary = {}
## (`diagram_cues` has numbers for keys: how the JSON form of a pack reads them, `ResourceJson`.)
const JSON_INT_KEYS: Array[String] = ["diagram_cues"]

func stream(id: int) -> AudioStream:
	return streams[id] if id >= 0 and id < streams.size() else null

## The effect called `effect_name`: a mounted pack's `audio/sound/<name>.ogg` first (it can replace an effect of the original, or add one),
## else the original's.
func stream_named(effect_name: StringName) -> AudioStream:
	var from_pack := Packs.clip(&"sound", effect_name)
	return from_pack.stream if from_pack != null else stream(id_of(effect_name))


## The effect index for a friendly name (or a made-up one like "sfx_28"), or -1.
func id_of(effect_name: StringName) -> int:
	return NameRegistry.original().index_of(&"sound", String(effect_name))


## The friendly name of effect `id` ("sfx_28" when nobody has named it yet): the name the game's events carry.
func name_of(id: int) -> StringName:
	return StringName(NameRegistry.original().name_of(&"sound", id))


## The sound for the diagram of problem type `type_id`, or -1 when that diagram is silent.
func diagram_cue(type_id: int) -> int:
	return int(diagram_cues.get(type_id, -1))
