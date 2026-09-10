# Operation Midnight

A near-future military RTS for Android, built in Godot 4.x, inspired by the base-building/harvesting/combat loop of classic C&C-style RTS games. This is **Milestone 1**: a small vertical slice proving that camera, selection, movement, building, harvesting, economy, and combat all work together. It is not a full game yet — no menus, no campaign, no multiplayer.

## Opening the project

- **Godot version:** 4.3+ (any Godot 4.x with `Forward Plus` rendering should work).
- Open Godot, choose "Import", select this folder's `project.godot`, then open. The editor will import `icon.svg` and the `.tres` config resources automatically.
- Press **F5** (or the Play button) to run. `main.tscn` at the project root is the entry point and *is* the battlefield — there is no menu in front of it yet.

There is nothing to build/export for Android to just try the prototype — run it in the editor (desktop) first. See "Android" below for what's already in place versus what's still needed for an actual device build.

## Project structure

```
res://
├── config/                  Resource (.tres) instances — the actual balance numbers.
│   ├── units/                assault_vehicle.tres, scout_vehicle.tres, harvester.tres
│   ├── buildings/             command_hq.tres, power_plant.tres, refinery.tres
│   ├── weapons/                assault_cannon.tres
│   └── economy/                 default_economy.tres
├── scenes/
│   ├── units/                Minimal .tscn wrappers (root node + script only — see below)
│   ├── buildings/
│   ├── resources/             resource_node.tscn
│   └── maps/                  (reserved for future authored maps; Milestone 1's single
│                               battlefield is assembled procedurally by scripts/core/main.gd)
├── scripts/
│   ├── core/                  GameState, EventBus, SelectionManager (autoloads), RTSCamera,
│   │                          UnitStats/BuildingStats/WeaponStats/EconomyConfig (data schemas), main.gd
│   ├── units/                  UnitBase + AssaultVehicle/ScoutVehicle/Harvester, HealthComponent,
│   │                          EnemyAIController
│   ├── buildings/               BuildingBase + CommandHQ/PowerPlant/Refinery, BuildingPlacer
│   ├── economy/                  ResourceNode
│   ├── combat/                    Weapon, AttackerComponent
│   └── ui/                         HUD
└── main.tscn                 Battlefield entry scene
```

### Why the scenes are almost empty

Every unit/building `.tscn` is just a root node (`CharacterBody3D` / `StaticBody3D`) with a script attached — no baked-in child nodes. The script builds its own collision shape, `NavigationAgent3D`, health component, and placeholder mesh at runtime from its assigned `UnitStats`/`BuildingStats` resource (see `stats.visual_scene` / `stats.body_color` / `stats.body_size`). This means:

- No hand-authored scene trees to get out of sync with the scripts.
- Swapping in a real Blender-made model later is a **data change**, not a code change: set `visual_scene` on the relevant `.tres` to a `PackedScene` and the primitive box/torus placeholder is skipped in favor of it. Nothing in `unit_base.gd` / `building_base.gd` needs to change.

## How the major systems interact

- **GameState** (autoload) is the single source of truth for credits, power generated/consumed, match state, and the list of player refineries. Buildings register their power draw/generation with it on spawn and unregister on death. Nothing else holds gameplay state that matters across systems.
- **EventBus** (autoload) carries cross-cutting signals that don't belong to one owner — currently just `building_placed`, which triggers an async navmesh rebake, and `unit_spawned`.
- **SelectionManager** (autoload) owns "what's selected" and turns clicks/taps into `move_to()` / `attack_target()` calls on units. Units never read input directly.
- **UnitBase** (`CharacterBody3D`) is the shared chassis for every mobile unit: `NavigationAgent3D`-driven movement, facing, the selection ring, and death handling via a child `HealthComponent`. `AssaultVehicle`, `ScoutVehicle`, and `Harvester` all extend it and only add what's different (a weapon, a harvest state machine, nothing).
- **AttackerComponent + Weapon** are a reusable pair: any unit that should fight attaches both instead of writing its own targeting/firing code. `AssaultVehicle.gd` is ~15 lines because of this.
- **BuildingBase** (`StaticBody3D`) is the equivalent chassis for structures. `CommandHQ` reports its destruction to `GameState` (this is the win/loss condition); `PowerPlant` and `Refinery` are almost entirely data-driven.
- **Harvester** never grants credits directly — it runs a state machine (`IDLE → TO_NODE → LOADING → TO_REFINERY → UNLOADING`) and only pays out via `Refinery.receive_resources()` after physically completing a round trip. This is intentional: the economy is meant to be attackable.
- **BuildingPlacer** owns ghost-preview placement (follows the pointer, validates footprint/overlap/bounds, deducts credits only on success) and exclusively consumes input while active so it doesn't fight with `SelectionManager`/`RTSCamera` for the same click/tap.
- **EnemyAIController** is a small "defend a radius around spawn" component attached only to enemy units — player units never carry faction-specific code.
- Navigation is a single runtime-baked `NavigationMesh` on one `NavigationRegion3D` (`Level/NavRegion`). It's baked synchronously once at match start (after both bases and the resource fields exist) and rebaked on a background thread whenever a building is placed, so new player structures block pathing.

