# Writing creature scripts

A short manual for level designers. It describes how the creatures ("foes") of a sector are
driven by small programs, the text format you write them in, and every instruction.

Everything here comes from the source: `godot/src/core/foe_vm.gd` (the interpreter),
`godot/src/core/foe_ops.gd` (the instruction table and names), `godot/src/core/foe_asm.gd`
(the text assembler) and [`DESIGN.md`](../port/DESIGN.md) section 3.5. Where the source does not settle a
question, the text says so.

## 1. How scripts run

### One script per sector, one program counter per foe

A sector has **one shared script**: a long run of instructions. You write it as text
(a `.foe` file, section 2); the game assembles that text into bytes
(`SectorData.foe_bytecode`) the first time it needs them.
Every foe has its own **program counter** (`pc`), the place in that script where it will read
its next instruction. Foes can run different parts of the same script, or even the same part
at different times. A foe never shares its `pc` with another foe.

### All the state, and where it lives

Everything a script reads or changes is in one of three places. The rest of this section explains how
each piece is used; this list is here so you can look up what belongs to whom.

**Per sector, shared by all its foes, read-only.** (`SectorData`)

"Bool" means a plain yes/no. A *byte offset* is a position in the original game's creature buffer:
`foe_script_base` is the offset of the script's first byte, so `pc - foe_script_base` indexes `foe_bytecode`.

| What | Source name | Type | Notes |
|---|---|---|---|
| The script | `foe_bytecode` | bytes | One run of instructions for the whole sector (section 2). Never changes while the game runs. |
| Where it starts | `foe_script_base` | byte offset | |

**Per sector, shared by all its foes, changing.** (`FoeVM.Context`, one per sector, owned by `sim_world.gd`)

| What | Source name | Type | Set by | Read by |
|---|---|---|---|---|
| 16 global flags | `semaphore` | 16-bit bit field, one bit per flag (original: the u16 `FoeSemaphore`) | `Set_Flag`, `Clear_Flag` | `If_Flag`; the game reads bit 15 (see "Global flags") |
| The sub's position | `sub_x`, `sub_y` | int, window pixels of the picture's top-left corner | the game, before the foes run each tick | `If_Sub_X_...`, `If_Sub_Y_...` |
| The screen being shown | `current_screen` | int, 0 to 11 | the game, when the sub changes screen | whether a foe runs; whether `Play_Sound` plays |
| Random numbers | `rng` | random number generator | | `If_Random_Greater` |
| Requested sounds | `sounds` | list of sound numbers | `Play_Sound` | the game, after the foes' turns (then emptied) |
| The list of foes | `foes` | list of `FoeVM`, in sector order | | `Put_Foe_To_Sleep`, `Wake_Foe` (by number) |

**Per foe.** (`FoeVM`, one per foe; the starting values come from the foe's `FoeData` record in the sector's `.tres`)

*What defines a foe.* Fixed for the foe's life; no instruction changes these.

| What | Source name | Type | Notes |
|---|---|---|---|
| Number in the sector's list | `index` | int, 0 to 127 | `self` in creature references means this |
| Hit and ink entry points | `script_hit`, `script_ink` | byte offsets | from `hit_label`, `ink_label` |
| Contact damage | `damage` | int: oxygen lost on contact | 0 = harmless; negative = friendly (refills air) |

*Game state per foe.* What the script changes as it runs.

| What | Source name | Type | Changed by |
|---|---|---|---|
| Program counter | `pc` | byte offset | every instruction; starts at the start entry point |
| Position | `x`, `y` | int, window pixels of the picture's top-left corner | the three move instructions; restored by an interrupt's `Return` |
| Screen | `screen` | int, 0 to 11 | `Move_Foe_To_Screen_XY` |
| Picture | `frame` | int, 0 to 127 | `Set_Frame`, the move instructions; restored by an interrupt's `Return` |
| Mirrored | `flip` | bool | the same as `frame` (bit 7 of their `frame` operand) |
| Frame range | `frame_min`, `frame_max` | int, 0 to 255 each | `Set_Frame_Range` |
| Hidden | `hidden` | bool | `Hide_Foe`, `Show_Foe` |
| Dormant (asleep) | `dormant` | bool | `Put_Foe_To_Sleep`, `Wake_Foe`, from *any* foe |
| Three loop counters | `_counters[0]`, `[1]`, `[2]` | 16-bit int each | `Loop_Counter0/1/2_Back_To`; start at 0 |
| One return slot | `_return_pc` | byte offset | `Call_Subroutine`; starts at the start entry point |
| Interrupted | `interrupted` | bool | set by a hit or ink; cleared by `Return` or by any `Put_Foe_To_Sleep` the foe itself runs |
| Saved state of an interrupt | `_saved_pc`, `_saved_x`, `_saved_y`, `_saved_frame`, `_saved_flip` | copies of `pc`, `x`, `y`, `frame`, `flip` | saved when interrupted, put back by `Return` |
| Fault | `fault` | text; empty = no fault | the VM, when the script does something impossible; never cleared |

There is nothing else: no registers, no stack, no variables a script can name. A foe cannot read another
foe's state at all; the only ways foes affect each other are the global flags and sleep/wake.

**The sub's oxygen is out of reach.** No instruction reads or changes the sub's oxygen (or anything else
about the sub except its position, which the `If_Sub_` instructions read). Oxygen changes only through
`damage`, and that is the game's doing, not the script's: when the sub touches a foe, `sim_world.gd`
(`sub_touches`) applies the foe's fixed `damage` and then starts its hit script. A positive damage costs that
much oxygen, then the sub is invulnerable for 30 ticks. A negative damage (Zoom the dolphin) adds 1, whatever
the number. A foe that is busy with an interrupt script is harmless. The hit script cannot change the
damage or add to it; all it can do is react (a sound, a move, a flag).

**Lifetime.** When the sub enters a sector, or respawns there after a lost tank, the game builds every foe
afresh from its `FoeData`, with a new `Context` (all flags 0). Changing screens inside a sector keeps
everything. Leaving the sector throws it all away, so nothing a script did survives to the next visit.
(The original game never clears the flags; see "Global flags".)

### Each game tick

The game runs the foes once per game tick, in list order (foe 0 first). For each foe:

1. **Does it run at all?** (`FoeVM.can_run`) Not if it has a *fault* (see below) or is
   *dormant* (asleep). Otherwise it runs if its screen is the screen being shown. The one
   exception: a foe that is busy with an interrupt script (next section) runs even when its
   screen is not shown.
   A *hidden* foe still runs. Hidden only means "not drawn and cannot be touched".
2. **It executes instructions, one after another, until one ends its tick.** `Wait_Next_Tick`,
   `Move_Foe_Relative_XY`, `Move_Foe_To_XY`, `Move_Foe_To_Screen_XY` and `Hide_Foe` end the tick.
   Every other instruction just continues with the next one in the same tick. Next tick the foe
   continues right after the instruction that ended its turn.
