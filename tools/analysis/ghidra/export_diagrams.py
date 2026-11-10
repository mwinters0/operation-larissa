"""Export how the original DRAWS each math problem (type 0-33) to docs/data/problem_diagrams.json.

No Ghidra needed to run this: the geometry below was transcribed from the decompiled
`DrawProblemDiagram` (0x424f3d) and the `ProbNN_Diagram` functions of ONWIN32.EXE
(docs/port/DESIGN.md 5.5), with the x87 maths read from the disassembly (`dump_asm.py`), and every
lookup table is read straight from the EXE.

    uv run tools/analysis/ghidra/export_diagrams.py

All coordinates are WINDOW pixels of the 640 x 400 screen (the original draws into an 8-bit
back buffer of that size). `pic` numbers index the type's picture bundle (item 0 is the panel).
The vocabulary of the "items" lists is documented in godot/src/problems/diagrams/diagram_base.gd.

Two more keys describe the ANIMATIONS (DESIGN 5.5, "Build-up animations"): "intro" is how the original builds the diagram
up in front of the player (DrawProblemDiagram runs the Prob*_Diagram function, which draws, plays a sound and DelayTicks
between the steps), "success" is what ShowSuccessMessage replays after a right answer. Items of the "items" list that appear
one by one are marked "animate": true; the constants are in ticks of 1/73 s. The modes are explained in DiagramBase.
"""
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))   # gamefiles.py reads the CD image (NEPTUNE.ISO)
import gamefiles
D = gamefiles.read("ONWINCD/ONWIN32.EXE")
_pe = struct.unpack_from('<I', D, 0x3c)[0]
_nsec = struct.unpack_from('<H', D, _pe + 6)[0]
_opt = _pe + 24
_szopt = struct.unpack_from('<H', D, _pe + 20)[0]
_base = struct.unpack_from('<I', D, _opt + 28)[0]
_secs = []
for _i in range(_nsec):
    _o = _opt + _szopt + _i * 40
    _vs, _va, _rs, _rp = struct.unpack_from('<IIII', D, _o + 8)
    _secs.append((_va, _vs, _rp, _rs))


def _off(a):
    r = a - _base
    for va, vs, rp, rs in _secs:
        if va <= r < va + max(vs, rs):
            return rp + r - va
    raise KeyError(hex(a))


def arr(a, n, fmt="B"):
    """n values of struct format `fmt` at virtual address `a` of the EXE."""
    return list(struct.unpack_from("<%d%s" % (n, fmt), D, _off(a)))


def triples(a, n):
    """n (x, y, flip) byte triples."""
    flat = arr(a, 3 * n)
    return [flat[i:i + 3] for i in range(0, 3 * n, 3)]


def pairs(xs, ys):
    return [[x, y] for x, y in zip(xs, ys)]


def interleaved(a, n):
    """n (x, y) byte pairs stored one after the other."""
    flat = arr(a, 2 * n)
    return [flat[i:i + 2] for i in range(0, 2 * n, 2)]


PANEL = {"pic": 0, "pos": [16, 58]}      # nearly every type draws its panel picture here


def opaque(item):
    """The original draws a few panels with the opaque blitter (DrawPicture (0x41262a)) instead of the masked one."""
    return dict(item, opaque=True)


types = {}

types[1] = {
    "source": "do_access_opening 0x417dd8",
    "family": "items",
    "items": [opaque(PANEL)]
    + [{"text": {"field": i}, "box": [x, 40], "y": 178} for i, x in enumerate((0x2c, 0x62, 0x98, 0xce))]
    + [{"pic": 1, "pos": [0x114, 0xb0]}],
}

types[2] = {
    "source": "Prob02_Diagram 0x432234 (+ Prob02_AnimateBar 0x4321cb: one 24x26 segment per 5 mph)",
    "family": "items",
    "items": [PANEL] + [
        {"pic": 1, "pos": [x, 226], "animate": True, "repeat": {"count": {"field": i, "divisor": 5}, "step": [0, -26]}}
        for i, x in enumerate((0x5c, 0x80, 0xa4, 200, 0xec, 0x110))],
    # Prob02_AnimateBar: per segment set_alarm(6) + PlaySoundEffect(0x22) + draw + wait_alarm; Prob02_Diagram: DelayTicks(30)
    # after each of the first five bars (even an empty one), none after the last
    "intro": {"mode": "bars", "sfx": 0x22, "interval": 6, "gap": 30},
}

