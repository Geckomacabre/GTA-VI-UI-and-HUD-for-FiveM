/* -----------------------------------------------------------------------------
   qbx_relog character switcher -- NUI side
   -----------------------------------------------------------------------------
   Display only. The page never takes NUI focus and never sends a callback: the
   player is holding a key and cycling with the mouse, and taking focus would
   both swallow the key-up and turn the mouse into a cursor. All of the input
   lives in client/wheel.lua, which sends `select` when the highlight moves.

   Messages:
     open    { characters: [{ id, name, sub, initials, current, honor... }],
               margin, key }
     capture { id, txd }        copy this pedheadshot before Lua unregisters it
     forget  { id }             drop a stored portrait so it gets rebuilt
     select  { index }          1-based, or 0 for nothing selected
     close   {}
     viceTheme { data }         same payload every other vice_hud consumer gets

   PORTRAITS LIVE HERE, not in Lua. REGISTER_PEDHEADSHOT_TRANSPARENT has exactly
   one texture slot in the whole engine (citizenfx/fivem#2611), so Lua can only
   borrow it for one character at a time and must unregister before building the
   next. This page therefore copies each texture into a blob it owns, keyed by
   citizenid, and answers the `captured` callback to say when it is safe to let
   the slot go. Hold that callback back and the texture is recycled mid-fetch;
   skip the copy and every character after the first has no face.
   -------------------------------------------------------------------------- */
