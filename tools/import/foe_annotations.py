"""The annotation store: the designers' label names and comments for the creature scripts, and how they are read back
out of a hand-edited .foe text ("harvest").

THE PROBLEM. the legacy pack's data/sectors/sector_NN/sector_NN.foe is generated from the ORIGINAL bytes (foe_text.py), and every import or
reset (step_sectors.py, reset_foe_scripts.py) writes that generated text again. A designer who renames `loc_529` to
`swim_back` or writes comments in the file would lose them. So those additions are kept in ONE committed file,
godot/data/sectors/foe_annotations.json, keyed by (sector, ORIGINAL byte offset), which is stable because the bytes
are the original's. The disassemblers (foe_text.py here, FoeAsm.disassemble in Godot) read it and put the names and
comments back. Only what differs from the generated text is stored; with an empty store everything is as generated.

THE FILE (written by `dumps`, always this exact layout, so git diffs stay small):

    {
     "comment": "...",
     "sectors": {
      "3": {
       "labels": {
        "529": "swim_back"
       },
       "comments": {
        "529": {"label_above": ["; the dive"], "label_inline": "; label", "above": ["    ; step"], "inline": "; x"}
       }
      }
     }
    }

Sectors and offsets are sorted as numbers. In memory one sector is {"labels": {offset: name},
"comments": {offset: {...}}} with int offsets (`for_sector`).

LABELS. offset -> name. It replaces the generated name of an entry point or jump target, or adds a label where the
generated text has none (a heading in the middle of a block). Names are identifiers, unique within the sector.

COMMENTS. offset -> a note with up to four keys. "Position" means the label line and/or instruction line at that byte
offset; the very end of the script is a position too (it has a label line at most, no instruction):
  label_above   the lines between the previous line and the label line: comments and blank lines, copied exactly
                (indentation included). Not stored when it is the default: one blank line, or nothing for the
                first line of the file. An empty list therefore means "no blank line before this label".
  label_inline  the comment on the label line (`name:  ; text`).
  above         the lines between the label line (or, without a label here, the previous line) and the
                instruction line, again exactly. At the end of the script: the lines after the last line.
                The default is none, EXCEPT before the first instruction of a run that never executes: there it is
                the generated `; The following instructions are not executed -- ...` comment
                (foe_text.unexecuted_notes). A stored "above" REPLACES the default, so a designer can reword that
                comment, add lines to it, or delete it (an empty list: no line at all).
  inline        the comment on the instruction line.
An inline comment is stored from its `;` on. It follows the code after two spaces; a comment written with another
distance keeps it as leading spaces in the stored text.
Blank lines are layout and are kept only where they sit inside `label_above` / `above`.

HARVEST. `harvest(text, script, base, entries)` reads a hand-edited text back: offsets come from summing the size of
every instruction line (no assembler is needed; a `Padding N` line is N bytes, a bare `Padding` is 1), names and
comments are stored when they differ from the generated text. A label or comment on a `Padding N` line belongs to its
FIRST byte; the instructions-match check treats `Padding N` as N zero bytes, so it also accepts N lines of
Wait_Next_Tick (or the other way round) where the original has zero bytes. The standard layout writes Padding only for
unreachable zero bytes (foe_text.padding_spans), so reachable zero bytes come back as Wait_Next_Tick lines. It REFUSES (Harvest.ok False, with the reason) when the text's instructions are not those of the original
bytes (a deliberately changed sector), when a place has two labels, or when a creature entry point lost its label,
because then the offsets would not mean the original's. The result also holds the text in the standard layout
(`text`): a harvested file is only in sync when it equals that text, so a caller rewrites the file with it.
The GDScript twin (godot/src/core/foe_annotations.gd) does the same; test_foe_annotations.py and
test_foe_asm.gd check that they agree. Manual: docs/create/FOE_SCRIPTING.md ("Names and comments").
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path

import foe_names
import foe_text
from common import PROJECT_DATA

STORE = PROJECT_DATA / "sectors" / "foe_annotations.json"

# The keys of one comment note, in the order they are written.
NOTE_KEYS = ("label_above", "label_inline", "above", "inline")
LIST_KEYS = ("label_above", "above")

FILE_COMMENT = ("The designers' label names and comments for the creature scripts, keyed by sector and ORIGINAL byte "
                "offset. Written by tools/import/harvest_foe_annotations.py and by the Foe Script screen; read by "
                "the importer and by tools/import/reset_foe_scripts.py. Not shipped with the game. "
                "See docs/create/FOE_SCRIPTING.md.")

_IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")
_MNEMONIC_INDEX = {name.lower(): i for i, name in enumerate(foe_text.MNEMONIC)}


def is_identifier(word: str) -> bool:
    return _IDENTIFIER.match(word) is not None


# ----------------------------------------------------------------------------------------------------------------
# The file
# ----------------------------------------------------------------------------------------------------------------

def empty_sector() -> dict:
    return {"labels": {}, "comments": {}}


def is_empty(sector: dict) -> bool:
    return not sector.get("labels") and not sector.get("comments")


def for_sector(store: dict[int, dict], n: int) -> dict:
    """One sector's annotations ({"labels": ..., "comments": ...}); empty ones when it has none."""
    return store.get(n, empty_sector())