_blip = arr(0x443068, 5), arr(0x44306d, 5)
_sweep = arr(0x443050, 24)
types[3] = {
    "source": "Prob03_Diagram 0x431b7d, RadarSweep 0x431a0f, RadarBlip 0x4319ad",
    "family": "sonar",
    "items": [{"pic": 0, "pos": [0x14, 0x3a]}],
    # the sweeping beam: 12 steps around the dial (bundle pictures 2-8, mirrored for the left half). The original
    # runs it twice and ends on step 0 (straight up) with the blip showing.
    "sweep": {"pics": arr(0x443044, 12), "pos": pairs(_sweep[0::2], _sweep[1::2]), "mirror_from": 7,
              "ticks_per_step": 6, "revolutions": 2},
    "blip": {"pic_frames": [9, 10, 11], "ticks_per_frame": 2, "field": 0, "divisor": 5, "clamp": [0, 4],
             "pos": pairs(*_blip),
             # the sweep step at which the blip is shown, per row (RadarBlipStep (0x443072); all 0 = beam straight up). RadarBlip (0x4319ad)
             # plays sound 0x29 each time it draws the blip: at that step of both turns and once more after them.
             "step": arr(0x443072, 5), "sfx": 0x29},
}

types[4] = {
    "source": "Prob04_Diagram 0x420e83 (the pressure line appears segment by segment)",
    "family": "items",
    "items": [opaque(PANEL)] + [
        {"pic": 1 + k, "pos": [x, y], "animate": True}
        for k, (x, y) in enumerate(zip(arr(0x441c64, 4, "I"), arr(0x441c74, 4, "I")))],
    # per piece: set_alarm(0, 15), draw, FlushRect, PlaySoundEffect(0x23), wait_alarm(0): the panel and the first piece appear
    # together, the function returns 15 ticks after the last piece
    "intro": {"mode": "sequence", "sfx": 0x23, "interval": 15, "trailing": True},
}

types[5] = {
    "source": "Prob05_Diagram 0x42c380",
    "family": "items",
    "items": [PANEL] + [
        {"pic": 1 + k, "pos": [x, y], "animate": True}
        for k, (x, y) in enumerate(zip(arr(0x442c88, 6, "I"), arr(0x442ca0, 6, "I")))],
    "intro": {"mode": "sequence", "sfx": 0x23, "interval": 15, "trailing": True},
}

types[6] = {
    "source": "Prob06_Diagram 0x431c23 (string 11250 = '5000')",
    "family": "items",
    "items": [opaque(PANEL),
              {"pic": 1, "pos": [0xe8, 0xd2]},
              {"text": {"literal": "5000"}, "box": [0xd6, 0x2c], "y": 0x6e},
              {"text": {"field": 0}, "box": [0xd6, 0x2c], "y": 0xa4}],
    # Prob06_SuccessAnimation (0x431d18): no sound, no delay: picture 2 over the "?" and the answer f2 under the scale
    "success": {"mode": "overlay", "items": [{"pic": 2, "pos": [0xe8, 0xd2]},
                                             {"text": {"field": 2}, "box": [0xd6, 0x2c], "y": 0xd8}]},
}

types[7] = {
    "source": "Prob07_Diagram 0x41b933",
    "family": "items",
    "items": [PANEL,
              {"pic": 1, "pos": [0xb8, 0x60], "when": {"levels": [0, 2]}},
              {"pic": 2, "pos": [0xb8, 0x60], "when": {"levels": [1, 3]}}]
    + [{"text": {"field": i}, "box": [0xa8, 0x74], "y": y, "animate": True} for i, y in enumerate((0x8e, 0xaa, 0xc6, 0xe2, 0xfe))],
    # DrawText + PlaySoundEffect(0x22) for a value, DelayTicks(30) before the next; nothing after the fifth
    "intro": {"mode": "sequence", "sfx": 0x22, "interval": 30, "trailing": False},
}

# depth gauge: f0 (0 ft->in, 1 ft->yd, 2 fathom->ft, 3 m->km, 4 ft->fathom) picks a picture
# (0x441b72[0x441b6c[f0]]) and the number of 128x16 marks is depth / divisor (0x441b78[...])
_k = arr(0x441b6c, 5)
_pic_by_kind = arr(0x441b72, 3)
_div_by_kind = arr(0x441b78, 3, "I")
types[8] = {
    "source": "Prob08_Diagram 0x41eacf",
    "family": "items",
    "items": [opaque(PANEL),
              opaque({"pic": {"field": 0, "table": [_pic_by_kind[k] for k in _k]}, "pos": [0xc0, 0x3a]}),
              {"pic": 4, "pos": [0x40, 0x50],
               "repeat": {"count": {"field": 1, "divisor_table": {"field": 0, "table": [_div_by_kind[k] for k in _k]}},
                          "step": [0, 18]}}],
}

