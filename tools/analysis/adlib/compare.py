"""B*.MID against E*.MID: are the Windows AdLib song's notes (tick, key) a subset of the General MIDI song's?

Teaches: the B set is a reduction of the E set. Melodic notes of B channels 13-15 are a subset of E's melodic notes, the drum
notes of B channel 16 equal E channel 10's; velocities are the original's own in both.
Run: `uv run tools/analysis/adlib/compare.py` (reads extracted/music/).
"""
import collections

import midi
import paths

paths.ensure_utf8()


def notes(name, perc_ch):
    no = midi.notes(str(paths.MUSIC / (name + ".MID")))[0]
    out = collections.defaultdict(list)
    vel = collections.Counter()
    for x in no:
        out["perc" if x[2] == perc_ch else "mel"].append((x[0], x[3]))
        vel[x[4]] += 1
    return out, vel


for s in ["END", "END2", "NEPT1", "NEPT2", "SECT1", "SECT2", "SECT3", "SECT4", "SECT5", "SECT6"]:
    b, bv = notes("B" + s, 16)
    e, ev = notes("E" + s, 10)
    res = []
    for k in ("mel", "perc"):
        B = collections.Counter(b[k])
        E = collections.Counter(e[k])
        res.append(f"{k}: B={sum(B.values())} E={sum(E.values())} common={sum((B & E).values())}")
    print(s, " | ".join(res), f"| B vel distinct={len(bv)} top={bv.most_common(3)} | E vel distinct={len(ev)}")
