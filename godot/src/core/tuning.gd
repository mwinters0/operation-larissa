class_name Tuning
extends RefCounted
## The values the rules run on: the sub's speeds and pictures, the air and ink limits, the screen of the respawn point, the waits of the
## math triggers and of the combination lock, the longest a creature script may run. `data/rules/tuning.json` holds the original's
## numbers; a pack may lay its own `rules/tuning.json` over it, key by key (`LayeredJson`, the way `Durations` is laid).
##
## A `Tuning` is made ONCE per run, by `GameState.begin_run` (`Tuning.resolve()`: the project's file, then each pack of the chain, the
## bottom one first), and the run keeps it (`GameState.tuning`). A rule asks the run it works for (`run.tuning.ink_max`), a sub-object
## is handed its section when a sector starts (`SimWorld`), a tool outside a run resolves its own for the chain in use. There is no
## global table to read: the same number cannot be one thing in one place and another in the next, and a test can build a world on
## numbers of its own (`Tuning.extra_files`, `from_dict`). `check` says what is wrong in a pack's layer (`PackCheck`).
##
## Teaches: a rule's constants as one typed, read-only-by-convention object built from a data file by one builder. The members are
## plain values (and `SubTuning`, the sub's section with its methods); a caller never reads the JSON itself. Ambient bubbles are not
## here: they are a presenter's decoration with their own dice (`BubbleRules`), not a rule. A value is judged by what the rules do with
## it: a number they divide by or count down from has a floor (an error below it), a table they index has a length (an error otherwise),
## and a number that merely strains the game's other parts (a faster sub than a wall is thick) is a warning.

## The project's file: the original's numbers.
const BASE_PATH := "res://data/rules/tuning.json"

## The pack-relative path of a pack's tuning (a few keys are enough: they are laid over the base key by key).
const PACK_PATH := "rules/tuning.json"

const OWNER := "Tuning"

## Files laid over the base and the mounted packs' files, later ones winning key by key: a test (or a tool) puts a file of its own here
## and calls `resolve`.
static var extra_files: Array[String] = []

## The submarine: speeds, frame rectangles, the sprite-cell tables, the ink pellet and hit tables (section `sub`).
var sub: SubTuning
## The oxygen of the tank in use and the spare tanks the sub can carry; the spare tanks a new player, a new sector and a supply station
## give at least (section `air`).
var max_oxygen: int = 0
var max_tanks: int = 0
var refill_tanks: int = 0
## A full supply of ink pellets, and how many may fly at once (section `ink`).
var ink_max: int = 0
var ink_in_flight_max: int = 0
## The screen that holds the respawn point; the game ticks from touching a math trigger to its problem; the countdown the data canister
## stores (section `sector`).
var midpoint_screen: int = 0
var pending_ticks: int = 0
var canister_pending_ticks: int = 0
## The combination lock's answer wheel, in ticks of the 73 Hz timer: one position of the wheel, the window in which a key stops it, and
## how often the right position may go by unused (section `lock_wheel`).
var lock_ticks_per_position: int = 0
var lock_key_window_ticks: int = 0
var lock_max_passes: int = 0
## The most instructions a creature script runs in one tick without a YIELD, before the creature is judged stuck (section `creatures`).
var max_instructions_per_tick: int = 0


## The files that make up the tuning: the project's, then `rules/tuning.json` of each pack of the chain (the bottom pack first, so
## that the chosen pack has the last word), then `extra_files`.
static func files() -> Array[String]:
	return LayeredJson.files(BASE_PATH, PACK_PATH, extra_files)


## The tuning of the chain in use: what a run begins with (`GameState.begin_run`), and what a tool outside a run asks once per use.
static func resolve() -> Tuning:
	return from_dict(LayeredJson.read_all(files(), OWNER))


## The original's numbers, whatever the chain says (the project's file alone). For what must not depend on a pack: the state of a game
## before any run has begun, and the tests that pin the original.
static func original() -> Tuning:
	return from_dict(LayeredJson.read(BASE_PATH, OWNER))