types[9] = {
    "source": "Prob09_Diagram 0x422f64 (x87 maths read from the disassembly)",
    "family": "nav_chart",
    "items": [opaque(PANEL), {"pic": 1, "pos": [0x30, 0x11a]}, {"pic": 2, "pos": [0xe4, 0x11a]}],
    # x = (trunc((lon_origin - lon) * lon_scale) + offset_x) * zoom,  y = (trunc((lat - lat_origin) * lat_scale) + offset_y) * zoom
    "map": {"lon_origin": 180.0, "lon_scale": 20.0, "lat_origin": 20.0, "lat_scale": 9.0,
            "offset": [0x2b, 0x29], "zoom": 2},
    # picture 1 is the red "Station" of the legend (record f1 longitude, f2 latitude), picture 2 the purple "Sub"
    # (f3, f4): the solution text subtracts f3 from f1, "{3} - {2}" = station minus sub
    "markers": [{"pic": 2, "lon_field": 3, "lat_field": 4},
                {"pic": 1, "lon_field": 1, "lat_field": 2}],
}

types[10] = {
    "source": "Prob10_Diagram 0x4211e1 (one loose picture; string 11251 = degree sign + 'C')",
    "family": "items",
    "items": [PANEL] + [{"text": {"field": i, "suffix": "°C"}, "box": [0xce, 0x5c], "y": y}
                        for i, y in enumerate((0x6c, 0xa4, 0xd2))],
}

types[11] = {
    "source": "Prob11_Diagram 0x42de8b",
    "family": "items",
    "items": [PANEL,
              {"pic": {"field": 1, "add": 3}, "pos": [0x5c, 0x5e]},
              {"pic": {"field": 2, "add": 6}, "pos": [0x58, 0x9e]},
              {"pic": 1, "pos": [0xdc, 0xc4]},
              {"text": {"field": 0, "format": "int"}, "box": [200, 0x3a], "y": 0x72}],
    # Prob11_SuccessAnimation (0x42df92): picture 2 over the "?" and the answer f3 (itoa) under it, no sound, no delay
    "success": {"mode": "overlay", "items": [{"pic": 2, "pos": [0xdc, 0xc4]},
                                             {"text": {"field": 3, "format": "int"}, "box": [200, 0x3a], "y": 0xc6}]},
}

# thermometers: the mercury is a column of 12x16 pictures (3), one per 5 degrees plus the one at the bulb
types[12] = {
    "source": "Prob12_Diagram 0x41f962, AnimateThermometerColumn 0x41f813",
    "family": "items",
    "items": [PANEL, {"pic": 2, "pos": [0x98, 0x112]},
              {"pic": 3, "pos": [0xa0, 0x102], "animate": True,
               "repeat": {"count": {"field": 0, "add": 15, "divisor": 5, "extra": 1}, "step": [0, -16]}}],
    # Prob12_Diagram (0x41f962): panel and bulb, DelayTicks(30), AnimateThermometerColumn (0x41f813) plays 0x25 and adds one
    # 16 px piece of mercury every 10 ticks, StopCommonSoundEffect, DelayTicks(60)
    "intro": {"mode": "run", "sfx": 0x25, "lead": 30, "interval": 10, "trail": 60},
    # AnimateThermometerSolution (0x41f8e3): DelayTicks(73), then the column goes from f0 to the answer f2 (signed bytes):
    # up = pic 3 pieces from the old top upwards (|f2 - f0| / 5 + 1 pieces), down = pic 4 (dark tube) pieces from the old top
    # downwards (|f2 - f0| / 5 pieces), 10 ticks each, sound 0x25 meanwhile, DelayTicks(30)
    "success": {"mode": "thermometer", "sfx": 0x25, "lead": 73, "interval": 10, "trail": 30,
                "from_field": 0, "to_field": 2, "offset": 15, "divisor": 5, "rise_pic": 3, "erase_pic": 4,
                "x": 0xa0, "y0": 0x102, "step": 16},
}

