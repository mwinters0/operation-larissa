import struct
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))   # tools/: gamefiles.py
import gamefiles
d=gamefiles.read('ONWINCD/ONWIN.EXE')
DS=0x3c200
def w(off,n): return list(struct.unpack_from('<%dH'%n,d,DS+off))
def sw(off,n): return list(struct.unpack_from('<%dh'%n,d,DS+off))
def cstr(off):
    e=d.index(b'\0',DS+off); return d[DS+off:e]
if __name__=='__main__':
    for name,off,n in [('sector tbl A',0x2cca,30),('sector tbl B',0x2d0a,30),('bg voy',0x2d4a,15),('bg exp',0x2d68,15)]:
        print(name,w(off,n))
