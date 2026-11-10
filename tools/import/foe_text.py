"""The text form of the creature scripts: a disassembler that writes EXACTLY what godot/src/core/foe_asm.gd writes.

The importer stores each sector's creature script as readable text (the legacy pack's data/sectors/sector_NN/sector_NN.foe, SectorData.foe_script). The Godot
side (FoeAsm.assemble) turns that text back into the original bytes; the test godot/tests/engine/test_foe_asm.gd proves
it against the hash in godot/tests/fixtures/foe_scripts.json (and the original bytes the importer wrote to
tests/fixtures/original/, when they are there), and also that FoeAsm.disassemble gives the same text as
`disassemble` here (so the two implementations cannot drift apart).

THE ONE PLACE FOR THE MNEMONICS: MNEMONIC below, the original's 25. test_foe_text.py checks it against the first 25 of godot/src/core/foe_ops.gd (the port's own
26th, Mod_Instruction, is no opcode of the original, which the importer reads).
Manual: docs/create/FOE_SCRIPTING.md.

Operands that have a NAME (a sound, a picture, a creature, a flag, a screen) are written with the name when `disassemble` is
given `names` (foe_names.Names: the sector and zone of the script) and the number has a REAL name there; every other number is
written as the number. A picture with bit 7 is written as the picture and `mirrored`. Without `names` all are numbers
(still with `mirrored`). The reading direction is `parse_operands`, used by the harvest of foe_annotations.py.

Format rules (same as FoeAsm): one instruction per line, indented by four spaces; a label is `name:` at column 0,
preceded by a blank line unless it is the first line; jump targets are label names; ONE label per offset: the first
entry name in creature order (foe0_hit), `loc_<offset>` for jump targets that are no entry point.

The designers' own label names and comments are not part of the generated text. They live in the annotation store
(godot/data/sectors/foe_annotations.json, foe_annotations.py), keyed by the ORIGINAL byte offset, and `disassemble`
writes them back in when it is given one sector's annotations: a stored name replaces the generated label at its
offset, comment lines come before the label / the instruction they were attached to, an end-of-line comment follows
its line (after two spaces, or the padding stored with it). Without annotations the text is the plain generated one.

Unreachable zero bytes that nothing falls into are written as the pseudo-instruction `Padding N` (N zero bytes, one
line; see `padding_spans`), never as N lines of Wait_Next_Tick; zero bytes that a creature can reach stay Wait_Next_Tick.

One comment IS generated, and so belongs to the plain text: before every run of unreachable CODE (a run with a byte that is
not zero),
`; The following instructions are not executed -- nothing jumps to them` (see `unexecuted_notes`). It is the default
"above" comment of the first instruction of that code (after any Padding that starts the run); a stored "above" for that
offset replaces it. A run of only zero bytes is just a `Padding N` line and has no comment.
"""
from __future__ import annotations

import re

import foe_names
import itertools

# Friendly name of each of the original's opcodes, indexed by opcode number (the first 25 of foe_ops.gd MNEMONIC).
MNEMONIC = [
    "Wait_Next_Tick", "Jump_To", "Call_Subroutine", "Return",
    "Loop_Counter0_Back_To", "Loop_Counter1_Back_To", "Loop_Counter2_Back_To",
    "Play_Sound", "Put_Foe_To_Sleep", "Wake_Foe",
    "Set_Frame_Range", "Set_Frame", "Move_Foe_Relative_XY", "Move_Foe_To_XY",
    "Move_Foe_To_Screen_XY", "Hide_Foe", "Show_Foe",
    "If_Sub_X_Greater", "If_Sub_X_Less", "If_Sub_Y_Greater", "If_Sub_Y_Less",
    "If_Random_Greater", "Set_Flag", "Clear_Flag", "If_Flag",
]
# Operand bytes after each opcode (the table at DS 0x184A of the original; the first 25 of foe_ops.gd OPERAND_COUNT).
OPERAND_COUNT = [0, 2, 2, 0, 4, 4, 4, 1, 1, 1, 2, 1, 3, 3, 4, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1]

# Operand kinds (FoeOps.Kind). SOUND, FRAME, FOE, FLAG and SCREEN are also the names of the registry kinds (foe_names.py).
TARGET, U8, I8, U16 = "target", "u8", "i8", "u16"
FOE, SOUND, FRAME, FLAG, SCREEN = "foe", "sound", "frame", "flag", "screen"
MIRROR_WORD = foe_names.MIRROR_WORD