3. **Runaway limit.** If a foe executes more than **512 instructions in one tick** without one
   of the tick-ending instructions, the VM declares an endless loop and gives it a *fault*.
   This limit is **not from the original game**: it is a safety net added by the port
   (`creatures.max_instructions_per_tick` of `data/rules/tuning.json`, `Tuning.max_instructions_per_tick`, which `FoeVM.Context.max_instructions` holds).
   The description of the original interpreter in [`DESIGN.md`](../port/DESIGN.md) section 3.5 lists no such limit
   and [`PORT_GAPS.md`](../port/PORT_GAPS.md) does not mention one, so, as far as our notes go, the original would simply have kept looping.
   The number 512 is the port's own choice: the engine test `test_foe_vm_real_data.gd` runs every script of the chain's sectors
   (the dev pack's in the engine suite, the original's when run on the legacy pack) and none of them faults. The other faults listed below are also the port's way of refusing
   impossible scripts instead of crashing.

A **fault** stops the foe for good: it never runs again and stays where it is. The faults the VM
can raise are: an unknown opcode, reading outside the script, more than 512 instructions in a
tick, `Put_Foe_To_Sleep` / `Wake_Foe` naming a creature that does not exist, and an `If_`
instruction followed by an unknown opcode. (`Mod_Instruction` is an unknown opcode where no mod gives it a meaning.) (A sector whose script text does not compile, section 2,
gives *every* foe of that sector a fault, so nothing runs on garbage.) The fault text is kept in `FoeVM.fault`. The foe
sandbox shows it. A correct script never faults, and `test_foe_vm_real_data.gd` checks that the
scripts of the chain's sectors do not.

`Put_Foe_To_Sleep` and `Wake_Foe` change the other foe's flag at once. A foe with a higher number
that is woken still runs later in the same tick. A foe with a lower number, which has already had
its turn, runs next tick.

### The three entry points

Every foe has three entry points, places in the script where it starts running:

| Entry | When it is used |
|---|---|
| **start** (`pc`) | The normal program. The foe starts here when the sector is loaded. |
| **hit** (`script_hit`) | Run when the sub touches the foe. Usually just `Return`: the touch only costs oxygen. |
| **ink** (`script_ink`) | Run when an ink pellet hits the foe. Mostly a freeze or slow-down loop. |

