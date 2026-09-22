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

## Neutral structures belong to nobody: they never shoot, never feed
## either side's tech tree or power grid, and exist to be captured. This
## replaces the previous hack of giving map structures to the enemy,
## which made them count as enemy prerequisites and enemy power.
@export var is_neutral: bool = false

var health: HealthComponent

## Production structures send new units here. Vector3.ZERO means unset.
var rally_point: Vector3 = Vector3.ZERO
var repairing: bool = false

var health_bar: HealthBar
var _indicator: MeshInstance3D

const BUILDING_COLLISION_LAYER: int = 1 << 2 # bit 3
const SELL_REFUND: float = 0.5
const REPAIR_HP_PER_SECOND: float = 0.05
const REPAIR_CREDITS_PER_HP: float = 0.5

var _body: MeshInstance3D
## The instanced greybox, kept so capture can repaint its faction slot.
var _visual_root: Node = null
var _damage_stage: int = -1
var _damage_plume: Node = null

func get_faction() -> int:
	return GameState.Faction.PLAYER if is_player_faction else GameState.Faction.ENEMY

func _ready() -> void:
	add_to_group("buildings")
	if is_neutral:
		add_to_group("neutral_buildings")
	else:
		add_to_group("player_buildings" if is_player_faction else "enemy_buildings")

	collision_layer = BUILDING_COLLISION_LAYER
	collision_mask = 0

	_build_fog_visibility()
	_build_collision()
	_build_health()
	_build_visual()
	_build_health_bar()
	_build_garrison()
	_register_power()

func _build_garrison() -> void:
	if stats == null or not stats.garrisonable:
		return
	var garrison := GarrisonComponent.new()
	garrison.name = "GarrisonComponent"
	add_child(garrison)

func _build_fog_visibility() -> void:
	if is_player_faction and not is_neutral:
		return
	var hideable := FogHideable.new()
	hideable.name = "FogHideable"
	## A neutral structure does not move, so once discovered it stays on
	## the player's map - it is a landmark, not a patrol.
	hideable.persists_once_explored = is_neutral
	add_child(hideable)

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
	health.armor_type = Armor.Type.STRUCTURE
	add_child(health)
	health.died.connect(_on_died)

func _build_visual() -> void:
	## See UnitBase._build_visual for what OM_NO_MODELS is for.
	if stats and stats.visual_scene and OS.get_environment("OM_NO_MODELS").is_empty():
		var visual := stats.visual_scene.instantiate()
		add_child(visual)
		_visual_root = visual
		FactionPaint.apply(visual, _faction_color())
		return

	var size: Vector3 = stats.body_size if stats else Vector3(5, 3, 5)
	_body = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	_body.mesh = mesh
	_body.position = Vector3(0, size.y / 2.0, 0)

	var material := StandardMaterial3D.new()
	material.albedo_color = stats.body_color if stats else Color.GRAY
	_body.material_override = material
	add_child(_body)

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

func _build_health_bar() -> void:
	var size: Vector3 = stats.body_size if stats else Vector3(5, 3, 5)
	health_bar = HealthBar.attach(self, health, size.y, maxf(size.x * 0.8, 2.0))

func _faction_color() -> Color:
	if is_neutral:
		return Color(0.85, 0.85, 0.6)
	return Color(0.2, 0.45, 1.0) if is_player_faction else Color(0.9, 0.15, 0.15)

## Hand the structure to the other side, intact and at full health. Power
## bookkeeping is moved with it and subclasses get a chance to re-register
## whatever they own (refinery lists, factory groups), so a captured
## building genuinely works for its new owner.
func set_faction(player: bool) -> void:
	## A neutral structure is always capturable: its is_player_faction
	## flag is meaningless until someone owns it, so comparing against it
	## here would silently no-op every capture by the player.
	if not is_neutral and is_player_faction == player:
		return

	_on_faction_changing()
	_unregister_power()
	if is_neutral:
		remove_from_group("neutral_buildings")
	else:
		remove_from_group("player_buildings" if is_player_faction else "enemy_buildings")

	is_neutral = false
	is_player_faction = player

	add_to_group("player_buildings" if is_player_faction else "enemy_buildings")
	_register_power()
	if _indicator != null:
		var material := _indicator.material_override as StandardMaterial3D
		if material != null:
			material.albedo_color = _faction_color()
	## Capturing a structure repaints it rather than swapping the model.
	if _visual_root != null:
		FactionPaint.apply(_visual_root, _faction_color())
	if health != null:
		health.heal_to_full()

	## A structure you now own is never hidden from you, and one you just
	## lost stops being permanently visible.
	var hideable := get_node_or_null("FogHideable")
	if is_player_faction and hideable != null:
		hideable.queue_free()
		visible = true
		collision_layer = BUILDING_COLLISION_LAYER
	elif not is_player_faction and hideable == null:
		_build_fog_visibility()

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

