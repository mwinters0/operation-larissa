"""Match the Win32 build's functions to the Win16 build's, and measure how good the match is. Pure standard library.

  uv run tools/analysis/ghidra/match_win32_win16.py evaluate [--folds 5]   # hold out known pairs, match, report precision and recall
  uv run tools/analysis/ghidra/match_win32_win16.py match                  # write matches_win32.json
  uv run tools/analysis/ghidra/match_win32_win16.py report                 # what is matched, what is not and why (counts only)
  mise run ghidra:match                                                    # fingerprints, then match

Inputs: extracted/matching/fp_win32.json and fp_win16.json (export_fingerprints.py), names_onwin32.json (its `{"map": "SSSS:OOOO"}`
entries are the known pairs: ground truth and seeds), pins_win32.json (hand-confirmed pairs and rejects, below).
Output: matches_win32.json: {version, win32: {image, size}, win16: {image, size}, matches: [{win32, win16, tier, signals, score, margin}]},
sorted by win32; one Win16 id per Win32 address and the reverse. Tier "A" and "B" are the matcher's (calibrated by `evaluate`), tier "pin"
a hand-confirmed pair; a weaker match is not written. The known pairs are not written (names_onwin32.json holds them). Ids only.

How it matches. A pair's score is a sum of log likelihood ratios: for each feature of the pair (below), how much more often its value occurs
in a true pair than in a random one, learned from the known pairs. Then rounds of mutual best choices: a pair is taken when each is the other's
best candidate and the lead over the runner-up (the margin) is large enough; taken pairs make the call-graph and order features of the
rest sharper, so the margin asked falls round by round. Features:
  shape   differences of the control-flow counts (calls, conditional jumps, loops, returns, switches, indirect calls), the size ratio, x87
  api     the Windows API calls, normalised across the two spellings (GetDC / GETDC, LoadStringA / LOADSTRING), as a multiset
  const   the immediates above 0xF that the two builds share, weighted by how rare they are (a 32-bit value is read as 16-bit when it is)
  string  string literals both use
  graph   how many of the callees (and callers) already matched to each other the two functions share
  order   the builds link the modules in the same order: a function lies between the Win16 functions its neighbours matched to
`evaluate` is honest: the model of a fold is trained on the other folds' known pairs only, and a held-out pair counts wrong when the matcher
gives either of its functions another partner. Known pairs are the functions larissa named after a Win16 public, a biased sample (large,
named, in game modules); a function larissa named itself has no ground truth, so precision there is what `evaluate` says, not more.

Pins: pins_win32.json = {"version": 1, "pins": {"0x00427bb4": "0010:054A"}, "rejects": {"0x00427bb4": ["0010:0100"]}}. A pin is a seed and
is written with tier "pin"; a reject removes a candidate pair. A stale or malformed entry is ignored with a warning.

Teaches: a likelihood-ratio matcher with a leave-fold-out evaluation, in plain Python.
"""
import argparse
import bisect
import collections
import json
import math
import random
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
FP_DIR = REPO / "extracted" / "matching"
NAMES = HERE / "names_onwin32.json"
PINS = HERE / "pins_win32.json"
MATCHES = HERE / "matches_win32.json"

WIN32_ID = re.compile(r"^0x[0-9a-f]{8}$")
WIN16_ID = re.compile(r"^[0-9A-F]{4}:[0-9A-F]{4}$")

