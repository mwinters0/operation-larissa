class_name TestNameRegistryLegacy
extends GdUnitTestSuite
## Teaches: checking a hand-made data file against the data it names. `names/original.json` is the registry of the original game's numbers: this suite checks
## every name against the real content of the legacy pack (how many sounds, zones, creatures ... the game has), the names the decompilation settled on, and
## the recordings the original stores twice. (The reader's rules and the file's convention are in tests/engine/test_name_registry.gd.)

const TEXT_TABLES := ["calc_notices", "closing", "help", "hints", "log_entries", "story", "supply_messages", "ui_strings"]
## The ids of the problem-panel art (docs/port/ASSET_FORMATS.md; the manifest lists no id outside it).
const PROBLEM_ART_IDS := Vector2i(1780, 2138)
## Creature picture slots 0-34 are common, the zone's own start at 35; deco slots 0-69 are common, the zone's own start at 70.
const FIRST_ZONE_FRAME := 35
const FIRST_ZONE_DECO := 70

var _names: NameRegistry


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func before_test() -> void:
	_names = NameRegistry.original()


## All (scope, name, number) of one kind in the committed file; the scope is NO_SCOPE for global kinds and common names.
func _stored(kind: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var scopes: Array[int] = [NameRegistry.NO_SCOPE]
	scopes.append_array(_names.named_scopes(kind))
	for scope in scopes:
		var table := _names.entries(kind) if scope == NameRegistry.NO_SCOPE else _scope_only(kind, scope)
		for name: String in table:
			found.append({"scope": scope, "name": name, "index": table[name]})
	return found


## The names of `scope` without the common ones (entries() gives both).
func _scope_only(kind: StringName, scope: int) -> Dictionary:
	var own := _names.entries(kind, scope)
	for name: String in _names.entries(kind):
		own.erase(name)
	return own


## Does number `index` of `kind` really exist in the game, in this scope?
func _exists(kind: StringName, scope: int, index: int) -> bool:
	match kind:
		&"sound":
			return index < Catalog.sfx_catalog().streams.size()
		&"frame":
			if scope == NameRegistry.NO_SCOPE:
				return index < FIRST_ZONE_FRAME
			return index >= FIRST_ZONE_FRAME and index < FIRST_ZONE_FRAME + Catalog.zone(scope).foe_count
		&"deco":
			if scope == NameRegistry.NO_SCOPE:
				return index < FIRST_ZONE_DECO
			return index >= FIRST_ZONE_DECO and index < FIRST_ZONE_DECO + Catalog.zone(scope).deco_count
		&"music":
			return Catalog.music_catalog().ids.has(index)
		&"voice":
			return Catalog.voice_index().ids.has(index)
		&"ui_picture":
			return Packs.has_file_at(Assets.ui_picture_path(index))
		&"problem_art":
			return index >= PROBLEM_ART_IDS.x and index <= PROBLEM_ART_IDS.y
		&"text":
			for table in TEXT_TABLES:
				if Catalog.texts(table).texts.has(index):
					return true
			return false
		&"zone":
			return index < Catalog.ZONE_COUNT
		&"sector":
			return index < Catalog.ORIGINAL_SECTOR_COUNT
		&"foe":
			return scope == NameRegistry.NO_SCOPE or index < Catalog.sector(scope).foes.size()
		&"screen":
			return index < Catalog.SCREENS_PER_SECTOR
		&"flag":
			return index < 16
	return false


## Does scope number `scope` exist for `kind` in the game?
func _scope_exists(kind: StringName, scope: int) -> bool:
	match kind:
		&"frame":
			return scope < Catalog.ZONE_COUNT
		&"deco":
			return scope < 5                                  # the art zones: the finale sectors use zone 4's decorations
		_:
			return scope < Catalog.ORIGINAL_SECTOR_COUNT


# --- the committed file --------------------------------------------------------------------------


func test_every_name_points_at_something_that_exists() -> void:
	for kind in NameRegistry.kinds():
		for entry in _stored(kind):
			var what := "%s '%s' = %d (scope %d)" % [kind, entry["name"], entry["index"], entry["scope"]]
			assert_bool(_exists(kind, entry["scope"], entry["index"])).override_failure_message(what).is_true()
			if entry["scope"] != NameRegistry.NO_SCOPE:
				assert_bool(_scope_exists(kind, entry["scope"])).override_failure_message(what + ": no such scope").is_true()


func test_the_seeded_names_are_the_known_ones() -> void:
	assert_int(_names.index_of(&"sound", "begin")).is_equal(22)
	assert_int(_names.index_of(&"sound", "scanner")).is_equal(29)
	assert_int(_names.entries(&"sound").size()).is_equal(46)               # the 24 of the decompilation and the 22 creature sounds
	assert_int(_names.index_of(&"music", "opening")).is_equal(9502)
	assert_int(_names.index_of(&"music", "finale")).is_equal(9500)
	assert_str(Catalog.voice_cues().jingle()).is_equal("jingle")
	assert_int(_names.index_of(&"zone", "dragon_reef")).is_equal(0)
	assert_str(_names.name_of(&"sector", 30)).is_equal("voyager_finale")
	assert_int(_names.index_of(&"flag", "finale", 20)).is_equal(15)      # a common name works in every sector
	assert_int(_names.index_of(&"frame", "ink_burst_3", 4)).is_equal(31)
	assert_int(_names.index_of(&"screen", "end_station", 7)).is_equal(11)


func test_every_creature_of_the_original_has_a_name_in_its_sector() -> void:
	for sector in Catalog.ORIGINAL_SECTOR_COUNT:
		for foe in Catalog.sector(sector).foes.size():
			assert_bool(_names.is_named(&"foe", foe, sector)).override_failure_message("sector %d foe %d" % [sector, foe]).is_true()


func test_the_creature_sounds_are_named_by_their_role() -> void:
	for sound in 22:
		assert_bool(_names.is_named(&"sound", sound)).override_failure_message("sound %d" % sound).is_true()
	assert_int(_names.index_of(&"sound", "clam_chomp")).is_equal(13)
	assert_int(_names.index_of(&"sound", "oxygen_refill")).is_equal(15)


func test_every_voice_clip_in_the_cues_has_a_name() -> void:
	var cues := Catalog.voice_cues()
	for group: String in cues.groups:
		for clip in cues.clips(group):
			assert_bool(_names.has_name(&"voice", clip) and not clip.begins_with("voice_")).override_failure_message("%s: clip %s" % [group, clip]).is_true()


# --- recordings the original stores twice -----------------------------------------------------------------------


func test_the_sounds_with_one_recording_are_listed() -> void:
	var expected: Array[Array] = [[6, 20, 21], [8, 17], [10, 11, 18], [14, 19], [15, 16], [23, 38]]
	assert_array(_names.same_audio_groups(&"sound")).is_equal(expected)
	assert_array(_names.same_audio(&"sound", 20)).is_equal([6, 21])
	assert_array(_names.same_audio(&"sound", 38)).is_equal([23])
	assert_array(_names.same_audio(&"sound", 22)).is_empty()          # a sound with no twin
	assert_array(_names.same_audio(&"voice", 4000)).is_empty()        # a kind with no groups
	assert_array(_names.same_audio(&"sandwich", 4000)).is_empty()


## The list in the file against the sound files themselves: the twins are byte for byte one file, and no other two are.
func test_the_listed_twins_are_the_files_that_are_alike() -> void:
	var by_hash: Dictionary = {}
	for i in 52:
		var path := Packs.source_of(Catalog.sfx_catalog().streams[i])
		var hash_of := FileAccess.get_sha256(path)
		assert_str(hash_of).override_failure_message("%s is missing" % path).is_not_empty()
		if not by_hash.has(hash_of):
			by_hash[hash_of] = []
		by_hash[hash_of].append(i)
	var found: Array[Array] = []
	for same: Array in by_hash.values():
		if same.size() > 1:
			found.append(same)
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	assert_array(found).is_equal(_names.same_audio_groups(&"sound"))


# --- every number has a name, and it finds the number again -----------------------------------------------------


func test_the_made_up_name_works_even_when_there_is_a_real_one() -> void:
	assert_str(_names.name_of(&"sound", 22)).is_equal("begin")
	assert_str(NameRegistry.fallback_name(&"sound", 22)).is_equal("sfx_22")
	assert_int(_names.index_of(&"sound", "sfx_22")).is_equal(22)          # an old script keeps working after the rename
	assert_int(_names.index_of(&"sound", "begin")).is_equal(22)
