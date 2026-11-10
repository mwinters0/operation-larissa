"""Rebuild docs/data/problem_layouts32.json from the decompiled problem-record reader.

  ./run.sh dump_c.py /tmp/pick.c ReadProblemRecord      # (before apply_problem_types.py is fine; names optional)
  uv run derive_problem_layouts.py /tmp/pick.c           # plain python, no Ghidra needed

The reader is one big switch(type); each case calls bytes_to_char / bytes_to_word / bytes_to_CompactNumberType
(1, 2 and 7 file bytes) with an explicit destination offset in the in-memory struct, so the decompilation
is a complete, ordered field list for every record layout.
"""
import json, re, sys
from pathlib import Path
src = Path(sys.argv[1]).read_text()
m = re.search(r'// ==== (?:ReadProblemRecord|FUN_00423c0e).*?(?=\n// ==== |\Z)', src, re.DOTALL)
if m is None:
    raise SystemExit('ReadProblemRecord not found in ' + sys.argv[1])
body = m.group(0)
FN = {'bytes_to_char': 'c', 'FUN_00423b98': 'c', 'bytes_to_word': 'w', 'FUN_00423bac': 'w',
      'bytes_to_CompactNumberType': 'n', 'FUN_00423bc2': 'n'}
SZ = {'c': 1, 'w': 2, 'n': 7}; MSZ = {'c': 1, 'w': 2, 'n': 9}
parts = re.split(r'\n  case (0x[0-9a-f]+|\d+):', body)
types = {}; pending = []
for i in range(1, len(parts), 2):
    label = int(parts[i], 0); text = parts[i + 1]
    if not text.strip():
        pending.append(label); continue
    m_glob = re.search(r'(DAT_[0-9a-f]+) = &DAT_004499b4;', text)
    m_rs = re.search(r'iVar5 \* (0x[0-9a-f]+|\d+) \+ 1', text)
    if m_glob is None or m_rs is None:
        raise SystemExit('case %d: record global / size not found' % label)
    glob = m_glob.group(1)
    rs = int(m_rs.group(1), 0)
    fields = []
    for call in re.finditer(r'(%s)\(([^;]*?)\);' % '|'.join(FN), text):
        fn, args = call.groups(); dst = args.rsplit(',', 1)[1]
        m_base = re.search(r'\+ iVar5 \+ (0x[0-9a-f]+|\d+)', dst)
        if '&DAT_004499b4' in dst: off = 0
        elif m_base:   # unrolled 9-byte loop
            base = int(m_base.group(1), 0)
            fields += [(base + j, 'c') for j in range(9)]; continue
        else:
            m_off = re.search(r'\+ (0x[0-9a-f]+|\d+)\)?\)?$', dst.strip())
            if m_off is None:
                raise SystemExit('cannot parse field offset: ' + dst)
            off = int(m_off.group(1), 0)
        fields.append((off, FN[fn]))
    for t in pending + [label]:
        foff = 0; fl = []
        for mo, k in fields:
            fl.append(dict(kind=k, mem_off=mo, file_off=foff)); foff += SZ[k]
        assert foff == rs, (t, foff, rs)
        types[str(t)] = {"global": "0x" + glob[4:], "record_size": foff,
                         "mem_size": max(f['mem_off'] + MSZ[f['kind']] for f in fl), "fields": fl}
    pending = []
out = {"note": "Record layouts of the 34 problem types. mem_off = byte offset in ONWIN32.EXE's in-memory struct "
               "(CompactNumber = 9 bytes), file_off = offset inside one stored record in NEP.DLL.", "types": types}
dst = Path(__file__).resolve().parents[3] / "docs/data/problem_layouts32.json"
dst.write_text(json.dumps(out, indent=1)); print("wrote", dst, len(types), "types")
