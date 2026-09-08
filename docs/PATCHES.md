# Applying the patches

Everything under `resources/` is a complete, self-contained resource — drag
it into your server's `resources/` folder, add it to `server.cfg`, done.

Everything under `patches/` is **not** a resource on its own. Each folder is
a small set of files that overlay onto a resource you already have installed
(ox_lib, ox_target, qb-menu, qb-input, speedlimits, zseatbelt,
qbx_smallresources, dpclothing, lb-phone) to connect it to vice_hud. Copy the
files into place, then make the one- or two-line edit shown below for that
resource.

`ox_inventory` is the one exception: its GTA6 weapon/item wheel reskin ships
as a full resource, `resources/ox_inventory`, not a patch here — a fragment
patch against it broke the first time stock `overextended/ox_inventory`
restructured its own components underneath it, so this repo now carries a
whole pinned copy of `communityox/ox_inventory` 2.45.0 with the reskin
already built in. Drop-in replace your existing `ox_inventory` install with
it instead of patching. See its entry in the main `README.md` for what it
needs (`dpclothing`, below, is still relevant for its clothing toggle
cells).

`lb-phone` is the one exception to "connect it to vice_hud" above; its patch
is a standalone rebrand of that resource's own Wallet app (see the lb-phone
section below) and doesn't touch vice_hud at all. It's grouped here anyway
because lb-phone is paid, so, same as every other patch, only the handful of
files actually changed are included, never the resource itself.

Most of these are presentational only — a stylesheet plus a script that
listens for a theme broadcast from vice_hud. Two are not: `speedlimits` and
`zseatbelt` are **positioning hooks** (they let vice_hud's `/movehud` editor
move that resource's own on-screen icon, which vice_hud otherwise has no way
to reach since each one draws through its own NUI page rather than
vice_hud's), and `qbx_smallresources` is a **functional conflict fix** (a
competing script that resets player stamina every 500ms, which pins vice_hud's
stamina bar at full and makes it look broken).

**Version pinned against:** ox_lib 3.32.3, ox_target 1.18.0, qb-menu 1.2.0,
qb-input 1.2.0, speedlimits 1.2.0, zseatbelt 1.1.0-um, dpclothing 1.0.3.
(`resources/ox_inventory` carries its own pin, 2.45.0, since it's a full
resource rather than a patch — see above.)
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

Two independent patches live here now: the original theme hook (below), and
a much bigger one that replaces ox_target's own eye + option-list NUI
outright with vice_hud's textui/menu system.

### Theme (presentational only)

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

If you only want the theme (ox_target keeps its own eye + list UI, just
recoloured to match), stop here and skip the textui migration below.

### textui migration (replaces ox_target's own UI)

**Not presentational, and not just a UI swap.** Two behaviour changes:

1. **No more keybind.** Upstream only raycasts while holding (or, with
   `ox_target:toggleHotkey`, after pressing) Alt. This patch removes that
   gate entirely — targeting runs continuously, so a prompt just appears
   when you're looking at something in range, GTA VI/RDR2 style, with
   nothing to hold first. Still fully **aim-based**: the raycast/option-
   resolution engine itself is untouched, this only removes the key that
   used to have to be held before any of it ran. `ox_target:toggleHotkey`
   is no longer read at all.
2. **Different UI.** What happens once a target's visible options are known
   no longer sends anything to ox_target's own web page. Instead it calls
   straight into vice_hud:
   - **1 visible option** → `exports.vice_hud:ShowActionPrompt`, a hold-to-
     confirm "[key] Label" textui prompt instead of a click-to-open
     one-item list. Hold duration is tunable via the
     `ox_target:textUiHoldMs` convar (default 350ms).
   - **2+ visible options** → `exports.vice_hud:OpenInteractMenu`, the same
     ScaleformUI list `qbx_vehiclekeys`' Slim Jim menu already uses (see
     that resource's `README.md`), instead of ox_target's own list.

Because neither of those needs NUI focus, ox_target never grabs the mouse
cursor for targeting any more either — confirming is the same `mouseButton`
control the server already used (`ox_target:leftClick`), just held instead
of clicked.