In the stored text each place has **one** label, however many foes use it. The name is
`foe<N>_start`, `foe<N>_hit` or `foe<N>_ink` of the first foe (lowest N, then start, hit,
ink) that has an entry point there; every other foe at that place names the same label in its
own record. (A hit script of just `Return` is shared by many foes, so sector 0 has one
`foe0_hit:` label and foe 9's `hit_label` is also `"foe0_hit"`.) Jump targets that are no
entry point are named `loc_<offset>`. When you write your own script, name the labels as you like.

### Interrupts: hit and ink

When the sub touches a foe, or an ink pellet hits it, the foe is **interrupted**
(`FoeVM.interrupt`):

1. It saves its `pc`, its position (x, y), its picture (frame) and its mirror flag (flip).
2. It jumps to the hit or ink entry point and marks itself as interrupted.
3. It then runs that script like any other, one tick at a time.
4. A **`Return`** in that script restores the saved pc, x, y, frame and flip and clears the
   interrupted mark, so the foe carries on as if nothing happened (apart from what the
   interrupt script did to flags and other foes).

Only those five things are saved. The three loop counters, the frame range and the hidden flag
are *not*. A handler that uses `Loop_Counter0_Back_To` disturbs the main script if the main
script was in the middle of a counter-0 loop. Use another counter in handlers.

While a foe is interrupted, it ignores a new interrupt. Which foes the sub can touch is decided in
`sim_world.gd` (the contact rule in DESIGN 3.5), not by the VM: a foe on the shown screen that is
not hidden. **Dormancy does not protect a foe from contact**: a dormant, visible foe still costs oxygen.
It only stops the interrupt: in the port, the sub's touch starts the hit script only if
`FoeVM.can_be_interrupted` agrees (not dormant, not hidden, not interrupted, no fault). The ink hit in
`FoeModel.hit_by_ink` (`foe_model.gd`) is looser: only "already interrupted" or "has a fault" block it, so ink does interrupt a
dormant foe.

A dormant foe does not run, not even an interrupt script: `can_run` says no. An interrupt it received
waits until it is woken.

If a foe runs `Put_Foe_To_Sleep` inside an interrupt script, its "interrupted" mark is cleared and
nothing is restored, **whichever foe the instruction names** (itself or another). The foe carries on
in the interrupt script, with the position it has then (a foe that put itself to sleep carries
on only when it is woken). (The Zoom dolphin does this: `Put_Foe_To_Sleep self`, then `Hide_Foe`. Sector 14 foe 18
puts foe 17 to sleep: its hit script runs foe 17's tail, which ends the interrupt, and its jump then
puts it into foe 17's cycle.) `Wake_Foe` does not end an interrupt.

*Differences from the original* ([`PORT_GAPS.md`](../port/PORT_GAPS.md)):

- **G41, deliberate deviation.** The original's sub contact interrupts a dormant foe too (it ignores
  dormancy entirely; the hit script then waits until the foe is woken). No original sector has a dormant
  foe that is visible, so this cannot be seen with the original data.

`Return` outside an interrupt returns from a `Call_Subroutine` (below). A foe that has never
called one returns to its start entry point.

### Global flags

The 16 flags (bits 0 to 15 of `Context.semaphore`) have no fixed meanings, with one exception: the game
itself reads **bit 15**, to start the ending (next section). Bits 0 to 14 mean whatever a sector's script
makes them mean, and the same number means different things in different sectors. The original scripts
use only bits 0 to 3 and 15. Bits 0 to 3 are used in two ways:

- **A foe's own memory** (sectors 2, 15, 17). A foe has no variable of its own, so a foe that alternates
  between two places keeps "which one" in a flag: it sets the flag when it appears at the first place
  and clears it when it moves to the second, and its hit script asks `If_Flag` which way to go. Sector 15
  has four such foes (7, 11, 14, 15) and gives each its own bit, 0 to 3.
- **One foe signalling another** (sectors 16, 19, 24). One foe sets bit 0 while it does something (a
  sweep of moves, say) and clears it afterwards; another waits in a `Wait_Next_Tick` / `If_Flag 0` loop
  for the change.

**When the flags are cleared.** In the port, every sector load (also a respawn) starts with all flags 0.
The **original never clears them**: `FoeSemaphore` (0x448cac) is zero when the program starts, and
the only instructions that touch it are `SEM_SET`, `SEM_CLR` and `IF_SEM` in `update_animals` and the bit 15
test in `DoAction`. So in the original, flags left set in one sector are still set in the next one, and in
the next game of the same session. A respawn reloads the creatures but keeps the flags too. The port's
reset is a **deliberate deviation** ([`PORT_GAPS.md`](../port/PORT_GAPS.md), G40, WONTFIX): leftovers from another sector or
game are an accident of the original, and their effects, below, are cosmetic.

What a leftover flag does in the original (traced with a simulation of the real scripts):

- **No effect in sectors 2, 15 and 17.** Their readers are each foe's own hit script, and the foe writes
  its flag on the same tick as its `Show_Foe`, before it can be touched. Bits 1 to 3 (sector 15 only) never
  matter for the same reason, and bit 15 cannot leak, because the finale guards clear it on the first tick.
  The whole Voyager game is unaffected.
- **Small effects in sectors 16, 19 and 24**, all bit 0, all short and self-correcting:
  - *Sector 16:* the plant creatures (foe 4 on screen 2, foe 20 on screen 8) do not pulse until the sub
    first moves left of x 140 on screen 2, which sets off foe 5's sweep. Usually a few seconds.
  - *Sector 19:* foe 7 on screen 4 stands still for about 80 ticks instead of restarting its patrol, but
    only if the sub stays above y 150 for the first 47 ticks on that screen. In normal play, nothing.
  - *Sector 24:* foe 9 on screen 4 skips its first animation and sound (within the first 53 ticks).
- **How the flags get there.** Bit 0 is left set about a third to half of the time by sectors 15, 17, 19 and 24,
  depending on where their foes were when the sub left. Sectors 15 → 16 and 19 → 24 (20 to 23 do not touch it)
  are the natural paths. None of these effects changes whether a sector can be finished.

### The finale: bit 15

Each finale sector (30 Voyager, 31 Expert) ends the game when the sub reaches its finale screen while
bit 15 is set. `DoAction` (0x417ffc) checks this on **every pass** of its loop, not only after a screen change:
`FoeSemaphore & 0x8000`, then sector 30 and screen 2 starts `VoyagerClosingSequence`, sector 31 and
screen 10 starts `ExpertClosingSequence`. The port does the same in `SimWorld.is_finale_triggered`.
No other sector, and no other screen, reacts to bit 15. The flag is set by the treasure's own hit
script, so it is a script/engine contract: the engine supplies the test and the scripts supply the bit.

**Sector 30 (Substance X).** Screens: 1 and 2 at the top, 0 (the start station) and 3 below them, 4 below 3.

| Foe | Where | What its script does |
|---|---|---|
| 0, the treasure | screen 4, damage 0 | `foe0_start` animates it and, on a timer, wakes the dormant foes 7, 6, 4, 1, 8 and 9 (the creatures that rise from it). `foe0_hit`: `Hide_Foe`, `Set_Flag 15`, `Play_Sound 27`, then waits forever and never `Return`s. |
| 3, the guard | screen 0, hidden, damage 0 | `foe3_start`: `Clear_Flag 15`, `Clear_Flag 0`, `Wait_Next_Tick`, repeat. |

Touching the treasure hides it and sets the bit. Because the hit script never returns, the foe stays
interrupted, so its start script, and the waking of the other creatures, stops for good. It stays hidden,
so it cannot be touched again. The player then swims 4, 3, 2, and the ending starts on arrival at screen 2.

The guard runs only while screen 0 is shown (it is not dormant and never interrupted), and while it runs it
clears bit 15 on every tick. It has two effects:

- A bit 15 left set from earlier is cleared as soon as the sector starts, because the sub starts on screen 0.
  That matters in the original, where the flags survive (see above). Without the guard, a stale bit would
  end the game the moment the sub reached the finale screen without the treasure. This is most likely why
  the guard exists, but nothing in the data says so.
- **The detour 4, 3, 0, 1, 2 loses the treasure.** Passing screen 0 clears the bit. The treasure is hidden
  and stuck in its hit script, so it cannot be taken again, and screen 2 does nothing. The sector can then
  only be finished after losing a tank: the respawn reloads the sector, with the treasure back on screen 4.
  (In the original, `Main` calls `FreeSectorResources` after every `DoAction` and `LoadSectorResources`
  before the next, so a respawn always reloads the creatures; the flags are kept.)

Clearing bit 0 has no effect: no sector 30 script uses bit 0.

**Sector 31 (Alien Artifact).** The treasure (foe 0) is on screen 10, the finale screen itself. Its hit
script is just `Set_Flag 15` and a wait forever, without `Hide_Foe`, so the ending starts on the next pass of
`DoAction`, right after the touch. Foe 1 shares its start script (the animation). Foe 2 is the same kind of
guard, hidden on screen 0 (`Clear_Flag 15`, wait, repeat), so a bit 15 left over from the Voyager finale
cannot end the Expert game early.

## 2. The text format

A script is plain text. One instruction or one label per line. Each sector's script is its own
file, `sector_NN/sector_NN.foe` (for the original's sectors in the legacy pack, `godot/packs/legacy/data/sectors/`; for a sector of your own in `godot/data/sectors/`), which the sector resource `sector_NN.tres` (in the same folder) refers to
(its property `foe_script`, a `FoeScript` resource). Because it is a plain file, git shows
exactly which lines changed and who changed them.

**How to edit it.** In the Godot editor, double-click `sector_NN.foe` (in the folder `packs/legacy/data/sectors/sector_NN/`, or `data/sectors/sector_NN/` for a sector of your own) in the FileSystem dock.
The editor switches to the **Foe Script** screen (a tab next to 2D, 3D, Script and AssetLib),
which the project plugin `addons/foe_script_editor` adds (enabled in Project Settings >
Plugins). The built-in Script screen cannot open a `.foe`: it only takes GDScript and other
`Script` resources. On the Foe Script screen:

- The list on the left holds the files you have opened; click one to switch. A `*` marks
  unsaved changes. The header shows the file's path and a "Unsaved changes" marker.
- The text has line numbers and colours (instruction names, labels, numbers, comments).
  Ctrl+K comments the caret's line (or the selected lines) out with `;`, and in again when they are all comments already.
- **F2 renames the label** under the caret (also in the right-click menu), and **Store names &
  comments** keeps your label names and comments for later imports and resets. See "Names and
  comments" below. Messages of these commands appear in blue under the problems.
- **The editor knows the instructions.** Everything below is generated from the instruction
  table `FoeOps.OPERANDS` (the same table the assembler checks your values against) and, for
  `Padding`, from `FoeOps.PSEUDO`, so it always agrees with section 3.
  - *Hover tooltips.* Rest the mouse on an instruction name: you see its signature
    (`Move_Foe_To_XY x y frame`), what it does, and each operand with its kind and valid
    range. On an operand: which operand it is, what it means, and whether the value is valid
    (`Out of range: 300 is not 0..255`); positions also show the pixels (`x` 12 is 48 pixels)
    and picture numbers whether they are mirrored. On a name (`lock_tick`): what it is and its
    number (`lock_tick (38)`; a mirrored picture `eel_swim_1 (41 + 128)`); on a number: its name,
    if it has one. On `self`, `self+2`, `self-1`: which creature that is. On a label, in its `name:` line or in a `Jump_To`: the line where it is
    defined, and how often it is used.
  - *Signature hint.* After the instruction name and a space, a small box under the caret shows
    the signature with the operand you are typing underlined, and a line that says what
    that operand means. It follows the caret as you press space or move with the cursor keys,
    and goes away after the last operand and in comments. Esc hides it.
  - *Completion.* While you type a word, a menu offers the instruction names that start with
    it (any upper/lower case), with a one-line summary. Where an operand is a label it
    offers the labels of the file, where it is a creature it offers `self` and the creatures'
    names, where it is a sound, a picture, a flag or a screen it offers the names valid in this
    sector, each shown with its original number (`lock_tick (38)`; only the name is inserted),
    and after a picture it offers `mirrored`. Enter or Tab takes
    the selected entry (an instruction name comes with a space after it), Esc closes the menu.
    Ctrl+Space opens it on demand, even before you have typed anything. It never opens by
    itself on a blank place, in a comment, after a number, or when you have typed a complete
    name.
- **Run in sandbox** (the button, or Ctrl+R) saves the text and plays `src/debug/foe_sandbox.tscn` on this sector, opened on
  the screen of a creature whose script runs the caret's line, with that creature framed and selected. The drop-down beside
  the button lists the creatures that run the caret's line (the ones that start, are hit or are inked at the label the line
  is under first, then the ones that only run through it); a line that no creature runs opens the sector on screen 0.
  *Paused* starts the clock stopped. A text that does not assemble is not run (the reason appears under the problems).
  In the sandbox, each creature's row shows its live instruction and, under it, the `.foe` line it came from (`line 42
  under 'again': ...`); Tab selects the next creature, `P` pauses, `S` steps one tick. While the sandbox is paused the Foe
  Script screen marks, in a gutter to the left of the text, the line every creature on the shown screen is on (`#3`, the
  selected one `*3`). The sandbox also takes `--sector= --screen= --foe= --pause` on a command line, or in the environment
  variable `NEPTUNE_SANDBOX_ARGS`, which is how the button hands them over.
