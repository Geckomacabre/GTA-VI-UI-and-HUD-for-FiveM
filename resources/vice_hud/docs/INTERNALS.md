# vice_hud internals

> The long version. [`README.md`](../README.md) at the repo root is the place to
> start; this is what is behind it — why each piece is built the way it is, and
> the traps that already bit once.

A GTA6-styled HUD for Qbox. Draws its own status bars, wanted stars, weapon and
ammo readout, money, zone bar, vehicle panel, honor standing, action prompts,
directional police glow and exhaustion effects, and hides only the native HUD
components it actually replaces.

**Dependency:** `ox_lib`. Weapon icons are read from `ox_inventory` over `nui://`
if it is present; if it is not, the icon is simply omitted.

## Layout

| File | What is in it |
| --- | --- |
| `config.lua` | Every tunable value, with the reasoning next to it |
| `client.lua` | Gathers game state, pushes plain data to the NUI, owns the commands |
| `client_vitals.lua` | Focus, stamina, oxygen, hunger/thirst, fatigue. Publishes `ViceVitals` |
| `client_overlays.lua` | Crosshair, kill mark, lap timer, world actions, lockpick, interact menu |
| `weapons.lua` | Weapon hash -> `ox_inventory` icon path |
| `html/` | The NUI page. No framework and no build step — what is on disk is what runs |
| `html/makes.js` | Manufacturer table: a vehicle's make -> its badge. **Generated** |
| `html/logos/` | The manufacturer marks themselves, 51 of them. **Generated** |
| `tools/` | Build and test tooling. Not in `files{}`, so clients never see it |
| `stream/vice_minimap.ytd` | The rounded radar mask. On by default — GTA's own mask has square corners |

**Why the client is three files.** A Lua chunk may declare at most **200
top-level locals**, and going over is a *parse* error — the file does not load
at all, which takes the whole HUD down rather than one feature, and the message
only appears in the F8 client console. `client.lua` reached 192. Each `.lua`
file is its own chunk with its own budget, so the two least-entangled
subsystems moved out on 2026-08-28 (moved verbatim, not rewritten), leaving
client.lua at 143.

Nothing reaches across those boundaries except:

- `ViceVitals` — seven functions published at the bottom of `client_vitals.lua`
  and called by the main status loop. `focusMeter`/`focusActive` are functions
  rather than values because a copied number would go stale crossing the file.
- `ui()` — four lines, duplicated per file, exactly as `client_skills.lua`
  already did it. A global would have been more ceremony than the thing itself.
- `client_overlays.lua` publishes **nothing**: it is driven entirely from
  outside through exports and commands.

`tools/split.test.js` is the standing guard — it loads every client chunk in
manifest order and fails if any is near the cap or if `client.lua` calls
something `ViceVitals` does not publish.

Every numeric layout decision lives in the CSS, so changing how the HUD looks
never means touching Lua.

Open `html/index.html` in a browser to see the layout with representative data —
`app.js` detects that it is outside FiveM and populates itself.

## Exports

```lua
exports.vice_hud:ShowActionPrompt(id, label, key)   -- key: a string, or a control id
exports.vice_hud:HideActionPrompt(id)
exports.vice_hud:ShowHonorToast(mugshot, honor, emoji, reason)
exports.vice_hud:ShowHonorChange(delta, mugshot)
exports.vice_hud:SetHonorStanding(honor)            -- seeds the value, draws nothing
exports.vice_hud:SetHudVisible(visible)
exports.vice_hud:SetHudOffsetX(pixels)
exports.vice_hud:GetHudOffset(element)              -- returns x, y
```

Prompts are cleaned up automatically when the resource that registered them
stops, so a crashed script cannot strand one on screen. Give prompt ids the
`yourresource:something` form for that to work.

### Honor: two panels, one push

`ShowHonorToast` feeds both the corner **standing** panel and the centre-screen **change**
indicator, and they behave differently:

| | corner panel | centre indicator |
|---|---|---|
| shows | where honor stands, and why it moved | that honor just moved |
| lifetime | `Config.Honor.holdMs` (6s) | ~2.2s |
| face | tier for the current value | direction of the change |
| driven by | `honor` | a non-zero `delta` |

Neither is permanent: honor is a readout you get when something happens, not furniture
parked in the corner all session. `holdMs = 0` keeps the panel up until something hides it.

`delta` is worked out here, against the last value seen — callers send the new value, not
the difference. Use **`SetHonorStanding`** to tell the HUD the current value without
drawing anything (at spawn, or after this resource restarts); without it the first real
change of a session is measured against nothing and draws no indicator.

**Pass `emoji` as nil** unless you specifically want to override the standing face; it is
otherwise derived from `Config.Honor.angelAt` / `devilAt`. Passing the direction face here
makes the corner panel disagree with the player's actual tier.

`Config.Honor.showValue` (default on) adds the numeric value and the `reason` to the
panel. Set it false for the reference treatment, which is the mugshot and its face and
nothing else.

## Placing the HUD

`/movehud` opens the editor. Pick an element on the left, tune it on the right.

| Key | Does |
| --- | --- |
| arrows | move the element |
| `Ctrl`+arrows | resize — left/right width, up/down height |
| `[` `]` | choose which property `+`/`-` acts on |
| `+` `-` | change the selected property (starts on Font size) |
| `Shift` | bigger steps |
| `Tab` | next element |
| `H` | collapse the panel to its title bar |
| `Space` | hold to see straight through the panel |
| drag the title bar | move the panel; where you leave it is remembered |
| drag the bottom-right corner | resize the panel; double-click the corner to reset it |
| `Enter` / `Esc` | save / cancel |

Every property also has `-` and `+` buttons, since the mouse works while the
editor holds NUI focus.

The editor deliberately draws **no scrim**. It used to lay a graded wash with a
blur over the whole screen, and because the game — and the engine-drawn minimap
— is composited *underneath* this page, that wash blacked out the very thing the
editor exists to position. The map went dark, the HUD went murky, and you were
tuning from memory. A layout tool has to leave the layout visible; `H`, `Space`
and dragging are there for when the panel is still over the piece you want.

The minimap is also forced on for as long as the editor is open, even for
players who keep it hidden on foot — the Minimap rows move and resize the real
map, and you cannot aim a map you cannot see.

Tunable per CSS element: **font size, font family, font weight, letter spacing,
text alignment, width, height, opacity, corner radius, spacing**, plus position.

**Spacing** multiplies the gap between an element's own children. Size alone
could never produce a proportionate stack — scale a row of icons up and the gap
between them stays where it was, so the row reads as crowded however good the
icon size is. That is what it is for.

The two map panels **arrive** with a springy rise and **leave** with a plain
fade — no travel on the way out, deliberately: the panel has said what it had to
say and should stop competing for attention, and sliding it away is a second
piece of motion for an event that no longer matters.

The fade has to be staged rather than toggled, because `hidden` is
`display: none` and that cancels an animation outright instead of playing it.
`SLOT_OUT_MS` in `app.js` is what swaps the element out afterwards and it is
deliberately **longer** than the CSS duration: the fill-mode holds opacity at 0
once the animation ends, so hiding late is invisible while hiding early cuts the
fade off mid-way. `editor.test.js` asserts that inequality, because the two
numbers live in different files and nothing else would notice them drifting.

The **Vehicle icons** row is the lock / engine / fuel pips inside the vehicle
panel, split out as their own element for the same reason: scaling them from the
panel grew the three discs and left the gap alone. Left untouched they still
follow the panel's own icon size, so an existing layout renders unchanged; the
moment you set them, they take over.

**Every number can be typed.** Click the value between the `−` and the `+`, type
a figure, press Enter. Stepping is for finding a value and hopeless for reaching
one — at 0.05 a click, a Width of 12 is 220 clicks away — and Escape puts the
old value back if you change your mind.

