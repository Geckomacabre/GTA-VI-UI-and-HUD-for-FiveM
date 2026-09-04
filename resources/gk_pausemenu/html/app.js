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
const panels = {
    quickmenu: document.getElementById('quickmenu'),
    map: document.getElementById('map'),
    players: document.getElementById('players'),
};

let allBlips = []; // last 'blips'/'open' payload (client/blips.lua's GK.ScanBlips()), so the search box can re-filter without asking Lua again
let blipVisible = {}; // blipId(b) -> bool, mirrors each row's own checkbox for the on-map pins

// ---------------------------------------------------------------- Blip sprite/colour data
//
// Every currently active native blip server-wide (client/blips.lua's
// GK.ScanBlips()) only ever carries a numeric sprite id and HUD colour
// index -- there is no native to read a blip's own display name back (see
// that file's header comment), so this is what turns "sprite 60, colour 29"
// into an actual icon and colour. Fetched once, from files this resource
// ships (html/data/*.json, built from docs.fivem.net's own blips/
// hud-colors reference pages) -- not hardcoded inline since there are 966
// sprites and 212 colours between them.
let SPRITE_DATA = {}; // sprite id -> [filename, extension]
let HUD_COLORS = {};  // colour id -> hex
// Both fetches are kicked off immediately at load, but the Map tab can
// already be open (and rendered once with the "Sprite 60"-style fallback
// labels/currentAccent-coloured badges) by the time either resolves -- each
// re-renders whatever's currently showing so labels/colours correct
// themselves in place rather than staying wrong until the next open.
fetch('data/blip_sprites.json').then(r => r.json()).then(d => {
    SPRITE_DATA = d;
    if (allBlips.length) renderLocations(allBlips);
});
fetch('data/hud_colors.json').then(r => r.json()).then(d => {
    HUD_COLORS = d;
    if (allBlips.length) renderLocations(allBlips);
});

// The 10 icons actually bundled locally (html/images/blips/) -- confirmed
// by eye as plain single-colour silhouettes before shipping them, see
// shared/config.lua's Points-of-interest comment for the history of why
// that hand-verification step matters. Everything else hotlinks the same
// docs.fivem.net URL these were originally fetched from, since bundling all
// 966 sprites unseen was exactly the "too many turned out to be detailed
// multi-colour art" mistake made (and reverted) twice before -- see
// renderMapBlips' <img>.onerror for the fallback when that hotlink fails
// (network blocked, sprite renamed, whatever).
const LOCAL_ICON_SPRITES = new Set([487, 380, 61, 60, 356, 477, 198, 318, 402, 357]);

function iconUrl(sprite) {
    const entry = SPRITE_DATA[sprite];
    if (!entry) return null;
    const [file, ext] = entry;
    return LOCAL_ICON_SPRITES.has(sprite) ? `images/blips/${file}.${ext}` : `https://docs.fivem.net/blips/${file}.${ext}`;
}

// "radar_police_station" -> "Police Station". Sprite names are already
// close to a human label as-is; this is just cosmetic cleanup, not a
// separate translation table to maintain.
function spriteLabel(sprite) {
    const entry = SPRITE_DATA[sprite];
    if (!entry) return `Sprite ${sprite}`;
    return entry[0].replace(/^radar_/, '').replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
}

function blipColorHex(blip) {
    return HUD_COLORS[blip.colour] || currentAccent;
}

// Coordinates, not a persistent id, are what's stable here -- a fresh
// GK.ScanBlips() on every Map-tab open (see client/main.lua) has no
// concept of "the same blip as last time" beyond it still existing at the
// same spot, so visibility toggles (blipVisible) key off this instead of
// an array index that would silently point at a different blip after any
// resource's blips changed between scans.
function blipId(b) {
    return `${b.sprite}:${b.coords.x.toFixed(1)}:${b.coords.y.toFixed(1)}`;
}

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

// ---------------------------------------------------------------- Map

