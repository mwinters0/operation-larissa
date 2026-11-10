class_name TestPacks
extends GdUnitTestSuite
## Teaches: a layered lookup that leaves the game alone until a pack is in the chain. A pack is a root and relative paths under
## it; the first pack of the chain that has a thing answers, and the packs it is laid over answer the rest. This test puts scratch packs in `user://` (`PackShelf`) over
## the pack the suite runs on and watches each kind of lookup: sectors, campaigns, texts, speech groups, problem types, pictures, sounds, songs and speech clips. After every
## test the game is as it shipped, which the first test states for itself. (How the chain is chosen and built is `test_pack_chain.gd`.)

const BLIP := "res://tests/fixtures/pack_blip.ogg.bin"

var _shelves: Array[PackShelf] = []


func after_test() -> void:
	for shelf in _shelves:
		shelf.remove()
	_shelves.clear()
	Packs.start()


func _shelf(pack_id: StringName = &"", base: StringName = &"") -> PackShelf:
	var shelf := PackShelf.new(pack_id, base)
	_shelves.append(shelf)
	return shelf


func _blip() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(BLIP)


# --- the game with no pack ----------------------------------------------------------------------------------------------------

func test_with_no_data_pack_in_the_chain_the_game_is_what_it_was() -> void:
	assert_array(Packs.chain_ids()).is_equal([PackShelf.base_id()])
	assert_object(Packs.fallback_reason()).is_null()
	assert_array(Catalog.sector_ids()).contains(DevPack.TOUR_SECTORS + [DevPack.TOUR_FINALE])
	assert_bool(Catalog.campaigns().any(func(c: Campaign) -> bool: return c.id == DevPack.TOUR)).is_true()
	assert_str(Catalog.text(&"click_to_go_on")).is_not_empty()
	assert_object(Packs.picture("ui_picture/title_sky")).is_null()
	assert_object(Packs.clip(&"sound", &"correct")).is_null()
	assert_object(Catalog.voice_cues()).is_same(Catalog.voice_cues())
	assert_bool(Catalog.has_sector(40)).is_false()


# --- the manifest ---------------------------------------------------------------------------------------------------------------

func test_a_manifest_names_the_pack() -> void:
	var shelf := _shelf(&"fine")
	var pack := Pack.open(shelf.root)
	assert_array(pack.errors).is_empty()
	assert_str(pack.id).is_equal(&"fine")
	assert_str(pack.title).is_equal("Scratch fine")
	assert_str(pack.version).is_equal("1.0")
	assert_int(pack.format).is_equal(Pack.FORMAT)
	assert_bool(pack.trusted).is_false()
	assert_dict(pack.manifest()).is_equal({"format": Pack.FORMAT, "id": "fine", "title": "Scratch fine", "version": "1.0", "base": String(PackShelf.base_id())})


func test_a_manifest_that_is_wrong_says_how() -> void:
	var shelf := _shelf(&"wrong")
	shelf.write_json("pack.json", {"id": "Bad Id", "title": " ", "version": "", "format": 99})
	var errors := "\n".join(Pack.open(shelf.root).errors)
	assert_str(errors).contains("not a lowercase word")
	assert_str(errors).contains("title is empty")
	assert_str(errors).contains("version is empty")
	assert_str(errors).contains("format 99")
	shelf.write_json("pack.json", {"title": "No id"})
	assert_str("\n".join(Pack.open(shelf.root).errors)).contains("has no \"id\"")
	shelf.write_text("pack.json", "this is not json")
	assert_str("\n".join(Pack.open(shelf.root).errors)).contains("not a JSON object")
	DirAccess.remove_absolute(shelf.root + "/pack.json")
	assert_str("\n".join(Pack.open(shelf.root).errors)).contains("no pack.json")
	assert_bool(Pack.open(shelf.root).is_valid()).is_false()


# --- a pack in the chain ----------------------------------------------------------------------------------------------------------

