class_name TestPackArchive
extends GdUnitTestSuite
## Teaches: a pack as ONE file, read where it lies. `PackArchive` reads a `.larissa` zip's central directory itself and builds the one index of what it holds; a hand-made zip (stored entries,
## central directory written byte by byte here) shows what is refused before anything is read: a path that leaves the pack, a size far over the cap, a total over the cap, a ZIP64 or encrypted
## archive. A pack opened from the file answers like the same pack as a folder (`Pack`: `read_text`, `files_in`, `texture`, `stream`, `resource`), the lookups choose between a project folder,
## an installed folder, an installed file and a bundled file in that order and say which they used, and installing a pack file copies it and uninstalling deletes it.

const ID := &"zz_archive_probe"
const TONE := "res://tests/fixtures/pack_tone_short.ogg.bin"

var _scratch: String
var _real_folders: Array[String]
var _real_bundled: Array[StringName]


func before_test() -> void:
	_scratch = "user://test_pack_archive_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_scratch)
	_real_folders = Packs.folders.duplicate()
	_real_bundled = Packs.bundled.duplicate()


func after_test() -> void:
	Packs.folders = _real_folders
	Packs.bundled = _real_bundled
	PackFiles.remove_tree("%s/%s" % [PackInstall.DIR, ID])
	DirAccess.remove_absolute(PackInstall.file_of(ID))
	PackFiles.remove_tree(_scratch)
	PackShelf.with_dev_again()
	Packs.forget_dev()
	Packs.start()


# --- making archives -----------------------------------------------------------------------------------------------------------

static func _put(buffer: PackedByteArray, value: int, width: int) -> void:
	var at := buffer.size()
	buffer.resize(at + width)
	if width == 2:
		buffer.encode_u16(at, value)
	else:
		buffer.encode_u32(at, value)


## A zip made byte by byte: every entry `{name, data (default empty), size (the size the headers declare, default the data's), flags (default 0), method (default 0: stored)}`, with a central directory.
## An entry may also carry `extra`: bytes after its name in the LOCAL header only (the central directory says none). `total` overrides the number of entries the end record says.
func _raw_zip(entries: Array, total := -1) -> PackedByteArray:
	var out := PackedByteArray()
	var central := PackedByteArray()
	for entry: Dictionary in entries:
		var name: PackedByteArray = String(entry["name"]).to_utf8_buffer()
		var data: PackedByteArray = entry.get("data", PackedByteArray())
		var declared: int = entry.get("size", data.size())
		var flags: int = entry.get("flags", 0)
		var method: int = entry.get("method", 0)
		var offset := out.size()
		_put(out, 0x04034b50, 4)
		for value in [20, flags, method, 0, 0]:
			_put(out, value, 2)
		_put(out, 0, 4)                                  # (crc: never read in these zips)
		_put(out, data.size(), 4)
		_put(out, declared, 4)
		_put(out, name.size(), 2)
		var extra: PackedByteArray = entry.get("extra", PackedByteArray())
		_put(out, extra.size(), 2)
		out.append_array(name)
		out.append_array(extra)
		out.append_array(data)
		_put(central, 0x02014b50, 4)
		for value in [20, 20, flags, method, 0, 0]:
			_put(central, value, 2)
		_put(central, 0, 4)
		_put(central, data.size(), 4)
		_put(central, declared, 4)
		_put(central, name.size(), 2)
		for value in [0, 0, 0, 0]:
			_put(central, value, 2)
		_put(central, 0, 4)
		_put(central, offset, 4)
		central.append_array(name)
	var start := out.size()
	out.append_array(central)
	_put(out, 0x06054b50, 4)
	_put(out, 0, 2)
	_put(out, 0, 2)
	_put(out, entries.size() if total < 0 else total, 2)
	_put(out, entries.size() if total < 0 else total, 2)
	_put(out, central.size(), 4)
	_put(out, start, 4)
	_put(out, 0, 2)
	return out


func _write(rel: String, bytes: PackedByteArray) -> String:
	var path := "%s/%s" % [_scratch, rel]
	assert_int(PackFiles.write_bytes(path, bytes)).is_equal(OK)
	return path


func _manifest(id: StringName = ID, version := "1") -> PackedByteArray:
	return JSON.stringify({"id": String(id), "title": "Probe", "version": version, "base": "dev"}).to_utf8_buffer()


