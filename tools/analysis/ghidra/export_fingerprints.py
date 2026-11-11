# @category Neptune
"""Export one fingerprint per function of the Win32 or the Win16 program, for the Win32 <-> Win16 matcher (match_win32_win16.py).

  ./run.sh export_fingerprints.py win32 [--out DIR]    # the Win32 project (mise run ghidra:import builds it)
  ./run.sh export_fingerprints.py win16 [--out DIR]    # the Win16 project (mise run ghidra16:import builds it)
  mise run ghidra:fingerprints                         # both

DIR is extracted/matching/ by default. The files hold text of the game (the strings a function uses) and the names of the Windows API
calls it makes, so they are git-ignored like the rest of extracted/; they hold no name of ONWIN.MAP and no name we chose.

Ids: Win32 `0x%08x` (the address), Win16 `SSSS:OOOO` (the map address: NE segment number and offset, win16_map.win16_id).
The Win16 starts are those of import_win16.py, which are those of the DOS build's function ids (the Win16 map address of each entry).

File: {version, kind, image, size, functions: [...], modules: [...] (win16 only)}. A function:
  id, off (Win32: the address; Win16: the offset), seg (Win16: NE segment number; Win32: 0), size (bytes), n (instructions),
  ext    the imported API calls in code order, as the import's own name ("GetDC", "LSTRCAT"); the matcher normalises the two spellings
  strs   the text of the strings its operands point at (at least 3 characters, in code order)
  consts the immediates above 0xF that are not addresses: Win32 as unsigned 32-bit values, Win16 as 16-bit ones (the matcher compares them
         across the two widths)
  calls  the ids of the functions it calls or tail-jumps to, in code order (library imports are `ext`, not `calls`)
  cf     [calls, indirect calls, conditional jumps, backward jumps, returns, computed jumps]
  retn   the `ret N` immediates (a Windows callback's argument bytes: halves from 32- to 16-bit)
  sw     per computed jump, its number of targets (a switch's cases)
  dref   the number of distinct data addresses it reads or writes, fpu (x87 instruction count), ints (INT n vectors)
  mod    Win16: index into `modules` (the map's code modules, address ranges only), else null

Teaches: reading references, thunks and operands out of a Ghidra program through PyGhidra, for a 16- and a 32-bit build alike.
"""
import argparse
import json
import sys
from pathlib import Path

import nepghidra as ng
import win16_map

VERSION = 1
OUT_DIR = ng.REPO / "extracted" / "matching"
WIN32_IMAGE, WIN16_IMAGE = "ONWIN32.EXE", "ONWIN.EXE"
MIN_STRING = 3
MAX_STRING = 200


def win32_id(address):
    return "0x%08x" % address


