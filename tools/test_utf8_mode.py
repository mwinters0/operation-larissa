"""tools/utf8_mode.py: off Windows, or already in UTF-8 mode, `ensure()` does nothing; on Windows outside it, the same command runs again
with PYTHONUTF8=1 and its exit code ends this one. The Windows case is tested on any machine with `os.name` and `subprocess.run` faked."""
import subprocess
import sys

import pytest

import utf8_mode


def test_off_windows_it_does_nothing(monkeypatch):
    monkeypatch.setattr(utf8_mode.os, "name", "posix")
    monkeypatch.setattr(utf8_mode.subprocess, "run", lambda *a, **k: pytest.fail("ran a second Python"))
    utf8_mode.ensure()


def test_on_windows_it_runs_the_command_again_in_utf8_mode(monkeypatch):
    seen = {}

    def run(cmd, env, check):
        seen.update(cmd=cmd, env=env)
        return subprocess.CompletedProcess(cmd, 7)

    monkeypatch.setattr(utf8_mode.os, "name", "nt")
    monkeypatch.setattr(utf8_mode.sys, "flags", type("Flags", (), {"utf8_mode": 0})())
    monkeypatch.setattr(utf8_mode.sys, "orig_argv", ["python.exe", "tools/import/import_all.py", "--only", "audio"])
    monkeypatch.setattr(utf8_mode.subprocess, "run", run)
    with pytest.raises(SystemExit) as stop:
        utf8_mode.ensure()
    assert stop.value.code == 7
    assert seen["cmd"] == [sys.executable, "tools/import/import_all.py", "--only", "audio"]
    assert seen["env"]["PYTHONUTF8"] == "1"


def test_in_utf8_mode_it_does_nothing(monkeypatch):
    monkeypatch.setattr(utf8_mode.os, "name", "nt")
    monkeypatch.setattr(utf8_mode.sys, "flags", type("Flags", (), {"utf8_mode": 1})())
    monkeypatch.setattr(utf8_mode.subprocess, "run", lambda *a, **k: pytest.fail("ran a second Python"))
    utf8_mode.ensure()
