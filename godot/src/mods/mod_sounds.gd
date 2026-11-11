class_name ModSounds
extends RefCounted
## The sounds a problem-screen mod may ask for: NAMES, never audio. The script returns `{"sounds": ["diagram_pop", ...]}` beside (or instead of) its draw list (API version `ModSpec.DRAWS_THE_GAME_API_VERSION`); the game keeps what is
## exactly one `sound` name of the chain (`SfxCatalog.can_play`: one of the original's effects by its name in `names/original.json`, or a file `audio/sound/<name>.ogg` of any pack of the chain, the mod's own pack included),
## and `ModDiagram` plays it through the same door every other sound of the screen takes (`sfx_requested`, `Audio.play_sfx`). A mod holds no stream and no player, and it cannot stop, loop or mix anything: it can only ask.
##
## A mod that asks is BOUNDED, because a sound is something the player hears and a loop could make a screen unbearable (or hide the effects that tell the player right from wrong): a call is heard for at most `MAX_PER_CALL` names, and
## the screen holds a bucket of `BURST` sounds that refills `PER_SECOND` a second (real time: nothing of the rules reads it); a name that is not a sound, or that finds the bucket empty, is dropped and counted (`dropped`), the
## names a hostile mod tries cost a token each before the chain is asked (so a list of a thousand made-up names asks the chain `BURST` times and no more). A sound never holds up play and never changes a length (the screen's
## durations are the data's, `ProblemFlow`); what a mod cannot do is silence the game's own cues: `correct`, `wrong` and the calculator's keys come from the flow and the inputs.
##
## Teaches: letting a stranger's code cause an effect by letting it name one from a closed list, and bounding the rate with a token bucket whose clock can be replaced, so a test needs no waiting.

## The most names one answer of the script is heard for (the rest are dropped).
const MAX_PER_CALL := 4
## The sounds that may play in a burst, and how many are given back each second.
const BURST := 8
const PER_SECOND := 8.0

## The sounds dropped so far on this screen (not a name of the chain, too many in a call, or the bucket was empty).
var dropped := 0
## The sounds accepted so far on this screen.
var accepted := 0
## What the last `accept` left out, for the warning `ModDiagram` gives: the names that are no sound of the chain (as text), and whether sounds were left out for want of a token or for the limit of a call.
var refused: Array[String] = []
var too_many := false
## The time in milliseconds: the engine's by default, a test's own to make the bucket refill without waiting.
var now: Callable = func() -> int: return Time.get_ticks_msec()

var _tokens := float(BURST)
var _last := -1


## The names of `raw` (what the script returned under `sounds`) that are heard now, in order: an Array of at most `MAX_PER_CALL` Strings, each a sound of the chain and each with a token in the bucket. Anything else is dropped; a `raw`
## that is not an Array gives none.
func accept(raw: Variant) -> Array[StringName]:
	var heard: Array[StringName] = []
	refused = []
	too_many = false
	if not raw is Array:
		return heard
	_refill()
	var list: Array = raw
	for i in list.size():
		if i >= MAX_PER_CALL:
			dropped += list.size() - i
			too_many = true
			break
		var name: Variant = list[i]
		if not (name is String or name is StringName) or not NameRegistry.is_valid_name(String(name)):
			dropped += 1
			refused.append(str(name).left(48))
			continue
		if _tokens < 1.0:
			dropped += 1
			too_many = true
			continue
		_tokens -= 1.0                                           # (a made-up name costs a token too: the chain is asked for it only now)
		if Catalog.sfx_catalog().can_play(StringName(name)):
			heard.append(StringName(name))
			accepted += 1
		else:
			dropped += 1
			refused.append(String(name))
	return heard


func _refill() -> void:
	var time: int = now.call()
	if _last >= 0:
		_tokens = minf(float(BURST), _tokens + float(maxi(time - _last, 0)) / 1000.0 * PER_SECOND)
	_last = time
