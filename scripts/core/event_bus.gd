extends Node

## Autoload: lightweight signal hub for cross-system events that don't
## belong to a single owner (e.g. the navmesh needing a rebake after a
## building is placed). Keeps buildings/units from needing direct
## references to unrelated systems.

signal building_placed(building: Node)
signal unit_spawned(unit: Node)
signal building_captured(building: Node, by_player: bool)
signal building_infiltrated(building: Node, effect: String)
## Fired for every accepted order so the HUD can show the player that
## their command landed, without the command path knowing about the UI.
signal command_issued(type: int, position: Vector3)
signal building_sold(building: Node)
## Emitted for every structure that dies, whichever side owned it. The AI
## uses it to notice when it has just cost the player their economy.
signal building_destroyed(building: Node)
signal construction_ready(stats: BuildingStats)
signal objective_changed(title: String, lines: PackedStringArray)
signal low_power_changed(low: bool)
signal no_resources_available(harvester: Node)
## Emitted when a harvester completes a full gather-and-deliver cycle,
## so economic route quality can be measured rather than assumed.
signal harvest_round_trip(is_player: bool, seconds: float)
