# -*- coding: utf-8 -*-
"""Downloads the manufacturer marks into html/logos/ and normalises them for
use as the vehicle panel's watermark.

    pip install pillow
    python tools/fetch_logos.py

Build tooling, like tools/make_masks.py. Run it when the roster in
tools/make_makes.py gains a manufacturer, or when a better mark turns up on
the wiki; the shipped output is html/logos/*.png, which fxmanifest streams to
every client.

SOURCE
    https://gta.fandom.com/wiki/Category:Vehicle_manufacturers

    Rockstar's own marks, as the wiki hosts them. tier() is the order the
    picker tries them in and says why each rung is where it is; the short
    version is that the marque's own full-size mark wins, and the GTA Online
    website's icon set -- consistent but only 64x64 -- is the fallback for a
    brand that has nothing else.

WHAT THE PROCESSING DOES AND WHY
    Everything comes out as GREYSCALE INK plus an alpha channel, evened out so
    the whole roster reads at one weight. The roster is sixty-odd marks drawn by
    different people over fifteen years -- some flat, some chrome, some with a
    drop shadow baked in, some light-on-dark and some dark-on-light -- and
    behind the same two lines of type they have to look like one set rather than
    like sixty-odd downloads. ink() is where that happens and carries the
    reasoning for each correction.

    Colour goes because the panel is a dark plate and the type on it is white:
    a full-colour badge behind white text at watermark opacity is mud, and the
    one thing a watermark must not do is make the text it sits behind harder to
    read. LA mode is also roughly a third of the size of RGBA, and these ship to
    every player who connects.

    Marks that arrive on an opaque background get their alpha rebuilt from
    distance-to-the-corner-colour, because "logo on white" is how a good few of
    them are stored and a straight alpha copy would give a white rectangle.
"""
import io
import json
import math
import os
import re
import sys
import time
import urllib.parse
import urllib.request

try:
    from PIL import Image, ImageOps, ImageStat
except ImportError:
    raise SystemExit('needs Pillow:  pip install pillow')

API = 'https://gta.fandom.com/api.php'
UA = {'User-Agent': 'vice_hud-logos/1.0 (FiveM HUD, local build tooling)'}

# Longest side of the shipped file. The watermark is drawn inside a panel that
# is about a tenth of the screen's height, so on a 4K display it never exceeds
# roughly this -- and every pixel past it is bytes each player downloads to
# render something they cannot see.
MAX_EDGE = 192

# Sentinel for "every mark this marque has is its own name set as type".
WORDMARK = False

# Where the average covered pixel of every mark is pulled to, out of 255. High
# enough that a dark-bodied emblem still reads on a near-black panel, low enough
# that a mark with any internal detail does not blow out into a white blob.
INK_TARGET = 168.0

