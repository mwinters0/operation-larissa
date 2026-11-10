"""Export the opening's animation tables (news cartoon crew / lights, title-scene ship, sub drop and splash) to
docs/data/opening.json.

Pure Python (no Ghidra needed to run it). Every rule below was read in the Ghidra decompilation of ONWIN32.EXE
(OPENING.C, `OpeningSequence` = OpeningSequence (0x42b16b)); the function addresses are the ones in that dump. The routines are
transcribed as small state machines and RUN here, so the JSON holds the resulting per-redraw tables, not just rules.

How the original draws (all [V]):

* One timer unit is 1/73 s. The screen is a 640 x 400 back buffer; a second, clean copy of the background lives
  400 rows below it. Each redraw restores a strip from the clean copy, draws the sprites with `DrawPictureMasked(x,
  y, picture, mirror)` (colour 200 is transparent, `mirror` != 0 flips left-right), then flushes the strip.
* The position table (68 points, NEP.DLL resource 10012, doubled at load) is MODIFIED IN PLACE by the routines: a
  moving sprite's point is its current position.
* A picture is `BundleItem(bundle, item)`: bundle 9 (cartoon) item i = picture 1001 + i, bundle 10 (ship) item i =
  picture 1027 + i, bundle 13 item i = picture 1041 + i.
* The news cartoon redraws every 10 ticks (call n = 1, 2, ... at t = 10 (n - 1) ticks; the counter CartoonClock (0x449e9c) is
  start + 10 n during call n, and the time gates below compare against it). The title scene redraws every 12 ticks.
* The title scene clips the mini-sub to rows <= 0x138 = 312 (`ClipBottom` (0x440b2c); the clip rectangle is inclusive).
"""
import json
import struct
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))   # gamefiles.py reads the CD image (NEPTUNE.ISO)
import gamefiles
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
    """File offset of a virtual address."""
    r = addr - base
    for va, vs, rp, rs in secs:
        if va <= r < va + max(vs, rs):
            return rp + r - va
    raise KeyError(hex(addr))


# --- the point table ------------------------------------------------------------------------------------------
raw_points = (ROOT / "extracted/data/NEP_raw/NEP_10012.bin").read_bytes()
raw_points += b"\0" * (-len(raw_points) % 4)          # the resource length is rounded down by one byte
_vals = [int.from_bytes(raw_points[i:i + 2], "little", signed=True) * 2 for i in range(0, len(raw_points), 2)]
POINTS = [[_vals[i], _vals[i + 1]] for i in range(0, len(_vals), 2)]
assert len(POINTS) == 68

POINT_NAMES = {
    "map": 0, "console_left": 1, "console_right": 2, "alarm_lights": [3, 4, 5], "status_lights": [6, 7, 8, 9, 10, 11],
    "panel_lights": [12, 13, 14, 15, 16, 17, 18, 19], "teletype": 20, "crash_site": 21, "crew": [22, 23, 24, 25, 26],
    "capsule_trail": [27, 47], "ship_hull": 48, "ship_radar": 49, "ship_hook": 50, "ship_sub": 51, "ship_bow_spray": 52,
    "waves_front": 53, "splash": 54, "sky": 55, "sea": 56, "cloud_left": 57, "cloud_right": 58, "presents": 59,
    "operation": 60, "neptune": 61, "copyright_text": 62,
}


def s8(b: int) -> int:
    return b - 256 if b > 127 else b


# --- 1. the news cartoon: crew -----------------------------------------------------------------------------------
CREW_OFFSETS = list(struct.unpack_from('<5i', D, off(0x442a9c)))      # byte offset of each crew member's script
CREW_TABLE = D[off(0x442ab4):off(0x442ab4) + 300]                      # 4-byte records, terminated by a lone 0xfe
BUNDLE9_FIRST_ID = 1001


def crew_records(k: int) -> list[dict[str, int]]:
    """Script of crew member k: records [cmd, item, mirror, delay]; cmd -1 show, -3 show and walk 12 px right."""
    out: list[dict[str, int]] = []
    p = CREW_OFFSETS[k]
    while s8(CREW_TABLE[p]) != -2:
        cmd, item, mirror, delay = (s8(b) for b in CREW_TABLE[p:p + 4])
        out.append({"cmd": cmd, "item": item, "picture": BUNDLE9_FIRST_ID + item, "mirror": mirror, "delay": delay})
        p += 4
    return out


