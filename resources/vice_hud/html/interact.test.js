/* Headless test for the interact menu (Phase 1 of the ox_target-replacement
 * project -- just the list, no targeting engine).
 *
 *   node html/interact.test.js
 *
 * Not shipped to clients -- not in fxmanifest's files{}. Run it after
 * touching #interact's markup, CSS or the interact functions in app.js. */
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

const posted = [];
window.fetch = function (url, opts) {
  posted.push({ url: String(url), body: JSON.parse(opts.body) });
  return Promise.resolve({ json: () => Promise.resolve({}) });
};
window.GetParentResourceName = () => 'vice_hud';

window.eval(fs.readFileSync(base + 'app.js', 'utf8'));
d.dispatchEvent(new window.Event('DOMContentLoaded'));

const msg = (data) => window.dispatchEvent(new window.MessageEvent('message', { data }));
const $ = (id) => d.getElementById(id);
const key = (k) => d.dispatchEvent(new window.KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true }));

console.log('\n-- hidden until shown --');
msg({ action: 'interact', show: false });
ok($('interact').classList.contains('hidden'), 'interact menu hidden when show:false');

console.log('\n-- shows with 4 options, first selected --');
msg({
  action: 'interact', show: true, selected: 0,
  options: [
    { label: 'Logger Beer' },
    { label: 'Lavazas Beer' },
    { label: 'Blitz Berry Smoothie', badges: ['stamina', 'focus'] },
    { label: 'Blitz Green Smoothie', badges: ['stamina'] }
  ]
});
ok(!$('interact').classList.contains('hidden'), 'interact menu visible');
let rows = [...d.querySelectorAll('.interact-row')];
ok(rows.length === 4, '4 rows rendered', rows.length);
ok(rows[0].classList.contains('selected'), 'first row selected');
ok(rows[0].querySelector('.interact-marker-x'), 'selected row has the X marker');
ok(rows[1].querySelector('.interact-marker-dot'), 'non-selected row has the dot marker');
ok(rows[0].querySelector('.interact-label').textContent === 'Logger Beer', 'label text correct');
ok(rows[2].querySelectorAll('.interact-badge').length === 2, 'third row has 2 badges', rows[2].querySelectorAll('.interact-badge').length);
ok(rows[3].querySelectorAll('.interact-badge').length === 1, 'fourth row has 1 badge');

console.log('\n-- arrow keys move selection --');
key('ArrowDown');
rows = [...d.querySelectorAll('.interact-row')];
ok(rows[1].classList.contains('selected'), 'ArrowDown moved selection to row 1');
key('ArrowDown'); key('ArrowDown'); key('ArrowDown'); // wraps past the end
rows = [...d.querySelectorAll('.interact-row')];
ok(rows[0].classList.contains('selected'), 'selection wraps around at the end', rows.map(r => r.classList.contains('selected')));
key('ArrowUp');
rows = [...d.querySelectorAll('.interact-row')];
ok(rows[3].classList.contains('selected'), 'ArrowUp wraps backward from 0');

console.log('\n-- arrow keys also post interactMove, to keep Lua\'s controller-side cache in sync --');
posted.length = 0;
key('ArrowDown');
ok(posted.length === 1 && posted[0].url.endsWith('/interactMove') && posted[0].body.index === 0, 'posted interactMove with the new index', posted);

console.log('\n-- Enter posts interactSelect with the current index --');
posted.length = 0;
key('Enter');
ok(posted.length === 1 && posted[0].url.endsWith('/interactSelect') && posted[0].body.index === 0,
   'posted interactSelect with index 0', posted);

console.log('\n-- reopening then clicking a row selects it directly --');
msg({
  action: 'interact', show: true, selected: 0,
  options: [{ label: 'A' }, { label: 'B' }, { label: 'C' }]
});
posted.length = 0;
rows = [...d.querySelectorAll('.interact-row')];
rows[2].dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
ok(posted.length === 1 && posted[0].url.endsWith('/interactSelect') && posted[0].body.index === 2,
   'clicking row 2 posts interactSelect with index 2', posted);

console.log('\n-- Escape posts interactClose --');
msg({ action: 'interact', show: true, selected: 0, options: [{ label: 'A' }] });
posted.length = 0;
key('Escape');
ok(posted.length === 1 && posted[0].url.endsWith('/interactClose'), 'posted interactClose', posted);

console.log('\n-- hides on show:false --');
msg({ action: 'interact', show: false });
ok($('interact').classList.contains('hidden'), 'interact menu hidden again');

console.log(fails === 0 ? '\nALL PASS' : ('\n' + fails + ' FAILURES'));
process.exit(fails === 0 ? 0 : 1);
