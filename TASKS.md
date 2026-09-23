## Milestone 10 — Second Art Pass (in progress)

- [x] Turret pivots hooked to aiming
- [x] Buildings: real verticality and a roof that reads
- [x] Infantry rebuilt for a top-down silhouette
- [x] Destruction states - structures leave ruins
- [x] Remaining icons into the top bar
- [ ] Vehicle wrecks (no model yet; smoke covers it for now)

### Turrets

The greyboxes were built with the turret as a separate node pivoting on
Y precisely so this could exist later, and nothing read it - tanks fired
from a barrel welded facing forward. `TurretAim` attaches itself only
when a model actually has a `Turret` node, so callers need no special
case and a harvester simply has nothing to turn. It aims in the hull's
frame, so a vehicle turning does not drag its aim around with it.

### Making a base read from above

Height alone did not fix it. The camera is steep, so the roof is most of
what is visible, and with walls and roof sharing one gunmetal a base read
as a single flat shape with faction stripes floating on it. A concrete
roof deck on every structure was worth more than all the added height -
and the first attempt, one step lighter in steel, was invisible under
this lighting.

Infantry are rebuilt around what the camera can see: shoulders wider
than the hips, a helmet that overhangs and separates from them, and a
brim so it casts its own edge. Legs are shaped only enough to carry the
stance.

### Ruins

`destroyed_building.glb` existed since the first art pass and nothing
ever spawned it. Structures now leave a ruin scaled to what stood there,
fogged like the ground so a ruin the player has never seen does not mark
their map, and capped at 24 so a long match cannot accumulate more
wreckage than the buildings cost.

41 models, 8,584 triangles. 59.8 / 60.0 / 57.2 FPS at 40 / 80 / 120.

## Milestone 8 — closing items (done)

### The expansion now earns its keep

The commander built a Forward Command Post and then never put a refinery
beside it, so the post was a flag on an ore field: every load still had
to be driven home. Worse, expanding sat behind the entire eight-building
order, so it only happened once the tech tree was finished - around seven
minutes, by which point the home field was gone and income had already
fallen to zero. When the ore at home runs out, reaching more of it IS the
economy, and it now outranks a Radar.

Measured over a 660s probe, before and after:

    forward post built     t=420 (match end)   ->  t=180
    refinery beside it     never               ->  t=420
    round trip at t=480    73.9s               ->  15.5s
    income t=360..660      0, 0                ->  4,199 .. 11,198 sustained
    ore actually mined     34,900              ->  70,300

The expansion is also defended now: it is included in the threat scan,
and a tower goes up out there once it has been shot at.

### Difficulty reads the way a player expects

HARD was the least aggressive setting in the game. The attack bar was
multiplied by difficulty's group-size scale, so HARD wanted 1.35x the
enemy army for the margin and another 1.25x for difficulty - 1.69x
altogether - and in a twenty minute match against an equal it never
attacked once, while EASY attacked twice. Aggression is now its own
number, inverted: EASY waits for overwhelming force, HARD commits near
parity.

Measured against a passive player, which is the least noisy board there
is for comparing aggression:

    EASY     peak army 5,200   first attack 2:37   victory 4:42
    NORMAL   peak army 6,500   first attack 1:51   victory 5:22
    HARD     peak army 8,700   first attack 1:49   victory 5:23

Strength ladders cleanly and EASY visibly hesitates. Victory time is not
a difficulty signal against a passive opponent - it is dominated by which
opening was drawn, which is the same caveat recorded in Milestone 6.

### The vertical slice flake was never timing

"Main Battle Tank produced" failed about one run in eight and was twice
written off as a wall-clock wait. It was not. The harness waited for the
player's unit COUNT to change, so if a unit died in the same frame the
tank spawned, the total was unchanged and the test concluded nothing had
been built - the tank was there the whole time. Making the AI attack
earlier made it frequent enough to catch. It now watches for the unit it
asked for. 5/5.

## Milestone 11 — Feel and Audio (in progress)

- [x] Weapon, impact and explosion SFX per class
- [x] Build, ready, capture, sell and alert cues
- [x] Ambient bed and calm/combat music states
- [x] Selection, marker and camera feel pass

Milestone 11 complete.

### Feel

