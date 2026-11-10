"""pytest checks of reset_screens.py and screen_record.py: the committed screen files are exactly what the original records
build, the committed hash fixture matches, a reset restores an edited screen byte for byte, and it touches nothing else. The
tests that need the importer-written original bytes (git-ignored) skip without them."""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common
import reset_screens as reset
import screen_record

needs_original = pytest.mark.skipif(not screen_record.RAW_FIXTURE.exists(),
                                    reason="run the importer on your copy of the game (needs %s)" % screen_record.RAW_FIXTURE)


@pytest.mark.legacy
def test_the_hash_fixture_holds_provenance_and_hashes_and_matches_the_game_files():
    """No importer-written bytes needed: the committed fixture is what the raw sector resources hash to."""
    text = screen_record.HASH_FIXTURE.read_text()
    sectors = common.load_json(common.DOCS_DATA / "sectors.json")
    assert text == screen_record.build_hash_fixture(sectors)
    parsed = json.loads(text)
    assert parsed["size"] == 0x500 and [e["index"] for e in parsed["sectors"]] == list(range(32))
    for sec, entry in zip(sectors, parsed["sectors"]):
        assert entry["source"] == sec["source"] and len(entry["screens"]) == 12
        for k, row in enumerate(entry["screens"]):
            assert set(row) == {"screen", "offset", "sha256"}              # no bytes, no per-field values
            assert row["offset"] == screen_record.record_offset(k) and len(row["sha256"]) == 64
            assert row["sha256"] == common.sha256_hex(screen_record.original_record(sec, k))


@needs_original
def test_the_raw_fixture_is_the_records_and_is_not_committed():
    sectors = common.load_json(common.DOCS_DATA / "sectors.json")
    assert screen_record.RAW_FIXTURE.read_text() == screen_record.build_raw_fixture(sectors)
    assert "godot/tests/fixtures/original/" in (common.ROOT / ".gitignore").read_text()


@needs_original
def test_every_committed_screen_file_is_what_the_original_records_build():
    records = reset.load_originals()
    assert len(records) == 32 * 12
    for (sector, screen), record in records.items():
        path = screen_record.screen_path(sector, screen)
        assert path.read_text() == screen_record.build_screen_from_record(record, sector, screen), path


@needs_original
def test_the_raw_fixture_matches_sectors_json_and_the_decoded_fields():
    originals = reset.load_originals()
    for sec in common.load_json(common.DOCS_DATA / "sectors.json"):
        for k, sc in enumerate(sec["screens"]):
            record = screen_record.original_record(sec, k)
            assert record == originals[(sec["index"], k)]
            assert sc["record_offset"] == screen_record.record_offset(k) == 0x72 + k * 0x500
            decoded = screen_record.decode_record(record)
            assert decoded["tiles"] == sc["tiles"]
            assert decoded["used"] == sc["used"]
            assert [bytes.fromhex(h) for h in sc["anim_decos"]] == decoded["anim_decos"]
            assert [tuple(t) for t in sc["math_triggers"]] == decoded["math_triggers"]
            for name in ("bg_decos", "mid_decos", "fg_decos"):
                assert [tuple(d) for d in sc[name]] == decoded[name]


@needs_original
def test_seven_records_have_stale_bytes_after_the_lists():
    stale = [k for k, record in reset.load_originals().items() if screen_record.decode_record(record)["stale_bytes"]]
    assert len(stale) == 7


@needs_original
@pytest.mark.parametrize("sector,screen", [(0, 0), (0, 6), (16, 11), (31, 3)])
def test_an_edited_screen_is_restored_byte_for_byte(tmp_path, sector, screen):
    original = screen_record.screen_path(sector, screen).read_text()
    copy = tmp_path / ("sector_%02d" % sector) / ("screen_%02d.tres" % screen)
    copy.parent.mkdir()
    copy.write_text(original.replace("pos = Vector2i(", "pos = Vector2i(2", 1).replace("tiles = PackedByteArray(", "tiles = PackedByteArray(9, "))
    assert copy.read_text() != original
    assert reset.reset_screen(copy, sector, screen, reset.load_originals()[(sector, screen)]) is True
    assert copy.read_text() == original
    assert reset.reset_screen(copy, sector, screen, reset.load_originals()[(sector, screen)]) is False


@needs_original
def test_run_changes_only_the_named_screens(tmp_path):
    for m in (1, 2):
        copy = tmp_path / "sector_03" / ("screen_%02d.tres" % m)
        copy.parent.mkdir(exist_ok=True)
        copy.write_text("edited\n")
    reset.run([(3, 1)], sector_dir=tmp_path)
    assert (tmp_path / "sector_03" / "screen_01.tres").read_text() == screen_record.screen_path(3, 1).read_text()
    assert (tmp_path / "sector_03" / "screen_02.tres").read_text() == "edited\n"


def test_targets_are_parsed_and_checked():
    assert reset.parse_target("3") == [(3, m) for m in range(12)]
    assert reset.parse_target("3:5") == [(3, 5)]
    for bad in ("32", "3:12", "x", "3:y"):
        with pytest.raises(ValueError):
            reset.parse_target(bad)


def test_missing_original_records_say_to_run_the_importer(tmp_path):
    with pytest.raises(ValueError, match="run the importer on your copy"):
        reset.load_originals(tmp_path / "screens.json")
    with pytest.raises(ValueError, match="run the importer on your copy"):
        reset.run([(3, 1)], sector_dir=tmp_path, raw=tmp_path / "screens.json")


@needs_original
def test_original_records_that_do_not_match_the_committed_hash_are_refused(tmp_path):
    raw = json.loads(screen_record.RAW_FIXTURE.read_text())
    row = raw["sectors"][3]["screens"][5]
    row["record_hex"] = row["record_hex"][:2] + ("00" if row["record_hex"][2:4] != "00" else "01") + row["record_hex"][4:]
    patched = tmp_path / "screens.json"
    patched.write_text(json.dumps(raw))
    with pytest.raises(ValueError, match="sector 3 screen 5.*different version or patched"):
        reset.load_originals(patched)
