/* -----------------------------------------------------------------------------
   Shared front end for Snarf and Ryde Me (internal identifier: goober).
   -----------------------------------------------------------------------------
   Two apps, one script. They are different companies in fiction and different
   icons on the phone, but the plumbing is the same either way, and duplicating
   this file to make that point twice would just be two files to fix every bug
   in. Which app is running comes from window.GIG_APP, set by each html file.

   The two apps are no longer the same SCREEN, though, and that is deliberate:

     Snarf   is a board. A list of deliveries, pick one. Unchanged.
     RydeMe  is dispatch. There is no list to browse -- you go online, and a
             request arrives with a clock on it. Plus a rider side, where you
             are the one asking for a lift.

   Two polls, on purpose and at different speeds:
     getState  server round trip. Rating, duty, the board, rider state. Slow.
     getLive   answered by the client with no server hop. The incoming request
               and its countdown, which has to tick. Fast.
   ---------------------------------------------------------------------------- */
(function () {
    'use strict';

    var APP = window.GIG_APP;
    var COPY = window.GIG_COPY;

    var state = null;       // last getState answer
    var live = null;        // last getLive answer
    var countdown = 0;      // seconds left on the card, ticked locally
    var countdownTotal = 0; // what it started at, so the bar has a scale
    var shownRequest = null;// id of the request whose card is currently built
    var shownJobKey = null; // stage+labels of the job whose shell is currently built
    var view = 'board';
    var busy = false;
    var rating = { stars: 5, comment: '' };
    var rideMode = 'real'; // 'real' | 'npc' -- which tier a destination tap books
    var rideMap = null;    // Leaflet instance, created once and reused
    var rideMarker = null;

    var driveMap = null;       // drive-HUD Leaflet instance, created once per job
    var driveMeMarker = null;
    var driveDestMarker = null;
    var driveMuted = false;    // "Silence" was pressed -- no more freak-out THIS job
    var driveAlertShown = false;

    var shownNpcPhase = null;  // rebuilds the NPC-ride screen only on a phase change
    var npcMap = null;
    var npcCarMarker = null;   // the driver, shown during 'approach'
    var npcMeMarker = null;    // you, shown during 'boarded'
    var npcDestMarker = null;
    var npcMapCentred = false;

    var SPEED_LINES = [
        'WHOA. slow down.',
        'the app is judging you right now.',
        'your rating just felt that.',
        'this is not a getaway car.',
        'sir. ma\'am. please.',
        'rydeme HQ has been notified. (not really. but still.)'
    ];

    /* Escape anything that came from the server before it reaches innerHTML.
       Same habit as lonelymans: cheap, and the one that stops a bad string
       becoming someone else's problem. */
    function esc(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }

    function el(id) { return document.getElementById(id); }

    function fetchNui(event, data) {
        return fetch('https://um_gigs/' + event, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {})
        }).then(function (r) { return r.json(); }).catch(function () { return null; });
    }

    function km(metres) {
        return (metres / 1000).toFixed(1) + ' km';
    }

    function stars(n) {
        var full = Math.round(n);
        var out = '';
        for (var i = 1; i <= 5; i++) out += (i <= full ? '★' : '☆');
        return out;
    }

    function setBusy(on) {
        busy = !!on;
        var list = el('list');
        if (list) list.classList.toggle('busy', busy);
    }

    /* ---- board / dispatch screen ------------------------------------------ */

    /* Duty is server state, so the button always reflects what came back rather
       than what we last clicked. */
    function renderDuty(on) {
        var btn = el('duty');
        if (!btn) return;
        btn.textContent = on ? COPY.dutyOn : COPY.dutyOff;
        btn.classList.toggle('on', !!on);
    }

    /* The request currently in front of the driver. This is the whole Ryde Me
       screen most of the time: one card, one clock, two answers. The bar drains
       rather than a number counting down on its own, because a number alone
       does not communicate "this is going away" fast enough to read at a
       glance while driving. */
    function incomingHtml(o) {
        return '<div class="request">'
            + '<div class="req-top">'
            + '<span class="req-kind">' + esc(o.playerRide ? 'Rider request' : (o.kindLabel || 'Fare')) + '</span>'
            + '<span class="req-secs" id="req-secs">' + Math.ceil(countdown) + 's</span>'
            + '</div>'
            + '<div class="req-clock"><i id="req-bar" style="width:' + clockPct().toFixed(1) + '%"></i></div>'
            + '<div class="req-pay">$' + o.pay + '</div>'
            + '<div class="req-who">' + esc(o.passengerName || '')
            + (o.mood && o.mood.label ? ' · ' + esc(o.mood.label) : '') + '</div>'
            + '<div class="leg"><span class="tag">FROM</span> ' + esc(o.pickupLabel) + '</div>'
            + '<div class="leg"><span class="tag">TO</span> ' + esc(o.dropoffLabel)
            + ' <span class="dist">' + km(o.distance) + '</span></div>'
            + '<div class="req-actions">'
            + '<button class="ghost" id="req-no">Decline</button>'
            + '<button id="req-yes">Accept</button>'
            + '</div>'
            + '<div class="req-hint">Y accepts, N declines, without opening your phone.</div>'
            + '</div>';
    }

    /* How much of the response window is left, as a percentage. */
    function clockPct() {
        if (countdownTotal <= 0) return 0;
        return Math.max(0, Math.min(100, (countdown / countdownTotal) * 100));
    }

    /* The card is rebuilt only when the REQUEST changes; the clock is redrawn
       four times a second by poking the two elements that move. Re-rendering
       the whole card on every tick threw away the buttons mid-press, which is
       a genuinely bad thing to do to a card with a deadline on it. */
    function tickClock() {
        var secs = el('req-secs');
        var bar = el('req-bar');
        if (secs) secs.textContent = Math.max(0, Math.ceil(countdown)) + 's';
        if (bar) bar.style.width = clockPct().toFixed(1) + '%';
    }

    /* Patches live numbers into the drive-HUD shell jobHtml() already built --
       creates the Leaflet map the first time this runs for a given job, then
       only ever moves markers and updates text after that. Called once a
       second by pollLive() (see below), same cadence a real nav app redraws
       its own speedometer at. */
    function tickDrive(liveData) {
        if (APP !== 'goober' || !liveData || !el('drive-hud')) return;

        if (liveData.target && el('drive-map')) {
            if (!driveMap) {
                driveMap = makeBaseMap('drive-map');
                driveDestMarker = L.marker(gToL(liveData.target.x, liveData.target.y)).addTo(driveMap);

                if (liveData.pos) {
                    driveMeMarker = L.circleMarker(gToL(liveData.pos.x, liveData.pos.y), {
                        radius: 6, color: '#ff2d95', weight: 2,
                        fillColor: '#ff2d95', fillOpacity: 1
                    }).addTo(driveMap);
                    driveMap.setView(gToL(liveData.pos.x, liveData.pos.y), 5);
                }

                setTimeout(function () { driveMap.invalidateSize(); }, 30);
            } else if (liveData.pos && driveMeMarker) {
                driveMeMarker.setLatLng(gToL(liveData.pos.x, liveData.pos.y));
            }
        }

        var speedEl = el('drive-speed');
        if (speedEl) {
            speedEl.innerHTML = (liveData.speedMph != null ? liveData.speedMph : 0)
                + '<span class="unit">mph</span>';
        }

        var badgeEl = el('drive-limit-badge');
        var limitEl = el('drive-limit');
        if (limitEl) {
            if (liveData.speedLimit != null) {
                limitEl.textContent = liveData.speedLimit;
                if (badgeEl) badgeEl.style.visibility = 'visible';
            } else if (badgeEl) {
                badgeEl.style.visibility = 'hidden';
            }
        }

        var hud = el('drive-hud');
        if (hud) hud.classList.toggle('over', !!liveData.overLimit);

        /* The freak-out. Built once when it first triggers (so the funny line
           does not reroll every second you stay over) and left up until you
           either slow down or hit Silence. */
        var alertEl = el('drive-alert');
        if (alertEl) {
            if (liveData.overLimit && !driveMuted) {
                if (!driveAlertShown) {
                    driveAlertShown = true;
                    var line = SPEED_LINES[Math.floor(Math.random() * SPEED_LINES.length)];
                    alertEl.innerHTML = '<div class="msg">' + esc(line) + '</div>'
                        + '<button class="mute" id="drive-mute">Silence</button>';
                    el('drive-mute').onclick = function () {
                        driveMuted = true;
                        alertEl.classList.remove('on');
                    };
                }
                alertEl.classList.add('on');
            } else if (!liveData.overLimit) {
                driveAlertShown = false;
                alertEl.classList.remove('on');
            }
        }
    }

    /* The "phone mounted on the dash" HUD -- Goober only, since Snarf has no
       speed mechanic and nobody is watching how you drive to a restaurant.
       This is the STATIC shell: it is rendered once per job (see the
       shownJobKey guard in renderBoard) and tickDrive() patches the live
       numbers into it afterward, the same split incomingHtml()/tickClock()
       already uses for the request countdown -- rebuilding this on every
       poll would tear down the Leaflet instance inside #drive-map. */
    function jobHtml(j) {
        var driveHud = '';
        if (APP === 'goober') {
            driveHud = '<div id="drive-hud">'
                + '<div id="drive-map"></div>'
                + '<div id="drive-meter">'
                + '<div id="drive-speed">--</div>'
                + '<div id="drive-limit-badge"><span id="drive-limit">--</span></div>'
                + '</div>'
                + '<div id="drive-alert"></div>'
                + '</div>';
        }

        return '<div class="empty">'
            + '<p><b>You are on a ' + esc(j.playerRide ? 'rider job' : 'job') + '.</b></p>'
            + '<p class="sub">' + esc(j.pickupLabel) + ' → ' + esc(j.dropoffLabel)
            + ' · $' + j.pay + '</p>'
            + '</div>'
            + driveHud
            + '<button class="danger" id="cancel">Cancel job</button>';
    }

    /* Dispatch idle: online and waiting, or offline. The pulsing dot is doing
       real work here -- without something moving, "waiting for a request" and
       "this app is broken" look identical. */
    function waitingHtml(on) {
        if (!on) {
            return '<div class="empty">'
                + '<p><b>You are offline.</b></p>'
                + '<p class="sub">Go online and requests will come to you. '
                + 'There is no list to browse — that is not how this works.</p></div>';
        }

        return '<div class="empty waiting">'
            + '<div class="pulse"></div>'
            + '<p><b>Looking for riders…</b></p>'
            + '<p class="sub">Stay near a busy area. You will get a notification '
            + 'and a few seconds to answer.</p></div>';
    }

    function renderBoard() {
        var list = el('list');
        var rateEl = el('rating');
        if (!list) return;

        if (!state) {
            list.innerHTML = '<div class="empty"><p>Could not reach ' + esc(COPY.name) + '.</p></div>';
            return;
        }

        if (rateEl) {
            rateEl.innerHTML = '<span class="stars">' + stars(state.rating) + '</span>'
                + '<span class="num">' + state.rating.toFixed(2) + '</span>';
        }

        renderDuty(state.onDuty);

        /* The nudge only shows when it is actually true, so it reads as the app
           being passive-aggressive rather than as permanent chrome.

           This is deliberately NOT the same bar that trims the offer list (that
           is the quiet punishment, on the server). warnThreshold is the loud
           "you are getting deactivated" banner, and a real app would not send
           that at a 4.4 -- it is the empty threat gig apps make, so it only
           fires once you are actually down at the floor. */
        var warn = el('warn');
        if (warn) {
            var warnAt = (typeof state.warnThreshold === 'number') ? state.warnThreshold : 1.0;
            if (state.rating <= warnAt) {
                warn.textContent = COPY.lowRating;
                warn.style.display = 'block';
            } else {
                warn.style.display = 'none';
            }
        }

        /* A live request outranks everything else on the screen. */
        var inc = (live && live.incoming) || state.incoming;
        if (inc && !(live && live.hasJob)) {
            if (shownRequest === inc.id && el('req-yes')) { tickClock(); return; }
            shownRequest = inc.id;
            list.innerHTML = incomingHtml(inc);
            el('req-yes').onclick = function () {
                setBusy(true);
                fetchNui('um_gigs:accept', { app: APP, id: inc.id }).then(function (r) {
                    setBusy(false);
                    if (r && r.ok === false) flash(r.message);
                    load();
                });
            };
            el('req-no').onclick = function () {
                fetchNui('um_gigs:decline').then(function () { pollLive(); load(); });
            };
            return;
        }

        shownRequest = null;

        var jobInfo = (live && live.job) || state.job;
        if ((live ? live.hasJob : state.hasJob) && jobInfo) {
            /* Only rebuild the shell on an actual job change (a new job, or a
               pickup->dropoff stage change, which is also when the target the
               drive-map points at moves). Every other tick just patches live
               numbers in via tickDrive() -- rebuilding via innerHTML every
               second would tear down the Leaflet instance sitting inside. */
            var jobKey = jobInfo.stage + '|' + jobInfo.pickupLabel + '|' + jobInfo.dropoffLabel;
            if (shownJobKey !== jobKey || !el('cancel')) {
                shownJobKey = jobKey;
                driveMap = null; driveMeMarker = null; driveDestMarker = null;
                driveMuted = false; driveAlertShown = false;

                list.innerHTML = jobHtml(jobInfo);
                el('cancel').onclick = function () {
                    fetchNui('um_gigs:cancel').then(load);
                };
            }

            tickDrive(live);
            return;
        }
        shownJobKey = null;

        if (state.dispatchOnly) {
            list.innerHTML = waitingHtml(state.onDuty);
            return;
        }

        if (!state.offers || state.offers.length === 0) {
            list.innerHTML = '<div class="empty"><p>Nothing right now.</p>'
                + '<p class="sub">Offers refresh every couple of minutes.</p></div>';
            return;
        }

        list.innerHTML = state.offers.map(function (o) {
            var detail = (APP === 'snarf')
                ? '<div class="detail">' + esc(o.order) + '</div>'
                  + '<div class="note">“' + esc(o.note) + '”</div>'
                : '<div class="detail">' + esc(o.passengerName) + ' · '
                  + esc(o.mood ? o.mood.label : '') + '</div>';

            return '<div class="card" data-id="' + esc(o.id) + '">'
                + '<div class="row"><span class="pay">$' + o.pay + '</span>'
                + '<span class="dist">' + km(o.distance) + '</span></div>'
                + detail
                + '<div class="leg"><span class="tag">FROM</span> ' + esc(o.pickupLabel) + '</div>'
                + '<div class="leg"><span class="tag">TO</span> ' + esc(o.dropoffLabel) + '</div>'
                + '<button class="accept">' + esc(COPY.accept) + '</button>'
                + '</div>';
        }).join('');

        Array.prototype.forEach.call(list.querySelectorAll('.card'), function (card) {
            card.querySelector('.accept').onclick = function () {
                setBusy(true);
                fetchNui('um_gigs:accept', { app: APP, id: parseInt(card.dataset.id, 10) })
                    .then(function (r) {
                        setBusy(false);
                        if (r && r.ok === false) flash(r.message);
                        load();
                    });
            };
        });
    }

    function flash(message) {
        var w = el('warn');
        if (!w) return;
        w.textContent = message || 'Could not take that job.';
        w.style.display = 'block';
    }

    /* ---- rider mode -------------------------------------------------------
       The other half of the app: you are the passenger, and the driver is
       another player. Ryde Me only -- snarf.html has no #ride view, so every
       lookup here comes back null and the whole block is a no-op there. */

    function riderIdleHtml(s) {
        var dests = s.destinations || [];
        var drivers = s.driversOnline || 0;

        var head = '<div class="ride-head confetti">'
            + '<span class="dot d1"></span><span class="dot d2"></span><span class="dot d3"></span>'
            + '<span class="dot d4"></span><span class="dot d5"></span><span class="dot d6"></span>'
            + '<div class="ride-q">Where to?</div>'
            + '<div class="ride-sub">' + drivers + (drivers === 1 ? ' driver' : ' drivers')
            + ' online right now</div></div>';

        /* A segmented tier choice, not two buttons per row: pick real-driver
           or NPC once, then every destination below books at that tier -- the
           same shape as choosing "Comfort" vs "X" before the list appears. */
        var mode = '<div class="ride-mode">'
            + '<button class="' + (rideMode === 'real' ? 'on' : '') + '" data-mode="real">Real driver'
            + '<span class="sub">a person · costs more</span></button>'
            + '<button class="' + (rideMode === 'npc' ? 'on' : '') + '" data-mode="npc">NPC driver'
            + '<span class="sub">instant · costs less</span></button>'
            + '</div>';

        /* Two ways into the same map preview: tap around in the app itself,
           or shortcut straight to wherever the player already dropped a pin
           on their own map. Both sit in the destination list, styled as the
           same kind of row -- they are other ways to pick a destination, not
           a separate feature bolted on top. */
        var rows = '<div class="dests">'
            + '<button class="dest map-pick" data-map="1">'
            + '<span class="dest-label">🗺️ Pick on map</span>'
            + '<span class="dest-meta">tap to drop a pin</span>'
            + '</button>'
            + '<button class="dest use-waypoint" data-map="1">'
            + '<span class="dest-label">📍 Use my waypoint</span>'
            + '<span class="dest-meta">already set one</span>'
            + '</button>';

        if (dests.length) {
            rows += dests.map(function (d) {
                return '<button class="dest" data-index="' + d.index + '">'
                    + '<span class="dest-label">' + esc(d.label) + '</span>'
                    + '<span class="dest-meta">' + km(d.distance) + '</span>'
                    + '<span class="dest-fare">$' + d.fare + '</span>'
                    + '</button>';
            }).join('');
        }

        rows += '</div>';

        return head + mode + rows
            + '<div class="ride-foot">Fares are estimates. rydeme keeps a service fee.</div>';
    }

    /* ---- destination map: pick a spot in the app, or reuse the game's own --
       Tapping the map IS the primary way to choose a destination here -- the
       resolving (ground height, road snap, street name) happens client-side
       in client.lua via RequestCollisionAtCoord, which works for a tap
       anywhere, not just near the player. "Use my waypoint" is a shortcut
       into the exact same picker for someone who already dropped a pin on
       their own map instead. */

    var GTA_CRS = null;
    function buildCRS() {
        if (GTA_CRS) return GTA_CRS;
        GTA_CRS = L.extend({}, L.CRS.Simple, {
            projection: L.Projection.LonLat,
            scale: function (z) { return Math.pow(2, z); },
            zoom: function (s) { return Math.log(s) / Math.LN2; },
            distance: function (a, b) {
                var dx = b.lng - a.lng, dy = b.lat - a.lat;
                return Math.sqrt(dx * dx + dy * dy);
            },
            transformation: new L.Transformation(0.02072, 117.3, -0.0205, 172.8),
            infinite: true
        });
        return GTA_CRS;
    }

    function gToL(x, y) { return [2.566 * y - 5585.98, 2.566 * x - 1325.11]; }
    function lToG(lat, lng) { return { x: (lng + 1325.11) / 2.566, y: (lat + 5585.98) / 2.566 }; }

    var SAT_URL = 'nui://night_shifts_mdt/NUI/img/map/satellite.png';
    var MAP_BOUNDS = [[-16000, -16000], [16000, 16000]];

    /* The bare tiles-and-projection map, with no interaction wired on top --
       shared by the destination picker (which adds a click handler) and the
       driver's live drive-HUD map (which does not; it is a read-only "you
       are here" view, not a second way to set a destination). */
    function makeBaseMap(elId) {
        var container = el(elId);
        if (container) container.classList.add('loading');

        var m = L.map(elId, {
            crs: buildCRS(), minZoom: 1, maxZoom: 6,
            center: gToL(0, 0), zoom: 4,
            preferCanvas: true, zoomControl: false
        });
        L.control.zoom({ position: 'topright' }).addTo(m);

        /* The tile is a large image fetched over nui:// (from night_shifts_mdt,
           not this resource), so it can take a moment -- or, if that resource
           is not running, never arrive at all. Either way the map area should
           say so rather than sit there looking like nothing rendered. */
        var sat = L.imageOverlay(SAT_URL, MAP_BOUNDS, { opacity: 1 });
        sat.on('load', function () {
            if (container) container.classList.remove('loading', 'map-error');
        });
        sat.on('error', function () {
            console.warn('rydeme: satellite tile failed to load from ' + SAT_URL
                + ' -- is night_shifts_mdt running?');
            if (container) {
                container.classList.remove('loading');
                container.classList.add('map-error');
            }
        });
        sat.addTo(m);

        return m;
    }

    function makeRideMap() {
        var m = makeBaseMap('ride-map');

        /* Every click resolves fresh, same as a real destination pin: the
           previous marker just moves rather than a second one appearing. */
        m.on('click', function (e) {
            var g = lToG(e.latlng.lat, e.latlng.lng);
            el('ride-map-confirm').innerHTML = '<p class="sub">Finding that spot…</p>';

            fetchNui('um_gigs:resolveMapPoint', { x: g.x, y: g.y }).then(function (res) {
                if (!res || res.ok === false) {
                    el('ride-map-confirm').innerHTML = '<p class="sub">'
                        + esc((res && res.message) || 'Could not use that spot.') + '</p>';
                    return;
                }
                placePoint({ x: res.x, y: res.y, z: res.z, label: res.label });
            });
        });

        return m;
    }

    /* Drops/moves the marker on an already-resolved point, prices it, and
       wires the request button -- shared by a map tap and the waypoint
       shortcut, so the two behave identically once a point is in hand. */
    function placePoint(point) {
        var ll = gToL(point.x, point.y);

        if (rideMarker) rideMarker.setLatLng(ll);
        else rideMarker = L.marker(ll).addTo(rideMap);
        rideMap.setView(ll, 4);

        el('ride-map-confirm').innerHTML = '<p class="sub">Getting a price…</p>';

        fetchNui('um_gigs:quoteRide', { custom: point, npc: rideMode === 'npc' }).then(function (q) {
            if (!q || q.ok === false) {
                el('ride-map-confirm').innerHTML = '<p class="sub">Could not price that spot.</p>';
                return;
            }

            el('ride-map-confirm').innerHTML =
                '<div class="map-quote"><span>' + esc(point.label || 'Dropped pin') + '</span>'
                + '<span class="dest-fare">$' + q.fare + '</span></div>'
                + '<button id="map-request">Request this ride</button>';

            el('map-request').onclick = function () {
                el('map-request').disabled = true;
                fetchNui('um_gigs:requestRide', { custom: point, npc: rideMode === 'npc' })
                    .then(function (r) {
                        if (r && r.ok === false) {
                            el('ride-map-confirm').insertAdjacentHTML('beforeend',
                                '<div class="ride-err">' + esc(r.message) + '</div>');
                            el('map-request').disabled = false;
                            return;
                        }
                        closeMapPicker();
                        load();
                    });
            };
        });
    }

    /* Opens the picker. `seed` is a resolved point to drop straight onto (the
       waypoint shortcut); leave it out to open blank, centred on the player,
       ready for a tap. */
    function openMapPicker(seed) {
        el('ride-map-overlay').classList.add('on');
        if (!rideMap) rideMap = makeRideMap();
        setTimeout(function () { rideMap.invalidateSize(); }, 30);

        if (seed) {
            placePoint(seed);
            return;
        }

        el('ride-map-confirm').innerHTML = '<p class="sub">Tap the map to drop a pin.</p>';
        fetchNui('um_gigs:getMyCoords').then(function (me) {
            if (me && me.ok) rideMap.setView(gToL(me.x, me.y), 5);
        });
    }

    /* The waypoint shortcut: reads the player's own waypoint (client.lua, not
       the server -- blips are client-only state) and opens the same picker
       already dropped on it. If none is set this drops the same inline error
       the destination-list request failures use, since #ride has nowhere
       else to put one while this tab is open. */
    function openMapPickerFromWaypoint() {
        fetchNui('um_gigs:getMyWaypoint').then(function (wp) {
            if (!wp || wp.ok === false) {
                var host = el('ride');
                if (host) {
                    var old = host.querySelector('.ride-err');
                    if (old) old.remove();
                    host.insertAdjacentHTML('afterbegin', '<div class="ride-err">'
                        + esc((wp && wp.message) || 'Set a waypoint on your map first.') + '</div>');
                }
                return;
            }
            openMapPicker(wp);
        });
    }

    function closeMapPicker() {
        var overlay = el('ride-map-overlay');
        if (overlay) overlay.classList.remove('on');
    }

    function riderActiveHtml(r) {
        var body;

        if (r.state === 'searching') {
            body = '<div class="empty waiting"><div class="pulse"></div>'
                + '<p><b>Finding you a driver…</b></p>'
                + '<p class="sub">' + esc(r.destLabel) + ' · $' + r.fare
                + (r.secondsLeft != null ? ' · ' + r.secondsLeft + 's left' : '')
                + '</p></div>';
        } else if (r.state === 'assigned') {
            body = '<div class="empty"><p><b>' + esc(r.driverName || 'Your driver')
                + '</b> is on the way.</p>'
                + '<p class="sub">'
                + (r.driverRating ? stars(r.driverRating) + ' ' + r.driverRating.toFixed(2) : '')
                + (r.vehicle ? ' · ' + esc(r.vehicle) : '')
                + (r.tier ? ' · ' + esc(r.tier) : '')
                + '</p>'
                + '<p class="sub">Get in when they pull up.</p></div>';
        } else if (r.state === 'onboard') {
            body = '<div class="empty"><p><b>On the way to ' + esc(r.destLabel) + '.</b></p>'
                + '<p class="sub">Driven by ' + esc(r.driverName || 'your driver') + '.</p></div>';
        } else {
            body = '<div class="empty"><p><b>Ride ended.</b></p>'
                + '<p class="sub">' + esc(r.reason || '') + '</p></div>';
        }

        var cancellable = (r.state === 'searching' || r.state === 'assigned' || r.state === 'onboard');

        return body + (cancellable
            ? '<div class="ride-foot"><button class="danger" id="ride-cancel">Cancel ride</button></div>'
            : '');
    }

    /* The one rating in this whole resource written by a person rather than
       picked out of a table. It gets its own screen for that reason. */
    function rateHtml(p) {
        var picks = '';
        for (var i = 1; i <= 5; i++) {
            picks += '<button class="star' + (i <= rating.stars ? ' on' : '') + '" data-n="' + i + '">★</button>';
        }

        return '<div class="rate">'
            + '<div class="ride-q">How was your ride?</div>'
            + '<div class="ride-sub">' + esc(p.driverName || 'Your driver')
            + ' · ' + esc(p.destLabel || '') + ' · $' + p.fare + '</div>'
            + '<div class="star-row">' + picks + '</div>'
            + '<textarea id="rate-note" maxlength="90" placeholder="Say something (optional)">'
            + esc(rating.comment) + '</textarea>'
            + '<button id="rate-send">Submit rating</button>'
            + '</div>';
    }

    /* ---- NPC ride: the rider-side view while an AI driver is doing the work.
       Entirely driven by live.npcRide (client.lua, no server round trip) --
       see the note on tickDrive() for why this is a static shell rebuilt only
       on a phase change, patched live in between: the map inside it would be
       torn down by a full innerHTML rebuild every poll. */
    function npcRideHtml(n) {
        if (n.phase === 'done') {
            var picks = '';
            for (var i = 1; i <= 5; i++) {
                picks += '<button class="star' + (i <= rating.stars ? ' on' : '') + '" data-n="' + i + '">★</button>';
            }
            return '<div class="rate">'
                + '<div class="ride-q">How was your AI driver?</div>'
                + '<div class="ride-sub">' + esc(n.destLabel || '') + '</div>'
                + '<div class="star-row">' + picks + '</div>'
                + '<button id="npc-rate-send">Submit rating</button>'
                + '</div>';
        }

        var boarded = n.phase === 'boarded';

        return '<div class="empty">'
            + '<p><b>' + (boarded ? 'On the way to ' + esc(n.destLabel) + '.' : 'Your driver is on the way.') + '</b></p>'
            + '</div>'
            + '<div id="npc-map"></div>'
            + (boarded
                ? '<div class="npc-actions">'
                  + '<button id="npc-speedup"' + (n.speedBoost ? ' disabled' : '') + '>'
                  + (n.speedBoost ? 'Speeding up…' : 'Tell them to speed up')
                  + '</button>'
                  + '<button class="danger" id="npc-end">End fare here</button>'
                  + '</div>'
                : '');
    }

    /* Patches the live bits into whichever phase npcRideHtml() built: the car
       marker while it is coming to you, your own marker plus the destination
       pin once you are aboard, and the Speed Up button's state either way. */
    function tickNpcRide(n) {
        if (!el('npc-map')) return;
        if (!npcMap) npcMap = makeBaseMap('npc-map');

        if (n.phase === 'approach' && n.driverPos) {
            if (!npcCarMarker) {
                npcCarMarker = L.circleMarker(gToL(n.driverPos.x, n.driverPos.y), {
                    radius: 6, color: '#ff2d95', weight: 2, fillColor: '#ff2d95', fillOpacity: 1
                }).addTo(npcMap);
            } else {
                npcCarMarker.setLatLng(gToL(n.driverPos.x, n.driverPos.y));
            }

            if (n.pos) {
                if (!npcMeMarker) {
                    npcMeMarker = L.circleMarker(gToL(n.pos.x, n.pos.y), {
                        radius: 5, color: '#f4e9f2', weight: 2, fillColor: '#f4e9f2', fillOpacity: 1
                    }).addTo(npcMap);
                } else {
                    npcMeMarker.setLatLng(gToL(n.pos.x, n.pos.y));
                }
            }

            /* A fixed setView() on just the car put the "you" marker off-screen
               whenever the driver spawned far away -- there was nothing on the
               map to gauge distance against. Fitting both markers keeps you
               visible for the whole approach, converging naturally as the car
               gets close. */
            if (!npcMapCentred) {
                npcMapCentred = true;
                if (n.pos) {
                    npcMap.fitBounds([gToL(n.driverPos.x, n.driverPos.y), gToL(n.pos.x, n.pos.y)], {
                        padding: [36, 36], maxZoom: 6
                    });
                } else {
                    npcMap.setView(gToL(n.driverPos.x, n.driverPos.y), 5);
                }
                setTimeout(function () { npcMap.invalidateSize(); }, 30);
            }
        } else if (n.phase === 'boarded' && n.pos) {
            if (!npcMeMarker) {
                npcMeMarker = L.circleMarker(gToL(n.pos.x, n.pos.y), {
                    radius: 6, color: '#ff2d95', weight: 2, fillColor: '#ff2d95', fillOpacity: 1
                }).addTo(npcMap);
            } else {
                npcMeMarker.setLatLng(gToL(n.pos.x, n.pos.y));
            }

            if (n.destPos && !npcDestMarker) {
                npcDestMarker = L.marker(gToL(n.destPos.x, n.destPos.y)).addTo(npcMap);
            }

            if (!npcMapCentred) {
                npcMapCentred = true;
                npcMap.setView(gToL(n.pos.x, n.pos.y), 5);
                setTimeout(function () { npcMap.invalidateSize(); }, 30);
            }
        }

        var speedBtn = el('npc-speedup');
        if (speedBtn && n.speedBoost) {
            speedBtn.disabled = true;
            speedBtn.textContent = 'Speeding up…';
        }
    }

    function renderRide() {
        var host = el('ride');
        if (!host || !state) return;

        if (live && live.npcRide) {
            var n = live.npcRide;

            if (shownNpcPhase !== n.phase) {
                shownNpcPhase = n.phase;
                npcMap = null; npcCarMarker = null; npcMeMarker = null; npcDestMarker = null;
                npcMapCentred = false;

                host.innerHTML = npcRideHtml(n);

                if (n.phase === 'done') {
                    Array.prototype.forEach.call(host.querySelectorAll('.star'), function (b) {
                        b.onclick = function () { rating.stars = parseInt(b.dataset.n, 10); renderRide(); };
                    });
                    el('npc-rate-send').onclick = function () {
                        fetchNui('um_gigs:npcRateDriver', { stars: rating.stars }).then(function () {
                            rating = { stars: 5, comment: '' };
                            shownNpcPhase = null;
                            load();
                        });
                    };
                } else {
                    var speedBtn = el('npc-speedup');
                    if (speedBtn) speedBtn.onclick = function () { fetchNui('um_gigs:npcSpeedUp'); };

                    var endBtn = el('npc-end');
                    if (endBtn) {
                        endBtn.onclick = function () {
                            endBtn.disabled = true;
                            fetchNui('um_gigs:npcEndRide');
                        };
                    }
                }
            }

            if (n.phase !== 'done') tickNpcRide(n);
            return;
        }
        shownNpcPhase = null;

        if (state.rateDriver) {
            host.innerHTML = rateHtml(state.rateDriver);

            Array.prototype.forEach.call(host.querySelectorAll('.star'), function (b) {
                b.onclick = function () {
                    rating.stars = parseInt(b.dataset.n, 10);
                    renderRide();
                };
            });

            el('rate-send').onclick = function () {
                var note = el('rate-note');
                rating.comment = note ? note.value : '';
                fetchNui('um_gigs:rateDriver', {
                    stars: rating.stars,
                    comment: rating.comment
                }).then(function () {
                    rating = { stars: 5, comment: '' };
                    load();
                });
            };
            return;
        }

        if (state.ride && state.ride.state) {
            host.innerHTML = riderActiveHtml(state.ride);
            var c = el('ride-cancel');
            if (c) {
                c.onclick = function () {
                    fetchNui('um_gigs:cancelRide').then(load);
                };
            }
            return;
        }

        if (live && live.hasJob) {
            host.innerHTML = '<div class="empty"><p><b>You are driving.</b></p>'
                + '<p class="sub">Finish your fare before booking one of your own.</p></div>';
            return;
        }

        host.innerHTML = riderIdleHtml(state);

        Array.prototype.forEach.call(host.querySelectorAll('.ride-mode button'), function (b) {
            b.onclick = function () {
                rideMode = b.dataset.mode;
                renderRide();
            };
        });

        var mapBtn = host.querySelector('.map-pick');
        if (mapBtn) mapBtn.onclick = function () { openMapPicker(); };

        var waypointBtn = host.querySelector('.use-waypoint');
        if (waypointBtn) waypointBtn.onclick = openMapPickerFromWaypoint;

        /* [data-index] excludes the map-pick and use-waypoint buttons -- both
           are styled as a .dest but carry no index, and parseInt(undefined)
           is NaN, which used to wire them to a broken request. */
        Array.prototype.forEach.call(host.querySelectorAll('.dest[data-index]'), function (b) {
            b.onclick = function () {
                b.disabled = true;
                fetchNui('um_gigs:requestRide', {
                    index: parseInt(b.dataset.index, 10),
                    npc: rideMode === 'npc'
                }).then(function (r) {
                    if (r && r.ok === false) {
                        host.insertAdjacentHTML('afterbegin',
                            '<div class="ride-err">' + esc(r.message) + '</div>');
                        b.disabled = false;
                        return;
                    }
                    load();
                });
            };
        });
    }

    /* ---- Driver Profile ---------------------------------------------------
       Ryde Me only: goober.html is the one page with a #profile screen. */

    function timeAgo(ts) {
        var diff = Math.floor(Date.now() / 1000) - ts;
        if (diff < 60) return 'just now';
        if (diff < 3600) return Math.floor(diff / 60) + 'm ago';
        if (diff < 86400) return Math.floor(diff / 3600) + 'h ago';
        return Math.floor(diff / 86400) + 'd ago';
    }

    function renderProfile(res) {
        var statsEl = el('profile-stats');
        var histEl = el('profile-history');
        var alertEl = el('profile-alert');
        if (!statsEl || !histEl) return;

        if (!res) {
            statsEl.innerHTML = '';
            histEl.innerHTML = '<div class="empty"><p>Could not load your profile.</p></div>';
            if (alertEl) alertEl.innerHTML = '';
            return;
        }

        setAvatar(res.avatar || null);

        /* The big "you tanked it" moment. Same bar the board's quiet #warn
           banner uses (warnThreshold, the rating floor) -- this is just the
           loud version of the same fact, shown where a real app would put it. */
        if (alertEl) {
            var warnAt = (typeof res.warnThreshold === 'number') ? res.warnThreshold : 1.0;
            alertEl.innerHTML = (res.rating <= warnAt)
                ? '<div class="suspend-alert">'
                  + '<div class="icon">⚠</div>'
                  + '<div class="title">Driver account suspended</div>'
                  + '<div class="msg-pill">' + esc(COPY.lowRating) + '</div>'
                  + '</div>'
                : '';
        }

        statsEl.innerHTML = '<div class="num-big">' + res.rating.toFixed(2) + '</div>'
            + '<span class="stars">' + stars(res.rating) + '</span>'
            + '<div class="sub">' + (res.history ? res.history.length : 0) + ' recent rides</div>';

        if (!res.history || res.history.length === 0) {
            histEl.innerHTML = '<div class="empty"><p>No rides yet.</p>'
                + '<p class="sub">They will show up here as you finish them.</p></div>';
            return;
        }

        histEl.innerHTML = res.history.map(function (h) {
            var tags = '';
            if (h.player) tags += '<span class="chip">real rider</span>';
            if (h.aborted) tags += '<span class="chip bad">never arrived</span>';
            if (h.tier) tags += '<span class="chip">' + esc(h.tier) + '</span>';

            return '<div class="card">'
                + '<div class="row"><b>' + esc(h.name) + '</b>'
                + '<span class="stars">' + stars(h.stars) + '</span></div>'
                + (tags ? '<div class="chips">' + tags + '</div>' : '')
                + (h.comment ? '<div class="note">“' + esc(h.comment) + '”</div>' : '')
                + '<div class="dist">$' + h.pay + (h.tip ? ' + $' + h.tip + ' tip' : '')
                + ' · ' + timeAgo(h.ts) + '</div>'
                + '</div>';
        }).join('');
    }

    /* ---- views ------------------------------------------------------------ */

    function showView(name) {
        var board = el('board');
        var profile = el('profile');
        var ride = el('ride');
        if (!board) return;

        view = name;
        board.style.display = name === 'board' ? 'block' : 'none';
        if (profile) profile.style.display = name === 'profile' ? 'block' : 'none';
        if (ride) ride.style.display = name === 'ride' ? 'block' : 'none';

        Array.prototype.forEach.call(document.querySelectorAll('#tabbar .tab'), function (btn) {
            btn.classList.toggle('on', btn.dataset.tab === name);
        });

        if (name === 'profile') {
            var h = el('profile-history');
            if (h) h.innerHTML = '<div class="empty"><p>Loading…</p></div>';
            fetchNui('um_gigs:getProfile', { app: APP }).then(renderProfile);
        } else if (name === 'ride') {
            renderRide();
        }
    }

    function renderCurrent() {
        if (view === 'ride') renderRide();
        else if (view === 'board') renderBoard();
    }

    /* ---- polling ---------------------------------------------------------- */

    function load() {
        return fetchNui('um_gigs:getState', { app: APP }).then(function (res) {
            state = res;
            setBusy(false);
            renderCurrent();
            return res;
        });
    }

    /* The client answers this one itself, so it is cheap enough to run every
       second -- which is what an accept-or-lose-it countdown needs. */
    function pollLive() {
        return fetchNui('um_gigs:getLive').then(function (res) {
            var hadIncoming = !!(live && live.incoming);
            live = res;

            if (res && res.incoming) {
                var secs = res.incomingSeconds || 0;
                // The card's own starting figure, taken from the first answer
                // about it rather than assumed from config -- the app should
                // not need to know what the response window is set to.
                if (!hadIncoming || secs > countdownTotal) countdownTotal = secs;
                countdown = secs;
                if (view === 'board') renderBoard();
            } else if (hadIncoming) {
                countdown = 0;
                countdownTotal = 0;
                shownRequest = null;
                load();
            } else if (res && res.hasJob && view === 'board') {
                // The drive HUD: speed, limit, and the live map marker all
                // need this same 1Hz cadence, same as a real nav app's own
                // speedometer redraw. renderBoard() only tears the shell down
                // on an actual job change (see shownJobKey) -- every other
                // call here just patches numbers into it via tickDrive().
                renderBoard();
            } else if (res && res.npcRide && view === 'ride') {
                // Same idea, rider side: the car/you markers need the 1Hz
                // cadence while an NPC ride is in progress. renderRide() only
                // rebuilds on a phase change (see shownNpcPhase) -- everything
                // else here just moves markers via tickNpcRide().
                renderRide();
            }

            return res;
        });
    }

    Array.prototype.forEach.call(document.querySelectorAll('#tabbar .tab'), function (btn) {
        btn.onclick = function () { showView(btn.dataset.tab); };
    });

    /* #ride-map-overlay is a permanent sibling of #board/#profile/#ride (see
       the CSS note on it), so its back button is wired once here rather than
       inside a render function that runs again every poll. */
    var mapBackEl = el('map-back');
    if (mapBackEl) mapBackEl.onclick = closeMapPicker;

    /* Ryde Me's wordmark is static two-tone markup baked into its HTML, not
       plain text -- overwriting it here would wipe out the colour split. */
    var brandEl = el('brand');
    if (brandEl) brandEl.textContent = COPY.name;
    var tagEl = el('tagline');
    if (tagEl) tagEl.textContent = COPY.tagline;

    var refreshEl = el('refresh');
    if (refreshEl) refreshEl.onclick = function () { setBusy(true); load(); };

    /* ---- Avatar picker -----------------------------------------------------
       #avatar-sheet is, like #ride-map-overlay, a permanent sibling wired once
       here rather than rebuilt by a render function. */
    var avatarBtnEl = el('avatar-btn');
    var avatarImgEl = el('avatar-img');
    var avatarSheetEl = el('avatar-sheet');
    var avatarCameraOverlayEl = el('avatar-camera-overlay');
    var avatarCameraCanvasEl = el('avatar-camera-canvas');
    var avatarGameRender = null; // live components.createGameRender() handle while the viewfinder is open

    function setAvatar(src) {
        if (!avatarBtnEl || !avatarImgEl) return;
        if (src) {
            avatarImgEl.src = src;
            avatarBtnEl.classList.add('has-photo');
        } else {
            avatarImgEl.removeAttribute('src');
            avatarBtnEl.classList.remove('has-photo');
        }
    }

    function saveAvatar(src) {
        if (!src) return;
        setAvatar(src);
        fetchNui('um_gigs:setAvatar', { app: APP, avatar: src });
    }

    function openAvatarSheet() { if (avatarSheetEl) avatarSheetEl.classList.add('on'); }
    function closeAvatarSheet() { if (avatarSheetEl) avatarSheetEl.classList.remove('on'); }

    if (avatarBtnEl) avatarBtnEl.onclick = openAvatarSheet;
    var avatarCancelEl = el('avatar-cancel');
    if (avatarCancelEl) avatarCancelEl.onclick = closeAvatarSheet;
    if (avatarSheetEl) {
        avatarSheetEl.onclick = function (e) { if (e.target === avatarSheetEl) closeAvatarSheet(); };
    }

    /* ---- Choose from camera roll --------------------------------------------
       The phone's own gallery picker, bridged in via globalThis.components
       (injected into every custom app's iframe -- see lb-phone's custom-apps
       docs). data.src comes back already usable straight as an <img src>. */
    function pickFromCameraRoll() {
        closeAvatarSheet();
        if (!window.components || !window.components.setGallery) {
            console.error('lb-phone gallery component is unavailable');
            return;
        }
        window.components.setGallery({
            includeVideos: false,
            includeImages: true,
            allowExternal: true,
            multiSelect: false,
            onSelect: function (data) {
                var item = Array.isArray(data) ? data[0] : data;
                if (item && item.src) saveAvatar(item.src);
            }
        });
    }
    var avatarRollEl = el('avatar-roll');
    if (avatarRollEl) avatarRollEl.onclick = pickFromCameraRoll;

    /* ---- Take photo -----------------------------------------------------
       The phone's ACTUAL in-game camera (the same live game-view feed its own
       Camera app uses), not a file-system picker -- createGameRender() paints
       the live view into #avatar-camera-canvas so the driver can compose the
       shot before capturing, same as any real camera viewfinder. */
    function closeAvatarCamera() {
        if (avatarCameraOverlayEl) avatarCameraOverlayEl.classList.remove('on');
        if (avatarGameRender) {
            try { avatarGameRender.destroy(); } catch (e) { /* already gone */ }
            avatarGameRender = null;
        }
    }

    function openAvatarCamera() {
        closeAvatarSheet();
        if (!window.components || !window.components.createGameRender || !avatarCameraCanvasEl) {
            console.error('lb-phone camera component is unavailable');
            return;
        }
        if (avatarCameraOverlayEl) avatarCameraOverlayEl.classList.add('on');
        avatarGameRender = window.components.createGameRender(avatarCameraCanvasEl);
        if (avatarGameRender && avatarGameRender.resizeByAspect) avatarGameRender.resizeByAspect(1);
    }

    function shootAvatarPhoto() {
        if (!avatarGameRender) return;
        var render = avatarGameRender;
        Promise.resolve(render.takePhoto())
            .then(function (blob) { return window.components.uploadMedia('Image', blob); })
            .then(function (url) {
                /* Also drops it in the driver's own gallery, same as a real
                   camera shot would -- a bonus, not required for the avatar
                   itself, so a failure here does not block setting it. */
                if (window.components.saveToGallery) {
                    window.components.saveToGallery(url).catch(function () {});
                }
                saveAvatar(url);
            })
            .catch(function (err) { console.error('avatar photo failed', err); })
            .then(closeAvatarCamera);
    }

    var avatarTakeEl = el('avatar-take');
    if (avatarTakeEl) avatarTakeEl.onclick = openAvatarCamera;
    var avatarCameraBackEl = el('avatar-camera-back');
    if (avatarCameraBackEl) avatarCameraBackEl.onclick = closeAvatarCamera;
    var avatarCameraShootEl = el('avatar-camera-shoot');
    if (avatarCameraShootEl) avatarCameraShootEl.onclick = shootAvatarPhoto;

    var dutyEl = el('duty');
    if (dutyEl) {
        dutyEl.onclick = function () {
            var goingOn = !dutyEl.classList.contains('on');
            setBusy(true);
            fetchNui('um_gigs:setDuty', { app: APP, on: goingOn }).then(function () {
                /* Reload rather than assuming: the server owns duty state. */
                load();
            });
        };
    }

    load();
    pollLive();

    /* Server state changes whether or not the app is open, but slowly. */
    setInterval(load, 12000);

    /* The card in front of the driver changes by the second. Ticked locally
       between polls so the bar drains smoothly instead of in one-second jumps
       whenever the fetch happens to land. */
    setInterval(pollLive, 1000);
    setInterval(function () {
        if (live && live.incoming && countdown > 0) {
            countdown -= 0.25;
            if (view === 'board') tickClock();
        }
    }, 250);
})();