types[13] = {
    "source": "Prob13_Diagram 0x41f9f4 (f2 = 0: given in F; 1: given in C, which also shows the Celsius scale picture)",
    "family": "items",
    "items": [PANEL, {"pic": 2, "pos": [0x98, 0x112]},
              {"pic": 1, "pos": [100, 0x44], "when": {"field": 2, "ne": 0}},
              {"pic": 3, "pos": [0xa0, 0x102], "when": {"field": 2, "eq": 0}, "animate": True,
               "repeat": {"count": {"field": 0, "add": 15, "divisor": 5, "extra": 1}, "step": [0, -16]}},
              {"pic": 3, "pos": [0xa0, 0x102], "when": {"field": 2, "ne": 0}, "animate": True,
               "repeat": {"count": {"field": 0, "add": 35, "divisor": 5, "extra": 1}, "step": [0, -16]}}],
    # Prob13_Diagram (0x41f9f4): the same build-up as type 12 (30 ticks, mercury, 60 ticks); no success animation
    "intro": {"mode": "run", "sfx": 0x25, "lead": 30, "interval": 10, "trail": 60},
}

_barn = interleaved(0x442a24, 20)
types[14] = {
    "source": "do_ccmonitor_opening 0x427b10, AnimateBarnacles 0x4278dc",
    "family": "barnacles",
    "items": [{"pic": 0, "pos": [0x14, 0x3c]}, {"pic": 1, "pos": [0x24, 0x48]}, {"pic": 2, "pos": [0x24, 0x10a]}],
    # the first `unhealthy` positions get picture 3; the rest alternate the two healthy pictures (first half 4, second half 5,
    # then swapped) 3 times, 30 and 40 ticks apart (73 ticks per second)
    "barnacle": {"total_field": 0, "unhealthy_field": 1, "unhealthy_pic": 3, "healthy_pics": [4, 5],
                 "pos": _barn, "ticks": [30, 40], "rounds": 3},
    # AnimateBarnacles (0x4278dc): at the start of each of the 3 rounds PlaySoundEffect(0x24) is called once for EVERY healthy
    # barnacle (back to back, no delay: the single wave device is restarted by each call, so one 0x24 is heard); then
    # DelayTicks(30), the pictures swap, DelayTicks(40). do_ccmonitor_opening (0x427b10) adds DelayTicks(20) before the prompt.
    "intro": {"sfx": 0x24, "tail": 20},
}

types[15] = {
    "source": "Prob15_Diagram 0x42e2a6",
    "family": "items",
    "items": [PANEL, {"pic": 1, "pos": [0x10, 0x108]},
              {"text": {"field": 0}, "box": [0x76, 0x6a], "y": 0x11c}],
}

types[16] = {
    "source": "Prob16_Diagram 0x421595 (levels 0-1 show one leg, levels 2-3 two legs)",
    "family": "items",
    "items": [opaque(PANEL),
              {"text": {"field": 0, "format": "int"}, "box": [0x34, 0x3c], "y": 0x9e},
              {"text": {"field": 6}, "box": [0x74, 0x4c], "y": 0x9e},
              {"pic": 2, "pos": [0xe4, 0x9c], "when": {"levels": [0, 1]}},
              {"text": {"field": 1, "format": "int"}, "box": [0x34, 0x3c], "y": 0xce, "when": {"levels": [2, 3]}},
              {"text": {"field": 7}, "box": [0x74, 0x4c], "y": 0xce, "when": {"levels": [2, 3]}},
              {"pic": 1, "pos": [0x3c, 0xfe], "when": {"levels": [2, 3]}},
              {"pic": 2, "pos": [0xe4, 0x104], "when": {"levels": [2, 3]}}],
    # Prob16_SuccessAnimation (0x4213f5): the answer box (picture 3, opaque) over picture 2 with the distances and the total
    # (f8, f9, f10; levels 0-1 only the total f10); no sound, no delay
    "success": {"mode": "overlay", "items": [
        {"pic": 3, "pos": [0xe4, 0x9c], "when": {"levels": [0, 1]}},
        {"text": {"field": 10}, "box": [0xc4, 100], "y": 0x9e, "when": {"levels": [0, 1]}},
        {"pic": 3, "pos": [0xe4, 0x104], "when": {"levels": [2, 3]}},
        {"text": {"field": 8}, "box": [0xc4, 100], "y": 0x9e, "when": {"levels": [2, 3]}},
        {"text": {"field": 9}, "box": [0xc4, 100], "y": 0xce, "when": {"levels": [2, 3]}},
        {"text": {"field": 10}, "box": [0xb8, 0x70], "y": 0x104, "when": {"levels": [2, 3]}}]},
}

