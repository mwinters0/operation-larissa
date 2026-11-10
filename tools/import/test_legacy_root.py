"""pytest checks of where the legacy pack is on disk (common.legacy_root: the real folder godot/packs/legacy), and its pack.json.
Nothing here touches the real godot/packs/: every path is in tmp_path."""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common
import import_all


def test_the_derived_paths_are_below_the_root():
    assert common.LEGACY == common.legacy_root()
    assert (common.ASSETS, common.PACK_DATA, common.MIDI) == (common.LEGACY / "assets", common.LEGACY / "data", common.LEGACY / "midi")
    assert common.PROJECT_DATA == common.GODOT / "data"


def test_res_paths_of_legacy_lead_into_its_folder_and_back():
    inside = common.LEGACY / "assets" / "tiles" / "x.png"
    assert common.res_path(inside) == "res://packs/legacy/assets/tiles/x.png"
    assert common.res_path(common.LEGACY / "data" / "zones.tres") == "res://packs/legacy/data/zones.tres"
    assert common.res_path(common.PROJECT_DATA / "closing_crew.tres") == "res://data/closing_crew.tres"
    assert common.file_of_res("res://packs/legacy/assets/tiles/x.png") == inside
    assert common.file_of_res("res://data/closing_crew.tres") == common.PROJECT_DATA / "closing_crew.tres"


def test_sectors_of_legacy_and_the_designers_own_live_in_different_folders():
    assert common.sector_file(0, "tres") == common.PACK_DATA / "sectors" / "sector_00" / "sector_00.tres"
    assert common.sector_file(31, "foe").parent.parent == common.PACK_DATA / "sectors"          # the last original sector is the legacy pack's
    assert common.sector_file(32, "tres") == common.PROJECT_DATA / "sectors" / "sector_32" / "sector_32.tres"
    assert common.sector_dir(100).name == "sector_100"


# --- the folder and its pack.json ---------------------------------------------------------------------------------------------------

def test_the_legacy_pack_is_a_real_folder_of_the_project():
    assert common.legacy_root() == common.GODOT / "packs" / "legacy" == common.LEGACY
    assert common.LEGACY_RES == "res://packs/legacy/"


def test_prepare_writes_pack_json_once(tmp_path):
    root = tmp_path / "godot" / "packs" / "legacy"
    first = common.prepare_legacy(root)
    assert len(first) == 1 and root.is_dir() and not root.is_symlink()
    manifest = json.loads((root / "pack.json").read_text())
    assert manifest == {"id": "legacy", "title": "Operation Neptune (your copy)", "version": "1", "format": 1}
    stamp = (root / "pack.json").stat().st_mtime_ns
    assert common.prepare_legacy(root) == []                                 # deterministic: nothing changes, the file is not even rewritten
    assert (root / "pack.json").stat().st_mtime_ns == stamp
    (root / "pack.json").write_text("{}")                                    # a damaged pack.json is repaired
    assert len(common.prepare_legacy(root)) == 1 and json.loads((root / "pack.json").read_text()) == manifest


def test_no_trace_is_left_of_the_user_data_dir_logic():
    assert not hasattr(common, "uses_flatpak") and not hasattr(common, "ensure_link") and not hasattr(common, "LEGACY_LINK")


def test_the_importer_lists_the_pack_files_its_steps_write_inside_the_pack():
    """The witnesses (what 'the game is there' means) are all below the pack's assets/ or data/."""
    assert all(name.startswith(("assets/", "data/")) for name in common.LEGACY_WITNESSES)
    assert common.LEGACY_MANIFEST["id"] == common.LEGACY_ID == "legacy"


@pytest.mark.legacy
def test_the_story_and_console_steps_split_their_files_between_the_project_and_the_pack(monkeypatch):
    """The committed timelines and the menu layout go to godot/data/ (and `--clean` owns exactly those), the news cartoon and the other layouts to
    the legacy pack: the steps' own owned_files say which, and what they write is exactly the two lists together."""
    import step_console
    import step_story
    written: list[Path] = []
    for module in (step_console, step_story):
        monkeypatch.setattr(module, "out_text", lambda dest, text: written.append(dest))
        module.run()
    in_project = {p for p in written if p.is_relative_to(common.PROJECT_DATA)}
    in_pack = {p for p in written if p.is_relative_to(common.PACK_DATA)}
    assert in_project == set(step_story.owned_files()) | set(step_console.owned_files()) and in_project | in_pack == set(written)
    assert common.PACK_DATA / "story" / "news_cartoon.tres" in in_pack and common.PROJECT_DATA / "story" / "news_cartoon.tres" not in in_project
    assert {p.name for p in in_pack if p.parent.name == "ui"} == {"hud_layout.tres", "calculator_layout.tres", "story_layout.tres"}
    assert import_all.OWNED_FILES["story"] is step_story.owned_files and import_all.OWNED_FILES["console"] is step_console.owned_files
