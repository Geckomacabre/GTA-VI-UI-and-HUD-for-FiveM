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
on disconnect. A hook with neither fires every time it is called — which is why the
per-passenger and per-pickpocket hooks below have them and the once-per-heist ones don't.

### Where each hook fires

| Hook | Fires when | Lives in |
|---|---|---|
| `wanted_level` | wanted stars increase | this resource (`client/main.lua`) |
| `kill_civilian` | you kill an unarmed, non-aggressive ped | this resource (`client/conduct.lua`) |
| `kill_animal` | you kill a harmless animal (skipped if the ped's `legitGame` state bag is set - see `um_hunting`) | this resource (`client/conduct.lua`) |
| `kill_cop` | you kill a COP-type ped, full stop - no self-defence/armed-ped exemption | this resource (`client/conduct.lua`) |
| `kill_player` | you kill another player (self-defence still exempt; the armed-ped heuristic deliberately is not applied, since in a firefight everyone is armed) | this resource (`client/conduct.lua`) |
| `carjack` | you drag a driver out of their car (`IS_PED_JACKING`; an empty parked car is `window_smash` instead) | this resource (`client/conduct.lua`) |
| `complied_with_police` | you pull over for a ticket, or submit to arrest, instead of running or fighting | `fenix-police/server/server.lua`, `um_livingworld/arrest/server/main.lua` |
| `store_robbery` | a store till/safe pays out | `loaf_storerobbery/server/framework/qbox.lua` |
| `atm_robbery` | an ATM is cracked | `um_rob_atm/bridge/qb/server.lua` |
| `bank_robbery` | a bank job pays out | `loaf_bankrobbery/server/framework/qbox.lua` |
| `drug_deal_rejected` | a buyer refuses the sale (a *clean* sale has no hook at all) | `tk_drugs/client/main_editable.lua` |
| `drug_deal_caught` | a buyer calls the police on you | `tk_drugs/client/main_editable.lua` |
| `aim_at_civilian` | you point a gun at a civilian (off by default) | this resource (`client/conduct.lua`) |
| `greet_npc` | "Greet" ox_target option on a civilian | this resource (`client/conduct.lua`) |
| `antagonize_npc` | "Antagonize" ox_target option on a civilian | this resource (`client/conduct.lua`) |
| `fish_release` | you put a landed fish back | `fusion_fishing/server/fishing.lua` |
| `geocache` | cache found or traded | `qbx_geocaching/server/main.lua` |
| `bounty` | lawful bounty collected | `qbox_bounties/server/main.lua` |
| `church_job` | church job completed | `um_beg/server/church.lua` |
| `odd_job` | odd job completed | `um_beg/server/main.lua` |
| `honest_work` | legal route/labour work paid out | `um_busjob`, `um_taxijob`, `um_garbagejob`, `um_truckerjob`, `oil_rigging/server/main.lua`, `wreck_salvage/server/main.lua` |
| `barn_find` | derelict restored rather than stripped | `qbox_barnfinds/server/main.lua` |
| `vending_robbery` | broke into a real vending machine | `petty_crime/server/main.lua` |
| `meter_theft` | broke into a real parking meter | `petty_crime/server/main.lua` |
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

### Adding the call sites yourself

Any hook whose "Lives in" column names another resource has to be wired up there by
hand. Those resources are third party, several of them paid, so they are not
redistributable here and this repo ships only the hook definitions. Each one is a single
line, and every one is wrapped in `pcall` so the host resource behaves exactly as before
if qbx_honor is stopped or not installed.

Server side, where you already have the player's server id:

```lua
pcall(function() exports.qbx_honor:ApplyHook(source, 'store_robbery') end)
```

Put it where the crime actually pays out rather than where it starts, so a robbery
someone walks away from halfway through does not count. In practice that means:

| Resource | Where | Hook |
|---|---|---|
| `loaf_storerobbery` | `server/framework/qbox.lua`, at the end of `GiveMoney` | `store_robbery` |
| `loaf_bankrobbery` | `server/framework/qbox.lua`, at the end of `GiveMoney` | `bank_robbery` |
| `um_rob_atm` | `bridge/qb/server.lua`, inside `atmRobbed` | `atm_robbery` |
| `fenix-police` | `server/server.lua`, in the `issueTicket` handler | `complied_with_police` |
| `um_livingworld` | `arrest/server/main.lua`, in `processArrest` | `complied_with_police` |

All five of those files sit outside the escrowed part of their resource, so this is
ordinary configuration rather than patching compiled code. The loaf scripts expose them
through their own `escrow_ignore` list precisely so they can be edited.

Client side there is no `source`, so report the deed instead and let the server decide
whether it is allowed:

```lua
TriggerServerEvent('qbx_honor:server:reportConduct', 'drug_deal_rejected')
```

`tk_drugs` is the one that ships this way. Its `client/main_editable.lua` is an editable
file the resource provides for exactly this kind of thing, and the two functions to add
to are `PlayRejectSaleVoiceLine` (the buyer refuses) and `PlayAlertPoliceVoiceLine` (the
buyer calls the police). A clean sale gets no hook, which is the whole point: dealing
only costs you when it goes wrong in public.

Only the names in `reportableHooks` (`server/main.lua`) are accepted from a client, so
adding a new client-reported hook means adding it there too. The amount and the throttle
always stay server side.

### Severity

Every hook also carries a `severity` - `'good'`, `'bad'`, or `'terrible'` - which picks
which of vice_hud's three faces the centre-screen change indicator shows for that
specific deed. This is independent of the tier badge in the corner, which always reflects
current *standing* (angel/devil/neutral off `AngelThreshold`/`DevilThreshold`), never the
deed that just happened - and independent of the delta's sign or size, so a small
`terrible`-tagged hook still pops the terrible face and a large `bad`-tagged one still
doesn't. A hook that omits `severity` falls back to plain `'good'`/`'bad'` by the sign of
its `delta` (see `AdjustHonor` in `server/main.lua`) - `'terrible'` is only ever reached by
a hook that explicitly asks for it.

The rough shape of the table: **killing is terrible** (`kill_civilian`, `kill_cop`), **theft
is bad** (`pickpocket`, `window_smash`, `carjack`, `house_robbery`, `chop_shop`,
`meter_theft`...), and **robbery is bad until it turns violent** — see Escalation below.

### Escalation

A hook can declare an `escalate` block, which replaces its `delta`, `label` and `severity`
whenever `Config.Escalation` matches at the moment it fires:

```lua
jewelry_heist = { delta = -8, label = 'Robbed a jeweller', severity = 'bad',
    escalate = { delta = -16, label = 'Robbed a jeweller at gunpoint', severity = 'terrible' } },
```

Two conditions, both checked server-side in `ApplyHook` against state the server already
has, so the robbery script itself never has to report anything:

- **`whenWanted`** — the player has a wanted level right now. qbx_honor's own client
  watcher reports every change (up *and* down, so the flag clears when the stars do).
- **`whenRecentKill`** — the player set off `kill_civilian`/`kill_cop`
  (`Config.Escalation.violentHooks`) within `recentKillWindowMs` (3 min).

Escalation swaps the amount, reason and severity but **not** the throttles — cooldown and
session-cap bookkeeping stay keyed to the base hook name, so a robbery can't be farmed by
alternating calm and escalated versions of itself.

The `kill_cop` / `complied_with_police` pair is the one genuinely new distinction here,
not just a relabel: a cop killed while you're wanted used to cost **nothing** if they'd
shot at you first, because `kill_civilian`'s self-defence exemption (25s grace window)
didn't distinguish "an officer doing their job against a wanted suspect" from "a random
mugger." `kill_cop` skips that exemption entirely - COP-type peds are checked before the
civilian branch in `classifyKill()` (`client/conduct.lua`) - so fighting cops you attracted
is always `terrible`. `complied_with_police` is the other side of that same choice:
pulling over for a ticket (`fenix-police:server:issueTicket`) or submitting to arrest
(`um_livingworld/arrest`'s `qbx_arrest:server:reportArrest`) rewards surrendering instead.

## Conduct watcher

`client/conduct.lua` is the RDR2-shaped half: honor reacts to how you treat the people
and animals around you, with no dependency on any other resource. Tuned under
`Config.ConductWatcher`.

- **Killing bystanders and harmless animals costs honor.** `civilianPedTypes` decides who
  counts — civilians, emergency services, the homeless — and deliberately excludes gang
  and criminal ped types, which are free.
- **Killing a cop always costs honor, full stop.** `copPedTypes` is checked before the
  civilian branch in `classifyKill()`, so a COP-type ped never falls into the
  self-defence/armed-ped exemptions below — an officer who shot at you first while you were
  wanted is not "an aggressor" in the sense those exemptions exist for.
- **Self-defence is free (for non-cops).** Any ped that damaged you within
  `selfDefenceGraceMs` (25s) is an aggressor, and killing it costs nothing. Peds that die
  holding a weapon are also treated as fair game (`armedPedsAreFairGame`) — a heuristic,
  since a dead ped drops its weapon quickly; the grace window is the reliable half of the
  check.
- **Greet / Antagonize** are `ox_target` options on any ped (target it, pick the option).
  Greet waves and ticks honor up (`Config.Hooks.greet_npc`); Antagonize intimidates and
  ticks honor down (`Config.Hooks.antagonize_npc`). Both read the player's own
  `qbx_reputation` standing if that resource is running, so a well-known criminal gets
  flinched away from on a Greet and bolted from harder on an Antagonize.
- **`penaliseAiming`** (off by default) docks honor for pointing a gun at a civilian. It
  fires on a very common action and gets noisy — turn it on for a stricter server.

The client never decides amounts or timing. It names what happened
(`qbx_honor:server:reportConduct`) and the server decides whether that hook may fire,
against an allowlist plus the usual cooldowns and caps. Ambient peds are client-owned and
gone by the time the server hears about a kill, so there is no way to re-validate one —
the allowlist and throttles are the defence.

## Catch and release

`fusion_fishing` gained a Keep / Put it back prompt on every landed fish. Keeping it is
the old behaviour exactly — item, full XP, **no honor change either way**. Releasing gives
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
- **The centre-screen +/− indicator — the change.** ~2.2s. Drawn only when vice_hud
  computes a non-zero delta against the last value it saw, with the face for the
  *direction* honor moved.

**Neither is permanent, on purpose.** An always-on honor panel is clutter; you get the
readout when something actually happens. `Config.Honor.holdMs = 0` in vice_hud restores
the always-on behaviour if you ever want it.

**The two are raised on different rules**, because they answer different questions.
`client/main.lua`'s `honorUpdated` handler decides:

- **The centre indicator fires for EVERY hook** — it answers "did that count?", which is
  true of a `meter_theft` inside the `devil` band just as much as a kill. Pushed via
  `exports.vice_hud:ShowHonorDeed(delta, severity, broken)`, which draws the indicator and
  nothing else (no mugshot is even taken for it).
- **The corner panel only draws when the standing actually changes** — it answers "what am
  I now?", so it earns screen time when the tier crosses `AngelThreshold`/`DevilThreshold`,
  or when honor latches at the unrepairable floor for the first time. That second case
  matters on its own: -45 → -100 crosses no threshold, but going permanently broken is not
  a "nothing changed" event.

Severity deliberately does **not** raise the panel. A terrible deed gets the terrible face
on the indicator; it doesn't get to reprint a standing that hasn't moved — doing that is
what buried the indicator under a panel repeating itself on every kill.

Neither gate touches the honor VALUE, which always updates. The persistent displays below
read that live and are never gated.

```lua
exports.vice_hud:ShowHonorToast(mugshot, honor, emoji, reason, broken, severity)
```

qbx_honor passes **`nil` for `emoji` on purpose**. vice_hud picks the standing face from
its own `Config.Honor` thresholds (mirroring this resource's) and the direction face for
the indicator separately. This resource used to pass the direction face, which forced the
standing badge to show it too — so the corner panel disagreed with the player's actual
tier on every single change. Do not put it back.

`reason` is the `label` from the hook that fired (`Config.Hooks.<name>.label`), e.g.
"Killed a bystander". It shows under the value for as long as the panel is up.

`severity` is the hook's `Config.Hooks.<name>.severity` (`'good' | 'bad' | 'terrible'`) —
see the Severity section above. It only affects the centre-screen change indicator, never
the corner badge.

On spawn — and whenever vice_hud restarts — this resource calls
`exports.vice_hud:SetHonorStanding(honor)` instead, which **seeds the value without
drawing anything**. vice_hud measures the delta that fires the +/− indicator against the
last value it saw, so it needs the spawn value; but a player who has not done anything yet
should not get a panel popped at them for it. Use `ShowHonorToast` for events,
`SetHonorStanding` for state.

`Config.AngelThreshold` / `Config.DevilThreshold` define the tiers and are mirrored in
`vice_hud/config.lua` as `Config.Honor.angelAt` / `devilAt`. **Keep the two in sync** —
nothing enforces it, and they will silently disagree.

## Persistent displays (never gated)

Two other places show the current character's standing continuously, independent of the
world-HUD gating above — checking your honor doesn't require waiting for (or provoking) a
hook:

- **ox_inventory's weapon wheel.** A small pill, bottom-right of the wheel — emoji + value,
  tinted by tier, greyed once broken. `[ox]/ox_inventory/client.lua` listens to both
  `qbx_honor:client:syncHonor` (initial) and `qbx_honor:client:honorUpdated` (every
  subsequent change) and relays value/tier/emoji/broken to its own NUI (`store/honor.ts`,
  rendered in `LeftInventory.tsx`). The emoji strings are hand-mirrored constants
  (`'😇'`/`'😈'`, matching `Config.AngelEmoji`/`DevilEmoji` here) — same reasoning as the
  threshold mirroring above.
- **qbx_relog's character switcher.** Every character on the license gets an honor chip
  under their portrait card (not just the current one — comparing standings across
  characters is the point there). `qbx_relog/client/main.lua` reads straight from each
  character's `metadata.honor`/`honorBroken` rather than qbx_honor's client cache, since it
  needs OTHER characters' values, not just the one currently loaded.

Both mirror `Config.Hooks`' visual language (the same angel/devil colour split, the same
"broken" treatment) without depending on qbx_honor being started to render — they degrade
to "no badge" rather than erroring if it's stopped.

## Not hooked (see task report for full reasoning)

`wasabi_ambulance` / `envi-medic` player revives were NOT hooked: their core logic ships
as pre-compiled/obfuscated FXAP bytecode in this repo, so there is no readable server-side
event carrying both the reviver's and the patient's source id to hook cleanly. Same for
`um_rob_atm`, `loaf_storerobbery`, `loaf_bankrobbery` and `rcore_prison` — all escrowed.
Wiring any of them would require guessing at or patching compiled bytecode, which this
resource deliberately avoids.

## Server.cfg

Started as part of `ensure [standalone]`.

## Licence

[CC BY-NC-SA 4.0](LICENSE) — non-commercial. You may use, modify and
redistribute this resource, including on a server of your own, but not sell it
or bundle it into anything paid, and a modified version has to carry the same
licence.
