class_name TestPackDoor
extends GdUnitTestSuite
## Teaches: one door for every file of a pack. The dev pack (a folder of the project: TRUSTED, its `.tres` are loaded) is exported whole in the data form
## (`PackExport.complete`) into a scratch pack that is not (a folder in `user://`), the scratch pack is chosen, and the game's own lookups answer from it: `Catalog` (zones, sprite
## frames, the tile set, a problem type, a sector with its screens, the speech groups), `Assets`, the sound resolvers and the music. Everything comes
## out equal to dev's own, and every picture and sound says it was read from the scratch pack's file. No file of the scratch pack is ever in the
## `ResourceLoader`'s cache (a `.json` is not a resource, and a `.png` of `user://` has no import): nothing but `FileAccess` and the `load_from_buffer`s touched it.

var _shelf: PackShelf
var _result: PackExport.Result


func before() -> void:
	_shelf = PackShelf.new(&"dev_in_data_form")
	var options := PackExport.Options.new()
	options.pack_id = _shelf.id
	options.reach = false
	_result = PackExport.complete(Packs.DEV, _shelf.root.get_base_dir(), options)       # (replaces the shelf's folder with the exported pack)
	# one thing the scratch pack says differently, so that it is plain who answers
	var zones: Dictionary = _shelf.pack_json("data/zones.json")
	zones["zones"][0]["title"] = "Scratch zone"
	_shelf.write_json("data/zones.json", zones)


func after() -> void:
	_shelf.remove()


func before_test() -> void:
	assert_object(_shelf.mount()).override_failure_message(str(Packs.fallback_reason())).is_not_null()


func after_test() -> void:
	Packs.start()


func _from_the_scratch_pack(resource: Resource) -> bool:
	return Packs.source_of(resource).begins_with(_shelf.root + "/")


func test_the_pack_is_exported_without_a_problem_and_is_not_trusted() -> void:
	assert_bool(_result.ok()).override_failure_message(_result.text()).is_true()
	assert_str(_result.path).is_equal(_shelf.root)
	assert_bool(_shelf.pack.trusted).is_false()
	assert_bool(Packs.dev().trusted).is_true()
	assert_array(Packs.chain_ids()).is_equal([_shelf.id])                                # (complete: laid over nothing)
	assert_array(_shelf.pack.problems()).is_empty()                                    # no resource and no code in it


func test_the_data_files_answer_from_the_scratch_pack() -> void:
	for rel in ["data/zones.tres", "data/trigger_table.tres", "data/bubble_rules.tres", "data/sprite_meta/sprite_meta_ink.tres", "data/neptune_tileset.tres",
			"data/sprite_frames/sub_frames.tres", "data/ui/hud_layout.tres", "data/voice_index.tres", "data/story/news_cartoon.tres",
			"data/story/title_reveal.tres", "data/story/story_script.tres", "data/story/voyager_closing_script.tres", "data/story/closing_crew.tres"]:
		assert_object(Packs.holder(rel)).override_failure_message(rel).is_same(_shelf.pack)
		assert_bool(_from_the_scratch_pack(Packs.resource(rel))).override_failure_message(rel).is_true()
	assert_str(Catalog.zone(0).title).is_equal("Scratch zone")
	assert_str(Catalog.zone(1).title).is_equal(Packs.dev().resource("data/zones.tres").zones[1].title)


func test_the_kinds_come_out_equal_to_dev_and_with_their_pictures_from_the_scratch_pack() -> void:
	var dev := Packs.dev()
	var checks := {
		"sub frames": [Catalog.sub_frames(), dev.resource("data/sprite_frames/sub_frames.tres")],
		"foes frames": [Catalog.foes_frames(2), dev.resource("data/sprite_frames/foes_zone2.tres")],
		"decos frames": [Catalog.decos_frames(1), dev.resource("data/sprite_frames/decos_zone1.tres")],
		"tile set": [Catalog.tileset(), dev.resource("data/neptune_tileset.tres")],
		"trigger table": [Catalog.trigger_table(), dev.resource("data/trigger_table.tres")],
		"hud layout": [Catalog.hud_layout(), dev.resource("data/ui/hud_layout.tres")],
		"bubble rules": [Catalog.bubble_rules(), dev.resource("data/bubble_rules.tres")],
		"sfx": [Catalog.sfx_catalog(), dev.resource("data/sfx_catalog.tres")],
		"texts": [Catalog.texts("hints"), dev.resource("data/problems/hints.tres")],
	}
	for what: String in checks:
		var differences: Array[String] = []
		ResourceCompare.same(checks[what][0], checks[what][1], what, differences)
		assert_array(differences).override_failure_message("%s: %s" % [what, "\n".join(differences.slice(0, 5))]).is_empty()
	var sub_picture := Catalog.sub_frames().get_frame_texture(&"all", 0)
	assert_bool(Packs.source_of(sub_picture).begins_with(_shelf.root + "/assets/sprites/sub/")).is_true()
	var tile_source := Catalog.tileset().get_source(0) as TileSetAtlasSource
	assert_bool(Packs.source_of(tile_source.texture).begins_with(_shelf.root + "/assets/tiles/")).is_true()
	assert_bool(Packs.source_of(Catalog.sfx_catalog().streams[0]).begins_with(_shelf.root + "/assets/audio/sfx/")).is_true()
	# a `$path` is read in the pack that holds the file: the problem type is dev's, its picture files are the scratch pack's
	var type := Catalog.problem_type(3)
	var type_in_dev := dev.resource("data/problems/problem_type_03.tres") as ProblemType
	assert_int(type.art_files.size()).is_equal(type_in_dev.art_files.size())
	for i in type.art_files.size():
		assert_str(type.art_files[i]).starts_with(_shelf.root + "/assets/")
		assert_str(Packs.relative(type.art_files[i])).is_equal(Packs.relative(type_in_dev.art_files[i]))
	var like_it := type_in_dev.duplicate() as ProblemType                             # (a copy: dev's own resource is shared)
	like_it.art_files = type.art_files
	like_it.art_dir = type.art_dir
	var differences: Array[String] = []
	ResourceCompare.same(type, like_it, "problem type", differences)
	assert_array(differences).is_empty()


