"""Step 'images': backgrounds, UI art and problem-panel art (plain PNG copies)."""
from __future__ import annotations

from asset_manifest import copy_picture, put_port
from common import ASSETS, EXTRACTED, PACK_DATA, ORIGINAL_SECTOR_COUNT, SCREENS, bundles, load_json, manifest, out_text
from pictures import UI_FOLDERS, home, problem_art_file, ui_file
import json

# 2081-2090 (logical ids 863-872) are the original LEVEL EDITOR's interface art, not problem art: the toolbar (Tiles /
# Foes / Currnt / DAnim / MathTr, Bkgrd / Midgrd / Forgrd, Save / Egg / Done), the foe-script instruction palette
# (Goto ... ClrS: all 24 opcodes but YIELD) and the foe field labels. The shipped ONWIN32.EXE never loads them (the
# editor modules EDIT / EDITDECO / EDITFOES / EDITMATH were compiled out, see DESIGN "Authoring-tool remnants").
# They are kept, in their own folder, so nothing mistakes them for problem art.
AUTHORING_TOOL_IDS = list(range(2081, 2091))


AUTHORING_TOOL_README = """# Authoring-tool art (NOT used by the game or the port)

NEP.DLL pictures 2081-2090: the interface of the original developers' level editor (toolbar, foe-script instruction
palette, foe field labels, list buttons). The shipped game never loads them; the editor's code was compiled out of the
executable. They are kept for reference only and nothing in the port references them.

Files are named `editor_<NEP.DLL picture id>.png`. What each one shows, how the palette maps to the foe-script opcodes and the
evidence that the game does not use them: `docs/port/DESIGN.md` section 16.

This file and the folder are written by `tools/import/step_images.py` (`import_all.py --only images`); edit the text there.
"""

PROBLEM_ART_SINGLE_README = """# Loose problem-screen pictures (written by tools/import/step_images.py)

Every NEP.DLL picture in ids 1780-2138 that belongs to no picture bundle (the bundles are the sibling `bNNN` folders)
and that no other part of the port owns. This is a sweep, not a list of what the port uses. Used by the port: 1780,
1803 (combination-lock face), 1864 and 1979 (problem-panel backgrounds, `problem_type_NN.tres`; the surface ship screen).

Files are called `<name>_<id>.png` (`surface_ship_1979.png`), or `pa_<id>.png` when nobody has named the picture (`docs/create/NAMES.md`, "Asset file names").

Each NEP.DLL picture is stored once, so pictures the story, title or finale-creature code owns are NOT repeated in
the sweep, here or in the `bNNN` folders: 1995-2001, 2012-2040 and 2055-2079 are the opening and closing sequences' art in
`assets/ui/story/`, 2041-2045 the sign-in scanner strips in `assets/ui/title/`, and 1980-1994 and 2002-2011 the Voyager and
Expert finale creatures in `assets/sprites/foes/foe_z5_*` and `foe_z6_*`. `tools/import/pictures.py` knows where each id
lives. 2080 is a red "CRASH SITE" arrow nobody has placed yet. The level editor's interface art (2081-2090) is in
`assets/authoring_tool/` (`docs/port/DESIGN.md` section 16).

`../../../data/problems/problem_art_index.json` lists the picture ids of every folder, including those whose file is kept elsewhere.
"""


def background_dll(bg_id: int) -> str:
    return "NEPBG1" if bg_id < 3180 else "NEPBG2"


def run() -> None:
    # Backgrounds: id 3000 + sector*12 + screen. 8 ids (sector 31 screen 11 and
    # seven in sector 30) do not exist in the game data, so 376 files result.
    n = 0
    for sector in range(ORIGINAL_SECTOR_COUNT):
        for screen in range(SCREENS):
            bg_id = 3000 + sector * SCREENS + screen
            if "%s:%d" % (background_dll(bg_id), bg_id) in manifest():
                copy_picture(bg_id, ASSETS / "backgrounds" / ("bg_s%02d_%02d.png" % (sector, screen)), background_dll(bg_id))
                n += 1
    print("  backgrounds:", n)

    # The ids of each folder are in pictures.py, which also keeps the same id out of every other folder.
    for folder, ids in UI_FOLDERS.items():
        for i in ids:
            copy_picture(i, ui_file(folder, i))
        print("  ui/%s: %d" % (folder, len(ids)))

    # Problem panel art: bundles 41 and 77-118 (picture ids 1780-2138) plus
    # loose pictures in that id range that belong to no bundle. The index lists every id of every folder; the
    # PNG of an id that the story, title or finale-creature code owns (pictures.home) is not written again here.
    index: dict[str, list[int]] = {}
    in_bundle: set[int] = set()
    for b in [41] + list(range(77, 119)):
        ids = bundles()[str(b)]["frame_ids"] if str(b) in bundles() else []
        index["b%03d" % b] = ids
        for i in ids:
            in_bundle.add(i)
            if home(i) is None:
                copy_picture(i, problem_art_file("b%03d" % b, i))
    singles = []
    for i in range(1780, 2139):
        if i in AUTHORING_TOOL_IDS:
            continue
        if i not in in_bundle and "NEP256:%d" % i in load_json(EXTRACTED / "images" / "manifest.json"):
            if home(i) is None:
                copy_picture(i, problem_art_file("single", i))
            singles.append(i)
    index["single"] = singles
    out_text(ASSETS / "problem_art" / "single" / "README.md", PROBLEM_ART_SINGLE_README)
    put_port(ASSETS / "problem_art" / "single" / "README.md", "tools/import/step_images.py", "text")
    out_text(PACK_DATA / "problems" / "problem_art_index.json", json.dumps(index, indent=1, sort_keys=True) + "\n")
    print("  problem art: %d pictures in %d folders" % (len(in_bundle) + len(singles), len(index)))

    for i in AUTHORING_TOOL_IDS:
        copy_picture(i, ASSETS / "authoring_tool" / ("editor_%d.png" % i))
    out_text(ASSETS / "authoring_tool" / "README.md", AUTHORING_TOOL_README)
    put_port(ASSETS / "authoring_tool" / "README.md", "tools/import/step_images.py", "text")
    print("  authoring_tool: %d" % len(AUTHORING_TOOL_IDS))
