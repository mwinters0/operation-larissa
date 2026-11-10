# usage: dump_nep.py NEP.DLL   (a file in ONWINCD/ on the CD)
import sys
from pathlib import Path
sys.path[:0] = [str(Path(__file__).resolve().parent), str(Path(__file__).resolve().parents[1])]   # tools/analysis (ne.py) and tools/ (gamefiles.py)
import gamefiles
from ne import NE
n=NE(gamefiles.read('ONWINCD/'+sys.argv[1]))
for r in n.resources:
    if r[0]=='NAMETABLE': continue
    d=n.get(r)
    print(r[0],r[1],r[2],r[3],r[4],d[:24].hex())
