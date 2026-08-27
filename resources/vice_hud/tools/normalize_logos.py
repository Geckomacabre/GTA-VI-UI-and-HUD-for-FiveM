# -*- coding: utf-8 -*-
"""Evens out how BIG the manufacturer marks read, and puts every one on the
same canvas.

    pip install pillow
    python tools/normalize_logos.py

Build tooling, like tools/make_masks.py. Operates in place on html/logos/*.png
and keeps a one-time copy of whatever it found there in tools/logos_raw/.

THE PROBLEM THIS SOLVES
    fetch_logos.py already evens out how DARK the marks are (greyscale plus a
    gamma pass onto one ink target) and then crops each to its own ink and caps
    the longest edge. What it does not do is even out how LARGE they read, and
    those are different problems.

    After cropping, every file is 100% ink to its own edges -- but the marks are
    wildly different SHAPES. Truffade is 192x147, a wide slab. Albany is
    100x192, a narrow upright. Feed those to one CSS rule
    (`max-width: 96%; max-height: 140%`) and the wide one is bounded by width
    while the tall one is bounded by height, so they end up with completely
    different amounts of ink on the panel: Truffade came out roughly three
    times the visual mass of the marks either side of it, which is what "the
    Truffade logo is kinda too big" was.

    No CSS rule can fix that, because the information needed -- how much ink a
    given mark actually has -- is in the pixels, not in the box.

WHAT IT DOES
    Scales each mark so its alpha-weighted INK AREA is the same across the
    roster, then centres it on one shared square canvas.

    Area, not height and not width. Height alone makes wide slabs enormous;
    width alone makes narrow uprights enormous. sqrt(area) is the closest cheap
    stand-in for "how big does this read", because it is the side of the square
    that holds the same amount of ink -- so a wide mark and a tall mark with the
    same ink end up feeling the same size, which is the thing being asked for.

    The target is the MEDIAN of the roster's current sizes, so the set as a
    whole stays about as large as it is today; only the outliers move.

    A mark whose natural shape would then overhang the canvas is scaled back to
    fit (FILL below). That is the one case where equal area is given up -- an
    extremely wide mark cannot both keep its area and stay inside the box --
    and it is deliberately the cap rather than the rule.

    Output is one uniform CANVAS for every mark, which is what lets the
    stylesheet stop caring: with every file the same square, any max-width /
    max-height pair renders every mark at the same scale.
"""

import os
import shutil
import math

from PIL import Image

# The shared canvas, in pixels. Purely a RESOLUTION choice -- how sharp the
# marks are and how many bytes every player downloads. It does not change how
# big anything looks, because INK and FILL below are both fractions of it, so
# retuning this scales the whole roster together.
CANVAS = 160

# The size every mark is normalised to, as a fraction of the canvas: the side
# of the square that would hold the same amount of ink. Measured from the
# roster's own median at the original 192px canvas (90.8/192), so the set stays
# about as large as it has always been and only the outliers move.
INK = 0.473

# How much of the canvas the ink may span before it is scaled back. The margin
# stops a mark sitting hard against the edge of its own box, which reads as
# clipped once the panel crops it.
FILL = 0.94


def ink_area(alpha):
    """Alpha-weighted pixel count -- the mark's real ink, not its bounding box.

    A hollow roundel and a solid slab can share a bounding box and carry very
    different amounts of ink, and it is the ink that the eye weighs.
    """
    h = alpha.histogram()
    return sum(i * h[i] for i in range(256)) / 255.0


def load(path):
    img = Image.open(path)
    # Everything fetch_logos.py writes is 'LA'. Anything hand-dropped into
    # html/logos/ might not be, so normalise before touching the channels.
    if img.mode != 'LA':
        img = img.convert('RGBA')
        grey = img.convert('L')
        alpha = img.split()[-1]
        img = Image.merge('LA', (grey, alpha))
    return img


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    logos = os.path.normpath(os.path.join(here, os.pardir, 'html', 'logos'))
    backup = os.path.join(here, 'logos_raw')

    files = sorted(f for f in os.listdir(logos) if f.lower().endswith('.png'))
    if not files:
        print('no logos found in %s' % logos)
        return

    # One-time backup, NEVER overwritten -- it holds the pre-normalisation
    # originals and a second run would otherwise replace them with already-
    # normalised copies and lose the source for good.
    if not os.path.isdir(backup):
        os.makedirs(backup)
        for f in files:
            shutil.copy2(os.path.join(logos, f), os.path.join(backup, f))
        print('backed up %d original marks -> tools/logos_raw/' % len(files))

    # Once the backup exists, EVERY run reads from it rather than from
    # html/logos/. That is what makes this re-runnable: normalising an already-
    # normalised mark would resample it a second time (and a third), softening
    # it a little more each pass, and CANVAS could never be retuned downward
    # because the ink would already have been padded to the old size.
    src = backup if os.path.isdir(backup) else logos
    files = sorted(f for f in os.listdir(src) if f.lower().endswith('.png'))
    print('reading originals from %s' % os.path.relpath(src, os.path.dirname(here)))

    marks = []
    for f in files:
        img = load(os.path.join(src, f))
        alpha = img.split()[1]
        box = alpha.getbbox()
        if not box:
            print('  %-28s EMPTY, skipped' % f)
            continue
        img = img.crop(box)
        alpha = img.split()[1]
        marks.append((f, img, math.sqrt(max(ink_area(alpha), 1.0))))

    # A fraction of the canvas, NOT the roster's own median in absolute pixels.
    # Deriving it from the sources each run would make the result depend on
    # which marks happen to be present, and -- worse -- retuning CANVAS
    # downward would keep the old absolute target, push far more marks into the
    # FILL clamp and quietly undo the evening-out this exists to do.
    target = CANVAS * INK
    sizes = sorted(m[2] for m in marks)
    print('target ink size: %.1f px of a %d canvas  (sources ran %.0f-%.0f)'
          % (target, CANVAS, sizes[0], sizes[-1]))

    limit = CANVAS * FILL
    clamped = 0
    for name, img, size in marks:
        scale = target / size
        w, h = img.width * scale, img.height * scale
        # The cap: keep the mark inside the canvas even when equal area would
        # push it out. Only extreme aspect ratios ever hit this.
        over = max(w / limit, h / limit)
        if over > 1.0:
            scale /= over
            w, h = img.width * scale, img.height * scale
            clamped += 1
        w, h = max(1, int(round(w))), max(1, int(round(h)))

        resized = img.resize((w, h), Image.LANCZOS)
        canvas = Image.new('LA', (CANVAS, CANVAS), (0, 0))
        canvas.paste(resized, ((CANVAS - w) // 2, (CANVAS - h) // 2))
        canvas.save(os.path.join(logos, name), optimize=True)

    print('normalised %d marks onto %dx%d (%d clamped to fit)'
          % (len(marks), CANVAS, CANVAS, clamped))


if __name__ == '__main__':
    main()
