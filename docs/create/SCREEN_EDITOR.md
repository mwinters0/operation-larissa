# The screen editor - a manual

Change one screen of any sector, the original's or your own, with Godot's own tools: paint its tiles, move its decorations,
pieces, creatures and math triggers. What you save is the original's data format (the 0x500-byte screen record,
[DESIGN](../port/DESIGN.md) 4.1), so for an original sector the status line can tell you what differs from the original game, and a
reset brings the original back.

The editor is a plugin, `godot/addons/screen_editor/` (enabled in `project.godot`; it is not part of an exported game).

## Open a screen

Any of these, in the Godot editor with the `godot/` project open:

- **FileSystem dock**: double-click `packs/legacy/data/sectors/sector_NN/screen_MM.tres` (the original's sectors; a sector of your own is `data/sectors/sector_NN/screen_MM.tres`). (Only a double-click on the file itself does this:
  looking at a screen in the Inspector some other way, for example by clicking an entry of a sector's `Screens` list, does
  not switch scenes.)
- **Project > Tools > Edit screen...**: type the sector (any sector there is: the original's 0-31 and your own) and the screen (0-11).
- **Inspector**: with a screen file shown in the Inspector there is a button "Open sector N, screen M in the Screen Editor"
  above its properties.

The screen opens as a scene in the 2D view. Its root is a `ScreenEditor` node (look at it in the Inspector: Sector, Screen,
the two buttons, and a read-only status text). Change *Sector* or *Screen* to load another screen; changes you have not saved
are dropped. The scene file itself lives in `godot/screen_editor_work/` (git ignores it) and holds nothing but "sector,
screen": the real data stays in the `.tres` files.

## What you see

The layers are listed in the Scene dock in the order the game draws them (back to front):

| Layer | What it is | How you change it |
| --- | --- | --- |
| Background | the picture behind the screen | not editable |
| `BackDecos` | decorations behind the tiles | nodes (see below) |
| `Walls` | solid tiles | paint with the TileMap panel |
| `MidDecos` | decorations between tiles and sub | nodes |
| `Pieces` | the capsule pieces and the data canister that lie on this screen | move, duplicate, delete them (see "Adding and removing") |
| `Start` | the sub's respawn point (screen 6 only) | move it, pick the sub's picture |
| Station | the supply station the game draws on screens 0 and 11 | not editable |
| `Foes` | the creatures that start on this screen, shown with their start picture | move, duplicate, delete them, edit their record (see "Creatures") |
| `FrontDecos` | decorations in front of the sub | nodes |
| `AnimDecos` | animated decorations (also in front of the sub; the editor shows the first picture) | nodes |
| `Currents` | the water currents; the game never draws them, the editor shows them as arrows | paint |
| `Triggers` | invisible math-problem triggers, shown as a cross with their slot number | nodes |

Everything is positioned in **window pixels**: the `ScreenEditor` node stays at (0, 0), the 608 x 288 playfield starts at
(16, 32) (the blue rectangle), and the `Position` of a node in the Inspector is exactly the number stored in the file.

## Tiles

Select `Walls` or `Currents` in the Scene dock; the TileMap panel opens at the bottom with the sector's tile atlas (the
TileSet panel lists the atlases by name). Use the brush, the rectangle, the bucket, the picker, the eraser - and Ctrl+Z.

- **Walls**: paint with the atlas of the sector's zone. The cell number of the picture is stored (picture k = byte `0x40 | k`).
  Picture 0 has no art in the game: an **invisible wall** (the invisible walls along the top of a surface sector). The editor
  shows it with the hatched tile of source "Invisible wall (editor only)"; paint with that tile to make one. The game itself
  keeps drawing nothing there.
- **Currents**: paint with the arrow atlas. Column = direction (0 NW, 1 N, 2 NE, 3 W, 4 E, 5 SW, 6 S, 7 SE), row = strength
  (0 weakest). Byte `0x80 | strength << 3 | direction`. The game does not draw them; they push the sub.
- **One byte per cell**: the original keeps ONE byte for each of the 38 x 18 cells, so a cell is a wall OR a current OR
  empty. A wall in `Walls` and a current in `Currents` on the same cell is a conflict.
- What can not be stored is **reported, never converted**: a tile of another zone's atlas, a current in `Walls`, a wall in
  `Currents`, a flipped or rotated tile, a cell outside the 38 x 18 screen. The Scene dock shows a warning triangle on
  `ScreenEditor`, the status line says "CAN NOT BE SAVED" and the screen is not written until you fix it.

## Decorations, animated decorations, triggers

Each entry of the original's lists is one node, in the layer for its list. Select it, drag it in the 2D view, edit it in
the Inspector.

