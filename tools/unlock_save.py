"""Builds a fully unlocked Lushfoil savefile.sav from any existing one (same layout, only values change):
levels, portals, photo boards, unlockable items, totems, animals and tutorials all set to done."""
import struct, sys
OFFS = {}
class R:
    def __init__(s, d): s.d=d; s.p=0
    def u8(s): v=s.d[s.p]; s.p+=1; return v
    def i32(s): v=struct.unpack_from('<i',s.d,s.p)[0]; s.p+=4; return v
    def u32(s): v=struct.unpack_from('<I',s.d,s.p)[0]; s.p+=4; return v
    def i64(s): v=struct.unpack_from('<q',s.d,s.p)[0]; s.p+=8; return v
    def f32(s): v=struct.unpack_from('<f',s.d,s.p)[0]; s.p+=4; return v
    def f64(s): v=struct.unpack_from('<d',s.d,s.p)[0]; s.p+=8; return v
    def u16(s): v=struct.unpack_from('<H',s.d,s.p)[0]; s.p+=2; return v
    def raw(s,n): v=s.d[s.p:s.p+n]; s.p+=n; return v
    def fstr(s):
        n=s.i32()
        if n==0: return ''
        if n<0: v=s.d[s.p:s.p-2*n-2].decode('utf-16le'); s.p+=-2*n; return v
        v=s.d[s.p:s.p+n-1].decode('latin1'); s.p+=n; return v
def header(r):
    assert r.raw(4)==b'GVAS'
    h={'ver':r.i32()}
    h['ue4']=r.i32()
    if h['ver']>=3: h['ue5']=r.i32()
    h['eng']=(r.u16(),r.u16(),r.u16(),r.u32(),r.fstr())
    h['cvfmt']=r.i32(); n=r.i32(); h['cv']=[(r.raw(16).hex(),r.i32()) for _ in range(n)]
    h['cls']=r.fstr(); return h
def prop_value(r, typ, size, name, inner=None):
    if typ=='IntProperty': return r.i32()
    if typ=='UInt32Property': return r.u32()
    if typ=='Int64Property': return r.i64()
    if typ=='FloatProperty': return r.f32()
    if typ=='DoubleProperty': return r.f64()
    if typ=='BoolProperty': return None
    if typ in('StrProperty','NameProperty','ObjectProperty','SoftObjectProperty'): return r.fstr()
    if typ=='ByteProperty': return r.u8()
    raise Exception('unhandled '+typ+' '+name)
def read_props(r):
    out=[]
    while True:
        name=r.fstr()
        if name=='None': return out
        typ=r.fstr(); size=r.i64(); start=None
        if typ=='BoolProperty':
            r.u8(); r.u8(); v=bool(r.d[r.p-2]); OFFS[name]=(r.p-2,1,'Bool'); out.append((name,typ,v)); continue
        if typ=='ArrayProperty':
            it=r.fstr(); r.u8(); start=r.p; n=r.i32(); items=[]; OFFS[name]=(r.p,n,it)
            if it=='StructProperty':
                nm=r.fstr(); tp=r.fstr(); sz=r.i64(); st=r.fstr(); r.raw(16); r.u8()
                for _ in range(n): items.append(read_struct(r,st))
            elif it=='BoolProperty': items=[bool(r.u8()) for _ in range(n)]
            elif it in('IntProperty',): items=[r.i32() for _ in range(n)]
            elif it in('FloatProperty',): items=[r.f32() for _ in range(n)]
            elif it in ('StrProperty','NameProperty'): items=[r.fstr() for _ in range(n)]
            else: raise Exception('array of '+it)
            assert r.p==start+size,(name,r.p,start+size)
            out.append((name,'Array<%s>'%it,items)); continue
        if typ=='StructProperty':
            st=r.fstr(); r.raw(16); r.u8(); start=r.p
            v=read_struct(r,st); assert r.p==start+size,(name,st,r.p-start,size); out.append((name,'Struct '+st,v)); continue
        if typ=='EnumProperty':
            en=r.fstr(); r.u8(); v=r.fstr(); out.append((name,typ,v)); continue
        if typ=='ByteProperty':
            en=r.fstr(); r.u8(); v=r.fstr() if en!='None' else r.u8(); out.append((name,typ,v)); continue
        if typ=='MapProperty':
            kt=r.fstr(); vt=r.fstr(); r.u8(); raw=r.raw(size); out.append((name,'Map<%s,%s>'%(kt,vt),raw)); continue
        r.u8(); start=r.p; v=prop_value(r,typ,size,name); assert r.p==start+size,(name,typ); out.append((name,typ,v))
def read_struct(r, st):
    if st=='IntPoint': return (r.i32(),r.i32())
    if st=='Vector' : return (r.f64(),r.f64(),r.f64())
    if st=='Quat': return (r.f64(),r.f64(),r.f64(),r.f64())
    if st=='Guid': return r.raw(16).hex()
    if st=='DateTime': return r.i64()
    return read_props(r)
def load(path):
    r=R(open(path,'rb').read()); h=header(r); return h, read_props(r), r

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: python -I unlock_save.py <template savefile.sav> <output.sav>")
    tpl, out = sys.argv[1], sys.argv[2]
    h, props, r = load(tpl)
    data = bytearray(r.d)
    P = {n: v for n, t, v in props}
    changed = 0
    def put(off, b):
        global changed
        if data[off] != b: data[off] = b; changed += 1
    for name, (off, n, it) in OFFS.items():
        if it == "Bool":
            if name in ("camera obtained", "GPS unlocked", "TransitionedToAnotherLevel"): put(off, 1)
        elif it == "BoolProperty":
            if name.startswith(("Home Menu Unlocked", "Portals Found", "Photo Board Progress", "Unlocked Item Progress", "Totem Progress", "Animals Seen", "Tutorials Seen")):
                for i in range(n): put(off + i, 1)
    def ints(name, values):
        off, n, it = OFFS[name]
        for i in range(min(n, len(values))): struct.pack_into("<i", data, off + 4 * i, values[i])
    ints("Saved Objective Photos", P["Total Objective Photos"])
    ints("Saved Totems", P["Total Totems"])
    ints("Saved Unlockables", [OFFS["Unlocked Item Progress Level 0"][1]] * 16)
    open(out, "wb").write(data)
    OFFS.clear()
    h2, props2, r2 = load(out)
    assert len(data) == len(r.d), "layout changed"
    print(f"wrote {out}: {changed} bytes changed, size unchanged ({len(data)})")
    for n, t, v in props2:
        if n.startswith(("Home Menu", "Portals", "Saved ", "Totem Progress Level 0", "Photo Board Progress Level 0")): print("  ", n, v)
