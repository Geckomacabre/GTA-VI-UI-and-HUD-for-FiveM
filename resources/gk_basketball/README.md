# gk_basketball

A playable basketball game for FiveM. Self-contained: ball handling, shot mechanics,
score detection and timed pickup matches, with no throwables dependency.

Built for Qbox (`qbx_core`), using `ox_lib`, `ox_target` and `ox_inventory`.

---

## Install

1. Drop this folder in `resources/[standalone]/`.
2. Add to `server.cfg`, after `ox_lib`, `ox_target` and `ox_inventory`:

   ```
   ensure gk_basketball
   ```

3. Register the `basketball` item in your `ox_inventory`:

   - Copy `ox_inventory-item/basketball.png` into `ox_inventory/web/images/`.
   - Add this entry to `ox_inventory/data/items.lua`:

     ```lua
     ['basketball'] = {
         label       = 'Basketball',
         description = 'Use it to start dribbling. Find a court and put it through the hoop.',
         weight      = 600,
         stack       = true,
         close       = true,
         client      = {
             export = 'gk_basketball.useBasketball',
         },
     },
     ```

4. Grant yourself hoop-placement rights in `permissions.cfg`:

   ```
   add_ace group.admin gk_basketball.manage allow
   ```

5. **Place your hoops** — see below. Until you do, there are no courts and nothing
   to shoot at.

---

## Placing hoops (required)

GTA's basketball hoops are part of the map, not props, so there is no way to find a
rim from code. The coordinates have to be measured once per court, by eye. The tool
makes it quick.

Stand on a court, look at a rim, and run:

```
/bball_place chamberlain
```

A green rim outline appears where you're looking, with the scoring cylinder drawn
above it so you can see the volume a shot has to pass through.

| Key | Action |
| --- | --- |
| `W` `A` `S` `D` | move horizontally, relative to your camera |
| `Q` / `E` | lower / raise |
| hold `SHIFT` | fine steps (1cm instead of 5cm) |
| `ENTER` | save |
| `BACKSPACE` | cancel |

Line the outline up with the real rim and hit `ENTER`. It's written to
`data/hoops.json` and pushed to every connected client immediately — no restart.

Repeat for the second hoop, using the **same court id**. A court is just a group of
hoops sharing an id; its centre (blip and interaction point) is averaged from them.

Other commands:

- `/bball_hoops` — list every hoop, with coordinates, in F8
- `/bball_delhoop` — delete the nearest hoop within 15m

Set `Config.Debug = true` to keep rim outlines drawn on every nearby hoop, which is
the fastest way to check your alignment.

### Half court vs full court

- **Leave the team argument off** for pickup rules: both hoops score for whoever
  shoots. This is what you want for most RP courts.
- `/bball_place mycourt home` tags a hoop as the home team's basket. With tagged
  hoops, each team scores on the *other* team's rim, and putting one through your
  own basket credits the opposition.

---

## Playing

**Getting a ball** — use a `basketball` from your inventory, or target the court
centre and pick *Grab a basketball* (free, no item needed; turn off with
`Config.Match.freeBallsOnCourt`).

**Shooting** — hold `LMB`. A meter fills, then falls, then repeats. There's a green
band on it: release inside the band for a clean shot. The closer to the centre of
the band you release, the closer to the middle of the rim the ball goes.

While you're lining up, the rim you're locked onto lights up in green, with the
scoring cylinder drawn above it and the points and range floating over the top —
so you know which basket you have and what it's worth before you commit. If nothing
lights up, no hoop is in range and the shot will be a loose throw; the hint tells
you so. `Config.AimMarker = false` turns it off.

Distance matters independently of your release — a perfect release from the arc is
still a much harder shot than a perfect release from under the rim.

The ball is then plain physics. Nothing is scripted to "go in": rim bounces,
in-and-outs and swishes all happen because a real object went through (or didn't go
through) a real circle in space.

| Key | Action |
| --- | --- |
| hold `LMB` | charge and shoot |
| `E` | pass to the nearest player |
| `G` | put the ball away |
| `E` (near a loose ball) | pick it up |

**Matches** — target the court centre to *Join pickup game*. Teams auto-balance onto
the smaller side. Once `Config.Match.minPlayers` have joined, anyone in the lobby can
*Start match*. A scoreboard appears top-centre with the clock, both scores and a
per-player points list.

Baskets score 2, or 3 from beyond `Config.Scoring.threePointDistance` measured from
where you released. The game ends on the clock or at `Config.Match.scoreLimit`,
whichever comes first, then resets to a lobby.

Shooting outside a live match still works and still tells you what you scored — it
just doesn't touch a scoreboard.

`/bball leave` and `/bball start` work if you'd rather not use the target.

---

## Tuning

Everything is in `shared/config.lua`. The knobs worth knowing:

