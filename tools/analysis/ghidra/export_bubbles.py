"""Export the ambient bubbles (BUBBLES.C) and the bubble-like overlays that `DrawSub` puts on the sub to
extracted/tables/bubbles.json.

Pure Python (no Ghidra needed to run it): the constants below were read in the Ghidra decompilation of ONWIN32.EXE
(see `names_onwin32.json`), the tables are read straight from the EXE's data segment, and the frame order of each
bubble is DERIVED by running the original's little state machine here (so the JSON holds the result, not a guess).

The original (all [V]):

* `UpdateAmbientBubbles` (UpdateAmbientBubbles (0x41a800), called once per game frame by `DoAction` AFTER the animated decos, i.e. the
  bubbles are the front-most thing in the playfield) works on exactly TWO bubbles, each with its own state: active
  flag, x, y, picture, and (second one only) a direction flag. Nothing else about them is stored: there is no
  list and no count, so at most two bubbles exist at a time.
* The picture bundle is logical id 0x27, which `OTHR 15001` maps to real bundle 22 (8 pictures: 0-3 are thin
  "columns" 20-24 px wide, 4-7 are wider clusters 56-60 px wide). The art is ALREADY the "translucent" look: the
  pictures are drawn with `DrawPictureMasked` (colour 200 transparent), the pixels are a sparse pattern of the blue
  ramp (indices around 176-205) with transparent gaps, so the water shows through. No palette trick, no blending.
* Each tick, for each bubble that is NOT active: `rand() % 50 == 0` starts it (about 1 in 50 per tick, so a new
  bubble every ~4 s on average per slot). It starts at y = 0x140 = 320 (the bottom edge of the playfield, which
  spans window y 32..319), x = 0x1c + rand() % (0x248 - width), rounded DOWN to an even number (if the sum is odd
  the code uses r + 0x1b instead), with `width` = the width of the bubble's FIRST picture rounded down to even.
  A new bubble is drawn the same tick, but at y = 320 it is below the clip rectangle (nothing shows yet).
* Each tick, for each bubble that IS active: it moves up (y -= 10 for the first, y -= 6 for the second), steps its
  picture, and when `height(picture) + y < 0x20` (completely above the playfield's top row, window y 32) it is
  deactivated and not drawn. The x never changes.
* Picture stepping: the first bubble cycles 0,1,2,3,0,... The second goes 4,5,6,7 then back 6,5,4 then 5,6,7,...
  (its direction flag flips at 8 -> 6 and at 3 -> 5): the cycle after the first picture is 5,6,7,6,5,4.
* `ResetBubbles` (ResetBubbles (0x41a6fc)) clears both active flags. It runs when `DoAction` starts and on EVERY screen
  change (the five places where CurScreen changes), NOT after a math problem.
* The routine is skipped (and the bubbles are frozen) on four (sector, screen) pairs read from `NoBubbleScreens` (DS 0x441410):
  sector 0, screens 0-3. `DoAction` also never calls it in sector 30 (the Voyager finale, GetZone() == 5) on
  screens 1 and 2.
* Nothing in it looks at the oxygen, the sub, a hit or the creatures.

DrawSub (DrawSub (0x418a81)) draws two more overlays on the sub that look like the bubbles in the reference screenshots
(they are NOT part of the ambient system):

* HIT BUBBLES: while the invulnerability counter InvulnerabilityCounter (0x448684) > 22 (the first 8 of the 30 ticks after a creature
  hit), picture `(30 - counter) / 2 + 9` of the SUB bundle (15; pictures 9-12, 76 x 54) is drawn at
  (SubX + hit_x_by_cell[cell], SubY), mirrored like the sub (cells 0-3).
* MESSAGE LIGHT: while the countdown MessageLightCountdown (0x448688) (36 after touching a math trigger, 2 after picking up the
  data canister; it falls by 1 per drawn frame) is ODD and the cell is < 3 or > 5, picture 8 of the sub bundle
  (16 x 12, the blue beacon) is drawn, NOT mirrored, at (SubX + light_dx[cell], SubY + light_dy[cell]).
"""
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))   # gamefiles.py reads the CD image (NEPTUNE.ISO)
sys.path.append(str(ROOT / "tools" / "import"))   # common.py: where extracted/ and its tables/ are
import utf8_mode
utf8_mode.ensure()   # Windows: UTF-8 mode, like every entry point of the importer
import gamefiles
from common import EXTRACTED, TABLES
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else TABLES   # the importer passes common.TABLES
D = gamefiles.read("ONWINCD/ONWIN32.EXE")
pe = struct.unpack_from('<I', D, 0x3c)[0]
nsec = struct.unpack_from('<H', D, pe + 6)[0]
opt = pe + 24
szopt = struct.unpack_from('<H', D, pe + 20)[0]
base = struct.unpack_from('<I', D, opt + 28)[0]
secs: list[tuple[int, int, int, int]] = []
for _i in range(nsec):
    _o = opt + szopt + _i * 40
    _vs, _va, _rs, _rp = struct.unpack_from('<IIII', D, _o + 8)
    secs.append((_va, _vs, _rp, _rs))