let mapConfig = null;
let mapZoom = 1;
let lastPlayerPos = null;
// Image-pixel coords the view is centered on. null = follow the player
// (the normal/default state); set by a drag or a blip click, both of which
// detach the view from the player until "Recenter" (or the "You" row) is
// used.
let manualCenterImg = null;
const mapViewport = document.getElementById('map-viewport');
const mapLayer = document.getElementById('map-layer');
const mapImage = document.getElementById('map-image');
const mapBlips = document.getElementById('map-blips');
const mapPlayerMarker = document.getElementById('map-player-marker');
const mapSection = document.getElementById('map');
const mapRecenterBtn = document.getElementById('map-recenter');
const mapBlipTooltip = document.getElementById('map-blip-tooltip');
let hoveredBlipDot = null; // the currently hovered/selected dot, if any -- kept so renderMap() can reposition its tooltip as the view pans/zooms

function worldToImagePixel(wx, wy) {
    const fracX = (wx - mapConfig.worldMinX) / (mapConfig.worldMaxX - mapConfig.worldMinX);
    const fracY = 1 - (wy - mapConfig.worldMinY) / (mapConfig.worldMaxY - mapConfig.worldMinY);
    return { x: fracX * mapConfig.pixelWidth, y: fracY * mapConfig.pixelHeight };
}

function mapCssScale() {
    return (mapZoom / mapConfig.metersPerPixelAtZoom1)
        / (mapConfig.pixelWidth / (mapConfig.worldMaxX - mapConfig.worldMinX));
}

// Pans/zooms the view onto a world coordinate without setting a waypoint or
// closing the menu -- the "preview" step for both a Locations-list row click
// and a map blip-dot click, so either lets you actually look at where
// something is before deciding to commit to a waypoint there.
function centerMapOn(worldX, worldY) {
    if (!mapConfig) return;
    manualCenterImg = worldToImagePixel(worldX, worldY);
    mapRecenterBtn.classList.remove('hidden');
    renderMap();
}

// Clicking a blip icon on the map should make it obvious which Locations
// row it is -- moves keyboard/gamepad focus onto that row (matched by
// blipId, the same key blipVisible/renderMapBlips use, set as data-blip-id
// on both the row and the dot when each is created) and highlights it
// exactly like arrowing onto it manually would (see applyFocusHighlight).
// No-ops quietly if the row isn't currently in the list -- filtered out by
// the search box, most likely -- rather than erroring.
//
// `scroll` defaults to true (a click/keyboard/gamepad selection SHOULD jump
// the list to show it) but a plain mouse HOVER passes false -- moving the
// mouse across several blips shouldn't yank the list's scroll position
// around each time, only an actual selection should.
function selectLocationRow(blip, scroll = true) {
    const rows = focusableRows();
    const index = rows.findIndex(r => r.dataset.blipId === blipId(blip));
    if (index === -1) return;
    focusIndex = index;
    applyFocusHighlight(scroll);
}

// Floating label above whichever blip is hovered, clicked, or keyboard/
// gamepad-focused (see applyFocusHighlight, which calls this too, so all
// three input methods show the same thing) -- separate from the dot's own
// `title` attribute (a native OS tooltip, slow to appear and easy to miss)
// because the ask here was for something immediately visible.
function showBlipTooltip(dot, text) {
    hoveredBlipDot = dot;
    mapBlipTooltip.textContent = text;
    mapBlipTooltip.classList.remove('hidden');
    positionBlipTooltip();
}

function hideBlipTooltip() {
    hoveredBlipDot = null;
    mapBlipTooltip.classList.add('hidden');
}

// Reads the dot's actual on-screen position via getBoundingClientRect
// rather than recomputing world->pixel->screen by hand -- the dot is
// already positioned correctly by renderMap's own transform/counter-scale
// logic, this just needs to sit above wherever that ends up. Called again
// on every renderMap() (pan/zoom/player movement) while a dot is hovered so
// the tooltip tracks it instead of drifting off as the view moves.
function positionBlipTooltip() {
    if (!hoveredBlipDot || !hoveredBlipDot.isConnected) {
        hideBlipTooltip();
        return;
    }
    const dotRect = hoveredBlipDot.getBoundingClientRect();
    const mapRect = mapSection.getBoundingClientRect();
    mapBlipTooltip.style.left = `${dotRect.left - mapRect.left + dotRect.width / 2}px`;
    mapBlipTooltip.style.top = `${dotRect.top - mapRect.top}px`;
}

