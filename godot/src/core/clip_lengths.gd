class_name ClipLengths
extends RefCounted
## How long a pack's sound, song or speech clips last, in ticks of 1/73 s, and whether the numbers can be believed.
##
## A clip's length is what holds up the game (a speech lasts a NUMBER of ticks, never the stream's `finished`), so it has to come from the
## pack that holds the clip. The legacy pack's are the importer's measurements of the original (`VoiceIndex.durations`); a pack in the data form's come from here:
##   MEASURED  `measure(stream)`: `AudioStream.get_length()` of the loaded file, rounded UP to whole ticks (`ticks_of_seconds`). The same file
##             always gives the same number, and nothing is played to find it out. Done when `Packs` mounts the pack (`Pack.clip_ticks`).
##   STATED    the pack's own `audio/lengths.json`, `{"voice": {"clip name": ticks}}` (the kinds are `Packs.CLIP_KINDS`): the length the
##             pack WANTS, which wins over the measured one. A longer number leaves a pause after the line; a shorter one cuts the clip off.
## Only a speech is waited for today (`Audio`); no sound or song holds up play, but all three kinds get a length so that a pack tool can show
## and check them alike.
##
## `warnings(pack)` is the validation that the pack tools call: a clip nothing can measure, a stated length far from the measured one, a
## `lengths.json` that makes no sense. Warnings, not errors: a student may mean a long pause.
##
## Teaches: a measurement turned into a number once, on the edge, so that the rules only ever read a number; and rounding that is
## stated, not accidental.

## The file of a pack that states lengths by hand.
const STATED_REL := "audio/lengths.json"
## A stated length is "far" from the measured one when it differs by more than this many seconds ...
const FAR_SECONDS := 1.0
## ... or by more than this part of the measured length.
const FAR_FRACTION := 0.25
## `get_length()` is a float: a clip that is 2 s long to the sample can come out as 2.0000000001 s and would round up to a tick too many.
## The measured number of ticks may be this much over a whole number without the next one being taken (a millionth of a tick).
const ROUNDING_SLACK := 1.0e-6


## Ticks of 1/73 s in `seconds`, rounded up. `ROUNDING_SLACK` keeps a float's last bit from adding a tick.
static func ticks_of_seconds(seconds: float) -> int:
	return ceili(seconds * TickMeter.TICKS_PER_SECOND - ROUNDING_SLACK)


## The length of `stream` in whole ticks (at least 1), or -1 when it has no measurable length (null, or a stream that says 0 seconds).
static func measure(stream: AudioStream) -> int:
	if stream == null:
		return -1
	var seconds := stream.get_length()
	if seconds <= 0.0 or is_nan(seconds) or is_inf(seconds):
		return -1
	return maxi(ticks_of_seconds(seconds), 1)


## Is `stated` ticks far from `measured` ticks (more than `FAR_SECONDS`, or more than `FAR_FRACTION` of the measured length)?
static func is_far(stated: int, measured: int) -> bool:
	var difference := absi(stated - measured)
	return difference > FAR_SECONDS * TickMeter.TICKS_PER_SECOND or difference > FAR_FRACTION * measured


## The stated lengths of `pack`: kind -> {clip name -> ticks}, with the entries that make no sense left out. `problems`, when given,
## gets one sentence for each of those (and for a file that is not the right shape).
static func stated(pack: Pack, problems: Array[String] = []) -> Dictionary:
	var found := {}
	if not pack.has(STATED_REL):
		return found
	var parsed: Variant = pack.read_json(STATED_REL)
	if not parsed is Dictionary:
		problems.append("%s must be a JSON object {\"voice\": {\"clip name\": ticks}}" % STATED_REL)
		return found
	for kind: String in parsed:
		if not Packs.CLIP_KINDS.has(StringName(kind)):
			problems.append("%s: '%s' is not a kind of clip (%s)" % [STATED_REL, kind, ", ".join(Packs.CLIP_KINDS)])
			continue
		if not parsed[kind] is Dictionary:
			problems.append("%s: '%s' must be an object {\"clip name\": ticks}" % [STATED_REL, kind])
			continue
		var lengths := {}
		for clip_name: String in parsed[kind]:
			var value: Variant = parsed[kind][clip_name]
			if (value is float or value is int) and value >= 1 and value == floorf(value):
				lengths[StringName(clip_name)] = int(value)
			else:
				problems.append("%s: %s '%s' must be a whole number of ticks, 1 or more (1 tick = 1/73 s), not %s" % [STATED_REL, kind, clip_name, str(value)])
		found[StringName(kind)] = lengths
	return found


## What is doubtful about the lengths of the clips of `pack`, one sentence each; empty when all is well. For the pack tools' validation.
## Every clip file is looked at (`audio/<kind>/*.ogg`): one that cannot be read, or has no measurable length, is reported; so is a stated
## length that is far from the measured one (`is_far`), one for a clip the pack does not hold, and a `lengths.json` that is malformed.
static func warnings(pack: Pack) -> Array[String]:
	var found: Array[String] = []
	var stated_lengths := stated(pack, found)
	for kind in Packs.CLIP_KINDS:
		var held := {}
		for file in pack.files_in("audio/%s" % kind, "ogg"):
			var clip_name := StringName(file.get_basename())
			held[clip_name] = true
			var measured := pack.measured_clip_ticks(kind, clip_name)
			if measured < 0:
				found.append("audio/%s/%s: has no measurable length (not an OGG Vorbis file, or it is empty), so the game cannot wait for it" % [kind, file])
				continue
			var own: int = (stated_lengths.get(kind, {}) as Dictionary).get(clip_name, -1)
			if own >= 0 and is_far(own, measured):
				found.append("%s: %s '%s' states %d ticks (%.2f s) but the file lasts %d ticks (%.2f s); %s" % [
						STATED_REL, kind, clip_name, own, TickMeter.seconds(own), measured, TickMeter.seconds(measured),
						"the clip is cut off" if own < measured else "silence follows the clip"])
		for clip_name: StringName in stated_lengths.get(kind, {}):
			if not held.has(clip_name):
				found.append("%s: %s '%s' states a length but the pack has no audio/%s/%s.ogg" % [STATED_REL, kind, clip_name, kind, clip_name])
	return found
