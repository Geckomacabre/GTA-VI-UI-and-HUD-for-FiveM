function GetParentResourceName() {
    return window.location.hostname.replace('cfx-nui-', '');
}

function post(name, data) {
    return fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    }).catch(() => {});
}

const app = document.getElementById('app');
// Map is not a panel here any more -- the Map footer icon hands off to the
// real native pause map instead (client/main.lua's openNativeFrontend,
// FE_MENU_VERSION_MP_PAUSE) rather than any NUI page. See client/main.lua's
// top header comment for why a self-drawn map was torn out in favour of it.
const panels = {
    dashboard: document.getElementById('dashboard'),
    players: document.getElementById('players'),
};

// ---------------------------------------------------------------- Theme
//
// Gender-matched accent, same two colours as vice_hud's own waypoint marker
// and nav-turn tile (client/main.lua's Config.Accent, mirroring vice_hud's
// NAV_ACCENT_HEX) -- pushed fresh on every 'open' since currentAccent's own
// resolution can only change between opens (a character switch closes and
// reopens the whole session), not while this menu is already up.
let currentAccent = '#47aba7'; // teal -- same fallback client/main.lua uses before qbx_core's PlayerData is ready

function applyAccent(accent) {
    if (!accent?.accent) return;
    currentAccent = accent.accent;
    const root = document.documentElement.style;
    root.setProperty('--accent', accent.accent);
    root.setProperty('--accent-ink', accent.ink || '#0b1a19');

    // CSS custom properties can't be split into rgba() channels without
    // color-mix(), which isn't reliably available in FiveM's bundled CEF --
    // precomputed here instead, once per accent change rather than per frame.
    const hex = accent.accent.replace('#', '');
    const r = parseInt(hex.slice(0, 2), 16);
    const g = parseInt(hex.slice(2, 4), 16);
    const b = parseInt(hex.slice(4, 6), 16);
    root.setProperty('--accent-soft', `rgba(${r}, ${g}, ${b}, 0.12)`);
}

function showPanel(name) {
    for (const [key, el] of Object.entries(panels)) {
        el.classList.toggle('hidden', key !== name);
    }
    app.dataset.panel = name;
    resetFocus();
}

function renderPlayers(players) {
    const body = document.getElementById('players-body');
    body.innerHTML = '';
    for (const p of players || []) {
        const tr = document.createElement('tr');
        tr.innerHTML = `<td>${p.id}</td><td>${escapeHtml(p.name)}</td>`;
        body.appendChild(tr);
    }
}

function escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str ?? '';
    return div.innerHTML;
}

// ---------------------------------------------------------------- Dashboard
//
// The home panel: a persistent shell (sidebar + navbar + footer) with a
// swappable content area (home cards / player-info / report) -- dashView
// tracks which of those three is showing, independent of which top-level
// `panel` (dashboard/players) is active.

let dashView = 'home';
const dashViews = {
    home: document.getElementById('dash-view-home'),
    playerinfo: document.getElementById('dash-view-playerinfo'),
    report: document.getElementById('dash-view-report'),
};

function showDashView(name) {
    dashView = name;
    for (const [key, el] of Object.entries(dashViews)) {
        el.classList.toggle('hidden', key !== name);
    }
    resetFocus();
}

document.querySelectorAll('.dash-card[data-view]').forEach(card => {
    card.addEventListener('click', () => showDashView(card.dataset.view));
});
document.querySelectorAll('.dash-back').forEach(btn => {
    btn.addEventListener('click', () => showDashView(btn.dataset.back));
});

// Footer icons -- Players is the one panel switch left (Map now hands off
// natively, see client/main.lua); the rest are one-shot actions with
// nothing local to show.
document.querySelector('[data-action="resume"]').addEventListener('click', () => post('resume'));
// Settings/Keybinds/Map all hand off to a real native frontend screen
// instead (client/main.lua's openNativeFrontend) -- no local panel for any
// of them.
document.querySelector('[data-action="settings"]').addEventListener('click', () => post('openSettings'));
document.querySelector('[data-action="keybinds"]').addEventListener('click', () => post('openKeybinds'));
document.querySelector('[data-action="map"]').addEventListener('click', () => post('openMap'));

