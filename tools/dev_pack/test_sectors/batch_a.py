"""I7 batch A: test sectors 100-119 (and the campaign `test_a`, if a test needs one): ground: tiles, walls, currents, screens, sector data and its editors and checks.

This module is the batch's alone (tools/dev_pack/README.md): no other batch edits it and it edits no other batch's. `write_all` is called by
`make_dev_pack.py` (stage "data") after the dev tour. Make a sector with `dev_sectors.standard_sector` or `finale_sector`, change what the test
needs, and write it with `test_sectors.write_sector("a", spec)`, which refuses a number outside the range.

The sectors (numbers are offsets into 100-119; the tests name them in `godot/tests/engine/ground.gd`):

  100 main    the sector the editors and the checkers work on: 12 screens in a row, 11 pieces (the header's most; the canister is piece 0), six
              creatures (one dormant and hidden), math triggers, a ledge on screens 2, 5, 6 and 9, every kind of current on screen 7, an
              animated decoration on screen 4, a bubble-free zone-1 look.
  101 ledge   rock at chosen heights on screen 1, for the sub's wall box (the rightmost position at three heights, a ceiling to rest against,
              a piece behind a rock) and an overhang the sub's picture hangs under.
  102 map     twelve screens in a grid of four columns and three rows, every link two-way, shafts through the floors.
  103 finale  a sector whose finale starts on screen 2: creature 0 is the treasure, no pieces are asked for, screens 5-11 are never reached.
  104 tangle  the row of 12 screens with tables that do not lead back: screen 9 leads left to 5 (5 leads right to 6), screen 4 leads up to 8 (8 has no way
              down), and the row is a ring (screen 11 leads right to screen 0 and screen 0 left to 11). Not a sector to play: it is for the models of the maps.
  105 edit    what the sector editors add to and take from: seven pieces (room for four more), five creatures, a script that names two of them
              (`Put_Foe_To_Sleep foe_3` and `Wake_Foe foe_1` in the label creature 3 runs when it is touched).

Positions are window pixels (the playfield is 608 x 288 at (16, 32), a tile is 16 x 16); tile bytes are `wall(picture)`, `current(direction, strength)`, 0.
"""
from __future__ import annotations

import re
from pathlib import Path

import dev_sectors
import devlib
import test_sectors
from dev_sectors import Foe, ScreenSpec, SectorSpec, Trigger, current, wall
from devlib import tres

BATCH = "a"

MAIN, LEDGE, MAP, FINALE, TANGLE, EDIT = 100, 101, 102, 103, 104, 105

# The main sector's pieces: (screen, x, y); piece 0 is the data canister.
MAIN_PIECES = [(9, 480, 232), (0, 480, 200), (2, 300, 100), (3, 320, 180), (4, 256, 240), (6, 448, 160),
               (9, 400, 150), (7, 100, 240), (8, 160, 230), (10, 300, 200), (1, 350, 120)]
# The main sector's creatures: (screen, position); the last one starts dormant and hidden.
MAIN_CREATURES = [(4, (300, 250)), (7, (200, 250)), (10, (420, 250)), (1, (300, 250)), (2, (400, 250)), (1, (450, 250))]
MAIN_DORMANT = 5                        # the creature that sleeps, hidden, until the script wakes it
MAIN_HIDDEN = 2                         # a creature that starts hidden but awake; creature 4 starts mirrored
# An animated decoration: screen, position, the slots it shows one tick each, the size of its largest picture, the start in the list.
ANIM_SCREEN, ANIM_POS, ANIM_FRAMES, ANIM_SIZE, ANIM_START = 6, (200, 240), [0, 0, 0, 0, 1, 1, 1, 1], (64, 48), 2


def _anim_screen_tres(spec: ScreenSpec, anims: list[tuple[tuple[int, int], list[int], tuple[int, int], int]]) -> str:
    """The text of a screen like `dev_sectors.screen_tres`, with animated decorations (`dev_sectors` writes none). The sub resources come in the order the
    screen editor's writer uses (background, middle and front decorations, animated ones, triggers), numbered one after the other."""
    t = tres.Tres("Resource", "ScreenData", devlib.SCRIPTS + "screen_data.gd")
    ids = {n: t.ext_id("Script", devlib.SCRIPTS + n + ".gd") for n in ("deco_placement", "anim_deco_data", "math_trigger_data")}

    def decos(items: list) -> str:
        subs = [t.sub("Resource", [("pos", tres.vec2i(d.x, d.y)), ("slot", str(d.slot)), ("flag", tres.b(d.mirrored))],
                      script=devlib.SCRIPTS + "deco_placement.gd", prefix="Deco") for d in items]
        return tres.array('ExtResource("%s")' % ids["deco_placement"], subs)

    lists = {name: decos(getattr(spec, name)) for name in ("bg", "mid", "fg")}
    animated = [t.sub("Resource", [("pos", tres.vec2i(*pos)), ("frames", tres.packed_ints(frames)), ("size", tres.vec2i(*size)), ("start_cursor", str(start))],
                      script=devlib.SCRIPTS + "anim_deco_data.gd", prefix="Anim") for pos, frames, size, start in anims]
    triggers = [t.sub("Resource", [("pos", tres.vec2i(g.x, g.y)), ("slot", str(g.slot)), ("armed", tres.b(g.armed)),
                                   ("rearm_on_enter", tres.b(g.rearm)), ("test_nibble", str(g.nibble))],
                      script=devlib.SCRIPTS + "math_trigger_data.gd", prefix="Trigger") for g in spec.triggers]
    t.set("original_sector", "-1")
    t.set("original_screen", "-1")
    t.set("tiles", tres.packed_bytes(spec.tiles))
    t.set("bg_decos", lists["bg"])
    t.set("mid_decos", lists["mid"])
    t.set("fg_decos", lists["fg"])
    t.set("anim_decos", tres.array('ExtResource("%s")' % ids["anim_deco_data"], animated))
    t.set("triggers", tres.array('ExtResource("%s")' % ids["math_trigger_data"], triggers))
    return t.render()


