# The sector inspector - a manual

The screen editor changes one screen. Everything that belongs to the **whole sector** is edited in the Inspector: select
`packs/legacy/data/sectors/sector_NN/sector_NN.tres` (a sector of your own: `data/sectors/sector_NN/sector_NN.tres`) in the FileSystem dock and a panel appears above the properties (plugin
`addons/sector_editor/`, enabled in the project; it needs the screen editor plugin too, which registers the saver that writes the
file). Ctrl+Z / Ctrl+Y undo and redo every change of the panel; Ctrl+S writes the file in the importer's text (a change the
saver cannot write is refused with a message that names it, and the file stays as it was).

| Section | What it edits | Notes |
| --- | --- | --- |
| (red text) | what stops the sector from being stored as the original's | `SectorData.header_problems()` and the creature records' problems, live, e.g. "piece 1 x 33 is not on the grid" |
| Start | where the sub restarts and with which picture | even window pixels; the picture is the sub's sprite cell 0-8 |
| Neighbours | for each of the 12 screens, the screen you reach through left / right / up / down | `-` is "no neighbour"; screens that have names show them (`start_station`, `end_station`) |
| Music | `music_name`, the stem of the song's MIDI file | the game chooses the sector's song by its number (`SelectSectorMusic`, `AudioService.music_for_sector`); the line under the box says which song that is. The name is data for packs and campaigns |
| Pieces | add (at the end) and remove pieces, move one to another screen or place | at most 11, the header has 11 slots; the data canister (0) stays |
| Creatures | add (a copy of one) and remove creatures | at most 255, one count byte; the script decides what can be removed (below) |

The raw rows the panel replaces are hidden (`start_pos`, `start_frame`, the four neighbour tables, `music_name`, `pieces`,
`stale_pieces`, `foe_script_base`); the creature list `foes` stays, its rows are where a creature's picture, damage and the
three script labels are changed. Creature markers in the screen editor are the other way to move one.

