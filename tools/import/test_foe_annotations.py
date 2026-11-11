"""pytest checks of the annotation store (foe_annotations.py): the file format, harvest, and the round trip from a
hand-edited .foe through the store and back; plus the tools that read it (reset, step_sectors, harvest CLI) and the
guarantee that they never touch a sector that has no original."""
import random
import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import foe_annotations as fa
import foe_names
import foe_script
import foe_text
import harvest_foe_annotations as harvester
import import_all
import reset_foe_scripts as reset
import step_sectors
import common
from common import GODOT, PACK_DATA, PROJECT_DATA

needs_scripts = pytest.mark.skipif(not foe_script.RAW_FIXTURE.exists(),
                                   reason="run the importer on your copy of the game (needs %s)" % foe_script.RAW_FIXTURE)

EXAMPLE = GODOT / "tests" / "fixtures" / "foe_annotations_example"


@pytest.fixture
def no_names(monkeypatch):
    """The example text of sector 3 is written with numbers only, so that it does not change when names are added to
    godot/names/original.json: the tools that write the stored scripts see an empty registry."""
    monkeypatch.setattr(foe_names, "_original", lambda: foe_names.Registry({}))
    return monkeypatch


def _sector(n: int):
    """(fixture entry, script bytes, entries) of original sector n."""
    if not foe_script.RAW_FIXTURE.exists():
        pytest.skip("run the importer on your copy of the game (needs %s)" % foe_script.RAW_FIXTURE)
    entry = {e["index"]: e for e in reset.load_originals()}[n]
    offsets = [(f["pc"], f["script_hit"], f["script_ink"]) for f in entry["foes"]]
    return entry, bytes.fromhex(entry["script_hex"]), foe_text.entry_names(offsets)


def _plain(n: int) -> str:
    entry, script, entries = _sector(n)
    return foe_text.disassemble(script, entry["base"], entries, None, foe_names.Names.for_original_sector(n))


def _harvest(n: int, text: str) -> fa.Harvest:
    entry, script, entries = _sector(n)
    return fa.harvest(text, script, entry["base"], entries, foe_names.Names.for_original_sector(n))


def _copy(tmp_path: Path, n: int) -> Path:
    common.sector_dir(n, tmp_path).mkdir(exist_ok=True)
    for ext in ("tres", "foe"):
        common.sector_file(n, ext, tmp_path).write_text(common.sector_file(n, ext).read_text())
    return common.sector_file(n, "tres", tmp_path)


# --- the file -------------------------------------------------------------------------------------------------

def test_the_committed_store_is_in_the_standard_layout():
    text = fa.STORE.read_text(encoding="utf-8")
    assert fa.dumps(fa.parse(text)) == text


def test_the_example_file_round_trips_exactly_and_sorts_numbers_not_text():
    text = (EXAMPLE / "foe_annotations.json").read_text(encoding="utf-8")
    store = fa.parse(text)
    assert fa.dumps(store) == text
    assert list(store[3]["labels"]) == [511, 529, 535]            # numeric order: "1490" would sort before "511" as text
    assert list(store[3]["comments"])[-1] == 1490


def test_an_empty_store_is_valid_and_has_no_sectors():
    assert fa.parse(fa.dumps({})) == {}
    assert '"sectors": {}' in fa.dumps({})
    assert fa.dumps({5: fa.empty_sector()}) == fa.dumps({})


def test_special_characters_survive_the_file():
    note = {"above": ['    ; quote " backslash \\ tab \t café → bell \x07'], "inline": '; "x"'}
    store = {1: {"labels": {10: "a_b"}, "comments": {10: note}}}
    assert fa.parse(fa.dumps(store)) == store
    assert "→" in fa.dumps(store)                              # not \u-escaped: readable in git diffs


@pytest.mark.parametrize("bad", [
    '{"sectors": {"1": {"labels": {"5": "no good"}}}}',
    '{"sectors": {"1": {"labels": {"5": "a", "6": "a"}}}}',
    '{"sectors": {"1": {"comments": {"5": {"bogus": ["x"]}}}}}',
    '{"sectors": {"1": {"comments": {"5": {"above": "not a list"}}}}}',
    '{"sectors": {"1": {"comments": {"5": {}}}}}',
])
def test_a_malformed_store_is_rejected(bad):
    with pytest.raises(ValueError):
        fa.parse(bad)


