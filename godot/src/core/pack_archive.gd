class_name PackArchive
extends RefCounted
## One open pack file (`<id>.larissa`, `Pack.FILE_EXTENSION`: a zip of a pack's folder), read IN PLACE: nothing is extracted.
##
## `open` reads the zip's CENTRAL DIRECTORY itself (the list at the end of the file: every entry's name, sizes, method, CRC-32 and where its data starts) and builds ONE index from it: the files with
## what it takes to read each, and the folders with what is in them. Every question about what the archive holds (`has`, `has_folder`, `size_of`, `files_in`, `folders_in`, `all_files`) is answered
## from that index. `read` goes straight to the entry: one seek to its local header, one read of its bytes, and for a deflated entry one `PackedByteArray.decompress`. There is no other zip reader
## here: the file is one `FileAccess`, opened on the first read and released by `close` (a file cannot be replaced or deleted on every system while it is held open; the next read opens it again).
##
## The archive is judged when it is opened, before anything is read from it (`errors` says what is wrong, and an archive with errors holds no files):
##   * the pack is found in it: at its root, or in the one folder in front of the files that holds `pack.json` (`folder`; a zip made by `PackFiles.zip_folder` has one, a zip made by hand may not);
##   * every path is `Pack.is_safe` (no `..`, no drive, no absolute path, no backslash), so every reader stays inside the pack;
##   * the sizes are bounded, `MAX_FILE_BYTES` for a file and `MAX_TOTAL_BYTES` for all of them. `read` allocates exactly the size the central directory declares before it reads, so a
##     hostile archive that claims two gigabytes for an entry is refused here and never reaches `read`; every entry's data lies in the file before the central directory;
##   * no entry is encrypted or stored in a form other than "stored" and "deflated", and the archive is not a ZIP64 one (a pack is far below the 4 GiB and 65535 entries of the plain format).
##
## Teaches: reading a file format with `FileAccess` and `PackedByteArray.decode_u16`/`decode_u32` (the end-of-central-directory record, then the directory's headers, all little-endian); why a
## size that comes out of a file must be checked before anything is allocated for it; and how a zip's raw deflate stream is inflated with Godot's gzip mode: a gzip member is a 10-byte header, the same
## raw deflate bytes and the CRC-32 and size a zip keeps in its directory, so zlib checks the data against the directory's CRC for us.

## The most one file of a pack may be, in bytes. The largest file of the original game's pack is a few megabytes (a song or a full-screen picture); a pack that needs more is made of a
## folder, which has no such limit. It is far below what a hostile header can claim (two gigabytes), and a few such files stay within `MAX_TOTAL_BYTES`.
const MAX_FILE_BYTES := 64 << 20      # (64 MiB)
## The most all the files of a pack file may add up to, in bytes (a campaign with all its pictures and a few songs is tens of megabytes).
const MAX_TOTAL_BYTES := 512 << 20     # (512 MiB)

const _EOCD_SIGNATURE := 0x06054b50
const _ZIP64_LOCATOR_SIGNATURE := 0x07064b50
const _CENTRAL_SIGNATURE := 0x02014b50
const _EOCD_SIZE := 22
const _CENTRAL_HEADER_SIZE := 46
## The end record sits in the last `_EOCD_SIZE` bytes plus a comment of at most 65535.
const _MAX_TAIL := _EOCD_SIZE + 0xFFFF
const _LOCAL_SIGNATURE := 0x04034b50
const _LOCAL_HEADER_SIZE := 30
const _STORED := 0
const _DEFLATED := 8
## The fields of an index entry (`_entries`): size, method, compressed size, CRC-32, where the entry's local header starts.
enum _Field { SIZE, METHOD, PACKED, CRC, OFFSET }
## The start of a gzip member whose data is a zip entry's raw deflate stream: magic, deflate, no flags, no time, no extra flags, "unknown" system.
const _GZIP_HEADER: PackedByteArray = [0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff]

