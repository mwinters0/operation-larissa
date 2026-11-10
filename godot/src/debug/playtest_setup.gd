class_name PlaytestSetup
extends RefCounted
## Everything that is decided BEFORE the first tick of a playtest of one screen: which screen, where the sub is, how much air and
## ink it has, which pieces are collected, which creature flags are set, and what each creature is doing. The screen editor's
## "Playtest screen" fills one in, writes it as command-line words, and the tool scene `screen_playtest.tscn` reads the words
## back and applies it to a fresh `SimWorld`; after that the sim runs as always.
##
## Teaches: testing a part of a game without touching its rules. Nothing here is a rule: `apply` only sets the starting state, in
## the places the rules already keep it (the run's numbers, the creatures' `dormant` / `hidden` flags, the flags of the creature
## scripts), with the calls the game itself makes to start a sector (`SimWorld.begin_sector_on`, `start_launch`, `start_flight`). It
## is a plain object, so a test can build one, apply it with no scene and compare the result with the normal start of a sector.
##
## WHAT THE GAME CAN REACH, AND WHAT IT CANNOT. A playtest should show what a player could meet, so the state a setup makes is
## limited to numbers the game has:
##  * air: 0 to `max_tanks` spare tanks (6 in the original) and 1 to `max_oxygen` oxygen (4), ink 0 to `ink_max` pellets (21), the limits of the
##    rules' `Tuning`; any combination is reachable.
##  * pieces: any subset of the sector's pieces; the midpoint flag is worked out from them (`GameState.update_midpoint`) as the
##    game does after every pickup. The order in which they were picked up is not kept by the game, so none is implied.
##  * flags: the 16 bits of `FoeVM.Context.semaphore`. A script sets and clears them one by one, so any single bit is reachable;
##    a combination is reachable only if some run of the scripts makes it (not checked). Bit 15 is the finale's: set, it ends the
##    game as soon as the sub is on the finale screen (`SimWorld.finale_screen`).
##  * creatures: `dormant` and `hidden` set or cleared. The game does that with SLEEP_FOE / WAKE_FOE and HIDE / SHOW. NOT changed:
##    a creature's place, picture and program counter stay at the start of its script (in the game a creature that was put to sleep
##    keeps the place where it slept, so "woken" is exactly right only for a creature that never moved).
##  * the sub: at the station door (the launch, screen 0), at the sector's respawn point (the midpoint screen, 6 in the original, as after a lost tank past the
##    midpoint), or at any place of the playfield with any of the nine pictures, standing still and not hurt. The place is NOT
##    checked against the walls: a sub put inside a wall does what the wall scan makes it do.
## `problems` lists what a setup asks for that the game cannot give, and `apply` then uses the nearest value it can.
##
## THE WORDS. `to_arguments` / `from_arguments` turn a setup into the command-line words of the tool scene and back:
##   --sector=N --screen=N --start=launch|respawn|centre|X,Y (left out: the screen's default) --cell=0-8 --tanks=N --oxygen=N
##   --ink=N --pieces=MASK --flags=MASK --foes=3:dormant,5:hidden+dormant,7:woken --pause
## They travel in the environment variable `FoeSandbox.ARGS_ENV`, because `EditorInterface.play_custom_scene` takes no arguments.

## `start`: where the sub begins. DEFAULT is decided by the screen (`resolved_start`).
const START_DEFAULT := "default"
## The sub drives out of the start station (screen 0): `SimWorld.start_launch`, 30 ticks without control, as every new sector.
const START_LAUNCH := "launch"
## The sub appears at the sector's respawn point (screen 6): `SimWorld.start_flight`.
const START_RESPAWN := "respawn"
## The middle of the playfield.
const START_CENTRE := "centre"
## At `sub_pos` (SubX / SubY, window pixels of the picture's top-left corner) with picture `cell`.
const START_AT := "at"
const STARTS: Array[String] = [START_DEFAULT, START_LAUNCH, START_RESPAWN, START_CENTRE, START_AT]

## What a creature is told to be: `dormant` (its script does not run), `hidden` (not drawn, cannot be touched), both, or `woken`
## (neither). A creature that is not in `foe_states` is as its record says.
const FOE_DORMANT := "dormant"
const FOE_HIDDEN := "hidden"
const FOE_DORMANT_HIDDEN := "dormant+hidden"
const FOE_WOKEN := "woken"
const FOE_STATES: Array[String] = [FOE_DORMANT, FOE_HIDDEN, FOE_DORMANT_HIDDEN, FOE_WOKEN]

