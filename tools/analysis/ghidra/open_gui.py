"""Opens the Ghidra GUI on the project the headless scripts build (ghidra-project/neptune/neptune.gpr, or under
NEP_GHIDRA_PROJECT), through PyGhidra so the Script Manager runs our Python scripts (apply_names.py, export_names.py ...).

  ./run.sh open_gui.py        (= `mise run ghidra:gui`; `mise run ghidra:import` builds or updates the project first)

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


def main() -> int:
    import pyghidra
    project = PROJECT_DIR / "neptune" / "neptune.gpr"          # PyGhidra nests the project one directory down
    if not project.is_file():
        print("no Ghidra project at %s yet: run ./run.sh apply_problem_types.py and ./run.sh apply_names.py first "
              "(mise run ghidra:import does both)" % project, file=sys.stderr)
        return 1
    launcher = pyghidra.GuiPyGhidraLauncher(install_dir=INSTALL_DIR)
    launcher.args = [str(project)]                               # GhidraRun opens a .gpr given as its argument
    launcher.start()
    return 0


if __name__ == "__main__":
    sys.exit(main())
