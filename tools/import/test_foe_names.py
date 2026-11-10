"""pytest checks of the operand names of the creature scripts (foe_names.py, and their use in foe_text.py).

The GDScript twin is godot/tests/engine/test_foe_names_operands.gd; both read the made-up probe script and registry of
godot/tests/fixtures/foe_names_probe.json and must agree with its expected text, which is how the two implementations are
kept the same (the stored scripts of the real sectors are checked against the GDScript disassembler too, by test_foe_asm.gd).
"""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common
import foe_names
import foe_text
import pytest

PROBE = json.loads((common.GODOT / "tests" / "fixtures" / "foe_names_probe.json").read_text())


def _probe_names() -> foe_names.Names:
    return foe_names.Names(foe_names.Registry(PROBE["registry"]["names"]), PROBE["sector"], PROBE["zone"])


def test_the_kinds_match_name_registry_gd():
    source = (common.GODOT / "src" / "core" / "name_registry.gd").read_text()
    block = source[source.index("const KINDS := {"):source.index("static var _original")]
    for kind, (scope, scopes, first, last, fallback) in foe_names.KINDS.items():
        m = re.search(r'&"%s": \{"scope": Scope\.(\w+)(?:, "scopes": (\w+))?, "first": (\d+), "last": (\d+), "fallback": "([^"]+)"' % kind, block)
        assert m, kind
        assert m.group(1).lower() == scope
        assert int(m.group(3)) == first and int(m.group(4)) == last and m.group(5) == fallback
        if scope != foe_names.GLOBAL:
            assert (256 if m.group(2) == "SECTOR_SCOPES" else int(m.group(2))) == scopes


def test_the_mirror_word_matches_foe_ops_gd():
    source = (common.GODOT / "src" / "core" / "foe_ops.gd").read_text()
    assert 'const MIRROR_WORD := "%s"' % foe_names.MIRROR_WORD in source


@pytest.mark.legacy
def test_sector_zone_is_the_zone_of_every_stored_sector():
    for i in range(common.ORIGINAL_SECTOR_COUNT):
        tres = common.sector_file(i, "tres").read_text()
        assert re.search(r"^zone = %d$" % foe_names.sector_zone(i), tres, re.MULTILINE), i


def test_the_probe_script_is_written_with_the_names_of_its_registry():
    script = bytes.fromhex(PROBE["script_hex"])
    assert foe_text.disassemble(script, 0, PROBE["entries"], None, _probe_names()) == PROBE["text"]


def test_the_probe_script_without_names_is_all_numbers():
    script = bytes.fromhex(PROBE["script_hex"])
    text = foe_text.disassemble(script, 0, PROBE["entries"])
    assert "probe_" not in text
    assert "    Set_Frame 40 mirrored\n" in text and "    Put_Foe_To_Sleep 3\n" in text and "    Set_Flag 2\n" in text


def test_scopes_pictures_belong_to_a_zone_and_creatures_flags_and_screens_to_a_sector():
    registry = foe_names.Registry(PROBE["registry"]["names"])
    assert registry.real_name("frame", 40, 2) == "probe_zone_pic" and registry.real_name("frame", 40, 4) == "other_zone_pic"
    assert registry.real_name("frame", 40, 3) == "" and registry.real_name("frame", 40) == ""
    assert registry.real_name("frame", 3, 3) == "probe_common"               # the common names are visible everywhere
    assert registry.real_name("foe", 3, 7) == "probe_boss" and registry.real_name("foe", 3, 8) == ""
    assert registry.index_of("frame", "probe_zone_pic", 2) == 40 and registry.index_of("frame", "probe_zone_pic", 4) == -1
    assert registry.index_of("flag", "probe_finale", 12) == 15 and registry.index_of("flag", "probe_gate", 12) == -1


def test_made_up_names_always_resolve_but_are_never_printed():
    names = _probe_names()
    assert names.index_for("sound", "sfx_28") == 28 and names.index_for("sound", "sfx_028") == -1
    assert names.index_for("frame", "frame_040") == 40 and names.index_for("foe", "foe_3") == 3
    assert names.name_for("sound", 28) == "" and names.name_for("sound", 5) == "probe_sound"
    assert foe_names.fallback_name("sound", 52) == "" and foe_names.fallback_name("sound", 7) == "sfx_07"


def test_the_names_of_the_registry_file_read_back():
    registry = foe_names.Registry.load()
    store = json.loads(foe_names.STORE.read_text())["names"]
    for name, number in store["sound"].items():
        assert registry.real_name("sound", number) == name and registry.index_of("sound", name) == number


# --- reading operands back (the harvest compares values, not spellings) -----------------------------------------------

def test_every_spelling_of_an_operand_reads_to_the_same_value():
    names = _probe_names()
    same = [("Set_Frame", ["probe_zone_pic", "mirrored"], ["40", "mirrored"], ["168"]),
            ("Set_Frame", ["probe_zone_pic"], ["40"], ["frame_040"]),
            ("Play_Sound", ["probe_sound"], ["5"], ["sfx_05"]),
            ("Wake_Foe", ["probe_boss"], ["3"], ["foe_3"]),
            ("Move_Foe_To_Screen_XY", ["1", "2", "probe_zone_pic", "probe_cave"], ["1", "2", "40", "4"], ["1", "2", "frame_040", "screen_04"])]
    for mnemonic, *spellings in same:
        opcode = foe_text.MNEMONIC.index(mnemonic)
        values = [foe_text.parse_operands(opcode, words, names) for words in spellings]
        assert values[0] is not None and all(v == values[0] for v in values), (mnemonic, values)


@pytest.mark.parametrize("mnemonic, words", [
    ("Set_Frame", ["nobody"]), ("Set_Frame", ["168", "mirrored"]), ("Set_Frame", ["mirrored"]), ("Set_Frame", ["3", "mirrored", "mirrored"]),
    ("Set_Frame", ["256"]), ("Set_Frame", ["other_zone_pic"]), ("Play_Sound", ["probe_gate"]), ("Wake_Foe", ["self+64"]),
    ("Wake_Foe", ["3", "mirrored"]), ("Put_Foe_To_Sleep", ["nobody"]), ("Jump_To", ["3"]), ("Set_Flag", []),
])
def test_what_the_assembler_would_refuse_reads_as_none(mnemonic, words):
    assert foe_text.parse_operands(foe_text.MNEMONIC.index(mnemonic), words, _probe_names()) is None


@pytest.mark.legacy
def test_every_line_of_every_stored_sector_reads_back_to_the_bytes_it_was_written_from():
    """Disassemble -> parse over the real scripts: the names, numbers and `mirrored` the importer wrote mean the original operands."""
    store_checked = 0
    for i in range(common.ORIGINAL_SECTOR_COUNT):
        names = foe_names.Names.for_original_sector(i)
        text = common.sector_file(i, "foe").read_text()
        decoded_lines = [re.split(r"\s+", line.split(";")[0].strip()) for line in text.split("\n")]
        words_per_instruction = [w for w in decoded_lines if w != [""] and not w[0].endswith(":")]
        for words in words_per_instruction:
            if words[0] == foe_text.PADDING:
                continue
            opcode = foe_text.MNEMONIC.index(words[0])
            assert foe_text.parse_operands(opcode, words[1:], names) is not None, (i, words)
            store_checked += 1
    assert store_checked > 3000
