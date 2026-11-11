# @category Neptune
"""Build the Win16 Ghidra project: ONWIN.EXE (16-bit NE) in ghidra-project16/, with a function at every code public of ONWIN.MAP.

  ./run.sh import_win16.py        (= `mise run ghidra16:import`)

ONWIN.EXE and ONWIN.MAP are read from the CD image (`nepghidra.win16_paths`). The program is imported as x86:LE:16:Protected Mode,
NE segment N at Ghidra segment 0x1000 + (N-1)*8 (`win16_map.ghidra_segment`). Every map public in a code segment becomes a function
entry named w_SSSS_OOOO after its map address (the map's own names are never stored: the project is git-ignored, the names are the
game's); Ghidra's auto-analysis then finds the functions the map does not list, and the entries are placed once more for the publics
the analysis skipped. A second run changes nothing, and a function you renamed in the GUI keeps its name.

The function starts are the ids the DOS build's functions are matched to: a Win16 function is identified by the map
address of its entry, publics or not, and its matches name those ids. Keep this placement as it is, or the ids stop lining up.

Teaches: importing a 16-bit NE executable into PyGhidra, and forcing function entries from a link map.
"""
import sys

import nepghidra as ng
import win16_map


def place_entries(prog, publics):
    """A function at every code public that has none; returns the counts."""
    from ghidra.program.flatapi import FlatProgramAPI
    from ghidra.program.model.symbol import SourceType
    api = FlatProgramAPI(prog)
    fm, mem, af = prog.getFunctionManager(), prog.getMemory(), prog.getAddressFactory()
    stat = dict(entries=0, existing=0, created=0, inside_function=0, no_memory=0, renamed=0)
    tx = prog.startTransaction("map entries")
    try:
        for pub in publics:
            if not 1 <= pub["seg"] <= win16_map.N_CODE_SEGMENTS:
                continue
            stat["entries"] += 1
            a = af.getAddress("%04x:%04x" % (win16_map.ghidra_segment(pub["seg"]), pub["off"]))
            if a is None or not mem.contains(a):
                stat["no_memory"] += 1
                continue
            name = "w_%04X_%04X" % (pub["seg"], pub["off"])
            f = fm.getFunctionAt(a)
            if f is None:
                if fm.getFunctionContaining(a) is not None:
                    stat["inside_function"] += 1
                    continue
                api.disassemble(a)
                f = api.createFunction(a, name)
                stat["created"] += f is not None
            else:
                stat["existing"] += 1
            if f is not None and f.getName().startswith(("FUN_", "w_")) and f.getName() != name:
                f.setName(name, SourceType.USER_DEFINED)       # replaces only a default name or our own id name
                stat["renamed"] += 1
    finally:
        prog.endTransaction(tx, True)
    print("map entries: %s" % stat)
    return stat


def main():
    import pyghidra
    _, map_path = ng.win16_paths()
    publics = win16_map.parse(map_path.read_text(encoding="latin-1"))["publics"]
    with ng.open_program16(analyze=False) as api:
        prog = api.getCurrentProgram()
        lang = str(prog.getLanguageID())
        if lang != "x86:LE:16:Protected Mode":
            raise SystemExit("unexpected language %s for ONWIN.EXE" % lang)
        place_entries(prog, publics)
        opts = prog.getOptions("Neptune")
        if not opts.getBoolean("analyzed", False):
            pyghidra.analyze(prog)
            tx = prog.startTransaction("mark analyzed")
            opts.setBoolean("analyzed", True)
            prog.endTransaction(tx, True)
        place_entries(prog, publics)                       # the entries the analysis skipped; nothing to do on a later run
        print("ONWIN.EXE: %s, %d functions" % (lang, prog.getFunctionManager().getFunctionCount()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
