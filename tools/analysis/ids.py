# usage: ids.py NEP.DLL [more...]   (files in ONWINCD/ on the CD)
import sys
from pathlib import Path
sys.path[:0] = [str(Path(__file__).resolve().parent), str(Path(__file__).resolve().parents[1])]   # tools/analysis (ne.py) and tools/ (gamefiles.py)
import gamefiles
from ne import NE
for f in sys.argv[1:]:
    n=NE(gamefiles.read('ONWINCD/'+f))
    ids=[(r[1],r[2]) for r in n.resources if r[0]!='NAMETABLE']
    print(f, len(ids))
    by={}
    for t,i in ids: by.setdefault(t,[]).append(i)
    for t,l in by.items():
        l=sorted(i for i in l if isinstance(i,int))
        # ranges
        rs=[];s=p=l[0]
        for x in l[1:]:
            if x!=p+1: rs.append((s,p)); s=x
            p=x
        rs.append((s,p)); print(' ',t,len(l),rs[:40])
