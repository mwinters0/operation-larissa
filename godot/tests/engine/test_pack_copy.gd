class_name TestPackCopy
extends GdUnitTestSuite
## Teaches: why copying a pack is not a plain copy. `PackCopy` (what `pack_tool --new=<id> --from=dev` and the editor's "New pack..." run) gives the copy its own
## paths (`res://packs/<id>/...`) and its own UIDs, so the engine finds no two files with the same UID. These tests make a real copy of the dev pack in the
## project, look at its files, let a Godot of its own import it (`godot --headless --import`, the slow part: some seconds), load sector 0 from the copy, and take
## the copy and its imported cache away again. They need no original game.

const ID := &"zz_copy_test"
const ROOT := "res://packs/zz_copy_test"
const DEV_ROOT := "res://packs/dev"

var _real_chain: Dictionary


func before_test() -> void:
	_real_chain = Packs.snapshot()
	_clean()


func after_test() -> void:
	Packs.restore(_real_chain)
	_clean()


## Takes the copy away, with the imported files the engine made for it in `.godot/imported`.
func _clean() -> void:
	for rel in PackFiles.files_under(ROOT):
		if rel.get_extension() != "import":
			continue
		for found in RegEx.create_from_string("\"(res://\\.godot/imported/[^\"]+)\"").search_all(FileAccess.get_file_as_string("%s/%s" % [ROOT, rel])):
			var cached := found.get_string(1)
			DirAccess.remove_absolute(cached)
			DirAccess.remove_absolute(cached.get_basename() + ".md5")
	PackFiles.remove_tree(ROOT)


## Every uid:// the file `rel` of `root` carries of its own, for all its files.
func _own_uids(root: String) -> Array[String]:
	var found: Array[String] = []
	for rel in PackFiles.files_under(root):
		var uid := PackCopy.own_uid(rel, FileAccess.get_file_as_string("%s/%s" % [root, rel]))
		if not uid.is_empty():
			found.append(uid)
	return found


# --- what is refused ------------------------------------------------------------------------------------------------------

func test_dev_is_reserved_and_other_bad_ids_are_refused() -> void:
	assert_str(PackCopy.make(&"dev").message).contains("reserved")
	assert_bool(PackCopy.make(&"dev").ok).is_false()
	assert_str(PackCopy.make(&"Big Name").message).contains("not a pack id")
	assert_bool(DirAccess.dir_exists_absolute("res://packs/Big Name")).is_false()


func test_a_source_that_is_not_there_is_refused() -> void:
	var result := PackCopy.make(ID, &"nowhere_at_all")
	assert_bool(result.ok).is_false()
	assert_str(result.message).contains("no pack 'nowhere_at_all'")
	assert_bool(DirAccess.dir_exists_absolute(ROOT)).is_false()


# --- the copy -------------------------------------------------------------------------------------------------------------

func test_the_copy_has_new_paths_new_uids_and_a_manifest_of_its_own() -> void:
	var dev_uids := _own_uids(DEV_ROOT)
	assert_int(dev_uids.size()).is_greater(1000)
	var result := PackCopy.make(ID, Packs.DEV, "Copy Test")
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	assert_int(result.files).is_equal(PackFiles.files_under(DEV_ROOT).size())
	assert_array(PackFiles.files_under(ROOT).filter(func(rel: String) -> bool: return rel != "pack.json")).is_equal(PackFiles.files_under(DEV_ROOT).filter(func(rel: String) -> bool: return rel != "pack.json"))
	# the manifest: the new id and title, no base
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/pack.json"))
	assert_str(manifest["id"]).is_equal(String(ID))
	assert_str(manifest["title"]).is_equal("Copy Test")
	assert_bool(manifest.has("base")).is_false()
	# the same number of UIDs, none of them dev's
	var copy_uids := _own_uids(ROOT)
	assert_int(copy_uids.size()).is_equal(dev_uids.size())
	for uid in copy_uids:
		assert_bool(dev_uids.has(uid)).override_failure_message("the copy shares the uid %s with dev" % uid).is_false()
	assert_int(copy_uids.size()).is_equal(PackFiles.files_under(ROOT).filter(func(rel: String) -> bool: return PackCopy.own_uid(rel, FileAccess.get_file_as_string("%s/%s" % [ROOT, rel])) != "").size())
	# no text file of the copy still says dev, no uid it mentions is one of dev's files', and every uid it mentions that is the copy's own is defined in the copy
	var own := {}
	for uid in copy_uids:
		own[uid] = true
	var mention := RegEx.create_from_string("uid://[a-z0-9]+")
	for rel in PackFiles.files_under(ROOT):
		if not PackCopy.TEXT_EXTENSIONS.has(rel.get_extension()):
			continue
		var text := FileAccess.get_file_as_string("%s/%s" % [ROOT, rel])
		assert_bool(text.contains("res://packs/dev/")).override_failure_message("%s still names the dev pack" % rel).is_false()
		for found in mention.search_all(text):
			assert_bool(dev_uids.has(found.get_string())).override_failure_message("%s mentions dev's uid %s" % [rel, found.get_string()]).is_false()
	# an .import file points at the cache name of its new path, not at dev's cached picture
	var dev_import := FileAccess.get_file_as_string(DEV_ROOT + "/assets/authoring_tool/editor_2081.png.import")
	var copy_import := FileAccess.get_file_as_string(ROOT + "/assets/authoring_tool/editor_2081.png.import")
	var dev_cache := RegEx.create_from_string("path=\"(res://\\.godot/imported/[^\"]+)\"").search(dev_import).get_string(1)
	var copy_cache := RegEx.create_from_string("path=\"(res://\\.godot/imported/[^\"]+)\"").search(copy_import).get_string(1)
	assert_str(dev_cache).contains((DEV_ROOT + "/assets/authoring_tool/editor_2081.png").md5_text())     # (the name is the md5 of the source path)
	assert_str(copy_cache).contains((ROOT + "/assets/authoring_tool/editor_2081.png").md5_text())
	assert_str(copy_cache).is_not_equal(dev_cache)


