"""pytest checks of ds_tables.py: the trigger table and the default educational levels, the committed hash fixtures, and
(with a CD image) that the exported JSON is what the program's data segment holds."""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common
import ds_tables as ds
import step_sectors


@pytest.mark.legacy
def test_the_trigger_table_is_63_slots_of_4_levels_of_2_picks_and_every_type_exists():
    raw = ds.trigger_table()
    assert len(raw) == 63 * 4 * 2 == 504
    assert max(raw) <= 33                                   # problem types 0-33
    assert list(raw[:8]) == [0] * 8 and list(raw[8:16]) == [1] * 8      # slot 0: the combination lock, slot 1: the data canister


@pytest.mark.legacy
def test_the_default_levels_are_the_ten_of_design_3_8():
    assert list(ds.default_edu_levels()) == [0, 0, 1, 1, 1, 2, 2, 2, 3, 3]


@pytest.mark.legacy
def test_the_committed_fixtures_hold_the_hashes_and_no_bytes():
    for path, build, raw, table in ((ds.TRIGGER_HASH_FIXTURE, ds.build_trigger_hash_fixture, ds.trigger_table(), ds.TRIGGER_TABLE),
                                    (ds.ZONES_HASH_FIXTURE, ds.build_zones_hash_fixture, ds.default_edu_levels(), ds.DEFAULT_EDU)):
        assert path.read_text() == build()
        fixture = json.loads(path.read_text())
        assert set(fixture) == {"comment", "source", "sha256"}
        assert fixture["source"] == {"file": "ONWIN.EXE", "ds_offset": table["ds_offset"],
                                     "file_offset": 0x3C200 + table["ds_offset"], "size": table["size"]} and table["size"] == len(raw)
        assert fixture["sha256"] == common.sha256_hex(raw)
        assert raw[:8].hex() not in path.read_text()


@pytest.mark.skipif(not ds.TRIGGER_RAW_FIXTURE.exists(), reason="run the importer on your copy of the game (needs %s)" % ds.TRIGGER_RAW_FIXTURE)
@pytest.mark.legacy
def test_the_raw_fixtures_are_the_table_bytes_and_are_not_committed():
    assert bytes.fromhex(json.loads(ds.TRIGGER_RAW_FIXTURE.read_text())["hex"]) == ds.trigger_table()
    assert bytes.fromhex(json.loads(ds.ZONES_RAW_FIXTURE.read_text())["hex"]) == ds.default_edu_levels()
    assert "godot/tests/fixtures/original/" in (common.ROOT / ".gitignore").read_text()


@pytest.mark.legacy
def test_the_tres_files_are_what_the_tables_build():
    assert (common.PACK_DATA / "trigger_table.tres").read_text() == step_sectors.build_trigger_table()
    assert (common.PACK_DATA / "zones.tres").read_text() == step_sectors.build_zones()


@pytest.mark.legacy
def test_a_finale_has_the_last_zones_levels():
    """The game has no row for the finales and uses the last zone's level (Progression.default_edu_level)."""
    import re
    text = step_sectors.build_zones()
    voyager = list(map(int, re.findall(r"default_edu_level_voyager = (\d)", text)))
    expert = list(map(int, re.findall(r"default_edu_level_expert = (\d)", text)))
    assert voyager == [0, 0, 1, 1, 1, 1, 1] and expert == [2, 2, 2, 3, 3, 3, 3]


def test_the_exported_tables_are_what_the_program_holds():
    """tools/analysis/export_json.py read them from ONWIN.EXE; this reads the CD image NEPTUNE.ISO (skipped without it)."""
    try:
        sys.path.insert(0, str(common.ROOT / "tools"))
        import gamefiles
        exe = gamefiles.read("ONWINCD/ONWIN.EXE")
    except FileNotFoundError as e:
        pytest.skip("needs the game's CD image (%s)" % e)
    for table, raw in ((ds.TRIGGER_TABLE, ds.trigger_table()), (ds.DEFAULT_EDU, ds.default_edu_levels())):
        at = ds.DS_FILE_OFFSET + table["ds_offset"]
        assert exe[at:at + table["size"]] == raw
