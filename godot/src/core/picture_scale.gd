class_name PictureScale
extends RefCounted
## The scale a run draws its pictures at, and why. The game's unit stays 640 x 400; a pack that carries 4x art says `"picture_scale": 4` in its manifest (`Pack.picture_scale`), its picture files are four times larger than they are drawn, and a
## picture of such a pack is a `ScaledTexture` that reports the size of the original's picture (`Pictures`). A run draws EVERY picture at ONE scale, so a picture of a pack of another scale is never mixed in.
##
## THE RUN'S SCALE is the highest scale whose packs of the chain, TOGETHER, hold a row for every picture key the chain needs (`PackNeeds.picture_keys`: the closure that start-up checks, not a second list); several packs of one
## scale stack (a 4x skin and a 4x tile pack are one set). Scale 1 is the fallback: when no higher set covers, the run draws at scale 1 (the packs that declare no scale). A key that no pack of the chain holds, at any scale, is a gap
## that is the same at every scale (`PackNeeds` says it), so it does not count against a set. The packs of another scale than the run's contribute no picture (their other content, sectors, tuning, mods, sounds, stays): `Packs.picture_packs`.
##
## `decide` is the one function that makes this decision, from a chain alone. `Packs` makes it every time it builds the lookups of a chain (`Packs.picture_decision`), so every change of the chain (start, a pack switch, a lent chain,
## a mod) decides again, and the run's scale has no other copy. A set that does not cover is a `Shortfall`: `Pictures` tells it once per run (`TroubleLog`), and `PackCheck` reports it with every missing key; both ask `Shortfall.line`.
##
## Teaches: a decision derived from the data by one pure function, called by the one builder of the state it feeds, instead of a flag that each place that changes the chain would have to set.

## The largest `picture_scale` of a pack (`ScaledTexture`'s own range is 1 to this).
const MAX := 16
## The lines this decision gives start with this.
const TAG := "[pictures]"
## How many missing keys the line the game tells names.
const KEYS_SHOWN := 5


## A set of packs at one scale above 1 that lacks pictures the game needs.
class Shortfall extends RefCounted:
	## The scale the packs declare.
	var scale := 1
	## The packs of the chain that declare it, top of the chain first.
	var pack_ids: Array[StringName] = []
	## Every needed key that no pack of the set has a row for, sorted.
	var missing: Array[String] = []
	## How many keys the chain needs that some pack holds (what the set is measured against).
	var needed := 0
	## The scale the run draws at instead, and the packs that declare it.
	var drawn_scale := 1
	var drawn_ids: Array[StringName] = []

	## The sentence for the log or a report: the packs, how many keys they lack, `shown` of them (all when `shown` is below 0), and what the game draws instead. One text for the game and for `PackCheck`.
	func line(shown := KEYS_SHOWN) -> String:
		var names := PackedStringArray()
		for key in missing:
			if shown >= 0 and names.size() >= shown:
				break
			names.append(key)
		var rest := missing.size() - names.size()
		var held := "%s (picture scale %d) %s no row for %d of the %d pictures the game needs (%s%s)" % [
				PictureScale.packs_text(pack_ids), scale, "has" if pack_ids.size() == 1 else "have", missing.size(), needed, ", ".join(names), "" if rest == 0 else " and %d more" % rest]
		var instead := "the game draws the pictures of scale %d (%s) instead" % [drawn_scale, PictureScale.packs_text(drawn_ids)] if not drawn_ids.is_empty() \
				else "no pack of the chain draws at scale %d, so nothing is drawn where those pictures are asked" % drawn_scale
		return "%s %s, so the pictures of %s are not drawn and %s" % [TAG, held, "that pack" if pack_ids.size() == 1 else "those packs", instead]


