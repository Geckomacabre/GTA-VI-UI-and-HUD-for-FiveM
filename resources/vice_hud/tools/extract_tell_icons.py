"""Crop the weapon/person/people/vehicle tell icons out of screenshots of the
"GRAND THEFT AUTO VI: HUD DEFINITIONS" reference sheet, instead of hand,
tracing SVG paths by eye (which is how the earlier drafts drifted off the
reference, see BUCKME_HANDOFF.md sections 2a/2b).

Each source screenshot is one red-plate badge (icon + circular red plate +
whatever screenshot chrome is around it). This isolates the white glyph on a
transparent background by treating pixel luminance as an interpolation
between the plate red and pure white: plate-red pixels become fully
transparent, white glyph pixels stay opaque, and anti-aliased edge pixels
get a proportional alpha, so the result blends into `.tell`'s own red plate
with no fringing as long as `.tell`'s background is set to the same red
(see PLATE_RED below and style.css's `.tell { background }`).

Usage: put the four source screenshots' paths in SOURCES below and run:
    python extract_tell_icons.py
Output goes to html/icons/tells/tell_<name>.png.
"""
import os
from PIL import Image
import numpy as np

SOURCES = {
    "weapon": "path/to/weapon-reference-screenshot.png",
    "vehicle": "path/to/vehicle-reference-screenshot.png",
    "people": "path/to/people-reference-screenshot.png",
    "person": "path/to/person-reference-screenshot.png",
    "camera": "path/to/camera-reference-screenshot.png",
}

# Measured off the source screenshots (median of pixels classified as
# plate-red across all four), keep this in sync with style.css's
# `.tell { background: #8d161c; }`.
PLATE_RED = np.array([141.0, 22.0, 28.0])
WHITE_L = 253.0
RED_L = 0.299 * PLATE_RED[0] + 0.587 * PLATE_RED[1] + 0.114 * PLATE_RED[2]

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "html", "icons", "tells")


def extract(path, pad=16):
    im = Image.open(path).convert("RGB")
    a = np.array(im).astype(float)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    is_white = (r > 190) & (g > 190) & (b > 190)
    ys, xs = np.where(is_white)
    x0, x1 = max(xs.min() - pad, 0), min(xs.max() + pad, im.width)
    y0, y1 = max(ys.min() - pad, 0), min(ys.max() + pad, im.height)
    crop = a[y0:y1, x0:x1]
    luminance = 0.299 * crop[..., 0] + 0.587 * crop[..., 1] + 0.114 * crop[..., 2]
    alpha = np.clip((luminance - RED_L) / (WHITE_L - RED_L), 0, 1) * 255
    rgba = np.zeros((crop.shape[0], crop.shape[1], 4), dtype=np.uint8)
    rgba[..., 0:3] = 255
    rgba[..., 3] = alpha.astype(np.uint8)
    return Image.fromarray(rgba, mode="RGBA")


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, src in SOURCES.items():
        out_path = os.path.join(OUT_DIR, f"tell_{name}.png")
        extract(src).save(out_path)
        print(f"{name}: {src} -> {out_path}")
