#!/usr/bin/env python3
"""Generate MacroSnap's launcher icons from assets/branding/app_icon_512.png.

Why this exists: the icon was previously stitched together by hand, and the
Android 8+ adaptive icon kept pointing at the OLD green vector while only the
legacy mipmap PNGs were regenerated. Modern launchers read the adaptive icon
exclusively, so phones kept showing the old icon no matter how many times the
PNGs were replaced. This script regenerates every layer from one source file so
they can never drift apart again.

Run from app/:  python tools/gen_app_icons.py

Outputs
  android/app/src/main/res/mipmap-*/ic_launcher.png              legacy (pre-8.0)
  android/app/src/main/res/mipmap-*/ic_launcher_foreground.png   adaptive foreground
  ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png            iOS, per Contents.json

Adaptive-icon sizing rule: every visible pixel of the artwork is kept inside the
66dp-diameter "safe circle" (radius 33dp of the 108dp canvas). Anything outside
that circle can be masked away by the launcher's shape (circle, squircle,
rounded square...), which is what used to clip the new leaf tip.
"""

from __future__ import annotations

import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
SRC = os.path.join(APP, "assets", "branding", "app_icon_512.png")
ANDROID_RES = os.path.join(APP, "android", "app", "src", "main", "res")
IOS_SET = os.path.join(
    APP, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset"
)

BACKGROUND = (0, 0, 0)

# density name -> px per dp
DENSITIES = {
    "mdpi": 1.0,
    "hdpi": 1.5,
    "xhdpi": 2.0,
    "xxhdpi": 3.0,
    "xxxhdpi": 4.0,
}

LEGACY_DP = 48          # launcher icon footprint on pre-8.0 devices
ADAPTIVE_DP = 108       # full adaptive-icon canvas
SAFE_RADIUS_DP = 33.0   # centre 66dp of the canvas is never masked away
ART_THRESHOLD = 30      # a pixel brighter than this in any channel is artwork


def art_pixels(img: Image.Image):
    """Yield (x, y) for every pixel that is part of the artwork, not the plate."""
    w, h = img.size
    px = img.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y][:3]
            if max(r, g, b) > ART_THRESHOLD:
                yield x, y


def art_geometry(img: Image.Image):
    """Bounding box, centre and max radius (from that centre) of the artwork."""
    xs = []
    ys = []
    for x, y in art_pixels(img):
        xs.append(x)
        ys.append(y)
    if not xs:
        raise SystemExit("source image has no artwork above the threshold")
    box = (min(xs), min(ys), max(xs) + 1, max(ys) + 1)
    cx = (box[0] + box[2]) / 2.0
    cy = (box[1] + box[3]) / 2.0
    max_r = max(((x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2) ** 0.5 for x, y in zip(xs, ys))
    return box, (cx, cy), max_r


def adaptive_foreground(src: Image.Image, geo, size_px: int) -> Image.Image:
    """Artwork centred on a black canvas, scaled into the safe circle."""
    _, (cx, cy), max_r = geo
    canvas = Image.new("RGB", (size_px, size_px), BACKGROUND)
    # dp per source pixel, chosen so the artwork's furthest pixel lands on the
    # safe circle's edge.
    dp_per_src = SAFE_RADIUS_DP / max_r
    px_per_dp = size_px / ADAPTIVE_DP
    scale = dp_per_src * px_per_dp
    new_size = max(1, round(src.width * scale))
    art = src.resize((new_size, new_size), Image.LANCZOS)
    left = round(size_px / 2.0 - cx * scale)
    top = round(size_px / 2.0 - cy * scale)
    canvas.paste(art, (left, top))
    return canvas


def legacy_icon(src: Image.Image, size_px: int) -> Image.Image:
    """The artwork full-bleed: pre-8.0 launchers draw whatever we give them."""
    return src.resize((size_px, size_px), Image.LANCZOS)


def main() -> int:
    if not os.path.exists(SRC):
        raise SystemExit(f"missing brand artwork: {SRC}")
    src = Image.open(SRC).convert("RGB")
    box, centre, max_r = art_geometry(src)
    print(f"artwork bbox={box} centre=({centre[0]:.1f},{centre[1]:.1f}) max_r={max_r:.1f}px")

    for density, mult in DENSITIES.items():
        out_dir = os.path.join(ANDROID_RES, f"mipmap-{density}")
        os.makedirs(out_dir, exist_ok=True)

        legacy_px = round(LEGACY_DP * mult)
        legacy_icon(src, legacy_px).save(
            os.path.join(out_dir, "ic_launcher.png"), optimize=True
        )

        fg = adaptive_foreground(src, (box, centre, max_r), round(ADAPTIVE_DP * mult))
        fg.save(os.path.join(out_dir, "ic_launcher_foreground.png"), optimize=True)
        print(f"  mipmap-{density}: ic_launcher.png {legacy_px}px, foreground {fg.width}px")

    if os.path.isdir(IOS_SET):
        contents = json.load(open(os.path.join(IOS_SET, "Contents.json")))
        for entry in contents.get("images", []):
            filename = entry.get("filename")
            if not filename:
                continue
            base = float(entry["size"].split("x")[0])
            scale = int(entry["scale"].rstrip("x"))
            px = round(base * scale)
            # iOS requires opaque, square, unmasked artwork.
            legacy_icon(src, px).save(os.path.join(IOS_SET, filename), optimize=True)
        print(f"  iOS: {sum(1 for e in contents['images'] if e.get('filename'))} icons")
    else:
        print("  iOS icon set not present, skipped")

    return 0


if __name__ == "__main__":
    sys.exit(main())
