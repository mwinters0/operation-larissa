class_name TestSpriteMetaFidelity
extends GdUnitTestSuite
## Teaches: a fixture of HASHES as the anchor for an encoder (docs/port/FIDELITY.md, "Fixtures commit hashes, not bytes"), for
## the sprite sizes and hit rectangles. tests/fixtures/sprite_meta.json holds, per set of sprites (the common creatures,
## the ink bursts, the creatures of each zone), the provenance and the SHA-256 of the three original 512-byte NEP.DLL
## resources (widths, heights, hit rectangles), and no original bytes. `SpriteMetaTable.encode_widths()`,
## `encode_heights()` and `encode_hit_rects()` must hash to them, or the failure names the set and the table. The hashes
## are the anchor that does not come from your copy of the game: a different release or a patched copy is caught
## instead of being compared with itself.
##
## The original table BYTES are written by the importer into the git-ignored tests/fixtures/original/sprite_meta.json.
## The tests that need them (the byte-for-byte comparison that names the entry, "nothing follows the used sprites") skip
## with a message when it is missing; the hash tests never need it.

const FIXTURE := "res://tests/fixtures/sprite_meta.json"
const ORIGINAL_BYTES := "res://tests/fixtures/original/sprite_meta.json"
const NEED_THE_IMPORTER := "run tools/import/import_all.py on your copy of the game"
const DIR := LegacyPack.ROOT + "data/sprite_meta/sprite_meta_%s.tres"
const KINDS := ["widths", "heights", "hit_rects"]

## DELIBERATE CHANGES to the sprite sizes or hit rectangles of an original set: set name ("common", "ink", "zone0" ...) -> the
## reason. A designer who changes a hit rectangle on purpose and wants to keep the change lists the set here; it then skips
## only the comparison with the original (it must still be valid and encode). The project's convention is the
## "Deliberate deviation" in docs/port/FIDELITY.md. To go back to the original instead, run
## tools/import/import_all.py --only sprites (it also writes the sprite pictures again).
const DELIBERATE_SET_CHANGES := {}


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func _fixture() -> Array:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return parsed["sets"]


## The original table bytes (set name -> {kind -> bytes}), or an empty dictionary when the importer has not written them.
func _original_tables() -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(ORIGINAL_BYTES):
		return out
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ORIGINAL_BYTES))
	for entry: Dictionary in parsed["sets"]:
		var tables := {}
		for kind: String in KINDS:
			tables[kind] = String(entry[kind + "_hex"]).hex_decode()
		out[entry["name"]] = tables
	return out


## True (after saying why) when the importer's raw file is missing, for the tests that need the original bytes.
func _skip_without_original_bytes() -> bool:
	if FileAccess.file_exists(ORIGINAL_BYTES):
		return false
	prints("SKIPPED: %s is missing; %s" % [ORIGINAL_BYTES, NEED_THE_IMPORTER])
	return true


func _meta(set_name: String) -> SpriteMetaTable:
	return load(DIR % set_name) as SpriteMetaTable


func _copy_of(set_name: String) -> SpriteMetaTable:
	return _meta(set_name).duplicate_deep() as SpriteMetaTable


func _encode(table: SpriteMetaTable, kind: String) -> PackedByteArray:
	match kind:
		"widths":
			return table.encode_widths()
		"heights":
			return table.encode_heights()
	return table.encode_hit_rects()


func test_the_fixture_covers_the_nine_sets_with_their_provenance_and_holds_no_bytes() -> void:
	var sets := _fixture()
	assert_array(sets.map(func(entry: Dictionary) -> String: return entry["name"])).contains_exactly(
		["common", "ink", "zone0", "zone1", "zone2", "zone3", "zone4", "zone5", "zone6"])
	for entry: Dictionary in sets:
		assert_array(entry.keys()).contains_exactly_in_any_order(["name", "tables"])
		assert_array(entry["tables"].keys()).contains_exactly(KINDS)
		for kind: String in KINDS:
			var table: Dictionary = entry["tables"][kind]
			assert_str(table["source"]["file"]).is_equal("NEP.DLL")
			assert_int(int(table["source"]["real_id"])).is_between(10000, 12020)
			assert_str(table["source"]["extracted"]).is_not_empty()
			assert_int(int(table["offset"])).is_equal(0)
			assert_int(int(table["size"])).is_equal(SpriteMetaTable.RESOURCE_SIZE)
			assert_int(String(table["sha256"]).length()).is_equal(64)
			assert_array(table.keys()).contains_exactly_in_any_order(["source", "offset", "size", "sha256"])


## This also proves the zero tail: the importer hashes the resource as NEP.DLL holds it, 512 bytes, and the encoders end
## with zeros, so an original with a non-zero byte after the last sprite would not match.
func test_every_table_encodes_to_the_hash_of_the_original() -> void:
	var problems: Array[String] = []
	var originals := _original_tables()
	for entry: Dictionary in _fixture():
		var set_name: String = entry["name"]
		if DELIBERATE_SET_CHANGES.has(set_name):
			continue
		var table := _meta(set_name)
		var messages := table.problems()
		if not messages.is_empty():
			problems.append("%s: does not fit the original's tables: %s" % [set_name, messages[0]])
			continue
		for kind: String in KINDS:
			var bytes := _encode(table, kind)
			assert_int(bytes.size()).is_equal(SpriteMetaTable.RESOURCE_SIZE)
			if FixtureHash.sha256_hex(bytes) == entry["tables"][kind]["sha256"]:
				continue
			var text := "%s %s table differs from the original (edited on purpose? list it in DELIBERATE_SET_CHANGES); %s to see which entry" % [set_name, kind, NEED_THE_IMPORTER]
			if originals.has(set_name):
				text = "%s: %s (edited on purpose? list it in DELIBERATE_SET_CHANGES)" % [set_name, SpriteMetaTable.first_difference(kind, originals[set_name][kind], bytes, table.count())]
			problems.append(text)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_the_combined_table_of_a_zone_is_made_of_these_sets() -> void:
	for zone in Catalog.ZONE_COUNT:
		assert_int(SpriteMeta.for_zone(zone).count()).is_equal(_meta("common").count() + _meta("ink").count() + _meta("zone%d" % zone).count())


