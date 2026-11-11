"""tools/godot.py: on Linux `command()` is the wrapper tools/godot.sh (test_godot_wrapper.py tests its choice); on Windows it picks
$GODOT_BIN, else `godot` on the PATH, else mise's install of the pinned Godot, and runs the `_console.exe` beside a Windows Godot
when there is one. The Windows choice is tested here on any machine: `WINDOWS` is switched on and `shutil.which` and `mise where`
answer from the test's own folder, so the machine's own Godot never answers."""
import subprocess
from pathlib import Path

import pytest

import godot


@pytest.fixture
def windows(monkeypatch):
    """godot.py as on Windows, with no GODOT_BIN, nothing on the PATH and no mise."""
    monkeypatch.setattr(godot, "WINDOWS", True)
    monkeypatch.delenv("GODOT_BIN", raising=False)
    monkeypatch.setattr(godot.shutil, "which", lambda name: None)


def exe(folder: Path, name: str) -> Path:
    folder.mkdir(parents=True, exist_ok=True)
    program = folder / name
    program.write_bytes(b"")
    return program


def test_off_windows_the_command_is_the_bash_wrapper(monkeypatch):
    monkeypatch.setattr(godot, "WINDOWS", False)
    assert godot.command() == [str(godot.WRAPPER)]
    assert godot.by_hand("--version") == "tools/godot.sh --version"


def test_windows_takes_godot_bin_and_prefers_its_console_twin(windows, monkeypatch, tmp_path):
    gui = exe(tmp_path, "Godot_v4.7.2-stable_win64.exe")
    monkeypatch.setenv("GODOT_BIN", str(gui))
    assert godot.command() == [str(gui)]
    console = exe(tmp_path, "Godot_v4.7.2-stable_win64_console.exe")
    assert godot.command() == [str(console)]
    assert godot.by_hand("--version") == "uv run tools/godot.py --version"


def test_windows_refuses_a_godot_bin_that_is_not_there(windows, monkeypatch, tmp_path):
    monkeypatch.setenv("GODOT_BIN", str(tmp_path / "nothing.exe"))
    with pytest.raises(godot.GodotNotFound, match="GODOT_BIN"):
        godot.command()


def test_windows_takes_godot_on_the_path(windows, monkeypatch, tmp_path):
    shim = exe(tmp_path / "shims", "godot.exe")
    monkeypatch.setattr(godot.shutil, "which", lambda name: str(shim) if name == "godot" else None)
    assert godot.command() == [str(shim)]


def test_windows_finds_mise_s_install_when_mise_is_not_activated(windows, monkeypatch, tmp_path):
    install = tmp_path / "mise" / "installs" / "godot" / "4.7.2-stable"
    exe(install, "Godot_v4.7.2-stable_win64.exe")
    console = exe(install, "Godot_v4.7.2-stable_win64_console.exe")
    monkeypatch.setattr(godot.shutil, "which", lambda name: "mise.exe" if name == "mise" else None)
    monkeypatch.setattr(godot.subprocess, "run",
                        lambda *a, **k: subprocess.CompletedProcess(a[0], 0, stdout=str(install) + "\n", stderr=""))
    assert godot.command() == [str(console)]


def test_windows_without_any_godot_says_how_to_get_one(windows):
    with pytest.raises(godot.GodotNotFound, match="mise install"):
        godot.command()


def test_main_runs_godot_with_the_arguments_and_returns_its_code(monkeypatch):
    seen = []
    monkeypatch.setattr(godot, "command", lambda: ["my_godot"])
    monkeypatch.setattr(godot.subprocess, "run", lambda cmd, check: (seen.append(cmd), subprocess.CompletedProcess(cmd, 3))[1])
    assert godot.main(["--path", "godot"]) == 3
    assert seen == [["my_godot", "--path", "godot"]]
