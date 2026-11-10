"""The annotation file (annotations_onwin32.json): everything you add to ONWIN32.EXE in Ghidra besides function names and
global labels, as plain text keyed by address. Pure Python (no Ghidra), so its rules are tested by test_annotations.py;
the Ghidra side is program_annotations.py, the scripts are export_annotations.py and apply_annotations.py.

The file holds, per section:
  comments   address -> {plate, pre, eol, post, repeatable}: text
  functions  entry -> {name (for the reader, none for an ONWIN.MAP name; names_onwin32.json owns it), signature, locals, labels}
  data       address -> {type, length?} (a type given to a global; null = Ghidra's data there was cleared)
  types      type path -> definition (struct, union, enum, typedef, function)
  equates    name -> {value, refs: ["address:operand"]}
  bookmarks  address -> {category: text}   (Note bookmarks only)

A parameter is one string, its type then its name: "/int x". A type is written as its path plus modifiers read left to right, innermost first: "/neptune/Prob00 *" is a pointer to Prob00,
"/int[3][2]" an array of 2 arrays of 3 ints, "/char *[4]" an array of 4 pointers.

Every entry is one fact under one key (`flatten`), so the file can be merged three ways like a text file: what the project
held when the file was last applied (base), what it holds now (mine) and the file on disk (theirs, maybe pulled from git).

Teaches: a three-way merge of keyed facts, the rule that lets a tool tell your deletions from someone else's additions.
"""
import json
import re

FILE = "annotations_onwin32.json"
SECTIONS = ("comments", "functions", "data", "types", "equates", "bookmarks")
COMMENT_KINDS = ("plate", "pre", "eol", "post", "repeatable")
FUNCTION_PARTS = ("signature", "locals", "labels")
MISSING = object()


def flatten(doc):
    """File -> {key tuple: value}: one entry per fact. Function names are not facts here (names_onwin32.json owns them)."""
    flat = {}
    for addr, kinds in doc.get("comments", {}).items():
        for kind, text in kinds.items():
            flat[("comments", addr, kind)] = text
    for entry, parts in doc.get("functions", {}).items():
        if "signature" in parts:
            flat[("functions", entry, "signature")] = parts["signature"]
        for storage, var in parts.get("locals", {}).items():
            flat[("functions", entry, "locals", storage)] = var
        for addr, name in parts.get("labels", {}).items():
            flat[("functions", entry, "labels", addr)] = name
    for addr, data in doc.get("data", {}).items():
        flat[("data", addr)] = data
    for path, definition in doc.get("types", {}).items():
        flat[("types", path)] = definition
    for name, equate in doc.get("equates", {}).items():
        flat[("equates", name)] = equate
    for addr, marks in doc.get("bookmarks", {}).items():
        for category, text in marks.items():
            flat[("bookmarks", addr, category)] = text
    return flat


def unflatten(flat, function_names=None):
    """{key tuple: value} -> file, every level sorted, so the same facts always give the same text.

    function_names: entry -> name, written into each function for the reader (not read back)."""
    doc = {s: {} for s in SECTIONS}
    for key in sorted(flat, key=_sort_key):
        value = flat[key]
        section = key[0]
        if section == "comments":
            doc["comments"].setdefault(key[1], {})[key[2]] = value
        elif section == "functions":
            parts = doc["functions"].setdefault(key[1], {})
            if key[2] == "signature":
                parts["signature"] = value
            else:
                parts.setdefault(key[2], {})[key[3]] = value
        elif section == "bookmarks":
            doc["bookmarks"].setdefault(key[1], {})[key[2]] = value
        elif section in doc:
            doc[section][key[1]] = value
    for entry, parts in doc["functions"].items():
        name = (function_names or {}).get(entry)
        ordered = {"name": name} if name else {}
        ordered.update((p, parts[p]) for p in FUNCTION_PARTS if p in parts)
        doc["functions"][entry] = ordered
    return {s: doc[s] for s in SECTIONS if doc[s]}


def _sort_key(key):
    """Comments in the order Ghidra shows them around an address; locals by stack offset; everything else by text."""
    out = []
    for part in key:
        if part in COMMENT_KINDS:
            out.append((0, COMMENT_KINDS.index(part), ""))
        elif isinstance(part, str) and part.startswith("Stack["):
            out.append((1, int(part[6:part.index("]")], 16), part))
        else:
            out.append((2, 0, str(part)))
    return out


