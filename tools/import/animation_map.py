"""HAND-CURATED animation names.

The extracted bundles are *sets* of pictures, not clean animations (frames in a
set often differ in size). Real animation grouping lives in the game's code.
This file lists the groups we are fairly sure about; anything else is only
available through the indexed "all" animation.

Entries are (animation name, list of indices into the indexed "all" frame list,
loop?). Speed is always one frame per game tick (TICK_HZ).
Entries marked PROVISIONAL are guesses to be checked visually in later milestones.
"""

# Added to EVERY foes_zone*.tres (frame numbers = slot numbers there).
FOE_COMMON = [
    ("ink_burst", list(range(28, 35)), False),      # bundle 16: ink cloud grows 16 -> 96 px
    ("dolphin_swim", [0, 1, 2], True),              # ids 1161-1163, PROVISIONAL (Zoom)
]

# sub_frames.tres (bundle 15: 0-7 sub, 8 tiny, 9-12 bubbles)
SUB = [
    ("bubbles", [9, 10, 11, 12], True),
]

# station_frames.tres (bundle 18, 7 pictures) -- PROVISIONAL
STATION = [
    ("station_open", [0, 1, 2, 3, 4, 5, 6], False),
]

# Extra single-purpose sets assembled from loose NEP256 ids: name -> ids. These ids are the opening cartoon's pictures,
# so the SpriteFrames point at their one file (assets/ui/story/, pictures.py) instead of holding copies.
FX_SETS = {
    "spray": (list(range(1034, 1039)), False),            # splash at the surface
    "crew_walk": (list(range(1016, 1027)), True),         # captain figure, PROVISIONAL
    "ship_idle": ([1027], True),
}
# Bundle 22 (8 frames) = rising bubble columns.
FX_BUBBLE_BUNDLE = 22
