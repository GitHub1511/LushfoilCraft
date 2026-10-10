"""
Generates the Minecraft assets LushfoilCraft needs, from your own Minecraft client jar (stays on your machine, private use):

  textures/<block>_<face>.png   one square PNG per distinct block face (all / top / bottom / side), nearest-neighbour upscaled
  textures/steve_<part>_<face>.png   the player skin cropped per body-part face
  Scripts/blocks.lua            manifest: every full-cube block and which faces it has

Usage: python make_assets.py <minecraft client jar> <output folder = LushfoilCraft>
Standard library only.
"""
import json, struct, sys, zlib, zipfile, os, re

SCALE = 8  # 16px -> 128px

# ---------------------------------------------------------------- minimal PNG codec (8 bit, non-interlaced)
def png_decode(data):
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos, idat, plte, trns = 8, b"", None, None
    while pos < len(data):
        ln, typ = struct.unpack(">I4s", data[pos:pos + 8]); body = data[pos + 8:pos + 8 + ln]; pos += 12 + ln
        if typ == b"IHDR": w, h, depth, ctype, _, _, inter = struct.unpack(">IIBBBBB", body)
        elif typ == b"PLTE": plte = body
        elif typ == b"tRNS": trns = body
        elif typ == b"IDAT": idat += body
    assert inter == 0, "interlaced png"
    ch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    bpp = depth * ch                      # bits per pixel
    bpb = max(1, bpp // 8)                # filter unit in bytes
    stride = (w * bpp + 7) // 8
    raw = zlib.decompress(idat); rows = []; prev = bytearray(stride); p = 0
    for _ in range(h):
        f = raw[p]; line = bytearray(raw[p + 1:p + 1 + stride]); p += 1 + stride
        for i in range(stride):
            a = line[i - bpb] if i >= bpb else 0; b = prev[i]; c = prev[i - bpb] if i >= bpb else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        rows.append(line); prev = line
    def sample(line, idx):                # idx-th sample (channel) of the row, scaled to 0..255 (palette/gray<8 bit returns raw index)
        if depth == 8: return line[idx]
        if depth == 16: return line[idx * 2]
        per = 8 // depth; byte = line[idx // per]; shift = 8 - depth * (idx % per + 1)
        return (byte >> shift) & ((1 << depth) - 1)
    px = []
    for line in rows:
        row = []
        for x in range(w):
            if ctype == 6: r, g, b, a = (sample(line, x * 4 + k) for k in range(4))
            elif ctype == 2: r, g, b = (sample(line, x * 3 + k) for k in range(3)); a = 255
            elif ctype == 0:
                v = sample(line, x); v = v * 255 // ((1 << depth) - 1) if depth < 8 else v; r = g = b = v; a = 255
            elif ctype == 4: r = g = b = sample(line, x * 2); a = sample(line, x * 2 + 1)
            else:
                i = sample(line, x); r, g, b = plte[i * 3:i * 3 + 3]; a = trns[i] if trns and i < len(trns) else 255
            row.append((r, g, b, a))
        px.append(row)
    return w, h, px

def png_encode(px):
    h, w = len(px), len(px[0])
    raw = b"".join(b"\x00" + bytes(v for p in row for v in p) for row in px)
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")

def upscale(px, k):
    return [[p for p in row for _ in range(k)] for row in px for _ in range(k)]

def crop(px, x, y, w, h): return [row[x:x + w] for row in px[y:y + h]]

def first_frame(px):  # animated textures are vertical strips of square frames
    w = len(px[0]); return px[:w] if len(px) > w else px

def tint(px, rgb):
    return [[(p[0] * rgb[0] // 255, p[1] * rgb[1] // 255, p[2] * rgb[2] // 255, p[3]) for p in row] for row in px]

def over(top, bottom):  # alpha composite top over bottom
    out = []
    for rt, rb in zip(top, bottom):
        row = []
        for t, b in zip(rt, rb):
            a = t[3] / 255.0
            row.append((int(t[0] * a + b[0] * (1 - a)), int(t[1] * a + b[1] * (1 - a)), int(t[2] * a + b[2] * (1 - a)), 255 if (t[3] + b[3]) > 0 else 0))
        out.append(row)
    return out

def flatten(px, bg):  # opaque result for materials that have no alpha
    return over(px, [[bg] * len(px[0]) for _ in px])

GRASS = (121, 192, 90); FOLIAGE = (89, 174, 48); SPRUCE = (97, 153, 97); BIRCH = (128, 167, 85)

def main(jar, out):
    z = zipfile.ZipFile(jar)
    names = set(z.namelist())
    def jload(n): return json.loads(z.read(n))
    def texpng(name):  # "minecraft:block/stone" or "block/stone"
        n = "assets/minecraft/textures/" + name.replace("minecraft:", "") + ".png"
        return png_decode(z.read(n))[2] if n in names else None

    os.makedirs(os.path.join(out, "textures"), exist_ok=True)
    os.makedirs(os.path.join(out, "Scripts"), exist_ok=True)

    elements_of = {}
    def resolve(model):
        texs, chain, m = {}, [], model
        first_elements = None
        while m:
            path = "assets/minecraft/models/" + m.replace("minecraft:", "") + ".json"
            if path not in names: break
            d = jload(path); chain.append(m.replace("minecraft:", ""))
            if first_elements is None and d.get("elements"): first_elements = d["elements"]
            for k, v in d.get("textures", {}).items(): texs.setdefault(k, v)
            m = d.get("parent")
        elements_of[model] = first_elements
        def deref(v):
            seen = 0
            while isinstance(v, str) and v.startswith("#") and seen < 10: v = texs.get(v[1:]); seen += 1
            return v
        return chain, {k: deref(v) for k, v in texs.items()}

    cube_roots = {"block/cube_all", "block/cube_column", "block/cube_column_horizontal", "block/cube_bottom_top", "block/cube", "block/orientable",
                  "block/orientable_with_bottom", "block/cube_mirrored_all", "block/cube_directional", "block/cube_top", "block/cube_column_mirrored"}
    blocks = []  # (name, {face: pixels})
    skipped = 0
    for n in sorted(x for x in names if x.startswith("assets/minecraft/blockstates/") and x.endswith(".json")):
        name = n.rsplit("/", 1)[1][:-5]
        d = jload(n)
        if "variants" not in d: skipped += 1; continue
        v = list(d["variants"].values())[0]
        v = v[0] if isinstance(v, list) else v
        chain, t = resolve(v["model"])
        root = next((c for c in chain if c in cube_roots), None)
        if not root:
            els = elements_of.get(v["model"]) or []
            if els and els[0].get("from") == [0, 0, 0] and els[0].get("to") == [16, 16, 16] and all(f in els[0].get("faces", {}) for f in ("up", "down", "north")):
                fc = els[0]["faces"]
                def deref(x):
                    n = 0
                    while isinstance(x, str) and x.startswith("#") and n < 10: x = t.get(x[1:]); n += 1
                    return x
                t = dict(t); t["up"] = deref(fc["up"]["texture"]); t["down"] = deref(fc["down"]["texture"]); t["north"] = deref(fc["north"]["texture"])
                root = "elements"
        if not root or name in ("water", "lava", "air", "cave_air", "void_air", "barrier", "light", "structure_void", "moving_piston"): skipped += 1; continue
        def g(*keys):
            for k in keys:
                if t.get(k): return t[k]
            return None
        top = g("up", "top", "end", "all"); bottom = g("down", "bottom", "end", "all"); side = g("north", "side", "front", "all", "east")
        if not (top and bottom and side): skipped += 1; continue
        faces = {"top": texpng(top), "bottom": texpng(bottom), "side": texpng(side)}
        if any(v is None for v in faces.values()): skipped += 1; continue
        faces = {k: first_frame(v) for k, v in faces.items()}
        # biome tints (the jar stores these as grey): use the default plains/forest colours
        if name == "grass_block":
            faces["top"] = tint(faces["top"], GRASS)
            ov = texpng("block/grass_block_side_overlay")
            if ov: faces["side"] = over(tint(first_frame(ov), GRASS), faces["side"])
        if name.endswith("leaves") and "azalea" not in name and "cherry" not in name:
            c = SPRUCE if name.startswith("spruce") else BIRCH if name.startswith("birch") else FOLIAGE
            for k in faces: faces[k] = tint(faces[k], c)
        # leaves and glass-like textures have transparent pixels: flatten onto a dark / light backdrop so the block is solid
        for k in faces:
            if any(p[3] < 250 for row in faces[k] for p in row):
                bg = (22, 40, 18, 255) if "leaves" in name else (190, 215, 225, 255)
                faces[k] = flatten(faces[k], bg)
        blocks.append((name, faces))

    manifest = []
    for name, faces in blocks:
        same = faces["top"] == faces["bottom"] == faces["side"]
        kinds = ["all"] if same else ["top", "bottom", "side"]
        for k in kinds:
            png = png_encode(upscale(faces["top" if k == "all" else k], SCALE))
            open(os.path.join(out, "textures", f"{name}_{k}.png"), "wb").write(png)
        manifest.append((name, kinds))

    with open(os.path.join(out, "Scripts", "blocks.lua"), "w") as f:
        f.write("-- generated by tools/make_assets.py: every full-cube Minecraft block and which texture faces it has\nreturn {\n")
        for name, kinds in manifest:
            f.write(f'  {{ "{name}", "{",".join(kinds)}" }},\n')
        f.write("}\n")

    # ---------------------------------------------------------------- Steve
    skin = None
    for cand in ("assets/minecraft/textures/entity/player/wide/steve.png", "assets/minecraft/textures/entity/steve.png"):
        if cand in names: skin = png_decode(z.read(cand))[2]; break
    if skin is None: raise SystemExit("steve skin not found in jar")
    # (x, y, w, h) per face; classic layout, second layer (hat, jacket, sleeves, pants) offsets in LAYER2
    parts = {
        "head":  {"top": (8, 0, 8, 8), "bottom": (16, 0, 8, 8), "right": (0, 8, 8, 8), "front": (8, 8, 8, 8), "left": (16, 8, 8, 8), "back": (24, 8, 8, 8)},
        "body":  {"top": (20, 16, 8, 4), "bottom": (28, 16, 8, 4), "right": (16, 20, 4, 12), "front": (20, 20, 8, 12), "left": (28, 20, 4, 12), "back": (32, 20, 8, 12)},
        "rarm":  {"top": (44, 16, 4, 4), "bottom": (48, 16, 4, 4), "right": (40, 20, 4, 12), "front": (44, 20, 4, 12), "left": (48, 20, 4, 12), "back": (52, 20, 4, 12)},
        "larm":  {"top": (36, 48, 4, 4), "bottom": (40, 48, 4, 4), "right": (32, 52, 4, 12), "front": (36, 52, 4, 12), "left": (40, 52, 4, 12), "back": (44, 52, 4, 12)},
        "rleg":  {"top": (4, 16, 4, 4), "bottom": (8, 16, 4, 4), "right": (0, 20, 4, 12), "front": (4, 20, 4, 12), "left": (8, 20, 4, 12), "back": (12, 20, 4, 12)},
        "lleg":  {"top": (20, 48, 4, 4), "bottom": (24, 48, 4, 4), "right": (16, 52, 4, 12), "front": (20, 52, 4, 12), "left": (24, 52, 4, 12), "back": (28, 52, 4, 12)},
    }
    for part, faces in parts.items():
        for face, (x, y, w, h) in faces.items():
            px = flatten(crop(skin, x, y, w, h), (0, 0, 0, 255)) if part != "head" else crop(skin, x, y, w, h)
            px = flatten(px, (0, 0, 0, 255))
            open(os.path.join(out, "textures", f"steve_{part}_{face}.png"), "wb").write(png_encode(upscale(px, SCALE * 2)))
    print(f"{len(manifest)} full-cube blocks written ({skipped} non-cube / special blockstates skipped), Steve skin cropped")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
