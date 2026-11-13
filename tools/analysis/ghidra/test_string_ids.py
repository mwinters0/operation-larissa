"""string_ids.py and the committed string-id data: names only, one equate per name, the enum agreeing with them."""
import json
from pathlib import Path

import annotations as an
import string_ids as si

HERE = Path(__file__).resolve().parent
NAMES = si.load_names(HERE / si.NAMES_FILE)
DOC = json.loads((HERE / an.FILE).read_text())


def test_names_are_ids_to_unique_names_without_text():
    assert all(isinstance(i, int) for i in NAMES)
    assert all(n.isupper() or n.replace("_", "").isalnum() for n in NAMES.values())
    assert all(len(n) < 48 and " " not in n for n in NAMES.values())


def test_equates_agree_with_the_names_and_the_enum():
    enum = DOC["types"][si.ENUM_PATH]
    assert enum["kind"] == "enum" and all(enum["values"][n] == i for i, n in NAMES.items())
    for name, equate in DOC["equates"].items():
        if name in enum["values"]:
            assert equate["value"] == enum["values"][name]
            assert equate["refs"] == sorted(equate["refs"])


def test_both_functions_take_the_enum():
    for entry, index in si.ID_PARAMETERS.items():
        param = DOC["functions"][entry]["signature"]["params"][index]
        assert param.startswith(si.ENUM_PATH + " ")


def test_with_ids_regenerates_and_is_idempotent():
    names = {1: "STR_A", 2: "STR_B"}
    sigs = {"0x00411726": {"cc": "__cdecl", "return": "/void", "params": ["/uint uID", "/char * b", "/int n"]},
            "0x00428d70": {"cc": "__cdecl", "return": "/int", "params": ["/int a", "/int string_id", "/int c"]}}
    doc = {"equates": {"OTHER": {"value": 5, "refs": ["0x00000001:0"]}, "STR_B": {"value": 2, "refs": ["0x00000009:0"]}}}
    once = si.with_ids(doc, names, [(1, "0x00000010", 0), (1, "0x00000020", 1)], sigs, {"0x00411726": "LoadStringResource"})
    assert once["equates"]["STR_A"] == {"value": 1, "refs": ["0x00000010:0", "0x00000020:1"]}
    assert "STR_B" not in once["equates"] and "OTHER" in once["equates"]       # a name no site uses any more is dropped
    assert once["types"][si.ENUM_PATH]["values"] == {"STR_A": 1, "STR_B": 2}
    assert once["functions"]["0x00411726"]["signature"]["params"][0] == si.ENUM_PATH + " uID"
    assert once["functions"]["0x00428d70"]["signature"]["params"][1] == si.ENUM_PATH + " string_id"
    assert si.with_ids(once, names, [(1, "0x00000010", 0), (1, "0x00000020", 1)], sigs, {"0x00411726": "LoadStringResource"}) == once


def test_an_id_without_a_name_gets_the_stable_fallback():
    assert si.name_of({}, 123) == "STR_0123"
    assert si.equates_for({}, [(123, "0x00000001", 0)]) == {"STR_0123": {"value": 123, "refs": ["0x00000001:0"]}}
