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
glass/theme system above. The visual layer is presentation-only: no
drag/drop, slot, or networking logic is touched there — `WeaponWheel.tsx`
and `ItemWheel.tsx` both wrap the same `InventorySlot` components, so dnd,
right-click, ctrl+click drop, and alt+click use all keep working. The one
genuinely functional piece is the pocket cap module described below, which
does change server-side slot/weight limits.

The hotbar is a curved wheel (`WeaponWheel.tsx`) of 8 cells mapped onto
inventory slots 1-7, not an evenly-spaced circle. Fixed layout: top (12
o'clock) is always `weapon`, middle-right is always `fist`, 8 o'clock is
always `melee`, 4 o'clock is always `handheld`, and the remaining four
cells are `free` (any item, including weapons). Every non-fist cell is a
real `InventorySlot` — including the top one, which used to be a read-only
image that only ever mirrored whatever was equipped elsewhere. Because it's
a real slot, the wheel is only gated on a *keybind* for slots 1-5; slots
5-7 still accept drag-and-drop from the inventory and right-click/alt-click
same as any other slot, there's just no default number key wired to them,
and clicking a cell equips/uses it (`onCellClick` → the same `onUse` call
the number keys make) regardless.

The top cell keeps the old readout's ammo strip and teal glow, but they
only render now while the item actually sitting in that cell is the
genuinely equipped weapon (`item.slot === equipped.slot`, the same check
every other cell already used for its own equipped-ring highlight) — a gun
sitting there unequipped just looks like an idle wheel cell, the same as an
idle melee/handheld cell does. `wheelCategories.isWeaponItem` accepts it:
any `weapon_`-prefixed item that isn't already claimed by the melee or
handheld lists (both of those are also `weapon_`-prefixed, e.g.
`weapon_bat`, `weapon_flashlight` — a bare prefix check can't tell them
apart from a real firearm).

Five cell positions were measured off reference art; the other two mirror
the melee/handheld row across the pistol/fist row — same x (38.33% /
62.45%), and as far above the middle row (48.49%) as melee/handheld sit
below it (63.61% − 48.49% = 15.12%, so 48.49% − 15.12% = 33.37%). Still
worth checking against a real screen rather than trusting pixel-for-pixel,
same as the five measured ones.

`fist.png` is padded onto a 1418x1418 transparent canvas (fist content at
60%/38.6% width/height) rather than the original 851x548 canvas with zero
internal margin — every other item icon has a several-percent transparent
border baked in, and the fist read oversized next to them at matching
`background-size` until it had a comparable margin. If it's still visibly
off after this, check for an NUI image cache first — `fist.png` is loaded
by a fixed path, not a content-hashed filename like the JS/CSS, so a client
that already loaded the page once may be showing stale cached bytes even
after the file on disk changes; a full reconnect clears it.

Stock `InventorySlot` also draws its own durability bar (`WeightBar.tsx`,
a red/orange/green fill strip) for any item carrying `metadata.durability`
— bandages and medkits included. It's a sibling of the header wrapper the
theme already hides, not a child of it, so hiding the header alone missed
it: it drew right across the top of the cell, which isn't part of this
wheel's design at all (ammo/qty readouts here come from the wheel's own
elements, built off real data). `gta6-theme.scss`'s shared slot-shell mixin
now hides `.durability-bar`/`.weight-bar` too.

The ITEMS tab (`InventoryTabs.tsx`) is a second wheel now, `ItemWheel.tsx`,
not the plain square grid it used to fall back to. It reuses `WeaponWheel.tsx`'s
exact eight measured cell positions and the same `gta6-wheel-slot` chrome, but
every cell is a plain `free` role — no fist button, no weapon/melee/handheld
restriction, since this tab holds ordinary carried items rather than guns. It
claims its own slot range (8-15), immediately after the weapon wheel's 1-7, so
the two wheels never fight over the same inventory slot. `LeftInventory.tsx`
now renders one wheel or the other depending on the active tab and never the
square grid — a player's own inventory is meant to be nothing but these two
wheels.

The two bottom-left medical quickslots (also `LeftInventory.tsx`) are a
read-only auto-populated readout, not a drop target: whatever medical items
(see `wheelCategories.isMedicalItem`) are already carried outside the two
wheels just show up there on their own, up to two, with no drag-and-drop and
no empty-slot padding — matching the reference, which never draws an empty
holster for a consumable you don't have.

That's backed by a slot/weight cap: without a bag equipped (four items from
[`wasabi_backpack`](https://github.com/wasabirobby/wasabi_backpack) —
`dufflebag`, `backpack`, `rucksack`, `cayoduffel`), a player's own inventory
is hard-capped to 17 slots (the two wheels' 15, plus 2 spare so a newly
picked-up medical item has somewhere to land outside the wheels and actually
reach the quickslot readout — `Inventory.AddItem` fills the first empty slot
it finds, so with the wheels' 15 already full of other things, a fresh
pickup naturally lands in 16 or 17) by `modules/gta6pockets/server.lua`, a
new self-contained module. It hooks
`Inventory.SetSlot` — the one low-level function every add/remove path
(buy, craft, give, drop, swap) funnels through — so picking up or dropping
a bag lifts or reapplies the cap on the same tick, with a slower poll as a
fallback for anything that changes `inv.items` outside that path.
`SetSlotCount`/`SetMaxWeight` only ever change the ceiling number, never
touch existing items, so lowering the cap on an unbagged player can't
delete or hide anything already in slots 1-17. Ship `wasabi_backpack`
separately if you want the cap to ever lift — without it every player
stays capped at 17 slots permanently. The bag item list and the
17-slot/8000-weight cap are both overridable via convars
(`inventory:pocketbags`, `inventory:pocketslots`, `inventory:pocketweight`)
rather than editing the module.

