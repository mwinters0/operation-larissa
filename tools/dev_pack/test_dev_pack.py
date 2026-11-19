"""Checks of the dev pack (godot/packs/dev) against its inventory and of the generator.

    uv run pytest tools/dev_pack -q

The inventory (inventory.json) is the list of files and picture keys a dev pack must have: one per file of the legacy pack, and a row of `pictures.json` per key of its table. These tests run on a checkout
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

import asset_manifest
import dev_pictures
import dev_problems
import dev_sectors
import devlib
import inventory
import make_dev_pack

DEV = devlib.DEV
INV = inventory.load()


def table() -> dict:
    return json.loads((DEV / "pictures.json").read_text())["pictures"]


def test_every_file_of_the_inventory_is_in_the_pack():
    missing = [f for f in INV["files"] if not (DEV / f).is_file()]
    assert not missing, "%d files are missing, for example %s" % (len(missing), missing[:3])


def test_the_pictures_table_has_a_row_for_every_key_of_the_inventory():
    rows = table()
    assert set(rows) == set(INV["pictures"]) | set(INV["picture_aliases"])
    for key in INV["pictures"]:
        assert rows[key] == "assets/pictures/%s.png" % key and (DEV / rows[key]).is_file(), key
    for key, target in INV["picture_aliases"].items():
        assert rows[key] == {"alias": target}, key
        assert target in rows, "%s is an alias of %s, which has no row" % (key, target)


def test_a_picture_file_is_named_by_its_key_and_the_pack_holds_no_other():
    on_disk = {p.relative_to(DEV).as_posix() for p in DEV.rglob("*.png")}
    assert on_disk == {"assets/pictures/%s.png" % key for key in INV["pictures"]}
    assert sorted(p.name for p in (DEV / "assets").iterdir()) == ["audio", "pictures"], "the pictures are in assets/pictures/<kind>/<name>.png and nowhere else"
    assert sorted(p.name for p in (DEV / "assets" / "pictures").iterdir()) == ["background", "deco", "frame", "problem_art", "tile", "ui_picture"]


def test_every_picture_key_the_data_holds_is_a_row_of_the_table():
    rows = table()
    wrong = []
    for tres in sorted(DEV.rglob("*.tres")):
        text = tres.read_text()
        keys = re.findall(r'^key = "([^"]+)"', text, re.MULTILINE)
        for match in re.findall(r'^art_keys = PackedStringArray\(([^)]*)\)', text, re.MULTILINE):
            keys += re.findall(r'"([^"]+)"', match)
        for match in re.findall(r'^pictures = PackedStringArray\(([^)]*)\)', text, re.MULTILINE):
            keys += re.findall(r'"([^"]+)"', match)
        wrong += ["%s: %s is no row of pictures.json" % (tres.relative_to(DEV), k) for k in keys if k not in rows]
    assert not wrong, wrong[:3]


def test_every_row_of_the_table_is_used_by_the_data_or_asked_for_by_name():
    """A picture the pack draws is held by key in its data, or asked for by name: a registry name (`Assets.ui_picture`), a background by sector and screen,
    a picture key. The rows nothing in the data holds are the registry's (the engine looks them up by name), the backgrounds and the aliases of problem art."""
    held = set()
    for tres in DEV.rglob("*.tres"):
        text = tres.read_text()
        held.update(re.findall(r'^key = "([^"]+)"', text, re.MULTILINE))
        for match in re.findall(r'^(?:art_keys|pictures) = PackedStringArray\(([^)]*)\)', text, re.MULTILINE):
            held.update(re.findall(r'"([^"]+)"', match))
    names = json.loads((devlib.GODOT / "names" / "original.json").read_text())["names"]
    asked = {"ui_picture/" + n for n in names["ui_picture"]} | {"problem_art/" + n for n in names["problem_art"]}
    unused = [k for k in table() if k not in held and k not in asked and not k.startswith(("background/", "problem_art/pa_", "ui_picture/ui_", "frame/foe_z", "deco/deco_z"))]
    assert not unused, unused[:5]


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
    for key in INV["pictures"]:
        _kind, w, h = dev_pictures.spec(key)
        with Image.open(DEV / dev_pictures.rel_of(key)) as img:
            if img.size != (w, h):
                wrong.append("%s is %s, the spec says %s" % (key, img.size, (w, h)))
    assert not wrong, wrong[:3]


