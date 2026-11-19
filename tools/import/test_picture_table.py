"""pytest checks of the picture table (picture_table.py): the key of every picture file is recorded by the step that writes it (the forward rules of asset_names.py), a `.tres` holds a picture
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


def _recorded_key(path: Path) -> str:
    """The key the manifest (the record the steps wrote with the file) holds the picture file `path` by."""
    return asset_manifest.load()[_rel(path)]["picture_key"]


def test_the_steps_record_the_key_the_forward_rules_make_with_each_picture_file():
    """What a step hands `copy_picture` with the file is the key `asset_names.*_key` makes (the key the resources hold the picture by): the table is built from these records."""
    for folder, ids in pictures.UI_FOLDERS.items():
        for pid in ids:
            assert _recorded_key(pictures.ui_file(folder, pid)) == asset_names.ui_key(pid), (folder, pid)
    for zone in range(7):
        for slot in range(len(common.foe_slots(zone))):
            assert _recorded_key(asset_names.foe_file(zone, slot)) == asset_names.foe_key(zone, slot), (zone, slot)
    for zone in range(5):
        for slot in range(len(common.deco_slots(zone))):
            assert _recorded_key(asset_names.deco_file(zone, slot)) == asset_names.deco_key(zone, slot), (zone, slot)
    for name in ("zone0_tiles", "currents", "invisible_wall"):
        file, key = asset_names.tile(name)
        assert _recorded_key(file) == key == "tile/" + name


@NEEDS_GAME
def test_the_key_recorded_with_a_problem_art_file_is_its_problem_art_key():
    for folder, ids in step_images.problem_art_index().items():
        for pid in ids:
            if pictures.home(pid) is None:
                assert _recorded_key(pictures.problem_art_file(folder, pid)) == asset_names.problem_art_key(pid), (folder, pid)


def test_a_picture_is_recorded_with_its_key_and_nothing_else_is():
    entries = asset_manifest.load()
    for rel, entry in entries.items():
        assert ("picture_key" in entry) == rel.endswith(".png"), rel
    keys = [entry["picture_key"] for entry in entries.values() if "picture_key" in entry]
    assert len(keys) == len(set(keys)) > 900
    for rel, entry in entries.items():
        if rel.endswith(".png"):
            kind, name = entry["picture_key"].split("/", 1)
            assert kind in ("ui_picture", "problem_art", "frame", "deco", "tile", "background") and name, rel


def test_the_plain_folders_make_the_file_and_the_key_from_one_name():
    assert asset_names.sprite("sub", "sub_00")[1] == "frame/sub_00"
    assert _rel(asset_names.sprite("fx", "fx_bubbles_03")[0]) == "assets/sprites/fx/fx_bubbles_03.png"
    assert (_rel(asset_names.tile("zone0_tiles")[0]), asset_names.tile("zone0_tiles")[1]) == ("assets/tiles/zone0_tiles.png", "tile/zone0_tiles")
    assert (_rel(asset_names.background(3, 7)[0]), asset_names.background(3, 7)[1]) == ("assets/backgrounds/bg_s03_07.png", "background/bg_s03_07")


def test_the_table_has_a_row_for_each_recorded_picture_and_no_file_name_is_read():
    manifest = {"assets/x/whatever_1.png": {"picture_key": "frame/a"}, "assets/y/other.png": {"picture_key": "tile/b"}, "assets/y/README.md": {}}
    assert picture_table.rows(manifest, {}) == {"frame/a": "assets/x/whatever_1.png", "tile/b": "assets/y/other.png"}


def test_a_picture_without_its_key_or_two_with_one_key_are_refused():
    with pytest.raises(AssertionError, match="no picture key"):
        picture_table.rows({"assets/a.png": {"origin": "original"}}, {})
    with pytest.raises(AssertionError, match="is the key of"):
        picture_table.rows({"assets/a.png": {"picture_key": "frame/a"}, "assets/b.png": {"picture_key": "frame/a"}}, {})


def test_a_picture_another_role_keeps_is_an_alias_of_its_owners_key():
    owner = pictures.home(2012)
    owner_key = pictures.home_key(2012)
    assert owner is not None and owner_key is not None and owner_key == asset_names.ui_key(2012)
    table = picture_table.rows({_rel(owner): {"picture_key": owner_key}}, {"b999": [2012]})
    assert table[owner_key] == _rel(owner)
    assert table[asset_names.problem_art_key(2012)] == {"alias": owner_key}
    with pytest.raises(AssertionError, match="has no file"):
        picture_table.rows({}, {"b999": [2012]})


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
        if rel.endswith(".png"):
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
    table = _table()
    first = common.load_json(common.TABLES / "expert_closing.json")["first_picture"]
    for pid in range(first + 10, first + 27):                # the sailors' pictures (item 10 to 26): the deck timeline names them, the table answers their keys
        assert asset_names.ui_key(pid) in table and _ends_in_a_file(table, asset_names.ui_key(pid)), pid