function setupMap(config) {
    mapConfig = config;
    mapImage.src = config.image;
    mapImage.onerror = () => mapSection.classList.add('no-image');
    mapImage.onload = () => mapSection.classList.remove('no-image');
    manualCenterImg = null; // start each fresh open following the player, not wherever a prior session's pan/click left off
    mapRecenterBtn.classList.add('hidden');
    renderMapBlips();
}

function renderMapBlips() {
    if (!mapConfig) return;
    mapBlips.innerHTML = ''; // destroys any currently-hovered dot -- its tooltip would otherwise point at a detached element
    hideBlipTooltip();
    for (const blip of allBlips) {
        if (blipVisible[blipId(blip)] === false) continue;
        const p = worldToImagePixel(blip.coords.x, blip.coords.y);
        const color = blipColorHex(blip);
        const url = iconUrl(blip.sprite);
        const label = spriteLabel(blip.sprite) + (blip.zone ? ` (${blip.zone})` : '');

        const dot = document.createElement('div');
        if (url) {
            // The real native blip icon on a coloured circle badge, NOT a
            // CSS mask-image tint -- that was tried first and made every
            // blip vanish outright: FiveM's embedded CEF build is
            // known-unreliable with mask-image, and a mask that fails to
            // apply typically renders as fully transparent rather than
            // falling back to unmasked. A plain <img> is the same tag
            // #map-image already relies on and works, so it can't have that
            // failure mode. Deliberately NOT inverted/tinted to white the
            // way the original hand-picked 10-icon set was -- across the
            // full ~966-sprite range most icons are detailed multi-colour
            // art (business logos, letter markers), and inverting those
            // would be exactly the "flattened real detail" mistake that
            // sank two earlier full-pipeline attempts (see shared/
            // config.lua's Points-of-interest comment). Shown at native
            // colour instead; the circle's own background still carries the
            // blip's real HUD colour as a border-style accent.
            dot.className = 'map-blip-icon';
            dot.style.borderColor = color;
            const img = document.createElement('img');
            img.src = url;
            img.alt = '';
            // Only the local 10 are hand-confirmed plain single-colour
            // silhouettes -- inverting those to white is what makes them
            // read clearly on a dark badge. Everything hotlinked is shown
            // at its own native colour instead (see this function's own
            // comment above for why forcing that for the full sprite range
            // would repeat a mistake already made twice).
            if (LOCAL_ICON_SPRITES.has(blip.sprite)) img.classList.add('mono');
            // A hotlinked (non-local) icon can fail -- network blocked
            // server-side, sprite renamed upstream, whatever. Falls back to
            // the plain coloured dot rather than an empty/broken circle.
            img.addEventListener('error', () => {
                dot.className = 'map-blip-dot';
                dot.style.backgroundColor = color;
                dot.style.borderColor = '';
                img.remove();
            });
            dot.appendChild(img);
        } else {
            dot.className = 'map-blip-dot';
            dot.style.backgroundColor = color;
        }
        dot.style.left = `${p.x}px`;
        dot.style.top = `${p.y}px`;
        dot.title = `${label} -- click to preview, double-click to set a waypoint`;
        dot.dataset.blipId = blipId(blip);
        dot.dataset.label = label; // read back by applyFocusHighlight when focus moves here via keyboard/gamepad, not a mouse hover
        dot.addEventListener('mouseenter', () => {
            showBlipTooltip(dot, label);
            selectLocationRow(blip, false); // highlight only -- don't scroll the list just because the mouse passed over a blip
        });
        dot.addEventListener('mouseleave', () => {
            if (hoveredBlipDot === dot) hideBlipTooltip();
        });
        dot.addEventListener('click', () => {
            if (mapDragMoved) return; // this click is the tail end of a drag, not a real click
            centerMapOn(blip.coords.x, blip.coords.y);
            selectLocationRow(blip);
        });
        dot.addEventListener('dblclick', () => {
            post('setWaypoint', { x: blip.coords.x, y: blip.coords.y });
        });
        mapBlips.appendChild(dot);
    }
    renderMap(); // re-applies the current counter-scale/transform to the freshly (re)created elements
}

