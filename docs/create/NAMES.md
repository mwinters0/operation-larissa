# Names (the symbol table)

The original game knows things by number: sound 22, creature picture 40, flag 3, sector 17. The port gives them friendly
names, so a creature script can say `Play_Sound begin` and a skin or a campaign can refer to "the lock tick" without
caring about its number. The names are **ours**, not the original's:
nothing in the name file is original text or original bytes.

* **The file:** `godot/names/original.json`, the one registry (packs bring no names of their own).
  Hand-made and committed. The importer never writes it, and a reset or an import never touches it, like
  `godot/data/sectors/foe_annotations.json` (but it is not under the legacy pack, which is generated). It is shipped with the game
  (`export_presets.cfg` includes it), because `SfxCatalog` asks it at run time.
* **The reader:** `NameRegistry` (`godot/src/core/name_registry.gd`). `NameRegistry.original()` is the shared instance.
* **The checks:** `godot/tests/engine/test_name_registry.gd` (the file's rules: the convention, uniqueness, every number has a
  name that finds it again; the reader and its error messages), `godot/tests/legacy/test_name_registry_legacy.gd` (every name
  points at something the game has, the `same_audio` twins against the sound files) and `tools/import/test_names.py` (a name
  written twice in one object, which a JSON parser silently merges; the standard layout; the names against their sources).

## The format

```json
{
 "comment": "...", "format": 1, "content_set": "original",
 "names": {
  "sound": { "begin": 22, "station_door": 23 },
  "frame": { "common": { "ink_burst_0": 28 }, "1": { "eel_swim_0": 35 } },
  "flag":  { "common": { "finale": 15 }, "15": { "left_door_open": 0 } }
 }
}
```

Every kind has an entry under `names` (empty is `{}`). A **global** kind is one table `name: number`. A **scoped** kind is
a table per scope: `common` (valid in every scope) and one per zone or sector, keyed by its number. Inside a table the
names are listed in the order of their numbers. The layout is `json.dumps(indent=1)`, so a tool can rewrite the file
without a diff.

