class_name Pictures
extends RefCounted
## The one lookup that turns a picture KEY (`ui_picture/title_sky`, `frame/sub_00`, `background/bg_s03_07`) into a texture: the chain's picture tables (`pictures.json`, `PictureTable`), the top of the chain first.
##
## CHOOSING A PICTURE BELONGS TO THE PACK. The first pack of the chain whose table has a row for the key answers; a pack laid over another that redraws a picture replaces it, and a pack that does not say leaves it to the pack under it. A row names a file of its own pack
## (drawn at its size, or at `1 / scale` of it through `ScaledTexture`) or ANOTHER KEY (`{"alias": key}`): an alias is resolved from the top of the chain again, whichever pack holds the row, so a pack above that redraws the target redraws every alias of it,
## and one file serves many names. A row that does not resolve (a file the pack does not hold or that is no PNG, an alias to a key no pack holds, aliases that go round in a circle) is left out, as if its pack had no row for the key, so the packs under it answer;
## it is told ONCE per run (`TroubleLog.session`), naming the pack, the key and what is shown instead.
##
## THE CACHE is per chain: an answer is kept until the chain changes (`forget`, from `Assets.forget_folders` by `Catalog.packs_changed`). `epoch` counts the changes and `events.changed` announces them, so a holder of an answer (`PictureRef`) asks again. A skin changes no picture.
##
## BRIDGE (deleted with the path lookups, when every pack has a table and the skins no longer map pictures): a pack WITHOUT a `pictures.json` answers as it always has, from its `pictures/<kind>/<name>.png` folder and from the files whose names make the key (`Assets.pack_key_files`),
## and `overlaid` is what the packs laid over another say, for `GameSkin.picture`, which still puts a skin's own pictures between them and the base game. Everything marked BRIDGE goes together.
##
## Teaches: a layered lookup with a re-entrant step (an alias asks the whole lookup again), a visited list to stop a cycle, and failures that degrade to the next layer and say so once.

## The lines this lookup tells start with this.
const TAG := "[pictures]"
## The most aliases one lookup follows (a chain longer than this is a pack's mistake; a cycle is found before it).
const MAX_ALIAS_DEPTH := 16

## The signal of a change of the chain's pictures. (A class cannot have a static signal: this object has it.)
static var events := PictureEvents.new()
## How many times the answers were forgotten.
static var epoch := 0

## key -> Texture2D, or null for a key nothing holds.
static var _answers: Dictionary = {}
## BRIDGE: key -> the answer of the packs laid over another only (`overlaid`).
static var _overlaid: Dictionary = {}
## "<pack id>/<file>@<scale>" -> the `ScaledTexture` of a row, so the same row gives the same object.
static var _scaled: Dictionary = {}
## How many causes of trouble were met (told or told before): lets a lookup see that what it followed failed for a cause already told.
static var _troubles := 0


class PictureEvents extends RefCounted:
	## The chain's pictures may be other ones now: ask again.
	signal changed


## The picture of `key` the chain holds, or null when no pack does.
static func resolve(key: String) -> Texture2D:
	if not _answers.has(key):
		_answers[key] = _find(key, [], false)
	return _answers[key]


## Does a pack of the chain hold a picture for `key`?
static func has(key: String) -> bool:
	return resolve(key) != null


## BRIDGE: what the packs laid over another say for `key` (their rows, or the `pictures/` folder of a pack with no table), before any skin: the first layer of `GameSkin.picture`.
static func overlaid(key: String) -> Texture2D:
	if not _overlaid.has(key):
		_overlaid[key] = _find(key, [], true)
	return _overlaid[key]


## Forget every answer (the chain changed). `epoch` moves and `events.changed` is emitted, so what holds an answer asks again.
static func forget() -> void:
	_answers = {}
	_overlaid = {}
	_scaled = {}
	epoch += 1
	events.changed.emit()


## The sentence that says no pack holds the picture `key` that data names, for whoever holds it (`PictureRef`).
static func unheld_line(key: String) -> String:
	var ids := ", ".join(PackedStringArray(Packs.chain_ids().map(func(id: StringName) -> String: return String(id))))
	return "%s no pack of the chain (%s) has a picture for '%s' (a row of its pictures.json), so nothing is drawn where the game shows it" % [TAG, ids, key]


# --- the lookup ---------------------------------------------------------------------------------------------------------

## `key` down the chain; `asking` is the keys whose rows are being followed (an alias asks again from the top and meets a key it is already asking for when the aliases go round).
## `only_overlays` (BRIDGE): the packs laid over another only, and no files by name.
static func _find(key: String, asking: Array[String], only_overlays: bool) -> Texture2D:
	if key.is_empty():
		return null
	var now: Array[String] = asking.duplicate()
	now.append(key)
	for each in Packs.chain():
		var found := _row(each, key, now, only_overlays)
		if found != null:
			return found
	return null


## The picture `pack`'s row for `key` gives, or null when the pack has no row or its row does not resolve (told once). `asking` ends with `key`.
static func _row(pack: Pack, key: String, asking: Array[String], only_overlays: bool) -> Texture2D:
	var table := pack.picture_table()
	if not table.present:
		return _bridge_row(pack, key, only_overlays)                  # BRIDGE
	if only_overlays and pack.base == &"":
		return null
	if table.files.has(key):
		return _file_row(pack, table, key)
	if not table.aliases.has(key):
		return null
	var target: String = table.aliases[key]
	if asking.has(target) or asking.size() > MAX_ALIAS_DEPTH:
		_tell("%s pack '%s': pictures.json: the aliases %s go round in a circle, so the row of '%s' is left out and the packs under it answer for it, if any do" % [
				TAG, pack.id, " -> ".join(PackedStringArray(asking + [target])), key])
		return null
	var met := _troubles
	var found := _find(target, asking, false)
	if found == null and _troubles == met:                         # (a cause met on the way, a circle or a file, has been told: not once more as a dangling alias)
		_tell("%s pack '%s': pictures.json: '%s' is an alias of '%s', which no pack of the chain has a picture for, so that row is left out and the packs under it answer for '%s', if any do" % [
				TAG, pack.id, key, target, key])
	return found


## The picture of the file row `key` of `pack`, drawn at `1 / scale` of its size when the row says so.
static func _file_row(pack: Pack, table: PictureTable, key: String) -> Texture2D:
	var rel: String = table.files[key]
	var texture := pack.texture(rel)
	if texture == null:
		_tell("%s pack '%s': pictures.json gives '%s' the file %s, which %s, so that row is left out and the packs under it answer for '%s', if any do" % [
				TAG, pack.id, key, rel, "is not a PNG picture the game can read" if pack.has(rel) else "the pack does not hold", key])
		return null
	var scale := table.scale_of(key)
	if scale <= 1:
		return texture
	var held := "%s/%s@%d" % [pack.id, rel, scale]
	if not _scaled.has(held):
		_scaled[held] = ScaledTexture.of(texture, scale)
	return _scaled[held]


## BRIDGE: a pack with no table: its `pictures/<key>.png`, and (not for `only_overlays`) the file whose name makes `key`.
static func _bridge_row(pack: Pack, key: String, only_overlays: bool) -> Texture2D:
	var from_folder := pack.texture("pictures/%s.png" % key)
	if from_folder != null or only_overlays:
		return from_folder
	var rel: String = Assets.pack_key_files(pack).get(key, "")
	return pack.texture(rel) if not rel.is_empty() else null


static func _tell(line: String) -> void:
	_troubles += 1
	TroubleLog.session.tell(line)