def _patched_text(text: str, which: int, dormant: bool, hidden: bool) -> str:
    """Sets `dormant` / `hidden` on the creature number `which` in the text of a sector (`dev_sectors` writes every creature awake and visible)."""
    seen = [-1]

    def swap(match: re.Match) -> str:
        seen[0] += 1
        if seen[0] != which:
            return match.group(0)
        return "dormant = %s\nhidden = %s" % ("true" if dormant else "false", "true" if hidden else "false")

    return re.sub(r"dormant = (?:true|false)\nhidden = (?:true|false)", swap, text)


def _write(spec: SectorSpec, dev_root: Path, anim: dict[int, list] | None = None, sleepers: dict[int, tuple[bool, bool]] | None = None) -> int:
    """Writes the sector. Each file is written once, with its final text: `dev_sectors` makes the text of the screens and of the sector, so for this one
    write its two functions are wrapped (and put back), which keeps a second run of the generator from rewriting a file twice."""
    anim = anim or {}
    sleepers = sleepers or {}
    plain_screen, plain_sector = dev_sectors.screen_tres, dev_sectors.sector_tres

    def screen_text(screen: ScreenSpec) -> str:
        number = next(k for k, each in enumerate(spec.screens) if each is screen)
        return _anim_screen_tres(screen, anim[number]) if number in anim else plain_screen(screen)

    def sector_text(wanted: SectorSpec) -> str:
        text = plain_sector(wanted)
        for foe, (dormant, hidden) in sleepers.items():
            text = _patched_text(text, foe, dormant, hidden)
        return text

    dev_sectors.screen_tres, dev_sectors.sector_tres = screen_text, sector_text
    try:
        return test_sectors.write_sector(BATCH, spec, dev_root)
    finally:
        dev_sectors.screen_tres, dev_sectors.sector_tres = plain_screen, plain_sector


def _creatures(index: int, homes: list[tuple[int, tuple[int, int]]], first: int = 35) -> tuple[list[Foe], str]:
    foes = [Foe(s, pos, first, first, first + 1) for s, pos in homes]
    return foes, dev_sectors.patrol_script(index, first, first + 1, "Test sector of I7 batch A.") if foes else dev_sectors.NO_SCRIPT % index


def main_sector() -> SectorSpec:
    spec = dev_sectors.standard_sector(MAIN, zone=1, creatures=0)
    spec.pieces = list(MAIN_PIECES)
    spec.foes, spec.script = _creatures(MAIN, MAIN_CREATURES)
    spec.foes[4].flip = True                                                     # creature 4 starts mirrored
    spec.screens[6].fill(10, 11, 20, 11, dev_sectors.LEDGE)                      # a ledge on the midpoint screen, for the start-position checks
    # screen 6 (the midpoint, with the respawn point) holds one of everything the screen editor shows: two background decorations, two middle ones, a front
    # one, an animated one (below), a current, rock, a piece (5), an invisible wall and a math trigger
    spec.screens[6].mid.extend([dev_sectors.Deco(248, 250, 2), dev_sectors.Deco(300, 250, 3)])
    spec.screens[6].fg.append(dev_sectors.Deco(348, 256, 4))
    spec.screens[6].triggers.append(Trigger(500, 240, 13))
    spec.screens[6].fill(30, 3, 31, 3, 0x40)                                      # an invisible wall (tile byte 0x40: solid, no picture)
    # every direction at the weakest and the strongest strength, side by side on screen 7: one row of tiles each
    for direction in range(8):
        spec.screens[7].tiles[(2 + 2 * direction) * dev_sectors.COLUMNS + 3] = current(direction, 0)
        spec.screens[7].tiles[(2 + 2 * direction) * dev_sectors.COLUMNS + 4] = current(direction, 7)
    spec.screens[7].triggers.append(Trigger(300, 200, slot=12, nibble=4))        # a trigger that tests the sub's x (table entry 4)
    return spec


