/* The frame, the corner badge and the nav compass are NUI drawn over WHERE the
 * engine's radar is -- so they must come down with it.
 *
 *   node html/mapchrome.test.js
 *
 * Not shipped to clients -- not in fxmanifest's files{}. Hiding the map on foot
 * used to leave an empty outlined box with a logo in the corner and nothing
 * inside it. client.lua's setRadar() is now the single place that toggles the
 * radar and it reports every transition as `visible` on the map payload; this
 * pins the page's half of that contract, including the case that made it
 * fiddly: the badge has TWO owners (nav steps aside for the compass, and the
 * radar state), and neither may clobber the other.
 */
const fs = require('fs');
const { JSDOM } = require('jsdom');

const base = __dirname + '/';
let fails = 0;
function ok(cond, label, extra) {
  if (cond) { console.log('  PASS  ' + label); }
  else { console.log('  FAIL  ' + label + (extra !== undefined ? '   -> ' + JSON.stringify(extra) : '')); fails++; }
}

const dom = new JSDOM(fs.readFileSync(base + 'index.html', 'utf8'),
  { url: 'http://localhost/', runScripts: 'outside-only', pretendToBeVisual: true });
const { window } = dom;
const d = window.document;
window.fetch = () => Promise.resolve({ json: () => Promise.resolve({}) });
window.GetParentResourceName = () => 'vice_hud';
window.eval(fs.readFileSync(base + 'app.js', 'utf8'));

const msg = (data) => window.dispatchEvent(new window.MessageEvent('message', { data }));
const shown = (id) => !d.getElementById(id).classList.contains('hidden');

// Map up, frame switched on: the ordinary state, and proof the listener ran.
msg({ action: 'mapRect', left: 2, width: 20, bottom: 2, height: 20, showFrame: true, visible: true });
ok(shown('map-frame'), 'app.js listener is attached (frame shows when asked for)');
ok(shown('map-badge'), 'badge shows with the map up and no nav');

// Hide the radar (on foot).
msg({ action: 'mapRect', visible: false });
ok(!shown('map-frame'), 'hiding the map takes the frame with it');
ok(!shown('map-badge'), 'and the corner badge');

// A map payload that says nothing about visibility must not resurrect them --
// client.lua re-pushes geometry on its own schedule.
msg({ action: 'mapRect', left: 2, width: 20, bottom: 2, height: 20 });
ok(!shown('map-frame'), 'a geometry-only push does not bring the frame back');

// Radar back on: the frame returns to what the config asked for, not to "on".
msg({ action: 'mapRect', visible: true });
ok(shown('map-frame'), 'showing the map restores the frame');
ok(shown('map-badge'), 'and the badge');

// Frame configured OFF: coming back must respect that, not force it on.
msg({ action: 'mapRect', showFrame: false });
msg({ action: 'mapRect', visible: false });
msg({ action: 'mapRect', visible: true });
ok(!shown('map-frame'), 'a frame configured off stays off across a hide/show');
ok(shown('map-badge'), 'while the badge, which was on, comes back');

// The badge's other owner: nav takes the corner, so the badge steps aside.
msg({ action: 'nav', active: true, near: true, instruction: 'Turn Left',
      dir: 'left', distance: '130 ft', remaining: '0.69 mi' });
ok(!shown('map-badge'), 'nav active hides the badge (it wants that corner)');

// Now hide the map while nav owns the corner, then clear nav. The badge must
// stay down: the map is still hidden. This is the clobber the two owners
// would otherwise cause.
msg({ action: 'mapRect', visible: false });
msg({ action: 'nav', active: false });
ok(!shown('map-badge'), 'clearing nav does NOT resurrect the badge over a hidden map');
// The compass is a .slot, so it FADES (SLOT_OUT_MS) rather than going on the
// same tick -- assert the fade has started now, and that it finished after.
const compass = d.getElementById('nav-compass');
ok(compass.classList.contains('slot-out') || !shown('nav-compass'),
   'the compass starts fading out with the map', compass.className);

setTimeout(function () {
  ok(!shown('nav-compass'), 'and is gone once the fade finishes', compass.className);

  // Map back: now the badge may return, because nav no longer wants the corner.
  msg({ action: 'mapRect', visible: true });
  ok(shown('map-badge'), 'badge returns once the map is back and nav is clear');

  console.log(fails ? '\n' + fails + ' check(s) failed' : '\nall checks passed');
  process.exit(fails ? 1 : 0);
}, 900);
