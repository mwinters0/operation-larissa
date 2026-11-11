class_name TroubleLog
extends RefCounted
## The warnings one owner has given, each once: the way the game says that a pack (or a campaign, a sector, a creature) holds or lacks something the game falls back from (docs/engine/ARCHITECTURE.md, "A pack's trouble is never silent").
## An owner that lives as long as the thing it warns about (`RuleHooks`: a run; `FoeVM.Context`: a sim of sectors) holds one; code with no such owner (a static lookup, a mod's draw list) tells `session`, which every run
## (`GameState.begin_run`) starts over. `tell` gives the line to `push_warning` the first time and never again, however often the rules meet the cause (every tick of a creature, every frame of a mod). `told` is what was said, in order,
## for a test to read: a test cannot see the log of the engine, only this.
##
## Teaches: a warning that is also data, so that "one warning per cause" is a property a test can check, and de-duplication by the text itself (the text names the cause).

## The warnings of code that has no owner of a run: given once per run (`new_run`, from `GameState.begin_run`).
static var session := TroubleLog.new()

## The most distinct lines one owner gives; the line after them says so, and the rest are dropped.
const MAX_LINES := 64

## The lines given, in order.
var told: Array[String] = []

var _seen: Dictionary = {}


## A run begins: what `session` said is said again if the cause is met again.
static func new_run() -> void:
	session = TroubleLog.new()


## Gives `line` to `push_warning` unless this log has given it already. True when it was given now.
func tell(line: String) -> bool:
	if _seen.has(line):
		return false
	if told.size() >= MAX_LINES:
		return false
	_seen[line] = true
	if told.size() == MAX_LINES - 1:
		line += " (further warnings of this kind are not given)"
	told.append(line)
	push_warning(line)
	return true


## Was `line` given?
func has(line: String) -> bool:
	return _seen.has(line)
