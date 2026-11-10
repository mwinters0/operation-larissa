"""annotations.py: the annotation file round-trips, and the three-way merge keeps your work and the file's (docs/port/GHIDRA_GUI.md)."""
import pytest

from annotations import (MISSING, dump, flatten, format_type, merge3, param_text, parse_param, parse_storage, parse_type, storage_key,
                         unflatten)

DOC = {
    "comments": {"0x004120bc": {"plate": "end of prologue", "eol": "EDI=height"}},
    "functions": {"0x004120b3": {"name": "FlushRect",
                                "signature": {"cc": "__cdecl", "return": "/void", "params": ["/int x"]},
                                "locals": {"Stack[-0x8]:4": {"name": "tmp_x", "type": "/int"}},
                                "labels": {"0x004120db": "validate_y"}}},
    "data": {"0x00440074": {"type": "/neptune/Prob00 *"}, "0x00440078": None},
    "types": {"/neptune/Point": {"kind": "struct", "size": 8, "packed": False, "fields": []}},
    "equates": {"SCREEN_W": {"value": 640, "refs": ["0x004120f1:1"]}},
    "bookmarks": {"0x004120b3": {"todo": "check the callers"}},
}


def test_flatten_unflatten_round_trip():
    assert unflatten(flatten(DOC), {"0x004120b3": "FlushRect"}) == DOC


def test_unflatten_orders_comments_as_ghidra_shows_them_and_locals_by_offset():
    doc = unflatten({("comments", "0x1", "eol"): "e", ("comments", "0x1", "plate"): "p", ("comments", "0x1", "pre"): "r",
                     ("functions", "0x2", "locals", "Stack[-0x10]:4"): {}, ("functions", "0x2", "locals", "Stack[-0x8]:4"): {},
                     ("functions", "0x2", "locals", "Stack[0x4]:4"): {}})
    assert list(doc["comments"]["0x1"]) == ["plate", "pre", "eol"]
    assert list(doc["functions"]["0x2"]["locals"]) == ["Stack[-0x10]:4", "Stack[-0x8]:4", "Stack[0x4]:4"]


def test_same_facts_same_text():
    flat = flatten(DOC)
    shuffled = dict(reversed(list(flat.items())))
    assert dump(unflatten(flat)) == dump(unflatten(shuffled))


def test_your_changes_win_and_the_files_other_changes_stay():
    base = {("c", "1"): "old", ("c", "2"): "kept", ("c", "3"): "deleted by me"}
    mine = {("c", "1"): "mine", ("c", "2"): "kept", ("c", "4"): "added by me"}
    theirs = {("c", "1"): "old", ("c", "2"): "changed upstream", ("c", "3"): "deleted by me", ("c", "5"): "added upstream"}
    result, changes, conflicts, new_base = merge3(base, mine, theirs)
    assert result == {("c", "1"): "mine", ("c", "2"): "changed upstream", ("c", "4"): "added by me", ("c", "5"): "added upstream"}
    assert {c[0] for c in changes} == {("c", "1"), ("c", "3"), ("c", "4")}
    assert conflicts == []
    assert new_base == {("c", "1"): "mine", ("c", "2"): "kept", ("c", "4"): "added by me"}


def test_without_a_base_nothing_is_deleted():
    """A project the file was never applied to: what it lacks is not yet applied, not deleted."""
    result, changes, conflicts, _ = merge3({}, {("c", "1"): "mine"}, {("c", "1"): "file", ("c", "2"): "only in the file"})
    assert result == {("c", "1"): "mine", ("c", "2"): "only in the file"}
    assert changes == [(("c", "1"), "file", "mine")]
    assert conflicts == []


def test_both_changed_is_a_conflict_and_yours_wins():
    result, _, conflicts, _ = merge3({("c", "1"): "a"}, {("c", "1"): "mine"}, {("c", "1"): "theirs"})
    assert result == {("c", "1"): "mine"}
    assert conflicts == [(("c", "1"), "a", "mine", "theirs")]


def test_a_change_already_in_the_file_is_no_change():
    _, changes, conflicts, _ = merge3({}, {("c", "1"): "same"}, {("c", "1"): "same"})
    assert changes == [] and conflicts == []


def test_deleting_what_the_file_already_lacks_is_no_change():
    _, changes, _, new_base = merge3({("c", "1"): "x"}, {}, {})
    assert changes == [] and new_base == {}
    assert MISSING not in new_base.values()


@pytest.mark.parametrize("text, base, mods", [
    ("/int", "/int", []),
    ("/neptune/Prob00 *", "/neptune/Prob00", ["*"]),
    ("/char *[4]", "/char", ["*", 4]),
    ("/int[3][2]", "/int", [3, 2]),
    ("/WinDef.h/DWORD", "/WinDef.h/DWORD", []),
    ("/neptune/Handler * *", "/neptune/Handler", ["*", "*"]),
])
def test_type_strings(text, base, mods):
    assert parse_type(text) == (base, mods)
    assert format_type(base, mods) == text


def test_a_type_is_a_path():
    with pytest.raises(ValueError):
        parse_type("int")


def test_storage():
    assert parse_storage("Stack[-0x8]:4") == ([("stack", -8, 4)], 0)
    assert parse_storage("EDX:4,EAX:4") == ([("register", "EDX", 4), ("register", "EAX", 4)], 0)
    assert parse_storage("EAX:4@0x1c") == ([("register", "EAX", 4)], 0x1c)
    assert storage_key("EAX:4", 0x1c) == "EAX:4@0x1c" and storage_key("Stack[0x4]:4", 0) == "Stack[0x4]:4"
    with pytest.raises(ValueError):
        parse_storage("ram:00400000:4")


def test_parameters():
    assert parse_param("/neptune/Prob00 * rec") == ("/neptune/Prob00 *", "rec")
    assert param_text(*parse_param("/int x")) == "/int x"
    with pytest.raises(ValueError):
        parse_param("x")
