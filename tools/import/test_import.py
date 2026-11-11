"""pytest checks of the generated tree:   uv run --with pillow --with pytest pytest tools/import"""
import hashlib
import sys
from pathlib import Path
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import asset_names
import common
import validate


def test_only_runs_the_steps_in_pipeline_order():
    """`--only` names steps in any order; they run in the order of the pipeline (a step reads what an earlier one writes), each once."""
    import import_all
    assert import_all.steps_to_run(None) == list(import_all.STEPS)
    assert import_all.steps_to_run(None, ("transcripts",)) == [n for n in import_all.STEPS if n != "transcripts"]   # --no-transcripts
    assert import_all.steps_to_run("audio,sectors,tiles") == ["tiles", "sectors", "audio"]
    assert import_all.steps_to_run("godot,extract,godot") == ["extract", "godot"]
    assert import_all.steps_to_run("story, campaigns") == ["story", "campaigns"]
    with pytest.raises(ValueError, match="unknown step nope"):
        import_all.steps_to_run("sectors,nope")


def tree_hash(*folders: Path) -> str:
    h = hashlib.sha256()
    for folder in folders:
        for p in sorted(folder.rglob("*")):
            if p.is_file() and p.suffix != ".import":
                h.update(p.relative_to(common.LEGACY if p.is_relative_to(common.LEGACY) else common.GODOT).as_posix().encode())
                h.update(p.read_bytes())
    return h.hexdigest()


@pytest.mark.legacy
def test_validate():
    assert validate.run() == []


@pytest.mark.legacy
def test_idempotent_data_steps():
    """Re-running the data-producing steps changes no bytes."""
    import step_console, step_problems, step_sectors, step_sprites, step_tiles
    before = tree_hash(common.PACK_DATA, common.ASSETS / "tiles", common.ASSETS / "sprites")
    for step in (step_tiles, step_sprites, step_sectors, step_problems, step_console):
        step.run()
    assert tree_hash(common.PACK_DATA, common.ASSETS / "tiles", common.ASSETS / "sprites") == before


@pytest.mark.legacy
def test_piece_animation_matches_the_decompiled_tables():
    """The pieces' SpriteFrames hold the canister flash and the rock sparkle from docs/data/piece_animation.json."""
    import json
    anim = json.loads((common.DOCS_DATA / "piece_animation.json").read_text())
    assert anim["canister_pictures"] == [3, 4]
    assert len(anim["rock_pictures"]) == anim["period"] == 16
    assert anim["rock_pictures"] == [1, 2, 1] + [0] * 13
    text = (common.PACK_DATA / "sprite_frames" / "pieces_frames.tres").read_text()
    assert '"name": &"canister"' in text and '"name": &"rock"' in text
    import re
    for name, pictures in (("canister", anim["canister_pictures"]), ("rock", anim["rock_pictures"])):
        block = re.search(rf'\{{"frames": \[([^\]]*)\], "loop": true, "name": &"{name}"', text)
        assert block, name
        ids = re.findall(r'ExtResource\("([^"]+)"\)', block.group(1))
        order = re.findall(r'\[ext_resource [^\n]*id="([^"]+)"\]', text)
        assert [order.index(i) for i in ids] == pictures


@pytest.mark.legacy
def test_bubble_rules_match_the_decompiled_tables():
    """bubble_rules.tres is written from docs/data/bubbles.json (BUBBLES.C, DrawSub)."""
    import json
    data = json.loads((common.DOCS_DATA / "bubbles.json").read_text())
    amb = data["ambient"]
    assert amb["max_bubbles"] == len(amb["slots"]) == 2
    assert amb["bundle"] == 22 and len(amb["picture_sizes"]) == 8
    assert [sl["rise_per_tick"] for sl in amb["slots"]] == [10, 6]
    assert [sl["loop"] for sl in amb["slots"]] == [[1, 2, 3, 0], [5, 6, 7, 6, 5, 4]]
    assert amb["no_bubble_screens"] == [[0, 0], [0, 1], [0, 2], [0, 3]]
    rules = (common.PACK_DATA / "bubble_rules.tres").read_text()
    assert "spawn_chance = 50" in rules and "spawn_y = 320" in rules and "top_y = 32" in rules
    assert "slot_rise_per_tick = PackedInt32Array(10, 6)" in rules
    assert "PackedInt32Array(5, 6, 7, 6, 5, 4)" in rules
    assert "Vector2i(0, 3)" in rules
    # the pictures' sizes are in the rules: the original's table, and the importer's pictures have them
    sizes = ", ".join("Vector2i(%d, %d)" % tuple(size) for size in amb["picture_sizes"])
    assert "picture_sizes = Array[Vector2i]([%s])" % sizes in rules
    for i, size in enumerate(amb["picture_sizes"]):
        assert common.png_size("res://packs/legacy/assets/sprites/fx/fx_bubbles_%02d.png" % i) == tuple(size)


