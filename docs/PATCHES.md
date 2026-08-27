# Applying the patches

Everything under `resources/` is a complete, self-contained resource — drag
it into your server's `resources/` folder, add it to `server.cfg`, done.

Everything under `patches/` is **not** a resource on its own. Each folder is
a small set of files that overlay onto a resource you already have installed
(ox_lib, ox_target, ox_inventory, qb-menu, qb-input) to bring vice_hud's
theme into that resource's own UI. Copy the files into place, then make the
one- or two-line edit shown below for that resource. None of these change
functionality — every patch is presentational only (a stylesheet + a script
that listens for a theme broadcast from vice_hud).

**Version pinned against:** ox_lib 3.32.3, ox_target 1.18.0, ox_inventory
2.45.0, qb-menu 1.2.0, qb-input 1.2.0. If your copy of any of these is on a
different version, check the target file still looks like the snippet below
before you paste the patch in — a big upstream version jump can move things
around.

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

## ox_inventory (GTA6 F2 screen reskin)

This one is a separate, unrelated visual — a GTA VI-inspired reskin of the
F2 inventory screen, not part of the vice_hud glass/theme system above. It's
presentation-only: no drag/drop, slot, or networking logic is touched.

Source files (for reference / future edits — editing these does nothing on
their own, ox_inventory's web UI is a Vite/React build):

```
patches/ox_inventory/web/src/gta6-theme.scss
patches/ox_inventory/web/src/index.scss
patches/ox_inventory/web/src/components/inventory/InventoryTabs.tsx
patches/ox_inventory/web/src/components/inventory/LeftInventory.tsx
patches/ox_inventory/web/src/components/inventory/WeaponWheel.tsx
patches/ox_inventory/web/src/components/inventory/PromptGlyph.tsx
patches/ox_inventory/web/src/components/inventory/PlayerStatusBars.tsx
```

Already-built output — copy these directly into your `ox_inventory/`
install and it just works, no build step required:

```
patches/ox_inventory/web/build/assets/index-4d9c5d34.js
patches/ox_inventory/web/build/assets/index-ed184ded.css
patches/ox_inventory/web/build/index.html
```

Your `web/build/index.html` must reference those exact two hashed asset
filenames — if your ox_inventory is on a different version than 2.45.0, the
hashes (and possibly the component APIs the `.tsx` files above call into)
will differ, so treat the source files as a reference to reapply by hand
rather than dropping the build output in blind.

Colors are exposed as CSS custom properties in `gta6-theme.scss`, so you can
retheme without touching component code.
