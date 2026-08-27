/* Vehicle manufacturers ------------------------------------------------------
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
        'ALBANY':                   ['Albany', 'ALBANY.png', 'Cadillac'],
        'ANNIS':                    ['Annis', 'ANNIS.png', 'Nissan / Mazda'],
        'BENEFACTOR':               ['Benefactor', 'BENEFACTOR.png', 'Mercedes-Benz'],
        'BF':                       ['BF', '', 'Volkswagen'],
        'BOLLOKAN':                 ['Bollokan', 'BOLLOKAN.png', 'Hyundai'],
        'BRAVADO':                  ['Bravado', 'BRAVADO.png', 'Dodge'],
        'BRUTE':                    ['Brute', 'BRUTE.png', 'GMC'],
        'BUCKINGHAM':               ['Buckingham', 'BUCKINGHAM.png', 'Learjet / Bell'],
        'CANIS':                    ['Canis', 'CANIS.png', 'Jeep'],
        'CHARIOT':                  ['Chariot', 'CHARIOT.png', 'Federal / Eagle Coach'],
        'CHEVAL':                   ['Cheval', 'CHEVAL.png', 'Holden'],
        'CLASSIQUE':                ['Classique', 'CLASSIQUE.png', 'Oldsmobile'],
        'COIL':                     ['Coil', 'COIL.png', 'Tesla / Rimac'],
        'DECLASSE':                 ['Declasse', 'DECLASSE.png', 'Chevrolet'],
        'DEWBAUCHEE':               ['Dewbauchee', 'DEWBAUCHEE.png', 'Aston Martin'],
        'DINKA':                    ['Dinka', 'DINKA.png', 'Honda'],
        'DUNDREARY':                ['Dundreary', 'DUNDREARY.png', 'Lincoln / Mercury'],
        'EBERHARD':                 ['Eberhard', 'EBERHARD.png', 'Lockheed Martin'],
        'EMPEROR':                  ['Emperor', 'EMPEROR.png', 'Lexus'],
        'ENUS':                     ['Enus', 'ENUS.png', 'Bentley / Rolls-Royce'],
        'FATHOM':                   ['Fathom', 'FATHOM.png', 'Infiniti'],
        'GALLIVANTER':              ['Gallivanter', 'GALLIVANTER.png', 'Land Rover'],
        'GROTTI':                   ['Grotti', 'GROTTI.png', 'Ferrari / Fiat'],
        'HIJAK':                    ['Hijak', 'HIJAK.png', 'Fisker'],
        'HVY':                      ['HVY', '', 'Oshkosh / CAT'],
        'IMPONTE':                  ['Imponte', 'IMPONTE.png', 'Pontiac'],
        'INVETERO':                 ['Invetero', 'INVETERO.png', 'Corvette'],
        'JACKSHEEPE':               ['Jack Sheepe', 'JACKSHEEPE.png', 'John Deere'],
        'JOBUILT':                  ['Jobuilt', 'JOBUILT.png', 'Peterbilt'],
        'KARIN':                    ['Karin', 'KARIN.png', 'Toyota / Subaru'],
        'KRAKEN':                   ['Kraken', 'KRAKEN.png', 'Triton Submarines'],
        'LAMPADATI':                ['Lampadati', 'LAMPADATI.png', 'Maserati / Lancia'],
        'LIBERTYCHOPSHOP':          ['Liberty Chop Shop', '', 'Orange County Choppers'],
        'LIBERTYCITYCYCLES':        ['Liberty City Cycles', '', 'West Coast Choppers'],
        'MAIBATSU':                 ['Maibatsu', 'MAIBATSU.png', 'Mitsubishi'],
        'MAMMOTH':                  ['Mammoth', 'MAMMOTH.png', 'Hummer / AM General'],
        'MAXWELL':                  ['Maxwell', 'MAXWELL.png', 'Vauxhall / Opel'],
        'MTL':                      ['MTL', '', 'Mack Trucks'],
        'NAGASAKI':                 ['Nagasaki', 'NAGASAKI.png', 'Kawasaki / Yamaha'],
        'OBEY':                     ['Obey', 'OBEY.png', 'Audi'],
        'OCELOT':                   ['Ocelot', 'OCELOT.png', 'Jaguar / Lotus'],
        'OVERFLOD':                 ['\u00d6verfl\u00f6d', 'OVERFLOD.png', 'Koenigsegg'],
        'PEDCYCLES':                ['PED Cycles', '', 'BMC Switzerland'],
        'PEGASSI':                  ['Pegassi', '', 'Lamborghini / Pagani'],
        'PENAUD':                   ['Penaud', 'PENAUD.png', 'Renault'],
        'PFISTER':                  ['Pfister', 'PFISTER.png', 'Porsche'],
        'PRINCIPE':                 ['Principe', '', 'Ducati / Piaggio'],
        'PROGEN':                   ['Progen', '', 'McLaren'],
        'RUNE':                     ['RUNE', 'RUNE.png', 'Lada / Sherp'],
        'SCHYSTER':                 ['Schyster', 'SCHYSTER.png', 'Chrysler / AMC'],
        'SHITZU':                   ['Shitzu', 'SHITZU.png', 'Suzuki'],
        'SPEEDOPHILE':              ['Speedophile', 'SPEEDOPHILE.png', 'Sea-Doo'],
        'STANLEY':                  ['Stanley', '', 'John Deere / Fordson'],
        'STEELHORSE':               ['Steel Horse', 'STEELHORSE.png', 'American IronHorse'],
        'TOUNDRA':                  ['Toundra', '', 'Alpine'],
        'TRICYCLES':                ['Tri-Cycles', '', 'Pinarello / De Rosa'],
        'TRUFFADE':                 ['Truffade', 'TRUFFADE.png', 'Bugatti'],
        'UBERMACHT':                ['\u00dcbermacht', 'UBERMACHT.png', 'BMW'],
        'VAPID':                    ['Vapid', '', 'Ford'],
        'VULCAR':                   ['Vulcar', 'VULCAR.png', 'Volvo'],
        'VYSSER':                   ['Vysser', '', 'Spyker'],
        'WEENY':                    ['Weeny', 'WEENY.png', 'Mini / Morris'],
        'WESTERNCOMPANY':           ['Western Company', '', 'Boeing / Sikorsky'],
        'WESTERNMOTORCYCLECOMPANY': ['Western Motorcycle Company', 'WESTERNMOTORCYCLECOMPANY.png', 'Harley-Davidson'],
        'WILLARD':                  ['Willard', 'WILLARD.png', 'Buick'],
        'ZIRCONIUM':                ['Zirconium', 'ZIRCONIUM.png', 'Diamond-Star / Saturn'],
    };

    var ALIASES = {
        'BUERGERFAHRZEUG':      'BF',
        'BURGERFAHRZEUG':       'BF',
        'GALIVANT':             'GALLIVANTER',
        'JACKSHEE':             'JACKSHEEPE',
        'LCC':                  'LIBERTYCITYCYCLES',
        'LCS':                  'LIBERTYCHOPSHOP',
        'MAIBATSUCORPORATION':  'MAIBATSU',
        'PED':                  'PEDCYCLES',
        'SPEEDOPH':             'SPEEDOPHILE',
        'WESTERN':              'WESTERNCOMPANY',
        'WESTERNMC':            'WESTERNMOTORCYCLECOMPANY',
        'WESTMIN':              'WESTERNMOTORCYCLECOMPANY',
    };

    /* Where the marks live, relative to index.html. One place, so moving them
       is one edit rather than sixty-six. */
    var DIR = 'logos/';

    /* Uppercase, strip accents, drop everything that is not a letter or digit.
       Covers "Ubermacht" against "\u00dcbermacht", "Western Motorcycle Company"
       against "WesternMotorcycleCompany", and the raw spawn tokens, all at once. */
    function normalise(name) {
        if (!name) return '';
        var s = String(name);
        if (s.normalize) s = s.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
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