The min/max on each row are **guard rails, not opinions**. They used to be taste
judgements, and a taste judgement in a tuning tool is just a wall: Width stopped
at 3.0, which is not enough to fit the minimap frame onto a map that has itself
been scaled up, and nothing inside the editor could get past it. What is left is
the point where an element stops existing in a recoverable way — a scale of zero
collapses it, an offset of five screens puts it somewhere you cannot see to drag
it back. The one real exception is **Opacity**, capped at 1 because CSS caps it
at 1; a larger number would be a control that silently does nothing.

**Text alignment** is one control writing two CSS properties: a `text-align`
value for the copy, and the matching flex alignment for the box that copy sits
in. Both are needed — `text-align` alone moves glyphs inside a box that is still
hard against one edge, and the flex value alone does nothing to text that wraps.
`Default` writes neither, so an untouched element renders exactly as designed.

The **Minimap** rows are different, because the engine draws the map and CSS
cannot touch it. Selecting one swaps the panel for the engine's own values:

| | |
| --- | --- |
| Crop top / bottom / left / right | trim dead space off the visible window |
| Blip X / Blip Y | move the map plane inside its window, to centre the player arrow |
| Map width / height | scale the map, its mask and its blur **together** |
| Plane width / height | stretch the map plane **only**, leaving the window put |
| Blur X / Y / width / height | the `minimap_blur` component, which can be what really sets the map's drawn size |
| Radar zoom | how far the radar is zoomed in; 0 leaves GTA's own zoom alone |
| North marker | GTA's north indicator on the map edge — **vanilla shows it** |
| Player arrow | scale of your own blip; 0 leaves GTA's own alone |
| Map X / Map Y | nudge it in pixels |
| Panel left / width / bottom / height | the published MAP rect — the frame and the centre cross sit on it. The two panels have their own rows now, under **Map panels**; see below |

### The map panels do not follow the map

They used to. `#slots` read `--map-left` / `--map-width` / `--map-bottom`
straight off the published map rect, so the zone bar and the vehicle panel
*were* the minimap's left edge and width by construction. That is a good default
and a bad rule: scaling the map in `/movehud` dragged both panels along with it
and resized them, and the only way to hold them still was to override the whole
map rect — which also moves the frame.

The stack now reads its own `--panel-left` / `--panel-width` / `--panel-bottom`,
falling back to the map's only when those are unset. `applyPanelRect` in
`app.js` decides what to write, from three sources in priority order:

1. an explicit **Panel left / Panel width / Panel bottom** saved on the
   **Map panels** element — wins at any map size;
2. **Follow map** turned on — track the rect live, the old behaviour;
3. otherwise the **snapshot**: the first map rect of the session, written once
   and then left alone.

(3) is what fixes the resize. An untouched layout still lands exactly on the
map's edge, because that is where the first rect puts it; every rect after that
is ignored. `Reset this` on Map panels re-snapshots rather than clearing, since
the map may well have been resized since — otherwise the rows would clear and
the panels would visibly stay put, which reads as Reset being broken.

`#map-frame` and the centre cross deliberately *do* still track the map live.
They are drawn on it and are wrong the instant they stop.

### Follow / Own, and the eleven inherited properties

Three elements sit inside the panel stack, and for a handful of properties
`style.css` reads the child's variable with the parent's as the fallback:

```css
font-family: var(--ff-zone, var(--ff-slots, inherit));
```

So an untouched **Zone bar** takes its font from **Map panels**, and setting the
Zone bar's own font silently detaches it. Useful, and previously invisible:
nothing said the value you were looking at came from somewhere else, and the way
back was to guess that `Reset this` would re-attach it.

Those rows now carry a **Follow / Own** switch. `INHERITS` in `app.js` names the
eleven declarations that really do this — every `var(--x-child, var(--x-parent`
in the stylesheet:

| Element | Inherits from Map panels |
| --- | --- |
| Zone bar | Font, Font size, Font weight, Letter spacing |
| Vehicle panel | Font, Font size, Font weight, Letter spacing |
| Vehicle icons | Icon size, Font size |

**If you add another such fallback in `style.css`, add it to `INHERITS` too**, or
the row will keep detaching silently — which is the state this replaced.

There is no stored follow flag. *Absence of a value is* the following state,
because a flag could disagree with the CSS and then one of the two would be
lying. So:

- **Follow** deletes the stored value and lets CSS fall through to the parent.
- **Own** seeds the value from whatever the row is rendering *right now* and
  writes it explicitly, so switching to Own never changes what you are looking
  at — it only stops the parent moving it.

A following row shows the **parent's** value rather than the shipped default
(otherwise it reads as wrong the moment the parent is tuned), dims it to say the
number is not this element's own, and is never given the `changed` dot — the
difference belongs to the parent and there is nothing here to undo. Stepping a
following row starts from the inherited value too, so the first nudge continues
from what is on screen instead of jumping to `default ± step`.

### The editor is on the plate, not the glass

`#editor-panel` uses `.plate` — the map panel material — where the skills screen
and the level-up card are still `.glass`. The split is deliberate: the editor is
chrome for *arranging* the HUD and now matches what it arranges, including the
`ox_target` / `qb-menu` / `qb-input` menus, which carry byte-identical copies of
the same recipe. The skills screen and the level-up card are content the HUD
*shows* you, and stay glass. See "One glass, shared" below for the two
materials side by side.

The panel is also **resizable** from its bottom-right corner, with the size
remembered next to the drag position. This is not decoration: the settings
column is a fixed 45% of the panel's width and its labels ellipsise, so at the
old `max-width: min(74vw, 920px)` there was no way to stop "Letter spacing"
being cut off — a ceiling on a panel whose contents the player controls is just
a wall. Double-clicking the corner puts the stylesheet's size back, so a panel
dragged to something unusable is always one gesture from sane.

### Map width vs Plane width, and why a radius blip goes oval

These two are easy to confuse and they do different jobs, so the rows carry
hover explanations (the dotted labels).

* **Map width / height** scale the `minimap`, `minimap_mask` and `minimap_blur`
  components as one. Everything stays locked together, which is what you want
  for "make the minimap bigger". Because all three move together, these cannot
  change the plane's shape *relative to its window*.
* **Plane width / height** resize the `minimap` component alone — the plane the
  engine draws the world and its blips onto — while the mask window stays where
  it is. This is the only control that changes the plane's **aspect ratio**.

That matters because GTA draws a radius blip (the shaded search area of a barn
find, a heist, a dispatch call) onto that plane. If the plane's aspect does not
match what the engine expects, the circle is drawn stretched — an oval, or with
enough distortion a rectangle-looking smear. If your search radius is not round,
that is the row to reach for, and `/hudcross` plus a radius blip on screen is
how you check your work.

### Vanilla map information

The shape, size and mask of the minimap are vice_hud's to play with. What is
drawn *on* it is GTA's, and this resource had been quietly removing some of it:

* **North marker** — `SetBlipAlpha(GetNorthRadarBlip(), 0)` ran on every apply,
  with no setting behind it and no comment saying why, so "the north icon is
  missing" had no answer anywhere in the config. It now defaults to shown, which
  is what vanilla does, and there is a row to hide it if you want that.
* **Player arrow** — the arrow does **not** scale with the map components. Shrink
  the minimap and the arrow keeps its absolute size, so the proportion vanilla
  had drifts as soon as you resize anything. `0` leaves GTA's own scale alone.

Note what is *not* in that list. `Config.HiddenHudComponents` hides the native
area name, street name, vehicle name and wanted stars, and those are hidden
because vice_hud draws its own zone bar, vehicle panel and star row in their
place — restoring them shows both at once. They are HUD text rather than map
furniture, and a different decision.

### Why the player arrow drifts when you resize the map

Two separate causes, and they are worth keeping apart.

