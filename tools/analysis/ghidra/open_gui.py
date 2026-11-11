"""Opens the Ghidra GUI on the project the headless scripts build (ghidra-project/neptune/neptune.gpr, or under
NEP_GHIDRA_PROJECT), through PyGhidra so the Script Manager runs our Python scripts (apply_names.py, export_names.py ...).

  ./run.sh open_gui.py          (= `mise run ghidra:gui`; `mise run ghidra:import` builds or updates the project first)
  ./run.sh open_gui.py --win16  (= `mise run ghidra16:gui`: the Win16 project, ghidra-project16/neptune16/, made by import_win16.py)

It returns when Ghidra closes. Building the project first (apply_problem_types.py, apply_names.py) is up to the caller; with
no project yet, Ghidra opens with an empty project window. See docs/port/GHIDRA_GUI.md.

Teaches: starting the Ghidra GUI from Python (pyghidra.GuiPyGhidraLauncher) with a project file as Ghidra's argument.
"""
import os
import sys
from pathlib import Path

# The same defaults as nepghidra.py, which is not imported: importing it starts a headless JVM, and a process has one JVM, so the
# GUI could not start after it.
INSTALL_DIR = Path(os.environ.get("GHIDRA_INSTALL_DIR", Path.home() / ".local/bin/ghidra/ghidra_12.2_PUBLIC"))
PROJECT_DIR = Path(os.environ.get("NEP_GHIDRA_PROJECT", Path.cwd() / "ghidra-project"))
PROJECT16_DIR = Path(os.environ.get("NEP_GHIDRA_PROJECT16", Path.cwd() / "ghidra-project16"))


def main() -> int:
    import pyghidra
    if "--win16" in sys.argv[1:]:
        project = PROJECT16_DIR / "neptune16" / "neptune16.gpr"
        how = "run ./run.sh import_win16.py first (mise run ghidra16:import)"
    else:
        project = PROJECT_DIR / "neptune" / "neptune.gpr"      # PyGhidra nests the project one directory down
        how = "run ./run.sh apply_problem_types.py and ./run.sh apply_names.py first (mise run ghidra:import does both)"
    if not project.is_file():
        print("no Ghidra project at %s yet: %s" % (project, how), file=sys.stderr)
        return 1
    launcher = pyghidra.GuiPyGhidraLauncher(install_dir=INSTALL_DIR)
    launcher.args = [str(project)]                               # GhidraRun opens a .gpr given as its argument
    launcher.start()
    return 0


if __name__ == "__main__":
    sys.exit(main())