## A scratch pack with a little of everything: JSON, text, a picture, a song, a resource in the data form (dev's zones).
func _shelf_with_content(id: StringName = ID) -> PackShelf:
	var shelf := PackShelf.new(id)
	shelf.write_json("texts.json", {"zz_text": "words"})
	shelf.add_picture("pictures/ui_picture/zz_probe.png", Color.ORANGE, Vector2i(8, 4))
	shelf.write_bytes("audio/sound/zz_tone.ogg", FileAccess.get_file_as_bytes(TONE))
	shelf.write_json("data/zones.json", ResourceJson.new().data_of(Packs.dev().resource("data/zones.tres")))
	shelf.write_text("sectors/readme.txt", "hello")
	return shelf


func _archive_of(shelf: PackShelf, name := "") -> String:
	var file := "%s/%s.%s" % [_scratch, name if not name.is_empty() else String(shelf.id), Pack.FILE_EXTENSION]
	assert_int(PackFiles.zip_folder(shelf.root, file, String(shelf.id))).is_equal(OK)
	return file


# --- the index --------------------------------------------------------------------------------------------------------------------

func test_the_index_answers_from_the_central_directory() -> void:
	var shelf := _shelf_with_content()
	var archive := PackArchive.open(_archive_of(shelf))
	assert_array(archive.errors).is_empty()
	assert_str(archive.folder).is_equal(String(ID))
	assert_bool(archive.has("pack.json")).is_true()
	assert_bool(archive.has("data/zones.json")).is_true()
	assert_bool(archive.has("data")).override_failure_message("a folder is not a file").is_false()
	assert_bool(archive.has_folder("data")).is_true()
	assert_bool(archive.has_folder("pictures/ui_picture")).override_failure_message("a folder above a file").is_true()
	assert_bool(archive.has_folder("nowhere")).is_false()
	assert_int(archive.size_of("texts.json")).is_equal(FileAccess.get_file_as_bytes(shelf.root + "/texts.json").size())
	assert_int(archive.size_of("nowhere.json")).is_equal(-1)
	assert_array(archive.files_in("")).is_equal(["pack.json", "texts.json"])
	assert_array(archive.folders_in("")).is_equal(["audio", "data", "pictures", "sectors"])
	assert_array(archive.folders_in("pictures")).is_equal(["ui_picture"])
	assert_array(archive.files_in("pictures/ui_picture")).is_equal(["zz_probe.png"])
	assert_array(archive.all_files()).is_equal(PackFiles.files_under(shelf.root))
	assert_int(archive.read("texts.json").size()).is_equal(archive.size_of("texts.json"))
	assert_array(Array(archive.read("audio/sound/zz_tone.ogg"))).is_equal(Array(FileAccess.get_file_as_bytes(TONE)))
	assert_int(archive.read("nowhere.json").size()).is_equal(0)
	shelf.remove()


func test_a_pack_at_the_root_of_the_zip_is_found_too() -> void:
	var file := _write("root.zip", _raw_zip([{"name": "pack.json", "data": _manifest()}, {"name": "a/b.txt", "data": "x".to_utf8_buffer()}]))
	var archive := PackArchive.open(file)
	assert_array(archive.errors).is_empty()
	assert_str(archive.folder).is_equal("")
	assert_array(archive.all_files()).is_equal(["a/b.txt", "pack.json"])


func test_a_stored_entry_is_read_after_a_local_extra_field_and_a_deflated_one_is_inflated() -> void:
	var text := "".join(Array(range(400)).map(func(i: int) -> String: return "line %d of the probe\n" % i))
	var stored := PackArchive.open(_write("stored.larissa", _raw_zip([{"name": "pack.json", "data": _manifest()}, {"name": "a/b.txt", "data": text.to_utf8_buffer(), "extra": PackedByteArray([1, 2, 3, 4, 5])}])))
	assert_array(stored.errors).is_empty()
	assert_str(stored.read("a/b.txt").get_string_from_utf8()).is_equal(text)
	var shelf := _shelf_with_content()
	shelf.write_text("a/long.txt", text)
	shelf.write_text("a/empty.txt", "")
	var deflated := PackArchive.open(_archive_of(shelf))
	assert_int(deflated.size_of("a/long.txt")).is_equal(text.length())
	assert_str(deflated.read("a/long.txt").get_string_from_utf8()).is_equal(text)
	assert_int(deflated.read("pictures/ui_picture/zz_probe.png").size()).is_equal(deflated.size_of("pictures/ui_picture/zz_probe.png"))
	assert_int(deflated.read("a/empty.txt").size()).is_equal(0)
	shelf.remove()


