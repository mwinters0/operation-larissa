"""I7 batch B: test sectors 120-139 (and the campaign `test_b`, if a test needs one): creatures, combat, the playfield as the skins see it.

This module is the batch's alone (tools/dev_pack/README.md): no other batch edits it and it edits no other batch's. `write_all` is called by
`make_dev_pack.py` (stage "data") after the dev tour. Make a sector with `dev_sectors.standard_sector` or `finale_sector`, change what the test
needs, and write it with `test_sectors.write_sector("b", spec)`, which refuses a number outside the range.

The sectors (the Godot side, with the numbers of the creatures, is `godot/tests/engine/dev_creatures.gd`, `DevCreatures`):

- 120 the arena (zone 0): a creature for every property the creature tests look at, on stated screens (see `ARENA`).
- 121 the closing (zone 0): a sector with a finale screen, a treasure that sets the flag of the ending and a guard that clears it.
- 122 the fish (zone 0): creatures of the kinds the "creatures" skin replaces. It names the original's fish by their registry picture names
  (`skins/creatures/creature_species.gd`: `rainbow_fish_*`, `puffer_*`), and dev uses the same registry names: a hard-coded assumption.

The creatures are the dev pack's own: pictures by their registry names (`Set_Frame clam_closed`), made-up speeds and waits.
"""
from __future__ import annotations

import re
from pathlib import Path

import dev_sectors
import test_sectors
from dev_sectors import Foe

BATCH = "b"

ARENA = 120
CLOSING = 121
FISH = 122

# Picture slots of zone 0 (the common creatures, the ink bursts, then the zone's own): see `dev_sprites.foe_paths`.
CLAM_CLOSED, DOLPHIN_0, RAY_0, INK_0 = 3, 0, 17, 28
RAINBOW_0, JELLY_0, TENTACLE = 35, 39, 44
PUFFER_0 = 9

# Waits of the scripts below, in ticks (the Godot tests state the same numbers, `DevCreatures`).
INK_TICKS = 60                    # an ink cloud lasts this long
CHOMP_ROUND = 20                  # the chomper plays its sound once per round


def arena_script() -> str:
    return """; Dev pack - sector 120, the creature arena (I7 batch B, tools/dev_pack/test_sectors/batch_b.py).
; One creature for every property the creature tests look at; the Godot side lists them in tests/engine/dev_creatures.gd.

; --- shared entry points ----------------------------------------------------------------------------------
quiet_hit:
    Return

; An ink pellet turns the creature into a harmless cloud for 60 ticks (the loop body runs count + 1 times).
cloud_ink:
    Set_Frame ink_burst_0
cloud_wait:
    Wait_Next_Tick
    Loop_Counter1_Back_To cloud_wait 59
    Return

; --- 0 the post: a clam that stays where it is ------------------------------------------------------------
post_start:
    Set_Frame clam_closed
post_wait:
    Wait_Next_Tick
    Jump_To post_wait

; --- 1 the swimmer: right and left, ten steps each --------------------------------------------------------
swimmer_start:
    Set_Frame_Range rainbow_fish_swim_0 rainbow_fish_swim_1
swim_right:
    Move_Foe_Relative_XY 2 0 1
    Loop_Counter0_Back_To swim_right 9
swim_left:
    Move_Foe_Relative_XY -2 0 129
    Loop_Counter0_Back_To swim_left 9
    Jump_To swimmer_start

; --- 2 the chomper: one sound per round of 20 ticks -------------------------------------------------------
chomper_start:
    Set_Frame clam_open_mid
chomp_round:
    Play_Sound clam_chomp
chomp_wait:
    Wait_Next_Tick
    Loop_Counter0_Back_To chomp_wait 19
    Jump_To chomp_round

; --- 3 the bell and 4 the hopper: a jellyfish and its loose tentacle tip -----------------------------------
bell_start:
    Set_Frame_Range jellyfish_pulse_0 jellyfish_pulse_4
bell_pulse:
    Move_Foe_Relative_XY 0 0 1
    Wait_Next_Tick
    Jump_To bell_pulse

; Four hops of 28, 8, 32 and 12 pixels (the picture jellyfish_tentacle is the one the original look never glides), two ticks apart.
hopper_start:
    Set_Frame jellyfish_tentacle
hopper_hop:
    Move_Foe_Relative_XY -14 0 0
    Wait_Next_Tick
    Wait_Next_Tick
    Move_Foe_Relative_XY 4 -1 0
    Wait_Next_Tick
    Wait_Next_Tick
    Move_Foe_Relative_XY 16 1 0
    Wait_Next_Tick
    Wait_Next_Tick
    Move_Foe_Relative_XY -6 0 0
    Wait_Next_Tick
    Wait_Next_Tick
    Jump_To hopper_hop

; --- 5 the sleeper: dormant and hidden until another creature (or a test) wakes it; it creeps right when it runs ---
sleeper_start:
    Set_Frame_Range clam_closed clam_open_wide
sleeper_creep:
    Move_Foe_Relative_XY 1 0 1
    Jump_To sleeper_creep

; --- 6 the runner (screen 6) uses the swimmer's script -------------------------------------------------------

; --- 7 the mirror: stands still, drawn mirrored -------------------------------------------------------------
mirror_start:
    Wait_Next_Tick
    Jump_To mirror_start

; --- 8 the glider: waits two ticks, then swims 12 steps, rests, and swims back ---------------------------------
glider_start:
    Set_Frame_Range ray_swim_0 ray_swim_2
    Wait_Next_Tick
    Wait_Next_Tick
glider_right:
    Move_Foe_Relative_XY 2 0 1
    Loop_Counter0_Back_To glider_right 11
    Wait_Next_Tick
    Wait_Next_Tick
glider_left:
    Move_Foe_Relative_XY -2 0 129
    Loop_Counter0_Back_To glider_left 11
    Jump_To glider_start

; --- 9 Zoom: a dolphin that refills the air; touched, it goes to sleep, plays its sound and hides -------------------
zoom_start:
    Set_Frame_Range dolphin_swim_0 dolphin_swim_2
zoom_swim:
    Move_Foe_Relative_XY 0 0 1
    Jump_To zoom_swim
zoom_hit:
    Put_Foe_To_Sleep self
    Play_Sound oxygen_refill
    Hide_Foe

; --- 10 the waker: on screen 5, it wakes the sleeper (foe 5) after 30 ticks -------------------------------------------
waker_start:
    Set_Frame clam_closed
waker_wait:
    Wait_Next_Tick
    Loop_Counter2_Back_To waker_wait 29
    Wake_Foe 5
waker_idle:
    Wait_Next_Tick
    Jump_To waker_idle
"""


