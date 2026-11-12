#!/usr/bin/env bash
# One MIDI file through a soundfont to a trimmed, loudness-matched OGG, for comparing renderings by ear (the same recipe as the
# importer's audio step: fluidsynth at gain 0.8, trailing silence removed, peaks kept below -1.5 dB).
# usage: render_midi.sh <song.mid> <soundfont.sf2> <out.ogg>        needs fluidsynth, ffmpeg (libvorbis)
# Example: render_midi.sh extracted/music/BSECT1.MID soundfonts/opl.sf2 build/adlib/BSECT1_opl.ogg
set -euo pipefail
mid=$1; sf=$2; out=$3
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fluidsynth -ni -g 0.8 -r 44100 -F "$tmp/x.wav" "$sf" "$mid" > "$tmp/fs.log" 2>&1
vd=$(ffmpeg -nostats -i "$tmp/x.wav" -af volumedetect -f null - 2>&1 | grep -E "mean_volume|max_volume" | sed 's/.*: //' | tr '\n' ' ')
gain=$(python3 - "$vd" <<'PY'
import sys
f = sys.argv[1].split()
mean, peak = float(f[0]), float(f[2])
g = -22.0 - mean if mean > -19.0 else 0.0
print(round(min(0.0, g, -1.5 - peak), 1))
PY
)
trim="areverse,silenceremove=start_periods=1:start_threshold=-60dB,areverse"
[[ $gain != 0.0 && $gain != -0.0 ]] && trim="$trim,volume=${gain}dB"
mkdir -p "$(dirname "$out")"
ffmpeg -y -loglevel error -i "$tmp/x.wav" -af "$trim" -c:a libvorbis -q:a 4 -fflags +bitexact -flags:a +bitexact -map_metadata -1 "$out"
echo "$(basename "$out") raw[mean max]=$vd gain=$gain"
