extends MeshInstance3D
class_name OrderLines

## Thin lines from each selected unit to what it is doing: green to where
## it is going, red to what it is shooting at. Nothing for an idle unit.
##
## This is the cheapest possible answer to "is it moving, fighting or
## doing nothing?" - the question players kept having to answer by
## watching a unit for a second. Drawn only for the player's selection,
## so the battlefield stays clean.

const MOVE_COLOR := Color(0.35, 1.0, 0.45, 0.55)
const ATTACK_COLOR := Color(1.0, 0.3, 0.25, 0.75)
const LIFT := 0.35

var _mesh := ImmediateMesh.new()
var _count: int = 0

func _ready() -> void:
	name = "OrderLines"
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material_override = material

func _process(_delta: float) -> void:
	_mesh.clear_surfaces()
	_count = 0
	var segments: Array = []
	for unit in SelectionManager.selected_units:
		if not is_instance_valid(unit) or not unit.has_method("issue_command") \
			or not unit.is_inside_tree():
			continue
		var from: Vector3 = unit.global_position + Vector3.UP * LIFT
		var attacker = unit.get_node_or_null("AttackerComponent")
		if attacker != null and attacker.has_target():
			segments.append([from, attacker.target.global_position + Vector3.UP * LIFT, ATTACK_COLOR])
			continue
		var agent: NavigationAgent3D = unit.get("nav_agent")
		if agent != null and not agent.is_navigation_finished():
			var to: Vector3 = agent.target_position
			to.y = unit.global_position.y
			segments.append([from, to + Vector3.UP * LIFT, MOVE_COLOR])
	_count = segments.size()
	if segments.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for seg in segments:
		_mesh.surface_set_color(seg[2])
		_mesh.surface_add_vertex(seg[0])
		_mesh.surface_add_vertex(seg[1])
	_mesh.surface_end()

## Lines currently drawn, for tests.
func line_count() -> int:
	return _count
