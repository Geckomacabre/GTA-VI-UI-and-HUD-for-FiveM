# Vendored: ScaleformUI assets (binary)

Source: https://github.com/manups4e/ScaleformUI/releases/download/5.8.1/ScaleformUI_Assets.zip
Release: 5.8.1 (published 2025-08-12T14:50:39Z)
SHA-256: 9beb7c7dae422f70917c277ef4f1584a7f1a48f2f5aa0af6642ee65156a502e0
Fetched: 2026-08-31

License: CC BY-NC-SA 4.0, same as the Lua library, non-commercial only.

Compiled `.gfx` scaleform movies (ActionScript source is
github.com/manups4e/ScaleformUI-Scaleform, not built here). Do not edit these
directly; if a newer release fixes something, re-download and replace this
folder wholesale rather than patching individual files.

Required by [vice_hud](../vice_hud). That resource's `UIMenu` calls resolve
to `stream/ScaleformUI.gfx` here at runtime
(`Scaleform.RequestWidescreen("scaleformui")`). This resource must be
`ensure`d BEFORE vice_hud in server.cfg.
