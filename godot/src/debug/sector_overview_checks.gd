@tool
class_name SectorOverviewChecks
extends RefCounted
## What the sector overview shows from the playability checks (`SectorChecks`) and the what-changed report (`SectorChanges`):
## every finding put at the place it is about (a piece, a creature, a trigger, the end station, a side of a screen, or the screen
## as a whole), and the screens that differ from the original. Plain data, so a test can read it and `SectorOverviewCanvas` only paints it.
##
## Teaches: connecting two tools by their data. A `CheckFinding` says WHERE in words ("piece 3" on screen 5, "creature 7 ink_label",
## "left link" of screen 2); the overview's model knows WHERE in pixels (`SectorOverviewModel.objects`). This class is the small
## dictionary between the two: it reads the words with a few patterns and finds the object, and what it cannot place (a finding about
## the whole sector, or about a thing that is on no screen) it keeps in `unplaced` so that a list can still show it.

enum Placed {
	## An object of the model (`Mark.object`, its `rect` in playfield pixels).
	OBJECT,
	## A strip along one side of a screen (a link).
	SIDE,
	## The screen as a whole.
	SCREEN,
}

## The strip a "left link" is marked with: playfield pixels along the edge.
const SIDE_STRIP := 24.0

## One finding at its place on the map.
class Mark extends RefCounted:
	var finding: CheckFinding
	var screen: int = -1
	var placed: Placed = Placed.SCREEN
	## The model's object (dictionary of `SectorOverviewModel`), or empty.
	var object: Dictionary = {}
	## Playfield pixels of the screen; the whole screen for a screen-level finding.
	var rect: Rect2 = Rect2()

	## Muted: the finding is how the original is (it is allowed), or only a remark.
	func muted() -> bool:
		return not finding.allowed.is_empty() or finding.severity == CheckFinding.Severity.INFO

var sector_index: int = -1
## Did the checks run (`findings` is meaningful)?
var checked := false
## Did the what-changed report run?
var compared := false
## The reachability search was part of the checks (the findings of `reach.*` can be there).
var with_reach := false
var findings: Array[CheckFinding] = []
## The findings that sit somewhere on the map.
var marks: Array[Mark] = []
## The findings about the sector as a whole, or about something no screen holds.
var unplaced: Array[CheckFinding] = []
## Screens that differ from the original -> the first lines of what differs (strings). Empty when the report was not asked for or
## nothing differs.
var changed_screens: Dictionary = {}
## The other kinds of data that differ from the original ("header", "creatures", "script", "sprite meta"): they belong to no screen.
var changed_elsewhere: Array[String] = []
## The notes of the what-changed report (no original bytes, no original sector ...).
var notes: Array[String] = []

var _by_screen: Dictionary = {}          # screen -> Array[Mark]


## Places the findings and the differences of `report` on the map of `model`.
static func build(model: SectorOverviewModel, report: SectorReport, p_with_reach: bool) -> SectorOverviewChecks:
	var result := SectorOverviewChecks.new()
	result.sector_index = model.sector.index
	result.checked = report.checked
	result.with_reach = p_with_reach
	result.findings = report.findings
	for finding in report.findings:
		var mark := place(model, finding)
		if mark == null:
			result.unplaced.append(finding)
		else:
			result.marks.append(mark)
			if not result._by_screen.has(mark.screen):
				result._by_screen[mark.screen] = []
			result._by_screen[mark.screen].append(mark)
	if report.changes != null:
		result.compared = true
		result.notes = report.changes.notes
		for item in report.changes.items:
			if item.state != SectorChanges.State.CHANGED and item.state != SectorChanges.State.DELIBERATE:
				continue
			if item.kind == "screen" and item.subject.begins_with("screen ") and item.subject.trim_prefix("screen ").is_valid_int():
				var lines: Array[String] = ["%s (%s)" % [item.subject, SectorChanges.STATE_TEXT[item.state]]]
				lines.append_array(item.details)
				result.changed_screens[item.subject.trim_prefix("screen ").to_int()] = lines
			elif not result.changed_elsewhere.has(item.kind):
				result.changed_elsewhere.append(item.kind)
	return result


## Where `finding` goes on the map of `model`, or null when it is about the sector as a whole (or about something on no screen).
## "piece N" and "creature N ..." are found by number in the model's objects, wherever the data puts them; "trigger N" is the N-th
## trigger of the finding's screen; "end station", "start" and "launch" are the model's places; "left link" (and right, up, down)
## is a strip along that side of the screen; anything else with a screen is that screen.
static func place(model: SectorOverviewModel, finding: CheckFinding) -> Mark:
	var mark := Mark.new()
	mark.finding = finding
	var words := finding.object
	var number := RegEx.create_from_string("^(?:stale )?(piece|creature|trigger) (\\d+)").search(words)
	if number != null:
		var index := number.get_string(2).to_int()
		var object := {}
		match number.get_string(1):
			"piece":
				object = _object_of(model, [SectorOverviewModel.Kind.PIECE, SectorOverviewModel.Kind.CANISTER], index, -1)
			"creature":
				object = _object_of(model, [SectorOverviewModel.Kind.CREATURE], index, -1)
			"trigger":
				object = _object_of(model, [SectorOverviewModel.Kind.TRIGGER], index, finding.screen)
		return _on_object(mark, object, finding)
	var place_kind := -1
	match words:
		"end station":
			place_kind = SectorOverviewModel.Kind.DOCK
		"start":
			place_kind = SectorOverviewModel.Kind.START
		"launch":
			place_kind = SectorOverviewModel.Kind.LAUNCH
	if place_kind >= 0:
		return _on_object(mark, _object_of(model, [place_kind], 0, -1), finding)
	if finding.screen < 0 or finding.screen >= SectorData.SCREEN_COUNT:
		return null
	mark.screen = finding.screen
	mark.rect = Rect2(Vector2.ZERO, Vector2(TileGrid.PLAYFIELD_SIZE))
	var side := SectorChecks.SIDE_NAMES.find(words.trim_suffix(" link")) if words.ends_with(" link") else -1
	if side >= 0:
		mark.placed = Placed.SIDE
		mark.rect = _strip(side)
	return mark