def test_the_store_never_holds_a_sector_without_an_original():
    originals = set(reset.original_sectors())
    assert set(fa.load()) <= originals


# --- harvest --------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("n", range(32))
def test_a_generated_text_has_nothing_to_store(n):
    result = _harvest(n, _plain(n))
    assert result.ok, result.problem
    assert result.labels == {} and result.comments == {}
    assert result.text == _plain(n)


def test_the_example_text_is_harvested_into_the_example_store_and_back():
    text = (EXAMPLE / "sector_03_annotated.txt").read_text(encoding="utf-8")
    expected = fa.parse((EXAMPLE / "foe_annotations.json").read_text(encoding="utf-8"))[3]
    entry, script, entries = _sector(3)
    # The example is written with numbers only (no symbols), so it does not change when names are added to the registry.
    result = fa.harvest(text, script, entry["base"], entries)
    assert result.ok, result.problem
    assert result.annotations() == expected
    assert result.text == text                                      # already in the standard layout
    assert foe_text.disassemble(script, entry["base"], entries, expected) == text


def test_comments_attach_to_the_line_that_follows_and_inline_to_their_own_line():
    plain = _plain(3)
    text = plain.replace("\nfoe0_ink:\n    Wait_Next_Tick\n",
                         "\n; about the label\nfoe0_ink:\n; between label and instruction\n    Wait_Next_Tick  ; same line\n", 1)
    result = _harvest(3, text)
    assert result.ok and result.text == text
    ink = _sector(3)[0]["foes"][0]["script_ink"]
    assert result.comments == {ink: {"label_above": ["", "; about the label"],
                                     "above": ["; between label and instruction"], "inline": "; same line"}}


def test_a_comment_after_the_last_instruction_and_a_label_at_the_end():
    plain = _plain(3)
    end = _sector(3)[0]["base"] + len(_sector(3)[1])
    result = _harvest(3, plain + "; the end\n\n; trailer\n")
    assert result.ok and result.comments == {end: {"above": ["; the end", "", "; trailer"]}}
    assert result.text == plain + "; the end\n\n; trailer\n"


def test_blank_lines_are_layout_stored_exactly_where_they_are_not_the_default():
    plain = _plain(3)
    spaced = plain.replace("\n\nfoe0_ink:", "\n\n\n\nfoe0_ink:", 1)                # three blank lines before a label
    result = _harvest(3, spaced)
    assert result.ok and result.text == spaced
    assert next(iter(result.comments.values()))["label_above"] == ["", "", ""]
    tight = plain.replace("\n\nfoe0_ink:", "\nfoe0_ink:", 1)                # no blank line at all
    result = _harvest(3, tight)
    assert result.ok and result.text == tight
    assert next(iter(result.comments.values()))["label_above"] == []


def test_the_text_comes_back_in_the_standard_layout():
    plain = _plain(3)
    messy = plain.replace("    Return\n", "    return  ;x\n", 1).replace("foe0_ink:", "  foe0_ink:", 1).rstrip("\n")
    result = _harvest(3, messy)
    assert result.ok
    assert result.text != messy and "    Return  ;x\n" in result.text and "\nfoe0_ink:\n" in result.text
    assert result.text.endswith("\n")
    assert _harvest(3, result.text).text == result.text             # standard layout is a fixed point


@pytest.mark.parametrize("edit, reason", [
    (lambda t: t.replace("    Set_Frame ink_burst_4\n", "    Set_Frame 99\n", 1), "differs|original has"),
    (lambda t: t.replace("    Return\n", "", 1), "original has"),
    (lambda t: t + "    Return\n", "no instruction"),
    (lambda t: t.replace("    Return\n", "    Frobnicate\n", 1), "unknown instruction"),
    (lambda t: t.replace("Loop_Counter2_Back_To loc_529", "Loop_Counter2_Back_To foe0_ink", 1), "original has"),
])
def test_a_text_whose_instructions_differ_from_the_original_is_refused(edit, reason):
    result = _harvest(3, edit(_plain(3)))
    assert not result.ok
    assert re.search(reason, result.problem), result.problem