// Sidebar "Players" stat doubles as a button into the existing Players panel.
document.getElementById('stat-players').addEventListener('click', () => {
    showPanel('players');
    post('setPanel', { panel: 'players' });
});

// ---- Exit confirmation ----
const exitModal = document.getElementById('exit-modal');
document.getElementById('footer-exit').addEventListener('click', () => exitModal.classList.remove('hidden'));
document.getElementById('exit-no').addEventListener('click', () => exitModal.classList.add('hidden'));
document.getElementById('exit-yes').addEventListener('click', () => post('exit'));

// ---- OOC chat ----
//
// This box is a convenience front-end for the real /ooc command qbx_core's
// own server/commands.lua already runs (proximity broadcast, admin relay,
// logging) -- client/main.lua's 'ooc' NUI callback just calls that command
// with this text. There is no feed of OTHER players' OOC messages here (that
// command's own delivery goes through the real chat resource, not this
// panel) -- sending a message just echoes your own line into this log so
// there's visible confirmation it was sent.
const oocLog = document.getElementById('ooc-log');
const oocInput = document.getElementById('ooc-input');
function sendOoc() {
    const text = oocInput.value.trim();
    if (!text) return;
    post('ooc', { text });
    const line = document.createElement('div');
    line.className = 'ooc-msg';
    line.innerHTML = `<b>You:</b> ${escapeHtml(text)}`;
    oocLog.prepend(line);
    oocInput.value = '';
}
document.getElementById('ooc-send').addEventListener('click', sendOoc);
oocInput.addEventListener('keydown', e => {
    e.stopPropagation(); // don't let Enter/Escape also drive dashboard nav while typing
    if (e.key === 'Enter') sendOoc();
});

// ---- Report form ----
const reportSent = document.getElementById('report-sent');
document.getElementById('report-submit').addEventListener('click', () => {
    const category = document.getElementById('report-category').value;
    const subject = document.getElementById('report-subject').value.trim();
    const text = document.getElementById('report-text').value.trim();
    if (!subject || !text) return;
    post('report', { category, subject, text });
    document.getElementById('report-subject').value = '';
    document.getElementById('report-text').value = '';
    reportSent.classList.remove('hidden');
    setTimeout(() => { reportSent.classList.add('hidden'); showDashView('home'); }, 1500);
});
['report-subject', 'report-text'].forEach(id => {
    document.getElementById(id).addEventListener('keydown', e => e.stopPropagation());
});

// ---- Sidebar stats / player-info / patch notes rendering ----

function renderStats(stats) {
    if (!stats) return;
    document.getElementById('stat-ping').textContent = stats.ping ?? '--';
    document.getElementById('stat-cash').textContent = `$${(stats.cash ?? 0).toLocaleString()}`;
    document.getElementById('stat-bank').textContent = `$${(stats.bank ?? 0).toLocaleString()}`;
    document.getElementById('stat-playercount').textContent = stats.playerCount ?? '--';

    const fullName = [stats.firstName, stats.lastName].filter(Boolean).join(' ');
    document.getElementById('dash-name').textContent = fullName || ' ';
    document.getElementById('dash-job').textContent = stats.job || ' ';

    document.getElementById('pi-firstname').textContent = stats.firstName || '--';
    document.getElementById('pi-lastname').textContent = stats.lastName || '--';
    document.getElementById('pi-job').textContent = stats.job || '--';
    document.getElementById('pi-grade').textContent = stats.jobGrade || '--';
    document.getElementById('pi-bar-hunger').style.width = `${stats.hunger ?? 100}%`;
    document.getElementById('pi-bar-thirst').style.width = `${stats.thirst ?? 100}%`;
}

