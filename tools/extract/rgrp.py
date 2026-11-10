"""Reader for TLC 'RGrp' archive files (ASSETS/*.GRP on the CD).

Group layout (all integers big-endian):
    +0   'RGrp'
    +4   u32 0
    +8   u32 count
    +12  u32 directory offset (relative to the start of this group)
    ...  member data ...
    dir: count * 16 bytes: char tag[4], u32 id, u32 size, u32 offset (relative to start of this group)
Members with tag 'RGrp' are nested groups (offset is again relative to the parent group start).
"""
import struct

class Entry:
    def __init__(self, tag, id, size, off, data):
        self.tag, self.id, self.size, self.off, self.data = tag, id, size, off, data

def parse_group(buf, base=0, depth=0):
    magic, _z, count, dir_off = struct.unpack_from('>4sIII', buf, base)
    assert magic == b'RGrp', (hex(base), magic)
    out = []
    for i in range(count):
        tag, id_, size, off = struct.unpack_from('>4sIII', buf, base + dir_off + 16 * i)
        tag = tag.decode('latin1')
        start = base + off
        if tag == 'RGrp':
            out.append(Entry(tag, id_, size, start, parse_group(buf, start, depth + 1)))
        else:
            out.append(Entry(tag, id_, size, start, buf[start:start + size]))
    return out

def walk(entries, path=()):
    for e in entries:
        if e.tag == 'RGrp':
            yield from walk(e.data, path + (e.id,))
        else:
            yield path, e
