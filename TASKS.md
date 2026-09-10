# Operation Midnight — Task Board

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