## The tuning that a merged dictionary says (sections `sub`, `air`, `ink`, `sector`, `lock_wheel`, `creatures`). A section or key it
## lacks is a bug in the data: it is reported and the value is 0, so a pack that forgot one is told which.
static func from_dict(merged: Dictionary) -> Tuning:
	var t := Tuning.new()
	t.sub = SubTuning.from_dict(_section(merged, "sub"))
	var air := _section(merged, "air")
	t.max_oxygen = LayeredJson.int_of(air, "max_oxygen", OWNER)
	t.max_tanks = LayeredJson.int_of(air, "max_tanks", OWNER)
	t.refill_tanks = LayeredJson.int_of(air, "refill_tanks", OWNER)
	var ink := _section(merged, "ink")
	t.ink_max = LayeredJson.int_of(ink, "max", OWNER)
	t.ink_in_flight_max = LayeredJson.int_of(ink, "in_flight_max", OWNER)
	var sector := _section(merged, "sector")
	t.midpoint_screen = LayeredJson.int_of(sector, "midpoint_screen", OWNER)
	t.pending_ticks = LayeredJson.int_of(sector, "pending_ticks", OWNER)
	t.canister_pending_ticks = LayeredJson.int_of(sector, "canister_pending_ticks", OWNER)
	var wheel := _section(merged, "lock_wheel")
	t.lock_ticks_per_position = LayeredJson.int_of(wheel, "ticks_per_position", OWNER)
	t.lock_key_window_ticks = LayeredJson.int_of(wheel, "key_window_ticks", OWNER)
	t.lock_max_passes = LayeredJson.int_of(wheel, "max_passes", OWNER)
	t.max_instructions_per_tick = LayeredJson.int_of(_section(merged, "creatures"), "max_instructions_per_tick", OWNER)
	return t


static func _section(merged: Dictionary, name: String) -> Dictionary:
	var section: Variant = merged.get(name)
	if section is Dictionary:
		return section
	push_error("%s: no section '%s'" % [OWNER, name])
	return {}


# --- checking a pack's file -----------------------------------------------------------------------------------------------------

## The sprite cells of the sub (`SubTuning`: 0-3 left, 4 front, 5-8 right): every table indexed by a cell has this many entries.
const CELLS := 9
## Whole numbers beyond this do not fit the 32-bit tables the rules keep them in.
const LARGEST := 2147483647.0
## A countdown or limit in game ticks (12.17 Hz) longer than this (a minute) is probably a typo.
const LONG_GAME_TICKS := 730

