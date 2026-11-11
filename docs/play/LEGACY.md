# Making the original game from your copy - a manual

This git repository holds the Larissa engine code, but it has nothing from the original game -- no art, levels, etc.  If you
own a copy of the original game (usually `NEPTUNE.ISO`), we provide tools that can extract it into a "content pack" file that
this engine can play.

## Quick start: from a clone to playing

When you're done, you'll have three files in `game/build/`:
- The game engine executable `operation-larissa.x86_64`.
- A `legacy.larissa` content pack.
- A `.so` file which allows the engine to play mods.  This file is not needed if you're only playing content packs like
 `legacy.larissa`.

The author uses Fedora Linux, so this is the only system where the tools are fully tested.  (Help wanted!)

On Windows, the steps to build the legacy pack and play it in the editor's Godot are in
[`../SETUP.md`](../SETUP.md), "On Windows: build the original game and play it"; the exported build below is Linux-only. Where this
manual writes `tools/godot.sh <arguments>`, Windows runs `uv run tools/godot.py <arguments>`.

1. Install the system programs that you'll need:

   Fedora:
   ```sh
   sudo dnf install git ffmpeg-free fluidsynth fluid-soundfont-common fluid-soundfont-gm
   ```

   Arch (untested!):
   ```sh
   sudo pacman -S git ffmpeg fluidsynth soundfont-fluid
   ```

   Debian Trixie (untested!):
   ```sh
   sudo apt install git ffmpeg fluidsynth fluid-soundfont-gm
   ```

2. Install [mise](https://mise.jdx.dev/installing-mise.html), which fetches the exact versions of Godot, uv, and Python that
   this project uses (activating mise in your shell is optional):

   Fedora:
   ```sh
   sudo dnf copr enable jdxcode/mise && sudo dnf install mise
   ```

   Other Linux:
   ```sh
   curl -fsSL https://mise.run | sh
   ```


3. Clone this repository and allow mise to use its `mise.toml`:

   ```sh
   git clone https://github.com/mwinters0/operation-larissa.git
   cd operation-larissa
   mise trust
   ```

4. Put your copy of the game in the root of the repo (see "The ISO" below for which copies work):

   ```sh
   cp /path/to/your/copy.iso NEPTUNE.ISO
   ```

5. Build the legacy content pack from `NEPTUNE.ISO`:

   ```sh
   mise run legacy:import
   ```

   The first time this runs it will need to download a 480 MB speech model, which is needed to convert some of the original
   audio dialogue to text. Aside from the download, the actual import takes about 10 minutes.

6. Build the game:

   ```sh
   mise run release:build_linux
   ```

   This runs several more `mise` steps for you, as needed:
   - `mise install` - installs the pinned tools
   - `setup` - creates the Python environment
   - `godot:fetch_templates` - downloads Godot's export templates (1.3 GB, kept in Godot's own folder), which is what lets it
     produce an executable.
   - `godot:pack legacy` - writes `legacy.larissa` (the original game pack); without a legacy pack it stops and says so.

   Then it exports everything to `build/game/`.

   You can move these files to wherever you like, or play the game right there.  The engine looks for content packs in the
   directory where the executable is, and also in Godot's `user://packs` directory.  (See [Godot's docs on the `user://`
   location.](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html#accessing-persistent-user-data-user))

   If you run this step again, it skips the download and writes the game executable and `legacy.larissa` again
   over the ones in `build/game/`.

To build the pack again after an update of the repository, run `mise run legacy:import`, then `mise run release:build_linux`, which
replaces the game and `legacy.larissa` in `build/game/`.


## What the legacy pack is

The legacy pack is the original game as content: the pictures, sounds, speech, music, sectors, creature scripts, math problems and
campaigns that the importer writes from your ISO as loose files into a folder of its own in the project: `godot/packs/legacy`
(`res://packs/legacy/`; see "Where the legacy pack is"). It is a *complete pack*, a pack like any other: the engine has no special case
for it, and the game plays it the way it plays any pack you choose with `--pack=legacy` (or by itself, when it is the only pack found).
Other packs can be laid over it. How packs, layers, campaigns and skins fit together is in [CONTENT.md](../create/CONTENT.md); you need
none of that to build it.

It is not in git because it is not ours: it is the original's artwork, recordings and data. The folder `godot/packs/legacy` is
git-ignored (`.gitignore` ignores all of `godot/packs/` but its README and the dev pack), so nothing of it can be committed by accident.
Only hashes of it are committed (the hash fixtures in `godot/tests/fixtures/`, `tools/import/source_files.json`), which is how the tools
know that your copy is the right one. A change to a file the importer makes is never committed: to change the game's content, change the
tools, or make a sector or campaign of your own ([MAKING_CONTENT.md](../create/MAKING_CONTENT.md)).

Without the legacy pack the project still opens in Godot and the Python tools still run, and the engine's tests pass; the game opens on
a warning screen saying that no pack was found and that the dev pack, which is not meant for play, is all there is, and plays `dev_tour`, the
placeholder game of the `dev` pack (a debug build with `dev.larissa` beside it, or the editor; a release build refuses to play and says to build the content with the importer). Only the tests of the original game have nothing to check (see "Check the result").

## What you need

The tools are in [SETUP.md](../SETUP.md). The importer checks them before it starts and refuses, listing what is missing and how to
get it, before it writes anything ("Troubleshooting"). Beyond them you need your copy of the game, and optionally a second soundfont.

### The ISO

The importer reads a CD image of the 1998 Windows CD-ROM release of Operation Neptune (the copies on the Internet Archive are of this
release). It does not look at the image as a whole: it hashes 31 files of the CD's `ONWINCD/` folder (the programs `ONWIN32.EXE` and
`ONWIN.EXE`, the resource DLLs `NEP.DLL`, `NEP256.DLL`, `NEPBG1.DLL`, `NEPBG2.DLL`, `NE0SOUND.DLL`, `NE1SOUND.DLL`, `NE2SOUND.DLL`, the
20 MIDI files in `SOUNDS/`, and a few small ones) and compares size and SHA-256 with the table in `tools/import/source_files.json`. Four
more files in that folder are not checked, because nothing is made from them (`HALLFAME.DAT` and `ONUSERS.DAT`, which are empty, the
setup file `ONWINCD.INI` and its backup `ONWINCD.BAK`), and nothing outside `ONWINCD/` is looked at (the CD's `ASSETS/` and `MOVIES/`
hold the promotional content of other titles). So any image of that release whose game files are the same passes. A different release,
a patched game or a damaged image does not.

