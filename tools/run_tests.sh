#!/usr/bin/env bash
# Runs the gdUnit4 tests, in two groups that pick the pack they run on (docs/engine/DEVELOPING.md):
#   engine  godot/tests/engine: the engine's tests, on the dev pack (`-- --pack=dev`). They need no legacy pack and never skip for want of content.
#   legacy  godot/tests/legacy: the tests that check the original game, on the legacy pack (`-- --pack=legacy`). It is made by the importer from
#           your ISO (docs/play/LEGACY.md) as the folder godot/packs/legacy; without it the group says so and passes.
# Almost all tests run with `--headless` (no window, no sound card), so the desktop you are working on cannot disturb them and they cannot
# disturb you. The few that really need a window or real rendering are listed in WINDOWED below and run in a real window afterwards.
#
#   tools/run_tests.sh                       both groups, engine first: each headless, then its windowed files
#   tools/run_tests.sh engine                only the engine group (also: legacy)
#   tools/run_tests.sh engine headless       only its headless files, every test file except WINDOWED (also: windowed; also without the group name)
#   tools/run_tests.sh tests/engine/test_catalog.gd   one test file (or a directory); the pack is chosen by the folder the file is in,
#                                            and it runs headless unless it is in WINDOWED
#
# The result of a run is what gdUnit4 itself reports: the `Exit code: N` it prints when the tests are done. The exit status:
#   0  every group passed
#   1  a test failed, or a run printed no `Exit code` (Godot ended before gdUnit4 had a verdict)
#   2  a path that is under neither tests/engine nor tests/legacy
#   3  every test passed (`Exit code: 0`) and Godot then died (an abort at shutdown): said loudly, and not a failed test
# Needs Godot through tools/godot.sh (mise's). The pin is the command line after `--` (`Packs.start()` reads it; gdUnit4's own tool
# ignores it), so a test that starts a second Godot must hand `Packs.asked()` on.
set -u
cd "$(dirname "$0")/../godot" || exit 1
godot="$PWD/../tools/godot.sh"

# Test files that need a window or the real audio output. One line each: why.
WINDOWED=(
  tests/legacy/test_snapshots.gd     # reads pixels back from a viewport: the dummy renderer draws nothing (skipped headless)
  tests/engine/test_skin_creatures_render.gd  # the creatures skin's 3D puffer fish in a SubViewport: pixels again (skipped headless)
  tests/engine/test_mod_skin_hud_render.gd    # a skin mod's picture of the console is cut off at its part's rectangle: pixels again (skipped headless)
  tests/engine/test_picture_ref_render.gd     # every consumer of a texture draws a PictureRef: pixels again (skipped headless)
  tests/engine/test_picture_scale_render.gd   # a run at picture scale 4 draws what a run at scale 1 draws (tiles, a nine-patch, sprites): pixels again (skipped headless)
)

# The pack a group runs on.
pin_of() { [[ $1 == engine ]] && echo dev || echo "$1"; }

# Is the legacy pack here? The importer's witnesses, the shortest list (tests/legacy/legacy_pack.gd has the full one).
legacy_here() {
  [[ -f packs/legacy/data/sectors/sector_00/sector_00.tres ]] && [[ -f packs/legacy/data/zones.tres ]]
}

