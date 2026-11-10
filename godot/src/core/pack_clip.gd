class_name PackClip
extends RefCounted
## A sound, song or speech clip found in a pack: the stream and, in time, how long it lasts, both from the same pack.
##
## A clip's LENGTH is what holds up the game (a speech lasts a number of ticks, never the stream's `finished`), and the length of a clip a
## pack brings comes from that pack, never from the original's table: `Packs.clip` returns the stream and `ticks` of the SAME pack.
## `ticks` is the length the pack states in its `audio/lengths.json`, else the file's own length measured when the pack was mounted and rounded
## up (`ClipLengths`). It is -1 only for a file with no measurable length.

## The pack that holds the clip.
var pack_id: StringName = &""
var stream: AudioStream
## The length in whole ticks of 1/73 s, or -1 when there is none to be had (see above).
var ticks: int = -1


static func of(from_pack: Pack, audio_stream: AudioStream, length_ticks: int = -1) -> PackClip:
	var clip := PackClip.new()
	clip.pack_id = from_pack.id
	clip.stream = audio_stream
	clip.ticks = length_ticks
	return clip
