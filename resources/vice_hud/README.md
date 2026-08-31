<div align="center">

# vice_hud

**A GTA VI–styled HUD for Qbox.**

Status bars, wanted stars, weapon and ammo, money, zone bar, a vehicle panel
with real manufacturer badges, honor standing, action prompts, directional
police glow and exhaustion effects — with a full in-game layout editor.

![version](https://img.shields.io/badge/version-2.0.0-2f81f7?style=flat-square)
![framework](https://img.shields.io/badge/framework-Qbox-8957e5?style=flat-square)
![dependency](https://img.shields.io/badge/requires-ox__lib-3fb950?style=flat-square)
![licence](https://img.shields.io/badge/licence-CC%20BY--NC--SA%204.0-fa7970?style=flat-square)
![build](https://img.shields.io/badge/build-none-6e7681?style=flat-square)
![tests](https://img.shields.io/badge/tests-624%20passing-3fb950?style=flat-square)

</div>

---

## The interact menu renders through ScaleformUI

As of 2.0.0 the interact menu (used for things like vehicle slim jim/lockpick
choices) no longer runs through NUI. It is built with
[ScaleformUI](https://github.com/manups4e/ScaleformUI), which draws native
vector graphics through the game engine the same way Rockstar's own menus do,
instead of a rasterized browser texture, so it is sharper and carries no CEF
overhead. The
vendored Lua library lives in `vendor/ScaleformUI_Lua`; see
`vendor/ScaleformUI_Lua/VENDORED.md` for its exact source, commit, and
licence.

This also means the resource now requires a second resource, ScaleformUI's
compiled scaleform movie, since that ships separately from the Lua source.
See **Requirements** and **Installation** below.

`fxmanifest.lua` loads the vendored library through one glob per source
subfolder instead of a single recursive glob, with `ScaleformUI/mainScaleform.lua`
listed last on purpose. That file captures globals like `MinimapOverlays`
into a shared table as soon as it loads, and a single glob expands in
alphabetical path order, which put `mainScaleform.lua` ahead of the files
defining those globals and left the table entries nil. Keep any future
additions to the vendored file list in that same order unless the vendored
source itself changes.

## Why this one

**No build step.** No bundler, no framework, no `dist/`. What is on disk is what
runs, so a stale build can never ship and any change is one restart away.

**Everything is tunable in game.** `/movehud` is a real editor — pick a piece on
the left, tune it on the right, drag the panel out of your way, save. It reaches
elements in *other* resources too, and it can publish one layout to the whole
server.

**It explains itself.** Every non-obvious decision has the reasoning written
next to it, in the file where someone would go looking. See
[`docs/INTERNALS.md`](docs/INTERNALS.md).

---

## Features

### The vehicle panel

Gets in, announces the car, then collapses to just the readings.

```
on entering                          for the rest of the drive
+--------------------------------+
|            TRUFFADE            |
|             THRAX              |   ->      (o)  (o)  (o)
+--------------------------------+           no plate, just the gauges
|         (o)  (o)  (o)          |
+--------------------------------+
```

- **51 real manufacturer badges**, stamped into the plate behind the names.
  Rockstar's own marks, normalised to one visual weight *and* one visual size
  (`tools/normalize_logos.py`), keyed off the make the game reports — accents,
  truncated spawn tokens and all.
- **Gauge rings** on engine and fuel that fill to the actual reading, so the
  strip answers *how much* rather than only *is it bad yet*.
- **The pips earn their place.** All three show while the panel is announcing
  the car. After it collapses only the ones with something to say stay —
  fuel and engine in the amber or red bands, and the lock for a few seconds
  when it actually changes. A healthy car stops drawing a panel at all.
- **A parked car goes monochrome.** Green, amber and red on a car nothing is
  burning fuel in is just noise.

### The rest

| | |
| --- | --- |
| **Status bars** | Health, armour, stamina. Auto-hide at full, with an anti-flicker hold |
| **Minimap** | Rounded corner mask with 14 baked radii, positioned and resized from the editor |
| **Turn-by-turn** | A nav bar above the map while a waypoint is set, from the game's *own* GPS route — so it never disagrees with the line on the minimap. Appears near a junction and gets out of the way otherwise |
| **Wanted** | Star row, plus the "cops are searching for you" notice and its tells |
| **Money** | Cash and bank, in GTA's own Pricedown |
| **Honor** | A standing panel and a separate centre-screen change indicator |
| **Police glow** | Directional edge lighting driven by real siren bearing and distance. Three modes, with a live editor |
| **Exhaustion** | A vignette that breathes in as stamina empties |
| **Skills** | Eight skills that write straight into the character's stats, so levelling changes how the game plays |
| **Prompts** | `ShowActionPrompt` for other resources, auto-cleaned if the caller crashes |

---

## Requirements

| | |
| --- | --- |
| **Required** | [`ox_lib`](https://github.com/overextended/ox_lib) |
| **Required** | `ScaleformUI_Assets` (bundled in `resources/`), the compiled scaleform movie the interact menu renders through |
| **Optional** | `ox_inventory` — weapon icons, omitted cleanly if absent |
| **Optional** | `qbx_core` — the money readout and skill XP persistence |
| **Optional** | `qbx_honor` — the honor system |
| **Optional** | `speedlimits`, `zseatbelt` — positioned by the editor's *Other resources* rows |

Nothing optional is a hard failure: each is probed with `GetResourceState` and
the HUD simply leaves that piece out.

## Installation

```bash
# 1. drop both folders into your resources/: vice_hud AND ScaleformUI_Assets
# 2. in server.cfg, after ox_lib, ScaleformUI_Assets BEFORE vice_hud:
ensure ScaleformUI_Assets
ensure vice_hud
```

> [!IMPORTANT]
> Adding new files to a running server needs `refresh` **before** `ensure`. A
> FiveM server only rescans a resource folder on `refresh` — `restart` re-runs
> the scripts but keeps serving the file list from the last scan, so new files
> 404 while everything else looks fine.

---

## The editor

```
/movehud
```

| Key | |
| --- | --- |
| <kbd>←</kbd><kbd>↑</kbd><kbd>↓</kbd><kbd>→</kbd> | move |
| <kbd>Ctrl</kbd> + arrows | resize |
| <kbd>Tab</kbd> | next piece |
| <kbd>[</kbd> <kbd>]</kbd> | pick a setting |
| <kbd>−</kbd> <kbd>+</kbd> | change it |
| <kbd>Shift</kbd> | bigger steps |
| <kbd>Space</kbd> | hold to see through the panel |
| <kbd>Enter</kbd> / <kbd>Esc</kbd> | save / cancel |

Click any value to type an exact number. Twenty elements, each with position,
size, opacity, font, weight, letter spacing, alignment, smoothing, corner radius
and child spacing — every one writing a single CSS custom property, with the
shipped value as the `var()` fallback so an untouched setting renders exactly as
designed.

> [!TIP]
> Run `/hudexport` **before** any restyle. Offsets are nudges away from a
> default, so changing a default silently invalidates every saved one.

Happy with it? `/hudpublish` makes your layout the server default for everyone
(gated behind an ace).

---

## API

```lua
exports.vice_hud:ShowActionPrompt(id, label, key)  -- key: a string, or a control id
exports.vice_hud:HideActionPrompt(id)

exports.vice_hud:ShowHonorToast(mugshot, honor, emoji, reason)
exports.vice_hud:ShowHonorChange(delta, mugshot)
exports.vice_hud:SetHonorStanding(honor)           -- seeds the value, draws nothing

exports.vice_hud:SetHudVisible(visible)
exports.vice_hud:SetHudOffsetX(pixels)
exports.vice_hud:GetHudOffset(element)             -- returns x, y

exports.vice_hud:AddSkillXp(id, amount)
exports.vice_hud:GetSkill(id)                      -- { id, xp, level, into, need, frac }
```

Prompts are cleaned up automatically when the resource that registered them
stops, so a crashed script cannot strand one on screen — give ids the
`yourresource:something` form for that to work.

---

## Commands

<details>
<summary><b>Layout</b></summary>

| | |
| --- | --- |
| `/movehud` | The editor — reach for this first |
| `/hudmove <element> <dx> <dy>` | The same by hand. `/hudmove list` prints the elements |
| `/hudreset` | Back to the shipped layout |
| `/hudexport` · `/hudimport <json>` | Dump / restore the whole tuned HUD |
| `/hudpublish` · `/hudunpublish` | Make your layout the server default |
| `/hudoffset <px>` · `/hudtheme` | Global nudge, theme |

</details>

<details>
<summary><b>Minimap</b></summary>

| | |
| --- | --- |
| `/mapinfo` | Prints every value deciding the map's size and shape, plus a block to paste into `config.lua` |
| `/mapmove` · `/mapreset` · `/mapvalues` | Position, restore, dump |
| `/hudmask` · `/hudmaskmode` · `/hudmaskoff` | The rounded corner mask |
| `/hudrects` · `/hudmatch` · `/hudcross` | Draw the engine's own component rects, and line them up |
| `/hudminimap` | Show the map on foot |

</details>

<details>
<summary><b>Diagnostics</b></summary>

| | |
| --- | --- |
| `/hudtest` | Push known-good sample data and print the live game state |
| `/hudbrand [make]` | One manufacturer badge for 20s, or walk all 51 |
| `/hudlogos` | Why is there no badge? Names the actual fault |
| `/hudpolice` · `/hudstamina` · `/hudfatigue` | Effect previews |
| `/skills` · `/skillinfo` · `/setskill` · `/skillxp` | The skills panel and its levers |

</details>

---

## Development

No build. Open `html/index.html` in a browser — `app.js` detects it is outside
FiveM and fills itself with representative data.

```bash
npm i jsdom fengari      # test deps only, never shipped

node html/editor.test.js     # the /movehud editor
node html/makes.test.js      # manufacturer badges, gauges, panel states
node html/mapchrome.test.js  # frame / badge / compass follow the map
node html/worldactions.test.js # world-action icons follow the live device
node html/healthreveal.test.js  # health row reveals on change, not on "not full"
node tools/aspect.test.js    # per-display map profiles
node tools/needs.test.js     # hunger / thirst
node tools/notify.test.js    # ox_lib notification offsets
node tools/oxygen.test.js    # the dive model
node tools/radius.test.js    # minimap mask radii
node tools/skills.test.js    # the XP curve
node tools/split.test.js     # every client chunk loads, and stays under Lua's 200-local cap
node tools/navfoot.test.js   # turn-by-turn hides on foot
node tools/radarchrome.test.js # setRadar reports transitions, not ticks
node tools/radarsurvives.test.js # a broken status tick cannot delete the minimap
node tools/onfoot.test.js    # hide-the-map-on-foot: toggle, KVP, and conflicts
node tools/worldactions.test.js # Slim Jim/Smash Window glyph resolves from the real bind
node tools/wheelheld.test.js  # weapon wheel detection covers both enabled and disabled control
node tools/stamina.test.js   # the fatigue model
node tools/waypoint.test.js  # waypoint route colour (one line, not two)
node tools/vehpanel.test.js  # the vehicle panel
```

The Lua suites run the shipped client files themselves through
[fengari](https://fengari.io), so
they test the shipped code rather than a re-implementation of it.

### Regenerating the manufacturer badges

```bash
pip install pillow
python tools/fetch_logos.py      # downloads them, evens out how DARK they are
python tools/normalize_logos.py  # evens out how BIG they are  <- do not skip
python tools/make_makes.py       # writes html/makes.js from what is there
```

The two normalisation passes fix different problems and both are needed.
`fetch_logos.py` flattens each mark to one ink weight, then crops it to its own
edges — which leaves fifty-one wildly different *shapes*, so a single CSS rule
sizes a wide slab and a narrow upright completely differently (the ink area ran
**9.9x** between the largest and smallest mark). `normalize_logos.py` scales
each one to a constant ink area and centres it on one shared square canvas,
which is what lets the stylesheet size all fifty-one with one rule. It keeps the
untouched originals in `tools/logos_raw/` and always re-reads from there, so it
is safe to re-run and `CANVAS` can be retuned freely.

Marks come from the [GTA Wiki](https://gta.fandom.com/wiki/Vehicle_Manufacturers).
**A badge never spells the manufacturer's name** — the panel already prints it
directly above — so marques whose only mark is their own name set as type ship
no badge and render the plain plate. Drop a better one in
`tools/logos_local/<KEY>.png` to override.

`tools/` is not in `fxmanifest`'s `files{}`, so none of it reaches clients.

---

## Configuration

`config.lua`, with the reasoning beside each value. The ones most worth knowing:

| | |
| --- | --- |
| `Config.DefaultLayout` | The shipped layout. A saved layout replaces it wholesale rather than merging |
| `Config.Minimap` · `Config.MinimapComponent` | The map's rect and the engine component values behind it |
| `Config.Nav` | Turn-by-turn: how close a junction has to be before the bar appears, and the hysteresis that stops it flickering |
| `Config.Skills` | The eight skills, their curves and what each one feeds into |
| `Config.PoliceLights` | Mode, brightness, flash, lamp shape, detection range |
| `Config.Exhaustion` · `Config.Stamina` | The fatigue model |
| `Config.HiddenHudComponents` | Which native components to suppress — only the ones actually replaced |

---

## Documentation

**[`docs/INTERNALS.md`](docs/INTERNALS.md)** — the long version. Why the minimap
is built the way it is, why the player blip drifts when you resize the map, how
the honor push works, what the exhaustion model actually models, and the traps
that already bit once. Read it before changing the minimap code.

## Assets and fonts

**Helvetica Neue is not bundled.** It is a commercial Monotype/Linotype face and
redistributing it here is not ours to do, so the four cuts are resolved with
`local()` from the player's own machine instead. The chain falls back
Helvetica Neue → Helvetica → **Arial** → Liberation Sans; Arial is metrically
compatible with Helvetica, so line lengths and the shrink-to-fit measurements
hold either way. The one visible difference is the *Thin* cut, which Arial has
no equivalent for and which therefore renders as regular on machines without
Helvetica Neue — that affects the nav bar and the wanted box, both tuned to
thin in the shipped layout. If you hold a licence, drop the `.otf` files into
`html/fonts/` and restore the `url()` sources in `style.css`; `fxmanifest`
already globs `html/fonts/*.otf`.

**Rockstar-derived assets** — the GTA Art Deco and Pricedown faces, and the 51
manufacturer marks (via the [GTA Wiki](https://gta.fandom.com/wiki/Vehicle_Manufacturers))
— ship as-is, as is normal for FiveM resources. They remain Rockstar's
property; this project claims no rights over them and the licence below covers
only the code.

## Licence

[CC BY-NC-SA 4.0](LICENSE): Attribution, NonCommercial, ShareAlike. You may
use, modify and redistribute this, but not on a paid/commercial server, and
credit is required. A modified version has to stay under the same licence.
This matches `vendor/ScaleformUI_Lua`'s own licence (see that folder's
`VENDORED.md`), which this resource depends on and could not legally be
distributed under permissive terms anyway.

> [!NOTE]
> `vendor/ScaleformUI_Lua` and the sibling `ScaleformUI_Assets` resource
> remain their own upstream project ([ScaleformUI](https://github.com/manups4e/ScaleformUI)
> by manups4e, PhilippRendell and Lacol9) under their own copyright; this
> licence covers vice_hud's own code, not theirs.

## Credits

Built for Qbox, on top of [`ox_lib`](https://github.com/overextended/ox_lib).
Minimap geometry follows [`qbx_hud`](https://github.com/Qbox-project/qbx_hud)'s
square-map preset. Manufacturer marks and the GTA typefaces are Rockstar's.

The interact menu's scaleform rendering is built on
[ScaleformUI](https://github.com/manups4e/ScaleformUI) by manups4e,
PhilippRendell and Lacol9, vendored under `vendor/ScaleformUI_Lua` (see that
folder's `VENDORED.md`). Thanks to the Qbox Discord for pointing to it and to
these related repositories:

- [ScaleformUI](https://github.com/QuadrupleTurbo/ScaleformUI)
- [ScaleformUI-Scaleform](https://github.com/QuadrupleTurbo/ScaleformUI-Scaleform)
- [FxEvents](https://github.com/QuadrupleTurbo/FxEvents)
- [natives](https://github.com/QuadrupleTurbo/natives)
- [NativeUI-scaleform_flash](https://github.com/QuadrupleTurbo/NativeUI-scaleform_flash)
