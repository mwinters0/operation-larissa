"""Round trip of the annotation tools on two throw-away projects (about a minute and a half): makes one annotation of
every kind in project A (comments of all five kinds, a struct with a bitfield and a pointer to itself, a union, an enum,
a typedef, a function definition, typed and cleared data, signatures with dynamic and custom storage, stack and register
locals, a label inside a function, an equate, a Note bookmark, an edited function comment), exports them, applies the file
to a fresh project B, and checks that B exports nothing new; then deletes a comment and a local in B, exports, and checks
that applying the file to A deletes them there too. Needs the ISO (like every script here); not part of pytest.

  ./run.sh check_annotations.py      (exit 1 on the first failed check)

Run it after changing annotations.py or program_annotations.py.

Teaches: testing an export/import pair by its round trip: export, import elsewhere, export again, and compare.
"""
import json
import shutil
import sys
import tempfile
from pathlib import Path

import nepghidra as ng
import annotations as an
import program_annotations as ga

FLUSH_RECT, UPDATE = "0x004120b3", "0x00411bfd"


def ok(cond, what):
    print(("PASS  " if cond else "FAIL  ") + what)
    if not cond:
        sys.exit(1)


def annotate(prog):
    """One annotation of every kind, made through Ghidra's API the way the GUI makes them."""
    from ghidra.program.model.data import (ArrayDataType, CategoryPath, DataTypeConflictHandler, EnumDataType,
                                           FunctionDefinitionDataType, IntegerDataType, ParameterDefinitionImpl,
                                           PointerDataType, StructureDataType, TypedefDataType, UnionDataType,
                                           UnsignedIntegerDataType)
    from ghidra.program.model.listing import Function, LocalVariableImpl, ParameterImpl, ReturnParameterImpl, VariableStorage
    from ghidra.program.model.symbol import SourceType
    w = ga.Writer(prog)
    a = w.addr
    listing, dtm = prog.getListing(), prog.getDataTypeManager()
    cat = CategoryPath("/student")
    tx = prog.startTransaction("annotate")
    try:
        i32 = IntegerDataType.dataType
        rect = dtm.addDataType(StructureDataType(cat, "Rect", 0, dtm), DataTypeConflictHandler.DEFAULT_HANDLER)
        body = StructureDataType(cat, "Rect", 24, dtm)
        body.setPackingEnabled(False)
        for off, name in ((0, "x"), (4, "y"), (8, "w"), (12, "h")):
            body.replaceAtOffset(off, i32, 4, name, "the %s of the box" % name if name == "x" else None)
        body.replaceAtOffset(16, PointerDataType(rect, dtm), 4, "next", None)
        body.insertBitFieldAt(20, 4, 0, UnsignedIntegerDataType.dataType, 3, "flags", "dirty, shown, clipped")
        rect.replaceWith(body)
        rect.setDescription("a dirty rectangle (made up for the check)")
        u = UnionDataType(cat, "Value", dtm)
        u.add(i32, 4, "i", None)
        u.add(PointerDataType(rect, dtm), 4, "r", None)
        dtm.addDataType(u, DataTypeConflictHandler.DEFAULT_HANDLER)
        e = EnumDataType(cat, "Colour", 1, dtm)
        e.add("BLACK", 0, None)
        e.add("WHITE", 15, "the brightest ink")
        dtm.addDataType(e, DataTypeConflictHandler.DEFAULT_HANDLER)
        dtm.addDataType(TypedefDataType(cat, "coord", i32, dtm), DataTypeConflictHandler.DEFAULT_HANDLER)
        fn = FunctionDefinitionDataType(cat, "FlushFn", dtm)
        fn.setArguments([ParameterDefinitionImpl(n, i32, None) for n in ("x", "y", "w", "h")])
        dtm.addDataType(fn, DataTypeConflictHandler.DEFAULT_HANDLER)

        free = _undefined_run(prog, 64)
        listing.createData(free, rect)
        listing.createData(free.add(32), ArrayDataType(w.resolve("/student/coord"), 4, 4, dtm))
        cleared = _a_baseline_datum(prog)
        listing.clearCodeUnits(cleared, cleared, False)

        for kind, code in ga.KINDS.items():
            listing.setComment(a("0x004120c8"), code, "%s comment\nwith a second line" % kind)
        listing.setComment(a(FLUSH_RECT), ga.KINDS["plate"], "FlushRect: an edited function comment")

        f = prog.getFunctionManager().getFunctionAt(a(FLUSH_RECT))
        f.updateFunction("__cdecl", ReturnParameterImpl(w.resolve("/void"), prog),
                         ga.java_list([ParameterImpl(n, w.resolve("/student/coord"), prog) for n in ("x", "y", "width", "height")]),
                         Function.FunctionUpdateType.DYNAMIC_STORAGE_ALL_PARAMS, True, SourceType.USER_DEFINED)
        f.addLocalVariable(LocalVariableImpl("tmp_x", 0, i32, VariableStorage(prog, -8, 4), prog), SourceType.USER_DEFINED)
        f.addLocalVariable(LocalVariableImpl("abs_x", 0x1f, i32, w.storage("EAX:4"), prog), SourceType.USER_DEFINED)
        prog.getSymbolTable().createLabel(a("0x004120db"), "validate_y", f, SourceType.USER_DEFINED)

        g = prog.getFunctionManager().getFunctionAt(a(UPDATE))
        g.updateFunction("__cdecl", ReturnParameterImpl(w.resolve("/void"), prog),
                         ga.java_list([ParameterImpl("x", i32, w.storage("Stack[0x4]:4"), prog),
                                       ParameterImpl("rest", i32, w.storage("EDX:4"), prog)]),
                         Function.FunctionUpdateType.CUSTOM_STORAGE, True, SourceType.USER_DEFINED)
        eq = prog.getEquateTable().createEquate("SCREEN_W", 0x280)
        eq.addReference(a("0x004120f1"), 1)
        prog.getBookmarkManager().setBookmark(a(FLUSH_RECT), "Note", "todo", "read the callers")
    finally:
        prog.endTransaction(tx, True)
    return ga.key(free), ga.key(cleared)