ALPHA = 0.5                                   # smoothing of the background distribution of a table
BETA = 4.0                                    # pseudo-counts that hold a likelihood ratio at zero until true pairs show otherwise
BACKGROUND_PAIRS = 60000                      # random pairs that stand for "not a match" when a table is learned
MARGIN_SCHEDULE = (9.0, 7.0, 5.5, 4.5, 3.5, 3.0)   # the lead over the runner-up asked for in each stage of the rounds
MIN_SCORE = 3.0                               # and the least score a pair needs
TIER_A_MARGIN = 7.0                           # calibrated by `evaluate` (see TIERS in the report it prints)
TIER_B_MARGIN = 3.0
API_ALIASES = {"GETWINDOWLONG": "GETWINDOWWORD", "SETWINDOWLONG": "SETWINDOWWORD", "GETCLASSLONG": "GETCLASSWORD",
               "SETCLASSLONG": "SETCLASSWORD", "CREATEWINDOWEX": "CREATEWINDOW", "GETWINDOWLONGPTR": "GETWINDOWWORD",
               "SETWINDOWLONGPTR": "SETWINDOWWORD"}


def warn(msg):
    print("WARNING: " + msg, file=sys.stderr, flush=True)


def load_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


# -- inputs -----------------------------------------------------------------------------------------------------------------

def win16_key(text):
    """'5:1a3' / '0005:01A3' -> '0005:01A3', or None."""
    try:
        seg, off = (int(x, 16) for x in str(text).split(":"))
    except ValueError:
        return None
    return "%04X:%04X" % (seg, off)


def known_pairs(names, ids32, ids16):
    """{win32 id: win16 id} from the `{"map": ...}` entries of names_onwin32.json that both fingerprints know."""
    out, stale = {}, 0
    for key, entry in names.items():
        if not isinstance(entry, dict) or "map" not in entry:
            continue
        try:
            a = "0x%08x" % int(key, 16)
        except ValueError:
            continue
        w = win16_key(entry["map"])
        if a in ids32 and w in ids16:
            out[a] = w
        else:
            stale += 1
    if stale:
        warn("%d map references name a function the fingerprints do not have (data, or an address that is not a function start)" % stale)
    return out


def load_pins(path, ids32, ids16):
    pins, rejects = {}, collections.defaultdict(set)
    if path is None or not Path(path).exists():
        return pins, rejects
    raw = load_json(path)
    claimed = {}
    for a, w in sorted(raw.get("pins", {}).items()):
        if not WIN32_ID.match(str(a)) or not WIN16_ID.match(str(w)) or a not in ids32 or w not in ids16:
            warn("pin %s -> %s: malformed or not in the fingerprints, ignored" % (a, w))
        elif w in claimed:
            warn("pin %s -> %s: %s is already pinned to %s, ignored" % (a, w, w, claimed[w]))
        else:
            pins[a] = w
            claimed[w] = a
    for a, ws in sorted(raw.get("rejects", {}).items()):
        for w in ws:
            if a in ids32 and w in ids16 and pins.get(a) != w:
                rejects[a].add(w)
            else:
                warn("reject %s -> %s: malformed, stale or against a pin, ignored" % (a, w))
    return pins, rejects


# -- function data ----------------------------------------------------------------------------------------------------------

class Func:
    """What the matcher reads of one function of either build, precomputed."""
    __slots__ = ("callees", "callers", "cf", "consts", "fpu", "id", "idx", "region", "size", "strs", "token_key", "tokens")

    def __init__(self, raw, idx, kind, vocab):
        self.id, self.idx, self.size = raw["id"], idx, raw["size"]
        self.region = None                      # Win16: the kind of the map module the function lies in ("game" or "rtl")
        self.cf = tuple(raw["cf"])
        self.tokens = collections.Counter(t for t in (api_token(e, vocab) for e in raw["ext"]) if t)
        self.token_key = tuple(sorted(self.tokens.items()))
        self.consts = frozenset(consts16(raw["consts"], kind))
        self.strs = frozenset(raw["strs"])
        self.fpu = raw["fpu"] > 0
        self.callees = set(raw["calls"])
        self.callers = set()


def consts16(values, kind):
    """The immediates as 16-bit values; a 32-bit constant that does not fit 16 bits (as unsigned or sign-extended) is dropped."""
    for c in values:
        if kind == "win16" or c <= 0xFFFF:
            yield c
        elif c >= 0xFFFF8000:
            yield c & 0xFFFF


