"""Rename a name of the registry and everything that uses it (docs/create/NAMES.md, "Renaming a name").

    uv run tools/import/rename_name.py KIND OLD NEW [--scope S] [--dry-run] [--import]
    uv run tools/import/rename_name.py KIND OLD_PREFIX NEW_PREFIX --run [--scope S] [--dry-run] [--import]

    uv run tools/import/rename_name.py sound lock_tick click_tick --dry-run
    uv run tools/import/rename_name.py frame eel_swim_0 eel_glide_0 --scope 1        # a zone-scoped name needs its zone (or "common")
    uv run tools/import/rename_name.py foe clam_s2 clam_left --scope 7              # a sector-scoped name needs its sector
    uv run tools/import/rename_name.py text log_entry_ captain_log_ --run           # a whole run of names that the code builds

KIND is one of the registry's kinds (sound frame deco music voice ui_picture problem_art text zone sector foe screen flag). The scope is
`common` or the zone / sector number; it can be left out when the name is only in one table. Nothing is written when anything is wrong
or when --dry-run is given; --dry-run lists every change and every place the tool found but did not dare to change.

WHAT IT CHANGES
  * the registry, godot/names/original.json, written as `json.dumps(data, indent=1, ensure_ascii=False) + "\\n"`, numbers and order kept;
  * the creature scripts, the legacy pack's data/sectors/sector_NN/sector_NN.foe, IN PLACE: exactly the operands of the renamed kind (a `Play_Sound`
    word for a sound, a picture of `Set_Frame` ... for a frame, ...) in the sectors where the name resolves to that entry. A label, a
    comment, another kind's operand with the same spelling and a sector of another scope are never touched. A use written as a number
    or as the made-up name (`sfx_22`) is left as it is: it does not hold the name. Every changed line is re-read with the old and the new
    registry and must give the same operand values (so the script assembles to the same bytes), else nothing is written. The importer's
    `sectors` step is NOT needed (and would overwrite a designer's edits: this tool edits the text instead);
  * the names in GDScript (src/, the project's own addons, tests/): the literals that code_names.py binds to the kind (an argument of
    `Assets.ui_picture`, `Audio.play_sfx`, `Catalog.text` ..., a constant that flows into one), and `&"old"` in a comment when no other kind
    has that name; the file stems `old_<number>` of the asset files in tests and docs; `Play_Sound old` in docs and the editor's help;
    a name in backticks in docs/**/*.md, README.md, AGENTS.md and godot/README.md when it is clearly this name. docs/ROADMAP.md is never edited;
  * with --run: every `prefix<digits>` member of a run, the `"prefix%d"` patterns in the code and the entry of name_runs.json.
  What it only REPORTS (not changed, check by hand): a literal of the name in code that is not bound to the kind (an animation called
  `&"wrong"` next to the sound `wrong`), a name that is also the name of something else, mentions in the tools' Python files and in prose.

WHAT IT REFUSES (nothing is written)
  an unknown kind or name; a made-up name (`sfx_22`: it is derived from the number, name the number instead); a new name that
  `name_problem` rejects (NameRegistry.name_problem: lowercase letters, digits, `_`, at most 40, not reserved, not an instruction) or
  that looks like a made-up name of the kind; a collision in the scope or in `common` (a common name must be free in every scope); the
  same name; one member of a run that the code builds at run time (`log_entry_3`) unless the whole run is renamed with --run.

THE FILES OF THE ASSETS move when the importer runs again (a rename never leaves the old file behind, and the `.import` file goes with its
file): --import does that (every step but `sectors`), or run it yourself, then `tools/godot.sh --headless --path godot --import` and
`git checkout godot/export_presets.cfg`.
"""
from __future__ import annotations

import argparse
import difflib
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import code_names
import common
import foe_names
import foe_text

ROOT = Path(__file__).resolve().parents[2]
COMMON = "common"

