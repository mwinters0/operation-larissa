"""The names ONWIN.MAP gives, read from the user's CD: the committed name tables hold a reference to the MAP, never the name.

`ONWINCD/ONWIN.MAP` is the 16-bit build's link map. It is part of the game, so its names are not committed: an entry of
names_onwin32.json, labels_onwin32.json or port_map_onwin32.json whose name is a MAP public holds `"map": "SSSS:OOOO"`, the
16-bit address of that public, in place of `"name"` (the matching of the 32-bit function to the 16-bit public is our work and
is committed; the name is the game's). The importer's `tables` step writes extracted/tables/onwin_map.json (git-ignored) from the ISO,
and every tool reads names through `resolve`, so the names are back wherever the tables are read.

A MAP public's name is the C name without its one leading underscore (`_DoMathProblem` -> `DoMathProblem`). A name the port
gave itself (`ShowProblemHint`, the runtime's `__scanner`, `Alarms` for `_alarms`) is committed as `"name"`. `with_name`
decides which form to write, so a name typed in the Ghidra GUI that happens to be a MAP public is committed as its reference.

  uv run tools/analysis/ghidra/map_names.py write [OUT]      # extracted/tables/onwin_map.json from the ISO (the importer runs this)
  uv run tools/analysis/ghidra/map_names.py find TEXT...     # entries whose name, address or reference contains TEXT

Pure Python, imported by the Ghidra scripts too (the GUI's interpreter has no pycdlib: only `write` reads the ISO).
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.append(str(REPO / "tools" / "import"))   # common.py: where the importer's tables are
from common import TABLES
TABLE = TABLES / "onwin_map.json"
MAP_FILE = "ONWINCD/ONWIN.MAP"
REF = re.compile(r"^[0-9A-F]{4}:[0-9A-F]{4}$")
_PUBLIC = re.compile(r"^\s*([0-9A-F]{4}):([0-9A-F]{4})\s+(?:idle\s+|Abs\s+)?(.+?)\s*$")


class MissingTable(FileNotFoundError):
    pass


def parse(text: str) -> dict[str, str]:
    """ONWIN.MAP's text -> {"SSSS:OOOO": name}, from its "Publics by Value" list.

    Segment 0 (imported and absolute symbols) has no address in the program and is left out; where several publics share an
    address (the runtime's F_LDIV@ / LDIV@ aliases) the first one listed is kept."""
    publics = text.split("Publics by Value", 1)[1].split("Line numbers", 1)[0]
    out: dict[str, str] = {}
    for line in publics.splitlines():
        m = _PUBLIC.match(line)
        if m and m.group(1) != "0000":
            name = m.group(3)
            out.setdefault("%s:%s" % (m.group(1), m.group(2)), name.removeprefix("_"))
    return out


def write_table(out: Path = TABLE) -> int:
    """Read ONWIN.MAP from the CD image and write the table of its publics. Returns the number of publics."""
    sys.path.insert(0, str(REPO / "tools"))
    import gamefiles
    symbols = parse(gamefiles.read(MAP_FILE).decode("latin-1"))
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"source": MAP_FILE, "symbols": symbols}, indent=1) + "\n", newline="\n")
    return len(symbols)


def symbols(table: Path = TABLE) -> dict[str, str]:
    """{"SSSS:OOOO": name} of the MAP's publics, from the table the importer wrote."""
    if not table.exists():
        raise MissingTable("%s is missing: it is made from your ISO by the importer's tables step "
                           "(uv run tools/import/import_all.py --only tables, or uv run %s write)" % (table, Path(__file__).relative_to(REPO)))
    return json.loads(table.read_text())["symbols"]


def refs_by_name(syms: dict[str, str]) -> dict[str, str]:
    """name -> reference, for the names only one public has."""
    seen: dict[str, list[str]] = {}
    for ref, name in syms.items():
        seen.setdefault(name, []).append(ref)
    return {name: refs[0] for name, refs in seen.items() if len(refs) == 1}


def name_of(entry, syms: dict[str, str]) -> str:
    """The name of a committed entry: a label string, or a dict with "name" or "map"."""
    if isinstance(entry, str):
        return entry
    if "name" in entry:
        return entry["name"]
    ref = entry["map"]
    if ref not in syms:
        raise KeyError("ONWIN.MAP has no public at %s (is %s made from another ISO?)" % (ref, TABLE.name))
    return syms[ref]


def resolve(table: dict, syms: dict[str, str]) -> dict:
    """A committed table with every entry's name: references become {"name": ..., other fields}; names stay as they are."""
    out = {}
    for address, entry in table.items():
        if isinstance(entry, dict) and "name" not in entry and "map" in entry:
            entry = {"name": name_of(entry, syms), **{k: v for k, v in entry.items() if k != "map"}}
        out[address] = entry
    return out


def with_name(entry, name: str, syms: dict[str, str]):
    """The committed form of `entry` (None, a label string or a dict) renamed to `name`: a reference when `name` is a MAP
    public, else the name. Other fields (evidence, status, where) are kept; a plain label stays a plain string."""
    ref = refs_by_name(syms).get(name)
    rest = {k: v for k, v in entry.items() if k not in ("name", "map")} if isinstance(entry, dict) else {}
    if ref is None and not isinstance(entry, dict):
        return name
    return {"map": ref, **rest} if ref else {"name": name, **rest}


def committed_names(table: dict) -> dict[str, str]:
    """address -> the names a table commits itself (never a MAP name; see test_map_names.py)."""
    return {a: (e if isinstance(e, str) else e["name"]) for a, e in table.items() if isinstance(e, str) or "name" in e}


def _find(words: list[str]) -> int:
    syms = symbols()
    port = json.loads((HERE / "port_map_onwin32.json").read_text())
    found = 0
    for fname in ("names_onwin32.json", "labels_onwin32.json"):
        for address, entry in json.loads((HERE / fname).read_text()).items():
            name = name_of(entry, syms)
            ref = entry.get("map", "") if isinstance(entry, dict) else ""
            if not any(w.lower() in s.lower() for w in words for s in (name, address, ref)):
                continue
            found += 1
            print("%s  %s%s  (%s)" % (address, name, "  [MAP %s]" % ref if ref else "", fname))
            if isinstance(entry, dict) and entry.get("evidence"):
                print("    evidence: " + entry["evidence"])
            if address in port:
                print("    port: %s: %s" % (port[address].get("status"), port[address].get("where", "")))
    return found


def main(argv: list[str]) -> int:
    if argv[:1] == ["write"] and len(argv) <= 2:
        out = Path(argv[1]) if len(argv) == 2 else TABLE
        print("%d publics of %s -> %s" % (write_table(out), MAP_FILE, out))
        return 0
    if argv[:1] == ["find"] and len(argv) > 1:
        return 0 if _find(argv[1:]) else 1
    print((__doc__ or "").split("\n\n")[-2])
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
