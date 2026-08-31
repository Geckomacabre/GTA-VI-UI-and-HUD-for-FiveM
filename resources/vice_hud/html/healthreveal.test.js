/* Health used to show continuously whenever it was below 100 -- in practice,
 * almost always, since a scratch sits there for minutes with nothing to clear
 * it (unlike stamina/focus, which mostly return to full within a second or
 * two). This is a regression test for the fix: the row now reveals on an
 * actual CHANGE (a hit or a heal), holds briefly, then fades -- the same
 * "a STATE is not a LEVEL" correction already applied to the vehicle lock
 * pip -- plus while the weapon/item wheel is held open (Tab), and still
 * unconditionally while a hunger/thirst cap is in effect (a standing
 * warning, not a one-off event).
 *
 *   node html/healthreveal.test.js
 *
 * Not shipped to clients -- not in fxmanifest's files{}.
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
const shown = () => !d.getElementById('s-health').classList.contains('hidden');

// The FIRST payload establishes a baseline, not a "change" -- a fresh page
// load at partial health must not immediately flash the row.
msg({ action: 'status', health: 80, focus: 100, stamina: 100 });
ok(!shown(), 'a first reading below full is NOT treated as a change (no flash on load)');

// Sitting at the same value, tick after tick, is not a change either -- this
// is the exact bug being fixed: "below full" alone used to keep it up.
msg({ action: 'status', health: 80, focus: 100, stamina: 100 });
msg({ action: 'status', health: 80, focus: 100, stamina: 100 });
ok(!shown(), 'unchanged health at 80 across multiple ticks stays hidden');

// A real hit reveals it.
msg({ action: 'status', health: 62, focus: 100, stamina: 100 });
ok(shown(), 'a change in health (a hit) reveals the row');

// And it holds for a while rather than hiding on the very next unchanged tick
// -- a hit has to actually be readable, not blink for one frame.
msg({ action: 'status', health: 62, focus: 100, stamina: 100 });
ok(shown(), 'stays up on the next tick even though health did not move again');

// client.lua pushes a fresh 'status' every 250ms regardless of whether
// anything changed, which is what actually notices the flash window expiring
// and lets the shared hide-hold take over -- simulate that here rather than
// going quiet, or nothing re-evaluates the row between now and the assertion.
var pollHealth = 62;
var poller = setInterval(function () {
  msg({ action: 'status', health: pollHealth, focus: 100, stamina: 100 });
}, 250);

setTimeout(function () {
  ok(!shown(), 'and fades once the flash window (plus the shared hide-hold) has passed');

  // A heal (value moving UP) counts as a change too, not just damage. Sent
  // explicitly rather than waiting on the poller, so this assertion does not
  // race the next scheduled tick.
  pollHealth = 90;
  msg({ action: 'status', health: pollHealth, focus: 100, stamina: 100 });
  ok(shown(), 'healing also reveals the row, not just taking damage');

  setTimeout(function () {
    ok(!shown(), 'fades again once the window passes');
    clearInterval(poller);

    // The weapon/item wheel: shows unconditionally while held, independent of
    // whether health has changed at all.
    msg({ action: 'status', health: 90, focus: 100, stamina: 100, wheel: true });
    ok(shown(), 'the row shows while the wheel is held, with no health change involved');
    msg({ action: 'status', health: 90, focus: 100, stamina: 100, wheel: false });
    // Releasing the wheel with nothing else pending goes through the shared
    // hide-hold, same as everything else -- not asserted synchronously here.

    // The hunger/thirst cap is a STANDING condition, not gated on a recent
    // change -- this is pre-existing behaviour and must survive the rewrite.
    msg({ action: 'status', health: 100, focus: 100, stamina: 100, cap: 70, capCause: 'hunger' });
    ok(shown(), 'a hunger/thirst cap still shows the row even at full, unchanged health');

    // ROUND 3, reported live: "hunger 100, thirst 100, capped at 62% by
    // health" -- the FLAT regen ceiling (Config.Needs.regenCeilingPct) shares
    // the same `cap`/`capCause` fields as the hunger/thirst warning, but it is
    // a completely different situation: it is only ever active while health
    // is ALREADY below it, i.e. ordinary unhealed damage, not a forward
    // warning at full health. Force-showing it unconditionally meant the row
    // stayed up continuously any time health sat under 62% for any reason --
    // the exact "always visible" bug this whole feature was fixing, just
    // reached through the cap instead of the raw health value. It must NOT
    // force the row on its own.
    msg({ action: 'status', health: 90, focus: 100, stamina: 100 });
    setTimeout(function () {
      // health UNCHANGED (90 -> 90) from the message right above -- only the
      // cap is new. Sending this alone leaves the shared hide-hold's own
      // 1200ms timer still to run, so the assertion has to wait it out too,
      // not read the DOM synchronously right after posting.
      msg({ action: 'status', health: 90, focus: 100, stamina: 100, cap: 62, capCause: 'health' });
      setTimeout(function () {
        ok(!shown(),
           'the flat regen-ceiling cap (capCause "health") does NOT force the row ' +
           'on its own -- only hunger/thirst does');

        console.log(fails ? '\n' + fails + ' check(s) failed' : '\nall checks passed');
        process.exit(fails ? 1 : 0);
      }, 1500);
    }, 4400);
  }, 4400);
}, 4400);