def api_token(name, vocab):
    """An API name in the spelling both builds share, or None when only one build has that function."""
    u = name.upper()
    if u in vocab:
        return u
    if u in API_ALIASES and API_ALIASES[u] in vocab:
        return API_ALIASES[u]
    if u[-1:] in ("A", "W") and u[:-1] in vocab:
        return u[:-1]
    return None


def build(fp32, fp16):
    """(functions32, functions16): lists of Func in address order with the callers filled in."""
    vocab16 = {e.upper() for f in fp16["functions"] for e in f["ext"]}
    vocab = {t for t in (api_token(e, vocab16) for f in fp32["functions"] for e in f["ext"]) if t}
    vocab &= vocab16
    out = []
    for fp, kind in ((fp32, "win32"), (fp16, "win16")):
        funcs = [Func(raw, i, kind, vocab) for i, raw in enumerate(fp["functions"])]
        by_id = {f.id: f for f in funcs}
        for f in funcs:
            f.callees = {c for c in f.callees if c in by_id and c != f.id}
            for c in f.callees:
                by_id[c].callers.add(f.id)
        out.append(funcs)
    mods = fp16.get("modules", [])
    for f, raw in zip(out[1], fp16["functions"]):
        if raw.get("mod") is not None and raw["mod"] < len(mods):
            f.region = mods[raw["mod"]]["kind"]
    return out[0], out[1]


# -- the model --------------------------------------------------------------------------------------------------------------

def clip(x, lo, hi):
    return lo if x < lo else min(x, hi)


def size_class(n):
    return 0 if n < 24 else 1 if n < 80 else 2 if n < 300 else 3


def fit_table(true_keys, bg_keys):
    """{key: log likelihood ratio}. A key's slot is its first element; within a slot the background gives the expectation of a random
    pair and the true pairs move it by their counts, BETA pseudo-counts strong, so a value seen once or twice stays near zero."""
    slots = collections.defaultdict(set)
    for k in list(true_keys) + list(bg_keys):
        slots[k[0]].add(k)
    table = {}
    for ks in slots.values():
        nt, nb = sum(true_keys[k] for k in ks), sum(bg_keys[k] for k in ks)
        for k in ks:
            p = (bg_keys[k] + ALPHA) / (nb + ALPHA * (len(ks) + 1))
            q = (true_keys[k] + BETA * p) / (nt + BETA)
            table[k] = math.log(q / p)
    return table


class Model:
    """The static features of a pair (shape, api, const, string), learned from `train`, a list of (Func32, Func16) true pairs."""

    def __init__(self, funcs32, funcs16, train, rng):
        df = collections.Counter()
        for f in funcs32 + funcs16:
            df.update(f.consts)
        n = len(funcs32) + len(funcs16)
        self.const_weight = {c: math.log(n / k) for c, k in df.items()}
        self.token_df = collections.Counter(f.token_key for f in funcs16 if f.token_key)
        true_keys = collections.Counter()
        for a, b in train:
            true_keys.update(self.keys(a, b))
        bg_keys = collections.Counter()
        for _ in range(BACKGROUND_PAIRS):
            bg_keys.update(self.keys(rng.choice(funcs32), rng.choice(funcs16)))
        self.table = fit_table(true_keys, bg_keys)

    def keys(self, a, b):
        return [("calls", clip(a.cf[0] - b.cf[0], -3, 3)), ("cond", clip(a.cf[2] - b.cf[2], -3, 3)),
                ("back", clip(a.cf[3] - b.cf[3], -1, 1)), ("rets", clip(a.cf[4] - b.cf[4], -2, 2)),
                ("switch", clip(a.cf[5] - b.cf[5], -1, 1)), ("icall", clip(a.cf[1] - b.cf[1], -1, 1)),
                ("fpu", a.fpu == b.fpu),
                ("size", size_class(b.size), clip(round(math.log2(max(a.size, 1) / max(b.size, 1)) * 3), -7, 6)),
                ("api",) + self.api_key(a, b), ("const", self.const_bucket(a, b)), ("string", self.string_bucket(a, b))]

    def api_key(self, a, b):
        ta, tb = a.tokens, b.tokens
        if not ta and not tb:
            return ("none",)
        if not ta or not tb:
            return ("one",)
        if ta == tb:
            return ("equal", clip(self.token_df.get(b.token_key, 1), 1, 4))
        j = sum((ta & tb).values()) / sum((ta | tb).values())
        return ("overlap", 3 if j >= 0.5 else 2 if j > 0 else 1)

    def const_bucket(self, a, b):
        if not a.consts or not b.consts:
            return "empty"
        w = sum(self.const_weight.get(c, 0.0) for c in a.consts & b.consts)
        return 0 if w == 0 else 1 if w < 3 else 2 if w < 7 else 3 if w < 14 else 4

    @staticmethod
    def string_bucket(a, b):
        if not a.strs or not b.strs:
            return "empty"
        return 1 if a.strs & b.strs else 0

    def score(self, a, b):
        t = self.table
        return sum(t.get(k, 0.0) for k in self.keys(a, b))


