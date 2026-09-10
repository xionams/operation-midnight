extends StaticBody3D
class_name BuildingBase

## Shared behavior for every structure: collision footprint, health,
## the placeholder visual body, and power bookkeeping. Concrete
## buildings (CommandHQ, PowerPlant, Refinery) only add what makes
## them different. Swapping in a real Blender model later only means
## setting stats.visual_scene; this script never changes.

signal died(building: BuildingBase)

@export var stats: BuildingStats
@export var is_player_faction: bool = true

var health: HealthComponent

var _indicator: MeshInstance3D

const BUILDING_COLLISION_LAYER: int = 1 << 2 # bit 3

func get_faction() -> int:
	return GameState.Faction.PLAYER if is_player_faction else GameState.Faction.ENEMY

func _ready() -> void:
	add_to_group("buildings")
	add_to_group("player_buildings" if is_player_faction else "enemy_buildings")

	collision_layer = BUILDING_COLLISION_LAYER
	collision_mask = 0

	_build_collision()
	_build_health()
	_build_visual()
	_register_power()

func _build_collision() -> void:
	var size: Vector3 = stats.body_size if stats else Vector3(5, 3, 5)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0, size.y / 2.0, 0)
	add_child(shape)

func _build_health() -> void:
	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = stats.max_health if stats else 500.0
	health.armor_type = Armor.Type.BUILDING
	add_child(health)
	health.died.connect(_on_died)

func _build_visual() -> void:
	if stats and stats.visual_scene:
		var visual := stats.visual_scene.instantiate()
		add_child(visual)
		return

	var size: Vector3 = stats.body_size if stats else Vector3(5, 3, 5)
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	body.mesh = mesh
	body.position = Vector3(0, size.y / 2.0, 0)

	var material := StandardMaterial3D.new()
	material.albedo_color = stats.body_color if stats else Color.GRAY
	body.material_override = material
	add_child(body)

	_indicator = MeshInstance3D.new()
	var indicator_mesh := BoxMesh.new()
	indicator_mesh.size = Vector3(size.x * 0.9, 0.2, 0.6)
	_indicator.mesh = indicator_mesh
	_indicator.position = Vector3(0, size.y + 0.15, size.z / 2.0)
	var indicator_material := StandardMaterial3D.new()
	indicator_material.albedo_color = _faction_color()
	indicator_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_indicator.material_override = indicator_material
	add_child(_indicator)

func _faction_color() -> Color:
	return Color(0.2, 0.45, 1.0) if is_player_faction else Color(0.9, 0.15, 0.15)

## Hand the structure to the other side, intact and at full health. Power
## bookkeeping is moved with it and subclasses get a chance to re-register
## whatever they own (refinery lists, factory groups), so a captured
## building genuinely works for its new owner.
func set_faction(player: bool) -> void:
	if is_player_faction == player:
		return

	_on_faction_changing()
	_unregister_power()
	remove_from_group("player_buildings" if is_player_faction else "enemy_buildings")

	is_player_faction = player

	add_to_group("player_buildings" if is_player_faction else "enemy_buildings")
	_register_power()
	if _indicator != null:
		var material := _indicator.material_override as StandardMaterial3D
		if material != null:
			material.albedo_color = _faction_color()
	if health != null:
		health.heal_to_full()
	_on_faction_changed()
	EventBus.building_captured.emit(self, is_player_faction)

## Overridden by buildings that register themselves somewhere on _ready.
func _on_faction_changing() -> void:
	pass

func _on_faction_changed() -> void:
	pass

## PowerPlant reports false while blacked out so a dark plant does not
## unregister generation it already gave back.
func _contributes_power() -> bool:
	return true

func _register_power() -> void:
	if stats == null:
		return
	if stats.power_generation > 0 and _contributes_power():
		GameState.register_power_generation(stats.power_generation)
	if stats.power_consumption > 0:
		GameState.register_power_consumption(stats.power_consumption)

func _unregister_power() -> void:
	if stats == null:
		return
	if stats.power_generation > 0 and _contributes_power():
		GameState.unregister_power_generation(stats.power_generation)
	if stats.power_consumption > 0:
		GameState.unregister_power_consumption(stats.power_consumption)

func _on_died() -> void:
	_unregister_power()
	died.emit(self)
	queue_free()
