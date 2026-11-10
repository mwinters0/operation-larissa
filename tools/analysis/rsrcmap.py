import sys,struct
from pathlib import Path
sys.path[:0] = [str(Path(__file__).resolve().parent), str(Path(__file__).resolve().parents[1])]   # tools/analysis (ne.py) and tools/ (gamefiles.py)
import gamefiles
from ne import NE
from ds import *
for o in (0x10b,0x110,0x115,0x11a,0x11f,0x124,0x129,0x12e): print(hex(o),cstr(o))
n=NE(gamefiles.read('ONWINCD/ONWIN.EXE'))
for r in n.resources:
    if r[0] in('OTHR','TEXT'): print(r[:3],r[4]); 
r=next(r for r in n.resources if r[0]=='OTHR')
b=n.get(r)
# true length unknown; 15001 PE says 1750 bytes
tab=struct.unpack_from('<%dH'%(1750//2),b,0)
for i in list(range(12))+list(range(50,66)): print(i,tab[i])
print(len(tab))
