extends Node3D
class_name BuildingPlacer

## Ghost-preview building placement. Started by the HUD build buttons
## (start_placement), it shows a translucent footprint that follows
## the pointer, turns red/green based on validity, and consumes input
## exclusively while active so SelectionManager/RTSCamera don't react
## to the same click/tap. Credits are only deducted on a valid,
## confirmed placement.

signal placement_started(stats: BuildingStats)
signal placement_ended

@export var bounds_min: Vector2 = Vector2(-55, -55)
@export var bounds_max: Vector2 = Vector2(55, 55)

const GROUND_MASK: int = 1
const RAY_LENGTH: float = 500.0
const VALID_COLOR: Color = Color(0.2, 1.0, 0.3, 0.45)
const INVALID_COLOR: Color = Color(1.0, 0.2, 0.2, 0.45)

var active_stats: BuildingStats = null

var _ghost: MeshInstance3D = null
var _ghost_material: StandardMaterial3D = null
var _valid: bool = false
var _pointer_pos: Vector2 = Vector2.ZERO
var _camera: Camera3D = null

func _get_camera() -> Camera3D:
	if not is_instance_valid(_camera):
		_camera = get_tree().get_first_node_in_group("rts_camera") as Camera3D
	return _camera

func is_placing() -> bool:
	return active_stats != null

func start_placement(stats: BuildingStats) -> void:
	if stats == null or stats.scene == null:
		return
	cancel_placement()
	active_stats = stats
	_build_ghost()
	placement_started.emit(stats)

func cancel_placement() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	if active_stats != null:
		active_stats = null
		placement_ended.emit()

func _build_ghost() -> void:
	_ghost = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = active_stats.body_size
	_ghost.mesh = mesh
	_ghost.visible = false
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = _ghost_material
	add_child(_ghost)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pointer_pos = (event as InputEventMouseMotion).position
	elif event is InputEventScreenDrag:
		_pointer_pos = (event as InputEventScreenDrag).position
	elif event is InputEventScreenTouch:
		_pointer_pos = (event as InputEventScreenTouch).position

	if active_stats == null:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_try_confirm()
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		if not (event as InputEventScreenTouch).pressed:
			_try_confirm()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if active_stats == null or _ghost == null:
		return
	var hit_pos: Variant = _raycast_ground(_pointer_pos)
	if hit_pos == null:
		_ghost.visible = false
		_valid = false
		return
	_ghost.visible = true
	_ghost.global_position = Vector3(hit_pos.x, active_stats.body_size.y / 2.0, hit_pos.z)
	_valid = _check_validity(hit_pos)
	_ghost_material.albedo_color = VALID_COLOR if _valid else INVALID_COLOR

func _raycast_ground(screen_pos: Vector2) -> Variant:
	var camera := _get_camera()
	if camera == null:
		return null
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * RAY_LENGTH
	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, GROUND_MASK)
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit.get("position")

func _check_validity(pos: Vector3) -> bool:
	var footprint: Vector2 = active_stats.footprint
	if pos.x - footprint.x / 2.0 < bounds_min.x or pos.x + footprint.x / 2.0 > bounds_max.x:
		return false
	if pos.z - footprint.y / 2.0 < bounds_min.y or pos.z + footprint.y / 2.0 > bounds_max.y:
		return false

	var buildings: Array = get_tree().get_nodes_in_group("buildings")
	for building in buildings:
		if not is_instance_valid(building) or building.stats == null:
			continue
		var other_pos: Vector3 = building.global_position
		var other_fp: Vector2 = building.stats.footprint
		var overlap_x: bool = abs(pos.x - other_pos.x) < (footprint.x + other_fp.x) / 2.0
		var overlap_z: bool = abs(pos.z - other_pos.z) < (footprint.y + other_fp.y) / 2.0
		if overlap_x and overlap_z:
			return false
	return true

func _try_confirm() -> void:
	if active_stats == null:
		return
	var hit_pos: Variant = _raycast_ground(_pointer_pos)
	if hit_pos == null or not _check_validity(hit_pos):
		return
	if GameState.credits < active_stats.cost:
		return

	var building = active_stats.scene.instantiate()
	building.stats = active_stats
	building.is_player_faction = true
	get_tree().current_scene.get_node("Level/NavRegion").add_child(building)
	building.global_position = Vector3(hit_pos.x, 0, hit_pos.z)

	GameState.try_spend(active_stats.cost)
	EventBus.building_placed.emit(building)

	active_stats = null
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	placement_ended.emit()
