"""match_win32_win16.py on made-up fingerprints (no line of the game): the normalisations, the order chain, the pins, and a whole run
that must find the pairs it was not told, one-to-one and the same every time. The last test reads the committed matches_win32.json
and checks that it holds ids only (no name of the game and none of ours)."""
import json
import random
import re
from pathlib import Path
from types import SimpleNamespace

import pytest

import match_win32_win16 as mm

HERE = Path(__file__).resolve().parent


def make_fps(n: int = 60, orphans32: int = 6, orphans16: int = 6, seed: int = 5) -> tuple[dict, dict, dict[str, str]]:
    """Two builds of the same n functions (plus some that exist in one build only), with distinct shapes and a call graph."""
    rng = random.Random(seed)
    base = []
    for i in range(n):
        base.append(dict(size=40 + rng.randrange(400), cond=rng.randrange(8), back=rng.randrange(3), rets=1 + rng.randrange(3),
                         ext=rng.sample(["GetDC", "ReleaseDC", "LoadStringA", "lstrcpyA", "SetRect", "MessageBoxA", "wsprintfA"], rng.randrange(3)),
                         consts=sorted(rng.sample(range(0x20, 0x3000), rng.randrange(4))), calls=[]))
    for i in range(n):
        base[i]["calls"] = sorted({rng.randrange(n) for _ in range(rng.randrange(4))} - {i})

    def raw32(i, b):
        cf = [len(b["calls"]) + len(b["ext"]), 0, b["cond"], b["back"], b["rets"], 0]
        return dict(id="0x%08x" % (0x401000 + i * 0x40), size=int(b["size"] * 1.2), n=b["size"] // 3, cf=cf, ext=b["ext"],
                    consts=b["consts"], strs=[], fpu=0, calls=["0x%08x" % (0x401000 + c * 0x40) for c in b["calls"]], mod=None)

    def raw16(i, b):
        cf = [len(b["calls"]) + len(b["ext"]), 0, b["cond"], b["back"], b["rets"], 0]
        return dict(id="%04X:%04X" % (1 + i // 20, (i % 20) * 0x30), size=b["size"], n=b["size"] // 2, cf=cf,
                    ext=[e.upper().rstrip("A") for e in b["ext"]], consts=b["consts"], strs=[], fpu=0,
                    calls=["%04X:%04X" % (1 + c // 20, (c % 20) * 0x30) for c in b["calls"]], mod=None)

    f32 = [raw32(i, b) for i, b in enumerate(base)]
    f16 = [raw16(i, b) for i, b in enumerate(base)]
    for k in range(orphans32):
        f32.append(dict(id="0x%08x" % (0x500000 + k * 0x40), size=30, n=10, cf=[0, 0, 0, 0, 1, 0], ext=[], consts=[], strs=[], fpu=0, calls=[], mod=None))
    for k in range(orphans16):
        f16.append(dict(id="%04X:%04X" % (9, k * 0x20), size=31, n=10, cf=[0, 0, 0, 0, 1, 0], ext=[], consts=[], strs=[], fpu=0, calls=[], mod=None))
    truth: dict[str, str] = {str(f32[i]["id"]): str(f16[i]["id"]) for i in range(n)}
    return (dict(version=1, kind="win32", image="ONWIN32.EXE", size=1, functions=f32),
            dict(version=1, kind="win16", image="ONWIN.EXE", size=1, functions=f16), truth)


def test_api_names_meet_across_the_two_spellings():
    vocab = {"GETDC", "LOADSTRING", "CREATEWINDOW", "GETWINDOWWORD"}
    assert mm.api_token("GetDC", vocab) == "GETDC"
    assert mm.api_token("LoadStringA", vocab) == "LOADSTRING"
    assert mm.api_token("CreateWindowExA", vocab) is None          # the alias table maps CREATEWINDOWEX, not the A form
    assert mm.api_token("CreateWindowEx", vocab) == "CREATEWINDOW"
    assert mm.api_token("GetWindowLong", vocab) == "GETWINDOWWORD"
    assert mm.api_token("ExitProcess", vocab) is None


def test_a_32_bit_constant_is_read_as_16_bit_when_it_is():
    assert sorted(mm.consts16([0x20, 0x1234, 0x20000, 0xFFFFFFF0], "win32")) == [0x20, 0x1234, 0xFFF0]
    assert sorted(mm.consts16([0x20, 0xFFF0], "win16")) == [0x20, 0xFFF0]


def test_order_chain_keeps_the_longest_run_in_order_and_windows_lie_between_its_neighbours():
    def pair(a, b):
        return SimpleNamespace(idx=a), SimpleNamespace(idx=b)
    pairs = [pair(1, 10), pair(2, 20), pair(3, 5), pair(4, 30), pair(6, 40)]       # (3, 5) is out of order
    chain = mm.order_chain(pairs)
    assert chain == [(1, 10), (2, 20), (4, 30), (6, 40)]
    assert mm.window(chain, 3) == (20, 30)
    assert mm.window(chain, 0) == (-1, 10)
    assert mm.window(chain, 9)[0] == 40


def test_known_pairs_and_pins_ignore_what_the_fingerprints_do_not_have(tmp_path, capsys):
    ids32, ids16 = {"0x00401000", "0x00401040"}, {"0001:0000", "0001:0030"}
    names = {"0x00401000": {"map": "1:0"}, "0x00401040": {"name": "OurName"}, "0x00409999": {"map": "0001:0030"}, "0x00401002": {"map": "0001:0099"}}
    assert mm.known_pairs(names, ids32, ids16) == {"0x00401000": "0001:0000"}
    assert "2 map references" in capsys.readouterr().err
    pins = tmp_path / "pins.json"
    pins.write_text(json.dumps({"version": 1, "pins": {"0x00401040": "0001:0030", "0x00401000": "0001:0030", "bad": "x"},
                                "rejects": {"0x00401000": ["0001:0030"]}}))
    got, rej = mm.load_pins(pins, ids32, ids16)
    assert got == {"0x00401000": "0001:0030"}                      # the later pin of the same Win16 id is dropped
    assert not rej.get("0x00401000")                               # a reject against a pin is ignored
    assert mm.load_pins(tmp_path / "missing.json", ids32, ids16) == ({}, {})


def test_a_run_finds_the_pairs_it_was_not_told_one_to_one_and_the_same_every_time():
    fp32, fp16, truth = make_fps()
    f32, f16 = mm.build(fp32, fp16)
    by32, by16 = {f.id: f for f in f32}, {f.id: f for f in f16}
    known = sorted(truth)
    held = set(known[::4])                                         # a quarter of the pairs are not told
    train = [(by32[a], by16[truth[a]]) for a in known if a not in held]
    first = mm.run(f32, f16, train, {}, train, random.Random(1))
    again = mm.run(f32, f16, train, {}, train, random.Random(1))
    assert [(r.a.id, r.b.id, round(r.margin, 6)) for r in first] == [(r.a.id, r.b.id, round(r.margin, 6)) for r in again]
    assert len({r.a.id for r in first}) == len(first) and len({r.b.id for r in first}) == len(first)
    got = {r.a.id: r.b.id for r in first}
    right = sum(1 for a in held if got.get(a) == truth[a])
    assert right >= 0.8 * len(held), "found %d of %d" % (right, len(held))
    told = {a for a, _ in train}
    assert not told & set(got), "a pair that was told is matched again"


def test_a_reject_removes_the_pair_and_a_pin_is_kept():
    fp32, fp16, truth = make_fps()
    f32, f16 = mm.build(fp32, fp16)
    by32, by16 = {f.id: f for f in f32}, {f.id: f for f in f16}
    known = sorted(truth)
    train = [(by32[a], by16[truth[a]]) for a in known[1:]]
    target = known[0]
    free = mm.run(f32, f16, train, {}, train, random.Random(1))
    assert {r.a.id: r.b.id for r in free}.get(target) == truth[target]
    rejected = mm.run(f32, f16, train, {target: {truth[target]}}, train, random.Random(1))
    assert {r.a.id: r.b.id for r in rejected}.get(target) != truth[target]


def test_written_matches_hold_ids_and_tiers_only(tmp_path):
    fp32, fp16, truth = make_fps()
    f32, f16 = mm.build(fp32, fp16)
    by32, by16 = {f.id: f for f in f32}, {f.id: f for f in f16}
    known = sorted(truth)
    train = [(by32[a], by16[truth[a]]) for a in known[::2]]
    results = mm.run(f32, f16, train, {}, train, random.Random(1))
    path = tmp_path / "m.json"
    n = mm.write_matches(path, fp32, fp16, results, {"0x00500000": "0009:0000"})
    doc = json.loads(path.read_text())
    assert doc["version"] == 1 and len(doc["matches"]) == n
    assert [m["win32"] for m in doc["matches"]] == sorted(m["win32"] for m in doc["matches"])
    assert {m["tier"] for m in doc["matches"]} <= {"A", "B", "pin"}
    assert len({m["win16"] for m in doc["matches"]}) == n


def test_the_committed_matches_hold_ids_only():
    path = HERE / "matches_win32.json"
    if not path.exists():
        pytest.skip("matches_win32.json is not made yet (uv run tools/analysis/ghidra/match_win32_win16.py match)")
    doc = json.loads(path.read_text())
    ok = re.compile(r"^(0x[0-9a-f]{8}|[0-9A-F]{4}:[0-9A-F]{4}|A|B|pin|ONWIN32\.EXE|ONWIN\.EXE)$")
    assert set(doc) == {"version", "win32", "win16", "matches"}
    for m in doc["matches"]:
        assert set(m) == {"win32", "win16", "tier", "signals", "score", "margin"}
        assert ok.match(m["win32"]) and ok.match(m["win16"]) and ok.match(m["tier"])
        assert all(s in ("pin", "shape", "api", "const", "string", "graph", "order") for s in m["signals"])
    assert len({m["win32"] for m in doc["matches"]}) == len(doc["matches"]) == len({m["win16"] for m in doc["matches"]})
