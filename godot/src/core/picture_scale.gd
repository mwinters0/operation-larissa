class_name PictureScale
extends RefCounted
## The scale a run draws its pictures at, and why. The game's unit stays 640 x 400; a pack that carries 4x art says `"picture_scale": 4` in its manifest (`Pack.picture_scale`), its picture files are four times larger than they are drawn, and a
## picture of such a pack is a `ScaledTexture` that reports the size of the original's picture (`Pictures`). A run draws EVERY picture at ONE scale, so a picture of a pack of another scale is never mixed in.
##
## THE RUN'S SCALE is the highest scale whose packs of the chain, TOGETHER, would draw every picture key the chain needs (`PackNeeds.picture_keys`: the closure that start-up checks, not a second list); several packs of one
## scale stack (a 4x skin and a 4x tile pack are one set). A key is covered by a set when the resolver `Pictures` draws with (`Pictures.unanswered`: its rows and its alias walk, restricted to the set's packs) answers it, so "covered" means "would
## draw", and a row whose file is missing or whose alias leads nowhere in the set is no cover. Scale 1 is the fallback: when no higher set covers, the run draws at scale 1 (the packs that declare no scale). A key that no pack of the chain
## answers, at any scale, is a gap that is the same at every scale (`PackNeeds` says it), so it does not count against a set. The packs of another scale than the run's contribute no picture (their other content, sectors, tuning, mods, sounds, stays): `Decision.packs`.
##
## `decide` is a pure function of the chain and the keys it is given (it reads no run state), so the run's scale has no other copy than the `Decision` `Packs.picture_decision` keeps for the chain in use. That decision is made again after every change of
## the chain (start, a pack switch, a lent chain, a mod refused), and is made from the one scan of what the chain needs. A set that does not cover is a `Shortfall`: `Pictures` tells it once per run (`TroubleLog`), and `PackCheck` reports it with every
## missing key; both ask `Shortfall.text`. Every picture of a run at scale N is a `ScaledTexture` of N (`Pictures` makes them from the packs of `Decision.packs` only), so a consumer that reads the scale of its picture and one that reads the decision agree.
##
## Teaches: a decision derived from the data by one pure function whose inputs are arguments, so that the builder of the state it feeds can call it from anywhere without a circle, instead of a flag that each place that changes the chain would have to set.

## How many missing keys the line the game tells names.
const KEYS_SHOWN := 5


## A set of packs at one scale above 1 that lacks pictures the game needs.
class Shortfall extends RefCounted:
	## The scale the packs declare.
	var scale := 1
	## The packs of the chain that declare it, top of the chain first.
	var pack_ids: Array[StringName] = []
	## Every needed key that the set would not draw, sorted.
	var missing: Array[String] = []
	## How many keys the chain needs that some pack answers (what the set is measured against).
	var needed := 0
	## The scale the run draws at instead, and the packs that declare it.
	var drawn_scale := 1
	var drawn_ids: Array[StringName] = []

	## The sentence for the log or a report (the caller puts its own tag in front): the packs, how many keys they lack, `shown` of them (all when `shown` is below 0), and what the game draws instead. One text for the game and for `PackCheck`.
	func text(shown := KEYS_SHOWN) -> String:
		var names := PackedStringArray()
		for key in missing:
			if shown >= 0 and names.size() >= shown:
				break
			names.append(key)
		var rest := missing.size() - names.size()
		var held := "%s (picture scale %d) %s no picture for %d of the %d pictures the game needs (%s%s)" % [
				PictureScale.packs_text(pack_ids), scale, "has" if pack_ids.size() == 1 else "have", missing.size(), needed, ", ".join(names), "" if rest == 0 else " and %d more" % rest]
		var instead := "the game draws the pictures of scale %d (%s) instead" % [drawn_scale, PictureScale.packs_text(drawn_ids)] if not drawn_ids.is_empty() \
				else "no pack of the chain draws at scale %d, so nothing is drawn where those pictures are asked" % drawn_scale
		return "%s, so the pictures of %s are not drawn and %s" % [held, "that pack" if pack_ids.size() == 1 else "those packs", instead]