def off(addr: int) -> int:
    r = addr - base
    for va, vs, rp, rs in secs:
        if va <= r < va + max(vs, rs):
            return rp + r - va
    raise KeyError(hex(addr))


def signed_bytes(addr: int, n: int) -> list[int]:
    o = off(addr)
    return list(struct.unpack_from('<%db' % n, D, o))


# --- the bubble picture bundle -------------------------------------------------------------------------------------
# Logical bundle 0x27 -> real bundle 22 through the id table (OTHR 15001, 16-bit entries indexed by logical id).
ID_TABLE = struct.unpack('<%dh' % 875, (EXTRACTED / "data/ONWIN32_resources/OTHR_15001.bin").read_bytes())
LOGICAL_BUNDLE = 0x27
REAL_BUNDLE = ID_TABLE[LOGICAL_BUNDLE]
assert REAL_BUNDLE == 22, REAL_BUNDLE
bundles = json.loads((EXTRACTED / "images/sprite_bundles.json").read_text())
frames = bundles[str(REAL_BUNDLE)]["frames"]
sizes = [(f["w"], f["h"]) for f in frames]
assert len(sizes) == 8

# --- the two bubbles' state machines, transcribed from UpdateAmbientBubbles (0x41a800) and RUN to get the picture orders ---------------
def first_bubble_pictures(ticks: int) -> list[int]:
    """Picture after each update tick (the spawn tick shows picture 0)."""
    pic, out = 0, [0]
    for _ in range(ticks):
        pic += 1                      # BubbleAPic (0x4486cc) = BubbleAPic + 1; if (3 < it) it = 0
        if pic > 3:
            pic = 0
        out.append(pic)
    return out


def second_bubble_pictures(ticks: int) -> list[int]:
    pic, up, out = 4, 1, [4]          # BubbleBPic (0x4486d0) = 4, BubbleBUp (0x4486d4) = 1 at spawn
    for _ in range(ticks):
        if up == 0:
            pic -= 1
            if pic < 4:
                pic, up = 5, 1
        else:
            pic += 1
            if pic > 7:
                pic, up = 6, 0
        out.append(pic)
    return out


a = first_bubble_pictures(40)
b = second_bubble_pictures(40)
# Loop part = what repeats after the first picture; check it really repeats.
A_LOOP = [1, 2, 3, 0]
B_LOOP = [5, 6, 7, 6, 5, 4]
assert a[1:] == (A_LOOP * 10)[:40]
assert b[1:] == (B_LOOP * 7)[:40]

SPAWN_CHANCE = 50                     # rand() % 0x32 == 0
START_Y = 0x140
TOP_Y = 0x20                          # inactive when height + y < 0x20
X_BASE = 0x1c
X_SPAN = 0x248                        # x = X_BASE + rand() % (X_SPAN - width)

out = {
    "_doc": "Ambient bubbles (BUBBLES.C: UpdateAmbientBubbles (0x41a800), ResetBubbles (0x41a6fc)) and the DrawSub "
            "overlays (DrawSub (0x418a81)) that look like bubbles. Read with tools/analysis/ghidra/export_bubbles.py. "
            "Positions are WINDOW pixels (the playfield's top-left is (16, 32)). All counts are game ticks (73/6 Hz). "
            "See that script's docstring for the original's rules.",
    "ambient": {
        "bundle": REAL_BUNDLE,
        "logical_bundle": LOGICAL_BUNDLE,
        "picture_sizes": [list(s) for s in sizes],
        "spawn_chance": SPAWN_CHANCE,
        "spawn_y": START_Y,
        "top_y": TOP_Y,
        "x_base": X_BASE,
        "x_span": X_SPAN,
        "max_bubbles": 2,
        "slots": [
            {"name": "column", "first_picture": 0, "rise_per_tick": 10, "loop": A_LOOP},
            {"name": "cluster", "first_picture": 4, "rise_per_tick": 6, "loop": B_LOOP},
        ],
        "no_bubble_screens": [[s, c] for s, c in zip(signed_bytes(0x441410, 8)[0::2], signed_bytes(0x441410, 8)[1::2])],
        "finale_no_bubble_sector": 30,
        "finale_no_bubble_screens": [1, 2],
        "reset_on": "game start, every screen change (not after a math problem)",
        "oxygen_or_hit_effect": False,
    },
    "sub_overlays": {
        "bundle": 15,
        "hit_bubbles": {
            "first_picture": 9, "picture_count": 4, "ticks": 8, "ticks_per_picture": 2,
            "x_by_cell": signed_bytes(0x44125f, 9), "y": 0, "mirrored_cells": [0, 1, 2, 3],
        },
        "message_light": {
            "picture": 8, "start_ticks_trigger": 36, "start_ticks_canister": 2,
            "dx_by_cell": signed_bytes(0x441268, 9), "dy_by_cell": signed_bytes(0x441271, 9),
            "cells": [c for c in range(9) if c < 3 or c > 5],
            "drawn_when": "countdown odd and (cell < 3 or cell > 5)", "mirrored": False,
        },
    },
}
OUT.mkdir(parents=True, exist_ok=True)
(OUT / "bubbles.json").write_text(json.dumps(out, indent=1) + "\n", newline="\n")
print("wrote", OUT / "bubbles.json")