func test_a_pack_laid_over_the_base_pack_is_chosen_and_the_world_is_told() -> void:
	var changes: Array[int] = [0]
	var listener := func() -> void: changes[0] += 1
	Packs.events.changed.connect(listener)
	var shelf := _shelf(&"first")
	assert_object(shelf.mount()).is_not_null()
	assert_bool(Packs.in_chain(&"first")).is_true()
	assert_array(Packs.chain_ids()).is_equal([&"first", PackShelf.base_id()])
	assert_int(changes[0]).is_equal(1)
	assert_object(Packs.chosen()).is_same(shelf.pack)
	Packs.start()
	assert_int(changes[0]).is_equal(2)
	assert_bool(Packs.in_chain(&"first")).is_false()
	Packs.events.changed.disconnect(listener)


func test_a_manifest_that_says_tier_is_read_and_the_key_is_ignored() -> void:
	var shelf := _shelf(&"sneaky")
	shelf.write_json("pack.json", {"id": "sneaky", "title": "Sneaky", "version": "1", "base": String(PackShelf.base_id())})
	shelf.write_text("data/evil.tres", "[gd_resource type=\"Resource\" format=3]\n")
	var pack := shelf.mount()                                    # (a folder in user:// that claims to be code, so that its .tres could be loaded)
	assert_object(pack).is_not_null()
	assert_bool(pack.trusted).is_false()
	assert_object(pack.resource("data/evil.tres")).is_null()
	assert_bool(pack.manifest().has("tier")).is_false()


func test_a_data_pack_cannot_open_a_resource() -> void:
	var shelf := _shelf(&"plain")
	shelf.write_text("data/evil.tres", "[gd_resource type=\"Resource\" format=3]\n")
	var pack := shelf.mount()
	assert_bool(pack.has("data/evil.tres")).is_true()
	assert_bool(pack.trusted).is_false()
	assert_object(pack.resource("data/evil.tres")).is_null()                  # (the door opens the data form only: there is no data/evil.json)
	assert_bool(pack.provides("data/evil.tres")).is_false()
	assert_str("\n".join(pack.problems())).contains("a pack outside the project holds no resources or code")


func test_paths_that_leave_the_pack_are_not_read() -> void:
	var shelf := _shelf(&"fenced")
	shelf.write_text("inside.txt", "yes")
	var pack := shelf.mount()
	assert_str(pack.read_text("inside.txt")).is_equal("yes")
	for bad in ["../pack.json", "/etc/passwd", "a/../../x", "res://project.godot", "a\\b", "", "a//b"]:
		assert_bool(Pack.is_safe(bad)).override_failure_message(bad).is_false()
		assert_bool(pack.has(bad)).is_false()
		assert_str(pack.read_text(bad)).is_empty()


func test_the_layout_problems_are_listed() -> void:
	var shelf := _shelf(&"messy")
	shelf.write_json("data/zones.json", {"class": "ZoneTable"})
	shelf.write_text("data/zones.tres", "[gd_resource type=\"Resource\" format=3]\n")
	var pack := shelf.mount()
	assert_str("\n".join(pack.problems())).contains("data/zones.tres: a pack outside the project holds no resources or code")
	assert_str("\n".join(pack.problems())).not_contains("data/zones.json")      # (any other data/ file is just not read: no rule protects the original's data)


func test_a_pack_may_hold_a_sector_or_a_campaign_of_the_base_pack_and_then_it_is_the_packs() -> void:
	var shelf := _shelf(&"remake")
	var changed := shelf.add_sector_copy(3, 0)                           # sector 0 of the pack is a copy of sector 3 (which has other creatures)
	shelf.write_json("campaigns/dev_tour.json", {"class": "Campaign", "id": "dev_tour", "title": "Remade", "sectors": [0], "finales": [DevPack.TOUR_FINALE]})
	var pack := shelf.mount()
	assert_array(pack.problems()).is_empty()
	assert_array(pack.sector_ids()).is_equal([0])
	assert_int(changed.foes.size()).is_not_equal(DevPack.TOUR_CREATURES[0])
	assert_int(Catalog.sector(0).foes.size()).is_equal(changed.foes.size())      # the pack's sector 0, not the base pack's
	assert_object(Packs.sector_owner(0)).is_same(pack)
	assert_str(Catalog.campaign(DevPack.TOUR).title).is_equal("Remade")
	assert_array(Catalog.campaigns().filter(func(c: Campaign) -> bool: return c.id == DevPack.TOUR)).has_size(1)     # (the one below it is hidden)
	assert_int(Catalog.sector(1).screens.size()).is_equal(DevPack.SCREENS)         # the other sectors are the base pack's
	Packs.start()
	assert_int(Catalog.sector(0).foes.size()).is_equal(DevPack.TOUR_CREATURES[0])
	assert_str(Catalog.campaign(DevPack.TOUR).title).is_not_equal("Remade")


