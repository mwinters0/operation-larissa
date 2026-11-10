"""pytest checks of reset_tables.py: an edited sprite_meta set, the trigger table, the zones' default levels and a problem type are
put back byte for byte, the other properties of the files are not touched, the result hashes to the committed fixture, and the tool
refuses without the original bytes or with bytes that do not match the hashes. The tests that need the importer-written original
bytes (git-ignored) skip without them."""
import json
import re
import shutil
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import reset_tables as reset
K = reset.KINDS


def _raw_missing(kind) -> bool:
    return not kind.raw_fixture.exists()


def needs_original(*names):
    return pytest.mark.skipif(any(_raw_missing(K[n]) for n in names),
                              reason="run the importer on your copy of the game (needs %s)" % ", ".join(str(K[n].raw_fixture) for n in names))


def _copy(tmp_path: Path, kind, item: str) -> tuple[Path, str]:
    """A copy of the committed file of `item` under tmp_path, laid out like `kind.base`."""
    src = kind.path(item, kind.base)
    dst = kind.path(item, tmp_path)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(src, dst)
    return dst, src.read_text()


def _committed_hashes(kind, item: str) -> tuple:
    """The committed SHA-256 of `item` straight from the hash fixture (no original bytes needed)."""
    fixture = json.loads(kind.hash_fixture.read_text())
    if kind is K["sprite_meta"]:
        tables = next(e["tables"] for e in fixture["sets"] if e["name"] == item)
        return tuple(tables[k]["sha256"] for k in ("widths", "heights", "hit_rects"))
    if kind is K["problems"]:
        return tuple(e["sha256"] for e in fixture["tables"] if e["type"] == int(item))
    return (fixture["sha256"],)


# ---- edits that change every property the tool owns -------------------------------------------------------------

def _edit_sprite_meta(text: str) -> str:
    text = re.sub(r"(sizes = Array\[Vector2i\]\(\[Vector2i\()\d+", r"\g<1>100", text, count=1)
    text = re.sub(r"(hit_rects = Array\[Rect2i\]\(\[Rect2i\()\d+", r"\g<1>40", text, count=1)
    text = re.sub(r"^(hit_rects_flipped = .*)\]\)$", r"\g<1>, Rect2i(0, 0, 2, 2)])", text, count=1, flags=re.MULTILINE)
    text = re.sub(r"^(hit_rects = .*)\]\)$", r"\g<1>, Rect2i(0, 0, 2, 2)])", text, count=1, flags=re.MULTILINE)
    return re.sub(r"^(sizes = .*)\]\)$", r"\g<1>, Vector2i(10, 10)])", text, count=1, flags=re.MULTILINE)       # one sprite too many


def _edit_trigger_table(text: str) -> str:
    return re.sub(r"table = PackedByteArray\((\d+)", lambda m: "table = PackedByteArray(%d" % ((int(m.group(1)) + 1) % 34), text, count=1)


def _edit_zones(text: str) -> str:
    text = re.sub(r"default_edu_level_voyager = \d", "default_edu_level_voyager = 3", text, count=2)
    text = re.sub(r"default_edu_level_expert = \d", "default_edu_level_expert = 0", text, count=1)
    return text.replace('title = "Dragon Reef"', 'title = "My Reef"')


def _edit_problems(text: str) -> str:
    text = re.sub(r"(records = Array\[PackedInt64Array\]\(\[PackedInt64Array\(\d+, )(-?\d+)", lambda m: m.group(1) + str(int(m.group(2)) + 1), text, count=1)
    text = re.sub(r"record_levels = PackedInt32Array\((\d)", lambda m: "record_levels = PackedInt32Array(%d" % ((int(m.group(1)) + 1) % 4), text, count=1)
    return re.sub(r'title = "([^"]*)"', r'title = "Mine \g<1>"', text, count=1)


EDITS = {"sprite_meta": (_edit_sprite_meta, "ink"), "trigger_table": (_edit_trigger_table, "table"),
         "zone_levels": (_edit_zones, "levels"), "problems": (_edit_problems, "6")}