- **Save** with Ctrl+S or the Save button. The file is written exactly as you see it (UTF-8, no
  added newline). Save All, running the game and closing the editor save the foe text too,
  and the editor asks first when you close with unsaved changes.
- After a save, and about half a second after you stop typing, the text is assembled with the
  same assembler the game uses. Mistakes are listed under the editor as `line N: ...`; click
  one to jump to the line (the line is also tinted red). When there are none, the list says
  how many bytes the script assembles to.
- If the file changes on disk while it is open (you saved it in another program), the screen
  reads it again, unless you have unsaved edits: then your text stays, a warning appears, and
  you choose between Save (overwrite the file) and Reload (discard your edits).

Any other text editor works as well; the file is UTF-8 and the
game uses it exactly as it is. The next time the game runs, the text is assembled again and
the change is in effect. This text is the **stored version** of the scripts. For an original sector
the importer writes it into the legacy pack (on the first import and on a full reset), which git
ignores; for a sector of your own, in `godot/data/sectors/`, it is the only source, and you commit it
(with `foe_annotations.json`, below). To go back to the original, see "Resetting a script to the
original" in section 5.

Only the text is in the `.foe` file. Which label each foe starts at, and which it runs when
the sub touches it or an ink pellet hits it, are still the foe's `start_label`, `hit_label`
and `ink_label` in the sector's `.tres` (select the foe in the Inspector). Ctrl+S saves such a change:
the screen editor plugin's sector saver replaces just those lines of the `.tres` (an unknown label
shows up as a compile error when the game next compiles the script).

*Editor note.* The running game loads the files afresh, so it always sees your last save.
The editor keeps a loaded copy of each script (the Inspector shows it as the sector's
`Foe Script`); the plugin re-reads that copy when the files on disk change, and the Foe Script
screen keeps it equal to what you typed. If the editor ever works from stale text, restart it.

```
; a comment runs to the end of the line
start:                            ; a label, on a line of its own
    Move_Foe_Relative_XY 2 0 1    ; an instruction and its operands
    Jump_To start
```

- **Comments.** `;` starts a comment that runs to the end of the line. Blank lines are ignored.
- **Labels.** A line `name:` names the place of the next instruction. A name starts with a
  letter or `_` and then has letters, digits or `_`. Label names are **case-sensitive**
  (`Loop1` and `loop1` are two labels) and each name may be used once. Several labels may
  name the same place. A label at the very end of the script is allowed. A label and an
  instruction cannot share a line.
- **Instructions.** A name from the reference below, then the operands separated by spaces
  (**no commas**). Indentation does not matter; the disassembler writes four spaces.
- **Padding.** `Padding 9` looks like an instruction but is a *pseudo-instruction*: it tells the
  assembler to write nine zero bytes. See "Pseudo-instruction: `Padding [count]`" in section 3.
- **Instruction names ignore case**: `hide_foe`, `HIDE_FOE` and `Hide_Foe` are the same. The
  original's short names (`JMP`, `MOVE_REL`, ...) are refused with a "did you mean `Jump_To`?"
  message.
- **Numbers** are whole decimal numbers. Each operand has a range and the assembler refuses
  values outside it.
- **Jump targets** are label names, never numbers. The assembler works out the distances. A
  jump can reach 32767 bytes forward or 32768 bytes back.
- **Creature references** (`Put_Foe_To_Sleep`, `Wake_Foe`) are either a creature number
  `0` to `127` (position in the sector's foe list), or relative to the foe running the
  instruction: `self` (the foe itself), `self+1` (the next foe in the list), `self-2` (two
  before), or the creature's name. The offset is from -64 to 63. The relative form is useful because numbers
  stay right even if foes are inserted nearby in the list.
- **Names.** A sound, a picture, a creature, a flag or a screen may be written with its name
  instead of its number: `Play_Sound begin`, `Set_Frame eel_swim_1`. See "Names in operands" below.

The assembler checks the whole file and reports **every** problem with its line number, for
example `line 12: Jump_To needs a label, got '40'` or `line 30: unknown label 'loop2'`.
It also reports a wrong number of operands, a value out of range, an unknown instruction, a
duplicate label, and a jump that is too far away.

**Where the errors appear.** The game assembles a sector's text the first time it needs the sector
(`SectorData.ensure_compiled`, called by `Catalog.sector` and `FoeVM.from_data`), and again whenever
the text, the base offset, the list of creatures or a creature's label has changed since (the compiled
script is keyed by all of them, so an edit in any editor shows in the next run). Each problem
is written to the Output panel with `push_error`, as
`SectorData res://packs/legacy/data/sectors/sector_05/sector_05.tres (sector 5): foe script: line 12: unknown label 'loop2'`.
No foe of that sector then runs the script: each one starts with a fault whose text names the
sector and the first problem (the foe sandbox shows it). Nothing crashes.

### Names in operands

The operands that are a *sound*, a *picture* (`frame`, `min`, `max`), a *creature*, a *flag* or a
*screen* take a name from the name registry (`godot/names/original.json`, [`NAMES.md`](NAMES.md)) as well as
a number; the assembler turns the name into the original number, so a script written only with
names assembles to the original bytes, and numbers are accepted as well. The table
`FoeOps.OPERANDS` says which operands: `Play_Sound` (sound), `Set_Frame`, `Set_Frame_Range`, the
`frame` of `Move_Foe_To_XY` and `Move_Foe_To_Screen_XY` (picture), `Put_Foe_To_Sleep` and `Wake_Foe`
(creature), `Move_Foe_To_Screen_XY`'s `screen`, and `Set_Flag`, `Clear_Flag`, `If_Flag`. The third operand of
`Move_Foe_Relative_XY` is a picture *step*, not a picture, and stays a number.

