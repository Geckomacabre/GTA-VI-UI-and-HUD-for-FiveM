# qbx_honor

RDR2-style persistent honor stat for qbx_core. Stored as `metadata.honor` on the player,
range `Config.MinHonor` to `Config.MaxHonor` (default -100 to 100), neutral default
`Config.DefaultHonor` (0). Seeded on first `QBCore:Server:PlayerLoaded` if not already
present, exactly like qbx_core seeds its own metadata defaults (`server/player.lua`).

## Hooks

Every honor change comes through a **named hook** defined in `Config.Hooks`, applied with
a single export:

```lua
exports.qbx_honor:ApplyHook(source, 'house_robbery')
```

The call site carries no numbers. Amount (`delta`), rate limit (`cooldownMs`) and
anti-farm ceiling (`sessionCap`) all live in `config.lua`, so rebalancing never means
editing Lua in an unrelated resource. Unknown hook names print a warning and do nothing.

`cooldownMs` and `sessionCap` are per-player *and* per-hook, held in memory, and cleared
on disconnect. A hook with neither fires every time it is called -- which is why the
per-passenger and per-pickpocket hooks below have them and the once-per-heist ones don't.

### Where each hook fires

| Hook | Fires when | Lives in |
|---|---|---|
| `wanted_level` | wanted stars increase | this resource (`client/main.lua`) |
| `kill_civilian` | you kill an unarmed, non-aggressive ped | this resource (`client/conduct.lua`) |
| `kill_animal` | you kill a harmless animal | this resource (`client/conduct.lua`) |
| `aim_at_civilian` | you point a gun at a civilian (off by default) | this resource (`client/conduct.lua`) |
| `greet_npc` | "Greet" ox_target option on a civilian | this resource (`client/conduct.lua`) |
| `antagonize_npc` | "Antagonize" ox_target option on a civilian | this resource (`client/conduct.lua`) |
| `fish_release` | you put a landed fish back | `fusion_fishing/server/fishing.lua` |
| `geocache` | cache found or traded | `qbx_geocaching/server/main.lua` |
| `bounty` | lawful bounty collected | `qbox_bounties/server/main.lua` |
| `church_job` | church job completed | `um_beg/server/church.lua` |
| `odd_job` | odd job completed | `um_beg/server/main.lua` |
| `honest_work` | legal route work paid out | `um_busjob`, `um_taxijob`, `um_garbagejob`, `um_truckerjob` |
| `barn_find` | derelict restored rather than stripped | `qbox_barnfinds/server/main.lua` |
| `jewelry_heist` | vitrine robbed | `jewelery_heist/server/main.lua` |
| `window_smash` | locked vehicle's window put through | `qbx_vehiclekeys/server/main.lua` |
| `house_robbery` | stolen household goods fenced | `um_HouseRobberys/server/s_server.lua` |
| `truck_robbery` | blown armoured truck looted | `um_truckrobbery/server/main.lua` |
| `chop_shop` | cash taken for a stripped stolen car | `caticus-chopshop/server/sv_main.lua` |
| `pawn_melt` | jewellery melted down | `um_pawnshop/server/main.lua` |
| `hobo_fence` | goods moved through the fence | `um_beg/server/main.lua` |
| `pickpocket` | a stranger's pocket picked | `um_beg/server/main.lua` |

Every external call site is wrapped in `pcall`, so stopping qbx_honor degrades those
resources to their normal behaviour instead of erroring.

## Conduct watcher

`client/conduct.lua` is the RDR2-shaped half: honor reacts to how you treat the people
and animals around you, with no dependency on any other resource. Tuned under
`Config.ConductWatcher`.

- **Killing bystanders and harmless animals costs honor.** `civilianPedTypes` decides who
  counts -- civilians, emergency services, the homeless -- and deliberately excludes gang
  and criminal ped types, which are free.
- **Self-defence is free.** Any ped that damaged you within `selfDefenceGraceMs` (25s) is
  an aggressor, and killing it costs nothing. Peds that die holding a weapon are also
  treated as fair game (`armedPedsAreFairGame`) -- a heuristic, since a dead ped drops its
  weapon quickly; the grace window is the reliable half of the check.
- **Greet / Antagonize** are `ox_target` options on any ped (target it, pick the option).
  Greet waves and ticks honor up (`Config.Hooks.greet_npc`); Antagonize intimidates and
  ticks honor down (`Config.Hooks.antagonize_npc`). Both read the player's own
  `qbx_reputation` standing if that resource is running, so a well-known criminal gets
  flinched away from on a Greet and bolted from harder on an Antagonize.
- **`penaliseAiming`** (off by default) docks honor for pointing a gun at a civilian. It
  fires on a very common action and gets noisy -- turn it on for a stricter server.

The client never decides amounts or timing. It names what happened
(`qbx_honor:server:reportConduct`) and the server decides whether that hook may fire,
against an allowlist plus the usual cooldowns and caps. Ambient peds are client-owned and
gone by the time the server hears about a kill, so there is no way to re-validate one --
the allowlist and throttles are the defence.

## Catch and release

