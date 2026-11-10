"""Checks of the dev pack (godot/packs/dev) against its inventory and of the generator.

    uv run pytest tools/dev_pack -q

The inventory (inventory.json) is the list of files a dev pack must have: one per file of the legacy pack. These tests run on a checkout
without the legacy pack; the ones marked `legacy` also compare with its file list and check that nothing was copied from it.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import pytest
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

import dev_pictures
import dev_problems
import dev_sectors
import devlib
import inventory
import make_dev_pack

DEV = devlib.DEV
INV = inventory.load()


def test_every_file_of_the_inventory_is_in_the_pack():
    missing = [f for f in INV["files"] if not (DEV / f).is_file()]
    assert not missing, "%d files are missing, for example %s" % (len(missing), missing[:3])


def test_the_audio_files_of_the_inventory_are_in_the_pack():
    if not (DEV / "assets" / "audio").exists():
        pytest.skip("the audio is made by tools/dev_pack/audio.py")
    missing = [f for f in INV["audio"] if not (DEV / f).is_file()]
    assert not missing, "%d audio files are missing, for example %s" % (len(missing), missing[:3])


def test_the_manifest_says_dev_is_complete():
    manifest = json.loads((DEV / "pack.json").read_text())
    assert manifest["id"] == "dev" and manifest["format"] == 1
    assert "base" not in manifest, "dev is a complete pack: it names no base"


def test_every_picture_has_its_sidecar_with_the_uid_of_its_path():
    wrong = []
    for png in sorted(DEV.rglob("*.png")):
        side = png.with_name(png.name + ".import")
        if not side.is_file():
            wrong.append(str(png) + ": no .import")
            continue
        uid = re.search(r'^uid="(uid://[^"]+)"', side.read_text(), re.MULTILINE)
        if not uid or uid.group(1) != devlib.uid_of(png.relative_to(DEV).as_posix()):
            wrong.append(str(png.relative_to(DEV)) + ": uid is not the one of its path")
    assert not wrong, wrong[:3]


def test_pictures_have_the_size_the_generator_specifies():
    wrong = []
    for rel in INV["files"]:
        if rel.endswith(".png"):
            _kind, w, h = dev_pictures.spec(rel)
            with Image.open(DEV / rel) as img:
                if img.size != (w, h):
                    wrong.append("%s is %s, the spec says %s" % (rel, img.size, (w, h)))
    assert not wrong, wrong[:3]


def test_backgrounds_are_640_by_400():
    for rel in INV["files"]:
        if rel.startswith("assets/backgrounds/"):
            with Image.open(DEV / rel) as img:
                assert img.size == (640, 400), rel


def test_sprite_sizes_are_even_so_the_sprite_tables_can_hold_them():
    for rel in INV["files"]:
        if rel.startswith("assets/sprites/") and rel.endswith(".png"):
            with Image.open(DEV / rel) as img:
                assert img.size[0] % 2 == 0 and img.size[1] % 2 == 0, rel


def test_every_resource_a_file_of_the_pack_points_at_is_there():
    missing = []
    for tres in sorted(DEV.rglob("*.tres")):
        for target in re.findall(r'path="(res://packs/dev/[^"]+)"', tres.read_text()):
            if not (DEV / target.removeprefix(devlib.DEV_RES)).is_file():
                missing.append("%s -> %s" % (tres.relative_to(DEV), target))
    assert not missing, missing[:3]


def test_nothing_in_the_pack_points_at_the_legacy_pack():
    offenders = [str(p.relative_to(DEV)) for p in DEV.rglob("*.tres") if "packs/legacy" in p.read_text()]
    assert not offenders, offenders[:3]


def test_the_generator_makes_the_committed_pack_again():
    """Idempotent: running it changes no file (so the committed pack is what the generator makes; a hand edit is the author's to keep
    by changing the generator too). Audio is not part of this test."""
    devlib.Stats.written = devlib.Stats.unchanged = 0
    assert make_dev_pack.main(["--only", "pictures,data"]) == 0
    assert devlib.Stats.written == 0, "the generator rewrote %d files: commit them, or fix the generator" % devlib.Stats.written


def test_the_text_tables_hold_the_ids_of_the_inventory():
    for table, ids in INV["text_tables"].items():
        text = (DEV / "data" / "problems" / (table + ".tres")).read_text()
        assert inventory.table_ids(text) == ids, table


def test_every_text_says_its_registry_name_or_its_number():
    names = json.loads((devlib.GODOT / "names" / "original.json").read_text())["names"]["text"]
    by_number = {n: name for name, n in names.items()}
    text = (DEV / "data" / "problems" / "ui_strings.tres").read_text()
    first = INV["text_tables"]["ui_strings"][0]
    assert '%d: "%s"' % (first, by_number.get(first, "text_%d" % first)) in text


def test_there_are_34_problem_types_with_records_at_every_level():
    for t in range(34):
        text = (DEV / "data" / "problems" / ("problem_type_%02d.tres" % t)).read_text()
        levels_match = re.search(r"record_levels = PackedInt32Array\(([^)]*)\)", text)
        assert levels_match is not None
        levels = levels_match.group(1).split(", ")
        missing = {str(level) for level in dev_problems.NO_RECORDS.get(t, ())}          # (a type may lack a level: dev_problems.NO_RECORDS)
        assert {"0", "1", "2", "3"} - missing <= set(levels), t
        assert not missing & set(levels), t
        assert "id = %d\n" % t in text


# --- dev_tour ------------------------------------------------------------------------------------------------------------

def sector_text(index: int) -> str:
    return (DEV / dev_sectors.sector_dir(index) / ("sector_%02d.tres" % index)).read_text()


def test_dev_tour_lists_sectors_0_to_3_and_the_finale_4():
    text = (DEV / "data" / "campaigns" / "dev_tour.tres").read_text()
    assert "sectors = PackedInt32Array(0, 1, 2, 3)" in text and "finales = PackedInt32Array(4)" in text and 'id = &"dev_tour"' in text


@pytest.mark.parametrize("index", range(5))
def test_a_dev_tour_sector_has_its_files_its_canister_and_a_chain_of_screens(index):
    base = DEV / dev_sectors.sector_dir(index)
    assert (base / ("sector_%02d.foe" % index)).is_file()
    for m in range(12):
        tiles_match = re.search(r"tiles = PackedByteArray\(([^)]*)\)", (base / ("screen_%02d.tres" % m)).read_text())
        assert tiles_match is not None
        tiles = tiles_match.group(1).split(", ")
        assert len(tiles) == 38 * 18
    text = sector_text(index)
    assert text.count("is_canister = true") == 1, "exactly one canister, and it is piece 0"
    assert text.index("is_canister = true") < text.index("is_canister = false")
    assert "neighbors_right = PackedInt32Array(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, -1)" in text


def test_a_creature_names_labels_its_script_has():
    for index in range(5):
        script = (DEV / dev_sectors.sector_dir(index) / ("sector_%02d.foe" % index)).read_text()
        for label in re.findall(r'(?:start|hit|ink)_label = "([^"]+)"', sector_text(index)):
            assert label + ":" in script, (index, label)


def test_a_new_sector_is_made_by_the_generator_in_a_few_lines(tmp_path, monkeypatch):
    """What tools/dev_pack/README.md says: standard_sector(...) then write_sector; here into a temporary pack."""
    monkeypatch.setattr(dev_sectors, "DEV", tmp_path)
    spec = dev_sectors.standard_sector(100, 2, creatures=2, comment="A test sector.")
    spec.pieces.append((10, 300, 100))
    assert dev_sectors.write_sector(spec) == 14
    assert (tmp_path / "data/sectors/sector_100/sector_100.tres").is_file()
    assert "index = 100" in (tmp_path / "data/sectors/sector_100/sector_100.tres").read_text()


# --- with the legacy pack -----------------------------------------------------------------------------------------------

@pytest.mark.legacy
def test_the_inventory_is_the_legacy_packs_file_list():
    legacy = devlib.LEGACY
    everything = ["pack.json"] + inventory._tree(legacy, "assets") + inventory._tree(legacy, "data") + inventory._tree(legacy, "midi")
    files = sorted(f for f in everything if not inventory.is_audio(f) and not f.startswith(("data/sectors/", "data/campaigns/")))
    assert files == INV["files"]
    assert sorted(f for f in everything if inventory.is_audio(f)) == INV["audio"]
    for table, ids in INV["text_tables"].items():
        assert inventory.table_ids((legacy / "data" / "problems" / (table + ".tres")).read_text()) == ids


@pytest.mark.legacy
def test_nothing_of_the_original_was_copied_into_the_pack():
    """No dev file is byte for byte a legacy file of the same name (a copied picture, table or text). The exception is the problem-art
    index: it lists picture ids, which are names (like the file names), and has no content of the original."""
    same = [f for f in INV["files"] if f not in ("pack.json", "data/problems/problem_art_index.json") and (devlib.LEGACY / f).is_file() and (DEV / f).read_bytes() == (devlib.LEGACY / f).read_bytes()]
    assert not same, same[:3]
