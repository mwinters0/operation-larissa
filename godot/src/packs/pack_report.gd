class_name PackReport
extends RefCounted
## What `PackCheck` found out about one pack: a list of findings, each an ERROR (the pack cannot be exported or played as made) or a
## WARNING (odd, worth a look, plays anyway), and what the pack holds. One object for every user of the check: the export dialog and the command
## line print `text()`, the in-game list shows `summary()` and `bbcode()`, the tests read `findings`.
##
## Teaches: a result as DATA, as `CheckFinding` is for one sector. The pack tool never decides to stop by printing something: it asks `passes()`.

enum Severity { WARNING, ERROR }

const SEVERITY_NAMES: Array[String] = ["warning", "error"]

## One thing found: how bad, which part of the pack ("manifest", "layout", "conflict", "sector 41", "campaign orchard", "audio", "durations", ...) and what.
class Finding extends RefCounted:
	var severity: Severity = Severity.ERROR
	var area: String = ""
	var message: String = ""

	func text() -> String:
		return "%s: %s: %s" % [SEVERITY_NAMES[severity], area, message]

var pack_id: StringName = &""
var title: String = ""
## The folder (or pack file) that was checked.
var root: String = ""
## What the pack holds, for a list: the campaign ids and the sector numbers.
var campaigns: Array[StringName] = []
var sectors: Array[int] = []
var findings: Array[Finding] = []


## Notes what `pack` is (before anything is found out about it).
func describe(pack: Pack) -> void:
	pack_id = pack.id
	title = pack.title
	root = pack.root
	if pack.is_valid():
		campaigns = pack.campaign_ids()
		sectors = pack.sector_ids()


func add(severity: Severity, area: String, message: String) -> void:
	var finding := Finding.new()
	finding.severity = severity
	finding.area = area
	finding.message = message
	findings.append(finding)


func error(area: String, message: String) -> void:
	add(Severity.ERROR, area, message)


func warn(area: String, message: String) -> void:
	add(Severity.WARNING, area, message)


func errors() -> Array[Finding]:
	return findings.filter(func(f: Finding) -> bool: return f.severity == Severity.ERROR)


func warnings() -> Array[Finding]:
	return findings.filter(func(f: Finding) -> bool: return f.severity == Severity.WARNING)


## No errors: the pack may be exported, installed and used. (Warnings do not stop it.)
func passes() -> bool:
	return errors().is_empty()


## "orchard: 2 errors, 1 warning" or "orchard: no problems".
func summary() -> String:
	var bad := errors().size()
	var odd := warnings().size()
	if bad == 0 and odd == 0:
		return "%s: no problems" % _name()
	var parts := PackedStringArray()
	if bad > 0:
		parts.append("%d error%s" % [bad, "" if bad == 1 else "s"])
	if odd > 0:
		parts.append("%d warning%s" % [odd, "" if odd == 1 else "s"])
	return "%s: %s" % [_name(), ", ".join(parts)]


## The report for a terminal: a heading, one line per finding (errors first), the summary.
func text() -> String:
	var lines := PackedStringArray()
	lines.append("Pack %s (\"%s\") in %s" % [_name(), title, root])
	var held := PackedStringArray()
	if not campaigns.is_empty():
		held.append("campaigns %s" % ", ".join(PackedStringArray(campaigns.map(func(c: StringName) -> String: return String(c)))))
	if not sectors.is_empty():
		held.append("sectors %s" % ", ".join(PackedStringArray(sectors.map(func(n: int) -> String: return str(n)))))
	if not held.is_empty():
		lines.append("  holds " + "; ".join(held))
	for finding in errors() + warnings():
		lines.append("  " + finding.text())
	lines.append(summary())
	return "\n".join(lines)


## The same for a `RichTextLabel` (errors red, warnings yellow).
func bbcode() -> String:
	var lines := PackedStringArray()
	for finding in errors() + warnings():
		var color := "#ff6666" if finding.severity == Severity.ERROR else "#e8c85a"
		lines.append("[color=%s]%s[/color] %s: %s" % [color, SEVERITY_NAMES[finding.severity], finding.area.replace("[", "[lb]"), finding.message.replace("[", "[lb]")])
	lines.append("[b]%s[/b]" % summary().replace("[", "[lb]"))
	return "\n".join(lines)


func _name() -> String:
	return String(pack_id) if pack_id != &"" else "(no id)"
