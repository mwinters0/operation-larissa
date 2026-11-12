"""A small standard MIDI file reader for the AdLib research scripts: tracks of events, a tempo map, and notes with their times.

Teaches: the B*.MID files are format 0 (one track, 480 ticks per beat) with running status and one tempo; `notes()` returns
`[tick, seconds, channel (1-16), key, velocity, program, duration in ticks]`. Reads the files at run time from `extracted/music/`.
Run: `uv run tools/analysis/adlib/midi.py [BSECT1 ...]` prints tempo, notes per (channel, program) and velocity range.
"""
import struct
import sys
from pathlib import Path

import paths

paths.ensure_utf8()
def vlq(d,p):
    v=0
    while True:
        b=d[p];p+=1;v=(v<<7)|(b&127)
        if not b&128:return v,p
def parse(path):
    d=Path(path).read_bytes()
    assert d[:4]==b'MThd'
    fmt,ntr,div=struct.unpack('>HHH',d[8:14])
    p=14;tracks=[]
    for _ in range(ntr):
        assert d[p:p+4]==b'MTrk'
        ln=struct.unpack('>I',d[p+4:p+8])[0];q=p+8;end=q+ln;p=end
        t=0;rs=None;ev=[]
        while q<end:
            dt,q=vlq(d,q);t+=dt
            s=d[q]
            if s==0xFF:
                ty=d[q+1];l,q2=vlq(d,q+2);ev.append((t,'meta',ty,bytes(d[q2:q2+l])));q=q2+l;continue
            if s in(0xF0,0xF7):
                l,q2=vlq(d,q+1);q=q2+l;continue
            if s&0x80:rs=s;q+=1
            else:s=rs
            n=2 if (s&0xF0) not in (0xC0,0xD0) else 1
            ev.append((t,'ch',s,tuple(d[q:q+n])));q+=n
        tracks.append(ev)
    return fmt,div,tracks
def tempo_map(tracks):
    tm=[]
    for tr in tracks:
        for e in tr:
            if e[1]=='meta' and e[2]==0x51:tm.append((e[0],int.from_bytes(e[3],'big')))
    tm.sort()
    if not tm or tm[0][0]>0:tm.insert(0,(0,500000))
    return tm
def tick2sec(tm,div):
    # returns function
    segs=[];s=0.0;pt,pu=0,500000
    for t,u in tm:
        s+=(t-pt)*pu/div/1e6;pt,pu=t,u;segs.append((t,s,u))
    def f(t):
        r=segs[0]
        for sg in segs:
            if sg[0]<=t:r=sg
        return r[1]+(t-r[0])*r[2]/div/1e6
    return f
def notes(path):
    _fmt,div,tr=parse(path);tm=tempo_map(tr);f=tick2sec(tm,div)
    out=[] # (tick,sec,ch,key,vel,prog,dur_ticks)
    prog={}
    for tr1 in tr:
        on={}
        for e in tr1:
            if e[1]!='ch':continue
            t,_,s,dat=e;ty=s&0xF0;ch=s&15
            if ty==0xC0:prog[ch]=dat[0]
            elif ty==0x90 and dat[1]>0:
                on[(ch,dat[0])]=len(out);out.append([t,f(t),ch+1,dat[0],dat[1],prog.get(ch,0),None])
            elif ty==0x80 or (ty==0x90 and dat[1]==0):
                i=on.pop((ch,dat[0]),None)
                if i is not None:out[i][6]=t-out[i][0]
    out.sort(key=lambda x:x[0])
    return out,div,tm,tr
if __name__=='__main__':
    import collections
    for n in (sys.argv[1:] or ['BSECT1','BSECT2','BSECT3','BSECT4','BSECT5','BSECT6','BEND','BNEPT2','BEND2','BNEPT1']):
        no,div,tm,tr=notes(str(paths.MUSIC/(n+'.MID')))
        c=collections.Counter((x[2],x[5]) for x in no)
        print(n,'div',div,'tempos',tm[:4],len(tm),'len s %.1f'%no[-1][1],'notes',len(no))
        print('  ',sorted(c.items()))
        vel=collections.Counter(x[4] for x in no); print('   vel',sorted(vel.items())[:3],sorted(vel.items())[-2:])
        # program changes
        pc=[(e[0],e[2]&15,e[3][0]) for t in tr for e in t if e[1]=='ch' and e[2]&0xF0==0xC0]
        print('   pcs',pc[:20],len(pc))
