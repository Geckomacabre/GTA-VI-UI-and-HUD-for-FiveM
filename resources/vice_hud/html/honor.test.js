/* Headless test for the honor panel + centre change indicator.
 *
 *   npm i jsdom && node html/honor.test.js
 *
 * Not shipped to clients -- it is not in fxmanifest's files{}, so FiveM never
 * sends it. Run it after touching onHonor()/onHonorPop() in app.js, the honor
 * markup in index.html, or the #honor rules in style.css.
 *
 * Drives the real page in jsdom with the exact payload shape client.lua's
 * ui('honor', ...) puts on the wire (the data table with `action` added), so
 * these cases are the ones qbx_honor actually produces.
 *
 * The case worth keeping: once honor latches at Config.MinHonor the NUMBER
 * stops moving, so every further kill arrives with delta 0. The centre
 * indicator used to gate purely on a non-zero delta, which meant it silently
 * stopped firing for every deed from that point on while the corner panel
 * carried on drawing -- looked exactly like "the popup is broken".
 */
const fs = require('fs');
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

window.fetch = function () { return Promise.resolve({ json: () => Promise.resolve({}) }); };
window.GetParentResourceName = () => 'vice_hud';

window.eval(fs.readFileSync(base + 'app.js', 'utf8'));
d.dispatchEvent(new window.Event('DOMContentLoaded'));

const $ = (id) => d.getElementById(id);
const shown = (el) => !!el && !el.classList.contains('hidden');

// Mirrors Config.Honor in config.lua. showValue false is the shipped value --
// the reference treatment, mugshot and face only.
const ART = {
  angelEmoji: 'icons/honor_good.png',
  devilEmoji: 'icons/honor_bad.png',
  terribleEmoji: 'icons/honor_terrible.png',
  showValue: false,
  valueLabel: 'HONOR',
  holdMs: 6000,
};

function push(extra) {
  const payload = Object.assign({ action: 'honor' }, ART, extra);
  window.dispatchEvent(new window.MessageEvent('message', { data: payload }));
}

function hidePop() {
  // Between cases, so each assertion is about the push it follows.
  $('honor-pop').classList.add('hidden');
}

console.log('\n-- a terrible deed at a neutral standing --');
push({ mugshot: 'data:,x', emoji: ART.devilEmoji, reason: 'Killed a bystander', honor: -8, delta: -8, broken: false, severity: 'terrible' });
ok(shown($('honor')), 'corner panel shows');
ok(shown($('honor-pop')), 'centre indicator fires');
ok($('honor-pop').className === 'down', 'indicator reads as a loss', $('honor-pop').className);
ok($('honor-pop-sign').textContent === '−', 'indicator shows a minus sign', JSON.stringify($('honor-pop-sign').textContent));
ok($('honor-pop-face').getAttribute('src') === ART.terribleEmoji, 'indicator uses the TERRIBLE face, not the plain devil one', $('honor-pop-face').getAttribute('src'));
ok(!$('honor-badge').classList.contains('broken'), 'badge is not greyed while honor is still repairable');

console.log('\n-- showValue false: picture + emoji only --');
ok($('honor-title').textContent === '', 'no HONOR value line');
ok($('honor-sub').textContent === '', 'no reason line');
ok(!shown($('honor-copy')), 'copy column is removed from the row, not just blanked');
ok($('honor').classList.contains('bare'), 'panel takes the bare class so the gap/padding collapse');

console.log('\n-- the reported bug: a kill while clamped at the floor (delta 0) --');
hidePop();
push({ mugshot: 'data:,x', emoji: ART.terribleEmoji, reason: 'Killed a bystander', honor: -100, delta: 0, broken: true, severity: 'terrible' });
ok(shown($('honor-pop')), 'centre indicator STILL fires with a zero delta');
ok(shown($('honor')), 'corner panel still shows too');
ok($('honor-pop').className === 'broken', 'indicator uses the broken treatment', $('honor-pop').className);
ok(shown($('honor-pop-crack')), 'indicator draws its crack overlay');

