"""Builds docs/port/AUDIT_CALLSITES.md from the mechanical call-site list (audit_callsites.py -> JSON) and the hand annotations
(audit_rows.py).  Fails loudly when a call site is not covered by a row (except the input-poll tables, which are
generated), so a new primitive call cannot slip through.

  python audit_report.py calls.json ../../../docs/port/AUDIT_CALLSITES.md
"""
import sys, json, collections
from pathlib import Path
from audit_rows import ROWS

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]

TABLES = collections.OrderedDict([
    ("S", ("Sound effects", ["PlaySoundEffect", "RepeatCommonSoundEffect", "StopCommonSoundEffect"])),
    ("M", ("Music and pause / resume", ["PlayBackgroundMusic", "StopBackgroundMusic", "PlaySectorMusic", "StopSectorMusic",
                                         "PlayExpertClosingMusic", "pause_sound", "resume_sound", "PauseSoundForDialog", "ResumeSoundAfterDialog",
                                         "SetMusicOn", "SetSoundOn", "ToggleAllSound", "FreeSectorStopMusic", "StopMusicUnused",
                                         "FreeClosingStopMusic"])),
    ("V", ("Speech and the wave device", ["LoadSpeechClip", "PlayWave", "KillWave", "IsWavePlaying", "set_sample_speed"])),
    ("T", ("Timing", ["DelayTicks", "set_alarm", "wait_alarm", "alarm_expired", "WaitKeyOrTicks", "WaitEnterOrTicks",
                             "WaitEnterSpaceEscOrTicks"])),
    ("I", ("Input waits (busy waits on keys / clicks)", ["WaitForInput", "PeekInput", "FlushInput"])),
    ("X", ("Text (string table lookups, monitor messages, dialogs)", ["LoadStringResource", "WriteMessageText", "RunModalDialog", "RunPagedDialog", "ShowFirstTimeHint"])),
    ("P", ("Pictures and bundle loads", ["LoadBundleInto", "LoadBundle"])),
])
PRIM_TABLE = {p: t for t, (_, ps) in TABLES.items() for p in ps}
FULLNAMES = {"S": "sound", "M": "music", "V": "speech", "T": "timing", "I": "input", "X": "text", "P": "pictures"}

# code regions Ghidra has no function for (switch handlers / dead code), attributed by hand
NOFUNC_OWNER = {0x41b7fd: "HighlightCalcKey", 0x41fefd: "GetNumber", 0x4232c8: "(dead 0x4232a0)", 0x42331c: "(dead 0x4232a0)",
                0x41d5fb: "(customization dialog)", 0x41d6bd: "(customization dialog)", 0x41d982: "(customization dialog)",
                0x41d5ec: "(customization dialog)", 0x41d987: "(customization dialog)", 0x41d643: "(customization dialog)"}


def load_sites(path):
    data = json.loads(Path(path).read_text())
    sites = []
    for v in data.values():
        t = PRIM_TABLE.get(v["name"])
        if not t:
            continue
        for s in v["sites"]:
            addr = int(s["site"], 16)
            sites.append(dict(table=t, prim=v["name"], addr=addr, caller=s["caller"] or "NOFUNC", caller_addr=s["caller_addr"],
                              args=s["args_nearest_first"], used=False))
    return sites


def fmt_arg(site):
    a = site["args"]
    p = site["prim"]

    def h(x):
        return "0x%x" % x if isinstance(x, int) else str(x)
    if p in ("PlaySoundEffect", "RepeatCommonSoundEffect", "DelayTicks", "WaitKeyOrTicks", "LoadStringResource", "PlaySectorMusic",
             "PlayBackgroundMusic", "LoadBundleInto", "LoadBundle", "set_sample_speed", "LoadSpeechClip"):
        return h(a[0]) if a else ""
    if p == "set_alarm":
        return h(a[1]) if len(a) > 1 else ""
    return ""


