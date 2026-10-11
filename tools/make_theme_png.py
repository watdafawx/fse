"""Draws mods/fse-std/graphics/theme.png: the white 9-slice tiles fse-std's themes tint (python tools/make_theme_png.py; needs pillow).
Grey levels shade a tile (a border, a bevel); the colour comes from the style's tint, so white means "the colour".
Layout (themes.lua reads the same numbers): one row per shape, one column per kind, every tile at
(col * STEP, row * STEP), CORNER[shape] * 2 + 1 pixels square (the game's composition tiles)."""
from pathlib import Path
from PIL import Image, ImageDraw

STEP = 32
SHAPES = [("square", 8, 0), ("soft", 8, 4), ("round", 12, 10), ("small", 4, 2)]  # name, corner size, radius
KINDS = ["panel", "button", "inset", "flat", "outline"]
SS = 4  # supersampling for smooth corners


def tile(kind, corner, radius):
    n = corner * 2 + 1
    big = n * SS
    # (alpha: the rounded shape; value: the shading)
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, big - 1, big - 1), radius=radius * SS, fill=255)
    mask = mask.resize((n, n), Image.LANCZOS)
    inner = Image.new("L", (big, big), 0)
    ImageDraw.Draw(inner).rounded_rectangle((SS, SS, big - 1 - SS, big - 1 - SS), radius=max(0, radius - 1) * SS,
                                            fill=255)
    inner = inner.resize((n, n), Image.LANCZOS)
    border = {"panel": 150, "button": 110, "inset": 120, "flat": 255, "outline": 90}[kind]
    value = Image.new("L", (n, n), 255)
    px = value.load()
    ip = inner.load()
    for y in range(n):
        for x in range(n):
            t = ip[x, y] / 255  # 1 inside, 0 on the border ring
            v = 255
            if kind == "button" and y >= n - 3:
                v = 205  # the bevel along the bottom
            if kind == "inset" and y <= 2:
                v = 170 if y <= 1 else 215  # the shadow under the top edge
            px[x, y] = round(v * t + border * (1 - t))
    rgba = Image.merge("RGBA", (value, value, value, mask))
    return rgba


def main():
    out = Image.new("RGBA", (STEP * len(KINDS), STEP * len(SHAPES)), (0, 0, 0, 0))
    for r, (_, corner, radius) in enumerate(SHAPES):
        for c, kind in enumerate(KINDS):
            out.paste(tile(kind, corner, radius), (c * STEP, r * STEP))
    path = Path(__file__).resolve().parents[1] / "mods" / "fse-std" / "graphics" / "theme.png"
    out.save(path)
    print(path, out.size)


def shortcut_icon():
    """graphics/theme-shortcut.png: the theme window's shortcut, a white palette (64 px, drawn at 4x)"""
    n, k = 64, 4
    big = Image.new("L", (n * k, n * k), 0)
    d = ImageDraw.Draw(big)
    d.ellipse((4 * k, 8 * k, 60 * k, 56 * k), fill=255)
    d.ellipse((34 * k, 34 * k, 50 * k, 50 * k), fill=0)  # (the thumb hole's notch)
    for x, y in ((18, 20), (31, 15), (44, 20), (16, 34)):
        d.ellipse(((x - 5) * k, (y - 5) * k, (x + 5) * k, (y + 5) * k), fill=0)
    alpha = big.resize((n, n), Image.LANCZOS)
    icon = Image.merge("RGBA", (Image.new("L", (n, n), 255),) * 3 + (alpha,))
    path = Path(__file__).resolve().parents[1] / "mods" / "fse-std" / "graphics" / "theme-shortcut.png"
    icon.save(path)
    print(path)


if __name__ == "__main__":
    main()
    shortcut_icon()