func test_a_deflated_entry_with_a_damaged_byte_reads_as_nothing() -> void:
	var text := "".join(Array(range(400)).map(func(i: int) -> String: return "line %d of the probe\n" % i))
	var shelf := _shelf_with_content()
	shelf.write_text("a/long.txt", text)
	var file := _archive_of(shelf)
	shelf.remove()
	var archive := PackArchive.open(file)
	var entry: PackedInt64Array = archive._entries["a/long.txt"]
	var bytes := FileAccess.get_file_as_bytes(file)
	var name_length := bytes.decode_u16(entry[4] + 26)
	var at := entry[4] + 30 + name_length + bytes.decode_u16(entry[4] + 28) + entry[2] / 2           # (inside the deflated data)
	bytes[at] ^= 0x55
	var damaged := _write("damaged.larissa", bytes)
	var broken := PackArchive.open(damaged)
	assert_array(broken.errors).is_empty()
	assert_int(broken.read("a/long.txt").size()).is_equal(0)
	assert_str(broken.read("texts.json").get_string_from_utf8()).contains("words")          # (the others are fine)
	assert_str(Pack.open(damaged).read_text("a/long.txt")).is_empty()


func test_an_entry_whose_data_is_not_where_the_directory_says_is_refused() -> void:
	var zip := _raw_zip([{"name": "pack.json", "data": _manifest()}, {"name": "a.txt", "data": "x".to_utf8_buffer()}])
	var central := zip.decode_u32(zip.size() - 22 + 16)
	zip.encode_u32(central + 42, zip.size() + 1000)                              # (the first entry's local header offset)
	assert_str(" ".join(PackArchive.open(_write("far.zip", zip)).errors)).contains("not where the list of files says")


func test_the_reader_is_opened_by_the_first_read_and_let_go_of_by_close() -> void:
	var shelf := _shelf_with_content()
	var archive := PackArchive.open(_archive_of(shelf))
	assert_bool(archive.is_open()).override_failure_message("listing opens nothing").is_false()
	assert_str(archive.read("texts.json").get_string_from_utf8()).contains("words")
	assert_bool(archive.is_open()).is_true()
	archive.close()
	assert_bool(archive.is_open()).is_false()
	assert_bool(archive.has("texts.json")).override_failure_message("the index stays").is_true()
	assert_str(archive.read("texts.json").get_string_from_utf8()).contains("words")
	archive.close()
	shelf.remove()


func test_a_file_of_a_pack_file_that_compresses_already_is_stored() -> void:
	var zeros := PackedByteArray()
	zeros.resize(200000)
	PackFiles.write_bytes(_scratch + "/pack/pack.json", _manifest())
	PackFiles.write_bytes(_scratch + "/pack/x.png", zeros)
	PackFiles.write_bytes(_scratch + "/pack/x.txt", zeros)
	assert_int(PackFiles.zip_folder(_scratch + "/pack", _scratch + "/both.larissa", "pack")).is_equal(OK)
	var packer_made := FileAccess.open(_scratch + "/both.larissa", FileAccess.READ).get_length()
	assert_int(packer_made).override_failure_message("the picture stays 200 kB, the text shrinks to nearly nothing").is_between(200000, 215000)
	assert_int(PackArchive.open(_scratch + "/both.larissa").size_of("x.txt")).is_equal(200000)


# --- what is refused ------------------------------------------------------------------------------------------------------------

func test_a_path_that_leaves_the_pack_is_refused_and_the_archive_holds_no_file() -> void:
	for bad in ["../escaped.txt", "/etc/x", "a/../../x", "c:/x", "a\\b"]:
		var file := _write("hostile.larissa", _raw_zip([{"name": "pack.json", "data": _manifest()}, {"name": bad, "data": "x".to_utf8_buffer()}]))
		var archive := PackArchive.open(file)
		assert_str(" ".join(archive.errors)).override_failure_message(bad).contains("leaves the pack")
		assert_array(archive.all_files()).override_failure_message(bad).is_empty()
		assert_bool(archive.has("pack.json")).is_false()
		var pack := Pack.open(file)
		assert_bool(pack.is_valid()).is_false()
		assert_str(" ".join(pack.errors)).contains("leaves the pack")


