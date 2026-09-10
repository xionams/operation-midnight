extends CharacterBody3D
class_name UnitBase

## Shared behavior for every mobile unit: navigation movement, facing,
## the selection ring, health wiring, and the placeholder visual body.
## Concrete units (AssaultVehicle, ScoutVehicle, Harvester) extend this
## and only add what makes them different — combat, harvesting, etc.
## Swapping in a real Blender model later only means setting
## stats.visual_scene; this script never changes.

signal died(unit: UnitBase)

@export var stats: UnitStats
@export var is_player_faction: bool = true

var health: HealthComponent
var nav_agent: NavigationAgent3D
var selection_ring: MeshInstance3D

const UNIT_COLLISION_LAYER: int = 1 << 1 # bit 2
const GROUND_COLLISION_LAYER: int = 1 << 0 # bit 1

func get_faction() -> int:
	return GameState.Faction.PLAYER if is_player_faction else GameState.Faction.ENEMY

func _ready() -> void:
	add_to_group("units")
	add_to_group("player_units" if is_player_faction else "enemy_units")

	collision_layer = UNIT_COLLISION_LAYER
	collision_mask = GROUND_COLLISION_LAYER | UNIT_COLLISION_LAYER

	_build_collision()
	_build_nav_agent()
	_build_health()
	_build_visual()
	_build_selection_ring()

func _build_collision() -> void:
	var size: Vector3 = stats.body_size if stats else Vector3(1.5, 1.0, 2.2)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0, size.y / 2.0, 0)
	add_child(shape)

func _build_nav_agent() -> void:
	nav_agent = NavigationAgent3D.new()
	nav_agent.radius = stats.nav_radius if stats else 1.0
	nav_agent.path_desired_distance = 0.6
	nav_agent.target_desired_distance = 0.8
	nav_agent.avoidance_enabled = false
	add_child(nav_agent)

func _build_health() -> void:
	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = stats.max_health if stats else 100.0
	add_child(health)
	health.died.connect(_on_died)

func _build_visual() -> void:
	if stats and stats.visual_scene:
		var visual := stats.visual_scene.instantiate()
		add_child(visual)
		return

	var size: Vector3 = stats.body_size if stats else Vector3(1.5, 1.0, 2.2)
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	body.mesh = mesh
	body.position = Vector3(0, size.y / 2.0, 0)

	var material := StandardMaterial3D.new()
	material.albedo_color = stats.body_color if stats else Color.GRAY
	body.material_override = material
	add_child(body)

	var indicator := MeshInstance3D.new()
	var indicator_mesh := BoxMesh.new()
	indicator_mesh.size = Vector3(size.x * 0.3, 0.15, size.z * 0.3)
	indicator.mesh = indicator_mesh
	indicator.position = Vector3(0, size.y + 0.1, size.z * 0.25)
	var indicator_material := StandardMaterial3D.new()
	indicator_material.albedo_color = Color(0.2, 0.45, 1.0) if is_player_faction else Color(0.9, 0.15, 0.15)
	indicator_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	indicator.material_override = indicator_material
	add_child(indicator)

func _build_selection_ring() -> void:
	selection_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	var radius: float = max(stats.body_size.x, stats.body_size.z) * 0.7 if stats else 1.2
	ring.inner_radius = radius
	ring.outer_radius = radius + 0.15
	selection_ring.mesh = ring
	selection_ring.position = Vector3(0, 0.05, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 1.0, 0.3)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	selection_ring.material_override = material
	selection_ring.visible = false
	add_child(selection_ring)

func set_selected(selected: bool) -> void:
	if selection_ring:
		selection_ring.visible = selected

func move_to(target_position: Vector3) -> void:
	if nav_agent:
		nav_agent.target_position = target_position

func stop_moving() -> void:
	if nav_agent:
		nav_agent.target_position = global_position
	velocity = Vector3.ZERO

func face_towards(target_position: Vector3) -> void:
	var direction: Vector3 = target_position - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	var desired_rotation: float = atan2(direction.x, direction.z)
	var turn_speed: float = stats.turn_speed if stats else 6.0
	rotation.y = lerp_angle(rotation.y, desired_rotation, clamp(turn_speed * get_physics_process_delta_time(), 0.0, 1.0))

func attack_target(target: Node) -> void:
	var attacker: AttackerComponent = get_node_or_null("AttackerComponent")
	if attacker:
		attacker.set_target(target)
	elif target is Node3D:
		move_to((target as Node3D).global_position)

func _physics_process(delta: float) -> void:
	if nav_agent == null or nav_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var next_position: Vector3 = nav_agent.get_next_path_position()
	var direction: Vector3 = next_position - global_position
	direction.y = 0.0

	if direction.length() > 0.05:
		var desired_rotation: float = atan2(direction.x, direction.z)
		var turn_speed: float = stats.turn_speed if stats else 6.0
		rotation.y = lerp_angle(rotation.y, desired_rotation, clamp(turn_speed * delta, 0.0, 1.0))
		var speed: float = stats.move_speed if stats else 5.0
		velocity = direction.normalized() * speed
	else:
		velocity = Vector3.ZERO

	move_and_slide()

func _on_died() -> void:
	died.emit(self)
	SelectionManager.notify_unit_removed(self)
	queue_free()