def arena() -> dev_sectors.SectorSpec:
    spec = dev_sectors.standard_sector(ARENA, zone=0, creatures=0)
    spec.script = arena_script()
    spec.music = "esect1"
    spec.pieces.append((8, 420, 200))                       # piece 2: beside piece 1 on screen 8 (taking one leaves the other)
    f = Foe
    spec.foes = [
        f(0, (300, 200), CLAM_CLOSED, CLAM_CLOSED, CLAM_CLOSED, 1, "post_start", "quiet_hit", "cloud_ink"),                    # 0 the post
        f(0, (292, 74), RAINBOW_0, RAINBOW_0, RAINBOW_0 + 1, 1, "swimmer_start", "quiet_hit", "cloud_ink"),                     # 1 the swimmer
        f(0, (500, 150), CLAM_CLOSED + 1, CLAM_CLOSED + 1, CLAM_CLOSED + 1, 0, "chomper_start", "quiet_hit", "cloud_ink"),       # 2 the chomper
        f(2, (412, 36), JELLY_0, JELLY_0, JELLY_0 + 4, 1, "bell_start", "quiet_hit", "cloud_ink"),                             # 3 the bell
        f(2, (408, 90), TENTACLE, TENTACLE, TENTACLE, 1, "hopper_start", "quiet_hit", "cloud_ink"),                            # 4 the hopper
        f(3, (200, 200), CLAM_CLOSED, CLAM_CLOSED, CLAM_CLOSED + 2, 1, "sleeper_start", "quiet_hit", "cloud_ink"),              # 5 the sleeper (dormant, hidden)
        f(6, (200, 74), RAINBOW_0, RAINBOW_0, RAINBOW_0 + 1, 1, "swimmer_start", "quiet_hit", "cloud_ink"),                     # 6 the runner
        f(4, (200, 150), RAY_0, RAY_0, RAY_0 + 2, 1, "mirror_start", "quiet_hit", "cloud_ink", flip=True),                      # 7 the mirror
        f(4, (260, 74), RAY_0, RAY_0, RAY_0 + 2, 1, "glider_start", "quiet_hit", "cloud_ink"),                                 # 8 the glider
        f(7, (300, 150), DOLPHIN_0, DOLPHIN_0, DOLPHIN_0 + 2, -4, "zoom_start", "zoom_hit", "cloud_ink"),                      # 9 Zoom
        f(5, (400, 200), CLAM_CLOSED, CLAM_CLOSED, CLAM_CLOSED, 0, "waker_start", "quiet_hit", "cloud_ink"),                   # 10 the waker
    ]
    return spec


def closing_script() -> str:
    return """; Dev pack - sector 121, the closing (I7 batch B). A sector with a finale screen (10): touching the treasure raises flag 15 and the ending starts
; when the sub is on that screen with the flag up. The guard clears the flag on every tick while the first screen is shown.

treasure_start:
    Set_Frame clam_closed
treasure_wait:
    Wait_Next_Tick
    Jump_To treasure_wait

treasure_hit:
    Hide_Foe
    Set_Flag 15
    Play_Sound oxygen_refill
treasure_hold:
    Wait_Next_Tick
    Jump_To treasure_hold

guard_start:
    Clear_Flag 15
    Wait_Next_Tick
    Jump_To guard_start

quiet_hit:
    Return
cloud_ink:
    Return
"""


