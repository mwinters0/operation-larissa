"""Find code referencing a DS offset range. usage: xref16.py lo hi  (hex)"""
import collections
import re
import sys

from dis16 import md, segs, symat

lo=int(sys.argv[1],16); hi=int(sys.argv[2],16)
res=collections.defaultdict(list)
for s,(seg,relocs) in segs.items():
    if s>=27: continue
    off=0
    while off<len(seg):
        ins=None
        for ins in md.disasm(seg[off:],off,1): break
        if ins is None: off+=1; continue
        # find 16-bit displacement values in the instruction bytes
        b=seg[off:off+ins.size]
        found=False
        txt=ins.op_str
        for m in re.finditer(r'0x([0-9a-f]+)|-0x([0-9a-f]+)',txt):
            v=int(m.group(1),16) if m.group(1) else (0x10000-int(m.group(2),16))
            if lo<=v<hi: found=True
        if found:
            res[(s)].append((off,ins.mnemonic+' '+ins.op_str))
        off+=ins.size
for s,l in sorted(res.items()):
    last=None
    for off,t in l:
        print('%s %04x %s'%(symat(s,off),off,t))