Selection rings pop on the transition into selected rather than simply
appearing, and harvesters ring amber - so a player scanning a selection
can see at a glance whether they grabbed their economy along with their
army, which is the mistake the ring exists to prevent.

Explosions shake the camera, scaled by blast size and faded by distance,
and only when the blast is within about 1.6 zoom lengths of what the
player is looking at: on a 220m map most explosions are off screen, and
a camera that rattles for those is noise. Shake is applied to the camera
position and never to pan_target, so it cannot drag the battlefield.

`feel_test` covers the observables: the ring appears, pops and settles;
markers spawn and clear themselves; move and attack differ; a near blast
shakes and a distant one does not; the shake settles to zero; and
focusing eases rather than teleporting.

Measured with audio and shake running: 59.8 / 60.0 / 56.9 FPS at
40 / 80 / 120 units.

22 sounds, synthesised by `tools/make_sfx.py` - written by Codex from an
audio brief, per this project's split of asset work. Standard-library
Python only, deterministic, so the whole set regenerates from source
rather than being binary blobs nobody can change.

Weapons choose their own report from what the weapon IS - splash,
anti-armour, damage, rate of fire - so a new weapon gets a sensible
sound without a per-unit table. Rocket is checked before the damage
threshold, because an AT launcher hits hard enough to be mistaken for a
tank gun and the launch whoosh is its whole character.

Music is two beds cross-fading on whether anyone has fired in the last
nine seconds, over an ambient wind layer, all three silenced under the
after-action report.

`audio_test` asserts which stream each cue resolves to and drives the
music state machine, rather than checking that nothing threw: 19 of 19
cues authored, four distinct weapon reports, beds looping, combat rising
and settling. Verified running on Android through OpenSLES.

## Milestone 9 — Match Shape (in progress)

- [x] MapDefinition resource; the layout is data, not constants
- [x] Three maps that play differently by economy, not decoration
- [x] Setup screen offers map and difficulty
- [x] Save and resume a match, with autosave on backgrounding
- [x] Win / lose flow and after-action report

Milestone 9 complete.

### Match ending

The report answers three questions instead of listing seven numbers:
what you fielded, what it cost, and how the economy behaved. The
exchange ratio ("2.0 : 1", or "2 for none") is the most descriptive line
in it - it separates a win that cost nothing from one that nearly was
not a win. Average income is derived from what was harvested over the
match length.

The battlefield pauses behind the report, the overlay processes while
paused so its buttons still work, and there are two ways out: PLAY AGAIN
on the same map and difficulty, or NEW SKIRMISH back to setup. The save
is deleted when a match ends so RESUME never offers a finished game.

`match_end_test` drives both endings for real rather than calling the
overlay directly, and checks the numbers, the pause, both buttons and
the cleared save.

### Save and resume

`SaveGame` stores what cannot be derived - credits, units with health,
veterancy and cargo, buildings with health and rally points, ore left in
each field, the explored fog, match statistics and the AI's strategy -
and rebuilds a match from it. Anything derivable (navmesh, scenery,
selection rings) comes back through the normal spawn path.

Autosaves when Android takes the game away (APPLICATION_PAUSED, back
button, window close) and offers RESUME OPERATION on the setup screen.
The save is deleted when a match ends, so the button never offers a
resume that goes nowhere.

Round trip verified 15/15: same units, buildings, neutrals and fields;
credits, ore, explored cells and unit damage all preserved; the resumed
match keeps playing.

Three defects the round trip found:
- The first refinery hands out a free harvester. On resume that
  duplicated one the save already contained, every single load.
- The commander resumes and spends immediately, which is correct but
  was being measured as the save losing 1,200 credits. The test now
  holds it still for the comparison rather than the game being changed
  to suit the test.
- Two earlier attempts at the map harness measured the wrong thing; see
  the Milestone 9 notes in the commit history.

## Milestone 7 — Android Beachhead (partly blocked)

Renderer switched Forward Plus -> Mobile with a full test pass; Android
export preset added; touch input fixed and tested; HUD sized for a thumb.

Blocked here and not attempted: installing the JDK and Android SDK needs
root, and there is no device to install an APK on. Everything short of
those is done.

### Decisive defect