types[17] = {
    "source": "Prob17_Diagram 0x42bfcc; the slice pictures are fixed art, only the order of the foods is random",
    "family": "pie",
    "items": [opaque({"pic": 0, "pos": [0x52, 0x4c]})],
    # legend row r (green, purple, orange) names food (rotation + r) % 3; rotation = rand() % 2.
    # Food names are texts 16.. of the type's text bundle (13.. are the lower case forms used in the sentences).
    "legend": {"text_base": 16, "pos": [[0x86, 0xe2], [0x86, 0xf8], [0x86, 0x10e]], "rotations": 2},
    # record field f0 picks the pie: 0 = thirds, 1 and 2 = half, quarter, quarter
    "layouts": {"0": [{"pic": 4, "pos": [0x6a, 0x4c]}, {"pic": 5, "pos": [0xaa, 0x4c]}, {"pic": 6, "pos": [0x6a, 0x82]}],
                "default": [{"pic": 1, "pos": [0x6a, 0x4c]}, {"pic": 2, "pos": [0xaa, 0x4c]}, {"pic": 3, "pos": [0xaa, 0x84]}]},
    # legend row of each slice colour (green = 0, purple = 1, orange = 2) and its share of the pie [numerator, denominator]
    "shares": {"0": [[1, 3], [1, 3], [1, 3]], "default": [[1, 4], [1, 4], [1, 2]]},
    # the panel and the legend appear at once, then each slice: draw, PlaySoundEffect(0x29), DelayTicks(88) (also after the last)
    "intro": {"mode": "sequence", "sfx": 0x29, "interval": 88, "trailing": True},
}

types[18] = {
    "source": "do_oil_supply_opening 0x428c9a",
    "family": "items",
    "items": [{"pic": 0, "pos": [0x14, 0x3a]},
              {"pic": 1, "pos": [0x4c, 0xaa], "repeat": {"count": {"field": 0}, "step": [0x14, 0]}},
              {"text": {"field": 1, "format": "int"}, "right": 0xac, "y": 0x66}],
}

types[19] = {
    "source": "Prob19_Diagram 0x41d2d3",
    "family": "ruler",
    "items": [{"pic": 0, "pos": [0x14, 0x3c]},
              {"pic": 1, "pos": [0x28, 0xb8], "when": {"field": 0, "lt": 2}},
              {"pic": 2, "pos": [0x28, 0xb8], "when": {"field": 0, "ge": 2}}],
    # the crack is a 2 px black line above the ruler from end A (f2) to end B (f1); 12 px per ruler unit
    # (f0: 0 inch and 1 quarter inch -> quarters, 2 decimal cm -> mm, 3 mm)
    "crack": {"from_field": 2, "to_field": 1, "unit_field": 0, "units_per_value": [4, 4, 10, 1],
              "x0": 0x32, "px_per_unit": 12, "y": [0xb2, 0xb1], "color": 0},
}

types[20] = {
    "source": "Prob20_Diagram 0x4330a7 (a 60x8 slice per 100 ppm; left bar f1, right bar f0)",
    "family": "items",
    "items": [{"pic": 0, "pos": [0x10, 0x3c]},
              {"pic": 1, "pos": [0x90, 0xf6], "animate": True,
               "repeat": {"count": {"field": 1, "divisor": 100, "round": "ceil"}, "step": [0, -8]}},
              {"pic": 2, "pos": [0xe4, 0xf6], "animate": True,
               "repeat": {"count": {"field": 0, "divisor": 100, "round": "ceil"}, "step": [0, -8]}}],
    # each pass adds a slice to each bar that still has one, PlaySoundEffect(0x22), DelayTicks(10); as long as either bar has slices left
    "intro": {"mode": "lockstep", "sfx": 0x22, "interval": 10},
}

