"""Mechanical call-site audit of ONWIN32.EXE.

  python audit_callsites.py out.json [targetAddr ...]

For every target function (default: the sound / timing / string / music primitives) lists every CALL instruction
that references it (Ghidra reference manager), with the caller function and the constant stack arguments that were
pushed just before the call (the cdecl PUSH imm32 chain, walking back through the straight-line code).
Also computes the transitive wrapper closure: a caller whose body is a tiny forwarder is reported with its own callers.
"""
import sys, json
import struct
from pathlib import Path
import nepghidra as ng

DEFAULT = {
 # sound
 0x431f1f: "PlaySoundEffect", 0x431f97: "RepeatCommonSoundEffect", 0x431ef2: "StopCommonSoundEffect",
 0x4151a4: "KillWave", 0x4150c4: "PlayWave", 0x415214: "IsWavePlaying", 0x4150b1: "set_sample_speed",
 0x411315: "LoadSpeechClip",
 0x43206e: "PlayBackgroundMusic", 0x43208f: "StopBackgroundMusic", 0x432064: "StopSectorMusic",
 0x43204d: "PlaySectorMusic", 0x4320cc: "PlayExpertClosingMusic", 0x414145: "pause_sound", 0x414163: "resume_sound",
 # timing
 0x416640: "DelayTicks", 0x416670: "set_alarm", 0x416692: "wait_alarm", 0x4166b5: "alarm_expired",
 0x423549: "WaitKeyOrTicks", 0x415b6c: "WaitForInput", 0x410c6c: "FlushInput", 0x410d50: "PeekInput",
 # text
 0x411726: "LoadStringResource",
 # wrappers around the primitives above (transitive closure of the sound / timing / text helpers)
 0x415ce0: "PauseSoundForDialog", 0x415cea: "ResumeSoundAfterDialog", 0x431db0: "SetMusicOn", 0x431dd9: "SetSoundOn",
 0x431dfb: "ToggleAllSound", 0x432043: "FreeSectorStopMusic", 0x4320ad: "StopMusicUnused", 0x4320c2: "FreeClosingStopMusic",
 0x432ddb: "WaitEnterOrTicks", 0x428fbe: "WaitEnterSpaceEscOrTicks", 0x4174ec: "RunModalDialog", 0x417755: "RunPagedDialog",
 0x4234c0: "WriteMessageText", 0x427e20: "ShowFirstTimeHint",
 # pictures / bundles
 0x411346: "LoadBundleInto", 0x411338: "LoadBundle",
}

def resolve_jump_tables(api):
    """Ghidra leaves the handlers of 'JMP [reg*4+table]' switches (byte-index tables) undisassembled; do it here so their
    CALLs show up. Returns the list of (function entry, jump site, handler count)."""
    prog = api.getCurrentProgram(); listing = prog.getListing(); mem = prog.getMemory(); fm = prog.getFunctionManager()
    done = []
    for ins in list(listing.getInstructions(True)):
        if ins.getMnemonicString() != "JMP":
            continue
        txt = str(ins)
        if "dword ptr [" not in txt or "*0x4" not in txt:
            continue
        # imm table address = last 0x4xxxxx literal in the operand
        import re
        m = re.search(r"\+ 0x(4[0-9a-f]{5})\]", txt)
        if not m:
            continue
        table = int(m.group(1), 16)
        p = ins.getPrevious()
        n = None
        if p is not None and p.getMnemonicString() == "MOV" and "byte ptr [" in str(p):
            m2 = re.search(r"\+ 0x(4[0-9a-f]{5})\]", str(p))
            if m2:
                bt = int(m2.group(1), 16)
                # bound from the CMP just before
                q = p.getPrevious()
                while q is not None and q.getMnemonicString() != "CMP":
                    q = q.getPrevious()
                assert q is not None, "no CMP before the table read"
                bound = int(q.getOpObjects(1)[0].getValue()) + 1
                data = bytes((mem.getByte(api.toAddr(bt + i)) & 0xff) for i in range(bound))
                n = max(data) + 1
        if n is None:
            continue
        targets = set()
        for i in range(n):
            v = mem.getInt(api.toAddr(table + 4 * i)) & 0xffffffff
            targets.add(v)
        for t in targets:
            api.disassemble(api.toAddr(t))
        f = fm.getFunctionContaining(ins.getAddress())
        done.append((str(f.getEntryPoint()) if f else None, str(ins.getAddress()), len(targets)))
    return done


