"""Export constant tables found with Ghidra straight from ONWIN32.EXE (no Ghidra needed to run this).
Each address was identified in the decompilation; see docs/port/DESIGN.md for the functions that read them.
Writes extracted/tables/{music_map,ink_tables,hud_gauges,lock_wheel,ballast,piece_animation,dissolve_tables,expert_closing}.json: the importer's "tables" step
(tools/import/step_extract.py) runs it, and the files are git-ignored (the game's own tables).
Run:  uv run tools/analysis/ghidra/export_constants.py
"""
import json, struct
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))   # gamefiles.py reads the CD image (NEPTUNE.ISO)
sys.path.append(str(ROOT / "tools" / "import"))   # common.py: where extracted/ and its tables/ are
import utf8_mode
utf8_mode.ensure()   # Windows: UTF-8 mode, like every entry point of the importer
import gamefiles
from common import TABLES
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else TABLES   # the importer passes common.TABLES
D = gamefiles.read("ONWINCD/ONWIN32.EXE")
pe = struct.unpack_from('<I', D, 0x3c)[0]
nsec = struct.unpack_from('<H', D, pe + 6)[0]; opt = pe + 24; szopt = struct.unpack_from('<H', D, pe + 20)[0]
base = struct.unpack_from('<I', D, opt + 28)[0]
secs = []
for i in range(nsec):
    o = opt + szopt + i * 40
    vs, va, rs, rp = struct.unpack_from('<IIII', D, o + 8); secs.append((va, vs, rp, rs))
def off(a):
    r = a - base
    for va, vs, rp, rs in secs:
        if va <= r < va + max(vs, rs): return rp + r - va if r - va < rs else None
    raise KeyError(hex(a))
def rd(a, n):
    o = off(a); return D[o:o + n] if o is not None else b'\0' * n
def u32(a): return struct.unpack('<I', rd(a, 4))[0]
def cstr(a):
    o = off(a); return D[o:D.index(b'\0', o)].decode('latin1')
def arr(a, n, fmt='B'): return list(struct.unpack('<%d%s' % (n, fmt), rd(a, n * struct.calcsize(fmt))))
out = OUT
out.mkdir(parents=True, exist_ok=True)
def dump_json(obj, path):
    with open(path, "w", newline="\n") as f: json.dump(obj, f, indent=1)

ids = arr(0x440dd8, 10, 'I'); names = [cstr(u32(0x440e28 + 4 * i)) for i in range(10)]
dump_json({"_doc": "Music id -> MIDI file. LoadMidiFile (0x413e8c) looks the id up in the table @0x440dd8, then opens SOUNDS\\<X><rest> where X='B' "
           "(base/AdLib set) or 'E' (extended/GM set, chosen from midimap.cfg) replaces the first letter of the stored name. "
           "Sector music id = 9504 + sector%6 for sector<30 (SelectSectorMusic 0x43200f); 9500 for sectors 30/31; 9501 closing; 9502/9503 sign-in/title.",
           "music": [{"id": i, "file": n.upper()} for i, n in zip(ids, names)]}, out / "music_map.json")

ink = {"_doc": "Ink pellet (stun gun) tables. StartStunGun 0x432330: pellet x = SubX + spawn_dx[SubCell], y = SubY + spawn_dy[SubCell], "
       "direction = dir_by_subcell[SubCell] (index into step tables; 3 = no motion: splashes at once). UpdateStunGun 0x4323f0 moves it 3 steps/frame "
       "of (step_dx[dir], step_dy[dir]) px = up to 24 px/frame; it is removed outside x 1..0x26f, y 0x11..0x13f, and 'hits' (starts the splash animation, "
       "frames 1..3) when the tile at ((x-8)>>4, (y-0x18)>>4) in the 38x18 map has flag 0x40. Splash frame k is drawn from the ink bundle (16) picture k "
       "at (x+splash_dx[k], y+splash_dy[k]). Max 2 pellets in flight.",
       "spawn_dx_by_subcell": arr(0x443080, 9), "spawn_dy_by_subcell": arr(0x443089, 9), "dir_by_subcell": arr(0x443092, 9),
       "step_dx_by_dir": arr(0x44309b, 7, 'b'), "step_dy_by_dir": arr(0x4430a2, 7, 'b'),
       "splash_dx": arr(0x4430a9, 5, 'b'), "splash_dy": arr(0x4430ae, 5, 'b'), "splash_w": arr(0x4430b3, 5), "splash_h": arr(0x4430b8, 5)}
dump_json(ink, out / "ink_tables.json")

