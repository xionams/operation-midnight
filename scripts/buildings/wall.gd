extends BuildingBase
class_name Wall

## A connectable wall segment.
##
## Walls live on a fixed grid (one segment per GRID-metre cell) and each
## segment knows which of its four neighbours are also walls of the same
## side - its `connections` mask of NORTH / EAST / SOUTH / WEST. From that
## mask it builds its own look AND its own collision out of the same few
## parts, so the two always agree:
##
##   hub   a post in the middle of the cell
##   arm   hub to the cell edge, towards each connected neighbour
##
## Neighbouring arms meet exactly on the shared cell edge, so a line of
## segments is one unbroken barrier in any direction, and corners,
## T-junctions, crossings and line ends all come out of the same rule -
## there is one scene for every state rather than a scene per shape.
## Straight runs and line ends (E-W or N-S) use the whole slab model,
## just rotated for N-S, which is what the unconnected wall has always
## looked like.
##
## (Before this, every segment was the same unrotated E-W slab: a north-
## south line read as a row of separate blocks with gaps between them,
## corners had nothing at the join, and placement was not snapped, so two
## drags never met cleanly.)
##
## Gate extends this, so walls and gates connect to each other.

const NORTH: int = 1 ## -Z
const EAST: int = 2  ## +X
const SOUTH: int = 4 ## +Z
const WEST: int = 8  ## -X

## Metres per cell. Matches the wall footprint.
const GRID: float = 2.0
## Thickness of the barrier across its run. Matches the slab model.
const THICKNESS: float = 1.1

const DIRECTIONS: Dictionary = {
	NORTH: Vector2i(0, -1), EAST: Vector2i(1, 0),
	SOUTH: Vector2i(0, 1), WEST: Vector2i(-1, 0),
}
const OPPOSITE: Dictionary = { NORTH: SOUTH, EAST: WEST, SOUTH: NORTH, WEST: EAST }

## Every wall-family segment in the world, by cell. One per cell: the
## placer's footprint overlap check already guarantees that.
static var _cells: Dictionary = {}

var connections: int = 0
var cell: Vector2i = Vector2i.ZERO
var _registered: bool = false
var _visual_container: Node3D = null

# ------------------------------------------------------------ grid

## Centre of the grid cell containing `point`.
static func snap(point: Vector3) -> Vector3:
	var c := cell_of(point)
	return Vector3((float(c.x) + 0.5) * GRID, point.y, (float(c.y) + 0.5) * GRID)

static func cell_of(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / GRID), floori(point.z / GRID))

## Cells from `a` to `b` as a 4-connected run: straight along an axis,
## or a staircase for a diagonal drag, so every consecutive pair shares an
## edge and the line has no corner-only contacts to leak through.
static func line_cells(a: Vector3, b: Vector3, max_cells: int) -> Array:
	var from := cell_of(a)
	var to := cell_of(b)
	var cells: Array = [from]
	var current := from
	var dx: int = absi(to.x - from.x)
	var dz: int = absi(to.y - from.y)
	var sx: int = signi(to.x - from.x)
	var sz: int = signi(to.y - from.y)
	var err: int = dx - dz
	while current != to and cells.size() < max_cells:
		## Step along whichever axis keeps the run closest to the drag.
		if err * 2 > -dz and current.x != to.x:
			err -= dz
			current.x += sx
		else:
			err += dx
			current.y += sz
		cells.append(current)
	return cells

static func cell_centre(c: Vector2i) -> Vector3:
	return Vector3((float(c.x) + 0.5) * GRID, 0.0, (float(c.y) + 0.5) * GRID)

static func at_cell(c: Vector2i) -> Wall:
	var w = _cells.get(c, null)
	return w if is_instance_valid(w) else null

# ------------------------------------------------------ lifecycle

func _ready() -> void:
	super._ready()
	add_to_group("walls")
	## Spawners add the node and THEN position it, so the cell is only
	## known once this frame's placement code has run.
	_join_grid.call_deferred()

func _exit_tree() -> void:
	_leave_grid()

func _join_grid() -> void:
	if not is_inside_tree() or _registered:
		return
	cell = cell_of(global_position)
	var occupant := at_cell(cell)
	if occupant != null and occupant != self:
		## Should not happen through the placer; keep the older one's slot.
		return
	_cells[cell] = self
	_registered = true
	refresh_connections()
	_refresh_neighbours()

func _leave_grid() -> void:
	if not _registered:
		return
	_registered = false
	if _cells.get(cell) == self:
		_cells.erase(cell)
	_refresh_neighbours()

