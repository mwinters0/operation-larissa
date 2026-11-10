class_name TestTriggerTableFidelity
extends GdUnitTestSuite
## Teaches: a fixture of HASHES as the anchor for an encoder (docs/port/FIDELITY.md, "Fixtures commit hashes, not bytes"), for
## the table that turns a math trigger into a problem type. tests/fixtures/trigger_table.json holds the provenance
## (ONWIN.EXE, the data segment at 0x22BE, 504 bytes) and the SHA-256 of the whole original table, and no original
## bytes. `TriggerTable.encode()` must hash to it, or the failure names the entry. The hash is the anchor that does not
## come from your copy of the game: a different release or a patched copy is caught instead of being compared with itself.
##
## The original table BYTES are written by the importer into the git-ignored tests/fixtures/original/trigger_table.json.
## The tests that need them (the comparison that names the entry) skip with a message when it is missing; the hash test
## never needs it.

const FIXTURE := "res://tests/fixtures/trigger_table.json"
const ORIGINAL_BYTES := "res://tests/fixtures/original/trigger_table.json"
const NEED_THE_IMPORTER := "run tools/import/import_all.py on your copy of the game"

## DELIBERATE CHANGE to the table (which problem a trigger gives): true plus the reason once a designer changed it on
## purpose and wants to keep the change; the table then skips only the comparison with the original (it must still be valid
## and encode). The project's convention is the "Deliberate deviation" in docs/port/FIDELITY.md. To go back
## to the original instead, run tools/import/import_all.py --only sectors (it also resets every sector).
const DELIBERATE_TABLE_CHANGE := ""


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func _fixture() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))


## The original table bytes, or an empty array when the importer has not written them.
func _original_bytes() -> PackedByteArray:
	if not FileAccess.file_exists(ORIGINAL_BYTES):
		return PackedByteArray()
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ORIGINAL_BYTES))
	return String(parsed["hex"]).hex_decode()


func _copy() -> TriggerTable:
	return Catalog.trigger_table().duplicate_deep() as TriggerTable


func test_the_fixture_has_its_provenance_and_holds_no_bytes() -> void:
	var fixture := _fixture()
	assert_array(fixture.keys()).contains_exactly_in_any_order(["comment", "source", "sha256"])
	assert_str(fixture["source"]["file"]).is_equal("ONWIN.EXE")
	assert_int(int(fixture["source"]["ds_offset"])).is_equal(0x22BE)
	assert_int(int(fixture["source"]["file_offset"])).is_equal(0x3C200 + 0x22BE)
	assert_int(int(fixture["source"]["size"])).is_equal(TriggerTable.SIZE)
	assert_int(String(fixture["sha256"]).length()).is_equal(64)


func test_the_table_encodes_to_the_hash_of_the_original() -> void:
	if DELIBERATE_TABLE_CHANGE != "":
		return
	var table := Catalog.trigger_table()
	var messages := table.problems()
	assert_array(messages).override_failure_message("the table does not fit the original's: %s" % "\n".join(messages)).is_empty()
	var bytes := table.encode()
	assert_int(bytes.size()).is_equal(TriggerTable.SIZE)
	var text := "the trigger table differs from the original (edited on purpose? set DELIBERATE_TABLE_CHANGE); %s to see which entry" % NEED_THE_IMPORTER
	var original := _original_bytes()
	if not original.is_empty():
		text = "the trigger table differs from the original: %s (edited on purpose? set DELIBERATE_TABLE_CHANGE)" % TriggerTable.first_difference(original, bytes)
	assert_str(FixtureHash.sha256_hex(bytes)).override_failure_message(text).is_equal(_fixture()["sha256"])


# --- what the original bytes show (need the importer's raw file) ------------------------------------------------

func test_the_table_matches_the_original_byte_for_byte() -> void:
	var original := _original_bytes()
	if original.is_empty():
		prints("SKIPPED: %s is missing; %s" % [ORIGINAL_BYTES, NEED_THE_IMPORTER])
		return
	assert_int(original.size()).is_equal(TriggerTable.SIZE)
	if DELIBERATE_TABLE_CHANGE != "":
		return
	assert_str(TriggerTable.first_difference(original, Catalog.trigger_table().encode())).is_empty()


# --- a deliberately edited table gives a readable message --------------------------------------------------------

func test_an_edited_entry_is_named() -> void:
	var original := Catalog.trigger_table().encode()
	var table := _copy()
	table.table[(12 * TriggerTable.LEVELS + 2) * TriggerTable.PICKS + 1] += 1
	assert_str(TriggerTable.first_difference(original, table.encode())).starts_with("first difference at byte 0x").contains("(slot 12, educational level 2, pick 1)")
	assert_str(TriggerTable.first_difference(original, original)).is_empty()
	assert_str(TriggerTable.first_difference(original, PackedByteArray())).contains("0 bytes")
	assert_str(TriggerTable.field_at(TriggerTable.SIZE - 1)).is_equal("slot 62, educational level 3, pick 1")


# --- what does not fit is refused, in words ---------------------------------------------------------------------

func test_a_table_of_the_wrong_size_is_refused() -> void:
	var table := _copy()
	table.table.resize(TriggerTable.SIZE - 2)
	assert_str("\n".join(table.problems())).contains("table: 502 bytes, but the original has 504 (63 slots x 4 levels x 2 picks)")
	assert_int(table.encode().size()).is_equal(0)
