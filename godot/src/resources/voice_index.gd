class_name VoiceIndex
extends Resource
## The 371 voice clips with their (machine generated, possibly wrong) transcripts.
##
## Teaches: lazy loading. Only paths are stored, so opening this index does not
## load 14 MB of audio; `stream()` loads a clip when it is needed, through the door of the pack the path is in (`Packs.file_at`).

## (`paths` are paths into a pack: how the data form of a pack writes them, `ResourceJson`.)
const JSON_PATH_FIELDS: Array[String] = ["paths"]

@export var ids: PackedInt32Array = PackedInt32Array()
@export var paths: PackedStringArray = PackedStringArray()
## Whisper transcript; may be empty or wrong.
@export var transcripts: PackedStringArray = PackedStringArray()
## How long each clip lasts in the ORIGINAL, in whole ticks of 1/73 s (rounded up), measured by the importer. This is the length the
## game waits for a clip (a screen that goes on after the speech, a story page): never the length of the stream that plays, so
## playback (device, focus, no audio at all) cannot change how long a step lasts. These are the legacy pack's lengths; a pack that
## brings its own recordings brings their lengths too (`ticks_named`).
@export var durations: PackedInt32Array = PackedInt32Array()

func stream(id: int) -> AudioStream:
	var i := ids.find(id)
	return Packs.file_at(paths[i]) as AudioStream if i >= 0 else null

## The recorded length of clip `id` in ticks of 1/73 s; 0 when there is no such clip.
func ticks(id: int) -> int:
	var i := ids.find(id)
	return durations[i] if i >= 0 and i < durations.size() else 0


## The length of the clip called `clip` (a `voice` name), in ticks of 1/73 s: that of the pack that holds the clip. A mounted pack's clip
## lasts what that pack says (`PackClip.ticks`: its stated length, else its file's measured one), the same pack the stream comes from, never
## the original's number for another recording; a clip no pack has lasts the importer's measurement of the original (the legacy pack). 0 for a name
## that is none of those (the speech goes on when the stream ends).
func ticks_named(clip: StringName) -> int:
	var from_pack := Packs.clip(&"voice", clip)
	if from_pack != null:
		return maxi(from_pack.ticks, 0)
	return ticks(NameRegistry.original().index_of(&"voice", String(clip)))


## The recorded length of a run of clips, one after the other.
func ticks_of(clips: Array[StringName]) -> int:
	var total := 0
	for clip in clips:
		total += ticks_named(clip)
	return total


func transcript(id: int) -> String:
	var i := ids.find(id)
	return transcripts[i] if i >= 0 else ""


## The clip called `clip` (a `voice` name of names/original.json): the resolver of the `voice` kind. A mounted pack's `audio/voice/<name>.ogg`
## comes first (it replaces a clip of the original or is a new one).
func stream_named(clip: StringName) -> AudioStream:
	var from_pack := Packs.clip(&"voice", clip)
	return from_pack.stream if from_pack != null else stream(NameRegistry.original().index_of(&"voice", String(clip)))


func transcript_named(clip: StringName) -> String:
	return transcript(NameRegistry.original().index_of(&"voice", String(clip)))