## Controls

**Desktop (for development):**
- `WASD` / arrow keys — pan camera
- Mouse wheel — zoom
- Left click — select a unit; left-drag — box-select; click empty ground — deselect
- Right click — move selected units, or attack-move if you right-click an enemy
- `F3` — toggle debug overlay (FPS, unit count, credits, power, match state)

**Android (touch):**
- One-finger drag over terrain — pan camera
- Two-finger pinch — zoom
- Tap a unit — select it
- Tap terrain after selecting units — move there; tap an enemy — attack it
- HUD buttons (bottom bar) — Build Power Plant / Build Refinery / Build Harvester / Cancel (while placing, drag to position the ghost, lift your finger to confirm)

## Running the prototype

Open in Godot 4.x and press Play. You start with a Command HQ, one Assault Vehicle, one Scout Vehicle, and 5,000 credits in the southwest corner; the enemy holds the northeast corner with their own HQ and two Assault Vehicles that defend their base radius. Two Strategic Resource fields (8,000 credits each) sit between the bases. Build a Power Plant, then a Refinery, then a Harvester from the HUD; the harvester will automatically find a resource node and start hauling credits back. Attack-move your Assault Vehicle into the enemy base to end the match.

## Known limitations (Milestone 1)

- No production time / construction animation — buildings complete instantly, but `BuildingStats.build_time` and `UnitStats` already have the fields wired in for when that's added.
- Only the Harvester is producible mid-match (from a Refinery); there's no vehicle factory yet, so Assault Vehicles/Scouts only exist as starting units.
- Enemy AI is "defend a radius, attack the nearest player unit within range" — no group tactics, no base-building, no threat response.
- Power shortages are tracked and shown in the HUD but don't yet throttle production/radar/defenses (explicitly deferred per the brief).
- Navmesh rebakes on building placement are threaded but not debounced — placing buildings in rapid succession queues multiple bakes. Not a problem at Milestone 1 build rates.
- No save system, no Android export preset (no Android SDK/keystore configured in this environment) — the input/UI layer is already touch-complete, but an actual `.apk` has not been produced or tested on a device/emulator.
- Camera can still pan via one-finger drag while a building ghost is being positioned on touch, which can feel like the ghost "overshoots" the finger. Minor polish item.

## Remaining/likely bugs

- Nothing has been run inside the Godot editor in this environment (no Godot binary available here), so this has been written and statically reviewed for GDScript correctness but not play-tested. Please open it in the editor and check the Output panel for parser errors on first run — most likely failure points would be a typo in a `.tres`/`.tscn` resource path or a NavigationMesh property name.

## Recommended Milestone 2 tasks

- A vehicle production building (barracks/war factory equivalent) so Assault Vehicles/Scouts are buildable, not just starting units.
- Construction time for buildings + a build queue for units, using the already-present `build_time` field.
- Power shortage consequences (slower production first, per the brief's suggested order).
- Manual harvester resource-node assignment (right now it's fully automatic).
- Basic fog of war.
- A second, distinct enemy unit type to force counter-play instead of one unit into another.
