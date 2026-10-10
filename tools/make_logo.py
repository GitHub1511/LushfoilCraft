"""Draws the LushfoilCraft logo into textures/lc_logo.png (1920x992, the same shape as the game's own title logo, so it drops into the game's layout).
"LUSHFOIL" in grass-block texture, "CRAFT" in stone, extruded with depth and a black outline like Minecraft's logo, flanked by big isometric
blocks, over a dark banner with the credit line. Needs the textures made by make_assets.py / make_icons.py / make_items.py.
Usage: python -I tools/make_logo.py ."""
import os, random, sys
sys.path.insert(0, os.path.dirname(__file__))
from make_assets import png_decode, png_encode

root = sys.argv[1] if len(sys.argv) > 1 else "."
GLYPHS = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"], "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"], "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"], "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"], "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"], "J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"], "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"], "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"], "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"], "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"], "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"], "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"], "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"], "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    " ": ["00000"] * 7,
}
W, H = 1920, 992
img = [[(0, 0, 0, 0)] * W for _ in range(H)]

def load(name):
    p = os.path.join(root, "textures", name + ".png")
    return png_decode(open(p, "rb").read())[2] if os.path.exists(p) else None

def tile16(px): return [[px[y * (len(px) // 16) + 3][x * (len(px[0]) // 16) + 3] for x in range(16)] for y in range(16)]
stone = tile16(load("stone_all"))
grass_top = tile16(load("grass_block_top") or load("grass_block_all") or load("stone_all"))
dirt = tile16(load("dirt_all"))

def put(x, y, c):
    if 0 <= x < W and 0 <= y < H and c[3] >= img[y][x][3]: img[y][x] = c

def block_cells(s):
    """cells (col, row, glyph index) of a word"""
    out, x = [], 0
    for gi, ch in enumerate(s):
        for gy, row in enumerate(GLYPHS.get(ch, GLYPHS[" "])):
            for gx, bit in enumerate(row):
                if bit == "1": out.append((x + gx, gy))
        x += 6
    return out, x - 1

def word(s, x0, y0, cell, tex, depth, tex2=None):
    cells, cols = block_cells(s)
    cs = set(cells)
    # black outline + extrusion first (back to front), then the lit faces on top
    for d in range(depth, -1, -1):
        for (cx, cy) in cells:
            px, py = x0 + cx * cell + d, y0 + cy * cell + d
            for yy in range(cell):
                for xx in range(cell):
                    if d == depth + 0:
                        put(px + xx + 4, py + yy + 6, (0, 0, 0, 120))          # soft drop shadow
                    shade = 0.45 - 0.15 * (d / max(1, depth))
                    t = tex[(yy * 16 // cell + cy * 5) % 16][(xx * 16 // cell + cx * 3) % 16]
                    put(px + xx, py + yy, (int(t[0] * shade), int(t[1] * shade), int(t[2] * shade), 255))
    o = 4
    for (cx, cy) in cells:                                                        # black outline around the face layer
        px, py = x0 + cx * cell, y0 + cy * cell
        for yy in range(-o, cell + o):
            for xx in range(-o, cell + o):
                if not (0 <= yy < cell and 0 <= xx < cell) and (cx, cy) in cs:
                    if img[py + yy][px + xx][3] == 0 or True:
                        put(px + xx, py + yy, (8, 8, 8, 255))
    for (cx, cy) in cells:
        px, py = x0 + cx * cell, y0 + cy * cell
        for yy in range(cell):
            for xx in range(cell):
                t = tex[(yy * 16 // cell + cy * 5) % 16][(xx * 16 // cell + cx * 3) % 16]
                e = max(3, cell // 9)
                k = 1.22 if (yy < e or xx < e) else (0.66 if (yy >= cell - e or xx >= cell - e) else 1.0)
                if tex2 is not None and yy > cell * 0.55 and cy > 0 and (cy, cx) not in {}:
                    pass
                put(px + xx, py + yy, (min(255, int(t[0] * k)), min(255, int(t[1] * k)), min(255, int(t[2] * k)), 255))
    return cols

def paste_icon(name, cx, cy, size):
    ic = load(name)
    if not ic: return
    n = len(ic)
    for y in range(size):
        for x in range(size):
            p = ic[y * n // size][x * n // size]
            if p[3] > 20: put(cx - size // 2 + x, cy - size // 2 + y, p)
    # soft shadow under the block
    for y in range(size // 12):
        for x in range(size // 2):
            for sx in (-1, 1):
                put(cx + sx * x, cy + size // 2 + y, (0, 0, 0, max(0, 110 - x * 220 // (size // 2))))

# ---- banner behind the credit lines
BX0, BX1 = 120, 1800          # wide enough for the longest caption line (about 1510 px) with margin
for y in range(745, 915):
    for x in range(BX0, BX1):
        edge = min(x - BX0, BX1 - x, y - 745, 915 - y)
        put(x, y, (6, 8, 7, 175 if edge > 3 else 220))

# ---- the words
cell1 = 34
cols1 = len("LUSHFOIL") * 6 - 1
x1 = (W - cols1 * cell1) // 2
word("LUSHFOIL", x1, 48, cell1, grass_top, 12)
cell2 = 34
cols2 = len("CRAFT") * 6 - 1
x2 = (W - cols2 * cell2) // 2
word("CRAFT", x2, 48 + 7 * cell1 + 38, cell2, stone, 12)

# ---- blocks and tools flanking CRAFT
cy = 48 + 7 * cell1 + 38 + 7 * cell2 // 2
paste_icon("icon_grass_block", x2 - 250, cy, 300)
paste_icon("icon_diamond_ore", x2 + cols2 * cell2 + 250, cy, 300)
paste_icon("icon_item_iron_pickaxe", x2 - 70, cy + 190, 150)
paste_icon("icon_item_iron_sword", x2 + cols2 * cell2 + 70, cy + 190, 150)

# ---- credit lines (small pixel font, white with shadow)
def line(s, cx, y, cell, col=(240, 240, 240, 255)):
    cells, cols = block_cells(s)
    x0 = cx - cols * cell // 2
    for (gx, gy) in cells:
        for yy in range(cell):
            for xx in range(cell):
                put(x0 + gx * cell + xx + 2, y + gy * cell + yy + 2, (0, 0, 0, 200))
    for (gx, gy) in cells:
        for yy in range(cell):
            for xx in range(cell):
                put(x0 + gx * cell + xx, y + gy * cell + yy, col)
line("A LUSHFOIL PHOTOGRAPHY SIM X MINECRAFT MOD", W // 2, 770, 6, (200, 235, 200, 255))
line("BY SHIVIN SINGH", W // 2, 830, 9)
open(os.path.join(root, "textures", "lc_logo.png"), "wb").write(png_encode(img))
print("logo written", W, H)
