extends Node
## The art templates tool on the command line: writes one flat-colour PNG per picture a skin may replace and per layer of the console a script may draw, with the key and size on it (`SkinTemplates`).
##
## Run from the repository root (a scene, not `-s`: it needs the autoloads). Options after `--`:
##   --out=<dir>     where the templates go, one folder per kind of key: `<dir>/ui_picture/ui_1195.png` (default user://skin_templates)
##   --pack=<id>     the pack whose layouts give the sizes (default the pack in use: dev when there is no other); `--pack=legacy` gives the original's sizes
##   --list          print the keys and sizes and write nothing
## Example:
##   tools/godot.sh --headless --path godot res://src/skins/skin_templates_tool.tscn -- --out=/tmp/templates
## (`mise run skin:templates` is the same with the folder `skin_templates` of the current directory.) The exit code is 1 when no template could be written, 2 for a bad option.
##
## Teaches: a command-line tool as a scene that reads `OS.get_cmdline_user_args()` and quits with an exit code, over a class (`SkinTemplates`) a test can call without a process.


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	Packs.start(args)
	var out := "user://skin_templates"
	var listing := false
	for arg in args:
		if arg == "--list":
			listing = true
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif not arg.begins_with(Packs.PACK_OPTION):
			printerr("skin_templates_tool: unknown option '%s'; see the comment at the top of skin_templates_tool.gd" % arg)
			get_tree().quit(2)
			return
	if listing:
		for entry in SkinTemplates.entries():
			print("%s  %d x %d" % [entry.key, entry.size.x, entry.size.y])
		get_tree().quit()
		return
	var failures: Array[String] = []
	var written := SkinTemplates.write(out, failures)
	for failure in failures:
		printerr("error: " + failure)
	print("wrote %d templates under %s" % [written.size(), ProjectSettings.globalize_path(out)])
	get_tree().quit(1 if written.is_empty() else 0)
