"""pytest checks of sprite_meta.py: the sprite size and hit rectangle tables decoded from the RAW NEP.DLL resources and
encoded again are the original byte for byte for all 9 sets, the committed hash fixture matches, and the zero tail holds."""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common
import sprite_meta as sm
import step_sprites


@pytest.mark.legacy
def test_every_set_decodes_and_encodes_to_the_original_bytes():
    assert len(sm.SETS) == 9
    for name, ids, count in sm.SETS:
        tables = sm.original_tables(ids)
        assert all(len(t) == sm.RESOURCE_SIZE for t in tables)
        assert sm.encode_set(sm.decode_set(tables, count)) == tables, name


@pytest.mark.legacy
def test_nothing_but_zeros_follows_the_used_sprites():
    for name, ids, count in sm.SETS:
        widths, heights, rects = sm.original_tables(ids)
        assert widths[count - 1] and heights[count - 1] and rects[8 * count - 4:8 * count], name   # the last used entry is not empty
        assert not any(widths[count:]) and not any(heights[count:]) and not any(rects[8 * count:]), name


@pytest.mark.legacy
def test_the_committed_fixture_holds_the_hashes_and_no_bytes():
    fixture = json.loads(sm.HASH_FIXTURE.read_text())
    assert sm.HASH_FIXTURE.read_text() == sm.build_hash_fixture()
    assert [s["name"] for s in fixture["sets"]] == [name for name, _, _ in sm.SETS]
    for entry, (name, ids, count) in zip(fixture["sets"], sm.SETS):
        assert list(entry["tables"]) == list(sm.KINDS)
        for kind, real_id in zip(sm.KINDS, ids):
            table = entry["tables"][kind]
            raw = sm.original_resource(real_id)
            assert table["source"] == {"file": "NEP.DLL", "real_id": real_id, "extracted": sm.extracted_name(real_id)}
            assert table["offset"] == 0 and table["size"] == sm.RESOURCE_SIZE and table["sha256"] == common.sha256_hex(raw)
            assert set(table) == {"source", "offset", "size", "sha256"}
            assert raw[:8].hex() not in json.dumps(table)


@pytest.mark.skipif(not sm.RAW_FIXTURE.exists(), reason="run the importer on your copy of the game (needs %s)" % sm.RAW_FIXTURE)
def test_the_raw_fixture_is_the_table_bytes_and_is_not_committed():
    raw_fixture = json.loads(sm.RAW_FIXTURE.read_text())
    for entry, (name, ids, count) in zip(raw_fixture["sets"], sm.SETS):
        assert entry["name"] == name
        for kind, real_id in zip(sm.KINDS, ids):
            assert bytes.fromhex(entry[kind + "_hex"]) == sm.original_resource(real_id)
    assert "godot/tests/fixtures/original/" in (common.ROOT / ".gitignore").read_text()


@pytest.mark.legacy
def test_the_set_files_are_what_the_raw_tables_build():
    for name, ids, count in sm.SETS:
        text = (common.PACK_DATA / "sprite_meta" / ("sprite_meta_%s.tres" % name)).read_text()
        assert text == step_sprites.meta_tres(name, ids, count), name


def test_the_resources_are_512_bytes_in_the_dll_itself_and_the_extracted_files_are_that_without_the_zero_tail():
    """The extractor cuts trailing zeros; this reads NEP.DLL from the CD image NEPTUNE.ISO (skipped without it) and compares."""
    try:
        sys.path.insert(0, str(common.ROOT / "tools" / "analysis"))
        import neptune_data
    except FileNotFoundError as e:          # no NEPTUNE.ISO: the importer itself never needs the game's files
        pytest.skip("needs the game's CD image (%s)" % e)
    for name, ids, count in sm.SETS:
        for real_id in ids:
            full = neptune_data.RES[real_id]
            assert len(full) == sm.RESOURCE_SIZE
            assert full == sm.original_resource(real_id)


@pytest.mark.legacy
def test_the_encoder_refuses_what_the_tables_cannot_hold():
    _name, ids, count = sm.SETS[1]
    meta = sm.decode_set(sm.original_tables(ids), count)
    for change in ({"sizes": [(17, 2)] + meta["sizes"][1:]}, {"sizes": [(2, 512)] + meta["sizes"][1:]},
                   {"sizes": [(-2, 2)] + meta["sizes"][1:]},
                   {"hit_rects": [(0, 0, 0, 3)] + meta["hit_rects"][1:]}, {"hit_rects": [(0, 0, 600, 2)] + meta["hit_rects"][1:]},
                   {"hit_rects_flipped": meta["hit_rects_flipped"][:-1]},
                   {"sizes": [(2, 2)] * 65, "hit_rects": [(0, 0, 2, 2)] * 65, "hit_rects_flipped": [(0, 0, 2, 2)] * 65}):
        with pytest.raises(ValueError):
            sm.encode_set({**meta, **change})