class CrewState:
    """CartoonCrew (0x4296de) (one call per 10 tick redraw): P = record offset (-1 = start), T = calls left of this record."""

    def __init__(self, k: int, x0: int):
        self.k, self.p, self.t, self.x = k, -1, 0, x0

    def step(self) -> tuple[int, int, int] | None:
        """One call: (picture id, mirror, x after the call) or None when nothing is drawn."""
        base_k = CREW_OFFSETS[self.k]
        old = self.p
        if self.t < 1:
            self.p = 0 if self.p == -1 else self.p + 4
        cmd = s8(CREW_TABLE[self.p + base_k])
        if cmd == -2:                      # end of the script: draw the previous record once more, restart
            rec = CREW_TABLE[old + base_k:old + base_k + 4]
            self.p, self.t = -1, 0
            return BUNDLE9_FIRST_ID + s8(rec[1]), s8(rec[2]), self.x
        if cmd not in (-1, -3):
            raise ValueError(cmd)
        if cmd == -3:
            self.x += 12
        rec = CREW_TABLE[self.p + base_k:self.p + base_k + 4]
        if self.t == 0:
            self.t = s8(rec[3])
        picture = BUNDLE9_FIRST_ID + s8(rec[1])
        mirror = s8(rec[2])
        self.t -= 1
        return picture, mirror, self.x


def crew_cycle(k: int) -> dict[str, Any]:
    """Run crew k from the start until its script restarts: the per-call pictures of ONE cycle."""
    x0 = POINTS[22 + k][0]
    st = CrewState(k, x0)
    calls: list[list[int]] = []
    last_x = x0
    while True:
        r = st.step()
        assert r is not None
        calls.append([r[0], r[1], r[2] - last_x])
        last_x = r[2]
        if st.p == -1:
            break
    return {"x0": x0, "y": POINTS[22 + k][1], "calls": len(calls), "dx_per_cycle": sum(c[2] for c in calls),
            "pictures": calls}


# --- 1b. the news cartoon: lights, trail, ring -------------------------------------------------------------------
# CartoonDrawAlarmLight(point*2, state) (0x4292aa): (bundle 9 item, mirror) of an alarm light state
ALARM_STATE = {0: (7, 0), 1: (6, 1), 2: (8, 0), 3: (6, 0)}


def alarm_states(calls: int = 12) -> dict[str, Any]:
    """The three alarm lights (CartoonAlarmLights (0x429318)). Counters start at (0, 1, 2) when the gate opens (call 37) and all
    three advance by one (mod 4) per call; the centre light draws from call 37 on, the outer two from call 234."""
    return {
        "points": [3, 4, 5],
        "gate_call": {"centre": 37, "outer": 234},
        "gate_ticks": {"centre": 365, "outer": 2336},
        "state_to_picture": {str(s): {"item": i, "picture": BUNDLE9_FIRST_ID + i, "mirror": m}
                              for s, (i, m) in ALARM_STATE.items()},
        "start_state": {"left": 0, "centre": 1, "right": 2},
        "sequence_first_calls": [[(s + c) % 4 for s in (0, 1, 2)] for c in range(calls)],
    }


def trail_and_ring() -> dict[str, Any]:
    """CartoonCapsuleTrail (0x42907e): counter c advances per call; a dot (picture 1002, item 1) every 11 calls at points 27..47
    (21 dots), then the ring (items 2..5 = pictures 1003..1006, point 21) 6 calls later, one picture per call."""
    dots = [{"call": 11 * (j + 1), "point": 27 + j} for j in range(21)]
    ring_first = dots[-1]["call"] + 6
    return {
        "dot_picture": 1002, "dots": dots, "ring_pictures": [1003, 1004, 1005, 1006], "ring_point": 21,
        "ring_first_call": ring_first, "ring_ticks_per_picture": 10,
        "dot_first_tick": 10 * (dots[0]["call"] - 1), "ring_first_tick": 10 * (ring_first - 1),
    }


