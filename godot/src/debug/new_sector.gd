extends Node
## "New sector" on the command line: makes a sector from the template or as a copy of another one, then you check it.
##
## Run from godot/:   ../tools/godot.sh --headless --path . res://src/debug/new_sector.tscn -- --template
##                    ../tools/godot.sh --headless --path . res://src/debug/new_sector.tscn -- --copy=5 --index=40
## (a scene, not `-s`: the scripts it loads need the autoloads, like `check_sector.tscn`.) Options after `--`:
##   --template          an empty sector: 12 screens with a floor, a canister, a piece, no creatures (the default without --copy)
##   --copy=5            a copy of sector 5 (any sector that exists) instead
##   --index=40          the number of the new sector (default: the next free one from 32 up; a number below 32 is refused)
##   --zone=2 --game=1   the zone (0-6) and game (0 Voyager, 1 Expert) of a template sector (default 0 and 0)
##   --dir=user://x      write into a folder of sector folders other than the project's res://data/sectors (a test, a scratch copy)
##   --source-dir=...    where --copy reads its source from (default: where the sector is, the legacy pack's or the project's, whatever --dir is)
## Prints the new sector's file and exits 0, or says why not and exits 1 (2 for an option it does not know). Then:
##   ../tools/godot.sh --headless --path . res://src/checks/check_sector.tscn -- --sector=40
## The work is `SectorFactory`; what a new sector is, is explained there.


func _ready() -> void:
	var copy := -1
	var index := -1
	var zone := 0
	var game := 0
	var dir := ""             # (the project's folder, `Catalog.sectors_dir`; a new number counts the sectors of the legacy pack too)
	var source_dir := ""      # (wherever the sector to copy is)
	for arg in OS.get_cmdline_user_args():
		if arg == "--template":
			copy = -1
		elif arg.begins_with("--copy="):
			copy = int(arg.trim_prefix("--copy="))
		elif arg.begins_with("--index="):
			index = int(arg.trim_prefix("--index="))
		elif arg.begins_with("--zone="):
			zone = int(arg.trim_prefix("--zone="))
		elif arg.begins_with("--game="):
			game = int(arg.trim_prefix("--game="))
		elif arg.begins_with("--dir="):
			dir = arg.trim_prefix("--dir=").trim_suffix("/")
		elif arg.begins_with("--source-dir="):
			source_dir = arg.trim_prefix("--source-dir=").trim_suffix("/")
		else:
			printerr("new_sector: unknown option '%s'; see the comment at the top of new_sector.gd" % arg)
			get_tree().quit(2)
			return
	var made: SectorFactory.Made
	if copy >= 0:
		made = SectorFactory.new_from_copy(copy, index, dir, source_dir)
	else:
		made = SectorFactory.new_from_template(index, zone, game, dir)
	if not made.ok():
		printerr("new_sector: %s" % made.error)
		get_tree().quit(1)
		return
	print("new_sector: made sector %d (%d files): %s" % [made.index, made.files.size(), made.path])
	get_tree().quit(0)
