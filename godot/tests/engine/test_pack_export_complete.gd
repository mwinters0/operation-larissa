class_name TestPackExportComplete
extends GdUnitTestSuite
## Teaches: a COMPLETE pack leaves the project in the data form. `PackExport.complete` writes the dev pack (a folder of the project, `.tres` and imported
## files) as JSON, `.foe` text, PNG, WAV, OGG and MIDI in a folder of `user://`; `PackCheck` accepts it (every data file parses to the class its place calls
## for, the closure of `PackNeeds` holds on it alone) and refuses a `.tres`, a scene or a script put into it; choosing it, the game's own lookups answer
## from its files. The round trip of every kind field by field is `test_data_form` (dev) and `test_pack_export_legacy` (legacy).

const ID := &"dev_exported"

var _dir := ""
var _result: PackExport.Result
var _root := ""


func before() -> void:
	_dir = "user://test_complete_export_%d" % Time.get_ticks_usec()
	var options := PackExport.Options.new()
	options.pack_id = ID
	options.reach = false
	_result = PackExport.complete(Packs.DEV, _dir, options)
	_root = _result.path


func after() -> void:
	PackFiles.remove_tree(_dir)


func after_test() -> void:
	Packs.start()


func _check(pack: Pack) -> PackReport:
	var options := PackCheck.Options.new()
	options.reach = false
	return PackCheck.run(pack, options)


func test_dev_is_exported_and_checked() -> void:
	assert_bool(_result.ok()).override_failure_message(_result.text()).is_true()
	assert_str(_root).is_equal("%s/%s" % [_dir, ID])
	assert_array(_result.report.findings.filter(func(f: PackReport.Finding) -> bool: return f.severity == PackReport.Severity.ERROR)).is_empty()
	assert_array(_result.files).contains(["pack.json", "data/zones.json", "data/sprite_frames/sub_frames.json", "data/neptune_tileset.json", "campaigns/dev_tour.json",
			"sectors/sector_00/sector_00.json", "sectors/sector_00/sector_00.foe", "rules/durations.json", "rules/tuning.json"])


func test_it_holds_nothing_the_engine_runs_and_no_editor_file() -> void:
	for rel in _result.files:
		assert_bool(["tres", "res", "tscn", "scn", "gd", "import", "uid", "dll", "so"].has(rel.get_extension())).override_failure_message(rel).is_false()
	assert_array(_result.files.filter(func(rel: String) -> bool: return rel.begins_with("assets/") and rel.get_extension() == "png")).is_not_empty()
	assert_array(_result.files.filter(func(rel: String) -> bool: return rel.begins_with("midi/"))).is_not_empty()
	assert_array(_result.files.filter(func(rel: String) -> bool: return rel.get_extension() == "wav")).is_not_empty()


func test_the_manifest_names_no_base_so_it_is_complete_and_is_in_the_data_form() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_root + "/pack.json"))
	assert_str(manifest["id"]).is_equal(String(ID))
	assert_bool(manifest.has("tier") or manifest.has("complete") or manifest.has("base")).is_false()
	var pack := Pack.open(_root)
	assert_array(pack.errors).is_empty()
	assert_str(pack.base).is_equal(&"")
	assert_bool(pack.trusted).is_false()
	assert_array(pack.problems()).is_empty()                                   # (no resource, no code)


