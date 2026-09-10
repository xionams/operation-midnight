extends Node3D
class_name BuildingPlacer

## Ghost-preview structure placement.
##
## A structure may only go down inside the player's construction
## influence - the union of a radius around each building they own. That
## is what makes a base grow outward from the HQ instead of appearing
## anywhere on the map, and it gives forward structures a real purpose:
## they extend where you may build next.
##
## The influence footprint is drawn only while placing, so it informs the
## decision without cluttering the battlefield the rest of the time.
##
## Walls support drag placement: press, drag, release lays a line of
## segments, which is the difference between walling a base and tapping
## fifty times.

signal placement_started(stats: BuildingStats)
signal placement_ended

@export var bounds_min: Vector2 = Vector2(-104, -104)
@export var bounds_max: Vector2 = Vector2(104, 104)

const GROUND_MASK: int = 1
const RAY_LENGTH: float = 800.0
const VALID_COLOR: Color = Color(0.2, 1.0, 0.3, 0.45)
const INVALID_COLOR: Color = Color(1.0, 0.2, 0.2, 0.45)
const MAX_WALL_SEGMENTS: int = 24

var active_stats: BuildingStats = null
var construction_queue: ConstructionQueue

var _ghost: MeshInstance3D = null
var _ghost_material: StandardMaterial3D = null
var _radius_ring: MeshInstance3D = null
var _wall_ghosts: Array = []
var _valid: bool = false
var _pointer_pos: Vector2 = Vector2.ZERO
var _camera: Camera3D = null
var _wall_anchor: Variant = null

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
	_build_radius_ring()
	placement_started.emit(stats)

func cancel_placement() -> void:
	_clear_wall_ghosts()
	_wall_anchor = null
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	if _radius_ring != null:
		_radius_ring.queue_free()
		_radius_ring = null
	if active_stats != null:
		active_stats = null
		placement_ended.emit()

# --------------------------------------------------------- build radius

## Union of every owned building's influence. A structure is placeable if
## its centre falls inside any of them.
static func in_build_radius(tree: SceneTree, point: Vector3, is_player: bool) -> bool:
	var group: String = "player_buildings" if is_player else "enemy_buildings"
	for building in tree.get_nodes_in_group(group):
		if not is_instance_valid(building) or building.stats == null:
			continue
		if point.distance_to(building.global_position) <= building.stats.build_radius_bonus:
			return true
	return false

func _build_radius_ring() -> void:
	_radius_ring = MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for building in get_tree().get_nodes_in_group("player_buildings"):
		if not is_instance_valid(building) or building.stats == null:
			continue
		_add_ring(mesh, building.global_position, building.stats.build_radius_bonus)
	mesh.surface_end()
	_radius_ring.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.75, 1.0, 0.5)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = false
	_radius_ring.material_override = material
	add_child(_radius_ring)

func _add_ring(mesh: ImmediateMesh, centre: Vector3, radius: float) -> void:
	var segments: int = 40
	var previous := centre + Vector3(radius, 0.3, 0)
	for i in range(1, segments + 1):
		var angle: float = TAU * float(i) / float(segments)
		var point := centre + Vector3(cos(angle) * radius, 0.3, sin(angle) * radius)
		mesh.surface_add_vertex(previous)
		mesh.surface_add_vertex(point)
		previous = point

# --------------------------------------------------------------- ghost

func _build_ghost() -> void:
	_ghost = _make_ghost_mesh()
	add_child(_ghost)
	_ghost_material = _ghost.material_override

func _make_ghost_mesh() -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = active_stats.body_size
	instance.mesh = mesh
	instance.visible = false
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = VALID_COLOR
	instance.material_override = material
	return instance

func _clear_wall_ghosts() -> void:
	for ghost in _wall_ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	_wall_ghosts.clear()

# --------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pointer_pos = (event as InputEventMouseMotion).position
	elif event is InputEventScreenDrag:
		_pointer_pos = (event as InputEventScreenDrag).position
	elif event is InputEventScreenTouch:
		_pointer_pos = (event as InputEventScreenTouch).position

func _unhandled_input(event: InputEvent) -> void:
	if active_stats == null:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin_action()
			else:
				_finish_action()
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			_begin_action()
		else:
			_finish_action()
		get_viewport().set_input_as_handled()

func _begin_action() -> void:
	if active_stats.is_wall:
		_wall_anchor = _raycast_ground(_pointer_pos)

func _finish_action() -> void:
	if active_stats.is_wall and _wall_anchor != null:
		_commit_wall_line()
		return
	_try_confirm()

