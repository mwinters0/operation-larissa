import sys
from pathlib import Path
sys.path[:0] = [str(Path(__file__).resolve().parent), str(Path(__file__).resolve().parents[1])]   # tools/analysis (ne.py) and tools/ (gamefiles.py)
import gamefiles
from ne import NE
n=NE(gamefiles.read('ONWINCD/NEP.DLL'))
res={r[2]:n.get(r) for r in n.resources if r[1]==32515}
def show(b):
    b=b.rstrip(b'\0')
    return ''.join(chr(c) if 32<=c<127 else '\\x%02x'%c if c!=10 else '\\n' for c in b)
lo,hi=int(sys.argv[1]),int(sys.argv[2])
for i in range(lo,hi):
    if i in res: print(i, show(res[i]))