// Renders the whole map view from current state (lastPlayerPos, mapZoom,
// manualCenterImg) -- the single place that touches mapLayer's transform
// and the player marker's position, called after any of those change.
function renderMap() {
    if (!mapConfig) return;

    const center = manualCenterImg || (lastPlayerPos && worldToImagePixel(lastPlayerPos.x, lastPlayerPos.y));
    if (!center) return; // nothing to center on yet (no player position received, no manual pan/click)

    const cssScale = mapCssScale();
    const viewportCenterX = mapViewport.clientWidth / 2;
    const viewportCenterY = mapViewport.clientHeight / 2;
    const translateX = viewportCenterX - center.x * cssScale;
    const translateY = viewportCenterY - center.y * cssScale;
    mapLayer.style.transform = `translate(${translateX}px, ${translateY}px) scale(${cssScale})`;

    // Pins live inside #map-layer (so their left/top can stay in plain
    // image-pixel coords), which means the layer's own scale would shrink
    // them right along with a zoomed-out view. Counter-scale each one so it
    // renders at a constant on-screen size regardless of zoom, like a
    // normal map pin. translate(-50%,-50%) centers it on its left/top point.
    const counterScale = 1 / cssScale;
    for (const dot of mapBlips.children) {
        dot.style.transform = `translate(-50%, -50%) scale(${counterScale})`;
    }
    positionBlipTooltip(); // keeps the tooltip tracking its dot through pan/zoom/player movement -- no-ops if nothing is hovered

    if (lastPlayerPos) {
        const p = worldToImagePixel(lastPlayerPos.x, lastPlayerPos.y);
        // Screen position of the player marker relative to the current
        // view center -- equals dead center only while manualCenterImg is
        // null (i.e. still following the player).
        const screenX = viewportCenterX + (p.x - center.x) * cssScale;
        const screenY = viewportCenterY + (p.y - center.y) * cssScale;
        mapPlayerMarker.style.left = `${screenX}px`;
        mapPlayerMarker.style.top = `${screenY}px`;
        // Heading is degrees counter-clockwise from north (GET_ENTITY_HEADING);
        // screen rotation is clockwise from the marker's north-pointing rest
        // pose, and north is "up" (image row 0), so negate it directly.
        mapPlayerMarker.style.transform = `translate(-50%, -50%) rotate(${-lastPlayerPos.heading}deg)`;
    }
}

function setMapZoom(zoom) {
    if (!mapConfig) return;
    mapZoom = Math.max(mapConfig.minZoom, Math.min(mapConfig.maxZoom, zoom));
    renderMap();
}

document.getElementById('map-zoom-in').addEventListener('click', () => setMapZoom(mapZoom * 1.35));
document.getElementById('map-zoom-out').addEventListener('click', () => setMapZoom(mapZoom / 1.35));
mapViewport.addEventListener('wheel', e => {
    e.preventDefault();
    setMapZoom(mapZoom * (e.deltaY < 0 ? 1.15 : 1 / 1.15));
}, { passive: false });

function recenterOnPlayer() {
    manualCenterImg = null;
    mapRecenterBtn.classList.add('hidden');
    renderMap();
}
mapRecenterBtn.addEventListener('click', recenterOnPlayer);
document.getElementById('you-row').addEventListener('click', recenterOnPlayer);

// ---- Free drag-panning ----
// mapDragMoved distinguishes an actual drag from a plain click (both start
// and end with a pointerdown/up on the same element) -- checked by the blip
// dot click handler above so a drag-that-ends-on-a-dot doesn't also
// re-center onto that dot.
let mapDragging = false;
let mapDragMoved = false;
let mapDragStartScreen = null;
let mapDragStartCenterImg = null;

mapViewport.addEventListener('pointerdown', e => {
    if (!mapConfig) return;
    mapDragging = true;
    mapDragMoved = false;
    mapDragStartScreen = { x: e.clientX, y: e.clientY };
    // Snapshot whatever the view is currently centered on (player or a
    // prior manual center) as the drag's starting point, so the first
    // pixel of movement pans smoothly from exactly where the view already
    // was -- no jump.
    mapDragStartCenterImg = manualCenterImg
        || (lastPlayerPos && worldToImagePixel(lastPlayerPos.x, lastPlayerPos.y))
        || { x: mapConfig.pixelWidth / 2, y: mapConfig.pixelHeight / 2 };
    mapViewport.setPointerCapture(e.pointerId);
});

