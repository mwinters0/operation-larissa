# Asset formats and the asset manifest

How the game's files are laid out, how the extractors and the importer turn them into the legacy pack's `assets/` (`godot/packs/legacy/assets/`), and the manifest that
says, for every asset file, where it came from. What each id *means* is in [`DESIGN.md`](DESIGN.md) (graphics binding: section 9,
audio: section 7, data layouts: sections 4-6 and 16) and [`CONTENT.md`](../create/CONTENT.md) section 6 (which role gets which
folder). This file is about the formats, not about single pictures or sounds: the lists of those are the manifest.

## The manifest: `tools/import/asset_manifest.json`

One entry for each file under the legacy pack's `assets/` (not Godot's `.import` sidecars), keyed by the path below the legacy pack's root:

```json
"assets/sprites/foes/foe_z5_canister_idle_0_35.png": {"origin": "original", "source": "ONWINCD/NEP256.DLL", "resource": 1980,
    "offset": 2181120, "length": 1536, "bundle": 110, "conversion": "rund_png_rgba"}
```

| Field | Meaning |
|---|---|
| `origin` | `original`: one resource of the game's files, converted one to one. `derived`: made from original data (a tile atlas arranges pictures, music is a MIDI file rendered through a soundfont). `port`: made by the port, with nothing original in it (the drawn currents / invisible-wall tiles, the READMEs and render stamps written next to the assets). |
| `source` | A file of the CD, as named in `source_files.json` (so it is covered by the hashes `import_all.py` checks first), or, for `port`, the importer script that writes the file. |
| `resource` | The resource id inside the source file. For a picture of NEP256 / NEPBG1 / NEPBG2 this is the **picture id**; for NE0SOUND / NE1SOUND it is the sound id (sound effect `n` is 8000 + n, a speech clip is its own id; the file name ends in that number, see "File names" below). `resources` (derived tile atlases): the picture ids of cells 0, 1, 2 ... in order; cell 0 stays empty. |
| `offset`, `length` | Where the resource starts in the source file and how long the file's resource table says it is (always a multiple of 512: see below). A MIDI source is the whole file: offset 0, its size. |
| `bundle` | The NEP.DLL bundle (BNDL) the picture is a member of, when it is in one (the extractor takes the first). |
| `conversion` | `rund_png_rgba` (a sprite: RUND decoded, palette 900, index 200 becomes alpha 0), `rund_png_opaque` (a background), `pcm_wav` (sound resource to WAV), `tile_atlas` (16 x 16 tile pictures into an 8 x 8 grid), `midi_ogg` (FluidSynth, then ffmpeg: silence at the end cut, loud songs turned down, see `step_audio.py`), `drawn` (made with Pillow), `text`, `stamp` (the `rendered_with.json` next to the OGGs). |
| `rate` | WAV only: the rate the game *plays* the clip at. Every resource header says 22050; see "Sounds". |

It holds provenance, never bytes. The **importer writes it** (`asset_manifest.py`): every step records an entry when it writes an
asset, `import_all.py` resolves the offsets from the DLLs' resource tables and saves the file, and a partial run
(`--only sprites`) replaces only the entries of the folders it owns. It is generated the way the hashed fixtures are, so it
cannot drift from the code. It lives in `tools/import/` beside `source_files.json` rather than in `godot/data/` because the two
belong together (what the importer reads, what it makes), because it is not game data (it should not be exported with the game),
and because the legacy pack is not in the repository (git-ignored, `godot/packs/legacy`) while the manifest has to stay.

`tools/import/test_asset_manifest.py` checks that the manifest covers every file under the legacy pack's `assets/` and names no file that is
missing, that every `source` is a file of the checked CD or a script, that no picture or sound is the source of two files, that the
offsets point at what they say (RUND headers, sound headers; needs `NEPTUNE.ISO`) and that a second importer run changes no file.

**File names.** An asset file is called `<name>_<number>.<ext>` after the registry's name and the original's number
(`audio/sfx/lock_tick_38.wav`), or keeps a numbered name when nobody has named it (`sfx_28.wav`, `foe_028.png`, `foe_z3_040.png`); the
rule per kind is in [`NAMES.md`](../create/NAMES.md), "Asset file names", and in code in `tools/import/asset_names.py`.

