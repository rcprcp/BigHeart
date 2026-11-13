#!/usr/bin/env python3
"""Generate the large bitmap fonts used by Big Heart.

The watch face needs a normal-looking font at several fixed sizes. The
Connect IQ resource compiler turns the BMFont text+PNG pair into a 1-bit
font at build time, which keeps memory use reasonable.

Run from the project root:
    python3 tools/make_fonts.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONT_PATH = "/usr/share/fonts/truetype/liberation/LiberationSansNarrow-Bold.ttf"
OUT_DIR = Path(__file__).resolve().parent.parent / "resources" / "fonts"
CHARS = "0123456789-"
PAD = 2

# (file stem, ink height in pixels)
FONTS = [
    ("hr_large", 195),
    ("hr_small", 156),
    ("spo2", 104),
]

PROBE_SIZE = 1000


def ink_boxes(font):
    boxes = {}
    for ch in CHARS:
        boxes[ch] = font.getbbox(ch, anchor="ls")
    return boxes


def generate(stem, target_height):
    probe = ImageFont.truetype(FONT_PATH, PROBE_SIZE)
    boxes = ink_boxes(probe)
    max_ink_height = max(b[3] - b[1] for b in boxes.values())
    size = round(PROBE_SIZE * target_height / max_ink_height)

    font = ImageFont.truetype(FONT_PATH, size)
    boxes = ink_boxes(font)
    cell_top = min(b[1] for b in boxes.values())
    cell_bottom = max(b[3] for b in boxes.values())
    cell_height = cell_bottom - cell_top
    ascent = -cell_top

    glyphs = {}
    cursor = PAD
    for ch in CHARS:
        x0, y0, x1, y1 = boxes[ch]
        width, height = x1 - x0, y1 - y0
        advance = round(font.getlength(ch))
        glyphs[ch] = {
            "width": width,
            "height": height,
            "xoffset": x0,
            "yoffset": y0 - cell_top,
            "xadvance": advance,
            "atlas_x": cursor,
            "atlas_y": PAD + (y0 - cell_top),
        }
        cursor += width + 2

    atlas_w = cursor + PAD
    atlas_h = cell_height + 2 * PAD
    atlas = Image.new("L", (atlas_w, atlas_h), 0)
    draw = ImageDraw.Draw(atlas)

    for ch in CHARS:
        g = glyphs[ch]
        x0, y0, x1, y1 = boxes[ch]
        glyph = Image.new("L", (g["width"], g["height"]), 0)
        glyph_draw = ImageDraw.Draw(glyph)
        # Draw with the baseline at -y0 so the glyph ink starts at (0, 0).
        glyph_draw.text((-x0, -y0), ch, font=font, fill=255, anchor="ls")
        # Crisp 1-bit edges; the font is already bold, so threshold high
        # enough to keep counters open at large sizes.
        glyph = glyph.point(lambda p: 255 if p >= 128 else 0)
        atlas.paste(glyph, (g["atlas_x"], g["atlas_y"]))

    png_name = f"{stem}.png"
    atlas.save(OUT_DIR / png_name, optimize=True)

    lines = [
        f'info face="BigHeart {stem}" size={-size} bold=0 italic=0 charset="" unicode=1 '
        f"stretchH=100 smooth=0 aa=0 padding=0,0,0,0 spacing=1,1 outline=0",
        f"common lineHeight={cell_height} base={ascent} scaleW={atlas_w} scaleH={atlas_h} "
        f'pages=1 packed=0 alphaChnl=1 redChnl=0 greenChnl=0 blueChnl=0',
        "page id=0 file=" + '"' + png_name + '"',
        f"chars count={len(CHARS)}",
    ]
    for ch in CHARS:
        g = glyphs[ch]
        lines.append(
            f"char id={ord(ch)} x={g['atlas_x']} y={g['atlas_y']} "
            f"width={g['width']} height={g['height']} "
            f"xoffset={g['xoffset']} yoffset={g['yoffset']} "
            f"xadvance={g['xadvance']} page=0 chnl=15"
        )
    lines.append("kernings count=0")

    (OUT_DIR / f"{stem}.fnt").write_text("\n".join(lines) + "\n")
    print(f"{stem}: size={size} atlas={atlas_w}x{atlas_h} cell={cell_height} base={ascent}")


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for stem, height in FONTS:
        generate(stem, height)


if __name__ == "__main__":
    main()
