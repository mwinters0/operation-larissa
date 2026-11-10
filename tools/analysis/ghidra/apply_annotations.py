# @category Neptune
"""Apply annotations_onwin32.json to ONWIN32.EXE: types, data types of globals, function signatures, local variables,
labels inside functions, comments, equates and Note bookmarks (annotations.py has the format). Run it after
apply_problem_types.py and apply_names.py (it types functions that apply_names.py creates). Safe to run repeatedly.

What the last apply wrote and the file no longer has (someone deleted it, and you pulled) is removed from the program; a
signature stays as it is. Every entry is read back after writing; one that reads back differently is reported and left out
of the record of what was applied, so the next export does not take it for a deletion.

  headless:  ./run.sh apply_annotations.py [--dir DIR]   (opens/creates the project in NEP_GHIDRA_PROJECT)
  GUI:       Script Manager > apply_annotations.py    (applies to the open program; then File > Save)
Annotations made in the GUI and not exported yet may be overwritten: run export_annotations.py first (`mise run ghidra:gui`
refuses to apply while there are some).

Teaches: writing to a Ghidra program in one transaction, and checking a write by reading it back.
"""
import argparse, sys
from pathlib import Path

import nepghidra as ng
import program_annotations as ga


def main(prog):
    ap = argparse.ArgumentParser(prog="apply_annotations.py")
    ap.add_argument("--dir", type=Path, default=None, help="read the JSON files in DIR instead of next to this script")
    args, _ = ap.parse_known_args(sys.argv[1:])
    ga.apply(prog, args.dir)
    if ng.in_script_manager(GLOBALS):
        print("now save the program (File > Save, Ctrl+S)")


GLOBALS = globals()
ng.run(GLOBALS, main)
