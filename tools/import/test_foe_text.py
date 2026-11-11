"""pytest checks of the creature-script text (foe_text.py) and of the hash fixture of the original scripts. The tests that need
the importer-written original bytes (git-ignored) skip without them."""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common
import foe_annotations
import foe_names
import foe_script
import foe_text
import pytest

needs_scripts = pytest.mark.skipif(not foe_script.RAW_FIXTURE.exists(),
                                   reason="run the importer on your copy of the game (needs %s)" % foe_script.RAW_FIXTURE)


def test_mnemonics_and_operand_counts_match_foe_ops_gd():
    """foe_text.py and godot/src/core/foe_ops.gd must list the same names and sizes for the original's 25 opcodes; the port's own 26th
    (Mod_Instruction, which only a campaign that declares a mod runs) is no opcode of the original, so the importer does not know it."""
    source = (common.GODOT / "src" / "core" / "foe_ops.gd").read_text()
    block = re.search(r"const MNEMONIC: Array\[String\] = \[(.*?)\n\]", source, re.DOTALL)
    assert block
    names = re.findall(r'"([A-Za-z0-9_]+)"', block.group(1))
    assert names[:len(foe_text.MNEMONIC)] == foe_text.MNEMONIC
    assert names[len(foe_text.MNEMONIC):] == ["Mod_Instruction"]
    counts = re.search(r"const OPERAND_COUNT: Array\[int\] = \[(.*?)\]", source, re.DOTALL)
    assert counts
    sizes = [int(v) for v in counts.group(1).replace("\n", " ").split(",")]
    assert sizes[:len(foe_text.OPERAND_COUNT)] == foe_text.OPERAND_COUNT
    assert sizes[len(foe_text.OPERAND_COUNT):] == [2]


def test_the_padding_pseudo_instruction_matches_foe_ops_gd_and_is_not_an_opcode():
    source = (common.GODOT / "src" / "core" / "foe_ops.gd").read_text()
    assert re.search(r'const PADDING_MAX := %d\b' % foe_text.PADDING_MAX, source)
    assert re.search(r'"name": "%s"' % foe_text.PADDING, source)
    assert foe_text.PADDING not in foe_text.MNEMONIC and len(foe_text.OPERAND_COUNT) == len(foe_text.MNEMONIC) == 25


def test_same_text_as_the_gdscript_example():
    """The example of test_foe_asm.gd (test_disassembly_uses_friendly_names_labels_and_signed_operands)."""
    script = bytes([12, 254, 3, 1,  5, 251, 255, 7, 0,  8, 0xFF,  8, 0x80,  9, 4,  1, 238, 255])
    text = foe_text.disassemble(script, 50, {"walker": 50, "walker_hit": 50, "late": 68})
    assert text == """walker:
    Move_Foe_Relative_XY -2 3 1

loc_54:
    Loop_Counter1_Back_To loc_54 7
    Put_Foe_To_Sleep self-1
    Put_Foe_To_Sleep self
    Wake_Foe 4
    Jump_To walker

late:
"""


def test_one_label_per_offset_and_shared_entries_use_the_first_name():
    offsets = [(10, 10, 12), (12, 10, 10)]
    assert foe_text.entry_labels(offsets) == [("foe0_start", "foe0_start", "foe0_ink"),
                                              ("foe0_ink", "foe0_start", "foe0_start")]


@pytest.mark.legacy
def test_the_hash_fixture_is_the_hash_of_the_original_scripts_and_holds_no_bytes():
    sectors = common.load_json(common.TABLES / "sectors.json")
    text = foe_script.HASH_FIXTURE.read_text()
    assert text == foe_script.build_hash_fixture(sectors)
    fixture = json.loads(text)["sectors"]
    assert len(fixture) == len(sectors) == 32
    for sec, entry in zip(sectors, fixture):
        base, script = foe_script.script_of(sec)
        assert set(entry) == {"index", "source", "offset", "size", "sha256"}      # provenance and one hash per script
        assert entry["index"] == sec["index"] and entry["source"] == sec["foes"]["source"]
        assert entry["offset"] == base and entry["size"] == len(script)
        assert entry["sha256"] == common.sha256_hex(script)
        # the script is the bytes sectors.json carries behind the records
        assert bytes.fromhex(sec["foe_script_bytes_hex"])[base:] == script
        assert script[:8].hex() not in json.dumps(entry)