GLOBAL_KINDS = ("sound", "music", "voice", "ui_picture", "problem_art", "text", "zone", "sector")
SCOPED_KINDS = {"frame": "zone", "deco": "zone", "foe": "sector", "screen": "sector", "flag": "sector"}
KINDS = tuple(code_names.KINDS)
# NameRegistry.KINDS fallback patterns (test_rename_name.py compares them with name_registry.gd).
FALLBACKS = {kind: foe_names.KINDS[kind][4] for kind in foe_names.KINDS}
FALLBACKS.update({"text": "text_%d", "zone": "zone_%d", "sector": "sector_%02d"})
FIRST_LAST = {kind: (foe_names.KINDS[kind][2], foe_names.KINDS[kind][3]) for kind in foe_names.KINDS}
FIRST_LAST.update({"text": (0, 65535), "zone": (0, 15), "sector": (0, 255)})
# The kinds whose names a creature script's operand takes, and the kinds whose names are asset files.
OPERAND_KINDS = (foe_text.SOUND, foe_text.FRAME, foe_text.FOE, foe_text.FLAG, foe_text.SCREEN)
ASSET_KINDS = ("sound", "voice", "music", "ui_picture", "problem_art", "frame", "deco")
# The importer steps that write asset paths: all but `sectors`, which would overwrite what the designers edited.
IMPORT_STEPS = "images,tiles,sprites,problems,console,story,campaigns,audio"

# NameRegistry.name_problem
MAX_NAME_LENGTH = 40
RESERVED = ("self", "mirror", "mirrored")
NAME_RULE = re.compile(r"^[a-z][a-z0-9_]*$")

# Documents whose mentions are updated; the ROADMAP is the owner's.
DOC_SKIP = ("ROADMAP.md",)
# Python files that spell names (reported, never edited), without the files of this tool.
OWN_FILES = ("rename_name.py", "test_rename_name.py", "code_names.py", "test_code_names.py")


class Refused(Exception):
    """The rename cannot be done; the message says why. Nothing was written."""


def name_problem(name: str) -> str:
    """Why `name` is not a valid name, "" if it is (NameRegistry.name_problem)."""
    if not name:
        return "is empty"
    if len(name) > MAX_NAME_LENGTH:
        return "is longer than %d characters" % MAX_NAME_LENGTH
    if not NAME_RULE.match(name):
        return "is not a valid name (lowercase letters, digits and underscores, starting with a letter)"
    if name in RESERVED:
        return "is a reserved word"
    if name.lower() in {m.lower() for m in foe_text.MNEMONIC} | {foe_text.PADDING.lower()}:
        return "is the name of an instruction"
    return ""


def fallback_name(kind: str, number: int) -> str:
    first, last = FIRST_LAST[kind]
    return FALLBACKS[kind] % number if first <= number <= last else ""


def fallback_index(kind: str, name: str) -> int:
    pattern = FALLBACKS[kind]
    prefix = pattern[:pattern.index("%")]
    digits = name[len(prefix):] if name.startswith(prefix) else ""
    if not re.fullmatch(r"-?[0-9]+", digits):
        return -1
    number = int(digits)
    return number if fallback_name(kind, number) == name else -1


# ----------------------------------------------------------------------------------------------------------------------
# What a plan holds.

@dataclass
class Change:
    path: str                      # relative to the root
    line: int
    before: str
    after: str | None              # None: found but not changed
    why: str


@dataclass
class Plan:
    kind: str
    pairs: list[tuple[str, str, int, str | None]]       # (old, new, number, table key: None for a global kind)
    run: bool = False
    prefixes: tuple[str, str] = ("", "")
    edits: dict[Path, str] = field(default_factory=dict)     # file -> its new text
    changes: list[Change] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)
    import_steps: str = ""

    @property
    def applied(self) -> list[Change]:
        return [c for c in self.changes if c.after is not None]

    @property
    def reported(self) -> list[Change]:
        return [c for c in self.changes if c.after is None]


def dumps(data: dict) -> str:
    return json.dumps(data, indent=1, ensure_ascii=False) + "\n"


def _tables(data: dict, kind: str) -> dict:
    """key -> {name: number}: a global kind has the one table under None."""
    node = data["names"].get(kind, {})
    return dict(node) if kind in SCOPED_KINDS else {None: node}


def _registry(data: dict) -> foe_names.Registry:
    return foe_names.Registry(data["names"])


