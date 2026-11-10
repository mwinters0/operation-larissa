"""map_names.py: the committed name tables refer to ONWIN.MAP instead of copying its names, and the names come back from the ISO.

The MAP text below is made up in the MAP's layout (no line of the original); the tests marked legacy read the table the
importer made from your ISO.
"""
import json

import pytest

import map_names as mn

MAP_TEXT = """
  Address         Publics by Name

 0002:0010       _OpenHatch

  Address         Publics by Value

 0000:0000 idle  GETVERSION
 0000:8000  Abs  FJSRQQ
 0001:0C5D       F_FTOL@
 0001:0C5D       FTOL@
 0002:0010       _OpenHatch
 0002:0042 idle  __scan_digits
 0003:0100       PASCALPROC
 0004:0008       xmsg::xmsg(const xmsg far&)

Line numbers for ACCESS.OBJ(ACCESS.C) segment ACCESS_TEXT

    12 0002:0010
"""
SYMS = mn.parse(MAP_TEXT)
HERE = mn.HERE
TABLES = ("names_onwin32.json", "labels_onwin32.json", "port_map_onwin32.json")


def test_parse_reads_the_publics_by_value():
    assert SYMS == {"0001:0C5D": "F_FTOL@", "0002:0010": "OpenHatch", "0002:0042": "_scan_digits", "0003:0100": "PASCALPROC",
                    "0004:0008": "xmsg::xmsg(const xmsg far&)"}


def test_resolve_gives_references_their_name_and_keeps_the_rest():
    table = {"0x1": {"map": "0002:0010", "evidence": "opens it"}, "0x2": {"name": "Mine", "evidence": ""}, "0x3": "Plain"}
    assert mn.resolve(table, SYMS) == {"0x1": {"name": "OpenHatch", "evidence": "opens it"}, "0x2": {"name": "Mine", "evidence": ""},
                                       "0x3": "Plain"}
    with pytest.raises(KeyError, match="0009:0000"):
        mn.name_of({"map": "0009:0000"}, SYMS)


def test_with_name_writes_a_map_name_as_its_reference():
    assert mn.with_name({"evidence": ""}, "OpenHatch", SYMS) == {"map": "0002:0010", "evidence": ""}
    assert mn.with_name({"map": "0002:0010", "evidence": "e"}, "CloseHatch", SYMS) == {"name": "CloseHatch", "evidence": "e"}
    assert mn.with_name("Old", "OpenHatch", SYMS) == {"map": "0002:0010"}
    assert mn.with_name({"map": "0002:0010"}, "Plain", SYMS) == {"name": "Plain"}
    assert mn.with_name("Old", "Plain", SYMS) == "Plain"
    assert mn.with_name(None, "Plain", SYMS) == "Plain"
    # a public whose address another public shares is not referred to by name (FTOL@ is not kept at all)
    assert mn.with_name(None, "FTOL@", SYMS) == "FTOL@"


def test_committed_entries_hold_a_name_or_a_reference():
    for fname in TABLES[:2]:
        for address, entry in json.loads((HERE / fname).read_text()).items():
            if isinstance(entry, str):
                continue
            assert ("name" in entry) != ("map" in entry), "%s %s: exactly one of name / map" % (fname, address)
            assert "map" not in entry or mn.REF.match(entry["map"]), "%s %s: %r is not SSSS:OOOO" % (fname, address, entry["map"])
    names = json.loads((HERE / "names_onwin32.json").read_text())
    for address, entry in json.loads((HERE / "port_map_onwin32.json").read_text()).items():
        # the port map repeats a name the port gave; a MAP name it leaves to names_onwin32.json
        assert entry.get("name") == names[address].get("name"), "port map %s: name %r, names_onwin32.json %r" % (
            address, entry.get("name"), names[address].get("name"))
    for entry, function in json.loads((HERE / "annotations_onwin32.json").read_text())["functions"].items():
        if "name" in function and entry in names:
            assert names[entry].get("name") == function["name"], "annotations name %s as names_onwin32.json does not" % entry


@pytest.mark.legacy
def test_no_committed_name_is_a_map_name():
    syms = mn.symbols()
    by_name = mn.refs_by_name(syms)
    for fname in TABLES:
        table = json.loads((HERE / fname).read_text())
        copied = {a: n for a, n in mn.committed_names(table).items() if n in by_name}
        assert not copied, "%s commits ONWIN.MAP names; write {\"map\": ref} (map_names.with_name): %s" % (fname, copied)
        for address, entry in table.items():
            if isinstance(entry, dict) and "map" in entry:
                assert entry["map"] in syms, "%s %s: ONWIN.MAP has no public at %s" % (fname, address, entry["map"])
    annotated = json.loads((HERE / "annotations_onwin32.json").read_text())["functions"]
    assert not {a: f["name"] for a, f in annotated.items() if f.get("name") in by_name}


@pytest.mark.legacy
def test_the_port_map_names_what_the_names_table_names():
    syms = mn.symbols()
    names = mn.resolve(json.loads((HERE / "names_onwin32.json").read_text()), syms)
    port = json.loads((HERE / "port_map_onwin32.json").read_text())
    assert set(port) == set(names)
    assert not {a: e["name"] for a, e in port.items() if "name" in e and e["name"] != names[a]["name"]}