@pytest.mark.legacy
def test_the_stored_text_is_the_disassembly_of_the_original_script_and_the_tres_refers_to_it():
    store = foe_annotations.load()
    for sec in common.load_json(common.TABLES / "sectors.json"):
        base, script = foe_script.script_of(sec)
        # the stored text in the .foe file is this disassembly (with the designers' names and comments from the
        # annotation store, if any), and the .tres refers to the file
        text = foe_text.disassemble(script, base, foe_text.entry_names(foe_script.offsets_of(sec)),
                                    foe_annotations.for_sector(store, sec["index"]),
                                    foe_names.Names.for_original_sector(sec["index"]))
        foe_file = common.sector_file(sec["index"], "foe")
        assert foe_file.read_bytes() == text.encode("utf-8")
        assert 'path="%s"' % common.res_path(foe_file) in common.sector_file(sec["index"], "tres").read_text()


@needs_scripts
@pytest.mark.legacy
def test_the_raw_fixture_is_the_original_scripts_and_is_not_committed():
    sectors = common.load_json(common.TABLES / "sectors.json")
    assert foe_script.RAW_FIXTURE.read_text() == foe_script.build_raw_fixture(sectors)
    for sec, entry in zip(sectors, foe_script.load_originals()):
        base, script = foe_script.script_of(sec)
        assert entry["index"] == sec["index"] and entry["base"] == base and bytes.fromhex(entry["script_hex"]) == script
        assert [(f["pc"], f["script_hit"], f["script_ink"]) for f in entry["foes"]] == foe_script.offsets_of(sec)
    assert "godot/tests/fixtures/original/" in (common.ROOT / ".gitignore").read_text()


# --- the generated "not executed" comment (reachability) ------------------------------------------------------------
#
# Hand-assembled scripts at base 0. Opcodes: 0 Wait_Next_Tick, 1 Jump_To, 2 Call_Subroutine, 3 Return, 4/5/6 Loop_Counter0/1/2,
# 11 Set_Frame, 15 Hide_Foe, 16 Show_Foe, 17 If_Sub_X_Greater. A jump's two operand bytes are (target - the offset after
# the instruction) as a signed 16-bit number, little endian.

UNUSED = [foe_text.UNEXECUTED_UNUSED]


def _dead(script: list[int], entries: dict[str, int] | None = None) -> dict[int, list[str]]:
    return foe_text.unexecuted_notes(bytes(script), 0, entries or {"start": 0})


def _spans(script: list[int], entries: dict[str, int] | None = None) -> dict[int, int]:
    return foe_text.padding_spans(bytes(script), 0, list((entries or {"start": 0}).values()))


def test_the_comment_text():
    assert foe_text.UNEXECUTED_UNUSED == "    ; The following instructions are not executed -- nothing jumps to them"
    assert not hasattr(foe_text, "UNEXECUTED_PADDING")             # the "they are padding" wording is gone
    source = (common.GODOT / "src" / "core" / "foe_asm.gd").read_text()
    assert "UNEXECUTED_PADDING" not in source and "they are padding" not in source
    assert re.search(r'const UNEXECUTED_UNUSED := "%s"' % re.escape(foe_text.UNEXECUTED_UNUSED), source)


def test_the_opcode_numbers_of_the_analysis_match_the_mnemonics():
    assert foe_text.MNEMONIC[foe_text.RET] == "Return"
    assert foe_text.MNEMONIC[foe_text.JMP] == "Jump_To" and foe_text.MNEMONIC[foe_text.HANDLER] == "Call_Subroutine"
    assert set(foe_text.CONDITIONAL) == {i for i, name in enumerate(foe_text.MNEMONIC) if name.startswith("If_")}


def test_everything_reachable_has_no_comment():
    #   0 Set_Frame 1; 2 Jump_To 0
    assert _dead([11, 1, 1, 0xFB, 0xFF]) == {}


