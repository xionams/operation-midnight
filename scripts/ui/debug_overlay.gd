extends Node3D
class_name DebugOverlay

## World-space debug drawing, toggled with the HUD's Debug button (F3).
## Everything here is rebuilt only while visible, so it costs nothing when
## switched off.
##
## Shows:
##   - vision radius rings on friendly units and structures
##   - the navigation destination of each selected unit
##   - fog cell state sampled on a coarse lattice

const RING_SEGMENTS: int = 32
const FOG_SAMPLE_STEP: int = 6

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _enabled: bool = false

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_mesh.material_override = _material
	add_child(_mesh)
	visible = false

func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	visible = enabled

func _process(_delta: float) -> void:
	if not _enabled:
		return
	_redraw()

func _redraw() -> void:
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)

	for entity in get_tree().get_nodes_in_group("player_units"):
		_draw_vision(immediate, entity, Color(0.3, 0.8, 1.0, 0.55))
	for entity in get_tree().get_nodes_in_group("player_buildings"):
		_draw_vision(immediate, entity, Color(0.4, 1.0, 0.6, 0.45))

	for unit in SelectionManager.selected_units:
		if not is_instance_valid(unit) or unit.nav_agent == null:
			continue
		_line(immediate, unit.global_position + Vector3.UP,
			unit.nav_agent.target_position + Vector3.UP, Color(1.0, 0.9, 0.2, 0.9))

	_draw_fog_lattice(immediate)

	immediate.surface_end()
	_mesh.mesh = immediate

func _draw_vision(immediate: ImmediateMesh, entity: Node, color: Color) -> void:
	if not is_instance_valid(entity) or entity.stats == null:
		return
	_ring(immediate, entity.global_position, entity.stats.vision_range, color)

func _ring(immediate: ImmediateMesh, centre: Vector3, radius: float, color: Color) -> void:
	var previous := centre + Vector3(radius, 0.4, 0)
	for i in range(1, RING_SEGMENTS + 1):
		var angle: float = TAU * float(i) / float(RING_SEGMENTS)
		var point := centre + Vector3(cos(angle) * radius, 0.4, sin(angle) * radius)
		_line(immediate, previous, point, color)
		previous = point

## Fog state on a sparse lattice - drawing all 12,100 cells would be
## unreadable as well as slow, and every Nth cell conveys the same thing.
func _draw_fog_lattice(immediate: ImmediateMesh) -> void:
	var side: int = FogOfWar.get_side()
	var half: float = FogOfWar.get_map_size() * 0.5
	var cell: float = FogOfWar.CELL_SIZE
	var x: int = 0
	while x < side:
		var y: int = 0
		while y < side:
			var colour: Color
			if FogOfWar.is_cell_visible(x, y):
				colour = Color(0.2, 1.0, 0.3, 0.5)
			elif FogOfWar.is_cell_explored(x, y):
				colour = Color(0.9, 0.75, 0.2, 0.35)
			else:
				colour = Color(1.0, 0.2, 0.2, 0.18)
			var centre := Vector3(x * cell - half + cell * 0.5, 0.3, y * cell - half + cell * 0.5)
			_line(immediate, centre + Vector3(-0.4, 0, 0), centre + Vector3(0.4, 0, 0), colour)
			y += FOG_SAMPLE_STEP
		x += FOG_SAMPLE_STEP

func _line(immediate: ImmediateMesh, from: Vector3, to: Vector3, color: Color) -> void:
	immediate.surface_set_color(color)
	immediate.surface_add_vertex(from)
	immediate.surface_set_color(color)
	immediate.surface_add_vertex(to)
