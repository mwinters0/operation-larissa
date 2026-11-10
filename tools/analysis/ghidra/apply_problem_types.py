# @category Neptune
"""Create one struct per problem type (Prob00..Prob33) in the Ghidra program and retype the global
pointers the engine uses for them, so the decompiler shows `rec->f3_n` instead of raw offsets.

Input: ../../../docs/data/problem_layouts32.json   (memory layout of each record in ONWIN32.EXE)
Field naming: f<index in file order>_<c|w|n>   c=u8, w=u16, n=CompactNumber (9 bytes in memory).
Run:  ./run.sh apply_problem_types.py     (headless), or from the GUI Script Manager (see docs/port/GHIDRA_GUI.md).
Safe to run repeatedly: the structs are replaced in place and the labels are not duplicated.
"""
import json
import nepghidra as ng

LAYOUT = ng.REPO / "docs/data/problem_layouts32.json"

def apply(prog, spec=None, log=print):
    spec = json.loads(LAYOUT.read_text()) if spec is None else spec
    ng.check_program(prog)
    from ghidra.program.flatapi import FlatProgramAPI
    from ghidra.program.model.data import (StructureDataType, ByteDataType, UnsignedShortDataType,
                                           IntegerDataType, PointerDataType, CategoryPath,
                                           ArrayDataType, DataTypeConflictHandler)
    api = FlatProgramAPI(prog)
    replace = DataTypeConflictHandler.REPLACE_HANDLER
    dtm = prog.getDataTypeManager()
    tx = prog.startTransaction("problem types")
    try:
        cn = StructureDataType(CategoryPath("/neptune"), "CompactNumber", 0)
        cn.setPackingEnabled(False)
        cn.add(IntegerDataType.dataType, 4, "kind", None)
        cn.add(ByteDataType.dataType, 1, "a", None)
        cn.add(ArrayDataType(ByteDataType.dataType, 4, 1), 4, "raw", None)
        cn = dtm.addDataType(cn, replace)
        listing = prog.getListing()
        for t, s in sorted(spec["types"].items(), key=lambda kv: int(kv[0])):
            st = StructureDataType(CategoryPath("/neptune"), "Prob%02d" % int(t), s["mem_size"])
            st.setPackingEnabled(False)
            for i, f in enumerate(s["fields"]):
                dt = {"c": ByteDataType.dataType, "w": UnsignedShortDataType.dataType, "n": cn}[f["kind"]]
                st.replaceAtOffset(f["mem_off"], dt, dt.getLength(), "f%d_%s" % (i, f["kind"]), None)
            st = dtm.addDataType(st, replace)
            a = ng.addr(api, s["global"])
            listing.clearCodeUnits(a, a.add(3), False)
            listing.createData(a, PointerDataType(st))
            ng.set_label(prog, a, "g_prob%02d" % int(t), primary=False)
    finally:
        prog.endTransaction(tx, True)
    log("created %d problem structs and retyped their globals" % len(spec["types"]))


ng.run(globals(), apply)