## The smallest value a number may have, where the rules would divide by it, never move, never begin, or be unable to run: an ERROR below it.
const AT_LEAST: Dictionary[String, int] = {
	"sub.max_speed_x_units": 1,           # a speed limit of 0 pins the sub; the velocity rule clamps to it
	"sub.max_speed_y_units": 1,
	"sub.accel_units": 1,                 # no acceleration, no steering
	"sub.decay_units": 0,                 # (a negative decay would speed the sub up when no key is held)
	"sub.invulnerability_ticks": 0,
	"sub.blink_ticks": 0,
	"sub.bubble_ticks": 0,
	"sub.ink_steps_per_tick": 1,          # a pellet that takes no step never flies
	"air.max_oxygen": 1,                  # a tank with no cell is empty before it is breathed
	"air.max_tanks": 0,
	"air.refill_tanks": 0,
	"ink.max": 0,                         # (0: a sub with no ink)
	"ink.in_flight_max": 1,               # 0 pellets in the air: the fire key does nothing (no ink: `ink.max` 0)
	"sector.midpoint_screen": 0,
	"sector.pending_ticks": 1,            # the problem opens when the countdown has run to 1 (`SimWorld._tick_pending_problem`)
	"sector.canister_pending_ticks": 1,
	"lock_wheel.ticks_per_position": 1,   # `LockWheel` takes the remainder by it
	"lock_wheel.key_window_ticks": 1,     # a window that lasts no tick cannot be pressed in
	"lock_wheel.max_passes": 1,           # the answer would time out before it came by
	"creatures.max_instructions_per_tick": 1,
}
## The largest value a number may have: an ERROR above it.
const AT_MOST: Dictionary[String, int] = {
	"sector.midpoint_screen": SectorData.SCREEN_COUNT - 1,   # the respawn point is on a screen of the sector
}
## A number above `[limit, why]` is odd but plays: a WARNING.
const ODD_ABOVE: Dictionary[String, Array] = {
	"sub.max_speed_x_units": [256, "more than twice the original's: the sub may cross a thin wall within one tick"],
	"sub.max_speed_y_units": [192, "more than twice the original's: the sub may cross a thin wall within one tick"],
	"sub.invulnerability_ticks": [LONG_GAME_TICKS, "longer than a minute"],
	"sub.ink_steps_per_tick": [6, "more than twice the original's: a pellet may cross a thin wall within one tick"],
	"air.max_oxygen": [4, "above the original's: the console draws as many cells as the pack's data/ui/hud_layout.tres has places"],
	"air.max_tanks": [6, "above the original's: the console draws as many tanks as the pack's data/ui/hud_layout.tres has places"],
	"ink.max": [21, "above the original's: the console draws as many pellets as the pack's data/ui/hud_layout.tres has places"],
	"sector.pending_ticks": [LONG_GAME_TICKS, "longer than a minute of waiting for a problem"],
	"sector.canister_pending_ticks": [LONG_GAME_TICKS, "longer than a minute of waiting for a problem"],
	"lock_wheel.ticks_per_position": [73, "longer than a second per position of the wheel"],
	"lock_wheel.key_window_ticks": [730, "longer than ten seconds to press a key"],
	"lock_wheel.max_passes": [10, "the right answer may go by ten times"],
	"creatures.max_instructions_per_tick": [100000, "a creature that never yields would take that long on every tick before it is judged stuck"],
}
## A number below `[limit, why]` is odd but plays: a WARNING.
const ODD_BELOW: Dictionary[String, Array] = {
	"creatures.max_instructions_per_tick": [64, "a creature script of ordinary length would be judged stuck"],
}
## Lists whose every entry is a cell, 0 to `CELLS - 1` (they are looked up with a cell, or hold cells).
const CELL_LISTS: Array[String] = ["sub.cell_after_left", "sub.cell_after_right", "sub.cell_after_down", "sub.cell_after_up",
		"sub.cell_after_level", "sub.light_cells"]
## Lists the rules index by a fixed count: the tables of the 9 cells, the 18 pictures, the 9 rectangles, the splash pictures, the points and sizes.
const EXACT_LISTS: Array[String] = ["sub.frame_rects", "sub.wall_box", "sub.sprite_size", "sub.current_probe", "sub.cell_pictures",
		"sub.cell_after_left", "sub.cell_after_right", "sub.cell_after_down", "sub.cell_after_up", "sub.cell_after_level",
		"sub.ink_spawn_dx", "sub.ink_spawn_dy", "sub.ink_direction", "sub.ink_splash_dx", "sub.ink_splash_dy",
		"sub.hit_bubble_x_by_cell", "sub.light_dx_by_cell", "sub.light_dy_by_cell"]
## Lists whose length the file decides: one entry per direction code (the two step tables), and the cells that show the light.
const FREE_LISTS: Array[String] = ["sub.ink_step_dx", "sub.ink_step_dy", "sub.light_cells"]
## Sub pictures 0 to 7 are the sub itself; 8 is the message light and 9 to 12 the bubbles (`SubModel.FIRST_BUBBLE_PICTURE`).
const SUB_PICTURES := 8


## What is wrong with a pack's `rules/tuning.json` (`layer`, parsed): one sentence per problem into `errors` (the file would be read wrongly or
## the rules could not run on it) and `warnings` (odd, but it plays). Only keys of the project's file are known (a typo would be silently
## ignored otherwise); a section stays a section and a list a list; numbers are whole numbers (`tick_hz` any positive number); a table the
## rules index by cell, picture or rectangle has as many entries as the project's, and every entry is in range; a step, a limit or a
## countdown is at least what `AT_LEAST` says. Cross-field facts are looked at on the merged result (`layer` over the project's file).
static func check(layer: Variant, errors: Array[String], warnings: Array[String]) -> void:
	if not layer is Dictionary:
		errors.append("rules/tuning.json must be a JSON object laid over data/rules/tuning.json")
		return
	var base := LayeredJson.read(BASE_PATH, OWNER)
	var walker := LayeredJson.Check.new("rule value", BASE_PATH, "whole numbers", _check_value)
	walker.exact_lengths = EXACT_LISTS
	walker.free_lengths = FREE_LISTS
	LayeredJson.walk(base, layer, walker, errors, warnings)
	var merged := base.duplicate(true)
	LayeredJson.merge(merged, layer)
	_check_together(merged, errors, warnings)


