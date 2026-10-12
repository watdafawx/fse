"""Draws fse-std's settings icon (a gear) for a window's title bar: graphics/settings.png (white, for dark themes)
and settings-black.png (light themes), 64 x 64, drawn 4x bigger and scaled down for smooth edges."""
import math
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parents[1] / "mods" / "fse-std" / "graphics"
S = 256  # (drawn at 4x)


def gear(color):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c, teeth, r_out, r_in, r_hole = S / 2, 8, S * 0.40, S * 0.30, S * 0.13
    pts = []
    for i in range(teeth * 4):
        a = 2 * math.pi * i / (teeth * 4) - math.pi / 2
        r = r_out if i % 4 in (0, 1) else r_in
        pts.append((c + r * math.cos(a), c + r * math.sin(a)))
    d.polygon(pts, fill=color)
    d.ellipse([c - r_in, c - r_in, c + r_in, c + r_in], fill=color)
    d.ellipse([c - r_hole, c - r_hole, c + r_hole, c + r_hole], fill=(0, 0, 0, 0))
    return img.resize((64, 64), Image.LANCZOS)


gear((255, 255, 255, 255)).save(OUT / "settings.png")
gear((0, 0, 0, 255)).save(OUT / "settings-black.png")
print("wrote", OUT / "settings.png", OUT / "settings-black.png")
