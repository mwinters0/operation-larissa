"""The Ghidra side of the annotation file (annotations.py has the format and the merge): read every annotation out of a
program as flat facts, write them into one, and the two records the export compares against:

  * the baseline: the facts a fresh import + auto-analysis of the same EXE makes by itself (the importer's PE header
    comments, its strings and types ...), cached as baseline_onwin32.json next to the project (never committed: it is
    made from the game). What differs from it, or what Ghidra marks USER_DEFINED, is your work.
  * the applied snapshot: the facts the project held right after apply_annotations.py, kept inside the program
    (Options > Neptune), so the export can tell a comment you deleted from one the file gained since.

Plate comments at a named function's entry, and at a global label that has evidence, are that entry's `evidence` in
names_onwin32.json / labels_onwin32.json (apply_names.py writes them); here they are ("evidence", "function"|"label", address).
Imported only after nepghidra (which starts the JVM).

Teaches: Ghidra's program model from Python: listing comments, defined data, the data type manager, function variables and
their storage, symbols in a function's namespace, equates, bookmarks, and program options as a place to keep a tool's state.
"""
import difflib
import hashlib
import json
import tempfile
from pathlib import Path

import annotations as an
import nepghidra as ng

BASELINE = "baseline_onwin32.json"
BASELINE_FORMAT = 1                 # raise when collect() writes a fact differently: older baselines are then made again
OPTIONS = "Neptune"
APPLIED = "annotations applied"
KINDS = {"eol": 0, "pre": 1, "post": 2, "plate": 3, "repeatable": 4}       # CodeUnit.*_COMMENT
MANAGED_TYPES = "/neptune/"        # apply_problem_types.py: CompactNumber, Prob00..Prob33


def key(address):
    return "0x%08x" % address.getOffset()


def managed(spec=None):
    """(type paths, data addresses) that apply_problem_types.py owns."""
    layout = ng.REPO / "docs/data/problem_layouts32.json"
    spec = spec if spec is not None else (json.loads(layout.read_text()) if layout.exists() else {"types": {}})
    paths = {MANAGED_TYPES + "CompactNumber"} | {MANAGED_TYPES + "Prob%02d" % int(t) for t in spec["types"]}
    addrs = {"0x%08x" % int(s["global"], 16) for s in spec["types"].values()}
    return paths, addrs


# ---- reading

def type_str(dt):
    from ghidra.program.model.data import Array, Pointer
    if isinstance(dt, Pointer) and dt.getDataType() is not None:
        return type_str(dt.getDataType()) + " *"
    if isinstance(dt, Array):
        return "%s[%d]" % (type_str(dt.getDataType()), dt.getNumElements())
    return dt.getPathName()


def describe_type(dt):
    """A struct, union, enum, typedef or function definition -> its JSON definition (None for anything else)."""
    from ghidra.program.model.data import Enum, FunctionDefinition, Structure, TypeDef, Union
    out = None
    if isinstance(dt, (Structure, Union)):
        fields = []
        for c in dt.getDefinedComponents():
            f = {"offset": c.getOffset()} if isinstance(dt, Structure) else {}
            if c.isBitFieldComponent():
                bf = c.getDataType()
                f.update(type=type_str(bf.getBaseDataType()), bits=bf.getDeclaredBitSize(), bit_offset=bf.getBitOffset(),
                         length=c.getLength())
            else:
                f["type"] = type_str(c.getDataType())
                if c.getLength() != c.getDataType().getLength():
                    f["length"] = c.getLength()
            f["name"] = c.getFieldName()
            if c.getComment():
                f["comment"] = c.getComment()
            fields.append(f)
        out = {"kind": "struct" if isinstance(dt, Structure) else "union", "packed": dt.isPackingEnabled()}
        if isinstance(dt, Structure) and not dt.isPackingEnabled():
            out["size"] = dt.getLength()
        out["fields"] = fields
    elif isinstance(dt, Enum):
        values = sorted(((n, dt.getValue(n)) for n in dt.getNames()), key=lambda nv: (nv[1], nv[0]))
        out = {"kind": "enum", "size": dt.getLength(), "values": {n: int(v) for n, v in values}}
        notes = {n: dt.getComment(n) for n, _ in values if dt.getComment(n)}
        if notes:
            out["value_comments"] = notes
    elif isinstance(dt, TypeDef):
        out = {"kind": "typedef", "type": type_str(dt.getDataType())}
    elif isinstance(dt, FunctionDefinition):
        out = {"kind": "function", "cc": dt.getCallingConventionName(), "return": type_str(dt.getReturnType()),
               "params": [an.param_text(type_str(p.getDataType()), p.getName()) for p in dt.getArguments()],
               "varargs": dt.hasVarArgs()}
    if out is not None and isinstance(dt, (Structure, Union, Enum)) and dt.getDescription():
        out["comment"] = dt.getDescription()     # a typedef's or function definition's description is Ghidra's, not yours
    return out


