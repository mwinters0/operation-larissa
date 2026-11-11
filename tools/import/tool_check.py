"""The importer's check of the programs it needs, made before any step reads or writes anything (import_all.py).

`missing(steps, soundfont)` returns one line per program the given steps call that is absent or unusable, saying which step needs
it and how to get it, so a run that cannot finish refuses at once and lists everything. `version_warnings(steps)` returns one line per
program that is there but not the version the project pins (Godot: mise.toml; the speech engine: uv.lock); `warn` prints them
loudly and the run goes on, so you can try another version (a beta, your distribution's build) at your own risk.
The supported way to get a tool is mise when mise has it (`mise install`: uv, Godot), else the system's packages; the hints name
Fedora's (docs/SETUP.md).

    uv run tools/import/tool_check.py            # the check alone, for every step
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common
import step_audio
import transcripts

GODOT_WRAPPER = common.ROOT / "tools" / "godot.sh"
DNF_MUSIC = "sudo dnf install ffmpeg-free fluidsynth fluid-soundfont-common fluid-soundfont-gm"


def godot_pin() -> str:
    """The Godot version mise.toml pins ("4.7.2-stable"), as Godot's `--version` begins ("4.7.2.stable")."""
    pin = tomllib.loads((common.ROOT / "mise.toml").read_text())["tools"]["godot"]
    return str(pin).replace("-", ".")


def godot_version() -> tuple[str | None, str | None]:
    """(the version tools/godot.sh's Godot prints, None) when it answers, else (None, why it did not)."""
    try:
        done = subprocess.run([str(GODOT_WRAPPER), "--version"], capture_output=True, text=True, timeout=120, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        return None, "tools/godot.sh could not run it (%s)" % error
    lines = [line.strip() for line in done.stdout.splitlines() if line.strip()]
    if done.returncode != 0 or not lines:
        return None, (done.stderr.strip().splitlines() or ["exit code %d" % done.returncode])[-1]
    return lines[-1], None


def check_godot() -> list[str]:
    """Godot answers through tools/godot.sh (GODOT_BIN, mise's `godot`, or the Flatpak)."""
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
    return ["Godot (step godot): tools/godot.sh runs Godot %s, the project pins %s: for the pinned one run `mise install` and put "
            "mise's `godot` first on the PATH (mise activate), or set GODOT_BIN to a %s binary" % (have, want, want)]


def check_audio(soundfont: str) -> list[str]:
    """The music: fluidsynth renders MIDI to WAV with the General MIDI soundfont, ffmpeg encodes it to OGG with libvorbis."""
    problems = []
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        problems.append("ffmpeg (step audio): not found: " + DNF_MUSIC)
    else:
        encoders = subprocess.run([ffmpeg, "-hide_banner", "-encoders"], capture_output=True, text=True, check=False).stdout
        if " libvorbis " not in encoders:
            problems.append("ffmpeg (step audio): %s has no libvorbis encoder: on Fedora install ffmpeg-free (or RPM Fusion's ffmpeg)" % ffmpeg)
    if not shutil.which("fluidsynth"):
        problems.append("fluidsynth (step audio): not found: " + DNF_MUSIC)
    if not Path(soundfont).is_file():
        problems.append("General MIDI soundfont (step audio): %s not found: %s, or name another with --soundfont" % (soundfont, DNF_MUSIC))
    return problems


def check_transcripts() -> list[str]:
    """The speech engine is installed (uv sync)."""
    try:
        transcripts.check_engine()
    except transcripts.EngineMismatch as error:
        return ["speech engine (step transcripts): %s; or leave the step out with --no-transcripts" % error]
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
    every_step = ["transcripts", "audio", "godot"]
    found = missing(every_step)
    for line in found:
        print("MISSING " + line)
    warn(version_warnings(every_step))
    print("all the importer's tools are here" if not found else "%d missing" % len(found))
    sys.exit(1 if found else 0)