`fusion_fishing` gained a Keep / Put it back prompt on every landed fish. Keeping it is
the old behaviour exactly -- item, full XP, **no honor change either way**. Releasing gives
up the fish and the sale for `Config.release.xpMultiplier` of the XP plus the
`fish_release` hook. The prompt is asked *before* the inventory check, so a full cooler is
never a reason you cannot put a fish back. Any dismissed or interrupted dialog keeps the
fish.

## Server exports

```lua
-- The one other resources should use.
exports.qbx_honor:ApplyHook(source, hookName)

-- Raw adjustment, no hook, no throttle. Prefer ApplyHook.
exports.qbx_honor:AddHonor(source, amount)     -- amount treated as positive
exports.qbx_honor:RemoveHonor(source, amount)  -- amount treated as positive, subtracted
exports.qbx_honor:AdjustHonor(source, delta)   -- signed

exports.qbx_honor:GetHonor(source)
exports.qbx_honor:GetBadgeTier(value)          -- 'angel' | 'devil' | nil
exports.qbx_honor:IsHonorBroken(source)        -- see "Unrepairable floor" below
```

## Client exports

```lua
-- Local player's current honor. Seeded from the server on spawn / resource start
-- and kept current by the honorUpdated event, so it never needs a round-trip.
exports.qbx_honor:GetHonor()

-- 'angel' | 'devil' | nil for a given value, defaulting to the local player's honor.
exports.qbx_honor:GetBadgeTier(value)

-- Same story as GetHonor() -- cached client-side, no round-trip.
exports.qbx_honor:IsHonorBroken()
```

`qbx_vehiclekeys` reads these client-side to scale how long a window smash takes and how
likely the police alert is.

## Unrepairable floor

Hitting `Config.MinHonor` isn't just "very devil" -- it's permanent. The moment
`AdjustHonor` clamps a character's honor to the floor, `metadata.honorBroken` latches
`true` and **never clears**, not even if honor is later raised back up by good conduct.
It's a wall, not a second threshold: there's nothing to tune here beyond `MinHonor` itself
and the hooks that move honor toward it.

`IsHonorBroken()` is deliberately a separate question from `GetHonor()` / `GetBadgeTier()`
-- the honor number can still move for anything else that reads it, only "can this
character's reputation ever look normal again" is permanently answered. vice_hud reads
this flag alongside the honor value (`ShowHonorToast`/`SetHonorStanding`'s trailing
`broken` argument, both now accept one) and renders the devil badge grey and cracked from
then on, independent of whatever the raw number does afterward.

## vice_hud

The HUD side goes through vice_hud's documented API. vice_hud draws **two separate
things** from one push, and they are not the same thing:

- **The corner panel.** Mugshot, the badge face for the current tier, and (with
  `Config.Honor.showValue`) the numeric value and the reason. Shown when honor moves,
  hidden again after `Config.Honor.holdMs` (6s). This is where you read your level.
- **The centre-screen +/− indicator -- the change.** ~2.2s. Drawn only when vice_hud
  computes a non-zero delta against the last value it saw, with the face for the
  *direction* honor moved.

**Neither is permanent, on purpose.** An always-on honor panel is clutter; you get the
readout when something actually happens. `Config.Honor.holdMs = 0` in vice_hud restores
the always-on behaviour if you ever want it.

```lua
exports.vice_hud:ShowHonorToast(mugshot, honor, emoji, reason)
```

qbx_honor passes **`nil` for `emoji` on purpose**. vice_hud picks the standing face from
its own `Config.Honor` thresholds (mirroring this resource's) and the direction face for
the indicator separately. This resource used to pass the direction face, which forced the
standing badge to show it too -- so the corner panel disagreed with the player's actual
tier on every single change. Do not put it back.

`reason` is the `label` from the hook that fired (`Config.Hooks.<name>.label`), e.g.
"Killed a bystander". It shows under the value for as long as the panel is up.

On spawn -- and whenever vice_hud restarts -- this resource calls
`exports.vice_hud:SetHonorStanding(honor)` instead, which **seeds the value without
drawing anything**. vice_hud measures the delta that fires the +/− indicator against the
last value it saw, so it needs the spawn value; but a player who has not done anything yet
should not get a panel popped at them for it. Use `ShowHonorToast` for events,
`SetHonorStanding` for state.

`Config.AngelThreshold` / `Config.DevilThreshold` define the tiers and are mirrored in
`vice_hud/config.lua` as `Config.Honor.angelAt` / `devilAt`. **Keep the two in sync** --
nothing enforces it, and they will silently disagree.

## Not hooked (see task report for full reasoning)

`wasabi_ambulance` / `envi-medic` player revives were NOT hooked: their core logic ships
as pre-compiled/obfuscated FXAP bytecode in this repo, so there is no readable server-side
event carrying both the reviver's and the patient's source id to hook cleanly. Same for
`um_rob_atm`, `loaf_storerobbery`, `loaf_bankrobbery` and `rcore_prison` -- all escrowed.
Wiring any of them would require guessing at or patching compiled bytecode, which this
resource deliberately avoids.

## Server.cfg

Started as part of `ensure [standalone]`.
