extends Node

## Autoload: lightweight signal hub for cross-system events that don't
## belong to a single owner (e.g. the navmesh needing a rebake after a
## building is placed). Keeps buildings/units from needing direct
## references to unrelated systems.

signal building_placed(building: Node)
signal unit_spawned(unit: Node)
