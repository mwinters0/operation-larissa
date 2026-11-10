@tool
class_name SectorReport
extends RefCounted
## "Check sector": the what-changed report (`SectorChanges`) and the playability checks (`SectorChecks`) of one sector, as one text or
## one piece of BBCode. This is what the command line tool (`res://src/checks/check_sector.tscn`) prints and what the editor's Sector
## Checks panel shows (`addons/sector_checks/`).
##
## Teaches: keeping the "what is true" (findings and change items, plain data) apart from "how it is shown" (text for a terminal,
## BBCode for a `RichTextLabel`): the same result feeds both, and a test reads the data.

var sector: SectorData
## The sector against the original, or null when it was not asked for.
var changes: SectorChanges.Report
## The tables the whole game shares against the original, or null.
var shared: SectorChanges.Report
## The playability findings, or empty when the checks were not asked for.
var findings: Array[CheckFinding] = []
var checked := false
var _pending: SectorChecks.Pending


## Runs what is asked for. `reach` false skips the reachability search (a few seconds); `with_shared` adds the shared tables.
static func make(p_sector: SectorData, with_changes: bool = true, with_checks: bool = true, reach: bool = true, with_shared: bool = false) -> SectorReport:
	var report := begin(p_sector, with_changes, with_checks, reach, with_shared)
	report.search()
	report.complete()
	return report


## The same in three steps, so that the slow one can run on another thread (`SectorCheckTask` does): `begin` makes the what-changed
## report and the instant checks and prepares the search (on the calling thread, which is the one that may touch the sector's
## resources); `search()` is the reachability search, which may run on a worker thread; `complete()` makes `findings` (on the calling thread).
static func begin(p_sector: SectorData, with_changes: bool = true, with_checks: bool = true, reach: bool = true, with_shared: bool = false) -> SectorReport:
	var report := SectorReport.new()
	report.sector = p_sector
	if with_changes:
		report.changes = SectorChanges.report(p_sector)
		if with_shared:
			report.shared = SectorChanges.shared_report()
	if with_checks:
		var options := SectorChecks.Options.new()
		options.reach = reach
		report._pending = SectorChecks.begin(p_sector, options)
	return report


## The reachability search of `begin` (nothing when it is not asked for). Thread-safe.
func search() -> void:
	if _pending != null:
		_pending.search()


## Is there a reachability search to run (asked for, and the sector can be searched)?
func has_search() -> bool:
	return _pending != null and not _pending.job.is_empty()


## Fills `findings` once `search()` is done.
func complete() -> void:
	if _pending != null:
		findings = _pending.finish()
		checked = true
		_pending = null


## The same for several sectors; the reachability searches run side by side on the worker threads (`SectorChecks.check_many`).
static func make_many(sectors: Array[SectorData], with_changes: bool = true, with_checks: bool = true, reach: bool = true) -> Array[SectorReport]:
	var out: Array[SectorReport] = []
	var all_findings: Array = []
	if with_checks:
		var options := SectorChecks.Options.new()
		options.reach = reach
		all_findings = SectorChecks.check_many(sectors, options)
	for k in sectors.size():
		var report := SectorReport.new()
		report.sector = sectors[k]
		if with_changes:
			report.changes = SectorChanges.report(sectors[k])
		if with_checks:
			report.findings.assign(all_findings[k])
			report.checked = true
		out.append(report)
	return out


## Do the playability checks pass (no error or warning that is not on the allow-list)? True when they were not run.
func passes() -> bool:
	return SectorChecks.passes(findings)


func text() -> String:
	var parts: Array[String] = []
	if changes != null:
		parts.append(changes.text())
	if shared != null:
		parts.append(shared.text())
	if checked:
		parts.append(checks_text())
	return "\n\n".join(parts)


func checks_text() -> String:
	var lines: Array[String] = ["Playability checks of sector %d: %s (%s)" % [sector.index, "pass" if passes() else "FAIL", SectorChecks.summary(findings)]]
	for finding in findings:
		lines.append("  " + finding.text())
	return "\n".join(lines)


## The same as `text()` in BBCode for a RichTextLabel: headings bold, differences in a warm colour, errors red, what passes green.
func bbcode() -> String:
	var parts: Array[String] = []
	if changes != null:
		parts.append(_changes_bbcode(changes))
	if shared != null:
		parts.append(_changes_bbcode(shared))
	if checked:
		parts.append(_checks_bbcode())
	return "\n\n".join(parts)


static func _changes_bbcode(report: SectorChanges.Report) -> String:
	var lines: Array[String] = ["[b]%s[/b]" % _escape(report.title)]
	for kind in report.kinds():
		var group: Array[SectorChanges.Item] = []
		for item in report.items:
			if item.kind == kind:
				group.append(item)
		var differing: Array[SectorChanges.Item] = []
		for item in group:
			if item.state == SectorChanges.State.CHANGED or item.state == SectorChanges.State.DELIBERATE:
				differing.append(item)
		if differing.is_empty():
			lines.append("  %s: [color=#4caf50]%s[/color]" % [_escape(kind), _escape(SectorChanges.STATE_TEXT[group[0].state] if group.size() == 1 else "all %d %s" % [group.size(), SectorChanges.STATE_TEXT[group[0].state]])])
			continue
		lines.append("  %s: [color=#e0a030]%d of %d differ[/color]" % [_escape(kind), differing.size(), group.size()])
		for item in differing:
			lines.append("    [b]%s[/b] %s" % [_escape(item.subject if not item.subject.is_empty() else item.kind), _escape(SectorChanges.STATE_TEXT[item.state])])
			for detail in item.details:
				lines.append("        " + _escape(detail))
	for note in report.notes:
		lines.append("  [i]%s[/i]" % _escape(note))
	return "\n".join(lines)


func _checks_bbcode() -> String:
	var colour := "#4caf50" if passes() else "#e04040"
	var lines: Array[String] = ["[b]Playability checks of sector %d:[/b] [color=%s]%s[/color] (%s)" % [sector.index, colour, "pass" if passes() else "FAIL", SectorChecks.summary(findings)]]
	for finding in findings:
		var tint := "#e04040" if finding.severity == CheckFinding.Severity.ERROR else ("#e0a030" if finding.severity == CheckFinding.Severity.WARNING else "#8899aa")
		if not finding.allowed.is_empty():
			tint = "#8899aa"
		lines.append("  [color=%s]%s[/color]" % [tint, _escape(finding.text())])
	return "\n".join(lines)


## BBCode treats "[" as the start of a tag; the reports are full of "[reach.piece]" and "[b]", so print them as they are.
static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