- **Where a name is valid.** Sounds are the same everywhere. Picture names belong to the **zone** of
  the sector (slot 40 is a different drawing in every zone; the `common` picture names work in every
  zone), creature, flag and screen names to the **sector**. A name of another zone or sector is an
  error that says where it exists. The editor and `SectorData.compile` use the zone and sector of the
  script's sector; `FoeAsm.assemble(source, base, symbols)` takes them as a `FoeNames`
  (`godot/src/core/foe_names.gd`), and without
  it only the sound names and the `common` names work.
- **Made-up names.** Every number also has a made-up name, `sfx_28`, `frame_040`, `foe_3`, `flag_02`,
  `screen_05`, which is always accepted. The disassembler never writes it: a number nobody has named is
  written as the **number**, which says more (the original value, no invented word). A real name is
  written wherever the number has one.
- **Mirroring.** A picture shown mirrored has bit 7 of its byte set (the picture number plus 128).
  Write the word `mirrored` after the picture: `Set_Frame eel_swim_1 mirrored`, `Set_Frame 41 mirrored`
  (the same as `Set_Frame 169`). Plain numbers with bit 7 (`Set_Frame 169`) are accepted. `mirrored`
  goes with `Set_Frame`, the picture of the two `Move_Foe_To_` instructions and the step of
  `Move_Foe_Relative_XY`; after anything else it is an error, and after a number of 128 or more it is
  too (the picture is already mirrored). `mirror` and `mirrored` are not usable as names.
- **Numbers stay visible.** The names are keys for skins and packs and carry no number; the editor
  shows the number next to the name in completion (`lock_tick (38)`, `eel_swim_1 (41)`, `mirrored (+ 128)`)
  and in tooltips (`eel_swim_1 (41 + 128)` for a mirrored picture).
- **In the stored text.** The importer (`tools/import/foe_text.py` with `foe_names.py`, which read the
  same registry) writes the names into `sector_NN.foe`, and a test checks that the GDScript disassembler
  writes the same text. When names are added to the registry, run
  `uv run tools/import/reset_foe_scripts.py --all` (it puts the original sectors' instructions back too); your
  label names and comments are kept. "Store names & comments" and `harvest_foe_annotations.py` compare the
  *values* of the operands, so a hand-written `Set_Frame 169` or `Set_Frame frame_041 mirrored` is accepted
  and stored in the standard spelling.

### Names and comments

The generated text names labels `foe3_hit` or `loc_529`, which says little. You can give a label a
better name and write comments anywhere (`; ...`, on a line of their own or after an instruction).
Because an import or a reset writes the text again from the original bytes, these additions are kept in
one more committed file, `godot/data/sectors/foe_annotations.json` (in the project, also for the sectors of the legacy pack), **keyed by sector and ORIGINAL byte
offset** (stable, because the bytes never change). The disassembler puts them back whenever the text is
generated. Only what differs from the generated text is stored.

**Rename a label.** Put the caret on a label (its `name:` line or the name after `Jump_To`,
`Call_Subroutine`, `Loop_Counter0_Back_To`...) and press **F2**, or use *Rename label* in the right-click
menu. The name must be an identifier (letters, digits, `_`) and not exist in the file yet. The definition
and every use are replaced, whole words only and never inside a comment; Ctrl+Z takes it back in one step.
If creatures name the label as their `start_label` / `hit_label` / `ink_label` (an entry label, like
`foe0_hit`), the sector's `.tres` is changed as well and the `.foe` is **saved with it**, so the two files
cannot disagree (a plain jump-target label only changes the buffer). Renaming by typing a new name by hand
works too, but then the creatures' labels in the `.tres` are fixed only by the next *Store* (below).

**Store them.** Saving a file never touches the store. To keep the names and comments, save the file, then
press **Store names & comments** in the Foe Script screen, or run

```
uv run tools/import/harvest_foe_annotations.py 3 7     # sectors 3 and 7
uv run tools/import/harvest_foe_annotations.py --all
```

Both read the text, work out the byte offset of every label and instruction (the sum of 1 + the operand
bytes of the instruction lines before it; a `Padding N` line counts as N bytes), and write what differs from the generated text into the store,
replacing the sector's old entry. They also lay the file out in the standard layout (the stored file must
equal what the disassembler writes: indentation, one space between words, comments after two spaces, a
final newline) and make the `.tres` entry labels follow renamed labels. They **refuse**, with the reason in
the Problems area (or on the console), when the instructions differ from the original's (a sector listed in
`DELIBERATE_SCRIPT_CHANGES`, say), when two labels sit at one place, when a creature's entry point lost its
label, or (the button) when the file has unsaved changes. Nothing is changed then.

**Reset and import keep them.** `reset_foe_scripts.py` and a full `step_sectors.py` run write the text
*with* the stored names and comments (the instructions go back to the original; the labels in the `.tres`
follow the names). To get the fully generated text instead, `uv run tools/import/reset_foe_scripts.py 3
--plain` ignores the store (the store file itself is not touched, so a later plain reset undoes nothing).
The legacy test `test_foe_asm_legacy.gd` fails for an original sector whose `.foe` is not what the disassembler writes from the
original bytes and the store, with a message naming the button and the script: it means you edited names or
comments and did not store them yet.

**Where a comment belongs.** Each stored comment is attached to the *byte offset* of the line that follows
it (a comment above an instruction belongs to that instruction), an end-of-line comment to its own line:

```
; Header.                         <- above the first label (label_above of the first position)
foe0_hit:   ; end of a label line <- label_inline

; The dive.                       <- label_above: between the blank line and the label
swim_back:
    ; three frames               <- above: between the label line and the instruction
    Set_Frame 33  ; frame        <- inline
```

A `Padding N` line is one line for N bytes, so a label or comment on it belongs to its *first* byte. (If a
stored name or comment sits at a later byte of a padding, which a hand-written `Wait_Next_Tick` line can
produce, the disassembler cuts the `Padding` there into two lines so that it keeps a line to sit on.)
A comment between an instruction and the next label goes above that label; blank lines are layout and are
kept exactly where they are (one blank line before a label is the default and needs no entry). Comments after
the last instruction, and a label at the very end, belong to the end of the script (offset = base + size).
In the JSON a position's note has up to four keys: `label_above`, `label_inline` (the label line) and
`above`, `inline` (the instruction line); `labels` maps offset to name. Offsets are written as numbers
sorted numerically, one entry per line, so git diffs stay small. The file is not shipped with the game
(`export_presets.cfg` excludes it). The exact rules are the docstring of `tools/import/foe_annotations.py`;
`FoeAnnotations` is the GDScript twin, and `tests/engine/test_foe_annotations.gd` and
`tools/import/test_foe_annotations.py` check that both give the same file and the same text.

