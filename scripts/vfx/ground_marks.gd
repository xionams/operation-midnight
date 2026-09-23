class_name GroundMarks
extends Node3D

## What the battlefield keeps: burns where things exploded, and ruts
## where armour drove.
##
## Everything the VFX layer does is momentary - a flash, a plume, a shake -
## so ten minutes into a match the ground looked exactly as it did at the
## start. A war game whose terrain never records that anything happened
## reads as a diorama, however well it is lit.
##
## One MultiMesh per LAYER, so the whole record is two draw calls rather
## than one per crater and one per rut. Marks never fade: the point is
## that the ground remembers, and a mark that cleans itself up after
## fifteen seconds is just another particle effect. Instead each layer is
## a ring - the oldest entry is overwritten once its cap is reached, which
## bounds the cost exactly while keeping the ground that saw the most
## traffic the most marked.

const SHADER: Shader = preload("res://shaders/ground_decal.gdshader")

const SCORCH: String = "scorch"
const TRACK: String = "track"

## Caps are per layer because the two fill at completely different rates:
## a burn happens when something dies, a rut every metre and a half a
## vehicle drives. Sharing one buffer would let a single harvester's
## commute erase the record of a battle.
const LAYERS: Dictionary = {
	SCORCH: {
		"texture": preload("res://assets/textures/scorch.png"),
		"cap": 96,
		"height": 0.03,
	},
	TRACK: {
		"texture": preload("res://assets/textures/track.png"),
		## 160, not the 420 this started at. Every mark is a large
		## alpha-blended quad and the layer's AABB spans the map, so none
		## of them are ever culled - at 420 the ruts alone cost 10 FPS at
		## 120 units, which is more than shadows and more than the entire
		## effects layer. This is overdraw, so the population is the only
		## lever that matters.
		"cap": 160,
		## Below the scorch layer: a burn crossing a track should read as
		## having happened after the vehicle passed, which is the usual
		## order of events.
		"height": 0.02,
	},
}

static var _instance: GroundMarks = null

var _layers: Dictionary = {}
var _next: Dictionary = {}
var _used: Dictionary = {}

static func enabled() -> bool:
	## Read directly rather than through VFX.enabled: VFX calls into here,
	## and GDScript resolves a circular class_name reference by failing to
	## compile both sides.
	return OS.get_environment("OM_NO_VFX").is_empty()

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
	var extent: float = _map_size()

	for name in LAYERS:
		var config: Dictionary = LAYERS[name]
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("mark_tex", config["texture"])
		material.set_shader_parameter("fog_tex", FogOfWar.get_texture())
		material.set_shader_parameter("map_size", extent)

		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = quad
		multi.instance_count = config["cap"]
		## Every slot starts collapsed to nothing. MultiMesh has no notion
		## of an unused instance, so an untouched slot would otherwise draw
		## a full-size quad at the origin.
		for i in int(config["cap"]):
			multi.set_instance_transform(i, Transform3D().scaled(Vector3.ZERO))

		var node := MultiMeshInstance3D.new()
		node.name = name
		node.multimesh = multi
		node.material_override = material
		## Marks lie flat on a 220m plane; without an explicit AABB Godot
		## derives one from the quad mesh and culls the lot the moment the
		## origin leaves the frustum.
		node.custom_aabb = AABB(Vector3(-extent, -1.0, -extent),
			Vector3(extent * 2.0, 2.0, extent * 2.0))
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)

		_layers[name] = node
		_next[name] = 0
		_used[name] = 0

func _map_size() -> float:
	var main := get_parent()
	if main != null and "map_size" in main:
		return float(main.map_size)
	return 220.0

func _stamp(layer: String, transform: Transform3D) -> void:
	var node: MultiMeshInstance3D = _layers.get(layer)
	if node == null:
		return
	var cap: int = int(LAYERS[layer]["cap"])
	node.multimesh.set_instance_transform(_next[layer], transform)
	_next[layer] = (_next[layer] + 1) % cap
	_used[layer] = mini(_used[layer] + 1, cap)

## Burn the ground at `position`. `radius` is the mark's radius in metres.
static func scorch(context: Node, position: Vector3, radius: float) -> void:
	if not enabled():
		return
	var marks := _marks(context)
	if marks == null:
		return
	## Random spin. Without it every burn is the same texture in the same
	## orientation, and a cluster reads as a repeated stamp rather than as
	## separate craters.
	var basis := Basis(Vector3.UP, randf_range(0.0, TAU)) \
		* Basis(Vector3.RIGHT, -PI / 2.0)
	var size: float = radius * 2.0 * randf_range(0.85, 1.2)
	marks._stamp(SCORCH, Transform3D(
		basis * Basis.from_scale(Vector3(size, size, size)),
		Vector3(position.x, LAYERS[SCORCH]["height"], position.z)))

## Lay one stamp of ruts at `position`, running along `forward`.
static func track(context: Node, position: Vector3, forward: Vector3,
		width: float, length: float) -> void:
	if not enabled():
		return
	var marks := _marks(context)
	if marks == null:
		return
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() < 0.0001:
		return
	flat = flat.normalized()
	## The texture is authored with +Y as the direction of travel. After
	## the -90 degree X rotation that lays the quad flat, its local +Y
	## points along world -Z, so this yaw turns -Z onto `flat`.
	var yaw: float = atan2(-flat.x, -flat.z)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI / 2.0)
	## Basis.scaled() scales the basis ROWS, which is a scale in WORLD
	## axes, not local ones. Used here it made every rut `width` across
	## world X and 1.0 deep in world Z whatever direction it ran - thin
	## slivers, which is why the first trail was barely visible. Composing
	## with from_scale on the right scales in the quad's own frame.
	## The scorch layer never showed this because its scale is uniform.
	marks._stamp(TRACK, Transform3D(
		basis * Basis.from_scale(Vector3(width, length, 1.0)),
		Vector3(position.x, LAYERS[TRACK]["height"], position.z)))

## How many marks of a layer are on the map. Used by the art pass tests.
static func count(layer: String = SCORCH) -> int:
	if _instance == null or not is_instance_valid(_instance):
		return 0
	return int(_instance._used.get(layer, 0))

static func cap(layer: String = SCORCH) -> int:
	return int(LAYERS[layer]["cap"])
