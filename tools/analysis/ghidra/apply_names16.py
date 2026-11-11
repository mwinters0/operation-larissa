# @category Neptune
"""Name the Win16 program (ONWIN.EXE) from what is known of it: names_onwin16.json / labels_onwin16.json (the names you gave),
ONWIN.MAP's publics, and the names of the Win32 counterparts (known pairs and matches_win32.json). win16_names.py says which wins.

  headless:  ./run.sh apply_names16.py           (= part of `mise run ghidra16:import`)
  GUI:       Script Manager > apply_names16.py   (Ghidra opened on the Win16 project by `mise run ghidra16:gui`; then File > Save)

The map's names and our Win32 names are applied to the project only (git-ignored); the committed tables never hold a name of the map.
A function that is the Win32 counterpart of one carries a comment "Win32 0x... (how it is matched)". A function you renamed in the GUI
and have not exported yet is renamed back (and listed): run export_names16.py first. Safe to repeat.

Teaches: applying a derived naming to a program without ever storing the derivation's inputs in the project's own files.
"""
import nepghidra as ng
import win16_map
import win16_names as wn


def address(prog, key):
    return prog.getAddressFactory().getAddress("%04x:%04x" % (win16_map.ghidra_segment(int(key[:4], 16)), int(key[5:], 16)))


def apply(prog, log=print):
    from ghidra.program.flatapi import FlatProgramAPI
    from ghidra.program.model.symbol import SourceType
    import map_names
    ng.check_program16(prog)
    syms = map_names.symbols()
    funcs, labels = wn.expected(syms, *wn.load_tables())
    api = FlatProgramAPI(prog)
    overwritten, renamed = [], 0
    tx = prog.startTransaction("apply names16")
    try:
        for key, (name, comment) in sorted(funcs.items()):
            name = wn.ghidra_name(name)
            ad = address(prog, key)
            if ad is None or not prog.getMemory().contains(ad):
                continue
            f = api.getFunctionAt(ad)
            if f is None:
                if api.getFunctionContaining(ad) is not None:
                    continue
                api.disassemble(ad)
                f = api.createFunction(ad, name)
            if f is None:
                continue
            if f.getName() != name:
                if f.getSymbol().getSource() == SourceType.USER_DEFINED and not wn.AUTO_NAME.match(f.getName()):
                    overwritten.append((key, f.getName(), name))
                same = [s for s in prog.getSymbolTable().getSymbols(ad) if s.getName() == name]
                if same:
                    same[0].setPrimary()                       # the loader already put a label of that name there (an exported entry)
                else:
                    f.setName(name, SourceType.USER_DEFINED)
                renamed += 1
            old = f.getComment()
            if comment and old != comment and (not old or old.startswith(wn.LINK_NOTE) or old == comment):
                f.setComment(comment)
        log("named %d functions (%d changed)" % (len(funcs), renamed))
    finally:
        prog.endTransaction(tx, True)
    tx = prog.startTransaction("apply labels16")
    try:
        counts = {"kept": 0, "created": 0}
        for key, (name, comment) in sorted(labels.items()):
            ad = address(prog, key)
            if ad is not None and prog.getMemory().contains(ad):
                counts[ng.set_label(prog, ad, wn.ghidra_name(name), comment)] += 1
        log("labelled %d globals (%s)" % (len(labels), ", ".join("%d %s" % (v, k) for k, v in counts.items())))
    finally:
        prog.endTransaction(tx, True)
    if overwritten:
        log("renamed %d user-defined functions that differ from what is derived (run export_names16.py first to keep GUI renames):" % len(overwritten))
        for key, old, new in overwritten:
            log("  %s  %s -> %s" % (key, old, new))


ng.run(globals(), apply, win16=True)