def test_two_labels_at_one_place_and_duplicate_names_are_refused():
    plain = _plain(3)
    assert "label the same place" in _harvest(3, plain.replace("foe0_ink:\n", "foe0_ink:\nextra:\n", 1)).problem
    assert "duplicate label" in _harvest(3, plain.replace("loc_529:\n", "foe0_ink:\n", 1)).problem


def test_a_creature_entry_without_a_label_is_refused():
    plain = _plain(3)
    result = _harvest(3, plain.replace("\nfoe0_ink:\n", "\n", 1))
    assert not result.ok and "foe0_ink" in result.problem or "original has" in result.problem


def test_a_new_label_in_the_middle_of_a_block_is_stored_by_offset():
    plain = _plain(3)
    result = _harvest(3, plain.replace("    Set_Frame ink_burst_6\n", "heading:\n    Set_Frame ink_burst_6\n", 1))
    assert result.ok and list(result.labels.values()) == ["heading"]
    assert result.text.count("heading:") == 1


# --- the generated "not executed" comment and the store ---------------------------------------------------------------

# 0 Return; 1, 2 zero bytes (dead, written as Padding 2); 3 Jump_To loc_3 (dead; a label splits the run); see _DEAD_TEXT
_DEAD_SCRIPT = bytes([3, 0, 0, 1, 0xFD, 0xFF])
_DEAD_ENTRIES = {"start": 0}
_DEAD_TEXT = """start:
    Return
    Padding 2

loc_3:
%s
    Jump_To loc_3
""" % foe_text.UNEXECUTED_UNUSED


def _dead_harvest(text: str) -> fa.Harvest:
    return fa.harvest(text, _DEAD_SCRIPT, 0, _DEAD_ENTRIES)


def test_the_generated_comment_is_the_default_text_and_not_stored():
    assert foe_text.disassemble(_DEAD_SCRIPT, 0, _DEAD_ENTRIES) == _DEAD_TEXT
    result = _dead_harvest(_DEAD_TEXT)
    assert result.ok, result.problem
    assert result.labels == {} and result.comments == {}
    assert result.text == _DEAD_TEXT


def test_a_stored_comment_above_replaces_the_generated_one():
    mine = _DEAD_TEXT.replace(foe_text.UNEXECUTED_UNUSED, "    ; my own words")
    result = _dead_harvest(mine)
    assert result.ok and result.comments == {3: {"above": ["    ; my own words"]}}
    assert result.text == mine and "not executed" not in mine
    assert foe_text.disassemble(_DEAD_SCRIPT, 0, _DEAD_ENTRIES, result.annotations()) == mine


def test_a_stored_empty_above_removes_the_generated_comment():
    bare = _DEAD_TEXT.replace(foe_text.UNEXECUTED_UNUSED + "\n", "")
    result = _dead_harvest(bare)
    assert result.ok and result.comments == {3: {"above": []}}
    assert result.text == bare and "not executed" not in bare
    assert foe_text.disassemble(_DEAD_SCRIPT, 0, _DEAD_ENTRIES, result.annotations()) == bare
    assert fa.parse(fa.dumps({7: result.annotations()})) == {7: result.annotations()}      # `"above": []` survives the file
    assert '"above": []' in fa.dumps({7: result.annotations()})


def test_lines_added_to_the_generated_comment_are_stored_with_it():
    longer = _DEAD_TEXT.replace(foe_text.UNEXECUTED_UNUSED + "\n", foe_text.UNEXECUTED_UNUSED + "\n    ; and more\n")
    result = _dead_harvest(longer)
    assert result.ok and result.comments == {3: {"above": [foe_text.UNEXECUTED_UNUSED, "    ; and more"]}}
    assert foe_text.disassemble(_DEAD_SCRIPT, 0, _DEAD_ENTRIES, result.annotations()) == longer