# One gdUnit4 run. $1 = "headless" or "windowed", $2 = the group; the rest are the test paths (-a for each).
run_group() {
  local mode=$1 group=$2; shift 2
  local flags=()
  [[ $mode == headless ]] && flags=(--headless)
  if [[ $group == legacy ]] && ! legacy_here; then
    echo "== legacy $mode: skipped: the legacy pack (the original game) is not here: run the importer on your copy of the game" \
         "(uv run tools/import/import_all.py), then tools/godot.sh --headless --path godot --import"
    return 0
  fi
  local adds=()
  for path in "$@"; do adds+=(-a "$path"); done
  echo "== $group $mode (--pack=$(pin_of "$group")): $# test path(s)"
  local log
  log=$(mktemp) || return 1
  # The same call as addons/gdUnit4/runtest.sh, plus --headless. --ignoreHeadlessMode lets gdUnit4 run in headless mode.
  "$godot" "${flags[@]}" --path . -s -d --remote-debug tcp://127.0.0.1:0 \
    res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode "${adds[@]}" -- --pack="$(pin_of "$group")" 2>&1 | tee "$log"
  local godot_status=${PIPESTATUS[0]}
  # gdUnit4's verdict: the last `Exit code: N` it printed (colored, so the line is matched, not compared).
  local verdict
  verdict=$(sed -n 's/^.*Exit code: \([0-9][0-9]*\).*$/\1/p' "$log" | tail -n 1)
  rm -f "$log"
  if [[ -z $verdict ]]; then
    echo "== $group $mode: FAILED: gdUnit4 printed no 'Exit code' (Godot ended with status $godot_status before the tests had a verdict)" >&2
    return 1
  fi
  if [[ $verdict != 0 ]]; then
    echo "== $group $mode: FAILED: gdUnit4 reports exit code $verdict" >&2
    return 1
  fi
  if [[ $godot_status != 0 ]]; then
    echo "== $group $mode: the tests PASSED (gdUnit4: Exit code 0) but Godot then ended with status $godot_status (134 is an abort: a crash at shutdown, not a failed test)" >&2
    return 3
  fi
  return 0
}

# Folds the status of one run into the result: a failed test beats a crash after a pass.
failed=0 crashed=0
record() {
  case $1 in
    0) ;;
    3) crashed=1 ;;
    *) failed=1 ;;
  esac
}

is_windowed() {
  local file
  for file in "${WINDOWED[@]}"; do [[ $1 == "$file" ]] && return 0; done
  return 1
}

# The test files of a group, headless or windowed.
group_files() {
  local group=$1 mode=$2 file
  for file in tests/"$group"/test_*.gd; do
    if is_windowed "$file"; then [[ $mode == windowed ]] && echo "$file"; else [[ $mode == headless ]] && echo "$file"; fi
  done
}

# A group in one mode; a mode with no file is not run.
run_files() {
  local group=$1 mode=$2
  local files=($(group_files "$group" "$mode"))
  [[ ${#files[@]} -gt 0 ]] || return 0
  run_group "$mode" "$group" "${files[@]}"
}

groups=() modes=() paths=()
for arg in "$@"; do
  case "$arg" in
    engine|legacy) groups+=("$arg") ;;
    headless|windowed) modes+=("$arg") ;;
    all) ;;
    *) paths+=("${arg#res://}") ;;
  esac
done

if [[ ${#paths[@]} -gt 0 ]]; then
  # Single files or directories: the folder says the group; one run for each group and mode that appears.
  declare -A runs=()
  for path in "${paths[@]}"; do
    path=${path#./}
    case "$path" in
      tests/engine|tests/engine/*) group=engine ;;
      tests/legacy|tests/legacy/*) group=legacy ;;
      *) echo "run_tests.sh: $path is not under tests/engine or tests/legacy" >&2; exit 2 ;;
    esac
    if is_windowed "$path"; then mode=windowed; else mode=headless; fi
    runs["$group $mode"]+="$path "
  done
  for key in "engine headless" "engine windowed" "legacy headless" "legacy windowed"; do
    [[ -n ${runs[$key]:-} ]] || continue
    set -- $key
    run_group "$2" "$1" ${runs[$key]}; record $?
  done
else
  [[ ${#groups[@]} -gt 0 ]] || groups=(engine legacy)
  [[ ${#modes[@]} -gt 0 ]] || modes=(headless windowed)
  for group in "${groups[@]}"; do
    for mode in "${modes[@]}"; do run_files "$group" "$mode"; record $?; done
  done
fi
if [[ $failed == 1 ]]; then exit 1; fi
if [[ $crashed == 1 ]]; then
  echo "run_tests.sh: every test passed, but Godot crashed at shutdown in at least one run (exit status 3); see docs/engine/DEVELOPING.md" >&2
  exit 3
fi
exit 0
