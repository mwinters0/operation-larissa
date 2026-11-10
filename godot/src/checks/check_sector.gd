extends Node
## "Check sector" on the command line: the what-changed report and the playability checks of one or more sectors.
##
## Run from godot/:   ../tools/godot.sh --headless --path . res://src/checks/check_sector.tscn -- --sector=3
## (a scene, not `-s`: the scripts it loads need the autoloads, like `reach_report.tscn`.) Options after `--`:
##   --sector=3,7      the sectors to check (default: every sector that exists, `Catalog.sector_ids`: the 32 originals and any made since); --all says the same
##   --file=res://data/sectors/sector_40/sector_40.tres   a sector file (e.g. a sector made by a designer, or in the legacy pack: res://packs/legacy/data/sectors/...); repeatable
##   --changes         only the what-changed report;   --checks   only the playability checks
##   --no-reach        skip the reachability search (instant instead of a few seconds per sector)
##   --shared          also report the tables the whole game shares (trigger table, default levels, problems)
##   --pack=<id>       the pack the sectors and tables come from, as for the game (default: the first pack found)
## The exit code is 1 when a playability check fails (an error or warning that is not on SectorChecks.ORIGINAL_ALLOWED), else 0.
## What the report says is explained in `SectorChanges` and `SectorChecks`.


func _ready() -> void:
	var sectors: Array[SectorData] = []
	var changes := true
	var checks := true
	var reach := true
	var shared := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sector="):
			for number in arg.trim_prefix("--sector=").split(",", false):
				sectors.append(_load(Catalog.sector_path(int(number))))
		elif arg.begins_with("--file="):
			sectors.append(_load(arg.trim_prefix("--file=")))
		elif arg == "--all":
			sectors.append_array(_all())
		elif arg == "--changes":
			checks = false
		elif arg == "--checks":
			changes = false
		elif arg == "--no-reach":
			reach = false
		elif arg == "--shared":
			shared = true
		elif arg.begins_with(Packs.PACK_OPTION):
			pass                                         # (`--pack=<id>` chooses the pack the sectors and tables come from: `Packs` reads it itself)
		else:
			printerr("check_sector: unknown option '%s'; see the comment at the top of check_sector.gd" % arg)
			get_tree().quit(2)
			return
	if sectors.is_empty():
		sectors = _all()
	var failed := 0
	var loaded: Array[SectorData] = []
	for sector in sectors:
		if sector == null:
			printerr("check_sector: a sector file could not be loaded")
			failed += 1
		else:
			loaded.append(sector)
	var reports := SectorReport.make_many(loaded, changes, checks, reach)
	for k in reports.size():
		if shared and k == 0:
			reports[k].shared = SectorChanges.shared_report()
		print(reports[k].text())
		print("")
		if not reports[k].passes():
			failed += 1
	get_tree().quit(1 if failed > 0 else 0)


## Every sector that exists. A sector with a number above 31 has no original to compare with: its report says so and the
## playability checks are all there is (`SectorChanges.report`).
func _all() -> Array[SectorData]:
	var out: Array[SectorData] = []
	for i in Catalog.sector_ids():
		out.append(Catalog.sector(i) if Packs.sector_owner(i) != null else _load(Catalog.sector_path(i)))     # (a pack's sector has no .tres)
	return out


## Loads a sector file the way `Catalog.sector` does, bypassing its cache (a file on disk may be newer than a cached copy).
func _load(path: String) -> SectorData:
	var sector := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as SectorData
	if sector != null:
		sector.ensure_compiled()
	return sector