def describe_signature(f):
    sig = {"cc": f.getCallingConventionName(), "return": type_str(f.getReturnType()),
           "params": [an.param_text(type_str(p.getDataType()), p.getName()) for p in f.getParameters()]}
    if f.hasVarArgs():
        sig["varargs"] = True
    if f.hasNoReturn():
        sig["noreturn"] = True
    if f.hasCustomVariableStorage():
        sig["custom_storage"] = True
        sig["return_storage"] = str(f.getReturn().getVariableStorage())
        sig["storage"] = [str(p.getVariableStorage()) for p in f.getParameters()]
    return sig


def collect(prog):
    """Every fact the program holds that a user could have made, as {key tuple: value}: all comments, all defined data,
    all composite / enum / typedef / function types, every function's signature; and only the USER_DEFINED locals,
    local labels and Note bookmarks (those Ghidra never makes itself). user_facts() subtracts the baseline."""
    from ghidra.program.model.symbol import SourceType, SymbolType
    flat = {}
    listing, mem = prog.getListing(), prog.getMemory()
    for kind, code in KINDS.items():
        for a in listing.getCommentAddressIterator(code, mem, True):
            flat[("comments", key(a), kind)] = listing.getComment(code, a)
    for d in listing.getDefinedData(True):
        value = {"type": type_str(d.getDataType())}
        if d.getLength() != d.getDataType().getLength():
            value["length"] = d.getLength()
        flat[("data", key(d.getAddress()))] = value
    for dt in prog.getDataTypeManager().getAllDataTypes():
        definition = describe_type(dt)
        if definition is not None:
            flat[("types", dt.getPathName())] = definition
    st = prog.getSymbolTable()
    for f in prog.getFunctionManager().getFunctions(True):
        entry = key(f.getEntryPoint())
        user_sig = f.getSignatureSource() == SourceType.USER_DEFINED or any(
            p.getSource() == SourceType.USER_DEFINED for p in f.getParameters())
        flat[("functions", entry, "signature")] = dict(describe_signature(f), _user=user_sig)
        for v in f.getLocalVariables():
            if v.getSource() != SourceType.USER_DEFINED:
                continue
            var = {"name": v.getName(), "type": type_str(v.getDataType())}
            if v.getComment():
                var["comment"] = v.getComment()
            flat[("functions", entry, "locals", an.storage_key(str(v.getVariableStorage()), v.getFirstUseOffset()))] = var
        for s in st.getSymbols(f):
            if s.getSymbolType() == SymbolType.LABEL and s.getSource() == SourceType.USER_DEFINED:
                flat[("functions", entry, "labels", key(s.getAddress()))] = s.getName()
    for eq in prog.getEquateTable().getEquates():
        refs = sorted("%s:%d" % (key(r.getAddress()), r.getOpIndex()) for r in eq.getReferences())
        flat[("equates", eq.getName())] = {"value": int(eq.getValue()), "refs": refs}
    for b in prog.getBookmarkManager().getBookmarksIterator("Note"):
        flat[("bookmarks", key(b.getAddress()), b.getCategory())] = b.getComment()
    return flat