## The presets of the dialog. Each sets the numbers (air, ink, pieces, flags) and leaves the place of the sub and the creatures.
const PRESET_START := &"sector_start"
const PRESET_FULL := &"full"
const PRESET_ALL_BUT_HERE := &"all_but_here"
const PRESET_LOW_OXYGEN := &"low_oxygen"
const PRESET_NO_INK := &"no_ink"
const PRESETS: Array[StringName] = [PRESET_START, PRESET_FULL, PRESET_ALL_BUT_HERE, PRESET_LOW_OXYGEN, PRESET_NO_INK]

const PRESET_TITLES := {
	PRESET_START: "As at the start of the sector (a new player's tanks, full air and ink, nothing collected)",
	PRESET_FULL: "Full tanks, air and ink",
	PRESET_ALL_BUT_HERE: "Full, and every piece collected except this screen's",
	PRESET_LOW_OXYGEN: "Low oxygen (1 oxygen, 1 spare tank)",
	PRESET_NO_INK: "No ink",
}

## The rule values the limits and the respawn screen come from: the chain's, resolved when the setup is made (the editor is outside a
## run); `apply` takes the run's own (`sim.run.tuning`).
var tuning: Tuning = Tuning.resolve()
var sector: int = 0
var screen: int = 0
var start: String = START_DEFAULT
## SubX / SubY for `START_AT`.
var sub_pos: Vector2i = Vector2i.ZERO
## The sub's picture (0-8) for `START_AT` and `START_CENTRE`; the respawn point has its own.
var cell: int = 6
## Spare tanks and oxygen: the numbers of a new player.
var tanks: int = tuning.refill_tanks
var oxygen: int = tuning.max_oxygen
var ink: int = tuning.ink_max
## Bit i is set: piece i of the sector is collected (bit 0 = the data canister).
var pieces_mask: int = 0
## The creature flags (`FoeVM.Context.semaphore`), 16 bits.
var flags: int = 0
## Creature number -> one of `FOE_STATES`.
var foe_states: Dictionary = {}
## The tool scene starts with the clock stopped (S steps).
var paused: bool = false


# --- the words ----------------------------------------------------------------

## The command-line words of this setup (see the header), separated by single spaces so that they can travel in one environment
## variable. `from_arguments` reads them back to an equal setup.
func to_arguments() -> String:
	var words: Array[String] = ["--sector=%d" % sector, "--screen=%d" % screen]
	match start:
		START_LAUNCH, START_RESPAWN, START_CENTRE:
			words.append("--start=" + start)
		START_AT:
			words.append("--start=%d,%d" % [sub_pos.x, sub_pos.y])
	words.append_array(["--cell=%d" % cell, "--tanks=%d" % tanks, "--oxygen=%d" % oxygen, "--ink=%d" % ink,
			"--pieces=%d" % pieces_mask, "--flags=%d" % flags])
	if not foe_states.is_empty():
		var numbers: Array = foe_states.keys()
		numbers.sort()
		words.append("--foes=" + ",".join(numbers.map(func(number: int) -> String: return "%d:%s" % [number, foe_states[number]])))
	if paused:
		words.append("--pause")
	return " ".join(words)


## A setup from command-line words. Unknown words, and values that do not parse, are ignored (the field keeps its default).
static func from_arguments(args: PackedStringArray) -> PlaytestSetup:
	var setup := PlaytestSetup.new()
	for arg in args:
		var parts := arg.trim_prefix("--").split("=", true, 1)
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"sector":
				setup.sector = value.to_int()
			"screen":
				setup.screen = value.to_int()
			"start":
				setup._read_start(value)
			"cell":
				setup.cell = value.to_int()
			"tanks":
				setup.tanks = value.to_int()
			"oxygen":
				setup.oxygen = value.to_int()
			"ink":
				setup.ink = value.to_int()
			"pieces":
				setup.pieces_mask = value.to_int()
			"flags":
				setup.flags = value.to_int()
			"foes":
				setup.read_foes(value)
			"pause":
				setup.paused = true
	return setup


func _read_start(value: String) -> void:
	if value in [START_LAUNCH, START_RESPAWN, START_CENTRE]:
		start = value
		return
	var at := value.split(",")
	if at.size() == 2 and at[0].is_valid_int() and at[1].is_valid_int():
		start = START_AT
		sub_pos = Vector2i(at[0].to_int(), at[1].to_int())


func read_foes(value: String) -> void:
	for entry in value.split(",", false):
		var pair := entry.split(":")
		if pair.size() == 2 and pair[0].is_valid_int() and pair[1] in FOE_STATES:
			foe_states[pair[0].to_int()] = pair[1]


## True when `other` would start the very same playtest.
func equals(other: PlaytestSetup) -> bool:
	return to_arguments() == other.to_arguments()