**The screen editor uses the same functions.** Duplicating or deleting a creature or piece marker there calls `add_foe` / `remove_foe`
/ `add_piece` / `remove_piece` below and shows their refusals ([`SCREEN_EDITOR.md`](SCREEN_EDITOR.md), "Adding and removing"). In the editor both
tools work on one `SectorData` object (the resource cache's), so when the panel and a screen of the same sector are open, a change in
either is at once in the other: the panel refreshes on `changed`, and the screen editor adds, removes (parks) and renumbers its
markers on `changed`. `SectorEdits.new(sector, history, history_owner)` takes the object whose undo history the steps belong to (the
screen editor passes its scene root, so that Ctrl+Z in the scene undoes them; the panel passes nothing: the sector's own).
`SectorEdits.piece_insert_problems(piece)` / `piece_remove_problems(i)` / `foe_insert_problems(foe)` / `foe_remove_problems(i)` ask
"would this be allowed?" without doing it.

## The plain-object API (no editor needed)

Everything the panel does is a function on `SectorData` (`src/resources/sector_data.gd`), so the screen editor, a test or a
script can do the same. Each returns the **problems in words** and changes nothing when there are any; a change emits `changed`.

```gdscript
sector.add_piece(screen, pos, at := -1) -> Array[String]        # at the end, or inserted (never in front of the canister)
sector.insert_piece(piece: PieceData, at := -1) -> Array[String]  # an existing object (undo of a removal)
sector.remove_piece(number) -> Array[String]
sector.add_foe(screen, pos, like := -1, at := -1) -> Array[String]  # a copy of creature `like` (-1: the first that hurts)
sector.new_foe(screen, pos, like := -1) -> FoeData              # the creature add_foe would add, not in the list yet
sector.insert_foe(foe: FoeData, at := -1) -> Array[String]
sector.remove_foe(number) -> Array[String]
sector.renumber_problems(at, inserting) -> Array[String]        # what the script says about an insertion / removal
sector.foe_operand_uses() / foe_notes()                         # the script's creature operands; things worth knowing
SectorData.pieces_mask_after_remove(mask, number) / pieces_mask_after_insert(mask, at)   # a saved game's collected pieces
sector.encode_foe_buffer()                                      # count byte + records + script, as the game loads it
```

`SectorEdits` (`addons/sector_editor/sector_edits.gd`) wraps these (and the property changes: neighbours, start, music,
a piece's place) in undoable actions for an `EditorUndoRedoManager` or a plain `UndoRedo`; it is what the panel calls.

## Making a new sector

Project > Tools > "New sector..." (the same plugin) asks for a start, the empty template or a copy of any sector, and a number (the next free one from
32 up); `SectorFactory.new_from_template` / `new_from_copy` do it from code and `src/debug/new_sector.tscn` from the command line ([`EDITORS.md`](../engine/EDITORS.md),
"New sectors"). The new sector is then in `Catalog.sector_ids()`, opens in this panel, the screen editor and the overview, and is judged by "Check sector"
(there is no original to compare with, so only the playability checks apply). The tool never makes a number below 32 (`Catalog.ORIGINAL_SECTOR_COUNT`, a left-over of the original, see [`HARD_CODED.md`](../engine/HARD_CODED.md)); a pack may hold any number.

## Limits, and where they come from

- **11 pieces**: the header has slots for 11 (`SectorData.MAX_PIECES`; DESIGN 4.1). The original sectors have 7 to 11.
- **255 creatures**: the foe buffer starts with one count byte (`SectorData.MAX_FOES`; DESIGN 3.5). The original sectors have
  11 to 29. Nothing in the repository says how the original sizes its foe buffer in memory, so the count byte is the limit the
  data format proves. One more limit sits in the script language: `Put_Foe_To_Sleep` / `Wake_Foe` take a creature number 0-127
  (bit 7 means `self+N`), so creatures from 128 on can run but cannot be named by number (`foe_notes()` says so).
- The creature records are followed by the script (`foe_script_base = 1 + 34 x count`). Adding or removing a creature moves
  `foe_script_base` by 34; the script text uses labels, so it needs no change, and every creature's entry points are
  recomputed when the script compiles.

## The game's bookkeeping by number: where the numbers are used

**Pieces** are known by their position in `pieces`. Where that number is used:

| Place | What it does with the number | Effect of removing piece k |
| --- | --- | --- |
| header slot k (`SectorData.encode`) | one of 11 slots | the slots after k move up; the last freed slot is zero, or the original's left-over (`stale_pieces`, sectors 6 and 22) |
| `PieceModel.index`, `SimWorld.take_piece` | bit k of the run's mask | rebuilt from the list at every screen; nothing stored |
| `GameState.pieces_mask`, `PlayerProfile.pieces_mask` | bit k = piece k collected | **the one stored copy**: a player's record saved in the middle of a sector keeps the old numbers. `pieces_mask_after_remove/insert` give the new mask for a tool that migrates records; the game does not migrate them, but `GameState.set_sector` drops bits beyond the sector's pieces and starts the collecting over, pieces and midpoint, when the piece count differs from `PlayerProfile.pieces_total` (the count when saved): such a save resumes at the station |
| `Progression.midpoint_flag`, `pieces_missing` | looks at bits 0..n-1 and the screens of the list | follows the list |
| `PieceCounter`, `GameState.piece_total` | count of the list | follows the list |
| the data canister: `SimWorld.take_piece(0)` starts the problem of trigger slot 1; `clear_piece(0)` | piece 0 is the canister | **piece 0 stays**: it can go only when it is the last piece (the finales 30 and 31 have 0 and 1) |
| `CanisterLog` | the sector's number (`sector % 15 + 1` entries) | not piece-based |
| the math triggers of the screens | their own slots (`MathTriggerData.slot`) | not piece-based |

**Creatures** are known by their position in `foes`; the number is written in the **script**: `Put_Foe_To_Sleep` and `Wake_Foe`
take it as a number, as a registry name (which stands for a number: `Put_Foe_To_Sleep oxygen_tank`) or as `self+N`. 30 of the
32 original scripts use these (all but sectors 5 and 31). Nothing else refers to a creature by number (no trigger, no save, no HUD; `HitFoeIndex` is a
run-time value; `ReachSweep` takes creature 0 of a finale to be the treasure).

**Decision: refuse, never renumber behind the designer's back.** Inserting a creature, or removing one, anywhere but at the end
renumbers the creatures after it. `SectorData.renumber_problems` reads the compiled script: it refuses

- the removal of a creature a line names (absolute, by number or by name),
- an insertion or removal that moves a creature a line names to another number,
- an insertion or removal that changes the distance of a `self+N` from a creature that can run the line (the creatures whose
  entry points reach it, by `FoeAsm.reachable`) to its target,
- anything, when the script does not compile (it can not be checked),

and the message names the script line ("line 408, Put_Foe_To_Sleep names creature 16, which would become creature 15"). Adding
at the end is always possible; removing the last creature is possible unless a line names it. So the order of work to remove
a creature in the middle is: edit the script (change the line, or the name's number in `names/original.json` with
`tools/import/rename_name.py`), then remove the creature. The sector tools never edit `names/original.json` (the names of the
original sectors' creatures; `rename_name.py` does): a sector that adds creatures gets made-up names (`foe_30`) for them.
In the finale sectors (30, 31) creature 0 stays.

## What is tested, and what is not

`tests/engine/test_sector_editing.gd` (the data functions, the limits, the bytes of the header and the foe buffer with an added piece or
creature and the original again afterwards, the script checks, the saver, `SectorLists`, on the dev pack's sectors; the original sectors:
`tests/legacy/test_sector_editing_legacy.gd`), `tests/engine/test_sector_inspector.gd` (`SectorEdits` with undo, the panel's controls
pressed by signal, the Inspector plugin's decisions; on the original sectors: `tests/legacy/test_sector_inspector_legacy.gd`),
`tests/engine/test_screen_editor_markers.gd` (the screen editor's marker add / remove / duplicate / refuse with undo and redo, the shared
sector, the saved bytes). Not automated: clicking in the real Inspector; Ctrl+S after a panel change.