# ------------------------------------------------------------- preview

func _process(_delta: float) -> void:
	if active_stats == null or _ghost == null:
		return
	var hit_pos: Variant = _raycast_ground(_pointer_pos)
	if hit_pos == null:
		_ghost.visible = false
		_valid = false
		return

	if active_stats.is_wall and _wall_anchor != null:
		_ghost.visible = false
		_preview_wall_line(_wall_anchor, hit_pos)
		return

	_ghost.visible = true
	_ghost.global_position = Vector3(hit_pos.x, active_stats.body_size.y / 2.0, hit_pos.z)
	_valid = _check_validity(hit_pos)
	_ghost_material.albedo_color = VALID_COLOR if _valid else INVALID_COLOR

## Segment positions along the drag, one per footprint width.
func _wall_points(from: Vector3, to: Vector3) -> Array:
	var step: float = maxf(active_stats.footprint.x, 1.0)
	var delta := to - from
	delta.y = 0.0
	var count: int = clampi(int(delta.length() / step), 0, MAX_WALL_SEGMENTS)
	var points: Array = []
	for i in count + 1:
		points.append(from + delta.normalized() * step * float(i))
	return points

func _preview_wall_line(from: Vector3, to: Vector3) -> void:
	var points := _wall_points(from, to)
	while _wall_ghosts.size() < points.size():
		var ghost := _make_ghost_mesh()
		add_child(ghost)
		_wall_ghosts.append(ghost)
	for i in _wall_ghosts.size():
		var ghost: MeshInstance3D = _wall_ghosts[i]
		if i >= points.size():
			ghost.visible = false
			continue
		var point: Vector3 = points[i]
		ghost.visible = true
		ghost.global_position = Vector3(point.x, active_stats.body_size.y / 2.0, point.z)
		var material := ghost.material_override as StandardMaterial3D
		material.albedo_color = VALID_COLOR if _check_validity(point) else INVALID_COLOR

func _commit_wall_line() -> void:
	var hit_pos: Variant = _raycast_ground(_pointer_pos)
	var points := _wall_points(_wall_anchor, hit_pos) if hit_pos != null else [_wall_anchor]
	_wall_anchor = null
	_clear_wall_ghosts()
	for point in points:
		if not _check_validity(point):
			continue
		if GameState.credits < active_stats.cost:
			break
		GameState.try_spend_for(true, active_stats.cost)
		_spawn(point)
	## Walls stay armed so a player can keep laying line after line.

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
	if not in_build_radius(get_tree(), pos, true):
		return false

	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or building.stats == null:
			continue
		var other_pos: Vector3 = building.global_position
		var other_fp: Vector2 = building.stats.footprint
		if abs(pos.x - other_pos.x) < (footprint.x + other_fp.x) / 2.0 \
			and abs(pos.z - other_pos.z) < (footprint.y + other_fp.y) / 2.0:
			return false

	## Terrain blockers are solid ground the player cannot build on.
	for blocker in get_tree().get_nodes_in_group("terrain_blockers"):
		if not is_instance_valid(blocker):
			continue
		var shape := blocker.get_node_or_null("CollisionShape3D")
		var extent: Vector3 = (shape.shape as BoxShape3D).size if shape != null else Vector3(6, 6, 6)
		if abs(pos.x - blocker.global_position.x) < (footprint.x + extent.x) / 2.0 \
			and abs(pos.z - blocker.global_position.z) < (footprint.y + extent.z) / 2.0:
			return false
	return true

func _try_confirm() -> void:
	if active_stats == null:
		return
	var hit_pos: Variant = _raycast_ground(_pointer_pos)
	if hit_pos == null or not _check_validity(hit_pos):
		return

	## Walls are paid for at placement; everything else was already paid
	## for when its construction order started.
	if active_stats.is_wall:
		if not GameState.try_spend_for(true, active_stats.cost):
			return
	elif construction_queue != null:
		if not construction_queue.is_ready():
			return
		construction_queue.consume()

	_spawn(hit_pos)
	if not active_stats.is_wall:
		cancel_placement()

func _spawn(hit_pos: Vector3) -> void:
	var building = active_stats.scene.instantiate()
	building.stats = active_stats
	building.is_player_faction = true
	get_tree().current_scene.get_node("Level/NavRegion").add_child(building)
	building.global_position = Vector3(hit_pos.x, 0, hit_pos.z)
	EventBus.building_placed.emit(building)