# --- what the original bytes show (need the importer's raw file) ------------------------------------------------

func test_the_tables_match_the_original_byte_for_byte_and_nothing_follows_the_used_sprites() -> void:
	if _skip_without_original_bytes():
		return
	var originals := _original_tables()
	assert_int(originals.size()).is_equal(9)
	for set_name: String in originals:
		if DELIBERATE_SET_CHANGES.has(set_name):
			continue
		var table := _meta(set_name)
		for kind: String in KINDS:
			var original: PackedByteArray = originals[set_name][kind]
			assert_int(original.size()).is_equal(SpriteMetaTable.RESOURCE_SIZE)
			assert_str(SpriteMetaTable.first_difference(kind, original, _encode(table, kind), table.count())).override_failure_message("%s %s" % [set_name, kind]).is_empty()
			var used := table.count() * (SpriteMetaTable.RECT_ENTRY if kind == "hit_rects" else 1)
			for i in range(used, original.size()):
				assert_int(original[i]).override_failure_message("%s %s byte %d" % [set_name, kind, i]).is_equal(0)


# --- a deliberately edited table gives a readable message --------------------------------------------------------

func test_an_edited_entry_is_named() -> void:
	var original := _meta("common").encode_hit_rects()
	var table := _copy_of("common")
	table.hit_rects_flipped[1].position.y += 2
	assert_str(SpriteMetaTable.first_difference("hit_rects", original, table.encode_hit_rects(), table.count())).starts_with(
		"first difference in the hit_rects table at byte 0x00d").contains("(sprite 1 flipped hit rectangle top)")
	table = _copy_of("common")
	table.sizes[3].x += 4
	assert_str(SpriteMetaTable.first_difference("widths", _meta("common").encode_widths(), table.encode_widths(), table.count())).contains("(sprite 3 width)")
	table = _copy_of("common")
	table.sizes[2].y -= 2
	assert_str(SpriteMetaTable.first_difference("heights", _meta("common").encode_heights(), table.encode_heights(), table.count())).contains("(sprite 2 height)")
	table = _copy_of("common")
	table.hit_rects[0].size.x += 2                  # the right edge moves
	assert_str(SpriteMetaTable.first_difference("hit_rects", original, table.encode_hit_rects(), table.count())).contains("(sprite 0 hit rectangle right)")


func test_a_sprite_added_after_the_stored_ones_is_marked_and_equal_tables_have_no_difference() -> void:
	var original := _meta("ink").encode_widths()
	var table := _copy_of("ink")
	table.sizes.append(Vector2i(10, 10))
	table.hit_rects.append(Rect2i(0, 0, 4, 4))
	table.hit_rects_flipped.append(Rect2i(0, 0, 4, 4))
	assert_str(SpriteMetaTable.first_difference("widths", original, table.encode_widths(), _meta("ink").count())).contains("(sprite 7 width (after the stored sprites))")
	assert_str(SpriteMetaTable.first_difference("widths", original, original)).is_empty()
	assert_str(SpriteMetaTable.first_difference("widths", original, PackedByteArray())).contains("0 bytes")


# --- what does not fit is refused, in words ---------------------------------------------------------------------

func test_an_original_set_has_no_problems_and_every_table_is_512_bytes() -> void:
	for set_name in ["common", "ink", "zone0", "zone1", "zone2", "zone3", "zone4", "zone5", "zone6"]:
		var table := _meta(set_name)
		assert_array(table.problems()).override_failure_message(set_name).is_empty()
		for kind: String in KINDS:
			assert_int(_encode(table, kind).size()).is_equal(SpriteMetaTable.RESOURCE_SIZE)


func test_values_off_the_grid_or_out_of_range_are_refused() -> void:
	var table := _copy_of("ink")
	table.sizes[0] = Vector2i(17, -2)
	table.hit_rects[1] = Rect2i(3, 0, 600, 4)
	var text := "\n".join(table.problems())
	assert_str(text).contains("sprite 0 width 17 is not on the grid: the original keeps it / 2, so it must be even")
	assert_str(text).contains("sprite 0 height -2 does not fit")
	assert_str(text).contains("sprite 1 hit rectangle left 3 is not on the grid")
	assert_str(text).contains("sprite 1 hit rectangle right (left + width) 603 does not fit")
	assert_int(table.encode_widths().size()).is_equal(0)
	assert_int(table.encode_hit_rects().size()).is_equal(0)


func test_the_three_lists_must_have_the_same_length_and_fit_the_table() -> void:
	var table := _copy_of("ink")
	table.hit_rects.pop_back()
	assert_str("\n".join(table.problems())).contains("there must be one of each per sprite")
	table = SpriteMetaTable.new()
	for i in SpriteMetaTable.MAX_SPRITES + 1:
		table.sizes.append(Vector2i(2, 2))
		table.hit_rects.append(Rect2i())
		table.hit_rects_flipped.append(Rect2i())
	assert_str("\n".join(table.problems())).contains("65 sprites, but the hit rectangle table has room for 64")
