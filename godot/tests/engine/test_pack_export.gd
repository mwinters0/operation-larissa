class_name TestPackExport
extends GdUnitTestSuite
## Teaches: making a pack out of what a designer built. A campaign becomes a pack laid over another (a folder or one `.larissa` pack file of JSON, `.foe` text and PNGs)
## from the game's own reader, so a campaign that is a `.tres` of the project and one that came from another pack export the same way.

const ID := &"orchard_pack"
const BOX := &"orchard_box"
const EXPORTS := "user://test_pack_exports"
const TONE_SHORT := "res://tests/fixtures/pack_tone_short.ogg.bin"
const TINY := "res://tests/skins/tiny"

var _shelves: Array[PackShelf] = []
var _campaigns: CampaignShelf
var _sectors_dir := ""
var _scratch: Array[String] = []


func before_test() -> void:
	PackFiles.remove_tree(EXPORTS)


func after_test() -> void:
	for shelf in _shelves:
		shelf.remove()
	_shelves.clear()
	Packs.start()
	if _campaigns != null:
		_campaigns.remove()
		_campaigns = null
	Catalog.sectors_dir = Catalog.SECTORS_DIR
	PackExport.source_dir = PackExport.SOURCE_DIR
	for dir in _scratch:
		PackFiles.remove_tree(dir)
	_scratch.clear()
	PackFiles.remove_tree(EXPORTS)
	if not _sectors_dir.is_empty():
		PackFiles.remove_tree(_sectors_dir)
		_sectors_dir = ""
	Catalog.reload_campaigns()


## The scratch pack `BOX` with the campaign `ID` (copies of dev's sectors 0, 1, 180 as 40, 41, 42), a picture and a text, mounted.
func _orchard(mounted := true) -> PackShelf:
	var shelf := PackShelf.new(BOX)
	_shelves.append(shelf)
	shelf.add_sector_copy(0, 40)
	shelf.add_sector_copy(1, 41)
	shelf.add_sector_copy(DevPack.test_sector("e", 0), 42)
	shelf.add_picture("pictures/ui_picture/orchard_finale.png", Color.ORANGE, Vector2i(8, 4))
	shelf.write_json("texts.json", {"orchard_hello": "Welcome to the orchard."})
	shelf.write_json("campaigns/%s.json" % ID, {
		"class": "Campaign", "id": String(ID), "title": "Orchard of Packs", "sectors": [40, 41], "finales": [42],
		"default_edu_levels": [0, 1], "log_unlock_order": [2, 1], "finale_log_counts": [2], "log_texts": ["Apples.", "Pears."], "log_voices": ["", ""],
		"supply_texts": ["Well picked.", "Well picked again."], "supply_voices": ["", ""], "finale_text": "The orchard is yours.", "finale_picture": "orchard_finale",
	})
	if mounted:
		assert_object(shelf.mount()).override_failure_message(str(Packs.fallback_reason())).is_not_null()
	return shelf


func _quick() -> PackExport.Options:
	var options := PackExport.Options.new()
	options.reach = false
	return options


# --- a campaign in the data form ----------------------------------------------------------------------------------------------------

func test_a_campaign_of_a_mounted_pack_exports_as_a_folder_that_is_a_sound_pack() -> void:
	_orchard()
	var result := PackExport.campaign(ID, EXPORTS, _quick())
	assert_bool(result.ok()).override_failure_message(result.text()).is_true()
	assert_str(result.path).is_equal("%s/%s" % [EXPORTS, ID])
	for rel in ["pack.json", "campaigns/orchard_pack.json", "sectors/sector_40/sector_40.json", "sectors/sector_40/sector_40.foe", "sectors/sector_41/sector_41.json",
			"sectors/sector_42/sector_42.foe", "pictures/ui_picture/orchard_finale.png", "texts.json"]:
		assert_bool(result.files.has(rel)).override_failure_message("%s is missing from %s" % [rel, result.files]).is_true()
	var pack := Pack.open(result.path)
	assert_array(pack.errors).is_empty()
	assert_str(pack.id).is_equal(ID)                                                    # (the pack is called after the campaign, not after the pack it came from)
	assert_str(pack.title).is_equal("Orchard of Packs")
	assert_array(pack.problems()).is_empty()
	assert_array(pack.sector_ids()).is_equal([40, 41, 42])
	assert_bool(result.report.passes()).is_true()
	# the sectors and the campaign are the source's, byte for byte
	for rel in ["sectors/sector_40/sector_40.json", "sectors/sector_42/sector_42.foe", "campaigns/orchard_pack.json", "pictures/ui_picture/orchard_finale.png"]:
		assert_array(Array(FileAccess.get_file_as_bytes("%s/%s" % [result.path, rel]))).is_equal(Array(FileAccess.get_file_as_bytes("%s/%s" % [_shelves[0].root, rel])))
	assert_bool(FileAccess.file_exists(result.path + "/pack.json")).is_true()


