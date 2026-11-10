class_name PackFiles
extends RefCounted
## The file work of the pack tools, in one place: list a folder, copy it, write a file, delete a folder, zip it. Plain functions on plain paths
## (`res://`, `user://` or the file system), so the exporter, the installer and the tests all do it the same way. Reading a pack's files is `Pack`'s (a folder or a pack file); a pack file is
## unpacked by nobody: the game reads it in place (`PackArchive`).
##
## Teaches: `ZIPPacker` (a folder as one archive; what is stored and what is deflated), and plain recursive folder walks with `DirAccess`.


## Every file under `dir` as a path relative to it, sorted (`a/b.json`). Empty for a folder that is not there.
static func files_under(dir: String) -> Array[String]:
	var found: Array[String] = []
	var pending: Array[String] = [""]
	while not pending.is_empty():
		var sub: String = pending.pop_back()
		var full := dir if sub.is_empty() else "%s/%s" % [dir, sub]
		for file in DirAccess.get_files_at(full):
			found.append(file if sub.is_empty() else "%s/%s" % [sub, file])
		for folder in DirAccess.get_directories_at(full):
			pending.append(folder if sub.is_empty() else "%s/%s" % [sub, folder])
	found.sort()
	return found


## Copies one file (its bytes), making the folders. `OK` or the error.
static func copy_file(from: String, to: String) -> Error:
	var bytes := FileAccess.get_file_as_bytes(from)
	if bytes.is_empty() and FileAccess.get_open_error() != OK:
		return FileAccess.get_open_error()
	return write_bytes(to, bytes)


static func write_bytes(to: String, bytes: PackedByteArray) -> Error:
	var made := DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	if made != OK:
		return made
	var file := FileAccess.open(to, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	return OK


static func write_text(to: String, text: String) -> Error:
	return write_bytes(to, text.to_utf8_buffer())


## Copies the folder `from` into `to` (made if needed), every file but those `skip` says no to (a Callable taking the relative path).
static func copy_tree(from: String, to: String, skip: Callable = Callable()) -> Error:
	DirAccess.make_dir_recursive_absolute(to)
	for rel in files_under(from):
		if skip.is_valid() and skip.call(rel):
			continue
		var error := copy_file("%s/%s" % [from, rel], "%s/%s" % [to, rel])
		if error != OK:
			return error
	return OK


## Deletes the folder and everything in it. (Nothing happens for a folder that is not there.)
static func remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute("%s/%s" % [dir, file])
	for folder in DirAccess.get_directories_at(dir):
		remove_tree("%s/%s" % [dir, folder])
	DirAccess.remove_absolute(dir)


## The files of a pack that are already compressed (pictures, songs, speech, sound effects, MIDI): deflating them again costs time and gains nothing, so `zip_folder` stores them.
const _COMPRESSED_EXTENSIONS: Array[String] = ["png", "ogg", "wav", "mid", "midi"]


## Writes the folder `dir` as the zip `zip_path`, every file under the folder name `top` ("orchard/pack.json"). Files that are compressed already (`_COMPRESSED_EXTENSIONS`) are
## stored without compression (`ZIPPacker.COMPRESSION_NONE`), the others deflated. `OK` or the error.
static func zip_folder(dir: String, zip_path: String, top: String) -> Error:
	DirAccess.make_dir_recursive_absolute(zip_path.get_base_dir())
	var packer := ZIPPacker.new()
	var error := packer.open(zip_path)
	if error != OK:
		return error
	for rel in files_under(dir):
		packer.compression_level = ZIPPacker.COMPRESSION_NONE if _COMPRESSED_EXTENSIONS.has(rel.get_extension().to_lower()) else ZIPPacker.COMPRESSION_DEFAULT
		packer.start_file("%s/%s" % [top, rel])
		packer.write_file(FileAccess.get_file_as_bytes("%s/%s" % [dir, rel]))
		packer.close_file()
	return packer.close()