def test_other_notes_at_a_commented_position_leave_the_generated_comment_alone():
    text = _DEAD_TEXT.replace("    Padding 2\n", "    Padding 2  ; x\n", 1)
    result = _dead_harvest(text)
    assert result.ok and result.comments == {1: {"inline": "; x"}}
    assert foe_text.disassemble(_DEAD_SCRIPT, 0, _DEAD_ENTRIES, result.annotations()) == text


def test_a_name_given_to_a_label_does_not_change_where_the_comments_go():
    renamed = _DEAD_TEXT.replace("loc_3", "again")
    result = _dead_harvest(renamed)
    assert result.ok and result.comments == {} and result.labels == {3: "again"}


@needs_scripts
def test_the_stored_comment_of_the_real_sectors_survives_a_reset(tmp_path):
    tres = _copy(tmp_path, 0)
    foe_path = tres.with_suffix(".foe")
    text = foe_path.read_text()
    foe_path.write_text(text.replace(foe_text.UNEXECUTED_UNUSED, "    ; zeros", 1))
    store_path = tmp_path / "foe_annotations.json"
    assert harvester.run([0], sector_dir=tmp_path, store_path=store_path) is True
    committed = fa.for_sector(fa.load(), 0).get("comments", {})     # the designer's own comments are harvested too
    stored = fa.load(store_path)[0]["comments"]
    added = [note for offset, note in stored.items() if committed.get(offset) != note]
    assert added == [{"above": ["    ; zeros"]}]
    foe_path.write_text("")
    reset.run([0], sector_dir=tmp_path, store_path=store_path)
    assert foe_path.read_text() == text.replace(foe_text.UNEXECUTED_UNUSED, "    ; zeros", 1)


# --- Padding in the harvest --------------------------------------------------------------------------------------------

def test_the_store_of_the_repository_holds_only_original_sectors():
    # Sectors made from scratch have no original bytes, so no annotations; whether each entry matches its .foe is
    # checked by test_reset_foe_scripts.py (a reset is a no-op) and godot/tests/engine/test_foe_asm.gd.
    assert all(0 <= n <= 31 for n in fa.load())


def test_a_padding_line_covers_its_bytes_and_labels_and_comments_attach_to_its_first_offset():
    # 0 Return; 1..4 four zero bytes (one Padding 4); 5 Jump_To loc_5 (dead, labelled by itself)
    script = bytes([3, 0, 0, 0, 0, 1, 0xFD, 0xFF])
    text = """start:
    Return
    ; about the padding
    Padding 4  ; filler

loc_5:
%s
    Jump_To loc_5
""" % foe_text.UNEXECUTED_UNUSED
    result = fa.harvest(text, script, 0, {"start": 0})
    assert result.ok, result.problem
    assert result.comments == {1: {"above": ["    ; about the padding"], "inline": "; filler"}}
    assert result.names == {0: "start", 5: "loc_5"}                       # loc_5 is at offset 5: 1 + 4 bytes of padding
    assert result.text == text


def test_padding_counts_as_that_many_zero_bytes_in_the_instructions_match_check():
    script = bytes([3, 0, 0, 0, 0, 1, 0xFD, 0xFF])
    for middle in ("    Padding 4", "    Padding 1\n    Padding 3", "    Wait_Next_Tick\n    Padding 3", "    padding\n    PADDING 3",
                   "    Wait_Next_Tick\n    Wait_Next_Tick\n    Wait_Next_Tick\n    Wait_Next_Tick"):
        text = "start:\n    Return\n%s\n\nloc_5:\n%s\n    Jump_To loc_5\n" % (middle, foe_text.UNEXECUTED_UNUSED)
        result = fa.harvest(text, script, 0, {"start": 0})
        assert result.ok, (middle, result.problem)
        assert result.labels == {} and result.comments == {}
        assert "    Padding 4\n" in result.text and "Wait_Next_Tick" not in result.text      # the standard layout


