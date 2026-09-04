# qbx_relog

Singleplayer-style character switching for Qbox. Two entry points:

- **`/relog`**: the classic command, unchanged in spirit. Confirmation
  dialog, a short anti-combat-log wait, then back to qbx_core's
  multicharacter picker.
- **Hold `B`**: the switcher. A row of portrait cards appears in the
  bottom-right with your other characters' faces on them. Cycle with the
  mouse, the scroll wheel, or the arrow keys, then release to switch.
  The switch itself is the engine's real singleplayer cinematic: up into
  the clouds, character swapped while the camera is up there, descend onto
  the new character wherever they last logged out. No loading screen.

## Requirements

- `ox_lib`
- `qbx_core`, **with the small patch in `patches/qbx_core`** (see the main
  README and `docs/PATCHES.md`). Without it, the quick-switch wheel fights
  with qbx_core's own character-select screen and this resource refuses to
  run, printing an explicit error to F8 telling you what's missing.

Optional:

- `illenium-appearance`: gives the portrait cards real faces instead of
  initials. Every call into it is guarded, so a missing appearance resource
  just degrades to initials rather than erroring.
- `vice_hud`: the switcher's panel is styled to match vice_hud's own glass
  material and picks up its theme colors when it's running. Looks fine on
  its own if vice_hud isn't installed.
- `qbx_honor`: shows an honor chip on each portrait card, using the same
  angel/devil thresholds as vice_hud and qbx_honor. Configure the two
  thresholds in `config.lua` to match whatever you have qbx_honor set to.

## Configuration

Everything tunable lives in `config.lua`, commented inline: the relog
cooldown and anti-combat-log delay, the wheel's hold key and hold time, its
corner position and sensitivity, the switch delay, and the honor
thresholds. A few defaults worth knowing before you go looking for bugs:

- `Config.cooldown` and `Config.delay` are 0 and 10 seconds by default.
  Switching right after a switch, or acting right before one, is blocked on
  purpose.
- `Config.switchDelay` (5 seconds) is the progress bar shown before the
  quick-switch camera moves. Cancel it and the switch aborts.
- The character you're currently on can't be selected in the wheel by
  design. It stays visible on the strip, just not selectable, so you can
  always see who you are.
- Portraits build a few seconds after your character loads. Before that,
  cards show initials instead of a face.

## Notes

- The wheel never takes NUI focus, so your mouse and keys keep controlling
  the game while it's open. Releasing the hold key is what confirms a
  switch.
- The game only allows one transparent headshot texture to exist at a time,
  so portraits are built and released one at a time rather than kept
  registered. If you ever see one character's card losing its face when
  another one loads, that behavior regressed and is worth a bug report.
