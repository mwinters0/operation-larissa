"""RUND sprite/background decoder (Operation Neptune, TLC 1996).

Resource layout:  u16 width, u16 height, b'RUND', RLE stream of 8-bit palette indices.
RLE control byte c:
    c & 0x80 set   -> repeat the following single byte (c & 0x7f) times
    c & 0x80 clear -> copy the following c bytes literally
The stream ends when width*height pixels have been produced (the rest of the
resource is zero padding to a 512-byte boundary).
"""
import struct

TRANSPARENT_INDEX = 200   # 0xC8 -- fully surrounds sprites in NEP256.DLL (docs/port/ASSET_FORMATS.md)

def decode_rund(data):
    w, h, tag = struct.unpack_from('<HH4s', data, 0)
    if tag != b'RUND':
        raise ValueError('not RUND')
    total = w * h
    out = bytearray()
    p = 8
    n = len(data)
    while len(out) < total and p < n:
        c = data[p]; p += 1
        if c & 0x80:
            cnt = c & 0x7f
            if cnt == 0 or p >= n:
                continue
            out += bytes([data[p]]) * cnt; p += 1
        else:
            out += data[p:p+c]; p += c
    short = total - len(out)
    if short > 0:
        out += bytes(short)          # truncated stream -> pad with index 0
    return w, h, bytes(out[:total]), short
