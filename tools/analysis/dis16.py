"""Disassemble functions of ONWIN.EXE (Win16 NE, Borland C++ large model) using ONWIN.MAP symbols
and NE relocations.  Usage: dis16.py <funcname-or-substring> [more...]
Run: uv run tools/analysis/dis16.py _DoAction   (after `mise run setup`)
"""
import collections
import os
import re
import struct
import sys
from pathlib import Path

from capstone import CS_ARCH_X86, CS_MODE_16, Cs

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))   # tools/: gamefiles.py reads the CD image (NEPTUNE.ISO)
import gamefiles
d=gamefiles.read('ONWINCD/ONWIN.EXE')
ne=struct.unpack_from('<I',d,0x3c)[0]
nseg=struct.unpack_from('<H',d,ne+0x1c)[0]
segtab=ne+struct.unpack_from('<H',d,ne+0x22)[0]
shift=struct.unpack_from('<H',d,ne+0x32)[0]
# entry table
ent_off=ne+struct.unpack_from('<H',d,ne+4)[0]; ent_len=struct.unpack_from('<H',d,ne+6)[0]
entries: list[tuple[int, int] | None]=[None]  # ordinal -> (seg, off)
p=ent_off
while p<ent_off+ent_len:
    n=d[p]; ty=d[p+1]; p+=2
    if n==0: break
    for _ in range(n):
        if ty==0: entries.append(None)
        elif ty==0xff:
            flags,int3f,seg,off=struct.unpack_from('<BHBH',d,p); p+=6; entries.append((seg,off))
        else:
            flags,off=struct.unpack_from('<BH',d,p); p+=3; entries.append((ty,off))
# import module names / import names
modoff=ne+struct.unpack_from('<H',d,ne+0x28)[0]; impoff=ne+struct.unpack_from('<H',d,ne+0x2a)[0]
nmod=struct.unpack_from('<H',d,ne+0x1e)[0]
mods=[]
for i in range(nmod):
    o=struct.unpack_from('<H',d,modoff+2*i)[0]; n=d[impoff+o]; mods.append(d[impoff+o+1:impoff+o+1+n].decode())
segs={}
for i in range(nseg):
    off,ln,fl,ma=struct.unpack_from('<HHHH',d,segtab+i*8)
    seg=d[off<<shift:(off<<shift)+(ln or 0x10000)]
    relocs={}
    if fl&0x100:
        ro=(off<<shift)+(ln or 0x10000)
        n=struct.unpack_from('<H',d,ro)[0]; ro+=2
        for k in range(n):
            st,fg,so,a,b=struct.unpack_from('<BBHHH',d,ro+8*k)
            relocs[so]=(st,fg,a,b)
    segs[i+1]=(seg,relocs)
# symbols
syms=collections.defaultdict(list)
lines=gamefiles.read('ONWINCD/ONWIN.MAP').decode('utf-8',errors='replace').split('Publics by Value')[1].splitlines()
for ln in lines:
    m=re.match(r'\s*([0-9A-F]{4}):([0-9A-F]{4})\s+(?:idle\s+)?(\S+)',ln)
    if m: syms[int(m.group(1),16)].append((int(m.group(2),16),m.group(3)))
for s in syms: syms[s].sort()
def symat(seg,off):
    best=None
    for o,n in syms.get(seg,[]):
        if o<=off: best=(o,n)
        else: break
    if best is None: return '%d:%04x'%(seg,off)
    return best[1] if best[0]==off else '%s+0x%x'%(best[1],off-best[0])
def target(seg,rel):
    _st,fg,a,b=rel
    t=fg&3
    if t==0:
        if a&0xff==0xff:
            e=entries[b] if b<len(entries) else None
            return symat(*e) if e else 'ent%d'%b
        return symat(a&0xff,b)
    if t==1: return '%s.%d'%(mods[a-1] if 0<a<=len(mods) else a,b)
    return 'reloc%d'%t
COMPACT=os.environ.get('COMPACT','1')=='1'
def dsname(v,orig):
    l=syms.get(28,[])
    best=None
    n=''  # name of the symbol that ended the scan below (checked, oddly, instead of best's)
    for o,n in l:
        if o<=v: best=(o,n)
        else: break
    if best and v<0xd1ca and v>=0x30 and v-best[0]<0x400 and not n.startswith('__'):
        return orig+('<%s%s>'%(best[1],'' if best[0]==v else '+%d'%(v-best[0])))
    return orig
md=Cs(CS_ARCH_X86,CS_MODE_16); md.detail=False
def dis(name_or_addr):
    # find function
    m=re.match(r'^(\d+):([0-9a-fA-F]+)-([0-9a-fA-F]+)$',name_or_addr)
    if m:
        s=int(m.group(1)); start=int(m.group(2),16); end=int(m.group(3),16)
        return _dis(name_or_addr,s,start,end)
    cands=[]
    for s,l in syms.items():
        for i,(o,n) in enumerate(l):
            if n==name_or_addr: cands.append((s,i))
    if not cands:
        raise SystemExit('no symbol '+name_or_addr)
    s,i=cands[0]; l=syms[s]; start=l[i][0]
    end=l[i+1][0] if i+1<len(l) else len(segs[s][0])
    return _dis(name_or_addr,s,start,end)
def _dis(name_or_addr,s,start,end):
    seg,relocs=segs[s]
    print(';;', name_or_addr, '%04x:%04x-%04x'%(s,start,end))
    off=start
    while off<end:
        ins=None
        for ins in md.disasm(seg[off:end],off,1): break
        if ins is None:
            print('%04x: db %02x'%(off,seg[off])); off+=1; continue
        ann=''
        for ro in range(off,off+ins.size):
            if ro in relocs:
                ann+='  ; reloc '+target(s,relocs[ro])
        ops=ins.op_str
        if COMPACT:
            ops=re.sub(r'0x([0-9a-f]{3,4})\b',lambda m: dsname(int(m.group(1),16),m.group(0)),ops)
            print('%04x: %s %s%s'%(off,ins.mnemonic,ops,ann))
        else:
            print('%04x: %-28s %s %s%s'%(off,seg[off:off+ins.size].hex(),ins.mnemonic,ops,ann))
        off+=ins.size
if __name__=='__main__':
    for a in sys.argv[1:]: dis(a)
