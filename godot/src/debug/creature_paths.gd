class_name CreaturePaths
extends RefCounted
## Where the creatures of a sector go: runs their scripts on a private copy for N ticks and writes down the positions.
##
## Teaches: asking a program a question by RUNNING it, without disturbing the real thing. A creature is a `FoeVM` (no nodes, DESIGN
## 3.5) built from a `FoeData` record and the sector's compiled script, and a `FoeVM.Context` carries what the script may look at
## (the sub's position, the shown screen, the shared flags, a random number generator). So a trace needs no `SimWorld`: build
## fresh VMs, give them a context, call `tick` as `SimWorld._tick_creatures` does, and read `x`, `y`, `frame` after each tick.
## Nothing of the game is touched (not `GameState`, not the clock, not the `SectorData`), so the rules and their traces stay
## as they were; `tests/engine/test_sector_overview.gd` checks that and that the trace is the very positions a `SimWorld` gets.
##
## WHAT A TRACE MEANS. Creatures only run while their screen is the shown one (`FoeVM.can_run`), so the question is asked per
## screen: "the sub is on screen S (at a fixed place) for N ticks: where does each creature on S go?". The sub's place matters to
## the scripts that chase it or flee from it (`IF_SUBX_GT` ...), and dice rolls (`IF_RAND_GT`) come from a generator that
## starts from a fixed seed, so a trace is the same every time (an ordinary game rolls differently, so a script with dice shows
## one of its possible paths). Creatures the other screens' scripts would wake are not woken, because those screens do not run.
## A creature that starts asleep (`dormant`) and is never woken here stands still: its path is one point.

## Ticks of a trace unless told otherwise: 600 ticks are about 50 seconds of game time (12.17 ticks a second).
const DEFAULT_TICKS := 600
## The seed of the dice of the scripts.
const DEFAULT_SEED := 17
## Where the sub is (SubX, SubY: the picture's top-left corner in window pixels) in the three presets.
const SUB_LAUNCH := Vector2i(96, 202)
const SUB_CENTRE := Vector2i(256, 150)
const SUB_RIGHT := Vector2i(480, 150)
const SUB_PRESETS: Array[Vector2i] = [SUB_LAUNCH, SUB_CENTRE, SUB_RIGHT]
const SUB_PRESET_NAMES: Array[String] = ["sub at the launch point", "sub in the middle", "sub on the right"]


## What one creature did on one screen.
class Path extends RefCounted:
	## Position in the sector's creature list.
	var foe_index: int = 0
	var screen: int = 0
	## The runs of positions between jumps and hidden stretches: each a polyline of the picture's CENTRE in window pixels.
	var segments: Array[PackedVector2Array] = []
	## Its place at the start (picture top-left, window pixels), the picture and mirror then.
	var start_pos: Vector2i = Vector2i.ZERO
	var start_frame: int = 0
	var start_flip: bool = false
	## Its place, picture and visibility the last time it was seen on this screen (picture top-left, window pixels).
	var end_pos: Vector2i = Vector2i.ZERO
	var end_frame: int = 0
	var end_flip: bool = false
	var end_hidden: bool = false
	## The pictures it showed on this screen, and the tick count it spent on it (hidden ones included).
	var frames: Dictionary = {}
	var ticks_on_screen: int = 0
	var ticks_hidden: int = 0
	var jumps: int = 0
	## The box all positions lie in (picture centres, window pixels).
	var bounds: Rect2 = Rect2()
	## It never moved nor changed its picture: asleep, hidden for good or just standing there.
	var still: bool = true
	## Non-empty when the script faulted (the creature then freezes).
	var fault: String = ""

	## A short text for the inspector.
	func describe() -> String:
		var text := "creature %d on screen %d: %d ticks here" % [foe_index, screen, ticks_on_screen]
		if still:
			text += ", stands still"
		else:
			text += ", path %d x %d px" % [int(bounds.size.x), int(bounds.size.y)]
		if ticks_hidden > 0:
			text += ", hidden %d ticks" % ticks_hidden
		if jumps > 0:
			text += ", %d jumps" % jumps
		if not fault.is_empty():
			text += ", FAULT: " + fault
		return text

	## A number that is the same for the same path (for tests: the trace of a run is the same every time).
	func digest() -> int:
		return hash([foe_index, screen, segments, start_pos, ticks_on_screen, ticks_hidden, jumps])


