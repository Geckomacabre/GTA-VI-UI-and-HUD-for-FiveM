/* Headless test for the manufacturer badge and the vehicle pips.
 *
 *   npm i jsdom && node html/makes.test.js
 *
 * Not shipped to clients -- it is not in fxmanifest's files{}, so FiveM never
 * sends it. Run it after touching html/makes.js, tools/make_makes.py, or the
 * pip rules in app.js.
 *
 * Two halves:
 *   1. VICE_MAKES.lookup on its own -- the spawn-code tokens, the accents, the
 *      two prefix passes, and the pairs that must not resolve to each other.
 *   2. the real page, driven through onVehicle the way client.lua drives it. */
const fs = require('fs');
const path = require('path');
const { JSDOM } = require('jsdom');

const base = __dirname + '/';
const html = fs.readFileSync(base + 'index.html', 'utf8');

let fails = 0;
function ok(cond, label, extra) {
  if (cond) { console.log('  PASS  ' + label); }
  else { console.log('  FAIL  ' + label + (extra !== undefined ? '   -> ' + extra : '')); fails++; }
}

const dom = new JSDOM(html, { url: 'http://localhost/', runScripts: 'outside-only', pretendToBeVisual: true });
const { window } = dom;
const d = window.document;
window.Element.prototype.scrollIntoView = function () { this.__scrolled = true; };

const st = d.createElement('style');
st.textContent = fs.readFileSync(base + 'style.css', 'utf8');
d.head.appendChild(st);

window.eval(fs.readFileSync(base + 'makes.js', 'utf8'));
window.eval(fs.readFileSync(base + 'app.js', 'utf8'));
d.dispatchEvent(new window.Event('DOMContentLoaded'));

const msg = (data) => window.dispatchEvent(new window.MessageEvent('message', { data }));
const $ = (id) => d.getElementById(id);
const MAKES = window.VICE_MAKES;
const key = (name) => { const m = MAKES.lookup(name); return m ? m.key : null; };

console.log('\n-- the table loaded --');
ok(!!MAKES, 'VICE_MAKES is on window');
ok(Object.keys(MAKES.makes).length === 66, '66 manufacturers', Object.keys(MAKES.makes).length);

console.log('\n-- display names resolve --');
ok(key('Truffade') === 'TRUFFADE', 'Truffade');
ok(key('Pegassi') === 'PEGASSI', 'Pegassi, even with no mark of its own');
ok(key('Übermacht') === 'UBERMACHT', 'accents are stripped: Übermacht');
ok(key('Överflöd') === 'OVERFLOD', 'two accents: Överflöd');
ok(key('Western Motorcycle Company') === 'WESTERNMOTORCYCLECOMPANY', 'spaces are dropped');
ok(key('Jack Sheepe') === 'JACKSHEEPE', 'Jack Sheepe');

console.log('\n-- truncated spawn tokens resolve --');
// GetMakeNameFromVehicleModel hands back an eight-character token when the GXT
// lookup misses. These are the shapes that actually occur.
[['UBERMACH', 'UBERMACHT'], ['DEWBAUCH', 'DEWBAUCHEE'], ['BENEFAC', 'BENEFACTOR'],
 ['DUNDREAR', 'DUNDREARY'], ['ZIRCONIU', 'ZIRCONIUM'], ['BUCKING', 'BUCKINGHAM'],
 ['LAMPADAT', 'LAMPADATI'], ['CLASSIQUE', 'CLASSIQUE'], ['INVETERO', 'INVETERO']
].forEach(([token, want]) => ok(key(token) === want, token + ' -> ' + want, key(token)));

console.log('\n-- aliases cover what a prefix cannot --');
[['GALIVANT', 'GALLIVANTER'], ['JACKSHEE', 'JACKSHEEPE'], ['SPEEDOPH', 'SPEEDOPHILE'],
 ['LCC', 'LIBERTYCITYCYCLES'], ['PED', 'PEDCYCLES']
].forEach(([token, want]) => ok(key(token) === want, token + ' -> ' + want, key(token)));

console.log('\n-- the two Western divisions do not collide --');
ok(key('WESTERN') === 'WESTERNCOMPANY', 'bare WESTERN is the aircraft company');
ok(key('WESTMIN') === 'WESTERNMOTORCYCLECOMPANY', 'WESTMIN is the motorcycle company');
ok(key('WesternMC') === 'WESTERNMOTORCYCLECOMPANY', 'so is WesternMC');
// The longest-match pass is the thing being checked here: a shortest-match
// rule would answer this with WESTERNCOMPANY.
ok(key('WesternMotorcycleCompanyCustoms') === 'WESTERNMOTORCYCLECOMPANY',
   'a decorated name takes the LONGEST marque it starts with', key('WesternMotorcycleCompanyCustoms'));

