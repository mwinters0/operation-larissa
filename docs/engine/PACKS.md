# Packs in code

A pack is content under a root, a folder or one pack file (`<id>.larissa`, "Pack files" below), with a `pack.json`. The engine has no content of its own and no special case for any pack: it plays
**one chosen pack and the packs it is laid over**, `Packs.chain()` (chosen pack first), and every lookup asks the chain in order, the first
pack that has the thing answering. The user-level description (the layout, what a pack can hold, installing)
is [`../create/CONTENT.md`](../create/CONTENT.md), section 4; this page is the code. Paths are relative to `godot/`.

| Class | File | Role |
|---|---|---|
| `Pack` | `src/core/pack.gd` | one pack, a folder or a pack file: manifest, `trusted`, files (`has`, `read_bytes`, `read_text`, `size_of`, `files_in`: the one way to read a pack's file), layout checks, the door (`resource`, `texture`, `stream`, `provides`), clip lengths |
| `PackArchive` | `src/core/pack_archive.gd` | one open pack file: the zip's central directory read into the one index of what it holds, the limits, the reads |
| `Packs` | `src/core/packs.gd` | static: finding packs, choosing, the chain, every lookup |
| `ResourceJson`, `EngineJson`, `SectorJson` | `src/core/` | the JSON forms of resources, of `SpriteFrames` / `TileSet`, and of sectors: the data form |
| `PackClip`, `ClipLengths` | `src/core/` | a clip's stream and its length in ticks, from the same pack |
| `Durations`, `Tuning`, `LayeredJson` | `src/core/` | the durations and the rule values, laid over down the chain (`LayeredJson` is the layering they share) |
| `PackCheck`, `PackReport`, `PackNeeds`, `PackExport`, `PackInstall`, `PackCopy`, `PackChoice`, `PackFiles` | `src/packs/` | the pack tools (below); `PackNeeds` is what a chain must hold |
| `PackDialog`, `PackWarning` | `src/ui/` | the player's pack screen; the warning screen |
| `ModSpec`, `ModLoader`, `ModApi`, `ModHost` | `src/mods/`; `src/autoload/mod_host.gd` | a mod pack's manifest entry, the loader that runs its script in a Sandbox, the API it is granted, the autoload that owns the running mods ("Mod packs", below) |

## Finding and choosing

- **Two packs are known by name.** `dev` (`Packs.DEV`, `Packs.dev()`): placeholder content, complete, the engine suite's pack and the fallback
  ([`../../tools/dev_pack/README.md`](../../tools/dev_pack/README.md)). `legacy`: the original game, written by the importer as loose files into
  `godot/packs/legacy` (git-ignored; no `base`), an ordinary pack. `LegacyPack` (`tests/legacy/legacy_pack.gd`) is a test helper
  that knows where legacy is; the engine does not.
- **Where dev comes from.** `Packs.dev()` is the folder `Packs.dev_root` (`res://packs/dev`, committed: the editor and the tests), else the installed
  `Packs.installed_dev_root` (the folder `user://packs/dev`, or the pack file `user://packs/dev.larissa`: installed from the pack screen or `pack_tool --install`),
  else the bundled `dev.larissa` (below), else null (`Packs.has_dev()`). The first of these that is a dev pack wins, in that order: the others are left out, and
  `Packs.ignored()` and the log say so (so does a `dev` whose manifest says another id). `Packs.available()` never lists dev: the id is reserved, and a folder of any other
  place that says it is `dev` is left out with a reason. `Packs.forget_dev()` makes the next call look again (and look for the pack files).
- **Found.** `Packs.available()` lists one pack per id, from the places `Packs._places` names, in this order: a folder with a `pack.json` in `Packs.folders`
  (`res://packs/`, the project's, then `user://packs/`), a pack file `<id>.larissa` in those same folders, and the bundled pack files (below). The first place that has an
  id wins; each other is left out and `Packs.ignored()` (the pack screen, the log) says which one is used. A pack file is used only when its `pack.json` names the id
  its file is called and `PackArchive` accepts it; else it is left out with the reason. A pack with errors in its manifest is listed (the pack screen shows them) but is
  never the default choice.
- **Pack files.** A pack as one file is `<id>.larissa` (`Pack.FILE_EXTENSION`): a zip of the pack's folder under an extension of its own, so a file manager, the pack
  screen's file picker and a web server tell a pack from any other zip. `PackExport` with `archive` writes one (`PackFiles.zip_folder`: pictures, sounds and MIDI, already
  compressed, are stored as they are, the rest deflated). A pack file is **read in place**, nothing is extracted:
  - `Pack.open` on the file's path makes a `Pack` whose `root` is that path and whose `_archive` is a `PackArchive`. `Pack.has`, `read_bytes`, `read_text`, `size_of`,
    `files_in`, `folders_in`, `modified_time` answer from the archive's one index; `path_of(rel)` is a *virtual* path under the file (`user://packs/legacy.larissa/data/zones.json`)
    that names the file and that no file system can open. The pack is **read-only and never `trusted`**: only the data form is read, and an editor writes only to a trusted
    project folder. `Pack.close` lets go of the file (it is reopened by the next read), which `PackInstall` does before it replaces or deletes the file.
  - `PackArchive.open` reads the zip's central directory itself and judges the file before anything is read: the pack is at the root of the zip or in the one folder that holds
    `pack.json`; every path is `Pack.is_safe`; an entry is over `PackArchive.MAX_FILE_BYTES` or all of them over `MAX_TOTAL_BYTES`; an entry is encrypted, stored in a form
    other than stored or deflated, or the zip is ZIP64. A file with errors holds no files and is refused (`Pack.errors`). A deflated entry is inflated through a gzip wrapper, so
    zlib checks it against the directory's CRC-32; a size the directory declares is checked before the buffer is allocated.
  - **The path door.** A path in a pack is never handed to `FileAccess`, `DirAccess`, `ResourceLoader` or `Image.load*`: code asks the pack (`Pack.has` ...), and for a path
    string it was handed `Packs.has_file_at(path)` and `Packs.bytes_at(path)`, which find the pack by the start of the path (`Packs.pack_of_path`), next to `file_at` and
    `exists_at` for the objects the door makes. `tests/engine/test_pack_paths_go_through_pack.gd` scans the source for a line that breaks this.
  - **Bundled.** A game carries `legacy` and `dev` as pack files next to it (`Packs.bundled`). They are looked for in `Packs.archive_folders`, which is
    `Packs.default_archive_folders(web, in_editor, executable)`: the folder of the executable on a desktop build (none in the editor, whose executable is Godot's), and
    `Packs.WEB_ARCHIVES_DIR` (`/packs`) on the Web, where the page (the export shell `export/web_shell.html`, `PACK_IDS`) preloads the `<id>.larissa` files that sit next to
    `index.html` into the virtual file system. They are read where they lie, and are the last place `Packs._places` looks, so a pack of the same id in the project or in
    `user://packs/` is used instead.
  - **Installed.** `PackInstall.install` copies a pack file whole to `user://packs/<id>.larissa` ("Pack tools"); an id is installed in one form, folder or file, at a time.
- **Chosen.** `main.gd` calls `Packs.start(args)` once: `--pack=<id>` after `--`, else the first pack found in the lexical order of the
  ids. `Packs.choose(id)` chooses in code; `Packs.resolve` follows the `base` links. `start` writes a report to stdout, each line once and
  prefixed `Packs:`: where it looks (`search_report`: `folders` with the real path of `user://`, the bundled pack files and `archive_folders`, debug or release),
  what it found (`found_report`: each id and where it is, the dev pack), the packs it left out and why, and what it chose (`choice_report`: `--pack=` or
  the first id, then the chain with each pack's place, and whether dev stands in or the chain is refused). An exported game says this way which pack file it plays.
- **Checked, once per choice.** A chain that resolves is asked what it lacks: `PackNeeds.gaps` on the chain with no `dev` under it and
  no skin (a pack is complete whatever skin is on), see "What a chain needs". A hard gap makes the chain incomplete; a soft gap is only
  logged. A chain that holds `dev` for real (`--pack=dev`, a pack whose `base` is `dev`) is whole and not asked: dev is complete.
  The chain is built into the lookups before the question (`PackNeeds` asks them) and not built again when nothing is added to it.
- **When the chain is not whole** (no pack, the one asked for is missing, a pack has errors, a `base` is missing, the links go round,
  the chain lacks things) `Packs.fallback_reason()` (`Packs.Fallback`) says why, and
  `Packs.dev_fallback` decides what happens. `Fallback.text()` is the sentence, `advice()` where to read, `missing_text()` the count.
  - **`dev_fallback` on** (the default in a debug build, `OS.is_debug_build()`): `dev` is put at the bottom of what was found, so it
    answers only what the chain lacks (a chain that lacks things keeps all its packs and dev goes under the whole chain; the reason is
    `MISSING_ASSETS`, with the count and `PackNeeds.summary`). `main.gd` opens `src/ui/pack_warning.tscn`: it says what happened, how many
    things are missing and that dev's placeholders stand in for them, and any key or click goes on into the game.
  - **`dev_fallback` off** (a release build): nothing is added and the game does not play the chain (`Packs.is_refused()`; the chain is
    whatever was found, empty when nothing was). `PackWarning` is a refusal: the problem, the missing count, where to read; `go_on` does
    nothing. P (or the Pack screen button) opens the pack screen with a Use button (`PackDialog.choosing`): `Packs.choose` makes the
    choice, the check runs again, a whole chain goes on to the opening and anything else is shown again. Any other key, any click that
    is not on a button, or Quit, quits (`SceneRouter.dry_run` keeps a test alive). The buttons take no key focus, so a key never
    presses one.
  - The sentences are by situation, never by pack id: no pack at all (build the content with the importer, `docs/play/LEGACY.md`); a
    complete pack (no `base`) that is incomplete or has errors (damaged or out of date: run the importer again, "Troubleshooting" in
    `docs/play/LEGACY.md`); a pack laid over another that is incomplete or has a missing base (unfinished or needs a pack that is
    not installed: `docs/create/MAKING_CONTENT.md`, "Packs" in `docs/create/CONTENT.md`); a pack asked for that is not there (the pack
    screen lists what was found). `PackChoice.summary()` (the pack screen, `pack_tool --list`) prints the same text and advice.
  - `--pack=dev` is a choice, not a fallback: no warning, in both modes.
  - **No dev pack** (`Packs.dev()` is null): `dev_fallback` on has nothing to put under the chain, so the chain is refused as with it off, and
    `Fallback.no_dev` is true: `text()` ends with `NO_DEV_SENTENCE` (there are no dev assets to fall back to) and `advice()` with `ADVICE_GET_DEV`
    (`dev.larissa` comes with the creator download). When the trouble is dev itself (`--pack=dev` is `NOT_FOUND`, a pack whose `base` is `dev` is
    `MISSING_BASE`; `Fallback.needs_dev()`) the chain is refused in both modes, `no_dev` is false and `advice()` is `ADVICE_NEEDS_DEV`. With
    `dev_fallback` off nothing mentions dev.
- **Other calls.** `Packs.chosen()`, `chain_ids()`, `pack(id)`, `in_chain(id)`, `asked()`, `reset()` (choose again after the packs on
  disk changed), `use(pack)` / `snapshot()` / `restore()` (a check or a test borrows the chain), `lend(packs, body)` (runs `body` with exactly `packs` as the chain, nothing
  appended), `resolve(first, found, with_dev)` (the chain `first` makes; `with_dev` false stops it at a broken link instead of putting `dev` under it), `events.changed`.

## The layout and the manifest

```
<root>/                               res://packs/<id>/  or  user://packs/<id>/
  pack.json                           {"id": "orchard", "title": "Orchard", "version": "1.0", "base": "legacy",
                                       "author": "", "description": "", "format": 1,
                                       "mod": {"entry": "orchard.sgd"}}      (a mod pack: "Mod packs" below)
  <entry>.sgd                         the script of a mod pack
  campaigns/<id>.json                 a Campaign (id = the file's name)
  sectors/sector_NN/sector_NN.json    a SectorData, NN 0 to 255   +   sector_NN.foe   its creature script
  texts.json                          {"text_name": "words"} (Catalog.text / has_text)
  voice_cues.json                     {"groups": {"group name": ["voice name", ...]}}
  pictures/<kind>/<name>.png          a picture by its skin key
  audio/sound|music|voice/<name>.ogg  a clip by registry name (replaces the base's) or a name of its own
  audio/lengths.json                  {"voice": {"name": ticks}}: stated lengths (optional)
  data/problems/problem_type_NN.json  a ProblemType
  rules/durations.json                durations laid over data/rules/durations.json key by key
  rules/tuning.json                   rule values laid over data/rules/tuning.json key by key
```

A complete pack (legacy, dev, a copy of dev) has the layout the importer and the generator write: `assets/`, `data/` with the `.tres`
files, `midi/`. The same pack **exported** (`PackExport.complete`) is in the data form: `data/` holds the `.json` of each `.tres` at the same place
(`data/zones.json`), the sectors and campaigns are in the layout above (`sectors/sector_NN/`, `campaigns/<id>.json`, for the originals' too),
`assets/`, `midi/` and `rules/` are copied as they are, and the manifest says `"complete": true`.

**Manifest.** `id` (a lowercase word, at most 32 characters), `title` and `version` (free text) are required; `author`, `description` and `base` (a pack id,
not the pack's own) are optional; `format` is 1. A pack with no `base` is complete (`PackNeeds` asks the pack for everything the game needs); a pack with one is laid
over that pack. `mod` is optional and makes the pack a mod pack ("Mod packs"). A key the code does not know (`"tier"`, `"skins"`) is left alone. `Pack.open(folder or pack file)` reads it, `errors` says what is wrong, `Pack.problems()` adds the layout's (a resource,
scene or script inside a pack that is not trusted).

## Lookups

- **The door.** A file of a pack becomes an object in one place, `Pack.resource(rel)` / `texture(rel)` / `stream(rel)`, and the lookups reach it
  through the chain: `Packs.resource(rel)`, `Packs.texture(rel)`, `Packs.stream(rel)` give the object the first pack that *provides* the file
  makes (`Pack.provides`, `Packs.holder`). `rel` is the authoring path (`data/zones.tres`, `assets/tiles/zone0_tiles.png`). `Packs.file_at(path)`
  does the same for a path *string* held in data (`VoiceIndex.paths`, `MusicCatalog.gm_paths`, `ProblemType.art_files`): the pack whose folder (or pack file's virtual path) the
  path is under answers by the file's extension; a path of the project itself (`res://data/...`) is project code and is loaded; a path under
  `user://` or in no pack of the chain gives null. `Packs.exists_at(path)` is the question without the answer. `Packs.provider_below(pack, rel)` is
  where a `$ref` of `pack` is looked for: the pack, then the packs under it, never above. `Packs.source_of(resource)` is the file a picture, sound or
  resource was made from (its `resource_path`, else the path `Pack` noted in `Pack.SOURCE_META`: a decoded picture has no path of its own).
  `Catalog._door` keeps what the door made until the chain changes. `tests/engine/test_no_direct_loads.gd` reads every script of `src/` and
  `addons/` and fails on a `load(` outside the door that is not on its short, commented list.
- **A whole file the caller reads itself** (MIDI bytes, a file an editor writes): `Packs.path(rel)` is where the first pack that has it keeps it
  (`Packs.holder`, `Packs.has`), a virtual path for a pack file. The bytes are read with `Packs.bytes_at(path)` (`has_file_at` asks whether there are any); a resource is never loaded from it.
- **A thing a pack holds in the layout above**: `Packs.sector_owner`, `campaign_files`, `text`, `voice_groups`, `picture`, `clip`; a pack with no
  such file answers nothing and the next one is asked. These are read as data, never with `ResourceLoader`. The project's own `res://data/sectors`
  and `res://data/campaigns` are the lowest layer.
- **Who asks.** `Catalog` (`sector`, `sector_ids`, `has_sector`, `campaigns`, `text`, `has_text`, `voice_cues`, `problem_type`, the zones, sprite
  frames and the rest of `data/`; `packs_changed()` forgets what was made from packs), `GameSkin.picture` (a pack's picture wins over every
  skin), `Assets.ui_picture / background`, `SfxCatalog / MusicCatalog / VoiceIndex.stream_named` (a pack's clip first), `MusicCatalog.song_of_stem`,
  `Durations` and `Tuning` (the chain's `rules/durations.json` and `rules/tuning.json`, bottom first, over the project's; a run resolves `Tuning` once, when it begins), `Campaign.pack_id` /
  `finale_picture`. No sector number or campaign id is reserved: the nearest pack wins. What stays project-level is in
  [`HARD_CODED.md`](HARD_CODED.md).

## Trust is the folder, and the data form

There is one kind of pack and one rule. `Pack.trusted` is true for a pack whose folder is inside the project (`res://packs/<id>`: `dev`, `legacy`, a copy of
dev), as much the project's as its code. A trusted pack's `.tres` files are loaded with `ResourceLoader` by the door (the authoring form: the editors, the
Inspector and uids work on them), and its imported pictures and sounds are loaded so their import settings hold. Every other pack (`user://packs/<id>`, `user://packs/<id>.larissa`:
installed; a pack file next to the game: bundled) is read in the **data form** only: JSON, `.foe` text, PNG, OGG, WAV and MIDI, as bytes from `Pack.read_bytes` (a file or an archive's entry), with
`Image.load_png_from_buffer`, `AudioStreamOggVorbis.load_from_buffer` and `AudioStreamWAV.load_from_buffer`. Nothing it holds reaches `ResourceLoader`, so
installing one runs nothing but the creature VM and, in a mod pack, a sandboxed `.sgd` script ("Mod packs"), and `Pack.problems()` refuses a `.tres`, scene, script or native library in one (`Pack.RESOURCE_EXTENSIONS`: `tres res tscn scn gd gdc cs gdextension dll so dylib elf pck wasm`; `.sgd` is the only code a pack may carry). The data form of `X.tres` is `X.json` at the
same relative path, and `Pack.provides` says whether a pack can answer for a file in a form it may be read in: a trusted pack for its `.tres`, any pack for the
`.json` of it, any pack for any other file it has. So a pack that holds only `data/zones.json` replaces `data/zones.tres` of the pack under it. A manifest cannot
make a pack trusted: the rule follows the folder, not what the pack says, and a pack file is never trusted.

The skins that come with the game have scenes and scripts, so they are code of the project (`res://skins/`). A skin from a stranger is a mod pack ("Mod packs" below): a sandboxed script that draws the sector, chosen like any skin. `Packs` neither finds nor mounts a Godot archive (`.pck`).

## JSON forms

`ResourceJson` writes any Resource as one key per `@export` field, leaving defaults out, and reads it back with `Script.new()` only
(never `ResourceLoader`); an unknown field or a value of the wrong kind is a problem in `problems`, not silence. `Vector2i` is `[x, y]`,
`Rect2i` `[x, y, w, h]`, `Color` `[r, g, b, a]`, `PackedVector2Array` and `PackedColorArray` lists of those, `PackedByteArray` base64 (the
screens' tiles), a typed `Array[PieceData]` a list of objects; a class lists number-keyed Dictionary fields in `JSON_INT_KEYS`. Where the type does
not say what a value is (inside a Dictionary or an untyped Array) it is tagged `{"$": "float", "v": 1}` (a whole float; a whole number alone is an
int), `StringName`, `Vector2`, `Vector2i`, `Rect2i`, `Color`, or a packed array. A campaign by hand: `{"class": "Campaign", "id": "orchard", "title": "Orchard", "sectors": [40, 41], "finales":
[42], ...}`. `SectorJson.save(sector, pack_root)` writes a sector's JSON and `.foe`; a copy is made with
`SectorFactory.copied_script_text` so its script means the same under the new number (`tests/pack_shelf.gd`).

What the data form adds to hold every kind a pack has (`data/` of dev and legacy):
- **`{"$ref": "assets/sprites/sub/sub_00.png"}`**: a Texture2D, AudioStream or Resource field (or a list element or a Dictionary value) that is a file of
  its own, by its authoring path (a trusted reader and an untrusted one name the same file). Read through the door, looking in the pack the file is in
  and then in the packs under it. On writing, a picture or sound whose file is in a pack becomes a `$ref`. A Texture2D field may also be the bare path
  of a PNG in the pack (a campaign by hand); a script resource is always inline.
- **`{"$path": "assets/audio/voice/x.wav"}`**: a String (or PackedStringArray element) of a field the class lists in `JSON_PATH_FIELDS`
  (`VoiceIndex.paths`, `MusicCatalog.gm_paths` / `adlib_paths`, `ProblemType.art_dir` / `art_files`). Written relative to the pack, read back as the
  full path of the file in the pack that holds it (`res://packs/dev/assets/...`, `user://packs/x/assets/...`), which `Packs.file_at` serves.
- **`{"$id": "r1", ...fields}`** for a sub-resource the file holds more than once, and `{"$id": "r1"}` for each later use (the same object).
- **`SpriteFrames` and `TileSet`** (`EngineJson`, the only engine classes in the data form; any other is a problem, never a `ClassDB.instantiate`).
  `{"class": "SpriteFrames", "animations": [{"name": "all", "speed": 0, "loop": false, "frames": [{"texture": {"$ref": "..."}, "duration": 2}]}]}`
  (`duration` is left out when 1). `{"class": "TileSet", "tile_size": [16, 16], "physics_layers": [{"collision_layer": 1, "collision_mask": 1}],
  "custom_data_layers": [{"name": "current", "type": 5}], "sources": [{"id": 0, "name": "Zone 0", "texture": {"$ref": "..."}, "region_size": [16, 16],
  "padding": false, "tiles": [{"at": [0, 0], "physics": [[[-8, -8, 8, -8, 8, 8, -8, 8]]], "data": {"0": [-2, -2], "1": 64}}]}]}`: per tile the
  collision polygons of each physics layer (flat lists x, y, x, y) and the custom data by layer; what a tile leaves out is the default.
- Every kind of dev's `data/` has this form: zones, the trigger table, sprite meta, sprite frames, the tile set, timelines, the UI layouts, the text
  tables, the audio catalogs, the voice index and cues, the bubble rules, problem types and layouts; sectors and campaigns keep the data-pack layout.

## Clip lengths

A clip's length in ticks of 1/73 s comes from the pack that holds the clip, and `Packs.clip(kind, name)` returns the stream and the
length (`PackClip.ticks`) of the same pack. A complete pack's are numbers in its data (`VoiceIndex.durations`: the importer's
measurements of the original, or dev's own). The clips of a pack's `audio/` folder are **measured when `Packs` loads the pack** (`AudioStream.get_length()`, rounded
up to whole ticks by `ClipLengths.ticks_of_seconds` with a millionth of a tick of slack; nothing is played) unless the pack **states**
the length in `audio/lengths.json` (whole ticks of 1 or more; the stated number wins). `Pack.clip_ticks / measured_clip_ticks /
stated_clip_ticks` read them; `VoiceIndex.ticks_named` never mixes one pack's stream with another's length. Only speech is waited for.
`Pack.clip_warnings()` (= `ClipLengths.warnings(pack)`) returns one sentence per doubt: no measurable length, a stated length far
from the file's (more than 1 s, `FAR_SECONDS`, or 25 %, `FAR_FRACTION`), a stated length for a clip the pack lacks, a malformed
`lengths.json`. Test: `tests/engine/test_clip_lengths.gd` (synthetic tones in `tests/fixtures/pack_tone_*.ogg.bin`).

## The pack tools

All plain objects in `src/packs/`, so the editor, a terminal, the game and the tests run the same functions.

| | |
| --- | --- |
| `PackCheck.run(pack, options)` -> `PackReport` | the one validation (below); `PackCheck.open(where)` takes a folder or the id of a pack that was found |
| `PackExport.campaign(id, out_dir, options)` / `.complete(id, out_dir, options)` -> `Result` | a campaign as a pack laid over `options.base` (default: the complete pack at the bottom of the chain in use; a folder, or one pack file), a complete pack (`dev`, `legacy`, a copy of dev) in the data form (a folder, or one pack file); a pack is checked first, and a pack with errors leaves nothing behind |
| `PackInstall.install(source)` / `uninstall(id)` | copy a folder to `user://packs/<id>/`, or a `.larissa` pack file to `user://packs/<id>.larissa` (judged by `PackArchive` first, then copied whole); an id is installed in one form at a time (installing either takes the other away), and `uninstall` removes whichever is there; refuses an id the project has in `res://packs/` (`dev` too: a project with no dev takes the installed one); runs nothing |
| `PackCopy.make(new_id, from, title)` | copies `res://packs/<from>` (default dev; with no dev pack it says so) to `res://packs/<new_id>`, rewrites its `res://packs/<from>/` paths, gives every file with a uid a new one, writes a `pack.json` with no `base` |
| `PackChoice.entries()` / `summary()` / `chain_text()` / `any()` | what the pack screen and `--list` say: the packs found, the chain in use and why |
| `src/packs/pack_tool.tscn` | the command line; `addons/pack_tools/` (Project > Tools > "Export pack..." exports a campaign or a complete pack; "Check pack..."; "New pack from dev...") is a window that runs this scene in a process of its own and shows what it prints |
| `src/ui/pack_dialog.tscn` | the player's pack screen (P on the sign-in screen) |

**Validation (`PackCheck`).** The pack is made the chosen pack for the check, with the chain its `base` links make, so the sector checks,
`Campaign.problems`, the readers and the name lookups are the game's own; the chain in use is put back afterwards.
- **Errors** stop a pack: the manifest (`Pack.errors`, a bad `mod` entry among them); the layout (`Pack.problems`); the chain (a `base` not found or with errors, a
  circle); a JSON file that is not JSON or has a field the class lacks; a data file (`data/**.json`) that does not say the
  class its place calls for (`PackNeeds.class_of`: `data/zones.json` is a `ZoneTable`) or is not one the game has; a campaign that is not playable,
  lists a sector in neither this pack nor those under it, or shares a sector with another campaign; a sector whose file says another
  number, has no `.foe`, or fails `SectorChecks` at severity error (the reachability search is `Options.reach`); a speech group naming a
  clip neither the game nor the pack has; a `texts.json` value that is not a string; a `.png` the engine cannot decode;
  `rules/durations.json` (`Durations.check`: known keys only, whole numbers, sensible signs and directions); `rules/tuning.json`
  (`Tuning.check`, on the same `LayeredJson.walk`: known keys only, whole numbers, tables of the length the rules index, entries in range,
  nothing below the floor a rule needs, a cross-key fact the rules cannot run with; [`ARCHITECTURE.md`](ARCHITECTURE.md), "Rule values are
  data"). A mod pack whose entry script is not in the pack, is empty or too large or has no `mod_init(api)` (`PackCheck._mod`). A file the game needs that neither the pack nor the packs under it hold (`PackNeeds`, below). A sector or campaign that a pack under
  it also holds is not an error: the nearest wins.
- **Warnings** do not stop a pack: a `.sgd` file that is never run (not the entry, or a pack with no `mod`); sector-check warnings; `Pack.clip_warnings`; odd durations (no movement, longer than ten minutes, off
  screen); a sector in no campaign; a voice group with no clips; a `fallback_song` or `music_name` that is no song; a `closing_scene`
  that is neither `voyager` nor `expert`; a campaign with no finale; names nothing can refer to; files the game
  never reads; an odd rule value (`Tuning.check`'s warnings: a very fast sub, more air than the console draws); a pack that holds nothing
  the game reads. `PackReport.text()` / `bbcode()` print them, errors first.

**What a chain needs (`PackNeeds`).** One definition of "playable", cheap enough to run at every start (`Packs.choose` runs it) (about 0.1 s on dev and on legacy; only existence
checks and the headers of resources, no sector check, no reachability search, no texture decoded). It takes the chain as an argument (`PackNeeds.chain_of(first)`
makes the chain of a pack with nothing under it, `Packs.resolve(first, [], false)`; a chain that is not the one in use is lent to `Packs` for the question) and answers
with `gaps(chain, skin)` (`PackNeeds.Gap`: `group`, `path`, `needed_by`, `soft`), `missing(chain, skin)` (the paths, sorted), `required(chain, skin)` (everything the closure
asked for), `is_complete`, `by_group`, `hard(gaps)` / `soft(gaps)` and `summary(gaps, limit)` ("7 missing: a, b, ... and 5 more"). Four layers, each derived from what the code asks for:
- **Whole files** a complete pack provides: the list `PackNeeds.FILES` (the one place the list is declared), the text tables (`Catalog.TEXT_TABLES`), the sets of each zone
  (`PER_ZONE` for `Catalog.ZONE_COUNT` zones, `PER_TILE_ZONE` for the art zones), and the problem types (`Catalog.PROBLEM_TYPE_COUNT`; a `.tres` of a complete pack or a
  `.json` of a pack in the data form). `test_pack_needs.gd` and `test_pack_needs_legacy.gd` keep the list equal to what dev and legacy hold under `data/` (bar sectors, campaigns and
  problem types), so a new file the engine loads is added to `FILES` or the tests fail.
- **Pictures asked for by name**: every `ui_picture` and `problem_art` name of the registry (`Assets.ui_picture_rel`, `problem_art_rel`).
- **Things the data names**, which live inside the pack that holds the resource: what each required `.tres` refers to (`ResourceLoader.get_dependencies`, so the tiles, sprites,
  sounds and layouts' pictures), the files of each problem type's art, the songs of the music catalog, the clips of the voice index.
- **What the content brings**: for each campaign `Catalog` finds, its sectors (a sector as JSON needs its `.foe`, a sector as a `.tres` its files), its finale picture and the speech
  groups of its log and supply messages (the last two are `soft`: the game goes on without a picture or a spoken line). The tiles, creature pictures and sounds a sector uses are
  slots of its zone's sets and of the sound catalog, so they are required above; a sector's background is not (a screen without one is plain black), nor is a MIDI file (the rendered
  song plays).

A **skin** is a parameter. A picture that a mounted pack's `pictures/` folder holds, or that the skin handed in maps (`GameSkin.picture`), counts as present for the pictures asked for
by name and for a problem type's art; a resource's own pictures are never covered, because Godot loads them with the resource. Neither the start-up check
(`Packs.choose`) nor `PackCheck` passes one, because a pack is complete by itself whatever skin a player turns on; they ask no skin at all (`Catalog.problem_type_unskinned`), which
also keeps them working in the editor, where a skin is only a placeholder.

`PackCheck` runs it on the chain the pack is used in, unless that chain cannot be made (the base error says so): one error per group,
with a few names. A pack over a complete base misses nothing the base holds; a complete pack that lacks a file is an error, and so is a base that lacks one. The campaigns' own
gaps are left to the campaign checks. `PackCheck.Options.needs` turns it off. The sector checks read the game's files (the trigger table among them), so with a file of the
group `files` missing they are not run on the pack's sectors: the `needs` error names the file (with `needs` off, each sector says it cannot be checked).

**Exporting a campaign.** The campaign (a `.tres` of the project, or one from a pack of the chain), its own sectors as JSON + `.foe`, and
what it uses that the game does not have: the **pack source folder** `res://data/campaigns/<id>/`, laid out as a pack
(`pictures/ui_picture/finale.png`, `audio/voice/line.ogg`, `texts.json`, `voice_cues.json`, `rules/durations.json`,
`data/problems/*.json`; `.import` and `.uid` files are left behind), or a pack's own files. A picture named by a `res://` path
(`finale_picture`, `banner`) is copied in as `pictures/ui_picture/<name>.png`. The export is checked and a failed one is removed.

**Exporting a complete pack.** `PackExport.complete(id, out_dir, options)` (`id`: `dev`, `legacy`, a copy of dev, an installed complete pack) writes
`<out>/<pack id>/` (or a `.larissa` pack file) in the data form, so that nothing of it is a `.tres`, a scene or a script: `pack.json` with no `base`,
every `data/**.tres` as the `.json` `ResourceJson` / `EngineJson` describe at the same place, each sector as `sectors/sector_NN/` (`SectorJson`: JSON and `.foe`),
each campaign as `campaigns/<id>.json`, and every other file the pack holds (`assets/`, `midi/`, `rules/`, `data/problems/problem_art_index.json`) as it is, but for
the editor's `.import` and `.uid` files. `options.pack_id`, `title`, `version`, `author` and `description` set the manifest (the source's by default; `base` is refused).
The result is checked like any export, with the pack alone in its chain: the data files parse to their classes, the closure (`PackNeeds`) holds, and a `.tres`,
scene or script is refused. The export can be chosen (`--pack=<id>` after it is installed or in `user://packs/`, or `Packs.use`) and the game plays from it.
`tests/legacy/test_pack_export_legacy.gd` round-trips all of legacy through it field by field, and `NEPTUNE_LEGACY_AS_DATA=1` makes the legacy suite play it
([`DEVELOPING.md`](DEVELOPING.md)).

**From a terminal** (repository root; options after `--`, run in the order install, uninstall, new, check, export, list; `--pack=<id>`
chooses the pack the checks and exports see; exit code 1 for an error or a failed step, 2 for a bad option):

```
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --list
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --check=/path/to/folder_or_installed_id [--no-reach]
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --export-campaign=orchard --out=/path/out [--archive] [--base=dev] [--pack-id= --title= --version= --author= --description=]
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --export-pack=legacy --out=/path/out [--archive] [--pack-id= --title= --version= --author= --description=]
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --install=/path/orchard.larissa      # also --uninstall=orchard
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --new=orchard --from=dev --title="Orchard"   # then --import
```

**The pack screen** (`PackDialog`, P on the sign-in screen): the packs found ("project" or "installed", "in use" / "base"), the chain and why
(`PackChoice.summary()`), details, Check (the quick check: no reachability search, `PackChoice.check_options`; a pack outside the project is read as data and its one kind of code is a sandboxed mod, so no pack asks for trust),
Install... (a folder or a `.larissa` pack file; `dev` too, when the project has none), Remove. A small **Packs** button appears beside the player
list only when a pack the player installed is in `user://packs/` (not the `legacy` and `dev` pack files a game carries next to it), so a game with no pack installed looks as the original did. Nothing is switched
there: `--pack=` chooses.

## Mod packs

A **mod pack** is an ordinary pack (same folder, `pack.json`, door and chain) whose manifest also has a `mod` entry: a SafeGDScript (`.sgd`) script that [godot-sandbox](https://github.com/libriscv/godot-sandbox) runs with restrictions on. The user-level description is
[`../create/CONTENT.md`](../create/CONTENT.md), "Mod packs"; the extension is fetched, not committed ([`../SETUP.md`](../SETUP.md)).

```
"mod": {"entry": "orchard.sgd", "requires_api": 1, "limits": {"execution_timeout": 100, "memory_max": 16}}
"mod": {"entry": "reef.sgd", "requires_api": 2, "skin": {"shaders": ["skin/glow.gdshader"]}}      // a skin mod
"mod": {"requires_api": 5, "skin": {"render": {"texture_filter": "linear"}, "pictures": {"ui_picture/title_sky": "skin/sky.png"}}}   // a data skin: no script
"mod": {"entry": "tides.sgd", "requires_api": 3, "problems": {"types": [40], "shaders": ["problems/glow.gdshader"]}}   // a mod that draws the screen of problem type 40
"mod": {"entry": "rules.sgd", "requires_api": 4, "rules": {"answers": [41], "instructions": [0, 1], "sub": true}}   // a mod with rule hooks, for the campaigns that declare it
```

- **The manifest entry** (`ModSpec.parse`, read by `Pack` into `Pack.mod`; every mistake is a sentence in `Pack.errors`). `entry` is a plain file name ending `.sgd` in the pack's root (no folder, no `..`); only a skin may leave it out (a data skin: `ModSpec.has_entry`). `requires_api` (default 1) is the lowest
  API version the script needs; `ModSpec.API_VERSION` (5) is what the game provides and a pack that needs more is refused (a mod that asks for 1 still runs: the version goes up when the API gains something, `ModSpec`). `skin` makes the mod a skin (below) and needs `requires_api` 2; its `shaders` list the `skin/<name>.gdshader` files the skin may use (at most `ModSpec.MAX_SHADERS`), `render` (`texture_filter` by the names of `RenderSettings.FILTER_NAMES`, `snap_transforms`, `snap_vertices`) is the `RenderSettings` it wears and `pictures` maps skin keys of the kinds `ModSpec.PICTURE_KINDS` (`ui_picture/<name>`) to PNGs of `skin/` (at most `ModSpec.MAX_PICTURES`); a skin with `render` or `pictures`, or with no `entry`, needs `requires_api` 5 (`ModSpec.DATA_SKIN_API_VERSION`). `problems` makes the mod draw problem screens (below) and needs `requires_api` 3: `types` (whole numbers from `Catalog.PROBLEM_TYPE_COUNT` to `Catalog.LAST_PROBLEM_TYPE`, at most `ModSpec.MAX_PROBLEM_TYPES`, each once) and `shaders` (`problems/<name>.gdshader`). `rules` gives the mod rule hooks (below) and needs `requires_api` 4: `answers` (problem types from 34 to 255 whose answers it judges, at most `ModSpec.MAX_PROBLEM_TYPES`, each once), `instructions` (the numbers 0 to `RuleHooks.MAX_INSTRUCTIONS - 1` of the creature instruction `Mod_Instruction` it defines) and `sub` (true: a sub ability), at least one of them. `limits` is optional, each key too: `execution_timeout` (millions of instructions per call into the mod, 1 to 200), `memory_max` (MiB, to 32),
  `allocations_max` (to 8000), `references_max` (to 100), `coroutines_max` (to 32). Every value is clamped to 1 up to the game's ceiling (`ModSpec.MAX_*`, the numbers of the godot-sandbox example's loader): a manifest can lower a limit and never raise it, and a request for 0 is 1 (the Sandbox does not count instructions at 0, and a mod that is not counted could hang the game from any callback it defines, `_process` included). A mod that draws (a skin, problem screens) is called while the player waits for a frame, so its `execution_timeout` goes up to `ModSpec.MAX_DRAWING_EXECUTION_TIMEOUT` (10): one that never returns costs a frame that much. A mod with `rules` is called inside the tick, so its limit is the lowest the Sandbox counts, 1 million (`ModSpec.MAX_RULE_EXECUTION_TIMEOUT`), and it is the lowest of the ceilings of a mod that is a skin too.
  `ModSpec.functions` is the one list of the functions the script must define for what the manifest lists (`skin_frame` for a skin that has an `entry`, `problem_frame`, the function of each rule hook; their argument counts), and `ModParts.make` the one judgement of what the pack must hold (below). `PackCheck` looks at the files (a mod that has an `entry`: the entry is in the pack, within `ModSpec.MAX_SOURCE_BYTES`, with a `mod_init(api)` and each function of `ModSpec.functions`, and what `ModParts.problems` says); whether the script compiles only the Sandbox can say, when the mod is loaded (`ModHost.failure`).
- **Without the extension** (`ClassDB` has no `Sandbox`: `ModLoader.sandbox_available()`) `Pack` adds `ModLoader.missing_extension_text()` to the manifest's errors, so a mod pack is a pack with errors: listed by the pack screen, never the default choice, and a chain with it is the
  `BROKEN` fallback of "Finding and choosing" with that reason. Nothing crashes, and a data pack never needs the extension, nor does a data skin (`ModSpec.has_entry` false: `Pack` asks for the extension only of a mod with a script). `ModLoader.pretend_no_sandbox` plays a build without it in a test.
- **Trusted or not, a mod is sandboxed.** A mod's script is never a script of the game: `ModLoader` compiles it into a `SafeGDScript` set on a bare `Node` and sets the restrictions and limits before the script's member initializers run. The only code a pack outside the project may hold is that `.sgd` file;
  `.gd`, `.gdc`, `.cs`, native libraries (`.so`, `.dll`, `.dylib`, `.gdextension`), `.elf` and the rest of `Pack.RESOURCE_EXTENSIONS` stay refused, in a mod pack as in any other.
- **The loader** (`src/mods/mod_loader.gd`, adapted from the `ModLoader` of godot-sandbox's `examples/modding`, BSD-3-Clause). The mod's id is its pack's id. Restrictions are always on: the mod reaches only the objects granted to it, and of those only the properties and methods the policies allow
  (`ModApi.property_allowed`, `method_allowed`: they allow nothing); a mod's own `load("...")` is refused whatever the path. Every call into a mod (`mod_init`, `mod_deinit`, `skin_frame`, `problem_frame`, a rule hook) is `ModLoader.call_mod`: the container arguments are made read-only (`ModLoader.freeze`), an error or a timeout is read from the Sandbox's counters and comes back as `{"ok": false, "why": ...}` (the caller decides what a fault means to it), and a container the mod hands back is copied with `ModLoader.detach` before the game keeps it. A mod that raises `MAX_FAULTS` times
  is quarantined (its frame and input callbacks stop; the others go on) and `check_health` counts the faults every frame. A script that does not compile, has no `mod_init(api)`, or raises while it starts is refused with the reason (`mod_failed`).
- **The API** (`ModApi.build`, the one place that decides what a mod is granted; the header of `src/mods/mod_api.gd` lists it): `api_version`, `id`, `log(message)`, `load(path)`, for a skin `skin` (plain facts: the tile grid, the caps, the listed shaders) and, for a mod that draws problem types, `problems` (plain facts: the types, the window, the caps, the listed shaders) and, for a mod with rule hooks, `rules` (plain facts: what it lists, the calls a tick allows, the bounds of its memory and of a move). `load` gives a picture, sound or resource of the mod's OWN pack through the pack's door (`Pack.file`); a path that is not a plain relative path of the
  pack, or a file it lacks, gives null. The loaded object is granted to the mod (it may hold it and hand it back) and the policies allow it nothing more. A mod gets nothing else: not the tree, not an autoload, not another pack, not a file by path.
- **The owner of the running mods is `ModHost`** (`src/autoload/mod_host.gd`, the autoload `Mods`). The mods that run are derived from `Packs.chain()`, each with one record, its `ModParts` (the `ModSkin` and the `ModProblems` its manifest asks for, and the key it runs under): `ModHost.wanted()` is the packs of the chain that carry a `mod`, bottom of the chain first, and `sync()` makes the running mods exactly those, each under a key
  (the pack's folder, the script's name and the file's time; a data skin's file is its manifest), loading the script of what is new (a data skin has none: `ModHost.mod` is null for it, and `loaded_ids()` lists it with the others) and unloading what left the chain or whose key changed. `Packs.events.changed` marks the host stale and the sync runs at the next idle moment, so a pack borrowed and put back inside one call
  (`PackCheck`, `Packs.lend`) costs no reload; `loaded_ids()`, `ModHost.mod(id)` and `ModHost.failure(id)` sync first when the chain changed (`ModHost.mod(id, false)` does not: a presenter asks in the middle of a frame, where a sync could swap the presenter itself). `mod`, `failure`, `is_quarantined`, `skin`, `skin_ids`, `problem_screen` and `rule_mod` are static, for code with no node. The lifetime is in [`ARCHITECTURE.md`](ARCHITECTURE.md), "Lifetimes of state". Nothing in `src/rules/` asks the host anything: a campaign's run resolves the mods it declares once, when it begins (`ModHooks.resolve`, which asks `ModHost.rule_mod`), and the rules hold the table that came out, so the original campaigns run none.
- **A skin mod** (`"skin"` in the manifest; the user-level guide is [`../create/SKIN_API.md`](../create/SKIN_API.md), "Writing a skin mod") is a skin like the project's own: `ModHost` makes its `ModSkin` (a `GameSkin` with the pack's id, mapping only the manifest's `render` and `pictures`, whose presenter scene is `ModPresenter`, or the original's for a data skin) when the mod loads, and
  `SkinChoice.available` / `load_skin` offer it, so `--skin=<id>`, F3 then S, the compare tool and the tests choose it like any skin. The mod's script defines `skin_frame(state, fraction, events)`; the presenter calls it from `show_between_ticks` and `refresh` and **nothing is granted**: the state is plain data built from
  `SimView` (`SkinState.build`: Dictionaries, numbers, places, read-only), the answer is a draw list (`ModDraw`: `rect`, `line`, `picture`, `region`, `text`, `layer`) that the game checks command by command, copying what it keeps, and draws in `ModLayer` nodes of its own, inside the playfield's clip. A picture is a PNG under the pack's own
  `skin/` folder (the folder is the `ModAssets` of the mod, with its compiled shaders), read with `Pack.texture` of that pack (never the chain's lookup, so another pack's file is out of reach); a shader is a text file listed in the manifest, held to a small language by `ModShader` (`canvas_item`, at most `ModShader.MAX_BYTES`, no preprocessor, no loops) and compiled by the game, and a layer names it by path; a layer that names any other shader draws nothing. A skin whose
  id is one of the project's skins, whose shader or picture is refused, whose mapped picture is not in the pack, or that has an `entry` and defines no `skin_frame` is refused with the reason (`ModParts.make`, `ModLoader.missing_functions`, `PackCheck`, `ModHost.failure`). A **data skin** (no `entry`) is the same `ModSkin` with no script: `ModSkin.make` puts the manifest's `render` (a copy of `ModSpec.render`) in `GameSkin.render` and each `pictures` entry, read with `Pack.texture` of the pack (the same door as above), in `GameSkin.pictures`, and leaves `presenter_scene` empty, so the sector is shown by the original presenter; `GameSkin.picture` asks the packs' `pictures/` first and then the skin, so the skin's pictures are worn only while it is the skin in use. It loads no script, so it runs in a build without the extension. The skin lives as long as its mod: when the mod is unloaded or quarantined, `SkinChoice.leave_dead_mod_skins` puts the original on, and a presenter bound to a mod that is gone draws nothing and asks nobody.
  A frame the script spoils (an error, a result that is not a list) leaves the last good one on; a script that faults `ModLoader.MAX_FAULTS` times is quarantined. The rules never wait for it and never hear of it: `test_plays_identically` and `test_skins_dont_change_the_game` play a good skin mod and a faulty one with every other skin.
- **A mod that draws problem screens** (`"problems"` in the manifest; the user-level guide is [`../create/CONTENT.md`](../create/CONTENT.md), "Problem screens") adds problem types as DATA and draws their picture; the answer checking is the game's. The pack holds each type as `data/problems/problem_type_NN.json` (NN from 34), found through the same door as a data pack's
  (`Catalog.problem_type`; `Catalog.problem_type_ids` lists the original's 34 and then the types the chain has, for the debug menu, Math Practice "All" and `PackNeeds`), worded by the type's own texts (`ProblemTexts._added`) and judged by its `compare_mode` and answer fields (`AnswerChecker`), and its diagram family is `mod`.
  `ModParts.make` judges the manifest through `ModProblems.make` (`PackCheck`, `ModHost`): each type is a file of the pack that `ModProblems.check_type` accepts (the data form, a `ProblemType`, its id) with the family `mod` and records; the shaders and pictures of `problems/` (`ModAssets`); and the script defines `problem_frame(state)`. `ModHost` keeps the `ModProblems` in the `ModParts` of each running mod and answers `problem_screen(type_id)`: the mod whose pack
  holds the type, while it runs and is not quarantined. **One builder:** every way of opening a problem (the game, Math Practice, the debug menu, a tool, a test) instantiates `ProblemScreen`, whose `start` calls `DiagramFactory.create`, which makes a `ModDiagram` for the family `mod`; `test_mod_problems` scans that nothing else makes one. `ModDiagram` is a `DiagramBase` that, when `ModHost.problem_screen` has a mod, calls
  `problem_frame(state)` with `ProblemState.build` (the values of the record, the `entry` the calculator or the answer box shows, the `step`: no verdict, tries, oxygen, hint or solution) and draws the checked list in `ModLayer` nodes; it asks again only when the state's hash changes (`DiagramBase.entry_changed` and `step_changed`, which `ProblemScreen` calls from `Calculator.entry_changed`, `AnswerBox.entry_changed` and the flow's
  `step_changed`). **The fallback** is the diagram the type's data describes (`items`): it shows until the mod has returned a good list, and again when the mod is absent, unloaded or quarantined at the next change; a spoiled frame leaves the last good one. The picture has no animation (`ModDiagram` schedules none), so no step of a problem is longer or shorter. A type of a mod that is not in the chain is not asked
  (`ProblemFactory` skips a trigger pick whose type the chain lacks); the original campaigns run on a chain without the pack. Nothing the script returns reaches `ProblemSession`, `ProblemFlow`, `GameState` or the clock.
- **A mod with rule hooks** (`"rules"` in the manifest; the user-level guide is [`../create/CONTENT.md`](../create/CONTENT.md), "Rule hooks") adds gameplay inside the tick, for a campaign that declares it in `Campaign.mods`. `ModHost` refuses the mod when the pack lacks a type it judges as data or the script lacks a hook it lists
  (`ModParts.make`, which asks `ModProblems.check_type` for each type it judges, and `ModSpec.functions`; `PackCheck` tells the author). The resolution into the run's `RuleHooks`, the three hook points, what each is told and may answer, the lifetimes, the limits and the defaults of a fault are in [`ARCHITECTURE.md`](ARCHITECTURE.md), "Rule hooks"; `Mod_Instruction`, the creature instruction, is in
  [`../create/FOE_SCRIPTING.md`](../create/FOE_SCRIPTING.md). Nothing a hook returns reaches the game but through `RuleHooks`' validators.
- **What the Sandbox does not bound.** It counts the guest's instructions and memory (a loop that never ends is a timeout, a call chain that never returns is out of memory, both contained), not the data a mod builds in the host: a string it doubles forty times or a `PackedByteArray` it resizes to gigabytes exhausts the
  game's memory (`docs/ROADMAP.md`, Open items).
- **Exports.** The Linux and Windows presets carry `addons/godot_sandbox` (the library of the platform, `gdscript.elf` which the extension loads by path, the licences), the library of the platform is written next to the executable of a Linux or Windows export and beside `index.html` of the Web one, and the Web preset uses the extensions template (`variant/extensions_support`). `PackExportFilter` still keeps every pack out of a game export; a mod pack reaches a game as a pack file like any other.
  `PackExport.complete` keeps a complete pack's `mod` entry.

Tests: `test_mod_rules.gd` (a rule-hook mod end to end: the manifest, the pack check, the campaign's declaration and its resolution, each of the three hooks, the faults of a misbehaving mod, the hostile `tests/mods/rules_chaos`, a whole visit played twice, what installing a mod pack asks), `test_rule_hooks.gd` (the table with a double for the sandbox: what is validated and cut, the defaults of a fault, the memory, the budget, the creature instruction in the VM, the sub in the tick, the verdict on an answer, and that a run with no hooks makes no call), `test_mod_problems.gd` (a problem-screen mod end to end: the manifest, the type as data, the text command, the screen and its fallbacks, the same play under a good, a hostile and a faulty mod and none, the hostile `tests/mods/tides_hostile`; the document pinned), `test_mod_skin.gd` (a skin mod end to end: the manifest, the shader text, the draw list against every kind of garbage, the skin chosen and worn, its lifetime, a faulty skin, the hostile skin `tests/mods/skin_hostile`; `tests/legacy/test_mod_skin_legacy.gd` draws every screen of the original), `test_mod_manifest.gd` (`ModSpec`, the manifest, `PackCheck`, the refusals), `test_mod_pack.gd` (a real mod of `tests/mods/`: loaded from the chain, `log`, `load`, the mods derived from the chain, a faulty mod quarantined, a mod over its limits stopped, a mod that asks for no limit held to the lowest with a `_process` that never returns stopped (`tests/mods/process_spinner`), and the hostile mod `tests/mods/hostile`: every `try_*` is refused and the
game is as it was, every `check_*` of the API gets nothing; a build without the extension), `test_state_lifetimes.gd` (`ModHost`'s fields). They need the extension (`uv run tools/fetch_sandbox.py`); `PackShelf.add_mod_fixture` makes a scratch pack of a fixture folder of `tests/mods/` (its folders too), `tests/mod_skin_shelf.gd` (`ModSkinShelf`) mounts the skin fixtures with their pictures `tests/mod_problem_shelf.gd` (`ModProblemShelf`) the problem-screen fixtures with the type they draw and `tests/mod_rule_shelf.gd` (`ModRuleShelf`) the rule-hook fixtures with their type, two sectors and two campaigns (one declares the mod).

## Tests

`tests/engine/test_pack_chain.gd` (choosing, the default, the fallbacks and their reasons, `dev` reserved), `test_pack_start_check.gd` (the check at choice, the two modes, the sentences by situation), `test_packs.gd` (manifest,
trust, every lookup), `test_pack_archive.gd` (`PackArchive`: the index, every limit and refusal, deflated and stored entries), `test_pack_file_plays.gd` (dev as a pack file: every lookup, a sector, the tools), `test_pack_paths_go_through_pack.gd` (the source scan of the path door), `test_pack_bundled.gd` (the bundled pack files, used in place, never over a pack of the project; an installed dev), `test_pack_no_dev.gd` (no dev, an installed dev), `test_pack_warning.gd` (which scene opens; the debug screen and the release refusal), `test_resource_json.gd` (dev's campaigns, sectors and problem types through JSON
and back), `test_pack_campaign.gd` (a three-sector campaign that exists only as a scratch pack over dev, played through
`GameFlow` to the generic finale), `test_pack_check.gd` (every rule, one thing wrong at a time), `test_pack_needs.gd` (the closure on dev, on packs that lack files, with and without `dev` under the chain; legacy: `tests/legacy/test_pack_needs_legacy.gd`), `test_pack_export.gd`,
`test_pack_install.gd` (a campaign exported, installed into `user://packs/`, chosen, offered in the new-player dialog and played to the
Hall of Fame), `test_pack_dialog.gd`, `test_pack_tool.gd` (the real tool in its own process: output, exit codes, the editor window's
arguments), `test_pack_copy.gd`, `test_clip_lengths.gd`, `test_durations.gd`. The door and the data form: `test_data_form.gd` (every `.tres` of dev's `data/` to JSON and back,
equal field by field; `$ref`, `$path`, `$id`, tags, the two engine classes), `test_pack_door.gd` (dev exported whole by `PackExport.complete` into a scratch pack in `user://`,
chosen: the game's lookups answer from it and nothing of it reaches `ResourceLoader`), `test_pack_export_complete.gd` (the export of dev: what it holds, its manifest, the
check accepting it and refusing a `.tres`, a scene or a script put into it, a wrong class or field, a missing file; a pack file; the options), `test_no_direct_loads.gd` (the scan for a `load(` outside the door);
`tests/legacy/test_pack_export_legacy.gd` (all of legacy exported, then every kind, sector, screen, script and campaign equal field by field, every other file the same bytes).
Helpers: `tests/pack_shelf.gd` (scratch packs over the chain; `PackExport.complete` into a shelf's folder fills it), `tests/resource_compare.gd` (the deep comparison, with pictures
and sounds compared by the file they came from, and `pack_roots` to compare a pack with its export).
