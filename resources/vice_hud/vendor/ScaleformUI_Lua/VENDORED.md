# Vendored: ScaleformUI (Lua)

Source: https://github.com/manups4e/ScaleformUI (upstream; QuadrupleTurbo's
fork the Discord dev linked is the same project).
Path taken: `ScaleformUI_Lua/src/**`
Commit: 5b1f8b83bbd49036b454fbcf32e122284854337f
Fetched: 2026-08-31

License: CC BY-NC-SA 4.0 (per upstream README) — non-commercial only. Do not
sell or bundle this resource in anything paid while this dependency is in
place; credit the upstream repo if distributing.

## Still required, NOT included here

The compiled `.gfx` scaleform movie itself ships separately as
`ScaleformUI_Assets.zip` from the same repo's GitHub Releases. It has to be
installed as its OWN FiveM resource (streamed assets need their own resource
manifest) and `ensure`d in server.cfg alongside this one. Nothing in this
vendor/ directory will render without it.

## Not modified

Everything under `src/` is the upstream source unmodified. If it ever needs
a local patch, note the change here rather than silently diverging so a
future update from upstream doesn't clobber it.