def test_the_project_tuning_file_matches_the_decompiled_tables():
    """godot/data/rules/tuning.json is committed, not generated: its tables for the ink pellets and for what DrawSub puts on the sub are
    those of docs/data/ink_tables.json and docs/data/bubbles.json, its collision rectangles those of DESIGN 3.3."""
    import json
    sub = json.loads((common.GODOT / "data" / "rules" / "tuning.json").read_text())["sub"]
    ink = json.loads((common.DOCS_DATA / "ink_tables.json").read_text())
    assert sub["ink_spawn_dx"] == ink["spawn_dx_by_subcell"]
    assert sub["ink_spawn_dy"] == ink["spawn_dy_by_subcell"]
    assert sub["ink_direction"] == ink["dir_by_subcell"]
    assert sub["ink_step_dx"] == ink["step_dx_by_dir"]
    assert sub["ink_step_dy"] == ink["step_dy_by_dir"]
    assert sub["ink_splash_dx"] == ink["splash_dx"]
    assert sub["ink_splash_dy"] == ink["splash_dy"]
    overlays = json.loads((common.DOCS_DATA / "bubbles.json").read_text())["sub_overlays"]
    assert sub["hit_bubble_x_by_cell"] == overlays["hit_bubbles"]["x_by_cell"] == [4, 4, 4, 4, 16, 16, 16, 16, 16]
    assert sub["light_cells"] == overlays["message_light"]["cells"] == [0, 1, 2, 6, 7, 8]
    assert sub["light_dx_by_cell"] == overlays["message_light"]["dx_by_cell"] == [46, 46, 46, 0, 0, 0, 34, 33, 35]
    assert sub["light_dy_by_cell"] == overlays["message_light"]["dy_by_cell"]
    # the collision rectangle of each of the nine frames (left, top, right, bottom in DESIGN 3.3), as [x, y, width, height]
    rects = [(10, 14, 90, 42), (4, 16, 86, 44), (2, 14, 94, 42), (6, 14, 78, 42), (26, 14, 70, 42),
             (16, 14, 88, 42), (0, 14, 92, 42), (8, 16, 90, 44), (4, 14, 84, 42)]
    assert sub["frame_rects"] == [[left, top, right - left, bottom - top] for left, top, right, bottom in rects]


@pytest.mark.legacy
def test_tileset_is_written_in_godots_own_text_format():
    """A Ctrl+S in the editor re-saves a loaded tileset; that must not change the committed file (docs/create/SCREEN_EDITOR.md, "Ctrl+S and Save All are safe").

    So the generator writes what Godot writes: a uid in the header and on every picture (the one in the picture's .import file),
    and no property that has its default value. Verified once by saving the file in a headless editor: byte for byte the same."""
    import re
    import step_tiles
    text = (common.PACK_DATA / "neptune_tileset.tres").read_text()
    assert text.startswith('[gd_resource type="TileSet" format=3 uid="%s"]\n' % step_tiles.TILESET_UID)
    textures = re.findall(r'^\[ext_resource type="Texture2D" uid="(uid://\w+)" path="res://packs/legacy/(assets/tiles/\w+\.png)"', text, re.MULTILINE)
    assert len(textures) == 7 == text.count("[ext_resource")
    for uid, png in textures:
        assert 'uid="%s"' % uid in (common.LEGACY / (png + ".import")).read_text()
    assert "texture_region_size" not in text and "\ntile_size" not in text           # 16 x 16 is the default: Godot leaves it out
    assert re.search(r"Vector2\(-?\d+\.", text) is None                            # whole numbers print without ".0"


@pytest.mark.legacy
def test_tileset_names_bytes_and_invisible_wall():
    """neptune_tileset.tres: named sources, a tile_byte on every tile (see TileCodec), and the editor-only source 6."""
    import re
    text = (common.PACK_DATA / "neptune_tileset.tres").read_text()
    names = re.findall(r'^resource_name = "(.*)"$', text, re.MULTILINE)
    assert names[:5] == ["Zone %d: %s" % (z, t) + (" (also the finales)" if z == 4 else "")
                         for z, t in enumerate(common.ZONE_TITLES)]
    assert names[5].startswith("Currents") and names[6].startswith("Invisible wall")
    assert len(names) == 7
    # 5 zone atlases of 64 cells, the currents (64 cells) and the one invisible-wall tile
    assert len(re.findall(r"/custom_data_1 = ", text)) == 5 * 64 + 64 + 1
    assert "0:0/0/custom_data_1 = 64\n" in text                       # zone cell 0 / invisible wall: 0x40
    assert "7:7/0/custom_data_1 = %d\n" % (0x80 | 7 << 3 | 7) in text  # currents (7, 7)
    assert (common.ASSETS / "tiles" / "invisible_wall.png").exists()


