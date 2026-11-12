"""Melodic and percussion polyphony, the drum keys used and the average drum length (ticks) of each B*.MID.

Teaches: what a base-level MPC card must play at once. A B song needs at most 14 melodic voices at the same time against the
AdLib chip's 6 melodic + 4 rhythm voices; the Windows driver spreads that over the chip's 9 two-operator voices.
Run: `uv run tools/analysis/adlib/poly.py`.
"""
import collections

import midi
import paths

paths.ensure_utf8()

for p in sorted(paths.MUSIC.glob("B*.MID")):
    _, _, tracks = midi.parse(str(p))
    ev = []
    for tr in tracks:
        for t, k, s, d in tr:
            if k != "ch" or s & 0xF0 not in (0x80, 0x90):
                continue
            ev.append((t, 1 if s & 0xF0 == 0x90 and d[1] > 0 else 0, s & 15, d[0]))
    ev.sort()
    cur = {"mel": 0, "perc": 0}
    mx = dict(cur)
    act = collections.Counter()
    drums = collections.Counter()
    dur = []
    start = {}
    for t, on, ch, n in ev:
        k = "perc" if ch == 15 else "mel"
        if on:
            act[(ch, n)] += 1
            cur[k] += 1
            mx[k] = max(mx[k], cur[k])
            if k == "perc":
                drums[n] += 1
                start[n] = t
        elif act[(ch, n)]:
            act[(ch, n)] -= 1
            cur[k] -= 1
            if k == "perc" and n in start:
                dur.append(t - start.pop(n))
    print(p.name, "max melodic poly", mx["mel"], "max perc poly", mx["perc"], "drum keys", sorted(drums),
          "avg drum len ticks", round(sum(dur) / max(1, len(dur)), 1))
