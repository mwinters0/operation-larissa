"""Parsers for Operation Neptune data (NEP.DLL resources). Run:  uv run tools/analysis/neptune_data.py [summary|json]
Logical->real resource id mapping comes from ONWIN.EXE resource OTHR/15001 (u16 array).
"""
import sys, struct, os
from typing import Any
HERE=os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0,HERE)
sys.path.insert(0,os.path.dirname(HERE))   # tools/: gamefiles.py reads the CD image (NEPTUNE.ISO)
import gamefiles
from ne import NE
_nep=NE(gamefiles.read('ONWINCD/NEP.DLL'))
RES={r[2]:_nep.get(r) for r in _nep.resources if isinstance(r[2],int) and r[1] in (32513,32514,32515,32516)}
_d=gamefiles.read('ONWINCD/ONWIN.EXE')
_exe=NE(_d)
_oth=next(r for r in _exe.resources if r[0]=='OTHR')
RMAP=list(struct.unpack('<%dH'%(1750//2),_exe.get(_oth)[:1750]))
def real(l): return RMAP[l] if l<=20000 else l-20000
def get(l): return RES[real(l)]
# DS tables (from ONWIN.EXE DGROUP image at file offset 0x3c200)
DS=0x3c200
def dsw(off,n): return list(struct.unpack_from('<%dH'%n,_d,DS+off))
SECTOR_TBL=dsw(0x2cca,32)   # logical ids of sector data (15874 B each)
FOE_TBL=dsw(0x2d0a,32)      # logical ids of foe buffers
BG_TBL_VOY=dsw(0x2d4a,15)
HDR=0x72; SCREEN=0x500; NSCREEN=12
def parse_sector(i):
    b=get(SECTOR_TBL[i])
    w=lambda o: struct.unpack_from('<H',b,o)[0]
    s: dict[str, Any]={'index':i,'start_x':w(0)*2,'start_y':w(2)*2,'n_pieces':w(4)}
    s['piece_screen']=list(b[6:6+s['n_pieces']])
    s['piece_x']=[w(0x11+2*k)*2 for k in range(s['n_pieces'])]
    s['piece_y']=[w(0x27+2*k)*2 for k in range(s['n_pieces'])]
    s['start_cell']=w(0x3e)
    s['hdr_unknown_0x3d']=b[0x3d]
    s['nbr']={n:list(b[o:o+12]) for n,o in (('left',0x42),('right',0x4e),('up',0x5a),('down',0x66))}  # value-1 = screen idx, 0 = none
    screens=[]
    def lst(sc,p,sz):
        n=sc[p]; return n, p+1+n*sz
    for k in range(NSCREEN):
        o=HDR+k*SCREEN; sc=b[o:o+SCREEN]
        tiles=list(sc[:38*18]); p=0x2ac
        nb,e=lst(sc,p,3); bg=[tuple(sc[p+1+3*j:p+4+3*j]) for j in range(nb)]; p=e
        nm,e=lst(sc,p,3); mg=[tuple(sc[p+1+3*j:p+4+3*j]) for j in range(nm)]; p=e
        nf,e=lst(sc,p,3); fg=[tuple(sc[p+1+3*j:p+4+3*j]) for j in range(nf)]; p=e
        na,e=lst(sc,p,22); an=[bytes(sc[p+1+22*j:p+23+22*j]).hex() for j in range(na)]; p=e
        nt,e=lst(sc,p,4); tr=[tuple(sc[p+1+4*j:p+5+4*j]) for j in range(nt)]; p=e
        # record_hex = the WHOLE original 0x500-byte record, hex, with the trailing zero bytes cut off (the rest is zero).
        # It keeps what is left after the used part (stale bytes in 7 of 384 records), which the decoded lists cannot.
        screens.append({'tiles':tiles,'bg_decos':bg,'mid_decos':mg,'fg_decos':fg,'anim_decos':an,'math_triggers':tr,'used':p,
                        'record_hex':bytes(sc).rstrip(b'\0').hex()})
    s['screens']=screens
    # Where this sector's bytes come from (provenance): NEP.DLL, logical resource id SECTOR_TBL[i] (a DS table of
    # ONWIN.EXE), real resource id from the OTHR/15001 map; tools/extract/extract_data.py saves it as the file below
    # (trailing zero bytes may be cut off there). Screen k is the 0x500 bytes at record_offset = HDR + k * SCREEN.
    s['source']={'file':'NEP.DLL','logical_id':SECTOR_TBL[i],'real_id':real(SECTOR_TBL[i]),
                 'extracted':'data/NEP_raw/NEP_%d.bin'%real(SECTOR_TBL[i]),'size':len(b)}
    for k,sc in enumerate(screens): sc['record_offset']=HDR+k*SCREEN
    return s
def parse_foes(i):
    b=get(FOE_TBL[i]); n=b[0]; recs=[]
    for k in range(n):
        r=b[1+34*k:1+34*(k+1)]
        u16=lambda o,r=r: struct.unpack_from('<H',r,o)[0]
        recs.append({'dormant':r[0],'hidden':r[1],'screen':r[2],'x':u16(3)*2,'y':u16(5)*2,'frame':r[7],'flip':r[8],
          'frame_min':r[9],'frame_max':r[10],'script_hit':u16(0xb),'script_ink':u16(0xd),'damage':r[0xf] if r[0xf]<128 else r[0xf]-256,'pc':u16(0x10)})
    # Where the records come from (provenance): the foe buffer is NEP.DLL logical resource FOE_TBL[i] (a DS table of ONWIN.EXE);
    # tools/extract/extract_data.py saves it as the file below (trailing zero bytes cut off). Byte 0 is the record count,
    # record k is the 34 bytes at record_offset = 1 + 34 * k, then the script bytecode.
    source={'file':'NEP.DLL','logical_id':FOE_TBL[i],'real_id':real(FOE_TBL[i]),
            'extracted':'data/NEP_raw/NEP_%d.bin'%real(FOE_TBL[i]),'size':len(b)}
    return {'n':n,'records':recs,'script_base':1+34*n,'script_bytes':len(b.rstrip(b'\0')),'source':source}
if __name__=='__main__':
    mode=sys.argv[1] if len(sys.argv)>1 else 'summary'
    if mode=='summary':
        for i in range(32):
            s=parse_sector(i); f=parse_foes(i)
            print(i,'start',s['start_x'],s['start_y'],'pieces',s['n_pieces'],'screens-used',[sc['used'] for sc in s['screens']][:3],'foes',f['n'],'triggers',[len(sc['math_triggers']) for sc in s['screens']])