# ----------------------------------------------------------------------------------------------------------------------
# Checking the request.

def _locate(data: dict, kind: str, name: str, scope: str | None) -> tuple[str | None, int]:
    tables = _tables(data, kind)
    if kind not in SCOPED_KINDS:
        if scope not in (None, ""):
            raise Refused("%s names are global: there is no scope %s" % (kind, scope))
        if name in tables[None]:
            return None, tables[None][name]
    else:
        holders = [key for key, table in tables.items() if name in table]
        if scope not in (None, ""):
            key = COMMON if scope == COMMON else str(int(scope)) if re.fullmatch(r"[0-9]+", scope) else None
            if key is None:
                raise Refused("a scope is `common` or a number (the %s), got '%s'" % (SCOPED_KINDS[kind], scope))
            if key in holders:
                return key, tables[key][name]
            where = ", ".join(holders) or "none"
            raise Refused("no %s named '%s' in scope %s (it is in: %s)" % (kind, name, key, where))
        if len(holders) == 1:
            return holders[0], tables[holders[0]][name]
        if len(holders) > 1:
            raise Refused("'%s' is a %s name in %d scopes (%s): say which with --scope" % (name, kind, len(holders), ", ".join(holders)))
    number = fallback_index(kind, name)
    if number >= 0:
        raise Refused("'%s' is the made-up name of %s %d, not a name in the registry. A made-up name is derived from the number, so there is "
                      "nothing to rename: give the number a name by adding it to names/original.json (docs/create/NAMES.md, \"Adding a name\")" % (name, kind, number))
    every = sorted({n for table in tables.values() for n in table})
    close = difflib.get_close_matches(name, every, n=3)
    raise Refused("there is no %s named '%s'%s" % (kind, name, " (did you mean %s?)" % ", ".join("'%s'" % c for c in close) if close else ""))


def _check_new(data: dict, kind: str, key: str | None, new: str, leaving: set[str]) -> None:
    """The new name must be valid and free where it will be used (`leaving`: names of the table that go away in the same rename)."""
    problem = name_problem(new)
    if problem:
        raise Refused("the new name '%s' %s" % (new, problem))
    if fallback_index(kind, new) >= 0:
        raise Refused("the new name '%s' looks like the made-up name of a %s number (%s); a hand-made name may not" % (new, kind, FALLBACKS[kind]))
    tables = _tables(data, kind)
    if kind not in SCOPED_KINDS or key == COMMON:
        checked = list(tables)                       # a global name, or a common one: free in every table
    else:
        checked = [key, COMMON]                      # a scope's name: free in the scope and in the common names
    for k in checked:
        if k in tables and new in tables[k] and not (k == key and new in leaving):
            where = "" if k is None else " in %s" % ("the common names" if k == COMMON else "scope %s" % k)
            raise Refused("'%s' is already a %s name%s (number %d)" % (new, kind, where, tables[k][new]))


def _load_runs(root: Path) -> dict:
    path = root / "tools" / "import" / "name_runs.json"
    return json.loads(path.read_text(encoding="utf-8"))["runs"] if path.is_file() else {}


def _scan(root: Path) -> tuple[dict[Path, str], code_names.Scan]:
    files = {p: p.read_text(encoding="utf-8") for p in code_names.code_files(root / "godot", tests=True)}
    return files, code_names.scan_sources(files, code_names.autoloads(root / "godot"))


# ----------------------------------------------------------------------------------------------------------------------
# Planning.