## What `decide` found out about one chain. Made whole by `decide` and not changed after.
class Decision extends RefCounted:
	## The scale the run draws at: 1 or the highest scale of a set that covers.
	var scale := 1
	## The packs of the chain that declare `scale`, top of the chain first: the only ones whose pictures the run draws.
	var packs: Array[Pack] = []
	## Every set above scale 1 that does not cover, highest scale first.
	var shortfalls: Array[Shortfall] = []
	## `shortfalls` told, one sentence each (`Shortfall.text`), for `Pictures` to tell in every run that asks for a picture.
	var texts: Array[String] = []

	## The shortfall `pack_id`'s pack is part of, or null.
	func shortfall_of(pack_id: StringName) -> Shortfall:
		for each in shortfalls:
			if each.pack_ids.has(pack_id):
				return each
		return null


## The decision for `chain` (the chosen pack first) given `keys`, the picture keys the chain needs (`PackNeeds.picture_keys`, which only a caller that found a pack of a higher scale in the chain, `has_higher`, need compute: pass an empty list otherwise).
## Pure: it reads the chain's packs and their picture tables, nothing of the run.
static func decide(chain: Array[Pack], keys: Array[String]) -> Decision:
	var decision := Decision.new()
	var scales: Array[int] = []
	for each in chain:
		if each.picture_scale > 1 and not scales.has(each.picture_scale):
			scales.append(each.picture_scale)
	if scales.is_empty():
		decision.packs = packs_at(chain, 1)
		return decision
	scales.sort()
	scales.reverse()
	var needs := needed(chain, keys)
	var covering := 1
	var short: Array[Shortfall] = []
	for scale in scales:
		var missing := _missing(chain, scale, needs)
		if missing.is_empty():
			covering = maxi(covering, scale)
		else:
			var found := Shortfall.new()
			found.scale = scale
			found.pack_ids = _ids(chain, scale)
			found.missing = missing
			found.needed = needs.size()
			short.append(found)
	decision.scale = covering
	decision.packs = packs_at(chain, covering)
	for found in short:
		found.drawn_scale = covering
		found.drawn_ids = _ids(chain, covering)
		decision.texts.append(found.text())
	decision.shortfalls = short
	return decision


## Does a pack of `chain` declare a scale above 1 (is there anything to decide)?
static func has_higher(chain: Array[Pack]) -> bool:
	return chain.any(func(each: Pack) -> bool: return each.picture_scale > 1)


## The packs of `chain` that declare `scale`, top of the chain first.
static func packs_at(chain: Array[Pack], scale: int) -> Array[Pack]:
	var found: Array[Pack] = []
	for each in chain:
		if each.picture_scale == scale:
			found.append(each)
	return found


## The keys of `keys` that the packs of `chain`, all scales together, would draw (`Pictures.unanswered`), sorted as given: what a set is measured against. A key no pack answers is a gap that is the same at every scale (`PackNeeds` says it) and counts against no set.
static func needed(chain: Array[Pack], keys: Array[String]) -> Array[String]:
	var held: Array[String] = []
	for key in keys:
		if Pictures.unanswered(key, chain).is_empty():
			held.append(key)
	return held


## "pack 'a'" or "packs 'a', 'b'".
static func packs_text(ids: Array[StringName]) -> String:
	var quoted := PackedStringArray()
	for id in ids:
		quoted.append("'%s'" % id)
	return "%s %s" % ["pack" if ids.size() == 1 else "packs", ", ".join(quoted)]


## The keys of `keys` that the packs of `chain` at `scale` would not draw (`Pictures.unanswered` over that set alone: an alias is followed inside it).
static func _missing(chain: Array[Pack], scale: int, keys: Array[String]) -> Array[String]:
	var set := packs_at(chain, scale)
	var lacking: Array[String] = []
	for key in keys:
		if not Pictures.unanswered(key, set).is_empty():
			lacking.append(key)
	return lacking


## The ids of the packs of `chain` that declare `scale`, top of the chain first.
static func _ids(chain: Array[Pack], scale: int) -> Array[StringName]:
	var ids: Array[StringName] = []
	for each in packs_at(chain, scale):
		ids.append(each.id)
	return ids