## What `decide` found out about one chain.
class Decision extends RefCounted:
	## The scale the run draws at: 1 or the highest scale of a set that covers.
	var scale := 1
	## Every set above scale 1 that does not cover, highest scale first.
	var shortfalls: Array[Shortfall] = []
	## The picture keys the sets were measured against (`needed`); empty when no pack declares a scale above 1 (nothing was measured).
	var needed: Array[String] = []

	var _lines: Array[String] = []

	## The lines that tell `shortfalls`, for `Pictures` (made once: every lookup of a run asks).
	func lines() -> Array[String]:
		if _lines.is_empty():
			for each in shortfalls:
				_lines.append(each.line())
		return _lines

	## The shortfall `pack_id`'s pack is part of, or null.
	func shortfall_of(pack_id: StringName) -> Shortfall:
		for each in shortfalls:
			if each.pack_ids.has(pack_id):
				return each
		return null


## Is `value` the number a manifest's `picture_scale` may be (a whole number from 1 to `MAX`)?
static func is_scale(value: Variant) -> bool:
	return (value is float or value is int) and int(value) == value and int(value) >= 1 and int(value) <= MAX


## The decision for `chain` (the chosen pack first). A chain whose packs all draw at scale 1 is decided without reading anything: `PackNeeds` runs only when some pack declares a higher scale, once per decision.
static func decide(chain: Array[Pack]) -> Decision:
	var decision := Decision.new()
	var scales: Array[int] = []
	for each in chain:
		if each.picture_scale > 1 and not scales.has(each.picture_scale):
			scales.append(each.picture_scale)
	if scales.is_empty():
		return decision
	scales.sort()
	scales.reverse()
	var keys := needed(chain)
	decision.needed = keys
	var covering := 1
	var short: Array[Shortfall] = []
	for scale in scales:
		var missing := _missing(chain, scale, keys)
		if missing.is_empty():
			covering = maxi(covering, scale)
		else:
			var found := Shortfall.new()
			found.scale = scale
			found.pack_ids = _ids(chain, scale)
			found.missing = missing
			found.needed = keys.size()
			short.append(found)
	decision.scale = covering
	for found in short:
		found.drawn_scale = covering
		found.drawn_ids = _ids(chain, covering)
	decision.shortfalls = short
	return decision


## The picture keys the game needs of `chain` that some pack of it holds a row for, at any scale, sorted: `PackNeeds.picture_keys` less the keys no pack holds (a gap that is the same at every scale: `PackNeeds` says it).
static func needed(chain: Array[Pack]) -> Array[String]:
	return _held(chain, PackNeeds.picture_keys(chain))


## "pack 'a'" or "packs 'a', 'b'".
static func packs_text(ids: Array[StringName]) -> String:
	var quoted := PackedStringArray()
	for id in ids:
		quoted.append("'%s'" % id)
	return "%s %s" % ["pack" if ids.size() == 1 else "packs", ", ".join(quoted)]


## The keys of `keys` that some pack of `chain` holds a row for, at any scale.
static func _held(chain: Array[Pack], keys: Array[String]) -> Array[String]:
	var held: Array[String] = []
	for key in keys:
		if chain.any(func(each: Pack) -> bool: return each.picture_table().has(key)):
			held.append(key)
	return held


## The keys of `keys` that no pack of `chain` at `scale` has a row for.
static func _missing(chain: Array[Pack], scale: int, keys: Array[String]) -> Array[String]:
	var tables: Array[PictureTable] = []
	for each in chain:
		if each.picture_scale == scale:
			tables.append(each.picture_table())
	var lacking: Array[String] = []
	for key in keys:
		if not tables.any(func(table: PictureTable) -> bool: return table.has(key)):
			lacking.append(key)
	return lacking


## The ids of the packs of `chain` that declare `scale`, top of the chain first.
static func _ids(chain: Array[Pack], scale: int) -> Array[StringName]:
	var ids: Array[StringName] = []
	for each in chain:
		if each.picture_scale == scale:
			ids.append(each.id)
	return ids