def plan_rename(root: Path, kind: str, old: str, new: str, scope: str | None = None, run: bool = False) -> Plan:
    """Everything that renaming `old` to `new` changes under `root` (the repository, or a copy of the parts that matter); raises Refused."""
    if kind not in KINDS:
        raise Refused("unknown kind '%s' (the kinds are %s)" % (kind, ", ".join(KINDS)))
    registry_path = root / "godot" / "names" / "original.json"
    data = json.loads(registry_path.read_text(encoding="utf-8"))
    runs = _load_runs(root)
    files, scan = _scan(root)

    if old == new:
        raise Refused("the new name is the old name")
    if run:
        pairs = _run_pairs(data, kind, old, new, scope, runs, scan)
    else:
        key, number = _locate(data, kind, old, scope)
        _refuse_run_member(kind, old, runs, scan)
        _check_new(data, kind, key, new, set())
        pairs = [(old, new, number, key)]
    plan = Plan(kind, pairs, run, (old, new) if run else ("", ""))

    # --- the registry
    after = json.loads(json.dumps(data))
    for (o, n, number, key) in pairs:
        table = _tables(after, kind)[key]
        renamed = {(n if name == o else name): value for name, value in table.items()}
        if kind in SCOPED_KINDS:
            after["names"][kind][key] = renamed
        else:
            after["names"][kind] = renamed
    plan.edits[registry_path] = dumps(after)
    shown = pairs[:1] if run else pairs
    for (o, n, number, key) in shown:
        plan.changes.append(Change(_rel(root, registry_path), 0, '"%s": %d' % (o, number), '"%s": %d' % (n, number),
                                   "the registry (%s%s)%s" % (kind, "" if key is None else ", scope " + key, ", and %d more of the run" % (len(pairs) - 1) if run and len(pairs) > 1 else "")))
    old_registry, new_registry = _registry(data), _registry(after)

    # --- the creature scripts
    if kind in OPERAND_KINDS:
        _plan_scripts(plan, root, data, after, old_registry, new_registry)

    # --- code, comments, docs
    _plan_text(plan, root, files, scan, data, runs)
    if run:
        _plan_runs_file(plan, root)

    plan.import_steps = IMPORT_STEPS if kind in ASSET_KINDS else ""
    return plan


def _rel(root: Path, path: Path) -> str:
    return path.relative_to(root).as_posix()


def _refuse_run_member(kind: str, name: str, runs: dict, scan: code_names.Scan) -> None:
    prefixes = set(runs.get(kind, {})) | {p.prefix for p in scan.patterns if not p.kinds or kind in p.kinds}
    for prefix in sorted(prefixes):
        if name.startswith(prefix) and name[len(prefix):].isdigit():
            raise Refused("'%s' is a member of the run '%s' that the code builds at run time (\"%s%%d\"): renaming one member would leave the "
                          "code asking for a name that is gone. Rename the whole run with --run (`%s %s <new prefix> --run`)"
                          % (name, prefix, prefix, kind, prefix))


def _run_pairs(data: dict, kind: str, old: str, new: str, scope: str | None, runs: dict, scan: code_names.Scan) -> list:
    declared = old in runs.get(kind, {}) or any(p.prefix == old and (not p.kinds or kind in p.kinds) for p in scan.patterns)
    if not declared:
        raise Refused("'%s' is not a run of %s names (the runs are in tools/import/name_runs.json: %s)" % (old, kind, ", ".join(sorted(runs.get(kind, {}))) or "none"))
    problem = name_problem(new + "0")
    if problem:
        raise Refused("the new prefix '%s' makes names that %s" % (new, problem))
    tables = _tables(data, kind)
    keys = list(tables)
    if kind in SCOPED_KINDS and scope not in (None, ""):
        keys = [COMMON if scope == COMMON else str(int(scope))]
    members = [(key, name, number) for key in keys for name, number in tables.get(key, {}).items()
               if name.startswith(old) and name[len(old):].isdigit()]
    if not members:
        raise Refused("no %s name starts with '%s' followed by digits" % (kind, old))
    pairs = []
    for key, name, number in members:
        target = new + name[len(old):]
        _check_new(data, kind, key, target, {n for k, n, _v in members if k == key})
        pairs.append((name, target, number, key))
    return pairs


# ----------------------------------------------------------------------------------------------------------------------
# The creature scripts.

def _mnemonics() -> dict[str, int]:
    return {m.lower(): i for i, m in enumerate(foe_text.MNEMONIC)}


