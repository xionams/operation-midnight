class_name GroundMarks
extends MultiMeshInstance3D

## Scorch marks the battlefield keeps.
##
## Everything the VFX layer does is momentary - a flash, a plume, a shake -
## so ten minutes into a match the ground looked exactly as it did at the
## start. A war game whose terrain never records that anything happened
## reads as a diorama, and that was true here however well it was lit.
##
## One MultiMesh for every mark on the map, so the whole record costs one
## draw call rather than one per crater. Marks never fade: the point is
## that the ground remembers, and a burn that cleans itself up after
## fifteen seconds is just another particle effect. Instead the buffer is
## a ring - the oldest mark is overwritten once the cap is reached, which
## bounds the cost exactly while keeping the places that saw the most
## fighting the most marked.

const MARK: Texture2D = preload("res://assets/textures/scorch.png")
const SHADER: Shader = preload("res://shaders/ground_decal.gdshader")

## 96 marks at one draw call. Enough that a contested crossroads looks
## fought over, few enough that a long match cannot fill the map with soot.
const MAX_MARKS: int = 96

## Just clear of the ground plane. The shader never writes depth, so this
## only has to beat the depth test, not z-fighting.
const HEIGHT: float = 0.03

static var _instance: GroundMarks = null

var _next: int = 0
var _used: int = 0

static func _root(context: Node) -> Node:
	var tree := context.get_tree() if context != null else null
	return tree.current_scene if tree != null else null

## Lazily built, and re-built whenever the scene changes - a resumed or
## restarted match must not inherit the previous match's craters.
static func _marks(context: Node) -> GroundMarks:
	if _instance != null and is_instance_valid(_instance) \
		and _instance.is_inside_tree():
		return _instance
	var root := _root(context)
	if root == null:
		return null
	_instance = GroundMarks.new()
	_instance.name = "GroundMarks"
	root.add_child(_instance)
	return _instance

func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE

	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("mark_tex", MARK)
	material.set_shader_parameter("fog_tex", FogOfWar.get_texture())
	material.set_shader_parameter("map_size", _map_size())
	material_override = material

	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = quad
	multi.instance_count = MAX_MARKS
	## Every slot starts collapsed to nothing. MultiMesh has no notion of
	## an unused instance, so an untouched slot would otherwise draw a
	## full-size quad at the origin.
	for i in MAX_MARKS:
		multi.set_instance_transform(i, Transform3D().scaled(Vector3.ZERO))
	multimesh = multi

	## The marks lie flat on a 220m plane; without an explicit AABB Godot
	## derives one from the quad mesh and culls the lot the moment the
	## origin leaves the frustum.
	var extent: float = _map_size()
	custom_aabb = AABB(Vector3(-extent, -1.0, -extent),
		Vector3(extent * 2.0, 2.0, extent * 2.0))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _map_size() -> float:
	var main := get_parent()
	if main != null and "map_size" in main:
		return float(main.map_size)
	return 220.0

## Reads OM_NO_VFX directly rather than through VFX.enabled. VFX calls
## into here, so depending on it back would be a cycle, and GDScript
## resolves a circular class_name reference by failing to compile both.
static var enabled: bool = OS.get_environment("OM_NO_VFX").is_empty()

## Burn the ground at `position`. `radius` is the mark's radius in metres.
static func scorch(context: Node, position: Vector3, radius: float) -> void:
	if not enabled:
		return
	var marks := _marks(context)
	if marks == null:
		return
	marks._add(position, radius)

func _add(position: Vector3, radius: float) -> void:
	## Random spin per mark. Without it every burn is the same texture in
	## the same orientation, and a cluster of them reads as a repeated
	## stamp rather than as separate craters.
	var basis := Basis(Vector3.UP, randf_range(0.0, TAU)) \
		* Basis(Vector3.RIGHT, -PI / 2.0)
	var size: float = radius * 2.0 * randf_range(0.85, 1.2)
	multimesh.set_instance_transform(_next, Transform3D(
		basis.scaled(Vector3(size, size, size)),
		Vector3(position.x, HEIGHT, position.z)))
	_next = (_next + 1) % MAX_MARKS
	_used = mini(_used + 1, MAX_MARKS)

## How many marks are currently on the map. Used by the art pass test.
static func count() -> int:
	if _instance == null or not is_instance_valid(_instance):
		return 0
	return _instance._used
