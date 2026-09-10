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

## NEXT
- Vehicle production building (factory/barracks equivalent) so units are buildable mid-match.
- Building construction time + visual progress (field already exists on BuildingStats).
- Manual harvester → resource node assignment (currently fully automatic).
- Debounce/throttle navmesh rebakes when multiple buildings are placed in quick succession.
- Fix camera panning during touch building-placement drag (currently both react to the same drag).

## LATER
- Power shortage consequences (slower production → radar shutdown → defenses disabled → strategic weapon pause, in that order per the brief).
- Additional unit types and hard counters (anti-tank, anti-air, artillery, infantry).
- Fog of war.
- Veterancy, strategic weapons, tech progression.
- Real Blender-authored models (swap in via `visual_scene` on the relevant `.tres` — no code changes needed).
- Android export preset + on-device build/test (needs Android SDK + keystore, not set up yet).
- Save system.
- Multiplayer-safe state sync (deferred, but current architecture avoids local-only assumptions where practical — GameState is a single deterministic source of truth, not scattered globals).
