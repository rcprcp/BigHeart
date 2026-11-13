import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

//! Draws digits as rounded seven-segment glyphs for AMOLED ambient mode.
//!
//! The normal face uses large bitmap fonts. A filled font at that size would
//! light too many pixels in always-on mode, so ambient mode redraws the same
//! values with these thin vector strokes instead. They can be sized to fit the
//! round display and shifted each minute to avoid burn-in.
class SegmentFont {

    //! Width of a complete string of glyphs at the given glyph height.
    public static function blockWidth(chars as Number, glyphHeight as Number) as Number {
        if (chars <= 0) {
            return 0;
        }
        var glyphWidth = (glyphHeight * 0.54).toNumber();
        var gap = (glyphHeight * 0.09).toNumber();
        return chars * glyphWidth + (chars - 1) * gap;
    }

    //! Largest glyph height for a value that still fits inside the round display.
    public static function fitHeight(chars as Number, rowCenterY as Number, maxHeight as Number,
                                     maxWidth as Number, screenCx as Number, screenCy as Number,
                                     radius as Number) as Number {
        var height = maxHeight;
        while (height > 40) {
            var top = rowCenterY - height / 2;
            var bottom = rowCenterY + height / 2;
            var available = maxWidth;
            var topWidth = widthAt(top, screenCx, screenCy, radius);
            var bottomWidth = widthAt(bottom, screenCx, screenCy, radius);
            if (topWidth < available) {
                available = topWidth;
            }
            if (bottomWidth < available) {
                available = bottomWidth;
            }
            if (blockWidth(chars, height) <= available) {
                return height;
            }
            height -= 2;
        }
        return 40;
    }

    //! Width of the display at a given y coordinate (for a round screen).
    private static function widthAt(y as Number, screenCx as Number, screenCy as Number,
                                    radius as Number) as Number {
        var dy = y - screenCy;
        if (dy < 0) {
            dy = -dy;
        }
        if (dy >= radius) {
            return 0;
        }
        var inner = (radius * radius - dy * dy).toFloat();
        var halfWidth = Math.sqrt(inner).toNumber();
        return halfWidth * 2;
    }

    //! Draw a numeric string centred horizontally on cx.
    //!
    //! @param text         Digits 0-9 and '-' are supported.
    //! @param cx           Horizontal centre of the completed number.
    //! @param rowCenterY   Vertical centre of the glyphs.
    //! @param maxHeight    Height to use if the display is wide enough.
    //! @param maxWidth     Hard horizontal limit in pixels.
    //! @param thin         Thin segments for AMOLED ambient mode.
    //! @param offsetX      Small burn-in avoiding offset.
    //! @param offsetY      Small burn-in avoiding offset.
    public static function draw(dc as Graphics.Dc, text as String, cx as Number, rowCenterY as Number,
                                maxHeight as Number, maxWidth as Number,
                                screenCx as Number, screenCy as Number, radius as Number,
                                color as Number, thin as Boolean,
                                offsetX as Number, offsetY as Number) as Void {
        var chars = text.length();
        if (chars == 0) {
            return;
        }

        var height = fitHeight(chars, rowCenterY, maxHeight, maxWidth, screenCx, screenCy, radius);
        var glyphWidth = (height * 0.54).toNumber();
        var gap = (height * 0.09).toNumber();
        var totalWidth = chars * glyphWidth + (chars - 1) * gap;
        var x0 = cx - totalWidth / 2 + offsetX;
        var y0 = rowCenterY - height / 2 + offsetY;

        var thickness = (height * (thin ? 0.045 : 0.145)).toNumber();
        if (thickness < 3) {
            thickness = 3;
        }
        var segmentGap = (thickness * 0.3).toNumber();
        if (segmentGap < 1) {
            segmentGap = 1;
        }

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < chars; i++) {
            var glyphX = x0 + i * (glyphWidth + gap);
            var mask = maskFor(text.substring(i, i + 1) as String);
            drawGlyph(dc, glyphX, y0, glyphWidth, height, thickness, segmentGap, mask);
        }
    }

    //! Seven-segment bit mask for a character.
    //! a=1, b=2, c=4, d=8, e=16, f=32, g=64
    private static function maskFor(character as String) as Number {
        switch (character) {
            case "0": return 0x3F;
            case "1": return 0x06;
            case "2": return 0x5B;
            case "3": return 0x4F;
            case "4": return 0x66;
            case "5": return 0x6D;
            case "6": return 0x7D;
            case "7": return 0x07;
            case "8": return 0x7F;
            case "9": return 0x6F;
            case "-": return 0x40;
            default:  return 0x00;
        }
    }

    private static function drawGlyph(dc as Graphics.Dc, x as Number, y as Number,
                                      width as Number, height as Number, thickness as Number,
                                      gap as Number, mask as Number) as Void {
        var r = thickness / 2;

        var horizontalX = x + r + gap;
        var horizontalWidth = width - thickness - 2 * gap;

        var verticalTop = y + thickness + gap;
        var verticalTopHeight = height / 2 - thickness - r - 2 * gap;
        var verticalBottom = y + height / 2 + r + gap;
        var verticalBottomHeight = height / 2 - thickness - r - 2 * gap;

        var leftX = x + r;
        var rightX = x + width - r;

        // a - top
        if ((mask & 1) != 0) {
            dc.fillRoundedRectangle(horizontalX, y, horizontalWidth, thickness, r);
        }
        // b - top right
        if ((mask & 2) != 0) {
            dc.fillRoundedRectangle(rightX - r, verticalTop, thickness, verticalTopHeight, r);
        }
        // c - bottom right
        if ((mask & 4) != 0) {
            dc.fillRoundedRectangle(rightX - r, verticalBottom, thickness, verticalBottomHeight, r);
        }
        // d - bottom
        if ((mask & 8) != 0) {
            dc.fillRoundedRectangle(horizontalX, y + height - thickness, horizontalWidth, thickness, r);
        }
        // e - bottom left
        if ((mask & 16) != 0) {
            dc.fillRoundedRectangle(leftX - r, verticalBottom, thickness, verticalBottomHeight, r);
        }
        // f - top left
        if ((mask & 32) != 0) {
            dc.fillRoundedRectangle(leftX - r, verticalTop, thickness, verticalTopHeight, r);
        }
        // g - middle
        if ((mask & 64) != 0) {
            dc.fillRoundedRectangle(horizontalX, y + height / 2 - r, horizontalWidth, thickness, r);
        }
    }
}