| Setting | Effect |
| --- | --- |
| `Config.Scoring.rimRadius` | how forgiving the hoop is. `0.32` default; regulation is `0.23`, arcade is `0.40` |
| `Config.Shot.lateralError` / `depthError` | metres of miss per metre of distance at zero accuracy. Lower = more shots go in |
| `Config.Shot.sweetWidth` | how wide the green band is. Wider = easier timing |
| `Config.Shot.distancePenalty` | how much raw distance eats into a perfect release |
| `Config.Shot.flightTime*` | arc height. The shot is solved to reach the rim in exactly this long, so a longer flight *is* a higher arc — lower these to flatten shots. Below about `0.4` base they start rimming out |
| `Config.Shot.aimHeightOffset` | how far above the rim the shot is aimed. Raising it makes shots land long, because the ball only drops to rim height past the basket — and scoring is a rim-plane crossing. Keep it small |
| `Config.Toss.maxLift` | ceiling on camera pitch for throws with no hoop targeted, so looking up doesn't launch one into orbit |
| `Config.Shot.aimAssist` | `false` makes every shot a manual camera-direction throw (hard mode) |
| `Config.Match.duration` / `scoreLimit` | set either to `0` to play purely to the other one |

### Animations

Every name in `Config.Anims` was checked against the GTA V animation database
(patch v1734), not guessed.

There is no basketball animation set in the game, so every clip here is something
else pressed into service. The shot is `melee@thrown@streamed_core` /
`plyr_takedown_front`, an overhand throw.

`amb@prop_human_movie_bulb@exit` — the change-a-lightbulb scenario exit that
gusti-basketball shoots with — looks right on paper and isn't. It's a scenario
*exit*, so it opens already in the raised pose and unwinds out of it, with the
hand tracking back over the head instead of pushing forward. Shots read as being
flung from behind you.

`Config.Shot.windUp` is how long after the clip starts the ball actually leaves.
Your target and accuracy are locked the instant you release the key, so this only
changes when the shot *looks* like it left, never where it goes.

Both are tunable without a restart, which saves a walk back to the court per guess:

```
/bball_anim shoot melee@thrown@streamed_core plyr_takedown_front
```

```
/bball_windup 220
```

`/bball_anim` with no arguments lists the keys you can retune.

### Dribbling

There is no dribble animation in GTA V. Not in that dict, not anywhere — every
basketball animation you've seen in a server is a streamed add-on.

So the dribble is sold two other ways. The stance comes from the movement clipset:
`anim@move_m@trash` walks with one arm hanging low and loose at your side, which is
as close to working a ball as the base game gets. And the bounce **ends in your
hand** — the top of every bounce is the hand bone, not a fixed height beside you.
That second part is what actually does the work. A ball that bounces on its own
private path next to you reads as floating no matter what the arm is doing; a ball
that arrives where your hand is reads as a dribble even if the arm never moves.

`Config.Dribble.offset` sets where it meets the floor. There's no bounce height to
set, because the hand is the apex. Two knobs shape the rest of it:

| Setting | Effect |
| --- | --- |
| `lead` | metres the bounce is pushed out in front of you at a sprint. A dribbler at speed puts the ball ahead and runs onto it; pinned to your hip it reads as carrying, not driving |
| `handDwell` | fraction of each bounce the ball rests in your hand before the next push |

The bounce curve is the real one — height under gravity is parabolic in *time*, so
the ball leaves the hand slowly, moves quickest at the floor and decays again on
the way up. Getting that backwards is most of what makes a scripted bounce look
floaty.

If you do want the arm pumping on top of that, `Config.Dribble.handAnim` scrubs an
upper-body clip's phase off the bounce. It's off by default: every stock clip that
moves the arm far enough to notice also bends the spine, and a ped folding in half
after the ball looks much worse than a still one. With an animation pack streamed
it's worth revisiting:

```
/bball_hand
```

prints the current clip, and

```
/bball_hand pickup_object pickup_low 0.05 0.40
```

swaps it live while you're holding a ball — no restart. Start narrow and widen
until the ped starts leaning.

Set any entry to `false` to skip its animation. A dict that fails to load is skipped
rather than hung on, and an anim name that doesn't exist is abandoned after a few
attempts instead of re-tasking the ped every frame.

---

## How it works

**Score detection** (`client/scoring.lua`) treats each hoop as a horizontal circle.
Rather than asking "is the ball inside the rim right now" — which a fast shot would
tunnel straight past between frames — it takes the segment between the ball's
previous and current position and solves for where that segment crossed the rim
plane. Detection is therefore frame-rate independent. A shot also has to have been
above the rim *while outside* the cylinder to count, so you can't score by punching
one up through the net from underneath.

**Authority.** Ball physics run on the client that threw it, which is what makes it
feel responsive. The server owns everything that matters: who may hold a ball, which
balls are loose, and the score. Only the client that released a ball tracks it, so
exactly one client reports each basket, and the server still range-checks the shooter
against the hoop and rate-limits scoring per player.

**Hoops** live in `data/hoops.json`, written by the placement tool at runtime and
re-broadcast on every change.

---

## File map

```
shared/config.lua      all tuning
shared/util.lua        court grouping, hoop targeting, maths helpers
client/court.lua       courts from hoops, blips, ox_target zones, notify/hint helpers
client/ball.lua        hold, charge meter, ballistic shot solve, pass, stow, pickup
client/scoring.lua     rim-plane crossing detection
client/hud.lua         NUI bridge + floating "+2" over the rim
client/placement.lua   /bball_place tool and debug rendering
server/hoops.lua       hoops.json persistence, ace-gated add/remove
server/ball.lua        who is carrying, which balls are loose, item integration
server/match.lua       match state machine, teams, clock, scoring authority
html/                  scoreboard
```
