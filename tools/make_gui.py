"""Extracts the Minecraft HUD sprites (hotbar, selection frame, crosshair) from the client jar, nearest-upscaled 8x."""
import sys, zipfile, os
sys.path.insert(0, os.path.dirname(__file__))
from make_assets import png_decode, png_encode, upscale
jar, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(jar)
for n in ["hotbar", "hotbar_selection", "crosshair", "heart/container", "heart/full", "heart/half", "food_empty", "food_full", "food_half", "experience_bar_background", "air", "air_bursting"]:
    w, h, px = png_decode(z.read(f"assets/minecraft/textures/gui/sprites/hud/{n}.png"))
    open(os.path.join(out, "textures", f"gui_{n.replace(chr(47), chr(95))}.png"), "wb").write(png_encode(upscale(px, 8)))
    print(n, w, "x", h)

# a fully transparent icon for empty hotbar slots, and a black texture for the red hurt flash
open(os.path.join(out, "textures", "icon_empty.png"), "wb").write(png_encode([[(0, 0, 0, 0)] * 8 for _ in range(8)]))
open(os.path.join(out, "textures", "white.png"), "wb").write(png_encode([[(255, 255, 255, 255)] * 8 for _ in range(8)]))