def _sector_dirs(root: Path):
    # The sectors of the legacy pack (0-31) are in its folder, godot/packs/legacy; a sector of the designers' own (32 and up) is in
    # godot/data/sectors/.
    bases = [root / "godot" / "packs" / "legacy" / "data" / "sectors", root / "godot" / "data" / "sectors"]
    for folder in sorted(f for base in bases for f in base.glob("sector_*")):
        m = re.fullmatch(r"sector_(\d+)", folder.name)
        script = folder / (folder.name + ".foe")
        if m and script.is_file():
            index = int(m.group(1))
            tres = folder / (folder.name + ".tres")
            zone = foe_names.sector_zone(index)
            if tres.is_file():
                z = re.search(r"^zone = (\d+)$", tres.read_text(encoding="utf-8"), re.MULTILINE)
                if z:
                    zone = int(z.group(1))
            yield index, zone, script


def _visible_keys(kind: str, sector: int, zone: int) -> list[str | None]:
    if kind not in SCOPED_KINDS:
        return [None]
    return [str(zone if kind == "frame" else sector), COMMON]


def rewrite_script(text: str, kind: str, renames: dict[str, str], old_names: foe_names.Names, new_names: foe_names.Names) -> tuple[str, list[tuple[int, str, str]]]:
    """`text` with the operands of `kind` renamed (`renames`: old -> new, already limited to the names this sector sees); the changed
    lines as (line number, before, after). Labels, comments and operands of other kinds are never touched. Raises Refused if a changed
    line would not read as the same operand values."""
    mnemonics = _mnemonics()
    out: list[str] = []
    changed: list[tuple[int, str, str]] = []
    for number, line in enumerate(text.splitlines(keepends=True), 1):
        code = line.split(";", 1)[0]
        words = [(m.start(), m.end(), m.group()) for m in re.finditer(r"\S+", code)]
        opcode = mnemonics.get(words[0][2].lower(), -1) if words else -1
        if opcode < 0 or len(words) < 2:
            out.append(line)
            continue
        spec = foe_text._spec(opcode)
        groups: list[int] = []                                   # the index in `words` of each operand word (a `mirrored` joins the word before)
        mirrored: list[bool] = []
        for w in range(1, len(words)):
            if words[w][2].lower() == foe_text.MIRROR_WORD and groups and not mirrored[-1]:
                mirrored[-1] = True
            else:
                groups.append(w)
                mirrored.append(False)
        if len(groups) != len(spec):
            out.append(line)
            continue
        edits = [(words[w][0], words[w][1], renames[words[w][2]]) for w, k in zip(groups, spec) if k == kind and words[w][2] in renames]
        if not edits:
            out.append(line)
            continue
        fixed = line
        for start, end, replacement in sorted(edits, reverse=True):
            fixed = fixed[:start] + replacement + fixed[end:]
        before_words = [w for _s, _e, w in words[1:]]
        after_words = [w for w in re.split(r"\s+", fixed.split(";", 1)[0].strip())[1:]]
        if foe_text.parse_operands(opcode, before_words, old_names) != foe_text.parse_operands(opcode, after_words, new_names):
            raise Refused("line %d of a creature script would not mean the same after the rename: '%s' -> '%s'" % (number, line.strip(), fixed.strip()))
        out.append(fixed)
        changed.append((number, line.rstrip("\r\n"), fixed.rstrip("\r\n")))
    return "".join(out), changed


def _plan_scripts(plan: Plan, root: Path, old_data: dict, new_data: dict, old_registry: foe_names.Registry, new_registry: foe_names.Registry) -> None:
    kind = plan.kind
    for index, zone, script in _sector_dirs(root):
        visible = _visible_keys(kind, index, zone)
        old_names = foe_names.Names(old_registry, index, zone)
        new_names = foe_names.Names(new_registry, index, zone)
        # a word is renamed where its entry is visible (its table is the sector's or the common one) and it resolves to the entry
        applicable = {o: n for (o, n, number, key) in plan.pairs
                      if key in visible and old_names.index_for(kind, o) == number and new_names.index_for(kind, n) == number}
        if not applicable:
            continue
        text = script.read_text(encoding="utf-8")
        fixed, changed = rewrite_script(text, kind, applicable, old_names, new_names)
        if changed:
            plan.edits[script] = fixed
            for number, before, after in changed:
                plan.changes.append(Change(_rel(root, script), number, before.strip(), after.strip(), "creature script operand"))


# ----------------------------------------------------------------------------------------------------------------------
# Code, comments and documents.