func test_the_rule_values_of_the_pack_go_with_the_campaign_and_a_bad_one_stops_the_export() -> void:
	var shelf := _orchard()
	shelf.write_json(Tuning.PACK_PATH, {"air": {"max_oxygen": 4}, "ink": {"max": 12}})
	var result := PackExport.campaign(ID, EXPORTS, _quick())
	assert_bool(result.ok()).override_failure_message(result.text()).is_true()
	assert_bool(result.files.has(Tuning.PACK_PATH)).is_true()
	assert_array(Array(FileAccess.get_file_as_bytes("%s/%s" % [result.path, Tuning.PACK_PATH]))).is_equal(Array(FileAccess.get_file_as_bytes("%s/%s" % [shelf.root, Tuning.PACK_PATH])))
	shelf.write_json(Tuning.PACK_PATH, {"air": {"max_oxygen": 0}})
	var refused := PackExport.campaign(ID, EXPORTS, _quick())
	assert_bool(refused.ok()).is_false()
	assert_str(refused.text()).contains("air.max_oxygen is 0")


func test_the_exported_pack_plays_as_the_source_did_once_the_source_is_gone() -> void:
	var shelf := _orchard()
	var before := Catalog.sector(41)
	var result := PackExport.campaign(ID, EXPORTS, _quick())
	assert_bool(result.ok()).override_failure_message(result.text()).is_true()
	shelf.remove()                                                                     # the source is gone ...
	assert_object(Catalog.campaign(ID)).is_null()
	Packs.use(Pack.open(result.path))                                                  # ... the export is used instead (laid over the pack the suite runs on)
	assert_str(Packs.chosen().root).is_equal(result.path)
	assert_str(Packs.chosen().base).is_equal(PackShelf.base_id())
	var campaign := Catalog.campaign(ID)
	assert_str(campaign.pack_id).is_equal(ID)
	assert_array(Array(campaign.sectors)).is_equal([40, 41])
	assert_array(campaign.problems()).is_empty()
	assert_vector(campaign.finale_texture().get_size()).is_equal(Vector2(8, 4))
	assert_str(Catalog.text(&"orchard_hello")).is_equal("Welcome to the orchard.")
	var after := Catalog.sector(41)
	assert_array(Array(after.foe_bytecode)).is_equal(Array(before.foe_bytecode))
	for m in SectorData.SCREEN_COUNT:
		assert_array(Array(after.screens[m].tiles)).is_equal(Array(before.screens[m].tiles))


func test_a_pack_can_be_exported_under_the_id_it_is_mounted_as() -> void:
	_orchard()
	var options := _quick()
	options.pack_id = BOX                                                              # (the source pack's own id: a re-export of an installed pack)
	options.title = "Orchard Again"
	options.author = "Pip"
	options.version = "2.0"
	var result := PackExport.campaign(ID, EXPORTS, options)
	assert_bool(result.ok()).override_failure_message(result.text()).is_true()
	var pack := Pack.open(result.path)
	assert_str(pack.id).is_equal(BOX)
	assert_str(pack.title).is_equal("Orchard Again")
	assert_str(pack.version).is_equal("2.0")
	assert_str(pack.author).is_equal("Pip")
	assert_bool(Packs.in_chain(BOX)).is_true()                                         # and the source is still in use as it was
	assert_str(Packs.pack(BOX).root).is_not_equal(result.path)


