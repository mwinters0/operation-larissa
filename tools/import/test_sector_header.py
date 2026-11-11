"""pytest checks of sector_header.py: the header decoded from the RAW sector resource and encoded again is the
original byte for byte for all 32 sectors, the committed hash fixture matches, and the stale / unused facts hold."""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common
import screen_record
import sector_header as sh
import step_sectors


def sectors() -> list[dict]:
    return common.load_json(common.TABLES / "sectors.json")


@pytest.mark.legacy
def test_every_header_decodes_and_encodes_to_the_original_bytes():
    assert len(sectors()) == 32
    for sec in sectors():
        raw = sh.original_resource(sec)
        assert len(raw) == sh.RESOURCE_SIZE
        assert sh.encode_header(sh.decode_header(raw)) == raw[:sh.HEADER_SIZE], sec["index"]


@pytest.mark.legacy
def test_the_committed_fixture_holds_the_hashes_and_no_bytes():
    fixture = json.loads(sh.HASH_FIXTURE.read_text())
    assert [e["index"] for e in fixture["sectors"]] == list(range(32))
    assert sh.HASH_FIXTURE.read_text() == sh.build_hash_fixture(sectors())
    for sec, entry in zip(sectors(), fixture["sectors"]):
        raw = sh.original_resource(sec)
        assert entry["source"] == sec["source"] and entry["offset"] == 0 and entry["size"] == sh.HEADER_SIZE
        assert entry["header_sha256"] == common.sha256_hex(raw[:sh.HEADER_SIZE])
        assert entry["resource_sha256"] == common.sha256_hex(raw)
        assert set(entry) == {"index", "source", "offset", "size", "header_sha256", "resource_sha256"}
        assert raw[:8].hex() not in json.dumps(entry)


@pytest.mark.skipif(not sh.RAW_FIXTURE.exists(), reason="run the importer on your copy of the game (needs %s)" % sh.RAW_FIXTURE)
@pytest.mark.legacy
def test_the_raw_fixture_is_the_header_bytes_and_is_not_committed():
    raw_fixture = json.loads(sh.RAW_FIXTURE.read_text())
    for sec, entry in zip(sectors(), raw_fixture["sectors"]):
        assert bytes.fromhex(entry["header_hex"]) == sh.original_resource(sec)[:sh.HEADER_SIZE]
    ignored = (common.ROOT / ".gitignore").read_text()
    assert "godot/tests/fixtures/original/" in ignored


def test_the_hash_helper_is_sha256():
    assert common.sha256_hex(b"abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"


@pytest.mark.legacy
def test_the_header_agrees_with_the_converted_values_of_sectors_json():
    """The importer does not read sectors.json for the header; this only checks that the two readings agree."""
    for sec in sectors():
        h = sh.decode_header(sh.original_resource(sec))
        assert h["start_pos"] == (sec["start_x"], sec["start_y"]) and h["start_frame"] == sec["start_cell"]
        assert h["pieces"] == list(zip(sec["piece_screen"], sec["piece_x"], sec["piece_y"]))
        assert h["header_unused_3d"] == sec["hdr_unknown_0x3d"]
        for side in sh.SIDES:
            assert [v + 1 for v in h["neighbors"][side]] == sec["nbr"][side]


@pytest.mark.legacy
def test_only_sectors_6_and_22_have_stale_piece_entries_and_the_unused_bytes_come_in_two_groups():
    stale = {}
    for sec in sectors():
        h = sh.decode_header(sh.original_resource(sec))
        if h["stale_pieces"]:
            stale[sec["index"]] = h["stale_pieces"]
        used = sec["index"] <= 10 or 12 <= sec["index"] <= 24
        assert (h["header_unused_3d"], h["header_unused_40"], h["header_unused_41"]) == ((11, 0x48, 0) if used else (0, 0, 0))
    assert stale == {6: [(7, 4, 576, 176)], 22: [(9, 5, 464, 288)]}


def test_the_tail_after_the_last_record_is_zero_in_the_dll_itself():
    """The extractor cuts trailing zeros; this reads NEP.DLL from the CD image NEPTUNE.ISO (skipped without it) and compares."""
    try:
        sys.path.insert(0, str(common.ROOT / "tools" / "analysis"))
        import neptune_data
    except FileNotFoundError as e:          # no NEPTUNE.ISO: the importer itself never needs the game's files
        pytest.skip("needs the game's CD image (%s)" % e)
    for sec in sectors():
        full = neptune_data.get(neptune_data.SECTOR_TBL[sec["index"]])
        assert len(full) == sh.RESOURCE_SIZE == sec["source"]["size"]
        assert full == sh.original_resource(sec)
        assert not any(full[screen_record.HEADER_SIZE + 12 * screen_record.RECORD_SIZE:])


@pytest.mark.legacy
def test_the_sector_files_are_what_the_raw_header_builds():
    for sec in sectors():
        resource, _ = step_sectors.build_sector(sec, None)
        h = sh.decode_header(sh.original_resource(sec))
        assert "header_unused_3d = %d" % h["header_unused_3d"] in resource
        assert "log_entry_id" not in resource
        assert ("stale_pieces" in resource) == bool(h["stale_pieces"])


@pytest.mark.legacy
def test_the_encoder_refuses_what_the_header_cannot_hold():
    h = sh.decode_header(sh.original_resource(sectors()[0]))
    for change in ({"start_pos": (3, 4)}, {"start_pos": (-2, 4)}, {"start_pos": (2 * 65536, 4)},
                   {"start_frame": 65536}, {"header_unused_3d": 256}, {"header_unused_41": -1},
                   {"pieces": [(256, 0, 0)]}, {"pieces": [(1, 1, 0)]}, {"pieces": [(1, 0, 0)] * 12},
                   {"neighbors": {**h["neighbors"], "left": [12] + [-1] * 11}},
                   {"neighbors": {**h["neighbors"], "up": [-2] + [-1] * 11}},
                   {"stale_pieces": [(11, 0, 0, 0)]}):
        with pytest.raises(ValueError):
            sh.encode_header({**h, **change})