console.log('\n-- unknown makes stay unknown --');
ok(key('') === null, 'empty string');
ok(key(null) === null, 'null');
ok(key('Mansory') === null, 'an addon manufacturer');
ok(key('SEGWAYCIV') === null, 'a raw spawn code that is not a marque');
ok(key('XYZ') === null, 'a short token matches nothing rather than guessing');

console.log('\n-- every mark named in the table is on disk --');
let missingFiles = [];
let withMark = 0;
Object.keys(MAKES.makes).forEach(function (k) {
  const file = MAKES.makes[k][1];
  if (!file) return;
  withMark++;
  if (!fs.existsSync(path.join(base, 'logos', file))) missingFiles.push(file);
  if (file !== k + '.png') missingFiles.push(file + ' (does not match its key)');
});
ok(missingFiles.length === 0, 'no dangling logo references', missingFiles.join(', '));
ok(withMark >= 50, 'at least 50 manufacturers have a mark', withMark);

console.log('\n-- the panel wires the mark up --');
msg({ action: 'vehicle', show: true, make: 'Truffade', model: 'Thrax',
      fuel: 70, engineOn: true, engineHealth: 1000, lockState: 'locked' });
ok($('vehicle').classList.contains('badged'), 'a known marque badges the panel');
ok($('veh-logo').getAttribute('src') === 'logos/TRUFFADE.png', 'and points at its mark',
   $('veh-logo').getAttribute('src'));
ok($('veh-make').textContent === 'TRUFFADE', 'make line still set');

msg({ action: 'vehicle', show: true, make: 'Vapid', model: 'Dominator',
      fuel: 70, engineOn: true, engineHealth: 1000, lockState: 'locked' });
ok(!$('vehicle').classList.contains('badged'),
   'a marque whose only mark is its own name gets no badge');
ok(!$('veh-logo').getAttribute('src'), 'and the src is cleared, not left stale',
   $('veh-logo').getAttribute('src'));

msg({ action: 'vehicle', show: true, make: '', model: 'SEGWAYCIV',
      fuel: 70, engineOn: true, engineHealth: 1000, lockState: 'locked' });
ok(!$('vehicle').classList.contains('badged'), 'an addon with no make gets no badge');

console.log('\n-- pip tones --');
// Just the tone token. The class list also carries `pip` and, on the two that
// have a ring, `gauge` -- neither of which is what these cases are about.
const tones = () => ['pip-lock', 'pip-engine', 'pip-fuel']
  .map((id) => $(id).className.split(/\s+/)
    .filter((c) => c && c !== 'pip' && c !== 'gauge')[0] || '')
  .join(' ');

function pips(label, payload, want) {
  payload.action = 'vehicle';
  payload.show = true;
  payload.make = 'Karin';
  payload.model = 'Kuruma';
  msg(payload);
  ok(tones() === want, label + ' -> ' + want, tones());
}

pips('running, healthy, locked, full tank',
     { fuel: 70, engineOn: true, engineHealth: 1000, lockState: 'locked' },
     'good good good');
pips('worn engine, unlocked',
     { fuel: 70, engineOn: true, engineHealth: 450, lockState: 'unlocked' },
     'warn warn good');
pips('broken engine, a quarter tank',
     { fuel: 20, engineOn: true, engineHealth: 80, lockState: 'locked' },
     'good bad warn');
// GetVehicleEngineHealth goes NEGATIVE past seized, so the bad band cannot
// have a floor on it.
pips('destroyed engine reads negative, still bad',
     { fuel: 5, engineOn: true, engineHealth: -4000, lockState: 'locked' },
     'good bad bad');
// The rule the whole thing hangs on: a parked car says nothing in colour.
pips('SHUT OFF is monochrome whatever else is wrong',
     { fuel: 5, engineOn: false, engineHealth: -4000, lockState: 'locked' },
     'unknown unknown unknown');
pips('an older client.lua sending no engineHealth is not "broken"',
     { fuel: 70, engineOn: true, lockState: 'locked' },
     'good good good');

console.log('\n-- pip glyphs are drawn, not typed --');
// They were emoji, and Windows renders the padlock orange and the pump red
// whatever `color` says. Inline SVG is what keeps the trio one colour.
const glyphs = ['pip-lock', 'pip-engine', 'pip-fuel'].map((id) => $(id).querySelector('.pip-glyph'));
ok(glyphs.every(Boolean), 'every pip holds a glyph svg');
ok(['pip-lock', 'pip-engine', 'pip-fuel'].every((id) => !$(id).textContent.trim()),
   'and no text content that a font could colour');

console.log('\n-- the gauge rings read the real numbers --');
const pct = (id) => $(id).style.getPropertyValue('--pct');
const ring = (id) => $(id).querySelector('.pip-fill');

