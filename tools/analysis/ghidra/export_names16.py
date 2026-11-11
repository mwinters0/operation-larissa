# @category Neptune
"""Write the names you gave in the Win16 GUI back into names_onwin16.json / labels_onwin16.json.

Collects every USER_DEFINED function name and global label of ONWIN.EXE that is not what the project derives (win16_names.expected: the
map's name, the name of the Win32 counterpart, or what the table already says) and not one of Ghidra's own (FUN_, DAT_, w_SSSS_OOOO ...),
and, compared with the JSON files:
  * adds the ones that are not in the file: a function as {"name": ...}, a label as a plain string; evidence is optional, added by hand,
  * updates the name where the address is in the file under a different name (evidence is kept).
A name that is an ONWIN.MAP public of another address is written as its reference ("map"), never as the name (map_names.py). Nothing is
ever removed and existing evidence is never touched. File formatting is preserved (indent=1, new entries appended).

  headless:  ./run.sh export_names16.py [--dry-run | --check] [--dir DIR]      (= `mise run ghidra16:export`)
  GUI:       Script Manager > export_names16.py (prints the diff, then asks whether to write; the GUI cannot pass arguments)

  --dry-run, -n   print the diff, write nothing
  --check         print the diff, write nothing, and exit 1 when there is something to export (`mise run ghidra16:import` runs it first,
                  so that apply_names16.py never renames back a GUI rename that is not in the JSON yet)
  --dir DIR       read/write the JSON files in DIR instead of next to this script (for testing)
"""
import argparse
import difflib
import json
import sys
from pathlib import Path

import map_names
import nepghidra as ng
import win16_map
import win16_names as wn


def key16(address):
    seg, off = (int(x, 16) for x in str(address).split(":"))
    return win16_map.win16_id((seg - 0x1000) // 8 + 1, off)


def collect(prog):
    """({key: name} of user-defined functions, {key: [names]} of user-defined global labels), Ghidra's own names left out."""
    from ghidra.program.model.symbol import SourceType, SymbolType
    funcs, by_addr = {}, {}
    for f in prog.getFunctionManager().getFunctions(True):
        sym = f.getSymbol()
        if sym.getSource() == SourceType.USER_DEFINED and not wn.AUTO_NAME.match(f.getName()):
            funcs[key16(f.getEntryPoint())] = f.getName()
    for sym in prog.getSymbolTable().getAllSymbols(False):
        if sym.getSymbolType() != SymbolType.LABEL or sym.getSource() != SourceType.USER_DEFINED:
            continue
        if not sym.getAddress().isMemoryAddress() or not sym.getParentNamespace().isGlobal() or wn.AUTO_NAME.match(sym.getName()):
            continue
        by_addr.setdefault(key16(sym.getAddress()), []).append(sym)
    labels = {}
    for k, syms in by_addr.items():
        syms.sort(key=lambda s: (not s.isPrimary(), s.getName()))
        labels[k] = [s.getName() for s in syms]
    return funcs, labels


def dump(d):
    return json.dumps(d, indent=1) + "\n"


def export(prog, directory, dry_run, log=print):
    """Compare the program with the JSON files in `directory`; write them unless dry_run. Returns the number of changes."""
    ng.check_program16(prog)
    syms = map_names.symbols()
    names_path, labels_path = directory / "names_onwin16.json", directory / "labels_onwin16.json"
    tables = wn.load_tables(names_path, labels_path)
    funcs_wanted, labels_wanted = wn.expected(syms, *tables)
    funcs, labels = collect(prog)
    total = 0
    for path, existing, found, wanted, what in ((names_path, tables[0], {k: [v] for k, v in funcs.items()}, funcs_wanted, "function"),
                                                (labels_path, tables[1], labels, labels_wanted, "label")):
        raw = path.read_text() if path.exists() else "{}\n"
        merged, changes = wn.merge(existing, found, syms, wanted, what == "function")
        for k, old, new in changes:
            log("+ %s  %s  %s   (new)" % (what, k, new) if old is None else "~ %s  %s  %s -> %s" % (what, k, old, new))
        for k, names in found.items():
            if len(names) > 1:
                log("note: %s %s has several user labels %s; only %s is exported" % (what, k, names, names[0]))
        total += len(changes)
        new_text = dump(merged)
        if new_text != raw and (changes or path.exists()):
            if dry_run:
                for line in difflib.unified_diff(raw.splitlines(), new_text.splitlines(), "a/" + path.name, "b/" + path.name, n=0, lineterm=""):
                    log(line)
            else:
                path.write_text(new_text)
                log("wrote %s" % path)
    if not total:
        log("nothing to export: the JSON files already hold every user-defined name")
    return total


def main(prog):
    ap = argparse.ArgumentParser(prog="export_names16.py")
    ap.add_argument("--dry-run", "-n", action="store_true")
    ap.add_argument("--check", action="store_true", help="dry run; exit 1 when there is something to export")
    ap.add_argument("--dir", type=Path, default=Path(__file__).resolve().parent)
    ap.add_argument("--yes", action="store_true", help="GUI: write without asking")
    args = ap.parse_args(sys.argv[1:])
    if args.check:
        if export(prog, args.dir, True):
            print("REFUSED: the Win16 Ghidra project has names that are not in the JSON files yet; applying the JSON would rename "
                  "them back. Export them first: mise run ghidra16:export")
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
ng.run(GLOBALS, main, win16=True)