## GameState holds the *player's* economy, so only player-owned
## structures touch the grid. Without this an enemy power plant would
## show up as generation on the player's HUD - and capturing one would
## do nothing, because its output was already counted.
func _register_power() -> void:
	if stats == null or is_neutral or not is_player_faction:
		return
	if stats.power_generation > 0 and _contributes_power():
		GameState.register_power_generation(stats.power_generation)
	if stats.power_consumption > 0:
		GameState.register_power_consumption(stats.power_consumption)

func _unregister_power() -> void:
	if stats == null or is_neutral or not is_player_faction:
		return
	if stats.power_generation > 0 and _contributes_power():
		GameState.unregister_power_generation(stats.power_generation)
	if stats.power_consumption > 0:
		GameState.unregister_power_consumption(stats.power_consumption)

## Refund half the build cost and remove the structure. Selling is how a
## player recovers from a misplaced building or trades a doomed outpost
## for tanks, so it returns real money rather than being a delete key.
func sell() -> void:
	if not is_player_faction:
		return
	GameState.add_credits_for(true, int(round(stats.cost * SELL_REFUND)))
	_unregister_power()
	EventBus.building_sold.emit(self)
	queue_free()

func can_repair() -> bool:
	return health != null and health.current_health < health.max_health

func toggle_repair() -> void:
	repairing = not repairing and can_repair()

## Repairs drain credits continuously while active, so holding a damaged
## base together competes with building a new one.
func _tick_repair(delta: float) -> void:
	if not repairing:
		return
	if not can_repair():
		repairing = false
		return
	var heal: float = health.max_health * REPAIR_HP_PER_SECOND * delta
	var price: int = int(ceil(heal * REPAIR_CREDITS_PER_HP))
	if price > 0 and not GameState.try_spend_for(is_player_faction, price):
		repairing = false
		return
	health.heal(heal)

func _process(delta: float) -> void:
	_tick_repair(delta)
	_refresh_damage_visual()

## Buildings show wear so a fight can be read at a glance without
## selecting anything: a scorch tint at 60% health, heavier at 30%.
func _refresh_damage_visual() -> void:
	if health == null or _body == null:
		return
	var fraction: float = health.health_fraction()
	var stage: int = 0 if fraction > 0.6 else (1 if fraction > 0.3 else 2)
	if stage == _damage_stage:
		return
	_damage_stage = stage
	_refresh_damage_plume(stage)
	var material := _body.material_override as StandardMaterial3D
	if material == null:
		return
	var base: Color = stats.body_color if stats else Color.GRAY
	match stage:
		0: material.albedo_color = base
		1: material.albedo_color = base.darkened(0.28)
		2: material.albedo_color = base.darkened(0.55).lerp(Color(0.15, 0.08, 0.05), 0.35)

## Smoke from stage 1, fire as well from stage 2, and nothing at all once
## repaired - a burning building that stays burning after repair teaches
## the player to distrust the effect.
func _refresh_damage_plume(stage: int) -> void:
	if _damage_plume != null and is_instance_valid(_damage_plume):
		_damage_plume.queue_free()
		_damage_plume = null
	if stage <= 0:
		return
	var size: Vector3 = stats.body_size if stats else Vector3(5, 3, 5)
	_damage_plume = VFX.damage_plume(self, Vector3(0, size.y * 0.85, 0), stage)

func _on_died() -> void:
	VFX.explosion_large(self, global_position + Vector3.UP)
	MatchStats.record_building_death(is_player_faction and not is_neutral)
	AudioDirector.play("explosion_large")
	_unregister_power()
	died.emit(self)
	EventBus.building_destroyed.emit(self)
	queue_free()