class Context:
    """The pairs matched so far, and from them what each function's matched neighbours are (as Win16 positions)."""

    def __init__(self, f32, f16, pairs):
        by32 = {f.id: f for f in f32}
        by16 = {f.id: f for f in f16}
        m32 = {a.idx: b.idx for a, b in pairs}
        m16 = {b: a for a, b in m32.items()}
        # a Win32 function's matched callees / callers, as the Win16 positions they matched to
        self.n32 = {f.idx: (frozenset(m32[by32[c].idx] for c in f.callees if by32[c].idx in m32),
                            frozenset(m32[by32[c].idx] for c in f.callers if by32[c].idx in m32)) for f in f32}
        # a Win16 function's matched callees / callers, as Win16 positions
        self.n16 = {f.idx: (frozenset(by16[c].idx for c in f.callees if by16[c].idx in m16),
                            frozenset(by16[c].idx for c in f.callers if by16[c].idx in m16)) for f in f16}


class Graph:
    """The call-graph and order evidence: how the callees and callers matched so far agree, and where a function lies between its neighbours."""

    def __init__(self, f32, f16, train, rng, bg_pairs=20000):
        ctx = Context(f32, f16, train)
        true_keys, bg_keys = collections.Counter(), collections.Counter()
        for a, b in train:
            true_keys.update(self.keys(ctx.n32[a.idx], ctx.n16[b.idx]))
        for _ in range(bg_pairs):
            bg_keys.update(self.keys(ctx.n32[rng.choice(f32).idx], ctx.n16[rng.choice(f16).idx]))
        self.table = fit_table(true_keys, bg_keys)
        self.zero = [self.table.get((name, 0, 0, 0), 0.0) for name in ("callee", "caller")]
        chain = order_chain(train)
        inside = sum(1 for a, b in train if window(chain, a.idx)[0] < b.idx < window(chain, a.idx)[1])
        self.p_in = (inside + 1) / (len(train) + 2)

    @staticmethod
    def keys(na, nb):
        out = []
        for slot, name in enumerate(("callee", "caller")):
            ia, ib = na[slot], nb[slot]
            both = len(ia & ib) if ia and ib else 0
            out.append((name, clip(both, 0, 3), clip(len(ia) - both, 0, 2), clip(len(ib) - both, 0, 2)))
        return out

    def score(self, na, nb):
        """The log likelihood ratio of the call-graph evidence of one pair; the common case, no matched neighbour at all, is a lookup."""
        total = 0.0
        t = self.table
        for slot, name in enumerate(("callee", "caller")):
            ia, ib = na[slot], nb[slot]
            if not ia and not ib:
                total += self.zero[slot]
                continue
            both = len(ia & ib) if ia and ib else 0
            total += t.get((name, clip(both, 0, 3), clip(len(ia) - both, 0, 2), clip(len(ib) - both, 0, 2)), 0.0)
        return total