static func _on_object(mark: Mark, object: Dictionary, finding: CheckFinding) -> Mark:
	if object.is_empty():
		if finding.screen < 0 or finding.screen >= SectorData.SCREEN_COUNT:
			return null
		mark.screen = finding.screen                    # the object is not there (a stale number): the screen it is said to be on
		mark.rect = Rect2(Vector2.ZERO, Vector2(TileGrid.PLAYFIELD_SIZE))
		return mark
	mark.placed = Placed.OBJECT
	mark.object = object
	mark.screen = object["screen"]
	mark.rect = object["rect"]
	return mark


## The object of one of `kinds` with number `index` (on `screen` unless that is -1), or an empty dictionary.
static func _object_of(model: SectorOverviewModel, kinds: Array, index: int, screen: int) -> Dictionary:
	for object in model.all_objects():
		if object["kind"] in kinds and object["index"] == index and (screen < 0 or object["screen"] == screen):
			return object
	return {}


static func _strip(side: int) -> Rect2:
	var size := Vector2(TileGrid.PLAYFIELD_SIZE)
	match side:
		SectorData.Direction.LEFT:
			return Rect2(Vector2.ZERO, Vector2(SIDE_STRIP, size.y))
		SectorData.Direction.RIGHT:
			return Rect2(Vector2(size.x - SIDE_STRIP, 0), Vector2(SIDE_STRIP, size.y))
		SectorData.Direction.UP:
			return Rect2(Vector2.ZERO, Vector2(size.x, SIDE_STRIP))
	return Rect2(Vector2(0, size.y - SIDE_STRIP), Vector2(size.x, SIDE_STRIP))


# --- asking ----------------------------------------------------------------------------------------------------------------

## The marks on `screen`, worst first (the order of the findings).
func marks_on(screen: int) -> Array[Mark]:
	var found: Array[Mark] = []
	found.assign(_by_screen.get(screen, []))
	return found


## The marks that belong to `object` (a dictionary of the model).
func marks_of(object: Dictionary) -> Array[Mark]:
	var found: Array[Mark] = []
	for mark in marks_on(object["screen"]):
		if mark.placed == Placed.OBJECT and mark.object == object:
			found.append(mark)
	return found


## The mark of `finding`, or null when it is unplaced.
func mark_of(finding: CheckFinding) -> Mark:
	for mark in marks:
		if mark.finding == finding:
			return mark
	return null


## The worst severity of the findings on `screen` that are not muted by the allow-list, or -1 when there are none; with
## `include_allowed` also those that are allowed (then -1 only when the screen has no finding at all).
func worst_on(screen: int, include_allowed: bool = false) -> int:
	var worst := -1
	for mark in marks_on(screen):
		if include_allowed or mark.finding.allowed.is_empty():
			worst = maxi(worst, mark.finding.severity)
	return worst


## How many findings are on `screen` (not counting the muted ones unless `include_muted`).
func count_on(screen: int, include_muted: bool = false) -> int:
	var count := 0
	for mark in marks_on(screen):
		if include_muted or not mark.muted():
			count += 1
	return count


func is_changed(screen: int) -> bool:
	return changed_screens.has(screen)


## One line for the status bar: what the checks and the comparison found.
func summary() -> String:
	var parts: Array[String] = []
	if checked:
		parts.append("checks: %s%s" % [SectorChecks.summary(findings), "" if with_reach else " (without the reachability search: switch on Reachable to include it)"])
	if compared:
		var text := "%d of %d screens differ from the original" % [changed_screens.size(), SectorData.SCREEN_COUNT] if not changed_screens.is_empty() else "no screen differs from the original"
		if not changed_elsewhere.is_empty():
			text += "; also differing: " + ", ".join(changed_elsewhere)
		parts.append(text)
		parts.append_array(notes)
	return "\n".join(parts)


## The text under a finding in the list and in the info panel: its line, and the reason when it is allowed.
static func describe(finding: CheckFinding) -> String:
	var where := "screen %d" % finding.screen if finding.screen >= 0 else "sector"
	if not finding.object.is_empty():
		where += " " + finding.object
	var text := "%s, %s: %s [%s]" % [CheckFinding.SEVERITY_NAMES[finding.severity], where, finding.message, finding.check]
	if not finding.allowed.is_empty():
		text += "\n(allowed, the original is like this: %s)" % finding.allowed
	return text
