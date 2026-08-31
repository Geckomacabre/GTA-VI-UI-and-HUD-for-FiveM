/* Headless test for the race lap/checkpoint HUD.
 *
 *   node html/laptimer.test.js
 *
 * Not shipped to clients -- not in fxmanifest's files{}. Run it after
 * touching #lap-hud's markup, CSS or the lap-hud functions in app.js. */
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

console.log('\n-- hidden until shown --');
msg({ action: 'lapHud', show: false });
ok($('lap-hud').classList.contains('hidden'), 'lap hud hidden when show:false');

console.log('\n-- shows with lap/checkpoint/time data --');
msg({ action: 'lapHud', show: true, lap: 1, laps: 2, cp: 10, cpTotal: 16, elapsedMs: 19950, running: true });
ok(!$('lap-hud').classList.contains('hidden'), 'lap hud visible');
ok($('lap-cur').textContent === '1' && $('lap-total').textContent === '2', 'lap counter text', [$('lap-cur').textContent, $('lap-total').textContent]);
ok($('lap-cp-cur').textContent === '10' && $('lap-cp-total').textContent === '16', 'checkpoint counter text');

console.log('\n-- pips: 16 rendered, 10 lit --');
const pips = [...d.querySelectorAll('#lap-cp-track .lap-cp-pip')];
ok(pips.length === 16, '16 pips rendered', pips.length);
ok(pips.filter(p => p.classList.contains('on')).length === 10, '10 pips lit');
ok(pips[9].classList.contains('on') && !pips[10].classList.contains('on'), 'boundary pip is correct (0-indexed 9 on, 10 off)');

console.log('\n-- timer displays the pushed value immediately --');
ok($('lap-timer').textContent === '00:19.95', 'timer text matches elapsedMs', $('lap-timer').textContent);

console.log('\n-- pip count rebuilds only when it changes --');
msg({ action: 'lapHud', show: true, lap: 1, laps: 2, cp: 11, cpTotal: 16, elapsedMs: 20100, running: true });
const pipsAfter = [...d.querySelectorAll('#lap-cp-track .lap-cp-pip')];
ok(pipsAfter.length === 16, 'still 16 pips (same element instances, not rebuilt)', pipsAfter.length);
ok(pipsAfter[0] === pips[0], 'first pip element is literally the same node (rebuild was skipped)');
ok(pipsAfter.filter(p => p.classList.contains('on')).length === 11, '11 pips lit now');

console.log('\n-- stopping (running:false) freezes the timer at the last pushed value --');
msg({ action: 'lapHud', show: true, lap: 2, laps: 2, cp: 16, cpTotal: 16, elapsedMs: 45230, running: false });
ok($('lap-timer').textContent === '00:45.23', 'timer frozen at final elapsedMs', $('lap-timer').textContent);

console.log('\n-- hides on show:false --');
msg({ action: 'lapHud', show: false });
ok($('lap-hud').classList.contains('hidden'), 'lap hud hidden again');

console.log(fails === 0 ? '\nALL PASS' : ('\n' + fails + ' FAILURES'));
process.exit(fails === 0 ? 0 : 1);