def order_chain(pairs):
    """The pairs (Func32, Func16) that are in the same order in both builds: a longest increasing subsequence of the Win16 positions.
    Returns [(Win32 position, Win16 position)]."""
    pairs = sorted(pairs, key=lambda p: p[0].idx)
    tails, tail_at, prev = [], [], [-1] * len(pairs)
    for i, (_, b) in enumerate(pairs):
        k = bisect.bisect_left(tails, b.idx)
        if k == len(tails):
            tails.append(b.idx)
            tail_at.append(i)
        else:
            tails[k], tail_at[k] = b.idx, i
        prev[i] = tail_at[k - 1] if k else -1
    chain, i = [], tail_at[-1] if tail_at else -1
    while i >= 0:
        chain.append((pairs[i][0].idx, pairs[i][1].idx))
        i = prev[i]
    chain.reverse()
    return chain


def window(chain, idx32):
    """(lo, hi): the Win16 positions of the chain's neighbours of Win32 position idx32 (exclusive), the position itself left out."""
    xs = [c[0] for c in chain]
    i = bisect.bisect_left(xs, idx32)
    j = bisect.bisect_right(xs, idx32)
    return (chain[i - 1][1] if i > 0 else -1), (chain[j][1] if j < len(chain) else 10 ** 9)


# -- the matching -----------------------------------------------------------------------------------------------------------

class Result:
    def __init__(self, a, b, score, margin, stage, signals=()):
        self.a, self.b, self.score, self.margin, self.stage, self.signals = a, b, score, margin, stage, list(signals)


def run(f32, f16, seeds, rejects, train, rng, log=None):
    """Match the functions not in `seeds`; the model is trained on `train`. Returns [Result] in the order taken."""
    model = Model(f32, f16, train, rng)
    graph = Graph(f32, f16, train, rng)
    pos16 = {f.id: f.idx for f in f16}
    static = [[model.score(a, b) for b in f16] for a in f32]
    for a in f32:
        for w in rejects.get(a.id, ()):
            static[a.idx][pos16[w]] = -1e9
    matched = list(seeds)
    taken32, taken16 = {a.idx for a, _ in matched}, {b.idx for _, b in matched}
    results = []
    for stage, need in enumerate(MARGIN_SCHEDULE):
        while True:
            new = take_round(f32, f16, static, model, graph, matched, taken32, taken16, need)
            if not new:
                break
            for r in new:
                taken32.add(r.a.idx)
                taken16.add(r.b.idx)
                matched.append((r.a, r.b))
                r.stage = stage
                results.append(r)
            if log:
                log("margin >= %.1f: %d new, %d matched in all" % (need, len(new), len(matched)))
    return results


def take_round(f32, f16, static, model, graph, matched, taken32, taken16, need):
    """One round: every pair that is the best of both its functions, by `need` over their runners-up and over MIN_SCORE."""
    ctx = Context(f32, f16, matched)
    chain = order_chain(matched)
    free16 = [b for b in f16 if b.idx not in taken16]
    free_pos = [b.idx for b in free16]
    best_s, best_a, second_s = {}, {}, {}                         # per free Win16 function: its best score, whose it is, its runner-up
    top = {}                                                      # per free Win32 function: (best, runner-up, Win16 function)
    for a in f32:
        if a.idx in taken32:
            continue
        lo, hi = window(chain, a.idx)
        n_in = bisect.bisect_left(free_pos, hi) - bisect.bisect_right(free_pos, lo)
        frac = clip(n_in / max(len(free16), 1), 0.002, 0.98)
        ins, outs = math.log(graph.p_in / frac), math.log((1 - graph.p_in) / (1 - frac))
        na, row = ctx.n32[a.idx], static[a.idx]
        s1, s2, arg = -1e9, -1e9, None
        for b in free16:
            s = row[b.idx]
            if s < -1e8:
                continue
            s += (ins if lo < b.idx < hi else outs) + graph.score(na, ctx.n16[b.idx])
            if s > s1:
                s1, s2, arg = s, s1, b
            elif s > s2:
                s2 = s
            bi = b.idx
            if s > best_s.get(bi, -1e9):
                second_s[bi] = best_s.get(bi, -1e9)
                best_s[bi], best_a[bi] = s, a.idx
            elif s > second_s.get(bi, -1e9):
                second_s[bi] = s
        if arg is not None:
            top[a.idx] = (s1, s2, arg)
    new = []
    for ai, (s1, s2, b) in top.items():
        if best_a[b.idx] != ai or s1 < MIN_SCORE:
            continue
        margin = min(s1 - s2, s1 - second_s[b.idx])
        if margin >= need:
            a = f32[ai]
            lo, hi = window(chain, a.idx)
            new.append(Result(f32[ai], b, s1, margin, 0, explain(model, graph, ctx, a, b, lo < b.idx < hi)))
    return new