# (normalised key, wiki page prefix to search, explicit filename / None / WORDMARK)
#
# THE MARK MUST NOT SPELL THE MANUFACTURER'S NAME.
# The panel prints the make directly above the badge, so a mark carrying the
# name as well says it twice -- "TRUFFADE" over a hexagon with TRUFFADE written
# across it, which just reads as sloppy. Nearly every marque files both a lockup
# and a bare emblem and nothing in the FILENAME tells them apart, so the choice
# is made here by eye and pinned. Where two are equally clean the bigger wins.
#
# WORDMARK means every asset that marque has IS its name set as type -- Vapid's
# script, Progen's, plain "MTL" -- with no emblem underneath to fall back to.
# Those ship no mark at all and the panel keeps its plain plate, the same thing
# it does for an addon vehicle with no resolvable make.
#
# A single-letter monogram in a badge shape is an EMBLEM, not a wordmark:
# Karin's K, Weeny's W, Brute's B. An initialism that is the whole name -- BF,
# HVY, MTL, LCC, PED -- is the name, and goes.
BRANDS = [
    ("ALBANY",                    "Albany",        "Albany-GTAO-Logo.png"),
    ("ANNIS",                     "Annis",         "Annis-Logo-GTAO.png"),
    ("BENEFACTOR",                "Benefactor",    "Benefactor-GTAO-Logo.png"),
    # the roundel reads BF, which is the whole name
    ("BF",                        "BF",            WORDMARK),
    ("BOLLOKAN",                  "Bollokan",      "Bollokan-Preview-GTAO-Logo.png"),
    ("BRAVADO",                   "Bravado",       "Bravado-GTAO-Logo.png"),
    ("BRUTE",                     "Brute",         "Brute-GTAIV-LogoBadge.png"),
    ("BUCKINGHAM",                "Buckingham",    "Buckingham-GTAO-AltLogo.png"),
    ("CANIS",                     "Canis",         "Canis-GTAO-Logo.png"),
    ("CHARIOT",                   "Chariot",       "Chariot-Logo-GTAO.png"),
    ("CHEVAL",                    "Cheval",        "Cheval-Preview-GTAO-Logo.png"),
    ("CLASSIQUE",                 "Classique",     "Classique-GTAO-Logo.png"),
    ("COIL",                      "Coil",          "Coil-GTAO-Logo.png"),
    ("DECLASSE",                  "Declasse",      "Declasse-Logo-GTAO.png"),
    ("DEWBAUCHEE",                "Dewbauchee",    "Dewbauchee-Preview-GTAO-Logo.png"),
    ("DINKA",                     "Dinka",         "Dinka-Preview-GTAO-Logo.png"),
    ("DUNDREARY",                 "Dundreary",     "Dundreary-GTAO-Logo.png"),
    ("EBERHARD",                  "Eberhard",      "Eberhard-GTAO-EmblemWhite.png"),
    ("EMPEROR",                   "Emperor",       "Emperor-Preview-GTAO-Logo.png"),
    ("ENUS",                      "Enus",          "Enus-Preview-GTAO-Logo.png"),
    ("FATHOM",                    "Fathom",        "Fathom-Preview-GTAO-Logo.png"),
    ("GALLIVANTER",               "Gallivanter",   "Gallivanter-Preview-GTAO-Logo.png"),
    # the hare alone; every shield carries the banner
    ("GROTTI",                    "Grotti",        "Grotti-GTASA-RabbitLogo.png"),
    ("HIJAK",                     "Hijak",         "Hijak-Preview-GTAO-Logo.png"),
    ("HVY",                       "HVY",           WORDMARK),
    ("IMPONTE",                   "Imponte",       "Imponte-GTAO-Logo.png"),
    ("INVETERO",                  "Invetero",      "Invetero-GTAO-Logo.png"),
    ("JACKSHEEPE",                "JackSheepe",    "JackSheepe-Preview-GTAO-Logo.png"),
    ("JOBUILT",                   "Jobuilt",       "Jobuilt-Preview-GTAO-Logo.png"),
    ("KARIN",                     "Karin",         "Karin-GTAO-Logo.png"),
    ("KRAKEN",                    "Kraken",        "Kraken-Preview-GTAO-Logo.png"),
    # the peacock; Logo2 is the script
    ("LAMPADATI",                 "Lampadati",     "Lampadati-Logo-GTAO.png"),
    # no mark on the wiki at all
    ("LIBERTYCHOPSHOP",           "LibertyChop",   WORDMARK),
    ("LIBERTYCITYCYCLES",         "LCC",           WORDMARK),
    ("MAIBATSU",                  "Maibatsu",      "Maibatsu-Alt-Logo-GTAV.png"),
    ("MAMMOTH",                   "Mammoth",       "Mammoth-Preview-GTAO-Logo.png"),
    ("MAXWELL",                   "Maxwell",       "Maxwell-Preview-GTAO-Logo.png"),
    ("MTL",                       "MTL",           WORDMARK),
    ("NAGASAKI",                  "Nagasaki",      "Nagasaki-Logo-GTAOnline.png"),
    ("OBEY",                      "Obey",          "Obey-Preview-GTAO-Logo.png"),
    ("OCELOT",                    "Ocelot",        "Ocelot-GTAO-Logo.png"),
    ("OVERFLOD",                  "Overflod",      "Overflod-Preview-GTAO-Logo.png"),
    ("PEDCYCLES",                 "PED",           WORDMARK),
    # every shield has PEGASSI across the top of it
    ("PEGASSI",                   "Pegassi",       WORDMARK),
    ("PENAUD",                    "Penaud",        "Penaud-GTAO-Logo.png"),
    ("PFISTER",                   "Pfister",       "Pfister-GTAO-Logo.png"),
    ("PRINCIPE",                  "Principe",      WORDMARK),
    ("PROGEN",                    "Progen",        WORDMARK),
    ("RUNE",                      "RUNE",          "RUNE-Preview-GTAO-Logo.png"),
    ("SCHYSTER",                  "Schyster",      "Schyster-Preview-GTAO-Logo.png"),
    ("SHITZU",                    "Shitzu",        "Shitzu-Preview-GTAO-Logo.png"),
    ("SPEEDOPHILE",               "Speedophile",   "Speedophile-Preview-GTAO-Logo.png"),
    # no mark on the wiki at all
    ("STANLEY",                   "Stanley",       WORDMARK),
    ("STEELHORSE",                "SteelHorse",    "SteelHorse-Preview-GTAO-Logo.png"),
    ("TOUNDRA",                   "Toundra",       WORDMARK),
    ("TRICYCLES",                 "Tri-Cycles",    WORDMARK),
    # the bare monogram; every other Truffade asset spells it out
    ("TRUFFADE",                  "Truffade",      "Truffade-Preview-GTAO-Logo.png"),
    ("UBERMACHT",                 "Ubermacht",     "Ubermacht-Logo-Plain.png"),
    ("VAPID",                     "Vapid",         WORDMARK),
    ("VULCAR",                    "Vulcar",        "Vulcar-GTAV-Logo.png"),
    ("VYSSER",                    "Vysser",        WORDMARK),
    ("WEENY",                     "Weeny",         "Weeny-GTAO-Logo.png"),
    ("WESTERNCOMPANY",            "Western",       WORDMARK),
    # WORDMARK is what the WIKI has: every mark it hosts spells the name across
    # the shield. Overridden by tools/logos_local/, which wins outright -- the
    # server owner supplied a clean shield with the lettering removed.
    ("WESTERNMOTORCYCLECOMPANY",  "WesternMC",     WORDMARK),
    ("WILLARD",                   "Willard",       "Willard-Logo-GTAO.png"),
    ("ZIRCONIUM",                 "Zirconium",     "Zirconium-Preview-GTAO-Logo.png"),
]


