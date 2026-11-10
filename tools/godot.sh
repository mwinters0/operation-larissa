#!/usr/bin/env bash
# Wrapper so every tool and manual can say `tools/godot.sh ...`. It runs, in this order:
#   1. the Godot named by $GODOT_BIN (one executable path or name, no arguments in it), when that is set;
#   2. `godot` on the PATH: mise's Godot (mise.toml pins it; the supported one), or any other you put there;
#   3. the Flatpak org.godotengine.Godot, when there is no `godot` on the PATH (not supported: docs/SETUP.md, "Godot").
# tools/run_tests.sh, the importer (import_all.py: its tool check and its "godot" step) and gdUnit4's runtest.sh all go through it.
# Usage:  GODOT_BIN=$PWD/tools/godot.sh godot/addons/gdUnit4/runtest.sh -a tests      (that GODOT_BIN is this script itself: it is skipped, not run twice)
#         GODOT_BIN=/opt/godot/godot tools/godot.sh --headless --path godot --import
here="$(readlink -f "${BASH_SOURCE[0]}")"
if [[ -n "${GODOT_BIN:-}" ]]; then
  wanted="$(command -v -- "$GODOT_BIN" 2>/dev/null)" || { echo "tools/godot.sh: GODOT_BIN='$GODOT_BIN' is not an executable" >&2; exit 127; }
  if [[ "$(readlink -f "$wanted")" != "$here" ]]; then
    exec "$wanted" "$@"
  fi
fi
if on_path="$(type -P godot)" && [[ "$(readlink -f "$on_path")" != "$here" ]]; then
  exec "$on_path" "$@"
fi
if type -P flatpak >/dev/null; then
  exec flatpak run --command=godot-bin org.godotengine.Godot "$@"
fi
echo "tools/godot.sh: no Godot found: run \`mise install\` in the repository (mise.toml pins Godot), or set GODOT_BIN" >&2
exit 127