# Different pictures (different NEP.DLL ids) that happen to hold the same pixels. They are not duplicates: the game
# draws each under its own id, so each keeps its file.
def _rel(path: Path) -> str:
    return path.relative_to(common.ASSETS).as_posix()


SAME_PIXELS_DIFFERENT_IDS = {
    frozenset({"authoring_tool/editor_2083.png", "authoring_tool/editor_2084.png"}),
    frozenset({_rel(asset_names.problem_art_folder_file("b084", 1851)), _rel(asset_names.problem_art_folder_file("b088", 1866)),
               _rel(asset_names.problem_art_folder_file("b092", 1889))}),
    frozenset({_rel(asset_names.problem_art_folder_file("b084", 1852)), _rel(asset_names.problem_art_folder_file("b088", 1867))}),
    frozenset({_rel(asset_names.foe_file(2, 41)), _rel(asset_names.foe_file(3, 43))}),
    frozenset({"sprites/station/station_05.png", "sprites/station/station_06.png"}),
}


@pytest.mark.legacy
def test_every_picture_is_stored_once():
    """Each NEP.DLL picture id has one PNG under assets/ (tools/import/pictures.py), however many roles need it."""
    by_content: dict[str, set[str]] = {}
    for p in common.ASSETS.rglob("*.png"):
        by_content.setdefault(hashlib.md5(p.read_bytes()).hexdigest(), set()).add(p.relative_to(common.ASSETS).as_posix())
    copies = {frozenset(files) for files in by_content.values() if len(files) > 1}
    assert copies == SAME_PIXELS_DIFFERENT_IDS


@pytest.mark.legacy
def test_pictures_have_one_home_and_the_problem_art_index_resolves():
    """`pictures.home` names an existing file for every owned id, and every id the index lists has a file somewhere."""
    import json
    import pictures
    for pid, path in pictures.homes().items():
        assert path.exists(), (pid, path)
    index = json.loads((common.PACK_DATA / "problems" / "problem_art_index.json").read_text())
    assert pictures.home(2005) == asset_names.foe_file(6, 38)       # finale creature, listed in b112
    assert 2005 in index["b112"] and pictures.home(2060) == pictures.ui_file("story", 2060) and 2060 in index["single"]
    for folder, ids in index.items():
        for pid in ids:
            assert pictures.problem_art_file(folder, pid).exists(), (folder, pid)


@pytest.mark.legacy
def test_png_size_reads_the_header_of_a_picture():
    assert common.png_size("res://packs/legacy/assets/sprites/fx/fx_bubbles_00.png") == (24, 70)


@pytest.mark.legacy
def test_layout_sizes_are_written_from_the_pictures():
    """Hit areas and centring are measured from DATA: the importer writes the sizes of the pictures they came from."""
    calc = (common.PACK_DATA / "ui" / "calculator_layout.tres").read_text()
    assert "picture_size = Vector2i(292, 130)" in calc and "answer_size = Vector2i(296, 40)" in calc
    assert "point_size = Vector2i(4, 6)" in calc and "slash_size = Vector2i(12, 14)" in calc
    ballast = (common.PACK_DATA / "problems" / "problem_type_28.tres").read_text()
    assert '"slot_size": [' in ballast and '"size": [' in ballast
    assert '"answer_wheel": {"first_pic": 12, "pos": [40, 60], "size": [268, 228]}' in (common.PACK_DATA / "problems" / "problem_type_00.tres").read_text()
    layout = (common.PACK_DATA / "problems" / "screen_layout.tres").read_text()
    assert "line_height = 20" in layout and "line_separation = 0" in layout     # GetFontLineHeight: 20 px for every text
    assert "background_size = Vector2i(616, 296)" in layout
    assert "title_x = PackedInt32Array(0, 36, 96)" in (common.PROJECT_DATA / "ui" / "menu_layout.tres").read_text()


# --- the legacy pack is not committed -----------------------------------------------------------------------------------------------

def test_the_python_and_the_godot_list_of_legacy_files_are_the_same():
    """tools/import/common.py LEGACY_WITNESSES and godot/tests/legacy/legacy_pack.gd WITNESSES say what 'the game is there' means: keep them one list."""
    import re
    source = (common.GODOT / "tests" / "legacy" / "legacy_pack.gd").read_text()
    block = source[source.index("const WITNESSES"):]
    block = block[block.index("= ["):]
    block = block[:block.index("\n]")]
    # (the Godot list may spell each path with the pack's root, res://packs/legacy/, or still without it)
    found = [path.removeprefix("packs/legacy/") for path in re.findall(r'"res://([^"]+)"', block)]
    assert found == common.LEGACY_WITNESSES


