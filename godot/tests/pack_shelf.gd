class_name PackShelf
extends RefCounted
## A scratch pack (outside the project, so read in the data form) for a test: a folder in `user://` with a `pack.json` and whatever the test writes into it, used with `Packs.use` as the chosen pack
## (over the pack its `base` names: by default the complete pack at the bottom of the chain in use). `remove` chooses again and deletes the folder, so the next
## test starts with the game as it ships. Each shelf has a folder of its own (the campaigns and sectors a pack holds are cached by what they are called).
##
## Teaches: a test double for a mod folder, as `CampaignShelf` is for the campaigns: the honest way to test a lookup that reads the disk is a
## real folder, written and removed.

static var _count: int = 0
static var _dev_saved: Dictionary = {}

var id: StringName
var root: String
var pack: Pack


func _init(pack_id: StringName = &"", base: StringName = &"") -> void:
	_count += 1
	id = pack_id if pack_id != &"" else StringName("scratch_%d" % _count)
	root = "user://test_packs_%d_%d/%s" % [Time.get_ticks_msec(), _count, id]
	DirAccess.make_dir_recursive_absolute(root)
	Packs.folders.append(root.get_base_dir())                  # (so that a pack laid over this one finds it: `Packs.available` looks here too)
	var manifest := {"id": String(id), "title": "Scratch %s" % id, "version": "1.0"}
	manifest["base"] = String(base if base != &"" else Packs.chain().back().id)
	write_json("pack.json", manifest)


## Writes `data` (a Variant) as JSON to `rel` under the pack.
func write_json(rel: String, data: Variant) -> void:
	ResourceJson.save_json(data, "%s/%s" % [root, rel])


## The JSON file `rel` of the pack, parsed (a Dictionary, or null).
func pack_json(rel: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [root, rel]))


