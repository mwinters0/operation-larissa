"""Operation Neptune -> Godot import pipeline: your NEPTUNE.ISO -> the LEGACY pack, the original game as content (docs/play/LEGACY.md).

    uv run tools/import/import_all.py [--only extract,tables,images,tiles,sprites,sectors,problems,console,story,campaigns,transcripts,audio,godot]
                                      [--clean] [--validate] [--soundfont PATH]
                                      [--compute-type int8|float32]

Before it reads anything it checks that your NEPTUNE.ISO is the reference release (source_files.py) and refuses with "your copy is
a different version or patched" if not, and that the programs the chosen steps need are here (tool_check.py: Godot, ffmpeg with
libvorbis, fluidsynth, the General MIDI soundfont, the speech engine); it refuses with the list of what is missing and how to get it.
A program that is there but not the version the project pins (Godot: mise.toml; the speech engine: uv.lock) gets a loud warning, and
the run goes on. Then, from that ISO alone: "extract" unpacks it into extracted/ (tools/extract/), "tables"
dumps the game's data tables to docs/data/ (step_extract.py), and the other steps write the legacy pack: loose files in the folder
godot/packs/legacy (common.legacy_root; res://packs/legacy/), holding pack.json, assets/, data/ and midi/. The importer makes that
folder and its pack.json first, then writes the asset manifest (tools/import/asset_manifest.json: where each file under assets/ comes from), the fixtures of the original
(godot/tests/fixtures/*.json: provenance and SHA-256 hashes, committed; godot/tests/fixtures/original/: the original bytes, not
committed) and a stub `.import` file with a stable uid beside every picture and sound (import_uids.py). The legacy pack is everything of
the pack's folder: none of it is in git. The last step, "godot", has Godot import the project (it completes the .import files)
through tools/godot.sh (on Windows, the Godot tools/godot.py finds).
Running the importer twice produces identical files.
The "transcripts" step (transcripts.py) turns the voice clips into text with a pinned speech model, the same on every machine,
and reports each clip whose text differs from godot/tests/fixtures/voice_transcripts.json; your hand corrections are read from
godot/data/legacy/voice_corrections.json (common.LEGACY_AREA). A run that leaves out the "godot" step ends by printing the command
that does it by hand:

    tools/godot.sh --headless --path godot --import          # on Windows: uv run tools/godot.py --headless --path godot --import
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import asset_manifest
import common
import godot
import import_uids
import source_files
import tool_check
import transcripts
import step_audio, step_campaigns, step_console, step_extract, step_images, step_problems, step_sectors, step_sprites, step_story, step_tiles

GODOT_IMPORT_BY_HAND = godot.by_hand("--headless --path godot --import")


def godot_import() -> None:
    """The last step: Godot imports the project (it completes the stub .import files and keeps their uids). Without Godot it says what
    to run by hand; everything else is already made."""
    try:
        command = godot.command() + ["--headless", "--path", str(common.GODOT), "--import"]
        done = subprocess.run(command, capture_output=True, text=True, check=False)
    except (godot.GodotNotFound, OSError) as error:
        print("Godot could not be started (%s): run `mise install`, or set GODOT_BIN" % error)
        done = None
    if done is not None and done.returncode != 0:
        sys.stderr.write(done.stdout[-3000:] + done.stderr[-3000:])
    if done is None or done.returncode != 0:
        print("the Godot import was not done. By hand:  " + GODOT_IMPORT_BY_HAND)


# Order matters: later steps reference files written by earlier ones. `--only` keeps this order (`steps_to_run`).
STEPS = {
    "extract": step_extract.run_extract,
    "tables": step_extract.run_tables,
    "images": step_images.run,
    "tiles": step_tiles.run,
    "sprites": step_sprites.run,
    "sectors": step_sectors.run,
    "problems": step_problems.run,
    "console": step_console.run,
    "story": step_story.run,
    "campaigns": step_campaigns.run,
    "transcripts": transcripts.run,
    "audio": step_audio.run,
    "godot": godot_import,
}
OWNED_DIRS = {
    "extract": [],                      # extracted/ and docs/data/'s tables are rewritten in place, never cleaned
    "tables": [],
    "images": [common.ASSETS / "backgrounds", common.ASSETS / "ui", common.ASSETS / "problem_art",
               common.ASSETS / "authoring_tool"],
    "tiles": [common.ASSETS / "tiles"],
    "sprites": [common.ASSETS / "sprites", common.PACK_DATA / "sprite_frames", common.PACK_DATA / "sprite_meta"],
    "sectors": [],                      # not the folder: see OWNED_FILES
    "problems": [common.PACK_DATA / "problems"],
    "console": [common.PACK_DATA / "ui"],            # (menu_layout.tres is the project's own: see OWNED_FILES)
    "story": [common.PACK_DATA / "story"],          # (the other timelines are the project's own: see OWNED_FILES)
    "campaigns": [],                    # not the folder: see OWNED_FILES
    "transcripts": [],                  # extracted/sounds/voice_transcripts*.json: input of the audio step, not cleaned
    "audio": [common.ASSETS / "audio"],
    "godot": [],                        # Godot completes the .import files and fills its own cache (godot/.godot/): nothing to clean
}
# Files a step owns inside a folder it shares with hand-made content (or that is the project's, not the legacy pack's: the committed story timelines
# and the menu layout). `--clean` deletes exactly these. The sectors
# folder also holds the annotation store (foe_annotations.json), the .uid files and any NEW sector the designers
# made, none of which the importer generates, so none is touched. The campaigns folder is shared the same
# way: the original's two files are the importer's, any other campaign there is not.
OWNED_FILES = {
    "sectors": step_sectors.owned_files,
    "campaigns": step_campaigns.owned_files,
    "console": step_console.owned_files,
    "story": step_story.owned_files,
}


def steps_to_run(only: str | None) -> list[str]:
    """The steps `--only` names (all of them without it), in PIPELINE ORDER (the order of STEPS) whatever order they were typed in, each once:
    a step reads files an earlier one writes, so `--only audio,sectors` runs "sectors" first. ValueError for a name that is no step."""
    if not only:
        return list(STEPS)
    asked = [name.strip() for name in only.split(",") if name.strip()]
    for name in asked:
        if name not in STEPS:
            raise ValueError("unknown step " + name)
    return [name for name in STEPS if name in asked]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", help="comma separated steps, run in pipeline order whatever order you type them: " + ",".join(STEPS))
    ap.add_argument("--clean", action="store_true", help="delete the selected steps' output folders first")
    ap.add_argument("--validate", action="store_true", help="run cross-checks on the generated tree")
    ap.add_argument("--soundfont", default=step_audio.DEFAULT_SOUNDFONT, help="General MIDI soundfont for the E*.MID set")
    ap.add_argument("--adlib-soundfont", default=step_audio.ADLIB_SOUNDFONT, help="OPL soundfont for the B*.MID (AdLib) set; optional")
    ap.add_argument("--compute-type", choices=transcripts.COMPUTE_TYPES, help="transcripts step: int8 (default) or float32")
    args = ap.parse_args()

    try:
        names = steps_to_run(args.only)
    except ValueError as error:
        ap.error(str(error))
    try:                                  # first of all: is this the release the committed hashes are of?
        source_files.check()
    except (source_files.DifferentRelease, source_files.gamefiles.MissingISO) as error:
        print("REFUSED, nothing was read or written: %s" % error)
        return 1
    missing = tool_check.missing(names, args.soundfont)    # then: is every program the chosen steps call here?
    if missing:
        print("REFUSED, nothing was read or written: the importer needs these first (docs/SETUP.md):")
        for line in missing:
            print("  - " + line)
        return 1
    tool_check.warn(tool_check.version_warnings(names))   # a version other than the pinned one: said loudly, not refused
    for line in common.prepare_legacy():  # the legacy pack's folder and its pack.json
        print(line)
    for n in [n for n in names if n != "godot"]:             # godot last, after the stable uids are written (Godot must keep them)
        if args.clean:
            for d in OWNED_DIRS[n]:
                common.clean_dir(d)
            for f in OWNED_FILES.get(n, list)():
                f.unlink(missing_ok=True)
        print("step", n)
        if n == "transcripts":
            try:
                transcripts.run(args.compute_type)
            except transcripts.EngineMismatch as error:
                print("REFUSED: %s" % error)
                return 1
        elif n == "audio":
            step_audio.run(args.soundfont, args.adlib_soundfont)
        else:
            STEPS[n]()
    full = set(names) == set(STEPS)
    asset_dirs = [d for n in names for d in OWNED_DIRS[n] if common.ASSETS in d.parents or d == common.ASSETS]
    owned = None if full else asset_dirs
    stale, carried = asset_manifest.prune(asset_dirs)          # files a renamed asset used to have (asset_names.py)
    if stale:
        print("stale asset files removed: %d (import files carried over to their new name: %d)" % (stale, carried))
    stubs = import_uids.ensure_sidecars(asset_dirs)            # a uid for every picture and sound, the same in every checkout
    if stubs:
        print("import files with a stable uid written: %d" % stubs)
    total = asset_manifest.write(owned)
    print("asset manifest: %d files" % total)
    print("files written: %d, unchanged: %d" % (common.Stats.written, common.Stats.unchanged))

    if "godot" in names:
        print("step godot")
        STEPS["godot"]()

    if args.validate:
        import validate
        problems = validate.run()
        if problems:
            print("VALIDATION FAILED:")
            for p in problems:
                print("  -", p)
            return 1
        print("validation OK")
    if "godot" not in names:
        print("next: " + GODOT_IMPORT_BY_HAND + "   (fills in the .import files)")
    return 0


if __name__ == "__main__":
    import utf8_mode
    utf8_mode.ensure()
    sys.exit(main())
