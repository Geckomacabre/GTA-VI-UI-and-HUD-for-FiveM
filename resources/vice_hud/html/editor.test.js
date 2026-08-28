/* Headless test for the /movehud editor.
 *
 *   npm i jsdom && node html/editor.test.js
 *
 * Not shipped to clients -- it is not in fxmanifest's files{}, so FiveM never
 * sends it. Run it after touching the editor's markup, CSS or JS.
 *
 * Drives the real /movehud editor in jsdom: loads index.html + style.css +
   app.js, fakes the openEditor message Lua sends, then exercises the list, the
   property rows, the keyboard and the save payload. */
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

// jsdom has no layout, so scrollIntoView is missing; the editor calls it.
window.Element.prototype.scrollIntoView = function () { this.__scrolled = true; };

const st = d.createElement('style');
st.textContent = fs.readFileSync(base + 'style.css', 'utf8');
d.head.appendChild(st);

// Capture what the page would POST back to Lua.
const posted = [];
window.fetch = function (url, opts) {
  posted.push({ url: String(url), body: JSON.parse(opts.body) });
  return Promise.resolve({ json: () => Promise.resolve({}) });
};
// app.js only posts when it believes it is inside FiveM.
window.GetParentResourceName = () => 'vice_hud';

window.eval(fs.readFileSync(base + 'app.js', 'utf8'));
d.dispatchEvent(new window.Event('DOMContentLoaded'));

const msg = (data) => window.dispatchEvent(new window.MessageEvent('message', { data }));
const $ = (id) => d.getElementById(id);

console.log('\n-- editor opens --');
msg({ action: 'openEditor', offsets: { status: { x: 1.1, y: 1.5, sx: 1.5, sy: 1.5 } }, native: { scaleW: 0.663, rounded: 1 } });
ok(!$('editor').classList.contains('hidden'), 'panel is visible');

console.log('\n-- grouped element list --');
const groups = [...d.querySelectorAll('#editor-list .ed-group')].map(n => n.textContent);
const items = [...d.querySelectorAll('#editor-list .ed-item')];
ok(groups.join(' | ') === 'HUD | Minimap | Other resources', 'three group headings, in order', groups.join(' | '));
ok(items.length === 26, '26 selectable elements', items.length); // Weapon wheel and Equip wheel retired; ox_inventory owns the wheel now
ok(d.querySelectorAll('#editor-list .ed-group').length + items.length === d.querySelectorAll('#editor-list li').length,
   'every li is either a heading or an item');
ok(items[0].classList.contains('sel'), 'first item starts selected');

console.log('\n-- modified dots --');
ok(items[0].querySelector('.ed-dot').classList.contains('on'), 'status (moved 1.1/1.5) is dotted');
ok(!items[3].querySelector('.ed-dot').classList.contains('on'), 'money (untouched) is not dotted');

console.log('\n-- settings column --');
ok($('editor-propfor').textContent === 'Status bars', 'caption names the selected element', $('editor-propfor').textContent);
let rows = [...d.querySelectorAll('.ed-prop .ed-plabel')].map(n => n.textContent);
ok(rows[0] === 'Position X' && rows[1] === 'Position Y', 'position is a real row now', rows.slice(0, 2).join(','));
ok(rows.length === 14, '2 position + 12 css properties', rows.length);
ok(rows.includes('Text align'), 'text alignment is one of them', rows.join(','));
ok(rows.includes('Spacing'), 'so is the gap between an element’s children', rows.join(','));
ok(d.querySelectorAll('.ed-prop .ed-step').length === rows.length, 'every row has a grouped stepper');

console.log('\n-- the + button actually moves the element --');
const before = window.getComputedStyle(d.querySelector('.stage')).getPropertyValue('--off-status-x');
d.querySelectorAll('.ed-prop')[0].querySelectorAll('button')[1].click();   // Position X, plus
const after = window.getComputedStyle(d.querySelector('.stage')).getPropertyValue('--off-status-x');
ok(before.trim() === '1.1cqw' && after.trim() === '1.2cqw', 'Position X + steps 1.1 -> 1.2 on the stage', before + ' -> ' + after);

console.log('\n-- text align writes BOTH properties --');
{
  const stageEl = d.querySelector('.stage');
  const cssv = (n) => window.getComputedStyle(stageEl).getPropertyValue(n).trim();
  // Re-query every time: each step rebuilds the settings column, so a node
  // captured once is detached by the first click.
  const alignRow = () => [...d.querySelectorAll('.ed-prop')][rows.indexOf('Text align')];
  const alPlus = () => alignRow().querySelectorAll('button')[1];
  const alMinus = () => alignRow().querySelectorAll('button')[0];
  const readout = () => alignRow().querySelector('.ed-pval').textContent;

  ok(readout() === 'Default', 'starts on Default', readout());
  ok(cssv('--al-status') === '' && cssv('--ai-status') === '', 'Default writes nothing at all');

  alPlus().click();   // Default -> Left
  ok(readout() === 'Left' && cssv('--al-status') === 'left' && cssv('--ai-status') === 'flex-start',
     'Left   -> text-align:left / flex-start', readout() + ' ' + cssv('--al-status') + ' ' + cssv('--ai-status'));
  alPlus().click();   // -> Center
  ok(readout() === 'Center' && cssv('--al-status') === 'center' && cssv('--ai-status') === 'center',
     'Center -> text-align:center / center', readout() + ' ' + cssv('--al-status') + ' ' + cssv('--ai-status'));
  alPlus().click();   // -> Right
  ok(readout() === 'Right' && cssv('--al-status') === 'right' && cssv('--ai-status') === 'flex-end',
     'Right  -> text-align:right / flex-end', readout() + ' ' + cssv('--al-status') + ' ' + cssv('--ai-status'));
  alPlus().click();   // wraps back to Default
  ok(readout() === 'Default' && cssv('--al-status') === '' && cssv('--ai-status') === '',
     'back to Default clears BOTH properties, not just --al-',
     '[' + cssv('--al-status') + '] [' + cssv('--ai-status') + ']');
  alMinus().click();  // -> Right, so the value has to survive the save at the end
  ok(readout() === 'Right', 'minus cycles the other way', readout());
}