**The slot tables.** Which picture sits in which creature or deco slot is data too: `tools/analysis/data/sprite_slots.json` (hand-kept,
read by `step_sprites.py`, `pictures.py` and `common.py`; `test_sprite_slots.py` checks it against the bundles). A foe record's
frame byte indexes the creature slots (0-27 common, 28-34 the ink burst, `ink_burst`, 35+ the zone's own), a deco id the deco slots (0-69
common, 70+ the zone's own); the manifest then says which file holds each picture.

## The game's files

All the importer reads is the CD's `ONWINCD/` folder (hash table: `tools/import/source_files.json`); the CD's other folders hold the
installers of other programs and are never read. `tools/gamefiles.py` reads them straight from `NEPTUNE.ISO`; `tools/extract/run_all.sh`
writes the first readable form to `extracted/` (git-ignored, large), which the importer then reads.

| File | Holds |
|---|---|
| `NEP256.DLL` | 1158 pictures with the colour key (sprites, UI parts, tiles, problem-panel art) |
| `NEPBG1.DLL`, `NEPBG2.DLL` | The backgrounds, one 608 x 288 picture per screen (ids 3000 + sector * 12 + screen; a few ids at the end do not exist) |
| `NEP.DLL` | Palettes, bundle lists, text, binary tables (sector and creature data, sprite metadata, problem tables), fonts, two x86 stubs of the DOS blitters |
| `NE0SOUND.DLL` | 52 sound effects (ids 8000-8051) and 191 AdLib FM patches (9000-9190, not used by the port) |
| `NE1SOUND.DLL` | 371 speech clips (4000-4370) |
| `NE2SOUND.DLL` | A 12-byte stub with no assets |
| `SOUNDS/*.MID` | 20 MIDI files: `B*.MID` for the AdLib / base sound card, `E*.MID` for General MIDI (same ten songs, richer arrangement) |
| `ONWIN.EXE` (Win16), `ONWIN32.EXE` | The program; string tables, dialogs, the id map `OTHR 15001`, icon |
| `ONWIN.MAP` | The linker map of the 16-bit program, with function and global names |
| `HALLFAME.DAT`, `ONUSERS.DAT`, `ONWINCD.INI` | An empty hall of fame and user list (formats: `DESIGN.md` section 6) and the setup file |

### The DLLs are Win16 NE files

Each DLL is an NE executable whose resource table is the container (reader: `tools/extract/ne.py`, `tools/analysis/ne.py`). The
resource types are custom: **32513** holds the pictures, the sounds and the bundle lists (`BNDL`), **32515** the data tables and
text (NEP.DLL, ids 10000-12020), **32514** the bitmap fonts, **32516** the two palettes (ids 900, 901). Resource offsets and
lengths are stored in units of 512 bytes (the table's shift count), so every resource is padded to a multiple of 512 and the true
length has to come from the content. The game finds a resource by a logical id that `OTHR 15001` maps to a real id; the id
ranges per library and the mapping are in `DESIGN.md` section 4. The manifest uses real ids.

A **bundle** is a resource `u32 'BNDL', u32 count, count x u32 ids`: the ids of pictures (or sounds, or texts) that belong
together, in the order the program indexes them. Frames of one animation are consecutive in their bundle; nothing inside a picture
says how it animates (see `DESIGN.md` section 9: timing and placement are in code and sector data).

## Pictures

* **RUND** (`tools/extract/rund.py`): `u16 width, u16 height, "RUND"`, then run-length coded 8-bit palette indices. A control
  byte `c` with bit 7 set repeats the next byte `c & 0x7f` times; with bit 7 clear it copies the next `c` bytes. The stream ends
  after width x height pixels; the rest of the resource is zero padding. All 1534 pictures decode with no short stream.
* **Palette**: one 256-colour palette for everything, resource 900 (901 differs only in the Windows static-colour slots 0-9 and
  246-255, which no picture uses apart from 0 and 1). 768 bytes RGB; the values are multiples of 4 (the VGA 6-bit palette). The
  PNGs use 900. Indices 176-205 are blue ramps; the program does not cycle them (`DESIGN.md` section 9).
* **Colour key**: palette index **200** (0xC8, RGB 0000A8) is transparent in every sprite (`set_invisible_color_to(0xC8)`). The
  PNGs of sprites are RGBA with that index at alpha 0; backgrounds never use it and are opaque.
* **Size**: pictures run from 4 x 2 to 640 x 400. The game surface is 640 x 400; the playfield is the 608 x 288 background at
  (16, 32). The extractor's own `images/manifest.json` lists every picture's width, height, bundle and file.
* The port stores each picture id once (`tools/import/pictures.py`); everything else that needs it points at that file.

### Indexed SpriteFrames

For every art set that comes from bundles, `tools/import/step_sprites.py` writes one `SpriteFrames` with the animation `all` (speed
0, no loop) whose frame i is slot i of the bundles, concatenated in the order the game indexes them: `decos_zone{z}.tres` (slots 0-69
common, then the zone's decos), `foes_zone{z}.tres` (0-27 creatures, 28-34 the ink burst, 35+ the zone's creatures),
`sub_frames.tres` (bundle 15 in order), and likewise the pieces, the station and the fx sets. So `FoeData.frame` and
`DecoPlacement.slot` bind one to one to a frame of `all`. The real, named animations (`ink_burst`, `bubbles`, `station_open`,
`dolphin_swim`, ...) are curated by hand in `tools/import/animation_map.py` and play one frame per game tick; the pieces' `canister`
and `rock` come from `extracted/tables/piece_animation.json`.

## Sounds

* **Resource**: `u32 format (0), u32 rate (22050), u32 length`, then `length` bytes of unsigned 8-bit mono PCM (silence is 0x80),
  zero padded. One resource (8013) has a wrong length field and is cut at its last non-zero byte.
* **Rate**: every header says 22050, but that is the real rate only for the effects. The one `waveOut` routine opens the device at
  an override rate when one is set; the opening cartoon sets 8000 for its eleven voice clips (4000-4010) and then 16000, never
  reset, so all other speech plays at 16000. The extractor reads both values out of `ONWIN32.EXE` and writes the WAVs at the rate
  the game plays them at (the manifest's `rate`). Evidence and call sites: `DESIGN.md` section 7.
* **Speech text** is not part of the repository (it is the game's speech): the importer's `transcripts` step
  (`tools/import/transcripts.py`) makes deterministic machine transcripts with a pinned Whisper model into the
  ignored `extracted/sounds/voice_transcripts.json` (hand corrections from the git-ignored hand-data area `godot/data/legacy/`, or
  `$NEP_LEGACY`, applied). The committed
  fixture `godot/tests/fixtures/voice_transcripts.json` holds one SHA-256 per clip and the engine pins, no text.
* **AdLib FM patches** (NE0SOUND 9000-9190: `u32 type 0-4`, then register and note bytes): not decoded, superseded by the WAVs.
* **Music** is Standard MIDI in `SOUNDS/`; the importer renders the ten songs of each set to OGG (`step_audio.py`), recording the
  soundfont and the MIDI hashes in `rendered_with.json` beside them. FluidSynth does not render the same samples twice, so the OGGs
  are fixed by the hashes of the MIDI files, not by their own.

## Text and tables (NEP.DLL, type 32515)

About 740 resources: 438 text strings, the rest binary. Text uses the game's own font codes: `0x08 0xD0+n` is variable `n` (the
extractor writes `{n}`), `0x0C` is the degree sign, `0x0D` a newline, `0xFF xx` a formatting or answer-field directive, and the
control characters `0x09` (a tab: the game draws the N key), `0x0B`, `0x0E-0x1C` are key and arrow glyphs of the game font (which key each is: `DESIGN.md` section 5.5, Font). The math problems are templates with such
variable slots, grouped by a bundle per problem type (the phrasings, the step-by-step hints and the success message).

The binary tables are decoded where the port needs them: sector maps and creature records (`DESIGN.md` sections 4 and 3.5; fixtures
`screens.json`, `foe_records.json`, `foe_scripts.json`), sprite sizes and hit rectangles (`sprite_meta.json`), the trigger table,
the problem parameter tables (`DESIGN.md` section 5.4, `extracted/tables/problem_*.json`, `tools/analysis/data/problem_*.json`). The text of the UI is in the executables' string
tables (`DESIGN.md`). The bitmap font data (type 32514: first and last character, height, a width table, the low and high bytes of each glyph's
offset, then 1-bit rows padded to bytes) is not imported; the port uses an ordinary font and writes the key glyphs below 0x20 as
labels (`DESIGN.md` section 5.5).

## Known quirks of the data

* The sprite height table says 32 px for the three 80 x 16 pictures 1175-1177 (common creature slots 14-16), an oversized value;
  the pictures and their hit rectangles fit 16 px, and `tools/import/validate.py` lets these three through.
* Tile bit 0x40 with picture 0 is taken as an invisible solid wall: the decompiled tile test treats 0x40 as solid and picture 0 is
  blank, and nothing in the 32 sectors contradicts it. It is an assumption, not seen in the running original.

## What is not imported

* The CD's `ASSETS/*.GRP` archives and `MOVIES/MV107A.SMK` belong to a preview reel for other Learning Company titles (a different
  licence), not to Operation Neptune; `tools/extract/extract_previews.py` can unpack them (`RGrp` archives with ASEQ animations,
  WAVE speech, RRGB palettes) into the ignored `extracted/previews_other_titles/`, and nothing reads them.
* The AdLib FM patches and the bitmap font data, as above; the editor-era pictures 2081-2090 are imported only for reference
  (`assets/authoring_tool/`, `DESIGN.md` section 16).
* Not decoded: the preview reel's cel format, and any palette cycling (the program seems to have none).