JMP, HANDLER, RET, LOOP0, LOOP2, MOVE_REL, SLEEP_FOE, WAKE_FOE = 1, 2, 3, 4, 6, 12, 8, 9
# The conditional instructions: If_Sub_X_Greater .. If_Random_Greater (17..21) and If_Flag (24). When the condition is
# false they skip the instruction that follows them (foe_vm.gd `_if`).
CONDITIONAL = (17, 18, 19, 20, 21, 24)

# The pseudo-instruction that writes zero bytes (foe_ops.gd PADDING, PADDING_MAX). It is an assembler directive, not an
# opcode, so it is not in MNEMONIC / OPERAND_COUNT.
PADDING = "Padding"
PADDING_MAX = 65535

# The generated comment before a run of unreachable code (docs/create/FOE_SCRIPTING.md). It is indented like instructions. Keep it
# equal to FoeAsm.UNEXECUTED_UNUSED.
UNEXECUTED_UNUSED = "    ; The following instructions are not executed -- nothing jumps to them"


# The instructions whose operand 2 / 3 can be mirrored (bit 7; FoeOps.OPERANDS "mirror"): Set_Frame, Move_Foe_Relative_XY (the
# picture step), Move_Foe_To_XY, Move_Foe_To_Screen_XY: opcode -> operand index.
MIRROR_OPERAND = {11: 0, 12: 2, 13: 2, 14: 2}


def _spec(opcode: int) -> list[str]:
    """The operands as the text format sees them (FoeOps.OPERANDS)."""
    if opcode in (JMP, HANDLER):
        return [TARGET]
    if LOOP0 <= opcode <= LOOP2:
        return [TARGET, U16]
    if opcode == MOVE_REL:
        return [I8, I8, U8]
    if opcode in (SLEEP_FOE, WAKE_FOE):
        return [FOE]
    if opcode == 7:                                          # Play_Sound
        return [SOUND]
    if opcode == 10:                                         # Set_Frame_Range
        return [FRAME, FRAME]
    if opcode == 11:                                         # Set_Frame
        return [FRAME]
    if opcode == 13:                                         # Move_Foe_To_XY
        return [U8, U8, FRAME]
    if opcode == 14:                                         # Move_Foe_To_Screen_XY
        return [U8, U8, FRAME, SCREEN]
    if opcode in (22, 23, 24):                               # Set_Flag, Clear_Flag, If_Flag
        return [FLAG]
    return [U8] * OPERAND_COUNT[opcode]


def _has_target(opcode: int) -> bool:
    return _spec(opcode)[:1] == [TARGET]


def _i16(data: bytes, at: int) -> int:
    v = data[at] | (data[at + 1] << 8)
    return v - 65536 if v >= 32768 else v


def _foe_text(operand: int, names: foe_names.Names | None = None) -> str:
    """3 -> "3" (or the creature's name); 0x81 -> "self+1"; 0xFF -> "self-1"; 0x80 -> "self"."""
    if operand & 0x80 == 0:
        return (names.name_for(FOE, operand) if names is not None else "") or str(operand)
    offset = operand & 0x7F
    if offset >= 64:
        offset -= 128
    return "self" if offset == 0 else "self%+d" % offset


def _operand_text(opcode: int, k: int, kind: str, value: int, symbols: foe_names.Names | None) -> str:
    """A one-byte operand: its real name when `symbols` has one, else the number; a picture with bit 7 is the picture
    and `mirrored` (FoeAsm._operand_text)."""
    mirrored = MIRROR_OPERAND.get(opcode) == k and value >= 128
    plain = value & 0x7F if mirrored else value
    shown = symbols.name_for(kind, plain) if symbols is not None and kind in foe_names.KINDS else ""
    text = shown or str(plain)
    return text + " " + MIRROR_WORD if mirrored else text