function renderPatchNotes(patchNotes) {
    if (!patchNotes) return;
    document.getElementById('patchnote-date').textContent = patchNotes.date || '';
    const list = document.getElementById('patchnote-list');
    list.innerHTML = '';
    for (const update of patchNotes.updates || []) {
        const li = document.createElement('li');
        li.textContent = update;
        list.appendChild(li);
    }
}

// url is a full data: URI (MugShotBase64's own GetMugShotBase64 export
// already returns canvas.toDataURL() output, see client/main.lua's
// requestMugshot) -- works directly as a CSS background-image url() same as
// the old nui://game/<txd>/<txd> src would have.
function setMugshot(url) {
    document.getElementById('dash-mugshot').style.backgroundImage = `url("${url}")`;
    document.getElementById('playerinfo-mugshot').style.backgroundImage = `url("${url}")`;
}

// ---- Navbar clock/date + session playtime ----

let sessionStart = null; // set on 'open' -- Date.now() at menu open time, not persisted across a resource restart
function tickClock() {
    const now = new Date();
    document.getElementById('dash-time').textContent = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    document.getElementById('dash-date').textContent = now.toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric' });

    if (sessionStart != null) {
        const mins = Math.floor((Date.now() - sessionStart) / 60000);
        document.getElementById('dash-playtime').textContent = `${String(Math.floor(mins / 60)).padStart(2, '0')}H : ${String(mins % 60).padStart(2, '0')}M`;
    }
}
setInterval(tickClock, 1000);
tickClock();

// ---------------------------------------------------------------- Controller / keyboard navigation
//
// SetNuiFocus(true, true) (see client/main.lua) only ever grants keyboard +
// mouse to a NUI page -- FiveM does not route controller input through the
// game's own native control system into NUI at all, with or without focus.
// The standard HTML5 Gamepad API is what actually sees stick/button state
// here, so it's polled directly every animation frame rather than watched
// via a native. Without this, a controller player gets a dead end: the game
// itself is locked out (DisableControlAction while the menu is open, see
// client/main.lua), and the NUI never listens for a controller at all --
// there would be no way to do anything.

function goBack() {
    if (!exitModal.classList.contains('hidden')) {
        exitModal.classList.add('hidden');
        return;
    }
    // A player-info/report sub-view backs out to the dashboard's own home
    // view first -- ESC shouldn't jump straight past an open sub-view all
    // the way to closing the whole menu.
    if (app.dataset.panel === 'dashboard' && dashView !== 'home') {
        showDashView('home');
        return;
    }
    if (app.dataset.panel && app.dataset.panel !== 'dashboard') {
        showPanel('dashboard');
        post('setPanel', { panel: 'dashboard' });
    } else {
        post('resume');
    }
}

// The panels/views with a real list to move a selection through -- Players
// is a plain read-only table, nothing to focus there.
function focusableRows() {
    if (app.dataset.panel === 'dashboard') {
        if (dashView === 'home') {
            return Array.from(document.querySelectorAll('#dash-view-home .dash-card[data-view], #stat-players, #dash-footer .dash-footer-btn'));
        }
        return Array.from(document.querySelectorAll(`#dash-view-${dashView} .dash-back`));
    }
    return [];
}

let focusIndex = -1;

function applyFocusHighlight(scroll = true) {
    const rows = focusableRows();
    rows.forEach((row, i) => row.classList.toggle('kb-focus', i === focusIndex));
    const row = rows[focusIndex];
    if (row && scroll) row.scrollIntoView({ block: 'nearest' });
}

// Called on every panel/view switch -- a stale focusIndex pointing past the
// end of a freshly shown (and possibly shorter) list would otherwise
// silently do nothing on the next confirm press.
function resetFocus() {
    focusIndex = focusableRows().length ? 0 : -1;
    applyFocusHighlight();
}

function moveFocus(delta) {
    const rows = focusableRows();
    if (!rows.length) return;
    focusIndex = ((focusIndex < 0 ? 0 : focusIndex) + delta + rows.length) % rows.length;
    applyFocusHighlight();
}

