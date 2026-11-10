"""Derive per-problem-type record layouts from MATHPROB.C pick function (seg 15, 0x9ec).
Output: type -> (record_size, [(dest_offset, kind)]) kind: c=char(1) w=word(2) n=CompactNumber(7)"""
import sys, os, re, struct, json
sys.argv=['x']
from dis16 import *
seg,relocs=segs[15]
jt=0x20b9
targets=[struct.unpack_from('<H',seg,jt+2*i)[0] for i in range(34)]
order=sorted(set(targets))
FUNC_END=jt
def case_range(t):
    nxt=[o for o in order if o>t]
    return t,(nxt[0] if nxt else FUNC_END)
layouts={}
for typ,t in enumerate(targets):
    s,e=case_range(t)
    # collect instructions
    off=s; ins_l=[]
    while off<e:
        ins=None
        for ins in md.disasm(seg[off:e],off,1): break
        if ins is None: off+=1; continue
        ins_l.append(ins); off+=ins.size
    rs=None; calls=[]; cur=0; lastadd=None
    for ins in ins_l:
        m=re.match(r'imul ax, ax, (0x[0-9a-f]+|\d+)',ins.mnemonic+' '+ins.op_str)
        if m and rs is None: rs=int(m.group(1),0)
        m=re.match(r'add ax, (0x[0-9a-f]+|\d+)$',ins.mnemonic+' '+ins.op_str)
        if m: lastadd=int(m.group(1),0)
        if ins.mnemonic=='mov' and re.match(r'ax, word ptr \[0x[0-9a-f]+\]',ins.op_str): lastadd=0
        if ins.mnemonic=='inc' and ins.op_str=='ax': lastadd=1
        if ins.mnemonic=='call':
            tgt=int(ins.op_str,16) if ins.op_str.startswith('0x') else None
            if tgt in (0x8c7,0x8e8,0x909):
                calls.append((lastadd if lastadd is not None else 0,{0x8c7:'c',0x8e8:'w',0x909:'n'}[tgt]))
                lastadd=None
    layouts[typ]=(rs,calls)
if __name__=='__main__':
    for t,(rs,c) in layouts.items():
        print(t,rs,' '.join('%s@%d'%(k,o) for o,k in c))
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'prob_layouts.json'),'w') as f:
        json.dump({t:[rs,c] for t,(rs,c) in layouts.items()},f)
