#!/usr/bin/env python3
"""
Shabbat Clock App Store Screenshot Composer.
Forked from axiom aso-appstore-screenshots/compose.py with:
 - Lighter font weight (Heavy, not Black)
 - Hebrew auto-detection -> SFHebrew
 - Same device frame + layout math
"""

import argparse
import os
import re
from PIL import Image, ImageDraw, ImageFont

CANVAS_W = 1290
CANVAS_H = 2796

DEVICE_W = 1030
BEZEL = 15
SCREEN_W = DEVICE_W - 2 * BEZEL
SCREEN_CORNER_R = 62

DEVICE_Y = 720

VERB_SIZE_MAX = 240
VERB_SIZE_MIN = 110
DESC_SIZE = 110
# Gap expressed as a ratio of desc font size — script-agnostic
VERB_DESC_GAP_RATIO = 0.15   # 15% of desc font size between verb bottom and desc top
DESC_LINE_GAP = 14
MAX_TEXT_W = int(CANVAS_W * 0.88)
MAX_VERB_W = int(CANVAS_W * 0.88)

FONT_LATIN = "/Library/Fonts/SF-Pro-Display-Heavy.otf"
FONT_HEBREW = "/System/Library/Fonts/SFHebrew.ttf"

SKILL_DIR = os.path.expanduser("~/.claude/skills/aso-appstore-screenshots")
FRAME_PATH = os.path.join(SKILL_DIR, "assets", "device_frame.png")

HEBREW_RE = re.compile(r"[֐-׿]")


def is_hebrew(text):
    return bool(HEBREW_RE.search(text))


def pick_font_path(text):
    return FONT_HEBREW if is_hebrew(text) else FONT_LATIN


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


def word_wrap(draw, text, font, max_w):
    words = text.split()
    lines, cur = [], ""
    for w in words:
        test = f"{cur} {w}".strip()
        if draw.textlength(test, font=font) <= max_w:
            cur = test
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def fit_font(text, font_path, max_w, size_max, size_min):
    dummy = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    for size in range(size_max, size_min - 1, -4):
        font = ImageFont.truetype(font_path, size)
        bbox = dummy.textbbox((0, 0), text, font=font)
        if (bbox[2] - bbox[0]) <= max_w:
            return font
    return ImageFont.truetype(font_path, size_min)


def draw_centered(draw, y, text, font, max_w=None):
    """Draw lines using font-metric-based spacing so Hebrew + Latin line up identically."""
    lines = word_wrap(draw, text, font, max_w) if max_w else [text]
    ascent, descent = font.getmetrics()
    for i, line in enumerate(lines):
        draw.text((CANVAS_W // 2, y), line, fill="white", font=font, anchor="mt")
        y += ascent + descent
        if i < len(lines) - 1:
            y += DESC_LINE_GAP
    return y


def compose(bg_hex, verb, desc, screenshot_path, output_path):
    bg = hex_to_rgb(bg_hex)

    canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (*bg, 255))
    draw = ImageDraw.Draw(canvas)

    verb_up = verb if is_hebrew(verb) else verb.upper()
    desc_up = desc

    verb_font_path = pick_font_path(verb_up)
    desc_font_path = pick_font_path(desc_up)

    verb_font = fit_font(verb_up, verb_font_path, MAX_VERB_W, VERB_SIZE_MAX, VERB_SIZE_MIN)
    desc_font = ImageFont.truetype(desc_font_path, DESC_SIZE)

    text_top = 200
    # Dry-run to measure actual text block height
    dummy_img = Image.new("RGBA", (CANVAS_W, CANVAS_H))
    dummy_draw = ImageDraw.Draw(dummy_img)
    m_y = text_top
    m_y = draw_centered(dummy_draw, m_y, verb_up, verb_font)
    m_y += int(DESC_SIZE * VERB_DESC_GAP_RATIO)
    m_y = draw_centered(dummy_draw, m_y, desc_up, desc_font, max_w=MAX_TEXT_W)
    # Guard against overflow into the device frame
    text_bottom_limit = DEVICE_Y - 20
    if m_y > text_bottom_limit:
        raise SystemExit(
            f"ERROR: text block (bottom y={m_y}) overflows into device frame "
            f"(limit y={text_bottom_limit}). Shorten verb/desc."
        )
    y = text_top
    y = draw_centered(draw, y, verb_up, verb_font)
    y += int(DESC_SIZE * VERB_DESC_GAP_RATIO)
    draw_centered(draw, y, desc_up, desc_font, max_w=MAX_TEXT_W)

    device_y = DEVICE_Y
    device_x = (CANVAS_W - DEVICE_W) // 2
    screen_x = device_x + BEZEL
    screen_y = device_y + BEZEL

    shot = Image.open(screenshot_path).convert("RGBA")
    scale = SCREEN_W / shot.width
    sc_w = SCREEN_W
    sc_h = int(shot.height * scale)
    shot = shot.resize((sc_w, sc_h), Image.LANCZOS)

    screen_h = CANVAS_H - screen_y + 500

    scr_mask = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(scr_mask).rounded_rectangle(
        [screen_x, screen_y, screen_x + SCREEN_W, screen_y + screen_h],
        radius=SCREEN_CORNER_R,
        fill=255,
    )

    scr_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(scr_layer).rounded_rectangle(
        [screen_x, screen_y, screen_x + SCREEN_W, screen_y + screen_h],
        radius=SCREEN_CORNER_R,
        fill=(0, 0, 0, 255),
    )
    scr_layer.paste(shot, (screen_x, screen_y))
    scr_layer.putalpha(scr_mask)

    canvas = Image.alpha_composite(canvas, scr_layer)

    frame_template = Image.open(FRAME_PATH).convert("RGBA")
    frame_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    frame_layer.paste(frame_template, (device_x, device_y))
    canvas = Image.alpha_composite(canvas, frame_layer)

    canvas.convert("RGB").save(output_path, "PNG")
    print(f"✓ {output_path} ({CANVAS_W}×{CANVAS_H})")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--bg", required=True)
    p.add_argument("--verb", required=True)
    p.add_argument("--desc", required=True)
    p.add_argument("--screenshot", required=True)
    p.add_argument("--output", required=True)
    args = p.parse_args()
    compose(args.bg, args.verb, args.desc, args.screenshot, args.output)


if __name__ == "__main__":
    main()
