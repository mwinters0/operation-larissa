# How content works

A manual for teachers, students and hobbyists who want to understand, and then change, what is in the game: its levels,
creatures, problems, words, pictures, sounds and campaigns. It explains the model (what can change and what never does) and
says where everything lives. It does not teach the editors; the other manuals do that.

You should be comfortable with files and folders and know the basics of Godot (a project, a scene, the Inspector, `res://`).
You do not need to know how this codebase works inside.

| If you want to ... | Read |
| --- | --- |
| build the original game from your own copy of it | [`LEGACY.md`](../play/LEGACY.md) |
| start a game of your own from the dev pack, make a sector, a creature or a campaign, then export, check and install it, or make a skin | [`MAKING_CONTENT.md`](MAKING_CONTENT.md) |
| understand the pieces: layers, packs, skins, where files are | this page |

The tool manuals go deeper on one thing each: [`SCREEN_EDITOR.md`](SCREEN_EDITOR.md) (one screen),
[`SECTOR_INSPECTOR.md`](SECTOR_INSPECTOR.md) (the whole sector), [`FOE_SCRIPTING.md`](FOE_SCRIPTING.md) (creature scripts),
[`NAMES.md`](NAMES.md) (names), [`SKIN_API.md`](SKIN_API.md) (skins). The reasons behind the design are in
[`OVERVIEW.md`](../OVERVIEW.md); how the engine does each of these is in [`docs/engine/`](../engine/).

---

## 1. The three layers

Everything in the project belongs to one of three layers. Knowing which one a thing is in tells you whether you may change it.

```
  +-------------------------------------------------------------------+
  |  PRESENTATION   how it looks and sounds                           |
  |                 skins: pictures, fonts, shaders, the HUD's words  |
  |                 changes freely - never changes the game           |
  +-------------------------------------------------------------------+
  |  CONTENT        what is in it                                     |
  |                 sectors, creatures and their scripts, problems,   |
  |                 texts, sounds, campaigns, lengths of waits        |
  |                 yours to change - judged by the checks            |
  +-------------------------------------------------------------------+
  |  RULES          how it plays                                      |
  |                 12.17 ticks a second, 640 x 400 whole pixels,     |
  |                 walls by tile scan, hit rectangles, air and ink,  |
  |                 the creature interpreter, how problems are judged |
  |                 does not change                                   |
  +-------------------------------------------------------------------+
```

| Layer | Examples | Who changes it |
| --- | --- | --- |
| **Rules** | the 12.17 Hz `GameClock` tick, integer window coordinates, the creature interpreter (`FoeVM`), wall tests, hit rectangles, oxygen, ink, pieces, how a problem is judged | nobody |
| **Content** | sectors, screens, creature scripts, triggers, problems, texts, sounds, pictures, campaigns | you, with the editors; student campaigns |
| **Presentation** | everything that reads the rules' state and draws or plays it | skins; the original look is just the first skin |

### Why the rules never change

The port is built so that it can be checked against the 1998 original. Tests compare the original sectors' data with hashes of
the original's bytes, and replay sectors to check that the result is the same tick by tick. That check is worth keeping. It also
helps your own content: a sector of yours is played by exactly the rules the originals are, so if it works, it works for a reason
you can read.

Two consequences:

- A **skin** can redraw anything but cannot change a hit rectangle, a wait that holds up input, or what happens in a tick. The
  tests play every skin against the original and require the same result.
- A **pack** adds or replaces content. It never touches the rules. (A **mod pack** that a campaign declares adds behaviour at the named rule hooks only, as plain data the game checks: "Rule hooks", section 4.)

### Where the fork is

A change to how an existing rule works ends what this codebase does. Examples: fractional coordinates or engine physics instead
of the tile scan, a different tick rate, scrolling or larger screens, creatures whose behaviour lives in scenes instead of
creature scripts, 3D gameplay. After any of these the original sectors are no longer guaranteed to play as designed, and the
tests stop meaning anything. Such a "remake" should be a separate project that uses this one as its specification and content
source, not a branch that drifts.

Two things that look like changes to the rules but are not:

- **High resolution.** The rules keep 640 x 400 as their coordinates. Godot draws 2D at window size, so 4x art drawn at a quarter
  scale is sharp. That is a skin.
- **Other values for the rules** (more oxygen, a faster sub). The plan is that a pack states them as data and a pack that states
  none plays with the original's. This is not built ([`ROADMAP.md`](../ROADMAP.md)).
- **New gameplay from a mod** (the judging of a new problem type's answers, a new creature instruction, a sub ability). This is a mod pack whose code runs inside a
  sandbox, which a campaign declares and the original campaigns provably do not ("Rule hooks", section 4).

---

## 2. The kinds of content

Each kind below says what it is, where the original's copy lives, and how you change it. "legacy" is the original game as a pack, made
from your own copy (section 4); it is the folder `godot/packs/legacy`, `res://packs/legacy/`. "dev" is the pack of placeholder content that is part of the project (the folder in the editor, the pack file `dev.larissa` for a binary)
(`res://packs/dev/`), with the same files in the same places and none of the original's content. Paths are shown as `res://` paths, for
legacy; dev has the same paths under `res://packs/dev/`.

| Kind | What it is | Where legacy has it | Change it with |
| --- | --- | --- | --- |
| Sector | a level: 12 screens, a start, pieces, creatures, triggers | `res://packs/legacy/data/sectors/sector_NN/` | screen editor, sector inspector, Foe Script editor |
| Problem | one of 34 math problem types, with stored questions and answers | `res://packs/legacy/data/problems/problem_type_NN.tres` | a pack's `data/problems/problem_type_NN.json` |
| Text | every string the game shows (menus, hints, story, log, messages) | `res://packs/legacy/data/problems/*.tres` text tables | a pack's `texts.json`; a campaign's own words |
| Picture | sprites, tiles, backgrounds, interface and problem art | `res://packs/legacy/assets/` (PNG) | a pack's `pictures/`; a skin |
| Sound, music, speech | effects, 20 MIDI songs rendered to OGG, 371 speech clips | `res://packs/legacy/assets/audio/` | a pack's `audio/` |
| Story timeline | the opening, the title and the two closings as timed tracks | `res://packs/legacy/data/story/news_cartoon.tres`, the rest in `res://data/story/` | a complete pack replaces `news_cartoon.tres`; the rest is the project's, not a pack's |
| Duration | how long a station trip, a fade, a message takes | `res://data/rules/durations.json` | a pack's `rules/durations.json` |
| Rule value | the sub's speeds, the air and ink limits, the respawn screen, the trigger countdown, the lock's waits | `res://data/rules/tuning.json` | a pack's `rules/tuning.json` |
| Name | the friendly name of each sound, picture, song, sector ... | `res://names/original.json` | edit the registry; `tools/import/rename_name.py` |

### Sectors

A **sector** is one level. It has:

- **12 screens** (numbered 0 to 11). Each screen is one flip-screen of walls and currents (38 x 18 tiles of 16 pixels),
  decorations (behind the walls, between, and in front of the sub), and math-problem **triggers**. Screens 0 and 11 are where the supply station is drawn.
- **A header**: where the sub starts, the four neighbour tables (which screen you reach by leaving left, right, up or down),
  the **pieces** you collect (at most 11, and piece 0 is the data canister), the zone (which art set), and the song.
- **Creatures** (called "foes" in the code): up to 255. Each has a start place, a picture and damage.
- **One shared creature script** for the whole sector, in `sector_NN.foe`. It is plain text. Every creature runs its own
  copy of its place in the script. See [`FOE_SCRIPTING.md`](FOE_SCRIPTING.md).

A sector of a complete pack is stored as `sector_NN.tres`, `sector_NN.foe` and twelve `screen_MM.tres` files in
`<pack>/data/sectors/sector_NN/` (for legacy, `res://packs/legacy/data/sectors/sector_NN/`). A sector you make with the editors goes to
`res://data/sectors/sector_NN/` in the project, whatever pack is in use. In the data form the same sector is `sectors/sector_NN/sector_NN.json`
and `sector_NN.foe`.

What a sector may contain is limited to what the original's formats can hold (11 pieces, 255 creatures, 12 screens).
The **sector checks** (Project > Tools > "Check sector...", or `check_sector.tscn` from a terminal) tell you whether a sector
is playable: the data fits, the script assembles, every screen is linked, the start is clear of rock, and, by search, the sub
can reach every piece, the canister and every trigger.

### Problems

A **problem type** is one of the 34 kinds of math problem (lock, ballast, scan, calculator ...). The original does not
generate problems; each type holds stored **records** for each of four educational levels, and the game picks one at random.
Which type a trigger asks is a table (the **trigger table**: trigger slot, level and pick give a type) that is a `.tres` file of the
complete pack, so only a complete pack has its own. A pack may replace a whole problem type, questions and answers included, and may **add** types of its own (the numbers 34 to 255, the byte the trigger table holds): a type
is the file `data/problems/problem_type_NN.json` (the data form of the class `ProblemType`), worded by itself: its text 0 is the prompt, 1 the hint, 2 the worked solution and 3 the success text (an empty text is none), and `{k}` in any of them is field `k` of the
record. The answer is judged by the type's data as the original's are (`compare_mode`, `answer_fields`, `tolerances`). A type a pack adds is asked only where the chain has it: a trigger table of that chain names it, and Math Practice "All Math Problems" and the
debug menu list it after the original's; the original campaigns, which run on a chain without it, never do. Its picture is a generic `items` diagram, or, in a mod pack, drawn by a script ("Problem screens").

### Texts

Every string of the game has a **text name** in the registry. `Catalog.text(&"some_name")` returns the words. A pack's
`texts.json` is asked first (the chosen pack's, then its base's), so it can say a text of the base in other words, or add texts of its own. A campaign's own
titles and messages may be a text name or just the words (section 3).

### Pictures

Pictures are PNGs. Each one has a **skin key**, written `<kind>/<name>`: `ui_picture/title_sky`, `background/bg_s00_00`,
`problem_art/log_scan_0`, `frame/dolphin_swim_0`, `deco/...`, `tile/zone0_tiles`. A key is how a skin or a pack says "this
picture". The kinds a pack may supply are `ui_picture`, `background`, `problem_art`, `frame` (creatures), `deco` and `tile`.

Files of the legacy pack are named `<name>_<number>.png` (`log_scan_0_2046.png`): the friendly name, then the original's number.

### Sounds, music, speech

The original's effects and speech are WAV files, its songs OGG, all in `res://packs/legacy/assets/audio/` (`sfx/`, `music/`, `voice/`;
dev has the same folders, with clips that say their own names). A pack outside the project supplies **OGG Vorbis** files, in `audio/sound/`, `audio/music/`
and `audio/voice/` (note: `sound`, not `sfx`), named by registry name. A clip with the name of one in the base replaces it; a new name adds a clip.

