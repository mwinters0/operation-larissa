class_name Durations
extends RefCounted
## Every duration that holds up play, as DATA the rules read: how long a supply station's door takes, where the balloon
## goes, how long a tank-loss dissolve, a message, a fade, the log scan last. `data/rules/durations.json` holds the original's numbers
## (the legacy pack); a rule asks for one by its path, `Durations.at("dissolve.ticks")`, and a view is TOLD the number and fits its drawing
## to it (`elapsed / ticks`): it never decides how long a step is.
##
## The layering itself (the files down the chain, the merge, the walk that checks a pack's file) is `LayeredJson`, shared with `Tuning`.
##
## Teaches: a constant that became data. The rules stay plain objects (no autoload, no scene, no `ResourceLoader` on a `.tres`): the
## file is plain JSON read with `FileAccess` and `JSON`, so a student's pack can state its own lengths in a text file, and a longer
## dock is a change to a number, not to a script. A key the pack leaves out keeps the base game's number. The default file
## reproduces the original exactly (`tests/engine/test_durations.gd`), so fidelity and the pinned digests do not move.
##
## Units: the file says in each key what it counts. Most are ticks of the original's 73 Hz timer (`TickMeter`); a station trip counts
## game ticks (the 12.17 Hz `GameClock`, `StationSequence`); positions are integer window pixels.

## The project's file: the original's numbers.
const BASE_PATH := "res://data/rules/durations.json"

## The pack-relative path of a pack's durations (a few keys are enough: they are laid over the base key by key).
const PACK_PATH := "rules/durations.json"

## Files laid over the base and the mounted packs' files, later ones winning key by key: a test (or a tool) puts a file of its own here
## and calls `read_files`.
static var extra_files: Array[String] = []

static var _table: Dictionary = {}
static var _loaded: bool = false


## The files that make up the durations: the base first, then `rules/durations.json` of each pack of the chain (the bottom pack first, so that the chosen
## pack has the last word), then `extra_files`. `Packs` calls `read_files` whenever the chain changes.
static func files() -> Array[String]:
	return LayeredJson.files(BASE_PATH, PACK_PATH, extra_files)


## Read the files again (after `extra_files` changed). (Not called `reload`: `Durations.reload()` would be the SCRIPT's own method.)
static func read_files() -> void:
	_table = LayeredJson.read_all(files(), "Durations")
	_loaded = true


## Back to the base game's numbers.
static func use_base() -> void:
	extra_files = []
	read_files()


## The whole number at `path` ("station.dock.opening_ticks"). A missing or non-numeric key is a bug in the data: it is reported and 0 is
## returned, so a pack that forgot one is told which, not left with a mysterious wait.
static func at(path: String) -> int:
	var value: Variant = _find(path)
	if value is float or value is int:
		return int(value)
	push_error("Durations: no number at '%s'" % path)
	return 0


## The whole numbers in the list at `path` ("news.group_pauses").
static func list_at(path: String) -> Array[int]:
	var found: Array[int] = []
	var value: Variant = _find(path)
	if value is Array:
		for entry: Variant in value:
			found.append(int(entry))
	else:
		push_error("Durations: no list at '%s'" % path)
	return found


# --- checking a pack's file ----------------------------------------------------------------------------------------------------

## The keys whose smallest sensible value is 1: the rules take `maxi(value, 1)` of them (a step cannot take no time at all).
const AT_LEAST_ONE: Array[String] = ["fade.ticks", "log_scan.ticks_per_picture", "sign_in.scan_ticks_per_picture", "sign_in.scan_sweeps"]
## A wait longer than this many ticks (ten minutes) is probably a typo.
const LONG_TICKS := 73 * 600
## A position this far outside the 640 x 400 window (a whole window) is probably a typo.
const FAR_OUTSIDE := 640

## What is wrong with a pack's `rules/durations.json` (`layer`, parsed): one sentence per problem into `errors` (the file would be read wrongly or
## the rules would run on nonsense) and `warnings` (odd, but it plays). Only keys of the base file are known (a typo would be silently ignored
## otherwise); a section stays a section and a number a whole number; ticks are 0 or more (1 or more where the rules would clamp, `AT_LEAST_ONE`),
## `pixels_per_tick` 1 or more; a station drives forward (`from_x` not above `to_x`) and the balloon rises (`from_y` not below `to_y`).
static func check(layer: Variant, errors: Array[String], warnings: Array[String]) -> void:
	if not layer is Dictionary:
		errors.append("rules/durations.json must be a JSON object laid over data/rules/durations.json")
		return
	var base := LayeredJson.read(BASE_PATH, "Durations")
	LayeredJson.walk(base, layer, LayeredJson.Check.new("duration", BASE_PATH, "whole numbers", _check_number), errors, warnings)
	var merged := base.duplicate(true)
	LayeredJson.merge(merged, layer)
	var stations := LayeredJson.dict(layer.get("station"))
	for trip in ["launch", "dock"]:
		var drive := LayeredJson.dict(LayeredJson.dict(merged.get("station")).get(trip))
		if stations.has(trip) and LayeredJson.is_number(drive.get("from_x")) and LayeredJson.is_number(drive.get("to_x")):
			if drive["from_x"] > drive["to_x"]:
				errors.append("station.%s: from_x (%d) is right of to_x (%d): the sub drives to the right" % [trip, drive["from_x"], drive["to_x"]])
			elif drive["from_x"] == drive["to_x"]:
				warnings.append("station.%s: from_x and to_x are the same: the sub does not drive" % trip)
	var balloon := LayeredJson.dict(LayeredJson.dict(merged.get("station")).get("balloon"))
	if stations.has("balloon") and LayeredJson.is_number(balloon.get("from_y")) and LayeredJson.is_number(balloon.get("to_y")):
		if balloon["from_y"] < balloon["to_y"]:
			errors.append("station.balloon: from_y (%d) is above to_y (%d): the balloon rises" % [balloon["from_y"], balloon["to_y"]])
		elif balloon["from_y"] == balloon["to_y"]:
			warnings.append("station.balloon: from_y and to_y are the same: the balloon does not rise")


static func _check_number(value: Variant, path: String, errors: Array[String], warnings: Array[String]) -> void:
	if not LayeredJson.check_whole(value, path, errors):
		return
	var leaf := path.get_slice(".", path.get_slice_count(".") - 1)
	var is_position := leaf in ["from_x", "to_x", "x", "from_y", "to_y"]
	if is_position:
		if absf(value) > FAR_OUTSIDE * 2:
			warnings.append("%s is %d: more than a window away from the screen" % [path, value])
		return
	var smallest := 1 if (leaf == "pixels_per_tick" or AT_LEAST_ONE.has(path)) else 0
	if value < smallest:
		errors.append("%s is %d: it must be %d or more" % [path, value, smallest])
	elif leaf.ends_with("ticks") and value > LONG_TICKS:
		warnings.append("%s is %d ticks (%.0f s): longer than ten minutes" % [path, value, TickMeter.seconds(int(value))])


static func _find(path: String) -> Variant:
	if not _loaded:
		read_files()
	var node: Variant = _table
	for key in path.split("."):
		if node is Dictionary and (node as Dictionary).has(key):
			node = (node as Dictionary)[key]
		else:
			return null
	return node