def _checked_note(where: str, note: object) -> dict:
    if not isinstance(note, dict) or not note:
        raise ValueError("%s: a comment note is an object with some of %s" % (where, ", ".join(NOTE_KEYS)))
    for key, value in note.items():
        if key not in NOTE_KEYS:
            raise ValueError("%s: unknown key '%s' (expected %s)" % (where, key, ", ".join(NOTE_KEYS)))
        if key in LIST_KEYS:
            if not isinstance(value, list) or not all(isinstance(line, str) for line in value):
                raise ValueError("%s: '%s' must be a list of text lines" % (where, key))
        elif not isinstance(value, str) or not value:
            raise ValueError("%s: '%s' must be non-empty text" % (where, key))
    return {key: note[key] for key in NOTE_KEYS if key in note}


def parse(text: str) -> dict[int, dict]:
    """The store from the text of the file; raises ValueError for a file that is not in the format described above."""
    data = json.loads(text)
    store: dict[int, dict] = {}
    for key, sector in data.get("sectors", {}).items():
        n = int(key)
        labels: dict[int, str] = {}
        for offset, name in sector.get("labels", {}).items():
            if not isinstance(name, str) or not is_identifier(name):
                raise ValueError("sector %d, label at %s: '%s' is not an identifier" % (n, offset, name))
            labels[int(offset)] = name
        if len(set(labels.values())) != len(labels):
            raise ValueError("sector %d: a label name is used twice in 'labels'" % n)
        comments = {int(offset): _checked_note("sector %d, offset %s" % (n, offset), note)
                    for offset, note in sector.get("comments", {}).items()}
        if labels or comments:
            store[n] = {"labels": dict(sorted(labels.items())), "comments": dict(sorted(comments.items()))}
    return store


def load(path: Path = STORE) -> dict[int, dict]:
    """The store from `path`; an empty one when the file does not exist."""
    if not path.exists():
        return {}
    return parse(path.read_text(encoding="utf-8"))


def _quote(text: str) -> str:
    return json.dumps(text, ensure_ascii=False)


def dumps(store: dict[int, dict]) -> str:
    """The file text for `store`: fixed layout, numbers sorted, one line per label and per commented position."""
    out = ["{", ' "comment": %s,' % _quote(FILE_COMMENT)]
    sectors = [n for n in sorted(store) if not is_empty(store[n])]
    if not sectors:
        out.append(' "sectors": {}')
    else:
        out.append(' "sectors": {')
        for si, n in enumerate(sectors):
            sector = store[n]
            parts: list[list[str]] = []
            if sector.get("labels"):
                block = ['   "labels": {']
                items = ['    "%d": %s' % (offset, _quote(name)) for offset, name in sorted(sector["labels"].items())]
                block.append(",\n".join(items))
                block.append("   }")
                parts.append(block)
            if sector.get("comments"):
                block = ['   "comments": {']
                items = []
                for offset, note in sorted(sector["comments"].items()):
                    fields = []
                    for key in NOTE_KEYS:
                        if key in note:
                            value = note[key]
                            shown = "[" + ", ".join(_quote(line) for line in value) + "]" if key in LIST_KEYS else _quote(value)
                            fields.append('"%s": %s' % (key, shown))
                    items.append('    "%d": {%s}' % (offset, ", ".join(fields)))
                block.append(",\n".join(items))
                block.append("   }")
                parts.append(block)
            out.append('  "%d": {' % n)
            out.append(",\n".join("\n".join(block) for block in parts))
            out.append("  }" + ("," if si < len(sectors) - 1 else ""))
        out.append(" }")
    out.append("}")
    return "\n".join(out) + "\n"