def _format(opcode: int, operands: bytes, at: int, names: dict[int, str], symbols: foe_names.Names | None = None) -> str:
    """`names` are the labels (offset -> name), `symbols` the operand names (foe_names.Names, or None for numbers)."""
    text = MNEMONIC[opcode]
    position = 0
    for k, kind in enumerate(_spec(opcode)):
        if kind == TARGET:
            target = at + 1 + OPERAND_COUNT[opcode] + _i16(operands, position)
            text += " " + names.get(target, "loc_%d" % target)
            position += 2
        elif kind == U16:
            text += " %d" % (operands[position] | (operands[position + 1] << 8))
            position += 2
        elif kind == I8:
            v = operands[position]
            text += " %d" % (v - 256 if v >= 128 else v)
            position += 1
        elif kind == FOE:
            text += " " + _foe_text(operands[position], symbols)
            position += 1
        else:
            text += " " + _operand_text(opcode, k, kind, operands[position], symbols)
            position += 1
    return text


def operand_values(opcode: int, operands: bytes, at: int, names: dict[int, str]) -> list:
    """The operand values of a decoded instruction in the form `parse_operands` returns (FoeAsm.operand_values): the label
    of a jump target, a signed number for an I8, the stored byte for everything else."""
    values: list = []
    position = 0
    for kind in _spec(opcode):
        if kind == TARGET:
            target = at + 1 + OPERAND_COUNT[opcode] + _i16(operands, position)
            values.append(names.get(target, "loc_%d" % target))
            position += 2
        elif kind == U16:
            values.append(operands[position] | (operands[position + 1] << 8))
            position += 2
        elif kind == I8:
            values.append(operands[position] - 256 if operands[position] >= 128 else operands[position])
            position += 1
        else:
            values.append(operands[position])
            position += 1
    return values


def _is_identifier(word: str) -> bool:
    return re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", word) is not None


def _is_int(word: str) -> bool:
    return re.fullmatch(r"[+-]?[0-9]+", word) is not None


def _parse_foe(word: str) -> int:
    """FoeOps.parse_foe: 3 -> 3, "self" -> 0x80, "self+2" -> 0x82, "self-1" -> 0xFF; -1 for anything else."""
    lower = word.lower()
    if _is_int(word) and 0 <= int(word) <= 127:
        return int(word)
    if lower == "self":
        return 0x80
    if (lower.startswith(("self+", "self-"))) and re.fullmatch(r"[0-9]+", lower[5:]):
        offset = int(lower[5:]) * (1 if lower[4] == "+" else -1)
        if -64 <= offset <= 63:
            return 0x80 | (offset & 0x7F)
    return -1


def parse_operands(opcode: int, words: list[str], symbols: foe_names.Names | None = None) -> list | None:
    """The operand values of one instruction line, as FoeAsm.parse_operands reads them (a label stays the word), or None
    when the assembler would refuse the line. `words` are the words after the instruction name; a `mirrored` belongs to the
    word before it. Two spellings of one instruction give equal values (see `operand_values`)."""
    symbols = symbols if symbols is not None else foe_names.Names()
    groups: list[list] = []                                  # [word, mirrored]
    for word in words:
        if word.lower() == MIRROR_WORD and groups and not groups[-1][1]:
            groups[-1][1] = True
        else:
            groups.append([word, False])
    spec = _spec(opcode)
    if len(groups) != len(spec):
        return None
    values: list = []
    for k, ((word, mirrored), kind) in enumerate(zip(groups, spec)):
        can_mirror = MIRROR_OPERAND.get(opcode) == k
        if mirrored and not can_mirror:
            return None
        if kind == TARGET:
            if not _is_identifier(word):
                return None
            values.append(word)
            continue
        if kind == FOE:
            value = _parse_foe(word)
            if value < 0 and _is_identifier(word):
                value = symbols.index_for(FOE, word)
            if value < 0:
                return None
        else:
            low, high = {I8: (-128, 127), U16: (0, 65535)}.get(kind, (0, 255))
            if _is_int(word):
                value = int(word)
            elif _is_identifier(word) and kind in foe_names.KINDS:
                value = symbols.index_for(kind, word)
                if value < 0:
                    return None
            else:
                return None
            if not low <= value <= high:
                return None
            if mirrored:
                if value >= 128:
                    return None
                value |= 128
        values.append(value)
    return values


def entry_names(offsets: list[tuple[int, int, int]]) -> dict[str, int]:
    """foe<i>_start / _hit / _ink -> offset, in creature order (FoeAsm.entry_names).

    `offsets` holds (pc, script_hit, script_ink) per creature.
    """
    entries: dict[str, int] = {}
    for i, (pc, hit, ink) in enumerate(offsets):
        entries["foe%d_start" % i] = pc
        entries["foe%d_hit" % i] = hit
        entries["foe%d_ink" % i] = ink
    return entries


