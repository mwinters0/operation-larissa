"""Export sectors, foes and problem tables to JSON for the Godot port. Usage: uv run tools/analysis/export_json.py <outdir>"""
import sys,json,os
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from neptune_data import *
from neptune_data import _d
out=sys.argv[1]; os.makedirs(out,exist_ok=True)
sectors=[]
for i in range(32):
    s=parse_sector(i); s['foes']=parse_foes(i)
    s['foe_script_bytes_hex']=get(FOE_TBL[i]).rstrip(b'\0').hex()
    sectors.append(s)
with open(out+'/sectors.json','w') as f: json.dump(sectors,f)
probs={}
for t in range(34):
    probs[t]={'levels':[get(0x118+t*4+L).rstrip(b'\0').hex() for L in range(4)],
              'text_bundle_real_id':43+t,'gfx_bundle_logical':dsw(0x227a,34)[t]}
with open(out+'/problem_tables_raw.json','w') as f: json.dump(probs,f)
tbl=list(_d[DS+0x22be:DS+0x22be+0x1fa])
with open(out+'/trigger_table.json','w') as f:
    json.dump({'trigger_to_type':[[ [tbl[t*8+L*2],tbl[t*8+L*2+1]] for L in range(4)] for t in range(63)]},f)
# Default educational level per zone, DS 0x25A8, 10 bytes indexed game*5+zone (DESIGN 3.8), for tools/import/ds_tables.py.
with open(out+'/zone_defaults.json','w') as f:
    json.dump({'source':{'file':'ONWIN.EXE','ds_offset':0x25a8,'file_offset':DS+0x25a8,'size':10},
               'default_edu_level':list(_d[DS+0x25a8:DS+0x25a8+10])},f)
print('ok')