def save(store: dict[int, dict], path: Path = STORE) -> None:
    path.write_text(dumps(store), encoding="utf-8")


# ----------------------------------------------------------------------------------------------------------------
# Harvest
# ----------------------------------------------------------------------------------------------------------------

@dataclass
class Harvest:
    """The outcome of `harvest`."""
    ok: bool = False
    problem: str = ""                                       # why it was refused ("line N: ..."), when not ok
    labels: dict[int, str] = field(default_factory=dict)
    comments: dict[int, dict] = field(default_factory=dict)
    names: dict[int, str] = field(default_factory=dict)     # offset -> the label the text has there
    text: str = ""                                          # the text in the standard layout, with these annotations

    def annotations(self) -> dict:
        return {"labels": dict(sorted(self.labels.items())), "comments": dict(sorted(self.comments.items()))}


@dataclass
class _Element:
    is_label: bool
    line: int
    offset: int
    gap: list[str]                    # comment and blank lines since the previous label / instruction line
    tail: str                         # what follows the code: padding and the `;` comment, or ""
    words: list[str]                  # instruction words, or [name] of a label


def _refuse(problem: str) -> Harvest:
    return Harvest(ok=False, problem=problem)


def _padding_count(operands: list[str]) -> int:
    """The N of a `Padding N` line (1 for a bare `Padding`); -1 when the operands are not one number 1..65535."""
    if not operands:
        return 1
    word = operands[0]
    if len(operands) == 1 and word.isascii() and word.isdigit() and 1 <= int(word) <= foe_text.PADDING_MAX:
        return int(word)
    return -1


def _stored_tail(tail: str) -> str:
    return tail[2:] if tail.startswith("  ;") else tail


