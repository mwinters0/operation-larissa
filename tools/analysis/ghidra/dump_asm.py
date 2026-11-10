"""Export the disassembly of selected functions of ONWIN32.EXE (to check what the decompiler drops, e.g. x87 maths).

  python dump_asm.py out.asm Prob09_Diagram 0x422f64 ...   # functions by name or address
"""
import sys
import nepghidra as ng

def main():
    out = sys.argv[1]; sel = sys.argv[2:]
    with ng.open_program() as api:
        prog = api.getCurrentProgram()
        listing = prog.getListing()
        fs = ng.functions(api)
        keep = []
        for s in sel:
            if s.lower().startswith("0x") or (len(s) >= 6 and all(c in "0123456789abcdefABCDEF" for c in s)):
                f = api.getFunctionAt(ng.addr(api, s)); keep += [f] if f else []
            else:
                keep += [f for f in fs if f.getName() == s]
        with open(out, "w") as fh:
            for f in keep:
                fh.write("; ==== %s @ %s\n" % (f.getName(), f.getEntryPoint()))
                fh.writelines("%s  %s\n" % (ins.getAddress(), ins) for ins in listing.getInstructions(f.getBody(), True))
                fh.write("\n")
        print("wrote %d functions to %s" % (len(keep), out))

main()
