# The dev pack generator

`godot/packs/dev/` is the developers' own pack: coloured shapes with their asset name written on them, text that says its own
name, sounds that say "bang", and a short playable game (`dev_tour`). It has one file for every file of the legacy pack (the original
game, made by the importer) and nothing of the original's content: its numbers and pictures are its own. A copy of it is a complete game
(`pack_tool --new=<id> --from=dev`, [`docs/create/MAKING_CONTENT.md`](../../docs/create/MAKING_CONTENT.md) B4). The engine's tests (`godot/tests/engine/`) run on it, with `-- --pack=dev`.
What the engine still assumes about the original, and so what dev cannot yet be free of, is in [`docs/engine/HARD_CODED.md`](../../docs/engine/HARD_CODED.md).

```sh
uv run --group dev-pack tools/dev_pack/make_dev_pack.py      # everything: pictures, data, audio (audio.py; the group has Piper)
uv run tools/dev_pack/make_dev_pack.py --only pictures,data  # without the audio (no Piper needed)
tools/godot.sh --headless --path godot --import              # Godot imports the new pictures; commit the .import files it completes
uv run pytest tools/dev_pack -q                              # the tests
tools/godot.sh --headless --path godot -s ../tools/dev_pack/godot/check_dev_pack.gd   # the engine's own check of the result (below)
```

**Regenerating and re-importing.** Change a module (or the inventory), run the generator for the stage it touches (`pictures` and `data` need only Pillow and numpy; `audio` needs the `dev-pack` group, which has Piper and
downloads its voice the first time), then the Godot import (it writes the `.import` files and `.godot/imported` copies of new pictures and sounds), then the check and the tests, and commit the files the generator and the import
changed. `--refresh-inventory` rebuilds `inventory.json` from the file names of the legacy pack and is the one step that needs legacy; without legacy the committed list is the inventory, and `test_dev_pack.py` compares the pack with it.

The output is committed and the generator is deterministic (Piper aside): run it again and `git status` stays clean. A file you edit by
hand is yours until the next run, so change the generator too. `test_dev_pack.py` fails when the generator would rewrite a file.

## What is where

| Module | Makes |
|---|---|
| `inventory.json`, `inventory.py` | The list of files the pack must have (from the legacy pack's file NAMES; `make_dev_pack.py --refresh-inventory` rebuilds it, needs legacy). |
| `dev_pictures.py` | Every PNG (flat shape, 1 px outline, its name written on it) and its `.import` stub (path-derived uid). Sizes are in `spec()`. |
| `dev_tiles.py`, `dev_tables.py` | The tile set; zones and the trigger table. |
| `dev_sprites.py` | Sprite frames, sprite metadata (box hit rectangles that match the pictures), bubble rules. |
| `dev_ui.py` | HUD, calculator and story layouts, the news cartoon. |
| `dev_problems.py` | The 34 problem types (a few made-up records per level), the problem screen layout, the text tables. |
| `dev_sectors.py` | Sectors, campaigns, and the `dev_tour` campaign. |
| `dev_rules.py` | `rules/tuning.json`: dev's rule values (below). |
| `test_sectors/` | The test sectors (100 and up), one module per area: `batch_a.py` ... `batch_e.py` (see "Test sectors"). |
| `problem_art.json` | Which art folder each of the 34 problem types draws from (the pack's file layout). The generator reads no `docs/data/` file that the importer writes. |
| `audio.py`, `audio_*.py` | The sounds, speech, songs, MIDI and the sound catalogs. |
| `godot/check_dev_pack.gd` | A Godot script that loads the pack with the engine's own classes and asks each resource if it is sound (see below). |

## Rule values

`rules/tuning.json` is a layer over the project's `data/rules/tuning.json` (the original's numbers), and it gives EVERY scalar rule value a number of
its own: a slower sub with a narrower wall box, less air and ink, three pellets in flight, another respawn screen, shorter countdowns and lock waits,
a lower creature limit. The engine's tests run on dev, so a rule that still reads the original's number instead of the run's fails; `test_dev_rule_values.gd`
checks that the layer is complete (a new key in the project's file needs a line in `dev_rules.py`), passes `Tuning.check` with no error and no warning (hence less air,
tanks and ink, not more: the console has places for the original's), differs from the original's on every key, and that each value reaches the code that uses it.
What the layer leaves out are the per-cell and per-picture tables of the sub, which belong to the pictures dev draws at the original's sizes (a layer states only what it changes).
The respawn screen is one on which every dev sector has free water at its start and a trigger on the screen before.

## Adding a sector

A sector is a `SectorSpec` in `dev_sectors.py`. `standard_sector(index, zone, creatures=1)` makes a small playable one: twelve screens chained
left to right with a floor, the data canister (piece 0) on screen 3 and one more piece on screen 8, decorations, ledges, a current, two math
triggers and pacing creatures. Make one, change what your test needs, write it:

```python
spec = dev_sectors.standard_sector(100, zone=2, creatures=0)
spec.screens[4].fill(10, 6, 20, 6, dev_sectors.wall())          # a wall: columns 10..20 of row 6 (tiles are 16 x 16)
spec.screens[4].triggers.append(dev_sectors.Trigger(300, 200, slot=10))
spec.pieces.append((9, 400, 120))                               # (screen, x, y) in window pixels; piece 0 stays the canister
test_sectors.write_sector("a", spec, dev_root)                  # data/sectors/sector_100/ of the dev pack (batch A's module)
```

A test sector belongs to no campaign and is written by its batch's module (next section). Run the generator, then check the sector:

```sh
tools/godot.sh --headless --path godot res://src/checks/check_sector.tscn -- --pack=dev --file=res://packs/dev/data/sectors/sector_100/sector_100.tres
tools/godot.sh --headless --path godot res://src/checks/check_sector.tscn -- --pack=dev --sector=100     # the same, by number
```

Positions are window pixels (the playfield is the 608 x 288 rectangle at (16, 32)); tile bytes are `wall(picture)`, `current(direction, strength)`
and 0 for empty. A creature (`Foe`) names three labels of the sector's script (`SectorSpec.script`; `patrol_script()` is the pacing creature
of [`docs/create/FOE_SCRIPTING.md`](../../docs/create/FOE_SCRIPTING.md)). A campaign is `campaign_tres(...)`; test sectors are in no campaign.

## Test sectors

Engine tests that need a place with a stated property get a sector of the dev pack made for them, numbered 100 and up and in no campaign (sectors 0-4 are the playable `dev_tour`). The numbers are split into
ranges by area, one generator module each, so that adding sectors for one area never edits another's files:

| Area (batch) | Sector numbers | Module | Own campaign (only if a test needs one) |
|---|---|---|---|
| A: ground (tiles, walls, currents, screens, sector data and its editors and checks) | 100-119 | `test_sectors/batch_a.py` | `test_a` |
| B: creatures, combat, the playfield as the skins see it | 120-139 | `test_sectors/batch_b.py` | `test_b` |
| C: problems, triggers, the calculator, the lock, the log, hints | 140-159 | `test_sectors/batch_c.py` | `test_c` (the only test campaign the pack holds) |
| D: flow, campaigns, saves, story, sign-in, HUD | 160-179 | `test_sectors/batch_d.py` | `test_d` |
| E: audio, names, assets, catalogs, the pack chain | 180-199 | `test_sectors/batch_e.py` | `test_e` |

A new area takes the next free range (200-219 ...), a module of its own and a `DevPack.BATCH_*` constant in `godot/tests/engine/dev_pack.gd`.

- Each module has `write_all(dev_root)`; `make_dev_pack.py` (stage `data`) calls the five in turn after `dev_tour`. A module is edited only for its own area.
- Write a sector with `test_sectors.write_sector("<batch>", spec, dev_root)` and a campaign with `test_sectors.write_campaign("<batch>", title, sectors, finales,
  edu, finale_text, dev_root)`: both refuse a number or an id that is not the batch's. `standard_sector`, `finale_sector`, `patrol_script` and the rest of
  `dev_sectors.py` are shared and must not change for one batch; if a sector needs something they cannot do, build it in the area's module (copy the spec and
  change it). A change to the shared Python code must keep the generator idempotent.
