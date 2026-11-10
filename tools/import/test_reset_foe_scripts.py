"""pytest checks of reset_foe_scripts.py: it restores the original script fields and touches nothing else. The original script
bytes are the importer's (git-ignored, hash-checked against the committed foe_scripts.json): the tests that need them skip
without them."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import foe_script
import reset_foe_scripts as reset
from common import sector_file

needs_scripts = pytest.mark.skipif(not foe_script.RAW_FIXTURE.exists(),
                                   reason="run the importer on your copy of the game (needs %s)" % foe_script.RAW_FIXTURE)


def _annotations(n: int) -> dict:
    """Sector n's stored label names and comments: the committed files are written WITH them (a designer's rename of
    an entry label is in the .tres too), so a reset that should give the committed text back needs them as well."""
    return reset.foe_annotations.for_sector(reset.foe_annotations.load(), n)


def _copy(tmp_path: Path, n: int) -> tuple[Path, str, str]:
    """Copies sector n (.tres and .foe) into tmp_path; returns the .tres path and both original texts."""
    original = sector_file(n, "tres").read_text()
    script = sector_file(n, "foe").read_text()
    copy = sector_file(n, "tres", tmp_path)
    copy.parent.mkdir(exist_ok=True)
    copy.write_text(original)
    copy.with_suffix(".foe").write_text(script)
    return copy, original, script


@needs_scripts
@pytest.mark.parametrize("n", [0, 3, 31])
def test_an_edited_sector_is_restored_byte_for_byte(tmp_path, n):
    copy, original, script = _copy(tmp_path, n)
    # a comment line and a changed instruction in the script, a changed label in the .tres
    edited_script = '; designer says "hi" \\ ok\n' + script.replace("    Wait_Next_Tick\n", "    Hide_Foe\n", 1)
    copy.with_suffix(".foe").write_text(edited_script)
    copy.write_text(original.replace('hit_label = "', 'hit_label = "x', 3))
    assert edited_script != script
    assert reset.reset_sector(copy, reset.load_originals()[n], _annotations(n)) is True
    assert copy.read_text() == original
    assert copy.with_suffix(".foe").read_text() == script
    assert reset.reset_sector(copy, reset.load_originals()[n], _annotations(n)) is False


@needs_scripts
def test_a_missing_foe_file_is_created(tmp_path):
    copy, _original, script = _copy(tmp_path, 5)
    copy.with_suffix(".foe").unlink()
    assert reset.reset_sector(copy, reset.load_originals()[5], _annotations(5)) is True
    assert copy.with_suffix(".foe").read_text() == script


@needs_scripts
def test_every_sector_reset_is_a_no_op_on_the_committed_files():
    store = reset.foe_annotations.load()            # a reset writes the stored names and comments too
    for entry in reset.load_originals():
        n = entry["index"]
        old = sector_file(n, "tres").read_text()
        annotations = reset.foe_annotations.for_sector(store, n)
        assert reset.patch_text(old, entry, annotations) == old
        source, _labels = reset.original_fields(entry, annotations)
        assert sector_file(n, "foe").read_bytes() == source.encode("utf-8")


@needs_scripts
def test_run_changes_only_the_named_sectors(tmp_path):
    for n in (1, 2):
        copy, original, _script = _copy(tmp_path, n)
        copy.write_text(original.replace('ink_label = "', 'ink_label = "x', 1))
        copy.with_suffix(".foe").write_text("; edited\n")
    reset.run([1], sector_dir=tmp_path)
    assert sector_file(1, "tres", tmp_path).read_text() == sector_file(1, "tres").read_text()
    assert sector_file(1, "foe", tmp_path).read_text() == sector_file(1, "foe").read_text()
    assert 'ink_label = "x' in sector_file(2, "tres", tmp_path).read_text()
    assert sector_file(2, "foe", tmp_path).read_text() == "; edited\n"


# ---- --records: the creatures' record fields ----

needs_records = pytest.mark.skipif(not reset.foe_record.RAW_FIXTURE.exists() or not foe_script.RAW_FIXTURE.exists(),
                                   reason="run the importer on your copy of the game (needs %s and %s)" % (reset.foe_record.RAW_FIXTURE, foe_script.RAW_FIXTURE))


@needs_scripts
def test_the_committed_creature_records_hash_to_the_committed_fixture():
    """No original bytes needed: the record fields of the committed .tres, with the script fixture's entry points."""
    hashes = {e["index"]: [f["sha256"] for f in e["foes"]]
              for e in reset.json.loads(reset.foe_record.HASH_FIXTURE.read_text())["sectors"]}
    for entry in reset.load_originals():
        assert reset.record_hashes(sector_file(entry["index"], "tres").read_text(), entry) == hashes[entry["index"]]