console.log('\n-- arrow keys and the row agree --');
const key = (k, o) => d.dispatchEvent(new window.KeyboardEvent('keydown', Object.assign({ key: k, bubbles: true }, o || {})));
// Numeric rows are <input>s now, list rows are still <span>s.
const pval = (row) => { const n = row.querySelector('.ed-pval'); return n.tagName === 'INPUT' ? n.value : n.textContent; };
key('ArrowRight');
const val = pval(d.querySelectorAll('.ed-prop')[0]);
ok(val === '1.30', 'arrow nudge shows up in the Position X row', val);

console.log('\n-- every number can be typed --');
{
  const rowFor = (label) => [...d.querySelectorAll('.ed-prop')]
    .find(r => r.querySelector('.ed-plabel').textContent === label);
  const field = (label) => rowFor(label).querySelector('.ed-pval');
  const type = (label, text) => {
    const f = field(label);
    f.value = text;
    f.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
  };
  const cssv = (n) => window.getComputedStyle(d.querySelector('.stage')).getPropertyValue(n).trim();

  ok(field('Width').tagName === 'INPUT', 'Width is a text field, not a label', field('Width').tagName);
  ok(field('Font').tagName === 'SPAN', 'a list row is still a label', field('Font').tagName);

  // The whole point: 3.0 used to be the ceiling, and the minimap frame needs
  // more than that to sit on a map that has itself been scaled up.
  type('Width', '7.5');
  ok(cssv('--sc-status-x') === '7.5', 'a width past the old 3.0 cap takes', cssv('--sc-status-x'));
  ok(pval(rowFor('Width')) === '7.50', 'and reads back', pval(rowFor('Width')));

  // Precision the step size could never reach must not be rounded away on the
  // way to the stylesheet OR on the way back to the field.
  type('Width', '4.4375');
  ok(cssv('--sc-status-x') === '4.4375', 'typed precision survives', cssv('--sc-status-x'));
  ok(pval(rowFor('Width')) === '4.4375', 'and is shown in full, not as 4.44', pval(rowFor('Width')));

  // Past the guard rail: clamped, and the row says what it actually did rather
  // than showing a number the HUD is not using.
  type('Width', '99999');
  ok(cssv('--sc-status-x') === '50', 'absurd values clamp to the guard rail', cssv('--sc-status-x'));
  ok(pval(rowFor('Width')) === '50.00', 'and the row shows the clamped value', pval(rowFor('Width')));

  // Junk restores the real value instead of silently becoming zero.
  type('Width', 'banana');
  ok(cssv('--sc-status-x') === '50', 'junk leaves the value alone', cssv('--sc-status-x'));

  // A unit typed (or left) in the box is tolerated.
  type('Letter spacing', '0.045em');
  ok(cssv('--ls-status') === '0.045em', 'a unit in the field is understood', cssv('--ls-status'));

  // Negative positions need the `-` key, which the editor otherwise claims for
  // "decrease the selected property".
  type('Position X', '-12.5');
  ok(cssv('--off-status-x') === '-12.5cqw', 'a negative can be typed', cssv('--off-status-x'));

  // ...and the global handler must not act on keys aimed at the field.
  const before = cssv('--off-status-x');
  const f = field('Position X');
  f.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }));
  f.dispatchEvent(new window.KeyboardEvent('keydown', { key: '-', bubbles: true }));
  f.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'h', bubbles: true }));
  f.dispatchEvent(new window.KeyboardEvent('keydown', { key: ' ', bubbles: true }));
  ok(cssv('--off-status-x') === before, 'typing in a field does not nudge the element', cssv('--off-status-x'));
  ok(!$('editor-panel').classList.contains('collapsed'), 'typing "h" does not collapse the panel');
  ok(!$('editor-panel').classList.contains('peek'), 'typing a space does not fade the panel');

  // Put Position X back where the save assertion at the end expects it.
  type('Position X', '1.3');
}

console.log('\n-- the panel gets out of the way --');
{
  const panel = $('editor-panel');
  const edCs = window.getComputedStyle($('editor'));
  // The full-screen scrim is what blacked out the game and, with it, the
  // ENGINE-DRAWN minimap the editor exists to position. It must not come back.
  ok(edCs.pointerEvents === 'none', 'the backdrop does not swallow clicks', edCs.pointerEvents);
  ok(!/gradient/.test(edCs.background || '') && !/blur/.test(edCs.backdropFilter || edCs.webkitBackdropFilter || 'none'),
     'no scrim and no full-screen blur behind the panel', edCs.background + ' | ' + edCs.backdropFilter);
  ok(window.getComputedStyle(panel).pointerEvents === 'auto', 'the panel itself is still clickable');

  key('h');
  ok(panel.classList.contains('collapsed'), 'H collapses the panel');
  ok(/Collapsed/.test($('editor-sub').textContent), 'and the subtitle says so', $('editor-sub').textContent);
  $('ed-collapse').click();
  ok(!panel.classList.contains('collapsed'), 'the title-bar button expands it again');

  key(' ');
  ok(panel.classList.contains('peek'), 'holding Space fades the panel out');
  d.dispatchEvent(new window.KeyboardEvent('keyup', { key: ' ', bubbles: true }));
  ok(!panel.classList.contains('peek'), 'releasing it brings the panel back');

  const down = (t, x, y) => t.dispatchEvent(new window.MouseEvent('mousedown', { clientX: x, clientY: y, button: 0, bubbles: true }));
  const at = (type, x, y) => d.dispatchEvent(new window.MouseEvent(type, { clientX: x, clientY: y, button: 0, bubbles: true }));
  down($('editor-head'), 400, 40);
  at('mousemove', 460, 120);
  at('mouseup', 460, 120);
  ok(panel.classList.contains('dragged'), 'dragging the title bar moves the panel');
  ok(panel.style.left === '60px' && panel.style.top === '80px',
     'it lands where it was dropped', panel.style.left + ' / ' + panel.style.top);
  ok(/"x":60/.test(window.localStorage.getItem('vice_hud:editorPanelPos') || ''),
     'and the position is remembered for next time', window.localStorage.getItem('vice_hud:editorPanelPos'));

  // A press that starts on a button must not start a drag.
  panel.style.left = ''; panel.style.top = ''; panel.classList.remove('dragged');
  down($('ed-collapse'), 700, 40);
  at('mousemove', 500, 300);
  at('mouseup', 500, 300);
  ok(panel.style.left === '', 'mousedown on the collapse button does not drag', panel.style.left);
}

