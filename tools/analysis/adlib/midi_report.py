"""Facts of every MIDI file in extracted/music/: format, ticks per beat, length, tempo changes, notes, polyphony, bends.

Teaches: what the Windows AdLib set (B*.MID) is made of next to the General MIDI set (E*.MID): per channel the note count, key
range, programs, controllers. Output feeds the table in docs/port/ADLIB_MUSIC.md.
Run: `uv run tools/analysis/adlib/midi_report.py [BSECT1 EEND ...]` (no argument: every file).
"""
import collections
import sys

import midi
import paths

paths.ensure_utf8()


def analyse(path):
    fmt, div, tracks = midi.parse(path)
    tempos = [(t, int.from_bytes(d, "big")) for tr in tracks for t, k, ty, d in tr if k == "meta" and ty == 0x51]
    progs = collections.defaultdict(list)
    ctrls = collections.defaultdict(set)
    bends = 0
    ev = []
    for ti, tr in enumerate(tracks):
        for e in tr:
            if e[1] != "ch":
                continue
            t, _, s, dat = e
            ty, ch = s & 0xF0, s & 15
            if ty == 0xC0:
                progs[ch].append((t, dat[0]))
            elif ty == 0xB0:
                ctrls[ch].add(dat[0])
            elif ty == 0xE0:
                bends += 1
            elif ty == 0x90 and dat[1] > 0:
                ev.append((t, 1, ch, dat[0]))
            elif ty in (0x80, 0x90):
                ev.append((t, 0, ch, dat[0]))
    ev.sort()
    active = collections.Counter()
    cur = mx = 0
    perch = collections.Counter()
    rng = {}
    for t, on, ch, n in ev:
        if on:
            active[(ch, n)] += 1
            cur += 1
            mx = max(mx, cur)
            perch[ch] += 1
            lo, hi = rng.get(ch, (999, -1))
            rng[ch] = (min(lo, n), max(hi, n))
        elif active[(ch, n)] > 0:
            active[(ch, n)] -= 1
            cur -= 1
    last = max((e[0] for tr in tracks for e in tr), default=0)
    length = midi.tick2sec(midi.tempo_map(tracks), div)(last)
    return fmt, div, tracks, tempos, progs, ctrls, bends, perch, rng, mx, length


def main():
    names = sys.argv[1:] or sorted(p.stem for p in paths.MUSIC.glob("*.MID"))
    for n in names:
        fmt, div, tracks, tempos, progs, ctrls, bends, perch, rng, mx, length = analyse(str(paths.MUSIC / (n + ".MID")))
        tl = [(t, round(6e7 / x, 1)) for t, x in tempos][:6]
        print(f"== {n}.MID fmt={fmt} tpb={div} tracks={len(tracks)} len={length:.1f}s tempos={tl}{'...' if len(tempos) > 6 else ''} "
              f"({len(tempos)}) notes={sum(perch.values())} maxpoly={mx} bends={bends}")
        for ch in sorted(set(perch) | set(progs)):
            pl = [pr for _, pr in progs.get(ch, [])]
            print(f"   ch{ch + 1:2d} notes={perch.get(ch, 0):4d} range={rng.get(ch)} progs={sorted(set(pl))} "
                  f"nprog_changes={len(pl)} ctrls={sorted(ctrls.get(ch, []))}")


if __name__ == "__main__":
    main()
