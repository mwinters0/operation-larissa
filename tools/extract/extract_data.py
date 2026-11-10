# /// script
# requires-python = ">=3.10"
# dependencies = ["pefile", "pillow", "pycdlib"]
# ///
"""Extract text, string tables, game-data blobs, icons, and small data files.
The sources are files of the CD (ONWINCD/*), read from NEPTUNE.ISO by tools/gamefiles.py. Usage: extract_data.py [OUT_DIR]

NEP.DLL custom type 32515 holds ~741 game-data resources (ids 10000-12020):
  * text (mission messages, math-problem templates, hints, help screens, data-canister log entries)
  * binary tables (level maps, object placements, problem parameter tables, x86 blitter stubs)
NEP.DLL custom type 32513 'BNDL' resources are id-range groups (u32 'BNDL', u32 count, u32 ids...) that tell which
resources belong together (e.g. the problem templates for one problem type).
Text escape codes (in the original font): 0x08 0xD0+n = substitute variable n; 0x0C = degree sign;
0x0D = newline (also 0x0A); 0xFF xx = answer-field / formatting directive; others are font glyphs (arrows etc.).
"""
import io, json, re, struct, sys
from pathlib import Path
from ne import NE
import pefile
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / 'tools'))     # gamefiles.py reads the CD image (NEPTUNE.ISO)
import gamefiles
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'extracted'

VAR = re.compile(rb'\x08([\xd0-\xdf])')

def is_text(e):
    if len(e) < 3: return False
    s = VAR.sub(b'', e)
    s = s.replace(b'\xff', b'')
    pr = sum(1 for b in s if 32 <= b < 127 or b in (10, 13))
    return len(s) > 0 and pr / len(s) > 0.9

def clean(e):
    s = VAR.sub(lambda m: b'{%d}' % (m.group(1)[0] - 0xd0), e).decode('latin1')
    s = s.replace('\r', '\n').replace('\x0c', '°')
    return s

def write_json(p, o):
    p.parent.mkdir(parents=True, exist_ok=True)
    with open(p, 'w', encoding='utf-8') as f:
        json.dump(o, f, indent=1, ensure_ascii=False)

def parse_strtab(d):
    out = []; p = 0
    for i in range(16):
        if p >= len(d): break
        l = d[p]; out.append(d[p+1:p+1+l].decode('latin1')); p += 1 + l
    return out

def do_nep():
    n = NE(gamefiles.read('ONWINCD/NEP.DLL'))
    bundles = {}
    for r in n.resources:
        if r[1] == 32513:
            d = n.get(r)
            if d[:4] == b'BNDL':
                cnt = struct.unpack_from('<I', d, 4)[0]
                bundles[r[2]] = list(struct.unpack_from('<%dI' % cnt, d, 8))
    member = {}
    for b, ids in bundles.items():
        for i in ids: member.setdefault(i, b)
    raw_dir = OUT / 'data' / 'NEP_raw'; raw_dir.mkdir(parents=True, exist_ok=True)
    texts = []; bins = []
    for r in n.resources:
        if r[1] == 32515:
            d = n.get(r); e = d.rstrip(b'\0')
            (raw_dir / f'NEP_{r[2]}.bin').write_bytes(e)
            ent = dict(id=r[2], bundle=member.get(r[2]), size=len(e))
            if not e: ent['kind'] = 'empty'; bins.append(ent)
            elif is_text(e):
                ent.update(kind='text', text=clean(e), raw_latin1=e.decode('latin1'))
                texts.append(ent)
            else:
                ent.update(kind='binary', head_hex=e[:32].hex()); bins.append(ent)
    write_json(OUT / 'data' / 'NEP_text.json', texts)
    write_json(OUT / 'data' / 'NEP_binary_index.json', bins)
    # grouped by bundle for easy browsing
    grouped = {}
    for t in texts:
        grouped.setdefault(str(t['bundle']), []).append(dict(id=t['id'], text=t['text']))
    write_json(OUT / 'data' / 'NEP_text_by_bundle.json', grouped)
    with open(OUT / 'data' / 'NEP_text.txt', 'w', encoding='utf-8') as f:
        for b, items in sorted(grouped.items(), key=lambda x: (x[0] == 'None', int(x[0]) if x[0] != 'None' else 0)):
            f.write(f'==== BNDL {b} ====\n')
            f.writelines(f'--- {it["id"]}\n{it["text"]}\n' for it in items)
    write_json(OUT / 'data' / 'NEP_bundles.json', {str(k): v for k, v in bundles.items()})
    # fonts (type 32514) raw
    fdir = OUT / 'data' / 'fonts_raw'; fdir.mkdir(parents=True, exist_ok=True)
    for r in n.resources:
        if r[1] == 32514: (fdir / f'NEP_font_{r[2]}.bin').write_bytes(n.get(r).rstrip(b'\0'))
    print('NEP text:', len(texts), 'binary/empty:', len(bins))