Besides `names` the file may hold `same_audio`: `{"sound": [[6, 20, 21], [8, 17], ...]}`, the numbers of a kind that hold
**one and the same recording**. The original stores some sounds twice under different numbers (the scripts play one or
the other, and the slots seem to be roles: 15 and 16 are both "an oxygen tank is taken", in different sectors). Each number
keeps its own name, because a script must assemble to the original bytes; the groups tell a skin or an editor that replacing
sound 20 does not replace 6 and 21. `tools/import/test_names.py` and `tests/legacy/test_name_registry_legacy.gd` check the groups against the
sound files (the twins are one file's worth of samples, and no other two are alike).

## Kinds and scopes

| Kind | The number is | Scope | Made-up name |
|---|---|---|---|
| `sound` | the common sound index 0-51 (`NE0SOUND` 8000 + n) | global | `sfx_22` |
| `frame` (creature picture) | a slot of the creature set (0-27 common, 28-34 ink, 35+ the zone's own) | **zone** 0-6 + common | `frame_040` |
| `deco` (decoration picture) | a slot of the deco set (0-69 common, 70+ the art zone's own) | **art zone** 0-4 + common | `deco_070` |
| `music` | the song id 9500-9509 | global | `music_9503` |
| `voice` | the speech clip id (`NE1SOUND` 4000-4370) | global | `voice_4243` |
| `ui_picture` | the `NEP256` picture id of an interface, story, console or title picture | global | `ui_1195` |
| `problem_art` | the `NEP256` picture id of a problem panel (1780-2138) | global | `pa_1780` |
| `text` | the string id of the original's string tables | global | `text_10648` |
| `zone` | the zone 0-6 (5 and 6 are the Voyager and Expert finale) | global | `zone_3` |
| `sector` | the sector number, 0-255 (0-31 are the original's, 32 and up the designers': 255 is `Catalog.MAX_SECTOR`) | global | `sector_07` |
| `foe` (creature) | the creature's number in its sector's list. A sector holds up to 255 creatures (`SectorData.MAX_FOES`), but a creature script names one with 7 bits (bit 7 is the mirror marker, below), so names go with the numbers 0-127 | **sector** + common | `foe_12` |
| `screen` | the screen 0-11 of a sector | **sector** + common | `screen_05` |
| `flag` | the creature scripts' global flag bit 0-15 | **sector** + common | `flag_03` |

Why these scopes. A creature picture (`frame`) and a deco are *slots*: slot 40 is a different drawing in every zone
(`tools/analysis/data/sprite_slots.json`), so a name that means slot 40 belongs to a zone; the common slots (0-34 and 0-69) are named
once, in `common`. The finale sectors use the art zones 5 and 6 for creatures and zone 4's decorations
(`ZoneData.tile_zone`), so a `deco` scope is the *art zone* and a `frame` scope is `SectorData.zone`. Creatures and screens
are numbered per sector (there are 256 sector scopes, `NameRegistry.SECTOR_SCOPES`: one for every number a sector can have; the registry names
the creatures, screens and flags of the original's 0-31 and none of a designer's own), and so are the **flags**: the 16 flags are one bit field shared by all the creatures *of the sector*
(`FoeVM.Context.semaphore`; a new one for every sector load), and the same number means different things in different sectors
(sector 15 gives bits 0-3 to four creatures, sector 16 uses bit 0 as a signal). Only **bit 15 means the same everywhere**:
the game itself reads it as the end of the game (`SimWorld.FINALE_SEMAPHORE_BIT`, sectors 30 and 31), so it is the common
name `finale`. Everything else (sounds, songs, speech, texts, pictures that are not slots) has one meaning for the whole
content set. A `zone` name lets scripts and tools say which scope they mean.

A lookup in a scope sees that scope's own names **and** the common ones, so within one kind a name is unique across
`common` + the scope, and one number has one name there (`index_of` and `name_of` must be inverses). The same name may mean
different numbers in two zones.

## The naming convention

* `[a-z][a-z0-9_]*`, at most 40 characters: lowercase ASCII letters, digits and underscores, starting with a letter. Unique
  within kind + scope. Words and positions are separated by `_` (`ink_burst_3`, `dragon_reef_voyager_1`).
* **Never ambiguous in an assembler operand** ([`FOE_SCRIPTING.md`](FOE_SCRIPTING.md), "Names in operands"). The assembler reads an operand as a number (digits, may start
  with a sign), as `self` / `self+N` / `self-N` (creature references), or as a label (`FoeAsm.is_identifier`, a jump
  target; a label *definition* ends with `:`). A name starts with a letter and has no `+`, `-` or `:`, so it is none of
  the first and last; and names are only read in a position where the operand kind says which kind they are (a `sound`
  operand looks a name up in `sound`), so a label and a name can have the same spelling without being mixed up.
  Refused: `self`, `mirror` and `mirrored` (kept for the creature reference and for writing a mirrored picture), and the name of
  any instruction (`jump_to`, `padding`).
* **Made-up names.** Every number has a name: if nobody has named it, its name is the kind's pattern with the number
  (`sfx_22`, `frame_040`; decimal, like the numbers in the file, the scripts and the asset file names, zero-padded to the
  width in the table). `NameRegistry.fallback_name` makes it and `fallback_index` reads it, and `index_of` accepts it
  **always**, also for a number that has a real name, so a script that uses it keeps working when the number gets a name.
  Only the exact spelling is accepted (`sfx_3` and `sfx_003` are not
  `sfx_03`), so there is one made-up name per number. For that reason a hand-made name may not look like a made-up
  name of the same kind.

## Names in creature scripts

Which operands take names, in which scope, how a mirrored picture is written and what the disassembler writes are in
[`FOE_SCRIPTING.md`](FOE_SCRIPTING.md), "Names in operands". On the registry side, `FoeNames` (`godot/src/core/foe_names.gd`; the
importer's twin is `tools/import/foe_names.py`) is the registry together with a sector and its zone, and is what `FoeAsm.assemble` /
`disassemble` take. The stored `.foe` files spell the names, so after names are added to `original.json` run
`uv run tools/import/reset_foe_scripts.py --all` (it also puts the instructions of every original sector back; the stored label
names and comments are kept).

## The API in a few lines

```gdscript
var names := NameRegistry.original()
names.index_of(&"sound", "begin")            # 22, or -1; "sfx_22" works too
names.name_of(&"sound", 28)                  # "sfx_28" (the real name when there is one); "" only outside the kind
names.index_of(&"frame", "ink_burst_3", 0)   # the third argument is the zone (frame, deco) or sector (foe, screen, flag)
names.names(&"flag", 15)                     # the real names usable there, in number order: for completion
names.same_audio(&"sound", 20)               # [6, 21]: the other numbers that hold the same recording
names.entries(&"sound")                      # the same as name -> number
names.explain_unknown(&"sound", "bgin")      # "unknown sound 'bgin' (did you mean 'begin'?)"
NameRegistry.name_problem("Begin")           # why a name cannot be used, "" if it can: for an editor that asks for a name
names.problems                               # what is wrong with the file (empty when it is sound)
```

## What is named, and from what

* `sound`: the 24 effects the decompilation identified. The registry is the only place for names: `extracted/tables/audio_map.json`
  (written by `tools/analysis/ghidra/export_audio.py`) keeps the numbers with *when* and *where* each is played, and `SfxCatalog`
  derives `named`, `id_of` and `name_of` from the registry. The 22 creature-only sounds (0-21) are named by their role:
  which creature plays it, doing what (`clam_chomp`, `eel_lash`, `oxygen_refill`). Nobody listened to them: the roles
  come from the scripts, the pictures and the waveform (length, loudness, brightness), so they are provisional. Where the
  recording is the same under several numbers, the later numbers carry `_alt` / `_third` (`ray_sting`, `ray_sting_alt`,
  `ray_sting_third`) and `same_audio` lists them.
* `voice`: one name per speech clip the game plays, from the runs of `VoiceCues.groups`: `<group>_<position>`
  (`supply_3_1`, `log_12_0`), or just the group name for a run of one clip (`jingle`). A clip two runs share keeps the first
  run's name. The groups themselves (which runs play when) stay in `VoiceCues`; they are sequences, not names.
* `frame`: every picture the game uses is named `<creature>_<pose>[_<n>]` (`puffer_swim_0`, `crab_hold_ball`), so a
  creature's pictures sort together and a frame range reads as its first and last name. The names are the *unmirrored*
  picture: the scripts' +128 (mirrored) is written with the `mirror` marker, not in the name. Names are provisional,
  chosen from how the creature scripts use each slot and from the picture itself. Common slots 0-34, zone slots 35+ per
  zone. The slot ranges of the SpriteFrames animations in `tools/import/animation_map.py` are not derived from the registry.
* `deco`: the 70 common slots and the art zones' own slots, named by what they show (`kelp_pods_0`, `rock_spire_dark`);
  pairs and runs that look like frames of one animation end in `_0`, `_1`. Zone 0's slot 96 is an empty picture and stays
  unnamed (its made-up name is `deco_096`).
* `ui_picture`: the loose picture sets of `animation_map.FX_SETS` (`tools/import/animation_map.py`): `spray_0..4`, `crew_walk_0..10`, `ship_idle`.
* `music`: `finale`, `closing`, `opening`, `title` (the `SONG_*` constants of `Audio`) and `sector_song_1..6`.
* `zone`: the titles of `zones.tres` in lowercase (`dragon_reef`, `hammerhead`, `voyager_finale`). `ZoneData.title` stays the
  display text.
* `sector`: `<zone>_<game>_<n>` (`dragon_reef_voyager_1` is sector 0, `hammerhead_expert_3` is 29), `voyager_finale` and
  `expert_finale` for 30 and 31.
* `screen` (common): `start_station` (0) and `end_station` (11), the two screens that draw the supply station.
* `flag` (common): `finale` (15). The flags of a sector that carry a clear meaning: the "which way am I flying" bit of a
  projectile that flies two legs (`ray_stinger_first_leg`: the bit is set during the first leg and the hit script asks it) and the
  "I am sweeping" bit that one creature raises for another to wait on (`puffer_s2_sweeping`, sectors 16, 19, 24). The other
  bits are named from the creature that owns them (`<creature name>_first_leg`).
* `foe`: every creature of the 32 sectors, named from its picture, its script and where it starts:
  `<species>` when the sector has one, else `<species>_s<screen>`, and `_left` / `_right` / `_upper` / `_lower` / `_middle`
  (or `_1`, `_2` ... / `_a`, `_b`) when several share a screen. The species are the pictures' subjects (`clam`, `anemone`,
  `puffer`, `barracuda`, `ray`, `sting_ray`, `ray_stinger`, `coral`, `dolphin`, `oxygen_tank`, `rainbow_fish`,
  `jellyfish_top` / `jellyfish_bottom`, `eel`, `angler`, `isopod`, `octopus`, `worm`, `crab`, `hammerhead`, `squid`,
  `flame`, `great_white` ...) and their helper creatures (`ray_stinger`, `*_ball`, `squid_dart`, `flame_trigger`, `flare`).
  A hidden creature that nobody wakes ends in `_dormant`. The position words come from the START position; creatures move.
* `ui_picture`, `problem_art`, `text`: every picture and string the code refers to, so that no number is left in `src/`.
  The pictures are named by what they show or where they stand (`radar_map`, `title_sky`, `crane_hook_0`, `story_caption_3`, `scanner_strip_2`,
  `log_scan_5`), the sets by a number suffix like the sprite sets (`crash_ring_0..3`, `status_light_0..2`). The strings are named by their role
  (`click_to_go_on`, `file_menu_title`, `exit_text`) and the runs the code walks through by an index (`hint_0..6`, `help_playing_0..1`). One `text` kind covers all the string tables (the ids are one number
  space), so `Catalog.text(name)` needs no table. All of them are provisional and role-based; the ones nobody has looked at closely are the
  story pictures (`story_cloud_swirl`, `story_americas`), the title pictures (`title_cloud_0/1`) and the units (`period_*`, `time_*`).

## Names in data and code

The numbers of the original are an implementation detail of the registry; the rest of the project says names.

* **The Inspector.** `FoeData.frame`, `frame_min` and `frame_max` are the original's numbers in the file and in `encode()`, but `FoeData._validate_property` shows them as a drop-down of the names of the sector's zone:
  `eel_swim_0` with 35 behind it. The zone comes from the sector file that holds the record (the record's `resource_path`
  is `...sector_03.tres::Foe_5`). A value the list does not offer (an unnamed slot, or a mirrored one: bit 7, `+ 128`) is added to
  the list as the current choice, so looking at a record never changes it (`FoeData.picture_choices`).
* **Events carry names.** `sfx_requested` (`SectorWorld`, which passes on the `sound_requested` event of `SimWorld`; `ProblemScreen`, `ProblemFlow`,
  `ProblemRunner`, `DiagramBase` and the sonar and ballast diagrams, `Calculator`, `AnswerBox`, `CombinationLock`) and `Audio.sfx_played` / `voice_played` / `voice_started` / `music_changed` carry a `StringName` (`&"lock_tick"`);
  `Audio.play_sfx`, `play_voice`, `play_voice_sequence` and `play_music` take one. The receiver looks the name up (`SfxCatalog.stream_named`,
  `VoiceIndex.stream_named`, `MusicCatalog.stream_named`). The rules side stays numeric where it runs the original's bytes: `FoeVM`
  collects `Play_Sound` numbers in `Context.sounds` and the world gives each its name (`SfxCatalog.name_of`) when it sends the event;
  the diagrams' plans hold the sound numbers the importer read and `DiagramBase` does the same when a step plays.
  `VoiceCues` hands out `voice` names.
* **One resolver per kind.** `sound`: `SfxCatalog.stream_named`; `music`: `MusicCatalog.stream_named`; `voice`: `VoiceIndex.stream_named`;
  `text`: `Catalog.text(name)`; `ui_picture` and `problem_art`: `Assets.ui_picture(name)` and `Assets.problem_art(name)` (`src/core/assets.gd`),
  which turn the name into the number (registry) and the number into a path (`Assets.ui_picture_path`, `Assets.problem_art_path`: the
  only places that know the folders); creature pictures: `NameRegistry.index_of(&"frame", name, zone)`. The asset files carry the name and the number
  (`lock_tick_38.wav`, "Asset file names" below), and `Assets.file_stem` is where the game knows that. A number that a data file holds
  (the closing crew's pictures) goes through `Assets.ui_picture_by_number`; code never writes one.
* **Cutscene timelines hold names, not numbers.** The tracks of a cutscene (`data/story/*.tres`) say
  `ship_radar_1`, `opening_scene`, `news_bulletin_0`, `alien_artifact_0`: the importer finds each name from the original's number (`step_story.py`,
  `picture()`, `sound()`, `text_name()`, `frame_name()`) and the view turns it into a texture, a sound or a text with the usual resolver
  (`CutsceneCast`), so a skin can map the same names to its own art. The files are regenerated by `rename_name.py ... --import` (the `story` step),
  and `tests/engine/test_story_timelines.gd` checks that every name in them exists.
* **Campaigns hold names too.** The original's two (`voyager.tres`, `expert.tres` in the legacy pack's `data/campaigns/`) list the `text` names of their log entries
  (`log_entry_0..29`), supply messages (`supply_message_0..29`) and game names; the `campaigns` step writes them from the registry, so a rename with `--import`
  keeps them current, and `tests/legacy/test_campaign_legacy.gd` checks that every name exists. A campaign of a designer's own is not written by the importer: a rename does not reach it.
* **The guard.** `tests/engine/test_no_asset_numbers.gd` reads every script of `src/` and fails on a number from 1000 to 12999, a two-digit
  hexadecimal number on a line about sounds, a string that names a numbered file (`ui_1039`), or a path into the legacy pack's `assets/ui`,
  `assets/problem_art` and `assets/audio`, anywhere but in the registry and `assets.gd`. The few other numbers of that size (`9999` tries,
  `1200` ticks) are listed in the test with their reason. `tests/engine/test_assets.gd` checks that every named picture loads and that every name
  of the `text` kind gives its string; `tests/legacy/test_assets_legacy.gd` that the folder rule finds every picture file the importer wrote.
* **What has a number, and why.** The generated `data/*.tres` files hold about 1,600 asset paths (sprite sets, problem types, the sound
  catalogs), which end in the number of what they point at (and, for a named thing, in its name): a Godot resource names its files by path, and the
  importer writes them. (The sign-in scene asks for its pictures by name in `_ready`, so no hand-made scene holds a path to a numbered picture.) The backgrounds (`bg_sNN_MM.png`) are per sector and screen, not a registry kind. The picture indices of
  the sub, the ink pellet, the bubbles, the pieces and the station are slots of those SpriteFrames sets (`Sub.LIGHT_PICTURE`), not asset ids.

## Asset file names

The file of a **named** entry is `<name>_<number>.<ext>`, so the original's number is next to the name when someone reads an original script,
a manifest or a folder (`lock_tick_38.wav` is sound 38). An entry **nobody has named** has a file name that holds
its number (the table). The number is decimal, as in the registry, and not padded. `tools/import/asset_names.py` is the rule; `Assets.file_stem` is its GDScript twin
for the picture kinds the game resolves by path (the other kinds are reached through the generated catalogs and SpriteFrames, which hold the paths).
The folders are those of the legacy pack's `assets/`.

| Kind | Named | Unnamed |
|---|---|---|
| `sound` | `audio/sfx/lock_tick_38.wav` | `audio/sfx/sfx_28.wav` (the made-up name, padded to two digits) |
| `voice` | `audio/voice/jingle_4243.wav` | `audio/voice/voice_4244.wav` |
| `music` | `audio/music/title_9503.ogg` and `audio/music/adlib/title_9503.ogg` | the MIDI file's stem, `esect1.ogg` / `adlib/bsect1.ogg` |
| `ui_picture` | `ui/<folder>/title_sky_1039.png` (the folder is the role: `story`, `title`, `hud`, `map`, `prompt`) | `ui/story/ui_2001.png` |
| `problem_art` | `problem_art/<bundle or single>/log_scan_0_2046.png` | `problem_art/b077/pa_1804.png` |
| `frame`, slots 0-34 (all zones) | `sprites/foes/ink_burst_0_28.png` | `sprites/foes/foe_028.png` (none: every creature picture is named) |
| `frame`, slots 35+ (the zone's own) | `sprites/foes/foe_z3_crab_walk_0_38.png` | `sprites/foes/foe_z3_040.png` (none) |
| `deco`, slots 0-69 (all art zones) | `sprites/decos/kelp_pods_0_0.png` | `sprites/decos/deco_005.png` (none) |
| `deco`, slots 70+ (the art zone's own) | `sprites/decos/deco_z2_fern_green_70.png` | `sprites/decos/deco_z0_096.png` (the empty picture) |

The **zone** of a creature or deco picture is a `foe_z<zone>_` / `deco_z<art zone>_` prefix, because a zone-scoped name means a different drawing in
every zone and all zones share one folder; the shared slots are named once (`common`) and carry no zone. The zone prefix is the one spelling for
both kinds (a folder per zone would have worked as well). Kinds without names (backgrounds, tiles, the sub, pieces, station and fx sets, the
authoring-tool art) keep their file names.

**Stale files.** A step writes the files of the current names; `import_all.py` then removes every file of the folders it ran that no step wrote
(`asset_manifest.prune`), so a rename never leaves the old file behind, and the folders hold exactly the files of the asset manifest. Godot's
`.import` sidecar of a file that moved is carried to the new name (same bytes), so the file keeps its `uid://`. A song that has only been renamed is
moved, not rendered again (`step_audio.adopt_song`: FluidSynth does not render the same samples twice).

What the importer does not touch: hand-written text that spells a file name (tests, docs), and the names in code (`Assets.ui_picture(&"old_name")`). Renaming a
name moves all of that together: "Renaming a name" below.

## Adding a name

Edit `godot/names/original.json` (keep each table in number order, and write it with `json.dumps(data, indent=1, ensure_ascii=False) + "\n"`), then run `tools/run_tests.sh tests/engine/test_name_registry.gd` and
`uv run pytest tools/import/test_names.py`. The reader reports every problem it finds in `problems`, with the kind, scope and
name. A new name in a creature-script operand reaches the stored `.foe` files with `reset_foe_scripts.py --all` ("Names in creature scripts" above).

## Renaming a name

A name is used in the registry, in the stored creature scripts, in the code and in the file names of the assets, and a rename that misses one of
them leaves a name that resolves to nothing. `tools/import/rename_name.py` does the whole rename, and a static check fails when a name in the code
resolves to nothing:

```
uv run tools/import/rename_name.py sound ray_sting sting_ray_hit --dry-run     # list every change, write nothing
uv run tools/import/rename_name.py sound ray_sting sting_ray_hit --import      # rename, then run the importer for the asset files
uv run tools/import/rename_name.py frame crab_hold_ball crab_hold --scope 3    # a zone's (frame, deco) or sector's (foe, screen, flag) name: its scope, or `common`
uv run tools/import/rename_name.py text news_bulletin_ headline_ --run             # a run of names that the code builds: the prefix
```

The tool is a Python command line, not an editor action: the importer has to run for the asset files anyway, and one implementation of the
rules is easier to keep right than two (the Foe Script editor renames labels itself). The
scope can be left out when the name is in one table only. Then `tools/godot.sh --headless --path godot --import` and `git checkout godot/export_presets.cfg`
(`--import` of the tool runs the importer, not Godot), `tools/run_tests.sh headless`, `uv run pytest tools`.

**What it changes.**

* `names/original.json`, written in the standard layout (`json.dumps(data, indent=1, ensure_ascii=False) + "\n"`); the number and the place in the
  table stay.
* The stored creature scripts, **in place**: the operands of the renamed kind (`Play_Sound` for a sound, the pictures of `Set_Frame` ... for a
  frame, the creature of `Wake_Foe`, the flag of `Set_Flag` ..., the screen of `Move_Foe_To_Screen_XY`) in the sectors where the name resolves to that
  entry: every sector for a sound or a common name, the sectors of the zone for a `frame` name of a zone, the one sector for a `foe`, `screen` or `flag`
  name of a sector. A label, a comment, an operand of another kind and a sector of another scope are never touched, even with the same spelling
  (`crab_hold_ball:` and `Jump_To crab_hold_ball` next to `Set_Frame crab_hold_ball` stay). **A use written as a number or as the made-up name
  (`sfx_22`) is left as it is**: it does not hold the name. Each changed line is read again with the old and the new registry and must give the same
  operand values, so the script still assembles to the same bytes (`tests/legacy/test_foe_asm_legacy.gd` checks the hash). The importer's `sectors` step is
  not run: it would overwrite what designers edited, which is why the text is edited and not regenerated.
* GDScript in `src/`, the project's own addons and `tests/`, by `tools/import/code_names.py` (below): the literals that are bound to the kind, and
  `&"old"` or `` `old` `` in a comment when no other kind has that name.
* The file stem `old_<number>` (`foe_z3_old_38` for a zone's own picture) in tests and docs, `Play_Sound old` in docs and the editor's help, and the name
  alone in backticks in `docs/**/*.md`, `README.md`, `AGENTS.md` and `godot/README.md` when no other kind has that name. `docs/ROADMAP.md` is not edited.
* With `--run`: every member `prefix<digits>`, the `"prefix%d"` patterns in the code, and the entry of `tools/import/name_runs.json`.
* With `--import`: the importer without the `sectors` step (`images,tiles,sprites,problems,console,story,campaigns,audio`) for the kinds that have files. It writes the
  new files, removes the old ones and carries Godot's `.import` file along (the `uid://` stays), rewrites the generated catalogs and
  `asset_manifest.json`, and moves a renamed song without rendering it again.

**What it only reports** ("NOT CHANGED", with file and line): a literal of the name that no resolver is seen to take (`animations.play(&"wrong")` next to the
sound `wrong`, a string in a test that compares with the name, a dictionary key), a name of a scoped kind that another scope has too, the name between
quotes in prose and in the Python files of `tools/import/` (`animation_map.py` and the seeds that `test_names.py` compares with the registry), and a name in
backticks that is also the name of something else (`finale` is a flag and a song). The first real use shows what to fix by hand; the tests that spell a
name (`test_assets.gd`, `test_audio_assets.gd`, `test_sfx_events.gd` for a sound) fail until it is done.

**What it refuses**, and changes nothing: an unknown kind or name (with a "did you mean"); a made-up name (`sfx_22` is derived from the number, there is nothing
to rename: name the number); a new name that `NameRegistry.name_problem` rejects (its Python twin is `rename_name.name_problem`, compared with
`name_registry.gd` by `test_rename_name.py`: case, characters, 40 characters, `self` / `mirror` / `mirrored`, an instruction name) or that looks like a made-up
name of the kind; a collision (a scope's name must be free in the scope and in `common`, a common name in every scope; the same name; ambiguity
of the old name between scopes); and **one member of a run** that the code builds at run time (`news_bulletin_3`: the code asks for `"news_bulletin_%d"`), unless the
whole run is renamed with `--run`.

**The check.** `tools/import/test_code_names.py` (pytest, `uv run pytest tools`) reads `src/` and the addons and fails when a name that is handed to a registry
resolver is not in the registry, or when a run is incomplete. `code_names.py` has a small GDScript lexer and finds, in order of directness:

1. *direct*: a literal in the name argument of `Catalog.text`, `Assets.ui_picture`, `Assets.problem_art`, `play_sfx`, `play_voice`, `play_voice_sequence`,
   `play_music`, `stream_named`, `<signal>.emit` of `sfx_requested` / `sfx_played` / `voice_played` / `voice_started` / `music_changed`,
   `index_of(&"kind", "name")` / `explain_unknown` / `number_of`; wrappers (`StringName(...)`, a ternary, an array) are
   looked through, other calls are not (so `&"voice"` in `name_of(&"voice", n)` is a kind, not a name);
2. *bound*: a `&"..."` in a constant or variable (or an argument of a function of the project) whose value flows into such an argument by an assignment, a
   `for ... in`, `.append`, `return` or a parameter (`const SFX_TICK := &"..."` ... `sfx_requested.emit(SFX_TICK)`; `HOPPING_PICTURES` ... `index_of(&"frame", picture_name, zone)`);
3. *a run*: `StringName("news_bulletin_%d" % n)`. `tools/import/name_runs.json` declares each run (kind, prefix, first and last number, the numbers that
   do not exist); the check compares it with the registry and with the patterns it finds in the code, so a renamed member, a member that was removed and a new
   pattern nobody declared all fail.

*Blind spots.* A name that reaches a resolver through a signal connected to a callable, a member variable of another object, a container filled in another file,
`call()` by name or a data file; a name built any other way than `"..._%d" % n`; the code in `tests/` (they spell wrong names on purpose; `tests/engine/test_assets.gd`
loads every named picture and text at run time); for a scoped kind the name must exist in *some* scope, which one the running code asks is not known statically. A literal
that is a registry name but that no resolver is seen to take is listed in `UNCHECKED_BUT_NAMES` of the test, with why: the animation `&"closing"` (also a
song) and the `&"finale"` step of `SimWorld.TICK_ORDER` (also a song and a flag).