**Sectors you make yourself.** Only the original sectors (those in
`tests/fixtures/foe_scripts.json`) have annotations. Any other sector has no original bytes:
your own sectors (32 and up, in the project's `godot/data/sectors/`) have their `.foe` text as their only source, and nothing regenerates them. So there is nothing to
harvest: the button is disabled, and `harvest_foe_annotations.py` and `reset_foe_scripts.py` refuse the
number. `import_all.py --clean` removes the generated `sector_00`-`sector_31` files of the legacy pack; the
annotation store and your sectors are in `godot/data/sectors/` and are not touched. Rename (F2), colours
and hints work the same for any sector.

### Code that never runs

Some bytes of the generated text can never execute: no creature starts there, and nothing falls through,
jumps, calls or skips to them. There are two kinds, and the disassembler writes them differently.

**Zero bytes are written as `Padding`.** A run of unreachable zero bytes is not code. It is filler, and it
is written as one `Padding N` line (N zero bytes) with no comment:

```
foe0_hit:
    Return
    Padding 9
```

**Anything else gets a comment.** Unreachable instructions are the unused scripts the original authoring tool
left in the data (a creature's animation that no creature ever starts, for instance, in sectors 0-3, 5, 6,
15, 20 and 25-31). They stay in the text, written as ordinary instructions under one comment line:

```
    Return
    Padding 2
    ; The following instructions are not executed -- nothing jumps to them
    Set_Frame 32
    Move_Foe_Relative_XY 0 -11 0
```

**Why they exist.** Every sector's script starts with the shared do-nothing hit script, a lone `Return`,
followed by nine zero bytes (`Padding 9`) that nobody reaches. The original authoring tool also left zero bytes
after the end of many creatures' loops, after their final `Jump_To`, and between its unused scripts. All of
it stays because the text must assemble to **exactly** the original bytes: delete it and the game still
plays the same, but the fidelity test (`test_foe_asm_legacy.gd`) fails, and the annotation store refuses the
sector (its instructions are no longer the original's). `Padding` is a way to keep those bytes without
dozens of `Wait_Next_Tick` lines that suggest a creature waits there.

**Zero bytes inside unused code.** A run with code in it is judged by what can fall into each stretch of zero
bytes. The zeros at the start of the run, and the zeros right after a `Return` or `Jump_To` (which never
go on to the next instruction), are `Padding`: nothing can enter them. Zeros after any other instruction
stay `Wait_Next_Tick`: in an unused animation they are a pause between two pictures, and the code before
them falls into them. So a run is "padding, then code, ...", and the comment goes before the first line that
is not `Padding`. Zero bytes that a creature *can* reach are always `Wait_Next_Tick`, never `Padding`. (The
rule is `FoeAsm.padding_spans` and its twin `foe_text.padding_spans`; the two disassemblers must write the
same text, and a test compares them for all 32 sectors.)

**How it is found.** A reachability analysis, like a compiler's dead-code detection (`FoeAsm.reachable`, twin
`foe_text.reachable`): start at every creature's start, hit and ink entry, and follow what the VM does. An
instruction goes on to the next one, except `Jump_To` (only its target) and `Return` (ends the path). `Call_Subroutine`
and the three `Loop_Counter...` go to their target *and* the next instruction, and the conditional instructions
(`If_...`) to the next one *and* the one after it. A label in the middle of a dead run, one that something
jumps to, starts a new run (a new comment, a new `Padding`).

**The comment is part of the generated text.** The store does not hold it; a text with the comments is in sync with an
empty store. If you reword it, add lines or delete it, the harvest stores your version as the `above` note of the
first line of code of the run. A stored `above` **replaces** the generated comment at that offset, so an empty one
(`"above": []`) removes it, and a stored note with only `inline` leaves it alone. (There is no comment for a run
of `Padding` alone.)

**Warnings in the editor.** The Foe Script screen checks any sector file, also a script you wrote yourself. It
assembles the text, takes the entry points from the labels the sector's `.tres` names (`start_label`,
`hit_label`, `ink_label`) and shows yellow warnings in the problems area, in line order. Click one to go to
the line; the line is tinted yellow. A warning is no error: the file still saves and runs. Without a `.tres`
next to the `.foe`, or when its labels are not in the text, there are no warnings. The original sectors have none.

- *A reachable `Padding`:* `line 7: Padding is reached and would run as Wait_Next_Tick (3 ticks of doing nothing); ...`.
  Padding is meant for bytes nobody runs, so if a creature can get there (found by the reachability analysis,
  not by looking at what comes before) the filler would really make it wait. End the code above it with
  a `Jump_To` or `Return`, or write `Wait_Next_Tick` if a pause is what you want. No comment silences this one.
- *Unreachable code:* one warning per dead run, on the first line that is not `Padding`:
  `line 12: never executed (no creature start/hit/ink entry or jump reaches it)`. A run of `Padding` alone is
  fine. If everything in the run besides `Padding` is `Wait_Next_Tick`, the message adds
  `; if it is only filler, write Padding 2 instead`. The warning disappears for a run that has a
  `; The following instructions are not executed` comment above it (the generated wording, or your own text
  after that start; blank lines, label lines and `Padding` lines in between do not matter), which says you meant it.

`FoeAsm.dead_code_warnings` does the work (and `FoeAsm.unreachable_offsets` / `foe_text.unreachable_offsets` give
the dead instruction offsets of any script bytes).

## 3. Instruction reference

In opcode order, followed by the one pseudo-instruction, `Padding`. The friendly name is what you write; the
*original* short name is the one in the enum `FoeOps.Op` and in [`DESIGN.md`](../port/DESIGN.md). Instructions 0 to 24 are the original's; 25 is the port's own and has no original name.
"Ends the tick" means the foe does nothing more until the next game tick.

Units: positions are in **window pixels** (the playfield starts at pixel (16, 32) of the
window). A *y* operand counts **2-pixel** steps, an *x* operand counts **4-pixel** steps, and
the relative moves count **2-pixel** steps in both directions.

### 0. `Wait_Next_Tick` (original `YIELD`)
No operands. **Ends the tick.** The foe continues with the next instruction next tick.
Put one in every loop that does not otherwise move the foe, or the foe will hit the 512
instruction limit and fault.

### 1. `Jump_To label` (original `JMP`)
Continue at `label`. Does not end the tick.

### 2. `Call_Subroutine label` (original `HANDLER`)
Remember the instruction after this one, then continue at `label`. A `Return` in the
subroutine goes back to the remembered place. Does not end the tick.
There is **one** return slot per foe, so calls cannot be nested: calling a second subroutine
from inside a subroutine overwrites the way back. Also, `Return` inside an interrupt script
ends the interrupt rather than returning from a call, so do not call subroutines from hit or
ink scripts.

### 3. `Return` (original `RET`)
No operands. In an interrupt script (hit or ink): restore the saved state and end the
interrupt. Otherwise: go back to the place remembered by `Call_Subroutine`. A foe that never
called one goes back to its start entry point. Does not end the tick.

### 4-6. `Loop_Counter0_Back_To label count`, `Loop_Counter1_Back_To`, `Loop_Counter2_Back_To` (original `LOOP0`, `LOOP1`, `LOOP2`)
`label`: a label, normally *before* this instruction. `count`: 0 to 65535.
Each foe has three independent counters. Every time the instruction is reached it counts its
counter down by one. If the result is 0, the loop is over: the counter is set to 0 and the
script goes on with the next instruction. Otherwise the script jumps to `label`. A fresh
counter starts at 0, so the first visit does not count: it loads `count` and jumps back.
**The loop body therefore runs `count + 1` times in total.** (`Loop_Counter0_Back_To again 4`
runs the body five times.)
**A count of 0 never ends.** Using it is a mistake that ends in a fault at the 512 limit,
unless the body ends the tick every time, in which case the foe is stuck in the loop forever.
A finished loop leaves its counter at 0, so the same counter can be used again by a
later loop. Two loops *inside* each other need different counters. If a script leaves a loop by
a jump before it finished, the counter keeps its old value, and the next loop on that counter
starts from there. Does not end the tick.

