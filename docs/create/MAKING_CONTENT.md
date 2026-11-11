# Making new content

How to make your own sectors, a campaign of them, and a skin with the Godot editor and the tools of this project, and how to
share the result as a pack. Written for a teacher or a student who is comfortable with the Godot editor (scenes, the Inspector, the
FileSystem dock, plugins) and has not read this codebase.

Two other manuals come first or alongside:

- [`CONTENT.md`](CONTENT.md), "How content works": the layers (rules, content, presentation), what a campaign, a pack and a skin
  are, and where everything lives. This page does not repeat it; read it when a word here is new.
- [`LEGACY.md`](../play/LEGACY.md), "Making the original game from your copy": the importer. You need it only if you want to build on the original
  game (the `legacy` pack). The tools below work on whatever pack the game is using; with no legacy that is the **dev pack**, placeholder pictures and
  sounds under the original's names, which is enough for the whole tutorial. Where legacy and dev differ the text says so. (In the editor the dev pack is the folder
  `godot/packs/dev`. With a binary you need `dev.larissa` from the creator download, next to the game (the game reads it there; or install it from the pack screen): [`CONTENT.md`](CONTENT.md), section 4,
  "Where packs are found". Without it a pack laid over `dev`, `--pack=dev`, "New pack from dev" and an export over `--base=dev` say that dev is missing.)

This page is the hub. Each tool has its own detailed manual, and this page links to it instead of copying it:
[`SCREEN_EDITOR.md`](SCREEN_EDITOR.md), [`SECTOR_INSPECTOR.md`](SECTOR_INSPECTOR.md), [`FOE_SCRIPTING.md`](FOE_SCRIPTING.md),
[`NAMES.md`](NAMES.md), [`SKIN_API.md`](SKIN_API.md), [`TEACHING.md`](../engine/TEACHING.md) (which Godot idea each file shows), and the
engine docs for every class and option mentioned here: [`EDITORS.md`](../engine/EDITORS.md), [`PACKS.md`](../engine/PACKS.md),
[`SKINS.md`](../engine/SKINS.md), [`ARCHITECTURE.md`](../engine/ARCHITECTURE.md).

**How the page is laid out.** Part A walks one small project from nothing to a pack somebody else can install: a two-sector student
campaign called "Reef School". Part B is the same ground again as reference tables, and says how to start a pack of your own from the dev pack. Part C does the same for a skin. Part D says what you
cannot change, and where the tools are still rough. Do Part A once, in order; then use the rest as a lookup.

> **An honest word first.** The tools were written and tested without a person at the keyboard of a windowed editor. The tests press the
> buttons by signal, run the dialogs' code and start the command-line tools in processes of their own, but nobody has yet clicked
> through the screen editor, the Inspector panel, "New sector...", "Check sector...", "Export pack...", the pack screen or a skin
> by hand ([`EDITORS.md`](../engine/EDITORS.md), "Not yet exercised by hand"; the open items of [`ROADMAP.md`](../ROADMAP.md)). You may meet a rough edge. Where this page knows of
> one, it says so in a box like this one, and "Where it is rough" (Part D) collects them. When something does not work, the
> command-line twin of each tool (given beside it) is the second way in, and the file formats are plain text, so a mistake is never
> hidden from you.

---

## Contents