def api(**params):
    params['format'] = 'json'
    url = API + '?' + urllib.parse.urlencode(params)
    return json.load(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30))


REJECT = 900


def tier(name):
    """Which KIND of asset this is. Lower is better; REJECT means never.

       Resolution is handled separately, and the split matters: the GTA Online
       website's "-Preview-GTAO-Logo" set is the most consistent one on the
       wiki and was the obvious first choice until you look at the files, which
       are 64x64 icons. At the size this watermark is drawn that is a blur, so
       the marque's own mark -- typically 300-700px -- wins and Preview is what
       a brand falls back to when it has nothing else. Dinka is the case that
       decides it: 64x64 is all Dinka has."""
    n = name.lower()
    if n.endswith('.jpg') or n.endswith('.jpeg'):
        return REJECT                  # no alpha, and always a photo of a mark
    if re.search(r'(tshirt|advert|hoodie|animation|decal|uniform|pinup)', n):
        return REJECT                  # merchandise, not the marque's mark
    if 'textlogo' in n or 'namebadge' in n:
        return 60                      # a wordmark is illegible at this size
    # AFTER the wordmark test. Vector is the best raster source there is and it
    # would otherwise win outright -- which is how Classique ended up with its
    # script wordmark instead of its crest, the one being SVG and the other not.
    if n.endswith('.svg'):
        return 5
    # BEFORE the -gtao-logo test below, which it would otherwise satisfy:
    # "Ubermacht-Preview-GTAO-Logo.png" ends in "-gtao-logo.png" like every
    # full-size mark does. Testing it second is what made a 64x64 icon beat
    # Ubermacht's own 512x512 roundel.
    if 'preview-gtao-logo' in n:
        return 40                      # 64x64. Last resort, see above.
    if 'onwhite' in n:
        return 50                      # recoverable, but never as clean
    if re.search(r'-(gtao|gtav)-logo\d*\.png$', n) or re.search(r'-logo-gtao(nline)?\.png$', n):
        return 10
    if re.search(r'-logo(-plain|-chrome|-\d{4})?\.png$', n):
        return 15
    if 'emblem' in n or 'badge' in n:
        return 30
    if 'logo' in n:
        return 35
    return REJECT


def shape_penalty(w, h):
    """A long thin strip is a wordmark, whatever it is filed under.

       Several marques file their wordmark as "<Name>-GTAO-Logo2.png", which
       the name test cannot tell from a badge -- Ocelot's is 445x42. Set behind
       two lines of type at watermark size a strip like that is indistinguish-
       able from an underline, so shape gets a say alongside the filename."""
    if not w or not h:
        return 0
    aspect = max(w, h) / float(min(w, h))
    return 25 if aspect > 4.0 else 0


