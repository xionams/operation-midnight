# Operation Midnight — TODO

## DONE (Milestone 1)
- Project scaffold, data-driven config resources (UnitStats/BuildingStats/WeaponStats/EconomyConfig)
- RTS camera: WASD/wheel (desktop) + drag-pan/pinch-zoom (touch), clamped to map bounds
- Selection system: click/tap select, box-select (desktop), reusable across all unit types
- Unit movement via NavigationAgent3D, formation-offset multi-unit move commands
- Runtime-baked navmesh, rebaked on building placement
- Building placement: ghost preview, validity check (bounds + overlap), credits deducted on success
- Power Plant, Resource Refinery, Command HQ buildings; global power tracking in GameState
- Resource nodes ("Strategic Resources") with finite capacity
- Supply Harvester with full find → travel → load → return → unload → repeat state machine
- Assault Vehicle combat via reusable AttackerComponent + Weapon (hitscan + tracer)
- Enemy base with 2 AI Assault Vehicles (defend-radius behavior)
- Win/defeat via Command HQ destruction, Victory/Defeat overlay + Restart
- Android-friendly HUD: credits, power, selection count, build buttons
- Debug overlay (F3): FPS, unit count, credits, power, match state

## CURRENT
- Headless verification passed on Godot 4.3 (2026-09-10): clean import, zero script errors,
  navmesh bakes (82 polys), harvester completes IDLE→TO_NODE→LOADING→TO_REFINERY→UNLOADING and
  delivers +700 credits, combat damages targets, HQ destruction triggers Victory.
- Still unverified — needs a display (editor run or Xvfb): camera pan/zoom, box-select, touch
  gestures, HUD layout/scaling, building ghost preview, tracer and explosion visuals.
- Camera framing fixed (2026-09-10): pitch 49°→62°, opening zoom 55→38, focus pulled toward
  centre, and the ground mesh widened to 2.4x purely as a visual skirt (collision and navmesh
  unchanged at 82 polys) so the horizon and map edge stay out of frame.
- Wire Codex's assets in `assets/generated_rts/` — currently referenced by nothing.
- Codex round 2 delivered re-exports only. Still outstanding: HUD icons, tileable terrain
  textures, muzzle flash / impact sprites, and whether .glb models are possible.

## UNIT LOGICS (done 2026-09-10)
- Armor classes (INFANTRY / LIGHT / HEAVY / BUILDING) + damage-vs-armor table on WeaponStats.
  Counters are tuned in `config/weapons/*.tres`, never in scripts.
- Barracks trains Rifle Soldier, Engineer, Spy, Attack Dog.
- Engineer captures enemy buildings intact (power, groups, registrations and production all move).
- Spy infiltrates: loot a Refinery, wipe a production queue with no refund, black out a Power Plant.
- Disguise + detection: disguised Spies are ignored by enemy targeting; Attack Dogs reveal them.
- Vehicles crush enemy infantry — infantry are on their own collision layer so armour drives
  through them rather than being blocked.
- Verified by `tests/logic_test.tscn` (26 checks).

## MILESTONE 2 — RTS CORE EXPERIENCE
Phase 1 — visibility foundation
- [x] vision_range on UnitStats/BuildingStats + values per entity
- [x] FogOfWar grid autoload (2m cells, explored vs currently_visible, ~8Hz updates)
- [x] Entity hiding: enemies outside vision are invisible, unselectable, untargetable
- [x] Attack orders vs a target lost to fog fall back to last known position
Phase 2 — map
- [x] 220x220 battlefield, POIs the player must discover, terrain blockers/chokepoints
- [x] Start with only the base area explored
Phase 3 — fog rendering
- [x] Ground shader sampling the fog texture, soft edges, three brightness states
Phase 4 — selection
- [x] Screen-space marquee box, real-time rectangle, friendly units only
- [x] Touch: hold-then-drag = marquee, immediate drag = camera pan
- [x] Double-click/tap selects same type within 30m
- [x] Control groups 1/2/3 (assign + recall, auto-remove dead)
Phase 5 — commands
- [x] CommandType architecture + contextual intent
- [x] Attack-move, Stop, defensive stance with leash
- [x] Command feedback markers
- [x] Formation offsets for multi-unit moves
Phase 6 — UI
- [x] Minimap (explored/unexplored, friendly, visible enemies, click to pan)
- [x] Selection info panel (single + multi)
- [x] Health bars on damage/selection only
- [x] Camera zoom limits so the map is never fully visible
- [x] Debug overlays: vision circles, fog cells, paths, current command

## MILESTONE 3 — ENEMY AI (in progress)
- [x] Faction-aware economy: separate credit pools, per-side refinery registry
- [x] AIDirector: build order, production, harvester economy, attack waves
- [x] Enemy home resource field so the map is fair
- [x] Navmesh agent radius >= widest unit; resource nodes excluded from bake
- [ ] AI reacts to being attacked (pull defenders, rebuild losses)
- [ ] AI uses fog itself (needs a second visibility grid)
- [ ] AI uses Engineers/Spies

## MILESTONE 4 — VERTICAL SLICE
Done
- [x] Data-driven tech tree (prerequisites, population, category, producer on the .tres)
- [x] Construction queue: structures are paid for and timed, then placed (C&C model)
- [x] Separate parallel unit queues per production building
- [x] Construction influence radius; ghost validity vs overlap, blockers, bounds, radius
- [x] Walls + gate, drag-placed in a line
- [x] Machine Gun Tower, Anti-Armor Turret (reuse unit weapons + armour table)
- [x] Radar Center, Technology Center; Main Battle Tank behind Tech
- [x] Rifle Squad, Anti-Armor Squad; all values moved to the brief's numbers
- [x] LOW POWER: defences offline, construction and production at half rate
- [x] Unit cap from structures; queued orders count against it
- [x] Sell (50%), continuous repair, rally points, damage tinting at 60%/30%
- [x] Full HUD: categories, locked items with reasons, selection panel, progress, objectives
- [x] Match intro + staged objectives
- [x] Enemy escalation schedule; waves come only from real production
- [x] Infrastructure consequences (verified by tests/infrastructure_test.tscn)
- [x] Placeholder audio, synthesised in code
- [x] tests/vertical_slice_test.tscn covers the brief's acceptance sequence