The tools find the image like this (`tools/gamefiles.py`):

1. the file named by the environment variable `NEP_ISO`, if it is set;
2. else `NEPTUNE.ISO` in the repository root.

A symlink works. Use an absolute path in `NEP_ISO`: a relative one is read from wherever you run the command. Nothing is
unpacked to a folder: the tools read files straight out of the image.

```sh
cp /path/to/your/copy.iso NEPTUNE.ISO          # or: export NEP_ISO=/path/to/your/copy.iso
uv run tools/gamefiles.py ls ONWINCD           # lists the CD's game folder: proves the tools can read the image
uv run tools/import/source_files.py            # is it the right release? "your copy is the reference release (31 files)"
```

`NEPTUNE.ISO` is in `.gitignore`.

### Soundfonts

The game's music is 20 MIDI files on the CD in two sets: `E*.MID` for General MIDI and `B*.MID` for the AdLib sound card. The
importer renders both to OGG with FluidSynth and a soundfont.

- The General MIDI set uses `/usr/share/soundfonts/FluidR3_GM.sf2` unless you pass `--soundfont PATH`.
- The AdLib set uses `soundfonts/opl.sf2` (an OPL3 imitation, 135 MB; put it in `soundfonts/` in the repository, which is
  git-ignored) unless you pass `--adlib-soundfont PATH`.
- If `soundfonts/opl.sf2` is not there, the AdLib set is rendered with the General MIDI soundfont instead. The legacy pack is then
  complete, the importer prints a note saying so, and the AdLib songs just sound like General MIDI. Add the soundfont later
  and run the `audio` step again.

To hear the music through another soundfont, render it again or let the game play the MIDI files itself: see "Music with another
soundfont".

## Make it

1. Set up the tools ([SETUP.md](../SETUP.md)), put the ISO in place and check it (see "The ISO").
2. Run the importer from the repository root:

   ```sh
   uv run tools/import/import_all.py
   ```

   Before the first step it makes the legacy pack's folder `godot/packs/legacy` and its `pack.json` (and prints what it did).
   Then it prints `step <name>` for each step, and a few lines for each. It ends with the number of files written and unchanged,
   then the `godot` step, Godot's import (below).
3. Start the game (see "Playing"):

   ```sh
   tools/godot.sh --path godot
   ```

If something is refused, the importer says `REFUSED, nothing was read or written: ...` before any step runs: see
"Troubleshooting".

### What the importer does

First it checks the ISO against `source_files.json`. Then it checks the programs the chosen steps need: it refuses when one is
missing and warns loudly when one is not the version the project pins (Godot, the speech engine), before any step writes anything.
Then it makes the legacy pack's folder and its `pack.json` (below, "Where the legacy pack is"), and runs the steps in this order. Later steps read files the earlier ones wrote.

| Step | What it makes |
|---|---|
| `extract` | Unpacks pictures, sounds, MIDI, text and data resources from the ISO into `extracted/` (the three extractors `extract_images.py`, `extract_sounds.py`, `extract_data.py` in `tools/extract/`, and the contact sheets of `make_sheets.py`, printed with their times). `tools/extract/run_all.sh` runs the same scripts alone, and also `extract_previews.py` (the promotional content of other titles), which the importer leaves out. |
| `tables` | Dumps the game's data tables to seven JSON files in `docs/data/` (`sectors`, `problem_records`, `problem_tables_raw`, `problem_gfx_bundles`, `trigger_table`, `zone_defaults`, and `onwin_map`, the names of ONWIN.MAP that the Ghidra tools resolve; by `tools/analysis/export_json.py`, `decode_problems.py`, `export_gfx_tbl.py` and `ghidra/map_names.py`). |
| `images` | The legacy pack's `assets/backgrounds/`, `ui/`, `problem_art/`, `authoring_tool/`. |
| `tiles` | `assets/tiles/` (zone atlases, currents) and `data/neptune_tileset.tres`, in the pack. |
| `sprites` | `assets/sprites/`, `data/sprite_frames/`, `sprite_meta/`, `bubble_rules.tres` in the pack; `godot/data/closing_crew.tres` in the project (committed); the `sprite_meta.json` hash fixture. |
| `sectors` | The 32 original sectors in the pack's `data/sectors/sector_00..31/` (header, creature script, 12 screens each), `zones.tres`, `trigger_table.tres`, the original bytes behind the fixtures (below) and their hash fixtures (`screens.json`, `foe_scripts.json`, `foe_records.json`, `sector_headers.json`, `trigger_table.json`, `zones.json`). |
| `problems` | The pack's `data/problems/` (the 34 problem types and their text tables), the problem pictures, and the `problem_tables.json` hash fixture. |
| `console` | The pack's `data/ui/` (HUD, calculator and story layouts); the menu layout is the project's `godot/data/ui/menu_layout.tres` (committed). |
| `story` | The pack's `data/story/news_cartoon.tres`; the other cutscene timelines are the project's `godot/data/story/` (committed). |
| `campaigns` | The pack's `data/campaigns/voyager.tres` and `expert.tres`. |
| `transcripts` | Turns the 423 voice clips into text: see "Voice transcripts". Writes `extracted/sounds/voice_transcripts.json` and `voice_transcripts_machine.json`. |
| `audio` | The 52 sound effects and 371 speech clips (`assets/audio/`), the music rendered from MIDI (both sets), the catalogs (`sfx_catalog`, `music_catalog`, `voice_index`, `voice_cues`), and a copy of the MIDI files in the pack's `midi/`. The speech text in `voice_index.tres` comes from the transcripts; after a run without them the clips have no text. |
| `godot` | Always last. Has Godot import the project (below, "The Godot import"). Needs Godot. |