# Hand-supplied marks, checked BEFORE the wiki. See its README for why one
# would be here; the short version is that some marques have nothing usable
# online and someone had a better file.
LOCAL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'logos_local')


def local_mark(key):
    path = os.path.join(LOCAL_DIR, key + '.png')
    return path if os.path.isfile(path) else None


def find_logo(prefix, explicit):
    # WORDMARK short-circuits: there is nothing to look for.
    if explicit is WORDMARK:
        return None
    imgs = api(action='query', list='allimages', aiprefix=prefix, ailimit=500,
               aiprop='url|size').get('query', {}).get('allimages', [])
    if explicit:
        for i in imgs:
            if i['name'] == explicit:
                return i
        return None
    cands = [i for i in imgs
             if re.search(r'(logo|emblem|badge)', i['name'], re.I)
             and tier(i['name']) < REJECT]
    if not cands:
        return None

    def key(i):
        # Kind and shape first, then the biggest of those. Sorting on
        # resolution ALONE picks a 1041px t-shirt print over the actual badge,
        # which is why this is the primary key and not a tie-break.
        w, h = i.get('width') or 0, i.get('height') or 0
        return (tier(i['name']) + shape_penalty(w, h), -max(w, h))

    cands.sort(key=key)
    return cands[0]


def coverage(img):
    """An 8-bit alpha: 255 where the mark is, 0 where it is not."""
    alpha = img.getchannel('A')
    if sum(alpha.histogram()[:250]) > img.width * img.height * 0.02:
        return alpha                                  # a real cut-out already

    # Opaque: the mark is printed on a flat card. Rebuild coverage from how far
    # each pixel is from the card's own colour, sampled at a corner.
    px = img.load()
    bg = px[0, 0][:3]
    out = Image.new('L', img.size)
    op = out.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b = px[x, y][:3]
            d = (abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2])) / 3.0
            op[x, y] = 255 if d > 90 else (0 if d < 30 else int((d - 30) / 60.0 * 255))
    return out


def percentile(img, mask, frac):
    hist = img.histogram(mask)
    total = sum(hist)
    if not total:
        return 255
    want, seen = total * frac, 0
    for value, count in enumerate(hist):
        seen += count
        if seen >= want:
            return value
    return 255


def ink(img, alpha):
    """The mark's own LUMINANCE, as greyscale ink.

       The obvious thing is a flat white silhouette -- paint every covered pixel
       white and let alpha do the rest -- and it is wrong for about a fifth of
       the roster. Pegassi's shield, Bravado's shield, Karin's roundel and a
       dozen others carry all of their detail in COLOUR against a solid outline:
       their alpha is one unbroken shape, so a silhouette of it is a blank
       shield. Keeping luminance keeps the horse inside the shield.

       Two corrections on top:
       - Marks drawn as dark ink on transparent (Ubermacht's plain roundel is
         the clearest) would come out near-black and vanish into a near-black
         panel, so a mark whose covered pixels average dark is inverted.
       - The result is then stretched so its brightest 5% is full white, which
         is what stops a mid-grey mark from reading as a fainter brand than a
         white one when they are all drawn at the same opacity."""
    lum = img.convert('RGB').convert('L')
    solid = alpha.point(lambda a: 255 if a > 128 else 0)
    if ImageStat.Stat(lum, mask=solid).mean[0] < 40:
        # Drawn as dark ink on transparent, with no light emblem to rescue it.
        # Gamma cannot lift this one -- there is nothing but ink -- so it has to
        # be flipped outright.
        lum = ImageOps.invert(lum)
    hi = percentile(lum, solid, 0.95)
    if 0 < hi < 250:
        f = 255.0 / hi
        lum = lum.point(lambda v: min(255, int(v * f)))

    # Then even out the WEIGHT of the set, by gamma rather than by another
    # linear stretch.
    #
    # Half a dozen marques draw a light emblem on a DARK body -- Ubermacht's
    # roundel, Pfister's crest, Bravado's shield. Faithful greyscale of those is
    # mostly black, and mostly black on a near-black panel is an invisible
    # watermark with a few bright strokes floating in it. Pulling the covered
    # mean up to a common target makes a dark-bodied mark read at the same
    # strength as a white one; gamma is what does it without flattening the
    # contrast between the body and the emblem on top of it, which is the thing
    # that makes the mark recognisable in the first place.
    mean = ImageStat.Stat(lum, mask=solid).mean[0]
    if 4 < mean < INK_TARGET:
        gamma = math.log(INK_TARGET / 255.0) / math.log(mean / 255.0)
        lum = lum.point(lambda v: int(255.0 * (v / 255.0) ** gamma) if v else 0)
    return lum


