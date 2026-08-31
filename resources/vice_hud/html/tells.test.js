/* Headless test for the wanted-tells row's five icons.
 *
 *   node html/tells.test.js
 *
 * Not shipped to clients -- not in fxmanifest's files{}. Run it after
 * touching TELL_SVG in app.js or #tells/.tell in style.css. Exists mainly to
 * catch a typo'd key rendering an empty badge -- renderTells() silently draws
 * nothing for a key TELL_SVG doesn't have, which editor.test.js's broader
 * onWanted exercise wouldn't notice. */
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

console.log('\n-- all five current tells render actual SVG content --');
msg({ action: 'wanted', active: true, stars: 3, maxStars: 6,
      tells: ['camera', 'medical', 'hanger', 'person', 'flag'] });
const tells = [...d.querySelectorAll('#tells .tell')];
ok(tells.length === 5, '5 tell badges rendered', tells.length);
tells.forEach(function (t) {
  const svg = t.querySelector('svg');
  ok(!!svg && svg.children.length > 0, 'badge "' + t.title + '" has real SVG content', t.innerHTML);
});

console.log('\n-- the old three keys no longer exist (renamed/dropped) --');
msg({ action: 'wanted', active: true, stars: 3, maxStars: 6,
      tells: ['outfit', 'voice', 'vehicle'] });
const staleTells = [...d.querySelectorAll('#tells .tell')];
ok(staleTells.length === 3, 'still draws 3 badges (renderTells does not filter)', staleTells.length);
ok(staleTells.every(function (t) { return !t.querySelector('svg'); }),
   'but every one of them is empty -- confirms outfit/voice/vehicle are gone from TELL_SVG',
   staleTells.map(function (t) { return t.innerHTML; }));

console.log(fails === 0 ? '\nALL PASS' : ('\n' + fails + ' FAILURES'));
process.exit(fails === 0 ? 0 : 1);