def do_ne_exe():
    n = NE(gamefiles.read('ONWINCD/ONWIN.EXE'))
    strings = {}
    ddir = OUT / 'data' / 'ONWIN_exe_resources'; ddir.mkdir(parents=True, exist_ok=True)
    for r in n.resources:
        d = n.get(r)
        if r[0] == 'STRING':
            for k, s in enumerate(parse_strtab(d)):
                if s: strings[(r[2] - 1) * 16 + k] = s
        else:
            (ddir / f'{r[0]}_{r[2]}.bin').write_bytes(d.rstrip(b'\0') or d[:1])
    write_json(OUT / 'data' / 'ONWIN16_strings.json', {str(k): v for k, v in sorted(strings.items())})
    print('ONWIN.EXE strings:', len(strings))

def do_pe_exe():
    pe = pefile.PE(data=gamefiles.read('ONWINCD/ONWIN32.EXE'))
    res = {}
    strings = {}
    # present only when the PE has a resource section (pefile's stubs don't declare it)
    res_dir = getattr(pe, 'DIRECTORY_ENTRY_RESOURCE', None)
    if res_dir is not None:
        for t in res_dir.entries:
            tname = pefile.RESOURCE_TYPE.get(t.struct.Id, str(t.name or t.struct.Id)) if t.name is None else str(t.name)
            for e in t.directory.entries:
                for l in e.directory.entries:
                    data = pe.get_data(l.data.struct.OffsetToData, l.data.struct.Size)
                    rid = e.name if e.name is not None else e.struct.Id
                    res.setdefault(str(tname), []).append((rid, data))
    for rid, d in res.get('RT_STRING', []):
        p = 0
        for k in range(16):
            l = struct.unpack_from('<H', d, p)[0]; p += 2
            s = d[p:p+2*l].decode('utf-16le'); p += 2*l
            if s: strings[(rid - 1) * 16 + k] = s
    write_json(OUT / 'data' / 'ONWIN32_strings.json', {str(k): v for k, v in sorted(strings.items())})
    ddir = OUT / 'data' / 'ONWIN32_resources'; ddir.mkdir(parents=True, exist_ok=True)
    for t, lst in res.items():
        for rid, d in lst: (ddir / f'{t}_{rid}.bin').write_bytes(d)
    print('ONWIN32 resource types:', {k: len(v) for k, v in res.items()}, 'strings', len(strings))

def do_icons():
    d = OUT / 'images' / 'icons'; d.mkdir(parents=True, exist_ok=True)
    ico = gamefiles.read('ONWINCD/ONCD.ICO')
    (d / 'ONCD.ICO').write_bytes(ico)
    try:
        Image.open(io.BytesIO(ico)).convert('RGBA').save(d / 'ONCD.png')
    except (OSError, ValueError) as ex:   # unreadable / unsupported icon: not fatal
        print('icon', ex)
    # tiny files
    t = OUT / 'data' / 'misc'; t.mkdir(parents=True, exist_ok=True)
    for f in ['HALLFAME.DAT', 'ONUSERS.DAT', 'ONWINCD.INI', 'ONWINCD.BAK']:
        (t / f).write_bytes(gamefiles.read('ONWINCD/' + f))
    (t / 'ONWIN.MAP').write_bytes(gamefiles.read('ONWINCD/ONWIN.MAP'))

if __name__ == '__main__':
    do_nep(); do_ne_exe(); do_pe_exe(); do_icons()
