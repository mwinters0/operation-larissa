"""pytest checks of reset_sector_header.py: an edited header (start, neighbours, pieces, stale pieces, unused bytes) is put back
byte for byte, the creatures, screens and script labels are not touched, the result hashes to the committed fixture, and
the tool refuses without the original bytes. The tests that need the importer-written original bytes (git-ignored) skip
without them."""
import json
import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import reset_sector_header as reset
import sector_header
import tres
from common import sector_file

needs_original = pytest.mark.skipif(not sector_header.RAW_FIXTURE.exists(),
                                    reason="run the importer on your copy of the game (needs %s)" % sector_header.RAW_FIXTURE)


def _hash_entries() -> dict[int, str]:
    return {e["index"]: e["header_sha256"] for e in json.loads(sector_header.HASH_FIXTURE.read_text())["sectors"]}


def _copy(tmp_path: Path, n: int) -> tuple[Path, str]:
    original = sector_file(n, "tres").read_text()
    copy = sector_file(n, "tres", tmp_path)
    copy.parent.mkdir(exist_ok=True)
    copy.write_text(original)
    return copy, original


def _edit(text: str) -> str:
    """Changes every kind of header field: start, a neighbour table, a piece, the unused bytes."""
    text = re.sub(r"start_pos = Vector2i\((\d+), ", lambda m: "start_pos = Vector2i(%d, " % (int(m.group(1)) + 2), text, count=1)
    text = re.sub(r"start_frame = \d+", "start_frame = 9", text, count=1)
    text = re.sub(r"neighbors_left = PackedInt32Array\(-?\d+", "neighbors_left = PackedInt32Array(7", text, count=1)
    text = re.sub(r"(\[sub_resource type=\"Resource\" id=\"Piece_2\"\]\nscript = .*\nscreen = )\d+", r"\g<1>11", text, count=1)
    return re.sub(r"header_unused_40 = \d+", "header_unused_40 = 3", text, count=1)


@pytest.mark.legacy
def test_the_committed_sector_files_encode_to_the_committed_hashes():
    """No original bytes needed: the fields of the committed .tres files, encoded again, hash to the fixture."""
    for n, expected in _hash_entries().items():
        assert reset.header_hash(sector_file(n, "tres").read_text()) == expected, n


@needs_original
@pytest.mark.parametrize("n", [0, 6, 22, 31])
def test_an_edited_header_is_restored_byte_for_byte(tmp_path, n):
    copy, original = _copy(tmp_path, n)
    copy.write_text(_edit(original))
    assert copy.read_text() != original
    assert reset.header_hash(copy.read_text()) != _hash_entries()[n]
    raw, expected = reset.load_original_headers()[n]
    assert reset.reset_sector(copy, raw, expected) is True
    assert copy.read_text() == original
    assert reset.header_hash(copy.read_text()) == _hash_entries()[n]
    assert reset.reset_sector(copy, raw, expected) is False


@needs_original
def test_every_reset_is_a_no_op_on_the_committed_files():
    for n, (raw, _expected) in reset.load_original_headers().items():
        old = sector_file(n, "tres").read_text()
        assert reset.patch_text(old, sector_header.decode_header(raw)) == old, n


