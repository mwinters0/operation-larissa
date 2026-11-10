"""Export decompiled C of ONWIN32.EXE functions.

  python dump_c.py out.c                  # every function (uses names_onwin32.json names)
  python dump_c.py out.c DoMathProblem 0x425772 ...   # selected functions (name or address)
"""
import sys
import nepghidra as ng

def main():
    out = sys.argv[1]; sel = sys.argv[2:]
    with ng.open_program() as api:
        dec = ng.Decompiler(api)
        fs = ng.functions(api)
        if sel:
            keep = []
            for s in sel:
                if s.lower().startswith("0x") or all(c in "0123456789abcdefABCDEF" for c in s) and len(s) >= 6:
                    f = api.getFunctionAt(ng.addr(api, s)); keep += [f] if f else []
                else:
                    keep += [f for f in fs if f.getName() == s]
            fs = keep
        with open(out, "w") as fh:
            for f in fs:
                fh.write("// ==== %s @ %s size=%d\n" % (f.getName(), f.getEntryPoint(), f.getBody().getNumAddresses()))
                fh.write(dec.c(f) + "\n")
        print("wrote %d functions to %s" % (len(fs), out))

main()