func test_a_size_over_the_cap_is_refused_before_anything_is_read() -> void:
	var big := PackArchive.MAX_FILE_BYTES + 1
	var archive := PackArchive.open(_write("big.zip", _raw_zip([{"name": "pack.json", "data": _manifest()}, {"name": "audio/huge.ogg", "size": big, "method": 8}])))
	assert_str(" ".join(archive.errors)).contains("audio/huge.ogg").contains("at most %d MB" % (PackArchive.MAX_FILE_BYTES >> 20))
	assert_array(archive.all_files()).is_empty()
	var claims_two_gigabytes := PackArchive.open(_write("bomb.zip", _raw_zip([{"name": "pack.json", "data": _manifest()}, {"name": "x.bin", "size": 0x7FFFFFFF, "method": 8}])))
	assert_array(claims_two_gigabytes.errors).is_not_empty()
	assert_int(claims_two_gigabytes.read("x.bin").size()).is_equal(0)


func test_a_total_over_the_cap_is_refused() -> void:
	var entries: Array = [{"name": "pack.json", "data": _manifest()}]
	for i in 9:
		entries.append({"name": "f%d.bin" % i, "size": PackArchive.MAX_FILE_BYTES - (1 << 20), "method": 8})        # (each under the cap, together over 512 MB)
	var archive := PackArchive.open(_write("total.zip", _raw_zip(entries)))
	assert_str(" ".join(archive.errors)).contains("unpacks to more than %d MB" % (PackArchive.MAX_TOTAL_BYTES >> 20))


func test_what_is_not_a_pack_or_not_a_plain_zip_is_refused_with_a_reason() -> void:
	assert_str(" ".join(PackArchive.open(_write("bare.zip", _raw_zip([{"name": "readme.txt"}]))).errors)).contains("holds no pack.json")
	assert_str(" ".join(PackArchive.open(_write("text.larissa", "not a zip".to_utf8_buffer())).errors)).contains("not a zip archive")
	assert_str(" ".join(PackArchive.open(_scratch + "/missing.larissa").errors)).contains("cannot open")
	assert_str(" ".join(PackArchive.open(_write("twice.zip", _raw_zip([{"name": "pack.json", "data": _manifest()}, {"name": "pack.json", "data": _manifest()}]))).errors)).contains("twice")
	assert_str(" ".join(PackArchive.open(_write("secret.zip", _raw_zip([{"name": "pack.json", "data": _manifest(), "flags": 1}]))).errors)).contains("encrypted")
	var zip64 := _raw_zip([{"name": "pack.json", "data": _manifest()}], 0xFFFF)
	assert_str(" ".join(PackArchive.open(_write("big64.zip", zip64)).errors)).contains("ZIP64")
	var cut := _raw_zip([{"name": "pack.json", "data": _manifest()}])
	cut.resize(cut.size() - 30)
	assert_array(PackArchive.open(_write("cut.zip", cut)).errors).is_not_empty()
	assert_bool(PackArchive.open(_write("fine.zip", _raw_zip([{"name": "pack.json", "data": _manifest()}]))).is_valid()).is_true()


func test_a_pack_file_with_the_wrong_id_for_its_name_is_not_used() -> void:
	PackFiles.write_text(_scratch + "/build/pack.json", _manifest(&"someone_else").get_string_from_utf8())
	var file := "%s/shelf/%s.%s" % [_scratch, ID, Pack.FILE_EXTENSION]
	assert_int(PackFiles.zip_folder(_scratch + "/build", file, "someone_else")).is_equal(OK)
	Packs.folders = [_scratch + "/shelf"]
	assert_array(Packs.available().filter(func(pack: Pack) -> bool: return pack.id == ID or pack.id == &"someone_else")).is_empty()
	assert_array(Packs.ignored().filter(func(line: String) -> bool: return line.begins_with(file) and line.contains("says 'someone_else', not '%s'" % ID))).has_size(1)


# --- a pack read from the file is the pack read from the folder ---------------------------------------------------------------------

