#!/usr/bin/env python3
"""Generate AppIcon.icns for Honey Todo List.

Design: rounded-square macOS-style tile with a warm amber/honey gradient,
a honeycomb hex pattern in the background, and a single highlighted hex
holding a white checkmark — todo + honey, one mark.
"""
import math
import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter

OUT_DIR = os.path.dirname(os.path.abspath(__file__))
ICONSET = os.path.join(OUT_DIR, "AppIcon.iconset")
os.makedirs(ICONSET, exist_ok=True)

SIZE = 1024
# macOS Big Sur+ icon corner radius is ~22.37% of side length
RADIUS = int(SIZE * 0.2237)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def make_master(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # 1. Rounded-square tile w/ vertical honey gradient (warm gold → deep amber)
    tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    tdraw = ImageDraw.Draw(tile)
    top = (255, 211, 96)      # warm honey gold
    bot = (214, 130, 18)      # deep amber
    for y in range(size):
        c = lerp(top, bot, y / size) + (255,)
        tdraw.line([(0, y), (size, y)], fill=c)

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [(0, 0), (size, size)], radius=RADIUS, fill=255
    )
    img.paste(tile, (0, 0), mask)

    # 2. Honeycomb hex pattern overlay (subtle, cream-colored)
    hex_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hdraw = ImageDraw.Draw(hex_layer)
    hex_radius = size * 0.085
    hex_h = math.sqrt(3) * hex_radius
    cols = int(size / (1.5 * hex_radius)) + 3
    rows = int(size / hex_h) + 3
    for r in range(-1, rows):
        for c in range(-1, cols):
            cx = c * 1.5 * hex_radius
            cy = r * hex_h + (hex_h / 2 if c % 2 else 0)
            pts = [
                (cx + hex_radius * math.cos(math.radians(60 * k)),
                 cy + hex_radius * math.sin(math.radians(60 * k)))
                for k in range(6)
            ]
            hdraw.polygon(pts, outline=(255, 246, 220, 70), width=4)
    img = Image.alpha_composite(img, _clip_to_mask(hex_layer, mask))

    # 3. Center "highlight" hexagon — white-ish, where the check sits
    cx, cy = size / 2, size / 2
    big_r = size * 0.30
    pts = [
        (cx + big_r * math.cos(math.radians(60 * k - 30)),
         cy + big_r * math.sin(math.radians(60 * k - 30)))
        for k in range(6)
    ]

    # Soft shadow under the center hex
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    sdraw.polygon([(x, y + size * 0.018) for (x, y) in pts], fill=(80, 40, 0, 130))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=size * 0.022))
    img = Image.alpha_composite(img, _clip_to_mask(shadow, mask))

    # Center hex fill — soft cream w/ subtle gradient
    hex_fill = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    fdraw = ImageDraw.Draw(hex_fill)
    fdraw.polygon(pts, fill=(255, 252, 240, 255))
    # Gradient overlay (top lighter, bottom warmer)
    grad = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(grad)
    for y in range(size):
        a = int(60 * (y / size))  # subtle warm wash
        gdraw.line([(0, y), (size, y)], fill=(255, 200, 110, a))
    grad_masked = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    poly_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(poly_mask).polygon(pts, fill=255)
    grad_masked.paste(grad, (0, 0), poly_mask)
    img = Image.alpha_composite(img, hex_fill)
    img = Image.alpha_composite(img, grad_masked)

    # 4. Checkmark — chunky, modern, deep amber so it pops on cream
    check = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cdraw = ImageDraw.Draw(check)
    # Three points of the checkmark: bottom-left elbow, deep V, top-right tip
    p1 = (cx - size * 0.15, cy + size * 0.005)
    p2 = (cx - size * 0.035, cy + size * 0.110)
    p3 = (cx + size * 0.165, cy - size * 0.105)
    width = int(size * 0.075)
    color = (132, 60, 12, 255)  # rich espresso-amber
    cdraw.line([p1, p2], fill=color, width=width, joint="curve")
    cdraw.line([p2, p3], fill=color, width=width, joint="curve")
    # Round the line ends
    rcap = width / 2
    for p in (p1, p2, p3):
        cdraw.ellipse([p[0] - rcap, p[1] - rcap, p[0] + rcap, p[1] + rcap], fill=color)
    img = Image.alpha_composite(img, check)

    # 5. Tiny honey drip at lower-right of center hex (extra honey vibe)
    drip = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ddraw = ImageDraw.Draw(drip)
    drip_x = cx + size * 0.225
    drip_y = cy + size * 0.18
    drip_r = size * 0.028
    ddraw.ellipse(
        [drip_x - drip_r, drip_y - drip_r, drip_x + drip_r, drip_y + drip_r * 1.4],
        fill=(214, 130, 18, 255),
    )
    # tiny shine
    sh_r = drip_r * 0.35
    ddraw.ellipse(
        [drip_x - drip_r * 0.3 - sh_r, drip_y - drip_r * 0.3 - sh_r,
         drip_x - drip_r * 0.3 + sh_r, drip_y - drip_r * 0.3 + sh_r],
        fill=(255, 240, 200, 220),
    )
    img = Image.alpha_composite(img, _clip_to_mask(drip, mask))

    # 6. Subtle inner glow at top edge for depth
    gloss = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gldraw = ImageDraw.Draw(gloss)
    gldraw.rounded_rectangle(
        [(int(size * 0.04), int(size * 0.04)),
         (int(size * 0.96), int(size * 0.55))],
        radius=int(RADIUS * 0.85),
        fill=(255, 255, 255, 28),
    )
    gloss = gloss.filter(ImageFilter.GaussianBlur(radius=size * 0.04))
    img = Image.alpha_composite(img, _clip_to_mask(gloss, mask))

    return img


def _clip_to_mask(layer: Image.Image, mask: Image.Image) -> Image.Image:
    out = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    out.paste(layer, (0, 0), mask)
    return out


def main():
    master = make_master(SIZE)
    master.save(os.path.join(OUT_DIR, "AppIcon.png"))

    # Apple's required iconset sizes
    sizes = [
        (16, "16x16"),
        (32, "16x16@2x"),
        (32, "32x32"),
        (64, "32x32@2x"),
        (128, "128x128"),
        (256, "128x128@2x"),
        (256, "256x256"),
        (512, "256x256@2x"),
        (512, "512x512"),
        (1024, "512x512@2x"),
    ]
    for px, name in sizes:
        master.resize((px, px), Image.LANCZOS).save(
            os.path.join(ICONSET, f"icon_{name}.png")
        )

    icns = os.path.join(OUT_DIR, "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", ICONSET, "-o", icns], check=True)
    print(f"Wrote {icns}")


if __name__ == "__main__":
    main()
