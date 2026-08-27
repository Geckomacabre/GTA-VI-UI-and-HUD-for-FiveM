/* -----------------------------------------------------------------------------
   vice_hud glass injector for ox_lib popups  (added by vice_hud; safe to delete)
   -----------------------------------------------------------------------------
   Two jobs:

   1. Receive the theme from Lua (vice_theme.lua sends `viceTheme`) and write it
      onto :root as CSS custom properties, so /hudtheme recolours every popup
      live with nothing rebuilt.

   2. Tag popup surfaces with .vice-surface so vice-glass.css has something to
      target.

   WHY (2) IS NEEDED
   ox_lib's UI is Mantine styled through emotion. The class names that reach the
   DOM are build-specific hashes, not `mantine-Paper-root`, so there is no
   stable selector to write in the stylesheet. Rather than guess at hashes that
   change on every rebuild, this finds surfaces by what they ARE: an element
   that paints its own opaque-ish background and is the outermost such element
   in a portal. That test holds regardless of how the bundle was built.

   This never removes or rewrites ox_lib's own styles -- it only adds a class.
   If the heuristic misses something the popup simply keeps its stock look.
   -------------------------------------------------------------------------- */
(function () {
    'use strict';

    var root = document.documentElement;

    /* ---- theme -------------------------------------------------------- */

    var VARS = {
        // The MAP PANEL plate. vice-glass.css carries the .slot recipe now, not
        // the .glass one, so these are the keys that actually paint a popup --
        // the tint/rim/spec trio below is left mapped only so a theme that
        // still sends them does not error, and so switching the stylesheet back
        // needs no change here.
        plate: '--vice-plate',
        plateEdge: '--vice-plate-edge',
        plateTopLit: '--vice-plate-toplit',
        tint: '--vice-tint',
        rim: '--vice-rim',
        spec: '--vice-spec',
        fill: '--vice-fill',
        fillHi: '--vice-fill-hi',
        line: '--vice-line',
        text: '--vice-text',
        textDim: '--vice-text-dim',
        accent: '--vice-accent',
        success: '--vice-success',
        error: '--vice-error',
        inform: '--vice-inform'
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

        // Separate switches so each can be turned off on its own: the glass
        // material, the accent colours and the display font are three different
        // opinions and /hudtheme exposes them as three different rows.
        root.setAttribute('data-vice-glass', t.glass === false ? '0' : '1');
        root.setAttribute('data-vice-font', t.font === false ? '0' : '1');
        root.setAttribute('data-vice-accent', '1');
    }

    window.addEventListener('message', function (event) {
        var data = event.data;
        if (!data || data.action !== 'viceTheme') return;
        applyTheme(data.data);
    });

    /* ---- surface tagging ----------------------------------------------- */

    // An element counts as a surface when it paints a background of its own
    // that is not effectively see-through. Mantine's Paper, Modal and
    // Notification all do; the layout divs between them do not.
    function paintsBackground(el) {
        var bg = getComputedStyle(el).backgroundColor;
        if (!bg || bg === 'transparent') return false;

        var m = bg.match(/^rgba?\(([^)]+)\)$/);
        if (!m) return false;

        var parts = m[1].split(',');
        // rgb() with no alpha component is fully opaque.
        if (parts.length < 4) return true;

        return parseFloat(parts[3]) > 0.25;
    }

    // Never a surface, whatever they are painted:
    //   html/body/#root  are the page, not a popup. Tagging one of them makes
    //     every real popup a NESTED surface and they all get the flat fill
    //     instead of the glass -- which is exactly what happened the first time
    //     this was tested against a page with an opaque body.
    //   .toast-*         are ox_lib's own accent stripes on a notification.
    //     They are coloured by type, and tagging them lets the nested-surface
    //     rule overwrite that colour.
    function neverSurface(el) {
        if (el === document.body || el === root) return true;
        if (el.id === 'root') return true;

        var cls = el.classList;
        if (!cls) return false;

        for (var i = 0; i < cls.length; i++) {
            if (cls[i].indexOf('toast-') === 0) return true;
        }

        return false;
    }

    // Tag only the OUTERMOST painted element in a subtree. Tagging a surface
    // inside a surface is handled by CSS (nested panels get the flat fill), but
    // that only works if the nesting is real rather than an artefact of us
    // tagging every painted div on the way down.
    function tagSubtree(node) {
        if (!node || node.nodeType !== 1) return;

        var stack = [node];

        while (stack.length) {
            var el = stack.pop();

            if (el.classList && el.classList.contains('vice-surface')) continue;

            if (!neverSurface(el) && paintsBackground(el)) {
                el.classList.add('vice-surface');
                // Do not descend: anything below is content on this surface.
                continue;
            }

            for (var i = 0; i < el.children.length; i++) {
                stack.push(el.children[i]);
            }
        }
    }

    // Mantine renders popups into portals appended to <body>, and re-renders
    // them on every open. One observer on body catches all of it.
    var observer = new MutationObserver(function (mutations) {
        for (var i = 0; i < mutations.length; i++) {
            var added = mutations[i].addedNodes;
            for (var j = 0; j < added.length; j++) {
                tagSubtree(added[j]);
            }
        }
    });

    function start() {
        observer.observe(document.body, { childList: true, subtree: true });
        // Anything already on the page when this runs.
        tagSubtree(document.body);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start);
    } else {
        start();
    }
})();
