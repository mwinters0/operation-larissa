"""pytest checks of the asset file names (asset_names.py): a named entry's file is `<name>_<number>`, an unnamed one keeps its
old name, nothing is left behind under an old name, and the importer moves a renamed file instead of leaving two."""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import asset_manifest
import asset_names
import common
import foe_names
import pictures
import step_audio

STORE = json.loads(foe_names.STORE.read_text())["names"]
INDEX_FILE = common.PACK_DATA / "problems" / "problem_art_index.json"
INDEX = json.loads(INDEX_FILE.read_text()) if INDEX_FILE.exists() else {}      # the legacy pack: the tests that need it are marked legacy


def _flat(kind: str):
    """(name, number, scope) of every real name of a global kind (scope -1) or of a scoped one."""
    for key, node in STORE[kind].items():
        if isinstance(node, dict):
            for name, number in node.items():
                yield name, number, (foe_names.NO_SCOPE if key == foe_names.COMMON else int(key))
        else:
            yield key, node, foe_names.NO_SCOPE


def _problem_art_path(pid: int) -> Path:
    folder = next(f for f, ids in INDEX.items() if pid in ids)
    return pictures.problem_art_file(folder, pid)


def _expected(kind: str, name: str, number: int, scope: int) -> Path:
    """The file of a named entry, built from the rule in the docs (not from asset_names)."""
    base = common.ASSETS
    if kind == "sound":
        return base / "audio" / "sfx" / ("%s_%d.wav" % (name, number))
    if kind == "voice":
        return base / "audio" / "voice" / ("%s_%d.wav" % (name, number))
    if kind == "frame":
        prefix = "" if number < common.FOE_ZONE_BASE else "foe_z%d_" % scope
        return base / "sprites" / "foes" / ("%s%s_%d.png" % (prefix, name, number))
    if kind == "deco":
        prefix = "" if number < common.COMMON_DECOS else "deco_z%d_" % scope
        return base / "sprites" / "decos" / ("%s%s_%d.png" % (prefix, name, number))
    raise AssertionError(kind)


def _old(kind: str, number: int, scope: int) -> Path:
    """The file the entry had before it was named."""
    base = common.ASSETS
    return {"sound": base / "audio" / "sfx" / ("sfx_%02d.wav" % number),
            "voice": base / "audio" / "voice" / ("voice_%d.wav" % number),
            "frame": base / "sprites" / "foes" / (("foe_%03d" % number) if number < common.FOE_ZONE_BASE else "foe_z%d_%03d" % (scope, number)),
            "deco": base / "sprites" / "decos" / (("deco_%03d" % number) if number < common.COMMON_DECOS else "deco_z%d_%03d" % (scope, number)),
            }[kind].with_suffix(".wav" if kind in ("sound", "voice") else ".png")


@pytest.mark.parametrize("kind", ["sound", "voice", "frame", "deco"])
@pytest.mark.legacy
def test_a_named_entry_has_its_file_under_name_and_number_and_not_under_the_old_name(kind):
    count = 0
    for name, number, scope in _flat(kind):
        if kind in ("frame", "deco") and number >= (common.FOE_ZONE_BASE if kind == "frame" else common.COMMON_DECOS):
            assert scope >= 0, (kind, name)                       # a zone's own slot is named in its zone
        want = _expected(kind, name, number, scope)
        assert want.exists(), (kind, name, number, want)
        assert not _old(kind, number, scope).exists(), (kind, name, number)
        count += 1
    assert count > 0


@pytest.mark.legacy
def test_a_named_music_picture_or_problem_art_entry_has_its_file_under_name_and_number():
    for name, number, _ in _flat("music"):
        song = next(e for e in common.load_json(common.TABLES / "music_map.json")["music"] if e["id"] == number)
        for letter, adlib in (("e", False), ("b", True)):
            midi = (letter + song["file"][1:]).rsplit(".", 1)[0].lower()
            path = asset_names.music_file(number, midi, adlib)
            assert path.name == "%s_%d.ogg" % (name, number) and path.exists(), path
            assert not path.with_name(midi + ".ogg").exists()
    for name, number, _ in _flat("ui_picture"):
        path = pictures.home(number)
        assert path is not None and path.name == "%s_%d.png" % (name, number) and path.exists(), (name, number)
        assert not path.with_name("ui_%d.png" % number).exists()
    for name, number, _ in _flat("problem_art"):
        path = _problem_art_path(number)
        assert path.name == "%s_%d.png" % (name, number) and path.exists(), (name, number)
        assert not path.with_name("pa_%d.png" % number).exists()


