# -*- coding: utf-8 -*-
"""Generates html/makes.js -- the table that turns a vehicle's make into the
manufacturer mark the vehicle panel draws behind it.

    python tools/fetch_logos.py     # downloads html/logos/*.png
    python tools/make_makes.py      # writes html/makes.js from what is there

Build tooling, like tools/make_masks.py. It is NOT in fxmanifest's files{} and
clients never see it; the shipped outputs are html/makes.js and html/logos/.

The roster is the GTA Wiki's Vehicle Manufacturers page, HD Universe table:
    https://gta.fandom.com/wiki/Vehicle_Manufacturers

The marque named on each row is the real-world brand the wiki's Influence
column gives. It is not used for rendering -- the mark is -- but it is what
/hudbrand puts on the model line while it walks the roster, so "whose badge am
I looking at" is answerable without going and finding one of their cars.
"""
import io
import os
import unicodedata

# (display name, real-world marque it parodies)
MAKES = [
    (u"Albany",        "Cadillac"),
    (u"Annis",         "Nissan / Mazda"),
    (u"Benefactor",    "Mercedes-Benz"),
    (u"BF",            "Volkswagen"),
    (u"Bollokan",      "Hyundai"),
    (u"Bravado",       "Dodge"),
    (u"Brute",         "GMC"),
    (u"Buckingham",    "Learjet / Bell"),
    (u"Canis",         "Jeep"),
    (u"Chariot",       "Federal / Eagle Coach"),
    (u"Cheval",        "Holden"),
    (u"Classique",     "Oldsmobile"),
    (u"Coil",          "Tesla / Rimac"),
    (u"Declasse",      "Chevrolet"),
    (u"Dewbauchee",    "Aston Martin"),
    (u"Dinka",         "Honda"),
    (u"Dundreary",     "Lincoln / Mercury"),
    (u"Eberhard",      "Lockheed Martin"),
    (u"Emperor",       "Lexus"),
    (u"Enus",          "Bentley / Rolls-Royce"),
    (u"Fathom",        "Infiniti"),
    (u"Gallivanter",   "Land Rover"),
    (u"Grotti",        "Ferrari / Fiat"),
    (u"Hijak",         "Fisker"),
    (u"HVY",           "Oshkosh / CAT"),
    (u"Imponte",       "Pontiac"),
    (u"Invetero",      "Corvette"),
    (u"Jack Sheepe",   "John Deere"),
    (u"Jobuilt",       "Peterbilt"),
    (u"Karin",         "Toyota / Subaru"),
    (u"Kraken",        "Triton Submarines"),
    (u"Lampadati",     "Maserati / Lancia"),
    (u"Liberty Chop Shop",   "Orange County Choppers"),
    (u"Liberty City Cycles", "West Coast Choppers"),
    (u"Maibatsu",      "Mitsubishi"),
    (u"Mammoth",       "Hummer / AM General"),
    (u"Maxwell",       "Vauxhall / Opel"),
    (u"MTL",           "Mack Trucks"),
    (u"Nagasaki",      "Kawasaki / Yamaha"),
    (u"Obey",          "Audi"),
    (u"Ocelot",        "Jaguar / Lotus"),
    (u"Överflöd", "Koenigsegg"),
    (u"PED Cycles",    "BMC Switzerland"),
    (u"Pegassi",       "Lamborghini / Pagani"),
    (u"Penaud",        "Renault"),
    (u"Pfister",       "Porsche"),
    (u"Principe",      "Ducati / Piaggio"),
    (u"Progen",        "McLaren"),
    (u"RUNE",          "Lada / Sherp"),
    (u"Schyster",      "Chrysler / AMC"),
    (u"Shitzu",        "Suzuki"),
    (u"Speedophile",   "Sea-Doo"),
    (u"Stanley",       "John Deere / Fordson"),
    (u"Steel Horse",   "American IronHorse"),
    (u"Toundra",       "Alpine"),
    (u"Tri-Cycles",    "Pinarello / De Rosa"),
    (u"Truffade",      "Bugatti"),
    (u"Übermacht", "BMW"),
    (u"Vapid",         "Ford"),
    (u"Vulcar",        "Volvo"),
    (u"Vysser",        "Spyker"),
    (u"Weeny",         "Mini / Morris"),
    (u"Western Company", "Boeing / Sikorsky"),
    (u"Western Motorcycle Company", "Harley-Davidson"),
    (u"Willard",       "Buick"),
    (u"Zirconium",     "Diamond-Star / Saturn"),
]