func test_an_id_that_is_taken_is_refused() -> void:
	assert_bool(PackCopy.make(ID, Packs.DEV).ok).is_true()
	var again := PackCopy.make(ID, Packs.DEV)
	assert_bool(again.ok).is_false()
	assert_str(again.message).contains("already a pack")
	assert_bool(PackCopy.make(&"dev").ok).is_false()
	# a refusal leaves the first copy as it was
	assert_bool(FileAccess.file_exists(ROOT + "/pack.json")).is_true()


func test_the_imported_copy_loads_and_its_uids_clash_with_nothing() -> void:
	var result := PackCopy.make(ID, Packs.DEV, "Copy Test")
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	# a Godot of its own imports the project (the new files only: the rest is up to date); this is the slow part
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--import"], output, true)
	var log_text := "\n".join(PackedStringArray(output.map(func(chunk: Variant) -> String: return str(chunk))))
	assert_int(code).override_failure_message(log_text).is_equal(0)
	assert_str(log_text).not_contains("Unrecognized UID")
	# every picture of the copy has an imported copy of its own
	var missing := 0
	for rel in PackFiles.files_under(ROOT):
		if rel.get_extension() == "import":
			for found in RegEx.create_from_string("(?m)^path=\"(res://\\.godot/imported/[^\"]+)\"").search_all(FileAccess.get_file_as_string("%s/%s" % [ROOT, rel])):
				missing += 0 if FileAccess.file_exists(found.get_string(1)) else 1
	assert_int(missing).is_equal(0)
	# the copy is a complete pack: choose it, and sector 0 loads from it, with its pictures
	var copy := Pack.open(ROOT)
	assert_array(copy.errors).is_empty()
	assert_str(String(copy.base)).is_empty()
	assert_bool(Packs.use(copy)).is_true()
	assert_object(Packs.fallback_reason()).is_null()
	assert_array(Packs.chain_ids()).is_equal([ID])
	var sector := Catalog.sector(0)
	assert_object(sector).is_not_null()
	assert_str(sector.resource_path).starts_with(ROOT + "/")
	assert_int(sector.screens.size()).is_greater(0)
	Packs.choose(Packs.DEV)
	assert_int(Catalog.sector(0).screens.size()).is_equal(sector.screens.size())       # the same sector, from dev's own files
	var picture := load(ROOT + "/assets/authoring_tool/editor_2081.png") as Texture2D
	assert_object(picture).is_not_null()
	assert_int(picture.get_width()).is_equal((load(DEV_ROOT + "/assets/authoring_tool/editor_2081.png") as Texture2D).get_width())
	# the engine's own check: a file that shares a uid with another is reported as a duplicate while it scans (a plain copy of dev gives one for every uid)
	assert_str(log_text).not_contains("UID duplicate")


func test_the_tool_makes_the_copy_on_the_command_line_and_refuses_dev() -> void:
	var refused := PackToolDialog.run_tool(PackShelf.pin_args() + PackedStringArray(["--new=dev"]))
	assert_int(refused[0]).is_equal(1)
	assert_str(refused[1]).contains("reserved")
	var made := PackToolDialog.run_tool(PackShelf.pin_args() + PackedStringArray(["--new=%s" % ID, "--from=dev", "--title=Tool Copy"]))
	assert_int(made[0]).override_failure_message(made[1]).is_equal(0)
	assert_str(made[1]).contains("made the pack 'zz_copy_test'")
	assert_str(JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/pack.json"))["title"]).is_equal("Tool Copy")
	var again := PackToolDialog.run_tool(PackShelf.pin_args() + PackedStringArray(["--new=%s" % ID]))
	assert_int(again[0]).is_equal(1)
	assert_str(again[1]).contains("already a pack")