SHAPE_SLOTS = ("calls", "cond", "back", "rets", "switch", "icall", "fpu", "size")


def explain(model, graph, ctx, a, b, in_window):
    """The features that carried a pair (each worth at least one nat), in a fixed order."""
    by_slot: dict[str, float] = collections.defaultdict(float)
    for k in model.keys(a, b):
        by_slot["shape" if k[0] in SHAPE_SLOTS else k[0]] += model.table.get(k, 0.0)
    names = [name for name in ("shape", "api", "const", "string") if by_slot[name] >= 1.0]
    if graph.score(ctx.n32[a.idx], ctx.n16[b.idx]) >= 1.0:
        names.append("graph")
    if in_window:
        names.append("order")
    return names


# -- evaluation and output --------------------------------------------------------------------------------------------------

def tier_of(margin):
    return "A" if margin >= TIER_A_MARGIN else "B" if margin >= TIER_B_MARGIN else None


def evaluate(f32, f16, truth, pins, rejects, folds, seed=1, orphans=False):
    """Hold out each fold of the known pairs in turn; returns [(Result, correct)] for every taken pair that involves a held-out function.

    With `orphans`, the held-out Win32 functions also lose their Win16 partners (no function of the pool may take them): they stand for the
    functions that have no counterpart, so every pair taken for one of them is wrong."""
    by32 = {f.id: f for f in f32}
    by16 = {f.id: f for f in f16}
    known = sorted(truth)
    out = []
    held_all = 0
    for k in range(folds):
        held = {a for i, a in enumerate(known) if i % folds == k}
        train = [(by32[a], by16[truth[a]]) for a in known if a not in held]
        seeds = train + [(by32[a], by16[w]) for a, w in sorted(pins.items()) if a not in held]
        gone = {}
        if orphans:
            gone = {a.id: {truth[h] for h in held} for a in f32}
            gone = {a: {*ws, *rejects.get(a, ())} for a, ws in gone.items()}
        results = run(f32, f16, seeds, gone or rejects, train, random.Random(seed + k))
        held16 = {truth[a]: a for a in held}
        held_all += len(held)
        for r in results:
            if r.a.id in held:
                out.append((r, truth[r.a.id] == r.b.id and not orphans))
            elif r.b.id in held16:
                out.append((r, False))
        print("fold %d: %d held out, %d taken" % (k, len(held), len(results)), flush=True)
    return out, held_all