(function () {
    'use strict';

    var root = document.documentElement;
    var panel = document.getElementById('switcher');
    var cards = document.getElementById('cards');
    var promptEl = document.getElementById('prompt');
    var nameEl = document.getElementById('name');
    var subEl = document.getElementById('sub');
    var hintEl = document.getElementById('hint');

    var rows = [];
    var characters = [];
    var selected = 0;

    // citizenid -> blob: URL of that character's portrait. Survives the strip
    // closing and reopening; only `forget` clears an entry.
    var portraits = {};

    // --- portraits -----------------------------------------------------------

    /* A pedheadshot renders straight from the game's texture memory. The txd and
       the texture inside it share a name, hence the doubled path. */
    function faceUrl(txd) {
        return 'https://nui-img/' + txd + '/' + txd;
    }

    function tellLua(id, ok) {
        fetch('https://' + GetParentResourceName() + '/captured', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({ id: id, ok: ok })
        }).catch(function () { /* the strip still works without the reply */ });
    }

    /* Copy the texture out of the engine and into a blob this page owns, then
       release Lua to unregister the slot. Everything after this point reads the
       blob, so the portrait no longer depends on the headshot existing. */
    function capture(id, txd) {
        if (!id || !txd) { tellLua(id, false); return; }

        fetch(faceUrl(txd))
            .then(function (r) {
                if (!r.ok) throw new Error('nui-img ' + r.status);
                return r.blob();
            })
            .then(function (blob) {
                if (portraits[id]) URL.revokeObjectURL(portraits[id]);
                portraits[id] = URL.createObjectURL(blob);
                paintFaces();
                tellLua(id, true);
            })
            .catch(function () {
                tellLua(id, false);
            });
    }

    function forget(id) {
        if (portraits[id]) {
            URL.revokeObjectURL(portraits[id]);
            delete portraits[id];
        }
    }

    /* Portraits are built in the background, so a card can open on its initials
       and gain a face part way through. */
    function paintFaces() {
        for (var i = 0; i < rows.length; i++) {
            var url = portraits[characters[i] && characters[i].id];
            if (!url || rows[i].face.dataset.url === url) continue;

            rows[i].face.dataset.url = url;
            rows[i].face.src = url;
            rows[i].face.hidden = false;
            rows[i].initials.hidden = true;
        }
    }

    /* qbx_honor's standing, as a chip under the portrait: the angel/devil face
       for anyone who has reached a tier, and the number always -- two neutral
       characters with no badge would otherwise be indistinguishable, and the
       point of showing honor here is comparing characters. */
    function buildHonor(character) {
        var honor = document.createElement('div');
        honor.className = 'honor'
            + (character.honorTier ? ' ' + character.honorTier : '')
            + (character.honorBroken ? ' broken' : '');

        var emoji = document.createElement('span');
        emoji.className = 'honor-emoji';
        emoji.textContent = character.honorEmoji || '';
        emoji.hidden = !character.honorEmoji;

        var value = document.createElement('span');
        value.className = 'honor-value';
        // Explicit sign on the positive side: this is an axis with two
        // directions, and "40" alone doesn't say which one it went.
        var n = typeof character.honor === 'number' ? character.honor : 0;
        value.textContent = (n > 0 ? '+' : '') + n;

        honor.appendChild(emoji);
        honor.appendChild(value);
        return honor;
    }

    function buildCard(character) {
        var slot = document.createElement('div');
        slot.className = 'slot' + (character.current ? ' current' : '');

        var card = document.createElement('div');
        card.className = 'card';

        var initials = document.createElement('div');
        initials.className = 'initials';
        initials.textContent = character.initials || '?';

        var face = document.createElement('img');
        face.className = 'face';
        face.hidden = true;
        // A texture that vanished (headshot unregistered mid-open) must not
        // leave a broken-image glyph in the card.
        face.addEventListener('error', function () {
            face.hidden = true;
            initials.hidden = false;
        });

        var url = portraits[character.id];
        if (url) {
            face.dataset.url = url;
            face.src = url;
            face.hidden = false;
            initials.hidden = true;
        }

        var bar = document.createElement('div');
        bar.className = 'bar';

        card.appendChild(initials);
        card.appendChild(face);
        card.appendChild(bar);

        slot.appendChild(card);
        slot.appendChild(buildHonor(character));

        return { el: slot, face: face, initials: initials };
    }

    function open(list, key) {
        cards.textContent = '';
        rows = [];
        characters = list || [];
        selected = 0;

        if (!characters.length) return;

        promptEl.textContent = key || 'B';

        for (var i = 0; i < characters.length; i++) {
            var built = buildCard(characters[i]);
            rows.push(built);
            cards.appendChild(built.el);
        }

        nameEl.hidden = true;
        subEl.hidden = true;
        hintEl.hidden = false;
        panel.hidden = false;
    }

    function select(index) {
        if (index === selected) return;

        if (rows[selected - 1]) rows[selected - 1].el.classList.remove('on');
        if (rows[index - 1]) rows[index - 1].el.classList.add('on');

        selected = index;

        var character = characters[index - 1];
        if (character) {
            nameEl.textContent = character.name || '';
            nameEl.hidden = false;
            subEl.textContent = character.sub || '';
            subEl.hidden = !character.sub;
            hintEl.hidden = true;
        } else {
            nameEl.hidden = true;
            subEl.hidden = true;
            hintEl.hidden = false;
        }
    }

    function close() {
        panel.hidden = true;
        cards.textContent = '';
        rows = [];
        characters = [];
        selected = 0;
    }

    // --- theme ---------------------------------------------------------------

    /* Identical to the receiver in qb-menu and ox_target, down to the attribute
       names, so one /hudtheme push is shaped the same for every page that
       reads it. */
    var VARS = {
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

        root.setAttribute('data-vice-glass', t.glass === false ? '0' : '1');
        root.setAttribute('data-vice-font', t.font === false ? '0' : '1');
        root.setAttribute('data-vice-accent', '1');
    }

    function applyPlacement(margin) {
        if (!margin) return;
        if (typeof margin.right === 'number') {
            root.style.setProperty('--edge-right', margin.right + 'cqw');
        }
        if (typeof margin.bottom === 'number') {
            root.style.setProperty('--edge-bottom', margin.bottom + 'cqh');
        }
    }

    // --- wiring --------------------------------------------------------------

    window.addEventListener('message', function (event) {
        var data = event.data;
        if (!data) return;

        switch (data.action) {
            case 'open':
                applyPlacement(data.margin);
                open(data.characters, data.key);
                break;
            case 'capture':
                capture(data.id, data.txd);
                break;
            case 'forget':
                forget(data.id);
                break;
            case 'select':
                select(data.index || 0);
                break;
            case 'close':
                close();
                break;
            case 'viceTheme':
                applyTheme(data.data);
                break;
        }
    });
})();