func test_two_packs_with_one_sector_number_the_one_nearer_the_top_of_the_chain_wins() -> void:
	var first := _shelf(&"one")
	first.add_sector_copy(0, 40)
	var second := _shelf(&"two", &"one")
	var changed := second.add_sector_copy(3, 40)
	second.mount()
	assert_array(Packs.chain_ids()).is_equal([&"two", &"one", PackShelf.base_id()])
	assert_int(Catalog.sector(40).foes.size()).is_equal(changed.foes.size())
	assert_object(Packs.sector_owner(40)).is_same(Packs.pack(&"two"))
	first.mount()                                                          # one alone: its own sector 40 answers
	assert_int(Catalog.sector(40).foes.size()).is_equal(Catalog.sector(0).foes.size())


# --- sectors and campaigns -----------------------------------------------------------------------------------------------------

func test_a_packs_sectors_and_campaigns_are_found_beside_the_games() -> void:
	var shelf := _shelf(&"garden")
	shelf.add_sector_copy(0, 40)
	shelf.add_sector_copy(DevPack.test_sector("e", 0), 41)
	var campaign := Campaign.new()
	campaign.id = &"garden_pack"
	campaign.title = "Garden"
	campaign.sectors = PackedInt32Array([40])
	campaign.finales = PackedInt32Array([41])
	campaign.default_edu_levels = PackedInt32Array([0])
	campaign.log_unlock_order = PackedInt32Array([1])
	campaign.finale_log_counts = PackedInt32Array([1])
	campaign.log_texts = [&"One note."]
	campaign.log_voices = [&""]
	campaign.supply_texts = [&"Planted."]
	campaign.supply_voices = [&""]
	shelf.add_campaign(campaign)
	var base_ids := Catalog.sector_ids()
	shelf.mount()
	assert_bool(Catalog.has_sector(40)).is_true()
	assert_array(Catalog.sector_ids()).contains([40, 41] + base_ids)
	assert_int(Catalog.sector_ids().size()).is_equal(base_ids.size() + 2)
	assert_bool(Catalog.has_sector(Catalog.next_free_sector())).is_false()
	assert_int(Catalog.sector(40).index).is_equal(40)
	assert_object(Catalog.sector(40)).is_same(Catalog.sector(40))               # made once and kept
	assert_int(SimWorld.finale_screen(41)).is_equal(Catalog.sector(DevPack.test_sector("e", 0)).finale_screen)
	var ids: Array = Catalog.campaigns().map(func(c: Campaign) -> StringName: return c.id)
	assert_array(ids).contains([DevPack.TOUR, &"garden_pack"])
	var found := Catalog.campaign(&"garden_pack")
	assert_str(found.pack_id).is_equal(&"garden")
	assert_array(found.problems()).is_empty()
	assert_array(Catalog.campaign_problems()).is_empty()
	assert_object(Catalog.campaign_of_sector(40)).is_same(found)
	assert_str(Catalog.campaign_name_of_sector(41)).is_equal("Garden Pack")
	Packs.start()
	assert_bool(Catalog.has_sector(40)).is_false()
	assert_object(Catalog.campaign(&"garden_pack")).is_null()
	assert_array(Catalog.sector_ids()).is_equal(base_ids)


func test_a_campaign_file_whose_id_is_not_its_name_is_refused() -> void:
	var shelf := _shelf(&"liar")
	shelf.write_json("campaigns/real_name.json", {"class": "Campaign", "id": "other_name", "title": "X"})
	shelf.write_json("campaigns/no_id.json", {"class": "Campaign", "title": "Y", "sectors": [40]})
	shelf.mount()
	assert_object(Catalog.campaign(&"other_name")).is_null()
	assert_object(Catalog.campaign(&"real_name")).is_null()
	assert_str(Catalog.campaign(&"no_id").id).is_equal(&"no_id")                    # no id: the file's name is it


# --- words, speech groups, problems ----------------------------------------------------------------------------------------------