@pytest.mark.legacy
def test_the_committed_files_encode_to_the_committed_hashes():
    """No original bytes needed: the fields of the committed .tres files, encoded again, hash to the fixtures."""
    for kind in K.values():
        for item in kind.items:
            assert kind.hashes(kind.path(item, kind.base).read_text(), item) == _committed_hashes(kind, item), (kind.name, item)


@needs_original("sprite_meta", "trigger_table", "zone_levels", "problems")
def test_every_reset_is_a_no_op_on_the_committed_files():
    for kind in K.values():
        for item, (original, _expected) in kind.load(kind.raw_fixture, kind.hash_fixture).items():
            text = kind.path(item, kind.base).read_text()
            assert kind.patch(text, item, original) == text, (kind.name, item)


@needs_original("sprite_meta", "trigger_table", "zone_levels", "problems")
@pytest.mark.parametrize("name", sorted(EDITS))
def test_an_edited_table_is_restored_byte_for_byte(tmp_path, name):
    kind = K[name]
    edit, item = EDITS[name]
    copy, original_text = _copy(tmp_path, kind, item)
    original, expected = kind.load(kind.raw_fixture, kind.hash_fixture)[item]
    copy.write_text(edit(original_text))
    assert copy.read_text() != original_text
    assert kind.hashes(copy.read_text(), item) != expected
    assert kind.hashes(original_text, item) == expected
    assert reset.reset_item(kind, item, copy, original, expected) is True
    if name == "zone_levels":                       # the title the designer changed is theirs
        assert copy.read_text() == original_text.replace('title = "Dragon Reef"', 'title = "My Reef"')
    elif name == "problems":
        assert copy.read_text() == original_text.replace('title = "', 'title = "Mine ', 1)
    else:
        assert copy.read_text() == original_text
    assert kind.hashes(copy.read_text(), item) == expected
    assert reset.reset_item(kind, item, copy, original, expected) is False


@needs_original("zone_levels")
def test_the_finale_zones_and_the_other_zone_properties_are_not_touched(tmp_path):
    kind = K["zone_levels"]
    copy, text = _copy(tmp_path, kind, "levels")
    zone5 = text.index('index = 5')
    edited = text[:zone5] + text[zone5:].replace("default_edu_level_voyager = 1", "default_edu_level_voyager = 3", 1)
    edited = edited.replace("deco_count = 27", "deco_count = 28")
    assert edited != text
    copy.write_text(edited)
    reset.run("zone_levels", [], base=tmp_path)
    assert copy.read_text() == edited


@needs_original("zone_levels", "sprite_meta", "problems")
def test_a_file_saved_by_godot_without_default_values_is_reset(tmp_path):
    """Godot leaves properties at their default out when it saves; a missing line is inserted where the importer puts it."""
    kind = K["zone_levels"]
    copy, text = _copy(tmp_path, kind, "levels")
    copy.write_text(re.sub(r"^default_edu_level_(voyager|expert) = 0\n", "", text, flags=re.MULTILINE))
    assert copy.read_text() != text
    reset.run("zone_levels", [], base=tmp_path)
    assert copy.read_text() == text
    kind = K["problems"]
    copy, text = _copy(tmp_path, kind, "12")
    copy.write_text(re.sub(r"^levels_available = .*\n", "", text, flags=re.MULTILINE))
    reset.run("problems", ["12"], base=tmp_path)
    assert copy.read_text() == text


@needs_original("sprite_meta", "problems")
def test_records_added_removed_or_with_odd_numbers_are_reset(tmp_path):
    kind = K["problems"]
    copy, text = _copy(tmp_path, kind, "6")
    original, expected = kind.load(kind.raw_fixture, kind.hash_fixture)["6"]
    # type 6 holds fractions with a byte after the denominator and records the designer could drop: both come back
    records_match = re.search(r"records = Array\[PackedInt64Array\]\(\[(.*)\]\)", text)
    assert records_match is not None
    records = records_match.group(1)
    first = records.split("), ")[0] + ")"
    copy.write_text(text.replace(first + ", ", "", 1))
    assert copy.read_text() != text
    reset.reset_item(kind, "6", copy, original, expected)
    assert copy.read_text() == text
    copy.write_text(text.replace("records = Array[PackedInt64Array]([", "records = Array[PackedInt64Array]([%s, " % first, 1))
    reset.reset_item(kind, "6", copy, original, expected)
    assert copy.read_text() == text