### 7. `Play_Sound sound` (original `SOUND`)
`sound`: 0 to 255, the number of a sound effect, or its name. Plays the effect, but only if the foe's screen is the
one being shown. Does not end the tick.

### 8. `Put_Foe_To_Sleep foe` (original `SLEEP_FOE`)
`foe`: a creature number 0 to 127 or `self+N` (section 2). Makes that foe dormant: its scripts stop
running until a `Wake_Foe` reaches it. Naming a foe that does not exist is a fault of the foe
running the instruction. Does not end the tick (even when the foe puts itself to sleep, it
finishes this tick; it does not run again next tick). A foe that runs this inside an interrupt
script also ends its own interrupt, whichever foe is named: nothing is restored (section 1).
A dormant foe that is visible can still hurt the sub, so put a sleeping foe out of sight with `Hide_Foe`
as the original scripts do.

### 9. `Wake_Foe foe` (original `WAKE_FOE`)
The opposite: the foe named by `foe` is no longer dormant. Same operand. Does not end the tick.

### 10. `Set_Frame_Range min max` (original `FRAME_RANGE`)
`min`, `max`: 0 to 255 or picture names. Sets the lowest and highest picture of this foe's animation. The two
move instructions below use it. Does not end the tick.

### 11. `Set_Frame frame` (original `SET_FRAME`)
`frame`: a picture name or a number 0 to 255. The picture is the low 7 bits (0 to 127). If bit 7 is set (`frame` + 128,
or the word `mirrored` after the picture), the picture is mirrored left-right, otherwise it is not. The frame range is **not** applied. Does not end the tick.

### 12. `Move_Foe_Relative_XY dx dy frame` (original `MOVE_REL`)
`dx`, `dy`: -128 to 127, how far to move, in 2-pixel steps (`dx` 3 is 6 pixels right, `dy` -1 is
2 pixels up). `frame`: 0 to 255, the picture step (a number, not a picture).
**Ends the tick.** The mirror flag is *set* from bit 7 of `frame` (not toggled): 128 or more
(or the word `mirrored` after it) mirrors the picture, below 128 does not. The low 7 bits are the picture increment. With an
increment of 0 the picture stays. Otherwise the new picture is the old one plus the increment,
and if that falls below the frame range minimum it becomes the maximum, and if it goes above
the maximum it becomes the minimum. So with `Set_Frame_Range 0 3` and an increment of 1, the
pictures go 0, 1, 2, 3, 0, 1, ...

### 13. `Move_Foe_To_XY x y frame` (original `SET_POS`)
`x`, `y`: 0 to 255; `frame`: a picture name or 0 to 255. Jumps to window pixel (4*x, 2*y). The picture is the low 7 bits of
`frame` (an absolute picture number, not an increment), **clamped** into the frame range: below
`min` becomes `min`, above `max` becomes `max`. Bit 7 (or `mirrored`) mirrors the picture. **Ends the tick.**