func test_a_campaign_with_errors_leaves_nothing_behind() -> void:
	var shelf := _orchard()
	shelf.write_text(SectorJson.foe_rel(41), "this is not a creature script\n")
	Packs.refresh()
	var result := PackExport.campaign(ID, EXPORTS, _quick())
	assert_bool(result.ok()).is_false()
	assert_str(result.path).is_empty()
	assert_bool(result.report.passes()).is_false()
	assert_bool(result.report.errors().any(func(f: PackReport.Finding) -> bool: return f.area == "sector 41")).is_true()
	assert_bool(DirAccess.dir_exists_absolute("%s/%s" % [EXPORTS, ID])).is_false()
	assert_str(result.text()).contains("nothing was exported")


func test_a_campaign_that_does_not_exist_is_refused() -> void:
	assert_str(PackExport.campaign(&"no_such_campaign", EXPORTS).error).contains("no campaign 'no_such_campaign'")
	assert_bool(DirAccess.dir_exists_absolute(EXPORTS)).is_false()


func test_an_id_that_is_not_a_pack_id_is_refused_before_anything_is_written() -> void:
	_orchard()
	var options := _quick()
	for bad in ["../escape", "Upper", "a/b", "with space", ".."]:
		options.pack_id = StringName(bad)
		assert_str(PackExport.campaign(ID, EXPORTS, options).error).contains("is not a pack id")
	assert_str(PackExport.campaign(&"../escape", EXPORTS, _quick()).error).is_not_empty()
	assert_bool(DirAccess.dir_exists_absolute(EXPORTS)).is_false()
	assert_bool(DirAccess.dir_exists_absolute(EXPORTS.get_base_dir() + "/escape")).is_false()


func test_a_folder_that_is_not_a_pack_is_never_overwritten() -> void:
	_orchard()
	DirAccess.make_dir_recursive_absolute("%s/%s" % [EXPORTS, ID])
	FileAccess.open("%s/%s/precious.txt" % [EXPORTS, ID], FileAccess.WRITE).store_string("mine")
	var result := PackExport.campaign(ID, EXPORTS, _quick())
	assert_str(result.error).contains("is not a pack")
	assert_bool(FileAccess.file_exists("%s/%s/precious.txt" % [EXPORTS, ID])).is_true()


func test_exporting_again_replaces_the_earlier_export() -> void:
	_orchard()
	var first := PackExport.campaign(ID, EXPORTS, _quick())
	FileAccess.open(first.path + "/stale.txt", FileAccess.WRITE).store_string("left over")
	var second := PackExport.campaign(ID, EXPORTS, _quick())
	assert_bool(second.ok()).is_true()
	assert_bool(FileAccess.file_exists(second.path + "/stale.txt")).is_false()


func test_a_pack_file_holds_the_same_pack_and_installs_like_a_folder() -> void:
	_orchard()
	var options := _quick()
	options.archive = true
	var result := PackExport.campaign(ID, EXPORTS, options)
	assert_bool(result.ok()).override_failure_message(result.text()).is_true()
	assert_str(result.path).is_equal("%s/%s.larissa" % [EXPORTS, ID])
	assert_bool(DirAccess.dir_exists_absolute("%s/%s" % [EXPORTS, ID])).is_false()      # (only the pack file is left)
	assert_str(PackArchive.open(result.path).folder).is_equal(String(ID))
	var in_place := Pack.open(result.path)                                              # (the pack file itself, read where it lies)
	assert_array(in_place.errors).is_empty()
	assert_array(in_place.sector_ids()).is_equal([40, 41, 42])
	assert_array(in_place.all_files()).is_equal(result.files)


# --- a campaign of the project ----------------------------------------------------------------------------------------------------

