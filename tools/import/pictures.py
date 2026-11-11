"""Where each NEP.DLL picture lives under the legacy pack's assets/: ONE file per picture id.

The original stores every picture once, under one id. Several of our steps sweep overlapping id ranges (the story and
title art, the HUD lights, the finale foes' frames, the problem-panel art of ids 1780-2138), so without a rule the same
id would be written to more than one folder. This module is that rule, and the only place that knows it:

  * a picture a role owns lives in that role's folder: `assets/ui/<folder>/<name>_<id>.png` (story, title, hud, map, prompt)
    or, for the finale zones' creatures, `assets/sprites/foes/foe_z<zone>_<name>_<slot>.png` (an unnamed picture: `ui_<id>.png`,
    `foe_z<zone>_<slot>.png`; asset_names.py has the rule for the file names);
  * every other consumer (a SpriteFrames set, a problem type's `art_files`, a bundle folder of the problem art)
    points at that file instead of keeping a copy: `home(id)` says where it is, None if no role owns the id;
  * the problem art (`assets/problem_art/bNNN/<name>_<id>.png`, `.../single/...`; unnamed `pa_<id>.png`) is a blanket sweep of an id
    range, so it only holds the pictures nobody else owns. `data/problems/problem_art_index.json` still lists every
    id of every bundle; `problem_art_file` turns an id into the path.

The rule depends on the ids only, never on the order the steps run in, so `import_all.py --only <step>` agrees with a
full run. Claiming one id for two roles is an error (`homes` raises).
"""
from __future__ import annotations

from functools import cache
from pathlib import Path

from asset_names import foe_file, problem_art_folder_file, ui_file       # the file names: asset_names.py (re-exported here)
from common import FOE_ZONE_BASE, foe_slots

# Console art: the Game / Zone / Sector lettering, zone banners and the console bezel. The status lights (1007-1012),
# panel lights (1013-1015) and the rest of ids 1001-1038 are the opening cartoon's pictures and belong to the story.
HUD_IDS = list(range(1189, 1214))
# 1039-1057: title art and the sign-in frame. 2041-2045: the sign-in security scanner's light strips (bundle 115, 100x22).
TITLE_IDS = list(range(1039, 1058)) + list(range(2041, 2046))
MAP_IDS = [1000]
# 2412 / 2413: the prompt's sender icons (`LoadPromptSenderPicture` 0x423378): the research ship and the control room, 55 x 20.
SENDER_IDS = [2412, 2413]
# Opening cartoon (bundles 4 and 5: control room, crew, surface ship), the nine story pages and the Start / Intro
# buttons, and the closing sequences (helicopter-sub, crane, ship deck). All pictures of the story scenes.
# 1016-1027 and 1034-1038 are also the crew-walk, ship and spray sets of `fx_frames.tres`: they point here.
STORY_IDS = (list(range(1001, 1039)) + list(range(1995, 2002)) + list(range(2012, 2039)) + [2039, 2040]
             + list(range(2055, 2080)) + list(range(2420, 2424)))

# The creature sets of the two finale sectors (the Voyager and the Expert finale): their art is in the problem-art id range.
FINALE_ZONES = (5, 6)

# Folder name under assets/ui/ -> its picture ids (the order claims are checked in).
UI_FOLDERS: dict[str, list[int]] = {"hud": HUD_IDS, "title": TITLE_IDS, "map": MAP_IDS, "story": STORY_IDS,
                                    "prompt": SENDER_IDS}


@cache
def homes() -> dict[int, Path]:
    """Picture id -> the one file that holds it, for every id a role owns (all others: see `problem_art_file`)."""
    found: dict[int, Path] = {}

    def claim(pid: int, path: Path) -> None:
        if pid in found:
            raise ValueError("picture %d is claimed twice: %s and %s" % (pid, found[pid], path))
        found[pid] = path

    for folder, ids in UI_FOLDERS.items():
        for pid in ids:
            claim(pid, ui_file(folder, pid))
    # The finale zones' creatures (zones 5 and 6 of tools/analysis/data/sprite_slots.json) are pictures of bundles 110 and 112, which are
    # also in the problem-art id range.
    for zone in FINALE_ZONES:
        for slot, pid in enumerate(foe_slots(zone)[FOE_ZONE_BASE:], FOE_ZONE_BASE):
            claim(pid, foe_file(zone, slot))
    return found


def home(pid: int) -> Path | None:
    """The file of picture `pid` if a role owns it (so nothing else may write a copy), else None."""
    return homes().get(pid)


def problem_art_file(folder: str, pid: int) -> Path:
    """Where problem-art picture `pid` of `folder` ("b077", "single" ...) is: its owner's file, else the folder's own."""
    return home(pid) or problem_art_folder_file(folder, pid)
