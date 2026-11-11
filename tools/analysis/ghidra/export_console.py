"""The sub console and the calculator, transcribed from the Ghidra decompilation of ONWIN32.EXE.

Pure Python (no Ghidra, no CD needed to run). Writes tools/analysis/data/console_layout.json; the gauges themselves
(tanks, oxygen, ink pellets) are in hud_gauges.json (export_constants.py). Every number below was read from the
function named next to it (addresses of the 32-bit build), all coordinates are pixels of the 640 x 400 window:

  DisplayBezel          0x419eec  draws bezel picture 0 at (12, 324), then the gauges, the three labels, the
                                  message lights and last the frame (DisplayBezelFrame (0x41a3e8))
  DisplayBezelGameIcon (0x41a2e1) (game)   picture 2 + game number (Voyager 0 / Expert 1) at (472, 374); picture 1 "Cust" at (568, 374)
                        when the player customised the game
  DisplayBezelZoneIcon (0x41a341) (zone)   picture 6 + min(zone, 4) at (472, 352)
  DisplayBezelSectorIcon (0x41a380) (sector) picture 11 + sector % 3 at (472, 330); picture 14 ("Final") over it for sectors > 29
  DisplayShipMathIcon   0x419e4c: picture 21 / 22 (ship off / on) at (340, 330), 23 / 24 (computer off / on) at
                        (340, 364); plays sound 0x2f when either is lit
  DisplayBezelFrame (0x41a3e8) (frame)  the fills below, in this order; colour 0 = black, colour 8 = dark grey
  AddCalcHotspots (0x41aaf8)          AddHotspot(key, x, y, w, h) of every calculator key (mouse regions)
  GetAnswer 0x41ade0    calculator picture 0 of bundle 41 at (336, 266) (DoMathProblem 0x4207xx); without the
                        calculator the "Ans:" picture (item 21) at (332, 270); the display is drawn by
  DrawCalcDisplay (0x420b73)          clear (x0+24, y0, 148, 22), digits right to left from x0+160 (advance 16, picture y0+4),
                        '.' at (x+8, y0+12) without advancing, 'F' flag at (x0+12, y0+12); x0 = 352 with the
                        calculator, 416 without, y0 = 282. GetAnswer also draws the pending operator at
                        (352, 284) (items 17-20 = + - x /) and the memory marker (item 16) at (364, 284).
Bundle 41 item i is picture 1781 + i.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "tools" / "analysis" / "data" / "console_layout.json"

BLACK, GREY = 0, 8

# DisplayBezelFrame (0x41a3e8): (kind, colour, x, y, w, h). A vertical line is a 1 px wide rect, a horizontal line 1 px high.
_frame = []


def vline(colour, x, y, h):
    _frame.append(["rect", colour, x, y, 1, h])


def hline(colour, x, y, w):
    _frame.append(["rect", colour, x, y, w, 1])


def rect(colour, x, y, w, h):
    _frame.append(["rect", colour, x, y, w, h])


for x in (0, 1, 0x27e, 0x27f):
    vline(BLACK, x, 0, 0x18e)
for y in (0x18e, 399, 0, 1):
    hline(BLACK, 0, y, 0x280)
for y in (0x1e, 0x1f, 0x140, 0x141):
    hline(BLACK, 0xc, y, 0x268)
rect(BLACK, 0xc, 0x20, 5, 0x120)
rect(BLACK, 0x270, 0x20, 5, 0x120)
for x in (0xc, 0xd, 0xe, 0xf, 0x270, 0x271, 0x272, 0x273):
    vline(BLACK, x, 0x144, 0x48)
for y in (0x1a, 0x1b, 0x1c, 0x1d):
    hline(GREY, 2, y, 0x27c)
for y in (0x142, 0x143):
    hline(GREY, 0xc, y, 0x268)
rect(GREY, 0, 0x18c, 0x280, 5)
rect(GREY, 0, 0x1a, 0xc, 0x175)
rect(GREY, 0x274, 0x1a, 0xc, 0x175)
rect(GREY, 0, 0x16, 0x280, 5)
rect(BLACK, 0, 0, 0x280, 0x17)

# AddCalcHotspots (0x41aaf8): (key, x, y, w, h). Keys 2-6 and 0xd are the special buttons (see "special").
_hotspots = [
    (0x30, 0x218, 0x16c, 0x12, 0x14), (0x31, 0x218, 0x152, 0x12, 0x14), (0x32, 0x22e, 0x152, 0x12, 0x14),
    (0x33, 0x244, 0x152, 0x12, 0x14), (0x34, 0x218, 0x138, 0x12, 0x14), (0x35, 0x22e, 0x138, 0x12, 0x14),
    (0x36, 0x244, 0x138, 0x12, 0x14), (0x37, 0x218, 0x11e, 0x12, 0x14), (0x38, 0x22e, 0x11e, 0x12, 0x14),
    (0x39, 0x244, 0x11e, 0x12, 0x14), (0x2e, 0x22e, 0x16c, 0x12, 0x14), (0x2b, 0x25a, 0x16c, 0x12, 0x14),
    (0x2d, 0x25a, 0x152, 0x12, 0x14), (0x2a, 0x25a, 0x138, 0x12, 0x14), (0x2f, 0x25a, 0x11e, 0x12, 0x14),
    (0x3d, 0x244, 0x16c, 0x12, 0x14),
    (0xd, 0x15e, 0x16c, 0x56, 0x12), (2, 0x15e, 0x13c, 0x56, 0x12), (3, 0x15e, 0x154, 0x56, 0x12),
    (4, 0x1b8, 0x13c, 0x56, 0x12), (5, 0x1b8, 0x154, 0x56, 0x12), (6, 0x1b8, 0x16c, 0x56, 0x12),
]
# The button faces in the picture (Fract. / Store / Enter on the left, Neg. / Recall / Clear on the right) say which
# calculator key each special hotspot is: the model's keys are F, S, Enter, N, R, C.
_special = {0xd: "Enter", 2: "F", 3: "S", 4: "N", 5: "R", 6: "C"}


def key_name(code):
    return _special.get(code) or chr(code)


layout = {
    "_doc": (__doc__ or "").strip().split("\n\n")[0] + " Details in tools/analysis/ghidra/export_console.py.",
    "playfield": {"xy": [16, 32], "size": [608, 288]},
    "labels": {
        "game": {"xy": [472, 374], "first_pic": 2, "custom_pic": 1, "custom_xy": [568, 374]},
        "zone": {"xy": [472, 352], "first_pic": 6, "last_zone": 4},
        "sector": {"xy": [472, 330], "first_pic": 11, "final_pic": 14, "final_from_sector": 30},
    },
    "message_lights": {
        "ship": {"xy": [340, 330], "pic_off": 21, "pic_on": 22},
        "computer": {"xy": [340, 364], "pic_off": 23, "pic_on": 24},
        "sound": 0x2f,
        "note": "DetectMathTrigger (0x427744) -> trigger slot s: ship lit when 2 <= s <= 19 or s >= 60, computer lit when 20 <= s <= 59; "
                "touching the data canister (piece 1 in the original's numbering) lights the computer",
    },
    "frame": _frame,
    "frame_colours": {"0": "black", "8": "dark grey (VGA colour 8)"},
    "calculator": {
        "bundle": 41,
        "picture": {"item": 0, "xy": [336, 266]},
        "answer_panel": {"item": 21, "xy": [332, 270]},
        "keys": [{"key": key_name(c), "rect": [x, y, w, h]} for c, x, y, w, h in _hotspots],
        "display": {
            "x0_calculator": 352, "x0_answer": 416, "y0": 282,
            "clear_rect": [24, 0, 148, 22], "digits_right": 160, "digit_y": 4, "advance": 16,
            "point_xy": [8, 12], "fraction_flag_xy": [12, 12],
            "operator_xy": [352, 284], "memory_xy": [364, 284],
            "glyph_items": {"digit0": 1, "point": 11, "comma": 12, "slash": 13, "minus": 14,
                            "fraction_flag": 15, "memory": 16, "plus": 17, "subtract": 18, "multiply": 19,
                            "divide": 20},
        },
    },
}

if __name__ == "__main__":
    OUT.write_text(json.dumps(layout, indent=1) + "\n")
    print("wrote", OUT)