def label_for_offsets(entries: dict[str, int], labels: dict[int, str] | None = None) -> dict[int, str]:
    """buffer offset -> the one label printed there (the first entry name that has that offset).

    `labels` are the designer's names from the annotation store (foe_annotations.py): offset -> name. They replace the
    generated name at that offset, or add a label where the generated text has none.
    """
    names: dict[int, str] = {}
    for label, offset in entries.items():
        names.setdefault(offset, label)
    names.update(labels or {})
    return names


def decode(script: bytes, base: int) -> list[tuple[int, int, bytes]]:
    """Every instruction as (buffer offset, opcode or -1, operands or the bad byte); -1 is printed as "??N"."""
    decoded: list[tuple[int, int, bytes]] = []
    index = 0
    while index < len(script):
        opcode = script[index]
        valid = opcode < len(OPERAND_COUNT)
        count = OPERAND_COUNT[opcode] if valid else 0
        if not valid or index + 1 + count > len(script):
            decoded.append((base + index, -1, bytes([opcode])))      # printed as "??N", which the assembler rejects
            index += 1
            continue
        decoded.append((base + index, opcode, script[index + 1:index + 1 + count]))
        index += 1 + count
    return decoded


def jump_targets(decoded: list[tuple[int, int, bytes]]) -> list[int]:
    """The buffer offset every jump / call / loop instruction goes to, in text order."""
    return [at + 1 + OPERAND_COUNT[opcode] + _i16(operands, 0)
            for at, opcode, operands in decoded if opcode >= 0 and _has_target(opcode)]


def default_names(script: bytes, base: int, entries: dict[str, int]) -> dict[int, str]:
    """The generated label of every place that has one: entry names, then `loc_<offset>` for the other jump targets."""
    names = label_for_offsets(entries)
    for target in jump_targets(decode(script, base)):
        names.setdefault(target, "loc_%d" % target)
    return names


def inline_text(tail: str | None) -> str:
    """What follows the code on a line for a stored end-of-line comment: two spaces, unless the stored text brings
    its own leading spaces (foe_annotations.py keeps a different padding that way)."""
    if not tail:
        return ""
    return tail if tail[0] in " \t" else "  " + tail


def reachable(decoded: list[tuple[int, int, bytes]], roots: list[int]) -> set[int]:
    """The offsets of the instructions that can ever execute: a REACHABILITY (control-flow) analysis, the same idea as
    a compiler's dead-code detection.

    Start at the `roots` (the creatures' start / hit / ink entry points) and follow every way the creature can go on
    from an instruction, exactly as foe_vm.gd does:
      - most instructions go on with the NEXT instruction (also Hide_Foe, Wait_Next_Tick: the next tick resumes there);
      - Jump_To goes to its target and nowhere else (no fall-through);
      - Return ends the path: it goes back to where the creature was interrupted, or to the instruction after the
        Call_Subroutine that called it (next point), and both of those are reached by their own paths;
      - Call_Subroutine goes to its target AND to the next instruction, because the subroutine's Return comes back there;
      - Loop_Counter0/1/2 go to their target (jump back) AND to the next instruction (the loop is over);
      - the conditional instructions (If_...) go to the next instruction AND to the one after it (skipped when the
        condition is false).
    Everything not visited is dead. It works on instruction starts only: a jump into the middle of an instruction
    reaches nothing, as the VM would execute different bytes there than this linear decoding shows.
    """
    index_of = {at: i for i, (at, _opcode, _operands) in enumerate(decoded)}
    todo = [index_of[at] for at in roots if at in index_of]
    seen: set[int] = set()
    while todo:
        i = todo.pop()
        if i >= len(decoded) or i in seen:
            continue
        seen.add(i)
        at, opcode, operands = decoded[i]
        if opcode < 0 or opcode == RET:
            continue                                         # a byte that faults / the end of a path
        if _has_target(opcode):                              # Jump_To, Call_Subroutine, Loop_Counter*
            target = index_of.get(at + 1 + OPERAND_COUNT[opcode] + _i16(operands, 0))
            if target is not None:
                todo.append(target)
        if opcode == JMP:
            continue                                         # never falls through
        todo.append(i + 1)
        if opcode in CONDITIONAL:
            todo.append(i + 2)                               # the skip
    return {decoded[i][0] for i in seen}