func test_a_pack_says_a_text_in_its_own_words() -> void:
	var original := Catalog.text(&"click_to_go_on")
	var shelf := _shelf(&"words")
	shelf.write_json("texts.json", {"click_to_go_on": "Klick weiter", "garden_hello": "Hello, gardener."})
	shelf.mount()
	assert_str(Catalog.text(&"click_to_go_on")).is_equal("Klick weiter")
	assert_str(Catalog.text(&"garden_hello")).is_equal("Hello, gardener.")
	assert_bool(Catalog.has_text(&"garden_hello")).is_true()
	assert_str(Campaign.text("garden_hello")).is_equal("Hello, gardener.")
	Packs.start()
	assert_str(Catalog.text(&"click_to_go_on")).is_equal(original)
	assert_bool(Catalog.has_text(&"garden_hello")).is_false()


func test_a_pack_sets_a_duration_and_keeps_the_others() -> void:
	var opening := Durations.at("station.dock.opening_ticks")
	var closing := Durations.at("station.dock.closing_ticks")
	var shelf := _shelf(&"slow_dock")
	shelf.write_json(Durations.PACK_PATH, {"station": {"dock": {"opening_ticks": opening + 7}}})
	shelf.mount()
	assert_int(Durations.at("station.dock.opening_ticks")).is_equal(opening + 7)
	assert_int(Durations.at("station.dock.closing_ticks")).is_equal(closing)
	Packs.start()
	assert_int(Durations.at("station.dock.opening_ticks")).is_equal(opening)


func test_a_pack_sets_a_rule_value_and_keeps_the_others() -> void:
	var before := Tuning.resolve()
	var shelf := _shelf(&"thin_air")
	shelf.write_json(Tuning.PACK_PATH, {"air": {"max_oxygen": 6}, "sub": {"max_speed_x_units": 64}})
	shelf.mount()
	var tuning := Tuning.resolve()
	assert_int(tuning.max_oxygen).is_equal(6)
	assert_int(tuning.sub.max_speed_x_units).is_equal(64)
	assert_int(tuning.max_tanks).is_equal(before.max_tanks)
	assert_int(tuning.sub.max_speed_y_units).is_equal(before.sub.max_speed_y_units)
	assert_array(Tuning.files().slice(-1)).is_equal([shelf.root + "/" + Tuning.PACK_PATH])
	Packs.start()
	assert_int(Tuning.resolve().max_oxygen).is_equal(before.max_oxygen)


func test_a_pack_adds_speech_groups_to_the_originals() -> void:
	var before := Catalog.voice_cues()
	var shelf := _shelf(&"speech")
	shelf.write_json("voice_cues.json", {"groups": {"garden_log_1": ["garden_line_a", "garden_line_b"]}})
	shelf.mount()
	var cues := Catalog.voice_cues()
	assert_array(cues.clips("garden_log_1")).is_equal([&"garden_line_a", &"garden_line_b"])
	assert_array(cues.clips("supply_0")).is_equal(before.clips("supply_0"))              # the original's groups are all still there
	assert_array(before.clips("garden_log_1")).is_empty()                                 # and the original object was not touched
	Packs.start()
	assert_object(Catalog.voice_cues()).is_same(before)


func test_a_pack_replaces_a_problem_type_from_json() -> void:
	var type := load(DevPack.path("data/problems/problem_type_05.tres")) as ProblemType
	var writer := ResourceJson.new()
	var data := writer.data_of(type)
	data["title"] = "Garden sums"
	var shelf := _shelf(&"sums")
	shelf.write_json("data/problems/problem_type_05.json", data)
	shelf.mount()
	assert_str(Catalog.problem_type(5).title).is_equal("Garden sums")
	assert_array(Array(Catalog.problem_type(5).text_ids)).is_equal(Array(type.text_ids))      # everything else is the original's
	assert_str(Catalog.problem_type(6).title).is_equal(load(DevPack.path("data/problems/problem_type_06.tres")).title)
	Packs.start()
	assert_str(Catalog.problem_type(5).title).is_equal(type.title)


# --- pictures -------------------------------------------------------------------------------------------------------------------------

