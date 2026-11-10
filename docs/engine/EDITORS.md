# The editor tools in code

The level editor is ordinary Godot: editor plugins in `godot/addons/`, tool scenes in `godot/src/debug/` and `godot/src/checks/`, and
plain objects underneath, so the editor, a terminal and the tests run the same functions. How to *use* the tools is in the manuals:
[`../create/SCREEN_EDITOR.md`](../create/SCREEN_EDITOR.md), [`../create/SECTOR_INSPECTOR.md`](../create/SECTOR_INSPECTOR.md),
[`../create/FOE_SCRIPTING.md`](../create/FOE_SCRIPTING.md) and the tutorial [`../create/MAKING_CONTENT.md`](../create/MAKING_CONTENT.md).
This page is how they are built. Paths are relative to `godot/`.

| Plugin (`addons/`) | Gives the editor | Built on |
| --- | --- | --- |
| `screen_editor` | a screen file opened as a scene (double-click a `screen_MM.tres`, Project > Tools > "Edit screen..." / "Playtest screen...", an Inspector button) | `ScreenEditor`, `ScreenFile` (text writer), `ScreenDataSaver` / `SectorDataSaver` (savers registered first), marker nodes `editor_*.gd`, `ScreenEditorFoeJump`, `PlaytestSetup` |
| `sector_editor` | a panel above the Inspector for a `sector_NN.tres`; Project > Tools > "New sector..." | `SectorEdits` (undo), `SectorPanel`, `SectorLists`, `SectorFactory`, `NewSectorDialog` |
| `foe_script_editor` | the **Foe Script** main screen for `.foe` files: highlighting, completion and tooltips with names and numbers, "Run in sandbox" (Ctrl+R), the paused line in the gutter | `FoeCodeEdit`, `FoeEditorPanel`, `FoeHelp` (opens `docs/create/FOE_SCRIPTING.md`), `FoeDebuggerPlugin`; `FoeAsm`, `FoeNames`, `FoeSourceMap` in `src/core/` |
| `sector_overview` | the **Sector Overview** main screen | `src/debug/sector_overview*.gd`, `SectorLayout`, `SectorReach`, `CreaturePaths`, `SectorOverviewChecks` |
| `sector_checks` | Project > Tools > "Check sector..." | `src/checks/` |
| `pack_tools` | Project > Tools > "Export pack..." / "Check pack..." / "New pack from dev..." | `src/packs/` ([`PACKS.md`](PACKS.md)) |

The Sector Inspector needs the Screen Editor plugin on, because that one registers the savers. The editor runs scripts without `@tool`
as placeholders, so every resource class the tools call into (`SpriteMetaTable`, `TriggerTable`, `ProblemType`, the screen and sector
data) carries `@tool`. Plugins start `Packs`, and its start-up check (`PackNeeds`) calls methods of the data resources it reads (`Campaign`, `ProblemType`, `VoiceCues`),
so those carry `@tool` too, and the check asks no skin (a `GameSkin` is not a tool script: `Catalog.problem_type_unskinned`). The Screen Editor plugin takes its savers out of
`ResourceSaver` when the editor announces new script classes (the editor removes every saver with a script right after) and registers them again when the editor is idle, so it
holds exactly the savers that are registered when it leaves. `tests/engine/test_editor_runs_quietly.gd` runs an export in an editor process and reads its output.

## Script debugging

`FoeSourceMap` (`src/core/foe_source_map.gd`; `SectorData.foe_line_of(pc)`) maps a creature's program counter to its `.foe` line.
`src/debug/foe_sandbox.tscn` shows every creature's current instruction and line; the Foe Script screen's "Run in sandbox" starts it with
`--sector= --screen= --foe= --pause` passed through the environment variable `NEPTUNE_SANDBOX_ARGS` (`play_custom_scene` takes no
arguments), and `FoeDebuggerPlugin` marks paused lines in the gutter over the debugger channel. Tests: `test_foe_source_map.gd`,
`test_foe_sandbox_debug.gd`.

## Adding and removing

`SectorData.add_piece / remove_piece / add_foe / remove_foe / renumber_problems` keep the original's limits (11 pieces, 255 creatures). A
change that would renumber a creature a script names is refused, never renumbered. The screen editor adds and removes by duplicating
and deleting markers. A new creature is a copy of an existing one. Tests: `test_sector_editing.gd`, `test_screen_editor_markers.gd`,
`test_screen_editor_foes.gd`, `test_sector_inspector.gd`.

