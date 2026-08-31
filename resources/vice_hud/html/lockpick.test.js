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

console.log('\n-- lockpick: opens with a zone position/width and glyph --');
msg({ action: 'lockpick', show: true, zoneStart: 62, zoneLen: 12, glyph: 'R' });
ok(!$('lockpick').classList.contains('hidden'), 'visible');
ok($('lp-zone').style.getPropertyValue('--lp-zone-start') === '62', 'zone start set', $('lp-zone').style.getPropertyValue('--lp-zone-start'));
ok($('lp-zone').style.getPropertyValue('--lp-zone-len') === '12', 'zone length set');
ok($('lp-glyph').textContent === 'R', 'glyph text set');
ok($('lp-fill').style.getPropertyValue('--lp-pct') === '0', 'fill resets to 0 on open');

console.log('\n-- lockpick: progress updates the fill, clamped 0-100 --');
msg({ action: 'lockpickProgress', pct: 48 });
ok($('lp-fill').style.getPropertyValue('--lp-pct') === '48', 'fill follows pct', $('lp-fill').style.getPropertyValue('--lp-pct'));
msg({ action: 'lockpickProgress', pct: 140 });
ok($('lp-fill').style.getPropertyValue('--lp-pct') === '100', 'fill clamped at 100');
msg({ action: 'lockpickProgress', pct: -10 });
ok($('lp-fill').style.getPropertyValue('--lp-pct') === '0', 'fill clamped at 0');

console.log('\n-- lockpick: result flashes win/fail then auto-hides --');
msg({ action: 'lockpickResult', success: true });
ok($('lockpick').classList.contains('lp-win'), 'lp-win class applied on success');
ok(!$('lockpick').classList.contains('hidden'), 'still visible immediately after the result (flash first)');

console.log(fails === 0 ? '\nALL PASS' : ('\n' + fails + ' FAILURES'));
process.exit(fails === 0 ? 0 : 1);