func test_choosing_it_the_game_answers_from_its_files() -> void:
	assert_bool(Packs.use(Pack.open(_root))).override_failure_message(str(Packs.fallback_reason())).is_true()
	assert_array(Packs.chain_ids()).is_equal([ID])                              # (laid over nothing: dev does not stand under it)
	assert_object(Packs.fallback_reason()).is_null()
	assert_bool(PackNeeds.is_complete(Packs.chain())).override_failure_message(PackNeeds.summary(PackNeeds.gaps(Packs.chain()))).is_true()
	var from_dev := Packs.dev().resource("data/zones.tres") as ZoneTable
	assert_str(Catalog.zone(0).title).is_equal(from_dev.zones[0].title)
	assert_str(Packs.source_of(Catalog.zones())).is_equal(_root + "/data/zones.tres")
	var title := Assets.ui_picture(&"title_sky")
	assert_str(Packs.source_of(title)).starts_with(_root + "/assets/ui/")
	assert_int(Packs.sector_ids().size()).is_equal(Packs.dev().folders_in("data/sectors").size())
	assert_object(Packs.sector_owner(1)).is_same(Packs.pack(ID))
	assert_array(Array(Catalog.sector(1).encode())).is_equal(Array(DevPack.sector(1).encode()))
	assert_array(Catalog.campaigns().map(func(c: Campaign) -> StringName: return c.id)).contains([&"dev_tour"])


func test_the_check_accepts_the_pack_and_refuses_a_resource_or_code_put_into_it() -> void:
	assert_bool(_check(Pack.open(_root)).passes()).is_true()
	var extras := {"data/extra.tres": "[gd_resource type=\"Resource\" format=3]\n", "scenes/main.tscn": "[gd_scene format=3]\n", "scripts/run.gd": "extends Node\n"}
	for rel: String in extras:
		PackFiles.write_text("%s/%s" % [_root, rel], extras[rel])
		var pack := Pack.open(_root)
		assert_str("\n".join(pack.problems())).override_failure_message(rel).contains(rel)
		assert_bool(_check(pack).passes()).override_failure_message(rel).is_false()
		DirAccess.remove_absolute("%s/%s" % [_root, rel])
	assert_bool(_check(Pack.open(_root)).passes()).is_true()


func test_the_check_reads_each_data_file_as_the_class_its_place_calls_for() -> void:
	var path := _root + "/data/zones.json"
	var original := FileAccess.get_file_as_string(path)
	var wrong_class := JSON.parse_string(original) as Dictionary
	wrong_class["class"] = "TriggerTable"
	ResourceJson.save_json(wrong_class, path)
	assert_str(_check(Pack.open(_root)).text()).contains("data/zones.json is a ZoneTable, but says it is TriggerTable")
	var stranger := JSON.parse_string(original) as Dictionary
	stranger["class"] = "Node"
	ResourceJson.save_json(stranger, path)
	assert_str(_check(Pack.open(_root)).text()).contains("is a ZoneTable, but says it is Node")
	var typo := JSON.parse_string(original) as Dictionary
	typo["zonez"] = []
	ResourceJson.save_json(typo, path)
	assert_str(_check(Pack.open(_root)).text()).contains("data/zones.json: ZoneTable has no field 'zonez'")
	FileAccess.open(path, FileAccess.WRITE).store_string("{ not json")
	assert_str(_check(Pack.open(_root)).text()).contains("data/zones.json line")
	FileAccess.open(path, FileAccess.WRITE).store_string(original)
	assert_bool(_check(Pack.open(_root)).passes()).is_true()


func test_a_file_the_closure_needs_is_missing_is_an_error() -> void:
	var path := _root + "/data/ui/hud_layout.json"
	var original := FileAccess.get_file_as_bytes(path)
	DirAccess.remove_absolute(path)
	var report := _check(Pack.open(_root))
	assert_bool(report.passes()).is_false()
	assert_str(report.text()).contains("data/ui/hud_layout.tres")
	PackFiles.write_bytes(path, original)
	assert_bool(_check(Pack.open(_root)).passes()).is_true()


func test_every_kind_dev_holds_has_a_class_the_check_knows() -> void:
	var dev := Packs.dev()
	for rel in dev.all_files():
		if not rel.begins_with("data/") or rel.get_extension() != "tres" or rel.begins_with("data/sectors/") or rel.begins_with("data/campaigns/"):
			continue
		var resource := dev.resource(rel)
		var actual := EngineJson.class_of(resource)
		if actual.is_empty():
			actual = resource.get_script().get_global_name()
		assert_str(PackNeeds.class_of(rel)).override_failure_message(rel).is_equal(actual)


