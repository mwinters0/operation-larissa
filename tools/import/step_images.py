"""Step 'images': backgrounds, UI art and problem-panel art (plain PNG copies)."""
from __future__ import annotations

from functools import cache

from asset_manifest import copy_picture, put_port
from common import ASSETS, EXTRACTED, ORIGINAL_SECTOR_COUNT, SCREENS, bundles, load_json, manifest, out_text
from pictures import UI_FOLDERS, home, problem_art_file, ui_file

# 2081-2090 (logical ids 863-872) are the original LEVEL EDITOR's interface art, not problem art: the toolbar (Tiles /
# Foes / Currnt / DAnim / MathTr, Bkgrd / Midgrd / Forgrd, Save / Egg / Done), the foe-script instruction palette
# (Goto ... ClrS: all 24 opcodes but YIELD) and the foe field labels. The shipped ONWIN32.EXE never loads them (the
# editor modules EDIT / EDITDECO / EDITFOES / EDITMATH were compiled out, see DESIGN "Authoring-tool remnants"), so the pack
# holds none of them: they stay in extracted/images/, and the sweep of loose problem art skips them.
AUTHORING_TOOL_IDS = list(range(2081, 2091))


PROBLEM_ART_SINGLE_README = """# Loose problem-screen pictures (written by tools/import/step_images.py)

Every NEP.DLL picture in ids 1780-2138 that belongs to no picture bundle (the bundles are the sibling `bNNN` folders)
and that no other part of the port owns. This is a sweep, not a list of what the port uses. Used by the port: 1780,
1803 (combination-lock face), 1864 and 1979 (problem-panel backgrounds, `problem_type_NN.tres`; the surface ship screen).

Files are called `<name>_<id>.png` (`surface_ship_1979.png`), or `pa_<id>.png` when nobody has named the picture (`docs/create/NAMES.md`, "Asset file names").

Each NEP.DLL picture is stored once, so pictures the story, title or finale-creature code owns are NOT repeated in
the sweep, here or in the `bNNN` folders: 1995-2001, 2012-2040 and 2055-2079 are the opening and closing sequences' art in
`assets/ui/story/`, 2041-2045 the sign-in scanner strips in `assets/ui/title/`, and 1980-1994 and 2002-2011 the Voyager and
Expert finale creatures in `assets/sprites/foes/foe_z5_*` and `foe_z6_*`. `tools/import/pictures.py` knows where each id
lives. 2080 is a red "CRASH SITE" arrow nobody has placed yet. The level editor's interface art (2081-2090) is not part of the pack
(`docs/port/DESIGN.md` section 16).

The pack's `pictures.json` names every one of them by key, including the ids whose file is kept elsewhere (an alias of the owner's key).
"""


def background_dll(bg_id: int) -> str:
    return "NEPBG1" if bg_id < 3180 else "NEPBG2"


@cache
def problem_art_index() -> dict[str, list[int]]:
    """Folder (`b041` ... `b118`, `single`) -> the picture ids of the problem art, including those whose file another role keeps (pictures.py). The bundles are 41 and
    77-118; `single` is every other picture of ids 1780-2138 (but the authoring tool's). Nothing is written: a pack names these pictures by key (picture_table.py)."""
    index: dict[str, list[int]] = {}
    in_bundle: set[int] = set()
    for b in [41] + list(range(77, 119)):
        ids = bundles()[str(b)]["frame_ids"] if str(b) in bundles() else []
        index["b%03d" % b] = ids
        in_bundle.update(ids)
    index["single"] = [i for i in range(1780, 2139)
                       if i not in AUTHORING_TOOL_IDS and i not in in_bundle and "NEP256:%d" % i in load_json(EXTRACTED / "images" / "manifest.json")]
    return index


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

    # Problem panel art: bundles 41 and 77-118 (picture ids 1780-2138) plus loose pictures in that id range that belong to no bundle
    # (`problem_art_index`). The PNG of an id that the story, title or finale-creature code owns (pictures.home) is not written again here.
    index = problem_art_index()
    for folder, ids in index.items():
        for i in ids:
            if home(i) is None:
                copy_picture(i, problem_art_file(folder, i))
    out_text(ASSETS / "problem_art" / "single" / "README.md", PROBLEM_ART_SINGLE_README)
    put_port(ASSETS / "problem_art" / "single" / "README.md", "tools/import/step_images.py", "text")
    print("  problem art: %d pictures in %d folders" % (sum(len(ids) for ids in index.values()), len(index)))