def _kinds_of(data: dict, name: str) -> dict[str, list[str | None]]:
    """kind -> the tables that hold `name` (as a real name)."""
    found: dict[str, list[str | None]] = {}
    for kind in data["names"]:
        for key, table in _tables(data, kind).items():
            if name in table:
                found.setdefault(kind, []).append(key)
    return found


def _stem_pattern(kind: str, old: str, number: int, key: str | None) -> re.Pattern | None:
    """The file stem `old_<number>` of an asset (`foe_z3_old_38` for a zone's own creature picture, `deco_z2_old_70` for a deco)."""
    if kind not in ASSET_KINDS:
        return None
    prefix = ""
    if kind == "frame" and number >= common.FOE_ZONE_BASE and key not in (None, COMMON):
        prefix = "foe_z%s_" % key
    elif kind == "deco" and number >= common.COMMON_DECOS and key not in (None, COMMON):
        prefix = "deco_z%s_" % key
    return re.compile(r"(?<![A-Za-z0-9_])%s(%s)_%d(?![0-9])" % (re.escape(prefix), re.escape(old), number))


class _Edits:
    """The edits of one rename, collected against the original texts and applied together."""

    def __init__(self, plan: Plan, root: Path, texts: dict[Path, str]) -> None:
        self.plan, self.root, self.texts = plan, root, texts
        self.pending: dict[Path, list[tuple[int, int, str, Change]]] = {}

    def text(self, path: Path) -> str:
        if path not in self.texts:
            self.texts[path] = path.read_text(encoding="utf-8")
        return self.texts[path]

    def add(self, path: Path, start: int, end: int, new: str | None, why: str) -> None:
        """Replace text[start:end] by `new` (certain), or only report it (`new` is None)."""
        text = self.text(path)
        line_start = text.rfind("\n", 0, start) + 1
        line_end = text.find("\n", end)
        line_end = len(text) if line_end < 0 else line_end
        before = text[line_start:line_end]
        change = Change(_rel(self.root, path), text.count("\n", 0, start) + 1, before.strip(), None, why)
        if new is None:
            self.plan.changes.append(change)
            return
        change.after = (before[:start - line_start] + new + before[end - line_start:]).strip()
        self.pending.setdefault(path, []).append((start, end, new, change))

    def finish(self) -> None:
        for path, edits in self.pending.items():
            text = self.text(path)
            kept: list[tuple[int, int, str, Change]] = []
            for e in sorted(edits, key=lambda e: e[0]):
                if not kept or e[0] >= kept[-1][1]:             # the first of two overlapping edits wins
                    kept.append(e)
            for start, end, new, change in reversed(kept):
                text = text[:start] + new + text[end:]
            self.plan.changes.extend(change for _s, _e, _n, change in kept)
            self.plan.edits[path] = text
        self.plan.changes.sort(key=lambda c: (c.after is None, c.path, c.line))