Between the `audio` step and `godot`, the importer also removes asset files that an earlier run wrote under an old name
(`stale asset files removed: N`), writes a stub `.import` file with a stable uid beside every picture and sound, and writes the
asset manifest (`tools/import/asset_manifest.json`: for each file under the pack's `assets/` its source file, resource id, offset
and conversion; [ASSET_FORMATS.md](../port/ASSET_FORMATS.md)).

The importer names each asset `<name>_<number>` when the name registry (`godot/names/original.json`) has a name for it
(`lock_tick_38.wav`: the name, then the original's number), and `<kind>_<number>` otherwise (`sfx_28.wav`). When a name changes in the
registry, the next import writes the file under its new name and removes the old one ([NAMES.md](../create/NAMES.md), "Asset file names").

Files are only rewritten when their content changes. The last lines of a run say how many were written and how many were
unchanged.

### The options

```
uv run tools/import/import_all.py [--only STEPS] [--clean] [--validate]
                                  [--soundfont PATH] [--adlib-soundfont PATH]
                                  [--no-transcripts] [--compute-type int8|float32]
```

| Option | What it does |
|---|---|
| `--only a,b,c` | Runs only those steps, always in the order of the table above (the pipeline order), whatever order you write them in, because later steps read what earlier ones wrote. A step named twice runs once. An unknown name is an error. `godot` runs last. |
| `--clean` | Before each selected step runs, deletes the files and folders that step owns (for example the `tiles` step's `assets/tiles/` in the legacy pack). `extract`, `tables`, `transcripts` and `godot` own nothing and are never cleaned. For `sectors` and `campaigns` it deletes only the original's files (`sector_00..31`, `voyager.tres`, `expert.tres`), never a sector or campaign of your own. |
| `--validate` | After the run, cross-checks the generated tree and prints `validation OK`, or `VALIDATION FAILED:` with what is wrong. Needs no Godot. |
| `--soundfont PATH` | General MIDI soundfont for the `E*.MID` songs. Default `/usr/share/soundfonts/FluidR3_GM.sf2` (on Windows `soundfonts\FluidR3_GM.sf2`). |
| `--adlib-soundfont PATH` | Soundfont for the AdLib `B*.MID` songs. Default `soundfonts/opl.sf2`; falls back to the General MIDI soundfont when that file is missing. |
| `--no-transcripts` | Leaves out the `transcripts` step: no speech engine needed, no model download, and the run takes a minute or two instead of about 10. The voice clips then have no text ("Voice transcripts"). |
| `--compute-type int8\|float32` | For the `transcripts` step. `int8` is the default; the environment variable `NEP_WHISPER_COMPUTE` does the same. |

The importer returns 1 when the ISO is missing or is not the reference release, when a program a step needs is missing, or when a
downloaded model file is not the pinned one (it says `REFUSED`), and when `--validate` finds something wrong. It does not return 1 when clips differ from the transcript fixture; it
only reports them.

After a run with `--only` that leaves out `godot`, the importer prints the command it would have run for you:

```sh
tools/godot.sh --headless --path godot --import        # Godot fills in the rest of the .import files
```

### The Godot import

Godot has to import the new pictures and sounds before anything can load them. The importer already wrote a stub `.import` file
for each asset (`tools/import/import_uids.py`), with a uid worked out from the file's path (a hash, written the way Godot writes one);
Godot completes the stubs and keeps the uid. Because the uid depends only on the path, the same ISO gives the same uids in every
checkout, so a scene that refers to an asset by `uid://...` (the tileset does) keeps working.

The `godot` step runs that import. The tool check has already found Godot; if the import still fails, the step says
`Godot could not be started (...)` or prints Godot's output, then `the Godot import was not done. By hand:` with the command above.
Everything else is already made; run that command when Godot works.

## Run it again

The importer is deterministic: the same ISO gives the same bytes. A second full run on the same ISO changes nothing: the
importer only writes a file whose content differs, the summary line (`files written: N, unchanged: M`) counts the files that
did, and `git status` stays clean. Do not run it just to check: it costs the full 10 minutes, because the transcripts are
made again.

For a partial run, name the steps (`extract`, `tables`, `images`, `tiles`, `sprites`, `sectors`, `problems`, `console`, `story`,
`campaigns`, `transcripts`, `audio`, `godot`). Examples:

```sh
uv run tools/import/import_all.py --only audio --adlib-soundfont soundfonts/opl.sf2   # render the AdLib music again
uv run tools/import/import_all.py --only transcripts                                   # transcripts only, compare with the fixture
uv run tools/import/import_all.py --only images,tiles --validate                       # pictures only, then cross-check
uv run tools/import/import_all.py --clean --only tiles                                 # delete the tiles output first
```

Three things to know before a partial run:

- **The `sectors` step overwrites your edits.** The creature scripts (`sector_NN.foe`), the screens (`screen_MM.tres`) and the
  sector headers in the legacy pack's `data/sectors/sector_00..31/` are the stored version that designers edit, so a run of `sectors`
  (or a full run) writes the originals over your changes. Label names and comments you stored in the project's
  `godot/data/sectors/foe_annotations.json` are kept and written back. To put back only some things, use the reset tools (below) instead.
- **`audio` takes its speech text from `transcripts`.** The speech text in `voice_index.tres` comes from
  `extracted/sounds/voice_transcripts.json`, which the `transcripts` step writes; without that file the clips have no text. In a fresh
  checkout run both: `--only extract,transcripts,audio`. Likewise `transcripts` needs `extract` (it says `N clips are missing in ...: run
  tools/extract/extract_sounds.py first` otherwise).
- **Music is re-rendered only when it must be**: see "Music with another soundfont".

After any partial run, let Godot import the changes: `tools/godot.sh --headless --path godot --import`.

## Voice transcripts

The `transcripts` step turns the 423 sound clips (371 speech, 52 effects) into text with a speech model (Whisper `small.en`,
run by `faster-whisper`). The text is the game's speech, so it is not committed. Nothing the game plays reads it: it feeds the sound
test's list (`src/debug/sound_test.gd`), the `Audio` cue log and the tests that check which clip says what. It takes most of the 10
minutes, so `--no-transcripts` leaves it out; then the clips have no text, the sound test shows none, and those tests
(`godot/tests/legacy/test_voice_cues_legacy.gd`, `tools/import/test_audio.py`) skip.

**It is meant to give the same text on every machine.** Everything that could change it is pinned: the `faster-whisper` and
`ctranslate2` versions (`uv.lock`), the model by Hugging Face revision, with the SHA-256 of every model file (the weights
included) checked before it is loaded and nothing newer ever fetched, greedy decoding at temperature 0 with no fallback, the
CPU, and 4 threads. Other `faster-whisper` or `ctranslate2` versions get a warning and the step runs with them; their text may differ
from the fixture.

**The fixture holds hashes only.** `godot/tests/fixtures/voice_transcripts.json` is committed. It holds one SHA-256 per clip
transcript, plus the engine settings and which compute type the hashes are for, and no text. The step transcribes every clip,
hashes the text and compares. You see one of:

```
  all 423 transcripts match the fixture
```

or a line per clip that is not right, and a summary:

```
  DIFFERS from the fixture: NE1SOUND_4123
  NOT in the fixture: ...                      (the clip has no hash in the fixture)
  in the fixture but not transcribed: ...
  1 of 423 transcripts differ from the fixture (0 new, 0 missing)
```

"DIFFERS from the fixture" means that on your machine the model produced a different text for that clip than the machine that
made the fixture did. The importer carries on and uses your text; the step does not fail. What can break is anything that
depends on the exact words, such as the checks in `godot/tests/legacy/test_voice_cues_legacy.gd`. If a line `note: engine setting
'compute_type' differs from the fixture's` appears above the differing clips, you chose another compute type than the fixture's, and
differences are to be expected.

**int8 or float32.** The default compute type is `int8`: fastest, and what the fixture is for. Its CPU kernels are chosen by
instruction set when it runs (AVX2, AVX-512 ...), and a different CPU could in principle round differently and change a
transcript. If the step reports clips that differ and you did not change anything, run it with `float32` (slower, no such
kernels) and see whether they agree:

```sh
uv run tools/import/import_all.py --only transcripts --compute-type float32
NEP_WHISPER_COMPUTE=float32 uv run tools/import/import_all.py --only transcripts       # the same
```

The two compute types give different text for about 8 % of the clips, so running `float32` against the `int8` fixture will
itself report differences; the question is only whether the *int8* run on your machine agrees with the fixture. int8 is verified
on one machine only (an AMD CPU with AVX-512; forcing CTranslate2 down to AVX2 with `CT2_FORCE_CPU_ISA=AVX2` gives identical text for
all 423 clips). Do not move the reference (`transcripts.py --write-fixture`) to make a message go away; that changes the project's
fixture for everyone.

**Hand corrections.** The machine is sometimes wrong: `NE1SOUND_4244` and `NE0SOUND_8037`, for instance, transcribe as long runs of
letters. You correct one clip with:

```sh
uv run tools/import/transcripts.py --correct NE1SOUND_4244 "Aaah!"
```

This needs the machine transcripts, so run the `transcripts` step once first. It writes `godot/data/legacy/voice_corrections.json`
(or `$NEP_LEGACY/voice_corrections.json`; `LEGACY_AREA` in `tools/import/common.py`), keyed by clip and by the hash of the machine
text the correction corrects. The file is yours and git-ignored, because a correction is the game's speech too. After adding
corrections, run `uv run tools/import/import_all.py --only transcripts,audio` so the corrected text reaches `voice_index.tres`.

A correction is used only while the machine text it was made for is unchanged. If it changes (another model, another setting)
the correction is **stale**: the step prints

```
  STALE correction NE1SOUND_4244: the machine transcript it corrects has changed, the correction is NOT used (set it again with --correct, or delete it from ...)
```

and uses the machine text. Set it again with `--correct`, or delete the entry from the file. A correction for a clip name that
does not exist is ignored with `correction for unknown clip ... ignored`. The step ends with `hand corrections: N used, N stale,
N unknown`.

The result, with corrections applied, is `extracted/sounds/voice_transcripts.json`, beside `voice_transcripts_machine.json`
(without them).

## Music with another soundfont

### Rendering it again

The importer renders the songs once, with the soundfonts of "Soundfonts". To hear them through another `.sf2`, render them again:

```sh
uv run tools/import/import_all.py --only audio --soundfont path/to/your.sf2          # the General MIDI set
uv run tools/import/import_all.py --only audio --adlib-soundfont path/to/your.sf2    # the AdLib set
```

Each rendered set has a `rendered_with.json` beside its OGG files that records the soundfont (its name and hash) and the hash of each
MIDI file. A song is rendered again only when one of those changed or the OGG is missing; a song that only got a new name is moved to
it, not rendered again. FluidSynth does not give identical samples on every run, so a re-render changes the OGG files a little even
with the same soundfont. To go back to the standard renders, delete `assets/audio/music` in the legacy pack and run the `audio` step
with the default soundfont.

### Playing the MIDI files through a soundfont at runtime

The game can also play the MIDI files itself, through any `.sf2`, with nothing to re-import. It is off by default:

```sh
tools/godot.sh --path godot -- --soundfont=/path/to/your.sf2     # or the project setting neptune/audio/soundfont
```

The game saves the choice in `user://audio_settings.cfg` (`[music] soundfont`). It needs the original songs in the legacy pack's
`midi/` (the importer copies them there) or in `user://midi/` (your own MIDI files, looked up by the same names). A song with no
usable soundfont or MIDI file plays from its OGG. Use a small soundfont (a few tens of MB) for the Web export: a large one costs a few
hundred MB of memory. How it works, what it costs and how it sounds different from the renders: [AUDIO.md](../engine/AUDIO.md),
"Music from MIDI at runtime".

## Playing

```sh
tools/godot.sh --path godot                                    # the game
tools/godot.sh --path godot -- --pack=legacy                   # the same, when other packs are installed too
tools/godot.sh --path godot res://src/debug/sector_viewer.tscn # a single scene
tools/godot.sh --editor --path godot                           # the Godot editor on the project
```

The game opens with the opening cartoon, then the sign-in screen. Choose or add a player (Insert = New, Ctrl+R or Delete = remove,
Enter = Start; P opens the pack screen), the sub drives out of the supply station and the mission begins: collect every piece, dock at
the end station on the last screen and open the combination lock (Space, Enter or a click stops the outer wheel while the right number
is under the arrow). After sector 14 (29 for Expert) comes the finale sector: take the Substance X (the Alien Artifact) and swim to the
closing screen. The players are saved in `user://roster.json` and the hall of fame in `user://hall_of_fame.json` (the user folder is in
the table of "Playing legacy in an exported game"). `res://src/gameplay/game.tscn` started alone (F6 in the editor) is free play and never
saves.

Controls: the arrow keys or WASD steer, Space fires ink, Enter opens a waiting math problem, Esc asks to leave, F10 opens the menu,
Alt+Enter toggles fullscreen. F3 shows the debug overlay (a read-out, the row of piece boxes, and cheats: 8 jumps to the finale
sector, 0 completes the sector).

## Check the result

Let Godot import (the full run did it for you): `tools/godot.sh --headless --path godot --import`. Then start the game: the opening
cartoon should play. To check the import itself, run the tests of the original game:

```sh
tools/run_tests.sh legacy                 # the gdUnit4 tests of the original game, on the legacy pack
uv run pytest tools -m legacy             # the importer's own tests
```

Both should pass. The legacy group (`godot/tests/legacy/`: the fidelity hashes, the original's numbers and texts, whole Voyager and
Expert runs) is the one that checks your import: without `godot/packs/legacy` it says so and passes, so read its line.
Reports go to `godot/reports/`. The other suites, the test helpers and how to run one file are in
[DEVELOPING.md](../engine/DEVELOPING.md).

### The messages that say the legacy pack is missing

- The **game** does not say it: with no legacy pack it opens on the warning screen, which names the reason (no pack was found, or there is no pack
  `legacy` when you asked for it with `--pack=legacy`). A debug build then plays on dev (or on whatever other pack is found, dev under it); a release build
  refuses to play and tells you to run the importer.
  `pack_tool --list` prints the packs found and the chain in use.
- `tools/run_tests.sh` prints `== legacy headless: skipped: the legacy pack (the original game) is not here: run the importer on your
  copy of the game ...` for the legacy group when `packs/legacy/data/sectors/sector_00/sector_00.tres` or `packs/legacy/data/zones.tres`
  is missing (this is also what you see when the importer has not run), and the script still exits 0.
- Inside the legacy group a test that needs more than that skips with `run the importer on your copy of the game`, and the Python tests
  with the marker `@pytest.mark.legacy`; the Python check also wants the seven `docs/data/` tables and
  `extracted/sounds/voice_transcripts.json`, and says which file is missing first. The legacy test helper checks 17 files, spread over
  the importer's steps (`LegacyPack.WITNESSES` in `godot/tests/legacy/legacy_pack.gd`); a small number missing (one of the
  `res://packs/legacy/assets/tiles/` pictures, say) usually means a step did not finish, a large one that the importer has not run.

Skips are not failures. But if you have run the importer and still see them, a step did not finish: read the importer's output
from the top.

## Playing legacy in an exported game

The exported game (the presets Linux, Windows Desktop and Web of `godot/export_presets.cfg`) carries no pack: neither your copy of the game nor
the dev pack nor a pack of your own from `godot/packs/<id>/`. A release build with no pack refuses to play; a debug build needs `dev.larissa`
([`CONTENT.md`](../create/CONTENT.md), "Shipping"). To play the original in it you put the legacy pack next to the game as a pack file, `legacy.larissa`, which the game
reads where it lies: nothing is unpacked. The importer never makes the pack file and this
repository never ships one: you make it from your own legacy pack, on your own machine.

`mise run release:build_linux` does steps 2 and 3 below for Linux (`release:build_web` for the Web) ("Quick start"). By hand:

1. Make the legacy pack (sections above). The pack file is made from the folder; it needs no import and no export templates.
2. Export the game itself with Godot's export templates (`mise run godot:fetch_templates` fetches them, or Editor > Manage Export Templates),
   `tools/godot.sh --headless --path godot --export-release "Linux" <where>`; [DEVELOPING.md](../engine/DEVELOPING.md) has the presets.
3. Make the pack file, in the data form (nothing in it is a `.tres`, a scene or a script), into the folder of the exported game's executable:

   ```sh
   mise run godot:pack legacy --out <folder of the executable>     # writes legacy.larissa there (default: the current directory); --version <v> sets the manifest's version
   # without mise, from the repository root:
   tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --export-pack=legacy --archive --out=<folder of the executable>
   ```

   That checks the pack first (add `--no-reach` to skip the reachability search of the sectors) and writes `<folder of the executable>/legacy.larissa`; a pack with errors
   leaves nothing behind. An export again writes over the earlier `legacy.larissa`. `--version=` sets the version in the manifest, which the pack screen shows (`1.0` by default). A Web build looks in `/packs/` of the page's virtual file system (`Packs.WEB_ARCHIVES_DIR`): its page
   (`godot/export/web_shell.html`) preloads `legacy.larissa` and `dev.larissa` from next to `index.html`, so you copy `legacy.larissa` there. Anyone who can load that
   page can download the pack file, which is the original game's content: use it for a private or self-hosted deployment only. The editor never looks next to
   its own executable.
4. Run the exported game. `legacy` is the only pack found, so it is chosen by itself: no warning, no flag, no dev. With other packs
   installed, `-- --pack=legacy` chooses it. `pack_tool --check=legacy` (or the pack screen's Check) tests it. The game looks for a pack in the user folder first and for the pack files next to the executable last, and
   the first place that has an id wins: a folder `<user dir>/packs/legacy/` (or a file `<user dir>/packs/legacy.larissa`) is used and the `legacy.larissa` next to the executable is left out (the pack
   screen and the log say so: run the game from a terminal and the lines that start `Packs:` say where it looked, what it found and which pack it chose). Delete that folder to use the file. The user folder of the game is:

   | OS | `<user dir>` (`user://`) |
   |---|---|
   | Linux | `~/.local/share/godot/app_userdata/Operation Larissa/` |
   | Windows | `%APPDATA%\Godot\app_userdata\Operation Larissa\` |
   | macOS | `~/Library/Application Support/Godot/app_userdata/Operation Larissa/` |

   (The exported game's own `user://` is the same place as a game run from the editor, because it reads the project's name, `Operation Larissa`. The sign-in screen's pack
   screen, key P, shows the real path.)

`pack_tool` is `tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --list` (or `--check=<id>`);
[PACKS.md](../engine/PACKS.md) has all its options.

The pack file holds your copy of the game's content, so it is for your own use and must not be shared or committed: keep it next to your exported game, outside the
repository (the `build/` folder is git-ignored; export anywhere else and keep the file out of git yourself).

## Where everything goes

Everything below is git-ignored (`.gitignore` lists each pattern), except the rows marked "committed". `<legacy>` in the table is the
legacy pack's folder, `godot/packs/legacy`.

### Where the legacy pack is

The legacy pack is the real folder `godot/packs/legacy/` of the project, that is `res://packs/legacy/`. The importer writes loose files
straight into it: no copy in Godot's user data dir, no link, and the same place whichever Godot you run (`tools/import/common.py`
`legacy_root()` is the one place that spells it; the game asks `Packs` for files, and the legacy test suite has `LegacyPack.ROOT` in
`godot/tests/legacy/legacy_pack.gd`).