def test_backgrounds_are_640_by_400():
    for key in INV["pictures"]:
        if key.startswith("background/"):
            with Image.open(DEV / dev_pictures.rel_of(key)) as img:
                assert img.size == (640, 400), key


def test_sprite_sizes_are_even_so_the_sprite_tables_can_hold_them():
    for key in INV["pictures"]:
        if key.startswith("frame/"):
            with Image.open(DEV / dev_pictures.rel_of(key)) as img:
                assert img.size[0] % 2 == 0 and img.size[1] % 2 == 0, key


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
    files = sorted(f for f in everything if not inventory.is_audio(f) and not f.startswith(("assets/", "data/sectors/", "data/campaigns/"))
                   and f != "data/problems/problem_art_index.json")
    assert files == INV["files"]
    assert sorted(f for f in everything if inventory.is_audio(f)) == INV["audio"]
    pictures, aliases = inventory.pictures_of(asset_manifest.load(), INV["problem_art_index"])
    assert pictures == INV["pictures"] and aliases == INV["picture_aliases"]
    for table, ids in INV["text_tables"].items():
        assert inventory.table_ids((legacy / "data" / "problems" / (table + ".tres")).read_text()) == ids


@pytest.mark.legacy
def test_nothing_of_the_original_was_copied_into_the_pack():
    """No dev file is byte for byte a legacy file of the same name (a copied picture, table or text). The pictures are named by key in dev and by
    the importer's file names in legacy, so they are compared through the two tables. The sprite frames hold keys and nothing else, the same keys as the
    slot tables of the analysis make for both packs, so they are the same text."""
    same = [f for f in INV["files"] if f != "pack.json" and not f.startswith("data/sprite_frames/") and (devlib.LEGACY / f).is_file() and (DEV / f).read_bytes() == (devlib.LEGACY / f).read_bytes()]
    legacy_table = devlib.LEGACY / "pictures.json"
    if legacy_table.is_file():
        theirs = json.loads(legacy_table.read_text())["pictures"]
        same += [key for key, rel in table().items() if isinstance(rel, str) and isinstance(theirs.get(key), str)
                 and (DEV / rel).read_bytes() == (devlib.LEGACY / theirs[key]).read_bytes()]
    assert not same, same[:3]


def test_every_actor_a_dev_timeline_names_is_on_its_stage():
    """The pack check says it of any pack; this keeps the generator from writing a dev timeline for an actor its own stage lacks."""
    played_on: dict[str, list[str]] = {}
    for scene_name in ("logo", "news_cartoon", "title"):
        scene = (DEV / "data" / "story" / (scene_name + ".tres")).read_text()
        found = re.search(r'^stage = &"([^"]+)"', scene, re.MULTILINE)
        assert found
        played_on[found.group(1)] = [name for line in re.findall(r"^(?:loops|timelines) = (.*)$", scene, re.MULTILINE) for name in re.findall(r'&"([^"]+)"', line)]
    played_on["expert_closing_stage"] = ["expert_hoist", "expert_deck", "expert_wait"]          # (ExpertClosing.TIMELINES; the Voyager flight is made from its script)
    for stage_name, timeline_names in played_on.items():
        held = set(re.findall(r'^name = &"([^"]+)"', (DEV / "data" / "story" / (stage_name + ".tres")).read_text(), re.MULTILINE))
        for name in timeline_names:
            named = set(re.findall(r'^actor = &"([^"]+)"', (DEV / "data" / "story" / (name + ".tres")).read_text(), re.MULTILINE))
            assert named and named <= held, (name, named - held)


def test_the_dev_opening_has_a_shape_of_its_own_and_every_part_is_a_file_of_the_pack():
    """Four parts, the first a scene the legacy opening has no counterpart of (with its own stage and timeline); each part is a file dev holds."""
    import dev_story
    import step_story
    legacy = step_story.build_opening()
    mine = dev_story.opening()
    assert len(mine.parts) != len(legacy.parts) and mine.parts[0][1] == "logo" and "logo" not in [name for _kind, name, _lead in legacy.parts]
    assert (DEV / "data" / "story" / "opening.tres").read_text() == mine.render()
    for _kind, name, _lead in mine.parts:
        assert (DEV / "data" / "story" / (name + ".tres")).is_file(), name
    assert "logo_stage" in (DEV / "data" / "story" / "logo.tres").read_text() and (DEV / "data" / "story" / "logo_show.tres").is_file()
