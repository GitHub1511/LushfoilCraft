"""Isometric inventory icons (Minecraft GUI block style: top lit, left side medium, right side dark) for every cube block.
Usage: python -I tools/make_icons.py .   (run after make_assets.py / make_models.py)"""
import math, os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from make_assets import png_decode, png_encode

root = sys.argv[1]
S = 128
blocks = re.findall(r'\{ "([^"]+)", "([^"]+)" \}', open(os.path.join(root, "Scripts", "blocks.lua")).read())
cache = {}
def tex(name):
    if name not in cache:
        p = os.path.join(root, "textures", name + ".png")
        cache[name] = png_decode(open(p, "rb").read())[2] if os.path.exists(p) else None
    return cache[name]

# view = Rx(30deg) * Ry(225deg); ray in view space goes along +z, so rotate origin and direction back into cube space
ax, ay = math.radians(30), math.radians(225)
cx, sx_, cy, sy_ = math.cos(ax), -math.sin(ax), math.cos(ay), math.sin(ay)      # looking down on the cube: top face visible
def to_cube(v):                    # inverse of (Rx . Ry): Ry^-1 . Rx^-1
    x, y, z = v
    y, z = y * cx + z * sx_, -y * sx_ + z * cx           # Rx(-30)
    x, z = x * cy - z * sy_, x * sy_ + z * cy            # Ry(-225)
    return x, y, z
H = 1 / 1.573 / 2 * 1.0           # half edge so the hexagon fills about +-1
H = 0.5 / 1.573 * 2 * 0.5 * 2 / 2 # (kept simple: 0.318 -> fills the icon)
H = 0.9 / 1.573                   # half-edge in view units: the cube fills ~90% of the icon, centred in the slot
dirc = to_cube((0, 0, 1))
shade = {"top": 1.0, "left": 0.78, "right": 0.55}

def render(top, side):
    out = [[(0, 0, 0, 0)] * S for _ in range(S)]
    for py in range(S):
        v = 1 - (py + 0.5) / S * 2
        for pxl in range(S):
            u = (pxl + 0.5) / S * 2 - 1
            o = to_cube((u, v, -5))
            best = None
            for ax_i in range(3):
                d = dirc[ax_i]
                if abs(d) < 1e-9: continue
                for sgn in (-1, 1):
                    t = (sgn * H - o[ax_i]) / d
                    p = [o[i] + dirc[i] * t for i in range(3)]
                    if all(abs(p[i]) <= H + 1e-6 for i in range(3) if i != ax_i):
                        n = [0, 0, 0]; n[ax_i] = sgn
                        if n[0] * dirc[0] + n[1] * dirc[1] + n[2] * dirc[2] < 0 and (best is None or t < best[0]):
                            best = (t, ax_i, sgn, p)
            if best is None: continue
            _, ai, sg, p = best
            if ai == 1:
                if sg < 0: continue
                img, sh = top, shade["top"]
                a, b = (p[0] + H) / (2 * H), (p[2] + H) / (2 * H)
            else:
                img = side
                # left/right in the view: sign of the face normal's x after the view rotation
                nx = (sg if ai == 0 else 0) * cy + (sg if ai == 2 else 0) * sy_
                sh = shade["left"] if nx < 0 else shade["right"]
                a = (p[2] if ai == 0 else p[0]) 
                a = (a + H) / (2 * H); b = (H - p[1]) / (2 * H)
            ty, tx = min(int(b * 128), 127), min(int(a * 128), 127)
            r, g, bl, al = img[ty][tx]
            out[py][pxl] = (int(r * sh), int(g * sh), int(bl * sh), 255)
    return out

done = 0
for name, kinds in ([] if 'models' in sys.argv[2:] else blocks):
    if kinds == "all": t = s = tex(name + "_all")
    else: t, s = tex(name + "_top"), tex(name + "_side")
    if t is None or s is None: print("skip", name); continue
    open(os.path.join(root, "textures", f"icon_{name}.png"), "wb").write(png_encode(render(t, s)))
    done += 1
print("icons:", done)

# non-cube models: flat sprite of the largest face slab (what Minecraft shows for flowers, saplings, torches, panes...), with its opacity mask
models = open(os.path.join(root, "Scripts", "models.lua")).read()
n = 0
for m in re.finditer(r'\["([^"]+)"\] = \{\n(.*?)\n  \},?', models, re.S):
    name, body = m.group(1), m.group(2)
    best = None
    for sl in re.finditer(r'\{ c = \{[^}]*\}, s = \{([-\d.]+),([-\d.]+),([-\d.]+)\}, i = "([^"]+)", m = (true|false)', body):
        dims = sorted([abs(float(sl.group(k))) for k in (1, 2, 3)], reverse=True)
        area = dims[0] * dims[1]
        if best is None or area > best[0]: best = (area, sl.group(4), sl.group(5) == "true")
    if not best: continue
    img = tex(best[1])
    if img is None: continue
    mask = tex(best[1] + "_m") if best[2] else None
    h, w = len(img), len(img[0])
    out = [[(img[y][x][0], img[y][x][1], img[y][x][2], mask[y][x][0] if mask else 255) for x in range(w)] for y in range(h)]
    open(os.path.join(root, "textures", f"icon_{name}.png"), "wb").write(png_encode(out))
    n += 1
print("model icons:", n)
