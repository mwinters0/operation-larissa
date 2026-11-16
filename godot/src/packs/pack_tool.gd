extends Node
## The pack tools on the command line: list, check, export, install, uninstall, new. The editor's "Pack tools" window runs this
## same scene in a process of its own, so what it shows is exactly what a terminal prints.
##
## Run from the repository root (a scene, not `-s`: the scripts it loads need the autoloads, like `check_sector.tscn`). Options after `--`:
##   --list                    the packs that are installed or come with the game, the chain the game uses and why
##   --pack=<id>               (before the tools run) choose the pack the game uses, as `godot ... -- --pack=<id>` does
##   --packs-dir=<folder>      (before the tools run) the folder installed packs live in (default user://packs/, `Packs.installed_dir`): --list, --install, --uninstall and a pack found by its id use it
##   --check=<where>           check a pack: a folder with a pack.json, or the id of a pack that was found (repeatable)
##   --no-reach                (with --check, --export-*) skip the reachability search
##   --export-campaign=<id>    export the campaign <id> in the data form into --out (a folder; with --archive one .larissa pack file)
##   --export-pack=<id>        export the complete pack <id> (dev, legacy, a copy of dev) in the data form into --out (a folder; with --archive one .larissa pack file)
##   --archive-folder=<folder> write a pack folder you made by hand (an example pack) as the pack file <id>.larissa in --out, checked first, with the pack it is laid over found as usual (repeatable)
##   --out=<dir>               where exports go (default user://pack_exports)
##   --pack-id= --title= --version= --author= --description=   what goes in the manifest (the campaign's or source pack's own by default)
##   --install=<where>         copy a pack (a folder or a .larissa pack file) into the installed-packs folder (dev included, unless the project has its own)
##   --base=<id>               (with --export-campaign) the pack the exported pack is laid over (default: the complete pack at the bottom of the chain in use)
##   --uninstall=<id>          delete an installed pack from the installed-packs folder
##   --pictures-table=<folder> write <folder>/pictures.json from the <kind>/<name>.png files under it (a row for each file no row names; the rows it holds stay), then check it with --check=<folder>
##   --new=<id>                start a pack of your own: copy the pack --from (default dev) to res://packs/<id>, with new paths and UIDs and a new pack.json
##                             (--title= names it); refuses an id that is taken or reserved (dev). Import it afterwards (`godot --headless --path godot --import`).
##   --from=<pack>             (with --new) the pack to copy, a folder of res://packs/ (default dev)
## Several may be given and run in the order: install, uninstall, new, pictures-table, check, export, archive-folder. Examples:
##   tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --export-campaign=orchard --out=/tmp/packs --archive
##   tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --export-pack=legacy --out=/tmp/packs --archive
##   tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --check=/tmp/packs/orchard
## The exit code is 1 when a check found an error, an export left nothing behind, or an install failed; 2 for a bad option.
## (user:// is the game's data folder: `ProjectSettings.globalize_path("user://")`.)

## The option that says where installed packs live: `--packs-dir=<folder>`.
const PACKS_DIR_OPTION := "--packs-dir="

var _failed := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with(PACKS_DIR_OPTION):
			Packs.installed_dir = arg.trim_prefix(PACKS_DIR_OPTION)
	Packs.start(args)                       # (`--pack=<id>` chooses the pack the checks and exports see)
	var values := {}
	var to_install: Array[String] = []
	var to_uninstall: Array[String] = []
	var to_check: Array[String] = []
	var to_tabulate: Array[String] = []
	var to_make: Array[String] = []
	var campaigns: Array[String] = []
	var packs: Array[String] = []
	var folders: Array[String] = []
	var listing := false
	var reach := true
	var archive := false
	for arg in args:
		if arg == "--list":
			listing = true
		elif arg == "--no-reach":
			reach = false
		elif arg == "--archive":
			archive = true
		elif arg.begins_with("--") and arg.contains("="):
			var key := arg.get_slice("=", 0).trim_prefix("--")
			var value := arg.substr(arg.find("=") + 1)
			match key:
				"install": to_install.append(value)
				"uninstall": to_uninstall.append(value)
				"new": to_make.append(value)
				"check": to_check.append(value)
				"pictures-table": to_tabulate.append(value)
				"export-campaign": campaigns.append(value)
				"export-pack": packs.append(value)
				"archive-folder": folders.append(value)
				"out", "pack-id", "title", "version", "author", "description", "base", "pack", "from", "packs-dir": values[key] = value
				_:
					_bad(arg)
					return
		else:
			_bad(arg)
			return
	if args.is_empty():
		listing = true
	for source in to_install:
		_report_install(PackInstall.install(source))
	for id in to_uninstall:
		var failure := PackInstall.uninstall(StringName(id))
		print("uninstalled %s" % id if failure.is_empty() else "error: " + failure)
		_failed += 0 if failure.is_empty() else 1
	for id in to_make:
		var made := PackCopy.make(StringName(id), StringName(values.get("from", String(Packs.DEV))), values.get("title", ""))
		print(made.message if made.ok else "error: " + made.message)
		_failed += 0 if made.ok else 1
	for folder in to_tabulate:
		var written := PackPictures.write(folder)
		print(written.text())
		_failed += 0 if written.ok() else 1
	for where in to_check:
		_print_report(PackCheck.run(PackCheck.open(where), _check_options(reach)))
	var options := PackExport.Options.new()
	options.pack_id = StringName(values.get("pack-id", ""))
	options.title = values.get("title", "")
	options.version = values.get("version", "1.0")
	options.author = values.get("author", "")
	options.description = values.get("description", "")
	options.base = StringName(values.get("base", ""))
	options.archive = archive
	options.reach = reach
	var out: String = values.get("out", "user://pack_exports")
	for id in campaigns:
		_print_export(PackExport.campaign(StringName(id), out, options))
	for id in packs:
		_print_export(PackExport.complete(StringName(id), out, options))
	for folder in folders:
		_print_export(PackExport.archive_folder(folder, out, options))
	if listing:
		_list()
	get_tree().quit(1 if _failed > 0 else 0)


func _check_options(reach: bool) -> PackCheck.Options:
	var options := PackCheck.Options.new()
	options.reach = reach
	return options


func _bad(arg: String) -> void:
	printerr("pack_tool: unknown option '%s'; see the comment at the top of pack_tool.gd" % arg)
	get_tree().quit(2)


func _report_install(result: PackInstall.Result) -> void:
	print(result.message if result.ok else "error: " + result.message)
	_failed += 0 if result.ok else 1


func _print_report(report: PackReport, note: String = "") -> void:
	print(report.text())
	if not note.is_empty():
		print(note)
	if not report.passes():
		_failed += 1
	print("")


func _print_export(result: PackExport.Result) -> void:
	print(result.text())
	print("")
	if not result.ok():
		_failed += 1


func _list() -> void:
	print(PackChoice.summary())
	var entries := PackChoice.entries()
	if entries.is_empty():
		print("no packs are installed (packs go in %s)" % ProjectSettings.globalize_path(Packs.installed_dir))
	for entry in entries:
		print("%-20s %-7s %s  (%s)" % [entry.id(), PackChoice.state_text(entry), entry.pack.title, entry.pack.root])