@needs_original
def test_pieces_added_or_removed_are_reset_and_the_creatures_are_not_touched(tmp_path):
    copy, original = _copy(tmp_path, 6)
    raw, expected = reset.load_original_headers()[6]
    blocks = tres.split_blocks(original)
    foe_blocks = [b for b in blocks if (tres.sub_resource_id(b) or "").startswith("Foe_")]
    pieces = [b for b in blocks if (tres.sub_resource_id(b) or "").startswith("Piece_")]
    assert len(pieces) == 7 and foe_blocks
    # one piece removed (the line and the block), one stale entry added, a creature edited: only the header comes back
    text = original.replace(pieces[-1] + "\n\n", "").replace(', SubResource("Piece_7")', "")
    text = text.replace("stale_pieces = PackedInt32Array(7, 4, 576, 176)", "stale_pieces = PackedInt32Array(1, 2, 3, 4)")
    text = text.replace("pos = Vector2i(312, 92)", "pos = Vector2i(310, 92)", 1)
    assert text != original and "Piece_7" not in text
    copy.write_text(text)
    assert reset.reset_sector(copy, raw, expected) is True
    result = copy.read_text()
    assert "pos = Vector2i(310, 92)" in result and "pos = Vector2i(312, 92)" not in result      # the creature stayed edited
    # (the piece that was removed comes back under the next free id: Piece_7 is not in the file any more)
    assert result.replace("Piece_37", "Piece_7") == original.replace("pos = Vector2i(312, 92)", "pos = Vector2i(310, 92)", 1)
    # an eighth piece added (the original has seven): it goes, the ids of the others stay
    extra = original.replace('SubResource("Piece_7")]', 'SubResource("Piece_7"), SubResource("Piece_99")]').replace(
        "[sub_resource type=\"Resource\" id=\"Foe_8\"]", pieces[-1].replace("Piece_7", "Piece_99") + "\n\n[sub_resource type=\"Resource\" id=\"Foe_8\"]", 1)
    assert "Piece_99" in extra and extra != original
    copy.write_text(extra)
    assert reset.reset_sector(copy, raw, expected) is True
    assert copy.read_text() == original


@needs_original
def test_a_file_saved_by_godot_without_default_values_is_reset(tmp_path):
    """Godot leaves properties at their default out when it saves; a missing line is inserted where the importer puts it."""
    copy, original = _copy(tmp_path, 3)
    raw, expected = reset.load_original_headers()[3]
    text = re.sub(r"^(header_unused_41|neighbors_down) = .*\n", "", original, flags=re.MULTILINE)
    text = text.replace("is_canister = false\n", "")
    assert text != original
    copy.write_text(text)
    reset.reset_sector(copy, raw, expected)
    assert reset.header_hash(copy.read_text()) == expected
    assert copy.read_text().count("neighbors_down") == 1 and copy.read_text().count("is_canister = false") == original.count("is_canister = false")
    assert copy.read_text().splitlines()[-1].startswith("header_unused_41")


@needs_original
def test_run_changes_only_the_named_sectors(tmp_path):
    for n in (1, 2):
        copy, original = _copy(tmp_path, n)
        copy.write_text(_edit(original))
    reset.run([1], sector_dir=tmp_path)
    assert sector_file(1, "tres", tmp_path).read_text() == sector_file(1, "tres").read_text()
    assert sector_file(2, "tres", tmp_path).read_text() == _edit(sector_file(2, "tres").read_text())


@needs_original
def test_the_screens_and_scripts_are_not_touched(tmp_path):
    copy, original = _copy(tmp_path, 4)
    foe = sector_file(4, "foe", tmp_path)
    foe.write_text("; mine\n")
    copy.write_text(_edit(original))
    reset.run([4], sector_dir=tmp_path)
    assert foe.read_text() == "; mine\n"
    assert sorted(p.name for p in tmp_path.rglob("*") if p.is_file()) == ["sector_04.foe", "sector_04.tres"]


@needs_original
def test_original_bytes_that_do_not_match_the_committed_hash_are_refused(tmp_path):
    raw_fixture = json.loads(sector_header.RAW_FIXTURE.read_text())
    raw = raw_fixture["sectors"][5]["header_hex"]
    raw_fixture["sectors"][5]["header_hex"] = raw[:-2] + ("00" if raw[-2:] != "00" else "01")
    patched = tmp_path / "sector_headers.json"
    patched.write_text(json.dumps(raw_fixture))
    with pytest.raises(ValueError, match="different version or patched"):
        reset.load_original_headers(patched)


def test_missing_original_bytes_say_to_run_the_importer(tmp_path):
    with pytest.raises(ValueError, match="run the importer on your copy"):
        reset.load_original_headers(tmp_path / "sector_headers.json")
    with pytest.raises(ValueError, match="run the importer on your copy"):
        reset.run([3], sector_dir=tmp_path, raw_fixture=tmp_path / "sector_headers.json")


def test_new_sectors_are_refused():
    assert "no original header" in reset.refuse_new_sectors([3, 32], list(range(32)))
    assert reset.refuse_new_sectors([3], list(range(32))) == ""