Godot emulates mouse events from touch by default. Gameplay acted on them
as well as on the touch events, so every tap ran twice - and the emulated
left-drag hit the desktop rule that a drag is always a marquee, meaning
**the camera could not be panned with one finger at all**. The game would
have shipped unplayable on the platform it targets.

## Milestone 8 — An Opponent That Fights Back (in progress)

The commander is now faction-agnostic: the same brain runs on either
side. `tests/ai_versus_test.gd` puts two of them on one map, which is the
first time any AI measurement here has been taken against someone who
shoots back.

### Measured, three matches after the fixes below

    match 1   player wins 7:32   waves 2/1   retreats 1/1
    match 2   player wins 7:57   waves 3/1   retreats 2/1
    match 3   player wins        waves 1/0   retreats 0/0

Multi-wave pressure is real now (2-3 waves with retreats between them),
and a commander that retreats comes back when it can. When it does not,
it is because it is facing three times its own army value - that is
judgement, not paralysis, and the test asserts the gate rather than the
outcome: a retreating commander is never "ready but idle".

### Defects found by running the AI against itself

- `desired_group_value()` ramped on the clock alone, so a commander got
  MORE passive as a match went on: after a failed wave the bar had risen
  out of reach and it never attacked again. It is now sized against the
  opponent's seen army value, floored and capped.
- The harvest round-trip signal handler named its parameter `is_player`,
  shadowing the commander's own. Once a second commander existed, both
  recorded only the enemy's trips and sized their harvester fleets off
  the opponent's route. Identical trip numbers for both sides in one
  match is what gave it away.
- `depth_test`'s veterancy check was flaky at about 50%: it sited its
  duel inside the acquisition range of its own earlier fixtures, and then
  raced the tank's own AttackerComponent for the trigger. Now isolated
  and observed rather than driven. 5/5.

### Outstanding
- [ ] AI defends its expansion, and builds a refinery there
- [ ] Re-tune EASY / NORMAL / HARD against an active opponent
- [ ] Player-side commander still underperforms in some openings

# Operation Midnight — Task Board

## Milestone 6 — AI Economy & Match Closure (in progress)

Objective: NORMAL AI must destroy a passive player's Command HQ in 8-15
minutes, 3/3, using the same economy the player has.

### Measured baseline (before this milestone's fixes)

    t=  0  cr=3900  in/min=    0  out/min=    0  ref=0  harv=0
    t= 30  cr=1600  in/min=    0  out/min= 6799  ref=1  harv=1
    t= 90  cr=   0  in/min= 2799  out/min= 6399  ref=2  harv=3
    t=120  cr=1600  in/min= 5599  out/min= 2399  ref=2  harv=4

Spend outran income better than 2:1 and the treasury hit zero at t=90.
The commander was insolvent, not mis-targeted.

### Done
- [x] Phase 1 economy instrumentation (AIEconomy + 30s snapshots)
- [x] Phase 2 treasury reserve, abandoned when the economy is crippled
- [x] Phase 3 spending priority ladder (CRITICAL..LUXURY)
- [x] Phase 4 harvester saturation, 3/refinery, 4 on long routes
- [x] Phase 5 second refinery in every opening, before the tech tier
- [x] Phase 6 offensives gated on the economy replacing casualties
- [x] Phase 7 expansion conditions include inadequate income
- [x] Phase 8 round-trip measurement feeding saturation policy
- [x] Phase 10 army value by role, not unit count
- [x] Phase 11 siege share requirement (20% of army value)
- [x] Phase 12 attack thresholds by credit value
- [x] Phase 13 reinforcements released as a body
- [x] Phase 14 staging point short of the objective
- [x] Phase 21 ai_passive_player_test with binary pass/fail
- [x] Phase 25 AI economy debug panel

- [x] Phase 22 three repeat passive wins (4:21, 4:50, 5:15 - all PASS)
- [x] Phase 24 full regression after the economy changes: 7/7 suites,
      0 failures (logic, fog, depth, economy_regression, infrastructure,
      vertical_slice, ai)

### Decisive defect found this milestone

`UnitBase._nearest_hostile()` only ever scanned unit groups, never
building groups, so an attack-move could not acquire a structure: armies
arrived at a base and stood in it. A second defect measured targets
against `_guard_origin` - where the order was issued - so an advancing
unit rejected everything once it had moved ~30m. Together these are why
sieges never resolved, for either side, across three milestones. Fixed
in `58254a0`.