def closing() -> dev_sectors.SectorSpec:
    spec = dev_sectors.standard_sector(CLOSING, zone=0, creatures=0)
    spec.script = closing_script()
    spec.finale_screen = 10
    spec.foes = [
        Foe(4, (300, 200), CLAM_CLOSED, CLAM_CLOSED, CLAM_CLOSED, 0, "treasure_start", "treasure_hit", "cloud_ink"),     # 0 the treasure
        Foe(0, (500, 100), CLAM_CLOSED, CLAM_CLOSED, CLAM_CLOSED, 0, "guard_start", "quiet_hit", "cloud_ink"),           # 1 the guard (hidden)
    ]
    return spec


def fish_script() -> str:
    return """; Dev pack - sector 122, the fish (I7 batch B). Creatures of the kinds the "creatures" skin draws itself: puffer fish (foes 1-3) and rainbow fish (foes 4, 5),
; by their registry picture names (skins/creatures/creature_species.gd), and a clam (foe 0) the skin leaves alone.

quiet_hit:
    Return
cloud_ink:
    Set_Frame ink_burst_0
cloud_wait:
    Wait_Next_Tick
    Loop_Counter1_Back_To cloud_wait 29
    Return

clam_start:
    Set_Frame clam_closed
clam_wait:
    Wait_Next_Tick
    Jump_To clam_wait

puffer_start:
    Set_Frame_Range puffer_swim_0 puffer_swim_1
puffer_right:
    Move_Foe_Relative_XY 1 0 1
    Loop_Counter0_Back_To puffer_right 19
puffer_left:
    Move_Foe_Relative_XY -1 0 129
    Loop_Counter0_Back_To puffer_left 19
    Jump_To puffer_start

rainbow_start:
    Set_Frame_Range rainbow_fish_swim_0 rainbow_fish_swim_1
rainbow_right:
    Move_Foe_Relative_XY 2 0 1
    Loop_Counter0_Back_To rainbow_right 14
rainbow_left:
    Move_Foe_Relative_XY -2 0 129
    Loop_Counter0_Back_To rainbow_left 14
    Jump_To rainbow_start
"""


def fish() -> dev_sectors.SectorSpec:
    spec = dev_sectors.standard_sector(FISH, zone=0, creatures=0)
    spec.script = fish_script()
    f = Foe
    spec.foes = [
        f(0, (300, 220), CLAM_CLOSED, CLAM_CLOSED, CLAM_CLOSED, 1, "clam_start", "quiet_hit", "cloud_ink"),                     # 0 the clam
        f(0, (240, 100), PUFFER_0, PUFFER_0, PUFFER_0 + 1, 1, "puffer_start", "quiet_hit", "cloud_ink"),                      # 1 a puffer, screen 0
        f(6, (240, 100), PUFFER_0, PUFFER_0, PUFFER_0 + 1, 1, "puffer_start", "quiet_hit", "cloud_ink"),                      # 2 a puffer, screen 6
        f(9, (240, 100), PUFFER_0, PUFFER_0, PUFFER_0 + 1, 1, "puffer_start", "quiet_hit", "cloud_ink"),                      # 3 a puffer, screen 9
        f(3, (200, 120), RAINBOW_0, RAINBOW_0, RAINBOW_0 + 1, 1, "rainbow_start", "quiet_hit", "cloud_ink"),                  # 4 a rainbow fish, screen 3
        f(5, (200, 120), RAINBOW_0, RAINBOW_0, RAINBOW_0 + 1, 1, "rainbow_start", "quiet_hit", "cloud_ink"),                  # 5 a rainbow fish, screen 5
    ]
    return spec


def _flagged(text: str, flags: dict[int, str]) -> str:
    """The sector file's text with creature `n` dormant and/or hidden: `flags` is {n: "dormant" | "hidden" | "both"}
    (`dev_sectors.Foe` writes both fields as false; the shared writer is left alone)."""
    parts = re.split(r"(?=\[sub_resource type=\"Resource\" id=\"Foe_)", text)
    out, n = [], 0
    for part in parts:
        if part.startswith("[sub_resource type=\"Resource\" id=\"Foe_"):          # (the creatures come in the order of the list)
            kind = flags.get(n)
            n += 1
            if kind in ("dormant", "both"):
                part = part.replace("dormant = false", "dormant = true", 1)
            if kind in ("hidden", "both"):
                part = part.replace("hidden = false", "hidden = true", 1)
        out.append(part)
    return "".join(out)


def write_all(dev_root: Path) -> int:
    """Writes this batch's sectors (and campaign) below `dev_root`; returns how many files were written or checked.
    Each file is written once, with its final content."""
    count = 0
    plain = dev_sectors.sector_tres
    try:
        for spec, flags in ((arena(), {5: "both"}), (closing(), {1: "hidden"}), (fish(), {})):
            dev_sectors.sector_tres = lambda sp, flags=flags: _flagged(plain(sp), flags)
            count += test_sectors.write_sector(BATCH, spec, dev_root)
    finally:
        dev_sectors.sector_tres = plain
    return count
