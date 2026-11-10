#!/usr/bin/env bash
# Re-run every extractor. Needs: uv, ffmpeg. Source: the CD image NEPTUNE.ISO (or $NEP_ISO), read by tools/gamefiles.py.
# Output: ../../extracted, or the folder given as the first argument.
set -euo pipefail
[ $# -gt 0 ] && set -- "$(realpath -m "$1")"     # an output folder is given relative to where you are
cd "$(dirname "$0")"
uv run extract_images.py "$@"
uv run extract_sounds.py "$@"
uv run extract_data.py "$@"
uv run make_sheets.py "$@"
uv run extract_previews.py "$@"       # promo content for other TLC titles (not Neptune)
# voice transcripts are a regular importer step now (downloads the pinned Whisper model on first use):
#   uv run ../import/import_all.py --only transcripts