types[21] = {
    "source": "Prob21_Diagram 0x43378d (strings 11213 ' liters' / 11214 ' gallons')",
    "family": "tank",
    "items": [{"pic": 0, "pos": [0x10, 0x38]}],
    # f0 (liters) = 0 means the supply is given in gallons (f2)
    "quantity": {"liters_field": 0, "gallons_field": 2, "scale_pos": [0x6c, 0x10e],
                 "liters": {"pic": 2, "unit": " liters"}, "gallons": {"pic": 1, "unit": " gallons"}},
    "tank": {"front_pic": 4, "front_pos": [0x60, 0xe0], "water_pic": 3, "water_x": 0x60, "water_y0": 0xd0,
             "water_step": -2, "frames_per_unit": 3, "frames_minus": 7, "rim_pic": 5, "rim_pos": [0x5c, 0x5e],
             "label_x": 0x7c, "label_y_add": 0x108},
    # PlaySoundEffect(0x28) once, then per water frame set_alarm(0, 6) + draw + wait_alarm; StopCommonSoundEffect and the label
    # when the tank is full (the effect is NOT looped in the 32-bit build, RepeatCommonSoundEffect has the same body)
    "intro": {"sfx": 0x28, "interval": 6},
}

types[22] = {
    "source": "Prob22_Diagram 0x420f71, Prob22_AngleToPicture 0x420fe7 / Prob22_AngleMirror 0x421046",
    "family": "items",
    "items": [{"pic": 0, "pos": [0x10, 0x3c]},
              {"pos": [0x88, 0x98],
               "lookup": {"field": 1, "divisor": 45, "exact": True, "entries": [
                   {"pic": 1}, {"pic": 2}, {"pic": 3}, {"pic": 4}, {"pic": 5},
                   {"pic": 4, "flip": True}, {"pic": 3, "flip": True}, {"pic": 2, "flip": True}]}}],
    # Prob22_SuccessAnimation (0x42108d): the needle turns from the present heading f1 in 45 degree steps (f2 = 0 port: down,
    # else starboard: up; 360 wraps to 0 and below 0 to 315) until it points at the answer f3: per picture the panel is redrawn,
    # PlaySoundEffect(0x29), DelayTicks(22); one more DelayTicks(22) at the end
    "success": {"mode": "heading", "sfx": 0x29, "interval": 22, "trail": 22, "angle_step": 45,
                "start_field": 1, "direction_field": 2, "end_field": 3, "wrap_to": 315},
}

types[23] = {
    "source": "Prob23_Diagram 0x42f0f9 (f2 = 1 mirrors the picture)",
    "family": "items",
    "items": [{"pic": 0, "pos": [0x14, 0x3a]}, {"pic": 3, "pos": [0x84, 0xa0], "flip_field": 2}],
    # Prob23_SuccessAnimation (0x42f163): DelayTicks(22), panel + picture 2 + PlaySoundEffect(0x29), DelayTicks(22),
    # panel + picture 1 + PlaySoundEffect(0x29), DelayTicks(44); both pictures mirrored when f2 = 1
    "success": {"mode": "pictures", "sfx": 0x29, "pos": [0x84, 0xa0], "flip_field": 2,
                "frames": [{"tick": 22, "pic": 2}, {"tick": 44, "pic": 1}], "end": 88},
}

_clock = triples(0x441544, 13)
_clock_pic = arr(0x44156b, 13)
types[24] = {
    "source": "Prob24_Diagram 0x41c060 (only the hour is used: hhmm -> hour of a 12 hour clock)",
    "family": "items",
    "items": [PANEL, {"pic": 1, "pos": [0xac, 0x58]},
              {"lookup": {"field": 3, "pre": "hour12", "entries": [
                  {"pic": p, "pos": [x, y], "flip": bool(f)} for p, (x, y, f) in zip(_clock_pic, _clock)]}}],
}

_gy = arr(0x4431b4, 6, "I")
_gx = arr(0x4431cc, 8, "I")
types[25] = {
    "source": "Prob25_Diagram 0x4331d7",
    "family": "line_graph",
    "items": [PANEL],
    # seven readings f0..f6 (ppm); grid level = ppm / 400; y_by_level = window y of each 400 ppm line.
    # Reading k: a 24 px segment at x_by_step[k] (flat, rising or falling from the previous reading; the first reading
    # starts with a flat one) and a 12x12 dot at x_by_step[k+1] (shifted left by dot_shift).
    "graph": {"ppm_per_level": 400, "y_by_level": _gy, "x_by_step": _gx,
              "flat_pic": 2, "rise_pic": 3, "fall_pic": 4, "dot_pic": 1, "dot_shift": [2, 4]},
    # the panel with the first reading, then one reading after the other: segment + dot, PlaySoundEffect(0x23), DelayTicks(15)
    # (the seventh reading has no delay after it)
    "intro": {"mode": "sequence", "sfx": 0x23, "interval": 15, "trailing": False},
}

