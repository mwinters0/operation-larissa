# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Build contact sheets (review montages) from extracted/images into extracted/contact_sheets/."""
import json, sys
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent.parent
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'extracted'
CS = OUT / 'contact_sheets'; CS.mkdir(parents=True, exist_ok=True)
with open(OUT / 'images' / 'manifest.json') as _f:
    man = json.load(_f)

def checker(w, h, s=8):
    im = Image.new('RGB', (w, h), (70, 70, 70))
    d = ImageDraw.Draw(im)
    for y in range(0, h, s):
        for x in range(0, w, s):
            if (x // s + y // s) % 2: d.rectangle([x, y, x+s-1, y+s-1], fill=(110, 110, 110))
    return im

def bg_sheets():
    for dll in ['NEPBG1', 'NEPBG2']:
        items = [v for v in man.values() if v['dll'] == dll]
        tw, th, cols = 200, 96, 8
        per_page = cols * 14
        for pg in range(0, len(items), per_page):
            chunk = items[pg:pg+per_page]
            rows = (len(chunk) + cols - 1) // cols
            sheet = Image.new('RGB', (cols * tw, rows * (th + 12)), (30, 30, 30))
            d = ImageDraw.Draw(sheet)
            for k, v in enumerate(chunk):
                im = Image.open(OUT / v['file']).convert('RGB').resize((tw - 4, th), Image.Resampling.NEAREST)
                x, y = (k % cols) * tw, (k // cols) * (th + 12)
                sheet.paste(im, (x + 2, y)); d.text((x + 4, y + th), str(v['id']), fill=(255, 255, 0))
            sheet.save(CS / f'backgrounds_{dll}_p{pg // per_page + 1}.png')

def sprite_sheets(maxw=1500, small_limit=160, pagelimit_h=1100):
    items = sorted([v for v in man.values() if v['dll'] == 'NEP256'], key=lambda v: v['id'])
    small = [v for v in items if v['w'] <= small_limit and v['h'] <= small_limit]
    big = [v for v in items if v not in small]
    def pack(lst, name, scale: float = 1):
        pages = []; x = y = rowh = 0
        cur = checker(maxw, pagelimit_h, 8); d = ImageDraw.Draw(cur); used_h = 0
        def flush():
            nonlocal cur, d, used_h
            if used_h:
                pages.append(cur.crop((0, 0, maxw, used_h)))
            cur = checker(maxw, pagelimit_h, 8); d = ImageDraw.Draw(cur); used_h = 0
        for v in lst:
            im = Image.open(OUT / v['file']).convert('RGBA')
            if scale != 1: im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.Resampling.NEAREST)
            cw = max(im.width, 32) + 6
            if x + cw > maxw: x = 0; y += rowh; rowh = 0
            if y + im.height + 14 > pagelimit_h:
                flush(); x = y = rowh = 0
            cur.paste(im, (x + 3, y), im); d.text((x + 3, y + im.height), str(v['id']), fill=(255, 255, 0))
            x += cw; rowh = max(rowh, im.height + 12); used_h = max(used_h, y + rowh)
        flush()
        for i, p in enumerate(pages): p.save(CS / f'{name}_p{i+1}.png')
    pack(small, 'sprites_small_NEP256')
    pack(big, 'sprites_large_NEP256_half', 0.5)

if __name__ == '__main__':
    bg_sheets(); sprite_sheets()
    print(sorted(p.name for p in CS.glob('*.png')))