### Economy measurements (Phases 18/19/20)

Harvest rate is 700 credits per round trip. Measured trips and the
resulting income, NORMAL AI, passive opponent:

    1 refinery,  3 harvesters, trip 25s   ->  ~2,800 cr/min observed
    2 refineries, 6 harvesters, trip 21s  ->  12,598 cr/min observed
                                              (theory 6*700*60/21 = 12,000)

Against production costs: a Vehicle Factory running continuously is
1800/18s = 6,000 cr/min, a Barracks 300/5s = 3,600 cr/min. A saturated
two-refinery economy funds both plus construction, which is the intent.

The catch is duration, not rate. Each home field holds 16,000 - about
23 loads - so six saturated harvesters strip it in under two minutes.
The logs show exactly that: `trip` climbs 21s -> 43s -> 65s as harvesters
fall back to the central field 103m away, and total harvested (20,200 -
23,700) exceeds the 16,000 a home field contains. Income after the home
field dies is roughly 5,000 cr/min, enough for one production building.

That pressure toward the contested centre is a design property worth
keeping, not a bug to tune away; it is recorded here so the next balance
pass starts from the measurement.

Phase 19/20, measured by `tests/ai_field_probe.gd` (distances are from
the AI base, ore remaining per field):

    t=  0  36m:16000  98m:20000  103m:28000  168m:16000   trip  0.0s  in/min      0
    t=180  36m:  600  98m:20000  103m:28000  168m:16000   trip 20.4s  in/min 11,197
    t=240  36m: gone  98m:19300  103m:24500  168m:16000   trip 30.0s  in/min  4,199
    t=300  98m:18600  103m:21000                          trip 52.8s  in/min  5,599
    t=420  98m:16500  103m:12600                          trip 63.4s  in/min  1,399

The home field is stripped between t=180 and t=240, exactly as predicted,
and every later number follows from that one event. Map control does
matter: the central field drops 28,000 -> 12,600, so the AI is genuinely
fighting for the middle rather than sitting at home. A 10-15 minute match
has ore to spare in total (45,100 of 80,000 left at t=420); what runs out
is ore that is *close*.

- [x] Phase 15 economic harassment (bounded opportunity retarget)
- [x] Phase 16 player economy damage compounds offensive confidence
- [x] Phase 19 resource field values measured, left unchanged
- [x] Phase 20 economic map control confirmed: central field contested
- [x] Phase 23 scenarios A-E, 11/11 checks, 0 failures

### Recovery results (`tests/ai_economy_recovery_test.gd`)

    E: expansion destroyed                            PASS
    E: decides about the expansion and keeps earning  PASS (rebuilt=true, +12,600/180s)
    A: replaces a single lost harvester               PASS (8 -> 8)
    C: harvest fleet destroyed                        PASS
    C: rebuilds harvesters from reserve               PASS (2)
    C: income resumes after losing the fleet          PASS (+1,400)
    B: rebuilds a destroyed refinery                  PASS (2 -> 2)
    D: restores power generation                      PASS (200)
    Economy is alive after sustained damage           PASS (+1,400 over 60s)

Scenario E has to run before any damage is done. Rebuilding a razed base
correctly outranks expanding, so a damaged AI never reaches the expansion
branch and the scenario cannot be observed at all - it reported N/A twice
before the ordering was fixed, which was the harness looking in the wrong
place rather than the AI declining to act.

### Known limitation, not fixed this milestone

The AI builds its Forward Command Post (t=300 in the probe) but never
follows it with a refinery out there, so refineries stay at 2 and the
round trip keeps climbing to 63s. Phase 7 describes the chain as
post -> refinery -> harvesters; only the first link happens. The
expansion currently buys map presence, not income. Left alone
deliberately: it is a pre-existing gap rather than a regression from
this milestone's changes, and closing it is a feature.


Living status for the current milestone. `TODO.md` keeps the long-range
backlog; this file tracks what is in flight.

## Milestone 5 — Gameplay Depth

### Done

