#!/usr/bin/env python3
"""A Belefér appikon forrásképeinek előállítása a branding/ mappába.

Futtatás (Pillow kell hozzá):  python3 tool/generate_icons.py

A kész képeket a tool/apply_branding.py másolja a generált Android- és
iOS-projektbe. A képek a repóban vannak, ezért ezt a szkriptet csak akkor
kell újrafuttatni, ha az ikon terve változik.
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "branding"

INK = (16, 26, 60)
INK_LIGHT = (32, 46, 98)
TEAL = (25, 211, 197)
CREAM = (247, 242, 234)
CORAL = (229, 83, 75)

SS = 4  # túlmintavételezés az élsimításhoz


def _vertical_gradient(size, top, bottom):
    img = Image.new("RGB", (size, size), top)
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        color = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        draw.line([(0, y), (size, y)], fill=color)
    return img


def _draw_motif(draw, size, scale):
    """Gyűrűdiagram, amelynek résébe pontosan „belefér” egy érme."""
    cx = size / 2
    cy = size / 2
    outer = 300 * scale
    width = 124 * scale
    box = [cx - outer, cy - outer, cx + outer, cy + outer]
    # Pillow: 0° = 3 óra, az óramutató járásával megegyezően.
    draw.arc(box, start=-66, end=176, fill=TEAL, width=round(width))
    draw.arc(box, start=184, end=246, fill=CORAL, width=round(width))
    # Érme a gyűrű tetején, a résben.
    ring_r = outer - width / 2
    coin_r = 74 * scale
    coin_cy = cy - ring_r
    draw.ellipse(
        [cx - coin_r, coin_cy - coin_r, cx + coin_r, coin_cy + coin_r],
        fill=CREAM,
    )
    inner_r = coin_r * 0.5
    draw.ellipse(
        [cx - inner_r, coin_cy - inner_r, cx + inner_r, coin_cy + inner_r],
        outline=INK,
        width=round(15 * scale),
    )


def full_icon(size=1024):
    big = size * SS
    img = _vertical_gradient(big, INK_LIGHT, INK)
    _draw_motif(ImageDraw.Draw(img), big, big / 1024)
    return img.resize((size, size), Image.LANCZOS)


def adaptive_foreground(size):
    """Átlátszó előtér: a motívum a 108 dp-s réteg 66%-os biztonsági zónájában."""
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    _draw_motif(ImageDraw.Draw(img), big, big / 1024 * 0.9)
    return img.resize((size, size), Image.LANCZOS)


def rounded(img, radius_ratio=0.22):
    size = img.size[0]
    mask = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size * SS - 1, size * SS - 1], radius=size * SS * radius_ratio, fill=255
    )
    mask = mask.resize((size, size), Image.LANCZOS)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def main():
    master = full_icon(1024)
    ios = OUT / "ios"
    ios.mkdir(parents=True, exist_ok=True)
    ios_sizes = {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    for name, px in ios_sizes.items():
        master.resize((px, px), Image.LANCZOS).save(ios / name, optimize=True)

    res = OUT / "android" / "res"
    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    legacy = rounded(master)
    for name, factor in densities.items():
        folder = res / f"mipmap-{name}"
        folder.mkdir(parents=True, exist_ok=True)
        legacy.resize((round(48 * factor),) * 2, Image.LANCZOS).save(
            folder / "ic_launcher.png", optimize=True
        )
        adaptive_foreground(round(108 * factor)).save(
            folder / "ic_launcher_foreground.png", optimize=True
        )

    master.save(OUT / "icon-1024.png", optimize=True)
    print("Kész:", OUT)


if __name__ == "__main__":
    main()