@needs_original("sprite_meta")
def test_run_changes_only_the_named_sets(tmp_path):
    kind = K["sprite_meta"]
    for item in ("ink", "zone1"):
        copy, text = _copy(tmp_path, kind, item)
        copy.write_text(_edit_sprite_meta(text))
    reset.run("sprite_meta", ["ink"], base=tmp_path)
    assert kind.path("ink", tmp_path).read_text() == kind.path("ink", kind.base).read_text()
    assert kind.path("zone1", tmp_path).read_text() == _edit_sprite_meta(kind.path("zone1", kind.base).read_text())


@needs_original("trigger_table", "zone_levels", "problems", "sprite_meta")
def test_original_bytes_that_do_not_match_the_committed_hash_are_refused(tmp_path):
    def flip(hex_text: str) -> str:
        return hex_text[:-2] + ("00" if hex_text[-2:] != "00" else "01")

    kind = K["trigger_table"]
    raw = json.loads(kind.raw_fixture.read_text())
    raw["hex"] = flip(raw["hex"])
    patched = tmp_path / "trigger_table.json"
    patched.write_text(json.dumps(raw))
    with pytest.raises(ValueError, match="different version or patched"):
        reset.run("trigger_table", [], base=tmp_path, raw_fixture=patched)
    kind = K["problems"]
    raw = json.loads(kind.raw_fixture.read_text())
    raw["tables"][7]["hex"] = flip(raw["tables"][7]["hex"])
    patched = tmp_path / "problem_tables.json"
    patched.write_text(json.dumps(raw))
    with pytest.raises(ValueError, match="type 1 level 3.*different version or patched"):
        reset.run("problems", ["1"], base=tmp_path, raw_fixture=patched)
    kind = K["sprite_meta"]
    raw = json.loads(kind.raw_fixture.read_text())
    raw["sets"][1]["heights_hex"] = flip(raw["sets"][1]["heights_hex"])
    patched = tmp_path / "sprite_meta.json"
    patched.write_text(json.dumps(raw))
    with pytest.raises(ValueError, match="ink heights.*different version or patched"):
        reset.run("sprite_meta", ["ink"], base=tmp_path, raw_fixture=patched)


def test_missing_original_bytes_say_to_run_the_importer(tmp_path):
    for name, items in (("sprite_meta", ["common"]), ("trigger_table", []), ("zone_levels", []), ("problems", ["3"])):
        with pytest.raises(ValueError, match="run the importer on your copy"):
            reset.run(name, items, base=tmp_path, raw_fixture=tmp_path / "nothing.json")


@needs_original("sprite_meta", "problems")
def test_new_sets_and_types_are_refused():
    with pytest.raises(ValueError, match="no original sprite_meta mine"):
        reset.run("sprite_meta", ["mine"])
    with pytest.raises(ValueError, match="no original problems 34"):
        reset.run("problems", ["34"])


@pytest.mark.legacy
def test_the_hash_of_a_file_with_the_wrong_number_of_values_is_refused():
    text = K["trigger_table"].path("table", K["trigger_table"].base).read_text()
    with pytest.raises(ValueError, match="504 bytes"):
        K["trigger_table"].hashes(re.sub(r"table = PackedByteArray\(\d+, ", "table = PackedByteArray(", text, count=1), "table")
    with pytest.raises(ValueError, match="0 to 3"):
        K["zone_levels"].hashes(K["zone_levels"].path("levels", K["zone_levels"].base).read_text().replace(
            "default_edu_level_expert = 2", "default_edu_level_expert = 9", 1), "levels")
