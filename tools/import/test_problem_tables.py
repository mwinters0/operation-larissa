"""pytest checks of problem_tables.py: the 136 stored problem tables decoded to the flat records of problem_type_NN.tres and
encoded again are the original byte for byte (the byte after a fraction's denominator and the authoring leftovers of the
numbers included), the committed hash fixture matches, the committed .tres files hold exactly these records, and what does not fit
is refused. The size rule of the tables is checked against the DLL when there is a CD image."""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common
import problem_tables as pt
import reset_tables
import step_problems

TABLES = [(t, level) for t in range(pt.TYPES) for level in range(pt.LEVELS)]


@pytest.mark.legacy
def test_every_table_decodes_and_encodes_to_the_original_bytes():
    total = 0
    for t, level in TABLES:
        kinds = pt.field_kinds(t)
        raw = pt.original_table(t, level)
        records = pt.decode_table(kinds, raw)
        assert pt.encode_table(kinds, records) == raw, (t, level)
        assert len(raw) % pt.UNIT == 0 and len(raw) == pt.table_size(kinds, raw[0])
        total += len(records)
    assert total == 1276                                    # DESIGN 5.4: the stored problem instances


def test_the_layouts_have_no_gaps_and_every_kind_is_known():
    for t in range(pt.TYPES):
        kinds = pt.field_kinds(t)                           # asserts the gaps itself
        assert set(kinds) <= set("cbwn") and pt.record_size(kinds) == common.load_json(common.DOCS_DATA / "problem_layouts32.json")["types"][str(t)]["record_size"]
    assert "b" in pt.field_kinds(12) and "b" not in pt.field_kinds(11)


@pytest.mark.legacy
def test_the_bytes_the_program_never_reads_are_kept():
    """33 fractions have a non-zero byte after the denominator, 45 numbers are not a decimal or a fraction at all."""
    unread, leftovers = 0, 0
    for t, level in TABLES:
        kinds = pt.field_kinds(t)
        for flat in pt.decode_table(kinds, pt.original_table(t, level)):
            at = 0
            for kind in kinds:
                if kind != "n":
                    at += 1
                    continue
                kind_number, _a, _b, c = flat[at:at + 4]
                unread += kind_number == 1 and c >> 16 != 0
                leftovers += kind_number == 2
                at += 4
    assert (unread, leftovers) == (33, 45)


@pytest.mark.legacy
def test_a_table_with_bytes_after_the_records_or_the_wrong_size_is_refused():
    kinds = pt.field_kinds(2)
    raw = bytearray(pt.original_table(2, 1))
    raw[-1] = 1
    with pytest.raises(ValueError, match="zeros"):
        pt.decode_table(kinds, bytes(raw))
    with pytest.raises(ValueError, match="should be"):
        pt.decode_table(kinds, bytes(raw[:-1]))


def test_what_does_not_fit_is_refused_in_words():
    for kinds, flat, message in (("c", [256], "record 0 field f0: 256 does not fit"), ("b", [128], "128 does not fit"),
                                 ("w", [-1], "-1 does not fit"), ("c", [1, 2], "2 ints"), ("n", [0, 1, 256, 0], "exponent: 256 does not fit"),
                                 ("n", [0, 2 ** 31, 0, 0], "mantissa"), ("n", [0, 1, 0, 1], "fourth int of a decimal"),
                                 ("n", [1, 128, 0, 1], "whole part"), ("n", [1, 0, 0, 256 * 65536], "unread byte"),
                                 ("n", [2, 1, 0, 0], "leftover kind"), ("n", [3, 0, 0, 0], "kind 3 does not exist")):
        with pytest.raises(ValueError, match=message):
            pt.encode_table(kinds, [flat])
    with pytest.raises(ValueError, match="at most 255"):
        pt.encode_table("c", [[1]] * 256)


def test_a_number_is_seven_bytes_and_a_fraction_keeps_its_unread_byte():
    assert pt.encode_number([0, -5, 2, 0]) == bytes([0, 0, 2, 0xfb, 0xff, 0xff, 0xff])         # -0.05
    assert pt.encode_number([1, -6, -2, 3 + 65536 * 0xff]) == bytes([1, 0, 0xfa, 0xfe, 3, 0, 0xff])  # -6 2/3, junk byte 0xff
    assert pt.decode_number(pt.encode_number([2, 0xc4c4, 0x1234, 7])) == [2, 0xc4c4, 0x1234, 7]


@pytest.mark.legacy
def test_the_committed_fixture_holds_the_hashes_and_no_bytes():
    assert pt.HASH_FIXTURE.read_text() == pt.build_hash_fixture()
    fixture = json.loads(pt.HASH_FIXTURE.read_text())
    assert set(fixture) == {"comment", "tables"} and len(fixture["tables"]) == 136
    for entry, (t, level) in zip(fixture["tables"], TABLES):
        raw = pt.original_table(t, level)
        assert entry == {"type": t, "level": level, "source": {"file": "NEP.DLL", "real_id": 10512 + 4 * t + level,
                                                               "extracted": pt.extracted_name(t, level)},
                         "offset": 0, "size": len(raw), "sha256": common.sha256_hex(raw)}
    assert "hex" not in pt.HASH_FIXTURE.read_text()


@pytest.mark.skipif(not pt.RAW_FIXTURE.exists(), reason="run the importer on your copy of the game (needs %s)" % pt.RAW_FIXTURE)
def test_the_raw_fixture_is_the_table_bytes_and_is_not_committed():
    for entry, (t, level) in zip(json.loads(pt.RAW_FIXTURE.read_text())["tables"], TABLES):
        assert (entry["type"], entry["level"]) == (t, level) and bytes.fromhex(entry["hex"]) == pt.original_table(t, level)
    assert "godot/tests/fixtures/original/" in (common.ROOT / ".gitignore").read_text()


@pytest.mark.legacy
def test_the_committed_problem_files_hold_exactly_these_records():
    for t in range(pt.TYPES):
        kinds, records, levels = step_problems.stored_records(t)
        text = (common.PACK_DATA / "problems" / ("problem_type_%02d.tres" % t)).read_text()
        assert reset_tables.Problems.fields(text) == (kinds, records, levels), t


def test_the_table_sizes_are_what_the_dll_holds():
    """The extractor cut the trailing zeros; the size rule (up to a multiple of 512) must give the DLL's own sizes and bytes."""
    try:
        sys.path.insert(0, str(common.ROOT / "tools"))
        sys.path.insert(0, str(common.ROOT / "tools" / "extract"))
        import gamefiles
        from ne import NE
        nep = NE(gamefiles.read("ONWINCD/NEP.DLL"))
    except FileNotFoundError as e:
        pytest.skip("needs the game's CD image (%s)" % e)
    resources = {r[2]: r for r in nep.resources if r[1] == 32515}
    for t, level in TABLES:
        assert nep.get(resources[pt.real_id(t, level)]) == pt.original_table(t, level), (t, level)