mapViewport.addEventListener('pointermove', e => {
    if (!mapDragging) return;
    const dx = e.clientX - mapDragStartScreen.x;
    const dy = e.clientY - mapDragStartScreen.y;
    if (!mapDragMoved && (Math.abs(dx) > 4 || Math.abs(dy) > 4)) {
        mapDragMoved = true;
        mapRecenterBtn.classList.remove('hidden');
    }
    if (!mapDragMoved) return;

    const cssScale = mapCssScale();
    // Dragging the map right should reveal territory to the left, i.e. the
    // view center moves opposite to the pointer's movement.
    manualCenterImg = {
        x: mapDragStartCenterImg.x - dx / cssScale,
        y: mapDragStartCenterImg.y - dy / cssScale,
    };
    renderMap();
});

function endMapDrag(e) {
    if (!mapDragging) return;
    mapDragging = false;
    if (e && mapViewport.hasPointerCapture?.(e.pointerId)) {
        mapViewport.releasePointerCapture(e.pointerId);
    }
}
mapViewport.addEventListener('pointerup', endMapDrag);
mapViewport.addEventListener('pointercancel', endMapDrag);

function showPanel(name) {
    for (const [key, el] of Object.entries(panels)) {
        el.classList.toggle('hidden', key !== name);
    }
    app.dataset.panel = name;

    document.querySelectorAll('.qm-row[data-panel]').forEach(row => {
        row.classList.toggle('active', row.dataset.panel === name);
    });

    resetFocus();
}

// Reflects every row checkbox's current state onto its sprite-group
// header's bulk checkbox: checked if all shown, unchecked if none,
// indeterminate (a dash, not a check) if mixed -- so the header always
// honestly shows whether "toggle group" would turn everything on or off
// next.
function syncGroupHeaderCheckbox(list, sprite) {
    const headerCb = list.querySelector(`.cat-header input[data-sprite="${sprite}"]`);
    if (!headerCb) return;
    const rowCbs = [...list.querySelectorAll(`.loc-row[data-sprite="${sprite}"] input[type="checkbox"]`)];
    const checkedCount = rowCbs.filter(cb => cb.checked).length;
    headerCb.checked = checkedCount === rowCbs.length;
    headerCb.indeterminate = checkedCount > 0 && checkedCount < rowCbs.length;
}

// Every blip instance of the same sprite shares a group (header + bulk
// checkbox) -- there is no other grouping concept left once locations come
// from a live scan instead of Config.Categories (see client/blips.lua's
// header comment). Individual rows within a group are distinguished by
// GET_NAME_OF_ZONE's district name (e.g. "Mission Row"), with a "#2"-style
// suffix appended only when two blips of the same sprite land in the same
// zone -- the closest thing to a real per-instance name that's actually
// readable back from a native blip (see client/blips.lua for why a blip's
// own custom text can't be read at all).
function labelRows(blips) {
    const totals = {};
    for (const b of blips) {
        const zone = b.zone || 'Unknown Area';
        totals[zone] = (totals[zone] || 0) + 1;
    }
    const seen = {};
    return blips.map(b => {
        const zone = b.zone || 'Unknown Area';
        seen[zone] = (seen[zone] || 0) + 1;
        return { blip: b, label: totals[zone] > 1 ? `${zone} #${seen[zone]}` : zone };
    });
}