## The path of the archive file.
var path := ""
## The folder of the zip that holds the pack: `""` for the archive's root, else the one folder in front of the files (`"orchard"`).
var folder := ""
## What is wrong with the archive, one sentence each; empty for one that can be read. An archive with errors holds no files.
var errors: Array[String] = []

## rel (a path inside the pack) -> a PackedInt64Array of `_Field`s. The whole index of the files.
var _entries: Dictionary = {}
## folder rel ("" is the pack's root) -> {"files": Array[String], "folders": Array[String]} (names, sorted). The whole index of the folders.
var _listing: Dictionary = {}
var _total := 0
## Where the central directory starts: the data of every entry lies before it.
var _directory_start := 0
var _file: FileAccess = null
## (The file is one cursor: one read at a time, whichever thread asks.)
var _lock := Mutex.new()


## The archive at `zip_path`, its central directory read and judged. Never null; check `errors` (`is_valid`).
static func open(zip_path: String) -> PackArchive:
	var archive := PackArchive.new()
	archive.path = zip_path
	archive._build()
	return archive


func is_valid() -> bool:
	return errors.is_empty()


## Is there the file `rel` (a path inside the pack, `data/zones.json`)?
func has(rel: String) -> bool:
	return _entries.has(rel)


## Is there the folder `rel` (a folder that holds a file somewhere below it)?
func has_folder(rel: String) -> bool:
	return not rel.is_empty() and _listing.has(rel)


## The size of the file `rel` in bytes, or -1 when there is none.
func size_of(rel: String) -> int:
	return _entries[rel][_Field.SIZE] if _entries.has(rel) else -1


## The names of the files in the folder `rel_dir` (`""` is the pack's root), sorted.
func files_in(rel_dir: String) -> PackedStringArray:
	return PackedStringArray(_listing[rel_dir]["files"]) if _listing.has(rel_dir) else PackedStringArray()


## The names of the folders in the folder `rel_dir` (`""` is the pack's root), sorted.
func folders_in(rel_dir: String) -> PackedStringArray:
	return PackedStringArray(_listing[rel_dir]["folders"]) if _listing.has(rel_dir) else PackedStringArray()


## Every file as a path relative to the pack, sorted.
func all_files() -> Array[String]:
	var found: Array[String] = []
	found.assign(_entries.keys())
	found.sort()
	return found


## What all the files add up to, in bytes.
func total_bytes() -> int:
	return _total


## The bytes of the file `rel`; empty when there is none, or when the entry cannot be read (a warning says why: damaged, or the data does not match its CRC-32).
func read(rel: String) -> PackedByteArray:
	if not _entries.has(rel):
		return PackedByteArray()
	_lock.lock()
	var bytes := _read_entry(rel, _entries[rel])
	_lock.unlock()
	return bytes


## Is the file open (a `read` has opened it and `close` has not let go of it)?
func is_open() -> bool:
	return _file != null


## Lets go of the file, so that it can be replaced or deleted. The index stays; a later `read` opens the file again.
func close() -> void:
	_lock.lock()
	_file = null
	_lock.unlock()


func _read_entry(rel: String, entry: PackedInt64Array) -> PackedByteArray:
	if _file == null:
		_file = FileAccess.open(path, FileAccess.READ)
		if _file == null:
			push_warning("PackArchive: cannot open %s" % path)
			return PackedByteArray()
	_file.seek(entry[_Field.OFFSET])
	var header := _file.get_buffer(_LOCAL_HEADER_SIZE)
	if header.size() < _LOCAL_HEADER_SIZE or header.decode_u32(0) != _LOCAL_SIGNATURE:
		push_warning("PackArchive: %s: the header of %s is damaged" % [path.get_file(), rel])
		return PackedByteArray()
	var start: int = entry[_Field.OFFSET] + _LOCAL_HEADER_SIZE + header.decode_u16(26) + header.decode_u16(28)      # (the local name and extra: not the central ones)
	if start + entry[_Field.PACKED] > _directory_start:
		push_warning("PackArchive: %s: the data of %s is not where it should be" % [path.get_file(), rel])
		return PackedByteArray()
	var size: int = entry[_Field.SIZE]
	if size == 0:
		return PackedByteArray()
	_file.seek(start)
	var packed := _file.get_buffer(entry[_Field.PACKED])
	if packed.size() != entry[_Field.PACKED]:
		push_warning("PackArchive: %s: %s is cut short" % [path.get_file(), rel])
		return PackedByteArray()
	if entry[_Field.METHOD] == _STORED:
		return packed
	var member := _GZIP_HEADER.duplicate()
	member.append_array(packed)
	_put(member, entry[_Field.CRC], 4)
	_put(member, size, 4)                                   # (the size modulo 2^32: the sizes of a pack are far below)
	var bytes := member.decompress(size, FileAccess.COMPRESSION_GZIP)
	if bytes.size() != size:
		push_warning("PackArchive: %s: %s does not unpack to what the archive says (damaged)" % [path.get_file(), rel])
		return PackedByteArray()
	return bytes


