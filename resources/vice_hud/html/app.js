/* =============================================================================
   vice_hud NUI
   -----------------------------------------------------------------------------
   Receives messages from client.lua and updates the DOM. No framework, no build
   step — what is on disk is what runs, so there is no way for a stale bundle to
   silently ship.

   Every handler is defensive about missing fields: client.lua may extend the
   payloads later, and a missing key must never throw and take the whole HUD out.
   ========================================================================== */
(function () {
    'use strict';

    var $ = function (id) { return document.getElementById(id); };
    var stage = $('stage');

    /* --- helpers --------------------------------------------------------- */

    function show(el, visible) {
        if (!el) return;
        el.classList.toggle('hidden', !visible);
    }

    function setFill(rowId, value) {
        var row = $(rowId);
        if (!row) return;
        var fill = row.querySelector('.sfill');
        if (fill) {
            // Set the transform DIRECTLY. Driving it through a custom property
            // silently froze the bar: a transition on a property whose value
            // comes from an unregistered var() never re-evaluates when that var
            // changes, so --fill updated while the rendered transform stayed put.
            var pct = Math.max(0, Math.min(100, value || 0));
            fill.style.transform = 'scaleX(' + (pct / 100).toFixed(4) + ')';
        }
    }

    /* Auto-hide with anti-flicker: showing is immediate, hiding is deferred.
       Values arrive from a poll and oscillate on their thresholds during normal
       play (health regenerating 99<->100, stamina ticking back up), which
       without this hold would strobe the bars on and off. */
    var HIDE_HOLD_MS = 1200;
    var hideTimers = {};

    function setVisible(key, el, shouldShow) {
        if (!el) return;
        if (shouldShow) {
            if (hideTimers[key]) { clearTimeout(hideTimers[key]); delete hideTimers[key]; }
            show(el, true);
        } else if (!hideTimers[key] && !el.classList.contains('hidden')) {
            hideTimers[key] = setTimeout(function () {
                delete hideTimers[key];
                show(el, false);
            }, HIDE_HOLD_MS);
        }
    }

    /* --- status bars ----------------------------------------------------- */

    /* The stamina row doubles as the OXYGEN row while the player is underwater.
       They are mutually exclusive in practice -- sprinting or submerged, never
       both in a way you must read at once -- so one track carries both, and a
       fourth permanent bar never has to appear in a corner whose whole design
       is to be empty when nothing is wrong.

       The presence of `oxygen` in the payload IS the mode switch: one value
       decides the state, so there is nothing for two flags to disagree about. */
    var OXYGEN_GLYPH = '○';   // a bubble; the stamina glyph is a bolt
    var staminaGlyph = null;       // read off the markup, so it lives in one place

    function setStaminaMode(row, submerged) {
        if (!row) return;
        row.classList.toggle('oxygen', submerged);
        var ic = row.querySelector('.sic');
        if (!ic) return;
        // Captured before the first swap, so it is always the markup's glyph
        // even if the very first payload arrives while underwater.
        if (staminaGlyph === null) staminaGlyph = ic.textContent;
        var want = submerged ? OXYGEN_GLYPH : staminaGlyph;
        if (ic.textContent !== want) ic.textContent = want;
    }

    /* Health used to show continuously whenever it was below 100 -- which in
       practice meant almost always, since a scratch of chip damage sits there
       for minutes with nothing else to clear it, unlike stamina/focus which
       mostly return to full within a second or two of letting off the key.
       So this now reveals on an actual CHANGE (a hit or a heal) and holds for
       HEALTH_FLASH_MS, the same "a STATE is not a LEVEL" fix already applied
       to the vehicle lock pip -- see vice-hud-nav-popup memory. `null` on the
       first payload so a fresh page load does not treat "no history yet" as
       a change. */
    var HEALTH_FLASH_MS = 3000;
    var lastHealthVal = null;
    var healthFlashTimer = null;
    var healthRecentlyChanged = false;

    function onStatus(d) {
        var health = d.health == null ? 100 : d.health;
        var focus = d.focus == null ? 100 : d.focus;
        var focusActive = !!d.focusActive;
        var stamina = d.stamina == null ? 100 : d.stamina;
        var oxygen = d.oxygen == null ? null : d.oxygen;
        var submerged = oxygen !== null;
        var staminaRow = $('s-stamina');
        var focusRow = $('s-focus');
        var wheelOpen = !!d.wheel;

        var cap = d.cap == null ? null : d.cap;
        // Two different things share `cap`/`capCause`: a hunger/thirst warning
        // ("you're hungry enough that a future heal would be capped, even
        // though you're at full health right now") and the separate flat
        // regen ceiling (Config.Needs.regenCeilingPct -- "you're just still
        // hurt, below the point passive regen tops out at"). Only the FIRST
        // is worth force-showing unconditionally: it is the one case that can
        // fire at 100% health, where nothing else would reveal the row. The
        // ceiling case can only ever be active while health is already below
        // it, so ordinary damage there is exactly what healthRecentlyChanged
        // already reveals -- force-showing it too meant the row stayed up
        // continuously any time health sat under 62%, full belly or not,
        // which is the same "always visible" bug being fixed here, just
        // reached through the cap instead of the raw health value.
        var needsWarning = cap != null && (d.capCause === 'hunger' || d.capCause === 'thirst');

        if (lastHealthVal !== null && health !== lastHealthVal) {
            healthRecentlyChanged = true;
            if (healthFlashTimer) clearTimeout(healthFlashTimer);
            healthFlashTimer = setTimeout(function () {
                healthFlashTimer = null;
                healthRecentlyChanged = false;
            }, HEALTH_FLASH_MS);
        }
        lastHealthVal = health;

        setFill('s-health', health);
        setFill('s-focus', focus);
        if (focusRow) focusRow.classList.toggle('active', focusActive);
        var focusFx = $('focus-fx');
        if (focusFx) focusFx.classList.toggle('active', focusActive);
        // Mode before fill: the class carries the colour, and setting it first
        // means the swap and the new value land in the same frame rather than
        // showing one tick of oxygen drawn in the stamina colour.
        setStaminaMode(staminaRow, submerged);
        setFill('s-stamina', submerged ? oxygen : stamina);

        // Nominal state is an empty top-left corner, matching the reference.
        // Shown on a recent change (a hit or a heal), while the weapon/item
        // wheel is open (Tab -- client.lua reads the control directly, so
        // this works regardless of which inventory owns the wheel), or while
        // a hunger/thirst cap is in effect: full health you cannot heal back
        // into is worth knowing before something takes a bite out of it, and
        // that one is a standing condition rather than a one-off event, so it
        // is not gated on "recently changed". The flat regen-ceiling cap
        // (capCause 'health') is deliberately NOT in this condition -- see
        // needsWarning above for why.
        setVisible('health', $('s-health'), healthRecentlyChanged || wheelOpen || needsWarning);
        // Focus is nominal at FULL (the opposite of armour's nominal-at-zero),
        // so it shows whenever it's spent at all, or actively draining.
        setVisible('focus', focusRow, focusActive || focus < 100);
        // Underwater the row shows unconditionally: full breath still means a
        // clock is running, and that is exactly when you want to see it. The
        // shared hide-hold then carries it a beat past surfacing, so a dive
        // that ends with low stamina slides into the stamina bar instead of
        // blinking out and back.
        setVisible('stamina', staminaRow, submerged || stamina < 100);
    }

    /* --- wanted ---------------------------------------------------------- */

    var STAR_PATH = 'M50 5 L61 38 L96 38 L68 59 L79 92 L50 71 L21 92 L32 59 L4 38 L39 38 Z';
    /* The "tells" are red ROUNDED SQUARES with white line-art, measured off the
       original reference at ~0.88% of width by ~1.94% of height — not emoji in
       circles. Drawn as inline SVG so they stay crisp and match the reference
       weight.

       A LATER reference frame showed five of these instead of the original
       three, and different ones: camera, a medical cross, a hanger, a person
       silhouette, and a flag — not the outfit/voice/vehicle set this row
       shipped with first. Renamed here to match; see getWantedTells() in
       client.lua for what each one is actually driven by, since none of them
       carry the same meaning as before:
         hanger  — was 'outfit', same glyph, same fenix-police signal
         person  — was 'voice'; fenix-police has no separate "physical
                   description" concept, so this reuses that signal under the
                   new icon rather than inventing a second one
         medical — new: vice_hud's own reading of the player's health, not
                   from fenix-police at all
         camera, flag — new, no detection wired yet; see
                   exports.vice_hud:SetWantedTellOverride
       The old 'vehicle' tell has no icon in the five-icon set and is simply
       not drawn any more — the underlying fenix-police signal is untouched. */
    var TELL_SVG = {
        hanger:
            '<svg viewBox="0 0 24 24"><path d="M12 3.2a1.9 1.9 0 1 0 1.35 3.24c.2.5.06.9-.4 1.2' +
            'L3.4 14.1a1.35 1.35 0 0 0 .78 2.45h15.64a1.35 1.35 0 0 0 .78-2.45l-8.2-5.3"/></svg>',
        person:
            '<svg viewBox="0 0 24 24"><circle cx="12" cy="7.2" r="3.3"/>' +
            '<path d="M4.7 20.4c0-4.3 3.3-6.9 7.3-6.9s7.3 2.6 7.3 6.9"/></svg>',
        medical:
            '<svg viewBox="0 0 24 24"><path d="M10 3.6h4v6.4h6.4v4H14v6.4h-4v-6.4H3.6v-4H10z" ' +
            'fill="#fff" stroke="none"/></svg>',
        camera:
            '<svg viewBox="0 0 24 24"><path d="M3.6 8.2a1.6 1.6 0 0 1 1.6-1.6h2l1.1-1.7a1.6 1.6 0 0 1 1.35-.7h4.7' +
            'a1.6 1.6 0 0 1 1.35.7l1.1 1.7h2a1.6 1.6 0 0 1 1.6 1.6v9a1.6 1.6 0 0 1-1.6 1.6H5.2a1.6 1.6 0 0 1-1.6-1.6z"/>' +
            '<circle cx="12" cy="13" r="3"/></svg>',
        flag:
            '<svg viewBox="0 0 24 24"><path d="M5.4 21V3.4"/>' +
            '<path d="M5.4 4.2h12.4l-3 3.6 3 3.6H5.4" fill="#fff" stroke="none"/></svg>'
    };

    /* Four star states, matching the reference frames exactly, all literal
       colours (client.lua's wantedState() decides which one applies, see
       the comment there for what each actually means):
         contact   solid white fill, static, they can see you right now.
         searching flashes between hollow and white fill, lost you, still
                   hunting.
         hollow    outline only, static, brighter than an unearned star but
                   never filled, reported, nobody's found you yet.
         red       solid red fill, static, shaken them, still in the zone.
       `filled` is how many stars the level has earned; `state` decides how
       those earned stars render. None of this is the pink/teal character
       accent, that's the waypoint/nav bar's own thing, not the stars'. */
    function renderStars(container, filled, total, state) {
        if (!container) return;
        container.innerHTML = '';
        for (var i = 0; i < total; i++) {
            var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
            svg.setAttribute('viewBox', '0 0 100 100');
            var cls = 'star';
            // Filled from the RIGHT: the reference lights the rightmost star
            // first and fills leftward, so a single star sits at the right end
            // of the row rather than the left.
            if (i >= total - filled && state) cls += ' ' + state;
            svg.setAttribute('class', cls);
            var p = document.createElementNS('http://www.w3.org/2000/svg', 'path');
            p.setAttribute('d', STAR_PATH);
            svg.appendChild(p);
            container.appendChild(svg);
        }
    }

    function renderTells(container, tells) {
        if (!container) return;
        container.innerHTML = '';
        (tells || []).forEach(function (t) {
            var d = document.createElement('div');
            d.className = 'tell';
            d.title = t;
            d.innerHTML = TELL_SVG[t] || '';
            container.appendChild(d);
        });
    }

    /* The notification says a different thing per state, because each one
       means something different to the player (see renderStars' comment).
       The box's own star mirrors the corner row so the two never disagree. */
    var WANTED_COPY = {
        contact:   'The cops are searching for you<br>and they have your description',
        searching: 'The police are searching the area<br>for a suspect',
        hollow:    'A crime has been reported<br>police are looking into it',
        red:       'You\'ve lost them, but stay sharp<br>you\'re still in the search area'
    };

    function onWanted(d) {
        var stars = d.stars || 0;
        var maxStars = d.maxStars || 6;
        var state = d.state || null;
        renderStars($('stars'), stars, stars > 0 ? maxStars : 0, state);

        var copy = $('wanted-copy');
        if (copy) copy.innerHTML = WANTED_COPY[state] || WANTED_COPY.hollow;
        // Same class renderStars uses, so it matches the corner row exactly.
        var wstar = $('wanted-star');
        if (wstar) wstar.setAttribute('class', 'star' + (state ? ' ' + state : ''));

        // The three "tells" (outfit / voice / vehicle) track independently of the
        // notification box — the reference shows them top-right under the stars
        // as well as inside the box.
        var tells = d.tells || [];
        show($('tells'), stars > 0 && tells.length > 0);
        renderTells($('tells'), tells);
        renderTells($('wanted-tells'), tells);

        setVisible('wanted', $('wanted'), !!d.active);
    }

    /* --- money / weapon -------------------------------------------------- */

    /* 28163 -> "$28,163". Grouped with commas; the reference shows thousands
       separated rather than a bare run of digits. */
    function money(n) {
        n = Math.floor(Math.abs(Number(n) || 0));
        return '$' + String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    function onCash(d) {
        var c = $('cash'), b = $('bank');
        if (d.cash != null && c) c.textContent = money(d.cash);
        if (d.bank != null && b) b.textContent = money(d.bank);
        // A row only appears once it has a real value, so a server that tracks
        // only one of the two never shows an empty second row.
        show($('cash-row'), d.show !== false && d.cash != null);
        show($('bank-row'), d.show !== false && d.bank != null);
    }

    /* What the duffle bag on the player's back is worth at a fence/pawn shop
       right now (see wasabi_backpack's server-side value sum). `value` absent
       means "not carrying one" -- the row hides rather than showing $0, same
       convention as cash/bank above. `value === 0` (carrying an empty or
       all-junk bag) still shows, so the number itself answers "worth robbing
       me for this?" at a glance. */
    function onDuffle(d) {
        var v = $('duffle');
        if (d.value != null && v) v.textContent = money(d.value);
        show($('duffle-row'), d.value != null);
    }

    /* rcore_casino's own chip balance, comma-grouped like money but with no $
       sign, chips aren't cash. Hidden at 0 same as vice_hud's client.lua only
       pushes a value once it's above 0 in the first place. */
    function onChips(d) {
        var v = $('chips');
        if (d.value != null && v) v.textContent = String(Math.floor(Math.abs(Number(d.value) || 0))).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
        show($('chips-row'), d.value != null);
    }

    /* Equipped weapon: icon plus, for ranged weapons, clip/reserve counts.
       Melee shows the icon alone — the frames confirm no ammo row for a wrench. */
    function onWeapon(d) {
        var icon = $('weapon-icon');
        if (icon) {
            if (d.icon) { icon.src = d.icon; show(icon, true); }
            else show(icon, false);
        }
        var hasAmmo = d.clip != null && d.reserve != null;
        show($('ammo'), !!d.armed && hasAmmo);
        if (hasAmmo) {
            var c = $('ammo-clip'), r = $('ammo-reserve');
            if (c) c.textContent = d.clip;
            if (r) r.textContent = d.reserve;
        }
    }

    /* --- aim crosshair ---------------------------------------------------
       Three small, mostly-independent pieces:
         onCrosshair  — show/hide + which variant (vehicle ring vs foot ticks)
         onCrossFire  — a discrete "a shot just fired" ping; the widen/settle
                        motion itself is a CSS transition on --spread (see
                        style.css), not anything animated from here
         onKillMark   — a discrete "a kill just happened, here's how clean"
                        ping, coloured by client.lua's classifier */
    function onCrosshair(d) {
        var box = $('crosshair');
        if (!box) return;
        if (!d || !d.active) { show(box, false); return; }
        box.dataset.mode = d.mode === 'vehicle' ? 'vehicle' : 'foot';
        show(box, true);
    }

    var crossFireTimer = null;
    function onCrossFire() {
        var tips = $('cross-tips');
        if (!tips) return;
        tips.style.setProperty('--spread', 'calc(0.35 * var(--w))');
        // Rapid fire keeps re-arming this rather than letting it settle
        // between shots, so sustained fire holds the wide reticle and only
        // eases back once the shooting actually stops.
        clearTimeout(crossFireTimer);
        crossFireTimer = setTimeout(function () {
            tips.style.setProperty('--spread', '0px');
        }, 220);
    }

    var KILL_CLASSES = ['kill-red', 'kill-yellow', 'kill-white'];
    var KILL_CLASS_FOR = { headshot: 'kill-red', sloppy: 'kill-yellow', clean: 'kill-white' };
    var killMarkTimer = null;
    function onKillMark(d) {
        var x = $('cross-kill');
        if (!x || !d || !d.quality) return;
        var cls = KILL_CLASS_FOR[d.quality] || 'kill-white';
        // A kill can land in the instant the crosshair itself is about to be
        // told it's inactive (the shot that killed is usually the last one
        // fired) -- force it visible for the flash rather than let a
        // same-tick "active: false" hide the thing that's supposed to flash.
        show($('crosshair'), true);
        x.classList.remove.apply(x.classList, KILL_CLASSES.concat('show'));
        void x.offsetWidth; // restart the transition even on back-to-back kills
        x.classList.add(cls, 'show');
        clearTimeout(killMarkTimer);
        killMarkTimer = setTimeout(function () { x.classList.remove('show'); }, 550);
    }

    /* --- race lap / checkpoint HUD -----------------------------------------
       Lua pushes only on discrete events (run start, each checkpoint hit,
       finish/abort) rather than streaming elapsedMs every frame -- see
       client.lua's exports.vice_hud:SetLapTimer. The visible ticking is
       entirely local: every push re-bases (lapTimerBasisMs, performance.now())
       and a requestAnimationFrame loop interpolates from there, so the
       number stays smooth without SendNUIMessage being called anywhere near
       that often. Self-correcting: the next real push re-bases again, so
       small drift between pushes never accumulates. */
    var raf = typeof requestAnimationFrame === 'function'
        ? requestAnimationFrame
        : function (cb) { return setTimeout(cb, 16); };
    var caf = typeof cancelAnimationFrame === 'function' ? cancelAnimationFrame : clearTimeout;

    var lapTimerRAF = null;
    var lapTimerBasisMs = 0;
    var lapTimerBasisPerf = 0;
    var lapTimerRunning = false;

    function formatLapTime(ms) {
        ms = Math.max(0, ms || 0);
        var totalSeconds = ms / 1000;
        var minutes = Math.floor(totalSeconds / 60);
        var seconds = totalSeconds - minutes * 60;
        var m = (minutes < 10 ? '0' : '') + minutes;
        var s = seconds.toFixed(2);
        if (seconds < 10) s = '0' + s;
        return m + ':' + s;
    }

    function lapTimerTick() {
        if (!lapTimerRunning) return;
        var el = $('lap-timer');
        if (el) el.textContent = formatLapTime(lapTimerBasisMs + (performance.now() - lapTimerBasisPerf));
        lapTimerRAF = raf(lapTimerTick);
    }

    function renderLapPips(cur, total) {
        var track = $('lap-cp-track');
        if (!track) return;
        // Checkpoints-per-lap never changes mid-run, so the element count
        // only needs rebuilding when it actually differs from last time.
        if (track.childElementCount !== total) {
            track.innerHTML = '';
            for (var i = 0; i < total; i++) {
                var pip = document.createElement('span');
                pip.className = 'lap-cp-pip';
                track.appendChild(pip);
            }
        }
        var pips = track.children;
        for (var j = 0; j < pips.length; j++) {
            pips[j].classList.toggle('on', j < cur);
        }
    }

    function onLapHud(d) {
        var box = $('lap-hud');
        if (!box) return;
        if (!d || !d.show) {
            show(box, false);
            lapTimerRunning = false;
            if (lapTimerRAF) caf(lapTimerRAF);
            return;
        }

        var cur = $('lap-cur'), tot = $('lap-total');
        if (cur) cur.textContent = d.lap != null ? d.lap : 1;
        if (tot) tot.textContent = d.laps != null ? d.laps : 1;

        var cpCur = $('lap-cp-cur'), cpTot = $('lap-cp-total');
        if (cpCur) cpCur.textContent = d.cp != null ? d.cp : 0;
        if (cpTot) cpTot.textContent = d.cpTotal != null ? d.cpTotal : 0;
        renderLapPips(d.cp || 0, d.cpTotal || 0);

        if (d.elapsedMs != null) {
            lapTimerBasisMs = d.elapsedMs;
            lapTimerBasisPerf = performance.now();
        }
        if (d.running) {
            if (!lapTimerRunning) {
                lapTimerRunning = true;
                lapTimerTick();
            }
        } else {
            lapTimerRunning = false;
            if (lapTimerRAF) caf(lapTimerRAF);
            var t = $('lap-timer');
            if (t) t.textContent = formatLapTime(lapTimerBasisMs);
        }

        show(box, true);
    }

    /* --- interact menu (Phase 1 of the ox_target-replacement project) -----
       A plain data-driven option list -- no targeting geometry, no raycast
       highlight, see the comment on #interact in index.html for why that
       engine is a separate, later project. Options: array of
       { label, badges: ['stamina'|'focus', ...], selected } (selected marks
       the ONE row that gets the X-in-circle marker; every other row gets a
       hollow dot). Keyboard-navigable: arrows move, Enter confirms, Escape
       cancels -- posted back to Lua as interactSelect / interactClose. */
    var INTERACT_MARKER_DOT = '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8"/></svg>';
    var INTERACT_MARKER_X = '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/>' +
        '<path d="M8.5 8.5l7 7M15.5 8.5l-7 7"/></svg>';
    var INTERACT_BADGE_SVG = {
        stamina: '<svg viewBox="0 0 24 24"><path d="M13 2 4.5 14h6L10 22l9.5-13h-6z"/></svg>',
        focus: '<svg viewBox="0 0 24 24"><path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/>' +
            '<circle cx="12" cy="12" r="3"/></svg>'
    };

    var interactOptions = [];
    var interactSel = 0;

    function renderInteract() {
        var list = $('interact-list');
        if (!list) return;
        list.innerHTML = '';
        interactOptions.forEach(function (opt, i) {
            var row = document.createElement('div');
            row.className = 'interact-row' + (i === interactSel ? ' selected' : '');
            row.dataset.index = i;

            var marker = document.createElement('span');
            marker.className = 'interact-marker ' + (i === interactSel ? 'interact-marker-x' : 'interact-marker-dot');
            marker.innerHTML = i === interactSel ? INTERACT_MARKER_X : INTERACT_MARKER_DOT;
            row.appendChild(marker);

            var label = document.createElement('span');
            label.className = 'interact-label item-select-outline';
            label.textContent = opt.label || '';
            row.appendChild(label);

            if (opt.badges && opt.badges.length) {
                var badges = document.createElement('span');
                badges.className = 'interact-badges';
                opt.badges.forEach(function (b) {
                    var chip = document.createElement('span');
                    chip.className = 'interact-badge ' + b;
                    chip.innerHTML = INTERACT_BADGE_SVG[b] || '';
                    badges.appendChild(chip);
                });
                row.appendChild(badges);
            }

            list.appendChild(row);
        });
    }

    function onInteract(d) {
        var box = $('interact');
        if (!box) return;
        if (!d || !d.show) { show(box, false); return; }

        interactOptions = d.options || [];
        // `selected` on the data wins if given; otherwise the row already
        // flagged selected: true in the option list itself, otherwise 0.
        interactSel = d.selected != null ? d.selected
            : Math.max(0, interactOptions.findIndex(function (o) { return o.selected; }));
        if (interactSel < 0) interactSel = 0;

        renderInteract();
        show(box, true);
    }

    function moveInteractSel(delta) {
        if (!interactOptions.length) return;
        interactSel = (interactSel + delta + interactOptions.length) % interactOptions.length;
        renderInteract();
        // Lua also drives this menu directly for controller input (see
        // client.lua) and keeps its own selected-index cache so a
        // controller Accept press knows what to confirm. Without this, a
        // keyboard nudge here would leave that cache pointing at whatever
        // was highlighted before — telling it every move is what keeps the
        // two input paths agreeing regardless of which one the player
        // actually used last.
        post('interactMove', { index: interactSel });
    }

    function confirmInteract() {
        if (!interactOptions.length) return;
        post('interactSelect', { index: interactSel });
    }

    function closeInteract() {
        show($('interact'), false);
        post('interactClose', {});
    }

    /* --- world action prompt ------------------------------------------------
       A short list of button-glyph + label options, e.g. Slim Jim / Smash
       Window. Not the scrollable #interact list — see the comment on
       #world-actions in index.html for why this is its own component.

       Each option now arrives as { label, glyph, device } -- glyph is the
       LIVE resolved key (client_overlays.lua's waResolveKey), the same way
       the Action Prompts row above gets its `glyph`/`device`. This used to
       take a hand-picked `button: 'triangle'|'circle'` string with nothing
       connecting it to what was actually bound, which is exactly how it went
       stale: the shown icon and the working button drifted apart (see the
       fix note in vice_hud/client_overlays.lua and
       qbx_vehiclekeys/client/slimjim.lua). Deriving the icon FROM the
       resolved glyph, below, is what makes that drift impossible now. */
    var WA_BTN_SVG = {
        triangle: '<svg viewBox="0 0 24 24"><path d="M12 4 L20.5 19.5 L3.5 19.5 Z"/></svg>',
        circle: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8" fill="none"/></svg>',
        square: '<svg viewBox="0 0 24 24"><rect x="5" y="5" width="14" height="14" rx="1.5" fill="none"/></svg>',
        cross: '<svg viewBox="0 0 24 24"><path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/></svg>'
    };
    // GTA's own instructional-button text names pad face buttons with their
    // Xbox letter (Y/B/X/A) regardless of the player's actual controller
    // brand -- the same convention PAD_TONE (action prompts, above) keys off.
    // Mapped to the matching PlayStation shape so a pad player still sees the
    // outlined icon this component was designed around, derived from the
    // resolved glyph rather than a separately hand-picked shape.
    var WA_PAD_SHAPE = { Y: 'triangle', B: 'circle', X: 'square', A: 'cross' };

    function onWorldActions(d) {
        var box = $('world-actions');
        if (!box) return;
        if (!d || !d.show) { show(box, false); return; }

        box.innerHTML = '';
        (d.options || []).forEach(function (opt) {
            var row = document.createElement('div');
            row.className = 'wa-row';

            var btn = document.createElement('span');
            btn.className = 'wa-btn';
            var glyph = opt.glyph == null ? '' : String(opt.glyph);
            var shape = opt.device === 'pad' ? WA_PAD_SHAPE[glyph] : null;
            if (shape) {
                // Recognised pad face button: the outlined shape this
                // component was designed around.
                // innerHTML alone -- setting .textContent afterward would wipe
                // the SVG right back out, since it replaces all children.
                btn.innerHTML = WA_BTN_SVG[shape];
                btn.classList.remove('wa-btn-text');
            } else {
                // Keyboard, or a pad button with no shape mapping (shoulders,
                // triggers, D-pad) -- show the resolved key/label as plain
                // text inside the same circle rather than guessing a shape.
                btn.innerHTML = '';
                btn.textContent = glyph;
                btn.classList.toggle('wa-btn-text', glyph.length > 0);
            }
            row.appendChild(btn);

            var label = document.createElement('span');
            label.className = 'wa-label';
            label.textContent = opt.label || '';
            row.appendChild(label);

            box.appendChild(row);
        });
        show(box, true);
    }

    /* --- lockpick check -------------------------------------------------
       "Hold, release inside the zone." Lua owns the timing and the
       win/lose decision entirely (see exports.vice_hud:StartLockpickCheck
       in client.lua) — this only ever draws whatever it's told: the zone's
       position/width once per check, the fill level while the button is
       held, and a brief win/lose flash at the end. */
    var lockpickResultTimer = null;

    function onLockpick(d) {
        var box = $('lockpick');
        if (!box) return;
        if (!d || !d.show) { show(box, false); return; }

        box.classList.remove('lp-win', 'lp-fail');
        var fill = $('lp-fill');
        if (fill) fill.style.setProperty('--lp-pct', 0);
        var zone = $('lp-zone');
        if (zone) {
            zone.style.setProperty('--lp-zone-start', d.zoneStart != null ? d.zoneStart : 0);
            zone.style.setProperty('--lp-zone-len', d.zoneLen != null ? d.zoneLen : 10);
        }
        var glyph = $('lp-glyph');
        if (glyph) glyph.textContent = d.glyph || 'R';

        show(box, true);
    }

    function onLockpickProgress(d) {
        var fill = $('lp-fill');
        if (fill && d && d.pct != null) fill.style.setProperty('--lp-pct', Math.max(0, Math.min(100, d.pct)));
    }

    function onLockpickResult(d) {
        var box = $('lockpick');
        if (!box) return;
        box.classList.add(d && d.success ? 'lp-win' : 'lp-fail');
        clearTimeout(lockpickResultTimer);
        lockpickResultTimer = setTimeout(function () { show(box, false); }, 450);
    }

    /* --- minimap slot geometry ------------------------------------------- */

    var mapFrameOn = false;
    var mapCrossOn = false;
    /* Is the ENGINE drawing the radar right now? The frame, the corner badge
       and the nav compass are all NUI drawn over where the map is, so they have
       to come down with it -- otherwise hiding the map on foot leaves an empty
       outlined box with a logo in it. client.lua's setRadar() is the single
       place that toggles the radar and it reports every transition here. */
    var mapVisible = true;
    /* What the badge would show if the map were up. onNav owns this (it steps
       aside for the compass); applyMapChrome owns whether it is ACTUALLY shown,
       so the two cannot fight over the same element. */
    var mapBadgeWanted = true;

    function applyMapChrome() {
        var fr = $('map-frame');
        if (fr) show(fr, mapVisible && mapFrameOn);
        show($('map-cross'), mapVisible && mapCrossOn);
        show($('map-badge'), mapVisible && mapBadgeWanted);
        // The compass rides the map's own top edge, so it goes too. Vanish, not
        // hide: it is a .slot and fades like the rest of that family.
        if (!mapVisible) slotVanish($('nav-compass'));
    }

    /* The last map rect we were told about, kept so the panel stack can be
       re-snapshotted on demand (Follow map, or Reset on the Map panels row)
       without waiting for the map to move again. */
    var lastMapRect = null;
    /* Has the panel stack been given its geometry yet this session? The map
       rect arrives repeatedly — the watchdog republishes it whenever it
       changes — and the whole point of the snapshot is that only the FIRST one
       counts. See applyPanelRect. */
    var panelSnapped = false;

    /* Writes the panel stack's own geometry.

       Three sources, in priority order:
         1. an explicit value saved on the `slots` element (Panel left/width/
            bottom in the editor) — wins always, at any map size;
         2. Follow map turned on — track the map rect live, which is what this
            HUD did unconditionally before;
         3. otherwise the SNAPSHOT: the first map rect of the session, written
            once and then left alone.

       (3) is what fixes "resizing the map resizes the panels". An untouched
       layout still lands on the map's edge, because that is where the first
       rect puts it; every rect after that is ignored, so the map can be scaled
       freely and the panels stay where they are. */
    function applyPanelRect(rect) {
        if (!stage) return;
        var o = offsets.slots || {};
        var follow = o.pfollow === 1 || o.pfollow === true;

        function put(cssVar, own, mapVal, unit) {
            if (own != null) {
                stage.style.setProperty(cssVar, own + unit);
            } else if (follow || !panelSnapped) {
                if (mapVal != null) stage.style.setProperty(cssVar, mapVal + unit);
            }
            // else: leave whatever the snapshot already wrote.
        }

        var r = rect || lastMapRect || {};
        put('--panel-left',   o.pl, r.left,   'cqw');
        put('--panel-width',  o.pw, r.width,  'cqw');
        put('--panel-bottom', o.pb, r.bottom, 'cqh');

        // Only a rect that actually carried the numbers counts as the snapshot,
        // so a partial message cannot burn it.
        if (r.left != null && r.width != null && r.bottom != null) panelSnapped = true;
    }

    /* Throws the snapshot away and takes a fresh one from wherever the map is
       now. Used by Follow map and by Reset on the Map panels row -- both mean
       "put them back on the map", and without this they would re-attach to a
       snapshot taken before the map was resized. */
    function resnapPanelRect() {
        panelSnapped = false;
        applyPanelRect(lastMapRect);
    }

    function onMapRect(d) {
        if (!stage) return;
        // Values arrive as percentages of the viewport, matching the reference
        // measurements. They are applied to the stage as cq units so they stay
        // correct inside the centred 16:9 box on an ultrawide.
        //
        //   --map-bottom       distance from screen bottom to the map's TOP
        //                      edge; the slot stack anchors to this.
        //   --map-bottom-edge  distance from screen bottom to the map's BOTTOM
        //                      edge, which is what the frame needs.
        if (d.left != null) stage.style.setProperty('--map-left', d.left + 'cqw');
        if (d.width != null) stage.style.setProperty('--map-width', d.width + 'cqw');
        if (d.bottom != null) stage.style.setProperty('--map-bottom', d.bottom + 'cqh');
        if (d.height != null) stage.style.setProperty('--map-height', d.height + 'cqh');
        if (d.bottom != null && d.height != null) {
            // Rounded: the subtraction is binary float arithmetic, so an honest
            // 2.5 arrives as 2.4999999999999982 and lands in the stylesheet
            // that way.
            stage.style.setProperty(
                '--map-bottom-edge', +(d.bottom - d.height).toFixed(4) + 'cqh');
        }
        // Remember it, then let the panel stack decide for itself whether this
        // rect is any of its business. Before the split it simply WAS the panel
        // stack's geometry, which is the coupling this removes.
        lastMapRect = {
            left: d.left != null ? d.left : (lastMapRect && lastMapRect.left),
            width: d.width != null ? d.width : (lastMapRect && lastMapRect.width),
            bottom: d.bottom != null ? d.bottom : (lastMapRect && lastMapRect.bottom),
            height: d.height != null ? d.height : (lastMapRect && lastMapRect.height)
        };
        applyPanelRect(lastMapRect);

        // The frame only helps when it sits exactly on the map; off by default.
        if (d.showFrame != null) mapFrameOn = d.showFrame === true;
        if (d.showCross != null) mapCrossOn = d.showCross === true;
        if (d.visible != null) mapVisible = d.visible === true;
        applyMapChrome();
    }

    /* --- component outlines (/hudrects) -----------------------------------
       Draws one labelled outline per engine minimap component, positioned in
       the same stage units the published map rect uses. Each carries its own
       measurements, because "the green box stops here" is only useful next to
       the number that put it there. */
    function onMapDebug(d) {
        var box = $('map-rects');
        if (!box) return;
        if (!d || d.show === false || !d.rects) { show(box, false); box.innerHTML = ''; return; }

        box.innerHTML = '';
        d.rects.forEach(function (item) {
            var r = item && item.r;
            if (!r) return;
            var el = document.createElement('div');
            el.className = 'mrect m-' + item.name;
            el.style.left = r.left + 'cqw';
            el.style.width = r.width + 'cqw';
            // `bottom` is the distance from the screen bottom to the rect's TOP
            // edge, matching --map-bottom, so the box hangs down from there.
            el.style.bottom = (r.bottom - r.height) + 'cqh';
            el.style.height = r.height + 'cqh';

            var tag = document.createElement('span');
            tag.innerHTML = '<b>' + item.name + '</b> ' +
                r.left.toFixed(2) + ',' + r.bottom.toFixed(2) +
                '  ' + r.width.toFixed(2) + '×' + r.height.toFixed(2);
            el.appendChild(tag);
            box.appendChild(el);
        });
        show(box, true);
    }

    /* --- skills ------------------------------------------------------------
       Two separate things, and the split matters. The TOAST is transient: it
       fires on a level-up and clears itself, and it is the only part most
       players will ever see. The PANEL is a screen you deliberately open to
       read where you stand, and it is pushed on every change so that opening it
       never shows a stale number. */
    var skillUpTimer = null;

    function onSkillUp(d) {
        var el = $('skillup');
        if (!el || !d || !d.label) return;
        var lab = $('skillup-label'), lvl = $('skillup-level'), blurb = $('skillup-blurb');
        if (lab) lab.textContent = d.label;
        if (lvl) lvl.textContent = d.level;
        if (blurb) blurb.textContent = d.blurb || '';

        // Restart the animation on a fresh level-up, so two in quick succession
        // read as two events rather than one that never finished.
        el.classList.remove('slot-in');
        show(el, true);
        void el.offsetWidth;
        el.classList.add('slot-in');

        if (skillUpTimer) clearTimeout(skillUpTimer);
        skillUpTimer = setTimeout(function () { show(el, false); }, 4200);
    }

    function onSkills(d) {
        var box = $('skills');
        var list = $('skills-list');
        if (!box || !list) return;

        if (d && d.skills) {
            list.innerHTML = '';
            d.skills.forEach(function (s) {
                var li = document.createElement('li');
                li.className = 'sk' + (s.max ? ' maxed' : '');

                var head = document.createElement('div');
                head.className = 'sk-head';
                var name = document.createElement('span');
                name.className = 'sk-name';
                name.textContent = s.label;
                var lvl = document.createElement('span');
                lvl.className = 'sk-level';
                lvl.textContent = s.max ? 'MAX' : s.level;
                head.appendChild(name); head.appendChild(lvl);

                var track = document.createElement('div');
                track.className = 'sk-track';
                var fill = document.createElement('div');
                fill.className = 'sk-fill';
                fill.style.transform = 'scaleX(' + Math.max(0, Math.min(1, s.frac || 0)).toFixed(4) + ')';
                track.appendChild(fill);

                var sub = document.createElement('div');
                sub.className = 'sk-sub';
                // The unit is named because "1240 / 1900" tells you nothing on
                // its own — what you want to know is what to go and DO.
                sub.textContent = s.max
                    ? s.blurb
                    : s.into + ' / ' + s.need + '  ·  ' + s.unit;

                li.appendChild(head); li.appendChild(track); li.appendChild(sub);
                list.appendChild(li);
            });
        }

        // `show` is only obeyed when it is true, or every background refresh
        // would slam the panel shut while the player was reading it.
        if (d && d.show) show(box, true);
    }

    /* --- map panel arrival ------------------------------------------------
       The two map panels announce themselves the way a phone announces a
       message: a springy rise into place. Going away is left exactly as it was
       — an instant hide — so only the arrival is staged.

       `.hidden` is `display: none`, which cancels an animation outright, so the
       class cannot simply be toggled alongside it: the element has to be made
       displayable, laid out once, and only then given the animation class.

       `restart` is not a detail. onZone fires on a genuine zone CHANGE, so
       re-announcing is right there. onVehicle is re-pushed by the poll loop
       roughly four times a second for as long as the panel is up (it carries
       live fuel and lock state), so restarting on every call would leave the
       vehicle panel permanently mid-animation. Pass it deliberately. */
    /* Going away is a fade, so it has to be STAGED rather than toggled: the
       `hidden` class is `display: none`, which cancels an animation outright
       instead of playing it. The element fades first and is hidden after.
       Kept in step with the CSS by hand — a transition the JS thinks is shorter
       than it is would cut the fade off part-way. */
    /* 460 against a 420ms animation, on purpose. The fill-mode holds opacity at
       0 once the animation ends, so hiding LATE is invisible — hiding early
       cuts the fade off mid-way. The margin absorbs timer drift in the only
       direction that can be seen. */
    var SLOT_OUT_MS = 460;
    var slotOutTimers = {};

    /* Reduced motion means no fade, and therefore nothing to wait for: leaving
       the element up for 460 invisible milliseconds would be a delay the player
       never asked for in exchange for an animation they turned off. */
    var reduceMotion = window.matchMedia
        && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    function slotLeaving(el) {
        return !!(el && slotOutTimers[el.id]);
    }

    function slotCancelExit(el) {
        if (!el || !slotOutTimers[el.id]) return;
        clearTimeout(slotOutTimers[el.id]);
        slotOutTimers[el.id] = null;
        el.classList.remove('slot-out');
    }

    function slotAppear(el, restart) {
        if (!el) return;
        // Mid-fade counts as gone, whatever the caller asked for: catching a
        // panel on its way out and leaving it half-faded looks like a bug.
        var wasLeaving = slotLeaving(el);
        slotCancelExit(el);

        var wasHidden = el.classList.contains('hidden');
        if (!wasHidden && !wasLeaving && !restart) { show(el, true); return; }

        el.classList.remove('slot-in');
        show(el, true);
        // Force a layout read between removing the class and re-adding it.
        // Without it both changes collapse into one style recalculation and the
        // browser has no "before" to animate from, so nothing plays.
        void el.offsetWidth;
        el.classList.add('slot-in');
    }

    function slotVanish(el) {
        if (!el || el.classList.contains('hidden')) return;
        if (slotOutTimers[el.id]) return;      // already on its way out
        if (reduceMotion) { el.classList.remove('slot-in'); show(el, false); return; }
        el.classList.remove('slot-in');
        el.classList.add('slot-out');
        slotOutTimers[el.id] = setTimeout(function () {
            slotOutTimers[el.id] = null;
            el.classList.remove('slot-out');
            show(el, false);
        }, SLOT_OUT_MS);
    }

    /* --- zone bar -------------------------------------------------------- */

    var zoneTimer = null;
    var ZONE_MS = 4500;

    /* --- shrink-to-fit ----------------------------------------------------
       "South Vice-Dale County" is wider than the zone bar, and the bar's answer
       was to clip it to "South Vice-Dale C…". An ellipsis is the right last
       resort and the wrong first one: the panel is a fixed width tied to the
       minimap, the names are not, and a name you cannot read is not doing its
       job.

       So the text is measured against the box it is in and given a scale factor
       that makes it fit. --fit multiplies the font size rather than replacing
       it, so it composes with whatever size was tuned in the editor. The
       nowrap/ellipsis rules stay as the floor: past FIT_MIN the text would be
       too small to read, and clipping is better than illegible.  */
    var FIT_MIN = 0.5;
    var fitting = false;          // a pass is running right now
    var fitQueued = false;        // a pass is already scheduled for next frame

    function overflows(items) {
        var worst = 1;
        for (var i = 0; i < items.length; i++) {
            var el = items[i];
            if (!el || !el.textContent) continue;
            var avail = el.clientWidth;
            var need = el.scrollWidth;
            if (avail > 0 && need > avail) worst = Math.min(worst, avail / need);
        }
        return worst;
    }

    function fitBox(box, items) {
        if (!box) return;
        // Start from a clean slate. Leaving the previous factor on would make
        // each pass shrink relative to the last and walk the text to nothing.
        box.classList.remove('fit-wrap');
        box.style.removeProperty('--fit');

        var scale = 1;
        /* Iterated, not one division.
           scrollWidth is an integer and letter-spacing leaves a trailing gap
           the ratio does not know about, so a single pass lands a pixel or two
           over and the text is STILL clipped — which looks exactly like the
           fitting never having run. Two or three passes converge. */
        for (var pass = 0; pass < 3; pass++) {
            var worst = overflows(items);
            if (worst >= 1) break;
            // One factor for the whole box, so a long model is never set
            // smaller than the make sitting directly above it.
            scale = Math.max(FIT_MIN, scale * worst);
            box.style.setProperty('--fit', scale.toFixed(4));
            if (scale <= FIT_MIN) break;
        }

        /* Past the floor, wrap rather than cut.
           "Western Motorcycle Company" does not fit this panel at any size you
           could still read, and shrinking further just trades one unreadable
           result for another. Both panels size from their content (the vehicle
           panel has a min-height, not a height), so letting the words wrap
           costs a taller panel and keeps the whole name. */
        if (scale <= FIT_MIN && overflows(items) < 1) box.classList.add('fit-wrap');
    }

    function fitNow() {
        fitting = true;
        try {
            fitBox($('zone'), [$('zone-text')]);
            fitBox($('vehicle'), [$('veh-make'), $('veh-model')]);
            /* The nav bar needs this for the opposite reason the other two do.
               Its type is sized off viewport HEIGHT (--w, so it holds its
               proportion on an ultrawide) while its WIDTH comes from the map
               panel -- so on a narrow, tall aspect like 4:3 the bar is short
               on width and the longest instruction is the one that no longer
               fits. fitBox is measured, not guessed, so it covers whatever
               aspect a player actually runs.
               `fit-wrap` is deliberately not styled for this box: the bar has a
               fixed height and wrapping would overflow it, so past the floor it
               keeps ellipsing. */
            fitBox($('nav-turn'), [$('nav-turn-text'), $('nav-turn-dist')]);
        } finally {
            fitting = false;
        }
    }

    /* COALESCED, not dropped.
       An earlier version of this refused to run while another pass was in
       flight, which looks like the same thing and is not: onZone and onVehicle
       fire back to back, so the second call was thrown away and the vehicle
       names went unfitted while the zone bar fitted correctly. Queueing one
       pass per frame lets every caller ask and still costs one reflow. */
    function fitAll() {
        if (fitQueued) return;
        fitQueued = true;
        requestAnimationFrame(function () { fitQueued = false; fitNow(); });
    }

    // Re-fit whenever the box changes width (resolution change, the editor
    // resizing the panel, the minimap rect moving under it) and once the real
    // fonts have loaded — measuring against the fallback face gives an answer
    // that is wrong the moment Helvetica arrives.
    if (window.ResizeObserver) {
        // `fitting` keeps the observer out while a pass is mid-flight: fitBox
        // removes --fit to measure, which resizes the box and would otherwise
        // wake the observer that is watching it.
        var ro = new ResizeObserver(function () { if (!fitting) fitAll(); });
        ['zone', 'vehicle', 'slots', 'nav-turn'].forEach(function (id) {
            var el = $(id); if (el) ro.observe(el);
        });
    }
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(fitAll);

    function onZone(d) {
        var el = $('zone');
        var txt = $('zone-text');
        if (!el || !txt || !d.zone) return;
        txt.textContent = d.zone;
        el.classList.toggle('water', !!d.water);
        // restart: a new zone is a new announcement, even if the bar is still
        // up from the last one.
        slotAppear(el, true);
        // After it is displayable, so the box has a width to measure against.
        fitAll();
        if (zoneTimer) clearTimeout(zoneTimer);
        zoneTimer = setTimeout(function () { slotVanish(el); }, d.duration || ZONE_MS);
    }

    /* --- nav popup --------------------------------------------------------
       Mirrors whatever client.lua computed, but only actually shows it while
       `near` is true -- client.lua only sets that once the next turn (or the
       destination) is close, same "appear for the thing that matters, then
       get out of the way" rule the zone bar already follows. slotAppear/
       slotVanish (not a plain show) so it fades like every other slot panel
       instead of snapping on/off; both are safe to call every tick regardless
       of current state, they no-op if already in the state asked for. */
    function onNav(d) {
        var el = $('nav-popup');
        var compass = $('nav-compass');
        // The compass figure sits up in the map's corner, same neighbourhood
        // as the badge -- so the badge steps aside rather than fighting it
        // for the same real estate.
        if (!el) return;
        if (!d || !d.active || !d.near) {
            slotVanish(el);
            slotVanish(compass);
            mapBadgeWanted = true;
            applyMapChrome();
            return;
        }
        var turnText = $('nav-turn-text');
        if (turnText) turnText.textContent = d.instruction || '';
        var distText = $('nav-turn-dist');
        if (distText) distText.textContent = d.distance || '';
        var arrow = $('nav-turn-arrow');
        if (arrow) arrow.setAttribute('data-dir', d.dir || 'straight');
        var compassDist = $('nav-compass-dist');
        if (compassDist) compassDist.textContent = d.remaining || '';
        // New copy means a new measurement -- "Continue Straight" and "Arrive"
        // are very different widths in the same bar.
        fitAll();
        slotAppear(el);
        slotAppear(compass);
        mapBadgeWanted = false;
        applyMapChrome();
    }

    /* The nav-turn tile's character-gender default, teal for a male
       character, pink for a female one, same accent client.lua repaints the
       native waypoint cross/route with (see applyWaypointPalette there),
       pushed once it resolves. Written to its OWN --*-gender-default
       properties, not --nav-accent/--nav-accent-ink directly, so that
       applyOffsets() clearing an unset editor customisation on every layout
       load (onLayout -> applyOffsets, including at resource start) cannot
       wipe this out along with it, see the fallback chain on #nav-turn-arrow
       in style.css. An explicit /movehud "Turn tile colour" customisation
       still wins over this either way, via the same var() chain. */
    function onNavAccent(d) {
        if (!stage || !d) return;
        if (d.accent) stage.style.setProperty('--nav-accent-gender-default', d.accent);
        if (d.ink) stage.style.setProperty('--nav-accent-ink-gender-default', d.ink);
    }

    /* --- vehicle panel --------------------------------------------------- */

    /* The tone class, and the gauge reading if this pip has a ring.
       `pct` is null for a pip that is a state rather than a quantity. */
    function tone(el, t, pct) {
        if (!el) return;
        var gauge = el.classList.contains('gauge');
        el.className = 'pip ' + (t || 'unknown') + (gauge ? ' gauge' : '');
        if (pct == null) return;
        var v = Math.max(0, Math.min(100, pct));
        el.style.setProperty('--pct', v.toFixed(1));
        // A round linecap paints a dot even at zero, which would show a pip of
        // fuel in an empty tank.
        var fill = el.querySelector('.pip-fill');
        if (fill) {
            if (v < 0.5) fill.setAttribute('data-empty', '1');
            else fill.removeAttribute('data-empty');
        }
    }

    /* Engine wear, as a tone.
       GetVehicleEngineHealth is 1000 factory-fresh down to 0 seized, and keeps
       going NEGATIVE for an engine past that, which is why the last test is
       `< WORN` rather than a range: a destroyed engine reads -4000 and would
       fall out of any band with a floor on it. */
    var ENG_GOOD = 700, ENG_WORN = 300;

    function engineTone(health) {
        // Missing rather than damaged: an older client.lua, or /hudtest before
        // it learned to send this. Treat silence as "nothing to report".
        if (health == null) return 'good';
        if (health >= ENG_GOOD) return 'good';
        if (health >= ENG_WORN) return 'warn';
        return 'bad';
    }

    /* The three pips.
       Fuel and engine are the two that carry a real reading; lock is a state
       rather than a health.

       A SHUT-OFF CAR IS MONOCHROME, all three of them. Not an oversight and not
       a missing reading: green / amber / red on a parked car is the HUD
       shouting about a fuel level nothing is currently burning, and once you
       have seen a whole car park of them light up you stop reading any of them.
       Turning the key is what makes the pips mean something, so turning the key
       is what gives them colour. */
    /* Engine health as a percentage for the ring. The native runs 1000 down to
       0 and then keeps going negative for an engine past seized, so the floor
       is a clamp rather than a range. */
    function enginePct(health) {
        if (health == null) return 100;
        return Math.max(0, Math.min(100, health / 10));
    }

    /* A pip EARNS its place on the panel by having something to report.
       'warn' and 'bad' are the two tones that mean "look at this"; 'good' and
       'unknown' are not worth a permanent icon, so those are hidden outright
       rather than shown in a colour that says nothing. A full tank, a healthy
       engine and a locked door are the normal case, and three discs that are
       lit green for the entire time you are driving are three discs nobody
       reads by the second day. */
    function pipShows(t) { return t === 'warn' || t === 'bad'; }

    /* The lock is the odd one out and cannot use pipShows.
       Fuel and engine are CONTINUOUS: "low" is a condition that persists, so a
       threshold is the whole rule. A door lock is neither low nor high -- it
       is one of two perfectly normal states, and while you are sitting in the
       car driving it, unlocked is the ordinary one. Treating "unlocked" as a
       standing warning is what pinned this pip on screen for the entire drive.
       So it is shown as an EVENT instead: it appears when the state actually
       changes -- you locked or unlocked the car -- confirms that for a few
       seconds, then leaves, which is the same "only here when it has something
       to say" rule the other two follow, expressed for a state rather than a
       level. */
    var LOCK_PIP_MS = 3200;
    var lockPipState = null;    // last lockState seen, to detect a change
    var lockPipUntil = 0;       // timestamp the pip stops being shown

    function lockPipVisible(d, running) {
        var st = running ? (d.lockState || 'unknown') : 'unknown';
        // First sighting of a car is not a change: getting in should not
        // flash the lock at you.
        if (lockPipState === null) { lockPipState = st; return false; }
        if (st !== lockPipState) {
            lockPipState = st;
            // Going 'unknown' is the engine stopping, not a lock action.
            lockPipUntil = (st === 'unknown') ? 0 : Date.now() + LOCK_PIP_MS;
        }
        return Date.now() < lockPipUntil;
    }

    /* `expanded` is the vehicle panel's ANNOUNCEMENT state -- the few seconds
       after you get in, while the make and model are still up. All three pips
       show there, because "here is the car you just got into" is exactly when
       a readout of its fuel, engine and lock is worth having, healthy or not.

       Once the panel COLLAPSES to the pip row and stays there for the rest of
       the drive, the warning rule takes over and only fuel/engine in the amber
       or red bands survive. Same principle either way -- a pip is on screen
       while it has something to say -- it is just that on entry, everything
       has something to say.

       Returns whether anything is left, so the caller can drop the panel
       rather than leave an empty box on the map. */
    function setPips(d, expanded) {
        var fuel = d.fuel == null ? 0 : d.fuel;
        var running = !!d.engineOn;

        var fuelTone = !running ? 'unknown'
            : fuel <= 10 ? 'bad' : fuel <= 25 ? 'warn' : 'good';
        var engTone = !running ? 'unknown' : engineTone(d.engineHealth);
        // The lock is a state, not a quantity, so it gets no ring. Its colour
        // still says WHICH state, for the few seconds it is up.
        var lockTone = !running ? 'unknown'
            : d.lockState === 'locked' ? 'good'
            : d.lockState === 'unlocked' ? 'warn' : 'unknown';

        /* The RING keeps its real reading whenever the pip is shown at all --
           it is a measurement, and a warning disc with no figure behind it
           just says "something". */
        tone($('pip-fuel'), fuelTone, fuel);
        tone($('pip-engine'), engTone, enginePct(d.engineHealth));
        tone($('pip-lock'), lockTone);

        /* NOTE: tone() above rewrites className wholesale, which drops the
           `hidden` class -- so these have to run AFTER it, not before. */
        // lockPipVisible has to run either way: it is what tracks the state
        // changes, and skipping it while expanded would make the pip fire on
        // whatever the lock happened to be doing when the panel collapsed.
        var lockEvent = lockPipVisible(d, running);
        var anyFuel = expanded || pipShows(fuelTone);
        var anyEng = expanded || pipShows(engTone);
        var anyLock = expanded || lockEvent;
        show($('pip-fuel'), anyFuel);
        show($('pip-engine'), anyEng);
        show($('pip-lock'), anyLock);

        /* With every pip hidden the strip is an empty band with a border on
           it, so drop the whole band. */
        var any = anyFuel || anyEng || anyLock;
        show($('veh-foot'), any);
        return any;
    }

    /* Manufacturer badge ----------------------------------------------------
       The vehicle panel carries the mark of the marque you are sitting in.
       html/makes.js turns the make into a file in html/logos/; everything about
       how the mark is DRAWN is in style.css, and this only decides which one
       and whether there is one at all.

       Two of the sixty-six manufacturers have no mark, and addon vehicles
       frequently have no resolvable make. Both are ordinary, not errors: they
       clear the class and the panel keeps the plain plate it always had. */
    var badgeKey = null;

    function setBadge(make) {
        var panel = $('vehicle');
        var img = $('veh-logo');
        if (!panel || !img) return;

        var table = window.VICE_MAKES;
        var m = table && table.lookup ? table.lookup(make) : null;
        var key = m && m.logo ? m.key : null;
        /* Cheap guard, not correctness: the poll loop re-pushes this payload
           about four times a second to keep the fuel and lock pips live, and
           reassigning an identical src makes the browser re-decode the image
           every time. */
        if (key === badgeKey) return;
        badgeKey = key;

        if (key) {
            img.src = m.logo;
            img.alt = m.name;
        } else {
            // Cleared, not just hidden. A src left behind is a mark that
            // flashes for one frame the next time the panel is shown.
            img.removeAttribute('src');
            img.alt = '';
        }
        panel.classList.toggle('badged', !!key);
    }

    function onVehicle(d) {
        var el = $('vehicle');
        if (!el) return;
        setBadge(d.make);
        if (!d.show) { slotVanish(el); return; }

        /* Collapsed: the announcement is over, the readings are not.
           Set BEFORE the names are measured -- fitAll() measures against a box
           whose head is collapsed to max-height:0 in this state, and a fit
           computed against a collapsed panel would be wrong the moment it
           expanded again. */
        var collapsed = !!d.collapsed;
        /* Getting into a car while the strip is already up is still an
           ANNOUNCEMENT, and it should arrive like one. Without this the panel
           pops from three icons to a full plate with no motion at all, because
           the element was never hidden and slotAppear has nothing to restart
           from. The reverse edge -- full plate down to icons -- needs no JS
           push like this one: the CSS transition on #veh-head/#veh-foot plays
           off the plain class toggle below, so simply flipping .collapsed is
           enough to animate it. */
        var expanding = !collapsed && el.classList.contains('collapsed');
        el.classList.toggle('collapsed', collapsed);
        if (collapsed) {
            /* Collapsed, the pip row IS the panel -- so with nothing left to
               report there is no panel, and a healthy car simply stops drawing
               one once its announcement is over. Showing an empty plate
               instead is what left a bare box sitting on the map. */
            if (!setPips(d, false)) { slotVanish(el); return; }
            slotAppear(el, false);
            return;
        }

        var make = (d.make || '').toUpperCase();
        var model = (d.model || '').toUpperCase();
        var makeEl = $('veh-make');
        var modelEl = $('veh-model');

        // Addon vehicles often have no resolvable make. Rather than leave a blank
        // row, hide the make line entirely and let the model stand alone.
        show(makeEl, !!make);
        if (makeEl) makeEl.textContent = make;
        if (modelEl) modelEl.textContent = model || 'VEHICLE';

        setPips(d, true);

        // NO restart, EXCEPT on the collapsed -> full edge: the poll loop
        // re-pushes this payload ~4x a second to keep the gauges live, and
        // restarting on each one would hold the panel in a permanent animation.
        slotAppear(el, expanding);
        // After it is displayable, so the panel has a width to measure the
        // names against.
        fitAll();
    }

    /* Badge diagnostic (/hudlogos).
       Three completely different faults look identical from the driver's seat --
       the marks did not ship, the page cannot see them, or they loaded fine and
       something in the CSS is hiding them -- and they have three different
       fixes. This tries to load every mark in the table and reports what
       actually happened, along with the state of the one element that draws
       them, so the answer comes back as evidence rather than as a guess. */
    function onLogoCheck() {
        var table = window.VICE_MAKES;
        var panel = $('vehicle');
        var img = $('veh-logo');
        /* Name the missing piece. "page not ready" was true and useless: the
           three things it covers fail for completely different reasons, and the
           one that actually happens -- makes.js not being served, so the table
           never exists -- is invisible from the driver's seat because the HUD
           carries on working perfectly without it. */
        if (!table || !panel || !img) {
            post('logoReport', {
                fatal: !table ? 'no-table' : (!panel ? 'no-panel' : 'no-img')
            });
            return;
        }

        var keys = Object.keys(table.makes).filter(function (k) { return !!table.makes[k][1]; });
        var okCount = 0, failed = [], done = 0;
        var cs = window.getComputedStyle(img);
        var clip = $('veh-logo-clip');
        var clipRect = clip ? clip.getBoundingClientRect() : { width: 0, height: 0 };

        function finish() {
            post('logoReport', {
                total: keys.length,
                ok: okCount,
                // Only the first few: this goes to a console, not a log file.
                failed: failed.slice(0, 8),
                // Absolute, so the console shows exactly what the page asked the
                // resource for. A wrong prefix here is the whole answer.
                sampleUrl: new URL(table.makes[keys[0]][1], document.baseURI).href,
                badged: panel.classList.contains('badged'),
                src: img.getAttribute('src') || '',
                display: cs.display,
                opacity: cs.opacity,
                imgW: img.clientWidth,
                imgH: img.clientHeight,
                clipW: Math.round(clipRect.width),
                clipH: Math.round(clipRect.height)
            });
        }

        keys.forEach(function (k) {
            var probe = new Image();
            probe.onload = function () {
                okCount++;
                if (++done === keys.length) finish();
            };
            probe.onerror = function () {
                failed.push(k);
                if (++done === keys.length) finish();
            };
            probe.src = table.makes[k][1];
        });
        if (!keys.length) finish();
    }

    /* Roster walk (/hudbrand with no argument).
       Driven from here rather than from Lua because the table is here: the
       page holds the only copy and can therefore never walk a roster that has
       drifted from the marks it is actually drawing. Running it
       again stops the one in flight — two tours pushing at each other would
       just flicker. */
    var tourTimer = null;

    function onBrandTour(d) {
        if (tourTimer) { clearTimeout(tourTimer); tourTimer = null; onVehicle({ show: false }); return; }
        var table = window.VICE_MAKES;
        if (!table) return;
        var keys = Object.keys(table.makes).sort();
        var ms = d && d.ms > 0 ? d.ms : 4000;
        var i = 0;

        (function step() {
            if (i >= keys.length) { tourTimer = null; onVehicle({ show: false }); return; }
            var m = table.makes[keys[i++]];
            // The MARQUE on the model line, so the tour answers the question you
            // are actually asking of it: whose badge is this, and does it look
            // like the real-world one it is standing in for.
            onVehicle({ show: true, make: m[0], model: m[2],
                        fuel: 70, engineOn: true, engineHealth: 1000,
                        lockState: 'locked' });
            tourTimer = setTimeout(step, ms);
        }());
    }

    /* --- honor toast ----------------------------------------------------- */

    // Centre-screen change indicator. Separate from the corner panel: this is
    // the EVENT (honor just moved), the corner is the STATE (where it stands).
    var honorPopTimer = null;
    var honorHideTimer = null;

    function onHonorPop(delta, emoji, broken) {
        var el = $('honor-pop');
        if (!el || !delta) return;
        var sign = $('honor-pop-sign');
        var face = $('honor-pop-face');
        var crack = $('honor-pop-crack');

        if (broken) {
            // Broken isn't a direction -- no sign, and the face reads the
            // same grey/cracked way the corner badge does.
            el.className = 'broken';
            if (sign) sign.textContent = '';
            if (face) { face.textContent = emoji || '😈'; face.classList.add('broken'); }
            show(crack, true);
        } else {
            var up = delta > 0;
            el.className = up ? 'up' : 'down';
            if (sign) sign.textContent = up ? '+' : '−';
            if (face) { face.textContent = emoji || (up ? '😇' : '😈'); face.classList.remove('broken'); }
            show(crack, false);
        }

        show(el, true);
        if (honorPopTimer) clearTimeout(honorPopTimer);
        honorPopTimer = setTimeout(function () { show(el, false); }, 2200);
    }

    function onHonor(d) {
        // A change fires the centre indicator; the corner panel then just
        // reflects the current standing and stays put. Same trigger as
        // always (a real delta) -- broken only changes HOW it renders once
        // it fires (see onHonorPop): no sign, cracked face instead of a
        // coloured direction arrow.
        if (d.delta) {
            onHonorPop(d.delta, d.delta > 0 ? d.angelEmoji : d.devilEmoji, d.broken);
        }

        var el = $('honor');
        if (!el) return;
        var img = $('honor-img');
        if (img) {
            if (d.mugshot) { img.src = d.mugshot; img.style.display = 'block'; }
            else { img.removeAttribute('src'); img.style.display = 'none'; }
        }
        // The badge is the face for the CURRENT honor level, not for the change.
        var badge = $('honor-badge');
        if (badge) badge.textContent = d.emoji || '';

        // qbx_honor's unrepairable floor: once broken, always broken for this
        // session -- classList.toggle only ever turns this ON here because
        // the caller (ShowHonorToast/SetHonorStanding in client.lua) already
        // enforces the same one-way latch, so `d.broken` is never sent false
        // after having been sent true.
        if (d.broken) {
            if (badge) badge.classList.add('broken');
            show($('honor-crack'), true);
        }

        // With showValue off this is the reference treatment: the corner panel
        // is the mugshot and its face, nothing else. With it on the panel also
        // reads out the standing, which is the only place the exact number is
        // visible in game.
        var title = $('honor-title');
        if (title) {
            title.textContent = (d.showValue && typeof d.honor === 'number')
                ? ((d.valueLabel || 'HONOR') + ' ' + d.honor)
                : '';
        }

        var sub = $('honor-sub');
        if (sub) sub.textContent = (d.showValue && d.reason) ? d.reason : '';

        if (honorHideTimer) { clearTimeout(honorHideTimer); honorHideTimer = null; }

        if (d.show === false) { show(el, false); return; }

        show(el, true);

        // The panel is a readout you get when something happens, not furniture
        // parked in the corner all session. holdMs of 0 (or missing) keeps the
        // old behaviour of leaving it up until something hides it.
        var hold = typeof d.holdMs === 'number' ? d.holdMs : 0;
        if (hold > 0) {
            honorHideTimer = setTimeout(function () {
                honorHideTimer = null;
                // The layout editor forces every panel visible with sample
                // content; a timer left over from before it opened must not
                // yank this one back out from under it.
                if (editorOpen) return;
                show($('honor'), false);
            }, hold);
        }
    }

    /* --- reputation toast --------------------------------------------------
       Same EVENT/STATE split as honor above, minus the direction: reputation
       only ever goes up (qbx_reputation's tracks are floor-0), so the popup is
       a single "+N icon", not an up/down pair. */
    var reputationPopTimer = null;
    var reputationHideTimer = null;

    function onReputationPop(delta, icon) {
        var el = $('reputation-pop');
        if (!el || !delta) return;
        var sign = $('reputation-pop-sign');
        if (sign) sign.textContent = '+' + Math.abs(delta);
        var face = $('reputation-pop-face');
        if (face) face.textContent = icon || '';
        show(el, true);
        if (reputationPopTimer) clearTimeout(reputationPopTimer);
        reputationPopTimer = setTimeout(function () { show(el, false); }, 2200);
    }

    function onReputation(d) {
        if (d.delta) onReputationPop(d.delta, d.icon);

        var el = $('reputation');
        if (!el) return;

        var icon = $('reputation-icon');
        if (icon) icon.textContent = d.icon || '';

        // Same reference treatment as honor: with showValue off the panel is
        // just the icon and the track name, nothing else.
        var title = $('reputation-title');
        if (title) {
            var name = d.label || 'REPUTATION';
            title.textContent = (d.showValue && typeof d.value === 'number')
                ? (name + ' ' + d.value + (d.tier ? ' · T' + d.tier : ''))
                : name;
        }

        var sub = $('reputation-sub');
        if (sub) sub.textContent = (d.showValue && d.reason) ? d.reason : '';

        if (reputationHideTimer) { clearTimeout(reputationHideTimer); reputationHideTimer = null; }

        if (d.show === false) { show(el, false); return; }

        show(el, true);

        var hold = typeof d.holdMs === 'number' ? d.holdMs : 0;
        if (hold > 0) {
            reputationHideTimer = setTimeout(function () {
                reputationHideTimer = null;
                if (editorOpen) return;
                show($('reputation'), false);
            }, hold);
        }
    }

    /* --- action prompts -------------------------------------------------- */

    var PAD_TONE = { A: 'pad-a', B: 'pad-b', X: 'pad-x', Y: 'pad-y' };
    var prompts = {};

    function renderPrompts() {
        var box = $('prompts');
        if (!box) return;
        box.innerHTML = '';
        Object.keys(prompts).forEach(function (id) {
            var p = prompts[id];
            var row = document.createElement('div');
            row.className = 'prompt';

            var label = document.createElement('span');
            label.textContent = p.label || '';

            var g = document.createElement('span');
            var text = p.glyph == null ? '' : String(p.glyph);
            g.className = 'glyph'
                + (text.length > 1 ? ' wide' : '')
                + (p.device === 'pad' && PAD_TONE[text] ? ' ' + PAD_TONE[text] : '');
            g.textContent = text;

            row.appendChild(label);
            row.appendChild(g);
            box.appendChild(row);
        });
    }

    function onPrompt(d) {
        if (!d.id) return;
        if (d.show === false) delete prompts[d.id];
        else prompts[d.id] = { label: d.label, glyph: d.glyph, device: d.device };
        renderPrompts();
    }

    function onPromptGlyphs(d) {
        // Device or bindings changed — refresh labels on anything already shown.
        Object.keys(prompts).forEach(function (id) {
            if (d.glyphs && d.glyphs[id] != null) prompts[id].glyph = d.glyphs[id];
            if (d.device) prompts[id].device = d.device;
        });
        renderPrompts();
    }

    /* --- directional police glow ------------------------------------------ */

    var POL_EDGES = ['top', 'right', 'bottom', 'left'];

    // Keys map straight onto the CSS custom properties the lamp shapes and
    // sweep animation read (see the "Directional police glow" block in
    // style.css) — one entry point for both the live scan and the editor.
    var POL_VARS = {
        lampA: '--pol-lamp-a', lampB: '--pol-lamp-b', spread: '--pol-spread',
        sweepAmt: '--pol-sweep', softness: '--pol-softness', whiteA: '--pol-white-a',
        whiteLampA: '--pol-white-w', whiteLampB: '--pol-white-h'
    };

    var POL_RADIUS_VARS = ['rx', 'ry', 'bx', 'by', 'wx', 'wy'];

    function onPolice(d) {
        // Shared vars go on the document root rather than #police, because
        // #police-radius (the alternative render mode) is a SIBLING, not a
        // descendant, and would not inherit anything set on #police alone.
        var root = document.documentElement;
        if (d.flashMs) root.style.setProperty('--pol-flash', d.flashMs + 'ms');
        if (d.sweepMs) root.style.setProperty('--pol-sweep-ms', d.sweepMs + 'ms');
        Object.keys(POL_VARS).forEach(function (k) {
            if (d[k] != null) root.style.setProperty(POL_VARS[k], String(d[k]));
        });

        // Edges mode. When the payload is from radius mode there is no
        // `edges` field, so every edge's opacity naturally falls to 0 here —
        // no explicit mode check needed to keep the two visuals from
        // overlapping.
        var edges = d.edges || {};
        var box = $('police');
        if (box) box.classList.toggle('no-white', d.white === false);
        for (var i = 0; i < POL_EDGES.length; i++) {
            var name = POL_EDGES[i];
            var el = document.querySelector('.pol-' + name);
            if (!el) continue;
            var v = d.active === false ? 0 : (edges[name] || 0);
            el.style.opacity = String(Math.max(0, Math.min(1, v)));
        }

        // Radius mode. Same reasoning in reverse: with no `rx`/`strength`
        // fields from an edges-mode payload, this collapses to invisible.
        var radiusBox = $('police-radius');
        if (radiusBox) {
            radiusBox.classList.toggle('no-white', d.white === false);
            POL_RADIUS_VARS.forEach(function (k) {
                if (d[k] != null) radiusBox.style.setProperty('--pol-' + k, d[k] + '%');
            });
            var rv = d.active === false ? 0 : (d.strength || 0);
            radiusBox.style.opacity = String(Math.max(0, Math.min(1, rv)));
        }
    }

    /* --- police light editor (/hudpolice edit) ----------------------------- */
    /* One decimal for the small fractional sliders, whole numbers for
       everything else — matches what each range's step actually produces. */
    var POL_ED_DEC = { sweepAmt: 1, focus: 1 };

    var POL_ED_PCT = { customRx: 1, customRy: 1, customBx: 1, customBy: 1, customWx: 1, customWy: 1 };

    function polEdFormat(k, v) {
        if (k === 'flashMs' || k === 'sweepMs') return Math.round(v) + 'ms';
        if (k === 'maxOpacity' || k === 'whiteA') return Math.round(v * 100) + '%';
        if (k === 'maxDistance' || k === 'fullDistance') return Math.round(v) + 'm';
        if (k === 'previewAngle') return Math.round(v) + '°';
        if (POL_ED_PCT[k]) return Math.round(v) + '%';
        var dec = POL_ED_DEC[k] != null ? POL_ED_DEC[k] : 0;
        return v.toFixed(dec);
    }

    // Rows that only make sense in one mode. Everything else (brightness,
    // lamp shape, movement, detection) shapes all three modes identically, so
    // it stays visible no matter which is picked.
    var POL_MODE_ONLY = { radius: 'pol-ed-radius-only', custom: 'pol-ed-custom-only' };

    function setPoliceEditorMode(mode) {
        document.querySelectorAll('.pol-mode-btn').forEach(function (btn) {
            btn.classList.toggle('active', btn.getAttribute('data-mode') === mode);
        });
        Object.keys(POL_MODE_ONLY).forEach(function (m) {
            var cls = POL_MODE_ONLY[m];
            document.querySelectorAll('.' + cls).forEach(function (el) {
                el.style.display = (mode === m) ? '' : 'none';
            });
        });
    }

    function onPoliceEditor(d) {
        var panel = $('police-editor');
        if (!panel) return;
        show(panel, !!d.open);
        if (!d.open) return;
        var values = d.values || {};
        document.querySelectorAll('#pol-ed-body .pol-ed-row[data-k]').forEach(function (row) {
            var k = row.getAttribute('data-k');
            var input = row.querySelector('input');
            var out = row.querySelector('.pol-ed-val');
            var v = k === 'previewAngle' ? d.previewAngle : values[k];
            if (!input || v == null) return;
            input.value = String(v);
            if (out) out.textContent = polEdFormat(k, +v);
        });
        var white = $('pol-ed-white');
        if (white) white.checked = values.white !== false;
        setPoliceEditorMode(values.mode === 'radius' || values.mode === 'custom' ? values.mode : 'edges');
    }

    document.addEventListener('DOMContentLoaded', function () {
        document.querySelectorAll('#pol-ed-body .pol-ed-row[data-k]').forEach(function (row) {
            var k = row.getAttribute('data-k');
            var input = row.querySelector('input');
            var out = row.querySelector('.pol-ed-val');
            if (!input) return;
            input.addEventListener('input', function () {
                var v = +input.value;
                if (out) out.textContent = polEdFormat(k, v);
                // previewAngle is a testing aid, not a saved setting — it has
                // its own endpoint so it never ends up written to the KVP.
                if (k === 'previewAngle') post('policePreviewAngle', { angle: v });
                else post('policeTune', { key: k, value: v });
            });
        });
        var whiteBox = $('pol-ed-white');
        if (whiteBox) whiteBox.addEventListener('change', function () {
            post('policeTune', { key: 'white', value: whiteBox.checked });
        });
        document.querySelectorAll('.pol-mode-btn').forEach(function (btn) {
            btn.addEventListener('click', function () {
                var mode = btn.getAttribute('data-mode');
                setPoliceEditorMode(mode);
                post('policeMode', { mode: mode });
            });
        });
        var b;
        if ((b = $('pol-ed-reset'))) b.addEventListener('click', function () {
            post('policeReset', {}, function (values) { onPoliceEditor({ open: true, values: values }); });
        });
        if ((b = $('pol-ed-close'))) b.addEventListener('click', function () {
            post('policeEditorClose', {});
            show($('police-editor'), false);
        });
    });

    /* --- exhaustion vignette ---------------------------------------------- */

    function onExhaustion(d) {
        var el = $('exhaust');
        if (!el) return;
        var lvl = Math.max(0, Math.min(1, d.level || 0));
        el.style.opacity = String(Math.max(0, Math.min(1, d.vignette || 0)));
        if (d.pulseMs) el.style.setProperty('--exhaust-pulse', d.pulseMs + 'ms');

        // Close the aperture as exhaustion climbs — the clear centre shrinks
        // from 74%/68% down to 40%/34%, so the edges visibly creep inward
        // rather than the screen merely getting darker.
        el.style.setProperty('--exhaust-w', (74 - 34 * lvl).toFixed(1) + '%');
        el.style.setProperty('--exhaust-h', (68 - 34 * lvl).toFixed(1) + '%');

        // Only breathe once genuinely winded, so a light jog doesn't throb.
        el.classList.toggle('breathing', lvl > 0.55);
        // Past the point of no return it starts costing health — a harder,
        // faster pulse marks that threshold so it isn't a silent penalty.
        el.classList.toggle('critical', lvl >= 0.995);
    }

    /* --- offset preference ----------------------------------------------- */

    function onOffset(d) {
        if (stage) stage.style.setProperty('--hud-offset-x', (d.x || 0) + 'px');
    }

    /* --- HUD editor offsets ------------------------------------------------ */

    function onLayout(d) {
        if (!stage || !d.offsets) return;
        offsets = asOffsetMap(d.offsets);
        // Must go through applyOffsets: an earlier version wrote only the two
        // --off-* translation vars here, so every saved SCALE was dropped the
        // moment Lua pushed the layout back (which it does on save, on reset
        // and on resource start). That made scaling look like it did nothing.
        applyOffsets(true);
    }

    /* --- HUD editor -------------------------------------------------------- */

    /* [key, label, selector, description, group]
       `group` only drives the headings in the list. Grouping matters here
       because the three kinds behave differently and used to be shuffled
       together: page elements are pure CSS, the minimap rows are forwarded to
       the engine, and the last two live in other resources entirely. */
    var EDITOR_ELEMENTS = [
        ['status',   'Status bars',    '#status',    'health / stamina, top-left',      'HUD'],
        ['topright', 'Wanted stars',   '#topright',  'stars (also moves ammo/tells/money together)', 'HUD'],
        ['tells',    'Wanted tells',   '#tells',     'the five round tell icons',       'HUD'],
        // Its own row, separate from the wanted stars above. It previously
        // shared #topright's position (and its Font/Icon size rows), which
        // meant nudging the ammo readout also nudged the stars.
        ['ammo',     'Ammo',           '#ammo-wrap', 'clip/reserve numbers + weapon icon', 'HUD'],
        ['money',    'Money',          '#money',     'cash and bank',                   'HUD'],
        ['slots',    'Map panels',     '#slots',     'both panels together',            'HUD'],
        /* The two panels are separate elements as well as being movable
           together. They are different kinds of text — a place name that can be
           long, and a make/model set in wide caps — and sharing one font, size
           and weight meant tuning either one to fit wrecked the other. `slots`
           still moves and scales the pair. */
        ['vehicle',  'Vehicle panel',  '#vehicle',   'make + model (upper panel)',      'HUD'],
        ['zone',     'Zone bar',       '#zone',      'place name (lower panel)',        'HUD'],
        // The pip row is its own element rather than something the vehicle
        // panel scales. Scaling it from the panel grew the three discs and left
        // the gap between them alone, which is the "wonky" — the icons need
        // their own spacing, position and scale to stay a proportionate row.
        ['vehpips',  'Vehicle icons',  '#veh-pips',  'lock / engine / fuel pips',       'HUD'],
        /* The manufacturer badge is its own element for the same reason the pip
           row is: it is behind the names rather than part of them, and the two
           things people will want from it — how big it is and how strongly it
           shows — are settings the panel itself has no row for. Opacity
           multiplies the shipped 0.42, so 1.00 is the design as drawn and
           anything below it fades the mark back. */
        ['vehlogo',  'Vehicle badge',  '#veh-logo',  'manufacturer mark behind the names', 'HUD'],
        ['wanted',   'Wanted box',     '#wanted',    '"cops are searching for you"',    'HUD'],
        ['honor',    'Honor standing', '#honor',     'mugshot + current honor face',    'HUD'],
        ['honorpop', 'Honor +/- popup', '#honor-pop', 'centre-screen change indicator', 'HUD'],
        ['reputation',    'Reputation standing', '#reputation',     'icon + current track value', 'HUD'],
        ['reputationpop', 'Reputation +N popup', '#reputation-pop', 'centre-screen change indicator', 'HUD'],
        ['prompts',  'Action prompts', '#prompts',   'bottom-right prompts',            'HUD'],
        ['skillup',  'Skill level-up', '#skillup',   'the card shown when a skill levels', 'HUD'],
        // No box of its own -- a full-screen vignette, not a positioned
        // panel -- so Position/Width/Height/Font rows are dropped for it in
        // NO_ROWS below and all it offers are its three custom rows.
        ['focusfx',  'Focus screen effect', '#focus-fx', 'vignette + pulse while Focus is active', 'HUD'],
        // The native minimap is drawn by the ENGINE, not this page — arrows are
        // forwarded to Lua, which re-applies SetMinimapComponentPosition and
        // rebuilds the scaleform. The frame is ours, but it belongs beside them.
        ['mapframe',    'Minimap frame',    '#map-frame', 'outline around the map',            'Minimap'],
        // Purely decorative -- no game state toggles it -- so unlike every
        // other row here it has nothing driving it besides the editor.
        ['mapbadge',    'Map badge',        '#map-badge', 'glyph in the map\'s top-left corner', 'Minimap'],
        // Own row rather than riding on mapframe: it is a text bar, not an
        // outline, and only ever shows while a waypoint is set — Reset/Save
        // still has to reach it even when nobody happens to have one right now.
        ['navpopup',    'Nav popup',        '#nav-popup', 'turn-by-turn bar shown above the map near a turn', 'Minimap'],
        ['navcompass',  'Nav distance',     '#nav-compass', 'the remaining-distance figure on the map', 'Minimap'],
        ['minimap',     'Minimap position', null, 'arrows move the native map',                'Minimap'],
        ['minimapsize', 'Minimap size',     null, 'left/right = width, up/down = height',      'Minimap'],
        // These live in OTHER resources (speedlimits / zseatbelt), each with its
        // own NUI page — CSS can't reach across, so vice_hud stores the offset
        // and those resources apply it to their own page.
        ['speedlimit', 'Speed limit sign', null, 'from the speedlimits resource', 'Other resources'],
        ['seatbelt',   'Seatbelt icon',    null, 'from the zseatbelt resource',   'Other resources'],
        // Notifications are drawn on ox_lib's OWN page, which this page cannot
        // reach with CSS. The values go to Lua, which puts them in a state bag
        // that a hook inside ox_lib reads — so one row here moves the popups of
        // every resource on the server at once.
        ['notify',     'Notifications',    null, 'ox_lib popups, from every resource', 'Other resources']
    ];

    // Elements the engine owns; nudges go to Lua rather than to CSS.
    var NATIVE_ELEMENTS = { minimap: 'move', minimapsize: 'size' };

    // Elements another resource draws, tuned by corner + nudge rather than CSS.
    var NOTIFY_ELEMENTS = { notify: 1 };

    /* Everything tunable per element. Each writes one CSS custom property on
       .stage; style.css reads it with the ORIGINAL value as the var() fallback,
       so an unset property renders exactly as designed. `def: null` means
       "leave the stylesheet alone" rather than a number. */
    /* The first four are SHIPPED with the resource, so they render the same for
       every player. The rest are whatever the player's OS provides and will
       differ machine to machine — fine for a personal tweak, a poor choice for
       anything you intend to /hudpublish. */
    var FONTS = [
        [null,                                    'Default'],
        ["'HelveticaNeueHUD', 'Helvetica Neue', sans-serif", 'Helvetica'],
        ["'GTAArtDeco', 'HelveticaNeueHUD', sans-serif",     'GTA Art Deco'],
        ["'Pricedown', sans-serif",               'Pricedown'],
        ['system-ui, sans-serif',                 'System'],
        ['Arial, Helvetica, sans-serif',          'Arial'],
        ["'Segoe UI', system-ui, sans-serif",     'Segoe UI'],
        ['Verdana, Geneva, sans-serif',           'Verdana'],
        ["'Trebuchet MS', system-ui, sans-serif", 'Trebuchet'],
        ["'Franklin Gothic Medium', Arial, sans-serif", 'Franklin Gothic'],
        ['Impact, Haettenschweiler, sans-serif',  'Impact'],
        ['Georgia, "Times New Roman", serif',     'Georgia'],
        ['Consolas, "Courier New", monospace',    'Monospace']
    ];
    /* Weight is only honest where a REAL cut exists. Thin (100/200), Roman
       (400), Medium (500) and Bold (700) are installed in html/fonts; anything
       else is synthesised, and a synthesised light in particular is the ragged,
       pixelated-looking text people blame on the screen. Art Deco has Regular
       and Medium, so 400 and 500+ are real there too.
       Add a weight here only alongside a real .otf/.ttf and an @font-face. */
    var WEIGHTS = [
        [null, 'Default'],
        [100, '100 Thin'],
        [200, '200 Thin'],
        [400, '400 Roman'],
        [500, '500 Medium'],
        [700, '700 Bold']
    ];

    /* Text alignment. The stored value is the text-align keyword; style.css
       also wants a flex keyword for the same intent, and FLEX_ALIGN is the
       translation. Both are written in applyOffsets — see the note there. */
    var ALIGN = [
        [null,     'Default'],
        ['left',   'Left'],
        ['center', 'Center'],
        ['right',  'Right']
    ];
    var FLEX_ALIGN = { left: 'flex-start', center: 'center', right: 'flex-end' };

    /* How glyph edges are rasterised. Hardcoded to `antialiased` for the whole
       page before this; which setting looks best depends on the display, so it
       is the player's call rather than the stylesheet's. */
    var SMOOTHING = [
        [null,          'Default'],
        ['auto',        'Subpixel'],
        ['antialiased', 'Grayscale'],
        ['none',        'Hard edges']
    ];

    /* About min / max.
       These are GUARD RAILS, not opinions. Every one of them used to be a taste
       judgement, and taste judgements in a tuning tool are just walls: Width
       stopped at 3.0, which is not enough to fit the minimap frame onto a map
       that has itself been scaled up, and there was nothing inside the editor
       that could get past it.

       So anything that is a matter of taste now runs far past any plausible
       use, and what is left is the point where the element stops existing in a
       recoverable way — a scale of zero collapses it to nothing, an offset of
       five screens puts it somewhere you cannot see to drag it back.

       The one real exception is Opacity: CSS clamps it to 1 itself, so a bigger
       number here would be a control that silently does nothing.

       The ceilings matter less than this, though: every numeric row can now be
       TYPED into. Stepping to 12.0 at 0.05 a click was never going to happen. */
    var SC_MIN = 0.01, SC_MAX = 50;

    var PROPS = [
        { k: 'fs',  label: 'Font size',      v: '--fs-',    def: 1,    step: 0.05,  min: 0.02, max: 50,  dec: 2 },
        { k: 'ic',  label: 'Icon size',      v: '--ic-',    def: 1,    step: 0.05,  min: 0.02, max: 50,  dec: 2,
          hint: 'Changes the icons’ real SIZE, so the panel around them grows to '
              + 'fit. Prefer this over Width/Height for making icons bigger — '
              + 'Width/Height only scales how they are PAINTED.' },
        { k: 'ff',  label: 'Font',           v: '--ff-',    def: null, list: FONTS },
        { k: 'fw',  label: 'Font weight',    v: '--fw-',    def: null, list: WEIGHTS },
        { k: 'sm',  label: 'Font smoothing', v: '--sm-',    def: null, list: SMOOTHING,
          hint: 'How glyph edges are rasterised. If text looks rough, try each — '
              + 'which one wins depends on your display.' },
        { k: 'ls',  label: 'Letter spacing', v: '--ls-',    def: 0,    step: 0.005, min: -2,   max: 10,  dec: 3, unit: 'em' },
        { k: 'al',  label: 'Text align',    v: '--al-',    def: null, list: ALIGN },
        /* A CSS transform, which means it changes how the element is PAINTED and
           not the box it occupies. Nothing around it moves out of the way, and
           an ancestor that clips (the map panels do -- .slot sets
           overflow: hidden so a child's square corners cannot escape the
           plate's rounded ones) will cut off whatever now paints outside it.
           That is not a bug to fix here: scaling in place is exactly what these
           two are for. It IS worth saying on the row, because "Width" and
           "Icon size" both read as "make it bigger" and only one of them makes
           room for the result. */
        { k: 'sx',  label: 'Width',          v: '--sc-',    def: 1,    step: 0.05,  min: SC_MIN, max: SC_MAX, dec: 2, suffix: '-x',
          hint: 'Scales how the element is PAINTED, in place — the space it takes '
              + 'up does not change. To make something bigger AND push its '
              + 'neighbours out of the way, use Font size or Icon size instead.' },
        { k: 'sy',  label: 'Height',         v: '--sc-',    def: 1,    step: 0.05,  min: SC_MIN, max: SC_MAX, dec: 2, suffix: '-y',
          hint: 'Scales how the element is PAINTED, in place — the space it takes '
              + 'up does not change. To make something bigger AND push its '
              + 'neighbours out of the way, use Font size or Icon size instead.' },
        { k: 'op',  label: 'Opacity',        v: '--op-',    def: 1,    step: 0.05,  min: 0,    max: 1,   dec: 2 },
        { k: 'rad', label: 'Corner radius',  v: '--rad-',   def: 1,    step: 0.1,   min: 0,    max: 100, dec: 2 },
        /* Multiplier on the gap between an element's own children. Size alone
           could never produce a proportionate stack: scale the icons up and the
           spacing between them stayed where it was, so the row read as crowded
           however good the icon size was. */
        { k: 'sp',  label: 'Spacing',        v: '--sp-',    def: 1,    step: 0.05,  min: 0,    max: 50,  dec: 2,
          hint: 'Multiplies the gap between this element’s own children. '
              + 'Scaling icons without it is what makes a row look crowded.' },

        /* ---- the panel stack's own geometry --------------------------------
           `only: { slots: 1 }` — these are offered on Map panels and nowhere
           else. `panel: true` keeps them out of the CSS-writing loop in
           applyOffsets: everything else there writes one custom property from
           its own `v` prefix, while these three are applied together by
           applyPanelRect, which has to weigh them against the map rect and the
           snapshot before it can know what to write.

           Unset means "use the snapshot" rather than a number, which is why
           `def` is null on all four. A default of, say, 1.75 would be a lie the
           moment anyone moved their minimap. */
        { k: 'pl',  label: 'Panel left',   def: null, step: 0.25, min: -500, max: 500, dec: 2, panel: true, only: { slots: 1 },
          hint: 'Left edge of the two map panels, in % of screen width. '
              + 'Unset follows the minimap as it was when you spawned.' },
        { k: 'pw',  label: 'Panel width',  def: null, step: 0.25, min: 0.01, max: 500, dec: 2, panel: true, only: { slots: 1 },
          hint: 'Width of the two map panels, in % of screen width. '
              + 'Set this and resizing the minimap will not touch them.' },
        { k: 'pb',  label: 'Panel bottom', def: null, step: 0.25, min: -500, max: 500, dec: 2, panel: true, only: { slots: 1 },
          hint: 'Distance from the bottom of the screen to the BOTTOM of the '
              + 'panel stack, in % of screen height. The stack grows upward.' },
        /* The way back to the old behaviour, kept because "sit on the map and
           stay there" and "sit on the map and follow it" are both reasonable
           and only one of them can be the default. Stored as 1/null rather than
           true/false so it round-trips through Lua's json as a number like
           every other value in the layout. */
        { k: 'pfollow', label: 'Follow map', def: null, panel: true, only: { slots: 1 },
          list: [[null, 'No — stay put'], [1, 'Yes — track the map']],
          hint: 'Off: the panels keep the position they had when you spawned, '
              + 'whatever the minimap does afterwards. On: they track the map '
              + 'live, which is what this HUD did before.' },

        /* ---- the focus vignette's own tuning -------------------------------
           `only: { focusfx: 1 }` — same opt-in pattern as the panel trio
           above. Position/scale/font rows mean nothing for a full-screen
           effect with no box, so those are dropped for this element in
           NO_ROWS instead of offered and doing nothing. */
        { k: 'fxstrength', label: 'Vignette strength', v: '--fxstrength-', def: 1, step: 0.1, min: 0, max: 3, dec: 2, only: { focusfx: 1 },
          hint: 'Multiplies how dark and how far the vignette reaches. 1.00 is '
              + 'shipped strength; 0 turns the vignette itself off while the '
              + 'pulse and bar keep working.' },
        { k: 'fxpulse', label: 'Pulse size', v: '--fxpulse-', def: 1, step: 0.1, min: 0, max: 4, dec: 2, only: { focusfx: 1 },
          hint: 'Multiplies the pulse\'s brightness swing AND how much it visibly '
              + 'grows each beat. 0 is a flat, non-pulsing vignette.' },
        { k: 'fxspeed', label: 'Pulse speed', v: '--fxspeed-', def: 1100, step: 50, min: 200, max: 4000, dec: 0, unit: 'ms', only: { focusfx: 1 },
          hint: 'How long one pulse takes, in milliseconds. Lower is faster.' },

        /* ---- the nav bar's own tuning --------------------------------------
           `only: { navpopup: 1 }`, same opt-in as the two groups above.

           Bar height is its own row because the nav bar is built off a single
           --nav-h: the bar, the square turn tile and the type all size off
           it, so this is the one control that grows the whole bar as a unit.
           The generic Width/Height rows only scale how it is PAINTED and
           would squash the tile out of square. */
        { k: 'navbar', label: 'Bar height', v: '--sc-navbar', def: 1, step: 0.05, min: 0.2, max: 4, dec: 2, only: { navpopup: 1 }, raw: true,
          hint: 'Grows the whole nav bar as a unit — height, the turn tile and '
              + 'the text together. Use this rather than Width/Height, which '
              + 'only rescale how it is painted.' },
        { k: 'navaccent', label: 'Turn tile colour', v: '--nav-accent', def: null, only: { navpopup: 1 }, raw: true,
          list: [[null, 'Default — mint'], ['#6fd5c3', 'Mint'], ['#57c8f5', 'Sky'],
                 ['#f5c451', 'Amber'], ['#f2795f', 'Coral'], ['#b48cf0', 'Violet'],
                 ['#8bd45f', 'Lime'], ['#ffffff', 'White']],
          hint: 'The colour of the square turn tile at the right of the bar.' },
        { k: 'navbg', label: 'Bar colour', v: '--nav-bg', def: null, only: { navpopup: 1 }, raw: true,
          list: [[null, 'Default — charcoal'], ['rgba(35,37,46,0.95)', 'Charcoal'],
                 ['rgba(18,19,24,0.95)', 'Near black'], ['rgba(24,32,48,0.95)', 'Navy'],
                 ['rgba(40,32,48,0.95)', 'Plum'], ['rgba(0,0,0,0.72)', 'Translucent']],
          hint: 'The dark bar behind the instruction text.' }
    ];
    /* Position was arrow-keys-only, which made it the one thing you could not
       do with the mouse and the one thing with no readable current value in the
       settings column. It is the same offsets[key].x / .y the arrows write, so
       the two stay in step automatically. Kept out of PROPS because PROPS is
       also the loop that writes CSS custom properties, and x/y are applied as
       the translate instead. */
    var POS_MAX = 500;
    var POS_PROPS = [
        { k: 'x', label: 'Position X', def: 0, step: 0.1, min: -POS_MAX, max: POS_MAX, dec: 2, pos: true },
        { k: 'y', label: 'Position Y', def: 0, step: 0.1, min: -POS_MAX, max: POS_MAX, dec: 2, pos: true }
    ];

    var propSel = 0;

    /* The minimap is drawn by the ENGINE, so none of the CSS properties above
       apply to it. It gets its own list instead, sent up from client.lua with
       real current values. Everything here used to be reachable only through
       chat commands, which put the fiddliest part of the HUD outside the tool
       built for fiddling. */
    var NATIVE_PROPS = [
        { k: 'cropT',  label: 'Crop top',    step: 5,    min: 0,     max: 2000,  dec: 0 },
        { k: 'cropB',  label: 'Crop bottom', step: 5,    min: 0,     max: 2000,  dec: 0 },
        { k: 'cropL',  label: 'Crop left',   step: 5,    min: 0,     max: 2000,  dec: 0 },
        { k: 'cropR',  label: 'Crop right',  step: 5,    min: 0,     max: 2000,  dec: 0 },
        { k: 'blipX',  label: 'Blip X',      step: 4,    min: -5000, max: 5000,  dec: 0,
          hint: 'Moves the map PLANE inside its window. Use it to centre the player arrow.' },
        { k: 'blipY',  label: 'Blip Y',      step: 4,    min: -5000, max: 5000,  dec: 0,
          hint: 'Moves the map PLANE inside its window. Use it to centre the player arrow.' },
        { k: 'scaleW', label: 'Map width',   step: 0.02, min: 0.01,  max: 20,    dec: 3,
          hint: 'Scales the map, its mask and its blur TOGETHER. This is "make the minimap bigger".' },
        { k: 'scaleH', label: 'Map height',  step: 0.02, min: 0.01,  max: 20,    dec: 3,
          hint: 'Scales the map, its mask and its blur TOGETHER. This is "make the minimap bigger".' },
        /* The plane on its own. Map width / height above scale the map, mask
           and blur as one, so they cannot change the plane's ASPECT relative to
           its window — and a plane with the wrong aspect is what draws a radius
           blip's circle as an oval. These two are the only control that can.
           Long-standing values (/hudblip size), persisted and printed by
           /mapinfo, that simply had no row here. */
        { k: 'blipW',  label: 'Plane width', step: 4,    min: -5000, max: 5000,  dec: 0,
          hint: 'Stretches the map plane ONLY, leaving the mask window where it is. '
              + 'This is what makes a squashed radius circle round again.' },
        { k: 'blipH',  label: 'Plane height',step: 4,    min: -5000, max: 5000,  dec: 0,
          hint: 'Stretches the map plane ONLY, leaving the mask window where it is. '
              + 'This is what makes a squashed radius circle round again.' },
        /* The blur component. It had no rows at all, which made it the one part
           of the minimap you could not touch — and on the shipped config it is
           1.6x the size of the map component, a ratio every scale preserves
           because all three are multiplied together. When the drawn map turns
           out to fill the BLUR rect while blips clip to the MAP rect, closing
           that gap is the fix and this is the only way to do it. /hudrects
           shows which rect the map is actually sitting on; /hudmatch does the
           arithmetic. */
        { k: 'blurX',  label: 'Blur X',      step: 4,    min: -5000, max: 5000,  dec: 0,
          hint: 'The minimap_blur component. Run /hudrects — if the drawn map '
              + 'fills the YELLOW outline rather than the green one, this is the '
              + 'rect that is really deciding how big the map looks.' },
        { k: 'blurY',  label: 'Blur Y',      step: 4,    min: -5000, max: 5000,  dec: 0,
          hint: 'The minimap_blur component. See Blur X.' },
        { k: 'blurW',  label: 'Blur width',  step: 4,    min: -5000, max: 5000,  dec: 0,
          hint: 'The minimap_blur component. See Blur X.' },
        { k: 'blurH',  label: 'Blur height', step: 4,    min: -5000, max: 5000,  dec: 0,
          hint: 'The minimap_blur component. See Blur X.' },
        /* Not a 2D/3D switch, and deliberately not labelled as one. GTA draws
           the radar as a tilted plane in its own renderer; nothing reachable
           from here flattens that. Zoom changes how MUCH of the plane you see,
           which is what actually decides whether it reads flat or skewed. */
        /* Vanilla map information. These are not vice_hud drawing something of
           its own — they are GTA's own map furniture, which this resource was
           suppressing with no setting behind it. */
        { k: 'north',  label: 'North marker', step: 1,   min: 0,     max: 1,     dec: 0,
          names: ['hidden', 'shown'],
          hint: 'GTA’s north indicator on the map edge. vice_hud used to hide it '
              + 'unconditionally; vanilla shows it.' },
        { k: 'blipScale', label: 'Player arrow', step: 0.05, min: 0, max: 8,     dec: 2,
          hint: 'Size of your own blip. 0 leaves GTA’s alone. The arrow does NOT '
              + 'scale with the map, so a resized minimap needs this to keep the '
              + 'proportion vanilla had.' },
        { k: 'zoom',   label: 'Radar zoom',  step: 25,   min: 0,     max: 1500,  dec: 0,
          hint: 'How far the radar is zoomed in. 0 leaves GTA’s own zoom alone. '
              + 'Pulled in you see the flat middle of the map; pulled out you see '
              + 'its steeply-angled far edge, which is what reads as "3D".' },
        { k: 'nudgeX', label: 'Map X',       step: 4,    min: -20000, max: 20000, dec: 0 },
        { k: 'nudgeY', label: 'Map Y',       step: 4,    min: -20000, max: 20000, dec: 0 },
        { k: 'rectL',  label: 'Panel left',  step: 0.25, min: -500,  max: 500,   dec: 2 },
        { k: 'rectW',  label: 'Panel width', step: 0.25, min: 0.01,  max: 500,   dec: 2 },
        { k: 'rectB',  label: 'Panel bottom',step: 0.25, min: -500,  max: 500,   dec: 2 },
        { k: 'rectH',  label: 'Panel height',step: 0.25, min: 0.01,  max: 500,   dec: 2 },
        // Corner radius, as a percentage of the mask's height.
        //
        // Stepped rather than continuous because the rounding lives in the mask
        // TEXTURE and the engine cannot build one at runtime -- each step is a
        // pre-baked file in stream/ (see tools/make_masks.py). Lua snaps
        // whatever it is sent to the nearest baked step and reports the snapped
        // value back, so this row always shows a radius that really exists.
        { k: 'radius',   label: 'Corner radius',   step: 4, min: 0, max: 50, dec: 0,
          unitLabel: '%' },
        // Toggles, stepped like numbers so one control type covers everything.
        // 'Custom mask' off means GTA's own square-cornered mask, where the
        // radius above has nothing to act on.
        { k: 'rounded',  label: 'Custom mask',     step: 1, min: 0, max: 1, dec: 0,
          names: ['stock', 'custom'] },
        { k: 'maskMap',  label: 'Mask = map',      step: 1, min: 0, max: 1, dec: 0,
          names: ['qbx crop', 'full map'] },
        /* The same idea as Mask = map, for the component that turns out to
           decide the map's DRAWN size. The arrow and every radius blip are
           drawn on the plane, so a blur that is a different rect puts the arrow
           off centre and stops radius blips at an invisible edge. `follows map`
           recomputes it from the plane on every apply, so resizing later cannot
           pull them apart again. */
        { k: 'blurMap',  label: 'Blur = map',      step: 1, min: 0, max: 1, dec: 0,
          names: ['own rect', 'follows map'],
          hint: 'The blur component decides how big the map is DRAWN, while the '
              + 'arrow and radius blips are drawn on the plane. Following the map '
              + 'keeps them the same rect at every scale.' }
    ];

    // Mirror of the engine-side values, refreshed from every callback reply so
    // the panel can never drift from what the map is actually doing.
    var nativeVals = {};

    /* Notifications get a CORNER plus a nudge, not a free position: ox_lib
       anchors its notification stack to one of eight points and the offset is
       measured from there. Picking the corner first is also what keeps a
       placement sane at every aspect ratio — the corner does the work, the
       nudge is the fine tuning. */
    var NOTIFY_ANCHORS = [
        ['top-left',     'Top left'],
        ['top',          'Top centre'],
        ['top-right',    'Top right'],
        ['center-left',  'Left'],
        ['center-right', 'Right'],
        ['bottom-left',  'Bottom left'],
        ['bottom',       'Bottom centre'],
        ['bottom-right', 'Bottom right']
    ];
    /* def is 'top-right', not null: that is where ox_lib puts notifications
       when nobody has said otherwise, so an unset row should READ as Top right
       rather than as a meaningless "Default" that steps somewhere unrelated. */
    var NOTIFY_PROPS = [
        { k: 'anchor', label: 'Corner', def: 'top-right', list: NOTIFY_ANCHORS }
    ].concat(POS_PROPS);

    // Keys that are neither a CSS property nor a position, and so are not in
    // PROPS — but still have to survive the trip to Lua.
    var EXTRA_KEYS = ['anchor'];

    /* Money is Pricedown and stays Pricedown — GTA's own display face, and the
       one piece of this HUD whose identity is the typeface. So it gets no Font
       row at all, rather than a row that can be set to something the design
       does not want. Weight, size and the rest are still tunable. */
    var NO_FONT_ROW = { money: 1 };

    /* Rows that would be dead controls on a given element. The badge is an
       IMAGE: a font, a weight, letter spacing, text alignment, glyph smoothing
       and a corner radius have nothing to act on, and a row that visibly does
       nothing is worse than no row -- it reads as a bug in the editor. What it
       keeps is what an image actually has: where it sits, how big it is, and
       how strongly it shows. */
    var NO_ROWS = {
        vehlogo: { ff: 1, fw: 1, sm: 1, ls: 1, al: 1, fs: 1, ic: 1, rad: 1, sp: 1 },
        mapbadge: { ff: 1, fw: 1, sm: 1, ls: 1, al: 1, fs: 1, ic: 1, rad: 1, sp: 1 },
        // A full-screen effect has no box: nothing here has a font, a
        // position, or a width/height to speak of. Only the three fx* rows
        // this element actually owns are left standing.
        focusfx: { ff: 1, fw: 1, sm: 1, ls: 1, al: 1, fs: 1, ic: 1, rad: 1, sp: 1,
                    sx: 1, sy: 1, op: 1, x: 1, y: 1 }
    };

    /* ---- inheritance, made explicit ---------------------------------------
       Three elements sit INSIDE the map panel stack and, for a handful of
       properties, style.css reads the child's variable with the PARENT's as the
       fallback:

           font-family: var(--ff-zone, var(--ff-slots, inherit));

       So an untouched Zone bar takes its font from Map panels, and setting the
       Zone bar's own font silently detaches it. That is a good default and it
       was completely invisible: nothing in the editor said the value you were
       looking at came from somewhere else, and the only way back was to guess
       that "Reset this" would re-attach it.

       PARENT_OF/INHERITS name the eleven declarations that actually do this, so
       each of those rows can carry a Follow/Own switch. The list is not a
       guess — it is every `var(--x-child, var(--x-parent` in style.css. If you
       add another such fallback there, add it here too or the row will keep
       detaching silently.

       Follow  -> the stored value is deleted, and CSS falls through to the
                  parent. This is exactly what an untouched element already did.
       Own     -> the value is SEEDED from whatever the row is rendering right
                  now and written explicitly, so switching to Own never changes
                  what you are looking at. It just stops the parent moving it. */
    var INHERITS = {
        zone:    { parent: 'slots', props: { ff: 1, fs: 1, fw: 1, ls: 1 } },
        vehicle: { parent: 'slots', props: { ff: 1, fs: 1, fw: 1, ls: 1 } },
        vehpips: { parent: 'slots', props: { ic: 1, fs: 1 } }
    };

    /* An element's display label, so the Follow tooltip can name the parent it
       is following rather than saying "the parent". */
    function labelOf(key) {
        for (var i = 0; i < EDITOR_ELEMENTS.length; i++) {
            if (EDITOR_ELEMENTS[i][0] === key) return EDITOR_ELEMENTS[i][1];
        }
        return key;
    }

    function inheritsProp(key, pk) {
        var inh = INHERITS[key];
        return !!(inh && inh.props[pk]);
    }

    /* Is this row currently taking its value from the parent? Absence of a
       stored value IS the following state — there is no separate flag, because
       a flag could disagree with the CSS and then one of the two would be
       lying. */
    function isFollowing(key, pk) {
        if (!inheritsProp(key, pk)) return false;
        var o = offsets[key];
        return !o || o[pk] === undefined || o[pk] === null;
    }

    /* What the row shows while it is following: the parent's value if the
       parent has one, otherwise the property's shipped default. */
    function inheritedValue(key, p) {
        var inh = INHERITS[key];
        var po = (inh && offsets[inh.parent]) || {};
        var pv = po[p.k];
        return (pv === undefined || pv === null) ? p.def : pv;
    }

    function setFollow(key, p, follow) {
        offsets[key] = offsets[key] || { x: 0, y: 0 };
        if (follow) {
            delete offsets[key][p.k];
        } else {
            // Seed from what is on screen, so Own is a no-op until you change
            // something. Detaching an element and having it jump at the same
            // moment would make the switch feel like it did two things.
            offsets[key][p.k] = inheritedValue(key, p);
        }
        applyOffsets(); renderEditor();
    }

    // The engine-owned rows already carry their own position and size fields
    // (Map X / Map Y / Map width / Map height), so they do not get POS_PROPS.
    function propsFor(key) {
        if (NATIVE_ELEMENTS[key]) return NATIVE_PROPS;
        if (NOTIFY_ELEMENTS[key]) return NOTIFY_PROPS;
        var list = POS_PROPS.concat(PROPS);
        if (NO_FONT_ROW[key]) list = list.filter(function (p) { return p.k !== 'ff'; });
        // `only` is opt-IN: a prop that carries one is offered on those
        // elements alone. Props without one are offered everywhere, which is
        // every prop but Brand tint.
        list = list.filter(function (p) { return !p.only || p.only[key]; });
        var drop = NO_ROWS[key];
        if (drop) list = list.filter(function (p) { return !drop[p.k]; });
        return list;
    }

    function propOf(k) {
        for (var i = 0; i < PROPS.length; i++) if (PROPS[i].k === k) return PROPS[i];
        return null;
    }
    function valueOf(o, p) {
        var raw = o[p.k];
        if (raw === undefined) {
            // sx/sy fall back to the legacy uniform `s`.
            if ((p.k === 'sx' || p.k === 'sy') && o.s != null) return o.s;
            return p.def;
        }
        return raw;
    }
    /* Show a number at its DESIGNED precision when it is sitting on it, and at
       full precision when it is not.
       A flat toFixed(p.dec) was fine while every value came from a step, but a
       typed 1.4375 would have been displayed as "1.44" — and the next time the
       row was read back, that display value is what got committed. The number
       you typed would quietly become a different number. */
    function fmtNum(v, p) {
        if (v == null || !isFinite(v)) return '-';
        var dec = p.dec == null ? 2 : p.dec;
        if (Math.abs(v - +v.toFixed(dec)) < 1e-9) return v.toFixed(dec);
        return String(+v.toFixed(6));
    }

    function labelFor(p, val) {
        if (p.list) {
            for (var i = 0; i < p.list.length; i++) if (p.list[i][0] === val) return p.list[i][1];
            return 'Default';
        }
        if (val == null) return '-';
        return fmtNum(val, p) + (p.unit || '');
    }

    /* Set a property to an ABSOLUTE value, as opposed to bumpProp's relative
       step. This is what the typed fields commit through, and it is deliberately
       the same code path the buttons end up in, so a number reached by typing
       and a number reached by clicking cannot behave differently. */
    function setProp(p, value, key) {
        if (!isFinite(value)) return false;
        var v = Math.max(p.min, Math.min(p.max, value));

        if (NATIVE_ELEMENTS[key]) {
            nativeVals[p.k] = v;                 // optimistic, corrected on reply
            renderProps();
            post('mapTune', { key: p.k, value: v }, function (state) {
                if (state && typeof state === 'object') { nativeVals = state; renderProps(); }
            });
            return true;
        }

        offsets[key] = offsets[key] || { x: 0, y: 0 };
        offsets[key][p.k] = v;
        applyOffsets(); renderEditor();
        return true;
    }

    // An EMPTY Lua table has no way to say whether it is a list or a map, so
    // SendNUIMessage serialises `layout = {}` as a JSON *array*. Editing that
    // array by key (offsets.slots = ...) appears to work in JS, but named
    // properties on an array are dropped by JSON.stringify — so the editor
    // posted `{"offsets":[]}` back and every move and scale was thrown away on
    // save. That hit any player whose layout was still empty, i.e. anyone who
    // had never saved one or had just run /hudreset.
    function asOffsetMap(v) {
        var out = {};
        if (!v || typeof v !== 'object') return out;
        Object.keys(v).forEach(function (k) {
            var o = v[k];
            if (o && typeof o === 'object') out[k] = o;
        });
        return out;
    }

    // Build a plain, fully-populated object to hand back to Lua, rather than
    // shipping the live working copy and hoping its shape survives.
    function offsetsForSave() {
        var out = {};
        Object.keys(offsets).forEach(function (k) {
            var o = offsets[k] || {};
            // `s` is still written so anything reading the old key keeps working;
            // it carries the width scale, which is the uniform one in the common
            // case where the two axes match.
            var e = { x: o.x || 0, y: o.y || 0, sx: scaleX(o), sy: scaleY(o), s: scaleX(o) };
            PROPS.forEach(function (p) {
                if (p.k === 'sx' || p.k === 'sy') return;
                if (o[p.k] !== undefined && o[p.k] !== null) e[p.k] = o[p.k];
            });
            // Without this the notification corner was silently dropped on
            // save: offsetsForSave builds a fresh object from PROPS, and
            // `anchor` is not one of them.
            EXTRA_KEYS.forEach(function (k2) {
                if (o[k2] !== undefined && o[k2] !== null) e[k2] = o[k2];
            });
            out[k] = e;
        });
        return out;
    }

    var editorOpen = false;
    var editorSel = 0;
    var offsets = {};
    var editorPopTimer = null;

    /* The centre indicator is transient by nature — it fires on a change and
       fades. That makes it impossible to position, so while the editor is open
       it is cycled between the + and the - face, on a period shorter than its
       own hide timer so it never disappears. It also shows BOTH states, which
       is what you actually want to see when placing it. */
    /* The level-up card clears itself after four seconds, which makes it
       impossible to position. While the editor is open it is re-fired on a
       period shorter than its own hide timer so it simply stays put — the same
       treatment the honor indicator gets, and for the same reason. */
    var editorSkillTimer = null;

    function editorSkillUpHold(on) {
        if (editorSkillTimer) { clearInterval(editorSkillTimer); editorSkillTimer = null; }
        if (!on) { show($('skillup'), false); return; }
        var beat = function () {
            onSkillUp({ id: 'stamina', label: 'Stamina', level: 42,
                        blurb: 'Sprint further before you redline.' });
        };
        beat();
        editorSkillTimer = setInterval(beat, 3000);
    }

    function editorHonorCycle(on) {
        if (editorPopTimer) { clearInterval(editorPopTimer); editorPopTimer = null; }
        if (!on) { show($('honor-pop'), false); return; }
        var up = false;
        var beat = function () {
            up = !up;
            onHonorPop(up ? 12 : -12, up ? '\uD83D\uDE07' : '\uD83D\uDE08');
        };
        beat();
        editorPopTimer = setInterval(beat, 1600);
    }

    /* No up/down cycle needed here, unlike honor: reputation only ever moves
       one direction, so re-firing the same "+N" is enough to hold it visible
       while it is being positioned. */
    var editorRepPopTimer = null;

    function editorReputationCycle(on) {
        if (editorRepPopTimer) { clearInterval(editorRepPopTimer); editorRepPopTimer = null; }
        if (!on) { show($('reputation-pop'), false); return; }
        var beat = function () { onReputationPop(15, '\uD83D\uDDE1\uFE0F'); };
        beat();
        editorRepPopTimer = setInterval(beat, 1600);
    }

    /* Scale is per-AXIS. `s` is the legacy uniform value and is still read as
       the fallback, so a layout saved before this existed still loads. */
    function scaleX(o) { return o.sx == null ? (o.s == null ? 1 : o.s) : o.sx; }
    function scaleY(o) { return o.sy == null ? (o.s == null ? 1 : o.s) : o.sy; }

    function applyOffsets(quiet) {
        if (!stage) return;
        EDITOR_ELEMENTS.forEach(function (e) {
            if (!e[2]) return;                 // external, handled over an event
            var o = offsets[e[0]] || { x: 0, y: 0 };
            stage.style.setProperty('--off-' + e[0] + '-x', (o.x || 0) + 'cqw');
            stage.style.setProperty('--off-' + e[0] + '-y', (o.y || 0) + 'cqh');
            PROPS.forEach(function (p) {
                // Same opt-in as propsFor. Without it a Brand tint left in a
                // hand-edited layout.json would write --tint-money, which
                // nothing reads but which isModified would still light a dot
                // for — a change you could see and not find a row to undo.
                if (p.only && !p.only[e[0]]) return;
                // Applied by applyPanelRect, not here: these three have to be
                // weighed against the map rect and the snapshot before anything
                // can be written, which this loop has no way to express.
                if (p.panel) return;
                /* `raw` rows own their whole property name. The normal rows
                   are one property PER ELEMENT (--fs-zone, --fs-wanted, ...)
                   so the element key is appended; a raw row is scoped to a
                   single element by `only` already and names a property that
                   style.css reads literally (--nav-accent), so appending the
                   key would write --nav-accentnavpopup, which nothing reads. */
                var name = p.raw ? p.v : (p.v + e[0] + (p.suffix || ''));
                var val = valueOf(o, p);
                // Unset -> remove, so style.css's own value wins through the
                // var() fallback. Writing an empty string would not do that.
                if (val == null || val === p.def) {
                    if (p.k === 'sx' || p.k === 'sy') stage.style.setProperty(name, 1);
                    else stage.style.removeProperty(name);
                    // Alignment is two properties, so unsetting it has to clear
                    // both — leaving --ai-* behind would keep the box aligned
                    // after the text had gone back to default.
                    if (p.k === 'al') stage.style.removeProperty('--ai-' + e[0]);
                    return;
                }
                stage.style.setProperty(name, p.unit ? (val + p.unit) : val);
                // The flex half of the same intent. style.css needs both: one
                // moves the copy, the other moves the box the copy sits in.
                if (p.k === 'al') stage.style.setProperty('--ai-' + e[0], FLEX_ALIGN[val] || 'flex-start');
            });
        });
        // The panel stack, whose three rows the loop above deliberately skips.
        applyPanelRect(lastMapRect);
        // A new font, size or width changes the box the names have to fit into,
        // so the fit factor is stale the moment any of them is touched.
        if (typeof fitAll === 'function') fitAll();
        // Live-update the other resources as you nudge, so external elements
        // move under the arrow keys exactly like the local ones.
        if (!quiet) post('layoutLive', { offsets: offsetsForSave() });
    }

    /* Has this element been changed from the shipped default? Drives the dot
       in the list, so "what have I actually touched" is answerable at a glance
       instead of by reading fourteen rows of numbers. */
    function isModified(key) {
        var o = offsets[key];
        if (!o) return false;
        if ((o.x || 0) !== 0 || (o.y || 0) !== 0) return true;
        if (scaleX(o) !== 1 || scaleY(o) !== 1) return true;
        for (var i = 0; i < PROPS.length; i++) {
            var p = PROPS[i];
            if (p.k === 'sx' || p.k === 'sy') continue;
            // A prop this element is not offered cannot be a change to it.
            if (p.only && !p.only[key]) continue;
            var v = o[p.k];
            if (v !== undefined && v !== null && v !== p.def) return true;
        }
        // 'top-right' is ox_lib's own default corner, so a layout sitting on it
        // has not been touched — treating any anchor as a change would light
        // this dot for every player from the moment they opened the editor.
        if (o.anchor != null && o.anchor !== 'top-right') return true;
        return false;
    }

    function renderEditor() {
        var ul = $('editor-list');
        if (!ul) return;
        ul.innerHTML = '';
        var group = null;
        var selLi = null;

        EDITOR_ELEMENTS.forEach(function (e, i) {
            if (e[4] && e[4] !== group) {
                group = e[4];
                var head = document.createElement('li');
                head.className = 'ed-group';
                head.textContent = group;
                ul.appendChild(head);
            }

            var o = offsets[e[0]] || { x: 0, y: 0 };
            var li = document.createElement('li');
            li.className = 'ed-item' + (i === editorSel ? ' sel' : '');
            if (i === editorSel) selLi = li;

            var native = !!NATIVE_ELEMENTS[e[0]];
            // Engine and cross-resource rows have no CSS scale to report, so
            // showing "x1.00 / 1.00" for them was noise that read as a value.
            var val = native || !e[2]
                ? ''
                : (o.x || 0).toFixed(2) + ', ' + (o.y || 0).toFixed(2) +
                  '  &times;' + scaleX(o).toFixed(2) + ' / ' + scaleY(o).toFixed(2);

            li.innerHTML =
                '<span class="ed-dot' + (isModified(e[0]) ? ' on' : '') + '"></span>' +
                '<span class="ed-name">' + e[1] +
                '<span class="ed-desc">' + e[3] + '</span></span>' +
                '<span class="ed-val">' + val + '</span>';

            li.addEventListener('click', function () { editorSel = i; renderEditor(); markTarget(); });
            ul.appendChild(li);
        });

        // Tab can walk the selection past the bottom of a scrolling list; without
        // this it disappears and the panel looks frozen.
        if (selLi && selLi.scrollIntoView) selLi.scrollIntoView({ block: 'nearest' });

        renderProps();
    }

    function markTarget() {
        document.querySelectorAll('.ed-target').forEach(function (n) { n.classList.remove('ed-target'); });
        var sel = EDITOR_ELEMENTS[editorSel];
        if (!sel || !sel[2]) return;          // lives in another resource
        var el = document.querySelector(sel[2]);
        if (el) el.classList.add('ed-target');
    }

    function nudge(dx, dy) {
        var key = EDITOR_ELEMENTS[editorSel][0];

        if (NATIVE_ELEMENTS[key]) {
            if (NATIVE_ELEMENTS[key] === 'size') {
                // Multipliers on the configured component size, not raw
                // safe-zone units: 0.1 step = 0.5%, Shift = 5%.
                post('mapAdjust', { dw: dx * 0.05, dh: -dy * 0.05 }, function (state) {
                    if (state && typeof state === 'object') { nativeVals = state; renderProps(); }
                });
            } else {
                // dy is INVERTED on the way to Lua. The minimap components are
                // anchored 'B' (bottom), where a larger y sits HIGHER up the
                // screen, while the arrow keys use the screen convention of
                // down-is-positive. Passing dy straight through made Up push
                // the map down.
                post('mapAdjust', { dx: dx * 8, dy: -dy * 8 }, function (state) {
                    if (state && typeof state === 'object') { nativeVals = state; renderProps(); }
                });
            }
            offsets[key] = offsets[key] || { x: 0, y: 0 };
            offsets[key].x = +((offsets[key].x || 0) + dx).toFixed(2);
            offsets[key].y = +((offsets[key].y || 0) + dy).toFixed(2);
            renderEditor();
            return;
        }

        offsets[key] = offsets[key] || { x: 0, y: 0 };
        offsets[key].x = +((offsets[key].x || 0) + dx).toFixed(2);
        offsets[key].y = +((offsets[key].y || 0) + dy).toFixed(2);
        applyOffsets(); renderEditor();
    }

    // Resize the selected element. Reachable from several keys AND from the
    // on-screen -/+ buttons: Ctrl+Arrow alone was too easy to miss, and any
    // single key combination that the game or the browser eats leaves scaling
    // looking broken.
    /* axis: 'x', 'y', or 'both'. The minimap frame in particular needs height
       on its own — it is sized from the map's rect, which is a different shape
       from the frame that has to sit on it. */
    function scaleBy(delta, axis) {
        axis = axis || 'both';
        var key = EDITOR_ELEMENTS[editorSel][0];
        offsets[key] = offsets[key] || { x: 0, y: 0 };
        var o = offsets[key];

        if (NATIVE_ELEMENTS[key]) {
            // The engine draws the map, so its scale is applied in Lua.
            post('mapAdjust', axis === 'x' ? { dw: delta }
                            : axis === 'y' ? { dh: delta }
                            : { ds: delta });
            var clampN = function (v) { return +Math.max(0.01, Math.min(20, v)).toFixed(4); };
            if (axis !== 'y') o.sx = clampN(scaleX(o) * (1 + delta));
            if (axis !== 'x') o.sy = clampN(scaleY(o) * (1 + delta));
            renderEditor();
            return;
        }

        // Bounded by the Width / Height rows themselves rather than by its own
        // numbers. Ctrl+Arrow used to stop at 2.5 while those rows went to 3,
        // so one element had two different ceilings depending on how you
        // reached for it.
        var clamp = function (v) { return +Math.max(SC_MIN, Math.min(SC_MAX, v)).toFixed(4); };
        if (axis !== 'y') o.sx = clamp(scaleX(o) + delta);
        if (axis !== 'x') o.sy = clamp(scaleY(o) + delta);
        applyOffsets(); renderEditor();
    }

    /* Step the selected property. `dir` is -1 or +1; list properties cycle. */
    function bumpProp(dir, big) {
        var key = EDITOR_ELEMENTS[editorSel][0];
        var p = propsFor(key)[propSel];
        if (!p) return;

        // The engine owns the minimap, so its values go to Lua as absolutes and
        // the reply is what the panel then shows.
        if (NATIVE_ELEMENTS[key]) {
            var cur = nativeVals[p.k] == null ? 0 : Number(nativeVals[p.k]);
            var next = cur + dir * p.step * (big ? 5 : 1);
            next = Math.max(p.min, Math.min(p.max, next));
            next = +next.toFixed(p.dec);
            nativeVals[p.k] = next;              // optimistic, corrected on reply
            renderProps();
            post('mapTune', { key: p.k, value: next }, function (state) {
                if (state && typeof state === 'object') {
                    nativeVals = state;
                    renderProps();
                }
            });
            return;
        }

        offsets[key] = offsets[key] || { x: 0, y: 0 };
        var o = offsets[key];

        /* A following row has no stored value, so valueOf would hand back the
           shipped default and the first nudge would JUMP from whatever the
           parent is doing to default±step. Starting from the inherited value
           makes stepping continue from what is on screen — and writing it is
           what detaches the row, which is the same rule as before: setting a
           value takes over from the parent. */
        var base = isFollowing(key, p.k) ? inheritedValue(key, p) : valueOf(o, p);

        if (p.list) {
            var cur = base;
            var i = 0;
            for (var n = 0; n < p.list.length; n++) if (p.list[n][0] === cur) i = n;
            i = (i + dir + p.list.length) % p.list.length;
            o[p.k] = p.list[i][0];
        } else {
            var step = p.step * (big ? 4 : 1);
            var v = (base == null ? p.def : base) + dir * step;
            v = Math.max(p.min, Math.min(p.max, v));
            // Position rounds to 2dp, matching what the arrow keys write, so
            // stepping a row and nudging with the keyboard cannot disagree.
            o[p.k] = +v.toFixed(p.pos ? 2 : p.dec + 1);
        }
        applyOffsets(); renderEditor();
    }

    /* Move the selection WITHOUT rebuilding the settings column.
       renderProps replaces every node it owns, which would tear the focused
       text field out from under the caret the moment you clicked into it. */
    function selectRow(i) {
        propSel = i;
        var rows = document.querySelectorAll('#editor-props .ed-prop');
        for (var n = 0; n < rows.length; n++) rows[n].classList.toggle('sel', n === i);
    }

    function renderProps() {
        var box = $('editor-props');
        if (!box) return;
        var sel = EDITOR_ELEMENTS[editorSel];
        var key = sel[0];
        var o = offsets[key] || {};
        var native = !!NATIVE_ELEMENTS[key];
        var list = propsFor(key);
        if (propSel >= list.length) propSel = list.length - 1;

        // Name the thing being tuned above its own settings. With fourteen
        // elements and two scrolling columns it was otherwise easy to lose track
        // of which one the -/+ buttons were about to change.
        var head = $('editor-propfor');
        if (head) head.textContent = sel[1];

        box.innerHTML = '';
        var selRow = null;

        list.forEach(function (p, i) {
            var row = document.createElement('div');
            row.className = 'ed-prop' + (i === propSel ? ' sel' : '');
            if (i === propSel) selRow = row;

            var lab = document.createElement('span');
            lab.className = 'ed-plabel'; lab.textContent = p.label;
            // Some rows cannot say what they do in two words — "Map width" and
            // "Plane width" are a case in point, and picking the wrong one is
            // how the map ends up the right size and the wrong shape.
            if (p.hint) { lab.title = p.hint; lab.classList.add('has-hint'); }

            // The minus, the value and the plus are wrapped as ONE control
            // rather than three loose ones, which is what makes it obvious the
            // buttons act on the number between them.
            var step = document.createElement('span');
            step.className = 'ed-step';

            var minus = document.createElement('button');
            minus.type = 'button'; minus.textContent = '\u2212';
            minus.setAttribute('aria-label', 'decrease ' + p.label);

            var plus = document.createElement('button');
            plus.type = 'button'; plus.textContent = '+';
            plus.setAttribute('aria-label', 'increase ' + p.label);

            /* A row whose value is a plain number gets a real text field, not a
               label. Stepping is fine for finding a value and hopeless for
               reaching one: at 0.05 a click, a Width of 12 is 220 clicks away,
               and no ceiling generous enough to allow it would make that
               usable. `p.list` rows (Font, Text align, Corner) and the native
               on/off rows have no number to type, so those stay labels. */
            var typeable = !p.list && !(native && p.names);
            var val = document.createElement(typeable ? 'input' : 'span');
            val.className = 'ed-pval';

            var current;
            if (native) {
                var nv = nativeVals[p.k];
                current = nv == null ? null : Number(nv);
                if (p.names) {
                    val.textContent = current == null ? '-'
                        : p.names[Math.max(0, Math.min(p.names.length - 1, Math.round(current)))];
                }
            } else {
                current = valueOf(o, p);
                // A following row has no stored value, so valueOf returns the
                // shipped default — which is not what is on screen if the
                // parent has been tuned. Show what the element is actually
                // rendering, or the row reads as wrong.
                var following = isFollowing(key, p.k);
                if (following) current = inheritedValue(key, p);
                if (!typeable) val.textContent = labelFor(p, current);
                // A quiet marker on rows that are no longer at their default, so
                // "what did I change on this element" is visible without diffing
                // against the stylesheet in your head.
                //
                // Not on a FOLLOWING row. Its value can differ from the shipped
                // default while this element is untouched -- the difference
                // belongs to the parent -- and marking it here would put a
                // change indicator on a row with nothing to undo.
                if (!following && current != null && current !== p.def) row.classList.add('changed');
            }

            if (typeable) {
                val.type = 'text';
                val.setAttribute('inputmode', 'decimal');
                val.setAttribute('aria-label', p.label);
                val.value = current == null ? ''
                    : fmtNum(current, p) + (native ? (p.unitLabel || '') : (p.unit || ''));
                val.title = 'Type a value, then Enter. Range ' + p.min + ' to ' + p.max;

                var commit = function () {
                    // Tolerate what people actually type: a unit they can see in
                    // the box ("0.045em", "8%"), a comma decimal, stray spaces.
                    var raw = String(val.value).replace(',', '.').replace(/[^0-9eE.+-]/g, '');
                    var n = parseFloat(raw);
                    // Not a number at all: put the real value back rather than
                    // guessing, so a mistyped row never silently becomes zero.
                    if (!isFinite(n)) { renderProps(); return; }
                    if (!setProp(p, n, key)) renderProps();
                };

                // The editor's global keydown owns the arrows, +, -, H and
                // Space. Every one of those is something you might type into a
                // number field, so while this has focus the field keeps them.
                val.addEventListener('keydown', function (ev) {
                    ev.stopPropagation();
                    if (ev.key === 'Enter') { ev.preventDefault(); commit(); }
                    else if (ev.key === 'Escape') { ev.preventDefault(); renderProps(); }
                });
                val.addEventListener('keyup', function (ev) { ev.stopPropagation(); });
                val.addEventListener('blur', commit);
                // Clicking in must not re-render the row out from under the
                // caret, and must not select the whole field mid-edit.
                val.addEventListener('mousedown', function (ev) { ev.stopPropagation(); });
                val.addEventListener('click', function (ev) { ev.stopPropagation(); selectRow(i); });
                val.addEventListener('focus', function () { val.select(); });
            }

            minus.addEventListener('click', function (ev) { ev.stopPropagation(); propSel = i; bumpProp(-1); });
            plus.addEventListener('click', function (ev) { ev.stopPropagation(); propSel = i; bumpProp(1); });
            row.addEventListener('click', function () { propSel = i; renderProps(); });

            step.appendChild(minus); step.appendChild(val); step.appendChild(plus);
            row.appendChild(lab); row.appendChild(step);

            /* The Follow/Own switch, on the eleven rows that really do inherit.
               Rendered as one button that names the CURRENT state and toggles
               it, rather than a pair of radio-ish buttons: there are only two
               states and the row is already three controls wide. */
            if (!native && inheritsProp(key, p.k)) {
                var isFol = isFollowing(key, p.k);
                var fol = document.createElement('button');
                fol.type = 'button';
                fol.className = 'ed-follow' + (isFol ? ' on' : '');
                fol.textContent = isFol ? 'Follow' : 'Own';
                fol.title = isFol
                    ? 'Taking this from ' + labelOf(INHERITS[key].parent)
                      + '. Click to give this element its own value.'
                    : 'This element has its own value. Click to go back to '
                      + 'following ' + labelOf(INHERITS[key].parent) + '.';
                fol.setAttribute('aria-pressed', isFol ? 'true' : 'false');
                fol.addEventListener('click', function (ev) {
                    ev.stopPropagation();
                    propSel = i;
                    setFollow(key, p, !isFollowing(key, p.k));
                });
                row.appendChild(fol);
                if (isFol) row.classList.add('following');
            }

            box.appendChild(row);
        });

        if (selRow && selRow.scrollIntoView) selRow.scrollIntoView({ block: 'nearest' });
    }

    function resetSelected() {
        var key = EDITOR_ELEMENTS[editorSel][0];
        offsets[key] = { x: 0, y: 0, s: 1, sx: 1, sy: 1 };
        PROPS.forEach(function (p) { delete offsets[key][p.k]; });
        offsets[key].sx = 1; offsets[key].sy = 1;
        // Resetting the panel stack means "put them back on the map", and the
        // map may well have been resized since the snapshot was taken. Without
        // this the rows clear but the panels stay at their old size, which
        // reads as Reset not working.
        if (key === 'slots') resnapPanelRect();
        if (NATIVE_ELEMENTS[key]) {
            post('mapReset', {}, function (state) {
                if (state && typeof state === 'object') { nativeVals = state; renderProps(); }
            });
        }
        applyOffsets(); renderEditor();
    }

    function closeEditor(save) {
        editorOpen = false;
        editorPreview(false);
        show($('editor'), false);
        document.querySelectorAll('.ed-target').forEach(function (n) { n.classList.remove('ed-target'); });
        post(save ? 'saveLayout' : 'closeEditor', save ? { offsets: offsetsForSave() } : {});
    }

    /* While the editor is open every element is forced visible with
       representative content, so you can see exactly what you're positioning
       instead of moving invisible boxes. Restored on close. */
    function editorPreview(on) {
        if (on) {
            onStatus({ health: 62, focus: 45, stamina: 54 });
            onWanted({ active: true, stars: 3, maxStars: 6, state: 'contact',
                       tells: ['camera', 'medical', 'hanger', 'person', 'flag'] });
            // A real icon, not just the clip/reserve numbers, so the ammo row
            // has actual art to line up against instead of an empty box.
            // weapon_pistol is ox_inventory's own art, the same nui:// path
            // client.lua's WeaponIcons table points at in game.
            onWeapon({ armed: true, icon: 'nui://ox_inventory/web/images/weapon_pistol.png', clip: 12, reserve: 84 });
            onCash({ cash: 28163, bank: 154200, show: true });
            onDuffle({ value: 4820 });
            onChips({ value: 3450 });
            onZone({ zone: 'Mirror Park', duration: 9e6 });
            /* Fuel and engine are pushed into their WARNING bands, and the
               lock pip's event window is held open, so all three discs are on
               screen to be positioned. In normal play each only appears when
               it has something to say (see setPips), which would otherwise
               leave the pip row unpositionable in a healthy car. */
            lockPipState = 'locked';
            lockPipUntil = Date.now() + 9e6;
            onVehicle({ show: true, make: 'Nagasaki', model: 'Chimera',
                        fuel: 18, engineOn: true, engineHealth: 420,
                        lockState: 'locked' });
            onHonor({ emoji: '😈', honor: -50, showValue: true,
                      reason: 'Killed a bystander', duration: 9e6, broken: true });
            onReputation({ icon: '🗡️', label: 'CRIMINAL', value: 240, tier: 3,
                            showValue: true, reason: 'Robbed an armoured truck',
                            holdMs: 9e6 });
            editorHonorCycle(true);
            editorReputationCycle(true);
            editorSkillUpHold(true);
            onPrompt({ id: '_ed', label: 'Interact', glyph: 'E',
                       device: 'kbm', show: true });
            var fr = $('map-frame'); if (fr) show(fr, true);
            onNav({ active: true, near: true, street: 'Bayside', remaining: '0.69 mi',
                    instruction: 'Turn Left', dir: 'left', distance: '130 ft' });
            // onNav just hid the badge the way it does whenever nav is active
            // -- correct in normal play, wrong here: editor preview wants
            // every piece on screen at once, badge included, so it can be
            // selected and positioned like everything else. Same for the frame
            // above: applyMapChrome would otherwise re-hide both, since the
            // editor forces the radar on regardless of what setRadar last said.
            show($('map-badge'), true);
            // Forced ON for the duration of editing, same reasoning as the
            // rest of this function: an effect that only shows for a few
            // seconds mid-fight is unpositionable/untunable otherwise.
            var ffx = $('focus-fx'); if (ffx) ffx.classList.add('active');
            var frow = $('s-focus'); if (frow) frow.classList.add('active');
        } else {
            // Drop the held-open lock pip, or it would stay up for hours
            // after the editor closed.
            lockPipUntil = 0;
            editorHonorCycle(false);
            editorReputationCycle(false);
            editorSkillUpHold(false);
            onPrompt({ id: '_ed', show: false });
            var ffxOff = $('focus-fx'); if (ffxOff) ffxOff.classList.remove('active');
            var frowOff = $('s-focus'); if (frowOff) frowOff.classList.remove('active');
            ['zone', 'vehicle', 'honor', 'wanted', 'honor-pop',
             'reputation', 'reputation-pop', 'skillup'].forEach(function (id) {
                show($(id), false);
            });
            // Not just a show(el, false) like the ids above: onNav's own
            // "inactive" branch is what clears mapBadgeWanted back to true.
            // editorPreview(true) called onNav({active:true, near:true, ...})
            // to preview the nav bar, which sets mapBadgeWanted = false (the
            // badge steps aside for the compass) -- hiding nav-popup/
            // nav-compass by id here without going back through onNav left
            // that flag stuck at false, so the badge stayed hidden after
            // every close from then on, not just during the preview.
            onNav({ active: false });
            // The frame and badge were forced on for the preview; put the whole
            // map chrome back to whatever the config and the live radar state
            // actually ask for.
            applyMapChrome();
            // Clear the fake money/weapon readouts. The client re-pushes the
            // real values on its next tick (see resetPushCaches in client.lua).
            onCash({ show: false });
            onWeapon({ armed: false });
        }
    }

    function openEditor(d) {
        offsets = asOffsetMap(d.offsets);
        if (d.native && typeof d.native === 'object') nativeVals = d.native;
        editorOpen = true; editorSel = 0;
        editorPreview(true);
        applyOffsets(); renderEditor(); markTarget();
        show($('editor'), true);
        // Always reopen expanded and un-peeked; only the POSITION persists,
        // because a panel that comes back collapsed reads as broken.
        setCollapsed(false); setPeek(false); restorePanelPos(); restorePanelSize();
    }

    /* --- the panel itself: drag, collapse, peek ---------------------------
       The editor is a tool laid OVER the thing it edits, so it will always be
       in the way of something. Three ways out, none of which need the editor
       closed and reopened:
         · drag it by its title bar, and the position is remembered
         · H (or the button in the title bar) folds it down to the title bar
         · hold Space to make it near-invisible for as long as you hold it
       Together with the removed scrim (see style.css) this is what makes it
       possible to fine-tune a corner element while looking at it. */
    var PANEL_POS_KEY = 'vice_hud:editorPanelPos';
    var PANEL_SIZE_KEY = 'vice_hud:editorPanelSize';

    /* Floors, not opinions — the same rule as the property min/max. Below these
       the panel stops being a panel: the two columns collapse into each other
       and the grip ends up under the action buttons. The ceiling is the
       viewport, applied at drag time rather than as a constant. */
    var PANEL_MIN_W = 520, PANEL_MIN_H = 260;

    function panelEl() { return $('editor-panel'); }

    function clampPanel(x, y) {
        var el = panelEl();
        var w = (el && el.offsetWidth) || 0;
        var h = (el && el.offsetHeight) || 0;
        var maxX = Math.max(0, (window.innerWidth || 0) - w);
        var maxY = Math.max(0, (window.innerHeight || 0) - h);
        return { x: Math.min(Math.max(0, x), maxX), y: Math.min(Math.max(0, y), maxY) };
    }

    /* `remember` is false during a drag: writing to storage on every mousemove
       is pointless, and the drop is the only position worth keeping. */
    function placePanel(x, y, remember) {
        var el = panelEl();
        if (!el) return;
        var c = clampPanel(x, y);
        el.classList.add('dragged');
        el.style.left = c.x + 'px';
        el.style.top = c.y + 'px';
        if (remember) {
            try { localStorage.setItem(PANEL_POS_KEY, JSON.stringify(c)); } catch (e) {}
        }
    }

    /* `remember` is false during a resize drag, for the same reason it is
       during a move: only the final size is worth storing. */
    function sizePanel(w, h, remember) {
        var el = panelEl();
        if (!el) return;
        var maxW = Math.max(PANEL_MIN_W, (window.innerWidth || 0) - 8);
        var maxH = Math.max(PANEL_MIN_H, (window.innerHeight || 0) - 8);
        var cw = Math.min(Math.max(PANEL_MIN_W, w), maxW);
        var ch = Math.min(Math.max(PANEL_MIN_H, h), maxH);
        el.classList.add('resized');
        el.style.width = cw + 'px';
        el.style.height = ch + 'px';
        if (remember) {
            try {
                localStorage.setItem(PANEL_SIZE_KEY, JSON.stringify({ w: cw, h: ch }));
            } catch (e) {}
        }
    }

    function restorePanelSize() {
        var el = panelEl();
        if (!el) return;
        var saved = null;
        try { saved = JSON.parse(localStorage.getItem(PANEL_SIZE_KEY) || 'null'); } catch (e) {}
        if (saved && typeof saved.w === 'number' && typeof saved.h === 'number') {
            sizePanel(saved.w, saved.h, false);
        } else {
            // Back to the stylesheet's starting size.
            el.classList.remove('resized');
            el.style.width = '';
            el.style.height = '';
        }
    }

    function initPanelResize() {
        var grip = $('ed-resize');
        var el = panelEl();
        if (!grip || !el) return;
        var sizing = false, sx = 0, sy = 0, sw = 0, sh = 0;

        grip.addEventListener('mousedown', function (ev) {
            if (ev.button !== 0) return;
            var r = el.getBoundingClientRect();
            sx = ev.clientX; sy = ev.clientY;
            sw = r.width; sh = r.height;
            sizing = true;
            el.classList.add('resizing');
            // Stop the head's drag handler and the row click-through both.
            ev.preventDefault();
            ev.stopPropagation();
        });
        // On document for the same reason the move drag is: a fast drag outruns
        // the cursor and the pointer ends up over the game.
        document.addEventListener('mousemove', function (ev) {
            if (!sizing) return;
            sizePanel(sw + (ev.clientX - sx), sh + (ev.clientY - sy), false);
        });
        document.addEventListener('mouseup', function (ev) {
            if (!sizing) return;
            sizing = false;
            el.classList.remove('resizing');
            sizePanel(sw + (ev.clientX - sx), sh + (ev.clientY - sy), true);
        });
        // Double-click the grip to go back to the stylesheet's size, so a panel
        // dragged to something unusable is always one gesture from sane.
        grip.addEventListener('dblclick', function (ev) {
            ev.preventDefault(); ev.stopPropagation();
            try { localStorage.removeItem(PANEL_SIZE_KEY); } catch (e) {}
            restorePanelSize();
        });
    }

    function restorePanelPos() {
        var el = panelEl();
        if (!el) return;
        var saved = null;
        try { saved = JSON.parse(localStorage.getItem(PANEL_POS_KEY) || 'null'); } catch (e) {}
        if (saved && typeof saved.x === 'number' && typeof saved.y === 'number') {
            placePanel(saved.x, saved.y, false);
        } else {
            // Back to the CSS centring.
            el.classList.remove('dragged');
            el.style.left = '';
            el.style.top = '';
        }
    }

    function setCollapsed(on) {
        var el = panelEl();
        if (!el) return;
        el.classList.toggle('collapsed', !!on);
        var b = $('ed-collapse');
        if (b) {
            b.textContent = on ? '▾' : '▴';
            b.setAttribute('aria-label', on ? 'expand the editor' : 'collapse the editor');
            b.title = on ? 'Expand (H)' : 'Collapse (H)';
        }
        var sub = $('editor-sub');
        if (sub) {
            sub.textContent = on
                ? 'Collapsed — arrows still move the selected piece. H to reopen.'
                : 'Pick a piece on the left, tune it on the right.';
        }
    }

    function togglePanel() {
        var el = panelEl();
        setCollapsed(!(el && el.classList.contains('collapsed')));
    }

    function setPeek(on) {
        var el = panelEl();
        if (el) el.classList.toggle('peek', !!on);
    }

    function initPanelDrag() {
        var head = $('editor-head');
        var el = panelEl();
        if (!head || !el) return;
        var dragging = false, ox = 0, oy = 0;

        head.addEventListener('mousedown', function (ev) {
            if (ev.button !== 0) return;
            // The collapse button lives in the head; dragging must not eat it.
            if (ev.target && ev.target.closest && ev.target.closest('button')) return;
            var r = el.getBoundingClientRect();
            ox = ev.clientX - r.left;
            oy = ev.clientY - r.top;
            dragging = true;
            el.classList.add('dragging');
            ev.preventDefault();
        });
        // On document, not on the head: a fast drag outruns the cursor and the
        // pointer ends up over the game, which would strand the panel mid-move.
        document.addEventListener('mousemove', function (ev) {
            if (!dragging) return;
            placePanel(ev.clientX - ox, ev.clientY - oy, false);
        });
        document.addEventListener('mouseup', function (ev) {
            if (!dragging) return;
            dragging = false;
            el.classList.remove('dragging');
            placePanel(ev.clientX - ox, ev.clientY - oy, true);
        });
    }

    // Space is held, not tapped, so the release has to be caught even when the
    // editor has already closed underneath it.
    document.addEventListener('keydown', function (ev) {
        if (ev.key !== 'Escape') return;
        var sk = $('skills');
        if (!sk || sk.classList.contains('hidden')) return;
        show(sk, false);
        post('closeSkills', {});
        // Stops here so a skills panel open on top of the editor does not also
        // cancel the edit underneath it.
        ev.stopPropagation();
        ev.preventDefault();
    }, true);

    document.addEventListener('keydown', function (ev) {
        var box = $('interact');
        if (!box || box.classList.contains('hidden')) return;
        if (ev.key === 'ArrowUp')        { moveInteractSel(-1); }
        else if (ev.key === 'ArrowDown') { moveInteractSel(1); }
        else if (ev.key === 'Enter')     { confirmInteract(); }
        else if (ev.key === 'Escape')    { closeInteract(); }
        else return;
        ev.stopPropagation();
        ev.preventDefault();
    }, true);

    document.addEventListener('keyup', function (ev) {
        if (ev.target && ev.target.tagName === 'INPUT') return;
        if (ev.key === ' ' || ev.key === 'Spacebar') setPeek(false);
    });

    /* Is the player typing into one of the value fields right now? Those fields
       need the arrows, the digits, `-`, `.` and Space — every one of which this
       handler otherwise claims. The fields stopPropagation as well; this is the
       backstop, because a single missed listener here turns typing a negative
       number into "shrink the element". */
    function typingInField(ev) {
        var t = ev.target;
        return !!t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable);
    }

    document.addEventListener('keydown', function (ev) {
        if (!editorOpen || typingInField(ev)) return;
        var step = ev.shiftKey ? 1.0 : 0.1;
        var sstep = ev.shiftKey ? 0.20 : 0.05;

        // Panel chrome. Checked before everything else so they work whatever
        // is selected and whichever property row is in focus.
        if (ev.key === 'h' || ev.key === 'H') { togglePanel(); ev.preventDefault(); return; }
        if (ev.key === ' ' || ev.key === 'Spacebar') { setPeek(true); ev.preventDefault(); return; }

        // Ctrl + arrows resize ALONG THAT AXIS: left/right = width,
        // up/down = height. Holding them apart is the only way to make an
        // element that is the wrong shape (rather than the wrong size) fit.
        if (ev.ctrlKey) {
            if (ev.key === 'ArrowUp')    { scaleBy(sstep, 'y');  ev.preventDefault(); return; }
            if (ev.key === 'ArrowDown')  { scaleBy(-sstep, 'y'); ev.preventDefault(); return; }
            if (ev.key === 'ArrowRight') { scaleBy(sstep, 'x');  ev.preventDefault(); return; }
            if (ev.key === 'ArrowLeft')  { scaleBy(-sstep, 'x'); ev.preventDefault(); return; }
        }

        // [ and ] choose which property + / - acts on.
        //
        // These wrapped on PROPS.length, which is only correct for a page
        // element. On the two engine-owned rows the list is NATIVE_PROPS and is
        // longer, so everything past the ninth entry -- Panel left/width/bottom/
        // height, Rounded corners and Mask = map -- was unreachable from the
        // keyboard. Clicking still worked, which is why it read as "the keys are
        // ignored down there" rather than as a bug.
        var plist = propsFor(EDITOR_ELEMENTS[editorSel][0]);
        if (ev.key === '[') { propSel = (propSel - 1 + plist.length) % plist.length; renderProps(); ev.preventDefault(); return; }
        if (ev.key === ']') { propSel = (propSel + 1) % plist.length; renderProps(); ev.preventDefault(); return; }

        // + / - (and PageUp/PageDown) step the SELECTED property, which starts
        // on Font size. Shift takes bigger steps.
        if (ev.key === '+' || ev.key === '=' || ev.key === 'PageUp') {
            bumpProp(1, ev.shiftKey); ev.preventDefault(); return;
        }
        if (ev.key === '-' || ev.key === '_' || ev.key === 'PageDown') {
            bumpProp(-1, ev.shiftKey); ev.preventDefault(); return;
        }

        switch (ev.key) {
            case 'ArrowLeft':  nudge(-step, 0); break;
            case 'ArrowRight': nudge(step, 0);  break;
            case 'ArrowUp':    nudge(0, -step); break;
            case 'ArrowDown':  nudge(0, step);  break;
            case 'Tab':
                editorSel = (editorSel + (ev.shiftKey ? -1 : 1) + EDITOR_ELEMENTS.length) % EDITOR_ELEMENTS.length;
                renderEditor(); markTarget(); break;
            case 'Enter':  closeEditor(true);  break;
            case 'Escape': closeEditor(false); break;
            default: return;
        }
        ev.preventDefault();
    });

    function post(name, data, onReply) {
        if (typeof GetParentResourceName === 'undefined') return;
        fetch('https://' + GetParentResourceName() + '/' + name, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {})
        }).then(function (r) {
            // Native rows read their values back out of the reply, so the panel
            // shows what the engine actually did rather than what was asked for.
            return onReply ? r.json() : null;
        }).then(function (j) {
            if (onReply && j) onReply(j);
        }).catch(function () {});
    }

    document.addEventListener('DOMContentLoaded', function () {
        var b;
        if ((b = $('ed-save')))     b.addEventListener('click', function () { closeEditor(true); });
        if ((b = $('ed-cancel')))   b.addEventListener('click', function () { closeEditor(false); });
        if ((b = $('ed-reset')))    b.addEventListener('click', resetSelected);
        if ((b = $('ed-collapse')))  b.addEventListener('click', togglePanel);
        if ((b = $('skills-close'))) b.addEventListener('click', function () {
            show($('skills'), false);
            post('closeSkills', {});
        });
        var interactList = $('interact-list');
        if (interactList) interactList.addEventListener('click', function (ev) {
            var row = ev.target.closest('.interact-row');
            if (!row) return;
            interactSel = Number(row.dataset.index);
            confirmInteract();
        });
        initPanelDrag();
        initPanelResize();
        if ((b = $('ed-resetall'))) b.addEventListener('click', function () {
            offsets = {}; post('mapReset', {}); applyOffsets(); renderEditor();
        });
        // Size / font buttons used to live down here too. They are gone: every
        // one of them duplicated a property row's own - / + , and eleven
        // buttons overflowed the action bar and clipped "Save & close".
    });

    /* --- dispatch -------------------------------------------------------- */

    var HANDLERS = {
        status: onStatus,
        wanted: onWanted,
        cash: onCash,
        duffle: onDuffle,
        chips: onChips,
        weapon: onWeapon,
        crosshair: onCrosshair,
        crossFire: onCrossFire,
        crossKill: onKillMark,
        lapHud: onLapHud,
        interact: onInteract,
        worldActions: onWorldActions,
        lockpick: onLockpick,
        lockpickProgress: onLockpickProgress,
        lockpickResult: onLockpickResult,
        mapRect: onMapRect,
        mapDebug: onMapDebug,
        zone: onZone,
        nav: onNav,
        navAccent: onNavAccent,
        vehicle: onVehicle,
        brandTour: onBrandTour,
        logoCheck: onLogoCheck,
        honor: onHonor,
        reputation: onReputation,
        prompt: onPrompt,
        promptGlyphs: onPromptGlyphs,
        police: onPolice,
        policeEditor: onPoliceEditor,
        skills: onSkills,
        skillUp: onSkillUp,
        exhaustion: onExhaustion,
        hudOffset: onOffset,
        layout: onLayout,
        openEditor: openEditor,
        hudVisible: function (d) { if (stage) stage.style.display = d.show === false ? 'none' : ''; }
    };

    /* Everything the editor preview draws itself. client.lua keeps polling the
       real game state while /movehud is open and pushes it every 250ms, which
       overwrote the preview almost immediately — at full health and no wanted
       level that meant the status bars and the top-right stack vanished a
       quarter-second after the editor opened, so there was nothing to place. */
    var PREVIEW_OWNED = {
        status: 1, wanted: 1, cash: 1, weapon: 1,
        zone: 1, vehicle: 1, honor: 1, reputation: 1, prompt: 1, nav: 1
    };

    /* makes.js is a separate file and index.html loads it BEFORE this one. If it
       is missing the page still works in every other respect -- the panel draws,
       the names are right, nothing throws -- and simply never shows a badge,
       which is a fault that can sit there for a long time looking like a design
       decision. Say so once, out loud, in the client console.

       In practice this means the file is not being SERVED rather than absent:
       adding files to fxmanifest needs `refresh` on the server before `ensure`,
       or the server keeps handing out the file list it scanned last. */
    if (!window.VICE_MAKES) {
        console.error('[vice_hud] html/makes.js did not load — no manufacturer '
                    + 'badges will be drawn. On the SERVER console: refresh, then '
                    + 'ensure vice_hud.');
        post('logoReport', { fatal: 'no-table' });
    }

    window.addEventListener('message', function (e) {
        var d = e.data || {};
        if (editorOpen && PREVIEW_OWNED[d.action]) return;
        var fn = HANDLERS[d.action];
        if (!fn) return;
        try { fn(d); }
        catch (err) { console.error('[vice_hud] handler "' + d.action + '" failed:', err); }
    });

    /* --- tell the client the page is listening ---------------------------- */
    /* The NUI page takes appreciably longer to come up than client.lua does, so
       anything the client pushes during those first moments lands nowhere --
       there is no listener yet and NUI messages are not queued. That is a
       silent failure: the state is correct on the Lua side and simply never
       reached the page.

       It bit the minimap. A player whose saved preference is "no map on foot"
       got the map hidden correctly, but the one `visible: false` that hides the
       frame and the corner badge with it was sent before this file existed, and
       setRadar only reports CHANGES -- so after every restart the frame and
       logo sat on screen outlining an empty box until the player got into a car
       and out again.

       This ping is the fix: the client invalidates its "already sent that"
       caches when it arrives, and the next poll tick re-asserts everything
       against a page that is now listening. Inert outside FiveM -- post()
       returns immediately when GetParentResourceName is undefined. */
    post('uiReady', {});

    /* --- browser demo mode ----------------------------------------------- */
    /* When opened outside FiveM (no GetParentResourceName) populate the HUD with
       representative data so the layout can be verified in a normal browser.
       This is inert in game. */
    if (typeof GetParentResourceName === 'undefined') {
        onStatus({ health: 66, focus: 40, stamina: 58 });
        onCash({ cash: 28163, bank: 154200, show: true });
        onDuffle({ value: 4820 });
        onChips({ value: 3450 });
        onWanted({ active: true, stars: 2, maxStars: 6, state: 'searching', tells: ['camera', 'medical', 'hanger', 'person', 'flag'] });
        onWeapon({ armed: true, clip: 20, reserve: 80 });
        // Keep these in step with Config.Minimap in config.lua.
        onMapRect({ left: 1.75, width: 15.8, bottom: 17.9, height: 15.4 });
        onZone({ zone: 'South Vice-Dale County', duration: 999999 });
        onNav({ active: true, near: true, street: 'Bayside', remaining: '0.69 mi',
                instruction: 'Turn Left', dir: 'left', distance: '130 ft' });
        onVehicle({ show: true, make: 'Pegassi', model: 'Bati 801', fuel: 72,
                    engineOn: true, engineHealth: 900, lockState: 'locked' });
        onHonor({ emoji: '😈', honor: -50, showValue: true, reason: 'Wanted by police', duration: 999999, broken: true });
        onReputation({ icon: '🗡️', label: 'CRIMINAL', value: 240, tier: 3,
                        showValue: true, reason: 'Robbed an armoured truck', holdMs: 999999 });
        // Nothing wires an action prompt today — the export exists for other
        // resources to call. Shown here only so the slot can be eyeballed.
        onPrompt({ id: 'demo', label: 'Interact', glyph: 'E', device: 'kbm', show: true });
        onPolice({ active: true, edges: { top: 0, right: 0.45, bottom: 0, left: 0 } });
        onCrosshair({ active: true, mode: 'foot' });
        onLapHud({ show: true, lap: 1, laps: 2, cp: 10, cpTotal: 16, elapsedMs: 19950, running: true });
        onInteract({
            show: true, selected: 0,
            options: [
                { label: 'Logger Beer' },
                { label: 'Lavazas Beer' },
                { label: 'Blitz Berry Smoothie', badges: ['stamina', 'focus'] },
                { label: 'Blitz Green Smoothie', badges: ['stamina'] }
            ]
        });
        onWorldActions({
            show: true,
            options: [
                { label: 'Slim Jim', button: 'triangle' },
                { label: 'Smash Window', button: 'circle' }
            ]
        });
        onLockpick({ show: true, zoneStart: 62, zoneLen: 12, glyph: 'R' });
        onLockpickProgress({ pct: 48 });

    }
})();