ok(ring('pip-fuel') && ring('pip-engine'), 'fuel and engine have a ring');
// The lock is a STATE, not a quantity. A ring on it would be a gauge that only
// ever reads full or empty, which is a worse way of saying what the colour
// already says.
ok(!ring('pip-lock'), 'the lock does not');

msg({ action: 'vehicle', show: true, make: 'Karin', model: 'Kuruma',
      fuel: 64, engineOn: true, engineHealth: 730, lockState: 'locked' });
ok(pct('pip-fuel') === '64.0', 'fuel ring reads the fuel level', pct('pip-fuel'));
ok(pct('pip-engine') === '73.0', 'engine ring reads health/10', pct('pip-engine'));

msg({ action: 'vehicle', show: true, make: 'Karin', model: 'Kuruma',
      fuel: 0, engineOn: true, engineHealth: -4000, lockState: 'locked' });
ok(pct('pip-fuel') === '0.0', 'an empty tank reads zero', pct('pip-fuel'));
// The native goes far below zero for a destroyed engine; the ring must clamp
// rather than compute a negative dash offset.
ok(pct('pip-engine') === '0.0', 'a destroyed engine clamps to zero, not negative',
   pct('pip-engine'));
// A round linecap paints a dot even at zero, which would show a pip of fuel in
// an empty tank.
ok(ring('pip-fuel').getAttribute('data-empty') === '1',
   'and zero switches the cap so it draws nothing at all');

msg({ action: 'vehicle', show: true, make: 'Karin', model: 'Kuruma',
      fuel: 140, engineOn: true, engineHealth: 4000, lockState: 'locked' });
ok(pct('pip-fuel') === '100.0', 'over-full clamps to 100', pct('pip-fuel'));
ok(pct('pip-engine') === '100.0', 'so does a better-than-new engine', pct('pip-engine'));

// The reading survives the engine being off: only the COLOUR goes monochrome.
msg({ action: 'vehicle', show: true, make: 'Karin', model: 'Kuruma',
      fuel: 42, engineOn: false, engineHealth: 800, lockState: 'locked' });
ok(pct('pip-fuel') === '42.0', 'a parked car still shows how much fuel it has',
   pct('pip-fuel'));
ok($('pip-fuel').classList.contains('unknown'), 'but says it in grey');

console.log('\n-- the panel collapses to just the icons --');
msg({ action: 'vehicle', show: true, collapsed: false, make: 'Truffade', model: 'Thrax',
      fuel: 70, engineOn: true, engineHealth: 1000, lockState: 'locked' });
ok(!$('vehicle').classList.contains('collapsed'), 'the announcement draws the whole plate');
ok($('veh-make').textContent === 'TRUFFADE', 'names are filled in');

msg({ action: 'vehicle', show: true, collapsed: true, make: 'Truffade', model: 'Thrax',
      fuel: 55, engineOn: true, engineHealth: 900, lockState: 'locked' });
ok($('vehicle').classList.contains('collapsed'), 'and then collapses');
ok(!$('vehicle').classList.contains('hidden'), 'without hiding the element');
ok(pct('pip-fuel') === '55.0', 'the gauges keep updating while collapsed',
   pct('pip-fuel'));

msg({ action: 'vehicle', show: false });
ok($('vehicle').classList.contains('slot-out') || $('vehicle').classList.contains('hidden'),
   'leaving the vehicle takes the whole thing away');

const css2 = fs.readFileSync(base + 'style.css', 'utf8');
const collapsedRule = css2.slice(css2.indexOf('#vehicle.collapsed {'));
ok(/background:\s*none/.test(collapsedRule.slice(0, 200)),
   'collapsed has no plate behind it');
// max-height/opacity rather than `display: none`: the head has to ANIMATE
// away and display is not animatable. Asserting the exact property pinned this
// to one implementation of "gone"; assert the outcome instead.
const headCollapse = css2.slice(css2.indexOf('#vehicle.collapsed #veh-head {'), );
ok(/max-height:\s*0/.test(headCollapse.slice(0, 240))
   && /opacity:\s*0/.test(headCollapse.slice(0, 240)),
   'and the announcement half is gone entirely');

console.log('\n-- the panel is two bands, and the badge stops at the barrier --');
// jsdom has no layout, so these check the STRUCTURE and the rules that produce
// the banding rather than measuring it. Between them they are what stops a
// future edit quietly putting the badge back over the status strip.
ok($('veh-logo').parentElement.id === 'veh-logo-clip', 'the badge sits inside its clip window');
ok($('veh-logo-clip').parentElement.id === 'veh-head', 'and the clip window is inside the head');
ok($('veh-pips').parentElement.id === 'veh-foot', 'the pips are in the foot band, not the head');
ok($('veh-make').parentElement.id === 'veh-head', 'the names are in the head band');

