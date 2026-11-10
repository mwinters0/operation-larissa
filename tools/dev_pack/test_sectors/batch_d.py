"""I7 batch D: test sectors 160-179 (and the campaign `test_d`, if a test needs one): flow, campaigns, saves, story, sign-in, HUD.

This module is the batch's alone (tools/dev_pack/README.md): no other batch edits it and it edits no other batch's. `write_all` is called by
`make_dev_pack.py` (stage "data") after the dev tour. Make a sector with `dev_sectors.standard_sector` or `finale_sector`, change what the test
needs, and write it with `test_sectors.write_sector("d", spec)`, which refuses a number outside the range:

    spec = dev_sectors.standard_sector(160, zone=2, creatures=0)
    spec.screens[4].fill(10, 6, 20, 6, dev_sectors.wall())
    count += test_sectors.write_sector("d", spec, dev_root)

A campaign (`test_sectors.write_campaign("d", ...)`) shows in `Catalog.campaigns()` of every suite, so add one only when the test needs it.
"""
from __future__ import annotations

from pathlib import Path

import json

import dev_sectors
import test_sectors
from dev_sectors import Foe
import devlib

BATCH = "d"

# The sectors (the tests name them in `godot/tests/engine/dev_pack.gd`: `DevPack.test_sector("d", offset)`).
TREASURE_UP, TREASURE_HERE = 160, 161

# Texts of the pack that the engine reads as STRUCTURE (a word count, a line, a page), not as one name: dev's own texts for them. Everything else keeps
# the generator's rule (a text says its registry name). table -> {text number: text}. `dev_problems.write_all` writes them into the text tables.
def _lines(prefix: str, count: int) -> str:
    return "\n".join("%s %d" % (prefix, i + 1) for i in range(count))


STRUCTURED_TEXTS: dict[str, dict[int, str]] = {
    "ui_strings": {
        # The Hall of Fame's header: the view splits the first line into the three column headings.
        11124: "Name Level Tries\n\n\n\n\n\n\n\n\n\n",
        # The menus: one item to a line. File: sign in, hall of fame, exit. Options: four switches (hints, sound, music, voice) and the customization.
        # Help: seven topics. Math Practice's short menus: file (sign in, exit), options (sound, customization), help (practice, about).
        11053: _lines("Dev help topic", 7),
        11055: _lines("Dev file item", 3),
        11057: _lines("Dev options item", 5),
        11059: _lines("Dev practice help item", 2),
        11061: _lines("Dev practice file item", 2),
        11063: _lines("Dev practice options item", 2),
        # The sign-in screen's exit hotkey: the letters (upper and lower case) of Exit.
        11208: "Ee",
        # The surface ship's "pieces missing": \b + Ð is the number, \b + Ñ the plural "s" (empty for one piece).
        11212: "Dev surface ship message:\nThe magnetometer sees \u0008\u00d0 piece\u0008\u00d1 still out in this sector. Out.",
    },
}

# Dev's durations (`rules/durations.json` of the pack, laid over the project's base file key by key: docs "Durations"). Only the keys that tests of batch D read
# are dev's own so far (the launch and the dock; the balloon's rise is asserted by tests of batch B, so it stays the base's); the rest (dissolve, log scan, message, silent speech, key flash, surface-ship wait) read the base file until the tests of the batches
# that own them move. Geometry (the stations' x and y) is kept, since it belongs to the art; the tick counts and speeds are dev's.
DURATIONS = {
    "_about": "Dev pack: its own lengths, in ticks of the 73 Hz timer (a station trip: ticks of the 12.17 Hz game clock). A key left out keeps the base file's number.",
    "station": {
        "launch": {"opening_ticks": 2, "closing_ticks": 2, "from_x": 0, "to_x": 96, "pixels_per_tick": 4},
        "dock": {"opening_ticks": 4, "closing_ticks": 2, "from_x": 352, "to_x": 452, "pixels_per_tick": 5},
    },
    "sign_in": {"pre_scan_ticks": 20, "pressed_ticks": 30, "scan_ticks_per_picture": 4, "scan_sweeps": 5},
    "news": {"speech_start_delay_ticks": 200, "group_pauses": [0, 200, 200, 200, 0]},
    "fade": {"ticks": 10},
}

TREASURE_SCRIPT = """; Dev pack - sector %02d. %s
; The treasure: a creature that does no damage; when the sub touches it, it sets flag 15, which the game reads: with the sub on the
; sector's finale screen (header field finale_screen) the closing sequence starts. docs/create/FOE_SCRIPTING.md, "The finale: bit 15".

treasure_start:
    Set_Frame 35
treasure_idle:
    Wait_Next_Tick
    Jump_To treasure_idle

treasure_hit:
%s    Set_Flag 15
    Play_Sound 3
treasure_stuck:
    Wait_Next_Tick
    Jump_To treasure_stuck

treasure_ink:
    Return
"""


def treasure_sector(index: int, finale_screen: int, treasure_screen: int, hides: bool, comment: str) -> dev_sectors.SectorSpec:
    """A finale sector: the standard one, with one treasure creature on `treasure_screen` and the closing starting on `finale_screen`."""
    spec = dev_sectors.standard_sector(index, 4, creatures=0, finale=True, comment=comment)
    spec.foes = [Foe(treasure_screen, (300, 250), 35, 35, 36, damage=0, start="treasure_start", hit="treasure_hit", ink="treasure_ink")]
    spec.script = TREASURE_SCRIPT % (index, comment, "    Hide_Foe\n" if hides else "")
    spec.finale_screen = finale_screen
    return spec


def write_durations(dev_root: Path) -> int:
    """`rules/durations.json` of the pack."""
    devlib.write_text(dev_root / "rules" / "durations.json", json.dumps(DURATIONS, indent=2) + "\n")
    return 1


def write_all(dev_root: Path) -> int:
    """Writes this batch's sectors (and campaign) below `dev_root`; returns how many files were written or checked."""
    count = write_durations(dev_root)
    # 160: the closing starts on screen 2 and the treasure is on screen 4 (hidden once touched), so the sub must swim back up with the flag set.
    count += test_sectors.write_sector("d", treasure_sector(TREASURE_UP, 2, 4, True, "The closing starts on screen 2; the treasure is on screen 4."), dev_root)
    # 161: the treasure is on the finale screen itself (10) and stays visible: the closing starts on the next tick after the touch.
    count += test_sectors.write_sector("d", treasure_sector(TREASURE_HERE, 10, 10, False, "The treasure is on the finale screen, 10."), dev_root)
    return count