def unreachable_offsets(script: bytes, base: int, entry_offsets: list[int]) -> list[int]:
    """The offsets of the instructions of `script` (first byte at buffer offset `base`) that can never execute, in
    order, given the creatures' entry offsets (every start / hit / ink offset). Works on any script bytes: the
    disassembler uses it, and so can anything that has assembled a hand-written text (FoeAsm.unreachable_offsets is the
    twin, and the Foe Script editor warns with it). The analysis itself is `reachable`."""
    decoded = decode(script, base)
    alive = reachable(decoded, entry_offsets)
    return [at for at, _opcode, _operands in decoded if at not in alive]


def dead_runs(script: bytes, base: int, entry_offsets: list[int]) -> list[tuple[int, int]]:
    """The runs of unreachable instructions as (offset of the first, offset just after the last).

    A run is consecutive dead instructions without a label between them. A label here is a place something jumps to
    (an entry offset or the target of a jump / call / loop; a name a designer merely gave to a place, or a heading
    in the middle of a block, is no reason to split), and the instructions after such a label are a new run. (The
    twin is FoeAsm.dead_runs.)"""
    decoded = decode(script, base)
    dead = set(unreachable_offsets(script, base, entry_offsets))
    splits = set(entry_offsets) | set(jump_targets(decoded))
    end = base + len(script)
    runs: list[list[int]] = []
    current: list[int] | None = None
    for i, (at, _opcode, _operands) in enumerate(decoded):
        stop = decoded[i + 1][0] if i + 1 < len(decoded) else end
        if at not in dead:
            current = None                                   # a live instruction closes the run
        elif current is None or at in splits:
            current = [at, stop]                             # a new run (a label starts a new one even inside a run)
            runs.append(current)
        else:
            current[1] = stop
    return [(first, stop) for first, stop in runs]


def _run_padding(decoded: list[tuple[int, int, bytes]], first: int, stop: int) -> list[tuple[int, int]]:
    """The padding inside one dead run (`dead_runs`): the (offset, offset just after) of each stretch of zero bytes that
    NOTHING FALLS INTO. (FoeAsm._run_padding is the twin.)

    A stretch of zero bytes (Wait_Next_Tick instructions) is padding when it starts the run, or follows a Return or a
    Jump_To: those never go on to the next instruction. A stretch after any other instruction (in an unused animation,
    a pause between two pictures) is entered by falling through from the code before it, so it is part of that code
    and stays Wait_Next_Tick. A run of only zero bytes is one stretch of padding.
    """
    inside = [(at, opcode) for at, opcode, _operands in decoded if first <= at < stop]
    spans: list[tuple[int, int]] = []
    i = 0
    while i < len(inside):
        if inside[i][1] != 0:
            i += 1
            continue
        j = i
        while j < len(inside) and inside[j][1] == 0:
            j += 1
        if i == 0 or inside[i - 1][1] in (JMP, RET):
            spans.append((inside[i][0], inside[j][0] if j < len(inside) else stop))
        i = j
    return spans


def padding_spans(script: bytes, base: int, entry_offsets: list[int]) -> dict[int, int]:
    """Where the disassembler writes `Padding N`: offset of the first zero byte -> N, in order. (FoeAsm.padding_spans.)

    Padding is the unreachable zero bytes that nothing falls into, found per dead run (`dead_runs`, `_run_padding`): a
    run of only zero bytes is ONE span (N = its length); in a run with code, the zero bytes that start it or follow a
    Return / Jump_To are spans (the filler the original tool left between its unused scripts), while a pause inside an
    unused animation stays Wait_Next_Tick. A reachable zero byte is never padding: a creature runs it as Wait_Next_Tick.
    """
    decoded = decode(script, base)
    spans: dict[int, int] = {}
    for first, stop in dead_runs(script, base, entry_offsets):
        for at, end in _run_padding(decoded, first, stop):
            while at < end:                                  # (a span longer than PADDING_MAX needs more than one line)
                size = min(end - at, PADDING_MAX)
                spans[at] = size
                at += size
    return spans


