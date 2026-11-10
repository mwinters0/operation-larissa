# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow", "pycdlib"]
# ///
"""Extract the bonus/promo content on the CD that is NOT part of Operation Neptune itself:
ASSETS/*.GRP on the CD (NEPTUNE.ISO; TLC 'RGrp' archives: ASEQ animation sequences, LIPS/LIP3 lip-sync tracks, WAVE speech, RRGB palettes)
and MOVIES/MV107A.SMK (Smacker video, converted to Ogg Theora).
These belong to the 'PREVIEWS.EXE' demo reel for other TLC titles (ClueFinders style), so they are written to
extracted/previews_other_titles/ and should NOT be redistributed without checking their licence.
ASEQ (animation) is dumped raw -- its cel format is not decoded here.
Usage: extract_previews.py [OUT_DIR]   (default: extracted/). ffmpeg reads the movie from a copy that gamefiles.materialize() makes.
"""
import json, subprocess, sys
from pathlib import Path
from PIL import Image
from rgrp import parse_group, walk

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / 'tools'))     # gamefiles.py reads the CD image (NEPTUNE.ISO)
import gamefiles
OUT = (Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'extracted') / 'previews_other_titles'

def main():
    man = {}
    for cd_path in gamefiles.glob('ASSETS/*.GRP'):
        f = Path(cd_path)
        buf = gamefiles.read(cd_path); top = parse_group(buf)
        base = OUT / 'grp' / f.stem; base.mkdir(parents=True, exist_ok=True)
        for path, e in walk(top):
            sub = '_'.join(str(p) for p in path)
            stem = f'{f.stem}{"_g" + sub if sub else ""}_{e.tag.strip()}_{e.id}'
            if e.tag == 'WAVE':
                fn = base / (stem + '.wav'); fn.write_bytes(e.data)
            elif e.tag == 'RRGB':
                # 256 entries x 3 u16 (hi byte == lo byte): 8-bit RGB = first byte of each pair
                pal = [(e.data[6*i], e.data[6*i+2], e.data[6*i+4]) for i in range(256)]
                with open(base / (stem + '.json'), 'w') as pf:
                    json.dump(pal, pf)
                sw = Image.new('RGB', (256, 256))
                for i, c in enumerate(pal): sw.paste(c, ((i % 16)*16, (i//16)*16, (i % 16)*16+16, (i//16)*16+16))
                sw.save(base / (stem + '_swatch.png')); fn = base / (stem + '.json')
            else:
                fn = base / (stem + '.bin'); fn.write_bytes(e.data)
            man[str(fn.relative_to(OUT))] = dict(archive=f.name, group_path=list(path), tag=e.tag, id=e.id, size=e.size)
    with open(OUT / 'grp_manifest.json', 'w') as mf:
        json.dump(man, mf, indent=1)
    mdir = OUT / 'movies'; mdir.mkdir(parents=True, exist_ok=True)
    smk = str(gamefiles.materialize('MOVIES/MV107A.SMK'))
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', smk, '-c:v', 'libtheora', '-q:v', '7',
                    '-c:a', 'libvorbis', '-q:a', '4', str(mdir / 'MV107A.ogv')], check=True)
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', '20', '-i', smk, '-frames:v', '1',
                    str(mdir / 'MV107A_frame20s.png')], check=True)
    print('grp members:', len(man))

if __name__ == '__main__':
    main()