console.log('\n-- beyond repair: the badge greys out --');
ok($('honor-badge').classList.contains('broken'), 'badge takes the broken class');
ok($('honor-badge').getAttribute('src') === ART.terribleEmoji, 'badge swaps to the terrible face');
ok(shown($('honor-crack')), 'badge crack overlay shows');
{
  const cs = window.getComputedStyle($('honor-crack'));
  ok(cs.width === '65%', 'crack is 65% of the badge, not full size', cs.width);
  ok(cs.height === '65%', 'crack height matches', cs.height);
}

console.log('\n-- a good deed still reads as a gain --');
hidePop();
push({ mugshot: 'data:,x', emoji: ART.angelEmoji, reason: 'Released a fish', honor: 42, delta: 2, broken: false, severity: 'good' });
ok($('honor-pop').className === 'up', 'indicator reads as a gain', $('honor-pop').className);
ok($('honor-pop-sign').textContent === '+', 'indicator shows a plus sign');
ok($('honor-pop-face').getAttribute('src') === ART.angelEmoji, 'indicator uses the good face');

console.log('\n-- a good deed at the CEILING (delta 0, severity only) --');
hidePop();
push({ mugshot: 'data:,x', emoji: ART.angelEmoji, reason: 'Released a fish', honor: 100, delta: 0, broken: false, severity: 'good' });
ok(shown($('honor-pop')), 'centre indicator fires at the ceiling too');
ok($('honor-pop').className === 'up', 'severity supplies the direction delta cannot', $('honor-pop').className);

console.log('\n-- the panel hairline (--hairline, matching ox_lib\'s panel edge) --');
{
  // Guards the thing that actually went wrong before: the ring was written as
  // a literal inside .plate only, so every surface that wasn't .plate silently
  // had no edge. Asserting the COMPUTED value catches a panel that stopped
  // inheriting it, which reading the stylesheet by eye does not.
  const token = window.getComputedStyle(d.documentElement).getPropertyValue('--hairline').trim();
  ok(/^inset 0 0 0 .+rgba\(\s*2[0-9]{2}, ?2[0-9]{2}, ?2[0-9]{2}, ?0?\.[0-9]+\s*\)$/.test(token),
     '--hairline is an inset near-white ring', token);
  // Pinned to #map-frame's border: that edge is the reference the other panels
  // copy, so a change to one that isn't mirrored in the other is a bug.
  const mapBorder = window.getComputedStyle($('map-frame')).border || '';
  // 0.085cqw -> calc(0.085 * var(--w)) as part of the --w aspect-ratio pass;
  // accept either spelling, same as editor.test.js's matching assertion.
  ok((/0\.085cqw/.test(token) || /calc\(0\.085\s*\*\s*var\(--w\)\)/.test(token)) && /rgba\(236, ?236, ?240, ?0?\.3\)?/.test(token),
     '--hairline matches #map-frame\'s width and colour', token + '   map: ' + mapBorder.slice(0, 40));

  const ringed = ['honor', 'reputation', 'wanted'];
  ringed.forEach((id) => {
    const el = $(id);
    const bs = el ? window.getComputedStyle(el).boxShadow : '';
    ok(/inset/.test(bs) || bs.includes('var(--hairline)'), '#' + id + ' carries the hairline', bs.slice(0, 60));
  });
}

console.log('\n-- a DEED push (ShowHonorDeed) is the indicator ONLY --');
hidePop();
$('honor').classList.add('hidden');           // panel down, as it would be between standings
$('honor-title').textContent = 'SENTINEL';    // must survive: a deed push must not touch the panel
push({ popOnly: true, delta: -8, severity: 'terrible', broken: false });
ok(shown($('honor-pop')), 'centre indicator fires');
ok($('honor-pop-face').getAttribute('src') === ART.terribleEmoji, 'indicator carries the terrible face');
ok(!shown($('honor')), 'corner panel is NOT raised by a deed');
ok($('honor-title').textContent === 'SENTINEL', 'deed push does not rewrite the panel copy');

console.log('\n-- nothing to say: no delta, no severity --');
$('honor').classList.remove('hidden');
hidePop();
push({ mugshot: 'data:,x', emoji: ART.devilEmoji, honor: -8, delta: 0, broken: false });
ok(!shown($('honor-pop')), 'centre indicator stays down when there is genuinely nothing to report');

console.log(fails === 0 ? '\nALL PASS\n' : '\n' + fails + ' FAILED\n');
process.exit(fails === 0 ? 0 : 1);
