extends Node
## Prints the reachability sweep of every sector (see `ReachSweep`).
##
## Run from godot/:  ../tools/godot.sh --headless --path . res://src/debug/reach_report.tscn
## (a scene, not `-s`: the scripts it loads need the autoloads). Optional user arguments after `--`: sector numbers to limit the run, e.g.  -- 1 30 31


func _ready() -> void:
	var wanted: Array[int] = []
	for arg in OS.get_cmdline_user_args():
		wanted.append(int(arg))
	if wanted.is_empty():
		wanted.append_array(Catalog.sector_ids())
	var started := Time.get_ticks_msec()
	var jobs: Array = []
	var rule_values := Tuning.resolve()
	for i in wanted:
		jobs.append(ReachSweep.prepare(i, rule_values))
	var prepared := Time.get_ticks_msec()
	var results := ReachSweep.run_all(jobs)
	var finished := Time.get_ticks_msec()
	for r: Dictionary in results:
		print(ReachSweep.report_line(r))
		for p: Dictionary in r["pieces"]:
			if p["orig_level"] != 0 or p["port_level"] != 0:
				print("    piece %d screen %d pos %s: original rule %s, port rule %s %s" % [
						p["index"], p["screen"], p["pos"], ReachSweep.MODE_NAMES[p["orig_level"]] if p["orig_level"] >= 0 else "UNREACHABLE",
						ReachSweep.MODE_NAMES[p["port_level"]] if p["port_level"] >= 0 else "UNREACHABLE", p["port_cells"]])
		for p: Dictionary in r["pieces"]:
			var main_cells: bool = 2 in p["port_cells"] or 6 in p["port_cells"]
			if p["orig_level"] == 0 and (p["orig_count"] < 20 or p["port_count"] < 8 or not main_cells):
				print("    fragile: sector %d piece %d screen %d pos %s: reachable contact states original %d, port %d (cells %s)" % [
						r["index"], p["index"], p["screen"], p["pos"], p["orig_count"], p["port_count"], p["port_cells"]])
		if r.has("finale"):
			print("    finale: %s   port start: %s" % [r["finale"], r["finale_port_start"]])
		if r.has("respawn_missing") and not r["respawn_missing"].is_empty():
			print("    from the respawn point pieces %s are unreachable" % [r["respawn_missing"]])
		if r.has("respawn_dock") and r["respawn_dock"] < 0:
			print("    from the respawn point the dock is unreachable")
		if r["launch_embedded"] > 0:
			print("    launch position overlaps %d solid tiles" % r["launch_embedded"])
		if r.get("respawn_embedded", 0) > 0:
			print("    respawn position overlaps %d solid tiles" % r["respawn_embedded"])
	for threshold in [ReachSweep.STRONG_CURRENT, 8, 6]:
		var effects := ReachSweep.parallel(jobs, ReachSweep.strong_current_effect.bind(threshold))
		for k in jobs.size():
			var effect: Dictionary = effects[k]
			if effect["strong_tiles"] > 0:
				print("currents >= %d: sector %d: %d tiles, %d states; pieces out of reach if impassable: %s, dock lost: %s" % [
						threshold, jobs[k]["index"], effect["strong_tiles"], effect["strong_states"], effect["lost_pieces"], effect["lost_dock"]])
	var in_currents := ReachSweep.parallel(jobs, ReachSweep.pieces_in_currents)
	for k in jobs.size():
		for e: Dictionary in in_currents[k]:
			if e["in_current"] == e["contact_states"]:
				print("current-only contact: sector %d piece %d screen %d: all %d contact states are in a current tile" % [jobs[k]["index"], e["index"], e["screen"], e["contact_states"]])
	var chokes := ReachSweep.parallel(jobs, ReachSweep.creature_choke)
	for k in jobs.size():
		var choke: Dictionary = chokes[k]
		if not choke["forced"].is_empty():
			print("creatures sector %d: %d fixed hostile creatures; forced: %s" % [jobs[k]["index"], choke["fixed"].size(), choke["forced"]])
		elif not choke["fixed"].is_empty():
			print("creatures sector %d: %d fixed hostile creatures, none forces a contact" % [jobs[k]["index"], choke["fixed"].size()])
	for i in wanted:
		var findings := ReachSweep.data_findings(Catalog.sector(i))
		for key: String in findings:
			for line: String in findings[key]:
				print("data sector %d %s: %s" % [i, key, line])
	print("prepare %.1fs, search %.1fs" % [(prepared - started) / 1000.0, (finished - prepared) / 1000.0])
	get_tree().quit()
