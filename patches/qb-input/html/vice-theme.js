/* -----------------------------------------------------------------------------
   vice_hud theme receiver for qb-input   (added by vice_hud; safe to delete)
   -----------------------------------------------------------------------------
   Receives the theme from client/vice_theme.lua and writes it onto :root as CSS
   custom properties, so /hudtheme recolours this menu live with nothing rebuilt
   or restarted. vice-theme.css does the rest.

   This is the theme half of ox_lib's vice-glass.js and NOT the tagging half:
   qb-input's page has stable, hand-written class names, so the stylesheet
   targets them directly and there is nothing to discover at runtime.

   qb-input's own script.js switches on `event.data.action` and returns on an
   unrecognised one, so `viceTheme` falls through its switch harmlessly. It is
   not a new key on a shared channel -- it is the same key ox_lib and ox_target
   already listen for, which is what keeps one /hudtheme push shaped the same
   for every page that reads it.
   -------------------------------------------------------------------------- */
(function () {
    'use strict';

    var root = document.documentElement;

    var VARS = {
        // The map-panel plate -- .slot, not .glass. See vice-theme.css.
        plate: '--vice-plate',
        plateEdge: '--vice-plate-edge',
        plateTopLit: '--vice-plate-toplit',
        plateBand: '--vice-plate-band',
        plateBarrier: '--vice-plate-barrier',
        line: '--vice-line',
        text: '--vice-text',
        textDim: '--vice-text-dim',
        accent: '--vice-accent'
    };

    function applyTheme(t) {
        if (!t || typeof t !== 'object') return;

        for (var key in VARS) {
            if (typeof t[key] === 'string' && t[key]) {
                root.style.setProperty(VARS[key], t[key]);
            }
        }

        if (typeof t.radius === 'number') {
            root.style.setProperty('--vice-radius', t.radius + 'px');
        }

        // Three separate switches because the glass material, the accent
        // colours and the display font are three different opinions, and
        // /hudtheme exposes them as three different rows. Kept identical to
        // ox_lib's attribute names so one stylesheet idiom covers every page.
        root.setAttribute('data-vice-glass', t.glass === false ? '0' : '1');
        root.setAttribute('data-vice-font', t.font === false ? '0' : '1');
        root.setAttribute('data-vice-accent', '1');
    }

    window.addEventListener('message', function (event) {
        var data = event.data;
        if (!data || data.action !== 'viceTheme') return;
        applyTheme(data.data);
    });
})();