xy = arr(0x4413bc, 42, 'h')
dump_json({"_doc": "HUD gauges on the 640x400 screen (DisplayBezel 0x419eec, DisplayOxygen 0x41a11c, DisplayInkPelletCounter 0x419f6e). Pictures come "
           "from the bezel bundle (picture indices below).",
           "tanks": {"slots": 6, "y": 0x14c, "x": arr(0x4413a4, 6, 'i'), "pic_full": 15, "pic_empty": 16, "dirty_rect": [0x5c, 0x14c, 0x90, 0x18]},
           "oxygen": {"slots": 4, "x0": 0xf0, "y": 0x14e, "step_x": 0x14, "pic_full": 17, "pic_empty": 18, "pic_low_warning": 19,
                      "note": "when Oxygen==1 slot 0 shows pic 19 (low-oxygen warning, new-player hint 1) and the remaining 3 empty slots start at x=0x104",
                      "dirty_rect": [0xf0, 0x14e, 0x50, 0x14]},
           "ink_pellets": {"max": 21, "pic_full": 4, "pic_empty": 5, "xy": [list(p) for p in zip(xy[0::2], xy[1::2])], "dirty_rect": [0x80, 0x16c, 0xc4, 0x1e]},
           "bezel_background": {"pic": 0, "xy": [0xc, 0x144]}}, out / "hud_gauges.json")

lock = {"_doc": "Combination lock (type 0). Label tables: variant = record field f0 (0, 5, 8, 11 occur); 12 sets of 8 labels each, the EXE's static bytes: DoCombinationLock loads strings 11219-11245 over the decimal ones at run time (step_problems.lock_labels). "
        "Timing in 73 Hz ticks: DoCombinationLock 0x421780; each operand is brought up by spinning wheel A one quarter-slot per 9 ticks (sound 0x26) "
        "until slot (8-n)*4, then sound 0x27; the answer wheel B then advances one slot = 4 sub-steps x 9 ticks = 36 ticks (sound 0x26 each), "
        "followed by a 73-tick window in which Space / Enter / click stops it. Correct iff wheel position == (8-answer_slot)*4 (0 if slot 0). "
        "Passing the correct slot unstopped twice -> 'OUT OF TIME' (string 11045); a wrong stop -> 'ERROR' (11046); both cost 1 oxygen "
        "(sound 0x21), show the solution and continue. Two combination numbers per lock (record fields f1..f9 and f12..f20).",
        "ticks_per_second": 73, "substeps_per_slot": 4, "ticks_per_substep": 9, "key_window_ticks": 73, "positions_per_revolution": 32,
        "ticks_per_slot_including_window": 36 + 73, "revolution_seconds": round(8 * (36 + 73) / 73, 2),
        "operand_labels_by_wheel_set": {str(v): [cstr(u32(0x441e9c + 4 * (v * 8 + i))) for i in range(8)] for v in range(12)},
        "answer_labels_by_wheel_set": {str(v): [cstr(u32(0x44201c + 4 * (v * 8 + i))) for i in range(8)] for v in range(12)},
        "operator_strings": [cstr(u32(0x441e88 + 4 * i)) for i in range(5)]}
dump_json(lock, out / "lock_wheel.json")

den = {"_doc": "Ballast problems (types 28/29): denominations by display mode (BallastMode (0x448694): L0 -> 0, L1 -> 2, L2 -> 1, L3 -> 2) and their labels, the EXE's static bytes: LoadBallastLabels loads strings 11215-11218 over mode 1's at run time (step_problems.ballast_labels).",
       "modes": {str(m): {"values": arr(0x441294 + m * 0x28, 10, 'i'), "labels": [cstr(0x44130c + m * 0x32 + i * 5) for i in range(10)]} for m in (0, 1)}}
den["modes"]["2"] = {"values": [1, 2, 4, 8, 16, 32, 64, 128, 256, 512], "labels": [str(2 ** i) for i in range(10)]}
dump_json(den, out / "ballast.json")
# Pieces on the sea floor (DrawProbePieces 0x42dc3b, called once per game frame by DoAction; the piece list is
# AddProbePiece (0x42daf8) / DrawScreen (0x433f1c): piece i is registered as id i + 1). ONE shared counter PieceAnimCounter (0x442e6c) runs 0..15 (+1 per call, wraps
# after 15). Piece id 1 (index 0) is the data canister: bundle 17 picture 3 + (counter & 1), i.e. it flashes every game frame.
# EVERY other piece is a rock: picture RockPictureTable (0x442e70)[counter], a 16-entry table (a sparkle on 3 of 16 frames, no randomness).
rock = arr(0x442e70, 16)
dump_json({"_doc": "Collectible pieces (bundle 17: pictures 0-2 rock without / with a growing sparkle, 3-4 the canister's red / green flash). "
           "DrawProbePieces (0x42dc3b) draws every piece once per game frame (73/6 Hz = one GameClock tick) from ONE counter shared by all pieces that "
           "runs 0..15 and wraps, never reset by a screen change. Piece index 0 (id 1) is the data canister: picture 3 + (counter & 1). "
           "Every other piece is a rock: picture rock_pictures[counter]. The rule does not depend on the sector or the zone.",
           "bundle": 17, "period": 16, "canister_piece_index": 0,
           "canister_pictures": [3 + (c & 1) for c in range(2)], "canister_rule": "3 + (counter & 1)",
           "rock_pictures": rock, "rock_rule": "rock_pictures[counter]"},
          out / "piece_animation.json")
