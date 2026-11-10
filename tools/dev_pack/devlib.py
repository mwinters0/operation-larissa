"""Shared helpers of the dev pack generator: where the pack is, how a file is written, and the importer modules it borrows.

The dev pack is the developers' own pack (godot/packs/dev, res://packs/dev/): pure developer content, written by this tool from
nothing but the *names* of things (the paths of the original's files, the name registry, the importer's naming code), never from
the content of the original. The generator imports the importer's `tres` writer, its uid rule and its naming code, but never
reads a picture, a size or a number out of the legacy pack.
"""
from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
GODOT = ROOT / "godot"
IMPORT = ROOT / "tools" / "import"
if str(IMPORT) not in sys.path:
    sys.path.insert(0, str(IMPORT))

import import_uids
import tres

DEV_ID = "dev"
DEV = GODOT / "packs" / DEV_ID
DEV_RES = "res://packs/dev/"
LEGACY = GODOT / "packs" / "legacy"
INVENTORY = HERE / "inventory.json"
PROBLEM_ART = HERE / "problem_art.json"
SCRIPTS = "res://src/resources/"
FONT = GODOT / "fonts" / "LiberationSans-Bold.ttf"

# The files the audio builder (audio.py) owns; the generator leaves them alone.
AUDIO_DATA = ("sfx_catalog.tres", "music_catalog.tres", "voice_index.tres", "voice_cues.tres")


class Stats:
    written = 0
    unchanged = 0


def write_bytes(path: Path, data: bytes) -> bool:
    """Write only when the content differs (keeps mtimes, so Godot does not import twice). True if written."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_bytes() == data:
        Stats.unchanged += 1
        return False
    path.write_bytes(data)
    Stats.written += 1
    return True


def write_text(path: Path, text: str) -> bool:
    return write_bytes(path, text.encode("utf-8"))


def res(path: Path | str) -> str:
    """res:// URL of a file of the dev pack (a path under DEV, or a path relative to it)."""
    rel = Path(path).relative_to(DEV) if Path(path).is_absolute() else Path(path)
    return DEV_RES + rel.as_posix()


def uid_of(rel: str) -> str:
    return import_uids.uid_of(DEV_RES + rel)


def tex(t: tres.Tres, rel: str) -> str:
    """ExtResource of a dev picture, with the uid the importer's rule gives its path (the `.import` sidecar holds the same)."""
    return t.ext_ref("Texture2D", DEV_RES + rel, uid_of(rel))


def write_sidecar(png: Path) -> None:
    """The stub `.import` the importer writes beside a picture (never over a sidecar that exists: Godot's completed one stays)."""
    side = png.with_name(png.name + ".import")
    if not side.exists():
        importer, kind = import_uids.IMPORTERS[png.suffix]
        write_text(side, '[remap]\n\nimporter="%s"\ntype="%s"\nuid="%s"\n' % (importer, kind, uid_of(png.relative_to(DEV).as_posix())))


def problem_art() -> list[int]:
    """Per problem type 0-33 the art it draws from (problem_art.json): below 900 a folder `assets/problem_art/bNNN`, from 1000 a loose picture."""
    import json
    return json.loads(PROBLEM_ART.read_text())["art"]