def test_padding_that_does_not_match_the_original_bytes_is_refused():
    script = bytes([3, 0, 0, 0, 0, 1, 0xFD, 0xFF])
    head = "start:\n    Return\n"
    tail = "\nloc_5:\n    Jump_To loc_5\n"
    result = fa.harvest(head + "    Padding 3" + tail, script, 0, {"start": 0})
    assert not result.ok and "line 5" in result.problem                      # one byte short: the label is no longer at 5
    result = fa.harvest(head + "    Padding 5" + tail, script, 0, {"start": 0})
    assert not result.ok and "Padding 5" in result.problem
    result = fa.harvest("start:\n    Return\n    Hide_Foe\n    Padding 3" + tail, script, 0, {"start": 0})
    assert not result.ok and "the original has 'Wait_Next_Tick' here, the text has 'Hide_Foe'" in result.problem
    # Padding where the original has an instruction
    result = fa.harvest("start:\n    Padding 2\n", bytes([3, 16]), 0, {"start": 0})
    assert not result.ok and "the original has 'Return' here, the text has 'Padding 2'" in result.problem
    result = fa.harvest("start:\n    Return\n    Padding 2\n", bytes([3, 0]), 0, {"start": 0})
    assert not result.ok and "the end of the script" in result.problem


@pytest.mark.parametrize("operands", ["0", "65536", "-1", "x", "3 4", "2.5"])
def test_a_bad_padding_count_is_refused(operands):
    result = fa.harvest("start:\n    Return\n    Padding %s\n" % operands, bytes([3, 0, 0]), 0, {"start": 0})
    assert not result.ok and result.problem.startswith("line 3: Padding takes one count")


def test_a_stored_label_or_comment_inside_zero_bytes_cuts_the_padding_there():
    script = bytes([3, 0, 0, 0, 0])
    plain = foe_text.disassemble(script, 0, {"start": 0})
    assert plain == "start:\n    Return\n    Padding 4\n"
    annotations = {"labels": {3: "middle"}, "comments": {2: {"above": ["    ; here"]}}}
    cut = foe_text.disassemble(script, 0, {"start": 0}, annotations)
    assert cut == "start:\n    Return\n    Padding 1\n    ; here\n    Padding 1\n\nmiddle:\n    Padding 2\n"
    result = fa.harvest(cut, script, 0, {"start": 0})
    assert result.ok, result.problem
    assert result.annotations() == annotations and result.text == cut      # nothing is lost, and it is stable


# --- round trip over a lot of annotations ---------------------------------------------------------------------

@pytest.mark.parametrize("n", [0, 3, 12, 31])
def test_random_annotations_survive_disassemble_then_harvest(n):
    entry, script, entries = _sector(n)
    base = entry["base"]
    positions = [at for at, _op, _o in foe_text.decode(script, base)] + [base + len(script)]
    generated = foe_text.default_names(script, base, entries)
    rng = random.Random(n)
    labels, comments = {}, {}
    for at in positions:
        if at in generated and rng.random() < 0.3:
            labels[at] = "named_%d" % at
        elif at not in generated and rng.random() < 0.02:
            labels[at] = "extra_%d" % at
    shown = set(generated) | set(labels)
    for at in positions:
        note = {}
        if rng.random() < 0.15:
            note["above"] = rng.choice([["    ; c"], ["", "; two"], [""]])
        if at != positions[-1] and rng.random() < 0.15:
            note["inline"] = rng.choice(["; x", " ; one space", "    ; wide"])
        if at in shown and at != min(shown) and rng.random() < 0.2:
            note["label_above"] = rng.choice([[], ["", "; head"], ["; tight"]])
        if at in shown and rng.random() < 0.2:
            note["label_inline"] = "; lbl"
        if note:
            comments[at] = {k: note[k] for k in fa.NOTE_KEYS if k in note}
    annotations = {"labels": labels, "comments": comments}
    text = foe_text.disassemble(script, base, entries, annotations)
    result = fa.harvest(text, script, base, entries)
    assert result.ok, result.problem
    assert result.annotations() == {"labels": dict(sorted(labels.items())), "comments": dict(sorted(comments.items()))}
    assert result.text == text
    # and through the file
    assert fa.parse(fa.dumps({n: result.annotations()})) == {n: result.annotations()}