func test_a_pack_file_answers_like_the_same_pack_as_a_folder() -> void:
	var shelf := _shelf_with_content()
	var file := _archive_of(shelf)
	var folder_pack := Pack.open(shelf.root)
	var file_pack := Pack.open(file)
	assert_array(file_pack.errors).is_empty()
	assert_bool(file_pack.is_archive()).is_true()
	assert_bool(folder_pack.is_archive()).is_false()
	assert_bool(file_pack.trusted).is_false()
	assert_str(file_pack.root).is_equal(file)
	assert_str(file_pack.path_of("data/zones.json")).is_equal(file + "/data/zones.json")
	assert_dict(file_pack.manifest()).is_equal(folder_pack.manifest())
	assert_array(file_pack.all_files()).is_equal(folder_pack.all_files())
	for dir in ["", "data", "pictures", "pictures/ui_picture", "audio", "audio/sound", "sectors", "nowhere"]:
		if not dir.is_empty():
			assert_bool(file_pack.has_folder(dir)).override_failure_message(dir).is_equal(folder_pack.has_folder(dir))
		assert_array(file_pack.files_in(dir)).override_failure_message(dir).is_equal(folder_pack.files_in(dir))
		assert_array(file_pack.folders_in(dir)).override_failure_message(dir).is_equal(folder_pack.folders_in(dir))
	assert_array(file_pack.files_in("audio/sound", "ogg")).is_equal(["zz_tone.ogg"])
	for rel in folder_pack.all_files():
		assert_bool(file_pack.has(rel)).override_failure_message(rel).is_true()
		assert_int(file_pack.size_of(rel)).override_failure_message(rel).is_equal(folder_pack.size_of(rel))
		assert_array(Array(file_pack.read_bytes(rel))).override_failure_message(rel).is_equal(Array(folder_pack.read_bytes(rel)))
	assert_bool(file_pack.has("nowhere.json")).is_false()
	assert_int(file_pack.size_of("nowhere.json")).is_equal(-1)
	assert_int(file_pack.size_of("../x")).is_equal(-1)
	assert_str(file_pack.read_text("texts.json")).is_equal(folder_pack.read_text("texts.json"))
	assert_dict(file_pack.read_json("texts.json")).is_equal({"zz_text": "words"})
	var picture := file_pack.texture("pictures/ui_picture/zz_probe.png")
	assert_object(picture).is_not_null()
	assert_vector(picture.get_size()).is_equal(Vector2(8, 4))
	assert_str(Packs.source_of(picture)).is_equal(file + "/pictures/ui_picture/zz_probe.png")
	var tone := file_pack.stream("audio/sound/zz_tone.ogg")
	assert_float(tone.get_length()).is_equal(folder_pack.stream("audio/sound/zz_tone.ogg").get_length())
	var made := file_pack.resource("data/zones.tres")
	var differences: Array[String] = []
	ResourceCompare.same(made, folder_pack.resource("data/zones.tres"), "zones", differences)
	assert_array(differences).is_empty()
	assert_bool(file_pack.provides("data/zones.tres")).is_true()
	assert_bool(file_pack.provides("data/other.tres")).is_false()
	assert_array(file_pack.problems()).is_empty()
	shelf.remove()


func test_a_pack_file_is_a_pack_of_the_chain_and_its_paths_are_found_by_their_prefix() -> void:
	var shelf := _shelf_with_content()
	var file := _archive_of(shelf)
	shelf.remove()                                                         # (only the file is left)
	assert_bool(Packs.use(Pack.open(file))).override_failure_message(str(Packs.fallback_reason())).is_true()
	var pack := Packs.chosen()
	assert_bool(pack.is_archive()).is_true()
	assert_object(Packs.holder("data/zones.tres")).is_same(pack)
	assert_str(Packs.path("texts.json")).is_equal(file + "/texts.json")
	assert_str(Packs.relative(file + "/data/zones.json")).is_equal("data/zones.json")
	assert_object(Packs.pack_of_path(file + "/data/zones.json")).is_same(pack)
	assert_object(Packs.file_at(file + "/pictures/ui_picture/zz_probe.png")).is_instanceof(Texture2D)
	assert_bool(Packs.exists_at(file + "/data/zones.tres")).is_true()
	assert_bool(Packs.exists_at(file + "/data/missing.tres")).is_false()
	assert_str(Packs.text("zz_text")).is_equal("words")
	assert_object(Packs.picture("ui_picture/zz_probe")).is_not_null()
	assert_object(Packs.clip(&"sound", &"zz_tone")).is_not_null()
	assert_bool(pack._archive.is_open()).is_true()
	pack.forget()
	assert_bool(pack._archive.is_open()).override_failure_message("forgetting lets go of the file").is_false()
	Packs.refresh()                                                                                          # (the lists are rebuilt: the clips are measured, which reads the file again)
	assert_object(Packs.texture("pictures/ui_picture/zz_probe.png")).is_not_null()
	assert_object(Packs.clip(&"sound", &"zz_tone")).is_not_null()