func test_a_pack_file_is_one_file_with_the_pack_in_it() -> void:
	var options := PackExport.Options.new()
	options.pack_id = &"dev_zipped"
	options.archive = true
	options.reach = false
	var zipped := PackExport.complete(Packs.DEV, _dir, options)
	assert_bool(zipped.ok()).override_failure_message(zipped.text()).is_true()
	assert_str(zipped.path).is_equal(_dir + "/dev_zipped.larissa")
	assert_bool(DirAccess.dir_exists_absolute(_dir + "/dev_zipped")).is_false()
	assert_str(PackArchive.open(zipped.path).folder).is_equal("dev_zipped")
	var pack := Pack.open(zipped.path)                                         # (read where it lies)
	assert_bool(pack.is_archive()).is_true()
	assert_array(pack.errors).is_empty()
	assert_str(pack.base).is_equal(&"")
	assert_bool(_check(pack).passes()).is_true()


func test_the_manifest_takes_the_options_and_a_new_export_replaces_the_old() -> void:
	var options := PackExport.Options.new()
	options.pack_id = ID
	options.title = "Dev, exported"
	options.version = "2.1"
	options.author = "Pip"
	options.reach = false
	var again := PackExport.complete(Packs.DEV, _dir, options)
	assert_bool(again.ok()).override_failure_message(again.text()).is_true()
	var pack := Pack.open(again.path)
	assert_str(pack.title).is_equal("Dev, exported")
	assert_str(pack.version).is_equal("2.1")
	assert_str(pack.author).is_equal("Pip")
	assert_str(pack.description).is_equal(Packs.dev().description)


func test_what_cannot_be_exported_is_said() -> void:
	var options := PackExport.Options.new()
	options.reach = false
	assert_str(PackExport.complete(&"no_such_pack", _dir, options).error).contains("there is no pack 'no_such_pack'")
	assert_str(PackExport.complete(&"Not A Pack", _dir, options).error).contains("is not a pack id")
	options.base = &"dev"
	assert_str(PackExport.complete(Packs.DEV, _dir, options).error).contains("laid over nothing")
	options.base = &""
	var shelf := PackShelf.new(&"laid_over_dev")                                  # (a pack with a base: not complete)
	var laid := PackExport.complete(shelf.id, _dir, options)
	shelf.remove()
	assert_str(laid.error).contains("is laid over")
	assert_bool(laid.ok()).is_false()
	assert_bool(DirAccess.dir_exists_absolute(_dir + "/laid_over_dev")).is_false()
	var squatter := PackShelf.new(&"squatter")
	DirAccess.remove_absolute(squatter.root + "/pack.json")
	PackFiles.write_text(squatter.root + "/notes.txt", "mine")
	options.pack_id = &"squatter"
	assert_str(PackExport.complete(Packs.DEV, squatter.root.get_base_dir(), options).error).contains("exists and is not a pack")
	squatter.remove()


func test_a_pack_with_no_base_stands_alone_and_one_with_a_base_is_laid_over_it() -> void:
	var shelf := PackShelf.new(&"standing_alone")
	shelf.write_json("pack.json", {"id": "standing_alone", "title": "Alone", "version": "1"})
	var pack := Pack.open(shelf.root)
	assert_array(pack.errors).is_empty()
	assert_object(Packs.resolve(pack, [], false).fallback).is_null()
	assert_array(Packs.resolve(pack, [], false).packs).has_size(1)
	assert_dict(pack.manifest()).is_equal({"format": Pack.FORMAT, "id": "standing_alone", "title": "Alone", "version": "1"})
	shelf.write_json("pack.json", {"id": "standing_alone", "title": "Alone", "version": "1", "base": "dev"})
	assert_str(Pack.open(shelf.root).base).is_equal(&"dev")
	shelf.remove()
