"""pytest checks of foe_record.py: the creature records decoded from the RAW foe buffers and encoded again are the
original bytes for all 640 creatures, the committed hash fixture matches, and the facts the format notes claim hold."""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common
import foe_record as fr
import foe_script
import step_sectors


def sectors() -> list[dict]:
    return common.load_json(common.TABLES / "sectors.json")


@pytest.mark.legacy
def test_every_record_decodes_and_encodes_to_the_original_bytes():
    total = 0
    for sec in sectors():
        records = fr.original_records(sec)
        assert len(records) == sec["foes"]["n"]
        for k, raw in enumerate(records):
            assert len(raw) == fr.RECORD_SIZE
            assert fr.encode_record(fr.decode_record(raw)) == raw, (sec["index"], k)
            total += 1
    assert total == 640


@pytest.mark.legacy
def test_the_raw_buffers_are_the_bytes_of_sectors_json():
    """sectors.json (tools/analysis/export_json.py) and the extracted files carry the same foe buffers."""
    for sec in sectors():
        assert fr.original_buffer(sec) == bytes.fromhex(sec["foe_script_bytes_hex"]), sec["index"]
        assert sec["foes"]["script_base"] == fr.record_offset(sec["foes"]["n"])


@pytest.mark.legacy
def test_the_records_agree_with_the_converted_values_of_sectors_json():
    """The importer does not read sectors.json for the records; this only checks that the two readings agree."""
    for sec in sectors():
        for r, j in zip(fr.decode_records(sec), sec["foes"]["records"]):
            assert (r["dormant"], r["hidden"], r["flip"]) == (bool(j["dormant"]), bool(j["hidden"]), bool(j["flip"]))
            assert r["pos"] == (j["x"], j["y"])
            for name in ("screen", "frame", "frame_min", "frame_max", "damage", "pc", "script_hit", "script_ink"):
                assert r[name] == j[name], (sec["index"], name)


@pytest.mark.legacy
def test_the_committed_fixture_holds_the_hashes_and_no_bytes():
    fixture = json.loads(fr.HASH_FIXTURE.read_text())
    assert fixture["size"] == fr.RECORD_SIZE
    assert [e["index"] for e in fixture["sectors"]] == list(range(32))
    assert fr.HASH_FIXTURE.read_text() == fr.build_hash_fixture(sectors())
    for sec, entry in zip(sectors(), fixture["sectors"]):
        assert entry["source"] == sec["foes"]["source"] and set(entry) == {"index", "source", "foes"}
        records = fr.original_records(sec)
        assert len(entry["foes"]) == len(records)
        for k, (row, raw) in enumerate(zip(entry["foes"], records)):
            assert row == {"offset": fr.record_offset(k), "sha256": common.sha256_hex(raw)}
            assert raw.hex() not in json.dumps(row)


@pytest.mark.skipif(not fr.RAW_FIXTURE.exists(), reason="run the importer on your copy of the game (needs %s)" % fr.RAW_FIXTURE)
@pytest.mark.legacy
def test_the_raw_fixture_is_the_record_bytes_and_is_not_committed():
    raw_fixture = json.loads(fr.RAW_FIXTURE.read_text())
    for sec, entry in zip(sectors(), raw_fixture["sectors"]):
        assert [bytes.fromhex(h) for h in entry["records_hex"]] == fr.original_records(sec)
    assert "godot/tests/fixtures/original/" in (common.ROOT / ".gitignore").read_text()


@pytest.mark.legacy
def test_the_flags_are_zero_or_one_and_the_run_time_state_is_zero_in_every_original():
    for sec in sectors():
        for raw in fr.original_records(sec):
            assert raw[0] in (0, 1) and raw[1] in (0, 1) and raw[8] in (0, 1)
            assert raw[fr.RUNTIME_STATE_AT:] == bytes(fr.RUNTIME_STATE_SIZE)


def test_the_foe_buffers_are_what_the_dll_holds():
    """The extractor cuts trailing zeros; this reads NEP.DLL from the CD image NEPTUNE.ISO (skipped without it) and compares."""
    try:
        sys.path.insert(0, str(common.ROOT / "tools" / "analysis"))
        import neptune_data
    except FileNotFoundError as e:          # no NEPTUNE.ISO: the importer itself never needs the game's files
        pytest.skip("needs the game's CD image (%s)" % e)
    for sec in sectors():
        src = sec["foes"]["source"]
        full = neptune_data.get(neptune_data.FOE_TBL[sec["index"]])
        assert (src["logical_id"], src["real_id"], src["size"]) == (neptune_data.FOE_TBL[sec["index"]],
                                                                      neptune_data.real(neptune_data.FOE_TBL[sec["index"]]), len(full))
        assert full.rstrip(b"\0") == fr.original_buffer(sec)


@pytest.mark.legacy
def test_the_sector_files_are_what_the_raw_records_build():
    for sec in sectors():
        resource, _ = step_sectors.build_sector(sec, None)
        assert resource.count("foe_data.gd") >= 1
        assert "runtime_state" not in resource            # all zero in the originals: nothing stored
        assert foe_script.offsets_of(sec) == [(j["pc"], j["script_hit"], j["script_ink"]) for j in sec["foes"]["records"]]


@pytest.mark.legacy
def test_a_non_zero_run_time_state_is_written_to_the_sector_file(monkeypatch):
    sec = sectors()[0]
    real = fr.decode_records

    def with_state(s):
        records = real(s)
        records[2] = {**records[2], "runtime_state": bytes([0, 0, 7] + [0] * 13)}
        return records
    monkeypatch.setattr(fr, "decode_records", with_state)
    resource, _ = step_sectors.build_sector(sec, None)
    assert resource.count("runtime_state = PackedByteArray(0, 0, 7") == 1


@pytest.mark.legacy
def test_the_encoder_refuses_what_the_record_cannot_hold():
    r = fr.decode_record(fr.original_records(sectors()[0])[0])
    for change in ({"pos": (3, 4)}, {"pos": (-2, 4)}, {"pos": (2 * 65536, 4)}, {"screen": 256}, {"frame": -1},
                   {"frame_min": 256}, {"damage": 128}, {"damage": -129}, {"pc": 65536}, {"script_hit": -1},
                   {"runtime_state": b"\0" * 15}):
        with pytest.raises(ValueError):
            fr.encode_record({**r, **change})
    assert fr.encode_record({**r, "damage": -1})[0x0F] == 0xFF
