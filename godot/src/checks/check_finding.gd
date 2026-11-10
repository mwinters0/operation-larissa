@tool
class_name CheckFinding
extends RefCounted
## One thing a playability check found: how bad it is, where it is, and what is wrong, in plain words.
##
## Teaches: a result as DATA (a small object with fields) instead of a printed line: the same finding is a line on the
## command line (`text()`), a coloured line in the editor's report panel, a failed assertion in a test, or an entry in an
## allow-list, because it says WHICH check found it and WHERE. `SectorChecks` makes them.

## ERROR: the sector cannot be stored as the original's data or cannot be played / finished as designed. WARNING: unusual,
## worth a look (a one-way door, a piece only reachable by slipping round a corner). INFO: a remark, or a check that was
## skipped. Higher is worse, so findings sort and compare.
enum Severity { INFO, WARNING, ERROR }

const SEVERITY_NAMES: Array[String] = ["info", "warning", "error"]

var severity: Severity = Severity.ERROR
## The id of the check that found it, e.g. "link.one_way" or "reach.piece" (the list is in `SectorChecks`).
var check: String = ""
var sector: int = -1
## The screen it is on, or -1 for a finding about the whole sector.
var screen: int = -1
## What it is about, e.g. "piece 3", "creature 7 ink_label", "left neighbour of screen 2"; "" for the sector itself.
var object: String = ""
var message: String = ""
## Not empty when this finding is how the ORIGINAL sector is (an allow-list entry of `SectorChecks.ORIGINAL_ALLOWED`): the
## reason. An allowed finding does not make a sector fail.
var allowed: String = ""


static func make(p_severity: Severity, p_check: String, p_sector: int, p_screen: int, p_object: String, p_message: String) -> CheckFinding:
	var finding := CheckFinding.new()
	finding.severity = p_severity
	finding.check = p_check
	finding.sector = p_sector
	finding.screen = p_screen
	finding.object = p_object
	finding.message = p_message
	return finding


## Does this finding stop the sector from passing? (An error or a warning that is not on the allow-list.)
func fails() -> bool:
	return allowed.is_empty() and severity != Severity.INFO


## "error: sector 3 screen 5 piece 2: no position the sub can reach touches it  [reach.piece]", with "(the original is like
## this: reason)" after an allowed one.
func text() -> String:
	var where := "sector %d" % sector if sector >= 0 else "sector"
	if screen >= 0:
		where += " screen %d" % screen
	if not object.is_empty():
		where += " " + object
	var line := "%s: %s: %s  [%s]" % [SEVERITY_NAMES[severity], where, message, check]
	if not allowed.is_empty():
		line += "  (allowed, the original is like this: %s)" % allowed
	return line