def print_evaluation(out, held, orphans=False):
    if orphans:
        print("\nfunctions without a counterpart: %d; pairs wrongly taken for them: %d" % (held, len(out)))
        for lo, hi in ((9.0, 99), (7.0, 9.0), (5.5, 7.0), (4.5, 5.5), (3.5, 4.5), (3.0, 3.5)):
            print("  margin %.1f .. %s: %d wrongly taken" % (lo, "inf" if hi == 99 else "%.1f" % hi, sum(1 for r, _ in out if lo <= r.margin < hi)))
        return
    print("\nheld-out pairs: %d; taken pairs involving one: %d; correct: %d" % (held, len(out), sum(c for _, c in out)))
    print("%-22s %6s %8s %10s %8s" % ("margin", "taken", "correct", "precision", "recall"))
    edges = [(9.0, 99), (7.0, 9.0), (5.5, 7.0), (4.5, 5.5), (3.5, 4.5), (3.0, 3.5)]
    cum_t = cum_c = 0
    for lo, hi in edges:
        grp = [c for r, c in out if lo <= r.margin < hi]
        cum_t += len(grp)
        cum_c += sum(grp)
        print("%-22s %6d %8d %9.1f%% %7.1f%%   cumulative: precision %.1f%%, recall %.1f%%" % (
            "%.1f .. %s" % (lo, "inf" if hi == 99 else "%.1f" % hi), len(grp), sum(grp), 100 * sum(grp) / max(len(grp), 1),
            100 * sum(grp) / held, 100 * cum_c / max(cum_t, 1), 100 * cum_c / held))
    for tier in ("A", "B"):
        grp = [c for r, c in out if tier_of(r.margin) == tier]
        print("tier %s: %d taken, %d correct, precision %.1f%%" % (tier, len(grp), sum(grp), 100 * sum(grp) / max(len(grp), 1)))
    for region in ("game", "rtl"):
        grp = [(r, c) for r, c in out if r.b.region == region]
        print("Win16 side in %s modules: %d taken, %d correct (%s)" % (region, len(grp), sum(c for _, c in grp), ", ".join(
            "margin >= %.0f: %d/%d" % (t, sum(c for r, c in grp if r.margin >= t), sum(1 for r, c in grp if r.margin >= t)) for t in (3, 7, 9))))
    wrong = sorted((r.margin, r.a.id, r.b.id) for r, c in out if not c)
    print("wrong, by margin (the highest first): " + ", ".join("%.1f %s->%s" % (m, a, b) for m, a, b in reversed(wrong[:12])))


def write_matches(path, fp32, fp16, results, pins):
    rows = [dict(win32=r.a.id, win16=r.b.id, tier=tier_of(r.margin), signals=r.signals, score=round(1 / (1 + math.exp(-r.margin / 2)), 3),
                 margin=round(r.margin, 2)) for r in results if tier_of(r.margin)]
    rows += [dict(win32=a, win16=w, tier="pin", signals=["pin"], score=1.0, margin=None) for a, w in pins.items()]
    rows.sort(key=lambda r: str(r["win32"]))
    doc = dict(version=1, win32=dict(image=fp32["image"], size=fp32["size"]), win16=dict(image=fp16["image"], size=fp16["size"]),
               matches=rows)
    head = json.dumps({k: v for k, v in doc.items() if k != "matches"}, sort_keys=True)[1:-1]
    body = ",\n".join("  " + json.dumps(r, sort_keys=True) for r in rows)          # one match per line: a readable diff
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("{%s,\n \"matches\": [\n%s\n ]}\n" % (head, body))
    return len(rows)