- Positions snap to the original's grid: x in steps of 4, y in steps of 2 (the file keeps x / 4 and y / 2 in one byte each).
- **Deco**: `Slot` (which picture; 0-69 are shared by all zones, 70 and up belong to the zone; the picture is shown live) and
  `Mirrored`.
- **Animated deco**: `Frames` (the slots shown in turn, at most 16), `Start Cursor` (where in the list it begins) and `Size`
  (the largest frame; the yellow rectangle).
  A frame list has no speed field: one entry is shown per game tick (about 12 per second) and the list loops, so the
  original repeats a picture to make it last (`62 x6, 63 x6` shows each picture for about half a second). The start
  cursor keeps identical decos side by side from blinking in step.
  **Original quirk**: sector 0 screen 1 has two byte-identical animated decos (Anim 0 and Anim 1: same position, frames
  and start cursor), the only such pair in the game. They draw on top of each other in step, so they look like one.
  In the editor clicking selects the top one (Anim 1); pick Anim 0 in the Scene dock. Deleting one is a harmless change
  that the fidelity test reports as a difference from the original.
- **Trigger**: `Slot` (0-62, which problem), `Armed`, `Rearm On Enter`, `Test Nibble`, `Other Bits` and the read-only
  `Fires When`, which the editor reads out of the game's own table (`TriggerModel.TABLE`): the test nibble and the sub's sprite
  cell decide whether the sub's x range and / or y range must contain the trigger point.
- **Add** an entry with Ctrl+D (duplicate) or "Add Child Node" (the deco classes are in the node list), **remove** it with
  Delete. **The order of the children is the order of the list in the record**: it changes the bytes, and later decorations
  are drawn over earlier ones; for triggers the first armed one that fires wins. Reorder by dragging in the Scene dock. The
  names ("Deco 3") are only labels and are not renumbered.
- Rotation and scale are not part of the original; the editor warns if you use them.

## Pieces and the respawn point

These belong to the **sector**, not to the screen (the original keeps them in the sector header), so saving a screen with a
moved piece also changes those lines of `sector_NN.tres` - and nothing else in that file.

- `Pieces`: the pieces whose screen is the one you edit. Drag them (steps of 2 in x and y). `Move To Screen` sends a piece to
  another screen when you save (it stays visible, dimmed, until the screen is reloaded; open the other screen to see it
  arrive). `Piece Index` (0 = the data canister) and `Is Canister` are read only. Adding and removing: see "Adding and removing
  creatures and pieces" below.
- `Start`: the place and sprite cell (`Start Frame` 0-8) where the sub reappears after a lost tank past the middle of the
  sector. The game puts it on **screen 6**, so that is where the node is; a sector that is started anew begins with the launch
  from the supply station on screen 0 instead.

## Creatures

