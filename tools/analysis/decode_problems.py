"""Decode the stored problem tables (NEP.DLL ids 10512+4*type+level) into docs/data/problem_records.json
using the verified record layouts in docs/data/problem_layouts32.json.

CompactNumber (7 bytes in the file) [V, ONWIN32 bytes_to_CompactNumberType (0x423bc2) / CompactToNumber (0x427ee4) / NumberToDouble (0x42837c)]:
  u16 kind
  kind 0 (decimal):  u8 exp, i32 raw      -> value = raw / 10**exp   (exp = digits shown after the point)
  kind 1 (fraction): i8 whole, i8 num (negative mixed numbers store both negative), u16 den, (1 unused byte) -> value = whole + num/den
Usage: uv run tools/analysis/decode_problems.py [out.json]
"""
import json, struct, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
LAY = json.loads((ROOT / "docs/data/problem_layouts32.json").read_text())["types"]
RAW = str(ROOT / "extracted/data/NEP_raw/NEP_%d.bin")
SZ = {"c": 1, "w": 2, "n": 7}

def num(b):
    kind = struct.unpack_from("<H", b)[0]
    if kind == 0:
        exp = b[2]; raw = struct.unpack_from("<i", b, 3)[0]
        return {"k": 0, "raw": raw, "exp": exp, "v": raw / 10 ** exp}
    if kind == 1:
        whole = struct.unpack_from("<b", b, 2)[0]; n = struct.unpack_from("<b", b, 3)[0]; d = struct.unpack_from("<H", b, 4)[0]
        return {"k": 1, "whole": whole, "num": n, "den": d, "v": whole + (n / d if d else 0)}
    return {"k": kind, "hex": b.hex()}

def decode_table(t, lv):
    d = RAW % (10512 + 4 * t + lv)
    d = Path(d).read_bytes() + b"\0" * 8192   # extractor trimmed trailing zeros
    spec = LAY[str(t)]; rs = spec["record_size"]; n = d[0]; recs = []
    for i in range(n):
        o = 1 + i * rs; rec = []
        for f in spec["fields"]:
            p = o + f["file_off"]; k = f["kind"]
            rec.append(d[p] if k == "c" else struct.unpack_from("<H", d, p)[0] if k == "w" else num(d[p:p + 7]))
        recs.append(rec)
    return recs

def main():
    out = {str(t): {"record_size": LAY[str(t)]["record_size"],
                    "fields": [f["kind"] for f in LAY[str(t)]["fields"]],
                    "levels": [decode_table(t, lv) for lv in range(4)]} for t in range(34)}
    dst = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/data/problem_records.json"
    dst.write_text(json.dumps(out, separators=(",", ":")))
    print("wrote", dst, sum(len(l) for t in out.values() for l in t["levels"]), "records")

if __name__ == "__main__":
    main()
