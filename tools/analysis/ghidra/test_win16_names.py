"""win16_names.py: what a Win16 function or label is named, on made-up names (no line of the game). The apply and the export of the Win16
project both use `expected`, so these tests are the contract between them. The last test reads the committed tables, if there are any, and
checks that none holds a name of ONWIN.MAP (the map's names are the game's: a table holds the reference)."""
import json

import pytest

import map_names
import win16_names as wn

SYMS = {"0001:0010": "OpenHatch", "0002:0100": "RunWindow", "001B:0000": "g_depth", "0000:0000": "GETVERSION", "0002:0200": "xalloc::f(int, long)"}
NAMES32 = {"0x00401000": {"map": "0001:0010"}, "0x00401040": {"name": "OurFunc"}, "0x00401080": {"name": "Other"},
           "0x004010c0": {"name": "Pinned"}, "0x00401100": {"map": "0002:0100"}}
MATCHES = {"matches": [
    {"win32": "0x00401040", "win16": "0003:0040", "tier": "A"},
    {"win32": "0x00401080", "win16": "0003:0080", "tier": "B"},
    {"win32": "0x004010c0", "win16": "0003:00C0", "tier": "pin"},
]}


def test_a_function_is_named_by_the_table_then_the_map_then_its_win32_counterpart():
    funcs, labels = wn.expected(SYMS, {"0003:0080": {"name": "ByHand", "evidence": "because"}}, {}, NAMES32, MATCHES)
    assert funcs["0001:0010"] == ("OpenHatch", "Win32 0x00401000 (the map)")
    assert funcs["0003:0040"] == ("OurFunc", "Win32 0x00401040 (matcher tier A)")
    assert funcs["0003:00C0"] == ("Pinned", "Win32 0x004010c0 (pinned)")
    assert funcs["0003:0080"] == ("ByHand", "because")                    # the table wins over the Win32 name
    assert "0000:0000" not in funcs and "0000:0000" not in labels         # an import has no address of its own
    assert labels["001B:0000"] == ("g_depth", None)


def test_a_hand_name_that_is_a_map_public_is_read_through_its_reference():
    funcs, _ = wn.expected(SYMS, {"0003:0200": {"map": "0001:0010"}}, {}, NAMES32, MATCHES)
    assert funcs["0003:0200"][0] == "OpenHatch"


def test_the_project_holds_a_name_without_spaces():
    assert wn.ghidra_name("xalloc::f(int, long)") == "xalloc::f(int,_long)"
    assert wn.ghidra_name("FTOL@") == "FTOL@"


def test_export_leaves_out_what_is_derived_and_writes_what_was_typed():
    funcs, _ = wn.expected(SYMS, {}, {}, NAMES32, MATCHES)
    found = {"0001:0010": ["OpenHatch"],            # the map's name
             "0003:0040": ["OurFunc"],              # the Win32 counterpart's name
             "0002:0200": ["xalloc::f(int,_long)"],  # the map's name, as the project holds it
             "0003:0300": ["TypedByHand"],
             "0002:0100": ["OpenHatch"]}            # another address's map name: a reference
    out, changes = wn.merge({}, found, SYMS, funcs)
    assert out == {"0003:0300": {"name": "TypedByHand"}, "0002:0100": {"map": "0001:0010"}}
    assert sorted(k for k, _, _ in changes) == ["0002:0100", "0003:0300"]
    again, none = wn.merge(out, found, SYMS, funcs)
    assert again == out and not none                  # the second export finds nothing


def test_export_keeps_evidence_and_updates_a_renamed_entry():
    existing = {"0003:0300": {"name": "Old", "evidence": "kept"}}
    out, changes = wn.merge(existing, {"0003:0300": ["New"]}, SYMS, {})
    assert out["0003:0300"] == {"name": "New", "evidence": "kept"}
    assert changes == [("0003:0300", "Old", "New")]


def test_a_label_is_a_plain_string_unless_it_is_a_map_name():
    out, _ = wn.merge({}, {"001B:0100": ["g_mine"], "001B:0200": ["g_depth"]}, SYMS, {}, functions=False)
    assert out == {"001B:0100": "g_mine", "001B:0200": {"map": "001B:0000"}}


def test_the_committed_tables_hold_no_name_of_the_map():
    try:
        syms = map_names.symbols()
    except map_names.MissingTable:
        pytest.skip("the importer has not made extracted/tables/onwin_map.json")
    game = set(syms.values())
    for path in (wn.NAMES16, wn.LABELS16):
        if path.exists():
            for key, entry in json.loads(path.read_text()).items():
                name = entry if isinstance(entry, str) else entry.get("name")
                assert name not in game, "%s %s is a name of ONWIN.MAP: commit its reference" % (path.name, key)