### 14. `Move_Foe_To_Screen_XY x y frame screen` (original `SET_POS_SCREEN`)
Like `Move_Foe_To_XY` (`x`, `y` and `frame` mean the same), and the foe also changes to screen number `screen` (or the screen's name). The assembler accepts 0 to 255;
the real screens are 0 to 11 (DESIGN 3.5), and what a larger number would do is not defined
in the source. **Ends the tick.**

### 15. `Hide_Foe` (original `HIDE`)
No operands. The foe becomes invisible and cannot be touched. Its script keeps running.
**Ends the tick.**

### 16. `Show_Foe` (original `SHOW`)
No operands. The foe is visible again. Does not end the tick.

### 17-18. `If_Sub_X_Greater x`, `If_Sub_X_Less x` (original `IF_SUBX_GT`, `IF_SUBX_LT`)
`x`: 0 to 255. Looks at the sub's X (window pixels, left edge of its picture) and compares with
`4*x`. See the note on `If_` instructions below.

### 19-20. `If_Sub_Y_Greater y`, `If_Sub_Y_Less y` (original `IF_SUBY_GT`, `IF_SUBY_LT`)
`y`: 0 to 255. The same with the sub's Y and `2*y`.

### 21. `If_Random_Greater value` (original `IF_RAND_GT`)
`value`: 0 to 255. True if a random number from 0 to 255 is greater than `value`. So `value` 255 is never true
and `value` 0 is true except 1 time in 256.

### 22. `Set_Flag flag` (original `SEM_SET`)
`flag`: 0 to 255, but use 0 to 15. Raises global flag number `flag`. The flags are shared by **all foes of
the sector**, and the sector finale uses bit 15. Does not end the tick. (The source comments speak of 16 flags; what a number
above 15 does is not defined there.)

### 23. `Clear_Flag flag` (original `SEM_CLR`)
Lowers global flag number `flag`. Same remarks. Does not end the tick.

### 24. `If_Flag flag` (original `IF_SEM`)
True if global flag `flag` is raised. See the note on `If_` instructions.

### 25. `Mod_Instruction number value`
The port's own instruction; the original has none, and **only a campaign that declares a mod pack with creature instructions runs it** ([`CONTENT.md`](CONTENT.md), "Rule hooks"). `number`: 0 to 7, which
instruction of the campaign's mods this is. `value`: 0 to 255, the operand the mod is given. The game asks the mod, with the number, the value and a snapshot of the creature, the sub and the flags,
what to do, and does only what it answers, held to the limits listed there: skip the next instruction like an `If_` (so it can be used as a condition), raise or lower flags, show a picture, move the creature
(which ends the tick like `Move_Foe_Relative_XY`) or end the tick. A number no mod of the campaign defines does nothing, and so does a call that failed (a mod that raised, ran too long or answered
something the game does not accept). Everywhere else, in a sector of a campaign that declares no such mod and in the original's, a foe that reaches it faults as for an unknown opcode, which is
also what a foe does when an `If_` is followed by it. The assembler, the disassembler and the editor know it in every sector.

### How the `If_` instructions work
An `If_` instruction never jumps. If its condition is **true**, the script just carries on with
the next instruction. If it is **false**, the VM **skips exactly one instruction**: the one right
after the `If_`, however many operands it has. To let a condition control a whole block, make the one guarded instruction a `Jump_To` or `Call_Subroutine` that leads to the block. An `If_` itself is an
instruction, so `If_Flag 3` followed by `If_Flag 4` skips the second `If_` only. A skipped
tick-ending instruction does not end the tick. If the byte after an `If_` is not a valid opcode,
the foe faults.

### Pseudo-instruction: `Padding [count]`
Not an instruction, and it has no opcode and no original name. A **pseudo-instruction** is written
like an instruction but is a command to the *assembler* about what bytes to produce; no creature ever
"executes" it. Real assemblers have them too: `db 0` or `.byte 0` writes a byte, `.fill 9` or `.space 9` writes a
block of them. `Padding` is the same idea for this language: it writes `count` zero bytes, `Padding 9` for nine. The
`count` may be left out (`Padding` is `Padding 1`), and runs from 1 to 65535. The line takes `count` bytes
and the labels after it move accordingly, so jumps over it still work.

A zero byte is the opcode of `Wait_Next_Tick`, so these bytes are *valid code*: if a creature could ever
get there it would run them as `count` ticks of doing nothing. The assembler does not know that you meant
them as filler; the **editor warns** when a creature can reach a `Padding` (see "Code that never runs"). The
VM and the bytes are exactly the same as for `count` lines of `Wait_Next_Tick`; only the text says what you meant.
The disassembler writes `Padding` for the unreachable zero bytes of the original scripts.

In the tables of the source, `Padding` is not in `FoeOps.MNEMONIC`, `OPERAND_COUNT` or `OPERANDS` (those
are the opcodes the VM runs), but in the separate `FoeOps.PSEUDO`.

## 4. A worked example

A creature that paces right then left. When the sub touches it, it plays a sound. An ink pellet
freezes it for a moment.

```
; ---- the normal program: the foe's start entry point ----
patrol_start:
    Set_Frame_Range 0 3
walk_right:
    Move_Foe_Relative_XY 2 0 1       ; 4 pixels right, next picture, not mirrored
    Loop_Counter0_Back_To walk_right 9      ; 10 steps in all (count + 1)
walk_left:
    Move_Foe_Relative_XY -2 0 1 mirrored    ; 4 pixels left, mirrored (+128) + next picture (1)
    Loop_Counter0_Back_To walk_left 9       ; counter 0 was reset to 0 by the last loop
    Jump_To patrol_start

; ---- the hit entry point: runs when the sub touches the foe ----
patrol_hit:
    Play_Sound 3                     ; any sound effect number that exists
    Return                           ; back to where the patrol was

; ---- the ink entry point: freeze for about 31 ticks ----
patrol_ink:
    Set_Frame 0
ink_wait:
    Wait_Next_Tick
    Loop_Counter1_Back_To ink_wait 30       ; counter 1, so the patrol's counter 0 is not disturbed
    Return
```

### Wiring the script to the foes

A foe record (`FoeData`) names its three entry points by label, in three properties:

| Property | The label to put there | In the example |
|---|---|---|
| `start_label` | where the foe starts and what it runs normally | `patrol_start` |
| `hit_label` | what runs when the sub touches it | `patrol_hit` |
| `ink_label` | what runs when an ink pellet hits it | `patrol_ink` |

Several foes may name the same label. A label that does not exist in the sector's script is a
compile error that names the foe and the property, for example
`foe 3 hit_label: unknown label 'patrol_hitt'`. (When the sector compiles, `SectorData` fills in the
numbers `FoeData.pc`, `script_hit` and `script_ink` from the labels; they are not stored.)

Things to notice: both loops use counter 0, one after the other, which is fine because a
finished loop leaves its counter at 0. Each walking step is a `Move_Foe_Relative_XY`, which ends
the tick, so the foe moves once per tick and never reaches the 512 instruction limit.

## 5. Authenticity: the scripts are the original game's

The text in an original sector's file is a readable form of the **original game's bytecode**. It is
not a rewrite, and a test proves it.

- **Where the text comes from.** The importer writes the legacy pack's `.foe` files from the original
  bytes in `docs/data/sectors.json` with a Python disassembler (`tools/import/foe_text.py`), and the
  three label properties of every foe to `sector_NN.tres`. After that the files are the stored
  version; the importer is only for a first creation or a full reset.
- **The test.** `godot/tests/legacy/test_foe_asm_legacy.gd` assembles each original sector's stored
  text and fails unless the bytes hash to the committed SHA-256 of the original script (with the
  original bytes at hand the message names the first differing byte) and each foe's labels resolve to
  exactly the original `pc`, `script_hit` and `script_ink`. With the original bytes it also checks
  that the GDScript disassembler writes the stored text (with the stored names and comments, section 2;
  so the Python and GDScript disassemblers agree) and that disassembling and assembling gives the
  bytes back. So whatever you read in the text is what the original machine ran. (The engine test
  `test_foe_asm.gd` covers the assembler's rules on the dev pack.) The fixtures it reads, and how
  the original bytes are checked: [`FIDELITY.md`](../port/FIDELITY.md).

**When you change an original script on purpose** (a new creature behaviour, a rebalanced sector),
`test_foe_asm_legacy.gd` fails for that sector until you either reset it (below) or declare the change
deliberate: add the sector to `DELIBERATE_SCRIPT_CHANGES` at the top of the test, and record it in
[`DESIGN.md`](../port/DESIGN.md) as a "Deliberate deviation" ([`FIDELITY.md`](../port/FIDELITY.md) has
the rules). This is intentional: the test protects the authentic data from accidental edits. A sector
of your own has no original and is not checked against one.

Designers: experiment on a sector of your own (a copy of an original one:
[`SECTOR_INSPECTOR.md`](SECTOR_INSPECTOR.md), "Making a new sector"), which git keeps, or reset an
original sector afterwards.

### Resetting a script to the original

1. **Throw away uncommitted experiments:** for a sector of your own, `git restore godot/data/sectors/sector_40/sector_40.foe`
   (or `git checkout -- ...`). This restores the script to the last commit, so it also drops other uncommitted changes in that file.
   (Changed labels are in `sector_40.tres`.) The original's sectors are in the legacy pack, which is not in git: there is nothing to restore, use the reset tool (next).
2. **The reset tool, for an original sector:**

   ```
   uv run tools/import/reset_foe_scripts.py 3 7     # sectors 3 and 7
   uv run tools/import/reset_foe_scripts.py --all   # every sector
   ```

   Add `--plain` to ignore the stored names and comments ("Names and comments", section 2) and get
   the fully generated text. Add `--records` to put each creature's record fields back as well (position, frame,
   flip, frame range, damage, dormant / hidden, run-time state): they sit in the same `.tres` blocks as the labels, so
   this tool is the one that knows a creature whole. It refuses a sector whose creature count differs from the original.
   The sector's own header (start, neighbours, pieces) is `reset_sector_header.py`.

   It rewrites `sector_NN.foe` and rebuilds every foe's `start_label`, `hit_label` and
   `ink_label` from the original script bytes the importer wrote from your copy of the game ("run the importer on your copy
   of the game" without them; how they are checked: [`FIDELITY.md`](../port/FIDELITY.md)), patching only those label lines
   into the existing `.tres`. Every other byte of the `.tres` (the
   rest of the sector's data, the uids, the ordering) stays as it is. It does not need `extracted/`. On a sector that
   is already original it changes nothing. If the sector is listed in `DELIBERATE_SCRIPT_CHANGES`,
   remove it from there.
3. **Do not use `import_all.py --only sectors` for this.** It regenerates the WHOLE sector files
   from `extracted/` and `docs/data/`, so it also wipes every deliberate change, in the scripts
   and in all other sector data. The comment at the top of `tools/import/step_sectors.py` says so.
4. **The test enforces it.** `test_foe_asm_legacy.gd` fails for an edited original sector until it is
   reset (point 2) or listed in `DELIBERATE_SCRIPT_CHANGES`.