def user_facts(prog, baseline, names, labels, layout=None):
    """The program's facts that are your work: collect() minus the baseline, minus what apply_problem_types.py owns, with
    the evidence plates moved to ("evidence", ...). Data the baseline had and the program lacks is None (you cleared it)."""
    managed_types, managed_data = managed(layout)
    evidence_labels = {a for a, v in labels.items() if isinstance(v, dict) and "evidence" in v}
    out = {}
    facts = collect(prog)
    for k, v in facts.items():
        section = k[0]
        if section == "comments" and k[2] == "plate" and k[1] in names:
            out[("evidence", "function", k[1])] = v
            continue
        if section == "comments" and k[2] == "plate" and k[1] in evidence_labels:
            out[("evidence", "label", k[1])] = v
            continue
        if section == "types" and k[1] in managed_types or section == "data" and k[1] in managed_data:
            continue
        if section == "functions" and k[2] == "signature":
            v = dict(v)
            if not v.pop("_user") or _plain_sig(baseline.get(k)) == v:
                continue
        elif baseline.get(k) == v:
            continue
        out[k] = v
    for k in baseline:
        if k[0] == "data" and k not in facts and k[1] not in managed_data:
            out[k] = None
    return out


def _plain_sig(sig):
    if sig is None:
        return None
    sig = dict(sig)
    sig.pop("_user", None)
    return sig


def evidence_facts(names, labels):
    """The evidence in names_onwin32.json / labels_onwin32.json as facts, to merge with the plates of the program."""
    out = {("evidence", "function", a): v["evidence"] for a, v in names.items() if v.get("evidence")}
    out.update({("evidence", "label", a): v["evidence"] for a, v in labels.items() if isinstance(v, dict) and v.get("evidence")})
    return out


# ---- the baseline and the applied snapshot

def ghidra_version():
    from ghidra.framework import Application
    return str(Application.getApplicationVersion())


def project_dir(prog):
    """The directory holding the program's project (where neptune.gpr is)."""
    return Path(str(prog.getDomainFile().getProjectLocator().getLocation()))


def load_baseline(path, sha256):
    """The cached baseline facts, or None when there is none for this EXE and this Ghidra."""
    if not path.exists():
        return None
    doc = json.loads(path.read_text())
    if doc.get("sha256") != sha256 or doc.get("ghidra") != ghidra_version() or doc.get("format") != BASELINE_FORMAT:
        return None
    return {an.from_json_key(k): v for k, v in doc["facts"].items()}


def make_baseline(path, log=print):
    """Import + analyse a fresh copy of the EXE in a throw-away project (as nepghidra.open_program does for the real one)
    and cache its facts. Headless only. About half a minute."""
    import pyghidra
    exe = ng.exe_path()
    log("making the baseline (a fresh import + analysis of %s, about 30 s) ..." % exe.name)
    with tempfile.TemporaryDirectory() as tmp, \
            pyghidra.open_program(str(exe), project_location=tmp, project_name="baseline", analyze=True) as api:
        facts = collect(api.getCurrentProgram())
    doc = {"format": BASELINE_FORMAT, "ghidra": ghidra_version(), "sha256": hashlib.sha256(exe.read_bytes()).hexdigest(),
           "facts": {an.json_key(k): v for k, v in sorted(facts.items(), key=lambda kv: an.json_key(kv[0]))}}
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(doc) + "\n")
    log("wrote %s (%d facts)" % (path, len(facts)))
    return facts


def applied(prog):
    """The snapshot apply_annotations.py left in the program, or {} (never applied: the export then deletes nothing)."""
    text = prog.getOptions(OPTIONS).getString(APPLIED, None)
    return {an.from_json_key(k): v for k, v in json.loads(text).items()} if text else {}