# --- presets ------------------------------------------------------------------

## A setup for `screen` of `sector` with the numbers of `preset` (one of `PRESETS`); the sub and the creatures are the defaults.
static func from_preset(preset: StringName, sector_number: int, screen_number: int) -> PlaytestSetup:
	var setup := PlaytestSetup.new()
	setup.sector = sector_number
	setup.screen = screen_number
	setup.apply_preset(preset)
	return setup


## Sets air, ink, pieces and flags to those of `preset`. The place of the sub, the creatures and `paused` are not touched.
func apply_preset(preset: StringName) -> void:
	tanks = tuning.refill_tanks
	oxygen = tuning.max_oxygen
	ink = tuning.ink_max
	pieces_mask = 0
	flags = 0
	match preset:
		PRESET_FULL:
			tanks = tuning.max_tanks
		PRESET_ALL_BUT_HERE:
			tanks = tuning.max_tanks
			pieces_mask = all_pieces_mask(sector) & ~pieces_mask_of_screen(sector, screen)
		PRESET_LOW_OXYGEN:
			tanks = 1
			oxygen = 1
		PRESET_NO_INK:
			ink = 0


## The mask with a bit for each piece of the sector (a sector has 7-11, the canister among them).
static func all_pieces_mask(sector_number: int) -> int:
	return (1 << Catalog.sector(sector_number).pieces.size()) - 1


## The bits of the pieces that lie on `screen_number`.
static func pieces_mask_of_screen(sector_number: int, screen_number: int) -> int:
	var mask := 0
	var pieces := Catalog.sector(sector_number).pieces
	for i in pieces.size():
		if pieces[i].screen == screen_number:
			mask |= 1 << i
	return mask


# --- where the sub starts -----------------------------------------------------------

## `start` with the default decided: the station launch on screen 0, the respawn point on screen 6 (the screen the editor shows
## the start marker on), the middle of the playfield elsewhere.
func resolved_start() -> String:
	if start != START_DEFAULT:
		return start
	if screen == 0:
		return START_LAUNCH
	if screen == tuning.midpoint_screen:
		return START_RESPAWN
	return START_CENTRE


## SubX / SubY of the middle of the playfield (the picture's top-left corner, window pixels, x even as the sub's is).
static func centre_position() -> Vector2i:
	var origin := Vector2i(SubModel.PLAYFIELD_ORIGIN)
	var free := TileGrid.PLAYFIELD_SIZE - PieceModel.SUB_PICTURE_SIZE
	return Vector2i(origin.x + (free.x / 2 & ~1), origin.y + free.y / 2)


## `resolved_start` as it can be done: a launch is on screen 0 only and the respawn point on screen 6 only, so on any other screen
## those two become the middle of the playfield (`problems` says so).
func effective_start() -> String:
	var wanted := resolved_start()
	if (wanted == START_LAUNCH and screen != 0) or (wanted == START_RESPAWN and screen != tuning.midpoint_screen):
		return START_CENTRE
	return wanted


## Where the sub's picture starts (SubX / SubY) and which of its nine pictures it shows, for `effective_start` (the launch starts
## at the station door, and drives from there). A place outside the playfield is brought inside it.
func start_place() -> Dictionary:
	var sector_data := Catalog.sector(sector)
	match effective_start():
		START_LAUNCH:
			return {"pos": Vector2i(StationSequence.launch().drive_from_x(), SimWorld.STATION_DRIVE_Y), "cell": 6}
		START_RESPAWN:
			return {"pos": sector_data.start_pos, "cell": sector_data.start_frame}
		START_AT:
			var first := Vector2i(SubModel.PLAYFIELD_ORIGIN)
			var last := first + TileGrid.PLAYFIELD_SIZE - PieceModel.SUB_PICTURE_SIZE
			return {"pos": sub_pos.clamp(first, last), "cell": clampi(cell, 0, 8)}
	return {"pos": centre_position(), "cell": clampi(cell, 0, 8)}


# --- what the game cannot give --------------------------------------------------------