**1. Scaling the group without scaling its offsets.** The three components' sizes
were multiplied by `mapScaleW/H` while their positions stayed at the absolute
constants from the config — the map at `y = -0.047`, the blur at
`(-0.01, 0.025)`. That is a deformation, not a resize. The map's `0.047` drop
below its mask is upstream's deliberate crop, measured in the same units as the
height it was measured against, so at `scaleH 0.603` the plane still dropped a
full `0.047` into a mask only 60% as tall — 1.66x the intended displacement, and
worse the smaller you went. The offsets are scaled now, which makes it a
similarity transform: proportions inside the group are preserved and only the
whole thing changes size.

This one only bites in **maskMode `config`**, where the mask is its own window.
In maskMode `map` the mask mirrors the plane exactly, so the plane's offset
inside it is zero at every scale and always was. `MAP_STATE_VERSION` is bumped,
so geometry saved under the old behaviour is discarded rather than reapplied to
maths it was never measured against.

**2. The plane and the drawn map being different rects.** The arrow is drawn on
the `minimap` component. If what you actually SEE is a different rect — and
`/hudrects` is how you find that out — the arrow sits at the plane's centre
while the map's centre is somewhere else, and the gap between the two centres is
exactly how far off the arrow looks. On one measured configuration (maskMode
`map`, scale 0.763/0.603) the drawn map was the blur rect and the two centres
were 57px and 85px apart, which is the whole of the reported "off and to the
left".

`/hudmatch blur` closes that gap by snapping the blur onto the plane. The same
move fixes radius blips, because those clip to the plane too — once the drawn
map *is* the plane, a radius fills it instead of stopping at an invisible edge.

**So: yes, the map can be resized without wrecking the arrow.** The arrow follows
the plane, so resizing is safe exactly as long as the plane and the visible
extent stay the same rect. What broke it was three rects being free to drift
apart from each other.

### `Blur = map`

The blur component turns out to decide how big the minimap is **drawn**, while
the player arrow and every radius blip are drawn on the **plane**. Let those be
two different rects and the arrow sits off centre and radius blips stop at an
invisible edge — which is exactly what happened.

`Blur = map` (default: **follows map**) recomputes the blur from the plane on
every apply, so the two cannot drift apart no matter what is rescaled later. It
is the same idea `Mask = map` has had all along; the blur simply never got one.

`/hudmatch blur` does the same sum **once**, in absolute units, so it fixes the
map you have and drifts again the next time you resize. Prefer the toggle. A
saved state carrying hand-tuned blur deltas is assumed to have come from
`/hudmatch` and is left on `own rect`, so an already-working map is not
double-corrected on upgrade.

### There is no 2D/3D switch, and this does not pretend to have one

GTA draws the radar as a **tilted three-dimensional plane**. That perspective
lives in the engine's radar renderer and nothing reachable from a resource
flattens it — every "flat minimap" you have seen works by hiding the parts of
the plane where the tilt shows. So rather than a toggle that would not do
anything, the levers that genuinely change how flat it reads are:

* **Radar zoom** — pulled in you are looking at the well-behaved middle of the
  plane and it reads flat; pulled out you see its steeply-angled far edge, which
  is what reads as "3D". `0` means "do not touch it".
* **Mask mode `config`** (`/hudmaskmode config`) — qbx_hud's narrower, taller
  mask window, which is a deliberate crop onto that same middle.
* **Crop top / bottom / left / right** — the manual version of the same idea.

If the map still looks skewed after those, it is the plane's aspect rather than
its tilt, and that is Plane width / height above.

### When a blip does not line up with the map: `/hudrects`