func test_a_packs_picture_replaces_the_originals_and_a_new_name_is_found() -> void:
	var original := Assets.ui_picture(&"title_sky")
	var original_size := original.get_size()
	var shelf := _shelf(&"paint")
	shelf.add_picture("pictures/ui_picture/title_sky.png", Color.RED, Vector2i(5, 3))
	shelf.add_picture("pictures/ui_picture/garden_gate.png", Color.GREEN, Vector2i(7, 2))
	shelf.add_picture("pictures/background/bg_s40_00.png", Color.BLUE, Vector2i(6, 6))
	shelf.mount()
	assert_vector(Assets.ui_picture(&"title_sky").get_size()).is_equal(Vector2(5, 3))
	assert_vector(Assets.ui_picture(&"garden_gate").get_size()).is_equal(Vector2(7, 2))         # a name only the pack has
	assert_vector(Assets.background(40, 0).get_size()).is_equal(Vector2(6, 6))                    # the picture behind a screen of a pack's sector
	assert_object(Assets.background(40, 1)).is_null()
	assert_vector(Assets.background(0, 0).get_size()).is_equal(Assets.texture_at(DevPack.path("assets/backgrounds/bg_s00_00.png")).get_size())
	Packs.start()
	assert_vector(Assets.ui_picture(&"title_sky").get_size()).is_equal(original_size)
	assert_object(Assets.background(40, 0)).is_null()


func test_a_packs_picture_reaches_the_pictures_data_holds_and_goes_away_with_the_pack() -> void:
	var before := Catalog.hud_layout()
	var path := DevPack.path("assets/ui/hud/")
	var some_key := ""
	for property in before.get_property_list():                       # any picture of the HUD layout: its key is what a pack redraws
		var value: Variant = before.get(property.name)
		if value is Texture2D and (value as Texture2D).resource_path.begins_with(path):
			some_key = GameSkin.key_of(value.resource_path)
			break
	assert_str(some_key).is_not_empty()
	var shelf := _shelf(&"hud")
	shelf.add_picture("pictures/%s.png" % some_key, Color.RED, Vector2i(2, 2))
	shelf.mount()
	var during := Catalog.hud_layout()
	assert_object(during).is_not_same(before)                          # a copy with the pack's picture put in
	var replaced := 0
	for property in during.get_property_list():
		var value: Variant = during.get(property.name)
		if value is Texture2D and (value as Texture2D).get_size() == Vector2(2, 2):
			replaced += 1
	assert_int(replaced).is_greater_equal(1)
	Packs.start()
	assert_object(Catalog.hud_layout()).is_same(before)                # the very object again: no copy, no pack


# --- sounds ---------------------------------------------------------------------------------------------------------------------------

func test_a_packs_sounds_songs_and_speech_replace_or_add_by_name() -> void:
	var shelf := _shelf(&"noise")
	shelf.write_bytes("audio/sound/correct.ogg", _blip())
	shelf.write_bytes("audio/sound/garden_chime.ogg", _blip())
	shelf.write_bytes("audio/music/garden_song.ogg", _blip())
	shelf.write_bytes("audio/voice/garden_line_a.ogg", _blip())
	var voice_name := StringName(NameRegistry.original().name_of(&"voice", Catalog.voice_index().ids[0]))
	shelf.write_bytes("audio/voice/%s.ogg" % voice_name, _blip())
	var original_ticks := Catalog.voice_index().ticks_named(voice_name)
	var original_sound := Catalog.sfx_catalog().stream_named(&"correct")
	shelf.mount()
	var sounds := Catalog.sfx_catalog()
	assert_object(sounds.stream_named(&"correct")).is_instanceof(AudioStreamOggVorbis)
	assert_object(sounds.stream_named(&"correct")).is_not_same(original_sound)
	assert_object(sounds.stream_named(&"garden_chime")).is_instanceof(AudioStreamOggVorbis)       # a name the original does not have
	assert_object(sounds.stream_named(&"lock_tick")).is_same(Catalog.sfx_catalog().stream_named(&"lock_tick"))
	var song := Catalog.music_catalog().stream_named(&"garden_song") as AudioStreamOggVorbis
	assert_object(song).is_not_null()
	assert_bool(song.loop).is_true()                                                              # a song loops, as the original's do
	assert_str(MusicCatalog.song_of_stem("garden_song")).is_equal(&"garden_song")
	assert_str(MusicCatalog.song_of_stem("esect2")).is_equal(&"sector_song_2")                    # the original's stems are untouched
	assert_str(MusicCatalog.song_of_stem("nothing_at_all")).is_equal(&"")
	var voices := Catalog.voice_index()
	assert_object(voices.stream_named(&"garden_line_a")).is_instanceof(AudioStreamOggVorbis)
	var blip_ticks := ClipLengths.measure(AudioStreamOggVorbis.load_from_buffer(_blip()))
	assert_int(blip_ticks).is_greater(0)
	assert_int(voices.ticks_named(&"garden_line_a")).is_equal(blip_ticks)                         # G2a: a pack's own clip lasts what its file does
	assert_int(voices.ticks_named(voice_name)).is_equal(blip_ticks)                               # ... and so does a replaced one, not the original's
	assert_int(blip_ticks).is_not_equal(original_ticks)
	var clip := Packs.clip(&"voice", voice_name)
	assert_str(clip.pack_id).is_equal(&"noise")
	assert_int(clip.ticks).is_equal(blip_ticks)                                                   # the length comes with the stream, from the same pack
	Packs.start()
	assert_int(Catalog.voice_index().ticks_named(voice_name)).is_equal(original_ticks)             # unmounted: the original's number again
	assert_object(Catalog.sfx_catalog().stream_named(&"correct")).is_same(original_sound)
	assert_object(Catalog.sfx_catalog().stream_named(&"garden_chime")).is_null()