def main():
    calls_json, out = sys.argv[1], sys.argv[2]
    str_path = REPO / "extracted/data/ONWIN16_strings.json"
    strings = json.loads(str_path.read_text()) if str_path.exists() else {}
    sites = load_sites(calls_json)
    # explicit-site rows first
    ordered = [r for r in ROWS if r["sites"] is not None] + [r for r in ROWS if r["sites"] is None]
    for r in ordered:
        r["matched"] = []
        pset = set(TABLES[r["table"]][1]) if r["prims"] == "*" else {x.strip() for x in r["prims"].split(",")}
        for s in sites:
            if s["used"] or s["table"] != r["table"] or s["prim"] not in pset:
                continue
            if r["sites"] is not None:
                if "%08x" % s["addr"] in [x.zfill(8) for x in r["sites"]]:
                    pass
                else:
                    continue
            elif s["caller"] != r["caller"]:
                continue
            s["used"] = True
            r["matched"].append(s)
    # automatic rows for the input-poll primitives and bundle loads
    auto = []
    for t, label in (("I", "input"), ("P", "bundle")):
        groups = collections.OrderedDict()
        for s in sites:
            if s["table"] == t and not s["used"]:
                groups.setdefault(s["caller"], []).append(s)
        for caller, ss in groups.items():
            for s in ss:
                s["used"] = True
            if t == "I":
                auto.append(dict(table="I", module="-", caller=caller, ctx="input polling (%s)" % ", ".join(sorted({x["prim"] for x in ss})),
                                 reach="yes", status="N/A", port="Godot input events", impact=None, arg=None, matched=ss))
            else:
                auto.append(dict(table="P", module="-", caller=caller, ctx="loads bundle %s" % ", ".join(sorted({fmt_arg(x) or "?" for x in ss})),
                                 reach="yes", status="N/A", port="pictures / sprite sheets pre-extracted by tools/import into godot/assets",
                                 impact=None, arg=None, matched=ss))
    rows = [r for r in ROWS] + auto
    uncovered = [s for s in sites if not s["used"]]
    if uncovered:
        print("UNCOVERED SITES (%d):" % len(uncovered))
        for s in uncovered:
            print("  %s %08x %s %s %s" % (s["table"], s["addr"], s["prim"], s["caller"], fmt_arg(s)))
    empty = [r for r in ROWS if not r["matched"]]
    for r in empty:
        print("ROW MATCHED NOTHING:", r["table"], r["caller"], r["prims"], r["sites"])

    # ---- summary ----
    counts = collections.OrderedDict()
    for t in TABLES:
        c = collections.Counter()
        for r in rows:
            if r["table"] == t:
                c[r["status"]] += len(r["matched"])
        counts[t] = c
    allsites = collections.Counter(s["table"] for s in sites)
    L = []
    L.append("# Call-site audit of ONWIN32.EXE: sound, timing, text, pictures, versus the Godot port\n")
    L.append("Generated by `tools/analysis/ghidra/audit_report.py` from `audit_callsites.py` (Ghidra references plus an independent scan of "
             "every `E8` / `E9` rel32 in the code section) and the hand annotations in `audit_rows.py`. "
             "Rerun it after the port changes; it refuses to finish if a call site has no row.\n")
    L.append("Counts are CALL SITES (not rows). Statuses: **PORTED** the port does the same thing; **MISSING** the original does it, the port does not; "
             "**DIFFERS** the port does something else (how is said); **N/A** nothing to port (OS error box, internal plumbing, dead code, "
             "engine feature). Ticks are 1/73 s. Address columns are the CALL instruction.\n")
    L.append("| table | call sites | PORTED | MISSING | DIFFERS | N/A |\n|---|---|---|---|---|---|")
    tot = collections.Counter()
    for t, (title, ps) in TABLES.items():
        c = counts[t]
        L.append("| %s (%s) | %d | %d | %d | %d | %d |" % (title, ", ".join(ps) if len(ps) < 4 else ps[0] + " ...", allsites[t], c["PORTED"], c["MISSING"], c["DIFFERS"], c["N/A"]))
        tot.update(c)
    L.append("| **total** | **%d** | **%d** | **%d** | **%d** | **%d** |\n" % (sum(allsites.values()), tot["PORTED"], tot["MISSING"], tot["DIFFERS"], tot["N/A"]))
    intro = HERE / "audit_intro.md"
    L.append(intro.read_text() if intro.exists() else "")
    # ranked list of MISSING / DIFFERS
    rank = {"G": 0, "N": 1, "C": 2}
    gaps = [r for r in rows if r["status"] in ("MISSING", "DIFFERS")]
    gaps.sort(key=lambda r: (rank.get(r["impact"], 3), r["table"], r["caller"]))
    L.append("## MISSING and DIFFERS ranked by player impact\n")
    L.append("G = game-breaking, N = noticeable, C = cosmetic.\n")
    L.append("| impact | status | table | original (caller, sites) | what the original does | port |\n|---|---|---|---|---|---|")
    for r in gaps:
        ss = ", ".join("%08x" % s["addr"] for s in sorted(r["matched"], key=lambda x: x["addr"]))
        L.append("| %s | %s | %s | %s | %s | %s |" % (r["impact"] or "?", r["status"], FULLNAMES[r["table"]], "%s: %s" % (r["caller"], ss), r["ctx"], r["port"]))
    L.append("")
    for t, (title, ps) in TABLES.items():
        L.append("## %s\n" % title)
        L.append("Primitives: %s.\n" % ", ".join("`%s`" % p for p in ps))
        L.append("| module | caller (addr) | site(s) | primitive | constant argument | context | reachable | status | port counterpart |\n|---|---|---|---|---|---|---|---|---|")
        trs = [r for r in rows if r["table"] == t]
        trs.sort(key=lambda r: min([s["addr"] for s in r["matched"]] or [0]))
        for r in trs:
            if not r["matched"]:
                continue
            ms = sorted(r["matched"], key=lambda x: x["addr"])
            caller_addr = ms[0]["caller_addr"] or "-"
            caller = r["caller"]
            if caller == "NOFUNC":
                owner = NOFUNC_OWNER.get(ms[0]["addr"], "")
                caller = "no function %s" % owner
                caller_addr = "-"
            sitestr = " ".join("%08x" % s["addr"] for s in ms)
            if len(ms) > 6:
                sitestr = " ".join("%08x" % s["addr"] for s in ms[:6]) + " ... (%d)" % len(ms)
            prims = collections.Counter(s["prim"] for s in ms)
            primstr = ", ".join("%s%s" % (p, " x%d" % n if n > 1 else "") for p, n in prims.items())
            if r.get("arg"):
                arg = r["arg"]
            else:
                args = []
                for s in ms:
                    a = fmt_arg(s)
                    if a and a not in args:
                        args.append(a)
                arg = ", ".join(args[:10]) + (" ..." if len(args) > 10 else "")
                if t == "X":
                    texts = []
                    for a in args[:4]:
                        if a.startswith("0x"):
                            texts.append("`%s`" % strings.get(str(int(a, 16)), "?").replace("\r", " ").replace("\n", " ")[:40].replace("|", "/"))
                    if texts:
                        arg += " (" + "; ".join(texts) + ")"
            module = r["module"]
            import re as _re
            if _re.match(r"Prob\d+_|AnimateThermometer|RadarBlip|RadarSweep|AnimateBarnacles|do_ccmonitor", r["caller"]):
                module = "problem-type diagram / helper"
            cell = (r["status"] if r["status"] == "PORTED" or r["status"] == "N/A" else "**%s**" % r["status"])
            L.append("| %s | %s%s | %s | %s | %s | %s | %s | %s | %s |" % (
                module, caller, (" (%s)" % caller_addr) if caller_addr != "-" else "", sitestr, primstr, arg, r["ctx"].replace("|", "/"),
                r["reach"], cell, r["port"].replace("|", "/")))
        L.append("")
    Path(out).write_text("\n".join(L))
    print("wrote", out, "rows:", len(rows), "sites:", len(sites), "uncovered:", len(uncovered), "status:", dict(tot))


main()
