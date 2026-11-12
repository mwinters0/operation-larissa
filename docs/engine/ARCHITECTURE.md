# Architecture of the Godot project

How the game in `godot/` is put together: the scenes, the rules as plain objects and their views, the flow of a mission,
campaigns in code, the autoloads, where data comes from, and the folders. Paths are relative to `godot/` unless they start with
`docs/` or `tools/`. The project runs on Godot 4.7.2 with the GL Compatibility renderer, a 640 x 400 base viewport and integer
scaling.

Related: packs and the lookup chain, [`PACKS.md`](PACKS.md); skins, [`SKINS.md`](SKINS.md); audio, [`AUDIO.md`](AUDIO.md); the editor
tools, [`EDITORS.md`](EDITORS.md); tests and builds, [`DEVELOPING.md`](DEVELOPING.md); which Godot concept each file teaches,
[`TEACHING.md`](TEACHING.md); how the original behaves, [`../port/DESIGN.md`](../port/DESIGN.md).

## The game, scene by scene

```
main.tscn  (run scene, src/main.gd: chooses the pack chain, Packs.start)
   |  SceneRouter.go_to(...)  - every change of scene goes through the router (a fade, then change_scene_to_file)
   v
story/opening.tscn  Opening (director)         the title and the story, skippable (Space / Esc, Enter = next part)
   |    NewsCartoon -> TitleScene -> StoryPages    (three StorySegment scenes, each driven by AnimationPlayers)
   v
ui/sign_in.tscn  SignIn                         the players (SaveStore), Start / New / Practice / Exit, Hall of Fame, Help; P = the pack screen
   |-- Practice ---> problems/practice_mode.tscn  Math Practice (PracticeSet, PracticeScore, ProblemScreen with practice = true)
   v
gameplay/game.tscn  Game                        one player's mission; the VIEW of a GameFlow (rules/game_flow.gd), no rules, no flow
   |    the campaign's sectors  ->  supply message (surface ship screen)  ->  next sector
   |    finale sector  ->  touch the treasure, swim to the closing screen
   |    story/voyager_closing.tscn / expert_closing.tscn, or story/generic_finale.tscn  (laid over the sector)
   v
ui/hall_of_fame.tscn  ->  back to sign-in
```

When the pack chain is not whole, `main.gd` first opens `ui/pack_warning.tscn` ([`PACKS.md`](PACKS.md)). `game.tscn` started alone
(F6) is "free play" and never saves.

Keys: arrows / WASD steer, Space fires ink, Enter opens a waiting math problem, Esc asks to leave, F10 opens the menu, Alt+Enter
toggles fullscreen (`src/autoload/window_hotkeys.gd`), F3 shows the debug overlay (`GameDebug`: read-out, piece boxes, cheats; 6 opens a
problem through the rules (`SimWorld.open_problem`), 8 jumps to the finale sector, 0 completes the sector; R, O and S switch presenter,
overlay and skin). On the sign-in screen Insert = New, Ctrl+R or Delete = remove, Enter = Start. Saves live in `user://roster.json` and `user://hall_of_fame.json`.

## The rules of a sector: `SimWorld`

The rules of a sector are a plain object, `SimWorld` (`src/rules/sim_world.gd`, a `RefCounted`: no node, texture, font, `Input` or
`TileMapLayer` in `src/rules/`). It owns the sub (`SubModel`), the creatures (`FoeModel`, wrapping `FoeVM`), the ink pellets in flight
(`PelletModel`), the pieces still lying on the screen (`PieceModel`), every math trigger of the sector (`TriggerModel`, with its armed
flag), the waiting problem, the dock and the finale. `SimWorld.tick(input)` runs them once per game tick in the order of the original's
`DoAction` (`SimWorld.TICK_ORDER`: fire presses, a waiting problem, dock, pieces, sub, finale, triggers, creature scripts, contacts,
pellets; pinned by `tests/engine/test_tick_order.gd`). It reports what happened as named events (a creature changed picture / mirror
/ visibility or was hit, the sub was damaged, a piece was collected, a trigger fired, a pellet was fired / splashed / gone, a sound by
name, a screen was loaded or entered, a problem is pending, the dock, the finale).

The player's numbers (oxygen, ink, collected pieces, the message lights) are not in it: it is handed an object that answers the
methods of `GameState` (`SimWorld.new(GameState)` in the game; a test hands it a fresh instance that is in no tree, so no autoload is
needed). It reads two plain inputs and nothing else of the outside world: a `TileGrid` (walls and currents of the shown screen, from
`ScreenData.tiles`; the `Walls` and `Currents` tile layers are only the picture) and an `InputSnapshot` (the player's hands in one
tick, taken by `InputReader`, the one place the playfield's keys are read). Walls are a tile scan and contacts are rectangle
arithmetic, so there is no physics body.

**Nothing that holds up play is timed by a picture.** The sub's dissolve after a lost tank (`SimWorld.dissolve_length()`, 21 ticks of
the 73 Hz timer with the clock held) and the supply station's launch, dock and balloon (`StationSequence`; the base durations hold the original's 30, 31 and 44 game ticks)
are counted by the rules; the view is told "you have N ticks" (`dissolve_started`, `sequence_started`), and the lost tank is
announced when the rules have counted the dissolve out.

Whoever runs the tick goes on with its own business only between two ticks: see "Nothing the owner does runs inside a tick" under
`GameFlow` below. A campaign that declares a mod pack has rule hooks inside two of its steps ("Rule hooks" below); no step is added,
moved or removed.

## Lifetimes of state

The original resets its state in a few places: the entry of `DoAction` (0x417ffc) for every life (a sector start and every respawn),
`Main` (0x427bb4) after each `DoAction` result (a sector done, a lost tank, a game over), `IncrementSector` (0x42e201), and `SignIn`
(0x42e028) for a new run. The port spreads the same state over objects, so each stateful rules or run object declares the lifetime of
every member variable, as `*_FIELDS` constants in its script, and each lifetime has one place that clears it. The doc comment of
that place cites the routine it mirrors and what that routine zeroes.

