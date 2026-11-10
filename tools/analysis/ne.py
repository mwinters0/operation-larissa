"""Minimal Win16 NE executable/DLL resource reader."""
import struct
from pathlib import Path

RT = {1:'CURSOR',2:'BITMAP',3:'ICON',4:'MENU',5:'DIALOG',6:'STRING',7:'FONTDIR',8:'FONT',
      9:'ACCELERATOR',10:'RCDATA',12:'GROUP_CURSOR',14:'GROUP_ICON',15:'NAMETABLE',16:'VERSION'}

class NE:
    def __init__(self, source):
        """source = the file's bytes (e.g. gamefiles.read('ONWINCD/NEP.DLL')) or a path to read them from."""
        self.data = d = bytes(source) if isinstance(source, (bytes, bytearray)) else Path(source).read_bytes()
        assert d[:2] == b'MZ'
        self.ne = struct.unpack_from('<I', d, 0x3c)[0]
        assert d[self.ne:self.ne+2] == b'NE', 'not NE'
        self.resources = []   # (type_name, type_id, res_id_or_name, offset, length, flags)
        self._parse()

    def _parse(self):
        d, ne = self.data, self.ne
        rt_off = struct.unpack_from('<H', d, ne+0x24)[0]
        self.nseg = struct.unpack_from('<H', d, ne+0x1c)[0]
        base = ne + rt_off
        shift = struct.unpack_from('<H', d, base)[0]
        self.shift = shift
        p = base + 2
        while True:
            tid = struct.unpack_from('<H', d, p)[0]
            if tid == 0: break
            n = struct.unpack_from('<H', d, p+2)[0]
            p += 8
            for _ in range(n):
                off, ln, fl, rid = struct.unpack_from('<HHHH', d, p)
                p += 12
                if tid & 0x8000:
                    tname_id = tid & 0x7fff
                    tname = RT.get(tname_id, 'TYPE%d' % tname_id)
                else:
                    tname_id = tid
                    tname = self._rname(base + tid)
                if rid & 0x8000: rname = rid & 0x7fff
                else: rname = self._rname(base + rid)
                self.resources.append((tname, tname_id, rname, off << shift, ln << shift, fl))
        # NB: length stored in alignment units too
    def _rname(self, p):
        n = self.data[p]
        return self.data[p+1:p+1+n].decode('latin1')

    def get(self, res):
        _, _, _, off, ln, _ = res
        return self.data[off:off+ln]
