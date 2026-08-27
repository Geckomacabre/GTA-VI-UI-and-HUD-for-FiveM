#!/usr/bin/env python3
"""Bake the family of minimap radar masks in stream/.

    python tools/make_masks.py

GTA cannot generate a texture at runtime, so "corner radius" cannot be a live
value the way a CSS radius can. What it CAN do is swap which texture dictionary
is replacing `radarmasksm`. So the radius control is a set of pre-baked masks,
one per step, and client.lua swaps between them.

Each file is `stream/vice_mask_NN.ytd`, where NN is the corner radius as a
percentage of the mask's SHORT side (its height). FiveM takes the texture
dictionary name from the FILENAME, so the files are what make the dict names;
the texture *inside* every one of them is `radarmasksm`, which is the stock name
being replaced.

HOW THE FILES ARE BUILT
-----------------------
`stream/vice_minimap.ytd` is used as a byte template. It is an RSC7 container:
a 16-byte header, then a raw-deflate stream that decompresses to an 8192-byte
resource block followed by exactly 512*256*4 bytes of BGRA pixels. Every mask in
the family has identical dimensions and format, so only the pixel block changes
and the 16-byte header (which encodes page counts, not lengths) is copied
verbatim.

THE ALPHA CHANNEL IS THE MASK
-----------------------------
GTA's radar shader reads ALPHA. The original file had its rounded rectangle
painted in RGB with alpha left at a uniform 255, which is a plain opaque
rectangle to the shader -- that is why the map kept drawing with square corners
no matter what the config said. Every mask written here puts the same coverage
value in all four channels, so it reads correctly either way.
"""

import os
import sys
import zlib

W, H = 512, 256
PIXELS = W * H * 4
HDR = 8192

# Radius steps, as a percentage of the texture's height. 0 is a full-bleed
# square; 50 is a stadium (the corner arc meets at the half-height).
STEPS = [0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 50]

# Keep the shape just inside the texture edge. The stock file does the same --
# a hard edge against the border shimmers once the engine samples it stretched.
INSET = 3.0

# Supersampling for the corner arcs. 4x4 is plenty at this size and keeps the
# generator instant.
SS = 4

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
STREAM = os.path.join(ROOT, 'stream')
TEMPLATE = os.path.join(STREAM, 'vice_minimap.ytd')


def load_template():
    """Return (16-byte header, 8192-byte resource block) from the shipped ytd."""
    data = open(TEMPLATE, 'rb').read()
    raw = zlib.decompressobj(-15).decompress(data[16:])
    if len(raw) != HDR + PIXELS:
        raise SystemExit(
            'template is %d bytes, expected %d -- it is not the 512x256 BGRA '
            'texture this script knows how to clone' % (len(raw), HDR + PIXELS))
    if b'radarmasksm' not in raw[:HDR]:
        raise SystemExit('template does not contain a texture named radarmasksm')
    return data[:16], raw[:HDR]


def coverage(x, y, r):
    """Fraction of pixel (x, y) inside the rounded rect, 0.0 to 1.0."""
    total = 0
    for sy in range(SS):
        py = y + (sy + 0.5) / SS
        for sx in range(SS):
            px = x + (sx + 0.5) / SS
            # Distance from the shape's edge, per axis, measured inward.
            dx = min(px - INSET, (W - INSET) - px)
            dy = min(py - INSET, (H - INSET) - py)
            if dx < 0 or dy < 0:
                continue
            if r <= 0:
                total += 1
                continue
            # Inside a corner box? Then the test is the arc, not the sides.
            if dx < r and dy < r:
                if (r - dx) ** 2 + (r - dy) ** 2 <= r * r:
                    total += 1
            else:
                total += 1
    return total / (SS * SS)


def build_pixels(radius_pct):
    """BGRA bytes for a rounded rect whose corner radius is radius_pct of H."""
    r = radius_pct / 100.0 * H
    # The arc cannot exceed half the short side, or opposite corners overlap.
    r = min(r, (H - 2 * INSET) / 2.0, (W - 2 * INSET) / 2.0)

    buf = bytearray(PIXELS)

    # Rows away from both corner bands are a flat run: compute one and copy it.
    #
    # The band has to clear the INSET as well as the arc. Sizing it to the arc
    # alone (int(r + 2)) put the first "flat" row at y=2 for radius 0 -- which is
    # inside the inset, so it is an EMPTY row, and copying it filled the whole
    # texture with zeroes. That shipped a completely blank mask_00.
    band = int(r + INSET + 2)
    flat = None

    for y in range(H):
        in_corner_band = y < band or y >= H - band
        if not in_corner_band and flat is not None:
            buf[y * W * 4:(y + 1) * W * 4] = flat
            continue

        row = bytearray(W * 4)
        for x in range(W):
            c = coverage(x, y, r)
            v = int(round(c * 255))
            o = x * 4
            row[o] = v       # B
            row[o + 1] = v   # G
            row[o + 2] = v   # R
            row[o + 3] = v   # A -- the channel the radar shader actually reads
        buf[y * W * 4:(y + 1) * W * 4] = row
        if not in_corner_band and flat is None:
            flat = bytes(row)

    # A mask that is blank, or opaque everywhere, is not a mask. Both are silent
    # failures in game -- the map just looks wrong -- so refuse to write one.
    mid = buf[(H // 2) * W * 4 + (W // 2) * 4 + 3]
    corner = buf[3]
    if mid != 255:
        raise SystemExit('radius %s: centre alpha is %d, expected 255' % (radius_pct, mid))
    if corner != 0:
        raise SystemExit('radius %s: outside-corner alpha is %d, expected 0' % (radius_pct, corner))

    return bytes(buf)


def write_ytd(path, header16, resblock, pixels):
    co = zlib.compressobj(9, zlib.DEFLATED, -15)
    body = co.compress(resblock + pixels) + co.flush()
    open(path, 'wb').write(header16 + body)
    return len(header16) + len(body)


def main():
    header16, resblock = load_template()
    total = 0
    for pct in STEPS:
        name = 'vice_mask_%02d.ytd' % pct
        size = write_ytd(os.path.join(STREAM, name), header16, resblock,
                         build_pixels(pct))
        total += size
        print('  %-20s radius %2d%% of height -> %5d bytes' % (name, pct, size))
    print('%d masks, %.1f KB total' % (len(STEPS), total / 1024.0))
    print('Steps for client.lua: ' + ', '.join(str(s) for s in STEPS))


if __name__ == '__main__':
    sys.exit(main())