static func _check_value(value: Variant, path: String, errors: Array[String], warnings: Array[String]) -> void:
	if path == "sub.frame_rects":
		_check_rect(value, path, errors)
		return
	if path == "sub.tick_hz":
		if not LayeredJson.is_number(value) or value <= 0:
			errors.append("%s must be a number above 0, not %s" % [path, str(value)])
		return
	if not LayeredJson.check_whole(value, path, errors):
		return
	if absf(value) > LARGEST:
		errors.append("%s is %s: too large for the rules' 32-bit numbers" % [path, str(value)])
		return
	if AT_LEAST.has(path) and value < AT_LEAST[path]:
		errors.append("%s is %d: it must be %d or more" % [path, value, AT_LEAST[path]])
	elif AT_MOST.has(path) and value > AT_MOST[path]:
		errors.append("%s is %d: it must be %d or less" % [path, value, AT_MOST[path]])
	elif ODD_ABOVE.has(path) and value > ODD_ABOVE[path][0]:
		warnings.append("%s is %d: %s" % [path, value, ODD_ABOVE[path][1]])
	elif ODD_BELOW.has(path) and value < ODD_BELOW[path][0]:
		warnings.append("%s is %d: %s" % [path, value, ODD_BELOW[path][1]])
	if CELL_LISTS.has(path) and (value < 0 or value >= CELLS):
		errors.append("%s has the entry %d: a cell is 0 to %d" % [path, value, CELLS - 1])
	elif path == "sub.cell_pictures":
		if value < 0:
			errors.append("%s has the entry %d: a picture is 0 or more" % [path, value])
		elif value >= SUB_PICTURES:
			warnings.append("%s has the entry %d: the sub itself is the pictures 0 to %d (8 is the message light, 9 to 12 the bubbles)" % [path, value, SUB_PICTURES - 1])
	elif path == "sub.ink_direction" and value < 0:
		errors.append("%s has the entry %d: a direction code is 0 or more" % [path, value])


## A rectangle `[x, y, width, height]` of `sub.frame_rects`.
static func _check_rect(value: Variant, path: String, errors: Array[String]) -> void:
	if not value is Array or (value as Array).size() != 4:
		errors.append("%s must hold rectangles [x, y, width, height], not %s" % [path, str(value)])
		return
	for number: Variant in value:
		if not LayeredJson.check_whole(number, path, errors):
			return
		if absf(number) > LARGEST:
			errors.append("%s has the number %s: too large for the rules' 32-bit numbers" % [path, str(number)])
			return