## Per-screen playtest

`PlaytestSetup` holds the start state (place, air, ink, pieces, flags, creature states); `src/debug/screen_playtest.tscn` flies one screen
from it; the screen editor's "Playtest screen" dialog and an unsaved start marker set it. Creatures keep their place and program counter
from the file, and the sub's start is not checked against walls. `PlaytestSetup.apply` starts the sector on its screen through the
rules' entry `SimWorld.begin_sector_on` (the load, the screen entered, the "begin" sound; `SimWorld.begin_sector` is built from it), then
sets the flags and the creatures and places the sub. A lost tank or game starts the setup over, at the moment the game
would respawn (`ToolRun`, after the problem that cost the tank is finished). Test: `test_screen_playtest.gd` (the default setup equals the normal
start trace).

## The sector overview

`src/debug/sector_overview.tscn` (`tools/godot.sh --path godot res://src/debug/sector_overview.tscn -- --sector=7`; `[` `]` sector, `F` fit,
Ctrl + wheel zoom; `--reach`, `--paths`, `--currents`, `--checks`, `--changed`, `--zoom=`, `--screen=`, `--snapshot=file.png`) and the
editor's Sector Overview screen. All 12 screens small, laid out from the neighbour tables by `SectorLayout` (a breadth-first search from
the start screen; links that do not fit a grid are red arrows, one-way links amber, unreachable screens stand apart in a dashed frame),
with the pieces, canister, creatures, triggers, currents, launch point, start and end station on top. Overlays:

- **Reachable**: `SectorReach` (the search the reachability tests use) shows where the sub's middle can be; pieces it cannot touch are
  ringed in red.
- **Creature paths**: `CreaturePaths` runs the creatures' scripts on a private copy for N ticks (`FoeVM` only) with the sub standing still
  where you choose.
- **Checks**: runs `SectorChecks` in the background (`SectorCheckTask`) and marks each finding where it is (a ring round the object, a strip
  for a one-way door, a frame for a screen, a count per screen: red error, amber warning, blue-grey remark, grey dashed allowed); the list
  beside the map selects and scrolls to a finding (`SectorOverviewChecks` holds which finding is where). The reachability search is part
  of the checks only while Reachable is on.
- **Changed**: frames the screens that differ from the original (`SectorChanges`).

Click an object to read about it; double-click a screen to open it (in the editor: the screen editor, through
`ScreenEditorPlugin.open_screen_in_editor`; as a tool scene: zoom in). "Show the creature script" opens the Foe Script screen at the
creature's start label (`ScreenEditorFoeJump`). The map is built from the sector it shows and built again when that sector or its
creature script emits `changed` (a screen editor save, the Sector Inspector, the Foe Script screen), keeping the selected screen.
Tests: `test_sector_overview.gd`, `test_sector_overview_checks.gd`.

## Check sector

Two reports about one sector, plain objects in `src/checks/`:

- **What changed** (`SectorChanges`): what the sector differs in from the original, per kind of data with an encoder: the header, the
  creature records (field by field), the script (a line diff of the disassembly with the source, naming the label and the creatures that
  enter there), each screen, and the sprite sizes and hit rectangles of its zone; `shared_report` adds the trigger table, the default
  levels and the problem tables. It reads the original bytes in `tests/fixtures/original/` (checked against the committed hashes); without
  them it still says which records differ and asks for the importer. A difference listed in a fidelity test's `DELIBERATE_*_CHANGES` is
  shown as deliberate, with the reason ([`../port/FIDELITY.md`](../port/FIDELITY.md)).
