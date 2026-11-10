class_name TestPackExportLegacy
extends GdUnitTestSuite
## Teaches: nothing of the original is lost on its way out of the project. `PackExport.complete` writes the legacy pack (`.tres` and imported files of the
## project, as the importer left them) in the data form to a scratch folder; every kind it holds is then read back through the door of a pack that is not
## trusted and compared field by field with the authoring file (`ResourceCompare`): zones, the trigger table, sprite meta and sprite frames, the tile set, the
## timelines, layouts, text tables, audio catalogs, voice index and cues, bubble rules, the 34 problem types, the 32 sectors with their twelve screens and
## their creature scripts (the bytes the importer keeps are the bytes the game builds), the two campaigns. Every other file (picture, sound, MIDI, index) is
## the same bytes. `tools/run_tests.sh legacy` with `NEPTUNE_LEGACY_AS_DATA=1` plays this export (docs/engine/DEVELOPING.md); this file proves that it is the same game.

## The classes every pack of the original holds (each must have been met by the round trip).
const KINDS := ["ZoneTable", "TriggerTable", "SpriteMetaTable", "CutsceneTimeline", "HudLayout", "CalculatorLayout", "StoryLayout", "ProblemScreenLayout",
		"TextTable", "SfxCatalog", "MusicCatalog", "VoiceIndex", "VoiceCues", "BubbleRules", "ProblemType", "SpriteFrames", "TileSet"]

var _dir := ""
var _result: PackExport.Result


func before() -> void:
	if not LegacyPack.present():
		return
	_dir = "user://test_legacy_export_%d" % Time.get_ticks_usec()
	var options := PackExport.Options.new()
	options.pack_id = &"legacy_as_data"
	options.reach = false
	_result = PackExport.complete(LegacyPack.ID, _dir, options)


func after() -> void:
	ResourceCompare.pack_roots = []
	if _result != null:
		PackFiles.remove_tree(_dir)
		_result = null


func _legacy() -> Pack:
	return Pack.open(LegacyPack.root())


func _exported() -> Pack:
	return Pack.open(_result.path)


func test_the_export_passes_the_check_and_is_a_complete_pack_in_the_data_form() -> void:
	if not LegacyPack.present():
		return
	assert_bool(_result.ok()).override_failure_message(_result.text().left(3000)).is_true()
	var pack := _exported()
	assert_array(pack.errors).is_empty()
	assert_str(pack.base).is_equal(&"")
	assert_bool(pack.trusted).is_false()
	assert_str(pack.title).is_equal(_legacy().title)
	assert_array(pack.problems()).is_empty()
	assert_array(pack.sector_ids()).has_size(32)
	assert_array(pack.campaign_ids()).is_equal([&"expert", &"voyager"])


func test_every_resource_of_the_data_folder_round_trips() -> void:
	if not LegacyPack.present():
		return
	var legacy := _legacy()
	var exported := _exported()
	ResourceCompare.pack_roots = [legacy.root, exported.root]
	var seen := {}
	var count := 0
	for rel in legacy.all_files():
		if not rel.begins_with("data/") or rel.get_extension() != "tres" or rel.begins_with("data/sectors/") or rel.begins_with("data/campaigns/"):
			continue
		var original := legacy.resource(rel)
		var back := exported.resource(rel)
		assert_object(original).override_failure_message(rel).is_not_null()
		assert_object(back).override_failure_message("%s is not in the export" % rel).is_not_null()
		var differences: Array[String] = []
		ResourceCompare.same(original, back, rel, differences)
		assert_array(differences).override_failure_message("%s\n%s" % [rel, "\n".join(differences.slice(0, 8))]).is_empty()
		seen[EngineJson.class_of(original) if EngineJson.class_of(original) != "" else original.get_script().get_global_name()] = true
		count += 1
	assert_int(count).is_equal(80)
	for kind in KINDS:
		assert_bool(seen.has(kind)).override_failure_message("legacy holds no %s to round trip" % kind).is_true()


func test_every_sector_round_trips_with_its_screens_and_its_creature_script() -> void:
	if not LegacyPack.present():
		return
	var legacy := _legacy()
	var exported := _exported()
	ResourceCompare.pack_roots = [legacy.root, exported.root]
	for number in 32:
		var original := legacy.resource("data/sectors/sector_%02d/sector_%02d.tres" % [number, number]) as SectorData
		var back := SectorJson.read(exported, number)
		assert_object(back).override_failure_message("sector %d is not in the export" % number).is_not_null()
		var differences: Array[String] = []
		ResourceCompare.same(original, back, "sector %d" % number, differences)
		assert_array(differences).override_failure_message("\n".join(differences.slice(0, 8))).is_empty()
		assert_array(Array(back.encode())).override_failure_message("sector %d bytes" % number).is_equal(Array(original.encode()))
		assert_int(back.screens.size()).is_equal(SectorData.SCREEN_COUNT)
		for m in SectorData.SCREEN_COUNT:
			assert_array(Array(back.screens[m].encode())).override_failure_message("sector %d screen %d bytes" % [number, m]).is_equal(Array(original.screens[m].encode()))
		assert_str(exported.read_text(SectorJson.foe_rel(number))).override_failure_message("sector %d script" % number).is_equal(legacy.read_text("data/sectors/sector_%02d/sector_%02d.foe" % [number, number]))
		assert_str(back.foe_script.source).is_equal(original.foe_script.source)


func test_both_campaigns_round_trip() -> void:
	if not LegacyPack.present():
		return
	var legacy := _legacy()
	var exported := _exported()
	ResourceCompare.pack_roots = [legacy.root, exported.root]
	for id in ["voyager", "expert"]:
		var original := legacy.resource("data/campaigns/%s.tres" % id) as Campaign
		var reader := ResourceJson.new(exported)
		var back := reader.read("campaigns/%s.json" % id, Campaign) as Campaign
		assert_array(reader.problems).is_empty()
		var differences: Array[String] = []
		ResourceCompare.same(original, back, id, differences)
		assert_array(differences).override_failure_message("\n".join(differences.slice(0, 8))).is_empty()


func test_every_other_file_is_the_same_bytes_and_nothing_else_is_there() -> void:
	if not LegacyPack.present():
		return
	var legacy := _legacy()
	var exported := _exported()
	var expected: Array[String] = ["pack.json"]
	for rel in legacy.all_files():
		var extension := rel.get_extension()
		if rel == Pack.MANIFEST or extension == "import" or extension == "uid" or rel.begins_with("data/sectors/") and extension != "tres":
			continue
		if extension == "tres":
			if rel.begins_with("data/sectors/"):
				if rel.get_file().begins_with("sector_"):
					expected.append("sectors/sector_%s/%s.json" % [rel.get_file().get_basename().trim_prefix("sector_"), rel.get_file().get_basename()])
					expected.append("sectors/sector_%s/%s.foe" % [rel.get_file().get_basename().trim_prefix("sector_"), rel.get_file().get_basename()])
			elif rel.begins_with("data/campaigns/"):
				expected.append("campaigns/%s.json" % rel.get_file().get_basename())
			else:
				expected.append(Pack.data_rel(rel))
			continue
		expected.append(rel)
		assert_str(FileAccess.get_md5(exported.path_of(rel))).override_failure_message("%s differs" % rel).is_equal(FileAccess.get_md5(legacy.path_of(rel)))
	expected.sort()
	assert_array(exported.all_files()).is_equal(expected)