# The tank-loss dissolve (dissolve 0x414f81, called only by RedrawFrameAfterTankLoss 0x418bcb): 16 passes over 2 x 2 pixel blocks.
dump_json({"_doc": "dissolve (0x414f81) tables. Pass p (0..15) copies, for every pair of rows r = 0, 2, 4 ... (h - 1), the 2 x 2 blocks at "
           "x = (-row_order[r % 16]) + 16 n + column_order[p] that lie in 0 <= x < w - 2; a FlushRect of the whole box follows each pass; "
           "one final full copy + flush ends it. Over the 16 passes column_order visits every residue mod 16 once.",
           "column_order": arr(0x441188, 16), "row_order": arr(0x441198, 16), "passes": 16, "block": 2},
          out / "dissolve_tables.json")
# The Expert closing's deck crew (ExpertClosingSequence 0x41c650, CLOSING.C). ExpertCraneTable (0x4415a4) is NOT a crane script: it holds the
# walk / wave scripts of six sailors. The sequence cuts it into six scripts at the byte -3 (the last op of a script); script n starts just
# after the n-th -3 (ExpertClosingCrewScriptStart 0x4487a4), the table ends with -1. ExpertClosingCrewStep (0x41ceb7) runs one record per
# animation step: 4 bytes [op, item, mirror, delay] (the end op -3 is a single byte, the next script follows at once).
crane = [b - 256 if b > 127 else b for b in rd(0x4415a4, 1200)]
crane = crane[:crane.index(-1) + 1]
crew_starts = [0]
for i, v in enumerate(crane[:-1]):
    if v == -3 and len(crew_starts) < 6: crew_starts.append(i + 1)
crew_scripts = []
for n, st in enumerate(crew_starts):
    end = crew_starts[n + 1] - 1 if n < 5 else len(crane) - 2        # index of the script's closing -3
    assert crane[end] == -3 and (end - st) % 4 == 0, (n, st, end)
    crew_scripts.append([crane[j:j + 4] for j in range(st, end, 4)] + [[-3, 0, 0, 0]])
# start positions: immediates in ExpertClosingSequence (0x41c650): ExpertClosingCrewPos 0x448774 / 0x448778 .. 0x4487a0, six (x, y) pairs
crew_pos = [[0x1f0, 0xd6], [0x14c, 0xd6], [0x170, 0xe0], [0x1b4, 0xd6], [0x1f0, 0xd6], [0x1f0, 0xd6]]
dump_json({"_doc": "Expert closing, deck shot (ExpertClosingSequence 0x41c650 .. ExpertClosingCrewStep 0x41ceb7). Six sailors, one script each, cut from "
           "ExpertCraneTable (0x4415a4) at its -3 bytes. A script is a list of 4-byte records [op, item, mirror, delay]; item i is picture 2012 + i "
           "(bundle 0x1d1 item 10-26 = pictures 2022-2038, 28 x 26), mirror 1 = drawn mirrored. ExpertClosingCrewStep runs once per 18-tick step; per "
           "actor: while delay < 1 the script advances one record (the first step starts at record 0); the op then acts: -8 wait (nothing drawn), "
           "-2 draw, -4 x += 4 then draw, -5 x -= 4 then draw, -7 y += 10 then draw, -6 y -= 10 then draw; a draw / move op loads the record's delay "
           "the first time it is reached; delay is counted down once per step, so a record lasts `delay` steps (a move op moves once per step); "
           "-3 (the closing record, [-3, 0, 0, 0] here) draws the previous record's picture once more at the current position and restarts the "
           "script at its first record (the position is NOT reset). Each step ExpertClosingEraseCrew first restores the 28 x 26 rectangle under "
           "every actor, so an actor that draws nothing in a step is invisible in it.",
           "first_picture": 2012, "ops": {"-8": "wait", "-7": "down 10", "-6": "up 10", "-5": "left 4", "-4": "right 4", "-3": "end", "-2": "draw"},
           "start_positions": crew_pos, "scripts": crew_scripts}, out / "expert_closing.json")
print("wrote 8 files to", out)
