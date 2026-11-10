class_name TestPackFilePlays
extends GdUnitTestSuite
## Teaches: a pack that is ONE file (`<id>.larissa`, read in place, `PackArchive`) is a pack in every way the game asks. The dev pack is exported whole as a pack file into a scratch folder of `user://` (`PackExport.complete`
## with `archive`) and chosen as the pack; then the lookups answer from the file (the catalog's sectors and campaigns, a picture, a sound, the rule values and durations the file lays over the project's, a MIDI
## song), a sector is played with the rules alone and comes out tick for tick as it does under dev, and the tools that read a pack (`PackExport` of a pack laid over it, of the pack itself, `PackCopy` from it) work
## from the file. Nothing is extracted: the virtual path of a file in it (`Pack.path_of`) names the file and no file system could open it. `test_pack_paths_go_through_pack` keeps the source honest.

const ID := &"dev_in_a_file"
const SECTOR := 2
const COPY_ID := &"zz_from_a_file"
const COPY_ROOT := "res://packs/zz_from_a_file"

var _scratch := "user://test_pack_file_plays_%d" % Time.get_ticks_msec()
var _file := ""
var _exported: PackExport.Result
var _dev_trace: Array = []
var _dev_tuning: Tuning
var _dev_fade := 0
var _dev_zones: Array[String] = []
var _dev_sectors: Array[int] = []
var _dev_files: Array[String] = []


func before() -> void:
	var dev := Packs.dev()
	_dev_files = dev.all_files()
	_dev_trace = _played(SECTOR)
	_dev_tuning = Tuning.resolve()
	_dev_fade = Durations.at("fade.ticks")
	_dev_sectors = Catalog.sector_ids()
	var options := PackExport.Options.new()
	options.pack_id = ID
	options.archive = true
	options.reach = false
	_exported = PackExport.complete(Packs.DEV, _scratch, options)
	_file = _exported.path
	Packs.folders.append(_scratch)                               # (so that the pack is found by its id: `PackExport.complete`, `PackCopy`)


func after() -> void:
	Packs.folders.erase(_scratch)
	Packs.start()
	PackFiles.remove_tree(_scratch)
	PackFiles.remove_tree(COPY_ROOT)


func before_test() -> void:
	assert_bool(Packs.use(Pack.open(_file))).override_failure_message("%s\n%s" % [_exported.text(), str(Packs.fallback_reason())]).is_true()


func after_test() -> void:
	Packs.start()


func _played(sector: int) -> Array:
	var run := auto_free(load("res://src/autoload/game_state.gd").new()) as Node
	run.reset()
	var scenario := SectorScenario.new(HeadlessStage.new(run), run)
	scenario.play(sector)
	return scenario.trace.lines


func _from_the_file(resource: Resource) -> bool:
	return Packs.source_of(resource).begins_with(_file + "/")


func test_the_pack_is_one_file_that_is_read_where_it_lies() -> void:
	assert_bool(_exported.ok()).override_failure_message(_exported.text()).is_true()
	assert_str(_file).is_equal("%s/%s.larissa" % [_scratch, ID])
	assert_bool(DirAccess.dir_exists_absolute("%s/%s" % [_scratch, ID])).is_false()
	var pack := Packs.chosen()
	assert_bool(pack.is_archive()).is_true()
	assert_bool(pack.trusted).is_false()
	assert_array(Packs.chain_ids()).is_equal([ID])
	assert_array(pack.all_files()).is_not_empty()
	assert_bool(FileAccess.file_exists(pack.path_of("pack.json"))).override_failure_message("the virtual path is no file").is_false()
	assert_bool(pack.has("pack.json")).is_true()
	assert_array(pack.problems()).is_empty()
	assert_bool(Packs.dev().trusted).is_true()


func test_the_catalog_answers_from_the_file() -> void:
	assert_array(Catalog.sector_ids()).is_equal(_dev_sectors)
	assert_object(Packs.sector_owner(SECTOR)).is_same(Packs.chosen())
	var sector := Catalog.sector(SECTOR)
	assert_array(Array(sector.encode())).is_equal(Array(DevPack.sector(SECTOR).encode()))
	assert_int(sector.screens.size()).is_equal(SectorData.SCREEN_COUNT)
	assert_str(Catalog.campaign(&"dev_tour").pack_id).is_equal(String(ID))
	assert_str(Catalog.zone(1).title).is_equal(Packs.dev().resource("data/zones.tres").zones[1].title)
	assert_array(Catalog.problem_type(3).art_files).is_not_empty()
	assert_str(Catalog.problem_type(3).art_files[0]).starts_with(_file + "/assets/")
	assert_object(Catalog.sub_frames()).is_not_null()
	assert_object(Catalog.tileset()).is_not_null()


func test_pictures_and_sounds_come_from_the_file() -> void:
	var title := Assets.ui_picture(&"title_sky")
	assert_object(title).is_not_null()
	assert_bool(_from_the_file(title)).is_true()
	assert_bool(_from_the_file(Assets.background(0, 0))).is_true()
	assert_bool(_from_the_file(Assets.texture_at(Catalog.problem_type(3).art_files[0]))).is_true()
	var index := Catalog.voice_index()
	var clip := index.stream(index.ids[0])
	assert_object(clip).is_instanceof(AudioStreamWAV)
	assert_bool(_from_the_file(clip)).is_true()
	assert_float(clip.get_length()).is_greater(0.0)
	var catalog := Catalog.music_catalog()
	var song := catalog.stream(catalog.ids[0])
	assert_object(song).is_instanceof(AudioStreamOggVorbis)
	assert_bool(_from_the_file(song)).is_true()
	for rel in ["data/zones.tres", "data/neptune_tileset.tres", "data/sprite_frames/sub_frames.tres"]:
		assert_bool(_from_the_file(Packs.resource(rel))).override_failure_message(rel).is_true()


