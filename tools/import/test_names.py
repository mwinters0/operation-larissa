"""pytest checks of the name registry (godot/names/original.json, read by NameRegistry in godot/src/core/name_registry.gd).

GDScript checks the file against the reader's rules (tests/engine/test_name_registry.gd: convention, uniqueness, ranges). What
only Python can do is here: find a name written twice (a JSON parser keeps the last and says nothing), check that the
file is in the standard layout (so a tool can rewrite it without a diff), and check that the names seeded from the
importer's own tables still agree with those tables, so the two cannot drift apart unseen.
"""
import json
import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import animation_map as amap
import asset_names
import common

STORE = common.GODOT / "names" / "original.json"


def _no_duplicate_keys(pairs: list[tuple[str, object]]) -> dict:
    found: dict = {}
    for key, value in pairs:
        assert key not in found, "'%s' is written twice in the same object of %s" % (key, STORE.name)
        found[key] = value
    return found


def _store() -> dict:
    return json.loads(STORE.read_text(), object_pairs_hook=_no_duplicate_keys)


def _names(kind: str, scope: str | None = None) -> dict[str, int]:
    table = _store()["names"][kind]
    return table if scope is None else table[scope]


def test_no_name_is_written_twice() -> None:
    _store()


def test_the_file_is_in_the_standard_layout() -> None:
    """json.dumps(indent=1) with a final newline: what the tools that write the store produce, so no diff by re-saving."""
    store = _store()
    assert STORE.read_text() == json.dumps(store, indent=1, ensure_ascii=False) + "\n"


def test_names_are_listed_by_number() -> None:
    """Each table is in the order of its numbers, so a new name has one obvious place and the diffs stay small."""
    def tables(node):
        if node and all(isinstance(v, int) for v in node.values()):
            yield node
        else:
            for child in node.values():
                if isinstance(child, dict):
                    yield from tables(child)
    for kind, node in _store()["names"].items():
        for table in tables(node):
            assert list(table.values()) == sorted(table.values()), kind


@pytest.mark.legacy
def test_the_sounds_are_the_effects_the_decompilation_found() -> None:
    """Every effect in audio_map.json has a name (and the registry may name more: the creature-only sounds)."""
    audio = common.load_json(common.TABLES / "audio_map.json")["sfx"]
    assert {int(k) for k in audio} <= set(_names("sound").values())


@pytest.mark.legacy
def test_every_speech_clip_that_the_game_plays_has_a_name() -> None:
    voice = common.load_json(common.TABLES / "audio_map.json")["voice"]
    played: set[int] = {voice["jingle"], *voice["sign_in_first_visit"], *voice["sign_in_begin"], *voice["sign_in_resume"],
                        *voice["opening_cartoon"]}
    for key in ("story_pages", "supply", "logs", "closing_pages"):
        played.update(clip for run in voice[key] for clip in run)
    assert played <= set(_names("voice").values())


@pytest.mark.legacy
def test_the_songs_are_the_ones_of_the_music_map() -> None:
    ids = {e["id"] for e in common.load_json(common.TABLES / "music_map.json")["music"]}
    assert set(_names("music").values()) <= ids


def test_the_common_creature_pictures_follow_the_animation_map() -> None:
    """`<animation>_<k>` names the k-th slot of the animation of the same name in animation_map.FOE_COMMON."""
    named = _names("frame", "common")
    for animation, slots, _loop in amap.FOE_COMMON:
        for k, slot in enumerate(slots):
            assert named["%s_%d" % (animation, k)] == slot


def test_the_loose_picture_sets_follow_the_animation_map() -> None:
    named = _names("ui_picture")
    for animation, (ids, _loop) in amap.FX_SETS.items():
        for k, picture in enumerate(ids):
            assert named[animation if len(ids) == 1 else "%s_%d" % (animation, k)] == picture


def _snake(title: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_")


@pytest.mark.legacy
def test_the_zone_names_are_the_zone_titles() -> None:
    titles = re.findall(r'^title = "([^"]*)"', (common.PACK_DATA / "zones.tres").read_text(), re.MULTILINE)
    assert _names("zone") == {_snake(t): i for i, t in enumerate(titles)}


@pytest.mark.legacy
def test_the_sector_names_follow_zone_and_game() -> None:
    """<zone>_<game>_<n> for the 30 sectors of the two games, voyager_finale and expert_finale for 30 and 31."""
    zone_of = {i: n for n, i in _names("zone").items()}
    counts: dict[tuple[int, int], int] = {}
    for i in range(common.ORIGINAL_SECTOR_COUNT):
        text = (common.PACK_DATA / "sectors" / ("sector_%02d" % i) / ("sector_%02d.tres" % i)).read_text()
        game_match = re.search(r"^game = (\d+)", text, re.MULTILINE)
        assert game_match is not None
        game = int(game_match.group(1))
        zone_match = re.search(r"^zone = (\d+)", text, re.MULTILINE)
        assert zone_match is not None
        zone = int(zone_match.group(1))
        if zone >= 5:
            expected = zone_of[zone]
        else:
            counts[(zone, game)] = counts.get((zone, game), 0) + 1
            expected = "%s_%s_%d" % (zone_of[zone], ("voyager", "expert")[game], counts[(zone, game)])
        assert _names("sector")[expected] == i


def test_same_audio_groups_are_ascending_and_disjoint() -> None:
    """`same_audio`: each group lists two or more sound numbers, ascending; a number is in one group only."""
    groups = _store()["same_audio"]["sound"]
    flat = [n for group in groups for n in group]
    assert all(len(group) >= 2 and group == sorted(set(group)) for group in groups)
    assert groups == sorted(groups)
    assert len(flat) == len(set(flat))
    assert all(0 <= n <= 51 for n in flat)


def test_the_sounds_that_share_a_recording_are_the_ones_listed() -> None:
    """The groups against the sound files themselves: the same sample data, and no other two files have the same."""
    import wave
    by_data: dict[bytes, list[int]] = {}
    for i in range(52):
        path = asset_names.sfx_file(i)
        if not path.exists():
            pytest.skip("the sound files are not imported here")
        with wave.open(str(path)) as w:
            by_data.setdefault(w.readframes(w.getnframes()), []).append(i)
    found = sorted(group for group in by_data.values() if len(group) > 1)
    assert found == _store()["same_audio"]["sound"]


def test_every_creature_sound_is_named() -> None:
    """The sounds 0-21 are only played by creature scripts; each has a name of its role."""
    assert set(range(22)) <= set(_names("sound").values())