Some of the original's sounds are stored twice under two numbers (the same recording), and scripts use one or the other. Replacing
`sound 20` does not replace `sound 6`. `same_audio` in the registry lists these groups ([`NAMES.md`](NAMES.md)).

**Speech holds up play.** A line of speech lasts a number of ticks, and the game waits that long. For the original these are
measured once by the importer. For a pack's own clips the game measures each clip when it loads the pack, or you state a length in
`audio/lengths.json` (section 4, "Clip lengths"). No sound or song holds up play.

### Story timelines

The opening, the title and the two closings are timed tracks of data in `res://data/story/` and, for the news cartoon, `res://packs/legacy/data/story/` (a `CutsceneTimeline`: when each
picture, text or sound happens, in ticks). The scenes only play them. The news cartoon is read from the chain (a complete pack has its own);
the others are preloaded by the scenes, so no pack can replace them. A campaign without a closing of its own gets the **generic finale** (section 3).

### Durations

Every length that holds up play is a number in `res://data/rules/durations.json`: how long the supply station's door and the
sub's launch and dock take, where the balloon goes, the dissolve after a lost tank, the log scan, a fade, a message, the wait on
the surface ship. Units are in the file: mostly ticks of the original's 73 Hz timer; a station trip counts game ticks (12.17 Hz).

The file is committed (it is hand-made, not copied out of the game) and holds the original's numbers
([`HARD_CODED.md`](../engine/HARD_CODED.md)). A pack states only the keys it changes, in its own `rules/durations.json`; the files of the
chain are laid over the project's file key by key (the bottom pack first, the chosen pack last), and a key no pack states keeps the project
file's number. The pack check refuses numbers that cannot work (a step of zero ticks where one is needed, a dock that drives left) and
warns about odd ones (no movement at all, a wait longer than ten minutes). So a longer dock is a number you change, not code. A skin is
*told* the length and fits its animation to it; it never decides it.

### Rule values

The numbers the rules run on are in `res://data/rules/tuning.json`: the sub (speeds, the collision rectangles, the picture tables), the
air (oxygen of a tank, spare tanks, the spare tanks a refill gives), the ink (a full supply, pellets in flight), the sector (the screen of the respawn point, the
countdown of a math trigger) and the combination lock's waits. The file holds the original's numbers and is laid out like the
durations: a pack states only the keys it changes, in its own `rules/tuning.json`, and the files of the chain are laid over the
project's file key by key (`godot/packs/dev/rules/tuning.json` is a complete example: every value changed). A game takes the values of its pack chain when it starts. How a rule works is not a value and no pack
changes it; the file's own `_about` note lists the units. The code side is in [`ARCHITECTURE.md`](../engine/ARCHITECTURE.md), "Rule values are data".

The pack check refuses a file the rules cannot run with (a key the game's file does not have, a speed of 0, a table of the wrong length,
a respawn screen the sector lacks) and warns about an odd one (a sub much faster than the original, more oxygen than the console has
places for); [`PACKS.md`](../engine/PACKS.md), "Validation". The original's numbers are the defaults: the original plays on the project's
file alone.

### Names

The original knows things by number: sound 22, picture 40, flag 3, sector 17. The **registry**, `godot/names/original.json`,
gives each number a friendly name (`begin`, `lock_tick`, `dragon_reef_voyager_1`). Names are ours, not the original's; nothing in
the file is original text or bytes. It is hand-made and committed, and the importer never writes it.

Kinds of names: `sound`, `frame` (creature picture), `deco`, `music`, `voice`, `ui_picture`, `problem_art`, `text`, `zone`,
`sector`, `foe`, `screen`, `flag`. Some are global; `frame`, `deco`, `foe`, `screen` and `flag` are scoped to a zone or a sector,
because slot 40 is a different drawing in every zone. Every number has a name: if nobody named it, it gets a made-up one
(`sfx_28`, `frame_040`) that always works.

Names are used in creature scripts (`Play_Sound begin`), in skin and pack file names, and in campaign data. Almost all names are
provisional: the author expects you to rename them. Packs do not bring a registry of their own; a new clip or picture in a pack
simply has a name that follows the same rule (`[a-z][a-z0-9_]*`, at most 40 characters). The full story, with the rename tool, is
[`NAMES.md`](NAMES.md).

---

## 3. Campaigns

A **campaign** is one whole game, as data. It is a `Campaign` resource (`res://src/resources/campaign.gd`). Voyager and Expert are
two of them (in legacy); so is dev's `dev_tour` and every campaign you or a student make.

```
Campaign
 |- id, title, banner
 |- sectors        the ordered list of sector numbers you play through
 |- finales        sectors whose end is the end of the game
 |- default_edu_levels   the starting math level, per zone
 |- canister log   what each log entry says, and its speech
 |- supply station what mission control says after each sector, and its speech
 |- fallback_song, closing_scene (or finale_text + finale_picture)
 |- mods           the mod packs it uses (pack ids), if any: "Rule hooks"
```

| Campaign | In pack | Sectors | Finale | Closing | Made by |
| --- | --- | --- | --- | --- | --- |
| `voyager` | legacy | 0-14 | 30 | the Voyager closing | the importer, from your copy |
| `expert` | legacy | 15-29 | 31 | the Expert closing | the importer, from your copy |
| `dev_tour` | dev | 0-3 | 4 | the generic finale | the dev pack's generator |
| yours | any pack, or the project | your numbers | one of them | the generic finale | you |

`dev` also holds test sectors (100 and up) that belong to no campaign and one campaign, `test_c`, for the engine tests; they are not meant for play.
The game's campaign list is every campaign of the chain, the project's own (`res://data/campaigns/`) among them, with `voyager` and `expert` first when
there are any and the others by id. A new player starts in the first of the list (`Catalog.default_campaign`): `voyager` when legacy is in the chain, else
the first by id.

### Sector numbers

A sector number is 0 to 255. Nothing in a pack is reserved: the numbers belong to whatever pack holds them.

- **Down the chain.** A sector is asked of the chain, the chosen pack first. A pack that holds sector 5 hides sector 5 of the pack under it, so a
  small pack that remakes one sector is a different game, not an error. The pack check allows it. Only legacy's sectors 0-31 have original bytes,
  hashes, fixtures and reset tools; the fidelity tests run on legacy alone.
- **New sectors from the tools.** "New sector..." (`Catalog.next_free_sector`) picks the lowest number from 32 up that no pack of the chain and no
  sector of the project has, and refuses a number below 32 (`Catalog.ORIGINAL_SECTOR_COUNT`: a left-over of the original, listed in
  [`HARD_CODED.md`](../engine/HARD_CODED.md)). With legacy or dev, yours start at 32. A new sector is
  its own source: the importer never writes or deletes it.
- A sector belongs to **one** campaign (the pack check reports a sector listed in two). A sector in no campaign is a warning, not an error.

### Finales

A sector with a `finale_screen` (the screen where the closing starts) is a finale: the sub touches the treasure and swims to the
closing. A campaign lists its finale sectors in `finales`; docking in one ends the game. To make one, copy a finale sector
(legacy's 30 or 31, or dev's 4).

The closing is `voyager` or `expert` for the originals. A campaign with neither (`dev_tour` among them) gets the **generic finale**
(`GenericFinale`): the campaign's title, its `finale_picture` and its `finale_text`, then the Hall of Fame. Enter or a click goes
on; Space or Escape skips.

### Words of its own

