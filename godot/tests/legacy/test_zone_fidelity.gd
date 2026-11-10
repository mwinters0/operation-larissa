class_name TestZoneFidelity
extends GdUnitTestSuite
## Teaches: which part of a table is the original's (docs/port/FIDELITY.md). Of everything in zones.tres only the default
## educational levels are a record of the original: 10 bytes in the program's data segment, `game * 5 + zone`. The titles are this
## project's own names, the picture counts and banners say which pictures of the art bundles the port uses, and the finale
## entries have no row of their own (the game uses the last zone's level). tests/fixtures/zones.json holds the provenance
## (ONWIN.EXE, the data segment at 0x25A8, 10 bytes) and the SHA-256 of the original table, and no original bytes.
## `ZoneTable.encode_default_edu_levels()` must hash to it, or the failure names the entry. (A table of 10 bytes with four
## possible values is small: its hash can be reversed by trying them all. The levels are printed in DESIGN 3.8 anyway.)
##
## The original table BYTES are written by the importer into the git-ignored tests/fixtures/original/zones.json. The
## tests that need them skip with a message when it is missing; the hash test never needs it.

const FIXTURE := "res://tests/fixtures/zones.json"
const ORIGINAL_BYTES := "res://tests/fixtures/original/zones.json"
const NEED_THE_IMPORTER := "run tools/import/import_all.py on your copy of the game"

## DELIBERATE CHANGE to the default levels: a non-empty reason once a designer changed them on purpose and wants to keep
## the change; the table then skips only the comparison with the original (it must still be valid and encode). The
## project's convention is the "Deliberate deviation" in docs/port/FIDELITY.md. To go back to the original
## instead, run tools/import/import_all.py --only sectors (it also resets every sector).
const DELIBERATE_LEVEL_CHANGE := ""


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func _fixture() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))


func _original_bytes() -> PackedByteArray:
	if not FileAccess.file_exists(ORIGINAL_BYTES):
		return PackedByteArray()
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ORIGINAL_BYTES))
	return String(parsed["hex"]).hex_decode()


func _copy() -> ZoneTable:
	return Catalog.zones().duplicate_deep() as ZoneTable


func test_the_fixture_has_its_provenance_and_holds_no_bytes() -> void:
	var fixture := _fixture()
	assert_array(fixture.keys()).contains_exactly_in_any_order(["comment", "source", "sha256"])
	assert_str(fixture["source"]["file"]).is_equal("ONWIN.EXE")
	assert_int(int(fixture["source"]["ds_offset"])).is_equal(0x25A8)
	assert_int(int(fixture["source"]["file_offset"])).is_equal(0x3C200 + 0x25A8)
	assert_int(int(fixture["source"]["size"])).is_equal(ZoneTable.DEFAULT_EDU_SIZE)
	assert_int(String(fixture["sha256"]).length()).is_equal(64)


func test_the_default_levels_encode_to_the_hash_of_the_original() -> void:
	if DELIBERATE_LEVEL_CHANGE != "":
		return
	var zones := Catalog.zones()
	var messages := zones.default_edu_problems()
	assert_array(messages).override_failure_message("the levels do not fit the original's: %s" % "\n".join(messages)).is_empty()
	var bytes := zones.encode_default_edu_levels()
	assert_int(bytes.size()).is_equal(ZoneTable.DEFAULT_EDU_SIZE)
	var text := "the default levels differ from the original (edited on purpose? set DELIBERATE_LEVEL_CHANGE); %s to see which zone" % NEED_THE_IMPORTER
	var original := _original_bytes()
	if not original.is_empty():
		text = "the default levels differ from the original: %s (edited on purpose? set DELIBERATE_LEVEL_CHANGE)" % ZoneTable.first_difference(original, bytes)
	assert_str(FixtureHash.sha256_hex(bytes)).override_failure_message(text).is_equal(_fixture()["sha256"])


func test_the_game_reads_the_stored_levels_and_a_finale_uses_the_last_zones() -> void:
	var table := _copy()
	var shared := Catalog.zones()
	for z in ZoneTable.ORIGINAL_ZONES:
		assert_int(Progression.default_edu_level(0, z)).is_equal(shared.zones[z].default_edu_level_voyager)
		assert_int(Progression.default_edu_level(1, z)).is_equal(shared.zones[z].default_edu_level_expert)
	for finale in [5, 6]:
		assert_int(shared.zones[finale].default_edu_level_voyager).is_equal(shared.zones[4].default_edu_level_voyager)
		assert_int(shared.zones[finale].default_edu_level_expert).is_equal(shared.zones[4].default_edu_level_expert)
		assert_int(Progression.default_edu_level(0, finale)).is_equal(shared.zones[4].default_edu_level_voyager)
	assert_int(table.zones.size()).is_equal(Catalog.ZONE_COUNT)


# --- what the original bytes show (need the importer's raw file) ------------------------------------------------

func test_the_levels_match_the_original_byte_for_byte() -> void:
	var original := _original_bytes()
	if original.is_empty():
		prints("SKIPPED: %s is missing; %s" % [ORIGINAL_BYTES, NEED_THE_IMPORTER])
		return
	assert_int(original.size()).is_equal(ZoneTable.DEFAULT_EDU_SIZE)
	if DELIBERATE_LEVEL_CHANGE != "":
		return
	assert_str(ZoneTable.first_difference(original, Catalog.zones().encode_default_edu_levels())).is_empty()


# --- a deliberately edited table gives a readable message --------------------------------------------------------

func test_an_edited_level_is_named() -> void:
	var original := Catalog.zones().encode_default_edu_levels()
	var table := _copy()
	table.zones[2].default_edu_level_expert = (table.zones[2].default_edu_level_expert + 1) % 4
	assert_str(ZoneTable.first_difference(original, table.encode_default_edu_levels())).starts_with("first difference at byte 7").contains("(Expert zone 2)")
	table = _copy()
	table.zones[0].default_edu_level_voyager = 3
	assert_str(ZoneTable.first_difference(original, table.encode_default_edu_levels())).contains("(Voyager zone 0)")
	assert_str(ZoneTable.first_difference(original, original)).is_empty()
	assert_str(ZoneTable.first_difference(original, PackedByteArray())).contains("0 bytes")


# --- what does not fit is refused, in words ---------------------------------------------------------------------

func test_a_level_that_does_not_exist_is_refused() -> void:
	var table := _copy()
	table.zones[1].default_edu_level_voyager = 4
	table.zones[3].default_edu_level_expert = -1
	var text := "\n".join(table.default_edu_problems())
	assert_str(text).contains("Voyager zone 1: educational level 4 does not exist, the levels are 0 to 3")
	assert_str(text).contains("Expert zone 3: educational level -1 does not exist")
	assert_int(table.encode_default_edu_levels().size()).is_equal(0)


func test_a_table_with_fewer_zones_than_the_original_is_refused() -> void:
	var table := _copy()
	table.zones.resize(4)
	assert_str("\n".join(table.default_edu_problems())).contains("zones: 4, but the table needs the 5 zones of the original")
