"""pytest checks of the asset manifest (tools/import/asset_manifest.py): it covers every committed asset and names no
missing file, every source it names is a file of the checked CD (source_files.json) or a script of the importer, each original
resource is the source of one file only, its offsets point at what it says (needs NEPTUNE.ISO), and a second importer run changes
nothing (needs NEPTUNE.ISO and extracted/)."""
import hashlib
import json
import struct
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import asset_manifest as am
import common
import source_files


def files() -> dict[str, dict]:
    return am.load()


def need_iso():
    try:
        source_files.gamefiles.iso_file()
    except source_files.gamefiles.MissingISO as e:
        pytest.skip(str(e))


@pytest.mark.legacy
def test_the_manifest_covers_every_committed_asset_and_names_no_missing_file():
    on_disk, listed = set(am.asset_files()), set(files())
    assert on_disk - listed == set(), "assets with no manifest entry (run the importer): %s" % sorted(on_disk - listed)[:10]
    assert listed - on_disk == set(), "manifest entries without a file: %s" % sorted(listed - on_disk)[:10]
    assert len(listed) == len(on_disk) > 1600


def test_the_file_is_sorted_one_entry_per_line_and_carries_no_bytes():
    text = am.MANIFEST.read_text()
    parsed = json.loads(text)
    assert parsed["format"] == am.FORMAT
    assert text == am.render(parsed["files"])                              # the importer's own layout, nothing hand-edited
    assert list(parsed["files"]) == sorted(parsed["files"])
    for entry in parsed["files"].values():
        assert set(entry) <= set(am.KEY_ORDER)
        assert all(isinstance(v, (int, str, list)) for v in entry.values())


def test_every_entry_names_a_real_source_and_the_fields_its_origin_needs():
    cd = source_files.load_table()
    for path, e in files().items():
        assert e["origin"] in am.ORIGINS, path
        assert e["conversion"], path
        if e["origin"] == "port":
            assert (common.ROOT / e["source"]).is_file(), (path, e["source"])             # the script that writes it
            assert not {"resource", "resources", "offset", "length"} & set(e), path       # nothing original in it
            continue
        assert e["source"] in cd, (path, e["source"])                                      # a file of the checked CD
        if e["origin"] == "original":
            assert isinstance(e["resource"], int) and "resources" not in e, path
            assert e["offset"] % 512 == 0 and e["length"] > 0, path                        # NE resources are 512-byte aligned
            assert e["offset"] + e["length"] <= cd[e["source"]]["size"], path
        elif "resources" in e:
            assert e["conversion"] == "tile_atlas" and 0 < len(e["resources"]) <= 64, path
        else:
            assert e["conversion"] == "midi_ogg" and e["offset"] == 0 and e["length"] == cd[e["source"]]["size"], path
        if e["conversion"] == "pcm_wav":
            assert e["rate"] in (8000, 16000, 22050), path


def test_each_original_resource_is_stored_once():
    """The rule of pictures.py, from the manifest's side: one file per picture id (and per sound)."""
    seen: dict[tuple, str] = {}
    for path, e in files().items():
        if e["origin"] == "original":
            key = (e["source"], e["resource"])
            assert key not in seen, "%s and %s are both %s" % (seen[key], path, key)
            seen[key] = path


def test_the_slot_table_pictures_all_have_a_file():
    pictures = {e["resource"] for e in files().values() if e["origin"] == "original" and e["source"].endswith("NEP256.DLL")}
    for zone in range(7):
        assert set(common.foe_slots(zone)) <= pictures, zone
    for zone in range(5):
        assert set(common.deco_slots(zone)) <= pictures, zone


def test_the_offsets_point_at_the_resources_they_name():
    """Picture resources start with width, height, 'RUND'; sound resources with the format word 0 and the header rate 22050."""
    need_iso()
    by_source: dict[str, list[dict]] = {}
    for e in files().values():
        if e["origin"] == "original":
            by_source.setdefault(e["source"], []).append(e)
    assert set(by_source) == {"ONWINCD/%s.DLL" % n for n in ("NEP256", "NEPBG1", "NEPBG2", "NE0SOUND", "NE1SOUND")}
    for source, entries in by_source.items():
        data = source_files.gamefiles.read(source)
        for e in entries:
            at = e["offset"]
            if "NE0" in source or "NE1" in source:
                assert struct.unpack_from("<II", data, at) == (0, 22050), e
            else:
                assert data[at + 4:at + 8] == b"RUND", e
            assert at + e["length"] <= len(data)


def tree_hash(*folders: Path) -> str:
    h = hashlib.sha256()
    for folder in folders:
        for p in sorted(folder.rglob("*")):
            if p.is_file():
                h.update(str(p).encode())
                h.update(p.read_bytes())
    return h.hexdigest()


@pytest.mark.legacy
def test_a_second_importer_run_changes_nothing():
    """What `git diff godot/` empty means, without git: every file the importer writes is byte for byte what it was."""
    need_iso()
    if not (common.EXTRACTED / "images" / "manifest.json").exists():
        pytest.skip("run tools/extract/run_all.sh first: the importer reads extracted/")
    folders = (common.LEGACY, common.PROJECT_DATA, common.GODOT / "tests" / "fixtures", am.MANIFEST.parent)
    before = tree_hash(*folders)
    done = subprocess.run([sys.executable, str(Path(am.__file__).with_name("import_all.py"))],
                          check=False, capture_output=True, text=True)
    assert done.returncode == 0, done.stdout + done.stderr
    assert "files written: 0," in done.stdout, done.stdout[-400:]
    assert tree_hash(*folders) == before