@needs_records
@pytest.mark.parametrize("n", [0, 7, 31])
def test_edited_records_are_restored_and_the_script_is_not_touched(tmp_path, n):
    copy, original, script = _copy(tmp_path, n)
    head, foes = original.split('id="Foe_', 1)                                   # (the pieces before it have a pos too)
    edited = head + 'id="Foe_' + foes.replace("pos = Vector2i(", "pos = Vector2i(2", 1).replace("damage = ", "damage = 1", 1)
    edited = edited.replace("dormant = false", "dormant = true", 1).replace("flip = false", "flip = true", 1)
    edited = edited.replace('hit_label = "', 'hit_label = "mine_', 1)                     # a label: not the record reset's business
    edited = edited.replace('ink_label = "foe0_ink"\n', 'ink_label = "foe0_ink"\nruntime_state = PackedByteArray(1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)\n', 1)
    copy.write_text(edited)
    copy.with_suffix(".foe").write_text("; mine\n")
    entry = reset.load_originals()[n]
    records = reset.load_original_records()[n]
    assert reset.record_hashes(edited, entry) != [h for _r, h in records]
    # patch_records_text alone puts the record fields back and keeps the changed label
    patched = reset.patch_records_text(edited, [r for r, _h in records])
    assert reset.record_hashes(patched, entry) == [h for _r, h in records]
    assert 'hit_label = "mine_' in patched
    # reset_sector with records also restores the labels and the script
    assert reset.reset_sector(copy, entry, _annotations(n), records) is True
    assert copy.read_text() == original
    assert copy.with_suffix(".foe").read_text() == script


@needs_records
def test_every_record_reset_is_a_no_op_on_the_committed_files():
    for n, records in reset.load_original_records().items():
        old = sector_file(n, "tres").read_text()
        assert reset.patch_records_text(old, [r for r, _h in records]) == old, n


@needs_records
def test_a_different_number_of_creatures_is_refused(tmp_path):
    _copy_path, original, _script = _copy(tmp_path, 2)
    records = reset.load_original_records()[2]
    with pytest.raises(ValueError, match="creatures"):
        reset.patch_records_text(original, [r for r, _h in records][:-1])


@needs_records
def test_original_records_that_do_not_match_the_committed_hash_are_refused(tmp_path):
    raw = reset.json.loads(reset.foe_record.RAW_FIXTURE.read_text())
    first = raw["sectors"][0]["records_hex"][0]
    raw["sectors"][0]["records_hex"][0] = first[:-2] + ("00" if first[-2:] != "00" else "01")
    patched = tmp_path / "foe_records.json"
    patched.write_text(reset.json.dumps(raw))
    with pytest.raises(ValueError, match="different version or patched"):
        reset.load_original_records(patched)


def test_missing_original_records_say_to_run_the_importer(tmp_path):
    with pytest.raises(ValueError, match="run the importer on your copy"):
        reset.run([3], sector_dir=tmp_path, records=True, record_raw=tmp_path / "foe_records.json")


def test_missing_original_scripts_say_to_run_the_importer(tmp_path):
    with pytest.raises(ValueError, match="run the importer on your copy"):
        reset.load_originals(tmp_path / "foe_scripts.json")
    with pytest.raises(ValueError, match="run the importer on your copy"):
        reset.run([3], sector_dir=tmp_path, raw=tmp_path / "foe_scripts.json")


def test_whether_a_sector_is_original_needs_only_the_committed_hashes():
    assert reset.original_sectors() == list(range(32))
    assert reset.refuse_new_sectors([0, 31]) == ""
    assert "sector 32 has no original script" in reset.refuse_new_sectors([32])


@needs_scripts
def test_original_scripts_that_do_not_match_the_committed_hash_are_refused(tmp_path):
    raw = reset.json.loads(foe_script.RAW_FIXTURE.read_text())
    first = raw["sectors"][4]["script_hex"]
    raw["sectors"][4]["script_hex"] = first[:-2] + ("00" if first[-2:] != "00" else "01")
    patched = tmp_path / "foe_scripts.json"
    patched.write_text(reset.json.dumps(raw))
    with pytest.raises(ValueError, match="sector 4.*different version or patched"):
        reset.load_originals(patched)
