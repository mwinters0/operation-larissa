# AdLib research scripts

Research scripts for [`docs/port/ADLIB_MUSIC.md`](../../../docs/port/ADLIB_MUSIC.md): the Windows AdLib songs (`B*.MID`) next to the
General MIDI songs (`E*.MID`), the patches of the DOS game's AdLib songs in `NE0SOUND.DLL`, and a small ymfm renderer for an OPL2
register log. They are not part of the importer and have no tests; each script starts with a header that says what it teaches and how
to run it. The game's files are read at run time (`extracted/` from the importer), never embedded here.

## Inputs and outputs

| Variable | Meaning | Default |
| --- | --- | --- |
| `LARISSA_EXTRACTED` | the importer's `extracted/` (`music/*.MID`, `sounds/fm_patches_undecoded/`) | `extracted/` of this repository |
| `ADLIB_OUT` | where the scripts write | `build/adlib/` (git-ignored) |
| `YMFM_DIR` | a checkout of [ymfm](https://github.com/aaronsgiles/ymfm) (BSD-3-Clause), for `build_ymfm_render.sh` | none |

`paths.py` holds the first two. Run a script with `uv run tools/analysis/adlib/<script>.py`; the scripts import each other by name,
so run them by path or from this folder.

## The scripts

| Script | What it does |
| --- | --- |
| `paths.py` | the folders above |
| `midi.py` | the small SMF reader the others use (`parse`, `tempo_map`, `notes`) |
| `midi_report.py`, `compare.py`, `poly.py` | per file length, tempo, channels, programs, controllers, bends; B against E; polyphony and drum keys |
| `patch_decode.py` | prints the 11-byte patches of the NE0SOUND type-3 resources (game data: look, never commit) |
| `ymfm_render.cpp`, `build_ymfm_render.sh` | an OPL2 register log (`<chip sample> <reg hex> <value hex>` per line) to a WAV with ymfm; the script builds it against `YMFM_DIR` |
| `render_midi.sh` | one MIDI file through a soundfont to a loudness-matched OGG, for comparing renderings by ear |

```sh
uv run tools/import/import_all.py --only extract            # extracted/music, extracted/sounds (once)
uv run tools/analysis/adlib/midi_report.py                  # the table of ADLIB_MUSIC.md 1.1
uv run tools/analysis/adlib/compare.py && uv run tools/analysis/adlib/poly.py
YMFM_DIR=<a ymfm checkout> tools/analysis/adlib/build_ymfm_render.sh
```

`ymfm` is a third-party library; a use of it in the importer would be a new external program (`AGENTS.md` "Tools"). `ruff` and
`pyright` cover these scripts (`uv run ruff check tools`).
