extends Resource
class_name BuildingStats

## Data-driven stat block for a building.

@export var display_name: String = "Building"
@export var cost: int = 0
@export var max_health: float = 500.0
@export var build_time: float = 0.0 ## Instant in Milestone 1; wired for later.
@export var power_generation: int = 0
@export var power_consumption: int = 0

## Footprint used for overlap checks and the ghost preview, in meters.
@export var footprint: Vector2 = Vector2(6, 6)

@export var body_color: Color = Color.WHITE
@export var body_size: Vector3 = Vector3(5, 3, 5)

## Replace with a Blender-authored PackedScene later.
@export var visual_scene: PackedScene = null

## Scene to instance when this building is placed via the build menu.
@export var scene: PackedScene = null