def harvest(text: str, script: bytes, base: int, entries: dict[str, int], symbols: foe_names.Names | None = None) -> Harvest:
    """Reads the label names and comments out of `text`, which must be the ORIGINAL `script` (bytes, first byte at
    buffer offset `base`) written as text. `entries` is label -> offset of the creatures' entry points
    (foe_text.entry_names). The operands are compared as VALUES, not as spelling (`Set_Frame 163`, `Set_Frame 35 mirrored`
    and `Set_Frame eel_swim_1 mirrored` are one instruction); `symbols` (foe_names.Names of the sector) says which names
    exist, and the text of the result is written with the names the registry has. See the module docstring for the rules."""
    decoded = foe_text.decode(script, base)
    end = base + len(script)
    positions = {at for at, _op, _operands in decoded} | {end}
    for name, offset in entries.items():
        if offset not in positions:
            return _refuse("entry point %s (offset %d) is not at the start of an instruction" % (name, offset))

    lines = text.replace("\r\n", "\n").split("\n")
    if lines and lines[-1] == "":
        lines.pop()                                         # the newline that ends the last line
    elements: list[_Element] = []
    gap: list[str] = []
    offset = base
    for number, raw in enumerate(lines, 1):
        raw = raw.rstrip()
        semicolon = raw.find(";")
        code = raw if semicolon < 0 else raw[:semicolon]
        if not code.strip():
            gap.append(raw if semicolon >= 0 else "")
            continue
        tail = raw[len(code.rstrip()):]
        words = re.split(r"[ \t\r]+", code.strip())
        if len(words) == 1 and words[0].endswith(":") and is_identifier(words[0][:-1]):
            elements.append(_Element(True, number, offset, gap, tail, [words[0][:-1]]))
        else:
            if words[0].lower() == foe_text.PADDING.lower():
                count = _padding_count(words[1:])
                if count < 0:
                    return _refuse("line %d: Padding takes one count, 1..%d (or none for 1), got '%s'" % (
                        number, foe_text.PADDING_MAX, " ".join(words[1:])))
                elements.append(_Element(False, number, offset, gap, tail, words))
                offset += count
            else:
                opcode = _MNEMONIC_INDEX.get(words[0].lower(), -1)
                if opcode < 0:
                    return _refuse("line %d: unknown instruction '%s'" % (number, words[0]))
                elements.append(_Element(False, number, offset, gap, tail, words))
                offset += 1 + foe_text.OPERAND_COUNT[opcode]
        gap = []
    trailing = gap

    # the labels of the text
    names: dict[int, str] = {}
    first_line_of: dict[str, int] = {}
    for e in (e for e in elements if e.is_label):
        name = e.words[0]
        if name in first_line_of:
            return _refuse("line %d: duplicate label '%s' (first defined on line %d)" % (e.line, name, first_line_of[name]))
        if e.offset in names:
            return _refuse("line %d: '%s' and '%s' label the same place; keep one of them" % (e.line, names[e.offset], name))
        first_line_of[name] = e.line
        names[e.offset] = name

    # the instructions must be the original's, one by one (a Padding line stands for that many zero bytes)
    instructions = [e for e in elements if not e.is_label]
    i = 0                                                   # the next original instruction
    for e in instructions:
        if i >= len(decoded):
            return _refuse("line %d: the original has no instruction here" % e.line)
        at, opcode, operands = decoded[i]
        if opcode < 0:
            return _refuse("the original has an undecodable byte at offset %d" % at)
        if e.words[0].lower() == foe_text.PADDING.lower():
            count = _padding_count(e.words[1:])
            for k in range(count):
                if i + k >= len(decoded) or decoded[i + k][1] != 0 or decoded[i + k][0] != e.offset + k:
                    shown = "the end of the script"
                    if i + k < len(decoded):
                        at_k, opcode_k, operands_k = decoded[i + k]
                        shown = "??%d" % operands_k[0] if opcode_k < 0 else foe_text._format(opcode_k, operands_k, at_k, names, symbols)
                    return _refuse("line %d: the original has '%s' here, the text has '%s'" % (e.line, shown, " ".join(e.words)))
            i += count
            continue
        expected = foe_text._format(opcode, operands, at, names, symbols)
        found = " ".join(e.words)
        if e.offset != at or found.split(" ")[0].lower() != expected.split(" ")[0].lower() \
                or foe_text.parse_operands(opcode, e.words[1:], symbols) != foe_text.operand_values(opcode, operands, at, names):
            return _refuse("line %d: the original has '%s' here, the text has '%s'" % (e.line, expected, found))
        i += 1
    if i < len(decoded):
        at, opcode, operands = decoded[i]
        if opcode < 0:
            return _refuse("the original has an undecodable byte at offset %d" % at)
        return _refuse("the text ends early: the original continues with '%s'" % foe_text._format(opcode, operands, at, names, symbols))
    for name, entry_offset in entries.items():
        if entry_offset not in names:
            return _refuse("%s (offset %d) is an entry point of a creature and needs a label" % (name, entry_offset))

    # what differs from the generated text
    generated = foe_text.default_names(script, base, entries)
    unexecuted = foe_text.unexecuted_notes(script, base, entries)       # the generated "above" lines
    result = Harvest(ok=True, names=names)
    result.labels = {at: name for at, name in names.items() if generated.get(at) != name}
    notes: dict[int, dict] = {}
    have_previous = False
    for e in elements:
        note = notes.setdefault(e.offset, {})
        tail = _stored_tail(e.tail) if e.tail else ""
        if e.is_label:
            if e.gap != ([""] if have_previous else []):
                note["label_above"] = e.gap
            if tail:
                note["label_inline"] = tail
        else:
            if e.gap != unexecuted.get(e.offset, []):         # stored when it differs, even if it is empty
                note["above"] = e.gap
            if tail:
                note["inline"] = tail
        have_previous = True
    if trailing:
        notes.setdefault(end, {})["above"] = trailing
    result.comments = {at: {key: note[key] for key in NOTE_KEYS if key in note}
                       for at, note in sorted(notes.items()) if note}
    result.text = foe_text.disassemble(script, base, entries, result.annotations(), symbols)
    return result
