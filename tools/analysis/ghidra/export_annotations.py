# @category Neptune
"""Write the annotations you made in Ghidra into annotations_onwin32.json: comments of every kind, data types you gave to
globals, structs / unions / enums / typedefs you defined, function signatures, local variable names and types, labels inside
functions, equates and Note bookmarks. A plate comment you edited at a named function's entry (or at a global label with
evidence) goes back into that entry's `evidence` in names_onwin32.json / labels_onwin32.json. Names themselves are
export_names.py's.

Your work is told from Ghidra's own by the baseline (a fresh import + analysis of the same EXE, cached next to the project;
the first headless run makes it, about 30 s) and from what the file held when it was last applied (kept in the program by
apply_annotations.py): a three-way merge, so a comment you deleted is deleted from the file, and what others added to the
file since (git pull) is kept. annotations.py has the file format.

  headless:  ./run.sh export_annotations.py [--dry-run | --check] [--dir DIR]
             ./run.sh export_annotations.py --baseline      (only make the baseline; works while the GUI has the project open)
  GUI:       Script Manager > export_annotations.py: prints the diff, asks before writing, then save the program (Ctrl+S)
             so it remembers what was exported.

  --dry-run, -n   print the diff, write nothing
  --check         print the diff, write nothing, exit 1 when there is something to export (`mise run ghidra:gui` runs it
                  first, so that apply_annotations.py never overwrites work that is not in the file yet)
  --dir DIR       read and write the JSON files in DIR instead of next to this script

Teaches: telling a user's work from a tool's output by diffing against a fresh run of the tool (the baseline).
"""
import argparse, hashlib, sys
from pathlib import Path

import annotations as an
import nepghidra as ng
import program_annotations as ga


def baseline_headless():
    path = ng.PROJECT_DIR / "neptune" / ga.BASELINE
    sha = hashlib.sha256(ng.exe_path().read_bytes()).hexdigest()
    return ga.load_baseline(path, sha) or ga.make_baseline(path)


def main(prog, baseline):
    ap = argparse.ArgumentParser(prog="export_annotations.py")
    ap.add_argument("--dry-run", "-n", action="store_true")
    ap.add_argument("--check", action="store_true", help="dry run; exit 1 when there is something to export")
    ap.add_argument("--dir", type=Path, default=Path(__file__).resolve().parent)
    ap.add_argument("--yes", action="store_true", help="GUI: write without asking")
    args, _ = ap.parse_known_args(sys.argv[1:])
    if args.check:
        if ga.export(prog, args.dir, True, baseline):
            print("REFUSED: the Ghidra project has annotations that are not in %s yet; applying the file would overwrite "
                  "them. Export them first: cd tools/analysis/ghidra && ./run.sh export_annotations.py" % an.FILE)
            sys.exit(1)
        return
    dry = args.dry_run
    if ng.in_script_manager(GLOBALS) and not dry and not args.yes:
        n = ga.export(prog, args.dir, True, baseline)
        try:
            dry = not (n and GLOBALS["askYesNo"]("Export annotations", "Write %d changes to the JSON files in %s?" % (n, args.dir)))
        except Exception:  # noqa: BLE001  (cancelled, or no GUI to ask)
            dry = True
        if dry:
            return
    ga.export(prog, args.dir, dry, baseline)
    if ng.in_script_manager(GLOBALS) and not dry:
        print("now save the program (File > Save, Ctrl+S): it records what was exported")


GLOBALS = globals()
if ng.in_script_manager(GLOBALS):
    _prog = GLOBALS["currentProgram"]
    _baseline = ga.load_baseline(ga.project_dir(_prog) / ga.BASELINE, str(_prog.getExecutableSHA256()).lower())
    if _baseline is None:
        print("no baseline for this EXE and this Ghidra yet. Make it from a terminal (the GUI may stay open):\n"
              "  cd tools/analysis/ghidra && ./run.sh export_annotations.py --baseline")
    else:
        main(_prog, _baseline)
elif "--baseline" in sys.argv[1:]:
    ga.make_baseline(ng.PROJECT_DIR / "neptune" / ga.BASELINE)
else:
    _baseline = baseline_headless()
    ng.run(GLOBALS, lambda prog: main(prog, _baseline))