A text of a campaign (`title`, `log_texts`, `supply_texts`, `finale_text`) is either a text name from the registry or the words
themselves. Voices (`log_voices`, `supply_voices`) are groups of speech clips. A group may be empty, and then the line is not
spoken.

### Saves are keyed by campaign

Each player in the roster, and each row of the Hall of Fame, stores the **campaign id**. Progress is stored as
`sector number * 2 + midpoint flag` (the original's own scheme), checked against the campaign's list when loaded. If a record
belongs to a campaign that the game is not using (its pack is not in the chain, or gone), the record is kept and shows "not installed"; you cannot
Start it until the game uses that pack again (`--pack=`). Nothing is lost.

The new-player dialog lists every campaign of the chain.

---

## 4. Packs

Content comes in **packs**. A pack is content with a manifest, `pack.json`, either a **folder** or one **pack file** (`<id>.larissa`, a zip of that folder; "Pack files" below). The engine has no content of
its own: it plays the pack it is given. The game uses **one chosen pack and the chain of packs it is laid over**; everything it asks for (a
sector, a picture, a sound, a text, a table) is looked up down that chain. This section is the user's view; the code is
[`PACKS.md`](../engine/PACKS.md).

### Complete packs, packs laid over another, and the two that are known by name

A pack with no `base` is **complete**; a pack with a `base` is laid over that pack.

| | Complete pack | Pack with a `base` |
| --- | --- | --- |
| Manifest | no `base` | `"base": "<id>"`: the pack it is laid over |
| Holds | everything a game is made of: the rules' tables, tile set, catalogs, layouts, problem types, sectors, campaigns, pictures, sounds, MIDI | some content: sectors, a campaign, texts, pictures, clips, a few problem types, durations |
| Stands alone | yes: the pack check reports any file the game needs that it lacks (`engine/PACKS.md`, "What a chain needs") | no: it needs the packs under it |
| Examples | `dev`, `legacy`, a copy of dev | a student campaign exported as a pack; a pack that remakes two sectors of `legacy` |

- **`dev`** is the folder `godot/packs/dev/` of the project (committed); a game without that folder gets it from `dev.larissa`, a pack file that comes with the
  creator download ("Shipping" below, and "Where packs are found"). It is a complete pack of placeholder content for developers: coloured shapes with
  their asset names written on them, speech that says their own name, sounds that say "bang", a short playable campaign (`dev_tour`) and test
  sectors for the engine tests. It holds nothing of the original. It is not meant for play; it is what an author copies to start a game of their
  own, and the engine's tests run on it ([`tools/dev_pack/README.md`](../../tools/dev_pack/README.md)).
- **`legacy`** is the original game, made by the importer from your own copy ([`LEGACY.md`](../play/LEGACY.md)) as the folder `godot/packs/legacy`. It is a complete pack
  like any other: the engine has no special case for it, and it is never in git.

The id `dev` is reserved: it is the folder of the project or the installed `user://packs/dev` or `user://packs/dev.larissa` (below), a pack folder anywhere else that says it is `dev` is ignored
(the log and the pack screen say so), and a copy of dev needs an id of its own. Every other id, `legacy` included, is an ordinary id.

### Where a pack lives, and what is trusted

There is one kind of pack. What is safe depends on **where the pack is**, and so on **how its files are read**:

| | A pack in the project (`res://packs/<id>/`) | A pack outside it (`user://packs/<id>/` or `<id>.larissa`) |
| --- | --- | --- |
| What it is | as much the project's as its code: `dev`, `legacy`, a copy of dev you are working on | installed or shipped: content others can share |
| Holds | the authoring form: `.tres` files (the editor, the Inspector and uids work on them), pictures and sounds with their import settings | the **data form**: JSON, `.foe` text, PNG, OGG, WAV, MIDI |
| Read with | Godot's resource loader | plain file reading; never Godot's resource loader |
| Safe to install from a stranger | n/a: you put it there | **yes**: it can run nothing but the creature interpreter and, in a mod pack, a sandboxed script ("Mod packs" below) |
| Made by | the importer (legacy), `pack_tool --new` (a copy of dev) | you, or the pack tools (`--export-campaign`; `--export-pack` writes a whole pack, dev, legacy or a copy of dev, in this form) |

A pack outside the project holds only files the game reads itself. The game decodes them with plain file reading and never hands them to Godot's resource loader (a
`.tres` can carry a script), so installing one runs nothing. It cannot hold scenes, scripts or resources, and it never answers for a `.tres` file even if one is in its
folder. What a `.tres` holds in the project, such a pack holds as the JSON of the same name (`data/zones.json` for `data/zones.tres`: the **data form**,
[`../engine/PACKS.md`](../engine/PACKS.md) "JSON forms"), and a picture or sound a data file names is a file of the pack (`{"$ref": "assets/sprites/sub/sub_00.png"}`). It
names a `base`, or it is complete: every kind in the data form and no `base`, as `pack_tool --export-pack=<id>` writes dev, legacy or a copy of dev. A pack with no `base`
that lacks what the game needs gets `dev` put under it (when there is a dev pack) and the game opens on the warning, below. A manifest cannot make a pack trusted, and a pack file is never trusted.

A **skin** from the project is scenes, scripts and shaders of the project (section 5); a skin you give to other people is a mod pack (below, section 5, "Skins and packs"): a pack like any other, installed with no trust question.

### Where packs are found