Targeting now running continuously rather than only during a held-key
session is a real, deliberate performance/behaviour tradeoff, not an
oversight — see the `-- Always-on` comment in the file for the reasoning,
and the CreateThread overlay comment for why firing/melee suppression had
to become conditional on an actual prompt being up rather than unconditional
for the whole scan loop (upstream's version would otherwise have
permanently disabled combat once this always-on).

**Requires vice_hud 2.1.0+** (this repo's copy already has it) — specifically
`ShowActionPrompt`'s `opts.hold`/`opts.onHeld` and `OpenInteractMenu`'s
`token` parameter, neither of which existed before. Running this patch
against an older vice_hud will error the first time a target resolves.

Replace, don't copy alongside:

```
patches/ox_target/client/main.lua
patches/ox_target/client/main.lua.pre-vice_hud   (restore point -- the un-patched original)
```

No `fxmanifest.lua` edit needed — same filename, same file list. The theme
patch above still applies on top of this one; they don't conflict.

If your `ox_target` version differs from 1.18.0, diff `main.lua.pre-vice_hud`
against your own `client/main.lua` first — this patch touches option
dispatch, menu/submenu bookkeeping, and the `startTargeting` control loop
directly (not just an appended block), so a shape change upstream needs a
hand-merge rather than a drop-in copy. See the `-- vice_hud textui
migration` comments inside the file for exactly what moved and why.

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

## dpclothing

[dpClothing+](https://forum.cfx.re/t/5158019) by dullpear. Two exports
appended to the end of `Client/Clothing.lua`, needed by the mask/hat/eyewear
cells on ox_inventory's ITEMS wheel above. dpclothing tracks worn items as
ped props (hat, glasses) and a drawable component (mask), toggled on and
off, rather than as inventory items, so this is the only way ox_inventory's
NUI can reach that state without knowing about drawable/prop IDs itself.

Copy into your `dpclothing/` install:

```
patches/dpclothing/Client/Clothing.lua
```

This is the full file, not a hand-edit snippet, since the only change is
two `exports(...)` calls appended at the very end: `ToggleClothingWheelSlot(role)`
dispatches to the resource's own `ToggleClothing('Mask')` / `ToggleProps('Hat'
| 'Glasses')`, and `GetClothingWheelState()` reads the on/off state straight
off the ped (`GetPedDrawableVariation`/`GetPedPropIndex`) rather than off
this resource's own internal bookkeeping, so it stays correct even if a
mask/hat/glasses changes through some other resource (a clothing store,
a character reload).

## qbx_core

Not theming, a functional requirement for `qbx_relog` (bundled under
`resources/`, see its own README). Two small exports and a one-line check
in the multicharacter flow, appended to `client/character.lua`. Without
this, `qbx_relog`'s quick-switch fights with the normal character-select
screen and refuses to run (it checks for these exports at startup and
prints an explicit error to F8 if they're missing).

Add near the top of `client/character.lua`, after
`if config.characters.useExternalCharacters then return end`:

```lua
local skipNextCharacterSelect = false

---Skip the multicharacter select screen the next time the player logs out.
---Consumed once. For resources that log a player straight into a different
---character instead of returning to the picker (e.g. qbx_relog's quick-switch).
exports('SkipNextCharacterSelect', function()
    skipNextCharacterSelect = true
end)
```

Just above `RegisterNetEvent('qbx_core:client:spawnNoApartments', ...)`,
right after the end of the `chooseCharacter` function:

```lua
---Fallback for a skipped character select that didn't get a character loaded
---(e.g. qbx_relog's quick-switch failed after the skip flag was already set).
exports('OpenCharacterSelect', chooseCharacter)
```

In the existing `RegisterNetEvent('qbx_core:client:playerLoggedOut', ...)`
handler, add the flag check right after the invoking-resource guard:

```lua
RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    if GetInvokingResource() then return end -- Make sure this can only be triggered from the server

    if skipNextCharacterSelect then
        skipNextCharacterSelect = false
        return
    end

    chooseCharacter()
end)
```

That's the whole patch, three small additions to one file. Version pinned
against `qbx_core` as of this repo's last commit; check the target file
still matches the snippets above before pasting in if your copy is far
ahead or behind.

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

## qbx_smallresources (Stamina)

Not a theme patch — a **functional conflict fix**. [Qbox-project/qbx_smallresources](https://github.com/Qbox-project/qbx_smallresources)
bundles a `Stamina` script that calls `ResetPlayerStamina()` every 500ms to
give infinite stamina. That pins `GetPlayerSprintStaminaRemaining()` at full
faster than it can ever drain, so vice_hud's stamina bar reads "full"
forever and looks broken — it isn't; there's just nothing for it to read.

If you run `qbx_smallresources` alongside vice_hud, replace:

```
patches/qbx_smallresources/Stamina/client.lua
```

The original — the infinite-stamina version — sits beside it as
`client.lua.pre-vice_hud` if you'd rather keep infinite stamina and just
remove vice_hud's stamina bar instead (`Config.Stamina` in `vice_hud`).

No `fxmanifest.lua` edit needed — same filename, same file list.

## lb-phone (BuckMe)

Rebrands lb-phone's stock Wallet app into "BuckMe": a Vice-styled debit card
(front, a tap-to-flip back with a real signature and CVV), a purple accent
scoped to just this one app, a bottom tab bar (Main / Pay / History), and a
Pay/Request toggle on the send screen (Request is UI only for now — there's
no request-money backend in lb-phone to hook into).

**Version pinned against:** lb-phone 2.8.3. The two `Wallet-*` files under
`ui/dist/assets/` are lb-phone's own Vite build output with content-hashed
filenames — a different lb-phone version will ship different hashes and a
different (minified) file, so these are a reference to hand-merge from
rather than something to drop in blind.

Copy into your `lb-phone/` install:

```
patches/lb-phone/server/apps/framework/wallet.lua
patches/lb-phone/ui/dist/assets/Wallet-Da9Ipi6P.js
patches/lb-phone/ui/dist/assets/Wallet-BB8GWuDZ.css
patches/lb-phone/ui/dist/assets/img/card.png
patches/lb-phone/ui/dist/assets/img/card-back.png
patches/lb-phone/ui/dist/assets/img/buckme-logo.png
patches/lb-phone/ui/dist/assets/img/icons/apps/Wallet.jpg
patches/lb-phone/ui/dist/assets/fonts/buckme/GTAArtDecoMedium.ttf
patches/lb-phone/ui/dist/assets/fonts/buckme/GTAArtDecoRegular.ttf
patches/lb-phone/ui/dist/assets/fonts/buckme/CedarvilleCursive-Regular.ttf
patches/lb-phone/config/locales/en.json
```

No `fxmanifest.lua` edit needed — lb-phone's manifest already ships
`ui/dist/**/*` as one glob, so the new image and font files are picked up
automatically.

`wallet.lua` adds two new callbacks, `wallet:getCardholderName` and
`wallet:getCardDetails`, both read by the client on load. Cardholder name
comes straight from `GetCharacterName` (framework-provided — qbox, qb, esx,
and standalone each define their own, so this works regardless of which one
your server runs). The card number's last 4 digits and CVV are generated
from `GetIdentifier` (the framework's persistent account id — citizenid for
qbox) run through a small deterministic hash, so they're stable for that
character across logins without needing a new database column, and unique
per account rather than per phone number.

`en.json` only changes two keys — `Wallet` (the home-screen app label) and
`WALLET.TITLE` (the in-app header) — both to `BuckMe`. Everything else in
the file is stock lb-phone; diff before overwriting if you've made your own
locale edits elsewhere in it.

If you swap in different card art later, the signature and card number/CVV
are live overlays positioned by CSS percentage to match `card.png`'s masked
number row and `card-back.png`'s blank signature strip — new art needs
those percentages (`.card-number`, `.card-signature-strip`, `.card-cvv` in
`Wallet-BB8GWuDZ.css`) nudged to match wherever the new art puts them, they
won't move on their own.
