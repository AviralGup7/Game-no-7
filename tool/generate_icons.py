#!/usr/bin/env python3
"""
Deterministically generate launcher icons, adaptive layers, notification icon
and Play Store graphics.

Code-generated rather than sourced or AI-made: reproducible byte-for-byte, no
third-party licence, one-line rebrand. CI regenerates and fails on drift.

Design: a 3x3 Hitori fragment with two cells shaded out and a large number in
the corner cell. The shaded squares ARE the brand - they are the one visual
that says "this is Hitori" rather than "this is a sudoku", and the oversized
numeral says "large print" before a word is read.

The grid drawn here is the same verified-unique 3x3 used in the How to play
screen, so the icon is a real puzzle rather than decorative nonsense.
"""
from PIL import Image, ImageDraw, ImageFont
import os

ROOT = os.path.join(os.path.dirname(__file__), '..')
RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
BRAND = os.path.join(ROOT, 'assets', 'branding')

TEAL_DEEP = (0, 56, 46)
TEAL = (15, 107, 92)
CREAM = (246, 250, 249)
INK = (27, 43, 40)
ON_SHADE = (214, 228, 224)
AMBER = (180, 83, 10)

# The verified-unique 3x3 from how_to_play.dart.
#   3 3 1     # . #
#   3 2 1     . . .
#   1 1 1     # . #
NUMS = [
    [3, 3, 1],
    [3, 2, 1],
    [1, 1, 1],
]
SHADED = [
    [True, False, True],
    [False, False, False],
    [True, False, True],
]


def _font(px):
    for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"]:
        if os.path.exists(p):
            return ImageFont.truetype(p, px)
    return ImageFont.load_default()


def draw_icon(size, pad_ratio=0.12, rounded=True, transparent=False):
    """Supersampled 4x then downscaled so edges stay clean at every density."""
    S = 4
    W = size * S
    img = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    if not transparent:
        if rounded:
            d.rounded_rectangle([0, 0, W - 1, W - 1],
                                radius=int(W * 0.22), fill=CREAM)
        else:
            d.rectangle([0, 0, W - 1, W - 1], fill=CREAM)

    pad = int(W * pad_ratio)
    avail = W - 2 * pad
    cell = avail / 3.0
    lw = max(2, int(cell * 0.055))
    f = _font(int(cell * 0.60))

    for r in range(3):
        for c in range(3):
            x0 = pad + c * cell
            y0 = pad + r * cell
            box = [x0, y0, x0 + cell, y0 + cell]
            on = SHADED[r][c]
            if on:
                d.rectangle(box, fill=INK)
            ch = str(NUMS[r][c])
            bb = d.textbbox((0, 0), ch, font=f)
            d.text((x0 + cell / 2 - (bb[2] - bb[0]) / 2 - bb[0],
                    y0 + cell / 2 - (bb[3] - bb[1]) / 2 - bb[1]),
                   ch, font=f, fill=ON_SHADE if on else TEAL_DEEP)

    # Grid lines, outer border heavier.
    for k in range(4):
        x = pad + k * cell
        y = pad + k * cell
        w = lw * 2 if k in (0, 3) else lw
        d.line([(x, pad), (x, pad + 3 * cell)], fill=TEAL_DEEP, width=w)
        d.line([(pad, y), (pad + 3 * cell, y)], fill=TEAL_DEEP, width=w)

    return img.resize((size, size), Image.LANCZOS)


def launcher():
    for folder, px in [('mipmap-mdpi', 48), ('mipmap-hdpi', 72),
                       ('mipmap-xhdpi', 96), ('mipmap-xxhdpi', 144),
                       ('mipmap-xxxhdpi', 192)]:
        p = os.path.join(RES, folder)
        os.makedirs(p, exist_ok=True)
        draw_icon(px).save(os.path.join(p, 'ic_launcher.png'))

    # Adaptive foreground must sit inside the 66/108 safe zone or the OEM mask
    # clips it.
    for folder, px in [('mipmap-mdpi', 108), ('mipmap-hdpi', 162),
                       ('mipmap-xhdpi', 216), ('mipmap-xxhdpi', 324),
                       ('mipmap-xxxhdpi', 432)]:
        canvas = Image.new('RGBA', (px, px), (0, 0, 0, 0))
        inner = int(px * 0.60)
        art = draw_icon(inner, pad_ratio=0.02, rounded=False,
                        transparent=True)
        off = (px - inner) // 2
        canvas.paste(art, (off, off), art)
        p = os.path.join(RES, folder)
        os.makedirs(p, exist_ok=True)
        canvas.save(os.path.join(p, 'ic_launcher_foreground.png'))


def notification():
    """Monochrome, transparent: Android tints it and discards colour."""
    for folder, px in [('drawable-mdpi', 24), ('drawable-hdpi', 36),
                       ('drawable-xhdpi', 48), ('drawable-xxhdpi', 72),
                       ('drawable-xxxhdpi', 96)]:
        S = 8
        W = px * S
        img = Image.new('RGBA', (W, W), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        # A checker of filled and outlined cells. Numbers would be mush at
        # 24 dp, but the shading pattern still reads as Hitori.
        cell = W / 3
        pad = cell * 0.07
        for r in range(3):
            for c in range(3):
                box = [c * cell + pad, r * cell + pad,
                       (c + 1) * cell - pad, (r + 1) * cell - pad]
                if SHADED[r][c]:
                    d.rectangle(box, fill=(255, 255, 255, 255))
                else:
                    d.rectangle(box, outline=(255, 255, 255, 255),
                                width=max(2, int(cell * 0.14)))
        p = os.path.join(RES, folder)
        os.makedirs(p, exist_ok=True)
        img.resize((px, px), Image.LANCZOS).save(
            os.path.join(p, 'ic_notification.png'))


def store():
    os.makedirs(BRAND, exist_ok=True)
    draw_icon(512).save(os.path.join(BRAND, 'play_icon_512.png'))

    W, H = 1024, 500
    img = Image.new('RGB', (W, H), CREAM)
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)],
               fill=(int(246 - 8 * t), int(250 - 10 * t), int(249 - 10 * t)))

    art = draw_icon(350)
    img.paste(art, (72, (H - 350) // 2), art)

    ft, fs = _font(74), _font(30)
    d.text((470, 148), "Large Print", font=ft, fill=TEAL_DEEP)
    d.text((470, 228), "Hitori", font=ft, fill=TEAL_DEEP)

    # No cognitive or medical claim - the FTC fined Lumosity $2M for exactly
    # that kind of copy.
    tag = "Big print · No timer · Offline"
    d.text((474, 326), tag, font=fs, fill=(66, 78, 76))
    right = d.textbbox((474, 326), tag, font=fs)[2]
    assert right < W - 24, f"feature graphic strapline overflows: {right}px"

    d.rounded_rectangle([474, 378, 690, 390], radius=6, fill=AMBER)
    img.save(os.path.join(BRAND, 'play_feature_1024x500.png'))


if __name__ == '__main__':
    launcher()
    notification()
    store()
    print('icons + store graphics generated')