- [Part A: a tutorial, "Reef School"](#part-a-a-tutorial-reef-school)
  - [1. Before you start](#1-before-you-start)
  - [2. A new sector](#2-a-new-sector)
  - [3. Screens: rock, currents, decorations, pieces](#3-screens-rock-currents-decorations-pieces)
  - [4. A creature and its script](#4-a-creature-and-its-script)
  - [5. Playtest and check](#5-playtest-and-check)
  - [6. The second sector and the finale](#6-the-second-sector-and-the-finale)
  - [7. The campaign](#7-the-campaign)
  - [8. Play it](#8-play-it)
  - [9. Your own words, pictures and sounds](#9-your-own-words-pictures-and-sounds)
  - [10. Export and check the pack](#10-export-and-check-the-pack)
  - [11. Install, choose, share](#11-install-choose-share)
- [Part B: reference](#part-b-reference)
- [Part C: making a skin](#part-c-making-a-skin)
- [Part D: what you cannot change, and where it is rough](#part-d-what-you-cannot-change-and-where-it-is-rough)

---

# Part A: a tutorial, "Reef School"

You will make:

- **sector 32**, "the shallows", from the empty template: some rock, a current, a decoration, one creature that you script;
- **sector 33**, a second sector, made from the first;
- **sector 34**, the finale, from a copy of a finale sector (legacy's 30, or dev's 4; the one thing the tools cannot yet make from nothing; see step 6);
- the campaign **`reef_school`** that lists them, with its own title, canister-log entries, mission-control messages and closing words;
- a **pack** (a folder or a `.larissa` pack file) that you install and play with `--pack=`, and could hand to someone else.

A sector number is 0 to 255, and the tools give a new sector the lowest number from 32 up that no pack of the chain and no sector of the project has. Legacy holds the
original's 0-31 and dev its own 0-4 and test sectors from 100, so on either the first free number is **32**, and the tutorial says 32 throughout: use what
the tool offers. The tools pick it for you, and your sectors and campaigns go to the project's
`godot/data/sectors/` and `godot/data/campaigns/` (the packs, legacy and dev, are separate folders in `godot/packs/`, and you do not write into them).

Commands below are written for a terminal in the repository root with the project's wrapper, `tools/godot.sh` (it runs mise's Godot; any
`godot` binary works the same with `--path godot`). Almost every step also has a menu or a button in the editor, and that is the way shown first.

## 1. Before you start

1. **Know which pack you are on, and name it.** Start the game with the pack you mean: `-- --pack=legacy` (or `mise run godot:play <id>`), `--pack=dev`,
   or your own pack's id. Without the flag the game takes the first pack found in the order of the ids, which changes as soon as you install
   another pack ([section 11](#11-install-choose-share), step 3). If you built legacy ([`LEGACY.md`](../play/LEGACY.md)) and have no other pack, it is
   what the game and the editor use. With no pack the game opens on a warning screen (no pack was found, so the dev pack, which is not meant for play, is all there is; or the pack
   asked for is not there) and runs on dev, which is fine for this tutorial (in the editor and in a debug build; a release build refuses to play it). `tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --list` prints the packs found and the chain in use.
2. **Open the project in Godot 4.7.2**: in the Project Manager, import `godot/project.godot`; or from a terminal, `tools/godot.sh --path godot -e`. Let it
   import (the first time it takes a while).
3. **The plugins are already on.** `godot/project.godot` enables, under `[editor_plugins]`, these tools (Project > Project Settings > Plugins shows them):

   | Plugin (`godot/addons/…`) | What you see in the editor |
   | --- | --- |
   | `screen_editor` (Screen Editor) | Opens a screen as a scene in the **2D** view. Project > Tools > **"Edit screen..."** and **"Playtest screen..."**. A button in the Inspector of a `screen_MM.tres` file. |
   | `sector_editor` (Sector Inspector) | A panel above the properties when you select a `sector_NN.tres`. Project > Tools > **"New sector..."**. |
   | `foe_script_editor` (Foe Script Editor) | A **Foe Script** tab beside 2D, 3D and Script, for the creature scripts (`.foe` files). |
   | `sector_overview` (Sector Overview) | A **Sector Overview** tab: all 12 screens of a sector on one map. |
   | `sector_checks` (Sector Checks) | Project > Tools > **"Check sector..."**. |
   | `pack_tools` (Pack Tools) | Project > Tools > **"Export pack..."**, **"Check pack..."** and **"New pack from dev..."**. |

   The other entries (`gdUnit4`, `godot_ai`) are the test runner and an editor-integration helper; you can ignore them. If a menu item is missing,
   the plugin is off: switch it on in Project Settings > Plugins. The Sector Inspector needs the Screen Editor plugin on too, because that one
   registers the code that saves the files.
4. **A few files the tools make**: the screen editor keeps a throw-away scene for each screen you open in `godot/screen_editor_work/` (ignored by git;
   the data stays in the `.tres` files), and the pack tools write their output to `user://` (Project > **Open User Data Folder** shows where).

## 2. A new sector

Project > Tools > **"New sector..."**.

1. **Start from**: choose **Empty template**. (The other entries, "Copy of sector N", copy any sector that exists, the originals too; step 6 uses one.)
2. **Sector number**: the next free one from 32 up is filled in (32 here). A number below 32, a number already taken or one above 255 is refused with
   the reason under the fields.
3. **Zone (template)**: 0-6 choose the pictures of the tiles, decorations and creatures (0 to 4 are the five ordinary underwater zones; 5 and 6 are the
   two finale zones). Choose **0**. **Game (template)** (Voyager or Expert) is only a label the importer and the checks read; leave it.
4. Press **Create**. A toast says "Made sector 32: res://data/sectors/sector_32/sector_32.tres", the FileSystem dock selects the file and the Inspector
   shows the sector panel for it.

The same thing from a terminal ([`EDITORS.md`](../engine/EDITORS.md), "New sectors"):

```sh
tools/godot.sh --headless --path godot res://src/debug/new_sector.tscn -- --template --index=32 --zone=0
tools/godot.sh --headless --path godot res://src/debug/new_sector.tscn -- --copy=5          # a copy of sector 5, at the next free number
```

**What you got.** The folder `godot/data/sectors/sector_32/` holds `sector_32.tres` (the header: start, neighbours, pieces, creatures), `sector_32.foe`
(the creature script, nearly empty) and `screen_00.tres` … `screen_11.tres`. The template is the smallest sector the checks accept: twelve empty
screens with a floor of rock, chained left to right (each screen's right link leads to the next, its left link back), the supply station on
screen 0 and the end station on screen 11 (the game draws both itself), the data canister on screen 3 and one more piece on screen 8, and no creatures. It
already plays: swim to the pieces, take the canister, dock.

**What "its own source" means.** The files of a sector numbered 32 or more are the *only* source of that sector. The importer never writes or deletes
them (`tools/import/common.py`, `refuse_new_sectors`), the reset tools refuse its number, and the fidelity tests, which compare the originals with
hashes of the original bytes, do not look at it. The judge of a new sector is the playability check (step 5), not a comparison with the original.
This has one consequence for what you may commit or share:

- A sector made **from the template** holds nothing of the original game. It is yours; commit it and share it.
- A sector made **from a copy of one of legacy's sectors** holds the original's level bytes (its screens, creatures and script). (A copy of a dev sector holds nothing of the original.) Do not commit
  it. Either keep it out of version control (add its folder to `.gitignore`), or make the copy a *recipe*: a script that makes the copy with the same tool
  (`new_sector.tscn -- --copy=N`) and then edits its text with edits that must each find their place exactly once, so a change in the source is noticed. Say
  which in the campaign's `provenance` field (step 7).
- A pack that contains a copied sector therefore contains part of the original game's levels. Treat it like the legacy pack: keep it among people who have the game, do
  not publish it.

## 3. Screens: rock, currents, decorations, pieces

This is the screen editor ([`SCREEN_EDITOR.md`](SCREEN_EDITOR.md) is its manual; read "What you see" and "Tiles" there once).

1. **Open a screen.** Double-click `data/sectors/sector_32/screen_00.tres` in the FileSystem dock. The screen opens as a scene in the 2D view. Its
   root is a `ScreenEditor` node; its layers (`Walls`, `Currents`, `BackDecos`, `Pieces`, `Foes`, `Triggers` …) are listed in the Scene dock back to front.
   (The same works from the Inspector button "Open sector N, screen M in the Screen Editor", from a double-click on a screen in the Sector Overview, and from
   Project > Tools > **"Edit screen..."**, whose Sector box goes up to the last sector there is, yours included. The box learns of a sector made in the same
   editor session when the dialog is opened again.)
2. **Paint rock.** Select `Walls`; the TileMap panel opens at the bottom with the zone's tiles. Paint with the brush, rectangle and bucket. A cell is a wall
   *or* a current *or* empty, never two things (the original keeps one byte per cell). A wall of another zone's picture, a flipped tile or a cell off the screen
   is reported and the screen is not saved until you fix it.
3. **Paint a current.** Select `Currents`, paint with the arrow atlas: column = direction, row = strength. Currents are invisible in the game and push the sub.
4. **A decoration.** Select `BackDecos`, then Add Child Node and choose the deco class (or duplicate a deco with Ctrl+D), and set its **Slot** (the picture) in the Inspector.
   Positions snap to the original's grid (x in steps of 4, y in steps of 2).
5. **Pieces.** Select a piece in `Pieces` and drag it. Piece 0 is the data canister. To add a piece, press **Add piece** in the Inspector of the `ScreenEditor` node (11 at most).
   The pieces belong to the sector, not the screen, so saving also changes those lines of `sector_32.tres`, and only those.
6. **Save with Ctrl+S.** The status line above the screen says "Sector 32, screen 0 - nothing to save" or "unsaved changes". For a sector of your own it says
   "sector 32 is your own: there is no original to compare with" where it compares the screen with the original's, and that is as it should be.
   A change the original's format cannot hold is refused with a toast and a message in the Output panel naming the file; nothing is written and your change stays in memory.

**The sector as a whole** is edited in the sector panel of the Inspector (select `sector_32.tres` in the FileSystem dock; [`SECTOR_INSPECTOR.md`](SECTOR_INSPECTOR.md)):
the **neighbours** of each of the 12 screens (which screen you reach through left, right, up and down; the template chains them left to right, and a one-way link is
reported by the checks), the **start** (where the sub reappears after a lost tank past the middle), **Music** and the lists of **pieces** and **creatures**. Red text at the
top says what stops the sector from being stored; Ctrl+Z / Ctrl+Y undo and redo the panel's changes.

- **Music.** The drop-down lists the original's songs by the name of their MIDI file (`esect1` …). The campaign plays the song that the sector names, or its own `fallback_song` if there is none. A
  song of your own (`audio/music/<name>.ogg` in a pack) is called by typing its name into `music_name` in the sector file; the panel keeps a name that is none of the original's ("not an original song")
  but does not offer a place to type one.

**The map.** The **Sector Overview** tab shows all 12 screens small, laid out from the neighbour tables, with pieces, creatures, triggers and currents. Pick the sector with its number box. Its boxes add
overlays: **Reachable** (where the sub can get to; pieces it cannot touch get a red ring), **Creature paths**, **Checks** (every finding of step 5, drawn where it is) and **Changed** (which screens differ
from the original; empty for a sector of your own). Double-click a screen to open it in the screen editor. Tool-scene form: `tools/godot.sh --path godot res://src/debug/sector_overview.tscn -- --sector=32 --checks`.

The overview's number box goes up to the last sector there is. It learns of a sector made later in the same editor session when you come back to the tab or click the box, so
"New sector..." and then typing the new number works without restarting.

**Names instead of numbers.** Everywhere a picture, a sound, a song, a creature, a flag or a screen is chosen, the tools show a name from the registry (`godot/names/original.json`: `eel_swim_1`, `lock_tick`) with the
original's number beside it; the numbers are the original's, the names are ours ([`NAMES.md`](NAMES.md)). Names work like this in your own sector:

- *Sounds, songs, speech and texts* have one name for the whole game: use them freely.
- *Pictures* (creature pictures and decorations) are named per **zone**: a name works in every sector of that zone, so your sector 32 (zone 0) can use the zone-0 names.
- *Creatures, flags and screens* are named per **sector**, and the registry has no names for sectors of your own. In a script of sector 32 they are written as numbers or as the made-up names that
  always work (`foe_3`, `flag_02`, `screen_05`). There is no tool for adding names to a sector of your own; the registry file is hand-edited (`NAMES.md`, "Adding a name"), and it is the
  original's, shared by everyone.

## 4. A creature and its script

A creature has two halves: a **record** (where it starts, which picture, how much damage it does) in `sector_32.tres`, and a **script** (what it does, every tick) in `sector_32.foe`.
The script language and every instruction are in [`FOE_SCRIPTING.md`](FOE_SCRIPTING.md); read its section 1 once. Write the script first, because the record names labels of it.

1. **The script.** Double-click `data/sectors/sector_32/sector_32.foe` in the FileSystem dock. The editor switches to the **Foe Script** tab. Paste in the worked example of
   `FOE_SCRIPTING.md`, section 4 ("A worked example": `patrol_start`, `patrol_hit`, `patrol_ink`): a creature that paces right and left, plays a sound when touched and
   freezes when an ink pellet hits it. The editor completes instruction names and shows each operand's meaning as you type. Mistakes are listed under the text as `line N: …`; click one to
   jump there. **Ctrl+S** saves.

   > **Hand edits, not an import.** For a sector of your own the `.foe` file is the stored version and nothing regenerates it. The button *Store names & comments* is for the
   > original sectors and is switched off for yours.
2. **The creature.** Open the screen it should live on in the screen editor, select the `ScreenEditor` node and press **Add creature** in the Inspector. A marker "Foe 0" appears in the `Foes`
   layer, ready to drag (positions in steps of 2). The template has no creature to copy, so this one starts blank: in its Inspector set **Start Frame** (a drop-down of the zone's picture names),
   **Damage** (more than 0 hurts the sub; negative is friendly) and the three entry points **Start Label** `patrol_start`, **Hit Label** `patrol_hit`, **Ink Label** `patrol_ink`. A label the script does
   not have is refused. The buttons "Go to start / hit / ink label" jump to those lines in the Foe Script tab. Save with Ctrl+S.
   More creatures: duplicate the marker (Ctrl+D); each is a copy of the one you duplicated. Removing one in the middle is refused if the script names a creature by number that would move
   (`SECTOR_INSPECTOR.md`, "Decision: refuse, never renumber").
3. **Run it alone.** In the Foe Script tab, put the caret on a line of the creature's script and press the **Run in sandbox** button, or **Ctrl+R**. The editor saves the text and plays
   `res://src/debug/foe_sandbox.tscn` on your sector, opened on the screen of a creature that runs that line, with it framed. Each creature's row shows its live instruction and, under it, the `.foe` line
   it came from; Tab selects the next creature, `P` pauses, `S` steps one tick. While the sandbox is paused, the Foe Script tab marks in its gutter the line each creature is on. That is the
   debugger: step a creature through its labels and watch the gutter. A text that does not assemble is not run; the reason appears under the problems.
   From a terminal: `tools/godot.sh --path godot res://src/debug/foe_sandbox.tscn -- --sector=32 --screen=0 --foe=0 --pause`.
4. **The creature does not move, or the sector has "script" findings.** `SectorData.compile()` assembles the text the first time the game needs it; a mistake is reported as `line N: …` and the sector's
   creatures then *stand still*. Fix the line and run again.

## 5. Playtest and check

Three ways to look at it, from small to large.

**One screen, from a state you choose.** In the screen editor, the **Playtest screen** button (or Project > Tools > **"Playtest screen..."**) flies the screen you are editing. A dialog sets where the sub
starts, air and ink, which pieces are collected, the creature flags and the state of each creature; there are presets (as at the start, full, low oxygen, no ink). The screen is saved first. Keys in the
playtest: `R` start over, `P` pause, `S` one tick while paused, `-` / `=` slower / faster, `H` hit rectangles. From a terminal:
`tools/godot.sh --path godot res://src/debug/screen_playtest.tscn -- --sector=32 --screen=0 --oxygen=1 --ink=4`.

**The whole sector, flying.** Open `res://src/debug/sector_viewer.tscn`, select its root node, set *Start Sector* to 32 (and *Start Screen*), and press F6. Keys: `[` and `]` change sector (the viewer steps
through every sector of the chain and the project, yours among them), arrows change screen, `F` flight mode (arrows or WASD steer, Space fires ink, Enter opens a waiting math problem), `C` currents, `H` collision shapes,
`T` the invisible math triggers, `L` educational level, `P` the debug rectangles instead of the pictures, `O` the rectangles laid over the pictures, `F1` this list. From a terminal:
`tools/godot.sh --path godot res://src/debug/sector_viewer.tscn -- --sector=32 --fly --collisions`.

**In the game, with the debug keys.** Run the project (F5) and press **F3** in the game. It shows a read-out and switches on the cheat keys (a debug build only; an exported release deletes them): `3` take the next
missing piece (as if the sub touched it: the canister also starts its problem), `4` refill ink, `6` open a problem, `8` jump to your campaign's first finale sector, `0` finish the sector as if the lock were solved, `R` swap the pictures for the debug rectangles, `O`
lay the rectangles over the pictures, `S` put on the next skin (full list in `src/debug/game_debug.gd`; [`ARCHITECTURE.md`](../engine/ARCHITECTURE.md), "The game, scene by scene"). You can reach your sector only
through a campaign (steps 7 and 8).

**Check sector.** Project > Tools > **"Check sector..."** (or the **Checks** box of the Sector Overview). Choose sector 32 in the drop-down and press Check; the window runs the playability checks
(`SectorChecks`) and, for a sector with an original, a what-changed report. The reachability search takes a few seconds and runs on a worker thread; you can switch it off for a quick look. The window can copy the report.

```sh
tools/godot.sh --headless --path godot res://src/checks/check_sector.tscn -- --sector=32           # --file=res://data/sectors/sector_32/sector_32.tres also works
#   options after --: --all (the default: every sector that exists) / --changes / --checks / --no-reach / --shared / --pack=<id>
```

A finding reads `error: sector 32 screen 3 piece 0: …  [reach.piece]`: severity, where, what, and the id of the check.

| Severity | Means | Fails the sector? |
| --- | --- | --- |
| **error** | The sector cannot be stored in the original's format, or cannot be started, finished or reached as designed: the data does not fit its header or screen record, the script does not assemble, a creature's labels do not exist, the start is inside a wall, the canister is not first, a piece is buried in rock or off the screen, the sub cannot reach a piece, the end station or a screen, the zone does not exist. | yes |
| **warning** | Unusual, worth a look: a one-way door (a link that does not lead back), script code no creature runs, a script longer than any original's, a script that does not start where the creature records end, a math trigger the sub cannot touch. | yes: a warning that is not on the allow-list fails the sector, and the exit code of `check_sector.tscn` is 1 for it as for an error |
| **info** | A remark or a skipped check (for example "reachability search skipped"). | no |

The checks that apply to sectors 0-31 only because of how the original is (four one-way doors, a canister in the start station's pocket) are marked "allowed" and are looked up by the original's sector
**number**, so do not copy sectors 7, 13, 15 or 31 as a base for your own: the copy would report their quirks as failures. Every check id is documented at the top of
`godot/src/checks/sector_checks.gd`.

Make 32 pass (no errors or warnings) before you go on. The Pack Check of step 10 runs these same checks again, so an error here is an error there.

## 6. The second sector and the finale

1. **Sector 33**: Project > Tools > "New sector..." again, **Start from: Copy of sector 32**, number 33. A copy keeps everything: the screens, the creature records and the script (names in the script that
   would mean something else in the new sector are written as numbers, and the tool checks that the copy assembles to the same bytes). A copy of your own sector holds nothing of the original, so it is yours to
   commit and share. Change it with the screen editor and the sector panel: move the rock, the pieces, the creature. (A copy keeps the zone. For another zone's tiles make 33 from the **Empty template** with
   another zone instead and build its screens afresh.)
2. **Sector 34, the finale.** A campaign ends in a **finale** sector (listed in `finales`): one whose `finale_screen` is set, where the player takes a treasure (creature 0, whose hit script sets creature flag 15, the
   `finale` flag) and swims to that screen ([`FOE_SCRIPTING.md`](FOE_SCRIPTING.md), "The finale: bit 15"). There is no template for it. The supported way is a copy: "New sector...", **Copy of sector 30**
   (legacy's Voyager finale, number 34) or **Copy of sector 4** (dev's finale). It keeps `finale_screen`. Leave it unchanged, or change its screens and creatures like any other. This is the one place in the tutorial where your pack will contain a copy of
   the original's level data (step 2, "What 'its own source' means"). Making a finale from the template means setting the sector's `finale_screen`, making creature 0 a treasure and writing its hit script;
   the tools do not guide you through it, and I have not found a worked example other than the copies.

   > A campaign **with no finale** is legal but never ends: after the last sector the player stays on it. The pack check warns "no finale: the game never ends".
3. Run **Check sector...** on 33 and 34.

## 7. The campaign

A campaign is one `Campaign` resource (`godot/src/resources/campaign.gd`), a `.tres` in `godot/data/campaigns/`. There is no menu item for it; you make the resource in the editor.

1. In the FileSystem dock, right-click `data/campaigns/` > **New** > **Resource…**, choose **Campaign**, and save it as `reef_school.tres`.
   The file name is the campaign's id.
2. Fill in the properties in the Inspector. The fields, in the order the Inspector groups them:

   | Group / field | What to put | For Reef School |
   | --- | --- | --- |
   | `provenance` | free text: who made this and where any original-derived numbers come from | "OWN: made by hand. Sector 34 is a copy of the Voyager finale (original bytes: not committed)." |
   | `id` | the file's name, lowercase | `reef_school` |
   | Name and banner: `title` | the name of the game, shown on sign-in and the Hall of Fame (own words, or a registry text name with `title_text`) | `Reef School` |
   | `new_game_text` | the caption of the button in the new-player dialog (own words or a text name); empty uses the title | `Reef School` |
   | `banner_index` / `banner` | which HUD game picture: 0 Voyager's, 1 Expert's, or -1 to use your own `banner` picture | 0 |
   | Sectors: `sectors` | the sectors to play, in order | `32, 33` |
   | `finales` | the finale sector(s); the first is where the game ends | `34` |
   | `default_edu_levels` | the educational level 0-3 the math problems use per **zone** (a zone past the list takes the last entry) | `0, 1` |
   | Canister log: `log_series` | the digit in "ENTRY 3.02" | `3` |
   | `log_unlock_order` | which entry each sector's canister delivers: each number 1..N exactly once, N at least the number of sectors | `1, 2` |
   | `finale_log_counts` | one count per finale: how many entries its log lists | `2` |
   | `log_texts`, `log_voices` | entry n is `log_texts[n-1]`, spoken as the voice group `log_voices[n-1]` (empty = not spoken); the three lists are equally long | two sentences; `&""`, `&""` |
   | Supply station: `supply_texts`, `supply_voices` | what mission control says after each sector (one entry per sector); voice groups may be empty | two sentences; `&""`, `&""` |
   | Music and closing: `fallback_song` | the song for a sector whose own `music_name` is empty or not a song | leave `sector_song_1` |
   | `closing_scene` | leave **empty** for the generic finale (`voyager` and `expert` are the two original closings) | empty |
   | `finale_text` | the words on the generic finale screen | "Reef School is charted. Thank you, explorer." |
   | `finale_picture` | the picture on it: a registry `ui_picture` name (`title_sky`), a picture name from a pack, or a `res://` path to a PNG | `title_sky` for now |

   **Texts are a registry name or your own words.** A value that is a known text name (`game_voyager`, `log_entry_3`) is looked up in the game's strings; anything else is shown as written.
   So a student types sentences straight into the Inspector. The one trap: a sentence that is *exactly* a text name shows the original's string instead. Voices: a voice group is a name from
   a pack's `voice_cues.json` (step 9); leave it empty to have no speech. Then the supply screen only plays its jingle, and its 20 seconds start when that is over; the durations are the
   data's, never the clip's.
3. **Know what will be checked.** `Campaign.problems()` is the list the pack check reports as errors: no id, no name, no sectors, a sector listed twice or both played and a finale, an empty `default_edu_levels`,
   a level outside 0-3, log lists that do not match each other or are shorter than the list of sectors, a number of supply texts that is not the number of sectors, a `finale_picture` that is neither a name nor a file
   that exists, `banner_index` -1 with no banner. A sector belongs to **one** campaign: 32-34 must not appear in another.

> **No tool for this step.** Making and editing a campaign is the Inspector on a `.tres` file, with no wizard and no "check campaign" menu. The first place `Campaign.problems()` is printed for you is
> the pack check in step 10.

## 8. Play it

1. Run the project (F5; or `tools/godot.sh --path godot`). Skip the opening with Space.
2. On the sign-in screen, add a player: **N** (or Insert, or the New button). The new-player dialog asks for a name and then "Choose a Game Level", with one button for each campaign there is:
   Voyager, Expert and **Reef School** (on dev: the dev tour, the engine's test campaign and Reef School). Choose it.
3. **S** (or Start) launches sector 32. Collect the pieces, take the canister, dock at the end station on screen 11, solve the lock; mission control speaks (your `supply_texts`); the log
   (the canister) shows your `log_texts`. After sector 33 comes 34; take the treasure and swim to the finale screen, and your generic finale shows `finale_text` and `finale_picture`, then the Hall of Fame.
4. To see it all quickly use F3 (step 5): `3` takes the next piece, `0` finishes the sector, `8` jumps to the finale.

A player's save records the campaign id, so the player stays in Reef School; a player of a campaign that the game is not using (its pack is not in the chain) is listed as "not installed" and cannot start.

> **Never played by eye.** The campaign path is covered by tests that play a scratch campaign from the new-player dialog to the Hall of Fame through the code; nobody has played a campaign of
> their own in a window.

## 9. Your own words, pictures and sounds

Your sectors and campaign, as `.tres` files, are only half of a pack. The game of the project (step 8) reads them from where they are. Your **own pictures, sounds and texts** are read only from a pack, so you keep them in a folder laid out like a pack, and the exporter picks that folder up:

```
godot/data/campaigns/reef_school/          the PACK SOURCE FOLDER: res://data/campaigns/<campaign id>/
  texts.json                               {"reef_hello": "Hello, diver."}   new texts, or the original's said differently
  voice_cues.json                          {"groups": {"reef_log_1": ["reef_log_1_line"]}}   speech groups a campaign may name
  pictures/ui_picture/reef_finale.png      a picture by kind and name (the kinds below)
  audio/voice/reef_log_1_line.ogg          a clip by kind and name: sound, music or voice; Ogg Vorbis
  audio/lengths.json                       {"voice": {"reef_log_1_line": 300}}   lengths stated by hand, in ticks (optional)
  rules/durations.json                     {"fade": {"ticks": 20}}   durations laid over the game's, key by key (optional)
  rules/tuning.json                        {"air": {"max_oxygen": 6}}   rule values laid over the game's, key by key (optional)
```

- **Names** are lowercase letters, digits and `_`, starting with a letter, at most 40 characters. A picture or clip named like one in the pack under yours (legacy's or dev's) replaces it; a name of your own adds one.
  Picture kinds the game looks in: `ui_picture`, `background`, `problem_art`, `frame`, `deco`, `tile`. Clip kinds: `sound`, `music`, `voice`. Only `.png` pictures and `.ogg` clips
  are read; anything else is a warning from the pack check.
- **The editor's import files** (`.import`, `.uid`) next to your PNG and OGG files are left behind by the exporter.
- **Where each thing is used.** `finale_picture`: in the Campaign, give it the `res://` path of your PNG in this folder
  (`res://data/campaigns/reef_school/pictures/ui_picture/reef_finale.png`). The project can load that file, so the campaign is valid before it is exported; the exporter copies it
  into the pack as `pictures/ui_picture/reef_finale.png` and rewrites the campaign to name it `reef_finale`. A `banner` works the same way. Words are typed into the Campaign directly, or you put a text's *name* in the field and define it in `texts.json` (the name
  only resolves once the pack is in use; in the project the game shows the name itself). Voice: `log_voices` / `supply_voices` take a group name from `voice_cues.json`. A group lists clip names;
  each is a clip of the game or a file `audio/voice/<name>.ogg` in the pack. A song of your own for a sector: `audio/music/<name>.ogg`, and that name in the sector's `music_name`.
- **You will not see or hear these in the project.** Pictures, clips, texts and durations in the source folder are read only once the pack is installed and chosen with `--pack=` (steps 10-11). Until then
  a voice group names nothing and the line is silent, which is legal. Try everything in step 11.
- **Clip lengths.** A speech holds the game up for as long as the clip lasts, counted in ticks of 1/73 s. A pack's clip is **measured** when the game loads the pack (its length, rounded up to whole ticks);
  you only write `audio/lengths.json` to state a length yourself (a longer number is a pause after the line, a shorter one cuts it off). The pack check warns about a clip it cannot measure, a stated length more than a second
  or more than 25% away from the file's, and a stated length for a clip the pack does not have. Only a speech is waited for; no sound or song holds up play.
- **Durations.** `rules/durations.json` may change the lengths that hold up play: the supply station's launch, dock and balloon (`station.*`), the dissolve after a lost tank (`dissolve.ticks`), the
  canister log's scan (`log_scan.*`), `problem.message_ticks`, `calculator.key_flash_ticks`, `surface_ship.wait_ticks`, `speech.silent_ticks` (how long a speech waits with Voice switched off), `news.*`, `sign_in.*` and `fade.ticks`.
  Only keys the game's own file has are accepted (see `godot/data/rules/durations.json` for the list and the units; the station trips count ticks of the 12.17 Hz game clock, the rest ticks of the 73 Hz timer), and the numbers must make
  sense (whole, 0 or more; `fade.ticks`, `log_scan.ticks_per_picture`, `sign_in.scan_*` at least 1; a launch or dock drives right; the balloon rises). A longer dock is a changed number, and every skin plays it identically.
  [`ARCHITECTURE.md`](../engine/ARCHITECTURE.md), "Durations are data", explains each.
- **Rule values.** `rules/tuning.json` may change the numbers the rules run on: the sub (`sub`: speeds, the collision rectangles, the picture tables), the air (`air.max_oxygen`, `air.max_tanks`, `air.refill_tanks`), the ink
  (`ink.max`, `ink.in_flight_max`), the screen of the respawn point and the countdown of a math trigger (`sector.*`), the combination lock's waits (`lock_wheel.*`) and the creature scripts' instruction limit (`creatures.*`).
  State only the keys you change, e.g. `{"air": {"max_oxygen": 6}}`; `godot/data/rules/tuning.json` lists every key with its units in its `_about` note. The pack check refuses a key the game's file does not have, a number that is not whole, a table of another length, and a value the rules cannot run with (a speed, a limit or a wait of 0); it warns about an odd one (a much faster sub). A game takes the values of its pack chain when it begins,
  and every skin plays them identically. [`ARCHITECTURE.md`](../engine/ARCHITECTURE.md), "Rule values are data", explains each.

## 10. Export and check the pack

Project > Tools > **"Export pack..."** opens the **Pack tools** window. Its first drop-down **What** has four modes: *Export a campaign (a pack over another)*, *Check a pack*,
*New pack (a copy of a pack of the project)* and *Export a complete pack (data form)* (a whole pack of the project, `dev` or a copy of it, in the data form, which holds no `.tres`: a folder or one pack file).

1. **What**: *Export a campaign*. **Which**: `reef_school` (the list is every campaign `.tres` of the chain's packs and of `res://data/campaigns/`, except Voyager and Expert;
   on dev that includes `dev_tour` and `test_c`).
2. Fill **Pack id** (a lowercase word of at most 32 characters; the campaign's id by default), **Title**, **Version**, **Author**. Leave **Folder for exports** at `user://pack_exports` or point it at a folder you can find.
   Tick **one .larissa pack file** to get a single file to hand round. Leave **reachability search** on for the full check.
3. **Run**. The window starts the tool in a process of its own and shows what it prints (and the command line that is the same thing). **Copy report** puts it on the clipboard.

From a terminal:

```sh
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --export-campaign=reef_school --out=$HOME/packs --archive --title="Reef School" --author="Class 6B"
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --check=$HOME/packs/reef_school [--no-reach]     # a folder, or the id of a pack that was found
```

**What the export does.** It checks the pack first (the same `PackCheck` the pack screen uses) and leaves *nothing* behind when the check finds errors. Otherwise it writes
`<out>/<pack id>/` (or `<pack id>.larissa`): `pack.json` (the manifest), `campaigns/reef_school.json` (the Campaign as JSON), `sectors/sector_32/sector_32.json` + `sector_32.foe` for each of your sectors, and
the whole contents of the pack source folder. Your `.tres` files are not shipped; the JSON form is. The manifest names a `"base"`: the complete
pack at the bottom of the chain in use when you export (`legacy` if you built it, else `dev`); the terminal's `--base=dev` (or `--base=legacy`) says which. A pack over `dev` plays on any copy of
the game; a pack over `legacy` needs the player to have legacy too.

**Reading the report.** Errors first, then warnings. The two are not the same as in "Check sector":

| | In the pack check |
| --- | --- |
| **Errors stop the pack**: it cannot be exported or used. | A manifest that is wrong (a `base` that is not a pack id, or the pack's own). A `base` that is not found, a circle of bases, A pack with no `base` is complete, so the check asks it for everything the game needs and names what it lacks. A layout the game refuses (resources, scenes or scripts in a pack outside the project). A JSON file that is not JSON or has a field the class does not. A campaign that is not playable (the `Campaign.problems()` list above), lists a sector that is in neither this pack nor the packs under it, or shares a sector with another campaign. A sector that fails the playability checks (**the sector checks' errors**). A voice group naming a clip nobody has. A `texts.json` value that is not a string. A `.png` the engine cannot decode. A `rules/durations.json` or `rules/tuning.json` with an unknown key or a nonsense value. |
| **Warnings do not stop it**: they are doubts. | The sector checks' *warnings* of a sector (a one-way door, dead code). A clip with no measurable length, a stated length far from the file's, a stated length for a clip the pack does not hold. An odd duration (no movement, longer than ten minutes) or rule value (a sub much faster than the original, a countdown over a minute). A sector in no campaign of the pack. A voice group with no clips (that line is not spoken). A `fallback_song` or `music_name` that is no song. A `closing_scene` that is neither `voyager` nor `expert` (the generic finale plays). A campaign with no finale. A name nothing can refer to (not a valid registry-style name). Files the game never reads (a picture kind or an audio kind it does not look in; a picture that is not `.png`, a clip that is not `.ogg`; a `.sgd` script the manifest does not name). A pack that holds nothing the game reads. |

The full list is in [`PACKS.md`](../engine/PACKS.md), "Validation".

**The pack is checked as the game will use it.** The check makes the pack the chosen pack for a moment, with the packs its `base` names under it, so the names it uses, the sectors it lists and the
sector checks are the real ones, and puts the chain back afterwards. A pack may hold a sector number or a campaign id that a pack under it (or the project) already has: the nearest wins, so a pack that holds
sector 32 hides the project's sector 32 while it is in use. That is how a small pack changes a game, not an error. Your own sources (`res://data/sectors/`, `res://data/campaigns/`) are the lowest layer of
all, so the pack you exported from them answers the same data.

## 11. Install, choose, share

**On the machine that will play it** (a copy of the game with the pack the exported one is laid over: `dev` is in every copy; `legacy` is made from that person's own ISO, [`LEGACY.md`](../play/LEGACY.md)):

1. Put the pack in `user://packs/`: the pack screen does it (below), the terminal does it (`--install=PATH`), or copy a `<id>/` folder or a `<id>.larissa` file in yourself. The pack screen shows where that folder is.
   Installing refuses an id the project itself has in `godot/packs/` (`dev` too: a project without a dev pack takes the one you install).
2. In the game, on the **sign-in screen**, press **P**. The **pack screen** lists the packs found: name, where it is (the project or installed), and whether the game is using it ("in use" for the chosen pack, "base" for the packs under it). Press **Install...**
   to pick a folder or a `.larissa` pack file; **Check** runs the quick check (the sector checks without the reachability search) and shows the report. An installed pack never runs code: it holds JSON, `.foe` text, PNG and OGG, read by the game's own
   readers. (A small **Packs** button also appears beside the list once a pack is installed, so a game with no pack installed looks exactly as the original did.)
3. **Choose it:** start the game with `--pack=reef_school` (`tools/godot.sh --path godot -- --pack=reef_school`). There is no switch on the pack screen; the game uses one pack and the packs under it. Without the flag, the first pack
   found by id is used, and `legacy` sorts before `reef_school`, so the flag is how you get the pack you installed.
4. **Reef School** is now a button in the new-player dialog. **Remove** (on the pack screen) deletes the pack. A record of a pack's campaign whose pack is not in use waits, unplayable, until it is back.

The same from a terminal: `--install=/path/reef_school.larissa` (also `--uninstall=`, `--list`, `--check=`). The pack tool runs the options in the order install, uninstall, new, check, export, list.
The exit code is 1 for an error or a failed step, 2 for a bad option.

**Sharing.** Hand the `.larissa` pack file (or the `reef_school` folder) to a classmate. They need the same game version, the pack your pack is laid over (named above) and the steps above. The things that go wrong:

- **Numbers are shared.** All the packs of a chain share one number space (0 to 255), and a campaign id must be unique too. Two packs that both use sector 32 cannot be told apart: the one nearest the top wins, silently. In a class,
  give each author a range (say 40-49, 50-59, ...) *before* they start; renumbering later means redoing the sector.
- **A pack that holds a copy of an original sector** carries original level data: keep it among people who own the game (step 2).
- A **skin mod** (Part C) is a pack with a script, run in a sandbox that lets it do nothing but say what to draw; a pack never runs code outside that sandbox. A mod pack can also draw the screen of a problem type it adds, or of an original one ([`CONTENT.md`](CONTENT.md), "Problem screens").

The pack format, in case you want to write or edit one by hand, is the tree in [`CONTENT.md`](CONTENT.md), section 4, "The layout of a pack"
(`pack.json`, `campaigns/`, `sectors/`, `texts.json`, ...), and the JSON forms in [`PACKS.md`](../engine/PACKS.md).

---

# Part B: reference

## B1. Which tool, which file

| You want to change | Tool | File it edits | Manual |
| --- | --- | --- | --- |
| A new sector's existence | Project > Tools > "New sector..." (or `new_sector.tscn`) | `data/sectors/sector_NN/` (all files) | here, step 2 |
| Rock, currents, decorations, triggers, one screen's pieces and creatures | Screen Editor (2D view) | `screen_MM.tres`, and the sector's lines for pieces, creatures, respawn | [`SCREEN_EDITOR.md`](SCREEN_EDITOR.md) |
| Neighbours, start, music, adding/removing pieces and creatures, a creature's picture and damage and labels | Sector panel in the Inspector | `sector_NN.tres` | [`SECTOR_INSPECTOR.md`](SECTOR_INSPECTOR.md) |
| What a creature does | Foe Script tab | `sector_NN.foe` (+ the three labels in `sector_NN.tres`) | [`FOE_SCRIPTING.md`](FOE_SCRIPTING.md) |
| A bird's-eye view, reachability, creature paths, where the checks complain | Sector Overview tab | nothing (read-only) | [`EDITORS.md`](../engine/EDITORS.md), "The sector overview" |
| Whether a sector can be played | Project > Tools > "Check sector..." | nothing | here, step 5 |
| A campaign | the Inspector on a `Campaign` `.tres` | `data/campaigns/<id>.tres` | here, step 7 |
| A campaign's own words, pictures, clips, durations | files in a folder | `data/campaigns/<id>/…` | here, step 9 |
| A pack out of it | Project > Tools > "Export pack..." / "Check pack..." | `<out>/<pack id>/` or a `.larissa` pack file | here, steps 10-11 |
| A whole game of your own, from the dev pack | Project > Tools > "New pack from dev..." (or `pack_tool --new`) | `godot/packs/<id>/` | here, B4 |
| How it looks | a `GameSkin` resource | `skins/<id>/` | Part C, [`SKIN_API.md`](SKIN_API.md) |

## B2. Sector numbers and what each tool lets you do with them

| | |
| --- | --- |
| 0-255 | The range (`Catalog.MAX_SECTOR` is 255; the registry has 256 sector scopes). A pack may hold any of them; the nearest pack of the chain wins. |
| below 32 | The tools never make a sector here ("New sector..." refuses it: `Catalog.ORIGINAL_SECTOR_COUNT`, a left-over of the original, [`HARD_CODED.md`](../engine/HARD_CODED.md)). Legacy has the original's 0-31; dev has 0-4 and its test sectors from 100. |
| 32 up | A new sector gets the lowest number that no pack of the chain and no sector of the project has. |

Limits that come from the original's data format, enforced by the tools and the checks (`SECTOR_INSPECTOR.md`, "Limits"): 12 screens per sector; a screen is 38 x 18 tiles and at most 1280 bytes
as a record (684 of them tiles); at most 255 of any list on a screen; **11 pieces** per sector (the first is the data canister); **255 creatures** per sector, though a script can name only creatures 0-127 by number; a deco
slot up to 127, a math trigger slot 0-62.

## B3. The Campaign fields

See the table in step 7; the field documentation is in `godot/src/resources/campaign.gd`. Methods the game calls on it: `is_finale`, `position_of`, `next_progress`, `default_edu_level`, `log_count`,
`log_entries`, `supply_text_name`, `song_for`, `display_title`, `problems`. `Catalog.campaign_problems()` adds "a sector in two campaigns".

## B4. Making a pack: a copy of dev, or a pack laid over another

**A whole game of your own: copy dev.** The dev pack is a complete pack with a file for every file of legacy's `assets/` and `midi/`, all placeholders. Copy it and replace its files one by one:

```sh
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --new=orchard --from=dev --title="Orchard"
tools/godot.sh --headless --path godot --import               # or just open the project in the editor
tools/godot.sh --path godot -- --pack=orchard                 # play it
```

`--new` copies `godot/packs/dev` to `godot/packs/orchard`, points the files at the new folder, gives every file that has a uid a new one (a plain copy would clash with dev's) and writes a `pack.json`
with the new id and title and **no `base`**: the copy is complete. The editor has the same in Project > Tools > "New pack from dev..." (the Pack tools window, mode *New pack*). It refuses an id that is
taken or `dev`. Then:

- Replace a picture by saving yours over the file with the same name; replace a sound the same way. Dev's tables (`data/sprite_frames`, `data/sprite_meta`, the layouts) match the sizes of dev's pictures,
  so a picture of another size needs its table changed too. `tools/dev_pack/README.md` says what the generator keeps (the sub 96 x 58, a piece 24 x 20, the 608 x 288 playfield).
- Edit its sectors in place: open the files under `godot/packs/orchard/data/sectors/sector_NN/` in the FileSystem dock with the editors above. Its campaign is `data/campaigns/dev_tour.tres`, its texts are the tables in `data/problems/`.
- The copy also holds dev's engine-test content: the campaign `data/campaigns/test_c.tres` and the test sectors 100-199 (`data/sectors/sector_100/` ...). Nothing of your game needs them; delete them
  ([`tools/dev_pack/README.md`](../../tools/dev_pack/README.md), "Test sectors", says what they are).
- `pack_tool --check=orchard` checks it. `godot/packs/` is git-ignored except `dev/`, so a pack you put there stays out of your history unless you add it (a `!/godot/packs/orchard/` line in the root `.gitignore`).

**A small pack over another.** A campaign exported in step 10 is a pack with a `base`: `{"id": "reef_school", "base": "dev", ...}` (or `"base": "legacy"`) plus JSON sectors, a campaign, texts, pictures, clips and
problem types. It is a tree of files you can also write by hand ([`CONTENT.md`](CONTENT.md), section 4, "The layout of a pack", which also gives the manifest). A pack that names a `base` that is not found, or has no `base` and lacks what the game needs, is refused by the check;
the game, started with such a pack, falls back on dev and says so on its warning screen. A pack outside the project cannot hold `.tres` files, scenes or scripts; it holds the JSON of a `.tres` instead
(the data form); a pack that needs the files themselves lives in `godot/packs/` and is part of the project.

**Installing and choosing.** Installed packs live in `user://packs/` (the pack screen, P on the sign-in screen, or `pack_tool --install=PATH`); the project's own are in `godot/packs/`. The game uses **one** pack and the
packs under it: `-- --pack=<id>` chooses, and without it the first pack found by id is used. `pack_tool --list` shows the packs found and the chain in use. A game shipped to someone else carries no pack; a player
who has `legacy.larissa` puts it next to the game (or in `user://packs/`, or the pack's folder there) ([`LEGACY.md`](../play/LEGACY.md)). More in [`CONTENT.md`](CONTENT.md), section 4, "Installing and checking packs".

The manifest, `pack.json`, is written for you by the exporter and by `--new`; its fields are in [`CONTENT.md`](CONTENT.md), section 4.
Problem types (`data/problems/problem_type_NN.json`) are the one piece of game data a pack outside the project may replace; there is no tool for writing one, it is JSON by hand in the form `ResourceJson` reads
(one key per `@export` field of `ProblemType`).

## B5. The command-line tools in one place

All from the repository root; the arguments after `--` belong to the scene.

| Scene | Options |
| --- | --- |
| `res://src/debug/new_sector.tscn` | `--template` / `--copy=N`, `--index=N`, `--zone=Z`, `--game=G`, `--dir=DIR` (where to write), `--source-dir=DIR` (where `--copy` reads) |
| `res://src/checks/check_sector.tscn` | `--sector=3,7` / `--file=PATH` / `--all`, `--changes`, `--checks`, `--no-reach`, `--shared`, `--pack=ID` |
| `res://src/packs/pack_tool.tscn` | `--list`, `--check=WHERE`, `--no-reach`, `--export-campaign=ID`, `--export-pack=ID`, `--archive-folder=DIR`, `--out=DIR`, `--archive`, `--pack-id= --title= --version= --author= --description= --base=ID`, `--install=WHERE`, `--uninstall=ID`, `--new=ID --from=PACK`, `--pack=ID` |
| `res://src/debug/sector_viewer.tscn` | `--sector= --screen= --fly --currents --collisions --level= --skin= --presenter=debug_rects --overlay --ticks= --snapshot=PATH` |
| `res://src/debug/sector_overview.tscn` | `--sector= --screen= --zoom= --reach --paths --currents --checks --changed --snapshot=PATH` |
| `res://src/debug/foe_sandbox.tscn` | `--sector= --screen= --foe=N --pause --fly --touch=N --ticks= --snapshot=` |
| `res://src/debug/screen_playtest.tscn` | `--sector= --screen= --oxygen= --ink= --pieces= --flags=` (the rest are in `PlaytestSetup`) |
| `res://src/debug/skin_compare.tscn` | `--skin= --sector= --screen= --fly --overlay --ticks= --snapshot=PATH` |
| `res://src/skins/skin_templates_tool.tscn` | `--out=DIR`, `--pack=ID`, `--list` (`mise run skin:templates`; one PNG per replaceable picture, `ui_picture/`, per console layer a script draws, `hud_layer/`, and for a problem-screen mod the frame and panels, `problem_art/`, and the window, `problem_layer/`) |

---

# Part C: making a skin

A skin changes how the game *looks*, never how it *plays*: every skin is checked to give the same events at the same ticks as the original skin. What a skin is, and why, is in [`CONTENT.md`](CONTENT.md); what a skin is
*given* by the rules (28 events, the state calls, the rules a presenter keeps) is [`SKIN_API.md`](SKIN_API.md). This part is the how-to.

## C1. What a skin can contain

A skin is a `GameSkin` resource, `res://skins/<id>/skin.tres`, in a folder of the same name (`godot/skins/original/` and `creatures/` are the two that exist). Its fields
(`godot/src/skins/game_skin.gd` documents them all):

| Field | What it does |
| --- | --- |
| `id`, `display_name` | the id (must equal the folder name) and what a menu would show |
| `fallback` | another skin to build on; empty means the original |
| `pictures` | a dictionary from a picture **key** to a `Texture2D` (`ui_picture/title_sky`, `frame/dolphin_swim_0`, `deco/coral_fan_cyan`, `tile/zone0_tiles`, `background/bg_s00_00`, `problem_art/log_scan_0`, `frame/sub_00`) |
| `art_folder`, `art_scale` | a folder of PNGs named by key (`<art_folder>/frame/sub_00.png`), drawn at 1 / `art_scale` of their size so 4x art is drawn sharp at the original's size. `pictures` wins over the folder for a key both have |
| `resources` | a whole presentation data resource instead of the original's (`ui/hud_layout`, `problems/screen_layout`, `sprite_frames/…`, `neptune_tileset`). Only those: a key that names rules or content is ignored |
| `presenter_scene` | the scene that shows a sector; its root extends `SectorPresenter` (inherit from `res://src/gameplay/original_presenter.tscn`) |
| `render` | filtering and pixel snapping (`RenderSettings`) |
| `hud_labels` | the HUD's words as `Label` text with your font (`HudLabels`) |

A **key** is `<kind>/<name>`. To find the key of a picture you want to redraw, look at its file in the pack you build on (`godot/packs/legacy/assets/`, or `godot/packs/dev/assets/`, which has the same paths): `assets/ui/title/title_sky_1039.png` is `ui_picture/title_sky` (the importer's trailing
number is dropped when the picture has a real name; a made-up name such as `ui_1189` keeps it); `sprites/foes/…` is `frame/…`, `sprites/decos/…` is `deco/…`, `tiles/…` is `tile/…`, `backgrounds/…`
is `background/…`, `problem_art/…` is `problem_art/…`; the sub, pieces, station and bubbles are `frame/sub_00` and similar. `GameSkin.key_of(path)` does exactly this. A picture that is the *content's* and that a pack of the chain
supplies wins over every skin.

## C2. Make one

1. In the FileSystem dock make the folder `res://skins/reef/`. Right-click it > **New** > **Resource…** > **GameSkin**, save as `skin.tres`. In the Inspector set `id` to `reef` and a `display_name`.
2. Start with one picture. Add an entry to `pictures` (key `ui_picture/title_sky`, value a PNG you drew), or put PNGs in a folder and point `art_folder` at it (for same-size pictures `art_scale` 1;
   for pictures four times as large 4). Anything you do not map is the original's.
3. For a change to how a sector is *drawn* (animation, shaders, a different sub), make a presenter: right-click `res://src/gameplay/original_presenter.tscn` > **New Inherited Scene**, save it in
   your skin's folder, attach a script that extends `OriginalPresenter` and overrides what you need, and set the skin's `presenter_scene`. `skins/creatures/` is the worked example. (A skin that only dresses the original presenter needs no scene: it is a skin pack, `examples/packs/modern/`, a manifest with a shader and a font; [`FIRST_SKIN.md`](FIRST_SKIN.md) walks through it.) A presenter written only against the skin API (`view`) is guaranteed not to change a trace ([`SKIN_API.md`](SKIN_API.md)).
4. For text in your own font, give `hud_labels` a `HudLabels` resource.

## C3. Try it

- **Run the game in it**: `tools/godot.sh --path godot -- --skin=reef`. The id is the folder name. An unknown id is a loud error and the original is used.
- **Switch while playing**: in a debug build press **F3**, then **S**: the next skin (original, then every folder of `res://skins/` with a `skin.tres`, then the original again). The game goes on as it was.
- **See what the rules test**: press **O** (after F3 in the game; plain `O` in the sector viewer; or `-- --overlay`) to lay the debug rectangles over your pictures: the walls, the sub's hurt rectangle and wall box,
  each creature's hit rectangle, the pellets, pieces, triggers and the dock. A picture should cover its rectangle. `R` (game, after F3) or `P` (viewer) swaps the picture for the rectangles.
- **Compare with the original**: `res://src/debug/skin_compare.tscn` runs one sector and shows it twice, the original on the left and your skin on the right (two 640 x 400 viewports bound to the same rules). Open it and press F6, or
  `tools/godot.sh --path godot res://src/debug/skin_compare.tscn -- --skin=reef --sector=32 --fly --overlay`. Keys: `[` `]` sector, arrows screen, `F` fly, Space pause, `,` `.` or the drop-down for the skin on the right, `O` the
  rectangles over both halves, `L` level, `F1` help.
- **The tests are free**: every skin in `res://skins/` is played against the original skin over several sectors of the dev pack and through a whole mission by the existing tests (`tests/engine/test_plays_identically.gd`,
  `test_skins_dont_change_the_game.gd`), with no step for you. `tools/run_tests.sh tests/engine/test_plays_identically.gd tests/engine/test_skins_dont_change_the_game.gd` takes about 15 seconds.

## C4. Share it as a mod pack

A skin of the project is a folder of `res://skins/`, code of the project. To give a skin to other people, write it as a **skin mod**: a pack whose script returns what to draw, run in a sandbox ([`SKIN_API.md`](SKIN_API.md), "Writing a skin mod"). It holds the script, its pictures in `skin/`, and shaders as text; it is exported, checked and installed like
any pack (step 10: `pack_tool --check=<folder>`, `--install=`), it needs the godot-sandbox extension (`mise run setup`), and installing it asks no trust question because all it can do is bounded: its picture is drawn by the game, and what it adds to the rules it adds only for a campaign that declares it, at hooks where the game checks and cuts every answer ([`CONTENT.md`](CONTENT.md), "Rule hooks").
`--pack=<id>` chooses it (laid over the game pack it names as `base`), and `--skin=<id>` or F3-then-S wears it. It lasts as long as its pack is in use.

**Limits.**

- **A mod skin is not a project skin.** It draws rectangles, lines and pictures (`SKIN_API.md` lists them), not scenes, animation trees, 3D models or fonts, and it keeps the game's HUD, screens and sounds. `skins/creatures/` is a folder of the project and is not shared as a pack; `examples/packs/modern/` is a skin pack with no script.
- **No player menu.** The pack screen does not choose a skin. A player picks it with `--skin=<id>` on the command line; F3-then-S is a debug build feature.
- **Art you make from the original's art is the original's.** A skin you share should have pictures you drew yourself.
- **Some things cannot be skinned one by one yet** ([`ROADMAP.md`](../ROADMAP.md)): creature and decoration pictures that the registry has not named share one key; tiles and backgrounds have no 4x path;
  there is no supported hook for "this skin draws creature N". (Filtering can be set for the playfield apart from the rest: `RenderSettings.playfield_filter`, [`SKINS.md`](../engine/SKINS.md).)

---

# Part D: what you cannot change, and where it is rough

## D1. What you cannot change

The game has three layers (CONTENT.md). Content and presentation are yours; the **rules** are not:

- The 12.17 Hz game tick, the integer 640 x 400 coordinates, the tile-scan walls and the hit rectangles, the creature VM and its instruction set (the 25 instructions of `FOE_SCRIPTING.md`), the zone and trigger tables, what a math
  trigger's slot asks, and the story and closing timelines. A skin or a pack cannot reach them; a skin that tries to
  replace one is ignored and a test would catch a presenter that changed a trace.
- Anything a pack outside the project may not hold: `.tres` files, scenes and scripts but for a mod's sandboxed `.sgd` (a pack in the project may hold them, as part of it).
- Fixed shape: screens per sector, tiles per screen, limits of the data format (B2).

What you *can* change without touching a rule: sectors, screens, creatures and their scripts (within the VM), campaigns and their words, your own pictures, clips, songs and speech, the durations that hold up
play and the values the rules run on, the sub's speed, the oxygen and ink limits and the like (step 9), and presentation.

**Asking for a rule to change.** Mod packs that add gameplay (code in the sandbox that runs inside the tick, declared so the
original campaigns provably do not use it) are planned ([`ROADMAP.md`](../ROADMAP.md)), **not built**; a mod pack can draw a skin ([`SKIN_API.md`](SKIN_API.md)) and the screen of a problem type, its own or an original one ([`CONTENT.md`](CONTENT.md), "Problem screens"). So the way to ask is to tell whoever maintains the project what behaviour you want, in terms of
what the player sees and which rule it adds to, not changes. A change to how an *existing* rule works (fractional movement, another tick rate, larger screens, scripts as scenes) is not an extension but a different game, and the
roadmap says that belongs in a separate project that takes this one as its specification.

## D2. Where it is rough

Collected from [`EDITORS.md`](../engine/EDITORS.md), the open items of [`ROADMAP.md`](../ROADMAP.md) and from reading the code for this page:

- **Never used by hand in a windowed editor:** the screen editor (buttons, dialogs, dragging, Ctrl+S ordering, undo with the real `EditorUndoRedoManager`, the debugger channel), the Sector panel, "New sector...", "Check sector...",
  "Export pack..." and "Check pack...", the pack screen. They are covered by tests that call the same code and by command-line processes.
- **Never played by eye:** a campaign of your own, a skin mod, the debug-rectangles presenter through a whole real-time session, the example skin pack `modern` and the `creatures` skin through a whole session.
- **Things with no editor tool, only files or the Inspector on a `.tres`:** a campaign (step 7); the pack source folder (step 9); a finale sector from the template; names for your own sector's creatures, flags and screens; a
  song of your own in a sector's `music_name`; a replacement math problem type; a skin (C2).
- **Existing creatures only:** a new creature is a copy of an existing one (or a blank record in a sector with none).
- **Story timelines are not replaceable by a pack outside the project** (the opening, the news, the closings; a complete pack has its own news cartoon); only the generic finale is yours.
- **The pack screen has no export** (that is the editor and the terminal); **there is no per-skin menu for the player.**
- **The engine still assumes some of the original** (the first free sector number is 32, `voyager` and `expert` are special campaign ids, the durations file holds the original's numbers): the list is
  [`HARD_CODED.md`](../engine/HARD_CODED.md).
- **Voice transcripts and the original's clip lengths** are the legacy pack's business ([`LEGACY.md`](../play/LEGACY.md)).

When something here is wrong, the quickest way to find out is the report the tool prints and the header comment of its source file, which every tool has (`godot/src/packs/pack_tool.gd`,
`godot/src/checks/check_sector.gd`, `godot/src/debug/new_sector.gd`).