static func _put(buffer: PackedByteArray, value: int, width: int) -> void:
	var at := buffer.size()
	buffer.resize(at + width)
	if width == 4:
		buffer.encode_u32(at, value)
	else:
		buffer.encode_u16(at, value)


# --- reading the central directory ---------------------------------------------------------------------------------

func _build() -> void:
	var names := PackedStringArray()
	var entries: Array[PackedInt64Array] = []
	_read_directory(names, entries)
	if not errors.is_empty():
		return
	var found: Variant = _find_folder(names)
	if found == null:
		errors.append("%s holds no %s" % [path.get_file(), Pack.MANIFEST])
		return
	folder = found
	var strip := "" if folder.is_empty() else folder + "/"
	for i in names.size():
		if not names[i].begins_with(strip):
			continue                                          # (not in the pack: never read)
		var rel := names[i].trim_prefix(strip)
		if not Pack.is_safe(rel):
			errors.append("the archive holds a path that leaves the pack: %s" % names[i])
		elif _entries.has(rel):
			errors.append("the archive holds %s twice" % names[i])
		elif entries[i][_Field.SIZE] > MAX_FILE_BYTES:
			errors.append("%s is %d MB: a file of a pack may be at most %d MB" % [names[i], entries[i][_Field.SIZE] >> 20, MAX_FILE_BYTES >> 20])
		else:
			_total += entries[i][_Field.SIZE]
			_add(rel, entries[i])
	if _total > MAX_TOTAL_BYTES:
		errors.append("the archive unpacks to more than %d MB" % (MAX_TOTAL_BYTES >> 20))
	for dir: String in _listing:
		if _entries.has(dir):
			errors.append("%s is both a file and a folder" % dir)
	if not errors.is_empty():
		_entries = {}
		_listing = {}
		_total = 0
		return
	for dir: String in _listing:
		(_listing[dir]["files"] as Array).sort()
		(_listing[dir]["folders"] as Array).sort()


