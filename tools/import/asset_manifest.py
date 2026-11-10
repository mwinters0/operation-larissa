"""The asset manifest: where every file under the legacy pack's assets/ comes from.

    tools/import/asset_manifest.json      written by import_all.py, never by hand

One entry per asset file, keyed by its path below the legacy pack's root ("assets/sprites/foes/foe_035.png"). The importer steps
record an entry whenever they write an asset (`copy_picture`, `copy_sound`, `put_*`), and `import_all.py` writes the file
at the end, so the manifest is made by the code that makes the assets and cannot drift from it. A step that is not run
(`--only`) keeps the entries of the folders it owns. docs/port/ASSET_FORMATS.md explains the fields.

    origin      "original"  the file is one resource of the game's files, converted one to one (PNG, WAV)
                "derived"   made from original data by the port: tile atlases (pictures arranged), music (MIDI rendered)
                "port"      made by the port, no original data in it (drawn tiles, the README and stamp files)
    source      a file of the CD ("ONWINCD/NEP256.DLL", named in source_files.json) or, for "port", the script that writes it
    resource    the resource id inside the source file (for a picture: its picture id; for a sound: the sound id);
                `resources` lists several for a file made of more (an atlas)
    offset      where the resource starts in the source file, `length` its size there (as the file's table stores it)
    bundle      the NEP.DLL bundle (BNDL) the picture belongs to, if it belongs to one
    conversion  how the original bytes became this file (the list is in docs/port/ASSET_FORMATS.md)
    rate        WAV only: the sample rate the game plays the clip at (the clip's own header says 22050)

Offsets and lengths are read from the resource tables of the game's DLLs (the importer has checked the copy of the game
first, source_files.py), so the manifest holds provenance and no original bytes.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import re
import sys
from functools import cache
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import gamefiles
from common import ASSETS, EXTRACTED, LEGACY, ROOT, load_json, manifest, out_copy, out_text, res_path
from source_files import FOLDER, load_table

MANIFEST = Path(__file__).with_name("asset_manifest.json")
FORMAT = 1
ORIGINS = ("original", "derived", "port")
KEY_ORDER = ("origin", "source", "resource", "resources", "offset", "length", "bundle", "conversion", "rate")
# NE resource type of the pictures and sounds (all of them: NE "TYPE32513", see docs/port/ASSET_FORMATS.md).
RESOURCE_TYPE = 32513

_recorded: dict[str, dict] = {}


def key_of(dest: Path) -> str:
    """<the legacy pack>/assets/x.png -> "assets/x.png"."""
    return dest.relative_to(LEGACY).as_posix()


def _put(dest: Path, entry: dict) -> None:
    key = key_of(dest)
    if key in _recorded and _recorded[key] != entry:
        raise ValueError("%s is recorded twice, differently: %s and %s" % (key, _recorded[key], entry))
    _recorded[key] = entry


def reset() -> None:
    _recorded.clear()


def dll_path(dll: str) -> str:
    return "%s/%s.DLL" % (FOLDER, dll)


# ---- recording ---------------------------------------------------------------------------------------------------------

def copy_picture(pid: int, dest: Path, dll: str = "NEP256") -> Path:
    """Copy the extracted PNG of picture `pid` of `dll` (NEP256: sprites and UI; NEPBG1 / NEPBG2: backgrounds) to `dest`."""
    info = manifest()["%s:%d" % (dll, pid)]
    out_copy(EXTRACTED / info["file"], dest)
    entry = {"origin": "original", "source": dll_path(dll), "resource": pid}
    if info.get("bundle") is not None:
        entry["bundle"] = info["bundle"]
    # sprites have the colour key turned into alpha, backgrounds are opaque
    entry["conversion"] = "rund_png_rgba" if info["transparent_index"] is not None else "rund_png_opaque"
    _put(dest, entry)
    return dest


def copy_sound(dll: str, sound: int, dest: Path) -> Path:
    """Copy the extracted WAV of sound `sound` of NE0SOUND / NE1SOUND to `dest`."""
    info = load_json(EXTRACTED / "sounds" / "manifest.json")["%s:%d" % (dll, sound)]
    out_copy(EXTRACTED / info["file"], dest)
    _put(dest, {"origin": "original", "source": dll_path(dll), "resource": sound, "conversion": "pcm_wav", "rate": info["rate"]})
    return dest


def put_atlas(dest: Path, bundle: int, pictures: list[int]) -> None:
    """A tile atlas the tiles step drew out of the pictures of one bundle (the file itself is written by the caller)."""
    _put(dest, {"origin": "derived", "source": dll_path("NEP256"), "resources": list(pictures), "bundle": bundle,
                "conversion": "tile_atlas"})


def put_song(dest: Path, midi_stem: str) -> None:
    """A song rendered from one MIDI file of the CD (the OGG itself is written by step_audio.render_music)."""
    source = "%s/SOUNDS/%s.MID" % (FOLDER, midi_stem.upper())
    _put(dest, {"origin": "derived", "source": source, "offset": 0, "length": load_table()[source]["size"],
                "conversion": "midi_ogg"})


def put_port(dest: Path, script: str, conversion: str) -> None:
    """A file the port itself makes (nothing original in it): `script` is the importer file that writes it."""
    assert (ROOT / script).is_file(), script
    _put(dest, {"origin": "port", "source": script, "conversion": conversion})


# ---- stale files ---------------------------------------------------------------------------------------------------------

def _number_of(path: Path) -> str:
    """The last run of digits of a file name: the original's number in `lock_tick_38.wav` and in `sfx_38.wav`."""
    found = re.findall(r"[0-9]+", path.stem)
    return found[-1] if found else ""