def raw_call_scan(exe_path):
    """Independent cross-check: every E8 / E9 rel32 in the code section, as {target: [site, ...]} (finds calls from code
    Ghidra has not disassembled, e.g. switch handlers or never-called functions)."""
    b = Path(exe_path).read_bytes()
    pe = struct.unpack_from("<I", b, 0x3c)[0]
    nsec = struct.unpack_from("<H", b, pe + 6)[0]; opt = struct.unpack_from("<H", b, pe + 20)[0]
    base = struct.unpack_from("<I", b, pe + 24 + 28)[0]
    o = pe + 24 + opt
    found = {}
    for i in range(nsec):
        name = b[o:o + 8].rstrip(b"\0"); _vs, va, rs, ro = struct.unpack_from("<IIII", b, o + 8); o += 40
        if name not in (b"CODE", b".text"):
            continue
        for j in range(rs - 4):
            if b[ro + j] in (0xE8, 0xE9):
                rel = struct.unpack_from("<i", b, ro + j + 1)[0]
                found.setdefault((base + va + j + 5 + rel) & 0xffffffff, []).append(base + va + j)
    return found


def disassemble_raw_sites(api, raw, targets):
    """Calls the raw scan finds but Ghidra has no instruction for (functions nothing calls, code behind unresolved
    jump tables): walk back to the nearest 'push ebp; mov ebp,esp' and disassemble from there so the CALLs get
    references. Returns the number of regions disassembled."""
    prog = api.getCurrentProgram(); listing = prog.getListing(); mem = prog.getMemory()
    n = 0
    for ta in targets:
        for site in raw.get(ta, []):
            a = api.toAddr(site)
            if listing.getInstructionAt(a) is not None:
                continue
            start = None
            for back in range(0x400):
                b0 = mem.getByte(api.toAddr(site - back)) & 0xff
                if b0 == 0x55 and (mem.getByte(api.toAddr(site - back + 1)) & 0xff) == 0x8b and (mem.getByte(api.toAddr(site - back + 2)) & 0xff) == 0xec:
                    start = site - back
                    break
            if start is not None:
                api.disassemble(api.toAddr(start)); n += 1
    return n


def main():
    out = sys.argv[1]
    targets = {int(a, 16): None for a in sys.argv[2:]} or dict(DEFAULT)
    with ng.open_program() as api:
        prog = api.getCurrentProgram()
        jt = resolve_jump_tables(api)
        print("jump tables resolved:", jt)
        raw = raw_call_scan(str(ng.exe_path()))
        print("regions disassembled from raw-scan call sites:", disassemble_raw_sites(api, raw, list(targets)))
        fm = prog.getFunctionManager(); rm = prog.getReferenceManager(); listing = prog.getListing()
        res = {}
        for ta, name in targets.items():
            f = api.getFunctionAt(api.toAddr(ta))
            name = name or (f.getName() if f else "?")
            sites = []
            for ref in rm.getReferencesTo(api.toAddr(ta)):
                if not ref.getReferenceType().isCall() and not ref.getReferenceType().isJump():
                    continue
                fa = ref.getFromAddress()
                caller = fm.getFunctionContaining(fa)
                # walk back for pushes
                args = []
                ins = listing.getInstructionAt(fa)
                p = ins.getPrevious() if ins else None
                steps = 0
                while p is not None and steps < 14:
                    mn = p.getMnemonicString()
                    if mn in ("CALL", "RET", "JMP") or p.getFlowType().isJump() and not p.getFlowType().isConditional():
                        break
                    if mn == "PUSH":
                        o = p.getOpObjects(0)
                        if o and hasattr(o[0], "getValue"):
                            args.append(int(o[0].getValue()) & 0xffffffff)
                        else:
                            args.append(str(p.getDefaultOperandRepresentation(0)))
                    steps += 1
                    p = p.getPrevious()
                sites.append({"site": str(fa), "caller": caller.getName() if caller else None,
                              "caller_addr": str(caller.getEntryPoint()) if caller else None,
                              "kind": str(ref.getReferenceType()),
                              "args_nearest_first": args[:4]})
            sites.sort(key=lambda s: s["site"])
            res[hex(ta)] = {"name": name, "sites": sites}
        for ta, v in res.items():
            have = {int(x["site"], 16) for x in v["sites"]}
            extra = sorted(set(raw.get(int(ta, 16), [])) - have)
            v["raw_only"] = [hex(x) for x in extra]
            if extra:
                print("WARNING raw scan finds calls Ghidra does not know for", v["name"], [hex(x) for x in extra])
        Path(out).write_text(json.dumps(res, indent=1))
        print("wrote", out, sum(len(v["sites"]) for v in res.values()), "sites")
main()
