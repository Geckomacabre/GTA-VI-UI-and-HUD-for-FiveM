(function () {
    'use strict';

    var REFERENCE_HEIGHT = 1080; // the layout numbers in config.lua are 1080p

    var root     = document.documentElement;
    var radio    = document.getElementById('radio');
    var track    = document.getElementById('track');
    var iconL    = document.getElementById('icon-left');
    var iconLImg = document.getElementById('icon-left-img');
    var odSwitch = document.getElementById('od-switch-graphic');
    var iconR    = document.getElementById('icon-right');
    var elLine   = document.getElementById('info-line');
    var elStat   = document.getElementById('station');
    var elTitle  = document.getElementById('title');
    var elArtist = document.getElementById('artist');

    var od          = document.getElementById('od');
    var odForm      = document.getElementById('od-form');
    var odUrl       = document.getElementById('od-url');
    var odQueueBtn  = document.getElementById('od-queue-btn');
    var odNotice    = document.getElementById('od-notice');
    var odQueue     = document.getElementById('od-queue');
    var odQueueNum  = document.getElementById('od-queue-count');
    var odNowTitle  = document.getElementById('od-now-title');
    var odNowArtist = document.getElementById('od-now-artist');
    var odTransport = document.getElementById('od-transport');
    var odVolume    = document.getElementById('od-volume');
    var odVolumeVal = document.getElementById('od-volume-value');
    var odMute      = document.getElementById('od-mute');
    var odClose     = document.getElementById('od-close');
    var odSwitch    = document.getElementById('od-switch');
    var odSwitchTxt = odSwitch.querySelector('.switch-state');

    var hud       = null;
    var stations  = [];
    var index     = 0;
    var muted     = false;
    var odOn      = false;
    var label     = null;   // overrides the station name while On Demand owns the audio
    var isOpen    = false;
    var flashTimer = null;

    // -- helpers -----------------------------------------------------------

    function rgba(str, fallback) {
        var parts = String(str || '').split(',').map(function (n) { return parseFloat(n); });
        if (parts.length < 3 || parts.some(isNaN)) return fallback;
        var a = parts.length > 3 ? parts[3] / 255 : 1;
        return 'rgba(' + parts[0] + ',' + parts[1] + ',' + parts[2] + ',' + a.toFixed(3) + ')';
    }

    function scale() {
        return window.innerHeight / REFERENCE_HEIGHT;
    }

    function px(n) { return n + 'px'; }

    function applyHud(cfg) {
        hud = cfg;
        var s = root.style;
        var font = cfg.fontPx || 94;

        s.setProperty('--s', scale());
        s.setProperty('--icon', px(cfg.iconSize));
        s.setProperty('--spacing', px(cfg.spacing));
        s.setProperty('--top', px(cfg.top));
        s.setProperty('--border', px(cfg.borderSize));
        s.setProperty('--box', rgba(cfg.boxColor, 'rgba(0,0,0,0.667)'));
        s.setProperty('--box-active', rgba(cfg.boxActiveColor, 'rgba(45,45,45,0.863)'));
        s.setProperty('--outline', rgba(cfg.borderColor, 'rgba(255,255,255,0.353)'));
        s.setProperty('--outline-active', rgba(cfg.borderActiveColor, 'rgba(255,255,255,1)'));
        s.setProperty('--slide', (cfg.slideTime || 110) + 'ms');
        s.setProperty('--side-gap', px(cfg.sideGap));
        s.setProperty('--left-icon-h', px(cfg.leftIconHeight));
        s.setProperty('--right-icon-h', px(cfg.rightIconHeight));
        s.setProperty('--mute-color', rgba(cfg.muteColor, '#ffffff'));
        s.setProperty('--muted-color', rgba(cfg.mutedColor, '#ff3b30'));
        radio.classList.toggle('dim-off', cfg.muteDim === false);
        s.setProperty('--line-y', px(cfg.infoLineY));
        s.setProperty('--line-w', px(cfg.infoLineWidth));
        s.setProperty('--line-h', px(cfg.infoLineHeight));
        s.setProperty('--station-y', px(cfg.stationY));
        s.setProperty('--station-size', px(font * cfg.stationScale));
        s.setProperty('--title-y', px(cfg.titleY));
        s.setProperty('--title-size', px(font * cfg.titleScale));
        s.setProperty('--artist-y', px(cfg.artistY));
        s.setProperty('--artist-size', px(font * cfg.artistScale));

        // With On Demand on the left icon is a live switch; without it, it is
        // the static artwork the original mod drew there.
        if (cfg.leftIcon) iconLImg.src = cfg.leftIcon;
        iconLImg.hidden = !!cfg.odSwitch;
        odSwitch.hidden = !cfg.odSwitch;
        iconL.style.display = cfg.sideIcons ? '' : 'none';
        iconR.style.display = cfg.sideIcons ? '' : 'none';
        elLine.style.display = cfg.infoLineHeight > 0 ? '' : 'none';
    }

    function buildTrack(list) {
        stations = list || [];
        track.innerHTML = '';

        stations.forEach(function (station) {
            var tile = document.createElement('div');
            tile.className = 'tile';

            if (station.logo && (!hud || hud.stationLogos !== false)) {
                var img = document.createElement('img');
                img.src = station.logo;
                // A missing PNG should not leave an empty box.
                img.onerror = function () {
                    tile.innerHTML = '';
                    tile.appendChild(fallbackNode(station.label));
                };
                tile.appendChild(img);
            } else {
                tile.appendChild(fallbackNode(station.label));
            }

            track.appendChild(tile);
        });
    }

    // Paints a white glyph PNG as a mask so it can be tinted. A div has no
    // intrinsic size, so the aspect ratio is read off the file once and cached.
    var ratioCache = {};

    function setMaskIcon(el, src) {
        if (!src) return;
        el.style.webkitMaskImage = 'url("' + src + '")';
        el.style.maskImage = 'url("' + src + '")';

        if (ratioCache[src]) {
            el.style.aspectRatio = ratioCache[src];
            return;
        }

        var probe = new Image();
        probe.onload = function () {
            if (!probe.naturalHeight) return;
            ratioCache[src] = probe.naturalWidth + ' / ' + probe.naturalHeight;
            el.style.aspectRatio = ratioCache[src];
        };
        probe.src = src;
    }

    function fallbackNode(label) {
        var span = document.createElement('span');
        span.className = 'fallback';
        span.textContent = label || '';
        return span;
    }

    function render() {
        var tiles = track.children;
        for (var i = 0; i < tiles.length; i++) {
            tiles[i].classList.toggle('active', i === index);
        }

        if (hud) {
            var step = hud.spacing * scale();
            track.style.transform = 'translateX(' + (-(index * step) - step / 2) + 'px)';
        }

        var station = stations[index];
        elStat.textContent = label || (station ? station.label : '');

        radio.classList.toggle('muted', muted);
        radio.classList.toggle('od-on', odOn);

        if (hud) setMaskIcon(iconR, muted ? hud.unmuteIcon : hud.rightIcon);
    }

    function renderNowPlaying(title, artist) {
        var station = stations[index];
        // A highlighted "radio off" tile blanks the lines -- unless On Demand
        // is what is actually playing, in which case they are not its lines.
        var isOff = station && station.off && !label;

        if (isOff) {
            elTitle.textContent = '';
            elArtist.textContent = '';
            return;
        }

        // Either line on its own is still a live feed. On Demand with an empty
        // queue sends only the second one ("Nothing queued"), and falling
        // through to the genre below would answer it with the highlighted
        // station's -- which is not what is playing, because nothing is.
        if (title || artist) {
            elTitle.textContent = title || '';
            elArtist.textContent = artist || '';
            return;
        }

        // No live track feed: fall back to the station genre, like the wheel
        // does in the singleplayer mod when a track has no metadata.
        elTitle.textContent = '';
        var wantsGenre = !hud || hud.subtitle === 'genre';
        elArtist.textContent = (wantsGenre && station && station.genre) ? station.genre : '';
    }

    function setVisible(visible) {
        radio.classList.toggle('hidden', !visible);
    }

    // -- messages ----------------------------------------------------------

    window.addEventListener('message', function (event) {
        var data = event.data || {};

        if (data.action === 'state') {
            if (data.hud) applyHud(data.hud);
            if (data.list) buildTrack(data.list);

            index  = typeof data.index === 'number' ? data.index : index;
            muted  = !!data.muted;
            odOn   = !!data.odOn;
            label  = data.label || null;
            isOpen = !!data.open;

            render();
            renderNowPlaying(data.title, data.artist);

            if (flashTimer) { clearTimeout(flashTimer); flashTimer = null; }
            setVisible(isOpen);
            return;
        }

        if (data.action === 'flash') {
            muted = !!data.muted;
            render();
            setVisible(true);
            if (flashTimer) clearTimeout(flashTimer);
            flashTimer = setTimeout(function () {
                if (!isOpen) setVisible(false);
                flashTimer = null;
            }, 1400);
            return;
        }

        if (data.action === 'od') {
            if (typeof data.notice === 'string') { notice(data.notice); return; }
            if (data.state) renderPanel(data.state);
            setPanelOpen(!!data.open);
            return;
        }

        if (data.action === 'sound') {
            var audio = new Audio(data.file);
            audio.volume = Math.max(0, Math.min(1, data.volume));
            audio.play().catch(function () { /* autoplay gate, ignore */ });
            return;
        }
    });

    window.addEventListener('resize', function () {
        root.style.setProperty('--s', scale());
        render();
    });


    // -- On Demand panel ---------------------------------------------------

    // The only part of this page that ever talks back to the client. The wheel
    // itself stays a one-way HUD: it takes no focus and posts nothing.
    var RESOURCE = 'vi_radio';
    var odState  = null;
    var noticeTimer = null;

    function post(name, data, done) {
        fetch('https://' + RESOURCE + '/' + name, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {})
        }).then(function (res) {
            return res.json().catch(function () { return null; });
        }).then(function (body) {
            if (done) done(body);
        }).catch(function () { /* not running in game */ });
    }

    function notice(message, ok) {
        odNotice.textContent = message || '';
        odNotice.classList.toggle('ok', !!ok);
        if (noticeTimer) clearTimeout(noticeTimer);
        if (message) {
            noticeTimer = setTimeout(function () {
                odNotice.textContent = '';
                noticeTimer = null;
            }, 5000);
        }
    }

    function duration(seconds) {
        if (!seconds || seconds <= 0) return '';
        var total = Math.round(seconds);
        var mins  = Math.floor(total / 60);
        var secs  = total % 60;
        return mins + ':' + (secs < 10 ? '0' : '') + secs;
    }

    function renderQueue(state) {
        var queue = state.queue || [];
        odQueue.innerHTML = '';
        odQueueNum.textContent = queue.length + ' / ' + state.limit;

        if (!queue.length) {
            var empty = document.createElement('li');
            empty.className = 'empty';
            empty.textContent = 'Nothing queued. Paste a link to start one.';
            odQueue.appendChild(empty);
            return;
        }

        queue.forEach(function (entry, i) {
            var row = document.createElement('li');
            if (i + 1 === state.index) row.classList.add('playing');

            var pos = document.createElement('span');
            pos.className = 'pos';
            pos.textContent = (i + 1 === state.index) ? '\u25B6' : String(i + 1);

            var name = document.createElement('span');
            name.className = 'name';
            name.textContent = entry.title || 'Track';

            var by = document.createElement('span');
            by.className = 'by';
            by.textContent = [entry.artist, duration(entry.duration)]
                .filter(Boolean).join('  \u00B7  ');

            var remove = document.createElement('button');
            remove.type = 'button';
            remove.textContent = 'Remove';
            remove.addEventListener('click', function () {
                post('odRemove', { index: i + 1 });
            });

            row.appendChild(pos);
            row.appendChild(name);
            row.appendChild(by);
            row.appendChild(remove);
            odQueue.appendChild(row);
        });
    }

    function renderPanel(state) {
        odState = state;

        var playing = !!state.playing;

        odSwitch.setAttribute('aria-checked', state.engaged ? 'true' : 'false');
        odSwitchTxt.textContent = state.engaged ? 'On' : 'Off';

        odNowTitle.textContent  = playing ? (state.title || 'Track') : 'Nothing queued';
        odNowArtist.textContent = playing
            ? [state.artist, state.paused ? 'Paused' : null].filter(Boolean).join('  \u00B7  ')
            : '';

        Array.prototype.forEach.call(odTransport.children, function (button) {
            button.disabled = !playing;
            if (button.dataset.act === 'pause') {
                button.textContent = state.paused ? 'Resume' : 'Pause';
            }
        });

        renderQueue(state);

        var volume = typeof state.volume === 'number' ? state.volume : 0;
        odVolume.max = state.maxVolume;
        odVolume.value = volume;
        odVolumeVal.textContent = volume + '%';
        odMute.checked = !!state.muted;
    }

    function setPanelOpen(open) {
        od.classList.toggle('hidden', !open);
        if (open) {
            odUrl.value = '';
            notice('');
            setTimeout(function () { odUrl.focus(); }, 30);
        } else if (noticeTimer) {
            clearTimeout(noticeTimer);
            noticeTimer = null;
        }
    }

    function submitLink(playNow) {
        var url = odUrl.value.trim();
        if (!url) { notice('Paste a link first'); return; }

        post('odAdd', { url: url, playNow: playNow }, function (body) {
            if (body && body.ok === false) {
                notice(body.error || 'That link was rejected');
                return;
            }
            odUrl.value = '';
            notice(playNow ? 'Playing' : 'Added to the queue', true);
        });
    }

    odForm.addEventListener('submit', function (event) {
        event.preventDefault();
        submitLink(true);
    });

    odQueueBtn.addEventListener('click', function () { submitLink(false); });
    odClose.addEventListener('click', function () { post('odClose'); });
    odSwitch.addEventListener('click', function () { post('odDisengage'); });

    odTransport.addEventListener('click', function (event) {
        var act = event.target.dataset && event.target.dataset.act;
        if (!act) return;
        if (act === 'next')  post('odSkip', { dir: 1 });
        if (act === 'prev')  post('odSkip', { dir: -1 });
        if (act === 'pause') post('odPause');
        if (act === 'stop')  post('odStop');
    });

    odVolume.addEventListener('input', function () {
        odVolumeVal.textContent = odVolume.value + '%';
    });
    odVolume.addEventListener('change', function () {
        post('odVolume', { volume: Number(odVolume.value) });
    });

    odMute.addEventListener('change', function () {
        post('odMute', { muted: odMute.checked });
    });

    document.addEventListener('keydown', function (event) {
        if (od.classList.contains('hidden')) return;
        if (event.key === 'Escape') {
            event.preventDefault();
            post('odClose');
        }
    });

    root.style.setProperty('--s', scale());
}());