def set_applied(prog, facts):
    text = json.dumps({an.json_key(k): v for k, v in sorted(facts.items(), key=lambda kv: an.json_key(kv[0]))})
    tx = prog.startTransaction("record applied annotations")
    try:
        prog.getOptions(OPTIONS).setString(APPLIED, text)
    finally:
        prog.endTransaction(tx, True)


# ---- writing

class Writer:
    """Writes facts into a program (inside the caller's transaction). Each method is safe to repeat."""

    def __init__(self, prog, log=print):
        from ghidra.program.flatapi import FlatProgramAPI
        from ghidra.program.model.data import BuiltInDataTypeManager
        self.prog, self.log = prog, log
        self.api = FlatProgramAPI(prog)
        self.dtm = prog.getDataTypeManager()
        self.builtin = BuiltInDataTypeManager.getDataTypeManager()
        self.types = {}            # path -> definition of the types being applied (resolved on first use)
        self.done = set()

    def addr(self, text):
        return self.api.toAddr(int(text, 16))

    # types

    def resolve(self, text):
        from ghidra.program.model.data import ArrayDataType, PointerDataType
        base, mods = an.parse_type(text)
        dt = self._base(base)
        for m in mods:
            dt = PointerDataType(dt, self.dtm) if m == "*" else ArrayDataType(dt, m, dt.getLength(), self.dtm)
        return dt

    def _base(self, path):
        from ghidra.program.model.data import DataType
        if path in self.types and path not in self.done:
            self.define(path, self.types[path])
        if path == DataType.DEFAULT.getPathName():
            return DataType.DEFAULT                  # "undefined": in no data type manager
        dt = self.dtm.getDataType(path) or self.builtin.getDataType(path)
        if dt is None:
            raise ValueError("no data type %s" % path)
        return dt

    def apply_types(self, types, attempt):
        """Composite placeholders first (so types can point at each other), then every definition, each on its own
        (attempt(what, fn, *args) reports a failure and goes on)."""
        from ghidra.program.model.data import CategoryPath, DataTypeConflictHandler, StructureDataType, UnionDataType
        self.types = dict(types)
        for path, d in types.items():
            if d["kind"] in ("struct", "union") and self.dtm.getDataType(path) is None:
                cat, name = _split(path)
                if d["kind"] == "struct":
                    empty = StructureDataType(CategoryPath(cat), name, 0, self.dtm)
                else:
                    empty = UnionDataType(CategoryPath(cat), name, self.dtm)
                self.dtm.addDataType(empty, DataTypeConflictHandler.DEFAULT_HANDLER)
        for path, d in types.items():
            if path not in self.done:
                attempt("types " + path, self.define, path, d)

    def define(self, path, d):
        from ghidra.program.model.data import (CategoryPath, DataTypeConflictHandler, EnumDataType, FunctionDefinitionDataType,
                                               ParameterDefinitionImpl, Structure, StructureDataType, TypedefDataType, Union,
                                               UnionDataType)
        self.done.add(path)
        cat, name = _split(path)
        cp = CategoryPath(cat)
        kind = d["kind"]
        if kind == "struct":
            new = StructureDataType(cp, name, 0 if d["packed"] else d["size"], self.dtm)
            new.setPackingEnabled(d["packed"])
            for f in d["fields"]:
                ft = self.resolve(f["type"])
                if "bits" in f:
                    if d["packed"]:
                        new.addBitField(ft, f["bits"], f["name"], f.get("comment"))
                    else:
                        new.insertBitFieldAt(f["offset"], f["length"], f["bit_offset"], ft, f["bits"], f["name"], f.get("comment"))
                elif d["packed"]:
                    new.add(ft, f.get("length", ft.getLength()), f["name"], f.get("comment"))
                else:
                    new.replaceAtOffset(f["offset"], ft, f.get("length", ft.getLength()), f["name"], f.get("comment"))
        elif kind == "union":
            new = UnionDataType(cp, name, self.dtm)
            new.setPackingEnabled(d["packed"])
            for f in d["fields"]:
                ft = self.resolve(f["type"])
                if "bits" in f:
                    new.addBitField(ft, f["bits"], f["name"], f.get("comment"))
                else:
                    new.add(ft, f.get("length", ft.getLength()), f["name"], f.get("comment"))
        elif kind == "enum":
            new = EnumDataType(cp, name, d["size"], self.dtm)
            notes = d.get("value_comments", {})
            for n, v in d["values"].items():
                new.add(n, v, notes.get(n))
        elif kind == "typedef":
            new = TypedefDataType(cp, name, self.resolve(d["type"]), self.dtm)
        elif kind == "function":
            new = FunctionDefinitionDataType(cp, name, self.dtm)
            new.setReturnType(self.resolve(d["return"]))
            new.setArguments([ParameterDefinitionImpl(n, self.resolve(t), None) for t, n in map(an.parse_param, d["params"])])
            new.setVarArgs(d.get("varargs", False))
            new.setCallingConvention(d.get("cc"))
        else:
            raise ValueError("%s: unknown kind %r" % (path, kind))
        if d.get("comment") and kind in ("struct", "union", "enum"):
            new.setDescription(d["comment"])
        old = self.dtm.getDataType(path)
        if old is None:
            self.dtm.addDataType(new, DataTypeConflictHandler.DEFAULT_HANDLER)
        elif kind == "struct" and isinstance(old, Structure) or kind == "union" and isinstance(old, Union):
            old.replaceWith(new)                     # keeps the type's identity: what uses it stays pointed at it
            old.setDescription(d.get("comment"))
        elif describe_type(old) != d:
            self.dtm.replaceDataType(old, new, True)

    def remove_type(self, path):
        from ghidra.util.task import TaskMonitor
        dt = self.dtm.getDataType(path)
        if dt is not None:
            self.dtm.remove(dt, TaskMonitor.DUMMY)

    # data, comments, functions ...

    def data(self, address, value):
        listing = self.prog.getListing()
        a = self.addr(address)
        old = listing.getDefinedDataAt(a)
        if value is None:
            if old is not None:
                listing.clearCodeUnits(a, a, False)
            return
        dt = self.resolve(value["type"])
        length = value.get("length", dt.getLength())
        if old is not None and type_str(old.getDataType()) == value["type"] and old.getLength() == length:
            return
        listing.clearCodeUnits(a, a.add(max(length, 1) - 1), False)
        listing.createData(a, dt, length)

    def comment(self, address, kind, text):
        listing = self.prog.getListing()
        a = self.addr(address)
        if listing.getComment(KINDS[kind], a) != text:
            listing.setComment(a, KINDS[kind], text)

    def function(self, entry):
        f = self.prog.getFunctionManager().getFunctionAt(self.addr(entry))
        if f is None:
            raise ValueError("no function at %s (is it in names_onwin32.json? apply_names.py creates it)" % entry)
        return f

    def signature(self, entry, sig):
        from ghidra.program.model.listing import Function, ParameterImpl, ReturnParameterImpl
        from ghidra.program.model.symbol import SourceType
        f = self.function(entry)
        if _plain_sig(describe_signature(f)) == _plain_sig(sig) and f.getSignatureSource() == SourceType.USER_DEFINED:
            return
        custom = sig.get("custom_storage", False)
        if custom:
            ret = ReturnParameterImpl(self.resolve(sig["return"]), self.storage(sig["return_storage"]), self.prog)
            params = [ParameterImpl(n, self.resolve(t), self.storage(s), self.prog)
                      for (t, n), s in zip(map(an.parse_param, sig["params"]), sig["storage"])]
            how = Function.FunctionUpdateType.CUSTOM_STORAGE
        else:
            ret = ReturnParameterImpl(self.resolve(sig["return"]), self.prog)
            params = [ParameterImpl(n, self.resolve(t), self.prog) for t, n in map(an.parse_param, sig["params"])]
            how = Function.FunctionUpdateType.DYNAMIC_STORAGE_ALL_PARAMS
        f.updateFunction(sig["cc"], ret, java_list(params), how, True, SourceType.USER_DEFINED)
        f.setVarArgs(sig.get("varargs", False))
        f.setNoReturn(sig.get("noreturn", False))
        f.setSignatureSource(SourceType.USER_DEFINED)

    def storage(self, text):
        from ghidra.program.model.listing import VariableStorage
        from ghidra.program.model.pcode import Varnode
        if text in (str(VariableStorage.VOID_STORAGE), str(VariableStorage.UNASSIGNED_STORAGE)):
            return VariableStorage.VOID_STORAGE if text == str(VariableStorage.VOID_STORAGE) else VariableStorage.UNASSIGNED_STORAGE
        pieces, _ = an.parse_storage(text.partition("@")[0])
        if len(pieces) == 1 and pieces[0][0] == "stack":
            return VariableStorage(self.prog, pieces[0][1], pieces[0][2])
        nodes = []
        for kind, where, size in pieces:
            if kind == "stack":
                nodes.append(Varnode(self.prog.getAddressFactory().getStackSpace().getAddress(where), size))
            else:
                reg = self.prog.getRegister(where)
                if reg is None:
                    raise ValueError("no register %s" % where)
                nodes.append(Varnode(reg.getAddress(), size))
        return VariableStorage(self.prog, nodes)

    def local(self, entry, storage_text, var):
        from ghidra.program.model.listing import LocalVariableImpl
        from ghidra.program.model.symbol import SourceType
        f = self.function(entry)
        storage = self.storage(storage_text)
        _, first_use = an.parse_storage(storage_text)
        dt = self.resolve(var["type"])
        same = [v for v in f.getLocalVariables() if v.getVariableStorage() == storage and v.getFirstUseOffset() == first_use]
        if same:
            v = same[0]
            if v.getName() != var["name"] or v.getSource() != SourceType.USER_DEFINED:
                v.setName(var["name"], SourceType.USER_DEFINED)
            if type_str(v.getDataType()) != var["type"]:
                v.setDataType(dt, SourceType.USER_DEFINED)
        else:
            for v in f.getLocalVariables():
                if v.getVariableStorage().intersects(storage) and v.getFirstUseOffset() == first_use:
                    f.removeVariable(v)
            v = f.addLocalVariable(LocalVariableImpl(var["name"], first_use, dt, storage, self.prog), SourceType.USER_DEFINED)
        if v.getComment() != var.get("comment"):
            v.setComment(var.get("comment"))

    def remove_local(self, entry, storage_text):
        f = self.function(entry)
        storage = self.storage(storage_text)
        _, first_use = an.parse_storage(storage_text)
        for v in f.getLocalVariables():
            if v.getVariableStorage() == storage and v.getFirstUseOffset() == first_use:
                f.removeVariable(v)

    def label(self, entry, address, name, remove=False):
        from ghidra.program.model.symbol import SourceType, SymbolType
        f = self.function(entry)
        st = self.prog.getSymbolTable()
        a = self.addr(address)
        same = [s for s in st.getSymbols(a) if s.getSymbolType() == SymbolType.LABEL and s.getParentNamespace() == f
                and s.getName() == name]
        if remove:
            for s in same:
                s.delete()
        elif not same:
            st.createLabel(a, name, f, SourceType.USER_DEFINED)

    def equate(self, name, eq, remove=False):
        table = self.prog.getEquateTable()
        e = table.getEquate(name)
        if remove:
            if e is not None:
                table.removeEquate(name)
            return
        if e is None:
            e = table.createEquate(name, eq["value"])
        have = {"%s:%d" % (key(r.getAddress()), r.getOpIndex()) for r in e.getReferences()}
        for ref in eq["refs"]:
            if ref not in have:
                address, _, op = ref.rpartition(":")
                e.addReference(self.addr(address), int(op))

    def bookmark(self, address, category, text, remove=False):
        bm = self.prog.getBookmarkManager()
        a = self.addr(address)
        old = bm.getBookmark(a, "Note", category)
        if remove:
            if old is not None:
                bm.removeBookmark(old)
        elif old is None or old.getComment() != text:
            bm.setBookmark(a, "Note", category, text)


