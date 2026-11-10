"""tools/godot.sh runs $GODOT_BIN when it is set, else `godot` on the PATH (mise's), else the Flatpak; run_tests.sh and the importer go
through it, so they follow the same choice. Each test runs the wrapper with a PATH of its own: a folder holding only bash, readlink and
the fakes the test asks for, so the machine's own Godot or Flatpak never answers."""
import os
import shutil
import subprocess
from pathlib import Path

WRAPPER = Path(__file__).resolve().parent / "godot.sh"


def bin_dir(tmp_path, *fakes):
    """A PATH folder with bash and readlink (the wrapper needs them) and a fake for each name in `fakes`, which echoes its name and arguments."""
    folder = tmp_path / "bin"
    folder.mkdir(exist_ok=True)
    for tool in ("bash", "readlink"):
        found = shutil.which(tool)
        assert found, tool
        (folder / tool).symlink_to(found)
    for name in fakes:
        fake = folder / name
        fake.write_text('#!/bin/sh\necho "fake %s: $@"\n' % name)
        fake.chmod(0o755)
    return folder


def run(path, env_extra, *args):
    env = {k: v for k, v in os.environ.items() if k != "GODOT_BIN"}
    env["PATH"] = str(path)
    env.update(env_extra)
    return subprocess.run([str(WRAPPER), *args], capture_output=True, text=True, env=env, check=False)


def test_godot_bin_is_run_with_the_arguments(tmp_path):
    path = bin_dir(tmp_path, "godot", "flatpak", "my_godot")
    done = run(path, {"GODOT_BIN": str(path / "my_godot")}, "--headless", "--path", "godot", "--import")
    assert done.returncode == 0
    assert done.stdout.strip() == "fake my_godot: --headless --path godot --import"


def test_godot_bin_may_be_a_name_on_the_path(tmp_path):
    done = run(bin_dir(tmp_path, "godot", "godot_on_the_path"), {"GODOT_BIN": "godot_on_the_path"}, "--version")
    assert done.stdout.strip() == "fake godot_on_the_path: --version"


def test_without_godot_bin_it_is_godot_on_the_path(tmp_path):
    """mise puts its pinned Godot on the PATH as `godot`: that one wins over the Flatpak."""
    done = run(bin_dir(tmp_path, "godot", "flatpak"), {}, "--headless")
    assert done.stdout.strip() == "fake godot: --headless"


def test_godot_bin_that_is_the_wrapper_itself_is_not_run_twice(tmp_path):
    """gdUnit4's runtest.sh is told `GODOT_BIN=tools/godot.sh`: the wrapper must not call itself for ever. It goes on to the PATH."""
    done = run(bin_dir(tmp_path, "godot"), {"GODOT_BIN": str(WRAPPER)}, "--version")
    assert done.stdout.strip() == "fake godot: --version"


def test_the_wrapper_on_the_path_as_godot_is_skipped(tmp_path):
    path = bin_dir(tmp_path, "flatpak")
    (path / "godot").symlink_to(WRAPPER)
    done = run(path, {}, "--version")
    assert done.stdout.strip() == "fake flatpak: run --command=godot-bin org.godotengine.Godot --version"


def test_without_godot_on_the_path_it_is_the_flatpak(tmp_path):
    done = run(bin_dir(tmp_path, "flatpak"), {}, "--headless")
    assert done.stdout.strip() == "fake flatpak: run --command=godot-bin org.godotengine.Godot --headless"


def test_no_godot_at_all_says_what_to_do(tmp_path):
    done = run(bin_dir(tmp_path), {}, "--version")
    assert done.returncode == 127
    assert "mise install" in done.stderr


def test_a_godot_bin_that_does_not_exist_says_so(tmp_path):
    done = run(bin_dir(tmp_path, "godot"), {"GODOT_BIN": str(tmp_path / "nothing_here")}, "--version")
    assert done.returncode == 127
    assert "GODOT_BIN" in done.stderr and "not an executable" in done.stderr
