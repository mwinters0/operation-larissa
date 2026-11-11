# @category Neptune
"""Write the names you gave in Ghidra back into names_onwin32.json / labels_onwin32.json.

Collects every USER_DEFINED function name and global label (Ghidra's own FUN_ / DAT_ / LAB_ / s_ ... names
and the g_probNN labels made by apply_problem_types.py are skipped) and, compared with the JSON files:
  * adds the ones that are not in the file: a function as {"name": ...}, a label as a plain string. Evidence is optional:
    add an "evidence" note by hand (or as the plate comment in Ghidra, export_annotations.py) when there is something to say,
  * updates the name where the address is in the file under a different name (evidence is kept).
A name that is an ONWIN.MAP public is written as its reference ("map"), never as the name (map_names.py; the table the importer
made from your ISO must exist). Nothing is ever removed and existing evidence is never touched. File formatting is preserved (indent=1,
"0x%08x" keys, new entries appended), so the git diff only shows the entries that changed.

  headless:  ./run.sh export_names.py [--dry-run | --check] [--dir DIR]
  GUI:       Script Manager > export_names.py. It prints the diff, then asks whether to write the files
             (answer No to just look). The GUI cannot pass arguments; use the headless form for --dir.

  --dry-run, -n   print the diff, write nothing
  --check         print the diff, write nothing, and exit 1 when there is something to export (`mise run ghidra:import`
                  runs it first, so that apply_names.py never renames back a GUI rename that is not in the JSON yet)
  --dir DIR       read/write the JSON files in DIR instead of next to this script (for testing)
"""
import argparse, difflib, json, re, sys
from pathlib import Path
import nepghidra as ng
import map_names

# names Ghidra generates itself (the SourceType check already excludes them; this guards a hand-typed one)
AUTO_NAME = re.compile(
    r"^(?:thunk_)?(?:FUN|SUB|DAT|LAB|PTR|UNK|EXT|BYTE|WORD|DWORD|QWORD|PTR_FUN)_[0-9a-fA-F]{6,8}$"
    r"|^(?:s|u|ds|ws)_.*_[0-9a-fA-F]{6,8}$|^(?:switchD|caseD)_[0-9a-fA-F]+$")


def key(address):
    return "0x%08x" % address.getOffset()


def collect(prog, managed=()):
    """-> (functions, labels): {address key: name} for everything user-defined in the program."""
    from ghidra.program.model.symbol import SourceType, SymbolType
    notes = []
    funcs = {}
    for f in prog.getFunctionManager().getFunctions(True):
        sym = f.getSymbol()
        if sym.getSource() != SourceType.USER_DEFINED or AUTO_NAME.match(f.getName()):
            continue
        if not sym.getParentNamespace().isGlobal():
            notes.append("function %s is in namespace %s; exporting the bare name" % (f.getName(), sym.getParentNamespace().getName()))
        funcs[key(f.getEntryPoint())] = f.getName()

    by_addr = {}
    for sym in prog.getSymbolTable().getAllSymbols(False):
        if sym.getSymbolType() != SymbolType.LABEL or sym.getSource() != SourceType.USER_DEFINED:
            continue
        if not sym.getAddress().isMemoryAddress() or not sym.getParentNamespace().isGlobal():
            continue
        if AUTO_NAME.match(sym.getName()) or (key(sym.getAddress()), sym.getName()) in managed:
            continue
        by_addr.setdefault(key(sym.getAddress()), []).append(sym)
    labels = {}
    for k, syms in by_addr.items():
        syms.sort(key=lambda s: (not s.isPrimary(), s.getName()))
        labels[k] = [s.getName() for s in syms]          # primary first
    return funcs, labels, notes


def merge(existing, found, syms, functions=True):
    """Return (new dict, [(key, old name or None, new name)]). existing keeps its order, additions go last.

    existing is the committed table (names or ONWIN.MAP references), syms the MAP's publics (map_names.symbols()).
    A new function is a dict ({"name"} or {"map"}), a new label a plain string (or {"map"}); neither has evidence."""
    out = dict(existing)
    changes = []
    for k, names in found.items():
        cur = existing.get(k)
        cur_name = None if cur is None else map_names.name_of(cur, syms)
        if cur_name is not None and cur_name in names:      # the file's name is still one of the labels there
            continue
        new = names[0]
        out[k] = map_names.with_name(({} if functions else None) if cur is None else cur, new, syms)
        changes.append((k, cur_name, new))
    return out, changes


def dump(d):
    return json.dumps(d, indent=1) + "\n"


def export(prog, directory, dry_run, log=print):
    """Compare the program with the JSON files in `directory`; write them unless dry_run. Returns #changes."""
    ng.check_program(prog)
    layout = ng.REPO / "docs/data/problem_layouts32.json"
    managed = set()      # (address key, name) pairs owned by apply_problem_types.py
    if layout.exists():
        for t, s in json.loads(layout.read_text())["types"].items():
            managed.add(("0x%08x" % int(s["global"], 16), "g_prob%02d" % int(t)))
    funcs, labels, notes = collect(prog, managed)
    syms = map_names.symbols()
    total = 0
    for fname, found, what in (("names_onwin32.json", {k: [v] for k, v in funcs.items()}, "function"),
                               ("labels_onwin32.json", labels, "label")):
        path = directory / fname
        raw = path.read_text() if path.exists() else "{}\n"
        existing = json.loads(raw)
        merged, changes = merge(existing, found, syms, what == "function")
        for k, names in found.items():
            if len(names) > 1:
                notes.append("%s %s has several user labels %s; only %s is exported" % (what, k, names, names[0]))
        for k, old, new in changes:
            if old is None:
                log("+ %s  %s  %s   (new)" % (what, k, new))
            else:
                log("~ %s  %s  %s -> %s" % (what, k, old, new))
        total += len(changes)
        new_text = dump(merged)
        if new_text != raw:
            if dry_run:
                for line in difflib.unified_diff(raw.splitlines(), new_text.splitlines(), "a/" + fname, "b/" + fname, n=0, lineterm=""):
                    log(line)
            else:
                path.write_text(new_text)
                log("wrote %s" % path)
    for n in notes:
        log("note: " + n)
    if not total:
        log("nothing to export: the JSON files already hold every user-defined name")
    return total


def main(prog):
    ap = argparse.ArgumentParser(prog="export_names.py")
    ap.add_argument("--dry-run", "-n", action="store_true")
    ap.add_argument("--check", action="store_true", help="dry run; exit 1 when there is something to export")
    ap.add_argument("--dir", type=Path, default=Path(__file__).resolve().parent)
    ap.add_argument("--yes", action="store_true", help="GUI: write without asking")
    args = ap.parse_args(sys.argv[1:])
    if args.check:
        if export(prog, args.dir, True):
            print("REFUSED: the Ghidra project has names that are not in the JSON files yet; applying the JSON would rename "
                  "them back. Export them first: mise run ghidra:export")
            sys.exit(1)
        return
    dry = args.dry_run
    if ng.in_script_manager(GLOBALS) and not dry and not args.yes:
        n = export(prog, args.dir, True)
        try:
            dry = not (n and GLOBALS["askYesNo"]("Export names", "Write %d changed entries to the JSON files in %s?" % (n, args.dir)))
        except Exception:  # noqa: BLE001  (cancelled, or no GUI to ask)
            dry = True
        if dry:
            return
    export(prog, args.dir, dry)


GLOBALS = globals()
ng.run(GLOBALS, main)