def java_list(items):
    """A Python list as a java.util.List (JPype does not convert one for an overloaded method)."""
    from java.util import ArrayList
    out = ArrayList()
    for item in items:
        out.add(item)
    return out


def _split(path):
    cat, _, name = path.rpartition("/")
    return cat or "/", name


def apply_facts(prog, facts, removed, log=print):
    """Write `facts` into the program and undo `removed` (facts the last apply wrote that the file no longer has).
    Order: types, data, signatures, locals, labels, comments, equates, bookmarks. Returns the number of problems."""
    w = Writer(prog, log)
    problems = 0

    def attempt(what, fn, *args):
        nonlocal problems
        try:
            fn(*args)
        except Exception as e:  # noqa: BLE001  (one bad entry must not stop the rest)
            problems += 1
            log("could not apply %s: %s" % (what, e))

    by = {}
    for k, v in facts.items():
        by.setdefault(k[0] if k[0] != "functions" else k[2], []).append((k, v))
    tx = prog.startTransaction("apply annotations")
    try:
        w.apply_types({k[1]: v for k, v in by.get("types", [])}, attempt)
        for k, v in by.get("data", []):
            attempt(an.key_text(k), w.data, k[1], v)
        for k, v in by.get("signature", []):
            attempt(an.key_text(k), w.signature, k[1], v)
        for k, v in by.get("locals", []):
            attempt(an.key_text(k), w.local, k[1], k[3], v)
        for k, v in by.get("labels", []):
            attempt(an.key_text(k), w.label, k[1], k[3], v)
        for k, v in by.get("comments", []):
            attempt(an.key_text(k), w.comment, k[1], k[2], v)
        for k, v in by.get("equates", []):
            attempt(an.key_text(k), w.equate, k[1], v)
        for k, v in by.get("bookmarks", []):
            attempt(an.key_text(k), w.bookmark, k[1], k[2], v)
        for k, v in removed.items():
            what = "removing " + an.key_text(k)
            section = k[0]
            if section == "comments":
                attempt(what, w.comment, k[1], k[2], None)
            elif section == "data":
                attempt(what, w.data, k[1], None)
            elif section == "types":
                attempt(what, w.remove_type, k[1])
            elif section == "equates":
                attempt(what, w.equate, k[1], v, True)
            elif section == "bookmarks":
                attempt(what, w.bookmark, k[1], k[2], None, True)
            elif section == "functions" and k[2] == "locals":
                attempt(what, w.remove_local, k[1], k[3])
            elif section == "functions" and k[2] == "labels":
                attempt(what, w.label, k[1], k[3], v, True)
            elif section == "functions":
                log("note: %s left as it is (a signature is not reverted to Ghidra's own)" % what)
    finally:
        prog.endTransaction(tx, True)
    return problems