def ledge_sector() -> SectorSpec:
    """Screen 1 (the second of the row) has rock at three heights, for the sub's wall box. Columns and rows are tiles of the screen (16 x 16)."""
    spec = dev_sectors.standard_sector(LEDGE, zone=1, creatures=0)
    s = spec.screens[1]
    s.fill(30, 15, 30, 16, wall())                  # rock A: low, in the way of a sub that flies along the floor
    s.fill(24, 12, 31, 12, wall())                  # a ceiling over the floor: a sub resting against it
    s.fill(32, 13, 32, 14, wall())                  # rock B: higher, behind the ceiling's end
    s.fill(34, 9, 34, 11, wall())                   # rock C: higher still; a piece lies behind it
    # screen 2: a tunnel two tiles high (rows 14-15, the sub's wall box fits exactly) with a piece at its closed end, entered from the left
    t = spec.screens[2]
    t.tiles = bytearray(dev_sectors.COLUMNS * dev_sectors.ROWS)
    t.floor()
    t.fill(12, 13, 30, 13, wall())                  # the roof
    t.fill(31, 11, 31, 15, wall())                  # the closed end
    spec.pieces = [(3, 320, 180), (1, 566, 190), (2, 488, 268)]
    return spec


def map_sector() -> SectorSpec:
    """Twelve screens in four columns and three rows: screen = 4 * row + column, every link two-way, a shaft through each floor that has a way down."""
    spec = dev_sectors.standard_sector(MAP, zone=2, creatures=0)
    for m, screen in enumerate(spec.screens):
        row, col = divmod(m, 4)
        screen.tiles = bytearray(dev_sectors.COLUMNS * dev_sectors.ROWS)
        screen.floor()
        if row < 2:
            screen.fill(15, dev_sectors.ROWS - 2, 22, dev_sectors.ROWS - 1, 0)      # the shaft down
        screen.triggers.clear()
        spec.left[m] = m - 1 if col > 0 else -1
        spec.right[m] = m + 1 if col < 3 else -1
        spec.up[m] = m - 4 if row > 0 else -1
        spec.down[m] = m + 4 if row < 2 else -1
    spec.pieces = [(5, 320, 180), (10, 160, 230)]
    spec.foes, spec.script = _creatures(MAP, [(2, (300, 250)), (9, (200, 250))])
    return spec


def tangle_sector() -> SectorSpec:
    spec = dev_sectors.standard_sector(TANGLE, zone=3, creatures=0)
    spec.left[9] = 5                                # 5 leads right to 6, not back to 9
    spec.up[4] = 8                                  # 8 has no way down
    spec.right[11] = 0                              # a ring
    spec.left[0] = 11
    spec.foes, spec.script = _creatures(TANGLE, [(3, (300, 250))])
    return spec


def edit_sector() -> SectorSpec:
    spec = dev_sectors.standard_sector(EDIT, zone=2, creatures=0)
    spec.pieces = [(3, 320, 180), (8, 160, 230), (0, 480, 200), (1, 350, 120), (2, 300, 100), (4, 256, 240), (5, 448, 160)]
    homes = [(4, (300, 250)), (7, (200, 250)), (10, (420, 250)), (1, (300, 250)), (2, (400, 250))]
    spec.foes, spec.script = _creatures(EDIT, homes)
    spec.foes[3].hit = "tank_hit"
    spec.script += """
; creature 3 puts itself to sleep and wakes creature 1 when the sub touches it: the script names both ("foe_3", "foe_1"), so neither can be taken out
; of the sector without changing the script.
tank_hit:
    Play_Sound 3
    Put_Foe_To_Sleep foe_3
    Wake_Foe foe_1
    Return
"""
    return spec


def finale_test_sector() -> SectorSpec:
    spec = dev_sectors.standard_sector(FINALE, zone=4, creatures=0)
    spec.pieces = []
    spec.finale_screen = 2
    spec.right[4] = -1                              # screens 5-11 are never visited: no link leads to them (a finale does not need them)
    spec.left[5] = -1
    for screen in spec.screens[5:]:
        screen.triggers.clear()                     # (nobody could fire them)
    spec.foes, spec.script = _creatures(FINALE, [(2, (300, 250)), (4, (200, 250))])
    return spec


def write_all(dev_root: Path) -> int:
    """Writes this batch's sectors (and campaign) below `dev_root`; returns how many files were written or checked."""
    count = 0
    count += _write(main_sector(), dev_root, anim={ANIM_SCREEN: [(ANIM_POS, ANIM_FRAMES, ANIM_SIZE, ANIM_START)]}, sleepers={MAIN_DORMANT: (True, True), MAIN_HIDDEN: (False, True)})
    count += _write(ledge_sector(), dev_root)
    count += _write(map_sector(), dev_root)
    count += _write(finale_test_sector(), dev_root)
    count += _write(tangle_sector(), dev_root)
    count += _write(edit_sector(), dev_root)
    return count
