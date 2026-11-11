# Setting up your machine

Everything you install to work on Operation Larissa: what each tool is for, where to get it, and how
to use it.

The author uses Fedora Linux, and all custom tools are written for that environment and tested
there.  (Feel free to test elsewhere / make a pull request.)  Everything which is Godot runs
wherever Godot runs.  Content packs don't care what platform you're on.

## Quick start

We use [mise](https://mise.jdx.dev/) (very similar to homebrew) as much as possible to ensure the
correct project-specific tooling across distros.  It is not required, and you can provide your own
installations for everything, but it is our happy path documented here.  More on that below, if
that's you.

You will need to first install mise and activate it in your shell (`mise activate`). If you prefer
Fedora COPR, it's available via `jdxcode/mise`.  We also include some mise "tasks" which are just
predefined scripts for convenience.  Investigate `mise.toml` if you want to see what any `mise run`
command below is doing.

Then run everything here from the repository root.

### For the engine: use the editors, run the tests

```sh
mise run setup              # installs uv, Godot 4.7.2 and a JDK (the versions mise.toml pins), then the Python environment (.venv) and the godot-sandbox extension
mise run godot:import       # Godot imports the project, once in a fresh checkout
mise run test:engine        # the engine's tests, on the dev pack
mise run godot:editor       # the project in the Godot editor
mise run godot:play dev     # play: the dev pack's placeholder game
mise run lint:tools         # ruff and pyright on the Python tools
```

### For the legacy importer: build the original game from your CD

All of the above, and also:

```sh
sudo dnf install ffmpeg-free fluidsynth fluid-soundfont-common fluid-soundfont-gm   # the music
cp /path/to/your/copy.iso NEPTUNE.ISO   # or: export NEP_ISO=/path/to/your/copy.iso
mise run legacy:checktools              # is every tool here? It names what is missing and how to get it
mise run legacy:import                  # NEPTUNE.ISO -> the legacy pack (about 10 minutes; plan on 1 GB free)
mise run test:legacy                    # the tests of the original game, on the legacy pack
mise run godot:play legacy              # play the original
mise run godot:pack legacy              # ./legacy.larissa, for an exported game (any pack id works; --out <dir>)
mise run release:build_linux            # the exported Linux game in build/game, legacy.larissa beside it (fetches the export templates)
mise run release:build_web              # the exported Web game in build/web, legacy.larissa beside index.html
mise run release:build                  # both
mise run release:play                   # play the Linux one
```

Importer options go after `--`: `mise run legacy:import -- --only audio`. What the importer does,
its options, and what to do when it refuses: [`play/LEGACY.md`](play/LEGACY.md).

### For AI coding assistants: the Godot editor over MCP

Optional. The project carries the [Godot AI](https://github.com/hi-godot/godot-ai) editor plugin (`godot/addons/godot_ai`, already
enabled). It runs an [MCP](https://modelcontextprotocol.io/) server, so an assistant such as Claude Code or Codex can look at the open
editor: the scene tree, node properties, logs, screenshots, the gdUnit4 tests. It works only while the editor is open:

1. `mise run godot:editor`; the plugin starts its server by itself (through `uv`, which `mise run setup` installed).
2. In the editor's **Godot AI** dock, pick your assistant and press **Configure**; it writes that assistant's MCP settings.
3. Restart the assistant in the repository root; it now has the `godot-ai` tools.

The assistant still needs the repository's own instructions: `AGENTS.md`.

### To run the original Windows game under Proton

Optional, and only for checking the port against the original. The tasks that install and run the original under Steam's Proton live
in `mise.proton.toml`, a mise config environment you opt into: `mise -E proton run <task>` for one command, or
`export MISE_ENV=proton` for a shell (then a plain `mise run <task>`). Without it, mise loads only `mise.toml` and these tasks and
their `PROTON` / `STEAM_COMPAT_*` variables do not exist.

You need Steam with *Proton Experimental* installed, your `NEPTUNE.ISO` in the repository root, and:

```sh
sudo dnf install 7zip xxd fluidsynth fluid-soundfont-common fluid-soundfont-gm   # unpacking the CD, patching, the music
mise -E proton tasks                       # what each task does
mise -E proton run install                 # unpacks NEPTUNE.ISO into iso/, creates the Wine prefix in prefix/, installs the game
mise -E proton run play                    # presents iso/ as drive D:, starts FluidSynth for the MIDI music, runs the game
mise -E proton run dpi 144                 # optional: Wine UI scaling (96 = 100%, 144 = 150%, 192 = 200%)
```

`SOUND=adlib mise -E proton run play` plays the AdLib set of songs instead of General MIDI (with `soundfonts/opl.sf2` when you have
it). Proton is looked for at `~/.steam/steam/steamapps/common/Proton - Experimental/proton`; another one goes in `mise.local.toml` as
`[env]` `PROTON = "/path/to/proton"`. Using the original to measure the port: [`port/FIDELITY.md`](port/FIDELITY.md), "Comparing
with the original game".

## mise, and using your own installs

mise is the default, not a requirement. The scripts call the plain names (`uv`, `godot`, `java`, `ffmpeg`), never `mise exec`, so
whatever install comes first on your `PATH` is the one that runs. You can opt out of any mise tool and use your own:

- **Leave one tool out**: `export MISE_DISABLE_TOOLS=godot` (a comma-separated list) and mise neither installs nor activates it, so
  your own install on the `PATH` is used.
- **Pin another version**: a `mise.local.toml` in the repository root (git-ignored) overrides `mise.toml`, for example
  `[tools]` `java = "temurin-21"`.
- **Point at a binary**: `GODOT_BIN` for Godot ("Godot"); `JAVA_HOME` for the JDK; `GHIDRA_INSTALL_DIR` for Ghidra;
  `--soundfont` for the importer's soundfont.
- **No mise at all**: install the tools yourself and put them on the `PATH`. The Proton tasks for running the original are mise
  tasks (`mise.proton.toml`), so they need mise.

The pinned versions (`mise.toml` for Godot, `uv.lock` for the speech engine) are the ones the project tests and supports. Where a
version matters, the tools check it and print a loud `WARNING` when it differs, then go on, so you can try a beta or your
distribution's build. Fedora's own `godot` package is 4.7.1, for example: the importer warns and runs with it. What breaks on another
version is yours to find.

## The tools

| Tool | Needed for | Get it | Notes |
| --- | --- | --- | --- |
| mise | everything | [mise.jdx.dev](https://mise.jdx.dev/) (installer or COPR `jdxcode/mise`) | Installs uv, Godot and the JDK. Runs the tasks of `mise.toml` and the Proton tasks (`mise.proton.toml`). |
| uv | every Python tool and test | `mise install` | uv fetches Python 3.12 or newer as `pyproject.toml` asks. See "The Python environment". |
| Godot 4.7.2 | the game, the editors, the tests, the importer's last step | `mise install` | The official Linux build, as `godot`. See "Godot". |
| Godot export templates 4.7.2 | exporting a runnable game (Linux, Windows, Web) | `mise run godot:fetch_templates` (`tools/fetch_export_templates.py`: the pinned release's archive, 1.3 GB, checked against its SHA-512; only the templates of our presets are kept), or Editor > Manage Export Templates | They go to `~/.local/share/godot/export_templates/4.7.2.stable/` (`$XDG_DATA_HOME`). `mise run release:build_linux` / `release:build_web` fetch them when they are missing. Making a pack file (`pack_tool --export-pack ... --archive`) needs none. [`engine/DEVELOPING.md`](engine/DEVELOPING.md), "Exporting builds". |
| godot-sandbox 0.60 (a GDExtension) | running a mod pack's SafeGDScript; the mod tests (`test_mod_*`); exporting a game that can run mod packs | `mise run setup`, or `uv run tools/fetch_sandbox.py` | Downloaded from the [GitHub release](https://github.com/libriscv/godot-sandbox/releases/tag/v0.60) over HTTPS, checked against the SHA-256 pinned in `tools/fetch_sandbox.py`, and extracted into `godot/addons/godot_sandbox/` (git-ignored; only the Linux, Windows and Web libraries, `gdscript.elf` and the licences). Run `godot:import` after the first fetch, so Godot learns of the extension. The game plays without it and every data pack works; a mod pack is refused with the reason, and the mod tests fail naming this step. Opt out by not fetching (`mise run setup` is `uv sync` plus the fetch; `uv sync` alone is enough for everything but mod packs). [`engine/PACKS.md`](engine/PACKS.md), "Mod packs". [github.com/libriscv/godot-sandbox](https://github.com/libriscv/godot-sandbox). |
| Godot AI (editor plugin and its MCP server) | optional: an AI assistant working in the open editor | in the repository (`godot/addons/godot_ai`); the server comes through `uv` | Quick start above, "For AI coding assistants". [github.com/hi-godot/godot-ai](https://github.com/hi-godot/godot-ai). |
| `ffmpeg` with the libvorbis encoder | the importer's `audio` step; the dev pack's `audio` stage | `sudo dnf install ffmpeg-free` | RPM Fusion's `ffmpeg` works too. |
| `fluidsynth` | the importer's `audio` step (MIDI to WAV); the Proton tasks' MIDI | `sudo dnf install fluidsynth` | |
| A General MIDI soundfont | the importer's `audio` step | `sudo dnf install fluid-soundfont-common fluid-soundfont-gm`; Windows: `uv run tools/fetch_soundfont.py` (`mise run setup` runs it) | Installs `/usr/share/soundfonts/FluidR3_GM.sf2`, the importer's default on Linux; on Windows the default is `soundfonts\FluidR3_GM.sf2`, from Debian's `fluid-soundfont-gm` package (version and SHA-256 pinned). `--soundfont` names another. |
| `soundfonts/opl.sf2` | optional: the AdLib set of songs | your own copy (135 MB) | Not in the repository, git-ignored. Without it the AdLib set sounds like General MIDI. See [`play/LEGACY.md`](play/LEGACY.md), "Soundfonts". |
| The speech engine (faster-whisper, CTranslate2) and its model | the importer's `transcripts` step (`--no-transcripts` leaves it out) | `uv sync` | Pinned versions. The model (about 480 MB) is downloaded on first use. |
| Piper text-to-speech | regenerating the dev pack's audio | `uv run --group dev-pack ...` | Not installed by default. Its voice (63 MB) goes to `~/.cache/neptune-dev-pack/` on first use. [`../tools/dev_pack/README.md`](../tools/dev_pack/README.md). |
| Steam with *Proton Experimental*, `7z`, `xxd`, PipeWire | running the *original* game under Wine (the `mise -E proton run` tasks) | Steam; `sudo dnf install 7zip xxd` | The Proton path is `PROTON` in `mise.proton.toml`. Quick start above. Music also needs `fluidsynth` and the GM soundfont. [`port/FIDELITY.md`](port/FIDELITY.md), "Comparing with the original game". |
| A JDK 21 or newer | the Ghidra workflow | `mise install` (Temurin 25) | |
| Ghidra 12.2 | decompiling `ONWIN32.EXE` | [ghidra-sre.org](https://ghidra-sre.org/) | Ghidra at `~/.local/bin/ghidra/ghidra_12.2_PUBLIC` (or `GHIDRA_INSTALL_DIR`). `mise run ghidra:import` builds the project with our names, `mise run ghidra:gui` opens it ([`port/GHIDRA_GUI.md`](port/GHIDRA_GUI.md)). [`../tools/analysis/ghidra/README.md`](../tools/analysis/ghidra/README.md). |

The importer checks its own tools before it writes anything and refuses with the list of what is missing
(`tools/import/tool_check.py`). A tool that is there at another version than the pinned one gets a warning, not a refusal.

## Godot

`tools/godot.sh` runs one Godot. It takes, in order:

1. `$GODOT_BIN` when that is set (one executable path or name, no arguments);
2. `godot` on the `PATH` (mise's);
3. the Flatpak `org.godotengine.Godot`.

Everything goes through it: `tools/run_tests.sh`, the importer and every `tools/godot.sh ...` command of the manuals. Any `godot` binary
also works directly with `--path godot`. Check with `tools/godot.sh --version`: the pinned one begins `4.7.2.stable`; the importer warns about any other. Another 4.7.2 binary works
through `export GODOT_BIN=/path/to/godot` ("mise, and using your own installs").

**The Flatpak is not supported.** The wrapper still falls back to it, and it mostly works, but nothing is tested on it. What differs:

- It can write only under your home folder, not `/tmp`: snapshots, exports and `--out=` paths must be under `$HOME`.
- Its `user://` is `~/.var/app/org.godotengine.Godot/data/godot/app_userdata/Operation Larissa/`, not
  `~/.local/share/godot/app_userdata/Operation Larissa/`: saves and installed packs do not carry over between the two Godots.
- Its export templates live in `~/.var/app/org.godotengine.Godot/data/godot/export_templates/4.7.2.stable/`.
- `GODOT_BIN` cannot name it (it needs arguments); it is used only when no `godot` is on the `PATH`.

## The Python environment

`uv sync` (`mise run setup` runs it) creates `.venv/` from `pyproject.toml` and `uv.lock`. It installs three sets of
packages:

- the image-reading and picture libraries the tools use (`pycdlib`, `numpy`, `pillow`, `pefile`, `capstone`);
- the developer tools (`pytest`, `ruff`, `pyright`);
- the `transcribe` group: `faster-whisper` 1.2.1 and `ctranslate2` 4.8.4, the speech engine for the voice transcripts, with the Hugging
  Face client that downloads its model.

`transcribe` is a default group, so a plain `uv sync` installs it, and it is large. With any other versions of those two packages the importer warns
and runs its `transcripts` step anyway; the text may then differ from the fixture. `uv run ...` syncs by itself the first time.

The `dev-pack` group (Piper) is not a default group: name it, `uv run --group dev-pack ...`. The Ghidra scripts build their own
environment (`tools/analysis/ghidra/run.sh`).

## Disk space and time for the legacy pack

On the author's machine a finished legacy pack takes:

- about 64 MB in its `assets/` and 9 MB in its `data/`;
- 58 MB in `extracted/`;
- about 120 MB for Godot's own import cache, `godot/.godot/`.

The speech model is a separate download of about 480 MB into the Hugging Face cache. That is `~/.cache/huggingface/hub` by default, or
wherever `HF_HOME` / `HF_HUB_CACHE` point. It is fetched once and reused. `soundfonts/opl.sf2`, if you have it, is another 135 MB. Plan
on 1 GB free.

A full importer run takes about 10 minutes, nearly all of it the voice transcripts (423 clips on the CPU). The first run adds the
model download. `--no-transcripts` leaves them out: a minute or two, no model ([`play/LEGACY.md`](play/LEGACY.md)).
