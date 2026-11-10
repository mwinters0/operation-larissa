"""The importer's tool check (tool_check.py): each step's programs are looked for before anything is written, and every missing one is
named with how to get it; one there at another version than the pinned one is a loud warning, not a refusal. The tests put fakes on a
PATH of their own, so the machine's own tools never answer."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import tool_check


def fake(folder: Path, name: str, output: str = "") -> None:
    script = folder / name
    script.write_text("#!/bin/sh\nprintf '%%s\\n' '%s'\n" % output)          # printf is the shell's own: the PATH holds only fakes
    script.chmod(0o755)


@pytest.fixture
def path_of_fakes(tmp_path, monkeypatch):
    folder = tmp_path / "bin"
    folder.mkdir()
    monkeypatch.setenv("PATH", str(folder))
    return folder


def test_the_godot_pin_is_mise_s():
    assert tool_check.godot_pin().startswith("4.7.2.")


def test_steps_that_call_no_program_need_nothing(path_of_fakes):
    assert tool_check.missing(["extract", "tables", "images", "sectors"]) == []


def test_audio_names_each_missing_tool_and_the_fedora_packages(path_of_fakes, tmp_path):
    problems = tool_check.missing(["audio"], str(tmp_path / "no.sf2"))
    assert [p.split(" ")[0] for p in problems] == ["ffmpeg", "fluidsynth", "General"]
    assert all("dnf install" in p for p in problems)


def test_audio_wants_the_libvorbis_encoder(path_of_fakes, tmp_path):
    fake(path_of_fakes, "fluidsynth")
    fake(path_of_fakes, "ffmpeg", " A....D vorbis               Vorbis")
    font = tmp_path / "gm.sf2"
    font.write_bytes(b"")
    problems = tool_check.missing(["audio"], str(font))
    assert len(problems) == 1 and "libvorbis" in problems[0]
    fake(path_of_fakes, "ffmpeg", " A....D libvorbis            libvorbis (codec vorbis)")
    assert tool_check.missing(["audio"], str(font)) == []


def test_another_godot_version_is_a_warning_not_a_refusal(monkeypatch, tmp_path):
    folder = tmp_path / "bin"
    folder.mkdir()
    fake(folder, "my_godot", "4.7.1.stable.official.49a5bc7b6")
    monkeypatch.setenv("GODOT_BIN", str(folder / "my_godot"))
    assert tool_check.missing(["godot"]) == []
    warnings = tool_check.version_warnings(["godot"])
    assert len(warnings) == 1 and "4.7.1" in warnings[0] and "mise install" in warnings[0]
    fake(folder, "my_godot", tool_check.godot_pin() + ".official.49a5bc7b6")
    assert tool_check.version_warnings(["godot"]) == []


def test_another_speech_engine_version_is_a_warning(monkeypatch):
    monkeypatch.setattr(tool_check.transcripts, "check_engine", lambda: None)
    monkeypatch.setattr(tool_check.transcripts, "engine_version_warning", lambda: "faster-whisper 9.9 / ctranslate2 9.9 are installed")
    assert tool_check.missing(["transcripts"]) == []
    assert tool_check.version_warnings(["transcripts"]) == ["speech engine (step transcripts): faster-whisper 9.9 / ctranslate2 9.9 are installed"]


def test_warnings_are_loud_on_stderr(capsys):
    tool_check.warn(["Godot (step godot): tools/godot.sh runs Godot 4.8.beta1"])
    err = capsys.readouterr().err
    assert "WARNING" in err and "4.8.beta1" in err
    tool_check.warn([])
    assert capsys.readouterr().err == ""


def test_no_godot_says_mise_install(monkeypatch, tmp_path):
    monkeypatch.setenv("GODOT_BIN", str(tmp_path / "nothing_here"))
    problems = tool_check.missing(["godot"])
    assert len(problems) == 1 and "mise install" in problems[0]


def test_the_import_refuses_before_writing(monkeypatch, capsys):
    """import_all asks tool_check after the ISO check and before the legacy pack's folder is made."""
    import import_all
    monkeypatch.setattr(import_all.source_files, "check", lambda: None)
    monkeypatch.setattr(import_all.tool_check, "missing", lambda steps, soundfont: ["fluidsynth (step audio): not found"])
    monkeypatch.setattr(import_all.common, "prepare_legacy", lambda: pytest.fail("wrote before the tool check"))
    monkeypatch.setattr(sys, "argv", ["import_all.py", "--only", "audio"])
    assert import_all.main() == 1
    assert "fluidsynth (step audio)" in capsys.readouterr().out


def test_the_import_goes_on_after_a_version_warning(monkeypatch, capsys):
    """A version other than the pinned one is said loudly, and the importer still makes the legacy pack."""
    import import_all

    class Made(Exception):
        pass

    def prepare():
        raise Made
    monkeypatch.setattr(import_all.source_files, "check", lambda: None)
    monkeypatch.setattr(import_all.tool_check, "missing", lambda steps, soundfont: [])
    monkeypatch.setattr(import_all.tool_check, "version_warnings", lambda steps: ["Godot (step godot): runs Godot 4.8.beta1"])
    monkeypatch.setattr(import_all.common, "prepare_legacy", prepare)
    monkeypatch.setattr(sys, "argv", ["import_all.py", "--only", "godot"])
    with pytest.raises(Made):
        import_all.main()
    assert "4.8.beta1" in capsys.readouterr().err


def test_on_windows_each_missing_music_tool_has_its_own_hint(path_of_fakes, tmp_path, monkeypatch):
    monkeypatch.setattr(tool_check, "WINDOWS", True)
    problems = tool_check.missing(["audio"], str(tmp_path / "no.sf2"))
    assert [p.split(" ")[0] for p in problems] == ["ffmpeg", "fluidsynth", "General"]
    assert "Gyan.FFmpeg" in problems[0] and "Gyan.FFmpeg" not in problems[1] + problems[2]
    assert "FluidSynth" in problems[1] and "soundfonts" in problems[2]
