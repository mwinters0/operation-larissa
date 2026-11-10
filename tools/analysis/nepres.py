import sys
import struct
from pathlib import Path
sys.path[:0] = [str(Path(__file__).resolve().parent), str(Path(__file__).resolve().parents[1])]   # tools/analysis (ne.py) and tools/ (gamefiles.py)
import gamefiles
from ne import NE
_n=NE(gamefiles.read('ONWINCD/NEP.DLL'))
_res={r[2]:_n.get(r) for r in _n.resources if r[1] in (32513,32514,32515,32516)}
# logical -> real resource id: ONWIN.EXE resource OTHR/15001, a u16 array of 875 entries (1750 bytes)
_exe=NE(gamefiles.read('ONWINCD/ONWIN.EXE'))
_map=struct.unpack('<875H',_exe.get(next(r for r in _exe.resources if r[0]=='OTHR'))[:1750])
def real(l): return _map[l] if l<=20000 else l-20000
def get(l): return _res[real(l)]
def hexdump(b,w=16,start=0):
    for i in range(0,len(b),w):
        print('%04x  %s'%(start+i,' '.join('%02x'%x for x in b[i:i+w])))
if __name__=='__main__':
    l=int(sys.argv[1]); b=get(l).rstrip(b'\0') if len(sys.argv)<4 else get(l)
    print(l,'->',real(l),len(b))
    hexdump(b[:int(sys.argv[2])] if len(sys.argv)>2 else b)
