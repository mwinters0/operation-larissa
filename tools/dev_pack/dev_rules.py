"""The dev pack's rule values: `rules/tuning.json`, a layer over the project's `data/rules/tuning.json` (the original's numbers).

Every value is DIFFERENT from the original's, so that an engine test, which runs on the dev pack, fails wherever the code still reads an
original number instead of the run's. The pick keeps `Tuning.check` quiet (no error, no warning: the console of the original has places
for 4 cells, 6 tanks and 21 pellets, so those go down), and keeps the dev sectors playable. A later rule value in the project's file
needs a line here, or a reason in `godot/tests/engine/test_dev_rule_values.gd` (`OMITTED`). Written by make_dev_pack.py.

Teaches: a pack states only what it changes. The per-cell and per-picture tables of the sub are the project's (the pictures of dev are
the original's sizes); `wall_box` is the one table the layer changes.
"""
from __future__ import annotations

import json

from devlib import DEV, write_text

# section -> key -> dev value (the original's in the comment)
TUNING: dict[str, dict[str, object]] = {
    "sub": {
        "tick_hz": 12.5,                  # 12.166667
        "max_speed_x_units": 112,         # 128
        "max_speed_y_units": 80,          # 96
        "accel_units": 10,                # 12
        "decay_units": 4,                 # 6
        "wall_box": [8, 10, 76, 32],      # [8, 10, 80, 32]: four pixels narrower, so every place the original's sub fits, this one does
        "invulnerability_ticks": 28,      # 30
        "blink_ticks": 18,                # 22
        "bubble_ticks": 6,                # 8
        "ink_steps_per_tick": 4,          # 3
    },
    "air": {"max_oxygen": 3, "max_tanks": 5, "refill_tanks": 3},                 # 4, 6, 2
    "ink": {"max": 18, "in_flight_max": 3},                                      # 21, 2
    "sector": {"midpoint_screen": 10, "pending_ticks": 30, "canister_pending_ticks": 3},   # 6, 36, 2
    "lock_wheel": {"ticks_per_position": 7, "key_window_ticks": 60, "max_passes": 3},     # 9, 73, 2
    "creatures": {"max_instructions_per_tick": 400},                              # 512
}

ABOUT = ("Dev pack: its own rule values, every one different from the original's (the file the project holds in data/rules/tuning.json). "
         "A key left out keeps the base file's: the per-cell and per-picture tables of the sub are the base's.")


def write_all() -> int:
    layer = {"_about": ABOUT, **TUNING}
    write_text(DEV / "rules" / "tuning.json", json.dumps(layer, indent=2) + "\n")
    return 1