def process(raw):
    img = Image.open(io.BytesIO(raw)).convert('RGBA')
    alpha = coverage(img)
    grey = ink(img, alpha)

    box = alpha.getbbox()                             # drop transparent margins
    if box:
        alpha, grey = alpha.crop(box), grey.crop(box)
    if max(alpha.size) > MAX_EDGE:
        s = float(MAX_EDGE) / max(alpha.size)
        size = (max(1, int(alpha.width * s)), max(1, int(alpha.height * s)))
        alpha, grey = alpha.resize(size, Image.LANCZOS), grey.resize(size, Image.LANCZOS)

    # 'LA' rather than 'RGBA': the mark is greyscale by the time it gets here,
    # so three identical colour channels would be bytes every player downloads
    # for nothing.
    out = Image.merge('LA', (grey, alpha))
    return out


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    dest = os.path.normpath(os.path.join(here, os.pardir, 'html', 'logos'))
    if not os.path.isdir(dest):
        os.makedirs(dest)

    got, missing, total = 0, [], 0
    for key, prefix, explicit in BRANDS:
        # A local file wins outright, WORDMARK included: someone putting a mark
        # in logos_local/ is saying they found one this script could not.
        override = local_mark(key)
        if override:
            img = process(open(override, 'rb').read())
            path = os.path.join(dest, key + '.png')
            img.save(path, optimize=True)
            total += os.path.getsize(path)
            got += 1
            print('  %-26s %-42s %dx%d  %.1fkB' %
                  (key, 'logos_local/' + key + '.png', img.width, img.height,
                   os.path.getsize(path) / 1024.0))
            continue
        try:
            hit = find_logo(prefix, explicit)
        except Exception as exc:
            print('  ! %-26s lookup failed: %s' % (key, exc))
            missing.append(key)
            continue
        if not hit:
            why = 'name-only mark' if explicit is WORDMARK else 'no mark on the wiki'
            print('  - %-26s %s' % (key, why))
            missing.append(key)
            continue
        try:
            url = hit['url']
            if hit['name'].lower().endswith('.svg'):
                # MediaWiki rasterises SVGs on demand; Pillow cannot open one.
                url = url.replace('/revision/latest',
                                  '/revision/latest/scale-to-width-down/%d' % (MAX_EDGE * 2))
            raw = urllib.request.urlopen(
                urllib.request.Request(url, headers=UA), timeout=60).read()
            img = process(raw)
        except Exception as exc:
            print('  ! %-26s %s: %s' % (key, hit['name'], exc))
            missing.append(key)
            continue
        path = os.path.join(dest, key + '.png')
        img.save(path, optimize=True)
        size = os.path.getsize(path)
        total += size
        got += 1
        print('  %-26s %-42s %dx%d  %.1fkB' %
              (key, hit['name'][:42], img.width, img.height, size / 1024.0))
        time.sleep(0.1)

    print('')
    print('%d marks in %s  (%.0fkB total)' % (got, dest, total / 1024.0))
    if missing:
        print('no mark for: %s' % ', '.join(missing))
        print('  Not a failure. Either the wiki has no mark for the marque at all, or')
        print('  every mark it has IS the name set as type -- and the panel already')
        print('  prints that name directly above the badge. Both keep the plain plate,')
        print('  the same thing an addon vehicle with no resolvable make gets.')
    print('')
    # NOT optional, and it has to be a SECOND pass rather than part of
    # process(): evening the marks out needs the whole roster measured before
    # any one of them can be scaled, which a per-image function cannot do.
    # Everything written above is cropped hard to its own ink and so is wildly
    # uneven in size -- shipping that is the "Truffade logo is kinda too big"
    # bug. normalize_logos.py reads from tools/logos_raw/ once that exists, so
    # the freshly downloaded marks here become the new originals only on a run
    # where that folder is absent; delete it if you want a re-fetch to reset
    # the baseline.
    print('Now run:  python tools/normalize_logos.py')
    print('    then: python tools/make_makes.py')


if __name__ == '__main__':
    sys.exit(main())