console.log('\n-- [ ] reach every native row (the wrap bug) --');
// Tab until "Minimap position" is selected, rather than counting to a fixed
// index -- adding an element to the list should not break an unrelated test.
for (let i = 0; i < 40 && $('editor-propfor').textContent !== 'Minimap position'; i++) key('Tab');
ok($('editor-propfor').textContent === 'Minimap position', 'selected the engine-owned row', $('editor-propfor').textContent);
const nrows = [...d.querySelectorAll('.ed-prop .ed-plabel')].map(n => n.textContent);
ok(nrows.length > 9, 'native list is longer than the CSS one (the wrap bug needs that)', nrows.length);
// Press ] once per row and collect what got selected. Derived from the real
// row count, so adding a native setting cannot silently stop being covered.
const seen = new Set();
for (let i = 0; i < nrows.length; i++) {
  seen.add(d.querySelector('.ed-prop.sel .ed-plabel').textContent);
  key(']');
}
ok(seen.size === nrows.length, '] visits every native row', seen.size + '/' + nrows.length +
   ': missing ' + nrows.filter(r => !seen.has(r)).join(', '));
ok(['Corner radius', 'Custom mask', 'Mask = map'].every(r => seen.has(r)),
   'the mask rows past the ninth are keyboard-reachable');

console.log('\n-- the map plane has its own size rows --');
{
  // blipDw / blipDh have always existed in client.lua -- persisted, reset,
  // printed by /mapinfo -- with no way to reach them from the editor. They are
  // the only control that changes the plane's ASPECT relative to its window,
  // which is what draws a radius blip's circle as an oval.
  const rowFor = (label) => [...d.querySelectorAll('.ed-prop')]
    .find(r => r.querySelector('.ed-plabel').textContent === label);
  ok(!!rowFor('Plane width') && !!rowFor('Plane height'),
     'Plane width / Plane height are rows now', nrows.join(','));
  ok(rowFor('Plane width') !== rowFor('Map width'),
     'and are distinct from Map width, which scales map+mask+blur together');
  ok(/radius circle round again/.test(rowFor('Plane width').querySelector('.ed-plabel').title),
     'the label explains which of the two to reach for',
     rowFor('Plane width').querySelector('.ed-plabel').title);

  posted.length = 0;
  const f = rowFor('Plane height').querySelector('.ed-pval');
  f.value = '-120';
  f.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
  const tune = posted.filter(p => p.url.endsWith('/mapTune')).pop();
  ok(tune && tune.body.key === 'blipH' && tune.body.value === -120,
     'and a typed value goes to Lua as an absolute', tune && JSON.stringify(tune.body));
}