func test_a_file_that_is_not_a_picture_or_a_sound_is_nothing_with_a_warning() -> void:
	var shelf := _shelf(&"junk")
	shelf.write_text("pictures/ui_picture/title_sky.png", "not a png")
	shelf.write_text("audio/sound/correct.ogg", "not an ogg")
	shelf.mount()
	assert_object(Packs.picture("ui_picture/title_sky")).is_null()
	assert_object(Packs.clip(&"sound", &"correct")).is_null()
	assert_object(Assets.ui_picture(&"title_sky")).is_not_null()                                    # the original's, as if the pack did not have it


# --- what can be chosen (the list G4 shows) ----------------------------------------------------------------------------------

func test_available_lists_the_packs_in_the_packs_folder_of_the_user() -> void:
	var folder := Packs.USER_PACKS_DIR + "/test_listed_pack"
	DirAccess.make_dir_recursive_absolute(folder)
	var manifest := FileAccess.open(folder + "/pack.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"id": "test_listed_pack", "title": "Listed", "version": "2", "base": String(PackShelf.base_id())}))
	manifest.close()
	var ids: Array = Packs.available().map(func(p: Pack) -> StringName: return p.id)
	assert_array(ids).contains([&"test_listed_pack"])
	assert_bool(Packs.choose(&"test_listed_pack")).is_true()
	assert_array(Packs.chain_ids()).is_equal([&"test_listed_pack", PackShelf.base_id()])
	Packs.start()
	DirAccess.remove_absolute(folder + "/pack.json")
	DirAccess.remove_absolute(folder)


func test_dev_is_never_offered_and_a_pack_linked_into_the_project_is_listed_once() -> void:
	var ids: Array = Packs.available().map(func(p: Pack) -> StringName: return p.id)
	assert_array(ids).not_contains([Packs.DEV])
	# a pack that lives in `user://packs/` and is linked into the project as `res://packs/<id>` is one pack, not two
	var id := "test_linked_pack"
	var folder := Packs.USER_PACKS_DIR + "/" + id
	var link := Packs.PROJECT_PACKS_DIR + "/" + id
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder + "/pack.json", FileAccess.WRITE).store_string(JSON.stringify({"id": id, "title": "Linked", "version": "1"}))
	var made := DirAccess.open(ProjectSettings.globalize_path(Packs.PROJECT_PACKS_DIR)).create_link(ProjectSettings.globalize_path(folder), ProjectSettings.globalize_path(link))
	assert_int(made).is_equal(OK)
	var listed: Array = Packs.available().filter(func(p: Pack) -> bool: return p.id == StringName(id))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(link))              # (the link only: remove does not follow it)
	DirAccess.remove_absolute(folder + "/pack.json")
	DirAccess.remove_absolute(folder)
	assert_array(listed).has_size(1)
	assert_bool(DirAccess.dir_exists_absolute(link)).is_false()