The importer makes the folder and writes its `pack.json` (`{"id": "legacy", "title": "Operation Neptune (your copy)", "version": "1", "format": 1}`: no `base`, so the pack is complete). `godot/packs/` is a real folder in git; `.gitignore` ignores
everything in it except its `README.md` and `dev/` (the developers' own pack, which is committed), so a pack of your own that you put
there stays out of git, and nothing of the legacy pack can be committed by accident. The game reads it as `res://packs/legacy/...`,
through the chain (`Packs.path("data/zones.tres")` is the first pack that has the file).

Inside it:

```
packs/legacy/
  pack.json
  assets/    pictures, sounds, speech, music, each with a stub .import file
  data/      sectors/sector_00..31/, campaigns/{voyager,expert}.tres, problems/, sprite_frames/, sprite_meta/, ui/, story/news_cartoon.tres,
             zones, trigger_table, neptune_tileset, bubble_rules, the sound catalogs
  midi/      the original MIDI songs
```

| Location | What | Made by |
|---|---|---|
| `NEPTUNE.ISO` (or `$NEP_ISO`) | Your copy of the game. | you |
| `extracted/` | The first readable form of the ISO's pictures, sounds, MIDI and data; the importer's input. Includes `sounds/voice_transcripts.json`. | `extract`, `transcripts` |
| `docs/data/` seven files: `sectors.json`, `problem_records.json`, `problem_tables_raw.json`, `problem_gfx_bundles.json`, `trigger_table.json`, `zone_defaults.json`, `onwin_map.json` | The game's data tables. The other JSON files in `docs/data/` are facts read from the program's code and are committed. | `tables` |
| `<legacy>/pack.json` | The pack's manifest. | the importer, before any step |
| `<legacy>/assets/` | Pictures, sounds, speech, music, each with a stub `.import` file. | `images`, `tiles`, `sprites`, `problems`, `audio` |
| `<legacy>/data/sectors/sector_00..31/` | The original sectors. Sectors of your own, 32 and up, go to `godot/data/sectors/` in the project and are committed. | `sectors` |
| `<legacy>/data/problems/`, `sprite_frames/`, `sprite_meta/` | Problem types, sprite frames, sprite sizes and hit rectangles. | `problems`, `sprites` |
| `<legacy>/data/zones.tres`, `trigger_table.tres`, `neptune_tileset.tres`, `bubble_rules.tres` | Zones, triggers, tileset, bubble rules. | `sectors`, `tiles`, `sprites` |
| `<legacy>/data/campaigns/voyager.tres`, `expert.tres` | The original's two games. Campaigns of your own go to `godot/data/campaigns/` and are committed. | `campaigns` |
| `<legacy>/data/{sfx,music}_catalog.tres`, `voice_index.tres`, `voice_cues.tres` | The sound catalogs. | `audio` |
| `<legacy>/data/ui/{hud,calculator,story}_layout.tres`, `<legacy>/data/story/news_cartoon.tres` | Layouts and the news cartoon. | `console`, `story` |
| `<legacy>/midi/` | The original MIDI songs, for playing the music through a soundfont at runtime. | `audio` |
| `godot/tests/fixtures/original/` | The original bytes behind the committed hash fixtures: sector headers, creature records and scripts, screens, sprite metadata, trigger table, zones, problem tables. The reset tools and the fidelity tests read them. Rebuilt on every import; never edit. | `sectors`, `sprites`, `problems` |
| `godot/data/legacy/` | Your own hand data about the legacy pack (it stays in the project, not in the pack: it is an input of the importer). It holds `voice_corrections.json`. The importer never writes it; `transcripts.py --correct` does. `$NEP_LEGACY` puts the folder elsewhere. | you |
| `godot/.godot/` | Godot's own import cache (git-ignored by `godot/.gitignore`). | Godot |
| `soundfonts/`, `build/`, `iso/`, `prefix/`, `.venv/` | Your soundfonts, files copied out of the ISO on demand, the CD unpacked and the Wine prefix for playing the original, the Python environment. | you, tools |
| `godot/tests/snapshots/*.png` | Pictures from the snapshot test that you chose to keep. | you (see below) |
| `user://roster.json`, `user://hall_of_fame.json`, `user://audio_settings.cfg`, `user://packs/`, `user://midi/` | Your players, the hall of fame, the audio settings, installed packs, your own MIDI files (the user folder: "Playing legacy in an exported game"). | the game, you |

Committed even though the importer also writes them, with the same bytes, so a clean import leaves `git status` clean:

- the files made from the program's code alone, with nothing of the game in them, which stay in the project's `godot/data/` and not in
  the pack: `closing_crew.tres`, the cutscene timelines in `story/` (all but the news cartoon's, whose length is that
  of the game's bulletins, which is the legacy pack's), and `ui/menu_layout.tres`;
- provenance and hashes, with no bytes of the game: `tools/import/asset_manifest.json` and the hash fixtures in `godot/tests/fixtures/`
  that the `sectors`, `sprites` and `problems` steps write (the step table names them).

If `git status` shows any change after an import, something in the tree is not what the importer expects: do not commit it.

Committed and never written by an import: `tools/import/source_files.json` (the reference release's hashes; only
`source_files.py --write` writes it, see "Troubleshooting"), `godot/tests/fixtures/voice_transcripts.json` (only
`transcripts.py --write-fixture`), the other files in `godot/tests/fixtures/` (test data that is not hashes, such as
`cutscene_timing.json` and `foe_names_probe.json`), and the hand-made files: `godot/names/original.json`,
`godot/data/rules/durations.json`, `godot/data/sectors/foe_annotations.json` (the project's, also for the original's sectors), your own
sectors and campaigns.

### What stays only on your machine and cannot be regenerated

`godot/tests/snapshots/*.png` (pictures from the snapshot test that you chose to keep) show the original's art, so git does not carry
them. The importer cannot make them either: they are pictures you keep.

## Putting things back: the reset tools

The creature scripts, screens, sector headers and a few small tables in the legacy pack's `data/` are what designers edit, and there is
no `git restore` for them, because git does not have them. The reset tools in `tools/import/` rebuild just those from the
original bytes that the importer saved in `godot/tests/fixtures/original/`, check them against the committed SHA-256 hashes
(a different release or a patched copy is refused), and leave everything else alone. Without the saved bytes they say `run the
importer on your copy of the game`.

| Tool | Puts back |
|---|---|
| `reset_screens.py --all` (or sector numbers, or `S:M` for one screen) | The screens, `screen_MM.tres`. |
| `reset_foe_scripts.py --all` (or sector numbers; `--records` for the creatures' record fields; `--plain` without your names and comments) | The creature scripts, `.foe`. |
| `reset_sector_header.py --all` (or sector numbers) | A sector's start, neighbours and pieces. |
| `reset_tables.py sprite_meta \| trigger_table \| zone_levels \| problems` (`--all` or names) | Sprite sizes and hit rectangles, the trigger table, the zones' default levels, the stored problems. |

Each is run as `uv run tools/import/<tool>.py ...`. They refuse every sector outside the original's 0 to 31: your own, 32 and up, whose
files are their only source. The scripts are
explained in [FOE_SCRIPTING.md](../create/FOE_SCRIPTING.md), the screens in [SCREEN_EDITOR.md](../create/SCREEN_EDITOR.md).

## Troubleshooting

**`REFUSED, nothing was read or written: ... not found: put your copy of the game at NEPTUNE.ISO or set NEP_ISO`**
The tools cannot find an image. Check the name (`NEPTUNE.ISO`, upper case on a case-sensitive file system), that you run from
the repository root, and that `NEP_ISO`, if set, is an absolute path to a file.

**`REFUSED ...: your copy of the game is a different version or patched. N files do not match source_files.json: ...`**
The list names each file that is missing, `differs` (with the size and the first digits of its SHA-256, and the reference's),
or `is not in the reference release`. Check which release your image is (the 1998 Windows CD-ROM release is the reference) and
try another copy. A damaged download shows up here too; compare `uv run tools/gamefiles.py sha256` with the source's checksum.
Do not run `source_files.py --write`: it replaces the reference table with *your* copy and so defeats the check. It is only for
moving the project to another release on purpose.

**`REFUSED, nothing was read or written: the importer needs these first`**
The tool check (`tools/import/tool_check.py`) found programs missing for the steps you asked for; each line names the program, the step
that needs it and how to get it, and nothing was written. `uv run tools/import/tool_check.py` repeats the check alone. The lines:

- `Godot (step godot): not found`: run `mise install`, and make sure mise's
  `godot` is the one on the `PATH` (`mise activate` in your shell; `which godot` should be under `~/.local/share/mise`), or set
  `GODOT_BIN` ([SETUP.md](../SETUP.md), "Godot").
- `ffmpeg`, `fluidsynth` or `General MIDI soundfont (step audio)`: install the packages the line names ([SETUP.md](../SETUP.md)), or give `--soundfont` the path of another General MIDI `.sf2`. An `ffmpeg` without the libvorbis encoder is refused too.
- `speech engine (step transcripts): faster-whisper is not installed ...`: run
  `uv sync --group transcribe` (or a plain `uv sync`), or leave the step out with `--no-transcripts` (the clips then have no text).

**`!!! WARNING: not the version the project pins, tests and supports`**
A program is there but at another version than the pinned one; the importer goes on. Nothing to do if you chose that version on
purpose (a beta, your distribution's build); what breaks with it is yours to find. To get the pinned one:

- `Godot (step godot): tools/godot.sh runs Godot 4.x, the project pins 4.7.2.stable`: run `mise install` and put mise's `godot`
  first on the `PATH`, or set `GODOT_BIN` to a 4.7.2 binary ([SETUP.md](../SETUP.md), "Godot").
- `speech engine (step transcripts): ... are installed, the pins are ...`: run `uv sync --group transcribe`. With other versions,
  expect `DIFFERS from the fixture` lines.

**`REFUSED: ... has SHA-256 ..., expected ...: delete the Hugging Face cache entry and run again`**
A downloaded model file is not the pinned one (a broken download, usually). Delete the model's folder from the Hugging Face
cache (`~/.cache/huggingface/hub/models--Systran--faster-whisper-small.en`) and run the step again.

**`DIFFERS from the fixture` lines**
See "Voice transcripts": try `--compute-type float32`, and report the CPU to the project if int8 differs.

**`STALE correction ...`**
See "Voice transcripts": set the correction again, or delete it.

**The game opens on the warning screen (no pack found, or no pack `legacy`), though the importer finished**
A release build says "This game cannot be played" and quits on a key; a debug build says the dev pack is in use. If the screen says the pack is *incomplete* (it counts what is
missing), the legacy pack is damaged or out of date, as when the importer stopped half way or the game is newer than the pack: run the importer again.
Look at `godot/packs/legacy`: it must be a real folder that holds `pack.json`, `assets/`, `data/`. Then run
`tools/godot.sh --headless --path godot --import` again: Godot must import the pictures and sounds in it.
`tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --list` says which packs the game finds and why it chose the
chain it did; `-- --pack=legacy` after the game's `--` asks for the pack by name.

**An exported game does not use the `legacy.larissa` next to it (or uses an old `legacy`)**
The first place that has the id `legacy` is used (an installed folder or file in the user folder before a pack file next to the executable), and the others are left out. The pack screen (key P),
`-- --list` and the game's log name the pack that is used and say what was left out. A folder `<user dir>/packs/legacy/` (or a file `<user dir>/packs/legacy.larissa`) wins over the file next to the
executable: delete it to use the file. A pack file that cannot be read (not a zip, a file over its size limit, a manifest that names another id than the file) is left out with its reason; make it again
(`mise run release:build_linux`, or `mise run godot:pack legacy --out <folder of the executable>`).

**`Godot could not be started` / `the Godot import was not done`**
Godot passed the tool check but its import failed: read the output printed above the line, then run
`tools/godot.sh --headless --path godot --import` by hand.

**`note: no soundfont for the AdLib music set` / `soundfonts/opl.sf2 not found - the AdLib set is rendered with ...`**
Not an error. See "Soundfonts".

**Godot warns about an invalid UID, or an asset that loaded before fails to load after you renamed things**
The uid of an asset is worked out from its path, so an asset that gets a new name gets a new uid, unless the importer carried
the `.import` file over (it does, for an asset whose bytes did not change). `godot/.godot/` is only Godot's own cache of
imports, and Godot makes it again: close the editor, delete `godot/.godot/`, and run `tools/godot.sh --headless --path godot
--import`. (This repository's documents do not describe this warning; it is the general Godot remedy.)

**The legacy tests skip "run the importer on your copy of the game" after you ran it**
A step did not finish, or Godot has not imported yet. Read the importer's output for `REFUSED`, `WARNING` and tracebacks, run
`tools/godot.sh --headless --path godot --import`, and run again. `uv run tools/import/import_all.py --validate` cross-checks
the tree.

## Where to go next

- [CONTENT.md](../create/CONTENT.md): how content works (layers, campaigns, packs, skins, where things live).
- [MAKING_CONTENT.md](../create/MAKING_CONTENT.md): making new content with the editor tools.
- [SCREEN_EDITOR.md](../create/SCREEN_EDITOR.md), [FOE_SCRIPTING.md](../create/FOE_SCRIPTING.md),
  [SECTOR_INSPECTOR.md](../create/SECTOR_INSPECTOR.md): the tools for changing the original's screens, creature scripts and sectors.
- [ASSET_FORMATS.md](../port/ASSET_FORMATS.md): the formats of the game's files and the asset manifest; [NAMES.md](../create/NAMES.md):
  the name registry.
- [FIDELITY.md](../port/FIDELITY.md): why the importer is built this way (provenance, hash fixtures, the fidelity rules) and how to run
  the original game for comparison.