# --- where packs are found ----------------------------------------------------------------------------------------------------

func _pack_file_of(dir: String, id: StringName, version: String) -> void:
	var folder := "%s/build_%s_%s" % [_scratch, id, version]
	PackFiles.write_text(folder + "/pack.json", JSON.stringify({"id": String(id), "title": "Probe", "version": version}))
	assert_int(PackFiles.zip_folder(folder, "%s/%s.%s" % [dir, id, Pack.FILE_EXTENSION], String(id))).is_equal(OK)


func _folder_of(dir: String, id: StringName, version: String) -> void:
	PackFiles.write_text("%s/%s/pack.json" % [dir, id], JSON.stringify({"id": String(id), "title": "Probe", "version": version}))


func _used(id: StringName) -> Pack:
	var found := Packs.available().filter(func(pack: Pack) -> bool: return pack.id == id)
	assert_array(found).has_size(1)
	return found[0]


func test_the_first_place_that_has_an_id_wins_and_the_notes_say_which_was_used() -> void:
	var project := _scratch + "/project"
	var user := _scratch + "/user"
	var shipped := _scratch + "/shipped"
	DirAccess.make_dir_recursive_absolute(project)
	DirAccess.make_dir_recursive_absolute(user)
	DirAccess.make_dir_recursive_absolute(shipped)
	Packs.folders = [project, user]
	Packs.bundled = [ID]
	Packs.archive_folders = [shipped]
	_folder_of(project, ID, "project folder")
	_folder_of(user, ID, "user folder")
	_pack_file_of(user, ID, "user file")
	_pack_file_of(shipped, ID, "bundled file")
	var order := [["project folder", project + "/" + ID], ["user folder", user + "/" + ID], ["user file", "%s/%s.larissa" % [user, ID]], ["bundled file", "%s/%s.larissa" % [shipped, ID]]]
	for step in order.size():
		var used := _used(ID)
		assert_str(used.version).is_equal(order[step][0])
		assert_str(used.root).is_equal(order[step][1])
		var notes := Packs.ignored().filter(func(line: String) -> bool: return line.contains("'%s' is %s, so this one is left out" % [ID, order[step][1]]))
		assert_array(notes).override_failure_message("the %d others say which is used" % (order.size() - 1 - step)).has_size(order.size() - 1 - step)
		match step:
			0:
				PackFiles.remove_tree(project + "/" + ID)
			1:
				PackFiles.remove_tree(user + "/" + ID)
			2:
				DirAccess.remove_absolute(order[2][1])
	assert_array(Packs.available().filter(func(pack: Pack) -> bool: return pack.id == ID)).has_size(1)


func test_dev_is_found_in_the_project_then_installed_as_a_folder_then_as_a_file_then_bundled() -> void:
	var project := _scratch + "/project/dev"
	var installed := _scratch + "/installed/dev"
	var shipped := _scratch + "/shipped"
	DirAccess.make_dir_recursive_absolute(shipped)
	PackShelf.without_dev([shipped])
	Packs.dev_root = project
	Packs.installed_dev_root = installed
	_folder_of(_scratch + "/project", Packs.DEV, "project")
	_folder_of(_scratch + "/installed", Packs.DEV, "installed folder")
	_pack_file_of(_scratch + "/installed", Packs.DEV, "installed file")
	_pack_file_of(shipped, Packs.DEV, "bundled")
	var order := [["project", project], ["installed folder", installed], ["installed file", installed + ".larissa"], ["bundled", shipped + "/dev.larissa"]]
	for step in order.size():
		Packs.forget_dev()
		assert_str(Packs.dev().version).is_equal(order[step][0])
		assert_str(Packs.dev().root).is_equal(order[step][1])
		Packs.available()
		assert_array(Packs.ignored().filter(func(line: String) -> bool: return line.contains("dev is %s, so this copy is left out" % order[step][1]))).has_size(order.size() - 1 - step)
		match step:
			0:
				PackFiles.remove_tree(project)
			1:
				PackFiles.remove_tree(installed)
			2:
				DirAccess.remove_absolute(order[2][1])
	assert_array(Packs.available().filter(func(pack: Pack) -> bool: return pack.id == Packs.DEV)).is_empty()


