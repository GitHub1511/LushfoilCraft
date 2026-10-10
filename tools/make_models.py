"""
Non-cube Minecraft blocks (stairs, slabs, plants, panes, fences, torches, doors...) for LushfoilCraft.

Reads each block's default model from the Minecraft client jar, flattens its cuboid elements into one thin "face slab" per
visible face (each with its own cropped texture), and writes:

  textures/m_<hash>.png        colour of one face (nearest-neighbour upscaled)
  textures/m_<hash>_m.png      opacity mask, only for faces with transparent pixels (plants, glass panes, torches...)
  Scripts/models.lua           name -> list of slabs { c = {x,y,z} centre in block pixels, s = {x,y,z} size, i = image, m = masked, yaw }
  Scripts/blocks.lua           (rewritten) full cubes as before, plus a plain cube fallback for blocks that have no cuboid model
                               (chests, beds, banners, signs, heads...: they are drawn by entity renderers in Minecraft)

Block pixel coordinates are Minecraft's: x east, y up, z south, 0..16.
Usage: python make_models.py <minecraft client jar> <LushfoilCraft folder>
"""
import json, os, sys, math, zipfile, hashlib, re

sys.path.insert(0, os.path.dirname(__file__))
import make_assets as MA

THICK = 0.4
GRASS = (121, 192, 90); FOLIAGE = (89, 174, 48); SPRUCE = (97, 153, 97); BIRCH = (128, 167, 85)


