# usage: list_res.py NEP.DLL [more...]   (files in ONWINCD/ on the CD)
import collections
import sys
from pathlib import Path
sys.path[:0] = [str(Path(__file__).resolve().parent), str(Path(__file__).resolve().parents[1])]   # tools/analysis (ne.py) and tools/ (gamefiles.py)
import gamefiles
from ne import NE
for f in sys.argv[1:]:
    n=NE(gamefiles.read('ONWINCD/'+f))
    c=collections.Counter(); sz=collections.Counter()
    for r in n.resources:
        c[r[0]]+=1; sz[r[0]]+=r[4]
    print(f, len(n.resources), {k:(c[k],sz[k]) for k in c})