def prune(dirs: list[Path]) -> tuple[int, int]:
    """Removes the files of `dirs` (asset folders of steps that ran) that this run did not write: what the steps leave behind
    when a file gets another name (a picture or sound that was named, `asset_names.py`) or stops existing. A file of the
    folders is either recorded by a step or stale, so afterwards the folders hold exactly the manifest's files.

    Godot's import file (`<file>.import`, which holds the file's uid and import settings) moves with its asset: when a stale
    file and a new one without a sidecar have the same bytes, the sidecar is carried over (Godot then reimports the new file
    and keeps the uid). Sidecars of files that are gone are deleted, and so are folders that are left empty.
    Returns (stale files removed, sidecars carried over)."""
    stale: dict[Path, str] = {}
    for d in dirs:
        for p in sorted(d.rglob("*")) if d.exists() else []:
            if p.is_file() and p.suffix != ".import" and key_of(p) not in _recorded:
                stale[p] = hashlib.sha256(p.read_bytes()).hexdigest()
    carriers: dict[str, list[Path]] = {}
    for p, digest in stale.items():
        if Path(str(p) + ".import").exists():
            carriers.setdefault(digest, []).append(p)
    carried = 0
    for key in sorted(_recorded):
        new = LEGACY / key
        sidecar = Path(str(new) + ".import")
        if sidecar.exists() or not new.exists() or not any(new.is_relative_to(d) for d in dirs):
            continue
        waiting = carriers.get(hashlib.sha256(new.read_bytes()).hexdigest())
        if waiting:
            # (files with the same bytes, the twin sounds: the one with the same number first, so the uids stay with their numbers)
            same_number = [p for p in waiting if _number_of(p) == _number_of(new)]
            old = (same_number or waiting)[0]
            waiting.remove(old)
            old_sidecar = Path(str(old) + ".import")
            sidecar.write_text(old_sidecar.read_text().replace(old.name, new.name).replace(res_path(old), res_path(new)))
            old_sidecar.unlink()
            carried += 1
    for p in stale:
        p.unlink()
        Path(str(p) + ".import").unlink(missing_ok=True)
    for d in dirs:
        for p in sorted(d.rglob("*.import")) if d.exists() else []:
            if not Path(str(p)[:-len(".import")]).exists():
                p.unlink()
        for sub in sorted((q for q in d.rglob("*") if q.is_dir()), reverse=True) if d.exists() else []:
            if not any(sub.iterdir()):
                sub.rmdir()
    return len(stale), carried


# ---- resolving offsets -------------------------------------------------------------------------------------------------

@cache
def _ne_class():
    """tools/extract/ne.py (the reader the extractors use), loaded by path: tools/analysis has another module of that name."""
    path = ROOT / "tools" / "extract" / "ne.py"
    spec = importlib.util.spec_from_file_location("extract_ne", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.NE


@cache
def resource_table(source: str) -> dict[int, tuple[int, int]]:
    """Resource id -> (offset, length) of the type-32513 resources of a DLL of the CD."""
    ne = _ne_class()(gamefiles.read(source))
    return {r[2]: (r[3], r[4]) for r in ne.resources if r[1] == RESOURCE_TYPE and isinstance(r[2], int)}


def _resolved(entry: dict) -> dict:
    out = dict(entry)
    if entry["origin"] == "original":
        out["offset"], out["length"] = resource_table(entry["source"])[entry["resource"]]
    return {k: out[k] for k in KEY_ORDER if k in out}


# ---- the file ----------------------------------------------------------------------------------------------------------

COMMENT = ("Where each file under the legacy pack's assets/ comes from: source file (named in source_files.json) or generating script, "
           "resource id, offset, conversion. Written by import_all.py (tools/import/asset_manifest.py), never by hand; "
           "docs/port/ASSET_FORMATS.md explains the fields. It holds provenance only, no original bytes.")


def load(path: Path = MANIFEST) -> dict[str, dict]:
    return json.loads(path.read_text())["files"]


def render(files: dict[str, dict]) -> str:
    rows = ",\n".join("  %s: %s" % (json.dumps(k), json.dumps(files[k], separators=(", ", ": "))) for k in sorted(files))
    return '{\n "comment": %s,\n "format": %d,\n "files": {\n%s\n }\n}\n' % (json.dumps(COMMENT), FORMAT, rows)


def write(owned_dirs: list[Path] | None = None) -> int:
    """Write the manifest from what the steps recorded; returns the number of entries.

    `owned_dirs`: after a partial run (import_all.py --only) the asset folders of the steps that ran; the entries below
    them are replaced, all others are kept from the old file. None = a full run: the recorded entries are the manifest."""
    files = {}
    if owned_dirs is not None and MANIFEST.exists():
        prefixes = tuple(key_of(d) + "/" for d in owned_dirs)
        files = {k: v for k, v in load().items() if not k.startswith(prefixes)}
    files.update({k: _resolved(v) for k, v in _recorded.items()})
    out_text(MANIFEST, render(files))
    return len(files)


def asset_files() -> list[str]:
    """Every file under the legacy pack's assets/ that the manifest has to cover (not Godot's .import sidecars)."""
    return sorted(key_of(p) for p in ASSETS.rglob("*") if p.is_file() and p.suffix != ".import")
