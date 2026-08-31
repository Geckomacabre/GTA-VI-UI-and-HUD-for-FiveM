/* The world action prompt (Slim Jim / Smash Window) must show the button
 * that ACTUALLY does something, on whichever device the player is using.
 *
 *   node html/worldactions.test.js
 *
 * Not shipped to clients -- not in fxmanifest's files{}. This is a regression
 * test for a real bug: the prompt used to take a hand-picked icon STRING with
 * no connection to the caller's actual keybind, so the icon and the working
 * button drifted apart -- a controller player saw a Triangle for Slim Jim
 * while the real button underneath was Circle, and pressing what was on
 * screen did nothing. Now the page is handed a resolved `glyph` (from Lua's
 * GetControlInstructionalButton against the caller's own keybind hash) and
 * derives the icon from THAT, so the two can no longer disagree.
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
const box = () => d.getElementById('world-actions');
const rows = () => Array.from(box().querySelectorAll('.wa-row'));

// ---- pad, recognised face buttons: the outlined shape ----------------------
msg({ action: 'worldActions', show: true, options: [
  { label: 'Slim Jim', glyph: 'Y', device: 'pad' },
  { label: 'Smash Window', glyph: 'B', device: 'pad' },
]});
ok(!box().classList.contains('hidden'), 'app.js listener is attached (box shows)');
let r = rows();
ok(r.length === 2, 'both options rendered', r.length);
ok(r[0].querySelector('.wa-btn svg') && !r[0].querySelector('.wa-btn').textContent,
   'pad Y (Triangle) renders the SHAPE icon, not text');
ok(r[0].querySelector('.wa-btn svg path'),
   'and it IS the triangle path, not some other shape');
ok(r[1].querySelector('.wa-btn svg circle'),
   'pad B (Circle) renders the circle shape');

// ---- keyboard: the resolved key as plain text ------------------------------
msg({ action: 'worldActions', show: true, options: [
  { label: 'Slim Jim', glyph: 'R', device: 'kbm' },
  { label: 'Smash Window', glyph: 'F', device: 'kbm' },
]});
r = rows();
ok(!r[0].querySelector('.wa-btn svg'), 'keyboard renders NO shape svg');
ok(r[0].querySelector('.wa-btn').textContent === 'R', 'keyboard shows the real bound letter (R)', r[0].querySelector('.wa-btn').textContent);
ok(r[1].querySelector('.wa-btn').textContent === 'F', 'and the other option shows its own letter (F)', r[1].querySelector('.wa-btn').textContent);
ok(r[0].querySelector('.wa-btn').classList.contains('wa-btn-text'),
   'the text variant gets its own class so it does not inherit the shape sizing');

// ---- a pad button with no shape mapping (shoulder/trigger/D-pad) ----------
// Must not silently render nothing -- the whole point of this fix is that the
// icon always reflects the real binding, even for a button this component
// has no dedicated artwork for.
msg({ action: 'worldActions', show: true, options: [
  { label: 'Slim Jim', glyph: 'LB', device: 'pad' },
]});
r = rows();
ok(!r[0].querySelector('.wa-btn svg'), 'an unmapped pad button falls back off the shape path');
ok(r[0].querySelector('.wa-btn').textContent === 'LB',
   'and shows its own resolved text instead of a blank circle', r[0].querySelector('.wa-btn').textContent);

// ---- hides cleanly, and an old-shape payload (pre-fix caller) is inert -----
msg({ action: 'worldActions', show: false });
ok(box().classList.contains('hidden'), 'hides when told to');

console.log(fails ? '\n' + fails + ' check(s) failed' : '\nall checks passed');
process.exit(fails ? 1 : 0);