**Combat model**
- Armor classes INFANTRY / LIGHT / MEDIUM / HEAVY / STRUCTURE
- Damage types SMALL_ARMS / ANTI_ARMOR / CANNON / EXPLOSIVE with one
  shared multiplier table (`scripts/combat/damage_types.gd`)
- Weapons refuse targets they cannot *usefully* hurt (0.25 multiplier
  floor), so a dog no longer chases a tank
- Artillery Vehicle: 26m range, 6m minimum range, splash, stop-to-fire

**Veterancy**
- REGULAR / VETERAN / ELITE at 100 / 300 XP
- XP is proportional to damage dealt, not final blow
- Veteran +10% HP/damage, Elite +20% HP/damage +10% speed and slow
  regeneration 8s after last damage
- Rank chevrons above the unit; rank shown in the selection panel

**Ownership**
- True NEUTRAL ownership replacing the enemy-owned placeholder
- Neutral structures feed neither tech tree nor power grid
- Engineer capture with a 3s channel, consumed on use

**Strategic structures**
- Communications Outpost (35m vision), Repair Depot (2%/s to vehicles
  within 10m), Supply Depot (+75 credits/minute)

**Orders**
- PATROL (sweeps between two points), GUARD (follows what it protects)
- Stances HOLD / DEFENSIVE / AGGRESSIVE driving acquisition and leash

**Economy**
- Resource depletion: harvesters retarget, then report NO RESOURCES
- Extra production buildings speed each other: `1 + 0.35 × extras`
- Rally arrivals scatter so units do not pile on one coordinate

**AI**
- Strategic controller replacing the wave timer
- `AIMemory`: records only what AI vision actually saw, decays with a
  45s half-life, never reads hidden player state
- Weighted opening strategies: ECONOMY / INFANTRY_PRESSURE /
  FAST_VEHICLES / TECH
- Counter-production from observed composition
- Scouting tasks with retreat when damaged
- Proportional defence, attack grouping, retreat at 65% losses
- Rebuilding via the same path as building - a razed structure is just a
  gap in the wanted list again
- Difficulty EASY / NORMAL / HARD affecting tempo and decision quality
  only, never raw stats

**Shell**
- Skirmish setup screen with difficulty, tree paused until START
- After-action report with match statistics

**Garrison**
- Infantry occupy civilian structures and fire from inside at +20% range
- Occupants are stored, not simulated: unshootable individually, so the
  counter is to destroy the building
- Destroying an occupied structure spills survivors at 40% damage
- Occupying a neutral building claims it

**Expansion**
- Forward Command Post (1800, 18m influence) for both sides
- AI plants one near a discovered field when home ore runs low

**Performance** (measured)
- 40 units: 60 FPS, worst frame 28.9 ms
- 80 units: 60 FPS, worst frame 16.7 ms
- 120 units: 60 FPS, worst frame 16.7 ms
- 40 v 40 battle: 144 FPS uncapped, worst frame 12.5 ms
- Local avoidance (RVO) enabled; unstick nudge as terrain backstop

### Measured AI competence (NORMAL, vs a fully passive player)

A 10-minute match, logged every 60s:

    t=  0  army= 3  buildings=3  credits=3900
    t=180  army= 5  buildings=8  credits=2700
    t=240  army=14  buildings=9  credits=   0  attacking
    t=360  army= 9  buildings=9  credits= 200  attacking
    t=540  army= 8  buildings=9  credits= 100  attacking
    t=600  army= 8  buildings=9  credits= 300

It builds an economy, techs up, scouts, commits, loses waves, retreats,
rebuilds and re-commits - and it sustained an attack for five straight
minutes. It killed one player unit and never threatened the HQ.

The binding constraint is income, not tactics: credits sit at 0-300 from
t=240 onward. Nine buildings and three harvesters cannot fund continuous
production, so the siege units the army needs are never affordable.
Target prioritisation and the siege check were added and did NOT change
the outcome - the AI simply cannot pay for what it decides it wants.

### Not started
- AI use of Spies and Engineers (both exist; only the player uses them)
- Aircraft, superweapons, naval - explicitly out of scope

### Known gaps
- Gate is passable to its owner via collision layers; it does not
  physically open or close
- Kill credit is damage-proportional for the shooter only; assists from
  splash on friendly-fire edge cases are not modelled