types[26] = {
    "source": "Prob26_Diagram 0x431732 (needle by speed 0-25)",
    "family": "items",
    "items": [PANEL,
              {"lookup": {"field": 0, "entries": [
                  {"pic": p, "pos": [x, y], "flip": bool(f)} for p, (x, y, f) in zip(arr(0x44302a, 26), triples(0x442fdc, 26))]}}],
    # Prob26_SuccessAnimation (0x4317d4): the needle (Prob26_NeedleIndex (0x44af5c), starts at f0) falls one step per 20 ticks
    # for f2 steps (f2 + 1 pictures); every picture but the first plays 0x22
    "success": {"mode": "needle", "sfx": 0x22, "interval": 20, "direction": -1, "count_field": 2, "start_field": 0},
}
types[27] = {
    "source": "Prob27_Diagram 0x42f2f6 (same needle art, panel two pixel rows lower)",
    "family": "items",
    "items": [{"pic": 0, "pos": [0x10, 0x3c]},
              {"lookup": {"field": 0, "entries": [
                  {"pic": p, "pos": [x, y], "flip": bool(f)} for p, (x, y, f) in zip(arr(0x442ed2, 26), triples(0x442e84, 26))]}}],
    # Prob27_SuccessAnimation (0x42f398): the needle (Prob27_NeedleIndex (0x44aee4), starts at f0) rises one step per 20 ticks
    # for f3 steps (f3 + 1 pictures); every picture but the first plays 0x22
    "success": {"mode": "needle", "sfx": 0x22, "interval": 20, "direction": 1, "count_field": 3, "start_field": 0},
}

types[28] = {
    "source": "Prob28_Diagram 0x419567, GetBallastAnswer 0x4196e8 (button 'increase')",
    "family": "ballast_panel",
    "items": [opaque(PANEL)],
    "weights": {"slot_pic": 4, "selected_pic": 3, "cursor_pic": 2, "pos": pairs(arr(0x441280, 10), arr(0x44128a, 10)),
                "label_offset": [0x3a, 5], "label_color": 0},
    # GetBallastAnswer (0x4196e8): Done plays 0x22 like every button, draws done_pic (the pressed OK) and DelayTicks(0x49) = 73 ticks
    # before it returns to the answer check
    "total": {"idle_pic": 7, "focus_pic": 6, "done_pic": 5, "pos": [0x34, 0xee], "hold_ticks": 73},
    "button": {"pic": 1, "pos": [0x38, 0x11c]},
}
types[29] = json.loads(json.dumps(types[28]))
types[29]["source"] = "Prob28_Diagram 0x419567 with param 1, GetBallastAnswer 0x4196e8 (button 'decrease')"
types[29]["button"]["pos"] = [0xb4, 0x11c]

types[30] = {
    "source": "Prob30_Diagram 0x41f527",
    "family": "storage_boxes",
    "items": [PANEL],
    # boxes are 40x34 pictures 1 and 2 (alternating); the compartment front (picture 3) is drawn over every box.
    # f0 boxes along x (a pair advances x_step[0] then x_step[1]), f1 rows back (each -12, +8), f2 layers up (-22), f9 extras
    "boxes": {"pics": [1, 2], "x_step": arr(0x441bc4, 2), "layer_dy": -22, "row_dx": -12, "row_dy": 8,
              "origin": [0x80, 0xa4], "front_pic": 3, "front_pos": [0x2c, 0x60],
              "length_field": 0, "width_field": 1, "height_field": 2, "extra_field": 9},
    # the panel, then one box after the other (layers, rows, columns, the f9 extras last): draw box + compartment front,
    # PlaySoundEffect(0x29), DelayTicks(15), also after the last
    "intro": {"mode": "sequence", "sfx": 0x29, "interval": 15, "trailing": True},
}

types[31] = {
    "source": "Prob31_Diagram 0x42eb3b and the shape routines Prob31_ShapeA..H 0x42e42b-0x42ea12 (shape codes 1, 2, 3 and 6 occur in the records)",
    "family": "search_area",
    "items": [opaque(PANEL), opaque({"pic": 1, "pos": [0x10, 0x112]})],
    # the searched region is built from 20x16 cells starting at `origin`: whole cells, and hypotenuse pieces for the triangles
    "cell": [0x14, 0x10],
    "origin": [0x50, 0x52],
    "pics": {"full": 2, "diagonal": 3, "steep": [6, 5], "half": [9, 10]},
    "max_columns": 21,               # two rectangles side by side only if their widths add up to less than this
}

