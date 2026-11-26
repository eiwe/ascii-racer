#!/usr/bin/env python3
"""Android launcher icons from the logo's own look.

Draws "AR" from the logo's block-letter bitmaps (game/logo.gd LETTERS) as '#'
glyphs in the bundled Hack font, coloured with the logo's gradient (COLOURS)
over its blue shadow, on the game's dark background. Writes:

  assets/android/icon_192.png           main launcher icon, 192x192
  assets/android/icon_foreground.png    adaptive foreground, 432x432 (transparent;
                                        the letters inside the middle 66 %)
  assets/android/icon_background.png    adaptive background, 432x432
  assets/android/icon_monochrome.png    themed (monochrome) icon, 432x432

assets/android/ has a .gdignore, so Godot does not import these files and the
desktop and web exports do not carry them; only the Android preset reads them
(launcher_icons/*). Needs Python 3 with Pillow.

  tools/make_android_icons.py
"""
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "android")
FONT = os.path.join(ROOT, "assets", "fonts", "HackNerdFontMono-Bold.ttf")
LOGO = os.path.join(ROOT, "game", "logo.gd")
BG = (5, 6, 13)  # the menus' panel colour, Color(0.02, 0.025, 0.05)
DOT = (40, 44, 62)


def logo_data():
    src = open(LOGO, encoding="utf-8").read()
    block = src[src.index("const LETTERS"):]
    letters = {}
    for ch in "AR":
        m = re.search(r'"%s": \[([^\]]*)\]' % ch, block)
        letters[ch] = re.findall(r'"([.#]+)"', m.group(1))
    colours = re.search(r"const COLOURS: Array\[Color\] = \[([^\]]*)\]", src).group(1)
    grad = [tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) for h in re.findall(r'Color\("([0-9a-fA-F]{6})"\)', colours)]
    shadow = re.search(r'const SHADOW_COLOUR: Color = Color\("([0-9a-fA-F]{6})"\)', src).group(1)
    return letters, grad, tuple(int(shadow[i:i + 2], 16) for i in (0, 2, 4))


def gradient(grad, t):
    t = min(max(t, 0.0), 1.0) * (len(grad) - 1)
    i = min(int(t), len(grad) - 2)
    f = t - i
    return tuple(round(grad[i][k] + (grad[i + 1][k] - grad[i][k]) * f) for k in range(3))


def draw_letters(img, box, letters, grad, shadow, mono=None):
    """'AR' as '#' cells filling `box` (x, y, w, h), slanted like the logo."""
    word = [letters["A"], letters["R"]]
    rows = len(word[0])
    cols = sum(len(l[0]) for l in word) + 1  # one cell between letters
    slant = 0.35  # cells of shift per row, as the logo leans
    cw = box[2] / (cols + slant * rows + 0.6)
    ch = box[3] / (rows + 0.6)
    font = ImageFont.truetype(FONT, int(ch * 1.05))
    d = ImageDraw.Draw(img)
    for pass_ in ("shadow", "ink"):
        x0 = 0
        for bm in word:
            for r, line in enumerate(bm):
                for c, p in enumerate(line):
                    if p != "#":
                        continue
                    x = box[0] + (x0 + c + slant * (rows - 1 - r)) * cw
                    y = box[1] + r * ch
                    if mono is not None:
                        if pass_ == "ink":
                            d.text((x, y), "#", font=font, fill=mono)
                    elif pass_ == "shadow":
                        d.text((x + cw * 0.35, y + ch * 0.3), "#", font=font, fill=shadow)
                    else:
                        d.text((x, y), "#", font=font, fill=gradient(grad, (r + 0.5) / rows))
            x0 += len(bm[0]) + 1


def background(size):
    img = Image.new("RGB", (size, size), BG)
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, max(size // 24, 8))
    step = size / 16
    for j in range(16):
        for i in range(16):
            d.text((i * step + step * 0.3, j * step), ".", font=font, fill=DOT)
    return img


def main():
    letters, grad, shadow = logo_data()
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, ".gdignore"), "w").close()
    # Main icon: background, letters with a margin.
    main_icon = background(192)
    draw_letters(main_icon, (22, 52, 148, 88), letters, grad, shadow)
    main_icon.save(os.path.join(OUT, "icon_192.png"))
    # Adaptive: the launcher masks to a shape and may crop to the middle 66 %
    # (288 px of 432), so the letters stay inside that.
    fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    draw_letters(fg, (82, 150, 268, 132), letters, grad, shadow)
    fg.save(os.path.join(OUT, "icon_foreground.png"))
    background(432).save(os.path.join(OUT, "icon_background.png"))
    # Themed icon (Android 13+): one colour, the launcher tints it.
    mono = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    draw_letters(mono, (82, 150, 268, 132), letters, grad, shadow, mono=(255, 255, 255, 255))
    mono.save(os.path.join(OUT, "icon_monochrome.png"))
    print("wrote", ", ".join(sorted(f for f in os.listdir(OUT) if f.endswith(".png"))), "in", OUT)


if __name__ == "__main__":
    sys.exit(main())
