class_name PackInstall
extends RefCounted
## Puts a pack where the game looks for packs (`user://packs/`) and takes it away again. A pack comes as a FOLDER with a `pack.json` or a PACK FILE, `<id>.larissa`
## (`Pack.FILE_EXTENSION`: a zip of the folder, what `PackExport` makes with `archive`). Installing copies; it runs nothing: a pack outside the project is read as data (`Pack.trusted`), and the script of a mod
## pack runs, sandboxed, only while the pack is in the chain in use (`ModHost`). A folder is installed as the folder `user://packs/<id>`. A pack file is installed as the FILE `user://packs/<id>.larissa`
## (its `pack.json` names the id; the file is checked by `PackArchive` first and is never extracted: the game reads it where it lies). An id is installed in one form at a time: installing either form of an id
## takes away the other, and `uninstall` takes away whichever is there. Whether the game uses the pack is `Packs`' business (`--pack=<id>`, or the first pack found), not something installing decides.
## The pack files a game carries next to it (`legacy.larissa`, `dev.larissa`) are not installed: they are read where they are (`Packs`, "Where packs are found").
##
## Teaches: putting a file in a folder is harmless; running what is in it is the decision. And why a pack file is let go of (`Pack.close`) before the file under it is replaced or deleted.

## Where installed packs live (`Packs.available` looks here and in `res://packs/`).
const DIR := Packs.USER_PACKS_DIR


class Result extends RefCounted:
	var ok := false
	var id: StringName = &""
	## The installed folder.
	var path := ""
	## What happened, in a sentence.
	var message := ""


## Installs the pack at `source` (a folder or a `.larissa` pack file, a path on disk or in `user://`). `reset` false leaves the chain alone; otherwise a new copy of a pack in use makes the game look at it again.
static func install(source: String, reset := true) -> Result:
	var result := _install(source)
	if reset and result.ok and Packs.in_chain(result.id):
		Packs.reset()                                   # (a new copy of a pack in use: the game looks at it again)
	return result


static func _install(source: String) -> Result:
	var result := Result.new()
	if source.get_extension() == Pack.FILE_EXTENSION and FileAccess.file_exists(source):
		return _install_file(source, result)
	if DirAccess.dir_exists_absolute(source):
		return _install_folder(source, result)
	result.message = "%s is not a folder or a .%s pack file" % [source, Pack.FILE_EXTENSION]
	return result


## Puts the pack file `source` in `DIR` as `<id>.larissa`: opened and judged first (`PackArchive`: a pack, safe paths, sizes within bounds), then copied whole.
static func _install_file(source: String, result: Result) -> Result:
	var pack := Pack.open(source)
	if not pack.is_valid():
		result.message = "not a pack: %s" % "; ".join(pack.errors)
		return result
	var why_not := refusal(pack.id)
	if not why_not.is_empty():
		result.message = why_not
		return result
	var target := file_of(pack.id)
	if ProjectSettings.globalize_path(source).simplify_path() != ProjectSettings.globalize_path(target).simplify_path():
		_take_away(pack.id)
		var part := target + ".part"
		var error := PackFiles.copy_file(source, part)
		if error == OK:
			error = DirAccess.rename_absolute(part, target)
		if error != OK:
			DirAccess.remove_absolute(part)
			result.message = "cannot copy the pack to %s: %s" % [target, error_string(error)]
			return result
	result.ok = true
	result.id = pack.id
	result.path = target
	result.message = "installed '%s' (%s) in %s" % [pack.id, pack.title, target]
	return result


## Puts the pack folder `source` in `DIR`, copied.
static func _install_folder(source: String, result: Result) -> Result:
	var pack := Pack.open(source)
	if not pack.is_valid():
		result.message = "not a pack: %s" % "; ".join(pack.errors)
		return result
	var why_not := refusal(pack.id)
	if not why_not.is_empty():
		result.message = why_not
		return result
	var target := folder_of(pack.id)
	if Packs.real_folder(source) != Packs.real_folder(target):
		_take_away(pack.id)
		var error := PackFiles.copy_tree(source, target)
		if error != OK:
			PackFiles.remove_tree(target)
			result.message = "cannot copy the pack to %s: %s" % [target, error_string(error)]
			return result
	result.ok = true
	result.id = pack.id
	result.path = target
	result.message = "installed '%s' (%s) in %s" % [pack.id, pack.title, target]
	return result


## Where the pack `id` is installed as a folder.
static func folder_of(id: StringName) -> String:
	return "%s/%s" % [DIR, id]


## Where the pack `id` is installed as a pack file.
static func file_of(id: StringName) -> String:
	return "%s/%s.%s" % [DIR, id, Pack.FILE_EXTENSION]


## Is the pack `id` installed, as a folder or as a pack file?
static func is_installed(id: StringName) -> bool:
	return DirAccess.dir_exists_absolute(folder_of(id)) or FileAccess.file_exists(file_of(id))


## Why `id` cannot be installed, or "": a pack of the project (`res://packs/<id>`, `dev` among them) would always win over a copy in `user://packs/`.
static func refusal(id: StringName) -> String:
	if DirAccess.dir_exists_absolute("%s/%s" % [Packs.PROJECT_PACKS_DIR, id]):
		return "the project itself has a pack called '%s' (in %s), which would be used instead of this one" % [id, Packs.PROJECT_PACKS_DIR]
	return ""


## Removes the installed pack `id`, folder or pack file (both, if both are there). "" or what went wrong. Only `user://packs/` is touched, never the project's own packs. If the game was using it,
## it chooses again (`Packs.reset`).
static func uninstall(id: StringName) -> String:
	if RegEx.create_from_string(Pack.ID_PATTERN).search(String(id)) == null:
		return "'%s' is not a pack id: nothing removed" % id
	if not is_installed(id):
		return "'%s' is not installed in %s" % [id, DIR]
	var was_in_use := Packs.in_chain(id)
	_take_away(id)
	if was_in_use:
		Packs.reset()
	return ""


## Deletes both installed forms of `id`. The pack file of a pack in use is let go of first (`Packs.release_file`): a file that a reader holds cannot be replaced or deleted on every system.
static func _take_away(id: StringName) -> void:
	Packs.release_file(id)
	PackFiles.remove_tree(folder_of(id))
	DirAccess.remove_absolute(file_of(id))