def news_cartoon() -> dict[str, Any]:
    texts = {t["id"]: t["text"] for t in json.loads((ROOT / "extracted/data/NEP_text.json").read_text())}
    bulletins = [{"id": 10003 + i, "characters": len(texts[10003 + i]), "typing_ticks": 3 * len(texts[10003 + i])}
                 for i in range(6)]
    crew_first_call = [1, 1, 1, 1, 220]               # crew 4 (the man from the left) only from call 220 (2190 ticks)
    crew = []
    for k in range(5):
        c = crew_cycle(k)
        c["records"] = crew_records(k)
        c["first_call"] = crew_first_call[k]
        c["first_tick"] = 10 * (crew_first_call[k] - 1)
        c["point"] = 22 + k
        crew.append(c)
    return {
        "redraw_ticks": 10,
        "structure": "7 passes of 25 redraws; after passes 1..6 bulletin 0..5 is typed (the box is empty during pass 1); "
                     "the redraws go on (every 10 ticks, by the clock) while typing",
        "typing": {"ticks_per_character": 3, "note": "2 ticks wait + 1 tick alarm per character, newline 2 ticks"},
        "bulletins": bulletins,
        "crew": {
            "pictures": "bundle 9 items 15..25 = pictures 1016..1026: 1016-1019 man from behind (4 poses), "
                        "1020-1021 woman, 1022-1023 man turned / front, 1024-1026 the walking man",
            "record": "[cmd, item, mirror, delay]: cmd -1 show the picture for `delay` calls; cmd -3 same, and move "
                      "the sprite 12 px right on EVERY call of the record; the script ends with a lone byte -2: "
                      "the previous record's picture is drawn once more and the script restarts (its x is NOT reset)",
            "members": crew,
        },
        "alarm_lights": alarm_states(),
        "status_lights": {
            "function": "CartoonStatusLights (0x429440)", "points": [6, 7, 8, 9, 10, 11], "base_item": 9, "first_picture": 1010,
            "rule": "every call, each light independently: with probability 100/299 (rand() % 299 < 100) draw picture "
                    "1010 + r % 3 (r = that remainder); the lights at points 9, 10, 11 are drawn mirrored; otherwise "
                    "the light is OFF (the strip is restored from the clean copy every call)",
            "mirror": [0, 0, 0, 1, 1, 1],
        },
        "panel_lights": {
            "function": "CartoonPanelLights (0x429595)", "points": [12, 13, 14, 15, 16, 17, 18, 19], "base_item": 12,
            "first_picture": 1013,
            "rule": "every call, each light is ALWAYS drawn with picture 1013 + rand() % 299 % 3; the last four "
                    "(points 16-19) are mirrored",
            "mirror": [0, 0, 0, 0, 1, 1, 1, 1],
        },
        "trail_and_ring": trail_and_ring(),
        "speech": {
            "function": "CartoonSpeech (0x42984d)", "states": 11,
            "waits_ticks": {"1": 219, "3": 248, "6": 248, "7": 248},
            "note": "clip n (NE1SOUND 3999 + n) starts when the previous one has finished; before clips 1, 3, 6, 7 "
                    "there is a pause of 219 (clip 1) / 248 ticks; clips 2, 4, 5, 8-11 follow at once",
        },
        "end": "after pass 7 (25 redraws after the last bulletin has been typed); Enter skips to the title scene, "
               "Space / Esc skip everything",
    }


# --- 2. the title scene: the ship, the dropped sub, the splash ------------------------------------------------------
STAND_FIRST, STAND_LAST = 0x38, 0x55            # redraws during which the ship does not advance


def wobble(i: int) -> int:
    """TitleShipWobble (0x429cc2): the vertical wobble added to every ship part after each draw."""
    if 0x37 < i < 0x56:
        return 0
    if i % 5 != 0:
        return 0
    if i % 10 == 0:
        return -2
    return 2


