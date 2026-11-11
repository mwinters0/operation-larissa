"""What the Win16 Ghidra project's functions and global labels are named, and the committed tables that say so. Pure Python.

Two tables, written by export_names16.py from names you give in the Win16 GUI and read by apply_names16.py:
  names_onwin16.json   {"SSSS:OOOO": {"name": ..., "evidence": ...}}  a function: its map address (NE segment number : offset)
  labels_onwin16.json  {"SSSS:OOOO": "name" | {"name": ..., "evidence": ...}}  a global label in a data segment
An entry holds `"map": "SSSS:OOOO"` in place of `"name"` when its name is an ONWIN.MAP public (map_names.py): the name is the game's,
so it is committed as the reference. The names of ONWIN.MAP at the entry's own address are not in the table at all (the map says them).

The name a Win16 function or label has, by the first that applies (`expected`):
  1. the table's entry (a hand name; its evidence becomes the function's comment),
  2. the public of ONWIN.MAP at its address,
  3. the name of its Win32 counterpart (names_onwin32.json), by the known pairs (a `{"map": ...}` entry of that table) and by the
     matcher's matches (matches_win32.json, tier A, B or pin); the comment says which Win32 function and how it is matched.
Anything else keeps the name import_win16.py gave it, w_SSSS_OOOO. apply names the program to `expected`, and export reads
back exactly the user-defined names that differ from it, so what the project derives is never exported as if you had typed it.

Teaches: one derivation shared by the apply and the export of a round trip, so the two cannot disagree.
"""
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
NAMES16 = HERE / "names_onwin16.json"
LABELS16 = HERE / "labels_onwin16.json"
NAMES32 = HERE / "names_onwin32.json"
MATCHES = HERE / "matches_win32.json"
N_CODE_SEGMENTS = 26
LINK_NOTE = "Win32 "                 # a comment this module writes starts with it; one you wrote does not, and is left alone
AUTO_NAME = re.compile(r"^(?:thunk_)?(?:FUN|SUB|DAT|LAB|PTR|UNK|EXT|BYTE|WORD|DWORD|QWORD)_[0-9a-fA-F_]{4,}$"
                       r"|^w_[0-9A-F]{4}_[0-9A-F]{4}$|^(?:s|u|ds|ws)_.*_[0-9a-fA-F_]{4,}$|^(?:switchD|caseD)_[0-9a-fA-F_]+$")


def win16_key(text):
    """'5:1a3' / '0005:01A3' -> '0005:01A3', or None."""
    try:
        seg, off = (int(x, 16) for x in str(text).split(":"))
    except ValueError:
        return None
    return "%04X:%04X" % (seg, off)


def is_code(key):
    return 1 <= int(key[:4], 16) <= N_CODE_SEGMENTS


def ghidra_name(name):
    """The name as the Ghidra project holds it: a symbol name there has no space and no control character (the map's C++ names have
    spaces). apply writes it and export compares with it, so the two agree."""
    return re.sub(r"[\x00-\x20\x7f-\U0010ffff]", "_", name)


def default_name(key):
    return "w_%s_%s" % (key[:4], key[5:])


def links(names32, matches_doc):
    """{win16 key: (win32 key, how)} from the known pairs of names_onwin32.json and the matches' tiers A, B and pin."""
    out = {}
    for tier in ("B", "A", "pin"):                        # a better tier overwrites a worse one (the matcher never gives two)
        for m in (matches_doc or {}).get("matches", []):
            if m["tier"] == tier:
                out[m["win16"]] = (m["win32"], "matcher tier " + tier if tier != "pin" else "pinned")
    for key, entry in names32.items():
        if isinstance(entry, dict) and "map" in entry and win16_key(entry["map"]):
            out[win16_key(entry["map"])] = ("0x%08x" % int(key, 16), "the map")
    return out


def load_tables(names16_path=NAMES16, labels16_path=LABELS16, names32_path=NAMES32, matches_path=MATCHES):
    """(names16, labels16, names32, matches) as parsed JSON; a missing file is an empty table."""
    def read(p, empty):
        return json.loads(Path(p).read_text()) if Path(p).exists() else empty
    return read(names16_path, {}), read(labels16_path, {}), read(names32_path, {}), read(matches_path, {})


def expected(syms, names16, labels16, names32, matches_doc):
    """({key: (name, comment or None)} for the functions, the same for the labels).

    syms: ONWIN.MAP's publics {"SSSS:OOOO": name} (map_names.symbols()). The tables are the committed ones, references not yet resolved."""
    import map_names
    linked = links(names32, matches_doc)
    names32_resolved = map_names.resolve(names32, syms)
    funcs, labels = {}, {}

    def note(key):
        if key in linked:
            win32, how = linked[key]
            return "%s%s (%s)" % (LINK_NOTE, win32, how)
        return None

    for key, name in syms.items():
        k = win16_key(key)
        if k and int(k[:4], 16) > 0:
            (funcs if is_code(k) else labels)[k] = (name, note(k))
    for key, (win32, how) in linked.items():
        if key not in funcs and is_code(key):
            entry = names32_resolved.get(win32) or names32_resolved.get("0x%08x" % int(win32, 16))
            if isinstance(entry, dict) and entry.get("name"):
                funcs[key] = (entry["name"], "%s%s (%s)" % (LINK_NOTE, win32, how))
    for table, out in ((map_names.resolve(names16, syms), funcs), (map_names.resolve(labels16, syms), labels)):
        for key, entry in table.items():
            k = win16_key(key)
            if k is None:
                continue
            entry = entry if isinstance(entry, dict) else {"name": entry}
            out[k] = (entry["name"], entry.get("evidence") or (out.get(k) or (None, None))[1])
    return funcs, labels


def merge(existing, found, syms, wanted, functions=True):
    """(the new table, [(key, old name or None, new name)]). existing keeps its order, new entries go last.

    found: {key: [user-defined names there, the primary first]}; wanted: {key: (name, comment)} from `expected`; a name equal to what
    the project derives is not exported. A new function is a dict ({"name"} or {"map"}), a new label a plain string (or {"map"})."""
    import map_names
    out = dict(existing)
    changes = []
    for key, names in sorted(found.items()):
        cur = existing.get(key)
        cur_name = None if cur is None else map_names.name_of(cur, syms)
        if cur_name is not None and ghidra_name(cur_name) in names:
            continue
        new = names[0]
        if key in wanted and ghidra_name(wanted[key][0]) == new and cur is None:
            continue                                      # what the map or the matcher says, not something typed
        out[key] = map_names.with_name(({} if functions else None) if cur is None else cur, new, syms)
        changes.append((key, cur_name, new))
    return out, changes
