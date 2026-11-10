"""Disassemble the enemy ('animal') bytecode found in foe buffers (see docs/port/DESIGN.md section on Foes)."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from neptune_data import *
OPS=['YIELD','JMP','HANDLER','RET','LOOP0','LOOP1','LOOP2','SOUND','SLEEP_FOE','WAKE_FOE','FRAME_RANGE','SET_FRAME',
 'MOVE_REL','SET_POS','SET_POS_SCREEN','HIDE','SHOW','IF_SUBX_GT','IF_SUBX_LT','IF_SUBY_GT','IF_SUBY_LT','IF_RAND_GT','SEM_SET','SEM_CLR','IF_SEM']
NOPERAND=[0,2,2,0,4,4,4,1,1,1,2,1,3,3,4,0,0,1,1,1,1,1,1,1,1]
def dis(buf,pc,maxn=40):
    out=[]
    for _ in range(maxn):
        op=buf[pc]; 
        if op>24: out.append('%04d: ??%d'%(pc,op)); break
        n=NOPERAND[op]; args=list(buf[pc+1:pc+1+n]); out.append('%04d: %s %s'%(pc,OPS[op],' '.join(map(str,args)))); pc+=1+n
        if op in (0,3): break
    return out
if __name__=='__main__':
    i=int(sys.argv[1]); b=get(FOE_TBL[i]); f=parse_foes(i)
    seen=set()
    for k,r in enumerate(f['records'][:int(sys.argv[2]) if len(sys.argv)>2 else 4]):
        print('foe',k,{kk:r[kk] for kk in ('screen','x','y','frame','frame_min','frame_max','damage')})
        for name in ('pc','script_hit','script_ink'):
            if r[name] in seen and name!='pc': continue
            seen.add(r[name]); print(' ',name); print('\n'.join('    '+l for l in dis(b,r[name])))