# Spawn-code makes the prefix passes in makes.js cannot resolve on their own:
# either the eight-character truncation loses a spelling the prefix needs, or
# the token would match two entries and has to be told which one it means.
ALIASES = {
    "GALIVANT":            "GALLIVANTER",
    "WESTMIN":             "WESTERNMOTORCYCLECOMPANY",
    "WESTERNMC":           "WESTERNMOTORCYCLECOMPANY",
    "WESTERN":             "WESTERNCOMPANY",
    "LCC":                 "LIBERTYCITYCYCLES",
    "LCS":                 "LIBERTYCHOPSHOP",
    "PED":                 "PEDCYCLES",
    "JACKSHEE":            "JACKSHEEPE",
    "SPEEDOPH":            "SPEEDOPHILE",
    "BUERGERFAHRZEUG":     "BF",
    "BURGERFAHRZEUG":      "BF",
    "MAIBATSUCORPORATION": "MAIBATSU",
}


def normalise(name):
    n = unicodedata.normalize('NFKD', name)
    n = u''.join(c for c in n if not unicodedata.combining(c))
    return u''.join(c for c in n.upper() if c.isalnum())


def js_str(s):
    """Single-quoted JS string, non-ASCII escaped so the file stays pure ASCII
       and cannot be broken by whatever encoding an editor decides to save."""
    out = [u"'"]
    for c in s:
        if c == u"'":
            out.append(u"\\'")
        elif c == u'\\':
            out.append(u'\\\\')
        elif ord(c) < 128:
            out.append(c)
        else:
            out.append(u'\\u%04x' % ord(c))
    out.append(u"'")
    return u''.join(out)


HEADER = u'''/* Vehicle manufacturers ------------------------------------------------------
 *
 * Turns the make GetMakeNameFromVehicleModel gives Lua into the manufacturer
 * mark the vehicle panel draws behind the make and model. Roster from the GTA
 * Wiki's HD Universe table:
 *   https://gta.fandom.com/wiki/Vehicle_Manufacturers
 *
 * The marks themselves are html/logos/<KEY>.png -- Rockstar's own, flattened to
 * greyscale-plus-alpha and evened out in weight so that sixty-odd badges drawn
 * by different people over fifteen years read as one set behind the same two
 * lines of type. tools/fetch_logos.py does that; see its header for how.
 *
 * A manufacturer with no mark is normal, not an error: two of them have none on
 * the wiki, and plenty of addon vehicles have no resolvable make at all. Both
 * cases render the plain plate the panel had before any of this existed.
 *
 * GENERATED FILE -- do not hand-edit the tables. Change tools/make_makes.py and
 * re-run `python tools/make_makes.py`.
 * -------------------------------------------------------------------------- */
(function (root) {
    'use strict';

    /* key: [display name, mark filename or '', real-world marque]
       The key is the name normalised for matching; the display name is kept
       beside it because normalising is lossy -- "WESTERNMOTORCYCLECOMPANY" is
       not a thing to show anybody. */
    var MAKES = {
'''

BODY = u'''    };

    var ALIASES = {
'''

