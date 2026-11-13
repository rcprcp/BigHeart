#!/usr/bin/env python3
"""Render a desktop preview of the Big Heart face layout.

The full-power preview uses the actual generated BMFont atlases, so glyph
positions and 1-bit shapes match what the watch will draw. The ambient preview
mirrors the vector seven-segment renderer in source/SegmentFont.mc.

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
    rgba = Image.new("RGBA", img.size, (0, 0, 0, 0))
    for ch in text:
        g = font["glyphs"][ch]
        if g["w"] > 0 and g["h"] > 0:
            glyph = atlas.crop((g["x"], g["y"], g["x"] + g["w"], g["y"] + g["h"]))
            solid = Image.new("RGBA", glyph.size, color)
            rgba.paste(solid, (pen_x + g["xo"], top + g["yo"]), glyph)
        pen_x += g["xa"]
    img.alpha_composite(rgba)


# --- seven-segment ambient renderer (mirrors SegmentFont.mc) ---
MASKS = {
    "0": 0x3F, "1": 0x06, "2": 0x5B, "3": 0x4F, "4": 0x66,
    "5": 0x6D, "6": 0x7D, "7": 0x07, "8": 0x7F, "9": 0x6F, "-": 0x40,
}


class SegmentDraw:
    def __init__(self, draw):
        self.draw = draw

    def rounded_rectangle(self, coords, radius, fill):
        self.draw.rounded_rectangle(coords, radius=radius, fill=fill)


def width_at(y):
    r = SIZE / 2 - 6
    dy = abs(y - SIZE / 2)
    if dy >= r:
        return 0
    return 2 * (r * r - dy * dy) ** 0.5


def block_width(chars, h):
    w = int(h * 0.54)
    gap = int(h * 0.09)
    return chars * w + (chars - 1) * gap


def fit_height(chars, row, max_h, max_w=SIZE - 24):
    h = max_h
    while h > 40:
        top, bottom = row - h // 2, row + h // 2
        if block_width(chars, h) <= min(max_w, width_at(top), width_at(bottom)):
            return h
        h -= 2
    return 40


def draw_segments(img, text, row, max_h, color, thin=True, ox=0, oy=0):
    d = SegmentDraw(ImageDraw.Draw(img))
    h = fit_height(len(text), row, max_h)
    w = int(h * 0.54)
    gap = int(h * 0.09)
    total = len(text) * w + (len(text) - 1) * gap
    x0 = SIZE / 2 - total / 2 + ox
    y0 = row - h / 2 + oy
    t = max(3, int(h * (0.045 if thin else 0.145)))
    sg = max(1, int(t * 0.3))
    for i, ch in enumerate(text):
        glyph(d, x0 + i * (w + gap), y0, w, h, t, sg, MASKS.get(ch, 0), color)


def glyph(d, x, y, w, h, t, gap, mask, color):
    r = t / 2
    hx = x + r + gap
    hw = w - t - 2 * gap
    vt = y + t + gap
    vh = h / 2 - t - r - 2 * gap
    vb = y + h / 2 + r + gap
    left = x + r
    right = x + w - r

    def box(x0, y0, x1, y1):
        d.rounded_rectangle([x0, y0, x1, y1], radius=max(1, r * 0.6), fill=color)

    if mask & 1:
        box(hx, y, hx + hw, y + t)
    if mask & 2:
        box(right - r, vt, right + r, vt + vh)
    if mask & 4:
        box(right - r, vb, right + r, vb + vh)
    if mask & 8:
        box(hx, y + h - t, hx + hw, y + h)
    if mask & 16:
        box(left - r, vb, left + r, vb + vh)
    if mask & 32:
        box(left - r, vt, left + r, vt + vh)
    if mask & 64:
        box(hx, y + h / 2 - r, hx + hw, y + h / 2 + r)


def render(hr="72", spo2="98", ambient=False, path="preview.png"):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
    clock_font = ImageFont.truetype(
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18
    )
    d = ImageDraw.Draw(img)

    if ambient:
        d.text((SIZE / 2, 22), "10:42", font=clock_font, fill=(96, 96, 96, 255), anchor="mm")
        hr_h = 195 if len(hr) <= 2 else 156
        draw_segments(img, hr, 155, hr_h, (160, 80, 80, 255))
        draw_segments(img, spo2, 328, 104, (62, 124, 156, 255))
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