def title_scene() -> dict[str, Any]:
    p = {n: list(POINTS[i]) for n, i in [("hull", 48), ("radar", 49), ("hook", 50), ("sub", 51), ("spray", 52)]}
    st = {"c0": 0, "c1": 0, "splash": -2, "toggle": 0}
    frames: list[dict[str, Any]] = []

    def moving(i: int) -> bool:
        return i < STAND_FIRST or i > STAND_LAST

    def one_frame(i: int, with_splash: bool, redraw: int) -> dict[str, Any]:
        f: dict[str, Any] = {"redraw": redraw, "param": i, "tick": 12 * redraw}
        # TitleDrawHull (0x429dbb): hull 1027, not mirrored
        f["hull"] = {"picture": 1027, "mirror": 0, "x": p["hull"][0], "y": p["hull"][1]}
        if moving(i):
            p["hull"][0] += 8
        p["hull"][1] += wobble(i)
        # TitleDrawRadar (0x429e25): radar item c0 + 1 (pictures 1028..1030), mirrored when c1
        f["radar"] = {"picture": 1028 + st["c0"], "mirror": st["c1"], "x": p["radar"][0], "y": p["radar"][1]}
        if moving(i):
            p["radar"][0] += 8
        p["radar"][1] += wobble(i)
        if i % 3 == 0:
            st["c0"] += 1
            if st["c0"] > 2:
                st["c1"], st["c0"] = 1, 1
            elif st["c1"]:
                st["c1"], st["c0"] = 0, 0
        # TitleDrawHook (0x429efc): hook item 4 / 5 (1031 / 1032, MIRRORED), open (1032) for 0x43 <= i <= 0x46
        f["hook"] = {"picture": 1032 if 0x43 <= i <= 0x46 else 1031, "mirror": 1, "x": p["hook"][0],
                     "y": p["hook"][1]}
        if moving(i):
            p["hook"][0] += 8
        p["hook"][1] += wobble(i)
        # TitleDrawSub (0x429f7b): the sub (1033, MIRRORED), y += 6 BEFORE the draw once i > 0x43 until y >= 0x13e, clipped to
        # rows <= 0x138
        fell = i > 0x43 and p["sub"][1] < 0x13e
        if fell:
            p["sub"][1] += 6
        y = p["sub"][1]
        rows = max(0, min(y + 44, 313) - y)
        f["sub"] = {"picture": 1033, "mirror": 1, "x": p["sub"][0], "y": y, "visible_rows": rows, "falling": fell}
        if moving(i):
            p["sub"][0] += 8
        p["sub"][1] += wobble(i)
        # TitleWaveStrip (0x42a1d7): the strip of waves 1041 at point 53 is drawn over the parts above (static)
        # TitleSplash (0x42a01f): the splash, only in the loop (not in the pre-frame)
        f["splash"] = None
        f["sfx"] = []
        if with_splash and y > 0x106 and st["splash"] < 5:
            if st["splash"] == -2:
                f["sfx"].append(0x2b)
            if st["splash"] >= 0:
                f["splash"] = {"picture": 1034 + st["splash"], "left": list(POINTS[54]),
                               "right": [POINTS[54][0] + 0x4c, POINTS[54][1]], "right_mirror": 1}
            st["splash"] += 1
        # TitleBowSpray (0x42a0f6): bow spray at point 52 (items 8 / 9 or 10 / 11 = pictures 1035..1038), toggles every call
        spray = None
        if i < 0x2a or i > 0x5d:
            spray = 1035 + st["toggle"]
        elif moving(i):
            spray = 1037 + st["toggle"]
        f["spray"] = None if spray is None else {"picture": spray, "mirror": 0, "x": p["spray"][0], "y": p["spray"][1]}
        if moving(i):
            p["spray"][0] += 8
        p["spray"][1] += wobble(i)
        st["toggle"] ^= 1
        return f

    # the pre-frame (parameter 0, no splash) is drawn before the music starts; the loop then runs i = 0 .. 161
    pre = one_frame(0, False, 0)
    pre["pre_frame"] = True
    frames.append(pre)
    for i in range(0xa2):
        frames.append(one_frame(i, True, i + 1))
    first_fall = next(f["redraw"] for f in frames if f["sub"]["falling"])
    sound = next(f["redraw"] for f in frames if 0x2b in f["sfx"])
    first_splash = next(f["redraw"] for f in frames if f["splash"])
    gone = next(f["redraw"] for f in frames if f["sub"]["visible_rows"] == 0)
    return {
        "redraw_ticks": 12,
        "redraws": 0xa2,
        "frame_note": "frames[0] is the pre-frame (t = 0, parameter 0), frames[r] for r = 1..162 is loop iteration "
                      "r - 1 (parameter r - 1) at t = 12 r ticks; positions are where the part is DRAWN in that frame",
        "ship": {
            "start_x": POINTS[48][0], "advance_px": 8, "stand_still_params": [STAND_FIRST, STAND_LAST],
            "wobble": "after each draw y += -2 when param % 10 == 0, +2 when param % 10 == 5 (none while standing "
                      "still); every part of the ship wobbles by the same amount",
        },
        "sub": {
            "picture": 1033, "mirror": 1, "size": [72, 44], "hook_open_params": [0x43, 0x46],
            "fall_starts_param": 0x44, "fall_px_per_redraw": 6, "fall_stops_when_y_at_least": 0x13e,
            "clip_bottom_row": 0x138,
            "note": "the sub is NOT attached to the ship after the drop: it keeps the ship's x advance but is clipped "
                    "to rows <= 312, so once its top row is at 313 or lower (it stops at y = 322) nothing of it is "
                    "drawn. It sinks behind the wave strip, splashes, and is gone.",
            "first_fall_redraw": first_fall, "gone_redraw": gone,
        },
        "splash": {
            "pictures": [1034, 1035, 1036, 1037, 1038], "size": [76, 50], "left_point": 54, "right_dx": 0x4c,
            "right_mirror": 1, "trigger": "sub y > 262 (0x106)", "sound": 0x2b,
            "sound_redraw": sound, "first_picture_redraw": first_splash,
            "note": "sound on the trigger frame, nothing for the next frame, then one picture per redraw (5 redraws); "
                    "both halves are drawn at the FIXED point 54 (the ship is standing still)",
        },
        "draw_order": ["sky 1039 (0,0)", "sea 1040 (0,284)", "clouds 1042 / 1043 (static)", "hull 1027", "radar",
                       "hook", "sub (clipped)", "waves 1041 (0,284)", "splash", "bow spray"],
        "frames": frames,
    }