| Place | Holds |
| --- | --- |
| `res://packs/<id>/` (`godot/packs/<id>/`) | the project's own packs: a folder with a `pack.json`, in the authoring form. `dev` is committed; `legacy` is written by the importer; everything else in the folder is git-ignored. |
| `user://packs/<id>/` | an installed pack: a folder in the data form. |
| `user://packs/<id>.larissa` | an installed pack: a pack file (the pack screen's Install copies one here). |
| `<id>.larissa` next to the game's executable (a desktop build; not the editor) | `legacy.larissa` and `dev.larissa`: the packs a game carries. They are read where they lie. |
| `/packs/<id>.larissa` (a Web build) | the same, for the pack files the page preloads (`Packs.WEB_ARCHIVES_DIR`). |

The places are looked at in this order, and the **first place that has an id wins**: a folder in `res://packs/`, a folder in `user://packs/`, a pack file in those folders, then a
bundled pack file. The pack screen and the log say which pack of an id is used and which were left out. A pack file is used only when the id in its `pack.json` is the one in its
file name (`legacy.larissa` holds `legacy`).
So an installed folder `user://packs/legacy/` is used and a `legacy.larissa` next to the game is left out; delete the folder to use the file.
`Packs.available()` lists the packs found, in the lexical order of the ids; a pack with errors is listed (the pack screen shows them) but never chosen by default.

**Where dev comes from.** In the editor `godot/packs/dev/` is a folder and there is nothing to do. A game without that folder (an exported one) uses a dev you installed in `user://packs/` (from the pack screen or `pack_tool --install`), else the `dev.larissa` next to it; it is the dev pack when something needs dev (a pack laid over `dev`, `--pack=dev`, the
pack tools' copy of dev, a debug build's fallback). The project's own dev always wins over an installed one. Without dev, a
pack that is laid over it or `--pack=dev` is refused with the advice to get `dev.larissa`, a debug build has nothing to fall back to (it refuses a chain that is not whole, as a
release build does), and the pack tools that start from dev (a new pack from dev, an export over `--base=dev`) say that dev is missing. Making a game of your own from a binary
therefore starts with `dev.larissa` from the creator download.

### Choosing the pack

- **`--pack=<id>`**, after `--` on the command line, chooses: `tools/godot.sh --path godot -- --pack=orchard`.
- **Without it**, the first pack found in the lexical order of the ids is chosen. The common case needs no flag: one complete pack that is installed
  (only `legacy`, say) is simply played, alone, with no warning and without dev.
- **When the chain is not whole** the game opens on a **warning screen** that says why and where to read about it. The reasons (`Packs.Fallback.Why`): no pack was
  found; the pack asked for is not there; a pack has errors; a pack names a `base` that is not there; the `base` links go round in a circle; the chain lacks files or things the game needs (the start-up check, `PackNeeds`; a campaign that names a sector nobody has counts, a
  missing picture of the finale or line of speech does not). A debug build puts `dev` under what was found, so its placeholders answer only what is missing; the screen
  says how many things are missing, and any key goes on into the game. (With no dev pack there is nothing to put under it: the debug build refuses too, and the screen adds that
  there are no dev assets to fall back to and where to get `dev.larissa`.) A release build does not play the chain: the screen is a refusal (what is wrong, where to read) with
  the pack screen, to choose another installed pack (it is checked again), and Quit; any other key or click quits. The sentences depend on the situation: no pack at all
  (build the content from your own copy of the original, [`LEGACY.md`](../play/LEGACY.md)); a complete pack that is incomplete (damaged or out of date: run the importer
  again); a pack laid over another that is incomplete or whose base is missing (unfinished, or it needs a pack that is not installed: this document and
  [`MAKING_CONTENT.md`](MAKING_CONTENT.md)).
- **`--pack=dev`** chooses dev on purpose: no warning, and a pack whose `base` is `dev` is whole too, in both kinds of build. The engine's tests run this way (`tools/run_tests.sh`).
  When there is no dev pack, both are refused in both kinds of build, with the advice to get `dev.larissa`.

There is no pack-choosing menu yet. The pack screen (P on the sign-in screen) shows which packs were found, the chain in use and why it is that one.

### The layout of a pack

A complete pack **in the project** is laid out the way the importer writes legacy and the generator writes dev: `pack.json`, `assets/` (pictures and sounds, each with a
`.import` file), `data/` (`sectors/`, `campaigns/`, `problems/`, `zones.tres`, `trigger_table.tres`, `neptune_tileset.tres`, the sound catalogs, layouts, ...)
and `midi/`. Section 6 lists legacy's files; dev has one file for every file of legacy's `assets/` and `midi/`. `pack_tool --new=<id> --from=dev` copies it.

A pack **outside the project** lays its content out as below. Every part is optional.

```
<id>/                                  folder
  pack.json                            the manifest
  campaigns/<id>.json                  a campaign (id = file name)
  sectors/sector_NN/sector_NN.json     a sector, NN = 0 to 255
  sectors/sector_NN/sector_NN.foe      its creature script (same text as in the game)
  texts.json                           {"text_name": "the words"}
  voice_cues.json                      {"groups": {"group_name": ["voice_name", ...]}}
  pictures/<kind>/<name>.png           a picture by skin key
  audio/sound|music|voice/<name>.ogg   a clip by registry name
  audio/lengths.json                   {"voice": {"name": ticks}}  lengths you state yourself (optional)
  data/problems/problem_type_NN.json   a problem type; any other data/ file of a complete pack is held the same way, as the JSON of the same name
                                       (data/zones.json, data/ui/hud_layout.json, data/sprite_frames/sub_frames.json, ...)
  rules/durations.json                 durations laid over the lower ones, key by key
  rules/tuning.json                    rule values laid over the lower ones, key by key
```

The **manifest**, `pack.json`:

```json
{"id": "orchard", "title": "Orchard", "version": "1.0", "base": "legacy", "author": "", "description": "", "format": 1}
```

`id`, `title` and `version` are required. `id` is a lowercase word: letters, digits and `_`, starting with a letter, at most 32
characters. `base` is the id of the pack this one is laid over (also a lowercase word, and not the pack's own id); leave it out for a complete pack.
`author` and `description` are optional. `format` is 1. A key the game does not know (`"tier"`, say) is left alone.

The JSON files are the same data as the `.tres` files of a complete pack, one key per field with defaults left out. A field the class does not have,
or a value of the wrong kind, is reported by the pack check; it is never silently ignored.

### The lookup: the chosen pack first, then its bases

Every time the game wants something, it asks the packs of the chain in order: the chosen pack, its base, the base's base. The first one that has it
wins. It works like your shell's `PATH`, or CSS.

```
  game asks for "picture ui_picture/title_sky"
        |
        v
   chosen pack ----has pictures/ui_picture/title_sky.png?---> use it
        | no
        v
   its base    ----has it?---> use it
        | no                    (and so on down the chain)
        v
   the skin in use, then the skin it builds on, ... ----has it?---> use it
        | no
        v
   the first pack of the chain that has the picture's file
   (assets/ui/title/title_sky_1039.png in legacy; dev has the same path)
```

There are two kinds of lookup, both down the chain:

- **A whole file** of a complete pack (`data/zones.tres`, `assets/tiles/zone0_tiles.png`): the first pack that provides the file. A pack of the project answers
  for a `.tres`, any pack for the JSON of it (`data/zones.json`). `Catalog`, `Assets`, the music and the scenes ask this (`Packs.resource`, `Packs.texture`, `Packs.stream`).
- **A thing a pack holds in the layout above**: a sector or campaign as JSON, a text, a picture by skin key, a clip by name, a problem type. A pack
  with no such thing answers nothing and the next one is asked. Texts and speech groups are merged down the chain, the pack nearest the top having
  the last word.

Pictures have one more layer: **a pack's picture by skin key wins over every skin**. The content says what a picture is; a skin only dresses what the
content leaves alone. Sounds, texts, problem types and durations do not involve skins.

Sectors and campaigns of the project itself (`res://data/sectors/`, `res://data/campaigns/`, the ones the editors make) are the lowest layer, under the chain.

### What a pack can and cannot hold

The rules are code and no pack changes them. What is left is decided by where the pack is alone; the engine protects no content.

| A pack outside the project **can** | A pack outside the project **cannot** |
| --- | --- |
| add or remake sectors (any number) and campaigns (any id) | hold scenes, GDScript, resources (`.tres`) or skins |
| add or re-word texts (`texts.json`) | change the project's own data (the menu layout, the cutscene timelines) |
| carry a sandboxed mod script (`.sgd`, "Mod packs" below) | hold any other code: a `.gd`, a native library |
| add or replace pictures of the six kinds above | |
| add or replace sounds, songs, speech (OGG, WAV) | |
| replace whole problem types | change how a rule works (only its values, `rules/tuning.json`; a mod adds behaviour only at the rule hooks of a campaign that declares it) |
| replace the data a complete pack holds (a zone table, a tile set, sprite frames, layouts, a story timeline) as JSON | |
| add speech groups a campaign can name | |
| state its own durations, rule values and clip lengths | |

A pack **in the project** can also hold `.tres` files, scenes and scripts: it is part of the project. It still cannot change the rules or replace a file of the game itself,
and when it leaves the project (`--export-pack`) it is written in the data form.

The pack check reports every one of these, so you do not have to remember them.

### Mod packs

A **mod pack** is a pack that also carries a script, written in SafeGDScript (a GDScript with a safe subset, `.sgd`), that the game runs inside the [godot-sandbox](https://github.com/libriscv/godot-sandbox) extension with restrictions on. Its manifest names the
script (`"mod": {"entry": "orchard.sgd"}`, with the API version it needs and, if it wants less than the game allows, its limits). The script can reach only what the game hands it: it can write to the log and load the pictures and sounds of its own pack,
and it can touch nothing else of the game; it cannot read a file by path, call into the game, or run past its time and memory limits (no limit is ever off, and a manifest that asks for 0 gets the lowest; a script that tries is refused or stopped, and one that keeps failing is switched off while the game goes on). So a mod pack is as safe to install from a stranger as a data pack,
and it asks no trust question. It is the only code a pack may hold. A mod pack whose manifest says `skin` is a **skin**: it draws the sector, chooses like any skin (`--skin=<its pack id>`, F3 then S) and is written as [`SKIN_API.md`](SKIN_API.md) says, "Writing a skin mod"; one whose manifest says `problems` draws the screen of problem types, those it adds and the original's ("Problem screens", below). The extension is fetched with `mise run setup` (`uv run tools/fetch_sandbox.py`, [`SETUP.md`](../SETUP.md)); a game without it plays every data pack and refuses a mod pack with that reason. A skin that only changes the look of the game's pictures, or puts a shader on a layer of the sector, needs no script: leave `entry` out ([`SKIN_API.md`](SKIN_API.md), "A skin with no script"), and the Sandbox is not needed to wear it. A mod whose manifest says `rules` adds gameplay inside the rules for the campaigns that declare it ("Rule hooks", below). The manifest, the loader and what a
mod is granted are in [`../engine/PACKS.md`](../engine/PACKS.md), "Mod packs"; `pack_tool --check` checks the script file as it checks the rest of the pack.

#### API versions

A manifest's `requires_api` (default 1) is the lowest version of the mod API the script needs. The game provides the highest (`ModSpec.API_VERSION`) and refuses a pack that needs more; a mod that asks for an older version keeps running, because what it was given is never changed or taken away. A manifest that uses a key of a later version is refused with the version it needs. This is the one list of the versions; every other document says "the version that draws the game" or links here.

| Version | What a mod can ask for |
| --- | --- |
| 1 | a script that writes to the log and loads the pictures and sounds of its own pack |
| 2 | a skin: `skin` with `shaders`, the script drawing the whole screen with `skin_frame` ([`SKIN_API.md`](SKIN_API.md)) |
| 3 | the screens of problem types the pack adds: `problems` with `types` and `shaders`, `problem_frame(state)` ("Problem screens", below) |
| 4 | gameplay at the rule hooks of a campaign that declares the mod: `rules` ("Rule hooks", below) |
| 5 | everything that draws the game: a skin with no script (`render`, `pictures`, `hud_font`, `layers`, `theme`), a script that draws named layers (`script_layers`, the console's too), a draw list that names a picture of the game by key, the screens of the original's problem types by number, and `problem_frame(state, events)` with the events, the clock and the sounds of a problem screen |

### Problem screens

A **mod pack** can draw the screen of a problem type of its own, or of an original type. A type it adds is data, like any problem type of the previous section; an original type is the game's own, and the mod opts in to draw it by its number. The script draws only the picture on the left monitor, and the game keeps everything else: the typed answer (the calculator or the answer box),
whether it is right (`AnswerChecker`), the two tries, the hint, the worked solution, the oxygen and every wait. Nothing the script returns can change the result, the score or a timing: a mod that is hostile, faulty or absent leaves the problem exactly as it is without it.
The worked example is `godot/tests/mods/tides/` (the type is built in `godot/tests/mod_problem_shelf.gd`).

```
pack.json     {"id": "tides", "title": "Tides", "version": "1.0", "base": "legacy",
               "mod": {"entry": "tides.sgd", "requires_api": 5, "problems": {"types": [3, 5, 40], "shaders": ["problems/glow.gdshader"]}}}
data/problems/problem_type_40.json   the type: texts, records, how an answer is judged; its diagram is {"family": "mod", "items": [...]}
tides.sgd     the script
problems/*.png, problems/*.gdshader   pictures and shaders (listed in the manifest) the screen may name
```

`types` lists the problem types the mod draws (at most 64, each from 0 to 255). A number from 34 is a type the pack adds: it must be a file of the pack with the diagram family `mod`, and `items` of its diagram are the **plain picture** the game falls back to (the vocabulary at the top of `DiagramBase`).
A number below 34 is an **original type**, drawn in place of the original's diagram (the version that draws the game, "API versions"); the pack holds no file for it, and the original's diagram is the plain picture the game falls back to. The other original types stay the original's. The combination lock (type 0) and the ballast panels (28, 29)
are answered through their own diagram, so no mod can list them. If several mods of the chain list the same original type, the first one (the chosen pack's) that runs draws it.
`pack_tool --check=<folder>` judges the manifest, the type files, the pictures, the shaders and the presence of `problem_frame`; a mod that fails is refused with the reason when the game loads it, and its type is then shown as its data describes it.

```
func problem_frame(state : Dictionary, events : Array) -> Array:
	var out := []
	for row in state["fields"][0]:
		for column in state["fields"][1]:
			out.append(["picture", "problems/fish.png", Vector2(28 + column * 24, 28 + row * 22)])
	out.append(["text", "Typed: " + state["entry"], Vector2(24, 260), 17, Color.WHITE])
	return out
```

`problem_frame` is called when the screen is shown, when what it is told changes (the player types a key, the step changes) and on the frame after something happened ("What happened"); it returns a draw list in window pixels (`window`, 640 x 400, clipped to it), the **same list** a skin returns, checked by the same code:
[`SKIN_API.md`](SKIN_API.md), "The draw list" has the commands (`rect`, `line`, `picture`, `region`, `text`, `layer`), their caps and the shaders. A picture is a PNG of the folder `problems/` of the mod's own pack, or a picture of the game named by its skin key (`problem_art/log_scan_0`, `ui_picture/...`; `SKIN_API.md`, "Pictures by key"), which the game resolves under the skin in use (a mod that does says the version that draws the game). The calculator, the prompt and the message box are drawn by the game over the picture.
The script runs under the mod's limits, and a mod that draws is held to at most 10 million instructions per call. Every mod runs under at least 1 million: a limit of 0 in a manifest is 1, so no mod runs uncounted.

**The state.** A read-only Dictionary of plain values (`ProblemState.build`):

| Key | Value |
| --- | --- |
| `type`, `level`, `title` | the type's number, the educational level (0 to 3) and its title |
| `prompt` | the problem's statement as the game words it |
| `fields` | the record's fields in order: a whole number for a byte or a word, `{"text", "value", "fraction"}` for a number (`text` the way the game prints it, `value` a float, `fraction` true for a fraction) |
| `family` | the diagram family the type's data names (`items`, `sonar`, `pie` ...; `mod` for a type a pack adds) |
| `diagram` | the type's diagram data as the pack holds it: what the original's diagram draws from (the vocabulary at the top of `DiagramBase`: pictures by number `pic`, positions, the record fields they read, the build-up) |
| `art` | the skin keys (`problem_art/pa_1843`) of the type's pictures in the order `diagram` numbers them (`pic`): a script names one to draw it; `""` for a file that has none |
| `entry` | what the calculator or the answer box shows now (`"0"` before anything is typed) |
| `step` | `intro` while the diagram builds up, `answering` while an answer is awaited, `waiting` while a message, the solution or the success text is up |
| `attempt` | the try the player is on: 1, or 2 after a miss (the hint is up) |
| `clock` | where the animation is ("The clock"): `animation`, `tick`, `length`, `since`; idle (`""`, 0, 0, -1) for a mod that requires less than the version that draws the game |
| `window` | the size of the window, 640 x 400 |

The fields, `family`, `diagram` and `art` are the problem's and the type's data, the answer's field included (a ruler is drawn to the length it asks about). The script is **not** told whether an entry is right before the game has judged it, the oxygen, the hint, the solution
or the success text. `api["problems"]` has the plain facts: `types`, `window`, `max_commands`, `max_layers`, `max_uniforms`, `max_texts`, `max_text`, `min_font_size`, `max_font_size`, the manifest's `shaders`, the names of the `events` and the bounds of the sounds (`max_sounds`, `sound_burst`, `sounds_per_second`).

**What happened.** `problem_frame(state, events)` takes the events since its last call as a second argument (the same goes for the clock and the sounds below: a mod that requires less than the version that draws the game, "API versions", defines `problem_frame(state)` and is told none of them). An event is `[name, arguments...]`, the shape of the sector's events ([`SKIN_API.md`](SKIN_API.md), "The events"), and is told **after the game decided it**: the game says it, never the script's own reading of the screen, and nothing the script returns reaches the game. Every type has the same set, the original's and a pack's:

| Event | Arguments | When |
| --- | --- | --- |
| `started` | none | the problem opened; the first event |
| `step` | `name` (`intro`, `answering`, `waiting`) | the step of the state changed to `name`; last of the events one input causes (an answer, a tick, Enter), so a step passed through on the way is not told |
| `verdict` | `right`, `attempt` (1 or 2) | an answer was judged; an entry with nothing usable in it ("Type a number first.") is no answer |
| `damage` | `amount` (1), `tank_lost` | a wrong answer cost oxygen, and `tank_lost` says it used up the air; after the `verdict`; not told in Math Practice, where wrong answers cost nothing |
| `success` | `solved` | the success replay and text begin; `solved` is false for the success text that follows the worked solution of a second miss. Math Practice tells a right answer too |
| `timeout` | none | a message ran out its time (146 ticks) with no Enter or click; the step it leads to follows |

The events come **on the frame after they happened**, in the order they happened, as one list in one call (the newest 64 if more came); the state of that call is as of then. A call that faults, or events that come while no mod runs (the mod is quarantined, unloaded or absent), are not told again. Events are changes and the state is the truth: a script bound in the middle of a problem (its mod runs from then on) is told what happens after it, not what happened before, and builds the picture from the state (the step, the entry, the `attempt`), so a picture that is a function of the state is the same whenever the script began. A reaction, such as a flash for a wrong verdict, is the one thing a picture does from memory of events; it changes nothing the game does. The lock and the ballast panels hear the events as well, and no mod draws them. The worked example, `godot/tests/mods/tides/`, shows the last event it heard and a mark for each oxygen lost, and a bar that follows the clock.

**The clock.** The state's `clock` says where the game's own animation is: `animation` is `"intro"` while the diagram builds up, `"replay"` while the right answer is replayed (types 6, 11, 12, 16, 22, 23, 26 and 27 have one) and `""` otherwise; `tick` is how many of its ticks are over (0 to `length`), `length` how many ticks it lasts and `since` the tick the script was last told in this animation (-1 for the first call of it). A tick is 1/73 s, the original's. The lengths are the original's data, counted by the game, which shows the animation as of its own count, so a script that draws frame `tick` of `length` (a bar, a needle, a fade) draws on the game's clock: it stands still when the game's time does, a frame rate or a slow script lengthens nothing, and **nothing the script draws or returns makes an animation longer or shorter, or ends it**. The script is asked again as each tick goes by while an animation runs (not per frame, per tick: at a low frame rate several ticks may pass between two calls), so a thing due on tick `n` is due when `since < n <= tick`; the last call of an animation carries its end tick and the call after it the idle clock. The end tick is told while the state's `step` is still the animation's, then the idle clock, then the step that follows.

**Sounds.** `problem_frame` may return, in place of the draw list, a Dictionary `{"draw": [...], "sounds": ["diagram_pop", ...]}` (either key may be left out: without `draw` what is on screen stays, without `sounds` none is asked for). A sound is a **name**: one of the original's effects by its name in the registry ([`NAMES.md`](NAMES.md); `diagram_bar`, `diagram_pop`, `thermometer`, `click`, ...) or a file `audio/sound/<name>.ogg` of any pack of the chain, the mod's own pack included (the same door as a pack's replacement of an effect), so a mod adds a sound by shipping the file and naming it. The game plays it through the one `Audio` door, with the sound effects option and the window's focus as for every other effect; a name that is not a sound of the chain is dropped. The script holds no audio and cannot stop, loop or mix a sound. It is bounded: at most 4 names are heard of one answer (`max_sounds`), and the screen holds a bucket of 8 sounds (`sound_burst`) that refills at 8 a second (`sounds_per_second`), a made-up name costing one like a good one, so a script that asks for a thousand sounds is heard for a handful. The first call, made while the screen is built, has nobody to hear it: ask on the `started` event or later. A sound holds nothing up and changes no length, a mod cannot silence the game's own cues (`correct`, `wrong`, the calculator's keys: the flow and the inputs play them), and the original diagram's own sounds (the build-up's and the replay's) are played as they are **unless the manifest says `"own_sounds": true`**, `"problems": {"types": [3], "own_sounds": true}`: then they are not played while the mod runs and is not quarantined (a mod that faulted, or is absent, leaves the original's), and the script asks for the sounds it wants at the ticks it wants from `clock`. The lengths are the same either way.

**What the game does with the answer.** The draw list is checked command by command and drawn by the game (`ModDraw`, `ModLayer`); a command that is not exactly one of the list is dropped, so a script cannot draw anything but pictures of its own pack, rectangles, lines and text in the game's font. A frame the script spoils (an error, a result that is
not a list) leaves the last good one on; before the first good one, and once the mod is quarantined (it faulted too often), unloaded or absent, the screen shows the plain picture of the type's data (for an original type, the original's diagram). The problem is as long as the game makes it: the build-up and the replay after a right answer of an original type run on their own lengths (and with their own sounds, unless the mod says `own_sounds`) whatever the mod draws, and a mod animates by drawing from the `clock`. A picture named by key follows the skin in use, also when the skin changes in the middle of the problem, and a mod that arrives or leaves in the middle of a problem draws, or stops drawing, from then on. How the game builds the screen (the plain picture under the mod's, the clock, the events, the sounds) is [`../engine/PACKS.md`](../engine/PACKS.md), "Mod packs".

### Rule hooks

A **mod pack** can add gameplay at three named points of the rules, and only for the campaigns that **declare** it. The campaign names the mod packs it uses by pack id, and the original campaigns name none, so they run none of it:

```
campaigns/orchard.json   {"class": "Campaign", "id": "orchard", ..., "mods": ["orchard_rules"]}
pack.json (orchard_rules) "mod": {"entry": "rules.sgd", "requires_api": 4, "rules": {"answers": [41], "instructions": [0, 1], "sub": true}}
```

When a game of the campaign begins the game finds each named pack in the chain in use and keeps what it offers for that game. A mod that is in the chain but that the campaign does not name is never asked. A named mod that is not
there, was refused, or lost an instruction number to a mod named before it, is skipped (the campaign plays on with the original's behaviour wherever a hook is missing) and `pack_tool --check` warns of a name that is no mod
with rule hooks. Free play of a sector uses the mods of the campaign the sector belongs to; Math Practice uses none. `rules` lists what the mod does: `answers` (problem types from 34 to 255 whose answers it judges; the pack
holds each as data), `instructions` (numbers 0 to 7 of the creature instruction `Mod_Instruction`, which [`FOE_SCRIPTING.md`](FOE_SCRIPTING.md) describes) and `sub` (true: a sub ability); at least one. The script defines
`judge_answer(state)`, `creature_instruction(state)` and `sub_ability(state)` for the ones it lists. The worked example is `godot/tests/mods/rules/` (the type is built in `godot/tests/mod_rule_shelf.gd`).

A hook is given **one read-only Dictionary of plain values** and **answers plain data**; the game checks it, cuts every number to its bounds and applies it itself. A key that is not in the lists below, or a value of another kind, is
garbage and counts as a fault. Whole numbers only: `1.5` is not a number of steps.

| Hook | The state | The answer |
| --- | --- | --- |
| `judge_answer` | `type`, `level`, `fields` (the record's, as for a problem screen), `typed` (`{"text", "value", "fraction"}`) | `true` or `false` |
| `creature_instruction` | `number`, `value` (the operands of the instruction), `tick`, `creature` (its number), `position` (`Vector2i`, window pixels), `frame`, `mirrored`, `screen`, `shown_screen`, `sub` (`Vector2i`), `flags` (the 16 global flags as a number), `memory` | any of `condition` (bool: false skips the next instruction, as an `If_`), `end_turn` (bool), `set_flags` and `clear_flags` (bit masks), `frame` (a picture, kept inside the creature's range, bit 7 mirrors), `dx` and `dy` (2-pixel steps, -16 to 16; a move ends the turn), `memory` |
| `sub_ability` | `tick`, `sector`, `screen`, `position`, `velocity` (1/8 pixel a tick), `cell`, `invulnerability`, `steer` (the arrow keys as -1, 0, 1), `fire` (presses since the last tick), `max_velocity`, `max_invulnerability`, `memory` | any of `vx`, `vy` (the velocity; cut to the run's top speeds; the walls and the screen's edges apply to it in the next tick), `invulnerability` (ticks left; cut to the run's length of it), `memory` |

The instruction `Mod_Instruction number value` runs for a creature only in a campaign whose mod defines `number`; elsewhere the creature that reaches it faults like on any byte that is no instruction. The sub ability is asked
once a tick, in the `sub` step after the sub has moved, and only while the player steers the sub.

**Deterministic.** The same snapshot is the same answer. The game gives a hook no clock, no dice and no object. What a hook needs to remember it **answers as `memory`**: a Dictionary of at most 16 keys (texts up to 32 characters)
whose values are whole numbers, numbers, booleans, texts up to 64 characters or lists of up to 16 of those; the game stores it for that hook and hands it back in the next call. Memory, faults and `tick` start over every time
the sector's creatures are made (a sector start, a respawn, the reload at the dock), as the creatures' flags do, so a respawn plays like the first visit. Variables of the script's own are not given back, so a hook that depends on
them plays differently after a respawn; keep nothing there that an answer depends on.

**Bounded.** A hook runs under 1 million instructions a call (never 0, whatever the manifest asks), at most 16 calls are made in a tick, and the sandbox's other limits apply. A call that raises an error, runs past its limit, is
asked of a mod that was unloaded or answers garbage is a **fault**: the call has the original's behaviour (an instruction does nothing and the script goes on, the sub is not changed, an answer is judged by the type's own
`compare_mode`, so a type a mod judges must also say in its data how it is judged without the mod), the fault is written down (`RuleHooks.fault_log`, a warning in the log, once per mod) and a mod with 8 faults in a load is switched off
until the next load. `pack_tool --check=<folder>` judges the manifest, the function of each hook, the types and the campaign's `mods`.

### Clip lengths

Speech holds up play, so its length must be a number, not "whenever the file ends". The clip lengths of a pack's `audio/` folder are:

- **measured** when the game loads the pack: the file's length rounded *up* to whole ticks of 1/73 s. The same file always gives the same number, and
  nothing is played to find it out; or
- **stated** by you in `audio/lengths.json`: `{"voice": {"line_a": 300}}`, whole ticks of 1 or more. A stated length wins. A longer number leaves a
  pause after the line; a shorter one cuts it off.

The stream and its length always come from the same pack. The check warns you when a stated length is far from the measured one (more than a second,
or more than 25 percent), or names a clip the pack does not hold.

A pack's `rules/durations.json` is laid over the project's durations key by key: section 2, "Durations"; its `rules/tuning.json` over the rule values the same way, "Rule values".

### Pack files

A pack can be a folder or one file, `<id>.larissa`: a zip of the pack's folder in the data form. **Edit a folder, ship a file.** The editors write only to a folder of the project; a pack file is read-only,
and the game reads it where it lies, so nothing is unpacked and a `.larissa` is as good a pack as a folder to hand round, install or ship next to a game. `pack_tool --export-pack` or
`--export-campaign` with `--archive` (or the "one .larissa pack file" box of the editor's export window) makes one. The game checks a pack file before it uses it and refuses what is not
a plain zip of a pack, a path that leaves the pack, an encrypted entry, a file over 64 MB or a pack over 512 MB in all (`engine/PACKS.md`, "Pack files"); a pack that is larger
stays a folder.

### Installing and checking packs

Installed packs live in `user://packs/` (one folder or one `.larissa` file per pack; the project's own are in `res://packs/`). A pack that lives elsewhere can be
symlinked as `godot/packs/<id>` (`res://packs/<id>`); if it is also in `user://packs/<id>` the list shows it once.

1. On the **sign-in screen**, press **P**. The pack screen opens and lists the packs found, the chain in use and why.
2. **Install...** takes a folder or a `.larissa` pack file and copies it into `user://packs/` (a folder as a folder, a pack file as a file); a pack is installed in one form at a time. It refuses an id the project already has in `res://packs/` (that one would always
   win; `dev` too, so a project without a dev takes the one you install). Installing runs nothing and does not change what the game uses.
3. **Check** runs the quick check (the sector checks without the reachability search, and a look that the pack and the packs under it hold every file the game needs) and shows the report. Nothing a pack holds runs, so none asks for trust.
4. **Remove** deletes an installed pack from `user://packs/`, folder or file.
5. To play it, start the game with `--pack=<id>` (an installed pack that names a `base` needs that pack found too).

A small **Packs** button also appears beside the player list, but only once a pack you installed is in `user://packs/` (the `legacy` and `dev` pack files a game carries next to it are no reason). The P key is always there.

The pack tools also work from the editor (Project > Tools > "Export pack...", "Check pack...", "New pack from dev...") and from a terminal; making,
exporting and checking packs is the subject of [`MAKING_CONTENT.md`](MAKING_CONTENT.md). From a terminal:

```sh
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --list                       # the packs found, the chain in use and why
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --check=/path/to/pack_or_id
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --new=orchard --from=dev     # a pack of your own, copied from dev
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --export-pack=orchard --out=/path/out --archive    # a whole pack in the data form
```

---

## 5. Skins

A **skin** is the presentation layer as data. It is a `GameSkin` resource (`res://skins/<id>/skin.tres`) that maps the registry's
names to its own pictures, fonts, shaders and, if it wants, a whole presenter scene. Whatever it does not map falls back to the
original skin, so a skin can be as small as one picture.

### What a skin may change, and may not

| A skin **may** change | A skin **may not** change |
| --- | --- |
| any picture, at any resolution (4x art drawn at a quarter scale is fine) | a hit rectangle, or the walls |
| how things are drawn: shaders, animation, 3D models, lighting | how long a step that holds up play lasts (launch, dock, balloon, dissolve) |
| the HUD's layout and its lettering (font, size, colour) | what happens in a tick: the same sector and the same hands give the same trace |
| the filter and pixel snapping of the window | content: sectors, texts, problem answers (a key that names them is ignored) |
| what plays on screen when the rules report an event (28 events) | the rules' data: tuning, zones, trigger table |

A skin gets copies of the rules' state, not the rules, through a small API (`SimView`). It cannot call `tick`, hold the clock,
write state or read the keyboard. [`SKIN_API.md`](SKIN_API.md) lists exactly what it is given; how skins work in code is
[`SKINS.md`](../engine/SKINS.md).

Because this is tested, you do not have to take it on trust. Every skin in `res://skins/` (and the example skin pack, below) is played against the original skin over
several sectors of the dev pack, switched at run time, and played through a whole mission, and must give the same event trace. A new skin is in
those tests the moment it exists; there is nothing to register.

### Where skins live and which ship

| Skin | Folder | What it shows |
| --- | --- | --- |
| `original` | `res://skins/original/` | maps nothing; the original look. The game cannot run without it, so an export carries it. |
| `creatures` | `res://skins/creatures/` | two species of creature redrawn: a rainbow fish with an animation tree, a 3D puffer fish. A demonstration of what only a project skin can do (3D models and animation trees need real nodes), so an export does not carry it. |
| `modern` | `examples/packs/modern/` | the example skin pack, not a folder of `res://skins/` (below). |

### Choosing a skin

- **On the command line**, after `--`: `tools/godot.sh --path godot -- --skin=creatures`. The id is the folder name, or the pack id of a skin mod of the pack in use (`--pack=`). An unknown id is a
  loud error and gives the original.
- **While playing**, press **F3** (the debug overlay), then **S**: it puts on the next skin. This works only in a debug build; an
  exported release game deletes the overlay. The choice is not saved.
- **In a scene or test**: `SkinChoice.select_id(&"creatures")`.

There is no skin menu for players yet.

### Skins and packs

A skin you give to other people is a **mod pack** (section 3, "Mod packs"): a pack with a script, its pictures in `skin/` and, if it wants, shaders as text. It is code of a stranger in a sandbox, so it can only say what to draw and can change no rule; installing one asks no trust question and it needs the godot-sandbox extension (a skin with no script needs none). `--pack=<id>`
chooses it (it is laid over the game pack it names as its `base`), and then its skin appears in the list of skins with its pack id and works with `--skin=<id>` and F3 + S like a shipped one. It lasts as long as its pack is in use. How to write one is [`SKIN_API.md`](SKIN_API.md), "Writing a skin mod". The skins of the project itself (`original`, `creatures`) are folders of `res://skins/`; an export carries `original` and not `creatures` ("Shipping", section 6). A mod skin's script draws the layers of the sector and of the console it names (or the whole screen) and leaves the rest to the original; the game's layouts (every rectangle), sounds, rules and timings stay as they are, and the pictures, font and theme of its manifest are worn only while the skin is.

**The example pack** is `examples/packs/modern/`: a skin with no script, laid over `legacy`, that you can copy. Its `pack.json` has the `skin` entry of [`SKIN_API.md`](SKIN_API.md) ("A skin with no script"): `render` (linear filter, no snapping), `hud_font` (Exo 2 at weight 600, with its licence `OFL.txt` next to it in `skin/fonts/`), a `theme` (that font and cool blues for the menus: the message box, the dialogs and the sign-in screen, and the problem screen's text, calculator keys and display), two `shaders` put on the layers `background` (the water) and `walls` (kept sharp under the smooth filter) and `pictures`, the console's templates. Those are flat colour at the original's sizes with their key and size written on them, made by `mise run skin:templates --pack legacy`; draw your art over them and keep their sizes. The templates of the problem screen's frame (`skin/problem_art/`) are in the folder too, not mapped. `mise run examples:pack modern [--out <dir>]` writes `modern.larissa` (the legacy pack must be found: it is the pack's `base`), and `mise run examples:install modern` installs the folder into `user://packs/`, so that `tools/godot.sh --path godot -- --pack=modern --skin=modern` plays it (`--pack=` chooses the pack, and its skin is then offered). The two are `mise run pack:archive <folder>` and `mise run pack:install <folder-or-file>` for any pack folder: [`FIRST_SKIN.md`](FIRST_SKIN.md), step 8. The template pictures, the shaders and every key of its manifest are told where they are used: [`SKIN_API.md`](SKIN_API.md), "A skin with no script"; [`FIRST_SKIN.md`](FIRST_SKIN.md) walks through it.

Remember the order in section 4: a pack's picture beats the skin's. If a content pack and a skin both supply a picture, the
content pack's is what you see.

---

## 6. Where things live

### In the project (`res://`, which is `godot/`)

| Path | Holds | In git? |
| --- | --- | --- |
| `godot/packs/dev` | the dev pack: a complete pack of placeholder content, with the engine's test sectors | yes |
| `godot/packs/legacy` | the legacy pack (below) | no |
| `godot/packs/README.md` | says what the folder is | yes |
| `godot/data/sectors/sector_32` and up | **your** sectors (a sector of yours goes here, whichever number is free from 32) | yes, if you commit them |
| `godot/data/sectors/foe_annotations.json` | label names and comments of the creature scripts, also those of the legacy pack's sectors | yes |
| `godot/data/campaigns/<your id>.tres` | your campaigns (and an optional `<id>/` folder: the pack source of what it uses) | yes |
| `godot/data/ui/menu_layout.tres`, `godot/data/closing_crew.tres` | made from the program's code alone, no game content | yes |
| `godot/data/story/` | cutscene timelines (all but `news_cartoon.tres`, which is a complete pack's) | yes |
| `godot/data/rules/durations.json` | the durations (the base layer; the packs' `rules/durations.json` go over it) | yes |
| `godot/data/rules/tuning.json` | the rule values (the base layer; the packs' `rules/tuning.json` go over it) | yes |
| `godot/names/original.json` | the name registry | yes |
| `godot/skins/{original,creatures}/` | the project's skins | yes |
| `examples/packs/modern/` | the example skin pack (a pack folder outside the project; `pack_tool --check` and `--archive-folder` read it) | yes |
| `res://packs/<id>/` | packs that are part of the project, or links to packs that live elsewhere | up to you (`dev`: yes; legacy and links: no) |
| `godot/src/` | all the code | yes |
| `godot/tests/` | tests; `tests/fixtures/*.json` are hashes, `tests/fixtures/original/` is bytes | hashes yes, bytes no |
| `godot/addons/` | the editors (screen editor, sector inspector, Foe Script editor, sector overview, check sector, pack tools) | yes |

### The legacy pack

The legacy pack is the folder `godot/packs/legacy` (`res://packs/legacy`), loose files that the importer writes
([`LEGACY.md`](../play/LEGACY.md), "Where the legacy pack is"). Nothing in it is in git. The dev pack (`godot/packs/dev`) has the same layout, file for file, in its own
content.

| Path in the legacy pack | Holds |
| --- | --- |
| `pack.json` | the manifest (`"id": "legacy"`, no `base`: it is complete) |
| `assets/` | pictures and sounds (`sprites/`, `tiles/`, `backgrounds/`, `ui/`, `problem_art/`, `authoring_tool/`, `audio/`), each with a stub `.import` file |
| `data/sectors/sector_00` ... `sector_31` | the original's sectors 0-31 |
| `data/campaigns/{voyager,expert}.tres` | the original's two campaigns |
| `data/problems/`, `sprite_frames/`, `sprite_meta/` | problem types, text tables, the problem screen's layout (`screen_layout.tres`) and art index (`problem_art_index.json`), creature and deco frames, hit rectangles |
| `data/zones.tres`, `trigger_table.tres`, `neptune_tileset.tres`, `bubble_rules.tres` | the rules' tables and the tile set |
| `data/{sfx,music}_catalog.tres`, `voice_index.tres`, `voice_cues.tres` | what the sounds and speech groups are |
| `data/ui/{hud,calculator,story}_layout.tres`, `data/story/news_cartoon.tres` | interface layout and the news cartoon |
| `midi/` | the original MIDI files, for music from MIDI |

The game lists sectors and campaigns from the whole chain and from the project (`Catalog`): a pack's are in the pack, the ones you make with the editors in `godot/data/`.

### In your user folder (`user://`)

`user://` is the writable folder Godot makes for this project. The project name is `Operation Larissa` and the project does not set a custom
folder, so it is:

| System | Folder |
| --- | --- |
| Linux | `~/.local/share/godot/app_userdata/Operation Larissa/` |
| Linux, Godot from Flatpak (not supported) | `~/.var/app/org.godotengine.Godot/data/godot/app_userdata/Operation Larissa/` |
| Windows | `%APPDATA%\Godot\app_userdata\Operation Larissa\` |
| macOS | `~/Library/Application Support/Godot/app_userdata/Operation Larissa/` |

In the Godot editor, **Project > Open User Data Folder** opens it.

| File or folder | Holds |
| --- | --- |
| `packs/` | installed packs: `<id>/` folders and `<id>.larissa` files (the pack files a game carries next to it are not here) |
| `roster.json` | the players, with their campaign and progress |
| `hall_of_fame.json` | the Hall of Fame |
| `machine_settings.cfg` | `[ONWINCD] Collision=` |
| `audio_settings.cfg` | volumes, the music set, the optional soundfont |
| `midi/` | your own MIDI files (optional, for music from MIDI) |
| `pack_exports/` | where the pack tool puts an export unless you say otherwise |

Delete `roster.json` to wipe the players. Delete `packs/` to remove every installed pack.

### In the repository root, outside `godot/`

| Path | Holds | In git? |
| --- | --- | --- |
| `NEPTUNE.ISO` | your CD image | **never** |
| `extracted/` | what the first import step pulls from the ISO | **never** |
| `docs/data/` | facts read from the program's code (committed), and seven tables dumped from the ISO (`sectors.json`, `problem_records.json`, `problem_tables_raw.json`, `problem_gfx_bundles.json`, `trigger_table.json`, `zone_defaults.json`, `onwin_map.json`; not committed) | mostly |
| `soundfonts/` | optional `.sf2` files for rendering or playing music | no |
| `godot/tests/fixtures/original/` | the original bytes, written by the importer, for the fidelity tests | no |
| `godot/data/legacy/` | your hand corrections of the speech transcripts | no |
| `tools/` | the importer, extractors, Python tests, `godot.sh` | yes |

### What is committed, and what is never committed, and why

The rule is one sentence: **the repository holds code, tools, hand-made data and hashes. The game's content belongs to your copy
of the game.**

- **Never committed:** anything that is a picture, sound, text, level, creature script or problem of the original game
  (the legacy pack, `godot/packs/legacy`, and a `legacy.larissa` made from it; `extracted/`, the seven `docs/data` tables, the original bytes). All of it is regenerated by
  the importer from your ISO. This is **provenance**: every file can be traced to a file, a resource id and an offset on the CD,
  and nothing in the repository carries the original's content to someone who does not own it.
- **Committed instead of the bytes:** *hashes*. A fixture holds the file, bundle and offset and a SHA-256 of each whole record. The
  tests compare your import against the hashes, so a different release or a patched copy is caught instead of compared with
  itself. A hash of a whole record cannot be reversed to the record.
- **Committed:** the code; the importer and its tables of *facts about the program*; the name registry; the durations; the cutscene
  timelines and the few resources made from the program's code alone; the dev pack and its generator (`tools/dev_pack/`), which hold nothing of the
  original; skins that hold no original art; your own sectors, campaigns and packs.
- **Because of that:** a change to a generated file is never committed. To change the game's content, change the tools, or make a
  sector or campaign of your own (sector 32 and up) and keep that. Editing sector 5 in `godot/packs/legacy/data/sectors/sector_05/` changes only your
  machine, and a full re-import will overwrite it (use `tools/import/reset_screens.py` and its siblings to go back deliberately; see
  [`LEGACY.md`](../play/LEGACY.md) and [`SCREEN_EDITOR.md`](SCREEN_EDITOR.md)).
- **Shipping.** An exported game carries the original skin and no other of `res://skins/` (`PackExportFilter`, and `skins/creatures/*` in the presets' exclude filter; a skin for players is a skin pack), and no pack: `godot/export_presets.cfg` excludes `packs/dev/*` and `packs/legacy/*` from the Linux, Windows
  Desktop and Web presets, and the pack tools' export plugin skips every other folder of `res://packs/` too, so a build never carries your copy of
  the game or a pack you are working on. A pack reaches a game as a pack file next to the executable (`legacy.larissa`, `dev.larissa`: `pack_tool --export-pack=<id> --archive`
  makes one in the data form), which the game reads where it lies (an installed folder of the same id is used instead, "Where packs are found"). Two downloads follow from it:
  - **The player download** is a release binary and nothing else. It refuses to play until a pack is found: you make `legacy.larissa` yourself
    (`tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --export-pack=legacy --archive --out=<folder of the executable>`;
    [`LEGACY.md`](../play/LEGACY.md), "Playing legacy in an exported game"). The importer never makes a pack file, and the pack file is yours: it is not
    shared or committed.
  - **The creator download** is a debug binary and `dev.larissa` next to the executable (`pack_tool --export-pack=dev --archive`): the dev pack in the data form. With
    it a debug build opens on the warning screen and plays `dev_tour`, and a pack laid over `dev` has its base. `dev` can also be installed from the pack screen
    or `pack_tool --install=dev.larissa`.
  - **The Web build** preloads `dev.larissa` and `legacy.larissa` when they sit next to `index.html` (the shell `godot/export/web_shell.html`, the Web
    preset's custom HTML shell; a missing file is skipped). The deployer puts them there. Hosting `legacy.larissa` where the public can fetch it
    redistributes the original game's content, so do that only for a private or self-hosted deployment.
- **Copies of originals** hold the original's bytes, so keep them out of git, or
  build your campaign from sectors made with the Empty template of "New sector...", which holds nothing of the original.

---

## 7. Glossary

| Word | Meaning |
| --- | --- |
| **ISO** | the CD image of the 1998 Windows release. You supply it; it is never in git. |
| **Importer** | `tools/import/import_all.py`, which builds the legacy pack from the ISO. |
| **Pack** | content with a manifest, a folder or a pack file. The game uses one chosen pack and the chain of packs under it. |
| **legacy** | the original game as a complete pack, made by the importer into `godot/packs/legacy` (`res://packs/legacy`). A pack like any other. |
| **dev** | the pack of placeholder content: a complete pack, the engine tests' pack, the fallback under a chain that is not whole in a debug build; the folder `res://packs/dev`, else a dev installed in `user://packs/`, else the bundled `dev.larissa`. The id is reserved. |
| **Complete pack** | a pack with no `base`: it holds everything a game is made of. |
| **Base** | the pack another pack is laid over (`"base": "<id>"` in its manifest). A thing is looked up in the chosen pack, then its base, and so on. |
| **Chain** | the chosen pack and the packs under it, `Packs.chain()`. `--pack=<id>` chooses; without it, the first pack found by id. |
| **Data form** | a pack outside the project (`user://packs/`) holds JSON, `.foe`, PNG, OGG, WAV and MIDI only, so installing it runs nothing; a pack in the project (`res://packs/`) holds the same content as `.tres` files. |
| **Pack file** | a pack as one file to hand round or ship next to a game: `<id>.larissa`, a zip archive of the pack's folder (`pack_tool --export-pack=<id> --archive`), read in place by the game and read-only; installing it copies the file into `user://packs/`. |
| **Manifest** | `pack.json`: the pack's id, title, version and optional base and mod. |
| **Mod pack** | a pack whose manifest has a `mod` entry: a SafeGDScript (`.sgd`) run by godot-sandbox with restrictions, reaching only what the game grants it. |
| **Sector** | one level: 12 screens, a header, pieces, creatures, one creature script. Numbered 0-255; the packs of the chain share the number space (the nearest wins). |
| **Screen** | one of a sector's 12 flip-screens. |
| **Zone** | one of 7 art and difficulty groupings (5 normal, 2 finale). |
| **Piece** | a capsule you collect. Piece 0 is the data canister. |
| **Trigger** | an invisible spot on a screen that starts a math problem. |
| **Foe** | the code's word for a creature. |
| **Foe script** | a sector's `.foe` text: the programs the creatures run. |
| **Problem type** | one of 34 kinds of math problem. |
| **Campaign** | a whole game: an ordered list of sectors, finales, logs, messages. |
| **Finale** | a sector whose end is the end of the game. |
| **Generic finale** | the closing a campaign gets when it has no closing of its own. |
| **Tick** | one step of the rules: 1/12.17 of a second. The 73 Hz timer ticks used for lengths are about six times shorter. |
| **Registry** | `godot/names/original.json`: friendly names for the original's numbers. |
| **Skin** | presentation as data: pictures, fonts, shaders, a presenter. Changes nothing about play. |
| **Presenter** | the scene that draws a sector from the rules' state. A skin may bring one. |
| **Skin key** | `<kind>/<name>` such as `frame/dolphin_swim_0`: how a skin or a pack names a picture. |
| **Fidelity** | the property that the port plays like the original, which the tests check. |
| **The fork** | a change to an existing rule. It would end this codebase and start another. |
| **User folder** | `user://`: where saves, settings and installed packs live. |