| Object | Lifetime (constant) | Cleared by | Mirrors |
| --- | --- | --- | --- |
| `GameState` | life (`LIFE_FIELDS`: the console lights, `midpoint_reached`) | `begin_life`, called by `SimWorld.load_sector` | the entry of `DoAction`: `MessageLightCountdown` 0, `MidpointReached` = `IsPastSectorMidpoint`, `DisplayBezel` with both lights out |
| | sector (`SECTOR_FIELDS`: the pieces, the midpoint flag) | `begin_sector` (`GameFlow.complete_sector`, `restart_sector`), also clears the life | `Main`: `ProbesPickedUp` (0x44f52c) 0; `IncrementSector` / `SetPastSectorMidpoint(0)` |
| | run (`RUN_FIELDS`: the player, the rule values (`tuning`), the rule hooks (`hooks`), oxygen, ink, level, hints, sector shown, loss holds) | `begin_run(player)` (the sign-in screen; `apply_profile` and `reset` are it; it resolves the `Tuning` of the pack chain and the `RuleHooks` of the player's campaign), also clears the sector and the life | `SignIn`: the chosen record becomes the current player's |
| `SimWorld` | screen (`SCREEN_FIELDS`: the shown screen, its walls, pellets and pieces, the tick it began to run) | `load_screen` (`reload_creatures` starts the screen's tick again) | `DoAction` on a screen change: `LastHitFoe`, `StunGunFlag` 0, the screen redrawn (`DrawScreen` 0x433f1c), the animated decorations stepped from their start cursors (`DrawAnimatedDecos` 0x41e943) |
| | load (`LOAD_FIELDS`: creatures, triggers, the waiting problem, the dock and finale latches, the station trip, the dissolve and its hold on the losses) | `load_sector` (also runs `load_screen` and `run.begin_life`; a dissolve still running is ended by `abandon_damage`) | the entry of `DoAction`; the trip and the dissolve are one blocking call each there, so none runs when `DoAction` begins |
| | tick (`TICK_FIELDS`) | the top of `tick` | |
| `FoeVM.Context` (held by `SimWorld` for its life) | load (`LOAD_FIELDS`: the creatures' VMs, the flags, the dice) | `begin_load`, called by `SimWorld._build_foes` (`load_sector`, `reload_creatures`); the dice are the sim's `foe_rng`, which no load resets | the entry of `DoAction` and `LoadSectorResources` (0x433d13): the creature records read again; the flags at 0 are a deliberate deviation (G40), `rand` (0x4388c4) keeps its state |
| | screen (`SCREEN_FIELDS`: the screen shown) | `show_screen`, called by `SimWorld._show_creatures` (`load_screen`, `reload_creatures`) | |
| | tick (`TICK_FIELDS`: the sub's SubX / SubY, the sounds asked for) | `begin_tick`, at the start of the creatures' step | `update_animals` (0x41ed0c) reads `SubX` / `SubY` as the tick left them |
| `RuleHooks` (made once per run, held by `GameState.hooks`) | load (`LOAD_FIELDS`: each mod's memory per hook, its faults in the load, the mods switched off, the tick of the load) | `begin_load`, called by `SimWorld._build_foes` with the creatures' `begin_load` (`load_sector`, `reload_creatures`) | the flags at 0 of the creatures (G40): what a mod keeps lives as long as they do |
| | tick (`TICK_FIELDS`: the calls made) | `begin_tick`, at the top of `SimWorld.tick` | |
| `FoeModel` (made anew by every load of the creatures) | screen (`SCREEN_FIELDS`: on the shown screen) | `refresh` (`SimWorld._show_creatures`, every creature tick) | |
| | tick (`TICK_FIELDS`: the place before the tick) | `tick`, `snap` | |
| `SubModel` | place (`PLACE_FIELDS`) | `place_original` | the entry of `DoAction`: `SubVX` / `SubVY`, `InvulnerabilityCounter` 0, the sub placed |
| | tick (`TICK_FIELDS`), switch (`SWITCH_FIELDS`) | every controlled tick; the owning `SimWorld` | |
| `GameClock` | scene (`SCENE_FIELDS`: the switch, the holds) | `paused = false` in `SceneRouter.start_fresh` | |
| `Audio` | scene (`SCENE_FIELDS`: the sound and music pause counts, a speech held by a pause) | `reset_pauses` in `SceneRouter.start_fresh` (a window without the focus keeps its one level) | |
| `ModHost` (the autoload `Mods`) | chain (`CHAIN_FIELDS`: the refused mods and their reasons, the faults already reported, whether the chain changed, the `ModParts` of each running mod: its `ModSkin` and the `ModProblems` it draws) | `sync`, at the next idle moment after `Packs.events.changed`, or when a reader asks | |

Every lifetime is announced after it is cleared: `GameState._announce_all` emits the signals whose values `Hud._ready` reads (oxygen,
ink, sector, pieces, message lights), so a console that is already up shows the cleared values. The run begins at the sign-in, before
the game scene exists, so the next game's console reads nothing of the game before. `KEPT_FIELDS` lists the variables that no lifetime
clears (wiring, configuration, counters over the object's life), each with the reason.

`tests/engine/test_state_lifetimes.gd` reads each script's own variables (`Script.get_script_property_list`) and fails for one that is
in no list or in two, naming the field and the lists. It then dirties every field of a lifetime, runs that lifetime's reset and
compares the object with a fresh one given the same reset (`begin_run` with the same player, a fresh `load_sector` of the same screen,
`place_original` at the same spot, `begin_load` with the same creatures). A new variable therefore needs a lifetime before the suite
passes. The objects a `SimWorld` holds and fills from itself (the creature context, the creatures) are checked against the sim after
every path that fills them (a load, a screen, `reload_creatures`, a tick): the context's screen, sub, creatures and dice are the
sim's, and the context and creatures after `reload_creatures` are field by field those of a fresh `load_sector` of the same screen.

### A scene leaves before its children exit

Godot takes a scene out of the tree children first: `Node._propagate_exit_tree` runs every child's `_exit_tree` before the parent's.
A scene that let go of the autoloads only in its own `_exit_tree` would still be listening while its children give back what they hold,
and the game would answer a child of a departing scene (a problem screen that gives back a held lost tank would respawn the sub, save
and start a song in a scene that is going away; a held game over would count a try and leave a message holding the clock). So a scene
change runs in this order (`SceneRouter.go_to`, once the fade is black):

1. `SceneRouter.leaving(path)`: the scene is still whole and detaches itself. `Game._leave` runs once: the flow stops listening
   (`GameFlow.leave`), the message queue forgets its messages and gives back the clock (`MessageQueue.discard`), the song and the speech
   stop and the message box's sound pause is given back. Closing the window (`NOTIFICATION_WM_CLOSE_REQUEST`: save, then `_leave`) and
   `Game.quit_game` take the same step before the program tears the tree down.
2. `change_scene_to_file`: the old scene leaves the tree at once, children first. Each child is safe on its own, also when nobody told
   the scene first (a test or a tool that only removes it; `Game._exit_tree` then runs `_leave` last): a problem screen thrown away
   without `close` gives the clock back and DROPS its hold on the losses (`GameState.drop_losses`: the loss is forgotten, not announced;
   as the original does, see `ProblemScreen._exit_tree`); `SectorWorld._exit_tree` ends a dissolve that is running
   (`SimWorld.abandon_damage` drops its hold on the losses) and gives back the clock it held for it.
3. `SceneRouter.start_fresh()`: `GameClock.paused = false` and `Audio.reset_pauses()`, after the old scene has left, so nothing that
   its nodes did on their way out is held in the next one.

A profile save on the way out (Return to Sign In, Exit, the window closed) happens in step 1 or before it, with the numbers of that
moment: oxygen a problem took is saved (an empty tank as 1), a tank or a try that a held loss would have cost is not.
`tests/engine/test_scene_leave.gd` leaves a game both ways in the middle of each hold.

### Durations are data

Every length that holds up play is a number in `data/rules/durations.json`, read through `Durations` (`src/core/durations.gd`, plain
JSON): the station trips (`station.launch|dock|balloon`: opening / closing ticks, drive from / to / pixels per tick, the balloon's x
and path, in integer window coordinates), `dissolve.ticks`, `log_scan.*` (`CanisterLog.scan_ticks()`), `problem.message_ticks`
(`ProblemFlow.message_ticks()`, also the combination lock's messages), `calculator.key_flash_ticks`, `surface_ship.wait_ticks`,
`speech.silent_ticks` (how long `Audio.speak` waits with the Voice option off), `news.*`, `sign_in.*`, `fade.ticks`
(`SceneRouter.fade_ticks()`). The `rules/durations.json` of each pack of the chain is laid over it key by key (`Durations.files()`
lists the files; [`PACKS.md`](PACKS.md)). A presenter fits its drawing to the N ticks it is told and never decides N;
`tests/engine/test_durations.gd` lengthens the dock and checks that every skin plays the longer game as the plain objects do. Not in
the file: speech clip lengths (they come with the clips, [`AUDIO.md`](AUDIO.md)); the lock wheel's speed and the trigger countdown are
rule values (below).

### Rule values are data

Every number a rule runs on is in `data/rules/tuning.json`, read through `Tuning` (`src/core/tuning.gd`, a plain object): the sub
(`sub`: speeds, the collision rectangles, the sprite-cell and ink-pellet tables, the hit timings), the air (`air.max_oxygen`,
`air.max_tanks`, the spare tanks a new player and a refill give `air.refill_tanks`), the ink (`ink.max`, `ink.in_flight_max`), the sector (`sector.midpoint_screen`, the math trigger countdown
`sector.pending_ticks`, the countdown the data canister stores), the combination lock's waits (`lock_wheel`) and the creature
scripts' instruction limit (`creatures`). The file holds the original's numbers; the `rules/tuning.json` of each pack of the chain is
laid over it key by key (`Tuning.files()`; [`PACKS.md`](PACKS.md)), by the same `LayeredJson` that lays `Durations`
(`src/core/layered_json.gd`: the files down the chain, the merge, and the walk that tells a pack's file from the project's, with a
check per value handed in as a `Callable`). Not in it: the ambient bubbles (`BubbleRules`: a presenter's decoration with its own
dice) and the structure of the screen (edges, tile counts, the dock rectangle). A change to how a rule works is not a value.

`Tuning.check` judges a pack's layer on that walk (`LayeredJson.walk` with a leaf check handed in, as `Durations.check`) and `PackCheck`
reports it ([`PACKS.md`](PACKS.md), "Validation"). It is a statement of what the rules can run with, kept beside the numbers it judges:
a key the project's file lacks, a section where a value belongs, a number that is not whole (`sub.tick_hz` is any positive number) or
too large for the 32-bit tables are errors; so is a table the rules index (a value per sprite cell, the 18 picture slots, the 9
rectangles, the splash offsets) with another length than the project's, an entry out of range (a cell 0 to 8, a direction code the
step tables have), a rectangle with no size, a step, limit or countdown below its floor (`Tuning.AT_LEAST`, each with the reason beside
it) and a respawn screen the sector lacks. A value that merely strains the game is a warning (`ODD_ABOVE` and `ODD_BELOW`: a sub more
than twice the original's speed, more oxygen, tanks or ink than the console's layout has places for, a countdown over a minute, a
creature limit far from 512; and the facts across keys: a blink or bubble phase longer than the invulnerability, bubbles beyond the
four pictures, pellets in flight beyond the ink there is, an acceleration above the top speed).

There is one owner and one builder. `GameState.begin_run` resolves the `Tuning` of the chain once and the run keeps it
(`GameState.tuning`); nothing else reads the file while a run plays, and no value is a constant in code
(`tests/engine/test_tuning.gd` scans `src/` for a constant of any of these names). A rule asks the run: `SimWorld` reads `run.tuning` for the trigger
countdown, the pellets in flight and the respawn screen, and hands each part that holds its own section the run's values in one
method, `SimWorld._hand_over_tuning`, called by `_init` and by every `load_sector`, so a sim made before its run began plays by the
run's numbers from the next load (`SubModel.tuning`, `FoeVM.Context.max_instructions`; the pellets use the sub's; the run's rule hooks go to the
creatures' context the same way). `OxygenModel` is made with
the run's limits, the combination lock is handed the run's wheel waits by the problem screen, and the closing cutscenes draw the sub
by `GameState.tuning.sub`. `PlayerProfile` holds no limit: `begin_run` holds a saved record to the limits of the run it enters
(`PlayerProfile.NEW_SUPPLY` marks a new player's tanks, air and ink: the run gives its own). A tool outside a run (the screen editor, the sector overview, the
reachability search, `SectorChecks`, `PlaytestSetup`) resolves its own `Tuning` once per use and passes it to what needs it. The wall
scan reads the box the run states (`SubModel.wall_gap` and `wall_scan_box`; the reachability tables and `SectorChecks` ask the same; `SectorReach` takes the whole `sub` section, and its fast mode moves by the top speeds it states). The dev
pack states every value with a number of its own, so the engine tests, which run on it, fail wherever a rule still reads the original's
([`tests/engine/test_dev_rule_values.gd`](../../godot/tests/engine/test_dev_rule_values.gd)); the legacy pack states none and
`tests/legacy/test_tuning_legacy.gd` pins that it resolves to the original's. A test
puts a file of its own in `Tuning.extra_files`; `GameState` before any run holds `Tuning.original()` (the project's file alone). The same
holds for a combination lock and a creature context made on their own (`CombinationLock.tuning`, `FoeVM.Context.new()`): in the game
`ProblemScreen` and `SimWorld` hand them the run's values, and only a test of the part alone meets the original's.

### Rule hooks

A campaign can declare mod packs (`Campaign.mods`, pack ids), and a mod pack whose manifest has `rules` ([`PACKS.md`](PACKS.md), "Mod packs") defines **hooks**: functions of its sandboxed script that the rules ask at three
named points and nowhere else, so that a mod adds gameplay inside the tick. The original campaigns declare none, and a run of a campaign that does not declare a mod never reaches it, whatever the chain holds.
How a creator writes one is [`../create/CONTENT.md`](../create/CONTENT.md), "Rule hooks".

* **One owner, one builder, once per run.** `GameState.hooks` is a `RuleHooks` (`src/core/rule_hooks.gd`, a plain object). `GameState.use_campaign_hooks(campaign)` makes it with `ModHooks.resolve` (`src/mods/mod_hooks.gd`):
  each pack the campaign names must be in the chain in use, be a mod with rule hooks and run (`ModHost.rule_mod`), and what its manifest lists is claimed in the table (the first mod to list an instruction number, a problem type or
  the sub ability keeps it); a declared mod that is missing, was refused or lost a claim is recorded in `RuleHooks.unresolved`, warned about once (`RuleHooks.trouble`, `[rules]`) and the campaign plays on without that hook. `begin_run` calls it for the player's campaign (the
  sign-in screen), `GameFlow.enter` for the campaign of a sector played in free play; Math Practice and the tools use none, and the empty table (`RuleHooks.none()`) is what every other run has. The table
  holds the nodes it resolved, so a mod unloaded later is a fault, never a call into something else.
* **The rules hold the table, not the mods.** `RuleHooks` and `HookState` are in `src/core/` and name no node and no autoload (`test_rules_are_plain_objects`); the table's only way to a mod is one `Callable` that `ModHooks` sets over `ModLoader.call_mod`, which
  freezes the state it is handed, calls the function under the mod's instruction limit and copies what comes back. `ModApi.build` still decides alone what a mod is granted (the `rules` key holds plain numbers). A presenter or a skin never
  names the table (`test_mod_rules`).
* **Three hook points**, each a function the manifest lists, given one read-only Dictionary of plain values (`HookState`: numbers, texts, `Vector2i`, never an object) and answering plain data that `RuleHooks` validates, cuts to its
  bounds and applies through the rules (`validate_instruction`, `validate_sub`, `validate_memory`; anything else, an unknown key included, is garbage and a fault):

| Hook | Reached from | Is told | May answer | On a fault |
| --- | --- | --- | --- | --- |
| `judge_answer(state)` | `ProblemSession.submit` (`judge`, pointed by `ProblemFlow.answer_judge`, which `ProblemScreen` sets from `GameState.hooks` outside Math Practice), for a type the mod added (number 34 up) | the type, level, the record's fields, what was typed | true or false | the type's own `compare_mode` judges |
| `creature_instruction(state)` | `FoeVM._mod_instruction`: the instruction `Mod_Instruction number value` (`FoeOps.Op.MOD_INSTRUCTION`), in the creatures' step; with no mod that defines instructions it is an unknown opcode, as any byte the original lacks | the number and value, the creature (place, picture, screen), the sub, the flags | skip the next instruction, raise or lower flags, a picture, a move (ends the turn), end the turn | nothing happens, the script goes on |
| `sub_ability(state)` | `SimWorld._use_sub_ability`, at the end of the `sub` step, after the sub moved | the sub's place, velocity and picture, the keys, the run's top speeds | the sub's velocity (cut to the top speeds) and invulnerability (cut to the run's) | the sub is not changed |

* **Deterministic.** A hook is a function of its snapshot and of its **memory**: a bounded plain Dictionary per mod and hook that the table stores and passes in (`state["memory"]`) and takes out (the `memory` key of the answer, validated).
  Nothing else is given: no clock, no dice, no object, and the mod is told the tick of its load. The memory, the faults and the tick start over with every load of the creatures (`RuleHooks.begin_load`, called where `SimWorld._build_foes`
  makes them: a sector start, a respawn, the reload at the dock), so a load is a fresh start whatever the loads before it did, and the same inputs are the same play (`test_mod_rules`, `test_plays_identically`). A mod that keeps
  state in variables of its own is outside the promise; `RuleHooks.verify_pure` asks every hook twice and calls a different answer a fault, for tests and tools.
* **Bounded, with a default.** A hook that raises, runs past its limit (`ModSpec.MAX_RULE_EXECUTION_TIMEOUT`: 1 million instructions a call, never 0), is gone or answers garbage is a **fault**: the call has the default in the table above, it
  is recorded (`RuleHooks.fault_log`, the `faulted` signal, one warning per mod and run), and a mod with `RuleHooks.MAX_FAULTS` faults in a load is switched off until the next load. A tick makes at most `RuleHooks.MAX_CALLS_PER_TICK`
  calls (the rest have their default), so a tick costs at most that many calls of the limit. The loader's own quarantine (`ModLoader.MAX_FAULTS`, counted per frame) is not consulted: a rule must not depend on how many frames went by.
* **The originals provably run none.** `tests/engine/test_rule_hooks.gd` asserts that every campaign of the chain declares no mod, that a run of it resolves the empty table, and that a whole scripted visit of a sector, with the
  table's way to a mod wired to a counter, makes no call; `test_mod_rules.gd` that a mod in the chain which the campaign does not declare is never asked, and plays a visit of a declaring campaign twice and under every
  presenter and skin to the same trace.

## Derived state is built from its owner

Every piece of state has one owner: the rules (`SimWorld`, `SubModel`, `FoeModel`), the run (`GameState` and its profile), the content
(the pack chain, read through `Catalog` and `Assets`). Anything else that holds a copy of it is derived state: the creature context
the scripts read (`FoeVM.Context`), the copies a presenter is given (`SimView`), a presenter's nodes, the console, a cache of pictures
or of compiled scripts. The rule is **derive, don't patch**:

1. **One builder, reading everything from the owner.** Derived state has one function that makes it, and that function fills every
   field from the owner's live state; no field is left at a default for a later step or signal to put right. Every path that makes or
   remakes it calls that builder: the first load, a reload, a respawn, a presenter bound in the middle of a sector, a skin or pack
   change, a debug key, a tool, a test. (`SimWorld._build_foes` fills the creature context from the sim through
   `FoeVM.Context.begin_load`: the creatures, the sim's dice, the screen that is shown, the sub; so `reload_creatures` and
   `load_sector` give the same creatures and the same context.)
2. **The state is the truth, the events are changes.** A view that binds, or receives a "loaded" event, builds itself from what the
   owner holds at that moment (the pellets in flight, a dissolve that is running, a station trip), never from what it assumes the
   event implies. The events after it carry only changes. A presenter bound in the middle of anything shows what a presenter bound
   from the start shows.
3. **Change the source, not the copy.** A value that differs from what the builder would compute (a level chosen for free play, a
   debug override) is set in the owner the builder reads (the profile), not written onto the derived value, which the next rebuild
   overwrites.
4. **One entry per transition; a reset clears its whole lifetime.** A path that moves to another sector, screen, life or run (the
   game, a debug key, a tool, a test harness) calls the entry the game uses (`GameFlow`, `GameState.begin_sector`,
   `SimWorld.begin_sector` / `load_sector` / `load_screen`), not a chosen subset of its steps, and a partial path (`reload_creatures`)
   is made of the full path's named steps. A path that needs a variant of a transition gets a rules entry the game's own entry is
   built from: the screen playtest starts a sector on any screen through `SimWorld.begin_sector_on`, which `begin_sector` calls; the
   F3 key 6 opens any problem through `SimWorld.open_problem`, which `open_pending_problem` calls. A reset that clears part of a lifetime clears all of it, through that lifetime's reset ("Lifetimes of
   state").
5. **A cache names what it derives from.** A cache of content (pictures, compiled scripts, tables) is cleared by the signal of its
   source (`Catalog.packs_changed`, a skin change, the resource's `changed`) or keyed by it.
   A view that draws what a mod draws never holds the mod: `ModDiagram` asks `ModHost` which mod draws its type each time it is asked and when `ModHost.mods_changed` is emitted.
6. **Harnesses take the game's paths.** What runs in the game runs in the test: a scenario step makes the call the game makes, and the
   creatures tick wherever they tick in the game. A shortcut that skips a step hides exactly the bugs of this rule.

## The view of a sector: `SectorWorld` and presenters

`SectorWorld` (`src/gameplay/sector_world.gd`) owns one `SimWorld` (`sim`), takes the player's hands once per tick, calls
`sim.tick(input)`, passes the tick fraction to its presenter every frame and tells `Game` what happened. What draws is a
`SectorPresenter`, a child node (`presenter`; `replace_presenter` swaps it). `src/gameplay/sector_presenter.gd` is the contract:
what a presenter receives (a `SimView`, `src/rules/sim_view.gd`: copies of the state of everything that moves with its previous place,
the tick fraction every frame, and the sim's events ending with `ticked`), what it may be asked (`refresh`, `show_between_ticks`,
`show_debug`: all instant; nothing waits for it) and what it must not do (change a rule or decide a length). Every event with its
arguments and its place in the tick is in [`../create/SKIN_API.md`](../create/SKIN_API.md), pinned by `tests/engine/test_skin_api.gd`.

- `OriginalPresenter` (`src/gameplay/original_presenter.tscn`) is the original look: `Sub`, `Foe`, `InkPellet`, `Collectible` and
  `MathTrigger` are plain `Node2D`s that only show their model. The creature "glide or hop" choice is the view's (`Foe.follow`).
- `DebugRectPresenter` (`src/gameplay/debug_rect_presenter.gd`, no scene, no child nodes) draws only what the rules test, in one
  `_draw()`: the walls and currents of `sim.tile_grid`, the sub's hurt rectangle and wall box, the creatures' hit rectangles, the
  pellets, pieces, triggers, the dock, the door and balloon of a supply trip and the dissolve. With `backdrop = false` it is an
  overlay over another presenter bound to the same sim.
- A skin mod (`ModSkin`, [`PACKS.md`](PACKS.md), "Mod packs") is shown by the original presenter, which hosts the layers its script draws (`ModLayerHost`, made by `OriginalPresenter.bind` from the skin worn; null for any other skin). It reads `view` only, like every skin: after any event it builds the state once more as plain data (`SkinState.build`) and each frame asks the mod's sandboxed script for a draw list for each layer the manifest names (`skin_layer(name, ...)`; for a script that draws the whole screen, one `skin_frame`, the same host with one slot over every layer), checks it and draws it in a `ModLayerStack` (`ModLayer` nodes) standing right behind the layer's node, which it places again whenever the presenter orders its layers (`_arrange`: the supply trips draw in another order). The layer's own node is made transparent (`modulate`, not `visible`, which the original's code decides) while the script's answer is on, derived from "has the script answered for it" each time, so a layer that faults, a quarantined mod and a mod that has gone are the original's layers. The state tells the screen too (`background`, `decos`, `anim_decos`, `station`, by skin key): `SkinState` reads it from `SimView` (`decorations`, `anim_decorations`, `station`, and `screen_ticks`, the ticks the shown screen has run, `SimWorld.screen_started_tick`, from which an animated decoration's entry is derived) and builds all of it again with the rest, so a skin bound on any screen is told what one bound from the start is. Its draw list may name those keys back: `ModDraw` resolves a picture key through `Assets.picture_by_key`, the lookup the original presenter's pictures come through, under the presenter's skin, so the two show the same pictures.
  Nothing of the game is granted to the script, and a script that faults leaves the original's layers and changes nothing of the tick.
- `PresenterChoice` (`src/gameplay/presenter_choice.gd`) is the one place that knows the names: `-- --presenter=debug_rects`,
  `-- --overlay`, `PresenterChoice.forced`. While a game runs (editor or debug build) F3 then R swaps the original look and the
  rectangles (`SectorWorld.toggle_presenter`), F3 then O lays the rectangles over the picture; in the sector viewer P and O.

```
tools/godot.sh --path godot -- --presenter=debug_rects
tools/godot.sh --path godot res://src/debug/sector_viewer.tscn -- --presenter=debug_rects --sector=3 --fly
```

### What keeps the split true

- **The rules are plain objects, and a test reads their source.** `tests/engine/test_rules_are_plain_objects.gd` fails with file:line
  and the word if the rules name `Node` (or any node class, or a script class made of nodes), `Texture2D`, `Font`, `TileMapLayer`,
  `Input`, a `Tween`, `Timer`, `AnimationPlayer`, `get_tree`, `Engine` / `OS`, or an autoload. Comments and strings do not count and
  a word counts only whole (`tests/engine/source_scan.gd`, shared with the other source-reading tests). Guarded: `src/rules/`,
  `src/core/`, `src/ui/message_queue.gd` and the problem models listed by name in the test (`ProblemFlow`, `ProblemFactory`,
  `CalculatorModel`, `LockWheel`, the diagram timelines ...), less the loaders in the test's `EXCLUDED` list, each with its reason.
  Every other file of `src/problems/` must be a view or excluded with a reason, so a new file cannot slip in unclassified.
- **A whole sector plays with no presenter.** `tests/engine/test_headless_sectors.gd` plays scripted visits
  (`tests/sector_scenario.gd`: launch, flight, a screen change, a trigger and its problem, the canister's problem that costs the tank, a
  lost tank, dock and balloon, the closing in a finale) and whole missions with `GameFlow`, a fake view and a fake store, and counts the
  engine's nodes: the rules made none.
- **The harnesses take the game's paths** (rule 6 of "Derived state is built from its owner"). The creatures tick in every tick of a
  harness, the station trips included, as they do in the game; only the sector viewer's pause freezes them (`SimWorld.foes_active`), and a
  test that needs the same creatures every time seeds `SimWorld.foe_rng`. `tests/headless_stage.gd` (the playfield of a `GameFlow` made of
  a `SimWorld` alone) passes the dock on and waits for a trip exactly as `SectorWorld` does ("Nothing the owner does runs inside a tick"
  below), and plays a trip asked for while it runs a tick after that tick. A scripted
  visit runs the game's own `GameFlow` around its stage: the flow starts the sector, answers the problems, respawns the sub
  (`GameFlow.respawn`), opens the lock and completes the sector (`complete_sector`: the creatures start over, then the dock and the
  balloon). What the script does that a player cannot is a test input: it moves the sub to a screen, entering it as a flight does (the
  rules lay it out, the run hears `screen_entered`), places it, and takes a piece where it lies (`SimWorld.take_piece`).
- **The game plays identically with any presenter.** `tests/engine/test_plays_identically.gd` plays the same visits with no
  presenter, the original one, the debug rectangles, a blank one and every skin; compares every event with its tick, the rules' state
  after every tick and the length of each step that holds up play; swaps the presenter mid-visit; and plays a whole mission through
  the real `Game` scene. `tests/sim_trace.gd` records the trace; `tests/engine/test_sim_world.gd` makes ten flights over dev sectors with
  scripted hands and no scene (the original's pinned digest is `tests/legacy/test_creatures_legacy.gd`); `tests/engine/test_presenter.gd` binds a presenter to a bare sim;
  `tests/engine/test_presenter_binds_late.gd` binds every presenter and every skin in the middle of a flight with ink, a dissolve, a supply
  trip and the creatures' reload, and compares what it shows with one bound from the start (rule 2 above: `OriginalPresenter` builds its
  pellets, the station's trip and the sub's dissolve from the sim in `bind` and on every load, and a new `Foe` decides "glide or hop" from its model).
- **The console is derived once.** `ConsoleState` (`src/ui/console_state.gd`) makes the console's state as plain data from `GameState` and the
  layout in use: the gauges' values and slots, the low-air warning, the capsule pieces, each label's picture, word and box, the lights and the
  rectangles of every part (`ConsoleState.rects`, from the layout's data). `Hud` takes each of those from it (its signal handlers call the part they own: `ConsoleState.oxygen`, `labels`, `lights`) and
  holds no copy of the logic, so what a script is told of the console and what the HUD shows are one fact. `tests/engine/test_console_state.gd`
  plays a game and finds every field in the HUD's nodes after every step, with the original's pictures and a skin with text, and shows a HUD made
  in the middle the same. The blink of a light and the pulse of the warning cell are the HUD's two `AnimationPlayer`s (the one clock the glow is drawn
  from), and the state carries where they are (`phase`) so a script blinks with them.
- **The console's layers are the sector's mechanism.** A skin mod's script may draw parts of the console as it draws layers of the sector: the HUD makes a
  `ModLayerHost` (`ModLayerHost.make_hud`) for the skin it wears, the same class `OriginalPresenter` makes for its layers, with the HUD as its site (`Hud.layer_nodes`,
  `layer_clip`, `console_state`; the presenter's site is its layer nodes and `SkinState.build`). Each part a script draws has a stack in a clipping `Control` of the
  part's rectangle behind the part's original nodes, which are made transparent (`modulate`: the HUD's own animations use `self_modulate`) while the script has answered; the
  state is built again every frame from `GameState` (no copy to go stale), `Hud._process` runs only while a host exists, and the host is made again whenever the HUD puts
  a skin on (`_apply_skin`), so a skin put on, taken off or quarantined and a HUD made in the middle of anything show what the first shows (`tests/engine/test_mod_skin_hud.gd`;
  `test_plays_identically.gd` plays every skin of the roster with a `Hud` beside the world).

## The flow of a mission: `GameFlow`

What happens next in a mission is a plain object too, `GameFlow` (`src/rules/game_flow.gd`): the start of a sector (the song, the
launch or the start screen), the dock (pieces missing, or the combination lock), the supply message, the balloon and the next sector, a
lost tank (the respawn), game over (the sector starts over), the finale (docking in it, or the closing sequence), the Hall of Fame, the
new-player hints, the saves, and the Options questions. `Game` (`src/gameplay/game.gd`) is its view: it makes the screens, dialogs
and layers, opens its dialogs through a `ModalHost`, holds the music and the clock while a dialog is up, wires the menu bar and the closing sequence's keys, and answers by
returning from what the flow `await`s.

The edge is explicit: `GameFlow.VIEW_METHODS` is what the view implements (`show_pieces_missing`, `show_supply_message`,
`show_problem`, `show_closing`, `show_hall_of_fame`, `play_sector_music`, `stop_music`, `go_to_sign_in`, `quit_game`) and
`GameFlow.STAGE_METHODS` what the playfield implements (`SectorWorld` does). The flow reaches for no autoload: it is handed the
player's numbers, the save store, the playfield, the message line and the view. `tests/engine/test_game_flow_machine.gd` plays a whole
mission with a fake view, a fake store and a `SimWorld` for a playfield (`tests/headless_stage.gd`). What differs between games the
flow asks of its `campaign`; it knows no sector number.

### Nothing the owner does runs inside a tick

A tick (`SimWorld.tick`, one pass of `DoAction`) runs all its steps on the state it began with. Whoever runs it (`SectorWorld`, the
test stages) and the flow behind it go on only between two ticks, never in the middle of one, so a load (a sector start, a respawn,
the next sector), the reload of the creatures after the lock and a station trip always begin between ticks, and no step of a tick runs
on a sector that was loaded inside it. It is the original's shape: a new sector is the entry of a new `DoAction`, which `Main` (0x427bb4)
calls only after the last one returned, and each trip is a loop of its own that the next call follows (`EnterSupplyStation` 0x432b96,
then the supply message, then `LaunchBalloon` 0x432eae; [DESIGN.md](../port/DESIGN.md) 3.7).

The property is built in, not left to each caller:

- **One door back from the tick: `SimWorld.after_tick(action)`.** It runs `action` at once when no step of a tick is running, otherwise
  when the running tick is over (after its `ticked` and the count of `tick_number`, or where it ended early or stopped for its
  problem). `SimWorld.is_ticking()` says which.
- **The owner awaits only signals said between ticks.** A trip ends twice: `sequence_finished` in the `sub` step, for the presenters
  (the skin API's table), and `sequence_over` through `after_tick`, for whoever waits to go on (`SectorWorld.launch` / `dock` /
  `send_balloon`, `HeadlessStage`). The playfield hands the dock to the flow through `after_tick` too (`SectorWorld.dock_reached`), so
  the lock, `GameFlow.complete_sector`, its trips and the next sector begin between ticks even when the view answers at once.
- **The rules say it loudly when it is broken.** `SimWorld.load_sector`, `reload_creatures` and the start of a trip `push_error` when
  they are called while a tick's steps run.
- **A test checks the whole design, not a call.** `tests/engine/test_owner_between_ticks.gd` watches every load and trip of scripted
  visits (plain objects and the `SectorWorld` scene) and of a mission whose view answers at once, and reads the source: an `await` on a
  signal of the rules or of the playfield must wait for one said between ticks.

What the tick asks of its owner inside a step is answered there, because the original does it inside the pass: a math problem
(`problem_requested`; the rest of the tick waits for `problem_resolved`, "Problems" below) and the finale (`finale_reached`: the flow
stops the sub and asks for the closing, as `DoAction` calls `VoyagerClosingSequence` (0x41c206) in its finale test and never finishes
that pass). A lost tank reaches the flow through the run (`tank_lost`, `game_over`), which `GameFlow` defers (`defer_call`).

### The tree of the game scene

```
Game (Node, game.gd)                                                the view of a GameFlow; shows what the flow asks
 |- Backdrop (ColorRect)
 |- Hud (Control)           console art, gauges, lights, frame; OBSERVES GameState through signals, shows what ConsoleState says (before SectorWorld, so the frame
 |                          does not cover the playfield's column x = 16)
 |- SectorWorld (Control 608x288 at (16,32), clip_contents)        the playfield; owns the SimWorld, the clock, the hands
 |   |- Presenter (OriginalPresenter, Node2D)                       shows the SimWorld (any SectorPresenter can take its place)
 |   |   |- Background, BackDecos, Walls (TileMapLayer), Currents (TileMapLayer, hidden), Station, MidDecos, Collectibles, Triggers
 |   |   |- Sub (Node2D), Foes, Pellets, FrontDecos, AnimDecos, Bubbles      (draw order = this order in play; while a supply trip
 |   |   |  runs the presenter moves Station between Sub and Collectibles: MidDecos, Sub, Station, Collectibles)
 |- MenuBar (GameMenuBar)   File / Options / Help (the original's texts)
 |- GameDebug (CanvasLayer) F3 cheats; deletes itself in release builds (OS.is_debug_build())
 |- ProblemLayer (CanvasLayer 10)   a ProblemScreen, SurfaceShipScreen or closing sequence is added here while it plays
 |- DialogLayer (CanvasLayer 20)    MessageBox, Hall of Fame, Help, Customization, Audio settings (modals of `Game.modals`: ProblemLayer
                                   sleeps while one is open)
```

### Problems

A math problem is a step machine, `ProblemFlow` (`src/problems/problem_flow.gd`, a plain object), with `ProblemScreen` as its view.
`ProblemFactory` picks a stored record of a `ProblemType` (the original stores problems; it does not generate them), `ProblemTexts`
words it, `AnswerChecker` judges it, `Calculator` / `CalculatorModel`, the diagrams (`src/problems/diagrams/`) and the combination
lock (`CombinationLock`, `LockProgram`, `LockWheel`) are its parts. A tick that opens a problem finishes when the problem is resolved,
as the original's `DoMathProblem` returns, unless the problem cost the tank: then the tick ends there (`SimWorld.problem_resolved`;
[DESIGN.md](../port/DESIGN.md) 3.10). `src/debug/problem_menu.tscn` plays any of the 34 types at any level.

The flow also says what HAPPENED, once, in its `happened` signal (`ProblemEvents`: started, step, verdict, damage, success, timeout; the table is in
[`../create/CONTENT.md`](../create/CONTENT.md), "Problem screens"): each is made after the flow decided it, a `step` is told when an input has been dealt
with (`_settle_step`), and the screen, which makes the diagram before the flow begins, passes each to it (`DiagramBase.told`), where a `ModDiagram` keeps them for the script's next frame. No view infers
a moment of its own; `tests/engine/test_problem_flow_machine.gd` pins the sequences without a scene.

The position of a build-up or a replay has one owner as well: the diagram that plays it (`DiagramBase.animation_name` / `animation_tick` / `animation_length`), moved only by `animate_to` with the tick the flow counts
(`presentation_elapsed`, which the flow announces with `presented` before it ends the step the tick ends), so it stands still when the flow's time does and its length is the timeline's data. A `ModDiagram` reports it to a mod as the state's `clock` and asks for no length: the flow waits for the plain
diagram's timeline, whatever the mod draws or asks for (`tests/engine/test_mod_problem_animation.gd` counts the ticks with and without each mod).

## Campaigns in code

A campaign is a `Campaign` resource (`src/resources/campaign.gd`): the ordered `sectors`, the `finales`, `default_edu_levels` per zone,
the canister log (`log_unlock_order`, `log_texts`, `log_voices`, `log_series`), the supply messages (`supply_texts`, `supply_voices`),
`fallback_song`, `closing_scene` (`voyager`, `expert`, or empty for the generic finale with `finale_text` and `finale_picture`), the
name (`title_text` / `title`), and the HUD banner (`banner_index` or its own `banner`).
Its methods answer what the original computes with `>= 30`, `/ 15` and `% 15`: `is_finale`, `position_of`, `next_progress`,
`default_edu_level`, `log_count / log_newest / log_entries`, `supply_text_name`, `song_for`, `display_title`; `problems()` lists what
is wrong with one. The field reference for authors is [`../create/CONTENT.md`](../create/CONTENT.md), section 3.

- **Finding one.** `Catalog.campaigns()` (every campaign of the pack chain and of `res://data/campaigns/`, `voyager` and `expert`
  first), `Catalog.campaign(id)`, `Catalog.campaign_of_sector(n)` (a sector belongs to one campaign; `Catalog.campaign_problems()`
  checks), `Catalog.campaign_for_game(0|1)` / `game_of_campaign(id)` (the save file's game numbers), `Catalog.default_campaign`.
  `PlayerProfile.campaign()` is the one place that turns what a save holds into a campaign.
- **What stays with the sector.** `SectorData.zone`, `music_name` (the stem of a MIDI file; `MusicCatalog.songs_by_stem` gives the
  song, `Campaign.song_for` adds the fallback) and `finale_screen` (the screen where the closing starts; -1 for an ordinary sector).
- **Who asks.** `Progression`, `CanisterLog`, `AudioService.music_for_sector`, `GameFlow.campaign`, `Hud`, `SignIn`,
  `NewPlayerDialog` (one button per campaign), `HallEntry`, `SurfaceShipScreen`. Functions that can take another campaign
  (`Progression.next_progress(progress, campaign)`, `CanisterLog.count(sector, campaign)`) are how a test plays a made-up one.
- **Words of its own.** `Campaign.text(value)` looks a registry text name up and returns anything else as written
  (`display_title()`, `log_entry_text(n)`, `supply_message_text(sector)`, `finale_message()`). A voice group that is empty or names no
  group is not spoken.
- **Generic finale.** A `closing_scene` that is neither `voyager` nor `expert` makes `Game.show_closing` put up `GenericFinale`
  (`src/story/generic_finale.tscn`, a `StorySegment`): the title, `finale_texture()` (a `ui_picture` name or a `res://` path) and
  `finale_message()`; Enter / a click go on, Space / Escape skip; then the Hall of Fame.
- **Saves.** A player and a Hall of Fame row store `campaign` (the id), and `game` (0 / 1) for the originals; a file without an id is
  read by `game`. `progress` is `sector id * 2 + midpoint flag`, the original's word, validated against the campaign's list (a sector
  not in the list loads as the campaign's start). A record whose campaign is not in the chain is kept and unplayable
  (`PlayerProfile.is_playable()`; sign-in shows "not installed"). `SaveStore.FORMAT_VERSION` is 2; format 1 files are read by the same
  code and written back as 2. A saved `pieces_mask` is checked against the sector when it loads (`GameState.set_sector`).
- **Tests.** `test_campaign.gd`, `test_campaign_saves.gd`, `test_generic_finale.gd`, `test_campaign_sign_in.gd`
  (`tests/campaign_shelf.gd` is a scratch campaigns folder), `tools/import/test_step_campaigns.py`.

## Cutscenes: timelines as data

```
tools/import/step_story.py  (the importer's "story" step: extracted/tables/opening.json, extracted/tables/expert_closing.json and the decompiled loops of CLOSING.C)
tools/dev_pack/dev_story.py (the dev pack's own, short and made up)
  v
a pack's data/story/*.tres   CutsceneTimeline: a length, tracks (actor name, property word, moments in ticks of the 73 Hz timer, values with
  |                 picture / sound / text NAMES of the registry) and cues (sounds, events). No node, no path, no Animation in it.
  |   news_cartoon, news_ambient, title_ship, title_reveal, expert_hoist, expert_deck, expert_wait
  |   (+ story_script: the story pages; voyager_closing_script: the Voyager flight's loop counts; closing_crew: the Expert closing's six sailors' programs)
  v
Catalog.story_timeline / story_script / voyager_closing_script / closing_crew     the first pack of the chain that holds the file (`Packs.resource`)
  v
src/story/cutscene.gd        Cutscene.animation(timeline, cast) builds an Animation; the scene's AnimationPlayer plays it
src/story/cutscene_cast.gd   CutsceneCast: "the actor crew_4 is the Crew4 sprite", and how a name becomes a texture (a skin changes this)
```

A timeline is the same on every skin: a skin redraws a cutscene by binding its own nodes and resolvers and takes exactly as long,
because the time is in the data. The choreography is the pack's: the original's is in the legacy pack, never committed; the dev pack has its own,
and `PackNeeds.FILES` requires every one of these files of a complete pack, so a chain always answers (the dev pack at its bottom) and a pack that
lacks one is reported by the start-up check and `PackCheck`, as it is for the news cartoon. Two small timelines are made in code because nothing in
the original is behind them (the fade of a story page, the flicker of the console lights); `CutsceneTimeline.provenance` says which numbers are the
original's. `SurfaceShipScreen` has no timeline: it counts `surface_ship.wait_ticks` from `Durations`. Tests: `tests/legacy/test_cutscene_timing.gd`
(the hash of each cutscene's timing record, from the timeline and from the animation a scene builds, against `tests/fixtures/cutscene_timing.json`), `tests/legacy/test_story_timelines_legacy.gd` (re-derives the timelines
from the analysis), `tests/engine/test_story_timelines.gd` (well formed, every name exists, the scripts run), `tests/engine/test_opening.gd` (the
scenes play the dev pack's timelines: the nodes show what the tracks say), `tests/engine/test_cutscene_timeline.gd` (the machinery).

## Autoloads

| Name | Script | One reason to exist |
|---|---|---|
| `GameClock` | `src/autoload/game_clock.gd` | the original's 12.17 Hz logic tick (`tick` signal); pausing it pauses the game |
| `GameState` | `src/autoload/game_state.gd` | the running player's numbers (oxygen, tanks, ink, pieces, midpoint); views observe it; its lifetimes are in "Lifetimes of state" |
| `SaveStore` | `src/autoload/save_store.gd` | the roster and the Hall of Fame as JSON in `user://` |
| `SceneRouter` | `src/autoload/scene_router.gd` | scene changes with a fade; scenes pass nothing to each other except through `GameState` |
| `Audio` | `src/autoload/audio.gd` (class `AudioService`) | music, effects, speech; buses `Music`, `SFX`, `Voice` |
| `WindowHotkeys` | `src/autoload/window_hotkeys.gd` | Alt+Enter fullscreen |
| `Mods` | `src/autoload/mod_host.gd` (class `ModHost`) | the one owner of the running mods of a mod pack: derived from `Packs.chain()`, run by `ModLoader` in a Sandbox ([`PACKS.md`](PACKS.md), "Mod packs") |

`_mcp_game_helper` is the editor-integration addon's own autoload (`addons/godot_ai/`). Everything else is a plain class with
`class_name` (`Catalog`, `Progression`, `FoeVM`, `OxygenModel`, `PracticeSet` ...): logic that does not need to be a node is a
`RefCounted` with `static` functions, which is also why it is easy to test.

## Where the data comes from

```
NEPTUNE.ISO  (your copy; read by tools/gamefiles.py, never by Godot)
  |  tools/import/import_all.py  steps extract, tables              (docs/play/LEGACY.md)
  v
extracted/   PNG / WAV / MIDI / text / binary tables                (git-ignored)
extracted/tables/  the game's own tables read from the ISO          (sectors.json, audio_map.json, music_map.json ...: git-ignored)
tools/analysis/data/  our analysis of the program                  (committed: layouts, field meanings, console and slot tables)
  |  the other importer steps
  v
godot/packs/legacy/   THE LEGACY PACK (git-ignored, never edited by hand but for the creature scripts and screens, docs/port/FIDELITY.md)
  assets/   PNG, WAV, OGG          data/   .tres: SectorData, ProblemType, HudLayout, SpriteFrames, TileSet, catalogs ...     midi/
godot/packs/dev/      the dev pack: the same layout, placeholder content, committed (tools/dev_pack/)
godot/data/           project-level and committed: rules/durations.json, rules/tuning.json, sectors/foe_annotations.json,
                      ui/menu_layout.tres; sectors and campaigns you make
  |  Catalog, Assets, the sound catalogs, Durations, Tuning - through the pack chain (Packs)
  v
src/   the Resource classes in src/resources/ describe the data; the scenes and scripts use it
```

The numbers that make the game feel right (the sub's speed, where each gauge sits, how long a lock wheel turns) are never typed into
a script: they were read from the original's code and live in the pack's `data/` (or `godot/data/` for the rule values and the menu layout, which no
tool reads from the original). To change one for the original, change the importer and run it again; a pack of your own changes its own data.

**Layout is data too**: where a hit area is and how big a panel is never comes from the picture or the font that is loaded. The
importer puts the original's picture sizes next to the positions (`size` in the ballast and lock diagram specs of
`data/problems/problem_type_*.tres`, `picture_size` / `digit_sizes` in `data/ui/calculator_layout.tres`, `picture_sizes` in
`data/bubble_rules.tres`, `line_separation` in `data/problems/screen_layout.tres`; the project's `data/ui/menu_layout.tres` for where
the menu popups open). `tests/engine/test_layout_from_data.gd` fails if layout code asks a texture or a font for a size, so a skin with
other pictures cannot move a button or change a random draw.

## Folders

| Folder | Contents |
|---|---|
| `src/autoload/` | the singletons above |
| `src/core/` | pure logic and loaders: `Catalog`, `Packs` / `Pack` (the chain), `Assets`, `Durations`, `Tuning` / `SubTuning` / `LayeredJson` (the rule values), `NameRegistry`, `Progression`, `FoeVM` / `FoeAsm` / `FoeOps` (the creature bytecode and its assembler), `RuleHooks` / `HookState` (the table of a run's rule hooks and the plain state they are told), `OxygenModel`, `HintSystem`, `HallOfFame`, `PracticeSet`, `TickMeter` (real time to the original's ticks), `TileGrid`, `InputSnapshot`, `ResourceJson` / `SectorJson` ... |
| `src/resources/` | typed `Resource` classes for the data (`SectorData`, `ScreenData`, `FoeData`, `Campaign`, `ProblemType`, `CutsceneTimeline` ...) and `PlayerProfile` |
| `src/rules/` | the rules as plain objects: `SimWorld` and its models, `SimView`, `StationSequence`, `GameFlow`. Nothing in here may be a node, a texture, a font, `Input` or a `TileMapLayer` |
| `src/gameplay/` | `game.tscn` (the view of `GameFlow`) and the playfield: `sector_world`, `sector_presenter`, `original_presenter`, `debug_rect_presenter`, `presenter_choice`, the parts (`sub`, `foe`, `ink_pellet`, `collectible`, `math_trigger`, `supply_station`, decorations, `bubbles`) and `input_reader` |
| `src/problems/` | the 34 math problem types: `ProblemFactory`, `ProblemFlow`, `ProblemScreen`, `Calculator`, the diagrams, the combination lock, `PracticeMode` |
| `src/story/` | the opening (`Opening`, `NewsCartoon`, `TitleScene`, `StoryPages`), the closings (`VoyagerClosing`, `ExpertClosing`, `GenericFinale`), `SurfaceShipScreen`, `StorySegment`, `Cutscene`, `CutsceneCast` |
| `src/ui/` | sign-in, Hall of Fame, dialogs, the menu bar, `Hud`, the message queue, the pack screen and warning, `theme_builder.gd` |
| `src/skins/` | `GameSkin`, `SkinChoice`, `RenderSettings`, `HudLabels`, `ScaledTexture` ([`SKINS.md`](SKINS.md)) |
| `src/audio/` | `MidiMusic` ([`AUDIO.md`](AUDIO.md)) |
| `src/checks/` | Check sector: `SectorChanges`, `SectorChecks`, `SectorReport`, `check_sector.tscn` ([`EDITORS.md`](EDITORS.md)) |
| `src/mods/` | mod packs: `ModSpec` (the manifest entry), `ModLoader` (runs a script in a Sandbox, watches its health), `ModApi` (what a mod is granted), `ModHooks` (a campaign's declared mods resolved into the run's rule hooks), `ModParts` (the one record of a running mod and the one judgement of its pack), `ModDraw` / `ModLayer` / `ModAssets` / `ModShader` (the draw list of a skin or a problem screen, checked and drawn), `ModProblems` / `ProblemState` (problem screens) ([`PACKS.md`](PACKS.md)) |
| `src/packs/` | the pack tools: `PackCheck` / `PackReport`, `PackExport`, `PackInstall`, `PackCopy`, `PackChoice`, `PackFiles`, `pack_tool.tscn` ([`PACKS.md`](PACKS.md)) |
| `src/debug/` | scenes for looking and tuning, each runnable with F6, and `GameDebug`; nothing in the game depends on them (below) |
| `addons/` | the editor plugins ([`EDITORS.md`](EDITORS.md)), gdUnit4, `midi/` (the MIDI player), `godot_ai/` (editor integration) |
| `skins/` | the project's skins: `original`, `creatures` (a skin pack, `examples/packs/modern/`, lives outside the project) |
| `packs/` | `dev/` (committed) and `legacy/` (made by the importer, git-ignored); any other pack folder there is git-ignored |
| `data/` | project-level data (above) |
| `names/` | the hand-made name registry `original.json` ([`../create/NAMES.md`](../create/NAMES.md)) |
| `themes/`, `fonts/` | the one project Theme and its font |
| `tests/` | gdUnit4: `engine/`, `legacy/`, shared helpers, `fixtures/`, test skins ([`DEVELOPING.md`](DEVELOPING.md)) |

### Debug scenes (`src/debug/`)

| Scene | What it is |
|---|---|
| `sector_viewer.tscn` | browse every sector and screen: `[` `]` sector, arrows screen, `C` currents, `H` collision shapes, `T` triggers, `L` level, `F` fly, `P` debug rectangles, `O` overlay; `--snapshot=` writes a PNG |
| `sector_overview.tscn` | all 12 screens of a sector on one map ([`EDITORS.md`](EDITORS.md)) |
| `foe_sandbox.tscn` | what every creature does: its current instruction as `label+offset: Mnemonic operands` and the `.foe` line (`FoeSourceMap`); `--foe=N`, Tab cycles; the Foe Script editor's "Run in sandbox" starts it |
| `screen_playtest.tscn` | flies one screen from a chosen state (`PlaytestSetup`); the screen editor's "Playtest screen" starts it |
| `skin_compare.tscn` | one sector shown twice, the original skin and another ([`SKINS.md`](SKINS.md)) |
| `problem_menu.tscn` | any of the 34 problem types at any level; `--snapshot=` writes a PNG |
| `new_sector.tscn` | a new sector from the command line ([`EDITORS.md`](EDITORS.md)) |
| `reach_report.tscn` | the reachability sweep of every sector (`ReachSweep`), or of the sectors named after `--` |
| `sub_sandbox.tscn`, `sound_test.tscn`, `asset_preview.tscn` | a hand-made room for tuning the sub; every effect, speech clip and song; a smoke scene of assets |

The command-line options of each are listed in [`../create/MAKING_CONTENT.md`](../create/MAKING_CONTENT.md), B5.

The scenes that play a sector (the sector viewer, the skin comparison, the creature sandbox, the screen playtest) start a sector,
show a math problem and answer a lost tank through one `ToolRun` (`src/debug/tool_run.gd`): the run's half of a sector start
(`GameState.begin_sector`) and then the rules' (`SectorWorld.load_sector`); a problem as `GameFlow.open_problem` shows it; a lost
tank or game over a little later, outside the signal, as `GameFlow` answers it (the screen playtest starts its setup over instead).
So no tool skips a step of the game's transition or runs it at another moment. Tests: `test_tool_run.gd`,
`test_foe_sandbox_debug.gd`, `test_screen_playtest.gd`.

## The theme

All UI looks come from one Theme, `themes/neptune_theme.tres` (Project Settings > GUI > Theme > Custom). Change colours or sizes in
`src/ui/theme_builder.gd` and rebuild it:

```sh
tools/godot.sh --headless --path godot -s res://src/ui/theme_builder.gd
```

`ThemeBuilder` is also the one place any other `Theme` is made. A skin that says how the menus look (`GameSkin.menu_theme`, a `SkinTheme`: font, named colours, panel and button styles, pictures by key; a skin mod's `skin.theme`, [`../create/SKIN_API.md`](../create/SKIN_API.md) "The menus' theme") is worn by the PROJECT theme itself, in
place: `SkinChoice.select` calls `ThemeBuilder.apply`, which lays `derive(data, skin)` (the engine's theme, `ThemeBuilder.engine()`, with only what the skin says changed) over it, or the engine's own over it again for a skin that says none. It is not a theme set on a root node, because a
`CanvasLayer` (where the dialogs and the message box live) breaks the chain of a theme set on a node, and not a step of each screen: every control with no theme of its own looks the project theme up, so a screen open when the skin changes is told by Godot, and a screen opened later is born in it. The
merge is never preceded by a `clear` (an empty theme for a moment makes every control size itself by the fallback font, and a control that grew does not shrink back). A control that must look different for a while (the sign-in button pressed, the calculator's lit key) switches its `theme_type_variation` (`SignInPressed`, `CalcKeyLit`); the variations hold the same boxes and colours as the `pressed` items they are derived from, in the engine's theme and in `derive` alike (`ThemeBuilder.COLOR_ITEMS`, `STYLE_ITEMS`), so nothing is copied and a skin put on in the meantime shows in them.
The text the problem diagrams draw is in the engine's font (`ThemeBuilder.engine_font`) whatever the skin says: the data puts each word at a pixel and a width, so a font of other widths would run over its picture.

The problem screen's frame is themed the same way ([`../create/SKIN_API.md`](../create/SKIN_API.md) "The problem screen's frame"). Its controls look the theme up and set no colour or style by hand: the labels and the text box have the theme's `text`, the line of an error is the type variation `ProblemWrong` (`ProblemScreen._say`; the engine's red is `ThemeBuilder.WRONG`), a key of the calculator is the variation `CalcKey` (the `key` style) and a lit one `CalcKeyLit` (`Calculator._light`: the `key` style's pressed look), and `LcdDisplay` reads the field it draws the digits on from the theme (`LcdDisplay` / `field`, the `display` colour). Its pictures are put on by one builder in each of `ProblemScreen`, `Calculator` and `AnswerBox` (`_dress`; the last two share `CalculatorPanel._dress_panel`, "Derived state is built from its owner"), which `_ready` and a skin change (`SkinChoice.events.changed`) both call: each picture is stretched to the rectangle the layout gives it (`expand_mode` of the `TextureRect`, `draw_texture_rect` of a digit), so a skin's picture of another size moves no control.

## Mechanisms worth knowing

Non-obvious choices that the code embodies; the original's side of each is in [`../port/DESIGN.md`](../port/DESIGN.md).

- **The clock.** Game logic runs on the 73/6 Hz tick; after a stall at most 5 ticks are caught up (`src/autoload/game_clock.gd`).
  Pauses are a hold counter (`GameClock.hold()` / `release()`), so nested dialogs cannot release each other's hold.
- **Sub movement** is the original's integers per tick: velocity in 1/8 px, `v >> 3` px moved, x kept even (`src/rules/sub_model.gd`,
  `SubTuning.step_velocity` / `displacement`); only the drawing is smoothed between ticks (`src/core/tick_smoothing.gd`). Walls use the
  original's tile scan with one fixed box (the run's `wall_box`, 80 x 32 in the original); the per-frame rectangles are only for creature contact. The sub's position is its
  picture's centre in playfield pixels (`SubModel.place_original` converts from the original's top-left in window pixels).
- **Coordinates.** Creatures, decorations, pieces and triggers keep the original's window coordinates in data; views subtract the
  playfield origin (16, 32). The playfield is a `Control` with `clip_contents` (decorations reach below y = 288); an empty finale screen
  draws black.
- **Contacts** are tested once per tick with inclusive edges; only the first touching hostile creature counts, and not again if it was
  the first last tick (`SimWorld`, `FoeModel.rects_touch`). A creature with damage 0 still runs its contact script (the finale's treasure
  sets flag bit 15 that way).
- **A pack's trouble is told once** (`src/core/trouble_log.gd`, `TroubleLog`). Wherever the game falls back because of what a pack, a campaign or a mod holds or lacks, it says so with `push_warning` and the system's prefix (`[rules]`, `[mods]`, `[creatures]`,
  `[problems]`, `Packs:`), naming the pack, campaign, sector or creature and what the player sees instead, once for each cause and run, never per tick or frame. The warning goes through a `TroubleLog`, which keeps the lines it gave (`told`) so that a test can read them:
  `RuleHooks.trouble` (a declared mod that does not resolve, `ModHooks.unresolved_line`; a judged type that takes no number), `FoeVM.Context.trouble` (a creature that faults, `FoeVM._tell_fault`; a `Mod_Instruction` no mod defines), and `TroubleLog.session`
  (code with no owner of a run: what a mod's draw list has dropped or answered that is no list, `ModDraw.report`; the sounds a problem mod asked for that nothing plays; the file a mod loads that its pack lacks, `ModApi`; a type laid over by another pack,
  `ModHost.problem_screen`; a trigger slot with no problem, `ProblemFactory.for_trigger_slot`: no screen, the owner answers the world with `ProblemSession.not_made`, the sub goes on, a data canister stays taken; `GameFlow._no_lock`: the dock finishes the sector; a problem type whose diagram names no family or one the game does not draw, `DiagramFactory._new_for`: the plain list of its items), which every run (`GameState.begin_run`) starts over. `test_pack_trouble` pins the log and the lookups with no mod behind them; the other lines are pinned where the
  system is tested. What is warned about already (a refused mod, a mod that faults or is quarantined, a file of a pack that does not read) is not told twice.
- **`FoeVM`**: a creature faults and stands still after 512 instructions without a yield or on bad code, and says so in the log (`[creatures]`); the game does not crash. All
  creatures of a sector exist from load; only those on the shown screen run.
- **Decorations**: bit 7 of a placement is the mirror; animated decorations store the original's 1-based frame lists 0-based and start at
  `start_cursor % frames.size()`.
- **Pieces**: the canister flashes between pictures 3 and 4, every other piece is a sparkling rock, all in step on the tick count
  (`src/gameplay/collectible.gd`).
- **Ambient bubbles**: a pool of two and a seeded random generator (`src/gameplay/bubbles.gd`); Godot particles are not used, because the
  original's bubbles are a small deterministic routine.
- **Sound**: one effect player and one voice player that cut each other off, as the original's one wave device does
  (`src/autoload/audio.gd`). The "begin" sound and the restart of the music happen at a sector start or respawn, never at a screen
  change.
- **Tank losses** are held while a problem is open (the HUD still shows the drop): `GameState`, `ProblemScreen`.
- **`MessageQueue.close_current`**: a closed message's handler may post the next message; the queue allows for it.
- **Modals: `ModalHost`** (`src/ui/modal_host.gd`). Every screen that shows dialogs (sign-in, Math Practice, the game, the Voyager
  closing) opens the message box and each dialog through one `ModalHost`; the screen keeps no "dialog open" flag of its own
  (`modals.is_open()`). While anything is open the nodes the screen hands it sleep (`process_mode = DISABLED`: the problem screen's
  calculator, answer box and ballast panel hear no key; `focus_behavior_recursive = DISABLED`: the arrows and Tab cannot move the focus
  under the dialog). A dialog closes by leaving the tree; the top modal that closes gives the focus back to the control that had it, or to
  the screen's home control (the sign-in list). Godot's arrow-key search stays under one top-level control, so a dialog on its own
  `CanvasLayer` keeps the arrows anyway; a dialog that shares its screen's root (Math Practice) needs the freeze.
  `tests/engine/test_modal_host.gd`; `test_problem_keyboard.gd` answers every problem type from the keyboard under it.
- **Answers** are compared with `AnswerChecker.BOUNDARY_SLACK` (1e-9) at range boundaries.
- **Saves** are written to a `.tmp` file and renamed; the roster is sorted by name in byte order. Volumes and the music set are per
  machine (`user://audio_settings.cfg`); the Sound / Music / Voice switches are per player.
- **The opening** loops like the original's attract mode: when the last story page times out with no key it starts over from the news cartoon (`Opening._run`). Esc does not skip a math problem.
- **Hint 10171** has no text in the original; `HintSystem` has a fallback sentence.
- **Text** uses one project theme with Liberation Sans Bold through a `FontVariation` (`src/ui/theme_builder.gd`), not the original's
  bitmap font.