func _refresh_neighbours() -> void:
	for dir in DIRECTIONS:
		var n := at_cell(cell + DIRECTIONS[dir])
		if n != null and n != self:
			n.refresh_connections()

## Walls join walls of the same side. An enemy segment built against
## yours is a separate barrier, not part of your perimeter.
func connects_to(other: Wall) -> bool:
	return other != null and other != self and other._registered \
		and other.is_neutral == is_neutral and other.is_player_faction == is_player_faction

func refresh_connections() -> void:
	var mask: int = 0
	if _registered:
		for dir in DIRECTIONS:
			if connects_to(at_cell(cell + DIRECTIONS[dir])):
				mask |= dir
	if mask == connections and _visual_container != null and _visual_container.get_child_count() > 0:
		return
	connections = mask
	_rebuild_shape()
	_on_connections_changed()

## Capture changes which segments count as ours.
func _on_faction_changed() -> void:
	refresh_connections()
	_refresh_neighbours()

## Gate hooks in here to re-orient itself.
func _on_connections_changed() -> void:
	pass

# ------------------------------------------------------ shape

## One box per part, in the wall's local space: [centre, size].
func _parts() -> Array:
	var h: float = stats.body_size.y if stats else 3.0
	## Straight runs, line ends and a lone segment are one full slab, so a
	## line finishes flush at its last cell rather than on a stub.
	var run_ew: bool = connections in [0, EAST, WEST, EAST | WEST]
	var run_ns: bool = connections in [NORTH, SOUTH, NORTH | SOUTH]
	if run_ew:
		return [[Vector3(0, h * 0.5, 0), Vector3(GRID, h, THICKNESS)]]
	if run_ns:
		return [[Vector3(0, h * 0.5, 0), Vector3(THICKNESS, h, GRID)]]
	var parts: Array = [[Vector3(0, h * 0.5, 0), Vector3(THICKNESS, h, THICKNESS)]]
	var half: float = GRID * 0.5
	for dir in DIRECTIONS:
		if not (connections & dir):
			continue
		var d: Vector2i = DIRECTIONS[dir]
		var centre := Vector3(d.x * half * 0.5, h * 0.5, d.y * half * 0.5)
		var size := Vector3(half if d.x != 0 else THICKNESS, h, half if d.y != 0 else THICKNESS)
		parts.append([centre, size])
	return parts

## Collision and visual are both rebuilt from _parts(), so what you see
## is exactly what blocks - including what the navmesh bakes around.
func _rebuild_shape() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			remove_child(child)
			child.queue_free()
	for part in _parts():
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = part[1]
		shape.shape = box
		shape.position = part[0]
		add_child(shape)
	_rebuild_visual()

## BuildingBase would build one full-cell box; the wall builds its parts
## once it knows its neighbours (see _rebuild_shape).
func _build_collision() -> void:
	pass

func _build_visual() -> void:
	_visual_container = Node3D.new()
	_visual_container.name = "WallVisual"
	add_child(_visual_container)
	_visual_root = _visual_container

## The slab model is 2m along X and THICKNESS deep; every part is that
## model scaled into the part's box, so the art stays the same concrete.
func _rebuild_visual() -> void:
	if _visual_container == null:
		return
	for child in _visual_container.get_children():
		_visual_container.remove_child(child)
		child.queue_free()
	var model: PackedScene = stats.visual_scene if stats and OS.get_environment("OM_NO_MODELS").is_empty() else null
	for part in _parts():
		var centre: Vector3 = part[0]
		var size: Vector3 = part[1]
		var piece: Node3D
		if model != null:
			piece = model.instantiate()
		else:
			var mesh_instance := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(GRID, stats.body_size.y if stats else 3.0, THICKNESS)
			mesh_instance.mesh = mesh
			mesh_instance.position.y = mesh.size.y * 0.5
			var material := StandardMaterial3D.new()
			material.albedo_color = stats.body_color if stats else Color.GRAY
			mesh_instance.material_override = material
			piece = Node3D.new()
			piece.add_child(mesh_instance)
		## Long axis along Z for N-S parts: rotate rather than stretch.
		var along_z: bool = size.z > size.x + 0.01
		var length: float = size.z if along_z else size.x
		var depth: float = size.x if along_z else size.z
		piece.rotation.y = PI * 0.5 if along_z else 0.0
		piece.scale = Vector3(length / GRID, 1.0, depth / THICKNESS)
		piece.position = Vector3(centre.x, 0.0, centre.z)
		_visual_container.add_child(piece)
	FactionPaint.apply(_visual_container, _faction_color())