def main(jar, out):
    z = zipfile.ZipFile(jar)
    names = set(z.namelist())
    jl = lambda n: json.loads(z.read(n))
    tdir = os.path.join(out, "textures")
    os.makedirs(tdir, exist_ok=True)

    tex_cache = {}
    def texture(ref):
        ref = ref.replace("minecraft:", "")
        if ref in tex_cache: return tex_cache[ref]
        n = "assets/minecraft/textures/" + ref + ".png"
        px = MA.first_frame(MA.png_decode(z.read(n))[2]) if n in names else None
        tex_cache[ref] = px
        return px

    def chain(model):
        texs, els, ch, m = {}, None, [], model
        while m:
            p = "assets/minecraft/models/" + m.replace("minecraft:", "") + ".json"
            if p not in names: break
            d = jl(p); ch.append(m.replace("minecraft:", ""))
            if els is None and d.get("elements"): els = d["elements"]
            for k, v in d.get("textures", {}).items(): texs.setdefault(k, v)
            m = d.get("parent")
        def deref(v):
            n = 0
            while isinstance(v, str) and v.startswith("#") and n < 12: v = texs.get(v[1:]); n += 1
            return v
        return ch, els, {k: deref(v) for k, v in texs.items()}

    def tint_for(texref):
        t = texref.replace("minecraft:", "")
        if "leaves" in t and "azalea" not in t and "cherry" not in t:
            return SPRUCE if "spruce" in t else BIRCH if "birch" in t else FOLIAGE
        if any(k in t for k in ("grass", "fern", "sugar_cane", "vine", "lily_pad")): return GRASS if "vine" not in t and "lily" not in t else FOLIAGE
        return None

    images = {}
    def face_image(texref, uv, rot, tintindex):
        px = texture(texref)
        if px is None: return None
        size = len(px[0]); k = size / 16.0
        u1, v1, u2, v2 = uv
        x0, x1 = sorted((u1, u2)); y0, y1 = sorted((v1, v2))
        X0, X1, Y0, Y1 = int(round(x0 * k)), int(round(x1 * k)), int(round(y0 * k)), int(round(y1 * k))
        X1 = max(X1, X0 + 1); Y1 = max(Y1, Y0 + 1)
        crop = [row[X0:X1] for row in px[Y0:Y1]]
        if not crop or not crop[0]: return None
        if u1 > u2: crop = [list(reversed(r)) for r in crop]
        if v1 > v2: crop = crop[::-1]
        for _ in range((rot // 90) % 4):   # rotate clockwise
            crop = [list(r) for r in zip(*crop[::-1])]
        if tintindex is not None and tintindex >= 0:
            c = tint_for(texref)
            if c: crop = MA.tint(crop, c)
        key = hashlib.md5(json.dumps([texref, uv, rot, tintindex]).encode()).hexdigest()[:12]
        if key in images: return images[key]
        w, h = len(crop[0]), len(crop)
        k2 = max(1, int(math.ceil(64 / max(w, h)))) if max(w, h) < 16 else MA.SCALE
        masked = any(p[3] < 250 for r in crop for p in r)
        name = "m_" + key
        rgb = [[(p[0], p[1], p[2], 255) for p in r] for r in crop]
        open(os.path.join(tdir, name + ".png"), "wb").write(MA.png_encode(MA.upscale(rgb, k2)))
        if masked:
            mask = [[(p[3], p[3], p[3], 255) for p in r] for r in crop]
            open(os.path.join(tdir, name + "_m.png"), "wb").write(MA.png_encode(MA.upscale(mask, k2)))
        images[key] = (name, masked)
        return images[key]

    def slabs_for(element, texs):
        F, T = element["from"], element["to"]
        rot = element.get("rotation")
        yaw = 0.0
        origin = (8, 8, 8)
        if rot and rot.get("axis") == "y" and rot.get("angle"):
            yaw = -float(rot["angle"]); origin = tuple(rot.get("origin", (8, 8, 8)))
        res = []
        faces = element.get("faces", {})
        zero_z, zero_x = abs(F[2] - T[2]) < 0.01, abs(F[0] - T[0]) < 0.01
        skip = set()
        if zero_z and "north" in faces and "south" in faces and faces["north"].get("texture") == faces["south"].get("texture"): skip.add("south")
        if zero_x and "west" in faces and "east" in faces and faces["west"].get("texture") == faces["east"].get("texture"): skip.add("east")
        xm, ym, zm = (F[0] + T[0]) / 2, (F[1] + T[1]) / 2, (F[2] + T[2]) / 2
        dx, dy, dz = T[0] - F[0], T[1] - F[1], T[2] - F[2]
        for fname, f in faces.items():
            if fname in skip: continue
            texref = texs.get(f["texture"][1:]) if f["texture"].startswith("#") else f["texture"]
            if not texref: continue
            n = 0
            while isinstance(texref, str) and texref.startswith("#") and n < 12: texref = texs.get(texref[1:]); n += 1
            if not texref: continue
            # default uv
            x1, y1, z1, x2, y2, z2 = F[0], F[1], F[2], T[0], T[1], T[2]
            default = {"up": [x1, z1, x2, z2], "down": [x1, 16 - z2, x2, 16 - z1], "north": [16 - x2, 16 - y2, 16 - x1, 16 - y1],
                       "south": [x1, 16 - y2, x2, 16 - y1], "west": [z1, 16 - y2, z2, 16 - y1], "east": [16 - z2, 16 - y2, 16 - z1, 16 - y1]}[fname]
            img = face_image(texref, f.get("uv", default), f.get("rotation", 0), f.get("tintindex"))
            if not img: continue
            t = THICK
            if fname == "north": c, s = (xm, ym, F[2] + (0 if zero_z else t / 2)), (dx, dy, t)
            elif fname == "south": c, s = (xm, ym, T[2] - (0 if zero_z else t / 2)), (dx, dy, t)
            elif fname == "west": c, s = (F[0] + (0 if zero_x else t / 2), ym, zm), (t, dy, dz)
            elif fname == "east": c, s = (T[0] - (0 if zero_x else t / 2), ym, zm), (t, dy, dz)
            elif fname == "down": c, s = (xm, F[1] + t / 2, zm), (dx, t, dz)
            else: c, s = (xm, T[1] - t / 2, zm), (dx, t, dz)
            if yaw:
                th = math.radians(-yaw)   # MC angle (counter-clockwise from above)
                ox, oz = origin[0], origin[2]
                cx, cz = c[0] - ox, c[2] - oz
                c = (ox + cx * math.cos(th) + cz * math.sin(th), c[1], oz - cx * math.sin(th) + cz * math.cos(th))
                if rot.get("rescale"):
                    k = 1 / math.cos(th)
                    s = (s[0] * k if s[0] > s[2] else s[0], s[1], s[2] * k if s[2] >= s[0] else s[2])
            res.append({"c": [round(v, 3) for v in c], "s": [round(v, 3) for v in s], "i": img[0], "m": img[1], "yaw": yaw})
        return res

    def pick_variant(variants):
        def score(k):
            sc = 0
            for good in ("half=bottom", "type=bottom", "open=false", "facing=east", "face=floor", "axis=y", "part=head", "hinge=left", "half=lower", "attached=false",
                         "powered=false", "lit=false", "waterlogged=false", "shape=straight", "snowy=false", "age=0", "bites=0", "level=0", "layers=1", "occupied=false", "in_wall=false"):
                if good in k: sc += 1
            for bad in ("open=true", "powered=true", "lit=true"):
                if bad in k: sc -= 2
            return sc
        k = max(variants.keys(), key=score)
        v = variants[k]
        return v[0] if isinstance(v, list) else v

    def multipart_models(parts):
        out = []
        for p in parts:
            if "when" in p: continue
            a = p["apply"]; out.append(a[0] if isinstance(a, list) else a)
        if not out:   # fences / panes / walls: the unconnected centre post is the part that applies when nothing is connected
            for p in parts:
                a = p["apply"]; a = a[0] if isinstance(a, list) else a
                if "post" in a["model"] or "noside" in a["model"] or a["model"].endswith("_post") or "_inventory" in a["model"]:
                    out.append(a); break
        return out

    cubes_manifest = []
    old = {}
    # existing full-cube manifest from make_assets (names with their face kinds)
    bpath = os.path.join(out, "Scripts", "blocks.lua")
    full = []
    for m in re.finditer(r'\{ "([^"]+)", "([^"]+)" \}', open(bpath).read()): full.append((m.group(1), m.group(2)))
    fullnames = {n for n, _ in full}

    models, fallbacks, skipped = {}, [], []
    for n in sorted(x for x in names if x.startswith("assets/minecraft/blockstates/") and x.endswith(".json")):
        name = n.rsplit("/", 1)[1][:-5]
        if name in fullnames or name in ("water", "lava", "air", "cave_air", "void_air", "barrier", "light", "structure_void", "moving_piston", "piston_head", "bubble_column"):
            continue
        d = jl(n)
        if "variants" in d: applies = [pick_variant(d["variants"])]
        else: applies = multipart_models(d.get("multipart", []))
        slabs, particle = [], None
        for a in applies:
            ch, els, texs = chain(a["model"])
            particle = particle or texs.get("particle")
            if els:
                # honour block-level rotation only in 90 degree steps about y by leaving geometry as modelled (default variants are unrotated)
                for e in els: slabs += slabs_for(e, texs)
        if slabs:
            models[name] = slabs
        elif particle:
            fallbacks.append((name, particle))
        else:
            skipped.append(name)

    # fallback cubes: textured with the model's particle texture
    for name, particle in fallbacks:
        px = texture(particle)
        if px is None: skipped.append(name); continue
        if any(p[3] < 250 for r in px for p in r): px = MA.flatten(px, (190, 215, 225, 255))
        open(os.path.join(tdir, f"{name}_all.png"), "wb").write(MA.png_encode(MA.upscale(px, MA.SCALE)))
        full.append((name, "all"))

    with open(bpath, "w") as f:
        f.write("-- generated by tools/make_assets.py + make_models.py: full-cube blocks (and plain-cube fallbacks) and which texture faces they have\nreturn {\n")
        for name, kinds in sorted(full): f.write(f'  {{ "{name}", "{kinds}" }},\n')
        f.write("}\n")
    with open(os.path.join(out, "Scripts", "models.lua"), "w") as f:
        f.write("-- generated by tools/make_models.py: non-cube blocks as face slabs. c/s in block pixels (x east, y up, z south), yaw = degrees about the vertical axis\nreturn {\n")
        for name in sorted(models):
            f.write('  ["%s"] = {\n' % name)
            for s in models[name]:
                f.write('    { c = {%s}, s = {%s}, i = "%s", m = %s, yaw = %s },\n' % (",".join(map(str, s["c"])), ",".join(map(str, s["s"])), s["i"], "true" if s["m"] else "false", s["yaw"]))
            f.write("  },\n")
        f.write("}\n")
    nm = sum(1 for n in models for s in models[n] if s["m"])
    print(f"{len(models)} element models ({sum(len(v) for v in models.values())} face slabs, {nm} masked), {len(fallbacks)} plain-cube fallbacks, {len(skipped)} skipped, {len(images)} face images")
    if skipped: print("skipped:", " ".join(skipped[:40]))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