A radius blip (a barn find's search area, a heist zone, a dispatch call) drawn as
a hard-edged **rectangle** on the minimap while the **pause map draws it as a
proper circle** means the blip is fine and some clip region is not where the
visible map is. The pause map is the control; that comparison is worth making
first, because it separates "the blip is wrong" from "our geometry is wrong".

`/hudrects` outlines the only three rects this resource hands the engine,
computed from the exact numbers passed to `SetMinimapComponentPosition` and
converted with the same safe-zone maths the published map rect uses, each
labelled with its own measurements:

| | |
| --- | --- |
| green | `minimap` — the plane the world and its blips draw onto |
| cyan | `minimap_mask` — the window that clips it |
| yellow | `minimap_blur` — the soft edge behind both |

Screenshot it with a radius blip on screen and read off which outline the shaded
area stops at:

* **stops at green** — the plane is smaller than the window. Grow it with Plane
  width / Plane height.
* **stops at cyan** — the mask is the constraint, which is normal.
* **stops at neither** — the clip is GTA's own rather than ours. Try
  `/hudmaskoff` (or Custom mask → `stock`) and `/hudmaskmode config`; if turning
  the custom mask off makes the shaded area match the map, the replacement mask
  texture is clipping the map and the overlay differently.
* **an outline is not on the drawn map at all** — the component numbers and the
  drawn map disagree, which is a different fix again.

An outline that does not sit on the thing it names is itself the finding.

**A worked example.** On one machine `/hudrects` showed `minimap` and
`minimap_mask` set to the *same* rect (`0.1250 x 0.1103`) while the drawn map
filled `minimap_blur` (`0.1999 x 0.1809`) — so the mask was clipping nothing and
the map was rendering 1.6x the size of the plane its blips clip to. A radius blip
therefore appeared as a rectangle in the top-left of the map, stopping dead at
the plane's right edge.

That 1.6x is baked into `Config.MinimapComponent` (`blurW 0.262` against
`w 0.1638`) and survives every scale, because map, mask and blur are all
multiplied by the same factor. Closing it means moving one rect onto the other,
which is what `/hudmatch` does:

```
/hudmatch plane    grow the plane onto the blur
/hudmatch blur     shrink the blur onto the plane
```

They are opposites, so one of the two is the answer; try one, look, `/mapreset`
if it was the wrong one. Which you want depends on whether you would rather keep
the map's current drawn size or its current plane.

The two Plane rows are `/hudblip size` under the hood. They have always been persisted,
reset and printed by `/mapinfo`; they simply had no row in the editor, which put
the one control that can fix a stretched blip outside the tool built for fixing
the map.

These go to Lua as absolute values and the panel redraws from the reply, so it
can never drift from what the map is actually doing. All of it was previously
reachable only through chat commands, which put the fiddliest part of the HUD
outside the tool built for fiddling. Each one writes a single
CSS custom property that `style.css` reads with its own value as the `var()`
fallback — so an untouched property renders exactly as designed, and setting one
back to its default *removes* the variable rather than pinning it.

Everything is forced visible with sample data while the editor is open, and live
game data is ignored for those elements so the preview cannot be painted over.
Choices are stored per player in KVP.

### The vehicle panel

**The panel announces, then collapses.** Getting into a car shows the full plate
for a few seconds; after that it sheds everything that was the announcement and
leaves the three status icons over the map for the rest of the drive.

```
on entering                          for the rest of the drive
+--------------------------------+
|            TRUFFADE            |
|             THRAX              |   ->      (o)  (o)  (o)
+--------------------------------+           no plate, no barrier,
|         (o)  (o)  (o)          |           just the readings
+--------------------------------+
```

The make, the model and the badge have no more news in them once you have read
them; the fuel and the engine do. So `client.lua` pushes the readings for as
long as you are in the vehicle and sends `collapsed` to say which of the two
shapes the page should draw. The panel is not rebuilt for this and never leaves
the slot stack — it collapses in place, which is what stops it reading as one
thing vanishing and a different thing appearing.

`panelUntil` is now only ever the announcement's deadline, never "is anything
showing". That distinction matters: an earlier version stopped pushing entirely
when the window closed, which was correct when the panel was all there was and
became a dead gauge the moment the strip outlived it.

While it is up, the full plate is two bands, and that is load-bearing rather
than decorative:

```
+--------------------------------+
|            TRUFFADE            |  head: the names, and the manufacturer
|             THRAX              |        badge stamped in behind them
+--------------------------------+  <- the barrier, edge to edge
|         (o)  (o)  (o)          |  foot: a lighter strip, status only
+--------------------------------+
```

The barrier is `#veh-foot`'s own `border-top`, not a rule of its own. That is
the whole reason it reaches both edges: a centred element would have to be told
a width, and any width it was told would be wrong the moment the panel was
resized. For the same reason `#vehicle` carries no padding — padding there
would show as a strip of plate the barrier could not cross — so the head owns
the padding instead.

The badge is clipped to the head by `#veh-logo-clip`. It is deliberately
oversized (140% of the head's height) and runs off the top and bottom of the
plate, but it must stop at the barrier: a mark bleeding into the status strip
is what stops the strip reading as a separate band.

**Height is the control that makes the badge bigger.** The head is short and the
marks are not, so height binds for nearly every mark on the roster and raising
`max-width` on its own does nothing at all. Worth knowing before you try it.

#### The manufacturer badges

`html/logos/` holds one mark per marque, keyed by the manufacturer's normalised
name. `html/makes.js` turns whatever `GetMakeNameFromVehicleModel` gives Lua
into one of those files. Both are generated:

```
python tools/fetch_logos.py    # downloads and normalises html/logos/*.png
python tools/make_makes.py     # writes html/makes.js from what is there
```

Two rules decide what ships, and both are worth knowing before you add to the
roster:

**The mark must not spell the manufacturer's name.** The panel already prints
the make directly above the badge, so a mark carrying the name says it twice.
Most marques file both a lockup and a bare emblem and nothing in the filename
separates them, so the choice is pinned by eye in `tools/fetch_logos.py`. A
single-letter monogram in a badge shape is an emblem (Karin's K, Weeny's W); an
initialism that is the whole name is not (BF, HVY, MTL).

**Fifteen manufacturers therefore ship no badge at all**, and that is the
correct outcome, not a gap to fill: Vapid, Pegassi, Progen, Principe, Toundra,
Vysser, Western Company and the rest have nothing on the wiki that is not their
own name set as type. They render the plain plate, exactly as an addon
vehicle with no resolvable make does. If you find a better mark for one, drop it
in `tools/logos_local/<KEY>.png` and re-run both scripts — a local file wins
over anything the wiki has.

Everything is flattened to greyscale ink plus alpha, then evened out so a
dark-bodied emblem reads at the same strength as a white one. `ink()` in
`tools/fetch_logos.py` carries the reasoning for each correction; the short
version is that the roster is sixty-odd marks drawn by different people over
fifteen years and behind the same two lines of type they have to look like one
set. The whole directory is about 400 kB.

#### The status pips

Lock, engine and fuel, in that order. Each is a dark disc with coloured ink;
engine and fuel also carry a **ring that fills to the real reading**, so the
strip answers "how much fuel" and "how broken" rather than only "is it bad yet".

The lock deliberately has no ring. It is a state, not a quantity, and a gauge
that only ever reads full or empty is a worse way of saying what the colour
already says.

| | Green | Amber | Red | Ring |
| --- | --- | --- | --- | --- |
| Lock | locked | unlocked | — | none |
| Engine | health >= 700 | >= 300 | below that, including the negatives a destroyed engine reports | health / 10 |
| Fuel | above 25% | 25% or less | 10% or less | fuel % |

The ring is drawn with `pathLength="100"` on the SVG circle, which relabels the
circle's own length as 100 units so the dash offset *is* the percentage — no
radius and no `2*pi*r` anywhere in the CSS. `--pct` is the only thing `app.js`
writes.

The disc is a constant dark backing and the colour lives in the ink and the
ring. It used to be the other way round — coloured disc, dark glyph — which
cannot carry a gauge, because a coloured ring on a coloured disc has nothing to
read against.

Two edges worth knowing: the ring **clamps**, because `GetVehicleEngineHealth`
runs past zero into the negatives for a destroyed engine and a negative dash
offset draws a full ring; and at zero the stroke's round linecap is swapped for
a butt cap, or an empty tank would still show a pip of fuel at twelve o'clock.

**A shut-off car is monochrome — all three of them.** Green, amber and red on a
parked car is the HUD shouting about a fuel level nothing is currently burning,
and once a whole car park of them lights up you stop reading any of them.
Turning the key is what makes the pips mean something, so turning the key is
what gives them colour.

Only the **colour** goes grey. The rings keep their real reading, because they
are a measurement and hiding it would mean walking up to a car and being told
nothing at all.

The glyphs are inline SVG rather than emoji, and that is not a style preference.
An emoji is drawn by the platform's own font: Windows renders the padlock orange
and the pump red whatever `color` says, so two of the three came out in colours
the design never picked. SVG inherits `currentColor`, so the pip's state tone is
the only thing deciding what colour they are.

### Fonts

The two map panels are set in **GTA Art Deco** by default — GTA's own display
face, shipped in `html/fonts/`. It is set once, on `#slots`, and both panels
inherit; Helvetica stays the fallback for the moment before the file loads and
for any glyph Art Deco does not carry. The Font rows on **Map panels**,
**Vehicle panel** and **Zone bar** still override it, because every one of them
reads its `--ff-*` property first.

Shipped with the resource, so they render identically for every player:

| Family | Real cuts |
| --- | --- |
| Helvetica Neue | Thin (100/200), Roman (400), Medium (500), Bold (700) |
| GTA Art Deco | Regular (400), Medium (500-700) |
| Pricedown | one weight |

The rest of the Font list (System, Arial, Segoe UI, Verdana, Trebuchet, Franklin
Gothic, Impact, Georgia, Monospace) comes from the player's own OS. Fine for a
personal tweak, a poor choice for anything you intend to `/hudpublish`.

**Money is pinned to Pricedown** and has no Font row — it is the one element
whose identity is the typeface.

Weight is only honest where a real cut exists. Picking a weight with no cut
behind it makes the browser synthesise one, and a synthesised light in
particular is the ragged, pixelated-looking text people usually blame on the
screen. To add a weight you need all three: the file in `html/fonts/`, an
`@font-face` block in `style.css`, and an entry in `WEIGHTS` in `app.js` — miss
any one and it silently synthesises.

Adding a **TrueType** font also needs `html/fonts/*.ttf` in fxmanifest's
`files{}`. The glob used to be `.otf` only, which ships nothing and leaves the
font working for exactly one person: whoever dropped the file in.

**Font smoothing** is a per-element row (`-webkit-font-smoothing`). It was
hardcoded to `antialiased` for the whole page; which of subpixel / grayscale /
hard-edged looks best genuinely depends on the display, so it is the player's
call. `text-rendering` is `geometricPrecision` rather than `optimizeLegibility`,
which keeps glyph outlines exact under the editor's scale transforms.

### Long names

The zone bar is a fixed width tied to the minimap and place names are not, so
"South Vice-Dale County Reservoir" used to be clipped to
"South Vice-Dale C…". Both map panels now measure their text and scale it down
to fit — `--fit` multiplies the tuned font size rather than replacing it, so it
composes with whatever you set in the editor.

Past `FIT_MIN` (half size) the text **wraps** instead of shrinking further:
"Western Motorcycle Company" does not fit that panel at any size you could still
read, and half a name is worth less than a taller panel. Re-fitted whenever the
box resizes and once the real fonts have loaded — measuring against the fallback
face gives an answer that is wrong the moment Helvetica arrives.

The **Minimap position** and **Minimap size** rows are special: the engine draws
the minimap, so those arrows are forwarded to Lua, which re-applies
`SetMinimapComponentPosition` and rebuilds the scaleform.

Speed limit and seatbelt live in other resources, each with its own NUI page.
vice_hud stores their offsets and broadcasts them on the `vice_hud:layout`
event; those resources apply the offset to their own page.

### Notifications

The **Notifications** row places the popups of *every* resource on the server —
anything that goes through `lib.notify`. Pick one of ox_lib's eight corners,
then nudge from there; a sample popup fires as you nudge, because a notification
only exists while it is on screen and there is otherwise nothing to aim at.

This needs a hook in **ox_lib**, and there is no way around that: ox_lib draws
notifications on its own NUI page, which vice_hud's CSS cannot reach. The hook
lives in `ox_lib/resource/interface/client/notify.lua`, marked between
`vice_hud hook -- BEGIN` and `-- END`. That file is loaded into *every* resource
that imports ox_lib, so one hook covers all of them without any of those
resources being touched. The original is kept beside it as
`notify.lua.pre-vice_hud`.

> **An ox_lib update overwrites that file and takes the hook with it.** If
> notifications drift back to the top-right on their own, that is what happened.
> `node tools/notify.test.js` fails loudly in that case — run it after updating
> ox_lib.

The hook reads two state bags, personal first:

| Bag | Set by |
| --- | --- |
| `LocalPlayer.state['vice_hud:notify']` | this player's `/movehud` |
| `GlobalState['vice_hud:notify']` | `/hudpublish`, server-wide |

Both are `{ anchor = <one of ox_lib's eight>, x = %, y = % }`. If vice_hud is not
running neither bag exists and the hook is a no-op, so ox_lib behaves exactly as
it did before.

The anchor is applied to every notification, **including ones that asked for a
position of their own**. That is deliberate — "control where popups happen" is
not much of a promise if any resource can opt out of it — but it does mean a
script that deliberately put one notification bottom-left will no longer manage
to.

The nudge is applied as margins in `vw`/`vh`, never pixels or a transform:
percentages keep the placement in the same relative spot on 1080p, 1440p and
ultrawide alike, and a transform would fight the enter animation ox_lib runs on
the same property. On a centred axis the margin is doubled, because flex splits
a margin across both sides of a centred item — that is what makes "+2 means two
percent of the screen to the right" true on all eight anchors.

### Publishing a layout to the whole server

Everything above is stored per player, which is the right home for a preference
and the wrong home for a mistake: when the shipped placement is off, it is off
for everyone and each of them has to fix it themselves.

`/hudpublish` takes whatever you have tuned — offsets, typography, alignment,
the native minimap geometry and the notification placement — and makes it the
default for the whole server. It is written to `layout.json` inside the resource
and mirrored into `GlobalState`, so connected players pick it up immediately and
later arrivals get it on join.

Per element, **personal nudges win**:

* a player who has never saved a layout gets the published one, whole
* a player who has saved one keeps every element they actually changed, and
  picks up the published value for the elements they left alone
* `/hudreset` clears the personal layout, so the published one applies again

The native minimap is all-or-nothing rather than per-element: its values are
interdependent, so half a map from the server and half from the player would be
a shape nobody ever looked at.

**The native minimap is also published per aspect ratio.** The layout offsets
are percentages and mean the same thing on every monitor, so they are published
as one set. The minimap is not like that: its values live in GTA's
safe-zone-relative component space, which is why the ultrawide correction in
`client.lua` has to exist for the map's own X position at all.

So `/hudpublish` files the map under the aspect **bucket** it was tuned on —
`4:3`, `16:10`, `16:9`, `2:1`, `21:9`, `32:9`, defined in `Config.AspectBuckets`
and named by the shared `Config.AspectBucket()` so the client and the server
cannot disagree. A player gets:

1. the profile for their own bucket, if one has been published;
2. otherwise the published bucket whose nominal aspect is **nearest**;
3. otherwise the flat `map` field, which is what a `layout.json` published
   before any of this existed still carries.

Publishing **merges**: a publish only overwrites the bucket it was measured on,
so an admin can tune 16:9 once and ultrawide later and end up with both. The
bucket name is recomputed server-side from the reported aspect rather than
trusted from the payload — otherwise a client could file its map under any name
every other player then matches against.

Nothing is ever **rescaled** between buckets, deliberately. "Centring the player
blip" below records two attempts to model that offset which were wrong in
opposite directions. Step 2 is a guess, but it is a guess *between values that
were each measured on a real screen*, which is a different thing from computing
one. `tools/aspect.test.js` covers all three steps.

Note that step 2 is not "pick the widest": a 21:9 display (2.389) is nearer to
16:9 (1.778, a gap of 0.61) than to 32:9 (3.556, a gap of 1.17), so an ultrawide
player with no 21:9 profile lands on the 16:9 one.

Publishing is gated on an ACE. Add this to `server.cfg`:

```
add_ace group.admin vice_hud.publish allow
```

`command` is accepted as well, since anyone holding it can already run anything
on the box. Payloads are scrubbed server-side before they reach anyone —
unknown keys dropped, nudges clamped to the screen, an unrecognised notification
anchor replaced (ox_lib silently *discards* a notification whose position it
does not know, so a typo there would mute the server). `/hudunpublish` from the
server console clears it.

### Commands

| Command | What it does |
| --- | --- |
| `/movehud` | The editor above — the one to reach for first |
| `/hudmove <element> <dx> <dy>` | Same thing by hand. `/hudmove list` prints the elements |
| `/hudreset` | Restore the reference layout and clear every saved offset |
| `/hudoffset <px>` | Nudge the whole HUD horizontally |
| `/hudbars [pill\|square]` | Status bar corner style |
| `/hudminimap` | Toggle whether the minimap shows while on foot |
| `/hudfocus` | Release NUI focus if the editor ever leaves it stuck |
| `/hudtest` | Push known-good sample data to the NUI and print the live game state |
| `/hudbrand [make]` | Show one manufacturer's badge for 20s, or walk all 51 at 4s each |
| `/hudexport` | Dump the whole tuned HUD as JSON — **run this before any restyle** |
| `/hudimport <json>` | Put an exported HUD back |
| `/hudpublish` | Make your layout the server default (needs `vice_hud.publish`) |
| `/hudunpublish` | Server console: clear the published layout |

### Minimap commands

Reach for `/mapinfo` first — it prints every value that decides the map's size
and shape, plus a block to paste back into `config.lua`.

| Command | What it does |
| --- | --- |
| `/mapinfo` (`/mapvalues`) | Print the full minimap state and a paste-ready config block |
| `/hudmap <wScale> <hScale> [dx] [dy]` | Size and nudge the map live; saved per player |
| `/mapmove` | Alias for `/hudmap` |
| `/mapreset` | Put the map back to `Config.MinimapComponent` |
| `/hudframe` | Draw an outline on the map's intended rect — the practical way to aim it |
| `/hudslot <l> <w> <b> <h>` | Move that outline, in percentages of the stage |
| `/hudnative` | Toggle vice_hud's minimap handling off entirely |
| `/hudmask`, `/hudmaskoff` | Apply or remove the rounded mask texture |
| `/hudmaskmode [config\|map]` | Which mask geometry the installed `.ytd` needs |
| `/hudclip <0-3>` | Try a different `SetMinimapClipType` |
| `/hudcross` | Pink crosshair on the centre of the map rect — the measuring tool |
| `/hudrects` | Outline the three engine component rects — for blips that miss the map |
| `/hudmatch plane\|blur` | Snap one component rect onto another (see `/hudrects`) |
| `/hudcrop top <n>` | Trim dead space off the visible window (top/bottom/left/right) |
| `/hudblip map\|mask <dx> [dy]` | Move either minimap component independently |

### Effect previews

| Command | What it does |
| --- | --- |
| `/hudpolice <edge> [0-1]` | Preview the directional police glow. `/hudpolice off` clears it |
| `/hudtired <0-1>` | Preview the exhaustion vignette without running yourself out |
| `/hudfatigue [0-1\|reset]` | Read or set accumulated fatigue — the thing that costs health |
| `/hudstamina [secs\|reset]` | Sample the stamina native and report what it really does |

### Skills

| Command | What it does |
| --- | --- |
| `/skills` (`/xp`, `/stats`) | Open the skills panel |
| `/skillinfo` | Print every skill and read the GTA stat back out of the engine |
| `/skillxp <skill> <amount>` | Grant XP by hand, for testing the curve and the toast |
| `/skillreset` | Clear your own skills |
| `setskill <id> <skill\|all> <0-100>` | Server console / admin: set someone's level |

## The minimap

`Config.MinimapComponent` holds **qbx_hud's square-map preset, verbatim**
([client/main.lua](https://github.com/Qbox-project/qbx_hud/blob/main/client/main.lua)):

```lua
minimap        0.0    -0.047   0.1638  0.183
minimap_mask   0.0     0.0     0.128   0.20
minimap_blur  -0.01    0.025   0.262   0.300
SetMinimapClipType(0)
```

The map sitting at `y = -0.047` while its mask sits at `y = 0.0` **is the
design, not a bug.** The mask is the visible window, so that offset crops the
map deliberately, and the crop is what gives the square map its shape. It reads
like a mistake, it is not one, and "fixing" it changes the shape. Same for the
mask being narrower (0.128 vs 0.1638) and taller (0.20 vs 0.183) than the map.

`client.lua` adds exactly one thing on top: the ultrawide x offset (credit
Dalrae, via qbx_hud), so on a wider-than-16:9 display the map sits at the
physical screen edge instead of ~18% in.

Do **not** re-derive these from a screenshot or from reference footage. The
reference images are for DESIGN — shape, colour, what sits where — not for
dimensions. Size is a per-player preference, so set it by eye instead:

1. `/movehud`, pick **Minimap size**, arrow keys (Shift for bigger steps).
   It applies live and saves as you go.
2. `/mapinfo` prints what the engine is actually being told, plus a
   paste-ready block for `config.lua` and a one-line summary
   (`3440x1440 aspect 2.3889 safeZone 0.950 scale 1.350/1.350`) for
   generalising the size across displays.
3. `/mapreset` puts it back to the config values.

### The dark band along the top

GTA renders the radar as a **tilted 3D plane**, and that plane does not fill the
`minimap` component — past its far edge there is nothing to draw. Vanilla never
shows this because the stock mask texture carries padding that hides it. Ours is
full-bleed, so the whole component is visible, dead space included.

`/hudcrop top 30` (then 40, 50…) trims the window until the band is gone.
`bottom`, `left` and `right` work the same way, each side independent. The
published rect follows the crop, so the zone bar and frame stay on the map.
Re-run `/hudblip` afterwards to re-centre the arrow.

### Centring the player blip

The blip is drawn against the `minimap` component; the mask is the window you
look through. When the two disagree the blip sits off-centre, and **the amount
is not derivable from outside the game** — two attempts to model it were wrong
in opposite directions (qbx's own mask values put it 14% right; mirroring the
mask onto the map put it left).

**Try `/hudrects` before reaching for the knob.** Most reports of an off-centre
arrow are cause 2 in "Why the player arrow drifts" above — the plane and the
drawn map being different rects — and that has a real fix rather than a nudge:

* **`Blur = map`** in `/movehud` recomputes the blur from the plane on *every*
  apply, so the two can never drift apart at any scale. **This is already the
  default** (`blurMode = 'plane'` in `client.lua`), which means on a stock setup
  cause 2 cannot be your problem — the green and yellow outlines in `/hudrects`
  are the same rect by construction.
* `/hudmatch plane|blur` is for the *other* mode, where the blur is its own
  rect. It is **refused** while `Blur = map` is on, and that refusal is load
  bearing rather than tidiness: its arithmetic is written for `blurMode
  'config'`, and in `'plane'` mode the deltas it computes get applied on top of
  a base that already contains them. With the shipped numbers `/hudmatch blur`
  landed the blur at `0.0656*scale` instead of `0.1638*scale` — a map about 40%
  of its previous size, and the arrow no better. If you are reading this because
  that already happened to you: `/mapreset`.

`/hudmask` and `/hudmaskoff` are unrelated — they apply and remove the rounded
mask *texture*, and neither moves anything.

### Why centring the arrow cuts the map off

On the shipped defaults the plane, the mask and the blur are **the same rect** —
`maskMode 'map'` mirrors the mask onto the plane and `blurMode 'plane'` does the
same for the blur. Computed at 1080p with `MinimapScale 0.663`, all three come
out at `x +0.0000  y -0.0312  w 0.1086  h 0.1213`.

That is why `/hudmatch` has nothing to do — and it is also why nudging cuts the
map off. **A blip nudge slides the plane under the window.** With the rects
flush there is no spare map outside the window, so the moment you slide it, one
edge shows area the plane does not cover. Centre the arrow and you clip an edge;
uncllip the edge and the arrow goes back off-centre. That is the trade people hit
and it is geometry, not a bug.

The way out is to give the nudge something to spend: **grow the plane first**
with `Plane width` / `Plane height` (`blipW`/`blipH`), which stretch the plane
and leave the window where it is. Then nudge into the slack.

`/mapinfo` now prints that slack directly, as the plane's overhang past the mask
on each side:

```
  Plane overhang past the mask (the slack a blip nudge spends):
    left +0.0px   right +0.0px   bottom +0.0px   top +0.0px
    FLUSH — nothing is cut off, but there is no slack.
```

Negative on a side means that edge is cut off *now*. Zero means flush — the
shipped state. Positive is what you want before centring.

If the arrow is still off after the rects agree, then it is a genuine plane
offset and it is a knob, not a computed value. `/hudblip <dx> [dy]` moves the
mask in thousandths of a safe-zone unit until the arrow is centred; `/hudblip
size <dw>` resizes it. The result is saved per player and appears in `/mapinfo`
and `/hudexport`, so once it is right the number gets baked in as the default —
and being a measurement rather than a rule, it is exactly the kind of value the
per-aspect publishing above exists for.

Moving the mask right moves the blip left — you are moving the window, not the
map under it.

`stream/vice_minimap.ytd` is a drop-in for the `squaremap` texture qbx_hud
swaps in, giving the same geometry rounded corners. It is a **512x256 luminance
mask** — the shape is painted in RGB with alpha a uniform 255, which is how GTA
radar masks work. Anyone checking the alpha channel sees a blank opaque
rectangle and concludes the file is empty; it is not. Its white region covers
98.6% x 97.3% of the image, aspect 2.03:1, corner radius ~21px.

## Things worth knowing before changing the minimap code

Two pieces of engine state **outlive this resource** and are not undone by a
restart on their own:

- `SetMinimapComponentPosition` writes into the engine's component table.
- `AddReplaceTexture` stamps over GTA's radar mask for the rest of the session.

`client.lua` restores both when the resource stops, and reconciles
`Config.MinimapMask` against the live swap on every pass. If you add a code path
that touches either, it needs a matching restore, or "vice_hud isn't touching
the map any more" will still draw a broken map.

`SetMinimapComponentPosition` also only updates stored values — the on-screen
scaleform keeps its old geometry until it is rebuilt, which is what
`rebuildMinimap()` is for.

Clip type is owned by `applyMinimap` alone. Setting it anywhere else just fights
the watchdog, and clip type 1 forces a **circle**, throwing away the rounded
rectangle the mask texture defines.

Both KVP stores — `vice_hud:map` and `vice_hud:layout` — carry a version stamp.
Saved offsets are nudges away from a default position, so when a default MOVES,
every saved offset is measured from the wrong origin and re-applying it is worse
than dropping it. Bump the version when that happens; players get a one-line
notice and a clean slate rather than a silently misplaced HUD.

If the map looks wrong, `/hudnative` takes vice_hud out of the picture entirely.
Anything still wrong after that is another resource, a tile pack, or the Safe
Zone Size slider.

## The shipped layout

`Config.DefaultLayout` in `config.lua` holds the tuned placement — offsets,
per-axis scale, and per-element typography — as exported from a real 3440x1440
client with `/hudexport`. A player who has never opened `/movehud` gets this,
not the bare stylesheet.

A saved layout **replaces** this table wholesale rather than merging, so a
player's own values are never stacked on top of the defaults and no version bump
is needed when the defaults change. `/hudreset` returns to this table, not to
nothing.

`speedlimit` and `seatbelt` live here too even though other resources draw them:
vice_hud broadcasts their offsets on `vice_hud:layout`, so dropping them from the
table would make those resources snap back to their own placement.

To change it: tune in `/movehud`, run `/hudexport`, paste the new block in.
Do not hand-edit it.

## Before restyling: export first

Everything a player tunes lives in **KVP on their own machine** — layout offsets,
per-element typography, the map's scale and nudge, the bar shape. None of it is
in this repo.

That matters because offsets are nudges away from a **default**. Move the
default and every saved offset is now measured from the wrong origin, which is
why `LAYOUT_VERSION` exists and why a bump discards them.

So the order is:

1. `/hudexport` — prints the complete state as one line of JSON, to the F8
   console and to `CitizenFX.log`. Copy everything between the markers.
2. Bake those values into `config.lua` and `style.css` as the new defaults.
3. Bump `LAYOUT_VERSION`, so the now-redundant per-player nudges clear. The HUD
   looks identical, but it is correct for everyone out of the box rather than
   only for whoever tuned it.

`/hudimport` puts an export back, so a tuned HUD survives testing something
destructive and can move between machines.

Do **not** run `/hudreset` or `/mapreset` before exporting — they clear the
thing you are trying to save.

## The wanted notification

The box tracks the same two states as the star row, because they mean different
things:

| State | Star | Copy |
| --- | --- | --- |
| police have line of sight (`spotted`) | solid red | "The cops are searching for you and they have your description" |
| police are hunting but cannot see you | flashing white | "The police are searching the area for a suspect" |

The box's own star uses the same two CSS classes as the corner row, so the two
can never disagree. `copsCanSeeMe()` in `client.lua` decides which it is.

## Status bars

The bars are meant to be absent when there is nothing to say: health appears
once you are hurt, stamina once you have spent some, armour once you have any.

Health is normalised against `GetEntityMaxHealth`, not a hardcoded 200 — GTA
puts 100 at dead, and a server that moves the ceiling would otherwise leave the
bar permanently short of full and therefore permanently on screen.

Stamina is harder. `GetPlayerSprintStaminaRemaining` is inconsistent across
builds — remaining vs depletion, `0..1` vs `0..100` — and any script calling
`ResetPlayerStamina` can pin it. `readStamina()` therefore watches the native
while you sprint and latches:

- **which direction it counts**, from the sign of the change, and
- **which scale it uses**, from whether it ever exceeds 1.0.

It prints what it settled on. If the value never moves at all across a sprint,
it falls back to a self-managed bar. **Until it has latched, the bar reports full
and stays hidden** — a wrong guess turns a full bar into an empty one, which then
sits on screen forever, so no bar is drawn until the reading is trustworthy.

`Config.StaminaIsDepletion` is documentation only; nothing reads it as a
fallback any more.

## Exhaustion and fatigue

Two separate mechanics, and the difference matters.

**Exhaustion** is how empty you are *right now*. It drives the move-rate
slowdown, the sprint block at `spentAt`, and the screen vignette. It recovers
the moment you stop.

**Fatigue** is how much exertion you have banked without paying it back. It
rises while you are spending stamina you do not have, and falls **only** once
stamina is genuinely back above `fatigueRecoverAt` — so sprinting, pausing for a
few seconds, and sprinting again accumulates instead of resetting. Past
`fatigueHurtsAt` it costs health continuously, ramped from nothing at the
threshold to `fatigueHpPerSecond` at full, floored at `drainFloor` so it wounds
rather than kills.

Fatigue exists because the instantaneous check could not express what running
yourself into the ground feels like: every individual moment of a sprint/rest
cycle passes the test while the cumulative cost is never paid.

The vignette shows whichever is worse, exhaustion or fatigue. A mechanic that
takes health with nothing on screen explaining it is just unexplained damage.

### Health taken is a debt, not a wound

GTA's own regeneration is slow, caps well short of full, and is switched off
entirely on plenty of servers. So health removed by exhaustion used to be a
permanent dent that only a medic could fix — a punishment for playing rather
than a mechanic. It is now **repaid**, at `recoverHpPerSecond`, once stamina is
back above `fatigueRecoverAt`: the same "actually rested" threshold that clears
fatigue, so catching your breath for two seconds does not refund the cost of not
having.

Repayment is capped at **exactly what this system took**, tracked as a running
debt. That cap is the whole reason it is safe for a HUD to touch health at all:
vice_hud undoes its own effect and nothing else. A HUD that quietly restored
health would fight every injury, downed-state and ambulance script on the
server, and that is not its call to make. Dying settles the debt outright, since
respawn hands back full health anyway.

One implementation note worth keeping: `SetEntityHealth` takes an **integer**. At
0.25 hp/s and 60 fps a frame's drain is 0.004 HP, and flooring that gives zero
every single frame — the drain would be exactly nothing, forever, while looking
entirely reasonable in the code. Both directions carry their sub-1 remainder
between frames.

Simulated behaviour at the shipped values:

| | |
| --- | --- |
| sprint to empty, keep pushing 30s | first hurt at 6s, 195/200 |
| the same for 90s | 180/200 |
| sprint / 4s pause / repeat x6, pause never reaching recovery | 186/200 |
| the same, then a real 60s rest | back to 200/200, debt cleared |
| five solid minutes at zero, then rest | bottoms out at the 140 floor, returns to full |
| jogging for 60s, never below `tiredAt` | never hurts |

The **level-up card** is a `/movehud` element (`Skill level-up`), so it can be
placed, scaled and restyled like anything else. It is two elements rather than
one: the outer carries the placement the editor writes, the inner carries the
glass and the arrival animation. Putting both on one element means the
animation's transform discards the editor's offset for its duration — a bug the
honor popup already had once. While the editor is open the card is re-fired on a
timer so it stays put long enough to position, the same treatment the honor
indicator gets.

`/hudfatigue` prints the live numbers and can jump straight to a level — the
mechanic is deliberately slow (about 11 seconds at zero stamina to build up), so
waiting for it to happen naturally is a poor way to check it works.

### Stamina is self-managed by default

`Config.Stamina.source` is **`'manual'`**: vice_hud runs its own bar. It drains
while you sprint, pauses briefly when you stop, then refills. Twelve seconds to
empty, nine to refill, and the stamina skill lengthens the sprint. That is the
whole model, it is identical on every build, and it cannot disagree with itself.

`'native'` is still there for servers whose build behaves, and it is better than
it was — it learns the range instead of assuming one. But the native is not
worth defaulting to, and the section below is why.

`/hudstamina manual` and `/hudstamina native` switch between them for the
current session, so you can try both without a restart.

### Why the native is not the default



`GetPlayerSprintStaminaRemaining` is documented three different ways —
remaining vs depletion, `0..1` vs `0..100` — and can be pinned outright by
anything calling `ResetPlayerStamina`. `readStamina` therefore does not assume:
it watches the value while you sprint and latches the convention from which way
it moves.

That guess can be wrong, and when it is the result is vicious. A native read as
depletion against an assumed ceiling of 100 gives `100 - 115 = -15%`, and
`exhaustionFrom(-15)` clamps to **full exhaustion** — which disables the sprint
control, which means the player can never sprint, which means the native never
moves again. The wrong reading holds itself in place and presents as "stamina
doesn't drain, it just sits around -15%".

Then `/hudstamina` was run on a real build and reported this:

```
raw  first 0.0000  last 1.2267  min 0.0000  max 9.1000
moved 9.1000  (rose while sprinting => DEPLETION)
mode depletion  scale 1.0  -> bar reads 98.9%
```

A depletion counter running **0 to 9.1**. Not 0..1, not 0..100 — and the ceiling
moves with the player's `MP0_STAMINA` stat, because a fitter character sprints
longer before it tops out. No native reports that ceiling. Read as 0..100, a
full sprint moved the bar from 100% to 91%.

So the native path stopped assuming and started measuring: it normalises against
the **largest value ever observed**, which is correct for 0..1, 0..100 and 0..9.1
at once and needs no guess. That also makes the -15% unproducible rather than
merely detectable — 115 against a learned range of 115 is "fully depleted", which
is what it means. A genuinely negative reading still falls back to the
self-managed bar, because no range makes that mean anything.

It is still not the default. A stamina bar's job is to be right, and after all
that the honest summary is that the native is a research project while the
self-managed bar is right by construction.

`/hudstamina` samples the native and prints its raw range and direction next to
what the interpretation makes of it. `/hudstamina reset` re-arms detection.

`tools/stamina.test.js` drives the real reader against a well-behaved native, a
frozen one, an honest overshoot, and the -15% case specifically.

### One bug worth recording

The original health drain was **unreachable**. It required
`IsPedSprinting(ped)` at `exhaustLevel >= 0.995`, but `spentAt` disables the
sprint control at `exhaustLevel >= 0.985` — so the ped was never sprinting when
the drain could fire, and `overExertMs` reset every frame. It now checks the
sprint **key** (`IsControlPressed(0, 21)`), which is what "still pushing" means
once the game has stopped obeying the input.

## One glass, shared

Every panel this HUD puts *on top of* itself — the `/movehud` editor, the skills
screen, the level-up card — is the same material, defined once as `.glass` with
its tokens on `:root`.

They were not, at first. The editor owned the recipe and each new surface
hand-rolled its own near-miss of the same colours, which is how a design becomes
an approximation of itself: three panels that look *related* rather than
identical. The tokens include the single warm accent (`--g-gold`) for the same
reason — so "the colour for something earned" cannot be reinvented slightly
differently on the next panel.

The recipe is two fills (a top-lit sheen over a translucent tint), a 1px rim,
and a wide low shadow with an inset specular highlight. The `::before` is a
specular **cap**: a real edge catches light unevenly along its top curve, and a
uniform border cannot say that on its own. That cap is most of the difference
between a pane of glass and a grey box with rounded corners — so don't flatten
the layered fills to one colour to simplify. The flat version *is* the grey box.

There is no `backdrop-filter` anywhere in it, and that is not an oversight: on a
transparent NUI page CEF has no backdrop to sample and rasterises the region as
opaque black. `editor.test.js` asserts the absence.

## Skills and XP

Doing a thing makes you better at that thing. Eight skills, each with its own XP
and its own level, and **each level is written straight into the matching GTA
player stat** — that is what makes this a mechanic rather than a number on a
panel. `MP0_STAMINA` really does lengthen your sprint; `MP0_STRENGTH` really does
raise melee damage.

| Skill | GTA stat | Earned by |
| --- | --- | --- |
| Stamina | `STAMINA` | metres sprinted |
| Strength | `STRENGTH` | melee hits landed |
| Lung capacity | `LUNG_CAPACITY` | seconds underwater |
| Shooting | `SHOOTING_ABILITY` | shots on target |
| Stealth | `STEALTH_ABILITY` | metres moved crouched |
| Driving | `DRIVING_ABILITY` | metres driven without a crash |
| Flying | `FLYING_ABILITY` | seconds airborne |
| Wheelie | `WHEELIE_ABILITY` | seconds on one wheel |

### Why levels are 0-100

Because GTA's stats are. Making a skill level *be* the stat value means there is
no second scale to convert between, and no way for the number on screen to drift
from the number the engine is using. `/skillinfo` reads the stat back **out of
the engine** rather than reporting the level it meant to write — a stat that
does not match its level was refused, and that is usually the wrong
`statPrefix` for the ped model in use.

There is deliberately **no global player level**. A single number that rises
whatever you do says nothing about what you are good at, and the stats it would
drive are per-discipline anyway.

### The curve

Per-level cost is linear (`100 + 18 x level`), which makes the total quadratic.
Chosen over the usual exponential on purpose: exponential means the last ten
levels cost more than the first ninety, which reads as a wall rather than as
progress. `tools/skills.test.js` asserts that property and prints what each
level actually costs in the activity's own units, so pacing is a decision
somebody looked at rather than an accident of the constants:

```
  skill      lvl 0->1      lvl 50->51        0->100   unit
  stamina        200          2000        198200   metres sprinted
  strength         8            83          8258   melee hits landed
  lung             8            83          8258   seconds underwater
  shooting        17           167         16517   shots on target
  stealth         50           500         49550   metres moved crouched
  driving       1000         10000        991000   metres driven without a crash
  flying          25           250         24775   seconds airborne
  wheelie         11           111         11011   seconds on one wheel
```

Run that test after changing any `rate` in `skills.lua`.

### Fitness feeds back into fatigue

A trained player banks fatigue more slowly and sheds it faster — at a maxed
stamina skill, half the rise and half again the recovery. `/hudfatigue` prints
the multipliers so the discount is visible rather than mysterious.

### How activity is measured

Two mechanisms, chosen per skill by what is actually observable:

* a sampling loop for anything that is **distance or elapsed time**
* `gameEventTriggered` / `CEventNetworkEntityDamage` for anything that is an
  **event** — a melee hit, a shot on target

Melee-versus-gun is decided by `IsPedArmed` at the moment of the hit, **not** by
the weapon hash in the event payload. That payload's argument layout is not
stable enough across builds to index by position with confidence, and guessing
wrong means silently crediting the wrong skill forever.

Two guards worth knowing about. Distance is discarded if a single sample covers
more than `maxStep` metres, because a teleport or a lift would otherwise bank
hundreds of metres of "sprinting" at once. And driving credits only the
**driver**, and only while the vehicle is not mid-collision — otherwise the
fastest route to a maxed driving skill is sitting in someone else's car.

### Storage, and how much the client is trusted

XP lives in `qbx_core`'s player metadata, which already has a database behind it
and already survives relogs and character switches. A second table for eight
integers would be a migration, a schema and a backup concern in exchange for
nothing.

XP is tracked client-side because that is where the activity is observable —
only the client can see that the player is sprinting. So the save payload is a
client-authored number driving a gameplay stat, and rather than pretend
otherwise, the server enforces the property that actually matters: **XP may only
go up, and only by a plausible amount for the time that has passed.** A modified
client cannot hand itself level 100; it can only earn at the rate an honest
client could.

That is a rate limit, not a proof, and it is worth being clear about which of
the two it is. A save arriving before the client has ever loaded is refused
outright — trusting it would let a fresh connection overwrite stored progress
with zeroes, which is the one way this system could destroy something.

### For other resources

```lua
-- client
exports.vice_hud:AddSkillXp('stamina', 250)
exports.vice_hud:GetSkill('shooting')   --> { xp, level, into, need, frac }
exports.vice_hud:GetSkills()            --> { [id] = { xp, level } }

-- server, authoritative: for rewards the client should not claim for itself
exports.vice_hud:AddPlayerSkillXp(src, 'driving', 500)
exports.vice_hud:GetPlayerSkills(src)
```

A skills system nothing else can feed only ever rewards the handful of
activities this resource happens to watch, which is why the grant exists on both
sides.
