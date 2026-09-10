extends Resource
class_name UnitStats

## Data-driven stat block for a unit. Designers tune balance here,
## never in gameplay scripts.

@export var display_name: String = "Unit"
@export var cost: int = 0

## Structures required before this unit can be produced.
@export var prerequisites: PackedStringArray = PackedStringArray()

## How much of the unit cap this consumes.
@export var population: int = 1

## Which production panel tab lists it, and which building trains it.
@export var category: String = "INFANTRY"
@export var produced_by: String = ""

## The scene to instance. Mirrors BuildingStats.scene, so production is
## one generic call rather than a hardcoded method per unit type.
@export var unit_scene: PackedScene = null 
@export var build_time: float = 0.0 ## Seconds in a ProductionQueue; 0 spawns instantly.
@export var max_health: float = 100.0
@export var move_speed: float = 5.0
@export var turn_speed: float = 6.0
@export var nav_radius: float = 1.0

## How far this unit reveals fog. The Scout exists because this number
## is much larger on it than on anything else.
@export var vision_range: float = 14.0

## Placeholder visual (ignored once a real visual_scene is assigned).
@export var body_color: Color = Color.WHITE
@export var body_size: Vector3 = Vector3(1.5, 1.0, 2.2)

## Optional weapon. Leave null for unarmed units (scout, harvester).
@export var weapon_stats: WeaponStats = null

## What this unit counts as when something shoots it.
@export var armor_type: Armor.Type = Armor.Type.HEAVY

## Infantry are cheap, squishy and can be run over. Vehicles that set
## can_crush flatten any crushable unit they drive into — the classic
## reason you never send infantry alone against armour.
@export var is_infantry: bool = false
@export var can_be_crushed: bool = false
@export var can_crush: bool = false

## Harvester-only fields. Ignored by other unit types.
@export var is_harvester: bool = false
@export var cargo_capacity: float = 0.0
@export var load_time: float = 0.0
@export var unload_time: float = 0.0

## Replace with a Blender-authored PackedScene later; when set, unit
## scripts instance this instead of building the primitive placeholder.
@export var visual_scene: PackedScene = null
