/* -----------------------------------------------------------------------------
   vice_hud theme receiver for ox_target   (added by vice_hud; safe to delete)
   -----------------------------------------------------------------------------
   Receives the theme from client/vice_theme.lua and writes it onto :root as CSS
   custom properties, so /hudtheme recolours the target menu live with nothing
   rebuilt or restarted.

   This is the theme half of ox_lib's vice-glass.js and NOT the tagging half:
   ox_target's page has stable class names, so vice-theme.css targets them
   directly and there is nothing to discover at runtime. See the comment at the
   top of that file.

   ox_target's own main.js switches on `event.data.event`; this listens for
   `event.data.action`, so neither script sees the other's messages and the
   order the two listeners run in does not matter.
   -------------------------------------------------------------------------- */
(function () {
    'use strict';

    var root = document.documentElement;

    var VARS = {
        // The map-panel plate. ox_target is built out of .slot, the
        // material the zone bar and vehicle panel are made of -- not the
        // .glass ox_lib's popups use -- so the glass keys are not read here.
        plate: '--vice-plate',
        plateEdge: '--vice-plate-edge',
        plateTopLit: '--vice-plate-toplit',
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
        // ox_lib's attribute names so one stylesheet idiom covers both pages.
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