@pytest.mark.legacy
def test_every_file_of_the_asset_kinds_is_a_named_or_an_unnamed_entrys_file():
    """No file is left under a name that no entry has any more: the folders hold exactly what the rule says (and the manifest agrees)."""
    wanted = {asset_names.sfx_file(n) for n in range(52)} | {asset_names.voice_file(v) for v in range(4000, 4371)}
    found = set((common.ASSETS / "audio" / "sfx").glob("*.wav")) | set((common.ASSETS / "audio" / "voice").glob("*.wav"))
    assert found == wanted
    music = {asset_names.music_file(e["id"], (letter + e["file"][1:]).rsplit(".", 1)[0].lower(), letter == "b")
             for e in common.load_json(common.TABLES / "music_map.json")["music"] for letter in "eb"}
    assert set((common.ASSETS / "audio" / "music").rglob("*.ogg")) == music
    ui = {p for p in pictures.homes().values() if "ui" in p.parts[-3:-1]}
    assert set((common.ASSETS / "ui").rglob("*.png")) == ui


def test_the_rule_for_every_sound_and_the_zone_prefix_of_zone_slots():
    registry = foe_names.original()
    for number in range(52):
        name = registry.real_name("sound", number)
        assert asset_names.sfx_file(number).name == ("%s_%d.wav" % (name, number) if name else "sfx_%02d.wav" % number)
    assert asset_names.foe_file(3, 40).name.startswith("foe_z3_")
    assert asset_names.deco_file(2, 100).name.startswith("deco_z2_")


# --- moving a renamed file ------------------------------------------------------------------------------------------

@pytest.fixture
def tree(tmp_path, monkeypatch):
    """A fake godot/ folder: asset_manifest records and prunes inside tmp_path."""
    monkeypatch.setattr(asset_manifest, "LEGACY", tmp_path)
    monkeypatch.setattr(asset_manifest, "res_path", lambda p: "res://" + p.relative_to(tmp_path).as_posix())
    asset_manifest.reset()
    yield tmp_path
    asset_manifest.reset()


def _record(path: Path) -> None:
    asset_manifest._recorded[asset_manifest.key_of(path)] = {"origin": "port", "source": "x", "conversion": "text"}


def test_prune_removes_what_the_run_did_not_write_and_carries_the_import_file_over(tree):
    folder = tree / "assets" / "audio" / "sfx"
    folder.mkdir(parents=True)
    old, new, other, gone = folder / "sfx_38.wav", folder / "lock_tick_38.wav", folder / "sfx_01.wav", folder / "sfx_02.wav"
    old.write_bytes(b"lock")
    new.write_bytes(b"lock")
    other.write_bytes(b"other")
    gone.write_bytes(b"gone")
    (folder / "sfx_38.wav.import").write_text('uid="uid://abc"\nsource_file="res://assets/audio/sfx/sfx_38.wav"\n')
    (folder / "sfx_01.wav.import").write_text('uid="uid://def"\n')
    (folder / "sfx_02.wav.import").write_text('uid="uid://ghi"\n')
    (folder / "orphan.wav.import").write_text("x")
    for p in (new, other):
        _record(p)
    removed, carried = asset_manifest.prune([tree / "assets" / "audio"])
    assert (removed, carried) == (2, 1)
    assert sorted(p.name for p in folder.iterdir()) == ["lock_tick_38.wav", "lock_tick_38.wav.import", "sfx_01.wav", "sfx_01.wav.import"]
    carried_text = (folder / "lock_tick_38.wav.import").read_text()
    assert 'uid="uid://abc"' in carried_text and "res://assets/audio/sfx/lock_tick_38.wav" in carried_text
    assert asset_manifest.prune([tree / "assets" / "audio"]) == (0, 0)          # a second run finds nothing


def test_prune_leaves_no_empty_folder_and_leaves_other_folders_alone(tree):
    (tree / "assets" / "ui" / "map").mkdir(parents=True)
    (tree / "assets" / "ui" / "map" / "ui_1000.png").write_bytes(b"1")
    (tree / "assets" / "tiles").mkdir(parents=True)
    (tree / "assets" / "tiles" / "x.png").write_bytes(b"2")
    assert asset_manifest.prune([tree / "assets" / "ui"]) == (1, 0)
    assert not (tree / "assets" / "ui" / "map").exists() and (tree / "assets" / "tiles" / "x.png").exists()


def test_a_song_that_was_rendered_under_its_old_name_is_moved_not_rendered(tmp_path):
    (tmp_path / "esect1.ogg").write_bytes(b"ogg")
    (tmp_path / "esect1.ogg.import").write_text('source_file="res://x/esect1.ogg"\n')
    dest = tmp_path / "sector_song_1_9504.ogg"
    assert step_audio.adopt_song(dest, "esect1", 9504)
    assert dest.read_bytes() == b"ogg" and not (tmp_path / "esect1.ogg").exists()
    assert "sector_song_1_9504.ogg" in Path(str(dest) + ".import").read_text()
    renamed = tmp_path / "first_song_9504.ogg"                                        # a later rename is found by the number
    assert step_audio.adopt_song(renamed, "esect1", 9504) and renamed.exists() and not dest.exists()
    assert not step_audio.adopt_song(renamed, "esect1", 9504)                          # already there: nothing to do