func test_a_campaign_of_the_project_exports_with_its_pictures_and_its_source_folder() -> void:
	_sectors_dir = "user://test_pack_export_sectors_%d" % Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(_sectors_dir)
	for pair in [[0, 40], [1, 41], [DevPack.test_sector("e", 0), 42]]:
		var made := SectorFactory.new_from_copy(pair[0], pair[1], _sectors_dir, DevPack.SECTORS_DIR)
		assert_bool(made.ok()).override_failure_message(made.error).is_true()
	Catalog.sectors_dir = _sectors_dir
	var campaign := Campaign.new()
	campaign.id = &"seaside"
	campaign.title = "Seaside"
	campaign.sectors = PackedInt32Array([40, 41])
	campaign.finales = PackedInt32Array([42])
	campaign.default_edu_levels = PackedInt32Array([0])
	campaign.log_unlock_order = PackedInt32Array([1, 2])
	campaign.finale_log_counts = PackedInt32Array([2])
	campaign.log_texts = [&"Sand.", &"Shells."]
	campaign.log_voices = [&"", &""]
	campaign.supply_texts = [&"One.", &"Two."]
	campaign.supply_voices = [&"", &""]
	campaign.finale_text = "The tide comes in."
	campaign.finale_picture = TINY + "/marker.png"                                       # a file of the project, not a name
	campaign.banner_index = -1
	campaign.banner = load(TINY + "/marker.png")
	_campaigns = CampaignShelf.new([campaign])
	var source := "user://test_pack_export_source_%d" % Time.get_ticks_msec()
	_scratch.append(source)
	DirAccess.make_dir_recursive_absolute(source + "/seaside/audio/voice")
	DirAccess.make_dir_recursive_absolute(source + "/seaside/pictures/ui_picture")
	FileAccess.open(source + "/seaside/texts.json", FileAccess.WRITE).store_string(JSON.stringify({"seaside_hello": "Ahoy."}))
	FileAccess.open(source + "/seaside/audio/voice/shanty.ogg", FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(TONE_SHORT))
	FileAccess.open(source + "/seaside/pictures/ui_picture/shells.png.import", FileAccess.WRITE).store_string("[remap]")      # (the editor's bookkeeping stays behind)
	PackExport.source_dir = source
	var result := PackExport.campaign(&"seaside", EXPORTS, _quick())
	assert_bool(result.ok()).override_failure_message(result.text()).is_true()
	assert_bool(result.files.has("pictures/ui_picture/marker.png")).is_true()           # (the finale picture and the banner are the same file: one copy)
	assert_bool(result.files.has("texts.json")).is_true()
	assert_bool(result.files.has("audio/voice/shanty.ogg")).is_true()
	assert_bool(result.files.any(func(f: String) -> bool: return f.ends_with(".import"))).is_false()
	var written: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(result.path + "/campaigns/seaside.json"))
	assert_str(written["finale_picture"]).is_equal("marker")
	assert_str(written["banner"]).is_equal("pictures/ui_picture/marker.png")
	# and as a pack it stands alone: the project's campaign and sectors are put away and the pack is mounted in their place
	Catalog.sectors_dir = Catalog.SECTORS_DIR
	_campaigns.remove()
	_campaigns = null
	assert_object(Catalog.campaign(&"seaside")).is_null()
	Packs.use(Pack.open(result.path))
	assert_str(Packs.chosen().root).is_equal(result.path)
	var back := Catalog.campaign(&"seaside")
	assert_array(back.problems()).is_empty()
	assert_vector(back.banner.get_size()).is_equal(Vector2(TINY_SIZE, TINY_SIZE))
	assert_vector(back.finale_texture().get_size()).is_equal(Vector2(TINY_SIZE, TINY_SIZE))
	assert_str(Catalog.text(&"seaside_hello")).is_equal("Ahoy.")
	assert_int(Packs.clip(&"voice", &"shanty").ticks).is_greater(0)


const TINY_SIZE := 16


func test_a_campaign_over_sectors_that_another_campaign_has_is_exported_but_fails_the_check() -> void:
	var campaign := CampaignShelf.orchard()                                              # sectors 0, 1 and the finale of the campaign the chain starts with, in the pack under it
	_campaigns = CampaignShelf.new([campaign])
	var result := PackExport.campaign(&"orchard", EXPORTS, _quick())
	assert_str(result.error).is_empty()                                                  # (no sector is the game's own: nothing protects them, the campaign rule does)
	assert_bool(result.ok()).is_false()
	assert_bool(result.report.errors().any(func(f: PackReport.Finding) -> bool: return f.message.contains("also in the campaign '%s'" % Catalog.default_campaign().id))).override_failure_message(result.text()).is_true()
	assert_bool(DirAccess.dir_exists_absolute(EXPORTS + "/orchard")).is_false()
