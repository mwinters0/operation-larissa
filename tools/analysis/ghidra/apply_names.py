# @category Neptune
"""Apply names_onwin32.json (address -> {name, evidence}) and labels_onwin32.json (global address -> name or
{name, evidence}) to ONWIN32.EXE. An entry that names an ONWIN.MAP public holds a reference to it, resolved from the
table the importer made from your ISO (map_names.py); the other names are descriptive. Safe to run repeatedly (existing identical names/labels are left alone, nothing is duplicated).

Two ways to run it:
  headless:  ./run.sh apply_names.py            (opens/creates the project in NEP_GHIDRA_PROJECT)
  GUI:       Script Manager > apply_names.py    (Ghidra started with support/pyghidraRun; applies to the open
                                                 program, then use File > Save). See docs/port/GHIDRA_GUI.md.
A function you renamed in the GUI and have not exported yet is renamed back (and listed): run export_names.py first.
"""
import nepghidra as ng


def apply(prog, names=None, labels=None, log=print):
    """Apply the function names (+ evidence as function comments) and global labels to `prog`."""
    from ghidra.program.flatapi import FlatProgramAPI
    from ghidra.program.model.symbol import SourceType
    ng.check_program(prog)
    names = ng.load_names() if names is None else names
    labels = ng.load_labels() if labels is None else labels
    api = FlatProgramAPI(prog)
    overwritten = []

    tx = prog.startTransaction("apply names")
    try:
        done = 0
        for a, info in names.items():
            ad = ng.addr(api, a)
            f = api.getFunctionAt(ad)
            if f is None:
                api.disassemble(ad)
                f = api.createFunction(ad, info["name"])
            if f is None:
                log("no function at %s" % a)
                continue
            old = f.getName()
            if old != info["name"]:
                if f.getSymbol().getSource() == SourceType.USER_DEFINED:
                    overwritten.append((a, old, info["name"]))
                f.setName(info["name"], SourceType.USER_DEFINED)
            if info.get("evidence") and f.getComment() != info["evidence"]:
                f.setComment(info["evidence"])
            done += 1
        log("renamed %d of %d" % (done, len(names)))
    finally:
        prog.endTransaction(tx, True)

    tx = prog.startTransaction("apply labels")
    try:
        counts = {"kept": 0, "created": 0}
        for a, nm in labels.items():
            # a label is either "name" or {"name": ..., "evidence": ...} (the evidence becomes a plate comment)
            info = nm if isinstance(nm, dict) else {"name": nm}
            ad = ng.addr(api, a)
            counts[ng.set_label(prog, ad, info["name"], info.get("evidence"))] += 1
        log("labelled %d globals (%s)" % (len(labels), ", ".join("%d %s" % (v, k) for k, v in counts.items())))
    finally:
        prog.endTransaction(tx, True)

    if overwritten:
        log("renamed %d user-defined functions that differ from the JSON (run export_names.py first to keep GUI renames):" % len(overwritten))
        for a, old, new in overwritten:
            log("  %s  %s -> %s" % (a, old, new))


ng.run(globals(), apply)