TAIL = u'''    };

    /* Where the marks live, relative to index.html. One place, so moving them
       is one edit rather than sixty-six. */
    var DIR = 'logos/';

    /* Uppercase, strip accents, drop everything that is not a letter or digit.
       Covers "Ubermacht" against "\\u00dcbermacht", "Western Motorcycle Company"
       against "WesternMotorcycleCompany", and the raw spawn tokens, all at once. */
    function normalise(name) {
        if (!name) return '';
        var s = String(name);
        if (s.normalize) s = s.normalize('NFD').replace(/[\\u0300-\\u036f]/g, '');
        return s.toUpperCase().replace(/[^A-Z0-9]/g, '');
    }

    /* Returns { key, name, logo, marque } or null.

       `logo` is a URL, or '' for a manufacturer the wiki has no mark for --
       which the panel treats exactly like an unknown make. null is the separate
       "this is not a manufacturer I know" answer.

       Exact and alias hits are tried first, so a short key like BF still
       resolves. The two prefix passes are what make truncated spawn tokens
       work, and both are floored at five characters: below that a prefix stops
       being evidence and a three-letter token could land on the wrong marque. */
    function lookup(name) {
        var n = normalise(name);
        if (!n) return null;
        if (ALIASES[n]) n = ALIASES[n];

        var key = MAKES[n] ? n : null;
        var k;

        if (!key && n.length >= 5) {
            /* The token is a truncation of the display name:
               "UBERMACH" -> "UBERMACHT". Shortest match wins, being the least
               of a leap from what we were actually given. */
            for (k in MAKES) {
                if (!MAKES.hasOwnProperty(k)) continue;
                if (k.indexOf(n) === 0 && (key === null || k.length < key.length)) key = k;
            }
        }
        if (!key) {
            /* The other direction: a decorated name that STARTS with a marque,
               e.g. "GrottiClassic". Longest match wins here, so
               "WESTERNMOTORCYCLECOMPANY" is not answered by "WESTERN". */
            for (k in MAKES) {
                if (!MAKES.hasOwnProperty(k)) continue;
                if (k.length >= 5 && n.indexOf(k) === 0 &&
                    (key === null || k.length > key.length)) key = k;
            }
        }
        if (!key) return null;

        var m = MAKES[key];
        return {
            key: key,
            name: m[0],
            logo: m[1] ? DIR + m[1] : '',
            marque: m[2]
        };
    }

    root.VICE_MAKES = {
        makes: MAKES,
        aliases: ALIASES,
        dir: DIR,
        normalise: normalise,
        lookup: lookup
    };
}(typeof window !== 'undefined' ? window : this));
'''


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    logos = os.path.normpath(os.path.join(here, os.pardir, 'html', 'logos'))
    have = set(f[:-4] for f in os.listdir(logos)) if os.path.isdir(logos) else set()

    rows = sorted(((normalise(n), n, m) for n, m in MAKES), key=lambda r: r[0])
    keys = [r[0] for r in rows]
    dupes = sorted(set(k for k in keys if keys.count(k) > 1))
    if dupes:
        raise SystemExit('duplicate keys: %s' % dupes)

    buf = io.StringIO()
    buf.write(HEADER)
    for key, name, marque in rows:
        logo = (key + '.png') if key in have else ''
        buf.write(u"        %-27s [%s, %s, %s],\n" % (
            u"%s:" % js_str(key), js_str(name), js_str(logo), js_str(marque)))
    buf.write(BODY)
    for k in sorted(ALIASES):
        buf.write(u"        %-23s %s,\n" % (u"%s:" % js_str(k), js_str(ALIASES[k])))
    buf.write(TAIL)

    dest = os.path.normpath(os.path.join(here, os.pardir, 'html', 'makes.js'))
    with io.open(dest, 'w', encoding='ascii', newline='\n') as fh:
        fh.write(buf.getvalue())

    marked = sum(1 for k in keys if k in have)
    orphans = sorted(have - set(keys))
    print('wrote %s' % dest)
    print('  %d manufacturers, %d with a mark' % (len(rows), marked))
    for key, name, _ in rows:
        if key not in have:
            print('  no mark: %s' % name)
    if orphans:
        print('  html/logos has files no manufacturer claims: %s' % ', '.join(orphans))


if __name__ == '__main__':
    main()