# --- installing ---------------------------------------------------------------------------------------------------------------------

func test_installing_a_pack_file_copies_it_and_uninstalling_removes_it() -> void:
	var shelf := _shelf_with_content()
	var file := _archive_of(shelf)
	shelf.remove()
	var result := PackInstall.install(file)
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	assert_str(result.path).is_equal(PackInstall.file_of(ID))
	assert_array(Array(FileAccess.get_file_as_bytes(result.path))).is_equal(Array(FileAccess.get_file_as_bytes(file)))
	assert_bool(DirAccess.dir_exists_absolute(PackInstall.folder_of(ID))).override_failure_message("nothing is extracted").is_false()
	assert_bool(FileAccess.file_exists(result.path + ".part")).is_false()
	assert_bool(PackInstall.is_installed(ID)).is_true()
	assert_str(_used(ID).root).is_equal(result.path)
	assert_bool(Packs.use(Pack.open(result.path))).is_true()                    # (in use, and read: the reader holds the file)
	assert_str(Packs.chosen().read_text("texts.json")).contains("words")
	assert_str(PackInstall.uninstall(ID)).is_empty()
	assert_bool(FileAccess.file_exists(result.path)).is_false()
	assert_bool(PackInstall.is_installed(ID)).is_false()
	assert_bool(Packs.in_chain(ID)).is_false()
	assert_str(PackInstall.uninstall(ID)).contains("is not installed")


func test_an_id_is_installed_in_one_form_at_a_time() -> void:
	var shelf := _shelf_with_content()
	var file := _archive_of(shelf)
	assert_bool(PackInstall.install(shelf.root).ok).is_true()
	assert_bool(DirAccess.dir_exists_absolute(PackInstall.folder_of(ID))).is_true()
	var result := PackInstall.install(file)
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	assert_bool(DirAccess.dir_exists_absolute(PackInstall.folder_of(ID))).override_failure_message("the file replaces the folder").is_false()
	assert_bool(FileAccess.file_exists(PackInstall.file_of(ID))).is_true()
	assert_bool(PackInstall.install(shelf.root).ok).is_true()
	assert_bool(FileAccess.file_exists(PackInstall.file_of(ID))).override_failure_message("the folder replaces the file").is_false()
	PackFiles.write_text(PackInstall.folder_of(ID) + "/marker.txt", "x")
	PackFiles.copy_file(file, PackInstall.file_of(ID))                                      # (both forms, put there by hand)
	assert_str(PackInstall.uninstall(ID)).is_empty()
	assert_bool(PackInstall.is_installed(ID)).override_failure_message("uninstalling takes away both").is_false()
	shelf.remove()


func test_a_pack_file_that_is_not_safe_or_not_a_pack_is_not_installed() -> void:
	var hostile := _write("hostile.larissa", _raw_zip([{"name": "pack.json", "data": _manifest()}, {"name": "../escaped.txt", "data": "x".to_utf8_buffer()}]))
	var result := PackInstall.install(hostile)
	assert_bool(result.ok).is_false()
	assert_str(result.message).contains("not a pack").contains("leaves the pack")
	assert_bool(FileAccess.file_exists(PackInstall.file_of(ID))).is_false()
	assert_bool(PackInstall.install(_write("junk.larissa", "no".to_utf8_buffer())).ok).is_false()
	PackFiles.write_text(_scratch + "/dev_build/pack.json", JSON.stringify({"id": "dev", "title": "Dev", "version": "1"}))
	assert_int(PackFiles.zip_folder(_scratch + "/dev_build", _scratch + "/dev.larissa", "dev")).is_equal(OK)
	assert_str(PackInstall.install(_scratch + "/dev.larissa").message).contains("the project itself has a pack called 'dev'")