## The traces of every creature that is on `screen` at some time while the sub is there for `ticks` ticks at `sub_pos`, in the
## order of the creature list. Does not change `sector` (its script is compiled if that has not happened yet). `rule_values` is the `Tuning`
## the scripts run under (their instruction limit); left out, the original's.
static func trace_screen(sector: SectorData, screen: int, ticks: int = DEFAULT_TICKS, sub_pos: Vector2i = SUB_CENTRE, seed_value: int = DEFAULT_SEED, rule_values: Tuning = null) -> Array[Path]:
	var context := FoeVM.Context.new(rule_values)
	context.rng.seed = seed_value
	context.current_screen = screen
	context.sub_x = sub_pos.x
	context.sub_y = sub_pos.y
	for i in sector.foes.size():
		context.foes.append(FoeVM.from_data(sector.foes[i], i, sector))
	var meta := SpriteMeta.for_zone(sector.zone)
	var paths: Dictionary = {}                                  # creature number -> Path
	var open: Dictionary = {}                                   # creature number -> the polyline being drawn
	var last: Dictionary = {}                                   # creature number -> [x, y, frame, flip, hidden]
	for vm: FoeVM in context.foes:
		if vm.screen == screen:
			_record(paths, open, last, vm, meta, false)
	for tick in ticks:
		for vm: FoeVM in context.foes:
			vm.tick(context)
		for vm: FoeVM in context.foes:
			if vm.screen == screen:
				_record(paths, open, last, vm, meta, true)
			elif open.has(vm.index):                            # it left the screen: the line ends where it was
				_close(paths[vm.index], open)
		context.sounds.clear()
	for index: int in open.keys():
		_close(paths[index], open)
	var found: Array[Path] = []
	var numbers: Array = paths.keys()
	numbers.sort()
	for index: int in numbers:
		var path: Path = paths[index]
		path.fault = context.foes[index].fault
		_finish(path)
		found.append(path)
	return found


## `trace_screen` for each of the sector's screens. Dictionary screen -> Array[Path].
static func trace_sector(sector: SectorData, ticks: int = DEFAULT_TICKS, sub_pos: Vector2i = SUB_CENTRE, seed_value: int = DEFAULT_SEED, rule_values: Tuning = null) -> Dictionary:
	var all: Dictionary = {}
	for screen in sector.screens.size():
		all[screen] = trace_screen(sector, screen, ticks, sub_pos, seed_value, rule_values)
	return all


## One creature after one tick (or before the first): adds its place to the path, in a new polyline after a jump or a hidden stretch.
static func _record(paths: Dictionary, open: Dictionary, last: Dictionary, vm: FoeVM, meta: SpriteMetaTable, counted: bool) -> void:
	var path: Path = paths.get(vm.index)
	if path == null:
		path = Path.new()
		path.foe_index = vm.index
		path.screen = vm.screen
		path.start_pos = Vector2i(vm.x, vm.y)
		path.start_frame = vm.frame
		path.start_flip = vm.flip
		paths[vm.index] = path
	if counted:
		path.ticks_on_screen += 1
	path.end_pos = Vector2i(vm.x, vm.y)
	path.end_frame = vm.frame
	path.end_flip = vm.flip
	path.end_hidden = vm.hidden
	path.frames[vm.frame] = true
	var state := [vm.x, vm.y, vm.frame, vm.flip, vm.hidden]
	if last.has(vm.index) and last[vm.index] != state:
		path.still = false
	last[vm.index] = state
	if vm.hidden:
		if counted:
			path.ticks_hidden += 1
		if open.has(vm.index):
			_close(path, open)
		return
	var size: Vector2i = meta.sizes[vm.frame] if vm.frame < meta.sizes.size() else Vector2i.ZERO
	var centre := Vector2(vm.x, vm.y) + Vector2(size) / 2.0
	if vm.jumped and open.has(vm.index):
		path.jumps += 1
		_close(path, open)
	if not open.has(vm.index):
		open[vm.index] = PackedVector2Array()
	open[vm.index].append(centre)


static func _close(path: Path, open: Dictionary) -> void:
	var line: PackedVector2Array = open[path.foe_index]
	open.erase(path.foe_index)
	if not line.is_empty():
		path.segments.append(line)


static func _finish(path: Path) -> void:
	var first := true
	for line in path.segments:
		for point in line:
			if first:
				path.bounds = Rect2(point, Vector2.ZERO)
				first = false
			else:
				path.bounds = path.bounds.expand(point)