func test_the_pictures_the_game_asks_for_by_name_come_from_the_scratch_pack() -> void:
	var title := Assets.ui_picture(&"title_sky")
	assert_object(title).is_not_null()
	assert_bool(Packs.source_of(title).begins_with(_shelf.root + "/assets/ui/")).is_true()
	var background := Assets.background(0, 0)
	assert_object(background).is_not_null()
	assert_bool(Packs.source_of(background).begins_with(_shelf.root + "/assets/backgrounds/")).is_true()
	var art := Assets.texture_at(Catalog.problem_type(3).art_files[0])
	assert_bool(Packs.source_of(art).begins_with(_shelf.root + "/")).is_true()


func test_the_sounds_come_from_the_scratch_pack() -> void:
	var index := Catalog.voice_index()
	assert_bool(index.paths[0].begins_with(_shelf.root + "/assets/audio/voice/")).is_true()
	var clip := index.stream(index.ids[0])
	assert_object(clip).is_instanceof(AudioStreamWAV)
	assert_bool(Packs.source_of(clip).begins_with(_shelf.root + "/assets/audio/voice/")).is_true()
	assert_float(clip.get_length()).is_greater(0.0)
	var catalog := Catalog.music_catalog()
	var song := catalog.stream(catalog.ids[0])
	assert_object(song).is_instanceof(AudioStreamOggVorbis)
	assert_bool(Packs.source_of(song).begins_with(_shelf.root + "/assets/audio/music/")).is_true()
	assert_bool(song.loop).is_true()


func test_a_sector_and_its_screens_come_from_the_scratch_pack() -> void:
	var index := Catalog.sector_ids()[0]
	assert_object(Packs.sector_owner(index)).is_same(_shelf.pack)
	var from_json := Catalog.sector(index)
	var from_dev := DevPack.sector(index)
	assert_array(Array(from_json.encode())).is_equal(Array(from_dev.encode()))
	assert_int(from_json.screens.size()).is_equal(SectorData.SCREEN_COUNT)
	for m in SectorData.SCREEN_COUNT:
		assert_array(Array(from_json.screens[m].encode())).override_failure_message("screen %d" % m).is_equal(Array(from_dev.screens[m].encode()))
	var campaign := Catalog.campaign(&"dev_tour")
	assert_str(campaign.pack_id).is_equal(String(_shelf.id))


func test_nothing_of_the_scratch_pack_reached_the_resource_loader() -> void:
	Catalog.sub_frames()
	Catalog.tileset()
	Catalog.voice_index().stream(Catalog.voice_index().ids[0])
	Assets.ui_picture(&"title_sky")
	for rel in _shelf.pack.all_files():
		assert_bool(ResourceLoader.has_cached(_shelf.pack.path_of(rel))).override_failure_message(rel).is_false()
	assert_bool(ResourceLoader.exists(_shelf.pack.path_of("assets/ui/title/%s" % _shelf.pack.files_in("assets/ui/title", "png")[0]))).is_false()   # (no import: Godot could not load it)


func test_a_path_outside_every_pack_gives_nothing() -> void:
	assert_object(Packs.file_at("user://nowhere/x.png")).is_null()
	assert_object(Packs.file_at("/etc/hostname")).is_null()
	assert_bool(Packs.exists_at("user://nowhere/x.png")).is_false()
	assert_object(Packs.file_at("res://packs/dev/assets/ui/title/%s" % Packs.dev().files_in("assets/ui/title", "png")[0])).is_instanceof(Texture2D)   # (dev is trusted)