def test_nothing_follows_a_jump():
    #   0 Set_Frame 1; 2 Jump_To 0; 5 Hide_Foe (dead); 6 Show_Foe (dead)
    assert _dead([11, 1, 1, 0xFB, 0xFF, 15, 16]) == {5: UNUSED}


def test_return_ends_the_path():
    #   0 Return; 1 Show_Foe (dead)
    assert _dead([3, 16]) == {1: UNUSED}


def test_a_subroutine_is_reached_by_the_call_and_its_return_comes_back_after_the_call():
    #   0 Call_Subroutine 7; 3 Show_Foe (only the Return of the subroutine gets here); 4 Jump_To 0; 7 Set_Frame 1; 9 Return
    assert _dead([2, 4, 0, 16, 1, 0xF9, 0xFF, 11, 1, 3]) == {}
    #   the same without the call: the subroutine is dead
    assert _dead([11, 1, 16, 1, 0xF9, 0xFF, 11, 1, 3]) == {6: UNUSED}


def test_a_loop_goes_back_and_falls_through_when_it_is_over():
    #   0 Show_Foe; 1 Wait_Next_Tick; 2 Loop_Counter1 -> 1, 3 times; 7 Jump_To 7; 10 Hide_Foe (dead)
    script = [16, 0, 5, 0xFA, 0xFF, 3, 0, 1, 0xFD, 0xFF, 15]
    assert _dead(script) == {10: UNUSED}
    #   entering at the loop: 0 is dead, but 1 is reached by the jump back and 7 by the fall-through
    assert _dead(script, {"start": 2}) == {0: UNUSED, 10: UNUSED}
    #   (Loop_Counter0 and 2 are the same)
    for opcode in (4, 6):
        assert _dead([16, 0, opcode, 0xFA, 0xFF, 3, 0, 1, 0xFD, 0xFF, 15], {"start": 2}) == {0: UNUSED, 10: UNUSED}


def test_a_condition_may_skip_the_next_instruction():
    #   0 If_Sub_X_Greater 5; 2 Jump_To 0; 5 Show_Foe (reached by the skip); 6 Jump_To 0; 9 Hide_Foe (dead)
    assert _dead([17, 5, 1, 0xFB, 0xFF, 16, 1, 0xF7, 0xFF, 15]) == {9: UNUSED}
    #   without the condition the jump is always taken and Show_Foe is dead too
    assert _dead([11, 5, 1, 0xFB, 0xFF, 16, 1, 0xF7, 0xFF, 15]) == {5: UNUSED}


def test_every_conditional_instruction_skips():
    for opcode in foe_text.CONDITIONAL:
        #   0 If_..., 2 Jump_To 0, 5 Show_Foe (reached only by the skip), 6 Return
        assert _dead([opcode, 1, 1, 0xFB, 0xFF, 16, 3]) == {}, foe_text.MNEMONIC[opcode]


def test_the_hit_and_the_ink_entry_are_starting_points_too():
    #   0 Jump_To 0; 3, 4 Wait_Next_Tick (dead); 5 Show_Foe, 6 Return (hit); 7 Hide_Foe, 8 Return (ink)
    script = [1, 0xFD, 0xFF, 0, 0, 16, 3, 15, 3]
    entries = {"foe0_start": 0, "foe0_hit": 5, "foe0_ink": 7}
    assert _dead(script, entries) == {} and _spans(script, entries) == {3: 2}      # only zero bytes: Padding 2, no comment
    assert _dead(script) == {5: UNUSED} and _spans(script) == {3: 2}               # without them the dead run has code too


def test_a_run_of_only_zero_bytes_is_padding_and_a_run_with_code_is_unused_code():
    assert _dead([3, 0, 0, 0]) == {} and _spans([3, 0, 0, 0]) == {1: 3}
    assert foe_text.disassemble(bytes([3, 0, 0, 0]), 0, {"start": 0}) == "start:\n    Return\n    Padding 3\n"


