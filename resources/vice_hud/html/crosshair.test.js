/* Headless test for the aim crosshair.
 *
 *   node html/crosshair.test.js
 *
 * Not shipped to clients -- not in fxmanifest's files{}. Run it after
 * touching #crosshair's markup, CSS or the crosshair functions in app.js. */
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

const st = d.createElement('style');
st.textContent = fs.readFileSync(base + 'style.css', 'utf8');
d.head.appendChild(st);

window.fetch = function () { return Promise.resolve({ json: () => Promise.resolve({}) }); };
window.GetParentResourceName = () => 'vice_hud';

window.eval(fs.readFileSync(base + 'app.js', 'utf8'));
d.dispatchEvent(new window.Event('DOMContentLoaded'));

const msg = (data) => window.dispatchEvent(new window.MessageEvent('message', { data }));
const $ = (id) => d.getElementById(id);

console.log('\n-- hidden until told to be active --');
msg({ action: 'crosshair', active: false });
ok($('crosshair').classList.contains('hidden'), 'crosshair hidden when inactive');

console.log('\n-- foot mode shows the tick reticle --');
msg({ action: 'crosshair', active: true, mode: 'foot' });
ok(!$('crosshair').classList.contains('hidden'), 'crosshair visible');
ok($('crosshair').dataset.mode === 'foot', 'data-mode is foot');

console.log('\n-- vehicle mode shows the ring --');
msg({ action: 'crosshair', active: true, mode: 'vehicle' });
ok($('crosshair').dataset.mode === 'vehicle', 'data-mode is vehicle');

console.log('\n-- a shot widens the reticle, then it settles back --');
msg({ action: 'crosshair', active: true, mode: 'foot' });
msg({ action: 'crossFire' });
const tips = $('cross-tips');
ok(tips.style.getPropertyValue('--spread') === 'calc(0.35 * var(--w))', 'spread pushed on fire', tips.style.getPropertyValue('--spread'));

console.log('\n-- kill mark: headshot is red, forces crosshair visible --');
msg({ action: 'crosshair', active: false });
msg({ action: 'crossKill', quality: 'headshot' });
ok(!$('crosshair').classList.contains('hidden'), 'crosshair forced visible for the flash');
ok($('cross-kill').classList.contains('kill-red'), 'headshot -> kill-red');
ok($('cross-kill').classList.contains('show'), 'kill mark shown');

console.log('\n-- kill mark: sloppy is yellow, clean is white --');
msg({ action: 'crossKill', quality: 'sloppy' });
ok($('cross-kill').classList.contains('kill-yellow') && !$('cross-kill').classList.contains('kill-red'),
   'sloppy -> kill-yellow, previous colour cleared');
msg({ action: 'crossKill', quality: 'clean' });
ok($('cross-kill').classList.contains('kill-white') && !$('cross-kill').classList.contains('kill-yellow'),
   'clean -> kill-white, previous colour cleared');

console.log(fails === 0 ? '\nALL PASS' : ('\n' + fails + ' FAILURES'));
process.exit(fails === 0 ? 0 : 1);
