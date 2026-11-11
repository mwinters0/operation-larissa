# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow", "pycdlib"]
# ///
"""Extract all RUND images (sprites + backgrounds) from the Operation Neptune DLLs to PNG.

Reads ONWINCD/NEP.DLL, NEP256.DLL, NEPBG1.DLL and NEPBG2.DLL from the CD (NEPTUNE.ISO, see tools/gamefiles.py).
Usage: uv run extract_images.py [OUT_DIR]      (default: extracted/)
"""
import json, struct, sys
from pathlib import Path
from PIL import Image
from ne import NE
from rund import decode_rund, TRANSPARENT_INDEX

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE.parent))     # tools/: gamefiles.py reads the CD image
import gamefiles
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'extracted'

def load_palettes():
    """NEP.DLL type 32516: 900 and 901 are 768-byte RGB palettes padded to 1024."""
    n = NE(gamefiles.read('ONWINCD/NEP.DLL'))
    pals = {}
    for r in n.resources:
        if r[1] == 32516:
            d = n.get(r)
            pals[r[2]] = [tuple(d[3*i:3*i+3]) for i in range(256)]
    return pals

def load_bundles():
    """NEP.DLL type 32513 'BNDL': u32 'BNDL', u32 count, count*u32 resource ids."""
    n = NE(gamefiles.read('ONWINCD/NEP.DLL'))
    b = {}
    for r in n.resources:
        if r[1] == 32513:
            d = n.get(r)
            if d[:4] != b'BNDL': continue
            cnt = struct.unpack_from('<I', d, 4)[0]
            b[r[2]] = list(struct.unpack_from('<%dI' % cnt, d, 8))
    return b

def to_image(w, h, px, pal, transparent=True):
    im = Image.frombytes('P', (w, h), px)
    flat = []
    for c in pal: flat += c
    im.putpalette(flat)
    rgba = im.convert('RGBA')
    if transparent:
        a = Image.frombytes('L', (w, h), bytes(0 if v == TRANSPARENT_INDEX else 255 for v in px))
        rgba.putalpha(a)
    return rgba

def main():
    pals = load_palettes()
    pal = pals[900]
    (OUT / 'palettes').mkdir(parents=True, exist_ok=True)
    for pid, p in pals.items():
        with open(OUT / 'palettes' / f'pal_{pid}.json', 'w', newline='\n') as fh:
            json.dump([list(c) for c in p], fh)
        with open(OUT / 'palettes' / f'pal_{pid}.pal', 'wb') as f:      # raw RGB 768 bytes
            f.writelines(bytes(c) for c in p)
        sw = Image.new('RGB', (16*16, 16*16))
        for i, c in enumerate(p):
            sw.paste(c, ((i % 16)*16, (i//16)*16, (i % 16)*16+16, (i//16)*16+16))
        sw.save(OUT / 'palettes' / f'pal_{pid}_swatch.png')
    bundles = load_bundles()
    manifest = {}
    for dll, kind in [('NEP256', 'sprites'), ('NEPBG1', 'backgrounds'), ('NEPBG2', 'backgrounds')]:
        n = NE(gamefiles.read(f'ONWINCD/{dll}.DLL'))
        d_out = OUT / 'images' / kind / dll
        d_out.mkdir(parents=True, exist_ok=True)
        for r in n.resources:
            if r[1] != 32513: continue
            w, h, px, _short = decode_rund(n.get(r))
            im = to_image(w, h, px, pal, transparent=(kind == 'sprites'))
            fn = f'{dll}_{r[2]}.png'
            im.save(d_out / fn)
            manifest[f'{dll}:{r[2]}'] = dict(dll=dll, id=r[2], w=w, h=h, file=f'images/{kind}/{dll}/{fn}',
                                              transparent_index=TRANSPARENT_INDEX if kind == 'sprites' else None)
    # group sprite frames by bundle (animation / image set)
    anims = {}
    adir = OUT / 'images' / 'sprite_bundles'
    adir.mkdir(parents=True, exist_ok=True)
    for bid, ids in sorted(bundles.items()):
        frames = [manifest.get(f'NEP256:{i}') for i in ids]
        if not any(frames): continue
        fr = [f for f in frames if f]
        maxw = max(f['w'] for f in fr); maxh = max(f['h'] for f in fr)
        sheet = Image.new('RGBA', (maxw * len(fr), maxh), (0, 0, 0, 0))
        for k, f in enumerate(fr):
            sheet.paste(Image.open(OUT / f['file']), (k * maxw, 0))
        sname = f'bundle_{bid:03d}.png'
        sheet.save(adir / sname)
        anims[bid] = dict(bundle=bid, frame_ids=[f['id'] for f in fr], cell_w=maxw, cell_h=maxh,
                          frames=[dict(id=f['id'], w=f['w'], h=f['h'], file=f['file']) for f in fr],
                          strip=f'images/sprite_bundles/{sname}',
                          note='frames in playback/index order; strip cells are top-left aligned in cell_w x cell_h')
    for k, v in manifest.items():
        v['bundle'] = next((b for b, a in anims.items() if v['id'] in a['frame_ids'] and v['dll'] == 'NEP256'), None)
    with open(OUT / 'images' / 'manifest.json', 'w', newline='\n') as fh:
        json.dump(manifest, fh, indent=1)
    with open(OUT / 'images' / 'sprite_bundles.json', 'w', newline='\n') as fh:
        json.dump(anims, fh, indent=1)
    print('images:', len(manifest), 'bundles:', len(anims))

if __name__ == '__main__':
    main()