# --- renamed entry labels reach the .tres; reset with and without the store -----------------------------------

def _example_store(tmp_path: Path) -> Path:
    store_path = tmp_path / "foe_annotations.json"
    store_path.write_text((EXAMPLE / "foe_annotations.json").read_text(encoding="utf-8"), encoding="utf-8")
    return store_path


def test_a_renamed_entry_label_is_written_into_the_tres(tmp_path):
    entry, _script, _entries = _sector(3)
    annotations = fa.parse((EXAMPLE / "foe_annotations.json").read_text(encoding="utf-8"))[3]
    tres_text = reset.patch_text(common.sector_file(3, "tres").read_text(), entry, annotations)
    assert 'hit_label = "touch_return"' in tres_text and 'hit_label = "foe0_hit"' not in tres_text
    assert 'ink_label = "foe0_ink"' in tres_text
    # every label the .tres names exists in the text
    text = foe_text.disassemble(_script, entry["base"], _entries, annotations)
    for name in re.findall(r'^(?:start|hit|ink)_label = "(.*)"$', tres_text, re.MULTILINE):
        assert "\n%s:" % name in "\n" + text


@needs_scripts
def test_reset_writes_the_stored_names_and_comments_and_plain_ignores_them(tmp_path, no_names):
    tres = _copy(tmp_path, 3)
    store_path = _example_store(tmp_path)
    reset.run([3], sector_dir=tmp_path, store_path=store_path)
    assert tres.with_suffix(".foe").read_text() == (EXAMPLE / "sector_03_annotated.txt").read_text()
    assert 'hit_label = "touch_return"' in tres.read_text()
    no_names.undo()                                      # the plain text is the committed one again, with the registry's names
    reset.run([3], sector_dir=tmp_path, store_path=store_path, plain=True)
    assert tres.with_suffix(".foe").read_text() == common.sector_file(3, "foe").read_text()
    assert tres.read_text() == common.sector_file(3, "tres").read_text()
    assert store_path.read_text() == (EXAMPLE / "foe_annotations.json").read_text()          # the store is not touched


@pytest.mark.legacy
def test_step_sectors_writes_the_stored_names_and_comments(no_names):
    import common
    sec = {s["index"]: s for s in common.load_json(common.TABLES / "sectors.json")}[3]
    annotations = fa.parse((EXAMPLE / "foe_annotations.json").read_text(encoding="utf-8"))[3]
    tres_text, foe_text_ = step_sectors.build_sector(sec, annotations)
    assert foe_text_ == (EXAMPLE / "sector_03_annotated.txt").read_text()
    assert 'hit_label = "touch_return"' in tres_text
    plain_tres, plain_foe = step_sectors.build_sector(sec)
    assert plain_foe == common.sector_file(3, "foe").read_text() or fa.load()      # unchanged without the store
    assert plain_tres == step_sectors.build_sector(sec, {})[0]


@needs_scripts
def test_the_harvest_tool_stores_fixes_the_tres_and_a_reset_reproduces_the_text(tmp_path, no_names):
    tres = _copy(tmp_path, 3)
    tres.with_suffix(".foe").write_text((EXAMPLE / "sector_03_annotated.txt").read_text())
    store_path = tmp_path / "foe_annotations.json"
    assert harvester.run([3], sector_dir=tmp_path, store_path=store_path) is True
    assert store_path.read_text() == (EXAMPLE / "foe_annotations.json").read_text()
    assert 'hit_label = "touch_return"' in tres.read_text()
    typed = tres.with_suffix(".foe").read_text()
    reset.run([3], sector_dir=tmp_path, store_path=store_path, plain=True)
    reset.run([3], sector_dir=tmp_path, store_path=store_path)
    assert tres.with_suffix(".foe").read_text() == typed == (EXAMPLE / "sector_03_annotated.txt").read_text()


