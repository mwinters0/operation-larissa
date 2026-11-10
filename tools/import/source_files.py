"""The reference release of the game's files, and the check that YOUR copy is that release.

    uv run tools/import/source_files.py            # check NEPTUNE.ISO against the table (import_all.py does this first)
    uv run tools/import/source_files.py --write    # make the table from the image: only to move the reference release

Teaches: an anchor that does not come from the copy it checks (docs/port/FIDELITY.md, "Fixtures commit hashes, not bytes"). The
importer writes every committed hash fixture from YOUR copy of the game, so on its own it would compare a patched
copy with itself and happily write the patched hashes. `source_files.json` is committed and holds the size and SHA-256 of
every file the importer's input is made from, as the reference release has them: the `ONWINCD/` folder of the CD (the
program, the resource DLLs with the pictures, sounds and data, the MIDI files), except the few files listed in IGNORED that
nothing is made from (an empty hall of fame and user list, the setup file and its backup), so a copy that differs only
there is still accepted. The importer checks the table
FIRST and refuses a copy that differs, with the names of the files, before it reads or writes anything. (The CD's
`ASSETS/` and `MOVIES/` folders hold the promotional content of other titles; nothing is made from them.)

The reference is the 1998 Windows CD-ROM release. The check compares the game's files, not the whole image, so every CD
image of that release that has the same files passes (the copies on the Internet Archive do; they differ only outside the
files). A different release, a patched game or a damaged image fails the check. `--write` exists for the day the reference moves to another
release: it overwrites the table with what YOUR copy has, so run it only on purpose and commit the result together with
the hash fixtures the importer then writes anew.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import gamefiles
from common import DIFFERENT_VERSION, sha256_hex

TABLE = Path(__file__).with_name("source_files.json")
FOLDER = "ONWINCD"
## Files of the folder that nothing is made from: they are neither hashed nor compared.
IGNORED = frozenset({"ONWINCD/HALLFAME.DAT", "ONWINCD/ONUSERS.DAT", "ONWINCD/ONWINCD.INI", "ONWINCD/ONWINCD.BAK"})


class DifferentRelease(ValueError):
    """The game's files are not the reference release's (the message says "your copy is a different version or patched")."""


def current(read=gamefiles.read, walk=gamefiles.walk) -> dict[str, dict]:
    """CD path -> {"size", "sha256"} of every file below ONWINCD/ (except IGNORED) of the image `read` / `walk` look at."""
    out = {}
    for path in walk(FOLDER):
        if path in IGNORED:
            continue
        data = read(path)
        out[path] = {"size": len(data), "sha256": sha256_hex(data)}
    return out


def load_table(path: Path = TABLE) -> dict[str, dict]:
    return json.loads(path.read_text())["files"]


def differences(have: dict[str, dict], want: dict[str, dict]) -> list[str]:
    """One line per file that is missing, extra or different; empty when the copy is the reference release."""
    problems = []
    for path in sorted(want):
        if path not in have:
            problems.append("%s is missing" % path)
        elif have[path] != want[path]:
            problems.append("%s differs (%d bytes, sha256 %s...; the reference release has %d bytes, %s...)"
                            % (path, have[path]["size"], have[path]["sha256"][:12], want[path]["size"], want[path]["sha256"][:12]))
    problems += ["%s is not in the reference release" % path for path in sorted(set(have) - set(want))]
    return problems


def check(table: Path = TABLE, read=gamefiles.read, walk=gamefiles.walk) -> None:
    """Raises DifferentRelease unless every file of the image is the reference release's; gamefiles.MissingISO without an image."""
    problems = differences(current(read, walk), load_table(table))
    if problems:
        raise DifferentRelease("%s. %d file%s do%s not match %s: %s"
                               % (DIFFERENT_VERSION, len(problems), "s" if len(problems) != 1 else "",
                                  "" if len(problems) != 1 else "es", table.name, "; ".join(problems)))


def build_table(files: dict[str, dict]) -> str:
    comment = ("The reference release of the game's files: size and SHA-256 of every file below ONWINCD/ of the CD image that the tools read, written "
               "by tools/import/source_files.py --write, never hand-edited. import_all.py checks your NEPTUNE.ISO against it "
               "before anything is read, and refuses a different version or a patched copy. It holds hashes only. See "
               "docs/port/FIDELITY.md, \"Fixtures commit hashes, not bytes\".")
    rows = ",\n".join('  %s: {"size": %d, "sha256": "%s"}' % (json.dumps(path), f["size"], f["sha256"]) for path, f in sorted(files.items()))
    text = '{\n "comment": %s,\n "folder": "%s",\n "files": {\n%s\n }\n}\n' % (json.dumps(comment), FOLDER, rows)
    json.loads(text)
    return text


def main() -> int:
    parser = argparse.ArgumentParser(description="Check NEPTUNE.ISO against the reference release (see the module docstring).")
    parser.add_argument("--write", action="store_true", help="overwrite the table with what your copy has (moves the reference)")
    args = parser.parse_args()
    try:
        if args.write:
            files = current()
            TABLE.write_text(build_table(files))
            print("wrote %s: %d files" % (TABLE, len(files)))
        else:
            check()
            print("your copy is the reference release (%d files)" % len(load_table()))
    except (DifferentRelease, gamefiles.MissingISO) as error:
        print("REFUSED: %s" % error)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