- A test campaign shows in `Catalog.campaigns()` of every engine suite (the sign-in screen lists it), so add one only when a test cannot do without.
- `test_batches.py` checks that the ranges do not overlap and match `godot/tests/engine/dev_pack.gd`'s `BATCH_A` ... `BATCH_E`, and that the pack holds no
  test sector or `test_*` campaign that no module writes.
- The Godot side: `godot/tests/engine/dev_pack.gd` (`DevPack`) has the dev root, `DevPack.sector(n)`, the tour's numbers and the same ranges
  (`DevPack.test_sector("c", 2)` is 142). Check a new sector with `check_sector.tscn` (above) before using it in a test.
- After a change to a module: run the generator (`--only pictures,data`), `tools/godot.sh --headless --path godot --import`, the check below (0 problems),
  `check_sector.tscn -- --pack=dev --sector=N` for each test sector you changed (the check below does not look at test sectors), `uv run pytest tools/dev_pack -q`,
  and commit the sector's files.
  Name the sector's number as a constant in a test helper (`Ground.MAIN`), not as a literal in forty tests.

## Checking the pack with the engine

```sh
tools/godot.sh --headless --path godot -s ../tools/dev_pack/godot/check_dev_pack.gd
```

loads every `.tres` of the pack, compares the sizes of its pictures with its sprite tables and layouts, builds every problem of every
level, and runs the engine's own checks on sectors 0-4 and `dev_tour`. It does not look at the test sectors: check one with
`check_sector.tscn -- --pack=dev --sector=N` (above). It prints `dev pack check: 0 problems` when all is well.
(It registers the `.foe` loader by hand: a `-s` script does not get the project's custom loaders.)

## Rules the generator keeps

- Nothing of the original: no pixel, size, coordinate, hit rectangle, string, number or record. File names, the registry's names and the
  program's own structure (the layout of a record, which field holds the answer) are used; every value is dev's.
- A size the engine itself assumes (the sub 96 x 58, a piece 24 x 20, the playfield 608 x 288, the prompt's sender icon 55 x 20) is kept.
- Picture sizes are even (the sprite tables keep sizes divided by two).