def test_zero_bytes_inside_a_run_with_code_are_padding_only_when_nothing_falls_into_them():
    # the comment goes before the first instruction that is not padding; Padding lines are not code
    #   0 Return; 1, 2 zero (follow a Return); 3 Hide_Foe; 4 zero (falls through from Hide_Foe: a pause); 5 Show_Foe;
    #   6 Jump_To 0 (dead); 9, 10 zero (follow a Jump_To); 11 Show_Foe
    script = [3, 0, 0, 15, 0, 16, 1, 0xF7, 0xFF, 0, 0, 16]
    assert _dead(script) == {3: UNUSED}
    assert _spans(script) == {1: 2, 9: 2}
    assert foe_text.disassemble(bytes(script), 0, {"start": 0}) == (
        "start:\n    Return\n    Padding 2\n%s\n    Hide_Foe\n    Wait_Next_Tick\n    Show_Foe\n"
        "    Jump_To start\n    Padding 2\n    Show_Foe\n" % foe_text.UNEXECUTED_UNUSED)
    # zero bytes that start a run are padding even after an instruction that falls through (the run is a new one)
    #   0 Jump_To 0; 3 zero; 4 Hide_Foe
    assert _spans([1, 0xFD, 0xFF, 0, 15]) == {3: 1} and _dead([1, 0xFD, 0xFF, 0, 15]) == {4: UNUSED}
    # trailing zero bytes after an instruction that falls through are code (the unused script runs on into them)
    assert _spans([3, 15, 0, 0]) == {} and _dead([3, 15, 0, 0]) == {1: UNUSED}
    assert _spans([3, 1, 0xFC, 0xFF, 0, 0]) == {4: 2}


def test_a_reachable_zero_byte_stays_wait_next_tick_and_gets_no_padding():
    #   0 Wait_Next_Tick; 1 Wait_Next_Tick; 2 Jump_To 0; 5, 6 zero (dead)
    script = [0, 0, 1, 0xFB, 0xFF, 0, 0]
    assert _spans(script) == {5: 2}
    assert foe_text.disassemble(bytes(script), 0, {"start": 0}) == (
        "start:\n    Wait_Next_Tick\n    Wait_Next_Tick\n    Jump_To start\n    Padding 2\n")


def test_a_label_in_a_run_of_zero_bytes_splits_the_padding_and_a_long_run_needs_more_than_one_line():
    #   0 Return; 1..4 zero; 5 Jump_To loc_3 (dead, makes loc_3 a label in the middle of the zero bytes)
    script = [3, 0, 0, 0, 0, 1, 0xFB, 0xFF]
    assert _spans(script) == {1: 2, 3: 2}
    n = foe_text.PADDING_MAX + 5
    assert foe_text.padding_spans(bytes([3] + [0] * n), 0, [0]) == {1: foe_text.PADDING_MAX, 1 + foe_text.PADDING_MAX: 5}


def test_a_label_inside_a_dead_run_starts_a_new_run():
    #   0 Jump_To 0; 3 Show_Foe, 4 Hide_Foe (both dead); 5 Jump_To loc_4 (dead, makes loc_4); 8 Show_Foe (dead)
    script = [1, 0xFD, 0xFF, 16, 15, 1, 0xFC, 0xFF, 16]
    assert _dead(script) == {3: UNUSED, 4: UNUSED}
    text = foe_text.disassemble(bytes(script), 0, {"start": 0})
    assert text == """start:
    Jump_To start
    %s
    Show_Foe

loc_4:
    %s
    Hide_Foe
    Jump_To loc_4
    Show_Foe
""" % (foe_text.UNEXECUTED_UNUSED.strip(), foe_text.UNEXECUTED_UNUSED.strip())


def test_the_parts_of_a_split_run_are_judged_separately():
    #   0 Jump_To 0; 3 Wait_Next_Tick (dead); 4 Wait_Next_Tick (dead, target of the next); 5 Jump_To loc_4 (dead)
    script = [1, 0xFD, 0xFF, 0, 0, 1, 0xFC, 0xFF]
    assert _spans(script) == {3: 1, 4: 1} and _dead(script) == {5: UNUSED}