func write_text(rel: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute("%s/%s" % [root, rel.get_base_dir()])
	var file := FileAccess.open("%s/%s" % [root, rel], FileAccess.WRITE)
	file.store_string(text)


func write_bytes(rel: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute("%s/%s" % [root, rel.get_base_dir()])
	var file := FileAccess.open("%s/%s" % [root, rel], FileAccess.WRITE)
	file.store_buffer(bytes)


## A campaign, as the JSON form of its fields.
func add_campaign(campaign: Campaign) -> void:
	write_json("campaigns/%s.json" % campaign.id, ResourceJson.new().data_of(campaign))


## A sector: `sector` as it is (its index decides the folder), with its script.
func add_sector(sector: SectorData) -> void:
	SectorJson.save(sector, root)


## A copy of sector `source` (original or not) as sector `index` of the pack: its script re-written for the new number, as the sector editor
## does (`SectorFactory.copied_script_text`). The source is not changed.
func add_sector_copy(source: int, index: int) -> SectorData:
	var from := Catalog.sector(source)
	var copy := from.duplicate(true) as SectorData
	copy.index = index
	var script := FoeScript.new()
	script.source = SectorFactory.copied_script_text(from.foe_script.source, from, source, index)
	copy.foe_script = script
	add_sector(copy)
	return copy


## A PNG of one colour and size, at `rel`.
func add_picture(rel: String, color: Color, size: Vector2i = Vector2i(4, 4)) -> void:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	write_bytes(rel, image.save_png_to_buffer())


## Makes the pack a mod pack from a fixture folder of the project (`tests/mods/<name>/`): its `pack.json`'s `mod` entry goes into the pack's manifest and every other file is copied in
## (the `.sgd` script, a skin's `skin/` folder). `mod` overrides the entry's keys (a test of a bad manifest says `{"entry": "../x.sgd"}`).
func add_mod_fixture(fixture_dir: String, mod: Dictionary = {}) -> void:
	var manifest: Dictionary = pack_json("pack.json")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/pack.json" % fixture_dir))
	var entry: Dictionary = (fixture["mod"] as Dictionary).duplicate()
	entry.merge(mod, true)
	manifest["mod"] = entry
	write_json("pack.json", manifest)
	_copy_fixture(fixture_dir, "")


## Copies the files of the fixture folder `from` (and its folders) to `rel` of the pack, but the manifest and the editor's `.uid` files.
func _copy_fixture(from: String, rel: String) -> void:
	for file in DirAccess.get_files_at(from):
		if (rel.is_empty() and file == "pack.json") or file.get_extension() == "uid":
			continue
		write_bytes(rel + file, FileAccess.get_file_as_bytes("%s/%s" % [from, file]))
	for folder in DirAccess.get_directories_at(from):
		_copy_fixture("%s/%s" % [from, folder], "%s%s/" % [rel, folder])


## Uses the pack as the chosen pack. The pack as the chain holds it, or null when the chain could not be made with it as its first link.
func mount() -> Pack:
	Packs.use(Pack.open(root))
	pack = Packs.pack(id)
	if pack != null and Packs.chosen() != pack:
		pack = null
	return pack


## A complete pack that holds only its manifest: the folder `user://test_empty_packs/<id>/`. Choosing it finds everything missing. Returns the folder it is in, to put in
## `Packs.folders`.
static func empty_complete_pack_dir(pack_id: StringName) -> String:
	const DIR := "user://test_empty_packs"
	PackFiles.write_text("%s/%s/pack.json" % [DIR, pack_id], JSON.stringify({"id": String(pack_id), "title": "Empty %s" % pack_id, "version": "1"}))
	return DIR


## Makes the dev pack absent for a test: `Packs.dev_root` and `Packs.installed_dev_root` point at folders that do not exist, and the bundled pack files are looked for only in
## `shipped_dirs` (none by default). The folders and the chain are left as they are; `with_dev_again` puts everything back, and every test that calls this must call that in `after_test`.
static func without_dev(shipped_dirs: Array[String] = []) -> void:
	if _dev_saved.is_empty():
		_dev_saved = {"root": Packs.dev_root, "installed": Packs.installed_dev_root, "archives": Packs.archive_folders.duplicate()}
	Packs.dev_root = "%s/zz_no_dev_here" % Packs.PROJECT_PACKS_DIR
	Packs.installed_dev_root = "%s/zz_no_dev_here" % Packs.USER_PACKS_DIR
	Packs.archive_folders = shipped_dirs.duplicate()
	Packs.forget_dev()


## Puts dev back where `without_dev` took it from, and chooses again (`Packs.start`).
static func with_dev_again() -> void:
	if _dev_saved.is_empty():
		return
	Packs.dev_root = _dev_saved["root"]
	Packs.installed_dev_root = _dev_saved["installed"]
	Packs.archive_folders.assign(_dev_saved["archives"])
	_dev_saved = {}
	Packs.forget_dev()
	Packs.start()


## The command line's `--pack=<id>` as arguments, for a second Godot that a test starts (`pack_tool`, the export's probe): it does not inherit the pin
## `run_tests.sh` puts after `--`, so the test hands it on. Empty when the suite runs without a pin.
static func pin_args() -> PackedStringArray:
	var out := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(Packs.PACK_OPTION):
			out.append(arg)
	return out


## The id of the pack the suite runs on, the base of a scratch pack that names none: what `--pack=` says (`run_tests.sh` pins `dev` for the engine group
## and `legacy` for the legacy one), else the first pack found, as `Packs.start` chooses. Tests compare chains with `[x, PackShelf.base_id()]`.
static func base_id() -> StringName:
	for arg in pin_args():
		return StringName(arg.trim_prefix(Packs.PACK_OPTION))
	for each in Packs.available():
		if each.is_valid():
			return each.id
	return Packs.DEV


## Makes the command-line choice again (`Packs.start`: the pinned pack, the game as it ships) and deletes the pack's folder.
func remove() -> void:
	_delete(root.get_base_dir())
	Packs.folders.erase(root.get_base_dir())
	Packs.start()


static func _delete(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute("%s/%s" % [dir, file])
	for folder in DirAccess.get_directories_at(dir):
		_delete("%s/%s" % [dir, folder])
	DirAccess.remove_absolute(dir)