function renderLocations(blips) {
    allBlips = blips || [];
    blipVisible = {}; // every checkbox below is (re)created checked, so the on-map pins must match
    const list = document.getElementById('locations-list');
    const filter = document.getElementById('location-search').value.trim().toLowerCase();
    // The "You" row lives outside this rebuilt content -- keep it, clear everything after it.
    const youRow = document.getElementById('you-row');
    list.innerHTML = '';
    list.appendChild(youRow);

    const groups = new Map(); // sprite id -> blips
    for (const b of allBlips) {
        if (!groups.has(b.sprite)) groups.set(b.sprite, []);
        groups.get(b.sprite).push(b);
    }

    const sortedSprites = [...groups.keys()].sort((a, b) => spriteLabel(a).localeCompare(spriteLabel(b)));
    for (const sprite of sortedSprites) {
        const rows = labelRows(groups.get(sprite))
            .filter(r => !filter || r.label.toLowerCase().includes(filter) || spriteLabel(sprite).toLowerCase().includes(filter))
            .sort((a, b) => a.label.localeCompare(b.label));
        if (!rows.length) continue;

        const groupColor = blipColorHex(rows[0].blip);

        const header = document.createElement('div');
        header.className = 'cat-header';

        // Label + chevron share one click target so the WHOLE header row
        // collapses the group (not just a small arrow icon) -- the bulk
        // checkbox is a separate element specifically so clicking it does
        // NOT also trigger the collapse (stopPropagation below).
        const headerLabelWrap = document.createElement('span');
        headerLabelWrap.className = 'cat-header-label';
        const chevron = document.createElement('span');
        chevron.className = 'cat-chevron';
        headerLabelWrap.appendChild(chevron);
        const headerLabel = document.createElement('span');
        headerLabel.textContent = `${spriteLabel(sprite)} (${rows.length})`;
        headerLabelWrap.appendChild(headerLabel);
        header.appendChild(headerLabelWrap);
        headerLabelWrap.addEventListener('click', () => {
            const collapsed = header.classList.toggle('collapsed');
            list.querySelectorAll(`.loc-row[data-sprite="${sprite}"]`).forEach(r => {
                r.classList.toggle('hidden', collapsed);
            });
            // A collapsed row can't stay the keyboard/gamepad focus target --
            // focusableRows() already excludes .hidden rows, so a stale
            // focusIndex pointing at one of them would silently do nothing
            // on the next confirm press.
            resetFocus();
        });

        const headerCheckbox = document.createElement('input');
        headerCheckbox.type = 'checkbox';
        headerCheckbox.checked = true;
        headerCheckbox.dataset.sprite = sprite;
        headerCheckbox.title = 'Show/hide this whole group on the map';
        headerCheckbox.addEventListener('click', e => e.stopPropagation()); // don't also collapse the group
        headerCheckbox.addEventListener('change', () => {
            list.querySelectorAll(`.loc-row[data-sprite="${sprite}"] input[type="checkbox"]`).forEach(cb => {
                cb.checked = headerCheckbox.checked;
                cb.dispatchEvent(new Event('change'));
            });
            headerCheckbox.indeterminate = false;
        });
        header.appendChild(headerCheckbox);

        list.appendChild(header);

        for (const { blip, label } of rows) {
            const row = document.createElement('div');
            row.className = 'loc-row';
            row.dataset.sprite = sprite;
            row.dataset.blipId = blipId(blip);
            row.style.borderLeftColor = groupColor;
            row.title = 'Click to preview on the map -- double-click / X to set a waypoint here';

            const swatch = document.createElement('span');
            swatch.className = 'loc-swatch';
            swatch.style.backgroundColor = groupColor;
            row.appendChild(swatch);

            const labelEl = document.createElement('span');
            labelEl.className = 'loc-label';
            labelEl.textContent = label;
            row.appendChild(labelEl);

            // None of these blips belong to this resource (see
            // client/blips.lua's header comment) -- there's no native blip
            // for it to toggle, only ever the NUI's own pin.
            const checkbox = document.createElement('input');
            checkbox.type = 'checkbox';
            checkbox.checked = true;
            checkbox.title = 'Show/hide this location on the map';
            checkbox.addEventListener('click', e => e.stopPropagation());
            checkbox.addEventListener('change', () => {
                blipVisible[blipId(blip)] = checkbox.checked;
                syncGroupHeaderCheckbox(list, sprite);
                renderMapBlips();
            });
            row.appendChild(checkbox);

            // A single click used to set a waypoint AND close the whole menu
            // outright -- there was no way to just look at where a location
            // actually is before committing to it. Click now only previews
            // (pans/zooms the map onto it, same as clicking its blip dot
            // does); double-click (or X on a controller, see
            // confirmFocusedWaypoint) is the deliberate "yes, go here" second
            // step that actually sets the waypoint and closes the menu.
            row.addEventListener('click', () => {
                centerMapOn(blip.coords.x, blip.coords.y);
            });
            row.addEventListener('dblclick', () => {
                post('setWaypoint', { x: blip.coords.x, y: blip.coords.y });
            });

            list.appendChild(row);
        }
    }

    renderMapBlips();
    resetFocus(); // rows were just rebuilt -- any prior focused element reference is stale
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

document.querySelectorAll('.qm-row').forEach(row => {
    row.addEventListener('click', () => {
        if (row.dataset.action === 'resume') {
            post('resume');
            return;
        }
        // Settings has no local panel to show -- it hands off to FiveM's
        // own real Settings screen instead (client/main.lua's
        // openNativeSettings), so there's nothing here to switch to.
        if (row.dataset.action === 'settings') {
            post('openSettings');
            return;
        }
        showPanel(row.dataset.panel);
        post('setPanel', { panel: row.dataset.panel });
    });
});

document.getElementById('location-search').addEventListener('input', () => renderLocations(allBlips));

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
    if (app.dataset.panel && app.dataset.panel !== 'quickmenu') {
        showPanel('quickmenu');
        post('setPanel', { panel: 'quickmenu' });
    } else {
        post('resume');
    }
}