def unexecuted_notes(script: bytes, base: int, entries: dict[str, int]) -> dict[int, list[str]]:
    """The generated comment before each run of unreachable code: offset of the run's first instruction that is not
    padding -> [comment line]. (FoeAsm.unexecuted_notes is the twin.)

    The runs are those of `dead_runs`, with the `entries` offsets as the creatures' entry points. A run made only of
    zero bytes is just a `Padding N` line (`padding_spans`) and gets no comment; any other run is "nothing jumps to them"
    (scripts the original authoring tool left behind). The comment is part of the plain text, so the annotation store
    holds it only when a designer replaced or removed it.
    """
    decoded = decode(script, base)
    notes: dict[int, list[str]] = {}
    for first, stop in dead_runs(script, base, list(entries.values())):
        padded = {at for start, end in _run_padding(decoded, first, stop) for at in range(start, end)}
        code = [at for at, _opcode, _operands in decoded if first <= at < stop and at not in padded]
        if code:
            notes[code[0]] = [UNEXECUTED_UNUSED]
    return notes


def _split_at(spans: dict[int, int], cuts: set[int]) -> dict[int, int]:
    """`spans` with every span cut in two at an offset of `cuts` that lies inside it, so that a stored label or comment
    at that offset still has a line of its own (a Padding line is the only place where one line covers several offsets)."""
    result: dict[int, int] = {}
    for at, size in spans.items():
        points = [at] + sorted(c for c in cuts if at < c < at + size) + [at + size]
        for start, end in itertools.pairwise(points):
            result[start] = end - start
    return result


def disassemble(script: bytes, base: int, entries: dict[str, int], annotations: dict | None = None,
                symbols: foe_names.Names | None = None) -> str:
    """Text for the whole `script`; `base` is the buffer offset of script[0] (FoeAsm.disassemble).

    `annotations` (optional) are one sector's designer additions from the store, see foe_annotations.py:
    {"labels": {offset: name}, "comments": {offset: {"label_above": [...], "label_inline": "...", "above": [...],
    "inline": "..."}}}. A stored label name replaces the generated one at its offset (jumps use it as well); the
    comment lines are written back in their places. Without them the text is the plain generated one. A stored "above"
    REPLACES the generated comment of `unexecuted_notes` at that offset (so an empty one removes it).

    `symbols` (foe_names.Names of the script's sector) says which operands are written as names; without it they are numbers.

    Unreachable zero bytes are written as `Padding N` lines (`padding_spans`). A stored label or comment at an offset
    inside such a span cuts the span there, so it keeps a line to sit on.
    """
    labels = (annotations or {}).get("labels", {})
    comments = (annotations or {}).get("comments", {})
    decoded = decode(script, base)
    names = label_for_offsets(entries, labels)
    for target in jump_targets(decoded):
        names.setdefault(target, "loc_%d" % target)
    unexecuted = unexecuted_notes(script, base, entries)
    spans = _split_at(padding_spans(script, base, list(entries.values())), set(labels) | set(comments))

    lines: list[str] = []
    placed: set[int] = set()

    def emit_position(offset: int, text: str | None) -> None:
        """The label line (if the offset has a label) and the instruction line (if `text`), with their comments."""
        note = comments.get(offset, {})
        if offset in names and offset not in placed:
            placed.add(offset)
            if "label_above" in note:                     # stored: exactly these lines (comments and blank lines)
                lines.extend(note["label_above"])
            elif lines:                                    # default: one blank line, unless this is the first line
                lines.append("")
            lines.append("%s:%s" % (names[offset], inline_text(note.get("label_inline"))))
        lines.extend(note["above"] if "above" in note else unexecuted.get(offset, []))
        if text is not None:
            lines.append("    " + text + inline_text(note.get("inline")))

    covered = base                                         # the offsets below this belong to a Padding line already
    for at, opcode, operands in decoded:
        if at < covered:
            continue
        if at in spans:
            emit_position(at, "%s %d" % (PADDING, spans[at]))
            covered = at + spans[at]
        else:
            emit_position(at, "??%d" % operands[0] if opcode < 0 else _format(opcode, operands, at, names, symbols))
    emit_position(base + len(script), None)               # labels and comments at the very end
    for offset in sorted(o for o in names if o not in placed):
        lines.append("")
        lines.append("; %s (offset %d) is not at the start of an instruction" % (names[offset], offset))
    return "\n".join(lines) + "\n"


def entry_labels(offsets: list[tuple[int, int, int]], labels: dict[int, str] | None = None) -> list[tuple[str, str, str]]:
    """Per creature, the label its start / hit / ink fields must name: the one printed at that offset."""
    names = label_for_offsets(entry_names(offsets), labels)
    return [(names[pc], names[hit], names[ink]) for pc, hit, ink in offsets]
