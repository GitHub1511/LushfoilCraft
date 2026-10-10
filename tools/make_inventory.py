"""Minecraft inventory screens: the survival inventory panel, the creative item grid / search / inventory panels, tabs, scroller and a flat
front view of Steve, nearest-upscaled for crisp drawing. Usage: python -I tools/make_inventory.py <client jar> ."""
import os, sys, zipfile
sys.path.insert(0, os.path.dirname(__file__))
from make_assets import png_decode, png_encode, upscale, crop, over
jar, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(jar)
def get(name): return png_decode(z.read("assets/minecraft/textures/" + name))[2]
def save(name, px, k): open(os.path.join(out, "textures", name + ".png"), "wb").write(png_encode(upscale(px, k)))
inv = get("gui/container/inventory.png")
save("inv_survival", crop(inv, 0, 0, 176, 166), 6)
for src, name in (("tab_items", "inv_items"), ("tab_item_search", "inv_search"), ("tab_inventory", "inv_creative_inv")):
    save(name, crop(get(f"gui/container/creative_inventory/{src}.png"), 0, 0, 195, 136), 6)
for n in ("scroller", "scroller_disabled"): save("inv_" + n, get(f"gui/sprites/container/creative_inventory/{n}.png"), 6)
for n in ("tab_top_selected_1", "tab_top_unselected_1", "tab_bottom_selected_7", "tab_bottom_unselected_7"): save("inv_" + n, get(f"gui/sprites/container/creative_inventory/{n}.png"), 6)
# Steve from the front, 16 x 32 pixels (second layers over the first)
skin = get("entity/player/wide/steve.png")
canvas = [[(0, 0, 0, 0)] * 16 for _ in range(32)]
def blit(sx, sy, w, h, dx, dy):
    for y in range(h):
        for x in range(w):
            p = skin[sy + y][sx + x]
            if p[3] > 0: canvas[dy + y][dx + x] = p if p[3] == 255 else tuple(int(a * p[3] / 255 + b * (255 - p[3]) / 255) for a, b in zip(p[:3], canvas[dy + y][dx + x][:3])) + (255,)
for (a, b, w, h, dx, dy) in [(8, 8, 8, 8, 4, 0), (44, 20, 4, 12, 0, 8), (36, 52, 4, 12, 12, 8), (20, 20, 8, 12, 4, 8), (4, 20, 4, 12, 4, 20), (20, 52, 4, 12, 8, 20),
                             (40, 8, 8, 8, 4, 0), (44, 36, 4, 12, 0, 8), (52, 52, 4, 12, 12, 8), (20, 36, 8, 12, 4, 8), (4, 36, 4, 12, 4, 20), (4, 52, 4, 12, 8, 20)]:
    blit(a, b, w, h, dx, dy)
save("gui_steve", canvas, 8)
print("inventory assets done")