def test_the_comment_comes_after_the_label_line_and_before_the_instruction():
    #   0 Return; 1 Hide_Foe (dead, labelled by a dead jump); 2 Jump_To loc_1
    script = [3, 15, 1, 0xFC, 0xFF]
    assert foe_text.disassemble(bytes(script), 0, {"start": 0}) == (
        "start:\n    Return\n\nloc_1:\n%s\n    Hide_Foe\n    Jump_To loc_1\n" % foe_text.UNEXECUTED_UNUSED)
    # a Padding line at the start of the run comes first, the comment goes before the code after it
    script = [3, 0, 15, 1, 0xFA, 0xFF]
    assert foe_text.disassemble(bytes(script), 0, {"start": 0}) == (
        "start:\n    Return\n    Padding 1\n%s\n    Hide_Foe\n    Jump_To start\n" % foe_text.UNEXECUTED_UNUSED)


@needs_scripts
def test_sector_0_starts_like_the_designers_model():
    entry = foe_script.load_originals()[0]
    offsets = [(f["pc"], f["script_hit"], f["script_ink"]) for f in entry["foes"]]
    text = foe_text.disassemble(bytes.fromhex(entry["script_hex"]), entry["base"], foe_text.entry_names(offsets))
    assert text.startswith("foe0_hit:\n    Return\n    Padding 9\n\nfoe0_ink:")
    assert text.count("    Padding ") == 14 and text.count(foe_text.UNEXECUTED_UNUSED) == 1
    assert "they are padding" not in text


@needs_scripts
def test_every_dead_instruction_of_every_sector_is_padding_or_under_a_comment_and_no_live_one_is():
    for entry in foe_script.load_originals():
        offsets = [(f["pc"], f["script_hit"], f["script_ink"]) for f in entry["foes"]]
        script, base, entries = bytes.fromhex(entry["script_hex"]), entry["base"], foe_text.entry_names(offsets)
        decoded = foe_text.decode(script, base)
        alive = foe_text.reachable(decoded, list(entries.values()))
        notes = foe_text.unexecuted_notes(script, base, entries)
        spans = foe_text.padding_spans(script, base, list(entries.values()))
        padded = {at for start, size in spans.items() for at in range(start, start + size)}
        assert not set(notes) & alive and not padded & alive         # neither a comment nor Padding on a live instruction
        assert all(script[at - base] == 0 for at in padded)
        names = foe_text.default_names(script, base, entries)
        covered = False
        for at, _opcode, _operands in decoded:
            if at in alive:
                covered = False
            elif at not in padded:
                covered = (covered and at not in names) or at in notes
                assert covered, "sector %d offset %d" % (entry["index"], at)


@needs_scripts
def test_the_text_of_every_sector_has_as_many_bytes_as_the_script_and_no_zero_byte_is_written_twice():
    for entry in foe_script.load_originals():
        offsets = [(f["pc"], f["script_hit"], f["script_ink"]) for f in entry["foes"]]
        script, base, entries = bytes.fromhex(entry["script_hex"]), entry["base"], foe_text.entry_names(offsets)
        text = foe_text.disassemble(script, base, entries)
        size = 0
        for line in text.splitlines():
            words = line.split(";")[0].split()
            if not words or words[0].endswith(":"):
                continue
            if words[0] == foe_text.PADDING:
                assert len(words) == 2 and 1 <= int(words[1]) <= foe_text.PADDING_MAX
                size += int(words[1])
            else:
                size += 1 + foe_text.OPERAND_COUNT[foe_text.MNEMONIC.index(words[0])]
        assert size == len(script), entry["index"]
        assert "they are padding" not in text


def test_unreachable_offsets_and_runs_work_on_any_script_bytes():
    #   0 Jump_To 0; 3 Show_Foe, 4 Hide_Foe (dead); 5 Jump_To loc_4 (dead); 8 Show_Foe (dead)
    script = bytes([1, 0xFD, 0xFF, 16, 15, 1, 0xFC, 0xFF, 16])
    assert foe_text.unreachable_offsets(script, 0, [0]) == [3, 4, 5, 8]
    assert foe_text.unreachable_offsets(script, 0, [0, 4]) == [3, 8]           # an entry at 4 makes 4 and 5 live
    assert foe_text.dead_runs(script, 0, [0]) == [(3, 4), (4, 9)]              # the jump target loc_4 splits the run
    assert foe_text.dead_runs(script, 100, [100]) == [(103, 104), (104, 109)]  # offsets are buffer offsets
    assert foe_text.unreachable_offsets(script, 0, []) == [0, 3, 4, 5, 8]     # no entry points: nothing is reachable