def _undefined_run(prog, n):
    """An address in DATA with n undefined bytes after it."""
    listing = prog.getListing()
    block = prog.getMemory().getBlock("DATA")
    a = block.getStart().add(0x1000)
    while a.compareTo(block.getEnd()) < 0:
        if all(listing.getDefinedDataContaining(a.add(i)) is None and listing.getInstructionContaining(a.add(i)) is None
               for i in range(n)):
            return a
        a = a.add(n)
    raise RuntimeError("no free run in DATA")


def _a_baseline_datum(prog):
    for d in prog.getListing().getDefinedData(prog.getMemory().getBlock("DATA").getStart(), True):
        return d.getAddress()
    raise RuntimeError("no defined data in DATA")


def main():
    import pyghidra
    exe = str(ng.exe_path())
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        files = tmp / "json"
        files.mkdir()
        for n in ("names_onwin32.json", "labels_onwin32.json"):
            shutil.copy(ng.NAMES_JSON.with_name(n), files / n)
        doc = lambda: json.loads((files / an.FILE).read_text())

        with pyghidra.open_program(exe, project_location=str(tmp / "a"), project_name="neptune", analyze=True) as api:
            prog = api.getCurrentProgram()
            baseline = ga.collect(prog)
            free, cleared = annotate(prog)
            ok(ga.export(prog, files, False, baseline) > 0, "A: export writes the annotations")
        d = doc()
        ok(set(d) == set(an.SECTIONS), "the file has every section: %s" % sorted(d))
        ok(d["data"].get(cleared, "absent") is None, "cleared data is written as null")
        ok(d["data"][free]["type"] == "/student/Rect", "a global typed with the new struct")
        ok(d["types"]["/student/Rect"]["fields"][-1].get("bits") == 3, "the struct's bitfield")
        ok(d["functions"][UPDATE]["signature"].get("storage") == ["Stack[0x4]:4", "EDX:4"], "custom parameter storage")
        ok("EAX:4@0x1f" in d["functions"][FLUSH_RECT]["locals"], "a register local with its first use")
        ok(len(d["comments"]["0x004120c8"]) == 5, "all five comment kinds")
        names = json.loads((files / "names_onwin32.json").read_text())
        ok(names[FLUSH_RECT]["evidence"] == "FlushRect: an edited function comment", "the function comment went to the evidence")
        written = (files / an.FILE).read_text()

        with pyghidra.open_program(exe, project_location=str(tmp / "b"), project_name="neptune", analyze=True) as api:
            prog = api.getCurrentProgram()
            ok(ga.collect(prog) == baseline, "a second fresh import makes the same baseline")
            lines = []
            ga.apply(prog, files, log=lines.append)
            ok(not any("did not take" in x or "could not" in x for x in lines), "B: every annotation applies\n  " + "\n  ".join(lines))
            ok(ga.export(prog, files, True, baseline) == 0, "B: exporting right after applying changes nothing")
            ok((files / an.FILE).read_text() == written, "the file is unchanged")
            tx = prog.startTransaction("delete")
            try:
                prog.getListing().setComment(ga.Writer(prog).addr("0x004120c8"), ga.KINDS["post"], None)
                ga.Writer(prog).remove_local(FLUSH_RECT, "Stack[-0x8]:4")
            finally:
                prog.endTransaction(tx, True)
            ok(ga.export(prog, files, False, baseline) == 2, "B: two deletions exported")
        d = doc()
        ok("post" not in d["comments"]["0x004120c8"] and "Stack[-0x8]:4" not in d["functions"][FLUSH_RECT]["locals"],
           "the deletions are out of the file")

        with pyghidra.open_program(exe, project_location=str(tmp / "a"), project_name="neptune", analyze=False) as api:
            prog = api.getCurrentProgram()
            ga.apply(prog, files, log=lambda _: None)
            facts = ga.collect(prog)
            ok(("comments", "0x004120c8", "post") not in facts, "A: applying the file deletes the comment B deleted")
            ok(("functions", FLUSH_RECT, "locals", "Stack[-0x8]:4") not in facts, "A: and the local")
            ok(ga.export(prog, files, True, baseline) == 0, "A: nothing left to export")
    print("all checks passed")


main()
