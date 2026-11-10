"""The game's files, read straight from the CD image (NEPTUNE.ISO). Every tool gets its input through here.

The CD is a plain ISO 9660 image (no Joliet, no Rock Ridge), so names are the DOS 8.3 upper-case ones. Files are
addressed by their path on the CD, with '/' separators and no leading slash, for example:

    gamefiles.read("ONWINCD/NEP.DLL")            # the bytes
    gamefiles.glob("ASSETS/*.GRP")               # ['ASSETS/WS107A.GRP', ...]
    gamefiles.materialize("MOVIES/MV107A.SMK")   # a real file on disk, for programs like ffmpeg

Paths are case-insensitive. The image is found at $NEP_ISO, else NEPTUNE.ISO in the repository root. Nothing is
unpacked to a folder: `read` goes straight into the image; `materialize` copies one file into build/gamefiles/,
a git-ignored cache that is named after the image's size and modification time so another image is never served
stale files.

Needs pycdlib (`uv sync`). A tool that reads the game must go through this module, not through a folder.
"""
import fnmatch
import hashlib
import io
import os
from pathlib import Path

import pycdlib

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "build" / "gamefiles"


class MissingISO(FileNotFoundError):
    pass


def iso_file() -> Path:
    """Where the CD image is: $NEP_ISO, else NEPTUNE.ISO in the repository root."""
    p = Path(os.environ.get("NEP_ISO") or ROOT / "NEPTUNE.ISO")
    if not p.is_file():
        raise MissingISO("%s not found: put your copy of the game at NEPTUNE.ISO or set NEP_ISO" % p)
    return p


def sha256() -> str:
    """SHA-256 of the whole image (hex). A release check can compare this with a known value."""
    h = hashlib.sha256()
    with open(iso_file(), "rb") as f:
        while chunk := f.read(1 << 22):
            h.update(chunk)
    return h.hexdigest()


# --- the directory tree, read once per process --------------------------------------------------------------------

_cd = None          # (PyCdlib, {UPPER-CASE CD path: (CD path, path as the image spells it, is_dir)}), see _open()


def _open():
    global _cd
    if _cd is None:
        iso = pycdlib.PyCdlib()
        iso.open(str(iso_file()))
        index = {}

        def walk(directory):                    # directory = absolute image path such as '/ONWINCD'
            for rec in iso.list_children(iso_path=directory):
                name = rec.file_identifier().decode("ascii")
                if name in (".", ".."):
                    continue
                real = directory.rstrip("/") + "/" + name
                shown = real.split(";")[0][1:]  # CD path without an ISO 9660 version suffix (';1') if the image has one
                index[shown.upper()] = (shown, real, rec.is_dir())
                if rec.is_dir():
                    walk(real)

        walk("/")
        _cd = (iso, index)
    return _cd


def _find(path: str, want_dir: bool):
    key = path.replace("\\", "/").strip("/").upper()
    entry = _open()[1].get(key)
    if entry is None or entry[2] != want_dir:
        raise FileNotFoundError("%s is not on the CD (%s)" % (path, iso_file()))
    return entry


def exists(path: str) -> bool:
    return path.replace("\\", "/").strip("/").upper() in _open()[1]


def read(path: str) -> bytes:
    """The contents of one file on the CD, e.g. read('ONWINCD/NEP.DLL')."""
    iso = _open()[0]
    out = io.BytesIO()
    iso.get_file_from_iso_fp(out, iso_path=_find(path, False)[1])
    return out.getvalue()


def listdir(path: str = "") -> list[str]:
    """Sorted names (files and folders) inside a CD folder; '' is the root of the CD."""
    key = path.replace("\\", "/").strip("/").upper()
    if key:
        _find(key, True)
    names = []
    for k, (shown, _, _) in _open()[1].items():
        if k.rpartition("/")[0] == key:
            names.append(shown.rpartition("/")[2])
    return sorted(names)


def glob(pattern: str) -> list[str]:
    """CD paths of the files matching a pattern whose last part may use * and ?, e.g. 'ASSETS/*.GRP'. Sorted."""
    folder, _, name = pattern.replace("\\", "/").strip("/").rpartition("/")
    if folder:
        folder = _find(folder, True)[0]         # the folder spelled as on the CD
    hits = []
    for entry in listdir(folder):
        path = folder + "/" + entry if folder else entry
        if fnmatch.fnmatch(entry.upper(), name.upper()) and not _open()[1][path.upper()][2]:
            hits.append(path)
    return hits


def walk(folder: str = "") -> list[str]:
    """Every file below a CD folder (the whole CD by default), as sorted CD paths."""
    return sorted(shown for shown, _, is_dir in _open()[1].values()
                  if not is_dir and shown.upper().startswith(folder.strip("/").upper() + "/" if folder else ""))


def materialize(path: str) -> Path:
    """A real file on disk with the contents of a CD file (for ffmpeg, Ghidra, ...). Extracted once, then reused."""
    st = iso_file().stat()
    out = CACHE / ("%d-%d" % (st.st_size, st.st_mtime_ns)) / _find(path, False)[0]
    if not out.exists():
        out.parent.mkdir(parents=True, exist_ok=True)
        tmp = out.with_name(out.name + ".part")
        tmp.write_bytes(read(path))
        tmp.replace(out)
    return out


if __name__ == "__main__":
    import sys
    import utf8_mode
    utf8_mode.ensure()
    usage = "usage: gamefiles.py ls [FOLDER] | read PATH > file | materialize PATH | sha256"
    cmd, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("", [])
    if cmd == "ls":
        print("\n".join(listdir(*args)))
    elif cmd == "read" and len(args) == 1:
        sys.stdout.buffer.write(read(args[0]))
    elif cmd == "materialize" and len(args) == 1:
        print(materialize(args[0]))
    elif cmd == "sha256":
        print(sha256())
    else:
        sys.exit(usage)