func test_the_rule_values_and_durations_the_file_lays_over_the_projects_are_read() -> void:
	assert_str(Tuning.files().back()).is_equal(_file + "/rules/tuning.json")
	assert_str(Durations.files().back()).is_equal(_file + "/rules/durations.json")
	var tuning := Tuning.resolve()
	assert_int(tuning.max_oxygen).is_equal(_dev_tuning.max_oxygen)
	assert_int(tuning.max_oxygen).override_failure_message("the file's layer was not read").is_not_equal(Tuning.original().max_oxygen)
	assert_int(tuning.sub.max_speed_x_units).is_equal(_dev_tuning.sub.max_speed_x_units)
	assert_int(tuning.refill_tanks).is_equal(_dev_tuning.refill_tanks)
	assert_int(Durations.at("fade.ticks")).is_equal(_dev_fade)
	assert_int(Durations.at("fade.ticks")).is_not_equal(LayeredJson.read(Durations.BASE_PATH, "test")["fade"]["ticks"])
	var errors: Array[String] = []
	var warnings: Array[String] = []
	Tuning.check(Packs.chosen().read_json(Tuning.PACK_PATH), errors, warnings)
	assert_array(errors).is_empty()


func test_a_midi_song_is_found_and_read_in_the_file() -> void:
	var music := MidiMusic.new()
	var path := music.find_midi(Catalog.music_catalog().midi_file_of(&"sector_song_1"))
	assert_str(path).starts_with(_file + "/midi/")
	assert_float(MidiMusic.song_seconds(Packs.bytes_at(path))).is_greater(1.0)
	assert_str(music.find_midi("esect1.mid")).is_equal(path.get_base_dir() + "/ESECT1.MID")       # (the case of the name is tried three ways)
	assert_str(music.find_midi("NO_SUCH_SONG.MID")).is_equal("")
	music.free()


func test_a_sector_plays_the_same_from_the_file_as_from_the_folder() -> void:
	var trace := _played(SECTOR)
	assert_int(trace.size()).is_greater(300)
	assert_array(trace).is_equal(_dev_trace)


func test_the_size_and_the_time_of_a_file_are_asked_of_the_pack() -> void:
	var pack := Packs.chosen()
	assert_int(pack.size_of("pack.json")).is_equal(pack.read_bytes("pack.json").size())
	assert_int(pack.modified_time("pack.json")).is_equal(FileAccess.get_modified_time(_file))
	assert_int(pack.modified_time("pack.json")).is_greater(0)


func test_a_campaign_laid_over_the_file_exports_with_its_files_read_from_it() -> void:
	var out := _scratch + "/campaign"
	var options := PackExport.Options.new()
	options.pack_id = &"tour_over_a_file"
	options.base = ID
	options.reach = false
	var result := PackExport.campaign(&"dev_tour", out, options)
	assert_bool(result.ok()).override_failure_message(result.text()).is_true()
	assert_bool(Pack.open(result.path).has("campaigns/dev_tour.json")).is_true()
	for number in Catalog.campaign(&"dev_tour").sectors:
		assert_bool(result.files.has(SectorJson.json_rel(number))).override_failure_message("sector %d" % number).is_true()
		assert_bool(result.files.has(SectorJson.foe_rel(number))).override_failure_message("sector %d script" % number).is_true()
		assert_str(Pack.open(result.path).read_text(SectorJson.foe_rel(number))).is_equal(Packs.chosen().read_text(SectorJson.foe_rel(number)))


func test_the_pack_file_is_exported_whole_again() -> void:
	var options := PackExport.Options.new()
	options.pack_id = &"again_from_a_file"
	options.reach = false
	var result := PackExport.complete(ID, _scratch + "/again", options)
	assert_bool(result.ok()).override_failure_message(result.text()).is_true()
	assert_array(result.files).is_equal(Packs.chosen().all_files())
	var again := Pack.open(result.path)
	assert_array(again.errors).is_empty()
	for rel in ["data/zones.json", "rules/tuning.json"]:
		assert_str(again.read_text(rel)).override_failure_message(rel).is_equal(Packs.chosen().read_text(rel))


func test_a_new_pack_is_made_from_the_file() -> void:
	var result := PackCopy.make(COPY_ID, ID, "From a file")
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	var source := Packs.chosen()
	assert_int(result.files).is_equal(source.all_files().size())
	var copy := Pack.open(COPY_ROOT)
	assert_str(copy.title).is_equal("From a file")
	assert_str(copy.base).is_equal("")
	for rel in ["data/zones.json", "rules/tuning.json", SectorJson.json_rel(SECTOR), "assets/ui/title/%s" % source.files_in("assets/ui/title", "png")[0]]:
		assert_array(Array(copy.read_bytes(rel))).override_failure_message(rel).is_equal(Array(source.read_bytes(rel)))
	PackFiles.remove_tree(COPY_ROOT)
	assert_bool(PackCopy.make(COPY_ID, &"nowhere_at_all").ok).is_false()


func test_a_pack_file_cannot_be_the_place_a_sector_is_edited() -> void:
	assert_object(Catalog.data_only_holder(SECTOR)).is_same(Packs.chosen())
	assert_bool(Catalog.own_sector_dirs().any(func(dir: String) -> bool: return dir.begins_with(_file))).is_false()
	assert_bool(Catalog.sector_dir(SECTOR).begins_with(_file)).is_false()
	assert_object(Catalog.data_only_holder(240)).is_null()