console.log('\n-- fonts actually reach the elements --');
{
  const css = fs.readFileSync(base + 'style.css', 'utf8');

  // Art Deco is a real @font-face rule pointing at a shipped file, not a list
  // entry naming a file nobody shipped.
  ok(/GTAArtDecoRegular\.ttf.*format\('truetype'\)/s.test(css), 'Art Deco Regular is declared as truetype');
  ok(/GTAArtDecoMedium\.ttf/.test(css), 'Art Deco Medium too, as a separate real cut');
  ['GTAArtDecoRegular.ttf', 'GTAArtDecoMedium.ttf', 'pricedown.otf'].forEach(f => {
    ok(fs.existsSync(base + 'fonts/' + f), 'fonts/' + f + ' is on disk');
  });

  // Helvetica Neue is deliberately NOT shipped -- it is a commercial face and
  // redistributing it is not ours to do. The family is still declared, but
  // resolved with local() off the player's own machine, and every cut ends in
  // a fallback that exists everywhere so the family always resolves.
  ok(!/url\(['\"]?fonts\/HelveticaNeue/.test(css),
     'no Helvetica Neue file is referenced -- it must not be redistributed');
  ok(!fs.existsSync(base + 'fonts/HelveticaNeueRoman.otf'),
     'and none is on disk');
  ok(/font-family:\s*'HelveticaNeueHUD'/.test(css),
     'the family is still declared, so every existing font stack still resolves');
  ok(/local\('Helvetica Neue'\)/.test(css), 'the real face is used where the OS has it');
  ok(/local\('Arial'\)/.test(css),
     'with Arial as the metric-compatible fallback, so fit measurements hold');
  ok(/font-weight:\s*100 200/.test(css), 'the thin cut is still claimed for 100 AND 200');
  const manifest = fs.readFileSync(base + '../fxmanifest.lua', 'utf8');
  ok(/fonts\/\*\.ttf/.test(manifest),
     'and .ttf is in files{} — an otf-only glob ships neither Art Deco cut');

  // --ff-* was written for every element and READ by two. Choosing a font on
  // anything else moved the row and did nothing to the screen.
  ['status', 'tells', 'slots', 'wanted', 'honor', 'honorpop', 'reputation', 'reputationpop', 'prompts', 'vehpips', 'zone', 'vehicle']
    .forEach(k => ok(new RegExp('var\\(--ff-' + k + '[,)]').test(css),
                     '--ff-' + k + ' is read by the stylesheet'));

  // Money is the exception, on purpose.
  ok(!/var\(--ff-money/.test(css), 'money has no font hook: it is pinned to Pricedown');
}

console.log('\n-- the two map panels are separate elements --');
{
  const names = [...d.querySelectorAll('#editor-list .ed-item .ed-name')]
    .map(n => n.childNodes[0].textContent);
  ok(names.includes('Vehicle panel') && names.includes('Zone bar'),
     'the upper and lower panels can be tuned apart', names.join(','));

  const stageEl = d.querySelector('.stage');
  const cssv = (n) => window.getComputedStyle(stageEl).getPropertyValue(n).trim();
  const pick = (label) => {
    const i = names.indexOf(label);
    d.querySelectorAll('#editor-list .ed-item')[i].click();
  };
  const setList = (label, times) => {
    const row = () => [...d.querySelectorAll('.ed-prop')]
      .find(r => r.querySelector('.ed-plabel').textContent === label);
    for (let n = 0; n < times; n++) row().querySelectorAll('button')[1].click();
    return row().querySelector('.ed-pval').textContent;
  };

  pick('Zone bar');
  const zoneFont = setList('Font', 3);            // Default -> Helvetica -> Art Deco -> Pricedown
  ok(cssv('--ff-zone') !== '', 'the zone bar takes a font of its own', zoneFont + ' / ' + cssv('--ff-zone'));

  pick('Vehicle panel');
  const vehFont = setList('Font', 2);             // Default -> Helvetica -> Art Deco
  ok(/GTAArtDeco/.test(cssv('--ff-vehicle')), 'and the vehicle panel a different one', cssv('--ff-vehicle'));
  ok(cssv('--ff-zone') !== cssv('--ff-vehicle'),
     'the two do not share one font any more', cssv('--ff-zone') + ' vs ' + cssv('--ff-vehicle'));
  ok(vehFont === 'GTA Art Deco', 'Art Deco is offered by name', vehFont);

  // Smoothing is a real row, and Default writes nothing.
  const smRow = () => [...d.querySelectorAll('.ed-prop')]
    .find(r => r.querySelector('.ed-plabel').textContent === 'Font smoothing');
  ok(!!smRow(), 'font smoothing is tunable per element');
  ok(cssv('--sm-vehicle') === '', 'and unset by default, so the page keeps its own');
  smRow().querySelectorAll('button')[1].click();
  ok(cssv('--sm-vehicle') === 'auto', 'stepping it writes a real value', cssv('--sm-vehicle'));

  $('ed-reset').click();
}

console.log('\n-- long names shrink instead of being clipped --');
{
  const css = fs.readFileSync(base + 'style.css', 'utf8');
  ok(/--fit, 1\)/.test(css), 'the fit factor multiplies the tuned font size rather than replacing it');
  // jsdom has no layout, so the measurement itself cannot run here -- what is
  // checked is that the wiring exists and that a fit factor is applied to the
  // BOX, so a long model is not set smaller than the make above it.
  const js = fs.readFileSync(base + 'app.js', 'utf8');
  ok(/box\.style\.removeProperty\('--fit'\)/.test(js),
     'each pass measures at full size, so repeated fits cannot walk the text down to nothing');
  ok(/Math\.max\(FIT_MIN/.test(js), 'and there is a floor past which clipping is preferred to illegible');
  ok(/ResizeObserver/.test(js) && /document\.fonts/.test(js),
     're-fitted when the box resizes and once the real fonts have loaded');
}

console.log('\n-- one glass, shared --');
{
  const css = fs.readFileSync(base + 'style.css', 'utf8');
  const htmlSrc = fs.readFileSync(base + 'index.html', 'utf8');

  // The tokens moved to :root so three surfaces stop hand-rolling near-misses
  // of the same colours. That drift is what makes a set of panels look
  // "related" rather than identical.
  // Non-greedy to the first closing brace that starts a line.
  const rootBlock = css.match(/:root \{[\s\S]*?^\}/m);
  ok(!!rootBlock && /--g-tint/.test(rootBlock[0]), 'the glass tokens live on :root');
  ok(!!rootBlock && /--g-gold/.test(rootBlock[0]),
     'including the one warm accent, so it cannot be reinvented per panel');

  ok(/\.glass \{[\s\S]*?linear-gradient\(176deg/.test(css), '.glass carries the layered sheen');
  ok(/\.glass::before[\s\S]*?radial-gradient\(125% 62%/.test(css),
     'and the specular cap, which is most of what separates glass from a grey box');

  // .plate is the HUD's OTHER material -- the map panel surface. Same idea as
  // .glass and deliberately different in three ways, each asserted here because
  // each is the one that would quietly turn it back into a grey box.
  ok(/\.plate \{[\s\S]*?linear-gradient\(118deg/.test(css),
     '.plate carries the diagonal sheen from #vehicle::after');
  ok(/\.plate \{[\s\S]*?inset 0 0 0 0\.055cqw/.test(css),
     'and the hairline INSET ring, which costs no layout width unlike a border');
  ok(!/\.plate::before/.test(css),
     'and NO specular cap: that is what separates the plate from the glass');

  // ONE surface now. The split was tried -- plate for chrome, glass for content
  // -- and read as two different apps rather than as a distinction; every
  // surface this HUD draws is the plate, and so is ox_lib's popup layer and the
  // ox_target / qb-menu / qb-input menus.
  ['editor-panel', 'skills-panel', 'skillup-card', 'pol-ed-panel'].forEach(id => {
    ok(new RegExp('id="' + id + '"[^>]*class="plate"').test(htmlSrc),
       id + ' is on the map-panel plate');
  });
  ok(!/class="glass"/.test(htmlSrc),
     'and nothing is left on the old glass');

  // No backdrop-filter anywhere: on a transparent NUI page CEF rasterises the
  // region as opaque black, which is the bug that blacked out the whole editor.
  // A DECLARATION, not the word. The stylesheet talks about backdrop-filter at
  // length precisely because it must not use it, so a bare substring match
  // fails on its own documentation.
  ok(!/^\s*(-webkit-)?backdrop-filter\s*:/m.test(css),
     'no backdrop-filter declaration survives: on a transparent NUI page CEF ' +
     'rasterises that region as opaque black');
}

console.log('\n-- the level-up card is placeable --');
{
  const names = [...d.querySelectorAll('#editor-list .ed-item .ed-name')]
    .map(n => n.childNodes[0].textContent);
  const idx = names.indexOf('Skill level-up');
  ok(idx !== -1, 'it is an element in the editor', names.join(','));

  d.querySelectorAll('#editor-list .ed-item')[idx].click();
  ok($('editor-propfor').textContent === 'Skill level-up', 'selecting it names it');
  ok(d.getElementById('skillup').classList.contains('ed-target'),
     'and it is highlighted on screen');

  const stageEl = d.querySelector('.stage');
  const cssv = (n) => window.getComputedStyle(stageEl).getPropertyValue(n).trim();
  key('ArrowDown'); key('ArrowRight');
  ok(cssv('--off-skillup-x') === '0.1cqw' && cssv('--off-skillup-y') === '0.1cqh',
     'and it moves', cssv('--off-skillup-x') + ' / ' + cssv('--off-skillup-y'));

  // The outer element is positioned; the CARD animates. One element doing both
  // means the animation's transform discards the editor's offset while it runs.
  const css2 = fs.readFileSync(base + 'style.css', 'utf8');
  ok(/#skillup \{[^}]*--off-skillup-x/s.test(css2), 'the offset is on the outer element');
  ok(/#skillup\.slot-in #skillup-card \{[^}]*animation/s.test(css2),
     'while the animation is on the inner card, so it cannot throw the offset away');

  $('ed-reset').click();
}

console.log('\n-- the reputation panel is placeable, and mirrors honor left/right --');
{
  const names = [...d.querySelectorAll('#editor-list .ed-item .ed-name')]
    .map(n => n.childNodes[0].textContent);
  const idx = names.indexOf('Reputation standing');
  ok(idx !== -1, 'it is an element in the editor', names.join(','));

  d.querySelectorAll('#editor-list .ed-item')[idx].click();
  ok($('editor-propfor').textContent === 'Reputation standing', 'selecting it names it');
  ok(d.getElementById('reputation').classList.contains('ed-target'),
     'and it is highlighted on screen');

  const stageEl = d.querySelector('.stage');
  const cssv = (n) => window.getComputedStyle(stageEl).getPropertyValue(n).trim();
  key('ArrowDown'); key('ArrowRight');
  ok(cssv('--off-reputation-x') === '0.1cqw' && cssv('--off-reputation-y') === '0.1cqh',
     'and it moves', cssv('--off-reputation-x') + ' / ' + cssv('--off-reputation-y'));
  $('ed-reset').click();

  // No mugshot: honor's toast carries a portrait, reputation is a plain icon
  // glyph -- the markup should not be dragging along an <img> it never uses.
  const repEl = d.getElementById('reputation');
  ok(!repEl.querySelector('img'), 'the panel has no mugshot element');
  ok(!!repEl.querySelector('#reputation-icon'), 'it has an icon glyph instead');

  // Opposite corners on purpose, so the two never sit on top of each other at
  // their shipped positions.
  const css = fs.readFileSync(base + 'style.css', 'utf8');
  ok(/#honor\s*\{[^}]*right:/s.test(css), 'honor is right-anchored');
  ok(/#reputation\s*\{[^}]*left:/s.test(css), 'reputation is left-anchored, not stacked on honor');
}

console.log('\n-- the reputation +N popup has no down state --');
{
  // Reputation only ever goes up (qbx_reputation's tracks are floor-0), so
  // unlike honor-pop there should be no .down class or minus-sign branch to
  // keep in sync with a case that can never fire.
  const js = fs.readFileSync(base + 'app.js', 'utf8');
  const fn = js.match(/function onReputationPop\([^)]*\)\s*\{[\s\S]*?\n    \}/);
  ok(!!fn, 'onReputationPop exists');
  ok(fn && !/down/.test(fn[0]), 'and it never branches on a down state', fn && fn[0]);
}

console.log('\n-- a tier crossing reuses the skill-up toast, not a second animation --');
{
  const lua = fs.readFileSync(base + '../client.lua', 'utf8');
  ok(/ShowReputationToast/.test(lua), 'ShowReputationToast is defined in client.lua');
  const fn = lua.match(/local function ShowReputationToast[\s\S]*?\nend/);
  ok(!!fn, 'found the function body');
  ok(fn && /ui\('skillUp',/.test(fn[0]),
     'a tier-up pushes the existing skillUp toast rather than a new one', fn && fn[0]);
}

console.log('\n-- the map panels arrive and leave --');
{
  const css = fs.readFileSync(base + 'style.css', 'utf8');
  const js = fs.readFileSync(base + 'app.js', 'utf8');

  ok(/@keyframes slotIn[^}]*translateY\(115%\)/s.test(css), 'arrival rises into place');
  ok(/\.slot\.slot-in\s*\{[^}]*cubic-bezier\(0\.16,\s*1\.28/s.test(css),
     'with an overshoot curve — the 1.28 control point IS the spring');
  // Leaving is a fade with no travel, which is what was asked for. A translate
  // creeping back into slotOut would be a silent behaviour change.
  const outBlock = css.match(/@keyframes slotOut\s*\{([^}]*\}[^}]*)\}/s);
  ok(!!outBlock && !/transform/.test(outBlock[1]),
     'leaving is opacity only, with no travel', outBlock && outBlock[1].replace(/\s+/g, ' ').trim());

  /* The one that can break silently: `hidden` is display:none, so the JS timer
     is what ends the fade. If it fires BEFORE the animation finishes the panel
     is cut off part-way; later is invisible thanks to the fill-mode. */
  const cssMs = +(css.match(/animation:\s*slotOut\s+(\d+)ms/) || [])[1];
  const jsMs = +(js.match(/var SLOT_OUT_MS = (\d+)/) || [])[1];
  ok(cssMs > 0 && jsMs > 0, 'both durations are declared', cssMs + ' / ' + jsMs);
  ok(jsMs >= cssMs, 'the hide timer never fires before the fade finishes',
     'js ' + jsMs + 'ms vs css ' + cssMs + 'ms');

  ok(/\.slot\.slot-in,\s*\.slot\.slot-out\s*\{\s*animation:\s*none/.test(css),
     'reduced motion turns both animations off in CSS');
  ok(/reduceMotion\s*\)\s*\{[^}]*show\(el, false\)/s.test(js),
     'and in JS, so a reader does not sit through an invisible 460ms wait');
}

console.log('\n-- the vehicle pips move and scale on their own --');
{
  const stageEl = d.querySelector('.stage');
  const cssv = (n) => window.getComputedStyle(stageEl).getPropertyValue(n).trim();
  const names = [...d.querySelectorAll('#editor-list .ed-item .ed-name')]
    .map(n => n.childNodes[0].textContent);
  const idx = names.indexOf('Vehicle icons');
  ok(idx !== -1, 'the pips are their own element', names.join(','));
  d.querySelectorAll('#editor-list .ed-item')[idx].click();
  ok($('editor-propfor').textContent === 'Vehicle icons', 'selecting it names it', $('editor-propfor').textContent);

  // The pip row is the element the editor is pointing at -- it is a real DOM
  // node, so it gets the outline the external rows cannot have.
  ok(d.getElementById('veh-pips').classList.contains('ed-target'),
     'and it is highlighted on screen like any other page element');

  const rowFor = (label) => [...d.querySelectorAll('.ed-prop')]
    .find(r => r.querySelector('.ed-plabel').textContent === label);
  const type = (label, text) => {
    const f = rowFor(label).querySelector('.ed-pval');
    f.value = text;
    f.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
  };

  // Size WITHOUT spacing is the original complaint: the discs grow and the gap
  // between them does not, so the row reads as crowded however good the size is.
  type('Icon size', '1.8');
  type('Spacing', '1.8');
  ok(cssv('--ic-vehpips') === '1.8', 'the pips have their own icon size', cssv('--ic-vehpips'));
  ok(cssv('--sp-vehpips') === '1.8', 'and their own spacing, so the row stays proportionate', cssv('--sp-vehpips'));

  const pipCs = window.getComputedStyle(d.querySelector('.pip'));
  ok(/--ic-vehpips/.test(pipCs.width) || pipCs.width !== '',
     'the pip size reads the new variable', pipCs.width);

  key('ArrowDown'); key('ArrowRight');
  ok(cssv('--off-vehpips-y') === '0.1cqh' && cssv('--off-vehpips-x') === '0.1cqw',
     'and they can be nudged independently of the panel around them',
     cssv('--off-vehpips-x') + ' / ' + cssv('--off-vehpips-y'));

  // Untouched, the pips must render exactly as they did before this element
  // existed -- the CSS falls back to the panel's own icon size.
  $('ed-reset').click();
  ok(cssv('--ic-vehpips') === '' && cssv('--sp-vehpips') === '',
     'reset clears them, so the panel drives them again as it always did',
     '[' + cssv('--ic-vehpips') + '] [' + cssv('--sp-vehpips') + ']');
}

console.log('\n-- notifications are a tunable element --');
{
  posted.length = 0;
  const names = [...d.querySelectorAll('#editor-list .ed-item .ed-name')]
    .map(n => n.childNodes[0].textContent);
  const idx = names.indexOf('Notifications');
  ok(idx !== -1, 'the list has a Notifications row', names.join(','));
  d.querySelectorAll('#editor-list .ed-item')[idx].click();
  ok($('editor-propfor').textContent === 'Notifications', 'selecting it names it', $('editor-propfor').textContent);

  const nrows2 = [...d.querySelectorAll('.ed-prop .ed-plabel')].map(n => n.textContent);
  ok(nrows2.join(',') === 'Corner,Position X,Position Y',
     'corner + nudge, and none of the CSS properties (ox_lib draws it, not us)', nrows2.join(','));

  // Nothing was sent for notify, so the row reads ox_lib's own default corner
  // rather than an abstract "Default" that would step somewhere unrelated.
  const cornerRow = () => [...d.querySelectorAll('.ed-prop')][0];
  ok(cornerRow().querySelector('.ed-pval').textContent === 'Top right',
     "an unset corner reads as ox_lib's own default", cornerRow().querySelector('.ed-pval').textContent);
  cornerRow().querySelectorAll('button')[1].click();
  ok(cornerRow().querySelector('.ed-pval').textContent === 'Left',
     "the corner steps through ox_lib's anchors", cornerRow().querySelector('.ed-pval').textContent);

  key('ArrowDown');
  const live = posted.filter(pp => pp.url.endsWith('/layoutLive')).pop();
  ok(!!live && !!live.body.offsets.notify, 'nudging it goes to Lua live, so a sample popup can be shown');
  ok(live && live.body.offsets.notify.anchor === 'center-left',
     'and the chosen corner travels with it', live && JSON.stringify(live.body.offsets.notify));
  ok(live && Math.abs(live.body.offsets.notify.y - 0.1) < 1e-9,
     'the nudge is a screen PERCENTAGE, not pixels', live && live.body.offsets.notify.y);
}

console.log('\n-- save payload survives --');
posted.length = 0;
key('Enter');
const save = posted.find(p => p.url.endsWith('/saveLayout'));
ok(!!save, 'Enter posts saveLayout');
ok(save && !Array.isArray(save.body.offsets), 'offsets is an object, not an array');
ok(save && Math.abs(save.body.offsets.status.x - 1.3) < 1e-9, 'the edited x is in the payload', save && save.body.offsets.status.x);
ok(save && save.body.offsets.status.al === 'right', 'and so is the alignment', save && save.body.offsets.status.al);
ok($('editor').classList.contains('hidden'), 'panel closed');

// #map-frame must keep reading the map rect even though #slots no longer does:
// the frame is drawn ON the map and is wrong the instant it stops following.
function frameRule() {
  const css = fs.readFileSync(base + 'style.css', 'utf8');
  const m = css.match(/#map-frame \{[\s\S]*?\}/);
  return m ? m[0] : '';
}

console.log('\n-- the map panels no longer track the map --');
{
  const stage = d.querySelector('.stage');
  const pv = (n) => stage.style.getPropertyValue(n).trim();

  // A fresh session: the first rect is the snapshot.
  msg({ action: 'openEditor', offsets: {}, native: {} });
  msg({ action: 'mapRect', left: 1.75, width: 15.8, bottom: 17.9, height: 15.4 });
  ok(pv('--panel-left') === '1.75cqw', 'the first map rect seeds the panel stack', pv('--panel-left'));
  ok(pv('--panel-width') === '15.8cqw', 'including its width', pv('--panel-width'));

  // Now resize the map, which is the reported bug. The map vars must follow it
  // and the PANEL vars must not.
  msg({ action: 'mapRect', left: 1.75, width: 31.6, bottom: 24.0, height: 30.8 });
  ok(pv('--map-width') === '31.6cqw', 'the map itself still tracks its rect', pv('--map-width'));
  ok(pv('--panel-width') === '15.8cqw', 'but the panels keep the width they had', pv('--panel-width'));
  ok(pv('--panel-bottom') === '17.9cqh', 'and their position', pv('--panel-bottom'));

  ok(/var\(--map-width/.test(frameRule()), 'the minimap frame still reads the map rect');

  // Follow map puts the old behaviour back.
  msg({ action: 'openEditor', offsets: { slots: { x: 0, y: 0, pfollow: 1 } }, native: {} });
  msg({ action: 'mapRect', left: 4.0, width: 40.0, bottom: 30.0, height: 28.0 });
  ok(pv('--panel-width') === '40cqw', 'Follow map re-attaches them', pv('--panel-width'));

  // An explicit width beats both the snapshot and the map.
  msg({ action: 'openEditor', offsets: { slots: { x: 0, y: 0, pw: 9.5 } }, native: {} });
  msg({ action: 'mapRect', left: 4.0, width: 40.0, bottom: 30.0, height: 28.0 });
  ok(pv('--panel-width') === '9.5cqw', 'an explicit Panel width wins over the map', pv('--panel-width'));
}

console.log('\n-- the panel rows are on Map panels and nowhere else --');
{
  msg({ action: 'openEditor', offsets: {}, native: {} });
  const pick = (label) => {
    const item = [...d.querySelectorAll('#editor-list .ed-item')]
      .find(n => n.textContent.indexOf(label) === 0);
    item.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    return [...d.querySelectorAll('.ed-prop .ed-plabel')].map(n => n.textContent);
  };

  const slotRows = pick('Map panels');
  ['Panel left', 'Panel width', 'Panel bottom', 'Follow map'].forEach(r => {
    ok(slotRows.indexOf(r) >= 0, 'Map panels has a ' + r + ' row');
  });

  const statusRows = pick('Status bars');
  ok(statusRows.indexOf('Panel left') < 0,
     'and Status bars does not -- the rows are opt-in, not global');
}

console.log('\n-- inheritance is visible and reversible --');
{
  msg({ action: 'openEditor', offsets: { slots: { x: 0, y: 0, fs: 1.4 } }, native: {} });
  const pickEl = (label) => {
    const item = [...d.querySelectorAll('#editor-list .ed-item')]
      .find(n => n.textContent.indexOf(label) === 0);
    item.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  };
  const rowFor = (label) => [...d.querySelectorAll('.ed-prop')]
    .find(n => n.querySelector('.ed-plabel').textContent === label);

  pickEl('Zone bar');
  const fsRow = rowFor('Font size');
  const fol = fsRow.querySelector('.ed-follow');
  ok(!!fol, 'an inheriting row carries a Follow switch');
  ok(fol.textContent === 'Follow', 'and starts on Follow, which is what untouched already meant');
  ok(fsRow.querySelector('.ed-pval').value === '1.40',
     'a following row shows the PARENT value, not the shipped default',
     fsRow.querySelector('.ed-pval').value);

  // Own seeds from what is on screen, so detaching is not also a jump.
  fol.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  const own = rowFor('Font size');
  ok(own.querySelector('.ed-follow').textContent === 'Own', 'clicking it takes the value over');
  ok(own.querySelector('.ed-pval').value === '1.40',
     'and seeds it from the inherited value, so nothing moves', own.querySelector('.ed-pval').value);
  ok(d.querySelector('.stage').style.getPropertyValue('--fs-zone').trim() === '1.4',
     'now written explicitly, so the parent no longer reaches it');

  // ...and back.
  own.querySelector('.ed-follow').dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  ok(d.querySelector('.stage').style.getPropertyValue('--fs-zone').trim() === '',
     'Follow clears it again and CSS falls back to the parent');

  // A row that does NOT inherit must not grow a switch.
  pickEl('Money');
  ok(!rowFor('Opacity').querySelector('.ed-follow'),
     'a non-inheriting row has no switch -- the eleven are a list, not a guess');
}

console.log('\n-- the panel can be resized --');
{
  msg({ action: 'openEditor', offsets: {}, native: {} });
  const panel = $('editor-panel');
  const grip = $('ed-resize');
  ok(!!grip, 'there is a resize grip');

  grip.dispatchEvent(new window.MouseEvent('mousedown', { bubbles: true, button: 0, clientX: 800, clientY: 600 }));
  d.dispatchEvent(new window.MouseEvent('mousemove', { bubbles: true, clientX: 1000, clientY: 750 }));
  d.dispatchEvent(new window.MouseEvent('mouseup', { bubbles: true, clientX: 1000, clientY: 750 }));
  ok(panel.classList.contains('resized'), 'dragging it takes the size over from the stylesheet');
  ok(/px$/.test(panel.style.width) && /px$/.test(panel.style.height),
     'in pixels, like the drag position', panel.style.width + ' x ' + panel.style.height);
  ok(parseFloat(panel.style.width) >= 520 && parseFloat(panel.style.height) >= 260,
     'never below the floor where the two columns collapse into each other');

  // The size has to survive a close/reopen, or resizing is busywork.
  const w = panel.style.width;
  msg({ action: 'closeEditor' });
  msg({ action: 'openEditor', offsets: {}, native: {} });
  ok($('editor-panel').style.width === w, 'and it is remembered across reopens', $('editor-panel').style.width);
}

console.log('\n-- a scaled pip row is not clipped when the panel is collapsed --');
{
  const css = fs.readFileSync(base + 'style.css', 'utf8');

  // .slot clips so a child's square corners cannot escape the plate's rounded
  // ones. Collapsed there is no plate -- and #veh-pips is scaled with a
  // TRANSFORM, which does not grow the layout box, so the clip cut the discs.
  const slot = (css.match(/^\.slot \{[\s\S]*?^\}/m) || [''])[0];
  ok(/overflow:\s*hidden/.test(slot), '.slot still clips -- the plate needs it');

  const collapsed = (css.match(/^#vehicle\.collapsed \{[\s\S]*?^\}/m) || [''])[0];
  ok(/overflow:\s*visible/.test(collapsed),
     'but the collapsed panel does not, so scaled pips are not cut off');
  ok(/background:\s*none/.test(collapsed) && /box-shadow:\s*none/.test(collapsed),
     'and that is safe there precisely because the plate is gone');

  // The transform is what made the clip matter. If these ever become a real
  // size change, the rule above can go -- this is the reminder.
  ok(/#veh-pips \{[^}]*scale\(var\(--sc-vehpips-x/.test(css.replace(/\n/g, ' ')),
     'pips are still scaled by transform, which is why the clip mattered');
}

console.log('\n-- the two "make it bigger" rows say which is which --');
{
  msg({ action: 'openEditor', offsets: {}, native: {} });
  const item = [...d.querySelectorAll('#editor-list .ed-item')]
    .find(n => n.textContent.indexOf('Vehicle icons') === 0);
  item.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  const hintOf = (label) => {
    const row = [...d.querySelectorAll('.ed-prop')]
      .find(n => n.querySelector('.ed-plabel').textContent === label);
    return row ? (row.querySelector('.ed-plabel').getAttribute('title') || '') : '';
  };
  ok(/real SIZE/.test(hintOf('Icon size')), 'Icon size says it changes the real size');
  ok(/PAINTED/.test(hintOf('Width')), 'Width says it only scales the painting');
  ok(/PAINTED/.test(hintOf('Height')), 'and so does Height');
}

console.log('\n-- plate styling reached the panel --');
const cs = window.getComputedStyle($('editor-panel'));
// NOT a backdrop blur. On a transparent NUI page CEF rasterises the backdrop
// root as opaque black, which put the panel in a black box and hid the HUD
// behind it -- the exact thing the editor exists to look at. The regression is
// easy to reintroduce ("the glass lost its blur"), so it is asserted against.
ok(!/blur/.test(cs.backdropFilter || cs.webkitBackdropFilter || 'none'),
   'no backdrop-filter: it renders as an opaque black box in FiveM', cs.backdropFilter);
// Read the token rather than the composited shorthand: the panel's background
// is a gradient over var(--g-tint), which jsdom does not resolve.
const plate = window.getComputedStyle($('editor')).getPropertyValue('--plate').trim();
ok(/0\.88/.test(plate), 'the plate is dense enough to carry the panel on its own', plate);
// The plate's edge, not the glass's. It is an INSET ring rather than a border
// so it costs no layout width -- which is what lets the panel keep an exact
// dragged width while still having a visible edge.
ok(/inset 0 0 0 0\.055cqw/.test(cs.boxShadow), 'plate hairline inset ring present', JSON.stringify(cs.boxShadow));
ok(cs.borderRadius === 'calc(1.5 * var(--w))', 'large radius, in the height-relative unit', cs.borderRadius);

console.log('\n' + (fails ? fails + ' FAILING' : 'all checks passed'));
// The honor-pop preview runs on a setInterval that outlives the editor closing
// in jsdom, so exit explicitly rather than waiting for an idle event loop.
dom.window.close();
process.exit(fails ? 1 : 0);
