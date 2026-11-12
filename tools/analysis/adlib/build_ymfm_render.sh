#!/usr/bin/env bash
# Builds ymfm_render (ymfm_render.cpp) against a checkout of ymfm (https://github.com/aaronsgiles/ymfm, BSD-3-Clause).
# usage: YMFM_DIR=<ymfm checkout> build_ymfm_render.sh [out-file]      env: YMFM_DIR (required), ADLIB_OUT, CXX
# YMFM_DIR holds ymfm_opl.h (a checkout of upstream keeps the sources in its src/ folder; either is found).
# Needs a C++17 compiler. Default output: $ADLIB_OUT/ymfm_render, else build/adlib/ymfm_render of this repository.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -n "${YMFM_DIR:-}" ] || { echo "set YMFM_DIR to a checkout of https://github.com/aaronsgiles/ymfm" >&2; exit 1; }
ymfm="$YMFM_DIR"
[ -f "$ymfm/ymfm_opl.h" ] || ymfm="$YMFM_DIR/src"
[ -f "$ymfm/ymfm_opl.h" ] || { echo "ymfm_opl.h not found in $YMFM_DIR or $YMFM_DIR/src" >&2; exit 1; }
out="${1:-${ADLIB_OUT:-$here/../../../build/adlib}/ymfm_render}"
mkdir -p "$(dirname "$out")"
"${CXX:-c++}" -O2 -std=c++17 -I"$ymfm" "$here/ymfm_render.cpp" "$ymfm/ymfm_opl.cpp" "$ymfm/ymfm_adpcm.cpp" "$ymfm/ymfm_pcm.cpp" -o "$out"
echo "built $out"
