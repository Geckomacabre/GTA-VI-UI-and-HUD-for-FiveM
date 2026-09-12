/* Headless test for the world action prompt (#world-actions) and the
 * lockpick check (#lockpick) -- the car-theft "Slim Jim / Smash Window"
 * interaction.
 *
 *   node html/lockpick.test.js
 *
 * Not shipped to clients -- not in fxmanifest's files{}. Run it after
 * touching either component's markup, CSS or app.js functions. */
const fs = require('fs');
const { JSDOM } = require('jsdom');

const base = __dirname + '/';
const html = fs.readFileSync(base + 'index.html', 'utf8');

let fails = 0;
function ok(cond, label, extra) {
  if (cond) { console.log('  PASS  ' + label); }
  else { console.log('  FAIL  ' + label + (extra !== undefined ? '   -> ' + JSON.stringify(extra) : '')); fails++; }
}

const dom = new JSDOM(html, { url: 'http://localhost/', runScripts: 'outside-only', pretendToBeVisual: true });
const { window } = dom;
const d = window.document;
window.Element.prototype.scrollIntoView = function () { this.__scrolled = true; };

window.fetch = function () { return Promise.resolve({ json: () => Promise.resolve({}) }); };
window.GetParentResourceName = () => 'vice_hud';

window.eval(fs.readFileSync(base + 'app.js', 'utf8'));
d.dispatchEvent(new window.Event('DOMContentLoaded'));

const msg = (data) => window.dispatchEvent(new window.MessageEvent('message', { data }));
const $ = (id) => d.getElementById(id);

console.log('\n-- world-actions: hidden until shown --');
msg({ action: 'worldActions', show: false });
ok($('world-actions').classList.contains('hidden'), 'hidden when show:false');

console.log('\n-- world-actions: renders both options with their button glyphs --');
// { glyph, device } now, not a hand-picked { button } string -- see
// html/worldactions.test.js for the full regression coverage of why (the
// icon used to disagree with what was actually bound). This is just the
// smoke-level check that the row still renders at all.
msg({
  action: 'worldActions', show: true,
  options: [{ label: 'Slim Jim', glyph: 'Y', device: 'pad' }, { label: 'Smash Window', glyph: 'B', device: 'pad' }]
});
ok(!$('world-actions').classList.contains('hidden'), 'visible');
const rows = [...d.querySelectorAll('.wa-row')];
ok(rows.length === 2, '2 rows rendered', rows.length);
ok(rows[0].querySelector('.wa-label').textContent === 'Slim Jim', 'first row labelled Slim Jim');
ok(rows[0].querySelector('.wa-btn svg'), 'first row has a button glyph');
ok(rows[1].querySelector('.wa-label').textContent === 'Smash Window', 'second row labelled Smash Window');

console.log('\n-- lockpick: hidden until shown --');
msg({ action: 'lockpick', show: false });
ok($('lockpick').classList.contains('hidden'), 'hidden when show:false');

console.log('\n-- lockpick: opens with a glyph, no target zone any more --');
msg({ action: 'lockpick', show: true, glyph: 'R' });
ok(!$('lockpick').classList.contains('hidden'), 'visible');
ok($('lp-glyph-text').textContent === 'R', 'glyph text set');
ok($('lp-fill').getAttribute('d') === '', 'fill path resets to empty on open');
ok($('lp-glyph').style.getPropertyValue('--lp-dx') === '0', 'glyph offset resets to 0 on open');

console.log('\n-- lockpick: a mouse-bound glyph draws the LMB/RMB icon, not the letters --');
msg({ action: 'lockpick', show: true, glyph: 'LMB' });
ok($('lp-glyph-text').querySelector('img') !== null, 'LMB glyph renders as an image');
ok($('lp-glyph-text').textContent === '', 'no literal "LMB" text alongside the icon');

console.log('\n-- lockpick: right-to-left progress anchors the fill from the right, clamped 0-100 --');
msg({ action: 'lockpickProgress', pct: 48, dir: -1 });
ok($('lp-fill').getAttribute('d') !== '', 'fill path drawn once pct > 0');
msg({ action: 'lockpickProgress', pct: 140, dir: -1 });
ok($('lp-fill').getAttribute('d') !== '', 'fill path still drawn past 100 (Lua already clamps, but the page must not choke on it)');
msg({ action: 'lockpickProgress', pct: -10, dir: -1 });
ok($('lp-fill').getAttribute('d') === '', 'fill path cleared at pct <= 0');

console.log('\n-- lockpick: left-to-right progress moves the glyph the other way --');
msg({ action: 'lockpickProgress', pct: 50, dir: -1 });
var dxLeft = $('lp-glyph').style.getPropertyValue('--lp-dx');
msg({ action: 'lockpickProgress', pct: 50, dir: 1 });
var dxRight = $('lp-glyph').style.getPropertyValue('--lp-dx');
ok(parseFloat(dxLeft) < 0, 'dir:-1 offsets the glyph negative', dxLeft);
ok(parseFloat(dxRight) > 0, 'dir:1 offsets the glyph positive', dxRight);

console.log('\n-- lockpick: success (right-to-left to 100%) flashes lp-win, not an alarm --');
msg({ action: 'lockpickResult', success: true });
ok($('lockpick').classList.contains('lp-win'), 'lp-win class applied on success');
ok(!$('lockpick').classList.contains('lp-alarm'), 'lp-alarm NOT applied on success');
ok(!$('lockpick').classList.contains('hidden'), 'still visible immediately after the result (flash first)');

console.log('\n-- lockpick: completing it left-to-right trips the alarm instead, a distinct message --');
msg({ action: 'lockpick', show: true, glyph: 'R' });
msg({ action: 'lockpickAlarm' });
ok($('lockpick').classList.contains('lp-alarm'), 'lp-alarm class applied');
ok(!$('lockpick').classList.contains('lp-win'), 'lp-win NOT applied on an alarm trip');
ok(!$('lockpick').classList.contains('hidden'), 'still visible immediately after the alarm (flash first)');

console.log(fails === 0 ? '\nALL PASS' : ('\n' + fails + ' FAILURES'));
process.exit(fails === 0 ? 0 : 1);