# ---- the two directions (export_annotations.py and apply_annotations.py are their command lines)

def show(value):
    if value is an.MISSING:
        return "(none)"
    text = json.dumps(value, ensure_ascii=False)
    return text if len(text) <= 100 else text[:97] + "..."


def export(prog, directory, dry_run, baseline, log=print):
    """Merge the program's annotations into the JSON files in `directory`; write them unless dry_run. Returns #changes."""
    ng.check_program(prog)
    paths = {n: directory / n for n in (an.FILE, "names_onwin32.json", "labels_onwin32.json")}
    raw = {n: (p.read_text() if p.exists() else "{}\n") for n, p in paths.items()}
    names, labels = json.loads(raw["names_onwin32.json"]), json.loads(raw["labels_onwin32.json"])
    mine = user_facts(prog, baseline, names, labels)
    base = applied(prog)
    theirs = an.flatten(json.loads(raw[an.FILE]))
    theirs.update(evidence_facts(names, labels))
    result, changes, conflicts, new_base = an.merge3(base, mine, theirs)
    for k, old, new in changes:
        mark = "+" if old is an.MISSING else "-" if new is an.MISSING else "~"
        log("%s %s: %s" % (mark, an.key_text(k), show(new if new is not an.MISSING else old)))
    for k, _, m, t in conflicts:
        log("conflict %s: the file changed it too (to %s); yours is written: %s" % (an.key_text(k), show(t), show(m)))
    if not base:
        log("note: this project has no record of an apply (apply_annotations.py), so nothing is deleted from the file")

    fn_names = {entry: v.get("name") for entry, v in names.items()}   # an ONWIN.MAP reference writes no name (map_names.py)
    for f in prog.getFunctionManager().getFunctions(True):
        fn_names.setdefault(key(f.getEntryPoint()), f.getName())
    doc = an.unflatten({k: v for k, v in result.items() if k[0] != "evidence"}, fn_names)
    for k, _, new in changes:
        if k[0] == "evidence":
            table = names if k[1] == "function" else labels
            table[k[2]]["evidence"] = "" if new is an.MISSING else new
    texts = {an.FILE: an.dump(doc), "names_onwin32.json": json.dumps(names, indent=1) + "\n",
             "labels_onwin32.json": json.dumps(labels, indent=1) + "\n"}
    for n, text in texts.items():
        if text == raw[n]:
            continue
        if dry_run:
            for line in difflib.unified_diff(raw[n].splitlines(), text.splitlines(), "a/" + n, "b/" + n, n=0, lineterm=""):
                log(line)
        else:
            paths[n].write_text(text)
            log("wrote %s" % paths[n])
    if not dry_run and new_base != base:
        set_applied(prog, new_base)
    if not changes:
        log("nothing to export: %s already holds every annotation of the project" % an.FILE)
    return len(changes)