// The two panels with a real list to move a selection through -- Players is
// a plain read-only table, nothing to focus there.
function focusableRows() {
    if (app.dataset.panel === 'quickmenu') {
        return Array.from(document.querySelectorAll('#quickmenu .qm-row'));
    }
    if (app.dataset.panel === 'map') {
        // :not(.hidden) -- a collapsed group's rows (see renderLocations'
        // header click handler) shouldn't be reachable by keyboard/gamepad
        // navigation any more than they're visible to the mouse.
        return Array.from(document.querySelectorAll('#locations-list .you-row, #locations-list .loc-row:not(.hidden)'));
    }
    return [];
}

let focusIndex = -1;

function applyFocusHighlight(scroll = true) {
    const rows = focusableRows();
    rows.forEach((row, i) => row.classList.toggle('kb-focus', i === focusIndex));
    const row = rows[focusIndex];
    // Keyboard/gamepad navigation and an actual click SHOULD jump the list
    // to show the selection; a plain mouse hover (selectLocationRow's own
    // `scroll = false` default there) should only highlight it in place --
    // otherwise moving the mouse across several map blips would yank the
    // list's scroll position around on every one, not just the one actually
    // picked.
    if (row && scroll) row.scrollIntoView({ block: 'nearest' });

    // Mirrors the focused Locations row on the map itself, the same way a
    // mouse hover does (see renderMapBlips' mouseenter) -- so moving focus
    // with the keyboard or a controller shows the same floating name label
    // a mouse user gets, instead of only working for one input method.
    const blipIdAttr = row?.dataset.blipId;
    const dot = blipIdAttr && document.querySelector(`.map-blip-icon[data-blip-id="${blipIdAttr}"], .map-blip-dot[data-blip-id="${blipIdAttr}"]`);
    if (dot) {
        showBlipTooltip(dot, dot.dataset.label);
    } else if (app.dataset.panel === 'map') {
        hideBlipTooltip();
    }
}

// Called on every panel switch and every locations-list rebuild (search
// filtering, category toggles) -- a stale focusIndex pointing past the end
// of a freshly rebuilt (and possibly now-shorter, filtered) list would
// otherwise silently do nothing on the next confirm press.
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

// Y on the focused Map row -- show/hide is a separate action from both
// activateFocus (A/Enter, preview-centers) and confirmFocusedWaypoint
// (X/Space, actually sets the waypoint), so each needs its own button.
function toggleFocusCheckbox() {
    const rows = focusableRows();
    const checkbox = rows[focusIndex]?.querySelector('input[type="checkbox"]');
    if (checkbox) {
        checkbox.checked = !checkbox.checked;
        checkbox.dispatchEvent(new Event('change'));
    }
}