function activateFocus() {
    const rows = focusableRows();
    if (rows[focusIndex]) rows[focusIndex].click();
}

window.addEventListener('keydown', e => {
    if (e.key === 'Escape') { goBack(); return; }
    if (e.key === 'ArrowUp') { moveFocus(-1); return; }
    if (e.key === 'ArrowDown') { moveFocus(1); return; }
    if (e.key === 'Enter') { activateFocus(); return; }
});

let gamepadIndex = null;
window.addEventListener('gamepadconnected', e => { gamepadIndex = e.gamepad.index; });
window.addEventListener('gamepaddisconnected', e => {
    if (gamepadIndex === e.gamepad.index) gamepadIndex = null;
});

// Standard Gamepad API button/axis indices (the "standard" mapping every
// major browser normalizes Xbox/PlayStation/etc pads to).
const GP_BTN = { A: 0, B: 1, X: 2, Y: 3, LB: 4, RB: 5, LT: 6, RT: 7, DUP: 12, DDOWN: 13 };
const AXIS_DEADZONE = 0.5;   // left stick, treated as a digital up/down for list navigation
const REPEAT_FIRST_MS = 350; // delay before a held direction starts auto-repeating
const REPEAT_MS = 130;       // repeat interval once it starts

// One entry per logical input (not per physical button) so a D-pad press
// and the left stick both driving "up" share the same edge/repeat state --
// holding both at once shouldn't double-fire.
const gpState = {};
function gpPressed(name, isDownNow) {
    const s = gpState[name] || (gpState[name] = { down: false, nextRepeatAt: 0 });
    const now = performance.now();
    if (isDownNow && !s.down) {
        s.down = true;
        s.nextRepeatAt = now + REPEAT_FIRST_MS;
        return true; // fresh press
    }
    if (isDownNow && s.down && now >= s.nextRepeatAt) {
        s.nextRepeatAt = now + REPEAT_MS;
        return true; // repeat while held
    }
    if (!isDownNow) s.down = false;
    return false;
}

function pollGamepad() {
    requestAnimationFrame(pollGamepad);
    if (gamepadIndex === null || !app.classList.contains('visible')) return;
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    const gp = pads[gamepadIndex];
    if (!gp) return;

    // Left stick doubles as D-pad-style list navigation on every panel.
    const navAxisY = gp.axes[1] || 0;
    const navUp = !!gp.buttons[GP_BTN.DUP]?.pressed || navAxisY < -AXIS_DEADZONE;
    const navDown = !!gp.buttons[GP_BTN.DDOWN]?.pressed || navAxisY > AXIS_DEADZONE;
    if (gpPressed('navUp', navUp)) moveFocus(-1);
    if (gpPressed('navDown', navDown)) moveFocus(1);
    if (gpPressed('a', !!gp.buttons[GP_BTN.A]?.pressed)) activateFocus();
    if (gpPressed('b', !!gp.buttons[GP_BTN.B]?.pressed)) goBack();
}
requestAnimationFrame(pollGamepad);

window.addEventListener('message', event => {
    const data = event.data;
    switch (data.type) {
        case 'open':
            app.classList.add('visible');
            applyAccent(data.accent);
            exitModal.classList.add('hidden'); // a leftover confirm from a prior open must never carry into a new one
            showDashView('home');
            showPanel(data.panel || 'dashboard');
            renderPlayers(data.players);
            renderStats(data.stats);
            renderPatchNotes(data.patchNotes);
            sessionStart = Date.now();
            oocLog.innerHTML = ''; // this menu's own sent-message echo only, not a persistent chat log -- see sendOoc's comment
            tickClock();
            break;
        case 'close':
            app.classList.remove('visible');
            sessionStart = null;
            break;
        case 'players':
            renderPlayers(data.players);
            break;
        case 'stats':
            renderStats(data.stats);
            break;
        case 'mugshot':
            setMugshot(data.url);
            break;
    }
});