def _plan_text(plan: Plan, root: Path, files: dict[Path, str], scan: code_names.Scan, data: dict, runs: dict) -> None:
    """Edits of the GDScript literals, the comments, the documents and (with --run) the run patterns."""
    kind = plan.kind
    edits = _Edits(plan, root, dict(files))
    docs = {p: p.read_text(encoding="utf-8") for p in _doc_files(root)}
    edits.texts.update(docs)
    lexed = {path: code_names.lex(text) for path, text in files.items()}

    for (old, new, number, key) in plan.pairs:
        holders = _kinds_of(data, old)
        same_kind_elsewhere = [t for t in holders.get(kind, []) if t != key]
        unique = not same_kind_elsewhere and all(k == kind for k in holders)

        # --- GDScript literals that the scan binds to the kind
        seen: set[tuple[Path, int]] = set()
        for lit in scan.literals:
            if lit.value != old:
                continue
            seen.add((lit.path, lit.start))
            if kind in lit.kinds and not same_kind_elsewhere:
                at = lit.start + len(lit.prefix) + 1
                edits.add(lit.path, at, at + len(old), new, "name literal (%s %s)" % (lit.how, lit.via))
            elif kind in lit.kinds:
                edits.add(lit.path, lit.start, lit.end, None, "a %s name in scope %s as well: which one does the code mean?" % (kind, ", ".join(map(str, same_kind_elsewhere))))
            elif not lit.kinds:
                edits.add(lit.path, lit.start, lit.end, None, "no resolver is seen to take this literal (an animation, a signal ...?): not changed")
        for path in files:
            for t in lexed[path]:
                if t.kind == "str" and t.value == old and t.prefix in ("&", "") and (path, t.start) not in seen:
                    edits.add(path, t.start, t.end, None, "a string outside any resolver call the scan can see: not changed")
                elif t.kind == "comment" or (t.kind == "str" and t.value != old):
                    _mentions(edits, path, t.start, t.end, kind, old, new, number, key, unique, comment=t.kind == "comment")

        # --- documents and Python files
        for path, text in docs.items():
            if path.suffix == ".py":
                for m in re.finditer(r"""(?<=["'`])%s(?=["'`])""" % re.escape(old), text):
                    edits.add(path, m.start(), m.end(), None, "Python file that spells the name: not changed")
            else:
                _mentions(edits, path, 0, len(text), kind, old, new, number, key, unique, comment=False, markdown=True)

    if plan.run:
        old_prefix, new_prefix = plan.prefixes
        for p in scan.patterns:
            if p.prefix == old_prefix and (not p.kinds or kind in p.kinds):
                at = p.start + p.text.index(old_prefix)
                edits.add(p.path, at, at + len(old_prefix), new_prefix, "pattern of the run built at run time")
        for path, text in list(docs.items()) + list(files.items()):
            for m in re.finditer(r"(?<![A-Za-z0-9_])%s(?=%%|<|\*|N\b)" % re.escape(old_prefix), text):
                edits.add(path, m.start(), m.start() + len(old_prefix), new_prefix, "prefix of the run")
    edits.finish()


def _mentions(edits: _Edits, path: Path, start: int, end: int, kind: str, old: str, new: str, number: int, key: str | None,
              unique: bool, comment: bool, markdown: bool = False) -> None:
    """Rules for the prose and the strings between text[start:end]. Certain: a file stem `old_<number>`, an instruction with the name as
    its operand (`Play_Sound old`), `&"old"` in a comment, a name alone in backticks (when no other kind has the name). A name between
    quotes that no rule took is reported."""
    text = edits.text(path)
    chunk = text[start:end]
    taken: list[tuple[int, int]] = []

    def rule(pattern: re.Pattern, why: str, certain: bool) -> None:
        for m in pattern.finditer(chunk):
            a, b = start + m.start(1), start + m.end(1)
            if all(b <= x or a >= y for x, y in taken):
                taken.append((a, b))
                edits.add(path, a, b, new if certain else None, why if certain else why + ": not changed")

    stem = _stem_pattern(kind, old, number, key)
    if stem is not None:
        rule(stem, "file name of the asset", True)
    if kind in OPERAND_KINDS:
        for opcode, mnemonic in enumerate(foe_text.MNEMONIC):
            spec = foe_text._spec(opcode)
            if spec and spec[0] == kind:
                rule(re.compile(r"(?<![A-Za-z0-9_])%s[ \t]+(%s)(?![A-Za-z0-9_])" % (mnemonic, re.escape(old)), re.IGNORECASE),
                     "operand of %s in an example" % mnemonic, unique)
    if comment:
        rule(re.compile(r'&"(%s)"' % re.escape(old)), "name in a comment", unique)
    if markdown or comment:
        rule(re.compile(r'`&?"?(%s)"?`' % re.escape(old)), "name in backticks", unique)
    rule(re.compile(r"""(?<=["'`])(%s)(?=["'`])""" % re.escape(old)), "the name between quotes", False)


def _doc_files(root: Path) -> list[Path]:
    docs = sorted(p for p in (root / "docs").glob("**/*.md") if p.name not in DOC_SKIP) if (root / "docs").is_dir() else []
    top = [p for p in (root / "README.md", root / "AGENTS.md", root / "godot" / "README.md") if p.is_file()]
    py = sorted(p for p in (root / "tools" / "import").glob("*.py") if p.name not in OWN_FILES) if (root / "tools" / "import").is_dir() else []
    return docs + top + py