- **Playability** (`SectorChecks`, no original bytes needed): the data fits the original's format and limits, the script assembles and
  every creature's entry labels exist, the neighbour tables lead somewhere and back and every screen is linked, the start is inside the
  screen and clear of rock, and with the reachability search the sub can touch every piece and the canister, enter the end station (or
  take a finale's treasure) and fire every trigger. Each finding is a `CheckFinding` (severity, check id, sector, screen, object, message).
  What is merely how the original is (four one-way doors, a canister in the start station's pocket) is in `SectorChecks.ORIGINAL_ALLOWED`
  with its reason, keyed by sector number.

```
tools/godot.sh --headless --path godot res://src/checks/check_sector.tscn -- --sector=3
#   every sector when none is named (--all); --file=res://data/sectors/sector_40/sector_40.tres for one file;
#   --changes / --checks pick a report; --no-reach skips the search; --shared adds the shared tables.
#   Exit code 1 when a check fails, 2 for an unknown option.
```

In the editor the reachability search runs on a worker thread (`SectorCheckTask`: `SectorReport.begin` does what touches resources on the
main thread, `search()` is the worker's part, `complete()` assembles the findings; `SectorChecks.begin` / `Pending` is the same split),
so the window stays responsive. Tests: `test_sector_changes.gd`, `test_sector_checks.gd` (broken copies of a dev sector),
`tests/legacy/test_sector_checks_legacy.gd` (the 32 originals pass), `test_sector_check_dialog.gd`.

## New sectors

There is no fixed number of sectors: `Catalog.sector_ids()` lists the `sector_NN/sector_NN.tres` folders in the `data/sectors/` of each
pack of the chain and in the project's `res://data/sectors/` (`Catalog.SECTORS_DIR`, the lowest layer; `Catalog.sectors_dir` can be
pointed elsewhere by a test). Also `has_sector`, `sector_count`, `step_sector`, `nearest_sector`, `next_free_sector`, and
`Catalog.home_dir(index)` (the first pack that has the sector, else the project's, where a new sector goes). A number goes up to
`Catalog.MAX_SECTOR` (255; the name registry has 256 sector scopes); the folder `sector_%02d` widens to `sector_100`.
`Catalog.ORIGINAL_SECTOR_COUNT` (32) and `is_original_sector(index)` name the sectors that come from the game's files;
`next_free_sector` starts at 32 and the editors refuse a lower number ([`HARD_CODED.md`](HARD_CODED.md)). A sector of 32 or more is its own
source: the importer neither writes nor deletes it and the reset and harvest tools refuse its number (`tools/import/common.py`
`refuse_new_sectors`).

`SectorFactory` (`addons/sector_editor/sector_factory.gd`) makes one and returns a `SectorFactory.Made` (`ok()`, `index`, `error`,
`path`, `files`):

```gdscript
SectorFactory.new_from_template(index := -1, zone := 0, game := 0, dir := "") -> Made   # 12 empty screens with a floor, a canister and a piece
SectorFactory.new_from_copy(source, index := -1, dir := "", source_dir := "") -> Made   # a copy of any sector that exists
SectorFactory.refusal(index, dir := "") -> String                                       # why a number cannot be used ("" if it can)
```

`index` -1 takes the next free number. A copy keeps the screens (with their provenance), creatures and script; names in the script that
mean something else in the new sector are written as numbers, and the copy must assemble to the source's bytes. The judge of a new sector
is `SectorChecks`, not the fidelity tests; a copy of an original reports that original's findings, and a copy of a finale is a finale.

```
tools/godot.sh --headless --path godot res://src/debug/new_sector.tscn -- --template --index=40 --zone=2 --game=1
tools/godot.sh --headless --path godot res://src/debug/new_sector.tscn -- --copy=5          # the next free number
```

Tests: `test_new_sector.gd` (discovery in a scratch folder, refusals, the template and copies pass the checks, a copy plays like its
original, the dialog), `tools/import/test_new_sectors.py` (the Python tools refuse a number above 31).

## Creature scripts and screens as stored files

A sector's creature script is text, `sector_NN/sector_NN.foe`, read and written by `FoeScriptLoader` / `FoeScriptSaver` as
`SectorData.foe_script`; each `FoeData` names its entry points with `start_label`, `hit_label` and `ink_label`. `SectorData.compile()`
assembles the text into the bytes `FoeVM` runs the first time the game needs them; a mistake is reported with `push_error` as
`line N: ...` and the sector's creatures stand still. Each of the 12 screens is its own file, `sector_NN/screen_MM.tres` (a `ScreenData`,
listed in `SectorData.screens`); `ScreenData.encode()` writes it back as the original's 0x500-byte record and `validate()` says what
does not fit. Label names and comments are kept apart in `res://data/sectors/foe_annotations.json` ("Store names & comments" in the Foe
Script screen, or `tools/import/harvest_foe_annotations.py`) so an import or reset writes them back. How these files are guarded against
the original and put back is [`../port/FIDELITY.md`](../port/FIDELITY.md).

## Not yet exercised by hand

The editor UI is covered by tests that call the same code and by command-line processes, but has not been driven by hand in a windowed
editor: buttons, dialogs, dragging, Ctrl+S ordering, the real `EditorUndoRedoManager`, the environment-variable launch and the debugger
channel. Dock-undo of a refused marker delete relies on English undo-step names.
