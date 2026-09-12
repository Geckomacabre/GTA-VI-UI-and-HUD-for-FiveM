# gk_pausemenu

A custom NUI pause menu that takes over the native ESC menu with a dashboard
UI: sidebar profile/stats/OOC chat, navbar, Player Details/Report/Patch Notes
cards, and footer icons, themed to match `vice_hud` (self-hosted
GTAArtDeco/Pricedown fonts, its `.plate` glass surface, gender-based accent
colour). Map, Settings and Keybinds all hand off to the real native frontend
screens rather than any custom NUI — see `client/main.lua` for why.

No hard dependency on `vice_hud`, `qbx_core`, or `MugShotBase64`; defers to
each cooperatively when running. Depends on `ox_lib`.

## Credit

The dashboard layout (sidebar/navbar/cards/footer) is reskinned on top of
[SY_PauseMenu](https://github.com/syno-sy/SY_PauseMenu) by
[syno-sy](https://github.com/syno-sy), licensed GPL-3.0. This resource
carries the same license — see [`LICENSE`](LICENSE).

## Superseded resource

An earlier, self-drawn-map version of this resource lives under
[`resources/_retired/gk_pausemenu`](../_retired/gk_pausemenu) for reference.
It's no longer maintained — use this one.