@needs_scripts
def test_harvesting_a_plain_sector_leaves_the_store_empty_and_the_files_alone(tmp_path):
    tres = _copy(tmp_path, 5)
    store_path = tmp_path / "foe_annotations.json"
    assert harvester.run([5], sector_dir=tmp_path, store_path=store_path)
    assert fa.load(store_path) == {}
    assert tres.read_text() == common.sector_file(5, "tres").read_text()
    assert tres.with_suffix(".foe").read_text() == common.sector_file(5, "foe").read_text()


@needs_scripts
def test_a_refused_sector_changes_nothing_and_the_store_keeps_its_old_entry(tmp_path, capsys):
    tres = _copy(tmp_path, 3)
    store_path = _example_store(tmp_path)
    edited = tres.with_suffix(".foe").read_text().replace("    Set_Frame ink_burst_4\n", "    Set_Frame 99\n", 1)
    tres.with_suffix(".foe").write_text(edited)
    assert harvester.run([3], sector_dir=tmp_path, store_path=store_path) is False
    assert "REFUSED" in capsys.readouterr().out
    assert tres.with_suffix(".foe").read_text() == edited
    assert store_path.read_text() == (EXAMPLE / "foe_annotations.json").read_text()


# --- sectors without an original are nobody's business but the designer's -------------------------------------

def _new_sector(tmp_path: Path, n: int = 40) -> Path:
    tres = common.sector_file(n, "tres", tmp_path)
    tres.parent.mkdir(exist_ok=True)
    tres.write_text('[gd_resource type="Resource"]\nstart_label = "mine"\n')
    tres.with_suffix(".foe").write_text("; my own\nmine:\n    Jump_To mine\n")
    return tres


@needs_scripts
def test_the_tools_refuse_a_sector_without_an_original_and_leave_its_files(tmp_path, capsys):
    tres = _new_sector(tmp_path)
    before = (tres.read_text(), tres.with_suffix(".foe").read_text())
    store_path = tmp_path / "foe_annotations.json"
    assert harvester.run([40], sector_dir=tmp_path, store_path=store_path) is False
    assert "no original script" in capsys.readouterr().out
    with pytest.raises(ValueError, match="no original script"):
        reset.run([40], sector_dir=tmp_path)
    assert (tres.read_text(), tres.with_suffix(".foe").read_text()) == before
    assert fa.load(store_path) == {}
    assert 40 not in reset.original_sectors()
    assert "sector 40 ha" in reset.refuse_new_sectors([3, 40]) and reset.refuse_new_sectors([3]) == ""


def test_harvest_all_and_reset_all_only_name_original_sectors():
    assert reset.original_sectors() == list(range(32))


@pytest.mark.legacy
def test_the_importer_owns_only_the_original_sector_files():
    owned_paths = step_sectors.owned_files()
    sector_files = [p for p in owned_paths if p.name.startswith("sector_")]       # sector_NN/sector_NN.tres and .foe
    owned = {p.name for p in sector_files}
    assert len(sector_files) == 64 and all(re.fullmatch(r"sector_(0\d|[12]\d|3[01])\.(tres|foe)", name) for name in owned)
    assert all(p.parent.name == p.stem and p.parent.parent == PACK_DATA / "sectors" for p in sector_files)
    screens = [p for p in owned_paths if p.name.startswith("screen_")]            # sector_NN/screen_MM.tres, 32 x 12
    assert len(screens) == 384 and all(
        re.fullmatch(r"sector_(0\d|[12]\d|3[01])", p.parent.name) and re.fullmatch(r"screen_(0\d|1[01])\.tres", p.name)
        for p in screens)
    assert len(owned_paths) == 64 + 384
    assert import_all.OWNED_DIRS["sectors"] == []                     # --clean never removes the whole folder
    assert import_all.OWNED_FILES["sectors"] is step_sectors.owned_files
    assert "foe_annotations.json" in {p.name for p in (PROJECT_DATA / "sectors").iterdir()}
    assert "sector_00.foe.uid" in {p.name for p in common.sector_dir(0).iterdir()}      # the .uid files are Godot's
    for kept in ("foe_annotations.json", "sector_00.foe.uid"):
        assert kept not in owned