def _plan_runs_file(plan: Plan, root: Path) -> None:
    """--run: the entry of name_runs.json."""
    runs_path = root / "tools" / "import" / "name_runs.json"
    old_prefix, new_prefix = plan.prefixes
    if runs_path.is_file():
        data = json.loads(runs_path.read_text(encoding="utf-8"))
        table = data["runs"].get(plan.kind, {})
        if old_prefix in table:
            data["runs"][plan.kind] = {(new_prefix if k == old_prefix else k): v for k, v in table.items()}
            plan.edits[runs_path] = dumps(data)
            plan.changes.append(Change(_rel(root, runs_path), 0, '"%s"' % old_prefix, '"%s"' % new_prefix, "the run"))


# ----------------------------------------------------------------------------------------------------------------------
# Applying and reporting.

def apply(plan: Plan) -> list[Path]:
    """Writes every edited file; returns them."""
    for path, text in plan.edits.items():
        path.write_text(text, encoding="utf-8", newline="")
    return list(plan.edits)


def describe(plan: Plan, dry: bool) -> str:
    lines: list[str] = []
    verb = "would change" if dry else "changed"
    if plan.run:
        shown = ", ".join("%s -> %s" % (o, n) for o, n, _num, _k in plan.pairs[:3]) + (" ..." if len(plan.pairs) > 3 else "")
        lines.append("run of %d names: %s" % (len(plan.pairs), shown))
    for change in plan.applied:
        where = change.path + (":%d" % change.line if change.line else "")
        lines.append("%s   (%s)\n  - %s\n  + %s" % (where, change.why, change.before[:200], (change.after or "")[:200]))
    for change in plan.reported:
        lines.append("NOT CHANGED  %s:%d   (%s)\n    %s" % (change.path, change.line, change.why, change.before[:200]))
    lines.append("%s %d places in %d files; %d places found but not changed" % (verb, len(plan.applied), len(plan.edits), len(plan.reported)))
    return "\n".join(lines)


def next_steps(plan: Plan) -> list[str]:
    steps = []
    if plan.import_steps:
        steps.append("uv run tools/import/import_all.py --only %s     (moves the asset files and their .import files, rewrites the catalogs)" % plan.import_steps)
        steps.append("tools/godot.sh --headless --path godot --import; git checkout godot/export_presets.cfg")
    steps.append("tools/run_tests.sh headless; uv run pytest tools")
    return steps


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("kind")
    ap.add_argument("old")
    ap.add_argument("new")
    ap.add_argument("--scope", help="`common`, or the zone (frame, deco) / sector (foe, screen, flag) of the name")
    ap.add_argument("--run", action="store_true", help="OLD and NEW are prefixes of a run of names that the code builds (log_entry_ -> captain_log_)")
    ap.add_argument("--dry-run", action="store_true", help="list every change, write nothing")
    ap.add_argument("--import", dest="do_import", action="store_true", help="afterwards run the importer for the asset files (every step but `sectors`)")
    ap.add_argument("--root", type=Path, default=ROOT, help="the repository (default: this one)")
    args = ap.parse_args(argv)
    try:
        plan = plan_rename(args.root, args.kind, args.old, args.new, args.scope, args.run)
    except Refused as why:
        print("REFUSED, nothing was changed: %s" % why, file=sys.stderr)
        return 1
    print(describe(plan, args.dry_run))
    if args.dry_run:
        return 0
    apply(plan)
    if args.do_import and plan.import_steps:
        print("running the importer ...")
        done = subprocess.run(["uv", "run", str(args.root / "tools" / "import" / "import_all.py"), "--only", plan.import_steps], cwd=args.root, check=False)
        if done.returncode != 0:
            print("the importer failed; the names are renamed, run it again after fixing", file=sys.stderr)
            return done.returncode
    print("next:")
    for step in next_steps(plan):
        if args.do_import and step.startswith("uv run tools/import/import_all.py"):
            continue
        print("  " + step)
    return 0


if __name__ == "__main__":
    sys.exit(main())