// X on the focused Map row -- the deliberate "yes, go here" second step.
// activateFocus (A/Enter) only ever previews (see the Locations-list row's
// own click handler in renderLocations) so a controller player isn't stuck
// unable to actually set a waypoint at all; dispatching a synthetic
// dblclick reuses that same handler rather than duplicating the post() call.
function confirmFocusedWaypoint() {
    const rows = focusableRows();
    const row = rows[focusIndex];
    if (row?.classList.contains('loc-row')) {
        row.dispatchEvent(new MouseEvent('dblclick'));
    }
}

window.addEventListener('keydown', e => {
    if (e.key === 'Escape') { goBack(); return; }
    if (e.key === 'ArrowUp') { moveFocus(-1); return; }
    if (e.key === 'ArrowDown') { moveFocus(1); return; }
    if (e.key === 'Enter') { activateFocus(); return; }
    if (e.key === ' ') { confirmFocusedWaypoint(); return; }
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
const PAN_DEADZONE = 0.15;   // right stick, treated as analog for free map panning
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

    // Left stick doubles as D-pad-style list navigation on every panel --
    // matches the reference screenshots' own "circular stick = MOVE" glyph.
    const navAxisY = gp.axes[1] || 0;
    const navUp = !!gp.buttons[GP_BTN.DUP]?.pressed || navAxisY < -AXIS_DEADZONE;
    const navDown = !!gp.buttons[GP_BTN.DDOWN]?.pressed || navAxisY > AXIS_DEADZONE;
    if (gpPressed('navUp', navUp)) moveFocus(-1);
    if (gpPressed('navDown', navDown)) moveFocus(1);
    if (gpPressed('a', !!gp.buttons[GP_BTN.A]?.pressed)) activateFocus();
    if (gpPressed('b', !!gp.buttons[GP_BTN.B]?.pressed)) goBack();
    if (gpPressed('x', !!gp.buttons[GP_BTN.X]?.pressed)) confirmFocusedWaypoint();
    if (gpPressed('y', !!gp.buttons[GP_BTN.Y]?.pressed)) toggleFocusCheckbox();

    // Right stick free-pans the map, independent of the left stick's list
    // navigation above -- both work at once without fighting each other.
    if (app.dataset.panel === 'map' && mapConfig) {
        const panX = gp.axes[2] || 0;
        const panY = gp.axes[3] || 0;
        if (Math.abs(panX) > PAN_DEADZONE || Math.abs(panY) > PAN_DEADZONE) {
            const cssScale = mapCssScale();
            const speed = 16 / cssScale; // image-pixels per frame at full stick deflection
            const base = manualCenterImg
                || (lastPlayerPos && worldToImagePixel(lastPlayerPos.x, lastPlayerPos.y))
                || { x: mapConfig.pixelWidth / 2, y: mapConfig.pixelHeight / 2 };
            manualCenterImg = { x: base.x + panX * speed, y: base.y + panY * speed };
            mapRecenterBtn.classList.remove('hidden');
            renderMap();
        }
        if (gp.buttons[GP_BTN.RT]?.pressed) setMapZoom(mapZoom * 1.03);
        if (gp.buttons[GP_BTN.LT]?.pressed) setMapZoom(mapZoom / 1.03);
    }
}
requestAnimationFrame(pollGamepad);

window.addEventListener('message', event => {
    const data = event.data;
    switch (data.type) {
        case 'open':
            app.classList.add('visible');
            applyAccent(data.accent);
            showPanel(data.panel || 'quickmenu');
            if (data.mapConfig) setupMap(data.mapConfig);
            // data.blips is only populated when opening straight to the Map
            // tab (see client/main.lua's showNui) -- opening elsewhere still
            // clears any stale list from a previous session rather than
            // leaving it, since blipVisible's checkboxes wouldn't match up
            // with pins from a scan that's now long gone.
            renderLocations(data.blips || []);
            renderPlayers(data.players);
            break;
        case 'close':
            app.classList.remove('visible');
            break;
        case 'blips':
            // Pushed by client/main.lua's setPanel handler when switching TO
            // Map from elsewhere -- the 'open' payload above only scans
            // blips when Map is the panel being opened straight into.
            renderLocations(data.blips);
            break;
        case 'players':
            renderPlayers(data.players);
            break;
        case 'playerPos':
            lastPlayerPos = { x: data.x, y: data.y, heading: data.heading };
            renderMap();
            break;
    }
});
