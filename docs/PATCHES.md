# Applying the patches

Everything under `resources/` is a complete, self-contained resource — drag
it into your server's `resources/` folder, add it to `server.cfg`, done.

Everything under `patches/` is **not** a resource on its own. Each folder is
a small set of files that overlay onto a resource you already have installed
(ox_lib, ox_target, ox_inventory, qb-menu, qb-input, speedlimits, zseatbelt,
um_smallresources) to connect it to vice_hud. Copy the files into place, then
make the one- or two-line edit shown below for that resource.

Most of these are presentational only — a stylesheet plus a script that
listens for a theme broadcast from vice_hud. Two are not: `speedlimits` and
`zseatbelt` are **positioning hooks** (they let vice_hud's `/movehud` editor
move that resource's own on-screen icon, which vice_hud otherwise has no way
to reach since each one draws through its own NUI page rather than
vice_hud's), and `um_smallresources` is a **functional conflict fix** (a
competing script that resets player stamina every 500ms, which pins vice_hud's
stamina bar at full and makes it look broken).

**Version pinned against:** ox_lib 3.32.3, ox_target 1.18.0, ox_inventory
2.45.0, qb-menu 1.2.0, qb-input 1.2.0, speedlimits 1.2.0, zseatbelt 1.1.0-um.
If your copy of any of these is on a different version, check the target
file still looks like the snippet below before you paste the patch in — a
big upstream version jump can move things around.

**An update to any of these resources will silently wipe its patch.** That's
expected — these are hand-edits sitting on top of someone else's resource,
not a fork you maintain. Re-apply the patch after you update.

---

## ox_lib

Copy into your `ox_lib/` install:

```
patches/ox_lib/resource/interface/client/notify.lua
patches/ox_lib/resource/interface/client/notify.lua.pre-vice_hud   (restore point — the un-patched original)
patches/ox_lib/resource/interface/client/vice_theme.lua
patches/ox_lib/web/build/vice-glass.css
patches/ox_lib/web/build/vice-glass.js
```

No `fxmanifest.lua` edit needed — `vice_theme.lua` is picked up by ox_lib's
existing `resource/**/client/*.lua` glob.

Then add two lines to `web/build/index.html`, right before `</head>`:

```html
<!-- vice_hud glass -- BEGIN (added by vice_hud; safe to delete these two
     lines and the two files they reference). Loaded AFTER ox_lib's own
     stylesheet so its rules win, and non-module so it runs before the
     React bundle mounts and can observe the first popup. An ox_lib update
     overwrites this file and removes both lines. -->
<link rel="stylesheet" href="./vice-glass.css">
<script src="./vice-glass.js"></script>
<!-- vice_hud glass -- END -->
```

If a `web/build/index.html` is included in this patch folder, it's an
already-edited reference copy — diff it against yours before overwriting,
since ox_lib's own build hashes its bundle filenames per version and yours
will differ.

## ox_target

Copy into your `ox_target/` install:

```
patches/ox_target/client/vice_theme.lua
patches/ox_target/web/vice-theme.css
patches/ox_target/web/js/vice-theme.js
patches/ox_target/web/fonts/GTAArtDecoRegular.ttf
patches/ox_target/web/fonts/GTAArtDecoMedium.ttf
```

In `fxmanifest.lua`, add to `client_scripts`:

```lua
'client/vice_theme.lua',
```