def test_the_importer_states_no_rule_values():
    """The original's rule values are the defaults (godot/data/rules/tuning.json, the project's own file): the legacy pack holds no rules/tuning.json, so the
    original plays on the defaults and a pack that wants other values states them itself. No step, no helper of the importer names the file."""
    sources = [p for p in sorted(Path(__file__).resolve().parent.glob("*.py")) if not p.name.startswith("test_") and p.name != "validate.py"]
    assert any(p.name == "import_all.py" for p in sources) and any(p.name.startswith("step_") for p in sources)
    for source in sources:
        text = source.read_text().lower()
        assert "tuning" not in text, f"{source.name} writes or names the rule values; the legacy pack states none"


@pytest.mark.legacy
def test_the_legacy_pack_holds_no_rule_values():
    """What the importer wrote for the original has no rules/tuning.json (a pack's file would be laid over the project's, key by key)."""
    assert (common.LEGACY / "data" / "campaigns").exists()
    assert not list(common.LEGACY.rglob("tuning.json"))


def test_every_file_the_importer_writes_for_legacy_is_git_ignored():
    """The legacy pack is never committed: godot/packs/legacy and anything else in godot/packs/ are ignored, except the README and the dev pack. The files the importer also writes into the project that commit (they are made from the committed analysis alone: the closing crew,
    the cutscene timelines but the news cartoon's, the menu layout) are not ignored. `git check-ignore` is the judge, so a pattern that does not
    match the real path is found here."""
    import subprocess
    ignored = ["godot/packs/legacy", "godot/packs/legacy/data/zones.tres", "godot/packs/legacy/assets/tiles/zone0_tiles.png", "godot/packs/some_pack", "godot/data/legacy/voice_corrections.json", "docs/data/sectors.json",
               "godot/tests/fixtures/original/screens.json"]
    committed = ["godot/packs/README.md", "godot/packs/dev/pack.json", "godot/packs/dev/data/zones.tres", "godot/data/sectors/foe_annotations.json", "godot/data/sectors/sector_32/sector_32.tres",
                 "godot/data/rules/tuning.json", "godot/data/closing_crew.tres", "godot/data/ui/menu_layout.tres", "godot/data/story/title_ship.tres",
                 "godot/data/rules/durations.json", "docs/data/hud_gauges.json", "godot/names/original.json"]
    for path, want in [(p, True) for p in ignored] + [(p, False) for p in committed]:
        done = subprocess.run(["git", "check-ignore", "-q", path], cwd=common.ROOT, check=False)
        assert (done.returncode == 0) == want, path


def test_a_stub_import_file_has_a_uid_that_depends_only_on_the_path():
    import import_uids
    assert import_uids.uid_of("res://packs/legacy/assets/a.png") == import_uids.uid_of("res://packs/legacy/assets/a.png") != import_uids.uid_of("res://packs/legacy/assets/b.png")
    assert import_uids.uid_of("res://packs/legacy/assets/a.png").startswith("uid://")
    assert set(import_uids.uid_of("res://packs/legacy/assets/a.png")[6:]) <= set(import_uids.ALPHABET)          # Godot's alphabet: 'z' and '9' are never used
    assert import_uids.ALPHABET == "abcdefghijklmnopqrstuvwxy012345678"
    # Godot writes the same number as base 34 of the 63 bit value: 1 is "b", 34 is "ba"
    assert import_uids.ALPHABET[1] == "b"


def test_a_sidecar_that_exists_is_never_touched(tmp_path, monkeypatch):
    import import_uids
    monkeypatch.setattr(import_uids, "res_path", lambda path: "res://" + path.name)
    png = tmp_path / "a.png"
    png.write_bytes(b"x")
    assert import_uids.ensure_sidecar(png) is True
    text = import_uids.sidecar(png).read_text()
    assert 'importer="texture"' in text and 'uid="%s"' % import_uids.uid_of("res://a.png") in text
    import_uids.sidecar(png).write_text(text + "# Godot's\n")
    assert import_uids.ensure_sidecar(png) is False and import_uids.sidecar(png).read_text().endswith("# Godot's\n")
    assert import_uids.uid_in(png) == import_uids.uid_of("res://a.png")
    assert import_uids.ensure_sidecar(tmp_path / "notes.md") is False             # only pictures and sounds have sidecars
