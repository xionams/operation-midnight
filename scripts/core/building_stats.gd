extends Resource
class_name BuildingStats

## Data-driven stat block for a building.

@export var display_name: String = "Building"
@export var cost: int = 0

## Display names of structures that must exist before this can be built.
## Kept as data so availability is one shared query rather than
## prerequisite checks scattered through UI scripts.
@export var prerequisites: PackedStringArray = PackedStringArray()

## How much unit capacity owning this structure grants.
@export var population_provided: int = 0

## Sorting/grouping in the production panel.
@export var category: String = "BUILDINGS"

## Structures that exist only to be walls: cheap, fast, and excluded from
## the normal build panel listing order.
@export var is_wall: bool = false

## Extends the area the owner may build in, in metres.
@export var build_radius_bonus: float = 8.0

## Defensive structures mount a weapon and are disabled by low power.
@export var weapon_stats: WeaponStats = null
@export var is_defensive: bool = false

## Infantry can occupy this structure and fire from inside it.
@export var garrisonable: bool = false
@export var max_health: float = 500.0
@export var build_time: float = 0.0 ## Instant in Milestone 1; wired for later.
@export var power_generation: int = 0
@export var power_consumption: int = 0

## How far this structure reveals fog.
@export var vision_range: float = 12.0

## Footprint used for overlap checks and the ghost preview, in meters.
@export var footprint: Vector2 = Vector2(6, 6)

@export var body_color: Color = Color.WHITE
@export var body_size: Vector3 = Vector3(5, 3, 5)

## Replace with a Blender-authored PackedScene later.
@export var visual_scene: PackedScene = null

## Scene to instance when this building is placed via the build menu.
@export var scene: PackedScene = null
