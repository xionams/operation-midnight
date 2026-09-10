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
- Play-test in the Godot editor (not yet run in this environment — no Godot binary available here) and fix any parser/runtime errors on first launch.

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
