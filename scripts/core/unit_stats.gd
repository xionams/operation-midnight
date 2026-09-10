extends Resource
class_name UnitStats

## Data-driven stat block for a unit. Designers tune balance here,
## never in gameplay scripts.

@export var display_name: String = "Unit"
@export var cost: int = 0
@export var max_health: float = 100.0
@export var move_speed: float = 5.0
@export var turn_speed: float = 6.0
@export var nav_radius: float = 1.0

## Placeholder visual (ignored once a real visual_scene is assigned).
@export var body_color: Color = Color.WHITE
@export var body_size: Vector3 = Vector3(1.5, 1.0, 2.2)

## Optional weapon. Leave null for unarmed units (scout, harvester).
@export var weapon_stats: WeaponStats = null

## Harvester-only fields. Ignored by other unit types.
@export var is_harvester: bool = false
@export var cargo_capacity: float = 0.0
@export var load_time: float = 0.0
@export var unload_time: float = 0.0

## Replace with a Blender-authored PackedScene later; when set, unit
## scripts instance this instead of building the primitive placeholder.
@export var visual_scene: PackedScene = null
