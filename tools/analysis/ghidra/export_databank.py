"""Export the data canister's log screen tables (DATABANK.C: `DoDataBank` (0x41e18f), `PrepareCanisterLog` (0x41e787)) to
docs/data/databank.json.

Pure Python (no Ghidra needed): every table is read straight from the EXE's data segment, the addresses come from the
Ghidra decompilation (see `names_onwin32.json` / `labels_onwin32.json`).

* `LogUnlockOrderVoyager` (0x4419d5) / `LogUnlockOrderExpert` (0x4419e4): 15 bytes each, the entry numbers (1-15) in the
  order the sectors of the game deliver them: sector s of a game lists the first `s % 15 + 1` of them; the last of those
  is the newest and the one the screen opens on.
* `LogRowX` (0x4419f4) / `LogRowY` (0x441a34): 16 u32 each, the top-left of menu row r (two columns of eight).
* `LogEntryClipFirst` (0x441a74) / `LogEntryClipEnd` (0x441aec): 30 u32 each, the first / one-past-last LOGICAL speech
  clip id of log entry n (voyager 0-14, expert 15-29) (already in `audio_map.json`, repeated here for the cross-check).
* The row caption is the string "ENTRY" (11032) + `LogEntryNumberTemplate` (0x441b64) " 1.00", patched with the game digit and the
  two digits of the entry number.

Run:  uv run tools/analysis/ghidra/export_databank.py
"""

import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))   # gamefiles.py reads the CD image (NEPTUNE.ISO)
import gamefiles
D = gamefiles.read("ONWINCD/ONWIN32.EXE")
pe = struct.unpack_from("<I", D, 0x3C)[0]
nsec = struct.unpack_from("<H", D, pe + 6)[0]
opt = pe + 24
szopt = struct.unpack_from("<H", D, pe + 20)[0]
base = struct.unpack_from("<I", D, opt + 28)[0]
secs = []
for i in range(nsec):
    o = opt + szopt + i * 40
    vs, va, rs, rp = struct.unpack_from("<IIII", D, o + 8)
    secs.append((va, vs, rp, rs))


def off(a: int) -> int:
    r = a - base
    for va, vs, rp, rs in secs:
        if va <= r < va + max(vs, rs):
            return rp + r - va
    raise KeyError(hex(a))


def arr(a: int, n: int, fmt: str = "B") -> list[int]:
    return list(struct.unpack_from("<%d%s" % (n, fmt), D, off(a)))


def cstr(a: int) -> str:
    o = off(a)
    return D[o : D.index(b"\0", o)].decode("latin1")


out = {
    "unlock_order_voyager": arr(0x4419D5, 15),
    "unlock_order_expert": arr(0x4419E4, 15),
    "row_x": arr(0x4419F4, 16, "I"),
    "row_y": arr(0x441A34, 16, "I"),
    "row_size": [0x73, 0x10],
    "caption_template": cstr(0x441B64),
    "clip_first": arr(0x441A74, 30, "I"),
    "clip_end": arr(0x441AEC, 30, "I"),
    "scan": {
        "bundle_logical": 0x1DC,
        "pictures": 9,
        "position": [0x170, 0x116],
        "ticks_per_picture": 5,
        "sweeps": 6,
        "pictures_per_sweep": 8,
        "sound": 0x1D,
    },
    "entry_text_box": [0x2C, 0x54, 0x108, 200],
    "menu_clear_box": [0x165, 0x30, 0xF5, 0xCA],
    "menu_title_box": [0x16C, 0x30, 0xEE],
    "text_bundles_logical": [0x1C0, 0x1C1],
    "mouse_hotspot_id_base": 3000,
}
for k in ("unlock_order_voyager", "unlock_order_expert"):
    assert sorted(out[k]) == list(range(1, 16)), k
path = ROOT / "docs/data/databank.json"
path.write_text(json.dumps(out, indent=1) + "\n")
print("wrote", path)