def dump(doc):
    return json.dumps(doc, indent=1, ensure_ascii=False) + "\n"


def merge3(base, mine, theirs):
    """Three-way merge of flat maps. Every key whose value in `mine` differs from `base` (you changed it in the project) is
    taken into the result; every other key keeps `theirs` (the file). A key missing from `mine` that `base` had is a deletion.

    Returns (result, changes, conflicts, new_base):
      changes    [(key, file value or MISSING, new value or MISSING)]: what the result changes in the file
      conflicts  [(key, base, mine, theirs)]: you and the file both changed a key; yours wins, the file's value is reported
                 (none without a base: then nothing tells a change of the file from one not applied yet)
      new_base   base plus your changes: what the project and the file now agree on (theirs-only changes stay to be applied)."""
    result, new_base = dict(theirs), dict(base)
    changes, conflicts = [], []
    for key in sorted(set(base) | set(mine), key=_sort_key):
        b, m = base.get(key, MISSING), mine.get(key, MISSING)
        if m == b:
            continue
        _put(new_base, key, m)
        t = theirs.get(key, MISSING)
        if t == m:
            continue
        if base and t != b:
            conflicts.append((key, b, m, t))
        _put(result, key, m)
        changes.append((key, t, m))
    return result, changes, conflicts, new_base


def _put(d, key, value):
    if value is MISSING:
        d.pop(key, None)
    else:
        d[key] = value


def key_text(key):
    return " ".join(str(k) for k in key)


def json_key(key):
    """A flat key as one string (for the baseline and the applied snapshot, which are JSON objects)."""
    return "\t".join(key)


def from_json_key(text):
    return tuple(text.split("\t"))


# ---- type strings

_MODIFIER = re.compile(r"(?:\s*\*|\[(\d+)\])$")


def parse_type(text):
    """"/neptune/Prob00 *[4]" -> ("/neptune/Prob00", ["*", 4]): base path and modifiers, innermost first."""
    mods = []
    rest = text.strip()
    while True:
        m = _MODIFIER.search(rest)
        if not m or m.start() == 0:
            break
        mods.append(int(m.group(1)) if m.group(1) else "*")
        rest = rest[:m.start()].rstrip()
    if not rest.startswith("/"):
        raise ValueError("a type is a path starting with '/': %r" % text)
    return rest, mods[::-1]


def format_type(base, mods):
    out = base
    for m in mods:
        out += " *" if m == "*" else "[%d]" % m
    return out


def param_text(type_text, name):
    """A parameter as one string: "/neptune/Prob00 * rec" (names never hold a space; the type may)."""
    return "%s %s" % (type_text, name)


def parse_param(text):
    """"/neptune/Prob00 * rec" -> ("/neptune/Prob00 *", "rec")."""
    type_text, _, name = text.rpartition(" ")
    if not type_text or not name:
        raise ValueError("a parameter is 'type name': %r" % text)
    return type_text, name


# ---- variable storage, as Ghidra prints it: "Stack[-0x8]:4", "EAX:4", "EDX:4,EAX:4"; a register variable that starts
# being used after the entry carries its first use: "EAX:4@0x1c"

_STACK = re.compile(r"^Stack\[(-?0x[0-9a-fA-F]+)\]:(\d+)$")
_REG = re.compile(r"^([A-Za-z][A-Za-z0-9_]*):(\d+)$")


def parse_storage(text):
    """-> (pieces, first_use): pieces [("stack", offset, size) | ("register", name, size)]."""
    storage, _, first = text.partition("@")
    pieces = []
    for piece in storage.split(","):
        piece = piece.strip()
        m = _STACK.match(piece)
        if m:
            pieces.append(("stack", int(m.group(1), 16), int(m.group(2))))
            continue
        m = _REG.match(piece)
        if not m:
            raise ValueError("unknown variable storage %r" % text)
        pieces.append(("register", m.group(1), int(m.group(2))))
    return pieces, int(first, 16) if first else 0


def storage_key(storage, first_use):
    return storage if not first_use else "%s@0x%x" % (storage, first_use)
