"""pytest checks of the picture table (picture_table.py): the key of every picture file is the key the importer says it holds the picture by, a `.tres` holds a picture
as a PictureRef sub-resource (`Tres.picture`), and the legacy pack's `pictures.json` answers every key its data names."""
import json
import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import asset_manifest
import asset_names
import common
import picture_table
import pictures
import step_images
import tres

NEEDS_GAME = pytest.mark.skipif(not (common.EXTRACTED / "images" / "manifest.json").is_file(), reason="run the importer on your copy of the game (extracted/ is missing)")


def _rel(path: Path) -> str:
    return path.relative_to(common.LEGACY).as_posix()


def test_the_key_of_a_file_is_the_key_the_importer_holds_the_picture_by():
    """`key_of_rel` (file -> key, for the table written from the manifest) and `asset_names.*_key` (the key a step writes into a resource) are one rule."""
    for folder, ids in pictures.UI_FOLDERS.items():
        for pid in ids:
            assert picture_table.key_of_file(pictures.ui_file(folder, pid)) == asset_names.ui_key(pid), (folder, pid)
    for zone in range(7):
        for slot in range(len(common.foe_slots(zone))):
            assert picture_table.key_of_file(asset_names.foe_file(zone, slot)) == asset_names.foe_key(zone, slot), (zone, slot)
    for zone in range(5):
        for slot in range(len(common.deco_slots(zone))):
            assert picture_table.key_of_file(asset_names.deco_file(zone, slot)) == asset_names.deco_key(zone, slot), (zone, slot)


@NEEDS_GAME
def test_the_key_of_a_problem_art_file_is_its_problem_art_key():
    for folder, ids in step_images.problem_art_index().items():
        for pid in ids:
            if pictures.home(pid) is None:
                assert picture_table.key_of_file(pictures.problem_art_file(folder, pid)) == asset_names.problem_art_key(pid), (folder, pid)


def test_a_key_of_a_plain_folder_is_the_stem_and_what_is_no_picture_has_none():
    assert picture_table.key_of_rel("assets/sprites/sub/sub_00.png") == "frame/sub_00"
    assert picture_table.key_of_rel("assets/sprites/fx/fx_bubbles_03.png") == "frame/fx_bubbles_03"
    assert picture_table.key_of_rel("assets/tiles/zone0_tiles.png") == "tile/zone0_tiles"
    assert picture_table.key_of_rel("assets/backgrounds/bg_s03_07.png") == "background/bg_s03_07"
    assert picture_table.key_of_rel("assets/ui/hud/ui_1189.png") == "ui_picture/ui_1189"                        # (nobody named it: the number is part of the name)
    assert picture_table.key_of_rel("assets/sprites/decos/deco_z0_096.png") == "deco/deco_z0_096"
    assert picture_table.key_of_rel("assets/sprites/foes/foe_z2_octopus_ball_41.png") == "frame/foe_z2_octopus_ball"
    assert picture_table.key_of_rel("assets/authoring_tool/editor_2081.png") == ""
    assert picture_table.key_of_rel("assets/problem_art/single/README.md") == ""
    assert picture_table.key_of_rel("assets/audio/sfx/lock_tick_38.wav") == ""


def test_a_picture_another_role_keeps_is_an_alias_of_its_owners_key():
    owner = pictures.home(2012)
    assert owner is not None
    files = [_rel(owner)]
    table = picture_table.rows(files, {"b999": [2012]})
    assert table[picture_table.key_of_file(owner)] == _rel(owner)
    assert table[asset_names.problem_art_key(2012)] == {"alias": picture_table.key_of_file(owner)}


def test_the_table_text_is_sorted_json_the_engine_reads():
    text = picture_table.render({"frame/b": "assets/b.png", "frame/a": {"alias": "frame/b"}})
    assert json.loads(text) == {"format": 1, "pictures": {"frame/a": {"alias": "frame/b"}, "frame/b": "assets/b.png"}}
    assert text.index('"frame/a"') < text.index('"frame/b"')


def test_a_picture_is_held_by_key_in_a_sub_resource_of_picture_ref_once_per_file():
    t = tres.Tres("SpriteFrames")
    first = t.picture("frame/sub_00")
    assert t.picture("frame/sub_00") == first != t.picture("frame/sub_01")
    t.set("x", first)
    text = t.render()
    assert text.count('[sub_resource type="Texture2D"') == 2
    assert 'script = ExtResource("1_picture_ref")' in text and 'key = "frame/sub_00"' in text
    assert '[ext_resource type="Script" path="res://src/core/picture_ref.gd" id="1_picture_ref"]' in text
    assert "Texture2D\" path" not in text                             # (no picture file is named)


# --- the legacy pack ------------------------------------------------------------------------------------------------

def _table() -> dict:
    return json.loads((common.LEGACY / picture_table.FILE).read_text())["pictures"]


def _ends_in_a_file(table: dict, key: str) -> bool:
    seen = set()
    while isinstance(table.get(key), dict):
        assert key not in seen, "%s: an alias circle" % key
        seen.add(key)
        key = table[key]["alias"]
    return isinstance(table.get(key), str)


@pytest.mark.legacy
def test_every_row_is_a_file_of_the_pack_or_an_alias_that_ends_in_one():
    table = _table()
    manifest = asset_manifest.load()
    files = {}
    for key, row in table.items():
        assert key.split("/")[0] in ("ui_picture", "background", "problem_art", "frame", "deco", "tile"), key
        assert _ends_in_a_file(table, key), key
        if isinstance(row, str):
            assert row in manifest and (common.LEGACY / row).is_file(), (key, row)
            assert files.setdefault(row, key) == key, "%s and %s are one file" % (files[row], key)
    for rel in manifest:
        if rel.endswith(".png") and "/authoring_tool/" not in rel:
            assert rel in files, "%s has no row" % rel
    assert table == picture_table.rows(manifest, step_images.problem_art_index())       # (the table on disk is what the manifest says)


@pytest.mark.legacy
def test_every_key_a_resource_of_the_pack_names_is_a_row():
    table = _table()
    named: dict[str, str] = {}
    for path in sorted(common.PACK_DATA.rglob("*.tres")):
        text = path.read_text()
        assert not re.search(r'\[ext_resource type="Texture2D"', text), "%s names a picture file" % path.name
        for key in re.findall(r'^key = "([^"]+)"$', text, re.MULTILINE):
            named.setdefault(key, path.name)
        for line in re.findall(r"^(?:art_keys|pictures) = PackedStringArray\((.*)\)$", text, re.MULTILINE):
            for key in re.findall(r'"([^"]+)"', line):
                named.setdefault(key, path.name)
    assert len(named) > 600
    for key, holder in named.items():
        assert key in table and _ends_in_a_file(table, key), "%s (%s) is no row of pictures.json" % (key, holder)


@pytest.mark.legacy
def test_the_problem_types_hold_their_art_by_key_in_the_order_of_their_pictures():
    for n in range(34):
        text = (common.PACK_DATA / "problems" / ("problem_type_%02d.tres" % n)).read_text()
        assert "art_dir" not in text and "art_files" not in text
        keys = re.search(r"^art_keys = PackedStringArray\((.*)\)$", text, re.MULTILINE)
        assert keys is not None and re.findall(r'"(problem_art/[^"]+)"', keys.group(1)), n
    lock = (common.PACK_DATA / "problems" / "problem_type_00.tres").read_text()
    assert asset_names.problem_art_key(1803) in lock
    crew = (common.PACK_DATA / "story" / "closing_crew.tres").read_text()
    assert "first_picture" not in crew and '"ui_picture/' in crew