## The names and index entries (`_Field`s) of the files (not the folder entries) in the zip's central directory, in `names` and `entries`; `errors` says what is wrong with the zip.
func _read_directory(names: PackedStringArray, entries: Array[PackedInt64Array]) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("cannot open %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return
	var length := file.get_length()
	var tail_start := maxi(0, length - _MAX_TAIL)
	file.seek(tail_start)
	var tail := file.get_buffer(length - tail_start)
	var end := _find_end_record(tail)
	if end < 0:
		errors.append("%s is not a zip archive" % path.get_file())
		return
	if (end >= 20 and tail.decode_u32(end - 20) == _ZIP64_LOCATOR_SIGNATURE) or tail.decode_u16(end + 10) == 0xFFFF \
			or tail.decode_u32(end + 12) == 0xFFFFFFFF or tail.decode_u32(end + 16) == 0xFFFFFFFF:
		errors.append("%s is a ZIP64 archive, which a pack is not (the plain zip format holds 65535 files of up to 4 GB)" % path.get_file())
		return
	if tail.decode_u16(end + 4) != 0 or tail.decode_u16(end + 6) != 0 or tail.decode_u16(end + 8) != tail.decode_u16(end + 10):
		errors.append("%s is one part of an archive in several" % path.get_file())
		return
	var count := tail.decode_u16(end + 10)
	var directory_size := tail.decode_u32(end + 12)
	var directory_start := tail.decode_u32(end + 16)
	if directory_start + directory_size > tail_start + end:
		errors.append("%s is damaged: its list of files is not where it says" % path.get_file())
		return
	_directory_start = directory_start
	file.seek(directory_start)
	var directory := file.get_buffer(directory_size)
	if directory.size() != directory_size:
		errors.append("%s is damaged: its list of files is cut short" % path.get_file())
		return
	var at := 0
	for counted in count:
		if at + _CENTRAL_HEADER_SIZE > directory.size() or directory.decode_u32(at) != _CENTRAL_SIGNATURE:
			errors.append("%s is damaged: its list of files is not a list of files" % path.get_file())
			return
		var flags := directory.decode_u16(at + 8)
		var method := directory.decode_u16(at + 10)
		var crc := directory.decode_u32(at + 16)
		var packed := directory.decode_u32(at + 20)
		var declared := directory.decode_u32(at + 24)
		var offset := directory.decode_u32(at + 42)
		var name_length := directory.decode_u16(at + 28)
		var next := at + _CENTRAL_HEADER_SIZE + name_length + directory.decode_u16(at + 30) + directory.decode_u16(at + 32)
		if next > directory.size():
			errors.append("%s is damaged: its list of files is cut short" % path.get_file())
			return
		if declared == 0xFFFFFFFF or packed == 0xFFFFFFFF or offset == 0xFFFFFFFF:
			errors.append("%s is a ZIP64 archive, which a pack is not" % path.get_file())
			return
		var name := directory.slice(at + _CENTRAL_HEADER_SIZE, at + _CENTRAL_HEADER_SIZE + name_length).get_string_from_utf8()
		if not name.ends_with("/"):
			if flags & 1 != 0:
				errors.append("%s is encrypted" % name)
				return
			if method != _STORED and method != _DEFLATED:
				errors.append("%s is compressed in a way the game does not read" % name)
				return
			if (method == _STORED and packed != declared) or offset + _LOCAL_HEADER_SIZE + name_length + packed > directory_start:
				errors.append("%s is damaged: its data is not where the list of files says" % name)
				return
			names.append(name)
			entries.append(PackedInt64Array([declared, method, packed, crc, offset]))
		at = next


## Where the end-of-central-directory record starts in `tail` (the last bytes of the file), or -1: the last place that holds its signature and a comment that runs exactly to the end.
func _find_end_record(tail: PackedByteArray) -> int:
	for at in range(tail.size() - _EOCD_SIZE, -1, -1):
		if tail.decode_u32(at) == _EOCD_SIGNATURE and at + _EOCD_SIZE + tail.decode_u16(at + 20) == tail.size():
			return at
	return -1


## The folder of the zip that holds `pack.json`: `""` for the root (preferred), else the first one-folder-deep `<folder>/pack.json`; null when there is none.
func _find_folder(names: PackedStringArray) -> Variant:
	var best: Variant = null
	for name in names:
		if name == Pack.MANIFEST:
			return ""
		if best == null and name.ends_with("/" + Pack.MANIFEST) and name.count("/") == 1:
			best = name.get_base_dir()
	return best


## Puts the file `rel` into the index: its entry, and its name in the folder it is in (the folders above it are made as they are needed).
func _add(rel: String, entry: PackedInt64Array) -> void:
	_entries[rel] = entry
	(_listing_of(rel.get_base_dir())["files"] as Array).append(rel.get_file())


func _listing_of(dir: String) -> Dictionary:
	if not _listing.has(dir):
		_listing[dir] = {"files": [] as Array[String], "folders": [] as Array[String]}
		if not dir.is_empty():
			(_listing_of(dir.get_base_dir())["folders"] as Array).append(dir.get_file())
	return _listing[dir]