def report(f32, f16, truth, pins, results, publics):
    """Counts only: what is matched and what is not, by region of the Win16 build."""
    by32 = {f.id: f for f in f32}
    by16 = {f.id: f for f in f16}
    taken = [(by32[a], by16[w], "known") for a, w in truth.items()]
    taken += [(by32[a], by16[w], "pin") for a, w in pins.items() if a not in truth]
    taken += [(r.a, r.b, tier_of(r.margin) or "weak") for r in results]
    print("Win32 functions %d, Win16 functions %d" % (len(f32), len(f16)))
    for tier in ("known", "pin", "A", "B", "weak"):
        rows = [t for t in taken if t[2] == tier]
        if rows:
            kinds = collections.Counter(b.region for _, b, _ in rows)
            pub = sum(1 for _, b, _ in rows if b.id in publics) if publics else None
            print("  %-6s %4d   Win16 side: game %d, rtl %d%s" % (tier, len(rows), kinds["game"], kinds["rtl"],
                                                              "" if pub is None else ", a map public %d, no map public %d" % (pub, len(rows) - pub)))
    done32 = {a.id for a, _, t in taken if t != "weak"}
    done16 = {b.id for _, b, t in taken if t != "weak"}
    chain = order_chain([(a, b) for a, b, t in taken if t != "weak"])
    xs = [c[0] for c in chain]
    by_pos16 = {f.idx: f for f in f16}
    free16 = sorted(b.idx for b in f16 if b.id not in done16)
    where = collections.Counter()
    for a in f32:
        if a.id in done32:
            continue
        lo, hi = window(chain, a.idx)
        n_free = bisect.bisect_left(free16, hi) - bisect.bisect_right(free16, lo)
        ends = {by_pos16[p].region for p in (lo, hi) if p in by_pos16}
        kind = ends.pop() if len(ends) == 1 else "boundary"
        where[(kind, "no free Win16 function in the gap" if n_free == 0 else "free Win16 functions in the gap")] += 1
    print("Win32 functions without a match: %d" % (len(f32) - len(done32)))
    for (kind, what), n in sorted(where.items(), key=lambda t: str(t[0])):
        print("  gap in %-8s %-36s %4d" % (kind, what, n))
    del xs


def load_all(args):
    fp32, fp16 = load_json(args.fp_dir / "fp_win32.json"), load_json(args.fp_dir / "fp_win16.json")
    for fp, pat in ((fp32, WIN32_ID), (fp16, WIN16_ID)):
        bad = [f["id"] for f in fp["functions"] if not pat.match(f["id"])]
        if bad:
            raise SystemExit("malformed function ids in a %s fingerprint, e.g. %r" % (fp["kind"], bad[:3]))
    f32, f16 = build(fp32, fp16)
    ids32, ids16 = {f.id for f in f32}, {f.id for f in f16}
    truth = known_pairs(load_json(args.names), ids32, ids16)
    pins, rejects = load_pins(args.pins, ids32, ids16)
    return fp32, fp16, f32, f16, truth, pins, rejects


def main():
    ap = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    ap.add_argument("command", choices=["evaluate", "match", "report"])
    ap.add_argument("--fp-dir", type=Path, default=FP_DIR)
    ap.add_argument("--names", type=Path, default=NAMES)
    ap.add_argument("--pins", type=Path, default=PINS)
    ap.add_argument("--out", type=Path, default=MATCHES)
    ap.add_argument("--folds", type=int, default=5)
    ap.add_argument("--orphans", action="store_true", help="evaluate: hide the held-out functions' partners (functions with no counterpart)")
    args = ap.parse_args()
    fp32, fp16, f32, f16, truth, pins, rejects = load_all(args)
    print("%d Win32 functions, %d Win16 functions, %d known pairs, %d pins" % (len(f32), len(f16), len(truth), len(pins)))
    if args.command == "evaluate":
        out, held = evaluate(f32, f16, truth, pins, rejects, args.folds, orphans=args.orphans)
        print_evaluation(out, held, args.orphans)
        return 0
    by32 = {f.id: f for f in f32}
    by16 = {f.id: f for f in f16}
    train = [(by32[a], by16[w]) for a, w in sorted(truth.items())]
    seeds = train + [(by32[a], by16[w]) for a, w in sorted(pins.items()) if a not in truth]
    results = run(f32, f16, seeds, rejects, train, random.Random(1), log=print)
    if args.command == "report":
        pub_path = REPO / "extracted" / "tables" / "onwin_map.json"
        publics = {win16_key(k) for k in load_json(pub_path)["symbols"]} if pub_path.exists() else None
        report(f32, f16, truth, pins, results, publics)
    if args.command == "match":
        print("wrote %d matches to %s" % (write_matches(args.out, fp32, fp16, results, {a: w for a, w in pins.items() if a not in truth}), args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