class Exporter:
    def __init__(self, prog, kind):
        from ghidra.program.model.scalar import Scalar
        self.Scalar = Scalar
        self.prog, self.kind = prog, kind
        self.mem, self.fm, self.lst = prog.getMemory(), prog.getFunctionManager(), prog.getListing()
        self.af, self.rm, self.sym = prog.getAddressFactory(), prog.getReferenceManager(), prog.getSymbolTable()
        self.ds = self.find_ds() if kind == "win16" else None

    # -- identity -------------------------------------------------------------------------------------------------------
    def key(self, addr):
        """(segment, offset, id) of a Ghidra address, in the contract's terms."""
        if self.kind == "win32":
            return 0, addr.getOffset(), win32_id(addr.getOffset())
        seg, off = (int(x, 16) for x in str(addr).split(":"))
        n = (seg - 0x1000) // 8 + 1
        return n, off, win16_map.win16_id(n, off)

    def find_ds(self):
        blocks = [b for b in self.mem.getBlocks() if b.getName().startswith("Data")]
        return int(str(max(blocks, key=lambda b: b.getSize()).getStart()).split(":")[0], 16)

    # -- strings --------------------------------------------------------------------------------------------------------
    def cstring_at(self, a):
        """The printable C string that starts at address a, or None."""
        try:
            if a is None or not self.mem.contains(a):
                return None
            blk = self.mem.getBlock(a)
            if blk is None or blk.isExecute():
                return None
            if a.getOffset() > blk.getStart().getOffset() and self.mem.getByte(a.subtract(1)) != 0:
                return None                                  # must start a string
            out = bytearray()
            for i in range(MAX_STRING + 1):
                c = self.mem.getByte(a.add(i)) & 0xFF
                if c == 0:
                    break
                if not (32 <= c < 127 or c in (9, 10, 13)):
                    return None
                out.append(c)
            else:
                return None
            return out.decode() if len(out) >= MIN_STRING else None
        except Exception:  # noqa: BLE001  (Java's MemoryAccessException and friends: not a string)
            return None

    def string_of_value(self, v):
        if self.kind == "win32":
            return self.cstring_at(self.af.getAddress("0x%x" % (v & 0xFFFFFFFF)))
        return self.cstring_at(self.af.getAddress("%04x:%04x" % (self.ds, v & 0xFFFF)))

    # -- API calls ------------------------------------------------------------------------------------------------------
    def thunk_name(self, f):
        """The import's name when function f is only a stub for an imported function, else None."""
        blk = self.mem.getBlock(f.getEntryPoint())
        if blk is not None and blk.getName() == "EXTERNAL":
            return f.getName()
        if f.isThunk():
            target = f.getThunkedFunction(True)
            return (target if target is not None else f).getName()
        return None

    def external_name(self, to):
        s = self.sym.getPrimarySymbol(to)
        return s.getName() if s is not None else None

    @staticmethod
    def first_scalar(ins):
        """The instruction's first operand as an int, or None when it is not an immediate."""
        sc = ins.getScalar(0)
        return int(sc.getValue()) if sc is not None else None

    # -- one function ---------------------------------------------------------------------------------------------------
    def function(self, f):
        seg, off, fid = self.key(f.getEntryPoint())
        body = f.getBody()
        mask = 0xFFFFFFFF if self.kind == "win32" else 0xFFFF
        consts, strs, calls, ext, ints, retn, sw, drefs = set(), [], [], [], [], [], [], set()
        n = fpu = icalls = cond = back = rets = computed = 0
        for ins in self.lst.getInstructions(body, True):
            m = ins.getMnemonicString().lower()
            if m == "nop":
                continue
            n += 1
            if m.startswith("f") and m != "fs":
                fpu += 1
            if m == "int" and self.first_scalar(ins) is not None:
                ints.append(self.first_scalar(ins))
            if m in ("ret", "retf", "retn") and ins.getNumOperands() == 1 and self.first_scalar(ins) is not None:
                retn.append(self.first_scalar(ins))
            for i in range(ins.getNumOperands()):
                if ins.getOperandRefType(i).isFlow() or "[" in ins.getDefaultOperandRepresentation(i):
                    continue
                for o in ins.getOpObjects(i):
                    if isinstance(o, self.Scalar):
                        v = o.getValue() & mask
                        s = self.string_of_value(v) if v > 0xFF else None
                        if s is not None:
                            strs.append(s)
                        elif v > 0xF and not (self.kind == "win32" and self.mem.contains(self.af.getAddress("0x%x" % v))):
                            consts.add(v)
            ft = ins.getFlowType()
            if ft.isConditional() and ft.isJump():
                cond += 1
            if m in ("ret", "retf", "retn"):
                rets += 1
            if ft.isComputed() and ft.isJump():
                computed += 1
                sw.append(sum(1 for r in self.rm.getReferencesFrom(ins.getAddress()) if r.getReferenceType().isJump()))
            direct = False
            for ref in self.rm.getReferencesFrom(ins.getAddress()):
                rt, to = ref.getReferenceType(), ref.getToAddress()
                if ft.isConditional() and ft.isJump() and rt.isJump() and to.compareTo(ins.getAddress()) <= 0 and body.contains(to):
                    back += 1
                if rt.isData() and to.isMemoryAddress() and not rt.isFlow():
                    blk = self.mem.getBlock(to)
                    if blk is not None and not blk.isExecute() and blk.getName() != "EXTERNAL":
                        drefs.add(str(to))
                if rt.isCall() or (rt.isJump() and rt.isUnConditional() and not body.contains(to)):
                    if to.isExternalAddress():
                        name = self.external_name(to)
                        if name:
                            ext.append(name)
                            direct = True
                        continue
                    tf = self.fm.getFunctionContaining(to)
                    if tf is None:
                        continue
                    name = self.thunk_name(tf)
                    if name:
                        ext.append(name)
                    else:
                        calls.append(self.key(tf.getEntryPoint())[2])
                    direct = True
            if m in ("call", "callf") and not direct:
                icalls += 1
        return dict(id=fid, seg=seg, off=off, size=int(body.getNumAddresses()), n=n, mod=None, consts=sorted(consts), strs=strs,
                    calls=calls, ext=ext, ints=ints, fpu=fpu, retn=retn, sw=sw, dref=len(drefs),
                    cf=[len(calls) + len(ext), icalls, cond, back, rets, computed])

    def functions(self):
        out = []
        for f in self.fm.getFunctions(True):
            blk = self.mem.getBlock(f.getEntryPoint())
            if blk is None or blk.getName() == "EXTERNAL" or not blk.isExecute() or self.thunk_name(f):
                continue                                       # imports and their stubs are `ext`, not functions
            out.append(self.function(f))
        out.sort(key=lambda r: (r["seg"], r["off"]))
        return out


def export(kind, out_dir):
    if kind == "win32":
        ctx, image = ng.open_program(analyze=False), WIN32_IMAGE
    else:
        ctx, image = ng.open_program16(analyze=False), WIN16_IMAGE
    with ctx as api:
        prog = api.getCurrentProgram()
        funcs = Exporter(prog, kind).functions()
    fp = dict(version=VERSION, kind=kind, image=image, size=image_size(kind), functions=funcs)
    if kind == "win16":
        _, map_path = ng.win16_paths()
        mods = win16_map.code_modules(win16_map.parse(map_path.read_text(encoding="latin-1"))["mods"])
        fp["modules"] = [dict(idx=k, **m) for k, m in enumerate(mods)]
        for r in funcs:
            for m in fp["modules"]:
                if m["seg"] == r["seg"] and m["off"] <= r["off"] < m["off"] + m["len"]:
                    r["mod"] = m["idx"]
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / ("fp_%s.json" % kind)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(fp, fh, sort_keys=True, ensure_ascii=True)
        fh.write("\n")
    print("%s: %d functions, %d with strings, %d with API calls -> %s"
          % (kind, len(funcs), sum(1 for r in funcs if r["strs"]), sum(1 for r in funcs if r["ext"]), path))


def image_size(kind):
    return (ng.exe_path() if kind == "win32" else ng.win16_paths()[0]).stat().st_size


def main():
    ap = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[1])
    ap.add_argument("kind", choices=["win32", "win16"])
    ap.add_argument("--out", type=Path, default=OUT_DIR)
    args = ap.parse_args()
    export(args.kind, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