for _t in (32, 33):
    types[_t] = {
        "source": "Prob32_Diagram 0x42ee6c (types 32 and 33 share all code)",
        "family": "search_grid",
        "items": [opaque(PANEL), opaque({"pic": 1, "pos": [0x10, 0x112]})],
        "origin": [0x50, 0x52],
        # the number of squares (f1) picks the grid: 100 (default), 16 or 4; `overlay` is the grid picture over the map
        "grids": {"100": {"step": [0x14, 0x10], "columns": 10, "pic": 2, "overlay": None},
                  "16": {"step": [0x34, 0x28], "columns": 4, "pic": 4, "overlay": 3},
                  "4": {"step": [100, 0x50], "columns": 2, "pic": 6, "overlay": 5}},
        "total_field": 1, "shaded_field": 0,
        # one shaded square after the other: draw, FlushRect, PlaySoundEffect(0x29), DelayTicks(2)
        "intro": {"mode": "sequence", "sfx": 0x29, "interval": 2, "trailing": True},
    }

types[0] = {
    "source": "DoCombinationLock 0x421780, LockDrawOperandWheel 0x421a81 / LockDrawAnswerWheel 0x421b78 (the resting wheels)",
    "family": "lock",
    "items": [],
    # The lock's own pictures are not all in the type's bundle (77): the importer appends the face (loose picture 1803,
    # = index 11) and the four answer-wheel pictures (bundle 78, = indices 12-15) to the art list of type 0.
    "face": {"pic": 11, "pos": [0x14, 0x3a]},
    "answer_wheel": {"first_pic": 12, "pos": [0x28, 0x3c]},
    # The window (item 10 of the type's bundle, 80 x 44, dark): `LockSpinOperandWheel` (0x421c6c) draws it over the top of the operand wheel
    # when the wheel has stopped, then the chosen label on it; the next `LockDrawOperandWheel` (0x421a81) paints over it.
    "operand_wheel": {"first_pic": 6, "pos": [0x54, 0x5f], "window": {"pic": 10, "pos": [0x88, 0x62]}},
    # label centres on the two wheels in the four rotation phases (phase 0 is the resting state)
    "operand_labels": [pairs(arr(0x441c88 + p * 0x40, 8, "I"), arr(0x441ca8 + p * 0x40, 8, "I")) for p in range(4)],
    "answer_labels": [pairs(arr(0x441d88 + p * 0x40, 8, "I"), arr(0x441da8 + p * 0x40, 8, "I")) for p in range(4)],
}

out = {
    "_doc": ("How the original draws each problem type (the ProbNN_Diagram functions of ONWIN32.EXE, DESIGN 5.5). "
             "Window coordinates (640x400). 'pic' = picture index in the type's art bundle (0 = the panel). Generated by "
             "tools/analysis/ghidra/export_diagrams.py; the vocabulary is documented in godot/src/problems/diagrams/diagram_base.gd."),
    "window": [640, 400],
    "screen": {
        "background": {"single_pic_id": 1780, "pos": [12, 30]},
        "title": {"box": [0x28, 0x10c], "y": 0x24, "color": 15},
        "message_box": [0x16c, 0x30, 0xee, 0xca],        # x, y, w, h of the prompt / hint / solution text (white on black)
        "calculator_pos": [0x14c, 0x10e],
        # GDI font of the text: Arial bold, 19 px cell height, average width 7 px (strings 11253-11256)
        "font": {"face": "Arial", "weight": 700, "cell_height": 19, "average_width": 7, "line_height": 20},
    },
    # SetColor(n): the 16 standard VGA colours
    "colors": [[0, 0, 0], [0, 0, 170], [0, 170, 0], [0, 170, 170], [170, 0, 0], [170, 0, 170], [170, 85, 0], [192, 192, 192],
               [85, 85, 85], [85, 85, 255], [85, 255, 85], [85, 255, 255], [255, 85, 85], [255, 85, 255], [255, 255, 85], [255, 255, 255]],
    "types": {str(k): v for k, v in sorted(types.items())},
}
dest = ROOT / "docs/data/problem_diagrams.json"
dest.write_text(json.dumps(out, indent=1) + "\n")
print("wrote", dest, len(types), "types")