## The facts that span several keys, on the merged file. A key of the wrong kind has been reported by the walk and is left out here.
static func _check_together(merged: Dictionary, errors: Array[String], warnings: Array[String]) -> void:
	var sub := LayeredJson.dict(merged.get("sub"))
	var air := LayeredJson.dict(merged.get("air"))
	var ink := LayeredJson.dict(merged.get("ink"))
	# the sizes of the rectangles and the pictures
	var rects: Variant = sub.get("frame_rects")
	if rects is Array:
		for i in (rects as Array).size():
			var rect: Variant = rects[i]
			if rect is Array and (rect as Array).size() == 4 and LayeredJson.is_number(rect[2]) and LayeredJson.is_number(rect[3]) and (rect[2] < 1 or rect[3] < 1):
				errors.append("sub.frame_rects: the rectangle of cell %d has no size (width and height are 1 or more)" % i)
	var wall := _whole_numbers(sub.get("wall_box"))
	if wall.size() == 4 and (wall[2] < 1 or wall[3] < 1):
		errors.append("sub.wall_box has no size (width and height are 1 or more)")
	var picture := _whole_numbers(sub.get("sprite_size"))
	if picture.size() == 2 and (picture[0] < 1 or picture[1] < 1):
		errors.append("sub.sprite_size has no size (width and height are 1 or more)")
	# the ink: a direction code of a cell must have a step in both tables
	var step_x := _whole_numbers(sub.get("ink_step_dx"))
	var step_y := _whole_numbers(sub.get("ink_step_dy"))
	if step_x.size() != step_y.size():
		errors.append("sub.ink_step_dx has %d entries and sub.ink_step_dy %d: one step per direction code in each" % [step_x.size(), step_y.size()])
	var directions := mini(step_x.size(), step_y.size())
	for code in _whole_numbers(sub.get("ink_direction")):
		if code >= directions:
			errors.append("sub.ink_direction names the direction code %d, but the step tables have %d entries (codes 0 to %d)" % [code, directions, directions - 1])
	# the hit: invulnerable for so long, the first bubble_ticks with bubbles, the last blink_ticks blinking
	var invulnerable: Variant = _whole(sub.get("invulnerability_ticks"))
	var bubbles: Variant = _whole(sub.get("bubble_ticks"))
	var blinks: Variant = _whole(sub.get("blink_ticks"))
	if invulnerable == 0:
		warnings.append("sub.invulnerability_ticks is 0: the sub is not protected after a hit")
	if invulnerable != null and blinks != null and blinks > invulnerable:
		warnings.append("sub.blink_ticks (%d) is longer than sub.invulnerability_ticks (%d): the sub blinks for all of it" % [blinks, invulnerable])
	if invulnerable != null and bubbles != null and bubbles > invulnerable:
		warnings.append("sub.bubble_ticks (%d) is longer than sub.invulnerability_ticks (%d): the bubbles never end" % [bubbles, invulnerable])
	var most_bubbles := SubModel.BUBBLE_PICTURES * SubModel.TICKS_PER_BUBBLE_PICTURE
	if bubbles != null and bubbles > most_bubbles:
		warnings.append("sub.bubble_ticks is %d: the bubbles have %d pictures of %d ticks, and then run out" % [bubbles, SubModel.BUBBLE_PICTURES, SubModel.TICKS_PER_BUBBLE_PICTURE])
	# the velocity
	var accel: Variant = _whole(sub.get("accel_units"))
	for axis in ["x", "y"]:
		var top: Variant = _whole(sub.get("max_speed_%s_units" % axis))
		if accel != null and top != null and accel > top:
			warnings.append("sub.accel_units (%d) is above sub.max_speed_%s_units (%d): the sub is at full speed after one tick" % [accel, axis, top])
	if _whole(sub.get("decay_units")) == 0:
		warnings.append("sub.decay_units is 0: the sub never slows down by itself")
	# the air and the ink
	var tanks: Variant = _whole(air.get("max_tanks"))
	var refill: Variant = _whole(air.get("refill_tanks"))
	if tanks != null and refill != null and refill > tanks:
		warnings.append("air.refill_tanks (%d) is above air.max_tanks (%d): a supply station fills the sub beyond what it can carry" % [refill, tanks])
	var supply: Variant = _whole(ink.get("max"))
	var in_flight: Variant = _whole(ink.get("in_flight_max"))
	if supply != null and in_flight != null and in_flight > supply:
		warnings.append("ink.in_flight_max (%d) is above ink.max (%d): there is never ink for that many pellets" % [in_flight, supply])


## `value` as a whole number, or null when it is not one.
static func _whole(value: Variant) -> Variant:
	if LayeredJson.is_number(value) and value == floorf(value):
		return int(value)
	return null


## The whole numbers of the list `value` (anything that is not a whole number is left out: the walk has reported it).
static func _whole_numbers(value: Variant) -> Array[int]:
	var found: Array[int] = []
	if value is Array:
		for entry: Variant in value:
			var number: Variant = _whole(entry)
			if number != null:
				found.append(number)
	return found
