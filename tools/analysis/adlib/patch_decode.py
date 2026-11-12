"""Prints the 11-byte OPL2 patches of the NE0SOUND type-3 (AdLib) resources 9048-9095 (effects) and 9144-9190 (songs).

Teaches: the type-3 layout read from `extracted/sounds/fm_patches_undecoded/NE0SOUND_<id>.bin`. An effect (113 bytes) holds one
patch at 0x5A. A song or bank holds, at 0x52, the song count n; at 0x53 + 4n a patch count and then that many u16 offsets (absolute,
11 bytes apart), the patches laid out [mod 20,40,60,80,E0][C0][car 20,40,60,80,E0]. The song layout is verified
(docs/port/ADLIB_MUSIC.md, "The DOS driver"); the effect's patch position and the "suspicious" check
(waveform byte above 3, feedback byte above 0x0F) are not. The output is game data: read it, never commit it.
Run: `uv run tools/analysis/adlib/patch_decode.py [folder]` (default: the importer's extracted/sounds/fm_patches_undecoded/).
"""
import struct
import sys
from pathlib import Path

import paths

paths.ensure_utf8()
D = Path(sys.argv[1]) if len(sys.argv) > 1 else paths.FM_PATCHES


def g(i):
    return (D / f"NE0SOUND_{i}.bin").read_bytes()


def fmt(p):
    return "mod[20=%02x 40=%02x 60=%02x 80=%02x E0=%02x] C0=%02x car[20=%02x 40=%02x 60=%02x 80=%02x E0=%02x]" % tuple(p)


bad = 0
for i in range(9048, 9096):
    b = g(i)
    if len(b) == 113:
        p = b[0x5A:0x65]
        print(i, fmt(p))
        bad += p[4] > 3 or p[10] > 3 or p[5] > 0x0F
print("sfx suspicious", bad)
for i in range(9144, 9191):
    b = g(i)
    if struct.unpack("<I", b[:4])[0] != 3:
        continue
    n = b[0x52]
    cnt = b[0x53 + 4 * n]
    offs = struct.unpack_from("<%dH" % cnt, b, 0x54 + 4 * n)
    print(i, "songs", n, "patches", cnt, "offsets", [hex(o) for o in offs[:3]], "...")
    for o in offs:
        print("   ", fmt(b[o:o + 11]))
