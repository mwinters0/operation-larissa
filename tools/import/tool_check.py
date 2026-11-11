"""The importer's check of the programs it needs, made before any step reads or writes anything (import_all.py).

`missing(steps, soundfont)` returns one line per program the given steps call that is absent or unusable, saying which step needs
it and how to get it, so a run that cannot finish refuses at once and lists everything. `version_warnings(steps)` returns one line per
program that is there but not the version the project pins (Godot: mise.toml; the speech engine: uv.lock); `warn` prints them
loudly and the run goes on, so you can try another version (a beta, your distribution's build) at your own risk.
The supported way to get a tool is mise when mise has it (`mise install`: uv, Godot), else the system's packages; the hints name
Fedora's on Linux and the Windows ones on Windows (docs/SETUP.md).

    uv run tools/import/tool_check.py            # the check alone, for every step
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import common
import godot
import step_audio
import transcripts

WINDOWS = os.name == "nt"
LAUNCHER = "tools/godot.py" if WINDOWS else "tools/godot.sh"      # what runs Godot here (godot.command())
DNF_MUSIC = "sudo dnf install ffmpeg-free fluidsynth fluid-soundfont-common fluid-soundfont-gm"
# How to get each music tool on Windows (docs/SETUP.md, "On Windows"); on Linux the one dnf line installs all three.
WINDOWS_HINTS = {
    "ffmpeg": "tools\\setup_windows.ps1 installs it (or: winget install --id Gyan.FFmpeg.Essentials -e)",
    "fluidsynth": "tools\\setup_windows.ps1 installs it (or: the win10-x64 zip of a release from "
                  "github.com/FluidSynth/fluidsynth/releases, its bin folder on the PATH)",
    "soundfont": "uv run tools/fetch_soundfont.py (mise run setup and tools\\setup_windows.ps1 run it)",
}


def music_hint(tool: str) -> str:
    """How to get one of the music tools here (ffmpeg, fluidsynth, soundfont)."""
    return WINDOWS_HINTS[tool] if WINDOWS else DNF_MUSIC


def godot_pin() -> str:
    """The Godot version mise.toml pins ("4.7.2-stable"), as Godot's `--version` begins ("4.7.2.stable")."""
    pin = tomllib.loads((common.ROOT / "mise.toml").read_text())["tools"]["godot"]
    return str(pin).replace("-", ".")


def godot_version() -> tuple[str | None, str | None]:
    """(the version the Godot of godot.command() prints, None) when it answers, else (None, why it did not)."""
    try:
        done = subprocess.run(godot.command() + ["--version"], capture_output=True, text=True, timeout=120, check=False)
    except godot.GodotNotFound as error:
        return None, str(error)
    except (OSError, subprocess.TimeoutExpired) as error:
        return None, "%s could not run it (%s)" % (LAUNCHER, error)
    lines = [line.strip() for line in done.stdout.splitlines() if line.strip()]
    if done.returncode != 0 or not lines:
        return None, (done.stderr.strip().splitlines() or ["exit code %d" % done.returncode])[-1]
    return lines[-1], None


def check_godot() -> list[str]:
    """Godot answers through godot.command(): tools/godot.sh (GODOT_BIN, mise's `godot`, or the Flatpak), or on Windows the program
    tools/godot.py finds (GODOT_BIN, `godot` on the PATH, or mise's install)."""
    have, why = godot_version()
    if have is None:
        return ["Godot (step godot): not found (%s): run `mise install` in the repository (mise.toml pins Godot), or set GODOT_BIN" % why]
    return []


def godot_version_warning() -> list[str]:
    """Godot is the version mise.toml pins (nothing to say when it does not answer: check_godot refuses that)."""
    want = godot_pin()
    have, _ = godot_version()
    if have is None or have.startswith(want):
        return []
    return ["Godot (step godot): %s runs Godot %s, the project pins %s: for the pinned one run `mise install` and put "
            "mise's `godot` first on the PATH (mise activate), or set GODOT_BIN to a %s binary" % (LAUNCHER, have, want, want)]


def check_audio(soundfont: str) -> list[str]:
    """The music: fluidsynth renders MIDI to WAV with the General MIDI soundfont, ffmpeg encodes it to OGG with libvorbis."""
    problems = []
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        problems.append("ffmpeg (step audio): not found: " + music_hint("ffmpeg"))
    else:
        encoders = subprocess.run([ffmpeg, "-hide_banner", "-encoders"], capture_output=True, text=True, check=False).stdout
        if " libvorbis " not in encoders:
            problems.append("ffmpeg (step audio): %s has no libvorbis encoder: %s" % (
                ffmpeg, "install Gyan.FFmpeg.Essentials (Gyan's builds have it)" if WINDOWS else "on Fedora install ffmpeg-free (or RPM Fusion's ffmpeg)"))
    if not shutil.which("fluidsynth"):
        problems.append("fluidsynth (step audio): not found: " + music_hint("fluidsynth"))
    if not Path(soundfont).is_file():
        problems.append("General MIDI soundfont (step audio): %s not found: %s, or name another with --soundfont" % (soundfont, music_hint("soundfont")))
    return problems


def check_transcripts() -> list[str]:
    """The speech engine is installed (uv sync)."""
    try:
        transcripts.check_engine()
    except transcripts.EngineMismatch as error:
        return ["speech engine (step transcripts): %s" % error]
    return []


def transcripts_version_warning() -> list[str]:
    """The speech engine is the version uv.lock pins."""
    differs = transcripts.engine_version_warning()
    return ["speech engine (step transcripts): %s" % differs] if differs else []


def missing(steps: list[str], soundfont: str = step_audio.DEFAULT_SOUNDFONT) -> list[str]:
    """Every problem with the tools the given steps need, in step order; [] when the run can go ahead."""
    problems: list[str] = []
    if "transcripts" in steps:
        problems += check_transcripts()
    if "audio" in steps:
        problems += check_audio(soundfont)
    if "godot" in steps:
        problems += check_godot()
    return problems


def version_warnings(steps: list[str]) -> list[str]:
    """Every program the given steps call that is there but not the pinned version, in step order; the run goes on."""
    found: list[str] = []
    if "transcripts" in steps:
        found += transcripts_version_warning()
    if "godot" in steps:
        found += godot_version_warning()
    return found


def warn(lines: list[str]) -> None:
    """Print version warnings so they cannot be missed: framed, on stderr. Not a refusal."""
    if not lines:
        return
    bar = "!" * 100
    print(bar, file=sys.stderr)
    print("!!! WARNING: not the version the project pins, tests and supports. Going on anyway; results may differ.", file=sys.stderr)
    for line in lines:
        print("!!!   - " + line, file=sys.stderr)
    print(bar, file=sys.stderr)


if __name__ == "__main__":
    import utf8_mode
    utf8_mode.ensure()
    every_step = ["transcripts", "audio", "godot"]
    found = missing(every_step)
    for line in found:
        print("MISSING " + line)
    warn(version_warnings(every_step))
    print("all the importer's tools are here" if not found else "%d missing" % len(found))
    sys.exit(1 if found else 0)