There's also a bottom-right honor badge (`gta6-honor`), fed by `qbx_honor`.
**This is wired up in `ox_inventory/client.lua` itself**, not in
`qbx_honor` — FiveM only lets a resource `SendNUIMessage` its own page, so
`qbx_honor` can't push to ox_inventory's NUI directly. Instead
`ox_inventory/client.lua` listens for the same `qbx_honor:client:syncHonor`
event `qbx_honor` fires for `vice_hud`'s toast, reads
`exports.qbx_honor:GetHonor()` / `GetBadgeTier()`, and relays a `setHonor`
NUI message — guarded so a server without `qbx_honor` just never shows the
badge. Seeded on the NUI's `uiLoaded` callback, not just on change, so it
has a value the moment the page opens. See `client.lua` below.

Source files (for reference / future edits — editing these does nothing on
their own, ox_inventory's web UI is a Vite/React build):

```
patches/ox_inventory/web/src/gta6-theme.scss
patches/ox_inventory/web/src/index.scss
patches/ox_inventory/web/src/components/inventory/InventoryTabs.tsx
patches/ox_inventory/web/src/components/inventory/LeftInventory.tsx
patches/ox_inventory/web/src/components/inventory/WeaponWheel.tsx
patches/ox_inventory/web/src/components/inventory/ItemWheel.tsx
patches/ox_inventory/web/src/components/inventory/InventorySlot.tsx
patches/ox_inventory/web/src/components/inventory/PromptGlyph.tsx
patches/ox_inventory/web/src/components/inventory/PlayerStatusBars.tsx
patches/ox_inventory/web/src/dnd/onDisarm.ts
patches/ox_inventory/web/src/store/honor.ts
patches/ox_inventory/web/src/store/wheelCategories.ts
```

The pocket cap is a whole new module, shipped in full since it adds no stock
files of its own to edit:

```
patches/ox_inventory/modules/gta6pockets/server.lua
```

Copy it into `modules/gta6pockets/server.lua` in your install, then add one
line to `server.lua` (the entry point, not the module itself), right after
the `local Inventory = require 'modules.inventory.server'` line near the top:

```lua
require 'modules.gta6pockets.server'
```

New image asset the fist cell needs (already covered by ox_inventory's own
`'web/images/*.png'` manifest glob, no manifest edit needed):

```
patches/ox_inventory/web/images/fist.png
```

`client.lua` (the Lua entry point, not the web UI) also carries two small
hand-edits, not shipped as a full file here since the rest of it is
unmodified stock `ox_inventory` (2000+ lines). Add these two blocks
yourself — no manifest edit needed, `client.lua` is already declared.

Near the top, after `local currentWeapon`:

```lua
-- Tell the NUI which slot is actually in hand.
--
-- Nothing used to send this, so the weapon wheel had no way to know what was
-- equipped -- it fell back to "the first weapon in the inventory" and labelled
-- that IN HAND whether it was or not. Hooking the event instead of each call
-- site covers Weapon.Equip, Weapon.Disarm and the bare TriggerEvent()s further
-- down this file in one place.
AddEventHandler('ox_inventory:currentWeapon', function(weapon)
    SendNUIMessage({
        action = 'setCurrentWeapon',
        data = weapon and weapon.slot or false,
    })
end)

-- Honor badge (bottom-right of the wheel, see LeftInventory.tsx / store/honor.ts).
--
-- qbx_honor owns the value; this resource only relays it. Guarded so a server
-- without qbx_honor installed just never shows the badge instead of erroring.
local function pushHonor()
	if GetResourceState('qbx_honor') ~= 'started' then return end

	local ok, value = pcall(exports.qbx_honor.GetHonor, exports.qbx_honor)
	if not ok or type(value) ~= 'number' then return end

	local _, tier = pcall(exports.qbx_honor.GetBadgeTier, exports.qbx_honor, value)

	SendNUIMessage({ action = 'setHonor', data = { value = value, tier = tier } })
end

AddEventHandler('qbx_honor:client:syncHonor', pushHonor)
```

In the existing `RegisterNUICallback('uiLoaded', ...)` handler, add the
`pushHonor()` call (seeds the badge the moment the page loads, not just on
the next honor change):

```lua
RegisterNUICallback('uiLoaded', function(_, cb)
	client.uiLoaded = true
	pushHonor()
	cb(1)
end)
```

Already-built output — copy these directly into your `ox_inventory/`
install and it just works, no build step required:

```
patches/ox_inventory/web/build/assets/index-95575c2f.js
patches/ox_inventory/web/build/assets/index-93b7c2d3.css
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