# --- 3. the reveal and the prompt ------------------------------------------------------------------------------------
def reveal_and_prompt() -> dict[str, Any]:
    return {
        "after_ship": "at once (no fade): sky + clouds + sea redrawn without the ship, music stopped (0x33 + stop)",
        "steps": [
            {"t_ticks": 0, "sfx": 0x33, "action": "show picture 1044 'The Learning Company Presents' at point 59 "
                                                  "(a single blit, NO wipe), hold 292 ticks"},
            {"t_ticks": 292, "action": "erase it (sky / clouds redrawn over the strip)"},
            {"t_ticks": 292, "sfx": 0x33, "action": "show picture 1045 'OPERATION' at point 60, hold 292 ticks"},
            {"t_ticks": 584, "sfx": 0x33, "action": "show picture 1046 'NEPTUNE' at point 61 and the TEXT string 11001 "
                                                   "(white, font colour 15) at point 62, with the two buttons"},
        ],
        "hold_ticks": 292,
        "keys_during_holds": "Enter, Space, Esc end the hold early; Space / Esc also abandon the whole opening",
        "prompt": {
            "buttons": {"start": {"x": 228, "y": 322, "normal": 2420, "pressed": 2421},
                        "intro": {"x": 330, "y": 322, "normal": 2422, "pressed": 2423}},
            "timeout_ticks": 1825, "music_after_ticks": 292, "music_id": 9502,
            "keys": {"start": ["Space", "Esc", "S", "click Start"], "intro": ["Enter", "I", "click Intro"],
                     "timeout": "Intro"},
        },
    }


out = {
    "_doc": "Opening animation tables decoded from OPENING.C (ONWIN32.EXE, 0x428f88 .. OpeningSequence 0x42b16b). See the "
            "docstring of tools/analysis/ghidra/export_opening.py. Points are window pixels (already doubled).",
    "tick_hz": 73,
    "points": POINTS,
    "point_names": POINT_NAMES,
    "news_cartoon": news_cartoon(),
    "title_scene": title_scene(),
    "reveal_and_prompt": reveal_and_prompt(),
}
(ROOT / "docs/data/opening.json").write_text(json.dumps(out, indent=1) + "\n")
_t = out["title_scene"]
print("wrote docs/data/opening.json:", len(_t["frames"]), "title frames; sub falls from redraw",
      _t["sub"]["first_fall_redraw"], "to gone at", _t["sub"]["gone_redraw"], "; splash sound at redraw",
      _t["splash"]["sound_redraw"])
for _c in out["news_cartoon"]["crew"]["members"]:
    print(" crew point", _c["point"], "cycle", _c["calls"], "calls, dx", _c["dx_per_cycle"], "first call",
          _c["first_call"])
