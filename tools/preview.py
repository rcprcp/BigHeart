#!/usr/bin/env python3
"""Render a desktop preview of the Big Heart face layout.

Uses the actual generated BMFont atlases, so glyph positions and 1-bit shapes
match what the watch will draw.

Development aid only; run from the project root:
    python3 tools/preview.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SIZE = 416
ROOT = Path(__file__).resolve().parent.parent
FONT_DIR = ROOT / "resources" / "fonts"


def load_bmfont(stem):
    lines = (FONT_DIR / f"{stem}.fnt").read_text().splitlines()
    glyphs = {}
    line_height = 0
    for line in lines:
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "common":
            fields = dict(p.split("=", 1) for p in parts[1:] if "=" in p)
            line_height = int(fields["lineHeight"])
        elif parts[0] == "char":
            fields = dict(p.split("=", 1) for p in parts[1:] if "=" in p)
            ch = chr(int(fields["id"]))
            glyphs[ch] = {
                "x": int(fields["x"]),
                "y": int(fields["y"]),
                "w": int(fields["width"]),
                "h": int(fields["height"]),
                "xo": int(fields["xoffset"]),
                "yo": int(fields["yoffset"]),
                "xa": int(fields["xadvance"]),
            }
    atlas = Image.open(FONT_DIR / f"{stem}.png").convert("L")
    return {"atlas": atlas, "glyphs": glyphs, "line_height": line_height}


def draw_bmtext(img, font, text, center_x, center_y, color):
    total = sum(font["glyphs"][c]["xa"] for c in text)
    pen_x = round(center_x - total / 2)
    top = round(center_y - font["line_height"] / 2)
    atlas = font["atlas"]
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    for ch in text:
        g = font["glyphs"][ch]
        if g["w"] > 0 and g["h"] > 0:
            glyph = atlas.crop((g["x"], g["y"], g["x"] + g["w"], g["y"] + g["h"]))
            solid = Image.new("RGBA", glyph.size, color)
            layer.paste(solid, (pen_x + g["xo"], top + g["yo"]), glyph)
        pen_x += g["xa"]
    img.alpha_composite(layer)


def render(hr="72", spo2="98", ambient=False, path="preview.png"):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
    clock_font = ImageFont.truetype(
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18
    )
    d = ImageDraw.Draw(img)

    if ambient:
        d.text((SIZE / 2, 22), "10:42", font=clock_font, fill=(96, 96, 96, 255), anchor="mm")
        draw_bmtext(img, load_bmfont("hr_ambient"), hr, SIZE / 2, 155, (160, 80, 80, 255))
        draw_bmtext(img, load_bmfont("spo2_ambient"), spo2, SIZE / 2, 328, (62, 124, 156, 255))
    else:
        d.text((SIZE / 2, 22), "10:42", font=clock_font, fill=(154, 154, 154, 255), anchor="mm")
        hr_font = load_bmfont("hr_large" if len(hr) <= 2 and not hr.startswith("-") else "hr_small")
        draw_bmtext(img, hr_font, hr, SIZE / 2, 155, (255, 77, 77, 255))
        draw_bmtext(img, load_bmfont("spo2"), spo2, SIZE / 2, 328, (79, 182, 255, 255))

    # Clip to the watch's round display.
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, SIZE - 1, SIZE - 1], fill=255)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
    out.paste(img, (0, 0), mask)
    out.save(ROOT / path)
    print(path)


if __name__ == "__main__":
    render("72", "98", False, "preview_full.png")
    render("168", "97", False, "preview_full_3digit.png")
    render("72", "100", False, "preview_spo2_100.png")
    render("72", "98", True, "preview_ambient.png")