const css = fs.readFileSync(base + 'style.css', 'utf8');
// The selector must start a LINE. `#veh-foot` also appears inside
// `#vehicle.collapsed #veh-foot`, and a bare indexOf finds whichever comes
// first in the file rather than the base rule being asked about.
// A selector can legitimately appear MORE THAN ONCE at the top level --
// #veh-foot has a transition-only block early on and its real block later --
// so returning the first match asks the wrong block about `border-top` and
// reports a property missing that is plainly there. Concatenate every
// top-level block for the selector instead.
const rule = (sel) => {
  const out = [];
  const needle = '\n' + sel + ' {';
  let i = css.indexOf(needle);
  while (i >= 0) {
    out.push(css.slice(i, css.indexOf('}', i)));
    i = css.indexOf(needle, i + 1);
  }
  return out.join('\n');
};
ok(/overflow:\s*hidden/.test(rule('#veh-logo-clip')),
   'the clip window clips -- without this the mark bleeds into the status strip');
ok(/inset:\s*0/.test(rule('#veh-logo-clip')), 'and it spans the head exactly');
ok(/border-top:/.test(rule('#veh-foot')),
   'the barrier is the foot band border, so it reaches both edges by construction');
ok(/align-self:\s*stretch/.test(rule('#veh-foot')),
   'and the band is full width rather than centred on its content');
ok(/background:\s*rgba/.test(rule('#veh-foot')),
   'the strip is a different shade from the plate above it');
ok(/padding:\s*0;/.test(rule('#vehicle')),
   'the plate has no padding of its own -- it would show as a gap the barrier could not span');

console.log('\n-- the map panels are set in GTA Art Deco by default --');
ok(/--ff-slots,\s*'GTAArtDeco'/.test(css),
   'Art Deco is the shipped default for the slot stack, not just a Font row option');

console.log('\n-- the editor offers the badge as its own element --');
msg({ action: 'openEditor', offsets: {}, native: { scaleW: 0.663, rounded: 1 } });
const labels = [...d.querySelectorAll('#editor-list .ed-item')]
  .map((n) => n.querySelector('.ed-name') ? n.querySelector('.ed-name').textContent : n.textContent);
ok(labels.some((t) => /Vehicle badge/.test(t)), 'a "Vehicle badge" row exists',
   labels.join(' | '));

// Select it and check it is offered the rows an IMAGE has, and none of the
// text ones -- a Font row on a picture is a control that does nothing.
const badgeIdx = [...d.querySelectorAll('#editor-list .ed-item')]
  .findIndex((n) => /Vehicle badge/.test(n.textContent));
[...d.querySelectorAll('#editor-list .ed-item')][badgeIdx].dispatchEvent(
  new window.MouseEvent('click', { bubbles: true }));
const rows = [...d.querySelectorAll('#editor-props .ed-prop .ed-plabel')]
  .map((n) => n.textContent.trim());
const has = (t) => rows.indexOf(t) >= 0;
ok(has('Position X') && has('Position Y'), 'badge has Position rows', rows.join(' | '));
ok(has('Width') && has('Height'), 'badge has Width and Height');
ok(has('Opacity'), 'badge has Opacity');
ok(!has('Font') && !has('Letter spacing') && !has('Text align'),
   'and none of the text rows', rows.join(' | '));

console.log('\n-- the page survives makes.js not being served --');
// This is the fault that actually happened in game: makes.js is a separate file
// and a server that has not rescanned the resource folder 404s it. Everything
// else has to keep working, silently and without throwing -- a HUD that dies
// because a decoration is missing is far worse than one with no badges.
{
  const d2 = new JSDOM(html, { url: 'http://localhost/', runScripts: 'outside-only', pretendToBeVisual: true });
  const w2 = d2.window;
  w2.Element.prototype.scrollIntoView = function () {};
  let threw = null;
  try {
    // app.js ONLY -- makes.js deliberately not loaded.
    w2.eval(fs.readFileSync(base + 'app.js', 'utf8'));
    w2.document.dispatchEvent(new w2.Event('DOMContentLoaded'));
    w2.dispatchEvent(new w2.MessageEvent('message', { data: {
      action: 'vehicle', show: true, make: 'Truffade', model: 'Thrax',
      fuel: 70, engineOn: true, engineHealth: 1000, lockState: 'locked' } }));
  } catch (e) { threw = e; }
  ok(!threw, 'app.js loads and runs without the table', threw && threw.message);
  ok(w2.document.getElementById('veh-model').textContent === 'THRAX',
     'the panel still fills in, badge or no badge',
     w2.document.getElementById('veh-model').textContent);
  ok(!w2.document.getElementById('vehicle').classList.contains('badged'),
     'and simply does not badge');
}

console.log(fails ? '\n' + fails + ' FAILING\n' : '\nall checks passed\n');
process.exit(fails ? 1 : 0);