Known gaps — verified 2026-10-14, each by its own code and tests
- [x] ~~No garrison mechanic~~ — `scripts/buildings/garrison_component.gd`, `tests/garrison_test.tscn`
- [x] ~~Veterancy/rank not implemented~~ — `scripts/units/veterancy_component.gd`
- [x] ~~No separate neutral-ownership state~~ — `BuildingBase.is_neutral`, `neutral_buildings` group
- [x] ~~AI does not use fog~~ — `scripts/ai/ai_memory.gd` observes symmetrically; it can be
      baited and surprised, and never reads hidden player state
- [x] ~~AI does not rebuild what it loses~~ — `tests/ai_economy_recovery_test.tscn`
- [ ] Gate does not physically open/close; it is passable to its owner via collision layers
- [x] ~~AI produces Engineers and Spies but does not use them tactically~~ — `_run_infiltration()`
      in `ai_director.gd`, pinned by `tests/ai_specialists_test.tscn`

## NEXT — rewritten 2026-10-14
The previous list was almost entirely stale. These were all claimed outstanding and are not:

- [x] Vehicle production building — `config/buildings/war_factory.tres`
- [x] Building construction time + visual progress — `scripts/buildings/construction_queue.gd`
- [x] Manual harvester → node assignment — `Harvester.assigned_node`, and a manual move order
      takes it off its route
- [x] Debounced navmesh rebakes — `main.gd` batches into one debounced request

Genuinely next:
- [ ] Gate open/close as real geometry and collision, not layer filtering
- [x] ~~AI tactical use of Engineers and Spies~~ — done. Targets come from AIMemory, so the
      commander can be baited by a structure that is no longer there; EASY abstains entirely,
      as a decision-quality difference rather than a numbers one
- [x] ~~Touch building-placement drag fights camera pan~~ — it was live. Reproduced at 30m of
      camera travel while positioning a ghost, fixed, and pinned by
      `tests/touch_placement_test.tscn`

## LATER — rewritten 2026-10-14
Also stale. All of these shipped:

- [x] Fog of war — autoload, grid, shader, `tests/fog_test.tscn`
- [x] Save system — `SaveGame`, `tests/save_resume_test.tscn`
- [x] Android export preset + on-device build/test — four APK variants, validated on an AVD
- [x] Real authored models — everything is generated through `assets/source/blender/om_kit.py`
- [x] Power shortage consequences — `GameState.is_low_power` slows construction
      (`LOW_POWER_SPEED`), shuts down the radar centre and disables defence towers
- [x] Strategic weapons — `scripts/buildings/strategic_structure.gd`
- [x] Veterancy — see above
- [x] Hard counters — armour classes and a damage-vs-armour table, tuned in `config/weapons/*.tres`

Actually later:
- [ ] **An air layer.** There are no aircraft and no anti-air: `config/units/` holds twelve
      units, all ground or naval. This is the largest missing axis of counterplay, not a polish
      item.
- [ ] Multiplayer-safe state sync. Deferred deliberately; GameState is a single deterministic
      source of truth rather than scattered globals, so the architecture does not block it.
- [ ] Tech progression / build tree gating.

## ACTIVE MISSION — the air layer
Marked 2026-10-14. The largest missing axis of counterplay: twelve units,
every one ground or naval, so there is no aircraft and no anti-air.

The ground is already prepared, which is why this is the next mission and
not a rewrite:
- `CombatTarget.Domain` is a real mask (LAND / NAVAL / SUBMERGED) and
  `domain_of()` is the single place that classifies a target.
- `WeaponStats.target_domains` already gates engagement by domain.
- `NavLayers` already runs two navmeshes off one pathfinder, so a third
  movement domain is an extension rather than a new system.

And a latent bug sits exactly here: **`WeaponStats.can_target_air` is set
by eleven weapon configs and read by nothing.** Designers have been
tuning a field that does not exist at runtime.

- [x] A1 Domain.AIR, Armor.Type.AIR, FLAK, and `can_target_air` now gates —
      `tests/air_domain_test.tscn`
- [x] A2 An aircraft that flies — the Gunship. No nav agent, straight-line flight, altitude
      held by the same settle pass that keeps ships on the water. `tests/air_flight_test.tscn`
- [ ] A3 Anti-air: a weapon and a unit that can answer it
- [ ] A4 The commander produces and uses both
- [ ] A5 Tests for each of the above

## OPEN ON HARDWARE
- [ ] Real-device validation: true GPU performance, thermal throttling, battery drain, touch
      ergonomics. The emulator rasterises in software at ~4 FPS and cannot speak to any of them.
      Sharpened by the art pass: infantry triangles rose 27-40% in battle scenarios while draw
      calls stayed flat, and vertex throughput is exactly what a software rasteriser hides.

## HOW TO KEEP THIS HONEST
This file had drifted badly: fog of war, saves, the Android export, construction progress,
strategic weapons and the power cascade were all listed as unbuilt while passing their own
tests, and four "known gaps" were closed. A plan built on it would have been wrong.

Check an item against `scripts/` and `tests/` before believing it.