No `files{}` edit needed — `ox_target`'s manifest already ships `'web/**'`
as one glob, so `vice-theme.css`, `js/vice-theme.js`, and the two font
files are picked up automatically once they're copied into `web/`.

In `web/index.html`, right before `</head>`:

```html
<!-- vice_hud theme -- BEGIN (added by vice_hud; safe to delete both lines).
     The stylesheet goes AFTER style.css so that where the two set the same
     property at the same specificity this one wins, which is what lets it
     avoid !important throughout. The script is deliberately not deferred:
     it only registers a message listener, and running it here means the
     listener exists before Lua's first push can arrive. An ox_target update
     overwrites this file and removes both lines. -->
<link href="vice-theme.css" rel="stylesheet" type="text/css" />
<script src="js/vice-theme.js"></script>
<!-- vice_hud theme -- END -->
```

## qb-menu

Copy into your `qb-menu/` install:

```
patches/qb-menu/client/vice_theme.lua
patches/qb-menu/html/vice-theme.css
patches/qb-menu/html/vice-theme.js
patches/qb-menu/html/fonts/GTAArtDecoRegular.ttf
patches/qb-menu/html/fonts/GTAArtDecoMedium.ttf
```

In `fxmanifest.lua`, add to `client_scripts`:

```lua
'client/vice_theme.lua',
```

And add to `files`:

```lua
'html/vice-theme.css',
'html/vice-theme.js',
'html/fonts/*.ttf'
```

In `html/index.html`, right before `<script src="./script.js" defer>`:

```html
<!-- vice_hud theme -- BEGIN (added by vice_hud; safe to delete both
     lines). The stylesheet goes AFTER style.css so that where the two
     set the same property at the same specificity this one wins, which
     is what lets it avoid !important throughout. The script is
     deliberately not deferred: it only registers a message listener,
     and running it here means the listener exists before Lua's first
     push can arrive. A qb-menu update overwrites this file and removes
     both lines. -->
<link rel="stylesheet" href="./vice-theme.css" />
<script src="./vice-theme.js"></script>
<!-- vice_hud theme -- END -->
```

## qb-input

Copy into your `qb-input/` install:

```
patches/qb-input/client/vice_theme.lua
patches/qb-input/html/vice-theme.css
patches/qb-input/html/vice-theme.js
patches/qb-input/html/fonts/GTAArtDecoRegular.ttf
patches/qb-input/html/fonts/GTAArtDecoMedium.ttf
```

`qb-input`'s `client_scripts` already globs `client/*.lua`, so no
`fxmanifest.lua` client_scripts edit is needed. Add to `files`:

```lua
'html/vice-theme.css',
'html/vice-theme.js',
'html/fonts/*.ttf'
```

In `html/index.html`, anywhere in `<head>` (position is cosmetic — this page
has no stylesheet link of its own; `script.js` injects the stock sheet at
runtime, always after this one):

```html
<!-- vice_hud theme -- BEGIN (added by vice_hud; safe to delete both
     lines). Position in <head> is cosmetic here and nothing else: this
     page has no stylesheet link of its own -- script.js injects the
     stock sheet at runtime, so it always lands after this one whatever
     order these lines are in. vice-theme.css wins on specificity
     instead; see its header. The script is deliberately not deferred,
     so its message listener exists before Lua's first push arrives. A
     qb-input update overwrites this file and removes both lines. -->
<link rel="stylesheet" href="./vice-theme.css" />
<script src="./vice-theme.js"></script>
<!-- vice_hud theme -- END -->
```

## ox_inventory (GTA6 reskin)

This one is a separate, unrelated visual — a GTA VI-inspired reskin of both
the F2 inventory screen and the in-world hotbar, not part of the vice_hud
glass/theme system above. It's presentation-only: no drag/drop, slot, or
networking logic is touched — `WeaponWheel.tsx` wraps the same
`InventorySlot` components, so dnd, right-click, ctrl+click drop, and
alt+click use all keep working.

The hotbar is a curved wheel (`WeaponWheel.tsx`) of 8 cells mapped onto
inventory slots 1-6, not an evenly-spaced circle — each cell's position was
measured off reference art (two of the eight are flagged in the source as
unverified placements). Cells now have **roles**: `free` (any item, the
original behaviour), `melee`, `handheld`, and a `fist` cell that isn't
backed by an inventory slot at all — it's a fixed button that always shows
the fist icon (`web/images/fist.png`) and holsters whatever's equipped
(`onDisarm.ts`). `wheelCategories.ts` defines what counts as melee/handheld/
medical. The bottom-left quickslots are now medical-items-only (2 slots).

There's also a bottom-right honor badge (`gta6-honor`), fed by `qbx_honor`
over a `setHonor` NUI message — see `store/honor.ts`. **This half isn't
wired up yet**: `qbx_honor/client/main.lua`'s `qbx_honor:client:syncHonor`
handler currently only seeds `vice_hud`, it never forwards to ox_inventory's
NUI page, so the badge will never render until that's added.

Source files (for reference / future edits — editing these does nothing on
their own, ox_inventory's web UI is a Vite/React build):

```
patches/ox_inventory/web/src/gta6-theme.scss
patches/ox_inventory/web/src/index.scss
patches/ox_inventory/web/src/components/inventory/InventoryTabs.tsx
patches/ox_inventory/web/src/components/inventory/LeftInventory.tsx
patches/ox_inventory/web/src/components/inventory/WeaponWheel.tsx
patches/ox_inventory/web/src/components/inventory/InventorySlot.tsx
patches/ox_inventory/web/src/components/inventory/PromptGlyph.tsx
patches/ox_inventory/web/src/components/inventory/PlayerStatusBars.tsx
patches/ox_inventory/web/src/dnd/onDisarm.ts
patches/ox_inventory/web/src/store/honor.ts
patches/ox_inventory/web/src/store/wheelCategories.ts
```

New image asset the fist cell needs (already covered by ox_inventory's own
`'web/images/*.png'` manifest glob, no manifest edit needed):

```
patches/ox_inventory/web/images/fist.png
```

Already-built output — copy these directly into your `ox_inventory/`
install and it just works, no build step required:

```
patches/ox_inventory/web/build/assets/index-dfcb990c.js
patches/ox_inventory/web/build/assets/index-bcccb513.css
patches/ox_inventory/web/build/index.html
```

Your `web/build/index.html` must reference those exact two hashed asset
filenames — if your ox_inventory is on a different version than 2.45.0, the
hashes (and possibly the component APIs the `.tsx` files above call into)
will differ, so treat the source files as a reference to reapply by hand
rather than dropping the build output in blind.

Colors are exposed as CSS custom properties in `gta6-theme.scss`, so you can
retheme without touching component code.

## speedlimits

Positioning hook, so the posted-speed-limit sign can be moved with everything
else in vice_hud's `/movehud` editor (**Other resources** row). Both files
were edited directly, not just appended to — the CSS in particular was
rewritten to anchor against vice_hud's own viewport stage (`.stage`, full
viewport, not a centred 16:9 box) instead of floating at a raw screen edge,
so it stays lined up with the minimap on ultrawide.

Copy over your `speedlimits/` install:

```
patches/speedlimits/client/main.lua
patches/speedlimits/html/index.html
patches/speedlimits/html/index.html.pre-vice_hud   (restore point — the un-patched original)
```

No `fxmanifest.lua` edit needed — both files already exist in stock
`speedlimits` and are already declared there; only their contents changed.

If your `speedlimits` version differs from 1.2.0, diff `index.html.pre-vice_hud`
against your own `html/index.html` first — if the stock file has changed
shape, hand-merge the vice_hud hook (the `.stage` wrapper, the `--off-*`
transform, and the `case "offset":` branch in the message listener) instead
of overwriting.

## zseatbelt

Same kind of positioning hook as `speedlimits`, for the seatbelt icon.

Copy over your `zseatbelt/` install:

```
patches/zseatbelt/client/main.lua
patches/zseatbelt/client/html/index.html
patches/zseatbelt/config.lua
```

`config.lua` is included because `Config.showUnbuckledIndicator` was flipped
back to `true` here — it had been turned off because an older HUD (`um_hud`)
drew its own belt icon, and vice_hud's vehicle panel does not. If you've
already set that config value deliberately for your own reasons, don't
overwrite it — only the `client/` and `html/` changes are the actual
vice_hud hook.

No `fxmanifest.lua` edit needed.

## um_smallresources (Stamina)

Not a theme patch — a **functional conflict fix**. `um_smallresources`
bundles a `Stamina` script that calls `ResetPlayerStamina()` every 500ms to
give infinite stamina. That pins `GetPlayerSprintStaminaRemaining()` at full
faster than it can ever drain, so vice_hud's stamina bar reads "full"
forever and looks broken — it isn't; there's just nothing for it to read.

If you run `um_smallresources` alongside vice_hud, replace:

```
patches/um_smallresources/Stamina/client.lua
```

The original — the infinite-stamina version — sits beside it as
`client.lua.pre-vice_hud` if you'd rather keep infinite stamina and just
remove vice_hud's stamina bar instead (`Config.Stamina` in `vice_hud`).

No `fxmanifest.lua` edit needed — same filename, same file list.
