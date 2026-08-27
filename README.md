# GTA VI Resources

A bundle of every FiveM/Qbox resource on this server that's built around a
GTA VI (Vice City / Leonida) visual identity — a shared HUD, a matching
popup/menu theme spread across a few community resources, a gig-economy
phone app pair, and a reskinned inventory screen. Pulled out of the main
server tree and organized here as a standalone, installable package.

This isn't a public repository — it's laid out like one (clear structure,
README, drag-and-drop instructions) so it's easy to hand off, back up, or
eventually publish, but it currently only exists locally.

## What's in here

```
GTA VI Resources/
├── resources/     Full, self-contained resources. Drag any of these
│                  straight into your server's resources/ folder.
│
├── patches/       NOT standalone resources. Small overlay files that patch
│                  vice_hud's theme into resources you install separately
│                  (ox_lib, ox_target, ox_inventory, qb-menu, qb-input).
│                  See docs/PATCHES.md for exact install steps per resource.
│
└── docs/          Extra documentation, including the patch install guide.
```

Everything under `resources/` is a full copy of that resource as it runs on
this server. Everything under `patches/` is deliberately **not** a full copy
of the resource it touches — those are large, actively-updated community
resources (ox_lib, ox_target, ox_inventory, qb-menu, qb-input) that aren't
"GTA VI resources" in themselves. Only the handful of files this server
changed or added to bring the theme into each one are included here.

### `resources/`

- **`vice_hud`** — The core HUD: minimap, vehicle panel, zone bar, skills,
  stamina/oxygen, notifications, a full in-game HUD editor (`/hudedit`), and
  the theme engine (`/hudtheme`, `/themepublish`) that the `patches/` folder
  plugs into. Has its own `README.md` and `docs/INTERNALS.md` inside —
  start there for anything HUD-specific. Depends on `ox_lib`.

- **`um_gigs`** — "Snarf" and "Ryde Me" (internal name `goober`): two
  parody gig-economy phone apps served through `lb-phone`, styled with the
  same Art Deco / Vice aesthetic as the rest of this set. Depends on
  `ox_lib`, `ox_target`, `qbx_core`, `lb-phone`.

### `patches/`

Theme overlays for resources you already have installed elsewhere:

- **`ox_lib`** — the popup/notification glass theme (`lib.notify`, context
  menus, dialogs, progress bars).
- **`ox_target`**, **`qb-menu`**, **`qb-input`** — each has its own
  `ui_page`, so each needed its own small copy of the same theme hook.
- **`ox_inventory`** — a separate, unrelated GTA6-inspired reskin of the F2
  inventory screen (not part of the vice_hud glass system above).

**Read [`docs/PATCHES.md`](docs/PATCHES.md) before touching any of these** —
each one needs a couple of files copied into an existing install plus a
one- or two-line manifest/HTML edit. None of it is drag-and-drop on its own.

## Installing (drag-and-drop resources)

1. Copy `resources/vice_hud` and/or `resources/um_gigs` into your server's
   `resources/` folder.
2. Add them to `server.cfg`:
   ```
   ensure vice_hud
   ensure um_gigs
   ```
3. Make sure the dependencies each one needs are already installed and
   started *before* it in `server.cfg`:
   - `vice_hud` needs **ox_lib**.
   - `um_gigs` needs **ox_lib**, **ox_target**, **qbx_core**, **lb-phone**.
4. Restart the resource (or the server) and confirm it starts clean in the
   server console.

`vice_hud` ships its own `README.md` with the full command list
(`/hudedit`, `/hudreset`, `/hudtheme`, `/themepublish`, etc.) — read that
once it's installed.

## Installing (theme patches)

These are not resources — do not `ensure` a `patches/` folder. Follow
[`docs/PATCHES.md`](docs/PATCHES.md), which walks through each of `ox_lib`,
`ox_target`, `ox_inventory`, `qb-menu`, and `qb-input` individually: which
files to copy in, and the exact manifest/HTML lines to add.

An update to any of those five resources will silently wipe its patch —
that's expected, and `PATCHES.md` says so per-resource. Re-apply after
updating.

## The arista-pro font

`resources/um_gigs/ui/fonts/arista-pro.pro-trial-regular.ttf` is bundled and
registered via `@font-face` in `ui/app.css` under the family name
`'Arista Pro'`, and listed in `fxmanifest.lua`'s `files{}` so FiveM actually
ships it to clients. Neither app currently points `--font-body` at it —
Ryde Me still uses GTAArtDeco, Snarf still uses the system font stack — the
font is just present and ready to use if you want to switch either app's
`--font-body` to `'Arista Pro'`.

## Notes

- This bundle was assembled from a live server tree; nothing here has its
  own separate issue tracker or release process. Version numbers noted in
  `docs/PATCHES.md` are what each patch was built and tested against.
- `resources/vice_hud` carries its own `.gitignore` (excludes
  `node_modules/`, its Python asset-prep tooling's `__pycache__/`, and raw
  pre-conversion texture originals) — respect it if you re-copy from the
  live server later rather than flattening everything in.