def evidence_plates(prog, names, labels):
    """The plate comments at the addresses whose evidence apply_names.py writes, as ("evidence", ...) facts."""
    listing = prog.getListing()
    out = {}
    for kind, table in (("function", names), ("label", {a: v for a, v in labels.items() if isinstance(v, dict) and "evidence" in v})):
        for a in table:
            text = listing.getComment(KINDS["plate"], prog.getAddressFactory().getAddress(a))
            if text:
                out[("evidence", kind, a)] = text
    return out


def apply(prog, directory=None, log=print):
    ng.check_program(prog)
    directory = directory or ng.NAMES_JSON.parent
    path = directory / an.FILE
    theirs = an.flatten(json.loads(path.read_text())) if path.exists() else {}
    base = applied(prog)
    removed = {k: v for k, v in base.items() if k[0] != "evidence" and k not in theirs}
    problems = apply_facts(prog, theirs, removed, log)
    facts = collect(prog)
    held = {}
    for k, v in theirs.items():
        got = facts.get(k)
        if k[0] == "functions" and k[2] == "signature" and got is not None:
            got = _plain_sig(got)
        if (v is None and got is None) or got == v:
            held[k] = v
        else:
            problems += 1
            log("did not take: %s\n  file:    %s\n  program: %s" % (an.key_text(k), json.dumps(v), json.dumps(got)))
    held.update(evidence_plates(prog, *(json.loads((directory / n).read_text()) for n in ("names_onwin32.json", "labels_onwin32.json"))))
    set_applied(prog, held)
    log("applied %d annotations from %s%s" % (len(theirs), path, ", removed %d" % len(removed) if removed else ""))
    if problems:
        log("%d problems (above)" % problems)