## What this setup asks for that the game cannot give (each line says what `apply` uses instead). Empty: all of it is reachable.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if not Catalog.has_sector(sector):
		found.append("sector %d does not exist (the catalog has %d sectors, up to %d)" % [sector, Catalog.sector_count(), Catalog.last_sector()])
		return found
	var sector_data := Catalog.sector(sector)
	if screen < 0 or screen >= Catalog.SCREENS_PER_SECTOR:
		found.append("screen %d does not exist (0-%d)" % [screen, Catalog.SCREENS_PER_SECTOR - 1])
		return found
	if start == START_LAUNCH and screen != 0:
		found.append("the launch is on screen 0, not %d: the sub starts in the middle instead" % screen)
	if start == START_RESPAWN and screen != tuning.midpoint_screen:
		found.append("the respawn point is on screen %d, not %d: the sub starts in the middle instead" % [tuning.midpoint_screen, screen])
	if start == START_AT:
		var picture := Rect2i(sub_pos, PieceModel.SUB_PICTURE_SIZE)
		var playfield := Rect2i(Vector2i(SubModel.PLAYFIELD_ORIGIN), TileGrid.PLAYFIELD_SIZE)
		if not playfield.encloses(picture):
			found.append("the sub at %s is not wholly inside the playfield %s" % [sub_pos, playfield])
	if cell < 0 or cell > 8:
		found.append("sub picture %d does not exist (0-8)" % cell)
	if tanks < 0 or tanks > tuning.max_tanks:
		found.append("%d spare tanks: the game has 0-%d" % [tanks, tuning.max_tanks])
	if oxygen < 1 or oxygen > tuning.max_oxygen:
		found.append("oxygen %d: the game has 1-%d (at 0 a tank is lost)" % [oxygen, tuning.max_oxygen])
	if ink < 0 or ink > tuning.ink_max:
		found.append("%d pellets: the game has 0-%d" % [ink, tuning.ink_max])
	if pieces_mask < 0 or pieces_mask > all_pieces_mask(sector):
		found.append("pieces mask %d has bits for pieces this sector does not have (it has %d)" % [pieces_mask, sector_data.pieces.size()])
	if flags < 0 or flags > 0xFFFF:
		found.append("flags %d: the creatures have 16 flags" % flags)
	for number in foe_states:
		if number < 0 or number >= sector_data.foes.size():
			found.append("creature %d does not exist (the sector has %d)" % [number, sector_data.foes.size()])
		elif not foe_states[number] in FOE_STATES:
			found.append("creature %d: unknown state %s" % [number, foe_states[number]])
	return found


# --- applying it ------------------------------------------------------------------

## Makes the state of the playtest in `sim` (a fresh one, before its first tick): the player's numbers, then the sector started on
## its screen through the rules' entry the game's own start is built from (`SimWorld.begin_sector_on`: the load, the screen entered,
## the "begin" sound), then the creatures' flags and states, then the sub. Values the game cannot have are brought into range (`problems` says which). Needs the run
## (`sim.run`) to be a `GameState`, or an object with its members.
func apply(sim: SimWorld) -> void:
	var run := sim.run
	var sector_number := Catalog.nearest_sector(sector)
	run.reset()
	tuning = run.tuning                                                   # (the rules of the run that `reset` began)
	var model: OxygenModel = run.oxygen_model
	model.tanks = clampi(tanks, 0, tuning.max_tanks)
	model.oxygen = clampi(oxygen, 1, tuning.max_oxygen)
	run.ink = clampi(ink, 0, tuning.ink_max)
	run.pieces_mask = pieces_mask & all_pieces_mask(sector_number)    # (before the screen: its pieces are the ones not collected)
	run.oxygen_changed.emit(model.tanks, model.oxygen)
	run.ink_changed.emit(run.ink)
	sim.begin_sector_on(sector_number, clampi(screen, 0, Catalog.SCREENS_PER_SECTOR - 1))
	sim.foe_context.semaphore = flags & 0xFFFF
	for number in foe_states:
		if number >= 0 and number < sim.foes.size() and foe_states[number] in FOE_STATES:
			_set_creature(sim.foes[number], foe_states[number])
			sim.foes[number].refresh(sim.foes[number].vm.screen == sim.screen_index)
	var place := start_place()
	match effective_start():
		START_LAUNCH:
			sim.start_launch()
		START_RESPAWN:
			sim.start_flight()
		_:
			sim.start_flight(place["pos"].x, place["pos"].y, place["cell"])


func _set_creature(foe: FoeModel, state: String) -> void:
	foe.vm.dormant = state in [FOE_DORMANT, FOE_DORMANT_HIDDEN]
	foe.vm.hidden = state in [FOE_HIDDEN, FOE_DORMANT_HIDDEN]
	foe.snap()


## One line saying what this setup is, for the title of the tool scene.
func describe() -> String:
	return "sector %d, screen %d, %s: %d tanks, oxygen %d, ink %d, %d pieces, flags %04x, %d creatures set" % [
			sector, screen, resolved_start(), tanks, oxygen, ink, _count_bits(pieces_mask), flags, foe_states.size()]


static func _count_bits(mask: int) -> int:
	var count := 0
	for i in 16:
		count += (mask >> i) & 1
	return count
