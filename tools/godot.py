"""Which Godot the tools run, and a launcher for it that works on Windows as well as Linux.

    uv run tools/godot.py --headless --path godot --import       # on Windows, what `tools/godot.sh ...` is on Linux

Teaches: one function that answers "how do I start this program here?", so every caller (the importer's tool check, its last
step, the mise tasks) asks it instead of spelling a path. On Linux and macOS `command()` is `tools/godot.sh`, the wrapper every
manual names, so nothing changes there. Windows cannot run a bash script, so there `command()` finds Godot itself, in the same
order as the wrapper:

1. `$GODOT_BIN` when it is set (one executable path or name, no arguments in it);
2. `godot` on the PATH (mise's shim when mise is activated, or any other);
3. mise's own install of the pinned Godot (`mise where godot`), when mise is installed but not activated.

A Windows Godot comes as two programs, `Godot_v4.7.2-stable_win64.exe` and `Godot_v4.7.2-stable_win64_console.exe`. Only the
console one writes its output to the terminal or to a pipe (the importer reads `--version` from it), so when the chosen program
has a `_console.exe` beside it, that one is run. docs/SETUP.md, "Godot", says which Godot to install.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WRAPPER = ROOT / "tools" / "godot.sh"
WINDOWS = os.name == "nt"


class GodotNotFound(FileNotFoundError):
    pass


def _console_of(program: Path) -> Path:
    """The `_console.exe` beside a Windows Godot when there is one, else the program itself."""
    if program.suffix.lower() == ".exe" and not program.stem.lower().endswith("_console"):
        console = program.with_name(program.stem + "_console.exe")
        if console.is_file():
            return console
    return program


def _mise_install() -> Path | None:
    """The Godot executable of mise's install of the pinned version (Windows), or None."""
    mise = shutil.which("mise")
    if not mise:
        return None
    try:
        done = subprocess.run([mise, "where", "godot"], cwd=ROOT, capture_output=True, text=True, timeout=60, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None
    folder = Path(done.stdout.strip()) if done.returncode == 0 and done.stdout.strip() else None
    if folder is None or not folder.is_dir():
        return None
    found = sorted(p for p in folder.rglob("*.exe") if p.name.lower().startswith("godot"))
    consoles = [p for p in found if p.stem.lower().endswith("_console")]
    return (consoles or found or [None])[0]


def find_windows() -> Path:
    """The Godot program on Windows, in the order of the module docstring. GodotNotFound says how to get one."""
    wanted = os.environ.get("GODOT_BIN")
    if wanted:
        named = shutil.which(wanted) or (wanted if Path(wanted).is_file() else None)
        if not named:
            raise GodotNotFound("GODOT_BIN=%r is not an executable" % wanted)
        return _console_of(Path(named))
    on_path = shutil.which("godot")
    if on_path:
        return _console_of(Path(on_path))
    installed = _mise_install()
    if installed:
        return installed
    raise GodotNotFound("no Godot found: run `mise install` in the repository (mise.toml pins Godot), "
                        "or set GODOT_BIN to Godot_v4.7.2-stable_win64_console.exe")


def command() -> list[str]:
    """The command that starts Godot here, without arguments: the wrapper on Linux and macOS, the program itself on Windows."""
    if WINDOWS:
        return [str(find_windows())]
    return [str(WRAPPER)]


def by_hand(args: str) -> str:
    """How a manual or a message writes a Godot command with `args` for this platform."""
    return ("uv run tools/godot.py " if WINDOWS else "tools/godot.sh ") + args


def main(argv: list[str]) -> int:
    try:
        program = command()
    except GodotNotFound as error:
        print("tools/godot.py: %s" % error, file=sys.stderr)
        return 127
    return subprocess.run(program + argv, check=False).returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
