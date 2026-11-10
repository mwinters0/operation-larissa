#!/usr/bin/env bash
# Usage: ./run.sh <script.py> [args...]   (creates ./.venv with PyGhidra on first use)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
export GHIDRA_INSTALL_DIR="${GHIDRA_INSTALL_DIR:-$HOME/.local/bin/ghidra/ghidra_12.2_PUBLIC}"
venv="${NEP_VENV:-$here/.venv}"
if [ ! -x "$venv/bin/python" ]; then
  uv venv --python 3.13 "$venv"
  uv pip install --python "$venv/bin/python" --no-index \
     --find-links "$GHIDRA_INSTALL_DIR/Ghidra/Features/PyGhidra/pypkg/dist" pyghidra
fi
# tools/gamefiles.py (reads NEPTUNE.ISO) needs pycdlib, a small pure-Python package from PyPI
if ! "$venv/bin/python" -c "import pycdlib" 2>/dev/null; then
  uv pip install --python "$venv/bin/python" pycdlib
fi
cd "$here"
exec "$venv/bin/python" "$@"
