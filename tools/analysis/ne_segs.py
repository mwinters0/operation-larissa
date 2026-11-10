import struct
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))   # tools/: gamefiles.py
import gamefiles
d=gamefiles.read('ONWINCD/ONWIN.EXE')
ne=struct.unpack_from('<I',d,0x3c)[0]
nseg=struct.unpack_from('<H',d,ne+0x1c)[0]
segtab=struct.unpack_from('<H',d,ne+0x22)[0]
shift=struct.unpack_from('<H',d,ne+0x32)[0]
print('nseg',nseg,'shift',shift,'entry',struct.unpack_from('<HH',d,ne+0x14))
for i in range(nseg):
    off,ln,fl,minalloc=struct.unpack_from('<HHHH',d,ne+segtab+i*8)
    print(i+1,hex(off<<shift),hex(ln),hex(fl),hex(minalloc))