Like the pieces, the creatures belong to the **sector** (the 34-byte records of `sector_NN.tres`, `FoeData`), not to the screen. Every creature that **starts**
on the screen you edit is a marker in `Foes`, named "Foe 3" after its number in the sector's creature list (the number the
script uses; it is read only and follows the creature when numbers move). The marker shows the creature's start
picture (`Start Frame`, a drop-down of the zone's picture names, mirrored if `Flip` is set) and a label with the number and the name.
Hidden creatures (not drawn until a script shows them) are faint with a dashed outline, dormant ones (asleep until a script wakes
them) are tinted blue; a creature sent to another screen is dimmed with an arrow, as a piece is.

- Drag it: positions are the record's pixels, in steps of 2 (the file keeps x / 2 and y / 2); a position below 0 is refused.
- The Inspector shows the record's fields: `Starts Dormant`, `Starts Hidden`, `Move To Screen`, `Start Frame`, `Flip`, `Frame Min` / `Frame Max`,
  `Damage` (-128 to 127; negative is friendly) and the three entry points `Start Label`, `Hit Label`, `Ink Label`, which are labels of the
  sector's `.foe` script (the drop-down suggests them; a label the script does not have is refused, like the compiler would).
  What the script does afterwards is not shown: the marker is the creature at the first tick.
- **Go to start / hit / ink label** (buttons under "Entry points") open the Foe Script screen on that line of the sector's script.
- Saving writes only the lines of the creatures you changed in `sector_NN.tres`; a screen you did not change saves byte for byte as before.

## Adding and removing creatures and pieces

A creature or piece is added or removed by adding or removing its **marker**; the sector follows, through the same `SectorData`
functions the Sector Inspector uses. What they allow and refuse, and why, is in [`SECTOR_INSPECTOR.md`](SECTOR_INSPECTOR.md)
("The plain-object API", "Decision: refuse, never renumber behind the designer's back").

- **Add**: select a marker and duplicate it (Ctrl+D in the Scene dock, or Copy / Paste): the sector gets a new creature (a copy of
  the one you duplicated, with its picture, damage and labels) or a new piece, at the end of the list. Or press **Add creature** /
  **Add piece** in the Inspector of the `ScreenEditor` node: the new one appears beside the selected marker (else in the middle of the
  playfield) and is selected, ready to drag. In both cases the new one is `Foe N` / `Piece N` with the next number.
- **Remove**: select the marker and press Delete. Creatures after it move up a number (their markers are renamed). When the sector
  refuses (the creature script names a creature the removal would move or remove, or the piece is the data canister while others
  are left), the marker is back where it was, the Scene dock's step is taken back (Ctrl+Y would repeat the Delete and be refused again), and a toast and the Output panel
  say why ("line 408 ... names creature 16, the one to remove"). Edit the script first, then the creature.
- **Undo / redo** (Ctrl+Z / Ctrl+Y in the scene) undo the sector and the markers together; the markers come back as the same nodes,
  with the changes you had made to them. (The Sector Inspector's own steps are on the sector's history, not the scene's; the
  screen editor follows them all the same, see the next point.)
- **The Sector Inspector and the screen editor work on the same `SectorData` object** (both get it from Godot's resource cache), so
  a creature added in one is at once in the other's list, and a creature the panel adds on this screen gets its marker here.
  "Revert to saved" reads the sector file again too, dropping what the panel changed and did not save.
- **Saving** writes the new count: `screen_MM.tres` as before and `sector_NN.tres` with the creature or piece blocks added or dropped
  (`SectorLists`). Adding something and removing it again, then saving, gives
  both files back byte for byte; saving without a change touches no file. The markers' values win over the sector's: a field of a
  creature changed in the Inspector's raw `foes` list while its marker is open is overwritten when you save the screen.

## Playtest the screen

**Playtest screen** (the button under *Revert to saved* on the `ScreenEditor` node, or Project > Tools > "Playtest screen...") flies
the screen you are editing in the game, from a state you choose. The screen is written first (the game is another process and reads
the files); a screen with problems is not played, the toast says why.

The dialog sets what the game would have at the start of that screen:

- **Where the sub starts**: by default the launch from the station on screen 0, the respawn point (the `Start` marker) on screen 6,
  the middle of the playfield elsewhere. Or choose the middle, typed-in coordinates, or **the playtest marker**: *Show the marker*
  puts a green copy of the sub on the screen and closes the dialog; drag it (it snaps to the sub's grid), then press Playtest again.
  The marker is not saved with the screen or the sector (Revert to saved, or another screen, removes it).
- **Air and ink**: spare tanks 0-6, oxygen 1-4, ink 0-21. **Presets**: as at the start of the sector, full, every piece but this
  screen's, low oxygen, no ink; change any value afterwards.
- **Pieces collected** (a box per piece of the sector) and the **16 creature flags** (bit 15 is the finale's).
- **Creatures** that start on the screen (and, in a text field, others): as in the file, dormant, hidden, both, or woken.

Nothing here changes a rule: the setup only sets the state the game itself can reach (the numbers of the run, the creatures'
`dormant` / `hidden`, the creature flags), and the sim then runs as always. A creature keeps its place, picture and program
counter from the file, and the sub's place is not checked against the walls; the dialog lists what the game could not give and
uses the nearest value. A lost tank or a lost game starts the playtest over (R does too) instead of restarting the sector. The
tool scene is `src/debug/screen_playtest.tscn` (keys in the header of `screen_playtest.gd`); the editor hands it the setup in the
environment variable `NEPTUNE_SANDBOX_ARGS`, the same way the Foe Script editor's *Run in sandbox* does, and you can run it by hand:
`tools/godot.sh --path godot res://src/debug/screen_playtest.tscn -- --sector=3 --screen=5 --oxygen=1 --ink=4 --pieces=5 --flags=3`
(the words are listed in `PlaytestSetup`).

## Save, revert, and what the status line says

- **Ctrl+S** saves the scene AND the screen: the editor tells the plugin, which writes the files (and what Godot saves besides is
  kept in the importer's format, see "Ctrl+S and Save All are safe"). **Save screen** in the
  Inspector of the `ScreenEditor` node does the same without saving the scene. Running the game from the editor saves a
  changed screen first. Saving writes `screen_MM.tres`, and `sector_NN.tres` only if you moved a piece, a creature or the respawn point;
  a file that would not change is not touched, so opening and saving a screen without a change leaves `git diff` empty.
- **Revert to saved** (Inspector button) reads the files again and throws your changes away.
- Saving is **not undoable** (tile painting, moving, editing are: Ctrl+Z). The way back to the original's screen is
  `uv run tools/import/reset_screens.py 3:5` (also `--all`, or a whole sector `3`), which rebuilds screens from the original records
  the importer wrote from your copy of the game (without them it says "run the importer on your copy of the game"). The piece and
  respawn-point fields of `sector_NN.tres` are put back by `uv run tools/import/reset_sector_header.py 3` (also `--all`; it leaves
  screens, creatures and scripts alone). Git cannot do this: the original sectors are in the legacy pack, which is not in the
  repository. For a sector of your own, committed under `godot/data/sectors/`, the way back is `git restore` of its files. How the
  reset tools check what they write against the original: [`FIDELITY.md`](../port/FIDELITY.md).
- The **status line** is drawn above the window rectangle in the 2D view and also shown in the Inspector:
  - `Sector 3, screen 5 - nothing to save` / `unsaved changes`: whether the nodes differ from the files.
  - (without the importer-written original bytes the status can only say `same as the original` or `differs from the original (run the importer ...)`, by comparing the SHA-256 in the committed `screens.json`)
  - `sector 32 is your own: there is no original to compare with`: a sector of the designers' own (numbered 32 or more) has no original, and that line replaces the comparison.
  - `same as the original` / `differs from the original: first difference at byte 0x1a3 (mid decos entry 3 y): expected ...`:
    the screen as it would be saved, compared byte for byte with the original game's record. Differing is the point of
    editing; the message tells you where the first change is. (The fidelity test of the legacy suite fails on an edited original
    screen for the same reason; how to keep such a change on purpose: [`FIDELITY.md`](../port/FIDELITY.md).)
  - `record: 911 / 1280 bytes`: how much of the 0x500-byte record the screen uses.
  - `CAN NOT BE SAVED: N problem(s). First: ...`: see the warnings on the `ScreenEditor` node (and on the node that is wrong).

## Ctrl+S and Save All are safe

Godot's editor does more than the screen editor when you press **Ctrl+S** or **Save All**: it also saves every resource it believes
you edited, and it believes that of every `.tres` it has loaded that has parts inside it (all twelve screens of a sector as soon as
the sector is loaded, the tileset, the project theme). Left alone it rewrites those files in its own text format (`format=4`, a
`uid=` line, `flag = false` left out, tile bytes as base64): a huge `git diff` without a single change in it. The plugin prevents
that for the data it knows:

- `screen_MM.tres` is always written in the importer's text. An unchanged screen is not touched; a changed one is written exactly
  as the screen editor writes it.
- `sector_NN.tres` is changed line by line, never rewritten. These changes are written: the respawn point (`start_pos`,
  `start_frame`), the four neighbour tables, any property of a creature (`dormant`, `hidden`, `screen`, `pos`, `frame`, `flip`,
  `frame_min`, `frame_max`, `damage`, and the three labels `start_label`, `hit_label`, `ink_label` that you edit in the Inspector,
  see [`FOE_SCRIPTING.md`](FOE_SCRIPTING.md)), a piece's `screen` and `pos`, and the number of pieces and creatures (whole lists are written again,
  see "Adding and removing").
- **What is refused.** A screen that cannot be stored as an original record (a tile byte the original does not use, a position off
  the grid, too many entries, more than 0x500 bytes: the same problems the status line lists) and a sector change outside the list
  above (the zone, a piece's `Is Canister`, the screens list ...). Nothing is written,
  the file on disk stays exactly as it was, and the editor shows an error toast and prints `res://... was NOT written: <why>`
  (naming the property) in the Output panel. Your change is still in memory: fix it (or revert it) and save again.
  Godot reports "saved" for a refused file all the same (see `ScreenFile.refuse` for why), so look at the toast.
- the legacy pack's `neptune_tileset.tres` and `themes/neptune_theme.tres` are written by Godot itself, in the text they already
  have (`step_tiles.py` writes the tileset in Godot's own format, with its uids), so a save leaves them unchanged.

If a file still shows up in `git status` after Ctrl+S, another resource type has the same problem (any generated `.tres` with parts
inside, such as `zones.tres`, is rewritten if something in the editor holds it); put it back (`git restore` for a committed file, the
importer for one of the legacy pack) and tell whoever maintains the plugin.

## The original's limits

They are explained, not lifted. A list holds at most 255 entries (one count byte). The whole record is 1280 bytes: 684 for
the tiles, one count byte per list, 3 bytes per deco, 22 per animated deco (at most 16 frames), 4 per trigger; the biggest
original screen uses 1164. Positions are in whole steps of 4 x 2 (decos, animated decos, triggers) or 2 x 2 (pieces, respawn
point) and must fit a byte (x up to 1020, y up to 510). Deco slots go to 127, trigger slots to 62.
